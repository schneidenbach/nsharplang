# Compiler Dogfood Rewrite Plan

Status: active goal
Updated: 2026-06-03

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

The metadata-buffer dry run also passed parity on 2026-06-03. `TokenizeMetadataInto` reported zero
managed allocation and filled token kind, source start, value length, line, and column buffers. The
large generated corpus crossed the dry smoke threshold at about 7.0x faster than the current C#
lexer filling equivalent metadata buffers (992 us vs 6.99 ms), while the representative corpus was
only near parity (105 us vs 110 us). This is useful compact-token-table evidence, not acceptance
evidence.

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
  ranges into caller-owned buffers, builds a small-file offset-to-line cache, and runs the same query
  workload without managed allocation.
- `CompilerServiceSourceTextLineMapCachedQueryBenchmarks` separates the steady-state query path after
  a document line map has already been built. The validating N# query API keeps the external
  line/column checks; the trusted N# query API is a separate internal-batch contract for positions
  already proven valid by the caller.

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

The dogfood project now includes `CompilerServices/IdentifierSpans.nl`. `CompilerDogfoodProjectTests`
compiles it through the SDK project and checks returned spans against the production snap rules for
valid selections, nearby punctuation/whitespace selections, invalid lines, empty lines, CRLF input,
standalone-CR input, Unicode identifier characters, member receivers with whitespace before the dot,
and the current nullable-member-access edge. It verifies the production-shaped match-count APIs,
the checksum parity helpers, the direct member receiver scanner, and the cached receiver-cache API.
The N# candidate imports `System`, uses ASCII fast paths, and falls back to
`Char.IsLetterOrDigit` / `Char.IsWhiteSpace`, matching the current C# identifier and whitespace
rules without putting the runtime predicates on the common ASCII path.

The normal BenchmarkDotNet run on 2026-06-03 passed match-count and buffer parity and reported zero
managed allocation on the N# code-intelligence paths. `CodeIntelligenceIdentifierSpansInto` ran
about 81x faster than the current C# split-per-query baseline on the representative corpus
(5.56 us vs 448.94 us, 0 B vs 4.1 MB) and about 682x faster on the large generated corpus
(91.76 us vs 62.57 ms, 0 B vs 129.6 MB).

`CodeIntelligenceMemberReceiversCachedInto` also cleared the normal BenchmarkDotNet speed gate. It
ran about 174x faster on the representative corpus (2.88 us vs 500.69 us, 0 B vs 4.6 MB) and about
233x faster on the large generated corpus (225.03 us vs 52.51 ms, 0 B vs 129.6 MB). This is
acceptance-grade benchmark evidence for the batched code-intelligence service shape, but the
production CLI/LSP query, hover, definition, reference, and completion paths still need an adapter
and swap proof before those surfaces can be claimed as dogfooded.

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
line splitting or source line-map construction. Calling optimized BCL `string.IndexOf` improved the
range-buffer candidate, and offset-to-line caches make large steady-state query batches clear the dry
5x threshold, but representative query loops and large map construction still miss the acceptance
gate. To reach the 5x goal, N# needs a faster native/string scanning primitive plus more
bounds-check-friendly indexed-array/span lowering for batches, without relying on hand-unrolled
compiler-service loops as the normal programming model.

Current code-intelligence pressure point: the identifier-span candidate gets its speed from batching
queries and reusing caller-owned line/result buffers. The N# compiler can emit a direct
`Char.IsLetterOrDigit` runtime static call from an imported `System` namespace while keeping the
normal BenchmarkDotNet speed gate above 5x, so the remaining work is a production adapter and swap
proof rather than an identifier-character semantic gap. The member-receiver candidate shows the next
API lesson: the 5x win comes from a source-level receiver cache plus caller-owned buffers, not from
calling a tiny backward scanner once per request. Production code-intelligence adapters should keep
that cache lifetime explicit.
