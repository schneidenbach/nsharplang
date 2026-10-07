# N# CLI Toolchain (`nlc`)

**Status:** Active pre-release CLI with code intelligence, auto-fix, and daemon mode. Verify release claims with current help/completion output and test logs.
**Test count:** Do not hard-code; run `./scripts/dev.sh --estate` (the compiler-service estate) plus `nlc test --project tests/native/<dir>` for the native projects, or `./scripts/test-all.sh`, for current evidence. There is no C# unit suite — `tests/*.cs` and `tests/Tests.csproj` are retired.

The `nlc` CLI is designed for two audiences: humans at a terminal and LLMs navigating code via bash. `nlc query`, `nlc check`, `nlc fix`, and `nlc lint` all output structured JSON by default with a versioned envelope. `check`, `fix`, and `lint` use `ok`/`error` at the top level; query failures use the same structured error envelope. Add `--text` for human-readable output. `nlc --version` prints the installed version.

The executable toolchain is now IL-only:
- `il` — emit IL directly to a managed assembly

`project.yml` supports `backend: il`; when omitted, IL is the default. The CLI honors that setting for `check`, `build`, `run`, `test`, `publish`, and `pack` through the native project.yml build path. The MSBuild SDK remains available for direct `dotnet build`, `dotnet run`, and `dotnet test` compatibility when a host tool needs a `.csproj`.

CLI command decision kernels live in `NSharpLang.Compiler.Core` and are statically
referenced by the CLI. Do not add product-path `Assembly.Load` or delegate-reflection binding for
compiler-service kernels. New kernel shapes must compile under the pinned stage-0 SDK; repin with
`./scripts/setup-local.sh` before relying on tip-only language/backend support inside kernels.

---

## Internal failures and exit status

A command normally exits `0` on success or `1` for a diagnostic, invalid request, or command failure.
An unexpected exception escaping command dispatch exits **`2`** and prints **NL924** to stderr.
The N# `InternalErrorBoundary` preserves the exception's invariant sentence and concrete type, explains
that the failure is a bug in N#, and links to the reporting instructions. It does not print a stack
trace or invent a source span. A known file may prefix the diagnostic; the process entry point has
only arguments and supplies no file.

This process-level failure uses the same plain stderr diagnostic for text and JSON requests. It
leaves stdout untouched, including any output already written; it does not invent a JSON envelope
or a new schema version. Consumers must check exit status before treating stdout as a complete
command response. Existing command-local catches still return their documented diagnostics and
exit status `1`; this boundary handles exceptions that escape those handlers.

`nlc run` forwards the launched program's exit status, including `2`. In that case the number alone
does not identify an internal compiler failure: NL924 on stderr supplies that distinction.

**Exit status 134 was a fourth case and is now gone.** A source whose expressions nested past what
the toolchain reads — a generated file of 2,000 parentheses, 2,000 lambdas or an 8,000-term operator
chain — exhausted the CLR stack, and `check`, `build`, `lint` and `format` all died with a bare
`Stack overflow.` and SIGABRT. The parser now bounds expression nesting at 512 levels and reports
**NL111** with a file and a position; every command refuses such a file instead of crashing.
`ColumnarParserRecovery.MaxExpressionNestingDepth` holds the number and the measurements behind it.
`LinterWalk.MaxRecursionDepth` (1,000 frames) remains as the walkers' own backstop.

## Command Reference

### Build & Run

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc build` | Compile project through the IL backend | `nlc build` |
| `nlc build <file>` | Compile single file | `nlc build Program.nl` |
| `nlc build --backend il` | Compile with the direct IL backend | `nlc build --backend il` |
| `nlc build --release` | Build with Release configuration/output layout | `nlc build --release` |
| `nlc build --verbose` | Build with detailed native resolver/test output | `nlc build --verbose` |
| `nlc build --timings` | Print, to stderr, the `Build timings:` block (resolve, emit, total) and then a `Phase timings:` block: one row per compiled project (project references included) and phase -- `load-references`, `parse`, `import-graph`, `analysis`, `systems-policy`, `lint`, `emit.parse`, `emit.codegen`, `emit.write` -- with wall ms, process CPU ms (all threads, so CPU above wall is that phase's parallelism) and process allocation MB. Owner: `CompilerPhaseTimings` (Compiler.Model); printed on failed builds too | `nlc build --timings` |
| `nlc build --perf-report` | Emit a versioned JSON perf report (allocations, dispatch, AOT blockers) | `nlc build --perf-report` |
| `nlc build\|check\|test --stats[=<path>]` | One `nsharp.cli-stats` v1 JSON line: wall/CPU time and the structural work counters (files parsed and analyzed, assemblies emitted, reference images loaded, framework-reference bytes hashed, processes spawned) — see [`--stats`](#--stats--what-one-command-cost) | `nlc check --stats` |
| `nlc build --aot` | Native AOT safety analysis; AOT blockers (reflection/dynamic code/runtime generics/expression trees) become build errors | `nlc build --aot` |
| `nlc run` | Compile and run project through the IL backend | `nlc run` |
| `nlc run <file>` | Compile and run single file | `nlc run Program.nl` |
| `nlc run --backend il` | Build and run via the direct IL backend | `nlc run --backend il` |
| `nlc publish` | Publish portable framework-dependent artifacts | `nlc publish --output ./dist` |
| `nlc publish --runtime <current-rid>` | Add a framework-dependent launcher for the current host runtime only | `nlc publish --runtime osx-arm64 --output ./dist` |
| `nlc publish --self-contained` | Unsupported/planned; exits 1 with guidance | `nlc publish --self-contained` |
| `nlc publish --aot` | Analysis-only: verify Native AOT safety (fails on blockers) and annotate public APIs; no native image yet | `nlc publish --aot` |
| `nlc publish --backend il` | Publish with the IL backend | `nlc publish --backend il --output ./dist` |
| `nlc clean` | Remove build artifacts (`bin/`, `obj/`, `.nlc/`) | `nlc clean` |
| `nlc clean --all` | Also clear NuGet caches | `nlc clean --all` |
| `nlc watch <check\|build\|test\|lint\|format>` | Re-run a command on file changes | `nlc watch check` |
| `nlc check` | Fast type-check + backend verification (JSON by default) | `nlc check` |
| `nlc check --backend il` | Verify semantic analysis plus direct IL emission | `nlc check --backend il` |
| `nlc check --aot` | Type-check plus Native AOT safety gate (AOT blockers become errors) | `nlc check --aot` |
| `nlc check --use-built-references` | Check the project against each `project:` dependency's BUILT assembly (`bin/Debug/<framework>`, what `nlc build` or `dotnet build` of that project wrote), transitively, instead of compiling it from source -- the `cargo check`/`go vet` shape over already-compiled dependencies. Nothing is compiled or written for a dependency; one that was never built, or whose product sources (`project.yml` and non-`.tests.nl` `.nl` files) are newer than its assembly, is an error naming it. Owner: `ReferenceResolutionOptions.UseBuiltProjectReferences` in the resolver; pinned by Driver's `CompilationReferenceResolver.tests.nl` and `tests/native/cli-command-contracts`. The self-host front door (Step 2d) checks every compiler project this way | `nlc check --use-built-references --project src/App` |
| `nlc check --systems-report` | Emit the versioned Systems N# policy/effect report. Callee findings are semantically resolved: each call binds to the declaration the Analyzer resolved at that call site (overload-, receiver-, and file-aware); a hot-path call that resolves to no declaration and no BCL/HotSummary fact reports NSYS050, never silence | `nlc check --systems-report` |
| `nlc fix` | Auto-apply compiler suggestions (JSON by default) | `nlc fix` |

### Code Intelligence (`nlc query`)

All query commands output **JSON by default** with a versioned envelope (`schemaVersion: 1`). Add `--text` for human-readable output. When a workspace server of the same `nlc` build is already running (one starts automatically on the first `check`/`build`/`test`/...; see [Workspace Server](#workspace-server-daemon-first-cli)), JSON query commands reuse it for any project in its workspace; add `--no-daemon` to force in-process analysis.

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc query symbols` | List all symbols in project | `nlc query symbols` |
| `nlc query symbols --file F` | Symbols in one file | `nlc query symbols --file Program.nl` |
| `nlc query symbols --kind K` | Filter by kind | `nlc query symbols --kind function` |
| `nlc query symbols --filter P` | Filter by glob or substring | `nlc query symbols --filter '*Person*'` |
| `nlc query outline <file>` | File structure (imports, declarations) | `nlc query outline Program.nl` |
| `nlc query ast` | Full parsed AST as stable, node-typed JSON (whole project) | `nlc query ast` |
| `nlc query ast --file F` | AST for one file | `nlc query ast --file Program.nl` |
| `nlc query diagnostics` | Errors/warnings with Elm-level context | `nlc query diagnostics` |
| `nlc query diagnostics --text` | Elm-style terminal output | `nlc query diagnostics --text` |
| `nlc query batch --requests requests.json` | Execute multiple semantic queries in one JSON response | `nlc query batch --requests requests.json` |
| `nlc query type --file F --pos L:C` | Type info at position | `nlc query type --file Program.nl --pos 5:4` |
| `nlc query inspect --file F --pos L:C` | One-shot symbol/type/definition/refs/completions bundle | `nlc query inspect --file Program.nl --pos 5:4` |
| `nlc query inspect --summary --file F --pos L:C` | Compact envelope for tooling that only needs the high-level inspection summary | `nlc query inspect --summary --file Program.nl --pos 85:22` |
| `nlc query def --file F --pos L:C` | Definition at position (semantic) | `nlc query def --file Program.nl --pos 5:12` |
| `nlc query def --name N` | Public definitions matching an exact symbol name | `nlc query def --name Point` |
| `nlc query refs --file F --pos L:C` | All references to symbol | `nlc query refs --file Program.nl --pos 5:12` |
| `nlc query completions --file F --pos L:C` | Completions at position | `nlc query completions --file Program.nl --pos 5:12` |
| `nlc query hover --file F --pos L:C` | Signature + docs at position (shared model with LSP) | `nlc query hover --file Program.nl --pos 5:6` |
| `nlc query doc <name>` | .NET API documentation for a type or member, from the reference packs' XML | `nlc query doc Console.WriteLine` |
| `nlc query call-graph --function N` | Callers and callees of a function | `nlc query call-graph --function Main` |
| `nlc query call-graph` | All call edges in the project (--limit N, default 100) | `nlc query call-graph --limit 50` |
| `nlc query implementors --name I` | Concrete types implementing an interface (by name) | `nlc query implementors --name IShape` |
| `nlc query implementors --file F --pos L:C` | Implementors of the interface at a position | `nlc query implementors --file Program.nl --pos 10:11` |
| `nlc query perf --file F --pos L:C` | Performance facts plus Systems N# effect findings at a position | `nlc query perf --file Program.nl --pos 5:12` |
| `nlc query trusted` | Governed Systems N# `[trusted]` wrappers and metadata | `nlc query trusted` |

Type-use positions are first-class semantic navigation targets. `type`, `inspect`, `def`, `refs`, and `hover` resolve annotations and type arguments through the same BindingMap/SemanticModel data used by the LSP, including `Person`, `List<Person>`, `Person?`, `Person[]`, and `Func<Person, string>`. Duplicate simple type names in different namespaces/files are resolved by semantic binding, not text search.

`nlc query def --name N` is the non-positional fallback for LLM discovery and scripts. It searches the public symbol outline by exact name, returns a stable `definition` envelope with `query`, `results`, and `note`, and exits 1 when there is no public match. Prefer `--file/--pos` when a cursor location is available because that path is fully semantic.

`nlc query type` and `nlc query inspect` type results include `nullability` (`unknown`, `null`, `maybeNull`, `notNull`, or `oblivious`) so CLI automation and the LSP can reason about the same null-flow facts.

At a position on a member that METADATA declares and the project does not — `list.ToArray()`, `DateTime.Now.AddDays(1)` — a `method` result's `resolvedType` carries the member's full **signature** (`WeatherForecast[] ToArray()`), rendered by the same N# owner `nlc query hover` uses, so the two commands answer the same fact and `hover`'s `signature` is exactly `kind + " " + name + ": " + resolvedType`. It previously carried the analyzer's internal diagnostic placeholder `ToArray(...)`, which names no type at all. Four surfaces move together because they share one builder: `nlc query type`, the `type` block of `nlc query inspect`, `nlc query inspect --summary`, and the `--text` rendering of each. This is **not** a schema change and `schemaVersion` stays `1`: no key is added, removed or retyped, and the only values that move are the ones that were a placeholder. Every other kind — a property, a field, a local, a type use — still answers with its TYPE and is untouched.

### Code Quality

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc format` | Format all .nl files | `nlc format` |
| `nlc format <files>` | Format specific files | `nlc format Program.nl` |
| `nlc format --check` | Exit 1 if formatting would change files | `nlc format --check` |
| `nlc format --diff` | Print unified diffs without writing files | `nlc format --diff` |
| `nlc format --stdin` | Format stdin to stdout | `nlc format --stdin < Program.nl` |
| `nlc lint` | Static analysis diagnostics (JSON by default) | `nlc lint` |
| `nlc lint <files>` | Lint specific files | `nlc lint Program.nl` |
| `nlc lint --json` | JSON output with structured envelope | `nlc lint --json` |
| `nlc lint --text` | Human-readable diagnostics | `nlc lint --text` |
| `nlc lint --project <dir>` | Lint a specific project | `nlc lint --project examples/17-issue-tracker/backend` |
| `nlc test` | Run .tests.nl files with the xUnit-backed N# test runner | `nlc test` |
| `nlc test --filter <name>` | Run a subset of tests | `nlc test --filter AddPerson` |
| `nlc test --verbose` | Show individual test results | `nlc test --verbose` |
| `nlc test --timings` | Report build, run and total time (stderr, or a `timings` object in `--json`) | `nlc test --json --timings` |
| `nlc test --stats[=<path>]` | The `nsharp.cli-stats` v1 line for the whole test command (build included) | `nlc test --stats=/tmp/s.json` |
| `nlc test --coverage` | Unsupported/planned native coverage; exits 1 with text or JSON guidance | `nlc test --coverage --json` |

### Project Management

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc new <name>` | Create new N# project | `nlc new MyApp` |
| `nlc new systems-cli <name>` | Create a systems-profile console app with strict policy, hot parser, boundary, warmup, and systems tests | `nlc new systems-cli PacketTool` |
| `nlc new systems-lib <name>` | Create a systems-profile library with a public hot API, boundary adapter, warmup, and systems tests | `nlc new systems-lib PacketCore` |
| `nlc new <name> --template console --systems` | Systems-profile console app via template flag | `nlc new PacketTool --template console --systems` |
| `nlc new <name> --template library --systems` | Systems-profile library via template flag | `nlc new PacketCore --template library --systems` |
| `nlc pack` | Generate a NuGet package from project.yml metadata | `nlc pack` |
| `nlc pack --version <ver>` | Override package version | `nlc pack --version 2.0.0` |
| `nlc pack --output <dir>` | Specify output directory for .nupkg | `nlc pack --output ./artifacts` |
| `nlc pack --include-symbols` | Also produce a .snupkg symbols package | `nlc pack --include-symbols` |
| `nlc doc` | Generate project API documentation | `nlc doc` |
| `nlc doc --json` | Emit a structured doc-generation result | `nlc doc --json` |
| `nlc completion <shell>` | Generate shell completions | `nlc completion zsh` |
| `nlc daemon start` | Start the workspace server explicitly (routed commands start it on first use anyway) | `nlc daemon start` |
| `nlc daemon stop` | Stop the workspace server | `nlc daemon stop` |
| `nlc daemon status` | Show pid, uptime, build identity, requests, memory, warm state | `nlc daemon status` |
| `nlc tree` | Show direct dependency tree from `project.yml`; include transitive NuGet packages when MSBuild can resolve the package graph | `nlc tree --json` |

### Public Browser Playground

The public website hosts the browser workbench, not a CLI command. `/playground` is a free-form sample explorer with Monaco syntax highlighting, browser diagnostics, formatting, completions, hover, file tabs, share links, and bounded browser-subset `Run` output. `/tutorial` uses the same workbench for a guided story with gated exercises.

Browser `Run` intentionally supports tutorial-scale code only: functions, `print`, simple control flow, records/classes, object initializers, selected string/numeric helpers, and selected match patterns. Use the local `nlc` toolchain for full CLR execution, build, test execution, NuGet restore, filesystem workflows, and editor integration.

---

## Key Commands In Detail

### `nlc check` — Fast Type-Check

The N# equivalent of `cargo check`. Parses and analyzes first, then validates IL emission in memory: it writes no assembly, scratch directory or reference assembly. The tightest feedback loop for development.

```bash
$ nlc check
{
  "schemaVersion": 1,
  "command": "check",
  "ok": true,
  "checkedFiles": 3,
  "projectRoot": "/abs/path/to/project",
  "results": [],
  "summary": { "errors": 0, "warnings": 0, "info": 0 }
}

$ nlc check --text   # with errors
── [NL301] ERROR ──────────────────── Program.nl:2:10 ──
    2 |     x := unknownVar
      |          ^
Undefined identifier 'unknownVar'
```

- **`check` reads `*.tests.nl`.** It loads the same file list `nlc test` compiles — sources plus test
  files — through `CodeIntelligenceService.LoadProjectIncludingTests`, and resolves the test
  references so a `test` block's lowering verifies under check's IL pass exactly as it does under
  `nlc test`. Before this, a project made of test files answered `checkedFiles: 0` with `ok: true`
  while `nlc test` on the same directory stopped at the first lint error in them. `nlc build`,
  `nlc lint` and the LSP are unchanged and still read sources only. **No schema change:** the test
  files are counted in the existing `checkedFiles` and their diagnostics arrive in the existing
  `results`, so `schemaVersion` stays 1.
- **A root containing nested project roots checks them as a workspace.** `nlc check` discovers every
  nested `project.yml`, assigns each `.nl` file to its nearest project root, applies that project's
  `exclude` rules, and checks every member as its own program. Files owned by the requested root are
  checked as the root program too. Discovery and source walking skip `bin/`, `obj/`, `.git/`, nested
  Git worktrees, `node_modules/` and `bootstrap/`. Member project-reference graphs are resolved into
  one shared context before bounded concurrent member analysis; this avoids incomplete external
  member views during concurrent reference loads. Text output groups diagnostics by project. JSON workspace output uses
  `schemaVersion: 2`: the top-level `projects` array contains each project's `projectRoot`,
  `checkedFiles`, `ok`, `results` and `summary`, with an optional `error` for a failed project and an
  optional `systemsReport` when requested; top-level `checkedFiles` and `summary` aggregate the
  members, and `summary.projectFailures` counts project-level failures that returned an `error`
  instead of diagnostics (for example, invalid project configuration or an unresolved reference).
  A source claimed by multiple projects is a configuration conflict and returns the normal version-1
  error envelope. Single project checks retain their existing `schemaVersion: 1` shape.
- The repository-root workspace contract in `tests/native/cli-command-contracts` reads both this
  envelope and `--stats`. It discovers member roots and source ownership at test time using the
  workspace walk's directory skips, nearest-project ownership, and each member's `exclude` list;
  every JSON member must appear exactly once and its `checkedFiles` must equal that filesystem
  census. It requires at least one parse event per checked file and caps parse events at three per
  file (the rounded-up measured ratio, including the 5,352-event gate observation). Reference-image
  opens use a dependency-derived budget instead of a global per-member constant: the test measures
  the shared surface with an empty member, then reads each member's `project.yml`, selected
  `project.assets.json` target when present, and transitive project/NuGet references. Without
  restored assets it follows the declared package versions and the target-framework-compatible
  package assets. Assembly identities are deduplicated per member. The budget is the empty-member
  surface times the discovered member count, plus up to six opens for each resolved member reference
  (four analyzer workers, emit and exact-identity runtime contexts). This lets the ratchet account for references
  that exist only in built outputs or restored assets while keeping the allowance tied to what each
  member actually uses. Absolute repo-wide member/file counts are not pinned.

  Reference counts vary with generated outputs because `AnalyzerReferenceLoadOrchestration` prefers
  a locally built `bin/Debug/<targetFramework>` package assembly and project references load their
  built output; when those files are absent it resolves package assemblies from the NuGet cache.
  `obj/project.assets.json` also pins the restored package versions when available, while an
  unrestored project falls back to the installed package version. At `d912a77ca`, the clean state
  measured 18,284 opens and the fully built `examples/` + `src/` state measured 18,598, identically
  across three runs in each state. The full-built increase is 314 opens, explained by the different
  local output and restored-version reference set; both states pass the computed budget. Since
  `d4f10f232`, member reference graphs are resolved before concurrent analysis to avoid the shared
  metadata-reference race.
  Earlier fresh worktree/copy runs measured 18,184 opens for 223 members / 1,991 checked files.
  The reported 5,352-event parse result was not reproduced; it does not point to counter
  nondeterminism or a source-inventory difference in that earlier reproduction.
  Its separate 128 s wall budget (the measured ~64 s check × 2) is judged only below one fifth of
  logical cores (2.0 on the 10-core measurement host); unknown or higher load records timing as
  unjudged. Workspace completeness, parse counts and the dependency-derived reference-image budget
  always gate. The separate 15-minute timeout is only a hang detector.
- Exit code 0 = clean, 1 = errors
- Near-zero-warnings policy: correctness/safety/hygiene diagnostics are build-blocking errors, so a clean `nlc check` (`ok: true`, exit 0) is a strong guarantee rather than "clean modulo warnings." `summary.warnings` is reported but is expected to stay at 0 for well-formed code; pure style is handled by `nlc format`, not surfaced here.
- JSON by default, `--text` for Elm-style diagnostics
- `results[].line`, `results[].column`, and `results[].length` are the canonical marker span for both compiler and linter diagnostics; linter results no longer use one-character placeholder lengths.
- Always runs parse + analysis first, then:
  - `il` backend (default): when the analysis is clean, validates the direct backend's emission IN
    MEMORY (`MultiFileCompiler.ValidateAnalyzedEmission`) and writes nothing.
- **Why a check still runs the IL back end.** One class of diagnostic exists nowhere but in the code
  generator: NL103, a program the analysis accepts and the back end refuses
  (`ColumnarEmissionDiagnostics`). The refusals are decided while the back end walks every body (the
  planners that choose an instruction sequence are the code that hands it to the `ILGenerator`, and
  the image's metadata serialisation can refuse it last), so no cheaper pass can answer them without
  being a second code generator. The repository corpus carries six of them under `nlc check`
  (`examples/14-minimal-api`, `examples/17-issue-tracker/backend`, `templates/nsharp-webapi`,
  `tests/fixtures/issue-tracker` and two census projects at the repository-root workspace check), so
  skipping the walk would turn real failures into `ok: true`. Measured on the agent-loop `large`
  project (80,960 lines): metadata generation and PE serialisation are ~20 ms of a ~1.5 s walk, so the
  walk itself is the cost and the image's write was never the part worth removing; what the check no
  longer does is create a scratch directory, write the image and count it (`--stats`
  `assembliesEmitted` is 0 for a check). The validated image stays on the compiler
  (`MultiFileCompiler.EmittedImage`). The repository-root workspace check's JSON was byte-identical
  before and after (225 members, 175 errors, 162 warnings, six NL103).
- **One analysis per file per check.** The emission proof uses the compiler that produced the
  diagnostics (`MultiFileCompiler.ValidateAnalyzedEmission`); it used to hand the project to a second
  compiler that parsed, analysed and loaded the reference closure again. On
  `tests/fixtures/issue-tracker` (8 files) `--stats` went from 40 parses / 16 analyses / 684
  reference loads to 16 / 8 / 501, and to 8 / 8 / 501 once the driver's parses were handed to the
  analyzer. What remains per file: ONE parse, shared — the driver parses the text, and when
  preprocessing changed nothing that parse (unit and syntax errors) seeds every analyzer of the
  compilation (`Analyzer.SeedProjectParses`), which serves cross-file declaration lookup and file
  imports (`TryGetProjectParse`) — plus the emitter's own columnar parse. Sharing declarations across
  files is safe because analysis writes nothing another file's analysis reads: the one such write,
  a body's nullable-return provenance, lives per analysis in `AnalyzerFunctionTypeFactory`
  (`RecordBodyReturnType`), not on the declaration (it used to, and once declarations were shared it
  made cross-file diagnostics depend on analysis order). The analyzer's metadata context and the
  emitter's are still separate loads of the same reference set (the larger share of
  `referenceAssembliesLoaded`).

### `--stats` — What One Command Cost

`nlc build`, `nlc check` and `nlc test` accept `--stats` (one JSON line, the LAST line on stderr) or
`--stats=<path>` (the same line written to that file, so a caller that captures the command's own
stderr does not have to parse around diagnostics). Stdout is never touched: `check`'s envelope and
`test --json` stay exactly their documented schemas. Any other command refuses the flag by name, and
a `--stats` after `--` belongs to the program, not to `nlc`.

```json
{"schema":"nsharp.cli-stats","schemaVersion":1,"command":"check","exitCode":0,"wallMs":727,"cpuMs":746,
 "counters":{"filesParsed":8,"emitParses":8,"filesAnalyzed":8,"assembliesEmitted":1,"referenceAssembliesLoaded":501,"frameworkReferenceBytesHashed":0,"processesSpawned":0},
 "phases":[{"project":"IssueTracker","phase":"parse","wallMs":22,"cpuMs":22,"allocatedBytes":1025064,"calls":1},
           {"project":"IssueTracker","phase":"import-graph","wallMs":1,"cpuMs":1,"allocatedBytes":8200,"calls":1},
           {"project":"IssueTracker","phase":"load-references","wallMs":40,"cpuMs":41,"allocatedBytes":23406936,"calls":1}, …]}
```

ONE LINE, TWO OWNERS BEHIND IT: the `counters` are `CompilerWorkCounters`' (how much work — exact,
load-independent, the agent-loop gate's subject) and the `phases` are `CompilerPhaseTimings`' (where
the time went — the same rows `nlc build --timings` prints under `Phase timings:`). `--stats` turns
the phase ledger on for its command. `phases` was added to version 1 as an optional field (omitted
when nothing was recorded), which the version's own compatibility rule allows; no existing field
changed.

| Field | Meaning |
|---|---|
| `schema`, `schemaVersion` | `nsharp.cli-stats`, `1`. Adding a field is compatible; renaming or retyping one is a new version |
| `command`, `exitCode` | The command measured and the exit code it returned |
| `wallMs` | In-process time from dispatch to completion. Excludes .NET host start-up; measure the process from outside for the whole wall |
| `cpuMs` | The CLI process's total CPU (user + system), start-up included |
| `peakWorkingSetBytes` | The process's peak working set; OMITTED where the platform does not report it (macOS) |
| `counters.filesParsed` | Source files parsed into the analyzer's syntax tree (`ColumnarParserRecovery.Run`). The same file parsed twice counts twice — that is the point |
| `counters.emitParses` | Source files tokenized and parsed by the columnar IL pipeline (`ColumnarProgramInputBuilder`) |
| `counters.filesAnalyzed` | Compilation units through `Analyzer.Analyze` |
| `counters.assembliesEmitted` | IL images written by the columnar emitter (a reference assembly beside one is not counted) |
| `counters.referenceAssembliesLoaded` | Reference images opened from a path: MetadataLoadContext loads plus exact-identity executable loads; one file in two contexts counts twice |
| `counters.frameworkReferenceBytesHashed` | Bytes read and SHA-256 hashed from installed `shared/` framework or `packs/` reference assemblies while validating incremental build inputs; an up-to-date build must report zero |
| `counters.processesSpawned` | Child processes this process started (`DotnetRunner`, the daemon launcher) |
| `phases[]` | Optional. One row per (project, phase) the command compiled — `load-references`, `parse`, `import-graph`, `analysis`, `systems-policy`, `lint`, `emit.parse`, `emit.codegen`, `emit.write` — with `wallMs`, `cpuMs` (process CPU across all threads, so CPU above wall is that phase's parallelism), `allocatedBytes` and `calls` (repeated rows folded). Wall-clock data: never gated |

The counters are always on (`CompilerWorkCounters` in `src/NSharpLang.Compiler.Model`, one atomic
increment per event) and process-wide; `--stats` reports the difference across the command. They do
not move with machine load, so they explain a latency change where a wall clock cannot: on
2026-10-05 a no-op `nlc check` of the 448-line issue-tracker fixture parsed its 8 files **40** times,
analyzed them twice and opened **684** reference images. A command routed through the daemon must
report the daemon's work for the request in these counters (snapshot before and after,
`CompilerWorkCounterSnapshot.Since`), or the numbers would claim the work vanished. It does: a routed
command carries `--stats` to the workspace server, whose `CliPipeline.ExecuteLocal` takes the
before/after snapshot around the request (one request runs at a time, so the delta is that
request's), writes the line to the client's stderr or to the `--stats=<path>` file (resolved in the
client's working directory), and reports `cpuMs` as the request's CPU delta rather than the server's
lifetime total. `peakWorkingSetBytes` is then the SERVER's peak; time the client process for the
client's own. The server resets the phase ledger around every request, so a routed `--stats` or
`--timings` reports its own phases and never an earlier client's. A warm server opens fewer reference images per command (measured on the small agent-loop
project: no-op `check` 684 → 540, `build` 497 → 356, `test` 505 → 361), because executable reference
handles loaded once stay loaded.

The agent-loop benchmark gates these counters exactly over the edit → check/build/test loop; see
`memory/testing.md` §8a.

### Backend Selection

Supported backend values:
- `il` — emit IL directly and continue through the selected CLI or SDK/MSBuild flow

Current status:
- `project.yml` backend selection is respected by both the CLI and the MSBuild SDK.
- `nlc check/build/run/test/publish/pack` all support `backend: il` through the native project.yml path.
- `dotnet build`, `dotnet run`, and `dotnet test` work for IL-backed SDK projects.

### `nlc fix` — Auto-Apply Suggestions

The N# equivalent of `cargo clippy --fix`. Reads diagnostics, finds available code fixes, and applies them to source files.

**Safety contract** — `nlc fix` never applies destructive edits by default:
- **Default (no flags):** applies only `Safe`-level fixes
- **`--include-review-needed`:** also applies `ReviewNeeded` fixes (e.g. unused import removal, unused variable removal)
- **`SuggestionOnly`:** never written to files — reported in `results` only

```bash
$ nlc fix
{
  "schemaVersion": 2,
  "command": "fix",
  "ok": true,
  "dryRun": false,
  "includeReviewNeeded": false,
  "projectRoot": "/abs/path/to/project",
  "filesModified": 1,
  "results": [
    { "file": "Program.nl", "diagnostic": "NL002", "title": "Add import System.Text", "safety": "safe", "edits": [...] },
    { "file": "Program.nl", "diagnostic": "NL010", "title": "Remove unused import", "safety": "reviewNeeded", "edits": [...] }
  ],
  "fixesApplied": [
    { "file": "Program.nl", "diagnostic": "NL002", "title": "Add import System.Text", "safety": "safe", "edits": [...] }
  ]
}

$ nlc fix --text
Fixed 1 issue in 1 file:
  Program.nl:
    [NL002] Add import System.Text

Skipped 1 fix:
  [NL010] Remove unused import (requires --include-review-needed flag)

$ nlc fix --include-review-needed   # also applies ReviewNeeded fixes
$ nlc fix --dry-run                 # preview without applying; exits 1 if fixes are available
$ nlc fix --file F                  # fix single file
```

**`results` vs `fixesApplied`:**
- `results` — every discovered fix regardless of safety level
- `fixesApplied` — only fixes that passed the safety gate and were (or would be) written to disk

**Built-in lint rules:**

N# is near-zero-warnings: every active linter rule is a build-blocking **error**. Pure-style rules have been deleted and folded into `nlc format`.

| Code | Severity | Name | Description |
|------|----------|------|-------------|
| NL001 | Error | `unused-variable` | Local variable declared but never read |
| NL002 | Error | `missing-import` | A name used without the import that provides it — the OTHER reading of NL010's fact, from the same `ImportUsageFacts` ledger. If the supplying namespace is imported the import is used (NL010 quiet); if it is not, this fires. No whitelist: any name whose supplying namespace is missing is reported. Silent for a source type from another namespace of the same project (which needs no import), for a name the project itself declares, for a member of the enclosing type, and for a file that was not analysed. |
| NL003 | Error | `unnecessary-null-check` | Null check on a value-type literal |
| NL004 | Error | `async-without-await` | `async` function never uses `await` |
| NL006 | Error | `unreachable-code` | Statements after `return` or `throw` |
| NL010 | Error | `unused-import` | `import` statement nothing in the file BOUND through. Answered from `ImportUsageFacts`, the per-file ledger the analyzer stamps on a `CompilationUnit`: when a simple name resolves, the namespace that supplied it is the prefix its resolved identity leaves over, and an import is used when it appears among those. There is NO table of namespace names any more — a dead import of a project's own namespace is reported exactly as a dead `import System` is. An ALIASED import (`import System.Text as Txt`) is one import with two spellings and both credit the same namespace; a FULLY QUALIFIED spelling credits nothing, so an import only ever written out in full really is dead. A file that was NOT analysed reports no namespace import at all (the file-import arm still answers). |
| NL011 | Error | `empty-catch` | Catch block with no statements (silently swallows exceptions) |
| NL012 | Error | `unused-parameter` | Function parameter never referenced in the body (underscore-prefixed names are exempt) |
| NL016 | Error | `redundant-null-check` | Null-equality check on an expression that is always non-null (`new`, array literal, numeric/bool literal) |
| NL020 | Error | `shadowed-variable` | Local variable declaration shadows a variable in an outer scope. A declaration is NOT in scope inside its own initializer (`x := x + 1` is NL301), so a lambda parameter written there shadows nothing; one that reuses a name already in scope IS reported, because N# does not take C# 8.0's relaxation of CS0136 for nested functions. Most shadowing reaches the developer as the analyzer's NL316 instead, which suppresses NL020 for the same file. |

**How deep an expression the linter walks.** `LinterWalk` refuses to descend past
`MaxRecursionDepth()` = **1000 frames** and throws, which aborts the whole `check`/`lint` run rather
than reporting anything. The real malformed-tree guard beside it is the visiting set (a node that is
its own descendant), so the counter's only job is to fail with a message before the CLR stack fails
without one. The cap was 100, which refused ORDINARY SOURCE: a C#-style keyword test
`word == "func" || word == "class" || …` parses left-associatively into one parenthesised binary per
alternative — two frames each — so seventy alternatives took the whole run down. 1000 frames is 500
such alternatives; the columnar parser itself overflows the stack between 1,800 and 2,000, so the
walk now stops well inside what the parser already accepted.

**Deleted (pure-style):** `NL005` (use-pattern-matching), `NL008` (camel-case-local), `NL013` (prefer-interpolation), `NL014` (unnecessary-type-annotation), `NL015` (prefer-const), `NL018` (prefer-readonly), `NL019` (empty-block). These slots are retired and not reused.

**Deleted (pure-style, now handled by `nlc format`):** `NL005` (use-pattern-matching), `NL008` (camel-case-local), `NL013` (prefer-interpolation), `NL014` (unnecessary-type-annotation), `NL015` (prefer-const), `NL018` (prefer-readonly), `NL019` (empty-block). These slots are retired and not reused.

Compiler diagnostics also include error `NL905` for possible null dereference/index/call access — now flow-based, so an unguarded nullable access is an error while narrowing via `if x != null`, `?.`, or `??` clears it. It is emitted from semantic analysis rather than the linter and is therefore visible through `nlc check`, `nlc query diagnostics`, and LSP diagnostics. Other promoted compiler diagnostics (`NL903` visibility-convention, `NL907` nullability) are likewise build-blocking errors.

**Currently supported auto-fixes (`nlc fix`):**

| Code | Fix | Safety | Notes |
|------|-----|--------|-------|
| NL001 | Remove unused variable declaration line | `ReviewNeeded` | Uses string matching (may match inside comments/strings) |
| NL002 | Add missing `import` statement | `Safe` | |
| NL003 | Remove unnecessary `== null` / `!= null` clause | `Safe` | |
| NL010 | Remove unused import line | `ReviewNeeded` | Answered from binding facts, so `nlc fix` AND `nlc lint` both load and analyse the project before they lint |
| NL011 | Insert `// TODO: handle exception` in empty catch | `Safe` | |
| NL905 | Use null-conditional member/index access | `ReviewNeeded` | Changes result nullability; guard/fallback/assertion alternatives are exposed as suggestion-only actions. |

Fixes for deleted pure-style rules (formerly `NL013` concatenation→interpolation, `NL015` `let`→`const`) no longer exist as diagnostics; those rewrites are now part of `nlc format`.

**`FixSafety` levels** (on `CodeAction`):
- `Safe` — always correct to apply automatically (default `nlc fix` behavior)
- `ReviewNeeded` — likely correct but may need follow-up; requires `--include-review-needed` flag
- `SuggestionOnly` — provides a hint only; never written to files

**LSP behavior:** Safe fixes are marked `isPreferred` in the code action response. SuggestionOnly fixes are marked `disabled` with a reason. ReviewNeeded fixes are neither preferred nor disabled — they appear as normal code actions.

Inline lint suppression is also supported for specific warnings:

```nsharp
// nlc:ignore NL001
unusedVar := 42
```

**The LLM coding loop:**
```bash
# Write code → check → fix → check → done
nlc check        # see error: missing import
nlc fix          # auto-adds import
nlc check        # clean ✓
```

### `nlc query completions` — LLM-Optimized Completions

Returns completions grouped by category. Optimized for LLM consumption — keywords and primitives excluded by default (LLMs already know these).

**Identifier context** (what variables/functions are in scope):
```bash
$ nlc query completions --file Program.nl --pos 15:4
{
  "context": "identifier",
  "completions": {
    "variables": [{"name": "person", "kind": "variable", "type": "Person"}],
    "functions": [{"name": "AddPerson", "kind": "function", "type": "void"}]
  }
}
```

The `functions` group is **project-wide, in two halves that are not the same rule.** It carries the
current file's functions (from its semantic model), then the top-level functions declared by every
OTHER file of the SAME namespace, in source order, camelCase ones included — because a camelCase
top-level `func` is private to its namespace, not to its file, so a caret in one file may legitimately
write another file's helper. Names the current file's model already supplied are not repeated.

Then it carries the **EXPORTED** top-level functions of every OTHER namespace of the project, each
row carrying `"importNamespace"` when the file does not already import that namespace (a namespace
the file already writes an `import` for owes nothing, so its functions carry no key at all —
`ImportEditPlanner.IsNamespaceInScope` is the one owner of that question). These are not in scope as written — `ComputeTotal(1, 2)` from
`NsProbe.App` with `NsProbe.Helpers` unimported is `NL412` — so the key names the `import` line a
caller has to add, which is what makes the offer an answer rather than a trap. `importNamespace` is
additive and appears only on a row that needs it, so `schemaVersion` stays at 1. An UNEXPORTED
(camelCase, no `pub`) function of another namespace is offered nowhere, because from there the name
is `NL308` and no import line can fix it. A same-namespace helper of the same name always wins, which
is the order the language resolves in.

**The LSP identifier list is a separate C#-owned path** (`CompletionHandler.AddSemanticCompletionItems`
reads `semanticModel.Functions` directly rather than asking `CompletionEngine`), so the cross-namespace
half reaches `nlc query completions`, `nlc query inspect`, `query batch` and the daemon today and NOT
the editor. Teaching the editor half means mapping `importNamespace` to an `additionalTextEdits`
import insertion the way `AddExternalImportableCompletionItems` already does for external types.

**Member access context** (what members does this type have):
```bash
$ nlc query completions --file PersonService.nl --pos 15:15
{
  "context": "memberaccess",
  "receiver": {"name": "people", "type": "System.Collections.Generic.List`1"},
  "completions": {
    "methods": [
      {"name": "Add", "kind": "method", "type": "void", "parameters": "(item T)"},
      {"name": "IndexOf", "kind": "method", "type": "int", "overloads": 3},
      {"name": "Remove", "kind": "method", "type": "bool", "parameters": "(item T)"},
      {"name": "Count", ...}
    ]
  }
}
```

Member access completion resolves the receiver expression semantically, including chained calls and properties such as `message.ToUpper().` or `factory.Create().`. CLI query results and LSP completion/hover use the analyzer's recorded expression types as the source of truth, so duplicate member names on unrelated receiver types do not collapse into name-only matches.

The member surface includes the receiver's declarations, its class bases, and the full closure of its
source or CLR interfaces. Generic interface edges keep their closed type arguments (`IValue<string>`
offers `Value: string`), and a shared diamond ancestor contributes one row. Source interface edges
follow the analyzer's depth-first, written-order lookup: the first declaration of a name hides later
interface declarations, so `IC: IA, IB` offers `IA.F` rather than inventing a cross-interface overload
set from `IA.F` and `IB.F`. The selected declaration keeps its ordinary overload grouping and static
or instance filter.

**One row per member name, ordered.** A member access answers one row per NAME, not one per overload: `string` reflects 105 methods under 39 names, and eleven `Split` declarations are one row carrying `"overloads": 11`. The `overloads` key is additive and appears only when a name has more than one declaration, so `schemaVersion` stays at 1; the editor renders the same fact as `(+10 overloads)` in the item's detail. Rows are ordered by kind rank — keyword, variable, function/method, property/field, type, everything else — and then by name, case-insensitively, so the JSON's group order and the editor's row order are the same order. A name listed under two different kinds (`async` as both a keyword and a modifier) collapses to one row but is not counted as an overload.

**A granting reference's internals are offered.** A referenced assembly that declares
`[assembly: InternalsVisibleTo("<this project>")]` has made this compilation a friend, and the
analyzer has bound its `internal` members for that project since friends landed — `nlc check` accepts
`WorkspaceSymbolHandler.MatchesQuery(...)`, an `internal static` method of a public type, from
`tests/native/census-internals-visible-to`. The completion list asked metadata for `BindingFlags.Public`
alone, so the editor offered strictly less than the compiler would accept. The snapshot now carries the
project's `InternalsVisibleToGrants` (the ONE owner of the grant) out of the analysis, and the
reflected-member walk asks it alongside `MemberAccessibility.IsAccessible` (the ONE owner of the
relation): a friend reaches `internal` and `protected internal`, never `private`, and `private
protected` still needs the derived-type half as well. A project the reference does not name sees the
public surface only. Hovering one of those offered members names the level as well — see
`accessibility` under [`nlc query hover`](#nlc-query-hover--signature-and-docs-at-a-position) — so
the editor both offers the member and says why it is reachable.

**Visibility is package-scoped, and the list obeys it.** N# spells visibility the way Go does — PascalCase (or a written `public`) exports, camelCase does not — and an unexported member stays readable from any file in the *same* namespace. A member access completion therefore offers an unexported member only when the caret shares the declaring package; asking from another package drops it, because the analyzer answers `NL308` on that read. When the declaring package cannot be established (no project behind the buffer, a receiver that is not source-declared, two files declaring the same simple name in different namespaces with nothing to tell them apart) the list fails open and offers everything, since a hidden legal member is a defect the developer cannot see past while an offered illegal one is explained by the very next diagnostic.

Add `--include-keywords` to also get keywords, primitives, and modifiers.

### `nlc query references` / `refs` — Semantic References

Returns only binding-map-backed references for the symbol at `--file --pos`. It does not grep text, scan comments, or fall back to simple-name matching; if the selected position cannot be tied to a precise compiler binding, the command returns `ok: false` with `error.code: "semanticReferencesUnavailable"`.

Successful results always include the declaration as a reference entry, so an empty result is never presented as a precise semantic answer.

```bash
$ nlc query refs --file Program.nl --pos 5:12
{
  "schemaVersion": 1,
  "command": "references",
  "ok": true,
  "symbol": { "name": "value", "kind": "local", "definedAt": { "file": "Program.nl", "line": 3, "column": 9 } },
  "count": 2,
  "results": [
    { "file": "Program.nl", "line": 3, "column": 9, "length": 5, "isDefinition": true },
    { "file": "Program.nl", "line": 4, "column": 11, "length": 5, "isDefinition": false }
  ]
}
```

### `nlc query inspect` — One Round Trip, Full Context

`inspect` is the LLM-first navigation primitive. It bundles the semantic symbol, resolved type, definition, references summary, and completions for a single cursor position.

```bash
$ nlc query inspect --file Program.nl --pos 85:22
{
  "schemaVersion": 1,
  "command": "inspect",
  "file": "Program.nl",
  "position": { "line": 85, "column": 22 },
  "result": {
    "symbol": { "name": "GetStats", "kind": "function", "definition": { "file": "Services/TaskService.nl", "line": 93, "column": 5 } },
    "type": { "resolvedType": "TaskStats", "kind": "record" },
    "definition": { "file": "Services/TaskService.nl", "line": 93, "column": 5 },
    "references": { "count": 2, "definitionCount": 1, "results": [...] },
    "completions": { "context": "memberaccess", "receiver": "service", "receiverType": "TaskService", "completions": { ... } }
  }
}
```

### `nlc query inspect --summary` — Compact, Stable Envelope

`--summary` keeps the same `schemaVersion`, `command`, `ok`, `file`, and `position` envelope, but replaces the full `result` tree with a compact `summary` object. That makes the output easier to diff, cache, and consume from automation.

```bash
$ nlc query inspect --summary --file Program.nl --pos 85:22
{
  "schemaVersion": 1,
  "command": "inspect",
  "ok": true,
  "file": "Program.nl",
  "position": { "line": 85, "column": 22 },
  "summary": {
    "symbol": { "name": "GetStats", "kind": "function" },
    "type": { "name": "GetStats", "resolvedType": "TaskStats", "kind": "record" },
    "definition": { "name": "GetStats", "kind": "function", "file": "Services/TaskService.nl", "line": 93, "column": 5 },
    "references": {
      "count": 2,
      "definitionCount": 1,
      "files": ["Program.nl", "Services/TaskService.nl"],
      "sample": [ ... ]
    },
    "completions": {
      "context": "memberaccess",
      "receiver": "service",
      "receiverType": "TaskService",
      "totalCount": 6,
      "groupCounts": { "functions": 2, "properties": 4 },
      "groups": {
        "functions": ["GetStats", "CreateTask"],
        "properties": ["Total", "Todo", "InProgress", "Done"]
      }
    }
  }
}
```

### `nlc query batch` — One Project Load, Many Queries

`batch` is the LLM-facing orchestration surface. It takes a JSON array or `{ "requests": [...] }` file, runs each request against the same project snapshot, and returns one stable envelope with per-item responses nested under `results[].response`. Each request can also carry an optional `id`, which is echoed back at `results[].id` for correlation.

```json
[
  { "command": "inspect", "file": "Program.nl", "pos": "86:39", "summary": true },
  { "command": "doc", "query": "Console.WriteLine" },
  { "command": "type", "file": "Program.nl", "pos": "83:1" }
]
```

```bash
$ nlc query batch --requests requests.json
{
  "schemaVersion": 1,
  "command": "batch",
  "ok": false,
  "projectRoot": "/repo/examples/17-issue-tracker/backend",
  "requestCount": 3,
  "successCount": 2,
  "failureCount": 1,
  "results": [
    {
      "index": 0,
      "request": { "command": "inspect", "file": "Program.nl", "pos": "86:39", "summary": true },
      "ok": true,
      "response": { "...": "full inspect --summary envelope" }
    },
    {
      "index": 2,
      "request": { "command": "type", "file": "Program.nl", "pos": "83:1" },
      "ok": false,
      "response": { "...": "full structured noSymbol error envelope" }
    }
  ]
}
```

Supported request commands:
- `symbols`
- `outline`
- `diagnostics`
- `type`
- `inspect`
- `definition` / `def`
- `references` / `refs`
- `completions`
- `doc`

### `nlc query hover` — Signature and Docs at a Position

Returns the signature, kind, definition location, and any inline doc comment for the symbol at a cursor position. Shares its semantic model with the LSP `HoverHandler`.

```bash
$ nlc query hover --file Program.nl --pos 5:6
{
  "schemaVersion": 1,
  "command": "hover",
  "ok": true,
  "file": "Program.nl",
  "position": { "line": 5, "column": 6 },
  "result": {
    "signature": "func hi(): int",
    "documentation": "A simple hello-world program demonstrating functions and string interpolation",
    "definedIn": "Program.nl",
    "kind": "function"
  }
}
```

A member that comes from METADATA rather than from the project — `summary.ToUpper()`, `DateTime.Now`, `arr.Length`, `list.ToArray()` — carries its full signature and an additional optional `declaringType`, and has no `definedIn` because there is no project file to point at:

```json
  "result": {
    "signature": "method ToUpper: string ToUpper() (+1 overload)",
    "declaringType": "System.String",
    "kind": "method"
  }
```

`declaringType` is an optional addition at `schemaVersion` 1: it is present only for metadata members, and `definedIn` remains a file path for project-declared symbols. One overload is rendered and the rest are counted. The language server shows the same two facts as `*Declaring Type:*` and `*Defined in:*`, because both surfaces are answered by the same owner.

**`accessibility` says WHY a name resolves, when that is not "it is public".** A metadata member whose DECLARED level is not `public` carries that level's own word — `internal`, `protected`, `protected internal` — beside its kind, and a public one carries no key at all. The case this exists for is the friend grant: reaching `WorkspaceSymbolHandler.MatchesQuery` is legal only because `LanguageServer.dll` names this project in an `InternalsVisibleTo`, and hover used to render it identically to a public member, so the one fact the reader needed was the one the editor never said. The word comes from `MemberAccessibility.LevelWord` — the same owner whose word a refusal quotes — so the editor and the diagnostic cannot disagree. Like `declaringType` this is an optional addition at `schemaVersion` 1 (`kind` is unchanged, because editors switch on it), and the language server renders it as `*Accessibility:*` while `--text` prints `Access:`.

```json
  "result": {
    "signature": "method MatchesQuery: bool MatchesQuery(string name, string query)",
    "declaringType": "NSharpLang.LanguageServer.Handlers.WorkspaceSymbolHandler",
    "accessibility": "internal",
    "kind": "method"
  }
```

A metadata member also carries `documentation`: the first sentence of its .NET XML summary, read from the reference packs — the same source `nlc query doc` uses. This is the key the envelope already had (a project symbol's `documentation` is its doc comment), so nothing about the schema moves; what changed is that a metadata member now has something to put in it. The language server renders it under the signature, as it always has for source symbols.

```json
  "result": {
    "signature": "method AddDays: DateTime AddDays(double value)",
    "documentation": "Returns a new DateTime that adds the specified number of days to the value of this instance.",
    "declaringType": "System.DateTime",
    "kind": "method"
  }
```

**Where the text comes from, and why it is not the assembly's own file.** The lookup is keyed on the ECMA-334 doc id (`M:System.DateTime.AddDays(System.Double)`), resolved against every `.xml` in the installed reference packs. It cannot be keyed on the declaring assembly: the compiler's external types are read out of the **shared framework**, which ships no `.xml` at all and whose facades type-forward, so `List<T>` reports `System.Private.CoreLib` and no `System.Private.CoreLib.xml` has ever existed. The packs are found by climbing from any loaded assembly path to the directory that holds both `packs` and `shared`; that path is used to locate the **dotnet root** and never to look for XML beside it. A machine with no reference packs, or a member the packs do not document, answers exactly as before — signature only. The feature can never subtract a line.

**Cost.** The doc index is built on the **first hover that lands on a metadata member** and never before, so a session that only hovers project symbols pays nothing: a source-symbol hover stays at ~0.45 s. The first metadata hover costs ~1.35 s (~0.9 s to read the packs' ~354 XML files / ~73 MB / ~144 k members). It is then memoized on the `ProjectSnapshot`, so the language server and any other long-lived host pay it once per project and every later hover — of any member — is free. `nlc query hover` from a shell is a fresh process each time and cannot amortize it: the daemon protocol has no `hover` method, so hover always runs in-process.

**Generic receivers and inherited members.** A member of any constructed external generic — `List<Reading>`, `Collection<string>`, `Dictionary<string, Node>` — is read off the generic DEFINITION and the receiver's spelled arguments are substituted back by position. So the declaring type is always the definition form (`System.Collections.ObjectModel.Collection<T>`, never the CLR's `Collection<String>`), and a member typed in a type parameter keeps the argument as written (`Items: IList<string>`, not the oblivious `IList<string?>` the closed type reports). A bare name inside a class body that no source symbol binds — `Items` or `Add("x")` in `class Bag: Collection<string>` — is hovered as `this.Items`: the source bases are climbed (a source member of that name always wins, as does any local or parameter) to the first external base, whose `protected` members are reachable this way and through `this.`/`base.` but never through another value. Expression-bodied functions (`func Size(c: Collection<string>): int => c.Count`) answer exactly as block-bodied ones do.

**Overloads.** Where the position is a call with arguments, hover shows the overload that call binds to and no count: the reader's own arguments chose one. `Random.Shared.Next(1, 7)` and `Random.Shared.Next(10)` are the same member and answer `int Next(int minValue, int maxValue)` and `int Next(int maxValue)` respectively. Away from a call site — a member named without calling it — one signature is shown with `(+N overloads)` beside it, because there is nothing to narrow with. The count also survives a call whose argument count fits no overload at all: nothing was chosen, and saying otherwise would trade a misleading signature for a misleading count. Arity is the gate and parameter-type identity ranks within it; the comparison is by type full name, which is the same string whether the type came from the compiler's `MetadataLoadContext` or from a live `typeof`.

**Members a project type inherits from a metadata base.** Inside `class Failure: Exception`, both `Message` and `this.Message` hover to `property Message: string { get; }` with `declaringType` `System.Exception` and the packs' summary — the same answer `DateTime.Now` gets. Both used to answer `noSymbol`: `this` and the enclosing type behind a bare name are SOURCE types with no CLR type of their own, and the member lives one `:` edge further up. Hover climbs the class chain through the edges the analyzer recorded, passing source bases that do not declare the name (`class Coded: Failure` reaches `Exception.StackTrace` through `Failure`), and asks the first base the project did not write. A name any source class on that chain declares is the project's own member and keeps its declaration answer, and a bare name that binds to a local or a parameter is that local or parameter — the analyzer's own channel order. Because the receiver is the deriving type's own instance, a `protected` base member is reachable exactly as the compiler binds it, and hover says so (`Collection<T>.Items` answers `"accessibility": "protected"`). `nlc query type` at an inherited METHOD (`ToString()`) renders the same signature, so the two commands still reconstruct each other.

Hover and `query type` also answer inside an **expression-bodied** function (`func Text(): string => this.Message`); the position finder read only block bodies, so every expression in an `=>` body — `this`, a member, a call — used to answer nothing unless a binding happened to cover it.

Exit code 0 on success, 1 with a structured `noSymbol` error envelope if there is no symbol at the given position.

### `nlc query doc` — .NET API Documentation

Resolves a type or member name (`Console`, `System.Console`, `List.Add`, `Environment.SpecialFolder`, case-insensitive, arity-blind) against every assembly the CLI's runtime can load — a fixed BCL seed list plus every reference-pack assembly — and renders the XML documentation from the packs: summary, members, parameters, base types. `--text` renders Elm-style text; the default is the versioned JSON envelope.

**Loading semantics.** The reference packs offer more assembly names than the CLI's own runtime carries (on a default install, the entire ASP.NET Core surface — ~140 names). A name the runtime cannot load is **skipped and noted, never fatal**: the query answers over everything that did load. A miss is explained when the evidence allows it — the packs' XML loads from disk even when its assembly does not, so:

- if the packs document a matching type whose documenting assembly could not be loaded, the error names that exact type and assembly ("The reference packs document 'Microsoft.AspNetCore.HttpLogging.HttpLoggingOptions' (assembly 'Microsoft.AspNetCore.HttpLogging'), but that assembly is not part of this runtime…");
- if the query itself names an unloadable assembly, the error says which one;
- otherwise the message stays the plain `No documentation found for '<query>'.`

Exit code 0 with a doc envelope on success, 1 with an error envelope on a miss (the `message` carries the unloadable-assembly note when there is one). The skip-and-note state lives in the N# owner `DocQueryTypeIndex.nl`; the miss-explanation policy is `DocQueryKernels.DescribeDocLookupMiss`.

### `nlc query call-graph` — Callers and Callees

Walks all ASTs in the project to build a call graph. Use `--function` to focus on a specific function; omit it for a project-wide edge list. Use `--limit` (default 100) to cap result size.

```bash
$ nlc query call-graph --function Main
{
  "schemaVersion": 1,
  "command": "callGraph",
  "ok": true,
  "function": "Main",
  "callers": [],
  "callees": [
    { "name": "hi", "file": "Program.nl", "line": 19, "column": 9 }
  ],
  "truncated": false
}
```

### `nlc query implementors` — Concrete Types Implementing an Interface

Finds all class, struct, and record declarations in the project that list a given interface in their inheritance chain.

```bash
$ nlc query implementors --name IShape
{
  "schemaVersion": 1,
  "command": "implementors",
  "ok": true,
  "interface": "IShape",
  "results": [
    { "typeName": "Circle", "kind": "class", "file": "RecordsAndInterfaces.nl", "line": 21, "column": 1 }
  ]
}
```

Also supports position-based lookup (`--file F --pos L:C`) which resolves the interface at that position first.

### `nlc query symbols --filter` — Fuzzy/Glob Symbol Search

The `symbols` subcommand now accepts `--filter <pattern>`:
- Patterns containing `*` are treated as globs (`*Person*` matches any name containing `Person`)
- Bare strings are treated as case-insensitive substring matches
- Results are capped at 200

```bash
$ nlc query symbols --filter '*Person*'     # glob wildcard
$ nlc query symbols --filter Person         # substring
$ nlc query symbols --filter 'Get*'         # prefix glob
```

### `nlc format` — Canonical Formatting With CI Support

`format` now supports the standard cargo/gofmt-style workflows:

```bash
nlc format           # rewrite files in place
nlc format --check   # exit 1 if any file would change
nlc format --diff    # show unified diffs without writing files
nlc format --stdin < Program.nl
```

- `--check` is the preferred CI flag
- `--verify-no-changes` remains as a compatibility alias
- `--diff` prints unified hunks against the formatter output
- `./scripts/test-all.sh` includes a formatting gate for `examples`, `templates`, and `tests/fixtures/issue-tracker`; intentionally malformed diagnostic fixtures are not part of that gate.

### `nlc tree` — Dependency Tree

`tree` is an active dependency-inspection command, not future work:

```bash
nlc tree
nlc tree --depth 1
nlc tree --json
```

Behavior:

- In csproj-free projects, `nlc tree` reads `project.yml` and lists direct runtime dependencies (`nuget`, `framework`, `project`, and `dll` references).
- If a minimal MSBuild project file is present and `dotnet list package` succeeds, `nlc tree` restores the `project.yml` projection and asks `dotnet list package --include-transitive --format json` for direct and transitive NuGet packages.
- JSON output uses schema version `2` and exposes `capabilities.transitiveNuGetDependencies` plus `limitations[]` so automation can distinguish "direct dependency list available" from "full transitive NuGet graph available."
- The command does not yet reconstruct nested package-to-package edges for csproj-free `project.yml` projects without an MSBuild project file; it names that limitation precisely instead of treating the entire command as absent.

### `nlc test` — Filtered, Developer-Friendly Test Runs

`test` now supports focused development loops:

```bash
nlc test --filter "should add"
nlc test --verbose
```

- `--filter` matches both test display names and fully-qualified test names
- `--verbose` shows individual test results without changing the test pipeline
- **A red run names its failures on the default text route.** Before the `Passed: …, Failed: …` summary, `nlc test` prints a `Failed tests (N):` block listing every failed row: its `test "…"` sentence, the generated method (`at Namespace.FileTests.Method`) when that differs, and the failure message indented under it (`Assertion failed` for an `assert` with no message). A green run prints no block, and the summary stays the last line. The same three facts are `displayName`, `name` and `errorMessage` in the `--json` rows, which are unchanged (schemaVersion 1). Emitted test assemblies carry no PDB and `assert` records no position, so the report cannot name a source line yet.
- Native coverage is not available in `nlc test` yet. `--coverage` and `--coverage-report` are accepted only to fail honestly: exit code 1, a clear text error by default, and the same message in the schemaVersion 1 JSON `error` field when `--json` is present.
- **The runner's vocabulary is N#-owned (`TestCommandKernels`), not the C# runner's.** `results[].outcome` is exactly `passed`, `skipped` or `failed`; a word outside that set ranks unknown and fails the run. `results[].duration` is three decimal places and an `s`, formatted with `CultureInfo.InvariantCulture`, so the envelope never carries a comma decimal regardless of the machine's locale. `results[].displayName` and `nsharpDescription` prefer the `test "…"` sentence over the framework's method name. The per-test lifecycle is `InitializeAsync` → `Setup` → the test → `Teardown` → `DisposeAsync` → `IDisposable.Dispose`, in that order, and every one of those names is excluded from discovery.
- **A `test` block may carry attributes.** A `test "…"` block lowers to a method, so an attribute
  written above it is an attribute on that method — including one the project declares itself. An
  attribute deriving from `Xunit.FactAttribute` is what makes a test conditional, and the compiler
  attaches its own `[Fact]` **only when the test does not already carry one**: a method with two
  `[Fact]`-derived attributes is a discovery error in xunit ("has multiple [Fact]-derived
  attributes"), so the author's wins and the synthesized one is withheld. The `[Trait]` row carrying
  the test's sentence is attached either way, which is why `displayName` is unaffected. A derived
  attribute whose constructor sets `Skip` produces a `skipped` result with its reason in
  `results[].errorMessage`.

  ```nsharp
  sealed class DockerFactAttribute: FactAttribute {
      public constructor() {
          if !DockerAvailable() {
              Skip = "Docker is not running"
          }
      }
  }

  [DockerFact]
  test "the container starts" { … }
  ```

  This is shipped, not illustrative: `tests/native/installed-toolchain-integration` carries thirteen
  rows under exactly this attribute, and it is how the installed-toolchain suite reports itself on a
  machine with no Docker daemon. See `memory/testing.md`, "The Installed Toolchain".

### The test-framework reference set

One owner — `TestFrameworkReferenceSet` — answers what a test framework's references ARE, and
`nlc test`, `nlc check` and the language server all read it. It distinguishes four things that are
not the same string:

| Question | xunit | nunit |
|---|---|---|
| The package a project that writes tests restores | `xunit` 2.9.2 | `NUnit` 4.3.2 |
| The assemblies a `test` block's lowering binds at COMPILE time | `xunit.core` (ships in `xunit.extensibility.core`), `xunit.assert`, `xunit.abstractions` | `nunit.framework` (ships in `NUnit`) |
| What the runner needs at RUN time, beyond the compile set | `xunit.execution.dotnet` (ships in `xunit.extensibility.execution`) | — |
| The emit host's last-ditch `Assembly.Load` probe | `xunit.core`, `xunit.v3.core` | `nunit.framework` |

- **A metapackage is never reported as an unreadable assembly.** `xunit` ships no dll at all (nor
  does `xunit.core`, which is also a metapackage — the *assembly* of that name lives in
  `xunit.extensibility.core`), so asking the analyzer's load context for an assembly called `xunit`
  could only ever fail. It used to, as `NL923 Reference assembly 'xunit' could not be loaded or fully
  inspected`. The rows above are planned instead, and every load failure is recorded under the
  ASSEMBLY name.
- **A project that has `*.tests.nl` sources depends on a test framework whether or not it says so.**
  `nlc check` and `nlc build` add the implicit package before analysis begins; the language server
  parses `project.yml` and does not, which is why a `.tests.nl` file used to bind in a build and not
  in the editor. `AnalyzerReferenceLoadOrchestration` plans the framework rows for any project with
  test sources, so all three products answer the same way.

### `nlc build` — Release Builds and Verbose Output

Build supports Go/Rust-style configuration flags:

```bash
nlc build                # debug build (default)
nlc build --backend il   # direct IL build
nlc build --release      # Release configuration/output layout
nlc build --verbose      # detailed native resolver/build output
nlc build --release --verbose
```

- All builds report elapsed time on completion (e.g., `Build successful! (release) [2.3s]`)
- `il` backend parses/analyzes the project, emits a managed assembly directly, and writes `.runtimeconfig.json` for executables
- `--release` selects the Release configuration and native output layout (`bin/Release/<tfm>` unless `--output` is provided); it is not a separate IL optimizer today
- `--verbose` enables detailed native resolver/build output
- Set `NSHARP_COLUMNAR_DECLINE_LOG=1` while debugging an `NL103` columnar-emission decline to print every decline trace
  record to stderr. `NSHARP_DEBUG_LOG=1` also mirrors the trace into `compile-debug.log`.
- In-project parallelism: a large project's semantic analysis and the IL back end's per-file parse fan
  its files out to several workers (`CompilerParallelism`: one worker per ~500,000 characters of
  source, at most `min(cores, 4)`; smaller projects stay serial). The output is identical to a serial build -- same diagnostics in the same
  order, same IL bytes. `NSHARP_COMPILER_WORKERS=<n>` overrides the count (`1` forces the serial path);
  every `build`, `check`, `test` and `run` that compiles through `MultiFileCompiler` honours it.

### Incremental builds — the up-to-date stamp

`nlc build`, `run`, `test`, `publish`, `pack` and every `project:` reference they build answer an
UNCHANGED compilation from a stamp instead of compiling it: nothing is parsed, analysed, linted or
emitted, the previous output is kept, and its diagnostics (warnings included) are printed exactly as
the compilation printed them. On a loaded machine (paired runs, 2026-10-05) a no-op `nlc build` of
`examples/16-task-cli` (11 files) dropped from 2.19 s to 0.22 s of CPU and of
`tests/native/census-flow-rules` (27 files) from 2.71 s to 0.17 s; a no-op `nlc test` from 2.61 s
to 0.34 s and 5.87 s to 0.46 s (the tests still run).

- **Content, never time.** The stamp (`<projectRoot>/obj/nlc/<assembly>.<output hash>.stamp`,
  `IncrementalBuildStamp.nl`) records a KEY — every non-file input hashed together: the compiler's
  identity (the deterministic MVIDs of the Model, Syntax, Core, Plan, Emit, CodeIntel and Driver
  assemblies, plus the CLR version, runtime directory and RID), the options (assembly name, output
  path, strict lint, analysis, AOT, reference assembly, SoA), the parsed `project.yml` (a structural
  walk of every public field and read/write property, so a new setting is covered without anyone
  listing it), the defines, the ordered source list, `NUGET_PACKAGES`, the user profile and the
  current directory — and an ENTRY per file or directory the compilation consulted, with its SHA-256
  (`IncrementalBuildInputCapture.nl` names each reader): every source; every `.nl` file the analyzer's
  project walk sees, as a set and by content, and whether any `*.tests.nl` exists; `project.yml`
  byte for byte; every `.editorconfig` from each source directory to the filesystem root (absence
  recorded); `obj/project.assets.json`; hot-summary sidecars; every `dll:` reference and its paired
  runtime asset; each `nuget:` reference's locally built `bin/` candidate and cache-directory listing;
  each `project:` reference's `project.yml`; every file a unit imports by path (each spelling the
  resolvers try); every assembly the analyzer's metadata context actually read, including lazily
  resolved ones, and the listing of every directory its resolver probes; `NSharpLang.Runtime.dll`;
  and the outputs themselves. Only files inside the running .NET installation's `shared/` and `packs/`
  trees (immutable, version-named) are identified by path, size and write time.
- **Fail-safe.** The stamp ends with a SHA-256 of its own payload and opens with a magic string and a
  format version; a corrupt, truncated, foreign or old stamp is a miss. An unreadable input never
  matches. Stamps are written atomically (unique temp file, then rename) and only after a successful
  compilation, so a failed build is always re-run.
- **One known extra rebuild.** A project with `nuget:` dependencies building into the default
  `bin/Debug/<tfm>/` is compiled TWICE before its stamp settles: the first build's analyzer read the
  package from the cache, the CLI then copies the package beside the output, and that copy is the
  "locally built" candidate the analyzer prefers next time — a genuinely changed input. The third
  build onward is a no-op. (Seen on four `tests/fixtures` projects when every example is built
  twice; every other example's second build is answered by its stamp with identical bytes.)
- **Who opts in.** `MultiFileCompiler.IncrementalBuild` is off by default; the CLI's project builds
  and reference builds turn it on. A stamp is kept only for an output INSIDE the project root, so
  `nlc build -o /elsewhere` (the compile-time bench) leaves the source tree untouched and always
  compiles. `nlc check` (which writes nothing), editor buffers
  (source overrides), single-file builds, `--perf-report` (which needs the systems analysis) and runs
  with `NSHARP_COLUMNAR_DECLINE_LOG`/`NSHARP_DEBUG_LOG` set always compile. `NSHARP_INCREMENTAL=0`
  turns every shortcut off for the process. `nlc test --no-cache` deletes the test output, which
  invalidates its stamp.
- **Pinned by** `tests/native/incremental-build` (`UpToDate.tests.nl`): every invalidation axis
  (source edit, add/delete/rename, a test file the build does not compile, `project.yml` comment,
  define, configuration value, compile options, `.editorconfig`, deleted or modified output, corrupt,
  truncated or foreign stamp, a referenced DLL's content) rebuilds and must equal a build with the
  machinery off; a touched-but-identical source stays up to date; and the stamp's `CompilerError`
  field list is compared with the record's own members.

### Incremental analysis in a warm process — `IncrementalProjectSession`

A process that compiles the same project repeatedly (the daemon, an editor host, a watch loop)
holds an `IncrementalProjectSession` (`src/NSharpLang.Compiler.Driver/IncrementalProjectSession.nl`)
per project and gets per-FILE reuse: a body-only edit re-analyses only the edited file, a signature
edit re-analyses only the files that depend on it.

```text
session := IncrementalProjectSession.Open(projectRoot, assemblyName)   // seeds summaries from obj/nlc/<assembly>.summaries
result := session.Compile(config, sourceFiles, outputPath, options, sourceTextOverrides)   // MultiFileCompilationResult
compiler := session.Analyze(config, sourceFiles, sourceTextOverrides)  // no emission: queries, check
snapshot := session.Snapshot()                                         // ProjectSnapshot of the last compilation
session.Save()                                                         // persist per-file summaries
session.State.LastFilesAnalyzed / LastFilesReused                      // what the last run did
```

- **What is kept** (`IncrementalCompilationState`, handed to `MultiFileCompiler.IncrementalState`):
  the analyzer (its metadata load context and caches) and, per file, the unit as analysis left it,
  its parse diagnostics, semantic model, bindings, type-declaration rows and raw analyzer
  diagnostics. An ENVIRONMENT KEY (compiler identity, configuration, defines, options, and the
  content of every non-source input: references, restore output, `project.yml`, the test-source
  switch) plus the metadata files the analyzer actually read guard all of it; any change drops the
  analyzer and every record.
- **When a file's analysis is reused** (`IncrementalCompilationPlan`): its text is unchanged; no file
  in its dependency closure changed SURFACE, appeared or vanished — checked against both the closure
  recorded when it was analysed and the closure computed now; no namespace it mentions appeared or
  vanished; every file it imports by path kept its content.
- **The per-file summary** (`IncrementalFileSummary`, content-hashed, computed from the unpreprocessed
  text the analyzer's project walk reads): the SURFACE HASH covers every token outside function,
  constructor, accessor and test bodies with its position (analysis results carry declaration
  positions, so a declaration that moves is a surface change); DECLARED names, REFERENCED names and
  BASE-LIST names come from a reflective walk of the declaration AST (new declaration kinds are
  covered without being listed); MENTIONS are the names the file's own analysis can ask for (every
  word in its bodies, string literals included, its references, its top-level names, its namespace
  and imports). A file that does not parse cleanly is OPAQUE: it depends on and is depended on by
  everything.
- **The dependency closure** of a file: every file declaring a name it mentions (or that name plus
  `Attribute`), every file whose types list such a name as a base, every opaque file, and
  transitively the same for the names those files' surfaces refer to. The premise — a file reaches
  another only through names, and learns only its surface — is what the differential test holds.
- **What still runs whole-project every time:** parsing (cheap), import-cycle detection, the systems
  policy (interprocedural over bodies), the strict lint and IL emission (one assembly).
- **Cold processes do not reuse per-file analyses.** The systems policy pass reads the full semantic
  model of every file (`ExpressionTypes`, `TypesByIdentity`, `TypeReferenceTypes` — `TypeInfo` graphs
  tied to the analyzer's `MetadataLoadContext`) and the emitter reads every file's model for
  free-function call targets, so a cold build after any edit re-analyses everything; its shortcut is
  the up-to-date stamp. The persisted summaries only spare a cold-opened session the summary pass.
- **Pinned by** `tests/native/incremental-build/Differential.tests.nl`: a warm session through seeded
  edits (body literals, inserted lines, renamed identifiers, retyped signatures, files added,
  duplicated, removed, restored) over five multi-file projects — `examples/16-task-cli`, the
  ASP.NET `examples/17-issue-tracker/backend`, `examples/12-multi-file-projects/{imports,WeatherDemo}`
  and the embedded `geo` corpus (`IncrementalGeoCorpus.nl`: cross-file interface implementations,
  base classes, `[Tag]` for `TagAttribute`, unions, overloads, generics, interpolation-only calls) —
  must produce diagnostics and IL bytes identical to a from-scratch compilation. Eight edits per
  project by default; `NSHARP_INCREMENTAL_DIFFERENTIAL_STEPS=60` ran 310 comparisons (171 successful
  builds byte-compared, 139 failing builds diagnostic-compared), 0 mismatches, 987 analyses reused.

### Observing incremental work

The structural work counters (files parsed, analysed, assemblies emitted) have one owner,
`CompilerWorkCounters` with `nlc build|check|test --stats` (the agent-loop benchmark's); an
up-to-date build reports zero of each, and a warm session's re-analysis counts only the files it
re-analysed. The incremental layers add their own direct readings:
`MultiFileCompiler.WasUpToDate` (the stamp answered) and
`IncrementalCompilationState.LastFilesAnalyzed` / `LastFilesReused` (what the last warm run did).

### The workspace server holds the sessions — warm body-edit re-analysis

`nlc check` and `nlc build` (and `run`/`test`/`publish`/`pack`, which compile through the same
backend) take a warm session when the workspace server runs them for a client
(`WarmIncrementalSessions`, Driver): one `IncrementalProjectSession` per compilation identity —
project root, assembly, command (`check` analyses for diagnostics and validates the emission in memory;
`build` emits what it keeps), test sources included or not, AOT. So a routed check after a body edit
re-analyses only the edited file; after a signature edit, that file and its dependents.

- Only a command the server runs for a client gets a session (`CliInvocationContext.IsRemoteInvocation`);
  a one-shot `nlc` and the server's own warm-up compile exactly as before.
- The state's own environment key still resets it on any configuration, define or reference change,
  so a stale session can cost a full compilation but never a wrong one. A compilation that THROWS
  discards its session; a session in use is never handed to a second compilation.
- It registers with `WarmStateRegistry` as `incremental-compilations`: a trim (memory cap) drops
  every idle session, a path change needs nothing (the plan compares content), and
  `nlc daemon status` lists `"incremental-compilations: N compilations, M files retained"`.
- Composes with parallel analysis: files the plan reuses skip the workers; the rest fan out under
  `CompilerParallelism`, and workers still replay every earlier file's import loads, reused ones
  included. A reused file's driver parse is kept on its record, so it seeds the analyzers too.
- Measured through `--stats` folded from the server (4-file probe, `tests/native/daemon-exec`):
  first routed check 4 files analysed, after a body edit 1, after a signature edit with its caller
  updated 2; `build` the same. Pinned by `daemon-exec`'s "a warm check and build re-analyse only the
  files an edit reaches and answer as a fresh process does" (counters plus in-process parity across
  body, signature and error edits) and `incremental-build/WarmIncrementalSessions.tests.nl` (identity,
  busy refusal, trim, discard).
- **The back end is incremental too (`speed/agent-loop-2`).** The session also keeps each file's
  columnar parse (`ColumnarFileProgramCache`, reused while the file's text and position hold, with
  the decline records it made) and the last emission's outcome under the key of everything emission
  reads (`MultiFileCompiler.ComputeEmissionKey`: the state's environment key, the assembly name, the
  back-end switches and every source by path and content): an unchanged compilation is answered with
  the previous image (written for a build, kept in memory for a check) and the previous diagnostics
  without walking a body. The IL walk itself is NOT per-function incremental, and cannot be cheaply:
  `PersistedAssemblyBuilder` writes `ldstr` tokens into the user-string heap at emit time (a body's
  bytes depend on every string emitted before it), the emitter's lambda counter, display classes and
  holder types are program-wide sequences, and the stage-0 seed cannot subclass `ILGenerator` (it
  does not yet emit an override of an abstract property, `ILOffset`) to record a body's call stream
  for replay -- so a body edit re-walks the program, which the walk's own speed-ups made cheap.
  Proven by `incremental-build`'s differential rows: a warm build session's diagnostics and IL bytes,
  and a warm check session's diagnostics and validated image, equal a fresh compilation's after every
  one of the seeded edits to five multi-file projects (40 per project measured; 8 in the gate), and
  each run must have reused emissions and parses -- the rows fail when the key ignores source text or
  the parse cache ignores it.
- **Measured warm (the agent-loop `large` project, 80,960 lines, daemon running, one body edit):**

  | request | before (`28dfd91b2`) | after |
  |---|---:|---:|
  | first `check` after the edit | 2.28 s | 0.76 s |
  | the same `check` again | 1.93 s | 0.13 s |
  | first `build` after the edit | 2.02 s | 0.43 s |

  The first check after the edit re-analyses one file, reuses 160 of 161 columnar parses and walks
  the program once (~0.3-0.5 s); merging the reused files' binding maps had cost ~0.2 s by itself
  until `BindingMap.FindReferenceBucket` grouped its fallback by file name.

### `nlc publish` — Framework-Dependent Deployment Artifacts

`nlc publish` builds through the IL backend and writes framework-dependent artifacts. Supported shapes today:

```bash
nlc publish --output ./dist
nlc publish --configuration Release --output ./dist
nlc publish --runtime <current-rid> --output ./dist
```

- Without `--runtime`, output is portable framework-dependent: run it with `dotnet <assembly>.dll` on a compatible .NET installation.
- With `--runtime`, the requested RID must equal the current host RID reported by .NET. The command adds a small framework-dependent launcher beside the `.dll`.
- Cross-runtime publishing fails before build with guidance that names both the requested RID and the current host RID.
- `--self-contained` is not implemented in `nlc publish`; it exits 1 with guidance instead of producing a directory that only looks self-contained.

### `nlc clean` — Build Artifact Cleanup

Equivalent to `cargo clean` / `go clean` for local artifacts:

```bash
nlc clean
nlc clean --all
```

- Removes `bin/`, `obj/`, `nsharp/`, and `.nlc/` directories under the project root
- `--all` also clears NuGet caches via `dotnet nuget locals all --clear`

### `nlc watch` — Re-run On Change

Watch the project tree and re-run a command after a debounce window:

```bash
nlc watch check
nlc watch build
nlc watch test --filter "should add"
```

- Watches `.nl`, `project.yml`, and `.editorconfig`
- Defaults to a 250ms debounce
- `--max-runs` is available for scripts and test harnesses

### `nlc doc` — Project API Documentation

Generate a lightweight HTML API reference directly from the project symbol graph:

```bash
nlc doc
nlc doc --open
nlc doc --json
```

- Default output directory: `./nsharp/docs`
- Generates `index.html` plus per-symbol pages
- `--json` emits a stable result envelope containing the generated paths

### `nlc query diagnostics` — Elm-Level Error Output

The richest error output of any .NET language. Every diagnostic includes source snippets, explanations, suggestions, type info, and documentation URLs.

```bash
$ nlc query diagnostics --text
── [NL202] ERROR ──────────────── Program.nl:10:12 ──
    10 |     x := "hello"
              ^^^^^^
Type mismatch: expected 'int' but got 'string'

Expected: `int`
  Actual: `string`

Hint: N# uses ':=' for declaration with inference.
Suggestion: Convert with int.Parse("hello") or change the type.
See: https://nsharp.dev/errors/NL202
```

### `nlc query symbols` — Project Overview

The first thing an LLM should call when entering a project. Returns all symbols with types, members, parameters.

```bash
$ nlc query symbols
{
  "schemaVersion": 1,
  "results": [
    {"name": "Person", "kind": "record", "file": "Models/Person.nl", "line": 4,
     "members": [
       {"name": "Name", "kind": "property", "type": "string"},
       {"name": "GetInfo", "kind": "function", "type": "string", "parameters": []}
     ]},
    {"name": "Main", "kind": "function", "file": "Program.nl", "line": 10}
  ]
}
```

---

## Systems Report Row Order

The systems report's row order is part of its schema, not an accident of iteration. One N# owner,
`src/NSharpLang.Compiler.Core/Semantics/SystemsReportOrder.nl`, declares all of it, and the whole
path from the analyzer to the user's JSON is order-preserving — the normalization and JSON kernels
each iterate their input and append in sequence, with no second sort anywhere.

| array | order | key |
|---|---|---|
| `systemsReport.functions[]` | root order of the analyzer's depth-first walk over files | file path, `OrdinalIgnoreCase` |
| `systemsReport.trustedSites[]` | file, then line, then column | file `OrdinalIgnoreCase`, then numeric |
| `systemsReport.functions[].calls[]` | de-duplicated, then ascending | callee name, `Ordinal` |

**`functions[]` is DFS root order, not file order.** The walk is re-entrant: analyzing a caller can
analyze a declared callee mid-walk, and a function is appended when its own analysis *finishes*, so
a callee row can precede its caller. Do not describe this array as "sorted by file".

`calls[]` is both de-duplicated and sorted by the same step, so a repeated callee appears once.
`Ordinal` and `OrdinalIgnoreCase` differ observably — ordinal sorts every uppercase letter before
every lowercase one — so the two comparers above are load-bearing and may not be swapped.

The same three orders are what `nlc check --systems-report`, `nlc query trusted`, `nlc query perf`
and `nlc build --perf-report` emit. `tests/native/systems-analysis-census` is the order instrument:
it spawns the real CLI and pins whole rows *by index*, including blocks whose file names are chosen
to disagree with disk order.

## Diagnostic Colour

`nlc build` and `nlc run` write human-readable diagnostics to standard error and colour them with
ANSI SGR sequences. Whether a run colours is decided by `DiagnosticColorPolicy`, in this precedence:

| # | Signal | Effect |
|---|---|---|
| 1 | `--color=always` / `--color` / `--color=yes` / `--color=force` | colour, whatever the rest says |
| 1 | `--color=never` / `--no-color` / `--color=no` / `--color=none` | no colour, whatever the rest says |
| 2 | `NO_COLOR` set and non-empty | no colour |
| 3 | `FORCE_COLOR` set and not `0` | colour, even into a pipe or file |
| 4 | *(default)* | colour when standard error is a terminal, plain when it is redirected |

`--color=auto`, and any `--color=<value>` that is not listed, fall back to row 4 rather than failing
the run. When several colour flags appear, the last one wins. An empty `NO_COLOR` is treated as
unset, per the [no-color.org](https://no-color.org) convention.

The machine-readable surfaces never colour, under any setting: `nlc check` and every `--json` output
are plain, and so is the diagnostic text embedded in a project-reference build failure's exception
message.

## JSON Schema Discipline

All `nlc check`, `nlc fix`, `nlc lint`, and `nlc tree --json` commands output JSON with a versioned envelope:

```json
{
  "schemaVersion": 1,
  "command": "<command-name>",
  "ok": true,
  ...
}
```

- `schemaVersion` is always present and will increment on breaking changes
- All project-scoped file paths are normalized to forward-slash separators
- `projectRoot` is emitted as an absolute path when the command has a project root
- Coordinates are 1-based (line 1, column 1)
- `null` fields are omitted from output

`check` envelope:
- `command`
- `projectRoot`
- `checkedFiles`
- `ok`
- `results`
- `summary`

`fix` envelope:
- `command`
- `projectRoot`
- `dryRun`
- `includeReviewNeeded`
- `ok`
- `filesModified`
- `results`
- `fixesApplied`

`lint` envelope:
- `command`
- `projectRoot`
- `lintedFiles`
- `ok`
- `results`
- `summary`

**`nlc lint` analyses the project before it lints** (`src/NSharpLang.Compiler/LintCommand.nl`, N#-owned
since the C# `LintCommand.cs` was deleted). NL010 and NL002 are answered from BINDING facts, so a lint
run that only parsed reported neither: `nlc check` printed two NL010 rows for a file with two dead
imports while `nlc lint` on the same file said "no issues". Lint now loads the project through
`CodeIntelligenceService.LoadProjectIncludingTests` exactly as `nlc fix` does and hands the ANALYSED
unit to the linter, falling back to the parsed unit for a source the project does not list. The parse
gate stays in front: a file the parser refuses is a `PARSE` row and is never linted, and that answer
does not depend on whether the snapshot loaded (analysis is best-effort and a project that fails to
load simply leaves every file on its parsed unit). No schema version change: rule rows now carry the
`docsUrl` the catalog already gave `nlc check`'s copy of the same row.

`tree` envelope (`schemaVersion: 2`):
- `command`
- `ok`
- `projectRoot`
- `project`
- `maxDepth`
- `capabilities`
- `dependencies`
- `transitiveDependencies`
- `summary`
- `limitations`

Migration note: the earlier tree JSON wrapper exposed raw `dotnet list package` output under `packages` when a `.csproj` was present. Schema version `2` replaces that with stable `dependencies` / `transitiveDependencies`, explicit `capabilities`, and project.yml support for csproj-free projects.

`query` expectations:
- Success responses include `ok: true` and command-specific payloads
- Failures use `ok: false` plus `error.message`
- Position-based misses use `error.code: "noSymbol"` plus structured `error.details.file` / `error.details.position`
- `outline` normalizes the file path relative to the project root
- Project-aware query results normalize file paths to project-relative form where the command can resolve them

`inspect` envelope:
- `command`
- `file`
- `position`
- `result.symbol`
- `result.type`
- `result.definition`
- `result.references`
- `result.completions`

`inspect --summary` envelope:
- `command`
- `file`
- `position`
- `summary`
- `summary.references.count` / `summary.references.definitionCount`
- `summary.completions.totalCount`
- `summary.completions.groupCounts`
- `summary.completions.groups`

`batch` envelope:
- `command`
- `projectRoot`
- `requestCount`
- `successCount`
- `failureCount`
- `results`
- `results[].request`
- `results[].ok`
- `results[].response`

## Local Contributor Install

Use [install-local.sh](/Users/spencer/repos/nsharplang/install-local.sh) as the contributor bootstrap. It builds packages from the current checkout, refreshes the local N# package cache, publishes `nlc` and `nsharp-lsp` as framework-dependent apps, installs launchers under `~/.nsharp/bin`, refreshes the VS Code extension when the `code` CLI is available, and writes `~/.nsharp/env` so future shells put those launchers on PATH.

```bash
./install-local.sh
```

The script:
- refreshes packages and toolset apps through the shared `scripts/lib/toolset.sh` helpers
- refreshes the local install-root package cache used by generated projects (`$NSHARP_INSTALL_DIR/packages`, defaulting to `~/.nsharp/packages`)
- packages and reinstalls the local VS Code extension by default from `./install-local.sh`
- verifies `nlc doctor --require-vscode` when the VS Code reinstall path runs

For a CLI-only reinstall while debugging packaging, use `./install-local.sh --skip-vscode --no-path-update`.

### Native front door and per-RID toolsets

`scripts/publish-toolset.sh` publishes two toolset shapes from the same sources:

| Shape | How | `bin/nlc` | `lib/nlc/Cli.dll` (compiler host) |
|---|---|---|---|
| portable (default; release archive, Docker rows) | `publish-toolset.sh` | bash/PowerShell launcher script | IL, JIT-compiled |
| per-RID | `publish-toolset.sh --rid <rid>` or `--rid host` | NativeAOT front door (on a build host of that RID; otherwise the script) | ReadyToRun for that RID (`nsharp-lsp` stays IL) |

`scripts/setup-local.sh` publishes for the host RID (`NSHARP_TOOLSET_RID=portable` opts out). The
toolset's `VERSION` records `rid=` and `nlc=native|script`.

**The front door** (`src/NSharpLang.Compiler.Driver/FrontDoor.nl`, decisions in `FrontDoorKernels.nl`)
is `Cli.csproj` published with `PublishAot=true`. `CliPipeline.Execute` first tests
`RuntimeFeature.IsDynamicCodeSupported`; under NativeAOT that is a compile-time `false`, so the AOT
compiler folds the test and trims the whole compiler out of the image (about 2.6 MB on osx-arm64,
zero trim/AOT warnings — `nsharp_publish_native_front_door` fails the publish on any `warning IL`).
The front door prints `--version`/`help` itself and, for every other command, resolves .NET in the
launcher script's order (`DOTNET_ROOT_<ARCH>`, `DOTNET_ROOT`, `dotnet` on PATH, `~/.dotnet`, the
standard install locations), exports `DOTNET_ROOT` the way the script did, and `execve`s
`dotnet lib/nlc/Cli.dll <args>`: same process id, same descriptors, signals and exit code. Windows
has no `exec`; there it starts the host on the same console and returns its exit code.
`NSHARP_FRONT_DOOR=1` forces the front-door path inside a JIT process; the host never sees it.
`tests/native/cli-command-contracts/FrontDoorContracts.tests.nl` proves the hand-off is
indistinguishable from a direct run (version, help, unknown command, check, run, test), and
`tests/native/installed-toolchain-integration/NativeFrontDoorToolset.tests.nl` publishes a real
`--rid host` toolset and drives a project through its native `bin/nlc`. The language server stays
portable IL in both shapes (a ReadyToRun server is an IDE change and needs VS Code verification).

**Why the compiler is not itself NativeAOT.** The emitter binds RUNTIME types:
`PersistedAssemblyBuilder` is created over `typeof(object).Assembly`, the plan/emit slices spell
types as runtime `typeof(...)` handles (about 3,400 sites), and `ExternalAssemblyScan` loads each
reference's implementation into the compiler's process (`AssemblyLoadContext.LoadFromAssemblyPath`,
`Assembly.Load`) to supply Reflection.Emit handles. Under NativeAOT neither in-process loading nor
the framework assemblies beyond the image exist, so every external type would stay metadata-only
and decline at emit; framework resolution (`RuntimeEnvironment.GetRuntimeDirectory()`) also points
at the app directory. `nlc test`/`nlc run` additionally load emitted assemblies into a collectible
context. All of that runs unchanged in the JIT host — the front door's `exec` IS the move to a child
process, at about 4 ms over invoking the host directly. Making the compiler AOT needs the emitter on
one metadata (`MetadataLoadContext`) type universe first.

Measured on osx-arm64 (M-series, `tests/fixtures/issue-tracker`, 534 lines; medians of paired,
interleaved runs; CPU = user+sys):

| Command | before: launcher script + JIT IL | after: front door + ReadyToRun host |
|---|---|---|
| `nlc --version` (quiet machine) | 40 ms wall (script 19 ms + host 21 ms) | 7 ms wall, 6 ms CPU |
| `nlc check` (quiet, host only) | 1,360 ms wall, 1,441 ms CPU | 950 ms wall, 979 ms CPU |
| `nlc build` (quiet, host only) | 1,026 ms wall, 1,023 ms CPU | 624 ms wall, 626 ms CPU |
| `nlc check` (loaded machine, load ≈ 23) | 4,317 ms CPU | 3,150–3,237 ms CPU |
| `nlc build` (loaded) | 2,852–2,959 ms CPU | 1,856–1,875 ms CPU |
| `nlc test --no-cache` (loaded) | 3,014–3,190 ms CPU | 1,976–2,108 ms CPU |
| unknown command (loaded; pure start-up) | 126 ms wall | 62 ms wall (direct host: 58 ms) |

The shipped portable toolset was already Release-optimized: `Cli.dll` and the seed's
`NSharpLang.Runtime.dll` carry `DebuggableAttribute(IgnoreSymbolStoreSequencePoints)` only, and
N#-emitted assemblies carry no `DebuggableAttribute` at all, so the JIT optimizes them. Even
`dev.sh`'s Debug build differs only in the 6 KB C# `Cli.dll` (`DisableOptimizations`); its
`NSharpLang.Runtime.dll` comes from the seed package and is Release, and Debug-vs-Release JIT runs
of `check`/`build` measured within noise of each other. ReadyToRun is what removes the JIT cost.

---

## Architecture

### Code Intelligence Stack

```
nlc query <cmd>
  → QueryCommand.cs (CLI dispatch)
    → CodeIntelligenceService (shared engine)
      → MultiFileCompiler.CompileForAnalysis()
        → Lexer → Parser → Analyzer
      → ProjectSnapshot (immutable analysis result)
        → CompilationUnits, SemanticModels, BindingMap, Errors
    → OutputFormatter (JSON or Elm-style text)
```

### Key Files

| File | Purpose |
|------|---------|
| `src/NSharpLang.Cli/Program.cs` | The CLI entry point, and nothing else: `Main` plus `GetVersion`. The version read cannot move — `nlc --version` and the help header must report `Cli.dll`'s own `AssemblyInformationalVersion`, and `typeof(Program).Assembly` is the only spelling that names it from inside it — so `Main` reads it and hands it to the pipeline as a value |
| `src/NSharpLang.TestHost/CliPipeline.nl` | The 26-arm command dispatch: `ProgramCommandKernels.GetCommandKind` turns the argument vector into a command number, and this is the one place that number becomes a call (N#-owned; replaced `Program.Execute`) |
| `src/NSharpLang.TestHost/TestCommandHost.nl` | `nlc test` whole: the preflight refusals, the incremental build, the choice of runner and the two output shapes (N#-owned; replaced `Program.Testing.cs`) |
| `src/NSharpLang.TestHost/XunitTestRunner.nl` | The DEFAULT runner: the two assembly-resolution hooks, xunit's front controller and the message sink that turns its messages into `NativeTestResult` rows. NOT isolated — the emitted assembly lands in the default context, which `tests/native/test-assembly-load-contexts` records |
| `src/NSharpLang.TestHost/ReflectionTestRunner.nl` | The NUnit-shaped runner, which IS isolated: it loads the emitted assembly into a private collectible `NativeTestLoadContext` and unloads it in a `finally` |
| `src/NSharpLang.TestHost/WatchCommandHost.nl` | `nlc watch`: the `FileSystemWatcher`, the debounce loop and the re-entry into `CliPipeline` (N#-owned; replaced `Commands/WatchCommand.cs`) |
| `src/NSharpLang.Compiler/CliIlBackend.nl` | The whole project/single-file route to an emitted IL assembly, and the two `run` routes that execute it. `build`, `run`, `publish`, `test` and `pack` all arrive here (N#-owned; replaced `Program.Backends.cs`) |
| `src/NSharpLang.Compiler/CliError.nl` | The one-line `Error: …` failure report — STDERR, exit 1 — shared by every command (N#-owned) |
| `src/NSharpLang.Compiler/PackCommand.nl` | `nlc pack`: metadata, build, nuspec and archive (N#-owned) |
| `src/NSharpLang.Compiler/CheckCommand.nl`, `FixCommand.nl`, `LintCommand.nl`, `DocCommand.nl` | `nlc check` / `fix` / `lint` / `doc` (N#-owned) |
| `src/NSharpLang.Cli/Commands/QueryCommand.cs` | All `nlc query` subcommands |
| `src/NSharpLang.Compiler.Driver/DaemonCommand.nl`, `DaemonCommandKernels.nl` | `nlc daemon start/stop/status/run` (N#-owned) |
| `src/NSharpLang.Compiler.Driver/DaemonProtocol.nl` | The JSON-RPC 2.0 wire types and the constants reader `DaemonConstants` (N#-owned) |
| `src/NSharpLang.Compiler.Driver/DaemonServer.nl` | The workspace server: singleton lock, accept loop, query snapshots, idle/liveness/caps, warm-up (N#-owned) |
| `src/NSharpLang.Compiler.Driver/DaemonClient.nl` | JSON-RPC client: ping/status/shutdown, `nlc daemon start`, queries (N#-owned) |
| `src/NSharpLang.Compiler.Driver/DaemonExecKernels.nl` | Every daemon-first decision as a pure function: routed commands, switches, workspace rule, build identity, launch command, wire constants, timings (N#-owned; pinned by `DaemonExecKernels.tests.nl`) |
| `src/NSharpLang.Compiler.Driver/DaemonExecClient.nl` | The client half: route, connect, stream frames, stdin pump, `run` launch, fallback, auto-start (N#-owned) |
| `src/NSharpLang.Compiler.Driver/DaemonExecHost.nl` | The server half: one command per request in the client's cwd/env/culture/console (N#-owned) |
| `src/NSharpLang.Compiler.Driver/DaemonExecWire.nl` | The exec wire: frames and the binary request encoding (N#-owned) |
| `src/NSharpLang.Compiler.Driver/DaemonLoadedReferenceGuard.nl` | Retires a server whose loaded references changed on disk (N#-owned) |
| `src/NSharpLang.Compiler.Driver/DaemonWorkspace.nl`, `DaemonWarmup.nl` | Workspace resolution + build identity; the warm-up project (N#-owned) |
| `src/NSharpLang.TestHost/TestWorkerHost.nl` | Isolated single-use test workers for server-run `nlc test` (N#-owned) |
| `src/NSharpLang.Compiler.Model/CliInvocationContext.nl` | The remote-invocation scope: client command line, stderr-is-terminal, `run` launcher, cancellation, termination (N#-owned) |
| `src/NSharpLang.Compiler.Model/WarmStateRegistry.nl` | The seam caches use to live in a long-lived host: change/trim/describe hooks (N#-owned) |
| `src/NSharpLang.Compiler.Model/AssemblyTypeNameIndex.nl` | Reference assemblies' top-level type and forwarder names, per assembly object and per file version; lets every type probe skip impossible MLC lookups (N#-owned; the one owner since speed/integration) |
| `src/NSharpLang.Compiler.Driver/WarmIncrementalSessions.nl` | The workspace server's incremental sessions, one per compilation identity (N#-owned) |
| `src/NSharpLang.Compiler/CodeIntelligence/CodeIntelligenceService.cs` | Shared analysis engine |
| `src/NSharpLang.Compiler/CodeIntelligence/CompletionEngine.nl` | LLM-optimized completions (snapshot plumbing; policy lives in `NSharpLang.Compiler.CodeIntel/CompletionEngineKernels.nl`) |
| `src/NSharpLang.Compiler/CodeIntelligence/SignatureHelpEngine.nl` | Overload signatures for a call being typed (snapshot plumbing; policy lives in `NSharpLang.Compiler.CodeIntel/SignatureHelpOverloadFacts.nl`). It resolves through the PROJECT SNAPSHOT, the same program completion asks, so an external instance or static method, a whole overload set and a type declared in another file all answer — the current document's own declaration table, which is all `textDocument/signatureHelp` used to read, could answer none of them |
| `src/NSharpLang.Compiler/CodeIntelligence/OutputFormatter.cs` | JSON + Elm-style formatters |
| `src/NSharpLang.Compiler/CodeIntelligence/FixApplicator.cs` | TextEdit application |
| `src/NSharpLang.Compiler.CodeIntel/CodeIntelligenceModels.nl` | Result types (SymbolResult, etc.) |
| `src/NSharpLang.Compiler.CodeIntel/CodeFix.nl` | TextEdit, CodeAction, CodeFixProviders |
| `src/NSharpLang.Compiler.Core/Semantics/BindingMap.nl` | Semantic symbol resolution |

### Testing

| File | What it tests |
|------|--------------|
| `tests/native/query-integration` | Real example projects, in N#: symbols, outline, diagnostics, definition, references, completions, binding map, the JSON envelopes, the shipped diagnostic-clusters golden document, unhappy paths |
| `src/NSharpLang.Compiler.Driver/OutputFormatterJsonKernels.tests.nl` | Every versioned JSON envelope and its exact ordered root keys |
| `src/NSharpLang.Compiler.Driver/OutputFormatterTextBuilders.tests.nl` | Every Elm-style `--text` answer, stated as whole texts |
| `src/NSharpLang.Compiler.Driver/OutputFormatterDiagnosticKernels.tests.nl` | Severity arithmetic, reference deduplication, end-to-end diagnostics |
| `tests/native/completion-engine` | `CompletionEngine` over real projects, reached by reflection |
| `tests/native/compile-time-bench` | The compile-time benchmark and gate: `nlc build --timings` and `nlc check --json` run as real processes under `/usr/bin/time -l` over the 68-project corpus and Compiler Core; corpus medians, lines/s, peak RSS and failing-check diagnostics are trend records. The gate always checks exact `--stats` counters and the Core phase contract; it compares paired base/head timings only when compiler product inputs change. It discards one warm-up pair, alternates order, and measures 9–17 pairs; failure requires the exact two-sided sign-test 95% lower bound for median head/base ratio to be >1.20× and median slowdown ≥30 ms/command. A no-compiler-change run says `timing: not compared`; see `memory/testing.md` §8. It also owns `--agent-loop`: no-op, body-edit, signature-edit and new-file scenarios through `check`/`build`/`test`, with exact `--stats` counters over small/medium/large fixtures; see §8a for measured rows and gate policy. |
| `tests/native/systems-proof-corpus` | `nlc build --perf-report`, `nlc check --systems-report` and `nlc query trusted` over the 21 shipped proof projects under `docs/design/systems-samples/proofs`, each SPAWNED AS A REAL PROCESS, plus the emitted assemblies executed as processes |
| `tests/native/systems-analysis-census` | The systems policy corpus answered by a SPAWNED `nlc check --project … --systems-report`: 54 fixture projects written, checked and deleted per block, plus `build --perf-report`, `query perf` and `query trusted` on temporary projects. Whole envelopes, whole finding rows, whole function summaries and the diagnostic census |
| `tests/native/systems-gauntlet-facts` | The ten `tests/fixtures/systems-gauntlet` cases against their four goldens each, plus the facts no CLI surface exposes: return lifetimes, scoped parameters, ref-struct-ness and the `Result<T, E>` runtime ABI |
| `tests/native/cli-command-contracts` | The shipped CLI's own contracts, SPAWNED as real processes: `--help` for FOURTEEN commands (`tree`/`clean`/`env`/`audit`/`doctor`/`daemon` plus `check`/`fix`/`lint`/`watch`/`format`/`tidy`/`doc`/`completion`), the `nlc tree` and `nlc env` JSON envelopes, the missing-project stderr routes for `check`/`fix`/`lint`/`doc`/`watch` and the argument refusals for `watch`/`format`/`test`/`completion` (which double as the anti-vacuity controls for every silence claim), the `nlc test --timeout` refusal on BOTH the text and the JSON route, **the whole `nlc query batch` envelope** (per-item results with the request echoed back, each response its own versioned envelope, the five per-request validation refusals with their codes, position parsing, and all four requests-file failures as top-level `invalidRequestsFile` errors), **the command registry's sync with `nlc help` / `nlc query help` / the generated zsh script / `website/docs/cli-reference.md`**, and top-level dispatch (`nlc help`, `--version`, an UPPERCASE command, an unknown command, `query help` / `query wat`), **and the six dependency/housekeeping commands proven as PROCESSES** — `nlc add` (help vs failure usage, the missing-project remedy, inline insertion with its indentation, both duplicate arms), `nlc update` and `nlc remove` (help, missing project.yml, missing package — the same sentence word for word), `nlc tidy` (help, the text and JSON missing-project sentences which DIFFER, the three-status classification, and the `ok`-vs-exit-code split), `nlc clean` (the ordered removal listing) and `nlc completion bash` (the script shape and all 27 command names). **Since 021/7 it also pins the two decisions that RETIRE WITH A C# SUBJECT** — `nlc query ast`'s compilation-unit ORDER (ordinal, so every capital sorts before every lowercase, on a fixture that separates `Ordinal` from `OrdinalIgnoreCase`, plus a stability row) and `nlc format --diff`'s git-style `a/PATH` / `b/PATH` labels (including the nested-path control, the already-formatted negative, and the invented `stdin.nl` name on both arms of `--stdin`). Both are observed through the SHIPPED BINARY, so they outlive whatever implements them |
| `src/NSharpLang.Compiler.Core/<slice>/*CommandKernels.tests.nl` (all in `src/NSharpLang.Compiler.Driver/` but `CompletionCommandKernels`, in `src/NSharpLang.Compiler.CodeIntel/`) | The per-command option summaries, output modes and user-facing sentences, called directly in the estate: `TreeCommandKernels`, `CleanCommandKernels`, `EnvCommandKernels`, `AuditCommandKernels`, `DoctorCommandKernels`, `DaemonCommandKernels`, `RunCommandKernels`, `InitCommandKernels`, `ProgramCommandKernels`, `QueryCommandKernels` (parsing and messages), `BatchQueryKernels`, `DefineArgumentKernels`, `PositionalArgumentKernels`, `CleanArtifactDirectoryOrderer`, `TestCommandKernels`, `WatchCommandKernels`, `TidyCommandKernels`, `DocCommandKernels`, `FixCommandKernels`, `FixCommandArgumentKernels` + `CheckCommandKernels` (one file, one production file), `LintCommandKernels`, `FormatCommandKernels`, `RestoreCommandKernels`, `NewCommandKernels`, `AddCommandKernels`, `RemoveCommandKernels`, `UpdateCommandKernels`, `CompletionCommandKernels`, `CompilationBackendSelectionKernels`, `CommandRegistry`, `PackCommandKernels`, and `BuildCommandKernels` (021/6). **Since 021/6 these also carry the RUNNER and COMMAND vocabulary the CLI used to spell for itself**: `TestCommandKernels`'s outcome words and the rank table defined from them, the invariant `F3` duration and `F0` elapsed formats, the verbose classification, the ordered pre/post lifecycle names the discovery predicate is defined from, the xUnit runner-error identity, the display-name preference, the failure-message join, the test build configuration and the output-mode ordinals; `BuildCommandKernels`'s `Release`/`Debug` names (which `ShouldApplyDebugDefine` is defined from) and its build exit code; `LintCommandKernels`'s two hand-built diagnostic codes (`LINT`, `PARSE`), the error severity defined from `GetSeverityText`, the command name and the parse-error join; and `WatchCommandKernels`'s 250 ms debounce default and its change-line time format |
| `src/NSharpLang.Compiler.Core/Model/CompilationReferenceResolverKernels.tests.nl` | The reference resolver's selection and parsing kernels: the reference-type filter, the best-score selector and its count bound, the shared-framework candidate over `Version[]`, the two NuGet version selectors, the path-segment probe, the dependency-version range normaliser, the target-framework parser and the framework compatibility score |
| `src/NSharpLang.Compiler.Driver/CliDependencyAndSymbolFilters.tests.nl` | The three pure static filters with no command wrapper: `UpdateDependencyFilter` (all-NuGet and case-insensitive target selection), `CompilerErrorSeverityFilter` (the error/warning partition) and `QuerySymbolNameFilter` (substring, leading-star, trailing-star and interior-star glob matching, the limit, and the two non-ASCII refusals) |
| `src/NSharpLang.Compiler.Driver/RestoreCommandGeneratedProps.tests.nl` | `nlc restore` end to end over a real two-project tree: project-reference deduplication in `obj/project.g.props`, the project's own `OutputType`/`AssemblyName`/`TargetFramework` facts, the exclusion of NuGet and framework dependencies, the recursion into a referenced project, and the exit-1 arm for a directory with no `project.yml` |
| `src/NSharpLang.Compiler.CodeIntel/UnifiedDiff.tests.nl` | The unified diff `nlc fix --diff` and `nlc format --diff` print: the two-line file header, the `@@ -old,count +new,count @@` arithmetic (with the old and new sides varied INDEPENDENTLY, which the deleted C# example's symmetric counts hid), the three line prefixes, the merge rule that joins two edits whose context windows touch, the identical-input short circuit to `""`, and the CRLF normalization |
| `src/NSharpLang.Compiler.Driver/NSharpInstallRoot.tests.nl` | What `nlc new` writes into a project's NuGet feed: the three arms (`%NSHARP_INSTALL_DIR%/packages` for an explicit override, `%HOME%/.nsharp/packages` for the default root, a real `<root>/packages` path for a detected custom toolset) and each of the three detection conditions — `bin/`, `packages/`, and a parent directory named `lib` case-insensitively — separated |
| `src/NSharpLang.Compiler.Driver/ProjectReferenceResolver.tests.nl` | How a `project:` dependency becomes something MSBuild can reference: the four MSBuild arms in order (a `.csproj` returned unchanged, the csproj named for `name:`, a single csproj of any name, the DIRECTORY-named csproj) and the refusal when two wrongly-named candidates remain; plus the N# project-root arms. The named-vs-single order was MEASURED to be unobservable and is recorded as such |
| `src/NSharpLang.Compiler.Core/Model/AstChildrenCore.tests.nl` | The skipped-subtree guard, as a SOURCE CENSUS rather than reflection (`Assembly.GetTypes()` declines at emit): every `class X: Expression` in `Expressions.nl` has a dispatch arm or is a declared leaf, every Expression-typed slot is named by its arm, no arm names a slot the node does not declare, and each of the five aggregates' slots is read by the helper that walks it — paired with runtime blocks over `StackAllocExpression.LengthExpression` and `NewExpression.ArrayLengthExpression`, the two children that shipped unvisited twice |
| `src/NSharpLang.Compiler.Driver/DaemonServerAndClientKernels.tests.nl` | The daemon protocol's user-facing text: the client's four failure sentences and the server's protocol refusals, lifecycle traces, project-loading traces, file-watcher traces and malformed-parameter trace. **Since 021/7 it also carries THE WIRE ITSELF** — the twelve method names and their exact dispatch (near misses included), the five JSON-RPC error codes, the `2.0` protocol version the error envelope is built from, that envelope's exact bytes, the `daemon/status` payload's exact bytes and member order, the five status field kernels the payload is composed from, the two control results as JSON-*encoded* strings, the socket/pid file names, the three timeouts, the uptime format, and the 100-byte socket-path budget. Before that slice, **not one of the five error codes was asserted anywhere in the repository** |
| `tests/CodeIntelligenceTests.cs` | One residual case: the culture-invariant severity fallback |
| `src/NSharpLang.Compiler.CodeIntel/CodeFix.tests.nl` | `CodeFixService`, its six providers and `CodeFixActionHelpers`; every edit proved by applying it |
| `src/NSharpLang.Compiler.CodeIntel/FixApplicatorCore.tests.nl` | Applied source as whole text; every rejection as its whole message, naming the blamed edit |
| `src/NSharpLang.Compiler.CodeIntel/FixApplicatorTextEditOrderer.tests.nl` | The five ordering keys in isolation, plus a 200-list differential sweep against an independent oracle |
| `src/NSharpLang.Compiler.CodeIntel/FixApplicatorValidationMessages.tests.nl` | The five rejection sentences and the error-slot clamp |
| `src/NSharpLang.Compiler.CodeIntel/FixApplicatorEditEngine.tests.nl` | The raw return codes, the error slots, the three line-ending arms, the malformed-call guard |
| `src/NSharpLang.Compiler.Driver/DiagnosticGoldenSuite.tests.nl` | The curated top-25 corpus (24 diagnostics) pinned against `tests/fixtures/diagnostics/` |
| `src/NSharpLang.Compiler.Core/Model/ProjectFileParser.tests.nl` | Whole `project.yml` documents in, every field read back; all nine validation refusals and the four file-not-found sentences as whole messages; the generated template pinned whole |
| `src/NSharpLang.Compiler.Core/Model/ProjectConfigModels.tests.nl` | `ProjectConfig`'s defaults and the recursive source walk — all twelve skipped directory names one at a time, plus kept neighbours as controls |
| `src/NSharpLang.Compiler.Core/Model/ProjectSourceFileFilter.tests.nl` | The exclude-glob engine arm by arm (`*`, `**/`, `?`, backslash normalisation, case sensitivity) and the `.tests.nl` suffix rule |
| `src/NSharpLang.Compiler.Core/Model/Reference.tests.nl` | The four dependency kinds, their precedence, `HasValue`, and `Validate` against the disk |
| `src/NSharpLang.Compiler.Core/Model/AssemblyVersionUtilities.tests.nl` | Package version → four-part assembly version, and the component kernel as a pinned table |
| `src/NSharpLang.Compiler.CodeIntel/ExampleProjectCorpus.tests.nl` | All nineteen shipped `examples/` projects walked through the compiler's own discovery, parser and linter — directories REQUIRED, file counts pinned |
| `src/NSharpLang.Compiler.CodeIntel/LinterFileImportUsage.tests.nl` | NL010 on a file import: resolved against the disk, spans over the quoted path, two imports tracked separately |
| `src/NSharpLang.Compiler.CodeIntel/LinterNamespaceImportUsage.tests.nl` | NL010 on a namespace import: the credited/uncredited decision, the unanalysed and incomplete-analysis gates, and the arithmetic that turns a written spelling plus a resolved identity into the supplying namespace |
| `tests/native/census-import-usage` | NL010 and NL002 end to end through the shipped `nlc`: every channel a name can reach an import through (type position, static receiver, attribute, extension method, declared member type, type argument, alias, inaccessible name), each paired with a removal control that builds |
| `tests/native/language-server-diagnostics/RecoveryAndLinterDiagnostics.tests.nl` | The converted-language-server census: NL010 on aliased and fully qualified imports, NL020 across an initializer boundary, NL012 through a lambda capture and NL002 for a name an implicit C# using used to supply — all through `DocumentManager`, the surface the editor shows |

---

## Workspace Server (daemon-first CLI)

**Every compiler-bound command is answered by a warm per-workspace server when one is available.**
`nlc check`, `build`, `test`, `run`, `format`, `lint` and `fix` ask the server first
(`CliPipeline.Execute` → `DaemonExecClient.TryExecute`) and run in-process only when it declines.
The first such command in a workspace runs in-process and starts the server in the background
(`nlc daemon run --project <workspace> --background`); every later command finds it warm. Before
2026-10-05 only `nlc query` used the daemon, and only when it had been started by hand.

```bash
nlc check            # first: in-process; starts the server in the background
nlc check            # later: the warm server answers
nlc daemon status    # {"pid":…,"identity":"…","servedRequests":…,"workingSetMb":…,"warmState":[…]}
nlc daemon stop
```

### Design

| Concern | Decision | Owner |
|---|---|---|
| Which commands route | `check`, `build`, `test`, `run`, `format`, `lint`, `fix` (case-insensitive); `query` keeps its own JSON-RPC route; `watch`, `new`, `daemon`, … never route | `DaemonExecKernels.IsRoutedCommandName` |
| Switches | `--no-daemon` (stripped before the command sees it); `NLC_NO_DAEMON` (any value but empty/`0`); `NLC_DAEMON_CHILD` (set for everything the server runs and for every test run); `CI=true\|1` unless `NLC_DAEMON=1` | `DaemonExecKernels.ShouldRoute` |
| Workspace | Looked for from the command's `--project` (else the current directory): nearest ancestor with `.git` (dir or worktree file), else nearest `project.yml`; neither → in-process, no `.nlc/` created. `nlc daemon start/stop/status` fall back to the directory itself | `DaemonExecKernels.ResolveWorkspaceRoot` |
| Identity | FNV-1a 64 over: exec protocol version, informational version (commit), `AppContext.BaseDirectory`, name+size+mtime of every `*.dll` there, runtime version, every `DOTNET_*`/`COMPlus_*` variable. Mismatch → client stops the old server, runs in-process, spawns a new one | `DaemonExecKernels.ComposeIdentitySource`, `DaemonBuildIdentity` |
| Launch | The SAME binary: `dotnet <entry Cli.dll> …` under the muxer, the apphost/native image itself otherwise (the old `dotnet run --project src/NSharpLang.Cli` plan is gone). Fresh pipes for all three streams so a caller reading our stdout to EOF never waits on the server | `DaemonExecKernels.GetServerLaunchCommand`, `DaemonAutoStart.Spawn` |
| Singleton | `.nlc/daemon.lock` held with `FileShare.None` (flock) for the server's life; a second server of the same build exits, a newer build waits ≤30 s for the old one to stop | `DaemonServer.AcquireServerLock` |
| Spawn storm guard | `.nlc/daemon.spawn` marker: no second spawn within 10 s unless the last spawned server came up (PID file newer) and has since died | `DaemonAutoStart.Spawn` |
| Execution | ONE command at a time per server (cwd, environment and console are process-wide). The request carries args, the full `GetCommandLineArgs()`, cwd, the complete environment (applied exactly — extra server variables are removed — and restored afterwards), culture/UI culture, and whether stdout/stderr/stdin are redirected. The command runs through the same `CliPipeline.ExecuteLocal` dispatch inside `InternalErrorBoundary` | `DaemonExecHost.Execute` |
| Busy | A request that cannot take the work lock within 250 ms is answered `Busy` and the client runs in-process (two agents never queue behind a long test run) | `GetBusyWaitMilliseconds` |
| Process facts a command reads | `--color=` from the CLIENT's command line and the CLIENT's stderr-is-terminal (`DiagnosticColorPolicy`), `nlc run`'s program started by the client (`DotnetRunner.RunPassthrough`) | `CliInvocationContext` |
| Output | Every `Console.Out`/`Console.Error` write is one frame, both streams through one send lock, so cross-stream order is preserved; one stateful UTF-8 encoder per stream (`DaemonFrameWriter` derives from `StringWriter` because the seed cannot yet emit an override of `TextWriter.Encoding`, an abstract property) | `DaemonFrameWriter` |
| Stdin | Pulled lazily: nothing is read from the user's terminal/pipe until the command reads `Console.In` (`format --stdin`) | `DaemonStdinReader`, `StartStdinPump` |
| Tests | Built in the server, RUN in a single-use test worker (`nlc __test-worker`, a hidden dispatch of the same binary), pre-spawned so it is warm. The worker adopts the request's cwd/env/culture, runs `TestCommandHost.RunRunnerInProcess`, writes results to a temp file (atomic rename + end marker). A worker that dies without results ends the request with ITS exit code (`CliInvocationContext.Terminate`), which is what that death does to an in-process `nlc test`; the server is untouched | `TestWorkerHost` |
| Test environment | `NLC_DAEMON_CHILD=1` during every test run on BOTH routes, so a test that runs `nlc` never starts or queues on a server and observes the same environment either way | `TestCommandHost.RunRunnerInProcess` |
| Cancellation | Client SIGINT/SIGTERM: commit buffered output, send `Cancel`, then die by the signal exactly as in-process (`-2`/`-15`). Server kills registered children (test workers) and, if the command is still running after 10 s, removes its socket and exits | `DaemonClientSession.OnInterrupt`, `DaemonServer.RetireIfStillRunning` |
| Server loss | Keep-alive every 1 s; no frame for 15 s = frozen (the client kills that PID). EOF/freeze before `Done` → one stderr line `nlc: the workspace server stopped responding; running in-process instead (…)` and an in-process rerun. Output is held for the first 1.5 s / 64 KB, so an early loss prints only the rerun's output. After `nlc run` launched the program, its exit code stands (the program is never run twice) | `DaemonClientSession.Lose` |
| Detachment | A server any `nlc` launched (auto or `daemon start`) gets fresh pipes for stdin/stdout/stderr (every other descriptor is close-on-exec), ignores SIGINT/SIGHUP (the launching terminal's process group), and stops gracefully on SIGTERM — the managed equivalent of `setsid`. A hand-typed `nlc daemon run` keeps default signals | `DaemonServer.Run`, `DaemonClient.StartDaemon`, `DaemonAutoStart.Spawn` |
| Lifecycle | Idle timeout (default 30 m, `NLC_DAEMON_IDLE_TIMEOUT`; never while a request runs), liveness (socket file gone → exit within 2 s), memory cap (default 4096 MB, `NLC_DAEMON_MAX_MEMORY_MB`: trim warm state, GC, retire if still over), SIGTERM graceful (in-flight requests finish), background servers ignore SIGINT/SIGHUP. The accept loop POLLS (500 ms): on macOS `close()` does not wake a thread blocked in `accept(2)` | `DaemonServer` |
| Stale references | The compiler loads executable handles for references (packages, `project:` outputs) into non-collectible contexts. MEASURED: rebuild a referenced library with a new member and a long-lived compiler's emitter still sees the old one. So the server records every loaded assembly file outside the runtime and CLI directories, checks them before each command, and on any change declines (client runs in-process) and retires; the next command starts a fresh server. A project's OWN output changing does not trigger it. The language server had the same defect in its long-lived analyzer and snapshot cache (a rebuilt library's new type stayed "not found" until restart) and uses the same version table (`ReferenceFileVersions`): its `DocumentManager` records every file its analyzer's metadata context read and, before a document is analysed or a snapshot is served, replaces the analyzer and drops the snapshots and type catalog when one changed (`tests/native/language-server-diagnostics/ReferenceRebuild.tests.nl`) | `DaemonLoadedReferenceGuard`, `ReferenceFileVersions` |
| Warm-up | A new server compiles a small built-in project (`check` + `build`, output discarded) under the work lock before taking work, then pre-spawns a test worker (`NLC_DAEMON_WARMUP=0` skips). `daemon/status` reports `"warm"`, and `nlc daemon start` returns only once it is true | `DaemonWarmup`, `DaemonExecHost.RunWarmupHooks` |
| Warm state | Kept across commands: JIT, `AssemblyTypeNameIndex` (each reference's top-level type/forwarder names, per assembly object and per FILE VERSION — lets every type probe skip MLC misses, which build and discard a localized `TypeLoadException`; registered as `reference-type-names`), the incremental sessions (`WarmIncrementalSessions`, registered as `incremental-compilations`: a warm check/build re-analyses only what an edit reaches), query snapshots per project. Any cache can join via `WarmStateRegistry.Register(name, onPathChanged, onTrim, describe)`; the server feeds it file-watcher changes, trims it before a memory retirement and lists it in `warmState` | `WarmStateRegistry` |
| Queries | `nlc query` reaches the WORKSPACE server, passes `projectRoot` and its `identity`; a different build answers `-32001` and the query runs in-process. The server keeps one snapshot per project, dropped on any watched change | `QueryCommand.TryExecuteViaDaemon`, `DaemonServer.EnsureSnapshot` |
| Security | Socket `0600` after bind (connect needs write permission); fallback runtime dirs created `0700`; nothing listens on TCP | `DaemonServer.RunWithSignals`, `DaemonProtocolKernels.GetSocketPath` |
| Scripts | `scripts/dev.sh` and `tests/scripts/test-all-core.sh` default `NLC_NO_DAEMON=1` for their own commands (parallel batches gain nothing; the in-process path is the reference). `NLC_NO_DAEMON=0 ./scripts/dev.sh …` exercises the server | — |
| Tracing | `NLC_DAEMON_TRACE=1` → one `[nlc-daemon] route=<daemon\|in-process> resolve= identity= connect= send= accepted= done= client-ms= process-ms=` line on stderr | `DaemonClientTrace` |

**Measured (2026-10-05, paired alternating runs, 10 each, `bench.py` in the session scratchpad;
machine under load — 1-min load average 12-15 on 10 cores — so absolute numbers are inflated, the
ratio is the signal).** 534-line `tests/fixtures/issue-tracker` (ASP.NET framework reference, ~180
reference assemblies):

| Command | in-process median | daemon median | speedup |
|---|---|---|---|
| `check` | 2.60 s | 0.63 s | 4.1x |
| `build` | 2.68 s | 0.50 s | 5.4x |
| `test` | 2.47 s | 0.62 s | 4.0x |
| `lint` | 1.04 s | 0.26 s | 3.9x |
| `format --check` | 0.13 s | 0.08 s | 1.5x |

`nlc run` of a small exe through the server: ~0.17 s client wall time including the program.
Client-side overhead per routed command ≈ 40 ms runtime start + ≈ 35 ms routing (resolve, identity,
connect, request); the rest is server-side compiler work. Both follow-ups this table pointed at have
landed on `speed/integration`: `check` analyses once (`EmitAnalyzedAssembly`, since `speed/agent-loop-2`
`ValidateAnalyzedEmission`, which writes nothing), and the server holds
the incremental sessions, so a routed check after a body edit re-analyses one file (the agent-loop
benchmark's `--daemon` table in `memory/testing.md` §8a has the measured loop).

### Native rows

`tests/native/daemon-exec` (23 rows, real processes against a real server): routing and auto-start,
switches (`--no-daemon`, `NLC_NO_DAEMON`, `CI`), no-workspace, parity over success/error/JSON/text/
`--color=always`/failing tests/`--verbose`/`--filter`/`format --stdin`/`run` with stdin and exit code,
per-request env and cwd, `Environment.Exit` and stack-overflow isolation, server killed mid-command,
build-identity replacement (a `DOTNET_` variable makes the other build), a `project:` dependency rebuilt under a running server, two clients at once,
SIGTERM cancellation of a hung test, status/stop, idle timeout, workspace deletion, memory cap,
owner-only socket, warm incremental re-analysis (a body edit re-analyses one file, a signature edit that file and its caller, with in-process parity), `nlc daemon start` outside any repository returning while a caller reads its output to EOF (both bugs the agent-loop benchmark reported against the old start path: `dotnet run --project src/NSharpLang.Cli` outside the repo, and the server inheriting the caller's stdout), and a launched server ignoring SIGHUP/SIGINT but stopping on SIGTERM. Kernel and wire contracts: `DaemonExecKernels.tests.nl`,
`DaemonServerAndClientKernels.tests.nl`, `DaemonCommandKernels.tests.nl` (Driver);
`CliInvocationContext.tests.nl`, `WarmStateRegistry.tests.nl`, `AssemblyTypeNameIndex.tests.nl`
(Core/Model).

### Daemon start, socket and log

Socket: `{workspace}/.nlc/daemon.sock` (falls back to `{TMPDIR}/nlc-daemon/{sha256-16}/daemon.sock` when the project-local path would exceed **100 UTF-8 bytes**, because a Unix domain socket path is capped near 104 bytes by the kernel; the hash is computed only for that fallback)
PID file: `{workspace}/.nlc/daemon.pid`; lock: `.nlc/daemon.lock`; spawn marker: `.nlc/daemon.spawn`
Protocols: the exec wire (below) and JSON-RPC 2.0, on the same socket, told apart by the first byte

`nlc daemon start` waits up to **120 seconds** for the spawned process to answer `daemon/ping` on
its socket. The wait polls every 100 ms and returns as soon as the daemon responds; it does not
wait a fixed startup duration. If the child exits first, startup fails immediately with its exit
code. If the deadline expires, startup fails with the elapsed time, socket path, whether the child
was still alive, and the last daemon output. Both diagnostics include the last captured output
lines (up to 20 from captured stderr and, when available, the last 20 from the daemon log). The
timeout form begins `Startup timed out after <milliseconds> ms waiting for daemon/ping to be
accepted at <socket>. Child process alive: <true|false>.`; early exit begins `Startup failed after
<milliseconds> ms: child process exited with code <exit-code> before daemon/ping was accepted.
Child process alive: false.`

Every server start (explicit or automatic) truncates `.nlc/daemon.log`. An explicit start's initial
diagnostics go to the launching process's captured stderr and later output to the log; an automatic
(`--background`) server writes everything to the log from its first line. When the socket falls back
to `{TMPDIR}/nlc-daemon/{sha256-16}/`, the log sits beside it. `.nlc/` is runtime state and should not
be committed. All shipped templates include `.nlc/` in their `.gitignore`.

### The exec wire

An exec connection opens with the four bytes `NLX1`; then frames `[kind: 1 byte][length: int32 LE][payload]`
(payload ≤ 16 MiB). Strings in the request are `BinaryWriter` strings (7-bit length + UTF-8): no JSON on
the client's cold path. Protocol version `1` is part of the build identity.

| Direction | Frame | Payload |
|---|---|---|
| client → server | `R` request | protocol, identity, args, command line, cwd, env names/values, culture, UI culture, stdout/stderr/stdin redirected, client pid |
| | `I` stdin data / `Z` stdin end | bytes / — |
| | `X` cancel | — |
| | `C` child exit | int32 exit code of the program `nlc run` launched |
| server → client | `A` accepted / `B` busy / `M` mismatch | server pid / — / server identity |
| | `O` stdout / `W` stderr | bytes, in write order |
| | `Q` stdin wanted | — |
| | `P` launch | `dotnet` arguments + working directory (for `nlc run`) |
| | `K` keep-alive | — (every 1 s while a command runs) |
| | `D` done | int32 exit code |

### The JSON-RPC wire contract (queries and control)

Every request and response is one JSON-RPC 2.0 message, sent and then half-closed. The envelope's own
member names — `jsonrpc`, `id`, `method`, `params`, `result`, `error`, `code`, `message`, `data` — are
the specification's, and they live on `[JsonPropertyName]` attributes in the N#-owned
`src/NSharpLang.Compiler/DaemonProtocol.nl`. (That file used to be C#, on the reasoning that an
attribute argument must be a compile-time constant and so could not be produced by a kernel call.
The constraint is real; the conclusion was not. N# takes `[JsonPropertyName("jsonrpc")]` on a
property, emits it, and `System.Text.Json` honours it in both directions — so the wire types are
N# and the fixed names are still written exactly once each.) **Everything the specification does not
fix is owned by
`src/NSharpLang.Compiler.Driver/DaemonProtocolKernels.nl` and pinned block by block in
`DaemonServerAndClientKernels.tests.nl`:**

| decision | owner | value |
|---|---|---|
| protocol version | `GetJsonRpcVersion()` | `2.0` — read by both DTO initializers and by `ErrorResponseJson` |
| the twelve methods | `GetPingMethod()` … `GetInspectMethod()` | `daemon/ping`, `daemon/shutdown`, `daemon/status`; `query/symbols`, `query/batch`, `query/outline`, `query/diagnostics`, `query/type`, `query/definition`, `query/references`, `query/completions`, `query/inspect` |
| method dispatch | `GetMethodKind()` | exact match — no prefix, no case folding; anything else is `Unknown` |
| the five error codes | `GetParseErrorCode()` … `GetInternalErrorCode()` | `-32700`, `-32600`, `-32601`, `-32602`, `-32603` |
| the `daemon/status` payload | `StatusResultJson()` | `pid`, `uptime`, `projectRoot`, `cachedFiles`, `idleTimeout`, in that order — each name spelled once, by its own field kernel — then, for a workspace server, `version`, `identity`, `activeRequests`, `servedRequests`, `workingSetMb`, `memoryCapMb`, `warmState` |
| build-identity mismatch | `GetIdentityMismatchErrorCode()` | `-32001` (server-defined range): a query carrying another build's `identity` |
| the two control results | `GetPongResultJson()`, `GetShutdownResultJson()` | `"pong"`, `"shutting down"` |
| socket and pid names | `GetSocketDir()`, `GetSocketName()`, `GetPidFileName()` | `.nlc`, `daemon.sock`, `daemon.pid` |
| timeouts | `GetIdleTimeoutMinutes()`, `GetConnectionTimeoutMilliseconds()`, `GetPingTimeoutMilliseconds()` | 30 minutes, 5000 ms, 2000 ms |
| uptime and idle-timeout text | `FormatUptime()`, `FormatIdleTimeoutMinutes()` | `1h 2m 3s`, `30m` |

**`result` carries JSON-encoded JSON.** It is typed as a string end to end, so every payload travels
as JSON *text inside* a JSON string — `daemon/ping` answers the six characters `"pong"`, and
`daemon/status` answers a document that a client parses a second time. `nlc daemon status` prints
that inner document verbatim, which is why the CLI never needs a status DTO of its own.

---

## Comparison with Go and Rust

| Feature | Go | Rust | N# |
|---------|-----|------|----|
| Fast type-check | `go build` | `cargo check` | `nlc check` |
| Auto-fix | — | `cargo clippy --fix` (lints) | `nlc fix` (compiler + linter) |
| Release build | implicit | `cargo build --release` | `nlc build --release` (Release configuration/output layout; no separate IL optimizer yet) |
| Verbose build | `go build -v` | `cargo build -v` | `nlc build --verbose` |
| Build timing | external (`time`) | `cargo build --timings` | Built-in (always shown) |
| Test coverage | `go test -cover` | `cargo tarpaulin` | Planned native coverage; `nlc test --coverage` exits 1 with guidance today |
| Code intelligence CLI | Need `gopls` server | Need `rust-analyzer` server | `nlc query` (single-shot JSON) |
| Structured output | No | No | Yes (versioned JSON schemas) |
| Canonical format | `gofmt` | `rustfmt` | `nlc format` |
| Elm-level errors | No | Good but no JSON | `nlc query diagnostics` |

---

*Last Updated: 2026-03-30*
