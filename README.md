# MPVonCrack

**An mpv build that upscales with neural nets, interpolates to 120fps, streams torrents through Real-Debrid without downloading them, and renders live Twitch/Kick chat with real emotes inside the video window.**

https://github.com/user-attachments/assets/e5842bfb-2501-4525-9f12-54b8a8405af3

Double-click a `.torrent` file → it plays. Paste a magnet → it plays. Open a Twitch link → chat appears next to the video. Hit `F1` → the anime you're watching gets run through a GAN in real time.

Built on [hooke007's mpv_PlayKit / MPV_lazy](https://github.com/hooke007/MPV_lazy) with a pile of custom Lua on top.

---

## ⬇️ Download

### **[→ Grab the latest release here ←](https://github.com/Kristijan1001/MPVonCrack/releases/latest)**

It's a **portable build** — no installer, nothing written to your registry, no dependencies to chase. Unpack it and run `mpv.exe`.

**What's in the download:**

| ✅ Included | |
|---|---|
| `mpv.exe` | The player itself, built with VapourSynth support |
| `yt-dlp.exe` | For YouTube / Twitch / Kick / everything else |
| Python + Pillow + numpy + websocket-client | **Bundled.** You don't install Python. You don't `pip install` anything. |
| All 56 AI models (`.onnx`) | AnimeJaNai V2/V3, Real-ESRGAN, Real-CUGAN, ArtCNN, RIFE — all of them |
| Every shader, script and config | The whole `portable_config` |
| VapourSynth plugins | `vstrt`, `vsort`, denoise/deinterlace filters, madVR |

**One thing you add yourself** — the NVIDIA CUDA/TensorRT runtime (3.3 GB, and *only* if you want the AI upscaling). [Two-step instructions below.](#step-2--add-the-cuda-runtime-nvidia-ai-features-only) Everything else — playback, torrents, chat overlay, GLSL shaders — works the second you unzip.

> Why isn't CUDA in the bundle? It's 3.3 GB of unmodified NVIDIA redistributables that would triple the download for everyone, including the people on AMD who can't use it. It's one copy-paste from upstream.

---

## Table of contents

- [What's in the box](#whats-in-the-box)
- [Requirements](#requirements)
- [Setup](#setup)
- [Real-Debrid setup](#real-debrid-setup)
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

| | |
|---|---|
| **OS** | Windows 10/11 (x64) |
| **Just watching video** | Any GPU. Works out of the box. |
| **GLSL shaders** (Anime4K, FSR, NNEDI3) | Any modern GPU — AMD, Intel or NVIDIA |
| **AI upscaling + RIFE** | **NVIDIA only**, RTX 20-series or newer. The `.vpy` presets use TensorRT. |
| **VRAM** | 6 GB minimum for 1080p→4K ESRGAN, 8 GB+ comfortable |
| **RTX VSR / True HDR** | RTX 20-series+, enabled in the NVIDIA Control Panel |
| **Real-Debrid** | A paid RD account + API token. Free accounts can't stream. |

**On AMD or Intel?** Everything works except the `vs/` AI presets. Use the GLSL shaders instead — Anime4K AIO (`Ctrl+0`) is genuinely excellent and costs a fraction of the performance.

---

## Setup

### Step 1 — Unpack and run

1. Download the release and extract it anywhere. A USB stick is fine — it's fully portable.
2. Run `mpv.exe`.
3. Right-click for the menu.

That's it. Playback, the right-click menu, GLSL shaders, the chat overlay, PiP and VR all work now.

### Step 2 — Add the CUDA runtime *(NVIDIA AI features only)*

Skip this if you're not going to use the neural upscaling or RIFE interpolation.

1. Go to [**vs-mlrt releases**](https://github.com/AmusementClub/vs-mlrt/releases/latest).
2. Download the archive with **`cuda`** in the filename (`vsmlrt-windows-x64-cuda…7z`). It's around 3.3 GB.
3. Open it and copy the **`vsmlrt-cuda`** folder into the `vs-plugins` folder of your MPVonCrack install:

   ```
   MPVonCrack/
   └── vs-plugins/
       ├── vstrt.dll          ← already there
       ├── models/            ← already there, models included
       └── vsmlrt-cuda/       ← you add this folder
   ```
4. Restart mpv. Press `F1` on a video.

> The first press of any AI preset will look like mpv has frozen for a few minutes. It hasn't — it's compiling a TensorRT engine for your specific GPU. This happens **once per preset**. [Full explanation here.](#the-engine-files--why-the-first-run-is-slow)

### Step 3 — Real-Debrid token *(torrent/magnet streaming only)*

See [the next section](#real-debrid-setup).

### Alternative: config only

Already have your own mpv + VapourSynth setup and just want the scripts and configs? Clone this repo and drop its `portable_config/` into your mpv folder, replacing yours. The models and CUDA runtime are on you.

```bash
git clone https://github.com/Kristijan1001/MPVonCrack.git
```

### What's *not* in the download

| Excluded | Why |
|---|---|
| `vsmlrt-cuda/` (3.3 GB) | Unmodified NVIDIA redistributables. Step 2 above. |
| `*.engine` (1.2 GB) | TensorRT engines are compiled for **one specific GPU, driver and TensorRT version**. Mine are useless on your machine, and yours build themselves automatically. |
| `_cache/`, watch-later history, `saved-props.json` | My personal playback state — resume positions, cached Real-Debrid links, saved volume. Not yours to inherit. |
| `script-opts/realdebrid.conf` | My API token. You add your own. |

---

## Real-Debrid setup

The torrent and magnet scripts do nothing without a token.

1. Log into Real-Debrid and open **https://real-debrid.com/apitoken**
2. Copy the token.
3. In `portable_config/script-opts/`, copy `realdebrid.conf.example` → `realdebrid.conf`
4. Set it:

   ```ini
   api_key=YOUR_TOKEN_HERE
   ```
5. Restart mpv.

**The token is never stored in a `.lua` file.** Both scripts call `load_rd_api_key()`, which reads `script-opts/realdebrid.conf`, then falls back to a `REALDEBRID_API_KEY` environment variable, then gives up with an on-screen error. `realdebrid.conf` is gitignored, so you can fork this and push without leaking anything.

> ⚠️ **If you ever paste a token directly into a `.lua` file and push it anywhere, revoke it.** Real-Debrid tokens don't expire on their own — go back to the API token page and generate a new one.

---

## Streaming torrents & magnets

Two scripts, one account, two entry points. Neither downloads anything to your disk — Real-Debrid holds the files and serves them over HTTP, and mpv seeks into them like a local file.

### `.torrent` files — `Custom_Torrent_Real_Derbid_Streaming.lua`

**Just double-click a `.torrent` file.** That's the whole workflow.

What happens under the hood:

1. **Read the folder.** Every `.torrent` in the same directory is picked up, not just the one you clicked — so a season folder becomes one playlist.
2. **Cache check.** `_cache/rdcache/rd_torrent_cache.json` is consulted first. A hit means playback starts instantly with zero API calls.
3. **On a miss**, the torrent is `PUT` to `torrents/addTorrent`, video/audio files are selected via `torrents/selectFiles` (filtered by extension, `trailer` excluded), and the resulting links are stored.
4. **A session `.m3u8` is written**, with each torrent name as a header row and its episodes nested under it.
5. **On playback**, the `on_load` hook calls `unrestrict/link` to turn the RD link into a real streamable URL.
6. **The torrent is deleted from your RD account** once links are extracted, so your RD torrent list doesn't fill up.

**Expired-link auto-recovery (v21):** Real-Debrid `/d/` links go stale. When one fails to unrestrict, the script re-adds that torrent to mint fresh links. If RD still has the content cached it recovers instantly and keeps playing; if not, it queues the caching and **skips ahead to the episodes that *are* ready**, so the playlist doesn't stall on one dead file. The on-disk cache is rewritten with the new links.

| Key | Action |
|---|---|
| `Ctrl+Shift+F8` | Add a whole folder of torrents to your RD cloud (pre-cache a season before bed) |
| `Ctrl+Shift+Alt+Z` | Clear the torrent link cache |
| Menu → Streaming | Show cache info |

### Magnet links — `Custom_Torrent_Magnet_Streaming.lua`

Four ways in:

1. **Paste it like a YouTube link.** `Ctrl+Shift+V` loads whatever's on your clipboard. Fastest path.
2. **`Ctrl+Shift+M`** — "Paste & Play Magnet". Handles several magnets at once.
3. **A `.magnet` text file** — one magnet per line, open it in mpv.
4. **A raw `magnet:?xt=...` URI** from the command line or a browser handler.

Because RD doesn't dedupe magnets by infohash, this script does extra work:

- **`find_existing_torrent(hash)`** queries `GET /torrents` *before* adding anything. If you already started caching this magnet in a previous session, it reattaches to that download instead of starting a duplicate from 0%.
- **Non-blocking resolution.** Caching runs on a timer-driven state machine polling every 2s for up to ~10 minutes. mpv stays fully responsive and shows `Caching on RD… 47% (12 seeders)` on screen. **The seeder count is displayed so a dead magnet is obvious immediately.**
- **It never deletes a torrent mid-download.** Only on success or a fatal status. A partially-cached magnet is left on RD so re-pasting later is instant.
- **Results don't hijack playback.** Start a normal video while a magnet caches in the background and the magnet won't steal the window when it finishes.

| Key | Action |
|---|---|
| `Ctrl+Shift+M` | Paste & play magnet from clipboard |
| `Ctrl+Shift+V` | Load clipboard URL (magnets, YouTube, anything) |
| Menu → Streaming | Show / clear magnet cache |

### Scroll-wheel navigation

Both scripts build playlists with **header rows** (the torrent/folder name) above their episodes. `Custom_Torrent_Unified_Navigation.lua` binds the mouse wheel to skip those headers automatically and forces a watch-later save before every jump — so your resume position in episode 3 survives scrolling to episode 4 and back.

| Input | Action |
|---|---|
| `Wheel Up` / `Wheel Down` | Previous / next item (skips headers) |
| `Mouse Back` / `Forward` | Previous / next |

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

Within a bucket it sorts naturally, so `Episode 2` comes before `Episode 10`.

It runs in **isolation mode**: it keeps a whitelist of URLs it created and refuses to touch any path it doesn't own, so it can never interfere with the torrent scripts.

---

## Live chat overlay — Twitch & Kick

`scripts/twitch_chat/` — live chat rendered *inside the video window*, with real emote images.

Open `twitch.tv/<channel>` or `kick.com/<channel>` in mpv and chat appears down the right side. Works fullscreen. Works on a second monitor. No browser.

**Nothing to install** — the Python runtime, Pillow and websocket-client all ship in the bundle.

### Why it's an image and not text

libass (mpv's subtitle renderer) **cannot inline images**. Any ASS-based chat overlay is text-only, which means no emotes — and on Twitch that's most of the conversation.

So this doesn't use ASS. `chat_render.py` connects to chat, composites the whole visible chat column — bold coloured usernames, white outlined text, inline emote bitmaps — into a raw **BGRA** buffer with Pillow, and `main.lua` blits it with mpv's `overlay-add` (the same mechanism thumbfast uses for its thumbnails).

Two hard-won details baked in:

- **`overlay-add` with `bgra` expects *premultiplied* alpha.** Feeding straight alpha makes every semi-transparent emote edge glow magenta. Every RGB channel is multiplied by alpha before writing.
- **Overwriting a `.bgra` file while mpv is reading it crashes the player.** Each frame is written to a fresh filename; only frame *n−2* is deleted.

Overlay ID is **63** (thumbfast owns 42; mpv rejects IDs above 63).

### Twitch

Connects to Twitch IRC as an anonymous `justinfan` guest — **read-only, no token, no login, nothing to leak**. Native emotes come from the IRC `emotes` tag; 7TV, BetterTTV and FrankerFaceZ are fetched globally at startup and per-channel once the `room-id` arrives.

### Kick

Kick chat isn't IRC. The script resolves the chatroom via `kick.com/api/v2/channels/<slug>`, then connects to Kick's public Pusher WebSocket and subscribes to `chatrooms.<id>.v2`. Native Kick emotes arrive inline as `[emote:<id>:<name>]` tokens. Third-party support on Kick is 7TV only — BTTV and FFZ return 404 there.

### Rendering

- **2× supersampled text** — the text layer renders at double size and downscales with LANCZOS, so outlines are clean instead of crunchy.
- **Animated emotes** — the `.gif` variant is pulled from 7TV/BTTV for true frame timings. A cached static base is composited with only the moving emote frames at 12fps, so animation stays cheap.
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
| `python` | *(blank)* | Blank = use the bundled Python. Leave it blank. |

| Key | Action |
|---|---|
| `Alt+C` | Toggle chat overlay |
| Menu → Live Chat | Bigger/smaller text, bigger/smaller emotes, wider/narrower column, swap side, auto-show, reconnect |
| Menu → Live Chat → **Show Status** | Diagnostics — detected channel, whether frames are generating, dump of `error.log` |

**If chat doesn't appear, run Show Status first.** Nine times out of ten mpv just needs a restart.

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

| Layer | What it is |
|---|---|
| **`vf=vapoursynth`** | mpv's video filter that hands frames to a VapourSynth script. Bound to keys via `vf toggle vapoursynth="~~/vs/…​.vpy"`. |
| **`.vpy`** | A tiny Python script — the files in `vs/`. Sets resolution limits, GPU index, thread count, picks the model. **This is the file you edit to tune things.** |
| **`k7sfunc`** | hooke007's helper library. Wraps the messy parts: `FMT_CTRL` (format/resolution guards), `UAI_NV_TRT` (generic ONNX upscaler), `CUGAN_NV`, `RIFE_NV`, `FPS_CTRL`. |
| **`vsmlrt`** | The ML runtime bridge. Takes an `.onnx` model and runs it through a backend — here, TensorRT. |
| **TensorRT** | NVIDIA's inference engine. Compiles the ONNX graph into a hardware-specific **`.engine`** file. |

### The `.engine` files — why the first run is slow

An `.onnx` file is a portable *description* of a neural network. TensorRT doesn't run it directly; it **compiles** it into an `.engine` optimised for one specific combination of:

- your exact GPU model
- your driver version
- your TensorRT version
- the input resolution range
- fp16 / int8 quantisation settings

**That compile takes minutes.** The first time you press `F1`, mpv will appear to hang. It's building an engine. It gets cached in `vs-plugins/models/` as a hash-named `.engine`, and every subsequent run is instant.

This is exactly why **`.engine` files aren't in the download.** Mine total 1.2 GB and are worthless on your machine. Yours build themselves.

> If you update your GPU driver, engines may be invalidated and rebuild once. Normal.

**Static vs dynamic engines** (`St_Eng` in the `.vpy` files):
- `St_Eng = False` *(default)* — a **dynamic** engine handling a range of resolutions. One build covers everything. Slightly slower, roughly double the VRAM budget.
- `St_Eng = True` — a **static** engine locked to one resolution. Faster and leaner, but rebuilds per source resolution. Use this if you're VRAM-starved, then tune `Ws_Size`.

### Upscaling models — `vs/Upscale/`

All of these are **already in the download**. Nothing to fetch.

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

**Picking one:** anime → AnimeJaNai V3 L3. Anime that's noisy or a bad rip → CUGAN with denoise. Live action → RealESRGAN x2plus/x4plus. Anything that stutters → drop to L1/L2, or use GLSL shaders instead.

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

CUGAN also has `Nr_Lv` (denoise level `-1`–`3`, `-1` = off) and `Sharp_Lv` (`0.0`–`2.0`).

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

```python
H_Pre   = 1440   # pre-downscale height — set to your monitor height
Model   = 4251   # 46 | 4251 | 426 | 4262
Fps_Num = 2      # multiplier (2 = double framerate)
Sc_Mode = 1      # scene-change detection: 0 off, 1/2 on.
                 # LEAVE THIS ON — without it, cuts produce smeared garbage frames
Gpu_T   = 2      # GPU threads
```

**VFR handling:** these presets detect variable-framerate sources and convert to CFR first, snapping to 23.976 / 29.97 / 59.94 where appropriate. RIFE on a VFR source without this judders badly.

**Note:** `mpv.conf` sets `video-sync = display-resample` and `interpolation = yes`, and `profiles.conf` has a `[vsync_auto]` profile that automatically disables mpv's own interpolation when container fps is above 32 or playback speed isn't 1×. That's there so mpv's interpolation and RIFE don't fight each other.

### Cleaning presets — `vs/Cleaning/`

| Preset | Key | What it does |
|---|---|---|
| `MIX_UVR_MAD_NGU_AA_Artifact_Removal` | `Ctrl+Shift+!` | Anti-aliasing and artifact removal |
| `NR_BM3D_NV_HighestQuality_Denoise` | `Ctrl+Shift+@` | BM3D denoise — very heavy, very good |
| `NR_CCD_STD_ColorFilm_Grain_Removal` | `Ctrl+Shift+#` | Colour/film grain removal |
| `ETC_DEINT_EX_Super_Deinterlacing` | `Ctrl+Shift+$` | Deinterlacing for old broadcast sources |

### Adding your own models

Drop an `.onnx` into `vs-plugins/models/`, copy any `vs/Upscale/*.vpy`, and change the `Model = "…"` line to your filename. Good hunting grounds: [OpenModelDB](https://openmodeldb.info/), [the-database/AnimeJaNai](https://github.com/the-database/mpv-upscale-2x_animejanai), [xinntao/Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN), [Artoriuz/ArtCNN](https://github.com/Artoriuz/ArtCNN).

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
| `Ctrl+0` | **Anime4K AIO optQ** | All-in-one — **start here** |
| `Ctrl+[` / `Ctrl+]` | Anime4K Clamp Highlights + Restore CNN VL chains | Main |

`mpv.conf` loads `hdeband.glsl` (debanding) and `adaptive_sharpen_RT.glsl` on every file by default.

> `glsl-shaders` and `volume` are persisted by `save_global_props.lua`. If a shader change doesn't seem to take, delete `saved-props.json`.

---

## NVIDIA RTX VSR & True HDR

Driver-level features exposed through mpv's `d3d11vpp` filter. RTX 20-series or newer, enabled in the NVIDIA Control Panel. **No CUDA runtime needed for these.**

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

`Ctrl+Wheel Up/Down` adjusts target peak brightness in 250-nit steps — commented out by default, uncomment lines 173–174 in `input_uosc.conf` to enable.

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

> The non-toggle bindings only exist **while 360 mode is on**. By design.

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
MPVonCrack/
├── mpv.exe                        The player
├── yt-dlp.exe                     Stream extractor
├── python.exe  Lib/               Bundled Python + Pillow + numpy + websocket-client
├── vs-plugins/
│   ├── models/                    All 56 .onnx models (engines build here)
│   ├── vstrt.dll  vsort.dll       TensorRT / ONNX Runtime backends
│   └── vsmlrt-cuda/               ← you add this (see Setup step 2)
│
└── portable_config/
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
    │   ├── input_plus.lua                             extra commands
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

### Auto-profiles in `profiles.conf`

These fire on their own, no key needed:

| Profile | Trigger | Effect |
|---|---|---|
| `[HDR_generic]` | `sig-peak > 1` | HDR reference white 100, peak percentile 99.99 |
| `[deband_bitrate]` | bitrate ≤ 3000 kbps | Auto-enable debanding on low-bitrate files |
| `[vsync_auto]` | fps > 32, or speed ≠ 1× | Disables mpv interpolation so it doesn't fight RIFE |
| `[save_props_auto]` | ≥90% watched, or ≤5 min long | Don't save a resume position |
| `[audio_DolbyAtmos]` | filename contains `.Atmos.` | Passthrough `eac3,truehd` |
| `[debrid_resilience]` | https path that isn't Twitch/Kick/`.m3u8` | ffmpeg reconnect options for flaky debrid links |
| `[speed_limit1/2]` | speed <0.1 or >8 | Clamps playback speed |

> ⚠️ **`[debrid_resilience]` is deliberately scoped.** Putting those ffmpeg `reconnect=1` options **globally** in `mpv.conf` breaks live HLS — Twitch and Kick streams die with `hls: Failed to reload playlist`, because a normal CDN connection close triggers a reconnect-at-byte-0 loop. Keep the profile condition intact.

---

## Troubleshooting

**AI upscaling does nothing / errors out**
Did you do [Setup step 2](#step-2--add-the-cuda-runtime-nvidia-ai-features-only)? Without `vs-plugins/vsmlrt-cuda/` the AI presets can't load. Also: are you on NVIDIA? Out of VRAM (lower `H_Pre`, or set `St_Eng = True` and cap `Ws_Size`)?

**mpv freezes the first time I press F1**
It's compiling a TensorRT engine. Takes minutes. Once per preset. [Explanation.](#the-engine-files--why-the-first-run-is-slow)

**Stuttering with an upscale preset on**
Your GPU can't keep up. Lower `H_Pre`, drop to a Lite model, or use GLSL shaders (`Ctrl+0`) instead.

**"Real-Debrid: no API token set"**
`script-opts/realdebrid.conf` is missing or still says `YOUR_TOKEN_HERE`. See [Real-Debrid setup](#real-debrid-setup).

**A torrent double-click does nothing / `Unsupported URL: real-debrid.com/d/…`**
Expired RD links. v21 recovers automatically — give it a moment. If it persists, `Ctrl+Shift+Alt+Z` to clear the cache and reopen.

**A magnet sits at "Fetching metadata… (0 seeders)"**
Dead magnet. No seeders means Real-Debrid can't cache it either. That's the seeder counter doing its job.

**Chat overlay doesn't show**
Menu → Live Chat → **Show Status**. Usually mpv just needs a restart. Check the `error.log` path that Status prints.

**Emotes have magenta/glowing edges**
Premultiplied-alpha bug — should be fixed. If you've modified `chat_render.py`, check `to_bgra_premult()` is still applied.

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

The custom Lua — Real-Debrid streaming, magnet streaming, the live chat overlay, unified navigation, `.strm` handling, PiP, RTX HDR ordering — is mine.

mpv is GPLv2+; the bundled components keep their own licenses.

---

## A note on the config

This is a **personal setup** that grew organically. Some of it is opinionated, some of it is held together with tape, and there's a folder literally named `Turned Off Scritps`. It's shared because people asked, not because it's a polished product.

Two things worth changing on day one: `H_Max` in the `.vpy` files to your monitor height, and `H_Pre` to whatever your GPU can survive.

If something breaks, the right-click menu and `input_uosc.conf` are where everything is defined — it's all readable plain text.
