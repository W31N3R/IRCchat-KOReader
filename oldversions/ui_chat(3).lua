--[[--
Chat UI widget for ircchat.koplugin.
--]]--

local Blitbuffer       = require("ffi/blitbuffer")
local Button           = require("ui/widget/button")
local CenterContainer  = require("ui/widget/container/centercontainer")
local Device           = require("device")
local Font             = require("ui/font")
local FrameContainer   = require("ui/widget/container/framecontainer")
local Geom             = require("ui/geometry")
local HorizontalGroup  = require("ui/widget/horizontalgroup")
local HorizontalSpan   = require("ui/widget/horizontalspan")
local InputDialog      = require("ui/widget/inputdialog")
local LineWidget       = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextWidget       = require("ui/widget/textwidget")
local UIManager        = require("ui/uimanager")
local VerticalGroup    = require("ui/widget/verticalgroup")
local VerticalSpan     = require("ui/widget/verticalspan")
local _                = require("gettext")
local Screen           = Device.screen

local MAX_DISPLAY_LINES = 200

local ChatUI = {}
ChatUI.__index = ChatUI

function ChatUI.new(_, opts)
    local o = setmetatable({
        title     = opts.title   or _("IRC Chat"),
        onSend    = opts.onSend  or function(_) end,
        onClose   = opts.onClose or function() end,
        lines     = {},
        _widget   = nil,
        _scroll_w = nil,
    }, ChatUI)
    return o
end

function ChatUI:show()
    self:_build()
end

function ChatUI:append(displayStr)
    table.insert(self.lines, tostring(displayStr))
    while #self.lines > MAX_DISPLAY_LINES do
        table.remove(self.lines, 1)
    end
    if self._widget and self._scroll_w then
        self._scroll_w:free()
        self._scroll_w.text = #self.lines > 0
            and table.concat(self.lines, "\n")
            or  _("(no messages yet)")
        self._scroll_w:init()
        self._scroll_w.dialog = self._widget  -- re-set after init() clears it
        self._scroll_w:scrollToRatio(1)
        UIManager:setDirty(self._widget, "ui")
    end
end

function ChatUI:close()
    self:_closeWidget()
    self.onClose()
end

function ChatUI:_closeWidget()
    if self._widget then
        UIManager:close(self._widget)
        self._widget  = nil
        self._scroll_w = nil
    end
end

function ChatUI:_build()
    local sw           = Screen:getWidth()
    local sh           = Screen:getHeight()
    local margin       = Screen:scaleBySize(15)
    local btn_height   = Screen:scaleBySize(42)
    local title_height = Screen:scaleBySize(36)
    local sep_height   = Screen:scaleBySize(2)
    local inner_w      = sw - margin * 2
    local text_h       = sh - title_height - sep_height - btn_height - sep_height - margin * 4

    local title_widget = TextWidget:new{
        text      = self.title,
        face      = Font:getFace("cfont", 18),
        bold      = true,
        max_width = inner_w - margin * 2,
    }

    local text_content = #self.lines > 0
        and table.concat(self.lines, "\n")
        or  _("(no messages yet)")

    local scroll_widget = ScrollTextWidget:new{
        text             = text_content,
        face             = Font:getFace("cfont", 14),
        width            = inner_w - margin * 2,
        height           = text_h,
        scroll_bar_width = Screen:scaleBySize(6),
    }
    self._scroll_w = scroll_widget

    local btn_w = math.floor((inner_w - margin * 3) / 2)

    local send_btn = Button:new{
        text     = _("Send"),
        width    = btn_w,
        callback = function() self:_openInputDialog() end,
    }

    local close_btn = Button:new{
        text     = _("Close"),
        width    = btn_w,
        callback = function() self:close() end,
    }

    local button_row = HorizontalGroup:new{
        align = "center",
        send_btn,
        HorizontalSpan:new{ width = margin },
        close_btn,
    }

    local vgroup = VerticalGroup:new{
        align = "left",
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = title_height },
            title_widget,
        },
        LineWidget:new{
            background = Blitbuffer.COLOR_DARK_GRAY,
            dimen      = Geom:new{ w = inner_w, h = sep_height },
        },
        VerticalSpan:new{ width = margin },
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = text_h },
            scroll_widget,
        },
        VerticalSpan:new{ width = margin },
        LineWidget:new{
            background = Blitbuffer.COLOR_DARK_GRAY,
            dimen      = Geom:new{ w = inner_w, h = sep_height },
        },
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = btn_height + margin },
            button_row,
        },
    }

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Screen:scaleBySize(2),
        radius     = Screen:scaleBySize(7),
        padding    = margin,
        dimen      = Geom:new{ w = sw, h = sh },
        vgroup,
    }

    local movable = MovableContainer:new{
        dimen = Geom:new{ w = sw, h = sh },
        frame,
    }

    self._widget = movable
    self._scroll_w.dialog = movable  -- required by ScrollTextWidget for scrollbar updates
    UIManager:show(movable)
    self._scroll_w:scrollToRatio(1)
end

function ChatUI:_openInputDialog()
    local input_dialog
    input_dialog = InputDialog:new{
        title   = _("Send message"),
        input   = "",
        buttons = {
            {
                {
                    text     = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text             = _("Send"),
                    is_enter_default = true,
                    callback         = function()
                        local text = input_dialog:getInputText()
                        UIManager:close(input_dialog)
                        if text and text ~= "" then
                            self:append(("[you] %s"):format(text))
                            self.onSend(text)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

return ChatUI
