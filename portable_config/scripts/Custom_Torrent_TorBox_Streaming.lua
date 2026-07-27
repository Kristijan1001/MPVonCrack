-- TorBox Unified Streamer
-- VERSION: 2.0 - Provider-gated, Windows-safe waits, real caching support
--
-- Streams .torrent files through TorBox, mirroring the Real-Debrid script's
-- workflow: open one .torrent and every .torrent in that folder becomes a
-- playlist, with each torrent name as a header row above its episodes.
--
-- ONLY ACTIVE when script-opts/debrid.conf says provider=torbox. The
-- Real-Debrid streamer hooks the same "start-file" event on *.torrent and also
-- calls mp.command("stop"), so with both live they fought over every file.
-- Switch between them from the menu: Streaming > Switch Provider.
--
-- Fixed since v1.1:
--   * sleep() shelled out to "timeout", which fails on Windows the moment
--     stdin is redirected ("Input redirection is not supported") - so every
--     retry delay was a silent no-op and the poll loop spun instantly. Now
--     uses PowerShell Start-Sleep, matching the rest of these scripts.
--   * The readiness poll gave up after 10 tries x 1s. That only ever worked
--     for torrents already cached on TorBox; anything TorBox had to actually
--     download failed after 10 seconds. Now polls up to ~5 minutes and shows
--     live progress with seeder count.
--   * Cache moved from script-opts/ to _cache/tbcache/, matching the RD
--     scripts, so config and state stop sharing a folder.
--   * API token moved out of this file into script-opts/torbox.conf.

local utils = require 'mp.utils'
local msg = require 'mp.msg'

-- ===== CONFIGURATION =====
-- Your TorBox token is NOT stored in this file. Put it in:
--     portable_config/script-opts/torbox.conf   ->   api_key=YOUR_TOKEN
-- or set a TORBOX_API_KEY environment variable.
-- Grab a token from https://torbox.app/settings while logged in.
local function load_tb_api_key()
    local path = mp.command_native({"expand-path", "~~/script-opts/torbox.conf"})
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
    return os.getenv("TORBOX_API_KEY") or ""
end

local TB_API = load_tb_api_key()
local API_BASE = "https://api.torbox.app/v1/api"

-- ===== PROVIDER GATE =====
-- Re-read on every use so switching providers from the menu takes effect
-- immediately, without restarting mpv.
local PROVIDER_CONF = mp.command_native({"expand-path", "~~/script-opts/debrid.conf"})

local function active_provider()
    -- get_property_native, NOT get_property: user-data nodes come back
    -- JSON-encoded as a string, i.e. with literal quotes around the value, and
    -- '"torbox"' never equals 'torbox'.
    local p = mp.get_property_native("user-data/debrid/provider")
    if type(p) == "string" and p ~= "" then return p end
    local f = io.open(PROVIDER_CONF, "r")
    if f then
        for line in f:lines() do
            local v = line:match("^%s*provider%s*=%s*(%S+)")
            if v then f:close() return v:lower() end
        end
        f:close()
    end
    return "realdebrid"
end

local function is_active() return active_provider() == "torbox" end

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
    "trailer", "sample"
}

-- How long to wait for TorBox to cache a torrent it doesn't already have.
local POLL_INTERVAL = 2     -- seconds between status checks
local POLL_MAX = 150        -- x2s = ~5 minutes before we give up on this torrent

-- ===== CACHE =====
-- Cache + temp session playlists live together in _cache/tbcache, matching the
-- Real-Debrid scripts. script-opts/ is for configuration, not state.
local function ensure_dir(dir)
    if utils.file_info and utils.file_info(dir) then return end
    utils.subprocess({
        args = {"powershell", "-NoProfile", "-NonInteractive", "-Command",
            "New-Item -ItemType Directory -Force -Path '" .. dir .. "' > $null"},
        cancellable = false, playback_only = false
    })
end

local CACHE_DIR = mp.command_native({"expand-path", "~~/_cache/tbcache"})
ensure_dir(CACHE_DIR)

local function get_cache_dir()
    return CACHE_DIR .. "/"
end

local CACHE_FILE = get_cache_dir() .. "tb_torrent_cache.json"

-- ===== STATE =====
local torrent_data = {
    processing = false,
    all_torrents = {},
    by_link = {},
    initial_target = nil
}

-- ===== CACHE FUNCTIONS =====
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
    if not file then return false end
    local json_str = utils.format_json(cache)
    file:write(json_str)
    file:close()
    return true
end

local function get_file_hash(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    return path .. "_" .. tostring(size)
end

local function get_cached_torrent(cache, t_path)
    local hash = get_file_hash(t_path)
    if hash and cache[hash] then return cache[hash] end
    return nil
end

-- ===== HELPER FUNCTIONS =====
local function get_filename(path)
    return path:match("([^/\\]+)$") or path
end

local function is_video(path)
    if not path then return false end
    local name = get_filename(path):lower()
    for _, w in ipairs(EXCLUDE_WORDS) do
        if name:match("%f[%a]" .. w .. "%f[%A]") then return false end
    end
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

local function scan_torrents(dir)
    local files = utils.readdir(dir, "files") or {}
    local torrents = {}
    for _, file in ipairs(files) do
        if file:match("%.torrent$") then table.insert(torrents, dir .. file) end
    end
    table.sort(torrents, function(a, b)
        return get_filename(a):lower() < get_filename(b):lower()
    end)
    return torrents
end

-- Standard CURL request
local function curl_request(url, method, data, headers)
    local args = {"curl", "-s", "-L", "-X", method or "GET"}
    if headers then
        for k, v in pairs(headers) do
            table.insert(args, "-H")
            table.insert(args, k .. ": " .. v)
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

-- Multipart Upload for TorBox
local function curl_multipart_upload(url, filepath, headers)
    local args = {"curl", "-s", "-L", "-X", "POST"}
    if headers then
        for k, v in pairs(headers) do
            table.insert(args, "-H")
            table.insert(args, k .. ": " .. v)
        end
    end
    table.insert(args, "-F")
    table.insert(args, "file=@" .. filepath)
    table.insert(args, "-F")
    table.insert(args, "seed=1")
    table.insert(args, url)
    local res = utils.subprocess({args = args, cancellable = false, playback_only = false})
    return (res and res.status == 0) and res.stdout or nil
end

-- Blocking wait. The old version called "timeout", which on Windows aborts with
-- "ERROR: Input redirection is not supported" whenever stdin isn't a console -
-- which is always, under mpv's subprocess. PowerShell's Start-Sleep works and is
-- already used elsewhere in these scripts.
local function sleep(seconds)
    local ms = math.floor((tonumber(seconds) or 1) * 1000)
    utils.subprocess({
        args = {"powershell", "-NoProfile", "-NonInteractive", "-Command",
            "Start-Sleep -Milliseconds " .. ms},
        cancellable = false, playback_only = false
    })
end

-- ===== ISOLATED M3U GENERATION =====
local function create_stable_playlist()
    if #torrent_data.all_torrents == 0 then return end

    local m3u_path = get_cache_dir() .. "mpv_tb_session_" .. os.time() .. ".m3u8"
    local file = io.open(m3u_path, "w")
    if not file then return end

    file:write("#EXTM3U\n")
    torrent_data.by_link = {}

    for _, torrent in ipairs(torrent_data.all_torrents) do
        local clean_header = torrent.name:gsub("%.torrent$", "")
        file:write("#EXTINF:-1," .. clean_header .. "\n")
        file:write("null://header\n")

        for i, v_file in ipairs(torrent.files) do
            local icon = (i == #torrent.files) and "└─ " or "├─ "
            local display_name = icon .. get_filename(v_file.path)
            local custom_link = "torbox://" .. torrent.id .. "/" .. v_file.id
            torrent_data.by_link[custom_link] = display_name
            file:write("#EXTINF:-1," .. display_name .. "\n")
            file:write(custom_link .. "\n")
        end
    end
    file:close()

    mp.commandv("loadlist", m3u_path, "replace")

    mp.add_timeout(0.1, function()
        local pl = mp.get_property_native("playlist")
        local target_name = get_filename(torrent_data.initial_target):gsub("%.torrent$", "")
        for i, item in ipairs(pl) do
            if item.title and item.title == target_name then
                mp.set_property("playlist-pos", i - 1)
                mp.set_property("pause", "no")
                break
            end
        end
    end)
end

-- ===== CORE PROCESS =====
local function process_torrent_with_api(t_path)
    msg.info("Processing torrent: " .. get_filename(t_path))

    local res = curl_multipart_upload(API_BASE .. "/torrents/createtorrent", t_path,
        {Authorization = "Bearer " .. TB_API})
    local json_res = res and utils.parse_json(res)

    if not json_res or not json_res.success then
        msg.error("Upload failed: " .. (json_res and json_res.detail or "Unknown error"))
        return nil
    end

    local tid = json_res.data and json_res.data.torrent_id
    if not tid then return nil end

    local files = nil
    local short_name = get_filename(t_path):gsub("%.torrent$", "")

    -- Poll until TorBox reports the torrent is usable. A torrent already cached
    -- on TorBox satisfies this on the first pass; one it has to fetch shows live
    -- progress instead of silently timing out after 10 seconds.
    for i = 1, POLL_MAX do
        local info_res = curl_request(API_BASE .. "/torrents/mylist?id=" .. tid, "GET", nil,
            {Authorization = "Bearer " .. TB_API})
        local info_json = info_res and utils.parse_json(info_res)

        if info_json and info_json.success and info_json.data then
            local t_data = info_json.data
            if t_data.download_finished or t_data.download_state == "cached" or t_data.download_present then
                files = t_data.files
                break
            end

            -- Fatal states: no point waiting these out.
            local state = t_data.download_state or ""
            if state == "error" or state == "stalled" or state == "missingFiles" then
                msg.error("TorBox reports '" .. state .. "' for " .. short_name)
                mp.osd_message("TorBox: " .. state .. " - " .. short_name, 5)
                return nil
            end

            local pct = math.floor((tonumber(t_data.progress) or 0) * 100)
            local seeds = tonumber(t_data.seeds) or 0
            mp.osd_message(string.format("Caching on TorBox... %d%% (%d seeders)\n%s",
                pct, seeds, short_name), POLL_INTERVAL + 1)
        end

        if i < POLL_MAX then sleep(POLL_INTERVAL) end
    end

    if not files then
        msg.warn("Timed out waiting for TorBox to cache: " .. short_name)
        mp.osd_message("TorBox still caching - skipping " .. short_name, 4)
        return nil
    end

    local v_files = {}
    for _, f in ipairs(files) do
        if is_video(f.name) then
            table.insert(v_files, {id = f.id, path = f.name})
        end
    end

    if #v_files == 0 then return nil end
    table.sort(v_files, natural_sort)

    return {id = tid, name = get_filename(t_path), files = v_files}
end

local function process(start_path)
    if torrent_data.processing then return end
    torrent_data.processing = true
    torrent_data.initial_target = start_path
    mp.set_property("pause", "yes")

    local dir, _ = utils.split_path(start_path)
    local t_files = scan_torrents(dir)
    local cache = load_cache()
    local needs_save = false

    torrent_data.all_torrents = {}
    msg.info("Processing " .. #t_files .. " torrents...")
    mp.osd_message("Processing torrents with TorBox...", 30)

    for _, t_path in ipairs(t_files) do
        local torrent_info = get_cached_torrent(cache, t_path)
        if torrent_info then
            table.insert(torrent_data.all_torrents, torrent_info)
        else
            torrent_info = process_torrent_with_api(t_path)
            if torrent_info then
                table.insert(torrent_data.all_torrents, torrent_info)
                local hash = get_file_hash(t_path)
                if hash then
                    cache[hash] = torrent_info
                    needs_save = true
                end
            end
        end
    end

    if needs_save then save_cache(cache) end

    if #torrent_data.all_torrents == 0 then
        mp.osd_message("TorBox: nothing playable found", 4)
        torrent_data.processing = false
        return
    end

    create_stable_playlist()
    torrent_data.processing = false
    mp.osd_message("", 1)
end

-- ===== HOOKS & LINK RESOLUTION =====
mp.add_hook("on_load", 50, function()
    local path = mp.get_property("path", "")

    -- Only claim our own virtual scheme. "null://header" is shared with the
    -- .strm handler, so skip headers regardless of provider.
    if path == "null://header" then mp.command("playlist-next"); return end

    local tid, fid = path:match("torbox://(%d+)/(%d+)")
    if not (tid and fid) then return end

    if TB_API == "" then
        msg.error("No TorBox token. Add 'api_key=...' to script-opts/torbox.conf")
        mp.osd_message("TorBox: no API token set\nAdd api_key=... to script-opts/torbox.conf", 6)
        return
    end

    local display = torrent_data.by_link[path] or "Unknown Video"
    local clean_title = display:gsub("^%s*[├└]─%s*", "")
    mp.set_property("file-local-options/osd-playing-msg", clean_title)
    mp.set_property("file-local-options/force-media-title", clean_title)
    mp.set_property("title", clean_title)

    msg.info("Requesting link for Torrent: " .. tid .. " File: " .. fid)

    -- RETRY LOGIC (3 Attempts)
    local stream_url = nil
    for attempt = 1, 3 do
        local req_url = API_BASE .. "/torrents/requestdl" ..
                        "?token=" .. TB_API ..
                        "&torrent_id=" .. tid ..
                        "&file_id=" .. fid ..
                        "&zip_link=false"

        local res = curl_request(req_url, "GET", nil, nil)
        local data = res and utils.parse_json(res)

        if data and data.success and type(data.data) == "string" then
            stream_url = data.data
            break -- Success!
        else
            local err_msg = (data and data.detail) or "Unknown"
            msg.warn("Attempt " .. attempt .. " failed: " .. err_msg)
            if attempt < 3 then sleep(1.5) end
        end
    end

    if stream_url then
        msg.info("Resolved URL: " .. stream_url)
        mp.set_property("stream-open-filename", stream_url)
    else
        msg.error("Failed to resolve link after 3 attempts.")
        mp.osd_message("Link Error: Try next file", 5)
    end
end)

mp.register_event("start-file", function()
    if not is_active() then return end
    local path = mp.get_property("path", "")
    if path:match("%.torrent$") then
        mp.command("stop")
        process(path)
    end
end)

-- ===== COMMANDS =====
mp.register_script_message("tb-clear-cache", function()
    os.remove(CACHE_FILE)
    msg.info("TorBox cache cleared")
    mp.osd_message("TorBox cache cleared", 3)
end)

mp.register_script_message("tb-show-cache-info", function()
    local cache = load_cache()
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    mp.osd_message(string.format("TorBox cache: %d torrents\n%s", count, CACHE_FILE), 5)
end)

if TB_API == "" then
    msg.warn("TorBox streamer loaded without a token (script-opts/torbox.conf)")
end
msg.info("TorBox Streamer v2.0 loaded (provider=" .. active_provider() .. ")")
