--
-- some helper functions
--

local minittp_util = {}

minittp_util.MINITTP_VERSION = "0.1.0"

function tabledump(t)
    for i, e in pairs(t) do
        print(i .. ": " .. e)
    end
end
minittp_util.tabledump = tabledump

-- Some lua magic; this translates an unpacked variable number
-- of arguments into one array (useful if functions return an unknown
-- number of values, like the page pattern matcher)
function pack(...)
  return arg
end
minittp_util.pack = pack

--
-- Add some helper function to string
--
function string:trim()
    return self:match "^%s*(.-)%s*$"
end

function string:split_iter(pat)
  pat = pat or '%s+'
  local st, g = 1, self:gmatch("()("..pat..")")
  local function getter(segs, seps, sep, cap1, ...)
    st = sep and seps + #sep
    return self:sub(segs, (seps or 0) - 1), cap1 or sep, ...
  end
  return function() if st then return getter(st, g()) end end
end

function string:split(pat, trim)
    local result = {}
    for i in self:split_iter(pat) do
        if trim then i = i:trim() end
        table.insert(result, i)
    end
    return result
end

function string:endswith(part)
    return part == self:sub(1+self:len()-part:len())
end

function string:startswith(part)
    return part == self:sub(1,part:len())
end

-- Send data_len of bytes from data to the socket
-- Returns data_len if succesfull, returns nil, error if not
-- If data_len is nil, send data:len() bytes
function send_data(sock, data, data_len)
    if data_len == nil then data_len = data:len() end

    vprint("> " .. data)

    local total_sent = 0
    local count, err, sent
    while total_sent < data_len do
        count, err, sent = sock:send(data, total_sent+1, data_len - total_sent)
        -- TODO: check for EAGAIN here?
        if count == nil then return nil, err, sent end
        -- We may have sent a partial message
        total_sent = total_sent + count
        if total_sent == data_len then return total_sent end
    end
end
minittp_util.send_data = send_data

local mimetypes = {};
mimetypes[".css"] = "text/css"
mimetypes[".txt"] = "text/plain"
mimetypes[".html"] = "text/html"
mimetypes[".pdf="] = "application/pdf"
mimetypes[".jpg"] = "image/jpeg"
mimetypes[".jpeg"] = "image/jpeg"
mimetypes[".png"] = "image/PNG"
mimetypes[".mp3"] = "audio/mpeg"
mimetypes[".mp4"] = "video/mp4"
mimetypes[".json"] = "application/json"
mimetypes[".js"] = "application/javascript"
mimetypes[".data"] = "application/octet-stream"

function derive_mimetype(filename)
    for ext, mimetype in pairs(mimetypes) do
        if filename:endswith(ext) then return mimetype end
    end
    -- what type to assume?
    return "text/plain"
end
minittp_util.derive_mimetype = derive_mimetype

handler = {}


return minittp_util
