import macros, strutils

proc uncapitalizeAscii*(s: string): string =
  result = s
  result[0] = result[0].toLowerAscii

proc realBasename*(n: NimNode): string =
  $(if n.kind in {nnkPostfix, nnkPragmaExpr}: n.basename else: n)

proc isNodeExported*(n: NimNode): bool =
  case n.kind
  of nnkPostfix: true
  of nnkPragmaExpr: isNodeExported(n[0])
  else: false

proc exportIf*(n: NimNode, b: bool): NimNode =
  case n.kind
  of nnkPostfix:
    result = n
  of nnkPragmaExpr:
    result = copy(n)
    result[0] = result[0].exportIf(b)
  else:
    result = if b: postfix(n, "*") else: n

proc replaceIdent*(n: NimNode, name: string, to: NimNode) =
  if n.kind != nnkAccQuoted:
    for i in 1 ..< n.len:
      if n[i].eqIdent(name) and not (i == 0 and n.kind in nnkCallKinds): n[i] = to
      else: replaceIdent(n[i], name, to)

proc withoutPragma*(prag: NimNode, name: string): (bool, NimNode) =
  result[1] = newNimNode(nnkPragma, prag)
  for i in 0 ..< prag.len:
    if not prag[i].eqIdent(name):
      result[1].add(prag[i])
    else:
      result[0] = true
  if result[1].len == 0:
    result[1] = newEmptyNode()

proc removePragmaFromExpr*(node: NimNode, name: string): bool =
  if node.kind == nnkPragmaExpr:
    let (res, newNode) = node[1].withoutPragma(name)
    if res:
      result = res
      node[1] = newNode

proc skipTypeDesc*(node: NimNode): NimNode =
  result = node
  while result.kind == nnkBracketExpr and result[0].eqIdent"typedesc":
    result = result[1]

proc collectTypeSection(n: NimNode): NimNode =
  result = newNimNode(nnkTypeSection, n)
  case n.kind
  of nnkTypeSection:
    result.add(n[0..^1])
  of nnkTypeDef:
    result.add(n)
  of nnkStmtList:
    for b in n:
      result.add(collectTypeSection(b)[0..^1])
  else:
    error "expected type section", n

proc applyTypeMacro*(body: NimNode, p: proc (typeSection: NimNode, poststmts: var seq[NimNode])): NimNode =
  let inTypeSection = body.kind == nnkTypeDef
  let typeSec = collectTypeSection(body)
  var poststmts: seq[NimNode]
  p(typeSec, poststmts)
  if inTypeSection:
    if typeSec.len == 1 and poststmts.len == 0:
      result = typeSec[0]
    else:
      result = newTree(nnkTypeDef, genSym(nskType, "_"), newEmptyNode(),
        newTree(nnkStmtListType, typeSec).add(poststmts).add(bindSym"void"))
  elif poststmts.len == 0:
    result = typeSec
  else:
    result = newStmtList(typeSec).add(poststmts)
