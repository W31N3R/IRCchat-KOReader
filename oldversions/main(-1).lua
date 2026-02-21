--[[--
This is a plugin to connect to an IRC channel to send, recieve, and view old messages.
--]]--


local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local IRC = require("plugins/ircchat.koplugin/irc")
local ChatUI = require("plugins/ircchat.koplugin/ui_chat")
local Storage = require("plugins/ircchat.koplugin/storage")

local IrcChat = {
	client = nil,
	ui = nil,
	poll_s = 0.2,
	connected = false,
}

function IrcChat:init()
	self.store = Storage:new("ircchat_history.lua") -- storage directory
	self.ui = ChatUI:new{
		onSend = function(text) self:handleSend(text) end,
		onClose = function() self:disconnect() end,
	}
end

function IrcChat:connect(opts)
	self.client = IRC:new(opts)
	self.client:onLine(function(line) self:onIrcLine(line) end)
	self.client:onEvent(function(ev) self:onIrcEvent(ev) end)
	
	local ok, err = self.client:connect()
	if not ok then
		self.ui:append(("Connection Failed: %s"):format(err or "unknown"))
		return
	end
	
	self.connected = true
	self:poll()
end

function IrcChat:poll()
	if not self.connected then return end
	self.client:drain() -- non-blocking read
	UIManager:scheduleIn(self.poll_s, function() self:poll() end)
end

function IrcChat:onIrcLine(line)
	-- parse & render
	local msg = self.client:parse(line)
	if msg then
		self.ui:append(self.client:formatForDisplay(msg))
		self.store:append(msg)
	end
end

function IrcChat:onIrcEvent(ev)
	-- statechanges, notices, etc
end

function IrcChat:handleSend(text)
	if not self.connected then return end
	self.client:sendUserText(text) --handles /commands vs chat lines
end

function IrcChat:disconnect()
	self.connected = false
	if self.client then self.client:close() end
end

return IrcChat