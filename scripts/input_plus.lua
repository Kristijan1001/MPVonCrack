--[[
Documentation_ https://github.com/hooke007/mpv_PlayKit/discussions/615

Shortcut command enhancement
]]

local mp = require "mp"
mp.options = require "mp.options"
mp.utils = require "mp.utils"

local user_opt = {
	load = true,
}
mp.options.read_options(user_opt)

if user_opt.load == false then
	mp.msg.info("Script disabled by initialization")
	return
end
-- Reason: Added fifth page to stats
local min_major = 0
local min_minor = 39
local min_patch = 0
local mpv_ver_curr = mp.get_property_native("mpv-version", "unknown")
local function incompat_check(full_str, tar_major, tar_minor, tar_patch)
	if full_str == "unknown" then
		return true
	end

	local clean_ver_str = full_str:gsub("^[^%d]*", "")
	local major, minor, patch = clean_ver_str:match("^(%d+)%.(%d+)%.(%d+)")
	major = tonumber(major)
	minor = tonumber(minor)
	patch = tonumber(patch or 0)
	if major < tar_major then
		return true
	elseif major == tar_major then
		if minor < tar_minor then
			return true
		elseif minor == tar_minor then
			if patch < tar_patch then
				return true
			end
		end
	end

	return false
end
if incompat_check(mpv_ver_curr, min_major, min_minor, min_patch) then
	mp.msg.warn("Current mpv version (" .. (mpv_ver_curr or "unknown") .. ") is lower than " .. min_major .. "." .. min_minor .. "." .. min_patch .. ", script terminated.")
	return
end

function round(n)
	return n + (2^52 + 2^51) - (2^52 + 2^51)
end



--
-- Variable Presets
--

local plat = mp.get_property_native("platform")

local adevicelist = {}
local target_ao = nil

local chap_skip = false
local chap_keywords = {
	"OP$", "opening$", "オープニング$",
	"ED$", "ending$", "エンディング$",
}

local cmds_sqnum = {}
local prop_tmp = ""

local osm = mp.create_osd_overlay("ass-events")
local osm_showing = false
local style_generic = "{\\rDefault\\fnConsolas\\fs20\\blur1\\bord2\\1c&HFFFFFF\\3c&H000000}"

local marked_aid_A = nil
local marked_aid_B = nil
local mark_aid_reg = false
local merged_aid = false

local ostime_msg = mp.create_osd_overlay("ass-events")
local ostime_showing = false
local ostime_style = "{\\rDefault\\fnmpv-osd-symbols\\fs30\\bord2\\an9\\alpha&H80\\1c&H01DBF1\\3c&H000000}"

local osd_hack = mp.create_osd_overlay("ass-events")
local osd_hack_freq = 1/60
osd_hack.data = "{\\rDefault\\an9\\alpha&HFF\\1c&HFFFFFF\\3c&HFFFFFF}" .. "FF"
local osd_hack_timer = nil

local scale_target = 0

local shuffled = false
local shuffling = false
local save_path = mp.command_native({"expand-path", "~~/"}) .. "/playlist_temp.mpl"

local pre_quit = false

local seek_dur_init = 0
local seek_dur_step = 1
local seek_dur = seek_dur_init

local spd_target = 3
local bak_speed = nil
local spd_adapt = false
local spd_iters_max = 10
local spd_delta_max = 0.5
local spd_delta_min = 0.0005

local show_page = 0



--
-- Function Settings
--

function adevicelist_pre(start)
	mp.set_property("audio-device", adevicelist[start].name)
	adevicelist[start].description = "■ " .. adevicelist[start].description
	local adevice_content = tostring("Audio Output Devices:\n")
	for items = 1, #adevicelist do
		if string.find(adevicelist[items].name, target_ao, 1, true) then
			if adevicelist[items].name ~= adevicelist[start].name then
				adevice_content = adevice_content .. "□ "
			end
			adevice_content = adevice_content .. adevicelist[items].description .. "\n"
		end
	end
	mp.osd_message(adevice_content, 2)
end
function adevicelist_pass(start, fin, step)
	while start ~= fin + step do
		if string.find(mp.get_property_native("audio-device"), adevicelist[start].name, 1, true) then
			while true do
				if start + step == 0 then
					start = #adevicelist + 1
				elseif start + step == #adevicelist + 1 then
					start = 0
				end
				start = start + step
				if string.find(adevicelist[start].name, target_ao, 1, true) then
					adevicelist_pre(start)
					return
				end
			end
		end
		start = start + step
	end
end
function adevicelist_fin(start, fin, step, dynamic)
	if dynamic then
		target_ao = ""
	else
		target_ao = mp.get_property_native("current-ao", "")
	end
	adevicelist_pass(start, fin, step)
end


function chap_skip_check(_, value)
	if not value then
		return
	end
	for _, words in pairs(chap_keywords) do
		if string.match(value, words) and chap_skip then
			mp.commandv("add", "chapter", 1)
			mp.msg.info("chap_skip_check skipped chapter")
		end
	end
end
function chap_skip_toggle()
	if chap_skip then
		mp.unobserve_property(chap_skip_check)
		chap_skip = false
		mp.osd_message("[input_plus] Skip intro/outro disabled", 1)
		return
	end
	mp.observe_property("chapter-metadata/TITLE", "string", chap_skip_check)
	chap_skip = true
	mp.osd_message("[input_plus] Skip intro/outro enabled", 1)
end

function chapter_seek_force(step, nat, uosc)
	if tonumber(step) >= 0 then
		step = 1
	else
		step = -1
	end
	local path = mp.get_property_native("path", "")
	if path == "" then
		return
	end
	local chapter_all = mp.get_property_number("chapters", 0)
	local chapter_act = mp.get_property_number("chapter", 0) + step
	if chapter_act < 0 then
		if uosc then
			mp.commandv("script-binding", "uosc/prev")
		else
			mp.commandv("playlist-prev", "weak")
		end
		if nat then
			mp.add_timeout(0.1, function()
				local path2 = mp.get_property_native("path", "")
				if path2 == path then
					return
				else
					local chapter_act2 = mp.get_property_number("chapters", 0) - 1
					print(chapter_act2)
					if chapter_act2 <= 0 then
						return
					else
						mp.commandv("set", "chapter", chapter_act2)
					end
				end
			end)
		end
	elseif chapter_act >= chapter_all then
		if uosc then
			mp.commandv("script-binding", "uosc/next")
		else
			mp.commandv("playlist-next", "weak")
		end
	else
		mp.commandv("add", "chapter", step)
	end
end


function cycle_cmds(...)
	local cmds_list = {...}
	local cur_cmd = table.concat(cmds_list, "|")
	cmds_sqnum[cur_cmd] = (cmds_sqnum[cur_cmd] or 0) % #cmds_list + 1
	mp.command(cmds_list[cmds_sqnum[cur_cmd]])
end


function import_via_dialog(config)
	if plat ~= "windows" then
		return
	end

	local was_ontop = mp.get_property_native("ontop")
	if was_ontop then mp.set_property_native("ontop", false) end

	local res = mp.utils.subprocess({
		args = {'powershell', '-NoProfile', '-Command', config.ps_script},
		cancellable = false,
	})

	if was_ontop then mp.set_property_native("ontop", true) end

	if res.status == 0 and res.stdout then
		config.handler(res.stdout)
	end
end
function get_file_dialog_ps(multiselect)
	return string.format([[& {
		Trap { Write-Error -ErrorRecord $_; Exit 1 }
		Add-Type -AssemblyName PresentationFramework
		$u8 = [System.Text.Encoding]::UTF8
		$out = [Console]::OpenStandardOutput()
		$ofd = New-Object -TypeName Microsoft.Win32.OpenFileDialog
		$ofd.Multiselect = %s
		If ($ofd.ShowDialog() -eq $true) {
			ForEach ($filename in $ofd.FileNames) {
				$u8filename = $u8.GetBytes("$filename`n")
				$out.Write($u8filename, 0, $u8filename.Length)
			}
		}
	}]], multiselect)
end
local import_configs = {
	files = {
		ps_script = get_file_dialog_ps("$true"),
		handler = function(stdout)
			local first_file = true
			for filename in string.gmatch(stdout, '[^\r\n]+') do
				local mode = first_file and "replace" or "append"
				mp.commandv("loadfile", filename, mode)
				first_file = false
			end
		end
	},

	dvd_iso = {
		ps_script = get_file_dialog_ps("$false"),
		handler = function(stdout)
			for filename in string.gmatch(stdout, '[^\r\n]+') do
				mp.commandv("set", "dvd-device", filename)
				mp.commandv("loadfile", "dvd://", "replace")
				break
			end
		end
	},

	bd_iso = {
		ps_script = get_file_dialog_ps("$false"),
		handler = function(stdout)
			for filename in string.gmatch(stdout, '[^\r\n]+') do
				mp.commandv("set", "bluray-device", filename)
				mp.commandv("loadfile", "bd://", "replace")
				break
			end
		end
	},

	audio = {
		ps_script = get_file_dialog_ps("$false"),
		handler = function(stdout)
			for filename in string.gmatch(stdout, '[^\r\n]+') do
				mp.commandv("audio-add", filename, "auto")
			end
		end
	},

	subtitle = {
		ps_script = get_file_dialog_ps("$false"),
		handler = function(stdout)
			for filename in string.gmatch(stdout, '[^\r\n]+') do
				mp.commandv("sub-add", filename, "cached")
			end
		end
	},

	url = {
		ps_script = [[& {
			Trap { Write-Error -ErrorRecord $_; Exit 1 }
			Add-Type -AssemblyName Microsoft.VisualBasic
			$u8 = [System.Text.Encoding]::UTF8
			$out = [Console]::OpenStandardOutput()
			$urlname = [Microsoft.VisualBasic.Interaction]::InputBox("Input URL", "Open", "https://")
			$u8urlname = $u8.GetBytes("$urlname")
			$out.Write($u8urlname, 0, $u8urlname.Length)
		}]],
		handler = function(stdout)
			mp.commandv("loadfile", stdout)
		end
	}
}
function import_files(iso)
	if plat ~= "windows" then
		return
	end
	local config_map = {
		[0] = import_configs.files,
		[1] = import_configs.dvd_iso,
		[2] = import_configs.bd_iso
	}
	local config = config_map[iso]
	if config then
		import_via_dialog(config)
	end
end
function import_url()
	import_via_dialog(import_configs.url)
end
function import_append_aid()
	import_via_dialog(import_configs.audio)
end
function import_append_sid()
	import_via_dialog(import_configs.subtitle)
end


function info_get()
	local conf_dir = mp.get_property_bool("config") and mp.command_native({"expand-path", "~~/"}) or "no"
	local osd_dims = mp.get_property_native("osd-dimensions")
	local w_s, h_s = osd_dims["w"] - osd_dims["ml"] - osd_dims["mr"], osd_dims["h"] - osd_dims["mt"] - osd_dims["mb"]
	local cur_name = mp.get_property_osd("media-title") or mp.get_property_osd("filename")
	local vid_params = mp.get_property_native("video-params") or "..."
	local w_raw, h_raw, pix_fmt, color_lv = vid_params["w"] or 0, vid_params["h"] or 0, vid_params["hw-pixelformat"] or vid_params["pixelformat"] or "...", vid_params["colorlevels"] or "..."
	local fps_o, fps_t = string.format("%0.3f", mp.get_property_number("container-fps", 0)), string.format("%0.3f", mp.get_property_number("estimated-vf-fps", 0))
	local bitrateV, bitrateA = mp.get_property_number("video-bitrate", 0) / 1000, mp.get_property_number("audio-bitrate", 0) / 1000
	local txt = (
	style_generic.."Config Folder: ".."{\\fs18\\1c&H0099FF}"..conf_dir:gsub("\\", "/").."\n"..
	style_generic.."Output Size: ".."{\\1c&H0099FF}".."["..w_s.."] x ["..h_s.."]".."\n"..
	style_generic.."Decoding Mode: ".."{\\1c&H0099FF}"..mp.get_property_native("hwdec-current", "...").."\n"..
	style_generic.."Video Sync: ".."{\\1c&H0099FF}"..mp.get_property_native("video-sync", "...").."\n"..
	style_generic.."Dropped Frames: ".."{\\1c&H0099FF}"..mp.get_property_number("frame-drop-count", 0).."\n"..
	style_generic.."Current File: ".."{\\fs18\\1c&H0099FF}"..cur_name:gsub("\\n", " "):gsub("\\$", ""):gsub("{","\\{").."\n"..
	style_generic.."Video ┓".."\n"..
	style_generic.."-   VO: ".."{\\1c&H03A89E}"..mp.get_property_native("current-vo", "...").."\n"..
	style_generic.."-   Codec: ".."{\\1c&H03A89E}"..mp.get_property_native("video-codec", "...").."\n"..
	style_generic.."-   Resolution: ".."{\\1c&H03A89E}".."["..w_raw.."] x ["..h_raw.."]".."\n"..
	style_generic.."-   Pixel: ".."{\\1c&H03A89E}"..pix_fmt.."\n"..
	style_generic.."-   Dynamic: ".."{\\1c&H03A89E}"..color_lv.."\n"..
	style_generic.."-   FPS: ".."{\\1c&H03A89E}"..fps_o.." FPS (Original) "..fps_t.." FPS (Target)".."\n"..
	style_generic.."-   Bitrate: ".."{\\1c&H03A89E}"..bitrateV.." kbps (Current)".."\n"..
	style_generic.."Audio ┓".."\n"..
	style_generic.."-   AO: ".."{\\1c&H9EA803}"..mp.get_property_native("current-ao", "...").." [Device] "..mp.get_property_native("audio-device", "...").."\n"..
	style_generic.."-   Codec: ".."{\\1c&H9EA803}"..mp.get_property_native("audio-codec", "...").."\n"..
	style_generic.."-   Bitrate: ".."{\\1c&H9EA803}"..bitrateA.." kbps (Current)".."\n"..
	style_generic.."Shader List: ".."{\\fs18\\1c&HFF8821}"..mp.get_property_osd("glsl-shaders"):gsub(":\\", "/"):gsub(":/", "/"):gsub("\\", "/"):gsub(";", " "):gsub(",", " "):gsub(":", " ").."\n"..
	style_generic.."Video Filter: ".."{\\fs18\\1c&HFF8821}"..mp.get_property_osd("vf"):gsub("%(empty%)", ""):gsub(" %[", "%["):gsub("%]\n", "%] "):gsub(" %(disabled%)", " (Disabled)").."\n"..
	style_generic.."Audio Filter: ".."{\\fs18\\1c&HFF8821}"..mp.get_property_osd("af"):gsub("%(empty%)", ""):gsub(" %[", "%["):gsub("%]\n", "%] "):gsub(" %(disabled%)", " (Disabled)")
	)
	return tostring(txt)
end
function info_toggle()
	if osm_showing then
		osm:remove()
		osm_timer:kill()
		osm_showing = false
		return
	end
	osm.data = info_get()
	osm:update()
	osm_showing = true
	osm_timer = mp.add_periodic_timer(0.5, function()
		if not osm_showing then
			osm_timer:kill()
		else
			osm.data = info_get()
			osm:update()
		end
	end)
end


function mark_aid_reset()
	mp.command("no-osd set lavfi-complex \"\"")
	merged_aid = false
	marked_aid_A, marked_aid_B = nil, nil
	mp.osd_message("[input_plus] Cancelled track merge and markers", 1)
	if mark_aid_reg then
		mp.unregister_event(mark_aid_check)
		mark_aid_reg = false
	end
end
function mark_aid_check()
	if marked_aid_A ~= nil or marked_aid_B ~= nil then
		mark_aid_reset()
	end
	mp.msg.info("mark_aid_check reset track merge and markers", 1)
end
function mark_aid_A()
	marked_aid_A = mp.get_property_number("aid", 0)
	if marked_aid_A == 0
	then
		mp.osd_message("[input_plus] Current audio track invalid", 1)
		marked_aid_A = nil
	else
		mp.osd_message("[input_plus] Pre-marked current track " .. marked_aid_A .. " as Parallel Track A", 1)
	end
	if mark_aid_reg then
		return
	else
		mp.register_event("end-file", mark_aid_check)
		mark_aid_reg = true
	end
end
function mark_aid_B()
	marked_aid_B = mp.get_property_number("aid", 0)
	if marked_aid_B == 0
	then
		mp.osd_message("[input_plus] Current audio track invalid", 1)
		marked_aid_B = nil
	else
		mp.osd_message("[input_plus] Pre-marked current track " .. marked_aid_B .. " as Parallel Track B", 1)
	end
	if mark_aid_reg then
		return
	else
		mp.register_event("end-file", mark_aid_check)
		mark_aid_reg = true
	end
end
function mark_aid_merge()
	if marked_aid_A == marked_aid_B or marked_aid_A == nil or marked_aid_B == nil
	then
		mp.osd_message("[input_plus] Invalid AB tracks", 1)
		marked_aid_A, marked_aid_B = nil, nil
	else
		mp.command("set lavfi-complex \"[aid" .. marked_aid_A .. "] [aid" .. marked_aid_B .. "] amix [ao]\"")
		mp.osd_message("[input_plus] Merged AB audio tracks", 1)
		merged_aid = true
	end
end
function mark_aid_fin()
	if merged_aid then
		mark_aid_reset()
		mp.commandv("set", "aid", "auto")
		return
	end
	if marked_aid_A == nil then
		mark_aid_A()
		return
	end
	if marked_aid_B == nil then
		mark_aid_B()
		return
	end
	mark_aid_merge()
end


function draw_ostime()
	local ostime = os.date("*t")
	ostime_msg.data = ostime_style .. "\238\128\134 " .. string.format("%02d:%02d:%02d", ostime.hour, ostime.min, ostime.sec)
	ostime_msg:update()
end
function ostime_toggle()
	if ostime_showing then
		ostime_timer:kill()
		ostime_msg:remove()
		ostime_showing = false
	else
		ostime_timer = mp.add_periodic_timer(1, draw_ostime)
		ostime_showing = true
	end
end
function ostime_display()
	if ostime_showing then
		return
	end
	draw_ostime()
	mp.add_timeout(1, function()
		ostime_msg:remove()
		draw_ostime()
	end)
	mp.add_timeout(2, function()
		ostime_msg:remove()
	end)
end


function update_osd()
	osd_hack:update()
end
function osd_hack_set(num, freq)
	num = tonumber(num) or -1
	if num ~= 0  and num ~= 1 then
		return
	end
	freq = tonumber(freq) or osd_hack_freq
	if freq <= 0 or freq > 1 then
		freq = osd_hack_freq
	end

	if osd_hack_timer == nil then
		if num == 0 then
			return
		elseif num == 1 then
			osd_hack_freq = freq
			osd_hack_timer = mp.add_periodic_timer(osd_hack_freq, update_osd)
			mp.msg.info("update_osd started")
		end
	else
		if freq == osd_hack_freq then
			if num == 0 then
				osd_hack_timer:stop()
				mp.msg.info("update_osd paused")
			elseif num == 1 then
				osd_hack_timer:resume()
				mp.msg.info("update_osd resumed")
			end
		else
			osd_hack_freq = freq
			osd_hack_timer:kill()
			osd_hack_timer = nil
			if num == 0 then
				mp.msg.info("update_osd terminated")
				return
			elseif num == 1 then
				osd_hack_timer = mp.add_periodic_timer(osd_hack_freq, update_osd)
				mp.msg.info("update_osd restarted")
			end
		end
	end
end


function scale_recal(pct)
	local w_dp, h_dp = mp.get_property_number("display-width", 0), mp.get_property_number("display-height", 0)
	local w_vf, h_vf = mp.get_property_number("dwidth", 0), mp.get_property_number("dheight", 0)
	local scale_win = mp.get_property_number("current-window-scale", 0)
	local scale_shift = mp.get_property_number("display-hidpi-scale", 1)
	if w_dp == 0 or w_vf == 0 or scale_win == 0 then
		mp.msg.warn("scale_recal lacks necessary conditions")
		scale_target = 0
		return
	end
	scale_target = tonumber(string.format("%.3f", math.sqrt((w_dp * h_dp * pct * 0.01) / (w_vf * h_vf)) / scale_shift))
end
function window_mini(alt1, alt2)
	mp.set_property_bool("fullscreen", false)
	if alt1 then
		mp.set_property_bool("border", false)
	end
	mp.set_property_number("current-window-scale", scale_target)
	mp.set_property_bool("auto-window-resize", false)
	mp.set_property_bool("keepaspect-window", false)
	if alt2 then
		mp.set_property_bool("ontop", true)
	end
end
function pip_dummy(pct)
	if mp.get_property_native("idle-active") or not mp.get_property_native("vid") then
		mp.msg.warn("pip_dummy cannot be used in current state")
		return
	end
	scale_recal(pct)
	if scale_target == 0 then
		return
	end
	window_mini(1, 2)
	mp.msg.info("pip_dummy application attempted")
end


function show_playlist_shuffle()
	mp.add_timeout(0.1, function()
		local shuffle_msg = mp.command_native({"expand-text", "${playlist}"})
		shuffling = false
		mp.osd_message(shuffle_msg, 2)
	end)
end
function playlist_order(mode, re)
	if shuffling then
		mp.msg.info("playlist_order blocked high-frequency shuffle")
		return
	end
	if mp.get_property_number("playlist-count") <= 2 then
		mp.osd_message("[input_plus] Insufficient items in playlist", 1)
		return
	end
	shuffling = true
	if mode == 0 then
		if not shuffled then
			mp.command("playlist-shuffle")
			shuffled = true
			if re then
				mp.commandv("playlist-play-index", 0)
			end
			show_playlist_shuffle()
		else
			mp.command("playlist-unshuffle")
			shuffled = false
			if re then
				mp.commandv("playlist-play-index", 0)
			end
			show_playlist_shuffle()
		end
	elseif mode == 1 then
		if shuffled then
			mp.command("playlist-unshuffle")
			mp.command("playlist-shuffle")
			if re then
				mp.commandv("playlist-play-index", 0)
			end
			show_playlist_shuffle()
		else
			mp.command("playlist-shuffle")
			shuffled = true
			if re then
				mp.commandv("playlist-play-index", 0)
			end
			show_playlist_shuffle()
		end
	end
end
function playlist_random()
	local range = mp.get_property_number("playlist-count", 0)
	local pos = mp.get_property_number("playlist-pos-1", 0)
	local pos_nxt = math.random(1, range)
	if range <=2 then
		mp.msg.info("playlist_random items in playlist do not exceed 2")
		return
	else
		while pos_nxt == pos do
			pos_nxt = math.random(1, range)
		end
		mp.commandv("set", "playlist-pos-1", pos_nxt)
	end
end
function playlist_tmp_save()
	local item_num = mp.get_property_number("playlist-count", 0)
	if item_num == 0 then
		mp.osd_message("[input_plus] No files in playlist", 1)
		return
	end
	local file, err = io.open(save_path, "w")
	file:write("#EXTM3U\n\n")
	local Nn = 0
	while Nn < item_num do
		local save_item = mp.get_property("playlist/"..Nn.."/filename")
		file:write(save_item, "\n")
		Nn = Nn+1
	end
	mp.osd_message("[input_plus] Saved to temporary playlist", 1)
	mp.msg.info("playlist_tmp_save Config Folder/playlist_temp.mpl")
	file:close()
end
function playlist_tmp_load()
	mp.commandv("loadlist", save_path, "replace")
	if mp.get_property_number("playlist-count", 0) == 0 then
		mp.osd_message("[input_plus] Temporary playlist loading failed", 1)
	else
		mp.osd_message(mp.command_native({"expand-text", "${playlist}"}), 2)
	end
end


function quit_real()
	if pre_quit then
		mp.command("quit")
	else
		mp.osd_message("Press again to confirm exit", 1.5)
		pre_quit = true
		mp.add_timeout(1.5, function()
			pre_quit = false
			mp.msg.verbose("quit_real accidental exit keypress detected")
		end)
	end
end
function quit_wait()
	if pre_quit then
		pre_quit = false
		return
	else
		pre_quit = true
		mp.osd_message("Exiting soon, press again to cancel", 3)
		mp.add_timeout(3, function()
			if pre_quit then
				mp.command("quit")
			else
				mp.osd_message("Exit cancelled", 0.5)
				return
			end
		end)
	end
end


-- Another version https://github.com/mpv-player/mpv/issues/11589#issuecomment-1513535980
function acc_seeking(back, flag)
	seek_dur = seek_dur + seek_dur_step
	if not back then
		mp.command("seek " .. seek_dur .. " " .. flag)
	else
		mp.command("seek -" .. seek_dur .. " " .. flag)
	end
end
function seek_acc(back, alt)
	local function seek_acc_sub(flag_complex)
		local evt = flag_complex.event
		if evt == "up" then
			seek_dur = seek_dur_init
			return
		end
		if evt ~= "repeat" then
			return
		end
		local mode = alt and "exact" or "keyframes"
		acc_seeking(back, mode)
	end
	return seek_acc_sub
end


function sids_sec_swap()
	local sid_main = mp.get_property_number("sid", 0)
	local sid_sec = mp.get_property_number("secondary-sid", 0)
	if sid_main == 0 and sid_sec == 0 then
		return
	end
	mp.set_property_number("sid", 0)
	mp.set_property_number("secondary-sid", 0)
	mp.set_property_number("sid", sid_sec)
	mp.set_property_number("secondary-sid", sid_main)
end


function speed_auto(num, any)
	if any then
		num = spd_target
	end
	local function speed_auto_sub(flag_complex)
		local evt = flag_complex.event
		if evt == "down" then
			mp.set_property_number("speed", num)
			mp.msg.verbose("speed_auto Variable speed playback")
		elseif evt == "up" then
			mp.set_property_number("speed", 1)
			mp.msg.verbose("speed_auto Normal speed restored")
		end
	end
	return speed_auto_sub
end

function speed_recover()
	if mp.get_property_number("speed") ~= 1 then
		bak_speed = mp.get_property_number("speed")
		mp.command("set speed 1")
	else
		if bak_speed == nil then
			bak_speed = 1
		end
		mp.command("set speed " .. bak_speed)
	end
end
function speed_scale(rat, fact)
	local spd_scale, spd_delta = nil, nil
	for _, i in ipairs({fact, fact-1, fact+1}) do
		spd_scale = rat * i / math.floor(i * rat + 0.5)
		spd_delta = math.abs(spd_scale - 1)
		if spd_delta < spd_delta_min then
			mp.msg.info("speed_sync_toggle Target speed is 1")
			return 1
		elseif spd_delta <= spd_delta_max then
			mp.msg.info("speed_sync_toggle Target speed is " .. spd_scale)
			return spd_scale
		end
	end
end
function speed_adaptive()
	local fps_raw = mp.get_property_number("container-fps", 0)
	local fps_vf = mp.get_property_number("estimated-vf-fps", 0)
	local fps_dp = mp.get_property_number("display-fps", 0)
	local spd_cur = mp.get_property_number("speed", 1)
	if (fps_raw == 0 or fps_dp == 0 or fps_raw > 32 or math.abs(fps_vf - fps_raw) > 0.5) then
		mp.msg.warn("speed_sync_toggle exceptional FPS scenario")
		return
	end
	for i = 1, spd_iters_max do
		local spd_target = speed_scale(fps_dp / fps_raw, i)
		if spd_target then
			if math.abs(spd_target - spd_cur) < 0.0001 then
				break
			else
				mp.set_property("speed", spd_target)
				mp.msg.info("speed_sync_toggle set current speed to " .. spd_target)
				break
			end
		end
	end
end
function speed_sync_toggle()
	spd_adapt = not spd_adapt
	if spd_adapt then
		speed_adaptive()
		mp.osd_message("[input_plus] Speed adaptation enabled", 1)
		mp.register_event("playback-restart", speed_adaptive)
	else
		mp.unregister_event(speed_adaptive)
		mp.set_property_number("speed", 1)
		mp.osd_message("[input_plus] Speed adaptation disabled", 1)
		return
	end
end


function stats_cycle(num_init, num_end)
	if num_init < 0 or num_init > 5 then
		num_init = 1
	end
	if num_end < num_init then
		num_end = num_init
	end
	if num_end > 5 then
		num_end = 5
	end
	if show_page + 1 > num_end then
		show_page = num_init - 1
	end
	show_page = show_page + 1
	mp.commandv("script-binding", "display-page-" .. show_page)
end


function track_seek(id, num)
	mp.command("add " .. id .. " " .. num)
	if mp.get_property_number(id, 0) == 0 then
		mp.command("add " .. id .. " " .. num)
		if mp.get_property_number(id, 0) == 0 then
			mp.osd_message("[input_plus] No available " .. id, 1)
		end
	end
end


function track_refresh(id)
	local current_id = mp.get_property_number(id, 0)
	if current_id == 0 then
		mp.msg.warn("track_refresh current " .. id .. " invalid")
		return
	end
	mp.set_property_number(id, 0)
	mp.set_property_number(id, current_id)
end


-- Another implementation https://github.com/mpv-player/mpv/pull/11444#issuecomment-1469229943
function volume2db(vol)
	return 60.0 * math.log(vol / 100.0) / math.log(10.0)
end
-- https://github.com/mpv-player/mpv/blob/051ba909b4107240d643e4793efa2ceb714fd1b4/player/audio.c#L175
function db2volume(db)
	return math.exp(math.log(10.0) * (db / 60.0 + 2))
end
function volume_add(diff)
	local gain = round(volume2db(mp.get_property_number("volume"))) + diff
	local cap = mp.get_property_number("volume-max")
	if db2volume(gain) > cap then
		gain = volume2db(cap)
	elseif db2volume(gain) < 10 then
		gain = volume2db(10)
	end
	mp.set_property_number("volume", db2volume(gain))
	mp.osd_message("[input_plus] " .. string.format("Volume Gain: %+.2f dB", gain))
end


function prop_hold(prop)
	local function prop_auto(flag_complex)
		local evt = flag_complex.event
		if evt == "down" then
			prop_tmp = mp.get_property_native(prop, "")
			mp.set_property_native(prop, "")
			mp.msg.verbose("prop_hold cleared " .. prop)
		elseif evt == "up" then
			mp.set_property_native(prop, prop_tmp)
			mp.msg.verbose("prop_hold restored")
		end
	end
	return prop_auto
end


function update_shader_param(prefix, shader, param, val, def, min, max)

	if prefix == "set" then
		if shader == "_all_" then
			mp.command("change-list glsl-shader-opts append " .. param .. "=" .. val)
		else
			mp.command("change-list glsl-shader-opts append " .. shader .. "/" .. param .. "=" .. val)
		end

	elseif prefix == "add" then
		local glsl_opts = mp.get_property("glsl-shader-opts", "")
		local glsl_target = shader .. "/" .. param
		local glsl_target2 = param
		local function extract(input, key)
			local pattern = "[,]*" .. key .. "=([^,]+)"
			local value = input:match(pattern)
			return value
		end
		val = tonumber(val) or 0
		def = tonumber(def) or 0
		local val_cur
		if shader == "_all_" then
			val_cur = extract(glsl_opts, glsl_target2) or def
		else
			val_cur = extract(glsl_opts, glsl_target) or def
		end
		min = tonumber(min) or -10000
		max = tonumber(max) or 10000
		val_nxt = val_cur + val
		if val_nxt > max then
			val_nxt = max
		elseif val_nxt < min then
			val_nxt = min
		end
		if shader == "_all_" then
			mp.command("change-list glsl-shader-opts append " .. param .. "=" .. val_nxt)
		else
			mp.command("change-list glsl-shader-opts append " .. shader .. "/" .. param .. "=" .. val_nxt)
		end

	end

end



--
-- Special
--

function update_var(var, val)
	local msg_info_pre = "[input_plus] "
	local msg_info = "internal variable update"

	if var == "spd_target" then
		mp.remove_key_binding("speed_autox")
		if tonumber(val) <=0 then
			val = 0.1
		end
		spd_target = tonumber(val)
		msg_info = "custom target speed " .. val
		mp.osd_message(msg_info_pre .. msg_info, 1)
		mp.msg.info(msg_info)
		mp.add_key_binding(nil, "speed_autox", speed_auto(nil, spd_target), {complex = true})

	elseif var == "seek_dur_step" then
		if tonumber(val) <=0 then
			val = 0.1
		end
		seek_dur_step = tonumber(val)
		msg_info = "custom seek step increment " .. val
		mp.osd_message(msg_info_pre .. msg_info, 1)
		mp.msg.info(msg_info)

	end
end

function lazy_helper(link)
	local param = ""
	if plat == "windows" then
		param = 'no-osd run cmd /c start "" "' .. link .. '"'
	elseif plat == "darwin" then
		param = "no-osd run /bin/sh -c \"open '" .. link .. "' &\""
	elseif plat == "linux" then
		param = "no-osd run /bin/sh -c \"xdg-open '" .. link .. "' &\""
	else
		return
	end
	return param
end
function lazy_helper_main(index)
	index = tonumber(index)
	local cmd = ""

	if index == 0 then -- project
		cmd = lazy_helper("https://github.com/hooke007/mpv_PlayKit")
	elseif index == 1 then -- mpv manual
		cmd = lazy_helper("https://mpv.io/manual/master/")
	elseif index == 2 then -- mpv manual cn
		cmd = lazy_helper("https://hooke007.github.io/official_man/mpv.html")
	elseif index == 3 then -- faq
		cmd = lazy_helper("https://github.com/hooke007/mpv_PlayKit/wiki/0_FAQ")
	elseif index == 4 then -- filter
		cmd = lazy_helper("https://github.com/hooke007/mpv_PlayKit/wiki/3_FILTER")
	elseif index == 5 then -- shader
		cmd = lazy_helper("https://github.com/hooke007/mpv_PlayKit/wiki/4_GLSL")
	end

	if cmd ~= "" then
		mp.command(cmd)
	end
end



--
-- Keybinding
--

mp.add_key_binding(nil, "adevice_back", function()
	adevicelist = mp.get_property_native("audio-device-list") adevicelist_fin(#adevicelist, 1, -1) end)
mp.add_key_binding(nil, "adevice_next", function()
	adevicelist = mp.get_property_native("audio-device-list") adevicelist_fin(1, #adevicelist, 1) end)
mp.add_key_binding(nil, "adevice_all_back", function()
	adevicelist = mp.get_property_native("audio-device-list") adevicelist_fin(#adevicelist, 1, -1, true) end)
mp.add_key_binding(nil, "adevice_all_next", function()
	adevicelist = mp.get_property_native("audio-device-list") adevicelist_fin(1, #adevicelist, 1, true) end)

mp.add_key_binding(nil, "chap_skip_toggle", chap_skip_toggle)

mp.add_key_binding(nil, "chapter_back", function() chapter_seek_force(-1) end)
mp.add_key_binding(nil, "chapter_back_nat", function() chapter_seek_force(-1, true) end)
mp.add_key_binding(nil, "chapter_next", function() chapter_seek_force(1) end)
mp.register_script_message("chapter-useek", function(dir, nat) chapter_seek_force(dir, nat, true) end)

mp.add_key_binding(nil, "import_files", function() import_files(0) end)
mp.add_key_binding(nil, "import_iso_dvd", function() import_files(1) end)
mp.add_key_binding(nil, "import_iso_bd", function() import_files(2) end)
mp.add_key_binding(nil, "import_url", import_url)
mp.add_key_binding(nil, "import_append_aid", import_append_aid)
mp.add_key_binding(nil, "import_append_sid", import_append_sid)

mp.add_key_binding(nil, "info_toggle", info_toggle)

mp.add_key_binding(nil, "mark_aid_A", mark_aid_A)
mp.add_key_binding(nil, "mark_aid_B", mark_aid_B)
mp.add_key_binding(nil, "mark_aid_merge", mark_aid_merge)
mp.add_key_binding(nil, "mark_aid_reset", mark_aid_reset)
mp.add_key_binding(nil, "mark_aid_fin", mark_aid_fin)

mp.add_key_binding(nil, "ostime_display", ostime_display)
mp.add_key_binding(nil, "ostime_toggle", ostime_toggle)

mp.add_key_binding(nil, "pip_dummy", function() pip_dummy(20) end)
mp.register_script_message("pip_dummy_pct", function(pct) pip_dummy(tonumber(pct)) end)

mp.add_key_binding(nil, "playlist_order_0", function() playlist_order(0) end)
mp.add_key_binding(nil, "playlist_order_0r", function() playlist_order(0, true) end)
mp.add_key_binding(nil, "playlist_order_1", function() playlist_order(1) end)
mp.add_key_binding(nil, "playlist_order_1r", function() playlist_order(1, true) end)
mp.add_key_binding(nil, "playlist_random", playlist_random)
mp.add_key_binding(nil, "playlist_tmp_save", playlist_tmp_save)
mp.add_key_binding(nil, "playlist_tmp_load", playlist_tmp_load)

mp.add_key_binding(nil, "quit_real", quit_real)
mp.add_key_binding(nil, "quit_wait", quit_wait)

mp.add_key_binding(nil, "seek_acc", seek_acc(false, false), {complex = true})
mp.add_key_binding(nil, "seek_acc_back", seek_acc(true, false), {complex = true})
mp.add_key_binding(nil, "seek_acc_alt", seek_acc(false, true), {complex = true})
mp.add_key_binding(nil, "seek_acc_back_alt", seek_acc(true, true), {complex = true})

mp.add_key_binding(nil, "sids_sec_swap", sids_sec_swap)

mp.add_key_binding(nil, "speed_auto", speed_auto(2), {complex = true})
mp.add_key_binding(nil, "speed_auto_bullet", speed_auto(0.5), {complex = true})
mp.add_key_binding(nil, "speed_autox", speed_auto(_, spd_target), {complex = true})
mp.add_key_binding(nil, "speed_recover", speed_recover)

mp.add_key_binding(nil, "speed_sync_toggle", speed_sync_toggle)

mp.register_script_message("cycle-stats", function(pg_init, pg_end) stats_cycle(tonumber(pg_init), tonumber(pg_end)) end)

mp.add_key_binding(nil, "trackA_back", function() track_seek("aid", -1) end)
mp.add_key_binding(nil, "trackA_next", function() track_seek("aid", 1) end)
mp.add_key_binding(nil, "trackS_back", function() track_seek("sid", -1) end)
mp.add_key_binding(nil, "trackS_next", function() track_seek("sid", 1) end)
mp.add_key_binding(nil, "trackV_back", function() track_seek("vid", -1) end)
mp.add_key_binding(nil, "trackV_next", function() track_seek("vid", 1) end)

mp.add_key_binding(nil, "trackA_refresh", function() track_refresh("aid") end)
mp.add_key_binding(nil, "trackS_refresh", function() track_refresh("sid") end)
mp.add_key_binding(nil, "trackV_refresh", function() track_refresh("vid") end)

mp.add_key_binding(nil, "volume_db_dec", function() volume_add(-1) end, {repeatable = true})
mp.add_key_binding(nil, "volume_db_inc", function() volume_add(1) end, {repeatable = true})

mp.add_key_binding(nil, "af_hold", prop_hold("af"), {complex = true})
mp.add_key_binding(nil, "vf_hold", prop_hold("vf"), {complex = true})
mp.add_key_binding(nil, "glsl_hold", prop_hold("glsl-shaders"), {complex = true})

mp.register_script_message("glsl-param", function(prefix, shader, param, val, def, min, max)
	update_shader_param(prefix, shader, param, val, def, min, max) end)

mp.register_script_message("cycle-cmds", cycle_cmds)

mp.register_script_message("update-osd", function(num, freq) osd_hack_set(num, freq) end)

mp.register_script_message("update-var", function(var, val) update_var(var, val) end)

mp.register_script_message("lazy-helper", function(index) lazy_helper_main(index) end)