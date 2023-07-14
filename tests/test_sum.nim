import skinsuit/sum

block:
  sum:
    type Foo = object
      case kind: _
      of A:
        x, y: int

block:
  type Foo {.sum.} = object
    case kind: _
    of A:
      x, y: int
  
  let a = Foo(kind: A)
  doAssert a.kind is FooKind
  var b = Foo(kind: A)
  b.x = 1
  doAssert b.x == 1
  let c = Foo(kind: A, a: FooA(x: 1, y: 2))
  b.y = 2
  doAssert b.a == c.a

block:
  type Value {.sum.} = object
    case kind: _
    of None: discard
    of Integer, Boolean:
      _: int
    of Unsigned:
      _: uint
    of Float:
      _: float
  doAssert $Value(kind: None) == "(kind: None, none: ())"
  doAssert $Value(kind: Integer, integer: 1) == "(kind: Integer, integer: 1)"
  doAssert $Integer(1) == "(kind: Integer, integer: 1)"
  doAssert $Value(kind: Boolean, integer: 1) == "(kind: Boolean, integer: 1)"
  doAssert $Boolean(1) == "(kind: Boolean, integer: 1)"
  doAssert $Value(kind: Unsigned, unsigned: 1) == "(kind: Unsigned, unsigned: 1)"
  doAssert $Unsigned(1) == "(kind: Unsigned, unsigned: 1)"
  doAssert $Value(kind: Float, float: 1) == "(kind: Float, float: 1.0)"
  doAssert $Float(1) == "(kind: Float, float: 1.0)"
  doAssert $Value(kind: None) == "(kind: None, none: ())"
