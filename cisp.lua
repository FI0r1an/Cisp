local state

local function newState(s, fn)
    state = {
        src = s,
        fileName = fn or "*",
        idx = 1,
        row = 1,
        col = 1,
    }
end

local function isNum(c)
    return c >= '0' and c <= '9'
end

local function lcurr()
    return string.sub(state.src, state.idx, state.idx)
end

local function llookahead()
    local idx = state.idx + 1
    return string.sub(state.src, idx, idx)
end

local function lnext()
    local rsl = lcurr()

    state.idx = state.idx + 1
    state.col = state.col + 1
    return rsl
end

local function inclinenumber()
    local cur = lcurr()

    if cur == '\r' or cur == '\n' then
        local nex = llookahead()

        if (nex == '\r' or nex == '\n') and cur ~= nex then
            lnext()
        end

        lnext()
    end

    state.row = state.row + 1
    state.col = 1
end

local TT_STRING = 0
local TT_NAME = 1
local TT_NUMBER = 2
local TT_LIST = 3
local TT_INDEX = 4
local TT_TABLE = 5
local TT_TUPLE = 6
local TT_EOF = -1

local abort = false

local function cerror(msg, row, col, ...)
    if col then
        print(string.format("[%s %d:%d] %s", state.fileName, row, col, msg:format(...)))
    else
        print(string.format("[%s %d] %s", state.fileName, row, msg:format(...)))
    end

    abort = true
end

local function readString(rsl)
    local val, sign = "", lnext()

    while lcurr() ~= sign do
        local cur = lcurr()
        if cur == '' then
            cerror("Expected '%s'", rsl.row, rsl.col, sign)
            break
        end

        val = val .. cur
        if cur == '\r' or cur == '\n' then
            inclinenumber()
        else
            lnext()
        end
    end

    lnext()

    rsl.typ = TT_STRING
    rsl.val = val

    return rsl
end

local function isalpha(c)
    return c == '_' or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')
end

local tkNext

local function readName(rsl)
    local val = lnext()
    local cur = lcurr()
    local meetDot = false

    while isalpha(cur) or (cur >= '0' and cur <= '9') or cur == '.' do
        if meetDot then
            if cur >= '0' and cur <= '9' then
                cerror("Unexpected character '%s'", state.row, state.col, cur)
                return rsl
            else
                meetDot = false
            end
        end

        if cur == '.' then
            meetDot = true
            if llookahead() == cur then
                lnext()
                cur = ':'
            end
        end
        
        val = val .. cur

        lnext()
        cur = lcurr()
    end

    if val == '__' then
        val = '...'
    end
    
    rsl.typ = TT_NAME
    rsl.val = val

    return rsl
end

local function readNumber(rsl)
    local val = lnext()
    local meetPoint = val == '.'
    local cur = lcurr()

    while cur == '.' or cur >= '0' and cur <= '9' do
        if cur == '.' then
            if meetPoint then
                cerror("Unexpected character '.'", state.row, state.col)
                return rsl
            end
            meetPoint = true
        end

        val = val .. cur
        lnext()
        cur = lcurr()
    end

    rsl.typ = TT_NUMBER
    rsl.val = tonumber(val)
    if not rsl.val then
        cerror("Unrecognized number \"%s\"", rsl.row, rsl.col, val)
    end

    return rsl
end

local function skipThem()
    while true do
        local cur, nex = lcurr(), llookahead()

        if cur == '\r' or cur == '\n' then
            inclinenumber()
        elseif cur == ' ' or cur == '\t' then
            lnext()
        elseif cur == ';' then
            if nex == cur then
                while lcurr() ~= '\r' and lcurr() ~= '\n' do
                    lnext()
                end
                inclinenumber()
            elseif nex == ':' then
                while lcurr() ~= ':' or llookahead() ~= ';' do
                    cur = lcurr()

                    if cur == '\r' or cur == '\n' then
                        inclinenumber()
                    else
                        lnext()
                    end
                end
                lnext()
                lnext()
            else
                cerror("Unexpected character ';'", rsl.row, rsl.col)
                return rsl
            end
        else
            return
        end
    end
end

local function readList(rsl)
    local cur = lnext()
    local val = {}

    local sign

    if cur == '(' then
        sign = ')'
        rsl.typ = TT_LIST
    elseif cur == '[' then
        sign = ']'
        rsl.typ = TT_INDEX
    elseif cur == '<' then
        sign = '>'
        rsl.typ = TT_TUPLE
    elseif cur == '{' then
        sign = '}'
        rsl.typ = TT_TABLE
    end

    while lcurr() ~= sign do
        if lcurr() == '' then
            rsl.typ = -2
            cerror("Expected '%s'", rsl.row, rsl.col, sign)
            return rsl
        end

        skipThem()

        if lcurr() == sign then break end

        local tk = tkNext()
        if abort then
            rsl.typ = -2
            return rsl
        end

        skipThem()

        val[#val + 1] = tk
    end

    rsl.val = val
    lnext()

    return rsl
end

local TOKEN_MT = {__tostring = function (self)
    return string.format("[%d:%d] %d %s", self.row, self.col, self.typ, self.val)
end}

tkNext = function ()
    while true do
        skipThem()

        local rsl = setmetatable({
            row = state.row,
            col = state.col,
            typ = -2,
            val = 0,
        }, TOKEN_MT)

        local cur, nex = lcurr(), llookahead()

        if cur == '' then
            rsl.typ = TT_EOF
            return rsl
        elseif cur == '\'' or cur == '"' then
            return readString(rsl)
        elseif cur == '(' or cur == '<' or cur == '[' or cur == '{' then
            return readList(rsl)
        elseif (cur == '+' or cur == '-' or cur == '.') and (isNum(nex) or nex == '.') or isNum(cur) then
            return readNumber(rsl)
        elseif isalpha(cur) or cur == '@' then
            return readName(rsl)
        elseif cur == '+' or cur == '-' or cur == '*' or cur == '/' or
               cur == '%' or cur == '^' then
            lnext()
            rsl.typ = TT_NAME
            rsl.val = cur
            return rsl
        else
            cerror("Unexpected character '%s'", state.row, state.col, cur)
            return rsl
        end
    end
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

local stmtTemp = {
    ["if"] = "if {val} then {stmt}{ else <stmt>} end",
    ["match"] = "{match}",
    ["enum"] = "{enum}",
    ["while"] = "while {val} do {tail} end",
    ["for"] = "for {name} = {val}, {val}, {val} do {tail} end",
    ["repeat"] = "repeat {stmt} until {val}",
    ["func"] = "{val} = function ({arg}) {tail} end",
    ["localfunc"] = "local {val} = function ({arg}) {tail} end",
    ["def"] = "{val} = {val}",
    ["localdef"] = "local {val} = {val}",
    ["forin"] = "for {arg} in {name}({arg}) do {tail} end",
    ["break"] = "break",
    ["ret"] = "return {<tuple>}",
    ["do"] = "do {tail} end",
    ["multdef"] = "{arg} = {tuple}",
    ["multldef"] = "local {arg} = {tuple}",
    ["nfunc"] = "function ({arg}) {tail} end",
    ["inv"] = "-{val}",
    ["luaexpr"] = "{val}",
}

local TEMP_TABLE = "{list}"
local TEMP_TUPLE = "{tuple}"
local TEMP_INDEX = "({val}){idx}"
local TEMP_CALL = "{val}({<tuple>})"

local function isBin(c)
    return binOper[c] ~= nil
end

local function getBin(c)
    return binOper[c]
end

local function getUnr(c)
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

local function isOper(c)
    return (binOper[c] or unrOper[c]) ~= nil
end

local curtoken
local prilist = {}

local function pappendPrty(p)
    table.insert(prilist, p)
end

local function premovePrty()
    table.remove(prilist)
end

local function pnext()
    local rsl = curtoken

    curtoken = tkNext()

    return rsl
end

local compileToken
local compileStmt

local function compileExpr(tk)
    if tk.typ ~= TT_LIST then
        return compileToken(tk)
    end

    local list = tk.val
    local len = #list
    local oper = list[1].val
    local rsl

    assert(list[1].typ == TT_NAME and isOper(oper))

    local realOper = getOper(oper)
    local prty = getOperPrty(realOper)

    local prtyToComp = prilist[#prilist] or 0
    pappendPrty(prty)
    
    if oper == "cc" or oper == 'or' or oper == 'and' then
        rsl = {}

        for i = 2, len do
            local part = compileToken(list[i])

            if part == nil then
                return nil
            end

            rsl[#rsl + 1] = part
        end

        rsl = table.concat(rsl, (" %s "):format(realOper))
    elseif len == 2 and unrOper[oper] then
        local operand = compileToken(list[2])

        if operand == nil then
            return nil
        end
        rsl = ("%s %s"):format(realOper, operand)
    elseif len == 3 and binOper[oper] then
        local left, right = compileToken(list[2]), compileToken(list[3])

        if left == nil or right == nil then
            return nil
        end
        rsl = ("%s %s %s"):format(left, realOper, right)
    else
        cerror("Incorrect argument counts", tk.row, tk.col)
        return nil
    end
    
    premovePrty()
    if prty <= prtyToComp then
        return '(' .. rsl .. ')'
    end
    return rsl
end

local function compileTable(tk)
    local rsl = {}
    local list = tk.val
    local cnt = #list
    
    if cnt % 2 ~= 0 then
        cerror("Incorrect format", tk.row, tk.col)
        return nil
    end

    for i = 1, cnt, 2 do
        local kt = list[i]
        local k, v = compileToken(kt), compileToken(list[i + 1])

        if k == nil or v == nil then return nil end

        if kt.typ == TT_NAME then
            if k:sub(1, 1) == '@' then
                k = k:sub(2)
            else
                k = "\"" .. k .. "\""
            end
        end

        rsl[#rsl + 1] = "[" .. k .. "]" .. " = " .. v
    end
    return '{' .. table.concat(rsl, ", ") .. '}'
end

local function compileTuple(tk, init)
    local rsl = {}
    local len = #tk.val
        
    for idx = init or 1, len do
        local part = compileToken(tk.val[idx])

        if part == nil then
            return nil
        end

        rsl[#rsl + 1] = part

        idx = idx + 1
    end

    return table.concat(rsl, ", ")
end

local function compileStmtTag(idx, stmt)
    local stmts = stmt.val
    local len, rsl = #stmts, {}

    for i = idx, len do
        local current = stmts[i]

        if current.typ == TT_LIST then
            local head = current.val[1]

            if head and head.typ == TT_NAME and isOper(head.val) then
                local part = compileExpr(stmts[i])
                if not part then return nil end
    
                rsl[#rsl + 1] = "return " .. part
    
                return table.concat(rsl, "; ")
            else
                local part = compileStmt(stmts[i])
                if not part then return nil end

                rsl[#rsl + 1] = part
            end
        else
            local part = compileExpr(stmts[i])
            if not part then return nil end

            rsl[#rsl + 1] = "return " .. part

            return table.concat(rsl, "; ")
        end
    end

    return table.concat(rsl, "; ")
end

local compileByTemp

local tagTable = {
    match = function (idx, stmt)
        local list = stmt.val
        local matchee = list[idx]
        local rsl = {}
        local len = #list

        for i = idx + 1, len do
            local subStmt = list[i]

            if subStmt.typ == TT_LIST and #subStmt.val >= 2 then
                local expr = ''
                local tailStmt = compileStmtTag(2, subStmt)
                if tailStmt == nil then return end

                if subStmt.val[1].val == '_' then
                    rsl[#rsl + 1] = ' ' .. tailStmt .. ' '
                else
                    expr = compileExpr({
                        typ = TT_LIST,
                        val = {
                            {typ = TT_NAME, val = 'eq'},
                            matchee,
                            subStmt.val[1]
                        },
                        row = subStmt.row,
                        col = subStmt.col,
                    })
                    if not expr then return end
                    rsl[#rsl + 1] = ("if %s then %s "):format(expr, tailStmt)
                end
            else
                cerror("Expected (<expr> <tail>)", subStmt.row)
                return
            end

            idx = idx + 1
        end

        return table.concat(rsl, "else") .. "end"
    end,
    enum = function (idx, stmt)
        local list = stmt.val
        local len = #list
        local curEnumVal = 0
        local rsl = {}

        while idx <= len do
            local cur = list[idx]
            local part

            if cur.typ == TT_NAME then
                part = compileByTemp(stmtTemp.localdef, {
                    typ = TT_LIST,
                    val = {
                        0,
                        cur, {
                            typ = TT_NUMBER,
                            val = curEnumVal
                        }
                    },
                    row = cur.row,
                })
                curEnumVal = curEnumVal + 1
            elseif cur.typ == TT_LIST and #cur.val == 2 then
                local id, val = cur.val[1], cur.val[2]

                if val.typ ~= TT_NUMBER then
                    cerror("Expected <number>", val.row, val.col)
                    return
                end

                curEnumVal = val.val

                part = compileByTemp(stmtTemp.localdef, {
                    typ = TT_LIST,
                    val = {
                        0,
                        id, {
                            typ = TT_NUMBER,
                            val = curEnumVal
                        }
                    },
                })
                curEnumVal = curEnumVal + 1
            end

            rsl[#rsl + 1] = part
            idx = idx + 1
        end

        return table.concat(rsl, "; ")
    end,
    stmt = function (idx, stmt)
        return compileStmtTag(1, stmt.val[idx])
    end,
    tail = function (idx, stmt)
        return compileStmtTag(idx, stmt)
    end,
    name = function (idx, stmt)
        local tk = stmt.val[idx]

        if tk.typ ~= TT_NAME then
            cerror("Expected <name>", tk.row, tk.col)
            return
        end

        return tk.val
    end,
    val = function (idx, stmt)
        return compileToken(stmt.val[idx])
    end,
    arg = function (idx, stmt)
        local argList = stmt.val[idx]

        if argList.typ ~= TT_LIST then
            cerror("Expected <list>", argList.row, argList.col)
            return
        end
        argList = argList.val

        local len, rsl = #argList, {}

        for i = 1, len do
            local tk = argList[i]

            if tk.typ ~= TT_NAME then
                cerror("Expected <name>", tk.row, tk.col)
                return
            end

            rsl[#rsl + 1] = tk.val
        end

        return table.concat(rsl, ", ")
    end,
    list = function (idx, stmt)
        return compileTable(stmt.val[idx])
    end,
    tuple = function (idx, stmt)
        return compileTuple(stmt, idx)
    end,
    idx = function (idx, stmt)
        local rsl = {}
        local len = #stmt.val
        
        while idx <= len do
            local tk = stmt.val[idx]
            local part = compileToken(tk)

            if abort then
                return nil
            end

            if tk.typ == TT_NAME then
                if part:sub(1, 1) == '@' then
                    part = part:sub(2)
                else
                    part = "\"" .. part .. "\""
                end
            end
            rsl[#rsl + 1] = part

            idx = idx + 1
        end

        return "[" .. table.concat(rsl, "][") .. "]"
    end,
}

function compileByTemp(temp, stmt, init)
    local idx = init or 2

    return temp:gsub("{[^}]+}", function (tag)
        tag = tag:sub(2, -2)
        local tagFunc = tagTable[tag]

        if tagFunc then
            if stmt.val[idx] == nil then
                cerror("Missing argument(s)", stmt.row)
                return nil
            end

            local rsl = tagFunc(idx, stmt)
            idx = idx + 1

            return rsl
        end

        local exhausted = false
        local rsl = tag:gsub("<[^>]+>", function (subTag)
            if not stmt.val[idx] then
                exhausted = true
            else
                subTag = subTag:sub(2, -2)
                local subTagFunc = tagTable[subTag]

                assert(subTagFunc)
                    
                local rsl = subTagFunc(idx, stmt)
                idx = idx + 1
                return rsl
            end
        end)

        if exhausted then
            return ''
        end
        
        return rsl
    end)
end

function compileStmt(tk)
    local head = tk.val[1]

    if head == nil then return '' end

    local temp = stmtTemp[head.val]

    if isOper(head.val) or (head.typ ~= TT_NAME and head.typ ~= TT_INDEX and head.typ ~= TT_LIST) then
        cerror("Expected <stmt>", tk.row, tk.col)
        return nil
    end

    if temp then
        return compileByTemp(stmtTemp[tk.val[1].val], tk)
    end

    local fakeList = {typ = TT_LIST, val = {
        {typ = TT_NAME, val = "_", row = tk.row, col = tk.col},
        unpack(tk.val),
    }, row = tk.row, col = tk.col}

    return compileByTemp(TEMP_CALL, fakeList)
end

local function compileList(tk)
    if tk.typ == -2 then
        return nil
    elseif tk.typ ~= TT_LIST then
        cerror("Expected <list>", tk.row)
        return nil
    end

    local list = tk.val
    local head = list[1]

    if head == nil then return '' end

    if head.typ == TT_NAME or head.typ == TT_INDEX or head.typ == TT_LIST then
        if head.typ == TT_NAME and isOper(head.val) then
            return compileExpr(tk), "EXPR"
        end
        return compileStmt(tk), "STMT"
    else
        cerror("Can't call the value \"%s\"", head.row, head.col, head.val)
        return nil
    end
end

function compileToken(tk)
    local typ, val = tk.typ, tk.val

    assert(typ ~= TT_EOF and typ ~= -2)

    if typ == TT_STRING then
        return "\"" .. val .. "\""
    elseif typ == TT_NAME or typ == TT_NUMBER then
        return tostring(val)
    elseif typ == TT_LIST then
        return compileList(tk)
    elseif typ == TT_INDEX then
        return compileByTemp(TEMP_INDEX, tk, 1)
    elseif typ == TT_TABLE then
        return compileTable(tk)
    elseif typ == TT_TUPLE then
        return '{' .. compileTuple(tk) .. '}'
    end

    return ''
end

local function compileProgram()
    if not curtoken then
        curtoken = tkNext()
    end

    local rsl = {}

    while curtoken.typ ~= TT_EOF do
        if curtoken.typ == -2 then
            return nil
        end

        local line, typ = compileList(curtoken)
        if typ == "EXPR" then
            cerror("Expected statement", curtoken.row, nil)
            return nil
        end
        if line == nil then
            return nil
        end

        rsl[#rsl + 1] = line

        pnext()
    end

    return table.concat(rsl, "\n")
end

local function compileFile(fn)
    local file, err = io.open(fn, "r")
    
    if not file then
        print(err)
        return
    end

    local source = file:read"*a"
    file:close()

    local linePos = source:find("%$", 2)
    local luaPath = source:sub(2, (linePos or 2) - 1)
    local rstr = source:sub(linePos + 1)
    
    newState(rstr, fn)

    local rsl = compileProgram()

    if abort then
        return
    end

    print(rsl)

    file = io.open(luaPath, "w")
    file:write(rsl)
    file:close()

    dofile(luaPath)
end

compileFile("cisp.cisp")
