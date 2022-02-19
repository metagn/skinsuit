import variantsugar/[sum, equals]

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
