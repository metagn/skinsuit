when not defined(js) and not defined(nimscript):
  import skinsuit/conditional

  conditional:
    type Foo = ref object
      num: int
      case branch: _ # type has to be _, name can also be _
      of Odd, num mod 2 == 1: # branch names can also be _
        name: string
      of DoubleEven, num mod 4 == 0:
        a*, b: int
      of Even:
        a: int

  block:
    var f = Foo(num: 1)
    f.name = "abc"
    doAssert f.name == "abc"
    doAssert f.branch == Odd
    f.num = 16
    f.resetBranch()
    doAssert f.a == 0
    doAssert f.b == 0
    f.a = 5
    doAssert f.a == 5
    f.b = 7
    doAssert f.b == 7
    doAssert f.branch == DoubleEven
    f.num = 2
    doAssert f.branch == Even
    doAssert f.a == 5
    f.resetBranch()
    doAssert f.a == 0

  block:
    type Foo {.conditional.} = ref object
      num: int
      case branch: _ # type has to be _, name can also be _
      of Odd, num mod 2 == 1: # branch names can also be _
        name: string
      of DoubleEven, num mod 4 == 0:
        a, b: int
      of Even:
        a: int
    var f = Foo(num: 1)
    f.name = "abc"
    doAssert f.name == "abc"
    doAssert f.branch == Odd
    f.num = 16
    f.resetBranch()
    doAssert f.a == 0
    doAssert f.b == 0
    f.a = 5
    doAssert f.a == 5
    f.b = 7
    doAssert f.b == 7
    doAssert f.branch == DoubleEven
    f.num = 2
    doAssert f.branch == Even
    doAssert f.a == 5
    f.resetBranch()
    doAssert f.a == 0

