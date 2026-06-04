# Compiler Dogfood Rewrite Plan

Status: active goal
Updated: 2026-06-04

This document tracks the rewrite of the N# compiler, compiler services, and CLI tooling in N#.
It is not a straight port. The goal is to use the systems-oriented parts of N# to make the
toolchain materially faster than the current C# implementation while exposing the language gaps
that prevent that result.

## Acceptance Standard

The rewrite is complete only when current evidence proves all of these:

1. Every production compiler, compiler-service, and CLI function has an N# implementation or a
   documented, justified CLR/BCL host boundary.
2. The N# implementation is behaviorally equivalent to the current C# implementation on the
   existing tests and targeted parity tests for that function.
3. Each measured function is at least 5x faster than the C# counterpart on a matched BenchmarkDotNet
   benchmark. The benchmark must report allocation counts and must use the same input corpus for
   both implementations.
4. The compiler and SDK can build the N# implementation through the normal `NSharpLang.Sdk`
   project path.
5. CLI and language-server surfaces use the N# implementation after parity and speed gates pass.
6. Documentation names any remaining boundary explicitly. No "dogfooded" claim is valid while a
   production compiler/service/CLI path still routes through unexplained C# code.

## Evidence Model

The dogfood evidence is separate from the existing runtime-code benchmark corpus. Existing
benchmarks prove that N# can emit fast user code for selected language patterns. Dogfood benchmarks
prove that the compiler and toolchain services themselves are faster after being rewritten in N#.

For each function family, land these artifacts together:

1. **Inventory:** source files and callable functions included in scope.
2. **C# baseline benchmark:** the current C# implementation over a representative corpus.
3. **N# candidate benchmark:** the N# implementation over the same corpus.
4. **Parity tests:** targeted tests plus existing suite coverage proving identical externally
   visible behavior.
5. **Speed gate:** C# mean divided by N# mean is `>= 5.0`; lower results stay in development and
   are not accepted as rewritten.
6. **Swap evidence:** proof that the production CLI/compiler/LSP path calls the N# implementation.

Benchmark command shape:

```bash
dotnet run -c Release --project benchmarks -- --filter '*CompilerServiceLexer*'
dotnet run -c Release --project benchmarks -- --filter '*SourceTextLine*'
dotnet run -c Release --project benchmarks -- --filter '*CompilerServiceCodeIntelligence*'
```

Current lexer dogfood benchmarks:

- `CompilerServiceLexerBenchmarks` records the current full C# `Lexer.Tokenize()` implementation on
  representative and large generated corpora. A production N# lexer replacement must add a matching
  token-producing benchmark over those exact corpora and prove token-sequence parity before any
  lexer rewrite claim is accepted.
- `CompilerServiceLexerScannerBenchmarks` is an early scanner-only benchmark. It loads an N#
  count-only scanner and pairs it with an equivalent C# count-only scanner. Benchmark setup verifies
  both scanners return the same token count as the real C# lexer on both corpora. This is useful
  pressure for N# emitted hot-loop quality, but it is not a production lexer replacement because it
  does not produce token objects, trivia, indentation tokens outside the explicit-brace corpus, or
  diagnostics.
- `CompilerServiceLexerTokenKindBenchmarks` is the next stricter dogfood step. It loads an N#
  scanner that emits compact `TokenType` ids into an `int[]` and verifies the full token-kind
  sequence against the current C# lexer on both corpora. It still is not a production lexer
  replacement because it does not emit token text, source positions, comment trivia, diagnostics, or
  general indentation-token behavior.
- `CompilerServiceLexerReusableTokenKindBenchmarks` measures the next production-shaped API:
  `TokenizeKindsInto(source, buffer)` writes token kinds into caller-owned storage and returns the
  filled count. This removes the known exact-array copy from the hot path while still verifying the
  full token-kind sequence against the current C# lexer on both corpora.
- `CompilerServiceLexerMetadataBenchmarks` extends the caller-owned-buffer shape to token kind,
  source start, token value length, line, and column. It compares those five metadata streams against
  the current C# `Lexer.Tokenize()` result on the same corpora. This is closer to the compact token
  table needed by a production rewrite, but it still does not model comment trivia, diagnostics, or
  indentation-token insertion for indentation-only source.

The lexer scanner candidate now lives in `src/NSharpLang.Compiler.Dogfood` as an ordinary N# SDK
project. Benchmarks embed `CompilerServices/LexerTokenKindScanner.nl` as source input and compile it
through the real N# lexer/parser/IL compiler before binding delegates. `CompilerDogfoodProjectTests`
also compiles the dogfood project from `project.yml` and invokes the emitted methods against the
production lexer token-kind sequence plus compact metadata streams. This proves the first candidate
is no longer benchmark-only C# data, but it does not yet satisfy the production swap requirement.

Dry-run evidence on 2026-06-03 (`--job Dry`) showed the N# scanner compiling and passing parity
checks, with no per-operation managed allocations reported for the count-only scanner. The dry
timings were mixed: N# was slower on the small representative corpus and faster on the large
generated corpus. The token-kind scanner also passed sequence parity on both corpora. Its dry run
was faster than the current full C# lexer token-kind extraction on both corpora and allocated much
less memory, but still did not reach the required 5x speedup gate. Dry jobs are not acceptance
evidence.

The same dry run style for `CompilerServiceLexerReusableTokenKindBenchmarks` showed
`TokenizeKindsInto(source, buffer)` eliminating per-operation managed allocation on the N# path.
After replacing per-token helper emission, duplicate operator scanning, and generic string-literal
keyword checks with direct buffer writes, an encoded operator kind/width result, and first-character
keyword dispatch, the large generated corpus ran about 6.7x faster than the current C# lexer filling
a caller-owned kind buffer (1.00 ms vs 6.77 ms). The exact-array token-kind path also crossed the
large-corpus dry smoke threshold at about 6.4x (1.06 ms vs 6.85 ms). The representative corpus is
still much closer (97 us vs 124 us for the reusable-buffer path), so this is not full lexer
acceptance evidence and the benchmark remains a dry smoke run.

On 2026-06-03 the compiler lowerer learned a statement-context assignment path: assignment
expressions still return the assigned value when the value is consumed, but bare assignment
statements no longer reload that value only for an expression-statement pop. `AssignmentStatementIlShapeTests`
pins this shape with zero `pop` opcodes for local/indexed assignment statements and verifies nested
assignment expressions still return their assigned value. The dogfood lexer scanner also decodes its
packed operator kind/width with `>> 2` and `& 3` instead of `/ 4` and multiply/subtract. The updated
dry smoke run still showed the large generated reusable-token benchmark above the 5x smoke threshold
(992 us vs 6.82 ms, about 6.9x), but the representative corpus remained near parity (109 us vs
113 us). This is useful IL-shape progress, not lexer production acceptance.

The metadata-buffer dry run also passed parity on 2026-06-03. `TokenizeMetadataInto` reported zero
managed allocation and filled token kind, source start, value length, line, and column buffers. The
large generated corpus crossed the dry smoke threshold at about 7.0x faster than the current C#
lexer filling equivalent metadata buffers (992 us vs 6.99 ms), while the representative corpus was
only near parity (105 us vs 110 us). This is useful compact-token-table evidence, not acceptance
evidence.

The post-lowering dry metadata smoke run preserved parity and zero managed allocation. In that run
the large generated metadata path measured 1.17 ms vs 6.90 ms (about 5.9x) while the representative
corpus stayed near parity at 104 us vs 116 us. The next lexer work should therefore focus on reducing
fixed overhead on small/representative files and on a production compact-token table, not on claiming
the lexer rewrite gate is met.

Later on 2026-06-03 the reusable kind-buffer and metadata-buffer lexer paths collapsed numeric token
scanning from separate end-position and token-kind passes into one packed result (`end << 2 | kind`).
The dry reusable-token-kind smoke run reported zero managed allocation on the N# path, 92.29 us vs
115.54 us on the representative corpus (about 1.25x), and 1.045 ms vs 7.153 ms on the large generated
corpus (about 6.85x). The matching metadata-buffer dry smoke run also reported zero managed
allocation, 96.83 us vs 111.88 us representative (about 1.16x), and 1.018 ms vs 7.164 ms large
(about 7.04x). This improves the large lexer path and keeps small-file lexer overhead explicit; it is
still dry smoke evidence, not lexer acceptance.

`CompilerDogfoodProjectTests` now includes a production-keyword sweep plus a near-miss identifier
(`throws`) to pin the optimized keyword dispatch to the actual C# `Lexer.Keywords` behavior. It also
checks `TokenizeMetadataInto` against production token kind, source start, token value length, line,
and column metadata, including numeric separators and multiline comment line accounting.

Current source-text dogfood benchmarks:

- `CompilerServiceSourceTextLineBenchmarks` records the current C# `SourceTextLines.SplitLogicalLines`
  helper against an N# implementation that returns the same `string[]` result. The N# candidate
  avoids the current helper's whole-source replacement strings and allocates less memory, but dry
  smoke timings remain slower on the large mixed-newline corpus (407 us vs 332 us). This is parity
  evidence and allocation-pressure evidence only, not speed acceptance.
- `CompilerServiceSourceTextLineRangeBenchmarks` measures the lower-level line-map shape:
  `SplitLogicalLineRangesInto(source, starts, lengths)` fills caller-owned arrays with source
  ranges. The N# path reports zero per-operation managed allocation and, after switching separator
  search to `string.IndexOf`, the large mixed-newline dry smoke run is faster than the current C#
  split-then-copy baseline (228 us vs 313 us). It is still far below the 5x speed gate and has not
  been swapped into production fix/diagnostic code.
- `CompilerServiceSourceTextLineMapBenchmarks` exercises the next source-position service shape:
  compact line starts and lengths plus offset-to-line, offset-to-column, and line/column-to-offset
  queries. The C# baseline starts from the current production split helper; the N# candidate builds
  ranges into caller-owned buffers, builds a dense offset-to-line cache for source text up to 1 MiB,
  and runs the same query workload without managed allocation.
- `CompilerServiceSourceTextLineMapCachedQueryBenchmarks` separates the steady-state query path after
  a document line map has already been built. The validating N# query API keeps the external
  line/column checks; the trusted N# query API is a separate internal-batch contract for positions
  already proven valid by the caller. Equal-length trusted offset and line/column batches use one
  fused eight-wide N# hot loop over both query streams.

The dogfood project also includes `CompilerServices/SourceTextLines.nl`; `CompilerDogfoodProjectTests`
compiles it through the SDK project and verifies both returned strings and range buffers against the
current C# `SourceTextLines.SplitLogicalLines` behavior for empty, trailing-separator, CRLF,
standalone-CR, LF, and mixed-newline cases. It also verifies line-start construction,
offset-to-line/column lookup, line/column-to-offset validation, cached build-and-query checksums,
validating cached-query checksums, and the trusted valid-query checksum contract over those cases.

The line-map build-and-query dry run on 2026-06-03 showed the N# candidate passing checksum parity and
reporting zero managed allocation. The representative corpus ran about 3.5x faster than the C#
split-derived line-map baseline (99 us vs 346 us, 0 B vs 920 B), while the large mixed-newline corpus
was about 2.0x faster (391 us vs 767 us, 0 B vs 2.84 MB). This is useful evidence for the compact map
shape, but it is still below the 5x acceptance gate and has not been swapped into production code.

The cached-query dry run on 2026-06-03 separated map construction from query throughput. The
validating N# cached-query path was about 3.0x faster on the representative corpus (106 us vs 321 us)
and about 7.6x faster on the large mixed-newline corpus (127 us vs 963 us), with no managed
allocation reported. The trusted-valid internal batch path uses a four-wide hot-loop unroll and ran
about 2.4x faster than a trusted C# binary-search query baseline on the representative corpus (74 us
vs 180 us) and about 5.6x faster on the large corpus (94 us vs 529 us). This is pressure evidence for
cached compiler-position batches, not acceptance evidence: the representative query path still misses
the 5x gate, and all numbers are dry smoke runs.

Later on 2026-06-03 the small-file line-map builder stopped scanning ordinary characters before
filling the offset-to-line table: it now uses `string.IndexOf` to find CR/LF separators and only loops
over the offsets that must be assigned to a line. Remaining nonnegative binary-search midpoints in
the N# source-map candidate also use `>> 1` instead of `/ 2`. The dry source-map smoke run improved
but still missed representative acceptance: build-and-query measured 94 us vs 336 us on the
representative corpus and 352 us vs 728 us on the large mixed-newline corpus; cached validating
queries measured 100 us vs 323 us representative and 119 us vs 920 us large. This keeps the same
conclusion: large cached query paths are promising, but representative source-map work still needs
more than local loop cleanup before any production rewrite claim.

On 2026-06-04, the source-map build path changed dense offset-to-line table construction from a
per-offset N# assignment loop to `Array.Fill` over each contiguous line span, then raised the dense
table cutoff to 1 MiB of source text. The normal BenchmarkDotNet build-and-query run reported zero
managed allocation on the N# path and measured 7.287 us vs 22.449 us on the representative corpus
(about 3.1x) and 128.786 us vs 660.875 us on the large mixed-newline corpus (about 5.1x). This is a
real large-corpus gate pass for the dense caller-owned table shape, but not source-map acceptance:
the representative build-and-query path still misses the 5x gate.

The next source-map build path pass on 2026-06-04 reused the already batched validating cached-query
helper after dense line-map construction, instead of keeping a separate scalar query loop in
`LineMapCachedChecksumInto`. The normal BenchmarkDotNet build-and-query run still reported zero
managed allocation on the N# path and measured 6.068 us vs 22.005 us on the representative corpus
(about 3.6x) and 126.992 us vs 725.020 us on the large mixed-newline corpus (about 5.7x). This moves
the external build-and-query API closer and keeps the large-corpus row comfortably past 5x, but the
representative row remains below the required 5x acceptance gate.

The next cached-query dry smoke pass on 2026-06-03 kept the same validating contract but processed
offset and line/column queries in four-wide batches, relying on the cached line-map invariant that
`starts[index] + lengths[index]` is within the source. The validating cached-query path improved to
85.83 us vs 332.79 us on the representative corpus (about 3.9x) and 104.83 us vs 959.25 us on the
large mixed-newline corpus (about 9.2x). The trusted valid-query batch measured 71.62 us
representative and 89.29 us large in the same dry run. Large cached-query throughput is now well past
the dry smoke threshold, but representative cached queries still miss the 5x acceptance gate.

On 2026-06-04, the trusted valid-query batch gained an equal-length fast path that processes offset
queries and line/column queries in one eight-wide loop. The normal BenchmarkDotNet run measured the
trusted N# internal batch at 4.301 us on the representative corpus and 5.699 us on the large
mixed-newline corpus, with no managed allocation reported. Compared with the current validating C#
cached-query baseline from the same benchmark pass, that is about 5.2x faster on representative
inputs (22.393 us vs 4.301 us) and about 38.0x faster on large mixed-newline inputs (216.690 us vs
5.699 us). The matched trusted C# baseline is still a real constraint: it measured 11.594 us
representative and 61.390 us large, so the same N# helper is about 2.7x faster on representative
trusted inputs and about 10.8x faster on large trusted inputs. This is acceptance evidence for callers
that can semantically prove valid query batches before entering the source-map hot path; it is not yet
acceptance evidence for the full external validating query API.

Current code-intelligence dogfood benchmarks:

- `CompilerServiceCodeIntelligenceIdentifierSpanBenchmarks` targets identifier span extraction used
  by query, hover, definition, and reference flows. The C# baseline mirrors the current
  `CodeIntelligenceService` behavior: each position query calls `source.Split('\n')` and scans the
  selected line with the same 3-column snap-to-neighbor rules. The N# candidate builds
  line ranges once into caller-owned arrays, processes the query batch in one compiled N# method,
  and writes start/length pairs into caller-owned result buffers through the production-shaped
  `CodeIntelligenceIdentifierSpansInto` API. The benchmark uses 1024
  representative-corpus position queries and 128 large-corpus position queries so the large C#
  split-per-query baseline stays bounded while each row still compares the same query workload for
  C# and N#.
- `CompilerServiceCodeIntelligenceDeclarationNameMatchBenchmarks` targets the declaration-name span
  guard used by strict references and rename. The C# baseline mirrors
  `SelectedSpanMatchesDeclarationName`: each candidate calls `source.Split('\n')`, searches the
  selected declaration line for the declaration name at or after the declaration column, and checks
  whether the selected identifier span exactly covers that occurrence. The N# candidate reuses
  cached line ranges and runs the same ordinal name search into caller-owned match buffers through
  `CodeIntelligenceDeclarationNameMatchesFromLinesInto`.
- `CompilerServiceCodeIntelligenceMemberReceiverBenchmarks` targets receiver extraction before a
  member access, currently used when source-context fallback tries to resolve `receiver.Member`.
  The C# baseline mirrors `ExtractMemberReceiverName`: it calls `source.Split('\n')`, scans backward
  from the member name, and allocates the receiver substring for each query. The accepted N#
  candidate builds line ranges, builds a per-source receiver cache keyed by separator offset into
  caller-owned arrays, and then answers the query batch by copying start/length pairs into
  caller-owned result buffers through the production-shaped `CodeIntelligenceMemberReceiversCachedInto`
  API. It intentionally preserves the current branch order, including the nullable member access
  edge where `customer?.Name` does not reach the later `?.` branch because the `'.'` branch runs
  first.
- `CompilerServiceCodeIntelligenceSourceContextBenchmarks` targets source-context extraction used by
  reference, diagnostic, hover, and query output. The C# baseline mirrors the current split-per-query
  behavior: each line query calls `source.Split('\n')` and trims the selected line. The N# candidate
  reuses line ranges and emits trimmed absolute source start/length pairs into caller-owned result
  buffers through `CodeIntelligenceSourceContextsInto`, leaving any string materialization to the
  outer output adapter.
- `CompilerServiceCodeIntelligenceSourceLineBenchmarks` targets raw source-line extraction used by
  diagnostics and `nlc lint` snippets. The C# baseline mirrors `ExtractSourceLine`: each line query
  calls `source.Split('\n')` and returns the selected untrimmed line. The N# candidate reuses cached
  line ranges and emits absolute source-line start/length pairs through
  `CodeIntelligenceSourceLinesFromLinesInto`, preserving the current LF split behavior including
  trailing CR characters on CRLF input.
- `CompilerServiceCodeIntelligenceCompletionPrefixBenchmarks` targets the source-prefix extraction
  used by completion before deciding identifier vs member-access context. The C# baseline mirrors
  `CompletionEngine.GetCompletions`: each request calls `source.Split('\n')` and materializes the
  selected line prefix with `Substring`, while columns less than one or past the line return the
  whole selected line. The N# candidate reuses cached line ranges and emits absolute prefix
  start/length pairs through `CodeIntelligenceCompletionPrefixesFromLinesInto`.
- `CompilerServiceCodeIntelligenceCompletionReceiverBenchmarks` targets the receiver-context
  classifier used by completion after prefix extraction. The C# baseline mirrors the current
  `CompletionEngine` helper shape: trim the prefix, decide member-access context, tokenize literal
  receiver candidates with the full lexer, and normalize call arguments with a `StringBuilder`. The
  N# candidate keeps the same context/receiver contract, including comment-text and partial-member
  edge behavior, but uses direct prefix scans and caller-owned context/receiver buffers through
  `CodeIntelligenceCompletionReceiversInto`.
- `CompilerServiceCodeIntelligenceDocCommentBenchmarks` targets leading doc-comment extraction used
  by hover documentation. The C# baseline mirrors the current helper: each queried declaration line
  splits the source into logical lines, walks backward across leading `//` comments, trims comment
  content, and materializes the joined documentation string. The N# candidate reuses cached line
  ranges and emits doc-comment content spans/counts through
  `CodeIntelligenceDocCommentLinesFromLinesInto`; the production adapter materializes only the final
  hover documentation string.
- `CompilerServiceCodeIntelligenceVariableDeclarationBenchmarks` targets variable declaration name
  extraction used by type and definition query candidate resolution on declaration lines. The C#
  baseline mirrors `ExtractVariableDeclarationNameAtPosition`: each queried line calls
  `source.Split('\n')`, scans for `:=`, trims whitespace, and allocates the name substring. The N#
  candidate builds a per-source declaration-name cache by line into caller-owned arrays, then answers
  batches by copying cached start/length pairs through
  `CodeIntelligenceVariableDeclarationNamesFromCacheInto`; the production adapter materializes only
  the single requested name.
- `CompilerServiceCodeIntelligenceDiagnosticClusterTraitBenchmarks` targets diagnostic cluster trait
  classification used by `nlc query diagnostics --clusters` and clustered check/lint output. The C#
  baseline mirrors the previous `OutputFormatter` classifier shape: each diagnostic lowercases the
  message and source snippet, builds a full trait record, normalizes the message pattern string, and
  allocates the suggested-action array. The N# candidate trusts stable compiler diagnostic codes on
  the hot path, falls back to message scanning only for unknown codes, and writes compact category
  and source-construct ids into caller-owned buffers. The formatter still materializes the public
  JSON `messagePattern` string after this hot trait pass.
- `CompilerServiceCodeIntelligenceDiagnosticSummaryBenchmarks` targets the diagnostic severity
  summary emitted by `diagnostics`, `diagnostics.clusters`, `check`, and `lint` JSON envelopes. The
  C# baseline models the formatter's previous shape: three LINQ count passes over diagnostic
  severities. The N# candidate counts error/warning/info severities in one compiled loop and writes
  the stable summary counts into caller-owned storage.

The dogfood project now includes `CompilerServices/IdentifierSpans.nl`,
`CompilerServices/CompletionReceivers.nl`, and `CompilerServices/DiagnosticClusters.nl`.
`CompilerDogfoodProjectTests`
compiles it through the SDK project and checks returned spans against the production snap rules for
valid selections, nearby punctuation/whitespace selections, invalid lines, empty lines, CRLF input,
standalone-CR input, Unicode identifier characters, member receivers with whitespace before the dot,
and the current nullable-member-access edge. It verifies the production-shaped match-count APIs,
the checksum parity helpers, the direct member receiver scanner, the cached receiver-cache API, and
source-context span extraction. It also verifies variable declaration name spans through both the
direct scanner and the cached by-line API, including Unicode identifier characters, member-assignment
lines, missing-name assignments, and invalid lines. Raw source-line span parity now covers invalid
lines, empty lines, whitespace-only lines, Unicode line text, and CRLF-preserved trailing `\r`
characters. Completion-prefix span parity covers invalid lines, empty lines, zero columns, in-range
columns, exact end columns, past-end columns, Unicode line text, and CRLF-preserved line content.
Completion receiver parity covers direct dots, partial member names, normalized method-call
receivers, string/interpolated/raw/char/numeric/bool literal receivers, Unicode identifiers, comment
text, and the current C# edge where some generated comment prefixes fall back to expression-suffix
scanning rather than literal-token handling.
Doc-comment span parity covers invalid declaration lines, blank lines immediately above the
declaration, `//`, `///`, and `////` prefixes, trimmed content, and empty comment content.
Declaration-name match parity covers invalid lines, exact selected declaration spans, mismatched
selected spans, Unicode names, missing names, and the current substring-search edge where the guard
can match a declaration name inside a larger token if the caller supplies that name and column. The
diagnostic cluster trait parity checks known-code classification, unknown-message fallback,
source-construct inference, and the compatibility message-pattern wrapper. Diagnostic severity
summary parity covers error, warning, info, and ignored unknown severities, including the
explicit-count contract used by reusable host buffers. The N# candidate imports `System`, uses ASCII
fast paths, and falls back to `Char.IsLetterOrDigit` /
`Char.IsWhiteSpace`, matching the current C# identifier and whitespace rules without putting the
runtime predicates on the common ASCII path.

The normal BenchmarkDotNet run on 2026-06-03 passed match-count and buffer parity and reported zero
managed allocation on the N# code-intelligence paths. `CodeIntelligenceIdentifierSpansInto` ran
about 81x faster than the current C# split-per-query baseline on the representative corpus
(5.56 us vs 448.94 us, 0 B vs 4.1 MB) and about 682x faster on the large generated corpus
(91.76 us vs 62.57 ms, 0 B vs 129.6 MB).

`CodeIntelligenceDeclarationNameMatchesFromLinesInto` passed parity and reported zero managed
allocation in the same normal BenchmarkDotNet evidence tier. It ran about 109x faster on the
representative corpus (4.697 us vs 511.834 us, 0 B vs 4,431,872 B) and about 120,100x faster on the
large generated corpus (536.345 ns vs 64.413 ms, 0 B vs 129,614,947 B). This is acceptance-grade
benchmark evidence for the strict reference/rename declaration-name span guard after line ranges are
built.

`CodeIntelligenceMemberReceiversCachedInto` also cleared the normal BenchmarkDotNet speed gate. It
ran about 174x faster on the representative corpus (2.88 us vs 500.69 us, 0 B vs 4.6 MB) and about
233x faster on the large generated corpus (225.03 us vs 52.51 ms, 0 B vs 129.6 MB). This is
acceptance-grade benchmark evidence for the batched code-intelligence service shape.

`CodeIntelligenceSourceContextsInto` passed parity and reported zero managed allocation in the same
normal BenchmarkDotNet evidence tier. It ran about 108x faster on the representative corpus
(4.503 us vs 487.396 us, 0 B vs 4,383,768 B) and about 676x faster on the large generated corpus
(91.982 us vs 62.176 ms, 0 B vs 129,610,141 B). This is acceptance-grade benchmark evidence for the
span extraction shape.

`CodeIntelligenceSourceLinesFromLinesInto` passed parity and reported zero managed allocation in the
same normal BenchmarkDotNet evidence tier. It ran about 772x faster on the representative corpus
(635.465 ns vs 490.450 us, 0 B vs 4,251,648 B) and about 828,000x faster on the large generated
corpus (74.227 ns vs 61.481 ms, 0 B vs 129,592,652 B). This is acceptance-grade benchmark evidence
for cached raw source-line lookup after line ranges are built.

`CodeIntelligenceCompletionPrefixesFromLinesInto` passed parity and reported zero managed allocation
in the same normal BenchmarkDotNet evidence tier. It ran about 377x faster on the representative
corpus (1.269 us vs 478.162 us, 0 B vs 4,229,816 B) and about 423,000x faster on the large generated
corpus (145.567 ns vs 61.663 ms, 0 B vs 129,589,768 B). This is acceptance-grade benchmark evidence
for cached completion-prefix lookup after line ranges are built.

`CodeIntelligenceCompletionReceiversInto` passed parity in the same normal BenchmarkDotNet evidence
tier for the completion member-access context/receiver classifier. It ran about 5.23x faster on the
representative corpus (47.516 us vs 248.648 us, 107.7 KB vs 1,262.11 KB) and about 5.28x faster on
the large generated corpus (5.663 us vs 29.890 us, 13.5 KB vs 156.45 KB). This is
acceptance-grade benchmark evidence for the post-prefix completion receiver-context hot path; the
remaining allocations are the receiver strings required by the current completion API boundary.

`CodeIntelligenceDocCommentLinesFromLinesInto` passed parity and reported zero managed allocation in
the same normal BenchmarkDotNet evidence tier. It ran about 62x faster on the representative corpus
(9.236 us vs 569.155 us, 0 B vs 4,688,008 B) and about 48,500x faster on the large generated corpus
(1.296 us vs 62.896 ms, 0 B vs 127,635,392 B). This is acceptance-grade benchmark evidence for
cached hover doc-comment extraction after line ranges are built.

`CodeIntelligenceVariableDeclarationNamesFromCacheInto` passed parity and reported zero managed
allocation in the same normal BenchmarkDotNet evidence tier. It ran about 829x faster on the
representative corpus (667.271 ns vs 553.418 us, 0 B vs 4,650,632 B) and about 646,000x faster on
the large generated corpus (82.435 ns vs 53.235 ms, 0 B vs 129,640,733 B). This is
acceptance-grade benchmark evidence for cached declaration-name lookup after the per-source
declaration-name cache is built.

`CodeIntelligenceEditorIdentifierSpansFromLinesInto` passed parity and reported zero managed
allocation in the same normal BenchmarkDotNet evidence tier for the strict LSP word-at-cursor
behavior. It ran about 186x faster on the representative corpus (2.686 us vs 499.657 us, 0 B vs
4,235,264 B) and about 224,000x faster on the large generated corpus (291.808 ns vs 65.221 ms, 0 B
vs 129,590,546 B). This is acceptance-grade benchmark evidence for cached editor identifier lookup
after line ranges are built.

`DiagnosticClusterTraitsInto` passed parity and reported zero managed allocation in the same normal
BenchmarkDotNet evidence tier for clustered diagnostic category/source-construct classification. It
ran about 5.82x faster on the representative diagnostic corpus (79.627 us vs 463.578 us, 0 B vs
2,216,992 B) and about 5.89x faster on the large generated diagnostic corpus (635.812 us vs
3.746 ms, 0 B vs 17,838,904 B). This is acceptance-grade benchmark evidence for the CLI/query
diagnostic clustering trait pass; message-pattern materialization intentionally remains in the
formatter boundary for the public JSON schema.

`DiagnosticSeveritySummaryInto` passed parity and reported no managed allocation in the same normal
BenchmarkDotNet evidence tier for JSON diagnostic summary counting. It ran about 5.54x faster on the
representative diagnostic corpus (781.7 ns vs 4.331 us) and about 5.36x faster on the large
generated diagnostic corpus (6.246 us vs 33.497 us). This is acceptance-grade benchmark evidence for
the diagnostic/check/lint severity-summary pass.

The production swap slice for these extraction helpers now ships the dogfood assembly beside the CLI,
language server, and test host through `NSharpLang.Compiler.Dogfood.targets`, while
`CodeIntelligenceService` dynamically binds the compiled N# methods when the assembly is present.
The adapter caches line ranges, receiver caches, and variable-declaration name caches per
`ProjectSnapshot`/file, uses cached line ranges for the strict reference/rename declaration-name
span guard, reference source-context and raw diagnostic-line materialization, completion-prefix
extraction, hover doc-comment extraction, and strict editor word/span extraction used by the language
server. Completion receiver-context classification also routes through the compiled N# classifier
when the dogfood assembly is available, with the old C# helper kept as the fallback.
Source-only diagnostic formatting uses a `ConditionalWeakTable<string, ...>` cache for callers such
as `nlc lint` and IDE open-buffer utilities that do not carry a `ProjectSnapshot`.
Clustered diagnostic output now uses the compiled N# trait classifier for category/source-construct
ids when the dogfood assembly is available, then materializes schema strings in the formatter.
Diagnostic, clustered diagnostic, check, and lint JSON envelopes now use the compiled N# severity
summary pass when the dogfood assembly is available, with the previous C# LINQ counts kept as the
fallback.
`CompilerDogfoodProjectTests` verifies the packaged adapter can load
`NSharpLang.Compiler.Dogfood.dll` and answer identifier, receiver, source-context, raw source-line,
completion-prefix, completion receiver-context, doc-comment, strict editor identifier,
declaration-name match, and
variable-declaration-name queries, plus diagnostic cluster trait classifications and diagnostic
severity summaries,
through the compiled N# methods;
`QueryIntegrationTests` exercises the public query surface with the adapter-enabled output,
including trimmed reference contexts and hover documentation. This is swap evidence for the
identifier-span, member-receiver, reference source-context, diagnostic/lint raw source-line,
completion-prefix, completion receiver-context, hover doc-comment, strict reference/rename
declaration-name guard, variable declaration name extraction, and diagnostic severity summary
slices, plus LSP editor word/span lookup for hover, definition, references, and rename entry points.
Broader query, hover, definition, diagnostic, completion candidate construction, binding, and CLI
command logic still contains C# implementation code and remains in scope for the dogfood rewrite.

## Rewrite Order

Start with compiler-service hot paths that are deterministic, independently testable, and used by
the compiler, CLI, and LSP:

1. **Lexer:** replace allocation-heavy string/token construction and dictionary keyword lookup with
   span-backed scanning, compact token storage, and systems-language memory discipline.
2. **Source text and line maps:** make position mapping allocation-light because diagnostics,
   query, and LSP call it constantly.
3. **Parser:** move recursive descent to N# once token representation is stable; benchmark
   declaration parsing, expression parsing, recovery paths, and large-file parsing separately.
4. **Binding and semantic lookup:** port symbol tables, binding maps, and reference lookup with
   semantic parity tests. No string-search fallbacks count as rewritten compiler services.
5. **Diagnostics and formatting:** keep Elm-quality output while reducing repeated string work.
6. **CLI query/check/fix daemon paths:** swap after compiler-service parity is proven, because these
   are product surfaces and schema stability matters.
7. **IL emission:** port only after front-end facts and parity are stable; this is the highest
   verifiability-risk area and must keep ILVerify gates green.

## Project Shape

N# dogfood modules should be ordinary SDK projects:

```xml
<Project Sdk="NSharpLang.Sdk" />
```

All configuration belongs in `project.yml`. C# host projects may reference these modules through
normal `ProjectReference` while migration is incremental. A C# adapter is acceptable only as a
temporary boundary that lets existing compiler, CLI, and LSP callers consume the N# implementation;
it must not hide the fact that a production service still depends on C# code.

Current dogfood module:

- `src/NSharpLang.Compiler.Dogfood`: first N# compiler-service candidate module. Its `.csproj`
  contains only `<Project Sdk="NSharpLang.Sdk" />`; compiler settings live in `project.yml`.

## Language Pressure

When a function cannot reach the 5x gate because N# lacks a required systems capability, record the
gap and make the smallest language/runtime change that addresses the measured bottleneck. Likely
pressure points:

- borrow/ref safety for spans and stack-only values;
- stable, slice-backed token text without eager string allocation;
- stack or arena allocation for short-lived compiler data;
- predictable value-layout controls for compiler structs;
- direct-call and generic-specialization support for internal hot helpers.

The language change is accepted only with the same evidence: semantic tests, IL-shape/verifiability
where applicable, and dogfood benchmarks showing the compiler-service win.

Current lexer pressure point: the token-kind scanner can use `new int[](length)` as a dynamic
buffer and write by index from N#-emitted IL. The reusable-buffer API proves the hot path can avoid
the exact-array copy when the caller owns storage, but N# still needs a slice/span or owned token
buffer type for production APIs that return a filled prefix without exposing unused capacity or
copying.

Current source-text pressure point: direct N# character loops are not yet competitive enough for
line splitting or representative source line-map construction. Calling optimized BCL
`string.IndexOf` improved the range-buffer candidate, and dense offset-to-line caches now make the
large normal build-and-query row plus large steady-state query batches clear the 5x threshold, but
representative source-map build/query still misses the acceptance gate. To reach the 5x goal, N#
needs lower-overhead source-map query batches after construction, a faster native/string scanning
primitive, and more bounds-check-friendly indexed-array/span lowering for batches, without relying on
hand-unrolled compiler-service loops as the normal programming model.

Current code-intelligence pressure point: the identifier-span candidate gets its speed from batching
queries and reusing caller-owned line/result buffers. The N# compiler can emit a direct
`Char.IsLetterOrDigit` runtime static call from an imported `System` namespace while keeping the
normal BenchmarkDotNet speed gate above 5x. The member-receiver candidate shows the next API lesson:
the 5x win comes from a source-level receiver cache plus caller-owned buffers, not from calling a
tiny backward scanner once per request. The source-context candidate proves reusable line ranges and
span outputs avoid split-and-trim allocation for reference output, and the production adapter now
materializes reference contexts from those spans. Diagnostic snippets, completion prefixes, and hover
doc comments now use the same cached-line-range shape for their extraction steps. Completion
receiver-context classification is also dogfooded, including literal receiver handling and
method-call receiver normalization, but semantic member lookup and completion item construction
remain in C#. Strict editor
identifier lookup uses a separate N# helper because editor hover/rename semantics must not inherit
the query engine's snap-to-nearby-identifier behavior. Broader hover/diagnostic/completion output
shaping still needs N# implementations. Diagnostic cluster trait classification and diagnostic
severity summary counting are now dogfooded, but message-pattern materialization and full cluster
grouping are still C# formatter work. The
strict reference/rename declaration-name guard now uses the same line-range cache, but the semantic
binding tables and lookup policy are still C# host logic.
The production adapter keeps cache lifetime explicit, but the remaining code-intelligence work still
needs N# implementations for semantic lookup, completion construction, output shaping, and CLI
command orchestration.
