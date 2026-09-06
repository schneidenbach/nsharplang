# Broader systems-language branch backlog

These initiatives retain their accepted work and outstanding evidence, but are separate from the
active compiler-only ownership objective in [README.md](README.md). Their historical records remain
in STATUS.md and their numbered tasks; this separation does not mark any initiative complete.

- CLI command ownership, query/daemon behavior and CLI presentation: task 019 and STATUS follow-ups.
- LSP/editor completion, hover, signature help, import acceptance and other editor features: task
  022 slice 4 and STATUS tooling chips. Keep existing IDE acceptance evidence; apply mandatory IDE
  verification whenever new compiler work actually affects IDE behavior.
- Runtime reimplementation and NativeAOT: task 022's native publishing and single-runtime-universe
  requirements remain open independently of compiler decision ownership.
- Metadata writer: task 023's second ECMA-335 executor and retirement of Reflection.Emit remain a
  branch initiative. Activate writer implementation for this objective only after demonstrating
  that compiler ownership requires it. Accepted declaration/plan migrations remain production code.
- Installer, gate infrastructure, performance follow-ups, documentation hosting, import hygiene and
  other branch chips remain in STATUS.md. Change SDK/tooling now only for compiler migration needs.

Compiler reference/metadata resolution and code generation themselves remain in the active compiler
objective, regardless of which historical task records them. Historical writer/AOT ordering cannot
force unrelated compiler ownership migrations to wait.
