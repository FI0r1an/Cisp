local tbl = {"A", "B", "C"}
print(table.concat(tbl))
local tbl = {["x"] = 10, ["foo"] = function (self, x) return self.x + x end}
print(tbl:foo(20))