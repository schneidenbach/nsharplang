# 001 — External static fields and properties

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

Execute exactly one vertical ownership slice. Do not stop at planning, scaffolding, prerequisites,
parity results, or a progress summary.

- Add no C# source, tests, helpers, bridges, callbacks, whitelists, or fallback logic.
- Existing C# may only shrink, route mechanically to N#, or be deleted.
- Implement all new behavior and canonical tests in N#.
- Before editing, identify the exact C# methods, branches, and assertions this slice will delete.
- N# must become the direct production owner. Leave no legacy fallback, shadow implementation,
  comparison route, or duplicated semantic authority for the migrated behavior.
- Tests migrate with the behavior; do not defer them to a later test-refactor task.
- If an N# or interop prerequisite is missing, implement it in N# and continue through production
  routing and C# deletion in this task. A prerequisite commit is not completion.
- If substantial N# code accumulates without a named C# deletion, recut the work inside this task
  and finish the smaller terminal slice. Do not commit an unused foundation.
- Follow `AGENTS.md`: use focused `./scripts/dev.sh` evidence, run the required integration or IDE
  gates, commit with an `Evidence:` block, update the queue ledger, perform any required clean SDK
  repin, stage selectively, and leave the working tree clean.
- Report only after the slice is complete. Include the commit, exact C# deletion, N# production and
  test delta, and gate evidence.

## Slice

Finish the current dirty external-static-field/property ownership work without landing a
feature-specific mini-analyzer.

All external static field/property forms currently accepted by the C# emitter must become
canonically N#-owned from source scope through assembly/type resolution, member selection, plan
construction, validation, and execution.

Audit the existing uncommitted additions. `ColumnarExternalBindingScopeFacts` must not remain a
second feature-specific semantic authority beside `Analyzer.cs`. Reuse existing columnar facts or
generalize the work into canonical binding facts that subsequent member and call slices consume.
Remove duplicated scanning and repetitive tests where possible; do not preserve code merely
because it has already been written.

Delete the corresponding C# emission, preflight, reflection, preload, and reference-path policy.
Prove common assemblies, explicit references, ref/lib pairs, reference-only metadata, relative DLL
paths, import ordering, source shadowing, nested types, primary parameters, inheritance, ambiguity,
invalid inputs, and persisted execution through native N# tests and product-route fixtures.

Close the currently known semantic gaps before commit:

- match the real file resolver's `.nl` suffix and project-relative base-directory behavior;
- resolve both short and fully qualified owners, including `System.Reflection.Emit.OpCodes`;
- handle external first bases/interfaces and ordered namespace-import base lookup without globally
  invalidating otherwise valid class scope;
- preserve declaration accessibility and package-versus-namespace precedence in exported facts;
- distinguish a global source name from ambiguous or unrelated namespaced declarations; and
- prove that base primary-constructor parameters are not inherited into derived lexical scope.

Add real product fixtures at `tests/fixtures/external-static-package/` and
`tests/fixtures/external-static-relative-dll/`. Cover a package with matching `ref/net10.0` and
`lib/net10.0` assets, an MSBuild/reference-only route, YamlDotNet static access, and a relative DLL
reference while the process runs outside the fixture directory.

Because package/reference configuration changed, run the required fresh non-VS-Code product gate.
Commit, clean-repin, update `tasks/README.md` and `systems-language-closeout/STATUS.md`, and leave a
clean tree.
