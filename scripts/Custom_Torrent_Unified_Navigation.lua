-- unified-nav.lua
-- Handles navigation for strm and torrent playlists
-- Recognizes virtual rdlink and null header protocols
-- Forces watch-later save before navigation to preserve resume position

local msg = require 'mp.msg'

-- Helper to identify headers
local function is_header_file(path)
    if not path then return false end
    -- Updated to match the virtual protocols in rd_streamer.lua v11.5
    return path:match("%.torrent$") or 
           path:match("%.strm$") or 
           path:match("^null://header")
end

local function unified_prev()
    local pos = mp.get_property_number("playlist-pos", 0)
    if pos <= 0 then 
        msg.info("Start of playlist")
        return 
    end
    
    -- FORCE SAVE CURRENT POSITION
    -- Preserves the resume point for the file you are leaving
    mp.command("write-watch-later-config")
    
    local target = pos - 1
    local target_path = mp.get_property("playlist/" .. target .. "/filename")
    local current_path = mp.get_property("playlist/" .. pos .. "/filename")
    
    -- SMART CHECK:
    -- Skip the previous entry if it's a header and we are coming from content
    if is_header_file(target_path) and not is_header_file(current_path) then
        msg.info("Skipping parent header: " .. target_path)
        target = target - 1
    else
        msg.info("Navigating to previous item")
    end
    
    -- Prevent going out of bounds
    if target < 0 then target = 0 end
    
    mp.commandv("playlist-play-index", tostring(target))
end

local function unified_next()
    -- FORCE SAVE CURRENT POSITION
    mp.command("write-watch-later-config")
    
    -- Standard next behavior
    mp.commandv("playlist-next")
end

-- Register keybinds
mp.register_script_message("unified-prev", unified_prev)
mp.register_script_message("unified-next", unified_next)

msg.info("Unified Navigation v2.0 Loaded (Virtual Path Support)")