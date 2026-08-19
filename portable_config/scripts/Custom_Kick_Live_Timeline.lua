-- Kick Live Timeline
-- VERSION: 1.0
--
-- Kick live streams came through ytdl_hook advertising the FULL elapsed stream
-- time as a seekable duration. Measured on a live channel: mpv reported
-- duration = 16928s (4h42m) with seekable=yes, while demuxer-cache-duration was
-- 6.5s. So uosc drew a four-and-a-half-hour scrubber where roughly six seconds
-- of it actually worked - drag anywhere else and nothing happened. The bar was
-- cosmetic.
--
-- Opening Kick's HLS URL directly instead (ytdl=no) makes mpv report only what
-- it has really got: duration 15.7s, seekable=no, on the same stream at the same
-- moment. Same honest behaviour Twitch now has.
--
-- Note this is NOT ad blocking. Kick's live playlist was checked for stitched
-- ads and carries none that reach mpv - its only EXT-X-DATERANGE tags are
-- CLASS="timestamp" and CLASS="live-video-net-stream-source" (source="live"),
-- i.e. plain metadata, no SCTE-35 and no ad markers. If Kick's ad rollout ever
-- reaches this path, that stream-source class is the field that would change.
--
-- "path" deliberately stays kick.com/<channel> - only stream-open-filename is
-- rewritten, so twitch_chat keeps auto-detecting the Kick channel from the URL.

local msg = require 'mp.msg'
local utils = require 'mp.utils'
local options = require 'mp.options'

local opts = {
    -- Blank = look next to mpv.exe, then fall back to yt-dlp on PATH.
    ytdl_path = "",
    format = "best",
    timeout = 20,
    osd = false,
}
options.read_options(opts, "kick_live_timeline")

-- Paths under kick.com that are not live channels. VODs and clips are real
-- recordings where a full seekable timeline is correct - leave those to ytdl.
local NOT_CHANNELS = {
    video = true, videos = true, clips = true, browse = true, category = true,
    categories = true, following = true, search = true, settings = true,
    dashboard = true, subscriptions = true, messages = true, wallet = true,
    help = true, about = true, terms = true, privacy = true, transparency = true,
}

local function channel_from(path)
    if not path then return nil end
    local ch = path:match("^https?://[^/]*kick%.com/([%w_%-]+)/?$")
             or path:match("^https?://[^/]*kick%.com/([%w_%-]+)%?")
    if not ch then return nil end
    if NOT_CHANNELS[ch:lower()] then return nil end
    return ch
end

local function ytdl_binary()
    if opts.ytdl_path ~= "" then return opts.ytdl_path end
    -- ~~exe_dir is not supported in this mpv build, but the config dir is
    -- portable_config/ which sits next to mpv.exe, so go up one.
    local bundled = mp.command_native({"expand-path", "~~/../yt-dlp.exe"})
    if bundled and utils.file_info(bundled) then return bundled end
    return "yt-dlp"
end

local function resolve(channel)
    local r = utils.subprocess({
        args = {ytdl_binary(), "-g", "-f", opts.format, "--no-warnings",
                "https://kick.com/" .. channel},
        cancellable = false, playback_only = false,
    })
    if not r or r.status ~= 0 or not r.stdout then return nil end
    -- -g can emit several lines (split video/audio); the first is what we want.
    local url = r.stdout:match("^[^\r\n]+")
    if url and url:match("^https?://") then return url end
    return nil
end

mp.add_hook("on_load", 5, function()
    -- Read "path", not stream-open-filename, and run before ytdl_hook (10).
    local channel = channel_from(mp.get_property("path", ""))
    if not channel then return end

    local url = resolve(channel)
    if not url then
        -- Offline, geo-blocked, yt-dlp broken - whatever it is, do nothing and
        -- let ytdl_hook handle it exactly as before.
        msg.warn("Could not resolve Kick stream for " .. channel ..
                 "; leaving it to ytdl_hook")
        return
    end

    msg.info("Direct HLS for kick.com/" .. channel)
    mp.set_property("stream-open-filename", url)

    -- Otherwise ytdl_hook sees an https URL in stream-open-filename and resolves
    -- it again, putting the inflated duration right back.
    mp.set_property("file-local-options/ytdl", "no")

    if opts.osd then
        mp.osd_message("Kick: direct HLS (" .. channel .. ")", 2)
    end
end)

msg.info("Kick Live Timeline v1.0 loaded")
