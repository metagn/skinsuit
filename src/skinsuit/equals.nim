## generates == for objects including case objects

runnableExamples:
  type Foo {.equals.} = object
    name: string
    case kind: bool
    of false:
      a: int
    of true:
      b: float
  
  assert Foo(name: "abc", kind: false, a: 1) == Foo(name: "abc", kind: false, a: 1)
  assert Foo(name: "abc", kind: false, a: 1) != Foo(name: "abc", kind: true, b: 1)
  assert Foo(name: "abc", kind: false, a: 1) != Foo(name: "def", kind: false, a: 1)

import macros, private/utils

template same(a, b: ref | ptr): bool =
  system.`==`(a, b)

proc equalsProc(typeName, objectNode: NimNode, doExport, ptrLike: bool): NimNode =
  proc generateEquals(sl: NimNode, field: NimNode) =
    case field.kind
    of nnkIdentDefs:
      for f in field[0 .. ^3]:
        sl.add quote do:
          if a.`f` != b.`f`:
            return false
    of nnkRecCase:
      let kf = field[0][0]
      sl.add quote do:
        if a.`kf` != b.`kf`:
          return false
      let cs = newTree(nnkCaseStmt, newDotExpr(ident"a", kf))
      for b in field[1 .. ^1]:
        let branch = copy b
        branch[^1] = newStmtList()
        for r in b[^1]:
          generateEquals(branch[^1], r)
        cs.add(branch)
      sl.add(cs)
    of nnkRecWhen:
      let ws = newTree(nnkWhenStmt)
      for b in field:
        let branch = copy b
        branch[^1] = newStmtList()
        for r in b[^1]:
          generateEquals(branch[^1], r)
        ws.add(branch)
      sl.add(ws)
    else: discard
  var equalsBody = newStmtList()
  if ptrLike:
    let same = bindSym"same"
    equalsBody.add quote do:
      if `same`(a, b): # covers both nil case
        return true
      if a.isNil or b.isNil:
        return false
  for r in objectNode[^1]:
    generateEquals(equalsBody, r)
  equalsBody.add(newTree(nnkReturnStmt, ident"true"))
  let noSideEffectPragma =
    when (NimMajor, NimMinor) >= (1, 6):
      newTree(nnkCast, newEmptyNode(), ident"noSideEffect")
    else:
      ident"noSideEffect"
  equalsBody = newStmtList(
    newTree(nnkPragmaBlock,
      newTree(nnkPragma, noSideEffectPragma),
      equalsBody))
  newProc(
    name = ident"==".exportIf(doExport),
    params = [ident"bool", newTree(nnkIdentDefs, ident"a", ident"b", typeName, newEmptyNode())],
    body = equalsBody,
    pragmas = newTree(nnkPragma, ident"used", ident"noSideEffect")
  )

proc patchTypeSection(typeSec: NimNode, poststmts: var seq[NimNode]) =
  for td in typeSec:
    var objectNode = td[^1]
    var ptrLike = false
    while objectNode.kind in {nnkRefTy, nnkPtrTy}:
      objectNode = objectNode[0]
      ptrLike = true
    if objectNode.kind == nnkObjectTy:
      let doExport = td[0].isNodeExported
      let typeName = td[0].realBasename
      poststmts.add(equalsProc(ident(typeName), objectNode, doExport, ptrLike))

macro equalsExistingType(t, T: typed, exported: static bool) =
  var objectNode = t.getTypeImpl
  var ptrLike = false
  while true:
    case objectNode.kind
    of nnkRefTy, nnkPtrTy:
      objectNode = objectNode[0]
      ptrLike = true
    of nnkSym, nnkBracketExpr: discard
    else: break
    objectNode = objectNode.getTypeImpl
  if objectNode.kind == nnkObjectTy:
    result = equalsProc(T, objectNode, exported, ptrLike)

macro equals*(body) =
  if body.kind in {nnkTypeDef, nnkTypeSection, nnkStmtList}:
    result = applyTypeMacro(body, patchTypeSection)
  else:
    var body = body
    var exported = false
    if body.kind == nnkPrefix and body[0].eqIdent"*":
      body = body[1]
      exported = true
    result = newCall(bindSym"equalsExistingType", newCall(bindSym"default", body), body, newLit exported)
