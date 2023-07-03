import variantsugar/dispatch

block: # on parameter name
  type Foo = object
    case a: bool
    of false:
      x: int
    else:
      y: float
  
  proc addStr(s: var seq[string], a: int) =
    s.add("int " & $a)
  proc addStr(s: var seq[string], a: float) =
    s.add("float " & $a)
  proc addStr(s: var seq[string], f: Foo) {.dispatchCase: f.}

  var s: seq[string]
  var f: Foo
  addStr(s, f)
  f = Foo(a: true, y: 1.2)
  addStr(s, f)
  f.y = 3.4
  addStr(s, f)
  f = Foo(a: false, x: 567)
  addStr(s, f)
  doAssert s == @["int 0", "float 1.2", "float 3.4", "int 567"]

block: # on parameter number
  type Foo = object
    case a: bool
    of false:
      x: int
    else:
      y: float
  
  proc addStr(s: var seq[string], a: int) =
    s.add("int " & $a)
  proc addStr(s: var seq[string], a: float) =
    s.add("float " & $a)
  proc addStr(s: var seq[string], f: Foo) {.dispatchCase: 2.}

  var s: seq[string]
  var f: Foo
  addStr(s, f)
  f = Foo(a: true, y: 1.2)
  addStr(s, f)
  f.y = 3.4
  addStr(s, f)
  f = Foo(a: false, x: 567)
  addStr(s, f)
  doAssert s == @["int 0", "float 1.2", "float 3.4", "int 567"]

block: # first parameter
  type Foo = object
    case a: bool
    of false:
      x: int
    else:
      y: float
  
  proc addStr(a: int, s: var seq[string]) =
    s.add("int " & $a)
  proc addStr(a: float, s: var seq[string]) =
    s.add("float " & $a)
  proc addStr(f: Foo, s: var seq[string]) {.dispatchCase.}

  var s: seq[string]
  var f: Foo
  addStr(f, s)
  f = Foo(a: true, y: 1.2)
  addStr(f, s)
  f.y = 3.4
  addStr(f, s)
  f = Foo(a: false, x: 567)
  addStr(f, s)
  doAssert s == @["int 0", "float 1.2", "float 3.4", "int 567"]

import variantsugar/sum

block: # combined
  type Value {.sum.} = object
    case kind: _
    of Integer, Boolean:
      _: int
    of Unsigned:
      _: uint
    of Float:
      _: float
  
  proc addStr(s: var seq[string], a: int) =
    s.add("int " & $a)
  proc addStr(s: var seq[string], a: uint) =
    s.add("uint " & $a)
  proc addStr(s: var seq[string], a: float) =
    s.add("float " & $a)
  proc addStr(s: var seq[string], v: Value) {.dispatchCase: v.}

  var s: seq[string]
  var v: Value
  addStr(s, v)
  v = Float(1.2)
  addStr(s, v)
  v.float = 3.4
  addStr(s, v)
  v = Unsigned(567)
  addStr(s, v)
  v = Boolean(1)
  addStr(s, v)
  v = Integer(89)
  addStr(s, v)
  doAssert s == @["int 0", "float 1.2", "float 3.4", "uint 567", "int 1", "int 89"]
