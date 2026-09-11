# N# compile time

| fact | value |
|---|---|
| measured (local date) | 2026-09-01 |
| CLI commit | `8cf40128a2175ecf5a61196a6ab7f7911ded5afc` |
| CLI under test | `/tmp/nsharp-csharp-ref/src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll` |
| dotnet --version | 10.0.105 |
| OS (`uname -sr`) | Darwin 24.6.0 |
| architecture (`uname -m`) | arm64 |
| logical processors | 10 |
| peak RSS source | /usr/bin/time -l |
| runs per project per command | 5 |
| median rule | the middle value of the sorted runs; for an EVEN run count, the LOWER middle value |
| scope | corpus |
| only | (none — every project in scope) |
| corpus size | 68 projects with a `project.yml` under `examples/`, `tests/` and `templates/`, of which 41 have non-test sources |

## How these numbers are produced

- **Wall clock** is `DateTime.UtcNow` immediately before `Process.Start()` and immediately
  after `WaitForExit()`, in milliseconds. It is the number the columns below report.
- **resolve / emit / total** are the CLI's OWN `--timings` numbers, read off stderr. The CLI
  formats them to a tenth of a second, so they are coarser than the wall clock by
  construction and are shown for the resolve-versus-emit split, not for precision.
- **peak RSS** is the kernel's maximum resident set for the child, via `/usr/bin/time -l`.
  An em dash means the OS time utility was unavailable, which is never a failure.
- **Every build is fresh.** `nlc build` has no incremental cache and `nlc check` has no daemon
  on this path; the build output goes to a directory created new under the system temp
  directory for every single run and deleted afterwards.
- **Every build is proven not to have touched the tree.** A recursive listing of the project
  directory (relative path and last-write UTC tick, every directory sorted) is taken before and
  after each build, and any difference is a harness failure carried to a non-zero exit code.
  The listing carries no byte length because `FileInfo` is unreachable on this emit path; the
  last-write tick moves on any write regardless of whether the length did.
- **A project that fails to compile keeps its timing.** The `ok` column marks it; the time the
  CLI took to reject the project is still compile time.
- **A FAILING build did not reach emit, and its milliseconds do not cover emit.** `nlc build`
  calls `MultiFileCompiler.CompileToIlAssembly(validateStrictLint: true)`, and
  `RunLegacyValidationPipeline` RETURNS before `AnalyzeAllFiles()` as soon as strict lint reports
  an error. So a row whose `ok` is `no (build)` measures PARSE + STRICT LINT only — read its
  `check results` census below to see what stopped it. The regression gate pins this explicitly:
  its baseline carries a `stage` and an `expectedExitCode`, and a run that stops failing fails
  the gate, because it would then be measuring stages the baseline never covered.
- **A project with no non-test sources is classified, not failed.** Neither command is spawned
  for it; see the section below.

### The file-selection rule, replicated

`files` and `lines` count the `.nl` files the command ACTUALLY compiles. `nlc build` reaches
its source list through `ProjectConfig.GetSourceFiles(projectRoot, includeTests: false)`, and
`nlc check` reaches the SAME function through `CodeIntelligenceService.LoadProject` ->
`MultiFileCompilerInputBuilder.BuildFromProject` -> `DiscoverSourceFiles`, which also passes
`false`. **Build and check therefore select the same file set, so there is one file count and
one line count per project, not two.** The rule is:

1. Recursively collect `*.nl` under the project directory.
2. Do not descend into `.context`, `.git`, `.github`, `.hermes`, `.vscode`, `.vscode-test`,
   `.worktrees`, `bin`, `node_modules`, `nsharp`, `obj` or `out` (`ShouldSkipSourceDirectory`).
3. Drop every path ending in `.tests.nl`, case-insensitively.

`lines` is the number of `\n`-terminated lines in those files. Each measured project
cross-checks this replication against the live compiler: the `checkedFiles` field of
`nlc check --json` is `snapshot.SourceFiles.Count`, and a disagreement is reported below.

`ProjectSourceFileFilter` also drops paths matching the `exclude:` globs of `project.yml`.
No measured project declares `exclude:`, so that arm is not replicated; the `checkedFiles`
cross-check is what would catch a project that started to.

## The large-project case: `src/NSharpLang.Compiler.BootstrapServices`

_Not measured in this run._

## The corpus

| project | files | lines | ok | build median ms | resolve ms | emit ms | total ms | build peak RSS MB | build lines/s | check median ms | check peak RSS MB | check lines/s | check results |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `examples/01-hello-world` | 1 | 20 | yes | 271 | 0 | 200 | 200 | 74.5 | 73.8 | 275 | 77.6 | 72.7 | 0 |
| `examples/11-advanced-features/CheckedUnchecked` | 1 | 90 | yes | 269 | 0 | 200 | 200 | 76.0 | 334.6 | 273 | 80.2 | 329.7 | 0 |
| `examples/11-advanced-features/ConversionOperators` | 1 | 149 | yes | 294 | 0 | 200 | 200 | 75.7 | 506.8 | 294 | 79.0 | 506.8 | 0 |
| `examples/11-advanced-features/FileScopedSimple` | 1 | 56 | yes | 289 | 0 | 200 | 200 | 74.8 | 193.8 | 294 | 77.6 | 190.5 | 0 |
| `examples/11-advanced-features/FileScopedTypes` | 1 | 119 | yes | 340 | 0 | 300 | 300 | 79.5 | 350.0 | 350 | 85.8 | 340.0 | 0 |
| `examples/11-advanced-features/InterpolatedRawStrings` | 1 | 72 | yes | 265 | 0 | 200 | 200 | 73.8 | 271.7 | 269 | 76.8 | 267.7 | 0 |
| `examples/11-advanced-features/LockStatement` | 1 | 126 | yes | 346 | 0 | 300 | 300 | 84.7 | 364.2 | 355 | 89.7 | 354.9 | 0 |
| `examples/11-advanced-features/OperatorOverloading` | 1 | 65 | yes | 271 | 0 | 200 | 200 | 74.9 | 239.9 | 274 | 77.9 | 237.2 | 0 |
| `examples/11-advanced-features/PreprocessorDirectives` | 1 | 43 | yes | 273 | 0 | 200 | 200 | 74.1 | 157.5 | 278 | 76.8 | 154.7 | 0 |
| `examples/12-multi-file-projects/AutoDiscovery` | 3 | 73 | yes | 335 | 0 | 300 | 300 | 85.1 | 217.9 | 350 | 89.0 | 208.6 | 0 |
| `examples/12-multi-file-projects/MultiFileProject` | 3 | 77 | yes | 342 | 0 | 300 | 300 | 86.2 | 225.1 | 363 | 91.5 | 212.1 | 0 |
| `examples/12-multi-file-projects/SimpleProject` | 1 | 5 | yes | 216 | 0 | 100 | 100 | 72.3 | 23.1 | 220 | 75.0 | 22.7 | 0 |
| `examples/12-multi-file-projects/TestExample` | 1 | 23 | yes | 245 | 0 | 200 | 200 | 72.3 | 93.9 | 263 | 79.2 | 87.5 | 0 |
| `examples/12-multi-file-projects/WeatherDemo` | 3 | 132 | yes | 658 | 0 | 600 | 600 | 128.6 | 200.6 | 698 | 136.8 | 189.1 | 0 |
| `examples/12-multi-file-projects/imports` | 2 | 30 | yes | 280 | 0 | 200 | 200 | 74.3 | 107.1 | 285 | 77.1 | 105.3 | 0 |
| `examples/14-minimal-api` | 1 | 33 | yes | 597 | 0 | 500 | 500 | 198.3 | 55.3 | 655 | 225.0 | 50.4 | 0 |
| `examples/16-task-cli` | 11 | 978 | yes | 994 | 0 | 900 | 900 | 135.0 | 983.9 | 1294 | 152.5 | 755.8 | 0 |
| `examples/17-issue-tracker/backend` | 7 | 523 | yes | 1609 | 0 | 1500 | 1500 | 213.7 | 325.0 | 1861 | 253.2 | 281.0 | 0 |
| `templates/nsharp-console` | 1 | 3 | yes | 213 | 0 | 100 | 100 | 72.2 | 14.1 | 218 | 74.9 | 13.8 | 0 |
| `templates/nsharp-library` | 1 | 9 | yes | 222 | 0 | 100 | 100 | 70.3 | 40.5 | 237 | 75.5 | 38.0 | 0 |
| `templates/nsharp-systems-cli` | 1 | 33 | yes | 310 | 0 | 200 | 200 | 79.0 | 106.5 | 321 | 85.7 | 102.8 | 1 |
| `templates/nsharp-systems-lib` | 1 | 25 | **no (build+check)** | 241 | — | — | — | 77.3 | 103.7 | 252 | 79.0 | 99.2 | 1 |
| `templates/nsharp-test` | 1 | 9 | yes | 223 | 0 | 100 | 100 | 70.2 | 40.4 | 238 | 75.5 | 37.8 | 0 |
| `templates/nsharp-webapi` | 2 | 46 | yes | 756 | 0 | 700 | 700 | 199.9 | 60.8 | 836 | 228.7 | 55.0 | 0 |
| `tests/fixtures/external-base-interface` | 1 | 40 | yes | 231 | 0 | 200 | 200 | 72.1 | 173.2 | 247 | 78.8 | 161.9 | 0 |
| `tests/fixtures/external-static-package` | 1 | 26 | **no (build+check)** | 230 | — | — | — | 83.9 | 113.0 | 239 | 85.8 | 108.8 | 1 |
| `tests/fixtures/external-static-relative-dll` | 1 | 12 | yes | 274 | 0 | 200 | 200 | 76.6 | 43.8 | 279 | 81.4 | 43.0 | 0 |
| `tests/fixtures/issue-tracker` | 7 | 448 | yes | 1354 | 0 | 1300 | 1300 | 217.3 | 330.9 | 1723 | 259.1 | 260.0 | 0 |
| `tests/native/analyzer-binding-map` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/analyzer-clean-source` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/analyzer-error-handling` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/analyzer-event-subscription` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/analyzer-identifier-binding` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/analyzer-semantic-model` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/as-boxing` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/async-task-like` | 1 | 57 | yes | 309 | 0 | 200 | 200 | 80.0 | 184.5 | 331 | 87.4 | 172.2 | 0 |
| `tests/native/boolean-code-plan` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/char-classification` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/cli-command-contracts` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/columnar-emit-facts` | 1 | 11 | yes | 211 | 0 | 100 | 100 | 69.9 | 52.1 | 226 | 75.1 | 48.7 | 0 |
| `tests/native/completion-engine` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/conditional` | 1 | 87 | yes | 282 | 0 | 200 | 200 | 72.6 | 308.5 | 297 | 78.4 | 292.9 | 0 |
| `tests/native/construction-arrays` | 3 | 498 | **no (build+check)** | 288 | — | — | — | 89.3 | 1729.2 | 299 | 91.3 | 1665.6 | 2 |
| `tests/native/direct-calls` | 1 | 353 | **no (build+check)** | 351 | — | — | — | 87.0 | 1005.7 | 379 | 95.4 | 931.4 | 1 |
| `tests/native/doc-query` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/erased-enum-identity` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/extension-calls` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/external-base-interface` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/generic-scope-invalid` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/interface-parameter-modifiers` | 1 | 47 | yes | 271 | 0 | 200 | 200 | 72.3 | 173.4 | 288 | 78.0 | 163.2 | 0 |
| `tests/native/iterators` | 1 | 259 | yes | 356 | 0 | 300 | 300 | 86.9 | 727.5 | 382 | 98.2 | 678.0 | 0 |
| `tests/native/lambda-placement` | 1 | 67 | yes | 557 | 0 | 500 | 500 | 123.9 | 120.3 | 592 | 135.4 | 113.2 | 0 |
| `tests/native/ownership-audit` | 2 | 1406 | yes | 806 | 0 | 700 | 700 | 102.3 | 1744.4 | 1077 | 118.3 | 1305.5 | 0 |
| `tests/native/parser-literal-facts` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/playground-diagnostic-spans` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/playground-tooling-surfaces` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/primitive-binary` | 1 | 375 | yes | 342 | 0 | 300 | 300 | 80.5 | 1096.5 | 368 | 92.1 | 1019.0 | 0 |
| `tests/native/query-completions` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/query-integration` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/range-index` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/readonly-dictionary-widening` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/readonly-init` | 1 | 113 | yes | 257 | 0 | 200 | 200 | 72.3 | 439.7 | 271 | 78.0 | 417.0 | 0 |
| `tests/native/record-with` | 1 | 58 | yes | 306 | 0 | 200 | 200 | 77.1 | 189.5 | 329 | 86.8 | 176.3 | 0 |
| `tests/native/reflection-emit-bootstrap` | 2 | 453 | yes | 573 | 0 | 500 | 500 | 92.7 | 790.6 | 682 | 104.0 | 664.2 | 0 |
| `tests/native/scalar-code-plan` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/systems-analysis-census` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/systems-gauntlet-facts` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/systems-proof-corpus` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |

## Aggregate over the corpus

| command | scope | projects | lines | sum of median wall ms | aggregate lines/s |
|---|---|---:|---:|---:|---:|
| build | measured corpus projects | 41 | 7049 | 16857 | 418.2 |
| build | compiled (status=measured, exit 0) | 37 | 6147 | 15747 | 390.4 |
| check | measured corpus projects | 41 | 7049 | 18762 | 375.7 |
| check | compiled (status=measured, exit 0) | 37 | 6147 | 17593 | 349.4 |

- `build` per-project lines/s — median 193.8, slowest `templates/nsharp-console` at 14.1, fastest `tests/native/ownership-audit` at 1744.4 (over 41 measured project rows).
- `check` per-project lines/s — median 189.1, slowest `templates/nsharp-console` at 13.8, fastest `tests/native/construction-arrays` at 1665.6 (over 41 measured project rows).

## Projects with no non-test sources

These 27 project(s) hold only `.tests.nl` files.
`nlc build` and `nlc check` both exclude `*.tests.nl`, so neither command has anything
to compile here and both exit 1 — which is why NEITHER WAS SPAWNED and these rows are
classified rather than counted as failures. They are compiled by `nlc test`, in the product
gate's Step 3a, and they contribute no lines and no project to the aggregates above.

- `tests/native/analyzer-binding-map`
- `tests/native/analyzer-clean-source`
- `tests/native/analyzer-error-handling`
- `tests/native/analyzer-event-subscription`
- `tests/native/analyzer-identifier-binding`
- `tests/native/analyzer-semantic-model`
- `tests/native/as-boxing`
- `tests/native/boolean-code-plan`
- `tests/native/char-classification`
- `tests/native/cli-command-contracts`
- `tests/native/completion-engine`
- `tests/native/doc-query`
- `tests/native/erased-enum-identity`
- `tests/native/extension-calls`
- `tests/native/external-base-interface`
- `tests/native/generic-scope-invalid`
- `tests/native/parser-literal-facts`
- `tests/native/playground-diagnostic-spans`
- `tests/native/playground-tooling-surfaces`
- `tests/native/query-completions`
- `tests/native/query-integration`
- `tests/native/range-index`
- `tests/native/readonly-dictionary-widening`
- `tests/native/scalar-code-plan`
- `tests/native/systems-analysis-census`
- `tests/native/systems-gauntlet-facts`
- `tests/native/systems-proof-corpus`

## Projects that did not compile

**`templates/nsharp-systems-lib`** (`build`) — exit 1 on run 1

```
[2m-- NAMING ERROR --------------------------------------------------[0m  /private/tmp/nsharp-compile-bench/templates/nsharp-systems-lib/PacketCore.nl

I cannot find a member called `AsSpan` on type `byte[]`:

[1;36m21|[0m         return ParseLength(bytes.AsSpan())
[1;36m                                   ^^^^^^[0m

Hint: The type `byte[]` does not have a member named `AsSpan`.
Check the type's documentation for available members.

[1;36mRead more:[0m https://docs.n-sharp.dev/errors/NL303
```

**`templates/nsharp-systems-lib`** (`check`) — exit 1 on run 1

Diagnostic census from the `nlc check --json` envelope: 1 results: NL303 ×1

```
(the command wrote nothing to stderr; its diagnostics are in the JSON envelope on stdout)
```

**`tests/fixtures/external-static-package`** (`build`) — exit 1 on run 1

```
[2m-- NAMING ERROR --------------------------------------------------[0m  /private/tmp/nsharp-compile-bench/tests/fixtures/external-static-package/ExternalStaticPackage.nl

I cannot find a `System` variable on line 21:

[1;36m21|[0m         return System.Reflection.Emit.OpCodes.Ldsfld
[1;36m                 ^^^^^^[0m

Hint: Make sure you've declared this variable before using it.

[1;36mRead more:[0m https://docs.n-sharp.dev/errors/NL301
```

**`tests/fixtures/external-static-package`** (`check`) — exit 1 on run 1

Diagnostic census from the `nlc check --json` envelope: 1 results: NL301 ×1

```
(the command wrote nothing to stderr; its diagnostics are in the JSON envelope on stdout)
```

**`tests/native/construction-arrays`** (`build`) — exit 1 on run 1

```
[1;31merror[0m [1mNL201[0m: Type 'Sibling' not found
  [1;36m-->[0m /private/tmp/nsharp-compile-bench/tests/native/construction-arrays/ConstructionArrays.nl:150:30
   [1;36m|[0m
[1;36m150 |[0m             func Echo(value: Sibling): Sibling {
   [1;36m|[0m                              [1;31m^^^^^^^[0m
   [1;36m|[0m
[1;32mhelp[0m: Check the spelling, add the missing 'import', or add the package/project reference that provides 'Sibling'.

[1;31merror[0m [1mNL201[0m: Type 'Sibling' not found
  [1;36m-->[0m /private/tmp/nsharp-compile-bench/tests/native/construction-arrays/ConstructionArrays.nl:150:40
   [1;36m|[0m
[1;36m150 |[0m             func Echo(value: Sibling): Sibling {
   [1;36m|[0m                                        [1;31m^^^^^^^[0m
   [1;36m|[0m
[1;32mhelp[0m: Check the spelling, add the missing 'import', or add the package/project reference that provides 'Sibling'.
```

**`tests/native/construction-arrays`** (`check`) — exit 1 on run 1

Diagnostic census from the `nlc check --json` envelope: 2 results: NL201 ×2

```
(the command wrote nothing to stderr; its diagnostics are in the JSON envelope on stdout)
```

**`tests/native/direct-calls`** (`build`) — exit 1 on run 1

```
[1;31merror[0m [1mNL103[0m: Failed to emit IL assembly 'NSharpLang.DirectCalls.Tests': No matching overload for static method AcceptSmallNullable on type NSharpLang.DirectCalls.Tests.DirectConvertedCalls with arguments (System.Int32)
  [1;36m-->[0m line 0, column 0
```

**`tests/native/direct-calls`** (`check`) — exit 1 on run 1

Diagnostic census from the `nlc check --json` envelope: 1 results: NL103 ×1

```
(the command wrote nothing to stderr; its diagnostics are in the JSON envelope on stdout)
```


## File-count cross-check against the live compiler

_Every project whose `nlc check --json` envelope carried `checkedFiles` agreed with the
replicated selection rule._

## Repository tree after the sweep

_Every measured project directory was byte-identical before and after every build._

