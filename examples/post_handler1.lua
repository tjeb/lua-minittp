--
-- Simple JSON API example
--

local handler = {}

function handler:init()
    self.posted_data = {}
end

function handler:handle_index(request, response)
    response:set_header("Content-Type", "application/json")
    response.content = '{ "statuscode": 0, "message": "you can retrieve and post data at: /test_endpoint (with data=foo)" }\n'
end

function handler:create_endpoint_response()
    result = ""
    result = result .. '{ "statuscode": 0,\n'
    result = result .. '  "message": "",\n'
    result = result .. '  "data": [\n'
    for i,v in pairs(self.posted_data) do
      result = result .. '    "' .. v .. '",\n'
    end
    result = result .. "  ]\n"
    result = result .. "}\n"
    return result
end

function handler:create_error(code, message)
    return '{ "statuscode": ' .. code .. ', "message": ' .. message .. ' }'
end

function handler:handle_post(request, response)
    response:set_header("Content-Type", "application/json")
    if request.method == 'GET' then
        response.content = self:create_endpoint_response()
    elseif request.method == 'POST' then
        local postdata = request.post_data['data']
        if postdata ~= nil then
            table.insert(self.posted_data, postdata)
            response.content = self:create_endpoint_response()
        else
            response:set_status(400, "Bad Request")
            response.content = self:create_error(2, 'No "data" field found in post data')
        end
    else
        response:set_status(400, "Bad Request")
        response.content = self:create_error(3, "This server only supports GET and POST")
    end
    return response
end

function handler:handle_request(request, response)
    if request.path == "/" then
        self:handle_index(request, response)
    elseif request.path == "/test_endpoint" or request.path == "/test_endpoint/" then
        self:handle_post(request, response)
    else
        response:set_status(404, "Notfound")
        response.content = self:create_error(3, "No endpoint found at " .. request.path)
    end
    return response
end

return handler
