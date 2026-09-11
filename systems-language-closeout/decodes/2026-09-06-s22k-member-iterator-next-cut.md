# S2.2(k): member-iterator discovery and admission

Completed at `137462ab1cf3898087304f6c4f524b4ea69bf478`; see the
[acceptance proof](2026-09-06-s22k-parity-proof.md). The necessary analyzer correction changed the
final verification scope to VS Code-enabled plus visual checks. The plan below records the original
cut; the active cursor is now [S2.2(l)](2026-09-06-s22l-entrypoint-next-cut.md).

Source pin: `4b5399140ffd9babff214790af63e036bd1fbb49`, after accepted j. The complete
`TryEmitMemberIterator` declaration is 70 lines at 2546–2615, exactly equal to c5 lines 2794–2863.
The earlier 69-line estimate omitted its closing brace. This is gross scope, not promised net deletion.
One production call remains in the enclosing-member body walk. Source hashes and the exact declaration
are retained in `/private/tmp/nsharp-023-s22j-proof-20260906/next-candidate-source.json` and
`next-member-owner-before.txt`; the reviewed source is unchanged through the gate revision.

Move this entire 10-argument discovery/admission driver into the accepted `ColumnarIteratorRealization`
owner and retain only the existing ambient-decline host forward. The N# entry must call the accepted
sync realization directly. No callback, raw-IL fallback, source-admission widening or new AddType site
is part of this cut. Existing j1 capabilities suffice only where measured; isolate any real new
compiler gap as a prerequisite instead of adding C# or changing the contract.

Preserve these evaluation boundaries:

- Build the builder-name/member-name label first. Async member rejection precedes static dispatch and
  generic checks. Static dispatch increments the supplied ordinal before GetILGenerator and uses the
  existing empty Type array and label.
- A non-null enclosing generic map, including an empty map, or method type parameters rejects the
  instance path before input discovery. The first exact DeclaredTypeName or ordinal dot-suffix input
  wins. Preserve existing enumeration, including disposal on first-hit break and exceptions.
- In input order, admit nonempty PascalCase fields that have exact retained handles, then read their
  parallel canonical entry. Preserve short-circuit reads and natural failures. Method admission keeps
  repeated Name reads, PascalCase/non-static checks, exact handle lookup and rejection only when an
  existing overload list has Count greater than 1. Preserve that walk's disposal too.
- AnalyzeShape receives the original admitted arrays/input.Name and increments the ordinal at its old
  argument evaluation. A declined shape precedes GetILGenerator. A supported instance still calls
  sync realization with ordinal 0, precomputed shape, original enclosing builder and actual handles.
  Do not silently repair this established ordinal convention during ownership transfer.
- Retain exact declaration/field/member/factory behavior inside j's accepted owner and unchanged
  source-file/decline scope. Do not prevalidate, cache repeated reads, snapshot input collections or
  replace observable enumeration with indexing.

Use explicit typed enumerator/try-finally patterns already proved by g where the N# bare-loop form
would change disposal. ColumnarInputs/ColumnarDefinitions already own the required input/definition
objects; production N# already uses char.IsUpper. Those source facts are not a compilation verdict.

Acceptance needs direct semantic controls for first-hit/field/method admission, empty generic-map and
async refusals, ordinal and GetILGenerator timing, and exact disposal/read behavior. Reuse existing
native static/instance iterator and decline-scope suites plus the accepted j persisted fixtures.
Commit the complete routed owner with measured C# shrink after focused nonzero evidence; then root
owns immutable parity/strict comparison, observed 381-row ratchet update and the scope-appropriate fresh integration gate.
Do not repeat accepted j0/j1 API probes or j's whole generic/async campaign. Remaining call/type/local/
maxstack work, S2.3–S2.6, unified metadata/NativeAOT and terminal ownership audit stay open.
