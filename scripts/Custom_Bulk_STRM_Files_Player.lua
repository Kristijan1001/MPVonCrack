-- strm-m3u-handler.lua
-- VERSION: 8.0 - Isolation Mode (Strict Whitelisting)

local utils = require 'mp.utils'
local msg = require 'mp.msg'

-- ===== CONFIGURATION =====
local function get_cache_dir()
    local config_dir = mp.command_native({"expand-path", "~~/script-opts"})
    return config_dir .. "/"
end

local processing = false
-- WHITELIST: Stores URLs that belong to this script.
-- If a URL isn't in here, the script will strictly ignore it.
local managed_urls = {}

-- ===== HELPER FUNCTIONS =====

local function url_decode(str)
    str = str:gsub("+", " ")
    str = str:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return str:gsub("\r", ""):gsub("\n", "")
end

local function get_filename_from_url(url)
    local clean = url:match("([^?]+)") or url
    clean = clean:gsub("/$", "")
    local name = clean:match("([^/]+)$") or clean
    return url_decode(name)
end

local function get_filename(path)
    return path:match("([^/\\]+)$") or path
end

local function is_strm(path)
    return path and path:match("%.strm$")
end

local function read_strm_lines(path)
    local file = io.open(path, "r")
    if not file then return {} end
    local urls = {}
    for line in file:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\r", "")
        if line ~= "" and not line:match("^#") then
            table.insert(urls, line)
        end
    end
    file:close()
    return urls
end

-- ===== PRIORITY SORTING LOGIC =====

local function get_priority_score(name)
    local lower = name:lower()
    
    if lower:match("%.flac$") or lower:match("%.mp3$") or lower:match("%.jpg$") or lower:match("%.png$") or lower:match("%.nfo$") or lower:match("%.txt$") or lower:match("%.srt$") then
        return 5
    end

    local junk_keywords = {
        "promo", "trailer", "sample", "bonus", "extra", 
        "featurette", "menu", "interview", "theme", 
        "opening", "ending", "credit", "preview", 
        "nep", "cm ", " cm", "ncop", "nced",
        "op ", "ed ", "specials", "ova", "oad", 
        "sp%d", "shiteater"
    }

    for _, keyword in ipairs(junk_keywords) do
        if lower:match(keyword) then return 4 end
    end

    if lower:match("s%d+e%d+") or lower:match("%d+x%d+") or lower:match("^%d%d%d+") or lower:match("[ .]%d%d%d+[ .]") or lower:match(" ep%d+") then
        return 1
    end

    return 2
end

local function smart_sort(a, b)
    local score_a = get_priority_score(a.name)
    local score_b = get_priority_score(b.name)
    
    if score_a ~= score_b then return score_a < score_b end
    
    local function padnum(n, d)
        return #d > 0 and ("%03d%s%.12f"):format(#n, n, tonumber(d) / (10 ^ #d)) 
                      or ("%03d%s"):format(#n, n)
    end
    local a_lower = a.name:lower():gsub("0*(%d+)%.?(%d*)", padnum)
    local b_lower = b.name:lower():gsub("0*(%d+)%.?(%d*)", padnum)
    return a_lower < b_lower
end

-- ===== CORE LOGIC =====

local function generate_and_load_playlist(start_path)
    processing = true
    msg.info("Generating sorted playlist...")
    
    -- RESET WHITELIST: Clear old URLs so we don't accidentally match old stuff
    managed_urls = {}
    
    local dir, _ = utils.split_path(start_path)
    local files = utils.readdir(dir, "files") or {}
    
    local strm_files = {}
    for _, file in ipairs(files) do
        if is_strm(file) then table.insert(strm_files, dir .. file) end
    end
    
    table.sort(strm_files, function(a,b) return get_filename(a):lower() < get_filename(b):lower() end)

    if #strm_files == 0 then processing = false; return end

    local m3u_path = get_cache_dir() .. "strm_playlist_" .. os.time() .. ".m3u8"
    local m3u_file = io.open(m3u_path, "w")
    if not m3u_file then processing = false; return end
    
    m3u_file:write("#EXTM3U\n")
    
    local target_index = 0
    local current_index = 0
    local start_name = get_filename(start_path)

    for _, strm_path in ipairs(strm_files) do
        local raw_urls = read_strm_lines(strm_path)
        
        if #raw_urls > 0 then
            local items = {}
            for _, url in ipairs(raw_urls) do
                -- ADD TO WHITELIST: We promise to manage this URL
                managed_urls[url] = true
                table.insert(items, { url = url, name = get_filename_from_url(url) })
            end

            table.sort(items, smart_sort)

            local header = get_filename(strm_path):gsub("%.strm$", "")
            m3u_file:write("#EXTINF:-1," .. header .. "\n")
            m3u_file:write("null://header\n")
            current_index = current_index + 1
            
            if get_filename(strm_path) == start_name then
                target_index = current_index
            end

            for i, item in ipairs(items) do
                local icon = (i == #items) and "└─ " or "├─ "
                local title = icon .. item.name
                
                m3u_file:write("#EXTINF:-1," .. title .. "\n")
                m3u_file:write(item.url .. "\n")
                current_index = current_index + 1
            end
        end
    end
    
    m3u_file:close()
    
    mp.commandv("loadlist", m3u_path, "replace")
    
    if target_index > 0 then
        mp.add_timeout(0.1, function() mp.set_property("playlist-pos", target_index) end)
    end
    
    processing = false
end

-- ===== HOOKS (ISOLATED) =====

mp.add_hook("on_load", 90, function()
    local path = mp.get_property("path", "")
    
    -- SAFETY CHECK:
    -- If this URL is NOT in our whitelist (managed_urls), STOP immediately.
    -- This ensures we NEVER touch torrent files or other media.
    if not managed_urls[path] then 
        return 
    end

    local title = mp.get_property("playlist/current/title", "")

    if path == "null://header" then
        mp.command("playlist-next")
        return
    end

    if title and (title:match("^├─") or title:match("^└─")) then
        local clean = title:gsub("^%s*[├└]─%s*", "")
        mp.set_property("file-local-options/force-media-title", clean)
        mp.set_property("title", clean)
    end
end)

mp.register_event("start-file", function()
    local path = mp.get_property("path", "")
    -- Only trigger generation if we explicitly opened a .strm file
    if is_strm(path) and not processing then
        mp.command("stop")
        generate_and_load_playlist(path)
    end
end)

msg.info("STRM Handler v8.0 (Isolation Mode) Loaded")