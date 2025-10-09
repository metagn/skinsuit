import skinsuit/expand

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
