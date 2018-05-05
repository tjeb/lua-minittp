#!/usr/bin/lua

-- FCGI runner for minittp

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
    print("[XX] b1: " ..b1)
    local b2 = math.modf(value % 256)
    print("[XX] b2: " ..b2)
    c:send(string.char(b1))
    c:send(string.char(b2))
end

function read_fcgi_record(c)
    local fr = {}
    setmetatable(fr, fcgi_record)
    local b = c:receive(1)
    if b == nil then return nil end
    fr.version = string.byte(b)
    fr.type = string.byte(c:receive(1))
    fr.requestId = 256*string.byte(c:receive(1)) + string.byte(c:receive(1))
    fr.contentLength = 256 * string.byte(c:receive(1)) +string.byte(c:receive(1))
    fr.paddingLength = string.byte(c:receive(1))
    fr.reserved = string.byte(c:receive(1))
    if fr.contentLength > 0 then
        fr.contentData = c:receive(fr.contentLength)
    end
    if fr.paddingLength > 0 then
        fr.paddingData = c:receive(fr.paddingLength)
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
    c:send(string.char(self.version))
    c:send(string.char(self.type))
    send_int16(c, self.requestId)
    send_int16(c, self.contentLength)
    c:send(string.char(self.paddingLength))
    c:send(string.char(self.reserved))
    if self.contentLength > 0 then
        c:send(self.contentData)
    end
    if self.paddingLength > 0 then
        c:send(self.paddingData)
    end
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
        print("[XX] it's begin request!")
        local fbr = read_begin_request(fr)
        fbr:print()
    elseif fr.type == fcgi_types.FCGI_PARAMS then
        local fp = read_params(fr)
        fp:print()
    else
        print("[XX] unknown type: " .. fcgi_type_str[fr.type])
        fr:print()
    end
end

function create_cwrap(c)
    local cw = {}
    cw.c = c

    function cw:send(d)
        local i = 1
        local ds = ""
        while(i <= d:len()) do
            ds = ds .. " " .. string.byte(d, i) .. "(" .. string.sub(d, i,i) .. ")"
            i = i + 1
        end
        print("[XX] sending: " .. ds)
        c:send(d)
    end
    return cw
end

function handle_fcgi_request(f, handler)
    -- should start with BEGIN_REQUEST

    -- maybe add 'read_begin_request, read_params' straight from f/c?
    local fr = read_fcgi_record(f)
    -- we should try again. did we have a reliable read somewhere?
    if fr == nil then return nil, "Bad FCGI request, no data" end
    fr:print()
    if fr.type ~= fcgi_types.FCGI_BEGIN_REQUEST then
        return nil, "Bad FCGI request: does not start with FCGI_REQUEST"
    end
    local fp = read_params(read_fcgi_record(f))
    fp:print()

    -- convert to request

    -- just print to stdout for now, and assume http 1.1 for the time being
    local scheme = fp.params.REQUEST_SCHEME
    local port = fp.params.SERVER_PORT
    local port_str = ""
    if (scheme == "http" and port ~= 80) or (scheme == "https" and port ~= 443) then
        port_str = ":" .. port
    end

    -- this should be converted to a Request object
    print(fp.params.REQUEST_METHOD .. " " .. fp.params.REQUEST_SCHEME .. "://" .. fp.params.HTTP_HOST .. port_str .. fp.params.PATH_INFO .. " " .. fp.params.SERVER_PROTOCOL)

    print("Host: " .. fp.params.HTTP_HOST)
    print("User-Agent: " .. fp.params.HTTP_USER_AGENT)
    print("X-Forwarded-For: " .. fp.params.REMOTE_ADDR)
    print("Accept-Encoding: " .. fp.params.HTTP_ACCEPT_ENCODING)
    if fp.params.HTTP_REFERER then
        print("Referer: " .. fp.params.HTTP_REFERER)
    end
    print("Content-Length: " .. fp.params.CONTENT_LENGTH)
    print("Cache-Control: " .. fp.params.HTTP_CACHE_CONTROL)
    print("")

    -- if the handler sends its own data, we need to make sure the right calls are wrapped into fcgi structures

    -- call the handler

    -- and send the response if not done yet

    -- depending on params of fcgi server, we may need to keep the connection open

    -- the response
    local fresp = create_fcgi_stdout_record("X-Foo: bar\r\n\r\ndata\r\n")
    print("[XX] SENDING: ")
    fresp:print()
    fresp:write_record(create_cwrap(f))

    fresp = create_fcgi_stdout_record("")
    print("[XX] SENDING: ")
    fresp:print()
    fresp:write_record(f)

    -- end request
    fresp = create_fcgi_record(fcgi_types.FCGI_END_REQUEST)
    fresp.contentLength = 2
    fresp.contentData = "\0\0"
    --print("[XX] LEN: " .. fresp.contentData:len())
    print("[XX] SENDING: ")
    fresp:print()
    fresp:write_record(f)

    return true
end
_M.handle_fcgi_request = handle_fcgi_request

function test_file()
    local f = io.open("fcgi_request.bin")

    result, err = handle_fcgi_request(f)
    if result == nil then print("Error: " .. err) end
end

return _M
