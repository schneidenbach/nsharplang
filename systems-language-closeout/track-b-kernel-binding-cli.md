# Track B — residual kernel, CLI, JSON, and metadata-policy ownership

**Live status:** static kernel binding, Dogfood deletion, parity-corpus deletion, and the C# CLI
`*Kernels.cs` shim deletions are complete. Much command and JSON policy is already N#-owned.
Resume from the residual C# owners below; do not recreate or re-execute the deleted binding work.

## Mission

Finish the surfaces that the static-binding/CLI campaign left partially owned:

- make OutputFormatter a tiny compatibility host or delete it;
- remove remaining command/query/batch/daemon/reference-resolution decisions from C#;
- finish DocQuery policy/formatting/index ownership in N#;
- finish NullabilityMetadata ownership and eliminate C# callbacks into N#;
- give CLI and Analyzer metadata loading one shared N# package/version-selection policy;
- classify every survivor as mechanical external integration glue.

Track B does not own LSP handler logic (G), Analyzer semantic binding (D), native test execution
policy/estate (H), or emitter member selection (E). It supplies stable N# APIs those tracks use.

## Current proof and residue

- `27bb97773` deleted the stale parity corpus.
- `aa9ec5326` deleted dead Dogfood kernels.
- `3c963eb5d` statically bound the consolidated parser kernels and deleted
  `DogfoodKernelLoader`, the Dogfood project, delegate binding, packaging, and build plumbing.
- The CLI C# `*Kernels.cs` shims are gone; command-owner deletion and typed-kernel commits landed
  across the July 7 series.
- OutputFormatter JSON families route through `OutputFormatterJsonKernels.nl`, but
  `OutputFormatter.cs` remains substantially larger than a mechanical host and AST JSON remains
  a cross-track/schema decision.
- `DocQuery.cs` and `NullabilityMetadata.cs` remain mixed owners. Nullability still accepts a C#
  `typeOverride` callback.
- Daemon JSON serialization, sockets, process execution, file/zip/http work, metadata loading,
  and ALC use may remain mechanical hosts; routing, selection, ranking, retry, error, schema,
  and formatting policy may not.
- A recently added Analyzer package-assets/SemVer implementation overlaps existing N# resolver
  version policy. It is deletion debt, not a second canonical owner.

## Standing harness

- Capture exact text/JSON bytes before each ownership flip. Existing schema versions do not
  change during a port.
- Use focused `./scripts/dev.sh` patterns for CLI, Query, Daemon, Doc, Nullability,
  OutputFormatter, Check, and relevant consumers.
- Run real fresh-CLI process probes, including daemon round trips and batch mixed-success cases.
- Reference-resolution changes run the dynamic example/project-reference/package corpus and the
  fresh non-VS-Code product gate.
- Any stage changing hover/completion/diagnostic/display data consumed by the IDE is
  IDE-affecting and follows the full VS Code rule.
- C# flattening glue tests raw extraction; N# tests policy over flattened facts. Direct C# product
  assertions enter H's migration inventory.

## Remaining waves

### B0 — live survivor inventory

Before porting, classify every nontrivial method in:

- `CodeIntelligence/OutputFormatter.cs`;
- `CodeIntelligence/DocQuery.cs`;
- `NullabilityMetadata.cs`;
- `QueryCommand.cs`, `BatchQueryRunner.cs`, daemon client/server/protocol, remaining command
  files, `Program*.cs`, and `CompilationReferenceResolver.cs`;
- relevant Build.Tasks configuration/reference loaders.

For each method record: behavior owner, existing N# candidate, consumers, exact byte contract,
mechanical boundary if any, and deletion commit. Do not commit a narrative inventory; put the
active rows in `STATUS.md` and delete each row when its owner closes.

### B1 — OutputFormatter closeout

Move or directly call N# for every normalization, key order, null omission, enum display,
summary, error-detail, and envelope decision. C# may stream the resulting string. Preserve exact
bytes and schema version.

`nlc query ast` is not a normal parity port: it exposes the C# AST and its retirement may require
a new schema. Resolve that as a separate approved versioned contract with goldens and
compatibility policy; do not leave an undocumented deferral and do not smuggle a schema bump
into front-end deletion.

Exit: no anonymous envelope construction or JsonSerializer policy remains in OutputFormatter;
the file is deleted or a small one-line compatibility surface with no decisions.

### B2 — CLI/query/batch/daemon decision closeout

For each surviving C# host, move:

- command/method kind selection and dispatch tables;
- argument/required-input/default/retry/fallback decisions;
- query daemon-use policy and parameter planning;
- batch validation, ordering, success/error shaping, and normalization;
- daemon socket/stale/start-wait/routing/error policy;
- elapsed/test/result/status formatting and all output schemas.

C# may parse/serialize wire JSON, read/write sockets, spawn processes, watch files, enumerate
directories, or perform atomic/zip/http IO. It receives an N# decision/plan and executes it.
Delete replaced bodies in the same commit and reuse one JSON writer/contract—never add a local
escaper.

Because daemon and query results feed IDE clients, apply the IDE gate whenever a changed route is
reachable from the Language Server/extension.

### B3 — DocQuery closeout

N# owns lookup normalization, type/member resolution policy, overload selection, index ordering,
doc-id construction, XML text/see formatting, reference-pack ordering, and result shaping.

C# may remain at one documented choke point for dynamic `Assembly.Load`, reflection enumeration,
or XDocument flattening only when the pinned compiler cannot call that API. Such a host returns
raw facts and has no case, scoring, ordering, or text policy. Record the NativeAOT metadata-reader
reevaluation trigger.

Expand direct and process-level oracles before deletion: qualified/simple/generic/nested types,
overloads, properties/events, cref/langword/href summaries, missing docs, reference-pack order,
and batch doc queries. Preserve case-sensitivity contracts exactly.

### B4 — NullabilityMetadata closeout

Port the remaining NullabilityInfo/reflection conversion, flow-attribute interpretation, and
display decisions into N#. If `NullabilityInfoContext` itself is unavailable, C# may flatten raw
read-state/attribute facts only.

Replace `Func<Type, TypeInfo>` callbacks with an explicit pre-resolved override table keyed by
canonical TypeId/CLR type identity. The Analyzer builds or requests raw binding facts; the N#
kernel decides where overrides apply. Cover nested mixed-nullability generics, byref/out/params,
nullable values, generic parameters, MaybeNull/NotNull/NotNullWhen, and IDE display strings.

Exit: `NullabilityMetadata.cs` deleted or a bounded fact extractor with no callback, recursion,
formatting, or carrier decision.

### B5 — one package/version policy

Unify CLI reference resolution, Analyzer metadata loading, and Build.Tasks projection on N#
models for:

- SemVer/package version parsing and ordering, including prerelease behavior;
- dependency-group and asset selection;
- shared-framework/root/candidate ordering;
- implicit test/runtime dependency policy;
- output/default/project-reference classification and projection.

C# may read JSON/XML/files, instantiate MetadataLoadContext, download/extract packages, and
materialize `ITaskItem`s. It passes raw facts to N# and executes the chosen plan. Delete the
duplicate Analyzer SemVer/package policy rather than reconciling two owners indefinitely.

This is a broad shared integration point: run focused resolver/analyzer/SDK suites, real NuGet and
project-reference probes, then a fresh non-VS-Code product gate.

### B6 — survivor and gate audit

Grep all B surfaces for delegate/callback crossings, anonymous JSON shaping, command switches,
version comparisons, and duplicated error/text policy. Delete or classify every hit. Update
memory docs to name the N# owner and the single metadata-loading choke points. Run the applicable
IDE evidence for changed display/query routes and a fresh product gate for the integrated state.

## Cross-track contracts

- D consumes the shared TypeId/nullability/package APIs and deletes Analyzer-side duplicates.
- E owns compiler/emitter BCL member selection. B must not add emitter whitelists.
- G consumes OutputFormatter/query/type-display APIs but owns protocol/IDE behavior.
- H migrates canonical CLI/query/runner product tests after B's bytes are pinned; B does not
  delete a C# oracle until its named successor executes in the gate.
- SDK repins and shared installed state are announced; use clean `/tmp` worktrees for gates when
  the main checkout is active.

## Prohibitions

- No Dogfood project, loader, reflection delegate binding, global `Program` ABI, or deleted shim
  recreation.
- No C# delegate/callback passed into an N# kernel.
- No second JSON/HTML/XML escaper or schema owner.
- No command/message/schema improvement during an ownership port.
- No C# scoring/filtering hidden inside “flattening” glue.
- No duplication of package/version policy between CLI, Analyzer, and Build.Tasks.
- No dynamic-assembly/AOT redesign in this track beyond documenting the single choke point and
  reevaluation trigger.

## Exit criteria

- [ ] Dogfood/static-binding completion remains intact and all deleted mechanism greps stay
      clean.
- [ ] OutputFormatter contains no formatting/schema decisions; AST query has an explicit approved
      contract.
- [ ] Remaining CLI/query/batch/daemon C# is mechanical process/socket/file/wire adaptation only.
- [ ] DocQuery policy is N#-owned; any dynamic metadata/XML host is a raw-fact choke point.
- [ ] Nullability is N#-owned with no C# callback crossing.
- [ ] CLI, Analyzer, and Build.Tasks consume one N# package/version/reference policy.
- [ ] Exact byte/process probes, focused suites, applicable IDE verification, and the fresh
      integration gate are green.
- [ ] Every survivor is in the final mechanical-glue inventory with forbidden responsibilities
      and a reevaluation trigger.
