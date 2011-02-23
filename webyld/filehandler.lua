-----------------------------------------------------------------------------
-- Xavante File handler
--
-- Authors: Javier Guerra and Andre Carregal
-- Copyright (c) 2004-2007 Kepler Project
--
-- $Id: filehandler.lua,v 1.26 2009/08/11 01:48:07 mascarenhas Exp $
----------------------------------------------------------------------------

local lfs = require "lfs"
require "webyld.mime"
local Response = require "wsapi.response"
local ev = require "ev"

mimetypes = webyld.mimetypes or {}

local reserve_fd, release_fd
do
	local open, tinsert = io.open, table.insert
	local pop = function(t) 
		local i, fd = next(t)
		t[i]=nil
		return fd
	end
	local push = function(t, v)
		tinsert(t, v)
	end
	local fds = setmetatable({}, {
		--__mode = 'k', 
		__index = function(self, path)
			local fd = open(path, 'rb')
			local path_fds = { fd }
			rawset(self, path, path_fds)
			return path_fds
		end
	})
	--nothing fancy yet.
	reserve_fd = function(path)
		return pop(fds[path])
	end
	release_fd = function(fd)
		fd:close()
		--TODO: recycle.
	end
end


-- gets the mimetype from the filename's extension
local function mimefrompath (path)
	local _,_,exten = path:find("%.([^.]*)$")
	if exten then
		return mimetypes[exten]
	else
		return nil
	end
end

-- gets the encoding from the filename's extension
local function encodingfrompath (path)
	local _,_,exten = path:find("%.([^.]*)$")
	if exten then
		return xavante.encodings [exten]
	else
		return nil
	end
end

-- on partial requests seeks the file to
-- the start of the requested range and returns
-- the number of bytes requested.
-- on full requests returns nil
local function getrange(req, f)
	local range = req.headers["range"]
	if not range then return nil end
	
	local s,e, r_A, r_B = range:find("(%d*)%s*-%s*(%d*)")
	if s and e then
		r_A = tonumber(r_A)
		r_B = tonumber(r_B)
		
		if r_A then
			f:seek("set", r_A)
			if r_B then return r_B + 1 - r_A end
		else
			if r_B then f:seek("end", - r_B) end
		end
	end
	
	return nil
end

-- sends data from the open file f
-- to the response object res
-- sends only numbytes, or until the end of f
-- if numbytes is nil
local min = math.min
local function sendfile(f, res, numbytes)
	local block
	local whole = not numbytes
	local left = numbytes
	local blocksize = 8192
	
	if not whole then blocksize = min(blocksize, left) end
	
	while whole or left > 0 do
		block = f:read(blocksize)
		if not block then return end
		if not whole then
			left = left - #block
			blocksize = min(blocksize, left)
		end
		res:write(block)
	end
end

local function in_base(path)
  local l = 0
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  for dir in path:gmatch("/([^/]+)") do
    if dir == ".." then
      l = l - 1
    elseif dir ~= "." then
      l = l + 1
    end
    if l < 0 then return false end
  end
  return true
end

local new_response = Response.new
-- main handler
local function filehandler(wsapi_env, root)
	local method, path = wsapi_env.REQUEST_METHOD:upper(), wsapi_env.PATH_INFO
	local res = new_response(200)
	if method ~= "GET" and method ~= "HEAD" then
		res.status=405
		return res:finish()
	end

	if not in_base(path) then
		res.status=403
		return res:finish()
	end

	local path = root .."/".. path
	
	res.headers["Content-Type"] = mimefrompath(path)
	--res.headers["Content-Encoding"] = encodingfrompath(path)
    
	local attr = lfs.attributes(path)
	if not attr then
		res.status=404 --not found!
		return res:finish()
	end
	assert(type(attr) == "table")
	
	if attr.mode == "directory" then
		--directory lister maybe?
		--req.parsed_url.path = req.parsed_url.path .. "/"
		--res.statusline = "HTTP/1.1 301 Moved Permanently"
		--res.headers["Location"] = url.build (req.parsed_url)
		--res.content = "redirect"
		return res:finish()
	end
	
	res.headers["Content-Length"] = attr.size
	
	local f = reserve_fd(path)
	if not f then
		return xavante.httpd.err_404 (req, res)
	end
	
	res.headers["last-modified"] = os.date ("!%a, %d %b %Y %H:%M:%S GMT", attr.modification)

	local lms = tonumber(wsapi_env.headers["if-modified-since"]) or 0
	local lm = res.headers["last-modified"] or 1
	if lms == lm then
		res.headers["Content-Length"] = 0
		res.status=304 --not modified
		res.content = ""
        res.chunked = false
		release_fd(f)
		return res:finish()
	end

	
	if method == "GET" then
		local range_len = getrange(wsapi_env, f)
		if range_len then
			res.statusline = "HTTP/1.1 206 Partial Content"
			res.headers["Content-Length"] = range_len
		end
		
		sendfile(f, res, range_len)
    end
    release_fd(f)
	return res:finish()
end

function webyld.filehandler(root)
	assert(type(root)=='string', "Root directory must be a string.")
	--TODO: check if root exists.
	return function(wsapi_env) 
		return filehandler(wsapi_env, root)
	end
end
