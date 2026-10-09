# Known Limitations

This is the current limitations register. Claims below reflect the source and merge-readiness
evidence at `b30cbefac` (2026-10-09); dated performance snapshots and resolved defects belong in
their historical records, not here.

## Before merging to `main`

- The Language Server reference-resolution fix for ASP.NET extension members is on
  `fix/lsp-aspnet-extension-members` and still needs its VS Code-enabled gate.
- A real-editor visual pass, including end-to-end rename, is still owed. Earlier editor screenshots
  predate this tip and do not establish current behavior.
- The example corpus still needs an NL103 re-census. Until that is done, do not claim every example
  builds with the current backend.

The non-VS gate at `b30cbefac` passed with 155 native projects and 5,392 tests, 0 failed and 1
skipped. That result does not cover the outstanding Language Server gate or visual editor pass.

## Compiler self-hosting

The current `nlc check` front door reports zero diagnostics for all eleven checked projects. Claims
that `nlc build`/`nlc check` cannot analyze the compiler, along with the September 2026 diagnostic
counts and throughput measurements, are obsolete and have been removed from this current register.
Use fresh benchmark output for performance claims.

## Publish

- `nlc publish` produces framework-dependent output. `--self-contained` is not implemented.
- `--runtime` supports only the current host runtime; cross-runtime publish requests are refused.
- `nlc publish --aot` checks NativeAOT safety but does not emit a native image.

## Compiler roadmap

Full-compiler NativeAOT remains planned after the merge. The compiler's emission path still needs to
move away from live runtime types before that work is complete.
