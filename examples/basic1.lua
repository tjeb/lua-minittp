local handler = {}

function handler:init()
end

function handler:handle_request(request, response)
    response.content = "The most basic of examples."
    return response
end

return handler
