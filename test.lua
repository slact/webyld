#!/usr/bin/env lua
local Request = require "wsapi.request"
local Response = require "wsapi.response"
function debug.dump(tbl)
	local function tcopy(t) local nt={}; for i,v in pairs(t) do nt[i]=v end; return nt end
	local function printy(thing, prefix, tablestack)
		local t = type(thing)
		if     t == "nil" then return "nil"
		elseif t == "string" then return string.format('%q', thing)
		elseif t == "number" then return tostring(thing)
		elseif t == "table" then
			if tablestack and tablestack[thing] then return string.format("%s (recursion)", tostring(thing)) end
			local kids, pre, substack = {}, "	" .. prefix, (tablestack and tcopy(tablestack) or {})
			substack[thing]=true	
			for k, v in pairs(thing) do
				table.insert(kids, string.format('%s%s=%s,',pre,printy(k, ''),printy(v, pre, substack)))
			end
			return string.format("%s{\n%s\n%s}", tostring(thing), table.concat(kids, "\n"), prefix)
		else
			return tostring(thing)
		end
	end
	local ret = printy(tbl, "", {})
	return ret
end

function debug.print(...)
	local buffer = {}
	for i, v in pairs{...} do
		table.insert(buffer, debug.dump(v))
	end
	local res = table.concat(buffer, "	")
	print(res)
	return res
end

local webyld = require "webyld"
local function bar()
	foo.bar.baz=11
end

webyld.serve("localhost", 8080, function(wsapi_env)
	local req = Request.new(wsapi_env)
	local resp = Response.new(200)
	resp:content_type("text/plain")
	resp:write("you asked for " .. req.path_info)
	resp:write("\r\ntest test test")
	return resp:finish()
end)

require "webyld.filehandler"
webyld.serve("localhost", 8081, webyld.filehandler("/home/leop/sandbox/webyld"))
webyld.run()
