## `expand` macro, adds alias templates for every field of an object,
## like the macro from [the library `with`](https://github.com/zevv/with) but doesn't use a block,
## can replicate by just wrapping its use in `block`

runnableExamples:
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

import std/macros

proc realBasename(n: NimNode): string =
  case n.kind
  of nnkPragmaExpr: n[0].realBasename 
  of nnkPostfix: n[1].realBasename
  else: $n

const experimentalViewsAvailable = compiles do:
  var x: int
  let y: var int = y

const skinsuitExpandUseViews* {.booldefine.} = experimentalViewsAvailable
  ## whether or not to use experimental views when using variables and not templates

proc createInner(x: NimNode, templ = true): seq[NimNode] =
  var t = getTypeImpl(x)
  if t.kind == nnkRefTy:
    t = getTypeImpl(t[0])
  proc processIdentDefs(rl: NimNode, res: var seq[NimNode]) =
    for n in rl:
      case n.kind
      of nnkIdentDefs:
        for f in n[0 .. ^3]:
          let name = ident(f.realBasename)
          res.add:
            if templ:
              quote do:
                template `name`(): untyped {.used.} =
                  `x`.`name`
            elif experimentalViewsAvailable:
              quote do:
                let `name` {.used.}: var typeof(`x`.`name`) = `x`.`name`
            else:
              quote do:
                let `name` {.used.} = `x`.`name`
      of nnkRecCase, nnkRecList, nnkOfBranch, nnkElse:
        processIdentDefs(n, res)
      else: discard
  processIdentDefs(if t.kind == nnkObjectTy: t[2] else: t, result)

macro expand*(x: typed, templ: static bool = true): untyped =
  ## unwraps fields of an object to the current scope
  ##
  ## `templ` decides if to use untyped templates or to unwrap to `let` variables
  result = newStmtList()
  if x.kind == nnkTupleConstr:
    for y in x:
      result.add createInner(y, templ)
  else:
    result.add createInner(x, templ)
