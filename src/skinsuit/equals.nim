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

proc patchTypeSection(typeSec: NimNode, poststmts: var seq[NimNode]) =
  for td in typeSec:
    var objectNode = td[^1]
    while objectNode.kind in {nnkRefTy, nnkPtrTy}:
      objectNode = objectNode[0]
    if objectNode.kind == nnkObjectTy:
      let doExport = td[0].isNodeExported
      let typeName = td[0].realBasename
      # ==
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
      let equalsBody = newStmtList()
      for r in objectNode[^1]:
        generateEquals(equalsBody, r)
      equalsBody.add(newTree(nnkReturnStmt, ident"true"))
      poststmts.add(newProc(
        name = ident"==".exportIf(doExport),
        params = [ident"bool", newTree(nnkIdentDefs, ident"a", ident"b", ident(typeName), newEmptyNode())],
        body = equalsBody,
        pragmas = newTree(nnkPragma, ident"used")
      ))

macro equals*(body) =
  result = applyTypeMacro(body, patchTypeSection)
