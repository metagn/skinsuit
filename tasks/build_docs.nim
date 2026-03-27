when (NimMajor, NimMinor) >= (1, 4):
  when (compiles do: import nimbleutils):
    import nimbleutils
    # https://github.com/metagn/nimbleutils

when not declared(buildDocs):
  {.error: "docs task not implemented, need nimbleutils".}

# run from project root
buildDocs(gitUrl = "https://github.com/holo-nim/skinsuit")
