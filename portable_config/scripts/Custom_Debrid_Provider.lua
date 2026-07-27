-- Debrid Provider Switch
-- VERSION: 1.0
--
-- Owns the single setting that decides WHICH debrid service handles .torrent
-- files and magnet links: Real-Debrid or TorBox.
--
-- Why this exists: the Real-Debrid and TorBox streamers both hook "start-file"
-- on *.torrent and both call mp.command("stop") + rebuild the playlist. With
-- both live they fight over every torrent you open. Each streamer now asks
-- is_active() before doing anything, and only the selected one responds.
--
-- The setting lives in script-opts/debrid.conf so it survives restarts, and is
-- mirrored to the user-data/debrid/provider property so menus can show it.
--
-- Commands:
--   script-message debrid-cycle-provider        toggle RD <-> TorBox
--   script-message debrid-set-provider <name>   realdebrid | torbox
--   script-message debrid-show-provider         report the current one

local utils = require 'mp.utils'
local msg = require 'mp.msg'

local CONF = mp.command_native({"expand-path", "~~/script-opts/debrid.conf"})

local PROVIDERS = {
    realdebrid = "Real-Debrid",
    torbox     = "TorBox",
}
local DEFAULT = "realdebrid"

local function read_provider()
    local f = io.open(CONF, "r")
    if not f then return DEFAULT end
    for line in f:lines() do
        local v = line:match("^%s*provider%s*=%s*(%S+)")
        if v then
            v = v:lower()
            f:close()
            return PROVIDERS[v] and v or DEFAULT
        end
    end
    f:close()
    return DEFAULT
end

-- Rewrite only the provider= line, preserving the comments around it.
local function write_provider(name)
    local lines, found = {}, false
    local f = io.open(CONF, "r")
    if f then
        for line in f:lines() do
            if line:match("^%s*provider%s*=") then
                table.insert(lines, "provider=" .. name)
                found = true
            else
                table.insert(lines, line)
            end
        end
        f:close()
    end
    if not found then table.insert(lines, "provider=" .. name) end

    local out = io.open(CONF, "w")
    if not out then
        msg.error("Could not write " .. CONF)
        return false
    end
    out:write(table.concat(lines, "\n") .. "\n")
    out:close()
    return true
end

local current = read_provider()

local function publish()
    -- user-data is how the uosc menu and other scripts see the current value.
    mp.set_property("user-data/debrid/provider", current)
    mp.set_property("user-data/debrid/provider-label", PROVIDERS[current])
end

local function set_provider(name, quiet)
    name = (name or ""):lower()
    if not PROVIDERS[name] then
        mp.osd_message("Unknown debrid provider: " .. tostring(name), 3)
        return
    end
    current = name
    write_provider(name)
    publish()
    msg.info("Debrid provider set to " .. PROVIDERS[name])
    if not quiet then
        mp.osd_message("Debrid provider: " .. PROVIDERS[name], 3)
    end
end

mp.register_script_message("debrid-set-provider", function(name) set_provider(name) end)

mp.register_script_message("debrid-cycle-provider", function()
    set_provider(current == "realdebrid" and "torbox" or "realdebrid")
end)

mp.register_script_message("debrid-show-provider", function()
    mp.osd_message("Debrid provider: " .. PROVIDERS[current], 3)
end)

mp.add_key_binding(nil, "cycle-provider", function()
    set_provider(current == "realdebrid" and "torbox" or "realdebrid")
end)

publish()
msg.info("Debrid Provider Switch loaded (" .. PROVIDERS[current] .. ")")
