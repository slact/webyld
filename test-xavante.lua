-------------------------------------------------------------------------------
-- Sample Xavante configuration file for launching WSAPI applications.
------------------------------------------------------------------------------

require "xavante"
require "xavante.filehandler"
require "wsapi.xavante"
local Request = require "wsapi.request"
local Response = require "wsapi.response"

-- Define here where Xavante HTTP documents scripts are located
local webDir = "/var/www"

-- Displays a message in the console with the used ports
xavante.start_message(function (ports)
    local date = os.date("[%Y-%m-%d %H:%M:%S]")
    print(string.format("%s Xavante started on port(s) %s",
      date, table.concat(ports, ", ")))
  end)

local function test(wsapi_env)
	local req = Request.new(wsapi_env)
	local resp = Response.new(200)
	resp:content_type("text/plain")
	resp:write("you asked for " .. req.path_info)
	resp:write("\r\ntest test test")
	return resp:finish()
end

xavante.HTTP{
    server = {host = "localhost", port = 8080},
    
    defaultHost = {
    	rules = { {-- filehandler 
			match = ".*",
			with = wsapi.xavante.makeHandler(test)
		} }
    },
}

xavante.start()