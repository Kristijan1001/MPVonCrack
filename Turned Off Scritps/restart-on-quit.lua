-- restart-on-quit.lua
local utils = require 'mp.utils'

mp.msg.info("=== RESTART SCRIPT LOADED ===")

local function restart_shim()
    mp.msg.info("Q PRESSED - Running restart script")
    
    local batch_file = "C:\\Library\\General\\Utilities\\Programs\\Shoko\\Jellyfin\\Jellyfin MPV Shim\\Jellyfin MPV Shim.bat"
    
    utils.subprocess_detached({
        args = {'cmd', '/c', batch_file},
        cancellable = false
    })
    
    mp.msg.info("Restart script executed")
end

-- Bind to 'q' key
mp.add_key_binding("Q", "restart-and-quit", restart_shim)