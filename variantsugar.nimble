# Package

version       = "0.1.0"
author        = "metagn"
description   = "utility macros mostly for object variants"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.6.0"

when (NimMajor, NimMinor) >= (1, 4):
  when (compiles do: import nimbleutils):
    import nimbleutils
    # https://github.com/metagn/nimbleutils

task docs, "build docs for all modules":
  when declared(buildDocs):
    buildDocs(gitUrl = "https://github.com/metagn/variantsugar")
  else:
    echo "docs task not implemented, need nimbleutils"

task tests, "run tests for multiple backends and defines":
  when declared(runTests):
    runTests(backends = {c, js, nims})
  else:
    echo "tests task not implemented, need nimbleutils"
