# Systems-language closeout cursor

Last updated: 2026-07-24

## Cursor

- Current task: `tasks/016-parser-and-syntax-diagnostics.md`
- Current iteration: one terminal slice
- Task 015 status: UNCHECKED, iteration PAUSED at `e0f987bba` — the movable decision surface is
  EXHAUSTED per the 015 completion roadmap (recorded below): every remaining emitter policy is
  BLOCKED-WITH-RECORD on four named future owners (plan-row lambda-body emitter, N# preflight/
  typing-owner port, async-func lowering, planner operand unlocks) or MECHANICAL. Resume 015 only
  when one of those owners lands. Emitter at 21,433/20,375 vs epoch 21,723/20,646 (−290 lines this
  task across 8 landed slices + 2 proven refutations + 1 restored regression).
- 016 note: Parser.cs is the LSP-fallback parser — the eventual PRODUCTION-WIRING/cutover slices are
  IDE-AFFECTING (VS Code-enabled gate + extension reinstall). The kernel-capability arc stages (Stages 1-8
  landed) are NOT IDE-affecting: they add self-contained N# owner files + native contracts with
  NO production/LSP wiring, so the non-VS-Code path suffices until cutover.
- Task 016 status: UNCHECKED, ARC IN PROGRESS. The diagnostic-CAPABILITY arc (Stages 0-17) is COMPLETE and the
  parity ledger is CLOSED; the arc has moved into the AST/facts BRIDGE (STAGE N+1), whose FIRST INCREMENT landed this
  turn (the owner now constructs the production preamble AST nodes — Namespace/Imports/Package — beside its diagnostics;
  see the THIS-TURN Active sub-slice + the new "## 016 AST/facts bridge (N+1) design record" section). Capability-arc
  summary follows (STAGE 17 landed — the CAPABILITY SURFACE IS NOW COMPLETE: residual map
  item [5], the LAST capability family — the garbage-type cascade shapes [`class 5` / `struct 5` non-`{` braced
  found-other via the unconditional `ParseTypeBody`; `func f(5)` non-identifier parameter name; `(x: 1, 5: 2)`
  named-tuple bad-name], the TYPE-ALIAS underlying-type consumer [`type T = <type>` — the `= <type>` body via
  ConsumeToken(Assign) + the newtype variant + the Stage-15 full type grammar], plus the deferral-ledger closeout
  [the corpus-light operator-`@` / `returns`-lifetime / multi-line-raw shapes now PINNED; the EOF-length-clamp class
  recorded PERMANENTLY-UNMATCHABLE; the Stage-16 table-row HANG recorded PRODUCTION-BUG-GATED with a chip filed]; the
  arc's parity ledger CLOSES — EVERY residual-map item [1]-[5] is DONE and EVERY recorded deferral is resolved or
  definitively classified. STAGE 16 [PRIOR] landed the TEST DSL + ATTRIBUTES [residual [4]]. 432 native parity
  contracts total [410 through Stage 16 + 22], `ColumnarParserRecovery.nl` now 6,855 lines; residual map items [1],
  [2], [3], [4], and [5] are ALL DONE) — the prior
  PROVEN-BLOCKED-WITH-RECORD finding
  (below) is the STAGE-0 prerequisite record for a staged parser-front-end arc (arc plan recorded in the "016
  parser/diagnostic ownership finding" section). STAGE 1 (shared-panic RECOVERY MODEL + import/namespace/package
  family, 11 contracts), STAGE 2 (the DECLARATION-NAME family — "Expected <kind> name" for func/class/struct/
  record/soa/interface/union/enum/type-alias, with `DiagnosticSpanFromToken` keyword-anchoring + the
  reserved-keyword-as-name variant, +24 contracts), STAGE 3 (the MALFORMED-LITERAL family — NL105
  unterminated string / interpolated / char / triple / interpolated-raw + empty char, reached via the
  expression-bodied `func f() => <literal>` context, +14 contracts), and STAGE 4 (the MEMBER / PARAMETER /
  FIELD declaration family — the `:`/`:=` colon and type-annotation errors via `func f(<params>)` and
  `class C { … }` / `struct S { … }`, the `ParseMemberList` per-member panic-reset sync point, and the
  Stage-2-deferred braced-kind found-other `{`-offender retirement, +17 contracts), and STAGE 5 (the
  GENERICS / CONSTRAINTS family — `ReportMissingTypeParameterName` / `ReportMissingGenericTypeArgument`, the
  `ConsumeGreater` split-`>>` discipline, and the `where`-clause constraint errors incl. the class/struct and
  struct/new() `InvalidSyntax` validations, via the function head + class type-params, +22 contracts), and STAGE 6
  (the STATEMENT family — the real `func f() { … }` block-body grammar Stages 3-5 left unparsed, the
  `SynchronizeToNextStatement` sync point + per-statement panic reset + `_currentRecoveryBoundaryColumn` tracking,
  the dangling-binary/assignment-operator through-token span, the missing-initializer `:=`/`=` forms, the
  missing if/while condition, the missing for/foreach `in`, and the missing-statement-body report, +25 contracts),
  and STAGE 7 (the EXPRESSIONS family — the fuller precedence ladder over Stage-6's shallow subset [ternary /
  coalescing / logical-or/and / bitwise-or/xor/and / equality / relational / shift / additive / multiplicative /
  range / unary / postfix-member], carrying the expression ERROR families Stages 3/6 kept panic-suppressed:
  unexpected-token-in-expression, prefix `+` [NL103], leading `.`, the ternary missing-then / missing-`:` /
  missing-else sites, dangling binary operators across every ladder tier, await/must/throw missing-operand, and
  member-name-after-dot [incl. the reserved-keyword member], +35 contracts), and STAGE 8 (the MATCH / PATTERN
  family — `ParseMatchExpression` [the match-keyword primary vehicle + `Consume(LeftBrace/Arrow/Comma/RightBrace)`
  case sites + the `EnsureProgress` per-case boundary that does NOT reset panic], the `ParsePattern` →
  or/and/not/relational → `ParsePrimaryPattern` grammar [list / slice / positional / literal / object / union-case /
  type / qualified-name] terminating in the "Invalid pattern" NL103, and `ParsePropertyPatterns`' property-name /
  brace sites, +18 contracts)
  have LANDED (no production edit to any consumer, no commit — mandate; working tree carries the two N# files + the
  STAGE-1 ColumnarSyntaxDiagnostics scaffolding deletion + this STATUS update). `ColumnarParserRecovery.nl`
  reproduces Parser.cs's recovery discipline faithfully and is proven byte-exact against the production Parser.cs
  path on a golden parity corpus (166 native contracts total, including the cascading-suppression, does-not-swallow-
  following, keyword-anchored absent/reserved name, cross-boundary panic-reset, the malformed-literal
  in-region-suppression, the member-boundary panic-reset, the split-`>>` well-formed-nested-generic, the
  statement-boundary reset + within-statement cascade-suppression, the expression-family unexpected-token-skip /
  prefix-plus-cascade / initializer-terminator-then-reset shapes, and the match/pattern cascade-suppression-within-a-
  match / statement-boundary-reset-between-matches / invalid-pattern-terminal shapes). Parser.cs REMAINS the sole
  production syntax authority; cutover is the arc's LAST stage. No wall tripped (self-contained shape, packaged SDK
  emits it — no repin).
- Active sub-slice (016 arc, THIS TURN, LANDED — no commit): STAGE N+1 (the AST/facts BRIDGE, FIRST INCREMENT) —
  the recovery owner now constructs the PRODUCTION `NSharpLang.Compiler.Ast` node instances for the file preamble
  (Namespace / Imports / Package) alongside its owned diagnostics, the first fact surface it produces beyond
  `List<CompilerError>`. Full design record + the bridge-shape decision + the precise CompilationUnit-container block +
  the refined N+1..N+3 staging are in the new "## 016 AST/facts bridge (N+1) design record" section below. WHAT LANDED:
  (1) a new `PreambleAst` result class {Namespace: NamespaceDeclaration?, Imports: List<ImportDirective>, Package:
  PackageDeclaration?, Errors: List<CompilerError>} and a static `ParseFilePreambleAst(source, fileName): PreambleAst`
  entry; (2) `ParseQualifiedName` now RETURNS the dot-joined name (bit-identical ConsumeIdentifier diagnostic sequence
  to the prior void form), and `ParseNamespace`/`ParsePackage`/`ParseImport` capture the keyword line/column and
  materialize `new NamespaceDeclaration(name, line, column)` (Parser.cs :127) / `new PackageDeclaration(...)` (:136) /
  `new ImportDirective(namespace, alias, importKwLine, importKwCol)` (:71) into recovery fields — a PURE side-effect of
  the existing grammar, so the diagnostic-only `ParseFilePreamble` stream is unperturbed (proven by the diagnostic-
  preservation contract). WHY LANDABLE / WHY BOUNDED HERE: those three preamble leaf types are already N# and owned in
  THIS assembly (FileHeaderDeclarations.nl / ImportDirective.nl), so the owner constructs the IDENTICAL instances
  Parser.cs constructs. The CompilationUnit CONTAINER + the FileImports list (FileImport/NamespaceImport) + the
  Declarations list are C# in the DOWNSTREAM `NSharpLang.Compiler` assembly (Ast/Declarations.cs, Ast/Statements.cs),
  which this upstream `BootstrapServices` owner cannot NAME (the dependency runs Compiler → BootstrapServices, never the
  reverse — confirmed: every BootstrapServices `.nl` that handles a `CompilationUnit` takes it as `object` + reflection,
  e.g. AnalyzerDeclarationContext.AddCompilationUnit / AstNodeFinderCore.VisitCompilationUnit) — so the container is NOT
  built here and is the recorded N+1 block (an assembly-dependency block, NOT an emitter gap). EQUIVALENCE PROOFS: +8
  native parity contracts in `ColumnarParserRecovery.tests.nl` asserting node-field equality against Parser.cs's
  constructor semantics on WELL-FORMED preambles (lone namespace keyword-anchored; package keyword-anchored; bare import
  null-alias; qualified aliased import joined-name + alias; a full multi-line namespace+package+two-imports subtree with
  per-line Line anchoring; a file-import-builds-no-ImportDirective negative; empty-source all-absent) PLUS a diagnostic-
  preservation contract proving `ParseFilePreambleAst("import 5\n").Errors` matches `ParseFilePreamble`'s exactly (the
  found-other NL102 then the boundary-reset NL101). Evidence: BootstrapServices contracts 1202/1202 (1194 baseline + 8;
  full-suite fresh no-build run, `-p:NSharpExcludeTests=false`); dev.sh Parser 381/381; ownership audit 18/18; git
  status shows ONLY the two `.nl` files + STATUS (no non-N# file moved). PRODUCTION COMPILE PATH UNTOUCHED — Parser.cs
  stays the sole production authority; `ParseFilePreambleAst`/`PreambleAst` are referenced ONLY by the owner's own
  `.tests.nl` (verified by grep across src+editors+tests: zero references outside the owner + its tests), so nothing in
  the production compile path changed. No LSP/VS Code change → no extension reload. NO wall tripped (self-contained edit
  to one owner + its tests; the packaged SDK 0.1.0 self-emitted the edited owner — incl. the AST construction + all 1202
  contracts cleanly — no repin; no new OpCode/kernel-entry surface). `ColumnarParserRecovery.nl` 6,855 → 6,937 (+82);
  `.tests.nl` 5,711 → 5,836 (+125). Next: STAGE N+1 continues — the CompilationUnit-container unblock (move the AstNode/
  Statement/Declaration hierarchy + CompilationUnit + FileImport/NamespaceImport upstream to N#), per the design record.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 17 of the parser-front-end arc — residual map
  item [5], the LAST capability family; the arc's parity ledger now CLOSES. Carried through the SAME shared-panic
  owner over the already-owned expression / statement / member / type / delimiter grammars, PROVEN byte-exact against
  the freshly built Release CLI oracle (`nlc check --json`, parser codes NL101-NL109, excluding the line-0 columnar-
  backend emit-decline NL103). SITE INVENTORY: (a) the GARBAGE-TYPE cascade shapes deferred since stages 4/9. The
  non-`{` braced found-other for class/struct: Parser.cs `ParseClassDeclaration`/`ParseStructDeclaration` (:970-971)
  ALWAYS parse the body (`Consume('{')` + `ParseMemberList`), so a `<error>`-named type whose offender is a non-`{`
  token (`class 5` / `struct 5`) leaves the offender for `ParseMemberList`, which — via its per-member panic reset +
  the SynchronizeToNextStatement panic reset before the type-body missing-`}` NL106 — reports the class-name NL102,
  the in-body field-name NL102(s), and the missing-`}` NL106; the Stage-12 position-sort orders them to the CLI
  display order (`class 5` → NL102@col1 [class], NL106@col1 [missing-`}`, emission-order tie], NL102@col7 [field]).
  The non-identifier parameter name (`func f(5)`): the param-name `ConsumeIdentifier` NL102 fires @ the offender,
  `ParseParameterTypeReference` routes the garbage through `ParseTypeReference` (which does NOT consume it), the `)`
  Consume is suppressed under panic, and the function returns bodiless — so `5 ) { }` each surface as a top-level
  "Unexpected token" NL101 through Run's per-declaration panic reset (the ALREADY-OWNED terminal arm). The named-tuple
  bad-name (`(x: 1, 5: 2)`): the named-element loop's `ConsumeIdentifier("Expected identifier")` NL102 fires @ the
  offender, the value `ParseExpression` consumes the offending `5`, the `)` Consume is suppressed under panic, and the
  leftover `:` and `)` surface as "Unexpected token '…' in expression" NL101 through the block-statement per-statement
  panic reset (ALREADY-OWNED). (b) the TYPE-ALIAS underlying-type consumer: Parser.cs `ParseTypeAliasDeclaration`
  (:1338-1350) `Consume(Assign)` + the optional `newtype` keyword (a bare advance) + `ParseTypeReference` (the full
  Stage-15 grammar) — the owner's `ParseTypeAliasName` previously parsed ONLY the alias NAME (a latent divergence: any
  aliased body `type T = int` would have leaked its `= int` to the top-level unexpected-token arm), now closed.
  IMPLEMENTATION: (1) renamed `ParseTypeBodyIfPresent` → `ParseTypeBody` and made it UNCONDITIONAL (`ConsumeToken(
  LeftBrace)` + `ParseMemberList`, mirroring Parser.cs :970-971 exactly, replacing the `if !Check('{') return`
  simplification that diverged for the non-`{` offender) — the 4 callers (class/struct/record/interface) route through
  it, so all four inherit the faithful body-always-parsed behavior; the `class {`/`struct {` `{`-offender case and every
  valid-name-with-body case are unchanged (the `{` is consumed as the opening brace), and every name-error-at-EOF case
  stays a single diagnostic (the missing-`}` NL106 is panic-suppressed). (2) extended `ParseTypeAliasName` with the
  `= <type>` body: `ConsumeToken(TokenType.Assign, "Expected '='", "assign")` [expected="assign" = TokenTypeToString(
  Assign)] + the `if Check(Newtype) { Advance() }` variant + `ParseTypeReferenceRecovery()`. All construction delegates
  to the shared `Report` / `ConsumeToken` / `ParseTypeReferenceRecovery` / `ParseMemberList`, so codes / messages /
  spans / snippets / hints / suggestions match Parser.cs automatically. VERIFIED PANIC INTERACTIONS (each pinned or
  re-proven): `class 5` reports THREE diagnostics (the member reset lets the field NL102 record, the sync reset before
  the NL106 lets it record); `class 5 { }` reports THREE NL102 with NO NL106 (the explicit `}` closes the body);
  `class struct\nfunc class` STILL reports exactly two NL109 (the func-name error now routes through the member-method
  `ParseMethodMember` path since the body is now parsed, but its `ConsumeDeclarationName("Expected function name",
  SpanFromToken(funcToken))` is byte-identical to the top-level `ParseFunctionName` path — same anchor @2:1 len4, same
  message; the outer missing-`}` NL106 is panic-suppressed) — the existing contract passes UNCHANGED. +22 native
  parity contracts in `ColumnarParserRecovery.tests.nl` (garbage cascade: `class 5` [3-diag], `struct 5` [3-diag],
  `class 5 { }` [3-diag], `func f(5) { }` [5-diag: param NL102 + 4 top-level NL101], `(x: 1, 5: 2)` [3-diag: element
  NL102 + 2 expr-terminal NL101]; type-alias positives: missing-`=` at EOF NL104 / missing-type at EOF NL104 /
  mid-line missing-`=` NL102 / `type T = List<>` generic-arg NL102 [proves the full type grammar] / `type = int`
  name-error-only NL102 [proves the body is cleanly consumed AFTER a name error] / `type T = newtype` at EOF NL104
  [newtype variant] / `type T = A |` union-missing-arm NL103; type-alias negatives: `A | B` / `int` / `newtype int` /
  `(int, string)` / `Func<int, bool>` / `int[]` / `A?` [all Count 0 — the underlying type routes through the full
  Stage-15 union/tuple/Func/postfix grammar]; ledger closeout: `func operator @` invalid-operator-symbol NL103 /
  `func g(): int returns {` missing-lifetime NL102 [via the local-function vehicle that wires ParseReturnLifetimeAnnotation] /
  a well-formed multi-line interpolated-raw `$"""…"""` in the block vehicle [Count 0]).
  COMPLETE DEFERRAL-LEDGER CLASSIFICATION (every recorded deferral across stages 1-16, resolved or definitively
  recorded): [NOW PINNED this stage] the garbage-type cascade (stages 4/9: `class 5`/`struct 5`/`func f(5)`/
  `(x: 1, 5: 2)`); the type-alias underlying-type (stage 15); the operator-symbol INVALID `func operator @` (stage 14,
  corpus-light); the `returns`-lifetime label error (stages 13/14, corpus-light — pinned via the local-function
  vehicle, the only owned `returns` consumer); the multi-line interpolated-raw negative (stage 12, corpus-light — a
  well-formed `$"""…"""` in the block vehicle is Count 0, the swallow concern does not materialize). [PERMANENTLY
  UNMATCHABLE at the CompilerError level] the EOF-length-clamp class (stages 5/12/16: the EOF-anchored `ConsumeGreater`
  `func f(): List<int`, the empty hole `$"{}"`, the bare `test`-at-EOF description, the EOF-anchored `returns`) —
  Parser.cs derives these lengths from `Current.Value.Length` = 0 at EOF, and the CLI's `DiagnosticSpanResolver.Resolve`
  clamps the JSON length 0→1 for display; the model faithfully emits the RAW length 0 (= Parser.cs), so a contract
  asserting length 1 would diverge from the model and a contract asserting length 0 cannot be oracle-CONFIRMED
  (BootstrapServices cannot reference Parser.cs, and the CLI — the only golden source — never exposes the raw 0). The
  diagnostic CAPABILITY (code/message/position at EOF) is present and is exercised by each family's NON-EOF variant
  already pinned; at cutover the model routes through the SAME clamp, so the DISPLAYED diagnostic converges. Definitively
  not a byte-exact CompilerError pin. [NOT A GAP — site-covered-elsewhere] the `allow` missing-`)` cascade-to-EOF (stage
  13): its `ConsumeSystemsIdentifier` / `Consume(Comma)` / `Consume(LeftParen)` / `Consume(RightParen)` sites are all
  exercised by the pinned allow-missing-`(` / allow-bad-effect + the Stage-9 closing-delimiter recovery; the corpus
  keeps the clean shapes to avoid asserting the fragile whole-file token consumption, which adds no new site.
  [PRODUCTION-BUG-GATED] the Stage-16 table-driven malformed-ROW HANG (`test "d" with (a) 9 { }`, `test "d" with (a)
  [ 9 ] { }`) — CONFIRMED this stage: production `nlc check` on `test "d" with (a) 9 { }` spins >12s (killed, no
  completion). Root cause: Parser.cs `ParseTestDeclaration` :590-604 — the outer table-case loop and the inner row loop
  (`while (!Check(RightParen) && !IsAtEnd()) { row.Add(ParseExpression()); … }`) have NO no-progress guard, so when
  `ParseExpression` cannot consume a `}`/`]` expression-terminator sitting in the row-expression position (and
  `ShouldSkipUnexpectedExpressionToken` returns false), the cursor never advances and the loop spins. The model
  reproduces the loop faithfully, so pinning the full malformed-row shape would hang the contract suite; the table `[`
  / row `(` / cases `]` Consume sites stay pinned at EOF (where the loop terminates). Chip filed (task_1f371371) with
  the precise site + the fix (a no-progress guard mirroring `ParseMemberList` :1379-1388) + a regression-test note; the
  older duplicate chip (task_9babb6f4) was dismissed as superseded. NO production wiring; NO wall tripped (self-contained
  edit to one owner + its tests; the packaged SDK 0.1.0 self-emitted the edited owner — incl. the `ParseTypeBody`
  restructure + the type-alias body + all 1194 contracts cleanly — no repin). Evidence: BootstrapServices contracts
  1194/1194 (1172 baseline + 22; full-suite fresh no-build run, `-p:NSharpExcludeTests=false`); dev.sh Parser 381/381;
  ownership audit 18/18 (`Cli.dll test --project tests/native/ownership-audit`); git status shows ONLY the two `.nl`
  files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` /
  `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+editors+tests:
  zero references outside the owner + its tests), so nothing in the production compile path changed. No LSP/VS Code
  change → no extension reload. `ColumnarParserRecovery.nl` 6,841 → 6,855 lines (+14); `.tests.nl` 5,347 → 5,711 (+364).
  RESIDUAL-TO-PARITY MAP (what remains for full Parser.cs syntax-diagnostic parity, after Stage 17 — the CAPABILITY
  SURFACE IS NOW COMPLETE): [1 — DONE Stage 13] the remaining statement kinds; [2 — DONE Stage 14] the MEMBER grammars +
  the record/interface/union/enum/soa type BODIES; [3 — DONE Stage 15] the richer type-reference forms; [4 — DONE Stage
  16] the TEST DSL + ATTRIBUTES; [5 — DONE] the garbage-type cascade shapes + the TYPE-ALIAS underlying-type consumer
  (this stage). EVERY residual-map item is DONE and EVERY recorded deferral is resolved or definitively classified.
  What remains before the arc completes: the AST/node-table-facts stage (N+1 — expose a `CompilationUnit`-equivalent /
  node-table surface the Analyzer/Linter/Formatter/LSP consume in place of Parser.cs's C# `CompilationUnit`), the
  CUTOVER (N+2, IDE-affecting — route every consumer to the N# owner at full diagnostic + AST parity), and the DELETION
  arc (N+3 — retire Parser.cs). Next: STAGE N+1 = the AST/node-table facts, per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 16 of the parser-front-end arc — the TEST DSL +
  ATTRIBUTES (residual map item [4]), carried through the SAME shared-panic owner over the already-owned expression /
  statement / member / block / argument / closing-delimiter grammars, PROVEN byte-exact against the freshly built
  Release CLI oracle (`nlc check --json`, parser codes NL101-NL109, excluding the columnar-backend emit-decline NL103 —
  for the test-DSL declarations the oracle also emits a line-0/1 emit decline ["…unmodeled declaration shape such as
  setup or teardown" / "…xunit attribute types were not resolvable"] which is a BACKEND diagnostic, not a parser one).
  SITE INVENTORY (grep of `ParseTestDeclaration`/`ParseSetupDeclaration`/`ParseTeardownDeclaration`/`ParseAttributes`/
  `ConsumeAttributeIdentifier` in Parser.cs): (a) the TEST-DSL declarations are dispatched from `ParseDeclaration`
  (:190-202) BEFORE attributes/modifiers via `IsTestDeclarationStart`/`IsSetupDeclarationStart`/`IsTeardownDeclarationStart`
  (:642/:667/:704), so each is its OWN top-level declaration and resets panic at the Run() declaration boundary. TEST
  (`ParseTestDeclaration` :546): the description-not-a-string-literal ExpectedToken DIRECT report ("Expected string
  literal for test description. Got 'X'", two example `suggestions`, length = Current.Value.Length) + skip-the-offender
  (`if (!IsAtEnd()) Advance()`, :570); the table-driven `with (params) [ (row), … ]` (:582 — `ParseParameterList` +
  `Consume(LeftBracket)` "…to start test cases" [plain NL102, LeftBracket declines closing-recovery] + the row loop's
  `Consume(LeftParen)` "…to start test case row" + `ParseExpression` list + `Consume(RightParen)` "…to end test case
  row" [NL107 via Stage-9] + `Consume(RightBracket)` "…to end test cases" [NL108 via Stage-9]); the `skip "reason"`
  string-literal ExpectedToken DIRECT report (:611, one suggestion, does NOT skip the offender); the `ParseBlock` body
  (owner span = the `test` keyword, length 4). SETUP/TEARDOWN (:695/:710): a bare `Advance()` past the contextual
  keyword then `ParseBlock` (owner span length 5 / 8), no own error site. assert/assert-throws already owned (Stage
  13). (b) ATTRIBUTES `[Name(.Name)* (args)?]` (`ParseAttributes` :269) precede modifiers on top-level declarations
  (:214), members (`ParseMemberDeclaration` :1424), AND parameters (`ParseParameterList` :770 — the owner's
  `ParseParameterListRecovery` per-parameter loop, closing the Stage-4-deferred parameter-attribute gap): the name via
  `ConsumeAttributeIdentifier` (:6811 — Identifier/Alloc/Allow, else the owned Stage-1 `ConsumeIdentifier` NL102 with
  its reserved-keyword / found-other / EOF variants + dot-access variant) + the qualified `.` continuation, the optional
  `(args)` via the owned Stage-10 `ParseArgumentList` (NL107 when unclosed), and the closing `]` via the owned Stage-9
  `Consume(RightBracket)` (NL108 when unclosed, else plain NL102). Also added the top-level PreprocessorDirective
  declaration (:205, a bare advance) so the `ParseDeclaration` dispatch ORDER is faithful. IMPLEMENTATION: inserted the
  test/setup/teardown/preprocessor checks + `ParseAttributes()` at the top of `ParseTopLevelDeclaration` (before
  `ParseModifiers`), the member `ParseAttributes()` into `ParseMemberDeclaration` (between the preprocessor check and
  `ParseModifiers`), and the per-parameter `ParseAttributes()` into `ParseParameterListRecovery`; added
  `IsTestDeclarationStart`/`IsSetupDeclarationStart`/`IsTeardownDeclarationStart`, `ConsumeTestKeyword`,
  `ParseTestDeclaration`, `ParseSetupDeclaration`, `ParseTeardownDeclaration`, `ParseAttributes`,
  `ConsumeAttributeIdentifier` — all delegating construction to the shared `Report` / `ConsumeToken` /
  `ConsumeIdentifier` / `ParseArgumentList` / `ParseBlock` / `ParseParameterListRecovery` and reusing the live shared
  `ParserErrorDiagnostics.Create`, so codes / messages / spans / snippets / hints / suggestions match Parser.cs
  automatically. VERIFIED PANIC INTERACTIONS (each pinned): two malformed tests BOTH report (declaration-boundary
  reset); a malformed test then a valid decl reports only the test error; a non-string skip reason before a body
  cascades the skip NL102 AND the block missing-`}` NL106 (block per-statement reset lets the NL106 record; the two are
  position-sorted so NL106 @col1 precedes the skip @col18); a non-identifier top-level attribute name (`[123]`) reports
  the ConsumeIdentifier NL102 then the `]` UnexpectedToken NL101 after the boundary reset re-dispatches (does-not-swallow-
  following); a non-identifier MEMBER attribute name (`class C { [123] … }`) cascades the attr-name NL102 and the
  field-name NL102 across the ParseMemberList member-boundary reset. +25 native parity contracts in
  `ColumnarParserRecovery.tests.nl` (14 positive-diagnostic: test-desc-not-string / two-malformed-tests-boundary-reset /
  malformed-test-then-valid / skip-not-string / skip-then-body-cascade [NL106+NL102 position-sorted] / table-missing-`[`
  NL102 / table-row-missing-`(` NL102 / table-unclosed-`]` NL108 / attr-bad-name-then-`]`-NL101 / attr-bad-qualified-`.`
  dot-access NL102 / attr-unclosed-`]` NL108 / attr-unclosed-args-`)` NL107 / member-attr-bad-name-cascade [attr-name +
  field-name across member reset]; 11 negatives: empty-test / assert-body-test / valid-skip / valid-table / setup /
  teardown / valid-attr / valid-attr-args / valid-qualified-attr / two-stacked-attrs / member-attr / parameter-attr).
  DEFERRED / RECORDED (NOT corpus-pinned — with reasons): the malformed table-driven ROW shapes reached via a following
  `{ }` BODY (`test "d" with (a) 9 { }`, `test "d" with (a) [ 9 ] { }`) HANG the PRODUCTION parser — the row loop
  `while (!Check(RightParen) && !IsAtEnd()) ParseExpression()` does NOT force-advance and `ShouldSkipUnexpectedExpressionToken`
  returns false for a `}` / `]` expression-terminator sitting in the row-expression position, so `ParseExpression` spins;
  the model reproduces this loop faithfully, so pinning such a shape would hang the suite — the malformed table `[` / row
  `(` / cases `]` Consume sites are instead pinned at EOF (where the loop terminates and the leading Consume error is the
  single unsuppressed diagnostic), which exercises exactly those Consume sites. The bare-`test`-at-EOF description error
  is the Stage-5/12 EOF-length-0-clamp class (Current.Value.Length 0 vs the JSON clamp to 1) so the corpus uses a
  numeric bad description. NO production wiring; NO wall tripped (self-contained edit to one owner + its tests; the
  packaged SDK 0.1.0 self-emitted the edited owner — incl. all new parsers + all 1172 contracts cleanly — no repin).
  Evidence: BootstrapServices contracts 1172/1172 (1147 baseline + 25; full-suite fresh no-build run,
  `-p:NSharpExcludeTests=false`; `FullyQualifiedName~Test_016Attributes|~Test_016TestDsl` filter 25/25); dev.sh Parser
  381/381; ownership audit 18/18 (`Cli.dll test --project tests/native/ownership-audit`); git status shows ONLY the two
  `.nl` files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` /
  `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+editors+tests:
  zero references outside the owner + its tests), so nothing in the production compile path changed. No LSP/VS Code
  change → no extension reload. `ColumnarParserRecovery.nl` 6,640 → 6,841 lines (+201); `.tests.nl` 5,069 → 5,347 (+278).
  RESIDUAL-TO-PARITY MAP (what remains for full Parser.cs syntax-diagnostic parity, after Stage 16):
  [1 — DONE Stage 13] the remaining statement kinds; [2 — DONE Stage 14] the MEMBER grammars + the record / interface /
  union / enum / soa type BODIES; [3 — DONE Stage 15] the richer type-reference forms (union / postfix array-nullable /
  byref / tuple / `Func<>`); [4 — DONE] the TEST DSL (test / setup / teardown + the table-driven case rows) and
  ATTRIBUTES (top-level / member / parameter) (this stage); [5] the garbage-type cascade shapes (non-identifier
  parameter name, named-tuple bad-name) needing `ParseTypeReference`-on-garbage + the stable position-sorted emit
  (unblocked since Stage 12), and the TYPE-ALIAS underlying-type consumer (`type T = A | B`, Parser.cs
  `ParseTypeAliasDeclaration` :1344/:1348 — the owner's `ParseTypeAliasName` parses only the alias NAME, not the
  `= <type>` body). THEN the AST/node-table-facts stage (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc
  (N+3). Next: STAGE 17 = residual map item [5] (the garbage-type cascade shapes + the type-alias underlying-type
  consumer), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 15 of the parser-front-end arc — the richer
  TYPE-REFERENCE forms (residual map item [3]), carried through the SAME shared owner over the already-owned
  simple / qualified / generic type subset, PROVEN byte-exact against the freshly built Release CLI oracle
  (`nlc check --json`, filtered to the parser codes NL101-NL109, excluding the SEMANTIC diagnostics — not-all-paths-
  return NL305, type-not-found NL201, undefined-name NL301, etc. — which are analyzer, not parser, diagnostics).
  SITE INVENTORY (grep of `ParseTypeReference` + its helpers in Parser.cs :1774-2021): the entry `ParseTypeReference`
  (:1774) → `ParseUnionTypeReference` (:1779) → `ParsePostfixTypeReference` (:1814) → `ParseBaseTypeReference`
  (:1884). The COMPLETE reachable error-site surface: (a) the UNION layer's ONE new report — the NL103
  "Expected a type after '|' in anonymous union type" (:1793, InvalidSyntax, anchored on Current, length
  Max(1, Current.Value.Length), humanExplanation + hint, NO suggestions) fired when a `|` is IMMEDIATELY followed by
  a type terminator (`IsTypeTerminator`: Comma/RightParen/RightBracket/RightBrace/Newline/Eof/Assign/Semicolon/Arrow/
  Colon — NOTE `{` / `|` / an identifier are NOT terminators, so `A | {` / `A | | B` reach the ConsumeIdentifier NL102
  on the arm, and the shared lexer's newline-suppression-after-`|` means the arm greedily crosses a suppressed newline
  and consumes the next line's leading identifier), then BREAK (only the first trailing `|` reports; panic suppresses
  any later one regardless); (b) the POSTFIX layer's `[]` / `?[]` / `?` suffixes (:1821/:1832/:1854) — the array /
  nullable-array closes are LOOKAHEAD-GUARDED (`[` only when `]` immediately follows), so their `Consume(RightBracket)`
  NEVER fails — NO reachable diagnostic; they only shape the consumed extent so a following error anchors byte-exact;
  (c) the BASE dispatch — byref `&T` (:1886, inner is a POSTFIX type, no own report), the tuple / parenthesized type
  `( … )` (`ParseParenthesizedOrTupleTypeReference` :1965 — its closing `)` routes through the shared ConsumeToken so a
  missing `)` reaches the Stage-9 closing-delimiter recovery [NL107 at a line / same-line boundary, else the plain
  NL102], and its element types + the empty-tuple / bad-named-element cases reach the shared ConsumeIdentifier NL102),
  the `Func<…>` function type (`ParseFunctionTypeReference` :2000 — `Consume(Less)` [NL102 "Expected '<'", expected
  "less", or the ConsumeToken EOF NL104] + a comma-separated ParseTypeReference list + the split-`>>`-aware
  ConsumeGreater; unlike the generic identifier arm, `Func` does NOT call ReportMissingGenericTypeArgument, so
  `Func<>` / `Func<int,>` reach the ConsumeIdentifier NL102 on the `>` — verified divergent from `List<>` /
  `List<int,>`), and the simple / qualified / generic identifier arm owned since Stage 5. So the ONLY genuinely new
  report Stage 15 adds is the union NL103; every other reachable site reduces to an already-owned primitive
  (ConsumeIdentifier NL102/NL104, ConsumeToken NL102/NL107/NL108, ConsumeGreater NL102, ReportMissingGenericTypeArgument).
  IMPLEMENTATION: restructured `ParseTypeReferenceRecovery` into the union entry (the `|`-arm loop + `ReportUnionMissingTypeArm`)
  → `ParsePostfixTypeReferenceRecovery` (the `[]` / `?[]` / `?` loop) → `ParseBaseTypeReferenceRecovery` (byref / tuple /
  Func dispatch + the moved simple/generic body) + `ParseParenthesizedOrTupleTypeReferenceRecovery` +
  `ParseFunctionTypeReferenceRecovery`, all delegating construction to the shared `Report` / `ConsumeIdentifier` /
  `ConsumeToken` / `ConsumeGreater` / `ReportMissingGenericTypeArgument` and reusing the live shared `IsTypeTerminator`
  / `ParserErrorDiagnostics.Create`, so codes / messages / spans / snippets / hints / suggestions match Parser.cs
  automatically. RETIRED the narrower `ParseSimpleTypeReference` (the Stage-4 minimal single-identifier vehicle):
  Parser.cs threads PARAMETER (`ParseParameterTypeReference` :6507), FIELD (`ParseFieldTypeReference` :6543), and
  `let`-declaration (`ParseVariableDeclaration` :2553) types through the FULL `ParseTypeReference` — so its three
  callers now route through `ParseTypeReferenceRecovery`, closing a latent parity gap (a generic / union / tuple /
  byref param or field type would previously have diverged) and giving the mandate's parameter/field consumers the
  full grammar; the speculative expression-statement typed-decl (`ParseExpressionStatement` :4244) already used it.
  SHARED-CONSUMER PROOF SITES (chosen representative, not exhaustive cross-products): the union NL103 pinned at the
  RETURN-type (`func f(): A |`), FIELD (`struct S { x: A | }`), CATCH (`catch (e: A |)`), IS-EXPRESSION
  (`x is A |`), and TYPED-DECLARATION (`x: A | = y`) sites — proving all five owned consumers thread the SAME grammar;
  the postfix / byref / tuple forms proven CONSUMED via the "form-then-trailing-`|`" shape (`A[] |` / `A? |` / `&A |` /
  `(int, string) |` each report the union NL103 AFTER the form, which only fires if the form was consumed to exactly
  the byte-position Parser.cs reaches); the generic-arg / tuple-element / Func-param recursion proven via the nested
  negatives (`List<A | B>`, `Func<Func<int, string>, bool>`); the base-list via the valid `class C : A | B`; the
  parameter consumer via `func f(x: &)`. +33 native parity contracts in `ColumnarParserRecovery.tests.nl` (19
  positive-diagnostic: union NL103 at return / field / typed-decl / catch / is-expr; array-then-`|` / nullable-then-`|`
  / byref-then-`|` / tuple-then-`|` NL103; byref-missing-inner NL104 [return] + NL102 [param `&)`]; tuple unclosed-`)`
  NL107 / empty-`()` NL102 / bad-named-element NL102; Func missing-`<` NL104 / unclosed-`>` NL102 / empty-`<>` NL102
  [divergent from generic] / trailing-comma NL102; the union arm greedily consuming across the `|`-suppressed newline
  [one NL102 field-name, not two]; 14 negatives: valid union / array / nullable / nullable-array / byref-param / tuple /
  named-tuple / single-unwrap / Func / multi-Func / union-in-generic-arg / nested-Func-`>>` / is-union / base-list-union).
  DEFERRED / RECORDED (NOT corpus-pinned — with reasons): the TYPE-ALIAS underlying type (`type T = A | B`) is NOT an
  arc-owned consumer — the owner's declaration preamble parses only the alias NAME (`ParseTypeAliasName`), not the
  `= <type>` body (Parser.cs `ParseTypeAliasDeclaration` :1344/:1348 does, via `ParseTypeReference`) — so the type-alias
  vehicle is out of Stage-15 scope; adding it is a separate consumer slice. The CAST site `(A | )x` does NOT reach the
  type-union grammar: the `IsCastExpression` lookahead requires a well-formed cast type, so a malformed `A |` fails the
  scan and the whole `(A | )` is parsed as a PARENTHESIZED bitwise-OR EXPRESSION (the Stage-7 "Expected expression
  after '|'" NL102), not a cast type — an expression diagnostic, already owned. The `new`-expression type
  (`ParseNewTypeReference`) routes through the same upgraded `ParseTypeReferenceRecovery`, so it inherits the full
  grammar for free (no separate pin — the new corpus is expression-side). NO production wiring; NO wall tripped
  (self-contained edit to one owner + its tests; the packaged SDK 0.1.0 self-emitted the edited owner — incl. the
  ParseTypeReferenceRecovery restructure + ParseSimpleTypeReference retirement + all new parsers + all 1147 contracts
  cleanly — no repin). Evidence: BootstrapServices contracts 1147/1147 (1114 baseline + 33; full-suite fresh no-build
  run, `-p:NSharpExcludeTests=false`; `FullyQualifiedName~016TypeRef` filter 33/33); dev.sh Parser 381/381; ownership
  audit 18/18 (`Cli.dll test --project tests/native/ownership-audit`); git status shows ONLY the two `.nl` files +
  STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` / `ParseFilePreamble`
  are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+editors+tests: zero references
  outside the owner + its tests), so nothing in the production compile path changed. No LSP/VS Code change → no
  extension reload. `ColumnarParserRecovery.nl` 6,520 → 6,640 lines (+120); `.tests.nl` 4,731 → 5,069 (+338).
  RESIDUAL-TO-PARITY MAP (what remains for full Parser.cs syntax-diagnostic parity, after Stage 15):
  [1 — DONE Stage 13] the remaining statement kinds; [2 — DONE Stage 14] the MEMBER grammars + the record / interface /
  union / enum / soa type BODIES; [3 — DONE] the richer type-reference forms (union / postfix array-nullable / byref /
  tuple / `Func<>`) shared across is/as/typeof/sizeof/cast/stackalloc/catch/typed-decl/local-func-return/base-lists/
  member-return-types/parameter/field/new/generic-args/tuple-elements/Func-params (this stage); [4] the TEST DSL
  (test / setup / teardown + the test-case rows) and ATTRIBUTES (member + declaration); [5] the garbage-type cascade
  shapes (non-identifier parameter name, named-tuple bad-name) needing `ParseTypeReference`-on-garbage + the stable
  position-sorted emit (unblocked since Stage 12); and the TYPE-ALIAS underlying-type consumer (recorded above). THEN
  the AST/node-table-facts stage (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc (N+3). Next: STAGE 16 =
  the TEST DSL + ATTRIBUTES (map residual [4]), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 14 of the parser-front-end arc — the MEMBER
  grammars + the remaining type BODIES (residual map item [2]), carried through the SAME shared-panic model over the
  already-owned expression / statement / type / delimiter / block grammars, PROVEN byte-exact against the freshly
  built Release CLI oracle (`nlc check --json`, filtered to the parser codes NL101-NL109, excluding the SEMANTIC
  diagnostics — not-all-paths-return NL305, undefined-name NL3xx, etc. — which are analyzer, not parser,
  diagnostics). SITE INVENTORY (grep of the type-declaration + `ParseMemberList`/`ParseMemberDeclaration` +
  `ParseFieldDeclaration`/`ParseFunctionDeclaration`/`ParseConstructorDeclaration`/`ParseIndexerDeclaration` grammars
  in Parser.cs): (a) the MEMBER dispatch — `ParseMemberDeclaration` (:1412): the preprocessor member (:1415), the
  modifiers (attributes are residual [4], omitted like the top-level dispatch), the nested-type declarations
  (class / ref-struct / struct / soa / record / enum / union / interface, :1428-1460), the `constructor` contextual
  identifier (:1463), the `func this[…]` indexer (:1469), the method / conversion-operator (:1475), and the
  field/property fall-through (:1481); `ParseMemberList` (:1359) now dispatches this full grammar (was FIELD-only at
  Stage 4) with the member-boundary panic reset, the `_currentRecoveryBoundaryColumn` save/set/restore around each
  member (:1367-1376), and the no-progress `SynchronizeToNextStatement`-then-force-advance (:1379-1388). (b) METHODS
  `ParseMethodMember` (Parser.cs `ParseFunctionDeclaration` :373 reached as a member) — the keyword-anchored name
  (`ConsumeDeclarationName`, DiagnosticSpanFromToken(funcToken), :435), `func*` generators (:409), `async`
  (via `ParseModifiers`), `func operator SYM` overloads (:415, `ParseOperatorSymbol` :5752 + the invalid-symbol
  NL103), `implicit`/`explicit operator` conversions (:393, return type BEFORE params :452), the `: T`/`-> T` return
  type or the `ReportMissingReturnTypeMarker` (NL102, name/operator-keyword-anchored, length = the NAME length so
  `func A() int` reports length 1 while `func Foo() int` reports 3), the `returns`-lifetime + generic constraints,
  and the `=> expr` / `{ }` body — with NO missing-body report (an abstract / interface method with no body is
  valid, unlike a local function). (c) CONSTRUCTORS `ParseConstructorMember` (:1484) — the `constructor` identifier,
  the parameter list, the optional `: this(args)` / `: base(args)` initializer (each `Consume(LeftParen)` +
  `ParseArgumentList`), the "Expected 'this' or 'base' after ':'" NL102 (+ skip the offender), and the block body
  (owner span on `constructor`, length 11). (d) INDEXERS `ParseIndexerMember` (:1564) — `func this[params]: retType
  { get/set }`, the `[`/`]`/`:`/`{` Consumes, the parameter loop (`ConsumeParameterColon`), and the accessor loop's
  "Expected 'get' or 'set' accessor, got X" NL102 (:1613) + skip. (e) PROPERTIES — `ParseFieldMember` extended
  (Parser.cs `ParseFieldDeclaration` :1637): the leading `required`/`init`/`readonly` property modifiers (:1644),
  the `:=` inferred form, the expression-bodied `=> expr` property (:1683), and the `{ get/set }` accessor block
  with the ", got X" invalid-identifier NL102 (:1718, anchored on the token AFTER the accessor, length = the bad
  accessor's) + skip, the ". Got X" non-identifier NL102 (:1738) + skip, and the "Expected '}' after property
  accessors" close (:1756); the `= initializer` field via `ParseRequiredExpressionAfter` (:1762). (f) the class /
  struct / record positional (primary-ctor) parameter lists (`(…)` after the type-params, :947/:992/:1037) and the
  base / interface lists (`: T, U`, `ParseBaseTypeList`, :955/:998/:1043/:1150) — added to `ParseClassName` /
  `ParseStructName` / `ParseRecordName` / `ParseInterfaceName`. (g) the record / interface type BODIES route through
  the shared `ParseMemberList` (like class/struct); the UNION body (`ParseUnionBody`, :1179) has its OWN case loop
  (the "Expected union case name" ConsumeIdentifier, the `{ prop: type, … }` payload with its "Expected ':'"
  ConsumeToken + `EnsureProgress`-per-property, the `EnsureProgress`-then-panic-reset per case, and the union-specific
  missing-`}` NL106 anchored on the union name / keyword, "The union body that started on line N…"); the ENUM body
  (`ParseEnumBody`, :1274) has its OWN member loop (the optional `= value` via `ParseExprValue`, the comma-or-break,
  the "Expected enum member name", and the enum-specific missing-`}` NL106) plus the optional `: int|string` backing
  type ("Expected enum backing type" + the "Unsupported enum backing type 'X'" NL101, length via the shared Create
  default-0 fallback → the type-name length); the SOA body (`ParseSoaRecordBody`, :1085) has its OWN column loop
  (the "Expected soa column name", the "Expected ':'" ConsumeToken, the trailing `,`/`;`, the per-column panic reset,
  and the soa-specific missing-`}` NL106) plus the generic-soa `<…>` "soa record type parameters are not supported
  yet" NL103. RETIRED the stage-2 deferred non-`{` braced found-other cases for record / interface / union / enum /
  soa: their name parsers now capture the name-token span (or the declaration-keyword span for a `<error>` name) and
  parse the body, exactly like class/struct since Stage 4, so a `record {` / `union {` etc. flows into body parsing
  byte-exact (verified against the oracle with the Stage-12 position-sort in place). IMPLEMENTATION: extended
  `ParseMemberList` + `ParseFieldMember` and added ~18 new parser methods + reports (`ParseMemberDeclaration`,
  `ParseConstructorMember`, `ParseIndexerMember`, `ParseMethodMember`, `ParseOperatorSymbol`, `IsOverloadableOperator`,
  `ParseBaseTypeList`, `ParseUnionBody`, `ParseEnumBody`, `ParseSoaRecordBody`, `ReportTypeBodyMissingClosingBrace`,
  `ReportConstructorInitializerTarget`, `ReportIndexerAccessorInvalid`, `ReportPropertyAccessorInvalidIdentifier`,
  `ReportPropertyAccessorExpectedGetSet`, `ReportSoaTypeParametersUnsupported`, `ReportEnumBackingTypeUnsupported`),
  all delegating construction to the shared `Report` / `ConsumeToken` / `ConsumeIdentifier` /
  `ParseRequiredExpressionAfter` and reusing the live shared `ParserTokenFacts` / `ParserErrorDiagnostics.Create`, so
  codes / messages / spans / snippets / hints / suggestions match Parser.cs automatically. VERIFIED PANIC INTERACTIONS
  (each pinned by a contract): two class methods each missing the `:` marker BOTH report (member-boundary reset); two
  properties each with a bad accessor BOTH report; a body-less method's missing-marker panic-suppresses the type-body
  EOF missing-`}` (one diagnostic); an unclosed NESTED enum reports its OWN missing-`}` and panic-suppresses the outer
  class body's; the invalid-accessor / bad-init-target cascades produce the byte-exact trailing "Unexpected token '}'"
  / EOF missing-`}` the oracle produces. +36 native parity contracts in `ColumnarParserRecovery.tests.nl` (20
  positive-diagnostic: interface-method-missing-marker / two-methods-each-report / method-missing-marker-suppresses-
  type-`}` / ctor-bad-init-target-then-`}` / ctor-this-missing-`(` / prop-non-ident-accessor / prop-invalid-ident-
  accessor-then-`}` / two-props-each-report / indexer-invalid-accessor-then-`}` / record-positional-param-colon /
  union-case-name / union-missing-`}` NL106 / union-payload-missing-`:` / enum-member-name-then-cascade / enum-
  unsupported-backing NL101 / enum-missing-`}` NL106 / soa-missing-`:` / soa-generic NL103 / soa-missing-`}` NL106 /
  nested-enum-missing-`}`; 3 stage-2 found-other retirement: record/union/enum whose name is a `{`; 13 negatives:
  method block / generator func* / async / expr-body / operator-overload / implicit-conversion / ctor-this-init /
  property-get-set / expr-body-property / nested-enum / union-payload / interface-members / record-positional).
  DEFERRED (recorded, NOT corpus-pinned — with reasons): the operator-symbol
  INVALID case (`func operator @`) is modelled faithfully (`ParseOperatorSymbol`'s NL103) but corpus-light (the corpus
  uses valid operators); the `returns`-lifetime body is shared-owned (Stage 13) and unchanged; the richer
  type-reference forms in base lists / indexer return types / method return types (union / postfix array-nullable /
  byref / tuple / `Func<>`) remain shared residual [3] (the member corpus uses simple / qualified / generic type
  names). NO production wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged SDK 0.1.0
  self-emitted the edited owner — incl. `ParseMemberList`/`ParseFieldMember` refactors + all new parsers + all 1114
  contracts cleanly — no repin). Evidence: BootstrapServices contracts 1114/1114 (1078 baseline + 36; full-suite
  fresh no-build run, `-p:NSharpExcludeTests=false`; `FullyQualifiedName~016Member|016TypeBody` filter 33/33 [+ the 3
  found-other retirement contracts under the decl-name/type-body names]); dev.sh Parser 381/381; ownership audit 18/18
  (`nlc test --project tests/native/ownership-audit`); git status shows ONLY the two `.nl` files + STATUS (no non-N#
  file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` / `ParseFilePreamble` are referenced
  ONLY by this owner's own `.tests.nl` (verified by grep across src+editors+tests: zero references outside the owner +
  its tests), so nothing in the production compile path changed. No LSP/VS Code change → no extension reload.
  `ColumnarParserRecovery.nl` 5,826 → 6,520 lines (+694); `.tests.nl` 4,303 → 4,731 (+428). RESIDUAL-TO-PARITY MAP
  (what remains for full Parser.cs syntax-diagnostic parity, after Stage 14):
  [1 — DONE Stage 13] the remaining statement kinds; [2 — DONE] the MEMBER grammars + the record / interface / union /
  enum / soa type BODIES (this stage); [3] the richer type-reference forms (union / postfix array-nullable / byref /
  tuple / `Func<>`) shared across is/as/typeof/sizeof/cast/stackalloc/catch/typed-decl/local-func-return/base-lists/
  member-return-types; [4] the TEST DSL (test / setup / teardown + the test-case rows) and ATTRIBUTES (member +
  declaration); [5] the garbage-type cascade shapes (non-identifier parameter name, named-tuple bad-name) needing
  `ParseTypeReference`-on-garbage + the stable position-sorted emit (unblocked since Stage 12). THEN the
  AST/node-table-facts stage (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc (N+3). Next: STAGE 15 =
  the richer type-reference forms (map residual [3]), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 13 of the parser-front-end arc — the REMAINING
  STATEMENT kinds (residual map item [1]), carried through the SAME shared-panic model over the already-owned
  expression / type / pattern / delimiter grammars, PROVEN byte-exact against the freshly built Release CLI oracle
  (`nlc check --json`, filtered to the parser codes NL101-NL109, excluding the line-0 columnar-backend decline and
  the SEMANTIC diagnostics — loop-context for break/continue/yield, generator-return NL202, undefined-name
  NL301/NL412, unused-local NL001 — which are analyzer, not parser, diagnostics). SITE INVENTORY (grep of the
  ParseStatement dispatch + helpers in Parser.cs): (a) the SIMPLE keyword statements with ZERO own error sites —
  `break` (:2885) / `continue` (:2967) (the guarded `Consume` never fires) / `preprocessor` (:2875) / `off`
  (:2957, `IsOffStatementStart` + a bare `ParseExpression` handle); (b) the REQUIRED-EXPRESSION statements routed
  through the already-owned `ParseRequiredExpressionAfter` (the `ShouldUnderlineAnchorForMissingRequiredExpression`
  set already carries Throw/Yield/Assert/Using/Lock/Switch) — `throw` (:2975, "an exception expression"), `yield`
  (:2839, "a value to yield" or the `yield break` no-value form), `assert` (:2388, "a condition expression" + the
  optional `, message` + the `assert throws Type { … }` form), `lock` (:3128, "an object expression" + optional
  parens; the "Expected block statement after lock" report is UNREACHABLE dead C# — `ParseBlock` always yields a
  block); (c) the BLOCK-bearing statements routed through the new `ParseBlock` (Consume-first, the Parser.cs :2143
  entry the block-bearing kinds call directly, refactored to share `ParseBlockStatementsLoop` with the Stage-6
  `ParseBlockBody`) — `unsafe` (:2379) / `alloc { … }` (:2301, the `Alloc && LookAhead=={` compound dispatch) /
  `try`-`catch`-`finally` (:2988, the catch parameter list `(Type e)` / `(e: Type)` / bare forms, the catch type
  via the owned `ParseTypeReferenceRecovery`, the catch `)` via the Stage-9 closing-delimiter recovery [NL107]);
  (d) the STATEMENTS with their OWN diagnostics — `using` (:3048, the `Consume(ColonAssign)` "Expected ':='" [NL102,
  expected "colonassign"] + the `using let (a, b)` invalid-tuple InvalidSyntax [NL103] anchored on the single-line
  `(…)` pattern span via the ported `TryGetSingleLineDelimiterSpanAt` :5968), `switch` (:3170, `Consume(LeftBrace)` +
  the per-case `Consume(Arrow)` [expected "arrow"] + the "Expected 'case' or 'default'" [NL102] skip-and-continue/
  break arm + the switch-specific missing-`}` [NL106, its own body-line message] distinct from the block NL106),
  `allow` (:2310, `Consume(LeftParen, "…after 'allow'")` + the effect loop's `ConsumeSystemsIdentifier` [NL102] +
  `Consume(Comma, "…between allow arguments")` + the `if (Current == nameToken) Advance()` force-advance modelled by
  a position guard + the trailing `Consume(RightParen)`; `ParseAllowEffectValue` + the reason/owner named args),
  `local-function` (:2419, `[static][async] func Name<…>(…)`; the LOCAL func uses plain `ConsumeIdentifier` for the
  name NOT the keyword-anchored `ConsumeDeclarationName`, and reaches `ReportMissingReturnTypeMarker` [NL102 "Expected
  ':' before return type", name-anchored via `IsLikelyMissingReturnTypeMarker`], the `-`-`>` return-type arrow's
  `Consume(Greater)`, the `ParseReturnLifetimeAnnotation` `returns` grammar [ported faithfully, corpus-light], and
  the missing-body ReportError [NL102 "Expected function body or '=>'…"]), `on` (:2893/:3649, the highest-precedence
  `ParseExprValue` prefix — `IsOnSubscriptionStart` + `ParseEventTarget` [a primary + member/index chain that STOPS
  before a `(` so the handler's parameter list is not swallowed; the member `ConsumeIdentifier("Expected event or
  member name after '.'")` reaches the dot-access NL102 variant] + the handler-is-lambda check [pre-detected via the
  two `ParseExprValue` lambda prefixes, avoiding an ExprResult flag] + the "Expected an event handler lambda" [NL103]
  when the handler is not a lambda); (e) the `for` (:2651) C-STYLE `for (init; cond; incr)` branch appended after the
  two foreach-style branches — optional parens, the `let`/`:=`/bare-expr initializer, the two `Consume(Semicolon)`
  [NL102, the `;` hint], the optional condition/iterator, and the optional `Consume(RightParen)` via the Stage-9
  recovery [NL107]; (f) `await foreach` (:2776) mirroring foreach with the `ConsumeInOrReportMissing` shared idiom +
  the "This await foreach statement" owner description; (g) `ParseVariableDeclaration` extended with the
  `(x, y) := …` TUPLE deconstruction dispatch (returns a bool so `using` can distinguish it) + `ParseTupleDeconstruction`
  [the name list, the "Tuple deconstruction requires ':=' or '='" NL102, the skip-the-offender + required-initializer]
  and `ParseExpressionStatement` extended with the typed `name: T = value` declaration [speculative parse + rewind on
  no `=`; NL102 "…after '='" name-anchored], the no-paren `x, y := e` and paren `(x, y) := e` tuple forms.
  IMPLEMENTATION: extended the `ParseStatement` dispatch in Parser.cs order (await-foreach compound before while, then
  yield/break/continue/throw/try/using/lock/switch/allow/alloc-block/unsafe/…/assert/preprocessor, then the
  static-async-func local-function forms, then the `off` contextual dispatch before the expression statement); added
  the ~30 new parser methods + reports (all delegating construction to the shared `Report` /
  `ParseRequiredExpressionAfter` / `ConsumeToken` / `ConsumeIdentifier`, and every boundary DECISION reusing the live
  shared `ParserTokenFacts`, so codes / messages / spans / snippets / hints / suggestions match Parser.cs
  automatically); refactored `ParseBlockBody`→`ParseBlockStatementsLoop`+`ParseBlock` (the Consume-first block entry).
  VERIFIED PANIC INTERACTIONS (each pinned by a contract): switch's missing-`{` panic still-set suppresses the func's
  own EOF missing-`}` (one diagnostic, not two); two switches each with a bad branch BOTH report (per-statement
  boundary reset); two functions each with a body-less local function BOTH report (declaration-boundary reset); the
  `on w. => 1` dot-access NL102 panic-suppresses the trailing non-lambda NL103 (one diagnostic). +45 native parity
  contracts in `ColumnarParserRecovery.tests.nl` (22 positive-diagnostic: yield-missing / throw-missing / lock-missing
  / catch-unclosed-`)` NL107 / switch-missing-`{` / switch-bad-branch / switch-missing-arrow / switch-missing-`}` NL106
  / allow-missing-`(` / allow-bad-effect / assert-missing / local-func-missing-body / local-func-missing-return-colon /
  await-foreach-missing-in / c-for-missing-`;` / c-for-missing-`)` NL107 / tuple-missing-`:=` / typed-decl-missing-init /
  using-missing-`:=` / using-invalid-tuple NL103 / on-non-lambda NL103 / on-missing-member-after-dot; 4 panic-interaction:
  switch-panic-suppresses-func-`}`, two-switches-each-report, two-local-funcs-each-report, on-dot-suppresses-non-lambda;
  19 negatives: yield-break / yield-value / break-continue-in-loop / throw-expr / try-catch-finally / catch-typed-var /
  lock-obj / lock-parens / unsafe / alloc / assert-cond+msg+throws / preprocessor / local-func block+expr+static /
  await-foreach / c-for paren+bare / tuple paren+no-paren / typed-decl / using-let+ident / off / on single+multi lambda).
  DEFERRED (recorded, NOT corpus-pinned — with reasons): the `allow` missing-`)` shape is really a "missing comma"
  cascade that, under the shared panic set by the first NL102, consumes to EOF with every further report suppressed —
  the loop (incl. the force-advance) is modelled faithfully and the OUTPUT is the single NL102, but the whole-file
  consumption is fragile to pin so the corpus keeps the clean allow shapes; the `returns` lifetime body of
  `ParseReturnLifetimeAnnotation` is ported faithfully but corpus-light (no `returns` annotation in the statement
  corpus); the richer type-reference forms in catch / typed-decl / assert-throws types (union / postfix array-nullable /
  byref / tuple / `Func<>`) remain shared residual [3] (the corpus uses simple / qualified / generic type names). NO
  production wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged SDK 0.1.0 self-emitted
  the edited owner — incl. the `ParseBlock` refactor + all new parsers — + all 1078 contracts cleanly — no repin).
  Evidence: BootstrapServices contracts 1078/1078 (1033 baseline + 45; full-suite fresh no-build run,
  `-p:NSharpExcludeTests=false`; `FullyQualifiedName~Test_016Stmt` filter 70/70 = 45 new + 25 Stage-6); dev.sh Parser
  381/381; ownership audit 18/18 (`nlc test --project tests/native/ownership-audit`); git status shows ONLY the two
  `.nl` files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` /
  `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+editors+tests:
  zero references outside the owner + its tests), so nothing in the production compile path changed. No LSP/VS Code
  change → no extension reload. `ColumnarParserRecovery.nl` 4,854 → 5,826 lines (+972); `.tests.nl` 3,784 → 4,303
  (+519). RESIDUAL-TO-PARITY MAP (what remains for full Parser.cs syntax-diagnostic parity, after Stage 13):
  [1 — DONE] the remaining statement kinds (this stage); [2] the MEMBER grammars (method / constructor / nested-type /
  record-positional / union-case / interface / property) + the record / interface / union / enum / soa type BODIES
  (each with its own missing-`}` + special diagnostics, e.g. soa's "not supported yet"); [3] the richer type-reference
  forms (union / postfix array-nullable / byref / tuple / `Func<>`) shared across is/as/typeof/sizeof/cast/stackalloc/
  catch/typed-decl/local-func-return; [4] the TEST DSL (test / setup / teardown + the test-case rows) and ATTRIBUTES;
  [5] the garbage-type cascade shapes (non-`{` braced found-other, non-identifier parameter name, named-tuple bad-name)
  needing `ParseTypeReference`-on-garbage + the stable position-sorted emit (unblocked since Stage 12). THEN the
  AST/node-table-facts stage (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc (N+3). Next: STAGE 14 =
  the MEMBER grammars + type BODIES (map residual [2]), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED): STAGE 12 of the parser-front-end arc — the
  interpolated-string `$"…"` HOLE grammar (`ParseInterpolatedString`, Parser.cs :4932). Extended
  `ColumnarParserRecovery.nl` to carry the hole grammar through the SAME shared-panic model, PROVEN byte-exact
  against the freshly built Release CLI oracle (`nlc check --json`, NL101-NL109, excluding the columnar-backend
  emit-decline NL103 anchored at line 0). SITE INVENTORY (grep of `ParseInterpolatedString`): the whole `$"…"`
  is ONE outer token whose VALUE is char-scanned; the method has ZERO `Consume` sites and exactly ONE explicit
  ReportError — the NL101 "Unexpected token 'X' after interpolated string expression" hole-tail (:5141) — but
  EVERY hole-EXPRESSION error is produced by a FRESH sub-Lexer + sub-Parser (`new Parser(subTokens, _fileName)`,
  sourceCode=null → the CLI re-attaches the snippet by line number, verified) reaching the owned expression
  grammar. The scan carries `{{`/`}}` escapes, non-raw `\` escapes, the raw `{`-literal heuristic (:5019), position
  tracking through text/holes (`AdvancePosition` newline handling), the `braceDepth` + `inNestedString` hole-content
  scan (:5051), the raw-with-newlines literal edge (:5101), the format-clause `:` split via the live shared
  `ParserLiteralFacts.FindFormatSpecifierColon` (:5117, the same function Parser.cs calls), token position
  adjustment (`tok.Line + exprStartLine - 1` / same-line `tok.Column + exprStartCol - 1`, :5129-5135), and the
  closing-`}` consume. VERIFIED PANIC INDEPENDENCE (each probed against the oracle and pinned by a contract): each
  hole's sub-parser has its OWN `_panicMode`, so (a) TWO bad holes in one string BOTH report — `$"{a +} {b +}"` →
  two NL102, `$"{a b} {c d}"` → two NL101; (b) the OUTER parser's panic is UNAFFECTED by hole errors AND a hole
  error records even when the outer parser is mid-panic, because Parser.cs appends the sub-parser's errors via
  `_errors.AddRange(...)` which BYPASSES the outer panic gate — `print + $"{b +}"` → BOTH the outer prefix-plus
  NL103 AND the hole NL102; (c) WITHIN a hole the sub-panic cascades, so a hole-EXPRESSION error SUPPRESSES the
  hole-tail — `$"{+ a b}"` → only the prefix-plus NL103, the trailing `b` swallowed. IMPLEMENTATION: added the
  interpolated dispatch to `ParsePrimaryExprValue`'s string-literal arm (Parser.cs :4654-4657 — a `$"`-prefixed
  StringLiteral or an InterpolatedRawStringLiteral routes to `ParseInterpolatedString`; the malformed NL105 check
  still runs FIRST), reached through the Stage-6 block-body statement vehicle `func f() { print $"…" }` (the Stage-3
  `=>` expression body uses the minimal literal vehicle and does NOT descend `ParsePrimaryExprValue`, so the corpus
  uses the block vehicle); `ParseInterpolatedString` (the full char-scan port — the C# local closures
  `AdvancePosition`/`AppendText`/`EmitText` are inlined/dropped since N# has no first-class Func values AND the text
  parts carry no diagnostic); `ParseHoleExpression` (the fresh sub-parse — the recovery model is a SINGLE instance,
  so a hole SAVES the outer cursor/panic/split/boundary state, swaps in the position-adjusted + Newline-compacted
  sub-token stream with `PanicMode=false` (a fresh panic universe → hole errors record even under outer panic,
  reproducing the AddRange bypass), runs `ParseExprValue` + the hole-tail, then RESTORES the outer state (so the
  hole never affects the outer panic universe); Errors + Source are SHARED, so hole diagnostics accumulate and the
  CLI's by-line snippet re-attachment matches the model's Source-based snippet automatically; nested holes recurse
  naturally via the sub-parse's own `ParsePrimaryExprValue`); and the helpers `IndexOfCharFrom` /
  `RangeContainsNewline` / `ContainsNewline` / `EndsWithString` (a hand-rolled ordinal EndsWith so the owner needs
  no `import System`). Also added a STABLE position-sort to `ParseFilePreamble` mirroring the CLI's
  `OutputFormatter.DeduplicateAndSortDiagnostics` → `CodeIntelligenceResultKernels.DiagnosticIndexComesAfter`
  (File, Line, Column, stable index): a hole diagnostic is RECORDED before a following outer-expression diagnostic
  positioned EARLIER (e.g. `print $"{a +}" +` — the hole dangling at col 21 is recorded before the outer dangling
  span at col 18), and the CLI presents diagnostics position-sorted; the stable sort is a proven no-op for every
  already-in-order family (full suite 1033/1033, no Stage 1-11 contract moved). +21 native parity contracts in
  `ColumnarParserRecovery.tests.nl` (7 negatives: hole-free / single hole / two holes / format `{x:D3}` / escaped
  `{{ }}` / nested `{g($"{y}")}` / raw `$"""…"""`; dangling-hole NL102; hole-tail NL101; hole-tail-first-trailing-
  only; two-bad-holes-EACH-report NL102 [independence]; two-tails-EACH-report NL101; bad-first/good-second; good-
  first/bad-second; two-DIFFERENT-error-kinds independent; expr-error-SUPPRESSES-tail [sub-panic gate]; format-
  expr-bad [format stripped]; nested-bad-inner [recursive composed positions, col 26]; raw-hole-bad; INTERLEAVE
  outer-prefix-plus + hole BOTH report [outer panic does not suppress the hole]; INTERLEAVE hole-recorded-first-
  positioned-after outer-dangling [position-sort]). DEFERRED (recorded, NOT covered — with reasons): the EMPTY
  hole `$"{}"` — the sub-parse's unexpected-token terminal fires at the sub-EOF with `Current.Value.Length == 0`,
  and the check pipeline clamps the JSON length 0→1, so the model's raw CompilerError (length 0) is unmatchable
  against the clamped golden (length 1) — the SAME EOF-length-clamp class Stage 5 deferred for the EOF-anchored
  `ConsumeGreater`; the raw multi-line `{`-literal heuristic + raw-with-newlines literal edge are PORTED faithfully
  but corpus-light (single-line raw only — a multi-line raw string placed in the block vehicle would swallow the
  block's closing `}`). NO production wiring; NO wall tripped (self-contained edit to one owner + its tests; the
  packaged SDK 0.1.0 self-emitted the edited owner + all 1033 contracts cleanly — no repin). Evidence:
  BootstrapServices contracts 1033/1033 (1012 baseline + 21; full-suite fresh no-build run,
  `-p:NSharpExcludeTests=false`; interpolation-only filter 21/21); dev.sh Parser 381/381; ownership audit 18/18
  (18 native tests; ratchet 0 refs to any `.nl` — no movement); git status shows ONLY the two `.nl` files + STATUS
  (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` / `ParseFilePreamble`
  are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+editors+tests), so nothing in
  the production compile path changed. No LSP/VS Code change → no extension reload. `ColumnarParserRecovery.nl`
  4,476 → 4,854 lines (+378); `.tests.nl` 3,516 → 3,784 (+268). RESIDUAL-TO-PARITY MAP (what remains for full
  Parser.cs syntax-diagnostic parity, after Stage 12): [1] the remaining statement kinds (yield / break / continue /
  throw / try / using / lock / switch / allow / alloc-stmt / unsafe / assert / preprocessor / local-function /
  await-foreach / off) + the C-style `for i;c;n` / tuple-deconstruction / typed `name: T = value` declarations +
  the `on` subscription; [2] the MEMBER grammars (method / constructor / nested-type / record-positional /
  union-case / interface / property) + the record / interface / union / enum / soa type BODIES (each with its own
  missing-`}` + special diagnostics, e.g. soa's "not supported yet"); [3] the richer type-reference forms (union /
  postfix array-nullable / byref / tuple / `Func<>`) shared across is/as/typeof/sizeof/cast/stackalloc; [4] the
  TEST DSL (test / setup / teardown + the test-case rows) and ATTRIBUTES; [5] the garbage-type cascade shapes
  (non-`{` braced found-other, non-identifier parameter name, named-tuple bad-name) needing `ParseTypeReference`-on-
  garbage + position-sorted emit — NOW UNBLOCKED on the emit side by the stable position-sort added this stage.
  THEN the AST/node-table-facts stage (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc (N+3). Next:
  STAGE 13 = the remaining statement kinds (map residual [1]), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 11 of the parser-front-end arc — the remaining
  keyword-led primaries (map item [1]: alloc / stackalloc / lambda) + the `is`/`as` type sub-grammar (map item [2]).
  Extended `ColumnarParserRecovery.nl` to carry, through the SAME shared-panic model, four sub-families end-to-end,
  PROVEN byte-exact against the freshly built Release CLI oracle (`nlc check --json`, NL101-NL109, excluding the
  columnar-backend emit-decline NL103 anchored at Main.nl:1:1). ORIGIN INVENTORY (grep of Parser.cs): (a) the `is`/
  `as` TYPE arms (`ParseRelationalExpression` :4140/:4153) — both call `ParseTypeReference` (the type sub-grammar);
  `is` also consumes an optional trailing pattern-variable identifier (no diagnostic). Reused the already-owned
  `ParseTypeReferenceRecovery` (the simple / qualified / generic subset — the identical typeof / sizeof / cast type-
  reference vehicle), so the is/as type errors (missing type name NL102, qualified `.` NL102, `Name<>` generic-arg
  NL102, unclosed `>` NL102, reserved-keyword NL109) fire byte-exact; the `<` after an is/as type is absorbed as a
  generic open (verified). The invalid-relational default (:4177) is an unreachable dead arm (peeled before it).
  (b) the ALLOC primary (`ParseAllocExpression` :5178, dispatched :4747) — the guarded `Consume(Alloc)` never fires;
  the new / array-literal / string-primary / unary sub-shape all delegate to already-owned grammars, so alloc adds no
  new error site (missing-operand routes to the NL101 unexpected-token terminal; `alloc new` with no type to the
  Stage-10 ParseNewTypeReference NL102). (c) the STACKALLOC primary (`ParseStackAllocExpression` :5197, dispatched
  :4752) — element `ParseTypeReference` + `Consume(LeftBracket, "…after stackalloc element type")` (distinct NL102) +
  length `ParseExpression` + `Consume(RightBracket, "…after stackalloc length")` (NL108 next-line/EOF via the Stage-9
  closing-delimiter recovery, else the distinct NL102 when the mid-line offender declines recovery). (d) the LAMBDA
  family (`ParseLambdaOrAssignmentExpression` :3641) — single-param `x => …` (:3652, gated `Check(Identifier) &&
  LookAhead(1)==Arrow`) and multi-param `(x,y) => …` (:3681, gated `IsLambdaExpression` :5535 — a bounded lookahead
  admitting ONLY a well-formed `( ident, … ) =>`, so `ParseMultiParameterLambda`'s ConsumeIdentifier / Consume(
  RightParen) / Consume(Arrow) sites never fire; the ONLY reachable error is the missing lambda body via the already-
  owned `ParseRequiredExpressionAfter` with span `DiagnosticSpanFromTokenRange(paramOr'('→'=>')`). The `on`
  subscription prefix (:3649) is a separate deferred family. IMPLEMENTATION: added the is/as arms to `ParseRelational`;
  the alloc / stackalloc arms to `ParsePrimaryExprValue` (between unchecked and new, Parser.cs order); the two lambda
  prefixes to the top of `ParseExprValue` (Parser.cs ParseExpression→ParseLambdaOrAssignmentExpression, so every
  ParseExpression consumer allows lambdas) + the new `IsLambdaExpression` (pure token-scan, the IsGenericMethodCall
  idiom) and `ParseMultiParameterLambda`. DECISIONS reuse the live shared `ParserTokenFacts` and CONSTRUCTION
  delegates to the live shared `ParserErrorDiagnostics.Create`, so codes / messages / spans / snippets / hints /
  suggestions match automatically. +31 native parity contracts in `ColumnarParserRecovery.tests.nl` (is/as: 4
  negatives [is / is-with-var / as / is-generic], missing-type NL102 [is / as / in-arg], `List<>` generic-arg NL102,
  qualified-`.` NL102, unclosed-`>` NL102, reserved-keyword NL109, two-`is`-statement-boundary-reset [NL101 swallowed-
  name then NL102]; alloc: 3 negatives [new / array / in-arg], missing-operand NL101, `alloc new` missing-type NL102;
  stackalloc: 2 negatives [int[4] / generic-element], missing-`[` NL102, missing-type NL102, unclosed-`]` NL108,
  mid-line-`]`-declines-then-stray-`]` [NL102 + NL101]; lambda: 4 negatives [single / multi / empty / block-body],
  single missing-body NL102, multi missing-body NL102, missing-body-does-not-swallow-following-statement, two-
  functions-each-body-less [declaration-boundary reset]). RECUT (recorded, DEFERRED to STAGE 12 — with reason): the
  interpolated-string `$"…"` HOLE grammar (`ParseInterpolatedString` :4932) — its inventory shows ZERO Consume sites
  and exactly ONE explicit ReportError (the NL101 "Unexpected token 'X' after interpolated string expression" hole-
  tail), BUT that error AND every hole-EXPRESSION error are produced by a FRESH sub-Lexer + sub-Parser (`new Parser(
  subTokens, _fileName)`, sourceCode=null → the CLI re-attaches the snippet by line number, verified) with per-hole
  hole-content char-scanning (`{{`/`}}` escapes, format-`:` split, nested strings, raw-string multi-line) + token
  position adjustment (`tok.Line + exprStartLine - 1` / `tok.Column + exprStartCol - 1`) + separate-panic semantics
  — materially heavier than the other three families combined, its own coherent sub-slice. The malformed-`$"…"` NL105
  (unterminated single-line / raw) is ALREADY owned (Stage 3, via ReportMalformedStringLiteralIfNeeded). Also DEFERRED
  (shared with typeof / sizeof / cast): the richer type-reference forms the whole is/as/typeof/sizeof/cast sub-grammar
  routes through `ParseTypeReferenceRecovery` does not model — union `A | B` ("Expected a type after '|'…"), postfix
  array `[]` / nullable `?`, byref `&`, tuple `( … )`, `Func<>` — a later shared type-grammar extension; the corpus's
  is/as types are all simple / qualified / generic names. The multi-param lambda `on` subscription prefix (:3649).
  NO production wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged SDK 0.1.0 self-
  emitted the edited owner + all 1012 contracts cleanly — no repin). Evidence: BootstrapServices contracts 1012/1012
  (981 baseline + 31; full-suite fresh run, `-p:NSharpExcludeTests=false`); dev.sh Parser 381/381; ownership audit
  18/18 (all deltas `.nl`, no ratchet movement — verified 0 refs to any `.nl` in the growth-ratchet manifests); git
  status shows ONLY the two `.nl` files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A —
  `ColumnarParserRecovery` / `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep
  across src+editors+tests), so nothing in the production compile path changed. No LSP/VS Code change → no extension
  reload. `ColumnarParserRecovery.nl` 4,302 → 4,476 lines (+174); `.tests.nl` 3,146 → 3,516 (+370). RESIDUAL-TO-PARITY
  MAP (what remains for full Parser.cs syntax-diagnostic parity, after Stage 11): [1] the interpolated-string `$"…"`
  hole grammar (STAGE 12 — the fresh sub-Lexer/sub-Parser + position adjustment described above); [2] the remaining
  statement kinds (yield / break / continue / throw / try / using / lock / switch / allow / alloc-stmt / unsafe /
  assert / preprocessor / local-function / await-foreach / off) + the C-style `for i;c;n` / tuple-deconstruction /
  typed `name: T = value` declarations + the `on` subscription; [3] the MEMBER grammars (method / constructor /
  nested-type / record-positional / union-case / interface / property) + the record / interface / union / enum / soa
  type BODIES (each with its own missing-`}` + special diagnostics, e.g. soa's "not supported yet"); [4] the richer
  type-reference forms (union / postfix array-nullable / byref / tuple / `Func<>`) shared across is/as/typeof/sizeof/
  cast/stackalloc; [5] the TEST DSL (test / setup / teardown + the test-case rows) and ATTRIBUTES; [6] the garbage-
  type cascade shapes (non-`{` braced found-other, non-identifier parameter name, named-tuple bad-name) needing
  `ParseTypeReference`-on-garbage + position-sorted emit. THEN the AST/node-table-facts stage (N+1), the CUTOVER (N+2,
  IDE-affecting), and the DELETION arc (N+3). Next: STAGE 12 = the interpolated-string `$"…"` hole grammar (map
  residual [1]), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 10 of the parser-front-end arc — the POSTFIX
  CALL / INDEX / generic-call / `with {…}` + call-argument family (map item [1]) and the first KEYWORD-LED-PRIMARY
  tranche — new / cast / tuple / typeof (+ the cheap same-shape nameof / sizeof / checked / unchecked) / array
  (map item [2]). Extended `ColumnarParserRecovery.nl` to carry, through the SAME shared-panic model, these
  sub-grammars with their error sites, PROVEN byte-exact against the freshly built Release CLI oracle (`nlc check
  --json`, NL101-NL109, excluding the columnar-backend emit-decline NL103 anchored at Main.nl:1:1 — a backend
  diagnostic, not a parser one). Reached through the Stage-6 block-body statement vehicle `func f() { <expr> }`.
  ORIGIN INVENTORY (grep of ParsePostfixExpression + ParseArgumentList + ParsePrimaryExpression in Parser.cs):
  (a) POSTFIX (:4405) — the loop's INDEX `[…]`/`?[…]` arm (:4444, `Consume(RightBracket)` → NL108 via the Stage-9
  recovery, IndexAccess span = the OBJECT's :5948), the GENERIC-CALL `<…>(…)` arm (:4452 — `IsGenericMethodCall`
  :2025 bounded lookahead + `ParseCallTypeArguments` :2086 split-`>>`-aware + the "Expected '(' after generic type
  arguments" NL102 :4460, CallExpr span = the CALLEE's :5946), the CALL `(…)` arm (:4484), and the `with {…}` arm
  (:4500 — `Consume(LeftBrace)` / `ConsumeIdentifier`(property name) / `Consume(Colon)` / `Consume(RightBrace)` +
  an `EnsureProgress` that does NOT reset panic, unlike the new-object / match-case reset). (b) ARGUMENT LIST
  (`ParseArgumentList` :4533) — the `IsArgumentListRecoveryBoundary(Previous)` break (:4541 → :4615/:4622 +
  `IsContinuationRecoveryBoundary` :6927), the inline-out NL103 (:4561), and the spread `...` / named `name:` /
  bare alloc-family-keyword recognitions (:4587/:4579/:4595, each consuming without a diagnostic); its closing `)`
  routes through the Stage-9 recovery (NL107). (c) KEYWORD-LED PRIMARIES (`ParsePrimaryExpression` :4626) —
  typeof / nameof / sizeof (:4700/:4709/:4718) and checked / unchecked (:4728/:4738), all the `( expr | Type )`
  paren-wrapped shape (`Consume(LeftParen)` NL102 + the `)` via the Stage-9 recovery); `new` (`ParseNewExpression`
  :5209 — target-typed `new(args)` / `new { init }`, traditional `new Type[len]?(args)?{ init }?`,
  `ParseNewTypeReference` :6579 "Expected type name" NL102 anchored on `new`, and the object / collection / sized-
  array initializer loops with the panic-RESET-on-natural-progress discipline :5334/:5268 + `ReportMissingObjectInitializerColon`
  :6605 + `ParseObjectInitializerMemberValue` :5345); the immutable / plain ARRAY literal (`ParseArrayLiteral`
  :5407, `[` … `]` → NL108 via recovery); the CAST `(Type)expr` (:4783), disambiguated from tuple / paren by the
  full `IsCastExpression` lookahead (:5573 — its nested scan closures lowered to methods over two scan-state
  fields `ScanPosition`/`ScanSplit`, since N# has no first-class Func values), then `ParseUnary` operand; and the
  full TUPLE / parenthesized grammar (`ParseTupleOrParenthesizedExpression` :5428 — empty tuple, the recovery-
  boundary `<error>`, single paren, named tuple `(a: x, …)` with its `ConsumeIdentifier` / `Consume(Colon)` sites,
  and unnamed tuple `(a, b)`; ParenthesizedExpr span = INNER, TupleExpr span = the default). DECISIONS reuse the
  live shared `ParserTokenFacts` (`IsCastOperandStart` / `IsStatementStartKeyword` / `IsDeclarationKeyword` /
  `IsModifierKeyword`) and the owner's `IsTypeTerminator` / `IsMissingRequiredExpressionBoundary` / `ParseTypeReferenceRecovery`
  / `ConsumeGreater`; CONSTRUCTION delegates to the live shared `ParserErrorDiagnostics.Create`, so codes /
  messages / spans / snippets / hints / suggestions match automatically. +40 native parity contracts in
  `ColumnarParserRecovery.tests.nl` (call: inline-out NL103, unclosed-`)` NL107, named / spread / bare-alloc
  negatives; index: closed negative, unclosed-`]` NL108; gencall: closed / nested-generic-args negatives,
  unclosed-`)` NL107; with: closed negative, missing-`{` / missing-`:` / bad-name NL102, two-bad-props-report-ONCE
  [with-loop no-reset]; new: 5 negatives [new() / Foo() / {init} / Foo{init} / Foo[2]{coll}], missing-type NL102,
  object-init missing-`:` TWO diags [panic-reset-on-progress] + bad-name ONE diag, unclosed-`(` NL107 + unclosed-
  `[` NL108; cast: hard / unary-operand negatives; tuple: unnamed / named / empty negatives + named-missing-`:`
  NL102; typeof: closed negative + missing-`(` NL102 + unclosed-`)` NL107; nameof / sizeof negatives; array: closed
  negative + unclosed-`]` NL108; postfix: mixed member/call/index chain negative + two-functions-each-unclosed-call
  [declaration-boundary reset]). DEFERRED (recorded, NOT covered — with reasons): the alloc / stackalloc primaries
  (`ParseAllocExpression` :5178 / `ParseStackAllocExpression` :5197 — their own sub-grammar; stackalloc has the
  distinct `Consume(LeftBracket, "…after stackalloc element type")` / `Consume(RightBracket, "…after stackalloc
  length")` messages) → next tranche; the `is`/`as` type sub-grammar; interpolation `$"…"` (ParseInterpolatedString)
  / lambda primaries; the named-tuple bad-NAME garbage cascade (`(x: 1, 5: 2)` → a 3-diagnostic cascade whose exact
  reproduction needs the ConsumeIdentifier-no-advance + ParseExpression recursion + reset interplay — the same
  garbage-type-cascade class Stage 4 deferred, kept out of the corpus); the generic-call ":4460" arm (modelled
  faithfully but not corpus-reachable — `IsGenericMethodCall` guarantees a `(` follows the `>`). NO production
  wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged SDK 0.1.0 self-emitted the
  edited owner — incl. the `IsCastExpression` scan-state port — + all 981 contracts cleanly — no repin). Evidence:
  BootstrapServices contracts 981/981 (941 baseline + 40; full-suite fresh run); dev.sh Parser 381/381; ownership
  audit 18/18 (all deltas `.nl`, no ratchet movement — verified 0 refs to `ColumnarParserRecovery` / any `.nl` in
  `non-nsharp-growth-ratchet.v1.json`); git status shows ONLY the two `.nl` files + STATUS (no non-N# file moved).
  Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` / `ParseFilePreamble` are referenced ONLY by
  this owner's own `.tests.nl` (verified by grep across src+editors+tests), so nothing in the production compile
  path changed. No LSP/VS Code change → no extension reload. `ColumnarParserRecovery.nl` 3,564 → 4,302 lines
  (+738); `.tests.nl` 2,741 → 3,146 (+405). RESIDUAL-TO-PARITY MAP (what remains for full Parser.cs syntax-
  diagnostic parity, after Stage 10): [1] the remaining keyword-led primaries — alloc / stackalloc / interpolation
  `$"…"` / lambda; [2] the `is`/`as` type sub-grammar; [3] the remaining statement kinds (yield / break / continue /
  throw / try / using / lock / switch / allow / alloc / unsafe / assert / preprocessor / local-function /
  await-foreach / off) + the C-style `for i;c;n` / tuple-deconstruction / typed `name: T = value` declarations;
  [4] the MEMBER grammars (method / constructor / nested-type / record-positional / union-case / interface /
  property) + the record / interface / union / enum / soa type BODIES (each with its own missing-`}` + special
  diagnostics, e.g. soa's "not supported yet"); [5] the TEST DSL (test / setup / teardown + the test-case rows)
  and ATTRIBUTES; [6] the garbage-type cascade shapes (non-`{` braced found-other, non-identifier parameter name,
  named-tuple bad-name) needing `ParseTypeReference`-on-garbage + position-sorted emit. THEN the AST/node-table-
  facts stage (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc (N+3). Next: STAGE 11 = the remaining
  keyword-led primaries (alloc / stackalloc first — cheap, then interpolation / lambda) + the `is`/`as` type
  sub-grammar (map items [1]+[2]), per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 9 of the parser-front-end arc — the
  CLOSING-DELIMITER recovery family. Extended `ColumnarParserRecovery.nl` to carry, through the SAME shared-panic
  model, the `Consume`-path closing-delimiter recovery + the block/type-body missing-`}` NL106 sites + the
  parameter trailing-comma recovery, PROVEN byte-exact against the freshly built Release CLI oracle (`nlc check
  --json`, NL101-NL109, excluding the columnar-backend emit-decline NL103 anchored at Main.nl:1:1 — a backend
  diagnostic, not a parser one). ORIGIN INVENTORY (grep of Consume + the delimiter helpers in Parser.cs): (a) the
  RECOVERY BRANCH — `Consume` (:6048) tries `TryReportMissingClosingDelimiter` (:6103) FIRST for a missing `)` /
  `]` (RightBrace is DECLINED, :6119): it reports the position-aware NL107 (`Missing closing ')'`) / NL108
  (`Missing closing ']'`) and returns a SYNTHETIC closing token so parsing continues. Two triggers: (i) crossed
  onto a LATER line or reached EOF (found==null, "reached the next line", :6148) → span via
  `GetMissingClosingDelimiterDiagnosticSpan` (:6164) → `TryFindUnmatchedOpeningDelimiter` (:6194, depth-tracked
  backward scan) → `TryGetDelimiterOwnerSpan` (:6237, anchors on the identifier/keyword `IsVisibleDelimiterOwner`
  :6268 that owns the delimiter, or the assigned name via `IsAssignmentAnchor` :6287 + `TryGetPreviousTokenOnLine`
  :6290), FALLING to the opening delimiter itself; (ii) a same-line BOUNDARY token (`IsSameLineMissingClosingDelimiterBoundary`
  :6309 — `{`/`}`/`]`/`:`/`=>`/`;` for `)`, `}`/`)`/`;` for `]`) stands in for the close (found!=null, "I found 'X'",
  span on the offender); a MID-LINE offender (not a boundary) DECLINES recovery (:6133) and takes the plain
  ExpectedToken path (NL102). (b) BLOCK missing-`}` (NL106) — `ParseBlock` (:2143) reports it directly (NOT via
  TryReport) both at EOF (:2205, "reached the end of the file") and at the `IsBlockClosingDeclarationStart` (:6964)
  found-declaration break (:2158, "I found 'class' … looks like a new declaration", does NOT advance). (c) TYPE-BODY
  missing-`}` (NL106) — `ParseMemberList` (:1396) reports it at EOF anchored on the `typeBodyDiagnosticSpan` (name,
  or the class/struct keyword for a `<error>` name). (d) PARAMETER trailing-comma — `ParseParameterList` (:761)
  reports `ReportMissingParameterAfterTrailingComma` (:6487, `DiagnosticSpanFromTokenRange(lastParameterStartToken,
  Previous)`, last-param-through-comma span) before its `Consume(RightParen)` (:819). IMPLEMENTATION: added the
  `TryReportMissingClosingDelimiter` result-carrier port (N# has no reference-typed out args → `ClosingDelimiterRecovery`
  / `TokenLookupResult` / `OwnerSpanResult` explicit carriers) + `GetMissingClosingDelimiterDiagnosticSpan` /
  `TryFindUnmatchedOpeningDelimiter` / `TryGetDelimiterOwnerSpan` / `FindTokenIndex` / `IsVisibleDelimiterOwner` /
  `IsAssignmentAnchor` / `TryGetPreviousTokenOnLine` / `IsSameLineMissingClosingDelimiterBoundary`, and hooked the
  recovery branch into `ConsumeToken` (so the EXISTING `new(` constraint close, the pattern list `]` / positional
  `)` closes, and the now-ConsumeToken-routed parameter `)` close all reach it with ZERO call-site churn); added
  `IsBlockClosingDeclarationStart` / `IsSoaRecordDeclarationStartAtOffset` + the `ParseBlockBody` found-declaration
  break + `ReportBlockMissingClosingBraceFoundDeclaration`; threaded the `typeBodyDiagnosticSpan` through
  `ParseClassName` / `ParseStructName` → `ParseTypeBodyIfPresent` → `ParseMemberList` and added its EOF NL106 report;
  and added the parameter trailing-comma recovery + `ReportMissingParameterAfterTrailingComma` to
  `ParseParameterListRecovery`. DECISIONS reuse the live shared `ParserTokenFacts` (`IsTypeDeclarationKeyword` /
  `IsModifierKeyword`) and CONSTRUCTION delegates to the live shared `ParserErrorDiagnostics.Create`, so codes /
  messages / spans / snippets / hints / suggestions match automatically. RETIRED the deferrals recorded across
  stages 4-8: Stage-4 parameter trailing-comma; Stage-5 `new(` missing-`)` (NL107 via the `where T: new(` constraint);
  Stage-6 block's own missing-`}` (both EOF + `IsBlockClosingDeclarationStart` found-declaration, now corpus-exercised);
  Stage-8 pattern-list `]` / positional `)` unclosed closes (NL108 / NL107). +13 native parity contracts (2 same-line-
  boundary/next-line NL107·NL108 triggers; 1 `new(` EOF NL107; 1 same-line-comma DECLINE→NL102; 1 parameter trailing-
  comma NL102; 2 block missing-`}` EOF + found-declaration NL106; 3 panic-model: two-unclosed-positionals-report-ONCE
  [cascade suppression, no per-case reset] + two-`new(`-functions-each-report [declaration-boundary reset] + found-
  declaration-then-type-body-EOF [two NL106, boundary reset]; 3 negatives: closed `new()`, class-after-closed-block,
  closed positional/list). DEFERRED (recorded, NOT covered — with reasons): the postfix CALL `(…)` / INDEX `[…]` /
  generic-call / `with {…}` + the call-argument families (`ParseArgumentList` inline-out / spread / named-args — their
  closing-delimiter close now routes through this recovery, but the argument grammar itself is unmodelled); the
  keyword-led primaries (new / alloc / stackalloc / cast / tuple / typeof / nameof / sizeof / checked / unchecked /
  array / immutable / interpolation / lambda — each opens its own Consume / closing-delimiter sub-grammar); the
  `is`/`as` type sub-grammar; the `ParseBlockBody` attribute-led / modifier-led-to-soa `IsBlockClosingDeclarationStart`
  arms (ported faithfully but corpus-exercised only via the direct `class` case); the parameter-list
  `IsParameterListRecoveryBoundary` early break; the soa/union/interface/record/enum type-body missing-`}` (NL106) at
  their own bodies (those bodies are unmodelled — later member-grammar stages); the non-`{` braced found-other
  (`class 5`) / non-identifier parameter name (`func f(5)`) garbage-type cascades (need `ParseTypeReference`-on-garbage +
  position-sorted emit). NO production wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged
  SDK 0.1.0 self-emitted the edited owner + all 941 contracts cleanly — no repin). Evidence: BootstrapServices contracts
  941/941 (928 baseline + 13); dev.sh Parser 381/381; ownership audit 18/18 (all deltas `.nl`, no ratchet movement — the
  growth ratchet does not track `.nl`, verified: 0 refs to any `.nl` in `non-nsharp-growth-ratchet.v1.json`); git status
  shows ONLY the two `.nl` files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A —
  `ColumnarParserRecovery` / `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep
  across src+editors+tests), so nothing in the production compile path changed. No LSP/VS Code change → no extension
  reload. `ColumnarParserRecovery.nl` 3,091 → 3,564 lines (+473); `.tests.nl` 2,533 → 2,741 (+208). RESIDUAL-TO-PARITY
  MAP (what remains for full Parser.cs syntax-diagnostic parity, after Stage 9): [1] postfix CALL/INDEX/`with` +
  call-argument families (ParseArgumentList: inline-out / spread / named-args); [2] keyword-led primaries (new / cast /
  tuple / typeof / array / interpolation / lambda / alloc / stackalloc / …); [3] the `is`/`as` type sub-grammar; [4] the
  remaining statement kinds (yield / break / continue / throw / try / using / lock / switch / allow / alloc / unsafe /
  assert / preprocessor / local-function / await-foreach / off) + the C-style `for i;c;n` / tuple-deconstruction / typed
  `name: T = value` declarations; [5] the MEMBER grammars (method / constructor / nested-type / record-positional /
  union-case / interface / property) + the record / interface / union / enum / soa type BODIES (each with its own
  missing-`}` + special diagnostics, e.g. soa's "not supported yet"); [6] the TEST DSL (test / setup / teardown + the
  test-case rows) and ATTRIBUTES; [7] the garbage-type cascade shapes (non-`{` braced found-other, non-identifier
  parameter name) needing `ParseTypeReference`-on-garbage + position-sorted emit. THEN the AST/node-table-facts stage
  (N+1), the CUTOVER (N+2, IDE-affecting), and the DELETION arc (N+3). Next: STAGE 10 = the POSTFIX CALL / INDEX /
  `with` + call-argument family (map item [1]) + the first keyword-led-primary tranche (new / cast / tuple / typeof /
  array, map item [2]), whose Consume / closing-delimiter sites now route through this Stage-9 recovery.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 8 of the parser-front-end arc — the
  MATCH / PATTERN diagnostic family (Stage-7's recorded cut B). Extended `ColumnarParserRecovery.nl` to carry,
  through the SAME shared-panic model, the match-expression + pattern-grammar diagnostics, PROVEN byte-exact against
  the freshly built Release CLI oracle (`nlc check --json`, NL101-NL109). ORIGIN INVENTORY (grep of
  ParseMatchExpression + the pattern helpers in Parser.cs): (a) MATCH — `ParseMatchExpression` (:5368) with
  `Consume(LeftBrace :5375 / Arrow :5391 / Comma :5397 / RightBrace :5402)` and the `EnsureProgress(startPosition)`
  per-case boundary (:5399) that — UNLIKE the union per-case reset (:1216) or the object-initializer per-element
  reset (:5269/:5335) — does NOT reset `_panicMode`, so a pattern/arrow/comma error cascade-suppresses the rest of
  the match until the enclosing statement/declaration boundary resets it (block boundary :2172); (b) PATTERN GRAMMAR
  — `ParsePattern` (:3263) → `ParseOrPattern` (:3269) → `ParseAndPattern` (:3285) → `ParseNotPattern` (:3301) →
  `ParseRelationalPattern` (:3315, comparison-operator prefix over a PRIMARY value) → `ParsePrimaryPattern` (:3335:
  list `[…]` / slice `..` / positional `(…)` / literal / object `{…}` / identifier-led qualified-name / union-case /
  type / identifier), terminating in the "Invalid pattern. Got 'X'" NL103 (:3440, keyword-and-operator offenders,
  span = `Current.Value.Length`, NO advance); (c) the pattern QUALIFIED NAME `A.B` ConsumeIdentifier("Expected
  identifier after '.'") (:3417, NL102 dot-access variant); (d) PROPERTY PATTERNS — `ParsePropertyPatterns` (:3459)
  property-name ConsumeIdentifier (:3468, NL102 found / NL109 reserved-keyword) + the closing RightBrace (:3494).
  IMPLEMENTATION: added the `match` keyword-led primary arm to `ParsePrimaryExprValue` (Parser.cs :4764 — the
  MINIMAL match vehicle Stage 7 deferred, reached through the Stage-6 block-body statement grammar `func f() { match
  … }`), `ParseMatchExpression` (value / `when` guard / case body all descend the full Stage-7 `ParseExprValue`
  ladder), the seven pattern-tier parsers, `ParsePropertyPatterns`, and a shared `EnsureProgress` helper
  (Parser.cs :6709); extended `GetHintForMissingToken` to the full Parser.cs :6345 mirror (RightParen / RightBrace /
  RightBracket / Semicolon) so the match / property-pattern `Consume(RightBrace)` NL102 carries its hint (RightBrace
  is NOT in `TryReportMissingClosingDelimiter`, so it takes the standard Consume path). CONSTRUCTION delegates to the
  live shared `ParserErrorDiagnostics.Create`, and the decisions reuse the live shared `ParserTokenFacts` /
  `Lexer.IsReservedKeyword`, so codes / messages / spans / snippets / hints match automatically. +18 native parity
  contracts in `ColumnarParserRecovery.tests.nl` (4 invalid-pattern terminal: `+` / `*` / reserved `return` /
  guard-`when`; 4 match Consume: missing `{` / missing `=>` [arrow] / missing `,` / EOF-comma NL104; 3 property:
  bad-name NL102 / reserved-kw NL109 / object-missing-`}` re-enters-loop NL102; 1 qualified-name dot-access NL102;
  2 panic-model: two-bad-patterns-in-one-match report ONCE [cascade suppression, no per-case reset] + two-separate-
  match-statements each report their first [statement-boundary reset]; 4 negatives: literal/ident/type,
  relational/or/and/not, list/positional/object/union-case/guard, slice patterns). DEFERRED (recorded, NOT covered —
  with reasons): the list `]` / positional `)` UNCLOSED closes route through `TryReportMissingClosingDelimiter`
  (RightBracket→NL108 / RightParen→NL107) — the closing-delimiter recovery family, a later arc stage (ConsumeToken
  here reproduces the CLOSED present-delimiter case byte-exact and the corpus keeps every list/positional/object
  pattern closed); the `is`/`as` relational operators (type sub-grammar) and complex guard/value expressions reuse
  the Stage-7 ladder (the corpus uses only simple values). NO production wiring; NO wall tripped (self-contained edit
  to one owner + its tests; the packaged SDK 0.1.0 self-emitted the edited owner + all 928 contracts cleanly — no
  repin). Evidence: BootstrapServices contracts 928/928 (910 baseline + 18); dev.sh Parser 381/381; ownership audit
  18/18 (all deltas `.nl`, no ratchet movement — the growth ratchet does not track `.nl`, verified: 0 refs to
  `ColumnarParserRecovery` / any `.nl` in `non-nsharp-growth-ratchet.v1.json`); git status shows ONLY the two `.nl`
  files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` /
  `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+tests+editors),
  so nothing in the production compile path changed. No LSP/VS Code change → no extension reload. Next: STAGE 9 =
  the CLOSING-DELIMITER recovery family (`TryReportMissingClosingDelimiter` — missing `)` NL107 / `]` NL108 / `}`
  NL106), then the postfix call/index/`with` + remaining keyword-led primaries, per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 7 of the parser-front-end arc — the
  EXPRESSIONS diagnostic family (recut A: the core precedence ladder + the leading expression ERROR families;
  match/patterns deferred to a follow-on stage). Extended `ColumnarParserRecovery.nl` by replacing Stage-6's
  shallow assignment/additive/multiplicative statement-expression subset with the FULLER Parser.cs precedence
  ladder and carrying the expression ERROR families Stages 3/6 deliberately kept panic-suppressed, all through
  the SAME shared-panic model, PROVEN byte-exact against the freshly built Release CLI oracle (`nlc check --json`,
  NL101-NL109, excluding the columnar-backend emit-decline NL103 — a backend diagnostic anchored at a nonzero line,
  not a parser diagnostic). ORIGIN INVENTORY (grep of ParseExpression + the ladder + ParsePrimaryExpression in
  Parser.cs): (a) the LADDER — `ParseAssignmentExpression` (:3690) → `ParseTernaryExpression` (:4009) →
  `ParseNullCoalescingExpression` (:4033) → `ParseLogicalOr/AndExpression` (:4047/:4061) →
  `ParseBitwiseOr/Xor/AndExpression` (:4075/:4089/:4103) → `ParseEqualityExpression` (:4117) →
  `ParseRelationalExpression` (:4132) → `ParseShiftExpression` (:4205) → `ParseAdditiveExpression` (:4220) →
  `ParseMultiplicativeExpression` (:4235) → `ParseRangeExpression` (:4280) → `ParseUnaryExpression` (:4316) →
  `ParsePostfixExpression` (:4405) → `ParsePrimaryExpression` (:4626); (b) UNEXPECTED-TOKEN-IN-EXPRESSION — the
  `ParsePrimaryExpression` terminal arm (:4813, NL101 `UnexpectedToken`) + `ShouldSkipUnexpectedExpressionToken`
  (:6943); (c) PREFIX `+` — `ParseInvalidPrefixPlusExpression` (:3816, NL103 `InvalidSyntax`, the plus-through-operand
  `DiagnosticSpanFromTokenRange` span), reached from `ParseUnaryExpression` (:4318); (d) LEADING `.` —
  `ParseLeadingMemberAccessWithoutReceiver` (:6407), reached from `ParsePrimaryExpression` (:4631); (e) TERNARY —
  the missing-then / missing-else `ParseRequiredExpressionAfter` sites (:4016/:4022, through-token spans) + the
  missing-`:` generic `Consume(Colon, "Expected ':' in ternary expression")` (:4021); (f) DANGLING BINARY OPERATOR —
  `ParseBinaryRightOperandOrMissing` (:3778) → `ParseRightOperandOrMissing` (:3750) with the
  `DiagnosticSpanFromExpressionThroughToken` span, now fired across every ladder tier; (g) await/must/throw
  MISSING-OPERAND — `ParseUnaryOperandOrMissing` (:3789, `IsMissingRequiredExpressionBoundary`-gated, the distinct
  "Add … or remove '…'" hint); (h) MEMBER-NAME-AFTER-DOT — `ReportMissingMemberNameAfterDot` (:6385, receiver-anchored)
  + the reserved-keyword member `ReportReservedKeywordAsName(…, isDotAccess: true)` (:4433), reached from
  `ParsePostfixExpression`. IMPLEMENTATION: rewrote the statement-expression entry `ParseExprValue` to descend the
  full ladder (each binary tier accumulates the operator-position `(line,column,1)` `DiagnosticSpanFromExpression`
  default that a `BinaryExpression` yields, so the following dangling operator's through-token span is byte-exact);
  added `ParseTernary`/`ParseNullCoalescing`/`ParseLogicalOr`/`ParseLogicalAnd`/`ParseBitwiseOr`/`ParseBitwiseXor`/
  `ParseBitwiseAnd`/`ParseEquality`/`ParseRelational`/`ParseShift`/`ParseRange`/`ParseUnary`/`ParsePostfix`/
  `ParseMemberAccess`, the `BinaryRightOperandMissing`/`RightOperandMissingWithSpan` operand-missing helpers (replacing
  the Stage-6 `additiveOperand`-bool variant, since N# has no first-class `Func<Expression>`), `ParseInvalidPrefixPlusExpression`,
  `ParseUnaryOperandOrMissing`, `ReportMissingMemberNameAfterDot`, `ParseLeadingMemberAccessWithoutReceiver`, and
  `ShouldSkipUnexpectedExpressionToken`; rewrote `ParsePrimaryExprValue` into the full primary (leading-dot / int-float /
  char-string malformed / true-false-null / default / this / base / parenthesized / identifier / the unexpected-token
  terminal). The boundary DECISIONS reuse the live shared `ParserTokenFacts` (`IsAssignmentOperator` /
  `CanStartExpression` / `IsExpressionTerminator` / `IsStatementStartKeyword` / `IsDeclarationKeyword` /
  `IsModifierKeyword`, identical to Parser.cs), and CONSTRUCTION delegates to the live shared `ParserErrorDiagnostics.Create`,
  so codes / messages / spans / snippets / hints match automatically. +35 native parity contracts in
  `ColumnarParserRecovery.tests.nl` (8 leading-family: unexpected `*`, prefix `+`, leading `.`, trailing-`.` member,
  reserved-keyword member, ternary missing-then / missing-`:` / missing-else; 9 dangling-per-tier: `?? || && | ^ & == <
  <<` [additive `+` / multiplicative already Stage-6]; 3 await/must/throw missing-operand; 5 panic-model: initializer-
  terminator `)` [missing-init NL102 then the reset-boundary unexpected-token NL101], two dangling operators in
  different statements, unexpected-token-skip-then-valid-statement, within-expression prefix-plus cascade suppression,
  a leading-dot error then a dangling operator across the DECLARATION boundary; 10 negatives: `a||b&&c`, `a<b`, `!a`,
  `a.b.c`, `a?.b`, `a?b:c`, `(a+b)*c`, `a..b`, `a++`, `a<<b`). DEFERRED (recorded, NOT covered — with reasons): the
  MATCH / PATTERN family (`ParseMatchExpression` :5368 — `Consume(LeftBrace/Arrow/Comma/RightBrace)` + `ParsePattern`
  :3263 → `ParsePrimaryPattern` :3335 terminal "Invalid pattern. Got 'X'" [NL103] + the list `Consume(RightBracket)`
  / positional `Consume(RightParen)` / qualified-name `ConsumeIdentifier` sites + `ParsePropertyPatterns` :3459) — the
  "match/patterns second" recut half, its own follow-on stage; the `is`/`as` relational operators (parse a type
  reference — the type sub-grammar); postfix CALL `(…)` / INDEX `[…]` / generic-call `<…>(…)` / `with {…}` (the
  call-argument + closing-delimiter families — `ParseArgumentList`'s inline-out / spread / named-args / missing `)`
  `]` `}`); the keyword-led primaries (new / alloc / stackalloc / match / immutable / array / cast / tuple / typeof /
  nameof / sizeof / checked / unchecked / spread / interpolation / lambda — each opens its own sub-grammar with
  Consume / closing-delimiter sites; Parser.cs would not reach the unexpected-token terminal for them, so their
  absence keeps that arm byte-exact); and the four INVALID-OPERATOR default arms (`ParseAssignmentExpression` :3718 /
  `ParseRelationalExpression` :4177 / `ParseMultiplicativeExpression` :4253 / `ParseUnaryExpression` :4348) — proven
  UNREACHABLE dead defaults (each `switch` is guarded by an exact-match fact — `IsAssignmentOperator` and the
  while/if token checks — that admits only tokens the switch already handles, so the default never fires and cannot be
  reached byte-exact). The Stage-3 `=>` expression-body and Stage-4 field-`:=` init still use the minimal
  `ParseLiteralBearingExpression` vehicle (a validated byte-exact subset for their corpora); unifying them onto the
  full ladder is a later mechanical cleanup. NO production wiring; NO wall tripped (self-contained edit to one owner +
  its tests; the packaged SDK 0.1.0 self-emitted the edited owner + all 910 contracts cleanly — no repin). Evidence:
  BootstrapServices contracts 910/910 (875 baseline + 35); dev.sh Parser 381/381; ownership audit 18/18 (all deltas
  `.nl`, no ratchet movement — the non-nsharp growth ratchet does not track `.nl`); git status shows ONLY the two `.nl`
  files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` /
  `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by grep across src+tests+editors),
  so nothing in the production compile path changed. No LSP/VS Code change → no extension reload. Next: STAGE 8 =
  match/patterns (the deferred `ParseMatchExpression` + pattern family), then closing-delimiter recovery, per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 6 of the parser-front-end arc — the
  STATEMENT diagnostic family. Extended `ColumnarParserRecovery.nl` with the block-body statement grammar (a real
  `func f() { … }` vehicle Stages 3-5 deliberately left unparsed) and carried the statement diagnostics through the
  SAME shared-panic model, PROVEN byte-exact against the freshly built Release CLI oracle (`nlc check --json`,
  NL101-NL109, excluding the line-0 columnar-backend decline NL103 — not a parser diagnostic).
  ORIGIN INVENTORY (grep of ParseStatement + its helpers in Parser.cs): (a) the SYNC POINT + BOUNDARY RESET —
  `ParseBlock` (:2143) resets `_panicMode` at each statement (:2172), tracks `_currentRecoveryBoundaryColumn`
  (:2177), and on no progress calls `SynchronizeToNextStatement` (:2188 → :7084, which resets panic +
  `_splitGreaterDepth` and skips to a closing brace / statement-start / type-declaration keyword); (b) the
  DANGLING BINARY/ASSIGNMENT OPERATOR — `ParseRightOperandOrMissing` (:3750) / `ParseBinaryRightOperandOrMissing`
  (:3778) report "Expected expression after 'X'" with the `DiagnosticSpanFromExpressionThroughToken` (:3842)
  left-operand-through-operator span, gated by `IsMissingOperandBoundary` (:6908, the recovery-boundary-column
  rule that stops the operator swallowing the following statement — `Parser_DanglingBinaryOperator_...`); (c) the
  MISSING-INITIALIZER `:=`/`=` and MISSING-CONDITION if/while — `ParseRequiredExpressionAfter` (:3855) with
  `IsMissingRequiredExpressionBoundary` (:3928) / `LooksLikeStatementStartAfterRequiredExpression` (:3946) /
  `ShouldUnderlineAnchorForMissingRequiredExpression` (:3887), anchored on the declaration target
  (`DiagnosticSpanFromExpression` :5917) or the keyword; (d) the MISSING for/foreach `in` —
  `ReportMissingInKeywordAndRecover` (:3908, keyword-anchored, returns a synthetic `in`); (e) the
  MISSING-STATEMENT-BODY — `IsMissingStatementBodyBoundary` (:3961) / `ReportMissingStatementBody` (:3968),
  reached through the `blockOwnerSpan` threaded into `ParseStatement` for if/while/for bodies. IMPLEMENTATION:
  extended the function head (`ParseFunctionHeadAndBody`) with the block-body branch (Parser.cs :498), and added
  `ParseBlockBody` / `ParseStatement` (let/const/readonly, if, for, foreach, while, return, print, block,
  expression-statement) + a deliberately shallow expression subset (assignment over additive/multiplicative over
  identifier/literal/bool/null/parenthesized primaries) that reproduces the two diagnostic-bearing behaviours
  (the dangling operator + its through-token span) byte-exact and consumes well-formed operands identically. The
  boundary DECISIONS reuse the live shared `ParserTokenFacts` (`IsStatementStartKeyword` / `CanStartExpression` /
  `IsExpressionTerminator` / `IsAssignmentOperator` / `IsModifierKeyword` / `IsDeclarationKeyword` /
  `IsTypeDeclarationKeyword`, identical to Parser.cs), and CONSTRUCTION delegates to the live shared
  `ParserErrorDiagnostics.Create`, so codes / messages / spans / snippets / hints match automatically. +25 native
  parity contracts in `ColumnarParserRecovery.tests.nl` (13 single-diagnostic: dangling `+`, dangling `=`,
  shorthand `:=` no-init, `let`/`const` no-init, `print` no-expr, `while`/`if` no-condition, `foreach`/`for`
  missing-`in`, `if`/`while`/`for-in` missing-body; 5 panic-model: two-`:=` statement-boundary reset,
  within-statement cascade suppression (`while` no-cond+no-body → 1), a valid statement between two errors,
  dangling-then-missing-init across the DECLARATION boundary, nested-block per-statement reset; 7 negatives:
  well-formed decl+print, binary, assignment, `while true { }`, `foreach … in …`, bare `return`, empty body).
  DEFERRED (recorded, NOT covered — with reasons): the C-style `for init; cond; iter` loop, tuple deconstruction,
  typed `name: T = value` declarations, and the remaining statement kinds (yield / break / continue / throw /
  try / using / lock / switch / allow / alloc / unsafe / assert / preprocessor / local-function / await-foreach /
  off) are later arc stages (each adds its own ReportError sites under the same shared-panic model); the full
  expression precedence ladder (ternary / coalescing / logical / bitwise / equality / relational / shift / range /
  unary / postfix / call / member / index) and the expression ERROR families (unexpected token, prefix `+`,
  leading `.`) belong to the expressions/patterns stage; the block's own missing-`}` (NL106) report +
  `IsBlockClosingDeclarationStart` break are reproduced-but-not-corpus-exercised (every corpus body is closed and
  free of nested type declarations) — the broader closing-delimiter family (missing `)`/`]`/`}`) stays a later
  arc stage. NO production wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged SDK
  0.1.0 self-emitted the edited owner + all 875 contracts cleanly — no repin). Evidence: BootstrapServices
  contracts 875/875 (850 baseline + 25); dev.sh Parser 381/381; ownership audit 18/18 (all deltas `.nl`, no
  ratchet movement); git status shows ONLY the two `.nl` files + STATUS (no non-N# file moved). Full unit suite /
  corpus IL sweeps N/A — `ColumnarParserRecovery` / `ParseFilePreamble` are referenced ONLY by this owner's own
  `.tests.nl` (verified by grep across src+tests+editors), so nothing in the production compile path changed. No
  LSP/VS Code change → no extension reload. Next: STAGE 7 = expressions/patterns (the expression ERROR families +
  the full precedence ladder) per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 5 of the parser-front-end arc — the
  GENERICS / CONSTRAINTS diagnostic family. Extended `ColumnarParserRecovery.nl` to carry, through the SAME
  shared-panic model, four sub-families end-to-end, PROVEN byte-exact against the freshly built Release CLI oracle
  (`nlc check --json`, NL101-NL109, excluding the columnar-backend decline NL103 — not a parser diagnostic).
  ORIGIN INVENTORY (grep of Parser.cs): (a) TYPE PARAMETER NAMES — `ParseTypeParameters` (:725) funnels the name
  through `ConsumeIdentifier` (:743, reserved-keyword variant reachable) and reports `ReportMissingTypeParameterName`
  (:6439, `DiagnosticSpanFromTokenRange(lessToken, Current)`) for the empty `<>` / trailing-comma `<T,>` shapes;
  the list closes with the generic `Consume(Greater)` (:747, NOT the split-aware ConsumeGreater →
  TokenTypeToString(Greater)="greater"); (b) GENERIC TYPE ARGUMENTS — the generic type-reference `Name<…>`
  (:1925-1957) reports `ReportMissingGenericTypeArgument` (:6457, `DiagnosticSpanFromTokenRange(typeNameToken,
  Current)`, message interpolates the type name + opening `<`) for `Name<>` / `Name<T,>`; (c) the `ConsumeGreater`
  split-`>>` discipline (:2101) — the `>>`-split mechanism (`_splitGreaterDepth` + the split-aware Check :6025 /
  Advance :5860; reset at the sync points :7042/:7086) so a well-formed nested generic `List<List<int>>` reports
  NOTHING, plus the "Expected '>'. Got 'X'" ExpectedToken error (:2121) when a type-argument list is left unclosed;
  (d) the `where`-clause constraints (`ParseGenericConstraints` :851) — the "Expected type parameter"
  `ConsumeIdentifier` name error (:861), the missing-`:` `Consume(Colon)` error (:862), and the class/struct
  mutual-exclusion (:901) and struct/new() redundancy (:915) `InvalidSyntax` validations with the
  `LaterToken`/`TokenLengthOrFallback`/`TokenSpanLengthOrFallback` anchoring (:6010/:5897/:5900). IMPLEMENTATION:
  routed the function head through `ParseTypeParameters` (after the name, before the params — Parser.cs :446) + a
  generic-aware `ParseTypeReferenceRecovery` for the return type (Parser.cs :475, the ReportMissingGenericTypeArgument
  + ConsumeGreater vehicle) + `ParseGenericConstraints` (after the return type — Parser.cs :488); added
  `ParseTypeParameters` to the class/struct declaration heads (Parser.cs :943/:988 — a no-op for the non-generic
  Stage-4 class corpus). Diagnostic CONSTRUCTION delegates to the live shared `ParserErrorDiagnostics.Create`, and
  the constraint DECISIONS mirror Parser.cs exactly (`GetHintForMissingToken(Greater/Colon)`=null, the constraint
  validation `LaterToken` + span-length math ported verbatim, incl. the "…not permitted in ." message typo), so
  codes / messages / spans / snippets / hints match automatically. +22 native parity contracts in
  `ColumnarParserRecovery.tests.nl` (4 type-param-name: empty `<>` / trailing-comma `<T,>` / class-`<>` /
  reserved-keyword; 3 generic-arg: empty / trailing-comma / named-type; 1 ConsumeGreater unclosed; 1 split-`>>`
  well-formed-nested NEGATIVE; 2 constraint validations: class+struct / struct+new(); 3 constraint name/colon:
  missing-name / reserved-keyword / missing-`:`; 1 non-type-constraint cross-boundary cascade (NL102 + boundary-reset
  NL101); 2 two-function boundary-reset (type-param / generic-return); 5 well-formed negatives). DEFERRED (recorded,
  NOT covered — with reasons): the EOF-anchored `ConsumeGreater` (the check pipeline clamps its JSON length 0→1 —
  Current.Value at EOF is "" so length 0 at the CompilerError level, unmatchable against the clamped golden); the
  `new(` missing-`)` (emits NL107 `Missing closing ')'` via `TryReportMissingClosingDelimiter` — the closing-delimiter
  recovery stage, deferred); class/interface/union/record/soa/method type-params (soa additionally reports the "soa
  record type parameters are not supported yet" special diagnostic) and class/interface/union bodies — later stages;
  classes do NOT take `where` clauses (verified: `class C<T> where …` cascades to 3 diagnostics), so the constraint
  family is function-only this stage. NO production wiring; NO wall tripped (self-contained edit to one owner + its
  tests; the packaged SDK 0.1.0 self-emitted the edited owner + all 850 contracts cleanly — no repin). Evidence:
  BootstrapServices contracts 850/850 (828 baseline + 22); dev.sh Parser 381/381; ownership audit 18/18 (all deltas
  `.nl`, no ratchet movement); git status shows ONLY the two `.nl` files + STATUS (no non-N# file moved). Full unit
  suite / corpus IL sweeps N/A — `ColumnarParserRecovery` / `ParseFilePreamble` are referenced ONLY by this owner's
  own `.tests.nl` (verified by grep across src+tests+editors), so nothing in the production compile path changed. No
  LSP/VS Code change → no extension reload. Next: STAGE 6 = statements (the `SynchronizeToNextStatement` sync point +
  the dangling-operator / missing-initializer / missing-condition shapes the ParserErrorTests pin) per the arc plan.
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 4 of the parser-front-end arc — the
  MEMBER / PARAMETER / FIELD declaration diagnostic family (the `:`/`:=` colon and type-annotation errors,
- Active sub-slice (016 arc, PRIOR TURN, LANDED — no commit): STAGE 4 of the parser-front-end arc — the
  MEMBER / PARAMETER / FIELD declaration diagnostic family (the `:`/`:=` colon and type-annotation errors,
  NL102 `ExpectedToken` / NL109 `ReservedKeywordAsName`). Extended `ColumnarParserRecovery.nl` to carry, through
  the SAME shared-panic model, four sub-families end-to-end, byte-exact against the freshly built Release CLI
  oracle. ORIGIN INVENTORY (grep of Parser.cs): (a) PARAMETERS — `ParseParameterList` (:751) funnels the name
  through `ConsumeIdentifier(message, diagnosticSpan?)` (:6720) with `GetMissingParameterNameDiagnosticSpan`
  (:6476, anchors a missing name on the following type token), the `:` through `ConsumeParameterColon` (:6625,
  anchors on the parameter NAME), and the type through `ParseParameterTypeReference` (:6504, name-anchored
  missing-type); (b) FIELDS — `ParseFieldDeclaration` (:1637) funnels the name through the no-span
  `ConsumeIdentifier` (:1666), the `:`/`:=` through `ConsumeFieldColon` (:6651), and the type through
  `ParseFieldTypeReference` (:6536) with the `LooksLikeNextFieldAfterMissingType` heuristic (:6572, so a
  following `Ident(:|:=)` on a later line is NOT swallowed as this field's type); (c) the MEMBER-BOUNDARY
  recovery — `ParseMemberList`'s per-member `_panicMode = false` reset (:1365) — proven by two malformed fields
  each reporting at their own member boundary; (d) the Stage-2-DEFERRED braced-kind found-other NAME, now
  reachable for the `{`-offender variant (`class {` / `struct {`), where the offending `{` is consumed as the
  empty body brace and panic suppresses the rest — RETIRING that deferred Stage-2 case. IMPLEMENTATION: routed
  the function head through a real `ParseParameterListRecovery` (empty `()` handled identically, so Stage-3's
  `func f() => <lit>` corpus is unaffected); extended `ParseClassName` / `ParseStructName` with
  `ParseTypeBodyIfPresent` (parses the braced body for a VALID name → fields, and for an `<error>` name ONLY
  when the offender is `{` — every other `<error>`-name shape keeps Stage-2 return-early, so no Stage-2
  multi-declaration case regresses); added `ParseMemberList` (member-boundary reset + force-advance),
  `ParseFieldMember`, the four `Consume*`/`Parse*TypeReference` reporters, and shared `IsTypeTerminator` /
  `IsVisibleName` / `TypeErrorAnchor` helpers. Diagnostic CONSTRUCTION delegates to the live shared
  `ParserErrorDiagnostics.Create`, and the field-type/parameter-type/colon DECISIONS reuse the live shared
  `ParserTokenFacts.IsTypeReferenceStart` (identical to Parser.cs), so codes / messages / spans / snippets /
  hints match automatically. +17 native parity contracts in `ColumnarParserRecovery.tests.nl` (7 parameter: the
  missing-`:` / missing-type / `:`-where-name-required found / reserved-keyword name / second-parameter-`:` /
  well-formed negative / two-functions-boundary-reset; 8 field: missing-`:`/`:=` / missing-type /
  member-boundary-reset (two malformed fields) / reserved-keyword field name / struct-body field / two-classes
  boundary reset / well-formed-field negative / empty-body negative; 2 braced found-other: `class {` / `struct {`).
  DEFERRED (recorded, NOT covered — with reasons): the non-`{` braced found-other (`class 5` / `struct 5`) emits a
  3-diagnostic cascade (name error → `Missing closing '}'` → in-body `Expected field name`) whose report order
  diverges from the oracle's position-sorted output and needs `ParseTypeReference`-on-garbage +
  `SynchronizeToNextStatement` + the sorted-emit order — a later stage; the non-identifier parameter name
  (`func f(5)`) cascade needs the same garbage-type reachability; the trailing-comma
  (`ReportMissingParameterAfterTrailingComma`), the missing-`)` / missing-`{` / missing-`}` (NL106/NL107)
  closing-delimiter recovery, and the method / nested-type / constructor / record-positional / union-case /
  interface member grammars (and record/interface/union bodies) are their own later arc stages. NO production
  wiring; NO wall tripped (self-contained edit to one owner + its tests; the packaged SDK 0.1.0 self-emitted the
  edited owner + all 828 contracts cleanly — no repin). Evidence: BootstrapServices contracts 828/828 (811
  baseline + 17); dev.sh Parser 381/381; ownership audit 18/18 (all deltas `.nl`, no ratchet movement); git
  status shows ONLY the two `.nl` files + STATUS (no non-N# file moved). Full unit suite / corpus IL sweeps N/A —
  `ColumnarParserRecovery` / `ParseFilePreamble` are referenced ONLY by this owner's own `.tests.nl` (verified by
  grep across src+tests), so nothing in the production compile path changed. No LSP/VS Code change → no extension
  reload. Next: STAGE 5 = generics / constraints (the `ConsumeGreater`, split `>>`, type-parameter /
  type-argument errors) per the arc plan.
- Prior sub-slice (016 arc, STAGE 3, LANDED — no commit): the parser-front-end arc — the
  MALFORMED-LITERAL diagnostic family (NL105 `InvalidLiteral`). Extended `ColumnarParserRecovery.nl` to carry the
  malformed-literal diagnostics — unterminated string, unterminated interpolated (single-line) string,
  unterminated char, empty char, unterminated triple-quoted string, unterminated interpolated raw string —
  through the SAME shared-panic model, byte-exact against the live-CLI oracle. ORIGIN INVENTORY (grep of
  Parser.cs + the N# Lexer): every malformed-literal diagnostic is REPORTED in `Parser.cs`
  `ParsePrimaryExpression` (:4646/:4653 → `ReportMalformedCharLiteralIfNeeded` :4905 /
  `ReportMalformedStringLiteralIfNeeded` :4830 → `ReportMalformedRawStringLiteralIfNeeded` :4876), each
  routing through the shared-panic `ReportError` (:6845). The already-N# `Lexer.nl` only CLASSIFIES
  (sets `Token.IsTerminated`, produces the token value); it emits NO diagnostic. The malformed DECISION reuses
  the LIVE shared N# owner `ParserLiteralFacts.IsCompleteStringLiteral`/`IsCompleteCharLiteral` (Parser.cs
  delegates to the identical calls). So the family belongs to the PARSER model (Parser.cs-reported,
  shared-panic-gated), NOT a separate lexer lane — carried in full this stage. Reached via the shallowest
  byte-exact expression context: the expression-bodied function `func f() => <literal>` (oracle-verified to
  emit exactly ONE NL105 per shape). Adds a MINIMAL literal-reaching expression path (paren + literal primary
  + minimal binary-operator continuation) as the vehicle — full expression grammar + the expression/statement
  ERROR families (unexpected-token-in-expression, dangling operator, missing `)`) stay a LATER arc stage; those
  would-be errors never fire here because they route through the SAME shared panic the literal error already
  set, so the diagnostic output stays byte-exact. Ported the three Parser.cs reporters faithfully
  (`ReportMalformedLiteralIfNeeded` → char / string / raw-string), delegating the DECISION to the live shared
  `ParserLiteralFacts` (identical to Parser.cs) and the CONSTRUCTION to `ParserErrorDiagnostics.Create`, so
  codes / messages / spans / snippets / hints match automatically. Extended `ParseFunctionName` to continue a
  validly-named function into its expression body (Stage-2 name-error cases preserved: a `<error>` name returns
  before any body parse). +14 native parity contracts in `ColumnarParserRecovery.tests.nl`: one per literal
  shape, plus panic interactions — across a DECLARATION boundary the next literal error fires (two malformed
  funcs → 2 diags; malformed literal then stray top-level token → NL105 + NL101), and IN-REGION a following
  malformed literal is SUPPRESSED by shared panic (`'a + 'b` / `'' + 'b` → 1 diag; the parenthesized `('a`
  suppresses the missing-`)` and anchors the char at column 14), plus negatives (well-formed literals report
  nothing). NO production wiring; NO wall (self-contained; packaged SDK 0.1.0 self-emits the edited owner +
  tests cleanly — including the `"""`-bearing message literals — no repin). Evidence: BootstrapServices
  contracts 811/811 (797 baseline + 14); dev.sh Parser 381/381; ownership audit 18/18 (all deltas `.nl`, no
  ratchet movement); git status shows ONLY the two `.nl` files + STATUS (no non-N# file moved). Full unit
  suite / corpus IL sweeps N/A — the owner is referenced ONLY by its own tests (verified), so nothing in the
  production compile path changed. No LSP/VS Code change → no extension reload. Next: STAGE 4 = member /
  parameter / field declaration diagnostics (the `:`/`:=` colon and type errors) per the arc plan.
- Prior sub-slice (016 arc, STAGE 2, LANDED — no commit): the DECLARATION-NAME diagnostic family.
  Extended `ColumnarParserRecovery.nl` to carry the "Expected <kind>
  name" diagnostics for func / class / struct / record / soa record / interface / union / enum / type-alias
  declarations through the SAME shared-panic model, with the `DiagnosticSpanFromToken` KEYWORD-ANCHORING
  discipline (a missing/invalid name underlines the DECLARATION KEYWORD, not the offending token, in all
  three ConsumeIdentifier variants) and the reserved-keyword-as-name variant. Added `ConsumeDeclarationName`
  (Parser.cs ConsumeIdentifier with a non-null diagnosticSpan), the `ParseTopLevelDeclaration` dispatch
  (ParseModifiers + the exact Parser.cs keyword order incl. `ref struct` / `soa record` / `duck interface`
  / `record struct` variants + LookAhead), the per-kind name parsers, and the boundary/force-advance loop
  (Parser.cs ParseCompilationUnit :83/:99-108). Bodies are NOT parsed (a later arc stage); the loop makes
  progress by consuming the keyword (and, for reserved-keyword recovery, the offender) or the stray token.
  +24 native parity contracts in `ColumnarParserRecovery.tests.nl` (per-kind absent-name / reserved-keyword,
  plus func/enum/type found-other + two panic-model interaction fixtures), proven byte-exact against golden
  live-CLI Parser.cs output (`nlc check --json`, NL101-NL109). NO production wiring; NO wall tripped
  (self-contained edit to one owner + its tests, packaged SDK emits it — no repin). Evidence: BootstrapServices
  contracts 797/797 (773 baseline + 24); ownership audit 18/18; git status shows only the two `.nl` files
  changed (no non-N# file moved). Next: STAGE 3 = the next-smallest family per the arc plan (malformed-literal:
  unterminated string/char/triple/interpolated, empty char).
- Prior sub-slice (016 arc, STAGE 1, LANDED — no commit): the shared-panic RECOVERY MODEL + import/namespace/
  package family. Added `ColumnarParserRecovery.nl` (Parser.cs `_panicMode` lifecycle: one shared flag,
  suppress-while-set, set-on-report, reset only at the declaration-boundary sync point; ordered reporting;
  the ConsumeIdentifier reserved-keyword/EOF/found variants + LastVisibleTokenSpan anchoring) + 11 golden
  parity contracts. Deleted the inert divergent `ColumnarSyntaxDiagnostics` scaffolding closure (see the arc
  plan's scaffolding-fate decision).
- CORRECTION (post-Stage-2): sub-slice 5's Min/Max deletion (`86f4c251b`) was PARTIALLY WRONG — its
  "provably dead" claim held only for plannable receivers. `Select(v => ...).Min()/.Max()` chains
  whole-subtree-exit to the legacy residual (contextual-lambda decline), where the deleted emit +
  preflight arms were load-bearing: tests/native/lambda-placement failed to emit at the checkpoint
  gate. The arms are RESTORED as fenced load-bearing residuals (retire with arc stages 3-4); the
  resolver-side ownership of plannable Min/Max receivers stands. LESSON (bar raised): every
  byte-exact corpus sweep MUST include the tests/native/* projects — the 59-assembly example/fixture
  sweep alone missed this; sub-slice 6's refutation of the identical premise for ToArray/ToList/
  Contains applied retroactively to 5 and nobody re-checked.
- Active sub-slice (THIS TURN, LANDED a net-negative deletion): the interpolation BASE-CALL
  CLASSIFICATION decision. CHOICE recorded pre-edit: move the string-classification half of
  `TryResolveInterpolationBaseCallPlan` (the `base.` prefix + `()` suffix parse and the method-name
  extraction/validation, deciding THAT an interpolated hole is a well-formed `base.<name>()` call and
  extracting the name) into the N# splitter owner `ColumnarInterpolationSplitter.TrySplitBaseCall(text,
  out methodName)` — an exact mirror of the accepted `TrySplitCast`/`TrySplitEquality`/`TrySplitCoalesce`
  splits (9a3c20950/aaddf...). The reflection-coupled resolution half (`_currentStruct?.BaseDef`,
  `TryFindMethodOnChain` over the base chain, and the return-type guards `void`/enum/generic-param/
  `ContainsBuilderBoundType`/`IsSupportedType`) STAYS C# as a mechanical host. Byte-exact verifiable on
  the live corpus path `examples/06-classes-and-records/ConstructorChaining.nl:56`
  (`$"{base.GetInfo()} - {EmployeeId} ({Department})"`). N# splitter +TrySplitBaseCall + tests; C#
  emitter net-negative (removes the const/prefix/suffix guard + the name-validation block, keeps the
  `BaseDef==null` reflection guard + mechanical resolution). This supersedes the case-12 prune below,
  which is now COMMITTED at 6e94ca88c.
- Prior committed sub-slice (6e94ca88c, "Prune the dead case-12 residual arms by four-surface liveness
  proof"): pruned the case-12 primitive-binary whole-subtree residual to its live reaching-set. Four sub-arms proven DEAD
  across ALL FOUR exercise surfaces — corpus+native (162 assemblies), units (3,190), and self-emit
  (BootstrapServices kernels, full 228-arm run) — via IL-neutral arm instrumentation (0 IL diff baseline
  vs instrumented across all 162 assemblies), then DELETED:
  * `case "&"|"|"|"^"` bitwise residual arm
  * record-struct structural-equality residual arm (`==`/`!=` boxing through the synthesized Equals)
  * the `null == null` / `null != null` constant fold
  * the multi-term string-concat CHAIN lowering (`TryEmitStringConcatChain` + its sole-caller
    `CanProveStringExpression`) — the residual pair-concat (`String.Concat(string,string)`) STAYS.
  ColumnarIlEmitter.cs 21,534 -> 21,438 (net -96 lines / -92 non-blank; epoch ceiling 21,723/20,646
  untouched). N# delta: ZERO — ColumnarPrimitiveBinaryPlanner / ColumnarConditionalPlanner already own
  these operators at the front door; the residual only served a non-plannable-OPERAND band that is
  empty for these four families. No test migration (dead-code deletion; live coverage = native
  primitive-binary 16/16 + conditional 8/8). SLICE-5 GUARD HONORED: a PARTIAL self-emit run (166 arms)
  showed `stringcharconcat` dead, but the COMPLETE run (228 arms) caught it firing late, so it was
  RETAINED — the exact slice-5 escape signature; every dead verdict waited for the full self-emit.
  * Candidate (a) BLOCKED (definitive record): the live preflight static-call arm (case-9
    `TryFindStaticMethodOnChain` on `_enclosingType`) types the user's OWN enclosing-type static-method
    call results (bare identifier, no receiver) — NOT external `ColumnarExternalBindingPlans` catalog
    facts (external static calls have a type-name receiver whose `TryGetPreflightExpressionType` returns
    false, so they never reach this arm). It FIRED on the corpus -> load-bearing, not dead. Six lines
    fused into the unified bare-call preflight tier (localfn->sibling->ownstruct->ownstatic); deleting it
    regresses user-static-call-result typing. Rerouting to an N# planner return-type is the forbidden
    add-a-planner-for-a-relocation anti-pattern (identical to the lambda-arc Candidate A rejection): no
    decision deleted, net N#+plumbing positive. The other corpus-dead preflight arms are BCL-shape
    (span/AsSpan/ArrayPool/MemoryPool/Stream — self-emit-live: the kernels use them) or lambda-family
    (where/toarray/minmax/contains — blocked with the lambda arc). No net-negative deletion in (a).
  * Candidate (b) partial blocks (definitive record): within the SAME residual, three more sub-arms fire
    in SELF-EMIT (kernel compilation) though dead in corpus+native+units, so RETAINED: the case-13
    ternary residual (kernels have 80 ternaries incl. `setter == null ? 0 : 1`, ColumnarDefinitions.nl:189,
    the exact form task 007 flagged; the N# ColumnarConditionalPlanner declines non-Boolean conditions +
    mixed-type arms, so the residual still serves them); reference-identity equality on user reference
    types (`==`/`!=`); and string+char concat (`TryEmitStringCharConcat`). Residual arith (`+`/`-`/`*`/`/`)
    and ordering (`<`/`<=`/`>`/`>=`) are all self-emit-live. These retire only as their non-plannable
    OPERAND forms become N#-plannable — a future four-surface-gated cut, not this turn.

- Lambda-taking LINQ ownership ARC — staged plan (concrete owners + deletion targets; ordered by the
  d2257f33c refutation, whose three blockers are the ground truth for why stages 3–5 must precede any
  enumerable-arm deletion):
  * Stage 1 (THIS TURN): contextual-lambda SIGNATURE binding → `ColumnarLambdaPlacementPlanner`; delete the
    C# param-binding loop in `TryEmitLambdaLiteral`. DONE.
  * Stage 2 (THIS TURN): contextual-lambda CAPTURE-SET collection → N#. Move `CollectLambdaCaptures` (the pure
    AST capture-name scan against the enclosing local/param/lifted name sets) into an N# owner; the
    non-capturing-vs-capturing branch consumes the N# capture set. Delete the C# `CollectLambdaCaptures`
    walk (~35 lines). The this-capture member-chain scan `BodyReferencesEnclosingChain` (needs the emitter's
    member-chain resolvers) and the display-class capturing residual stay C# until Stage 6.
  * Stage 3a (THIS TURN): contextual-lambda RETURN-TYPE inference DECISION → N#. DONE. The
    `TryInferSingleParameterContextualDelegateReturnType` decision (which of the two admitted argument forms —
    a contextual lambda body vs a visible local-function method group — supplies a single-parameter
    contextual delegate's return type, refutation blocker 2's `Select`-result / MapGet-return machinery) now
    routes to `ColumnarLambdaPlacementPlanner.PlanSingleParameterContextualReturnType` (lambda precedence,
    null → decline). The two duplicated single/zero-parameter inference helpers
    (`TryInferSingleParameterLambdaReturnType` + `TryInferZeroParameterLambdaReturnType`) collapsed into one
    mechanical host `TryPreflightContextualLambdaReturnType` that reuses the N#-owned `PlanContextualSignature`
    for the parameter-SHAPE decision (removing the third duplicated C# shape authority) and consumes the
    scoped sub-emitter body-preflight mechanically. Emitter 21,551 → 21,534 (net −17). GROUND TRUTH from the
    inventory: the inference's core (recursive body preflight = the C# expression-typing engine) and its
    validity gates (`IsSupportedType`/`TypesEquivalent`, reflection-bound) cannot move without porting the
    whole preflight engine, so they stay mechanical; only the SHAPE + SELECTION decisions were movable.
  * Stage 3b/4: PROVEN BLOCKED (re-inventoried THIS TURN, Candidate C). N# cannot own lambda-chain EMISSION
    or DELETE the enumerable EMIT+PREFLIGHT arms until the lambda BODY is plan-row-emittable: today a lambda
    body is emitted by a recursive C# sub-emitter (`new ColumnarIlEmitter(...)` at ColumnarIlEmitter.cs:1551 +
    `EmitLambdaBody` at :1566, NOT `ColumnarCodePlanExecutor` plan rows) and typed by the C# preflight engine
    (`TryPreflightContextualLambdaReturnType` → scoped sub-emitter body preflight). Stage 3a moved only the
    return-type SELECTION to N#; it did NOT unblock emission. Neither the chain-admission decision (Candidate A)
    nor the Cast/OfType type-argument binding (Candidate B) is a net-negative decision deletion (reasons in the
    Active sub-slice above). Proven byte-exact: neutralizing the three arms fails 8 corpus builds + 3 native
    projects with 0 common-file IL diffs — the arms are the sole load-bearing emitter of lambda-taking chains
    and Cast/OfType. RE-SEQUENCED: this family retires as a DEDICATED FUTURE TASK "plan-row lambda-body emitter"
    (whole-expression columnar emission of lambda bodies via schema plan rows executed by
    `ColumnarCodePlanExecutor`, + N# lambda-chain planning that retires the `ColumnarDirectCallPlanner.nl:112`
    contextual-lambda decline). Only after that lands can the old Stage 4 (below) delete the arms.
  * Stage 4 (GATED on the plan-row lambda-body emitter task above): DELETE the lambda-taking enumerable EMIT +
    PREFLIGHT arms (`TryEmitEnumerableExtensionCall` Where/Select/ToArray/ToList/Contains/Min/Max +
    `TryGetPreflightEnumerableExtensionCallType` mirror) — retires refutation blockers 1+2 together.
  * Stage 5 (Cast/OfType, separable from lambdas but a NEW-capability slice): the explicit-type-argument
    `TryEmitExplicitEnumerableExtensionGenericCall` Cast/OfType arm is lambda-free but its `TResult` is a
    return-type-only generic parameter the N# `ColumnarExtensionMethodResolver` cannot structurally bind (the
    explicit arg is never consumed by inference). Owning it needs N# explicit-type-argument extension-call
    support + ported type-node/member-chain resolution — a new capability, not a duplicated-fact deletion.
    Separable from Stage 4 and can precede or follow it.
  * Stage 5' (was Stage 5): receiver WIDENING with user-source-extension precedence — model user-source extension precedence
    in `ColumnarExtensionMethodResolver` so BCL generic `First`/`Last` never shadow user extensions
    (`examples/07-interfaces/ExtensionMethods.nl`, refutation blocker 3), then admit interface/variance
    receiver widening for the generic non-lambda arms. NOTE: the widening logic itself was proven correct in
    isolation but the `ColumnarExtensionMethodResolver` widening test was REVERTED with the refuted slice —
    contracts baseline is 740 (now 747 with Stage 1), NOT 741.
  * Stage 6: value-capture DISPLAY-CLASS lowering → N# (the fenced capturing residual in `TryEmitLambdaLiteral`,
    the `<>c__DisplayClass` `ModuleBuilder.DefineType` path) — model the reflection-emit display-class surface
    in the columnar backend and retire the C# capturing path.
- Refutation ground truth (d2257f33c, do not re-litigate): the `ToArray`/`ToList`/`Contains` family has NO
  deletion-ready subset before Stages 3–4 land. (1) the EMIT arms are LOAD-BEARING for lambda chains routed
  via the contextual-lambda decline; disabling ToArray makes WeatherDemo fail to build. (2) the PREFLIGHT
  arms are LOAD-BEARING for lambda RETURN-TYPE inference (MapGet `() => …ToList()`, Endpoints.nl:28) — only
  the byte-exact corpus IL diff catches the `List<IssueResponse>` → `object` regression; builds + the full
  unit suite do not. (3) receiver widening is not admission-safe until user-source-extension precedence is
  modeled (BCL `First`/`Last` shadow user extensions).
- Next smallest concrete sub-slice: NONE remaining as a movable-decision deletion. See the "015 completion
  roadmap" below (the exhaustive three-way policy inventory that replaces the former ad-hoc residual lists):
  after this slice the directly-MOVABLE decision surface is EXHAUSTED (base-call was the last inline
  string-classification split), and every remaining policy decision is BLOCKED-WITH-RECORD on a named future
  task or is already a MECHANICAL reflection-emit host. Do NOT reopen the lambda arms (blocked on the plan-row
  lambda-body emitter task), the case-12/13 live residual families (retire only under the four-surface gate as
  planner OPERAND forms unlock), or candidate (a) preflight static-call typing (load-bearing, not net-negative).
- Method note (this turn): the byte-exact product-IL sweep (scratchpad `verify_basecall.sh`: baseline HEAD via
  `git stash` vs working tree, both fresh Release CLIs, `sweepall.sh` over examples+fixtures+all 18 tests/native)
  yielded PRODUCT_IL_DIFFS=0 across all 162 N#-emitted assemblies. The only expected non-product diffs are the
  C# `Compiler.dll`/`BootstrapServices.dll` binaries copied as a reflection-test dependency by the six native
  reflection projects (they reflect any emitter/kernel source change); exclude them and compare only N#-EMITTED
  assemblies.
- Last committed ownership slice: the case-12 residual dead-arm prune at `6e94ca88c` (ratchet head
  `40cb7fa576abc6c2`, a fresh non-VS-Code gate is fully green there). This turn's base-call classification
  deletion is NOT committed (mandate: do not commit); the working tree carries the emitter deletion + the
  N# splitter `TrySplitBaseCall` + its tests + repin + this STATUS update.
- Prior accepted ownership commits: task 014's slice commits (`d396a847c`, `73ae226d5`,
  `0a33f1ff2`, `f3d1e89c9`).
- Queue: `tasks/README.md`

## Current evidence

- Task 005 is accepted at `6746c1b2c` (stage-0 prerequisites `67a3e5803`,
  `37822d657`, `f9ed33dd9`, `aca8d35b3`, `91c062dd6`, `e63f27176`, and `ff2cf1138`). N# now owns
  construction planning end-to-end for the admitted family: ordinary source/runtime constructor
  calls with exact selection, defaults (including enum and dotted/aliased enum defaults), sized and
  inferred array literals with exact store opcodes, source class/struct/record and union-case object
  initializers (including nested values, generic-base member rebinding, and target-typed integers),
  closed source/runtime generic construction, and the approved runtime constructor catalog, all
  through schema-v3 plan rows executed and stack-validated by `ColumnarCodePlanExecutor`.
- The Analyzer's string-matched member/export/declaration resolution was deleted and replaced by
  the N#-owned `AnalyzerDeclarationContext`/`ColumnarSemanticTypeRegistry` exact-scope facts:
  `Analyzer.cs` fell from 23,471 to 23,068 lines. `ColumnarSynthesizedGenericScopeTests.cs` was
  deleted in favor of the native `generic-scope-invalid` project. Aggregate C# across the slice is
  net negative (−157 lines).
- The C# emitter retains exactly one fenced legacy surface for constructions: the whole-subtree
  residual (kinds 15/58/36 plus four helpers), reachable only when the N# planner declines without
  claiming (a value outside the plannable surface, e.g. interpolated holes or sibling-function call
  arguments). This mirrors the accepted task-004 fenced-call architecture; `ColumnarIlEmitter.cs`
  is 21,586 lines (epoch ceiling 21,723). The residual shrinks as later owners land (interpolation,
  sibling calls: task 015).
- Evidence: 3,182/3,182 units in the fresh gate (task 009's issue-tracker failure is FIXED by this
  slice); 553/553 BootstrapServices contracts; native product contracts all green: 14/14
  direct-calls, 18/18 ownership-audit, 7/7 construction-arrays (new), 3/3 generic-scope-invalid
  (new), 1/1 erased-enum-identity (new). Previously red vs HEAD and now green: `examples/16-task-cli`
  (union-case construction with interpolated argument), `examples/12-multi-file-projects/WeatherDemo`
  (record object initializer with call/index values), AutoDiscovery, issue-tracker backend check,
  and systems proof 36 (`new Dictionary<int,int>(capacity: 128)` named argument).
- The fresh non-VS-Code product gate has exactly four remaining failure groups, all verified
  byte-identical at HEAD `ff2cf1138` and assigned to later queue owners: Web API template build
  (009), Iterators single-file example (013), AsyncStreams single-file example (014), and the IL
  verification findings `RecordStructs.dll` CallVirtOnValueType/StackUnexpected (011) and
  `RecordsAndInterfaces.dll` InitOnly on `<InitializeFields>$` (012). Down from ten groups at the
  task-004 acceptance.
- The ownership growth ratchet is repinned to observed state (audit 18/18); the emitter entry rises
  only within its immutable epoch ceiling and records the restored fenced residual.
- Post-acceptance follow-ups `195028aa9` and `7f4e727d6`: columnar emission now runs on a dedicated
  wide-stack thread (MSBuild task threads run ~256 KB stacks and the emitter's per-node frames are
  large; the July-12 sources overflowed every fresh SDK-path emit), and the NL103 decline diagnostic
  is built inside that same thread (the decline trace is thread-local). The stale mid-slice SDK pack
  in `~/.nuget/local-feed` (the feed actually consulted; `~/.nsharp/packages` is not) was replaced,
  and the self-host loop is regenerative again: BootstrapServices Release re-emits cleanly through
  the packaged SDK, 553/553 contracts pass against the fresh kernel, and the clean repin is
  `nlc 0.1.0+7f4e727d615d2c38b5b71e6ac69690e5aa2275ff` with doctor status all-green.

## 015 completion roadmap

Exhaustive three-way classification of the REMAINING `ColumnarIlEmitter.cs` policy surface (this
replaces the former ad-hoc residual lists). Method: swept the full decision surface (516 members; the
`EmitExpressionCore` per-node-kind switch at ~10231, the `EmitStatement` switch at 6711, the preflight
typing engine `TryGetPreflight*`/`TryPreflight*` at 16718-17588, the interpolation core at 20340-21200,
the lambda family, and the declaration/reflection-emit hosting). N# planners run at the FRONT DOOR of
every dispatch (26 distinct `Columnar*Planner/Resolver/Facts` owners consulted before any C# residual
arm); the residual switch arms are whole-subtree-exit servers for non-plannable OPERAND bands.

### MOVABLE (an existing N# owner absorbs it with a named C# deletion) — EXHAUSTED
The interpolation string-classification splits were the only clean movable-decision family, and
`TrySplitBaseCall` (this slice) was the last of them (cast/equality/coalesce/integer-additive landed at
9a3c20950/aff33f1db/d37d3d732). The ~40-arm prior inventory (notes_015_pivot.md) plus this sweep find no
further decision an existing N# owner can absorb with a net-negative C# deletion. The two marginal
remainders are NOT clean decision deletions and are declined: decimal-literal VALUE parse (case 0/1 →
`TryEmitDecimalLiteral`, fused with the reflection-backed `decimal(...)` ctor emission → net N#+plumbing
positive, no decision deleted) and the entry-point return-shape rule (already N#-owned for async via
ColumnarIteratorPlanner facts; residual is reflection-typed return wrapping).

### BLOCKED-WITH-RECORD (proven/provable; retires via a named OTHER task)
1. LAMBDA-TAKING FAMILY — the dominant remaining policy block. `case 9` residual calls →
   `TryEmitEnumerableExtensionCall` (~17792: Where/Select/ToArray/ToList/Contains/Min/Max),
   `TryEmitExplicitEnumerableExtensionGenericCall` (~13943: Cast/OfType), `TryEmitLambdaLiteral` (~1491)
   + `EmitLambdaBody` recursive C# sub-emitter (~1702), `BodyReferencesEnclosingChain` (~1724), the
   `<>c__DisplayClass` capturing residual, and the preflight `TryPreflightContextualLambdaReturnType`
   (~17588) / `TryGetPreflightEnumerableExtensionCallType` (~17215). A lambda body is emitted by a
   recursive C# sub-emitter + typed by the C# preflight engine, not by plan rows. Stages 1–3a landed
   (signature/capture-set/return-type SELECTION → N#); Stage 3b/4/5/6 GATED on the FUTURE TASK "plan-row
   lambda-body emitter". Cited: lambda-arc Stages 3b–6, refutation d2257f33c, arms-off byte-exact proof.
2. C# PREFLIGHT TYPING ENGINE. `TryGetPreflightExpressionType` (~16718) + family
   (Binary/InstanceCall/MemberAccess/ExtensionSibling/ExtensionStatic). Reflection-bound expression-TYPING
   authority serving interpolation parsed holes + lambda return inference. Candidate (a) proven
   load-bearing (types the user's own enclosing-type statics, not catalog facts); its reroute is the
   forbidden add-a-planner-for-a-relocation anti-pattern. Retires via a FUTURE N# typing-owner port
   (adjacent to 017 analyzer semantic ownership).
3. LIVE case-12/13 RESIDUAL FAMILIES. `case 12` (short-circuit `&&`/`||`, null-comparison nullable+ref,
   `??` coalesce nullable+ref, signed arith `+`/`-`/`*`/`/`, ordering `<`/`<=`/`>`/`>=`, ref-identity
   equality on user reference types, string+char concat, String.Concat pair) and `case 13` ternary — all
   self-emit-load-bearing (four-surface probe). Retire ONLY as their non-plannable OPERAND forms become
   N#-plannable (member-chains-on-call-results, dictionary indexers, enum string constants) via the
   planners — an incremental four-surface-gated cut, not a movable relocation. Cited: 6e94ca88c prune.
4. BLOCKING-AWAIT MODEL. `case 53` await (`TryEmitBlockingAwait` ~6643) + `case 73` await-foreach
   consumer. The accepted synchronous GetAwaiter().GetResult() model retires when REAL async-func lowering
   lands (a FUTURE async-func task). Cited: 014 residuals.
5. INTERPOLATION CHAIN/PARSED-HOLE RESOLUTION. `TryResolveInterpolationChainPlan`/`TryResolveInterpolationHole`
   (~20885) + `TryResolveInterpolationMemberPlan` (~21041) + `TryParseInterpolationExpressionHole`/
   `TryGetParsedInterpolationExpressionType`. Chain tokenization is intertwined WITH reflection member/
   local/getter resolution (hop boundaries drive reflection) and parsed holes route through the preflight
   engine (#2). No clean string-classification split remains to peel off; retires with the preflight port.

### MECHANICAL (reflection-emit hosting, zero policy — the target end-state, already non-growing)
- Control flow + structural statement arms: block/if/while/for/return/break/continue, try/catch region ops
  (schema-4), lock lowering, throw, print, var/typed-local/tuple-deconstruction lowering, assert/
  assert-throws, expression-statement assignment, the StatementExits analysis mirror.
- Expression mechanical arms: parenthesized (7), checked-context (57), spread (64), unary (11, via
  ColumnarSourceOperatorResolver), is/as isinst (46/47), must (45), postfix ++/-- (44), match/pattern-test
  emit (18/34/33/35/32/8-pattern via ColumnarPatternFacts), index reads (10), anonymous-object synthesis (59).
- Construction/with/record/field-init: kinds 15/58/36/42 (ColumnarConstructionPlanner), 52
  (ColumnarRecordWithPlanner), record member synthesis, ColumnarFieldInitPlanner.
- Iterator/async hosting: yield (72), foreach (29), MoveNext/state-machine emission
  (ColumnarIteratorPlanner/ColumnarIteratorBodyPlanner), async fault guards.
- Type/member definition: DefineType/DefineMethod/DefineGenericParameters, union/generic declaration +
  constraints, delegate mapping (IsSupportedDelegateType/CreateDelegateType), bare-static + ref/out-deref
  reads (case 6), typeof, interpolation cast/equality/call-argument emit, and the base-call reflection
  RESOLUTION (this slice's mechanical host over TrySplitBaseCall's extracted name).

### VERDICT
015 does NOT complete this turn; its box stays UNCHECKED. After this slice the directly-MOVABLE decision
surface for 015-proper is EXHAUSTED. What concretely remains before the "reviewed, non-growing, zero-policy
mechanical host" criterion is met is ALL BLOCKED-WITH-RECORD policy that retires only via OTHER queue tasks:
- the FUTURE "plan-row lambda-body emitter" task (retires blocker #1: lambda family Stages 4/5/6 + the
  enumerable/Cast-OfType arms + display-class);
- a FUTURE N# preflight/typing-owner port (retires blockers #2 + #5: the C# typing engine and interpolation
  parsed-hole resolution) — adjacent to 017 analyzer;
- a FUTURE async-func-lowering task (retires blocker #4: blocking await);
- incremental planner-driven OPERAND unlocks that let the live case-12/13 residual families (#3) retire
  under the four-surface gate.
016 (parser) and 017 (analyzer) own the LSP-fallback parser/analyzer, NOT the emitter. 015's cursor is
therefore: no movable decision remains in the emitter; 015 is gated on the four future tasks above.

## 016 parser/diagnostic ownership finding

Verdict (this turn, PROVEN-BLOCKED-WITH-RECORD; no production edit, no commit): no bounded syntax
behavior can be moved from `src/NSharpLang.Compiler/Parser.cs` (7,117 lines; ratchet row
`compiler-core`, ceiling 7,117, fingerprint `text-v1:895641da1f9de8a6`) to N# as the "sole production
parser + ordered diagnostic authority" this turn while keeping every compiler AND Language Server
consumer byte-exact. The AST-shape half and the syntax-diagnostic half are gated on the SAME missing
prerequisite. Evidence below is code + committed-test grounded (the C# model is verified-green by the
full VS Code-enabled gate at HEAD `2859f8329`); no fresh live run was required.

### Inventory — who consumes `Parser.cs` output (exactly)
`Parser.ParseCompilationUnit()` returns `ParseResult { CompilationUnit, Errors }` — the C#
`CompilationUnit` AST + the syntax diagnostics. Every non-emit front-end consumes it MONOLITHICALLY:
- `MultiFileCompiler.ParseAllFiles` (192-198): `_allErrors.AddRange(parseResult.Errors)` — the
  production `nlc build`/check syntax-diagnostic source; Analyzer/Systems/Linter then run on the C# AST.
- `LanguageServer/Services/DocumentManager` (250-296): builds `state.CompilationUnit` ONCE, then the
  Analyzer, Linter, symbol/hover/completion extraction, and all 25+ LSP handlers read that one AST.
- `Analyzer.cs` (5 parse sites: cross-file/project/import), `Formatter.cs`, CLI `Program.FormatSource`
  (688) + `LintCommand` (90), `CodeIntelligence/{FixApplicator,CodeIntelligenceService}` (fix/query),
  `Playground`.
The N# columnar parser kernels (`CompilerServices/ColumnarParserKernels.nl`, 13,773 lines) produce
columnar node TABLES consumed ONLY by the emit pipeline (`ColumnarProgramInputBuilder` →
`ColumnarIlEmitter`), and only AFTER the C# path is error-free (`MultiFileCompiler` gates emit on zero
errors). They build no `CompilationUnit` and feed no tooling/LSP consumer. NO node-table→C#-AST bridge
exists; materialization-to-AST was explicitly rejected (memory
`project_parser_routing_materialization_deadend`: "port downstream to consume columnar tables directly").

### Why the AST-shape families are blocked (imports/namespaces, type/member decls, functions/generics, statements, expressions, patterns)
Moving any AST-shape behavior to N# requires the tooling/LSP front-end to consume N#-produced facts for
that behavior. The front-end reads the whole C# `CompilationUnit` as one recursive tree; a single node
family cannot be excised from that tree without breaking the tree the Analyzer/LSP read, and there is no
bridge to splice N# facts in per-family. Blocked on the bridge.

### Why the syntax-diagnostic families are blocked (the unwired `ColumnarSyntaxDiagnostics` arc)
A prior 9-commit arc (`760cf0203`..`771f741b7`, Jul 8, ALL ancestors of HEAD, ALL PURE ADDITIONS — zero
`Parser.cs` deletion, zero consumer wiring) built an UNWIRED N# owner: `ColumnarSyntaxDiagnostics.ParseFile`
+ `ParserDiagnosticMessages.Materialize` + `ParserDiagnosticsTable`. It has ZERO external references (C#
or N#), is in no `.tests.nl`, and `Parser.cs` still owns every production syntax diagnostic. It CANNOT be
wired byte-exact, for three independent reasons:
1. COVERAGE. It mirrors ~20 of `Parser.cs`'s ~256 distinct syntax diagnostics (100 emit sites) — 10
   "expected-token/malformed" families only (`ParserDiagnosticMessageKind` 1-20). Wiring `ParseFile` as
   the sole authority would LOSE ~236 diagnostics (missing `)`/`]`/`}`/`:`/`;`/`=>`, unexpected tokens,
   dangling operators, constraint conflicts, pattern/match/test-DSL errors, …) — a catastrophic regression.
2. DIVERGENT SUPPRESSION MODEL. `Parser.cs` emits inline during ONE recursive-descent pass gated by one
   shared `_panicMode` flag (`ReportError` at 6856 returns early if panic; sets panic after each error;
   resets only at true parse-structure sync points — declaration/statement/member/case boundaries).
   Committed tests PIN this: `Parser_CascadingErrorsSuppressed` (`Errors.Count <= 5`),
   `Parser_DanglingBinaryOperator_DoesNotSwallowFollowingStatements` (exactly one error, exact column 14
   / length 3, parse-context message "Expected expression after '+'"). The N# owner runs 10 INDEPENDENT
   whole-token-scan collectors, each with a per-token-boundary panic heuristic (`ParserDiagnosticTable.
   PanicMode`, reset at Newline/Semicolon/Comma/Brace) threaded across sequential passes. The models
   diverge exactly in the cascading-error cases the tests pin, and the collectors fire on scan-reached
   tokens vs the parser's parse-reached tokens.
3. SHARED-PANIC COUPLING ⇒ NO BOUNDED SINGLE-FAMILY EXTRACTION. Deleting any one family's inline
   `Parser.cs` report also deletes its `_panicMode = true` side-effect, changing the suppression seen by
   every subsequent diagnostic of EVERY OTHER family. So even a single-family diagnostic move is not
   side-effect-free and cannot be verified byte-exact against the 520-assertion
   `LanguageServerDiagnosticsTests` + `ParserErrorTests`/`ErrorHandlingTests`.
Note: the C# report site already delegates `CompilerError` CONSTRUCTION to the shared N#
`ParserErrorDiagnostics.Create`, so only the DECISION (whether/where to report, under the shared panic
model) + the message/hint/suggestion literals are C#-owned. Moving just the literals is NOT a
decision-ownership move and is declined.

### Prerequisite that unblocks 016 (sized honestly)
One N# parse front-end whose output the C# tooling/IDE consumers can consume in place of `Parser.cs`. Either:
(a) Extend the N# columnar parser kernels to (i) emit the FULL syntax-diagnostic surface WITH the parser's
    shared-panic recovery model (NOT the `ColumnarSyntaxDiagnostics` token-scan mirror) and (ii) expose a
    `CompilationUnit`-equivalent / node-table facts the Analyzer/Linter/Formatter/LSP handlers consume;
    validated byte-exact against the diagnostic + parser-error suites. This is a PARSER-KERNEL change → it
    TRIPS THE TWO-STAGE BOOTSTRAP WALL (coordinator toolset repin required before dependent code compiles)
    and is a multi-slice effort, not one bounded deletion. OR
(b) Port the tooling front-end (Analyzer/Linter/Formatter/LSP handlers) to consume the columnar node tables
    directly (the memory-endorsed direction) — task 017+ (analyzer ownership) scope, far beyond one bounded
    parser slice.
The `ColumnarSyntaxDiagnostics` arc is scaffolding for path (a)'s diagnostic half but is incomplete (~8%
coverage) and model-divergent; it must NOT be wired as-is. `Parser.cs` stays the sole production syntax
parser/diagnostic authority until the prerequisite lands; 016 stays UNCHECKED.

### Staged parser-front-end ARC PLAN (chosen: path (a), the recovery-aware N# front-end)
The finding above is STAGE 0 (the prerequisite record). The arc builds path (a)'s kernel-side capability to
FULL parity FIRST (family by family, each stage's diagnostics proven byte-exact against Parser.cs on a
native parity corpus), then production-wires the consumers LAST at parity, then deletes Parser.cs. This is
the 013/014/lambda-arc precedent: a proven-record capability arc, not a single byte-exact deletion. No
production shadow/comparison route ever runs — parity proofs live only in `.tests.nl`.

- STAGE 1 (LANDED this turn) — the SHARED-PANIC RECOVERY MODEL + first diagnostic family. New owner
  `src/NSharpLang.Compiler.BootstrapServices/ColumnarParserRecovery.nl` faithfully reproduces Parser.cs's
  recovery discipline (one shared `PanicMode`; `Report` suppresses-while-set / records-in-source-order /
  sets-panic; reset ONLY at the declaration-boundary sync point; the `ConsumeIdentifier` reserved-keyword /
  end-of-file / found-other variants; `LastVisibleTokenSpan` EOF anchoring) and carries the
  IMPORT / NAMESPACE / PACKAGE family end-to-end (qualified-name identifier errors, dot-access member
  errors, missing import alias, duplicate-package). Diagnostic CONSTRUCTION delegates to the already-live
  shared owner `ParserErrorDiagnostics.Create` (the same call Parser.cs uses), so codes/snippets/docs URLs
  match automatically. Proven by 11 native contracts in `ColumnarParserRecovery.tests.nl` against golden
  Parser.cs output captured from the fresh CLI — INCLUDING the two committed-test model shapes: cascading
  suppression (triple-package → 1 diagnostic; the third suppressed with no intervening reset, mirroring
  `Parser_CascadingErrorsSuppressed`) and does-not-swallow-following (package/package/stray-token → 2
  diagnostics; the declaration-boundary reset lets the stray token report, mirroring
  `Parser_DanglingBinaryOperator_...`). NO production wiring; NO wall tripped (self-contained new files, the
  packaged SDK emits them — no repin). Evidence: BootstrapServices contracts 773/773 (762 baseline + 11);
  ownership audit 18/18; dev.sh Parser 381/381.
- STAGE 2 (LANDED this turn) — the DECLARATION-NAME family. Extended `ColumnarParserRecovery.nl` with
  `ConsumeDeclarationName` (Parser.cs ConsumeIdentifier with a non-null diagnosticSpan, :6720) carrying the
  "Expected <kind> name" diagnostics for func / class / struct / record / soa record / interface / union /
  enum / type-alias, with the `DiagnosticSpanFromToken` KEYWORD-ANCHORING discipline (missing/invalid name
  underlines the declaration keyword in all three variants) and the reserved-keyword-as-name variant; plus
  the `ParseTopLevelDeclaration` dispatch (ParseModifiers + the exact Parser.cs keyword order incl.
  `ref struct` / `soa record` / `duck interface` / `record struct` + LookAhead), the per-kind name parsers,
  and the boundary/force-advance loop (Parser.cs ParseCompilationUnit :83/:99-108). Bodies are NOT parsed;
  the corpus keeps to shapes where a name-only parser is byte-exact with the full Parser.cs body parse
  (absent-at-EOF, reserved-keyword-then-EOF for every kind; found-other only for func/enum/type, whose
  failing body consumes no trailing token so the stray token fires at the next boundary — the panic-reset
  demonstration). +24 native contracts; BootstrapServices 797/797 (773+24); ownership audit 18/18; git
  status shows only the two `.nl` files (no non-N# move). NO production wiring; NO wall (self-contained).
- STAGE 3 (LANDED this turn) — the MALFORMED-LITERAL family (NL105 `InvalidLiteral`). Extended
  `ColumnarParserRecovery.nl` with `ReportMalformedLiteralIfNeeded` → the three Parser.cs reporters
  (`ReportMalformedCharLiteralIfNeeded` :4905 / `ReportMalformedStringLiteralIfNeeded` :4830 /
  `ReportMalformedRawStringLiteralIfNeeded` :4876), carried through the shared-panic `Report`. ORIGIN: every
  malformed-literal diagnostic is Parser.cs-REPORTED inside `ParsePrimaryExpression` (:4646/:4653); the
  already-N# `Lexer.nl` only CLASSIFIES (`Token.IsTerminated` + the token value), emitting NO diagnostic, and
  the malformed DECISION delegates to the live shared `ParserLiteralFacts` (Parser.cs delegates identically).
  So the family belongs to the parser model, NOT a lexer lane. Reached via the shallowest byte-exact literal
  context — the expression-bodied `func f() => <literal>` — through a MINIMAL literal-reaching expression path
  (paren + literal primary + minimal binary-operator continuation); the expression/statement ERROR families
  (unexpected-token-in-expression, dangling operator, missing `)`) are DEFERRED to their own stages and never
  fire here (suppressed under the same shared panic, so output stays byte-exact). +14 native contracts:
  per-shape single-malformed, across-boundary (next fires), in-region suppression (`'a + 'b` → 1), and
  negatives. BootstrapServices 797→811; dev.sh Parser 381/381; ownership audit 18/18; NO production wiring;
  NO wall (self-contained). NOTE for later: `import`-path strings and test-description strings do NOT run the
  malformed check (verified: `import "abc` → NL701, not NL105), so they are correctly out of this family.
- STAGE 4 (LANDED this turn) — the MEMBER / PARAMETER / FIELD declaration family (NL102 `ExpectedToken` /
  NL109 `ReservedKeywordAsName`). Extended `ColumnarParserRecovery.nl` with a real `ParseParameterListRecovery`
  (from the function head) carrying the parameter name (`ConsumeIdentifier`(message, span?) :6720 +
  `GetMissingParameterNameDiagnosticSpan` :6476), colon (`ConsumeParameterColon` :6625, name-anchored), and
  type (`ParseParameterTypeReference` :6504) errors; and a braced-body path (`ParseClassName` / `ParseStructName`
  → `ParseTypeBodyIfPresent` → `ParseMemberList` → `ParseFieldMember`) carrying the field name
  (`ConsumeIdentifier` "Expected field name" :1666), colon (`ConsumeFieldColon` :6651, name-anchored), and type
  (`ParseFieldTypeReference` :6536 with `LooksLikeNextFieldAfterMissingType` :6572) errors, plus the
  `ParseMemberList` per-member panic-reset sync point (:1365). RETIRED the Stage-2-deferred braced-kind
  found-other NAME for the `{`-offender variant (`class {` / `struct {`) — now reachable because the offending
  `{` is consumed as the empty body brace; `ParseTypeBodyIfPresent` enters the body for a valid name (→ fields)
  or an `<error>` name ONLY when the offender is `{`, so no Stage-2 multi-declaration case regresses (proven by
  the unchanged Stage-1/2/3 contracts). Bodies parse FIELD members only; type-params/primary-ctor/base-lists,
  the missing-`{`/`}` (NL106) reports, and the method/nested/constructor/record-positional/union-case member
  grammars are later stages (corpus avoids them). +17 native contracts (7 parameter, 8 field incl. the
  member-boundary-reset two-field and two-class shapes, 2 braced found-other). DEFERRED with reasons: the
  non-`{` braced found-other (`class 5`) and non-identifier parameter name (`func f(5)`) both emit garbage-type
  cascades whose report order diverges from the oracle's position-sorted output (need `ParseTypeReference`-
  on-garbage + `SynchronizeToNextStatement` + sorted emit); trailing-comma
  (`ReportMissingParameterAfterTrailingComma`) and the closing-delimiter recovery are their own stages.
  BootstrapServices 811→828; dev.sh Parser 381/381; ownership audit 18/18; NO production wiring; NO wall
  (self-contained; packaged SDK self-emitted the edited owner + all 828 contracts — no repin).
- STAGE 5..N (per-family capability, each proven byte-exact on the parity corpus, NO production wiring):
  extend `ColumnarParserRecovery` family by family until it matches Parser.cs's full ~256-diagnostic
  surface under the shared-panic model. Suggested order (smallest-coherent first, member/parameter/field +
  generics/constraints DONE above): [STAGE 5 DONE — generics/constraints: `ConsumeGreater`, split `>>`,
  type-param / type-argument errors, `where`-clause constraints] → [STAGE 6 DONE — statements: the block-body
  grammar + `SynchronizeToNextStatement` sync point + per-statement panic reset + `_currentRecoveryBoundaryColumn`,
  the dangling-operator through-token span, missing-initializer `:=`/`=`, missing if/while condition, missing
  for/foreach `in`, missing-statement-body] → [STAGE 7 DONE — expressions (recut A): the fuller precedence ladder +
  the expression ERROR families unexpected-token-in-expression / prefix `+` / leading `.` / ternary errors /
  dangling-operator-per-tier / await-must-throw missing-operand / member-name-after-dot] → [STAGE 8 DONE — the
  MATCH / PATTERN family (`ParseMatchExpression` + `ParsePattern`/`ParsePrimaryPattern`/`ParsePropertyPatterns`; the
  "match/patterns second" recut half)] → [STAGE 9 DONE — closing-delimiter recovery (`TryReportMissingClosingDelimiter`,
  missing `)` NL107 / `]` NL108 + the block/type-body missing-`}` NL106 + the parameter trailing-comma; retired
  STAGE 5's deferred `new(` missing-`)`, STAGE 6's block missing-`}` [EOF + found-declaration], STAGE 8's pattern-list
  `]` / positional `)` closes, and STAGE 4's parameter trailing-comma)] → [STAGE 10 DONE — the POSTFIX CALL / INDEX /
  generic-call / `with {…}` + call-argument family (`ParseArgumentList`: inline-out NL103 + spread / named / bare-alloc
  recognition, closes via the Stage-9 recovery) and the first keyword-led-primary tranche (new incl. the object-init
  panic-reset-on-progress + `ParseNewTypeReference`; cast via the ported `IsCastExpression` scanner; the full tuple /
  parenthesized grammar; typeof / nameof / sizeof / checked / unchecked; array literal); +40 contracts]. STAGE 2's
  non-`{` declaration-body found-other and the remaining keyword-led primaries (alloc / stackalloc / interpolation /
  lambda) + `is`/`as` remain — STAGE 11+.
  Each stage adds the family's `ConsumeX`/`ReportError` sites + its sync-point discipline, and grows the
  parity corpus; each stays self-contained (new/edited `.nl` in BootstrapServices + `.tests.nl`) UNLESS a
  stage needs a kernel entry point dependents compile against — that stage TRIPS the two-stage bootstrap
  wall and needs a coordinator repin (call it out at stage start).
- STAGE N+1 (AST/node-table facts): expose a `CompilationUnit`-equivalent / node-table surface the
  Analyzer/Linter/Formatter/LSP consume in place of Parser.cs's C# `CompilationUnit`, proven fact-equivalent.
- STAGE N+2 (CUTOVER, IDE-AFFECTING): at full diagnostic + AST parity, route every consumer
  (`MultiFileCompiler.ParseAllFiles`, `DocumentManager`, `Analyzer`, `Formatter`, CLI format/lint,
  `CodeIntelligence`, Playground) directly to the N# front-end. VS Code-enabled gate + extension reinstall +
  computer-use visual check. No shadow route.
- STAGE N+3 (DELETION ARC): delete Parser.cs's per-family parsing/recovery/reporting decisions as each
  consumer is cut over, ending when Parser.cs is deleted or is a reviewed zero-policy mechanical host
  (`compiler-core` ratchet row retires). The C# `ParserErrorTests`/`ErrorHandlingTests`/
  `LanguageServerDiagnosticsTests` assertions migrate to native `.tests.nl` as their families cut over.

### Scaffolding fate decision (recorded): DELETE the divergent `ColumnarSyntaxDiagnostics` closure
The inert prior-arc scaffolding is SUPERSEDED by `ColumnarParserRecovery` (which uses the correct shared
ordered-panic model, not the divergent 10-pass per-token-scan model that must never be wired). The closure
`{ColumnarSyntaxDiagnostics.nl, ParserDiagnosticMessages.nl, ParserDiagnosticsTable.nl}` was fully
self-contained (zero external references — verified across all of src+tests; the four support types
`ParserDiagnosticTable`/`ParserDiagnosticTableOps`/`ParserDiagnosticMessageKind`/`ParserDiagnosticContextKind`
were reachable only through that closure) and has been DELETED this turn to honor the no-dead-code rule.
`ParserErrorDiagnostics.nl` is KEPT — it is LIVE (Parser.cs and now `ColumnarParserRecovery` both call
`ParserErrorDiagnostics.Create`). Its message templates are not lost: the message ORACLE is Parser.cs
itself, and git history preserves the scaffolding. Not ratchet-tracked (all `.nl`); the deletion left the
BootstrapServices contract count unchanged at 773 (the deleted files carried no `.tests.nl`).

## 016 AST/facts bridge (N+1) design record

The diagnostic-capability arc (Stages 0-17) is complete: `ColumnarParserRecovery.nl` reproduces every Parser.cs
syntax diagnostic byte-exact (432 native contracts). N+1 turns that recovery-only owner into one that ALSO produces
the AST the non-emit consumers read, so that at N+2 (cutover) every consumer can be routed to the N# owner and at N+3
Parser.cs can be deleted. This section is the definitive N+1 design.

### Consumer-needs inventory (what each consumer reads from ParseResult / CompilationUnit)
`Parser.ParseCompilationUnit()` returns `ParseResult { CompilationUnit?, Errors, Success }`. Verified consumer-by-
consumer (13 production parse sites; grep of `ParseCompilationUnit` / `new Parser(` / `.CompilationUnit`):
- `.Success` is NEVER read by any consumer — the bridge need not reproduce it (it is a convenience predicate).
- `.Errors` (`List<CompilerError>`) is read by MultiFileCompiler.ParseAllFiles (:198), DocumentManager (:255/:301),
  Analyzer's import site (:21708), Formatter's re-parse gate (:39), CLI FormatSource (:691) + LintCommand (:92/:113).
  The owner ALREADY produces this list identically (the whole 432-contract arc) — the `Errors` half is DONE.
- `.CompilationUnit` (`Ast.CompilationUnit`) is read by all 13 sites. What they read off it:
  * `Namespace` / `Package` — Analyzer.GetUnitNamespace = `Package?.Name ?? Namespace?.Name` (:22066), used by
    project-namespace resolution (Analyzer :19122/:22012/:22038) and Formatter (:67/:117).
  * `Imports` (`List<ImportDirective>`, `.Namespace`) — Formatter (:79/:111), CodeIntelligenceService.GetOutline (:126).
  * `FileImports` (`List<Statement>` of FileImport/NamespaceImport; `.Path`/`.Line`/`.DiagnosticColumn`/
    `.DiagnosticLength`) — MultiFileCompiler (:248), Analyzer import site (:21736/:21740), Formatter (:96/:111).
  * `Declarations` (`List<Declaration>`) — recursed by Analyzer.Analyze, Linter.Lint, SystemsAnalyzer.Analyze,
    Formatter.Format, and 12+ LSP handlers (DocumentSymbol/CallHierarchy/TypeHierarchy/SemanticTokens/Completion/…).
  * `Line` / `Column` — the AstNode base coordinates.
  * FixApplicator (:29) positionally CONSTRUCTS a fallback `CompilationUnit(null, [], [], null, [], 1, 1)` — so a
    consumer already depends on the C# CompilationUnit constructor shape.
- RECORD-FEATURE AUDIT (does any consumer rely on AST nodes being C# `record`s?): NO `with`-expressions and NO
  positional deconstruction on any parser AST node anywhere in src. AST-node-keyed collections all use
  `ReferenceEqualityComparer` (Linter/Analyzer/SystemsAnalyzer). The ONLY value-equality dependency on a parser record
  is `Analyzer.cs:18169` — `pattern.Properties.Except(constrainedProperties)` over `List<PropertyPattern>` (a record),
  where `constrainedProperties` is a `.Where`-filtered subset so it works by identity coincidence today. CONCLUSION:
  migrating the AST hierarchy from C# `record`s to N# CLASSES (reference equality) is safe for every consumer EXCEPT
  that one `Except`, which must be reproduced with `ReferenceEqualityComparer` or rewritten to a reference-based diff
  at cutover. This removes the only real risk from the "AST-as-N#-classes" migration.

### Bridge-shape decision (chosen: option (a) — the owner constructs the production Ast types directly)
Two shapes were weighed under the hard constraint NO new production C#:
- (a) The N# owner CONSTRUCTS the existing production `NSharpLang.Compiler.Ast` node instances directly. The consumers
  are statically typed against `Ast.CompilationUnit` and its field types, so the bridge MUST output exactly those
  types; producing them directly means N+2 cutover changes zero consumer field-reads. PROBED viable: the three preamble
  leaf types are already N# classes in this assembly and the owner constructs them field-exact THIS turn; N# supports
  the class-inheritance hierarchies the AstNode tree needs (TypeInfoModels.nl: `class ClassTypeInfo: TypeInfo` + 12
  siblings); and the record-feature audit shows classes suffice. The 2026-06 decision that rejected node-table→C#-AST
  materialization was an EMIT-path perf decision; the TOOLING path already pays AST materialization today (Parser.cs
  builds the full tree for every consumer), so (a) carries no new perf cost there.
- (b) An N#-native fact surface the owner exposes, with consumers rewritten to read it. REJECTED: it pushes an enormous
  consumer rewrite (Analyzer/Linter/Formatter/every LSP handler recurse the typed `Declarations` tree) into N+2 and
  still must reach full AST fidelity. (a) confines the work to the parser side and keeps consumers byte-stable.

Rationale recorded: (a) is correct, and its enabler is moving the AST TYPE DEFINITIONS upstream to N# so the owner can
NAME/construct them — the precedent is already set (ImportDirective/PackageDeclaration/NamespaceDeclaration moved to N#
classes in BootstrapServices and Parser.cs constructs them fine). This is the mandate's "shrink C# / move to N#"
pattern, not new C#.

### The CompilationUnit-container block (proven precisely) — and what unblocks it
The owner CAN construct today (all N# in this assembly): `NamespaceDeclaration`, `ImportDirective`, `PackageDeclaration`,
`CompilerError`. It CANNOT construct: `CompilationUnit`, `FileImport`, `NamespaceImport`, the `AstNode`/`Statement`/
`Declaration` bases, and every concrete Declaration/Statement/Expression subtype — because they are C# in the DOWNSTREAM
`NSharpLang.Compiler` assembly and `BootstrapServices` cannot reference it (Compiler → BootstrapServices; the reverse is
a cycle). This is an ASSEMBLY-DEPENDENCY block, NOT an emitter gap: no `.nl` emitter operand family is missing — the
types are simply not nameable upstream (confirmed: BootstrapServices `.nl` code that must touch a `CompilationUnit`
takes it as `object` + reflection). Even an EMPTY-Declarations preamble `CompilationUnit` is blocked, because its
constructor signature NAMES `List<Statement>` and `List<Declaration>` (downstream bases). A thin C# assembler in the
Compiler assembly would be new production C# (forbidden); routing Parser.cs's preamble into the owner is the N+2
cutover (out of scope, and Parser.cs must stay authority this stage).

UNBLOCK (the bulk of N+1): move the AST type hierarchy upstream to N#. The hard sub-constraint is that C# `record`s
cannot derive from N# classes, so the AstNode → {Expression, Statement, Declaration} → concrete-subtype hierarchy must
move TOGETHER (all-or-nothing at the base). The record-feature audit shows N# CLASSES suffice (only the one
`PropertyPattern` `Except` needs care), so the migration is: port `AstNode` + all subtypes (Declarations.cs,
Statements.cs, Expressions.cs — ~3 files, deep but mechanical record→class ports) into N# in an assembly the owner
references (BootstrapServices, or a dedicated upstream `NSharpLang.Compiler.Ast` N# assembly both the owner and Compiler
reference). Parser.cs keeps constructing the SAME (now-N#) types, so it is untouched until cutover; the C# record
definitions are deleted as they move (shrink, not new). NO emitter-operand unlock is required (this does NOT feed the
015 planner-operand backlog) — it is a location/dependency migration, gated only on the record→class port + the single
`Except` fix.

### Refined N+1..N+3 staging
- N+1a (LANDED this turn): the owner constructs the preamble leaf subtree (Namespace/Imports/Package) + the Errors list,
  field-exact to Parser.cs, via `ParseFilePreambleAst`. Proves the direct-construction mechanism on the upstream types.
- N+1b: migrate the AST type hierarchy (AstNode + Statement/Declaration/Expression bases + all subtypes + CompilationUnit
  + FileImport/NamespaceImport) from C# records to N# classes in an upstream assembly the owner references; delete the C#
  record definitions as they move; reproduce the `PropertyPattern` value-equality site (Analyzer.cs:18169) with reference
  equality. This makes the CompilationUnit container constructable from the owner. Multi-slice, mechanical, no emitter
  unlock; may trip the two-stage bootstrap wall if a moved type becomes a kernel-compiled dependency surface — call it
  out at slice start.
- N+1c: extend the owner's recovery grammar (already at full diagnostic parity) to also MATERIALIZE the full node tree
  (declarations/statements/expressions) it currently parses for diagnostics only, returning a real `CompilationUnit`;
  prove node-by-node structural equality against Parser.cs on the parity corpus (comparison in `.tests.nl` only).
- N+2 (CUTOVER, IDE-AFFECTING): at full AST + diagnostic parity, route every consumer (MultiFileCompiler.ParseAllFiles,
  DocumentManager, Analyzer's 4 sites, Formatter, CLI format/lint, CodeIntelligence, Playground) to the N# owner. VS
  Code-enabled gate + extension reinstall + computer-use visual check. No shadow route.
- N+3 (DELETION): delete Parser.cs's per-family parse/recovery/report decisions as each consumer cuts over; end when
  Parser.cs is deleted or a reviewed zero-policy mechanical host (`compiler-core` ratchet row retires).

## Iterative-task targets

These are populated only when their task becomes current.

- Task 015 next emitter sub-slice: NONE — movable-decision surface exhausted (see the 015 completion
  roadmap above); gated on the plan-row lambda-body emitter, N# preflight/typing-owner port, async-func
  lowering, and incremental planner OPERAND unlocks.
- Task 016 next parser sub-slice: STAGE N+1b (the CompilationUnit-container unblock — migrate the AstNode/
  Statement/Declaration/Expression hierarchy + CompilationUnit + FileImport/NamespaceImport from C# records to N#
  classes upstream, per the "## 016 AST/facts bridge (N+1) design record"). The diagnostic-capability arc (Stages
  0-17) is COMPLETE and N+1a (the preamble-leaf construction increment) LANDED this turn. The historical STAGE-14
  pointer below is retained for reference only.
  (HISTORICAL) STAGE 14 of the parser-front-end arc (see the "Staged parser-front-end
  ARC PLAN" + the Stage-13 RESIDUAL-TO-PARITY MAP in the Active sub-slice above). STAGES 1-13 have LANDED
  (recovery model + import/namespace/package; declaration-NAME; malformed-literal; member/parameter/field;
  generics/constraints; statements; expressions; match/patterns; CLOSING-DELIMITER recovery; POSTFIX
  call/index/generic-call/`with` + call-argument family + the new / cast / tuple / typeof / nameof / sizeof /
  checked / unchecked / array primary tranche; is/as + alloc/stackalloc/lambda; the interpolated-string `$"…"`
  hole grammar; and the REMAINING STATEMENT kinds [yield/break/continue/throw/try-catch-finally/using/lock/switch/
  allow/alloc-block/unsafe/assert/preprocessor/local-function/await-foreach/off/on + C-style for + tuple
  deconstruction + typed declarations] — 316 native contracts). STAGE 14 = the MEMBER grammars (method /
  constructor / nested-type / record-positional / union-case / interface / property) + the record / interface /
  union / enum / soa type BODIES (residual map item [2]). Still kernel-capability-only (no production wiring, no
  IDE gate). Do NOT resurrect the deleted `ColumnarSyntaxDiagnostics` scanner.
  (HISTORICAL, for reference — the Stage 1-8 pointer this replaced): STAGE 1 (recovery model + import/namespace/package), STAGE 2 (declaration-NAME family),
  STAGE 3 (MALFORMED-LITERAL family), STAGE 4 (MEMBER / PARAMETER / FIELD declaration family), STAGE 5
  (GENERICS / CONSTRAINTS family), STAGE 6 (STATEMENT family — block-body grammar +
  `SynchronizeToNextStatement` sync point + per-statement panic reset + `_currentRecoveryBoundaryColumn`, the
  dangling-operator through-token span, missing-initializer `:=`/`=`, missing if/while condition, missing
  for/foreach `in`, missing-statement-body; proven byte-exact incl. `Parser_DanglingBinaryOperator_...`'s exact
  span/message and the statement-boundary reset + within-statement cascade shapes), and STAGE 7 (EXPRESSIONS,
  recut A — the fuller precedence ladder [ternary / coalescing / logical / bitwise / equality / relational /
  shift / range / unary / postfix-member] replacing Stage-6's shallow subset, carrying the expression ERROR
  families STAGE 3/6 kept panic-suppressed: unexpected-token-in-expression, prefix `+` [NL103 InvalidSyntax],
  leading `.`, ternary missing-then/`:`/else, dangling operators per-tier, await/must/throw missing-operand, and
  member-name-after-dot; proven byte-exact incl. the initializer-terminator-then-reset and prefix-plus-cascade
  panic shapes; +35 contracts) have LANDED. STAGE 8 = the DEFERRED MATCH / PATTERN family through the SAME
  shared-panic model: `ParseMatchExpression` (:5368, the `Consume(LeftBrace/Arrow/Comma/RightBrace)` + `ParsePattern`
  scaffolding) and the pattern parsers `ParsePattern`/`ParseOrPattern`/…/`ParsePrimaryPattern` (:3263-:3457, the
  terminal "Invalid pattern. Got 'X'" [NL103] + list `Consume(RightBracket)` / positional `Consume(RightParen)` /
  qualified-name `ConsumeIdentifier` sites) + `ParsePropertyPatterns` (:3459). NOTE: match/pattern shapes lean on
  closing-delimiter `Consume` sites (`{`/`}`/`)`/`]`), so STAGE 8 may fold in or immediately precede the
  closing-delimiter stage. Also DEFERRED from STAGE 7 (recorded): the `is`/`as` relational operators (type
  sub-grammar); postfix CALL `(…)` / INDEX `[…]` / generic-call / `with {…}` (the call-argument + closing-delimiter
  families); the keyword-led primaries (new / alloc / match / cast / tuple / typeof / array / interpolation / lambda /
  …); and the four INVALID-OPERATOR default arms (assignment/relational/multiplicative/unary) — UNREACHABLE dead
  defaults (exact-match-fact guards admit only tokens the switch handles), never fired, not corpus-modellable. Still
  kernel-capability-only (no production wiring, no IDE gate). Stays self-contained (BootstrapServices `.nl` +
  `.tests.nl`, no repin) unless the stage needs a kernel entry point dependents compile against — call out the
  two-stage bootstrap wall at stage start. Do NOT resurrect the deleted `ColumnarSyntaxDiagnostics` scanner
  (divergent per-token panic model). NOTES for later stages:
  (a2) STAGE 7's statement-expression path is now the fuller ladder; the Stage-3 `=>` expression-body and Stage-4
  field-`:=` init still use the minimal `ParseLiteralBearingExpression` vehicle (validated byte-exact for their
  corpora) — unifying them onto the full ladder is a later mechanical cleanup, not a diagnostic change.
  (a1) STAGE 6 carries the statement family via the block-body vehicle; DEFERRED (with reasons): the C-style
  `for init; cond; iter` loop, tuple deconstruction, typed `name: T = value` declarations, the remaining
  statement kinds (yield / break / continue / throw / try / using / lock / switch / allow / alloc / unsafe /
  assert / preprocessor / local-function / await-foreach / off — each adds its own ReportError sites under the
  same shared-panic model), the full expression ladder + expression ERROR families (STAGE 7), and the block's own
  missing-`}` (NL106) report + `IsBlockClosingDeclarationStart` break (reproduced-but-not-corpus-exercised;
  retire with the closing-delimiter stage). The STAGE-6 expression subset is assignment over additive/
  multiplicative over identifier/literal/bool/null/parenthesized primaries — a vehicle that reproduces only the
  dangling-operator through-token span byte-exact; the corpus keeps its statement expressions within that subset.
  (a0) STAGE 5 carries the generics/constraints family via the FUNCTION head + class type-params; DEFERRED
  (with reasons): the EOF-anchored `ConsumeGreater` (the check pipeline clamps JSON length 0→1; unmatchable at
  the CompilerError level), the `new(` missing-`)` (NL107 via `TryReportMissingClosingDelimiter` — the
  closing-delimiter stage), class/interface/union/record/soa/method type-params + soa's "not supported yet"
  special diagnostic, and class-body `where` (classes do NOT take `where` — `class C<T> where …` cascades).
  (a) STAGE 4 parses FIELD members only and retires the braced-kind found-other ONLY for the `{`-offender; the
  non-`{` found-other (`class 5`), non-identifier parameter name (`func f(5)`), trailing-comma, and the
  method/nested/constructor/record-positional/union-case member grammars remain deferred (garbage-type cascade
  + position-sorted emit order — need `ParseTypeReference`-on-garbage + `SynchronizeToNextStatement`), retiring
  with the expression/statement + closing-delimiter stages. (b) STAGE 3's MINIMAL literal-reaching
  expression path (paren + literal primary + flat binary-operator continuation) is a vehicle, NOT the full
  expression grammar — the expressions/patterns and closing-delimiter stages OWN the expression/statement
  ERROR families (unexpected-token-in-expression, dangling operator, missing `)`/`]`/`}`); STAGE 3/4 corpus
  shapes deliberately keep those would-be errors panic-suppressed so their output is byte-exact without them.
- Task 017 next semantic sub-slice: not selected
- Task 018 next systems-policy sub-slice: not selected
- Task 019 next tooling sub-slice: not selected
- Task 020 next native-runner sub-slice: not selected

## Completion ledger

Completed slices:

- Task 016 — EIGHTH slice (parser-front-end arc STAGE 7): the EXPRESSIONS diagnostic family (recut A — the
  fuller precedence ladder over Stage-6's shallow assignment/additive/multiplicative subset, carrying the
  expression ERROR families Stages 3/6 kept panic-suppressed: unexpected-token-in-expression [NL101], prefix `+`
  [NL103], leading `.` [NL102], the ternary missing-then / missing-`:` / missing-else sites, dangling binary
  operators across every ladder tier [NL102], await/must/throw missing-operand [NL102], and member-name-after-dot
  [NL102 + the reserved-keyword member NL109]), in N#, PROVEN byte-exact against the freshly built Release CLI
  oracle. NOT committed (mandate: do not commit); working tree carries the two edited N# files + STATUS. NO
  production wiring — Parser.cs remains the sole production syntax authority.
  - Site inventory (grep of ParseExpression + the ladder + ParsePrimaryExpression in Parser.cs): the LADDER
    `ParseAssignmentExpression` (:3690) → `ParseTernaryExpression` (:4009) → `ParseNullCoalescingExpression` (:4033)
    → `ParseLogicalOr/AndExpression` (:4047/:4061) → `ParseBitwiseOr/Xor/AndExpression` (:4075/:4089/:4103) →
    `ParseEqualityExpression` (:4117) → `ParseRelationalExpression` (:4132) → `ParseShiftExpression` (:4205) →
    `ParseAdditiveExpression` (:4220) → `ParseMultiplicativeExpression` (:4235) → `ParseRangeExpression` (:4280) →
    `ParseUnaryExpression` (:4316) → `ParsePostfixExpression` (:4405) → `ParsePrimaryExpression` (:4626); the
    unexpected-token terminal (:4813) + `ShouldSkipUnexpectedExpressionToken` (:6943); `ParseInvalidPrefixPlusExpression`
    (:3816); `ParseLeadingMemberAccessWithoutReceiver` (:6407); the ternary sites (:4016/:4021/:4022);
    `ParseBinaryRightOperandOrMissing`/`ParseRightOperandOrMissing` (:3778/:3750); `ParseUnaryOperandOrMissing` (:3789);
    `ReportMissingMemberNameAfterDot` (:6385) + the reserved-keyword member (:4433).
  - Deliverables: `ColumnarParserRecovery.nl` 2,334 → 2,822 lines (+488: the full ladder tiers +
    `BinaryRightOperandMissing`/`RightOperandMissingWithSpan` + `ParseUnary`/`ParsePostfix`/`ParseMemberAccess` +
    `ParseInvalidPrefixPlusExpression` + `ParseUnaryOperandOrMissing` + `ReportMissingMemberNameAfterDot` +
    `ParseLeadingMemberAccessWithoutReceiver` + `ShouldSkipUnexpectedExpressionToken` + the rewritten full
    `ParsePrimaryExprValue`; the removed Stage-6 `ParseBinaryRightOperandOrMissing`/`ParseRightOperandOrMissing`
    replaced by the boolean operand-missing helpers, since N# has no first-class `Func<Expression>`). +35 native
    parity contracts in `ColumnarParserRecovery.tests.nl` (1,842 → 2,279 lines).
  - Parity + evidence: BootstrapServices contracts 910/910 (875 baseline + 35); dev.sh Parser 381/381; ownership
    audit 18/18 (all deltas `.nl`, no ratchet movement); git status shows ONLY the two `.nl` files + STATUS. NO
    wall (self-contained; packaged SDK 0.1.0 self-emitted the edited owner + all 910 contracts cleanly — no repin).
    Full suite / corpus sweeps N/A (`ColumnarParserRecovery` / `ParseFilePreamble` referenced ONLY by this owner's
    own `.tests.nl`, verified by grep across src+tests+editors); no LSP change → no reload. Next: STAGE 8 =
    match/patterns (deferred), then closing-delimiter recovery.
- Task 016 — SEVENTH slice (parser-front-end arc STAGE 6): the STATEMENT diagnostic family (the block-body
  statement grammar Stages 3-5 left unparsed, the `SynchronizeToNextStatement` sync point + per-statement panic
  reset + `_currentRecoveryBoundaryColumn` tracking, the dangling-binary/assignment-operator through-token span,
  the missing-initializer `:=`/`=` forms, the missing if/while condition, the missing for/foreach `in`, and the
  missing-statement-body report), in N#, PROVEN byte-exact against the freshly built Release CLI oracle. NOT
  committed (mandate: do not commit); working tree carries the two edited N# files + STATUS. NO production wiring —
  Parser.cs remains the sole production syntax authority.
  - Site inventory (grep of ParseStatement + helpers in Parser.cs): the SYNC POINT + BOUNDARY RESET via `ParseBlock`
    (:2143 — panic reset :2172, `_currentRecoveryBoundaryColumn` :2177, `SynchronizeToNextStatement` :2188 → :7084);
    the DANGLING OPERATOR via `ParseRightOperandOrMissing` (:3750) / `ParseBinaryRightOperandOrMissing` (:3778) +
    `DiagnosticSpanFromExpressionThroughToken` (:3842) + `IsMissingOperandBoundary` (:6908); the MISSING-INITIALIZER
    / MISSING-CONDITION via `ParseRequiredExpressionAfter` (:3855) + `IsMissingRequiredExpressionBoundary` (:3928) +
    `LooksLikeStatementStartAfterRequiredExpression` (:3946) + `ShouldUnderlineAnchorForMissingRequiredExpression`
    (:3887) + `DiagnosticSpanFromExpression` (:5917); the MISSING-`in` via `ReportMissingInKeywordAndRecover` (:3908);
    the MISSING-STATEMENT-BODY via `IsMissingStatementBodyBoundary` (:3961) / `ReportMissingStatementBody` (:3968);
    the statement dispatch `ParseStatement` (:2219) and the block-body branch of the function head (:498).
  - Deliverables: `ColumnarParserRecovery.nl` 1,648 → 2,334 lines (+686: the `ExprResult` carrier +
    `RecoveryBoundaryColumn`/`HasRecoveryBoundaryColumn` state; `ParseBlockBody`, `ReportMissingClosingBrace`,
    `SynchronizeToNextStatement`, `ParseStatement`, `IsMissingStatementBodyBoundary`, `ReportMissingStatementBody`,
    `ParseVariableDeclaration`, `ParseIfStatement`, `ParseWhileStatement`, `ParseForStatement`,
    `ParseForeachStatement`, `ConsumeForeachInKeyword`, `ReportMissingInKeywordAndRecover`, `ParseReturnStatement`,
    `ParsePrintStatement`, `ParseExpressionStatement`, `ParseExprValue`, `ParseAdditive`, `ParseMultiplicative`,
    `ParseBinaryRightOperandOrMissing`, `ParseRightOperandOrMissing`, `ReportExpectedExpressionAfter`,
    `DiagnosticSpanFromExpressionThroughToken`, `ParsePrimaryExprValue`, `ParseRequiredExpressionAfter`,
    `ShouldUnderlineAnchorForMissingRequiredExpression`, `IsMissingRequiredExpressionBoundary`,
    `LooksLikeStatementStartAfterRequiredExpression`, `StartsTupleDeconstructionAtCurrentPosition`,
    `IsMissingOperandBoundary`, `IntToString`; `ParseFunctionName` / `ParseFunctionHeadAndBody` extended for the
    block body). +25 native parity contracts in `ColumnarParserRecovery.tests.nl` (1,485 → 1,842 lines).
  - Parity + evidence: BootstrapServices contracts 875/875 (850 baseline + 25); dev.sh Parser 381/381; ownership
    audit 18/18; git status shows ONLY the two `.nl` files + STATUS. NO wall (self-contained; packaged SDK 0.1.0
    self-emitted the edited owner + all 875 contracts cleanly — no repin). Full suite / corpus sweeps N/A
    (`ColumnarParserRecovery` / `ParseFilePreamble` referenced ONLY by this owner's own `.tests.nl`, verified by
    grep across src+tests+editors); no LSP change → no reload. Next: STAGE 7 = expressions/patterns.
- Task 016 — SIXTH slice (parser-front-end arc STAGE 5): the GENERICS / CONSTRAINTS diagnostic family
  (`ReportMissingTypeParameterName` / `ReportMissingGenericTypeArgument` NL102, the reserved-keyword NL109
  type-param name, the `ConsumeGreater` split-`>>` discipline + its NL102 unclosed-list error, and the
  `where`-clause NL102/NL109 name/colon errors + the class/struct and struct/new() NL103 `InvalidSyntax`
  validations), in N#, PROVEN byte-exact against the freshly built Release CLI oracle. NOT committed (mandate:
  do not commit); working tree carries the two edited N# files + STATUS. NO production wiring — Parser.cs remains
  the sole production syntax authority.
  - Site inventory (grep of Parser.cs): TYPE PARAMS via `ParseTypeParameters` (:725) → `ConsumeIdentifier` (:743)
    + `ReportMissingTypeParameterName` (:6439) + the closing `Consume(Greater)` (:747); GENERIC ARGS via the
    generic type-reference (:1925-1957) → `ReportMissingGenericTypeArgument` (:6457); the `ConsumeGreater`
    split-`>>` (:2101, `_splitGreaterDepth` + split-aware Check :6025 / Advance :5860, reset :7042/:7086);
    `where` constraints via `ParseGenericConstraints` (:851) → `ConsumeIdentifier` (:861) / `Consume(Colon)`
    (:862) / the class-struct (:901) + struct-new (:915) `InvalidSyntax` validations with
    `LaterToken`/`TokenLengthOrFallback`/`TokenSpanLengthOrFallback` (:6010/:5897/:5900).
  - Deliverables: `ColumnarParserRecovery.nl` 1,252 → 1,648 lines (+396: split-aware Check/Advance +
    SplitGreaterDepth; `ParseTypeParameters`, `ReportMissingTypeParameterName`, `ParseTypeReferenceRecovery`,
    `ReportMissingGenericTypeArgument`, `ConsumeGreater`, `ConsumeToken`, `GetHintForMissingToken` /
    `HintForMissingTokenOrDefault`, `ParseGenericConstraints`, `ReportClassStructConflict`,
    `ReportStructNewRedundancy`, `LaterToken`, `TokenLengthOrFallback`, `TokenSpanLengthOrFallback`,
    `DiagnosticSpanFromTokenRange`; `ParseFunctionHeadAndBody` / `ParseClassName` / `ParseStructName` extended).
    +22 native parity contracts in `ColumnarParserRecovery.tests.nl` (1,144 → 1,484 lines).
  - Parity + evidence: BootstrapServices contracts 850/850 (828 baseline + 22); dev.sh Parser 381/381; ownership
    audit 18/18; git status shows ONLY the two `.nl` files + STATUS. NO wall (self-contained; packaged SDK 0.1.0
    self-emitted the edited owner + all 850 contracts cleanly — no repin). Full suite / corpus sweeps N/A
    (`ColumnarParserRecovery` / `ParseFilePreamble` referenced ONLY by this owner's own `.tests.nl`, verified by
    grep across src+tests+editors); no LSP change → no reload. Next: STAGE 6 = statements.
- Task 016 — FIFTH slice (parser-front-end arc STAGE 4): the MEMBER / PARAMETER / FIELD declaration
  diagnostic family (the `:`/`:=` colon and type-annotation errors, NL102 `ExpectedToken` / NL109
  `ReservedKeywordAsName`), in N#, PROVEN byte-exact against the freshly built Release CLI oracle. NOT committed
  (mandate: do not commit); working tree carries the two edited N# files + STATUS. NO production wiring —
  Parser.cs remains the sole production syntax authority.
  - Site inventory (grep of Parser.cs): PARAMETERS via `ParseParameterList` (:751) → `ConsumeIdentifier`(msg,
    span?) (:6720) + `GetMissingParameterNameDiagnosticSpan` (:6476), `ConsumeParameterColon` (:6625),
    `ParseParameterTypeReference` (:6504); FIELDS via `ParseFieldDeclaration` (:1637) → no-span `ConsumeIdentifier`
    (:1666), `ConsumeFieldColon` (:6651), `ParseFieldTypeReference` (:6536) + `LooksLikeNextFieldAfterMissingType`
    (:6572); the MEMBER-BOUNDARY panic reset in `ParseMemberList` (:1365); and the Stage-2-deferred braced-kind
    found-other NAME (`ConsumeDeclarationName` reached with a `{` offender, retired for `class {` / `struct {`).
  - Deliverables: `ColumnarParserRecovery.nl` +~350 lines (`ParseParameterListRecovery`, `ConsumeNameWithSpan`,
    `GetMissingParameterNameDiagnosticSpan`, `ConsumeParameterColon`, `ParseParameterTypeReference`,
    `ParseTypeBodyIfPresent`, `ParseMemberList`, `ParseFieldMember`, `ConsumeFieldColon`,
    `ParseFieldTypeReference`, `LooksLikeNextFieldAfterMissingType`, `ParseSimpleTypeReference`, `TypeErrorAnchor`,
    `IsVisibleName`, `IsTypeTerminator`, `SingleSuggestion`, `FieldColonSuggestions`; `ParseFunctionHeadAndBody` /
    `ParseClassName` / `ParseStructName` extended). +17 native parity contracts in `ColumnarParserRecovery.tests.nl`.
  - Parity + evidence: BootstrapServices contracts 828/828 (811 baseline + 17); dev.sh Parser 381/381; ownership
    audit 18/18; git status shows ONLY the two `.nl` files + STATUS. NO wall (self-contained; packaged SDK 0.1.0
    self-emitted the edited owner + all 828 contracts cleanly — no repin). Full suite / corpus sweeps N/A
    (`ColumnarParserRecovery` / `ParseFilePreamble` referenced ONLY by this owner's own `.tests.nl`); no LSP
    change → no reload.
- Task 016 — FOURTH slice (parser-front-end arc STAGE 3): the MALFORMED-LITERAL diagnostic family (NL105
  `InvalidLiteral`), in N#, PROVEN byte-exact against Parser.cs. NOT committed (mandate: do not commit);
  working tree carries the two edited N# files + STATUS. NO production wiring — Parser.cs remains the sole
  production syntax authority.
  - Origin inventory (grep of Parser.cs AND the N# Lexer path): all six shapes are Parser.cs-REPORTED inside
    `ParsePrimaryExpression` — `ReportMalformedCharLiteralIfNeeded` (:4646→:4905, empty/unterminated char),
    `ReportMalformedStringLiteralIfNeeded` (:4653→:4830, unterminated string + unterminated interpolated
    single-line string), and its delegate `ReportMalformedRawStringLiteralIfNeeded` (:4876, unterminated
    triple-quoted + unterminated interpolated-raw), each routed through the shared-panic `ReportError`
    (:6845). The already-N# `Lexer.nl` (`ReadString`/`ReadCharLiteral`/`ReadTripleQuoteString`/
    `ReadInterpolatedRawString`) only CLASSIFIES — it sets `Token.IsTerminated` and builds the token value —
    and emits NO diagnostic. The malformed DECISION delegates to the LIVE shared N# owner `ParserLiteralFacts`
    (`IsCompleteStringLiteral`/`IsCompleteCharLiteral`), the identical calls Parser.cs makes. VERDICT: the
    family belongs to the PARSER model (Parser.cs-reported, shared-panic-gated), NOT a separate lexer lane; it
    is carried in FULL this stage. (`import`-path and test-description strings are NOT part of it — they never
    run the malformed check; `import "abc` → NL701, verified.)
  - Extended `ColumnarParserRecovery.nl`: `ReportMalformedLiteralIfNeeded` dispatches to the three ported
    reporters (byte-exact messages / explanations / hints / suggestions / marker-lengths), all routing through
    the shared-panic `Report`; the decision reuses `ParserLiteralFacts` and construction reuses
    `ParserErrorDiagnostics.Create`. `ParseFunctionName` now continues a validly-named function through its
    head (empty params, optional return type) into the `=> <expr>` expression body via a MINIMAL
    literal-reaching expression path (`ParseLiteralBearingExpression`/`ParseLiteralBearingPrimary`:
    `( expr )` grouping + literal primaries + a flat binary-operator continuation) — enough to reach literals
    and consume the corpus's trailing tokens identically to Parser.cs's `ParseExpression`. Stage-2 name-error
    cases preserved (a `<error>` name returns before any body parse). The expression/statement ERROR families
    are NOT modeled (a later arc stage); their would-be errors never fire because they route through the same
    shared panic the literal error already set, so the output is byte-exact.
  - +14 native parity contracts in `ColumnarParserRecovery.tests.nl`: one per literal shape (string / char /
    empty char / triple / interpolated / interpolated-raw), across-boundary (two malformed funcs → 2 diags;
    malformed literal then stray top-level token → NL105 + NL101), IN-REGION suppression (`'a + 'b` and
    `'' + 'b` → 1 diag — the second malformed literal's check runs but is suppressed by shared panic; the
    parenthesized `('a` anchors the char at column 14 and suppresses the missing `)`), and negatives
    (well-formed literals report nothing). Every expected value is GOLDEN Parser.cs output captured from the
    freshly built Release CLI (`nlc check --json`, filtered NL101-NL109).
  - Evidence: BootstrapServices contracts 811/811 (797 baseline + 14; packaged SDK 0.1.0 self-emits the edited
    owner + tests cleanly, INCLUDING the `"""`-bearing message literals); dev.sh Parser 381/381; ownership
    audit 18/18 (no ratchet change — all deltas are `.nl`); git status shows ONLY the two `.nl` files + STATUS
    (no non-N# file moved). Full unit suite / corpus IL sweeps N/A — `ColumnarParserRecovery` is referenced
    ONLY by its own tests (verified across src/tests/examples), so nothing in the production compile path
    changed. No LSP/VS Code change → no extension reload. NO wall tripped (self-contained; no dependent
    compiles against a changed kernel signature). Next: STAGE 4 (member/parameter/field declaration family).

- Task 016 — THIRD slice (parser-front-end arc STAGE 2): the DECLARATION-NAME diagnostic family, in N#,
  PROVEN byte-exact against Parser.cs. NOT committed (mandate: do not commit); working tree carries the two
  edited N# files + STATUS. NO production wiring — Parser.cs remains the sole production syntax authority.
  - Extended N# owner `ColumnarParserRecovery.nl`: `ConsumeDeclarationName(message, anchor)` (Parser.cs
    ConsumeIdentifier with a non-null diagnosticSpan, :6720) — the keyword-anchor overrides the offending-
    token span in all three variants (reserved-keyword NL109 / end-of-file NL104 / found-other NL102), so a
    missing/invalid declaration name underlines the DECLARATION KEYWORD. Added the `ParseTopLevelDeclaration`
    dispatch (ParseModifiers + the exact Parser.cs ParseDeclaration keyword order, incl. `ref struct` /
    `soa record` (contextual, LookAhead) / `duck interface` / `record struct` variants), the per-kind name
    parsers (func/class/struct/record/soa/interface/union/enum/type-alias, each anchoring on
    DiagnosticSpanFromToken(keywordToken) per Parser.cs :435/939/984/1029/1067/1143/1173/1247/1337), a
    `LookAhead` helper, and the boundary loop with the force-advance safety net (Parser.cs
    ParseCompilationUnit :83/:99-108). Removed the now-unreferenced `IsDeclarationStart`/
    `IsContextualDeclarationStart` (superseded by the dispatch). Bodies are NOT parsed (a later arc stage).
  - Site inventory (Parser.cs ConsumeIdentifier sites carried, with keyword anchor): func :435, class :939,
    struct :984, record :1029, soa record :1067, interface :1143, union :1173, enum :1247, type-alias :1337
    (the last uses `new DiagnosticSpan(line,column,Math.Max(1,"type".Length))` = SpanFromToken(typeToken)).
    All route through the shared `ConsumeDeclarationName` + `ReportReservedKeywordAsName` + `Report` model;
    the terminal unexpected-token arm reuses Parser.cs ParseDeclaration :241.
  - +24 native contracts in `ColumnarParserRecovery.tests.nl`: per-kind absent-name (EOF, 11 incl. the soa
    col-5 / duck col-6 / record-struct anchor variants), per-kind reserved-keyword-as-name (8 core kinds),
    found-other for func/enum/type (the panic-reset shape: name error then the stray token fires at the next
    boundary), and two panic-model interaction fixtures (`func 5\nenum` three-diagnostic cross-boundary;
    `class struct\nfunc class` two reserved names at two boundaries). Every expected value is GOLDEN Parser.cs
    output captured from the fresh Release CLI (`nlc check --json`, filtered to NL101-NL109).
  - Method: BootstrapServices cannot reference Parser.cs, so parity is proven against golden Parser.cs output
    captured out-of-band, same as STAGE 1. class/struct/record/interface/union found-other cases were
    DELIBERATELY EXCLUDED (their member-list body consumes the trailing junk and resets panic, diverging from
    a name-only parser — verified against the oracle, e.g. `class 5` → NL102+NL106+NL102 not NL102+NL101);
    they retire in the body/closing-delimiter stage.
  - Evidence: BootstrapServices contracts 797/797 (773 baseline + 24 new; packaged SDK 0.1.0 self-emits the
    edited owner cleanly); ownership audit 18/18 (no ratchet change — all deltas are `.nl`); git status shows
    ONLY the two `.nl` files changed (no non-N# file moved). Full unit suite / corpus IL sweeps are N/A —
    nothing in the production compile path changed (the owner is inert, referenced only by its own tests). No
    LSP/VS Code change → no extension reload. NO wall tripped (self-contained, no dependent compiles against a
    changed kernel signature). Next: STAGE 3 (malformed-literal family).

- Task 016 — SECOND slice (parser-front-end arc STAGE 1): shared-panic RECOVERY MODEL + import/namespace/
  package diagnostic family, in N#, PROVEN byte-exact against Parser.cs. NOT committed (mandate: do not
  commit); working tree carries the two new N# files + the `ColumnarSyntaxDiagnostics` scaffolding deletion
  + STATUS. NO production wiring — Parser.cs remains the sole production syntax authority (cutover is the
  arc's last stage).
  - Added N# owner: `src/NSharpLang.Compiler.BootstrapServices/ColumnarParserRecovery.nl` — a faithful
    reproduction of Parser.cs's `_panicMode` lifecycle (one shared flag; suppress-while-set; set-on-report;
    reset only at the declaration-boundary sync point), ordered reporting, and the `ConsumeIdentifier`
    reserved-keyword / end-of-file / found-other message variants + `LastVisibleTokenSpan` EOF anchoring,
    carrying the import/namespace/package family end-to-end (qualified-name identifier errors, dot-access
    member errors, missing import alias, duplicate-package, and the declaration-boundary terminal
    unexpected-token arm). Diagnostic construction delegates to the live shared `ParserErrorDiagnostics.Create`.
    Introduces a local `RecoverySpan` reference class instead of the C#-owned `DiagnosticSpan` value struct
    (user value-struct construction is not yet columnar-emittable), and inlines the Newline-strip compaction
    (the reference-typed `out` argument on `ParserTokenCompactor.TryCompact` is not yet columnar-emittable) —
    both faithful to Parser.cs's behavior. Plus `ColumnarParserRecovery.tests.nl` — 11 native parity
    contracts against golden Parser.cs output (captured from the fresh CLI), including the cascading-
    suppression shape (`Parser_CascadingErrorsSuppressed`) and the does-not-swallow-following shape
    (`Parser_DanglingBinaryOperator_...`).
  - Deleted N# owner: the inert divergent `ColumnarSyntaxDiagnostics` scaffolding closure
    (`ColumnarSyntaxDiagnostics.nl` + `ParserDiagnosticMessages.nl` + `ParserDiagnosticsTable.nl`, ~2,177
    lines) — superseded by the correct-model `ColumnarParserRecovery`; zero external references (verified);
    `ParserErrorDiagnostics.nl` kept (live). See the arc plan's scaffolding-fate decision.
  - Method: BootstrapServices cannot reference Parser.cs (Compiler depends on BootstrapServices, not the
    reverse), so parity is proven against GOLDEN Parser.cs output captured out-of-band via `nlc check --json`
    on the malformed corpus, filtered to parser codes NL101-NL109. Both paths construct diagnostics through
    the identical live `ParserErrorDiagnostics.Create`, and the CompilerError→DiagnosticResult mapping +
    `DiagnosticSpanResolver.Resolve` (length>0) are identity for these cases, so the golden values equal the
    owner's raw CompilerError fields.
  - Evidence: BootstrapServices contracts 773/773 (762 baseline + 11 new; unchanged by the scaffolding
    deletion — no `.tests.nl` in it); ownership audit 18/18 (no ratchet change — all deltas are `.nl`, and
    the ratchet tracks only non-N# files); dev.sh Parser 381/381 (C# build re-emits the new file + the
    deletion cleanly, Parser oracle green). NO wall tripped: the self-contained shape (new `.nl` + `.tests.nl`,
    no dependent compiling against a changed kernel signature) emits through the packaged SDK 0.1.0 with no
    repin. Full unit suite / corpus IL sweeps are N/A this stage — nothing in the production compile path
    changed (the new owner is inert, referenced only by its own tests; the deletion removed inert code). No
    LSP/VS Code change → no extension reload. Next: STAGE 2 (next diagnostic family — declaration-name or
    malformed-literal — through the same model).

- Task 016 — FIRST slice: PROVEN-BLOCKED-WITH-RECORD (no commit; mandate: do not commit; STATUS.md-only,
  working tree otherwise clean). No C#/N# production delta. The full consumer inventory, the AST-bridge
  blocker, the syntax-diagnostic blockers (`ColumnarSyntaxDiagnostics` ~8% coverage / divergent panic
  model / shared-panic coupling), and the honestly-sized prerequisite are recorded in the "016
  parser/diagnostic ownership finding" section. Evidence is code + committed-test grounded: ~256 vs ~20
  diagnostic coverage; `Parser_CascadingErrorsSuppressed` + `Parser_DanglingBinaryOperator…` pin the
  shared-panic model; `ColumnarSyntaxDiagnostics`/`ParserDiagnosticMessages`/`ParserDiagnosticsTable` have
  ZERO external references and no `.tests.nl`; `MultiFileCompiler`/LSP/`Analyzer` all consume the C#
  `CompilationUnit` monolithically with no node-table→AST bridge. Next: the enabling PARSER-KERNEL slice
  (kernel-repin wall) or the task-017 front-end port.

- Task 015 sub-slice — interpolation BASE-CALL classification → N# splitter. NOT committed this turn
  (mandate: do not commit); working tree carries the emitter deletion + the N# splitter method + its tests
  + repin + STATUS.
  - Deleted C# owner: the string-classification half of `TryResolveInterpolationBaseCallPlan` (the `base.`
    prefix + `()` suffix Ordinal parse and the method-name extraction/validation with the no-`.`/`(`/`)`
    guard) in `ColumnarIlEmitter.cs`. Replaced by one mechanical call to
    `ColumnarInterpolationSplitter.TrySplitBaseCall(text, out methodName)` plus a fence comment; the retained
    `_currentStruct?.BaseDef == null` reflection guard, `TryFindMethodOnChain` base-chain resolution, and the
    return-type guards (`void`/enum/generic-param/`ContainsBuilderBoundType`/`IsSupportedType`) stay as the
    mechanical host. `ColumnarIlEmitter.cs` fell 21,438 → 21,433 (net −5 lines / −4 non-blank; epoch ceiling
    21,723/20,646 untouched). This was the LAST inline interpolation string-classification split (cast/
    equality/coalesce/integer-additive already N#-owned) — the movable-decision surface is now exhausted (see
    the 015 completion roadmap).
  - Added N# owner: `ColumnarInterpolationSplitter.TrySplitBaseCall` (an exact mirror of the accepted
    `TrySplitCast`/`TrySplitEquality`/`TrySplitCoalesce` split-decision methods; `import System` added for
    `StringComparison.Ordinal`) + two canonical `.tests.nl` contracts (decompose modeled base-call holes;
    decline non-base-call shapes: no prefix, no `()` suffix, arg-suffix, empty name, paren-in-name, dotted
    name).
  - Method: the live corpus path `examples/06-classes-and-records/ConstructorChaining.nl:56`
    (`$"{base.GetInfo()} - {EmployeeId} ({Department})"`) exercises the arm, making the relocation directly
    byte-exact verifiable rather than a dead-code deletion.
  - Evidence: product IL BYTE-EXACT — PRODUCT_IL_DIFFS=0 across all 162 N#-emitted example/fixture/native
    assemblies (baseline HEAD `6e94ca88c` via `git stash` vs working tree, both fresh Release CLIs,
    `sweepall.sh`); native 208/208 (18 projects; ownership-audit 18/18 post-repin — the single pre-repin
    failure was the ratchet net-negative check, cleared by the repin); BootstrapServices contracts 762/762
    (760 baseline + 2 new split tests, fresh Release self-emit); units 3,190/3,190 Release; Web API template
    builds via the IL backend; ratchet repin (currentLines 21,438→21,433, head `d7f043fb072388db`, mirrored
    in OwnershipAudit.nl).

- Task 015 pivot sub-slice — case-12 primitive-binary residual dead-arm prune (pivot off the blocked
  lambda family). COMMITTED at `6e94ca88c` ("Prune the dead case-12 residual arms by four-surface liveness
  proof"); ratchet head `40cb7fa576abc6c2`.
  - Deleted C# owners: the case-12 primitive-binary whole-subtree residual's four provably-dead sub-arms —
    the `&`/`|`/`^` bitwise arm, the record-struct structural-equality arm (`==`/`!=` boxing through the
    synthesized Equals), the `null == null`/`null != null` constant fold, and the multi-term string-concat
    CHAIN lowering (`TryEmitStringConcatChain` + its sole caller `CanProveStringExpression`). The residual
    pair-concat (`String.Concat(string,string)`) and the reference-identity/string+char/ternary residuals
    stay (self-emit-live). `ColumnarIlEmitter.cs` fell 21,534 -> 21,438 (net -96 lines / -92 non-blank;
    epoch ceiling 21,723/20,646 untouched).
  - Added N# owners: none — ColumnarPrimitiveBinaryPlanner / ColumnarConditionalPlanner already own the
    plannable surface at the front door; the deleted arms served an empty non-plannable-operand band.
  - Method: IL-neutral env-gated arm instrumentation (0 IL diff instrumented vs baseline across all 162
    assemblies) built a FOUR-surface liveness map (corpus+native, units 3,190, full self-emit 228 arms).
    The four deleted arms were 0 on all three logs; three sibling arms (ternary, ref-identity equality,
    string+char) were caught firing in the FULL self-emit and RETAINED (a partial 166-arm run had missed
    `stringcharconcat` — the slice-5 escape signature). Candidate (a) preflight static-call typing proven
    load-bearing (types user-owned enclosing-type statics, not catalog facts) — blocked, recorded.
  - Evidence: product IL BYTE-EXACT (0 diffs across all N#-emitted example/fixture/native assemblies; the
    only 12 sweep diffs are the C# `Compiler.dll`/`BootstrapServices.dll` binaries copied as a reflection-test
    dependency by 6 native projects — expected reflection of the emitter source change, not product IL);
    native 208/208 (18 projects, ownership-audit 18/18 post-repin); BootstrapServices contracts 760/760
    (two-stage, fresh deletion Release SDK); units 3,190/3,190 (Debug and Release); Web API template builds
    via the IL backend; ratchet repin (audit 18/18, head `40cb7fa576abc6c2`); clean feed restored.

- Task 001 — external static fields and properties; commit `6110bbbcf`.
  - Deleted C# owners: `TryUsePlannedExternalStaticMember`,
    `PreloadSupportedExternalReferenceAssemblies`, `TryGetStringComparisonValue`,
    `TryEmitPrimitiveStaticConstant`, and the matching enum/primitive/pool/static-member emission
    and preflight branches. `ColumnarIlEmitter.cs` fell from 21,515 to 21,361 lines.
  - Added N# owners: `ColumnarBindingScopeFacts`, `ColumnarExternalStaticMemberPlanner`,
    `ExternalAssemblyScan`, `ExternalQualifiedTypeResolver`, schema-v3 field handles/`ldsfld`, and
    their native contracts plus package and relative-DLL product fixtures.
  - Evidence: 3,182 units; 178 BootstrapServices contracts; 18 ownership tests; package,
    outside-CWD DLL, issue-tracker, exact-reference, persisted execution, and clean repin proofs.

- Task 002 — bound identifier reads; commit `61a593715`.
  - Deleted C# owners: ordinary local/non-byref-parameter, lifted-local, boxed-capture,
    explicit-`this`, and bare current-instance field/property identifier emission, plus the
    matching preflight/type branches. `ColumnarIlEmitter.cs` fell from 21,361 to 21,209 lines.
  - Added N# owners: `ColumnarBoundIdentifierPlanner`, exact lexical/current-instance binding
    facts, recursive code-plan argument-address and declared-signature validation, live source-type
    metadata, and atomic zero-arity property accessor definition, with native malformed, rollback,
    shadowing, generic/inherited receiver, persisted, and source-type-return contracts.
  - Evidence: 3,182 units; 201 BootstrapServices contracts; 26 range-index product contracts;
    18 ownership tests; fresh non-VS-Code product-gate task surfaces; clean SDK repin.

- Task 003 — instance fields and properties; commit `ad51692d4` (stage-0 prerequisites
  `da2be2c32`, `97cde7c6e`, and `aedb1267f`).
  - Deleted C# owners: direct one-receiver source field/property read emission, direct
    `Exception.Message` and `WebApplication.Environment` property arms, the member-chain preflight
    shortcut for the migrated roots, `typeof` emission/preflight, and zero-hole interpolation
    emission. The retained source-member branch is restricted to excluded nested receivers.
    `ColumnarIlEmitter.cs` fell from 21,209 to 21,164 lines.
  - Added N# owners: `ColumnarInstanceMemberPlanner`, exact runtime/source member resolvers,
    schema-v3 field/method/type handles and receiver-address operations, `ColumnarTypeOfPlanner`,
    zero-hole interpolation receiver planning, and live source type/union/tuple facts, with native
    accessibility, shadowing, inheritance, closed-generic, value/reference/byref, corrupt-handle,
    rollback, persisted-execution, nested-fallback, and recursive range/index contracts.
  - Evidence: 3,182 units; 238 BootstrapServices contracts; 41 range-index product contracts;
    18 ownership tests; three adversarial audits; fresh non-VS-Code product-gate task surfaces;
    clean SDK repin.

- Task 004 — fixed-arity direct calls; commit `5ad756e1d` (stage-0 prerequisites `d6d551ea1`,
  `d24ec7bb4`, `8ce4d49e2`, `fcbcf4ef6`, `0cd216a44`, `0e1d02ed1`, `507742abc`,
  `1e747dd97`, `469408917`, `1b63b9a82`, and `0035d82ae`).
  - Deleted C# owners: synthesized-record `Equals(object)` and `GetHashCode()` call preflight and
    emission, the direct `TextWriter.WriteLine(string)` arm, and unrestricted re-entry into ordinary
    source/runtime fixed-call paths. Retained C# routes are mechanically fenced to excluded call
    families. `ColumnarIlEmitter.cs` fell from 21,164 to 21,097 lines.
  - Added N# owners: `ColumnarDirectCallPlanner`, exact source/runtime resolvers, contextual
    conversion and nullable lowering, source-static scope resolution, exact method/constructor facts,
    address-preserving value receivers, synthesized record call facts, and schema/executor stack
    validation, with native overload, accessibility, malformed-handle, rollback, recursive,
    persisted, alias/shadowing, and IL-shape contracts.
  - Evidence: 3,181/3,182 fresh-gate units with only Task 009 remaining; 382 BootstrapServices
    contracts; 14 direct-call, 2 interface-parameter, 18 ownership, 4 decline-diagnostic, and 2
    reflection-bootstrap contracts; exact ILVerify; three adversarial audits; clean SDK repin.

- Task 005 — construction and array literals; commit `6746c1b2c` (stage-0
  prerequisites `67a3e5803`, `37822d657`, `f9ed33dd9`, `aca8d35b3`, `91c062dd6`, `e63f27176`,
  and `ff2cf1138`).
  - Deleted C# owners: the Analyzer's string-matched member/export/declaration resolution
    (nested-type, tuple, primary-constructor-parameter, declared-member and export-visibility
    string lookups; `Analyzer.cs` fell from 23,471 to 23,068 lines), the emitter's unconditional
    construction ownership (constructions claimed by the N# planner never reach C#; the retained
    kinds 15/58/36 arms are fenced to the whole-subtree residual), and
    `ColumnarSynthesizedGenericScopeTests.cs` (replaced by the native `generic-scope-invalid`
    project). Aggregate C# net −157 lines.
  - Added N# owners: `ColumnarConstructionPlanner` (source/runtime/closed-generic constructor
    selection with defaults, sized/inferred arrays, source and union-case object initializers,
    runtime catalog), construction-row execution in `ColumnarCodePlanExecutor`,
    `ColumnarSemanticTypeRegistry` + `AnalyzerDeclarationContext` exact declaration scopes,
    `ColumnarPrimitiveBinaryPlanner` (admitted value-position binaries),
    `ColumnarSourceOperatorResolver`, and `TypeInfoIdentityFacts`, with native construction-arrays,
    generic-scope-invalid, and erased-enum-identity product contracts.
  - Evidence: 3,182/3,182 fresh-gate units (issue-tracker fixed); 553 BootstrapServices contracts;
    14 direct-call, 18 ownership, 7 construction-arrays, 3 generic-scope-invalid, and 1
    erased-enum-identity contracts; fresh non-VS-Code product gate down to four failure groups all
    verified pre-existing at HEAD and owned by 009/011/012/013/014; ratchet repin (audit 18/18);
    clean SDK repin.

- Task 006 — primitive binary expressions; commit `e57c80c8a` (stage commits `3dcb60bd2`,
  `e41570f69`, `83941f204`, `62ab5ffdf`, `096655625`, `5523402c5`, `aade33590`, `8397811ea`).
  - Deleted C# owners: the case-12 shifts branch, decimal op_* table, and right-literal adoption
    path from both emission and preflight, plus the preflight's arith/bitwise/ordering/numeric
    equality arms. `ColumnarIlEmitter.cs` fell from 21,618 to 21,499. The retained fenced numeric
    core serves exactly the whole-subtree residual: contextual-lambda call operands (010), member
    chains on call results, unary-negated call operands, dictionary-indexer reads, and string-typed
    operands such as enum string-constant reads (015 grows the nested-operand surface).
  - Added N# owners: the full primitive binary family (arithmetic with checked/unchecked overflow
    selection, bitwise, shifts, ordering with float unordered complements, numeric/Boolean
    equality, decimal op_* calls, string-pair concat, right-literal adoption) at expression roots
    and value position; operand families unlocked along the way — numeric casts, decimal literals
    (incl. negative), sibling-function calls, local-delegate invocations, String.Join catalog,
    List<T> indexer chains, byref-parameter deref reads over the typed-ldind family, ushort literal
    casts, and slot-reinterpretation casts via explicit conv.
  - Evidence: 608 BootstrapServices contracts (Debug and fresh Release self-emit); 15 primitive-
    binary, 41 range-index, 14 direct-call, 3 interface-parameter, 18 ownership contracts;
    3,182/3,182 units; fresh non-VS-Code gate at the same four pre-existing later-owner failure
    groups (009/011/012/013/014) as the 005 acceptance; toolset repins at each two-stage bootstrap.

- Task 007 — conditional and short-circuit expressions; commit `e9df4eb60` (routing commit
  `7eaccb1e9`, Brtrue two-stage bootstrap with mid-stage toolset repin).
  - Deleted C# owner: the `&&`/`||` sub-arm in `TryGetPreflightBinaryExpressionType` (proven dead —
    N# types every plannable short-circuit at the front door; a residual short-circuit is only ever
    emitted, never preflight-typed; zero hits across units, native contracts, examples, and the
    self-emit). `ColumnarIlEmitter.cs` fell from 21,499 to 21,497. The case-12 short-circuit and
    case-13 ternary EMIT arms are verify-first load-bearing (self-emit ternary null-comparison
    conditions; example `||` chains over string equality) and are recut as precisely-fenced
    whole-subtree residual servers retiring with task 015's nested-operand/equality surface growth.
  - Added N# owners: `ColumnarConditionalPlanner` — Boolean `&&`/`||` with the exact case-12
    short-circuit lowering and relocated ternary planning with widened operand recursion, claimed
    at expression roots and value position across emit and preflight facades; the `Brtrue` schema
    identity (contract id 58, condition-gated validation, allowlist name).
  - Evidence: 619 BootstrapServices contracts (Debug and fresh Release-packed-SDK re-emit); new
    conditional product project 8/8 with executed side-effect-order and right-operand-not-evaluated
    proofs; 3,182/3,182 units; all native projects green; fresh non-VS-Code gate at the same four
    pre-existing later-owner failure groups (009/011/012/013/014); clean toolset repin.

- Task 008 — complete range/index owner deletion; commit `23ced5034`.
  - Deleted C# owners: every range/index decision from `399008ea9` and its expansions — five
    static handles plus their resolver, thirteen lowering helpers, the case-11 index-from-end and
    case-69 range arms, the case-10 string/array Index/Range reads, and both preflight
    type-selection helpers with their dispatch arms. Only the Index/Range type-system entries
    remain (typed locals/parameters, not lowering policy). Residual inventory: empty — no fallback
    from N# to any old branch. `ColumnarIlEmitter.cs` fell from 21,497 to 21,209 (net −288).
  - Added N# owners: none needed — `ColumnarRangeIndexPlanner`/`ColumnarRangeIndexHandles` already
    owned the entire surface; the historical C# canonical test was migrated at `0206a1ed1`.
  - Evidence: 41/41 range-index product contracts identical before and after the deletion (the
    decisive dead-code proof); 619 BootstrapServices contracts against both feed and fresh SDK;
    3,182/3,182 units; all native projects green; fresh Release self-emit clean; fresh non-VS-Code
    gate at the same four pre-existing later-owner failure groups (009/011/012/013/014).

- Task 009 — external base and interface resolution; slice commits `85c817440` (base/interface
  classification), `5f9bf3fce` (inherited external-base-method calls), and the extension-calls
  commit; ACCEPTANCE: the generated Web API template checks, builds, and ILVerifies clean, and the
  fresh gate fell from four failure groups to three (013/014 iterators, 011/012 ilverify).
  - Deleted C# owners: the emitter's PASS 0a' base/interface classification decision block
    (`ColumnarIlEmitter.cs` 21,209 → 21,164); the remaining slices added zero C#.
  - Added N# owners: `ColumnarBaseTypePlanner` (ordered base classification incl. external runtime
    class bases with protected-ctor default chaining), inherited external-base-method bare/this
    call planning over the recorded base chain, `ColumnarExtensionMethodResolver` (ExtensionAttribute
    index with instance-beats-extension precedence and trailing-optional null-default fill),
    IServiceCollection admission, and highest-version NuGet runtime-asset unification.
  - Evidence: 625 BootstrapServices contracts; external-base-interface 18/18, extension-calls 4/4
    executed; 3,182/3,182 units; fresh Release self-emit clean; Web API ILVerify fully verified;
    all native projects green; gate baseline shrunk to three groups.

- Task 014 — async iterators; staged commits `d396a847c` (async classification facts: IsAsync,
  AwaitResumeCount, async return-shape admission/declines), `73ae226d5` (await-foreach parsing in
  the N# kernels: awaited kind-29 form + kind-73 consumer statement, toolset repin), `0a33f1ff2`
  (async state machines with REAL suspension: IAsyncEnumerable/IAsyncEnumerator/IAsyncDisposable
  member specs, schema-4 catch regions op 7, awaiter/promise/result/continuation field roles 5-8,
  MoveNextAsync fast-path vs TaskCompletionSource pending path, ldftn MoveNextCore continuation
  ctor, both exception routes, clone/dispose discipline — proven resuming off-caller-thread),
  `f3d1e89c9` (closing: classic C-style for kind 28, postfix ++/-- kind 44 incl. yield i++,
  ToUpper/ToLower/Trim instance calls, kind-73 await-foreach consumer lowering via the accepted
  blocking-await model; AsyncStreams.nl end-to-end).
  - NEW SURFACE like 013: no C# async-iterator emitter ever existed; deletion contract satisfied
    by planner-owned decline sites (emit.iterator.async-*) plus the deleted
    emit.iterator.async-emit-pending gate and zero net C# decision growth (emitter net −2 across
    the closing slice: 21,719/20,644 vs immutable epoch 21,723/20,646 — case-73 additions paid by
    lossless comment compression).
  - Added N# owners: ColumnarIteratorPlanner async classification + AnalyzeShape async facts +
    BuildAsyncMoveNextCore/MoveNextAsync/DisposeAsync/GetAsyncEnumerator/AsyncFactory plans, the
    kind-28/44/instance-string-call body surface, ColumnarCodePlan/Executor schema-4 catch
    regions, parser-kernel await-foreach forms.
  - Evidence: FULL VS Code-ENABLED GATE GREEN — ZERO failure groups (first fully-green gate of
    the closeout; AsyncStreams cleared; 14m11s; gate exit 0 with ALL TESTS PASSED). 731/731
    BootstrapServices contracts (717+14); 3,185/3,185 units; native iterators 25/25 (21+4 async);
    ownership audit 18/18; AsyncStreams.nl builds via the columnar pipeline, output order exact,
    real delays (1.273s wall for 10×100ms+4×50ms), ILVerify 2/2; nlc check/lint on the example
    0 findings; post-commit SDK repin to ~/.nuget/local-feed + gate dependency-cache reseed
    (nsharplang.* must be copied into the active Caches/NSharpLang/test-all/dependencies/<key>
    after a repin — the isolated gate only sees nuget.org plus that cache). VS Code extension
    rebuilt+reinstalled (reload-vscode-extension.sh exit 0); gate VS Code integration tests
    (extension, diagnostics, hover, completion) pass. OUTSTANDING: the computer-use visual IDE
    spot-check was attempted at this acceptance and screen-control access was DENIED at the
    approval dialog again (second denial after 013); the automated VS Code integration evidence
    stands in. Retry at the next IDE-affecting acceptance only if the user re-enables access.
  - Residuals recorded for 015+: await foreach inside an async iterator body (machine
    composition), async instance/generic iterators, awaited operands beyond statement-position
    Task.Delay(int), real async-func lowering to retire the blocking consumer await model.

- Task 013 — synchronous iterators; staged commits `489895987` (func*/yield parsing in the N#
  kernels, node kind 72, generator flag 4096, toolset repin), `71c5450b1` (schema-4 stage 1:
  Ret/Throw/Isinst/Stsfld/Leave allowlist + exception-region operations incl. FAULT, repin),
  `dd7d12107` (method-body executor + backward-branch stack-fixpoint validator, 13 contracts incl.
  the leave-runs-finally-not-fault proof), `03849de55` (ColumnarIteratorPlanner decision layer),
  `d0a4ee530` (MoveNext lowering proven running), `0c0961048` (native iterators project registered
  in ilverify.sh at its 476 ceiling + fall-through fix), `9698fbb76` (array for..in, throw, slot
  reuse), `bb359043f` (enumerator hoisting under the Roslyn try/FAULT region discipline; Dispose
  cascade), `d3602cfa4` (generic iterators via self-instantiation TypeSpec rebinding + MVAR-leak
  guard), `edfcbeb66` (instance iterators: <>__this capture, member reads, user-type sequence
  elements, member-call for..in sources incl. recursion), `f1c1b3b9f` (consumer surface:
  interpolation multi-arg call holes, plan-pinned generic String.Join<Int32>, open-generic
  extension inference — all N#, zero C# growth).
  - NEW SURFACE, not a migration: no C# iterator emitter ever existed (the C# recursive-descent
    func*/yield parser/analyzer stays as the LSP-fallback/oracle owned by 016/017; the analyzer
    already validated func* correctly). The "delete the C# owner" premise did not apply; the
    deletion contract is satisfied by the planner-owned decline sites replacing the blanket
    emit.statement.yield-unsupported arm and by zero net C# decision growth (emitter hosts
    mechanically at 21,619 of the immutable 21,723 ceiling).
  - Added N# owners: parser kernels (func* scan/signature/method-scan + yield statements),
    ColumnarCodePlan/Executor schema-4 method bodies, ColumnarIteratorPlanner (shape facts, state
    numbering, field layout, member/override specs, MoveNext/member/factory plans, decline
    classification), interpolation splitter multi-arg holes, plan-pinned generic external calls,
    open-generic extension-method inference.
  - Evidence: examples/09-linq-and-collections/Iterators.nl builds through the columnar pipeline,
    runs byte-exact across all nine sections, and ILVerifies (all six assemblies); native
    tests/native/iterators 21/21 executed proofs (sequences, infinite+break, re-enumeration
    clones, lazy throw, recursive tree traversal 1,2,4,5,3,6, generic value+reference elements,
    LINQ chain); 690/690 BootstrapServices contracts; 3,182/3,182 units; ownership audit 18/18;
    FULL VS Code-ENABLED GATE: exactly one failure group remains (AsyncStreams, owned by 014) —
    the Iterators group is CLEARED; VS Code smoke tests (extension, diagnostics, hover,
    completion) pass; extension rebuilt+reinstalled via reload-vscode-extension.sh. OUTSTANDING:
    the computer-use visual IDE spot-check was not performed this session (screen-control access
    denied at the approval dialog); the gate's automated VS Code integration evidence stands in.
    Perform the visual check at the next IDE-affecting acceptance (014).
  - Fenced 015 residuals recorded: lambda-taking LINQ arms (TryEmitEnumerableExtensionCall,
    TryEmitLambdaLiteral), the interpolation hole/emission core, the C# generic String.Join arm
    for non-int/string elements, extension interface-receiver inference, preflight typing of
    legacy-owned static calls.

- Task 012 — readonly-field initialization placement; commit recorded in git ("Own readonly-field
  initialization placement in N#").
  - Deleted C# owners: the initialized-fields decision, unconditional helper synthesis, whole-body
    helper emission, and the inline default-ctor body decision — the N# plan is the sole placement
    authority.
  - Added N# owners: `ColumnarFieldInitPlanner` — initonly stores inline in every base-reaching
    constructor, mutable stores in a helper synthesized only when needed, static ownership
    untouched.
  - Evidence: RecordsAndInterfaces builds, runs, ILVerifies clean; estate-wide ILVerify 0 findings
    (empty baseline); the gate's IL-verification step now PASSES — the gate is down to TWO groups
    (013 Iterators, 014 AsyncStreams). New readonly-init project 18/18; 625 contracts; 3,182/3,182
    units; fresh Release self-emit clean.

- Task 011 — record-with lowering for value receivers; commit `8a90bcd92`.
  - Deleted C# owners: the case-52 arm's clone-always callvirt selection, receiver gate, per-field
    binding, and result-type decision, plus the value-record `<Clone>$` synthesis branch (record
    structs now carry no Clone, matching C#). The arm is mechanical over the N# plan.
  - Added N# owners: `ColumnarRecordWithPlanner` — clone/copy strategy (reference clone versus
    verifiable value copy through an addressed temp), receiver shape, ordered member resolution,
    readonly decline, exact call form, result type.
  - Evidence: RecordStructs builds, runs correctly, ILVerifies clean (delta −2 findings);
    whole-estate ILVerify over 91 assemblies leaves only the task-012 InitOnly finding; new
    record-with product project 12/12 registered in the ilverify gate; 625 contracts; 3,182/3,182
    units; fresh Release self-emit clean; gate steady at three groups.

- Task 010 — lambda definition placement and visibility; slice commit recorded
  in git ("Own lambda definition placement in N#").
  - Deleted C# owners: the non-capturing lambda placement decisions — visibility attribute
    literals, name+counter construction, synthesized-signature guards, value-type/ctor guard,
    type-parameter ownership decision, static-versus-this classification branching, and the dual
    sub-emitter constructions (unified). `ColumnarIlEmitter.cs` 21,164 → 21,150. The value-capture
    display-class path is a precisely-fenced residual pending ModuleBuilder/DefineType modeling.
  - Added N# owners: `ColumnarLambdaPlacementPlanner` — owning-type selection, generated method
    identity, exact visibility (assembly-static for verifiable cross-type ldftn), signature
    validation, and the physical DefineMethod, consumed mechanically by the emitter.
  - Evidence: byte-identical IL across all three product reproducers (which run correctly and
    ILVerify clean; the historical cross-type MethodAccess shapes are confirmed fixed); new
    lambda-placement product project 9/9 registered in the ilverify gate; 625 BootstrapServices
    contracts; 3,182/3,182 units; fresh Release self-emit clean; gate steady at three groups
    (013/014 iterators, 011/012 ilverify).

After each accepted slice, record only:

- task and concrete sub-slice;
- commit hash;
- exact C# owner/assertion deletion;
- N# production/test delta;
- focused, product, IL, IDE, and repin evidence as applicable;
- next queue cursor.
