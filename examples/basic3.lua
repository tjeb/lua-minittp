local handler = {}

function handler:init()
end

function handler:handle_request(request, response)
    response.content = nil
    response:set_header("Transfer-Encoding", "chunked")
    response:send_status()
    response:send_headers()

    response:send_chunk("In this example, the handler sends content data as chunks <br />")
    response:send_chunk("That line was the first chunk, this is the second.<br />")
    response:send_chunk("And this line is a third one<br />")
    -- Don't forget the final empty chunk
    response:send_chunk("")
    
    -- We have sent status and headers, and set content to nil
    -- Returning the response now is unnecessary, since the engine
    -- would not do anything anyway. So we can just return nil
    return nil
end

return handler
