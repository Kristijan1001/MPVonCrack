-- Custom_Hide_uosc_In_Jellyfin_Browser.lua
--
-- Hides uosc while the Jellyfin MPV Shim's in-window library browser (mpvtk)
-- is on screen, so uosc's idle logo / OSC bars don't bleed through behind the
-- browser UI.
--
-- NON-DESTRUCTIVE and inert for normal use: it only reacts to the
-- `user-data/mpvtk/active` flag that the shim's renderer sets (true while the
-- browser owns the window, false/absent otherwise). During ordinary playback
-- and streaming that flag is never set, so uosc behaves exactly as before.
-- When the flag clears, uosc is re-enabled. Uses uosc's own `disable-elements`
-- message, scoped to THIS script's name, so it never clobbers uosc's or
-- another script's element state.

local mp = require 'mp'

-- Elements suppressed while the browser is up. `idle_indicator` is the big
-- centered play-button/logo shown when nothing is playing (the thing bleeding
-- through the library); the rest are the OSC bars, which the browser replaces
-- with its own controls.
local HIDE = table.concat({
    'idle_indicator', 'audio_indicator', 'controls', 'timeline',
    'volume', 'speed', 'top_bar',
}, ',')

mp.observe_property('user-data/mpvtk/active', 'native', function(_, active)
    -- OSC bars: uosc's manager-controlled elements (controls, timeline, ...).
    mp.commandv('script-message-to', 'uosc', 'disable-elements',
                mp.get_script_name(), active and HIDE or '')
    -- The idle logo (the purple mpv logo + "mpv-lazy" text) is a STANDALONE
    -- element gated by uosc's `idlescreen` state, not the element manager, so
    -- disable-elements can't touch it. Toggle it with uosc's own message
    -- instead (2nd arg = no_osd, suppresses the on-screen flash).
    mp.commandv('script-message-to', 'uosc', 'osc-idlescreen',
                active and 'no' or 'yes', 'yes')
end)
