
local replace = function (str, ...)
    local arg = {...}
    local r = str

    for i = 1, #arg do
        r = r:gsub("{" .. i .. "}", arg[i])
    end

    return r
end

local exist = function (str, chr)
    return (str:find(chr, 1, true)) ~= nil
end

local compile

local op = {
    ["^"] = 100,
    ["not"] = 99,
    ["*"] = 98, ["/"] = 98,
    ["+"] = 97, ["-"] = 97,
    [".."] = 96,
    ["<"] = 95, [">"] = 95, ["<="] = 95, [">="] = 95, ["=="] = 95, ["~="] = 95,
    ["and"] = 94,
    ["or"] = 93
}
local operPrio = function (oper)
    return op[oper] or 0
end

local exprstmt = function (ast)
    local l, r = ast[2], ast[3]
    local lt, rt = type(l), type(r)
    local pp = operPrio(ast[1])
    local lv, rv
    
    if lt == "table" then
        local p = operPrio(l[1])
        if pp >= p then
            lv = "( " .. compile(l) .. " )" 
        else
            lv = compile(l)
        end
    else
        lv = l 
    end
    
    if rt == "table" then
        local p = operPrio(r[1])
        if pp >= p then
            rv = "( " .. compile(r) .. " )" 
        else
            rv = compile(r)
        end
    else
        rv = r 
    end
    
    return replace("{1} {2} {3}", lv, ast[1], rv)
end

function compile(ast)
    local typ = type(ast)

    if typ ~= "table" then
        return ast
    end

    local oper = ast[1]

    if exist("+-*/=~<>", oper) then
        return exprstmt(ast)
    end
end

return compile