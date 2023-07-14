import skinsuit/equals

block:
  type Foo {.equals.} = object
    name: string
    case kind: bool
    of false:
      a: int
    of true:
      b: float
  
  doAssert Foo(name: "abc", kind: false, a: 1) == Foo(name: "abc", kind: false, a: 1)
  doAssert Foo(name: "abc", kind: false, a: 1) != Foo(name: "abc", kind: true, b: 1)
  doAssert Foo(name: "abc", kind: false, a: 1) != Foo(name: "def", kind: false, a: 1)
