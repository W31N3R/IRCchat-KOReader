--[[--
ircchat.koplugin - Connect to an IRC channel, send, receive, and view past messages.

@module koplugin.ircchat
--]]--

local Dispatcher      = require("dispatcher")
local InputDialog     = require("ui/widget/inputdialog")
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local IRC     = require("irc")
local ChatUI  = require("ui_chat")
local Storage = require("storage")

-- Plugin class

local IrcChat = WidgetContainer:extend{
    name        = "ircchat",
    is_doc_only = false,
    -- instance fields (default values)
    client      = nil,
    chat_ui     = nil,
    store       = nil,
    connected   = false,
    poll_s      = 0.2,
}

-- Lifecycle

function IrcChat:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.store = Storage:new("ircchat_history.lua")
end

function IrcChat.onDispatcherRegisterActions(_self)
    Dispatcher:registerAction("ircchat_open", {
        category = "none",
        event    = "IrcChatOpen",
        title    = _("IRC Chat"),
        general  = true,
    })
end

-- Menu

function IrcChat:addToMainMenu(menu_items)
    menu_items.ircchat = {
        text         = _("IRC Chat"),
        sorting_hint = "more_tools",
        callback     = function()
            self:onIrcChatOpen()
        end,
    }
end

-- Dispatcher event handler

function IrcChat:onIrcChatOpen()
    if self.connected then
        -- Already connected - just re-show the UI.
        if self.chat_ui then
            self.chat_ui:show()
        end
    else
        self:_showServerDialog()
    end
end

-- Connection dialogs (3-step: server -> channel -> nick)

function IrcChat:_showServerDialog()
    local dlg
    dlg = InputDialog:new{
        title       = _("IRC Server  (host or host:port)"),
        input       = "irc.libera.chat:6667",
        description = _("Example: irc.libera.chat:6667"),
        buttons     = {
            {
                {
                    text     = _("Cancel"),
                    callback = function() UIManager:close(dlg) end,
                },
                {
                    text             = _("Next →"),
                    is_enter_default = true,
                    callback         = function()
                        local val = dlg:getInputText()
                        UIManager:close(dlg)
                        if val and val ~= "" then
                            self:_showChannelDialog(val)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function IrcChat:_showChannelDialog(server_str)
    local dlg
    dlg = InputDialog:new{
        title       = _("Channel to join"),
        input       = "#koreader",
        description = _("Include the # (e.g. #koreader)"),
        buttons     = {
            {
                {
                    text     = _("← Back"),
                    callback = function()
                        UIManager:close(dlg)
                        self:_showServerDialog()
                    end,
                },
                {
                    text             = _("Next →"),
                    is_enter_default = true,
                    callback         = function()
                        local val = dlg:getInputText()
                        UIManager:close(dlg)
                        if val and val ~= "" then
                            self:_showNickDialog(server_str, val)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function IrcChat:_showNickDialog(server_str, channel)
    local dlg
    dlg = InputDialog:new{
        title       = _("Your nickname"),
        input       = "KOReader_User",
        buttons     = {
            {
                {
                    text     = _("← Back"),
                    callback = function()
                        UIManager:close(dlg)
                        self:_showChannelDialog(server_str)
                    end,
                },
                {
                    text             = _("Connect"),
                    is_enter_default = true,
                    callback         = function()
                        local nick = dlg:getInputText()
                        UIManager:close(dlg)
                        if nick and nick ~= "" then
                            self:_doConnect(server_str, channel, nick)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

-- Core connect / disconnect

function IrcChat:_doConnect(server_str, channel, nick)
    -- Parse "host" or "host:port"
    local host, port_str = server_str:match("^([^:]+):?(%d*)$")
    host = host or server_str
    local port = (port_str and port_str ~= "") and tonumber(port_str) or 6667

    -- Build the ChatUI title and create it.
    local title = ("%s @ %s"):format(channel, host)
    self.chat_ui = ChatUI:new{
        title   = title,
        onSend  = function(text) self:_handleSend(text) end,
        onClose = function() self:disconnect() end,
    }

    -- Pre-populate with stored history.
    local history = self.store:getLines()
    for _, line in ipairs(history) do
        self.chat_ui.lines[#self.chat_ui.lines + 1] = line
    end

    -- Show the UI first so the user gets feedback immediately.
    self.chat_ui:show()
    self.chat_ui:append(_("Connecting to ") .. host .. ":" .. tostring(port) .. " ...")

    -- Create and connect the IRC client.
    self.client = IRC:new{
        host    = host,
        port    = port,
        nick    = nick,
        channel = channel,
    }
    self.client:onLine(function(line) self:_onIrcLine(line) end)
    self.client:onEvent(function(ev)  self:_onIrcEvent(ev)  end)

    local ok, err = self.client:connect()
    if not ok then
        self.chat_ui:append(_("Connection failed: ") .. tostring(err or "unknown"))
        return
    end

    self.connected = true
    self.chat_ui:append(_("Connected. Joining ") .. channel .. " ...")
    self:poll()
end

-- Polling loop

function IrcChat:poll()
    if not self.connected then return end
    self.client:drain()   -- non-blocking read; fires onLine callbacks
    UIManager:scheduleIn(self.poll_s, function() self:poll() end)
end

-- Incoming message handling

function IrcChat:_onIrcLine(line)
    local msg = self.client:parse(line)
    if msg then
        local display = self.client:formatForDisplay(msg)
        self.chat_ui:append(display)
        -- Only persist PRIVMSG lines so history stays useful.
        if msg.cmd == "PRIVMSG" then
            self.store:append(display)
        end
    end
end

function IrcChat:_onIrcEvent(ev)
    if ev.type == "closed" then
        self.connected = false
        if self.chat_ui then
            self.chat_ui:append(_("*** Connection closed by server."))
        end
    end
end

-- Outgoing message handling

function IrcChat:_handleSend(text)
    if not self.connected then
        self.chat_ui:append(_("*** Not connected."))
        return
    end
    local ok, err = self.client:sendUserText(text)
    if ok == false then
        -- Send failed — socket probably dropped; mark disconnected
        self.connected = false
        self.chat_ui:append(_("*** Send failed: ") .. tostring(err or "unknown"))
        self.chat_ui:append(_("*** Connection lost. Please reconnect."))
    end
end

-- Disconnect

function IrcChat:disconnect()
    self.connected = false
    if self.client then
        self.client:raw("QUIT :Goodbye\r\n")
        self.client:close()
        self.client = nil
    end
end

return IrcChat
