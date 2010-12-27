local ev = require("ev")
local socket = require "socket"
local connector = require "webyld.connector"

local parsers = setmetatable({}, {__mode='k'})

module("webyld", package.seeall)  -- Yet Another Lua http Server

local function watch_client(client, loop)
	local parser = connector(function(url)
		print(url)
	end)
	local read = ev.READ
	return ev.IO.new(function(loop, watcher, ev)
		client:settimeout(0)
		repeat
			local r = client:receive('*l')
			if r then
				assert(parser:execute(r))
				parser:execute("\r\n")
			else
				watcher:stop(loop)
			end 
		until not r
		
	end, client:getfd(), ev.READ):start(loop, true)
end


function new(address, port)
	local server, err = assert(socket.bind(address, port))
	local ioWatcher = assert(ev.IO.new(
		function(loop, watcher)
			watch_client(server:accept(), loop)
		end,
		server:getfd(),
		ev.READ
	))
	ioWatcher:start(ev.Loop.default)
	return assert(ev.Loop.default):loop()
end