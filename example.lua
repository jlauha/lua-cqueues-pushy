#!/usr/bin/lua5.2

local cqueues = require 'cqueues'
local push = require 'cqp.push'
local AtemMixer = require 'cqp.mixer.atem'
local PanasonicAW = require 'cqp.camera.panasonic_aw'
local XKeys = require 'cqp.input.xkeys'
local httpd = require 'cqp.httpd'
local http = require 'cqp.http'

local function setup_config()
	local keys = XKeys.new(0)
	local mixer = AtemMixer.new("192.168.1.151")
	local cam = PanasonicAW.new("192.168.1.152")

	local block_program = push.property(false, "Block program sending out")

	-- For nginx-rtmp ingeration:
	--   on_play http://localhost:8000/allow_program_out;
	httpd.new({uri={
	["allow_program_out"]=
		function()
			if block_program() then
				return 404, "Forbidden"
			else
				return 200, "OK"
			end
		end
	}})

	keys.joystick.x:push_to(cam.pan)
	keys.joystick.y:push_to(cam.tilt)
	keys.joystick.z:push_to(cam.zoom)

	mixer.channel(5).program_tally:push_to(cam.tally)

	for preset, key_ndx in ipairs({ 0, 8, 16, 24 }) do
		keys.key(key_ndx).state:push_to(push.action.timed(function(t)
			if t > 5.0 then cam:save_preset(preset)
			else cam:goto_preset(preset)
			end
		end))
	end

	mixer.fade_to_black_enabled:push_to(keys.key(1).red_led)
	keys.key(1).state:push_to(push.action.on(true, function() mixer:do_fade_to_black() end))
	keys.key(9).state:push_to(push.action.on(true, function() mixer:set_preview(1 + ((mixer.preview() + 4) % 6)) end))
	keys.key(17).state:push_to(push.action.on(true, function() mixer:set_preview(1 + (mixer.preview() % 6)) end))
	keys.key(25).state:push_to(push.action.on(true, function() mixer:do_cut() end))

	block_program:push_to(keys.key(2).red_led)
	block_program:push_to(push.action.on(true, function() http.get("127.0.0.1", 80, "/control/drop/subscriber?app=broadcast") end))
	keys.key(2).state:push_to(push.action.on(true, function() block_program(not block_program()) end))
end

local loop = cqueues.new()
print(loop:wrap(setup_config):loop())
