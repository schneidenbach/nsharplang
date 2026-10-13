# Iterator body lowering unification

**Status:** architectural PoC complete; synchronous straight-line statement migration is in progress
**Decision:** lower iterator suspension to ordinary method-body IR before emission; do not keep the iterator value emitter as a fallback.

**PoC checkpoint:** a tuple declaration inside a synchronous iterator compiles and executes across three yields. Both an ordinary method and the iterator use `ColumnarMethodBodyPlanner.TryAppendTupleDeclaration` for declaration evaluation and extraction. The iterator test asserts the method-body statement route for an ordinary call statement and the tuple declaration on the production MoveNext plan, so the old iterator tuple implementation cannot satisfy the proof. Iterator lowering supplies exact state-machine field bindings; the shared planner owns the source expression's single evaluation, tuple extraction, stores, and binding publication.

**Slice 1 progress:** ordinary inferred locals, typed-local initializers, tuple declarations, simple assignments to hoisted fields, simple `if`/`else` branches that assign hoisted fields, and discarded expression statements whose value forms are claimed by the shared planner enter a method-body statement owner. The iterator assignment entry uses the same identifier binding and assignment-conversion owners, gated to exact state-machine fields; supported member/indexer stores continue through the shared store-target planner. Synchronous iterator locals supply exact machine-field bindings; ordinary inferred locals keep plan-local bindings. Initializers the planner explicitly declines (including lambdas and event subscriptions), uninitialized captured typed locals, compound member/indexer stores, and awaited local initializers in async iterators remain on the current iterator body path. This is a measured migration boundary: routing captured event subscription initializers through the narrow shared statement path regressed `census-events`, so that shape stays with its current owner until the shared body path can lower it. The new conditional claim accepts only branch trees of field assignments and does not include declarations, suspension, loops, or exits. Yields and other statement forms also remain with the iterator statement walker; this is not completion of the general body rewrite.

**Slice 2 progress:** non-suspending `while` and `for` loops whose bodies contain method-body-owned expression statements now use shared method-body branch and loop planning. Simple and arithmetic compound assignments plus integer postfix steps target already-bound machine fields; discarded values and resolved sibling calls use the shared expression dispatcher. A `for` loop with a simple field-assignment initializer is planned in one shared route. When the initializer is a scoped local declaration, the iterator owner still creates and publishes its exact field binding, then the shared planner owns the condition, body, and step. Nested `break` and `continue` bind to the nearest shared loop, and `for` continuation targets its step label. Runtime assertions cover loop entry, exit, break, continue, shared expression evaluation, and a sibling call's single evaluation. Loops containing suspension, declarations in their body, returns, or other unsupported body forms retain the iterator walker's path.

## Problem and decision

`func*` and `async func*` bodies have a different statement and expression owner from ordinary function bodies. That owner already handles the state-machine-specific work, but it also carries a second, smaller implementation of ordinary language constructs. As a result, an expression or statement accepted in an ordinary method can still decline inside an iterator with NL103. The remaining cases are inventoried in `/private/tmp/claude-501/-Users-spencer-repos-nsharp-worktrees-census-merge/a7573ffd-4ca0-4670-a215-8c6d75e6d514/scratchpad/iterator-declines.md`; the inventory includes deconstruction, statement forms, compound stores, broader increment types, protocols, local functions, lambdas, events, and expression forms.

The long-term owner should be a lowering pass over the columnar body representation. It should turn each iterator function into (1) a state-machine type and factory description and (2) ordinary method bodies for `MoveNext` and the other CLR members. The `MoveNext` body must contain no source-level `yield` or `await`; those become state updates, stores, branches, and ordinary returns. Once rewritten, the body goes through the same general statement and expression emitter as every other method.

This is the Roslyn-shaped boundary: state-machine rewriting owns suspension, hoisting, and generated members; ordinary method-body emission owns the language constructs in the rewritten body. N# should preserve its own columnar IR and emitted metadata contracts rather than port Roslyn's bound-tree implementation.

## Current architecture

`ColumnarIlEmitter` detects `func*` and `async func*` and routes them to `ColumnarIteratorRealization`. `ColumnarIteratorPlanner` scans the source node table into `ColumnarIteratorShape`: yield and await counts, local and spill fields, loop and enumerator fields, catch and try-region facts, generic facts, and generated member signatures. `ColumnarIteratorRealization` creates the machine type, fields, CLR interface implementations, constructors, factory, and methods.

The iterator body itself is planned by `ColumnarIteratorBodyPlanner` in `ColumnarIteratorPlanner.nl`. `BuildMoveNextPlan` and `BuildAsyncMoveNextCorePlan` construct specialized code plans. `EmitStatement`, `AppendValue`, and their helpers then handle statements, expressions, suspension points, exception regions, enumeration, lambdas, events, and storage against machine fields. The machine's public members and the body plan are executed separately. This separation is the source of the subset: the iterator body owner must keep deciding which ordinary syntax it accepts and how it emits it.

Some expression work already reaches shared columnar value owners through `ColumnarIteratorBodyScope` and `ColumnarMethodBodyPlanner.TryAppendValue`. That is useful reuse, but it does not make the body unified: the iterator still has its own statement walker, statement emitter, special cases, and declines. For example, `ColumnarIlEmitter.EmitStatement` has a tuple-deconstruction implementation; the iterator's `WalkStatement` and `EmitStatement` do not route that statement through it.

Ordinary `async func` methods are different from async iterators. They use `ColumnarIlEmitter`'s general method-body statement and expression emitter. Await is currently lowered by `TryEmitBlockingAwait`, which calls the awaiter's `GetResult` synchronously; successful returns are wrapped as `Task`, `Task<T>`, `ValueTask`, or `ValueTask<T>`, and the async body has a fault-to-task wrapper. They do not use the iterator realization and are not currently lowered to a resumable async method state machine. Async-iterator unification must not be described as reusing an existing ordinary async state-machine emitter.

## Proposed columnar rewrite

Add a planner-owned iterator state-machine lowerer between `ColumnarFunctionInput` and method-body emission. Its output should be explicit, inspectable facts rather than IL instructions:

- a generated type identity and generic owner mapping;
- fields for captured parameters, locals live across a suspension, pending awaiters, current value, state, and protected-region/disposal bookkeeping;
- generated ordinary method inputs for the factory, `MoveNext`, `Current`, disposal, and async-iterator protocol members;
- a rewritten `MoveNext` node table whose nodes preserve source-origin spans and whose storage bindings resolve machine fields as method-body bindings.

The lowerer should preserve each source operation's order and resolved symbol identity. It should use existing semantic facts and expression binding, and it should not resolve members again by matching their names. A suspension node is replaced with ordinary stores and branches. For a synchronous `yield return`, the rewritten path stores the yielded value in the machine's current field, writes the resume state, and returns `true`; the resume label resets the running state and continues. `yield break` and natural completion return `false`. For async iterators, `await` gets a resume state and an awaiter field; `yield return` completes the pending `MoveNextAsync` operation and returns control to the consumer. The async-iterator contract remains a distinct CLR protocol even though the rewritten body uses the ordinary emitter.

The first implementation should hoist every local that crosses a suspension and leave other locals as ordinary method locals. A later liveness pass can minimize fields where proof and debugging need it. Any temporary value live across a suspension must be spilled to a field, with evaluation order fixed before the suspension. Compound assignment lowering must evaluate a receiver and index arguments exactly once. Byref, pointer, and ref-like values must not be placed in machine fields; if such a value is live across a suspension, the compiler should issue the language's appropriate diagnostic rather than inventing storage.

Lexical binding and storage are separate facts. A local becomes visible at its declaration and is hidden again at scope exit, even when its field is declared before the method body is emitted. Disjoint locals can share a field only when liveness and exact type compatibility prove the slots do not overlap. Captured locals used by nested functions must preserve the existing closure semantics, including per-iteration capture identity.

## Exception handling and cleanup

Exception-region lowering is a prerequisite for broad iterator parity, not a final polish step.

- A `try` without a suspension may stay as a normal CLR protected region in the rewritten method.
- A `yield` or `await` inside a protected region needs a resume path that legally re-enters that region. Branching directly into a CLR protected region is invalid IL.
- `finally` blocks must run on normal completion, exceptions, and iterator disposal after a consumer stops early. The state machine needs explicit cleanup states or equivalent generated cleanup dispatch.
- Catch clauses and filters keep source order and CLR first-pass filter behavior. Exceptions thrown by a filter make that filter false. Catch variables are hoisted only when their value is needed after suspension.
- Async cleanup such as `await using` and an awaited `finally` must resume `DisposeAsync` correctly. Disposal must not be reduced to a blocking wait.
- Illegal source forms remain analyzer diagnostics: suspension in a filter, yield from a catch/finally, and suspension inside `lock` remain rejected where the language contract says so.

No `ret` may be emitted inside a protected region. Rewritten exits must store a result and use `leave` to a common method exit, matching the ordinary emitter's protected-return contract.

## Generics, members, and generated identity

The existing metadata contract is worth retaining. Free-function machines are module-level generated types. Member iterator machines are nested in the declaring type so they can access private instance and static members. A machine carries declaring-type generic parameters first and method generic parameters after them; method constraints and dependent constraints must be copied to the generated owner at the same CLR positions. The body must bind `this`, enclosing fields, inherited members, and overloaded calls to the same semantic identities the ordinary member body uses.

Generated type and member names must remain deterministic for a source file and declaration ordinal. Generic field and method handles must be rebound to the constructed machine type before the emitted ordinary body uses them. The lowerer must keep existing generic-iterator ABI tests green while moving body ownership.

## Debug information and source mapping

The rewrite must retain an origin span for every source-derived node and mark generated dispatch, cleanup, and plumbing nodes as hidden. Source `yield` and `await` positions should remain the visible step points; a resume should continue at the first source operation after the suspension. Hoisted locals need their source names and lexical lifetimes in debug metadata. Generated fields and states must not appear as user locals.

The current columnar iterator plans do not establish a full sequence-point contract for generated state machines. The migration must first record what the current emit path writes to Portable PDBs, if any, and then add an explicit PDB/sequence-point parity test before claiming debugger parity. Missing current sequence points are a tracked gap, not evidence that synthesized offsets are an adequate replacement.

## Proof and parity strategy

The proof-of-concept must add a shape that currently declines inside an iterator, compile it through the rewritten ordinary method-body path, and execute it. It should pin both the behavior and the route taken, so an old iterator-emitter fallback cannot make the proof pass unnoticed.

Existing coverage already gives a useful parity net:

- `tests/native/iterators` covers synchronous and asynchronous iteration behavior and must keep passing.
- `tests/native/census-iterators` covers iterators across receivers, locals, loops, closures, stores, exception regions, and awaits.
- `tests/native/async-member-iterators` and `tests/native/async-generic-iterators` pin async member, generic, and cleanup behavior.
- `ColumnarIteratorPlanner` and `ColumnarIteratorRealization` estates pin shape analysis, plans, realization, metadata, and decline attribution.
- Existing ILVerify coverage checks generated assemblies for valid IL; iterator parity needs targeted ILVerify over PoC and representative sync, async, generic, and protected-region assemblies.
- `tests/native/ownership-audit` must remain at 26/26 and must reject any new production C# body owner.

For each slice, focused evidence is the relevant compiler Plan/Emit estate and native iterator projects, plus ILVerify where the generated machine or EH layout changes. At migration completion, run the fresh non-VS-Code integration checkpoint required by `AGENTS.md`; this task's machine-shared constraint explicitly forbids `test-all.sh`, so the final handoff must report that gate as not run and provide the narrower evidence actually obtained.

## Migration slices and rough size

Estimates are engineering effort for one compiler engineer, not elapsed calendar time. They include focused tests and cleanup.

| Slice | Work | Size |
|---|---|---:|
| 0. Contract and PoC | Define generated method-input/storage-binding contracts; rewrite one declined straight-line iterator shape; execute it through ordinary body emission and pin the no-fallback route. | 1–2 weeks |
| 1. Synchronous straight-line bodies | Lower `yield return`/`yield break`, local and parameter storage, simple branches, ordinary calls/expressions, and factory/machine members. | 1–2 weeks |
| 2. Synchronous control flow and stores | Loops, break/continue, tuple deconstruction, local functions/lambdas/events, compound member/indexer stores, conversions, and protocol-based enumeration. | 2–3 weeks |
| 3. Synchronous exception regions and disposal | Try/catch/filter/finally, using, nested protected-region resume, early consumer disposal, and cleanup failure parity. | 2–3 weeks |
| 4. Async iterator suspension and cleanup | Await, async enumeration/disposal protocols, awaiter spilling, MoveNextAsync completion/fault/cancellation contracts, awaited cleanup, and custom awaiters. | 3–5 weeks |
| 5. Generics, members, captures, and debug info | Generic/instance ownership and constraints, nested local functions and per-iteration captures, source maps and sequence points, deterministic generated identity. | 2–3 weeks |
| 6. Parity, removal, and ratchet | Run the full iterator census and focused ILVerify matrix, delete the old iterator body scanner/emitter and declines, update audit assertions and docs. | 1–2 weeks |

Overall estimate: **12–20 engineer-weeks**. Protected-region resume and async disposal are the highest-risk work; the estimate should be revised after the PoC exposes the exact synthetic-body and storage-binding interfaces.

## End-state deletion

The old body owner is removed, not retained as an alternate backend. At completion, delete the iterator-specific source-body classification and emission from `ColumnarIteratorPlanner.nl`: its restricted `WalkStatement`/expression classifier, `ColumnarMoveNextEmit`, `ColumnarIteratorBodyPlanner.EmitStatement` and `AppendValue` branches, iterator-only lambda/event body emission, and the body-building methods for `MoveNext`/`MoveNextCore`. Remove any iterator-only fallback and shape decline which exists solely because that subset emitter cannot handle ordinary syntax. Remove planner/realization tests whose purpose is to pin the old subset as product behavior; replace them with state-machine-lowering and ordinary-body-path contracts.

Keep only iterator-specific lowering and CLR contract facts that remain necessary: suspension-point analysis, state-machine field/method descriptions, generated iterator interfaces and factories, and the state/disposal transition data. `ColumnarIteratorRealization.nl` should shrink to declaring the machine surface and submitting its rewritten ordinary method inputs; it must not contain another statement or expression emitter. The ordinary method-body emitter is the only production owner of rewritten source statements and expressions.

No C# implementation or adapter is introduced. Any temporary bridge is N#-owned, tested as a transition boundary, and deleted as the state-machine lowering routes directly to the production method-body owner.

## Reference implementation

The upstream Roslyn AsyncRewriter derives from a shared StateMachineRewriter and delegates the rewritten MoveNext body to AsyncMethodToStateMachineRewriter. Roslyn's async-stream design describes async iterators as extending that lowering for yields, protected-region cleanup, and the iterator promise surface. These are architectural references only; N# keeps its own columnar inputs, semantic facts, and CLR contracts:

- [Roslyn AsyncRewriter.cs](https://github.com/dotnet/roslyn/blob/main/src/Compilers/CSharp/Portable/Lowering/AsyncRewriter/AsyncRewriter.cs)
- [Roslyn async streams design](https://github.com/dotnet/roslyn/blob/main/docs/features/async-streams.md)
