# Prompt: Evidence, Launch Claims, And Demo Surface

Last updated: 2026-05-25

Copy this into a fresh agent/dev session.

```text
You are working in the N# repository. Your goal is to replace vague launch/tooling claims with current evidence and decide the demo/playground surface.

Read `tasks/CURRENT.md` first. Focus on these current issues:
- 27. Build benchmark corpus and results workflow around `nlc bench`
- 28. Build a public website playground if still part of launch strategy
- 32. Add built-in build timing evidence or avoid timing claims
- 34. Remove stale launch and maturity claims

Expected approach:
1. Audit current benchmark command support, docs, website, README, memory docs, talk materials, and launch/evidence docs.
2. Build a small benchmark corpus around existing `nlc bench`; do not create another benchmark runner unless the existing command cannot support the needed evidence.
3. Decide whether public website playground is in scope. If it is, reuse current tutorial/compiler infrastructure where practical; if it is not, explicitly document deferral.
4. Either add reliable timing evidence or remove/soften timing claims.
5. Remove static test counts and production/launch maturity claims unless tied to fresh artifacts.

Acceptance:
- Benchmark docs cite actual artifacts/results, not targets.
- Timing/performance claims are either supported by current measurements or removed.
- Public playground scope is decided and reflected in tasks/docs.
- Docs build passes and public-facing claims match current evidence.

Verification:
- Add benchmark/test scripts and docs tests where practical.
- Run docs/website build if docs or website change.
- Run focused tests during development.
- Run `./scripts/test-all.sh` before committing if code changes.
```
