local ev = require("ev")
local socket = require "socket"
local parser = require "http.parse"

local parsers = setmetatable({}, {__mode='k'})

--module("yals", package.seeall)  -- Yet Another Lua http Server
local function watchclient(client, loop)
	return ev.IO.new(function(loop, watcher)
		
	end, client:getfd(), ev.READ):start(loop)
end


function new(address, port)
	local server, err = assert(socket.bind(address, port))
	local ioWatcher = assert(ev.IO.new(
		
	function(loop, watcher)
			watchclient(server:accept(), loop)
		end,
		server:getfd(),
		ev.READ
	))
	ioWatcher:start(ev.Loop.default)
	return assert(ev.Loop.default):loop()
end


print(new("localhost", 8080)
)