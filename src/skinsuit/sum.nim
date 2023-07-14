## macro for sum type sugar
## 
## Generates kind enum and objects for each case branch allowing
## multiple fields with the same name across branches. These objects can
## also be made ref objects with `kind: ref _`.
## 
## Also generates constructors for branches with only one field `_: sometype`.

runnableExamples:
  type Foo {.sum.} = object
    case kind: _
    of A:
      x, y: int
  
  let a = Foo(kind: A)
  assert a.kind is FooKind
  var b = Foo(kind: A)
  b.x = 1
  assert b.x == 1
  let c = Foo(kind: A, a: FooA(x: 1, y: 2))
  b.y = 2
  assert b.a == c.a

  type Value {.sum.} = object
    case kind: _
    of None: discard
    of Integer, Boolean:
      _: int
    of Unsigned:
      _: uint
    of Float:
      _: float
  
  assert $Value(kind: None) == "(kind: None, none: ())"
  assert $Value(kind: Integer, integer: 1) == $Integer(1)
  assert $Value(kind: Boolean, integer: 1) == $Boolean(1)
  assert $Value(kind: Unsigned, unsigned: 1) == $Unsigned(1)
  assert $Value(kind: Float, float: 1) == $Float(1)

import macros, private/utils, strutils, sets

proc patchTypeSection(typeSec: NimNode, poststmts: var seq[NimNode]) =
  var typedefIndex = 0
  while typedefIndex < typeSec.len:
    template addType(d: NimNode, index = typedefIndex) =
      typeSec.insert(index, d)
      inc typedefIndex
    let td = typeSec[typedefIndex]
    var objectNode = td[^1]
    while objectNode.kind in {nnkRefTy, nnkPtrTy}:
      objectNode = objectNode[0]
    if objectNode.kind == nnkObjectTy:
      proc doCase(node: NimNode, typeName: string, doExport: bool, poststmts: var seq[NimNode]): NimNode
      proc eachField(rl: NimNode, typeName: string, doExport: bool, poststmts: var seq[NimNode]): NimNode =
        case rl.kind
        of nnkEmpty, nnkNilLit, nnkDiscardStmt: result = rl
        of nnkIdentDefs: result = rl
        of nnkRecList:
          result = rl
          for i in 0 ..< rl.len:
            result[i] = eachField(rl[i], typeName, doExport, poststmts)
        of nnkRecWhen:
          result = rl
          for b in 1 ..< rl.len:
            result[b] = eachField(rl[b], typeName, doExport, poststmts)
        of nnkRecCase:
          result = doCase(rl, typeName, doExport, poststmts)
        else: error "unknown node kind " & $rl.kind, rl
      
      proc doCase(node: NimNode, typeName: string, doExport: bool, poststmts: var seq[NimNode]): NimNode =
        var isRef = node[0][1].kind == nnkRefTy
        if isRef: node[0][1] = node[0][1][0]
        if node[0][1].eqIdent"_":
          let kindName = node[0][0].realBasename
          let enumTypeName = typeName & kindName.capitalizeAscii
          result = newNimNode(nnkRecCase, node)
          node[0][1] = ident(enumTypeName)
          result.add(node[0])
          let originalIndex = typedefIndex
          let enumBody = newTree(nnkEnumTy, newEmptyNode())
          for i in 1 ..< node.len:
            let branch = node[i]
            if branch.kind != nnkOfBranch:
              error "sum type only accepts of branches", branch
            let newBranch = newNimNode(nnkOfBranch, branch)
            for j in 0 ..< branch.len - 1:
              enumBody.add(branch[j])
              newBranch.add(branch[j])
            if branch[^1].len == 1 and branch[^1][0][0].eqIdent"_":
              let fieldname = ident(toLowerAscii $branch[0])
              let ty = branch[^1][0][1]
              newBranch.add(newTree(nnkRecList, newIdentDefs(fieldname.exportIf(doExport), ty)))
              for b in branch[0 .. ^2]:
                let name = ident($b).exportIf(doExport)
                let tn = ident(typeName)
                let kn = ident(kindName)
                poststmts.add(quote do:
                  proc `name`(field: `ty`): `tn` {.used.} = `tn`(`kn`: `b`, `fieldname`: field))
            else:
              let newTypeName = typeName & $branch[0]
              let objNode = newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), eachField(branch[^1], typeName, doExport, poststmts))
              let objType = newTree(nnkTypeDef, ident(newTypeName).exportIf(doExport), newEmptyNode(),
                if isRef: newTree(nnkRefTy, objNode) else: objNode)
              addType(objType)
              newBranch.add(newTree(nnkRecList, newIdentDefs(($branch[0]).toLowerAscii.ident.exportIf(doExport), ident(newTypeName))))
            result.add(newBranch)
          addType(newTree(nnkTypeDef, ident(enumTypeName).exportIf(doExport), newEmptyNode(), enumBody), originalIndex)
          
          proc hasField(reclist: NimNode, field: string): bool =
            for r in reclist:
              if r.kind == nnkIdentDefs:
                for i in 0 .. r.len - 3:
                  if r[i].realBasename.eqIdent(field): return true
            false
          var doneFields: HashSet[string]
          for bi in 1 ..< node.len:
            type Branch = tuple[conds: seq[NimNode], fieldname: NimNode]
            let bran = (conds: node[bi][0 .. ^2], fieldname: ident(toLowerAscii($node[bi][0])))
            for r in node[bi][^1]:
              let branchName = bran.fieldname
              if r.kind == nnkIdentDefs:
                for i in 0 .. r.len - 3:
                  let fieldName = r[i].realBasename
                  if fieldName != "_" and fieldName notin doneFields:
                    var otherBranches: seq[Branch]
                    for bj in bi + 1 ..< node.len:
                      if node[bj].hasField(fieldName):
                        otherBranches.add((conds: node[bj][0 .. ^2], fieldname: ident(toLowerAscii($node[bj][0]))))
                    template getField(b: Branch): NimNode =
                      newDotExpr(newDotExpr(ident"self", b.fieldname), ident(fieldName))
                    let setterValue = genSym(nskParam, "value")
                    var getter = newTree(nnkCaseStmt, newDotExpr(ident"self", branchName))
                    var setter = newTree(nnkCaseStmt, newDotExpr(ident"self", branchName))
                    var names: seq[string]
                    for b in bran.conds:
                      names.add(b.repr)
                    getter.add(newTree(nnkOfBranch).add(bran.conds).add(bran.getField))
                    setter.add(newTree(nnkOfBranch).add(bran.conds).add(bran.getField.newAssignment(setterValue)))
                    for ob in otherBranches:
                      getter.add(newTree(nnkOfBranch).add(ob.conds).add(ob.getField))
                      setter.add(newTree(nnkOfBranch).add(ob.conds).add(ob.getField.newAssignment(setterValue)))
                      for b in ob.conds:
                        names.add(b.repr)
                    if otherBranches.len == 0: # unsafe
                      getter = getter[1][1]
                      setter = setter[1][1]
                    else:
                      let raiser = newTree(nnkElse,
                        newTree(nnkRaiseStmt, newCall("newException", ident"FieldDefect",
                          newLit("object is not of branch " & names.join(" or ") & " and therefore does not have field `" & fieldName & "`"))))
                      getter.add(raiser)
                      setter.add(raiser)
                    let gettername = if (r[i].kind == nnkPragmaExpr and r[i][0].kind == nnkPostfix) or r[i].kind == nnkPostfix:
                        postfix(ident(fieldName), "*") else: ident(fieldName)
                    poststmts.add(newProc(
                      name = gettername,
                      params = [r[^2], newIdentDefs(ident"self", ident(typeName))],
                      body = getter,
                      procType = nnkProcDef,
                      pragmas = newTree(nnkPragma, ident"used")
                    ))
                    let settername = if (r[i].kind == nnkPragmaExpr and r[i][0].kind == nnkPostfix) or r[i].kind == nnkPostfix:
                        postfix(newTree(nnkAccQuoted, ident(fieldName), ident"="), "*") else: newTree(nnkAccQuoted, ident(fieldName), ident"=")
                    poststmts.add(newProc(
                      name = settername,
                      params = [newEmptyNode(), newIdentDefs(ident"self", newTree(nnkVarTy, ident(typeName))), newIdentDefs(setterValue, r[^2])],
                      body = setter,
                      procType = nnkProcDef,
                      pragmas = newTree(nnkPragma, ident"used")
                    ))
                    when false:
                      poststmts.add(newProc(
                        name = gettername,
                        params = [newTree(nnkVarTy, r[^2]), newIdentDefs(ident"self", newTree(nnkVarTy, ident(typeName)))],
                        body = ifstmt,
                        pragmas = used
                      ))
                    doneFields.incl(fieldName)
        else:
          result = node
      
      let doExport = td[0].isNodeExported
      let typeName = td[0].realBasename
      let output {.used.} = eachField(objectNode[^1], typeName, doExport, poststmts)
    inc typedefIndex

macro sum*(body) =
  result = applyTypeMacro(body, patchTypeSection)
