import skinsuit/expand

block:
  type Foo = ref object
    first: int
    second: string
    third: float

  proc useFoo(foo: Foo) =
    expand(foo)
    doAssert first == foo.first
    doAssert second == foo.second
    doAssert third == foo.third
    if true:
      third = float(first)
      second = "abc"
    doAssert float(first) == third
    doAssert second == "abc"

  var foo = Foo(first: 1, second: "two", third: 3.0)
  useFoo(foo)

block:
  type
    Bar = ref object
      first: int
      second: string
      third: float
    Foo = ref object
      bar: Bar

  expandField Foo, bar

  var foo = Foo(bar: Bar(first: 1, second: "two", third: 3.0))
  doAssert foo.first == foo.bar.first
  doAssert foo.second == foo.bar.second
  doAssert foo.third == foo.bar.third
  if true:
    foo.third = float(foo.first)
    foo.second = "abc"
  doAssert float(foo.first) == foo.third
  doAssert foo.second == "abc"
