# S2.2(l): assembly entry-point selection and wrapper realization

Execute after S2.2(k) is accepted. Revalidate the current source and seed before editing. This plan
is source-reviewed; it is not an implementation or capability verdict. Tasks 015/021/022/023 stay open.

The first exact-source probe found an array-element admission prerequisite for the
`Dictionary<string, Type>[]` input. Complete and publish
[S2.2(l0)](2026-09-06-s22l0-catalog-reference-array-prerequisite.md) before resuming this owner.
The draft remains parked; the complete C# block is still the production owner.

## Connected cut

Move the complete entry-point selection/wrapper block from `ColumnarIlEmitter.TryEmitColumnarAssembly`
into N#. At the k source it is lines 4358–4413, 56 lines including the trailing blank; its exact bytes
hash to `38d9aa91f4dce00c83bb7ea89b4b1c1421ddd2e9ad7b0b794a3d315378fc799d`. This is gross scope;
measure net C# deletion after the mechanical forwarding boundary. Pair it with the one awaiter-local
`AddType` in `ColumnarAsyncEntryPointPlanner.BuildWrapperPlan`, consuming the caller's exact catalog
structural table. Existing N# body/return policy remains the owner. Add no C# behavior or callback.

## Ordering and identity constraints

- Preserve `isExecutable == false` without selection or wrapper reads. The assembly output starts
  at actual `Array.Empty<byte>()`; only the local entry-point method starts null. Async parameters
  cause bare `false` after assigning the selected method. Do not add a decline trace or invent an
  extracted helper contract that clears the method on every failure.
- Preserve both indexed walks and ordinal `String.Equals`: lowercase `main` has priority over
  uppercase `Main`, even when uppercase occurs first. `funcs.Count` is read before `mainIndex < 0`
  in every condition, including after a hit and at the second loop's first condition. Null names
  retain the existing comparison behavior.
- The static fallback uses the original local `Dictionary<string, ColumnarStructDef>.Values`,
  including its aliases, order and concrete value enumerator. Do not substitute semantic-registry
  values, snapshot it or acquire it before the fallback is reached. Only static `Main` qualifies;
  retain count == 1 and the two separate `mains[0]` reads. A first matching null Builder still breaks
  before the later no-entry-point refusal.
- Preserve selected method → wrapped-return read → parameter-map Count refusal → inner-return read
  → WrapperReturnType → shared Type.EmptyTypes read → DefineMethod. Complete BuildWrapperPlan before
  wrapper.GetILGenerator, then
  execute, and assign the wrapper as entry point only after successful execution. Later CreateType,
  metadata generation and save stay outside the moved owner.
- Pass the existing catalog's `StructuralTypeReferences` lazily. Select and consume the awaiter at
  the old AddType site, after the original null guards, GetAwaiter/GetResult, WrapperReturnType,
  PrepareMethodBody and AddMethodWithSignature. Nonasync paths must not create type rows. Test actual
  selected-key/companion mismatch; a different fresh table does not necessarily reject every runtime
  type. Do not broaden async return families or establish another type universe.

## Acceptance

Use the existing seed to prove the exact source forms before extraction. Extend the existing async
entry-point controls with actual selection, partial wrapper progress and reached-table witnesses:
main/Main priority; first static hit; actual empty-array output on bare false; declaration before
later plan failure; plan before GetIL; consumed keyed pair and a measured mismatch; existing executed
Task/ValueTask wrappers. Preserve actual failed artifacts if a capability prerequisite appears.

Rederive the emitter/AddType census, compare the accepted fixed 94-image corpus and native execution,
map strict diagnostics, update the observed ratchet and commit focused-green source. Run the fresh
integration gate required by the actual scope; IDE-affecting prerequisites require VS Code tests,
extension reload and visual verification. Accept this connected cut before selecting further
call/type/local/maxstack work, S2.3–S2.6, NativeAOT and final ownership closeout.
