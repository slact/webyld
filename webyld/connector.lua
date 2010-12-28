local lhp = require "http.parser"

local common = require"wsapi.common"
local tinsert = table.insert

module ("webyld.connector", package.seeall)

local function process_finished_request(wsapi_env, url, headers, body, parser)
	local keepalive = parser:should_keep_alive()
	--TODO: upgrade

	local input_read = 0
	local request = {
		env = wsapi_env
		headers = headers
		input = {
			read = function(n)
				if not n then
					return body
				else
					local ret = body:strsub(input_read + 1, n)
					input_read = input_read + n
					return ret
				end
			end
		},
	}
end

local blanks = { __index = function() return "" end }
local case_insensitive = {__index = function(t,k) return rawget(t, k:tolower()) end }

local function init_parser(callback)
	local cur, headers, url, body
	local last_header_field
	local parser

	local wsapi_env = setmetatable({ }, blanks)

	local cb = {
		on_message_begin = function()
			assert(cur == nil, "Can't start parsing HTTP request: another request on this connection has not yet finished parsing.")
			cur, headers, url = { }, setmetatable({}, case_insensitive), nil
		end,
		on_body = function(request_body)
			if request_body then
				body = request_body
				wsapi_env.CONTENT_LENGTH = headers['Content-Length']
				wsapi_env.CONTENT_TYPE = headers['Content-Type']
			end
		end,
		on_message_complete = function()
			wsapi_env.REQUEST_METHOD = parser:method()
			wsapi_env.SERVER_NAME = headers.Host
			wsapi_env.SERVER_PORT = 80 --d'oh!

			return process_finished_request(wsapi_env, url, headers, body, parser)
		end,
		on_url = function(request_url)
			url = request_url
		end,
		on_header_field = function(fieldname)
			last_header_field=fieldname
		end,
		on_header_value = function(value)
			headers[last_header_field:tolower()]=value
		end
	}
	parser = lhp.request(cb)
	return parser
end

return function()
	return init_parser(process_finished_request)
end