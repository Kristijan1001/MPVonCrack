-- Real-Debrid Magnet Streamer
-- VERSION: 2.1 - Reuses in-progress torrents by infohash (no duplicate re-adds)
--
-- Plays magnet links through Real-Debrid, mirroring the .torrent workflow.
-- Input methods:
--   1. Clipboard  : press Ctrl+Shift+M (or uosc menu "Paste & Play Magnet")
--   2. .magnet file: open a text file ending in .magnet holding one magnet per line
--   3. Direct URI : open mpv on a "magnet:?xt=..." path (e.g. from a browser handler)
--
-- Fully self-contained: uses its own "magnet-rd://" virtual scheme so it never
-- collides with the .torrent script's "real-debrid.com/d/" on_load hook.
--
-- v2.0: resolution runs in the BACKGROUND (mpv stays responsive). If a magnet
-- isn't cached on RD yet, RD downloads it first; we poll without blocking, show
-- live progress, and auto-play when links appear. We ONLY delete the torrent
-- from RD after successfully extracting links, or on a fatal error - never while
-- it is still downloading (that was the v1.0 bug that removed it mid-download).

local utils = require 'mp.utils'
local msg = require 'mp.msg'

-- ===== CONFIGURATION =====
-- Your Real-Debrid token is NOT stored in this file (so the script can be shared
-- without leaking it). Put it in:
--     portable_config/script-opts/realdebrid.conf   ->   api_key=YOUR_TOKEN
-- or set a REALDEBRID_API_KEY environment variable.
-- Grab a token from https://real-debrid.com/apitoken while logged in.
local function load_rd_api_key()
    local path = mp.command_native({"expand-path", "~~/script-opts/realdebrid.conf"})
    local f = io.open(path, "r")
    if f then
        for line in f:lines() do
            local k = line:match("^%s*api_key%s*=%s*(.-)%s*$")
            if k and k ~= "" and k ~= "YOUR_TOKEN_HERE" then
                f:close()
                return k
            end
        end
        f:close()
    end
    return os.getenv("REALDEBRID_API_KEY") or ""
end

local RD_API = load_rd_api_key()

if RD_API == "" then
    msg.error("No Real-Debrid token. Add 'api_key=...' to script-opts/realdebrid.conf")
    mp.add_timeout(1, function()
        mp.osd_message("Real-Debrid: no API token set\nAdd api_key=... to script-opts/realdebrid.conf", 6)
    end)
end

local EXTENSIONS = {
    -- Video Formats
    ".mp4", ".mkv", ".avi", ".mov", ".wmv", ".flv", ".webm", ".m4v",
    ".mpg", ".mpeg", ".m2ts", ".ts", ".mts", ".vob", ".ogv", ".3gp",
    ".3g2", ".asf", ".divx", ".m2t", ".f4v", ".rm", ".rmvb", ".dv",
    ".h264", ".h265", ".xvid",

    -- Audio Formats
    ".mp3", ".flac", ".wav", ".m4a", ".ogg", ".oga", ".opus"
}
local EXCLUDE_WORDS = {
    "trailer"
}

local API_BASE = "https://api.real-debrid.com/rest/1.0"
local AUTH = {Authorization = "Bearer " .. RD_API}

-- Background poll cadence (non-blocking). POLL_MAX * POLL_INTERVAL is how long we
-- keep watching a not-yet-cached torrent before backing off (it stays on RD).
local POLL_INTERVAL = 2     -- seconds between RD status checks
local POLL_MAX = 300        -- ~10 minutes of watching before we stop (but keep it on RD)

-- Permanent cache + temp session-playlist storage. Everything lives together in
-- portable_config/_cache/rdcache (shared with the .torrent RD script), not script-opts.
local function ensure_dir(dir)
    if utils.file_info and utils.file_info(dir) then return end
    utils.subprocess({
        args = {"powershell", "-NoProfile", "-NonInteractive", "-Command",
            "New-Item -ItemType Directory -Force -Path '" .. dir .. "' > $null"},
        cancellable = false, playback_only = false
    })
end

local CACHE_DIR = mp.command_native({"expand-path", "~~/_cache/rdcache"})
ensure_dir(CACHE_DIR)

local function get_cache_dir()
    return CACHE_DIR .. "/"
end

local CACHE_FILE = get_cache_dir() .. "magnet_rd_cache.json"

-- ===== STATE =====
local magnet_data = {
    all_torrents = {},       -- resolved torrents this session
    active = {},             -- infohash -> true while a resolver is running
    awaiting_first = false,  -- true until the first torrent of a request starts playing
    initial_target = nil
}
local tmp_counter = 0

-- ===== CACHE FUNCTIONS (keyed by infohash) =====

local function load_cache()
    local file = io.open(CACHE_FILE, "r")
    if not file then return {} end
    local content = file:read("*all")
    file:close()

    if content and content ~= "" then
        local cache = utils.parse_json(content)
        return cache or {}
    end
    return {}
end

local function save_cache(cache)
    local file = io.open(CACHE_FILE, "w")
    if not file then
        msg.warn("Failed to save cache to " .. CACHE_FILE)
        return false
    end
    file:write(utils.format_json(cache))
    file:close()
    return true
end

-- ===== HELPER FUNCTIONS =====

local function get_filename(path)
    return path:match("([^/\\]+)$") or path
end

local function trim(s)
    -- Wrap in parens: gsub returns (string, count); the parens discard the
    -- count so callers like table.insert(t, trim(x)) don't get a stray 2nd arg.
    return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function urlencode(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function urldecode(s)
    s = tostring(s):gsub("+", " ")
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

local function is_video(path)
    if not path then return false end
    local name = get_filename(path):lower()

    -- explicit excludes (user controlled)
    for _, w in ipairs(EXCLUDE_WORDS) do
        if name:match("%f[%a]" .. w .. "%f[%A]") then
            return false
        end
    end

    -- extension allow
    local ext = name:match("%.([^%.]+)$")
    if not ext then return false end
    ext = "." .. ext
    for _, v_ext in ipairs(EXTENSIONS) do
        if ext == v_ext then return true end
    end
    return false
end

local function natural_sort(a, b)
    local function padnum(n, d)
        return #d > 0 and ("%03d%s%.12f"):format(#n, n, tonumber(d) / (10 ^ #d))
                      or ("%03d%s"):format(#n, n)
    end
    local a_lower = (a.path or ""):lower():gsub("0*(%d+)%.?(%d*)", padnum)
    local b_lower = (b.path or ""):lower():gsub("0*(%d+)%.?(%d*)", padnum)
    return a_lower < b_lower
end

local function curl_request(url, method, data, headers)
    local args = {"curl", "-s", "-L", "-X", method or "GET"}
    if headers then
        for k, v in pairs(headers) do
            table.insert(args, "-H"); table.insert(args, k .. ": " .. v)
        end
    end
    if data then
        table.insert(args, "-d")
        table.insert(args, data)
    end
    table.insert(args, url)
    local res = utils.subprocess({args = args, cancellable = false, playback_only = false})
    return (res and res.status == 0) and res.stdout or nil
end

local function osd(text, secs)
    mp.osd_message("[Magnet] " .. text, secs or 3)
end

-- Read the Windows clipboard as raw text.
local function get_clipboard()
    local res = utils.subprocess({
        args = {"powershell", "-NoProfile", "-NonInteractive", "-Command", "Get-Clipboard -Raw"},
        cancellable = false, playback_only = false
    })
    if res and res.status == 0 and res.stdout then
        return res.stdout
    end
    return nil
end

local function mpv_idle()
    if mp.get_property_bool("idle-active", false) then return true end
    if (mp.get_property_number("playlist-count", 0) or 0) == 0 then return true end
    return false
end

local function current_is_ours()
    return (mp.get_property("path", "") or ""):match("^magnet%-rd://") ~= nil
end

local function delete_torrent(tid)
    curl_request(API_BASE .. "/torrents/delete/" .. tid, "DELETE", nil, AUTH)
end

-- Look up a torrent already on the RD account by infohash. This is what makes
-- re-adding a magnet recognise one that a previous session already added / is
-- still caching, instead of piling up a fresh duplicate that restarts from 0%.
-- Returns the id of the best match (prefers already-downloaded, else furthest along).
local function find_existing_torrent(hash)
    if not hash then return nil end
    local res = curl_request(API_BASE .. "/torrents?limit=200", "GET", nil, AUTH)
    local list = res and utils.parse_json(res)
    if type(list) ~= "table" then return nil end
    local best = nil
    for _, t in ipairs(list) do
        if t.hash and tostring(t.hash):lower() == hash then
            if not best then
                best = t
            elseif t.status == "downloaded" and best.status ~= "downloaded" then
                best = t
            elseif (t.progress or 0) > (best.progress or 0) then
                best = t
            end
        end
    end
    return best and best.id or nil
end

-- Delete every torrent on the account matching this hash (the one we streamed
-- plus any leftover duplicates), keeping the RD list clean.
local function delete_all_for_hash(hash, fallback_tid)
    local ids = {}
    if hash then
        local res = curl_request(API_BASE .. "/torrents?limit=200", "GET", nil, AUTH)
        local list = res and utils.parse_json(res)
        if type(list) == "table" then
            for _, t in ipairs(list) do
                if t.hash and tostring(t.hash):lower() == hash then
                    table.insert(ids, t.id)
                end
            end
        end
    end
    if #ids == 0 and fallback_tid then ids = {fallback_tid} end
    for _, id in ipairs(ids) do delete_torrent(id) end
end

-- ===== MAGNET PARSING =====

-- Pull every magnet URI out of an arbitrary blob of text.
local function extract_magnets(text)
    local out = {}
    if not text then return out end
    for m in text:gmatch("magnet:%?[^%s\"'<>]+") do
        table.insert(out, trim(m))
    end
    return out
end

local function magnet_infohash(magnet)
    local h = magnet:match("[Xx][Tt]=urn:bt[im]h:([%w]+)")
    return h and h:lower() or nil
end

local function magnet_display_name(magnet)
    local dn = magnet:match("[&?]dn=([^&]+)")
    if dn then return trim(urldecode(dn)) end
    return nil
end

-- ===== PLAYLIST GENERATION =====

local function build_virtual_link(rd_link, title)
    return "magnet-rd://play?l=" .. urlencode(rd_link) .. "&t=" .. urlencode(title)
end

-- Write a temp m3u for a single resolved torrent (header row + its files).
local function write_torrent_m3u(torrent)
    tmp_counter = tmp_counter + 1
    local m3u_path = get_cache_dir() .. "mpv_magnet_" .. os.time() .. "_" .. tmp_counter .. ".m3u8"
    local file = io.open(m3u_path, "w")
    if not file then return nil end

    file:write("#EXTM3U\n")
    file:write("#EXTINF:-1," .. torrent.name .. "\n")
    file:write("magnet-rd://header\n")
    for i, v_file in ipairs(torrent.files) do
        local icon = (i == #torrent.files) and "└─ " or "├─ "
        local display_name = icon .. get_filename(v_file.path)
        file:write("#EXTINF:-1," .. display_name .. "\n")
        file:write(build_virtual_link(v_file.link, get_filename(v_file.path)) .. "\n")
    end
    file:close()
    return m3u_path
end

-- Append a resolved torrent to the current playlist. If autoplay, jump to its
-- first playable entry and start; otherwise add quietly and notify.
local function append_torrent(torrent, autoplay)
    if not torrent or #torrent.files == 0 then return end
    local old_count = mp.get_property_number("playlist-count", 0) or 0
    local m3u = write_torrent_m3u(torrent)
    if not m3u then return end

    mp.commandv("loadlist", m3u, "append")

    if autoplay then
        mp.add_timeout(0.1, function()
            local n = mp.get_property_number("playlist-count", 0) or 0
            for i = old_count, n - 1 do
                local fn = mp.get_property("playlist/" .. i .. "/filename", "") or ""
                if fn:match("^magnet%-rd://play") then
                    mp.set_property("playlist-pos", i)
                    break
                end
            end
            mp.set_property("pause", "no")
        end)
    else
        osd("Ready in playlist: " .. torrent.name, 4)
    end
end

-- Decide whether a freshly-resolved torrent should start playing now or just
-- be appended. The first torrent of a request auto-plays only if mpv is idle or
-- already playing our content (so a slow background download never hijacks a
-- normal video the user started in the meantime).
local function handle_result(torrent)
    local first = magnet_data.awaiting_first
    magnet_data.awaiting_first = false
    local autoplay = first and (mpv_idle() or current_is_ours())
    table.insert(magnet_data.all_torrents, torrent)
    append_torrent(torrent, autoplay)
end

-- ===== NON-BLOCKING RESOLVER =====

-- Build the final {name, files={{path, link}}} from a "downloaded" info payload.
local function build_result(magnet, hash, j)
    local sel = {}
    for _, f in ipairs(j.files or {}) do
        if f.selected == 1 then table.insert(sel, {path = f.path}) end
    end
    if #sel == 0 then
        for _, f in ipairs(j.files or {}) do table.insert(sel, {path = f.path}) end
    end
    for i, link in ipairs(j.links or {}) do
        if sel[i] then sel[i].link = link end
    end
    local final = {}
    for _, f in ipairs(sel) do
        if f.link then table.insert(final, f) end
    end
    table.sort(final, natural_sort)

    local name = magnet_display_name(magnet)
        or (final[1] and get_filename(final[1].path))
        or ("Magnet " .. (hash or ""))
    return {name = name, files = final}
end

-- Drive one magnet through RD's lifecycle without blocking mpv.
-- Calls done(result_or_nil, reason).
local function resolve_magnet_async(magnet, done)
    local hash = magnet_infohash(magnet)

    -- Reuse an existing torrent if this magnet is already on the account (still
    -- caching from a previous session, or already downloaded). This avoids adding
    -- a duplicate that restarts from 0%, and lets a re-paste attach to the one
    -- that's already in progress.
    local tid = find_existing_torrent(hash)
    if not tid then
        -- The magnet value contains '&' and '=' and MUST be url-encoded, otherwise
        -- RD's form parser truncates it at the first '&' (dropping xt/dn/tr params).
        local res = curl_request(API_BASE .. "/torrents/addMagnet", "POST",
            "magnet=" .. urlencode(magnet), AUTH)
        local add_json = res and utils.parse_json(res)
        tid = add_json and add_json.id
    end
    if not tid then
        done(nil, "add-failed")
        return
    end

    local selected = false
    local last_msg = nil
    local tries = 0

    local function tick()
        tries = tries + 1
        local info = curl_request(API_BASE .. "/torrents/info/" .. tid, "GET", nil, AUTH)
        local j = info and utils.parse_json(info)

        if not j then
            -- transient network hiccup; keep trying within the cap
            if tries < POLL_MAX then mp.add_timeout(POLL_INTERVAL, tick) else done(nil, "no-info") end
            return
        end

        local status = j.status or "?"

        -- Fatal states: this magnet will never produce links -> safe to delete.
        if status == "error" or status == "magnet_error" or status == "dead"
           or status == "virus" or status == "magnet_conversion_error" then
            delete_torrent(tid)
            done(nil, status)
            return
        end

        -- Links ready -> build, remove the torrent(s) for this hash, done.
        if j.links and #j.links > 0 then
            local result = build_result(magnet, hash, j)
            delete_all_for_hash(hash, tid)
            if #result.files == 0 then done(nil, "no-video-files") else done(result, "ok") end
            return
        end

        -- Select the video files ONLY while RD is actually waiting for a
        -- selection. A reused torrent that's already downloading/downloaded has
        -- its files selected already; re-selecting it would error or reset it
        -- (this was the "Please choose the files" stuck-at-0% case).
        if status == "waiting_files_selection" and not selected and j.files and #j.files > 0 then
            local f_ids = {}
            for _, f in ipairs(j.files) do
                if is_video(f.path) then table.insert(f_ids, f.id) end
            end
            if #f_ids == 0 then
                for _, f in ipairs(j.files) do table.insert(f_ids, f.id) end
            end
            if #f_ids > 0 then
                local ok = curl_request(API_BASE .. "/torrents/selectFiles/" .. tid, "POST",
                    "files=" .. table.concat(f_ids, ","), AUTH)
                if ok ~= nil then selected = true end  -- retry next tick if the call failed
            end
        end

        -- Still working: show progress, keep polling. NEVER delete here.
        local seeders = j.seeders or 0
        local m
        if status == "downloading" then
            m = ("Caching on RD… %d%%  (%d seeders)"):format(math.floor(j.progress or 0), seeders)
        elseif status == "queued" then
            m = "Queued on Real-Debrid…  (auto-plays when ready)"
        elseif status == "magnet_conversion" then
            m = ("Fetching metadata… (%d seeders)"):format(seeders)
        elseif status == "waiting_files_selection" then
            m = "Selecting files…"
        elseif status == "compressing" or status == "uploading" then
            m = "Almost there (" .. status .. ")…"
        else
            m = "Preparing (" .. status .. ")…"
        end
        if m ~= last_msg then osd(m, POLL_INTERVAL + 2); last_msg = m end

        if tries < POLL_MAX then
            mp.add_timeout(POLL_INTERVAL, tick)
        else
            -- Give up watching, but LEAVE it on RD so it keeps downloading.
            -- A later paste of the same magnet will resolve instantly.
            done(nil, "still-downloading")
        end
    end

    tick()
end

-- Start one background resolver, dedup'd by infohash, caching + playing on done.
local function start_resolver(magnet)
    local hash = magnet_infohash(magnet)
    if hash and magnet_data.active[hash] then
        osd("Already resolving that magnet…", 3)
        return
    end
    if hash then magnet_data.active[hash] = true end

    resolve_magnet_async(magnet, function(result, reason)
        if hash then magnet_data.active[hash] = nil end

        if result then
            if hash then
                local cache = load_cache()
                cache[hash] = {name = result.name, files = result.files}
                save_cache(cache)
            end
            handle_result(result)
        elseif reason == "still-downloading" then
            osd("Still caching on RD — it'll start automatically, or re-paste later.", 6)
        elseif reason == "add-failed" then
            osd("Real-Debrid rejected the magnet.", 5)
        elseif reason == "no-video-files" then
            osd("No playable files in that torrent.", 5)
        else
            osd("Magnet could not be resolved (" .. tostring(reason) .. ").", 5)
        end
    end)
end

-- Entry point: resolve a list of magnets (cache-first) and play/append them.
local function process_magnets(magnets, target)
    if #magnets == 0 then
        osd("No magnet link found", 4)
        return
    end
    magnet_data.initial_target = target
    magnet_data.awaiting_first = true

    local cache = load_cache()
    local stagger = 0
    for _, magnet in ipairs(magnets) do
        local hash = magnet_infohash(magnet)
        local cached = hash and cache[hash] or nil
        if cached then
            handle_result(cached)          -- instant
        else
            -- Stagger uncached starts so we don't fire many addMagnet calls at once.
            local m = magnet
            mp.add_timeout(stagger, function() start_resolver(m) end)
            stagger = stagger + 1.5
        end
    end
end

-- ===== ON_LOAD: unrestrict our virtual scheme just before playback =====

mp.add_hook("on_load", 50, function()
    local path = mp.get_property("path", "")

    if path == "magnet-rd://header" then
        mp.command("playlist-next")
        return
    end

    if path:match("^magnet%-rd://play") then
        local rd_enc = path:match("[?&]l=([^&]*)")
        local title_enc = path:match("[?&]t=([^&]*)")
        local rd_link = rd_enc and urldecode(rd_enc) or nil
        local title = title_enc and urldecode(title_enc) or get_filename(path)

        mp.set_property("file-local-options/osd-playing-msg", title)
        mp.set_property("file-local-options/force-media-title", title)
        mp.set_property("title", title)

        if not rd_link then return end
        local res = curl_request(API_BASE .. "/unrestrict/link", "POST", "link=" .. rd_link, AUTH)
        local data = res and utils.parse_json(res)
        if data and data.download then
            mp.set_property("stream-open-filename", data.download)
        else
            osd("Link unavailable - cache may be stale (clear it and retry)", 5)
        end
    end
end)

-- ===== INPUT HOOKS =====

-- Intercept a magnet URI or a .magnet file opened directly in mpv - including
-- via the uosc file-browser "Ctrl+V" paste or your "Clipboard URL" binding.
--
-- IMPORTANT: mpv doesn't recognise the "magnet:" scheme, so when a magnet is
-- loaded it treats it as a filename and prepends the working directory, e.g.
-- "C:\...\magnet:?xt=...". We therefore scan the whole path for the magnet
-- rather than anchoring to the start.
mp.register_event("start-file", function()
    local path = mp.get_property("path", "") or ""

    local magnets = extract_magnets(path)
    if #magnets > 0 then
        mp.command("stop")
        process_magnets(magnets, path)
        return
    end

    if path:match("%.magnet$") then
        mp.command("stop")
        local f = io.open(path, "r")
        local content = f and f:read("*all") or ""
        if f then f:close() end
        process_magnets(extract_magnets(content), path)
    end
end)

-- ===== SCRIPT MESSAGES / HOTKEYS =====

local function paste_and_play()
    local clip = get_clipboard()
    local magnets = extract_magnets(clip)
    if #magnets == 0 then
        osd("Clipboard has no magnet link", 4)
        return
    end
    osd(("Found %d magnet(s) on clipboard"):format(#magnets), 2)
    process_magnets(magnets, "clipboard")
end

mp.register_script_message("magnet-paste-play", paste_and_play)
mp.add_key_binding("Ctrl+Shift+M", "magnet-paste-play", paste_and_play)

mp.register_script_message("magnet-clear-cache", function()
    os.remove(CACHE_FILE)
    osd("Cache cleared", 3)
end)

mp.register_script_message("magnet-show-cache-info", function()
    local cache = load_cache()
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    osd("Cache contains " .. count .. " magnet(s)", 3)
end)

msg.info("Real-Debrid Magnet Streamer v2.1 loaded")
