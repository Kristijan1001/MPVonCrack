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
           path:match("^null://header") or
           path:match("^magnet%-rd://header")
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

-- ===== HEADER AUTO-SKIP (single owner) =====
-- Playlists built by the Real-Debrid, TorBox and .strm players all use
-- "null://header" rows as folder titles, which must be skipped on load.
--
-- This lives HERE, in exactly one script, on purpose. It used to be duplicated
-- in the Real-Debrid and TorBox streamers, and once both were enabled at the
-- same time BOTH called playlist-next for the same header - so every header
-- skipped TWO entries instead of one, and opening the first torrent in a folder
-- played the second one's file. This script is always loaded and is
-- provider-independent, so it's the right place for it.
--
-- Note: the magnet streamer uses its own "magnet-rd://header" scheme and skips
-- those itself; it has only ever had one handler, so it stays as it is.
mp.add_hook("on_load", 50, function()
    if mp.get_property("path", "") == "null://header" then
        mp.command("playlist-next")
    end
end)

-- Register keybinds
mp.register_script_message("unified-prev", unified_prev)
mp.register_script_message("unified-next", unified_next)

msg.info("Unified Navigation v2.0 Loaded (Virtual Path Support)")