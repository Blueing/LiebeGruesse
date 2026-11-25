-- Compact, safe serializer for strings, numbers, booleans and nested tables.
-- No code is ever loaded; malformed input returns nil.
local _, ns = ...
local Serialize = {}
ns.Serialize = Serialize

local concat, format, tostring, type = table.concat, string.format, tostring, type
local MAX_DEPTH = 24

local function write(value, out, depth)
    local t = type(value)
    if t == "string" then
        out[#out + 1] = "s" .. #value .. ":" .. value
    elseif t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            out[#out + 1] = "z"
        elseif value == math.floor(value) and math.abs(value) < 2 ^ 53 then
            out[#out + 1] = format("n%d;", value)
        else
            out[#out + 1] = "n" .. format("%.14g", value) .. ";"
        end
    elseif t == "boolean" then
        out[#out + 1] = value and "T" or "F"
    elseif t == "table" then
        if depth > MAX_DEPTH then error("Serialize: table too deep") end
        out[#out + 1] = "t"
        local n = #value
        for i = 1, n do write(value[i], out, depth + 1) end
        out[#out + 1] = "|"
        for k, v in pairs(value) do
            local array = type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)
            if not array then
                local kt, vt = type(k), type(v)
                if (kt == "string" or kt == "number" or kt == "boolean")
                    and (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
                    write(k, out, depth + 1)
                    write(v, out, depth + 1)
                end
            end
        end
        out[#out + 1] = "e"
    else
        out[#out + 1] = "z"
    end
end

function Serialize.Pack(value)
    local out = {}
    write(value, out, 0)
    return concat(out)
end

local function read(s, pos, depth)
    local tag = s:sub(pos, pos)
    if tag == "s" then
        local len, start = s:match("^(%d+):()", pos + 1)
        len = tonumber(len)
        if not len then return nil, nil, true end
        local stop = start + len - 1
        if stop > #s then return nil, nil, true end
        return s:sub(start, stop), stop + 1
    elseif tag == "n" then
        local num, after = s:match("^([%-%d%.eE+]+);()", pos + 1)
        num = tonumber(num)
        if not num then return nil, nil, true end
        return num, after
    elseif tag == "T" then return true, pos + 1
    elseif tag == "F" then return false, pos + 1
    elseif tag == "z" then return nil, pos + 1
    elseif tag == "t" then
        if depth > MAX_DEPTH then return nil, nil, true end
        local tbl, i = {}, 0
        pos = pos + 1
        while s:sub(pos, pos) ~= "|" do
            if pos > #s then return nil, nil, true end
            local v, nextPos, bad = read(s, pos, depth + 1)
            if bad then return nil, nil, true end
            i = i + 1
            tbl[i] = v
            pos = nextPos
        end
        pos = pos + 1
        while s:sub(pos, pos) ~= "e" do
            if pos > #s then return nil, nil, true end
            local k, p1, bad1 = read(s, pos, depth + 1)
            if bad1 or k == nil then return nil, nil, true end
            local v, p2, bad2 = read(s, p1, depth + 1)
            if bad2 then return nil, nil, true end
            tbl[k] = v
            pos = p2
        end
        return tbl, pos + 1
    end
    return nil, nil, true
end

function Serialize.Unpack(s)
    if type(s) ~= "string" or s == "" then return nil end
    local ok, value, pos, bad = pcall(read, s, 1, 0)
    if not ok or bad or pos ~= #s + 1 then return nil end
    return value
end

-- Transport escaping: addon messages must not contain NUL; newlines and
-- pipes are escaped too so chat code never sees them.
local ESC = { ["\0"] = "~0", ["\n"] = "~n", ["\r"] = "~r", ["|"] = "~p", ["~"] = "~~" }
local UNESC = { ["0"] = "\0", n = "\n", r = "\r", p = "|", ["~"] = "~" }

function Serialize.Escape(s)
    return (s:gsub("[%z\n\r|~]", ESC))
end

function Serialize.Unescape(s)
    return (s:gsub("~(.)", UNESC))
end
