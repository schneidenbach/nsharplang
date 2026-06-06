# Self-Host Progress Log

**Status:** Living log for the N# compiler self-hosting / dogfood migration. Newest entries on top.
See [`compiler-dogfood-rewrite.md`](compiler-dogfood-rewrite.md) for per-slice methodology and
evidence, [`compiler-benchmark-metrics.md`](compiler-benchmark-metrics.md) for the numbers, and
[`compiler-dogfood-boundary-profiling.md`](compiler-dogfood-boundary-profiling.md) for the
delegate-boundary cost analysis (the key perf finding driving the endgame).

This log records: what migrated, benchmark deltas, adapters removed, bootstrap coverage %, and every
language/runtime/compiler limitation found plus the principled change made to resolve it.

---

## 2026-06-06 — N# parser slice 3: package name

`PackageNameSpanInto` (ParserDeclarations.nl) records the file's `package A.B.C` dotted-name span (or
returns 0 when absent), matching the C# parser's `CompilationUnit.Package?.Name`. Verified on the
controlled/indentation corpora and all 27 dogfood kernels. The N# parser now extracts a coherent
file-structure index — package + top-level declaration kinds + names — from the lexer's tokens,
in-assembly. (Imports' namespace-vs-file-import distinction is deferred to a later careful slice.)

## 2026-06-06 — N# parser slice 2: top-level declaration names

`TopLevelDeclarationNameSpansInto` (ParserDeclarations.nl) extends slice 1 to also record each
top-level declaration's NAME span. A declaration's name is the token immediately after its keyword
(modifiers precede the keyword), so `name = next token when it is an Identifier` is exact for all eight
keyword declaration kinds and correctly yields no-name for `test "..."` (string-named, out of scope
this slice). Verified against the C# parser's `Declaration.Name` (kind + name pairs) on the controlled
corpus, the indentation-style corpus, and all 27 dogfood kernels. The N# parser now extracts a
top-level declaration index (kind + name) from the lexer's tokens, all in-assembly.

## 2026-06-06 — Phase 2 begins: first N#-native parser slice (top-level declaration extraction) + nlc query ast

**What:** Two slices that open the parser-migration phase (the path to actually deleting the
`*DogfoodAdapter` bridge and, ultimately, bootstrap).

1. **`nlc query ast`** (LLM-first CLI + verification harness). New `nlc query ast [--file F]`
   subcommand emits the parsed `CompilationUnit` AST(s) as stable, node-typed JSON
   (`OutputFormatter.AstToJson`: each node `{ "node": "<ConcreteType>", …declared props }`, recursing,
   preserving the concrete kind through the polymorphic Declaration/Statement/Expression bases). This
   is both an AGENTS LLM-first-CLI deliverable and the **canonical AST representation** for verifying an
   N# parser against the C# parser. Hardened by `Parser_RealCorpus_AstSerializesDeterministically`
   (parse + serialize all 108 real .nl files: valid, deterministic, no crashes).

2. **First N#-native parser kernel** (`CompilerServices/ParserDeclarations.nl`):
   `TopLevelDeclarationKindsInto` extracts the top-level declaration KIND sequence from the
   brace-inserted token stream (output of the now-complete N# lexer), tracking brace/bracket/paren depth
   so it captures declaration keywords (Func/Class/Struct/Interface/Union/Record/Enum/Type/Test) only at
   depth 0 — naturally skipping modifiers, attributes, and NESTED declarations, and capturing
   `ref struct`/`duck interface` at their `struct`/`interface` keyword exactly as the C# dispatch
   (`Parser.cs:226-273`) produces. Verified by `Parser_TopLevelDeclarationKinds_MatchProductionParser`
   against the C# parser's `CompilationUnit.Declarations` (mapped to keyword ordinals) on a controlled
   corpus (all keyword kinds + nested-decl exclusion + modifiers + attributes), an indentation-style
   corpus (virtual braces handled identically to explicit), and all 27 dogfood kernels (real code).

**Significance:** the lexer is feature-complete and an N# consumer of its tokens now exists in-assembly
(the kernel reads the lexer's token arrays). This is the first verified rung of the parser ladder.
Building it surfaced no new language gaps. Bootstrap coverage remains 0% (these are services behind the
adapter), but the verification harness (AstToJson) + the first parser rung are the scaffolding for
growing an N# parser slice-by-slice against the C# parser.

## 2026-06-06 — Lexer real-corpus dogfood parity (108 real .nl files) + CommentsInto benchmark

**What:** Two consolidation slices proving the now-complete N# lexer on real code.

1. **Real-corpus parity.** Extended `LexerTokenKindScanner_ProjectCompilesAndMatchesProductionLexer`
   to run the COMPLETE N# lexer (`TokenizeMetadataWithIndentationInto` + `CommentsInto`) against the C#
   production lexer (`Lexer.Tokenize()` / `Lexer.Comments`) over **every real `.nl` file** — 81 in
   `examples/` + 27 dogfood compiler-service kernels = **108 files**, including the systems source the
   compiler is written in (lifetimes, `scoped`/`unsafe`, raw/interpolated strings, comments,
   indentation). Full token-stream parity (kind/start/valueLength/line/column) AND comment-trivia
   parity hold on all 108 — the strongest available correctness evidence that the N# lexer matches C#
   on the code that matters. (This is the "use the compiler on itself to ensure correctness" mandate.)

2. **CommentsInto benchmark** (`CompilerServiceLexerCommentBenchmarks`, see
   [`compiler-benchmark-metrics.md`](compiler-benchmark-metrics.md)): N#'s zero-alloc comment scan vs
   C#'s tokenize-byproduct comment collection — 4.7× representative (0 B vs 33.9 KB), 18× large
   (0 B vs 10.7 MB). Framed honestly there (C# has no dedicated comment scanner).

**Status:** the N# lexer is feature-complete AND validated correct on the real compiler/example corpus.
The remaining self-host work is the large subsystem migration (parser → N#, consuming N# tokens
in-assembly) needed to actually delete the `*DogfoodAdapter` bridge — a multi-slice Phase 2/3 effort.

## 2026-06-06 — Phase 1 lexer: comment-trivia collection (N# lexer feature-complete vs C#)

**What:** Added the `CommentsInto` N# kernel — the last lexer feature gap. The C# `Lexer.Tokenize`
collects line/doc/block comments into `Lexer.Comments` (consumed by the formatter) while excluding them
from the token stream. `CommentsInto` reproduces it exactly: for each comment it records line, column,
start offset, length, and `isMultiLine` (1 = block `/* */`, 0 = line `//` or doc `///`). C#'s stored
text is the full span for line/doc comments and `"/*" + inner + "*/"` for block comments — both equal
`end - start`, so `length` = `end - start` uniformly. The kernel mirrors `TokenizeMetadataInto`'s token
dispatch (consuming string / raw-string / char / lifetime / number / identifier / operator runs as
units), so a `//` or `/*` INSIDE a literal is never misread as a comment and line/column tracking
through multi-line raw strings stays exact.

**Verified:** `AssertCommentsLikeProductionLexer` compares `CommentsInto` to `new Lexer(src).Comments`
(line/column/start/length/isMultiLine) on a dedicated `commentSource` (line + doc + single-line block +
multi-line block + trailing comment with no final newline + `//`/`/*` inside string and char literals
that must NOT be collected) plus the representative/metadata/source/lifetime corpora. Targeted test
green.

**Milestone — the N# lexer is now feature-complete vs the C# production lexer:** token kind, source
position (start/line/column), value length, indentation braces, Unicode classification, lifetimes,
malformed-number Unknown tokens, AND comment trivia all match `Lexer.Tokenize()`/`Lexer.Comments`.
Token-text is host-derivable from start+length (not a kernel gap). The Phase 0/1 lexer beachhead's
correctness work is done; what remains for the lexer is the **architecture** (Phase 2): an N#-native
Token representation + an in-assembly N#→N# consumer (parser) so the `*DogfoodAdapter` delegate
boundary can actually be deleted — the dogfood kernels remain behind that bridge until their caller is
also N#.

## 2026-06-06 — Phase 1 lexer: malformed-number Unknown tokens (raw-tokenizer kind-stream parity complete)

**What:** Closed the last raw-tokenizer kind divergence — malformed numbers. The C# `ReadNumber`
emits an `Unknown` token (137) for: a `0x`/`0b` prefix with no valid digit immediately after (a leading
`_` counts as "no digit", `Lexer.cs:592/614`), a second decimal point (`Lexer.cs:650-659`), and an
exponent `e`/`E[+/-]` with no following digit (`Lexer.cs:681-684`). The N# `ScanNumberInfo` had no
error path — it returned `IntLiteral`/`FloatLiteral` and (for a leading `_` after `0x`/`0b`)
over-consumed the span. Added the four error branches: `ScanNumberInfo` now returns a kind-`3` sentinel
(Unknown) with the exact span C# consumes, and the two metadata/kind callers map `3`→`137`. Because
the error branches return C#'s consumed span and `NumberValueLength` counts non-`_` chars, the Unknown
token's value text/length matches C#'s `sb` automatically (`1_e'`→"1e", `0x`→"0x", `1.2.3`→"1.2.3").

**Cleanup:** consolidated the duplicate number scanner — `TokenizeCount` now uses
`ScanNumberInfo(...) >> 2` for the end offset, and the redundant `ScanNumber` function was removed
(single source of truth for number consumption).

**Coverage completion (honest accounting):** also added `indentLifetimeSource` (the indentation-style
lifetime corpus the `5c793e57` entry claimed to restore but missed) and composed-path asserts for the
flat lifetime/unicode/char-literal/malformed-number corpora — closing the two coverage gaps from the
earlier agent-revert incident.

**Verified:** `malformedNumberSource` (`0x`, `0b`, `1e`, `1.2.3`, `0x_F`, `1e+`) asserted across all
three raw tokenizers + the composed path vs `Lexer.Tokenize()` (kind/start/valueLength/line/column +
count). Targeted test green. With this, **N# raw-tokenizer kind-stream parity with the C# production
lexer is complete** — identifiers, keywords (incl. systems), literals (incl. raw/interpolated/char),
lifetimes, operators, delimiters, comments-excluded, indentation braces, Unicode classification, and
now malformed-number Unknown tokens all match.

**Remaining lexer gaps:** comment-trivia collection for the formatter (`Lexer.Comments`) and token-text
materialization (host-derivable from start+length) — neither is a *kind/position* parity gap.

## 2026-06-05 — Phase 1 lexer: Unicode character classification + char-literal fix

**What:** Closed the last raw-tokenizer character-classification gap and restored lost test coverage.

1. **Unicode classification.** The scanner's char helpers were ASCII-only; the C# lexer uses the BCL
   Unicode predicates throughout (`char.IsDigit` 336/631/…/757, `char.IsLetter` 342/905,
   `char.IsLetterOrDigit` 567/922/926/942, `char.IsWhiteSpace` 912/1084). Rewrote
   `IsWhitespaceExceptNewline` → `char.IsWhiteSpace(ch) && ch != '\n' && ch != '\r'`,
   `IsIdentifierStart` → `ch == '_' || char.IsLetter(ch)`, `IsIdentifierPart` →
   `ch == '_' || char.IsLetterOrDigit(ch)`, `IsDigit` → `char.IsDigit(ch)`, and the lifetime-lookback
   whitespace → `char.IsWhiteSpace(ch)`. `IsHexDigit` stays `IsDigit || a-f || A-F` (now matching C#'s
   `char.IsDigit(c) || a-f || A-F`). **The C# lexer has no ASCII fast path, so calling the same BCL
   predicates is BOTH exact-parity AND the same cost** — no perf regression vs C#.
2. **Char-literal `'\<CR>` fix.** `ScanCharLiteral` consumed the escaped char unconditionally; C#
   `ReadCharLiteral` guards it with `!IsAtLineBreak()` (Lexer.cs:882). Added the `\n`/`\r` guard so a
   backslash at end-of-line leaves the line break to become a separate Newline token (pre-existing gap
   surfaced by the lifetime slice's fuzz).

**Audit answer (resolved):** the open question "do `char.IsWhiteSpace`/`IsLetter`/`IsLetterOrDigit`/
`IsDigit` compile in the dogfood kernel?" is **YES** — verified by compiling the dogfood project with
them and passing the full ASCII corpus. This also retroactively confirms the lifetime port could have
used them; the ASCII helpers it used are exactly equivalent on ASCII, and now share the Unicode upgrade.

**Verification:** added `unicodeSource` (Unicode-letter identifiers `café`/`ident١`, NBSP U+00A0 as an
inline separator splitting `x y`, Arabic-Indic digit U+0661 in identifier-continuation) asserted via
all three raw tokenizers + the composed path, and `charLiteralLineBreakSource` (`'\<CR>`) — all match
`Lexer.Tokenize()`. Targeted test green; gate green.

**Test-coverage restoration (honest accounting):** the prior lifetime slice's commit `dc42b0f0` was
SUPPOSED to add `lifetimeSource`/`indentLifetimeSource` parity corpora, but a concurrent adversarial
review agent (running in the main repo, not an isolated worktree) ran `git checkout HEAD -- tests/...`
to revert its own scratch edits — which silently wiped my uncommitted lifetime corpora before the
commit. The lifetime KERNEL code committed fine and was independently validated by the review's
differential-fuzz harness, but the corpora were missing from `dc42b0f0`'s test. This slice restores
`lifetimeSource` (all contexts: `<'a>`, `<'a,'b>`, `scoped 'a`, `returns 'a`, char-literal non-lifetimes)
+ `indentLifetimeSource`. Process fix recorded: verify/review agents must be read-only or worktree-
isolated, and never commit while they run against the shared tree.

**Remaining lexer gaps:** a number-scanner exponent/underscore divergence (`1_e'`-style, surfaced by
fuzz — separate from classification; **closed in the next-dated entry above**); then comment-trivia
(`Lexer.Comments`) + token-text materialization for a full production N# lexer.

## 2026-06-05 — Phase 1 lexer: lifetime tokens ported to N# (blocker closed)

**What:** Closed the lifetime-token blocker from the prior entry's audit. The C# lexer
(`Lexer.cs:325-328`, `IsLifetimeStart`/`IsLifetimeContext`/`ReadLifetime` at `Lexer.cs:903-958`) emits
a single `Lifetime` token (ordinal 142) — instead of a char literal — when an apostrophe begins an
identifier (next char letter/`_`, and the char after that is not a closing quote, so `'a` vs the char
literal `'a'`) AND it sits in a lifetime *context*: the nearest preceding non-whitespace char is `<`
or `,`, or the identifier word immediately before it is `scoped`/`returns`. The N# scanner had no
lifetime handling, so it lexed `'a` as a char literal — wrong kind, and for multi-char lifetimes
(`'a1`) even the wrong token *count*.

**Port** (`CompilerServices/LexerTokenKindScanner.nl`): added `IsLifetimeStartAt`,
`IsLifetimeContextAt`, `MatchesScopedOrReturns`, `ScanLifetime`, and `IsAsciiWhitespace`, mirroring the
C# methods statement-for-statement, and inserted a lifetime branch **before the char-literal branch in
all three tokenizers** (`TokenizeKindsInto`, `TokenizeMetadataInto`, `TokenizeCount`) so every parity
path agrees. The backward context scan (skip whitespace incl. newlines → `<`/`,` early-true → else read
the preceding identifier word and match `scoped`/`returns`) reuses the scanner's existing ASCII
classification helpers (`IsIdentifierStart` ≡ `char.IsLetter||'_'`, `IsIdentifierPart` ≡
`char.IsLetterOrDigit||'_'`, `IsAsciiWhitespace` ≡ `char.IsWhiteSpace` — exact on ASCII), keeping the
scanner uniformly ASCII; the scanner-wide ASCII-vs-Unicode gap (next slice) will upgrade all helpers
together. The systems-keyword recognition landed in the prior slice is what makes the `scoped` context
word resolve correctly.

**Verified:** added a brace-style `lifetimeSource` corpus (so `InsertIndentationBraces` is a no-op and
it exercises ALL three raw tokenizers + the composed path against `Lexer.Tokenize()`) mixing every
lifetime context (`<'a>`, `<'a, 'b>`, `scoped 'a`, `returns 'a`) with char literals that must STAY char
literals (`'x'`, `'\n'`, escaped quote, and `name 'a` whose preceding word is not scoped/returns), plus
an indentation-style `indentLifetimeSource` (lifetimes + virtual braces + a char literal in one stream).
Full token-stream parity (kind/start/valueLength/line/column + count) holds; targeted test green. An
adversarial differential-fuzz workflow (compiled dogfood DLL vs the real C# `Lexer.Tokenize()` over
many ASCII lifetime/char-literal inputs) confirmed no divergence.

> **Correction:** these two corpora were LOST from this commit — a concurrent review agent reverted the
> test file before commit, so `dc42b0f0` shipped the lifetime kernel + an under-covered test. The
> corpora were RESTORED in the next-dated entry above. The kernel itself was independently validated by
> the differential-fuzz harness, so the port was correct; only the in-suite regression coverage lapsed.

**Remaining lexer gaps:** (a) ASCII-vs-Unicode character classification (whitespace/digits/letters);
(b) a pre-existing `ScanCharLiteral` edge case surfaced by this slice's adversarial fuzz — a char
literal whose body is a backslash immediately followed by a line break (`'\<CR>`): C# `ReadCharLiteral`
guards the escaped-char consumption against EOL, the N# `ScanCharLiteral` does not (pre-existing, from
commits d636e3a2/ff921348, NOT a lifetime-port regression). Both fold into the char-classification /
char-literal parity slice. Then comment-trivia + token-text for a full production N# lexer.

## 2026-06-05 — Phase 1 lexer: indentation tokens + systems-keyword recognition ported to N#

**What:** Two cohesive N# lexer kind-stream parity improvements, plus an adversarial audit that
surfaced (and this slice partly closes) several pre-existing raw-tokenizer gaps.

1. **Indentation tokens.** Ported `Lexer.InsertIndentationBraces` (`src/NSharpLang.Compiler/Lexer.cs:167-266`)
   — the virtual `{`/`}` insertion for indentation-style (brace-free) source — to N#. Until now the N#
   scanner emitted only the *raw* token stream (`TokenizeMetadataInto`), so metadata parity was pinned
   only on explicit-brace corpora where `InsertIndentationBraces` is a no-op.
2. **Systems keywords.** `KeywordKind` now recognizes the five systems keywords the C# lexer emits
   (`Lexer.cs:97-101`): `alloc`→`Alloc(143)`, `allow`→`Allow(144)`, `stackalloc`→`Stackalloc(145)`,
   `unsafe`→`Unsafe(146)`, `scoped`→`Scoped(147)` — appended to the length-gated first-char dispatch,
   so near-miss prefixes (`all`/`scope`/`alloca`) stay `Identifier`. Previously the scanner returned
   `Identifier(0)` for these, so it could not even tokenize the dogfood's own systems-N# source.

**Adversarial audit:** a 4-agent workflow (line-by-line + edge-case + metadata lenses + synthesis,
with 400k-program structural fuzzing and a differential harness against the compiled C# lexer)
confirmed the **indentation post-pass port is faithful** (zero divergences across all fuzz + 92
hand-built cases) and drove out the gap list below. Systems keywords are closed here; the rest are the
next slices.

Added two N# kernels to `CompilerServices/LexerTokenKindScanner.nl`:
- `InsertIndentationBracesInto(...)` — a faithful, zero-alloc (caller-owned-buffer) port of
  `InsertIndentationBraces`, operating purely over the raw metadata arrays
  (kind/start/valueLength/line/column). It tracks an indent stack, explicit-brace depth, and
  paren/bracket depth; opens a virtual `LeftBrace` (ordinal 129) on indentation increase and closes
  virtual `RightBrace` (130) tokens on dedent and at EOF, with the base-indent capture, the
  `Math.Max(0, …)` clamps, the "halfway dedent pops without re-opening" stack walk, and the
  brace-vs-indentation suppression rules matching the C# source statement-for-statement. A virtual
  brace's start offset is derived as `tokenStart - (tokenColumn - 1)` (the trigger token's line start)
  with column fixed to 1 — exactly what the parity test's `TokenStartFromLineColumn` expects.
- `TokenizeMetadataWithIndentationInto(source, …)` — the composed entry: tokenize raw, then run the
  brace post-pass, producing the exact stream `Lexer.Tokenize()` yields on any source **whose tokens
  are already correctly recognized by the raw scanner** (i.e. excluding the gaps below).

**Verification (parity, not a perf-routing slice):** extended
`LexerTokenKindScanner_ProjectCompilesAndMatchesProductionLexer` with
`AssertTokenMetadataWithIndentationLikeProductionLexer`, asserting full token-stream parity (kind +
start + valueLength + line + column, count included) against `new Lexer(src).Tokenize()`. Coverage:
the composed entry is first proven a correct **superset** on all four existing explicit-brace corpora
(it must equal the raw stream there), then proven on indentation-style corpora that genuinely trigger
insertion — simple single indent, nested indents with multi-level dedent and sibling blocks,
globally-indented source with interior blank lines, paren-continuation + explicit-brace suppression,
CRLF endings, tab indentation, an inconsistent "halfway" dedent, and degenerate empty / whitespace-
only inputs. The count assertion makes the tests non-trivial: if the port inserted nothing while C#
did (or vice-versa) the token counts would differ and the test would fail. For systems keywords, added
a `systemsKeywordSource` corpus asserted three ways (raw kinds, raw metadata, composed) that exercises
each of the five keywords plus near-miss prefixes (`all`/`scope`/`alloca`/`scopes`/`unsaf` must stay
`Identifier`). Targeted test passes; full `CompilerDogfoodProjectTests` class green, including the
`Newline == 136` ordinal-layout pin. Full `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` gate run
for the commit.

**Language/compiler findings (Phase 0 audit):** the port compiled on today's N# with **no new gaps** —
confirming the audit's "lexer port is feasible" finding extends to the control-heavy indentation
logic. Specifically exercised and confirmed working: an 11-array-parameter function signature
(previously the widest kernel was 7 arrays), intra-assembly N#→N# calls with internal `new int[](…)`
allocation, `bool` locals with reassignment and logical `!`/`&&`/`||`, nested `while` with `continue`,
mid-loop `return`, and `else if` chains. No principled compiler change was required this slice.

**Architecture note (honest framing):** this is a correctness/parity slice that **advances the N#
lexer's kind-stream** (indentation post-pass), not a production-routing slice. Per the
boundary-profiling finding, the lexer adapter bridge cannot be deleted until its *caller* (the parser)
is also N# and the call inlines in-assembly; routing tokenization through this kernel today would only
add another ~1.2 ns delegate boundary. The indentation logic is written in the fast canonical style
(counted loops, manual int stack, zero per-call allocation in the pure kernel) so it is ready to be
the production lexer once the in-assembly N#→N# parser path lands (Phase 2). No adapter added/removed.

**Audit findings (pre-existing raw-tokenizer parity bugs, NOT in the new indentation code; latent
because no in-tree corpus exercised them):**

- ✅ **Systems keywords (blocker) — CLOSED this slice.** `KeywordKind` returned `Identifier(0)` for
  `alloc`/`allow`/`stackalloc`/`unsafe`/`scoped`; now emits `143/144/145/146/147`. Empirically
  confirmed against the compiled C# lexer and pinned by `systemsKeywordSource`.

**Remaining gaps (the immediate next slices):**

> ✅ Gap 1 (lifetime tokens) was closed in the next-dated entry above.

1. **Lifetime tokens (blocker) — CLOSED (see entry above).** `TokenizeMetadataInto` has no lifetime handling; C# `NextToken`
   (`Lexer.cs:325-328`) calls `IsLifetimeStart()`/`ReadLifetime()` (`Lexer.cs:903-960`) to emit a
   single `Lifetime(142)` token (e.g. `,'a`→`Lifetime`, `,'b1`→`Lifetime`). `IsLifetimeStart` is
   context-sensitive: apostrophe, next char letter/`_`, char-after-next not `'`, AND the nearest
   preceding non-whitespace char is `<` or `,` or the word `scoped`/`returns`. The N# scanner instead
   lexes `'a` as a char literal, diverging on kind AND count. Fix: port `IsLifetimeStart`/`ReadLifetime`
   into the scanner before the char-literal branch — its own slice given the source lookback. **Note:**
   the systems-keyword recognition landed here is a prerequisite for the `scoped`/`returns` lookback.
2. **ASCII-vs-Unicode character classification (major).** The scanner's `IsWhitespaceExceptNewline`,
   `IsDigit`, and `IsIdentifierStart` are ASCII-only, but the C# lexer uses the Unicode-aware BCL
   predicates `char.IsWhiteSpace` (`Lexer.cs:1084`), `char.IsDigit` (`Lexer.cs:336`), and
   `char.IsLetter` (`Lexer.cs:342`). So non-ASCII whitespace (NBSP/NEL/U+2028/U+2029/U+2000–U+200A/
   U+202F/U+205F/U+1680/U+3000 — note C# treats U+0085/U+2028/U+2029 as inline whitespace, not line
   breaks, since `IsAtLineBreak` is `\n`/`\r` only), Unicode letters in identifiers, and Unicode
   decimal digits all diverge (the scanner emits `Unknown(137)` / wrong kinds/columns/count). Fix as
   one coherent slice: ASCII fast-path + BCL-predicate fallback for ch > 127 in all three helpers
   (parity guaranteed by sharing the BCL predicate), with Unicode corpora. **Open audit question:**
   confirm the kernel compile path supports `char.IsWhiteSpace`/`char.IsLetter`/`char.IsDigit` interop
   (the Phase 0 probe verified `char.IsDigit`/`char.IsLetter` standalone; no dogfood kernel calls them
   today — they all hand-roll ASCII checks).
3. **Comment-trivia + token-text** for the formatter (`Lexer.Comments`) and token-text materialization
   (derivable from start+length by the host) — the last pieces to a full production N# lexer.

## 2026-06-05 — Consolidation: dogfood work merged onto `systems-language`

**What:** Consolidated all scattered dogfood worktrees/branches onto the canonical working branch
`systems-language` (which carries the separate "Systems N#" line: memory pools, zero-copy proofs,
ref/lifetime safety, source generators, etc.). Previously the dogfood self-hosting work lived only on
`codex/compiler-dogfood-benchmarks` and a fan of unit branches.

Merged in:
- `nsharp-dogfood-profiling` — the real integration branch: canonical dogfood base (145 commits) +
  accepted/routed units **1** (formatter import ordering), **3** (ProjectFile source filtering),
  **5** (ILCompiler overload selection) + rejection-evidence units **2** (formatter safety scan),
  **4** (analyzer overload-signature distinctness), **6** (declared-type exact-name lookup) + all
  three design docs + the `DogfoodBoundaryOverheadBenchmarks` decomposition benchmark.
- `nsharp-dogfood-unit-7-code-intel-audit` — the audit-only doc section.

**Routed (production) kernels carried in** (unchanged numbers, see metrics doc):
- Formatter import ordering — 6.2× representative / 20.2× large, 0 B.
- ProjectFile source filtering — 25.8× / 26.9×.
- ILCompiler overload selection — 11.3× / 10.9×, 0 B (runs on every declared-method/ctor call).

**Conflicts reconciled (8 core files)** — preserving BOTH systems-language semantics and dogfood
routing:
- `ILCompiler.cs`: kept profiling's routed compact-candidate overload ranking
  (`SelectBestDeclaredMethodCandidate`) **and** systems-language's `HasRuntimeTypeParameters` generic
  detection; kept systems-language's `FinalizeTopLevelEnumTypes` (re-registers baked enums in
  `_enumTypes`/`_typeKeys`) **and** the dogfood `OrderTypeBuildersByDescendingTypeKeyDepth` helper;
  kept systems-language's `EmitExpressionStatement`/`TryEmitAssignmentStatement` lowering (a superset
  of profiling's inline assignment-discard); combined profiling's member-load null-guard with the
  correct `memberOwnerType`.
- `Program.cs`: preserved systems-language's `--systems` template flag on top of profiling's
  `GetFirstPositionalArg` refactor.
- `Program.Backends.cs`: dropped profiling's now-dead `ValidateStrictLintDiagnostics` (systems-language
  moved strict-lint into the compiler via `CompileToIlAssembly(validateStrictLint: true)`).
- `CompilationStubEmitter.cs`, `Analyzer.cs`, `memory/README.md`, `runTest.ts`: additive.

### Limitation found + principled fix: TokenType ordinal coupling

**Symptom:** After a clean (compiling) merge, the full gate hit **63 failures** — formatting gate,
unit tests, example builds, IL verification — all braced N# source failing to parse with
"Unexpected token newline in expression."

**Root cause:** The systems-language line inserted six token types (`Lifetime`, then
`Alloc`/`Allow`/`Stackalloc`/`Unsafe`/`Scoped`) into the **middle** of the `TokenType` enum. The
production-routed dogfood kernel `ParserTokenCompactionIndicesInto`
(`src/NSharpLang.Compiler.Dogfood/CompilerServices/LexerTokenKindScanner.nl`) — reached from the
`Parser` constructor via `NSharpCompilerDogfoodAdapter.TryCompactParserTokens` — filters newline
tokens by the **hard-coded integer ordinal 136**. The insertions shifted `Newline` from 136 to 142,
so the kernel filtered the wrong token type and left stray newlines in the parser's token stream.
This is the dogfood kernels' ordinal-coupling fragility surfacing through a real enum change.

**Fix (smallest principled change):** Restore the kernels' ordinal contract by appending the six new
token types at the **end** of `TokenType` (they are referenced only by name in C#, never by ordinal).
Documented the load-bearing ordering on the enum, and added an explicit guard test
`ParserTokenCompactionParityRespectsTokenTypeLayout` pinning `(int)TokenType.Newline == 136` so any
future mid-enum insertion fails loudly at the C# test layer instead of silently in production.

**Follow-up debt (tracked, not yet done):** The dogfood `TokenType`-ordinal kernels remain coupled to
a fixed enum layout. The more robust long-term fix is to pass ordinal constants (e.g. the newline
kind) into the kernels as data rather than baking them — decoupling kernels from enum layout entirely.
Deferred to avoid widening the binding/benchmark/test surface during consolidation; the guard test +
enum comment prevent silent recurrence in the meantime.

**Verification:** `format --project examples --check` → "All files are properly formatted"; targeted
re-run of the previously-failing classes (`CompilerDogfoodProjectTests`, `StructCopyEliminationTests`,
`AnalyzerBindingMapTests`) → 42/42 pass.

### Limitation found + principled fix: short-circuit `&&`/`||` codegen vs C#

**Symptom:** After the ordinal fix the full gate had exactly one remaining failure — the Systems
BenchmarkDotNet gate (`SystemsFastGateBenchmarks`), `HotResultCombinations` scenario, N# at
~1.01× the C# baseline (zero-tolerance gate; N# must be ≤ C#).

**Root cause (verified by emitted-IL diff vs pre-merge `84dda83`):** the merge correctly brought in
the dogfood branch's short-circuit `&&`/`||` lowering (commit `b4a873e "Fix IL primitive operator
semantics"`, with the `ILCompiler_LogicalOperatorsShortCircuit` test). Pre-merge systems-language
lowered `&&`/`||` **eagerly** (`clt; cgt; or; brfalse` — one branch) which is a *latent correctness
bug* (the right operand is always evaluated). The IL diff showed only `scanDigits`,
`scanAndChecksumDigits`, `copyDigits` changed — each a hot loop with `if value < 48 || value > 57`.
The materializing short-circuit helper (`EmitLogicalOr`) added `ldc.i4.0`/`ldc.i4.1`/`br`
boolean-materialization and a second branch; RyuJIT compiles the equivalent C# range check
(`value < 48 || value > 57`) to a single branch, so correct-but-two-branch N# lost by ~1–2%.

**Fix (compiler self-improvement — explicitly in scope):** added a short-circuiting
`EmitConditionBranch(condition, target, branchIfTrue)` used by `EmitIf`/`EmitWhile`/`EmitFor`. It
lowers `&&`/`||`/`!` to branches taken directly against the target labels (no boolean
materialization), and:
- **fuses** integer relational comparisons with their branch into one
  `blt`/`bgt`/`ble`/`bge`/`beq`/`bne.un` opcode (gated to integral operands, where the relational
  inverse is exact — no NaN/unordered hazard);
- **eagerly** evaluates `a && b`/`a || b` as `left; right; and/or; br` (a single branch) ONLY when
  both operands are provably pure and non-throwing (an integer comparison whose leaves are integer
  locals/params or integer/char literals) — observably identical to short-circuit but one branch
  instead of two, matching the JIT-folded C# shape.

Side-effecting operands (calls, member access, indexing, division) still short-circuit, so
`ILCompiler_LogicalOperatorsShortCircuit` and the operator-matrix/IL-shape suites pass (100/100 on
the targeted run). After the fix the emitted IL for the hot loops is *smaller* than pre-merge's, and
`HotResultCombinations` measures **0.99×** (N# faster), so the benchmark gate passes. This is a net
codegen quality improvement for every `if`/`while`/`for` condition in the language.

**Verification:** Systems BenchmarkDotNet gate passes (all 6 scenarios ≤ 1.00, HotResultCombinations
0.99); 100/100 targeted short-circuit/operator/control-flow tests pass. Full
`VSCODE_TESTS=skip ./scripts/test-all.sh --commit` re-run pending.

---

## 2026-06-05 — Lever 3 codegen: `array.Length` → `ldlen` for SZ arrays

**What:** `EmitMemberAccess`/`EmitMemberLoadValue` lowered `array.Length` on a single-dimension
zero-based array (`IsSZArray`) to a non-virtual `call Array.get_Length()`. Replaced with the canonical
`ldlen; conv.i4`. Strings, `Span<T>`, and multidimensional arrays are unaffected (not `IsSZArray`).

**Why (boundary-profiling Lever 3):** `ldlen` is the form the JIT's bounds-check elimination
pattern-matches, so an `array.Length`-bounded counted loop (`for i := 0; i < a.Length; i++ { a[i] }`)
now emits the same shape C# does and the JIT elides the `ldelem` bounds check.

**Evidence (direct micro-benchmark, 4096-int sum, 2M iterations, identical checksums):**

| N# array.Length form | N# / C# ratio | IL size (`sumArray`) |
|----------------------|---------------|----------------------|
| `call get_Length` (before) | 1.003× (slightly slower) | 33 B |
| `ldlen; conv.i4` (after)   | **0.999× (parity)** | 30 B |

Modest but real: moves the canonical counted array loop from marginally-slower to parity with C#,
meeting the "never slower than C#" bar, with smaller and canonical IL. 537 array/length/span/string/
loop tests pass; parity is guaranteed (same value). Benefits every `array.Length`-bounded loop,
including the array-heavy dogfood kernels.

## 2026-06-05 — Phase 0 audit kickoff: lexer feature surface + N# interop readiness

Per [`self-host-roadmap.md`](self-host-roadmap.md), began the language-completeness audit by scoping
the **lexer** beachhead (`src/NSharpLang.Compiler/Lexer.cs`, 1150 LOC). Its dependency surface:
`string` indexing, one `Dictionary<string,TokenType>` (keywords), `List<Token>` (output), 13
`StringBuilder` uses (token text), one `Stack`/indentation, 15 `char.Is*` calls, 14 `switch`, the
`Token` record, the `TokenType` enum. No LINQ.

**Finding — a correct lexer port is feasible on today's N#.** N#'s C# interop already covers every BCL
dependency. Verified by compiling AND running an N# probe that uses `new StringBuilder()` +
`Append`/`ToString`, `new Stack<int>()` + `Push`/`Pop`, `char.IsDigit`/`char.IsLetter`, and
`new Dictionary<string,int>()` + indexer + `ContainsKey` (output `hi 2 True True True`). Examples
already use `List<T>`, nested `Dictionary<...>`, collection expressions, records, enums, and `switch`.

**Open work for the port (not feasibility, but the "super fast" bar):**
- Decide BCL collections (mechanical, allocates) vs **systems-native pooled/zero-alloc** `Token`/
  `TokenStream` for the hot path — the latter is what makes the migrated lexer dramatically faster.
- Confirm full trivia / indentation-token / diagnostic / source-position parity in N#.
- The keyword table: prefer the existing first-character dispatch (already proven in the dogfood
  scanner) over a `Dictionary` lookup on the hot path.

**Finding 2 — the existing N# lexer scanner is production-close.** `LexerTokenKindScanner.nl`
(1573 LOC) already emits full per-token metadata (kind, start, value length, line, column) for
identifiers, separated int/hex/binary/float numbers, string/raw/interpolated/char literals, the full
operator set, and keywords, and it excludes comments from the stream exactly as the C# lexer does.
Pinned with a new representative-corpus parity test in `CompilerDogfoodProjectTests`
(`AssertTokenMetadataLikeProductionLexer`) over a single source that combines line/doc/block comments,
string + interpolated + char literals, separated numeric literals, a wide operator set, and keywords —
it matches the production `Lexer.Tokenize()` token stream exactly (count + kind + start + length +
line + column), and the compaction parity holds too.

**Remaining gaps to a full production N# lexer** (narrower than first thought): indentation-token
insertion for indentation-style (brace-free) source, comment-trivia collection for the formatter
(`Lexer.Comments`), and token-text materialization (derivable from start+length by the host). Token
*kind/position* parity — the hard part — is already met on realistic code.

Next slice: cover indentation-token insertion in the N# scanner (the main remaining kind-stream gap),
or stand up the N#-native pooled `Token`/`TokenStream` so the parser can consume N# tokens directly
(removing the host materialization boundary). Record any language gap here and close it principled.

> **Update (newest entry above):** indentation-token insertion is now DONE and verified faithful.
> BUT the adversarial audit of that slice surfaced three pre-existing raw-tokenizer parity gaps
> (systems keywords, lifetime tokens, Unicode whitespace) that the old "kind/position parity is
> already met on realistic code" claim missed — they were latent only because no corpus exercised
> them. See the newest entry's "Gaps surfaced" list; those are the immediate next slices.

## Bootstrap coverage

- **0%** — no compiler source is yet compiled by the N# compiler itself. The dogfood kernels are
  N#-authored compiler *services* compiled through the normal `NSharpLang.Sdk` path and bound via the
  `*DogfoodAdapter` delegate boundary; this is the pre-bootstrap stage. The endgame (per the boundary
  profiling doc) is removing those delegate boundaries via in-assembly N#-to-N# calls.

## Adapters (debt to shrink toward zero)

- `NSharpCompilerDogfoodAdapter`, `NSharpCodeIntelligenceDogfoodAdapter`,
  `NSharpPerformanceDogfoodAdapter`, `NSharpCliDogfoodAdapter` — all still present as temporary
  transition boundaries. None removed yet. Each routed kernel still crosses the ~1.2 ns
  delegate-dispatch + bounds-check floor documented in the boundary profiling doc.
