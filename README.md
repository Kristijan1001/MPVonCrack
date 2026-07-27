# MPVonCrack

**An mpv build that upscales with neural nets, interpolates to 120fps, streams torrents through Real-Debrid without downloading them, and renders live Twitch/Kick chat with real emotes inside the video window.**

https://github.com/user-attachments/assets/e5842bfb-2501-4525-9f12-54b8a8405af3

Double-click a `.torrent` file → it plays. Paste a magnet → it plays. Open a Twitch link → chat appears next to the video. Hit `F1` → the anime you're watching gets run through a GAN in real time.

Built on [hooke007's mpv_PlayKit / MPV_lazy](https://github.com/hooke007/MPV_lazy) with a pile of custom Lua on top.

---

## Table of contents

- [What's in the box](#whats-in-the-box)
- [Requirements](#requirements)
- [Install](#install)
- [Real-Debrid setup (do this first)](#real-debrid-setup-do-this-first)
- [Streaming torrents & magnets](#streaming-torrents--magnets)
- [`.strm` bulk playlists](#strm-bulk-playlists)
- [Live chat overlay — Twitch & Kick](#live-chat-overlay--twitch--kick)
- [AI upscaling & frame interpolation — how the models actually work](#ai-upscaling--frame-interpolation--how-the-models-actually-work)
- [GLSL shaders](#glsl-shaders)
- [NVIDIA RTX VSR & True HDR](#nvidia-rtx-vsr--true-hdr)
- [VR / 360° video](#vr--360-video)
- [Picture-in-Picture / phone mode](#picture-in-picture--phone-mode)
- [Full hotkey reference](#full-hotkey-reference)
- [File map](#file-map)
- [Troubleshooting](#troubleshooting)
- [Credits](#credits)

---

## What's in the box

| | Feature | Where it lives |
|---|---|---|
| 🧲 | Play `.torrent` files and magnet links via Real-Debrid — no download, no torrent client | `scripts/Custom_Torrent_*.lua` |
| 💬 | Live Twitch **and** Kick chat rendered *inside* mpv, with animated 7TV/BTTV/FFZ emotes | `scripts/twitch_chat/` |
| 🔍 | Real-time neural upscaling — Real-ESRGAN, AnimeJaNai, Real-CUGAN, ArtCNN | `vs/Upscale/` |
| 🎞️ | Real-time frame interpolation — RIFE 4.6 / 4.25 / 4.26, 2× and 3× | `vs/FrameInterpolation/` |
| ✨ | 30+ GLSL shaders — Anime4K, FSRCNNX, NNEDI3, AMD FSR, adaptive sharpening | `shaders/` |
| 🖥️ | NVIDIA RTX Video Super Resolution + RTX True HDR (SDR→HDR) | `input_uosc.conf`, `Custom_NVIDIA_RTX_HDR.lua` |
| 🧹 | Denoise, deinterlace, grain removal, anti-aliasing presets | `vs/Cleaning/` |
| 📺 | `.strm` bulk playlists with smart episode sorting (Jellyfin-friendly) | `scripts/Custom_Bulk_STRM_Files_Player.lua` |
| 🥽 | 360° / VR video with mouse-look | `scripts/mpv360.lua` |
| 📱 | Picture-in-Picture / vertical phone mode with edge snapping | `scripts/Custom_Phone_PiP_Mode.lua` |
| 🖱️ | Scroll-wheel playlist navigation that skips folder headers and saves resume points | `scripts/Custom_Torrent_Unified_Navigation.lua` |
| 🎛️ | uosc UI + right-click mega-menu with every preset one click away | `scripts/uosc/`, `input_uosc.conf` |

---

## Requirements

**Read this before you file an issue.**

| | |
|---|---|
| **OS** | Windows 10/11 (x64). The Lua scripts shell out to PowerShell for clipboard and directory work. |
| **GPU for shaders** | Anything modern. Anime4K/FSR/NNEDI3 run on AMD, Intel and NVIDIA. |
| **GPU for AI upscale + RIFE** | **NVIDIA only.** The `.vpy` presets use `vsmlrt`'s TensorRT backend (`UAI_NV_TRT`, `CUGAN_NV`, `RIFE_NV`). RTX 20-series or newer. |
| **VRAM** | 6 GB minimum for 1080p→4K ESRGAN. 8 GB+ recommended. CUGAN at 3× wants more. |
| **RTX VSR / True HDR** | RTX 20-series+ with the feature enabled in the NVIDIA Control Panel. |
| **Real-Debrid** | A paid RD account + API token. Free accounts won't stream. |
| **Live chat** | Python 3 with Pillow (bundled next to `mpv.exe` in the full build) + `websocket-client` for Kick. |

If you're on AMD or Intel: everything except the `vs/` AI presets still works. Use the GLSL shaders instead — Anime4K AIO (`Ctrl+0`) is genuinely good.

---

## Install

This repo contains **`portable_config/` only** — the configuration layer. It is not a full mpv build.

1. Get a portable mpv with VapourSynth already wired up. The easiest path is [hooke007's mpv_PlayKit release](https://github.com/hooke007/MPV_lazy/releases) — it ships `mpv.exe`, a bundled Python, VapourSynth and the plugin folders.
2. Drop this repo's `portable_config/` into the mpv folder, replacing the one that came with it. You should end up with:

   ```
   mpv/
   ├── mpv.exe
   ├── yt-dlp.exe
   ├── python.exe                  ← bundled Python (used by the chat overlay)
   ├── vs-plugins/
   │   └── models/                 ← .onnx weights go here (NOT in this repo)
   └── portable_config/            ← this repo
       ├── mpv.conf
       ├── profiles.conf
       ├── script-opts.conf
       ├── input_uosc.conf
       ├── input_contextmenu_plus.conf
       ├── fonts/
       ├── scripts/
       ├── script-opts/
       ├── shaders/
       └── vs/
   ```
3. Copy `portable_config/script-opts/realdebrid.conf.example` → `realdebrid.conf` and paste your token in. See below.
4. Download the AI model weights you want (see [the models section](#getting-the-model-weights)) into `vs-plugins/models/`.
5. Launch `mpv.exe`. Right-click for the menu.

### What's deliberately *not* in this repo

| Excluded | Why |
|---|---|
| `*.engine` | TensorRT engines are compiled for **your exact GPU, driver version and TensorRT version**. They're useless on any other machine and get rebuilt automatically. Mine are ~1.2 GB. |
| `*.onnx` | Model weights are large and belong to their upstream authors. Download links below. |
| `portable_config/_cache/` | Shader cache, watch-later, ICC cache, Real-Debrid link cache. Machine-local state. |
| `script-opts/realdebrid.conf` | Contains your API token. Gitignored. |
| `saved-props.json` | Your saved volume/mute. |
| `portable_config/OLD/` | My junk drawer. |

---

## Real-Debrid setup (do this first)

The torrent and magnet scripts do nothing without a token.

1. Log into Real-Debrid and open **https://real-debrid.com/apitoken**
2. Copy the token.
3. In `portable_config/script-opts/`, copy `realdebrid.conf.example` to `realdebrid.conf`
4. Set it:

   ```ini
   api_key=YOUR_TOKEN_HERE
   ```
5. Restart mpv.

**The token is never stored in a `.lua` file.** Both scripts call `load_rd_api_key()`, which reads `script-opts/realdebrid.conf`, then falls back to a `REALDEBRID_API_KEY` environment variable, then gives up with an on-screen error. `realdebrid.conf` is in `.gitignore`, so you can fork this and push without leaking anything.

> ⚠️ **If you ever pasted your token directly into a `.lua` file and pushed it anywhere, revoke it.** Real-Debrid tokens don't expire on their own — go to the API token page and generate a new one.

---

## Streaming torrents & magnets

Two scripts, one account, two entry points. Neither one downloads anything to your disk — Real-Debrid holds the files and serves them over HTTP, and mpv seeks into them like a local file.

### `.torrent` files — `Custom_Torrent_Real_Derbid_Streaming.lua`

**Just double-click a `.torrent` file.** That's the whole workflow.

What happens under the hood:

1. **Read the folder.** Every `.torrent` in the same directory is picked up, not just the one you clicked — so a season folder becomes one playlist.
2. **Cache check.** `_cache/rdcache/rd_torrent_cache.json` is consulted first (mine has ~136 torrents in it). A hit means playback starts instantly with zero API calls.
3. **On a miss**, the torrent is `PUT` to `torrents/addTorrent`, video/audio files are selected via `torrents/selectFiles` (filtered by extension, `trailer` excluded), and the resulting links are stored.
4. **A session `.m3u8` is written** to `_cache/rdcache/`, with each torrent name as a header row and its episodes nested under it.
5. **On playback**, the `on_load` hook calls `unrestrict/link` to turn the RD link into a real streamable URL.
6. **The torrent is deleted from your RD account** once links are extracted, so your RD torrent list doesn't fill up.

**Expired-link auto-recovery (v21):** Real-Debrid `/d/` links go stale. When one fails to unrestrict, the script re-adds that torrent to mint fresh links. If RD still has the content cached it recovers instantly and keeps playing; if not, it queues the caching and skips ahead to the episodes that *are* ready, so the playlist doesn't stall on one dead file. The on-disk cache is rewritten with the new links.

| Key | Action |
|---|---|
| `Ctrl+Shift+F8` | Add a whole folder of torrents to your RD cloud (pre-cache a season before bed) |
| `Ctrl+Shift+Alt+Z` | Clear the torrent link cache |
| Menu → Streaming | Show cache info |

### Magnet links — `Custom_Torrent_Magnet_Streaming.lua`

Four ways in:

1. **Paste it like a YouTube link.** `Ctrl+Shift+V` loads whatever's on your clipboard. This is the fastest path.
2. **`Ctrl+Shift+M`** — "Paste & Play Magnet", reads the clipboard directly. Handles several magnets at once.
3. **A `.magnet` text file** — one magnet per line, open it in mpv.
4. **A raw `magnet:?xt=...` URI** passed on the command line or from a browser handler.

Because magnets aren't cached by infohash on RD's side by default, this script does extra work:

- **`find_existing_torrent(hash)`** queries `GET /torrents` *before* adding anything. If you already started caching this magnet in a previous session, it reattaches to that download instead of creating a duplicate starting from 0%.
- **Non-blocking resolution.** RD caching runs on a `mp.add_timeout` state machine polling every 2s for up to ~10 minutes. mpv stays fully responsive and shows `Caching on RD… 47% (12 seeders)` on screen. Seeder count is displayed so a dead magnet is obvious immediately.
- **It never deletes a torrent mid-download.** Only on success or a fatal status (`error`/`dead`/`virus`/`magnet_error`). A partially-cached magnet is left on RD so re-pasting it later is instant.
- **Results don't hijack playback.** If you start a normal video while a magnet caches in the background, the magnet won't steal the window when it finishes.

Cache lives at `_cache/rdcache/magnet_rd_cache.json`, keyed by infohash — re-pasting the same magnet is instant.

| Key | Action |
|---|---|
| `Ctrl+Shift+M` | Paste & play magnet from clipboard |
| `Ctrl+Shift+V` | Load clipboard URL (works for magnets, YouTube, anything) |
| Menu → Streaming | Show / clear magnet cache |

### Scroll-wheel navigation

Both scripts build playlists with **header rows** (the torrent/folder name) above their episodes. `Custom_Torrent_Unified_Navigation.lua` binds the mouse wheel to skip those headers automatically and forces a `write-watch-later-config` before every jump — so your resume position in episode 3 survives scrolling to episode 4 and back.

| Input | Action |
|---|---|
| `Wheel Up` | Previous item (skips headers) |
| `Wheel Down` | Next item |
| `Mouse Back / Forward` | Previous / next |

---

## `.strm` bulk playlists

`Custom_Bulk_STRM_Files_Player.lua` — for Jellyfin/Emby `.strm` libraries.

Open any `.strm` file and every `.strm` in that folder is expanded into one playlist, with each file's URLs sorted by a **priority scoring** pass:

| Score | Matches | Result |
|---|---|---|
| 1 | `S01E05`, `1x05`, `EP12`, `001` | Real episodes — first |
| 2 | everything else | Movies / specials |
| 4 | `trailer`, `sample`, `promo`, `NCOP`, `NCED`, `bonus`, `featurette`, `interview`, `preview`, `OVA`… | Junk — pushed down |
| 5 | `.flac`, `.mp3`, `.jpg`, `.nfo`, `.srt` | Non-video — last |

Within a score bucket it sorts naturally, so `Episode 2` comes before `Episode 10`.

It runs in **isolation mode**: it maintains a whitelist of URLs it created and refuses to touch any path it doesn't own, so it can never interfere with the torrent scripts.

---

## Live chat overlay — Twitch & Kick

`scripts/twitch_chat/` — live chat rendered *inside the video window*, with real emote images.

Open `twitch.tv/<channel>` or `kick.com/<channel>` in mpv and chat appears down the right side. Works fullscreen. Works on a second monitor. No browser.

### Why it's an image and not text

libass (mpv's subtitle renderer) **cannot inline images**. Any ASS-based chat overlay is text-only, which means no emotes — and on Twitch that's most of the conversation.

So this doesn't use ASS. `chat_render.py` connects to chat, composites the whole visible chat column — bold coloured usernames, white outlined text, inline emote bitmaps — into a raw **BGRA** buffer with Pillow, and `main.lua` blits it with mpv's `overlay-add` (the same mechanism thumbfast uses for thumbnails).

Two hard-won details baked in:

- **`overlay-add` with `bgra` expects *premultiplied* alpha.** Feeding straight alpha makes every semi-transparent emote edge glow magenta. Every RGB channel is multiplied by alpha before writing.
- **Overwriting a `.bgra` file while mpv is reading it crashes the player.** Each frame is written to a fresh filename; only frame *n−2* is deleted.

Overlay ID is **63** (thumbfast owns 42; mpv rejects IDs above 63).

### Twitch

Connects to Twitch IRC as an anonymous `justinfan` guest — **read-only, no token, no login, nothing to leak**. Native emotes come from the IRC `emotes` tag; 7TV, BetterTTV and FrankerFaceZ are fetched globally at startup and per-channel once the `room-id` arrives.

### Kick

Kick chat isn't IRC. The script resolves the chatroom via `kick.com/api/v2/channels/<slug>`, then connects to Kick's public Pusher WebSocket and subscribes to `chatrooms.<id>.v2`. Native Kick emotes arrive inline as `[emote:<id>:<name>]` tokens. Third-party support on Kick is 7TV only — BTTV and FFZ return 404 there. Needs `websocket-client` installed into the bundled Python.

### Rendering

- **2× supersampled text** — the text layer renders at double size and downscales with LANCZOS, so outlines are clean instead of crunchy.
- **Animated emotes** — the `.gif` variant is pulled from 7TV/BTTV for true frame timings. A cached static base is composited with just the moving emote frames at 12fps, so animation is cheap.
- **Full-height column**, bottom-anchored — new messages push up, old ones scroll off the top. Height re-pushes on window resize and fullscreen toggle.
- **Live resizing with no reconnect** — Python watches the options file's mtime and rebuilds the renderer in place.
- **Changes persist.** Every live tweak rewrites the matching line in `script-opts/twitch_chat.conf`, so your sizing survives a restart.

### Configuration — `script-opts/twitch_chat.conf`

| Option | Default | Meaning |
|---|---|---|
| `enabled` | `yes` | Auto-show when a stream loads |
| `channel` | *(blank)* | Force a channel; blank = auto-detect from URL |
| `platform` | *(blank)* | `twitch` / `kick`; blank = auto-detect |
| `position` | `right` | Which side the column sits on |
| `margin` | `24` | Gap from the screen edge, px |
| `width` | `420` | Column width, px |
| `font_px` | `20` | Text size, px |
| `emote_scale` | `1.8` | Emote height as a multiple of text size |
| `height_frac` | `1.0` | Column height as a fraction of the player (1.0 = full) |
| `line_ratio` | `1.5` | Line height = `font_px` × this |
| `outline` | `0` | Outline thickness; 0 = auto-scale |
| `max_messages` | `60` | Message buffer |
| `bg_opacity` | `0.0` | Panel behind the text; 0 = fully transparent (OLED-safe) |
| `supersample` | `2` | Text render scale; set 1 to save CPU |
| `anim_fps` | `12` | Animated emote frame rate |
| `emotes` | `yes` | 7TV/BTTV/FFZ on/off (native emotes always render) |
| `font_regular` / `font_bold` | Segoe UI | Point at a Roobert `.ttf` for the exact Twitch look |
| `python` | *(blank)* | Path to `python.exe`; blank = use the bundled one |

| Key | Action |
|---|---|
| `Alt+C` | Toggle chat overlay |
| Menu → Live Chat | Bigger/smaller text, bigger/smaller emotes, wider/narrower column, swap side, auto-show, reconnect |
| Menu → Live Chat → **Show Status** | Diagnostics — detected channel, Python path, whether frames are generating, dump of `error.log` |

**If chat doesn't appear, run Show Status first.** Nine times out of ten it's that mpv wasn't restarted after installing the script.

---

## AI upscaling & frame interpolation — how the models actually work

This is the part people get confused by, so here's the whole chain.

### The pipeline

```
video frame
   ↓
mpv decodes it (hwdec=auto-copy)
   ↓
vf=vapoursynth  ──►  a .vpy script  ──►  k7sfunc  ──►  vsmlrt  ──►  TensorRT
   ↓                                                                   ↓
   └───────────────── upscaled/interpolated frame ◄──────── your NVIDIA GPU
   ↓
GLSL shaders (glsl-shaders) run on the result
   ↓
screen
```

Each layer:

| Layer | What it is |
|---|---|
| **`vf=vapoursynth`** | mpv's video filter that hands frames to a VapourSynth script. Bound to keys via `vf toggle vapoursynth="~~/vs/…​.vpy"`. |
| **`.vpy`** | A tiny Python script — the files in `vs/`. Sets resolution limits, GPU index, thread count, picks the model. This is the file you edit to tune things. |
| **`k7sfunc`** | hooke007's helper library. Wraps the messy parts: `FMT_CTRL` (pixel format/resolution guards), `UAI_NV_TRT` (generic ONNX upscaler), `CUGAN_NV`, `RIFE_NV`, `FPS_CTRL`. |
| **`vsmlrt`** | The ML runtime bridge. Takes an `.onnx` model and runs it through a backend — here, TensorRT. |
| **TensorRT** | NVIDIA's inference engine. Compiles the ONNX graph into a hardware-specific **`.engine`** file. |

### The `.engine` files — why the first run is slow

An `.onnx` file is a portable description of a neural network. TensorRT doesn't run it directly; it **compiles** it into an `.engine` optimised for one specific combination of:

- your exact GPU model
- your driver version
- your TensorRT version
- the input resolution range
- fp16 / int8 quantisation settings

**That compile takes minutes.** The first time you press `F1`, mpv will appear to hang — it's building an engine. It's cached in `vs-plugins/models/` as a hash-named `.engine`, and every subsequent run is instant.

This is also exactly why **`.engine` files are excluded from this repo.** Mine total ~1.2 GB and are worthless on your machine. Yours build themselves.

> If you update your GPU driver, engines may be invalidated and rebuild once. That's normal.

**Static vs dynamic engines** (`St_Eng` in the `.vpy` files):
- `St_Eng = False` (default) — a *dynamic* engine that handles a range of resolutions. One build covers everything. Slightly slower, uses roughly double the VRAM budget.
- `St_Eng = True` — a *static* engine locked to one resolution. Faster and leaner, but a new build per source resolution. Use this if you're VRAM-starved, then tune `Ws_Size`.

### Upscaling models — `vs/Upscale/`

| Preset | Model | Best for |
|---|---|---|
| `ESRGAN_FAST_AnimeJaNaiV3L1` | `animejanaiV3-HD-L1.onnx` | Anime, fastest |
| `ESRGAN_MEDIUM_AnimeJaNaiV3L2` | `animejanaiV3-HD-L2.onnx` | Anime, balanced |
| `ESRGAN_HEAVY_AnimeJaNaiV3L3` | `animejanaiV3-HD-L3.onnx` | Anime, best quality — **the main one** |
| `ESRGAN_HEAVY_AnimeJaNaiV3L3_4K` / `_8K` | same model, higher `H_Max` | Chained for 4K/8K output |
| `ESRGAN_*_AnimeJaNaiV2L1/2/3` | `animejanaiV2L*.onnx` | V2 line — softer, sometimes kinder to bad sources |
| `ESRGAN_Light_RealESRGANv2_animevideo_xsx2` | `RealESRGANv2-animevideo-xsx2.onnx` | Anime video, 2×, light |
| `ESRGAN_HEAVY_RealESRGANv2_animevideo_xsx4` | `…xsx4.onnx` | Anime video, 4× |
| `ESRGAN_HEAVIEST_realesr_animevideov3` | `realesr-animevideov3.onnx` | Heaviest anime preset |
| `CUSTOM_ESRGAN_REAL_realesr_RealESRGAN_x2plus` / `x4plus` | `RealESRGAN_x2plus.onnx` / `RealESRGAN-x4plus.onnx` | **Live action / real footage** |
| `CUGAN_HEAVY_pro_nodenoise_up2x` | `pro-no-denoise-up2x.onnx` | Anime, clean sources |
| `CUGAN_HEAVIEST_pro_denoise3x_up2x` | `pro-denoise3x-up2x.onnx` | Anime, noisy/compressed sources |
| `CUGAN_PSYCHO_pro_denoise3x_up3x` | `pro-denoise3x-up3x.onnx` | 3× — will melt your GPU |
| `CUSTOM_Adore` | `2x_Adore_renarchi_fp16.onnx` | General-purpose 2× |

**Picking one:** anime → AnimeJaNai V3 L3. Anime that's noisy or a bad rip → CUGAN with denoise. Live action → RealESRGAN x2plus/x4plus. Anything that stutters → drop to L1/L2 or use GLSL shaders instead.

### Key `.vpy` options you'll actually want to change

Open any file in `vs/Upscale/` — the tunables are at the top:

```python
H_Pre  = 720     # pre-downscale source to this height before the model runs.
                 # THE performance dial. 720 is safe; 1080 is much heavier.
Lt_Hd  = False   # True = also process sources above 720p
Model  = "animejanaiV3-HD-L3.onnx"
Gpu    = 0       # GPU index (0 = first)
Gpu_T  = 2       # GPU threads, 1–4. Higher = faster but more VRAM
St_Eng = False   # static engine — see above
Ws_Size= 0       # VRAM cap in MiB. 0 = unlimited
H_Max  = 1440    # output height cap — SET THIS TO YOUR MONITOR HEIGHT
```

For CUGAN there's also `Nr_Lv` (denoise level `-1`–`3`, `-1` = off) and `Sharp_Lv` (`0.0`–`2.0`).

### Frame interpolation — `vs/FrameInterpolation/`

RIFE turns 24fps into 48/60/72fps by **generating** intermediate frames from optical flow, not by duplicating them.

| Preset | Model | Multiplier |
|---|---|---|
| `RIFE_LIGHT_4_6` | RIFE 4.6 | 2× |
| `RIFE_LIGHT_x3_4_6` | RIFE 4.6 | 3× |
| `RIFE_MEDIUM_4_25_Lite` | RIFE 4.25 Lite | 2× |
| `RIFE_MEDIUM_x3_4_25_Lite` | RIFE 4.25 Lite | 3× |
| `RIFE_HEAVY_4_26` | RIFE 4.26 | 2× |
| `RIFE_HEAVY_x3_4_26` | RIFE 4.26 | 3× |

Options:

```python
H_Pre   = 1440   # pre-downscale height — set to your monitor height
Model   = 4251   # 46 | 4251 | 426 | 4262
Fps_Num = 2      # multiplier numerator (2 = double framerate)
Sc_Mode = 1      # scene-change detection: 0 off, 1/2 on.
                 # Leave ON — without it, cuts produce smeared garbage frames
Gpu_T   = 2      # GPU threads
```

**VFR handling:** these presets detect variable-framerate sources and convert to CFR first, snapping to 23.976 / 29.97 / 59.94 where appropriate. RIFE on a VFR source without this produces judder.

**Note:** `mpv.conf` sets `video-sync = display-resample` and `interpolation = yes`, and `profiles.conf` has a `[vsync_auto]` profile that automatically disables mpv's own interpolation when container fps is above 32 or playback speed isn't 1×. That's there so mpv's interpolation and RIFE don't fight each other.

### Cleaning presets — `vs/Cleaning/`

| Preset | Key | What it does |
|---|---|---|
| `MIX_UVR_MAD_NGU_AA_Artifact_Removal` | `Ctrl+Shift+!` | Anti-aliasing and artifact removal |
| `NR_BM3D_NV_HighestQuality_Denoise` | `Ctrl+Shift+@` | BM3D denoise — very heavy, very good |
| `NR_CCD_STD_ColorFilm_Grain_Removal` | `Ctrl+Shift+#` | Colour/film grain removal |
| `ETC_DEINT_EX_Super_Deinterlacing` | `Ctrl+Shift+$` | Deinterlacing for old broadcast sources |

### Getting the model weights

`.onnx` files go in `vs-plugins/models/`, matching the subfolder layout the `.vpy` files expect (`CuGan/`, `ArtCNN/`, `drba/`, and loose files at the root).

| Model family | Source |
|---|---|
| AnimeJaNai V2 / V3 | [the-database/mpv-upscale-2x_animejanai](https://github.com/the-database/mpv-upscale-2x_animejanai) |
| Real-ESRGAN / RealESRGANv2-animevideo | [xinntao/Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) |
| Real-CUGAN | [bilibili/ailab](https://github.com/bilibili/ailab) — or the [vsmlrt model release](https://github.com/AmusementClub/vs-mlrt/releases) |
| ArtCNN | [Artoriuz/ArtCNN](https://github.com/Artoriuz/ArtCNN) |
| RIFE | Bundled with [vs-mlrt](https://github.com/AmusementClub/vs-mlrt/releases) |

The [vs-mlrt releases page](https://github.com/AmusementClub/vs-mlrt/releases) has a bundled model pack that covers most of these in one download — easiest option.

---

## GLSL shaders

Shaders run **after** the VapourSynth stage, on the GPU, in mpv's own render pipeline. They cost far less than the AI models and work on **any** GPU — this is your path if you're not on NVIDIA.

| Key | Shader | Type |
|---|---|---|
| `` Ctrl+` `` | **Clear all shaders** | — |
| `Ctrl+1` | Ani4Kv2 ArtCNN C4F32 | Luma upscale |
| `Ctrl+2` | AniSD ArtCNN C4F32 | Luma upscale (SD sources) |
| `Ctrl+3` | FSRCNNX x2 16 | Luma upscale |
| `Ctrl+4` | NNEDI3 nns128 | Luma upscale (classic, heavy) |
| `Ctrl+5` | CfL Prediction RT | Chroma |
| `Ctrl+6` | AMD FSR EASU RGB RT | Main scaler |
| `Ctrl+7` | Anime4K Restore CNN L | Main |
| `Ctrl+8` | Anime4K Upscale GAN x2 M | Main |
| `Ctrl+9` | Adaptive Sharpen RT | Output sharpening |
| `Ctrl+0` | **Anime4K AIO optQ** | All-in-one — start here |
| `Ctrl+[` / `Ctrl+]` | Anime4K Clamp Highlights + Restore CNN VL chains | Main |

`mpv.conf` loads `hdeband.glsl` (debanding) and `adaptive_sharpen_RT.glsl` by default on every file.

> **Note:** `glsl-shaders` and `volume` are persisted globally by `save_global_props.lua`. If a shader change doesn't seem to take, delete `saved-props.json`.

---

## NVIDIA RTX VSR & True HDR

Driver-level features exposed through mpv's `d3d11vpp` filter. RTX 20-series or newer, enabled in the NVIDIA Control Panel.

| Key | Action |
|---|---|
| `,` | **RTX Video Super Resolution** (`d3d11vpp=scale=2:scaling-mode=nvidia`) |
| `.` | **RTX True HDR** — converts SDR content to HDR (`d3d11vpp=nvidia-true-hdr`) |

`Custom_NVIDIA_RTX_HDR.lua` exists because **True HDR must be the last filter in the chain** or the output is wrong. The script watches the `vf` property and silently moves `d3d11vpp=nvidia-true-hdr` back to the end whenever anything else is added. You never have to think about ordering.

### HDR handling

`profiles.conf` has an `[HDR_generic]` profile that auto-applies when `video-params/sig-peak > 1`:

```ini
hdr-reference-white  = 100
hdr-peak-percentile  = 99.99
blend-subtitles      = no
```

`Ctrl+Wheel Up/Down` adjusts target peak brightness in 250-nit steps (commented out by default in `input_uosc.conf` — uncomment lines 173–174 to enable).

---

## VR / 360° video

`scripts/mpv360.lua`. Options in `script-opts/mpv360.conf`.

| Key | Action |
|---|---|
| `Ctrl+E` | Toggle 360 / VR mode |
| `Ctrl+Shift+P` | Cycle projection (equirectangular, fisheye, …) |
| `Ctrl+Shift+E` | Switch eye — left / right / both (stereoscopic) |
| `Ctrl+Shift+S` | Cycle sampling quality |
| `Ctrl+R` | Reset view |
| `Ctrl+Click` | Toggle mouse-look |
| `Ctrl+T` | Show controls help |
| `Esc` | Exit mouse-look |

> The non-toggle bindings only exist **while 360 mode is on**. That's by design.

---

## Picture-in-Picture / phone mode

`scripts/Custom_Phone_PiP_Mode.lua` — for vertical video and always-on-top corner playback.

| Key | Action |
|---|---|
| `Ctrl+A` | Toggle PiP / phone mode (auto-orient) |
| `Ctrl+S` | Snap to left edge |
| `Ctrl+D` | Snap to right edge |

`input_plus.lua` also provides a `pip_dummy` binding that shrinks the window to a percentage of the screen (default 20%).

---

## Full hotkey reference

Everything below is also in the **right-click menu**, organised into submenus. If you remember one thing, remember right-click.

### Loading & navigation

| Key | Action |
|---|---|
| `Ctrl+Shift+V` | Load clipboard URL — YouTube, magnet, direct link, anything |
| `Ctrl+Shift+M` | Paste & play magnet from clipboard |
| `Wheel Up` / `Wheel Down` | Previous / next playlist item (skips headers) |
| `Mouse Back` / `Forward` | Previous / next |
| `Middle click` / `Right click` | uosc menu |
| `Ctrl+Right click` | Native context menu |
| `Double click` | Fullscreen |

### Playback

| Key | Action |
|---|---|
| `,` / `.` | Previous / next frame |
| `l` | Set / clear A-B loop |
| `[` / `]` | Cycle speed down / up (2 → 1.5 → 1.2 → 1) |
| `{` / `}` | Speed ∓0.1 |
| `-` / `=` | Volume ∓1 |
| `c` / `v` | Audio delay ∓100ms |
| `z` / `x` | Subtitle delay ∓100ms |
| `Shift+Backspace` | Reset audio & subtitle sync |

### Frame interpolation

| Key | Preset |
|---|---|
| `!` | Light — RIFE 4.6 (2×) |
| `@` | Medium — RIFE 4.25 Lite (2×) |
| `#` | Heavy — RIFE 4.26 (2×) |
| `$` | Light ×3 |
| `%` | Medium ×3 |
| `^` | Heavy ×3 |

### Super resolution

| Key | Preset |
|---|---|
| `&` `*` `(` | AnimeJaNai V2 — Lite / Medium / Heavy |
| `)` `_` `+` | AnimeJaNai V3 — Lite / Medium / Heavy |
| `N` / `M` | AnimeJaNai V3 Heavy — 4K / 8K |
| `{` / `}` / `\|` | RealESRGAN AnimeVideo — Light x2 / Heaviest v3 / Heavy x4 |
| `?` / `Z` | RealESRGAN x4plus / x2plus (**live action**) |
| `:` / `"` | CUGAN Heavy (no denoise) / Heaviest (denoise 3×) |

### Combined presets — the good stuff

| Key | Stack |
|---|---|
| `F1` | AnimeJaNaiV3L3 ×1 + Ani4Kv2 ArtCNN + Anime4K AIO + FSR RT + adaptive sharpen |
| `F2` | AnimeJaNaiV3L3 ×2 (for <1080p) + same shader stack |
| `F3` | AnimeJaNaiV3L3 4K ×2 (for <1080p) + same |
| `F4` | AnimeJaNaiV3L3 ×3 (for <1080p) + ArtCNN + FSR + sharpen |
| `F5` | AnimeJaNaiV3L3 ×1 + **RIFE ×2** + full shader stack |
| `F6` | AnimeJaNaiV3L3 ×1 + **RIFE ×3** + full shader stack |
| `F7` | AnimeJaNaiV3L3 ×2 + RIFE ×2 + full stack |
| `F8` | AnimeJaNaiV3L3 4K ×2 + RIFE ×2 + full stack |
| `Ctrl+Shift+~` | **General 1080p** — ESRGANv2 x2 + Anime4K AIO (good default for non-anime) |
| `Ctrl+Alt+Shift+A` | AnimeJaNaiV3 + RIFE 4.6 + Anime4K AIO |
| `Ctrl+Alt+Shift+S` | RIFE 4.6 + Anime4K AIO |
| `Ctrl+Alt+Shift+D` | RIFE 4.6 ×3 |
| `Ctrl+Alt+Shift+F` | ESRGAN 8K ×4 |
| `Ctrl+Alt+Shift+G` | ESRGAN 4K ×2 |
| `Ctrl+Alt+Shift+Z` | RIFE + NVIDIA RTX VSR + AMD FSR |

> Every one of these is a **toggle** — press again to turn it off. `` Ctrl+` `` clears all shaders.

### Everything else

| Key | Action |
|---|---|
| `Alt+C` | Toggle live chat overlay |
| `Ctrl+E` | Toggle VR / 360 mode |
| `Ctrl+A` / `Ctrl+S` / `Ctrl+D` | PiP toggle / snap left / snap right |
| `,` / `.` (menu → NVIDIA) | RTX VSR / RTX True HDR |
| `Alt+Wheel` | Cursor-centric zoom |
| `Alt+Left drag` | Pan image |
| `Ctrl+Shift+F8` | Add torrent folder to RD cloud |
| `Ctrl+Shift+Alt+Z` | Clear RD cache |

---

## File map

```
portable_config/
├── mpv.conf                       Core config — gpu-next, hwdec, OSD, subs, screenshots
├── profiles.conf                  Conditional auto-profiles (HDR, deband, vsync, debrid)
├── script-opts.conf               Options for uosc, thumbfast, console, stats
├── input_uosc.conf                THE hotkey + right-click menu file
├── input_contextmenu_plus.conf    Native context menu definition
│
├── fonts/                         LXGW WenKai Mono, Material Icons, uosc textures
│
├── script-opts/
│   ├── realdebrid.conf.example    ← copy to realdebrid.conf, add your token
│   ├── twitch_chat.conf           Chat overlay settings
│   └── mpv360.conf                VR / 360 settings
│
├── scripts/
│   ├── uosc/                              The UI
│   ├── twitch_chat/                       Live chat (main.lua + chat_render.py)
│   ├── Custom_Torrent_Real_Derbid_Streaming.lua   .torrent → Real-Debrid
│   ├── Custom_Torrent_Magnet_Streaming.lua        magnet → Real-Debrid
│   ├── Custom_Torrent_Unified_Navigation.lua      wheel nav + header skipping
│   ├── Custom_Bulk_STRM_Files_Player.lua          .strm playlists
│   ├── Custom_NVIDIA_RTX_HDR.lua                  keeps True HDR last in the vf chain
│   ├── Custom_Phone_PiP_Mode.lua                  PiP / vertical mode
│   ├── Custom_Hide_uosc_In_Jellyfin_Browser.lua   hides uosc in the Jellyfin shim
│   ├── mpv360.lua                                 VR / 360
│   ├── thumbfast.lua                              seekbar thumbnails
│   ├── contextmenu_plus.lua                       native menu
│   ├── input_plus.lua                             extra commands (chapters, imports, PiP)
│   └── save_global_props.lua                      persists volume + shader state
│
├── shaders/                       30+ GLSL — Anime4K/, QCOM/, Disabled/, root
│
├── vs/
│   ├── Upscale/                   ESRGAN, AnimeJaNai, CUGAN, Adore
│   ├── FrameInterpolation/        RIFE 4.6 / 4.25 / 4.26, 2× and 3×
│   ├── Images/                    Still-image upscaling
│   ├── Cleaning/                  Denoise, deinterlace, grain, AA
│   └── Disabled/                  Alternate backends (DML, MIGX) — AMD/Intel paths
│
└── Turned Off Scritps/            Parking lot — includes an unfinished TorBox streamer
```

### Config files worth knowing about

**`profiles.conf`** — conditional profiles that fire on their own:

| Profile | Trigger | Effect |
|---|---|---|
| `[HDR_generic]` | `sig-peak > 1` | HDR reference white 100, peak percentile 99.99 |
| `[deband_bitrate]` | bitrate ≤ 3000 kbps | Auto-enable debanding on low-bitrate files |
| `[vsync_auto]` | fps > 32, or speed ≠ 1× | Disables mpv interpolation so it doesn't fight RIFE |
| `[save_props_auto]` | ≥90% watched, or ≤5 min long | Don't save a resume position |
| `[audio_DolbyAtmos]` | filename contains `.Atmos.` | Passthrough `eac3,truehd` |
| `[debrid_resilience]` | https path that isn't Twitch/Kick/`.m3u8` | ffmpeg reconnect options for flaky debrid links |
| `[speed_limit1/2]` | speed <0.1 or >8 | Clamps playback speed |

> ⚠️ **`[debrid_resilience]` is deliberately scoped.** Putting those ffmpeg `reconnect=1` options **globally** in `mpv.conf` breaks live HLS — Twitch and Kick streams die with `hls: Failed to reload playlist` because a normal CDN connection close triggers a reconnect-at-byte-0 loop. Keep the profile condition intact.

---

## Troubleshooting

**"Real-Debrid: no API token set"**
`script-opts/realdebrid.conf` is missing or still says `YOUR_TOKEN_HERE`. See [Real-Debrid setup](#real-debrid-setup-do-this-first).

**A torrent double-click does nothing / `Unsupported URL: real-debrid.com/d/…`**
Expired RD links. v21 recovers automatically — give it a moment. If it persists, `Ctrl+Shift+Alt+Z` to clear the cache and reopen.

**A magnet sits at "Fetching metadata… (0 seeders)"**
Dead magnet. No seeders means Real-Debrid can't cache it either. That's the seeder counter doing its job.

**mpv freezes the first time I press F1**
It's compiling a TensorRT engine. Takes minutes. Once. See [the models section](#the-engine-files--why-the-first-run-is-slow).

**AI upscaling does nothing / errors out**
In order: are you on NVIDIA? Is the `.onnx` in `vs-plugins/models/`? Does the filename in the `.vpy` match exactly? Are you out of VRAM (lower `H_Pre`, or set `St_Eng = True` and cap `Ws_Size`)?

**Stuttering with an upscale preset on**
Your GPU can't keep up. Lower `H_Pre`, drop to a Lite model, or use GLSL shaders (`Ctrl+0`) instead.

**Chat overlay doesn't show**
Menu → Live Chat → **Show Status**. Usually mpv just needs a restart after installing. Check `error.log` in the workdir that Status prints. For Kick, make sure `websocket-client` is installed into the bundled Python.

**Emotes have magenta/glowing edges**
Premultiplied-alpha bug — should be fixed. If you've modified `chat_render.py`, check `to_bgra_premult()` is still being applied.

**Twitch stream dies partway through**
Twitch URLs from yt-dlp expire when ad-break tokens rotate. Only re-resolving via yt-dlp recovers it; no config option fixes this. Reload the file.

**Shader changes don't stick**
`save_global_props.lua` persists `volume` and `glsl-shaders`. Delete `saved-props.json` to reset.

**A right-click menu entry does nothing**
uosc only picks up commented-out menu lines when the key is exactly `#` (one character) and the comment starts with `#!`. A `##` prefix is ignored by both mpv and uosc.

---

## Credits

Nearly all the groundwork here is other people's, and it's very good work:

- **[hooke007 — MPV_lazy / mpv_PlayKit](https://github.com/hooke007/MPV_lazy)** — the base preset, `k7sfunc`, the `.vpy` structure, `input_plus`, `contextmenu_plus`, `save_global_props`. The backbone of this whole thing.
- **[tomasklaen — uosc](https://github.com/tomasklaen/uosc)** — the UI
- **[po5 — thumbfast](https://github.com/po5/thumbfast)** — seekbar thumbnails, and the `overlay-add` pattern the chat overlay is built on
- **[AmusementClub — vs-mlrt](https://github.com/AmusementClub/vs-mlrt)** — the TensorRT/ONNX bridge
- **[bloc97 — Anime4K](https://github.com/bloc97/Anime4K)** — the shaders
- **[the-database — AnimeJaNai](https://github.com/the-database/mpv-upscale-2x_animejanai)** — the anime upscaling models
- **[xinntao — Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN)**, **[bilibili — Real-CUGAN](https://github.com/bilibili/ailab)**, **[Artoriuz — ArtCNN](https://github.com/Artoriuz/ArtCNN)** — models
- **[hzwer — RIFE](https://github.com/hzwer/Practical-RIFE)** — frame interpolation
- **[VapourSynth](https://www.vapoursynth.com/)** and **[mpv](https://mpv.io/)** themselves
- **7TV / BetterTTV / FrankerFaceZ** — emote APIs

The custom Lua (Real-Debrid streaming, magnet streaming, live chat, unified navigation, `.strm` handling, PiP, RTX HDR ordering) is mine.

---

## A note on the config

This is a **personal setup** that grew organically. Some of it is opinionated, some of it is held together with tape, and the folder is literally named `Turned Off Scritps`. It's shared because people asked, not because it's a polished product.

You will probably want to change `H_Max` in the `.vpy` files to your monitor height, and `H_Pre` to whatever your GPU can survive. Start there.

If something breaks, the right-click menu and `input_uosc.conf` are where everything is defined — it's all readable plain text.
