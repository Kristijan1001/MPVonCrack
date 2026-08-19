-- Twitch Ad Block
-- VERSION: 1.0
--
-- Twitch serves ads with SSAI (server-side ad insertion): the ad segments are
-- stitched into the same HLS stream, off the same CDN, with the same URL shape
-- as the real content. There is nothing to pattern-match, which is why uBlock
-- style filter lists cannot touch it. The only thing that works is getting a
-- DIFFERENT master playlist - one requested without your auth token, or from a
-- region Twitch doesn't serve ads to. That is what the public proxies below do.
--
-- So on load we rewrite twitch.tv/<channel> to a proxy master playlist. Only the
-- master playlist goes through the proxy; the variant playlists inside it point
-- straight at Twitch's CDN, so all the actual video still comes direct.
--
-- "path" deliberately stays twitch.tv/<channel> - only stream-open-filename is
-- rewritten. That matters for two reasons:
--   * twitch_chat auto-detects the channel from the URL and would break.
--   * the [debrid_resilience] profile excludes twitch.tv by path, and its
--     reconnect opts are known to kill live HLS (reconnect-at-byte-0 loops).
--
-- Always on: there is deliberately no off switch. If every proxy is down it
-- falls back to normal yt-dlp resolution (with ads) on its own.

local msg = require 'mp.msg'
local utils = require 'mp.utils'
local options = require 'mp.options'

local opts = {
    -- Tried in order, first one returning a real #EXTM3U wins. These do die off
    -- periodically; if all of them fail the stream just falls through to normal
    -- yt-dlp resolution (with ads) rather than failing to play.
    proxies = "https://eu.luminous.dev/live," ..
              "https://lb-eu.cdn-perfprod.com/live," ..
              "https://lb-as.cdn-perfprod.com/live",
    timeout = 8,
    osd = true,
}
options.read_options(opts, "twitch_adblock")

-- Paths under twitch.tv that are not live channels. VODs and clips are not
-- ad-stitched the same way and the proxies don't serve them.
local NOT_CHANNELS = {
    videos = true, directory = true, settings = true, popout = true,
    downloads = true, subscriptions = true, wallet = true, drops = true,
    u = true, moderator = true, team = true, jobs = true, turbo = true,
    p = true, friends = true, inventory = true, prime = true,
}

local function channel_from(path)
    if not path then return nil end
    local ch = path:match("^https?://[^/]*twitch%.tv/([%w_]+)/?$")
             or path:match("^https?://[^/]*twitch%.tv/([%w_]+)%?")
    if not ch then return nil end
    if NOT_CHANNELS[ch:lower()] then return nil end
    return ch:lower()
end

-- A HEAD-ish probe: we pull the master playlist once to confirm the proxy is
-- alive and actually returned a playlist rather than a Cloudflare error page.
local function probe(url)
    local r = utils.subprocess({
        args = {"curl", "-s", "-m", tostring(opts.timeout), url},
        cancellable = false, playback_only = false,
    })
    if r and r.status == 0 and r.stdout and r.stdout:sub(1, 7) == "#EXTM3U" then
        return true
    end
    return false
end

-- Without allow_source the proxies hand back transcodes ONLY - capped at 720p,
-- no source rendition at all. Measured on a live channel: bare URL topped out at
-- 1280x720, with allow_source the same playlist offers 1920x1080.
-- allow_audio_only keeps the audio-only rendition available as a fallback.
local PLAYLIST_PARAMS = "?allow_source=true&allow_audio_only=true"

local function pick_proxy(channel)
    for base in opts.proxies:gmatch("[^,]+") do
        base = base:match("^%s*(.-)%s*$")
        if base ~= "" then
            local url = base .. "/" .. channel .. PLAYLIST_PARAMS
            if probe(url) then return url, base end
            msg.warn("Proxy did not return a playlist: " .. base)
        end
    end
    return nil
end

mp.add_hook("on_load", 5, function()
    -- Read "path", not stream-open-filename: we want the original twitch URL,
    -- and we want to run before ytdl_hook (priority 10) bothers resolving it.
    local channel = channel_from(mp.get_property("path", ""))
    if not channel then return end

    local url, base = pick_proxy(channel)
    if not url then
        msg.warn("No working ad-block proxy; falling back to yt-dlp (with ads)")
        if opts.osd then
            mp.osd_message("Twitch adblock: no proxy available, ads may play", 4)
        end
        return
    end

    msg.info("Ad-free playlist for " .. channel .. " via " .. base)
    mp.set_property("stream-open-filename", url)

    -- ytdl_hook looks at stream-open-filename and would happily hand our proxy
    -- URL to yt-dlp, which resolves it right back to an ad-stitched stream.
    mp.set_property("file-local-options/ytdl", "no")

    -- Twitch's HLS drops keepalive connections; without this the stream dies with
    -- "Error reading HTTP response: End of file" every so often.
    mp.set_property("file-local-options/demuxer-lavf-o-append", "http_persistent=0")

    -- NOTE on seeking: the proxy playlist is not seekable, so live rewind does
    -- NOT work on Twitch. That is a known, accepted cost of blocking the ads.
    -- force-seekable=yes was tried and removed - it flips the "seekable" property
    -- to yes but real seeks still fail, so it only made the UI lie.

    if opts.osd then
        mp.osd_message("Twitch adblock on (" .. channel .. ")", 2)
    end
end)

msg.info("Twitch Ad Block v1.0 loaded")
