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
        t.type = typ
        return t
    else
        return {type = typ, value = val}
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
    return makeTK(TT_STRING, str)
end

local function readName()
    local str = ""
    while notEnd() and isWS(current()) == false and current() ~= ")" do
        str = str .. next()
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
    elseif isNumber(cur) then
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
        if current() == ")" then break end
        ast(isWS(current()), "Missing separate")
    end
    next()
    return makeTK(TT_LIST, t)
end

local function parse(s)
    newState("(" .. s .. ")")
    return readList()
end

local NUM_OF_ARG, index, node = 10, 1, {}
local lastNode = {}

local function bfree(tbl)
    for k in pairs(tbl) do
        tbl[k] = nil
    end
    tbl = nil
    collectgarbage"collect"
end

local function reqArg(num)
    NUM_OF_ARG = num
    ast(#node <= NUM_OF_ARG, "Too many arguments")
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
    ast(v)
    return v
end

local function eat()
    ast(index <= NUM_OF_ARG, "Out of range")
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
    ["ifcond"] = true,
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
    ["call"] = true
}

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
    toCode = function (self, tk)
        if tk.type == TT_LIST then
            local ln, n, idx = copy(lastNode), copy(node), index
            newNode(tk)
            local r
            local tv = tk[1].value
            if isOper(tv) then
                r = self:toExpr()
            elseif kwList[tv] then
                r = self:toStmt()
            else
                local s = self:toCode(tk[1]) .. "("
                for i = 2, #tk do
                    s = s .. self:toCode(tk[i]) .. ", "
                end
                return s:sub(1, -3) .. ")"
            end
            lastNode = ln
            node = n
            index = idx
            return r
        else
            return tk.value
        end
    end,
    toExpr = function (self)
        local sign = eat()
        local rs = ""
        ast(sign.type == TT_NAME)
        local sv = sign.value
        if isBin(sv) then
            reqArg(3)
            local l = self:toCode(eat())
            local r = self:toCode(eat())
            rs = table.concat({l, getBin(sv), r}, ' ')
        else
            reqArg(2)
            rs = table.concat({getUnr(sv), self:toCode(eat())})
        end
        local spri = getOperPrty(getOper(sv))
        local lpri = getOperPrty(getOper(lastNode[1].value))
        if lpri >= spri then
            rs = "(" .. rs .. ")"
        end
        return rs
    end,
    toStmt = function (self)
        --[[
            (if expr thenstmt elsestmt)
            (ifcond expr thenstmt expr elifstmt ...)
            (while expr dostmt)
            (for i from to inc dostmt)
            (repeat dostmt expr)
            (func name arg1 arg2 ... body)
            (lfunc arg1 arg2 ... body)
            (localfunc name arg1 arg2 ... body)

            (def name value)
            (localdef name value)
            (index tbl idx1 idx2 ...)
            (forin k v ... pmode tbl dostmt)
                pmode: a function name with P at start
                        Ppairs
                        Pipairs
            (break)
            (return r1 r2 ...)
            (list (a 10) (b 20) (1 2))
        ]]
        local sign = eat()
        ast(sign.type == TT_NAME)
        local sv = sign.value
        if sv == 'return' then
            local args = {}
            for i = index, #node do
                args[#args+1] = self:toCode(node[i])
            end
            return "return " .. table.concat(args, ", ") .. ';'
        elseif sv == 'list' then
            local kv = {}
            for i = index, #node do
                local c = eat()
                ast(c.type == TT_LIST)
                local k, v = self:toCode(c[1]), self:toCode(c[2])
                if c[1].type == TT_STRING or c[1].type == TT_NAME then
                    k = "'" .. k .. "'"
                end
                kv[#kv+1] = '[' .. k .. ']' .. " = " .. v
            end
            return "{" .. table.concat(kv, ", ") .. "}"
        elseif sv == 'break' then
            return "break;"
        elseif sv == 'forin' then
            local arg = {}
            while true do
                local cur = look()
                if cur.value then
                    if tostring(cur.value):sub(1, 1) == "P" then
                        break
                    end
                end
                ast(cur.type == TT_NAME)
                arg[#arg+1] = cur.value
                eat()
            end
            local pairfunc = eat()
            ast(pairfunc.type == TT_NAME)
            pairfunc = pairfunc.value:sub(2)
            local tbl = eat()
            ast(tbl.type == TT_NAME)
            tbl = tbl.value
            local _body = eat()
            local body = ""
            for i = 1, #_body do
                body = body .. self:toCode(_body[i])
            end
            return table.concat{"for ", table.concat(arg, ", "), " in ", pairfunc, "(", tbl, ") do ", body, " end;"}
        elseif sv == 'index' then
            local s = ""
            local tbl = eat()
            ast(tbl.type == TT_NAME or tbl.type == TT_LIST)
            if tbl.type == TT_LIST then
                tbl = '('..self:toCode(tbl)..')'
            else
                tbl = tbl.value
            end
            for i = index, #node do
                local k = '['
                local ctk = eat()
                if ctk.type == TT_STRING or ctk.type == TT_NAME then
                    k = k  .. '"' .. ctk.value .. '"]'
                else
                    k = k .. ctk.value .. ']'
                end
                s = s .. k
            end
            return tbl .. s
        elseif sv == 'def' then
            return self:toCode(eat()) .. " = " .. self:toCode(eat()) .. ';'
        elseif sv == 'localdef' then
            return "local" .. self:toCode(eat()) .. " = " .. self:toCode(eat()) .. ';'
        end
    end
}

local n = parse("(def (index a 1 2 3) (list (a 10) (b 20)))")
newNode(n[1])
print(t:toStmt())