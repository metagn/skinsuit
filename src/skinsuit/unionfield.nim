import macros, private/utils

proc patchTypeSection(typeSec: NimNode, poststmts: var seq[NimNode]) =
  for td in typeSec:
    var objectNode = td[^1]
    while objectNode.kind in {nnkRefTy, nnkPtrTy}: objectNode = objectNode[0]
    if objectNode.kind == nnkObjectTy:
      proc doField(idefs: NimNode): NimNode =
        if idefs[0].removePragmaFromExpr("union"):
          result = newNimNode(nnkRecCase, idefs)
          let types = idefs[1]
          let name = idefs[0].realBasename
          result.add(newIdentDefs(genSym(nskField, name & "Type"),
            newTree(nnkBracketExpr, ident"range", infix(newLit(0), "..", newLit(types.len - 1)))))
          for i, t in types:
            result.add(newTree(nnkOfBranch, newLit(i),
              newTree(nnkRecList, newIdentDefs(ident(name & $i), t))))
        else:
          result = idefs
          
      proc eachField(rl: NimNode) =
        case rl.kind
        of nnkRecList:
          for i in 0 ..< rl.len:
            if rl[i].kind == nnkIdentDefs:
              rl[i] = doField(rl[i])
            else:
              eachField(rl[i])
        of nnkRecCase:
          rl[0] = doField(rl[0])
          for b in rl[1..^1]:
            eachField(b[^1])
        of nnkRecWhen:
          for b in rl[1..^1]:
            eachField(b[^1])
        else: error "unknown node kind", rl
            
      eachField(objectNode[^1])

macro unionField*(body): untyped =
  result = applyTypeMacro(body, patchTypeSection)

macro withUnionField*(obj: typed, field, body: untyped): untyped =
  var impl = obj.getTypeImpl
  while impl.kind in {nnkRefTy, nnkPtrTy}: impl = impl[0]
  if impl.kind == nnkSym: impl = impl.getTypeImpl
  expectKind impl, nnkObjectTy
  let fieldName = field.realBasename
  let fieldTypeName = fieldName & "Type"
  for k in impl[^1]:
    if k.kind == nnkRecCase and k[0][0].realBasename.eqIdent(fieldTypeName):
      result = newTree(nnkCaseStmt, newDotExpr(obj, ident(fieldTypeName)))
      for b in k[1..^1]:
        result.add(newTree(nnkOfBranch).add(b[0..^2]).add(newStmtList(
          newProc(
            name = ident(fieldName),
            params = [ident"untyped"],
            body = newDotExpr(obj, ident(b[^1][0][0].realBasename)),
            procType = nnkTemplateDef
          ),
          copy body)))
      return
  error "could not find field " & fieldName, obj

template getUnionField*(obj: typed, field: untyped, ty: untyped): untyped =
  obj.withUnionField(field):
    when field is ty:
      field
    else:
      raise newException(FieldDefect, "field " & astToStr(field) & " was not of type " & $ty)

macro setUnionField*(obj: typed, field: untyped, value: untyped): untyped =
  var objConstr: NimNode
  var impl: NimNode
  case obj.kind
  of nnkObjConstr:
    objConstr = obj
    impl = obj[0].getTypeImpl
  else:
    objConstr = obj
    impl = obj.getTypeImpl
  while impl.kind in {nnkRefTy, nnkPtrTy}: impl = impl[0]
  if impl.kind == nnkSym: impl = impl.getTypeImpl
  expectKind impl, nnkObjectTy
  let fieldName = field.realBasename
  let fieldTypeName = fieldName & "Type"
  for k in impl[^1]:
    if k.kind == nnkRecCase and k[0][0].realBasename.eqIdent(fieldTypeName):
      result = newTree(nnkWhenStmt)
      for b in k[1..^1]:
        let
          (lhs1, rhs1) = (ident(fieldTypeName), b[0])
          (lhs2, rhs2) = (ident(b[^1][0][0].realBasename), value)
        result.add(newTree(nnkElifBranch, infix(value, "is", b[^1][0][^2]),
          if objConstr.kind == nnkObjConstr:
            copy(objConstr).add(
              newColonExpr(lhs1, rhs1),
              newColonExpr(lhs2, rhs2))
          else:
            newStmtList(
              newAssignment(newDotExpr(objConstr, lhs1), rhs1),
              newAssignment(newDotExpr(objConstr, lhs2), rhs2)
            )))
      return
