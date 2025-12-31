-- image_only_cugan_fix_v3.lua
-- ONLY handles image files - completely ignores videos
-- Does NOT touch hwdec (you handle that via mpv.conf)
-- Only adjusts image dimensions when necessary for Real-CUGAN compatibility
-- Maintains Real-CUGAN filter when switching between images
-- Clears filters when switching from image to video
-- Removes scale filters when switching to videos

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

-- List of image file extensions
local image_extensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'tif', 'avif'
}

local previous_was_image = false
local cugan_applied = false
local last_cugan_filter_command = nil

local function is_image()
    local path = mp.get_property("path", "")
    if not path or path == "" then 
        return false 
    end
    
    local extension = path:match("%.([^%.]+)$")
    if not extension then return false end
    
    extension = extension:lower()
    for _, ext in ipairs(image_extensions) do
        if extension == ext then
            local duration = mp.get_property_number("duration", -1)
            if duration > 0 then return false end

            local format = mp.get_property("file-format", "")
            if format and format:match("^image") then return true end

            local width = mp.get_property_number("width", 0)
            if width > 0 and duration <= 0 then return true end
        end
    end
    return false
end

local function has_cugan_filter()
    local vf_json = mp.get_property("vf", "")
    if not vf_json or vf_json == "" then return false end

    local success, vf = pcall(utils.parse_json, vf_json)
    if not success or not vf then
        vf = mp.get_property_native("vf", {})
    end

    for _, filter in ipairs(vf) do
        if filter.name and filter.name:match("glsl") and
           ((filter.label and filter.label:match("[cC][uU][gG][aA][nN]")) or
            (filter.params and filter.params.file and filter.params.file:match("[cC][uU][gG][aA][nN]"))) then
            return true
        end
    end
    return false
end

local function has_scale_filter()
    local vf_json = mp.get_property("vf", "")
    if not vf_json or vf_json == "" then return false end

    local success, vf = pcall(utils.parse_json, vf_json)
    if not success or not vf then
        vf = mp.get_property_native("vf", {})
    end

    for _, filter in ipairs(vf) do
        if filter.name and filter.name == "scale" then
            return true
        end
    end
    return false
end

local function remove_scale_filters()
    local vf = mp.get_property_native("vf", {})
    local new_vf = {}
    local removed_count = 0
    
    for _, filter in ipairs(vf) do
        if filter.name ~= "scale" then
            table.insert(new_vf, filter)
        else
            removed_count = removed_count + 1
        end
    end
    
    if removed_count > 0 then
        mp.set_property_native("vf", new_vf)
        msg.info(string.format("Removed %d scale filter(s) for video playback", removed_count))
        mp.osd_message(string.format("Removed %d scale filter(s)", removed_count), 2)
        return true
    end
    
    return false
end

local original_command = mp.command
mp.command = function(cmd)
    if cmd and type(cmd) == "string" and cmd:match("[cC][uU][gG][aA][nN]") then
        if cmd:match("vf%s+append") or cmd:match("vf%s+pre") or cmd:match("vf%s+add") or cmd:match("vf%s+set") or cmd:match("vf%s+toggle") then
            msg.info("Detected CUGAN filter command: " .. cmd)
            last_cugan_filter_command = cmd
            cugan_applied = true
        end
    end
    return original_command(cmd)
end

local function clear_filters()
    msg.info("Clearing video filters")
    mp.command("vf clr")
    mp.osd_message("Cleared video filters", 2)
end

local function is_cugan_compatible()
    local width = mp.get_property_number("width", 0)
    local height = mp.get_property_number("height", 0)
    
    if width == 0 or height == 0 then
        msg.warn("Could not get image dimensions")
        return false
    end
    
    if width % 8 == 0 and height % 8 == 0 and
       width >= 64 and height >= 64 and
       width <= 1920 and height <= 1080 then
        local aspect_ratio = width / height
        if aspect_ratio >= 0.5 and aspect_ratio <= 2.0 then
            return true
        end
    end
    
    return false
end

local function adjust_image_for_cugan()
    local width = mp.get_property_number("width", 0)
    local height = mp.get_property_number("height", 0)
    
    if width == 0 or height == 0 then
        msg.warn("Could not get image dimensions")
        return
    end
    
    -- Ensure the image is always adjusted to be compatible with Real-CUGAN
    local mod8_width = math.ceil(width / 8) * 8
    local mod8_height = math.ceil(height / 8) * 8
    
    local target_width = mod8_width
    local target_height = mod8_height
    
    if target_width < 64 then target_width = 64 end
    if target_height < 64 then target_height = 64 end
    if target_width > 1920 then target_width = 1920 end
    if target_height > 1080 then target_height = 1080 end

    local aspect_ratio = target_width / target_height
    if aspect_ratio < 0.5 then
        target_width = math.ceil(target_height * 0.5 / 8) * 8
    elseif aspect_ratio > 2.0 then
        target_height = math.ceil(target_width * 0.5 / 8) * 8
    end

    msg.info(string.format("Adjusting image from %dx%d to %dx%d for Real-CUGAN compatibility", 
                          width, height, target_width, target_height))
    
    mp.command(string.format("vf set scale=%d:%d:flags=lanczos", target_width, target_height))
    mp.osd_message(string.format("Adjusted to %dx%d for Real-CUGAN compatibility", 
                              target_width, target_height), 3)
end

local function reapply_cugan_filter()
    if last_cugan_filter_command then
        msg.info("Reapplying CUGAN filter: " .. last_cugan_filter_command)
        mp.command(last_cugan_filter_command)
        mp.osd_message("Reapplied CUGAN filter", 2)
        return true
    else
        msg.info("No CUGAN filter command stored to reapply")
        return false
    end
end

local function reapply_cugan_filter_with_delay()
    -- Delay reapplying the filter to ensure the hwdec setting is settled.
    mp.add_timeout(0.3, function()
        if last_cugan_filter_command then
            msg.info("Reapplying CUGAN filter: " .. last_cugan_filter_command)
            mp.command(last_cugan_filter_command)
            mp.osd_message("Reapplied CUGAN filter", 2)
        else
            msg.info("No CUGAN filter command stored to reapply")
        end
    end)
end

function on_file_loaded()
    mp.add_timeout(0.5, function()
        local path = mp.get_property("path", "")
        local current_is_image = is_image()
        
        if previous_was_image and not current_is_image then
            msg.info("Switching from image to video, clearing filters and removing scale filters")
            mp.add_timeout(0.1, function()
                clear_filters()
                cugan_applied = false
                -- Additional check to remove any remaining scale filters
                mp.add_timeout(0.2, function()
                    if has_scale_filter() then
                        remove_scale_filters()
                    end
                end)
            end)
        elseif not previous_was_image and not current_is_image then
            -- Video to video transition, check for and remove scale filters
            msg.info("Video detected, checking for scale filters to remove")
            mp.add_timeout(0.2, function()
                if has_scale_filter() then
                    remove_scale_filters()
                end
            end)
        end
        
        if current_is_image then
            msg.info("Image detected: " .. path)

            -- Force the adjustment and CUGAN application
            adjust_image_for_cugan()

            if previous_was_image and cugan_applied and last_cugan_filter_command then
                mp.add_timeout(0.3, function()
                    reapply_cugan_filter_with_delay()
                end)
            end
        else
            msg.info("Not an image, doing nothing: " .. path)
        end

        previous_was_image = current_is_image
    end)
end

mp.observe_property("vf", "native", function(name, value)
    if value and is_image() then
        if not has_cugan_filter() then return end
        if not last_cugan_filter_command then
            msg.info("Detected CUGAN filter added, but don't have command")
            cugan_applied = true
            local vf_json = mp.get_property("vf", "")
            if vf_json and vf_json ~= "" then
                msg.info("Current filters: " .. vf_json)
                local vf = mp.get_property_native("vf", {})
                for _, filter in ipairs(vf) do
                    if filter.name and filter.name:match("glsl") and
                       filter.params and filter.params.file and 
                       filter.params.file:match("[cC][uU][gG][aA][nN]") then
                        local file_path = filter.params.file
                        last_cugan_filter_command = "vf toggle vapoursynth=\"" .. file_path .. "\""
                        msg.info("Reconstructed CUGAN command: " .. last_cugan_filter_command)
                        break
                    end
                end
            end
        end
    end
end)

mp.add_key_binding("F4", "cugan_adjust", function()
    if is_image() then
        adjust_image_for_cugan()
    else
        mp.osd_message("CUGAN adjustment only works on images", 2)
    end
end)

mp.add_key_binding("F5", "clear_filters", function()
    clear_filters()
    cugan_applied = false
    last_cugan_filter_command = nil
end)

mp.add_key_binding("F6", "reapply_cugan", function()
    if is_image() then
        if reapply_cugan_filter() then
            -- ok
        else
            mp.osd_message("No CUGAN filter to reapply", 2)
        end
    else
        mp.osd_message("CUGAN filters only work on images", 2)
    end
end)

-- New key binding to manually remove scale filters
mp.add_key_binding("F7", "remove_scale_filters", function()
    if not is_image() then
        if remove_scale_filters() then
            -- Success message already shown in remove_scale_filters()
        else
            mp.osd_message("No scale filters found to remove", 2)
        end
    else
        mp.osd_message("Scale filter removal only works on videos", 2)
    end
end)

mp.add_timeout(1, function()
    local key_bindings = mp.get_property_native("input-bindings", {})
    for _, binding in ipairs(key_bindings) do
        if binding.cmd and binding.cmd:match("[cC][uU][gG][aA][nN]") then
            local original_key = binding.key
            local original_cmd = binding.cmd
            mp.add_forced_key_binding(original_key, "wrapped_" .. original_key, function()
                msg.info("Detected CUGAN hotkey: " .. original_cmd)
                last_cugan_filter_command = original_cmd
                cugan_applied = true
                mp.command(original_cmd)
            end, {repeatable=true})
        end
    end
end)

mp.register_event("file-loaded", on_file_loaded)

msg.info("Image-only CUGAN Fix v3.2 loaded - now removes scale filters on videos")