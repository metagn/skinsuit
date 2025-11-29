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

import std/macros, private/utils

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

type FieldAliasKind* = enum TemplateAlias, Let, LetVarView

proc createInner(x: NimNode, kind: FieldAliasKind): seq[NimNode] =
  var t = getTypeImpl(x)
  while t.kind in {nnkPtrTy, nnkRefTy, nnkVarTy, nnkOutTy}:
    t = getTypeImpl(t[0])
  proc processIdentDefs(rl: NimNode, res: var seq[NimNode]) =
    for n in rl:
      proc generateAlias(res: var seq[NimNode], fieldName: string) =
        let name = ident(fieldName)
        let fieldExpr = newDotExpr(x, name)
        res.add:
          case kind
          of TemplateAlias:
            quote do:
              template `name`(): untyped {.used.} =
                `fieldExpr`
          of LetVarView:
            when experimentalViewsAvailable:
              quote do:
                let `name` {.used.}: var typeof(`fieldExpr`) = `fieldExpr`
            else:
              error("experimental views unavailable", x)
          of Let:
            quote do:
              let `name` {.used.} = `fieldExpr`
      case n.kind
      of nnkIdent, nnkAccQuoted, nnkSym, nnkOpenSymChoice, nnkClosedSymChoice:
        generateAlias(res, $n)
      of nnkIdentDefs:
        for f in n[0 .. ^3]:
          generateAlias(res, f.realBasename)
      of nnkRecCase, nnkRecList, nnkOfBranch, nnkElse:
        processIdentDefs(n, res)
      else: discard
  processIdentDefs(if t.kind == nnkObjectTy: t[2] else: t, result)

macro expandAs*(a: typed, kind: static FieldAliasKind): untyped =
  ## unwraps fields of an object to the current scope
  ##
  ## `kind` decides if to use untyped templates or to unwrap to `let` variables etc
  result = newStmtList()
  if a.kind == nnkTupleConstr:
    for b in a:
      result.add createInner(b, kind)
  else:
    result.add createInner(a, kind)

macro expand*(args: varargs[typed]): untyped =
  ## `expandAs` that allows multiple arguments, defaults to template alias
  result = newStmtList()
  for a in args:
    if a.kind == nnkTupleConstr:
      for b in a:
        result.add createInner(b, TemplateAlias)
    else:
      result.add createInner(a, TemplateAlias)

type FieldAccessorKind* = enum UntypedGetter, Getter, VarGetter, Setter

proc createInnerField(rootType: NimNode, fieldName: NimNode, accessors: set[FieldAccessorKind]): seq[NimNode] =
  var fieldName = fieldName
  let exported = fieldName.kind in nnkCallKinds and fieldName[0].eqIdent"*"
  if exported: fieldName = fieldName[1]
  if fieldName.kind notin {nnkIdent, nnkAccQuoted, nnkSym, nnkOpenSymChoice, nnkClosedSymChoice}:
    error "expected field name", fieldName
  let fname = $fieldName
  var rt = getTypeImpl(rootType)
  if rt.kind == nnkBracketExpr and rt[0].eqIdent"typedesc":
    rt = getTypeImpl(rt[1])
  while rt.kind in {nnkPtrTy, nnkRefTy, nnkVarTy, nnkOutTy}:
    rt = getTypeImpl(rt[0])

  proc findFieldType(rl: NimNode): NimNode =
    result = nil
    for n in rl:
      case n.kind
      of nnkIdent, nnkAccQuoted, nnkSym, nnkOpenSymChoice, nnkClosedSymChoice:
        if $n == fname:
          return getTypeImpl(n)
      of nnkIdentDefs:
        for f in n[0 .. ^3]:
          let name = f.realBasename
          if name == fname:
            return getTypeImpl(n[^2])
      of nnkRecCase, nnkRecList, nnkOfBranch, nnkElse:
        let found = findFieldType(n)
        if not found.isNil: return found
      else: discard

  var ft = findFieldType(if rt.kind == nnkObjectTy: rt[2] else: rt)
  if ft == nil:
    error "could not find field " & fname & " in type " & repr rootType, fieldName
  if ft.kind == nnkBracketExpr and ft[0].eqIdent"typedesc":
    ft = getTypeImpl(ft[1])
  while ft.kind in {nnkPtrTy, nnkRefTy, nnkVarTy, nnkOutTy}:
    ft = getTypeImpl(ft[0])

  proc processIdentDefs(rl: NimNode, res: var seq[NimNode]) =
    for n in rl:
      proc generateAccessor(res: var seq[NimNode], innerFieldName: string) =
        let outerField = ident(fname)
        let name = ident(innerFieldName)
        let nameExported = name.exportIf(exported)
        let rootName = ident"root"
        let fieldExpr = newDotExpr(newDotExpr(rootName, outerField), name)
        for akind in accessors:
          res.add:
            case akind
            of UntypedGetter:
              quote do:
                template `nameExported`(`rootName`: `rootType`): untyped {.used.} =
                  `fieldExpr`
            of Getter:
              quote do:
                proc `nameExported`(`rootName`: `rootType`): typeof(`fieldExpr`) {.used, inline.} =
                  `fieldExpr`
            of VarGetter:
              quote do:
                proc `nameExported`(`rootName`: var `rootType`): var typeof(`fieldExpr`) {.used, inline.} =
                  `fieldExpr`
            of Setter:
              quote do:
                proc `nameExported`(`rootName`: var `rootType`, value: typeof(`fieldExpr`)) {.used, inline.} =
                  `fieldExpr` = value
      case n.kind
      of nnkIdent, nnkAccQuoted, nnkSym, nnkOpenSymChoice, nnkClosedSymChoice:
        generateAccessor(res, $n)
      of nnkIdentDefs:
        for f in n[0 .. ^3]:
          generateAccessor(res, f.realBasename)
      of nnkRecCase, nnkRecList, nnkOfBranch, nnkElse:
        processIdentDefs(n, res)
      else: discard
  processIdentDefs(if ft.kind == nnkObjectTy: ft[2] else: ft, result)

macro expandField*(root: typedesc, field: untyped, accessors: static set[FieldAccessorKind] = {UntypedGetter}): untyped =
  ## generates getters for fields of a field of an object to the original object
  ##
  ## `templ` decides if to use untyped templates or to unwrap to `let` variables
  result = newStmtList()
  if field.kind == nnkTupleConstr:
    for y in field:
      result.add createInnerField(root, y, accessors)
  else:
    result.add createInnerField(root, field, accessors)
