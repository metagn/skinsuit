import variantsugar/unionfield

block:
  type Foo {.unionField.} = ref object
    value {.union.}: (int, bool, string)
  
  var f1 = Foo().setUnionField(value, 3)
  f1.withUnionField(value):
    doAssert value is int
    when value is int:
      doAssert value == 3
      value = 4
  f1.withUnionField(value):
    doAssert value is int
    when value is int:
      doAssert value == 4
  
  var s: seq[string]

  proc foo(f: Foo) =
    f.withUnionField(value):
      s.add($typeof(value))
  
  var s2 = @[Foo().setUnionField(value, true), Foo().setUnionField(value, 3), Foo().setUnionField(value, "abc")]
  for a in s2: foo(a)
  doAssert s == @["bool", "int", "string"]

block:
  type Foo {.unionField.} = ref object
    a, b: int
    value {.union.}: (int, bool, string)
    c, d: int
  
  var s: seq[string]

  proc foo(f: Foo) =
    f.withUnionField(value):
      when value is bool:
        doAssert value == true
        doAssert (f.a, f.b, f.c, f.d) == (1, 0, 0, 0)
      elif value is int:
        doAssert value == 3
        doAssert (f.a, f.b, f.c, f.d) == (2, 0, 2, 0)
      elif value is string:
        doAssert value == "abc"
        doAssert (f.a, f.b, f.c, f.d) == (0, 0, 0, 0)
      s.add($typeof(value))
  
  var s2 = @[Foo(a: 1).setUnionField(value, true), Foo(c: 2, a: 2).setUnionField(value, 3), Foo().setUnionField(value, "abc")]
  for a in s2: foo(a)
  doAssert s == @["bool", "int", "string"]
