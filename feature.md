## 更方便的索引方式
`table.insert`较于`[table insert]`更便于书写。  
同样对于`(cls..m)`和`([cls.m] cls)`。  
对已知表的已知元素可以采取前者形式。
## 匹配语句
```
(if (eq X A) (
    ...
) ((if (eq X B) (
        ...
    ))
))
```
这种形式过于冗杂，且造成大量开销，于是将有下种形式  
```
(match X 
    (A
        ...
    )
    (B
        ...
    )
    (_
        ...
    )
)
```
_表示“其余”情况，类似于switch语句，不过不存在goto、break等控制。
## 枚举
在Lua中，实现枚举的方式也同样冗杂，于是有：  
```
(enum 
    (ENUM_A 0)
    ENUM_B
    (ENUM_C 10)
)
```
仅在当前作用域下有效，也就是说，枚举语句应在任何语句开始之前出现。
## 尾语句
更方便表示语句，在函数定义中，最后一条语句（或表达式）将作为返回值。
```
(func foo (x) (* 2 x) 5)
(func bar (x) {a x}))
```