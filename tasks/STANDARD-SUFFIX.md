# Standard Verification, Review, and Merge Protocol

**Append this to every task. Do not skip any step.**

## Step 1: Test

Run the full test suite:
```bash
./scripts/test-all.sh
```
If ANY test fails, fix it before proceeding. Do not skip. Do not proceed with "pre-existing failures" — all tests must pass.

## Step 2: Codex Adversarial Review

Use the `codex-review-skills:codex-code-review` skill on your changes (git diff).

Read Codex's findings critically:
- If it finds a real bug → fix it
- If it's a false positive → argue back with evidence, document why you disagree
- If it raises a design concern → use `codex-review-skills:codex-review` to debate it

Do NOT just accept or ignore Codex output. Engage with it.

## Step 3: Commit and PR

```bash
git checkout -b schneidenbach/<branch-name>
git add <specific files>
git commit -m "<descriptive message>"
git push -u origin schneidenbach/<branch-name>
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<bullets>

## Test plan
- [x] All tests pass (./scripts/test-all.sh)
- [x] Codex adversarial review passed
<additional items>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

## Step 4: Merge

```bash
gh pr merge <number> --merge --admin
```

## Step 5: Deploy Latest Locally

```bash
git checkout main && git pull origin main
./scripts/setup-local.sh --skip-vscode --no-path-update
```

Verify `nlc --help` runs with the new version.
