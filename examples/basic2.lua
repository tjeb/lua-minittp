local handler = {}

function handler:init()
end

function handler:handle_request(request, response)
    response.content = "Another basic example. <br /> In this case the handler already calls for the sending if the status line and the headers"
    response:send_status()
    response:send_headers()
    -- Still return it; the engine will then send the content.
    -- (alternatively, we could also call response:send_content() and
    -- return nil)
    return response
end

return handler
