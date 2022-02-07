import unions/flatbranch

block:
  type FooKind = enum fkA, fkB, fkC
  flattenBranches:
    type
      Foo = ref object
        num: int
        case kind: FooKind
        of fkA:
          name: string
        of fkB:
          a, b: int
        else:
          a: int
  var f = Foo(num: 1, kind: fkA)
  f.name = "abc"
  doAssert f.kind == fkA
  doAssert f.name == "abc"
  f = Foo(num: 16, kind: fkB)
  doAssert f.kind == fkB
  doAssert f.a == 0
  doAssert f.b == 0
  f.a = 5
  doAssert f.a == 5
  f.b = 7
  doAssert f.b == 7
  f = Foo(num: 2, kind: fkC)
  doAssert f.kind == fkC
  doAssert f.a == 0
