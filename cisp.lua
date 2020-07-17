local function newState(s)
    _G.state = {
        source = s,
        idx = 1,
        row = 1,
        col = 1
    }
end

local escapeChar = {
    ["\\r"] = "\r",
    ["\\n"] = "\n",
    ["\\t"] = "\t",
    ["\\'"] = '"',
    ['\\"'] = "'"
}

TT_STRING = 0
TT_NAME = 1
TT_NUMBER = 2
TT_LIST = 3
TT_EMPTY = -1

local function makeTK(typ, val)
    if typ == TT_LIST then
        local t = val
        t.count = #val
        t.type = typ
        return t
    else
        return setmetatable({type = typ, value = val}, {__call = function (self)
            return self.value
        end})
    end
end

local function ast(b, msg)
    local rmsg = (msg or "Error") .. (" At Row: %d, Column: %d"):format(state.row, state.col)
    assert(b, rmsg)
end

local function current()
    local idx = state.idx
    return state.source:sub(idx, idx)
end

local function lookahead()
    local idx = state.idx + 1
    return state.source:sub(idx, idx)
end

local function next()
    local idx, col = state.idx, state.col
    local old = current()
    state.idx = idx + 1
    state.col = col + 1
    return old
end

local function isLine(c)
    return c == '\r' or c == '\n'
end

local function isSpace(c)
    return c == ' ' or c == '\t'
end

local function isWS(c)
    return isSpace(c) or isLine(c)
end

local function isComment()
    local cur, nex = current(), lookahead()
    return cur == ';' and (nex == cur or nex == ':')
end

local function isNumber(c)
    return (c >= '0' and c <= '9') or
    (c == '+' or c == '-' or c == '.')
end

local function isQuote(c)
    return c == "'" or c == '"'
end

local function nextRow()
    state.row = state.row + 1
end

local function resetCol()
    state.col = 1
end

local function skipWS()
    while isWS(current()) do
        local old = next()
        if isLine(old) then
            local cur = current()
            if isLine(cur) and cur ~= old then
                next()
            end
            nextRow()
            resetCol()
        end
    end
end

local function notEnd()
    return state.idx <= #state.source
end

local function skipComment()
    next()
    local sign = next()
    if sign == ';' then
        while not isLine(current()) do next() end
        return
    end
    while current() ~= ':' and lookahead() ~= ';' do
        ast(notEnd(), "Missing :;")
        local old = next()
        if isLine(old) then
            local cur = current()
            if isLine(cur) and cur ~= old then
                next()
            end
            nextRow()
            resetCol()
        end
    end
    next(); next()
end

local function readString()
    local str, sign = "", next()
    local msg = "Missing " .. sign
    while current() ~= sign do
        ast(notEnd(), msg)
        local char = next()
        local nex = current()
        local e = escapeChar[char .. nex]
        if e then
            char = e
            next()
        end
        str = str .. char
    end
    next()
    return makeTK(TT_STRING, str)
end

local function readName()
    local str = ""
    while notEnd() and isWS(current()) == false and current() ~= ")" do
        str = str .. next()
    end
    if str:sub(1, 1) == "@" then
        return makeTK(TT_STRING, str:sub(2))
    end
    return makeTK(TT_NAME, str)
end

local function readNumber()
    local str = ""
    while notEnd() and isNumber(current()) do
        str = str .. next()
    end
    local num = tonumber(str)
    ast(num, "Can't convert to number")
    return makeTK(TT_NUMBER, num)
end

local function skipBad()
    while isWS(current()) or isComment() do
        if isWS(current()) then
            skipWS()
        else
            skipComment()
        end
    end
end

local function readNext()
    local cur, nex = current(), lookahead()
    if isQuote(cur) then
        return readString()
    elseif isNumber(cur) and nex ~= "." then
        return readNumber()
    else
        return readName()
    end
end

local function readList()
    local t = {}
    next()
    while current() ~= ")" do
        skipBad()
        if not notEnd() then break end
        if current() == ")" then break end
        local c = current()
        local v
        if c == "(" then
            v = readList()
        else
            v = readNext()
        end
        t[#t + 1] = v
        if current() == ")" or not notEnd() then break end
        ast(isWS(current()), "Missing separate")
    end
    next()
    return makeTK(TT_LIST, t)
end

local function parse(s)
    newState("(" .. s .. ")")
    return readList()
end

local index, node = 1, {}
local lastNode = {}

local function bfree(tbl)
    for k in pairs(tbl) do
        tbl[k] = nil
    end
    tbl = nil
    collectgarbage"collect"
end

local function newNode(n)
    bfree(lastNode)
    for k, v in pairs(node) do
        lastNode[k] = v
    end
    lastNode[1] = lastNode[1] or makeTK(TT_EMPTY)
    bfree(node)
    node = n
    index = 1
end

local function look()
    local v = node[index]
    ast(v, "Got nil")
    return v
end

local function eat()
    local v = look()
    index = index + 1
    return v
end

local binOper = {
    ["add"] = '+',
    ["sub"] = '-',
    ["mul"] = '*',
    ["div"] = '/',
    ["mod"] = '%',
    ["pow"] = '^',
    ["eq"] = '==',
    ["neq"] = '~=',
    ["ge"] = '>=',
    ["gt"] = '>',
    ["le"] = '<=',
    ["lt"] = '<',
    ["cc"] = '..',
    ["and"] = 'and',
    ["or"] = 'or',
}

local unrOper = {
    ["len"] = "#",
    ["not"] = "not"
}

local operPrty = {
    ['^'] = 10,
    ['not'] = 9,
    ['#'] = 9,
    ['*'] = 8,
    ['/'] = 8,
    ['%'] = 8,
    ['+'] = 7,
    ['-'] = 7,
    ['..'] = 6,
    ['>'] = 5,
    ['<'] = 5,
    ['>='] = 5,
    ['<='] = 5,
    ['~='] = 5,
    ['=='] = 5,
    ['and'] = 4,
    ['or'] = 4
}

local kwList = {
    ["if"] = true,
    ["while"] = true,
    ["for"] = true,
    ["repeat"] = true,
    ["func"] = true,
    ["lfunc"] = true,
    ["localfunc"] = true,
    ["def"] = true,
    ["localdef"] = true,
    ["index"] = true,
    ["forin"] = true,
    ["break"] = true,
    ["return"] = true,
    ["list"] = true,
    ["do"] = true,
    ["array"] = true,
    ["_"] = true,
}

local stmtTemp = {
    ["if"] = "if {expr} then {stmt}{ else <stmt>} end",
    ["while"] = "while {expr} do {stmt} end",
    ["for"] = "for {name} = {val}, {val}{, <val>} do {stmt} end",
    ["repeat"] = "repeat {stmt} until {expr}",
    ["func"] = "{code} = function ({arg}) {stmt} end",
    ["lfunc"] = "local function ({arg}) {stmt} end",
    ["localfunc"] = "local {code} = function ({arg}) {stmt} end",
    ["def"] = "{code} = {code}",
    ["localdef"] = "local {code} = {code}",
    ["index"] = "{name}{idx}",
    ["forin"] = "for {arg} in {name}({arg}) do {stmt} end",
    ["break"] = "break",
    ["return"] = "return {array}",
    ["list"] = "{list}",
    ["array"] = "{array}",
    ["do"] = "do {stmt} end",
    ["_"] = "{code}({<array>})",
}

--[[local extra = require("extraGrammar")
for k, v in pairs(extra) do
    stmtTemp[k] = v
end]]

local function isBin(c)
    return binOper[c] ~= nil
end

local function getBin(c)
    ast(isBin(c))
    return binOper[c]
end

local function getUnr(c)
    ast(not isBin(c))
    return unrOper[c]
end

local function getOperPrty(c)
    local v = operPrty[c or 0]
    return v or -1
end

local function getOper(c)
    if isBin(c) then
        return getBin(c)
    else
        return getUnr(c)
    end
end

local function copy(t)
    local r = {}
    for k, v in pairs(t) do
        if type(v) == 'table' then
            r[k] = copy(v)
        else
            r[k] = v
        end
    end
    return r
end

local function isOper(c)
    return (binOper[c] or unrOper[c]) ~= nil
end

local t = {
    replace = function (self, fstr)
        local str = fstr:sub(2, -2)
        if str == "expr" then
            return self:compileExprTo(eat())
        elseif str == "stmt" then
            local r = ""
            local stmt = eat()
            for i = 1, stmt.count do
                r = r .. self:compileStmtTo(stmt[i])
            end
            return r
        elseif str == "code" then
            return self:compileLineTo(eat())
        elseif str == "val" then
            return tostring(eat().value)
        elseif str == "name" then
            local n = eat().value
            assert(n, "Need name, got code")
            return n
        elseif str == "arg" then
            local tp = eat()
            local r = {}
            for i = 1, tp.count do
                local n = tp[i].value
                assert(n, "Need name, got code")
                r[#r + 1] = n
            end
            return table.concat(r, ", ")
        elseif str == "idx" then
            local r = {}
            while node[index] do
                local tk = eat()
                local s = self:compileLineTo(tk)
                if tk.type == TT_STRING or tostring(tk.value):find(" ") then
                    s = s
                end
                r[#r + 1] = s
            end
            return "[" .. table.concat(r, "][") .. "]"
        elseif str == "list" then
            local r = {}
            assert((#node-1) % 2 == 0, "Too less arguments")
            for i = 2, #node-1, 2 do
                r[#r + 1] = "[\"" .. self:compileLineTo(node[i]) .. "\"]" .. " = " .. self:compileLineTo(node[i+1])
            end
            return table.concat(r, ", ")
        elseif str == "array" then
            local r = {}
            while node[index] do
                local tk = eat()
                local s = self:compileLineTo(tk)
                r[#r + 1] = s
            end
            return table.concat(r, ", ")
        else
            assert(str:find("<"), "Missing code")
            if node[index] then
                local r = str:gsub("<[^>]+>", function (fstr)
                    local r = self:replace(fstr)
                    return r
                end)
                return r
            end
            return ""
        end
    end,
    compileExprTo = function (self, tk)
        local ln, n, idx = copy(lastNode), copy(node), index
        newNode(tk)
        local r = self:exprToCode()
        lastNode = ln
        node = n
        index = idx
        return r
    end,
    compileStmtTo = function (self, tk)
        local ln, n, idx = copy(lastNode), copy(node), index
        newNode(tk)
        local r = self:stmtToCode()
        lastNode = ln
        node = n
        index = idx
        return r
    end,
    compileLineTo = function (self, tk)
        if tk.type == TT_LIST then
            local ln, n, idx = copy(lastNode), copy(node), index
            newNode(tk)
            local r
            local tv = tk[1].value
            if isOper(tv) then
                r = self:exprToCode()
            else
                r = self:stmtToCode()
            end
            lastNode = ln
            node = n
            index = idx
            return r
        else
            if tk.type == TT_STRING then
                if tk.value:find("\r\n", 1, true) then
                    return "[=[" .. tk.value .. "]=]"
                end
                return "\"" .. tk.value .. "\""
            end
            return tk.value
        end
    end,
    exprToCode = function (self)
        local sign = eat()
        local rs = ""
        ast(sign.type == TT_NAME)
        local sv = sign.value
        if isBin(sv) then
            local l = self:compileLineTo(eat())
            local r = self:compileLineTo(eat())
            rs = table.concat({l, getBin(sv), r}, ' ')
        else
            rs = table.concat({getUnr(sv), self:compileLineTo(eat())})
        end
        local spri = getOperPrty(getOper(sv))
        local lpri = getOperPrty(getOper(lastNode[1].value))
        if lpri >= spri then
            rs = "(" .. rs .. ")"
        end
        return rs
    end,
    stmtToCode = function (self)
        local sign = look().value
        local temp = stmtTemp[sign]
        if not temp then
            temp = stmtTemp._
        else
            eat()
        end
        local r = temp:gsub("{[^}]+}", function (fstr)
            local r = self:replace(fstr)
            return r
        end)
        if sign == "list" or sign == "array" then
            r = "{" .. r .. "}"
        end
        return r .. " "
    end,
    compile = function (self, str)
        local n = parse(str)
        local r = {}
        for i = 1, #n do
            r[#r + 1] = self:compileLineTo(n[i])
        end
        return table.concat(r)
    end,
    compileFromFile = function (self, name)
        local f = io.open(name, "r")
        local r = self:compile(f:read"*a")
        f:close()
        return r
    end
}
