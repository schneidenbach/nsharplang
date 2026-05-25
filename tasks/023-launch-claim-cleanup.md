# Task 023: Launch Claim Cleanup

Priority: P2.

Remove stale launch-readiness, maturity, and static evidence claims from docs and memory files. This task protects product credibility.

## User Outcome

Public docs, website docs, README, talk materials, and memory docs make claims that are true at the current source state and tied to current evidence where needed.

## Scope

- Audit README, public docs, website docs, memory docs, talk materials, launch docs, and package artifacts.
- Remove static test counts unless generated from fresh artifacts.
- Tie marketplace, debug, benchmark, production-ready, and feature-complete claims to current evidence.
- Keep planned, partial, and verified workflows clearly distinguished.

## Likely Files

- `README.md`
- `docs`
- `website/docs`
- `memory`
- `docs/talk`

## Acceptance

- Public docs, website docs, README, memory docs, and talk materials avoid static test counts unless generated from fresh artifacts.
- Marketplace, debug, benchmark, production-ready, and feature-complete claims are tied to current evidence.
- Docs build passes after claim updates.
- No launch claim depends on stale local-only evidence.

## Verification

- Run docs/website build or link checks if available.
- Run focused tests only if docs tooling or generated docs change.
- Run `./scripts/test-all.sh` before committing if code changes.
