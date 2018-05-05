--local posix = require "posix"
local copas = require "copas"
local mtu = require "minittp_util"

local handler = {}

function handler:handle_index(request, response)
    response.content = [[
<html>
    <head>
        <title>MiniTTP example</title>
    </head>
    <body>
        <p>
        This is an example of a slightly more advanced minittp setup.
        </p>
        <p>
        This index is a static page, as is the first link.
        </p>
        <p>
        The second link is a page that slowly sends a number of chunks
        </p>
        <p>
        The third link points to non-html content, a json data file
        </p>
        <p>
        <a href="/static_data.html">static_data</a>
        </p>
        <p>
        <a href="/download_file.html">A file download with some text</a>
        </p>
        <p>
        <a href="/chunked/10.html">A file download as chunked data (10 parts)</a>
        </p>
        <p>
        <a href="/chunked/60.html">A file download as chunked data (60 parts)</a>
        </p>
        <p>
        <a href="/json_data.json">JSON file</a>
        </p>
    </body>
</html>
]]
    return response
end

function handler:handle_static(request, response)
    response.content = [[
<html>
    <head>
        <title>MiniTTP example</title>
    </head>
    <body>
        <p>
        This is some static content
        </p>
        <a href="/">Go back</a>
        </p>
    </body>
</html>
]]
    return response
end

function handler:handle_download_file(request, response)
    response.content = [[
This is a text file that is served as a direct download.

You can delete it now.
]]
    response:set_header("Content-Disposition", "attachment; filename=\"download_file.txt\"")
    return response
end

function handler:handle_chunked_file(request, response, args)
    local chunk_count = args[1]
    response.content = nil
    response:set_header("Transfer-Encoding", "chunked")
    response:set_header("Content-Disposition",  "attachment; filename=\"download_chunked.txt\"")
    response:send_status()
    response:send_headers()

    response:send_chunk("In this example, the handler sends content data as chunks\n")
    response:send_chunk("We shall send " .. chunk_count .. " chunks at an interval of 1 second per chunk\n")
    --request.socket:flush()
    -- todo: do we need this?
    io.flush()
    for i=1,tonumber(chunk_count) do
        copas.sleep(1)
        local sent, err = response:send_chunk("Counter: " .. i .. "\n")
        io.flush()
        if sent == nil then
            print("Error sending chunk: " .. err)
            return nil, err
        end
    end
    response:send_chunk("")

    -- we could also return nil now, since we sent status and headers
    -- already, and content is nil
    return response
end

function handler:handle_json(request, response)
    response:set_header("Content-Type", "application/json")
    response.content = [[{
    "content": "JSON content",
    "lines": 5,
    "items": [ "foo", "bar" ],
    "description": "This is an example of JSON data"
}]]
    return response
end

function handler:init()
    self.mapping = {}
    table.insert(self.mapping, { pattern = '^/$', handler = self.handle_index })
    table.insert(self.mapping, { pattern = '^/static_data.html$', handler = self.handle_static })
    table.insert(self.mapping, { pattern = '^/download_file.html$', handler = self.handle_download_file })
    table.insert(self.mapping, { pattern = '^/chunked/([0-9]+).html$', handler = self.handle_chunked_file })
    table.insert(self.mapping, { pattern = '^/json_data.json$', handler = self.handle_json })
end

function handler:handle_request(request, response)
    local request_uri = request.path
    for _,v in pairs(self.mapping) do
        local match_elements = mtu.pack(request_uri:match(v.pattern))
        if #match_elements > 0 then
            return v.handler(self, request, response, match_elements)
        end
    end
    response:set_status(404, "Not found")
    response.content = "Not found: '" .. request_uri .. "'"
    return response
end

return handler
