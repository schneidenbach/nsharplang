# N# compiler ownership queue

This is the authoritative execution order for the systems-language closeout. The former broad
track notebooks were replaced by vertical ownership prompts on 2026-07-10.

Run one numbered task at a time. Every task embeds the complete execution contract before its
slice-specific prompt. Do not batch multiple numbered files into one implementation turn.

## Queue protocol

1. Read `systems-language-closeout/STATUS.md` and open the first unchecked task below.
2. Revalidate its named code and accept set against the current tree and recent history.
3. Complete one terminal vertical slice, including N# implementation, direct production routing,
   native tests, C# deletion, required gates, commit, repin, and documentation.
4. Mark a non-repeatable task complete only after all of its stated exit conditions pass.
5. Tasks 015–020 are iterative owner burn-downs. One goal turn completes one concrete sub-slice.
   Keep the task unchecked and record the next exact sub-slice in STATUS.md until its named owner
   is gone or is a reviewed zero-policy mechanical host.
6. Update this checklist and STATUS.md in the same commit as the completed slice. Never mark work
   complete based on preparatory code or tests alone.

## Ordered tasks

- [ ] [001 — External static fields and properties](001-external-static-fields-and-properties.md)
- [ ] [002 — Bound identifier reads](002-bound-identifier-reads.md)
- [ ] [003 — Instance fields and properties](003-instance-fields-and-properties.md)
- [ ] [004 — Fixed-arity direct calls](004-fixed-arity-direct-calls.md)
- [ ] [005 — Construction and array literals](005-construction-and-array-literals.md)
- [ ] [006 — Primitive binary expressions](006-primitive-binary-expressions.md)
- [ ] [007 — Conditional and short-circuit expressions](007-conditional-and-short-circuit-expressions.md)
- [ ] [008 — Complete range/index owner deletion](008-range-index-owner-deletion.md)
- [ ] [009 — External base and interface resolution](009-external-base-interface-resolution.md)
- [ ] [010 — Lambda definition placement and visibility](010-lambda-definition-placement.md)
- [ ] [011 — Record-with lowering for value receivers](011-record-with-value-receivers.md)
- [ ] [012 — Readonly-field initialization placement](012-readonly-field-initialization.md)
- [ ] [013 — Synchronous iterators](013-synchronous-iterators.md)
- [ ] [014 — Async iterators](014-async-iterators.md)
- [ ] [015 — Remaining emitter decisions](015-remaining-emitter-decisions.md)
- [ ] [016 — Parser and syntax-diagnostic ownership](016-parser-and-syntax-diagnostics.md)
- [ ] [017 — Semantic analyzer ownership](017-semantic-analyzer-ownership.md)
- [ ] [018 — Systems analyzer ownership](018-systems-analyzer-ownership.md)
- [ ] [019 — Compiler-contained tooling ownership](019-compiler-contained-tooling.md)
- [ ] [020 — Native N# test-runner capabilities](020-native-test-runner-capabilities.md)
- [ ] [021 — Final compiler ownership audit](021-final-compiler-ownership-audit.md)

The order is deliberate. If current code proves a dependency has changed, update the queue in a
small documentation commit with concrete evidence before reordering; do not silently skip ahead.
