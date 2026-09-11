# diag-honesty — decode notes and open forks (handoff)

Worktree `/private/tmp/nsharp-agent-wt/diag-honesty`, branch `stream/diag-honesty`.
Slices 1–7 are merged into `systems-language`; slice 8 is on this branch.

## Slice 8 (NL002) — what landed and what is still owed

LANDED: `LinterMissingImport.Message` is now `'X' is used without the import that provides it`
(was `I can't find 'X' — it looks like a missing import`). Suggestion unchanged. Pins moved in
`LinterMissingImport.tests.nl`, `DiagnosticGoldenSuite.tests.nl`, `playground-diagnostic-spans`,
`tests/fixtures/diagnostics/top25.golden.txt`, the terminal screenshot, `NL002.md` and `NL201.md`.
Contracts: 1 estate block + 6 blocks in `tests/native/diagnostic-honesty` (32 total).

STILL OWED: the §4 row in `systems-language-closeout/STATUS.md` (not written — see the row draft
below), and a fresh `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` gate.

## The measurement that decided slice 8

Run with `dotnet_diagnostic.NL002.severity = none` in the probe project's `.editorconfig`:

- BUILDS AND RUNS with NO import: `StringBuilder`, `Task`, `CancellationToken`, `List<int>`,
  `Dictionary<string, int>`, `HashSet<int>`, `Stack<int>`, `Stream`.
- FAILS at emit: `Regex`, `HttpClient`, `Queue<int>`, `LinkedList<int>`, `File`, `JsonSerializer`,
  `Encoding` — and FAILS IDENTICALLY WITH THE IMPORT. The columnar backend cannot lower those
  types; the failure was never the import's.
- `Stack<int>` builds and `Queue<int>` does not, from the same namespace.

So NOT ONE of the 25 rows is a resolution failure: NL002 is import hygiene and its old sentence was
false for every row. That is the whole basis for the new sentence.

## Reverted before it shipped (do not re-take without reading this)

A first cut of slice 8 extracted the two name->namespace tables into a neutral
`ImportNamespaceTable` owner and had `AnalyzerDiagnostics.UnresolvedTypeSuggestion` name the import
for any table row that failed to resolve. MEASURED: `List` written with no type argument reports
NL201 *whether or not* `System.Collections.Generic` is imported, so that suggestion would have been
a fix that does not fix it — the exact defect class this chip removes. Both the analyzer change and
the extraction were reverted; the fact is contracted in `diagnostic-honesty`
("a bare generic name reports NL201 WITH the import as well as without").

## Open forks (owner decisions, with recommendations)

1. **NL002's whitelist.** It cannot be completed as a list of NAMES. The complete shape is to probe
   NAMESPACES instead: for a bare name, try `Type.GetType` across the namespace list the product
   already publishes (`AnalyzerImports.BuildAssemblyMappings`), caching results. That turns 25 names
   into ~30 namespaces covering thousands of types. NOT TAKEN, deliberately: the measurement above
   shows the import is never required for resolution, so a widened rule would be pure style
   enforcement at Error severity, newly blocking builds across the estate. Recommendation: decide
   NL002's SEVERITY first (a hygiene rule that fails a build the compiler would otherwise accept),
   then widen.

2. **NL003 vs the analyzer's half (slice 7).** The two owners now partition the shape via
   `NullComparisonFacts` — the linter claims literal operands, the analyzer claims typed names and
   reports NL202 with NL003's sentence. Recommendation: eventually RETIRE NL003 into the analyzer
   rule (one code, one page, one owner). The deciding evidence is that the SDK build path does not
   lint at all, so the literal half is silent there while the analyzer half is not. Not taken here
   because it is a catalog retirement (census pins, page deletion, `.editorconfig` severity knob).

3. **NL011 comment-only catch.** Fixed as a text change: every option the suggestion names now
   clears the rule. The alternative — honouring a comment-only catch as deliberate, as PMD and
   ESLint optionally do — was NOT taken: it needs trivia the linter does not walk, and it would
   create a second, un-machine-checkable opt-out beside `// nlc:ignore NL011`. The shipped page
   already argued "a comment is not enough", so the text came to the page.

4. **NL702's alias-qualified CALL.** `Alias.Format(v)` stops at NL103
   `emit.call.static-member-unmodeled` while an alias-qualified TYPE (`Alias.Tag`, `new Alias.Tag()`)
   compiles. Slice 3 routed around it by making the suggestion kind-dependent. The door slice that
   admits an alias-qualified call would let the function arm go back to the alias.

## Walls hit while writing contracts (all routed around, for §2.1)

- A parameter named `operator` declines its whole declaration (NL103 `parse.function`).
- Locals named `file` and `with` are reserved; the parser DOES name the token and the line for these
  (a good message), unlike the declaration-level declines.
- `new string[]{...}` declines at `parse.function` — the very spelling slice 3 stopped suggesting;
  `[...]` is the way.
- A `new` with call-result arguments declines both as a call argument and as a local initializer;
  route through a free function or a statement instead.
- `nlc build` refuses `--text`; only `check` takes it.

## §4 row draft (not yet written into STATUS.md)

| slice | commit | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| diag-honesty 1-8 | `9b53bf5d6` 1 · `177bc7343` 2 · `6feec3136` 3 · `a0cf3ce6e` 4 · `c63f2079f` 5 · `610f87e44` 6 · `7a30bc5a2` 7 · this branch 8 | the eight product defects the error-docs arc surfaced by running every published example: the `<error>` cascade suppressed at all four diagnostic doors; NL701's inverted hint; NL321's and NL702's uncompilable suggestions; NL001/NL012 counting a write as a use; NL010 blind to `catch` types; NL011 suggesting a comment; the null-check-on-a-value-typed-name emit decline; NL002's false "I can't find it" | A DIAGNOSTIC IS ONLY AS TRUE AS THE RUN BEHIND IT — five of the eight were fixed by measuring what the compiler ACTUALLY does and finding the message said the opposite: the import rule is file-relative not root-relative, `new T[] { ... }` does not compile, an alias-qualified CALL does not compile, a comment does not clear NL011, and every row of NL002's table resolves without its import. Two contracts had PINNED holes (`EqualityOperator_SupportedOperands_AreValid` pinned `int != null` as valid; `playground-diagnostic-spans` pinned 17 `<error>` rows) | probe `func Add(a: int, 5: int)` 30 diagnostics -> 11; estate 7,517 -> 7,631; NEW `tests/native/diagnostic-honesty` 32 blocks (the 74th native project, corpus pin 73 -> 74); 46/46 native projects green; unit 593/593; ZERO C# added; ownership audit 18/18 with both keys unmoved throughout |
