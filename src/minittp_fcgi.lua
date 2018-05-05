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

function read_fcgi_record(c)
    local fr = {}
    setmetatable(fr, fcgi_record)
    local b = c:read(1)
    if b == nil then return nil end
    fr.version = string.byte(b)
    fr.type = string.byte(c:read(1))
    fr.requestId = 256*string.byte(c:read(1)) + string.byte(c:read(1))
    fr.contentLength = 256 * string.byte(c:read(1)) +string.byte(c:read(1))
    fr.paddingLength = string.byte(c:read(1))
    fr.reserved = string.byte(c:read(1))
    if fr.contentLength > 0 then
        fr.contentData = c:read(fr.contentLength)
    end
    if fr.paddingLength > 0 then
        fr.paddingData = c:read(fr.paddingLength)
    end
    return fr
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

function handle_fcgi_request(f)
    -- should start with BEGIN_REQUEST

    -- maybe add 'read_begin_request, read_params' straight from f/c?
    local fr = read_fcgi_record(f)
    if fr == nil then return nil, "Bad FCGI request, no data" end
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

    print(fp.params.REQUEST_METHOD .. " " .. fp.params.REQUEST_SCHEME .. "://" .. fp.params.HTTP_HOST .. port_str .. fp.params.PATH_INFO .. " " .. fp.params.SERVER_PROTOCOL)

    print("Host: " .. fp.params.HTTP_HOST)
    print("User-Agent: " .. fp.params.HTTP_USER_AGENT)
    print("X-Forwarded-For: " .. fp.params.REMOTE_ADDR)
    print("Accept-Encoding: " .. fp.params.HTTP_ACCEPT_ENCODING)
    print("Referer: " .. fp.params.HTTP_REFERER)
    print("Content-Length: " .. fp.params.CONTENT_LENGTH)
    print("Cache-Control: " .. fp.params.HTTP_CACHE_CONTROL)
    print("")

    return fp
end
_M.handle_fcgi_request = handle_fcgi_request

function test_file()
    local f = io.open("fcgi_request.bin")

    result, err = handle_fcgi_request(f)
    if result == nil then print("Error: " .. err) end
end

return _M
