-- twitch_chat/main.lua
-- Live Twitch chat overlay inside mpv, WITH emotes (7TV / BTTV / FFZ / native).
--
-- Detects the Twitch channel from the playing URL, spawns chat_render.py
-- (bundled portable python + Pillow). That helper reads chat over anonymous
-- IRC, composites the visible chat block -- anu-styled text with inline emote
-- images -- into a raw BGRA frame, and this script blits it with `overlay-add`.
--
-- Bindings (bind keys in input.conf or use the uosc menu):
--   script-binding twitch_chat/toggle      -- show/hide chat for the current stream
--   script-binding twitch_chat/reload      -- force reconnect
--   script-binding twitch_chat/cycle-side  -- move overlay left <-> right
-- Script message:
--   script-message twitch-chat-channel <name>   -- force a specific channel

local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'
local msg = require 'mp.msg'

local opts = {
    enabled = false,      -- auto-show chat when a stream loads
    channel = "",         -- force a channel (blank = auto-detect from the URL)
    platform = "",        -- with a forced channel: "twitch" or "kick" (blank=twitch)
    position = "right",   -- "right" or "left"
    margin = 24,          -- gap from the screen edge (screen px)
    emotes = true,        -- render 3rd-party emotes (7TV/BTTV/FFZ); native always on

    -- render settings (passed to the python renderer via opts.json)
    width = 420,          -- chat column width in px
    font_px = 20,         -- text size in px
    emote_scale = 1.8,    -- emote height = font_px * this (bigger emotes vs text)
    height_frac = 1.0,    -- column height as a fraction of the player height (1.0 = full)
    line_ratio = 1.5,     -- line-height = font_px * this
    outline = 0,          -- black outline thickness px (0 = auto, scales with font)
    max_messages = 60,    -- message buffer; column shows as many as fit
    pad = 8,              -- inner padding
    supersample = 2,      -- text render scale for crisp outlines
    anim_fps = 12,        -- animated-emote frame rate
    bg_opacity = 0.0,     -- 0 = fully transparent (OLED-safe, like anu idle)
    font_regular = "C:/Windows/Fonts/segoeui.ttf",
    font_bold = "C:/Windows/Fonts/seguisb.ttf",

    python = "",          -- path to python.exe (blank = auto-find bundled one)
}
options.read_options(opts, "twitch_chat")

local OVERLAY_ID = 63   -- mpv overlay-add ids must be 0..63 (thumbfast uses 42)
local SCRIPT_DIR = mp.get_script_directory()
    or mp.command_native({ "expand-path", "~~/scripts/twitch_chat" })
local CONF_PATH = mp.command_native({ "expand-path", "~~/script-opts/twitch_chat.conf" })

-- kick.com/<slug> paths that aren't channels
local KICK_NONCHAN = {
    browse = true, categories = true, following = true, search = true, category = true,
    clips = true, videos = true, dashboard = true, settings = true, subscriptions = true,
    messages = true, wallet = true, ["video"] = true,
}

local proc = nil          -- abort handle from command_native_async
local workdir = nil
local opts_file = nil
local read_timer = nil
local active = false
local cur_channel = nil
local cur_platform = "twitch"
local show = opts.enabled   -- chat currently visible
local auto = opts.enabled   -- auto-show on every new stream

local last_counter = -1
local last_x, last_y = nil, nil
local last_sent_h = nil
local last_push_t = 0

-- ---------- helpers ----------

local function file_exists(p)
    if not p or p == "" then return false end
    local info = utils.file_info(p)
    return info and info.is_file
end

local function find_python()
    if opts.python ~= "" then return opts.python end
    -- chat_render needs a normal console-less python that has Pillow; the
    -- bundled pythonw.exe sits next to mpv.exe and shares its site-packages.
    for _, rel in ipairs({ "~~/../pythonw.exe", "~~/../python.exe" }) do
        local p = mp.command_native({ "expand-path", rel })
        if file_exists(p) then return p end
    end
    return "pythonw"
end

-- returns channel, platform  (platform = "twitch" | "kick"), or nil
local function detect_channel()
    if opts.channel ~= "" then
        local p = (opts.platform ~= "" and opts.platform:lower()) or "twitch"
        return opts.channel:lower():gsub("^#", ""), p
    end
    for _, prop in ipairs({ "path", "stream-open-filename", "filename", "media-title" }) do
        local v = mp.get_property(prop)
        if v then
            local c = v:match("twitch%.tv/([%w_]+)")
            if c and c ~= "videos" and c ~= "directory" then
                return c:lower(), "twitch"
            end
            local k = v:match("kick%.com/([%w_]+)")
            if k and not KICK_NONCHAN[k:lower()] then
                return k:lower(), "kick"
            end
        end
    end
    local blob = (mp.get_property("path") or "") .. " " ..
                 (mp.get_property("stream-open-filename") or "")
    if blob:find("ttvnw%.net") or blob:lower():find("twitch") then
        for _, k in ipairs({ "uploader", "Uploader", "uploader_id", "channel" }) do
            local up = mp.get_property("metadata/by-key/" .. k)
            if up and up:match("^[%w_]+$") then return up:lower(), "twitch" end
        end
    end
    return nil
end

-- ---------- options file (read live by the python helper) ----------

local function target_height()
    local oh = mp.get_property_number("osd-height", 0)
    if oh <= 0 or opts.height_frac <= 0 then return 0 end
    return math.max(60, math.floor((oh - opts.margin * 2) * opts.height_frac))
end

local function write_opts_json(path)
    local o = {
        platform = cur_platform,
        width = opts.width,
        font_px = opts.font_px,
        emote_scale = opts.emote_scale,
        height = target_height(),
        max_msgs = opts.max_messages,
        line_ratio = opts.line_ratio,
        outline = opts.outline,
        pad = opts.pad,
        supersample = opts.supersample,
        anim_fps = opts.anim_fps,
        bg_opacity = opts.bg_opacity,
        emotes_3rd_party = opts.emotes and true or false,
        font_regular = opts.font_regular,
        font_bold = opts.font_bold,
    }
    local f = io.open(path, "w")
    if f then f:write(utils.format_json(o)); f:close() end
end

-- rewrite the options file live; the python helper re-reads it (no reconnect)
local function push_opts()
    if active and opts_file then
        write_opts_json(opts_file)
        last_sent_h = target_height()
        last_push_t = mp.get_time()
    end
end

-- persist a setting into script-opts/twitch_chat.conf so it survives restarts
local function persist(key, value)
    if not CONF_PATH then return end
    local lines, found = {}, false
    local f = io.open(CONF_PATH, "r")
    if f then
        for l in f:lines() do lines[#lines + 1] = l end
        f:close()
    end
    for i, l in ipairs(lines) do
        if l:match("^%s*" .. key .. "%s*=") then
            lines[i] = key .. "=" .. value
            found = true
            break
        end
    end
    if not found then lines[#lines + 1] = key .. "=" .. value end
    local w = io.open(CONF_PATH, "w")
    if w then w:write(table.concat(lines, "\n") .. "\n"); w:close() end
end

-- ---------- overlay blitting ----------

local function remove_overlay()
    mp.command_native_async({ name = "overlay-remove", id = OVERLAY_ID }, function() end)
    last_counter = -1
    last_x, last_y = nil, nil
end

local function read_meta()
    if not workdir then return nil end
    local f = io.open(workdir .. "/meta.json", "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    if not s or s == "" then return nil end
    return utils.parse_json(s)
end

local function tick()
    if not active or not workdir then return end
    local meta = read_meta()
    if not meta or not meta.w then return end

    local ow = mp.get_property_number("osd-width", 0)
    local oh = mp.get_property_number("osd-height", 0)
    if ow == 0 or oh == 0 then return end

    -- keep the column height synced with window / fullscreen changes
    local th = target_height()
    if th > 0 and (last_sent_h == nil or math.abs(th - last_sent_h) > 8)
       and (mp.get_time() - last_push_t) > 0.4 then
        push_opts()
    end

    local w, h = meta.w, meta.h
    local m = opts.margin
    local x = (opts.position == "left") and m or (ow - w - m)
    local y = oh - h - m
    if x < 0 then x = 0 end
    if y < 0 then y = 0 end

    if meta.counter == last_counter and x == last_x and y == last_y then
        return
    end
    last_counter, last_x, last_y = meta.counter, x, y

    mp.command_native_async({
        name = "overlay-add", id = OVERLAY_ID, x = x, y = y,
        file = workdir .. "/" .. meta.file, offset = 0, fmt = "bgra",
        w = w, h = h, stride = w * 4,
    }, function() end)
end

-- ---------- lifecycle ----------

local function stop()
    active = false
    cur_channel = nil
    if proc then
        mp.abort_async_command(proc)
        proc = nil
    end
    if read_timer then read_timer:kill(); read_timer = nil end
    remove_overlay()
    if opts_file then os.remove(opts_file); opts_file = nil end
    workdir = nil
end

local function start(channel, platform)
    platform = platform or "twitch"
    if active and cur_channel == channel and cur_platform == platform then return end
    stop()

    active = true
    cur_channel = channel
    cur_platform = platform
    local tmp = os.getenv("TEMP") or os.getenv("TMP") or "."
    local base = "mpv_twitch_chat_" .. utils.getpid() .. "_" .. os.time()
    workdir = tmp .. "/" .. base        -- created by the python helper
    opts_file = tmp .. "/" .. base .. "_opts.json"
    write_opts_json(opts_file)

    local py = find_python()
    local script = SCRIPT_DIR .. "/chat_render.py"
    proc = mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        capture_stdout = false,
        capture_stderr = false,
        args = { py, script, channel, workdir, tostring(utils.getpid()), opts_file },
    }, function() end)

    read_timer = mp.add_periodic_timer(0.066, tick)   -- ~15fps for smooth animation
    last_sent_h = nil
    local label = (platform == "kick") and "Kick" or "Twitch"
    mp.osd_message(label .. " chat: " .. channel, 2)
end

-- Is what we're playing plausibly a Twitch/Kick stream at all? This decides
-- whether a failed channel detection is worth reporting.
local function looks_like_stream()
    for _, prop in ipairs({ "path", "stream-open-filename", "filename", "media-title" }) do
        local v = mp.get_property(prop)
        if v then
            v = v:lower()
            if v:find("twitch%.tv") or v:find("kick%.com") or v:find("ttvnw%.net") then
                return true
            end
        end
    end
    return false
end

local function refresh()
    if auto then show = true end
    local ch, platform = detect_channel()
    if show and ch then
        start(ch, platform)
    else
        stop()
        -- Only complain when this really IS a Twitch/Kick stream whose channel we
        -- couldn't work out - that's a genuine problem worth surfacing.
        --
        -- Anything else has no channel to find and nothing to report. auto-show
        -- sets show=true for every file, so without this check the popup fired on
        -- ordinary videos: torrents, debrid links (torbox:// , real-debrid.com/d/)
        -- and local files, complaining it couldn't find a Twitch channel in
        -- something that was never a stream.
        if show and not ch and looks_like_stream() then
            local hint = (mp.get_property("path") or "?"):sub(1, 64)
            mp.osd_message("Live chat: no twitch.tv/kick.com channel detected from\n" .. hint ..
                "\n(set channel= in twitch_chat.conf, or script-message twitch-chat-channel <name>)", 5)
        end
    end
end


-- ---------- events & bindings ----------

mp.register_event("file-loaded", refresh)
mp.register_event("end-file", stop)
mp.register_event("shutdown", stop)

mp.add_key_binding(nil, "toggle", function()
    show = not show
    if show then
        refresh()
    else
        stop()
        mp.osd_message("Chat overlay: off", 1)
    end
end)

mp.add_key_binding(nil, "reload", function()
    if show then
        local ch, plat = detect_channel()
        if ch then cur_channel = nil; start(ch, plat) end
    end
end)

mp.add_key_binding(nil, "cycle-side", function()
    opts.position = (opts.position == "right") and "left" or "right"
    last_x = nil  -- force reposition on next tick
    mp.osd_message("Chat overlay: " .. opts.position, 1)
    persist("position", opts.position)
end)

mp.add_key_binding(nil, "toggle-autoshow", function()
    auto = not auto
    mp.osd_message("Chat auto-show: " .. (auto and "ON" or "off"), 2)
    persist("enabled", auto and "yes" or "no")
    if auto then show = true; refresh() end
end)

mp.add_key_binding(nil, "size-up", function()
    opts.font_px = math.min(64, opts.font_px + 2)
    mp.osd_message("Chat text size: " .. opts.font_px, 1)
    push_opts(); persist("font_px", tostring(opts.font_px))
end)

mp.add_key_binding(nil, "size-down", function()
    opts.font_px = math.max(8, opts.font_px - 2)
    mp.osd_message("Chat text size: " .. opts.font_px, 1)
    push_opts(); persist("font_px", tostring(opts.font_px))
end)

mp.add_key_binding(nil, "width-up", function()
    opts.width = math.min(900, opts.width + 30)
    mp.osd_message("Chat width: " .. opts.width, 1)
    push_opts(); persist("width", tostring(opts.width))
end)

mp.add_key_binding(nil, "width-down", function()
    opts.width = math.max(160, opts.width - 30)
    mp.osd_message("Chat width: " .. opts.width, 1)
    push_opts(); persist("width", tostring(opts.width))
end)

mp.add_key_binding(nil, "emote-up", function()
    opts.emote_scale = math.min(4.0, opts.emote_scale + 0.2)
    mp.osd_message(string.format("Chat emote size: %.1fx", opts.emote_scale), 1)
    push_opts(); persist("emote_scale", string.format("%.1f", opts.emote_scale))
end)

mp.add_key_binding(nil, "emote-down", function()
    opts.emote_scale = math.max(1.0, opts.emote_scale - 0.2)
    mp.osd_message(string.format("Chat emote size: %.1fx", opts.emote_scale), 1)
    push_opts(); persist("emote_scale", string.format("%.1f", opts.emote_scale))
end)

mp.add_key_binding(nil, "status", function()
    local ch, plat = detect_channel()
    local L = {}
    L[#L + 1] = "Chat overlay status"
    L[#L + 1] = "channel: " .. (ch or "NONE DETECTED") .. " (" .. (plat or "?") .. ")"
    L[#L + 1] = "show=" .. tostring(show) .. " auto=" .. tostring(auto) ..
                " active=" .. tostring(active)
    L[#L + 1] = "python: " .. find_python()
    if workdir then
        local meta = read_meta()
        L[#L + 1] = "frames: " .. (meta and ("yes, counter=" .. tostring(meta.counter))
                                        or "none yet")
        local ef = io.open(workdir .. "/error.log", "r")
        if ef then
            local e = ef:read("*a"); ef:close()
            L[#L + 1] = "PYTHON ERROR:\n" .. (e or ""):sub(1, 400)
        end
        local sf = io.open(workdir .. "/status.log", "r")
        if sf then local s = sf:read("*a"); sf:close(); L[#L + 1] = "py: " .. (s or ""):gsub("\n", " ") end
    else
        L[#L + 1] = "(helper not started)"
    end
    local report = table.concat(L, "\n")
    mp.osd_message(report, 10)
    msg.info("\n" .. report)
end)

mp.register_script_message("twitch-chat-channel", function(name)
    if name and name ~= "" then
        opts.channel = name
        show = true
        cur_channel = nil
        refresh()
    end
end)
