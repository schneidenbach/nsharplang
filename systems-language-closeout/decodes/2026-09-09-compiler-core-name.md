# Compiler Core name and completed-worktree cleanup — accepted

The completed N# compiler no longer carries the transitional `BootstrapServices` project or assembly
name. Production, SDK loading, native canonical tests and editor packaging now use
`NSharpLang.Compiler.Core`. Namespaces and compiler semantics are unchanged; no C# behavior,
compatibility alias, fallback or additional package was introduced. `CompilerBootstrapServices.nl`
is now `CompilerServices.nl`. Historical acceptance records retain their original paths and names.

- Implementation: Sol Max `391ed8b3948ee3d69059eeae65d2293c21dfbdd0`, integrated by Astra as
  `b3a954257`; reviewed by a second Sol Max agent. Of911 changed paths,811 are byte-identical moves.
- Integration source: `b22bafc155e73c68ee9fae4cc5346e4cfee6a2db`, pushed to `systems-language`.
- All381 ownership epoch ceilings/classifications are unchanged. Two logical paths moved;13 current
  row fingerprints/path facts and the corresponding aggregate fingerprints were recomputed.
  Current head `head-v1:0d1db3eb1998be8c`; no new growth allowance.

## Verification

Focused `dev.sh` production builds, formatting,8017 canonical tests and238 native assertions passed.
Fresh `NSHARP_TEST_KEEP_RUN=1 ./scripts/test-all.sh --commit` passed711s at the integrated source:
399 integration tests,8017 N# canonicals,56 native project entries,36 VS Code smoke tests,12
throughput cells, templates/examples and68 IL assemblies. This was a fresh VS Code-enabled run.

Official `setup-local.sh --skip-vscode --no-path-update` installed SDK version
`0.1.0+b22bafc155e73c68ee9fae4cc5346e4cfee6a2db`. Exact archives agree across both feeds; all12
SDK/cache files and10 Release tool payloads match. Installed CLI/LSP and the rebuilt, reinstalled
VSIX contain Core and no old DLL/PDB/assembly identity. A clean installed-SDK self-host passed8017
tests with no overrides or NU1504. The old seed's initial NU1504 warning required no compatibility
code; the renamed SDK's existing runtime-package exclusion resolves it.

Six native families ran against112 byte-verified installed host files:47 reflection,198 columnar,78
query,4 reference-resolution,88 language-server diagnostics and12 SDK assertions. Exact test names
and zero skips are frozen. Unfiltered ILVerify passed Core1236 types/10977 methods, Compiler5/58,
and packaged Build.Tasks3/33. Real VS Code hover, string-member completion, NL202 return-type
diagnostics and diagnostic clearing after undo were visually verified; the sample is byte-restored.
The running editor process was observed loading the installed extension's Core DLL.

## Evidence and cleanup

Final receipt: `/private/tmp/nsharp-compiler-core-name-root-20260909/final-receipt.json`
SHA-256: `649210cda1112ff3bbce627cc29c63a67622cbd2b5e2b9dabd276a9ad31a02b2`.
It hashes gate, installed package/self-host/native/IL, source review and four visual screenshots.
Gate log SHA-256: `c6ac75b1d8e5680c67622538f2e2b67f0d5633c0d19b46c6f47ca0fe6201c2ee`.

The rename worktree and branch are removed; recovery bundle and receipt are under
`/Users/spencer/nsharp-worktree-archives/2026-09-09/compiler-core-name`. The installed verification
tree remains at its original evidence path as a plain snapshot, with its Git registration removed
and every tracked source hash preserved. Eight older completed verification registrations were also
retired this session. Only the main checkout and four held backlog worktrees remain registered.

The standalone `NSharpLang.Compiler` facade package already depended on an unpublished compiler
project package before the rename. Its dependency now names Core; standalone package usability is
not claimed by SDK payload acceptance. The exact existing debt and baseline evidence remain in
`tasks/BRANCH-BACKLOG.md`, alongside separately held CLI/editor/runtime/AOT/writer work.
