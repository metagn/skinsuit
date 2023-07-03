## turns procs into case statements dispatched over single
## case branch fields of an object variant argument

runnableExamples:
  type Foo = object
    case a: bool
    of false:
      x: int
    else:
      y: float
  
  proc addStr(s: var seq[string], a: int) =
    s.add("int " & $a)
  proc addStr(s: var seq[string], a: float) =
    s.add("float " & $a)
  proc addStr(s: var seq[string], f: Foo) {.dispatchCase: f.}

  var s: seq[string]
  var f: Foo
  addStr(s, f)
  f = Foo(a: true, y: 1.2)
  addStr(s, f)
  f.y = 3.4
  addStr(s, f)
  f = Foo(a: false, x: 567)
  addStr(s, f)
  doAssert s == @["int 0", "float 1.2", "float 3.4", "int 567"]

import macros, private/utils

proc doDispatchCase(arg, prc: NimNode): NimNode =
  result = copy prc
  if result[0].kind == nnkPostfix:
    result[0][1] = ident repr result[0][1]
  else:
    result[0] = ident repr result[0]
  var argi = 0
  let params = prc[3]
  case arg.kind
  of nnkIntLit..nnkUInt64Lit:
    argi = arg.intVal.int
  of nnkCallKinds:
    if arg.len == 2 and arg[0].eqIdent"^" and arg[1].kind in {nnkIntLit..nnkUInt64Lit}:
      var len = 0
      for a in params[1..^1]:
        len += a.len - 2
      argi = len - arg[1].intVal.int
  of nnkStrLit..nnkTripleStrLit, nnkIdent, nnkSym, nnkOpenSymChoice, nnkClosedSymChoice:
    let id =
      if arg.kind in {nnkOpenSymChoice, nnkClosedSymChoice}:
        arg[0].strVal
      else:
        arg.strVal
    block finder:
      var c = 1
      for a in params[1..^1]:
        let typeIndex = a.len - 2
        for i in 0 ..< typeIndex:
          if a[i].eqIdent(id):
            argi = c
            break finder
          inc c
  else: discard
  if argi <= 0:
    error("invalid argument number " & $argi, arg)
  var arg, argTyp: NimNode = nil
  var callTemplate = @[ident prc[0].realBasename]
  block paramIter:
    var c = 1
    for a in params[1..^1]:
      let typeIndex = a.len - 2
      for i in 0 ..< typeIndex:
        callTemplate.add(a[i])
        if c == argi:
          arg = a[i]
          argTyp = a[typeIndex]
        inc c
  var argTypImpl = getTypeImpl(argTyp)
  while not argTypImpl.isNil and argTypImpl.kind != nnkObjectTy:
    case argTypImpl.kind
    of nnkRefTy, nnkPtrTy: argTypImpl = argTypImpl[0]
    else:
      let newImpl = getTypeImpl(argTypImpl)
      if newImpl == argTypImpl:
        error("not an object type for dispatchCase", argTyp)
      else:
        argTypImpl = newImpl
  if argTypImpl.isNil or argTypImpl.kind != nnkObjectTy:
    error("invalid type for dispatchCase " & repr(argTyp), argTyp)
  proc findCase(rec: NimNode): NimNode =
    template maybe(x) =
      let y = x
      if not y.isNil: return y
    case rec.kind
    of nnkRecCase: result = rec
    of nnkRecWhen: # still check branches
      for a in rec:
        case a.kind
        of nnkElifBranch:
          maybe findCase(a[1])
        of nnkElse: maybe findCase(a[0])
        else: error("unreachable, branch kind " & $a.kind, a)
    of nnkRecList:
      for a in rec:
        maybe findCase(a)
    else: result = nil
  let firstCase = findCase(argTypImpl[^1])
  if firstCase.isNil:
    error("no case branch found in " & repr(argTyp), argTyp)
  var caseStmt = newTree(nnkCaseStmt, newDotExpr(arg, ident realBasename firstCase[0][0]))
  for b in firstCase[1..^1]:
    let fields = b[^1]
    if fields.kind in {nnkNilLit, nnkDiscardStmt}:
      caseStmt.add(b)
    else:
      expectKind fields, nnkRecList
      if fields.len != 1 or fields[0].len != 3:
        error("case branch has multiple fields: " & repr(b), argTyp)
      var newB = copy b
      var call = newTree(nnkCall, callTemplate)
      call[argi] = newDotExpr(call[argi], ident realBasename fields[0][0])
      newB[^1] = call
      caseStmt.add(newB)
  case result[^1].kind
  of nnkEmpty: result[^1] = newStmtList()
  of nnkStmtList: discard
  else: result[^1] = newStmtList(result[^1])
  result[^1].add caseStmt

macro dispatchCaseImpl(arg: untyped, prc: typed) =
  result = doDispatchCase(arg, prc)

macro dispatchCase*(arg, prc) =
  case prc.kind
  of nnkStmtList:
    result = newStmtList()
    for p in prc:
      result.add newCall(bindSym"dispatchCaseImpl", arg, prc)
  else: # routine kinds
    result = newCall(bindSym"dispatchCaseImpl", arg, prc)

macro dispatchCase*(prc) =
  ## no specified argument to dispatch on, assumes the first argument
  result = newCall(bindSym"dispatchCase", newLit(1), prc)
