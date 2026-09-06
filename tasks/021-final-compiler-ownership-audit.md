# 021 — Final compiler ownership audit

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

This task verifies and closes already-migrated ownership. Do not use it to hide unfinished product
work, waive a failed gate, or classify policy as glue.

- Add no C# source, tests, helpers, bridges, callbacks, whitelists, or fallback logic.
- Delete zero-consumer legacy owners and superseded assertions.
- Every surviving non-N# file must be pre-existing, non-growing, mechanical, and explicitly
  reviewed against a canonical N# owner.
- Follow every final backend, product, IDE, visual-verification, documentation, selective-staging,
  `Evidence:` commit, repin, and clean-tree rule in `AGENTS.md`.
- Report only after every terminal condition below is green.

## Slice

Close `NSharpLang.Compiler` ownership.

Audit every tracked source file in `NSharpLang.Compiler` and verify that parser, syntax diagnostics,
AST, semantic analysis, systems policy, binding, lowering, IL generation,
compiler reference/metadata resolution and canonical compiler tests each have exactly one N#
production owner.

Delete every zero-consumer legacy C# owner and superseded C# assertion. Classify only genuine
pre-existing mechanical ecosystem boundaries, proving that none contains product decisions and
none grew during the closeout.

Run the complete canonical compiler estate, compiler tests and required integration checks under
AGENTS.md, including examples, templates, interop, ILVerify and the ownership audit. Use a fresh
backend product gate for backend-only work; retain the VS Code-enabled gate, extension reinstall
and visual verification for IDE-affecting changes. Repin only when required by a verified seed change.
Update present-tense architecture documentation and the queue ledger. Leave
a clean committed tree with no partial compiler stages.
