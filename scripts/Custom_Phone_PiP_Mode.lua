-- auto-orient.lua
-- Requires LuaJIT (MPV_lazy / shinchiro builds include it)

local ffi_ok, ffi = pcall(require, 'ffi')
if not ffi_ok then
    mp.osd_message("auto-orient: LuaJIT required (FFI not available)")
    return
end

ffi.cdef[[
    typedef void* HWND;
    typedef int   BOOL;
    typedef long  LONG;
    typedef struct { LONG left; LONG top; LONG right; LONG bottom; } RECT;
    BOOL GetWindowRect(HWND hwnd, RECT* lpRect);
    BOOL MoveWindow(HWND hwnd, int X, int Y, int nWidth, int nHeight, BOOL bRepaint);
]]
local user32 = ffi.load('user32')

local enabled          = false
local last_orientation = nil
local long_side        = nil
local snapped          = nil   -- nil | "left" | "right"
local saved            = {}
local saved_rect       = nil
local mpv_hwnd         = nil

mp.observe_property('window-id', 'number', function(_, val)
    if val then
        mpv_hwnd = ffi.cast('void*', ffi.cast('uintptr_t', val))
    else
        mpv_hwnd = nil
    end
end)

local function get_win_rect()
    if not mpv_hwnd then return nil end
    local r = ffi.new('RECT')
    if user32.GetWindowRect(mpv_hwnd, r) ~= 0 then
        return { left = r.left, top = r.top,
                 right = r.right, bottom = r.bottom }
    end
    return nil
end

local function save_properties()
    saved.ontop              = mp.get_property("ontop")
    saved.border             = mp.get_property("border")
    saved.title_bar          = mp.get_property("title-bar")
    saved.auto_window_resize = mp.get_property("auto-window-resize")
    saved.keepaspect_window  = mp.get_property("keepaspect-window")
    saved_rect = get_win_rect()
end

local function apply_phone_mode()
    mp.set_property("ontop",              "yes")
    mp.set_property("border",             "no")
    mp.set_property("title-bar",          "no")
    mp.set_property("auto-window-resize", "no")
    mp.set_property("keepaspect-window",  "yes")
end

local function restore_properties()
    if next(saved) == nil then return end
    mp.set_property("ontop",              saved.ontop)
    mp.set_property("border",             saved.border)
    mp.set_property("title-bar",          saved.title_bar)
    mp.set_property("keepaspect-window",  saved.keepaspect_window)
    mp.set_property("auto-window-resize", saved.auto_window_resize)
    if saved_rect and mpv_hwnd then
        local w = saved_rect.right  - saved_rect.left
        local h = saved_rect.bottom - saved_rect.top
        user32.MoveWindow(mpv_hwnd,
            saved_rect.left, saved_rect.top, w, h, 1)
    end
end

local function do_snap(side)
    if not mpv_hwnd then return end
    local rect = get_win_rect()
    if not rect then return end

    local screen_w = mp.get_property_number("display-width")
    local win_w    = rect.right  - rect.left
    local win_h    = rect.bottom - rect.top
    local win_y    = rect.top

    local new_x
    if side == "right" then
        new_x = math.floor(screen_w - win_w)
    else
        new_x = 0
    end

    user32.MoveWindow(mpv_hwnd, new_x, win_y, win_w, win_h, 1)
end

-- Keep long_side updated whenever the user manually resizes the window.
-- osd-width/osd-height fire on resize, so we track the larger dimension.
mp.observe_property("osd-width", "number", function(_, w)
    if not enabled then return end
    local h = mp.get_property_number("osd-height") or 0
    w = w or 0
    local new_long = math.max(w, h)
    if new_long > 0 then
        long_side = new_long
    end
end)

mp.register_event("file-loaded", function()
    if not enabled then return end
    local vw = mp.get_property_number("video-params/w")
    local vh = mp.get_property_number("video-params/h")
    if not vw or not vh then return end
    local orientation = (vh > vw) and "portrait" or "landscape"

    -- On first load just record orientation; long_side already set and
    -- kept up to date by the osd-width observer above.
    if last_orientation == nil then
        last_orientation = orientation
        return
    end

    -- Same orientation: no resize needed, long_side stays as-is.
    if orientation == last_orientation then
        last_orientation = orientation
        return
    end

    -- Orientation changed: resize to new_w x new_h preserving long_side.
    local aspect = vw / vh
    local new_w, new_h
    if orientation == "landscape" then
        new_w = long_side
        new_h = math.floor(long_side / aspect + 0.5)
    else
        new_h = long_side
        new_w = math.floor(long_side * aspect + 0.5)
    end

    if snapped and mpv_hwnd then
        local rect = get_win_rect()
        local win_y = rect and rect.top or 0
        local screen_w = mp.get_property_number("display-width")
        local new_x
        if snapped == "right" then
            new_x = math.floor(screen_w - new_w)
        else
            new_x = 0
        end
        user32.MoveWindow(mpv_hwnd, new_x, win_y, new_w, new_h, 1)
    else
        mp.set_property("geometry", new_w .. "x" .. new_h)
    end

    last_orientation = orientation
    long_side = math.max(new_w, new_h)
end)

mp.add_forced_key_binding("ctrl+a", "toggle-auto-orient", function()
    enabled = not enabled
    if enabled then
        save_properties()
        apply_phone_mode()
        -- Seed long_side from the real current window size
        local rect = get_win_rect()
        if rect then
            long_side = math.max(rect.right - rect.left, rect.bottom - rect.top)
        else
            local ww = mp.get_property_number("osd-width") or 0
            local wh = mp.get_property_number("osd-height") or 0
            long_side = math.max(ww, wh)
        end
        local vw = mp.get_property_number("video-params/w")
        local vh = mp.get_property_number("video-params/h")
        if vw and vh then
            last_orientation = (vh > vw) and "portrait" or "landscape"
        else
            last_orientation = nil
        end
        mp.osd_message("Auto-orient: ON")
    else
        restore_properties()
        last_orientation = nil
        long_side        = nil
        snapped          = nil
        saved            = {}
        saved_rect       = nil
        mp.osd_message("Auto-orient: OFF")
    end
end)

mp.add_forced_key_binding("ctrl+s", "snap-left", function()
    if snapped == "left" then
        snapped = nil
        mp.osd_message("Unsnapped")
    else
        snapped = "left"
        do_snap("left")
        mp.osd_message("Snapped: Left")
    end
end)

mp.add_forced_key_binding("ctrl+d", "snap-right", function()
    if snapped == "right" then
        snapped = nil
        mp.osd_message("Unsnapped")
    else
        snapped = "right"
        do_snap("right")
        mp.osd_message("Snapped: Right")
    end
end)