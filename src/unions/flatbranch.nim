## flatten object variant case branches into their own objects, allows shared field names
## 

runnableExamples:
  type FooKind = enum fkA, fkB, fkC
  flattenBranches:
    type
      Foo = ref object
        num: int
        case kind: FooKind
        of fkA:
          name: string
        of fkB:
          a, b: int
        else:
          a: int
  var f = Foo(num: 1, kind: fkA)
  f.name = "abc"
  doAssert f.kind == fkA
  doAssert f.name == "abc"
  f = Foo(num: 16, kind: fkB)
  doAssert f.kind == fkB
  doAssert f.a == 0
  doAssert f.b == 0
  f.a = 5
  doAssert f.a == 5
  f.b = 7
  doAssert f.b == 7
  f = Foo(num: 2, kind: fkC)
  doAssert f.kind == fkC
  doAssert f.a == 0

import macros, strutils, sets, private/utils

proc patchTypeSection(typesec: NimNode, poststmts: var seq[NimNode]) =
  expectKind typesec, nnkTypeSection
  var typedefIndex = 0
  template insertType(n: NimNode) =
    typesec.insert(typedefIndex, n)
    inc typedefIndex
  while typedefIndex < typesec.len:
    var objectNode = typesec[typedefIndex][2]
    while objectNode.kind in {nnkRefTy, nnkPtrTy}: objectNode = objectNode[0]
    if objectNode.kind == nnkObjectTy:
      let typeName = typesec[typedefIndex][0].realBasename
      var fieldNames: seq[string] # use for template
      for rec in objectNode[2]:
        if rec.kind == nnkIdentDefs:
          for i in 0 .. rec.len - 3: fieldNames.add(rec[i].realBasename)
      for recI, rec in objectNode[2]:
        if rec.kind == nnkRecCase:
          type Branch = ref object
            conds: seq[NimNode]
            fields: NimNode
            name: string
          var
            branches: seq[Branch]
            defaultBranch: Branch
            allBranches: seq[Branch]
            branchName = rec[0][0].realBasename
          template objtype(b: Branch): NimNode =
            ident(typeName & branchName & b.name & "Obj")
          template fieldname(b: Branch): NimNode =
            ident(branchName & b.name & "Obj")
          let used = newTree(nnkPragma, ident"used")
          for i in 1 ..< rec.len:
            let b = rec[i]
            let recList = b[^1]
            case b.kind
            of nnkOfBranch:
              var name: string
              for c in b[0..^2]:
                name.add(c.repr.capitalizeAscii)
              let branch = Branch(conds: b[0..^2],
                fields: copy recList,
                name: name)
              let objt = branch.objtype
              b[^1] = newTree(nnkRecList, newTree(nnkIdentDefs, branch.fieldname, objt, newEmptyNode()))
              insertType(newTree(nnkTypeDef, objt, newEmptyNode(),
                newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), branch.fields)))
              branches.add(branch)
              allBranches.add(branch)
            of nnkElse:
              let branch = Branch(conds: @[],
                fields: copy recList,
                name: "Else")
              let objt = branch.objtype
              b[^1] = newTree(nnkRecList, newTree(nnkIdentDefs, branch.fieldname, objt, newEmptyNode()))
              insertType(newTree(nnkTypeDef, objt, newEmptyNode(),
                newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), branch.fields)))
              defaultBranch = branch
              allBranches.add(branch)
            else: error("unexpected reccase branch kind " & $b.kind, b)
          #let baseTypeName = typeName & capitalizedBranch
          #let unionRecList = newNimNode(nnkRecList)
          #let unionTypeName = ident(baseTypeName & "Obj")
          #insertType(newTree(nnkTypeDef,
          #  newTree(nnkPragmaExpr, unionTypeName, newTree(nnkPragma, ident"union")),
          #  newEmptyNode(),
          #  newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), unionRecList)))
          #let unionFieldName = ident(uncapitalizeAscii(realBranchName) & "Obj")
          #objectNode[2][recI] = newTree(nnkIdentDefs, unionFieldName, unionTypeName, newEmptyNode())
          #template nameOrEnumConvIndex(b: Branch): NimNode =
          #  if b.name.len == 0: newCall(enumName, newLit(b.index)) else: ident(b.name)
          proc hasField(reclist: NimNode, field: string): bool =
            for r in reclist:
              if r.kind == nnkIdentDefs:
                for i in 0 .. r.len - 3:
                  if r[i].realBasename.eqIdent(field): return true
            false
          var doneFields: HashSet[string]
          for bi in 0 ..< branches.len:
            let bran = branches[bi]
            for r in bran.fields:
              if r.kind == nnkIdentDefs:
                for i in 0 .. r.len - 3:
                  let fieldName = r[i].realBasename
                  if fieldName notin doneFields:
                    var otherBranches: seq[Branch]
                    for bj in bi + 1 ..< branches.len:
                      if branches[bj].fields.hasField(fieldName):
                        otherBranches.add(branches[bj])
                    template getField(b: Branch): NimNode =
                      newDotExpr(newDotExpr(ident"self", b.fieldname), ident(fieldName))
                    let setterValue = genSym(nskParam, "value")
                    var getter = newTree(nnkCaseStmt, newDotExpr(ident"self", ident(branchName)))
                    var setter = newTree(nnkCaseStmt, newDotExpr(ident"self", ident(branchName)))
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
                    if not defaultBranch.isNil and defaultBranch.fields.hasField(fieldName):
                      getter.add(newTree(nnkElse, defaultBranch.getField))
                      setter.add(newTree(nnkElse, defaultBranch.getField.newAssignment(setterValue)))
                    elif otherBranches.len == 0: # unsafe
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
                      pragmas = used
                    ))
                    let settername = if (r[i].kind == nnkPragmaExpr and r[i][0].kind == nnkPostfix) or r[i].kind == nnkPostfix:
                        postfix(newTree(nnkAccQuoted, ident(fieldName), ident"="), "*") else: newTree(nnkAccQuoted, ident(fieldName), ident"=")
                    poststmts.add(newProc(
                      name = settername,
                      params = [newEmptyNode(), newIdentDefs(ident"self", newTree(nnkVarTy, ident(typeName))), newIdentDefs(setterValue, r[^2])],
                      body = setter,
                      procType = nnkProcDef,
                      pragmas = used
                    ))
                    when false:
                      poststmts.add(newProc(
                        name = gettername,
                        params = [newTree(nnkVarTy, r[^2]), newIdentDefs(ident"self", newTree(nnkVarTy, ident(typeName)))],
                        body = ifstmt,
                        pragmas = used
                      ))
                    doneFields.incl(fieldName)
          if not defaultBranch.isNil:
            for r in defaultBranch.fields:
              if r.kind == nnkIdentDefs:
                for i in 0 .. r.len - 3:
                  let fieldName = r[i].realBasename
                  if fieldName notin doneFields:
                    let gettername = if (r[i].kind == nnkPragmaExpr and r[i][0].kind == nnkPostfix) or r[i].kind == nnkPostfix:
                        postfix(ident(fieldName), "*") else: ident(fieldName)
                    # somewhat unsafe
                    let body = newDotExpr(newDotExpr(ident"self", defaultBranch.fieldname), ident(fieldName))
                    poststmts.add(newProc(
                      name = gettername,
                      params = [r[^2], newIdentDefs(ident"self", ident(typeName))],
                      body = body,
                      procType = nnkProcDef,
                      pragmas = used
                    ))
                    let setterValue = genSym(nskParam, "value")
                    let setter = body.newAssignment(setterValue)
                    let settername = if (r[i].kind == nnkPragmaExpr and r[i][0].kind == nnkPostfix) or r[i].kind == nnkPostfix:
                        postfix(newTree(nnkAccQuoted, ident(fieldName), ident"="), "*") else: newTree(nnkAccQuoted, ident(fieldName), ident"=")
                    poststmts.add(newProc(
                      name = settername,
                      params = [newEmptyNode(), newIdentDefs(ident"self", newTree(nnkVarTy, ident(typeName))), newIdentDefs(setterValue, r[^2])],
                      body = setter,
                      procType = nnkProcDef,
                      pragmas = used
                    ))
    inc typedefIndex

macro flattenBranches*(body) =
  result = applyTypeMacro(body, patchTypeSection)
