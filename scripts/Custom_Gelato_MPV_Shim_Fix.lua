-- MPV script to fix backslashes and null bytes in URLs
-- Place this in: ~/.config/mpv/scripts/Gelato_MPVShimFix.lua (Linux/Mac)
-- or: %APPDATA%/mpv/scripts/Gelato_MPVShimFix.lua (Windows)

function fix_url_hook()
    local url = mp.get_property("stream-open-filename")
    
    if url and url:match("^https?:") then
        local original_url = url
        
        -- Remove null bytes (they appear as literal \0 in the string)
        url = url:gsub("%z", "")
        
        -- Replace all backslashes with forward slashes
        url = url:gsub("\\", "/")
        
        -- Fix the protocol - ensure it's https:// or http:// (exactly two slashes)
        url = url:gsub("^(https?):/+", "%1://")
        
        if url ~= original_url then
            mp.msg.info("[Gelato_MPVShimFix] Fixing URL with backslashes")
            mp.msg.info("Original: " .. original_url)
            mp.msg.info("Fixed: " .. url)
            
            -- Update the URL that will be opened
            mp.set_property("stream-open-filename", url)
        end
    end
end

-- Register the hook at priority 50 (runs before file opens)
mp.add_hook("on_load", 50, fix_url_hook)