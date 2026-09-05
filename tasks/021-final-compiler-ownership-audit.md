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
AST, semantic analysis, systems policy, binding, lowering, IL generation, type/reference policy,
compiler-contained tooling, native test execution, and canonical tests each have exactly one N#
production owner.

Delete every zero-consumer legacy C# owner and superseded C# assertion. Classify only genuine
pre-existing mechanical ecosystem boundaries, proving that none contains product decisions and
none grew during the closeout.

Run the complete native N# estate, all compiler tests, examples, templates, interop, ILVerify,
fresh product gate, VS Code-enabled gate, extension reinstall, visual IDE verification, ownership
audit, and clean repin. Update present-tense architecture documentation and the queue ledger. Leave
a clean committed tree with no partial compiler stages.
