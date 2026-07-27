-- fix_path_prepend.lua
-- Fixes URLs where mpv has incorrectly prepended the local directory
-- Uses "loadfile" to completely replace the entry so the OSC doesn't error out.

local msg = require 'mp.msg'

mp.add_hook("on_load", 50, function()
    local path = mp.get_property("path")
    if not path then return end

    -- 1. Check if "http:" or "https:" exists ANYWHERE in the string
    local start_index = path:find("https?:")
    
    if start_index then
        -- 2. Extract ONLY the URL part (cut off the C:\Library... prefix)
        local extracted_url = path:sub(start_index)
        
        -- 3. Fix the backslashes to forward slashes
        local fixed_url = extracted_url:gsub("\\", "/")

        -- 4. Fix protocol typos (e.g., https:/example -> https://example)
        if fixed_url:match("^https?:/[^/]") then
            fixed_url = fixed_url:gsub("^(https?:)/", "%1//")
        end

        -- Check if we actually changed anything
        if fixed_url ~= path then
            msg.warn("Detected corrupted local path: " .. path)
            msg.info("Reloading with clean URL: " .. fixed_url)
            
            -- KEY CHANGE: Use loadfile with "replace".
            -- This tells mpv: "Stop loading the broken C:\ path completely
            -- and load this HTTP URL instead."
            -- This ensures the UI knows it's a web stream, not a folder.
            mp.commandv("loadfile", fixed_url, "replace")
        end
    end
end)