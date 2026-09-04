# Accepted external completions insert their imports

The installed-editor takeover reproduced this with YamlDotNet 16.3.0: in a project with no
imports, accepting `DeserializerBuilder (auto-import YamlDotNet.Serialization)` completed the
identifier but left its namespace absent. `CompletionHandler` advertised an import and only
sent `InsertText`.

`ImportEditPlanner.nl` now owns both the missing-import quick fix and external completion
edits. The old reflective quick-fix placement and the C# namespace-scope helpers are removed.
The handler only maps the N# edits to LSP coordinates. Its file shrinks from 638/559 total/nonblank
lines to 620/546. The ownership manifest records the observed fingerprint after the code review.

Placement uses the existing parser's header phase, extracted unchanged as `RunHeader`; `Run`
then continues its existing declaration loop. This consumes multiline qualified names and aliases
rather than treating a directive's start line as its end. A trailing comment that begins on the
header's line extends the boundary through the comment. The next declaration token bounds that
walk, and later documentation comments remain with their declaration. Namespace, package,
namespace-import and file-import headers, headers without final newlines, and LF/CRLF/bare-CR
line endings share this policy. A planner computes the header once for a completion request.

Completion edits replace the complete identifier, including text after an interior caret. An
import insertion touching that primary edit is combined into the primary edit in source order;
the remaining additional edits are disjoint. Empty files and the first word therefore receive
one edit instead of two conflicting edits at position zero. Malformed input still produces
bounded edits; accepting a name does not claim to repair unrelated unfinished syntax.

The acceptance contract also exposed an existing scope mismatch: the linter demanded
`import System.Text` inside `namespace System.Text` or `package System.Text`, while completion
already considered that namespace in scope. `RegisterImports` now seeds the lookup set from
`AnalyzerDeclarationFileFacts.GetUnitNamespace`. The separate explicit-import ledger remains
unchanged, and regressions retain NL010 for actual unused imports.

The native stdio contract applies the actual response's primary and additional edits, asserts
that they do not overlap, and checks the resulting source with the CLI. It covers 15 acceptance
fixtures: 11 complete fixtures must check clean; four intentionally unfinished/header-only
fixtures retain ordinary syntax or unused-import diagnostics. The 8 new test blocks run beside
the 3 existing process-lifetime contracts. N# owner tests cover quick-fix equivalence, scope,
header/trivia/newline placement, complete-word replacement, and incomplete preambles. A leading
U+FEFF was measured as a parser refusal (`Unexpected token`); this slice does not add a separate
BOM policy. The test helper uses explicit arguments: its attempted optional-argument signature
was a measured `NL103 parse.function` decline in the native test route.

Integration still requires the coordinator's rebuilt/reinstalled extension, screenshots of real
VS Code acceptance, and fresh VS Code-enabled product gate. No installed-editor or whole-product
verdict is claimed by the worktree's focused checks.

Focused evidence on the slice: `./scripts/dev.sh 'FullyQualifiedName~Completion|FullyQualifiedName~CodeAction'`
passed 20/20; the full BootstrapServices estate passed 7,639/7,639 with
`-p:NSharpExcludeTests=false` on both restore and test. Native `lsp-lifetime` passed 11/11
(15 acceptance fixtures), and `diagnostic-honesty` passed 32/32. Root format and the 18-test
ownership audit passed after the observed C# shrink was repinned on both reviewed-head keys.
