local socket = require("socket") -- LuaSocket (in KOReader builds that use it)
local IRC = {}
IRC.__index = IRC

function IRC:new(opts)
	return setmetatable({
		host = opts.host,
		port = opts.port or 6667,
		nick = opts.nick,
		user = opts.user or opts.nick,
		real = opts.real or opts.nick,
		channel = opts.channel,
		sock = nil,
		buf = "",
		onLineCb = function(_) end,
		onEventCb = function(_) end,
	}, IRC)
end

function IRC:onLine(cb) self.onLineCb = cb end
function IRC:onEvent(cb) self.onEventCb = cb end

function IRC:connect()
	local s, err = socket.tcp()
	if not s then return false, err end
	s:settimeout(5)
	local ok, cerr = s:connect(self.host, self.port)
	if not ok then return false, cerr end
	s:settimeout(0) --non-blocking after connect
	self.sock = s
	
	self:raw(("NICK %s\r\n"):format(self.nick))
	self:raw(("USER %s 0 * :%s\r\n"):format(self.user, self.real))
	if self.channel then
		self:raw(("JOIN %s\r\n"):format(self.channel))
	end
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
			self.onEventCb({type="closed"})
			self:close()
			break
		end
	end
end

function IRC:onRawLine(line)
	-- respond to PING immediately
	local ping = line:match("^PING%s*:(.*)$")
	if ping then
		self:raw(("PONG :%s\r\n"):format(ping))
		return
	end
	self.onLineCb(line)
end

function IRC:parse(line)
	-- minimal parse: prefix, command, params, trailing
	local prefix, rest = line:match("^:([^ ]+) (.+)$")
	local cmd, params = rest and rest:match("^([^ ]+) (.*)$") or line:match("^([^ ]+) (.*)$")
	if not cmd then return nil end
	
	local trailing
	if params then
		local before, tr = params:match("^(.*) :(.+)$")
		if tr then params, trailing = before, tr end
	end
	
	return { raw=line, prefix=prefix, cmd=cmd, params=params, trailing=trailing }
end

function IRC:formatForDisplay(msg)
	if msg.cmd == "PRIVMSG" and msg.trailing then
		local nick = msg.prefix and msg.prefix:match("^([^!]+)!") or msg.prefix or "?"
		return ("%s: %s"):format(nick, msg.trailing)
	end
	return msg.raw
end

function IRC:sendPrivmsg(target, text)
	self:raw(("PRIVMSG %s :%s\r\n"):format(target, text))
end

function IRC:sendUserText(text)
	-- simple command handling
	if text:match("^/join%s+") then
		local chan = text:match("^/join%s+(%S+)")
		if chan then self:raw(("JOIN %s\r\n"):format(chan)) end
		return
	end
	if text:match("^/nick%s+") then
		local nick = text:match("^/nick%s+(%S+)")
		if nick then self:raw(("NICK %s\r\n"):format(nick)) end
		return
	end
	-- default: send to current channel
	if self.channel then
		self:sendPrivmsg(self.channel, text)
	end
end

return IRC