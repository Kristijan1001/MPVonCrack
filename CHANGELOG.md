# Changelog

Notable changes to the config and the custom scripts. Anything older than the
first entry here is in the commit log.

## 2026-08-19

### Added

- **`scripts/Custom_Twitch_AdBlock.lua`** — blocks Twitch ads.

  Twitch uses server-side ad insertion: ad segments are stitched into the same
  HLS stream, off the same CDN, with the same URL shape as the real content.
  There is nothing to pattern-match, which is why uBlock-style filter lists do
  nothing here. The only thing that works is fetching a *different* master
  playlist — one requested without your auth token — from a public proxy.

  On load it rewrites `twitch.tv/<channel>` to that playlist. Only the master
  playlist goes through the proxy; every variant playlist inside it points
  straight at Twitch's CDN, so all video still comes direct from Twitch. Three
  proxies are tried in order, and if all of them are down it falls back to
  normal yt-dlp resolution rather than failing to play.

  Two things worth knowing:
  - **Live rewind does not work while this is active.** The proxy playlist is
    not seekable. `force-seekable=yes` was tried and rejected — it flips the
    `seekable` property to yes but real seeks still fail, so it only made the
    UI lie.
  - The playlist request must carry `allow_source=true` or the proxies return
    transcodes only. Measured on a live channel: without it the playlist topped
    out at 1280x720; with it, 1920x1080.

- **`scripts/Custom_Kick_Live_Timeline.lua`** — honest seek bar on Kick.

  Kick live streams came through ytdl_hook advertising the full elapsed stream
  time as a seekable duration. Measured on a live channel: mpv reported
  `duration = 16928s` (4h42m) with `seekable=yes`, while only ~6.5s was really
  buffered — so uosc drew a four-and-a-half-hour scrubber over about six
  seconds of real data, and dragging anywhere else did nothing.

  Opening Kick's HLS URL directly instead reports only what mpv actually has:
  `duration = 15.7s`, `seekable=no`, same stream at the same moment.

  Live channels only — `kick.com/video/...` VODs, clips and browse pages are
  left to ytdl_hook, where a full seekable timeline is correct.

  This is **not** an ad blocker. Kick's live playlist carries no stitched ads
  that reach mpv: its only `EXT-X-DATERANGE` tags are `CLASS="timestamp"` and
  `CLASS="live-video-net-stream-source"` (`source="live"`), i.e. plain
  metadata, no SCTE-35. Kick does use SSAI, but on the web-player path, which
  yt-dlp does not go through.

- `script-opts/twitch_adblock.conf` and `script-opts/kick_live_timeline.conf`.

### Fixed

- **TorBox: opening a folder of `.torrent` files could freeze mpv for minutes.**

  `process()` uploads every `.torrent` in the folder before playing the one you
  opened, and each got its own readiness poll of 150 × 2s. A folder of nine
  uncached torrents was a 45-minute worst case. Four changes:

  - Only the torrent you actually opened gets the ~5 minute wait. The rest of
    the folder gets a quick probe and joins the playlist on a later launch once
    TorBox has them.
  - Permanent API rejections ("larger than 200GB", "upgrade your plan") are
    remembered as rejections instead of being re-uploaded on every single
    launch. Eight oversized torrents cost one round trip each, once, instead of
    once per start.
  - The poll loop now gives up after 3 consecutive unusable responses. If
    `mylist` returned unparseable JSON or `success:false`, the old loop treated
    that identically to "still downloading" and ground through all 150
    iterations in silence.
  - Failures show on the OSD. `msg.error` only reaches the log file, which is
    disabled by default, so a refusal was indistinguishable from a hang.

- **`[debrid_resilience]` never applied to TorBox streams.**

  The profile condition matched `^https?://`, but the TorBox script writes
  `torbox://<id>/<id>` into the playlist and only swaps in the real https URL
  later, in its `on_load` hook — so `path` was never https and the profile
  never fired. Real-Debrid was covered, because its playlist entries are real
  `https://real-debrid.com/d/` links.

  The visible symptom was TorBox-only mid-playback freezes of about a minute:
  with no `rw_timeout` override a stalled socket sat on mpv's 60s
  `network-timeout` default, while RD recovered in ~5s. The condition now also
  matches `^torbox://`, with a scoped `network-timeout = 15` inside the profile
  (verified scoped — the global property still reads 60 at idle).

  Worth remembering generally: a `profile-cond` on `p.path` sees the *playlist
  entry*, not whatever a script later puts in `stream-open-filename`.
