local function newState(s)
    _G.state = {
        source = s,
        idx = 1,
        row = 1,
        col = 1
    }
end

local escapeChar = {
    ["\\r"] = "\\r",
    ["\\n"] = "\\n",
    ["\\t"] = "\\t",
    ["\\'"] = '\"',
    ['\\"'] = "\'"
}

TT_STRING = 0
TT_NAME = 1
TT_NUMBER = 2
TT_LIST = 3
TT_INDEX = 4
TT_TABLE = 5
TT_ARRAY = 6
TT_EMPTY = -1

local function makeTK(typ, val)
    if typ >= TT_LIST then
        local t = val
        t.count = #val
        t.type = typ
        t.col, t.row = state.col, state.row
        return t
    else
        return {type = typ, value = val, row = state.row, col = state.col}
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

local function isNumber(c, nex)
    return (c >= '0' and c <= '9') or
    ((c == '+' or c == '-' or c == '.') and (nex >= '0' and nex <= '9'))
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
    local isName = false
    if current() == "!" then
        isName = true
        next()
    end
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
    if isName then
        return makeTK(TT_NAME, str)
    else
        return makeTK(TT_STRING, str)
    end
end

local signs = {
    ["("] = ")",
    ["["] = "]",
    ["{"] = "}",
    ["<"] = ">"
}

local signInversed = {
    [")"] = "(",
    ["]"] = "[",
    ["}"] = "{",
    [">"] = "<"
}

local signType = {
    ["("] = TT_LIST,
    ["["] = TT_INDEX,
    ["{"] = TT_TABLE,
    ["<"] = TT_ARRAY
}

local function readName()
    local str = ""
    while notEnd() and isWS(current()) == false and signInversed[current()] == nil do
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
    ast(num, ("Can't convert %s to number"):format(str))
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
    local cur = current()
    if isQuote(cur) then
        return readString()
    elseif isNumber(cur, lookahead()) then
        return readNumber()
    else
        return readName()
    end
end

local function readList()
    local t = {}
    local sign = next()
    local endSign = signs[sign]
    while current() ~= endSign do
        skipBad()
        if not notEnd() then break end
        if current() == endSign then break end
        local c = current()
        local v
        if signs[c] then
            v = readList()
        else
            v = readNext()
        end
        t[#t + 1] = v
        if current() == endSign or false == notEnd() then break end
        ast(isWS(current()), "Missing separate character")
    end
    next()
    return makeTK(signType[sign] or TT_EMPTY, t)
end

local parse = function (s)
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
    assert(v, "Got nil")
    return v
end

local function cAst(b, msg)
    local tk = node[index] or node[index-1]
    local rmsg = (msg or "Error") .. (" At Row: %d, Column: %d"):format(tk.row, tk.col)
    assert(b, rmsg)
end

local function eat()
    local v = look()
    index = index + 1
    return v
end

local binOper = {
    ["+"] = '+',
    ["-"] = '-',
    ["*"] = '*',
    ["/"] = '/',
    ["%"] = '%',
    ["^"] = '^',
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
    ["if"] = "if {expr} then\n {stmt}{ \nelse\n <stmt>}\n end",
    ["while"] = "while {expr} do\n {stmt}\n end",
    ["for"] = "for {name} = {val}, {val}{, <val>} do\n {stmt}\n end",
    ["repeat"] = "repeat\n {stmt}\n until {expr}",
    ["func"] = "{code} = function ({arg})\n {stmt}\n end",
    ["lfunc"] = "local function ({arg})\n {stmt}\n end",
    ["localfunc"] = "local {code} = function ({arg})\n {stmt}\n end",
    ["def"] = "{code} = {code}",
    ["localdef"] = "local {code} = {code}",
    --["index"] = "{name}{idx}",
    ["forin"] = "for {arg} in {name}({arg}) do\n {stmt}\n end",
    ["break"] = "break",
    ["return"] = "return {array}",
    --["list"] = "{list}",
    --["array"] = "{array}",
    ["do"] = "do\n {stmt}\n end",
    ["_"] = "{code}({<array>})",
    ["multdef"] = "{arg} = {array}",
    ["multldef"] = "local {arg} = {array}",
    ["nfunc"] = "function ({arg})\n {stmt}\n end",
    ["inv"] = "-{expr}",
    ["luaexpr"] = "{code}"
}

TEMP_TABLE = "{list}"
TEMP_ARRAY = "{array}"
TEMP_INDEX = "{name}{idx}"

local function isBin(c)
    return binOper[c] ~= nil
end

local function getBin(c)
    cAst(isBin(c))
    return binOper[c]
end

local function getUnr(c)
    cAst(not isBin(c))
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

local compiler

compiler = {
    replace = function (fstr)
        local str = fstr:sub(2, -2)
        if str == "expr" then
            return compiler.compileExprTo(eat())
        elseif str == "stmt" then
            local r = ""
            local stmt = eat()
            for i = 1, stmt.count do
                r = r .. compiler.compileStmtTo(stmt[i])
            end
            return r
        elseif str == "code" then
            return compiler.compileLineTo(eat())
        elseif str == "val" then
            return tostring(eat().value)
        elseif str == "name" then
            local n = eat().value
            cAst(n, "Need name, got code")
            return n
        elseif str == "arg" then
            local tp = eat()
            local r = {}
            for i = 1, tp.count do
                local n = tp[i].value
                cAst(n, "Need name, got code")
                r[#r + 1] = n
            end
            return table.concat(r, ", ")
        elseif str == "idx" then
            local r = {}
            while node[index] do
                local tk = eat()
                local s = compiler.compileLineTo(tk)
                if tk.type == TT_STRING or tostring(tk.value):find(" ") then
                    s = s
                end
                r[#r + 1] = s
            end
            return "[" .. table.concat(r, "][") .. "]"
        elseif str == "list" then
            local r = {}
            cAst(node.count % 2 == 0, "Too less arguments")
            for i = 1, node.count - 1, 2 do
                r[#r + 1] = "[\"" .. compiler.compileLineTo(node[i]) .. "\"]" .. " = " .. compiler.compileLineTo(node[i+1])
            end
            return table.concat(r, ", ")
        elseif str == "array" then
            local r = {}
            while node[index] do
                local tk = eat()
                local s = compiler.compileLineTo(tk)
                r[#r + 1] = s
            end
            return table.concat(r, ", ")
        else
            cAst(str:find("<"), "Missing code")
            if node[index] then
                local r = str:gsub("<[^>]+>", function (fstr)
                    local r = compiler.replace(fstr)
                    return r
                end)
                return r
            end
            return ""
        end
    end,
    compileExprTo = function (tk)
        local ln, n, idx = copy(lastNode), copy(node), index
        newNode(tk)
        local r = compiler.exprToCode()
        lastNode = ln
        node = n
        index = idx
        return r
    end,
    compileStmtTo = function (tk)
        local ln, n, idx = copy(lastNode), copy(node), index
        newNode(tk)
        local r = compiler.stmtToCode()
        lastNode = ln
        node = n
        index = idx
        return r
    end,
    compileLineTo = function (tk)
        if tk.type >= TT_LIST then
            local ln, n, idx = copy(lastNode), copy(node), index
            newNode(tk)
            local r
            if tk.type == TT_TABLE then
                r = "{" .. compiler.split(TEMP_TABLE) .. "}"
            elseif tk.type == TT_ARRAY then
                r = "{" .. compiler.split(TEMP_ARRAY) .. "}"
            elseif tk.type == TT_INDEX then
                r = compiler.split(TEMP_INDEX)
            else
                local tv = tk[1].value
                if isOper(tv) then
                    r = compiler.exprToCode()
                else
                    r = compiler.stmtToCode()
                end
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
    exprToCode = function ()
        local sign = eat()
        local rs = ""
        cAst(sign.type == TT_NAME)
        local sv = sign.value
        if isBin(sv) then
            local l = compiler.compileLineTo(eat())
            local r = compiler.compileLineTo(eat())
            rs = table.concat({l, getBin(sv), r}, ' ')
        else
            rs = table.concat({getUnr(sv), compiler.compileLineTo(eat())})
        end
        local spri = getOperPrty(getOper(sv))
        local lpri = getOperPrty(getOper(lastNode[1].value))
        if lpri >= spri then
            rs = "(" .. rs .. ")"
        end
        return rs
    end,
    split = function (temp)
        local r = temp:gsub("{[^}]+}", function (fstr)
            local r = compiler.replace(fstr)
            return r
        end)
        return r
    end,
    stmtToCode = function ()
        local sign = look().value
        local temp = stmtTemp[sign]
        if not temp then
            temp = stmtTemp._
        else
            eat()
        end
        local r = compiler.split(temp)
        if sign == "list" or sign == "array" then
            r = "{" .. r .. "}"
        end
        return r .. " "
    end,
    compile = function (str)
        local linePos = str:find("%$", 2)
        local luaPath = str:sub(2, (linePos or 2) - 1)
        local rstr = str:sub(linePos + 1)
        local n = parse(rstr)
        local r = {}
        for i = 1, #n do
            r[#r + 1] = compiler.compileLineTo(n[i])
        end
        return table.concat(r, "\n"), luaPath
    end,
    compileFromFile = function (name)
        local f = io.open(name, "r")
        local r, path = compiler.compile(f:read"*a")
        f:close()
        return r, path
    end
}

local lua, path = compiler.compileFromFile("test.cisp")
print(lua)
local file = io.open(path, "w")
file:write(lua)
file:close()
