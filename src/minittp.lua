--
-- extremely minimalistic http wrapper for lua scripts
--
-- Does not do multiplexing, coroutines, or anything fancy,
-- it just listens on a port, and passes http requests to
-- the given lua script.
--
-- Put this behind a proxy (such as nginx) for front-end services
--

-- mostly compatible with uhttpd server, and comparable in goals, but
-- I needed something a bit more flexible

-- Dependencies: luasocket

-- Usage: minittp <handler script>

-- Note: it will only run the script once, so you can keep state between
-- requests there (but do care for concurrency, please)
--
-- Changing the script does mean you will need to restart minittp
--
local copas = require 'copas'
local socket = require 'socket'

local mtu = require 'minittp_util'
local mt_engine = require 'minittp_engine'

local minittp = {}
verbose = false

function vprint(msg)
    if verbose then print(msg:trim()) end
end

--
-- CLI functions
--
function help(rcode, msg)
    if msg ~= nil then print(msg) end

    print("Usage: minihttp.lua <handler script> [options]")
    print("Options:")
    print("-p <port number> The port number to listen on, defaults to 8080")
    print("-a <host ip> IP address to listen on, defaults to 127.0.0.1")
    print("-v verbose output")
    print("-s <handler options> Treat the rest of the command line as arguments for the handler (passed as a single string to its init() function")
    --print("-a <address>")
    --print("-f <function name>  Function to call in the script (will pass Request object, may return Response object, see docs. Defaults to 'handle_request()'")
    if rcode == nil then os.exit(0) else os.exit(rcode) end
end

function parse_args(args)
    local script_to_run = nil
    local port = 8080
    local host = "127.0.0.1"
    local script_args = nil
    skip = false
    for i = 1,table.getn(args) do
        if skip then
            skip = false
        elseif args[i] == "-h" then
            help()
        elseif args[i] == "-a" then
            host = args[i+1]
            if host == nil then help(1, "missing argument for -a") end
            skip = true
        elseif args[i] == "-p" then
            port = args[i+1]
            if port == nil then help(1, "missing argument for -p") end
            skip = true
        elseif args[i] == "-v" then
            verbose = true
        elseif args[i] == "-s" then
            script_args = {}
            for j = i+1,table.getn(args) do
                table.insert(script_args, arg[j])
            end
            break
        else
            if script_to_run == nil then script_to_run = args[i]
            else help(1, "Too many arguments at " .. table.getn(args))
            end
        end
    end
    if script_to_run == nil then
        help(1, "Missing arguments")
    end
    return script_to_run, host, port, script_args
end

function get_time_string()
    return os.date("%a, %d %b %Y %X %z")
end

-- Send data_len of bytes from data to the socket
-- Returns data_len if succesfull, returns nil, error if not
-- If data_len is nil, send data:len() bytes

--
-- HTTP functions
--
function errorhandle(err, cor, skt)
    print("Copas error handler called: " .. err)

    response = mt_engine.create_response(skt)
    response:set_status(500, "Internal Server Error")
    response.content = err
    response:send_status()
    response:send_headers()
    response:send_content()
end

function handle_connection(c)
    c = copas.wrap(c)
    copas.setErrorHandler(errorhandle)
    request, err = mt_engine.create_request(c)
    if request == nil then print("Client error: " .. err)
        -- TODO: send bad request response
    else
        -- Create a default response object
        local response = mt_engine.create_response(c)
        vprint("Calling request handler from script")
        response = script:handle_request(request, response)
        if response ~= nil then
            response:send_status()
            response:send_headers()
            response:send_content()
        end
        -- TODO check if closed, and whether it SHOULD be closed,
        -- and/or we should read another request
        c:close()
    end
end

function run()
    -- Load the handler script and call its initialization
    script_to_run, host, port, script_args = parse_args(arg)
    script = dofile(script_to_run)
    local r, err = script:init(script_args)
    if r == nil then
        print("Error initializing handler: " .. err)
        return nil, err
    end

    -- Bind to the socket and start listening for connections
    vprint("Binding to host '" ..host.. "' and port " ..port.. "...")
    s = assert(socket.bind(host, port))
    i, p   = s:getsockname()
    assert(i, p)
    vprint("Waiting connection from client on " .. i .. ":" .. p .. "...")
    
    -- fire it up
    copas.addserver(s, handle_connection)
    copas.loop()
end
minittp.run = run

return minittp
