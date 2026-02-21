--[[--
Minimal persistent message storage for ircchat.
Saves the last N messages to a Lua data file so they survive restarts.
--]]--

local DataStorage = require("datastorage")

local MAX_LINES = 300

local Storage = {}
Storage.__index = Storage

-- `filename` is just the base filename, e.g. "ircchat_history.lua"
-- The file will live in KOReader's data directory.
function Storage.new(_, filename)
    local path = DataStorage:getDataDir() .. "/" .. filename
    local o = setmetatable({
        path  = path,
        lines = {},
    }, Storage)
    o:_load()
    return o
end

-- Load existing history from disk (ignore errors if file missing).
function Storage:_load()
    local f = io.open(self.path, "r")
    if not f then return end
    local src = f:read("*a")
    f:close()
    if not src or src == "" then return end
    local fn = load("return " .. src)
    if fn then
        local ok, data = pcall(fn)
        if ok and type(data) == "table" then
            self.lines = data
        end
    end
end

-- Persist current lines to disk.
function Storage:_save()
    local f = io.open(self.path, "w")
    if not f then return end
    f:write("{\n")
    for _, v in ipairs(self.lines) do
        -- Escape backslashes and quotes, then write as a quoted string entry.
        local escaped = tostring(v):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
        f:write(('  "%s",\n'):format(escaped))
    end
    f:write("}\n")
    f:close()
end

-- Append a display string (already formatted) and persist.
function Storage:append(displayStr)
    table.insert(self.lines, tostring(displayStr))
    -- Trim to MAX_LINES
    while #self.lines > MAX_LINES do
        table.remove(self.lines, 1)
    end
    self:_save()
end

-- Return all stored lines as a single newline-joined string.
function Storage:getText()
    return table.concat(self.lines, "\n")
end

-- Return the raw lines table (read-only use only).
function Storage:getLines()
    return self.lines
end

-- Wipe history from memory and disk.
function Storage:clear()
    self.lines = {}
    local f = io.open(self.path, "w")
    if f then f:write("{}\n") f:close() end
end

return Storage
