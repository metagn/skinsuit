import variantsugar/[sum, equals, dispatch]

block:
  type Value {.sum, equals.} = object
    case kind: _
    of None: discard
    of Integer, Boolean:
      _: int
    of Unsigned:
      _: uint
    of Float:
      _: float
  doAssert Value(kind: Integer, integer: 1) == Integer(1)
  doAssert Value(kind: Boolean, integer: 1) == Boolean(1)
  doAssert Value(kind: Unsigned, unsigned: 1) == Unsigned(1)
  doAssert Value(kind: Float, float: 1) == Float(1)

  proc double[T](x: var T) =
    x *= 2
  proc double(x: ValueNone) = discard
  proc double(v: var Value) {.dispatchCase: v.}
  var v = Integer(1)
  double(v)
  doAssert v == Integer(2)
  v = Float(1.0)
  double(v)
  doAssert v == Float(2.0)
