state = {
    ptr = 1,
    lptr = 1,
    line = 1
}

local literal = {
    ["true"] = true,
    ["false"] = false,
    ["null"] = nil,
}

local current = function ()
    local ptr = state.ptr
    return state.source:sub(ptr, ptr)
end

local lookahead = function ()
    local ptr = state.ptr + 1
    return state.source:sub(ptr, ptr)
end

local lnext = function ()
    local ptr = state.ptr
    state.ptr = ptr + 1
    state.lptr = state.lptr + 1
end

local exist = function (str, chr)
    return (str:find(chr, 1, true)) ~= nil
end

local replace = function (str, ...)
    local arg = {...}
    local r = str

    for i = 1, #arg do
        r = r:gsub("{" .. i .. "}", arg[i])
    end

    return r
end

local lassert = function (bool, info)
    local err = replace((info or "Error at line {1}, position {2}, character \"{3}\""), state.line, state.lptr, current())
    assert(bool, err)
end

local sLine = function ()
    lassert(exist("\r\n", current()))
    local old = current()
    lnext()
    state.lptr = 1
    state.line = state.line + 1
    if exist("\r\n", current()) and current() ~= old then
        lnext()
        state.lptr = 1
        state.line = state.line + 1
    end
end

local sWhitespace = function ()
    local ws = "\t\r\n "
    
    while exist(ws, current()) and state.ptr <= #state.source do
        if exist("\r\n", current()) then
            sLine()
        else
            lnext()
        end
    end
end

local sComment = function ()
    lassert(current() == ";" and lookahead() == ";")
    lnext(); lnext()

    while exist("\r\n", current()) == false do
        lnext()
    end
end

local rString = function ()
    lnext()
    local str = ""

    while exist("\"'", current()) == false do
        str = str .. current()
        lnext()
    end

    lnext()

    return "\"" .. str .. "\""
end

local isD = function (num)
    return "0" <= num and num <= "9"
end

local rDigit = function ()
    local str = ""

    if exist("+-", current()) then
        str = str .. current()
        lnext()
    end

    while isD(current()) or current() == "." do
        str = str .. current()
        lnext()
    end

    local num = tonumber(str)
    lassert(num ~= nil)
    return num
end

local rName = function ()
    local name = ""

    while exist(" \r\n\t(){}", current()) == false do
        name = name .. current()
        lnext()
    end
    
    return literal[name] or name
end

local parse

local rList = function ()
    lassert(current() == "(")
    local list = {}
    lnext()

    while current() ~= ")" do
        sWhitespace()
        lassert((#list == 0 and current() == ")") == false, "Empty list at line {1}, position {2}")
        lassert((state.ptr >= #state.source) == false, "Unfinished list at line {1}, position {2}")
        if current() == ")" then
            break
        end
        local v = parse()
        lassert(exist(" \r\n\t)", current()))
        sWhitespace()
        list[#list + 1] = v
    end

    lnext()
    return list
end

local rTable = function ()
    lassert(current() == "{")
    local list = {}
    lnext()

    while current() ~= "}" do
        sWhitespace()
        lassert((next(list) == nil and current() == "}") == false, "Empty table at line {1}, position {2}")
        lassert((state.ptr >= #state.source) == false, "Unfinished table at line {1}, position {2}")
        if current() == "}" then
            break
        end
        local k = parse()
        sWhitespace()
        lassert(current() == ":")
        lnext()
        sWhitespace()
        local v = parse()
        list[k] = v
    end

    lnext()
    list.__cispt = true
    return list
end

parse = function ()
    local ch = current()

    if isD(ch) or ((exist("+-", ch) or ch == ".") and isD(lookahead())) then
        return rDigit()
    elseif exist("'\"", ch) then
        return rString()
    elseif ch == "(" then
        return rList()
    elseif ch == "{" then
        return rTable()
    end

    return rName()
end

local parseBlock = function ()
    local ast = {}
    
    while state.ptr <= #state.source do
        local ch = current()
        if exist(" \t\r\n", ch) then
            sWhitespace()
        elseif ch == ";" and lookahead() == ";" then
            sComment()
        else
            local array = parse()
            lassert(type(array) == "table")
            ast[#ast + 1] = array
            sWhitespace()
        end
    end

    return ast
end

return parseBlock