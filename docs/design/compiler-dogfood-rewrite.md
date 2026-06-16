> **Strategy superseded; methodology retained.** The "N# kernels behind `*DogfoodAdapter` delegates" routing approach described here is a proven performance dead-end — the delegate boundary is a fixed ~1.2 ns/call floor and materializing back to the C# AST is 4–5× slower (see `docs/design/compiler-dogfood-boundary-profiling.md`). The current self-host strategy is the **columnar pipeline** (`docs/design/columnar-pipeline.md`, `docs/design/roadmap-to-done.md`). This doc is retained for its per-slice parity/benchmark methodology and accepted/rejected evidence record, which remain valid.

# Compiler Dogfood Rewrite Plan

Status: superseded strategy — retained as a methodology + accept/reject evidence archive (see banner above)
Updated: 2026-06-05

This document tracks the rewrite of the N# compiler, compiler services, and CLI tooling in N#.
It is not a straight port. The goal is to use the systems-oriented parts of N# to make the
toolchain materially faster than the current C# implementation while exposing the language gaps
that prevent that result.

## End State

The compiler core libraries, compiler-service core libraries, and CLI command logic are expected to
move to N#. C# is acceptable only for CLR/BCL host boundaries, bootstrap loading, public .NET object
materialization, or measured fallback while a function has not yet cleared parity and speed gates.
Adapter names such as `NSharpPerformanceDogfoodAdapter`, `NSharpCompilerDogfoodAdapter`, and
`NSharpCliDogfoodAdapter` were temporary transition boundaries and have been deleted from product
routes as owner-local helpers took over. `NSharpCodeIntelligenceDogfoodAdapter` remains temporary;
adapter surfaces are not the target architecture and must shrink as N# slices land.

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
dotnet run -c Release --project benchmarks -- --filter '*CompilerServiceSemanticScope*'
dotnet run -c Release --project benchmarks -- --filter '*AnalyzerEnumExhaustiveness*'
dotnet run -c Release --project benchmarks -- --filter '*AnalyzerUnionExhaustiveness*'
dotnet run -c Release --project benchmarks -- --filter '*CompilerServiceAotRequirementGrouping*'
dotnet run -c Release --project benchmarks -- --filter '*CompilerServiceStructCopyFieldAnalysis*'
dotnet run -c Release --project benchmarks -- --filter '*CompilerServiceAnonymousUnionShim*'
dotnet run -c Release --project benchmarks -- --filter '*CliQueryBatchResultCount*'
dotnet run -c Release --project benchmarks -- --filter '*CliTestOutcomeSummary*'
dotnet run -c Release --project benchmarks -- --filter '*CliTidy*'
dotnet run -c Release --project benchmarks -- --filter '*CliDocSlug*'
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
- `CompilerServiceParserTokenCompactionBenchmarks` targets parser constructor newline-token
  compaction. The C# baseline mirrors `tokens.Where(t => t.Type != TokenType.Newline).ToList()`.
  The N# candidate runs after the host projects token kinds into compact ids and writes kept source
  indices through the full-array `ParserTokenCompactionIndicesInto` parity wrapper. Token objects and the final parser token list
  remain C# host boundaries until the compact parser token table is ported. The product adapter now
  binds `TokenizeColumnarSourceInto` for columnar tokenization so N# tokenizes, inserts indentation
  braces, and writes compact kind/start/value-length rows before crossing back to C#; parser-constructor
  token-object compaction still binds the counted-prefix `ParserTokenCompactionIndicesCountedInto`
  ABI. The full-array, standalone parser-metadata, and standalone compact-metadata exports are
  retained only in the parity corpus for benchmark and parity evidence.

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
  already proven valid by the caller. Equal-length validating offset and line/column batches use a
  fused four-wide N# loop with a valid-batch fast path and scalar fallback for invalid batches.
  Equal-length trusted batches use one fused eight-wide N# hot loop over both query streams.

The source-text candidate now lives only in
`NSharpLang.Compiler.Dogfood.ParityCorpus/SourceTextLines.nl`. `CompilerDogfoodProjectTests` compiles
that extracted parity file and verifies both returned strings and range buffers against the current
C# `SourceTextLines.SplitLogicalLines` behavior for empty, trailing-separator, CRLF, standalone-CR,
LF, and mixed-newline cases. It also verifies line-start construction, offset-to-line/column lookup,
line/column-to-offset validation, cached build-and-query checksums, validating cached-query checksums,
and the trusted valid-query checksum contract over those cases.

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

On 2026-06-05, the validating cached-query batch gained the same equal-length query-stream fusion and
a four-wide valid-batch fast path: offset batches that are already within the source extent skip
per-item clamping, and line/column batches that are already valid skip scalar fallback while retaining
the external invalid-input behavior. The short BenchmarkDotNet cached-query run measured the
validating N# path at 4.850 us vs 22.246 us on the representative corpus (about 4.6x) and 8.042 us vs
207.191 us on the large mixed-newline corpus (about 25.8x), with no managed allocation reported. This
is a strong large-corpus pass and a meaningful representative pressure reduction, but the external
validating representative path still misses the 5x gate; callers that can prove valid query batches
should continue to use the trusted internal contract.

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
- `CompilerServiceCodeIntelligenceDeclarationNameColumnBenchmarks` targets analyzer declaration-name
  column lookup before binding-map declaration recording. The C# baseline mirrors the previous
  analyzer helper: each declaration lookup splits the source text, trims a trailing CR from the
  selected line, searches for a whole identifier at or after the parser fallback column, and retries
  from the start of the line. The N# candidate reuses cached line ranges and writes resolved
  declaration columns into caller-owned buffers through
  `CodeIntelligenceIdentifierNameColumnsFromLinesInto`.
- `CompilerServiceCodeIntelligenceReferenceDeduplicationBenchmarks` targets semantic reference
  result deduplication and deterministic ordering after declaration/reference lookup. The C#
  baseline mirrors `BuildReferenceResultsFromDeclaration`: LINQ `GroupBy` over `(file,line,column)`,
  first-reference preservation, and file/line/column ordering. The N# candidate consumes
  host-computed file sort ranks, deduplicates with a caller-owned open-addressed table, and writes
  sorted result indices through `ReferenceDeduplicateCompactInto`.
- `CompilerServiceInspectSummaryReferenceFileBenchmarks` targets the distinct ordered reference-file
  list in `nlc query inspect` summaries. The C# baseline mirrors the formatter shape: normalize
  each reference path, run ordinal `Distinct`, ordinal `OrderBy`, and materialize the public string
  array. The accepted N# candidate runs after the host has assigned compact ordinal file ranks,
  emits present ranks in sorted order through `ReferenceFileSummaryRanksInto`, and lets the host
  materialize the final string array.
- `CompilerServiceCodeIntelligenceBindingLookupBenchmarks` targets strict semantic binding
  position lookup before definition/reference/hover result materialization. The C# baseline uses the
  production `BindingMap.GetBindingAt` dictionaries with declaration-first lookup semantics. The N#
  candidate consumes host-built declaration/binding arrays, prebuilt open-addressed slot tables, and
  candidate query columns, then writes declaration indices through
  `BindingLookupQueryDeclarationIndicesInto`.
- `CompilerServiceBindingLookupNearestDeclarationIndexBuildBenchmarks` targets sorted nearest
  declaration index construction inside the compact `BindingMap` cache. The C# baseline mirrors the
  production cache builder: allocate an order array, sort declaration ids with
  `Array.Sort(order, CompareDeclarationOrder)`, then materialize sorted primitive arrays. The N#
  candidate uses dense name-id counting with caller-owned buffers, writes the sorted arrays directly,
  and returns a fallback signal when same-name declarations are not already in source order.
- `CompilerServiceCodeIntelligenceBindingCandidateColumnBenchmarks` targets strict binding
  candidate-column ordering before declaration/binding lookup. The C# baseline mirrors the current
  helper shape: `HashSet<int>` insertion for nearby columns plus the selected identifier span,
  followed by stable distance ordering. The N# candidate emits the same ordered candidate columns
  through a direct distance-order generator over caller-owned integer buffers. The host still owns
  identifier-span extraction and the exact single-call `int[]` return shape.
- `CompilerServiceSemanticScopeVisibleVariablesBenchmarks` targets scoped visible-variable lookup
  used by CLI/daemon identifier completion. The C# baseline uses the current
  `SemanticModel.GetVisibleVariablesAtPosition` scan/sort/dictionary path. The N# candidate consumes
  compact scope ranges, parent/depth arrays, scope-to-symbol spans, and a sorted scope-start index
  with prefix max-end lines, then writes visible symbol indices through
  `SemanticScopeVisibleSymbolIndicesInto`. The host still owns final `TypeInfo` objects and
  completion item materialization.
- `CompilerServiceSemanticScopeIndexBuildBenchmarks` targets sorted scope-start index construction
  inside the compact `SemanticModel` cache. The C# baseline mirrors the current cache-builder shape:
  allocate an order array, sort scope ids with a start line/column/source-id comparer, then materialize
  sorted scope arrays and prefix max-end lines. The N# candidate writes caller-owned output arrays,
  detects the common source-order scope table in one pass, and falls back to comparer-free primitive
  quicksort for out-of-order scope tables.
- `CompilerServiceSemanticScopeDepthBuildBenchmarks` targets scope-depth table construction inside
  the compact `SemanticModel` cache. The C# baseline mirrors the current cache-builder shape:
  compute each scope depth by walking its parent chain. The N# candidate fills the caller-owned depth
  array in one source-order pass for normal scope trees, with a bounded parent-walk fallback for
  out-of-order parents.
- `CompilerServiceSemanticScopeLookupBenchmarks` targets position-aware scoped identifier lookup
  used by member-access completion when resolving a plain receiver name. The C# baseline uses the
  current `SemanticModel.LookupIdentifierAtPosition` containing-scope scan. The N# candidate reuses
  the compact scope/symbol table and sorted scope-start index, finds the deepest containing scope,
  walks the parent chain for the requested name id, and writes the resolved symbol index through
  `SemanticScopeLookupSymbolIndicesInto`. The host still owns `TypeInfo` objects and the
  properties/fields/types fallback boundary.
- `CompilerServiceCodeIntelligenceNearestDeclarationLookupBenchmarks` targets the source-context
  fallback that chooses the nearest same-file declaration by name before AST declaration scans. The
  C# baseline mirrors the production LINQ shape: `FindDeclarationsByName`, file/line filtering,
  line/column descending ordering, and `FirstOrDefault`. The N# candidate consumes host-sorted
  compact `(nameId,fileRank,line,column)` declaration facts and answers each query with a binary
  search upper bound through `BindingLookupFindNearestDeclarationIndicesInto`.
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
- `CompilerServiceCodeIntelligenceCompletionItemGroupingBenchmarks` targets member-completion item
  grouping before CLI/daemon completion output. The C# baseline mirrors the current
  `CompletionEngine` shape: LINQ `GroupBy` over `CompletionItem.Kind`, pluralized dictionary keys,
  and `ToList` materialization for each public group. The N# candidate runs after the host has
  assigned compact first-seen kind ids and writes group kind ids, starts/counts, and stable source
  indices into caller-owned buffers through `CompletionItemKindGroupsInto`.
- `CompilerServiceCodeIntelligenceCompletionMethodGroupingBenchmarks` targets reflected CLR method
  overload grouping before member-completion item construction. The C# baseline mirrors
  `CompletionEngine.GetTypeMembers`: filter `MethodInfo` values, group by `MethodInfo.Name` with
  LINQ `GroupBy`, materialize the first-seen group list, and count overloads. The N# candidate runs
  after the host has assigned compact first-seen method-name ids and writes group name ids, first
  source indices, and overload counts through `CompletionMethodOverloadGroupsInto`. Reflection and
  final `CompletionItem` string materialization remain explicit C# host boundaries.
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
- `CompilerServiceCodeIntelligencePathMatchingBenchmarks` targets code-intelligence file-path
  matching used when user-supplied paths are resolved against project snapshot paths. The C#
  baseline mirrors the current helper: allocate slash-normalized copies, compare exact paths
  case-insensitively, then check case-insensitive suffix plus segment boundary. The N# candidate
  compares normalized slash and case on the fly through `CodeIntelligencePathMatches`, with both
  single-call and batch-shaped benchmark rows. This is pressure evidence only because both N# rows
  currently miss the speed gate.
- `CompilerServiceCodeIntelligenceDiagnosticClusterTraitBenchmarks` targets diagnostic cluster trait
  classification used by `nlc query diagnostics --clusters` and clustered check/lint output. The C#
  baseline mirrors the previous `OutputFormatter` classifier shape: each diagnostic lowercases the
  message and source snippet, builds a full trait record, normalizes the message pattern string, and
  allocates the suggested-action array. The N# candidate trusts stable compiler diagnostic codes on
  the hot path, falls back to message scanning only for unknown codes, and writes compact category
  and source-construct ids into caller-owned buffers. The formatter still materializes the public
  JSON `messagePattern` string after this hot trait pass.
- `CompilerServiceCodeIntelligenceDiagnosticClusterTraitPatternBenchmarks` targets the attempted
  combined diagnostic cluster trait and public message-pattern materialization path. The C# baseline
  mirrors the formatter's full trait construction shape, while the N# candidate writes compact
  category/source-construct ids and stable message-pattern strings into caller-owned buffers through
  `DiagnosticClusterTraitsAndPatternsInto`. This is kept as pressure evidence for public string
  materialization, not as a production-routing benchmark, because the current result misses the 5x
  acceptance gate.
- `CompilerServiceCodeIntelligenceDiagnosticSummaryBenchmarks` targets the diagnostic severity
  summary emitted by `diagnostics`, `diagnostics.clusters`, `check`, and `lint` JSON envelopes. The
  C# baseline models the formatter's previous shape: three LINQ count passes over diagnostic
  severities. The N# candidate counts error/warning/info severities in one compiled loop and writes
  the stable summary counts into caller-owned storage.
- `CompilerServiceDiagnosticShadowSuppressionBenchmarks` targets the `GetDiagnostics` suppression of
  linter `NL020` shadowing diagnostics for files that already have compiler shadowing errors. The C#
  baseline mirrors the previous service shape: a case-insensitive shadowed-file set and LINQ list
  materialization. The N# candidate runs after the host has assigned compact ordinal code ids,
  case-insensitive file ranks, and shadowed-file flags, then writes kept diagnostic indices through
  caller-owned storage while preserving source order.
- `CompilerServiceDiagnosticClusterFileListBenchmarks` targets the distinct ordered file list inside
  each clustered diagnostic payload. The C# baseline mirrors `CreateDiagnosticCluster`: select
  diagnostic files, apply case-insensitive `Distinct`, case-insensitive `OrderBy`, and materialize
  the public string array. The accepted N# candidate runs after the host has assigned compact
  case-insensitive file ranks, emits present ranks through `ReferenceFileSummaryRanksInto`, and lets
  the host materialize the final public string array.
- `CompilerServiceCodeIntelligenceDiagnosticDeduplicationBenchmarks` targets diagnostic
  deduplication used by `nlc check` and strict build lint. The C# baseline mirrors the previous CLI
  shape: LINQ `GroupBy` over `(code,file,line,column,message)`, first-diagnostic preservation, and
  file/line/column ordering. The N# candidate consumes compact code/message ids and host-computed
  file sort ranks, deduplicates with a caller-owned open-addressed table, and writes sorted result
  indices into caller-owned storage. The host rank boundary preserves the old default string ordering
  while keeping the N# hot path integer-only.
- `CompilerServiceCodeIntelligenceDiagnosticStableDeduplicationBenchmarks` targets the
  preserve-first-order duplicate removal used by `CodeIntelligenceService.GetDiagnostics` after
  compiler and lint diagnostics are combined. The C# baseline mirrors the private helper's LINQ
  `GroupBy(...).Select(First)` shape without final sorting. The N# candidate consumes compact
  code/file/message ids, deduplicates with a caller-owned open-addressed table, and writes first-seen
  unique diagnostic indices in original input order.
- `CompilerServiceCodeIntelligenceDiagnosticClusterGroupBenchmarks` targets diagnostic cluster
  grouping before clustered diagnostic JSON/text materialization. The C# baseline mirrors the
  formatter's current shape: LINQ `GroupBy` over string cluster fields, root selection per group,
  and final cluster ordering. The N# candidate consumes preclassified integer dimensions, groups
  with a caller-owned open-addressed table, and writes ordered root indices/counts into
  caller-owned storage.
- `CompilerServiceCodeIntelligenceDiagnosticClusterIdBenchmarks` targets public diagnostic cluster
  id materialization for clustered diagnostics JSON. The C# baseline mirrors the formatter shape:
  build a composite key string, hash the key characters, then materialize the public `diag-{hex}`
  id. The N# candidate hashes each stable cluster field directly, formats the public hex suffix
  through a reusable char buffer, and writes ids into caller-owned storage, avoiding the temporary
  composite key and per-id hex string allocations.
- `CompilerServiceCodeIntelligenceDiagnosticClusterNextCommandBenchmarks` targets the
  `nlc query inspect` command emitted for each diagnostic cluster root. The C# baseline mirrors the
  formatter helper: escape the root file path with a LINQ safety scan and replacement-based quoting,
  then materialize the command string. The N# candidate scans directly, appends escaped path content
  through one batch-local `StringBuilder`, and writes commands into caller-owned storage.
- `CompilerServiceTextEditOrderingBenchmarks` targets the text-edit application ordering used by
  `FixApplicator.ValidateAndSortEdits` before `nlc fix` applies edits. The C# baseline mirrors the
  previous production LINQ shape: attach the source index, order by descending start line/column,
  ascending end line/column, descending source index for same-position inserts, then materialize the
  list. The accepted N# candidate runs after the host has compacted `(startLine,startColumn)` and
  `(endLine,endColumn)` ranks and returns ordered source indices through caller-owned buffers.
- `CompilerServiceFormatterImportOrderingBenchmarks` targets the import/using ordering in
  `Formatter.Format` ("System* first, then namespace alphabetical"). The C# baseline mirrors the
  production LINQ shape: `Select`-with-index projection, `OrderByDescending(StartsWith "System")`,
  `ThenBy(namespace)`, then `ToList()`. The accepted N# candidate runs after the host has compacted
  each import to a dense namespace rank (sharing a rank when namespaces compare equal under
  `Comparer<string>.Default`, mirroring stable `ThenBy` ties) plus a System-prefix flag, then returns
  ordered source indices through caller-owned buffers via a two-pass stable counting sort with no
  per-call managed allocation.
- `CompilerServiceErrorSuggestionBenchmarks` targets compiler typo-suggestion scoring used by
  Elm-style diagnostics. The C# baseline mirrors `SmartSuggester.SuggestSimilarNames`: LINQ
  projection/filter/order, lowercase string allocation, edit-distance matrix allocation, and final
  name list materialization. The N# candidate returns sorted candidate indices into caller-owned
  buffers, reuses edit-distance row buffers, and compares characters case-insensitively without
  lowercase string allocation. This benchmark is currently pressure evidence only because the N#
  dynamic-programming loop is slower than the C# baseline.

Current compiler-performance dogfood benchmarks:

- `CompilerServiceAotRequirementGroupingBenchmarks` targets AOT requirement construction before
  public AOT/trimming compatibility attributes are emitted. The C# baseline mirrors
  `AotRequirements.FromBlockers`: filter public blockers, group by enclosing declaration, combine
  unreferenced-code and dynamic-code flags, distinct/order construct names, and build the annotation
  inputs. The accepted N# candidate runs after the host has projected blockers to dense declaration
  ranks, sorted construct ranks, and compact blocker-kind ids, then writes grouped declaration
  ranks, flags, and the first three sorted construct ranks through `AotRequirementGroupsInto`.
  Public annotation strings and dictionaries remain explicit C# host boundaries until the broader
  AOT attribute-emission path is ported.
- `CompilerServiceStructCopyFieldAnalysisBenchmarks` targets the declared-field readonly gate used
  by struct-copy analysis before deciding whether a large value type can be passed by `in`
  reference. The C# baseline mirrors the previous `Where(...).ToList().All(...)` shape. The
  accepted N# candidate runs after the host has projected static-or-readonly field readiness into
  compact 0/1 integer flags, then scans those flags through
  `StructCopyAllInstanceFieldsInitOnly`. Reflection over CLR fields, type-size calculation, and
  public descriptor construction remain explicit C# host boundaries until the full struct-copy
  optimizer is ported.
- `CompilerServiceAnonymousUnionShimBenchmarks` targets IL compiler anonymous-union overload-shim
  eligibility before overload materialization and struct-copy elision. The C# baseline mirrors the
  previous `Where(...).ToList().All(...)` shape over two-arm anonymous-union parameters. The accepted
  N# candidate runs after the host has packed only exactly-two-arm anonymous-union parameter flags,
  then scans those flags through `AnonymousUnionDeclaresPublicShim`. Function public-surface checks,
  modifier/type-parameter preconditions, exact union-arm recognition, and final overload-shim
  materialization remain explicit C# host boundaries until the broader IL compiler port lands.
- `CompilerServiceInterfaceDeduplicationBenchmarks` targets first-source implemented-interface
  de-duplication in the IL compiler after direct and inherited interfaces have been expanded. The C#
  baseline mirrors the fallback shape: group by ordinal type key, keep the first interface in each
  group, and materialize the result. The accepted N# candidate runs after the host has assigned
  dense type-key ranks, marks first-seen ranks in caller-owned buffers, and writes first-source
  indices through `FirstDistinctRankIndicesInto`.
- `CompilerServiceDeclaredTypeLookupBenchmarks` targets declared project-type suffix resolution in
  the IL compiler. The C# baseline mirrors `TryLookupUniqueDeclaredTypeBySuffix`: scan dictionary
  keys for exact or dotted-suffix ordinal matches, select distinct `Type` values, take at most two,
  and materialize the result. The accepted N# candidate scans compact key/value-rank/query-width
  tail-hash arrays and returns a unique value rank, no-match sentinel, or ambiguous sentinel through
  `DeclaredTypeUniqueSuffixValueRank`.
- `CompilerServiceDeclaredTypeNameCandidateBenchmarks` targets declared type-name disambiguation in
  `GetDeclaredTypeNameCandidates`. The C# baseline mirrors the fallback shape: enumerate declared
  type names, filter null/whitespace, distinct by ordinal name, materialize exact-or-dotted-suffix
  matches, materialize imported-namespace matches, then select the unique imported match or unique
  total match. The accepted N# candidate scans compact unique declared-name/import-flag/query-width
  tail-hash arrays and returns a 1-based selected name index, no-match/ambiguous sentinel, or invalid
  input sentinel through `DeclaredTypeNameCandidateIndex`.
- `CompilerServiceTypeCreationOrderBenchmarks` targets IL compiler `TypeBuilder` creation order.
  The C# baseline mirrors the fallback shape: stable `OrderByDescending` by type-key dot count and
  array materialization. The accepted N# candidate counts key depths once, uses stable descending
  counting buckets, and writes source indices through `TypeCreationOrderIndicesInto`.
- `CompilerServiceAnalyzerEnumExhaustivenessBenchmarks` targets analyzer enum-match exhaustiveness
  finalization. The C# baseline mirrors the existing `CheckEnumMatchExhaustiveness` tail: build an
  all-member hash set from enum declaration member names, run `Except` against covered members, and
  materialize missing names. The accepted N# candidate runs after the analyzer has projected
  declaration-order covered-member flags, then writes missing source indices through
  `AnalyzerMissingMemberIndicesInto`; final public diagnostic string materialization remains in C#.
- `CompilerServiceAnalyzerUnionExhaustivenessBenchmarks` targets analyzer union-match
  exhaustiveness finalization. The C# baseline mirrors the existing `CheckMatchExhaustiveness`
  tail: build the all-case set, run `Except` against covered cases, then partition missing cases
  into partially-covered and never-covered lists. The compact N# candidate runs after the analyzer
  has declaration-order covered/partial flags and writes missing, partial-missing, and
  never-covered source indices through `AnalyzerUnionMissingCaseIndicesInto`. The accepted
  production route now builds those compact flags while collecting union coverage and materializes
  diagnostic case names through `TrySelectMissingUnionCasesFromFlags`. The benchmark also keeps a
  projected C# set-to-flag row as rejection evidence; do not regress production back to that late
  adapter shape.
- `CompilerServiceOverloadSelectionBenchmarks` targets the IL compiler declared-method
  overload/candidate ranking in `ILCompiler.BindDeclaredMethodCall`, which runs on every
  declared-method/constructor call during IL emission. The C# baseline mirrors the previous binder
  shape: `.ToList()` materialization of the overload set, a per-candidate
  `GetParameters().Select(...).ToArray()` parameter-type projection, and the four-level tie-break
  (score > non-generic > non-params > fewer-defaults, first-wins-on-tie) that allocates a bound-call
  record per improving candidate. The accepted N# candidate represents the overload set as compact
  primitive columns (per-candidate validity, score, generic/params flags, defaults-used, plus a
  flattened parameter-type-id table with per-candidate offsets/counts) computed once by the host,
  then runs the exact ranking over those columns through `OverloadSelectBestCandidate` /
  `OverloadSelectBatchInto`. The production binder now binds each surviving candidate once into a
  compact candidate list and routes winner selection through `OverloadSelectBestCandidate` via
  `NSharpCompilerDogfoodAdapter.TrySelectOverloadCandidate`, preserving the exact selection and
  emitted IL with an identical inline C# tie-break fallback when the dogfood assembly is absent.
  On 2026-06-05 the normal BenchmarkDotNet run passed checksum and per-call index parity and reported
  zero managed allocation on the N# path. It ran about 11.3x faster on the representative corpus
  (11.07 us vs 124.95 us, 0 B vs 417,112 B) and about 10.9x faster on the large generated corpus
  (95.91 us vs 1,042.99 us, 0 B vs 3,337,272 B). This is acceptance-grade evidence for the compact
  overload-candidate ranking after the host has projected the per-candidate rank columns; the final
  `BoundDeclaredMethodCall` materialization and per-candidate parameter binding remain C# host
  boundaries.

The dogfood project now includes `CompilerServices/IdentifierSpans.nl`,
`CompilerServices/CompletionReceivers.nl`, `CompilerServices/DiagnosticClusters.nl`,
`CompilerServices/DiagnosticDeduplication.nl`, `CompilerServices/BindingLookup.nl`,
`CompilerServices/CliQueryParsing.nl`,
`CompilerServices/CliArguments.nl`, `CompilerServices/CliDocOrdering.nl`,
`CompilerServices/CompletionGrouping.nl`, `CompilerServices/PathMatching.nl`,
`CompilerServices/TextEditOrdering.nl`, `CompilerServices/AotRequirements.nl`,
`CompilerServices/StructCopyAnalysis.nl`, `CompilerServices/AnonymousUnionShims.nl`,
`CompilerServices/ErrorSuggestions.nl`, `CompilerServices/AnalyzerExhaustiveness.nl`,
`CompilerServices/TypeLookup.nl`, and `CompilerServices/OverloadCandidates.nl`.
The semantic-scope kernels formerly shipped as `CompilerServices/SemanticScopes.nl` now live only in
the parity corpus as `SemanticScopesCore.nl` plus the checksum/wrapper `SemanticScopes.nl`; the
public `SemanticModel` bridge missed the production 5x gate, so no shipped product adapter binds
those symbols until a wider batched/caller-owned route exists.
`CompilerDogfoodProjectTests`
compiles it through the SDK project and checks returned spans against the production snap rules for
valid selections, nearby punctuation/whitespace selections, invalid lines, empty lines, CRLF input,
standalone-CR input, Unicode identifier characters, member receivers with whitespace before the dot,
and the current nullable-member-access edge. It verifies the production-shaped match-count APIs,
the checksum parity helpers, the direct member receiver scanner, the cached receiver-cache API, and
source-context span extraction. It also verifies variable declaration name spans through both the
direct scanner and the cached by-line API, including Unicode identifier characters, member-assignment
lines, missing-name assignments, and invalid lines. It verifies CLI query position parsing against
the current split/`int.TryParse` behavior for valid, invalid, signed, whitespace-padded, and overflow
inputs. It verifies typo-suggestion candidate index ordering against the current
`SmartSuggester.SuggestSimilarNames` score/filter/order contract. It verifies CLI doc symbol
ordering against the current `SymbolKind.ToString()` ordinal kind ordering, ordinal name ordering,
variable/parameter filtering, and stable equal-key behavior. It verifies declared type-name
candidate selection for imported-namespace preference, unique suffixes, exact full names, ambiguous
suffixes, and missing suffixes. Raw source-line span parity now covers invalid lines, empty lines,
whitespace-only lines, Unicode line text, and CRLF-preserved trailing `\r` characters.
Completion-prefix span parity covers invalid lines, empty lines, zero columns, in-range columns,
exact end columns, past-end columns, Unicode line text, and CRLF-preserved line content.
Completion receiver parity covers direct dots, partial member names, normalized method-call
receivers, string/interpolated/raw/char/numeric/bool literal receivers, Unicode identifiers, comment
text, and the current C# edge where some generated comment prefixes fall back to expression-suffix
scanning rather than literal-token handling.
Completion item grouping parity covers first-seen kind group ordering, pluralized public group keys,
stable per-kind member order, and the raw compact group start/count/member-index buffer contract.
Doc-comment span parity covers invalid declaration lines, blank lines immediately above the
declaration, `//`, `///`, and `////` prefixes, trimmed content, and empty comment content.
Declaration-name match parity covers invalid lines, exact selected declaration spans, mismatched
selected spans, Unicode names, missing names, and the current substring-search edge where the guard
can match a declaration name inside a larger token if the caller supplies that name and column. The
analyzer declaration-column parity checks invalid lines, CRLF-trimmed source lines, Unicode
identifiers, whole-identifier boundary skips such as `prefixvalue` vs `value`, retry-from-line-start
behavior, and missing-name fallback columns. The
enum exhaustiveness parity checks missing-member declaration order and the all-covered fast path
through the compiler dogfood adapter. Union exhaustiveness parity checks the compact N# missing,
partial-missing, and never-covered source-index streams directly against the dogfood assembly and
the adapter path that materializes diagnostic case-name lists from compact flags. The
diagnostic cluster trait parity checks known-code classification, unknown-message fallback,
source-construct inference, and the compatibility message-pattern wrapper. Diagnostic cluster id
parity checks stable public ids against the production key/hash/hex algorithm without routing
through the formatter. Diagnostic cluster next-command parity checks safe paths, whitespace paths,
quoted paths, backslash escaping, embedded quotes, and Unicode file names against the current
formatter command contract. Diagnostic severity summary parity covers error, warning, info, and
ignored unknown severities, including the explicit-count contract used by reusable host buffers. The
compact diagnostic cluster grouping parity checks preclassified integer dimensions against the
production string grouping semantics, including root selection by line/column/file and final
ordering by count/file/line/column. Diagnostic deduplication parity checks compact ids and sorted
file ranks against the production `(code,file,line,column,message)` grouping semantics, including
first-diagnostic preservation and file/line/column ordering. Stable diagnostic deduplication parity
checks compact ids against the `GetDiagnostics` preserve-first-order duplicate-removal contract.
Reference-result deduplication parity checks sorted file ranks against the production
`(file,line,column)` grouping semantics, including first-reference preservation and
file/line/column ordering. Reference-file summary parity checks normalized path ranks against the
production inspect-summary ordinal distinct/order contract. Diagnostic-cluster file-list parity
checks case-insensitive file ranks against the production clustered-diagnostic
`Distinct`/`OrderBy(StringComparer.OrdinalIgnoreCase)` contract. Path-matching parity checks
slash-normalized case-insensitive exact matches, suffix matches, segment-boundary false positives,
empty queries, and Unicode paths against the current helper, but remains pressure-only because it
misses the speed gate. CLI positional-argument parity checks the current shared all-positionals
helper's option-with-value skipping, value-less flag skipping, unknown flag handling, empty-argument
inclusion, and positional order contract, plus the first-index variant's early-return and no-match
contracts. Binding candidate-column parity checks the current
`HashSet<int>` plus stable distance-order contract for cursor columns, adjacent columns, invalid
columns, and identifier span ranges. Binding lookup parity checks compact
declaration and binding tables against production
`BindingMap.GetBindingAt` semantics, including declaration-position hits, usage-position hits,
misses, and declaration-first precedence when a binding shares a declaration key.
Nearest-declaration lookup parity checks sorted compact
declaration facts against the production same-file/name, preceding-line, line/column-descending
selection contract. Semantic scope lookup parity checks compact scope ranges and sorted start-index
facts against production `SemanticModel.GetVisibleVariablesAtPosition` shadowing/order semantics,
including root, nested, sibling, open-scope, and no-containing-scope queries. The
semantic scope depth parity checks parent-id tables against expected root/nested depth arrays and
checksum output. The
text-edit ordering parity checks compact start/end position ranks against the production
bottom-to-top, right-to-left, end-position, and same-position reverse-input ordering contract. The
text-scanning candidates use ASCII fast paths and fall back to `Char.IsLetterOrDigit` /
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

`CodeIntelligenceIdentifierNameColumnsFromLinesInto` passed parity and reported zero managed
allocation in the normal BenchmarkDotNet evidence tier for analyzer declaration-name column lookup
before binding-map declaration recording. It ran about 42.05x faster on the representative corpus
(11.266 us vs 473.775 us, 0 B vs 4,121,760 B) and about 44,000x faster on the large generated
corpus (1.315 us vs 57.898 ms, 0 B vs 117,475,691 B). This is acceptance-grade benchmark evidence
for the whole-identifier declaration-column lookup once the host has cached line ranges for the
source text.

`ReferenceDeduplicateCompactInto` passed parity and reported zero managed allocation in the same
normal BenchmarkDotNet evidence tier for semantic reference result deduplication and ordering. It
ran about 13.02x faster on the representative reference corpus (6.557 us vs 85.349 us, 0 B vs
59,560 B) and about 13.19x faster on the large generated reference corpus (71.671 us vs
945.375 us, 0 B vs 468,184 B). This is acceptance-grade benchmark evidence for reference result
deduplication after the host has assigned default-comparer file sort ranks.

`ReferenceFileSummaryRanksInto` passed parity and reported much lower managed allocation in the
same normal BenchmarkDotNet evidence tier for inspect-summary reference file lists. It ran about
18.9x faster on the representative reference corpus (1.257 us vs 23.735 us, 1.65 KB vs 32.73 KB)
and about 29.9x faster on the large generated reference corpus (4.989 us vs 149.325 us, 1.96 KB vs
111.45 KB). This is acceptance-grade benchmark evidence for `nlc query inspect` reference-file
summaries after the host has assigned compact ordinal file ranks. The production output-format
route now binds this kernel through `OutputFormatterReferenceFileKernels` instead of the broad
code-intelligence dogfood adapter.

`BindingLookupQueryDeclarationIndicesInto` passed parity and reported zero managed allocation in the
same normal BenchmarkDotNet evidence tier for strict semantic binding position lookup. It ran about
5.93x faster on the representative binding corpus (41.781 us vs 247.807 us) and about 5.22x faster
on the large generated binding corpus (646.484 us vs 3.378 ms). This is acceptance-grade benchmark
evidence for batched declaration-first binding lookup after the host has built compact binding
tables and slot arrays.

`BindingLookupCandidateColumnsInto` passed parity and reported zero managed allocation in the same
normal BenchmarkDotNet evidence tier for strict binding candidate-column ordering before lookup. It
ran about 8.26x faster on the representative candidate corpus (122.958 us vs 1.016 ms,
0 B vs 7,499,808 B) and about 7.72x faster on the large generated candidate corpus
(1.056 ms vs 8.153 ms, 0 B vs 60,005,240 B). This is acceptance-grade benchmark evidence for the
candidate ordering kernel after the host has identified the relevant source span and provided
caller-owned result buffers.

`SemanticScopeVisibleSymbolIndicesInto` passed parity and reported zero managed allocation in the
normal BenchmarkDotNet evidence tier for scoped visible-variable selection before CLI completion
item materialization. It ran about 7.35x faster on the representative semantic-scope corpus
(438.998 us vs 3.225 ms, 0 B vs 6,823,936 B) and about 19.04x faster on the large generated
semantic-scope corpus (2.473 ms vs 47.073 ms, 0 B vs 36,790,272 B). This is acceptance-grade
benchmark evidence for visible symbol selection after the host has built compact scope/symbol tables
and the sorted scope-start index.

`SemanticScopeBuildSortedIndexInto` passed parity and reported zero managed allocation in the normal
BenchmarkDotNet evidence tier for compact semantic-scope cache index construction. The production
builder-shaped benchmark measured 1.355 us vs 8.176 us on the representative source-order scope corpus
(about 6.0x, 0 B vs 4,184 B) and 10.742 us vs 84.782 us on the large generated scope corpus (about
7.9x, 0 B vs 32,856 B). This is acceptance-grade benchmark evidence for replacing the C#
`Array.Sort(order, CompareScopeStartOrder)` semantic-scope index builder when the dogfood assembly is
available, with fallback retained for unavailable or invalid N# output.

`SemanticScopeBuildDepthsInto` passed parity in the normal BenchmarkDotNet evidence tier for compact
semantic-scope cache depth construction. The production builder-shaped benchmark measured 1.523 us
vs 22.553 us on the representative nested-scope corpus (about 14.8x faster) and 12.217 us vs
562.741 us on the large generated nested-scope corpus (about 46.1x faster). The BenchmarkDotNet
memory report was present and showed no managed allocation reported for either path. This is
acceptance-grade benchmark evidence for replacing the C# per-scope parent-chain depth walk when the
dogfood assembly is available, with fallback retained for unavailable or invalid N# output.

`SemanticScopeLookupSymbolIndicesInto` passed parity in the normal BenchmarkDotNet evidence tier for
position-aware scoped identifier lookup before member-completion type materialization. It ran about
17.07x faster on the representative semantic-scope lookup corpus (210.411 us vs 3.593 ms) and about
88.04x faster on the large generated semantic-scope lookup corpus (735.576 us vs 64.750 ms). The
BenchmarkDotNet memory report was present and showed no managed allocation reported for either path.
This is acceptance-grade benchmark evidence for scoped identifier selection after the host has built
compact scope/symbol tables and the sorted scope-start index.
As of 2026-06-14 these kernels are retained as parity-corpus evidence only; the single-query public
API bridge below did not clear the production-shaped 5x gate.

`BindingLookupFindNearestDeclarationIndicesInto` passed parity and reported zero managed allocation
in the same normal BenchmarkDotNet evidence tier for nearest same-file declaration selection by
name. It ran about 231x faster on the representative declaration corpus (40.721 us vs 9.402 ms,
0 B vs 5,911,960 B) and about 903x faster on the large generated declaration corpus (58.794 us vs
53.100 ms, 0 B vs 5,911,960 B). This is acceptance-grade benchmark evidence for the source-context
definition fallback after the host has assigned stable name/file ids and sorted declaration facts.

`BindingLookupBuildNearestDeclarationIndexInto` passed parity and reported zero managed allocation in
the scoped BenchmarkDotNet run for compact `BindingMap` nearest-declaration index construction. It
ran about 6.8x faster on the representative source-ordered declaration corpus (3.460 us vs
23.383 us, 0 B vs 4,184 B) and about 6.1x faster on the large generated declaration corpus
(42.249 us vs 258.197 us, 0 B vs 32,856 B). This is acceptance-grade benchmark evidence for
replacing the C# `Array.Sort(order, CompareDeclarationOrder)` index builder when the dogfood assembly
is available, with fallback retained for unavailable, invalid, or out-of-order same-name N# output.

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

`CompletionItemKindGroupsInto` passed parity and reported zero managed allocation in the normal
BenchmarkDotNet evidence tier for member-completion item grouping before public CLI/daemon
completion output. It ran about 5.26x faster on the representative completion-item corpus
(2.827 us vs 14.865 us, 0 B vs 30,288 B) and about 5.49x faster on the large generated
completion-item corpus (22.531 us vs 123.802 us, 0 B vs 231,208 B). This is acceptance-grade
benchmark evidence for stable first-seen kind grouping after the host has assigned compact kind ids.

`CompletionMethodOverloadGroupsInto` passed parity and reported zero managed allocation in the
normal BenchmarkDotNet evidence tier for reflected CLR method overload grouping before
member-completion item construction. It ran about 14.9x faster on the representative reflected
method corpus (1.579 us vs 23.447 us, 0 B vs 47,569 B) and about 15.9x faster on the large
generated reflected method corpus (9.364 us vs 148.468 us, 0 B vs 215,382 B). This is
acceptance-grade benchmark evidence for stable first-seen method-name grouping after the host has
assigned compact method-name ids.

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

`DiagnosticClusterTraitsAndPatternsInto` passed parity through the checksum wrapper, but missed the
normal BenchmarkDotNet speed gate for combined trait and public message-pattern materialization. The
N# path measured about 1.42x faster on the representative diagnostic corpus (339.4 us vs 482.5 us)
and about 1.30x faster on the large generated diagnostic corpus (4.081 ms vs 5.291 ms), with managed
allocation reduced to about 63% of the C# formatter-shaped baseline (1.33 MB vs 2.11 MB and 10.67 MB
vs 17.01 MB). This is measured language/runtime pressure, not acceptance evidence, and the production
formatter must keep the C# message-pattern path until N# has a lower-allocation public string
construction strategy that clears the 5x gate.

`DiagnosticSeveritySummaryInto` passed parity and reported no managed allocation in the same normal
BenchmarkDotNet evidence tier for diagnostic summary counting. It ran about 5.64x faster on the
representative diagnostic corpus (783.4 ns vs 4.420 us) and about 5.46x faster on the large
generated diagnostic corpus (6.222 us vs 33.998 us). This is acceptance-grade benchmark evidence for
the diagnostic/check/lint severity-summary pass. The production output-format route now binds this
kernel through `OutputFormatterDiagnosticKernels` instead of the broad code-intelligence dogfood
adapter.

`DiagnosticShadowSuppressionIndicesInto` passed parity and reported zero managed allocation in the
short BenchmarkDotNet evidence tier for `GetDiagnostics` lint-shadowing suppression. The accepted N#
path uses compact ordinal diagnostic-code ids, case-insensitive file ranks, and a caller-owned
shadowed-file flag table. It ran about 5.75x faster on the representative diagnostic corpus
(1.335 us vs 7.673 us, 0 B vs 7,368 B) and about 6.97x faster on the large generated diagnostic
corpus (10.696 us vs 74.597 us, 0 B vs 57,736 B). This is acceptance-grade benchmark evidence for
the source-order-preserving `NL020` suppression pass before combined diagnostic deduplication.

`ReferenceFileSummaryRanksInto` also passed parity for clustered diagnostic file-list materialization
after the host has assigned compact case-insensitive file ranks. In the normal BenchmarkDotNet
evidence tier, the `CompilerServiceDiagnosticClusterFileListBenchmarks` route ran about 27.8x faster
on the representative diagnostic file corpus (1.108 us vs 30.813 us, 1.26 KB vs 29.6 KB) and about
32.4x faster on the large generated diagnostic file corpus (4.821 us vs 156.270 us, 1.4 KB vs
173.69 KB). This is acceptance-grade benchmark evidence for clustered diagnostic `files` lists while
preserving the public case-insensitive distinct/order contract. The production output-format route
now binds this kernel through `OutputFormatterReferenceFileKernels` instead of the broad
code-intelligence dogfood adapter.

`DiagnosticDeduplicateCompactInto` passed parity and reported zero managed allocation in the same
normal BenchmarkDotNet evidence tier for check/build diagnostic deduplication. It ran about 13.38x
faster on the representative diagnostic corpus (7.877 us vs 105.425 us, 0 B vs 63,656 B) and about
12.63x faster on the large generated diagnostic corpus (86.654 us vs 1,094.624 us, 0 B vs
500,952 B). This is acceptance-grade benchmark evidence for the compact integer diagnostic
deduplication kernel after the host has assigned default-comparer file sort ranks.

`DiagnosticDeduplicateStableInto` passed parity and reported zero managed allocation in the same
normal BenchmarkDotNet evidence tier for `GetDiagnostics` duplicate removal while preserving the
old first-seen result order. It ran about 14.4x faster on the representative diagnostic corpus
(3.693 us vs 53.242 us, 0 B vs 56,672 B) and about 13.6x faster on the large generated diagnostic
corpus (36.395 us vs 494.160 us, 0 B vs 450,960 B). This is acceptance-grade benchmark evidence
for stable duplicate removal after the host has assigned compact code/file/message ids.

`DiagnosticClusterCompactGroupsInto` passed parity and reported zero managed allocation in the same
normal BenchmarkDotNet evidence tier for the clustered diagnostic grouping kernel. It ran about 6.76x
faster on the representative diagnostic cluster corpus (16.570 us vs 111.999 us, 0 B vs 141,136 B)
and about 10.59x faster on the large generated diagnostic cluster corpus (77.336 us vs 819.389 us,
0 B vs 719,184 B). This is acceptance-grade benchmark evidence for the compact integer grouping
shape after category/source/rewrite/message dimensions have been classified.

`DiagnosticClusterCompactGroupMembersInto` passed parity and reported zero managed allocation in the
same normal BenchmarkDotNet evidence tier for post-group diagnostic member indexing. The first
candidate only removed allocation because it still rescanned all diagnostics once per group; the
accepted kernel hashes the sorted group roots, scans diagnostics once, keeps per-group linked lists
ordered by root location, and flattens member indices into caller-owned buffers. It ran about 43.6x
faster on the representative diagnostic cluster corpus (11.179 us vs 487.282 us, 0 B vs 32,840 B)
and about 66.8x faster on the large generated diagnostic cluster corpus (115.806 us vs 7.741 ms,
0 B vs 65,664 B). The production clustered-diagnostic formatter now consumes those N# member spans
instead of running the former C# per-group scan and sort.

`DiagnosticClusterIdsInto` passed parity but missed the normal BenchmarkDotNet speed gate for public
cluster id string materialization. After replacing per-id hex `ToString("x")` and final string
concatenation with a reusable N# char buffer, the N# path avoided the temporary composite key
allocation and reduced managed allocation to about 10% of the current C# formatter-shaped baseline,
but it measured only about 1.19x faster on the representative diagnostic cluster corpus (235.9 us vs
281.3 us) and about 1.26x faster on the large generated diagnostic cluster corpus (1.913 ms vs
2.417 ms). This is measured language/runtime pressure, not acceptance evidence, and the production
formatter must keep the C# id path until N# has a faster short-string/hex materialization strategy
that clears the 5x gate.

`DiagnosticClusterNextCommandsInto` passed parity but also missed the normal BenchmarkDotNet speed
gate for public next-command string materialization. After reusing one `StringBuilder` across the N#
batch and keeping direct path escaping, the N# path measured about 1.54x faster on the representative
diagnostic cluster corpus (46.920 us vs 72.298 us) and about 1.78x faster on the large generated
diagnostic cluster corpus (370.855 us vs 658.986 us), with managed allocation reduced to about 63%
of the C# formatter-shaped baseline. This is measured language/runtime pressure, not acceptance
evidence, and the production formatter must keep the C# next-command path until N# has a
lower-allocation public string construction strategy that clears the 5x gate.

`CodeIntelligencePathMatches` passed parity but missed the normal BenchmarkDotNet speed gate for
code-intelligence file-path matching. The C# helper allocates slash-normalized strings but then uses
optimized `Equals`/`EndsWith(StringComparison.OrdinalIgnoreCase)` calls. The N# direct char-loop path
removed all managed allocation but measured about 1.53x slower in the single-call adapter shape on
both representative and large corpora (16.347 us vs 10.683 us and 129.141 us vs 84.453 us). The
batch-shaped N# row was also slower at about 1.43x representative and 1.39x large (15.328 us vs
10.683 us and 117.294 us vs 84.453 us). This is measured code-intelligence string-comparison
pressure, not acceptance evidence, and production path matching must keep the current C# helper
until N# has a faster slash-normalized ordinal-ignore-case comparison primitive.

`TextEditOrderIndicesInto` passed parity and reported zero managed allocation in the same normal
BenchmarkDotNet evidence tier for edit application ordering. It ran about 6.7x faster on the
representative edit corpus (5.177 us vs 34.476 us, 0 B vs 70,808 B) and about 11.6x faster on the
large generated edit corpus (40.948 us vs 476.531 us, 0 B vs 558,232 B). This is
acceptance-grade benchmark evidence for `FixApplicator` text-edit ordering after the host has
assigned compact start/end position ranks. The production route now binds this kernel through
`FixApplicatorTextEditOrderer` beside the edit application code instead of through the broad
code-intelligence dogfood adapter.

`TypoSuggestionIndicesInto` passed parity against `SmartSuggester.SuggestSimilarNames` and reported
zero managed allocation, but missed the normal BenchmarkDotNet speed gate for typo-suggestion
scoring. The N# path measured about 1.83x slower on the representative typo corpus (5.409 ms vs
2.956 ms, 0 B vs 7,812,704 B) and about 2.01x slower on the large generated typo corpus
(1.080 s vs 536.405 ms, 0 B vs 1,242,163,808 B). This is measured language/runtime pressure, not
acceptance evidence. The production compiler must keep the current C# `SmartSuggester` path until
N# has faster bounds-check elimination, row-buffer access, or a better systems-memory primitive for
small dynamic-programming tables.

`AotRequirementGroupsInto` passed parity and reported zero managed allocation in the normal
BenchmarkDotNet evidence tier for public AOT blocker requirement grouping. It ran about 16.2x faster
on the representative blocker corpus (3.078 us vs 49.735 us, 0 B vs 154,824 B) and about 17.5x
faster on the large generated blocker corpus (26.217 us vs 458.017 us, 0 B vs 1,237,176 B). This is
acceptance-grade benchmark evidence for AOT requirement grouping after the host has assigned compact
declaration ranks, construct ranks, and blocker-kind ids.

`StructCopyAllInstanceFieldsInitOnly` passed parity and reported zero managed allocation in the
short BenchmarkDotNet evidence tier for declared-field readonly gating. It ran about 7.2x faster on
the representative all-readonly field corpus (164.3 ns vs 1,175.9 ns, 0 B vs 7,120 B), about 7.4x
faster when the last instance field was mutable (164.5 ns vs 1,213.2 ns, 0 B vs 7,120 B), about
7.2x faster on the large generated all-readonly field corpus (1.274 us vs 9.115 us, 0 B vs
56,272 B), and about 7.2x faster on the large generated last-instance-mutable field corpus
(1.274 us vs 9.155 us, 0 B vs 56,272 B). This is acceptance-grade benchmark evidence for replacing
the C# `Where(...).ToList().All(...)` readonly-field gate after the host has projected compact
static-or-readonly field flags.

`NullableFlagsAllOne` was measured as a rejected direct-`List<byte>` nullable metadata candidate on
2026-06-05 and removed instead of being routed. The completed representative all-default row measured
the N# direct indexed scan slower than the current .NET 10 C# `flags.All(flag => flag == 1)` path
(322.938 ns vs 264.926 ns), despite avoiding LINQ at the source level. This is useful systems-language
pressure: direct N# `List<T>` indexer loops are not automatically faster than current BCL-specialized
LINQ, so nullable metadata emission should keep its C# gate until the rewrite can use a compact array,
span-like storage, or a proven lower-overhead list scan.

`AnonymousUnionDeclaresPublicShim` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for anonymous-union overload-shim eligibility. It ran about 9.0x
faster on representative dense two-arm-union parameters (148.51 ns vs 1,332.68 ns, 0 B vs 8,296 B)
and about 9.0x faster when the last dense union parameter was disallowed (153.04 ns vs
1,376.06 ns, 0 B vs 8,296 B). With sparse two-arm-union parameters, it ran about 16.8x faster on the
representative eligible corpus (30.22 ns vs 508.17 ns, 0 B vs 1,744 B) and about 18.2x faster when
the last sparse union parameter was disallowed (28.34 ns vs 517.05 ns, 0 B vs 1,744 B). The large
generated rows stayed above the gate: about 9.4x and 9.3x faster on dense shapes, and about 16.0x
and 15.5x faster on sparse shapes. This is acceptance-grade benchmark evidence for replacing the
C# `Where(...).ToList().All(...)` eligibility gate after the host has projected compact
anonymous-union parameter flags.

`FirstDistinctRankIndicesInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for first-source implemented-interface de-duplication. It ran about
36.2x faster on the representative interface corpus (1.081 us vs 39.119 us, 0 B vs 39,784 B) and
about 46.7x faster on the large generated interface corpus (6.990 us vs 326.717 us, 0 B vs
209,704 B). This is acceptance-grade benchmark evidence for the IL compiler's type-key
de-duplication after the host has expanded direct/inherited interfaces and assigned compact ordinal
type-key ranks.

`DeclaredTypeUniqueSuffixValueRank` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for declared project-type suffix lookup. It ran about 11.1x faster on
the representative unique-short-name corpus (766.10 ns vs 8.518 us, 0 B vs 66,168 B), about 9.1x
faster on representative three-character suffix lookup (768.36 ns vs 6.967 us, 0 B vs 33,400 B),
about 11.9x faster on representative exact-full-name lookup (771.26 ns vs 9.144 us, 0 B vs
107,024 B), about 10.2x faster on representative missing lookup (760.20 ns vs 7.787 us, 0 B vs
65,904 B), and about 8.5x faster on representative ambiguous lookup (36.25 ns vs 306.51 ns, 0 B vs
2,312 B). On the large generated corpus it ran about 10.8x faster for unique short-name lookup
(6.085 us vs 65.424 us, 0 B vs 524,920 B), about 8.9x faster for three-character suffix lookup
(6.103 us vs 54.548 us, 0 B vs 262,776 B), about 12.0x faster for exact full-name lookup (6.050 us
vs 72.668 us, 0 B vs 852,496 B), about 10.2x faster for missing lookup (6.050 us vs 61.721 us, 0 B
vs 524,656 B), and about 8.4x faster for ambiguous lookup (36.31 ns vs 305.61 ns, 0 B vs 2,312 B).
This is acceptance-grade benchmark evidence for suffix lookup after the host has projected declared
type dictionaries into compact ordinal key/value-rank/query-width tail-hash arrays.

`DeclaredTypeNameCandidateIndex` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for declared type-name candidate selection. It ran about 88x faster on
representative imported, unique, tiny, ambiguous, and missing suffix lookups (roughly 488-515 ns vs
43.102-45.028 us, 0 B vs 114,312-146,760 B), about 93.6x faster on representative exact full-name
lookup (511.9 ns vs 47.894 us, 0 B vs 203,808 B), and about 93x-105x faster on the large generated
corpus (3.920-4.065 us vs 376.646-411.503 us, 0 B vs 650,538-1,370,818 B). This is
acceptance-grade benchmark evidence for declared-name disambiguation after the host has projected
declared names and imported-namespace membership into compact ordinal arrays.

`TypeCreationOrderIndicesInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for IL compiler type creation ordering. It ran about 7.2x faster on
the representative corpus (22.15 us vs 159.85 us, 0 B vs 57,648 B) and about 7.6x faster on the
large generated corpus (179.48 us vs 1,355.23 us, 0 B vs 459,056 B). This is acceptance-grade
benchmark evidence for stable descending type-key-depth ordering after the host has projected
`TypeBuilder` keys into compact arrays.

`AnalyzerMissingMemberIndicesInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for enum-match missing-member selection. It ran about 76x faster on
the representative missing-every-fourth corpus (540.1 ns vs 41.169 us), about 116x faster on the
representative one-missing-near-end corpus (351.8 ns vs 40.728 us), and about 115x faster on the
representative all-covered corpus (396.5 ns vs 45.621 us). On the large generated corpus it ran
about 86x faster for missing-every-fourth (6.051 us vs 523.441 us), about 241x faster for
one-missing-near-end (2.251 us vs 543.218 us), and about 133x faster for all-covered
(2.051 us vs 273.501 us). This is acceptance-grade benchmark evidence for replacing the analyzer's
C# `ToHashSet().Except().ToList()` missing-member selection after the host has projected covered
enum members into declaration-order flags.

`AnalyzerUnionMissingCaseIndicesInto` passed parity and reported zero managed allocation in the
short BenchmarkDotNet evidence tier for union-match missing-case partitioning. With compact
declaration-order covered/partial flags already available, the raw source-index kernel ran about
49x faster on the representative missing-every-fourth corpus (702.3 ns vs 34.107 us), about 77x
faster on the representative one-partial/one-never corpus (271.3 ns vs 20.778 us), and about 69x
faster on the representative all-covered corpus (268.8 ns vs 18.559 us). On the large generated
corpus it ran about 56x faster for missing-every-fourth (5.533 us vs 307.689 us), about 122x faster
for one-partial/one-never (2.049 us vs 249.756 us), and about 108x faster for all-covered
(2.042 us vs 219.967 us).

The production-shaped materialized route also cleared the speed gate after diagnostic case names
were materialized from the compact source-index buffers. It ran about 19x faster on representative
missing-every-fourth unions (1.762 us vs 34.107 us), about 68x faster on representative
one-partial/one-never unions (303.5 ns vs 20.778 us), and about 66x faster on representative
all-covered unions (281.5 ns vs 18.559 us). On the large generated corpus it ran about 20x faster
for missing-every-fourth (15.258 us vs 307.689 us), about 119x faster for one-partial/one-never
(2.093 us vs 249.756 us), and about 107x faster for all-covered (2.059 us vs 219.967 us). This is
acceptance-grade evidence for routing `Analyzer.CheckMatchExhaustiveness` through the compact
systems-language primitive after the analyzer builds declaration-order coverage flags directly.
The late C# set-to-flag projected row remains intentionally unrouted: it only reached about 1.9x to
3.3x on the same corrected benchmark rows.

Current CLI dogfood benchmarks:

- `CliQueryPositionParsingBenchmarks` targets `nlc query --pos line:col` parsing and daemon query
  dispatch position parsing. The C# baseline mirrors the current command parser shape: split on
  `:` and parse the two pieces with `int.TryParse`. The N# candidate scans once, handles
  whitespace/signs/overflow to match `int.TryParse` behavior, and writes line/column values into
  caller-owned buffers through `CliQueryPositionsInto`.
- `CliQueryBatchDuplicateIdBenchmarks` targets duplicate request-id validation in `nlc query
  batch`. The C# baseline mirrors the previous CLI LINQ shape: ignore null/whitespace ids, group
  by ordinal string id, keep groups with more than one request, and sort duplicate ids by ordinal
  string order. The N# candidate runs after the host has assigned dense sorted ordinal ranks to
  nonblank ids, counts duplicate ranks in caller-owned buffers, and returns the duplicate ranks in
  public error-order through `CliBatchDuplicateIdRanksInto`.
- `CliQueryBatchResultCountBenchmarks` targets success/failure summary counting after `nlc query
  batch` has executed each request. The C# baseline mirrors the current command shape:
  `items.Count(item => item.Ok)` followed by derived failure count. The accepted N# route retains
  successful-item flags in compact `ulong` words while public result objects are created, then
  counts set bits through `CliBatchResultPackedSuccessCount`; the projected row measures the old
  object-to-bitset adapter shape separately and is not routed.
- `CliTestOutcomeSummaryBenchmarks` targets `nlc test` text/JSON summary counting after the native
  test runner has produced public result objects. The C# baseline mirrors the current text-output
  shape: one `All(...)` pass for `ok`, then three `Count(...)` passes for passed/failed/skipped.
  The accepted N# route runs after the xUnit/reflection runners retain compact outcome ranks as
  results are created, then computes `ok`, passed, failed, and skipped in one pass through
  `CliTestOutcomeSummaryInto`. The benchmark also keeps a projected string-to-rank row to prove
  late projection is not the accepted production shape.
- `CliFormatDiscoveryBenchmarks` targets `nlc format` discovered-file filtering after filesystem
  traversal has produced normalized project-relative paths. The C# baseline mirrors the current
  split/segment helper that excludes VCS/build/cache/tooling directories and `test(s)/fixtures`.
  The N# candidates scan path segments without allocation through `CliShouldFormatDiscoveredPath`
  and `CliFormatDiscoveredPathFlagsInto`, but they remain benchmark-only because measured wall-clock
  speed missed the production gate.
- `CliWatchForwardingBenchmarks` targets `nlc watch` forwarded-argument selection. The C# baseline
  mirrors the current command shape: copy `args.Skip(1).ToArray()`, scan with a list, skip watch-only
  options and help flags, then materialize the forwarded argument array. The N# pressure candidate
  scans the original argv from index one and writes forwarded source indices through
  `CliWatchForwardedArgIndicesInto`, but it remains benchmark-only because measured wall-clock speed
  missed the production gate.
- `CliTestFilterMatchingBenchmarks` targeted `nlc test --filter` test-case selection. The C# baseline
  mirrored the current per-candidate predicate: split the public filter on `|`, trim/remove empty
  parts, and run ordinal-ignore-case contains checks against display and fully-qualified names. The
  N# pressure candidate scanned pre-trimmed filter parts over projected candidate-name arrays and
  wrote selected source indices through `CliTestFilterMatchIndicesInto`; it was intentionally not
  routed because the measured speedup missed the 5x production gate, and the unrouted probe has since
  been retired from the dogfood compiler-service source.
- `CliDiagnosticSeverityFilterBenchmarks` targets diagnostic severity filtering in
  `nlc query diagnostics`, batch diagnostics, and daemon diagnostics. The C# baseline mirrors the
  current CLI LINQ shape: case-insensitive severity comparison and list materialization. The N#
  candidate runs after the host has assigned compact `StringComparer.OrdinalIgnoreCase` severity
  ranks, scans an unrolled rank array, and writes matching diagnostic indices through
  `DiagnosticSeverityFilterIndicesInto`.
- `CliCompilerErrorSeverityFilterBenchmarks` targets compiler-error severity filtering in
  `nlc check` backend verification and `nlc lint` parse-error reporting. The C# baseline mirrors the
  current CLI LINQ shape: enum severity comparison and list materialization over `CompilerError`
  objects. The N# candidate reuses the compact severity-rank scanner after the host has projected
  `ErrorSeverity` values into small integer ranks.
- `CliFixSafetyFilterBenchmarks` targets `nlc fix` safety filtering before text edits are collected
  and validated. The C# baseline mirrors the current CLI LINQ shape: enum safety checks and list
  materialization over fix objects. The N# candidate runs after the host has projected `FixSafety`
  values into compact ranks, preserves source order, applies the safe-only or include-review-needed
  threshold, and writes matching fix indices through `CliFixSafetyFilterIndicesInto`.
- `CliFixSkippedSelectionBenchmarks` targets skipped-fix selection in `nlc fix --text` output after
  the accepted fixes have been applied. The C# baseline mirrors the previous text-output shape:
  `results.Where(r => !applied.Contains(r)).ToList()`. The accepted N# candidate runs after the
  host has projected fix safety strings into compact ranks, preserves the default
  safe-only/include-review-needed behavior, treats unknown safety values as skipped, and writes
  skipped source indices through `CliFixSkippedIndicesInto`.
- `CliFixAppliedFileGroupingBenchmarks` targets applied-fix grouping in `nlc fix --text` output.
  The C# baseline mirrors the current text-output shape: `applied.GroupBy(f => f.File)` plus
  per-group materialization. The accepted N# candidate runs after the host has assigned first-seen
  dense file ranks, then writes group ranks, group spans, and grouped source indices through
  `CliFixAppliedFileGroupsInto`.
- `CliUnifiedDiffHunkBenchmarks` targets unified-diff hunk range construction in
  `nlc format --diff` after the line diff has been produced. The C# baseline mirrors the previous
  `UnifiedDiff.BuildHunks` LINQ shape: collect changed indices, build ranges, materialize hunk
  slices, and count old/new lines. The accepted N# candidate writes hunk ranges and metadata through
  `CliUnifiedDiffHunkRangesInto`, letting the host render directly from the original diff lines
  without materializing hunk objects or slice arrays.
- `CliTidyDependencyFilterBenchmarks` targets `nlc tidy --fix` dependency removal selection after
  dependencies have been classified. The C# baseline mirrors the command fallback shape:
  `results.Where(r => r.Status == "possibly-unused").ToList()`. The accepted N# candidate reuses
  the compact rank filter after the host has projected tidy status strings into integer ranks, then
  writes possibly-unused source indices through caller-owned buffers.
- `CliTidyStatusSummaryBenchmarks` targets `nlc tidy` status summary calculation after dependencies
  have been classified. The C# baseline mirrors the previous command shape: one `All(...)` pass to
  compute the JSON `ok` value, then two `Count(...)` passes for the text summary's possibly-unused
  and unknown counts. The accepted N# candidate scans compact tidy status ranks once through
  `CliTidyDependencyStatusSummaryInto` and writes summary counts into caller-owned storage.
- `CliTidyDependencyClassificationBenchmarks` targets `nlc tidy` dependency usage classification.
  The C# baseline mirrors the current command shape: split the package name, join the first two
  segments, then scan imports with case-insensitive prefix checks. The accepted N# candidate scans
  ASCII package/import strings directly, writes compact status ranks through
  `CliTidyDependencyStatusRanksInto`, and leaves non-ASCII names on the exact C# fallback.
- `CliTidyRemovalLineBenchmarks` targets `nlc tidy --fix` project.yml dependency-line removal after
  dependency names have been selected for removal. The C# baseline mirrors the current command
  shape: trim each line, check list-item syntax, then scan every package with case-insensitive
  interpolated `StartsWith`/`Contains` patterns and materialize a filtered list. The accepted N#
  candidate scans ASCII project lines and package names directly, preserves the current broad
  `- Package` prefix behavior, and writes keep/remove flags through caller-owned storage.
- `CliFixEditFlattenBenchmarks` targets safe-edit flattening in `nlc fix` after the safety gate has
  selected applicable actions. The C# baseline mirrors the current CLI shape:
  `safeActions.SelectMany(action => action.Edits).ToList()`. The N# pressure candidate runs after
  the host has projected each safe action's edit count, then writes flattened action/edit indices
  through `CliFixEditFlattenIndicesInto`.
- `CliSymbolKindFilteringBenchmarks` targets symbol-kind filtering in `nlc query symbols --kind`,
  batch symbol queries, and daemon symbol queries. The C# baseline mirrors the current query LINQ
  shape: enum comparison, list materialization, and stable source-order results. The N# candidate
  runs after the host has projected symbol kinds into compact integer ids, scans an unrolled kind-id
  array, and writes matching symbol indices through `SymbolKindFilterIndicesInto`.
- `CliSymbolNameFilterBenchmarks` targets name filtering in `nlc query symbols --filter`. The C#
  baseline mirrors the current CLI regex path: build a case-insensitive regex, filter symbol names,
  stop at 200 matches, and materialize the result. The accepted N# candidate handles ASCII glob
  patterns in systems code, specializes prefix/suffix globs, routes ASCII bare substring patterns
  through a compiled N# index filter with `StringComparison.OrdinalIgnoreCase`, and writes matching
  symbol indices through `CliSymbolNameGlobFilterIndicesInto` or
  `CliSymbolNameSubstringFilterIndicesInto`.
- `CompilerServiceDocQueryBestTypeBenchmarks` targets candidate selection in `nlc query doc` type
  lookup. The C# baseline mirrors the current post-scoring LINQ selection shape: order by descending
  match score, then namespace length, then full name with ordinal-ignore-case comparison, and take
  the first candidate. The accepted N# candidate runs after the host has projected distinct
  reflection candidates into score/namespace/full-name arrays and selects the best index with an
  eight-wide unrolled scan through `DocQueryBestTypeIndex`.
- `CompilerServiceDocQueryMemberOrderingBenchmarks` targets member ordering inside `nlc query doc`
  type descriptions. The C# baseline mirrors `DocQuery.GetTypeMembers`: order by member kind, then
  by member name with ordinal-ignore-case comparison, and materialize the array. The accepted N#
  candidate runs after the host has projected fixed member-kind ranks and exact .NET
  ordinal-ignore-case name ranks, then uses stable counting passes through
  `DocQueryMemberOrderIndicesInto`.
- `CliFirstPositionalArgumentBenchmarks` targets CLI commands that only need the first positional
  operand, such as project-name/project-root discovery, `nlc update` target package selection, and
  `nlc export csharp` input discovery. The
  C# baseline mirrors the previous shared helper shape: build every positional string, materialize
  the result array, then read index zero. The accepted N# candidate returns the first positional
  source index through `CliFirstPositionalArgIndex`, letting the host read only that string and skip
  the rest of the positional materialization.
- `CliLintFileArgBenchmarks` targets positional file-argument extraction in `nlc lint`. The C#
  baseline mirrors the current command shape: filter non-flags with LINQ, then rescan the full
  argument array for each candidate to remove values belonging to `--project`. The accepted N#
  candidate records project-value source indices once, writes accepted file-argument source indices
  through `CliLintFileArgIndicesInto`, and lets the host materialize the final string array at the
  command boundary.
- `CliUpdateAllDependencyFilterBenchmarks` targets all-NuGet dependency selection in `nlc update`
  when no package name is supplied. The C# baseline mirrors the fallback no-target filter:
  materialize dependencies whose `Nuget` field is present. The accepted N# candidate runs after the
  host has projected compact NuGet-present flags and scans the flag array through
  `CliUpdateAllNuGetDependencyIndicesInto`.
- `CliUpdateDependencyFilterBenchmarks` targets target-package narrowing in `nlc update` after the
  command has parsed `project.yml` and decided a package name was supplied. The C# baseline mirrors
  the fallback target filter: keep NuGet dependencies whose package name matches the target with
  ordinal-ignore-case comparison. The accepted N# candidate runs after the host has assigned
  case-insensitive package-name ranks, reserves rank 0 for non-NuGet dependencies, and scans only
  the rank array through `CliUpdateTargetNuGetDependencyIndicesInto`.
- `CliBuildArgumentNormalizationBenchmarks` targets `nlc build` source-file operand discovery. The
  C# baseline mirrors the current build command shape: remove value-less build flags with LINQ, run
  four option-with-value stripping passes, materialize the normalized operand array, then read the
  first operand. The accepted N# candidate returns the first source operand index through
  `CliBuildFirstOperandIndexInto`; it exits immediately for the common source-first path and falls
  back to an exact linked-list scratch routine when leading options require the existing stripping
  order.
- `CliBuildOptionSummaryBenchmarks` targets the remaining `nlc build` option discovery work after
  source-operand routing. The C# baseline mirrors the current command shape: separate
  `args.Contains(...)` scans for help/release/verbose/timings/perf-report/AOT plus separate
  `GetOptionValue` scans for `--output`/`-o`, `--backend`, and `--project`. The N# pressure
  candidate scans argv once and writes option value indices plus flags through
  `CliBuildOptionSummaryInto`, but it remains benchmark-only because measured wall-clock speed
  missed the production gate.
- `CliRunArgumentNormalizationBenchmarks` targets `nlc run` source-file operand discovery. The C#
  baseline mirrors the previous run command shape: strip `--backend <value>` into a new array, then
  read the first remaining argument. The accepted N# candidate returns the first source operand
  index through `CliRunFirstOperandIndex`, preserving dangling `--backend` and unknown-flag
  behavior without materializing a stripped argument array.
- `CliPublishArgumentNormalizationBenchmarks` targets `nlc publish` option validation and option
  value discovery. The accepted production route is intentionally limited to the default no-argument
  publish path, where the N# candidate returns the default summary through `CliPublishOptionsInto`
  without allocating validation sets. Option-bearing rows are pressure evidence only and stay on the
  exact C# fallback because they do not clear the 5x speed gate yet.
- `CliExportCSharpArgumentNormalizationBenchmarks` targets `nlc export csharp` input operand
  discovery. The C# baseline mirrors the current export command shape: run three
  option-with-value stripping passes for `--output`, `-o`, and `--project`, materialize each
  intermediate array, then scan for the first positional operand. The accepted N# candidate returns
  the first source operand index through `CliExportCSharpFirstOperandIndexInto`; it exits
  immediately for the common source-first path and falls back to the same linked-list removal
  strategy when leading options require exact ordered stripping.
- `CliExportReferenceDeduplicationBenchmarks` targets stable first-source reference de-duplication
  in `nlc export csharp` after project, framework, DLL, and package references have been resolved
  to host values. The C# baseline mirrors the command fallback shape for string references:
  ordinal-ignore-case `Distinct` plus materialization. The accepted N# candidate runs after the host
  has assigned compact equality ranks and writes first-source indices through
  `CliStableDistinctRankIndicesInto`.
- `CliRestoreProjectReferenceDeduplicationBenchmarks` targets stable first-source
  project-reference de-duplication in `nlc restore` after N# project references have been resolved
  to MSBuild project paths. The C# baseline mirrors the restore fallback shape:
  ordinal-ignore-case `Distinct` plus array materialization. The accepted N# candidate reuses the
  compact equality-rank stable distinct kernel and writes first-source indices through
  `CliStableDistinctRankIndicesInto`.
- `CliReferenceResolutionBestScoreBenchmarks` targets the score-selection kernel inside CLI
  compilation reference resolution. The C# baseline mirrors the current asset-directory candidate
  shape: filter candidates with non-negative compatibility scores, sort by descending score, and
  take the first candidate. The N# pressure candidate runs after the host has projected compatibility
  scores into primitive arrays and selects the first highest-scoring candidate through
  `CliReferenceResolutionBestScoreIndex`, but it remains benchmark-only because representative
  timings missed the production gate.
- `CliDocOrderingBenchmarks` targets symbol filtering and ordering before `nlc doc` page generation.
  The C# baseline mirrors the previous CLI LINQ shape: filter variable/parameter symbols, order by
  `SymbolKind.ToString()` with ordinal string comparison, then order by symbol name and materialize
  the list. The accepted N# candidate runs after the host has assigned dense kind/name ranks and
  uses two stable counting passes to return ordered source indices through
  `CliDocSymbolOrderCountingIndicesInto`.
- `CliDocMemberOrderingBenchmarks` targets member ordering inside generated `nlc doc` symbol pages.
  The C# baseline mirrors the previous symbol-page LINQ shape: order every member by
  `SymbolKind.ToString()` with ordinal string comparison, then order by member name and materialize
  the list. The accepted N# candidate reuses the compact kind/name rank counting-order kernel with
  all include flags set, preserving full member inclusion while avoiding comparison-sort and list
  allocation on the hot ordering path.
- `CliDocSlugBenchmarks` targets generated `nlc doc` symbol-page slug materialization. The C#
  baseline mirrors the previous production slugifier: lower-case the raw kind/name/file slug, map
  non-letter/digit characters through LINQ, allocate an intermediate string, split on separators,
  and join the remaining parts. The accepted N# candidate batches raw slugs, grows one reusable
  char scratch buffer as needed, uses an ASCII-specialized hot path with Unicode fallback, and
  materializes only the final slug strings through `CliDocSlugsInto`.
- `CliTreeDependencyDeduplicationBenchmarks` targets dependency deduplication and ordering before
  `nlc tree` renders JSON or text output. The C# baseline mirrors the previous CLI LINQ shape:
  group dependencies by ordinal kind and case-insensitive name, keep the first dependency in each
  group, then order by kind and name. The accepted N# candidate runs after the host has assigned
  compact kind/name ranks, uses stable counting passes to preserve first-source dependency
  selection, and returns ordered source indices through `CliTreeDependencyDeduplicateIndicesInto`.
- `CliCleanArtifactDirectoryBenchmarks` targets artifact directory selection in `nlc clean` after
  filesystem enumeration has identified existing directories. The C# baseline mirrors the previous
  post-IO LINQ shape: ordinal `Distinct`, exclude `node_modules`, keep `bin`/`obj`/`.nlc`, then
  stably `OrderByDescending` path length before deletion. The accepted N# candidate runs after the
  host has projected artifact-kind flags, node_modules flags, ordinal path ranks, and path lengths,
  then uses caller-owned buffers for first-source de-duplication and stable descending-length order
  through `CliCleanArtifactDirectoryIndicesInto`.
  Both MSBuild-derived tree output and pure `project.yml` tree output now route through the accepted
  `TreeCommand.Deduplicate` helper before rendering.
  A focused 2026-06-04 validation run measured 4.598 us vs 155.891 us on the representative corpus
  (about 33.9x faster) and 36.362 us vs 2.318 ms on the large generated corpus (about 63.8x faster),
  with zero managed allocation reported on the N# benchmark path.

`CliQueryPositionsInto` passed parity and reported zero managed allocation in the normal
BenchmarkDotNet evidence tier, but missed the speed gate for CLI position parsing. The best measured
N# path now uses a simple positive `line:column` fast path, ASCII-first whitespace checks, and
branch overflow checks instead of per-digit division. It ran about 2.46x faster on the
representative position corpus (11.17 us vs 27.49 us, 0 B vs 107,056 B) and about 2.43x faster on
the large generated position corpus (90.57 us vs 220.43 us, 0 B vs 857,760 B). This is measured CLI
command-orchestration pressure, not acceptance evidence, and the production CLI/daemon position
parser must keep the current C# path until N# helper-call and small string parsing overhead clears
the 5x gate.

`CliPositionalArgIndicesInto` passed parity but missed the normal BenchmarkDotNet speed gate for
shared CLI positional-argument filtering. The production-shaped benchmark, including final string
array materialization, measured about 1.06x slower on the representative argument corpus (5.778 us
vs 5.461 us) and about 1.06x slower on the large generated argument corpus (46.031 us vs
43.272 us), while reducing managed allocation to about 26%-27% of the C# helper shape. This is
measured CLI command-parser pressure, not acceptance evidence, and production CLI argument parsing
for commands that need every positional operand must keep the current C# helper until N# string
comparison/helper-call overhead clears the 5x gate.

`CliWatchForwardedArgIndicesInto` passed parity but missed the dry BenchmarkDotNet speed gate for
`nlc watch` forwarded-argument selection. The production-shaped benchmark, including final string
array materialization, measured 99.541 us vs 150.750 us on the representative corpus and 717.333 us
vs 1.142 ms on the large generated corpus, while reducing managed allocation to about 16% of the C#
command shape. This is useful allocation-pressure evidence only: the best dry run reached about
1.5x to 1.6x, so `WatchCommand` must stay on the current C# forwarded-argument helper until N#
string option classification and host-boundary materialization can clear the 5x route gate.

`CliBuildOptionSummaryInto` passed parity but missed the dry BenchmarkDotNet speed gate for the
remaining `nlc build` option-discovery work. The production-shaped benchmark measured 81.791 us vs
95.750 us on the representative corpus and regressed on the large generated corpus at 503.041 us vs
202.833 us. Both paths reported zero managed allocation. This is argv-classification pressure
evidence only, not a production route; `BuildCommand` should keep the current C# `Contains` and
`GetOptionValue` scans for option values and booleans until N# string/array iteration overhead drops
enough to clear the 5x gate.

Two additional low-level CLI orchestration candidates were measured and deliberately removed
instead of being routed into production because they did not clear the speed gate. A caller-owned
command-argument tail copy reduced allocation pressure but measured only 87.742 ns vs 95.460 ns on
the representative corpus and regressed on the large corpus (12.409 us vs 10.387 us), so
`args.Skip(1).ToArray()` remains the boundary until N# has a faster reference-array copy primitive
or can call the BCL array-copy path without extra overhead. A follow-up 2026-06-05 probe that
allocated the exact N# result array and called `Array.Copy` directly from N# also missed the gate:
307.765 ns vs 309.268 ns on the representative corpus, and a large-corpus regression of 1.971 us vs
1.641 us, with essentially identical allocation. Top-level command classification by ASCII literal
comparison removed lowercase string allocation but measured 9.951 us vs 9.670 us on representative
command batches and 77.516 us vs 77.920 us on large batches, so the current C# `raw.ToLower()`/switch
dispatcher remains.

`CliBatchResultPackedSuccessCount` passed parity and reported zero managed allocation for the
packed-flag kernel once successful-item flags are already represented as `ulong` words. A short
validation run on 2026-06-05 measured the N# packed kernel about 18.0x faster on the representative
mixed corpus (26.435 ns vs 476.825 ns), about 11.4x faster on representative all-success
(26.431 ns vs 300.052 ns), and about 10.0x faster on representative all-failure
(26.436 ns vs 264.257 ns). On the large generated corpus it ran about 10.6x faster for mixed
results (220.545 ns vs 2.349 us), about 10.7x faster for all-success
(219.933 ns vs 2.355 us), and about 10.2x faster for all-failure (219.062 ns vs 2.237 us).
The projected adapter row remains intentionally unrouted because packing current C#
`BatchQueryItemResult` objects after the fact measured slower than the existing C# count on every
row in that run.
`BatchQueryRunner` therefore retains the packed ok flags as each public result object is created and
routes success/failure summary counting through the N# packed kernel. It keeps the existing C#
`items.Count(item => item.Ok)` count as the fallback when the dogfood assembly is unavailable or
returns invalid data.

`CliTestOutcomeSummaryInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for `nlc test` summary calculation after the runner has retained
compact outcome ranks. It ran about 15.7x faster on the representative all-passed corpus
(276.6 ns vs 4.333 us), about 17.7x faster on representative mostly-passed results
(282.6 ns vs 5.012 us), and about 16.5x faster on representative mixed/unknown outcomes
(301.6 ns vs 4.964 us). On the large generated corpus it ran about 14.0x faster for all-passed
results (2.174 us vs 30.539 us), about 16.5x faster for mostly-passed results
(2.252 us vs 37.141 us), and about 16.4x faster for mixed/unknown outcomes
(2.730 us vs 44.659 us). The same benchmark shows why late projection is not routed:
string-to-rank projection rows only reached about 4.1x-5.2x and missed the 5x gate on
all-passed and mixed/unknown corpora. The production xUnit/reflection runners therefore keep the
public result objects for JSON output but also retain compact ranks as each result is created, then
route text and JSON summary counts through the N# kernel.

The now-retired `CliTestFilterMatchIndicesInto` probe passed parity and reported zero managed
allocation in a dry BenchmarkDotNet probe for `nlc test --filter`, but missed the speed gate and was
not routed through production. The pre-trimmed-filter-parts candidate measured only about 1.4x faster on representative
single-part filters (143.333 us vs 205.166 us), about 1.3x faster on representative multipart
filters (298.792 us vs 373.542 us), about 1.3x faster on representative no-match filters
(149.417 us vs 191.084 us), about 1.7x faster on large single-part filters (1.020 ms vs
1.692 ms), about 2.0x faster on large multipart filters (1.579 ms vs 3.080 ms), and about 1.7x
faster on large no-match filters (911.166 us vs 1.556 ms). A raw filter-segment scanner was also
probed first and was slower than C# on every row, so the native xUnit/reflection filter predicates
remain in C# until N# has a faster string-search primitive or a filter automaton that can clear 5x.

`CliTestOptionSummaryInto` preserves the current `nlc test` command-parser behavior for help,
`--project`, `--filter`, `--timeout`, `--backend`, and the verbose/json/coverage/cache switches, but
also missed the speed gate and is not routed through production. The accepted-shaped probe scans argv
once, writes original value indexes and switch bits into a caller-owned buffer, and inlines its
length/character classifier to avoid a per-argument helper call. A dry run still measured slower on
18 arguments (`84.667 us` N# vs `62.834 us` C#), roughly parity on 64 arguments (`64.250 us` N# vs
`66.084 us` C#), and slower on 1024 arguments (`91.667 us` N# vs `70.208 us` C#). Keep `nlc test`
option parsing in C# until CLI command orchestration can move as a broader parser/argv
representation, or until N# string/branch lowering makes one-pass option classification clearly beat
the repeated `Contains`/`GetOptionValue` shape.

`CliShouldFormatDiscoveredPath` and `CliFormatDiscoveredPathFlagsInto` preserve the current
`nlc format` discovered-file skip semantics for VCS/build/cache/tooling segments and
`test(s)/fixtures`, and they eliminate the C# split allocation. They still missed the speed gate in
the 2026-06-05 dry probe: the per-path candidate measured `468.334 us` vs `205.167 us` on the
representative corpus and `2.452 ms` vs `1.853 ms` on the large generated corpus; the batched
upper-bound row measured `425.000 us` vs `205.167 us` representative and `2.505 ms` vs `1.853 ms`
large. Keep `ShouldFormatDiscoveredFile` on the current C# split helper until path segment scanning
is either owned by a broader N# format-discovery pipeline or N# string/indexing overhead drops enough
to beat the BCL split/segment path by at least 5x.

`CliFixEditFlattenIndicesInto` was reintroduced as a benchmark-only pressure kernel and remains
unrouted. The revised caller-owned shape projects each safe `nlc fix` action's edit count, writes
flattened action/edit index pairs into caller-owned buffers, and uses explicit fast paths for one-
through eight-edit actions. A short validation run on 2026-06-05 measured only about 2.1x faster on
the representative corpus (6.477 us vs 13.656 us, 0 B vs 35,720 B) and about 2.6x faster on the
large generated corpus (51.822 us vs 133.055 us, 0 B vs 285,295 B). Because acceptance requires
every measured corpus to clear 5x, `nlc fix` keeps the current `SelectMany(...).ToList()` edit
flattening path until N# has lower loop/arithmetic overhead or a faster way to bulk-fill parallel
integer result buffers.

`CliFirstPositionalArgIndex` passed parity and reported zero managed allocation in the normal
BenchmarkDotNet evidence tier for first positional-operand discovery. The accepted N# path returns
as soon as it finds the first operand instead of using the previous shared helper shape that scanned
and materialized every positional argument. A short validation run measured about 186x faster on the
representative argument corpus (48.20 ns vs 8.991 us, 0 B vs 22,296 B) and about 1,678x faster on
the large generated argument corpus (48.35 ns vs 81.122 us, 0 B vs 175,280 B). This is
acceptance-grade benchmark evidence for `nlc new`, `nlc check`, `nlc fix`, `nlc update`, and
`nlc export csharp` first positional project/operand discovery when those commands do not need the
full positional list.

`CliLintFileArgIndicesInto` passed parity and routes `nlc lint` positional file-argument extraction
through the owner-local `LintCommandKernels` helper when the N# assembly is available. It preserves
the current value-based `--project` exclusion semantics while replacing repeated full-array rescans
with a caller-owned index buffer. A short validation run measured about 94.0x faster on the
representative argument corpus (20.95 us vs 1.968 ms, 6.70 KB vs 34.32 KB) and about 118.8x faster
on the large generated argument corpus (1.092 ms vs 129.694 ms, 53.68 KB vs 273.90 KB). This is
acceptance-grade benchmark evidence for `nlc lint --project ... [files...]` command-boundary file
selection.

`CliBuildFirstOperandIndexInto` passed parity and reported zero managed allocation in the normal
BenchmarkDotNet evidence tier for source-first `nlc build` operand discovery. The accepted N# path
returns the first source operand index directly instead of materializing the build command's
normalized operand array; leading-option cases still use the exact linked-list fallback to preserve
the current `--output`, `-o`, `--backend`, `--project` stripping order. It ran about 1,262x faster
on the representative source-first argument corpus (7.395 ns vs 9.332 us, 0 B vs 62,072 B) and
about 9,618x faster on the large generated source-first argument corpus (7.491 ns vs 72.047 us,
0 B vs 489,152 B). This is acceptance-grade benchmark evidence for `nlc build Program.nl ...`
single-file route selection; commands that need every normalized build operand remain covered by
the all-positionals pressure note above.

`CliRunFirstOperandIndex` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for `nlc run` source-file operand discovery. The accepted N# path
returns the first source operand index directly instead of materializing a `--backend`-stripped
argument array, while preserving the current dangling `--backend` and unknown-flag behavior. It ran
about 358x faster on the representative argument corpus (4.988 ns vs 1,786.022 ns, 0 B vs
21,216 B) and about 2,701x faster on the large generated corpus (5.152 ns vs 13,915.787 ns, 0 B vs
168,056 B). `RunCommand` now routes source operand discovery through
`RunCommandKernels`, with the previous C# strip path retained as the exact fallback.

`CliPublishOptionsInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for the default no-argument `nlc publish` option summary. It ran
about 12.0x faster than the previous C# parser shape (9.550 ns vs 114.938 ns, 0 B vs 936 B), which
allocated validation sets before discovering there were no options. `PublishCommand` now routes only
this no-argument path through `PublishCommandKernels`; option-bearing publish invocations remain on
the exact C# fallback because the same benchmark measured only about 4.1x for a realistic 18-token
publish command (53.578 ns vs 220.507 ns) and about 2.6x at 64 tokens (140.409 ns vs 368.786 ns),
below the production speed gate.

`CliExportCSharpFirstOperandIndexInto` passed parity and reported zero managed allocation in the
short BenchmarkDotNet evidence tier for source-first `nlc export csharp` input operand discovery.
The accepted N# path returns the first source operand index directly instead of materializing three
stripped argument arrays; leading-option cases keep the exact ordered stripping behavior for
`--output`, `-o`, and `--project`. It ran about 694x faster on the representative source-first
argument corpus (4.423 ns vs 3.070 us, 0 B vs 27,712 B) and about 4,766x faster on the large
generated source-first corpus (4.687 ns vs 22.338 us, 0 B vs 219,344 B). `ExportCommand` now routes
input operand discovery through `ExportCommandKernels`, with the previous three-strip C# path
retained as the exact fallback.

`CliStableDistinctRankIndicesInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for `nlc export csharp` stable reference de-duplication after the host
has assigned compact equality ranks. It ran about 18.8x faster on the representative export-reference
corpus (1.184 us vs 22.252 us, 0 B vs 30,256 B) and about 22.2x faster on the large generated
export-reference corpus (6.956 us vs 154.107 us, 0 B vs 186,066 B). This is acceptance-grade
benchmark evidence for replacing the export command's post-resolution reference `Distinct` passes
while preserving first-source order and the host-owned project path, package metadata, DLL metadata,
and XML emission boundaries.

The same stable distinct kernel passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for `nlc restore` resolved project-reference de-duplication. It ran
about 24.3x faster on the representative project-reference corpus (1.156 us vs 28.087 us, 0 B vs
30,256 B) and about 28.1x faster on the large generated project-reference corpus (6.855 us vs
192.416 us, 0 B vs 185,722 B). This is acceptance-grade benchmark evidence for replacing restore's
post-resolution project-reference `Distinct` pass while preserving ordinal-ignore-case identity and
first-source output order.
The compiler-service `DocQuery` reference-pack assembly-name discovery now reuses the same accepted
stable distinct kernel after the host has projected non-empty assembly names, preserving
ordinal-ignore-case identity and first-source discovery order.

`DiagnosticSeverityFilterIndicesInto` passed parity and reported zero managed allocation in the
normal BenchmarkDotNet evidence tier for CLI diagnostic severity filtering. The accepted N# path
uses compact case-insensitive severity ranks, an eight-wide unrolled scan for caller-owned result
buffers, and a single-pass checksum wrapper. It ran about 7.2x faster on the representative
diagnostic corpus in the latest short validation run (380.5 ns vs 2.666 us, 0 B vs 2,840 B) and
about 7.0x faster on the large generated diagnostic corpus (3.125 us vs 21.990 us, 0 B vs
21,944 B). This is acceptance-grade benchmark evidence for `nlc query diagnostics`, batch
diagnostics, daemon diagnostics, and strict build lint error filtering after the host has assigned
compact case-insensitive severity ranks. The production output-format route now binds this kernel
through `OutputFormatterDiagnosticKernels` instead of the broad code-intelligence dogfood adapter.

The same compact severity filter passed parity for `CompilerError` enum-severity filtering and
reported zero managed allocation in the normal BenchmarkDotNet evidence tier. It ran about 6.4x
faster on the representative compiler-error corpus (399.7 ns vs 2.577 us, 0 B vs 3,384 B) and about
6.8x faster on the large generated compiler-error corpus (3.180 us vs 21.625 us, 0 B vs 26,312 B).
This is acceptance-grade benchmark evidence for `nlc check` backend-verification error filtering
and `nlc lint` parse-error filtering after the host has projected `ErrorSeverity` values into compact
integer ranks.

The same compact rank filter passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for `nlc tidy --fix` possibly-unused dependency selection. It ran
about 8.0x faster on the representative tidy dependency corpus (298.0 ns vs 2.369 us, 0 B vs
1,920 B) and about 7.9x faster on the large generated corpus (2.396 us vs 18.953 us, 0 B vs
14,672 B). This is acceptance-grade benchmark evidence for replacing tidy's
`Where(r => r.Status == "possibly-unused").ToList()` removal-selection gate after the host has
projected status strings into compact integer ranks.

`CliTidyDependencyStatusSummaryInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for `nlc tidy` status summary calculation. It ran about 6.3x faster
on the representative tidy status corpus (420.8 ns vs 2.667 us) and about 5.8x faster on the large
generated corpus (3.526 us vs 20.613 us). This is acceptance-grade benchmark evidence for replacing
the command's previous `All(...)` plus two `Count(...)` status scans after the host has projected
status strings into compact integer ranks.

`CliTidyDependencyStatusRanksInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for `nlc tidy` dependency usage classification. The accepted N# path
uses the current command semantics that a first-segment namespace match determines the final status,
so it avoids the C# baseline's split/join allocation while preserving the same public status and
reason text in the host. It ran about 10.9x faster on the representative dependency/import corpus
(17.414 us vs 199.280 us, 0 B vs 1,485,616 B) and about 7.5x faster on the large generated corpus
(665.013 us vs 5.001 ms, 0 B vs 38,533,472 B). The production command helper guards the
ASCII-specialized fast path and keeps the C# classifier for non-ASCII package or import names.

`CliTidyRemovalLineKeepFlagsInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for `nlc tidy --fix` project.yml dependency-line removal. The accepted
N# path scans ASCII project lines and selected package names directly, writes keep/remove flags into
caller-owned storage, and preserves the current C# fallback semantics including broad `- Package`
prefix matching and case-insensitive `nuget: Package` containment. It ran about 8.5x faster on the
representative tidy project corpus (92.15 us vs 779.59 us, 0 B vs 6,639,824 B) and about 8.6x
faster on the large generated corpus (2.525 ms vs 21.848 ms, 0 B vs 203,167,904 B). The production
command helper guards the ASCII-specialized fast path and keeps the C# line filter for non-ASCII
project lines, non-ASCII package names, or unavailable dogfood.

Production `nlc tidy` now routes dependency classification, status summarization, possibly-unused
selection, and removal-line filtering through the owner-local `TidyCommandKernels` helper when the
dogfood assembly is available, with the previous C# command fallbacks retained for unavailable
dogfood and non-ASCII classification/removal inputs.

`CliFixSafetyFilterIndicesInto` passed parity and reported zero managed allocation in the normal
BenchmarkDotNet evidence tier for `nlc fix` safety filtering. The accepted N# path uses compact
`FixSafety` ranks, an eight-wide unrolled threshold scan, and a single-pass checksum wrapper. It ran
about 7.5x faster on the representative safe-only corpus (334.2 ns vs 2.499 us, 0 B vs 2,752 B),
about 6.3x faster on representative include-review-needed filtering (493.9 ns vs 3.102 us, 0 B vs
5,344 B), about 7.2x faster on the large generated safe-only corpus (2.635 us vs 19.008 us,
0 B vs 20,864 B), and about 6.1x faster on the large generated include-review-needed corpus
(3.996 us vs 24.360 us, 0 B vs 41,568 B). This is acceptance-grade benchmark evidence for the
`nlc fix` edit-collection safety gate after the host has projected `FixSafety` values into compact
integer ranks.

`CliFixSkippedIndicesInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for `nlc fix --text` skipped-fix selection. The accepted N# path uses
compact safety ranks and caller-owned skipped-index buffers instead of the previous
`Where(... !applied.Contains(...))` materialization. It ran about 181.8x faster on the
representative safe-only skipped corpus (1.181 us vs 214.668 us, 0 B vs 5,776 B), about 430.4x
faster on representative include-review-needed output (806.9 ns vs 347.289 us, 0 B vs 3,184 B),
about 1,523x faster on the large generated safe-only corpus (9.459 us vs 14.410 ms, 0 B vs
45,008 B), and about 5,972x faster on the large generated include-review-needed corpus (6.523 us vs
38.953 ms, 0 B vs 24,304 B). This is acceptance-grade benchmark evidence for `nlc fix --text`
skipped-fix output after the host has projected safety strings into compact integer ranks.

`CliFixAppliedFileGroupsInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for `nlc fix --text` applied-fix file grouping. The accepted N# path
uses first-seen dense file ranks, caller-owned count/offset buffers, and grouped source-index
output instead of the previous `applied.GroupBy(f => f.File)` materialization. It ran about 13.1x
faster on the representative applied-fix corpus (2.081 us vs 27.244 us, 0 B vs 42,976 B) and about
12.8x faster on the large generated corpus (15.710 us vs 200.511 us, 0 B vs 233,952 B). This is
acceptance-grade benchmark evidence for `nlc fix --text` applied-fix output after the host has
projected file names into compact integer ranks.
Production `nlc fix` now routes the accepted safety filter, skipped-fix selector, and applied-file
grouping kernels through the owner-local `FixCommandKernels` helper when the dogfood assembly is
available, with the previous LINQ and `GroupBy` paths retained as exact fallbacks.

`CliUnifiedDiffHunkRangesInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for `nlc format --diff` hunk range construction after line diffing.
The first production-shaped candidate still materialized hunk records and slice arrays and only
reached about 4.6x on the representative corpus, so the accepted route computes N# hunk ranges and
renders directly from the original diff lines. It ran about 7.5x faster on the representative diff
corpus (911.0 ns vs 6.820 us, 0 B vs 14,216 B) and about 7.2x faster on the large generated diff
corpus (7.315 us vs 53.003 us, 0 B vs 108,672 B). `UnifiedDiff.Create` now routes through
`UnifiedDiffHunkRangeBuilder` when the dogfood assembly is available, with the previous C#
`BuildHunks` path retained as an exact fallback.

`SymbolKindFilterIndicesInto` passed parity and reported zero managed allocation in the normal
BenchmarkDotNet evidence tier for symbol-kind filtering. The accepted N# path uses compact symbol
kind ids, an eight-wide unrolled scan for caller-owned result buffers, and a single-pass checksum
wrapper. It ran about 6.1x faster on the representative symbol corpus in the latest short validation
run (299.4 ns vs 1.824 us, 0 B vs 1,216 B) and about 6.2x faster on the large generated symbol
corpus (2.337 us vs 14.567 us, 0 B vs 8,936 B). This is acceptance-grade benchmark evidence for
`nlc query symbols --kind`, batch symbol queries, and daemon symbol queries after the host has
projected symbol kinds into compact integer ids.

`CliSymbolNameGlobFilterIndicesInto` and `CliSymbolNameSubstringFilterIndicesInto` passed parity in
the short BenchmarkDotNet evidence tier for `nlc query symbols --filter` name filters. The accepted
N# path handles ASCII glob matching with caller-owned result-index buffers and prefix/suffix
specializations, and routes ASCII bare substring matching through the compiled N# index filter with
`StringComparison.OrdinalIgnoreCase`, preserving source order and the 200-result cap. It ran about
15.1x faster on the representative prefix-glob corpus (4.026 us vs 60.997 us), about 72.6x faster
on the representative suffix-glob corpus (4.922 us vs 357.321 us), about 7.4x faster on the
representative substring corpus (3.298 us vs 24.519 us), about 14.9x faster on the large generated
prefix-glob corpus (8.065 us vs 119.854 us), about 70.2x faster on the large generated suffix-glob
corpus (9.128 us vs 640.915 us), and about 7.1x faster on the large generated substring corpus
(9.770 us vs 69.645 us). This is acceptance-grade benchmark evidence for ASCII name filtering in
`nlc query symbols --filter` after the host has projected public symbol names into a string array.

`DocQueryBestTypeIndex` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence run for `nlc query doc` candidate selection. The accepted N# path uses
caller-owned score, namespace-length, and full-name arrays plus an eight-wide unrolled scan that
preserves the C# ordering contract: score descending, namespace length ascending, and
`StringComparer.OrdinalIgnoreCase` full-name order for ties. It ran about 5.1x faster on the
representative type-candidate corpus (437.7 ns vs 2.248 us, 0 B vs 440 B) and about 5.2x faster on
the large generated corpus (3.282 us vs 17.028 us, 0 B vs 440 B). `DocQuery.SelectBestType` now
routes candidate-array de-duplication through the accepted stable distinct rank kernel and routes
the resulting distinct candidate arrays through
`DocQueryKernels.TrySelectBestDocType` when the dogfood assembly is available,
with the previous LINQ distinct/order path retained as the exact fallback; the helper also falls
back for non-ASCII CLR full names so the public
`StringComparer.OrdinalIgnoreCase` tie-break contract is not approximated.

`DocQueryMemberOrderIndicesInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence run for `nlc query doc` member ordering. The accepted N# path receives
fixed member-kind ranks plus host-computed `StringComparer.OrdinalIgnoreCase` name ranks, then uses
stable counting passes to preserve the C# `OrderBy(kind).ThenBy(name)` contract. It ran about
22.0x faster on the representative member corpus (5.585 us vs 122.970 us, 0 B vs 37,368 B) and
about 30.0x faster on the large generated corpus (51.244 us vs 1.535 ms, 0 B vs 295,416 B).
`DocQuery.GetTypeMembers` now routes through
`DocQueryKernels.TryOrderDocMembers` when the dogfood assembly is available,
with the previous LINQ ordering retained for unexpected member kinds or unavailable dogfood.

The full-array `ParserTokenCompactionIndicesInto` parity wrapper passed parity and reported zero
managed allocation in the normal BenchmarkDotNet evidence tier for parser newline-token compaction.
It ran about 7.3x faster on the
representative token corpus (96.771 ns vs 706.742 ns, 0 B vs 1,560 B) and about 8.6x faster on the
large generated token corpus (31.250 us vs 268.324 us, 0 B vs 468,667 B). This is
acceptance-grade benchmark evidence for newline compaction after the host has projected token kinds
into compact integer ids. The shipped adapter binding uses the counted-prefix ABI so production
callers pass logical token counts instead of relying on exact-sized full arrays.

`CliBatchDuplicateIdRanksInto` passed parity and reported zero managed allocation in the normal
BenchmarkDotNet evidence tier for the compact rank duplicate-id kernel. It ran about 21.8x faster
on the representative batch corpus (1.075 us vs 23.400 us, 0 B vs 59,592 B) and about 23.2x faster
on the large generated batch corpus (5.800 us vs 134.725 us, 0 B vs 278,384 B). This is
acceptance-grade benchmark evidence for duplicate request-id validation after the host has assigned
sorted ordinal ranks to public string ids.

`CliDocSymbolOrderCountingIndicesInto` passed parity and reported zero managed allocation in the
normal BenchmarkDotNet evidence tier for doc symbol ordering. The first comparison-sort candidate
only reached about 2.7x-2.9x faster, so the accepted kernel uses dense ranks and two stable counting
passes. It ran about 11.6x faster on the representative symbol corpus (3.880 us vs 45.050 us,
0 B vs 54,319 B) and about 23.9x faster on the large generated symbol corpus (32.143 us vs
769.319 us, 0 B vs 430,687 B). This is acceptance-grade benchmark evidence for `nlc doc` symbol
filtering and kind/name ordering after the host has assigned compact ordinal ranks.

The same counting-order kernel also passed parity for generated symbol-page member ordering with
all include flags set. It ran about 10.3x faster on the representative member corpus (4.929 us vs
50.641 us, 0 B vs 61,952 B) and about 29.0x faster on the large generated member corpus
(36.541 us vs 1,058.544 us, 0 B vs 492,088 B). This is acceptance-grade benchmark evidence for
`nlc doc` member-list ordering after the host has assigned compact ordinal ranks.

`CliDocSlugsInto` passed parity in the short BenchmarkDotNet evidence tier for generated doc page
slug materialization. The accepted N# path batches raw slugs, reuses one growable scratch char
buffer, and uses an ASCII-specialized slug loop with Unicode fallback. It ran about 5.1x faster on
the representative slug corpus (36.179 us vs 184.292 us, 94.55 KB vs 803.74 KB) and about 5.7x
faster on the large generated slug corpus (306.967 us vs 1.760 ms, 754.95 KB vs 6,431.67 KB). This
is acceptance-grade benchmark evidence for `nlc doc` slug generation after the host has built the
raw kind/name/file slug strings.
Production `nlc doc` now routes symbol ordering, member ordering, and slug generation through the
owner-local `DocCommandKernels` helper when the dogfood assembly is available, with the previous C#
ordering and slugifier paths retained as fallbacks.

`CliTreeDependencyDeduplicateIndicesInto` passed parity and reported zero managed allocation in the
normal BenchmarkDotNet evidence tier for `nlc tree` dependency deduplication and order. It ran about
33.7x faster on the representative dependency corpus (4.528 us vs 152.442 us, 0 B vs 150,408 B) and
about 61.5x faster on the large generated dependency corpus (35.635 us vs 2,192.579 us, 0 B vs
1,168,344 B). This is acceptance-grade benchmark evidence for `nlc tree` dependency deduplication
after the host has assigned compact ordinal kind ranks and case-insensitive name ranks.
Production `nlc tree` now routes this kernel through the owner-local
`TreeDependencyDeduplicator` helper when the dogfood assembly is available, with the previous C#
grouping/order path retained as the fallback.

`CliCleanArtifactDirectoryIndicesInto` passed parity and reported zero managed allocation in the
short BenchmarkDotNet evidence tier for `nlc clean` artifact directory selection after directory IO.
It ran about 19.4x faster on the representative directory corpus (2.703 us vs 52.389 us, 0 B vs
114,464 B) and about 21.3x faster on the large generated directory corpus (23.487 us vs
501.349 us, 0 B vs 644,415 B). This is acceptance-grade benchmark evidence for `nlc clean`
post-enumeration artifact de-duplication and deletion order after the host has projected compact
path facts.
Production `nlc clean` now routes this kernel through the owner-local
`CleanArtifactDirectoryOrderer` helper when the dogfood assembly is available, with the previous C#
distinct/filter/order path retained as the fallback.

`CliUpdateAllNuGetDependencyIndicesInto` passed parity and reported zero managed allocation in the
short BenchmarkDotNet evidence tier for `nlc update` all-NuGet dependency selection. The flag-based
route ran about 6.2x faster on the representative dependency corpus (468.185 ns vs 2.896 us, 0 B vs
5,136 B) and about 6.5x faster on the large generated dependency corpus (3.846 us vs 24.959 us,
0 B vs 40,320 B). This replaces the earlier no-target rank-filter attempt that measured only about
4.96x and was left unrouted.

`CliUpdateTargetNuGetDependencyIndicesInto` passed parity and reported zero managed allocation in
the short BenchmarkDotNet evidence tier for `nlc update <package>` target-package narrowing. It ran
about 7.7x faster on the representative existing-target corpus (266.107 ns vs 2.049 us, 0 B vs
912 B) and about 7.9x faster on the large generated existing-target corpus (2.150 us vs 16.941 us,
0 B vs 6,120 B). Missing target ranks return immediately on the N# path: the representative
missing-target row measured 0.397 ns vs 1.945 us, and the large generated missing-target row
measured 0.401 ns vs 15.558 us. This is acceptance-grade benchmark evidence for named-package
`nlc update` narrowing after the host has assigned case-insensitive package-name ranks with rank 0
reserved for non-NuGet dependencies.
Production `nlc update` now routes both accepted kernels through the owner-local
`UpdateDependencyFilter` helper when the dogfood assembly is available, with the previous C#
dependency-filter path retained as the fallback.

`CliReferenceTypeFilterIndicesInto` passed parity and reported zero managed allocation in the short
BenchmarkDotNet evidence tier for CLI dependency reference-type selection. The
compact-rank route ran about 7.1x faster for representative NuGet references (473.963 ns vs
3.365 us), 8.0x faster for representative DLL references (282.690 ns vs 2.248 us), 8.3x faster for
representative project references (283.925 ns vs 2.358 us), and 8.1x faster for representative
framework references (283.614 ns vs 2.308 us). On the large generated corpus it ran about 7.1x
faster for NuGet references (3.868 us vs 27.584 us), 8.1x faster for DLL references (2.212 us vs
17.885 us), 8.1x faster for project references (2.239 us vs 18.082 us), and 8.2x faster for
framework references (2.244 us vs 18.335 us). This is acceptance-grade benchmark evidence for
reference-kind selection after the host has projected compact reference-type ranks with rank 0
reserved for invalid/non-selected values.

The production swap slice for these extraction helpers now ships the dogfood assembly beside the CLI,
language server, and test host through `NSharpLang.Compiler.Dogfood.targets`, while
`CodeIntelligenceService` dynamically binds the compiled N# methods when the assembly is present.
The adapter caches line ranges, receiver caches, and variable-declaration name caches per
`ProjectSnapshot`/file, uses cached line ranges for the strict reference/rename declaration-name
span guard, reference source-context and raw diagnostic-line materialization, completion-prefix
extraction, hover doc-comment extraction, and strict editor word/span extraction used by the language
server. Analyzer declaration-name column lookup for binding-map declaration recording also routes
through the compiled N# whole-identifier scanner when the dogfood assembly is available, with the
old split-based helper kept as the fallback. Completion receiver-context classification also routes
through the compiled N# classifier
when the dogfood assembly is available, with the old C# helper kept as the fallback.
`LintCommand` positional file-argument extraction now routes through `LintCommandKernels` and the
compiled N# `CliLintFileArgIndicesInto` kernel when the dogfood assembly is available, with the
previous LINQ/rescan helper retained as the fallback.
Analyzer central error/warning snippets and namespace-import source-line lookups now route through
the same source-only cached raw-line adapter, with the existing split-backed source lines retained
for semantic span calculations that still need broader analyzer refactoring.
Parser diagnostic source snippets now route through the same source-only cached raw-line adapter,
with the previous `source.Split('\n')` helper kept as the fallback when the dogfood assembly is not
available; this preserves the parser's LF-split semantics, including CRLF lines retaining a trailing
carriage return in the snippet.
`Parser` construction now routes newline-token compaction through
`NSharpCompilerDogfoodAdapter.TryCompactParserTokens` when the dogfood assembly is available, with
the previous LINQ `Where(...).ToList()` path kept as the fallback. This is a temporary compact-token
bridge: token objects and broader parser state remain C# until the parser is ported.
`Analyzer.CheckEnumMatchExhaustiveness` now routes enum missing-member selection through
`NSharpCompilerDogfoodAdapter.TrySelectMissingEnumMembers` when the dogfood assembly is available,
with the previous C# `ToHashSet().Except().ToList()` path kept as the fallback.
`Analyzer.CheckMatchExhaustiveness` now rents declaration-order covered/partial flag buffers while
collecting union-case coverage, routes missing/partial/never-covered case selection through
`NSharpCompilerDogfoodAdapter.TrySelectMissingUnionCasesFromFlags` when the dogfood assembly is
available, and keeps a small C# flag-loop fallback for unavailable or invalid dogfood output.
`CompletionEngine` member-access result grouping now routes through the compiled N# completion-item
grouping kernel when the dogfood assembly is available, preserving the previous pluralized group
keys and first-seen item-kind ordering, with the previous LINQ `GroupBy`/`ToList` path kept as the
fallback.
`CompletionEngine` reflected CLR method overload grouping inside member completion now routes
through the compiled N# method-overload grouping kernel when the dogfood assembly is available,
preserving the previous method filtering, first-seen method-name ordering, first overload selected
for display, and overload count details, with the previous LINQ `Where`/`GroupBy`/`ToList` path kept
as the fallback.
Source-only diagnostic formatting uses a `ConditionalWeakTable<string, ...>` cache for callers such
as `nlc lint` and IDE open-buffer utilities that do not carry a `ProjectSnapshot`.
`MultiFileCompiler` circular-import and AOT diagnostic snippets now route LF-only source texts
through the same source-only cached raw-line adapter, with the previous CR/CRLF split fallback kept
for files where the raw-line LF semantics would otherwise preserve carriage returns.
Public AOT requirement construction now routes `AotRequirements.FromBlockers` through the
owner-local `AotRequirementSelector` when the dogfood assembly is available,
preserving the previous public-surface filter, per-declaration flag combination, sorted construct
names, and annotation message text, with the previous C# LINQ grouping path kept as the fallback.
Struct-copy declared-field readonly gating now routes `AllInstanceFieldsAreInitOnly` through
the owner-local `StructCopyInitOnlySelector` when the dogfood assembly is
available, preserving static-field exclusion and instance init-only semantics, with the previous C#
LINQ `Where(...).ToList().All(...)` path kept as the fallback.
Anonymous-union overload-shim eligibility now routes `DeclaresAnonymousUnionShims` through
`NSharpCompilerDogfoodAdapter.TryDeclaresAnonymousUnionShims` when the dogfood assembly is
available, preserving public method/type preconditions, modifier/type-parameter exclusions,
flattened exactly-two-arm anonymous-union recognition, and ref/out/params exclusion, with the
previous C# LINQ `Where(...).ToList().All(...)` path kept as the fallback.
IL compiler implemented-interface expansion now routes first-source type-key de-duplication through
`NSharpCompilerDogfoodAdapter.TryDeduplicateFirstTypeKeys` when the dogfood assembly is available,
preserving direct/inherited interface expansion, ordinal type-key identity, and first-source
selection, with the previous C# `GroupBy(GetTypeKey).Select(First)` path kept as the fallback.
Compiler source-file list construction now routes first-source ordinal-ignore-case de-duplication in
`MultiFileCompiler` and `CompilationStubEmitter` through
`NSharpCompilerDogfoodAdapter.TryDeduplicateFirstStringsOrdinalIgnoreCase`, which calls the same
accepted compact-rank `FirstDistinctRankIndicesInto` kernel after the host has normalized or
filtered source paths, with the previous C# `Distinct(StringComparer.OrdinalIgnoreCase)` path kept
as the fallback.
Compiler stub namespace import construction now routes ordinal distinct/order selection through
`NSharpCompilerDogfoodAdapter.TryDistinctOrderStringsOrdinal`, which calls the accepted
`ReferenceFileSummaryRanksInto` rank-summary kernel after the host has collected namespace names,
with the previous C# `Distinct(StringComparer.Ordinal).OrderBy(StringComparer.Ordinal)` path kept as
the fallback.
`ProjectConfig.GetSourceFiles` now routes its post-enumeration source-file filtering (test-file drop
plus exclude-glob filtering) through `NSharpCompilerDogfoodAdapter.TryFilterSourceFiles`, which calls
the accepted compact-flag `ProjectSourceFilterKeptIndicesInto` kernel after the host computes
project-relative paths. The kernel classifies every file in a single pass and hand-matches the
exclude globs (`**/`, `**`, `*`, `?`, slash normalization, case-sensitive literals) with the exact
semantics of the previous per-file `Regex.Escape/Replace/IsMatch` `MatchesPattern`, preserving
enumeration order and the public `string[]` contract; the previous two-pass `Where(...).ToArray()`
filtering is kept as the fallback. `CompilerServiceProjectSourceFilterBenchmarks` measured
`411.42 us` C# vs `15.94 us` N# representative (about 25.8x, 307,248 B -> 760 B) and `6.505 ms` C# vs
`242.10 us` N# large (about 26.9x, 4,593,824 B -> 10,944 B); the C# baseline is dominated by
recompiling a regex per (file, pattern) pair.
IL compiler declared project-type suffix resolution now routes
`TryLookupUniqueDeclaredTypeBySuffix` through
`NSharpCompilerDogfoodAdapter.TryLookupUniqueDeclaredTypeBySuffix` when the dogfood assembly is
available, preserving exact-or-dotted-suffix ordinal matching, distinct `Type` result uniqueness,
and no-match/ambiguous false behavior, with the previous C# LINQ scan kept as the fallback.
IL compiler declared type-name candidate selection now routes the declared-name exact/suffix and
imported-namespace disambiguation tail of `GetDeclaredTypeNameCandidates` through
`NSharpCompilerDogfoodAdapter.TrySelectDeclaredTypeNameCandidate` when the dogfood assembly is
available, preserving unique imported match, unique total match, no-match, and ambiguous behavior,
with the previous C# LINQ scan kept as the fallback.
IL compiler type-builder creation now routes nested enum `TypeBuilder`, string-enum container, and
normal user-type creation order through
`NSharpCompilerDogfoodAdapter.TryOrderTypesByDescendingKeyDotCount` when the dogfood assembly is
available, preserving stable descending type-key dot-count order, with the previous C#
`OrderByDescending` path kept as the fallback.
Clustered diagnostic output now uses the compiled N# trait classifier for category/source-construct
ids when the dogfood assembly is available, then materializes schema strings in the formatter.
Clustered diagnostic output also routes group root/count/order selection through the compiled N#
compact grouping kernel when the dogfood assembly is available, with the previous LINQ `GroupBy`
path kept as the fallback.
Clustered diagnostic `files` arrays now route through the compiled N# rank-summary kernel when the
dogfood assembly is available, preserving the previous case-insensitive distinct/order contract,
with the previous LINQ `Distinct`/`OrderBy` path kept as the fallback.
Diagnostic, clustered diagnostic, check, and lint JSON envelopes, Elm-style diagnostic text
summaries, and CLI diagnostic exit decisions now use the compiled N# severity summary pass when the
dogfood assembly is available through the owner-local `OutputFormatterDiagnosticKernels`, with the
previous C# LINQ counts kept as the fallback.
`CodeIntelligenceService.GetDiagnostics` now routes lint `NL020` shadowing suppression for files
that already have compiler shadowing errors through the compiled N# compact code/file-rank filter
when the dogfood assembly is available, with the previous C# case-insensitive `HashSet`/LINQ filter
kept as the fallback.
`nlc query diagnostics`, batch diagnostics, and daemon diagnostics now route `--severity` filtering
through `OutputFormatter.FilterDiagnosticsBySeverity`, which calls the compiled N# compact-rank
severity filter through `OutputFormatterDiagnosticKernels` when the dogfood assembly is available,
with the previous C# LINQ
`Where(...Equals(..., OrdinalIgnoreCase)).ToList()` path kept as the fallback.
`nlc check` backend verification and `nlc lint` parse-error reporting now route compiler-error
severity filtering through the owner-local `CompilerErrorSeverityFilter`, which calls the same
compiled N# compact-rank severity filter when the dogfood assembly is available, with the previous
C# LINQ `Where(e => e.Severity == ...).ToList()` path kept as the fallback.
`CodeIntelligenceService.GetSymbols` now routes optional `SymbolKind` filtering through the compiled
N# compact kind-id filter when the dogfood assembly is available, covering `nlc query symbols
--kind`, batch symbol queries, and daemon symbol queries, with the previous C# LINQ
`Where(s => s.Kind == kind).ToList()` path kept as the fallback.
`nlc query symbols --filter` now routes ASCII wildcard and bare substring name filters through
the owner-local `QuerySymbolNameFilter`, which calls the compiled N# glob or
substring matcher when the dogfood assembly is available, preserving case-insensitive matching
semantics, source order, and the 200-result cap. Non-ASCII patterns/names keep the previous C#
regex fallback.
Strict `nlc build` lint gating now routes its error-only diagnostic filter through the same
adapter-backed formatter path before the accepted diagnostic deduplication/order route, instead of
running a local C# LINQ severity filter.
`nlc new`, `nlc check`, `nlc fix`, `nlc add`, `nlc remove`, and `nlc update` now route first
positional project/operand/package discovery through owner-local command helpers
(`NewCommandKernels`, `CheckCommandKernels`, `FixCommandArgumentKernels`, `AddCommandKernels`,
`RemoveCommandKernels`, and `UpdateCommandKernels`), which call the compiled N# first-index scanner
when the dogfood assembly is available, with command-local C# positional scans kept as the fallback.
`nlc export csharp` input operand discovery routes through `ExportCommandKernels`.
`nlc build` now routes source-file operand discovery through
`BuildCommandKernels`, which calls the compiled N# first-operand scanner when the dogfood assembly
is available, with the previous C# build-argument normalization kept as the fallback.
`nlc export csharp` dependency reference-type selection for project, DLL, NuGet package, and
framework references now routes through `ExportCommandKernels`, which calls the compiled N#
compact-rank filter when the dogfood assembly is available, preserving source order and
invalid-reference fallback behavior, with the previous C# `Where(...).ToList()` filters kept as the
fallback. `nlc restore` now routes the same accepted kernel through `RestoreCommandKernels`; native
CLI compilation reference resolution now routes it through `CompilationReferenceResolverKernels`,
with the previous C# filters kept as the fallback.
`nlc export csharp` now routes stable post-resolution reference de-duplication for project,
framework, package, and DLL references through `ExportCommandKernels`, which calls the compiled N#
compact-rank stable distinct kernel when the dogfood assembly is available, with the previous C#
`Distinct` paths kept as the fallback.
`nlc restore` now routes stable post-resolution project-reference de-duplication through
`RestoreCommandKernels`, which calls the same compiled N# compact-rank stable distinct kernel when
the dogfood assembly is available, with the previous C# `Distinct` path kept as the fallback.
CLI stale generated-output cleanup now routes stable generated-directory de-duplication through
`GeneratedOutputDirectoryDeduplicator`, and `nlc tree` target-framework summaries route stable string
de-duplication through `TreeDependencyDeduplicator` when the dogfood assembly is available,
preserving ordinal generated-directory identity, ordinal-ignore-case framework identity, and
first-source output order, with the previous C# `Distinct` paths kept as the fallback.
`DocQuery` reference-pack assembly-name discovery routes stable ordinal-ignore-case de-duplication
through `DocQueryKernels.TryDeduplicateStableStringsOrdinalIgnoreCase`, with the
previous C# `Distinct(StringComparer.OrdinalIgnoreCase)` path kept as the fallback.
`nlc check` and strict build lint now route duplicate diagnostic removal and file/line/column
ordering through `OutputFormatter.DeduplicateAndSortDiagnostics`, which calls the compiled N#
deduplication kernel when the dogfood assembly is available and keeps the previous LINQ `GroupBy`
shape as the fallback.
`CodeIntelligenceService.GetDiagnostics` now routes its preserve-first-order duplicate removal
through the compiled N# stable deduplication kernel when the dogfood assembly is available, with the
previous LINQ `GroupBy(...).Select(First)` shape kept as the fallback.
`FindReferences` result deduplication and ordering now calls the compiled N# reference-deduplication
kernel when the dogfood assembly is available, with the previous LINQ `GroupBy`/`OrderBy` path kept
as the fallback.
`nlc query inspect` summary reference-file lists now route through the compiled N# rank-summary
kernel when the dogfood assembly is available, preserving normalized path ordinal distinct/order
semantics, with the previous LINQ `Distinct`/`OrderBy` path kept as the fallback.
Strict definition/reference/hover binding candidate-column ordering now routes through the compiled
N# direct distance-order generator when the dogfood assembly is available, with the previous
`HashSet<int>`/LINQ helper kept as the fallback.
Strict definition/reference/hover binding lookup now builds a compact `BindingMap` cache and calls
the compiled N# binding lookup kernel when the dogfood assembly is available, with the previous
dictionary lookup path kept as the fallback.
The source-context definition fallback now uses the same compact `BindingMap` cache to route nearest
same-file declaration-by-name selection through the compiled N# binary-search kernel, with the
previous LINQ filter/order path kept as the fallback.
The same compact `BindingMap` cache now routes sorted nearest-declaration index construction through
the compiled N# dense name-id counting builder when the dogfood assembly is available, with the
previous C# `Array.Sort(order, CompareDeclarationOrder)` builder kept as the fallback for unavailable,
invalid, or out-of-order same-name N# output.
The semantic-scope public API bridge was removed from both code-intelligence and compiler dogfood
adapters. Production-shaped dry probes missed the 5x gate once the public dictionary/`TypeInfo`
boundary and per-call adapter overhead were included, so `CompletionEngine` keeps the current
`SemanticModel.GetVisibleVariablesAtPosition` and `SemanticModel.LookupIdentifierAtPosition` paths
until a wider batched or caller-owned completion route lands. The semantic-scope N# kernels now live
only in the parity corpus.
CLI/daemon member-access completion also routes public completion-item kind grouping through the
compiled N# grouping kernel when the dogfood assembly is available, with the previous LINQ
`GroupBy`/`ToList` shape kept as the fallback.
CLI/daemon member-access completion also routes reflected CLR method overload grouping through the
compiled N# grouping kernel when the dogfood assembly is available, with reflection enumeration and
final completion item construction still handled by the C# host boundary.
`nlc query batch` duplicate request-id validation now routes through the owner-local
`BatchQueryKernels` helper, which calls the compiled N# compact-rank duplicate detector when the
dogfood assembly is available, preserving the previous sorted ordinal duplicate-id error output,
with the previous LINQ grouping path kept as the fallback.
`nlc query batch` result summary counting now retains compact ok bitsets while public item results
are created, then routes success-count calculation through `BatchQueryKernels`, which calls the
compiled N# packed popcount kernel when the dogfood assembly is available, with the previous C#
`items.Count(item => item.Ok)` count kept as the fallback.
`nlc doc` symbol filtering and kind/name ordering now routes through `DocCommandKernels`, which
calls the compiled N# stable counting-sort kernel when the dogfood assembly is available, preserving
the previous `SymbolKind.ToString()`/ordinal name order and variable/parameter filtering, with the
previous LINQ ordering path kept as the fallback.
Generated `nlc doc` symbol-page member ordering also routes through `DocCommandKernels` and the same
compiled N# stable counting-sort kernel when the dogfood assembly is available, preserving the
previous full member inclusion and `SymbolKind.ToString()`/ordinal name order, with the previous
LINQ ordering path kept as the fallback.
Generated `nlc doc` symbol-page slug generation now batches raw kind/name/file slug strings through
`DocCommandKernels` and the compiled N# `CliDocSlugsInto` route when the dogfood assembly is
available, preserving the previous lower-case letter/digit-only slug text, with the previous
LINQ/split/join slugifier kept as the fallback.
`nlc tree` dependency deduplication and kind/name ordering now routes through
`TreeDependencyDeduplicator`, which calls the compiled N# stable counting-sort kernel when the
dogfood assembly is available, preserving the previous first-source dependency selection for each
ordinal-kind/case-insensitive-name key, with the previous LINQ grouping/order path kept as the
fallback.
`FixApplicator.ValidateAndSortEdits` now routes edit application ordering through the compiled N#
two-pass stable counting kernel when the dogfood assembly is available, preserving the previous
bottom-to-top, right-to-left, end-position, and same-position reverse-input ordering, with the
previous LINQ ordering path kept as the fallback.
`Formatter.Format` import/using ordering now routes through the compiled N#
`FormatterImportOrderIndicesInto` two-pass stable counting kernel when the dogfood assembly is
available, preserving the "System* first, then namespace alphabetical" ordering (including stable
ties for duplicate namespaces), with the previous `OrderByDescending`/`ThenBy`/`ToList` LINQ path
kept as the fallback. Measured `2026-06-05` on `.NET 10.0.5` (Arm64): the representative single-file
import set (~33 imports) ran `330.6 ns` (N#) vs `2,057.0 ns` (C#), about `6.2x`, and the large
generated multi-file set ran `63.40 us` (N#) vs `1,281.05 us` (C#), about `20.2x`, with zero
per-operation managed allocation on the N# path (`0 B` vs `2,568 B` representative, `0 B` vs
`478,176 B` large). Both rows clear the 5x acceptance gate; the representative win is convincing
because the C# baseline's per-call LINQ projection plus list materialization dominates even at small
import counts. Parity is asserted by `CompilerDogfoodProjectTests`
(`AssertFormatterImportOrderingLikeProduction` checksum/sequence parity and
`CompilerDogfoodAdapter_OrdersImportsBySystemThenNamespaceLikeProduction` reference-identical routed
ordering against the exact production LINQ).
`nlc fix --text` skipped-fix selection now routes through the compiled N# skipped-index kernel when
the dogfood assembly is available, preserving the default safe-only behavior,
include-review-needed behavior, suggestion-only exclusion, unknown-safety exclusion, and source-order
output, with the previous `Contains`-based C# path kept as the fallback.
`nlc fix --text` applied-fix file grouping now routes through the compiled N# file-group kernel when
the dogfood assembly is available, preserving first-file-seen group order and per-file source order,
with the previous LINQ `GroupBy` output path kept as the fallback.
`nlc clean` artifact directory selection now routes through the compiled N# clean-ordering kernel
when the dogfood assembly is available, preserving ordinal first-source de-duplication,
node_modules exclusion, `bin`/`obj`/`.nlc` filtering, and stable descending-length deletion order,
with the previous LINQ selection/order path kept as the fallback after directory-existence IO.
`nlc update` all-NuGet selection now routes through the compiled N# NuGet-flag kernel when the
dogfood assembly is available, preserving source order and non-NuGet exclusion, with the previous C#
filter kept as the fallback.
`nlc update <package>` target-package narrowing now routes through the compiled N# package-rank
kernel when the dogfood assembly is available, preserving source order, duplicate package entries,
case-insensitive package-name matching, non-NuGet exclusion, and empty results for missing package
targets, with the previous C# filter kept as the fallback.
`nlc tidy` status summary calculation now routes through the compiled N# tidy summary kernel when
the dogfood assembly is available, preserving exact status matching for JSON `ok` and text summary
counts, with equivalent C# status-count scans kept as the fallback.
`nlc test` native xUnit/reflection runs now retain compact outcome ranks as public result objects
are created, then route text and JSON summary calculation through `TestCommandKernels`, which calls
the compiled N# `CliTestOutcomeSummaryInto` kernel when the dogfood assembly is available,
preserving `ok` as passed-or-skipped-only and preserving public passed/failed/skipped counts, with
the previous C# string-count summary kept as the fallback.
`nlc test --filter` test-case selection remains on the current C# predicates: N# filter matching has
parity and zero-allocation pressure evidence, but the best measured candidate only reached about
1.3x-2.0x and therefore misses the 5x production route gate.
NL010 namespace unused-import checking also remains on the current C# path: the dense N# ranked
kernel has parity and strong large-batch pressure evidence, but the production-shaped route that must
project linter identifiers/member names into namespace ranks does not clear the 5x gate.
`nlc tidy` dependency usage classification now routes through `TidyCommandKernels`, which calls the
compiled N# `CliTidyDependencyStatusRanksInto` kernel for ASCII package and import names, preserving
the current single-segment unknown rule, first-segment namespace match semantics, public status
strings, and reason text, with the previous C# classifier kept as the fallback for non-ASCII names
or unavailable dogfood.
`nlc tidy --fix` possibly-unused dependency selection now routes through `TidyCommandKernels` and
the compiled N# compact rank filter when the dogfood assembly is available, preserving exact status
matching and source order after dependency classification, with the previous C#
`Where(...).ToList()` path kept as the fallback.
`nlc tidy --fix` project.yml dependency-line removal now routes through `TidyCommandKernels` and the
compiled N# `CliTidyRemovalLineKeepFlagsInto` kernel for ASCII project lines and package names,
preserving current broad dependency-prefix removal and case-insensitive `nuget:` matching, with the
previous C# line filter kept as the fallback for non-ASCII input or unavailable dogfood.
`CompilerDogfoodProjectTests` verifies the packaged adapter can load
`NSharpLang.Compiler.Dogfood.dll` and answer identifier, receiver, source-context, raw source-line,
completion-prefix, completion receiver-context, completion item grouping, reflected method overload
grouping, doc-comment, strict editor identifier, declaration-name match, scoped visible-variable,
scoped identifier-lookup, and variable-declaration-name queries, plus diagnostic cluster trait
classifications and diagnostic severity summaries, compact diagnostic cluster grouping, diagnostic
cluster file-list ordering, diagnostic shadow suppression, diagnostic deduplication, reference result deduplication, stable
diagnostic deduplication, binding
candidate-column ordering, strict binding lookup, nearest declaration index construction, nearest declaration lookup,
semantic scope index construction, scoped visible-variable selection, CLI batch duplicate-id validation, CLI doc symbol/member
ordering and slug generation, CLI tree dependency deduplication, diagnostic severity filtering, symbol-kind filtering, symbol-name filtering, CLI first positional-argument
discovery, CLI build first source-operand discovery, parser newline-token compaction,
text-edit ordering, struct-copy readonly-field gating, skipped-fix selection, applied-fix file grouping, clean artifact directory ordering, update all-NuGet and target-package dependency filtering,
CLI reference-type filtering,
AOT requirement grouping, anonymous-union overload-shim eligibility, declared-type suffix lookup, type-creation ordering, compiler source-file de-duplication,
compiler stub namespace import ordering, inspect-summary reference-file summaries,
CLI stable string de-duplication for stale generated cleanup and target-framework summaries,
add/remove package operand discovery, tidy dependency-line keep flags,
DocQuery reference-pack assembly-name and type-candidate de-duplication,
CLI test outcome summaries,
and the accepted batch result packed-count kernel through the compiled N# methods. The same suite
also compiles and exercises the pressure-only path-matching, all-positionals CLI argument, build
option summary, and watch forwarded-argument parity kernels from the parity corpus without routing
them through product adapters; `CliCommandTests` verifies both
packaged CLI dogfood routes for duplicate batch request ids, `nlc update` target package
selection, `nlc doc` symbol/member ordering and slug generation, `nlc tree` dependency deduplication, and
`nlc query diagnostics --severity` filtering plus compiler-error severity filtering, skipped-fix
selection, applied-fix file grouping, clean artifact directory ordering, `nlc export csharp` reference de-duplication,
CLI reference-type filtering,
`nlc restore` project-reference de-duplication, `nlc update` dependency filtering, `nlc tidy`
status summaries, `nlc test` outcome summaries, `nlc tidy --fix` possibly-unused dependency selection, and `nlc tidy --fix`
project.yml dependency-line removal;
`CliParityAuditTests` verifies `nlc new` accepts the project name after a value-taking template
option through the first-positional route and `nlc clean` removes build artifact directories through
the production route;
`CodeFixTests` verifies the production fix-applicator ordering route.
`AotBlockerAnalyzerTests` verifies the production AOT requirement route combines public blockers,
ignores private/internal blockers, preserves both requirement flags, and emits sorted construct
names in the public annotation message.
`QueryIntegrationTests` exercises the public query surface with the adapter-enabled output,
including trimmed reference contexts and hover documentation. This is swap evidence for the
identifier-span, member-receiver, reference source-context, diagnostic/lint raw source-line,
completion-prefix, completion receiver-context, completion item grouping, reflected method overload
grouping, hover doc-comment, strict reference/rename
declaration-name guard, analyzer declaration-name column lookup, variable declaration name extraction, diagnostic severity summary across
JSON/text/CLI exit surfaces, diagnostic cluster grouping, check/build diagnostic deduplication, and
clustered diagnostic file-list ordering, `GetDiagnostics` lint shadow suppression, `GetDiagnostics` stable diagnostic deduplication, and
semantic reference result deduplication/order slices, plus strict binding candidate-column ordering,
strict semantic binding lookup, and LSP
editor word/span lookup for hover, definition, references, and rename entry points, nearest
same-file declaration index construction and lookup in the source-context definition fallback,
reflected method overload grouping and grouped member-completion
output, plus batch duplicate-id validation in `nlc query batch` and generated doc symbol/member
ordering and slug generation in `nlc doc`, plus dependency deduplication and ordering in `nlc tree`, plus text-edit
application ordering in `nlc fix`, plus diagnostic severity filtering in `nlc query diagnostics`,
batch diagnostics, daemon diagnostics, and strict `nlc build` lint gating, plus first positional
project/operand/package discovery in
`nlc new`, `nlc check`, `nlc fix`, `nlc update`, and `nlc export csharp`, plus first source-file
route selection in `nlc build` and `nlc run`, plus default no-option summary routing in
`nlc publish`, plus inspect-summary reference-file ordering in
`nlc query inspect`, plus symbol-kind filtering in `nlc query symbols`, plus skipped-fix text output
and applied-fix file grouping in `nlc fix --text`,
plus wildcard and bare substring symbol-name filtering in `nlc query symbols --filter`, plus artifact directory
selection in `nlc clean`.
`nlc doc` symbol filtering/order, symbol-page member ordering, and symbol-page slug generation are
also routed through the compiled N# doc-ordering kernel.
Path matching, all-positionals CLI argument filtering, option-bearing `nlc publish` argument
normalization, and `nlc format` discovered-file filtering have parity and benchmark evidence but are
not routed through production code-intelligence, query, daemon, publish option-bearing, or format
discovery paths because they currently miss the 5x speed gate. `nlc test` option summary parsing
also has parity evidence but remains C# because the inlined N# argv classifier is slower or only
parity on dry rows.
Broader query, hover, definition, diagnostic, completion candidate construction, semantic binding
table construction, remaining semantic-scope name/symbol table materialization, AOT public
annotation materialization, and CLI command logic still contain C# implementation code and remain in
scope for the dogfood rewrite.

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

Current parser pressure point: newline-token compaction is dogfooded through a compact token-kind
index kernel, but production parsing still projects C# `Token` records into the N# buffer and then
materializes a C# `List<Token>`. The real parser rewrite needs a compact token table owned by N# so
constructor filtering, cursor movement, token trivia, recovery boundaries, and recursive descent all
operate on the same allocation-light representation.

Current typo-suggestion pressure point: even after removing lowercase string allocation and
edit-distance matrix allocation, the N# row-buffer Levenshtein candidate is slower than the current
C# `SmartSuggester` path. This points at bounds-check-heavy array indexing and helper-call overhead
inside nested dynamic-programming loops. A production rewrite needs either stronger emitted-IL
optimization for checked row-buffer loops or a systems-memory primitive that lets the compiler prove
fixed row lengths and eliminate repeated bounds checks.

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
method-call receiver normalization. Completion item grouping and reflected method overload grouping
are dogfooded for member-access completion output, but reflection enumeration, semantic member
lookup, and completion item construction remain in C#. Strict editor
identifier lookup uses a separate N# helper because editor hover/rename semantics must not inherit
the query engine's snap-to-nearby-identifier behavior. Broader hover/diagnostic/completion output
shaping still needs N# implementations. Diagnostic cluster trait classification, diagnostic
severity summary counting and filtering, compact diagnostic cluster grouping, lint shadow suppression, strict semantic binding lookup, and
nearest same-file declaration index construction and lookup, semantic scope index construction, scoped visible-variable
selection, and reference result deduplication/order are now dogfooded.
Message-pattern materialization, cluster id materialization, and next-command materialization remain
C# formatter work.
These public string materialization misses are specifically about short string construction: direct
N# message-pattern construction, direct N# field hashing, and direct N# command-buffer construction
all beat their C# formatter-shaped helpers modestly, but they remain far below the 5x gate. The
CLI query position parser also shows helper-call overhead on tiny strings: direct parsing removes
all split allocation but still only reaches about 2.4x on the measured batch. Diagnostic severity
filtering cleared the gate once its compact-rank scan moved to an eight-wide unrolled path and the
checksum evidence stopped rescanning the output. The
strict reference/rename declaration-name guard now uses the same line-range cache, and semantic scope
index sorting has moved into N#, but broader semantic binding/scope table construction and compact
cache materialization around the N# lookup kernels are still C# host logic.
The batch result packed-count probe shows the same representation boundary:
`BitOperations.PopCount` gives a fast N# systems kernel over compact `ulong` words, but current C#
object-to-bitset projection overwhelms the win. A manual N# popcount using large unsigned mask
constants exposed an IL-emission overflow; unsigned integer literal lowering now preserves `U`/`L`
suffix types through analysis, overload binding, and IL emission, so the remaining systems work is
intrinsic-friendly bit operations plus earlier compact bitset materialization.
The `nlc test` outcome summary slice is the positive version of the same lesson: late projection of
public outcome strings misses the gate, but retaining compact ranks while result objects are created
lets the N# summary kernel clear 5x comfortably.
The production adapter keeps cache lifetime explicit, but the remaining code-intelligence work still
needs N# implementations for broader semantic lookup, completion construction, output shaping, and
CLI command orchestration.

## Rejected Probes

These probes were built, benchmarked, and removed because they did not clear the 5x gate or did not
produce a production-shaped win:

- IL compiler declared-type exact-name resolution (`ILCompiler.TryGetDeclaredTypeInfo` /
  `GetDeclaredTypeMetadataName`): the remaining unrouted declared-type candidate path is a first
  ordinal exact-name match over the enumerated declared-type name list. `DeclaredTypeExactNameFirstIndex`
  (in `CompilerServices/TypeLookup.nl`) reproduces that scan exactly — first-wins on duplicate names,
  1-based index, 0 on no match, with a tail-hash prefilter — and passes parity
  (`CompilerDogfoodProjectTests.AssertDeclaredTypeExactNameLookupLikeProduction`, including
  non-interned positive queries so ordinal string value equality is exercised). It is benchmarked by
  `CompilerServiceTypeLookupBenchmarks` over both corpus rows, kept as benchmark-only, and NOT routed.
  Unlike the accepted declared-type suffix/name-candidate kernels (whose C# baselines allocate via
  `Distinct`/`Where`/`ToArray` and run 11x-93x faster), the realistic baseline here is a plain
  zero-allocation `FirstOrDefault(Ordinal Equals)` loop over the already-projected name array, so
  there is no allocation to recover and the only edge is the tail-hash prefilter skipping full string
  compares on long dotted names. Measured (BenchmarkDotNet, Apple M4, .NET 10, 0 B both sides):
  - Representative (1024 names): NestedMiddle C# 1,326.79 ns vs N# 344.09 ns = **3.86x**; NestedLate
    C# 2,551.71 ns vs N# 798.61 ns = **3.19x**; Missing C# 1,162.79 ns vs N# 832.74 ns = **1.40x**;
    NestedEarly (2-element match) C# 1.458 ns vs N# 4.964 ns = **0.29x (N# slower)**.
  - LargeGenerated (8192 names): NestedLate C# 28,250.15 ns vs N# 5,653.97 ns = **5.00x**; NestedMiddle
    C# 13,844.46 ns vs N# 3,800.06 ns = **3.64x**; Missing C# 12,444.62 ns vs N# 5,297.66 ns = **2.35x**;
    NestedEarly C# 1.871 ns vs N# 4.923 ns = **0.38x (N# slower)**.
  Representative tops out at ~3.86x and the common compiler cases (tiny lists, early match, missing)
  are at or below 1.4x or actively slower because the N# delegate-call and bounds-check overhead
  dominates when there is no allocation to amortize. Only the LargeGenerated worst-case full scan
  reaches exactly 5.0x, and firm rule (b) forbids routing on the large/generated row alone. Do not
  route `TryGetDeclaredTypeInfo` through this kernel until the call site can own a cached compact
  declared-name table (so the scan is not the only thing measured) or the surrounding
  `GetDeclaredTypeMetadataName` recursion moves into one N# batch. Note also: `TypeResolver`
  simple-name resolution (`TypeResolver.ResolveTypeBySimpleName`, a `FirstOrDefault(t => t.Name ==
  simpleName)` over CLR exported types) is a sibling declared/CLR-type candidate path, but it lives in
  the LanguageServer project and is therefore out of scope for routing in this unit (touching it would
  trigger mandatory IDE visual verification); it is left unmeasured and unrouted here by constraint.
- `CompilationStub` top-level function namespace grouping: replacing the C# `GroupBy`/namespace
  ordering shape with compact namespace ranks removed allocation, but dry timings were only about
  1.75x faster on the representative corpus and 1.48x faster on the large corpus. Do not re-add this
  until the top-level function stub path can move more of the surrounding emission into N#.
- Declared extension-method key lookup in the IL compiler: a compact key-index scan avoided most
  LINQ allocation, but the N# string suffix loop was only about 1.4x-1.6x faster on representative
  rows and was slower on the many-match large row. This needs a better ordinal suffix/string
  comparison primitive or a broader declared-method binding table port.
- Project-reference cycle canonicalization: ranking nodes and selecting a minimal rotation in N#
  was about 25x faster on a large 512-node cycle, but only about 1.3x faster on a representative
  32-node cycle because rank construction and final public string materialization dominated. Keep
  the current C# rotation path unless a broader project-graph representation can cache ranks.
- Source-map validating cached-query eight-wide unrolling: doubling the existing four-wide
  equal-length fast path preserved parity but did not push the representative row over the gate in
  dry smoke (`89.6 us` N# vs `369.4 us` C#, about 4.1x). The added duplication was removed.
- Parser-facing lexer token materialization: compact N# `TokenizeMetadataInto` output can recreate
  the parser token stream on explicit-brace corpora, but the C# boundary still has to allocate
  `Token` records and public token values. A dry probe measured only about 1.2x on the
  representative corpus (`151.208 us` N# vs `180.334 us` C#) and about 3.0x on the large generated
  corpus (`2.466 ms` N# vs `7.325 ms` C#), so this is not a production lexer route. The parser needs
  a compact token table owned by N# before lexer dogfood can satisfy the 5x gate.
- Project config reference `HasValue` filtering: compact flag filtering was neutral to slower once
  the host still had to project `Reference.HasValue` and materialize the final `List<Reference>`
  (`77.0 us` N# vs `76.6 us` C# representative; `204.2 us` N# vs `178.4 us` C# large). This is a
  bad adapter slice; a useful port would need to own project-reference parsing/normalization.
- CLI test timeout duration parsing: direct ASCII duration scanning removed the C# trim/slice parse
  allocation, but the `--job Short` batch benchmark only reached about 1.27x on the representative
  corpus (`7.829 us` N# vs `9.937 us` C#) and about 1.23x on the large corpus (`67.073 us` N# vs
  `82.426 us` C#). Keep `nlc test --timeout` on the C# parser until N# has a faster tiny-string
  parse path or the surrounding test-command option parsing moves into one N# batch.
- CLI test option summary parsing: a one-pass N# argv classifier for `nlc test` preserved current
  help, option-value, and switch semantics without allocation, and the final probe inlined the
  classifier into the scan, but dry timings still missed the gate (`84.667 us` N# vs `62.834 us` C#
  on 18 args, `64.250 us` N# vs `66.084 us` C# on 64 args, and `91.667 us` N# vs `70.208 us` C# on
  1024 args). Do not route `Program.TestCommand` through this adapter; revisit only with a broader
  CLI parser representation or lower-overhead string/branch lowering.
- Analyzer overload parameter-signature distinctness via compact type-rank rows: the N# kernel
  (`AnalyzerOverloadSignatureDistinct` / `AnalyzerOverloadSignatureDistinctChecksumInto` in
  `CompilerServices/AnalyzerExhaustiveness.nl`) reframes `Analyzer.HasDistinctParameterSignature` /
  `ParameterSignaturesMatch` as an integer rank-row scan instead of `GetParameterTypeSignature`
  string build + ordinal string compare. It passed parity exactly (single-shot distinct/duplicate
  verdicts, batched checksum, and malformed-request guards in `CompilerDogfoodProjectTests`) and
  allocated zero managed bytes, but missed the gate: the `CompilerServiceAnalyzerOverloadSignature`
  rows measured `2.665 us` N# vs `2.339 us` C# on the representative corpus (about 0.88x — N# is
  SLOWER) and `184.146 us` N# vs `261.051 us` C# on the large generated corpus (about 1.42x). The
  string-signature comparison is the wrong shape for a compact kernel: once the analyzer has the
  per-parameter type signatures in hand, the C# baseline's per-parameter `string.Equals` over short
  interned signatures JITs to fast length/reference checks with no per-call allocation, so the
  rank-row scan only wins marginally at large arity and loses on the representative few-overload
  shape. Per the unit-4 guardrail, `HasDistinctParameterSignature` stays on the C# string path; do
  not route it. Revisit only if overload resolution adopts a retained type-interning rank table that
  removes signature-string construction across a broader slice (so the rank rows are already
  materialized and the win is amortized over many checks), and never on the large generated row
  alone.
- Union exhaustiveness through a late C# set-to-flag adapter: the compact N# kernel cleared the
  gate, but projecting `HashSet<string>` coverage into flags at the tail of
  `CheckMatchExhaustiveness` missed the 5x bar on the corrected benchmark rows (`10.482 us` N# vs
  `34.107 us` C#, `10.761 us` N# vs `20.778 us` C#, `7.271 us` N# vs `18.559 us` C#,
  `101.394 us` N# vs `307.689 us` C#, `122.111 us` N# vs `249.756 us` C#, and `70.987 us` N# vs
  `219.967 us` C#). The accepted analyzer route builds compact coverage flags directly and calls
  `TrySelectMissingUnionCasesFromFlags`; keep this projected row as rejection evidence.
- CLI implicit test-package membership: a compact package-rank membership kernel made missing
  package checks dramatically faster (`2.848 ns` N# vs `743.150 ns` C# representative and
  `2.807 ns` N# vs `6.844 us` C# large), but existing-package rows only reached about 1.8x
  (`4.570 ns` N# vs `8.382 ns` C# representative; `4.687 ns` N# vs `8.388 ns` C# large) because the
  C# `Any` baseline exits after the first early match. Do not route `AddPackageReferenceIfMissing`
  through a one-off adapter call; revisit this only as part of a retained package-name index or
  broader reference-resolution port.
- CLI reference-resolution best-score selection: selecting the first highest non-negative
  compatibility score through a compact N# score-array scan removed the current LINQ
  `Where`/`OrderByDescending` allocation and reached about 5.35x on the large generated corpus
  (`379.292 us` N# vs `2.029 ms` C#), but the representative 128-candidate row only reached about
  1.15x (`88.708 us` N# vs `102.208 us` C#). Do not route `SelectBestAssetAssemblies` or NuGet
  dependency-group selection through this adapter slice; reference resolution needs to own a broader
  retained compatibility table or more of package metadata parsing in N# before this can clear the
  gate.
- CLI batch result counting through current result objects: the packed N# popcount kernel cleared
  the speed gate once ok flags were already represented as compact `ulong` words, but the
  production-shaped C# projection from `BatchQueryItemResult.Ok` into that bitset failed immediately
  (`1.452 us` N# projected row vs `300 ns` C# count on the representative mixed corpus). Do not
  route `BatchQueryRunner` through this adapter bridge. The accepted production route keeps packed
  ok flags while each public result object is created and calls `CliBatchResultPackedSuccessCount`
  directly.
- IL compiler entry-point single-candidate selection: compact key/name/static arrays removed the
  LINQ branch allocation for the fallback `_methods.Where(...).OrderByDescending(...).ThenBy(...)`
  path, but `--job Short` only reached about 1.16x on the representative single-candidate row
  (`568.9 ns` N# vs `661.9 ns` C#), 1.12x on the representative missing row (`570.7 ns` N# vs
  `641.5 ns` C#), and about 1.09x on the large rows (`4.518 us`/`4.503 us` N# vs
  `4.916 us`/`4.899 us` C#). Keep `GetEntryPointMethod` on the current C# path until N# owns the
  broader method table or entry-point diagnostics instead of just this one scan.
- Semantic-scope single-query/public API bridge: moving the compact semantic-scope cache to the
  compiler adapter and routing public `SemanticModel`/completion calls through it failed the
  production-shaped dry probes once dictionary materialization, `TypeInfo` lookup, and per-call
  adapter overhead were included. `CompilerServiceSemanticScopeVisibleVariablesBenchmarks --job Dry`
  reported `22.261 ms` N# vs `51.869 ms` C# on the representative row (about 2.3x) and
  `129.700 ms` N# vs `48.833 ms` C# on the large row (slower). The lookup bridge reported
  `33.502 ms` N# vs `30.026 ms` C# representative and `186.249 ms` N# vs `140.916 ms` C# large.
  Keep the compact semantic-scope kernels in the parity corpus for future batched/caller-owned
  routes, but do not route `SemanticModel.GetVisibleVariablesAtPosition`,
  `SemanticModel.LookupIdentifierAtPosition`, or completion's single-query calls through an adapter
  bridge.
- NL010 namespace unused-import checking: the dense-rank N# kernel removes the repeated
  known-type/member scans and allocations from the C# `Any(...Contains...)` loop, but it only clears
  the gate when ranks are already available. The optimized dry probe measured ranked-core rows at
  `69.833 us` N# vs `179.708 us` C# representative (about 2.6x) and `124.334 us` N# vs `3.102 ms` C#
  large (about 25x). Once the production-shaped C# projection from collected identifiers/member names
  into namespace ranks is included, the rows were `97.666 us` N# vs `179.708 us` C# representative
  (about 1.8x) and `796.084 us` N# vs `3.102 ms` C# large (about 3.9x). Keep `CheckUnusedImports` on
  the current C# route until the linter tracks compact namespace usage during AST visitation or a
  broader linter rewrite moves import analysis into N#.
- CLI format discovered-file path scanning: direct N# segment scanning removed split allocations for
  `nlc format` recursive file discovery but was slower than the current C# split helper on both dry
  rows (`468.334 us` N# vs `205.167 us` C# representative and `2.452 ms` N# vs `1.853 ms` C# large).
  Keep this as benchmark-only evidence until a broader format-discovery port owns path enumeration
  and segment classification together.
- Formatter `FormatSafe` reparse-error safety scan: `Formatter.FormatSafe` reparses formatted output
  and rejects the formatting when any reparse diagnostic has `ErrorSeverity.Error`
  (`reparseResult.Errors.Any(e => e.Severity == ErrorSeverity.Error)`), then collects the matching
  error messages for a `string.Join("; ", ...)` warning. `ErrorSeverity` has only two values
  (`Warning = 0`, `Error = 1`), so the gate is a trivially cheap linear scan and the C# `Any`
  short-circuits on the first error. A compact severity-flag kernel
  (`FormatterSafetyScan.nl`: `FormatterSafetyHasError` plus `FormatterSafetyErrorIndicesInto`, which
  writes error-severity indices into a caller-owned `int[]` and defers all string materialization)
  passed parity and reported zero managed allocation, but the normal BenchmarkDotNet run measured
  only `707.8 ns` N# vs `2,066.0 ns` C# on the representative corpus (about 2.9x) and `6,184.7 ns` N#
  vs `16,446.6 ns` C# on the large generated corpus (about 2.7x). Both rows miss the 5x gate. The
  benchmark deliberately excludes the public `string.Join` message materialization (the host
  boundary) to give the kernel its best case, and the only reason the C# baseline is even ~2.7-2.9x
  slower is the `Enumerable.Range().Where().ToArray()` allocation in the error-collection path — the
  severity scan itself is essentially free. In production the dominant cost is the message
  `string.Join`, which this kernel cannot remove. Keep `FormatSafe` on the current C# path; the
  `FormatterSafetyScan.nl` kernel, benchmark
  (`CompilerServiceFormatterSafetyScanBenchmarks`), and `CompilerDogfoodProjectTests` parity
  coverage are retained as rejection evidence only.

## Code-Intelligence Output Construction Audit (Unit 7)

This audit inventories the remaining hover/definition/diagnostic/completion *output construction*
C# in the non-LSP compiler-side `CodeIntelligence` library
(`src/NSharpLang.Compiler/CodeIntelligence/CodeIntelligenceService.cs`, `Models.cs`,
`OutputFormatter.cs`). The verdict is **REJECT / audit-only**: the remaining pieces are pure string
materialization with no compact integer-domain kernel, so they cannot clear the 5x gate over a late
one-off adapter call. The pieces with a genuine compact-array shape (grouping, dedup, clustering,
ranking, span/offset math) have *already* been routed — see the accepted code-intel kernels
(`IdentifierSpans.nl`, `CompletionGrouping.nl`, `CompletionReceivers.nl`, `DiagnosticClusters.nl`,
`DiagnosticDeduplication.nl`, etc.) and their benchmark entries above. What
remains below is the residue: the per-call string assembly that wraps those kernels.

Recent rejected probes (Rejected Probes section; semantic-scope public-API bridge, NL010 namespace
checking, format path scanning) all confirm the same boundary cost: once the production-shaped C#
projection into-and-out-of the N# kernel and the public string/object materialization are included,
the 5x gate is lost even when the integer core is 2-25x faster. Crossing the C# boundary over public
strings/objects per call is the failure mode for every piece below.

Per-piece inventory and routing verdict:

- `GetHoverInfo` (`CodeIntelligenceService.cs:725`) — orchestration only: it calls
  `GetTypeAtPosition`, `FindDefinition`, `FindCompilationUnit`, `BuildSignature`, and
  `ExtractDocComment`, then allocates one `HoverResult` record. The position/lookup work is already
  served by routed span/scope kernels; the residue is a single record construction. **REJECT** — no
  array, no hot loop, one allocation per on-demand hover. Dogfooding this would mean N# owning the
  whole hover *result type* and its construction, not a one-off adapter call.
- `BuildSignature` / `FormatFunctionSignature` / `FormatTypeRef`
  (`CodeIntelligenceService.cs:749-803`) and the parallel `FormatTypeReference` family
  (`:2411` and the `FormatTypeReferencePublic`/inner switch around it) — recursive
  `StringBuilder`/string-interpolation/`string.Join` over a single `FunctionDeclaration` or
  `TypeReference`. This is the canonical string-materialization-dominated shape: the cost *is* the
  string building, there is no separable integer kernel to extract. A compact route would have to
  pre-intern every type-name fragment into ids and re-materialize the exact same string, paying the
  boundary twice for zero arithmetic. **REJECT** — pure materialization; mirrors the rejected
  diagnostic cluster *trait+pattern* probe
  (`...DiagnosticClusterTraitPatternBenchmarks`), which was kept as pressure evidence precisely
  because the public string materialization sank the gate.
- `DiagnosticResult` construction in `GetDiagnostics` (`CodeIntelligenceService.cs:214-234`) and the
  two `ToDiagnosticResult` overloads (`:341`, `:376`) — per-error record construction with a severity
  switch, relative-path computation, and optional source-snippet extraction. The *structural* parts
  of this path that had compact shape are already routed: shadow suppression
  (`CompilerServiceDiagnosticShadowSuppressionBenchmarks`), dedup
  (`CompilerServiceCodeIntelligenceDiagnosticStableDeduplicationBenchmarks`), severity summary
  (`CompilerServiceCodeIntelligenceDiagnosticSummaryBenchmarks`), and cluster file lists
  (`CompilerServiceDiagnosticClusterFileListBenchmarks`). What is left is the record allocation +
  string field copy per diagnostic. **REJECT** — string/object materialization over the public
  `DiagnosticResult` boundary; the routed kernels already proved the only gate-clearing work here is
  the integer rank/dedup core, which is done.
- `OutputFormatter` text/JSON emitters: `HoverToText`/`HoverToJson` (`:569-603`),
  `CompletionsToText` (`:463`), and the `InspectToText`/`DefinitionToText`-style `AppendLine`
  builders — line-oriented `StringBuilder.AppendLine` over already-materialized result records.
  These are terminal presentation buffers with no arithmetic. **REJECT** — pure formatting; identical
  in shape to the rejected `nlc format` path-scanning probe where direct N# string scanning was
  *slower* than the C# helper.

Recommendation (broader N#-owned representations that would be required to ever route these):
None of the above is dogfood-able as a late adapter call over public strings/objects. The only path
that would change the verdict is **broader N# ownership of the result representations themselves** —
i.e. N# owning the `HoverResult`/`DiagnosticResult`/signature value types and the buffer that backs
their string fields, so signature/diagnostic text is assembled in N#-owned `char`/offset buffers as
part of a larger compiled emission stage (the same way the IL-compiler and formatter ports are gated
on N# owning the surrounding emission, per the `GetEntryPointMethod` and CLI-format rejected probes).
Absent that broader port, signature and diagnostic string assembly must stay on the C# route. No new
kernel or benchmark is warranted for this unit; the achievable compact-array code-intel routes are
already landed and benchmarked above.
