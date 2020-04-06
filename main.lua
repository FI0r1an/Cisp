local parse = require"parser"
local compile = require"compiler"

local readFile = function (name)
    local file, content = io.open(name, "r")
    content = file:read"*a"
    file:close()
    return content
end

local replace = function (str, ...)
    local arg = {...}
    local r = str

    for i = 1, #arg do
        r = r:gsub("{" .. i .. "}", arg[i])
    end

    return r
end

_G.tree = function (t, tab)
    local _tab = ("\t"):rep(tab)
    local r
    
    for k, v in pairs(t) do
        local typ = type(v)
        if typ == "table" then
            print(_tab .. replace("Statement: {1}", v[1]))
            tree(v, tab + 1)
        else
            print(_tab .. replace("|{1} {2}", typ, tostring(v)))
        end
    end
end

state.source = readFile("test.cisp")

print(compile(parse()[1]))