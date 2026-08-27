# Testing

## Test Suite

**Total Tests:** Do not hard-code counts here. Run `dotnet test tests/Tests.csproj` for the current unit count and `./scripts/test-all.sh` for the full product gate.

## Test Organization

### By Component
- Lexer coverage
- Parser coverage
- Analyzer coverage
- Integration coverage

### Test Files
```
tests/
├── IntegrationTests.cs          - End-to-end pipeline tests
├── LanguageServerTests.cs       - LSP handler tests (completion, hover, definition, rename)
└── CodeIntelligenceTests.cs     - the one culture-walled OutputFormatter case (see below)
```

**PARSING has no C# assertion layer either, as of task 020 slice 22.** `tests/ParserTests.cs` is
DELETED: its 212 `[Fact]`s and 6,130 lines migrated to the BootstrapServices estate over six tranches
— the 50 DECLARATION cases in slice 17, the 23 STATEMENT + test-DSL cases in slice 18, the 46
PATTERN / parameter-modifier / operator-overload / constructor-initializer cases in slice 19, the 33
FILE-HEADER / literal and interpolation / attribute / preprocessor cases in slice 20, the 30
CALL-AND-ACCESS cases in slice 21, and the last 30 (keyword and primary expressions, lambdas, type
references, operators) in slice 22, which also took both private helpers and the file itself. The
whole error half had already moved in slice 16. The canonical contracts now live in
`ColumnarParserAst.tests.nl` plus the six tranche files beside it. See `memory/components/parser.md`.

**AST POSITION FINDING has no C# assertion layer either, as of task 020 slice 23.**
`tests/AstNodeFinderTests.cs` is DELETED and its five `[Fact]`s were SPLIT by subject, because
`src/NSharpLang.Compiler/AstNodeFinder.cs` was a fifteen-line shim whose whole body was
`AstNodeFinderCore.FindExpressionAtPosition(...) as Expression` — that shim is itself DELETED as of
task 021 slice 4, and its two LSP consumers now call `AstNodeFinderCore` directly, spelling the
`as Expression` narrowing at the call site. The finder half — 21 of the file's
30 decoded claim rows — is `AstNodeFinderCore.tests.nl` in the estate, where each of the five
fixtures is swept COLUMN BY COLUMN across its cursor line and the answers pinned run-length encoded,
so the boundary columns are stated rather than implied. The analyzer half — the 9 rows about
`Analyzer`, `SemanticModel` and `ClassTypeInfo` — is `tests/native/analyzer-identifier-binding`,
because `Analyzer` is C# in `Compiler.dll`.

**THE `on` / `off` EVENT-SUBSCRIPTION SYNTAX AND ITS DIAGNOSTICS have no C# assertion layer either,
as of task 020 slice 24.** `tests/EventSubscriptionTests.cs` is DELETED and its ten `[Fact]`s split
5 / 5 by subject, the second file this arc has split across both estates. The PARSE half — 49 of the
file's 55 decoded claim rows — is `ColumnarParserEventSubscription.tests.nl` in the estate, as WHOLE
TREE goldens, so every anchor the deleted assertions never stated is pinned: the `on` keyword the
subscription and its statement share, the DOT the event target anchors on, the `(` and `{` of the
handler. The ANALYSIS half — the 6 rows out of `Analyzer.Analyze` — is
`tests/native/analyzer-event-subscription`, and it states the WHOLE diagnostic census rather than one
code: **both rejecting fixtures report TWO errors, not one**, because `Assert.Single(errors, e =>
e.Code == X)` is silent about every row carrying another code. The second row is an `NL203` on the
handler's first lambda parameter.

**THE BINDING MAP — go-to-definition and find-all-references — has no C# assertion layer either, as
of the same slice.** `tests/AnalyzerBindingMapTests.cs` is DELETED WHOLE into
`tests/native/analyzer-binding-map`: all twelve of its `[Fact]`s needed `Analyzer` to populate the
map, so there is no estate half. Its eighteen cursor columns were runtime `FindColumn(...)`
computations and were decoded by pasting the twelve fixtures AND that helper into a generated C#
program. **The whole usage LIST is now pinned, and that mattered**: the deleted
`Assert.True(usages.Count >= 2)` was hiding a reference set of five in which three entries are the
same position.

**ERROR HANDLING — MALFORMED SOURCE, RECOVERY AND THE DIAGNOSTICS OVER IT — has no C# assertion
layer either, as of task 020 slice 25.** `tests/ErrorHandlingTests.cs` is DELETED and its 39
`[Fact]`s split 24 / 15 by subject, the third file this arc has split. **The subject test does not
follow the method NAMES**: three methods called `Parser_*` assert only over `AnalysisResult` and are
in the analyzer half. The PARSE half — 29 of the file's 57 decoded claim rows — is
`ColumnarParserErrorHandling.tests.nl` in the estate, as WHOLE-TREE goldens. **This is the first
tranche whose clean-parse pin is NON-EMPTY by design**: 13 of the 24 fixtures report 17 diagnostics
between them, every one named by code, line, column and length AND pinned whole through `PeRow`, and
the other 11 pin an EMPTY census — four of them fixtures whose names say the parser should be
complaining. The ANALYSIS half is `tests/native/analyzer-error-handling`, which also drives the
LINTER, because one deleted method drove both owners over one fixture and the PAIRING is the content.

**What the deleted file could not see, and why the split earns itself:** 21 of the 24 parse methods
asserted `Assert.NotNull(unit)` and NOTHING ELSE, so a parser returning an empty unit for all 21
passed all 21 — and one fixture (an unterminated `/* … */`) really does return an empty unit, and
reports no diagnostic about it. On the analysis side, `Assert.Contains(result.Errors, e =>
(int)e.Code >= 200 && (int)e.Code < 300)` is a claim about a NUMERIC RANGE that is silent about every
other row; two fixtures report more rows than the assertion named, and in both the extra rows are
`NL301` on the word `var`.

**THE SEMANTIC MODEL — both what analysis PUTS INTO it and the nominal source facts it records — has
no C# assertion layer at all as of task 020 slice 27, and `tests/AnalyzerSemanticModelTests.cs` IS
DELETED.** The file was 1,361 lines and the ~700-line budget could not hold it in one slice, so it
SPLIT ACROSS SLICES rather than across estates: **all 51 of its `[Fact]`s construct `new Analyzer()`,
so there was no estate half at all.** Slice 26 took the 33 that read the model through
`LookupIdentifier`, `LookupIdentifierAtPosition`, `LookupTypeAtPosition`,
`LookupTypeReferenceAtPosition`, `GetVisibleVariablesAtPosition`, `GetTypeMembers`, `Fields`,
`Properties`, `Scopes` and `ExpressionTypes` into `tests/native/analyzer-semantic-model`; slice 27
took the remaining 18 into the SAME project rather than a new sibling — same subject, same fixtures
territory, same `Analyze(unit, "test.nl", null, source)` entry point — so the native project count
did not grow. **The name split would have been wrong on seventeen of eighteen**: sixteen methods
named `Analyzer_NominalTypes_*` make no nominal-type claim at all and read only `result.Errors`,
while `Analyzer_RecordTypes_RecordStructFlagInSemanticModel`, which is not named `NominalTypes_*`,
is one of the two that DO walk the type table.

**Slice 27 also built the TypeInfo WALKER, and it is meant to be reused.** `SmTypeRuntimes`,
`SmTypeInfo`, `SmTypeFacts`, `SmTypeMemberNames`, `SmTypeMemberCount` and `SmTypeMember` read
`SemanticModel.Types[…]` — `ClassTypeInfo` / `StructTypeInfo` / `RecordTypeInfo` /
`InterfaceTypeInfo` and every field of their `DeclaredMembers` — through the same reflective member
walk the rest of the project uses, and render each census so it decodes field by field rather than
by substring search: a `TypeReference` is `ClrTypeName(ToString())`, a list is `[a,b]` so its LENGTH
is a count claim, a primary-constructor parameter is `name:ref@line:column`, and a generic
constraint is `typeParameter:specialConstraints:[constraints]`. **`<null>` and `<absent>` are
different answers and are never conflated** — `BaseClass` is `<null>` on a base-less class and
`<absent>` on a struct, which does not declare the member. The `AnalyzerTests.cs` campaign's
clean-only tranche should take this surface as it stands. Its full documentation is the header of
`tests/native/analyzer-semantic-model/AnalyzerSemanticModel.tests.nl`.

**What the deleted second half could not see:** the type table holds TWENTY types where the deleted
monster named eighteen through `Assert.IsType` — `Base` and `Marker`, the two types every other
declaration points at, were never mentioned; a `sealed class` anchors at the `class` KEYWORD (column
8) while a `duck interface` anchors at `duck` (column 1), so modifiers are skipped in one case and
not the other; `TypeMembers` and `DeclaredMembers` are DIFFERENT tables with different population
rules — a fixture declaring twenty types with thirteen members between them leaves ONE row in
`TypeMembers`; ten of the sixteen diagnostic fixtures report exactly one diagnostic and the other
six report NONE, so every `Assert.DoesNotContain` in the file was satisfied by an empty or
single-row list; and **two fixtures produce an `NL202` whose entire message is the bare words `Type
mismatch` with a NULL suggestion**, the least helpful diagnostic in the cluster and one no assertion
in the deleted file could see. Two `using`-pattern rejections that differ in shape report a message
that is equal BYTE FOR BYTE, and the static and instance readonly assignments report the same
`NL309` at the same 7:13 with different sentences — pairs no substring match could have compared.

**ASSIGNABILITY AND FLOW NARROWING — the first twelve regions of the former `tests/AnalyzerTests.cs` — have no
C# assertion layer either, as of task 020 slice 28.** That file is the campaign's last big cluster:
13,451 lines, 781 `[Fact]` + 35 `[Theory]`, ONE subject (every body funnels through a private
`Analyze(source, config)` that calls `ParseFileAst(source, null)`, `new Analyzer()`,
`LoadSystemAssemblies()` and the single-argument `Analyze(unit)`), so it is a WHOLE-FILE NATIVE move
with no estate half at all — cut into tranches rather than estates. **Slice 28 took tranche 1a: the
file's first TWELVE `#region`s, 109 `[Fact]`s and 1,584 lines, into `tests/native/analyzer-clean-source`.**

Three rules that campaign confirmed, and one it corrected:
- **The tranche is not the contiguous span.** Three un-regioned `ReflectionGenericReceiver_*` methods
  sit between region 2 and region 3 and read `result.SemanticModel.LookupIdentifier`, a surface the
  new project has no kernel for. They stayed behind, so the deletion is TWO spans. Classify by what
  the body NAMES, never by where it sits.
- **The instrument is COPIED, not shared.** `Ac*` is `analyzer-error-handling`'s `Eh*` plus
  `analyzer-semantic-model`'s count pair, renamed. Two things are new: `AcHint` (the `ContextualHint`
  field), and the NULL file name in the parse — the deleted helper passed `null` where slice 25's
  passed `"test.nl"`.
- **`[Theory]` is 0 in all 19 regions.** All 35 theories and all 100 `InlineData` rows are
  un-regioned, so `nlc test`'s table-driven syntax — which compiles in `tests/native` and not in the
  estate — still has NO consumer. Its first one is a later tranche.
- **The campaign sketch was corrected by measurement, as every campaign's has been**: 19 regions, not
  20; 53 in-body `Assert.`, not 55; 2,241 declaration lines where the sketch's 2,740 was the region
  SPAN; and NINE private assertion helpers where the sketch named four.

**What the deleted 109 could not see:** `AssertNoErrors` asserted one boolean (`HasErrors == false`)
and 75 of the 109 bodies contained nothing else, so nothing stated how many rows there were or what
they said — all 86 silent fixtures now pin an EMPTY census, a zero count and a `<no-such-error>`
sentinel, and all 109 pin an EMPTY PARSE census the deleted helper discarded outright. **The
rejected-lambda `NL202` says a value is not assignable to its own type** — `Variable 'f' is typed as
'NSharpLang.Compiler.FunctionTypeInfo', but the value is 'NSharpLang.Compiler.FunctionTypeInfo'` —
and that fixture reports TWO rows where the deleted method asked about one. A code NAMED
`NullabilityWarning` is reported at `Error` severity, twice. `null` assigns to a non-nullable
`string` and to a non-nullable class in SILENCE while `null` to `int` is rejected, so the annotation
is enforced at the DEREFERENCE and not at the assignment — both halves pinned on adjacent fixtures.
And no method in the tranche stated a line or a column: `NL202` anchors on the declared NAME,
`NL905` on the RECEIVER, `NL907` on the `must` keyword and on `Value` with the dot outside the
underline, `NL501` on `match`, and `NL412` on the callee NAME with the parentheses excluded — which
**corrects slice 25's record**, where the same code's 13-column span was read as "the whole call
including its parentheses" when 13 is the length of the name alone.

**TRANCHE 1b — the SEVEN REMAINING `#region`s — followed in slice 29, and after it
the former `tests/AnalyzerTests.cs` had NO `#region` left.** 82 `[Fact]`s, 1,193 C# lines and 22 `Assert.`
occurrences, extending `tests/native/analyzer-clean-source` rather than adding a sibling (same
subject, same fixtures territory, same entry point), so the native project count stays 39. The
regions are generic constraint validation, string-to-enum rejection, overload betterness, type-system
edge cases, impossible patterns, numeric narrowing cast suggestions and `default`/`new()` expressions.

**Its headline is that `Analyze(unit)` and `Analyze(unit, path, root, source)` ARE DIFFERENT ANSWERS,
and production calls the one 73 of the 82 deleted assertions never drove.** A repository-wide sweep
finds exactly TWO production call sites and both pass all four arguments —
`MultiFileCompiler.cs:282` (the compiler) and `DocumentManager.cs:277` (the IDE); the one-argument
overload has ZERO production callers. `AssertNoErrors`, `AssertHasError`, `AssertHasStrictError` and
`AssertNoWarning` all pass one. (`AssertHasError` is gone as of slice 32, which measured the cost of
that: 32 of its 79 message claims are false on the route production actually takes.) Over these 82
fixtures the two entry points
agree on every CODE and disagree otherwise: **22 of the 33 reporting fixtures get a different COLUMN
or LENGTH** (the plain route anchors `NL202` on the declared NAME one column wide, the production route
on the VALUE and underlines all of it; `NL506` is `is` two columns plain and `is string` nine rich);
**15 get a different MESSAGE, and the production one is WORSE** — `Variable 'c' is typed as 'Color',
but the value is 'string'` collapses to the bare `Type mismatch` and its suggestion is DROPPED to
null, with a `ContextualHint` added in its place. `ContextualHint` is non-null on 15 fixtures rich and
ZERO plain, which is why slice 28 saw `<null>` twenty-four times: the field is a property of the ENTRY
POINT, not of the fixture. `SourceSnippet` is non-null on all 33 reporting fixtures rich and ZERO
plain. Every tranche-1b contract states BOTH routes.

**THREE FIXTURES DO NOT PARSE AND TWO OF THEM MADE A VACUOUS CLAIM.** A bodiless positional record —
`record Person(Name: string, Age: int)` — is a PARSE ERROR in N#: `NL102 Expected '{'` plus `NL106
Missing closing '}'`, and the rest of the file is swallowed. Two of the three fixtures that spell one
are `AssertNoErrors` methods, so their `HasErrors == false` held only because the analyzer never saw
the declaration they were written to test. Slice 28's tranche had no false-clean fixture; this one has
two, and only the pinned parse census could find them.

Three more rules this tranche settled:
- **The un-regioned method rule cuts BOTH ways.** `SetupSymbols_VisibleInTestBodies` sits between two
  regions and names `AssertNoErrors` — the tranche's own shape — so it is IN, and the deletion is ONE
  contiguous span. Slice 28's three un-regioned methods named a surface with no kernel and stayed out.
  The rule is the same: classify by what the body NAMES.
- **`AssertHasStrictError` is not strict mode.** Its body is the same no-config `Analyze(source)`; the
  name describes a severity-filtered CLAIM. Zero of the 82 bodies names a `ProjectConfig`.
- **The file name is inert.** `ParseFileAst(source, null)` and `ParseFileAst(source, "test.nl")` return
  the same census and the same `Success` on all 82 fixtures, pinned in both spellings on every one.

**TRANCHE 2 — the ERROR-CODE ASSERTION FAMILY — followed in slice 30, and after it both
`AssertHasErrorCode` and `AssertNoErrorCode` are gone.** 106 methods (105 `[Fact]` + the campaign's
FIRST migrated `[Theory]`), 1,743 C# lines, 85 in-body `Assert.` occurrences and 199 decoded claim
rows, extending `tests/native/analyzer-clean-source` again, so the native project count stays 39.
The boundary is by SHAPE, not by name or region: the 88 methods that named either helper, plus the
18 direct-`Analyze` methods that read an `ErrorCode` and sit interleaved among their deletion runs
from line 9460 to the end of the file — which collapses ten runs into eight and migrates the
generic-arity subject and the WHOLE NL319 subject rather than splitting them.

**The one missing kernel was an error-CODE census read.** Both helpers select
`e.Code == code && e.Severity == ErrorSeverity.Error`, and the presence half RETURNS the matching
row; `AcCodeMatchIndex` is that selection and `AcCodeErrorCount` / `AcCodeRow` / `AcCodeAnchor` are
what it answers. `AcSuggestions` reads the PLURAL `Suggestions` list, which no contract in the arc
had touched.

**Six things the 199 deleted claims could not see:** (1) **the severity half of both helpers is
dead over this corpus** — all 82 diagnostics the 111 fixtures produce are `Error`, so slice 28's
severity-blind `AcCodeCount` and the new filtered `AcCodeErrorCount` agree on every fixture and every
code; both are pinned so the day one arrives as a Warning they separate; (2) **34 of the 35
`AssertNoErrorCode` fixtures analyse COMPLETELY SILENT**, so "this code is absent" was almost always
"every code is absent"; (3) **the one that is not silent is a FALSE CLEAN** —
`EnumValueObjectMemberAccess_Resolves` reports `NL202:TypeMismatch@10:17+1` and the deleted assertion
asked only about `UndefinedMember`; (4) **two fixtures do not parse** — a C# `switch`/`case`
statement (`NL102`, and the analysis then reports NOTHING, so its `AssertNoErrorCode` proved nothing
at all) and an enum whose members are newline- rather than comma-separated (`NL101` twice; its NL320
claim survives, but the analysis reports FOUR rows, two of them `NL903` complaining about an
identifier literally named `<error>`); (5) **`VisibilityConventionWarning` is reported at `Error`
severity**, the same shape slice 28 found in `NullabilityWarning`; (6) **the plural `Suggestions`
list is a production-only field** — null on all 82 plain rows, non-null on 5 rich ones — so the
`error.Suggestion ?? string.Join(", ", error.Suggestions ?? …)` fallback the deleted code carried was
unreachable on the route the deleted code used.

**The two-entry-point divergence reproduces on a disjoint corpus and in the same direction**: census
differs on 16 fixtures, code row on 28, code anchor on 13, error COUNT on none; production DROPS the
suggestion 15 times and gains one zero times; 37 of 82 rich rows carry a `ContextualHint` the plain
route leaves null. **Three deleted assertions are true ONLY of the entry point nothing ships** — the
`'Items' is typed as 'List<Pt>', but the value is 'List<Rs>'` sentence and its two siblings collapse
to the bare `Type mismatch` on the production route.

**THE FIRST `[Theory]` LEFT THE FILE, AND THE PER-ROW PIN IMMEDIATELY FOUND A DEFECT.**
`GenericTypes_StaticMembers_ReportBeforeEmission` is a table here rather than three declarations
because BOTH its fixture and its message claim are interpolated per row, and all four C# parameters
stay load-bearing in the N# body. `nlc test` counts its three rows as three tests, so the unit suite
loses 108 cases (105 `[Fact]` + 3) and the native project gains 106 declarations that run as 108.
The three rows do NOT anchor alike: `field count` underlines `count` and `property value` underlines
`value`, but **`method mk` underlines `fu`** — column 12, length 2: the column of the `func` keyword
with the length of the member name. `nlc test`'s table syntax already had a `[Theory]` consumer in
`tests/native/parser-literal-facts`; what is new is that this is the first of `AnalyzerTests.cs`'s
35, and that per-row identity earned its keep on the first try.

**TRANCHE 3 — the WHOLE remaining direct-`Analyze` + `ErrorCode` shape plus the first 56 of the
`AnalyzeWithSource` + `ErrorCode` shape — followed in slice 31, and after it the direct-`Analyze` +
`ErrorCode` shape is at ZERO.** 80 methods (49 `[Fact]` + **31 `[Theory]`s**), 1,349 declaration
lines, 1,599 deleted C# lines, 242 in-body `Assert.` occurrences, 90 `InlineData` rows, 139 fixtures
and 570 decoded claim rows, extending `tests/native/analyzer-clean-source` again (project count
still 39). The `AnalyzeWithSource` prefix is cut at line 3353, the end of the readonly-field
subject. **This is the first tranche in which NO helper dies** — `Analyze` keeps 15 consumers plus
both `Assert*` helpers, `AnalyzeWithSource` keeps 26 plus the 33 beyond the cut — and that was
verified rather than assumed.

**THE TABLE CAPABILITY STOPPED BEING A MILESTONE.** 31 tables in one slice against slice 30's one:
31 of the residue's 34 `[Theory]`s and 90 of its 97 `InlineData` rows. Columns are deduplicated by
per-row VALUE TUPLE — two pins that vary identically share one column — and every C# parameter that
survives only inside a claim is kept load-bearing by rebuilding the deleted substring in the body
(`assert AcRow(rich, 0).Contains("'" + operandType + "'")`). The widest is
`Write_NullConditionalTarget_Error` at twelve rows.

**THE HEADLINE IS AN ANCHOR DEFECT IN THE ONE-ARGUMENT ROUTE, AND IT IS 23 ROWS WIDE.** Every one of
the 139 fixtures was analysed through BOTH entry points. Of the 148 resulting row pairs, **23 differ
in LENGTH and the plain route reports `1` in every single one of the 23** while production reports
the real token width (2, 3, 5, 6, 7). The one-argument overload is handed no source text and so
cannot measure a token; it emits a one-column underline and no caller can tell. Slice 30's anchor
audit had already recorded `NL202` anchors as "TRUNCATED … single letters" — this names the cause.
Seven SUGGESTIONS and three MESSAGES also differ, and `ContextualHint` is non-null on 11 rich rows
and 0 plain ones. Not one of the 242 deleted `Assert.` calls read a line, a column or a length, so
none of it was visible from `AnalyzerTests.cs`.

**FIVE OF THE THIRTEEN ABSENCE CLAIMS WERE VACUOUS, AND A CONTROL PROVES IT.** Three fixtures —
`GenericListOfNSharpType_CountProperty_IsNotMethodGroup`, `StackAlloc_SmallIntLengths_Accepted`,
`StackAlloc_AliasedSmallIntLength_Accepted` — report NOTHING at all. Control V2 rewrites one of
their absence claims to name two DIFFERENT absent codes and the comparator does not move; control V3
does the same edit on a discriminating fixture and loses a row; control V1 strips the empty-census
pin from the three N# contracts and loses five. The other eight absence claims are discriminating.
Unlike tranche 2, **all 139 fixtures parse cleanly** — 139 empty parse censuses, 139 successes — so
every analysis row is provably the analyzer's own.

**The same sentence can have two owners, one per route.** `Method 'X' must be called or passed to a
delegate` lives in `ErrorMessageBuilder.nl` (production route) AND in
`AnalyzerReflectionCallReporter.nl` (plain route); mutating either moves exactly 5 native contracts,
which is what pinning both routes on every fixture buys.

**TRANCHE 4 — the REST of the `AnalyzeWithSource` + `ErrorCode` shape, which goes to ZERO, plus the
WHOLE 79-method `AssertHasError` family — followed in slice 32, and `AssertHasError` died with its
last consumer.** 112 methods (111 `[Fact]` + 1 `[Theory]`), 1,515 declaration lines, 1,689 deleted
C# lines across 53 runs, 254 assert-statement instances, 114 fixtures and 282 decoded claim rows,
extending `tests/native/analyzer-clean-source` again (project count still 39). Both `ErrorCode`
shapes are now at zero and the residue is 327 methods over 4,809 declaration lines.

**THE HEADLINE IS THAT `AssertHasError` PINNED SENTENCES THE SHIPPING COMPILER DOES NOT WRITE.** The
helper reached the ONE-ARGUMENT `Analyze(unit)` overload. Running all 114 fixtures through both
entry points and re-deciding all 282 claims against each: every claim holds on its own method's
route (`0 fail`), and **40 of the 282 are FALSE on the other route** — 32 of them `AssertHasError`
message substrings that production never emits, spread over 32 of the 79 family members. Slice 31
found 2 such rows; this tranche finds 40. **And the plain route does not merely under-measure — it
points somewhere else**: over 126 row pairs, 31 LENGTH differences (all 31 with `plain = 1`, the
third tranche running), **20 COLUMN differences, all 20 with `plain < rich`** — the plain route
anchors on the start of the declaration where production anchors on the offending VALUE — and **one
LINE difference**, `VoidFunctionReturnValue_Error` at 3:17+1 plain against 2:18+9 production, the
plain route blaming the `return` and production blaming the signature with no return type. Codes,
severities and row counts agree everywhere: the routes always agree on WHAT and HOW MANY and
disagree about WHERE and WHAT IT SAYS.

**EIGHT OF THE NINE ABSENCE CLAIMS WERE VACUOUS — the worst ratio the campaign has measured.** Eight
fixtures report NOTHING AT ALL on either route, and control V2 renames five of their absence claims
to a DIFFERENT absent code without moving the comparator; V3 makes the same edit on the one
discriminating claim and loses a row; V1 strips the empty-census and zero-count pins from the eight
N# contracts and loses eight.

**TWO INSTRUMENT DEFECTS WERE FOUND IN THE DECODER BEFORE ANY NUMBER WAS TRUSTED.** Anchoring the
attribute finder with `^(\s*)\[` lets `\s` eat the preceding NEWLINE, so every method preceded by a
blank line is measured one line early — it made the residue read 7,207 declaration lines instead of
6,324. And blanking comments by looking for `//` in non-code text destroys a `//` that is TEXT
inside a raw string literal, swallowing a whole method body. Use `[ \t]*`, and identify comments
from the scanner rather than by re-scanning for the delimiter.

**AND THE `Code|Message|Suggestion|Severity` PIN ENCODING IS AMBIGUOUS.** `AcRow` joins the four
fields with a bare `|`, and the anonymous-union sentence CONTAINS one (`int | string`), so a
left-to-right split mis-reads it. Code is the first field and Severity the last; no suggestion in
the corpus carries a `|` (measured: 0 of 252 rows), so the message is everything between the first
field and the last two.

**Why the estate half is EMPTY here is itself a measurement.** `SemanticModel.nl` IS N# in the
estate and `SemanticModel.tests.nl` already owns its ALGEBRA — it constructs a model directly,
hand-records entries and pins the lookup ranking, the scope-depth rule and the inclusive bounds.
What no estate contract can reach is the POPULATION. The mutation panel measures the gap: removing
the FUNCTION rank from `LookupIdentifier` moves 3 estate contracts AND 1 native one, while deleting
the CALL-SITE `RecordExpressionType` in `Analyzer.cs` — C# inside `Compiler.dll` — moves **0 of the
6,316 estate contracts and 1 in the new native project.**

**What the deleted assertions could not see:** three of the 33 fixtures are BYTE-IDENTICAL
duplicates (33 methods, 30 distinct sources); four "clean" fixtures report diagnostics nobody asked
about (`NL903` on a leading-underscore field, `NL316` on a shadow); a function does not look up as
itself (the `Functions` table holds a `FunctionTypeInfo` whose `ToString()` is its CLR NAME, and the
LOOKUP answers the RETURN type); the flat tables COLLIDE across scopes, which is why the position
tables exist; every scope's end column is `int.MaxValue` and no scope ever ends on the fixture's own
last line; the analyzer opens **twelve scopes for two lambdas** in one LINQ chain; and
`GetVisibleVariablesAtPosition` answers FUNCTIONS as well as variables — which the perturbation
panel found by REFUSING a control whose anchor occurred zero times.

**Two emit walls were measured by bisection while writing it, and both are general.** A LOCAL whose
type is `System.Collections.IDictionary` or `System.Collections.IEnumerable` is declined at
`emit.local.unsupported-type`; an `IList` local is accepted, but a `Dictionary<,>` is not an `IList`,
so a dictionary is walked through its enumerator BY REFLECTION into an `object?[]`. And a function
whose RETURN TYPE is `IList` declines, while an `as IList` local in the same file does not.
Separately, an insertion sort over a `List<string>` whose condition calls `String.Compare` declines
in any file that also carries a reflective member walk — sorting a `string[]` and comparing character
by character emits. **`nlc check` on a `.nl` COPY is how to see any of this**: `nlc test` prints only
the HumanExplanation, with no decline site, and `nlc check` never sees a `.tests.nl`.

**THE PLAYGROUND'S DIAGNOSTIC SPANS have no C# assertion layer as of task 020 slice 37**, and the
capability that slice added is a `dll:` line: `tests/native/playground-diagnostic-spans` is the first
native project to reference `NSharpLang.Playground`, and the gate now builds that project in the same
step it builds the CLI so the dependency is DECLARED rather than a side effect of the unit-test step.
The cut is the 34 bodies of `tests/PlaygroundCompilerTests.cs` that NAME its `AssertPlaygroundSpan`
helper — 30 `[Fact]` + 4 `[Theory]` carrying 25 `InlineData` rows, 1,051 declaration lines, 113
in-body `Assert.`, 71 helper calls, 57 source fixtures, 233 decoded claim rows — and the helper dies
with them because all 71 call sites are inside the cut. The file survives at 35 methods / 745 lines
for the slice that closes it: catalog, completions, run, format, and the check bodies that read a
message rather than a span.

**THE HEADLINE IS THAT THE PARSER'S INTERNAL `<error>` PLACEHOLDER REACHES USERS TWICE OVER, AND THE
DELETED FILE WAS GUARDING AGAINST EXACTLY THAT ON TWO OTHER FIXTURES.** Seventeen pinned rows across
five migrating fixtures carry `<error>` in a MESSAGE or a SUGGESTION — `NL903 Identifier '<error>'
starts with a non-letter character`, `NL012 Parameter '<error>' in 'main' is never read`, `NL201 Type
'<error>' not found`, and two suggestions that tell the user to import `<error>`. **And the leak also
sets the diagnostic's LENGTH**: those spans are `"<error>".Length` = 7 characters wide, so of 316
pinned rows TEN run past the end of their own source line (`NL903` at 3:1+7 on the six-character line
`enum {`, `NL201` at 4:5+7 on the nine-character line `    Name:`). Two deleted methods asserted
`DoesNotContain(… Message.Contains("<error>"))`; nothing looked at the other five, and no deleted
assertion read a length it had not itself supplied.

**The `PlaygroundCompiler` route is REFLECTION-ONLY, and three emit walls were measured by bisection
while writing the kernels.** `Array.CreateInstance` DECLINES the moment its result is bound to a
LOCAL — it emits only as a RETURN VALUE — so the constructed `PlaygroundFile[]` is passed around as
`object` and its elements are written through a REFLECTED `Array.SetValue` rather than an indexer;
`record` and `file` are both reserved in local-binding position; and `typeof(IEnumerable<>)` is
rejected by the parser, so the `CheckProject` overload is found by NAME rather than by parameter
types. The models themselves are already N# — `PlaygroundFile`, `PlaygroundCheckResponse`,
`PlaygroundDiagnostic` and `PlaygroundSummary` live in `PlaygroundModels.nl`; only
`PlaygroundCompiler` and `PlaygroundRunner` are still C#.

**TASK 021 SLICE 11 SPLIT `PlaygroundRunner.cs` IN TWO AND MOVED THE HALF THAT DECIDES.** Its
execution MECHANISM — the tree walk, the scope chain, the runtime value model — stays C# and is a
`(b)`-bucket subject whose retirement is a Playground task (run emitted IL in the browser), because
a browser tab has no process to spawn and no `Reflection.Emit`. Everything it DECIDES now lives in
`src/NSharpLang.Compiler.BootstrapServices/PlaygroundRunFacts.nl` (66 `static func`s) and is pinned
by `PlaygroundRunFacts.tests.nl` (18 blocks / 143 asserts): the **37-code `PG201`–`PG237`
vocabulary** with its sentences, the three budgets (20,000 steps / 128 frames / 200 output lines),
the entry-point rule, the reserved names, union-case name matching and splitting, the division and
equality rules, the string-literal escape decoder, and every word the runner prints a value with.
`PlaygroundRunner.cs` went **966 → 939 lines** and its literal census **81 lines / 131 sites / 117
distinct → 13 / 13 / 12**; the 13 survivors are one `'\0'`, one `'.'`-free array suffix `"[]"`, and
the nine BCL member names that are the switch labels of the calls implementing them.

**THE PLAYGROUND AND `nlc run` DISAGREE ON HALF A MEASURED CORPUS, AND THAT IS A PRODUCT QUESTION.**
Fourteen analysis-clean probes driven through the shipped `RunProject` and then built with `nlc run`
diverge on **seven**: int and double division by zero (the runner answers `division by zero` and
exits 1 where the CLR throws or prints `∞`), `0.1 + 0.2 == 0.3` (the runner's `1e-7` tolerance says
true), record and union printing (`Point { X: 1, Y: 2 }` vs `P.Point`), `"n=" + 1` (the runner runs a
program `nlc` declines to emit), and a union pattern's SHORTHAND property binding (`PG208` where
`nlc run` prints the answer). The last one breaks the SHIPPED `04-unions-patterns` example, which
carries a declared `ExpectedOutput` it cannot produce. Both are filed as chips, not absorbed.

**THE WHOLE PLAYGROUND HAS NO C# ASSERTION LAYER AS OF TASK 020 SLICE 38**, which deleted
`tests/PlaygroundCompilerTests.cs` outright — 821 lines, 35 `[Fact]`s, 745 declaration lines, 191
in-body `Assert.` and 194 decoded claim rows — and split them 21 / 14 by what the bodies READ. The 21
that answer `PlaygroundCheckResponse` through `Check(source)` extended
`tests/native/playground-diagnostic-spans`; the 14 that answer the FOUR OTHER response records
(`Catalog`, `Completion`, `Run`, `Format`) went to a NEW sibling
`tests/native/playground-tooling-surfaces`, the 41st native project, because none of the 14 is
span-shaped and one of them EXECUTES the program. `AssertCompletion`, `LineNumberContaining` and
`ColumnAfter` died with their last consumers, and `tests/Tests.csproj` lost its now-dead
`ProjectReference` to `NSharpLang.Playground`.

**Two findings from that slice are product defects, not test facts.** (1) **The browser completion
list offers compiler-generated CLR accessors**: 51 of 339 pinned items are `get_`/`set_`/`add_`/
`remove_` methods — 45 of 92 on `Console.` — and on `System.String` `get_Chars` and `get_Length` are
offered beside the properties `Chars` and `Length`, so one member appears twice under two names.
(2) **The `<error>` placeholder sizes spans past the end of their own line**, again: one character
under `MaxSourceLength` the playground reports `NL101@1:1+65536` plus `NL903@1:65537+7`, where 7 is
`"<error>".Length`. A third finding is about the deleted assertions themselves: the
`DoesNotContain(Code == "PG900")` claim was STRUCTURALLY VACUOUS — `PG900` occurs in exactly one
place in the whole repository, that assertion, while the shipping playground emits `PG001`,
`PG200`–`PG237` and `PG299`.

**Two more emit walls were measured by bisection while writing those kernels, and both are general.**
`new object?[](0)` written INLINE as `MethodBase.Invoke`'s second argument DECLINES at emit — bound
to a local it emits, and the same inline expression handed to an ordinary N# function emits. And a
boxing store into an `object?[]` element declines when the source is an `int`-typed PARAMETER
(`values[index] = value`); routing it through a typed `object` local first emits. That REFINES the
older "a boxed literal into `object?[]` declines" note, which does not reproduce: an int literal and
an int local both pass through an `object?` parameter fine.

**THE EXECUTABLE SYSTEMS PROOF CORPUS HAS NO C# ASSERTION LAYER AS OF TASK 020 SLICE 40**, and the
capability that slice added is a SYNCHRONOUS PROCESS SPAWN KERNEL. `tests/native/systems-proof-corpus`
is the 43rd native project and the first that reaches its subject entirely through spawned CLI
processes — no `dll:` dependency, no reflection. Its 38 blocks replace the single 544-line `[Fact]`
`ExecutableSystemsProofProjects_CheckBuildPerfAndQueryEvidence` in `tests/SystemsNSharpTests.cs`
(212 in-body `Assert.` plus 42 rows inside `AssertSystemsProofBuildDiagnostics` and 12 inside
`AssertNativeImportHasNoManagedBody` — 266 decoded claim rows), and they cover the 21 shipped proof
projects under `docs/design/systems-samples/proofs`: 21 `nlc build --perf-report` blocks, 13
emitted-assembly RUN blocks, 2 `nlc check --systems-report` blocks and 2 `nlc query trusted` blocks.
`SystemsProofBuildResult`, `BuildSystemsProofProjects`, `BuildSystemsProofProject`,
`BuildSystemsProofPerfReportJson`, `AssertSystemsProofBuildDiagnostics`, `StripAnsi` and
`AssertNativeImportHasNoManagedBody` died with their last consumer.

**The route is stronger than the one it replaces, and the decode is why.** The deleted body never
spelled a process API — `Process`, `ProcessStartInfo`, `StandardOutput` and `WaitForExit` occur zero
times in it, and its 11 launches went through the already-N#-owned `DotnetRunner`. Its "real build"
was IN-PROCESS (`new MultiFileCompiler(...).CompileToIlAssembly(...)`), and the perf-report JSON its
25 `JsonDocument.Parse` calls read was assembled by a private helper IN THE TEST FILE, so it pinned
a test-local copy of the CLI's output rather than the CLI's output. Every block now spawns the real
command and pins the shipped envelope. **Nothing is loaded**: emitted assemblies are EXECUTED AS
PROCESSES, which is route (a) of the AOT question in
`project_aot_vs_reflection_kernel_loading` — the `AssemblyLoadContext` the C# used to read
`GetMethodBody()` bought exactly the reflection-loading debt the single-binary end state forbids.

**Two findings from that slice are product facts, not test facts.** (1) **`docs/design/systems-samples/proofs/27-c-library-cli`
cannot execute**: its `[LibraryImport]` over a `ReadOnlySpan<byte>` parameter is not marshalable on
this emit path, so the CLR's interop marshaller raises `MarshalDirectiveException` at
`SystemsProofs.CLibraryCli.NativeHash.Hash64` and the process aborts. The sample compiles clean under
`systems:strict` and the deleted C# never ran it — it only read metadata — so this was invisible for
the file's whole life. It is now PINNED as the successor to the deleted no-managed-body claim, because
only a genuine interop stub can provoke a marshalling failure. (2) **`nlc check --systems-report`
cannot write to stderr**: every `Console.Error` path in `CheckCommand.Execute` is gated on text mode,
which a JSON output mode never enters, so the deleted `Assert.True(string.IsNullOrWhiteSpace(stderr))`
was STRUCTURALLY VACUOUS. It is replaced by a runtime diagnostic census read out of the envelope.

**Two emit walls were measured by bisection while writing it.** `nuget:`-sourced types are
reflection-only on this emit path: with `System.Reflection.Metadata` declared as a dependency the
namespace resolves, but `new PEReader(stream)` declines at `emit.local.initializer`, both
`PEStreamOptions` arities decline identically, and even `(int)PEStreamOptions.PrefetchEntireImage`
declines at `emit.return.expression`. And `foreach` over a `JsonElement.ArrayEnumerator` is refused
by NL202 — the explicit `MoveNext()` / `.Current` walk the estate already uses is the working
spelling.

**`tests/SystemsNSharpTests.cs` IS DELETED AS OF TASK 020 SLICE 41, AND THE SYSTEMS PROFILE HAS NO C#
ASSERTION LAYER AT ALL.** The whole remainder — 60 methods, 1,226 declaration lines, 163 in-body
`Assert.` and 205 decoded claim rows — became two native projects, split by what the bodies READ.
`tests/native/systems-analysis-census` (the 44th) takes the 52 SYSTEMS-ANALYSIS methods and the 4
CLI-IN-PROCESS ones as 58 blocks, and it answers them through a SPAWNED
`nlc check --project … --systems-report` rather than through `MultiFileCompiler.CompileForAnalysis()`:
every mutation the deleted `Analyze` helper made to a `ProjectConfig` has a project.yml spelling
(`language.profile`, `language.systems.mode`, `.stackBudgetBytes`, `.warmup`, `.hotSummaryFiles`,
`.allowHotSidecars`), so the fixture now goes through the YAML parser a user's project goes through,
and the pin is the versioned envelope rather than an in-memory object. It declares NO dependencies
and loads no assembly. `tests/native/systems-gauntlet-facts` (the 45th) takes the ten
`tests/fixtures/systems-gauntlet` cases, the two lifetime-syntax methods and the `Result<T, E>` ABI
method as 13 blocks, because those three families read what no `nlc` surface exposes — return
lifetimes, `scoped` parameters, ref-struct-ness, type-reference text — and two of the ten gauntlet
cases carry exactly those keys. All 109 run-expanded analysis claim rows and all 135 gauntlet claim
rows were evaluated against the new routes BEFORE the migration was written, and all of them hold.

**One product finding came out of it: twenty of the 54 analysis fixtures do not compile clean.** They
carry 22 non-systems ERROR rows the deleted assertions could not see, because those assertions read
only `report.Findings`. Two of the twenty undermine the claim their own method was making —
`SystemsStrict_DisposeCallSatisfiesObviousResourceOwnership` proved that a `Dispose()` call satisfies
NSYS090 while the analyzer reports `NL303: Member 'Dispose' not found on type 'FileStream'`, and
`PoolRent_MustBeReturnedOnObviousLexicalPath` proved the pool rule over a receiver reported as
`NL301: Variable 'ArrayPool' not found`. Every one of those rows is now pinned as a diagnostic census
beside the systems report.

**And the carried stderr-vacuity prediction was HALF right, measured.** `nlc check --systems-report`
truly cannot write to standard error — a project that does not exist at all still answers with an
empty stderr — so that deleted claim was structurally vacuous and is replaced by the diagnostic
census. `nlc query perf` is NOT vacuous: it writes 138 bytes on a missing project and 70 on a
malformed `--pos`, so its silence is kept as a claim.

**Four emit walls were measured by bisection while writing these two projects, all minimised out of
repo.** (1) The two-argument `string.IndexOf(value, startIndex)` DECLINES; the three-argument
`(value, startIndex, StringComparison)` form compiles, which is the spelling
`tests/native/systems-proof-corpus` already uses. (2) EVERY `System.Type` BOOLEAN property —
`IsValueType`, `IsClass`, `IsGenericType`, `IsAbstract` — declines in every spelling tried (returned
directly, bound to a local, or `.ToString()`-chained); `valueType.IsAssignableFrom(ownerType)` is the
working route. (3) A `??`-coalesced RECEIVER (`(owner ?? "").GetType()`) declines, while the same call
on a non-null `object` parameter compiles. (4) An `out` argument on the `Result<T, E>` `TryGet*` pair
declines; `GetMethod(name, [typeof(int).MakeByRefType()])` plus `Invoke` reads the same fact.

**The `nlc` command surface is being taken next, and task 020 slice 42 took the first 35 bodies of
it.** `tests/CliCommandTests.cs` is 5,482 → 4,274 lines and 135 → 100 test methods. The mechanical
decode that opened it OVERTURNED the census slice 41 recorded: the file holds 135 test methods, not
114, and **96** of them are canonical over an N#-owned subject, not 82 — because an instrument that
looks for the string `Kernels` cannot see `TreeCommand`, `EnvCommand`, `AuditCommand`,
`RestoreCommand`, `CleanArtifactDirectoryOrderer`, `UpdateDependencyFilter`,
`CompilerErrorSeverityFilter`, `QuerySymbolNameFilter`, `CommandRegistry` or `CompletionCommand`,
all of which are `.nl` files in `src/NSharpLang.Compiler.BootstrapServices`. The classifier now
builds the set of every type name declared in a production `.nl` (1,094 of them) and asks which
bodies name one.

**The route split between the estate and `tests/native` is forced by a measured emit wall, not
chosen.** A `.tests.nl` in the estate can call `TreeCommand.Execute(...)` — same assembly — but it
can never see what that call printed: **`Console.SetOut` declines at
`emit.call.static-member-unmodeled`**, and so does `Console.SetOut(Console.Out)`. So every exit-code
row, every `IsNullOrWhiteSpace(stderr)` row and every stdout row has to leave the estate, and they
land in `tests/native/cli-command-contracts` (the 46th native project), which SPAWNS the real `nlc`.
That is strictly stronger than the C# was: the deleted bodies called `TreeCommand.Execute` directly
and never proved that `nlc tree` reaches `TreeCommand` at all. A second wall was re-measured on the
same route — a `JsonElement` INDEXER declines at `emit.local.initializer`, so arrays are walked with
`EnumerateArray`, as `tests/native/query-integration` already records.

**One product finding came out of it: `nlc clean` deletes in PATH-LENGTH order, not depth order.**
`CleanArtifactDirectoryOrderer.Order` runs a selection sort on `selected[i].Length` and consults
`GetArtifactDirectoryKindRank` only as a `rank > 0` filter — the three nonzero ranks are never
compared with one another, so the `.nlc`-before-`bin` ordering the deleted expectation appears to
pin is a coincidence of name lengths. The order is nevertheless SOUND for the job, because a nested
path is always strictly longer than the ancestor it nests under, which is the only pair where
deletion order matters.

**Slice 43 took the next 44 bodies, and `tests/CliCommandTests.cs` is now 2,805 lines / 56 test
methods.** The tranche is every remaining `*CommandKernels` family that is pure-kernel-plus-help-
contract: the nine `CompilationReferenceResolverKernels` bodies, the five `TestCommandKernels` ones,
and the `Watch`/`Tidy`/`Doc`/`Fix`/`FixCommandArgument`/`Lint`/`Format`/`Restore`/`Check` families.
It lands as **117 blocks in nine NEW estate `.tests.nl` files, 13 more in `TestCommandKernels
.tests.nl`, and 17 more in `tests/native/cli-command-contracts`** — 147 blocks replacing 44 bodies.
Nine of the 44 also read a console capture. Seven drove an `XCommand.Execute` IN PROCESS and two
drove the top-level dispatcher; command ownership was MEASURED, and six of those seven reach a
command that is still a `.cs` file in `src/NSharpLang.Cli/Commands/` — `CheckCommand`, `FixCommand`,
`LintCommand`, `WatchCommand` (twice) and `DocCommand`, with only `TidyCommand` N#-owned. So the
spawned successors are the only thing in the repository that proves `nlc check` dispatches to
`CheckCommand` at all.

**The product finding of slice 43 is a data-loss defect in `nlc tidy --fix`: the removal filter
matches a package name by BARE PREFIX.** `TidyCommandKernels.RemovalLineStartsWithPackage` compares
`packageName.Length` characters and checks nothing after them, and `TidyCommand.RemoveDependencies`
feeds it exactly the possibly-unused names — so a user whose `project.yml` carries both `Serilog`
(unused) and `SerilogExtra` (used) loses BOTH lines when the command rewrites the file. The deleted
C# had `  - SerilogExtra` in its fixture and in its expected removal, but the fact was invisible
inside a nine-element array comparison; it is now its own block with a control on the other side of
the rule. `FilterRemovalLines` has exactly ONE production caller and the estate is its only
coverage: under a mutation that adds the missing delimiter check, the whole C# unit suite is 653
green while the estate is red on 2.

**One more reserved-word position was measured: `file` is reserved in the PARAMETER-NAME position.**
A free function `func Entry(file: string, ...)` declines at `parse.function`; `filePath` compiles.

**Slice 44 is the task-020 finisher: bucket (a) is EMPTY in both surviving C# test files, and the
runner's last three policy decisions move into N#.** `tests/CliCommandTests.cs` drops its final 17
canonical bodies (947 declaration lines, 265 `Assert.`) to **1,810 lines / 39 test methods**, and
`tests/DaemonCommandTests.cs` drops two (45 lines, 27 `Assert.`) to **764 lines / 29**. The
successors are **132 blocks in ten NEW estate `.tests.nl` files, 11 more appended to
`BatchQueryKernels.tests.nl` and `TestCommandKernels.tests.nl`, and 13 more in
`tests/native/cli-command-contracts`** — 156 blocks and 662 assert rows replacing 19 bodies and 292
assert rows. Both files now hold ONLY bucket-(b) bodies, which retire with `CheckCommand.cs`,
`FixCommand.cs`, `QueryCommand.cs`, `Program.cs`, `DaemonCommand.cs`, `DaemonClient.cs`,
`DaemonServer.cs` and `DaemonProtocol.cs` under 021/015.

**Slice 45 CLOSES TASK 020: the ownership classifier reports bucket (a) = 0 across ALL 24
`tests/*.cs`.** Slice 44's closing pass found 30 more bucket-(a) bodies in four files it had never
measured; slice 45 re-verified them with a SHARPENED classifier that adds a reachability rule — the
N#-owned type must not only be CALLED, its value must REACH an assertion — and the census corrected
itself to **29**. `DotnetBuild_ResolvesRuntimeForAnonymousUnionAndProjectReferences` calls
`RestoreCommand.Restore` only as SETUP; its three assertions are a `dotnet build` exit code, a
`dotnet run` exit code and that run's stdout, so its subject is MSBuild, not N#. It is bucket (c),
and it stays.

`tests/CliParityAuditTests.cs` drops 24 bodies to **1,194 lines / 49 tests**,
`tests/IlSdkToolchainTests.cs` drops 2 to **282 / 5**, `tests/ErrorRecoveryPipelineTests.cs` drops
1 to **455 / 11**, and `tests/AstChildrenTests.cs` is DELETED WHOLE (147 lines, its only test).
The 29th body — `PackCommand_NoProjectYml_Fails` — is DE-TAUTOLOGISED IN PLACE rather than
migrated, because the command it drives is still C#-owned: it compared stderr against a live call to
`ProgramCommandKernels.GetErrorLine(PackCommandKernels.GetMissingProjectFileTextMessage())`, so both
sides agreed by construction. It now asserts the literal sentence, and the kernels' own text is
pinned independently in the new `PackCommandKernels.tests.nl`.

The successors are **60 blocks in five NEW estate `.tests.nl` files** (`UnifiedDiff`,
`NSharpInstallRoot`, `ProjectReferenceResolver`, `AstChildrenCore`, `PackCommandKernels`), **9 more
appended to `Linter.tests.nl` and `ColumnarParserRecovery.tests.nl`**, and **26 more in
`tests/native/cli-command-contracts`** — 95 blocks and 297 assert rows replacing 28 bodies and 95
assert rows.

**One body could not be ported and was RE-FORMULATED into something stronger.**
`EveryExpressionTypedSlot_OfEveryExpressionNode_IsEnumerated` enumerated AST node types with
`typeof(Expression).Assembly.GetTypes()`, which DECLINES at
`emit.local.initializer` — measured on a probe. It does not need reflection: every Expression node
is declared in ONE file (`Expressions.nl`) and `AstChildrenCore.Of` is a string-dispatch table whose
arms name their slots as string literals. `AstChildrenCore.tests.nl` reads both sources and checks
the containment IN BOTH DIRECTIONS — every node has an arm or is a declared leaf, every
Expression-typed slot is named by its arm, no arm names a slot the node does not declare — and pairs
that with runtime blocks over the two slots that historically shipped unvisited. The C# could only
check nodes its reflective kit could CONSTRUCT; the source census checks nodes no constructor
reaches, and catches the reverse error (a renamed slot leaving an arm that walks nothing) that the
C# could not see at all.

**Slice 45's product finding is in the parser's error recovery, and the deleted body could not see
it.** `Parser_AlwaysProducesCompilationUnit_EvenWithErrors` asserted only `CompilationUnit != null`
for five malformed sources. Measured against the real recovery: `@@`, `!!` and `%%` each report TWO
errors alone, but `##` parses as a PREPROCESSOR declaration and reports **NONE** — and a `##`
earlier in the file **SWALLOWS every diagnostic after it**. `"!! %%"` reports 4 errors;
`"## !! %%"` reports **0**. The five-source file the C# used reports 2 of its 6, and recovers
THREE invented declarations. Recorded, pinned, not fixed. A second finding is in the `nlc tidy`
JSON envelope: `ok` reports CLEANLINESS, not success, so `exit 0` can carry `ok:false` — the only
`nlc` envelope where the two disagree.

**Two of slice 43's route predictions were overturned by measurement, both in the cheaper
direction.** `CompilationBackendSelectionKernels_ValidatesEffectiveBackend` was flagged as possibly
unmigratable because it needs a `ProjectConfig`; in fact `new ProjectConfig()` with a property set
emits fine in the estate, and the whole policy sits behind one pure two-string function,
`EffectiveBackendKind`. `RestoreCommand_Deduplicates…` was predicted to want the native route
because it writes files; `RestoreCommand` is N#-owned and in the same assembly, and the whole
`Directory.CreateDirectory` / `File.WriteAllText` / `File.ReadAllText` path emits in the estate,
with no process to spawn.

**The product finding of slice 44 is that three deleted assertions pinned something no user can
observe.** `BatchQueryRunner_LoadRequestsErrorsUseMessageKernels` asserted
`Assert.Throws<FileNotFoundException>` and `Assert.Throws<InvalidDataException>` against
`BatchQueryRunner.LoadRequests`, which is `internal` in `src/NSharpLang.Cli/`. The shipped behaviour
distinguishes neither: all four requests-file failures — missing file, non-array payload, non-object
element, duplicate ids — exit 1 with a top-level `invalidRequestsFile` error envelope naming the
requests path, and the duplicate case emits NO `results` array and NO counts at all, because the run
never begins. The successors pin the observable envelope instead.

**Fourteen more deleted assertions were tautologies, and both sides are literal now.** Each batch
body compared an envelope's message against a LIVE call to the kernel that produced it, so the pair
agreed by construction and neither side ever said what the sentence is. The same pattern held for
the two surviving `DaemonServer` bodies, which are kept and de-tautologised in place: they assert
the literal wire message, and the kernel's own text is pinned independently in
`src/NSharpLang.Compiler.BootstrapServices/DaemonServerAndClientKernels.tests.nl`.

**Two emit walls and one parser limit were measured this slice.** A widening ARRAY STORE of a user
reference type into `object[]` declines (`emit.statement.block-child`), and so does an array
LITERAL of user types passed to an `IReadOnlyList<object>` parameter (`emit.local.initializer`); a
`List<object>` built with `.Add` works and is the spelling to use. Passing an `IReadOnlyList<T>`
static PROPERTY straight into an `IEnumerable<T>` parameter declines at
`emit.call.static-user-argument`; the backing array widens cleanly. And the vacuity instrument found
a parser limit rather than a vacuous block: **inverting SIX asserts as `!( … )` across THREE locals
in one `test` block declines at `parse.test`** — each shape parses alone, and the `(X) == false`
spelling carries the same inversion, which is what the matrix used.

**The `nlc test` runner's timeout classification and arity policy are now N#-owned, which
discharges task 020's condition (2).** `Program.Testing.cs` shrinks 618 → **617** and no longer
spells any of the three: `TestCommandKernels.GetRunTimedOutMessage`, `GetTestTimedOutMessage`,
`IsSupportedTestMethodArity`, `GetUnsupportedTestArityMessage` and `GetTestFullName` own them, and a
grep confirms zero copies of `Test run timed out.`, `Test timed out.`, `takes none` or the
`GetParameters().Length != 0` predicate remain anywhere in C#. Three mutations of those kernels each
move exactly one estate block.

**The runner's remaining VOCABULARY is N#-owned as of task 021 slice 6, and `Program.Testing.cs`'s
literal census is now exactly its three surviving invariant sentences.** Slice 42's partition named
four residues; a full literal/ordinal census at slice 6's tip found TWELVE, and all twelve moved:
the outcome words `passed`/`skipped`/`failed` (`GetPassedOutcome`/`GetSkippedOutcome`/
`GetFailedOutcome`, which `GetNativeTestOutcomeRank` is now DEFINED FROM), the `F3` JSON duration
and the `F0` verbose elapsed number (`FormatTestDurationSeconds`, `GetZeroTestDuration`,
`FormatTestElapsedMilliseconds`), the verbose classification (`GetVerboseMessage`), the lifecycle
names AND their order (`GetPreTestLifecycleMethodNames`/`GetPostTestLifecycleMethodNames`, which
`IsLifecycleMethodName` is now defined from), the xUnit runner-error row's identity
(`GetXunitRunnerErrorName`/`…DisplayName`), the display-name preference
(`GetPreferredDisplayName`), the failure-message join (`JoinFailureMessages`), the test build
configuration (`GetTestBuildConfiguration`, which `GetTestOutputDirectory` now reads), the
output-mode ordinals (`IsJsonOutputMode`/`IsTextOutputMode`, defined from `GetOutputMode`), the four
bare `return 1`s (`GetExitCode(false)`) and two re-implementations of `GetTestFullName`.
**NONE OF THE OUTCOME VOCABULARY HAD EVER BEEN PINNED**: before this slice no contract anywhere
asserted a native `nlc test` outcome value, so the three words that decide the command's exit code
could have been renamed freely. `TestCommandKernels.tests.nl` now pins them, including the
consequence — an unknown outcome word ranks 0 and FAILS the run. **One deliberate behaviour change**:
the JSON `duration` field was built with `$"{…:F3}s"`, which reads the CURRENT culture; it is now
`CultureInfo.InvariantCulture`, so the versioned envelope cannot print a comma decimal.

**The `nlc test` runner seam is the instrument for that slice** — `nlc test` driven six ways
(`--json`, `--verbose`, plain text, `--filter`, and `--coverage` on both routes) over a fixture
carrying a passing and a deliberately failing test, with every duration and elapsed number
canonicalised to its SHAPE rather than its value. Before and after are byte-identical at 130 lines,
and the after reproduces byte-identical across a restore-and-rebuild.

Tokenization has no C# assertion layer: the lexer's canonical contracts are N#, in
`src/NSharpLang.Compiler.BootstrapServices/Lexer.tests.nl`, and they run in the BootstrapServices
estate rather than in `tests/Tests.csproj`. See `memory/components/lexer.md`.

Linting has no C# assertion layer either. The linter's canonical contracts are N# and live beside
their subjects in the same estate: `Linter.tests.nl` (the declaration walk, and the end-to-end rule
contracts for NL001/NL002/NL003/NL004/NL006/NL010/NL011/NL012/NL016/NL020, suppression and resolved
spans), `DiagnosticCatalog.tests.nl` (all 99 descriptors), `LinterConfig.tests.nl` (severities,
overrides and `.editorconfig`) and `LinterBindingUsageCore.tests.nl` (the unused-binding policy).
Formatting has no C# assertion layer either. The formatter's canonical contracts are N# and live
beside their subjects in the same estate: `Formatter.tests.nl` (the nineteen declaration arms, one
at a time, against hand-built AST nodes, plus the two `FormatSafe` gates), `FormatterWalk.tests.nl`,
`FormatterWalkState.tests.nl` and `FormatterSyntaxText.tests.nl` (the body walk, the state carrier
and the leaf text), `FormatterSourceText.tests.nl` (the front door — source text in, canonical
source text out, with idempotence and the reparse round trip) and `FormatterConfig.tests.nl`
(`FormatterConfig`, `.editorconfig` reading and the `FormatterConfigKernels` int parser).

Four more subjects moved out of `tests/Tests.csproj` in 020 slice 12 and now have no C# assertion
layer at all. `NullabilityMetadataCore.tests.nl` states the CLR↔N# built-in maps as one sixteen-row
table read two ways, the 3 × 3 nullability wrapping table, and the reference-nullability eligibility
partition, beside `NullabilityTypeDisplay`'s sixteen display arms. `StringLiteralDecoder.tests.nl`
crosses all eleven escapes through the scalar seam and pins the divergence between the strict and
tolerant decoders. `OutputFormatterDiagnosticClusterKernels.tests.nl` states the diagnostic-cluster
triage layer — both tiers of the category classifier, all nine source constructs, the message
pattern, the cluster id and the escaped next command — with the serialised payload beside the other
envelopes in `OutputFormatterJsonKernels.tests.nl`. The local-function parser arms are whole-tree
goldens in `ColumnarParserAst.tests.nl` — whose `AstEq` reflective comparator and `Golden.*` builders
are shared by `ColumnarParserDeclarations.tests.nl` (the declaration family, 020 slice 17),
`ColumnarParserStatements.tests.nl` (statements and the test DSL, slice 18) and
`ColumnarParserPatterns.tests.nl` (patterns/`match`, parameter and argument modifiers, operator and
conversion overloads and constructor initializers, slice 19) — and the four
`ColumnarCompiler.TryEmitProgram` cases are
real source shapes in `tests/native/columnar-emit-facts`.

Run them with `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release -p:NSharpExcludeTests=false`
(restore with `-p:NSharpExcludeTests=false --force-evaluate` first).

## Testing Strategy

### 1. No Mocks
Tests use real components, not mocks. This ensures:
- Real-world behavior validation
- Integration coverage where feasible
- Simpler test code

### 2. Focused Tests
Each test validates one specific feature:
```text
[Fact]
public void TestVariableDeclaration()
{
    var source = "let x := 42";
    var tokens = new Lexer(source, "test").Tokenize();
    var parser = new Parser(tokens, "test");
    var ast = parser.ParseCompilationUnit();

    var stmt = ast.Statements[0] as VariableDeclarationStatement;
    Assert.NotNull(stmt);
    Assert.Equal("x", stmt.Name);
}
```

### 3. End-to-End Validation
Integration tests validate full pipeline:
```text
[Fact]
public void TestFullCompilation()
{
    var source = "let x := 42";

    // Lex
    var tokens = new Lexer(source, "test").Tokenize();

    // Parse
    var ast = new Parser(tokens, "test").ParseCompilationUnit();

    // Analyze
    var result = new Analyzer().Analyze(ast, "test", "/");
    Assert.Empty(result.Errors);

    // Compile/analyze through the current backend under test
    Assert.Empty(result.Errors);
}
```

### 4. Emitted Assemblies Load Into Collectible Scopes
Tests that reflect over or invoke an emitted assembly (columnar parity programs, compiled
BootstrapServices or CLI outputs, `MultiFileCompiler` outputs) must load it through `CollectibleAssemblyScope`
(tests/CollectibleAssemblyScope.cs):

```text
using var loadScope = CollectibleAssemblyScope.Load(asm!);                  // emitted byte[]
using var loadScope = CollectibleAssemblyScope.LoadFromFile(outputPath);    // emitted .dll
var type = loadScope.Assembly.GetType(typeName!)!;
```

Never `Assembly.Load(bytes)` or `Assembly.LoadFile(path)`: each call pins the assembly in a fresh
NON-collectible AssemblyLoadContext for the test host's lifetime. The parity suite loads hundreds of
emitted assemblies per run and grows every slice — the pinned pile intermittently OOM-crashed the
xUnit host ("Test host process crashed : Out of memory").

Rules of the scope:
- Keep every `Type`/`MethodInfo`/delegate obtained from `loadScope.Assembly` inside the `using` scope.
- `CollectibleAssemblyScopeTests` pins the contract (collectible, non-default, reclaimable after Dispose).
- The compiler side holds the matching guarantee: external-type/doc resolution enumerates loaded
  assemblies through the N# `ExternalAssemblyScan.Loaded()` owner
  (`src/NSharpLang.Compiler.BootstrapServices/ExternalAssemblyScan.nl`),
  which skips dynamic and collectible assemblies — so a briefly-loaded emitted assembly can no longer
  hijack a concurrent in-process compile's bare-name lookup (the "MemoryCopy not found on type Buffer"
  flake). Never resolve external types via a raw `AppDomain.CurrentDomain.GetAssemblies()` scan.

### 5. The Product Gate Skips Steps With Unchanged Inputs
Within a plain fresh isolated `./scripts/test-all.sh` development run, a gate step is skipped when
its ENTIRE input set is byte-identical to inputs that previously PASSED that step on the same
toolchain and environment (validated per-step cache in `tests/scripts/test-all-core.sh`; markers
written only on success). Input sets are over-inclusive — `src/**` and the gate scripts invalidate
everything, and UNIT includes `docs/` and `website/docs/` wholesale because unit tests
golden-compare and parity-check repo documentation (cli-reference.md, the diagnostic-clusters
sample, the systems audit). Step keys are also salted with the behavior-changing environment (the
same env_names as the whole-gate signature, including `NSHARP_EXPERIMENTAL_SOA`) and the installed
dotnet-ilverify tool version. Practical effect for local development: docs-only changes re-run unit
tests (~1m36s) but still skip benchmarks, interop, and the example chain; tests-only changes skip
benchmarks and the example chain. Do NOT "optimize" docs changes back out of UNIT — that exact gap
let a red docs-parity test pass the step cache during finding F9. `--commit`, `--release`,
`--fresh`, `--no-cache`, and `--clean` disable skipping and run every step. The isolated run always unsets
`NSHARP_UPDATE_DIAGNOSTIC_GOLDENS` (golden regeneration inside the discarded copy is
self-satisfying); regenerate goldens with plain `dotnet test` in the working tree. When adding a
gate step, pointing one at new input paths, or making a test read a new repo file, update the
input-set prefixes next to the step wrappers in test-all-core.sh —
`tests/GateStepInputSetGuardTests.cs` enforces coverage of repo files tests read, the env-list
sync between the two scripts, and the hash-step behavior itself.

### 7. Gate Profiling And Slicing Guidance
Current gate profiling must be refreshed after the removal of the old
wall-clock benchmark lane. Use a fresh `VSCODE_TESTS=skip ./scripts/test-all.sh
--commit` run when updating this section.

Per-test TRX profiling from the same pass showed the unit bucket is dominated by
SDK/toolchain subprocess tests and a few full IL execution cases. Those sums
exceed wall time because xUnit runs collections concurrently; the critical path
is still the slow `dotnet build`/`dotnet test` subprocess tests.

Do not pay the full gate during normal edit loops. Use:

```bash
./scripts/dev.sh --since
./scripts/dev.sh Columnar
./scripts/dev.sh 'FullyQualifiedName~SomeTest&Category!=Slow'
```

`dev.sh --since` is intentionally fail-safe: central compiler, SDK/runtime,
build, fixture, or unmapped changes run the full unit suite rather than silently
narrowing. For backend-only commit verification, the required final command is
still:

```bash
VSCODE_TESTS=skip ./scripts/test-all.sh --commit
```

The full gate avoids one known duplicate-work trap: Step 8/9 build the
example/fixture surface, then Step 10b passes the exact emitted assemblies to
`scripts/ilverify.sh --built-dirs-file` and adds `--build-native-tests` for the
selected direct-call, construction/array, and erased-enum regression assemblies.
The built-dirs mode never rebuilds examples or fixtures. Copied package and DLL
runtime assets remain verifier references rather than being mistaken for N#
outputs. Standalone `scripts/ilverify.sh` and CI build the product surface and
selected native regression assemblies themselves before verification.

## Test Categories

### Lexer Tests
- Keyword recognition
- Operator tokenization
- String interpolation
- Numeric literals
- Comments
- Error handling

### Parser Tests
- Statement parsing (if, for, while, etc.)
- Expression parsing (binary, unary, calls, etc.)
- Declaration parsing (class, func, record, etc.)
- Operator precedence
- Pattern parsing
- Error recovery

### Analyzer Tests
- Type inference
- Type checking
- Name resolution
- Scope management
- External type resolution
- Pattern exhaustiveness
- Definite assignment
- Duck interface validation
- Error detection

### Language Server Tests
- Completion (member access, namespace, N# types)
- Hover (type info display)
- Go-to-definition
- Rename (with interpolation awareness)
- FindAllReferences
- Headless VS Code extension-host smoke tests live under `editors/vscode/src/test`
- `./scripts/test-vscode-headless.sh` builds the release server, launches VS Code in extension-host mode, exercises diagnostics/completions/hover/definition/references/code actions, and writes `.context/vscode-headless-report.json`; the implementation lives under `tests/scripts/`

### Code Intelligence Tests (CLI Toolchain)
- **`tests/native/query-integration`** — the `nlc query` toolchain has no C# assertion layer as of
  task 020 slice 39: `tests/QueryIntegrationTests.cs` is DELETED and all 65 of its cases are N#
  contracts in that project, reaching `CodeIntelligenceService`, `CompletionEngine` and
  `OutputFormatter` IN PROCESS by reflection. It runs against the same REAL projects:
  - `examples/01-hello-world` — single file, functions, variables
  - `examples/06-classes-and-records` — records, members, methods
  - `examples/12-multi-file-projects/MultiFileProject` — cross-file imports, namespaces
  - `examples/05-unions` — unions, error handling
  - `tests/fixtures/issue-tracker` — multi-file API: unions, duck interfaces, records
- Contracts: symbols (filters, members, casing-visibility), outline, diagnostics, definition,
  references (cross-file, contexts), completions, BindingMap, the versioned JSON envelopes, the
  shipped `docs/examples/diagnostic-clusters.sample.json` golden document, and unhappy paths
- **CodeIntelligenceTests** — one case only: the unknown-severity invariant fallback, which is
  non-vacuous only under a Turkish ambient culture and therefore cannot move (N# reaches
  `CultureInfo` in neither direction). The other 44 cases are N# contracts in the BootstrapServices
  estate — `OutputFormatterJsonKernels.tests.nl` (the versioned JSON envelopes and their exact root
  keys), `OutputFormatterTextBuilders.tests.nl` (every `--text` answer, stated as whole texts) and
  `OutputFormatterDiagnosticKernels.tests.nl` (severity arithmetic, reference deduplication, and the
  two end-to-end `CodeIntelligenceQueries.Diagnostics` contracts)
- **Completion engine** has no C# assertion layer: `CompletionEngine`'s contracts are N# in
  `tests/native/completion-engine`, a native project that drives the production `CompletionEngine`
  and `CodeIntelligenceService.LoadProject` BY REFLECTION — the route `tests/native/query-completions`
  established, and the only one available, because the engine's inputs need the C# `Analyzer` that
  lives in the assembly which DEPENDS on BootstrapServices
- **Error reporting** has no C# assertion layer: the diagnostic record, the suggestion tables and the
  Elm-style builders are stated in N#, beside their subjects in the same estate —
  `CompilerError.tests.nl` (the rust-style, tooling and MSBuild renderers as WHOLE texts, the
  diagnostic-id derivation and its override, the seven-heading Elm severity table, the inline-text
  folder), `ErrorSuggestions.tests.nl` (the whole code-to-suggestion table, the typo probe and the
  Levenshtein kernel), `ErrorSuggestionHelpers.tests.nl` (`SmartSuggester`'s RANKED answers and
  `TypeConversionSuggester`'s ordered rule table) and `ErrorMessageBuilder.tests.nl` (the docs-URL
  table, the similar-names switch and the three list renderers)
- **Code fixes** have no C# assertion layer: `CodeFixService`, its six providers and
  `CodeFixActionHelpers` are stated in `CodeFix.tests.nl` in the same estate, where every edit is
  proved by APPLYING it through `FixApplicatorCore.ApplyEdits` and re-parsing the result
- **The fix applicator** has no C# assertion layer: the four owners are stated one file each in the
  same estate — `FixApplicatorCore.tests.nl` (applied source as WHOLE text, and every rejection as
  its whole message rather than a substring, so the blamed edit is named),
  `FixApplicatorTextEditOrderer.tests.nl` (each of the five ordering keys in isolation plus a
  200-list differential sweep against an independently written oracle, over an N#-owned generator
  because `System.Random` cannot be constructed in this estate),
  `FixApplicatorValidationMessages.tests.nl` (the five rejection sentences and the index clamp) and
  `FixApplicatorEditEngine.tests.nl` (the raw return codes, the error slots, the three line-ending
  arms and the malformed-call guard)
- **The unused-binding rules** are stated end to end in `Linter.tests.nl`, where every "this
  variable is NOT reported" claim carries a control — the same source with the read removed, or with
  an unused sibling added — so a linter that reported nothing could not pass. This replaced a C#
  file in which seventeen of nineteen negative cases ran against an entirely empty diagnostic list
- **The top-25 diagnostic golden suite** has no C# assertion layer: `DiagnosticGoldenSuite.tests.nl`
  holds the curated corpus and pins it against `tests/fixtures/diagnostics/`, calling
  `OutputFormatterTextBuilders.DiagnosticsToText` directly instead of through the C# `OutputFormatter`
  forwarder. **It also records that the suite is misnamed: it holds TWENTY-FOUR diagnostics.** The
  fixtures stay covered by the validated per-step cache without a gate-script change, because the
  `native-nsharp-tests` step is keyed on `UNIT_INPUTS_HASH` and the UNIT input set already covers
  `tests/` wholesale
- **`project.yml`** has no C# assertion layer: the four owners are stated one file each in the same
  estate — `ProjectFileParser.tests.nl` (whole documents in, every field read back, and all NINE
  validation refusals plus the four `FileNotFoundException` sentences as whole messages, where the
  deleted C# reached three refusals and produced no file-not-found at all),
  `ProjectConfigModels.tests.nl` (the defaults and the source walk, with all TWELVE skipped
  directory names one at a time plus four kept neighbours as controls),
  `ProjectSourceFileFilter.tests.nl` (the glob engine arm by arm — and it records that `**/name`
  does NOT match a root-level `name/`, unlike MSBuild) and `Reference.tests.nl` (the four kinds,
  their precedence, and `Validate`, which had no direct coverage at all). `AssemblyVersionUtilities
  .tests.nl` states the package-version kernel as a TABLE rather than as a differential sweep
  against `int.TryParse`, because `CultureInfo` cannot be reached from this estate in either
  direction
- **The shipped `examples/` corpus** has no C# assertion layer: `ExampleProjectCorpus.tests.nl`
  walks all nineteen example projects through the compiler's OWN discovery
  (`MultiFileCompilerInputBuilder.BuildFromProject`), parser and linter, pinning each project's file
  count, zero parse errors and an empty lint census. **It REQUIRES every directory to exist**,
  which the deleted C# theories did not — each opened with `if (!Directory.Exists(…)) return;`. One
  of the nineteen, `11-advanced-features`, is covered by nothing else in the repository: the gate's
  Step 10a keeps a directory only when it has a `project.yml` or a top-level `.nl` file, and that
  one has neither. The remaining half of `nlc check` (semantic analysis and IL emission) stays with
  Step 10a, which runs the real binary over a superset of these directories

### Known Testing Limitation
Raw filtered `dotnet test --filter` invocations can hang in this project because of the
assembly-loading test topology. Use `./scripts/dev.sh <pattern>` for focused work and plain
`dotnet test tests/Tests.csproj` for the full unit suite.

## Running Tests

### All Tests
```bash
dotnet test tests/Tests.csproj
```

### Specific Test Class
```bash
./scripts/dev.sh SystemsNSharp
```

### Specific Test Method
```bash
./scripts/dev.sh TestGenericConstraints
```

### With Detailed Output
```bash
dotnet test -v detailed
```

## Test Examples

### Example 1: Lexer Test
```text
[Fact]
public void TestStringInterpolation()
{
    var source = "$\"Hello {name}\"";
    var lexer = new Lexer(source, "test");
    var tokens = lexer.Tokenize();

    Assert.Single(tokens);
    Assert.Equal(TokenType.StringLiteral, tokens[0].Type);
    Assert.Equal("$\"Hello {name}\"", tokens[0].Value);
}
```

### Example 2: Parser Test
```text
[Fact]
public void TestMatchExpression()
{
    var source = "result := match value { 0 => \"zero\", _ => \"other\" }";
    var tokens = new Lexer(source, "test").Tokenize();
    var parser = new Parser(tokens, "test");
    var ast = parser.ParseCompilationUnit();

    var stmt = ast.Statements[0] as VariableDeclarationStatement;
    var match = stmt.Initializer as MatchExpression;
    Assert.NotNull(match);
    Assert.Equal(2, match.Cases.Count);
}
```

### Example 3: Analyzer Test
```text
[Fact]
public void TestTypeMismatchError()
{
    var source = "let x: int = \"hello\"";
    var tokens = new Lexer(source, "test").Tokenize();
    var ast = new Parser(tokens, "test").ParseCompilationUnit();
    var result = new Analyzer().Analyze(ast, "test", "/");

    Assert.NotEmpty(result.Errors);
    Assert.Contains("Type mismatch", result.Errors[0].Message);
}
```

## Test Coverage

### Features Tested
- ✅ All statement types
- ✅ All expression types
- ✅ All declaration types
- ✅ Type inference
- ✅ Type checking
- ✅ Pattern matching
- ✅ External types
- ✅ Duck interfaces
- ✅ Unions and enums
- ✅ Async/await
- ✅ Iterators
- ✅ Error handling
- ✅ String interpolation
- ✅ Operator overloading
- ✅ Conversion operators
- ✅ Params collections
- ✅ List patterns
- ✅ And much more...

## N# Test Files (.tests.nl)

N# native tests use top-level `test` declarations and `assert` statements:

```
// example.tests.nl
namespace Example

test "adds two values" {
    result := Add(2, 3)
    assert result == 5
}
```

Run with:
```bash
nlc test --project <project-directory>
```

Table-driven tests are live too, and each ROW is an independent test:

```
test "adds" with (a: int, b: int, sum: int) [
    (1, 2, 3),
    (2, 3, 5)
] {
    assert a + b == sum
}
```

N# lowers every row into its own test declaration before emit — the row's values are bound as typed
locals of the declared parameter types — so each row emits its own method and reports under its own
name, `adds (1, 2, 3)`. Row values must be literals (`NL310` otherwise), and a row's value count
must match the parameter count (`NL202` otherwise).

`skip`, `setup` and `teardown` parse and are understood by the editor tooling, but `nlc test` still
refuses a file containing one — `skip` at emit (`parse.declaration-scan`), `setup` earlier still, in
the analyser (see the table below). Do not rely on them yet.

**Which runner capability comes next is decided by MEASURED demand, not by the task file's order.**
The close-out contract forbids shipping runner infrastructure with no consumer, so before building
one, sweep the C# test estate for tests that actually need it. The sweep taken at
`tests/native/parser-literal-facts`'s slice, over **2,818 attributed test methods in 279 classes**:

| capability | C# tests that need it | measured runner state (probed against a freshly built tip CLI) |
|---|---|---|
| table-driven cases | shipped, consumed twice | live |
| **skip** | **0** — no `[Fact(Skip=…)]`, no `SkipException`, no `[ConditionalFact]`, no trait filters anywhere. The only `Skip=` in the repo is `DockerFactAttribute`, in the Testcontainers `IntegrationTests` project the gate never runs. The 6 `if (!Directory.Exists(…)) return;` guards that used to live in `ExampleLintTests.cs` — the original finding here — **are gone: that file is deleted and its successor `ExampleProjectCorpus.tests.nl` REQUIRES all nineteen example directories, so an absent corpus now fails instead of silently passing** | declines the WHOLE FILE at `parse.declaration-scan`; an **emit-only** gap — parser, analyser, formatter, LSP, runner and JSON envelope all already carry it. **No consumer remains: the last runtime skip emulation in the estate was migrated away rather than expressed** |
| setup/teardown | 3 classes with a real ctor+`IDisposable` pair, all LSP or Docker fixtures | fails EARLIER than skip, in the **analyser**: a `setup { seed := 7 }` binding is not visible to the test body, so `NL001 Variable 'seed' is declared but never read` |
| **async `Task`** | **134** | **ALREADY SERVED.** A plain `test` body may `await`; an assertion that fails after an await FAILS, and an exception thrown inside awaited work is REPORTED with its message (probe: 3 declarations → 1 passed / 2 failed, each named). Only the `async test "…"` DECLARATION form is missing (`NL101`), and no C# test needs it |
| async `ValueTask` | 0 | same path |
| structured failure JSON | — | already in the envelope: `errorMessage` carries the failure text |
| whole-run timeout | **1 cluster, measured in 020 slice 16** — `tests/ParserErrorTests.cs`'s `Parser_MalformedTableDrivenTest_TerminatesWithErrors` bounded each of its three malformed parses with `Task.Run(...)` + `Wait(TimeSpan.FromSeconds(10))`, so a lost no-progress guard in `ParseTestDeclaration` failed FAST instead of hanging the host. That is a PER-PARSE bound inside a test body, not a per-assembly one | the per-assembly flag exists (`nlc test --timeout <duration>`, "Test timeout per assembly"), but **no in-body bound is expressible in the BootstrapServices estate: `Task.Run` declines at `emit.local.initializer`, an inline lambda in its overload set declines at `emit.body`, `System.Diagnostics.Stopwatch` is an unsupported local type, and `Environment.TickCount64` declines at `emit.typed-local.initializer` — all four measured by execution at that slice's tip.** The lambda itself is innocent: bound to an explicit `Func<int>` local it emits and invokes. The three rows migrated with their exact diagnostic censuses; the fail-fast property did not |

**So most of the remaining order is already served or unwanted, and the real remaining work in the
native-runner close-out is MIGRATION, not capability.** Note also that the gate's Step 3a validator
ALREADY accepts skips at `schemaVersion` 1 — it cross-checks `passed + failed + skipped == total` and
`outcome_counts["skipped"] == summary.skipped` — and the runner already maps xUnit's `ITestSkipped`
to a `skipped` outcome with its reason.

### Which native estate a migrated cluster belongs in

Step 3a runs **two** native estates, and they have different capability ceilings. Choose by the
ARGUMENT TYPES the cluster's subject calls take — measured by probe, not assumed:

| the cluster's subject calls take… | estate | why |
|---|---|---|
| `string` / `int` / `bool` / arrays / literals, answering primitives | **`tests/native/<name>/`**, subject reached as a `dll:` dependency, run by the LIVE CLI | tables (`with (…) […]`) are available here, so each row reports as its own test |
| an ENUM member, a CONSTRUCTED object, or anything else the emitter must resolve in the dependency assembly | **`src/NSharpLang.Compiler.BootstrapServices/<Subject>.tests.nl`**, same assembly, compiled by the PINNED toolset | a dependency-assembly enum member declines at `emit.typed-local.initializer` (and `emit.call.static-member-unmodeled` in argument position), and `new <dependency type>(…)` declines at `emit.local.initializer`; in a table row the enum member is refused earlier still, by `NL310` |
| a subject that lives ABOVE the estate (in `Compiler.dll`), whose values are not primitives | **`tests/native/<name>/`**, subject reached BY REFLECTION through `object` | this is the `tests/native/query-completions` / `completion-engine` / `analyzer-identifier-binding` / `analyzer-event-subscription` route |

**A file can have TWO subjects, and then it splits.** Membership is decided per CLUSTER, not per
file: `tests/AstNodeFinderTests.cs` (slice 23) had a finder subject in the estate and an analyzer
subject above it, `tests/EventSubscriptionTests.cs` (slice 24) had a parser subject in the estate
and an analyzer subject above it, and `tests/ErrorHandlingTests.cs` (slice 25) had the same pair.
All three were split rather than forced whole through the weaker route. **A file with ONE subject
that is too big for the budget splits ACROSS SLICES instead**: `tests/AnalyzerSemanticModelTests.cs`
was 1,361 lines and 51 `[Fact]`s that ALL construct `new Analyzer()`, so its cut was by INSTRUMENT —
the model's query surface in slice 26, the `TypeInfo` source-fact walker and the diagnostics it
drives in slice 27. Its ratchet row SHRANK exact-match at the first cut and flipped to `removed` at
the second, which is the shape a cross-slice split always takes. **Decide membership by
decoding what each method CALLS, never by its name** — slice 25's file has three methods named
`Parser_*` whose only claims are over `AnalysisResult`, and they belong in the native half.
**And a subject the estate CAN reach may still belong in the native half**: slice 25's `Linter` rows
are native, because the one deleted method that drove both owners drove them over ONE fixture and the
pairing is what states the finding — that on one input the analyzer reports and the linter does not.
Each native project carries its OWN reflection plumbing — `SetCompletionObject` / `SetDocQueryObject`
/ `SetEventObject` are the same idiom written per project — so a NEW subject gets a NEW sibling
project named for it rather than a second tenancy in one named for something else. **The converse
holds too, and slice 27 is the case**: the SECOND half of a cross-slice split is the SAME subject, so
it EXTENDS the project the first half created rather than adding a sibling — same fixtures territory,
same entry point, and the existing plumbing already covers it. The native project count does not
grow when a slice takes a second tranche of a subject it already owns.

**A `project:` reference would not change that second row, and 020 slice 23 measured why.** The
decline is in the emitter's TYPE RESOLUTION, not in how the assembly arrives: naming a referenced
assembly's type in a local, an argument or a `new` declines for a C# type in `Compiler.dll`
(`new Analyzer()`), for an N# type in the estate's own compiled assembly
(`ColumnarParserRecovery.ParseFileAst(...)` bound to a `FileParseAst` local, which reports
`emit.local.unsupported-type` naming the type) AND for a `nuget:` type (`new SerializerBuilder()`) —
three routes, one decline. Static entry points whose values are ALL primitives bind by name with no
reflection at all, which is why `tests/native/parser-literal-facts` calls its owner directly.
Separately, `project:` in `project.yml` resolves only through
`ProjectReferenceResolver.ResolveNSharpProjectRoot`, which requires a `project.yml`: a C# `.csproj`
cannot be a project reference at all, and the resolver says so in its own message.

The pinned toolset predates table-driven lowering, so the BootstrapServices estate takes plain `test`
declarations with `assert` lines — which is also why its contract count moves by exactly the number
of DECLARATIONS added. Its reported total runs ~22 above a `grep -c '^test "'` census (5,071 vs 5,093
at the `OperatorFacts` slice), so measure the estate with `dotnet test` before and after and diff;
never quote the grep as the contract count.

## Validation cadence

Use the narrowest relevant inner loop while editing:

```bash
./scripts/dev.sh <pattern>
./scripts/dev.sh --since
```

Commit a coherent compiler slice after its focused evidence is green. Do not run the full
product gate between every small backend commit.

At integration checkpoints—before push/handoff, after SDK/runtime/build-script/package changes,
after broad shared compiler changes, or when focused evidence is ambiguous—run a fresh
non-VS-Code product gate:

```bash
VSCODE_TESTS=skip ./scripts/test-all.sh --commit
```

For Language Server, LSP, extension, or other IDE-affecting work, do not skip VS Code tests:

```bash
./scripts/test-all.sh --commit
./scripts/reload-vscode-extension.sh
```

Then use computer-use to verify the behavior in the installed extension and capture screenshots.
`AGENTS.md` is authoritative for the exact gate boundary.

The product-gate entrypoint runs from an isolated temporary copy of the
repository with separate HOME, temp, NuGet, and npm state. Successful isolated
runs write a content-addressed cache manifest that includes source content,
test arguments, selected environment, tool versions, and platform data; when all
of those inputs still match, follow-up invocations validate the manifest and
return the recorded green result quickly. Plain `./scripts/test-all.sh` may use
that cache for development feedback. Integration and release evidence uses
`--commit` (or `--release`) so cached results are not accepted.

The full isolated run:
1. Runs all unit tests (`dotnet test`)
2. Runs compiler-service `.tests.nl` contracts plus every `.tests.nl` project under
   `examples/` and `tests/`; template-native suites join this gate with their N# lowering owners.
   The gate requires a positive executed-test count and reconciles every native JSON outcome
   before it may cache the step, so empty or internally inconsistent runs are failures.
3. Rebuilds the compiler and SDK
4. Installs the latest SDK to local NuGet feed
5. Tests `dotnet new` template creation
6. Builds ALL example projects with `dotnet build`
7. Validates everything works end-to-end

Do not use a cached gate result as integration-checkpoint evidence.

## Continuous Testing

Tests run on:
- Every commit (CI/CD)
- Before releases
- During development (watch mode)

## Test Quality Standards

1. **One assertion per test** (when possible)
2. **Descriptive test names** (TestFeature_Scenario_ExpectedBehavior)
3. **Arrange-Act-Assert pattern**
4. **No test interdependencies**
5. **Fast focused execution** (keep individual facts small; broad integration suites may be slower)
