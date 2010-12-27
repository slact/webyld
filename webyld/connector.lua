local lhp = require "http.parser"

local common = require"wsapi.common"
local tinsert = table.insert

module ("webyld.connector", package.seeall)

local function process_finished_request(url, headers, body, parser)
	local method, keepalive = parser:method(), parser:should_keep_alive()
	--TODO: upgrade
	print(method, url)
	for i,v in pairs(headers) do 
		print(i,v)
	end
	print(body)
	print("keepalive:", keepalive)
end

local function init_parser(callback)
	local cur, headers, url, body
	local last_header_field
	local parser
	local cb = {
		on_message_begin = function()
			assert(cur == nil, "Can't start parsing HTTP request: another request on this connection has not yet finished parsing.")
			cur, headers, url = { }, { }, nil
		end,
		on_body = function(request_body)
			body = request_body
		end,
		on_message_complete = function()
			return process_finished_request(url, headers, body, parser)
		end,
		on_url = function(request_url)
			url = request_url
		end,
		on_header_field = function(fieldname)
			last_header_field=fieldname
		end,
		on_header_value = function(value)
			headers[last_header_field]=value
		end
		
		
	}
	parser = lhp.request(cb)
	return parser
end

return function()
	return init_parser(process_finished_request)
end