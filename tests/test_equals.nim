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

block:
  type
    Bar = ref object
      case a: bool
      of false:
        x: Foo
      else:
        discard
    Foo = object
      name: string
      bar: Bar
      case kind: bool
      of false:
        a: int
      of true:
        b: float

  equalsForwardDecl Foo
  
  equals Bar
  equals Foo
  
  doAssert Foo(name: "abc", kind: false, a: 1) == Foo(name: "abc", kind: false, a: 1)
  doAssert Foo(name: "abc", kind: false, a: 1) != Foo(name: "abc", kind: true, b: 1)
  doAssert Foo(name: "abc", kind: false, a: 1) != Foo(name: "def", kind: false, a: 1)
  doAssert Bar(a: false, x: Foo(name: "abc")) == Bar(a: false, x: Foo(name: "abc"))
  doAssert Bar(a: false, x: Foo(name: "abc")) != Bar(a: false, x: Foo(name: "def"))
