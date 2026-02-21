local socket = require("socket") -- LuaSocket (in KOReader builds that use it)

local IRC = {}
IRC.__index = IRC

function IRC.new(_, opts)
    return setmetatable({
        host      = opts.host,
        port      = opts.port or 6667,
        nick      = opts.nick,
        user      = opts.user or opts.nick,
        real      = opts.real or opts.nick,
        channel   = opts.channel,
        sock      = nil,
        buf       = "",
        onLineCb  = function(_) end,
        onEventCb = function(_) end,
    }, IRC)
end

function IRC:onLine(cb)  self.onLineCb  = cb end
function IRC:onEvent(cb) self.onEventCb = cb end

function IRC:connect()
    local s, err = socket.tcp()
    if not s then return false, err end
    s:settimeout(5)
    local ok, cerr = s:connect(self.host, self.port)
    if not ok then return false, cerr end
    s:settimeout(0) -- non-blocking after connect
    self.sock = s

    self:raw(("NICK %s\r\n"):format(self.nick))
    self:raw(("USER %s 0 * :%s\r\n"):format(self.user, self.real))
    -- Do NOT join here. Wait for 001 RPL_WELCOME in onRawLine before joining.
    return true
end

function IRC:close()
    if self.sock then pcall(function() self.sock:close() end) end
    self.sock = nil
end

function IRC:raw(s)
    if not self.sock then return end
    self.sock:send(s)
end

function IRC:drain()
    if not self.sock then return end
    while true do
        local chunk, err, partial = self.sock:receive("*l")
        local line = chunk or partial
        if line and #line > 0 then
            self:onRawLine(line)
        end
        if err == "timeout" then break end
        if err == "closed" then
            self.onEventCb({ type = "closed" })
            self:close()
            break
        end
    end
end

function IRC:onRawLine(line)
    -- Respond to PING immediately
    local ping = line:match("^PING%s*:(.*)$")
    if ping then
        self:raw(("PONG :%s\r\n"):format(ping))
        return
    end
    -- Wait for 001 RPL_WELCOME before joining — server isn't ready until then
    if line:match("^:[^ ]+ 001 ") then
        if self.channel then
            self:raw(("JOIN %s\r\n"):format(self.channel))
        end
        self.onEventCb({ type = "registered" })
        -- fall through so the 001 line still shows in the UI
    end
    self.onLineCb(line)
end

function IRC.parse(_, line)
    -- Minimal parse: prefix, command, params, trailing
    local prefix, rest = line:match("^:([^ ]+) (.+)$")
    local cmd, params
    if rest then
        cmd, params = rest:match("^([^ ]+) (.*)$")
        if not cmd then cmd = rest end
    else
        cmd, params = line:match("^([^ ]+) (.*)$")
        if not cmd then cmd = line end
    end
    if not cmd then return nil end

    local trailing
    if params then
        local before, tr = params:match("^(.*) :(.+)$")
        if tr then
            params, trailing = before, tr
        else
            -- handle trailing with no preceding params (e.g. ":text")
            tr = params:match("^:(.+)$")
            if tr then params, trailing = "", tr end
        end
    end

    return { raw = line, prefix = prefix, cmd = cmd, params = params, trailing = trailing }
end

function IRC.formatForDisplay(_, msg)
    if msg.cmd == "PRIVMSG" and msg.trailing then
        local nick = msg.prefix and msg.prefix:match("^([^!]+)!") or msg.prefix or "?"
        return ("[%s] %s"):format(nick, msg.trailing)
    end
    if msg.cmd == "JOIN" then
        local nick = msg.prefix and msg.prefix:match("^([^!]+)!") or msg.prefix or "?"
        return ("*** %s has joined"):format(nick)
    end
    if msg.cmd == "PART" or msg.cmd == "QUIT" then
        local nick = msg.prefix and msg.prefix:match("^([^!]+)!") or msg.prefix or "?"
        return ("*** %s has left"):format(nick)
    end
    if msg.cmd == "NOTICE" and msg.trailing then
        return ("NOTICE: %s"):format(msg.trailing)
    end
    -- Server numerics (001-005, 372 MOTD, etc.) - show trailing if available
    if msg.trailing then
        return msg.trailing
    end
    return msg.raw
end

function IRC:sendPrivmsg(target, text)
    self:raw(("PRIVMSG %s :%s\r\n"):format(target, text))
end

function IRC:sendUserText(text)
    -- Simple command handling
    if text:match("^/join%s+") then
        local chan = text:match("^/join%s+(%S+)")
        if chan then
            self:raw(("JOIN %s\r\n"):format(chan))
            self.channel = chan
        end
        return
    end
    if text:match("^/nick%s+") then
        local nick = text:match("^/nick%s+(%S+)")
        if nick then
            self:raw(("NICK %s\r\n"):format(nick))
            self.nick = nick
        end
        return
    end
    if text:match("^/part") then
        if self.channel then
            self:raw(("PART %s\r\n"):format(self.channel))
        end
        return
    end
    if text:match("^/quit") then
        self:raw("QUIT :Goodbye\r\n")
        return
    end
    -- Default: send to current channel
    if self.channel then
        self:sendPrivmsg(self.channel, text)
    end
end

return IRC
