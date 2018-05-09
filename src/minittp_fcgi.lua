#!/usr/bin/lua

-- FCGI runner for minittp

local mt_engine = require 'minittp_engine'
local copas = require 'copas'

local _M = {}

local fcgi_type_str = {
    "FCGI_BEGIN_REQUEST",
    "FCGI_ABORT_REQUEST",
    "FCGI_END_REQUEST",
    "FCGI_PARAMS",
    "FCGI_STDIN",
    "FCGI_STDOUT",
    "FCGI_STDERR",
    "FCGI_DATA",
    "FCGI_GET_VALUES",
    "FCGI_GET_VALUES_RESULT",
    "FCGI_UNKNOWN_TYPE"
}

local fcgi_types = {
    FCGI_BEGIN_REQUEST = 1,
    FCGI_ABORT_REQUEST = 2,
    FCGI_END_REQUEST = 3,
    FCGI_PARAMS = 4,
    FCGI_STDIN = 5,
    FCGI_STDOUT = 6,
    FCGI_STDERR = 7,
    FCGI_DATA = 8,
    FCGI_GET_VALUES = 9,
    FCGI_GET_VALUES_RESULT = 10,
    FCGI_UNKNOWN_TYPE
}

local fcgi_role_str = {
    "FCGI_RESPONDER",
    "FCGI_AUTHORIZER",
    "FCGI_FILTER"
}

local fcgi_roles = {
    FCGI_RESPONDER = 1,
    FCGI_AUTHORIZER = 2,
    FCGI_FILTER = 3
}

local fcgi_record = {}
fcgi_record.__index = fcgi_record

function receive_int16(c)
    return 256*string.byte(c:receive(1)) + string.byte(c:receive(1))
end

function send_int16(c, value)
    if value > 65535 then error("Value too large for 16 bits: " .. value) end
    local b1 = math.modf(value / 256)
    local b2 = math.modf(value % 256)
    c:send(string.char(b1))
    c:send(string.char(b2))
end

function int16tos(value)
    if value > 65535 then error("Value too large for 16 bits: " .. value) end
    local b1 = math.modf(value / 256)
    local b2 = math.modf(value % 256)
    return string.char(b1) .. string.char(b2)
end

function read_fcgi_record(c)
    local bs = nil
    local count = 1
    while bs == nil and count <= 10 do
        bs = c:receive(8)
        if bs == nil then copas.sleep(0.1) end
        count = count + 1
    end
    if bs == nil then return nil, "Timeout reading fcgi record header" end

    local fr = {}
    setmetatable(fr, fcgi_record)

    fr.version = string.byte(bs, 1)
    fr.type = string.byte(bs, 2)
    fr.requestId = 256*string.byte(bs, 3) + string.byte(bs, 4)
    fr.contentLength = 256 * string.byte(bs, 5) + string.byte(bs, 6)
    fr.paddingLength = string.byte(bs, 7)
    fr.reserved = string.byte(bs, 8)

    if fr.contentLength > 0 then
        fr.contentData = nil
        count = 1
        while fr.contentData == nil and count <= 10 do
            fr.contentData = c:receive(fr.contentLength)
            if fr.contentData == nil then copas.sleep(0.1) end
            count = count + 1
        end
        if fr.contentData == nil then return nil, "Timeout reading fcgi content data" end
    end
    if fr.paddingLength > 0 then
        fr.paddingData = nil
        count = 1
        while fr.paddingData == nil and count <= 10 do
            fr.paddingData = c:receive(fr.paddingLength)
            if fr.paddingData == nil then copas.sleep(0.1) end
            count = count + 1
        end
        if fr.paddingData == nil then return nil, "Timeout reading fcgi padding data" end
    end

    return fr
end

function create_fcgi_record(record_type)
    local fr = {}
    setmetatable(fr, fcgi_record)

    fr.version = 1
    fr.type = record_type
    fr.requestId = 1
    fr.contentLength = 0
    fr.paddingLength = 0
    fr.reserved = 0

    return fr
end

function create_fcgi_stdout_record(data)
    local fr = create_fcgi_record(fcgi_types.FCGI_STDOUT)
    if data ~= nil and data:len() > 0 then
        fr.contentLength = data:len()
        fr.contentData = data
    end
    return fr
end

function fcgi_record:write_record(c)
    local header = string.char(self.version) ..
                   string.char(self.type) ..
                   int16tos(self.requestId) ..
                   int16tos(self.contentLength) ..
                   string.char(self.paddingLength) ..
                   string.char(self.reserved)
    c:send(header)
    if self.contentLength > 0 then
        c:send(self.contentData)
    end
    if self.paddingLength > 0 then
        c:send(self.paddingData)
    end

    return true
end


function fcgi_record:print()
    print("FCGI_RECORD")
    print("  Version: " .. self.version)
    print("  Type: " .. fcgi_type_str[self.type])
    print("  requestId: " .. self.requestId)
    print("  ContentLength: " .. self.contentLength)
    print("  PaddingLength: " .. self.paddingLength)
    --print(": " .. self.)
    --print(": " .. self.)
    if self.contentData ~= nil then
        print("  ContentData: " .. self.contentData)
    end
end

local fcgi_begin_request = {}
fcgi_begin_request.__index = fcgi_begin_request

function read_begin_request(fr)
    fbr = {}
    setmetatable(fbr, fcgi_begin_request)
    fbr.role = string.byte(fr.contentData, 1) * 256 + string.byte(fr.contentData, 2);
    fbr.flags = string.byte(fr.contentData, 3)
    return fbr
end

function fcgi_begin_request:print()
    print("FCGI_BEGIN_REQUEST")
    print("  Role: " .. fcgi_role_str[self.role])
    print("  Flags: " .. self.flags)
    -- TODO set convenience vars for flags here (e.g. keep_connection)
end

local fcgi_params = {}
fcgi_params.__index = fcgi_params

function read_name_value(data, pos)
    -- returns: name, value, next_pos
    local nlen = string.byte(data, pos)
    local vlen = string.byte(data, pos + 1)
    -- note: we remove the terminating 0
    local name = string.sub(data, pos + 2, pos + 1 + nlen)
    local value = string.sub(data, pos + 2 + nlen, pos + 1 + nlen + vlen)
    return name, value, pos + nlen + vlen + 2
end

function read_params(fr)
    fp = {}
    setmetatable(fp, fcgi_params)

    fp.params = {}

    local name, value
    local pos = 1
    while pos < fr.contentLength do
        name, value, pos = read_name_value(fr.contentData, pos)
        fp.params[name] = value
    end

    return fp
end

function fcgi_params:print()
    print("FCGI_PARAMS")
    for n,v in pairs(fp.params) do
        print("  " .. n .. " = " .. v)
    end
end

function read_fcgi_records(f)
    local fr = read_fcgi_record(f)
    if fr == nil then return nil end
    if fr.type == fcgi_types.FCGI_BEGIN_REQUEST then
        local fbr = read_begin_request(fr)
    elseif fr.type == fcgi_types.FCGI_PARAMS then
        local fp = read_params(fr)
    else
        print("[XX] unknown fcgi record type: " .. fcgi_type_str[fr.type])
        fr:print()
    end
end

function ocreate_cwrap(c)
    local cw = {}
    cw.c = c

    function cw:send(d)
        local i = 1
        local ds = ""
        while(i <= d:len()) do
            ds = ds .. " " .. string.byte(d, i) .. "(" .. string.sub(d, i,i) .. ")"
            i = i + 1
        end
        c:send(d)
    end
    return cw
end

-- this wraps one send() call into a FCGI stdout message
function create_cwrap_debug(c)
    local cw = {}
    cw.c = c

    function cw:send(d)
        local i = 1
        local ds = ""
        while(i <= d:len()) do
            ds = ds .. " " .. string.byte(d, i) .. "(" .. string.sub(d, i,i) .. ")"
            i = i + 1
        end

        local fresp = create_fcgi_stdout_record(d)
        fresp:write_record(c)
        return d:len()
    end

    return cw
end

-- this wraps one send() call into a FCGI stdout message
function create_cwrap(c)
    local cw = {}
    cw.c = c

    function cw:send(d)
        local fresp = create_fcgi_stdout_record(d)
        fresp:write_record(c)
        return d:len()
    end

    return cw
end

function handle_fcgi_request(f, handler)
    -- should start with BEGIN_REQUEST

    -- maybe add 'read_begin_request, read_params' straight from f/c?
    local fr = read_fcgi_record(f)
    -- we should try again. did we have a reliable read somewhere?
    if fr == nil then return nil, "Bad FCGI request, no data" end
    if fr.type ~= fcgi_types.FCGI_BEGIN_REQUEST then
        return nil, "Bad FCGI request: does not start with FCGI_REQUEST"
    end
    local fp = read_params(read_fcgi_record(f))

    -- convert to request

    -- just print to stdout for now, and assume http 1.1 for the time being
    local scheme = fp.params.REQUEST_SCHEME
    local port = fp.params.SERVER_PORT
    local port_str = ""
    if (scheme == "http" and port ~= 80) or (scheme == "https" and port ~= 443) then
        port_str = ":" .. port
    end

    -- Convert the fastcgi data to a Request object
    local request = mt_engine.create_request()
    request.query = fp.params.REQUEST_SCHEME .. "://" .. fp.params.HTTP_HOST .. port_str .. fp.params.REQUEST_URI
    request.http_version = fp.params.SERVER_PROTOCOL

    request.path = fp.params.SCRIPT_NAME

    if fp.params.QUERY_STRING then
        local param_parts = fp.params.QUERY_STRING:split("&")
        params = {}
        for i,p in pairs(param_parts) do
            local pv = p:split("=")
            if #pv == 2 then
                params[pv[1]] = pv[2]
            end
        end
        request.params = params
    end

    request.client_address = fp.params.REMOTE_ADDR

    request.headers = {}
    -- heeey can we derive these from HTTP_?
    request.headers['Host'] = fp.params.HTTP_HOST
    if fp.params.HTTP_USER_AGENT then
        request.headers['User-Agent'] = fp.params.HTTP_USER_AGENT
    end
    if fp.params.REMOTE_ADDR then
        request.headers['X-Forwarded-For'] = fp.params.REMOTE_ADDR
    end
    if fp.params.HTTP_ACCEPT_ENCODING then
        request.headers['Accept-Encoding'] = fp.params.HTTP_ACCEPT_ENCODING
    end
    if fp.params.HTTP_REFERER then
        request.headers['Referer'] = fp.params.HTTP_REFERER
    end
    if fp.params.CONTENT_LENGTH and fp.params.CONTENT_LENGTH ~= "" and tonumber(fp.params.CONTENT_LENGTH) > 0 then
        request.headers['Content-Length'] = fp.params.CONTENT_LENGTH
    end
    if fp.params.HTTP_CACHE_CONTROL then
        request.headers['Cache-Control'] = fp.params.HTTP_CACHE_CONTROL
    end

    -- if the handler sends its own data, we need to make sure the right calls are wrapped into fcgi structures
    local c_wrap = create_cwrap(f)
    local response = mt_engine.create_response(c_wrap, request)

    -- sending chunks is now a normal send of the wrapper;
    -- no need to use the chunked transmission protocol ourselves
    response.send_chunk = c_wrap.send

    -- (we could make it more efficient by having the other standard send
    -- calls wrapped as well, btw, but those need special handling)

    -- call the handler
    response = handler:handle_request(request, response)

    -- and send the response if not done yet
    if response ~= nil then
        response:send_status()
        response:send_headers()
        response:send_content()
    end

    -- depending on params of fcgi server, we may need to keep the connection open

    -- end request
    fresp = create_fcgi_record(fcgi_types.FCGI_END_REQUEST)
    fresp.contentLength = 2
    fresp.contentData = string.char(0) .. string.char(0)
    fresp:write_record(f)

    f:close()
    return true
end
_M.handle_fcgi_request = handle_fcgi_request

function test_file()
    local f = io.open("fcgi_request.bin")

    result, err = handle_fcgi_request(f)
    if result == nil then print("Error: " .. err) end
end

return _M
