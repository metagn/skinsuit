## object variants generalized to any condition for each possible union value

runnableExamples:
  conditionalUnion:
    type Foo = ref object
      num: int
      case branch: _ # type has to be _, all types without a case branch with _ as discriminator type are kept in the type section
      # the name "branch" can be changed or made _ in which case it defaults to "branch" for now
      of Odd, num mod 2 == 1: # branch names can also be _
        name: string
      of DoubleEven, num mod 4 == 0:
        a, b: int
      of Even:
        a: int # duplicate names are allowed, only the accessors care that they have the same type

  var foo = Foo(num: 1)
  foo.name = "abc"
  doAssert foo.name == "abc"
  doAssert foo.branch == Odd # branch is not an actual variable
  foo.num = 2
  foo.resetBranch() # advantage over object variants, named after "branch"
  foo.a = 3
  doAssert foo.a == 3
  doAssert foo.branch == Even
  foo.num = 16
  doAssert foo.a == 3
  foo.b = 4
  doAssert foo.b == 4
  doAssert foo.branch == DoubleEven

import macros, strutils, sets, private/utils

type ConditionalFieldDefect* = object of FieldDefect

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
        if rec.kind == nnkRecCase and rec[0][1].eqIdent("_"):
          type Branch = ref object
            index: int
            name: string
            cond, fields: NimNode
          var
            branches: seq[Branch]
            defaultBranch: Branch
            allBranches: seq[Branch]
            branchName: NimNode
            branchNameExported: bool
          if rec[0][0].kind == nnkPostfix:
            branchNameExported = true
            rec[0][0] = rec[0][0][1]
          branchName = ident(rec[0][0].realBasename)
          template exportIfBranchExported(n: NimNode): NimNode =
            if branchNameExported: postfix(n, "*") else: n
          let used = newTree(nnkPragma, ident"used")
          for i in 1 ..< rec.len:
            let b = rec[i]
            case b.kind
            of nnkOfBranch:
              if b.len > 3: error("`of` for branches only accepts a name and an optional condition", b)
              let name = b[0]
              if name.kind notin {nnkIdent, nnkSym, nnkOpenSymChoice, nnkClosedSymChoice, nnkAccQuoted}:
                error("first argument of `of` must be branch name", name)
              let cond = if b.len == 3: b[1] else: nil
              if not cond.isNil:
                for f in fieldNames:
                  cond.replaceIdent(f, newDotExpr(ident"self", ident(f)))
              let recList = b[^1]
              let branch = Branch(name: if name.eqIdent("_"): "" else: $name, cond: cond, fields: recList)
              if cond.isNil:
                if not defaultBranch.isNil:
                  error("cannot set multiple default branches" &
                    (if defaultBranch.name.len != 0: ", original default branch is " & defaultBranch.name
                    else: ""), b)
                defaultBranch = branch
              else:
                branches.add(branch)
              allBranches.add(branch)
            of nnkElse:
              let branch = Branch(name: "", cond: nil, fields: b[1])
              branches.add(branch)
              allBranches.add(branch)
            of nnkElifBranch: # not actually possible
              let branch = Branch(name: "", cond: b[0], fields: b[1])
              branches.add(branch)
              allBranches.add(branch)
            else: error("unexpected reccase branch kind " & $b.kind, b)
          let kinds = newTree(nnkEnumTy, newEmptyNode())
          for i, a in allBranches:
            a.index = i
            if a.name.len != 0:
              kinds.add(newTree(nnkEnumFieldDef, ident(a.name), newLit(i)))
          let realBranchName = if branchName.isNil: "branch" else: $branchName
          let capitalizedBranch = capitalizeAscii(realBranchName)
          let baseTypeName = typeName & capitalizedBranch
          let enumName = ident(baseTypeName & "Kind")
          insertType(newTree(nnkTypeDef, enumName, newEmptyNode(), kinds))
          template objtype(b: Branch): NimNode =
            ident(baseTypeName &
              (if b.name.len == 0: $b.index else: b.name.capitalizeAscii) & "Obj")
          template fieldname(b: Branch): NimNode =
            ident((if b.name.len == 0: "branch" & $b.index else: b.name.uncapitalizeAscii) & "Obj")
          let unionRecList = newNimNode(nnkRecList)
          for b in allBranches:
            let objt = b.objtype
            insertType(newTree(nnkTypeDef, objt, newEmptyNode(),
              newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), b.fields)))
            unionRecList.add(newTree(nnkIdentDefs, b.fieldname, objt, newEmptyNode()))
          let unionTypeName = ident(baseTypeName & "Obj")
          insertType(newTree(nnkTypeDef,
            newTree(nnkPragmaExpr, unionTypeName, newTree(nnkPragma, ident"union")),
            newEmptyNode(),
            newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), unionRecList)))
          when defined(js) and false:
            insertType(newTree(nnkTypeDef,
              newTree(nnkPragmaExpr, unionTypeName, newEmptyNode()),
              newEmptyNode(),
              newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), newTree(nnkRecList))))
            for u in unionRecList:
              let name = u[0]
              let ty = u[1]
              poststmts.add(newProc(
                name = name,
                params = [ident"untyped", newIdentDefs(ident"self", unionTypeName)],
                procType = nnkTemplateDef,
                body = newTree(nnkCast, newTree(nnkRefTy, ty), ident"self")))
          let unionFieldName = ident(uncapitalizeAscii(realBranchName) & "Obj")
          objectNode[2][recI] = newTree(nnkIdentDefs, unionFieldName, unionTypeName, newEmptyNode())
          when false:
            let fieldTemplates = newStmtList()
            for f in fieldNames:
              fieldTemplates.add(newProc(
                name = ident(f),
                params = [ident"untyped"],
                body = newDotExpr(ident"self", ident(f)),
                procType = nnkTemplateDef,
                pragmas = used))
          template nameOrEnumConvIndex(b: Branch): NimNode =
            if b.name.len == 0: newCall(enumName, newLit(b.index)) else: ident(b.name)
          block branchkind:
            let ifstmt = newNimNode(nnkIfStmt)
            for b in branches:
              ifstmt.add(newTree(nnkElifBranch, b.cond.copy,
                b.nameOrEnumConvIndex))
            if not defaultBranch.isNil:
              ifstmt.add(newTree(nnkElse, defaultBranch.nameOrEnumConvIndex))
            else:
              ifstmt.add(newTree(nnkElse, newCall(enumName, newLit(0))))
            poststmts.add(
              newProc(
                name = ident(realBranchName).exportIfBranchExported,
                params = [enumName, newIdentDefs(ident"self", ident(typeName))],
                body = ifstmt,
                pragmas = used
              )
            )
          poststmts.add(
            newProc(
              name = ident("reset" & capitalizedBranch).exportIfBranchExported,
              params = [newEmptyNode(), newIdentDefs(ident"self", newTree(nnkVarTy, ident(typeName)))],
              body = newCall("reset", newDotExpr(ident"self", unionFieldName)),
              pragmas = used))
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
                      newDotExpr(newDotExpr(newDotExpr(ident"self", unionFieldName), b.fieldname), ident(fieldName))
                    let setterValue = genSym(nskParam, "value")
                    var ifstmt = newTree(nnkIfStmt)
                    var setter = newTree(nnkIfStmt)
                    var names: seq[string]
                    names.add(if bran.name.len == 0: $bran.index else: bran.name)
                    ifstmt.add(newTree(nnkElifBranch, bran.cond.copy, bran.getField))
                    setter.add(newTree(nnkElifBranch, bran.cond.copy, bran.getField.newAssignment(setterValue)))
                    for ob in otherBranches:
                      ifstmt.add(newTree(nnkElifBranch, ob.cond.copy, ob.getField))
                      setter.add(newTree(nnkElifBranch, ob.cond.copy, ob.getField.newAssignment(setterValue)))
                      names.add(if ob.name.len == 0: $ob.index else: ob.name)
                    if not defaultBranch.isNil and defaultBranch.fields.hasField(fieldName):
                      ifstmt.add(newTree(nnkElse, defaultBranch.getField))
                      setter.add(newTree(nnkElse, defaultBranch.getField.newAssignment(setterValue)))
                    elif otherBranches.len == 0: # unsafe
                      ifstmt = ifstmt[0][1]
                      setter = setter[0][1]
                    else:
                      let raiser = newTree(nnkElse,
                        newTree(nnkRaiseStmt, newCall("newException", ident"ConditionalFieldDefect",
                          newLit("object is not of branch " & names.join(" or ") & " and therefore does not have field `" & fieldName & "`"))))
                      ifstmt.add(raiser)
                      setter.add(raiser)
                    let gettername = if (r[i].kind == nnkPragmaExpr and r[i][0].kind == nnkPostfix) or r[i].kind == nnkPostfix:
                        postfix(ident(fieldName), "*") else: ident(fieldName)
                    poststmts.add(newProc(
                      name = gettername,
                      params = [r[^2], newIdentDefs(ident"self", ident(typeName))],
                      body = ifstmt,
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
                    let body = newDotExpr(newDotExpr(newDotExpr(ident"self", unionFieldName), defaultBranch.fieldname), ident(fieldName))
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

macro conditionalUnion*(body) =
  result = applyTypeMacro(body, patchTypeSection)
