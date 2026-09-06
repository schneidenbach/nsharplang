# S2.2(l1): concrete dictionary value enumerator prerequisite

S2.2(l0) is accepted and published at `e7d4486d9`. Its verified SDK gets the parked entry-point
driver past the exact dictionary-array signature. The complete C# entry-point owner remains
unchanged; this prerequisite must pass before that owner can be moved and accepted as S2.2(l).

## Measured refusal

The exact direct acquisition `structRegistry.get_Values().GetEnumerator()` is refused as a local:
`Dictionary<string, ColumnarStructDef>.ValueCollection.Enumerator` reaches
`emit.local.unsupported-type` in `ColumnarEntryPointRealization.TryEmit`. The resumed
`./scripts/dev.sh EntryPoint` command exited 1 before tests. Its exact four source files, command,
output and hashes are retained at
`/private/tmp/nsharp-s22l-executor-logs/resume-20260906/attempt-02-direct-values-enumerator/`;
receipt SHA `e302525d62244fc1352fdc462b5b741a235c2afaff50c85f9debd378508ad105`.

The preceding attempt stored `ValueCollection` separately and was also refused. That intermediate
local is unnecessary: the old C# reads Values once and immediately acquires its concrete enumerator
before entering the try. The direct N# chain preserves this phase and is the required source form.
An interface enumerator, boxing, a copied collection or a semantic-registry snapshot would change
the original owner and is not a substitute.

The refusal proves the storage boundary, not which internal admission arm supplied false. The
formatted type name does not establish whether its arguments are source builders or completed
runtime types after member-result rebinding. Observe the actual failing initializer type through
the N# predicate before choosing the correction's dispatch point. If rebinding returned the wrong
definition or arguments, correct that N# binding owner rather than admitting the wrong handle.
The phase and branch review at
`/private/tmp/nsharp-s22l-review/resume-20260906/branch-placement-audit.json` is retained as local
evidence; its branch hypotheses are explicitly provisional.

## Connected N# correction and controls

1. Establish the actual generic definition, argument identities and builder/open-type predicates.
   Preserve any diagnostic source and failed command, then remove the temporary diagnostic.
2. Admit the genuine concrete `Dictionary<TKey, TValue>.ValueCollection.Enumerator` storage shape
   through the existing N# type owner, using exact BCL generic-definition identity and the existing
   Dictionary key/value admissibility rules. Do not add name-only acceptance, a C# helper, generic
   value-type admission, or separate ValueCollection-local support for convenience.
3. Prove the exact type and member results through the existing N# call/address machinery. Existing
   source routes suggest it is sufficient; only actual compilation and execution can accept it.
   A later member refusal must be measured before extending another policy surface.
4. Canonical controls must distinguish the exact predicate from the whole supported-type surface:
   adjacent runtime-closed types may already pass via the catalog. Retain genuine/foreign definition,
   open/element/value shapes and existing key/value boundaries without weakening unrelated assertions.
5. A self-contained native fixture must use a real source-class dictionary, direct Values acquisition,
   a concrete enumerator local, MoveNext, typed Current and finally Dispose. Exercise value order and
   reference identity, early exit and an exception after adding a new key. Inspect the actual local,
   method operands and exception region to prove unboxed concrete storage and reached disposal;
   a counter on an unrelated wrapper does not prove the BCL enumerator's cleanup.
6. Commit focused-green N# code and tests. Compare the accepted fixed corpus and strict diagnostics;
   C# and the ownership ratchet remain unchanged for this capability prerequisite. Run a fresh backend
   product gate, then publish and verify the SDK with the same committed native fixture and actual
   package/cache/task-load evidence before the parked l owner consumes the capability.

The next connected ownership cut remains the complete
[S2.2(l) entry-point driver](2026-09-06-s22l-entrypoint-next-cut.md), including its reached keyed
awaiter local. Tasks 015/021/022/023 and the overall goal remain open.
