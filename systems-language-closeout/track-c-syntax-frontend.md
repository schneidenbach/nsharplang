# Track C — syntax authority and front-end pipeline

**Live status:** per-file planning, construction, source-id stamping, decline provenance, and
multi-file routing are complete through `6382af774`. Syntax-diagnostic kernels are partial and
unconsumed; `Parser.cs` still owns product syntax diagnostics and has not shrunk.

## Mission

Make the consolidated N# parser the sole syntax-diagnostic authority, preserve exact recovery and
diagnostic behavior, flip every product/IDE consumer, and remove C# reporting ownership. The C#
Parser may remain temporarily as a silent AST/recovery producer only for consumers not yet
retargeted by D/G; it cannot remain a diagnostic authority or fallback.

## Live topology and hazards

- Parser kernels are statically bound in one file:
  `src/NSharpLang.Compiler.BootstrapServices/CompilerServices/ColumnarParserKernels.nl`.
  Historical `ParserExpressions.nl`, `ParserDeclarations.nl`, and `ParserColumnar*.nl` paths no
  longer exist. C, F1, G formatter trivia, and language coverage contend on this file.
- `ColumnarSyntaxDiagnostics.nl`, `ParserDiagnosticMessages.nl`, and
  `ParserDiagnosticsTable.nl` exist. The candidate calls `Lexer` and runs independent collectors;
  it has no production consumer and no direct ordered full-tuple parity suite. Existing Parser
  tests therefore do not prove it.
- The original architecture required diagnostics to share the columnar scanner/parser state and
  allocate lazily on errors. Before adding families, either integrate the candidate into that
  state or approve a replacement architecture with the same one-parse, one-authority, recovery,
  clean-path allocation, and performance properties. Two parser-like decision engines are not
  an acceptable end state.
- Node kind 57 is occupied by `CheckedContextExpression`; the in-flight range slice claims 69.
  Always allocate from the live consolidated ledger and update every producer/consumer in the
  same commit.
- `FormatSafe` is C's syntax-consumer responsibility: its parse-error refusal gate must use the
  N# authority before `ParseResult.Errors` disappears. Its temporary AST/idempotence comparison
  is removed later with G's formatter/front-end re-host.
- `Analyzer.cs` is D's exclusive file. C supplies the stable syntax API and parity oracle; D
  retargets the imported-file wrapper in a D-owned commit.

## Required diagnostic contract

For every file, preserve ordered full tuples:

- diagnostic code/id, message, severity;
- file, 1-based line/column, span length, source snippet;
- human explanation, hint, suggestions;
- panic-mode suppression and reset boundaries;
- delimiter/EOF/literal/interpolation recovery;
- forced progress and declaration/statement synchronization;
- parser recovery shape needed by mid-keystroke Analyzer/LSP consumers.

Syntax errors, unsupported-yet declines, and unexpected compiler faults are three distinct
outcomes. A syntax error cannot become a decline; an unexpected fault cannot become either.

## Standing harness

Build one direct differential suite before more implementation:

1. run the current C# `Lexer`/`Parser` diagnostic path;
2. run the exact N# candidate entry point being proposed for production;
3. compare ordered full tuples over all invalid ParserError/Parser recovery fixtures;
4. parse all repository `.nl` source as a clean corpus and compare empty/ordered results;
5. parse deterministic line-boundary prefixes and adversarial incomplete-edit cases;
6. measure clean-path allocations and throughput so diagnostic readiness does not erase the
   columnar parser's performance value.

Use `./scripts/dev.sh ColumnarParserDiagnostics`, Parser, DiagnosticGolden, Check, and the
smallest affected suite. After a production route changes, run the full VS Code-enabled product
gate, extension reload, computer-use visual verification, and screenshots at that commit.

## Remaining waves

### C2a — direct parity harness and architecture decision

Add tests that call `ColumnarSyntaxDiagnostics.ParseFile` directly; prove they fail for a
deliberate candidate defect so the harness cannot be vacuously green. Cover invalid, clean,
prefix/recovery, CRLF/LF, multi-error, interpolation-hole, nested-generic `>>`, delimiter EOF,
reserved-keyword, and partial declaration/statement cases.

Then choose and record one design:

- preferred: diagnostic state/table/message materialization integrated into
  `ColumnarParserKernels.nl`; or
- replacement: a single N# parse entry that demonstrably shares tokenization/recovery state,
  allocates nothing material on the clean path, and does not duplicate grammar decisions.

Delete or fold the losing candidate; do not preserve two implementations for comparison after
the decision commit.

### C2b — diagnostic state, recovery, and first families

Implement one diagnostic table/materialization funnel. Allocate the next free error-node kind
from the live ledger only if recovery requires an error node. Port panic-mode lifecycle and
synchronization before family breadth; otherwise error counts/order will never match.

Start with the core consume/expected-token/EOF family and reserved-keyword-as-name family. N#
owns all text, source mapping, snippets, hints, and suggestions. C# receives final
`CompilerError` records only.

Each commit unit ports one coherent family, grows the direct parity corpus, and leaves the old
C# path authoritative until the whole C2 gate is green.

### C2c — remaining families

Port in dependency order:

- declaration/member/identifier diagnostics and declaration synchronization;
- statement/expression/missing-operand diagnostics and statement synchronization;
- missing delimiter, owner-span EOF, and malformed literal diagnostics;
- interpolation-hole diagnostics with absolute source rebasing;
- any remaining recovery reporters discovered by exhaustive `ReportError`/helper/caller
  inventory.

Do not copy July 2 line counts or assume a fixed call-site total; re-inventory symbols and prove
every current C# trigger maps to an N# trigger or is deleted dead behavior.

### C2d — candidate exit gate

Run all differential prongs, direct message/materialization tests, full unit breadth, and the
fresh non-VS-Code product gate because BootstrapServices/SDK packaging changed. The production
route is still C# at this point, so no IDE flip is claimed. C2 is complete only when the candidate
matches current behavior and every trigger/recovery path is accounted for.

### C3a — compiler spine flip

In `MultiFileCompiler`, keep any still-required silent AST parse but source syntax errors only
from the N# authority. Preserve NL110 preprocessing and diagnostic ordering. Hand D the API and
oracle for the imported-file Analyzer wrapper; D lands that read-side swap in its exclusive
file.

This changes Analyzer/code-intelligence results reachable from the IDE. Run focused Check,
CodeIntelligence, Parser, and golden probes, then the full VS Code-enabled gate, extension reload,
real-editor error/squiggle/hover/clear-on-fix verification, and screenshots.

### C3b — LSP, lint, format, and playground consumers

Use separate commit units for contended surfaces:

- `DocumentManager` published diagnostics and log counts;
- CLI lint parse gate;
- CLI/IDE format refusal gate, including `FormatSafe`;
- playground/compiler-service parse-error surfaces.

Do not run both diagnostic paths and deduplicate afterward. Each surface has exactly one source.
Every commit is IDE-affecting and carries focused tests, the VS Code-enabled gate, extension
reload, computer-use verification of the affected behavior, and screenshots.

### C3c — delete C# reporting ownership

Delete `ParseResult.Errors` and compile-drive every remaining reader. Delete C# message/reporting
helpers, panic-mode reporting state, snippets, and diagnostic-only text/branches. Preserve silent
AST recovery/synchronization only while a named D/G consumer still needs it.

Repoint ParserError and parser error-path tests to the N# authority without weakening full-tuple
assertions. Keep AST grammar/recovery shape tests on the temporary silent parser until its named
successor exists. Run full unit, diagnostic goldens without opportunistic rebaseline, full
VS Code-enabled gate, reload, recovery/mid-edit visual verification, and screenshots.

## Cross-track contracts

- E/A language coverage shares the consolidated parser ledger; one writer at a time.
- D owns Analyzer edits and consumes source-qualified file/SymbolId/TypeId contracts.
- F1 may add default-empty attribute/modifier columns after the current parser writer releases
  the file; F2 waits for C/D semantic identity.
- G consumes syntax/tokens/comments and owns formatter/LSP re-host after C's authority flip.
- H deletes the silent parser only after C/D/G have removed every consumer and preserved grammar
  and recovery tests.

## Prohibitions

- No fixed ordinal or deleted split-parser path from the historical notebook.
- No re-lex/reparse diagnostic engine that duplicates grammar decisions.
- No C# diagnostic text, mapping, suggestion, or recovery policy in the new path.
- No C# AST materialization from columnar tables and no emitter reparse.
- No dual diagnostic production, offset compensation, or golden rebaseline to hide drift.
- No C edit to `Analyzer.cs`; use the D handoff.
- No skipped IDE gate after a production consumer changes.

## Exit criteria

- [ ] Direct invalid/clean/recovery differential harness is non-vacuous and green.
- [ ] N# parser is the sole syntax-diagnostic authority on compiler, query, imported-file, lint,
      format/FormatSafe, playground, and LSP surfaces.
- [ ] Per-file provenance produces correct file/span data without merged-source compensation.
- [ ] C# parser reporting machinery and `ParseResult.Errors` are deleted; any silent AST parser
      residue has an exact consumer and deletion owner.
- [ ] Full diagnostic tuples/goldens remain byte-identical unless a separately approved
      improvement says otherwise.
- [ ] Every production flip carries the full IDE gate, reload, visual verification, and
      screenshots.
- [ ] Docs name the N# syntax owner and `STATUS.md` records C completion and handoffs.
