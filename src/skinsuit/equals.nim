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

proc equalsProc(typeName, objectNode: NimNode, doExport, ptrLike, forwardDecl: bool): NimNode =
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
      var needsEmptyElse = false
      for b in field[1 .. ^1]:
        let branch = copy b
        for i in 0 ..< b.len - 1:
          if branch[i].kind == nnkRange or
              (branch[i].kind == nnkInfix and branch[i][0].eqIdent".."):
            # https://github.com/nim-lang/Nim/issues/22661
            # if the issue is fixed, this block needs to be disabled
            needsEmptyElse = true
        branch[^1] = newStmtList()
        for r in b[^1]:
          generateEquals(branch[^1], r)
        if branch[^1].len == 0:
          branch[^1].add(newTree(nnkDiscardStmt, newEmptyNode()))
        cs.add(branch)
      if needsEmptyElse:
        cs.add(newTree(nnkElse, newTree(nnkDiscardStmt, newEmptyNode())))
      sl.add(cs)
    of nnkRecWhen:
      let ws = newTree(nnkWhenStmt)
      for b in field:
        let branch = copy b
        branch[^1] = newStmtList()
        for r in b[^1]:
          generateEquals(branch[^1], r)
        if branch[^1].len == 0:
          branch[^1].add(newTree(nnkDiscardStmt, newEmptyNode()))
        ws.add(branch)
      sl.add(ws)
    else: discard
  var equalsBody: NimNode
  if forwardDecl:
    equalsBody = newEmptyNode()
  else:
    equalsBody = newStmtList()
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
      poststmts.add(equalsProc(ident(typeName), objectNode, doExport, ptrLike, false))

macro equalsExistingType(t, T: typed, exported: static bool, forwardDecl: static bool) =
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
    result = equalsProc(T, objectNode, exported, ptrLike, forwardDecl)

macro equals*(body) =
  ## generates `==` proc for object types, either as type pragma or statement,
  ## i.e. ``type Foo {.equals.} = ...` or `equals Foo`
  ## (or `equals *Foo` to export)
  ## 
  ## type pragma version will not work with recursive types,
  ## write `equals Foo`/`equals *Foo` after type section
  if body.kind in {nnkTypeDef, nnkTypeSection, nnkStmtList}:
    result = applyTypeMacro(body, patchTypeSection)
  else:
    var body = body
    var exported = false
    if body.kind == nnkPrefix and body[0].eqIdent"*":
      body = body[1]
      exported = true
    result = newCall(bindSym"equalsExistingType", newCall(bindSym"default", body), body, newLit exported, newLit false)

macro equalsForwardDecl*(body) =
  ## generates forward declaration of `equals`, useful for
  ## mutually recursive types
  ## 
  ## used like `equalsForwardDecl T` or `equalsForwardDecl *T` (exported)
  var body = body
  var exported = false
  if body.kind == nnkPrefix and body[0].eqIdent"*":
    body = body[1]
    exported = true
  result = newCall(bindSym"equalsExistingType", newCall(bindSym"default", body), body, newLit exported, newLit true)
