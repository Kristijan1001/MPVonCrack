#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
chat_render.py - Twitch chat -> rendered image bridge for the twitch_chat mpv script.

Connects to Twitch IRC anonymously (read-only, no login), pulls emote maps from
Twitch-native tags + 7TV + BetterTTV + FrankerFaceZ (global + channel), and
renders the visible chat block -- anu-styled text (2x supersampled for crisp
outlines) WITH inline emotes, including ANIMATED gif/webp emotes -- into raw
BGRA frames that mpv blits with `overlay-add`.

Design for cheap animation: the text + static emotes are composited once into a
cached "base" image; an animation thread only copies that base and pastes the
current frame of each animated emote, so per-frame cost stays tiny.

Outputs into <outdir>:
    frame_<n>.bgra   raw BGRA pixels (stride = w*4)
    meta.json        {"counter", "file", "w", "h", "animating"}
Options are read from <opts_path> (argv[4]) and re-read live when it changes,
so size/width/height tweaks apply without reconnecting.

Usage:  pythonw chat_render.py <channel> <outdir> [<parent_pid>] [<opts_path>]
"""

import sys
import os
import io
import json
import time
import socket
import random
import re
import threading
import ctypes
import urllib.request

from PIL import Image, ImageDraw, ImageFont, ImageChops

TAG_RE = re.compile(r'^@([^ ]+) +(.*)$')
MSG_RE = re.compile(r'^:([^!]+)![^ ]+ +PRIVMSG +#[^ ]+ +:(.*)$', re.S)
UA = {'User-Agent': 'mpv-twitch-chat/2.0'}

OPTS = {
    'platform': 'twitch',    # 'twitch' or 'kick'
    'width': 420,
    'font_px': 20,
    'emote_scale': 1.8,      # emote height = font_px * this (bigger emotes vs text)
    'max_msgs': 60,          # buffer size; the column shows as many as fit
    'line_ratio': 1.5,
    'outline': 0,            # 0 = auto (scales with font)
    'pad': 8,
    'height': 0,             # 0 = size to content; >0 = fixed full-height column
    'supersample': 2,        # text render scale for crisp outlines
    'anim_fps': 12,
    'bg_opacity': 0.0,
    'emotes_3rd_party': True,
    'font_regular': r'C:\Windows\Fonts\segoeui.ttf',
    'font_bold': r'C:\Windows\Fonts\seguisb.ttf',
}

MAX_EMOTE_FRAMES = 150


def to_bgra_premult(img):
    """RGBA PIL image -> premultiplied BGRA bytes for mpv's overlay-add.
    mpv treats overlay 'bgra' as premultiplied alpha; feeding straight alpha
    makes semi-transparent emote edges glow (halos), so premultiply here."""
    r, g, b, a = img.split()
    return Image.merge('RGBA', (
        ImageChops.multiply(b, a),
        ImageChops.multiply(g, a),
        ImageChops.multiply(r, a),
        a,
    )).tobytes('raw', 'RGBA')


def load_opts(path):
    if not path:
        return
    try:
        with open(path, 'r', encoding='utf-8') as f:
            OPTS.update(json.load(f))
    except Exception:
        pass


def pid_alive(pid):
    if not pid:
        return True
    try:
        k32 = ctypes.windll.kernel32
        h = k32.OpenProcess(0x1000, False, pid)
        if not h:
            return False
        code = ctypes.c_ulong()
        k32.GetExitCodeProcess(h, ctypes.byref(code))
        k32.CloseHandle(h)
        return code.value == 259
    except Exception:
        return True


# ---------------- emote maps + sprite cache ----------------

class Emotes:
    def __init__(self):
        self.by_name = {}       # word -> url (gif url for animated)
        self.cache = {}         # url -> sprite dict or None
        self.lock = threading.Lock()
        self.dirty = threading.Event()
        self.want = []
        self.want_lock = threading.Lock()
        self._emote_h = 28

    def set_emote_h(self, h):
        # changing target size invalidates cached sprite scaling
        if h != self._emote_h:
            self._emote_h = h
            with self.lock:
                self.cache.clear()

    def _get_json(self, url):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=8) as r:
                return json.loads(r.read().decode('utf-8', 'replace'))
        except Exception:
            return None

    def load_global(self):
        d = self._get_json('https://7tv.io/v3/emote-sets/global')
        if d and 'emotes' in d:
            for e in d['emotes']:
                anim = bool(e.get('data', {}).get('animated'))
                self.by_name.setdefault(e['name'], self._seventv_url(e['id'], anim))
        d = self._get_json('https://api.betterttv.net/3/cached/emotes/global')
        if isinstance(d, list):
            for e in d:
                self.by_name.setdefault(e['code'], 'https://cdn.betterttv.net/emote/%s/2x' % e['id'])
        d = self._get_json('https://api.frankerfacez.com/v1/set/global')
        if d and 'sets' in d:
            for s in d['sets'].values():
                for e in s.get('emoticons', []):
                    url = self._ffz_url(e)
                    if url:
                        self.by_name.setdefault(e['name'], url)

    def load_channel(self, room_id, login):
        d = self._get_json('https://7tv.io/v3/users/twitch/%s' % room_id)
        if d and d.get('emote_set') and d['emote_set'].get('emotes'):
            for e in d['emote_set']['emotes']:
                anim = bool((e.get('data') or {}).get('animated'))
                self.by_name[e['name']] = self._seventv_url(e['id'], anim)
        d = self._get_json('https://api.betterttv.net/3/cached/users/twitch/%s' % room_id)
        if isinstance(d, dict):
            for key in ('channelEmotes', 'sharedEmotes'):
                for e in d.get(key, []):
                    self.by_name[e['code']] = 'https://cdn.betterttv.net/emote/%s/2x' % e['id']
        d = self._get_json('https://api.frankerfacez.com/v1/room/id/%s' % room_id)
        if d and 'sets' in d:
            for s in d['sets'].values():
                for e in s.get('emoticons', []):
                    url = self._ffz_url(e)
                    if url:
                        self.by_name[e['name']] = url

    def load_channel_kick(self, user_id):
        # 7TV channel emotes for a Kick channel (BTTV/FFZ don't serve Kick)
        d = self._get_json('https://7tv.io/v3/users/kick/%s' % user_id)
        if d and d.get('emote_set') and d['emote_set'].get('emotes'):
            for e in d['emote_set']['emotes']:
                anim = bool((e.get('data') or {}).get('animated'))
                self.by_name[e['name']] = self._seventv_url(e['id'], anim)

    @staticmethod
    def _seventv_url(eid, animated):
        # gif for animated (Pillow gets real frame durations), webp for static
        return 'https://cdn.7tv.app/emote/%s/2x.%s' % (eid, 'gif' if animated else 'webp')

    @staticmethod
    def _ffz_url(e):
        urls = e.get('urls') or {}
        u = urls.get('2') or urls.get('1') or urls.get('4')
        if not u:
            return None
        return ('https:' + u) if u.startswith('//') else u

    def start_worker(self, parent_pid):
        threading.Thread(target=self._worker, args=(parent_pid,), daemon=True).start()

    def _worker(self, parent_pid):
        while True:
            if parent_pid and not pid_alive(parent_pid):
                return
            url = None
            with self.want_lock:
                if self.want:
                    url = self.want.pop(0)
            if url is None:
                time.sleep(0.05)
                continue
            with self.lock:
                if url in self.cache:
                    continue
            sprite = self._download(url)
            with self.lock:
                self.cache[url] = sprite
            self.dirty.set()

    def _download(self, url):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=8) as r:
                data = r.read()
            im = Image.open(io.BytesIO(data))
            n = getattr(im, 'n_frames', 1)
            frames, durs = [], []
            eh = self._emote_h
            for i in range(min(n, MAX_EMOTE_FRAMES)):
                try:
                    im.seek(i)
                except EOFError:
                    break
                fr = im.convert('RGBA')
                w, h = fr.size
                if h != eh and h > 0:
                    nw = max(1, round(w * eh / h))
                    # resize in premultiplied-alpha space ('RGBa') so transparent
                    # pixels' colour (often a magenta/black matte) can't bleed into
                    # the anti-aliased edges as a halo.
                    fr = fr.convert('RGBa').resize((nw, eh), Image.LANCZOS).convert('RGBA')
                frames.append(fr)
                durs.append(im.info.get('duration') or 40)
            if not frames:
                return None
            return {'frames': frames, 'durs': durs, 'total': sum(durs),
                    'w': frames[0].size[0], 'h': frames[0].size[1]}
        except Exception:
            return None

    def get(self, url):
        with self.lock:
            if url in self.cache:
                return self.cache[url]
        with self.want_lock:
            if url not in self.want:
                self.want.append(url)
        return None


# ---------------- message parsing ----------------

def parse_tags(s):
    out = {}
    for kv in s.split(';'):
        if '=' in kv:
            k, v = kv.split('=', 1)
            out[k] = v
    return out


def native_ranges(emotes_tag):
    ranges = []
    if emotes_tag:
        for part in emotes_tag.split('/'):
            if ':' not in part:
                continue
            eid, rs = part.split(':', 1)
            for r in rs.split(','):
                if '-' in r:
                    a, b = r.split('-')
                    try:
                        ranges.append((int(a), int(b), eid))
                    except ValueError:
                        pass
    ranges.sort()
    return ranges


KICK_EMOTE_RE = re.compile(r'\[emote:(\d+):([^\]]*)\]')


def build_segments_kick(content, by_name, use_3p):
    """Kick messages embed native emotes as [emote:<id>:<name>]; the rest is text
    (with 3rd-party emotes matched by word)."""
    result = []
    pos = 0

    def add_text(chunk):
        for tok in re.split(r'(\s+)', chunk):
            if tok == '':
                continue
            if use_3p and tok.strip() and tok in by_name:
                result.append(('emote', by_name[tok], tok))
            else:
                result.append(('text', tok))

    for m in KICK_EMOTE_RE.finditer(content):
        if m.start() > pos:
            add_text(content[pos:m.start()])
        result.append(('emote',
                       'https://files.kick.com/emotes/%s/fullsize' % m.group(1),
                       m.group(2) or 'emote'))
        pos = m.end()
    if pos < len(content):
        add_text(content[pos:])
    return result


def build_segments(text, emotes_tag, by_name, use_3p):
    ranges = native_ranges(emotes_tag)
    result = []
    n = len(text)
    pos = 0
    ni = 0
    while pos < n:
        if ni < len(ranges) and ranges[ni][0] == pos:
            a, b, eid = ranges[ni]
            result.append(('emote',
                           'https://static-cdn.jtvnw.net/emoticons/v2/%s/default/dark/2.0' % eid,
                           text[a:b + 1]))
            pos = b + 1
            ni += 1
        else:
            nxt = ranges[ni][0] if ni < len(ranges) else n
            for tok in re.split(r'(\s+)', text[pos:nxt]):
                if tok == '':
                    continue
                if use_3p and tok.strip() and tok in by_name:
                    result.append(('emote', by_name[tok], tok))
                else:
                    result.append(('text', tok))
            pos = nxt
    return result


# ---------------- colors ----------------

def hex_to_rgb(h):
    if not h or len(h) < 7:
        return None
    try:
        return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))
    except ValueError:
        return None


PALETTE = [(255, 76, 76), (76, 175, 80), (33, 150, 243), (255, 152, 0),
           (156, 39, 176), (0, 188, 212), (233, 30, 99), (139, 195, 74),
           (255, 193, 7), (124, 77, 255)]


def name_color(name, tag_color):
    c = hex_to_rgb(tag_color)
    if c:
        return c
    h = 0
    for ch in name:
        h = (h * 31 + ord(ch)) % 2147483647
    return PALETTE[h % len(PALETTE)]


# ---------------- renderer ----------------

class Renderer:
    def __init__(self, opts, emotes):
        self.o = dict(opts)
        self.em = emotes
        self.ss = max(1, int(opts.get('supersample', 2)))
        self.font_px = int(opts['font_px'])
        self.line_h = int(round(self.font_px * opts['line_ratio']))
        self.emote_h = max(8, int(round(self.font_px * float(opts.get('emote_scale', 1.8)))))
        self.outline = int(opts['outline']) or max(1, round(self.font_px / 12))
        self.font = ImageFont.truetype(opts['font_regular'], self.font_px * self.ss)
        try:
            self.font_b = ImageFont.truetype(opts['font_bold'], self.font_px * self.ss)
        except Exception:
            self.font_b = self.font
        self.em.set_emote_h(self.emote_h)
        self._scratch = ImageDraw.Draw(Image.new('RGBA', (4, 4)))

    def _tw(self, s, bold):
        # measured at supersample scale, converted back to 1x
        f = self.font_b if bold else self.font
        return int(round(self._scratch.textlength(s, font=f) / self.ss))

    def _atoms(self, m):
        atoms = []
        col = name_color(m['name'], m['color'])
        atoms.append(('name', m['name'], self._tw(m['name'], True), col))
        atoms.append(('text', ': ', self._tw(': ', False), None))
        for seg in m['segments']:
            if seg[0] == 'emote':
                spr = self.em.get(seg[1])
                if spr is not None:
                    atoms.append(('emote', spr, spr['w'], None))
                    atoms.append(('text', ' ', self._tw(' ', False), None))
                else:
                    atoms.append(('text', seg[2] + ' ', self._tw(seg[2] + ' ', False), None))
            else:
                for w in re.split(r'(\s+)', seg[1]):
                    if w == '':
                        continue
                    atoms.append(('text', w, self._tw(w, False), None))
        return atoms

    def _wrap(self, atoms, maxw):
        lines, cur, x = [], [], 0
        for a in atoms:
            w = a[2]
            if x + w > maxw and cur:
                lines.append(cur)
                cur, x = [], 0
                if a[0] == 'text' and a[1].strip() == '':
                    continue
            cur.append((a, x))
            x += w
        if cur:
            lines.append(cur)
        return lines

    def build(self, messages):
        """Return (base_rgba, anim_list). anim_list = [{'x','y','sprite'}]."""
        o = self.o
        W = int(o['width'])
        pad = int(o['pad'])
        maxw = W - pad * 2
        ss = self.ss
        lh = self.line_h

        # wrapped lines, each with its own height so tall emotes get room
        lh_list = []
        for m in messages:
            for ln in self._wrap(self._atoms(m), maxw):
                max_e = max([a[1]['h'] for (a, x) in ln if a[0] == 'emote'], default=0)
                lh_list.append((ln, max(lh, max_e + 2)))

        fixed_h = int(o.get('height') or 0)
        if fixed_h > 0:
            H = fixed_h
            avail = H - pad * 2
            kept, used = [], 0
            for pair in reversed(lh_list):
                if used + pair[1] > avail and kept:
                    break
                kept.append(pair)
                used += pair[1]
            kept.reverse()
            lh_list = kept
            block_h = sum(h for _, h in lh_list)
            y0 = H - pad - block_h
        else:
            block_h = sum(h for _, h in lh_list)
            H = max(lh, block_h + pad * 2)
            y0 = pad

        bg_a = int(255 * float(o.get('bg_opacity', 0.0)))
        base = Image.new('RGBA', (W, H), (0, 0, 0, bg_a))

        # --- text layer at supersample, then downscale onto base ---
        tW, tH = W * ss, H * ss
        tlayer = Image.new('RGBA', (tW, tH), (0, 0, 0, 0))
        td = ImageDraw.Draw(tlayer)
        anim = []
        white = (255, 255, 255, 255)
        black = (0, 0, 0, 255)
        ow = self.outline * ss

        y = y0
        for line, h_i in lh_list:
            cy = y + h_i // 2
            for (a, x) in line:
                px = pad + x
                kind = a[0]
                if kind == 'emote':
                    spr = a[1]
                    ey = cy - spr['h'] // 2
                    if len(spr['frames']) > 1:
                        anim.append({'x': px, 'y': ey, 'sprite': spr})  # composited later
                    else:
                        base.alpha_composite(spr['frames'][0], (px, ey))
                elif kind == 'name':
                    td.text((px * ss, cy * ss), a[1], font=self.font_b, fill=a[3] + (255,),
                            anchor='lm', stroke_width=ow, stroke_fill=black)
                else:
                    td.text((px * ss, cy * ss), a[1], font=self.font, fill=white,
                            anchor='lm', stroke_width=ow, stroke_fill=black)
            y += h_i

        tlayer = tlayer.convert('RGBa').resize((W, H), Image.LANCZOS).convert('RGBA')
        base.alpha_composite(tlayer)
        return base, anim


# ---------------- frame index for animation ----------------

def frame_index(sprite, t_ms):
    total = sprite['total'] or 1
    tt = t_ms % total
    acc = 0
    for i, d in enumerate(sprite['durs']):
        acc += d
        if tt < acc:
            return i
    return len(sprite['frames']) - 1


# ---------------- chat sources ----------------

def run_twitch(channel, parent_pid, emotes, add_msg):
    nick = 'justinfan%d' % random.randint(10000, 99999)
    room_loaded = [False]
    last_pid_check = 0.0
    while True:
        if parent_pid and not pid_alive(parent_pid):
            return
        try:
            s = socket.create_connection(('irc.chat.twitch.tv', 6667), timeout=10)
            s.sendall(b'CAP REQ :twitch.tv/tags twitch.tv/commands\r\n')
            s.sendall(('NICK %s\r\n' % nick).encode())
            s.sendall(('JOIN #%s\r\n' % channel).encode())
            s.settimeout(1.0)
            buf = ''
            while True:
                if parent_pid:
                    now = time.time()
                    if now - last_pid_check > 2:
                        last_pid_check = now
                        if not pid_alive(parent_pid):
                            try:
                                s.close()
                            except Exception:
                                pass
                            return
                try:
                    data = s.recv(4096)
                    if not data:
                        break
                    buf += data.decode('utf-8', 'replace')
                except socket.timeout:
                    continue
                except OSError:
                    break
                while '\r\n' in buf:
                    line, buf = buf.split('\r\n', 1)
                    if line.startswith('PING'):
                        try:
                            s.sendall(b'PONG :tmi.twitch.tv\r\n')
                        except OSError:
                            break
                        continue
                    rest = line
                    tags = {}
                    mt = TAG_RE.match(line)
                    if mt:
                        tags = parse_tags(mt.group(1))
                        rest = mt.group(2)
                    if not room_loaded[0] and tags.get('room-id'):
                        room_loaded[0] = True
                        threading.Thread(target=emotes.load_channel,
                                         args=(tags['room-id'], channel), daemon=True).start()
                    mm = MSG_RE.match(rest)
                    if mm:
                        user = mm.group(1)
                        text = mm.group(2).rstrip()
                        if text.startswith('\x01ACTION ') and text.endswith('\x01'):
                            text = text[8:-1]
                        name = tags.get('display-name') or user
                        color = tags.get('color') or ''
                        segs = build_segments(text, tags.get('emotes', ''),
                                              emotes.by_name, OPTS['emotes_3rd_party'])
                        add_msg(name, color, segs)
        except Exception:
            pass
        for _ in range(3):
            if parent_pid and not pid_alive(parent_pid):
                return
            time.sleep(1)


KICK_UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
           '(KHTML, like Gecko) Chrome/126.0 Safari/537.36')
KICK_PUSHER_KEY = '32cbd69e4b950bf97679'


def run_kick(slug, parent_pid, emotes, add_msg):
    try:
        import websocket  # websocket-client
    except Exception:
        raise RuntimeError('websocket-client not installed (pip install websocket-client)')

    # resolve chatroom id (+ user id for 7TV channel emotes) via Kick's API
    chatroom_id = user_id = None
    for _ in range(6):
        if parent_pid and not pid_alive(parent_pid):
            return
        try:
            req = urllib.request.Request('https://kick.com/api/v2/channels/%s' % slug,
                                         headers={'User-Agent': KICK_UA, 'Accept': 'application/json'})
            data = json.loads(urllib.request.urlopen(req, timeout=12).read())
            chatroom_id = (data.get('chatroom') or {}).get('id')
            user_id = data.get('user_id')
            if chatroom_id:
                break
        except Exception:
            time.sleep(2)
    if not chatroom_id:
        raise RuntimeError('could not resolve kick chatroom for ' + slug)
    if user_id:
        threading.Thread(target=emotes.load_channel_kick, args=(user_id,), daemon=True).start()

    wsurl = ('wss://ws-us2.pusher.com/app/%s?protocol=7&client=js&version=8.4.0&flash=false'
             % KICK_PUSHER_KEY)
    last_pid_check = 0.0
    while True:
        if parent_pid and not pid_alive(parent_pid):
            return
        try:
            ws = websocket.create_connection(
                wsurl, timeout=15,
                header=['Origin: https://kick.com', 'User-Agent: ' + KICK_UA])
            ws.recv()  # pusher:connection_established
            ws.send(json.dumps({'event': 'pusher:subscribe',
                                'data': {'channel': 'chatrooms.%s.v2' % chatroom_id}}))
            ws.settimeout(1.0)
            while True:
                if parent_pid:
                    now = time.time()
                    if now - last_pid_check > 2:
                        last_pid_check = now
                        if not pid_alive(parent_pid):
                            try:
                                ws.close()
                            except Exception:
                                pass
                            return
                try:
                    raw = ws.recv()
                except websocket.WebSocketTimeoutException:
                    continue
                except Exception:
                    break
                if not raw:
                    continue
                try:
                    ev = json.loads(raw)
                except Exception:
                    continue
                name = ev.get('event', '')
                if name == 'pusher:ping':
                    try:
                        ws.send(json.dumps({'event': 'pusher:pong', 'data': {}}))
                    except Exception:
                        break
                    continue
                if 'ChatMessage' in name:
                    try:
                        d = json.loads(ev.get('data', '{}'))
                    except Exception:
                        continue
                    sender = d.get('sender') or {}
                    uname = sender.get('username') or '?'
                    color = (sender.get('identity') or {}).get('color') or ''
                    segs = build_segments_kick(d.get('content', '') or '',
                                               emotes.by_name, OPTS['emotes_3rd_party'])
                    add_msg(uname, color, segs)
        except Exception:
            pass
        for _ in range(3):
            if parent_pid and not pid_alive(parent_pid):
                return
            time.sleep(1)


# ---------------- main ----------------

def main():
    if len(sys.argv) < 3:
        return
    channel = sys.argv[1].lower().lstrip('#')
    outdir = sys.argv[2]
    parent_pid = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else None
    opts_path = sys.argv[4] if len(sys.argv) > 4 else None

    os.makedirs(outdir, exist_ok=True)
    load_opts(opts_path)
    try:
        with open(os.path.join(outdir, 'status.log'), 'w', encoding='utf-8') as f:
            f.write('started: channel=%s pid=%s\n' % (channel, parent_pid))
    except Exception:
        pass

    emotes = Emotes()
    emotes.start_worker(parent_pid)
    threading.Thread(target=emotes.load_global, daemon=True).start()

    messages = []
    msg_lock = threading.Lock()
    state = {'base': None, 'anim': [], 'W': 0, 'H': 0}
    state_lock = threading.Lock()
    counter = [0]
    render_dirty = threading.Event()
    render_dirty.set()

    renderer = [Renderer(OPTS, emotes)]
    start_t = time.time()

    def write_frame(img, animating):
        w, h = img.size
        counter[0] += 1
        n = counter[0]
        fname = 'frame_%d.bgra' % n
        with open(os.path.join(outdir, fname), 'wb') as f:
            f.write(to_bgra_premult(img))
        with open(os.path.join(outdir, 'meta.json'), 'w', encoding='utf-8') as f:
            json.dump({'counter': n, 'file': fname, 'w': w, 'h': h,
                       'animating': animating}, f)
        old = os.path.join(outdir, 'frame_%d.bgra' % (n - 2))
        try:
            os.remove(old)
        except OSError:
            pass

    def rebuild():
        with msg_lock:
            msgs = list(messages)
        base, anim = renderer[0].build(msgs)
        with state_lock:
            state['base'], state['anim'] = base, anim
            state['W'], state['H'] = base.size
        if os.environ.get('TC_DEBUG_PNG'):
            base.save(os.path.join(outdir, 'debug.png'))
        if not anim:
            write_frame(base, False)

    # render worker: throttled rebuilds (expensive text render)
    def render_worker():
        while True:
            if parent_pid and not pid_alive(parent_pid):
                return
            render_dirty.wait()
            render_dirty.clear()
            try:
                rebuild()
            except Exception:
                pass
            time.sleep(1.0 / 8)

    # animation worker: cheap per-frame compositing of the cached base
    def anim_worker():
        while True:
            if parent_pid and not pid_alive(parent_pid):
                return
            with state_lock:
                base = state['base']
                anim = state['anim']
            if base is None or not anim:
                time.sleep(0.1)
                continue
            t_ms = (time.time() - start_t) * 1000.0
            frame = base.copy()
            for a in anim:
                spr = a['sprite']
                frame.alpha_composite(spr['frames'][frame_index(spr, t_ms)], (a['x'], a['y']))
            try:
                write_frame(frame, True)
            except Exception:
                pass
            time.sleep(1.0 / max(1, int(OPTS.get('anim_fps', 12))))

    # emote downloads -> mark dirty
    def dirty_watch():
        while True:
            if parent_pid and not pid_alive(parent_pid):
                return
            if emotes.dirty.wait(timeout=1.0):
                emotes.dirty.clear()
                render_dirty.set()

    # live opts reload
    def opts_watch():
        last = None
        while True:
            if parent_pid and not pid_alive(parent_pid):
                return
            try:
                mt = os.path.getmtime(opts_path) if opts_path else None
            except OSError:
                mt = None
            if mt and mt != last:
                last = mt
                load_opts(opts_path)
                try:
                    renderer[0] = Renderer(OPTS, emotes)
                except Exception:
                    pass
                render_dirty.set()
            time.sleep(0.5)

    for fn in (render_worker, anim_worker, dirty_watch):
        threading.Thread(target=fn, daemon=True).start()
    if opts_path:
        threading.Thread(target=opts_watch, daemon=True).start()

    def add_msg(name, color, segments):
        with msg_lock:
            messages.append({'name': name, 'color': color, 'segments': segments})
            while len(messages) > OPTS['max_msgs']:
                messages.pop(0)
        render_dirty.set()

    if str(OPTS.get('platform', 'twitch')).lower() == 'kick':
        run_kick(channel, parent_pid, emotes, add_msg)
    else:
        run_twitch(channel, parent_pid, emotes, add_msg)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        try:
            import traceback
            _od = sys.argv[2] if len(sys.argv) > 2 else '.'
            os.makedirs(_od, exist_ok=True)
            with open(os.path.join(_od, 'error.log'), 'w', encoding='utf-8') as _f:
                _f.write(traceback.format_exc())
        except Exception:
            pass
