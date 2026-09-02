# N# compile time

| fact | value |
|---|---|
| measured (local date) | 2026-09-01 |
| CLI commit | `8cf40128a2175ecf5a61196a6ab7f7911ded5afc` |
| CLI under test | `/private/tmp/nsharp-compile-bench/src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll` |
| dotnet --version | 10.0.105 |
| OS (`uname -sr`) | Darwin 24.6.0 |
| architecture (`uname -m`) | arm64 |
| logical processors | 10 |
| peak RSS source | /usr/bin/time -l |
| runs per project per command | 5 |
| median rule | the middle value of the sorted runs; for an EVEN run count, the LOWER middle value |
| scope | all |
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

| project | files | lines | ok | build median ms | resolve ms | emit ms | total ms | build peak RSS MB | build lines/s | check median ms | check peak RSS MB | check lines/s | check results |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `src/NSharpLang.Compiler.BootstrapServices` | 403 | 172653 | **no (build+check)** | 7868 | — | — | — | 172.2 | 21943.7 | 26997 | 683.4 | 6395.3 | 243 |

## The corpus

| project | files | lines | ok | build median ms | resolve ms | emit ms | total ms | build peak RSS MB | build lines/s | check median ms | check peak RSS MB | check lines/s | check results |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `examples/01-hello-world` | 1 | 20 | yes | 296 | 0 | 200 | 200 | 93.4 | 67.6 | 296 | 97.0 | 67.6 | 0 |
| `examples/11-advanced-features/CheckedUnchecked` | 1 | 90 | yes | 288 | 0 | 200 | 200 | 95.5 | 312.5 | 295 | 100.5 | 305.1 | 0 |
| `examples/11-advanced-features/ConversionOperators` | 1 | 149 | yes | 317 | 0 | 200 | 200 | 98.5 | 470.0 | 324 | 101.1 | 459.9 | 0 |
| `examples/11-advanced-features/FileScopedSimple` | 1 | 56 | yes | 322 | 0 | 300 | 300 | 95.5 | 173.9 | 326 | 99.3 | 171.8 | 0 |
| `examples/11-advanced-features/FileScopedTypes` | 1 | 119 | yes | 367 | 0 | 300 | 300 | 100.8 | 324.3 | 382 | 111.6 | 311.5 | 0 |
| `examples/11-advanced-features/InterpolatedRawStrings` | 1 | 72 | yes | 293 | 0 | 200 | 200 | 93.8 | 245.7 | 296 | 97.6 | 243.2 | 0 |
| `examples/11-advanced-features/LockStatement` | 1 | 126 | yes | 378 | 0 | 300 | 300 | 102.2 | 333.3 | 393 | 107.2 | 320.6 | 0 |
| `examples/11-advanced-features/OperatorOverloading` | 1 | 65 | yes | 303 | 0 | 200 | 200 | 97.5 | 214.5 | 308 | 100.6 | 211.0 | 0 |
| `examples/11-advanced-features/PreprocessorDirectives` | 1 | 43 | yes | 300 | 0 | 200 | 200 | 93.8 | 143.3 | 304 | 97.2 | 141.4 | 0 |
| `examples/12-multi-file-projects/AutoDiscovery` | 3 | 73 | yes | 366 | 0 | 300 | 300 | 100.3 | 199.5 | 373 | 109.1 | 195.7 | 0 |
| `examples/12-multi-file-projects/MultiFileProject` | 3 | 77 | yes | 371 | 0 | 300 | 300 | 100.3 | 207.5 | 380 | 106.0 | 202.6 | 0 |
| `examples/12-multi-file-projects/SimpleProject` | 1 | 5 | yes | 236 | 0 | 200 | 200 | 90.7 | 21.2 | 239 | 93.8 | 20.9 | 0 |
| `examples/12-multi-file-projects/TestExample` | 1 | 23 | yes | 278 | 0 | 200 | 200 | 95.7 | 82.7 | 295 | 102.3 | 78.0 | 0 |
| `examples/12-multi-file-projects/WeatherDemo` | 3 | 132 | yes | 499 | 0 | 400 | 400 | 134.2 | 264.5 | 523 | 140.2 | 252.4 | 0 |
| `examples/12-multi-file-projects/imports` | 2 | 30 | yes | 303 | 0 | 200 | 200 | 93.6 | 99.0 | 307 | 97.1 | 97.7 | 0 |
| `examples/14-minimal-api` | 1 | 33 | yes | 634 | 0 | 600 | 600 | 193.5 | 52.1 | 681 | 219.1 | 48.5 | 0 |
| `examples/16-task-cli` | 11 | 978 | yes | 836 | 0 | 800 | 800 | 143.3 | 1169.9 | 965 | 153.5 | 1013.5 | 0 |
| `examples/17-issue-tracker/backend` | 7 | 523 | yes | 1380 | 0 | 1300 | 1300 | 227.0 | 379.0 | 1535 | 261.8 | 340.7 | 0 |
| `templates/nsharp-console` | 1 | 3 | yes | 235 | 0 | 200 | 200 | 90.8 | 12.8 | 245 | 94.0 | 12.2 | 0 |
| `templates/nsharp-library` | 1 | 9 | yes | 222 | 0 | 200 | 200 | 86.1 | 40.5 | 235 | 91.8 | 38.3 | 0 |
| `templates/nsharp-systems-cli` | 1 | 33 | **no (build+check)** | 198 | — | — | — | 67.1 | 166.7 | 209 | 69.9 | 157.9 | 2 |
| `templates/nsharp-systems-lib` | 1 | 25 | **no (build+check)** | 197 | — | — | — | 66.9 | 126.9 | 207 | 69.8 | 120.8 | 1 |
| `templates/nsharp-test` | 1 | 9 | yes | 219 | 0 | 100 | 200 | 86.1 | 41.1 | 237 | 91.8 | 38.0 | 0 |
| `templates/nsharp-webapi` | 2 | 46 | yes | 653 | 0 | 600 | 600 | 198.1 | 70.4 | 704 | 221.2 | 65.3 | 0 |
| `tests/fixtures/external-base-interface` | 1 | 40 | yes | 236 | 0 | 200 | 200 | 93.2 | 169.5 | 255 | 97.5 | 156.9 | 0 |
| `tests/fixtures/external-static-package` | 1 | 26 | yes | 327 | 0 | 200 | 300 | 108.7 | 79.5 | 331 | 116.3 | 78.5 | 0 |
| `tests/fixtures/external-static-relative-dll` | 1 | 12 | yes | 289 | 0 | 200 | 200 | 95.5 | 41.5 | 296 | 100.9 | 40.5 | 0 |
| `tests/fixtures/issue-tracker` | 7 | 448 | yes | 1432 | 0 | 1400 | 1400 | 225.2 | 312.8 | 1571 | 264.5 | 285.2 | 0 |
| `tests/native/analyzer-binding-map` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/analyzer-clean-source` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/analyzer-error-handling` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/analyzer-event-subscription` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/analyzer-identifier-binding` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/analyzer-semantic-model` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/as-boxing` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/async-task-like` | 1 | 57 | yes | 326 | 0 | 300 | 300 | 99.2 | 174.8 | 353 | 105.3 | 161.5 | 0 |
| `tests/native/boolean-code-plan` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/char-classification` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/cli-command-contracts` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/columnar-emit-facts` | 1 | 11 | yes | 206 | 0 | 100 | 100 | 85.7 | 53.4 | 221 | 91.1 | 49.8 | 0 |
| `tests/native/completion-engine` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/conditional` | 1 | 87 | yes | 304 | 0 | 200 | 200 | 94.6 | 286.2 | 320 | 100.6 | 271.9 | 0 |
| `tests/native/construction-arrays` | 3 | 498 | yes | 583 | 0 | 500 | 500 | 118.1 | 854.2 | 644 | 124.8 | 773.3 | 0 |
| `tests/native/direct-calls` | 1 | 353 | yes | 433 | 0 | 400 | 400 | 110.3 | 815.2 | 468 | 113.0 | 754.3 | 0 |
| `tests/native/doc-query` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/erased-enum-identity` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/extension-calls` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/external-base-interface` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/generic-scope-invalid` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/interface-parameter-modifiers` | 1 | 47 | yes | 299 | 0 | 200 | 200 | 93.0 | 157.2 | 315 | 99.6 | 149.2 | 0 |
| `tests/native/iterators` | 1 | 259 | yes | 387 | 0 | 300 | 300 | 102.5 | 669.3 | 419 | 110.7 | 618.1 | 0 |
| `tests/native/lambda-placement` | 1 | 67 | yes | 381 | 0 | 300 | 300 | 102.4 | 175.9 | 413 | 115.8 | 162.2 | 0 |
| `tests/native/ownership-audit` | 2 | 1406 | yes | 868 | 0 | 800 | 800 | 133.4 | 1619.8 | 1058 | 151.8 | 1328.9 | 0 |
| `tests/native/parser-literal-facts` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/playground-diagnostic-spans` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/playground-tooling-surfaces` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/primitive-binary` | 1 | 375 | yes | 381 | 0 | 300 | 300 | 104.2 | 984.3 | 410 | 115.8 | 914.6 | 0 |
| `tests/native/query-completions` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/query-integration` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/range-index` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/readonly-dictionary-widening` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/readonly-init` | 1 | 113 | yes | 280 | 0 | 200 | 200 | 95.8 | 403.6 | 295 | 100.4 | 383.1 | 0 |
| `tests/native/record-with` | 1 | 58 | yes | 329 | 0 | 300 | 300 | 98.0 | 176.3 | 359 | 111.7 | 161.6 | 0 |
| `tests/native/reflection-emit-bootstrap` | 2 | 453 | yes | 547 | 0 | 500 | 500 | 116.2 | 828.2 | 639 | 127.8 | 708.9 | 0 |
| `tests/native/scalar-code-plan` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/systems-analysis-census` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/systems-gauntlet-facts` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |
| `tests/native/systems-proof-corpus` | 0 | 0 | n/a (no non-test sources) | — | — | — | — | — | — | — | — | — | — |

## Aggregate over the corpus

| command | scope | projects | lines | sum of median wall ms | aggregate lines/s |
|---|---|---:|---:|---:|---:|
| build | measured corpus projects | 41 | 7049 | 17099 | 412.2 |
| build | compiled (status=measured, exit 0) | 39 | 6991 | 16704 | 418.5 |
| check | measured corpus projects | 41 | 7049 | 18426 | 382.6 |
| check | compiled (status=measured, exit 0) | 39 | 6991 | 18010 | 388.2 |

- `build` per-project lines/s — median 176.3, slowest `templates/nsharp-console` at 12.8, fastest `tests/native/ownership-audit` at 1619.8 (over 41 measured project rows).
- `check` per-project lines/s — median 171.8, slowest `templates/nsharp-console` at 12.2, fastest `tests/native/ownership-audit` at 1328.9 (over 41 measured project rows).

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

**`src/NSharpLang.Compiler.BootstrapServices`** (`build`) — exit 1 on run 1

```
\x1b[1;31merror\x1b[0m \x1b[1mNL012\x1b[0m: Parameter 'name' in 'ParseTypeBody' is never read — is it needed?
  \x1b[1;36m-->\x1b[0m /private/tmp/nsharp-compile-bench/src/NSharpLang.Compiler.BootstrapServices/ColumnarParserRecovery.nl:1486:24
   \x1b[1;36m|\x1b[0m
\x1b[1;36m1486 |\x1b[0m     func ParseTypeBody(name: string, typeBodyDiagnosticSpan: RecoverySpan): List<Declaration> {
   \x1b[1;36m|\x1b[0m                        \x1b[1;31m^^^^\x1b[0m
   \x1b[1;36m|\x1b[0m
\x1b[1;32mhelp\x1b[0m: If the parameter is required by an interface or override, prefix with '_' to suppress this: '_name'

\x1b[1;31merror\x1b[0m \x1b[1mNL011\x1b[0m: This catch block is empty — exceptions will be silently swallowed
  \x1b[1;36m-->\x1b[0m /private/tmp/nsharp-compile-bench/src/NSharpLang.Compiler.BootstrapServices/EnvCommand.nl:74:11
   \x1b[1;36m|\x1b[0m
\x1b[1;36m 74 |\x1b[0m         } catch {
   \x1b[1;36m|\x1b[0m           \x1b[1;31m^^^^^\x1b[0m
   \x1b[1;36m|\x1b[0m
\x1b[1;32mhelp\x1b[0m: Log the error, handle it, or add a comment explaining why it's safe to ignore

\x1b[1;31merror\x1b[0m \x1b[1mNL011\x1b[0m: This catch block is empty — exceptions will be silently swallowed
  \x1b[1;36m-->\x1b[0m /private/tmp/nsharp-compile-bench/src/NSharpLang.Compiler.BootstrapServices/EnvCommand.nl:136:11
   \x1b[1;36m|\x1b[0m
\x1b[1;36m136 |\x1b[0m         } catch {
   \x1b[1;36m|\x1b[0m           \x1b[1;31m^^^^^\x1b[0m
   \x1b[1;36m|\x1b[0m
\x1b[1;32mhelp\x1b[0m: Log the error, handle it, or add a comment explaining why it's safe to ignore

\x1b[1;31merror\x1b[0m \x1b[1mNL011\x1b[0m: This catch bloc …
```

**`src/NSharpLang.Compiler.BootstrapServices`** (`check`) — exit 1 on run 1

Diagnostic census from the `nlc check --json` envelope: 243 results: NL202 ×85, NL402 ×65, NL905 ×26, NL012 ×20, NL011 ×17, NL301 ×16, NL010 ×7, NL303 ×3, NL412 ×3, NL002 ×1

```
(the command wrote nothing to stderr; its diagnostics are in the JSON envelope on stdout)
```

**`templates/nsharp-systems-cli`** (`build`) — exit 1 on run 1

```
\x1b[2m-- FUNCTION CALL ERROR --------------------------------------------------\x1b[0m  /private/tmp/nsharp-compile-bench/templates/nsharp-systems-cli/Program.nl

I cannot find an overload of `Slice` that matches this call:

\x1b[1;36m16|\x1b[0m         return Ok(BinaryPrimitives.ReadUInt32LittleEndian(buf.Slice(0, 4)))
\x1b[1;36m                                                                ^^^^^\x1b[0m

Hint: This call passes 2 arguments: `uint`, `uint`.
Available overloads:
  - Slice(int start): ReadOnlySpan<byte>
  - Slice(int start, int length): ReadOnlySpan<byte>

Check the argument count and types. If you meant to reference the method itself, use it in a context with a delegate type instead of calling it.

\x1b[1;36mRead more:\x1b[0m https://docs.n-sharp.dev/errors/NL402

\x1b[2m-- FUNCTION CALL ERROR --------------------------------------------------\x1b[0m  /private/tmp/nsharp-compile-bench/templates/nsharp-systems-cli/Program.nl

I cannot find an overload of `Slice` that matches this call:

\x1b[1;36m16|\x1b[0m         return Ok(BinaryPrimitives.ReadUInt32LittleEndian(buf.Slice(0, 4)))
\x1b[1;36m                                                                ^^^^^\x1b[0m

Hint: This call passes 2 arguments: `uint`, `uint`.
Available overloads:
  - Slice(int start): ReadOnlySpan<byte>
  - Slice(int start, int length): ReadOnlySpan<byte>

Check the argument count and types. If you meant to reference the method itself, use it in a context with a delegate type instead of calling it.

\x1b[1;36mRead more:\x1b[0m https://docs.n-sharp.dev/errors/NL402

\x1b[2m-- WARNIN …
```

**`templates/nsharp-systems-cli`** (`check`) — exit 1 on run 1

Diagnostic census from the `nlc check --json` envelope: 2 results: NL402 ×1, NSYS050 ×1

```
(the command wrote nothing to stderr; its diagnostics are in the JSON envelope on stdout)
```

**`templates/nsharp-systems-lib`** (`build`) — exit 1 on run 1

```
\x1b[2m-- FUNCTION CALL ERROR --------------------------------------------------\x1b[0m  /private/tmp/nsharp-compile-bench/templates/nsharp-systems-lib/PacketCore.nl

I cannot find an overload of `Slice` that matches this call:

\x1b[1;36m16|\x1b[0m         return Ok(BinaryPrimitives.ReadUInt32LittleEndian(buf.Slice(0, 4)))
\x1b[1;36m                                                                ^^^^^\x1b[0m

Hint: This call passes 2 arguments: `uint`, `uint`.
Available overloads:
  - Slice(int start): ReadOnlySpan<byte>
  - Slice(int start, int length): ReadOnlySpan<byte>

Check the argument count and types. If you meant to reference the method itself, use it in a context with a delegate type instead of calling it.

\x1b[1;36mRead more:\x1b[0m https://docs.n-sharp.dev/errors/NL402

\x1b[2m-- FUNCTION CALL ERROR --------------------------------------------------\x1b[0m  /private/tmp/nsharp-compile-bench/templates/nsharp-systems-lib/PacketCore.nl

I cannot find an overload of `Slice` that matches this call:

\x1b[1;36m16|\x1b[0m         return Ok(BinaryPrimitives.ReadUInt32LittleEndian(buf.Slice(0, 4)))
\x1b[1;36m                                                                ^^^^^\x1b[0m

Hint: This call passes 2 arguments: `uint`, `uint`.
Available overloads:
  - Slice(int start): ReadOnlySpan<byte>
  - Slice(int start, int length): ReadOnlySpan<byte>

Check the argument count and types. If you meant to reference the method itself, use it in a context with a delegate type instead of calling it.

\x1b[1;36mRead more:\x1b[0m https://docs.n-sharp.dev/errors/NL402
```

**`templates/nsharp-systems-lib`** (`check`) — exit 1 on run 1

Diagnostic census from the `nlc check --json` envelope: 1 results: NL402 ×1

```
(the command wrote nothing to stderr; its diagnostics are in the JSON envelope on stdout)
```


## File-count cross-check against the live compiler

_Every project whose `nlc check --json` envelope carried `checkedFiles` agreed with the
replicated selection rule._

## Repository tree after the sweep

_Every measured project directory was byte-identical before and after every build._

