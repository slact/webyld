local ev = require "ev"
local socket = require "socket"
local lhp = require "http.parser"
local assert, type, setmetatable, rawget, io, tonumber = assert, type, setmetatable, rawget, io, tonumber
local tinsert, tremove, tconcat = table.insert, table.remove, table.concat
local common = require "wsapi.common"
require "coxpcall"
local copcall, coxpcall = copcall, coxpcall
local print=print
require "debug"
local traceback = debug.traceback
module "webyld"   -- Yet Another Lua http Server

local newEv = ev.IO.new
local blanks = { __index = function() return "" end }
local case_insensitive = {__index = function(t,k) return rawget(t, k:lower()) end }

local err = function(e)
	return e
end
local function handle_request(wsapi_env, parser, callback)
	local success, status_code, headers, body_iter = coxpcall(function() return callback(wsapi_env) end, err)
	if success then
		assert(type(status_code)=='number', "Status code (first return parameter) must be a number.")
		assert(type(headers)=='table', "Headers table (first return parameter) must obviously be a table.")
		if not parser:should_keep_alive() then
			headers.Connection='close'
		end
		common.send_output(wsapi_env.output, status_code, headers, body_iter, nil, true)
		--don't check resp_body_iter, it's a tiny bit tricky (functions, callable tables, and coroutines are all okay)
	else
		common.send_error(wsapi_env.output, wsapi_env.error, status_code, nil, nil, true)
	end

end
local function init_parser(ip, loop, client, callback)
	
	local parser
	local readEv = newEv(function(loop, watcher, ev)
		client:settimeout(0)
		repeat
			local r, err = client:receive('*l')
			--print("read ".. (r and #r or 0) .. " bytes", err)
			if r then
				assert(parser:execute(r .. "\r\n"))
			elseif err=="closed" then
				watcher:stop(loop)
				client:close()
			end
		until not r
	end, client:getfd(), ev.READ)
	readEv:start(loop, true)
	
	local headers, url
	local last_header_field
	local body = ""
	local output_buffer = {}
	local writeEv = newEv(function(loop, watcher, ev)
		--print("write event", watcher)
		--this is the writer. it, um, writes
		if #output_buffer > 0 then
			local out = tconcat(output_buffer) --should there be a /r/n separator here?
			--print(out)
			client:send(out)
			output_buffer = { }
		else
			--nothing to write -- stop trying for now.
			watcher:stop(loop)
			--print("stopped watching for write events")
		end
	end, client:getfd(), ev.WRITE)

	local wsapi_env = setmetatable({
		REMOTE_ADDR = ip,
		error = {
			write = function(self, err)
				io.stderr:write(err)
			end
		},
		input = {
			read = function()
				local body_bytes_read = 0
				return function(self, n)
					if n then
						local ret = body:sub(body_bytes_read+1, n)
						body_bytes_read = body_bytes_read + n
						return ret
					else
						return body
					end
				end
			end
		},
		output = {
			write = function(self, str)
				assert(type(str)=='string', type(str))
				tinsert(output_buffer, str)
				if #output_buffer == 1 then
					--print("started watching write events")
					writeEv:start(loop, true)
				end
				return #str
			end
		}
	}, blanks)

	local write = wsapi_env.output.write
	local parser_callbacks = {
		on_message_begin = function()
			headers, url = setmetatable({}, case_insensitive), nil
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
			wsapi_env.SERVER_PORT = tonumber(port) or 80
			wsapi_env.REQUEST_METHOD = parser:method()
			
			wsapi_env.headers = headers

			handle_request(wsapi_env, parser, callback)
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
	parser = lhp.request(parser_callbacks)
	return parser, wsapi_env
end

local function accept_client(client, loop, callback)
	--print("accepted new client ", client)
	local resume_read
	local wsapi_callback = function(...)
		callback(...)
		resume_read()
	end
	return assert(init_parser(client:getsockname(), loop, client, callback))
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

