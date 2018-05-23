local handler = {}

function handler:init()
end

function get_html()
    return [[<html>
    <head>
        <title>MiniTTP static data example</title>
    </head>
    <body>
        <p>This is an example of some static data</p>
        <p>There should be an image below</p>
        <img src="minittp.png" alt="minittp image" />
    </body>
</html>
]]
end

function handler:handle_request(request, response)
    if request.path == "/" then
        response.content = get_html()
        return response
    else
        return handle_static_file(request, response, "img")
    end
end

return handler
