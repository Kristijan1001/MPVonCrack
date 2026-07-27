-- Real-Debrid Unified Streamer
-- VERSION: 21.0 - Infinite Cache + expired-link auto-recovery
--
-- v21.0: when a cached /d/ link no longer unrestricts (expired) OR a torrent was
-- never cached on RD, the torrent is re-added to Real-Debrid for caching. If the
-- content is still on RD it re-caches instantly and auto-plays; if not, it's
-- queued for caching and we skip to the files that ARE ready (the cached ones
-- keep playing). Cache/temp files live in portable_config/_cache/rdcache.

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

-- ===== PROVIDER GATE =====
-- The TorBox streamer hooks the same "start-file" event on *.torrent and also
-- calls mp.command("stop"), so with both live they fight over every file we
-- open. script-opts/debrid.conf picks the winner; re-read on each use so
-- switching from the menu takes effect without restarting mpv.
local PROVIDER_CONF = mp.command_native({"expand-path", "~~/script-opts/debrid.conf"})

local function active_provider()
    -- get_property_native, NOT get_property: user-data nodes come back
    -- JSON-encoded as a string, i.e. with literal quotes around the value, and
    -- '"realdebrid"' never equals 'realdebrid'.
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

local function is_active() return active_provider() == "realdebrid" end

if RD_API == "" then
    msg.error("No Real-Debrid token. Add 'api_key=...' to script-opts/realdebrid.conf")
    -- Only nag if Real-Debrid is actually the selected provider; someone running
    -- TorBox shouldn't get an error popup about a service they aren't using.
    mp.add_timeout(1, function()
        if is_active() then
            mp.osd_message("Real-Debrid: no API token set\nAdd api_key=... to script-opts/realdebrid.conf", 6)
        end
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

-- Permanent cache + temp session-playlist storage. Everything lives together in
-- portable_config/_cache/rdcache (shared with the magnet RD script), not script-opts.
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

local CACHE_FILE = get_cache_dir() .. "rd_torrent_cache.json"

-- ===== STATE =====
local torrent_data = {
    processing = false,
    all_torrents = {},
    by_link = {},
    link_info = {},   -- rd /d/ link -> { torrent = <torrent>, file = <file> }
    refreshed = {},   -- expired /d/ link -> fresh /d/ link (string), or false = skip
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
    if not file then 
        msg.warn("Failed to save cache to " .. CACHE_FILE)
        return false
    end
    
    local json_str = utils.format_json(cache)
    file:write(json_str)
    file:close()
    return true
end

local function get_file_hash(path)
    -- Create a simple hash from file path and modification time
    local file = io.open(path, "r")
    if not file then return nil end
    file:close()
    
    -- Use file size and path as hash (modification time not easily accessible in Lua)
    local size = 0
    local f = io.open(path, "rb")
    if f then
        size = f:seek("end")
        f:close()
    end
    
    return path .. "_" .. tostring(size)
end

local function get_cached_torrent(cache, t_path)
    local hash = get_file_hash(t_path)
    if hash and cache[hash] then
        return cache[hash]
    end
    return nil
end

-- ===== HELPER FUNCTIONS =====

local function get_filename(path)
    return path:match("([^/\\]+)$") or path
end

local function is_video(path)
    if not path then return false end

    -- check filename ONLY
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
        if ext == v_ext then
            return true
        end
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

local function curl_request(url, method, data, headers)
    local args = {"curl", "-s", "-L", "-X", method or "GET"}
    if headers then
        for k, v in pairs(headers) do table.insert(args, "-H"); table.insert(args, k .. ": " .. v) end
    end
    if data then
        table.insert(args, (method == "PUT" and "--data-binary" or "-d"))
        table.insert(args, (method == "PUT" and "@" .. data or data))
    end
    table.insert(args, url)
    local res = utils.subprocess({args = args, cancellable = false, playback_only = false})
    return (res and res.status == 0) and res.stdout or nil
end

-- Reliable sleep on Windows. mpv runs subprocesses with stdin redirected,
-- which makes the `timeout` command abort instantly ("Input redirection is
-- not supported"). `ping` waits ~1s between echoes, so N seconds ~= N+1 pings.
local function sleep_seconds(secs)
    secs = math.max(1, math.floor(secs or 1))
    utils.subprocess({
        args = {"ping", "-n", tostring(secs + 1), "127.0.0.1"},
        cancellable = false, playback_only = false
    })
end

-- ===== ISOLATED M3U GENERATION =====

local function create_stable_playlist()
    if #torrent_data.all_torrents == 0 then return end
    
    -- Create a unique filename to prevent autoload from merging other files
    local m3u_path = get_cache_dir() .. "mpv_rd_session_" .. os.time() .. ".m3u8"
    local file = io.open(m3u_path, "w")
    if not file then return end
    
    file:write("#EXTM3U\n")
    torrent_data.by_link = {}
    torrent_data.link_info = {}

    for _, torrent in ipairs(torrent_data.all_torrents) do
        local clean_header = torrent.name:gsub("%.torrent$", "")
        file:write("#EXTINF:-1," .. clean_header .. "\n")
        file:write("null://header\n")

        for i, v_file in ipairs(torrent.files) do
            local icon = (i == #torrent.files) and "└─ " or "├─ "
            local display_name = icon .. get_filename(v_file.path)
            torrent_data.by_link[v_file.link] = display_name
            torrent_data.link_info[v_file.link] = {torrent = torrent, file = v_file}

            file:write("#EXTINF:-1," .. display_name .. "\n")
            file:write(v_file.link .. "\n")
        end
    end
    file:close()
    
    -- Use 'replace' to kill the old playlist and any autoload artifacts
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

-- ===== CORE PROCESS WITH CACHE =====

local function process_torrent_with_api(t_path)
    msg.info("Processing torrent via API: " .. get_filename(t_path))
    
    local res = curl_request("https://api.real-debrid.com/rest/1.0/torrents/addTorrent", "PUT", t_path, {Authorization = "Bearer " .. RD_API, ["Content-Type"] = "application/x-bittorrent"})
    local add_json = res and utils.parse_json(res)
    local tid = add_json and add_json.id
    if not tid then return nil end
    
    local info = curl_request("https://api.real-debrid.com/rest/1.0/torrents/info/" .. tid, "GET", nil, {Authorization = "Bearer " .. RD_API})
    local info_json = info and utils.parse_json(info)
    if not info_json or not info_json.files then return nil end
    
    local v_files = {}
    local f_ids = {}
    for _, f in ipairs(info_json.files) do
        if is_video(f.path) then 
            table.insert(v_files, {id = f.id, path = f.path})
            table.insert(f_ids, f.id)
        end
    end
    
    if #v_files == 0 then return nil end
    
    curl_request("https://api.real-debrid.com/rest/1.0/torrents/selectFiles/" .. tid, "POST", "files=" .. table.concat(f_ids, ","), {Authorization = "Bearer " .. RD_API})
    
    local links = nil
    for i = 1, 10 do
        local r_info = curl_request("https://api.real-debrid.com/rest/1.0/torrents/info/" .. tid, "GET", nil, {Authorization = "Bearer " .. RD_API})
        local r_json = r_info and utils.parse_json(r_info)
        if r_json and r_json.links and #r_json.links > 0 then 
            links = r_json.links
            break 
        end
        -- Wait ~1s for Real-Debrid to finish generating the links
        sleep_seconds(1)
    end
    
    if not links then return nil end
    
    -- Assign links to files BEFORE sorting
    for i, link in ipairs(links) do 
        if v_files[i] then 
            v_files[i].link = link 
        end 
    end
    
    -- NOW sort the files with their links already attached
    table.sort(v_files, natural_sort)
    
    -- Delete torrent from Real-Debrid after extracting links
    curl_request("https://api.real-debrid.com/rest/1.0/torrents/delete/" .. tid, "DELETE", nil, {Authorization = "Bearer " .. RD_API})
    msg.info("Cleaned up torrent from RD: " .. get_filename(t_path))
    
    return {name = get_filename(t_path), files = v_files}
end

local function process(start_path)
    if torrent_data.processing then return end
    torrent_data.processing = true
    torrent_data.initial_target = start_path 
    mp.set_property("pause", "yes") 
    
    local dir, _ = utils.split_path(start_path)
    local t_files = scan_torrents(dir)
    
    -- Load existing cache
    local cache = load_cache()
    local needs_save = false
    
    torrent_data.all_torrents = {}
    torrent_data.refreshed = {}

    msg.info("Processing " .. #t_files .. " torrents...")

    for _, t_path in ipairs(t_files) do
        -- Try to get from cache first
        local torrent_info = get_cached_torrent(cache, t_path)

        if torrent_info then
            msg.info("Cache HIT: " .. get_filename(t_path))
            -- Remember which .torrent this came from, so an expired link can be re-cached.
            torrent_info.torrent_path = t_path
            table.insert(torrent_data.all_torrents, torrent_info)
        else
            -- Process via API if not in cache
            msg.info("Cache MISS: " .. get_filename(t_path))
            torrent_info = process_torrent_with_api(t_path)

            if torrent_info then
                torrent_info.torrent_path = t_path
                table.insert(torrent_data.all_torrents, torrent_info)

                -- Save to cache
                local hash = get_file_hash(t_path)
                if hash then
                    cache[hash] = torrent_info
                    needs_save = true
                end
            end
        end
    end
    
    -- Save updated cache if we processed any new torrents
    if needs_save then
        save_cache(cache)
        msg.info("Cache updated with new torrents")
    end
    
    create_stable_playlist()
    torrent_data.processing = false
end

-- ===== EXPIRED-LINK RECOVERY =====

-- Unrestrict a single /d/ link into a playable download URL (nil if it fails).
local function unrestrict(link)
    local res = curl_request("https://api.real-debrid.com/rest/1.0/unrestrict/link",
        "POST", "link=" .. link, {Authorization = "Bearer " .. RD_API})
    local data = res and utils.parse_json(res)
    return data and data.download or nil
end

-- A cached /d/ link that no longer unrestricts is expired. Re-add its .torrent to
-- Real-Debrid to mint fresh links. If the content is still cached on RD this is
-- instant and we return a ready-to-play URL; if it isn't cached, RD starts caching
-- it and we return nil so the caller skips ahead to the files that ARE ready.
local function recover_expired_link(old_link)
    local info = torrent_data.link_info[old_link]
    if not info or not info.torrent or not info.torrent.torrent_path then return nil end
    local t = info.torrent

    mp.osd_message("Link expired — re-caching on Real-Debrid…", 4)
    local fresh = process_torrent_with_api(t.torrent_path)

    if not fresh or #fresh.files == 0 then
        -- Not cached on RD yet; it's now queued for caching. Mark this torrent's
        -- links so we skip them (instead of re-resolving once per file).
        for _, of in ipairs(t.files) do
            torrent_data.refreshed[of.link] = false
        end
        return nil
    end

    -- Pair every old link with its fresh counterpart (by filename) so the other
    -- files of this torrent reuse the fresh links without re-resolving.
    for _, of in ipairs(t.files) do
        local want = get_filename(of.path)
        for _, nf in ipairs(fresh.files) do
            if get_filename(nf.path) == want then
                torrent_data.refreshed[of.link] = nf.link
                break
            end
        end
    end
    t.files = fresh.files

    -- Persist the fresh links so next session isn't stale again.
    local hash = get_file_hash(t.torrent_path)
    if hash then
        local cache = load_cache()
        fresh.torrent_path = t.torrent_path
        cache[hash] = fresh
        save_cache(cache)
    end

    local fresh_link = torrent_data.refreshed[old_link]
    return fresh_link and unrestrict(fresh_link) or nil
end

-- ===== HOOKS =====

mp.add_hook("on_load", 50, function()
    local path = mp.get_property("path", "")
    if path == "null://header" then mp.command("playlist-next"); return end
    if not path:find("real%-debrid%.com/d/") then return end

    -- Title: strip the tree icons from the playlist display name.
    local title = torrent_data.by_link[path] or get_filename(path)
    local clean_title = title:gsub("^%s*[├└]─%s*", "")
    mp.set_property("file-local-options/osd-playing-msg", clean_title)
    mp.set_property("file-local-options/force-media-title", clean_title)
    mp.set_property("title", clean_title)

    -- If this torrent was already re-resolved, use the fresh link (or skip if the
    -- torrent turned out to be un-cached / queued for caching this session).
    local mapped = torrent_data.refreshed[path]
    if mapped == false then
        mp.command("playlist-next")
        return
    end

    local link = mapped or path
    local download = unrestrict(link)

    -- The original cached link failed => it's expired. Re-cache the torrent.
    if not download and not mapped then
        download = recover_expired_link(path)
    end

    if download then
        mp.set_property("stream-open-filename", download)
    else
        -- Not playable yet (now queued on RD) — skip so the cached ones keep playing.
        mp.command("playlist-next")
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

-- ===== CACHE MANAGEMENT COMMANDS =====

mp.register_script_message("rd-clear-cache", function()
    os.remove(CACHE_FILE)
    msg.info("Real-Debrid cache cleared")
    mp.osd_message("Real-Debrid cache cleared", 3)
end)

mp.register_script_message("rd-show-cache-info", function()
    local cache = load_cache()
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    msg.info("Cache contains " .. count .. " torrents")
    mp.osd_message("Cache: " .. count .. " torrents", 3)
end)

-- ===== HOTKEY: Add all .torrent files in current folder to RD cloud =====

local function add_folder_to_rd_cloud()
    local base = torrent_data.initial_target
    if not base or base == "" then base = mp.get_property("path", "") end
    if not base or base == "" then
        mp.osd_message("RD: no folder context", 3)
        return
    end

    local dir, _ = utils.split_path(base)
    local t_files = scan_torrents(dir)
    if #t_files == 0 then
        mp.osd_message("RD: no .torrent files in folder", 3)
        return
    end

    mp.osd_message("RD: adding " .. #t_files .. " torrents...", 3)
    local added, failed = 0, 0

    for _, t_path in ipairs(t_files) do
        local res = curl_request("https://api.real-debrid.com/rest/1.0/torrents/addTorrent", "PUT", t_path,
            {Authorization = "Bearer " .. RD_API, ["Content-Type"] = "application/x-bittorrent"})
        local parsed = res and utils.parse_json(res)
        local tid = parsed and parsed.id

        if not tid then
            failed = failed + 1
            msg.warn("addTorrent failed: " .. get_filename(t_path))
        else
            local info = curl_request("https://api.real-debrid.com/rest/1.0/torrents/info/" .. tid, "GET", nil,
                {Authorization = "Bearer " .. RD_API})
            local info_json = info and utils.parse_json(info)
            if info_json and info_json.files then
                local f_ids = {}
                for _, f in ipairs(info_json.files) do
                    if is_video(f.path) then table.insert(f_ids, f.id) end
                end
                if #f_ids == 0 then
                    for _, f in ipairs(info_json.files) do table.insert(f_ids, f.id) end
                end
                if #f_ids > 0 then
                    curl_request("https://api.real-debrid.com/rest/1.0/torrents/selectFiles/" .. tid, "POST",
                        "files=" .. table.concat(f_ids, ","), {Authorization = "Bearer " .. RD_API})
                end
            end
            added = added + 1
            msg.info("Added to RD: " .. get_filename(t_path) .. " (id=" .. tid .. ")")
        end

        mp.osd_message(("RD: %d/%d (added %d, failed %d)")
            :format(added + failed, #t_files, added, failed), 2)

        -- Throttle to avoid RD rate-limiting (~5s between torrents)
        sleep_seconds(5)
    end

    mp.osd_message(("RD done: added %d, failed %d"):format(added, failed), 5)
end

mp.add_key_binding("Ctrl+Shift+F8", "rd-add-folder", add_folder_to_rd_cloud)