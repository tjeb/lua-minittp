--
-- The 'main' engine and classes for MiniTTP
--

--
-- The response object; an empty version is provided to handler classes
-- The handlers can return it and the engine will send it to the client
-- Or the handlers can respond themselves (for instance with chunked
-- data)
--
local mte_M = {}

local mt_util = require 'minittp_util'
local mt_io = require 'minittp_io'
local posix = require 'posix'
local sys_stat = require "posix.sys.stat"

local response = {}
response.__index = response

-- should probably pass request here too (some headers need to be copied)
-- if request is given, take some header values from that
function response.create(connection, request)
    local r = {}
    setmetatable(r, response)
    r.headers = response.create_standard_headers()
    r.content = nil
    r.status_code = 200
    r.status_description = "OK"
    r.connection = connection

    if request ~= nil then
        r.keepalive = request.keepalive
        r.http_version = request.http_version

        -- update the standard headers we will send
        if r.keepalive then
            r.headers["Connection"] = "keep-alive"
        end
    else
        r.keepalive = false
        r.http_version = "HTTP/1.1"
    end

    return r
end
mte_M.create_response = response.create

function response.create_standard_headers()
    headers = {}
    headers["Server"] = "minittp/" .. mt_util.MINITTP_VERSION
    headers["Date"] = get_time_string()
    headers["Content-Type"] = "text/html"
    -- Note: Content-Length will be calculated at the end, if content is set
    headers["Last-Modified"] = get_time_string()
    headers["Connection"] = "close"
    headers["Cache-Control"] = "max-age: 3600"
    headers["X-Frame Options"] = "deny"
    headers["Allow"] = "GET, HEAD"
    return headers
end

function response:set_cache(maxage)
    self:set_header("Cache-Control", "max-age: " .. maxage)
    self:set_header("pragma", nil)
end

function response:set_header(key, value)
    self.headers[key] = value
end

function response:set_status(code, description)
    self.status_code = code
    self.status_description = description
end

function response:create_status_line()
    return self.http_version .. " " .. self.status_code .. " " .. self.status_description .. "\r\n"
end

-- Send the status response line. Returns number of bytes sent
-- This sets the status code to nil, so it is only sent once
function response:send_status()
    if self.status_code ~= nil then
        local count, err = send_data(self.connection, self:create_status_line())
        if count == nil then return nil, err end
        self.status_code = nil
        return count
    end
    return 0
end

-- Sends the response headers
-- If response content has been set, it will add/update the Content-Length header
-- Headers are set to nil, so they are only sent once
-- Returns the number of *headers* sent on success
-- Returns nil, error on error
function response:send_headers()
    local count = 0
    local sent, err
    if self.headers ~= nil then
        -- recalculate Content-Length
        if self.content ~= nil then
            self.headers["Content-Length"] = self.content:len()
        end
        for h, v in pairs(self.headers) do
            local hline = h .. ": " .. v .. "\r\n"
            sent, err = send_data(self.connection, hline)
            if sent == nil then return nil, err end
            count = count + 1
        end
        -- marker for headers->content
        sent, err = send_data(self.connection, "\r\n")
        if sent == nil then return nil, err end
        self.headers = nil
    end
    return count
end

-- Sends the response content, if any
-- Sets the content to nil, so it is only sent once
-- Returns the number of bytes sent
function response:send_content()
    local sent = 0
    if self.content ~= nil then
        sent, err = send_data(self.connection, self.content)
        if sent == nil then return nil, err end
        self.content = nil
    end
    return sent
end

-- Send one chunk of data, i.e. send the length followed by the data
-- The status and headers must have been sent, and the Transfer-Encoding
-- header must be 'chunked'
-- Returns the amount of bytes sent, or (nil, error)
function response:send_chunk(chunk)
    local chunk_len = string.format("%x\r\n", chunk:len())
    local sent, err = send_data(self.connection, chunk_len)
    if sent == nil then
        return nil, err
    end
    return send_data(self.connection, chunk .. "\r\n")
end


--
-- The request object; this is parsed from the HTTP request, and
-- passed on to the engine (and subsequently the handler)
--
local request = {}
request.__index = request

--
-- Creates a request object, read from the given connection (which
-- must have the receive() and getpeername() functions, like a socket
-- connection
-- Returns the request object, or (nil, error) on error
--
-- the request object contains all the headers as strings in request.headers
-- and a few additional values:
-- TODO
--
function request:parse_query()
    local path = self.query
    local params = nil

    local parts = self.query:split("?")
    if #parts > 2 then
        return nil, "Bad query"
    elseif #parts > 1 then
        path = parts[1]
        -- TODO: split up params further
        local param_parts = parts[2]:split("&")
        params = {}
        for i,p in pairs(param_parts) do
            local pv = p:split("=")
            if #pv == 2 then
                params[pv[1]] = pv[2]
            end
        end
    end
    return path, params
end



function request.create(connection)
    local r = {}
    setmetatable(r, request)
    r.connection = connection
    r.query = ""
    r.headers = {}
    return r
end
mte_M.create_request = request.create

function request.create_from_connection(connection)
    local r = request.create()
    r.connection = connection

    -- first line must be a GET (for now)
    local line, err = connection:receive()
    if line == nil then return nil, err end

    local parts = line:split(" ")
    if parts[1] == "GET" then
        vprint("r: " .. line)
        r.query = parts[2]
        r.path, r.params, err = r:parse_query()
        if r.path == nil then return nil, err end
        r.http_version = parts[3]
        local headers, err = request.parse_headers(connection)
        if headers == nil then return nil, err end
        r.headers = headers

        -- specific header parsing
        local header_connection = headers['Connection']
        if header_connection ~= nil then
            if header_connection == 'keep-alive' then
                r.keepalive = true
            else
                r.keepalive = false
            end
        end

        -- If we are behind a proxy, assume X-Forwarded-For has been set
        -- if not, use the peer name of the socket
        -- (question/TODO: should we do the same for the other X-Forwarded options?)
        if headers['X-Forwarded-For'] ~= nil then
            r.client_address = headers['X-Forwarded-For']
        else
            r.client_address = connection:getpeername()
        end
        vprint("Peer: " .. r.client_address)

    else
        return nil, "Unsupported command: " .. line
    end
    return r
end
mte_M.create_request_from_connection = request.create_from_connection

function request.parse_headers(connection)
    local header_count = 0
    local headers = {}
    local line = connection:receive()
    while line ~= nil and line:trim() ~= "" do
        vprint("< " .. line)
        local hparts = line:split(":", true)
        if table.getn(hparts) > 1 then
            headers[hparts[1]] = table.concat(hparts, ":", 2)
            header_count = header_count + 1
        else
            return nil, "Bad header: " .. line
        end
        line = connection:receive()
    end
    return headers
end


-- Prebuilt handler for static files
-- TODO: add autoindex? (as opposed to trying out index.html)
-- Returns nil if file was succesfully sent
-- Returns a response object if it was not; the response is then filled
-- with some information but the caller may modify it
function handle_static_file(request, response, base_path)
    local file_path = request.path
    if base_path ~= nil then file_path = base_path .. file_path end

    -- TODO remove bad chars from path
    if mt_io.isdir(file_path) then
        file_path = file_path .. "index.html"
    end

    local fstat = sys_stat.stat(file_path)
    if fstat == nil then
        response:set_status(404, "Not found")
        response.content = err
        return response
    end

    local fr, err = mt_io.file_reader(file_path)
    response:set_header("Content-Type", mt_util.derive_mimetype(file_path))
    response:set_header("Last-Modified", os.date("%a, %d %b %Y %X %z", fstat.st_mtime))
    response:send_status()

    -- if below READSIZE bytes, send in one go, otherwise, send chunked
    local READSIZE = 8192
    if fstat.st_size < READSIZE then
        response:set_header("Content-Length", fstat.st_size)
        bytes, err, code = posix.read(fr.fd, fstat.st_size)
        if bytes ~= nil and bytes:len() > 0 then
            response.content = bytes
        end
        return response
    else
        response:set_header("Transfer-Encoding", "chunked")
        response:send_headers()
        local bytes = "dummy", err, code
        while bytes ~= nil and bytes:len() > 0 do
            bytes, err, code = posix.read(fr.fd, READSIZE)
            if bytes ~= nil and bytes:len() > 0 then
                response:send_chunk(bytes)
            end
        end
        response:send_chunk("")
        return nil
    end
end
mte_M.handle_static_file = handle_static_file

return mte_M
