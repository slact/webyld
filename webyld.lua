local ev = require("ev")
local socket = require "socket"
local connector = require "webyld.connector"
local lhp = require "http.parser"
local parsers = setmetatable({}, {__mode='k'})
local string = string
require "coxpcall"

module("webyld", package.seeall)  -- Yet Another Lua http Server

local newEv = ev.IO.new
local blanks = { __index = function() return "" end }
local case_insensitive = {__index = function(t,k) return rawget(t, k:lower()) end }
local function init_parser(ip, loop, client, callback)
	local cur, headers, url
	local last_header_field
	local parser
	local body = ""
	local output_buffer = {}
	local writeEv = newEv(function(loop, thing)
		--this is the writer. it, um, writes.
		if #output_buffer > 0 then
			local out = table.concat(output_buffer, "\r\n")
			client:send(out)
			output_buffer = {}
		end
	end, ev.WRITE)
	writeEv:start(loop, true)

	local wsapi_env = setmetatable({
		REMOTE_ADDR = ip
	}, blanks)

	local read_so_far = 0
	wsapi_env.input = {
		read = function(self, n)
			if n then
				local ret = body:sub(read_so_far+1, n)
				read_so_far = read_so_far + n
				return ret
			else
				return body
			end
		end
	}
	local cb = {
		on_message_begin = function()
			assert(cur == nil, "Can't start parsing HTTP request: another request on this connection has not yet finished parsing.")
			cur, headers, url = { }, setmetatable({}, case_insensitive), nil
		end,
		on_body = function(request_body)
			if request_body then
				body = request_body
			end
			wsapi_env.CONTENT_LENGTH = headers['Content-Length'] or '0'
			wsapi_env.CONTENT_TYPE = headers['Content-Type']
		end,
		on_message_complete = function()
			local host, port = (headers.Host or ""):match("([^:]+):?(%d*)")
			wsapi_env.SERVER_NAME = host			
			wsapi_env.SERVER_PORT = port or 80
			wsapi_env.REQUEST_METHOD = parser:method()
			
			wsapi_env.error = {
				write = function(self, err)
					io.stderr:write(err)
				end
			}
			wsapi_env.headers = headers
			local success, status_code, headers, body = copcall(callback, wsapi_env)
			if not success then
				--TODO: do something!
			end
			table.insert(output_buffer, status_code)
			--TODO: do better.
			for header_name,header_value in pairs(headers) do
				table.insert(output_buffer, ("%s: %s"):format(header_name, header_value))
			end
			table.insert(output_buffer, "\r\n")
			--TODO: output the body
			
		end,
		on_url = function(request_url)
			url = request_url
		end,
		on_path = function(path)
			wsapi_env.PATH_INFO = path
		end,
		on_query_string = function(query_string)
			wsapi_env.QUERY_STRING = query_string
		end,
		on_header_field = function(fieldname)
			last_header_field=fieldname
		end,
		on_header_value = function(value)
			headers[last_header_field:lower()]=value
		end
	}
	parser = lhp.request(cb)
	return parser
end

local function accept_client(client, loop, callback)
	local parser = init_parser(client:getsockname(), loop, client, callback)
	local read = ev.READ
	return newEv(function(loop, watcher, ev)
		client:settimeout(0)
		repeat
			local r, err = client:receive('*l')
			if r then
				assert(parser:execute(r))
				assert(parser:execute("\r\n"))
			elseif err ~= 'timeout' then
				watcher:stop(loop)
			end 
		until not r
		
	end, client:getfd(), ev.READ):start(loop, true)
end

function serve(address, port, wsapi_callback)
	local server, err = assert(socket.bind(address, port))
	local ioWatcher = assert(ev.IO.new(
		function(loop, watcher)
			accept_client(server:accept(), loop, wsapi_callback)
		end,
		server:getfd(),
		ev.READ
	))
	return ioWatcher:start(ev.Loop.default)
end

function run()
	return assert(ev.Loop.default):loop()
end

