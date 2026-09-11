# 022/4 — resume plan (prepared read-only during the r21 hold)

Companion to `2026-09-03-editor-type-universe-decode.md`. Written during the hold on gate r21, with
no build and no test; every line is a READ or a coordinator ruling.

**Filed here, not in a scratchpad.** It was first written under a session `scratchpad/` path, which
§2.4 records as WIPED when a session ends or resumes — that is how four uncommitted slices were lost
on 2026-09-03. Prose belongs in the repository the moment it is worth keeping; the hazard that
justifies staying out of the tree is uncompilable SOURCE, not markdown.

## Order (coordinator's ruling 1): the cache-identity contract is written FIRST

The centre contract, in `EditorTypeCatalog.tests.nl`:

    test "a namespace set computed before an assembly joins is not the answer after it joins"
        assemblies := <one assembly only>            # the pre-project universe
        catalog    := new EditorTypeCatalog(assemblies)
        first  := catalog.NamespaceSuggestions("")   # computes AND caches
        assert !holds(first, <ns present only in the second assembly>)
        assemblies.Add(<second assembly>)            # LoadFromProjectConfig arrives
        second := catalog.NamespaceSuggestions("")
        assert  holds(second, <ns present only in the second assembly>)

    ... and the twin for ImportableTypes and for ResolveType-by-simple-name.

Mutation that MUST bite: remove the identity key (cache once, never invalidate) -> the second
assertion fails. If it does not bite, the contract is wrong, not the owner (3b-4b's warning).

Harness already exists and is proven spellable: `EditorTypeCatalogFacts.tests.nl:70`
`EtcSeedAssemblies(): List<Assembly>` builds a `List<Assembly>` from `Type.GetType` + `get_Assembly`.
Reuse that shape; the second assembly can be any the seed set does not reach.

Real-world trigger, for the contract's header: `DocumentManager.cs:262-270` takes `_analyzerLock` and
calls `_sharedAnalyzer.LoadFromProjectConfig(...)` ONCE per project directory, inside AnalyzeDocument
-- i.e. AFTER the window is up and completions can already have been served.

## Ruling 2: IsPublic / IsNested -- prefer outcome 2, but PIN both facts by contract

Two facts to pin against MLC types, not assert:
  (a) `GetExportedTypes()` over an MLC assembly yields only publicly reachable types;
  (b) a nested type's `FullName` carries `+` there too.
Only if (a) or (b) fails on MLC types do the two rows become necessary -> stop before the estate-side
step and report `Type::get_IsPublic` / `Type::get_IsNested`.

## Ruling 3: 4d scope in THIS worktree
RUN:  unit suite; `tests/LanguageServer*Tests.cs`; `tests/native/lsp-lifetime`.
DO NOT RUN: `scripts/test-all.sh`; any VS Code integration test (two VS Code gates on one box collide).
The §4.11 row states 4d as "gated by the coordinator's VS Code-enabled gate + visual round", not done.

## Estate impact already counted (read-only)
`EditorTypeCatalogFacts.tests.nl` = 34 blocks. FOUR are about the universe slice 4 deletes:
  :109 "the editor universe is four seed names and every one of them resolves"
  :125 "the four seed names reach THREE assemblies because List and object share the core library"
  :142 "the metadata-name spelling is the only one N# has ..."
  :223 "every force-included full name resolves inside the three-assembly seed universe"
plus the `EtcSeedAssemblies()` helper (:70). They retire or re-aim in 4c; the estate count moves by
that delta plus the new catalog contract's blocks, and the row must state both halves.
`EditorUniverseSeedTypeNames` has exactly three referents: the facts owner, that contract, and
`TypeResolver.cs`.

## Ratchet rows in play
`TypeResolver.cs` 373; `CompletionHandler.cs` 638 and `HoverHandler.cs` 149 only if the
`ImportableTypeInfo` namespace change reaches them; `DocumentManager.cs` 1,449 must NOT grow -- the
factory line belongs on `Analyzer`. Repin LAST, derived at each commit's own tree.
