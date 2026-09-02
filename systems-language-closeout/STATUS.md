# Systems-language closeout — STATUS

Ledger of the C#→N# compiler and tooling closeout (`tasks/README.md` is the queue). Compressed on
2026-09-01 at `40e0cc20e` from a 75,634-line / 6.4 MB per-slice proof archive into a file future work can
read. Nothing was lost: the full pre-compression text is in git history —

```bash
git show 40e0cc20e:systems-language-closeout/STATUS.md
```

— and every slice's proof summary is in its commit message (`git log --format=%B <hash>`).

## 0. How to read and maintain this file

- **§1 Cursor** is the only operative section: where the work is, what the next slice is, the baselines a slice
  must re-measure, the verification bar, the harness state, and the two procedures (toolset republish, ratchet
  repin). Read it first; keep it current **in place**.
- **§2 Walls and gotchas** is the deduplicated, categorised list harvested from every slice. Check it before
  writing `.nl`, before running the estate, and before trusting an instrument.
- **§3 Architecture facts** are the structural findings future engineers must know that the code does not say.
- **§4 Arc records** hold one table row per slice per task (001–021), newest first within an arc, plus the
  arc's durable findings. **§5** holds remediations and corrections.
- **Recording discipline (binding for every future slice):**
  1. Do not prepend a "Last updated" paragraph. Update §1 in place (tip, active slice, next brief, baselines).
  2. Append ONE row to the arc's table in §4 (`| slice | commit | what moved | durable finding | numbers |`)
     and at most ~10 finding bullets under the arc. A slice record is ≤ ~60 lines total.
  3. A new wall or lesson goes to §2 under its category, one line, deduplicated against what is there.
  4. Proof narratives (control walks, probe tables, corpus md5s, gate timings) go in the commit message and the
     slice's scratch tree, not here. Here you write the verdict and the headline numbers.
  5. Never replace this file wholesale. `tasks/README.md` is touched only by a measured box-checking slice.

## 1. Cursor

**Tip:** `26592a954` on `systems-language` (PR #190 against `main`; gated at `a1440ec95` — VS Code-ENABLED `./scripts/test-all.sh --commit`, 131 steps, `GATE EXIT 0`, 6 m 35 s; a first run at `26592a954` failed on two merge fix-ups, see Active slices).

### Queue state (`tasks/README.md`)

| task | state |
|---|---|
| 001–014 | accepted, boxes checked (acceptance commits in §4) |
| 015 | **box UNCHECKED — reopened at `6fcb41f64`**; the `015-A` arc closed at `87afbcb39`; the `015-B` arc (method-body door) is in progress, B1–B15 landed, B16 active |
| 016 | complete — `Parser.cs` deleted; box checked; one optional bookkeeping follow-on (see §4) |
| 017 | complete — zero-policy analyzer; box checked |
| 018 | complete — systems-analyzer policy N#-owned; box checked |
| 019 | complete — `DocQuery.cs` deleted at `dc2c4ae20`; box checked |
| 020 | complete at `530bfbc85` (45 slices); box checked |
| 021 | audit complete at `6fcb41f64` (12 slices); **box deliberately unchecked** — the emitter retires via 015-E on Reflection.Emit (the `MetadataBuilder` writer is shelved), the external type universe via task 022; visual IDE verification discharged 2026-09-02 (D1–D3 fixed, D4 open) |
| 022 | filed `0d472bdd4`; slice 1 (the AOT capability floor, measurement only) in progress on `stream/022-s1-aot-floor` — §4.11 |

### Visual IDE verification — DISCHARGED 2026-09-02 (D1–D3 FIXED and merged; D4 open; re-verification in progress)

Verified against `d26460045` with VSIX 0.6.0 (sha256 `853abbfc…8568`, LanguageServer.dll 10:58) in VS Code 1.134 on
`examples/12-multi-file-projects/WeatherDemo` and a systems probe; record, 21 screenshots, the `nlc --systems-report`
comparison and the language-server log are at `artifacts/ide-verification/2026-09/README.md` (branch
`verify/ide-2026-09`, commit `94884528f`, merged). Computer-use was user-approved on 2026-09-02; VS Code is click-tier
(no typing), so nothing was verified by keystroke workaround. **PASS**: syntax highlighting; live NL202 with the
full-sentence headline and Elm body, squiggle exactly on the offending token, cleared on revert (the four-arg Analyze
fix, in the editor); the parser cast-lookahead fix (`print(x)` then `sum := 0` — no false NL101/NL301/NL001, `sum` hovers
as a local int); hover on user functions and record members; go-to-definition and find-references across files;
the NL002 auto-import quick fix offered and applied; NSYS010/NSYS050/NL001 identical to `nlc check --systems-report`.
**BLOCKED (tier)**: rename — the widget opens with the right placeholder but cannot be typed into or confirmed.
**FAIL — four IDE defects, each with a VS Code-free repro in the README, filed as wave-3 chips. Three are FIXED (§4.10
rows); the visual re-verification of D3 at `385b7e8d1` and of D1/D2 at `26592a954` is the IDE-verify session's
(branch `verify/ide-2026-09-02b`; it holds on a computer-use screen-takeover consent the user must approve):**
- **D3 — FIXED, merged `87ec6b9d1`.** Member completion after a trailing `.` listed scope identifiers + keywords because
  `CompletionHandler` was the only handler with no project route; it now routes to the same N# owners
  `nlc query completions` uses, with an in-process comparator asserting the two answers are equal.
- **D2 — FIXED, merged `26592a954` (`87400ec24`).** Three causes, three N# owners, zero new C#: `AstNodeFinderCore` had
  arms for 9 of 42 expression kinds (`new Foo { A: x.Y() }` and `$"{x.Y}"` were leaves); `MemberTypeInfoOfType` had no
  reflected-member arm (`MemberInfo` is not a columnar surface — `ReflectedMemberHandle` carries the three sorts); the
  renderer was bare. Generic members are read off the DEFINITION and mapped back through `AnalyzerReflectionTypeOverride`
  because `CompletionReflectionFacts` substitutes `object` for every N# user type. `HoverHandler.cs` 307 → 149.
  `nlc query type` moved with it (a BCL member position answers the member, not the receiver) and no pin moved.
- **D1 — FIXED by D2's `InterpolatedStringExpression` arm** (`{forecast.TemperatureC}` now `int`).
- **D4: NL002 is anchored on `new`**, so the import quick fix is offered only with the cursor on `new`, not on the type. OPEN.

### Active slices (2026-09-02)

- `stream/format-rawstring-reparse` — the formatter's data-loss family: attributes re-rendered (`[trusted(reason: …)]`
  became `[trusted(reason = …)]` on one line and `[aotSafe(mono-wasm)]` became `[aotSafe(mono - wasm)]` — the estate
  reformat did this to two proof programs and the batch gate caught it through `systems-proof-corpus` 42/44; the two
  files are restored and the fix is "attributes are emitted verbatim from their source span"), raw strings losing
  `"""`, `let` unspellable, digit separators dropped; plus the parser refusing `return """abc"""` (NL305/NL312/NL006 on
  correct source), `EndLine` under-reported for multi-line raw literals, the `AllocExpression` arm and `--check`
  reporting. Terminal condition: root `nlc format --check --project .` exits 0 with zero declines (was 23). Six commits.
  LESSON for any wide reformat: test-run identity plus `nlc check --json` identity did NOT cover
  `docs/design/systems-samples/proofs/**` semantics — run `tests/native/systems-proof-corpus` too.
- `stream/022-s1-aot-floor` — task 022 slice 1, measurement only (§4.11); probe outside the repo; decode file
  `decodes/2026-09-02-aot-capability-floor-decode.md`.
- IDE re-verification (peer session, `verify/ide-2026-09-02b`): D3 at `385b7e8d1`, then D1/D2 at `26592a954`.

### `015-B16` — door kind 7 (Parenthesized) and door kind 55 (`typeof`) — LANDED (record; numbers in §4.1)

Decode tip `8cf40128a`; ZERO C#. Four files: `ColumnarMethodBodyPlanner.nl`, `ColumnarTypeOfPlanner.nl`,
`ColumnarMethodBodyFacts.tests.nl`, `columnar-emit-facts/DeclarationAndLiteralEmitFacts.tests.nl`. Every
proof in the bar ran green; the numbers are in §4.1 and the coordinator commits.

- **The brief's kind-7 basis is OVERTURNED, and the code says so.** `FacadeRootMayNeedFacts` and ALL EIGHT
  cascade owners' `MayPlanRoot` open with `UnwrapParentheses` — TEN copies of that helper exist, one per
  owner — so for nine inner kinds the host never reaches `case 7`: the OWNER claims the OUTER node. Every
  owner's `TryAppendRoot` unwraps too, so ONE child recursion reproduces BOTH host routes.
- **CORRECTION 1 — the pin count is EIGHT, not seven.** The source-text census found seven; the eighth was
  the ledger block's `assert claimed == 13`, a COUNT assertion no textual census can see.
- **CORRECTION 2 — the estate baseline at this tip is 7,192, not the inherited 7,190.** `577d756ad` (the
  raw-interpolation removal) landed between B15's `40e0cc20e` and this tip and carries +2.
- **CORRECTION 3 — the kind-7 arm WIDENS NOTHING; it inherits the child's claim class exactly.** Predicted
  25 probe movers, measured 24: `return (!flag)` does NOT move, because the door's kind-11 arm claims only
  a unary over a LITERAL. The door was right and the prediction was wrong.
- **CORRECTION 4 — the child-count guard is LOAD-BEARING.** Removing it is not an equivalent mutant: it
  gives UNBOUNDED `TryAppendValue` recursion and a test-host STACK OVERFLOW, isolated to one block.
- The hazard held in bytes on BOTH CLIs: `return -5` is `1f fb 2a` (adopted, pre-negated) and `return (-5)`
  is `1b 65 2a`. `IsHostAdoptedReturnShape` must NOT unwrap — control C3 proves it by breaking that pin.
- `return (null)` fails to compile on BOTH CLIs, identically: the kind-5 refusal stands.
- Kind 55 is the cascade's FIFTH and ONLY UNCONDITIONAL arm, so a door decline can only narrow the BODY.

### Next briefs (in order)

1. **B17 — the composed instance-member receiver (`o.Inner.V`).** It moves the EIGHTH cascade arm,
   the one where the cascade sets `nsharpOwned = ClaimsRoot(...)` BEFORE `TryEmit` and a set-but-failed claim
   declines the whole function; type and append sides must move together. The three plain-surface sites in
   `ColumnarDirectCallPlanner` (`:1040`/`:1208` pinned as receivers paired with a written `false`).
2. Continue the B-arc to full statement/expression coverage (C# host: 21 statement kinds / 27 expression
   kinds; N# door growing).
3. `015-D` real async lowering (retires the blocking-await model).
4. `015-E` the declaration host + the AOT metadata writer (`MetadataBuilder` as a SECOND executor over the
   same plan rows; retires `System.Reflection.Emit` in the emitter).
5. The AOT type-model task (replace the analyzer's MetadataLoadContext external type model; `MetadataReader`
   is unreachable from N# at emit). Then re-run 021's closing decision and its box.
6. Wave 3 (below): D4, then the chip-found defects; the 15 filed chips are closed.

Decided (2026-09-01/02, the owner choosing "whatever is best long-term for the language"):
- File task 022, shelve the `MetadataBuilder` writer, port 015-E on Reflection.Emit; the formatter wraps
  gofmt-style (author-preserving).
- **`MEASUREMENT-VERDICT-2026-09.md` §7 → option (b), as a RE-AIM, not an abandonment.** `ColumnarIlEmitter.cs`
  is declared a reviewed mechanical host: non-growing under the ratchet, its user-facing sentences pinned by
  native contracts, the door keeping everything it has claimed. The ownership END STATE stands; what changes is
  the route and the order. 015's next slices, in order:
  1. **Emit-path regression** — DONE `e531353f0` (8.4×: `ColumnarExternalTypeCatalog.TryGet` built and disposed a full
     `ExternalAssemblyScan` per cache miss, 2,952 per emit; it now retains Prepare's scan). Shipped in the 0.1.0 SDK
     packed from `385b7e8d1`.
  2. **Self-hosting**: make `nlc build` and `nlc check` pass on the compiler's own sources (the 45 strict-lint
     findings, then the 198 MLC-type-model analysis errors), so the gate covers emit and the by-name SDK
     exception dies.
  3. **The native-kernel June gap**: measure the columnar port's emitted IL around the vectorizer helpers and its
     scalar codegen against the ILCompiler's.
  4. **Task 022** slice 1 onward — IN PROGRESS (`stream/022-s1-aot-floor`; §4.11).
  5. **An incremental skip in the SDK build** — DONE (`Sdk.targets` stamp-keyed `Inputs`/`Outputs` on `EmitNSharpIlAssembly`;
     no-op product build 0.93 s through the shipped SDK; the commit gate 28 m 44 s → ~15 min).
  6. Ownership resumes by the faster route: **015-E on Reflection.Emit** (the ~2,000-line declaration host), then
     the B-arc's remaining door kinds as coverage — B17 (the composed receiver) is parked behind items 1–5.
  021's closing contract refused a documented C# exception; the owner's decision supersedes that refusal for the
  emitter, and 021's box is re-decided by a measured slice once items 1–2 land.

### Baselines at `26592a954` (re-measure at your tip; never inherit)

| measure | value |
|---|---|
| unit suite (`tests/Tests.csproj`) | 595 (596 − 2 collapsed Range duplicates + 1 new, D2) |
| BootstrapServices estate (`.tests.nl` blocks) | 7,320 (7,305 at `385b7e8d1`; the widening's deleted snapshot contracts −3; D2 +15; +3 elsewhere in the batch) |
| native projects / `columnar-emit-facts` blocks | 47 / 38 |
| live-tree `nlc check --project src/NSharpLang.Compiler.BootstrapServices --json` | 403 files / 243 results (NL402 65, a pre-existing false-positive family) |
| `ColumnarIlEmitter.cs` | 20,784 lines / 19,768 non-blank |
| compiler C# files (`src/NSharpLang.Compiler`, excl. obj/bin) | 10 |
| growth-ratchet head (BOTH keys: manifest header AND `OwnershipAudit.nl`) | `head-v1:819d6f5c4ed70cb7` (the union of the widening's `ff22308bc20ee46a` and D2's `3764b579fdba8a1f`, audit-observed) |
| ratchet epoch triple (immutable) | 381 / `pathset-v1:8a26e1529863444b` / `epochfacts-v1:1b3090747e517fc1` |
| ratchet manifest | 391 lines, no BOM |
| corpus IL harness | 68 projects / 64 built / 3,669 rows / 3,590 keys / door-marker floor 461 keys (B16 re-measure: mirrored paths + a tip-built dep snapshot; the 4 misses are 2 pre-existing NL402 template declines and 2 needing a Playground dll) |
| packaged SDK 0.1.0 in both feeds | packed from `385b7e8d1` (Sdk nupkg md5 `e55c25e1…`), carrying the incremental-emit stamp and the retained external-type scan; **measured through the shipped package on a loaded box: the compiler's own product build 29.6 s wall (was 133–160 s), no-op rebuild 0.93 s (was 132.8 s), tests-included build 46.0 s (was 273–307 s); estate restore+emit+test 76 s, 7,305/7,305** |
| gate | `./scripts/test-all.sh --commit` VS Code-ENABLED (auto) → 131 steps, `GATE EXIT 0`, **6 m 35 s** at `a1440ec95` (28 m 44 s skip-VS-Code at wave-3 start; the incremental emit + emit-path fix did it). Steps 3c/allocation stay load-sensitive |

### The verification bar (every B-arc slice; the accumulated standard)

1. **Decode first, in this file, before any production edit.** Every B-slice so far has overturned or
   re-shaped its brief. Write predictions (which bodies move, by name) before running mutations.
2. **Tip bytes read before the edit:** the probe set compiled by a pristine tip CLI and again by the slice CLI;
   `IL_DIFFS=0` (MVID-free SRM body dumps); normalisers proven non-vacuous by a one-character perturbation.
3. **Corpus IL byte comparison, control-first:** ctlA vs ctlB `IL_DIFFS=0` BEFORE ctlA vs slice; KEY-based
   comparison, never raw `diff` (mis-reported by two rows at 320 changes in B12); `nlc test` for `.tests.nl`
   projects (`nlc build` silently under-measures them); the harness must not copy `bin/obj` and must not
   flatten the copy (repo-relative `dll:` deps break).
4. **Liveness:** the door-marker mutation (two markers) — claim rows and live corpus bodies, both predicted
   by name; byte identity alone cannot distinguish a claim from a decline.
5. **Control walk, pristine-bracketed:** compile-checked mutations, predictions written first, single-block
   isolations, captured-bytes restores behind sha256 with the CLI rebuilt inside each restore; an equivalent
   mutant is proven and replaced with an observable variant; a zero-test / no-`Total` run is a NON-VERDICT.
6. **Estate count-diff exact** (tip re-measured in a pristine worktree, which needs a `-c Debug` build first).
7. **Live-tree row-for-row walk** (`nlc check --json` on the same tree with both CLIs, and tip-tree vs
   slice-tree): LOAD-BEARING — it alone caught B10's three new NL011s past a green estate, a green native gate
   and `IL_DIFFS=0`. Never skip it.
8. **Ratchet:** if any C# row moves, the two-key repin is taken LAST (procedure below); otherwise confirm both
   keys unchanged.
9. **Gate:** fresh isolated `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` from a `/tmp` byte-copy that
   excludes nested `.claude/worktrees`, log OUTSIDE the copy, launched detached, `pgrep test-all-core.sh`
   empty first; NEVER signal a gate (its EXIT trap deletes the tree under the live core). Read the verdict from
   the log's `GATE EXIT` line; a log's filename is part of its identity.
10. **Agent hygiene:** progress line every few minutes (the 600 s stream watchdog kills silent waits); never
    `git add -A`; stage only your files; do not commit (the coordinator commits); this file always,
    `tasks/README.md` never.

### Harness state (inherit exactly)

- Corpus harness: fixed in B15 (no flattening); 68 / 59 / 3,463 / floor 445. Key-based comparison.
- Census regex: three blind spots fixed — `func operator ==(` (B13), conversion operators have no `func`
  keyword (B14), local functions were skipped by `i = j` (B10). `this.count` is a kind-6 identifier the door
  has claimed since B5 (the parser flattens it). Expression-bodied members are NOT claimable bodies
  (`=> a + b` declines while its block twin claims) — census them out.
- Estate runner: the `tail` fix (never pipe a walk through `tail`); restore with
  `-p:NSharpExcludeTests=false --force-evaluate` after ANY other build; exit-0-with-zero-output is a failure.
- Fragment-kind instrument: extend its owner list when a new owner lands; do not re-census.
- Tagged-CLI reachability for the four type-discovery scratch sites: S1 (B8), S2 (B10), S3 (B14) reached;
  S4 unreached as of B15.

### Toolset republish (coordinator only, at a two-stage boundary, from a COMMITTED tip)

1. `git worktree add` a clean tree at the tip; `source scripts/lib/common.sh scripts/lib/packages.sh`;
   `nsharp_pack_package_set "$STAGING" minimal`.
2. Verify `Mono.Cecil.dll` inside the Sdk nupkg; UTF-16-LE scan of the packed
   `tools/NSharpLang.Compiler.BootstrapServices.dll` for the new literals (ASCII `strings` is a false
   negative — .NET literals are UTF-16 in the `#US` heap).
3. Copy all nupkgs to BOTH feeds (`~/.nuget/local-feed` — the one actually consulted — and
   `~/.nsharp/packages`); `rm -rf ~/.nuget/packages/nsharplang.*`.
4. Estate `dotnet restore -p:NSharpExcludeTests=false --force-evaluate` + `dotnet test` with the fresh emit
   confirmed in-log; extracted dll md5 == staging dll md5.
5. A spelled probe project through the PACKAGED SDK: a bare-int control plus the previously-declining shape
   (the CALL, not a bare declaration). Probe gotchas: `import`, not `use`; interpolation call-holes decline
   (`emit.interpolation.split`) — use locals + `Console.WriteLine`.
6. Never pack feeds mid-slice; a mid-slice pack poisons the feed.

### Growth-ratchet repin (only when C# rows move; taken LAST)

`tests/native/ownership-audit/non-nsharp-growth-ratchet.v1.json` (391 lines, no BOM) + the
`ReviewedHeadFingerprint` constant in `OwnershipAudit.nl` — TWO keys, both updated. Walks are validated
pristine-first (text fingerprints count UTF-16 code units, not codepoints; the pathset is a sorted newline
join). Rows may only be removed (`0/0/0,text-v1:removed`) or exact-shrunk; the epoch triple never moves.
Audit reads 17/18 before the repin (record it) and 18/18 after. `audit --verbose` prints the values to paste.
OWN003 = a gate log inside the byte-copy; OWN009 = leftover `TestResults/.trx`.

### Product-defect chips (15 filed; state at `ef3ff87c3`, 2026-09-01)

Fixed and merged (see §5 for each decode row): four-arg `Analyze` degraded diagnostics · dead `match`
wildcard arm + missing override-virtual check (now NL311) · `LibraryImport` span marshalling (now NL405) ·
systems policy accepting unresolved members · `nlc tidy` bare-prefix deletion · false NL001 on `off` reads ·
parse failure after bare member access (the trigger was the CAST lookahead crossing a line) · documented `skip`
form failing to emit (two defects: the runner's unlocated one-sentence refusal is now NL323 at the declaration; the docs
no longer promise the form at parity) · NL309 coverage (the filed defect did not exist — the estate had no contract for the
arm; three real holes fixed: struct/record bare-name writes to their own `readonly` fields were silent, the constructor
exemption leaked into nested bodies, and a shadowing local was accused of the field's write). Fixed earlier:
raw-interpolation `:` swallow (`e6aa8c88b`). WITHDRAWN with proof: undefined type names silent at declaration
sites (every probe spelled `Missing`, a real BCL type; two smaller real holes it hid are fixed).

Format non-idempotence + the `.tests.nl` gate gap: CLOSED — the idempotence rule `24befbd97`, gofmt-style wrapping
`8707f046e`, discovery widening `35f2c1fd7`, the 286-file estate reformat `17aa99e58` (fixed point; `nlc check --json`
byte-identical over 26 projects; the reformat drops redundant `public` — the documented modifier rule).
`stream/chip-format-idempotence` and its worktree are deleted (its 233-file reformat `fd13f0d67` never merged). All
fifteen filed chips are closed: locale-sensitive estate blocks (7 defects, 4 of them product: the lint-config severity fold,
two suggestion folds, the CLI's unknown-command echo, and the emitter writing a Turkish İ into CLR method names — the estate
is identical under en-US/de-DE/tr-TR) · playground union shorthand (the runner was a third spelling of `BindingName ?? Name`,
the only wrong one — routed to `AnalyzerPropertyPatternBinding.BoundName`) · playground vs `nlc run` divergences (5 fixed;
`"n=" + 1` is a compiler gap in the primitive-binary `+` arm, filed).

**Wave 3, first slice — the gate-speed slice: DONE as measured.** The gate was emit-bound (8 N# emits per gate), not
unit-suite-bound as first planned; the stamp-keyed incremental emit in `Sdk.targets` plus the emit-path fix took the
commit gate 28 m 44 s → ~15 min. Still open from the original plan: splitting the subprocess-spawning unit tests out,
running independent gate steps in parallel (ratchet line-pinned scripts → a measured repin), and making CI carry the full
gate so no local session waits on another's.

Wave-3 DONE: the gate-speed slice (incremental emit + the emit-path regression; ~15 min gate), D3, D2, D1, the formatter
rule + wrapping + widening + reformat. IN PROGRESS: the formatter data-loss family (`stream/format-rawstring-reparse`: raw
`"""` delimiters dropped by `Lexer.ReadTripleQuoteString`, `let` unspellable, digit separators dropped by `ReadNumber`;
the parser's `CanStartExpression` missing `TripleQuoteStringLiteral` so `return """abc"""` reported NL305/NL312/NL006;
`EndLine` under-reported for multi-line raw literals; 15 `AllocExpression` formatter declines; `--check` returning before
its report on a decline). Wave-3 candidates, remaining: D4 NL002 anchor; `nlc query type` renders methods as a
`Name(...)` placeholder; hover declines XML doc summaries; call-site overload preference in hover; `"n=" + 1`
primitive-binary `+`; then those found by the chips: `unsafe`/`alloc`/`allow` block bodies unwalked by the linter (NL001
fail-open) · `TypePattern` type references untracked (false NL010) · `nlc tidy --fix` corrupts the mapping
dependency form · tidy's removal filter not scoped to a dependency section (decision) · `where` clauses on
TYPE declarations do not parse · `override` PROPERTIES unchecked · tuple-deconstruction scan crossing lines
(invalid source only) · coloured `nlc` diagnostics write the LITERAL bytes `\x1b[1;31m` instead of ESC (every colourised
line; pre-existing) · the formatter argument-list wrapping policy (decided: gofmt-style, author-preserving — build it before
the `.tests.nl` reformat).

CLOSED: **the documented `skip` form fails to emit** — the defect REPRODUCED on both halves and both are
fixed. The skip CAPABILITY stays declined (§3.7 is unchanged and must not be re-litigated): the form is now
REFUSED by name as `NL323` at the declaration, and the docs no longer publish it. See §5.

## 2. Walls and gotchas

Deduplicated from every slice record in the arc (1,888 raw lines). Check `lang` before writing `.nl`,
`build` before running the estate or a gate, `instrument` before trusting a zero, `process` before
touching git or launching anything long. Attribution is the first finder plus the re-confirmations that
matter; an entry that a later slice OVERTURNED keeps the overturn.

### 2.1 `lang` — shapes the N# toolchain rejects, and the spelling that works

**Reserved words.** A reserved word used as a local, parameter or `out` name declines the WHOLE enclosing
declaration and the position is reported at the CLASS or `test` header, naming nothing about the identifier.
The full list is one function, `Lexer.KeywordTypeForText` (85 keywords):

- `type` (017/1, the family's first; again 017/9, 20B, 45, 58; 020/41), `newtype` (017/4, 12B, 64),
  `record` (017/5, 18, 53; 019/10; 020/37), `partial` (017/7, 17, 25; 020/11), `file` (017/9; 018/4;
  019/5, 14, 15, 21; 020/10, 43; 021/3 — a THIRD and FOURTH victim), `union` (017/10, 29, 48, 63; 019/18),
  `match` (017/25; 019/21; 020/13), `must` (017/27), `nameof` (017/50), `base` (017/42, 59), `allow`
  (018/7; 019/18), `alloc` (017/33, 34), `throws` (017/41), `params` (017/62; 016 N+1c/4), `scoped`
  (020/5 — declines at a bare `parse.test` with NO detail; four bisecting rounds), `required` (020/41),
  `on` (017/62 — contextual, so `constructor(on: …)` parses as an `on` statement and dies on the next `=`).
- Usable despite looking reserved: `test`, `field`, `property` (017/64). `.Type` is a legal MEMBER name
  even though `type` is a reserved parameter name (017/3).
- `throw` and `alloc` are keywords in ATTRIBUTE-ARGUMENT-NAME position, so `[allow(throw, reason: "x")]`
  and `[allow(alloc: pooled)]` do not parse while the block form `allow(throw, reason: "x") { }` does —
  the function-level waiver is unwritable in N# source (018/7, 018/8).
- `base` is reserved as a union-case property binding: `case Triangle { base } =>` is NL109 (017/42).
- The mechanical rule: extract the keyword list from `Lexer.nl` and intersect it with every identifier a
  new `.nl` introduces BEFORE the first build (019/18, 019/21). The estate's emit-only path replaces the
  precise `NL109` with a useless `NL103 parse.function`/`parse.struct`, so bisect in a throwaway project
  (019/5; 021/3).

**typeof / GetType surface.** `ColumnarTypeOfPlanner.IsSupportedType` is a CLOSED list; extending it is a
kernel change.

- `typeof` of an OPEN generic does not PARSE and takes the enclosing class with it (019/2).
- `typeof` of a STATIC class does not emit — `Console`, `Enumerable`, `Math` — it is the `abstract sealed`
  SHAPE, not the assembly (019/2, 019/22-2, 017/23, 017/55).
- `typeof` of a type outside the core library does not emit: `Uri`, `ConsoleColor`, `Guid`, `Regex`,
  `HttpClient`, `JsonSerializer`, `Path`, `File`, `Environment`, `MemoryStream`, `Stream`, `FileStream`,
  `TextWriter`, `StringBuilder` unless fully qualified, `StringComparison` and every enum type,
  `Nullable<T>`, `void`, `Delegate`/`MulticastDelegate`, `IEnumerable` (non-generic), `IAsyncEnumerable<T>`,
  `ICollection<int>`, `IList<int>`, `HashSet<int>`, `Queue<int>`, `SortedSet<int>`, `Span<int>`,
  `ValueTuple<…nested…>` (017/2, 2, 6, 13, 26, 28, 30, 32, 36, 41, 56, 59; 019/2, 6; 020/11, 12; 015-A0,
  A1, A3+A4, B11). `object`, `string`, `int`, `int[]`, `DateTime`, `Task`, `List<int>`, `IEnumerable<int>`,
  `StringComparer`, `Process`, `Type`, `Version`, `Exception` DO bind.
- The door is `Type.GetType("<metadata name>")` (assembly-qualified only where the type is neither core nor
  forwarded — ``Stack`1`` needs `, System.Collections`, ``Queue`1``/``HashSet`1`` do not), then
  `MakeGenericType`; `typeof(object).get_Assembly().GetType(...)` is the compiler's own spelling
  (017/2, 3, 23, 36; 019/22-2 — proved reference-identical 9/9).
- `typeof(X)` as a static-call ARGUMENT is narrower still: arrays, nullables and external enum/attribute
  types decline at `emit.call.static-user-argument` while primitives and `typeof(Type)`/`typeof(object)`
  bind (017/13, 64).
- `GetType()` on a TYPED receiver declines at `emit.statement.block-child` (node kind 48) and the error
  names the ENCLOSING METHOD; cast the receiver to `object` first (019/11; 016 N+1c/10). It IS spellable
  when the receiver arrives as `object?` out of an `IList` indexer (020/33).
- `SymbolType.IsSZArray` is TRUE for a POINTER and for a BY-REF on BOTH `RuntimeTypeBuilder` and
  `TypeBuilderImpl` — the landmine at the centre of the type-admissibility family. Guard
  `!IsPointer && !IsByRef` FIRST, in the HEAD, not the arm (015-A6).
- `System.Type`'s boolean properties do not read as properties anywhere — `IsEnum`, `IsClass`,
  `IsValueType`, `IsGenericType`, `IsAbstract`, `IsArray`, `IsInterface`, `IsGenericParameter`,
  `GenericTypeArguments` — the ACCESSOR spelling `get_IsEnum()` binds (019/6, 13; 017/18, 36, 41, 55, 56,
  60; 020/41). The same holds for every reflection property: `get_Name()`, `get_Assembly()`,
  `get_Namespace()`, `get_ParameterType()`, `get_IsStatic()`, `get_GetMethod()`.

**Receivers and chaining.** Every instance call needs a NAMED receiver.

- A chained call on a CALL RESULT, on a member-access, or on an ARRAY/LIST INDEX declines
  (`emit.call.instance-member-unmodeled` / `emit.return.expression`); bind the receiver to a local
  (017/5, 6, 20B, 26, 56; 019/2, 6). A three-deep chain `type.get_Assembly().GetName().Name` declines on
  SHAPE, not on member (019/2).
- `.Length` read off a CALL RESULT declines at `emit.statement.block-child`, while `.Count` off a call
  result and `.DiagnosticId` off a static call both emit — it is `.Length` specifically (020/13).
- A property READ chained onto a call result must be bound first (`Only(sink).Severity`, 018/4; 017/16).
- Assignment targets are receivers too: a property SET whose receiver is a FIELD declines where the same
  write through a local compiles (019/19); `list[i].Field = value` (019/10), `state.Depth = state.Depth+1`
  (019/12), `harness.Scopes.Peek().Types[k] = v` (017/63) and `elements[0].Type.Span = …` (016 N+1c/5) all
  decline; a chained property assignment declines where the same chained READ emits (018/1).
- A two-hop instance PROPERTY chain on an admitted external type declines (`element.Name.LocalName`),
  because `ColumnarInstanceMemberPlanner.TryGetComposedReceiverType` routes a member-access receiver
  through the STATIC member planner (019/22-1). Method chains are not subject to it —
  `root.GetProperty("a").GetProperty("b").GetInt32()` in one expression emits (020/10-2).
- A `??`-coalesced receiver declines; `(owner ?? "").GetType()` fails where `owner.GetType()` on a
  non-null `object` parameter compiles (020/41).
- `(p).V` parses as `MemberAccess[Parenthesized[Identifier]]`, not `Parenthesized[MemberAccess]`: a
  parenthesised RECEIVER is claimed, a parenthesised ROOT is not (015-B14).
- `this.count` / `this.Count` are kind-6 IDENTIFIERS, not member accesses — the columnar parser flattens
  them, and `ColumnarExpressionSyntaxFacts`'s own header says so (015-B14).
- A call chained straight off a `new` declines (017/57); `new X().Method(...)` declines in
  expression-statement position while the same expression inside an `assert` is fine (017/8).

**Interpolation.** An interpolation hole containing a string literal or a call declines at
`emit.interpolation.split`, and the decline names the ENCLOSING FUNCTION, not the hole (019/7, 10; the
probe-project gotcha in the toolset-republish procedure). Bind the value to a local and interpolate the
local, or concatenate. `$"…{expr}…"` is ONE literal to a scanner, a defect that recurred in three freshly
built instruments (020/42, 43, 44). In a RAW interpolated string a `:` followed by optional whitespace
SWALLOWS the next brace group into the literal text run instead of opening a hole (020/20, pinned as
measured; ruled a defect and fixed on a concurrent branch — see §5).

**Generics, tuples, spans.**
- A GENERIC METHOD on a class declines at `parse.struct` naming the class header — a missing language
  construct, not a catalog gap, so NO repin (019/9). Explicit type arguments at a CALL site parse as a
  comparison (`G.Echo<int>(…)` → NL202 + NL411) (019/9).
- Classes do not take `where` (016 slice 6). Nested-generic `List<List<T>>` trips the `>>` tokenizer —
  write `List<List<T> >` with a space; it emits the identical closed type (016 N+1c/3).
- A generic static member access does not parse: `ArrayPool<byte>.Shared`, `Result<T,E>.Ok(v)` are NL102 —
  use a closed-generic type alias, and the Result factories are the bare `Ok(...)`/`Err(...)`
  (018/6, 018/8; 015-B7).
- A closed `Func<...>` over an EMITTED type is off the parameter surface (`Func<Type,TypeInfo>?` declines,
  `Func<Type,object>?` binds) — it is the type ARGUMENT that is refused (017/12B).
- An EMITTED type cannot KEY a dictionary (`Dictionary<TypeInfo,…>` declines as field and as parameter;
  `Dictionary<Type,TypeInfo>` is fine) (017/12C). A tuple-keyed `HashSet` is off the surface while a
  tuple-keyed `Dictionary` is on it (017/10).
- A tuple-typed local needs `let`, a `(`-led type annotation does not parse in local position (tuple type
  references parse only as parameter or return types), a NESTED named tuple is not emittable, and a `null`
  ELEMENT inside a tuple literal declines at `emit.expression.unhandled-kind` (017/51; 020/5, 11).
- Reading a NAMED TUPLE ELEMENT off a walked dictionary entry declines at `emit.if.condition` while the
  walk itself emits (020/5).
- TWO span heads, not one: `ReadOnlySpan<T>` and `Span<T>` must stay separate — a folded head differs on
  588 of 20,164 ordered span pairs, including `ReadOnlySpan<int> → Span<int>`, for which no CLR conversion
  exists (015-A3+A4).

**Literals and widening.**
- An UNSUFFIXED integer literal always types as `int` and never widens by magnitude: `let x: long =
  3000000000` declines while `3000000000L` emits, and `someUlong == 255` is NL202 at EVERY magnitude while
  `255UL` passes (020/11; 017/18 `ulong != 0`). An `int` literal into a `long[]` element needs `0L`
  (021/9). An implicit `uint → ulong` widening declines at emit even though the ANALYSER admits it (020/11).
- Enum → int is `Convert.ToInt32(enumValue)` and nothing else: `x as int`, `int(x)`, `TokenType(78)`,
  `enum == 78` and `Array.IndexOf(Enum.GetNames(typeof(T)), …)` all decline or fail analysis — verified by
  RUNNING the probe (021/2). `Modifiers.HasFlag` does not emit; the route is
  `Convert.ToInt32(a) & Convert.ToInt32(b)` (020/12; 019/13; 016 N+1c/4).
- An enum-flag `|` in a typed-local initializer declines (017/18); a bitwise OR over two enum operands
  declined UNIFORMLY until 017/14 fixed it N#-side through `ColumnarNumericFacts.IsBitwiseEnum` — and an
  enum is NOT another promotable row, the result must keep the ENUM type.
- Assigning an `int` to an `int?` FIELD declines; route through an `int?` local. Comparing an `int?`
  against a literal is NL202 inside an `assert` (017/12C, 18; 019/1; 020/43; 021/6).
- Every literal AST node carries its value as a `string`: `new IntLiteralExpression("1", …)`; the type is
  `IntLiteralExpression`, not `IntegerLiteralExpression` (017/30; 019/16; 020/24).
- An N# raw string literal keeps its own indentation — C#'s closing-delimiter indent-stripping rule does
  NOT apply (020/20). A raw `"` or `\` inside a hand-written test DESCRIPTION terminates the literal and
  turns the rest of the file into garbage reported as one `parse.declaration-scan` at `1:1` (020/20).
- `= []` is not an empty array literal; the estate spells it `new X[](0)`, and array creation is
  `new T[](count)`, not `new T[count]` (017/53, 57).
- `uint.MaxValue`/`long.MaxValue` are not spelled anywhere in the repository — write `4294967295UL` /
  `9223372036854775807UL`; `2147483647` stands in for `int.MaxValue` (017/8, 49).

**Statements and declarations.**
- `switch`'s case label is `case X => …`, never `case X:`; the colon form gives NL102 and swallows the
  whole switch, so a C#-muscle-memory fixture reaches its arm ZERO times while looking like coverage
  (017/37, 42, 45). A braced case body is FLATTENED into the case's statement list. A C#-shaped
  `switch i { case 2: … }` source does not parse at all (020/30).
- `match` arms are COMMA-separated with no `case` keyword, the guard keyword is `when`, and a
  bare-identifier guard parses as a LAMBDA (`n when n => "x"` reads as `n when (n => "x")`); the type
  pattern is `TypeName binding`, not `binding: TypeName` (017/27, 39, 59).
- `catch` binds with a type annotation — `catch ex: Exception {`, not `catch ex {` — and the toolset takes
  ONE `catch` clause per `try`; a bare `throw` is not a language form, so a non-matching arm must rethrow
  `ex` and resets the stack trace (017/3, 43, 65; 019/22-2).
- A `return` inside a `try` with a `finally` is NOT a returning path (NL305 at the member's signature
  line); assign to a local and return after the handler (017/10; 020/36).
- `while true` whose only exit is a `return` inside the loop declines at `emit.body`; the working shape is
  a `searching := true` flag (017/32; 018/1). A `throw` as the FIRST statement of a block makes the rest
  unreachable and declines the whole ASSEMBLY at `emit.statement.unreachable-after-transfer` — which is
  also why an inserted `return 1` is not a valid mutation (017/21; 020/9, 16).
- `using` is `using name := expr { … }`; the EXPRESSION form is unreachable when the resource starts with
  an identifier, and `using new MemoryStream() { … }` parses the `{` as an object initializer (017/37, 41).
- `for i in 0..n` is NL202 (the collection is a `Range`) — use `while` (020/43). `await foreach x in e`,
  never `await for` (which parses as an `await` expression plus a plain `for` and SILENTLY reaches the
  sync arm) (017/38).
- A `record` declaration REQUIRES a body block, even empty; a bodiless positional record is a parse error
  (018/1; 020/29). A local declaration with an annotation and no initializer needs `let` (017/31).
- The operator-overload spelling is `static func operator +(…)`; the short form parses as a FIELD
  declaration and reports NL109 about the wrong construct (017/46).
- No block-bodied properties; a lazy C# property becomes a METHOD (017/3). A SET-only property declines at
  parse (019/2). No class-level `const` and no `null!` — a shared constant is a `static func` (017/25).
  ANY mutable static FIELD declines at columnar emit (020/39; 017/37).
- The postfix null-forgiving `!` is not an N# shape and declines the whole class (017/57).
- Free functions do NOT overload, not within a file and not across files, and a free function's name must
  be unique ASSEMBLY-WIDE: a `.tests.nl` helper named `One`/`Names` made an UNRELATED production file
  decline at a site naming something else (017/8, 20B; 018/7, 8; 019/16; 020/8). A NEW N# TYPE NAME must
  also be unique assembly-wide — `class DiagnosticSpan` collided with a dead `struct DiagnosticSpan` and
  the backend declined at `emit.declaration.method-return` on an unrelated member. The arc's costliest
  gotcha; grep the name first (017/16).
- A free function declared AFTER a `class` in the same file cannot be called at all (019/4); a file with no
  namespace emits its free functions onto a class called `Program` (019/9).
- A class with OVERLOADED methods declines wholesale at `parse.struct` naming the CLASS (017/27).
- Omitting a DEFAULTED parameter declines — on free functions, on instance methods, on STATIC methods, on
  records and on constructors; pass every defaulted argument explicitly (017/5, 55, 57, 66; 019/1, 10, 20;
  020/6, 9, 18). The converse is fine: an N#-emitted optional parameter IS optional to C# (019/20).
- A local of an INTERFACE type declines at `emit.local.unsupported-type` (`IDisposable`, `IEnumerable`,
  `IDictionary`, `Array`); a TYPED local of a read-only interface declines at
  `emit.typed-local.unsupported-type` (`IReadOnlyList`, `IReadOnlyDictionary`) — two site names for two
  spellings of one wall (019/15-2; 020/23, 26, 27). `as IList` is the estate's established idiom.
- NULL NARROWING survives `return` and `||` but NOT `continue`, NOT a repairing assignment, NOT `out`, NOT
  `IsNullOrEmpty`, NOT `assert x != null`, and NOT a `||`-joined guard; only the POSITIVE `if x != null`
  narrows, and only `nlc check` says so (017/17, 20A, 29, 30, 31, 43, 53, 58, 64, 65, 66; 018/5; 019/10,
  14, 20). `.Value` on a nullable is NL907; `.Value` on a nullable-ANNOTATED receiver is read as the
  language's nullable unwrap and SHADOWS a real `.Value` member (019/22-2).
- `object.ToString()` is typed `string?`, and the columnar backend accepts the un-narrowed form SILENTLY —
  only the analyzer finds it (017/18).
- `decimal` is EXCLUDED from the primitive relational domain and still compares, because the OVERLOAD is
  consulted FIRST and `System.Decimal` declares `op_GreaterThanOrEqual`; `bool < bool` is the shape really
  refused (017/53). Separately, the door's `ByRefParameter` claim class carries a recorded `ref decimal`
  DECLINE, kept as a measured limitation rather than widened — the ledger states it only as 015-B6's C10
  back-reference to "the same class of honesty `015-B5` applied to its `ref decimal` decline", so the
  shape's exact site is not written down anywhere in the archive.

**Collections and BCL types.**
- Iterate a dictionary DIRECTLY (`for entry in dict` with `.Key`/`.Value`); `dict.Keys`, `dict.Values` and
  `Dictionary<K,V>.KeyCollection` all decline as values (017/55; 018/5; 019/4, 6, 22-2; 020/10-2). The
  `for kvp in dict` blocker recorded by 019/4 was REFUTED by execution and had the shape backwards.
- `Dictionary<K,V>` does NOT widen to `IReadOnlyDictionary<K,V>` in any position while `List<T>` widens to
  `IReadOnlyList<T>` in all of them: a read-only dictionary can be RECEIVED by N# and never CREATED by it.
  That asymmetry is what kept `ProjectSnapshot` out of reach of `.tests.nl` (019/21). Root-caused in
  020/10-1: the missing half was a GATE ABOVE an already-published row —
  `TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition` listed fifteen ONE-argument heads and no
  two-argument one; the wall had been CONTRACT-PINNED as a wall.
- `IReadOnlyDictionary`/`IReadOnlySet`'s `.Count` still reports NL303 (019/15-2; 020/10-1).
- An INTERFACE RECEIVER sees only its own members: `IList<T>.get_Item` binds, `get_Count` does not
  (declared on `ICollection<T>`), `foreach` over `IList<T>` declines, and interface-to-interface casts
  decline — route through `object` then the non-generic `IList` (017/12A, 13). Interface member lookup
  ignores BASE INTERFACES on both the analyzer and `ColumnarOrdinaryRuntimeDirectCallResolver` (017/12A).
- A derived value does not widen into a base-typed slot: array element stores, `List<Base>.Add` inside a
  call's argument, and `:=` inference all need an explicitly BASE-typed local first (017/11, 14, 36, 58,
  59). A heterogeneous or constructed-element array literal declines at `emit.local.initializer`; the
  estate builds object arrays with `new T[](n)` plus index assignment, an idiom that is LOAD-BEARING, not
  stylistic (020/4; 019/16).
- Constructing any type that lives in a REFERENCED assembly declines at `emit.local.initializer` — the
  reason every native project reaches production types by reflection (020/10-1, 23). A type on the TYPE
  surface is not automatically CONSTRUCTIBLE: `new` is a separate hard-coded C# name table in the emitter;
  use the reflected constructor with an `object?[]` argument array (017/12A).
- A boxed value cannot be UNBOXED by cast, `as` or `is` — compare with `Equals` against a boxed constant
  (017/12A). `.ToString()` on a user N# class or a `TypeInfo`-typed receiver declines; the idiom is
  `boxed := x as object` then `boxed.ToString()`, now in six owners (017/4, 11, 13, 31, 34, 56, 64;
  019/14). An enum's `ToString()` is not in the catalog — write the mapping out (017/47, 64).
- `Object.ReferenceEquals` (capital O) is the reference-identity route and `object.ReferenceEquals` is not
  bound; both operands must be `object`-typed locals, and over a USER type or with a static-property
  argument it declines anyway (017/7, 11, 27, 31, 55, 67; 019/12; 020/12, 45). `==` between two
  differently-typed `TypeInfo` expressions, two `Assembly` references or two `Version` references declines
  (017/4; 020/15; 021/9b).
- `System.Xml.Linq` is a TOTAL wall at the DECLARATION boundary — `XElement` cannot even be a parameter
  type — so the tempting "C# loads, N# traverses" split does not exist (019/6). Published in 019/22-1.
- Not modeled at emit: `File.AppendAllText`, `Console.SetOut` (so a `.tests.nl` can CALL a command's
  `Execute` and never SEE what it printed), `CultureInfo` in both directions except
  `CultureInfo.InvariantCulture`, `Regex` construction and static `IsMatch` (only `Escape` compiles),
  `Activator.CreateInstance`, `Task.Run`, `Stopwatch`, `Environment.TickCount64`, `Double.Epsilon`,
  `Math.Abs(double)`, `string.CompareOrdinal`, `StringComparer.Ordinal.Compare`, two-argument
  `string.IndexOf`, `Array.Sort` with a comparer, `List<T>.RemoveRange`, `new Dictionary<K,V>(other)`,
  `new HashSet<T>(source, comparer)`, `Directory.CreateTempSubdirectory`, `Directory.GetParent`,
  `Assembly.GetTypes`, `Assembly.get_FullName`/`AssemblyName.get_Name` (OVERTURNED — both ARE on the
  surface, proved by execution in 017/65), `Type.GetMethod(string, BindingFlags)`,
  `Type.GetFields(BindingFlags)` (OVERTURNED — published, 019/2), `MetadataLoadContext.CoreAssembly`,
  `SearchOption.AllDirectories`, `System.Random`, `System.Text.Json.Nodes` construction, `JsonElement`
  enumeration and indexing, `ProcessStartInfo.RedirectStandardInput`, `System.Reflection.Metadata` in
  every spelling (017/3, 7, 13, 14, 21, 22, 30, 32, 36, 37, 48, 62, 66; 019/5, 6; 020/10-2, 14, 16, 39,
  40, 41, 42; 021/6, 9, 11). `Enum.Parse` and `System.Text.Json` cannot COEXIST in one compilation unit,
  and splitting into two `.tests.nl` does not isolate it — a native project compiles as ONE unit (020/39).
- **The columnar surface binds the CULTURE-SENSITIVE overloads by default and says nothing.** A bare
  `.ToLower()`, `.ToUpper()`, `.StartsWith(s)`, `.EndsWith(s)` or `.ToString()` on a numeric value needs no
  `CultureInfo` argument, so it compiles everywhere and reads `CurrentCulture` at run time — 021/6's
  "the compiler is a stronger guarantee than a contract" holds only where `CultureInfo` is SPELLED. The
  spellings that work and are invariant: `.ToLowerInvariant()`, `.ToUpperInvariant()`,
  `Char.ToLowerInvariant`/`ToUpperInvariant`, `Convert.ToString(x, CultureInfo.InvariantCulture)`,
  `String.Compare(a, b, StringComparison.Ordinal)`, `StartsWith`/`EndsWith` with an explicit
  `StringComparison`, and `Double`/`Decimal.TryParse(text, CultureInfo.InvariantCulture, out v)`
  (locale chip; 018/70.4).
- A `\uXXXX` escape in a `.nl` string literal is NOT decoded anywhere in the pipeline — it stays six
  literal characters. Write the character, or avoid needing it (locale chip).
- `NL103 reports only the FIRST decline in an assembly`, so an early decline MASKS every later one and
  each gotcha costs one build (017/12C, 14, 26; 020/3). The bare `nlc build` decline sentence carries no
  code and no line; `NSHARP_COLUMNAR_DECLINE_LOG=1` is the only way to locate the expression (021/11).
  Where a decline names a whole function or a bare node kind, check the CALLEE's arity first — a
  nonexistent constructor overload declines at the enclosing statement (017/24, 28, 35, 47).

**Toolset-pinned limits (these lift at an SDK repack, not by editing `.nl`).** `BootstrapServices` is
`<Project Sdk="NSharpLang.Sdk" />` and compiles under the PACKAGED SDK from `~/.nuget/local-feed`, so a
widened allowlist, catalog row or opcode name is INERT inside it until the coordinator repacks — that is
the two-stage boundary, and a probe against the branch's freshly built CLI answers the wrong question
(015-B1, B2-1, B10, B11; 017/12A, 14, 19, 20A, 36; 019/15-1, 22-1; 020/10-1). Walls that a repack has
since lifted and that should NOT be re-priced: `char.IsLower` (017/48), the `BindingFlags`
`GetStaticMemberPlan` row (017/20A), enum bitwise `|`/`&`/`^` (017/14), and `System.Reflection.Module` +
`get_Module` (015-B11; the 0.1.0 SDK packed from `b57c661a0` carries them). The columnar front end also
has a PER-CLASS MEMBER-FUNCTION CEILING: at the ceiling, adding ANY member function declines the whole
class at `parse.struct` regardless of name or body — inline the helper; fields do not count (016 N+1c/10,
11). Raising it is a kernel change, i.e. the two-stage wall.

### 2.2 `build` — estate, SDK, feed, restore and gate mechanics

- **The estate silent-abort.** `dotnet test` on `NSharpLang.Compiler.BootstrapServices` runs NOTHING
  without `-p:NSharpExcludeTests=false`: it restores, prints `Build succeeded`, exits 0 and runs zero
  contracts. The flag must be applied by a `dotnet restore -p:NSharpExcludeTests=false --force-evaluate`
  BEFORE `dotnet test --no-restore`, and ANY other build in the checkout (a `Cli.csproj` build, a
  `Tests.csproj` run) invalidates it. **Exit 0 with no `Passed:` line is a FAILURE, not a pass** — assert
  on the `Passed:` line, never on the exit code (017/52, 61; 018/5; 020/11–31; 021/2, 3, 11).
- `dotnet test` can also exit 0 with zero output after concurrent builds share `obj`/`bin`, and WEDGES
  rather than fails beside a heavy oracle run (0.11 s of CPU in 60 s, never exits). Clean `bin`/`obj`,
  restore with the flag, re-run SERIALLY (019/22-2; 020/19, 24).
- Emit runs on a DEDICATED 64 MB wide-stack thread: MSBuild task threads run ~256 KB stacks and the
  emitter's per-node frames overflowed every fresh SDK-path emit; the NL103 decline trace is thread-local
  and must be BUILT on that same thread (`195028aa9`, `7f4e727d6`).
- The feed actually consulted is `~/.nuget/local-feed`; `~/.nsharp/packages` is NOT. A mid-slice pack
  poisons it — take the repin ONCE, at the end, behind a green gate; a full
  `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` from a clean tree IS the repin, and the gate's own
  Step 4 packs into its OWN isolated run directory, leaving the user feed untouched (017/12A; 019/15-1;
  021/1; Current evidence).
- **In a fresh worktree, build `-c Debug` before running the estate.** Three
  `ExternalAssemblyScan.tests.nl` blocks read `<projectDir>/obj/Debug/net10.0/refint/…dll` off disk while
  the estate runs in Release; a tree that never built Debug reads `7,180 / 3` instead of `7,183 / 0`. The
  same three fail after `rm -rf bin obj` and after an IL sweep deletes the Debug layout (015-B15;
  016 N+1c/8, 9a; 017/10, 11, 12B; 020/14, 17, 25).
- Eight corpus targets reference `../../../src/NSharpLang.Cli/bin/Debug/net10.0/Compiler.dll`, so a fresh
  `git worktree` that built only Release fails them; seven answer `{"error": …}` with no `results` key
  (017/33, 38).
- The CLI project is `src/NSharpLang.Cli/Cli.csproj` and the assembly is `Cli.dll`; the compiler project is
  `src/NSharpLang.Compiler/Compiler.csproj` and the assembly is `Compiler`. A wrong name fails in 0.05 s
  with MSB1009 while a wrapper still reports success (017/31; 019/10, 12, 13).
- The installed `~/.nsharp/bin/nlc` is routinely stale; run every probe through a freshly built tip CLI
  (020/1).
- `nlc build` is not `nlc test`: a `.tests.nl` project fails `nlc build` outright even on a pristine tree,
  and `nlc build` silently UNDER-MEASURES a `.tests.nl` corpus. `nlc test --project src/…BootstrapServices`
  is also not the contracts route (it re-checks the whole project and exits on the estate's 282 tolerated
  lint findings) — the gate's own route is `dotnet test <csproj> -p:NSharpExcludeTests=false`
  (015-B13; 017/45; 021/7).
- `nlc check` structurally NEVER sees a `.tests.nl` (`ProjectSourceFileFilter` drops them by extension,
  no switch turns them on), so "zero rows in a contract file" is a property of the check. The real
  yardstick is a scratch copy with every contract renamed `.checked.nl` (019/6; 020/17, 18, 19–31).
  Conversely a `.tests.nl` is NOT evidence about the production emit path — `NSharpExcludeTests=true`
  compiles them differently, and `typeof(Console)` builds in a contract and declines in a production `.nl`
  of the same project (019/6).
- The ratchet manifest `tests/native/ownership-audit/non-nsharp-growth-ratchet.v1.json` is 391 lines with
  NO BOM (first bytes `7b 0a 20`); edit it LINE BY LINE — a `json.dumps` round trip reflows 381 compact
  rows into 6,106 lines (017/1, 2, 22; 020/14, 15; 021/6). It tracks only NON-N# files (zero `.nl` rows),
  so an `.nl`-only slice needs no repin — prove it, since appending one blank line to
  `ColumnarIlEmitter.cs` takes the audit to 17/18 (015-B2-1; 016 stages 1–8; 021/9b).
- The two-key repin (JSON header `reviewedHeadFingerprint` AND `OwnershipPolicy.ReviewedHeadFingerprint`
  at `OwnershipAudit.nl:241`) is the LAST edit; the audit reads 17/18 before it and 18/18 after, with zero
  occurrences of the superseded head left under `tests/native/ownership-audit` (every A- and B-stage;
  018/1; 020/16, 19–31).
- Deleting a tracked file flips its row to `state:"removed"` with zero current metrics and the literal
  fingerprint `text-v1:removed`, epoch ceilings untouched; dropping the row fires `OWN006` (016 N+1b, N+3;
  017/12B; 020/22–31, 45; 021/4).
- The audit reads sources through .NET's BOM-stripping reader and fingerprints UTF-16 CODE UNITS: a
  replica must read `utf-8-sig`, hash UTF-16 units, and write the manifest back as plain `utf-8`
  (017/21, 22, 24; 020/34, 44; 021/2, 6). `OWN003` = a new unclassified non-N# file, including the gate's
  own log written inside the byte-copy and a stray probe `.cs`/`.test.ts`; `OWN009` = a leftover
  `TestResults/.trx` or a staged `.nl` under `systems-language-closeout/` (017/12A, 20B, 39; 020/17, 18;
  021/12). `OWN004` fires on a SHRINK too — the ceiling is an EXACT match (021/5).
- `editors/vscode/test/suite/` cannot grow by EITHER route: all 21 rows sit exactly at their epoch ceiling
  and a probe `.test.ts` is refused by `OWN003`. The sanctioned path for editor coverage is a
  protocol-seam harness in N# (021/12).
- The audit CANNOT see emitter growth: the ceiling is the EPOCH (21,723 / 20,646), not the low-water mark,
  which is how the emitter grew 21,433 → 21,519 across seven product-fix commits while 015 was paused
  (015 status; reopening decode).
- Run the gate from a `/private/tmp` byte-copy that KEEPS `.git` (the cache-key step uses `git ls-files`)
  and EXCLUDES `.claude/worktrees` — the repo root carries up to eight nested worktrees from other
  sessions, several with a duplicate `NSharpLang.Benchmarks.csproj` that breaks the BDN Systems gate in
  place. Verify the copy's contents directly (worktrees absent, `.git` present, `.csproj` count, zero
  `.trx`, both ratchet keys) rather than assuming (015-A/B arc-wide; 019/12, 15-1; 020/10–45; 021/5b, 12).
- Write the gate log OUTSIDE the copy; a log at the copy's root fails the audit (020/17, 18; 021/11, 12).
- `pgrep -f test-all-core.sh` must be EMPTY before launching, and the gate launched DETACHED; use
  `env -u VSCODE_TESTS` so an inherited value cannot leak in. Read the verdict from the log's
  `ALL TESTS PASSED` line and the driver's `GATE EXIT`, never from `pgrep` (019/21; 020/4–45; 021/5b).
- The gate keeps a SHARED, session-crossing dependency cache at
  `~/Library/Caches/NSharpLang/test-all/dependencies/<key>/`; a `Could not load file or assembly
  'Mono.Cecil, Version=0.11.6.0'` out of `EmitIlAssembly.SynchronizeReferenceAssembly` is its stale-cache
  signature wherever it appears — delete the one entry (019/2, 3; 017/23).
- Gate input sets are enumerated at `tests/scripts/test-all-core.sh:191-199` (`scripts/`, `tests/scripts/`,
  `global.json`, `Directory.Build.props/.targets`, `NuGet.config`, `NSharpLang.sln`, `src/`, `tests/`,
  `examples/`, `templates/`, `docs/`, `website/docs/`, `editors/vscode/test/suite/`, `tests/fixtures/`,
  `tests/native/`). `systems-language-closeout/` and `memory/` are in NONE, so editing this ledger after
  the copy cannot enter the verdict (017/41–54; 019/20; 020/3, 8, 43–45; 021/7).
- FORMAT-GATE HOLE: step 2b checks exactly four project paths (`examples`, `templates`,
  `tests/fixtures/issue-tracker`, `src/NSharpLang.Compiler.BootstrapServices`). `tests/native/*` is not
  among them, so `ownership-audit/OwnershipAudit.nl` has been unformatted since before 021/12 and nothing
  said so; `nlc format --check` also answers differently by invocation form, and `.tests.nl` are outside
  discovery entirely (015-A0, A6; 017/43, 47; 018/5; 020/4, 17, 18, 23; 021/11, 12).
- The canonical formatter JOINS a multi-line boolean `return` onto one line and owns the blank line after
  a doc-commented class header — write long tables as NAMED HALVES from the start, and accept the
  canonical output (018/3; 019/1, 17; 021/6). `ColumnarIteratorPlanner.tests.nl` trips the formatter's own
  idempotence safety check on a normal committed file (015-A6).
- A native test project cannot reference another native test project, so shared reflection kernels are
  DUPLICATED — the cost is stated, not hidden (020/38). `project:` references require a `project.yml`, so
  `NSharpLang.Compiler.csproj` cannot be one at all (020/23).
- An N#-emitted assembly cannot be consumed from C# through a bare `<Reference>`: every N# signature
  naming a corelib type resolves it in `System.Private.CoreLib` (`CS0012`), and adding that reference
  makes it worse (`CS0518`/`CS0433`). A `ProjectReference` is the only route (018/7; 019/18; 020/34). The
  Cecil corelib→contract TypeRef rewrite is the whole of N#→C# consumability, executed not reasoned
  (021/8).
- `/private/tmp` IS REAPED. Regenerate worktrees, fixtures, IL trees and instruments rather than assuming
  they survive; durable harnesses live in the scratchpad or under `~/nlNNkeep/` (017/21, 30, 55, 64–67;
  018/1–8; 019/1–22).
- The N# emit is NOT incremental: a harness that runs `dotnet build` then `dotnet test` pays the
  ~4.5-minute emit twice per control case (015-B3), and four concurrent `.nl` emits turn a 4-minute build
  into a 15-minute one — two at a time is this machine's ceiling (017/52).
- Environment facts: `timeout(1)` does not exist on this machine (every "run the target" step returns 127
  and a sweep can be BLIND while reporting zero diffs); BSD `sed` has no `\b`, so a copied `\b`-anchored
  normaliser or rename silently does NOTHING and reports success (015-B5; 017/30, 44, 61, 66; 019/16;
  021/11).

- The CLI project file is `src/NSharpLang.Cli/**Cli.csproj**`, not `NSharpLang.Cli.csproj`; a wrong path fails
  with a bare `MSB1009` while the stale `bin/` still holds a `Cli.dll`, so it reads as a stale-CLI success (B16).
- **An `Sdk.targets` change cannot take effect in the gate run that packs it — it lands ONE GENERATION LATER.**
  `BootstrapServices` resolves `Sdk="NSharpLang.Sdk"` 0.1.0 from the NuGet package cache, never from the source
  tree, and the isolation wrapper's `is_dependency_input` counts `.targets` as a dependency input — so editing
  `Sdk.targets` changes the DepKey, which allocates a FRESH dependency dir seeded from the real
  `~/.nuget/packages`, i.e. the OLD package. Two gate runs measured this as "the fix did nothing" (identical
  2-emit Step 2) before the cause was found. To measure an SDK change before its republish, seed that run's own
  `dependencies/<DepKey>/nuget/packages/nsharplang.sdk/0.1.0/Sdk/Sdk.targets` with the patched bytes — the same
  bytes Step 4's pack produces — and restore them afterwards. The real fix is the coordinator's two-stage
  republish (repack, place in BOTH `~/.nuget/local-feed` and `~/.nsharp/packages`, purge the cache entry) (GATE-SPEED).

### 2.3 `instrument` — comparators, censuses, harnesses, and how each one lied

- **`nlc check` DOES NOT ANALYSE `.tests.nl` AT ALL, so a green `check` over a test project is a
  non-verdict.** Measured on the skip-form chip: a project whose only file is a `.tests.nl` answers
  `checkedFiles: 0, ok: true, results: []` — and it answers the same with a plain `NL001` in a test body.
  Only `nlc test`'s own build runs the analyzer over them. Any claim of the form "`check` says the shape
  analyses cleanly" is unfounded for a test file; probe it with `nlc test` and a KNOWN diagnostic first
  (§5, skip-form chip).
- **A CONTRACT THAT RENDERS BOTH SIDES CANNOT FAIL ON A RENDERING BUG.** `assert Run(x) == (2.5).ToString()`
  moves with the culture on BOTH halves and passes under de-DE while printing `2,5`; four such blocks stayed
  invisible until the ACTUAL side was made invariant, which is why the filed locale failure count was 3 and
  the real one is 7. Pin rendered output as MEASURED literal text, and measure it (decimal keeps its operands'
  scale: `1.5m + 2.5m` is `4.0`, not `4`) (locale chip).
- **A zero-count run is a NON-VERDICT, never a pass.** Proved at every scale: `nlc test` answering
  `total: 0` after a mutation crashed the analyzer; a mutation matrix reporting `EXIT=0` with an empty log
  because a CLI build had run between the restore and the test; an IL sweep reporting `compared 0, SAME 0,
  DIFFERENT 0` because `timeout` does not exist; an oracle reporting `ORACLE_DIFFS = 0` with
  `NO_RESULTS = 71`. A harness must REFUSE a verdict unless the run reports a non-zero `Total:`
  (015-A3+A4; 017/44, 64; 020/21, 25, 36–38, 41; 021/2, 6, 11).
- **A "nothing is reported" probe must prove its own INPUT first, and a placeholder NAME is an input.**
  020/35 filed a whole analyzer gap on five probes that all spelled the undefined type `Missing` —
  `System.Reflection.Missing` is a real BCL type the simple-name external probe resolves with no import,
  so every probe measured a RESOLVING type and none tested the claim. Any absence probe over the name
  resolver must first show the SAME source with a name that resolves through no channel (`Zqxwvut`) and
  watch it move; drawing a placeholder from ordinary English is how you hit a BCL type (§5).
- **A control that cannot fail is not a control.** Every census, comparator and probe carries a declared
  non-vacuity control that has actually failed at least once: a SPEAKING CONTROL (a deliberately failing
  assert) in every probe project; a one-character perturbation of a single dump row for the IL comparator;
  the known-answer control that deleted types must appear ZERO times (015-B10 onward; 020/33–41; 021/12).
- **Control-first for every corpus comparison**: run ctlA vs ctlB (the SAME CLI twice on fresh trees)
  BEFORE ctlA vs slice. Same-CLI controls caught a wrong COFF `TimeDateStamp` offset (it is COFF+4, not
  COFF+8), a missing `#GUID`/MVID zeroing (two builds of one source differ by 17 bytes), an
  `rsync`-vs-`git worktree` SourceLink difference (512 bytes on `NSharpLang.Runtime.dll`) and a phantom
  `nlc build` floor from two example directories with no `project.yml` (015-A6, B10; 017/24, 25, 30, 31,
  38, 40, 41, 42, 44).
- A worktree used for IL comparison MUST be a real `git worktree`, never an `rsync` copy (017/31).
- **Compare IL by KEY, never by raw `diff`.** `diff` over two sorted IL dumps mis-reported by two rows at
  320 changes — line ALIGNMENT, not byte movement; the comparison is keyed on
  `<assembly>|<Type>::<Method>` (015-B12). The dump instrument must be MVID-free by construction (an SRM
  method-body reader), and a normaliser must RAISE rather than swallow: a swallowing `except` around a
  section-count read at COFF offset 0 instead of 2 turned "186 diffs" into a harness bug (015-B1;
  017/15, 16).
- **Byte identity cannot tell a claiming door from a declining one**, and a decline-side mutation is
  VACUOUS by construction. Every door slice therefore carries a MARKER mutation (`ldc.i4.0; pop` before
  the value arm's `ret`), with per-body moves predicted BY NAME first — and the marker itself must be
  validated: the injected-row marker does not survive a schema-v3 fragment and broke three corpus projects
  on both sides (015-B3, B7, B8, B11).
- **The corpus harness must MIRROR each project's repo-relative path** and carry one fixed
  `src/NSharpLang.Cli/bin/Debug/net10.0` snapshot beside it; flattening breaks repo-relative `dll:` deps —
  22 projects failed `DLL not found` and the harness silently covered 41 instead of 59. It must also not
  copy `bin`/`obj` (the first pass dumped 18,574 rows against a baseline's 8,408 — two different corpora,
  not a diff) (015-B4, B15).
- The corpus dependency SNAPSHOT must carry `src/NSharpLang.Playground/bin/...` as well as the CLI bin and
  the BootstrapServices `refint` dir: without it two projects fail `DLL not found` IDENTICALLY on both
  sides, so the loss is invisible in the diff and silently shortens the corpus (015-B16).
- **`nlc test`, not `nlc build`, for `.tests.nl` corpus projects** — that one harness fix took the corpus
  41 → 45 built (015-B13, closed at B15's 68/59/3,463).
- **The live-tree row-for-row `nlc check` walk is load-bearing and catches what nothing else can**: three
  new NL011 empty-catch diagnostics past a green estate, a green native gate and `IL_DIFFS=0` on both
  corpora (015-B10); two NL202s past a green build and 4,952 green contracts (019/19); an unused import
  after a green build, green emit and a byte-identical differential (019/12). `BootstrapServices` builds
  with `NSharpEmitValidateWithLegacyAnalysis=false`, so a green build is not a clean file.
- **UTF-16 literal scans.** A UTF-16-LE scan of a packed dll is the only way to verify new literals —
  ASCII `strings` is a false negative, because .NET literals live UTF-16 in the `#US` heap (toolset
  republish procedure). The same code-unit rule governs the ratchet fingerprint.
- **Census blind spots, each found by a marker or a mutation rather than by reading**: the function-header
  regex `func\s+(\w+)\s*\(` cannot spell `func operator ==(` (015-B12), a CONVERSION operator has no
  `func` keyword at all (015-B14), a walk over top-level and member declarations misses LOCAL functions
  (015-B9), a textual census reads TEXT while the door dispatches on NODE KIND (015-B14), an
  expression-bodied member is not a claimable body and must be censused out (015-B13), and `.WithHandler<T>()`
  hides its type argument in a MethodSpec SIGNATURE BLOB so three live LSP handlers read zero-consumer
  until an ECMA-335 signature walker was added (021/1).
- An IL census needs a STALENESS gate and then an EVIDENCE gate and then ONE canonical copy per assembly:
  a clock-only cutoff let a Wasm Debug `Compiler.dll` through, censusing every copy on disk let an older
  build through, and "freshest copy" then picked `obj/*/ref` reference assemblies whose method bodies are
  EMPTY, reading every type as zero-consumer. Any one would have produced FALSE DELETIONS (021/1, 4, 5b,
  12). Enum members inline as `ldc.i4` and C# `record` synthesis is structurally invisible — 29 of 31
  zero-consumer rows (021/12).
- **A source grep cannot see the compiler's own overload choice**: an IL member census over `DocQuery`'s
  compiled bodies corrected the `System.Xml.Linq` brief three times (a SEVENTH type `XContainer` no source
  line spells; `XName.op_Implicit`, not `Get`; real signature crossings) (019/22-1).
- A NAME-based dead sweep is defeated by a same-named member in a sibling file (`SharedAnalyzer` on two
  types needed a RECEIVER-TYPED IL census over 170,633 bodies) and by reflection-by-string-name — for a
  `private` member only string literals count as outside references (019/3, 20, 21).
- **The corpus routinely cannot decide the question.** `AnalyzeCall`'s 96,502 receiver-site evaluations
  fired ZERO times; 14,608 of 14,736 finalisations carry no lambda and none carries two; the corpus has NO
  indexer, no `switch`, no `off`, no `using`, no `checked`/`unchecked`, no `sizeof`/`nameof`/`default`,
  no `stackalloc`, and its maximum pinned `trustedSites` is ONE. A corpus of COMPILING sources reaches
  none of a reporting family's told paths (691,080 SoA gate asks, all False; 34,172 condition gates, zero
  reports). Purpose-built fixtures are the only evidence the reporting half works (017/21, 24, 25, 37, 39,
  41, 42, 47, 50, 52; 018/1; 021/3).
- **A fixture that does not PARSE still fires the driver you built it for**, because recovery substitutes
  nodes — so a PARSE-ERROR CENSUS over the WHOLE ACCUMULATED fixture set runs before any transcript is
  trusted. It found Go-style `[]int` arrays, C#-style `case X:`, `await for`, `func F(): T = e`,
  `binding: TypeName` patterns, lambdas written `func(x) { … }`, 43 `params` parse errors and a
  non-parsing multi-argument indexer (017/34–51, 67; 018/3, 6, 7).
- A fixture that CRASHES `nlc check` also differentials perfectly and looks like coverage: check for a
  MISSING `results` key, not just a matching diff (017/36, 37, 40). `nlc check --json` puts diagnostics
  under `results` as a FLAT list, not under `diagnostics` — a trap 017/33 recorded that caught 017/35
  anyway and 021/11 again.
- `nlc check` collapses diagnostics by `code|file|line|column|message` and SORTS; only `nlc build` renders
  `_errors` in LIST order with no dedup, so it is the only surface on which multiplicity and order are
  visible (017/17–21, 24).
- **The decoder is always the thing that is wrong.** Every comparator in 020 corrected itself 6–13 times
  and EVERY correction was a silent wrong answer rather than a crash: a brace-counting splitter that found
  36 of 91 methods (source literals contain braces — mask them), a member walker that ended a member at
  the first `    }`, a line-range reader thrown off by a non-line-count-preserving control, an
  interpolated `$"…"` read as one literal, C# raw literals needing closing-delimiter indent stripping and
  NO escape processing, a `.Count`/`.Length` fold that rewrote a record FIELD on one side only, and a
  `s.replace("", old)` restore that inserted `old` between every character. Completeness arithmetic
  (rows in = decoded = reconstructed, 0 UNDECODED, 0 MISSING) is what makes the answer meaningful
  (020/8–45).
- The mutation ATTRIBUTION predicate trap took six forms in 020 alone (naive substring under-counting to
  zero, over-counting by six, matching six wrong tests, matching through a digit boundary, matching a
  `Parser.cs` line number embedded in a name); only the runner's FULL generated prefix, read out of a
  `--logger trx` dump of the green estate, is safe (020/17–22).
- Every mutation anchor must be asserted to occur EXACTLY once before the walk, and a case whose anchor
  does not match must ABORT rather than silently do nothing; `ANCHOR NOT FOUND (0)` is equally a
  non-verdict (015-B3 onward; 020/21, 22, 30, 35).
- **A non-mover must be proven non-observable by an exact count and then REPLACED**, never waived; an
  EQUIVALENT MUTANT is a correct green and the slice must not leave the non-result standing (015-A3+A4;
  020/12–45). Some non-movers are real findings — but a REAL FINDING IS NOT THE SAME AS A BROKEN OWNER, and
  the difference is measured, never inferred: NL309's object-initializer arm's sentence was pinned by
  nothing in either suite (020/33) and the ARM ITSELF ALWAYS FIRED (chip decode, §5 — the gap was the
  estate's, and chasing it found three real NL309 holes the mutation could not see), while
  `AnalyzerMatchExhaustiveness.nl:301`'s explicit `_` wildcard arm
  is DEAD CODE shadowed by the catch-all arm eleven lines below (020/34).
- A byte-identical seam is a measurement only when a mutation matrix moves it, and a suite's verdict has
  no general answer: `LanguageServerTests` was sharp in 021/5, blind in 021/4 and blind again in 021/5b —
  measure sufficiency PER SEAM. A test that fires only when the owner is destroyed is a LIVENESS check,
  not a behaviour comparator (021/4, 5, 5b).
- Transcript normalisers: `nlc build` has TWO elapsed-time spellings (`[0.4s]` and `in 0.4s`); `nlc lint`
  embeds the invoking `projectRoot` so its md5 is CWD-dependent; every normaliser must be RE-DERIVED per
  slice, never inherited by copying the script (017/18, 21, 26, 27, 30, 34, 36, 43; 019/7, 8, 18).
- Instruments that graded the owner they were meant to prove, six times in the 017 arc alone: the
  estate-wide `nlc check` caught NL012, NL010, NL202 and NL905 in new owners after green builds
  (017/29–35, 47, 52).
- **`/usr/bin/time -l`'s page-reclaim count is the instrument that would have caught the emit regression
  two months early, and peak RSS is the decoy that hid it.** The 2026-09-01 `sdk-emit-only` log already
  carried **2.1 M page reclaims against a 611 MB peak RSS** — ~34 GB of 16 KB pages mapped and thrown
  away, which is the signature of repeated `MetadataLoadContext` create/dispose, not of a large heap.
  The fix moved reclaims to 383 K and `sys` from 20.7 s to 1.4 s while RSS went UP. When a run is
  CPU-bound with double-digit `sys` seconds, read reclaims before RSS (015 item 1).
- **Never compare two emits across an edit to the compiler's own sources.** BootstrapServices IS the
  corpus, and a harness that reads source at thread start (not at launch) will silently pick up a patch
  applied while an earlier run was still going. Two "baselines" differing by 512 bytes were recorded as a
  product nondeterminism and RETRACTED; the control taken properly is 18 bytes (015 item 1).

### 2.4 `process` — git, staging, agents, watchdogs

- **Never `git add -A`; stage only your files.** Other sessions work in the same checkout: three
  concurrent sessions reverted two of one slice's edits, left an `.orig` behind and moved the tip mid-slice
  with a 309-file reformat. Snapshot own files, build and diff in a DEDICATED `/tmp` worktree, never
  revert another session's files, re-anchor before finishing (017/23, 43).
- **Never `git checkout --` over uncommitted work.** A mutation harness that restored with
  `git checkout --` WIPED a slice's own executor edits; restores must be COPY-BASED with a `sha256` gate
  at every step (015-B2-2, then arc-wide). Equally, never clean by glob: `rm -f …/_*.nl` matched 51 files,
  FOUR of them tracked — clean from `git status` (021/5, 5b).
- **Never kill a running gate driver.** Its EXIT trap deletes the `/tmp` run tree out from under the
  still-running core: `Interop.Sys.GetCwd()` then throws inside the packaged SDK's emit and MSB3541
  follows as a consequence, not a cause. The safe form is to kill the whole `nsharp-test-all.<key>` TREE
  first, then the driver, then stale run trees and the worktree's `tests/bin`+`tests/obj`, then clear the
  poisoned dependency-cache entry (015-A5; 019/22-2; 020/18; 021/11).
- **`pgrep -f test-all-core.sh` before launching a gate** — `~/.nuget/local-feed` is shared mutable state
  and a mid-rewrite feed produced 16 `Unable to find package` failures that were not the diff (019/21;
  020/4–45). A `pgrep -f` waiter also matches its OWN command line: two waiters reported "still running"
  for twenty minutes after the work had finished (017/39).
- **A log's filename is part of its identity.** A gate run whose verdict has not been read is not
  evidence; a gate stopped, signalled or superseded is a NON-VERDICT and is REPORTED rather than
  discarded; a gate launched as a child of a chained wait dies when that parent is stopped; a gate must be
  RE-RUN fresh whenever any byte it covers changes after the copy (017/10, 42, 47, 48; 019/8; 020/6, 7,
  16, 18, 40, 41; 021/3, 9).
- **Never pipe a long-running walk through `tail`.** The pipe buffers every line, the no-progress
  watchdog kills the driver mid-mutation, and the production owner is LEFT MUTATED on disk because the
  `finally` never ran. `tee` the full stream beside the tail; piping `dotnet test` through `tail -40` also
  truncates the per-block enumeration and cost B15 its block lists (015-B4, B15; 020/22).
- A mutation harness that is SIGNALLED leaves a mutant on the tree — a `finally` does not run when the
  process is killed. Run matrices DETACHED under `nohup`, outside the task watchdog, behind
  `atexit` + `SIGTERM`/`SIGINT` restore handlers, and verify each restore by `shasum -a 256` against a
  pre-mutation backup; the trap must STOP on a signal, not restore and continue (021/7, 8, 9, 9b;
  020/22–44).
- Emit a progress line every few minutes: the 600 s stream watchdog kills silent waits, and a BACKGROUNDED
  `sleep` is not a wait — only a FOREGROUND `until <condition>; do sleep N; done` advances the clock
  (018/6; 017/5).
- A `cd` inside a backgrounded bash command does not apply — use absolute project paths; `git diff > patch`
  after a `cd` into a worktree captures THAT worktree's diff; zsh EATS `$rev:path` (it is a `:s` history
  modifier), so spell `git show "${r}:src/…"`; `git grep --include=*.cs` fails under this shell, the
  spelling is `git grep -- '*.cs'` (017/31, 32; 019/7; 021/11).
- Predictions are written to a file BEFORE the first mutation; a control walk whose predictions are
  written after the results is evidence about nothing (arc-wide). A stage must reproduce the PRIOR stage's
  published readings before reading a new number of its own (015-A1..A6).
- A run whose inputs changed under it is not a result: a unit-suite run started before an edit and still
  running when it landed measures a tree that never existed (021/5b). Build the differential base at the
  CURRENT tip, not the one the last slice preserved (019/22-1).
- Probes, oracles, bisections and mutation copies are built OUTSIDE the repository and destroyed; a scratch
  `.cs` inside the tree is exactly the file the ownership audit refuses (017/20B; 020/18, 21–45).
- This file is a RUNNING LEDGER: replacing it wholesale once destroyed 42,150 lines and the loss was
  invisible until `git diff --stat`. Never replace it wholesale; edit §1 in place, append rows to §4 and
  lines to §2 per §0's discipline, then check `git diff --numstat` before reporting (020/22)
- `tasks/README.md` is touched only by a measured box-checking slice, verified by `git diff --quiet`
  everywhere else (020/32–45).
- Do not commit when the mandate reserves it; state the changed-path count exactly, and let the
  coordinator commit (016 stages 1–17; 020/32–45; 017 arc).
- Session-memory notes outside the repo can carry STALE instructions: `project_aot_vs_reflection_kernel_loading`
  once described `DogfoodKernelLoader` as current and forbade deleting the C# fallbacks; the type was retired at
  `3c963eb5d`, 021/12 flagged the note, and the coordinator rewrote it as SUPERSEDED on 2026-08-27. Treat any
  "the fallback is load-bearing under AOT" claim as stale unless re-measured (021/12)
- Visual IDE verification is UNDISCHARGED and was MEASURED, not inherited: `list_granted_applications`
  returns `allowedApps: []` with every grant flag false, and a grant needs an interactive approval dialog
  an autonomous run cannot answer. An integration suite is not a screenshot (016 N+3; 017/1–21; 021/4, 12).

## 3. Architecture facts

Structural knowledge the code does not state. Process lessons are in §2; per-slice proofs are in §4.

### 3.1 The method-body door and the expression cascade (015-B)

- **The claim rule is TYPE EQUALITY** (`ColumnarMethodBodyPlanner:299`, `valueType == returnType`), and
  that is precisely what makes the host's seven target-typed pre-passes and seven coercions *provably
  unreached*: `42 → int` is claimed, `42 → long` is declined to the adoption pre-pass that would emit
  `ldc.i8`. Raising it to `TypesEquivalent` is its own slice with its own corpus diff.
- **The production expression path is an ELEVEN-ARM CASCADE of root facades, not a dispatcher.**
  `EmitExpressionCore` calls four standalone owner facades first, then
  `ColumnarRangeIndexPlanner.TryEmitFromFacts`, which dispatches to each owner's OWN root facade. Routing
  the door at `TryAppendPlannableValueCore` would be a SECOND routing policy; the byte-identical move is to
  factor a `TryAppendRoot` out of that kind's `Plan` (between `PrepareV3`/`CompleteV3`) and call it from
  both.
- **Kind 8 (member access) has TWO cascade owners, and the external-static one is asked FIRST.** Arm 7 is
  `ColumnarExternalStaticMemberPlanner`, arm 8 is `ColumnarInstanceMemberPlanner`, both testing the same
  unqualified `kind == MemberAccess`. A door arm calling only the instance-member owner would emit the
  WRONG owner's bytes for any node both would claim, so the arm must ask both in cascade order.
- **Arm SEVEN falls through on a decline and sets no `nsharpOwned`; arm EIGHT sets
  `nsharpOwned = ClaimsRoot(…)` BEFORE `TryEmit`.** `EmitExpressionCore` answers a set-but-failed claim
  with `if (nsharpOwned) return false;`, so on arm 8 a claim that fails declines the WHOLE FUNCTION while
  at the door it only declines the body. That asymmetry is why arm 7 was separable and arm 8's widening is
  not — and it is measured in bytes: widening `TryGetComposedReceiverType` (the TYPE side) alone turns
  `return a[i + 1].X` from "compiles" into "the function is declined", exactly one body.
  `ColumnarInstanceMemberPlanner:338` therefore stays PLAIN, and any future widening must move the TYPE
  side and `TryAppendComposedReceiver` in ONE commit.
- **One open plan offered to TWO owners is safe only because of `ColumnarCodePlan.Rollback`**, which
  restores `OperationCount`, every pool count, `FragmentCount`, `OpenFragmentCount`, `ResultType = null`
  **and sets `Status = NotOwned`** — that last line is what lets the second owner's input gate see a
  pristine plan after the first opened a fragment and rolled back.
- **The plan-local MIRROR contract has TWO independent rules and they fire in an order the brief got
  wrong.** R1 = `ValidateAllUsed` (every pool entry must be referenced) runs FIRST; R2 = `ApplyLocal`'s
  assigned-before-`ldloc` is what actually kills a one-local scratch that READS its local. A fix touching
  only `ValidateAllUsed` would not have fixed the crash shape. The mirror exemption is PER SLOT, never per
  pool, and a mirrored plan may never be `Execute`d (replay declares one `LocalBuilder` per pool entry and
  would shift slot ordinals).
- **`HasValidV2Fragments` asks only `FragmentKinds[i] >= 0`** — it never compares the recorded fragment
  kind with the kind of the node `FragmentSourceNodeIndices[i]` points at. Fragment kind is DESCRIPTIVE
  metadata no plan invariant enforces (control C3 hard-coded the root fragment's kind and the whole
  7,166-block estate stayed green). It DOES reject a child fragment whose row range EQUALS its parent's,
  which is why a nested value frame is DECLARED (`EnableNestedValueFrame`) rather than fabricated.
- **Kind 57 (`checked`) has NO N# owner at all** — absent from `FacadeRootMayNeedFacts` and from
  `TryAppendPlannableValueCore`; its owner is `EmitExpressionCore`'s own `case 57`, so byte identity is
  against the DOOR'S OWN RECURSION (flip `bindings.OverflowCheckingEnabled`, recurse, restore). Inventing a
  `ColumnarCheckedContextPlanner` would have manufactured an owner the emitter never consults. **Kind 7
  (`Parenthesized`) is the same shape**, and the B16 decode adds the reason: `FacadeRootMayNeedFacts` and
  ALL EIGHT cascade owners' `MayPlanRoot` open with `UnwrapParentheses`, so for nine inner kinds the host
  never reaches `case 7` and the owner claims the OUTER node.
- **The RETURN position is not the VALUE position.** The host's kind-20 arm runs SEVEN target-typed
  pre-passes; its kind-24 (`:=`) arm runs NONE. One door serving both is wrong by construction — hence
  `TryAppendReturnValue` = `IsHostAdoptedReturnShape` + `TryAppendValue`, with the declaration loop calling
  `TryAppendValue` directly. The host ADOPTS a unary minus over an unsuffixed integer literal and emits it
  PRE-NEGATED with no `neg` row on every signed target, and `TryEmitIntLiteralAsType` reads the node kind
  UNWRAPPED — so `IsHostAdoptedReturnShape` must NOT unwrap.
- **Standing rule for refusing a host-adopted shape: a SUPERSET narrows safely, a SUBSET diverges
  silently.** Every parse/range disagreement in `IsHostAdoptedReturnShape` is built to fall on the
  REFUSING side.
- **The owner-scope "inherited value surface" family is CLOSED at four owners** —
  `ColumnarDirectCallPlanner`, `ColumnarConstructionPlanner`, `ColumnarRangeIndexPlanner`,
  `ColumnarInstanceMemberPlanner`. The surface is not a `TryAppend*` PARAMETER but the CHOICE BETWEEN TWO
  NAMED FORWARDERS (`TryAppendPlannableValue` = plain, `TryAppendConstructionValue` = rich); censused by
  parameter the literal answer is 28 false positives. **A ROOT is plain BY RULE**: it has no enclosing
  position to inherit from, exactly as it has no parent fragment to point at.
- **Declarable and bindable are TWO independent admissions.** `IsSupportedRuntimeTypeName` makes a type
  *declarable*; an explicit per-member row in `ColumnarExternalBindingPlans.GetInstanceCallPlan`'s
  `System.Type` table makes a call *bindable*. With the type list alone, `a.get_Module()` still declined.
- A VOID-returning call is a THROW, not a decline: `CompleteFragment` refuses a `System.Void` result
  unless `SchemaVersion == ScalarSchemaVersion() && fragmentIndex == 0`, which a method body satisfies
  neither of.
- The type-identity predicates are THREE and must never be merged:
  `ColumnarTypeEquivalenceFacts.TypesEquivalent` (ported whole from C# in B10),
  `ColumnarReferenceConversionFacts.ExactTypeShapeMatches`, `ColumnarBaseTypePlanner.SameInterfaceType`.
  Their differences (enum arm, by-ref arm, `TypeBuilder` arm, recursive vs reference-identity generic
  definitions, reflection guards) are tabulated at the new owner's head so the next reader does not merge
  them.
- The overflow flag is provably FALSE at every `EmitBody` entry (no initializer, written only inside
  `EmitExpressionWithOverflowChecking`, all seven call sites on fresh emitters) and is routed anyway, so
  the door reads the same field the host reads rather than reproducing a conclusion about it.
- `ColumnarPrimitiveBinaryPlanner` and `ColumnarConditionalPlanner` partition kind 12 by operator LENGTH:
  `HasExactOperatorText` tests `length == expected.Length` before comparing text, so two-character `&&` can
  never match one-character `&`.
- There is no argument-position rule in the IR; the only rule in reach is about plan ROOTS
  (`allowOrdinaryIntIndex = parentFragment >= 0`), and the direct-call owner's type-discovery SCRATCH
  applied it to a value never at a root — the TYPE side refused what the APPEND side would have planned.

### 3.2 The plan-row IR and its executor

- `ColumnarCodePlan.nl` (2,155 lines) is the plan-row IR and `ColumnarCodePlanExecutor.nl` (2,625 lines) is
  the only `.nl` file naming `OpCodes`; it carries `ExecuteMethodBody`, a schema validator and a
  stack-height validator, driven from 14 `Execute(` sites. Together they are 4,780 N# lines. The
  "future plan-row lambda-body emitter" the 015 roadmap waits on ALREADY EXISTS AND SHIPS: it is not
  blocked, it is UNDER-COVERED at 10 of 21 statement kinds and 7 of 27 expression kinds.
- **`Validate` dispatches by SCHEMA.** `ApplyInstruction` is the TYPED model and runs for v2/v3 ONLY; a
  schema-v4 method body runs `ValidateMethodBodyStack`, a HEIGHT model that does not type branch
  conditions. `Isinst`/`UnboxAny`/`Pop` are method-body-ONLY by construction. `ExecuteV3` and
  `ExecuteMethodBody` share `EmitInstruction`, so byte identity across schemas is BY CONSTRUCTION — the
  only thing a claim has to reproduce is the ROW SEQUENCE.
- Schema v4 is a documented SUPERSET of v3 and has NO fragments at all: neither
  `ValidateMethodBodySemantics` nor `ExecuteMethodBodyRows` reads `FragmentCount` or the fragment columns,
  so a body-spanning root is not expressible and a method-body plan admits MANY roots.
- The IR does NOT bind locals as hoisted fields: `PlanLocalOperand` exists at every layer with five
  production owners, including the iterator planner. But a `LocalBuilder` cannot exist at plan time (the
  driver holds no `ILGenerator`), so a kind-24 `:=` publishes a PLAN-LOCAL, not into `bindings.Locals`.
- Narrowing is an EXECUTOR concern needing no new row constant: `Emit(OpCode, LocalBuilder)` narrows locals
  itself, `Emit(OpCode, short)` NEVER narrows `Ldarg`, and the short-form ordinal family is exactly four
  (`Ldarg_0..3`). `Ldarg_S` is a TWO-half widening (the opcode name AND a `System.Byte` emit operand
  `IsSupportedEmitOperand` refuses), so ordinals ≥ 4 stay long-form deliberately.
- The modeled `OpCodes` allowlist lives in ONE file with ONE consumer
  (`ColumnarExternalBindingPlans.IsSupportedOpCodeMemberName` over three family predicates, 108 names);
  the three-family split is a linter-guard artefact.
- The pools already carry structural signatures beside the reflection handles
  (`AddMethodWithSignature` / `AddConstructorWithSignature` / `AddFieldWithSignature`, used by 12
  production planners) — which is what makes a `MetadataBuilder` second executor cheap. Its one named
  prerequisite is giving `AddType` the same treatment, because the residual `Type` operands are
  `TypeBuilder`/`GenericTypeParameterBuilder` handles `MetadataBuilder` cannot consume.

### 3.3 Owners, planners and facades

- N# planners run at the FRONT DOOR of every emitter dispatch: 26 distinct
  `Columnar*Planner/Resolver/Facts` owners are consulted before any C# residual arm can run. Residual
  switch arms are whole-subtree-exit servers for non-plannable OPERAND bands, not fallbacks — the
  FENCED-CALL ARCHITECTURE established by task 004 and mirrored by 005.
- Admitting an external type is catalog DATA in ONE N# file (`ColumnarExternalBindingPlans.nl`:
  `IsSupportedRuntimeTypeName`, `TryGetRuntimeTypeName`, `GetStaticMemberPlan`), gated by
  `ColumnarIlEmitter.IsSupportedType:397` — no C#, no kernel, no OpCodes allowlist. Adding a CALL PLAN
  alongside it can BREAK what the ordinary direct-call resolver would have bound: a supported instance
  plan pre-empts `ColumnarOrdinaryRuntimeDirectCallResolver` TERMINALLY (`plan.Rollback` + `return false`,
  never falling through), and no plan can describe a VALUE receiver (`ValidatePlanForm` demands `Call`
  while the legacy host demands `CallVirtual`).
- **`ColumnarExternalBindingPlans` is the LEGACY whole-subtree planner's surface, not the binding
  authority.** `ColumnarDirectCallPlanner` falls through to `ColumnarOrdinaryRuntimeDirectCallResolver`,
  which binds any suitable public non-generic instance method on a receiver already in
  `IsSupportedRuntimeTypeName`. A member missing from the catalog is NOT evidence it does not bind —
  measure by execution. This is the root cause of the phantom "two-row catalog wall" 017/55 priced and
  017/56 destroyed.
- A catalog row is FIVE rows until a sweep says otherwise: the analyser's table, the emitter's plan/type
  catalog, and the emitter's own external assembly SCAN (`ExternalAssemblyScan.CommonAssemblyNames`) are
  THREE separate tables. With the type rows in and the scan row missing, `XDocument.Load` resolved to
  nothing at emit time and **the decline was SILENT** — `TryResolveExternalStaticOwner` rolls back without
  recording a site.
- `System.Xml.Linq` is a PURE FACADE: `GetExportedTypes()` in a `MetadataLoadContext` answers ZERO (the
  load context does not follow type forwarders) while `System.Private.Xml.Linq` answers 25.
  `System.Xml.ReaderWriter` is the same kind of facade.
- Columnar emission runs on a DEDICATED WIDE-STACK THREAD (64 MB since `195028aa9`); the NL103 decline
  trace is thread-local and must be built on that thread (`7f4e727d6`).
- The feed the self-host loop consults is `~/.nuget/local-feed`; `~/.nsharp/packages` is not.

### 3.4 The analyzer's end state (017) and what keeps `Analyzer.cs` alive

- `Analyzer.cs` is a **REVIEWED ZERO-POLICY MECHANICAL HOST**: 23,060 → 2,962 lines (−87.2%) over 67
  slices, 186 extents in SEVEN classes with an executable classifier reporting `UNCLASSIFIED = 0`. It is
  NOT deleted and will not be — the task-021 `MetadataLoadContext` assembly-loading surface (30 extents /
  655 lines, redrawn to 25/492 by 021/9) keeps it alive — so 017 closed on the checkbox's SECOND arm.
- What survives: 91 field declarations, the constructor plus 26 `Create*` factories, the entry handshake
  (23 ordered operations), 29 driver loops, 5 dispatches, the ambient bracket and scope pair, and the MLC
  surface. Outside that surface the whole shell (2,276 lines) contains exactly 14 conditionals and 2
  null-coalescing operators, every one named.
- The semantic model is 80 `Analyzer*.nl` owners / 47,173 production lines with 73 contract files;
  contracts went 1,554 → 3,890 across the arc. FOUR toolset repins in 67 slices (12A / 20A / 22 / 48) and
  ZERO from slice 49 on.
- **The driver protocol.** A resumable walk exists when the step COUNT or a step's OPERANDS depend on an
  answer the walk does not have yet; report-order-only gives an answer-free request loop; neither gives a
  whole move with no driver. Step kinds are pinned BY VALUE by ~40 contracts, so retiring a kind KEEPS
  ITS GAP rather than renumbering. One state serving several walks needs PHASE BANDS, never a shared
  counter. A phase range routed BEFORE a fall-through must be disjoint from everything the fall-through
  can see ("the next free number" does not measure that). A driver may drive a driver and stay
  zero-policy. `Kind` is what the DRIVER performs; `Pending` is what the WALK does with the answer.
  `DriveStatementSequence` is the estate's only driver with no `Supply`, so its ANSWERS is 0 BY DESIGN;
  everything else is `ENTER == RESULT` and `STEP == ANSWER`.
- Owner lifetime is a first-class design axis: collaborators the metadata load context REBUILDS
  (`_wellKnownTypes`, `_assignability`, `_clrTypeConversion`, `_patternReachability`, `_flowNarrowing`)
  arrive at `Begin` and ride the state or go behind a `Create…` factory; `readonly` built-once
  collaborators are HELD; an owner that needs BOTH rebuilt collaborators and per-analysis dedupe state is
  constructed once and TOLD through a setter (`SetMetadataCollaborators`). An owner's fields never change
  after construction. A cache can be part of the ANSWER (the external-type probe caches under the BARE
  spelling and short-circuits the import loop), which is why that owner is never rebuilt.
- A resumable owner's bracket closes in `Supply`, not in the phase handler — the handler runs one call
  later than the C#'s `finally`. A walk with more than one SECTION needs TWO counters, `Phase` (returns to
  0) and `Stage` (only moves forward), or it re-enters a finished section.
- The `_errors` LIST is passed BY REFERENCE and never owned, so report ORDER is exact by construction;
  `AnalyzerDiagnosticSink` owns the CONSTRUCTION of every semantic `CompilerError` and both doors
  (`Report` and `ReportBuilt`) append to the same list.
- **The NL202 front door is the only guard against `EmitValueCoercion`'s silent no-op** for closed
  generics over emitted user types — without it, `List<Rs>` into a `List<Pt>` field is a type-confused
  read at runtime.
- A live UNBOUNDED RECURSION is recorded and NOT fixed: `IsAssignable(Shape <- Money)` with a duck
  interface target over a class carrying both an int arm and a mutual-cycle implicit conversion
  stack-overflows IDENTICALLY in both trees; the guard bounds `HasImplicitConversion` but nothing bounds
  the root's re-entry through the conversion's return type. Unreachable from the corpus and the suite.
- `_referenceLoadFailures` is WRITE-DEAD, so half the NL923 pairing rule's input never arrives; the owner
  holds the table BY REFERENCE, so the rule starts working the moment the loading surface starts writing.
- The MLC quarantine is TOTAL: zero references to the diagnostic sink, the span reader, `_errors`, any
  `Report`/`Warn`, the semantic model, the binding map, any driver, any dispatch, the scope stack, and zero
  uses of `ErrorCode` — replacing it cannot move a squiggle.
- 017's alias funnel is blocked by IDENTITY, not policy: `Analyzer.cs:369` declares an alias as a FRESH
  `AliasTypeInfo` while `AnalyzerDeclarationContext.filesByType` is keyed by TypeInfo REFERENCE identity
  (measured `aliasSeen=36`, declaration-context branch 0, `ResolveType` branch 36).
- Under a `MetadataLoadContext` a `CustomAttributeTypedArgument`'s `ArgumentType` is a PROJECTED type that
  fails `== typeof(bool)` while its `Value` is a live boxed bool — test the VALUE. Roughly half of what the
  analyzer sees is MLC, which is exactly how the language server sees an external assembly, so every
  differential grid runs each cell twice.

### 3.5 The parser owner (016)

- `src/NSharpLang.Compiler/Parser.cs` is DELETED (7,116 lines) along with the `ParseResult` record (14) —
  7,130 C# lines out, 0 in. `ColumnarParserRecovery.ParseFileAst` is the sole parse + ordered-diagnostic
  authority for production and for every test, so **there is no second parser left to serve as an
  independent oracle**; every golden written after the cutover is a behavioural snapshot.
- The arc rests on ONE shared `_panicMode` flag (suppress-while-set, set-on-report, reset only at boundary
  sync points), and WHICH boundaries reset it is not uniform: the union per-case reset and the
  object-initializer per-element reset DO; match's per-case `EnsureProgress` and `with {…}`'s do NOT, so
  two bad match cases report ONCE. Interpolation holes live in a SEPARATE panic universe — each hole gets a
  fresh sub-Lexer/sub-Parser and its errors are appended, bypassing the outer gate.
- **SHARED-PANIC COUPLING is the structural reason no bounded parser deletion existed**: removing a
  family's inline report also removes its `_panicMode = true` side effect, changing suppression for every
  other family. That, ~8% coverage (~20 of ~256 diagnostics) and a divergent 10-pass per-token-scan panic
  model are the three independent reasons the unwired `ColumnarSyntaxDiagnostics` arc was DELETED, not
  wired. Never resurrect the scanner.
- `ParseFileAst` returns diagnostics in RECORDING order; `ParseFilePreamble` returns them POSITION-SORTED.
  Every consumer that prints `result.Errors` sees the unsorted one, and nothing had stated it.
- Declaration-name errors are KEYWORD-ANCHORED (the declaration keyword's span overrides the offending
  token's in all three variants). Top-level recovery MANUFACTURES `ClassDeclaration`s named `<error>`, and
  the `<error>` placeholder does not only leak into the MESSAGE — it SIZES THE UNDERLINE.
- Malformed literals belong to the PARSER model, not a lexer lane: the already-N# `Lexer.nl` only
  CLASSIFIES (`Token.IsTerminated`) and emits no diagnostic.
- The `>>`-split discipline (`_splitGreaterDepth`) is owed debt that SURVIVES boundaries — Parser.cs resets
  it only inside `SynchronizeToNextDeclaration/Statement`.
- The EOF-length-clamp class is PERMANENTLY UNMATCHABLE at the `CompilerError` level: the parser derives
  lengths from `Current.Value.Length` = 0 at EOF and the CLI's `DiagnosticSpanResolver.Resolve` clamps
  0→1 for display, so a contract asserting 1 diverges from the model and one asserting 0 cannot be
  oracle-confirmed.
- **The AST is N#-owned.** The `CompilationUnit` bridge block was an ASSEMBLY-DEPENDENCY block, not an
  emitter gap (Compiler → BootstrapServices, never the reverse), and C# `record`s cannot derive from N#
  classes — so `AstNode → {Expression, Statement, Declaration} → ~110 subtypes` had to move
  ALL-OR-NOTHING at the base, into `Expressions.nl`/`Statements.nl`/`Declarations.nl`. N# emits data
  members as public FIELDS (every reflector needs a `GetProperty → GetField` fallback) and emits classes
  WITHOUT the CLR abstract flag. The record-feature audit that licensed the migration found no
  `with`-expressions and no positional deconstruction anywhere in src, and exactly ONE value-equality
  dependency (`Analyzer.cs:18169`'s `Properties.Except(…)`), which became a reference-based diff.
- **016's ONLY remaining follow-on is BOOKKEEPING, not ownership**, and it must NOT be a bulk deletion:
  2,021 parser assertions (356 facts) across `ParserTests.cs`/`ParserErrorTests.cs`/`ErrorHandlingTests.cs`/
  `EventSubscriptionTests.cs`/`LocalFunctionTests.cs` were REROUTED to the N# owner rather than translated.
  Rerouted, each is an executable proof obligation over a 2,021-assertion synthetic surface the native
  corpus never reaches; deleting them trades executable coverage for prose. (020 then migrated the
  parser-subject files by WRITING N# contracts, closing bucket (a) — see §4's 020 arc.)

### 3.6 The tooling survivors (019) and the systems analyzer (018)

- 019 opened at 7,739 lines / 341 member extents across seven C# files and closed at 520 / 55 across
  three. FOUR were DELETED WHOLE with ZERO insertions — `Linter.cs`, `Formatter.cs`, `DocQuery.cs`,
  `NullabilityMetadata.cs` — because the N# owner keeps the NAME, the NAMESPACE and every public
  SIGNATURE, so consumers are byte-unchanged. THREE are reviewed non-growing mechanical hosts:
  `CodeIntelligenceService.cs` 153, `OutputFormatter.cs` 271, `CompletionEngine.cs` 96, each with an
  executable `POLICY = 0` verdict and a non-vacuity control on the pre-cut file.
- **The deletion arm is available only when every type in the file's public signature is already N# in the
  same namespace AND no C# type from the DEPENDENT assembly appears in it.** `CodeIntelligenceService.cs`
  could only become a host because `MultiFileCompiler`, `ProjectFileParser` and `ProjectConfig` are C# in
  the assembly that depends on BootstrapServices — a reference back would be a cycle. `ProjectSnapshot`'s
  declaration at `CodeIntelligenceService.cs:1851` is what kept `CompletionEngine.cs` from being deleted.
- N# spells member visibility by CASE, so a moved type's surface is wider than the C#'s (`DocQuery` went
  3 public / 17 private to 21 public / 0 private) — stated, not hidden.
- The estate is the BOTTOM of the dependency graph: no `.tests.nl` in BootstrapServices can EVER reach
  `Analyzer`, `SemanticModel`, `BindingMap`, `CodeIntelligenceService`, `MultiFileCompiler` or a CLI
  command; those need a `tests/native/*` project with a `Compiler.dll` dep.
- 018 closed `SystemsAnalyzer.cs` at 1,160 lines (2,390 → 1,160, −51.5% over eight slices) as a reviewed
  zero-policy mechanical host with `grep -c NSYS = 0`, `UNCLASSIFIED = 0` and `MISMATCHED = 0` — the
  completion assertion is a ZERO, not a line count. Twenty systems N# owners / 3,581 lines.
- Deletion was never available there: the `MultiFileCompiler` seam consumes `SystemsAnalyzer.Analyze`
  (`:318-328`, routing findings through the already-N# `SystemsFindingDiagnostics.ToCompilerError`) and no
  N# type can host a walk that re-enters the analyzer's own semantic models.
- `AnalyzeFunction` is RE-ENTRANT through `MergeDeclaredCalleeSummaries`, which reports against the OUTER
  caller — which is why the current subject cannot be sink state, and why that member's transitive
  closure is 118 members / 1,402 lines (the whole file). It is a DRIVER; only its policy moves.
- There is NO dedupe in the finding sink and there never was; what IS observable is the STABLE sort (file
  `OrdinalIgnoreCase` → line → column, ties keep insertion order) plus two call-path compositions.
  `systemsReport.functions[]` is DFS ROOT ORDER, not file order.
- The allow set has TWO testers and they are DIFFERENT tests: `WalkContext.IsAllowed` prefix-widens
  (`effect:`) and ORs across the block-level stack, `MergeDeclaredCalleeSummaries` uses exact `Contains` —
  they agree on all 180 function-level cells and diverge on 173 of 1,440 block-stacked ones.
- 018's territory boundary is FILE-scoped: `SystemsAnalyzer.cs` + `NSYS*` only. The SoA direct-column call
  gates lived in `Analyzer.cs`, so 017 took them.

### 3.7 The native test runner (020) — capabilities built vs proven unnecessary

- 020 named seven runner capabilities and built exactly ONE: **table-driven cases**, shipped as an N#
  LOWERING (one R-row declaration becomes R independent `[Fact]`s, so per-case identity is free and the
  emitter did not grow). The whole surface was already in the language except emit; the gap was ONE scan
  function, `TopLevelPlainTestHeaderEndsAt`, which accepted only `test STRING {`. `[Theory]`/`[InlineData]`
  was rejected on two independent grounds: it needs new `ColumnarIlEmitter.cs` the ratchet forbids, and a
  `[Trait]` is per-METHOD so N failures would hide behind one line.
- PROVEN UNNECESSARY: `skip` (zero `[Fact(Skip=…)]`, `SkipException`, `[ConditionalFact]` or filters across
  2,818 attributed methods in 279 classes; the one true `Skip=` is `DockerFactAttribute` in a project the
  gate never runs, and N#'s `skip` is a STATIC modifier that cannot express a RUNTIME precondition);
  process launch as a RUNNER capability; and a native project taking a PROJECT REFERENCE (the decline is in
  the EMITTER'S TYPE RESOLUTION, not in how the assembly arrives). SERVED ALREADY: setup/teardown, async
  `Task`, async `ValueTask`, structured failure JSON, whole-run timeout. `nlc test`'s JSON envelope is
  byte-for-byte the schema it had at slice 1. **Unused runner infrastructure is not completion.**
- `nlc test` counts each TABLE ROW as a test, so a project's total and its declaration count diverge.
- The `tests/native` estate is compiled and run by the LIVE CLI, so a capability and its first consumer can
  land together with NO toolset republish — unlike the BootstrapServices estate, which the PINNED toolset
  compiles.
- Terminal 020 census over all 24 surviving `tests/*.cs`: bucket (a) = 0, (b) = 110, (c) = 85, (d) = 350
  over 545 bodies. The 195 (b)/(c) bodies retire with their C#-owned SUBJECTS under 021 and 015.
  `Program.Testing.cs` is 617 lines with 43 kernel call sites over 34 N#-owned entry points; its residue is
  three internal invariant sentences on CLR-handed impossible paths.

### 3.8 021's terminal state and the measured AOT direction

> **CORRECTED 2026-09-01 by two decodes proven by execution (a NativeAOT `osx-arm64` publish + run).**
> `MetadataLoadContext` is AOT-compatible (`ilc` zero errors; its `IL3050` are false positives on
> metadata-only overrides), and so is `PersistedAssemblyBuilder` — the emitter's ONLY builder (one site,
> `ColumnarIlEmitter.cs:3991`; zero `DefineDynamicAssembly` sites) — including with an MLC `RoAssembly` as its
> core assembly and MLC types in every signature position (a 2,560-byte assembly saved and read back clean).
> NativeAOT forbids exactly two things this compiler does: loading an assembly into its own process
> (`Assembly.LoadFrom` → `PlatformNotSupportedException`; `Assembly.Load` → `FileNotFoundException`; the
> emitter's runtime-loader sites `:2794/:9314/:9329/:9359` plus 3 N# sites) and generating code to RUN
> in-process (`DefineDynamicAssembly`, unused). Consequences: the "replace MLC with `MetadataReader`" task is
> dead; the `MetadataBuilder` second executor is OFF the AOT path (ownership work only — and Reflection.Emit is
> already spellable from N# while `MetadataBuilder` is not, so the 015-E declaration host ports to N# ON
> Reflection.Emit with no catalog widening); the AOT work is a drafted task 022 — (1) AOT capability floor over
> the full builder/opcode/131-member surface, (2) one type universe: delete the runtime-loader half and
> re-source `metadataPath` off `Assembly.Location`, (3a) admit `new` on a `nuget:` type → (3b) retire the
> `Analyzer.cs` MLC quarantine, (4) serve the editor from the analyzer's universe (VS Code-gated),
> (5) a NativeAOT `nlc`. Census at `8cf40128a`: 105/403 production `.nl` name reflection types (70 %
> `Columnar*`, 20 % `Analyzer*`); 131 distinct reflection members, only 4 MLC-hostile; `MetadataLoadContext`
> IS spellable from N# — the one wall is `new` on a `nuget:`-sourced type. Filing task 022 and shelving the
> writer are pending the owner's decision. The bullets below are the 021 audit's record as written and are
> superseded where they conflict with this note.

- The closing contract is a CONJUNCTION of four: every surviving non-N# file must be *pre-existing,
  non-growing, mechanical, and explicitly reviewed against a canonical N# owner*. Three PASS.
  **`mechanical` FAILS for `Columnar/ColumnarIlEmitter.cs`** — 144 user-facing sentences at 21,519 lines,
  72 of them decline sites reaching users as `NL103 Declined at <site>`, the identical class 021/2 already
  migrated out of `ColumnarProgramInputBuilder.cs`. So IL generation has no single N# owner and the 021 box
  stays UNCHECKED. Naming a file's future owner is not the same as the file being mechanical today.
- The named remainder is exactly three items: the emitter (four `015` sub-tasks plus the AOT
  metadata-writer task), the `MetadataLoadContext` quarantine (17 members plus nested
  `NSharpMetadataResolver` → the AOT external-type-model task), and visual IDE verification.
- **The inherited AOT premise is DEAD.** `DogfoodKernelLoader` does not exist — retired at `3c963eb5d`
  ("Static bind columnar kernels and retire dogfood loader"), an ancestor of the tip. The real blockers are
  (a) Reflection.Emit in the emitter — 1,190 `OpCodes.` sites, 177 `TypeBuilder`, 52 `ILGenerator`, 27
  `MethodBuilder`, 9 `AssemblyBuilder`, 5 `ModuleBuilder`, 2 `PersistedAssemblyBuilder`, plus three
  `Assembly.LoadFrom`/`Load` sites and `Program.Testing.cs`'s collectible `AssemblyLoadContext` (under a
  single-binary AOT `nlc`, `nlc test` cannot load an emitted assembly at all and the native runner must
  SPAWN the built test executable); and (b) the analyzer's MLC external TYPE MODEL.
- **The AOT leg is measured shut at the language level**: `MetadataReader` is unspellable from the estate
  in five spellings, and behind that, 74 of 396 production `.nl` files open with `import System.Reflection`
  and 99 name a reflection object type on a line of code. Replacing MLC is a whole external-type-model
  swap across a quarter of the estate — a TASK, not a slice. The mechanism is already half-reachable:
  `System.Reflection.MetadataLoadContext` is ALREADY a `nuget:` dependency and
  `ExternalAssemblyScan.CreateMetadataLoadContext` already builds one from N# by reflection-invoke.
- **THE AOT DECISION, not to be re-litigated**: the plan-row body emitter targets the EXISTING
  Reflection.Emit `ColumnarCodePlanExecutor` FIRST; `MetadataBuilder` arrives LATER as a SECOND EXECUTOR
  over the SAME plan rows. It is NOT built AOT-first, because coverage is the scarce thing and backends
  are cheap once the IR is total; the end state is one N# IL owner with two backends.
- **The editor and the analyzer see two different type universes**: the LSP's `_loadedAssemblies` is THREE
  assemblies (`typeof(object)` and `typeof(List<>)` are both `System.Private.CoreLib`) against the
  analyzer's 27 `CommonAssemblyNames()` plus project references. Completion cannot offer a type from a
  user's package and hover cannot name one. The fix is serving the editor from the analyzer's universe,
  which is the AOT type-model task — **do not "fix" it by adding a fifth seed name**.
- `HoverHandler.ResolveIdentifier` is unreachable for any document INSIDE a workspace (a 666-position ×
  2-configuration sweep reaches its formatters zero times; `DocumentManager.FindProjectHover` answers
  first) and IS reachable for a loose `.nl` opened outside the server's workspace root.
- **The playground is a SECOND IMPLEMENTATION of N# semantics** and 7 of 14 comparable programs already
  answer differently from `nlc run` (int and double division by zero, `0.1+0.2==0.3` under a 1e-7
  tolerance, record and union `print`, `"n=" + 1`, shorthand union binding). Routing it to the canonical
  path is not a refactor, and there is no process to spawn and no Reflection.Emit inside a browser tab.
- A hard boundary no future N# capability removes: a C# attribute argument must be a compile-time
  constant, so an attribute name is the one residue that can never be *defined from* an N# owner. The same
  holds for an MSBuild property default. That is why the eleven JSON-RPC 2.0 member names that stay must be
  ecosystem facts.
- The `(b)` bucket — retires with its subject — MAY NOT RETIRE UNPINNED: `DaemonProtocol.cs`'s wire DTOs,
  `QueryCommand.cs:108`'s ordering and `Program.cs`'s diff labels are pinned through the SHIPPED BINARY by
  `tests/native/cli-command-contracts`, which outlives any C# behind it.
- The `.nl`-vs-`.cs` ratchet asymmetry is the DESIGNED GRADIENT: `.nl` carries no rows and grows freely,
  every `editors/vscode/test/suite/` row sits at its ceiling.
- The one operative campaign rule for a residue: **"define in terms of, do not restate"**. `IsBuiltInTypeName`
  reads `BuiltInSimpleType(name) != null`, so sixteen of eighteen members cannot drift;
  `GetNativeTestOutcomeRank` reads the three outcome kernels rather than restating three literals, which
  closed a real gap.

### 3.9 The 015 completion roadmap, re-measured (superseded in part)

The roadmap's three-way classification of `ColumnarIlEmitter.cs`'s residual policy surface is correct about
WHAT lives where and stale in three named ways: every line number is stale by +24 to +124; **"MOVABLE —
EXHAUSTED" is FALSE** (that sweep read the dispatch ARMS and never the HELPERS — a name-match of all 449
emitter members against every production `.nl` `func` returns 34 hits / 2,706 C# lines, whose coherent
residue is a 25-member / 396-line / 286-call-site type-admissibility family with a live N# owner on every
row, i.e. duplicated semantic authority, which became `015-A`); and blocker #1's "future plan-row
lambda-body emitter" ALREADY EXISTS AND SHIPS. Blockers #2, #3 and #4 were re-probed at `6fcb41f64` and
HOLD.

- **MOVABLE.** Interpolation string-classification splits were the only clean movable family and
  `TrySplitBaseCall` was the last. Two marginal remainders DECLINED as not-clean-decision-deletions: the
  decimal-literal VALUE parse (fused with reflection-backed ctor emission) and the entry-point return-shape
  rule (already N#-owned for async; the residual is reflection-typed return wrapping).
- **BLOCKED-WITH-RECORD #1, the LAMBDA-TAKING FAMILY** (the dominant block): `case 9` →
  `TryEmitEnumerableExtensionCall`, `TryEmitExplicitEnumerableExtensionGenericCall`,
  `TryEmitLambdaLiteral` + `EmitLambdaBody` (a recursive C# sub-emitter), `BodyReferencesEnclosingChain`,
  the `<>c__DisplayClass` capturing residual, and two preflight members. Stages 1–3a landed
  (signature/capture-set/return-type SELECTION → N#); 3b/4/5/6 are gated on the plan-row lambda-body
  emitter. **B inherits a constraint it must not soften**: a lambda body cannot be routed shape-by-shape
  with the C# sub-emitter kept as a fallback — that is a shadow route and duplicated authority; the cut is
  gated on the planner's coverage being TOTAL for the bodies it claims.
- **#2, the C# PREFLIGHT TYPING ENGINE** (`TryGetPreflightExpressionType` + family, 8 members / 629 lines,
  36 call sites on the root alone): reflection-bound expression-TYPING authority serving interpolation
  parsed holes and lambda return inference. Candidate (a) is PROVEN load-bearing — it types the USER's own
  enclosing-type statics, not catalog facts — so rerouting it is the forbidden
  add-a-planner-for-a-relocation anti-pattern. Retires via a real N# typing-owner port.
- **#3, the LIVE case-12/13 RESIDUAL FAMILIES** (~227 lines): short-circuit `&&`/or-else, null-comparison
  and coalesce over nullable+ref, signed `+ - * /`, ordering, ref-identity equality on user reference
  types, string+char concat, `String.Concat` pair, and `case 13` ternary. All self-emit-load-bearing by
  the four-surface probe. They retire ONLY as their non-plannable OPERAND forms become N#-plannable
  (member-chains-on-call-results, dictionary indexers, enum string constants) under the four-surface gate —
  never as a relocation.
- **#4, the BLOCKING-AWAIT MODEL** (`case 53` `TryEmitBlockingAwait`, 52 lines, plus the `case 73`
  await-foreach consumer; the await family is 5 members / 245 lines). The accepted synchronous
  `GetAwaiter().GetResult()` model retires when REAL async-func lowering lands.
- **#5, INTERPOLATION CHAIN / PARSED-HOLE RESOLUTION**: chain tokenization is intertwined WITH reflection
  member/local/getter resolution and parsed holes route through #2. No clean string-classification split
  remains; retires with the preflight port.
- **MECHANICAL (the target end state, already non-growing)**: control flow and structural statements
  (block, if, while, for, return, break, continue, try/catch schema-4 region ops, lock, throw, print, var /
  typed-local / tuple-deconstruction lowering, assert and assert-throws, expression-statement assignment,
  the StatementExits mirror); the mechanical expression arms (parenthesized 7, checked 57, spread 64,
  unary 11, is/as 46/47, must 45, postfix 44, the match/pattern-test family, index reads 10, anonymous
  objects 59); construction/with/record/field-init (15/58/36/42, 52, record member synthesis, field init);
  iterator/async hosting (yield 72, foreach 29, MoveNext/state machine, async fault guards); and
  type/member definition (DefineType/DefineMethod/DefineGenericParameters, union and generic declaration +
  constraints, delegate mapping, bare-static and ref/out-deref reads (case 6), typeof, interpolation
  cast/equality/call-argument emit, base-call reflection RESOLUTION).
- **Campaign order (015-A → B, with C folded in and F riding along → D; then E and the AOT writer
  together).** `015-C`'s ruling: do NOT build a standalone N# typing owner — fold the typing answer into
  B's body planner, since a plan-row builder must already know each subexpression's type to pick opcodes;
  only the interpolation parsed-hole path needs its own entry point. `015-E`'s ruling: the declaration host
  `TryEmitColumnarAssembly` (2,024 lines / 41 decline sites / 57 sentences) is NOT a 015 ownership target
  and must NOT be cut by moving message literals (the 016 Stage-0 precedent) — it retires with the AOT
  metadata writer. `015-F`'s operand unlocks are not schedulable as slices at all: an unlock adds N# and
  deletes no C# until `case 12`/`case 13` go whole.

## 4. Arc records

One row per slice, newest first within each arc, verbatim from the slice records. The commit cell carries
the LANDED coordinator commit (`(landed)`; proved by subject/body and `--numstat` against the row's own
counts) — the records themselves were written before the coordinator committed, which is why some cells
also carry the decode/baseline tip the slice measured at. Only non-slice notes carry `no commit`.

### 4.1 Task 015 — the emitter (box UNCHECKED, reopened at `6fcb41f64`)

Outcome: 015 does not complete and its box stays unchecked by design. The `015-A` arc (duplicated
type-admissibility authority) CLOSED at `87afbcb39`, taking `ColumnarIlEmitter.cs` 21,519 → 20,984 (−535
lines, −35 members, 476 extent lines across 35 members, 308 call sites rerouted, ten behaviour fixes
carried). The `015-B` arc (the method-body door) opened at `9bd9aa222` and has landed B1–B15, taking the
emitter to 20,784 / 19,768 non-blank and the BootstrapServices estate 7,030 → 7,190 blocks; B16 (door kinds
7 and 55) is the active slice at `40e0cc20e`. Only three B-slices carry commits (`9bd9aa222`,
`b99b7dc6f`, `d0e0faa3f`); the rest are recorded against their decode tip.

#### The reopening decode (no cut taken)

| slice | commit | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| FORMAT-DISCOVERY WIDENING + the estate reformat | two commits (branch `stream/format-tests-widening` off `385b7e8d1`) | **`FormatCommandKernels.ShouldFormatDiscoveredPath` stops refusing the `.tests.nl` SUFFIX**, and its two now-dead helpers `PathEndsWithTestsNl`/`PathEndsWithAsciiIgnoreCase` are deleted, so `nlc format --project X` and `nlc format <file>` finally answer the SAME question about the same file. The `tests/fixtures/**` rule stands and is now asserted for the suffix too. `tests/CliParityAuditTests.cs` moves 2/2 lines because its discovery fixture used a BROKEN root `Program.tests.nl` as a skip exhibit — discovery would now find it, so that exhibit becomes canonical `.tests.nl` source and the broken one moves inside the excluded fixtures tree where it proves the rule covers the suffix. **`FormatterWalkState.Snapshot`/`Restore`/`FormatterPositionSnapshot` and their four contracts are DELETED** with the 33-line header that explained the measurement pass: the width rule that measured expressions is gone, so the pair had no product caller, and it must never get one — a snapshot around anything that can emit a comment rolls the cursor back and emits that comment twice. The second commit is the mechanical reformat the wrapping slice measured but deliberately held | **`--check` DOES NOT FORGIVE A DECLINE, SO THE CENSUS HAD TO COME BEFORE THE REFORMAT, NOT AFTER.** `FormatSource` throws on both a front-door parse error and a `FormatSafe` decline; the per-file `catch` sets `failed`, and `GetCompletionKind(failed:true, …)` returns 1 — so a decliner inside a gate path is a HARD Step 2b failure, not a silent skip, and the early return means `--check` then never prints WHICH files needed formatting. The census found **23 declines in two families, and the eight the brief named were only one of them**: 8 reparse-gate declines (`tests/native/**`, the raw-string family plus `ColumnarEmitFacts.tests.nl`) and **15 `Formatter does not handle expression type: AllocExpression` on plain `.nl`** under `docs/design/systems-samples/proofs/**` and `artifacts/**`. The 15 are NOT the widening's doing — they are non-`.tests.nl` paths discovery already walked — which corrects the pre-flight worry: **`nlc format --project .` at the repo root ALREADY exited 1 before this slice**, and the widening adds 8 decline lines without changing that exit code. Neither family touches a gate path. Second finding: **the reformat is TWO invocations, not one** — `tests/fixtures/issue-tracker` is a gate path that a root walk excludes by its own `test(s)/fixtures` rule, so it is only reachable as its own `--project` root. Third, and the one a reader will notice: the reformat **drops the `public` keyword in 16 files (~367 occurrences, 5 of them in a gate path)**. That is not information loss and not new — `FormatterSyntaxText.FormatModifiers` documents `public`/`private` as the only two droppable modifiers because N# encodes visibility in the identifier's CASE, and `ShouldPreserveExplicitCasingVisibility` keeps the keyword wherever it is not redundant. It merely becomes visible now, because these files had never been through a WRITE pass — only a `--check` on four paths. Proven neutral, not assumed: six affected `tests/native` projects run row-for-row identical before and after | **Reformat touches 286 files — 272 `.tests.nl` + 14 product `.nl` — and all 238 inside the four gate paths are `.tests.nl`, so ZERO product `.nl` the gate already formatted moves.** Lines **406,711 → 414,836 (+8,125)**, **>120 chars 15,924 → 16,207 (+283)** (the wrapping slice predicted +8,127/+283 at its own tip), bytes 19,222,203 → 19,275,914. **Fixed point over all 932 sources: pass 3 == pass 4 byte-identical**, and `format --project tests/fixtures/issue-tracker` reports "Formatted 0 file(s)." on the second pass. `format --check` exit 0 and "All files are properly formatted" on all four gate paths WITH `.tests.nl` included, and a negative control proves the gate really sees them — a deliberate violation appended to `FormatterConfig.tests.nl` is caught and named, rc 1, and reverting restores rc 0. Estate **7,302/7,302 Failed 0 BEFORE the reformat and 7,302/7,302 after** (baseline 7,305; net −3 = +1 discovery contract, −4 snapshot contracts); `dev.sh --since` selected the FULL unit suite 596/596 Failed 0. `nlc check --json` over all 26 `project.yml` under the gate paths **byte-identical** before/after against a pre-reformat reference worktree (md5 `d1379254ec08262160029496ddbbc111`, 3,591 lines both). Ownership audit **17/18 → 18/18**: row `text-v1:33b472145106e25d` → `text-v1:1b774ad91cf77e84` (exactly the value `1e192a8c2` predicted, since `CliParityAuditTests.cs` was byte-identical to that commit's parent) and head `head-v1:345b890bcab2f222` → `head-v1:ff22308bc20ee46a` **recomputed at this tip, not inherited**, in BOTH keys; manifest still exactly 391 lines |
| `015 reopening decode` | `208ecaa89` (landed) | No production file edited. Re-measures every roadmap number at `6fcb41f64`, re-probes all recorded blockers, writes the `015-A`..`015-F` campaign plan and the AOT decision. NO CUT TAKEN | "MOVABLE — EXHAUSTED" is FALSE: the roadmap's sweep enumerated decision ARMS, never HELPERS; a name-match of 449 emitter members against every production `.nl` `func` finds the 25-member type-admissibility family (396 lines, 286 call sites) with live N# owners on every row | emitter 21,519 / 20,457 non-blank / 449 members / 20,348 extent; +86 GROWTH since the 015 pause (21,433), invisible to the audit's epoch ceiling 21,723; 145 sentences (133 declines / 8 internal throws / 4 `Ldstr`); plan-row planner covers 10/21 statement + 7/27 expression kinds |

#### The `015-A` arc — duplicated type-admissibility authority

| slice | commit | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| `015-A6` | `87afbcb39` | `ColumnarIlEmitter.cs`: 3 C# members deleted (`IsSupportedType` 49 lines/72 sites, `IsSupportedAnonymousUnionArmType` 5/2, `IsClosedUserGenericInstantiation` 6/10 = 60 extent lines, 84 sites, 82 external) → `ColumnarTypeOfPlanner.IsSupportedType` / `.IsSupportedAnonymousUnionArm` / `.IsClosedSourceGeneric`; new `ColumnarSupportedTypeHeadFacts.tests.nl` (250 lines / 94 asserts / 6 blocks) | `SymbolType.IsSZArray` is TRUE for a pointer AND a by-ref, on BOTH `RuntimeTypeBuilder` and `TypeBuilderImpl`; the head's array arm trusted it, so `UserStruct*`/`UserStruct&` were in the whole supported surface and `ref UserStruct` never reached the by-ref arm written for it. FIX 1 goes in the HEAD, not the arm | emitter 21,054→20,984 / 416→413 members; 82 IL = 82 source sites; family `STILL_DECLARED_IN_CS` 3→0; corpus 90/90 byte-identical; estate 7,062→7,068; gate EXIT 0, 22m 37s |
| `015-A5` | `31a3e2d93` (landed) | `ColumnarIlEmitter.cs`: `IsSupportedExternalType` (3 lines / 2 sites) + transitive private `IsSupportedAspNetExternalReferenceType` (9 lines / 3 sites) deleted; 4 sites rerouted — 2 to `ColumnarTypeOfPlanner.IsSupportedExternalType`, 2 receiver-shaped ones to `ColumnarRuntimeInstanceMemberResolver.IsSupportedAspNetReceiver`; new `ColumnarExternalTypeGuardFacts.tests.nl` (7 blocks) | The two C# defects are NOT one bug with two faces and need TWO distinct guards: the array case is `IsPointer` asked where `HasElementType` was needed; the open-generic case is `ContainsGenericParameters` reading False on a `TypeBuilderImpl` (its `HasElementType` is False, so a `HasElementType` fix misses it) | emitter 21,068→21,054 / 418→416; `IsSupportedExternalType` DIVERGENT 19 = 17 tightenings (both defects) + 2 ruled R2 widenings; 8 real AspNet runtime array cells `cs=T nl=F`; estate 7,062; gate EXIT 0, 22m 44s |
| `015-A3`+`015-A4` | `4accb8c4e` (landed) | `ColumnarIlEmitter.cs`: 4 C# members deleted (35 extent lines) — `IsAdmissibleCollectionElement` 19/16, `IsSupportedReadOnlySpanType` 7/4, `IsSupportedSpanType` 7/4, `IsAdmissibleHashSetElement` 2/4 → `ColumnarTypeOfPlanner`; A3 WRITES the two span heads as narrowings of `IsSupportedSpanLikeType` (no N# owner existed); new `ColumnarSpanHeadAndElementFacts.tests.nl` (173 lines / 5 blocks / 77 asserts) | Ruling: TWO N# span heads, not one merged head — measured over 20,164 ordered span-typed pairs the two-head rule matches C# on every one (`CS_VS_NL_PAIR_MISMATCHES 0`) and a folded head differs on 588, including `ReadOnlySpan<int> → Span<int>` for which no CLR conversion exists | emitter 21,115→21,068 / 422→418; 27 IL = 27 source sites; 852 cells / 4 divergent (all R2 widenings, not one tightening); corpus 90/90 byte-identical; estate 7,050→7,055; gate EXIT 0, 22m 33s |
| `015-A2` | `f2239872c` (landed) | `ColumnarIlEmitter.cs`: 19 C# members deleted (227 extent lines, 170 sites — 154 move, 16 vanish in deleted bodies) → `ColumnarTypeOfPlanner`; 4 new named buffer heads written in N# (`IsSupportedArrayPoolType`/`MemoryPoolType`/`MemoryOwnerType`/`MemoryType`); dead `bindings: ColumnarFragmentBindings` parameter removed from 12 admissibility functions + 60 call sites; new `ColumnarSupportedTypeConeFacts.tests.nl` (387 lines / 9 blocks / 194 asserts) | A flat type corpus cannot see what a reroute changes — the N# owner recurses into N#'s `IsSupportedType`, not C#'s; the 25-wrapper composed-input probe found exactly 10 divergent cells in 8,316, every one a `cs=F nl=T` WIDENING over R1/R2, not one tightening | emitter 21,385→21,115 / 441→422; N# call sites in emitter 83→236 (`ColumnarTypeOfPlanner` 5→159); 154 IL = 154 source; corpus 92/92 byte-identical; estate 7,041→7,050; gate EXIT 0, 22m 28s |
| `015-A1` | `57e141ea1` (landed) | `ColumnarIlEmitter.cs`: 7 C# members deleted (142 body lines, 41 sites) → `ColumnarTypeOfPlanner` (`SplitTopLevelPipes`, `TryResolveKnownExternalType`, `OpenValueTupleType`, `IsSupportedJsonType`), `ColumnarBaseTypePlanner` (`IsRuntimeInterfaceType`, `EnumerateInterfaceAndBases`), `ColumnarRuntimeInstanceMemberResolver` (`SubstituteClosedTypeArguments`); `TryResolveLoadedExternalType` KEPT (second UNMATCHED entry point); one dead `using YamlDotNet.Serialization.NamingConventions` removed; new `ColumnarReroutedOwnerFacts.tests.nl` (225 lines / 5 blocks / 82 asserts) | Deleting the C# is what makes an unpinned N# owner permanently unpinnable — the differential can never be re-run on it. Sweep the estate for pins BEFORE the cut: 5 of A1's 7 owners had ZERO native contracts. The corrected leaf criterion is "calls no family member", not "nothing calls it" | emitter 21,519→21,385 / 448→441; 37 IL vs 41 source sites reconciled by 4 self-recursions moving inside the N# owners; corpus 97/97 byte-identical; estate 7,036→7,041; two gates green (24m 59s, 22m 36s) |
| `015-A0` | `846389f16` (landed) | ZERO C# changes (`git diff -- '*.cs'` empty). Six N#-owner bugs fixed: `ColumnarTypeOfPlanner.nl` 1,480→1,544, `ColumnarRuntimeInstanceMemberResolver.nl` 1,046→1,075, `ColumnarBaseTypePlanner.nl` 252→258; new `ColumnarTypeAdmissibilityFacts.tests.nl` (302 lines / 6 blocks / 86 asserts). Publishes the 68-row / 12,115-cell differential grid and the staged A1–A6 cut plan | The reroute would have shipped live defects: `IsSupportedSpanLikeType` had NO element constraint, so `Span<UserStruct>` reached a `GetConstructor` that THROWS. Overturns the reopening decode's `IsClosedUserGenericInstantiation` divergence — 245/245 AGREE. 26 residual cells partition exactly into R1/R2/R3/R4 | grid 133 divergent → 28 same-row-set → 26 final; 48 EQUIVALENT / 8 DIVERGENT / 12 UNMATCHED rows; call-site census reproduces 286 to the digit; estate 7,030→7,036; gate EXIT 0, 22m 39s |

**Durable findings (`015-A` and the reopening decode).**

- The differential grid is 68 driven rows over 12,115 cells (every member with TWO live N# owners is
  driven against both): 133 divergent cells before the six fixes, 28 on the identical row set after, 26
  final; rows are 48 EQUIVALENT / 8 DIVERGENT / 12 UNMATCHED (A0).
- The 26 residual cells partition EXACTLY — AspNet-typed ARRAY 8, twice-loaded `IYamlTypeConverter` 7,
  three runtime generic parameters 9, second-owner-only pair 2 — which is how the arc knows nothing is
  unaccounted for (A0).
- Of the five divergences the reopening decode recorded, four reproduce and ONE IS OVERTURNED:
  `IsClosedUserGenericInstantiation` vs `IsClosedSourceGeneric` agree 245/245, re-measured 0/302 by A6
  before it enlarged its cut. A second reproduces SHARPER: naming `typeof(Stream)` inline does not merely
  spell it differently, it DROPS `FileStream` and `DirectoryInfo` (A0, A6).
- **R1, record do not change**: C# `t is GenericTypeParameterBuilder` admits only builder-backed
  parameters while N# `get_IsGenericParameter()` admits every generic parameter; the emitter only asks
  about types it resolved itself and a source parameter IS a builder-backed one. R1 is a CLASS (4 of 302),
  invisible to all 90 corpus assemblies, and is now pinned by a contract naming it as the deliberate
  difference it is (A0, A6).
- **R2**: N#'s rule (assembly full-NAME) is long-term-correct but unobservable — the compiler references
  YamlDotNet directly and loads it once. **R3**: the C# is the defect and the reroute is the repair —
  `IsSupportedAspNetExternalReferenceType` rejects value/by-ref/pointer/open-generic but NOT arrays, so
  `SomeAspNetType[]` was admitted without ever seeing `IsSupportedElementType`. **R4**: the two N# owners
  disagree with EACH OTHER — `ColumnarRuntimeInstanceMemberResolver`'s copy carries ONE TIGHTENING in
  8,316 cells and `ColumnarTypeOfPlanner`'s carries none, which is the measured reason the whole cone
  routes to the planner (A0, A2, A5).
- The two C# defects A5 fixed are NOT one bug with two faces: the array case is `IsPointer` asked where
  `HasElementType` was needed; the open-generic case is `ContainsGenericParameters` reading False on a
  `TypeBuilderImpl`, whose `HasElementType` is also False — so a `HasElementType` fix misses it (A5).
- **The reroute would have shipped live defects**: `IsSupportedSpanLikeType` had NO element constraint, so
  `Span<UserStruct>` reached a `GetConstructor` that THROWS (measured `NotSupportedException`), and the
  admissibility predicate is the only guard in front of it. Ten behaviour fixes were carried rather than
  preserved (A0, A5, A6).
- Two of A0's fixes are RE-ALIGNMENTS, not new policy: `ColumnarTypeOfPlanner`'s own RESOLUTION paths
  already enforced the constraints its ADMISSIBILITY predicates had lost — one file spelled the same rule
  twice and kept only one copy correct, precisely the failure mode 015 exists to remove (A0).
- **CHECK NATIVE CONTRACT COVERAGE BEFORE CUTTING**: deleting the C# is what makes an unpinned N# owner
  permanently unpinnable, because the differential can never be driven on it again. A1 found 5 of 7 owners
  with zero contracts, A2 12 of 19, A3+A4 both span heads with 0 and no owner to call, A6 found the 24
  asserts naming `IsSupportedType` were all composed rows pinning SUB-heads and ZERO of the head's own 20
  arms. +32 estate blocks across the arc, every one added because a sweep measured that nothing could tell
  the owner's answer from a wrong one (A1–A6).
- Reroute ORDER is forced by the call graph: `IsSupportedType` calls 12 of the other duplicates, so it
  moves LAST — a leaf-first cut would leave a C# root calling an N# leaf with eleven sibling leaves still
  C#. The corrected leaf criterion is "calls no family member", not "nothing calls it" (decode, A0, A1).
- **A widening cannot move an already-green corpus by construction**, so its silence is not evidence of
  decoupling; each such mutation must be carried by a named estate contract that breaks (A3+A4 pairs
  M1↔C1, M3↔C3, M5↔C4, M6↔C5).
- The out-parameter contract: `TryResolveKnownExternalType` agrees on the BOOL for all 39 canonicals, but
  on the FALSE path C# leaves the `out` as `null` while N# leaves it `typeof(object)` (16 of 39). A
  mechanical reroute would silently install `System.Object` into a slot every caller reads only on the
  true path; A1 routed through a fresh local and the guard rests on a direct 46-input probe, because the
  corpus cannot tell either way (A0, A1).
- `TryResolveLoadedExternalType` was KEPT: a member with a second, UNMATCHED entry point survives the cut,
  and the call-site count already says so (A1).
- The family is TERMINAL: all 25 numbered members and every transitive private read `csDeclared=False`,
  measured by the metadata instrument over all 36 rows. `FAMILY_ROWS_WITH_ZERO_NL_CALLS 6` is explained,
  not left as a number (two answered by `ColumnarBaseTypePlanner`, which the counter does not scan; two
  transitive privates called only from N#; two whose one site was the arm inside the deleted head) (A6).
- The centre is measurable: control C1 removes ONE arm (`typeof(int)`) from `IsSupportedType` and breaks
  its own block plus TEN written by four earlier stages, and the corrected coupling run shows deleting that
  one identity breaks 18 of 20 corpus programs (A6).
- The transferable method A6 handed to B: derive at the tip before editing; sweep the estate for pins
  before the cut; run the differential CONTROL-FIRST and reproduce the prior stage's published readings
  before reading a new one; reconcile the collapse at IL level against the source census; compare the
  corpus byte-for-byte with sources fixed and only the compiler swapped; take the two-key repin LAST (A6).
- **`015-B1` had to be the LOCALS-AS-LOCALS binding mode alone**, not a statement kind: the planner was
  specialised to the iterator lowering where a local is a hoisted state-machine FIELD (`Stfld` via
  `FieldPool`), not a `Stloc`, and every missing statement kind that declares or assigns a local was
  blocked behind it (A6).

#### The `015-B` arc — the method-body door

| slice | commit | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| 015-B16 | no commit (decode tip `8cf40128a`) | ZERO C#. `ColumnarTypeOfPlanner.Plan` factored into `TryAppendRoot` (the FOURTH time, and the first that KEEPS the `try`/`catch`, because this owner's `Plan` had one); the door gains a kind-55 arm calling it and a kind-7 arm that is a child-count guard plus ONE recursion through its own dispatcher; kinds 7 and 55 move from the declined set to the claimed set (13 → 15); EIGHT pinned decline blocks rewritten as claims; classes G and Y added | **OVERTURN: the brief's kind-7 basis.** `FacadeRootMayNeedFacts` and ALL EIGHT cascade owners' `MayPlanRoot` open with `UnwrapParentheses`, so for nine inner kinds the host never reaches `case 7` — the OWNER claims the OUTER node; every owner's `TryAppendRoot` unwraps too, so one recursion reproduces BOTH host routes. The parenthesis costs NO row, and the arm widens nothing: it inherits the child's claim class exactly | estate 7,192→7,201 (+9, predicted exactly); emit-facts 38→41; corpus 68/64/3,669 rows/3,590 keys — ctlA-ctlB AND ctlA-slice both IL_DIFFS=0; probes 37 bodies IL_DIFFS=0, +24 claims −0 lost; **live +2, both named by the census BEFORE the run**; marker floor 461→463; live-tree 403/243, identical in order, one pre-existing NL011 shifted 669→702 by the file's own +33 lines; controls C1 5/C2 stack-overflow/C3 2/C4 3/C5 1, all predicted; gate 126/0 `ALL TESTS PASSED`, launched at 1-min load 4.55, 9.61 at exit (nine sibling agents building throughout) |
| 015-B15 | `40e0cc20e` (landed); decode tip `b460354c2` | ZERO C#. `ColumnarExternalStaticMemberPlanner.Plan` factored into `TryAppendRoot` (no try/catch added — this owner's `Plan` never had one); `ColumnarMethodBodyPlanner.TryAppendMemberAccessRoot` loses its scratch plan and its refusal → **door kind 8 CLOSED**, both cascade arms owned, class X added | The cascade's SEVENTH arm FALLS THROUGH on a decline and sets no `nsharpOwned`, so the door's guard becomes a CLAIM; one open plan is offered to TWO owners, safe only because `ColumnarCodePlan.Rollback` resets `Status = NotOwned` | estate 7,183→7,190 (+7); emit-facts 36→38; corpus IL_DIFFS=0 / 3,463 keys; probes +18 moved, −0 lost; live +5; gate 126/0, 21m50s |
| 015-B14 | `b460354c2` (landed); decode tip `5af0b2fec` | ZERO C#. `ColumnarInstanceMemberPlanner.Plan` factored into `TryAppendRoot`; door gains a kind-8 arm that asks both cascade owners in cascade order and claims only the second; `015-B8`'s "inert" plan-local mirror comment retired | **OVERTURN: kind 8 has TWO owners** — external-static (arm 7, asked FIRST) then instance-member (arm 8). Arm 8 sets `nsharpOwned = ClaimsRoot(…)` BEFORE `TryEmit`, so a set-then-failed claim declines the WHOLE FUNCTION | estate 7,175→7,183 (+8); emit-facts 34→36; corpus 68/45/1,851, IL_DIFFS=0; live +12; C7 costs exactly 1 body (`a[i+1].X` stops compiling); gate 126/0 |
| 015-B13 | `5af0b2fec` (landed); decode tip `92af20111` | ZERO C#. Door claims kind 57 `checked(…)` through its OWN recursion (flip `bindings.OverflowCheckingEnabled`, recurse, restore); `ColumnarDirectCallPlanner:611`'s delegate-invoke ARGUMENT reads `ArgumentsAdmitPrimitiveBinary()`; `:1040`/`:1208` receivers PINNED to `:854`'s rule | **OVERTURN: kind 57 has NO N# owner** — the B6/B7 factoring does not apply and byte identity is against the door's own recursion. `:611` was a LIVE type-side/append-side inconsistency: `TryGetArgumentTypes` admits a primitive binary its APPEND side refused | estate 7,166→7,175 (+9); emit-facts 32→34; corpus 68/45/1,839 keys, IL_DIFFS=0; +14 claim rows, 8 live bodies; NL402 64→65; gate 126/0 |
| 015-B12 | `92af20111` (landed); decode tip `b57c661a0` | ZERO C#. STAGE 2: `ColumnarTypeEquivalenceFacts.SameDeclaredIdentity` collapses to `Object.ReferenceEquals(a.get_Module(), b.get_Module())`, deleting the reflective `PropertyInfo` detour + its 11-line wall comment; `ColumnarConditionalPlanner.TryAppendRoot` gives the door TWO arms (ternary 13, short-circuit 12) | **OVERTURN: the surface is not a `TryAppend*` parameter** — it is the choice between two named forwarders; censused that way the inherited-surface family is CLOSED at four owners and the literal census returns 28 false positives | estate 7,158→7,166 (+8); emit-facts 30→32; corpus 68/41/1,721 keys, IL_DIFFS=0; +11 live bodies; residue scan 0/0/0/0; gate 126/0 |
| 015-B11 | `b57c661a0` (landed); decode tip `dd9f56863` | ZERO C#. STAGE 1: `System.Reflection.Module` onto BOTH `ColumnarExternalBindingPlans` tables PLUS a `get_Module` row on `GetInstanceCallPlan`'s `System.Type` member table; `IsHostAdoptedReturnShape` narrowed to the pre-pass's own two tests; `allowPrimitiveBinary` threaded into `ColumnarInstanceMemberPlanner.TryAppend` | **DECLARABLE AND BINDABLE ARE TWO ADMISSIONS** — the list alone left `a.get_Module()` declining at `emit.return.expression`, found by differential probe (`get_Assembly` compiled, `get_Module` did not) | estate 7,151→7,158 (+7); corpus 25/425 IL_DIFFS=0; 4 claim rows, 0 live; `IsSupportedRuntimeTypeName` 31→32; 8/8 controls exact; gate run twice, both green |
| 015-B10 | `dd9f56863` (landed); decode tip `6252626c7` | **The arc's FIRST emitter shrink**: the 118-line five-function type-identity cone (`TypesEquivalent`, `IsByRefType`, `IsSzArrayType`, `TryGetElementType`, `IsSameEnumType`) ported WHOLE to new `ColumnarTypeEquivalenceFacts.nl` (211 lines); `ColumnarIlEmitter.cs` keeps 3 forwarders, deletes 2 definitions; RangeIndex threads the surface into 5 inner planners | **OVERTURN: six plain-surface appends in five functions, not one selector.** The port has a partial N# sibling (`ExactTypeShapeMatches`) that is NOT the same function and must not be merged; the port is blocked on `a.Module`, routed reflectively rather than weakened | emitter 20,890→20,784 / 19,871→19,768; estate 7,141→7,151 (+10); corpus md5 `13d2574e…` unchanged 3rd slice running; +8 probe claims, 0 live; first two-key repin `head-v1:9717a7390756f51c` |
| 015-B9 | `6252626c7` (landed); decode tip `109bfa015` | ZERO C#. `ColumnarPrimitiveBinaryPlanner.TryAppendRoot` factored; door claims kind 12 (claimed 9→10); `ArgumentsAdmitPrimitiveBinary()` replaces eight hard-coded `false`s in `ColumnarDirectCallPlanner`; `ColumnarCodePlan` gains `EnableNestedValueFrame`/`HasNestedValueFrame` | **OVERTURN: the index-access argument is refused by a ROOT rule the scratch applies in the wrong place** — `allowOrdinaryIntIndex` is `parentFragment >= 0`, and the TYPE side typed arguments at `-1`, a position the value never occupies | estate 7,133→7,141 (+8); corpus md5 `13d2574e…` identical to B8; **+17 LIVE bodies** (the arc's largest move); 5/5 controls exact; gate 126/0, 22m31s |
| 015-B8 | `109bfa015` (landed); decode tip `4265cec9a` | ZERO C#. The plan-local MIRROR: `PlanLocalIsMirror` column + `EnablePlanLocalMirror` on `ColumnarCodePlan`; `ValidatePlanLocalsUsed` + `SeedMirrorAssignments` + an `Execute` refusal on `ColumnarCodePlanExecutor`; `PlanLocalMirrorTypes()` vocabulary; all four scratch sites armed; `ReadsPlanLocal` DELETED (`ColumnarMethodBodyPlanner` 666→626) | **OVERTURN: there are FOUR scratch sites, not three, and only S1 is reachable** — and `ValidateAllUsed` is NOT the rule that blocks the crash shape: R1 (all-used) runs first, R2 (`ApplyLocal`'s assigned-before-`ldloc`) is what kills P1. The brief's fix would not have fixed it | estate 7,127→7,133 (+6); both corpora IL_DIFFS=0, big md5 `13d2574e…`; 8 shapes crashed, 6 claim (crash class ⊃ claim class); gate 126/0 |
| 015-B7 | `4265cec9a` (landed); decode tip `b5644eff7` | `ColumnarDirectCallPlanner.TryAppendRoot` factored + a void-result guard; door claims kind 9 (9 claimed kinds); the three binding facts (`ExactSourceTypes`, `_overflowCheckingEnabled`, `SiblingCallFacts`) routed line-neutrally through `ColumnarIlEmitter.cs` (20,890→20,890) | **OVERTURN: the overflow flag is PROVABLY FALSE at every `EmitBody` entry** (no initializer, written only inside `EmitExpressionWithOverflowChecking`, all 7 call sites on fresh emitters) — routed anyway. **A void-returning call THROWS out of `CompleteFragment`, it does not decline** | estate 7,121→7,127 (+6); corpus 885/59/60 IL_DIFFS=0; **MUT-C moves 2 LIVE bodies** — first live movement since B5; 6 controls, C3/C5 single-block; repin `head-v1:6bc1f1b6f58f020d` |
| 015-B6 | `b5644eff7` (landed); decode tip `cb03f78dc` | ZERO net C#. NINE owner gates widened to admit the method-body schema; `TryAppendRoot` factored out of the unary-literal and `nameof` owners; the STATEMENT LOOP (kind-24 `:=` declarations + one `return`) with plan-locals and a `PlanLocal` identifier selection tier; `BeginFragment` admits a NEW ROOT on a method-body plan | **OVERTURNS ALL THREE BRIEF MOVES**: `TryEmitFromFacts` is an eleven-arm CASCADE not a dispatcher; a `LocalBuilder` cannot exist at plan time so kind 24 publishes a PLAN-LOCAL; fragments are inert in a sealed v4 payload, so a method body admits MANY roots | estate 7,103→7,121 (+18); big corpus 6,784 rows IL_DIFFS=0; **B6's classes move 0 live bodies** (census: 6 blocked bodies); C10 a measured non-isolation; repin `head-v1:d0a2dfa62779dee5` |
| 015-B5 | `cb03f78dc` (landed); decode tip `b440f294f` | ZERO net C#. The APPEND-MODE EXPRESSION DOOR: `TryAppendReturnValue` + `IsClaimedExpressionKind`/`IsDeclinedExpressionKind`/`ExpressionKindLedger` (34 kinds, total partition); identifier filter widens 1→4 selection kinds (`CurrentField`, `CurrentProperty`, `ByRefParameter` added) | **OVERTURNS THREE BRIEF ITEMS**: the append-mode dispatcher already exists (`TryAppendPlannableValueCore`); `ColumnarConditionalPlanner`'s entries exist but are not spelled `TryAppend*`; the current-instance pair does NOT make the three unrouted facts mandatory — composites do | estate 7,098→7,103 (+5); 6,784 rows IL_DIFFS=0; **12 live corpus bodies** (was 7); the equality ceiling costs `IssueStore::GetAll`; 9 controls; repin `head-v1:be442a48eab08ecf` |
| 015-B4 | `b440f294f` (landed); decode tip `5d36d569e` | Driver widens from one literal family to FOUR classes (literal, bool, parameter, void); `ColumnarBooleanLiteralPlanner.TryAppendLiteral` (v1 ‖ v4); `ColumnarBoundIdentifierPlanner`'s gate admits a method-body plan; `ContainsReturnStatement`'s 13-line body moved out of C# (emitter 20,893→20,890) | **OVERTURN: the `Ldarg_S` hazard does not exist** — `EmitLoadArgument` is not on the parameter-read path, so no ordinal cap is needed. The seventh pre-pass `IsSupportedNullable` is RETURN-TYPE gated, so the parameter class needed an explicit nullable guard the brief never named | estate 7,090→7,098 (+8); corpus 8,408 rows IL_DIFFS=0; mutations 5/3/6/5 probe, 3/0/0/4 live; `P4`=`fe090400 2a` proves long-form both sides; repin `head-v1:2e0c2a5aa72bebf1` |
| 015-B3 | `5d36d569e` (landed); decode tip `d0e0faa3f` | NEW `ColumnarMethodBodyPlanner.nl` (158 lines): `AlwaysReturns`+`TryStatementAlwaysReturns` moved whole out of C#, plus `TryPlanLiteralReturnBody` (the first ordinary-user-body driver); `ColumnarScalarLiteralPlanner.ValidateAppendInputs` admits schema v4; emitter 20,923→20,893 / 19,902→19,874 | **OVERTURN: the row, executor arm and height model for `Ret` all already exist with 18 production consumers** — what was missing is a DRIVER. The mandate conflated the plan-row IR with the N# statement-kind walk | estate 7,082→7,090 (+8); corpus 6,238 rows md5 `2c1b1f11…` on all three passes; coupling mutation moves exactly 3 of 6,238; 8/8 controls bite; repin `head-v1:a66a697f7a3d2a9f` |
| 015-B2 stage 2 | `d0e0faa3f` | `UnboxAny()` = 165 row + admission + executor arm; `EmitArgument` narrowing (ordinals 0..3 → `Ldarg_0..3`, `Ldarga` never narrows); PASS 0e (`Equals`/`GetHashCode`/`<Clone>$`, 90 lines of raw `ILGenerator`) moved to new `ColumnarRecordValueMemberPlanner.nl` (230 lines); emitter 20,976→20,923 | **THE CONTROL WALK OVERTURNED THE DECODE**: a schema-v4 method body never reaches `ApplyInstruction` (the TYPED model is v2/v3 only; v4 runs the HEIGHT model), so three typed-stack arms added on a misdiagnosis were DEAD CODE and were deleted with zero byte change | estate 7,076→7,082 (+6); 165 of 5,803 rows changed, ALL shorter, long-form `ldarg` 449→3; 249 record rows byte-identical; without the narrowing 55 record rows diverge; gate run twice |
| 015-B2 stage 1 | `b99b7dc6f` | N#-only: `Ldarg_0..3` into `IsSupportedValueOpCodeMemberName` (33→37) and `Unbox_Any` into `IsSupportedObjectModelOpCodeMemberName` (33→34); allowlist 108→113 names, one head, one consumer, no second copy. ZERO C# touched | The modeled-`OpCodes` allowlist lives in ONE file with ONE consumer (the three-family split is a linter-guard artefact). `Ldarg_S` is a TWO-half widening (name AND a `System.Byte` emit operand `IsSupportedEmitOperand` refuses), so ordinals ≥4 stay long-form deliberately | estate 7,073→7,076 (+3); native `reflection-emit-bootstrap` 2→5; corpus 5,803 rows, md5 `f1e1d702…` on all three passes; ownership audit 18/18 with NO repin (predicted first) |
| 015-B1 | `9bd9aa222` | NEW `ColumnarAsyncEntryPointPlanner.nl` (98 lines) owning `__NSharpEntryPoint`'s signature rule and body; `Pop()` = 38 row (method-body-only, explicit −1 delta); emitter 20,984→20,976 (−8) | **OVERTURN: the IR does NOT bind locals as hoisted fields** — `PlanLocalOperand` exists at every layer with five production owners, including the iterator planner itself. PASS 0e was attempted FIRST and abandoned: `Emit(OpCode, short)` does not narrow `Ldarg`, and the fix is repack-gated | estate 7,068→7,073 (+5); corpus 112 assemblies / 4,046 rows IL_DIFFS=0; both `__NSharpEntryPoint` bodies byte-identical; 5 controls; repin `head-v1:fd53ebb53ffa009c` |

**Durable findings (`015-B`).** The door/cascade model itself is in §3.1; these are the rest.

- **A PARENTHESIS COSTS NO ROW, and that is the whole kind-7 claim**: `(x)`, `((x))` and `(((7)))` plan the
  identical rows at identical indices with no fragment of their own, which is what makes one recursion
  byte-identical against BOTH host routes — `case 7` and the owner that claims the outer node (B16).
- **The kind-7 arm WIDENS NOTHING; it inherits the child's claim class exactly.** `(!flag)` stays the
  host's (the kind-11 arm claims only a unary over a LITERAL), `(null)` reaches the kind-5 refusal and
  `return (null)` does not compile on either CLI, `(new T())` stays declined. Predicting 25 probe movers
  and measuring 24 is the door being right and the prediction being wrong (B16).
- **Kind 55 is the cascade's FIFTH and ONLY UNCONDITIONAL arm** (`nsharpOwned = true` before `TryEmit`, no
  `ClaimsRoot`, no fall-through), so the host already declines the whole FUNCTION for an unplannable
  `typeof` root and a door decline can only narrow the BODY — the opposite risk profile from the eighth
  arm, and the reason kind 55 was separable while `o.Inner.V` is not (B16).
- **The `TryAppendRoot` factoring runs in BOTH directions.** `ColumnarTypeOfPlanner.Plan` carried a
  `try`/`catch`, so its factored sequence carries one — where B15's owner, whose `Plan` had none, got none.
  The rule is "the sequence `Plan` runs, no more and no less" (B16).
- **A guard the host does not write can still be load-bearing.** Deleting the kind-7 child-count guard is
  not an equivalent mutant: `Child(node, 0)` on a childless node feeds the arm back to itself, giving
  unbounded `TryAppendValue` recursion and a TEST-HOST STACK OVERFLOW, isolated to one block (B16).
- **Byte identity cannot tell a claim from a decline**: `return typeof(int)` on an `object`-returning
  function has rows IDENTICAL to the claimed `Type`-returning twin and is still the host's, because the
  claim rule is type EQUALITY. Only the marker separates them. A pin census over source text has the same
  blind spot: B16's found SEVEN parenthesis pins and the `claimed == N` COUNT assertion was the EIGHTH (B16).
- **A textual census reads TEXT while the door dispatches on NODE KIND**, at scale: 24 corpus return values
  start with `(` and exactly TWO are kind-7 ROOTS — the rest are casts, tuples and parenthesised
  sub-expressions under a binary root. Both were named before the run and both moved (B16).

- NINE owner `ValidateAppendInputs`/inline gates THROW `InvalidOperationException` on a method-body plan
  instead of declining — a HARD CRASH, so they had to be widened together (B5, B6).
- `ColumnarBooleanLiteralPlanner` is a schema-v1 producer: v1's `AppendInstruction` throws on a second row
  and admits only `LdcI4_0`/`LdcI4_1`, so there is no gate to relax and an additional append entry is
  required (B4).
- The direct-call owner types arguments in a FRESH scratch plan with an EMPTY local pool, so
  `n := f(3); return g(n)` crashed the compiler with `Build failed: The opcode does not use this
  plan-local entry.` — the type-discovery scratch is a distinct execution context from the plan (B7).
- **There are FOUR type-discovery scratch sites, not three** (the brief's census missed
  `ColumnarRangeIndexPlanner:353`), and only S1 is reachable from a claimed body; tagged-CLI reachability
  reached S1 (B8), S2 (B10) and S3 (B14), with S4 unreached as of B15 (B8, B15).
- `ColumnarNodeTable.Text` is a bare `source.Substring(...)`: a literal node with no span THROWS
  `ArgumentOutOfRangeException` out of the compiler. The host guards with `ValueStart < 0` and any new
  predicate reading operand text must too (B11).
- `ByteArrayPool.Shared.Rent` (an alias chain) sets `legacyWholeSubtreePlanning` and rolls back — a
  documented, deliberate yield to the legacy composed-expression owner (B7).
- `checked(-a)` over a parameter is refused BY CONSTRUCTION, not by a guard: the host's `case 11` overflow
  negation DECLARES A LOCAL, and the door's kind-11 arm claims only a unary over a LITERAL operand. The
  one place `checked` changes a unary lowering is the one place the door cannot go (B13).
- `TryEmitIntLiteralAsType`'s POSITIVE arm (byte/sbyte/short/ushort/uint/long/ulong) and the door's
  claimable return type (`int` only, for an unsuffixed literal) are DISJOINT — re-derived in bytes with
  five probes rather than inherited from B5's prose (B12).
- The negative-literal range needs no return type threaded in: the door types `-<unsuffixed int literal>`
  as `int` and nothing else, so a fixed `int.MaxValue` cap is a provable superset for every target; the one
  value the range half buys is `-2147483648` (B11).
- `MethodBodyStackDelta`'s `Ldtoken`/`TypeOperand` arm already returns 1, and `AppendLabelInstruction`
  admits `Br`/`Brfalse`/`Brtrue` in ANY schema (only `Leave` is method-body-gated) — check schema legality
  before assuming a row shape needs work (B12, B15).
- `:611`'s delegate-invoke ARGUMENT was a LIVE type-side/append-side inconsistency:
  `TryGetArgumentTypes` admits a primitive binary its APPEND side refused. `ColumnarDirectCallPlanner`'s
  `:1040`/`:1208` receiver sites are PINNED to `:854`'s rule and may only move together with it (B13).
- `arr[^(i + 1)]` and `s[(i + 1)..]` did not compile AT ALL at `6252626c7` — the legacy host cannot emit a
  composite inside a `^` operand or a range endpoint either, so two of five sites are a CAPABILITY GAIN
  verified by EXECUTION, with no tip bytes to compare (B10).
- The port of `TypesEquivalent` has a partial N# sibling, `ExactTypeShapeMatches`, that is NOT the same
  function and must not be merged; the port was blocked on `a.Module` and was routed reflectively rather
  than weakened, and the `AssemblyQualifiedName` shortcut was REJECTED IN WRITING as a silently-diverging
  subset (B10).
- **What the arc leaves open**: the composed instance-member receiver (`o.Inner.V`), which moves the
  cascade's eighth arm and carries the `nsharpOwned` hazard, so its TYPE and APPEND sides must land in one
  slice; kind 7 (`Parenthesized`) with `IsHostAdoptedReturnShape` as its one hazard; kind 55 (`typeof`) as
  the smallest remaining cascade arm; and the two pinned receiver surfaces at `:1040`/`:1208` (B13–B15).

### 4.2 Task 021 — the final compiler ownership audit (audit complete at `6fcb41f64`; box deliberately UNCHECKED)

Outcome: twelve slices, every surviving non-N# file classified with its owner named and its decision census
measured. `src/NSharpLang.Compiler` fell 65,454 → 27,838 epoch lines (−57%), 11 files removed whole
(37,616 lines), 0 of 381 ratchet rows above ceiling, 0 non-N# files added. Slices 7 and 8 were accepted at
`2c525c7bb` and `a9d9ed504`; the rest are recorded against their measured tip. The box stays UNCHECKED
because the closing contract's `mechanical` conjunct fails for `ColumnarIlEmitter.cs` (144 sentences,
21,519 lines) — see §3.8.

| slice | commit | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| 021 slice 12 (closing slice) | `6fcb41f64` (landed) | `SystemsAnalyzer.cs` 1,160 → 1,156: `MutableFunctionSummary::get_Line`/`get_Column` + both ctor params/assignments deleted (write-only, never read); no new C#. `tests/scripts/test-all.sh` gains `--exclude='.claude/'` on the existing rsync/tar lines without growing the file. 8 docs corrected; `memory/architecture.md` placeholder replaced with the 11-row allowlist. | The box stays UNCHECKED: the contract is a conjunction of four (pre-existing, non-growing, mechanical, reviewed-against-an-N#-owner) and `ColumnarIlEmitter.cs` FAILS "mechanical" — 144 user-facing sentences, 72 decline sites reaching users as `NL103 Declined at <site>`, the identical class 021/2 already ruled product decisions. Naming a future owner ≠ being mechanical today. | `NSharpLang.Compiler` 65,454 → 27,838 epoch lines (−57%), 11 files removed / 37,616 lines; 0 of 381 rows above ceiling; 0 non-N# files added; gate `ALL TESTS PASSED` 25m42s, 127 steps, unit 596/0, estate 7030/0, VS Code 3b PASSED |
| 021 slice 11 | tip `aded3dd58` (not committed) | `PlaygroundRunner.cs` 966 → 939 (`+78/−105`, one C# file, no new type): the `PG201`–`PG237` vocabulary (37 codes + 37 sentences, 74 literal sites), 3 budgets, entry-point rule, division rule, 1e-7 equality tolerance, escape decoder, union case name matching/splitting, rendering words → new `src/NSharpLang.Compiler.BootstrapServices/PlaygroundRunFacts.nl` (442 lines, 66 `static func`s) + `PlaygroundModels.nl` 55 → 60. | The playground is a SECOND implementation of N# semantics and **7 of 14 comparable programs answer differently from `nlc run`** (int and double div-by-zero, 0.1+0.2==0.3, record and union `print`, `"n="+1`, shorthand union binding) — so "route to the canonical path" was NOT available; Group A execution mechanism is classified `(b)`, Groups B/C moved. | runner literals 81/131/117 → 13/13/12; 74 `PlaygroundRunFacts.` call sites; contracts 268 lines / 18 blocks / 143 asserts; estate 7,012 → 7,030; mutation matrix 12/12 distinct blocks; seam sha256 byte-identical 249 lines; gate 23m15s `VSCODE_TESTS=skip` |
| 021 slice 9b | tip `3e90666ef` (not committed) | `LanguageServer/Services/TypeResolver.cs` 526 → 373 lines / 459 → 326 non-blank (`+73/−226`, one C# file, no new type): 20 decisions (seed universe, 12-entry short-name roster, namespace probe prefixes+order, `?`/array/generic name rules, completion display name, offerability guards, prefix-match case rules, the 200 cap, namespace ranking + ordinal tie-breaks, well-known namespace seeds, import-prefix split) → NEW `EditorTypeCatalogFacts.nl` (483 lines, 25 `static func`s) + `EditorTypeCatalogFacts.tests.nl` (507 lines, 34 blocks). 4 dead items deleted: `GetImportNamespace` ×2 (26 lines, absent from the whole IL census), `ImportableTypeInfo.IsStatic`, a stale `<summary>` at `:401–403`, and the never-passed `maxResults = 200` parameter. | THE EDITOR AND THE ANALYZER SEE TWO DIFFERENT TYPE UNIVERSES: the LSP's `_loadedAssemblies` is THREE assemblies (`typeof(object)` and `typeof(List<>)` are both `System.Private.CoreLib` — slice 9's "four assemblies" is wrong and the `// System.Collections` comment is wrong), vs the analyzer's 27 `CommonAssemblyNames()` + project references. So completion cannot offer a type from a user's package and hover cannot name one; unifying is the AOT type-model task, NOT a fifth seed name. | literals 52/76/59 → 5/5/5 (all logging templates); estate 6,978 → 7,012; mutation matrix 15/15 bite, 1 non-mover proved unobservable; seam 1,812 lines BYTE-IDENTICAL `sha256 47648c56…`; gate VS Code-enabled 25m37s, 127 steps, unit 596/0 |
| 021 slice 9 (Stage A; 9b/AOT task split out) | tip `a9d9ed504` (not committed, 8 paths) | `Analyzer.cs` 2,960 → 2,798 (non-blank 2,748 → 2,605): 21 of 24 MLC-quarantine decisions (NuGet cache root, 27-name assembly table, ASP.NET set + trigger, shared-framework climb, TFM ladder, package layout, `libraries` key split, project spellings, SemVer precedence, same-load predicates) → NEW `AnalyzerMetadataLoadPolicy.nl` (688 lines, 42 static funcs) + `.tests.nl` (443 lines, 54 blocks / 141 asserts). `NuGetVersionComparer` (86) + `NuGetVersionOrder` (7) DELETED WHOLE. `tests/AnalyzerMetadataLoadContextTests.cs` 189 → 159, assertion markers 22 → 15 (9 of 11 xUnit cases migrated). | THE AOT LEG IS MEASURED SHUT: `MetadataReader` is unspellable from the estate (`typeof` declines at `emit.local.initializer`; as an annotation → `NL201 Type 'MetadataReader' not found`; `System.Reflection.PortableExecutable` → `NL704` without a `nuget:` line, and WITH one `new PEReader` still declines). Behind that, 99 of 396 production `.nl` files name a reflection object type — replacing MLC is a whole external-TYPE-MODEL swap across a quarter of the estate: a TASK, not a slice. | quarantine 27 extents/646 lines → 25/492 (21.8% → 17.6%); literals 81 sites/67 distinct → 4/3; 36 call sites over 33 entry points; estate 6,924 → 6,978; unit 605 → 596; mutation matrix 14/14 bite, NO non-movers; differential IDENTICAL on 58 projects + 8-project corpus; gate run 3 = 126 steps green |
| 021 slice 8 | ACCEPTED at `a9d9ed504` (tip measured `2c525c7bb`) | `src/NSharpLang.Build.Tasks/EmitIlAssembly.cs` 341 → 303 lines / 293 → 262 non-blank (`+92/−130`, zero-headroom row): 14 of 17 decisions (DEBUG define rule, `$(DefineConstants)` fold, diagnostic id, MSBuild end column, reference dedupe, `System.Private.CoreLib` name, the corelib→contract TypeRef rewrite + owner precedence, empty-owner-map verbatim, sync preconditions, self-output exclusion, AssemblyRef reuse, corelib-ref drop, version precedence, success sentence) → NEW `SdkEmitTaskKernels.nl` (224 lines, 15 static funcs + `ReferenceTypeOwners`) + `.tests.nl` (237 lines, 18 blocks / 82 asserts), plus `CompilerError.nl` `+6` (`MsBuildEndColumn`). | THE CECIL REWRITE IS THE WHOLE OF N#→C# CONSUMABILITY, executed not reasoned: the un-rewritten implementation dll gives `csc` **`error CS0012: The type 'Object' is defined in an assembly that is not referenced … System.Private.CoreLib`**; the rewritten ref assembly builds clean. `System.Private.CoreLib` is the one runtime assembly with no reference-pack counterpart, which is why it is the one name the scope test checks. | `\w+Kernels\.` sites 0 → 16 over 13 entry points; literals 11 sites/7 distinct → 3 (all XML-doc prose, no literal-bearing code line); estate 6,905 → 6,924; A/B over 46 projects: identical outcomes, ALL 75 normalized IL digests identical; mutation matrix 16/16, zero non-movers; gate 126 steps, 22m20s |
| 021 slice 7 | ACCEPTED at `2c525c7bb` (tip measured `80a6e3027`) | `Cli/Daemon/DaemonProtocol.cs` 116 → 100 / 95 → 84 on a ZERO-headroom row: `DaemonStatus` DELETED (5 names + the `"30m"` default, zero production consumers), the 3 spellings of `"2.0"` → `GetJsonRpcVersion()`, the 5 status member names → `GetStatusPidField()`…`GetStatusIdleTimeoutField()`, all in `DaemonProtocolKernels.nl` 327 → 357 (44 → 50 entry points). `tests/DaemonCommandTests.cs` 764 → 741. `QueryCommand.cs:108` ordering and `Program.cs:581/584/633` diff labels CLASSIFIED (b) and PINNED through the SHIPPED BINARY, not moved. | A wire name a SPECIFICATION fixes is an ecosystem fact; a wire name N# invents is a product decision — 11 JSON-RPC 2.0 members stay, 5 status keys move. The binding reason is NOT "until N# emits JSON attributes": a C# attribute argument must be a compile-time constant, so an attribute name is the one residue that can never be *defined from* an N# owner. A (b) item may not retire UNPINNED. | pin census 2 of 44 → 46 of 50; error codes `-32700/-32600/-32601/-32602/-32603` had ZERO assertions in ANY language before this slice; estate 6,889 → 6,905; cli-command-contracts 77 → 83 blocks; unit 606 → 605 (one vacuous test deleted); seam 104 lines byte-identical `sha256 38af308b…`; matrix 16 perturbations / 15 movers; gate 126 steps, 22m18s |
| 021 slice 6 | `80a6e3027` (landed); tip measured `b2f2356bf`, 19 paths | `Program.Testing.cs` 617/539 → 617/538 (literal-bearing lines 29 → 2): all 12 residues moved — outcome vocabulary, `F3` duration, verbose `F0`+`InvariantCulture`, verbose classification, lifecycle names+order, `xunit.runner` identity, `GetTestFullName` join, display-name preference, `"Debug"` config, bare `return 1`s, output-mode ordinals, failure-message join → `TestCommandKernels.nl` 648 → 790. Take-together LINE FOR LINE: `Program.Backends.cs` 366/328, `LintCommand.cs` 199/181, `WatchCommand.cs` 155/127. `BuildCommandKernels.tests.nl` NEW (it had NO estate contract at all). `Program.cs` 786/682 held exactly (4 call sites reordered by the signature change). | THE COMPILER IS A STRONGER GUARANTEE THAN A CONTRACT: mutating `CultureInfo.InvariantCulture` → `CurrentCulture` DOES NOT COMPILE (`NL103` at `TestCommandKernels.nl:647:16`, `emit.call.instance-member-unmodeled`) because `ColumnarExternalBindingPlans.nl:313` models exactly ONE `CultureInfo` static member. The latent comma-decimal `duration` bug is not merely fixed — on the columnar path it is UNWRITABLE. | estate 6,861 → 6,889 (+28 = 17+4+4+3); `TestCommandKernels` sites 41/33 → 77/49; the 3 outcome words had ZERO pins anywhere before this slice; both seams byte-identical (`nlc test` 130 lines `sha256 973db094…`, `nlc lint`/`build` 193); matrix 12 perturbations, 2 first-pass non-movers both root-caused; gate 126 steps, 22m16s |
| 021 slice 5b | `b2f2356bf` (landed); 22 paths | Six in-scope LSP files 3,298 → 2,803 (−495 lines, NOT ONE LINE ADDED ANYWHERE): `SemanticTokensHandler.cs` 1,021 → 842, `CallHierarchyHandler.cs` 768 → 734, `TypeResolver.cs` 536 → 526, `EditorUtilities.cs` 299 → 27. Owners: `ParserTokenFacts.IsOperator` (36 ops, delegating to `IsAssignmentOperator`), `AnalyzerTypeReferenceFacts.IsBuiltInTypeName`/`BuiltInClrTypeName` (18, DEFINED FROM `BuiltInSimpleType`), `LinterInterpolationScan.HoleSpans`, `AnalyzerVariableDeclaration.IsErrorCaptureForm`, `CodeIntelligenceTextUtilities.IsEditorPositionInsideStringLiteral`, `DeclarationFacts.EstimateDeclarationEndLine` (+ a new `ExpressionBody` arm). `ColumnarIlEmitter.cs` rerouted LINE FOR LINE at 21,519. | THREE OF SLICE 5's OWN CENSUS CLAIMS OVERTURNED: (a) the `"err"` convention DID have an N# owner (`AnalyzerVariableDeclaration.nl:475`, `== 2`) — the editor's `>= 2` was a REAL DRIFT painting `catchResult` on an ordinary 3-name deconstruction; (b) there are FOUR primitive-name answers, and analyzer's 16 ∪ columnar's 17 = the editor's 18 EXACTLY; (c) a THIRD copy of the interpolation scan already ships in `ColumnarParserRecovery:7547–7700`. | comparator 108 rows before/after, EXACTLY ONE ROW MOVES (`variable\|catchResult 'err'` → `variable 'err'`); matrix 7 mutations, each moving only its own surface; IL census 25 assemblies / 86,830 bodies / 2,434 stale-skipped; estate 6,821 → 6,861; gate VS Code-enabled 25m16s, 127 steps, VS Code `36 passing (41s)` |
| 021 slice 5 (cut 1 of the LSP six) | `d04d2d932` (landed); 7 paths | Four rerouted `.cs` 2,317 → 2,231 (−86 lines, −79 non-blank, NOT ONE LINE ADDED): `SemanticTokensHandler.cs` 1,045 → 1,021 (77-entry `KeywordTokenTypes` deleted → `Lexer.IsReservedKeyword`), `GoToImplementationHandler.cs` 285 → 272 and `TypeHierarchyHandler.cs` 414 → 402 (the 9-line `TypeReferenceMatchesName`, duplicated verbatim in both, deleted → `CodeIntelligenceDisplayText.InterfaceNameMatches` at 7 call sites), `TypeResolver.cs` 573 → 536 (dead `FormatTypeName` deleted). Writes NO N# — both owners already shipped. | THE KEYWORD DRIFT WAS A REAL EDITOR BUG: the lexer answers 85, the editor's hand-copy 77; the 9 missing (`alloc allow must newtype private public scoped stackalloc unsafe`) fell through to the TextMate guess, and the 1 extra (`Test`) is UNREACHABLE — the lexer has no arm producing `TokenType.Test`. So the reroute is strictly additive. `OWN004` fires on a SHRINK too: the ceiling is an EXACT match. | comparator 84 → 87 rows, exactly the 3 predicted keyword spans; matrix M1 moves 30 rows / M2 moves 12, each only its own surface; IL census `CodeIntelligenceDisplayText` 14 → 23 distinct external callers, `Lexer` 11 → 12; unit 606/0, estate 6,821/0; gate VS Code-enabled 33m24s, 127 steps, `36 passing` |
| 021 slice 4 | `ce5b7e939` (landed); 8 paths | `src/NSharpLang.Compiler/AstNodeFinder.cs` DELETED WHOLE (15 lines / 13 non-blank, one member + a dead synthesised ctor); both LSP consumers (`CompletionHandler.cs:198`, `HoverHandler.cs:67`) route directly to `AstNodeFinderCore.FindExpressionAtPosition(…) as Expression` LINE FOR LINE (both files unchanged at 700/611 and 307/264, fingerprint-only rows). `AstNodeFinderCore.nl` 376 → 389 (13-line ownership header). `src/NSharpLang.Compiler` 11 files / 27,981 → 10 / 27,966. | THE HOVER SITE IS PINNED BY NONE OF THE 133 `LanguageServerTests`: M1 makes the finder answer `null` ALWAYS and not one hover body notices, because `TryResolveExpression` handles only `IdentifierExpression` and the word-based fallback at `:87` produces byte-identical hovers. M2 (a one-column boundary shift) fails ZERO tests. `as Expression` is a LATENT GUARD — total over today's AST, kept because the owner returns `object?`. | IL census `AstNodeFinder` 6 sites / 2 callers → 0 / 0, TypeDef gone; `AstNodeFinderCore` 4 distinct external callers (both LSP handlers, forwarder gone); seam 13 = 13 byte-identical (1,596 bytes each), M1 moves 3 rows / M2 moves 1; estate 6,821/0; unit 606/0; gate VS Code-enabled 26m00s, 127 steps, `36 passing` |
| 021 slice 3 | `82f70d052` (landed); 8 paths | `SystemsAnalyzer.cs`'s three ordering sites (`:86` file walk `OrdinalIgnoreCase`, `:103` trusted sites file/line/column, `:244` calls `Distinct(Ordinal)+OrderBy(Ordinal)`) → NEW `SystemsReportOrder.nl` (251 lines) + `.tests.nl` (295 lines, 24 blocks). A FOURTH order came with them: `OrderedFindings`, already N# inside `SystemsFindingSink`, moved so the family has ONE owner of row position — `SystemsFindingSink.nl` 305 → 233. `SystemsAnalyzer.cs` holds 1,160/1,065 LINE FOR LINE (fingerprint-only row); its SORT census 3 → 0 and all four slice-1 instruments read 0. | TWO OF THE THREE ORDERS WERE UNPINNED BY ANYTHING: the repo's max `trustedSites` anywhere is ONE (a one-row list has no order), and all 80 pinned `calls=[…]` values are 54 empty + 26 single-element + ZERO with two or more. Also `:86` is not "file order" but ROOT ORDER OF A DFS — the walk is re-entrant (`MergeDeclaredCalleeSummaries:456`) so a callee row precedes its caller. | estate 6,797 → 6,821; census 58 → 63 blocks / 1,960 → 2,090 lines; matrix 7 mutations all failing by name (M5 alone fails 7 blocks, six of them policy contracts depending on stability); comparator 12 = 12, 77,534 bytes byte-identical, M2 moves 3 of 12; gate run 2 `ALL TESTS PASSED` 24m06s, 126 steps |
| 021 slice 2 | `fec3c43da` (landed); 8 paths | `Columnar/ColumnarProgramInputBuilder.cs` 1,062 → 1,051 / 991 → 981 (`+69/−80`, the ONLY C# touched, zero new C#): 6 raw `TokenType` ordinal comparisons (4 decisions) → NEW `ColumnarTokenKindFacts.nl` (70 lines); 49 site ids + 49 sentences + 6 scan-stage names → `ColumnarDeclineReasons.nl` 170 → 290 (`ColumnarParseDecline` + 48 static properties + `DeclarationScan(code)`); 3 modifier bits → `ColumnarParserKernels.nl` (+24), and 3 that ALREADY had N# owners now simply call them. The private `Decline` helpers now take a `ColumnarParseDecline`, not `(string, string)`. | THE C# ORDINALS WERE A **THIRD** COPY IN A THIRD LANGUAGE: `git grep -n 'enum TokenType' --include='*.cs'` matches ZERO files and no `Token*.cs` exists — the kernel comments still citing "see Token.cs" are stale. The two real tables are `Token.nl:5`'s enum and the columnar lexer's hand-written `KeywordKind` ordinals. `131072` is `1 << 17`, one bit past `Modifiers.Override`, and is NOT a member of the `Modifiers` enum at all. | builder residue: SENTENCE 53 → 0, `"parse.*"` 49 → 0, raw `ck[]==int` 6 → 0, modifier-bit tests 5 → 0, `NSharpModifier*` constants 2 → 0; estate 6,778 → 6,797 (+19 blocks); comparator 54 pairs each side, MISSING `[]` EXTRA `[]`; matrix 5/5 fail by name; gate run 2 green 1,342s, 126 steps |
| 021 slice 1 (opening inventory) | `9ed10a390` (landed); 4 paths | `Columnar/ColumnarCompiler.cs` DELETED WHOLE (39 lines, 0 external / 0 self sites in 90 assemblies / 188,291 method bodies — its only consumers were five already-deleted C# test files). `MultiFileCompiler.cs` 665 → 663: `SharedAnalyzer` and `ProjectRoot` getters deleted (0 external, 0 self, shadowed internally by `_sharedAnalyzer`/`_projectRoot`). `src/NSharpLang.Compiler` 12 files / 28,033 → 11 / 27,992. | THE INHERITED AOT PREMISE IS OVERTURNED: **`DogfoodKernelLoader` DOES NOT EXIST** — retired at `3c963eb5d` ("Static bind columnar kernels and retire dogfood loader"), which is an ancestor of this tip; `git grep DogfoodKernelLoader HEAD` matches only this STATUS. The real AOT blocker is Reflection.Emit in `ColumnarIlEmitter.cs` (1,190 `OpCodes.` sites, 177 `TypeBuilder`) → a `MetadataBuilder` metadata writer, plus `Analyzer.cs`'s MLC. | census 90 assemblies / 188,291 bodies / 0 undecodable / 551 stale-skipped; product-decision census: `SystemsAnalyzer.cs` 0 sentences+0 codes but 3 SORT, `ColumnarProgramInputBuilder.cs` 53 sentences, `ColumnarIlEmitter.cs` 146; N# types NAMED: Analyzer 218, SystemsAnalyzer 128, ColumnarIlEmitter 99; estate 6,778/0, unit 606/0; gate green 1,346s, 126 steps |

**Durable findings (021).** The terminal verdict, the AOT blockers and the two-type-universe finding are in
§3.8.

- The `mechanical` claim rule is a MEASUREMENT, not a word: every survivor was swept for `NL\d{3}`
  literals, user-facing SENTENCES (≥ 20 chars, containing a space and a lowercase word, excluding dotted
  site-ids/paths/URLs), ordering sites and non-zero exit returns, then cross-referenced for how many
  N#-declared types it NAMES. `SystemsAnalyzer.cs` carries ZERO sentences and ZERO codes while naming 128
  N# types — *"a 1,160-line walk that names 128 N# types and writes zero sentences is not an owner"*
  (slice 1).
- MOVED, the decision half: 49 site ids + 49 sentences + 6 scan-stage names + 6 token ordinals + 6 modifier
  bits out of `ColumnarProgramInputBuilder.cs`; three ordering sites out of `SystemsAnalyzer.cs`; 13
  re-implemented decisions out of six LSP files (−495 lines with NOT ONE LINE ADDED); 12 residues out of
  `Program.Testing.cs`; the 5 daemon status keys and 3 `"2.0"` spellings; 14 of 17 decisions out of
  `EmitIlAssembly.cs`; 21 of 24 out of the MLC quarantine; 20 out of `TypeResolver.cs`; Groups B and C out
  of `PlaygroundRunner.cs` (slices 2, 3, 5, 5b, 6, 7, 8, 9, 9b, 11).
- MECHANICAL, each with a stated proof rather than a wave: MSBuild `Task` plumbing and Mono.Cecil API
  mechanics (the ecosystem contract fixes every spelling); JSON-RPC 2.0's eleven member names (the
  specification's §4/§5/§5.1 fixes them); xUnit's `TraitAttribute` arity; the MLC's 22 remaining extents
  (API mechanics, `AssemblyName.ReferenceMatchesDefinition`, filesystem probes performing paths the owner
  computes, host facts); and the reflection MECHANICS in `TypeResolver.cs` — caches are state not policy,
  and `ignoreCase: false` is a correctness property of the READ, not a curation choice.
- The honest verdict on the redrawn MLC quarantine is 22 mechanical, 3 NAMED-BLOCKED — not "zero decisions
  left". Three orchestration decisions survive in C# control flow and carry no literal, which is why the
  census cannot see them: non-NuGet dependencies load BEFORE NuGet ones, a TEST dependency contributes its
  package NAME where a normal one contributes a PATH, and `LoadReferencedAssembly`'s four-stage probe
  sequence (slice 9).
- A LATENT GUARD is kept and the REASON recorded rather than the observation: `as Expression` is total over
  today's AST but the owner returns `object?`; the `isNested` clause is unobservable because all 118 nested
  types in the editor's universe report `IsPublic == false`, but is load-bearing the moment a `Type`
  arrives from elsewhere. Conversely `IsTruthy` was proved unobservable and deliberately NOT moved —
  moving a decision nothing can observe would have been ceremony (slices 4, 9b, 11).
- The N# owner-of-record for one question must be ONE owner: slice 3 moved a FOURTH order
  (`OrderedFindings`, already N# inside `SystemsFindingSink`) purely so the family would not have two
  owners of "how a report row is positioned"; slice 5b routed `ColumnarIlEmitter.cs` LINE FOR LINE at its
  ceiling so the analyzer, the backend and the editor all name one `"err"` owner.
- THREE of slice 5's own census claims were OVERTURNED by 5b: the `"err"` convention DID have an N# owner
  (`AnalyzerVariableDeclaration.nl:475`, `== 2`) and the editor's `>= 2` was a REAL DRIFT painting
  `catchResult` on an ordinary 3-name deconstruction; there are FOUR primitive-name answers and analyzer's
  16 ∪ columnar's 17 = the editor's 18 EXACTLY; and a THIRD copy of the interpolation scan already ships in
  `ColumnarParserRecovery:7547–7700`.
- THE KEYWORD DRIFT WAS A REAL EDITOR BUG: the lexer answers 85 keywords, the editor's hand-copy 77; the 9
  missing (`alloc allow must newtype private public scoped stackalloc unsafe`) fell through to the TextMate
  guess and the 1 extra (`Test`) is UNREACHABLE, so the reroute is strictly additive (slice 5).
- THE CECIL REWRITE IS THE WHOLE OF N#→C# CONSUMABILITY, executed not reasoned: the un-rewritten
  implementation dll gives `csc` `error CS0012: The type 'Object' is defined in an assembly that is not
  referenced … System.Private.CoreLib`; the rewritten ref assembly builds clean. `System.Private.CoreLib`
  is the one runtime assembly with no reference-pack counterpart, which is why it is the one name the scope
  test checks (slice 8).
- THE COMPILER IS A STRONGER GUARANTEE THAN A CONTRACT: mutating `CultureInfo.InvariantCulture` →
  `CurrentCulture` DOES NOT COMPILE (`NL103` at `TestCommandKernels.nl:647:16`,
  `emit.call.instance-member-unmodeled`) because `ColumnarExternalBindingPlans.nl:313` models exactly ONE
  `CultureInfo` static member — the latent comma-decimal `duration` bug is not merely fixed, it is
  UNWRITABLE (slice 6).
- The C# `TokenType` ordinals were a THIRD copy in a THIRD language: `enum TokenType` matches ZERO `.cs`
  files and no `Token*.cs` exists, so the kernel comments citing "see Token.cs" are stale. The two real
  tables are `Token.nl:5`'s enum and the columnar lexer's hand-written `KeywordKind` ordinals, and `131072`
  (`1 << 17`, one past `Modifiers.Override`) is NOT a member of the `Modifiers` enum at all (slice 2).
- Some things had NEVER been pinned by anything before their slice: the three `nlc test` outcome words that
  decide the command's exit code; the five JSON-RPC error codes `-32700/-32600/-32601/-32602/-32603`; two
  of `SystemsAnalyzer.cs`'s three ordering sites (the repo's max `trustedSites` is ONE and all 80 pinned
  `calls=[…]` values are 54 empty + 26 single-element + ZERO with two or more); `BuildCommandKernels`,
  which had no estate contract at all (slices 3, 6, 7).
- Two shipped playground defects were filed as chips rather than absorbed: `04-unions-patterns`, a shipped
  tutorial example carrying a declared `ExpectedOutput`, DOES NOT RUN (`PatternMatches` at `:659–666`
  declares a binding only when `property.BindingName` is non-null, so the shorthand form binds nothing);
  `08-async-interop` fails `PG207` and is still offered behind a Run button. The playground's diagnostic
  space is 40 `PG` codes across two files and `git grep` finds not one documented (slice 11).
- Every slice re-verified its predecessor's census by DECODE rather than inheriting it, and that overturned
  findings repeatedly: slice 2 found six ordinal sites where slice 1 named two; 5b overturned three of
  slice 5's claims; 9 overturned three of five claimed consumers and corrected a `[Fact]` count; 9b found
  slice 9's 190/208 line split irreproducible; 12 falsified slice 1's "textbook glue" classification of
  `PlaygroundCompiler.cs` by measuring 24 sentences in it.

### 4.3 Task 020 — the C# test estate close-out (complete at `530bfbc85`, 45 slices; box CHECKED)

Outcome: `tests/*.cs` went from the ratchet's E0 epoch of 74 files / 68,217 lines / 12,111 assertion
markers to 24 / 20,277 / 2,800 (−50 files, −70% lines, −77% markers); 50 files were deleted whole
(42,216 lines) and 5,724 lines shrunk out of the 24 survivors. The C# unit suite fell 3,193 → 606 tests;
the compiler-service `.tests.nl` estate rose 5,075 → 6,778 cases from 6,756 `test` declarations across 268
files; `tests/native/*` went 29 → 46 projects. Both closing conditions held at slice 45: bucket (a) = 0
and the runner surface is N#-owned. The arc opened at `dc2c4ae20` (slice 1) and slice 2 committed at
`493a82eab`; most later slices are recorded against their tip.

| slice | commit | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| 020 slice 45 | `530bfbc85` (landed) | 28 bucket-(a) bodies deleted + 1 de-tautologised: `tests/CliParityAuditTests.cs` 1822→1194 (73→49 tests, −90 `Assert.`), `tests/IlSdkToolchainTests.cs` 334→282, `tests/ErrorRecoveryPipelineTests.cs` 478→455, `tests/AstChildrenTests.cs` DELETED WHOLE (147 lines/1 test + its 90-line reflective constructor kit) → 5 new estate `.tests.nl` (`AstChildrenCore`, `ProjectReferenceResolver`, `NSharpInstallRoot`, `UnifiedDiff`, `PackCommandKernels`), extended `Linter`/`ColumnarParserRecovery`, and `tests/native/cli-command-contracts` 51→77 blocks | Census sharpened: an owned type must REACH an assertion, and a local mutated in a scope inherits the owned types named in every enclosing scope HEADER — that asymmetry demotes `IlSdkToolchainTests.cs:126` (bare `RestoreCommand.Restore(…)` statement) to (c) while keeping `AstChildrenTests.cs:24` (mutated set) in (a). Both 020 conditions hold; box checked | estate 6709→6778 (+69); unit 634→606 (−28); native 51→77 blocks, 46 projects; 95 blocks/297 assert rows replace 28 bodies/95 rows; gate 126 steps, 24m59s; audit 18/18 |
| 020 slice 44 | `a70dead8d` (landed) | 19 bodies deleted + 2 de-tautologised: `tests/CliCommandTests.cs` 2805→1810 (56→39 tests, 507→240 `Assert.`), `tests/DaemonCommandTests.cs` 808→764; `src/NSharpLang.Cli/Program.Testing.cs` 618→617 with 5 new kernels (`GetRunTimedOutMessage`, `GetTestTimedOutMessage`, `IsSupportedTestMethodArity`, `GetUnsupportedTestArityMessage`, `GetTestFullName`) → 10 new estate `.tests.nl` + `BatchQueryKernels`/`TestCommandKernels` extended + native corpus 38→51 blocks | Condition (2) DISCHARGED but (1) FAILED on a file no prior slice measured: run over all 25 `tests/*.cs` the classifier found 30 more (a) bodies in `CliParityAuditTests.cs` (25), `IlSdkToolchainTests.cs` (3), `AstChildrenTests.cs` (1), `ErrorRecoveryPipelineTests.cs` (1) — every one of the 13 subjects a `.nl` with no C# counterpart | estate 6566→6709 (+143); unit 653→634 (−19); native 38→51; 156 blocks/662 rows replace 19 bodies/292 rows; 292 decoded rows, 0 missing; gate 126 steps, 23m08s; audit 18/18 |
| 020 slice 43 | `1b8fdc496` (landed) | 44 of 61 (a) bodies: `tests/CliCommandTests.cs` 4274→2805 (100→56 tests, 865→507 `Assert.`, all 28 `[InlineData]` left) → 9 new estate `.tests.nl` (`CompilationReferenceResolverKernels`, `Tidy`, `Doc`, `Fix`, `Watch`, `Restore`, `Format`, `FixCommandArgument`+`Check`, `Lint`), `TestCommandKernels.tests.nl` 31→190 lines, native corpus 21→38 blocks | Ownership was MEASURED not assumed and OVERTURNED the assumption: `WatchCommand` and `DocCommand` are `.cs`, so 6 of the 7 bodies driving `XCommand.Execute` reach a C#-owned command — the spawned successors are the only thing in the repository proving `nlc check` dispatches to `CheckCommand` at all | estate 6436→6566 (+130); unit 722→653 (−69 = 41 `[Fact]` + 28 cases); native 21→38; 147 blocks/624 rows replace 44 bodies/358 rows (+266 claims); 451 decoded rows, 0 missing; gate 126 steps, 1,325s |
| 020 slice 42 | `dde1d6e53` (landed) | 35 of 96 (a) bodies out of `tests/CliCommandTests.cs` 5482→4274 (135→100 tests, 1262→865 `Assert.`); dead `ExecuteRunWithIlBackend` deleted → 15 new estate `.tests.nl` (120 blocks) + NEW native project `tests/native/cli-command-contracts` (21 blocks), the 46th | OVERTURNS slice 41's census: the file holds 135 methods not 114 and 96 are (a) not 82, because a `*Kernels`-name instrument cannot see 13 N#-owned subjects without that suffix (two are pure static calls with no command wrapper). Route forced by a wall, not preference: `Console.SetOut` declines, so the estate can CALL `Execute` and never SEE what it printed | estate 6316→6436 (+120); unit 757→722 (−35); native projects 45→46; 141 blocks/583 rows replace 35 bodies/395 rows; 395 decoded rows, 0 missing; gate 126 steps, 23m09s; audit 18/18 |
| 020 slice 41 | `7584d5334` | `tests/SystemsNSharpTests.cs` FINISHER — whole remainder and the file: 60 methods/1,700 lines/1,226 decl lines/163 in-body `Assert.`/205 claim rows → two NEW native projects `tests/native/systems-analysis-census` (58 blocks) and `tests/native/systems-gauntlet-facts` (13 blocks), the 44th and 45th; 18 helpers incl. already-dead `FormatCompilerError` die with the file | OVERTURNS a standing campaign claim: `SystemsNSharpTests.cs` was NOT "the last canonical C# assertion layer" — that is true only of WHOLLY canonical files, and `CliCommandTests.cs` (a)=96 and `DaemonCommandTests.cs` (a)=4 had never been migrated since the slice-12 triage. Headline: 20 of 54 systems fixtures carry 22 non-systems ERROR rows, two undermining their own method's claim | unit 818→757 (−61); estate 6316→6316; native 43→45; C# estate 26 files/26,543 → 25/24,843; 694 asserts stating 4,751 cells (23.2× widening); gate 125 steps, 22m37s; audit 18/18 |
| 020 slice 40 | `2e42038ed` | `tests/SystemsNSharpTests.cs` 2402→1700: the ONE 544-line `[Fact]` that launches processes (`ExecutableSystemsProofProjects_…`, 212 in-body `Assert.`/266 claim rows) + 7 helpers → NEW native project `tests/native/systems-proof-corpus` (43 blocks, 880 lines, 30 kernels, NO dependencies), the 43rd | The endgame sketch's own predictions were overturned by the decode: the "38 process occurrences" are all the word `ExitCode` (`Process`/`ProcessStartInfo`/`StandardOutput`/`WaitForExit` = 0, launching delegated to the already-N#-owned `DotnetRunner`), and the "real build" was an IN-PROCESS `MultiFileCompiler` whose perf JSON the test file assembled itself. Route (a) — execute as a PROCESS — avoids the AOT `Assembly.Load` debt | unit 819→818; estate 6316→6316; native 42→43; 578 facts across 210 asserts vs 266 rows; 56 anchors, 0 mismatches; M2/M3 caught by nothing else; gate 123 steps, 22m01s; audit 18/18 |
| 020 slice 39 | `3c80e89e3` | `tests/QueryIntegrationTests.cs` DELETED WHOLE (1,322 lines / 65 `[Fact]` / 209 in-body `Assert.` / 219 claim rows) with 7 helpers → NEW native project `tests/native/query-integration` (65 blocks, 1,946 lines, 90 kernels), the 42nd | Slice 38's predicted capabilities BOTH retired: process launch is not needed (`Process`/`ExitCode`/`nlc ` occur ZERO times in the CODE class — every body is in-process) and JSON parsing is already owned by `ownership-audit`. Under the no-unused-infrastructure rule the spawn kernel was NOT BUILT | unit 884→819 (−65); estate 6316→6316; native 41→42; C# estate 27 files/28,567 → 26/27,245; 219 rows = 210 restated + 9 kernel-guard, +11 new; all 65 blocks move under perturbation; gate 122 steps, 22m00s |
| 020 slice 38 | `5ff035f5f` | `tests/PlaygroundCompilerTests.cs` CLOSED and DELETED WHOLE (821→0; 35 `[Fact]`/745 decl lines/191 in-body `Assert.`/194 claim rows; `AssertCompletion`, `LineNumberContaining`, `ColumnAfter` die) → 21 extend `tests/native/playground-diagnostic-spans` (74→116) and 14 land in NEW `tests/native/playground-tooling-surfaces` (19 blocks), the 41st; `tests/Tests.csproj` 65→64 loses the Playground ProjectReference | The split axis is what the body NAMES, not the response record (23/12 → 21/14): three bodies name `PlaygroundExamples` and move with the corpus. A native project cannot reference another native project, so nine base reflection kernels are DUPLICATED — cost stated, not hidden | unit 919→884 (−35); estate 6316→6316; native 40→41; 1,334 assert executions vs 194 rows (6.9×); 13 perturbation controls, 2 true non-movers both replaced by runtime runs (27/27 and 21/21); gate 21m48s |
| 020 slice 37 | `61b9f2519` | First cut of `tests/PlaygroundCompilerTests.cs` 1913→821: the 34 bodies naming `AssertPlaygroundSpan` (30 `[Fact]`+4 `[Theory]`/25 `InlineData`, 1,051 decl lines, 233 claim rows) and the helper (71 call sites, all inside the cut) → NEW `tests/native/playground-diagnostic-spans` (2,049 lines, 74 blocks, 23 kernels), the 40th; `tests/scripts/test-all-core.sh` 916→917 to build the playground in Step 2 | The `dll:` route to `NSharpLang.Playground` had never been walked and five of its spellings decline. Nothing in the gate built that assembly on purpose — it was a by-product of `dotnet test`, which would make a native project's dependency depend on a cacheable step | unit 974→919 (−55); estate 6316→6316; native 39→40; 1,286 asserts vs 233 rows (5.5×); 233 decoded/233 reconstructed/0 missing; 10 of 316 pinned anchors out of range, all length 7 (`<error>`); gate 21m40s |
| 020 slice 36 | `9e157d430` | `tests/AnalyzerTests.cs` FINISHER — last 46 `[Fact]`s / 974 decl lines / 86 `Assert.` / 45 fixtures / 86 claim rows and both surviving helpers (`Analyze` 15 consumers, `AnalyzeWithSource` 26); file DELETED WHOLE (1,127→0) → `tests/native/analyzer-clean-source` 18,954→21,167 (+2,213), 797→863 blocks, 38→66 kernels | Nine-slice campaign closes and the three columns close exactly: the per-slice deletions sum to 13,451 lines, 816 methods and 565 `Assert.` — the file's whole opening census. Two byte-identical fixtures reach OPPOSITE verdicts because the difference is the OTHER file in the directory | unit 1,020→974 (−46); native subject 862→928; estate 6316→6316; 1,070 asserts vs 86 rows (12.4×); 1,712 claim rows across the 9 slices; M2/M2b prove one sentence has two owners; gate 19m49s; audit 18/18 |
| 020 slice 35 | `06fdb2fd4` | `tests/AnalyzerTests.cs` tranche 7: the whole remaining `AssertNoErrors` family — 95 `[Fact]`s / 1,178 decl lines / ZERO in-body `Assert.` / 99 fixtures / 99 claim rows; `AssertNoErrors` DIES → `analyzer-clean-source` 17,045→18,954 (+1,909), 690→797 blocks, 38→38 kernels (none added) | Two fixtures are byte-identical to already-migrated ones but only ONE is a substitute: slice 28's contract pins five values and predates `AcUnitShape`/`AcParseSuccess`, so it satisfies neither the precondition nor the vacuity half of the four-part rule — measured by widening N0 from −98 to −99 and no further | unit 1,115→1,020 (−95); native 755→862; estate 6316→6316; 1,185 asserts vs 99 rows (12.0×); 99/99 hold on both routes, zero false cleans; append sweep 99/99 report; 10 mutation runs, 8 predictions, 2 computed misses; gate 19m20s |
| 020 slice 34 | `714aa6d9c` | `tests/AnalyzerTests.cs` tranche 6: 99 `[Fact]`s / 1,434 decl lines cut at the file's own lambda banner (line 2281), carrying all 17 `AspNetCoreConfig` sites; `AspNetCoreConfig`, its `ProjectConfig? config` parameters and the `LoadFromProjectConfig` branch deleted → `analyzer-clean-source` 14,944→17,045, 581→690 blocks, 33→38 kernels (first `ProjectConfig` group) | `LoadFromProjectConfig` consumes exactly ONE field, measured over six config spellings: `config.Sdk.Contains("Web")` is the whole trigger; `TargetFramework` is dead because `Dependencies` hands back an empty list. Only 5 of the 17 fixtures are config-sensitive at all | unit 1,214→1,115 (−99); native 646→755; estate 6316→6316; 1,183 asserts vs 99 rows (11.8×); 99/99 hold both routes; M6 (a 4-character C# edit in `Analyzer.cs`) caught by 6 contracts and nothing else; gate 19m01s |
| 020 slice 33 | `17f093780` | `tests/AnalyzerTests.cs` tranche 5: first line-cut third of the `AssertNoErrors` family, nudged back to the file's banner at 1727 — 87 methods (85 `[Fact]`+2 `[Theory]`) / 1,223 decl lines / ZERO in-body `Assert.` / 89 fixtures / 89 claim rows → `analyzer-clean-source` 13,153→14,944, 489→581 blocks, 31→33 kernels (`AcUnitShape`, `AcDeclName`) | The route split is about the SENTENCE, never the VERDICT: over 89 clean fixtures both entry points report empty census, `HasErrors == "False"` and zero rows — the other half of slice 32's 40-false-claims finding. M2 is a TRUE non-mover and a real ESTATE gap: `NL309`'s object-initializer arm's sentence is pinned by nothing in either suite — CLOSED at §5: the arm FIRES (it was never the defect), the sentence is now pinned over a class, an inherited field, a struct and a record, and the probe that proved it found three real NL309 holes elsewhere | unit 1,303→1,214 (−89); native 552→646; estate 6316→6316; 1,134 asserts vs 89 rows (12.7×); append sweep 89/89 report, zero non-movers; 9 mutations, 4 first-pass matches, 4 corrected, 1 true non-mover; gate 19m02s |
| 020 slice 32 | `9f2404b46` | `tests/AnalyzerTests.cs` tranche 4: all 33 remaining `AnalyzeWithSource`+`ErrorCode` methods (shape → ZERO) plus the whole 79-method `AssertHasError` family; helper DIES. 112 methods / 1,515 decl lines / 254 assert instances / 114 fixtures / 282 claim rows; file 7,332→5,643 across 53 runs → `analyzer-clean-source` 8,772→13,153, +112 declarations, +2 kernels (`AcTypes`, `AcExplanation`) | The two analyzer entry points put the SAME information in DIFFERENT FIELDS: plain says `Variable 'x' is typed as 'string'…` with a suggestion; production says bare `Type mismatch` with the content in `ActualType`/`ExpectedType`/`SourceSnippet`/`ContextualHint`. 40 of 282 claims FALSE on the other route; 36 of 126 row pairs underline different text; 8 of 9 absence claims vacuous — the campaign's worst ratio | unit 1,417→1,303 (−114); native 552 (first run green); estate 6316→6316; 3,984 pins vs 258 distinct C# claims (15.4×); 45 perturbation controls, 44 movers, 1 proven non-mover; 9 mutations, 7 exact predictions; gate 119 steps, 19m04s; audit 18/18 |
| 020 slice 31 | `b836dd0df` | `tests/AnalyzerTests.cs` 8,931→7,332 (−1,599 across 35 runs; 80 methods = 49 `[Fact]` + 31 `[Theory]`; `[Theory]` 34→3, `InlineData` 97→7); whole direct-`Analyze`+`ErrorCode` shape to ZERO + first 56 of `AnalyzeWithSource`+`ErrorCode` → `tests/native/analyzer-clean-source/AnalyzerCleanSource.tests.nl` 6,039→8,772, 80 declarations, NO new kernel | The one-argument `Analyze(unit)` route CANNOT MEASURE A TOKEN: all 23 anchor-LENGTH differences have `plain = 1`, never the reverse, because it is handed no source text; production reports the real width. This names the cause of slice 30's "TRUNCATED NL202 anchors". 5 of 13 absence claims vacuous (vs tranche 2's 34/35). | 570 claim rows in / 570 matched / 0 missing; native 438 pass; estate 6,316; unit 1,556→1,417; gate ALL TESTS PASSED, 18m46s |
| 020 slice 30 | `b85b80864` | `tests/AnalyzerTests.cs` 10,674→8,931 (−1,743 across 8 spans; 106 methods = 105 `[Fact]` + the campaign's FIRST migrated `[Theory]`); helpers `AssertHasErrorCode` + `AssertNoErrorCode` die with their last consumer → contract 3,471→6,039, 191→297 declarations (299 tests), 23→28 kernels, 1,884→3,579 asserts | THREE deleted `ObjectInitializer` `is typed as` assertions are TRUE ONLY OF THE ENTRY POINT NOTHING SHIPS — the production four-argument route collapses them to the bare `Type mismatch`. Estate holds hand-written COPIES of production sentences no code path feeds, so grepping contract text OVERSTATES what the estate pins (ME1, ME8). | 199 rows in / 199 matched; native 299; estate 6,316; unit 1,664→1,556; gate 19m05s |
| 020 slice 29 | `b2910fb2b` | `tests/AnalyzerTests.cs` 11,867→10,674 (−1,193 across 3 spans; 82 `[Fact]`; the last seven `#region`s → `#region` 7→0); four private helpers die (`AssertHasStrictError`, `AssertNoWarning`, `AssertHasParseError`, `AssertHasHint`) → contract 1,503→3,471, 109→191 contracts, 14→23 kernels | The two `Analyze` overloads ARE DIFFERENT ANSWERS: `Analyze(unit)` has ZERO production callers (only `MultiFileCompiler.cs:282` and `DocumentManager.cs:277`, both four-argument), truncates anchors, and never fills `ContextualHint`/`SourceSnippet` — 73 of 82 deleted assertions drove an entry point nothing ships, and on 15 rows production's MESSAGE is the WORSE one. | 134 rows / 134 matched; native 191; estate 6,316; unit 1,746→1,664; gate 19m02s |
| 020 slice 28 | `49dab4752` | Opens the `AnalyzerTests.cs` campaign. Tranche 1a: `tests/AnalyzerTests.cs` 13,451→11,867 (−1,584 across TWO spans; 109 `[Fact]`, 12 `#region` pairs) → NEW sibling `tests/native/analyzer-clean-source` (1,503 lines, 109 contracts, 14 kernels, 612 asserts); native project count 38→39 | `AnalyzerTests.cs` is a WHOLE-FILE NATIVE MOVE with no estate half; the contiguous region span is NOT the tranche — classify by what the body NAMES, never by where it sits (three un-regioned `ReflectionGenericReceiver_*` methods left behind). `NL412` underlines the callee NAME and never the parentheses, correcting slice 25's record. | 154 rows / 154 matched; native 109; estate 6,316; unit 1,855→1,746; gate 19m03s |
| 020 slice 27 | `50d89d26a` | `tests/AnalyzerSemanticModelTests.cs` remainder (643 lines, 18 `[Fact]`, 188 `Assert.`) DELETED WHOLE; ratchet row flips `existing-debt` → `removed` → `tests/native/analyzer-semantic-model` EXTENDED 1,515→2,408 lines, 33→51 contracts, 40→61 kernels; `tests/` 30→29 `.cs` files | The one new instrument is a **TypeInfo WALKER** built for the `AnalyzerTests.cs` campaign to reuse; each native project carries its own reflection plumbing by design — COPY the walker, do not share it. A `sealed class` anchors on `class` (modifier SKIPPED) but a `duck interface` anchors on `duck`. `TypeInfoFactories.nl` is N# and has NO estate contract at all. | 234 rows / 234 matched; native 51 (from 33); estate 6,316; unit 1,873→1,855; 38 native projects |
| 020 slice 26 | `29dfc1178` | First half of `tests/AnalyzerSemanticModelTests.cs`: 1,361→643 lines, 51→18 `[Fact]`, 323→188 `Assert.` (−718); the `FindColumn` helper and its `using System;` die → NEW `tests/native/analyzer-semantic-model` (1,515 lines, 40 kernels, 33 contracts); native project count 37→38 | A file with ONE subject too big for the ~700-line budget splits ACROSS SLICES, by INSTRUMENT — group A (33 query facts) vs groups B+C (18 nominal/diagnostic facts). Name-based cutting fails again: `Analyzer_RecordTypes_RecordStructFlagInSemanticModel` belongs to group B. The estate owns `SemanticModel`'s ALGEBRA (hand-fed); only a native project can reach the POPULATION that `Analyzer.Analyze` fills in. | 136 rows / 136 matched; native 33; estate 6,316; unit 1,906→1,873; gate ALL TESTS PASSED |
| 020 slice 25 | `b96203ff6` | `tests/ErrorHandlingTests.cs` DELETED (580 lines, 39 `[Fact]`, 54 `Assert.`, 95 markers); ratchet row flips `existing-debt` → `removed`; split 24 parse / 15 analyzer → `src/…/ColumnarParserErrorHandling.tests.nl` (602 lines, 26 declarations) + NEW `tests/native/analyzer-error-handling` (561 lines, 15); native count 36→37, estate 6,290→6,316 | First tranche whose clean-PARSE pin is non-empty by design: 17 designed diagnostics named `code@line:col+len`. `var x = 5` IS C#, NOT N# — the parser reads `var` as an `IdentifierExpression` statement and `x = 5` as a separate `AssignmentExpression`, so nearly every fixture has twice the statements its author intended. 21 of 24 parse methods asserted only `Assert.NotNull(unit)`. A ZERO-TEST RUN IS A NON-VERDICT, NEVER A PASS. | 57 rows / 57 matched, 47.5× widening; native 15; estate 6,316; unit 1,945→1,906; gate 117 steps |
| 020 slice 24 | `17ddbf88b` | TWO files deleted (540 C# lines, 22 `[Fact]`, 107 `Assert.`, both ratchet rows → `removed`): `tests/EventSubscriptionTests.cs` (183) split 5/5 → `src/…/ColumnarParserEventSubscription.tests.nl` (176 lines, 6 decls) + NEW `tests/native/analyzer-event-subscription` (316, 7); `tests/AnalyzerBindingMapTests.cs` (357) whole → NEW `tests/native/analyzer-binding-map` (425, 13). Native count 34→36 | A file can have TWO subjects, and a per-subject native project is the established shape (each carries its own reflection plumbing). `Assert.True(usages.Count >= 2)` hid that `FindAllReferences` over `Config` answers FIVE usages, THREE of them the same position `6:14`. A function parameter's declaration reports Kind `variable`, not `parameter`. | 144 rows in / 144 matched; events 7/7, binding map 13/13; estate 6,284→6,290; unit 1,967→1,945; 36 native projects |
| 020 slice 23 | `9776e6ec3` | `tests/AstNodeFinderTests.cs` DELETED (115 lines, 5 `[Fact]`, 21 `Assert.`, 30 markers; row → `removed`); FIRST file split across BOTH estates by subject → `src/…/AstNodeFinderCore.tests.nl` (209 lines, 6 decls, 21 finder rows) + NEW `tests/native/analyzer-identifier-binding` (307, 4, 9 analyzer rows); native count 33→34 | The mandate's named capability (a native test project taking a PROJECT REFERENCE) was MEASURED AND NOT BUILT: the decline is in the EMITTER'S TYPE RESOLUTION (`emit.local.initializer` / `emit.local.unsupported-type`), not in how the assembly arrives — a `project:` reference builds the assembly and changes nothing about whether its types can be named, and `project:` requires a `project.yml` so `NSharpLang.Compiler.csproj` cannot be one at all. | 30 rows / 30 matched, 10.2× widening; native 4/4; estate 6,278→6,284; unit 1,972→1,967; gate 18m59s |
| 020 slice 22 | `fd9da30a3` | The `ParserTests.cs` FINISHER: whole file DELETED (`0 883`, 30 `[Fact]`, 824 method lines, 197 in-method `Assert.`, both private helpers `Parse`/`AssertHasParseError`, the stray `it(` marker; row → `removed`) → `src/…/ColumnarParserKeywordLambdaType.tests.nl` (700 lines, 30 decls, 64 asserts); `AstEq.FieldNames` and `Golden` needed ZERO new entries | Campaign closed: 212 `[Fact]`s / 5,896 method lines over six tranches; with `ParserErrorTests.cs` the parser's whole C# assertion layer (316 xUnit cases, 8,044 lines) is N#. Slice 21's rule that "an `ArrayTypeReference`'s Span is its ELEMENT's span" is CORRECTED: that is the sized-array-`new` path only — in DECLARED-TYPE position the array span COVERS its own brackets (4 of 4). | 331 rows / 331 matched, 14.2× widening; 25 mutations, 25/25 own-counts predicted; estate 6,248→6,278; unit 2,002→1,972 |
| 020 slice 21 | `76873437b` | `tests/ParserTests.cs` 1,911→883 (−1,028, `0 1028`, byte-verified pure; 60→30 `[Fact]`, 459→199 `Assert.`); the call-and-access tier (30 methods / 998 lines / 260 `Assert.`) → `src/…/ColumnarParserCallAccess.tests.nl` (617 lines, 30 decls, 60 asserts); ZERO new `Golden` builders and ZERO registry entries — the first tranche to need neither | Of the 368 decoded C# rows, the number stating a `Line`, `Column`, `Span`, `NameLine` or `NameColumn` is **ZERO** in 998 lines and 260 assertions — a parser that moved every member access, index, call, range, `new`, initializer and array literal one column right would have passed all 30 deleted tests. M18b (`^n` → Negate) has ZERO siblings in the 6,248-contract estate. | 368 rows / 368 matched, 9.8× widening, 419 pinned nodes; 18 mutations, no survivors; estate 6,218→6,248; unit 2,032→2,002 |
| 020 slice 20 | `0e9c7ca88` | `tests/ParserTests.cs` 2,655→1,911 (−744, `0 744`, ZERO added lines; 93→60 `[Fact]`, 668→459 `Assert.`); four small families (file header, literals/interpolation, attributes, preprocessor: 33 methods / 711 lines / 209 `Assert.`) → `src/…/ColumnarParserSmallFamilies.tests.nl` (627 lines, 33 decls, 79 asserts) + `ColumnarParserAst.tests.nl` `+57/−0` (9 builders) | SUSPECTED DEFECT pinned as measured, not endorsed: in a RAW interpolated string a `:` followed by optional whitespace SWALLOWS the next brace group into the literal text run instead of opening a hole (the colon may sit on an earlier line; only the FIRST following group is swallowed; ordinary `$"…"` unaffected). `TestInterpolatedRawString`'s `Assert.Single(...OfType<InterpolatedStringHole>())` passed BECAUSE of the bug. An attribute-free parameter carries a NULL `Attributes` list, not an empty one (M17 blast radius 77). | 261 rows / 261 matched, 8.6× widening, 263 nodes; 18 mutations, all 18 own-counts predicted; estate 6,185→6,218; unit 2,065→2,032 |
| 020 slice 19 | `cbc981a08` | `tests/ParserTests.cs` 4,098→2,655 (net −1,443, byte-verified; 139→93 `[Fact]`, 1,013→668 `Assert.`); patterns/`match`, parameter/argument modifiers, operator+conversion overloads, constructor initializers (46 methods / 1,397 lines / 345 `Assert.`) → `src/…/ColumnarParserPatterns.tests.nl` (1,023 lines, 46 decls, 98 asserts) + `ColumnarParserAst.tests.nl` `+50/−0` (5 builders incl. `OpFunc`) | A fact the deleted C# could not see is NOT automatically a fact nothing had recorded: the draft claimed seven new shape facts and the SIBLING SWEEP showed five already pinned by stage-N+1c tranches 9c/10/11 and a sixth half-new — the mutation row's `siblings` column is evidence about NOVELTY, not just blast radius. A parenthesized pattern is a ONE-element `PositionalPattern`; there is no parenthesized-pattern node. | 489 rows / 489 matched, 13.5× widening, 837 nodes; 18 mutations, no survivors, 8/8 node-kind own-counts predicted; estate 6,139→6,185; unit 2,111→2,065 |
| 020 slice 18 | `8c40ba048` | `tests/ParserTests.cs` shrunk 4,729→4,098 (23 of 162 `[Fact]`s / 608 lines / 140 `Assert.` — the statement + test-DSL family) → new `ColumnarParserStatements.tests.nl` (505 lines, 23 decls) + 8 returning builders in `ColumnarParserAst.tests.nl` | The naive slice-tag attribution predicate OVER-counts: `s18` matches 29 names, strict `Test_020S18ParserStatements` matches 23 — six parity contracts carry Parser.cs line numbers (`…Parsercs1890`). Use the runner's FULL generated prefix, never the bare tag. | estate 6,116→6,139 (+23), unit 2,134→2,111, C# estate 51,256→50,625; 198/198 matched 0 missing, 2,239 N# rows (12.5× widening); 15 mutations; gate PASSED |
| 020 slice 17 | `d56e42f27` | `tests/ParserTests.cs` shrunk 6,087→4,729 (50 of 212 `[Fact]`s / 1,358 lines / 350 `Assert.` — the declaration family) → new `ColumnarParserDeclarations.tests.nl` (906 lines, 50 decls) + full-arity `Golden` builders | `src/NSharpLang.Compiler/Parser.cs` DOES NOT EXIST and `ParseFileAst` has five production callers, so BOTH halves of `ColumnarParserAst.tests.nl`'s "TESTS-ONLY / Parser.cs sole authority" header are FALSE — there is no second parser left as an independent oracle; post-cutover goldens are behavioural snapshots. | estate 6,066→6,116 (+50), unit 2,184→2,134, C# estate 52,614→51,256; 432/432 matched 0 missing, 6,805 N# rows (10.9×); 14 mutations; gate PASSED 18m46s |
| 020 slice 16 | `4971c9cd4` | `tests/ParserErrorTests.cs` DELETED WHOLE (1,914 lines / 91 methods / 104 xUnit cases) → new `ColumnarParserErrorRecovery.tests.nl` (1,498 lines, 103 decls); one comment-only edit at `ColumnarParserRecovery.nl:4173` | `ParseFileAst` returns diagnostics in RECORDING order; `ParseFilePreamble` returns them POSITION-SORTED — proved by execution (`NL102@3:13+3;NL106@2:6+4;` vs the reverse). Every consumer that prints `result.Errors` sees the unsorted one and nothing stated it. | estate 5,963→6,066 (+103), unit 2,288→2,184, C# estate 36→35 files / 54,528→52,614; 660 in, 628 matched / 32 routed / 0 missing; 13 mutations; gate verdict NOT read at write time |
| 020 slice 15 | `48f74a25d` (landed); record has NO header bullet in the source, it is nested inside slice 16's bullet | `tests/ProjectFileTests.cs` (903) + `tests/ExampleLintTests.cs` (670) both DELETED WHOLE → 7 new + 2 appended estate contracts (1,884 lines, 81 decls): `ProjectFileParser`, `ProjectConfigModels`, `Reference`, `AssemblyVersionUtilities`, `ProjectSourceFileFilter`, `ExampleProjectCorpus`, `LinterFileImportUsage` | The estate is the BOTTOM of the dependency graph — `NSharpLang.Compiler` references BootstrapServices, never the reverse — so NO estate `.tests.nl` can reach `Analyzer`, `SemanticModel`, `BindingMap`, `CodeIntelligenceService`, `MultiFileCompiler` or a CLI command; those need a `tests/native/*` project with a `Compiler.dll` dep. | estate 5,882→5,963 (+81), unit 2,368→2,288, C# estate 38→36 files / 56,101→54,528; 176 in, 157 matched / 19 routed / 0 missing; 14 mutations; gate PASSED 18m41s, 113 steps |
| 020 slice 14 | `30e60cee2` (landed) | `tests/FixApplicatorTests.cs` (554) + `tests/LinterUnusedVariableTests.cs` (469) + `tests/DiagnosticGoldenTests.cs` (306) DELETED WHOLE → 5 new + 1 appended estate contracts (2,134 lines, 59 decls); the C# forwarder `OutputFormatter.DiagnosticsToText` leaves the assertion path | The "top 25" diagnostic golden suite holds TWENTY-FOUR diagnostics (5 parser / 9 analyzer / 10 linter); the shipped fixture's own first line has said `24 groups, 24 diagnostics` since check-in and nothing compared the two. PINNED, not corrected — renaming means choosing a 25th diagnostic, a product-content decision. | estate 5,823→5,882 (+59), unit 2,430→2,368, C# estate 41→38 files / 57,430→56,101; 93/93 matched 0 missing; 11 mutations, ZERO equivalent mutants; gate PASSED 18m50s |
| 020 slice 13 | `b8f5126cd` (landed) | `tests/ErrorReportingTests.cs` (541) + `tests/CodeFixTests.cs` (598) DELETED WHOLE → 5 new estate contracts (1,970 lines, 85 decls): `CompilerError`, `ErrorSuggestions`, `ErrorSuggestionHelpers`, `ErrorMessageBuilder`, `CodeFix` | `HumanExplanation` ALONE selects the renderer (rust-style vs Elm-style) — proved by adding only that field to the same error and watching the whole rendering flip. The two renderers indent their marker differently: rust-style `Column-1`, Elm-style `Column-1+6` to clear its `{Line}\|     ` gutter. | estate 5,738→5,823 (+85), unit 2,489→2,430, C# estate 43→41 files / 58,569→57,430; 191/191 matched 0 missing; 9 mutations (M3 a proven equivalent mutant, replaced by M3b); gate PASSED 18m54s |
| 020 slice 12 | `23b2671aa` (landed) | TRIAGE of all 45 C# test files / 58,744 lines into buckets (a)(b)(c)(d), plus the 5 cheapest DELETED WHOLE (547 lines): `NullabilityMetadataTests.cs` 59, `ColumnarDeclarationScanTests.cs` 67, `LocalFunctionTests.cs` 84, `DiagnosticClusteringTests.cs` 137, `ColumnarLiteralFactsTests.cs` 200 → 3 new + 3 appended estate contracts + 2 files in `tests/native/columnar-emit-facts` (1,485 lines, 67 decls) | Disk fixtures and process launching are NOT estate blockers (`LinterConfig.tests.nl` writes temp trees, `DotnetRunner.tests.nl` starts real `dotnet`). The real wall is ASSEMBLY REACH, and `tests/native/*` already crosses it — so "needs `new Analyzer()`" is a ROUTE, not a block. | estate 5,675→5,738 (+63), unit 2,518→2,489, C# estate 45→40 files / 58,744→58,197; 123/123 matched; 7 mutations (M4 equivalent, replaced by M4b); native project count stays 33; `columnar-emit-facts` 11/11→15/15 |
| 020 slice 11 | `a0336f203` (landed) | The five "blocked mini-clusters" DELETED WHOLE (369 lines): `ColumnarRuntimeTypeFactsTests.cs` 20, `ColumnarPatternFactsTests.cs` 66, `NumericLiteralFactsTests.cs` 80, `ColumnarNumericFactsTests.cs` 101, `ColumnarTypeCanonicalizerTests.cs` 102 → 5 new estate contracts + the 33rd native project `tests/native/columnar-emit-facts` (1,090 lines, 57 decls) | ALL FIVE blocks dissolve and NONE because a toolset row moved: the slice-3/4 block verdicts were ROUTE-shaped, recorded against the `tests/native` table route, and four of the five clusters never belonged there. `NL310` was never a `typeof` verdict — 116 estate `.tests.nl` files already spell `typeof`. | estate 5,629→5,675 (+46), unit 2,603→2,518 (85 cases), native projects 32→33; 118/118 matched 0 missing; 6 mutations; gate PASSED 18m52s, 113 steps |
| 020 slice 10 stage 2 | `f00130366` | `tests/CompletionEngineTests.cs` (322/12/49) DELETED WHOLE → `tests/native/completion-engine` (32nd native project, 523 lines, 12 decls); `tests/CodeIntelligenceTests.cs` 1,354→62 SPLIT 44/1 → 3 new estate contracts (`OutputFormatterJsonKernels` 654, `OutputFormatterTextBuilders` 605, `OutputFormatterDiagnosticKernels` 242; 1,501 lines, 59 decls) | Two mutations came back green and BOTH were holes, not agreement: a substring assertion cannot pin what a line STARTS with (a 3-`─` Elm header still `Contains` the 2-`─` one), and suppression was never stated to be CODE-SCOPED (broadening it past `Code == "NL020"` left all 5,629 green). Both contracts were strengthened and then failed their own mutation. | estate 5,570→5,629 (+59), unit 2,659→2,603 (44+12), native 31→32; 125/125 + 49/49 matched, 0 missing; 12 mutations; gate PASSED 19m10s, 112 steps |
| 020 slice 10 stage 2 probe verdicts | measured at `a0bf7e89a`; no production or contract file changed this turn | Nothing moved — probe-only record establishing the 44/1 split before any migration edit | `CultureInfo` is unreachable in BOTH directions (`CultureInfo.CurrentCulture` and `new CultureInfo("tr-TR")` both decline at `emit.local.initializer`), so `DiagnosticsToText_UnknownSeverityUsesInvariantFallback` CANNOT be migrated without weakening it — that one fact is the cluster's split point. | 4 walls measured; `JsonElement` enumeration unreachable 3 ways; the 2-space root-key line scanner replaces `SequenceEqual`; tree clean |
| 020 slice 10 stage 1 | `a0bf7e89a` | No C# deleted (`git diff -- '*.cs'` EMPTY). Published the `IReadOnlyDictionary<K,V>` two-argument widening: 3 arms in `TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition` + 1 new declaration in `AnalyzerAssignabilityFacts.tests.nl`; new `tests/native/readonly-dictionary-widening` (31st project, 291 lines, 9 decls) | Finding 90.8's new shape: the missing half was a GATE ABOVE an already-published row, not a peer catalog. `ClassifyKnownGenericAssignability` reaches `IsKnownGenericConversion` only after `HasKnownRuntimeGenericDefinition` admits BOTH sides, and that table listed fifteen ONE-argument heads and no two-argument one — and the wall was CONTRACT-PINNED as a wall. | estate 5,569→5,570 (+1); native 30→31, 9/9; non-vacuity: row reverted → 14 `NL202`s native + exactly 2 estate failures; audit 18/18 with NO REPIN (first in the arc); gate PASSED 18m57s |
| 020 slice 9 | `7c251b3da` (landed) | `tests/FormatterTests.cs` DELETED WHOLE — the arc's largest cluster (2,132 lines / 121 `[Fact]`s / 148 `Assert.`) → `FormatterSourceText.tests.nl` (577, 71 decls) + `FormatterConfig.tests.nl` (223, 15 decls); 86 decls, 800 lines | The mutation proof found a real hole: deleting the space after the comma in `FormatterWalk.FormatAttributeInline` left all 5,568 green, because every attribute in the deleted file carried exactly ONE argument so the `index > 0` separator branch was never executed anywhere in the estate. | estate 5,483→5,569 (+86), unit 2,780→2,659 (121 cases); 166 C# rows in, 163 distinct, 163/163 matched 0 missing 37 extra (3 duplicate claims were the deleted file's own); 8 mutations → 32 failures; gate PASSED 19m, 110 steps |
| 020 slice 8 (short note) | `e476bf912` (landed) | Short "Current iteration" note restating the `tests/LinterTests.cs` whole-file deletion: 1,366 C# lines / 87 xUnit cases → 109 declarations across four estate files | Duplicate summary of the slice-8 full record below; adds nothing new. `DiagnosticCatalog` and `LinterBindingUsageCore` had NO estate coverage at all and are now crossed rather than sampled; `DocsUrlFor`'s stored-URL arm executes for the first time. | — |
| 020 slice 7 (short note) | `3d10916cb` (landed) | Short note restating the `tests/LexerTests.cs` migration (894 C# lines / 77 xUnit cases) | Duplicate summary of the slice-7 full record below. The keyword table the deleted file SAMPLED is now CROSSED; the dead sweep corrected three live documentation rows for the first time in the arc. | — |
| 020 slice 6 (short note) | `0a91a21e5` (landed) | Short note restating the third batch migration: 3 cheapest estate clusters + the one `tests/native` row re-classified as estate-routable (1,058 C# lines, 110 xUnit cases, 4 `[Theory]`s) | Duplicate summary of the slice-6 full record below. Two walls: omitted default arguments on STATIC methods, and `TimeSpan` member reads. | — |
| 020 slice 5 (short note) | `e05276aeb` (landed) | Short note restating the second batch migration: 5 cheapest estate-routable clusters (874 C# lines, 39 xUnit cases) priced by a nine-round probe | Duplicate summary of the slice-5 full record below. Three walls routed around, one of them a reserved word (`scoped`). | — |
| 020 slice 4 (short note) | `05d65da38` (landed) | Short note restating the first batch migration: the five cheapest estate-routable clusters of slice 3's sixteen, probed live in one file before they were written | Duplicate summary of the slice-4 full record below. | — |
| 020 slice 3 (short note) | `92798b61c` (landed) | Short note restating the wall-count sweep over 74 `*Tests.cs` files and the migration of `tests/OperatorFactsTests.cs` into the BootstrapServices estate | Duplicate summary of the slice-3 full record below. The async row is the estate's MOST expensive territory (142 of the 134-test demand row live in `LanguageServerTests.cs`: 10 wall kinds, 25 C# receivers). | — |
| 020 slice 2 (short note) | `493a82eab` (landed) | Short note restating that the SKIP capability was measured and DECLINED — nothing built; `tests/ParserLiteralFactsTests.cs` migrated instead | Duplicate summary of the slice-2 full record below. The census names `async Task` (134 real tests) as the next capability by demand. | — |
| 020 slice 8 | `e476bf912` (landed); tip `3d10916cb` | `tests/LinterTests.cs` DELETED WHOLE (1,366 lines, 79 `[Fact]` + 4 `[Theory]`×8 rows = 87 xUnit cases) → `Linter.tests.nl` 467→1,060 plus three NEW files (`DiagnosticCatalog.tests.nl` 408, `LinterConfig.tests.nl` 262, `LinterBindingUsageCore.tests.nl` 100); 109 decls, 282 assert lines | A cluster's risk lives in HOW IT BUILDS ITS INPUT, not in what its subject is about — this OVERTURNS slice 7's own warning that `Linter`/`Formatter` should be priced above their line counts. `LinterTests.cs` never constructs an AST; it is string-in / primitive-out, structurally the same shape as `Lexer`. | estate 5,374→5,483 (+109), unit 2,867→2,780; 190 in, 190 matched, 0 missing, 281 extra; 8 perturbations, 6 mutations → 11 failures; gate PASSED 18m49s, 110 steps |
| 020 slice 7 | `3d10916cb` (landed); tip `0a91a21e5` | `tests/LexerTests.cs` DELETED WHOLE (894 lines / 77 `[Fact]`s / 0 `[Theory]`s) → `Lexer.tests.nl` (1,675 lines, 55 decls, 433 assert lines) | The sample-to-cross conversion is worth more than the migration: 16 single-keyword `[Fact]`s become one 85-row sweep that PROVABLY subsumes them (the keyword-text perturbation moves exactly `TestWhenKeyword`'s three rows and no other), plus a partition guard over the whole 148-member `TokenType` enum. | estate 5,319→5,374 (+55), unit 2,944→2,867; 279 in / 1,181 N# rows, 279 matched 0 missing 902 extra; 7 perturbations, 6 mutations → exactly 6 failures with zero collateral; gate PASSED twice (18m39s, 18m35s) |
| 020 slice 6 | `0a91a21e5` (landed); tip `e05276aeb` | `tests/PreprocessorTests.cs` 303, `tests/BindingMapTests.cs` 332, `tests/DiagnosticSpanResolverTests.cs` 358 and `tests/DotnetRunnerTests.cs` 65 ALL DELETED WHOLE (1,058 lines / 110 xUnit cases) → 4 new estate contracts (1,908 lines, 95 decls, 441 asserts) | The `tests/native` classification of `DotnetRunnerTests` was OVERTURNED by measurement: `DotnetRunner.nl` is a file of THIS project, so the estate reaches it directly and five real `dotnet` processes run green inside the estate host. | estate 5,224→5,319 (+95), unit 3,054→2,944; 353 in / 884 N#, 353 matched 0 missing 532 extra; 4 mutations, zero collateral; gate PASSED twice (18m34s, 18m32s) |
| 020 slice 5 | `e05276aeb` (landed); tip `05d65da38` | `tests/TypeReferenceFactsTests.cs` 137, `AnalyzerBindingFactsTests.cs` 123, `PerformanceFactStoreTests.cs` 155, `ParserTokenFactsTests.cs` 207, `SemanticModelTests.cs` 252 ALL DELETED WHOLE (874 lines / 39 xUnit cases) → 5 new estate contracts (2,271 lines, 83 decls, 441 asserts) | A probe that compares SHAPES cannot be exhaustive: the third wall (a tuple literal with a `null` element declining at `emit.expression.unhandled-kind`) appeared only when the REAL contracts were built, after the probe had cleared `null` as a bare argument and a tuple literal with a string separately. | estate 5,141→5,224 (+83), unit 3,093→3,054; 1,464 in / 1,906 N#, 1,464 matched 0 missing 410 extra (`ParserTokenFacts` alone: 9 sweeps × 148 = 1,332 rows); 5 mutations zero collateral; gate PASSED 18m36s |
| 020 slice 4 | `05d65da38` (landed); tip `92798b61c` | `tests/TaskLikeTypeFactsTests.cs` 50, `GeneratorSequenceTypeFactsTests.cs` 57, `AnalyzerOverloadSignatureFactsTests.cs` 75, `LoopSequenceTypeFactsTests.cs` 81, `ColumnarDeclineReasonFactsTests.cs` 103 ALL DELETED (366 lines / 65 xUnit cases) → 4 new + 1 grown estate contract (48 decls) | The estate REFUSES an array literal whose elements are constructed objects (`[new SimpleTypeReference(…), new ArrayTypeReference(…)]` declines at `emit.local.initializer`) — which is why the estate's 171 existing `.tests.nl` files build object arrays with `new T[](n)` plus index assignment. The idiom was load-bearing, not stylistic. | estate 5,093→5,141 (+48), unit 3,158→3,093; 130 in / 379 N#, 130 matched 0 missing 248 extra; 5 mutations + 1 collateral sibling failure (evidence, not damage); gate PASSED 18m32s |
| 020 slice 3 | `92798b61c` (landed); tip `493a82eab` | `tests/OperatorFactsTests.cs` DELETED (98 lines / 6 `[Fact]`s / 57 `Assert.`) → `OperatorFacts.tests.nl` in the BootstrapServices estate (265 lines, 10 decls, 133 asserts) | The `tests/native` estate has a CAPABILITY CEILING and it is the ARGUMENT-TYPE SET: a dependency-assembly static call emits with literals/locals/arrays and declines the moment an argument is a CONSTRUCTED object (`emit.local.initializer`) or an ENUM MEMBER (`emit.typed-local.initializer` / `emit.call.static-member-unmodeled`; in a table row it is refused earlier still by NL310). String/int/bool-in goes to `tests/native`; everything else belongs in the estate. | estate 5,083→5,093 (+10), unit 3,164→3,158; 57 in / 121 N#, 57 matched 0 missing 64 extra; 4 mutations naming exactly their 4 declarations; sweep costed 74 `*Tests.cs` files by WALL COUNT; gate PASSED 18m24s |
| 020 slice 2 | `493a82eab` (landed); tip `3ed71b4a0` | Nothing built for `skip`. `tests/ParserLiteralFactsTests.cs` DELETED (47 lines / 3 `[Theory]`s / 22 `[InlineData]` rows) → `tests/native/parser-literal-facts` (8-line `project.yml` + 76-line contract, 22 cases from 3 declarations) | THE SKIP CAPABILITY WAS MEASURED AND DECLINED: across 2,818 attributed test methods in 279 classes there are ZERO `[Fact(Skip=…)]`, `SkipException`, `[ConditionalFact]` or trait/`.runsettings` filters. The one true `Skip=` is `DockerFactAttribute` in a project the gate never runs, and the six `if (!Directory.Exists(…)) return;` guards in `ExampleLintTests.cs` are RUNTIME conditions N#'s STATIC `skip "reason"` modifier cannot express. Unused runner infrastructure is not completion. | unit 3,186→3,164 (exactly 22 rows); 22 in / 22 out, 0 differing; 4 mutations each failing exactly 1 of 22; `async Task` probed and OVERTURNED — already served (a plain `test` body may `await` and failures survive it); only the `async test "…"` DECLARATION form is missing and no C# test needs it |
| 020 slice 1 | `3ed71b4a0` (landed); tip `dc2c4ae20` | Table-driven test cases shipped as an N# LOWERING (6 new kernels + 1 rewritten contract in `ColumnarParserKernels.nl`); `tests/DocQueryTests.cs` DELETED (122 lines / 7 tests / 37 assertion markers) → `tests/native/doc-query/DocQuery.tests.nl`, 11 cases from 5 declarations. `Program.Testing.cs` 653→618 (`GetInlineDataRows` deleted whole as provably unreachable); `ColumnarProgramInputBuilder.cs` 1062→1062, two same-line edits | The table-driven surface was ALREADY in the language everywhere except emit — `TestDeclaration` carries `TableParameters`/`TableCases`/`SkipReason`, the recovery parser parses the clause, `AdvanceTest` phases 3-9 validate and walk it, the formatter renders it, the LSP lists it, and `nlc check --json` reported `ok:true` on the failing probe. The gap was ONE scan function (`TopLevelPlainTestHeaderEndsAt`). Lowering beat `[Theory]` because per-case identity comes free and the emitter may not grow. | C# diff +2/−45 over two files, zero new C# files; estate 5,075→5,083 (+8); unit 3,193→3,186 (7 cases); 29 native projects all `ok:true`, `doc-query` 11/11; 30 `Assert.` in / 30 out; 4 mutations each failing exactly its own case |

**Durable findings (020).** The runner-capability verdicts and the estate-reach facts are in §3.7.

- The closing rule has two halves, re-measured every slice: (1) no C# compiler/tooling file remains a
  canonical assertion layer over N#-owned code, and (2) the required runner surface is N#-owned — "C# may
  only mechanically execute an N#-decided plan; N# must own result classification and stable output".
  Half (2) was discharged at 44, half (1) at 45 (slice 45).
- The bucket rule that decides (1): (a) canonical over an N#-owned SUBJECT; (b) retires with its C#-owned
  subject; (c) reaches an N#-owned type only as the harness's ROUTE; (d) names no N#-owned type. An
  N#-owned value used as an expected LABEL (an enum) is NOT a subject — that rule takes the crude
  "names an N#-owned type" reading of 214–224 down to 113–114 ("calls or `new`s one") and then to 30
  (slices 44, 45).
- The FINAL sharpening: an owned type's value must REACH an assertion (directly in an `Assert.` argument
  or through a local that carries it), and a local mutated in a scope inherits the owned types named in
  every enclosing scope HEADER. That asymmetry demotes `IlSdkToolchainTests.cs:126` to (c) while keeping
  `AstChildrenTests.cs:24`, whose subject reaches an assertion through a mutated set (slice 45).
- **The analyzer has TWO entry points and they are DIFFERENT ANSWERS.** `Analyze(unit)` has ZERO
  production callers (both live sites pass all four arguments), is handed no source text so it cannot
  MEASURE A TOKEN (all 23 anchor-length differences have `plain = 1`), never fills
  `ContextualHint`/`SourceSnippet`, and says `Variable 'x' is typed as 'string'…` with a suggestion where
  production says a bare `Type mismatch` and moves the content into `ActualType`/`ExpectedType`/
  `SourceSnippet`/`ContextualHint`. 73 of 82 deleted assertions in one slice drove an entry point nothing
  ships, and on 15 rows production's MESSAGE is the WORSE one. 40 of 282 claims are FALSE on the other
  route (slices 29, 30, 31, 32).
- The split is about the SENTENCE, never the VERDICT — where there is no diagnostic there is nothing to
  disagree about, which is the other half of the 40-false-claims finding (slices 32, 33, 34).
- **The same user-facing sentence often has MORE THAN ONE OWNER** and only measurement says which one a
  fixture reaches; contracts are now written so either owner moving is caught. `Method 'X' must be called
  or passed to a delegate` has two owners (`ErrorMessageBuilder.nl` on the production route,
  `AnalyzerReflectionCallReporter.nl` on the plain one) and NEITHER sentence was stated anywhere in the
  6,316-contract estate on either route (slices 31–36).
- **Absence claims are mostly vacuous unless controlled**: 34 of 35 in slice 30, 8 of 9 in slice 32 — the
  campaign's worst ratio. The answer is three instruments the C# had none of (the parse census, the pinned
  unit shape, an out-of-repo append sweep), after which slices 33–36 report zero non-movers across 327
  appended fixtures.
- The estate holds hand-written COPIES of production sentences that no code path feeds, so grepping
  contract text OVERSTATES what the estate pins (slice 30).
- `Compiler.dll` C# is INVISIBLE to the whole estate: one one-statement C# mutation moves 0 of 6,316 estate
  contracts and 72/299, 33/191 or 7/15 native ones — measured from both sides in five slices rather than
  asserted (slices 24–30).
- Classification rule, proved four separate times: classify a test by what its body NAMES, never by its
  method name or its position in the file. A name-based cut would have been wrong on seventeen of eighteen
  methods in `AnalyzerSemanticModelTests.cs` (slices 19, 21, 25–28).
- The split ladder, established one slice at a time: a file can be split across BOTH estates by subject
  (23); a file can have TWO subjects (24); a file with ONE subject too big for the ~700-line budget splits
  ACROSS SLICES by INSTRUMENT (26); and the SECOND half of a cross-slice split EXTENDS the project the
  first half created rather than adding a sibling (27).
- A cluster's risk lives in HOW IT BUILDS ITS INPUT, not in what its subject is about — this OVERTURNED
  slice 7's own warning that `Linter`/`Formatter` should be priced above their line counts:
  `LinterTests.cs` never constructs an AST, it is string-in / primitive-out (slice 8).
- Splitting successors BY SUBJECT (one contract file per production owner) is what makes coverage gaps
  visible — folding `DiagnosticCatalog` and `LinterBindingUsageCore` into `Linter.tests.nl` would have
  hidden that neither had ANY estate coverage anywhere (slice 8, recurring at 10 and 14).
- The deleted parser suite was almost entirely SILENT ABOUT POSITION: rows stating a `Line`, `Column`,
  `Span`, `NameLine` or `NameColumn` numbered 6, 7, **0** (over 998 lines and 260 assertions) and 7 across
  the four tranches — a parser that moved every member access, index, call, range, `new`, initializer and
  array literal one column right would have passed all 30 of slice 21's deleted tests. `Parse(source)`
  also DISCARDED `result.Errors`, so all 212 positive cases were structurally silent about clean parsing;
  the successors pin `PsCensus(source) == ""` first (slices 16–22).
- The `ParserTests.cs` campaign closed at slice 22: six tranches, 212 `[Fact]`s over 5,896 method lines
  into six estate contract files. With `ParserErrorTests.cs` the parser's whole C# assertion layer — 316
  xUnit cases, 8,044 lines — is N#.
- The `AnalyzerTests.cs` campaign closed at slice 36 and its three columns close exactly: the per-slice
  deletions sum to 13,451 lines, 816 methods and 565 `Assert.` — the file's whole opening census.
- Measured widening over byte-identical fixtures ran 5.5× to 47.5× (typically 9–14×), and the arc's
  headline pairs are 1,712 claim rows across the nine `AnalyzerTests.cs` slices and 95 blocks / 297 assert
  rows replacing 28 bodies / 95 rows in the finisher.
- A fact the deleted C# could not see is NOT automatically a fact nothing had recorded — sweep the sibling
  parity file first: slice 19's draft claimed seven new shape facts and five were already pinned by stage
  N+1c tranches 9c/10/11 (slice 19).
- Product findings pinned as measured rather than fixed (seven at slice 45 alone): a top-level `##` parses
  as a preprocessor declaration IN SILENCE and swallows every later diagnostic (`!! %%` = 4 errors,
  `## !! %%` = 0); `nlc tidy`'s JSON `ok` reports CLEANLINESS so exit 0 can carry `ok:false`; `nlc tidy
  --fix` deletes by BARE PREFIX and can take a used package with it; `nlc clean` deletes in LENGTH order,
  not depth order; `BatchQueryRunner.LoadRequests` distinguishes two exception types the shipped CLI does
  not; `nlc new`'s empty-output guard is structurally unreachable; only the `Program` arm of the `nlc new`
  text kernel branches on the template.
- Two shipped-product defects found by EXECUTING what the deleted tests only read:
  `docs/design/systems-samples/proofs/27-c-library-cli` aborts at exit 134 with `MarshalDirectiveException`
  because `[LibraryImport]` over a `ReadOnlySpan<byte>` is not marshalable on this emit path — invisible
  for the file's whole life because the C# read only METADATA; and 20 of 54 systems fixtures carry 22
  non-systems ERROR rows, two of which undermine their own method's claim (slices 40, 41).
- Structurally vacuous claims exist and only a control finds them: `nlc check --systems-report` CANNOT
  write to stderr at all (every `Console.Error` path in `CheckCommand.Execute` is gated on text mode), so a
  whole family of `Assert.True(IsNullOrWhiteSpace(stderr))` could not fail for its life; `nlc query perf`
  CAN, so that claim is KEPT (slices 40, 41, 42).
- The parser's `<error>` placeholder does not only leak into the MESSAGE — it SIZES THE UNDERLINE: ten of
  316 pinned rows are out of range and every one has `length == 7`; `NL903@1:65537+7` starts one column
  past the end of its own 65,536-character line (slices 37, 38).
- Three measured analyzer gaps were filed rather than papered over: the analyzer never reports an undefined
  TYPE NAME in a declaration position (five probes all silent; it surfaces only as an `NL202` naming the
  phantom type) — **WITHDRAWN, see §5: all five probes spelled `Missing`, which IS `System.Reflection.Missing`,
  so none of them tested the claim**; one undefined `out` argument is reported FOUR times over two positions;
  and the two sentence-builders disagree on plural agreement for `NL402` and on whether an over-defaulted call
  states its argument RANGE (slices 34, 35, 36).
- Two facts about the language the migration surfaced and pinned: `var x = 5` IS C# AND NOT N# (the parser
  reads `var` as an `IdentifierExpression` statement and `x = 5` as a separate assignment, so nearly every
  fixture has twice the statements its author intended), and a BODILESS positional record is a PARSE
  ERROR, so two deleted `AssertNoErrors` fixtures proved NOTHING (slices 25, 29).
- The `enum Status: decimal` refusal is the ONLY corpus diagnostic with a null `HumanExplanation`, and
  since `HumanExplanation` alone selects the renderer, it is the one parser diagnostic a developer meets in
  RUST style while every other one is Elm — a live user-visible inconsistency, now stated (slices 13, 16).
- The "top 25" diagnostic golden suite holds TWENTY-FOUR diagnostics (5 parser / 9 analyzer / 10 linter)
  and the shipped fixture's own first line has said `24 groups, 24 diagnostics` since check-in; PINNED, not
  corrected, because renaming means choosing a 25th diagnostic — a product-content decision (slice 14).
- The 50 deleted files each carry a `removed` ratchet row, so the deletion record is ENFORCED rather than
  narrated, and that is what keeps `epochPathFingerprint`/`epochFactFingerprint`/`epochFileCount`
  unchanged (slices 36–45).

### 4.4 Task 019 — the tooling burn-down (complete; `DocQuery.cs` deleted at `dc2c4ae20`; box CHECKED)

Outcome: the arc opened at `0d55966e8` over six C# files totalling 7,739 lines / 6,892 non-blank / 341
member extents summing 7,257, and closes at 520 / 442 / 55 / 382 across three — a −93.3% cut over 22
slices, every deleted line's behaviour re-owned in N# and proved by two-sided differential rather than by
inspection. FOUR of the seven listed files are DELETED WHOLE with zero insertions (`Linter.cs`,
`Formatter.cs`, `DocQuery.cs`, `NullabilityMetadata.cs`); THREE are reviewed non-growing hosts. ZERO
toolset repins across slices 1–12; the `System.Xml.Linq` catalog was the arc's one two-stage boundary
(`9b0dd2388`). Slice 21 committed at `e6aaf57cd`.

| slice id | commit(s) | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| 019 slice 22 stage 2 | `dc2c4ae20` (landed); target recorded at tip `9b0dd2388` | `DocQuery.cs` 443 → 0, DELETED (`git diff --numstat -- '*.cs'` = added=0 deleted=443) → `DocQuery.nl` 633 lines in BootstrapServices, same name/namespace/3 public signatures; `BatchQueryRunner.cs`, `QueryCommand.cs`, `tests/DocQueryTests.cs` byte-unchanged | The deletion arm is decided by measuring the untouched file first: whole-file closure `n=19 lines=390`, ESCAPES TO (0), ENTERED FROM (0), and every public-signature type already N# in the same namespace — no cycle to route around, so deletion not host | Arc 7,739 → 520 lines (−93.3%) over 22 slices; 4 of 7 files deleted; gate 109 steps 21m34s |
| 019 slice 22 stage 1 | `9b0dd2388` | No C# moved. Five `.nl` files publish the `System.Xml.Linq` catalog surface: `ColumnarExternalBindingPlans.nl` (7 type rows + 2 static + 4 instance call rows), `ColumnarRuntimeInstanceMemberResolver.nl` (6 property rows), `AnalyzerImports.nl`, `ExternalAssemblyScan.nl` (26→27), new `ColumnarXmlLinqCatalog.tests.nl` 393 lines | An IL member census over `DocQuery`'s own compiled bodies corrected the source-derived brief three times: a SEVENTH type (`XContainer`) no source line spells, `XName.op_Implicit` not `Get`, and real signature crossings. A source grep cannot see the compiler's overload choice | 146 insertions / 2 deletions; contracts 5,062 → 5,075 (+13); 15 oracle legs 0 diffs; gate 109 steps 35m23s |
| 019 slice 21 | `e6aaf57cd` | `CodeIntelligenceService.cs` 578 → 153 (−432, −74.7%), `CompletionEngine.cs` 109 → 96; dead carrier `ProjectSnapshot.SharedAnalyzer` deleted at 4 construction sites; `ProjectSnapshot` moved whole → `ProjectSnapshot.nl`, `CodeIntelligenceNavigation.nl`, `CodeIntelligenceQueries.nl` | `Dictionary<K,V>` does NOT widen to `IReadOnlyDictionary<K,V>` in any position while `List<T>` widens to `IReadOnlyList<T>` in all of them: a read-only dictionary can be RECEIVED by N# and never CREATED by it. That asymmetry keeps `ProjectSnapshot` out of reach of `.tests.nl` | LSP oracle 40,386 rows/side 0 diffs; partition POLICY=0 vs control 23 extents/430 lines; unit 3,192; gate PARTIAL (another session's feed) |
| 019 slice 20 | `e7c7864e4` | `Formatter.cs` 821 → 0, DELETED (821 deletions, ZERO insertions) → `Formatter.nl` 913 lines / 28 public members + 654-line contracts; `Program.cs`:699, `DocumentFormattingHandler.cs`:51, `PlaygroundCompiler.cs`:87 and `tests/FormatterTests.cs` byte-unchanged | An N#-emitted optional parameter IS optional to C# (emitter writes `ParameterAttributes.Optional\|HasDefault` + the constant) — that is what makes a whole-file deletion possible rather than a host. The converse still fails: an N# call site may not omit one | Differential 3,219 rows/side 0 diffs; non-vacuity control 2,507 differing rows; contracts +69 → 5,022; gate 108 steps 27m50s |
| 019 slice 19 | `b35754e6d` | `Formatter.cs` 2,134 → 821 (−1,313, −61.5%); the whole body walk (15 members / 1,302 lines, 83 type-dispatch arms + 12 `is`-patterns) → `FormatterWalk.nl` 1,790 lines + 848-line contracts; the 35 added C# lines are all `_walk.` calls, the field and the ctor line | State is BORROWED, not owned: a third build giving the walk its OWN `FormatterWalkState` compiles, type-checks and passes the structural section but reports 384 differing behavioural rows. A declaration formatter and a statement arm are one walk at two depths | Differential 3,811 rows, 1 declared divergence (`InvalidCastException` message); contracts 4,878 → 4,953; gate 108 steps 27m41s |
| 019 slice 18 | `2c260c435` | `Formatter.cs` 2,252 → 2,134 (net −118); `FormatTypeReference`, `FormatModifiers`/`ShouldPreserveExplicitCasingVisibility` and the `allow` family (6 members / 112 lines, 14 arms) → `FormatterSyntaxText.nl` 348 lines + 250-line contracts; the 44 added lines are 44 owner calls | The estate already contained both names in N# and NEITHER is the same function: routing into `TypeReferenceFacts.GetDisplayName` diverges on 6 of 33 shapes, and `CodeIntelligenceDisplayText.FormatModifiers` emits `pub`/`priv`. Same name, same argument, different question | Differential 3,737 rows/side 0 diffs; contracts 4,848 → 4,878 (+30); gate 108 steps 27m39s |
| 019 slice 17 | `2642cd173` | `Formatter.cs` 2,302 → 2,252 (net −50); all six instance fields and three state-only members → `FormatterWalkState.nl` 224 lines + `FormatterPositionSnapshot` + 374-line contracts; the 212 added C# lines are 194 `_state.` calls + 17 doc lines + 1 re-indent | The inherited field census was FALSE about the most-written field: `nl91-fields.py` cannot see `++`, so `_indent` (76 writes across 20 members) was called read-only. Following that brief would have built a carrier that unblocks nothing — every arm pushes and pops the depth | Differential 4,725 rows/side 0 diffs; non-vacuity control 14 differing rows; contracts 4,819 → 4,848; gate 108 steps 27m41s |
| 019 slice 16 | `007ce12bc` | `CodeIntelligenceService.cs` 889 → 578 (−311; `git diff` +14/−325); the 13 type-info resolvers (305 lines, 76 type-dispatch arms + 5 `is`-patterns) → `CodeIntelligenceTypeResolution.nl` 805 lines + 560-line contracts, 15 public statics for 13 C# members | The C# was hiding a nine-arm duplication in plain sight: `TryGetTypeInfoFromDeclaration` and `FindNamedTypeInfo` spelled the same nine type arms twice, differing only in three VALUE arms. A mechanical port is the moment to ask whether the two things being ported are one thing | Differential 713 rows/side 0 diffs; LSP oracle 40,387 lines 0 diffs; contracts 4,796 → 4,819; gate 108 steps 27m13s |
| 019 slice 15 stage 2 | `27a5df665` | `CodeIntelligenceService.cs` 1,010 → 889 (−121; +16/−137); `GetSourceText`, `ToDiagnosticResult(CompilerError,…)` and the 3 reference-result builders → `CodeIntelligenceReferenceResults.nl` 69 lines + `CodeIntelligenceSourceDoor.nl` widened (11 → 12 members); stage 1's deliberate concrete-dictionary twin `CodeIntelligenceDiagnostics.SourceTextIn` DELETED | The analyser and the emitter are two catalogs: stage 1 proved the emitter row by execution and the very first stage-2 probe still failed because `AnalyzerAssignabilityFacts` had no `IReadOnlyList <- List` twin for dictionaries. A type that emits perfectly can still be unassignable | Differential 3,163 rows/side 0 diffs; contracts 4,788 → 4,796; 4 materialisations deleted from the LSP publish path; gate 108 steps 27m15s |
| 019 slice 15 stage 1 | `27a5df665` (target recorded at `19c78c7d2`) | `CodeIntelligenceService.cs` 1,166 → 1,010 (−156); implementors territory + diagnostics family (8 members / 191 extent lines) → `CodeIntelligenceImplementors.nl` 90 + `CodeIntelligenceDiagnostics.nl` 181 + 542 contract lines. PLUS the `IReadOnlyDictionary<K,V>` catalog surface published across `ColumnarIlEmitter.cs` (+51) and four `.nl` owners | A catalog row is FIVE rows until the sweep says otherwise (slice 48's `char.IsLower` sweep found one owner; this one found one C# and four N#), and the `.nl` halves cannot spell `typeof(IReadOnlyDictionary<…>)` because the pinned toolset compiles them — `Type.GetType` by name is the only route | Differential 203 rows/side 0 diffs; contracts 4,768 → 4,788; emitter 21,471 → 21,522 (epoch ceiling 21,723 intact); gate 108 steps 26m34s |
| 019 slice 14 | `19c78c7d2` | `CodeIntelligenceService.cs` 1,618 → 1,166 (−452; `git diff` +8/−460); declaration projectors + call-site collector + `GetCallGraph`'s 74-line body (7 members / 381 lines) → `CodeIntelligenceDeclarationProjection.nl` 342 + `CodeIntelligenceCallGraph.nl` 306 + 869 contract lines; `GetCallGraph` survives as a 12-line driver | `query call-graph --name X` is silently unparsed (the selector is `--function`) and answers the UNFILTERED graph — slice 13's oracle used it, so the function arm, the callers list and the truncation arithmetic had never been compared at all. Check that what answered is what you ASKED | Differential 145 rows/side 0 diffs; LSP oracle 40,386 lines 0 diffs; contracts 4,727 → 4,768; gate 108 steps 30m29s |
| 019 slice 13 | `04bc0d021` | `CodeIntelligenceService.cs` 1,897 → 1,618 (−279; +229/−388); 20 of the 21-member display/position family → `CodeIntelligenceSourceDoor.nl` 209 + `CodeIntelligenceDisplayText.nl` 400 + 450 contract lines; `LintCommand.cs` 202 → 199 as its pass-through dissolved; `GetSourceText` stayed, walled | The catalog wall is an INTERFACE, not a shape: `IReadOnlyDictionary<string,string>` declines as a static parameter at `emit.declaration.method-param` while `Dictionary<string,string>` resolves. One more probe turned "dictionaries don't cross" into a routed-around wall with no repin | Differential 519 rows/side 0 diffs; live-tree check 285 → 272, BELOW the inherited baseline; contracts 4,682 → 4,727; gate 108 steps 33m40s |
| 019 slice 12 | `10da4c520` | `src/NSharpLang.Compiler/Linter.cs` DELETED WHOLE — 197/177, all 14 extents/165 (`LintVisitor` declaration walk + the public `Linter`) → N# `Linter.nl` (282) + `Linter.tests.nl` (467) in `NSharpLang.Compiler.BootstrapServices`, same namespace `NSharpLang.Compiler`; 6 production consumers and 17 C# test call sites bind with ZERO source change | Closure has a second half: a FILE can be deleted rather than reduced to a host when every type in its public signature is already N#-owned (87.1). N# emits optional params as `opt=True hasdef=True def=null`, which is why 23 call sites did not move (87.2) | `Linter.cs` 984→0 over 3 slices; arc surface 5,025/4,491/206/4,707, −35.1%; contracts 4,682; gate 27m01s, 108 steps |
| 019 slice 11 | `2d89e4b7e` | `Linter.cs`'s whole walker SCC — `VisitFunction` 59, `VisitStatement` 209, `VisitExpression` 34, `VisitExpressionInternal` 70, `VisitChildExpressions` 7 (379) + the 3 recursion-guard fields → N# `LinterWalk.nl` (576) / `LinterWalk.tests.nl` (725); `LintVisitor` keeps declarations only | The inherited 111-line brief was OVERTURNED by executable closure: `{VisitExpression,…}` escapes to `VisitStatement`, so the smallest closed cut is the 379-line SCC. A callback a C# extraction introduced is not a language boundary (86.7) | 584→197 (−66.3%), extents 21→14/165; 963 behavioural rows byte-identical md5 `2f4ad5cb85e4…`; contracts 4,649 |
| 019 slice 10 | `3e2bec5a3` | 19 of 22 `LintVisitor` fields, 19 extents deleted whole (249 lines) and the moved halves of 3 more → N# `LinterWalkState.nl` (569) / tests (703); the reporting spine (`AddDiagnostic`, `Report`, `SourceLine`, `FindTokenColumn`, suppression) is now internal — C# can no longer add a diagnostic | The field inventory was taken by execution (`nl85-fields.py`), making carrier-vs-arm a measured partition: the 3 guard fields touched by `VisitExpression` ALONE stay with that arm. The three save/restore idioms disagree on the exception path and are reproduced exactly | 984→584, extents 58→21 summing 910→545; slice adds NO C# but one field line; contracts 4,596; unit suite unmoved 3,192 |
| 019 slice 9 | `da2688e4d` | 6 `Linter.cs` extents (229) + LSP `SignatureHelpHandler.IsValidIdentifier` (25) and `CompletionHandler.IsIdentifierPart` (4) = 258/8 extents → new `IdentifierText.nl`, `LinterInterpolationScan.nl`, `LinterNullCheckPolicy.nl`, `LinterShadowedVariable.nl`, plus `LinterTypeReferenceName` into `LinterMissingImport.nl` | The estate carried EIGHT production identifier-text predicates, not the brief's five — found by sweeping, not by trusting the list. The ninth (`DiagnosticGoldenTests.IsIdentifierPart`) is deliberately LEFT: an independent oracle must stay independent | `Linter.cs` 1,178→984; SignatureHelpHandler 548→522; CompletionHandler 705→700; 2,176 rows, 17 declared diffs; contracts 4,546 |
| 019 slice 8 | `f991104a0` | `ContainsParserErrorPlaceholder` 55, `IsValidIdentifier` 18, `GetBaseTypeName` 13 deleted whole; `CheckMissingImport` 55→14 and `CheckMissingImportForType` 53→18 → `LinterMissingImport.nl` (241) carrying both NL002 tables + `LinterTypeReferenceName.Base`; neither NL002 arm survived as a table | Two of the three predicates needed NO new owner and the verdict came by execution: `AnalyzerDeclarationPolicy.IsValidIdentifier` is an EXACT twin (65/65); `AnalyzerParserErrorPlaceholders.ContainsInExpression` is a STRICT SUPERSET with 9 named divergences, reachability ZERO on real sources | 1,340→1,178 (−12.1%); differential 2,836 rows md5 `491b5098838c…`; 8 spurious NL001 squiggles disappear in the LSP; contracts 4,473 |
| 019 slice 7 | `c3f9c14f3` | The two known-namespace tables — `_knownNamespaceTypes`/`BuildKnownNamespaceTypes` 145, `_knownNamespaceMembers`/`BuildKnownNamespaceMembers` 89 (238) — and `CheckUnusedImports`'s namespace arm → `LinterNamespaceImportUsage.nl` (148), the twin of the already-N# file arm; NL010 now has no C# policy left | The `HashSet` became per-namespace ARRAY funcs on purpose: membership is the only question ever asked, and rebuilding two dictionaries per lint is work the shape does not need. "Absent from the table" and "empty row" encode the same state — sound only because no row is empty, which is asserted | 1,611→1,340 (−16.8%), extents 65→61/1,267; 7,726 rows md5 `15bf90842747…`; tables 112 types over 10 namespaces + 66 LINQ members |
| 019 reconciliation (inside slice 7) | `c3f9c14f3` / `f8f512918` | No ownership move. The tip moved mid-slice because a concurrent session landed THIS slice's own filed chip, `f8f512918` "Fix pre-existing NL010/NL202 errors in `CompletionReceiverFacts.nl`" (one `.nl` file, no manifest row) | A tip that moves mid-slice is run down, not re-run: the base worktree was rebased onto `f8f512918`, its CLI and base grid side rebuilt, and EVERY tip-sensitive proof re-run. The 9 frozen-snapshot oracles are unaffected by construction | live-tree oracle `eb900a30… count=288` → `cdcdb677… count=285`; IL transcript 1,573/`eb430931…` → 1,557/`1ff6a379…` |
| 019 slice 6 | `f10eb1274` | 23 `DocQuery.cs` extents + 6 fields (270 lines) → `DocQueryReflectionFacts.nl` (252) and `DocQueryTypeIndex.nl` (246); THREE pure relays simply END (call sites now name `DocQueryKernels` directly); both reflection-door tests in `tests/DocQueryTests.cs` migrate as native contracts | `DocQuery.cs` is NOT a zero-policy host and every surviving line is behind a MEASURED wall: `nl81-wallreach.py` reports WALLED 9/142, DOWNSTREAM 12/258, FIELD 2/2, UNEXPLAINED 0. `System.Xml.Linq` is a total wall at the DECLARATION boundary, so no traversal half exists to move | 740→446 (−39.7%), extents 51→23/402; unit suite 3,194→3,192 (exactly the 2 migrated tests); 2,638 rows md5 `f77c825fb0dd…` |
| 019 slice 5 | `5d4a204bc` | `AstToJson` 21, `AstValueToJson` 55, `JsonOptions` 8, `NormalizePath` 1, `SchemaVersion` 1 (86) die whole → `OutputFormatterAstJsonKernels.nl` (170); the anonymous C# tuple becomes the N#-owned `AstJsonUnit`; `QueryCommand.cs` 1,085→1,084 (moved OFF its epoch ceiling) | `OutputFormatter.cs` CLOSES as a reviewed zero-policy host — partition `UNCLASSIFIED=0, POLICY=0`, non-vacuous because the same rule on the pre-cut file reports `POLICY=2`. Deleting it whole is a 163-site façade rename, not an ownership question | 378→271 (−28.3%), extents 43→38/206; MetadataToken sort reorders 477,032 of 716,042 rows (66.6%), `tokenTies=0`; 217 rows md5 `c965494 97a7c…` |
| 019 slice 4 | `be95ec85e` | 17 extents over SIX families (position 28, receiver text 39, declared-member resolution 68, identifier answer 80, member-access answer 71, typed-receiver answer 45) → `CompletionReceiverFacts.nl` (NEW 352) + `CompletionDeclarationFacts.nl` +139 + `CompletionEngineKernels.nl` +145; `AstNodeFinder.cs` unchanged — its single member is already an N# relay | `CompletionEngine.cs` CLOSES as a reviewed zero-policy host; delete-whole is blocked by ONE measured fact — `ProjectSnapshot` is declared at `CodeIntelligenceService.cs` :1851, a C# type `BootstrapServices` cannot reference, and 7 production + 23 test sites pass one | 458→109 (−76.2%, 86.5% below the 805 epoch), extents 21→4/81; 1,352 rows md5 `3a92896788 72…`; keywords 43=43, modifiers 12=12, primitives 16=16 |
| 019 slice 3 | `294035b7c` | Dead pair `ResolveTypeReferenceToTypeInfo` 16 + `FlattenUnionTypeReference` 15 DELETED with no N# work; receiver classification (`GetMemberFilter` 6, `IsStaticTypeReceiver` 11, `ResolveLiteralReceiverType` 6, `IsStringLiteralReceiver` 8 = 31) → existing `CompletionReflectionFacts.nl` (370→418) | The "dead" pair was a STALE WEAKER FORK of the live `CodeIntelligenceService` pair — 5 of 24 `TypeReference` shapes DIVERGE, so deleting it removed a trap rather than a copy. `OutputFormatter`'s perf-report→JSON family is RETIRED: 57 scored lines that are already N# relays | 526→458 (−12.9%), extents 27→21/414; dead sweep DEAD 1→0 over 1,033 files, DETACHED 53; 1,404 cells md5 `a0284e26e86a…` |
| 019 slice 2 | `228081146` | `TryGetCompletionReflectionType` 66, `GetReflectionTypeArgumentOrObject` 25, `BuildReflectionMemberItems` 55 (146) + the driver's 4-line `BindingFlags` ternary + `private enum MemberFilter` → `CompletionReflectionFacts.nl` (NEW, 371) with the enum as N# `CompletionMemberFilter` | The move found three LIVE crashes the C# carried: `Nullable<string>` throws ArgumentException, a live definition closed over an MLC argument answers a `TypeBuilderInstantiation` whose `GetMethods` throws, and a null `Type` NREs. All become declines via the estate's existing `IsPoisonedMixedInstantiation` | 678→526 (−22.4%), extents 30→27/476; 1,193 cells, 1,176 byte-identical, 17 declared divergences, 0 work-side faults; contracts 4,328 |
| 019 slice 1 | `0d55966e8` | 10 extents / 117 lines ("what a completion item says") + the cascade `CodeIntelligenceService.FormatTypeReferencePublic` → `CompletionDeclarationFacts.nl` +102, `CompletionTypeTextFacts.nl` (NEW 154), `AnalyzerCallableReferenceFacts.nl` +3; two CALLER-LESS duplicates deleted with no N# work | The inherited brief undercounted surviving duplicates by three. `FormatClrType` is NOT a duplicate of `FormatClrTypeName` (FullName over 8 types vs simple-name aliasing) — folding them would be a silent behaviour change, so it moves verbatim and the difference is pinned by contract | CompletionEngine 805→678 (−15.8%); CIS 1,903→1,897; arc opens at 6 files, 7,739/6,892/341/7,257; 2,678 cells md5 `af01e4393f74…` |

Short notes on the same three slices, recorded in the 020 region:

| slice id | commit(s) | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| 019 slice 22 stage 2 (short note) | `dc2c4ae20` (landed) | `DocQuery.cs` DELETED — the whole file, 19 members and 390 extent lines, into one 633-line N# owner that keeps the name, the namespace and every public signature | The three consumers never learned it moved. Four language walls met in the move and ALL FOUR routed without a catalog row. | 19 members / 390 extent lines → one 633-line N# owner |
| 019 slice 22 stage 1 (short note) | `9b0dd2388` (landed) | The `System.Xml.Linq` catalog surface published for ZERO lines of C#: 14 members and 9 type shapes across THREE halves — the analyser's namespace table, the emitter's plan/type catalog, and the emitter's own assembly scan, in `.nl` only | The surface was enumerated from `DocQuery`'s COMPILED bodies by an IL census rather than from the namespace — the namespace would have over-published. | 14 members / 9 type shapes / 13 executable contracts, plus a probe that emits and runs |
| 019 slice 21 (short note) | `e6aaf57cd` (landed) | The dead carrier `ProjectSnapshot` plus the whole query and navigation surface: 25 C# members and 432 lines into three N# owners | A name-based census could NOT see the dead property, because `MultiFileCompiler` declares a `SharedAnalyzer` too and the two members share one name — it took a RECEIVER-TYPED IL census over 170,633 method bodies in 62 freshly-built assemblies to tell them apart. | 25 members / 432 lines → 3 N# owners; 170,633 method bodies / 62 assemblies censused |

**Durable findings (019).** The deletion-vs-host criterion and the estate's position in the dependency
graph are in §3.6.

- The closure question has TWO halves and only the second decides deletion-vs-host: escape analysis says
  whether a SET of members can move; whether a FILE can be DELETED is the separate, equally mechanical
  question "is every type in its public signature already N#-owned?" (slice 12, finding 87.1).
- A brief's line count is a hypothesis until the closure is run: the inherited 111-line expression
  sub-territory measured at 379 (the whole SCC), and the same tool overturned the brief's other
  instruction in the same run (slice 11).
- A callback a C# extraction introduced is not a language boundary: `VisitWithTypeMemberScope`'s `Action`
  was marked immovable in slice 10 and dissolved in slice 12 — once its three callers are N# each writes
  its own `try/finally`, and the dissolution costs exactly three copies (slices 11, 12).
- State is BORROWED, not owned: `Formatter` constructs the one `FormatterWalkState` and hands it to
  `FormatterWalk`, because a declaration formatter and a statement arm are ONE walk at two depths. The
  third build that gave the walk its OWN state compiles, type-checks and reports 384 differing behavioural
  rows (slices 19, 20).
- **Same name, same argument, different question.** The estate already contained
  `TypeReferenceFacts.GetDisplayName` and `CodeIntelligenceDisplayText.FormatModifiers`, and neither is the
  formatter's function: routing into the first diverges on 6 of 33 shapes and the second emits `pub`/`priv`.
  "Consolidating" would have changed what `nlc format` emits for every function type (slice 18).
- A same-named twin in the estate may be WEAKER, and only reading both bodies tells them apart: slice 3
  found a stale weaker FORK (5 of 24 `TypeReference` shapes diverge — deleting it removed a TRAP, not a
  copy), slice 4 a live weaker NAMESAKE, slice 8 an EXACT twin (65/65) and a STRICT SUPERSET with 9 named
  divergences and reachability ZERO on real sources.
- The C# was hiding a nine-arm duplication in plain sight: `TryGetTypeInfoFromDeclaration` and
  `FindNamedTypeInfo` spelled the same nine type arms twice, differing only in three VALUE arms — a
  mechanical port is the moment to ask whether the two things being ported are one thing (slice 16).
- The inherited field census was FALSE about the most-written field: the instrument cannot see `++`, so
  `_indent` (76 writes across 20 members) was called read-only, and following that brief would have built a
  carrier that unblocks nothing (slice 17).
- **A catalog row is FIVE rows until the sweep says otherwise** (one C# owner and four N#), the analyser
  and the emitter are two separate catalogs, and the emitter's own external assembly SCAN is a THIRD —
  publishing one publishes neither of the others, and the missing scan row makes the decline SILENT
  (slices 15-1, 15-2, 22-1; findings 90.4, 90.8, 98.1).
- An IL member census over compiled bodies is required where a source grep will lie: it corrected the
  `System.Xml.Linq` brief three times, and a receiver-typed IL census over 170,633 bodies in 62 assemblies
  is what told two same-named `SharedAnalyzer` members apart (slices 21, 22-1).
- A 0-diff live oracle can be 0-diff because its CORPUS cannot ask the question: the standing LSP corpus
  parses clean by design and answered `diagnostics` twice while slice 15 moved the whole diagnostics
  family. The fix — a deliberately-WRONG second corpus — is now a standing artefact (finding 90.1).
- `query call-graph --name X` is silently unparsed (the selector is `--function`) and answers the
  UNFILTERED graph, so slice 13's oracle had never compared the function arm, the callers list or the
  truncation arithmetic. Check that what answered is what you ASKED (slice 14).
- POLICY = 0 by executable partition is the terminal-host criterion, always with a non-vacuity control on
  the pre-cut file; a second instrument (`nl99-policycensus.py`, counting LOOP/PROJECTION/SWITCH/BUILD
  marks over blanked text) exists specifically so the first can be falsified (slices 4, 5, 22-2).
- Every slice ships a THIRD BUILD embodying the mistake it could have made — own-state formatter walk 384
  differing rows, own-state formatter 2,507, dropped blank-line guard 14, routing into `TypeReferenceFacts`
  13, disabled `TargetInvocationException` unwrap 36. A 0-diff result is a measurement only when the
  control says the harness can see (slices 15-1, 17–20).
- `DocQuery.cs` closed as a WALLED host, not a closed one, with the wall recorded by rule
  (`WALLED 9/142, DOWNSTREAM 12/258, FIELD 2/2, UNEXPLAINED 0`) — and the wall was then lifted by the
  catalog slice, which is what made the whole-file deletion available (slices 6, 22).
- `DocQuery`'s whole-file closure was MEASURED before the first edit and it said DELETE: `SET n=19
  lines=390`, ESCAPES TO (0), ENTERED FROM (0), zero multi-member SCCs, every public-signature type already
  N# in the same namespace (slice 22-2).
- The way past a catalog wall is to MOVE THE BOUNDARY, not to probe the type: slice 14 designed out a
  PARAMETER (making the call-graph accumulator N#-internal) and slice 15 designed out a CALL (letting the
  N# owner carry its own door over the concrete dictionary the caller had already materialised).
- The linter walkers were a multi-slice arc refused as a sub-slice three times; the order actually taken is
  carrier (10) → walker SCC (11) → declarations + entry + file deletion (12), and every arm mutated
  `LintVisitor`'s privates in place so moving one without the carrier needs a callback the mandate forbids
  (slices 7–12).
- Things that were prose, a coincidence, dead or measurably vacuous were turned into CONTRACTS rather than
  tidied away: `AddDiagnostic`'s undecidable span fork, NL004's `var needsAwait = true; if (needsAwait)`,
  NL020's dead first disjunct, NL016's unobservable partition, the linter's guard being a STACK not a
  visited-set, and `Visit`'s globally vacuous unused-variable check (slices 9–12).
- The `HashSet` became per-namespace ARRAY funcs on purpose: membership is the only question ever asked,
  and "absent from the table" and "empty row" encode the same state — sound only because no row is empty,
  which is asserted (slice 7).
- `.Cast<T>()` has no N# spelling and the faithful replacement is `as` plus a THROW on null — an `as` plus
  a null-SKIP would silently drop a subtree and produce false NL001/NL010 (slice 11).
- **What the arc left open**: the `Dictionary<K,V> → IReadOnlyDictionary<K,V>` widening (020's first
  blocker, root-caused and closed in 020/10-1); four measured repin candidates nobody took (`typeof` over a
  static-class operand, a second typed `catch`, `.Value` shadowing on a nullable-annotated receiver,
  `Dictionary.Keys` as a walked sequence); two pre-existing formatter defects filed and NOT fixed inside an
  ownership slice (no file containing a `switch`, and no file containing an INDEXER, can be formatted); and
  a second `System.Xml.Linq` consumer out of scope, `src/NSharpLang.Cli/CompilationReferenceResolver.cs`.

### 4.5 Task 018 — the systems-analyzer policy burn-down (closed at `554174624`; box CHECKED)

Outcome: `Performance/SystemsAnalyzer.cs` 2,390 → 1,160 lines (−51.5%) over eight slices, from epoch
`dae23a74d` to `554174624`, with twenty systems N# owners / 3,581 lines and contracts 3,890 → 4,296. The
task closed on its criterion's SECOND arm — a reviewed zero-policy mechanical host with
`grep -c NSYS = 0`, `UNCLASSIFIED = 0` and `MISMATCHED = 0` — because deletion was never available.

| slice | commit | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| 018 slice 8 (F18 + zero-policy host review; closes task 018's checkbox) | `554174624` (baseline `a9373c0b4`) | `SystemsAnalyzer.cs` 1,241→1,160 (non-blank 1,139→1,065; 104→100 extents; +47/−128). All 26 NSYS arms in `AnalyzeFunction`/`WalkStatement`/`WalkExpression`/`WalkCall` moved out; `AddHotFinding` + `AddFindingForPolicy` lost every caller and died; `WalkContext._allowStack`/`PushAllows`/`PopAllows`/`IsAllowed`/`ContainsEffect` → new N# `SystemsAllowStack` in `SystemsAttributePolicy.nl`. +470 N# lines on five owners: new `SystemsConstructPolicy.nl` (124, 13 arms), `SystemsAttributePolicy.nl` +178 (5), `SystemsGuardPolicy.nl` +75 (new `class SystemsTrapPolicy`, 3), `SystemsCalleePolicy.nl` +54 (4), `SystemsHotSummaryPolicy.nl` +39 (1) | Deletion of the C# host was never available — the `MultiFileCompiler` seam consumes `Analyze` and no N# type can host a walk that re-enters the analyzer's own semantic models — so 018 closed on its SECOND arm, a reviewed zero-policy mechanical host: `UNCLASSIFIED = 0`, `NSYS = 0`, `MISMATCHED = 0`. The completion assertion is a ZERO, not a line count | estate 2,390→1,160 (−51.5%, 8 slices); contracts 4,239→4,296; 20 N# owners / 3,581 lines; gate 16 steps 20m54s |
| 018 slice 7 (F4 + F12 + last of F1) | `a9373c0b4` (baseline `0f82c8fa8`) | 26 C# extents die whole, 313 extent lines, nothing becomes a relay: F4's eleven (`ValidateFunctionLevelAllows` 39, `AttributeString` 6, `Unquote` 2, plus the nested `AttributeSet` type entire = 95), F12's two (`ApplyBufferMemoryCopyFacts` 19, `ApplyHotSummary` 85), F1's thirteen guard members (114). `SystemsAnalyzer.cs` 1,590→1,241 (+39/−388). Three new N# owners: `SystemsAttributePolicy.nl` (260), `SystemsHotSummaryPolicy.nl` (162), `SystemsGuardPolicy.nl` (402) | `AttributeSet` is the first NESTED TYPE in the file to move whole (2 type-touchers, own closure 11 members / 57 lines, zero out-edges, all element types already N#). The seventeen-family inventory was INCOMPLETE: it scored MEMBERS, so it never named the 26 reporting ARMS living inside four walk members — F18 | largest cut of the arc: −349 lines, −22.0%, 48.1% below epoch; contracts 4,151→4,239 (+88 contracts, 1,223 lines); 82,557 differential cells, 0 mismatches |
| 018 slice 6 (F11 + F13) | `0f82c8fa8` (baseline `037482e45`) | `CheckIgnoredResult` (22), `ReportCalleePolicyViolations` (26), `AddUnknownExternalCall` (51) die whole = 99 lines; 5 call sites become 5 direct routes. `SystemsAnalyzer.cs` 1,674→1,590 (+27/−111). One new owner `SystemsCalleePolicy.nl` (201 lines, ctor + 7 members) with the `unknownExternalCalls` setting read once in its own `BeginAnalysis` | `MergeDeclaredCalleeSummaries` looks like a 15-line member but its transitive closure is 118 members / 1,402 lines — THE WHOLE FILE — through `AnalyzeFunction` re-entrancy. It is a DRIVER, not a rule: leave it, take its policy, let it become a zero-policy loop. F13 splits on that number | −84 (−5.0%, 33.5% since epoch); contracts 4,116→4,151, green first run; 4,320 differential cells 0 mismatches; gate 20m31s |
| 018 slice 5 (F15 + F14) | `037482e45` (baseline `d185399e9`) | `CheckRefLikeFields` (22), `CheckFunctionSurface` (60), `CheckPoolBalance` (19), `CheckResourceBalance` (19) die whole = 120 lines; 5 call sites routed. `SystemsAnalyzer.cs` 1,794→1,674 (+9/−129). Two new owners: `SystemsSurfacePolicy.nl` (152) and `SystemsBalancePolicy.nl` (97). Only C# added: 2 fields + 2 ctor assignments | The brief's MEMBERSHIP was overturned: `CheckIgnoredResult`'s closure is 28 members / 259 lines because it calls `TryResolveDeclaredCallee` and drags in all of F9 — its subject is a RESOLVED CALLEE, so it belongs to F13, not F15. `CheckRefLikeFields` (closure 6 members / 27 lines, tightest in the file) took its place; the line total stayed 120 | −120 (−6.7%, 29.9% since epoch); contracts 4,072→4,116; 1,760 cells 0 mismatches; 28 fixtures, 69 findings / 7 codes |
| 018 slice 4 (F8, the finding sink) | `d185399e9` (baseline `3e5497e5e`) | `AddTypeFinding` (27) and the DEAD 7-parameter `AddFinding` (9) die whole; the family 119→44 over 7→5 extents; `IsAuditMode` and the `_findings` field die; `IsSystemsProfile`/`EffectiveMode` become one-line routes. New owner `SystemsFindingSink.nl` (305 lines, 24 members) holds the findings list, both severity downgrades, both policy labels, both call-path compositions, the counts, the AOT verdict and the order. `SystemsAnalyzer.cs` 1,873→1,794 | THERE IS NO DEDUPE and there never was — the brief asserted `AddFinding` "also DEDUPLICATES"; both producers `Add` unconditionally. What is observable is the STABLE sort (file OrdinalIgnoreCase, line, column) and two call-path compositions. `AnalyzeFunction` is re-entrant, so the subject cannot be sink state; it must travel with each report | −79 (−4.2%, 24.9% since epoch); contracts 4,028→4,072; `new SystemsFinding(` gone from C# repo-wide; 1,256 cells 0 mismatches |
| 018 slice 3 (F6 + F7 + last of F17) | `3e5497e5e` (baseline `d841cd802`) | 17 C# members die whole, 159 extent lines: the brief's 15 (141 lines, `GetCallTarget` 7, `ExpressionKey` 7, `IsResourceCreationExpression` 22, `MarkResourceDisposedIfRecognized` 30, `MarkPoolReturnIfRecognized` 14, `IsReflectionOrDynamicCall` 15 and nine others) plus the two the terminality grep found — `IsDictionaryTryGetValueCall` (11) and `RegisterMemberType` (7) — and their `_memberTypeNames` field. New owners `SystemsCallPolicy.nl` (404, 36 members) and `SystemsExpressionNames.nl` (92). `SystemsAnalyzer.cs` 2,048→1,873 | `IsResourceCreationExpression`'s two tables are keyed DIFFERENTLY and that is a rule, not a tidy-up: `new T` keys on `SimpleName(ErasedName(T))` (so `System.IO.FileStream` matches) while `f(...)` keys on the FULL dotted target (so a user's `MyApp.File.Open` does NOT). Contract-pinned in both directions. F17 disappears; F1 becomes out-edge-free | −175 (−8.5%, 21.6% since epoch); contracts 3,984→4,028; 2,788 cells 0 mismatches; 26 call sites routed into N# |
| 018 slice 2 (F2 + F3 + F10, joined) | `d841cd802` (baseline `56174a687`) | 10 members die whole (169 lines) incl. `IsSystemsHostileSurface` 78, `EstimateSimpleTypeSize` 17, `ContainsRefLikeType` 15; `RecordAllocation` 53→15 (a zero-policy relay); `_structTypes`/`_refStructTypes`/`_enumTypes` → one `_typePolicy`. New owners `SystemsTypePolicy.nl` (500, 21 members) and `SystemsAllocationPolicy.nl` (69). `SystemsAnalyzer.cs` 2,261→2,048 | The `IsResultType` identity guard in the 128-byte Result-ABI rule is LOAD-BEARING: any generic of arity two sizes as 16 + both payloads, so `Unknown<Result<Vec,Vec>, Result<Vec,Vec>>` reaches the same 176 bytes and must stay silent. Taking F2/F3/F10 together retires all three registration sets; separately none could be terminal | −213 (−9.4%, 14.3% since epoch); contracts 3,940→3,984; 17,157 cells 0 mismatches; brief's "305 lines" measured to be 222 |
| 018 slice 1 (F5 stackalloc; the burn-down opens at epoch) | `56174a687` (baseline `dae23a74d`) | 8 members die, 120 extent lines (`IsStackallocLengthWithinBudget` 34, `TryGetStackallocElementCount` 22, `TryGetUnsignedIntegerMagnitude` 12, `UnwrapStackallocLengthExpression` 22, `IsStackallocIntLikeCast` 5, `ResolveTypeAliasName` 11, `TypeReferenceName` 9, `SimpleName` 5) plus the `_typeAliases` field and the inline escape branch. New owners `SystemsStackallocPolicy.nl` (254, 13 members) and `SystemsTypeNames.nl` (77). `SystemsAnalyzer.cs` leaves epoch 2,390→2,261 | The STATE-EXCLUSIVITY CENSUS chooses the family, not the line count: `_typeAliases` (3 touchers) was the one analyzer-scoped collection a policy family could take, `_structTypes`/`_enumTypes` blocked F2/F3/F10 on each other, and `AddFinding`'s 24 callers blocked every reporting family. `TypeReferenceName` is NOT `TypeReferenceFacts.GetDisplayName` — erased vs `Name<args>` — and folding them would have silently stopped matching every systems table | −129 (−5.4%) in one slice; contracts 3,890→3,940; 54,526 cells 0 mismatches; 17-family closure inventory recorded; gate 19m53s |

**Durable findings (018).** The re-entrancy, sink and allow-set facts are in §3.6.

- The seventeen-family inventory was INCOMPLETE and the measurement said so with a 26-arm number: it scored
  MEMBERS, so the 26 reporting arms over 11 NSYS codes living INSIDE `AnalyzeFunction` (4),
  `WalkStatement` (8), `WalkExpression` (10) and `WalkCall` (4) were never named. Called F18, "the walk's
  own arms" — found at slice 7, moved at slice 8. An arm is not a member, so a closure harness cannot
  score it.
- The STATE-EXCLUSIVITY CENSUS, not the line count, chooses the opening family: a collection moves with a
  family iff that family is its only toucher besides `Analyze`'s reset. That made F5 the only terminal
  opening — `_typeAliases` had 3 touchers, `_structTypes`/`_enumTypes` blocked F2/F3/F10 on each other, and
  `AddFinding`'s 24 callers blocked every reporting family (slice 1).
- Shared members MOVE AND ARE PUBLISHED rather than being reimplemented privately: `SimpleName` and
  `TypeReferenceName` moved in slice 1 specifically to unblock four families instead of one.
- The "duplicate that isn't one" recurs in every slice and must be MEASURED: `TypeReferenceName` vs
  `TypeReferenceFacts.GetDisplayName` (erased vs `Name<args>` — folding them would silently stop matching
  every systems table), `GetCallTarget` vs `AnalyzerSyntheticCallFacts.GetCallTargetName` (full dotted vs
  last segment), `ExpressionKey` vs `TryGetStableNullPath`, and the two `AttributeNameEquals`. Each is
  pinned by a contract asserting the two DISAGREE (slices 1, 3, 7).
- `Modifiers.Public || IsExportedIdentifier(name)` is WIDER than the two-argument
  `IsExportedIdentifier(name, modifiers)`, which answers FALSE for an upper-case name carrying `private` —
  folding them would silently stop reporting the missing owner on `private func Foo` (slice 7).
- `IsResourceCreationExpression`'s two tables are keyed DIFFERENTLY and that is a rule, not a tidy-up:
  `new T` keys on `SimpleName(ErasedName(T))` so `System.IO.FileStream` matches, while `f(...)` keys on the
  FULL dotted target so a user's `MyApp.File.Open` does NOT. Contract-pinned in both directions (slice 3).
- The `IsResultType` identity guard in the 128-byte Result-ABI rule is LOAD-BEARING: any generic of arity
  two sizes as 16 + both payloads, so `Unknown<Result<Vec,Vec>, Result<Vec,Vec>>` reaches the same 176
  bytes and must stay silent (slice 2).
- Size tables are keyed by the LANGUAGE KEYWORD and the CLR spelling misses them (`System.Int32` lands on
  the unknown default, 16 bytes in the stackalloc element table and 8 in `EstimateSimpleTypeSize`).
  Reproduced exactly, never widened — widening changes every systems project's reported byte count and
  belongs to a slice that owns the whole size subject (slices 1, 2).
- Preferred severity belongs to the RULE, not the sink; the sink applies the boundary downgrade then the
  audit downgrade, in that order. `AddTypeFinding` has no `[hot]` arm, no preferred severity and no
  boundary arm — a type has no hotness — and that asymmetry is contract-pinned in both directions. The
  `[hot]`/`[boundary]` MESSAGE prefix is composed at exactly two sites and is NOT the sink's `Policy`
  field, which has a third arm the prefix does not (slices 4, 5).
- Every moved arm takes `SystemsAllowStack` (DATA) rather than a `bool`: a `bool` door would have stranded
  twelve effect-name literals in C# as the price of moving eleven codes; passing data moves the code, the
  effect, the sentence, the fix and the waiver test together (slice 8).
- Ledgers do not move while a C# writer remains; they are handed over as `Dictionary` parameters.
  `PoolRent`/`ResourceLocal` being ALREADY N# classes is what lets the discharge happen inside the owner
  and cross no boundary the language cannot express (slices 3, 5).
- A project setting belongs on the rule that reads it, in the owner's own `BeginAnalysis`, not on the sink
  — and the owner must still treat any unrecognised string as `warn`, because a `SystemsAnalyzer` can be
  built with a config that never went through `ProjectFileParser` (slice 6).
- Relays are TRANSITIONAL, not architecture: slice 6 priced a "move the policy half" relay at −3 lines
  against −17 for resolving at the walk and deleting outright, and rejected it — the relay would leave a
  member that is neither a rule nor one of the host's six partition classes.
- A caller-less overload is DELETED, not ported, and the deletion is proved behaviour-neutral by EXECUTION
  rather than merely proved unreferenced (the dead 7-parameter `AddFinding`, `ApplyBufferMemoryCopyFacts`'s
  dead second guard, `AddHotFinding`/`AddFindingForPolicy`) (slices 4, 7, 8).
- Run the terminality grep against the SUBJECT, not the member list — it found something the closure
  scoring missed three slices running: the inline `is StackAllocExpression` binding test, the inline
  `EstimateResultSize > 128` threshold, and the inline `.Rent` / `Ok|Err` tests plus the whole
  `IsDictionaryTryGetValueCall` member (slices 1, 2, 3).
- A dead guard is PRESERVED with its reason recorded, not tidied: the strict-profile arm's unreachable
  `!isBoundary` conjunct stays, because removing a redundant guard is behaviour-neutral only for as long as
  the arm above it keeps returning. Unreachable-from-N# rules are still ported byte-for-byte
  (`GetCallTarget`'s `ParenthesizedExpression` arm) so a parser that later accepts the form finds the rule
  already written (slices 2, 3).
- `ENTER == ANSWER` on all eight drivers is an assertion about the DRIVER — exactly one routed outcome per
  dispatch, never two and never none — and it is only meaningful because a `default:` arm was added to
  every switch so unmatched node kinds are COUNTED rather than silently skipped (slice 8).
- The `MultiFileCompiler` seam is one construction site and one method, and the whole report surface is
  already N#; the seam is 019/021 territory, not 018 debt (slice 8).
- Re-pointing `MutableFunctionSummary.MergeEffectsFrom` at the N# `SystemsEffectFacts` record collapsed a
  16-line inline projection already duplicated at the merge site into one mechanical `ToFacts()` door —
  the file shrank 17 lines in a member the brief did not predict (slice 7).

### 4.6 Task 017 — the semantic analyzer (complete at `dae23a74d`; box CHECKED)

Outcome: `Analyzer.cs` 23,060 → 2,962 lines (−20,098, −87.2%; non-blank 20,246 → 2,748) over 67 slices,
from `dfec28f2a` to `dae23a74d`. Contracts 1,554 → 3,890; the semantic model is 80 `Analyzer*.nl` owners /
47,173 production lines with 73 contract files; 29 driver loops, 5 dispatches. FOUR toolset repins in the
whole arc (12A / 20A / 22 / 48) and ZERO from slice 49 on. The task closed on the checkbox's SECOND arm —
a reviewed zero-policy mechanical host — because task-021 MLC loading keeps the file alive.

| slice id | commit(s) | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| 017 slice 67 (zero-policy review; task 017 close) | `dae23a74d` (accepted; base `829faee32`) | Review, not a port: cut 8 extents / 19 lines from `Analyzer.cs` — 5 dead `Error`/`Warning`/`GetSourceSnippet` helpers (13 lines, zero callers), 3 write-only fields (`_currentFilePath`, `_compilationUnit`, `_sourceText`), and moved `ThisExpression`'s `?? Unknown` rule into `AnalyzerScopeStack.CurrentTypeScopeOrUnknown` (+14 N# lines) | VERDICT: `Analyzer.cs` is a REVIEWED ZERO-POLICY MECHANICAL HOST — 186 extents in SEVEN classes (class 7 deleted), UNCLASSIFIED = 0; it is not deleted and will not be (task-021 MLC loading keeps it alive), so 017 closes on the checkbox's SECOND arm | `Analyzer.cs` 23,060 → 2,962 (−87.2 %) over 67 slices; 2,986→2,962, non-blank 2,767→2,748; contracts 3,889→3,890; 80 N# owners / 47,173 lines; 29 drivers; gate ALL TESTS PASSED 19m47s |
| 017 slice 66 (last policy slice) | `829faee32` (base `43472d7ce`) | 20 C# extents / 466 lines out of `Analyzer.cs`: declaration family (139), default-parameter family (153), package name (27), expression tail (78 incl. the 39-line `AnalyzeExpression` tail body), reference-load report (37), plus 32 lines deleted as dead → new `AnalyzerDeclarationPolicy.nl` (750), `AnalyzerExpressionTail.nl` (191), `AnalyzerReferenceLoadReport.nl` (158), `AnalyzerDiagnosticSink.nl` +26 | The overload merge was NEARLY LOST: C# passes `new[]{existingFunction}` alone; the port's first draft passed BOTH, which would have made every overload in the language a duplicate-declaration error. Caught by re-reading C# against the port BEFORE any oracle — a corpus without overloads would have passed it | `Analyzer.cs` 3,422→2,986, non-blank 3,148→2,767, extents 210→194, diff +75/−511; drivers 28→29; contracts 3,833→3,889 (+56); 87.3 % cut from epoch |
| 017 slice 65 (import/namespace family, terminal) | `43472d7ce` (base `456288ecf`) | 15 C# members / 468 lines (`ProcessImports`…`FormatImportCollisionSources` + the unnamed `ProcessImportForAssemblyLoading` 33, a 17-row namespace→assembly policy table) → new `AnalyzerImports.nl` (912 lines, 3 types, 34 members); `AnalyzerExternalTypeProbe.nl` +6/−5 comment correction | A RECORDED WALL IS EVIDENCE WITH AN EXPIRY DATE — re-measure it by execution before honouring it. The probe's header claimed `Assembly.get_FullName`/`AssemblyName.get_Name` were off the columnar surface; a probe build proved BOTH are on it, exit 0, no repin | `Analyzer.cs` 3,866→3,422, non-blank 3,538→3,148, extents 225→210, diff +47/−491; drivers 27→28 (first driver relaying an EFFECT not an answer, 18 lines of C# for 468 deleted); contracts 3,779→3,833 (+54); 85.4 % cut |
| 017 slice 64 (attribute validator, terminal) | `456288ecf` (base `19ac88cfc`) | 48 C# members / 49 extents / 959 lines + a 6-line private record → new `AnalyzerAttributeValidator.nl` (1,452 lines, 2 types, 49 members); `TypeInfoIdentityFacts.nl` +22 (`HasSourceEnumMember`, `HasRuntimeEnumMember`) | NO DRIVER WAS ADDED and that is the defining measurement: every collaborator was already N#-owned and published, so 959 lines of policy left C# for ONE line of routing. The two argument tables stay SEPARATE (slice 49's note): `null` is kind `Null` but types as `object`; `typeof` is kind `Type` but types as `System.Type` | `Analyzer.cs` 4,866→3,866 (first time under 4,000), non-blank 4,425→3,538, members 191→142, diff +19/−1,019; drivers stay 26; contracts 3,676→3,779 (+103); 83.5 % cut |
| 017 slice 63 (expression-tree validator + declaration walkers) | `19ac88cfc` (base `217cb5a8e`) | 19 C# members / 563 lines + a 35-line pre-pass inside `Analyze`: expression-tree validator (241), test walker + table rules (145), setup/teardown (94), constructor walker (38), plus the opportunistic `ReportSoaRowTypeReferencesInAttributeTypeof` (45) → new `AnalyzerExpressionTreeValidator.nl` (530), `AnalyzerDeclarationWalkers.nl` (955), `AnalyzerTypeResolver.nl` +83, `AnalyzerLambdaAnalysis.nl` +36/−20, `AnalyzerDiagnosticSink.nl` +24 (`HasReported`) | Slice 62's fork reason was WRONG: the expression-tree validator is NOT purely syntactic — `IsExpressionTreeStaticCallReceiver` reads four collaborators because `x.Trim()` and `Path.Combine(...)` are the same AST shape. All were already N#, so lambda kinds 7 and 8 DIED rather than moved. The census also found ~1,800 lines of policy the completion assessment never named | `Analyzer.cs` 5,416→4,866, non-blank 4,901→4,425, members 209→191, diff +87/−637; drivers 25→26; contracts 3,613→3,676 (+63); residual policy measured at ~1,815 lines / ~80 members |
| 017 slice 62 (lambda, `on`, `base`, reflected bind half D) | `217cb5a8e` (base `e4bbdac29`) | 8 C# members / 343 lines: `AnalyzeLambda` 104 + `GetFunctionSignature` 26, `AnalyzeOnSubscription` 84, `AnalyzeBaseExpression` 10, and half D (`BindReflectionCall` 53, `BindSingleReflectionMethod` 27, `FinalizeBoundReflectionCall` 27, `AnalyzeExpressionAllowingUnboundCallableReference` 12) → new `AnalyzerLambdaAnalysis.nl` (669), `AnalyzerCallAnalysis.nl` +379/−33 (→1,380), `AnalyzerDeclarationContext.nl` +22 (`ResolveBaseType`), `AnalyzerDiagnosticSink.nl` +25 (`RollbackErrorsTo`) | PHASE-NUMBER COLLISION regression, found by the self-host oracle and root-caused: the reflected bind was numbered 20-26, but `AdvanceCall` routes 14-17 then FALLS THROUGH to the N#-method-group return owning 18-23, whose range appears in no listed case. RULE: a phase range routed before a fall-through must be disjoint from everything the fall-through can see; "the next free number" does not measure that. Renumbered 30-36 | `Analyzer.cs` 5,638→5,416, non-blank 5,088→4,901, diff +124/−346; call kinds 12,13 die and 15 arrives (no renumber, slice 37 rule); contracts 3,570→3,613 (+43); brief under-named the lambda closure by 6 members / 220 lines and the call-site count by one since slice 59 (9 sites / 4 owners, not 10) |
| 017 slice 61 (call arm's deciding half) | `e4bbdac29` (base `3493fd47d`) | 6 C# members / 183 lines + 3 suppression fields + a 4-line orphan doc: `TryAnalyzeResultConstructorCall` 54 + `TryGetResultArmTypes` 25, `AnalyzeCallCallee` 7 + `AnalyzeCallCalleeExpression` 19, `AnalyzeRefOutArgumentExpression` 35 + `ReportInvalidRefOutArgumentTargetIfNeeded` 43 → `AnalyzerCallAnalysis.nl` +424/−51 (661→1,034), `AnalyzerAmbientContext.nl` +86 (the three suppressions with Enter/Exit and `AmbientCallCalleeFrame`) | `Type.GetType("…, SomeAssembly")` is a RUNTIME assembly load, NOT `typeof`: it answers null in any host that does not reference the assembly (proved by execution in the BootstrapServices test host, 5 contracts failed), so it is the wrong port for a `typeof` identity anchor — route through `AnalyzerDeclarationContext.IsRuntimeResultDefinition`. Also: `Kind` is what the DRIVER performs, `Pending` is what the WALK does with the answer — they had always been different | `Analyzer.cs` 5,850→5,638, non-blank 5,277→5,088, diff +21/−233; call protocol 11 kinds → 8 (1, 2, 5 retired; gaps kept, no renumber); contracts 3,558→3,570 (+12); brief under-named the arm's closure by 3 members |
| 017 slice 60 (SoA direct-column call family; 017/018 boundary re-derived) | `3493fd47d` (base `0f6a5d8ca`) | 19 C# members / 331 lines + a 4-line orphan doc: 5 reporters (117), 12 predicates (202), 2 parameter tables (12) → new `AnalyzerSoaDirectColumnCalls.nl` (564 lines, 1 type, 18 members, sibling to `AnalyzerSoaEscape`); `AnalyzerCallAnalysis.nl` +16/−16 | THE FILE CRITERION SETTLED THE 017/018 BOUNDARY: both tasks' completion criteria are FILE-scoped (`Analyzer.cs` vs `SystemsAnalyzer.cs`), and every member of this family lives in `Analyzer.cs` — `SystemsAnalyzer.cs` has ONE `Soa` occurrence in 2,390 lines. Slice 24's subject-matter line made 017's terminal state unreachable and advanced 018 by nothing; its "reachable only from the call walk" premise was also FALSE | `Analyzer.cs` 6,201→5,850, non-blank 5,588→5,277, members 238→220, diff +17/−368; call kinds 9,10,11 retired, phases 9-12 collapse to one (four round trips → one); contracts 3,534→3,558 (+24); brief understated the family by 81 lines |
| 017 slice 59 (`range`, `match`-as-expression, call arm's static-addressability pre-cut) | `0f6a5d8ca` (base `93dfdd615`) | 13 C# members / 14 extents / 301 lines: range arm (50), `IsIndexLikeType` (3), match-as-expression (116: `AnalyzeMatchExpression` 72, `FindCommonBaseType` 31, `AnalyzeExpressionWithoutExpectedType` 13), ref/out static-addressability pre-cut (132) → new `AnalyzerRangeExpression.nl` (217, the estate's smallest resumable owner), `AnalyzerMatchExpression.nl` (382), `AnalyzerWriteTargets.nl` +205 (rule 8) | STANDING PATTERN: a two-caller predicate dies when the SECOND caller moves, and never before (`IsIndexLikeType`, after `IsRangeLikeType` in slice 58). The match arm is the first owner holding BOTH walk forms — slice 51's owner-held plain bracket AND slice 52's target-typed driver kind — because `AnalyzeExpressionWithExpectedType` forks a lambda to `AnalyzeLambda` BEFORE any bracket opens. The arm join's under-specification (first arm wins; `Dog` then `Animal` types as `Dog`) is preserved, not improved | `Analyzer.cs` 6,420→6,201, non-blank 5,765→5,588, diff +96/−315; expression walk 13→11 policy arms; drivers 21→23, returning 10→12; contracts 3,484→3,534 (+50); three contracts failed and all three were the CONTRACT being wrong (7th consecutive slice) |
| 017 slice 58 (assignment arm + write-target family, terminal) | `93dfdd615` (base `306331225`) | 45 C# members / 1,187 lines + 3 host slots: assignment arm and closure (13/474), write-target reporters (15/324), readonly-field target family (10/304), shared classification tail published-and-routed (6/82), `IsRangeLikeType` (3) → new `AnalyzerWriteTargets.nl` (1,054, 37 members, 7 shared rules) and `AnalyzerAssignment.nl` (774, 3 types, 30 members); `AnalyzerAmbientContext.nl` +91 (took `_assignmentTargetExpressionTypes`, `_allowEventReference`, `_inConstructor`); `AnalyzerConstruction.nl` +8/−132 deleting slice 57's REPRODUCTION of the readonly-field rule | THE SPLIT INTO TWO OWNERS IS FORCED, NOT PREFERRED: assignment needs the operator family and the operator family needs the write-target reports, so one owner would be a CYCLE the language cannot express. Slice 56 refused to merge index+array (shared only a SHAPE), slice 57 merged new+with (shared a RULE), this one could do neither. A resumable owner's bracket must close in `Supply`, not in the phase handler — the handler runs one call later than the C#'s `finally` | `Analyzer.cs` 7,646→6,420, non-blank 6,843→5,765, members 290→248, diff +124/−1,350 (net −1,226, the arc's largest); `DriveOperatorExpression` 10 kinds → 3 (arc's largest protocol reduction, an increment takes ONE step where it took seven); stay-behind report kinds 5 → ZERO; contracts 3,436→3,484; brief understated the family 401 → 1,188 lines (8th consecutive) |
| 017 slice 57 (construction family: `new`, `with`, the shared object-initializer rule) | `306331225` (base `4699ad20c`) | 14 C# members / 772 lines (the arc's largest single cut at the time): `new` arm and closure (456), `AnalyzeWithExpression` (54), and the 262 lines of object-initializer rule the two shared (`TryResolveObjectInitializerMemberType` 141, `TryGetDeclaredTypeShape` 34, `FindDeclaredMemberTypeReference` 21, the two SoA initializer reports 66) → new `AnalyzerConstruction.nl` (1,416 lines, 3 types, 51 members) | A RESUMABLE WALK WITH MORE THAN ONE SECTION NEEDS TWO COUNTERS — `Phase` (outstanding step, returns to 0) and `Stage` (where in the form, only moves forward); a phase-only machine re-enters a finished section and `new int[4]` would have reported its conflict TWICE. Found in the slice's own first draft. Also: the NL202 front door is the only guard against `EmitValueCoercion`'s silent no-op for closed generics over emitted user types | `Analyzer.cs` 8,371→7,646, non-blank 7,501→6,843, diff +52/−777; drivers 19→20, returning 8→9; first time two expression arms share one driver (`DriveConstruction`, 2 kinds); contracts 3,395→3,436 (+41), 8 failed first and ALL EIGHT were the contract being wrong; brief understated 183 → 772 lines (7th consecutive) |
| 017 slice 56 (the wall that was not there; `index` + `array` + NL303 rendering, terminal) | `4699ad20c` (base `4fde8ff23`) | 34 C# members / 599 lines: index family (9/235), array family (19/269, incl. the 15-member collection-expression materialisation rule), NL303 rendering (6/95, of which `ResolveAliasAndMetadata` was already reproduced in N# so the C# copy DIED) → new `AnalyzerIndexAccess.nl` (522), `AnalyzerArrayLiteral.nl` (549), `AnalyzerMemberAccess.nl` +180/−66 | THE WALL SLICE 55 PRICED DOES NOT EXIST — no catalog row was added, no stage boundary taken, no toolset repinned. `PropertyInfo.get_Name()`/`FieldInfo.get_Name()` already bind under the PINNED toolset. Root cause: `ColumnarExternalBindingPlans` is the LEGACY whole-subtree planner's surface; `ColumnarDirectCallPlanner` falls through to `ColumnarOrdinaryRuntimeDirectCallResolver`, which binds any suitable public non-generic instance method on a receiver in `IsSupportedRuntimeTypeName`. NEVER RE-PRICE THIS WALL. What slice 55 measured was its OWN gotcha 6, the property spelling | `Analyzer.cs` 8,946→8,371, non-blank 7,991→7,501, members 334→302, diff +77/−652; driver kind 2 RETIRED (`MemberAccessRequest` loses 2 fields, `MemberAccessState` loses 3 pending slots); drivers 17→19, returning 6→8; contracts 3,345→3,395 (+50); `GetDefaultMembers` substitute proved over 317 assemblies / 23,645 types, DIFFS 0, comparator perturbation finds 6 |
| 017 slice 55 (member arm, its exclusive closure, the undefined-member report family) | `4fde8ff23` (base `f7f7c4b30`) | 24 C# members + the 8 built-in member tables / 542 lines: `AnalyzeMemberAccess` 87, its exclusive closure, the receiver classification, the SHOULD-REPORT rule and its helpers, `MakeNullableResult`, `ReportSoaDirectColumnNullConditionalAccessIfNeeded` (→ `AnalyzerSoaEscape`) → new `AnalyzerMemberAccess.nl` (1,008 lines, 3 types, 37 members, 22 collaborators, 4 arriving via `SetMetadataCollaborators` rather than a factory rebuild because the owner carries per-analysis state) | The NL303 RENDERING was left behind as driver kind 2 on a "measured two-row catalog wall" (`PropertyInfo.Name`/`FieldInfo.Name` allegedly unmodeled). **SLICE 56 OVERTURNED THIS: the wall does not exist** — what was measured was this slice's own gotcha 6, the property spelling. Census finding that stands: the member arm almost never reports — 23 undefined-member reports in 83,455 walks (1 per 3,628) and 34 zero-step answers | `Analyzer.cs` 9,428→8,946, non-blank 8,416→7,991, members 365→334, diff +75/−557; drivers 17, 6 return; contracts 3,291→3,345 (+54); protocol differential 5 runs / 333,798 rows / 0 mismatches, ENTER==RESULT, STEP==ANSWER, max nesting 4; 165 of 588 accumulated fixture directories had been REAPED from `/private/tmp` |
| 017 slice 54 | `f7f7c4b30` (landed); target tip `3546a9e17` | `Analyzer.cs` identifier arm: 5 members / 188 lines deleted (`ResolveIdentifier` 66, `TryResolveIdentifierBindingTarget` 69, `TryResolveVisibleProjectFunction` 22, `ReportUnverifiedErrorTupleResultUseIfNeeded` 20, `AnalyzeIdentifierCallTarget` 11) + 2 state fields → new `AnalyzerIdentifierResolution.nl` (337 lines, 1 type, 11 members, 11 held collaborators + 2 behind a setter) | The arc's first expression family with NO driver loop: `ResolveIdentifier` takes ZERO expression steps (grep for `AnalyzeExpression` over its whole closure returns 0), so it is a rule with two consumers, not a walk. It is constructed ONCE and told about rebuilt collaborators via `SetMetadataCollaborators`, because a `Create…` factory would drop its per-analysis `(line,column,name)` dedupe set. | `Analyzer.cs` 9,611→9,428 (+20/−203, non-blank −160, members 371→365); contracts 3,256→3,291; 304,014 probe rows 0 mismatches; gate 19m08s, 108 passes |
| 017 slice 53 | `3546a9e17` (landed); target tip `e191ec36d` | The operator expression family: 46 C# members / 1,248 named lines gone (binary arm 9/399, operator-overload resolution 7/276, unary arm 8/224, numeric tables + comparison rules 18/273, four unnamed 4/76) → new `AnalyzerOperatorExpressions.nl` (1,806 lines, 3 types, 84 members, 11 collaborators, rebuilt via `CreateOperatorExpressions`) | There is no honest split along the arm axis: `GetNumericName`, `IsIntegralType`, `GetUnaryNumericPromotionType` and `TryResolveOperandClrType` each have callers in BOTH the unary and binary arms, so either order leaves the other relaying four tables. Moving both retires slice 52's driver kind 3. | `Analyzer.cs` 10,796→9,611 (+175/−1,360 = net −1,185, the arc's largest cut); contracts 3,208→3,256; 266,804 probe rows 0 mismatches, max nesting 67; gate 19m48s |
| 017 slice 52 | `e191ec36d` (landed); target tip `5e2a28a89` | Target-typed operand family (`cast`/`checked`/`unchecked`/`ternary`): 5 C# members / 63 named lines gone, 4 dispatch arms collapse to 1 → new `AnalyzerTargetTypedOperands.nl` (443 lines, 3 types, 16 members, 4 collaborators, NO sink and NO span reader) | `AnalyzeCastExpression` raises NO diagnostic of its own — the brief named a diagnostic family that does not exist; the whole family reports nothing on its own account, which is why its owner is the first in the arc holding neither a diagnostic sink nor a span reader. Cast's two doors DIFFER observably: `print (int)default` is clean, `print default as int` reports NL203. | `Analyzer.cs` 10,813→10,796 (+55/−72 = net −17, the arc's thinnest cut); contracts 3,181→3,208; 7,702 probe rows 0 mismatches; door A entered 4× in the whole world, all 4 this slice's fixtures |
| 017 slice 51 | `5e2a28a89` (landed); target tip `b6f4a12cc` | Pass-through operand family (`throw`/`is`/`spread`/`alloc`/`must`/`stackalloc`/`tuple`/`await`): 14 C# members / 285 named lines gone (not the 8 the brief counted), 8 dispatch arms collapse to 1 → new `AnalyzerPassThroughOperands.nl` (769 lines, 3 types, 25 members, 8 held collaborators) | The arc's first family whose ANSWER is a function of its step's answer — slices 49/50 settled at `Begin`, here `ResultType` starts `unknown` and is decided in the phase after the step. `_patternReachability` is NOT readonly (rebuilt at `:10572`/`:10600`) so it arrives at `Begin` and rides the state, never held. | `Analyzer.cs` 11,096→10,813 (+42/−325 = net −283); contracts 3,139→3,181; 1,016 probe rows 0 mismatches; `throw`/`spread`/`must`/`stackalloc` never entered by corpus OR self-host |
| 017 slice 50 | `b6f4a12cc` (landed); target tip `974a4b231` | Compile-time constant family (`typeof`/`sizeof`/`nameof`/`default`): 5 C# members / 77 named lines gone (`AnalyzeNameofExpression` 26, `AnalyzeDefaultExpression` 22, `ReportSoaDefaultValueIfNeeded` 15, `AnalyzeTypeofExpression` 9, `AnalyzeSizeofExpression` 5) → new `AnalyzerCompileTimeConstants.nl` (331 lines, 3 types, 14 members, 6 collaborators) | The brief was WRONG in three ways: `nameof` does NOT take zero steps (its `AnalyzeExpression(target)` is unconditional and its answer is the row-escape report's operand); it is 5 members not 4 (the brief counted dispatch ROOTS); and the walk establishes no expected type for its step, so `nameof`'s target INHERITS the dispatch's slot. `_wellKnownTypes` is rebuilt AND nulled by the metadata load context so it arrives at `Begin`; `_typeResolver` is readonly and held. | `Analyzer.cs` 11,144→11,096 (+38/−86 = net −48); contracts 3,111→3,139; 3,756 probe rows 0 mismatches; family entered 1,771× over corpus+self-host, EVERY ONE a `typeof` |
| 017 slice 49 | `974a4b231` (landed); target tip `f3f1c2c3b` | The expression walk opens: literal family, all 7 arms. 4 C# members / 74 named lines gone (`GetIntLiteralType` 31, `TryGetExpectedIntegerLiteralType` 28, `AnalyzeInterpolatedString` 13, `AnalyzeStringLiteral` 2) → new `AnalyzerLiteralExpressions.nl` (379 lines, 3 types, 13 members, 3 collaborators). Publishes the 41-arm scored inventory (LN/SB/RE/diags/AMB per arm) that briefs slices 50–54. | The estate's first ANSWERING DRIVER. All ELEVEN pre-existing drivers return `void` and carry answers only INWARD via `Supply`; nothing carried a walk's answer OUTWARD because no statement/declaration walk ever had one. The territory needed exactly one new thing: `Result(state)` + a `TypeInfo`-returning loop (10 lines). The brief expected the opening arm to re-enter — six of seven do NOT. | `Analyzer.cs` 11,189→11,144 (+41/−86 = net −45); contracts 3,078→3,111; 112,430 probe rows 0 mismatches; 55,545 walks / 670 steps, max nesting 2 |
| 017 slice 48 (two stages) | stage 1 coordinator commit `f71b5c1e6`; stage 2 `f3f1c2c3b` (landed); plan tip `97bb14ecc` | Stage 1: one catalog row `"IsLower"` into `ColumnarIlEmitter.cs`'s `System.Char` switch (`:14286`) + 7 contracts in `tests/native/char-classification`. Stage 2: 15 C# members / 583 named lines gone (8 type-declaration walkers 462 lines + 6 census-found exclusive helpers + `CheckVisibilityConvention` 16) plus 2 ambient fields → `AnalyzerTypeDeclarations.nl` (1,342 lines, 3 types, 44 members) + `AnalyzerDeclarationConventions.nl` (54 lines, 1 static member) + 58 lines on the ambient context | The arc's FIRST toolset repin, and the reason for the two-stage split: a catalog row must be COMMITTED and the toolset REPACKED FROM THE COMMITTED TIP before the packaged SDK can build N# that calls it — packing mid-slice from a working tree is forbidden. The brief's shared-shape claim was WRONG: the forward-reference first pass is a CLASS's alone; levelling it would have made a forward reference between two STRUCT methods resolve where it does not today. | `Analyzer.cs` 11,739→11,189 (+100/−650 = net −550); `ColumnarIlEmitter.cs` 21,470→21,471; contracts 3,036→3,078 (+23 migrated); 45,481 probe rows 0 mismatches, max nesting 3; convention checked 12,615× |
| 017 slice 47 | `97bb14ecc` (landed); target tip `13950c477` | Property / indexer accessor family: 3 C# members / 116 named lines gone (`AnalyzePropertyDeclaration` 71, `AnalyzeIndexerDeclaration` 31, `DeclareIndexerParameters` 14) → new `AnalyzerAccessorBodies.nl` (697 lines, 26 members, 5 collaborators, deliberately NOT the scope stack) + new `DriveAccessorBody` (44 lines, TEN kinds) | The slice-46 brief was wrong in FOUR ways — 116 lines not ~127, and TWO call sites not three, neither in a member walk (both are arms of the ONE `AnalyzeDeclaration` dispatch). Its own owner rather than a third form of the function walk because the balance invariant is per ACCESSOR, not per declaration: a `{ get set }` property opens TWO scopes, which would have weakened three passing slice-44 contracts. | `Analyzer.cs` 11,791→11,739 (+71/−123 = net −52); contracts 3,004→3,036; 12,910 corpus probe rows 0 mismatches, 1,198 opens == 1,198 closes; corpus contains NO indexer at all (kind 6 fires ZERO times) |
| 017 slice 46 | `13950c477` (landed); target tip `077d02c5e` | `AnalyzeFunctionDeclaration` joins `AnalyzerFunctionBodies` as FORM 1: 4 members / 305 named lines gone (`AnalyzeFunctionDeclaration` 164, `ValidateOperatorOverload` 65, `CheckCircularGenericConstraints` 60, plus `CheckVisibilityConvention` 16 deleted then RESTORED at the wall) → `AnalyzerFunctionBodies.nl` 653→1,268 lines, 26→43 members. No new file. | THE ARC'S FIRST REAL WALL, and it is a CATALOG gap not a closure one: `char.IsLower` is absent from `ColumnarIlEmitter.cs:14286`'s `System.Char` catalog (`IsUpper` is there). NO published predicate reproduces it — `IsLetter && !IsUpper` accepts title-case, `ToUpperInvariant(c) != c` refuses `ß`, an ASCII range refuses `é`; every approximation SILENTLY changes which identifiers get NL903. Stopped at the wall and relayed as kind 10. | `Analyzer.cs` 12,048→11,791 (+63/−320 = net −257); contracts 2,976→3,004; 124,549 probe rows 0 mismatches; 98.8% of top-level declarations take the method-group SKIP path (151 of 12,684 declare their own name) |
| 017 slice 45 | `077d02c5e` (landed); target tip `bff998d23` | `AnalyzeStatement` falls, statement territory CLOSES: 8 members / 60 named lines gone (`AnalyzeStatements` 21, `RecordVariableInCurrentScope` 14, `RecordFunctionInCurrentScope` 14, 5 forwarders, 4 inline-policy arms, the `_currentLine` cursor) → new `AnalyzerStatementSequence.nl` (279 lines, 3 types, 12 members) + `NoteLine`/`RecordVariable`/`RecordFunction` on `AnalyzerScopeStack.nl`; one new C# member `DriveStatementSequence` | The three-way shape fork was costed and forks (a) and (b) REFUSED on CORRECTNESS, not cost: (a) a discriminated route with 9 nullable state slots DE-TYPES the dispatch (today `case IfStatement` → `BeginIf` → `DriveLoopStatement` is type-checked end to end); (b) unifying the eight drivers would renumber contract-pinned kinds whose differences are load-bearing (`DriveLoopStatement` kind 5 is ONE statement, `DriveExpressionStatement`'s is a LIST — and that difference IS the unreachable-code rule). The estate's first walk with NO `Supply`, because none of its three operations answers anything. | `Analyzer.cs` 12,066→12,048 (+89/−107 = net −18); contracts 2,954→2,976; 240,400 probe rows 0 mismatches, 52,151 PUSH == 52,151 POP, max depth 15. Arc total slices 31–45: 13,946→12,048 lines |
| 017 slice 44 | `bff998d23` (landed); target tip `061096f15` | `AnalyzeLocalFunction`, the last policy-carrying named arm: 6 members / 180 named lines gone (`AnalyzeLocalFunction` 71, `ReportGeneratorReturnTypeIfNeeded` 33, `ValidateParamsParameters` 31, `IsGeneratorSequenceReflectionType` 20, `ReportGeneratorExpressionBodyIfNeeded` 17, `IsGeneratorSequenceReturnType` 8) → new `AnalyzerFunctionBodies.nl` (653 lines, 26 members) + `AnalyzerParameterDeclarations.nl` (52 lines); one new C# member `DriveFunctionBody` | The three shared blockers forked INDEPENDENTLY and did not answer the same way: two moved whole (N#-complete closures), `ValidateParameterDeclarations` (EIGHT callers, not the two the brief claimed) RELAYS because its closure reaches `AnalyzeExpressionWithExpectedType` — but its N#-complete half `ValidateParamsParameters` (31 lines) moved anyway, putting all 8 callers on N# for the `params` half. The expected-type kind is its OWN number, not a widening of kind 1: `AnalyzeExpressionWithExpectedType` short-circuits a lambda into `AnalyzeLambda(lambda, expectedType)` with the ambient slot UNTOUCHED, so the paths diverge (fixture f25, NL203 on both sides). | `Analyzer.cs` 12,178→12,066 (+70/−182 = net −112); contracts 2,905→2,954 (+49); oracle 0 diffs over 71 targets; compiler warnings 10→9 |
| 017 slice 43 | `3f04d6ed8` (landed); target tip `e929453e0`, re-anchored mid-slice onto `0a66db6ec` | The `if` arm terminal + `StatementAlwaysReturns` moved whole: 3 members / 114 named lines gone (`AnalyzeIfStatement` 54, `StatementAlwaysReturns` 58, forwarder `IsUnitTaskLikeTypeReference` 2) → `AnalyzerLoopSequence.nl` 1,451→1,738 (Form 3, phase band 30..37) + new `AnalyzerStatementTermination.nl` (189 lines, 1 type, 4 members). ZERO new C# members and ZERO new driver kinds. | The slice-42 brief was WRONG about the dependency direction: `StatementAlwaysReturns` never calls `AnalyzeStatements` — `AnalyzeStatements` calls IT — so the predicate's closure is N#-COMPLETE and the estate's first boolean-answering driver kind was never needed. Three items of the evidence bar (protocol differential, IL sweep, full gate) were explicitly OWED, not run, because three concurrent sessions were rewriting the same checkout and the tip moved mid-slice. | `Analyzer.cs` 12,292→12,178 (+21/−135 = net −114); contracts 2,865→2,897 (+32); oracle 0 diffs, 597 diagnostics/13 codes; unit suite 3,178/3,194 with 16 failures proved ENVIRONMENTAL (missing `Mono.Cecil.dll` in the packaged SDK) |
| 017 slice 42 | `e929453e0` (landed); target tip `8811585f4` | `switch` and `off`, TWO independent moves: 2 members / 64 named lines gone (`AnalyzeSwitchStatement` 31, `AnalyzeOffStatement` 33) → `AnalyzerPatternAnalysis.nl` 759→924 (Form 1, band 70..75, 3 new kinds) and `AnalyzerExpressionStatements.nl` 1,120→1,264 (sixth form, band 50..51, ZERO new kinds). The pattern driver's SoA relay kinds 2 and 3 DIE; numbering keeps GAPS rather than closing up. NO new file. | `off` is NOT switch's other half: it is an EVENT statement living 3,200 lines away, sharing no scope, ambient frame, pattern or statement list. FIRST time in the arc the re-measurement came back at 1.00x rather than 4x — neither arm has a single exclusive C# helper. A dedicated `AnalyzerSwitchStatement.nl` was refused as net +22 C# in a slice whose purpose is C# deletion. | `Analyzer.cs` 12,348→12,292 (+35/−91 = net −56); contracts 2,843→2,863; 2,651 corpus probe rows + 2,966 fixture rows, 0 mismatches; the 71-target corpus contains NOT ONE `switch` and NOT ONE `off`; gate 31m36s, 106 passes |
| 017 slice 41 | `8811585f4` (landed); target tip `917cdfef7` | The resource family `try`/`using`/`lock` on one driver + `IsThrowableType` deleted: 16 C# members / 396 named lines gone → new `AnalyzerResourceStatements.nl` (1,065 lines, 3 types, 33 members) + new `AnalyzerThrowability.nl` (137 lines, 1 type, 3 members) + `AnalyzerExpressionStatements.nl` +74/−53. One new C# member `DriveResourceStatement` (52 lines); `DriveExpressionStatement`'s kind 7 dies. | The brief was wrong in BOTH directions again — 396 named lines across SIXTEEN members, four times the 99 briefed. The brief's body-walk warning was BACKWARDS: all five bodies go to `AnalyzeStatement` (SINGULAR) and re-enter the dispatch's own block arm, so taking the LIST walk would have DOUBLE-applied the unreachable-code rule and skipped the block scope. Throwability moved whole to its own file because the answer is not a function of the type alone. | `Analyzer.cs` 12,694→12,348 (+79/−425 = net −346); contracts 2,792→2,843 (+51); 5,295 corpus + 2,238 fixture probe rows, 0 mismatches; compiler warnings 11→10; gate 32m47s |
| 017 slice 40 | `917cdfef7` (landed); baseline `781f5a470` | `Analyzer.cs` −74 net (12,768→12,694, 8 hunks): `AnalyzeForStatement` (43) and `ReportNonThrowableThrowOperandIfNeeded` (15) deleted, `while`/`for`/`throw`/`print` arms collapsed to routing lines → `AnalyzerLoopSequence.nl` (+553/−75) and `AnalyzerExpressionStatements.nl` (+176/−13); `DriveForeachStatement` RENAMED `DriveLoopStatement` for zero new C# | A driver may drive a driver and stay zero-policy: kind 7 hands one expression to `DriveExpressionStatement(BeginForIterator)`. One state serving four walks needs PHASE BANDS (iteration 0..6, `while` 10..14, `for` 20..29), never a shared counter. `while` extracts narrowings BEFORE the boolean report; `for` reports first — must not be unified | Analyzer.cs 12,694; N# +1,165 / 4 files; contracts 2,772→2,792; gate 33m51s all green |
| 017 slice 39 | `a4080a0e8` (landed); baseline `a5f034cda` | `Analyzer.cs` −58 net (12,826→12,768, 13 hunks): `IsBoolType` (4) and `ReportBooleanConditionTypeMismatch` (13) deleted, the `if` arm's 25-line `ErrorMessageBuilder` block gone, five condition gates routed → NEW owner `AnalyzerBooleanConditions.nl` (211 lines, 9 members); 9 non-condition `IsBoolType` calls rerouted direct to `BuiltInTypes.Is` | `IsBoolType` was a private C# ALIAS for an already-N#-owned answer, not policy. The condition family is FIVE sites not four — the MATCH GUARD (:10467) uses assignability, not identity. A pure SINK needs no driver/state/program counter — the arc's first | Analyzer.cs 12,768; N# +589 / 1 new file; contracts 2,758→2,772; gate 41m59s all green |
| 017 slice 38 | `a5f034cda` (landed); baseline `ea6335a7b` | `Analyzer.cs` +41/−53 = net −12 (12,838→12,826): `AnalyzeForeachStatement` (27) and `AnalyzeAwaitForeachStatement` (28) deleted, both dispatch arms become routing lines → `AnalyzerLoopSequence.nl` 693→973 (`ForeachStatementRequest`/`State`, `DriveForeachStatement` 44 lines in C#) | Non-blank went 11,332→11,332 FLAT and that is the honest finding: after six prior slices the arms were 43 non-blank lines of replayed operations and the driver replaying them is 43 too. A driver kind that looks shared may not be — `DriveExpressionStatement` kind 5 is the statement LIST walk with the unreachable-code rule; a loop body is a single Statement | Analyzer.cs 12,826; N# +280 lines, 2 types, no new file; contracts 2,746→2,758; gate 36m52s all green |
| 017 slice 37 | `ea6335a7b` (landed); baseline `33808eb97` | `Analyzer.cs` +202/−326 = net −124 (12,962→12,838, decls 571→564): 7 members GONE (`IsSoaColumnMemberAccess` 8, `ReportSoaRowEscape` 11, `ReportSoaRowEscapeIfNeeded` 10, `ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded` 10 + raw 14, `TryGetSoaColumnMemberAccess` 23, `TryGetSoaRecordReceiverType` 25) plus the `_soaColumnMemberAccesses` registry → new `AnalyzerSoaEscape.nl` (258 lines); 147 sites routed; 018's four call-walk gates re-shaped from `out` params to a nullable-returning probe without touching their policy | The column gate is a SYNTACTIC probe no `TypeInfo` can answer (a column reads as its plain array type), so the registry — a reference-identity `HashSet<MemberAccessExpression>` — had to move with it. Neither gate is driver-answerable, so the whole test moves into the sink. Kind numbering keeps GAPS at 2 and 3 rather than closing up: 40-odd contracts pin kinds by value | Analyzer.cs 12,838; all 4 drivers shrank, 2 to a single line; 95,843 driver round trips gone; contracts 2,723→2,746; gate 33m45s green |
| 017 slice 36 | `33808eb97` (landed); baseline `f74037b50` | `Analyzer.cs` +41/−273 = net −232 (13,194→12,962, decls 565→556): the whole loop-sequence element-type family — ELEVEN members / 211 lines at :3721–:3941, not the brief's five/128 — plus the `yield` arm → new `AnalyzerLoopSequence.nl` (708 lines, 3 types, 28 members) with `DriveYieldStatement` (34 lines) in C#; `TryGetGenericLoopSequenceElementType` was a 12-line C# wrapper over `LoopSequenceTypeFacts` and DIED rather than moved | The slice-35 brief undercounted by 83 lines and was wrong twice more: the family is NOT diagnostic-free (2 report members) and NOT a pure function of a type (it reads scope stack, declaration context, type resolver, ambient context). `YieldStatementState` must capture `DeclaresGenerator` AT ENTRY because a lambda in the yielded expression opens a nested function context while the walk is suspended | Analyzer.cs 12,962; N# +708 / 1 new file; contracts 2,686→2,723 (+37); gate 32m25s green |
| 017 slice 35 | `f74037b50` (landed); baseline `6acfe959e` | `Analyzer.cs` +87/−159 = net −72 (13,266→13,194, decls 566→565): the expected-type (target-typing) FIELD and its 16 save/restore idioms across 12 members deleted, plus `AnalyzeReturnStatement` (78) → `AnalyzerAmbientContext.nl` 560→918 (`ReturnStatementRequest`/`State`, `EnterExpectedType`/`EnterExpectedTypeIfProvided`/`ExitExpectedType`); C# gains only `DriveReturnStatement` (34 lines, 11 of them doc) | `Analyze`'s prologue NEVER resets the target-typing slot (it is only written inside a matched pair), so `BeginAnalysis` deliberately does not either. Eleven idioms set unconditionally, FIVE set only when there is something to ask for — leaving the slot alone is SEMANTIC, nulling it would change what `default`, `new()`, a lambda and a negative literal resolve to | Analyzer.cs 13,194; N# +358 / 2 types / 16 members; contracts 2,648→2,686 (+38); gate 31m38s (re-run) green |
| 017 slice 34 | `6acfe959e` (landed); baseline `9f8ae278f` | `Analyzer.cs` +55/−325 = net −270 (13,536→13,266, decls 577→566): the EIGHT ambient function-and-loop fields, all seven save/restore idioms, and four whole members (`AddReturnValueMismatchError` 50, `AddExpressionBodyReturnError` 35, `FormatReturnValueMismatchMessage` 13, `ReportControlTransferOutOfFinally` 19) plus the `break`/`continue` arms → new `AnalyzerAmbientContext.nl` (560 lines, 2 types, 38 members). NOT ONE C# member added | Every `Enter` hands its snapshot BACK to the C# caller instead of pushing an internal stack: only the block-bodied lambda restores from a `finally`, the other six restore straight-line and are skipped on a throw — an internal stack would silently make six idioms exception-safe. `AnalyzeFunctionDeclaration` sets `_currentReturnType = null` on exit, NOT the saved value; that asymmetry is preserved verbatim | Analyzer.cs 13,266; N# +560 / 41 contracts; contracts 2,607→2,648; gate 30m44s green |
| 017 slice 33 | `9f8ae278f` (landed); baseline `944adad72` | `Analyzer.cs` +60/−263 = net −203 (13,739→13,536, decls 540→530): FOURTEEN members / 257 lines (the assert + expression-statement cluster and its whole private closure — discard walk, must-use closure, both NL313 reporters, `DescribeExpressionForDiagnostic`, assert-throws NL202) → new `AnalyzerExpressionStatements.nl` (925 lines, 3 types, 30 members) + a 35-line `DriveExpressionStatement` and three one-line routers, so the statement dispatch did not change | The slice-32 brief named 4 members / ~60 lines; the real closure is 14 / 257 and the stay-behind re-entry set is 7, not 3. The `_errors.Count` guard is NOT a driver-visible operand — the sink already owns the list, so `AnalyzerDiagnosticSink.ErrorCount` keeps the guard inside N# and removes a driver kind | Analyzer.cs 13,536; N# +925 / 81 contracts; contracts 2,526→2,607; gate 31m35s green |
| 017 slice 32 | `944adad72` (landed); baseline `3d1743c9d` | `Analyzer.cs` +24/−160 = net −136 (13,875→13,739, decls 495→492): `AnalyzeTupleDeconstruction` and its whole private closure — FIVE members / 150 lines, not the brief's one member / 87 — → `AnalyzerVariableDeclaration.nl` 467→923; `AnalyzeTupleDeconstruction` survives as a one-line router so the dispatch call site :3191 did not change; slice 31's `DriveLocalDeclaration` now serves both arms unchanged but for capturing the kind-3 boolean | There is NO `Deconstruct`-method resolution in the arm — the mandate's anticipated overload-machinery fork does not exist; a source is deconstructable iff it resolves to `TupleTypeInfo`, a `GenericTypeInfo` named `ValueTuple`, or a `ReflectionTypeInfo` over a constructed `System.ValueTuple\`N`. The stay-behind re-entry set is slice 31's five kinds with ZERO additions | Analyzer.cs 13,739; N# +456 lines, 18→33 members; contracts 2,472→2,526 (+54); gate 34m06s green |
| 017 slice 31 | `3d1743c9d` (landed); baseline `85d0b5975` | `Analyzer.cs` +35/−106 = net −71 (13,946→13,875): `AnalyzeVariableDeclaration` (:3725–:3840, 116 lines) → new `AnalyzerVariableDeclaration.nl` (467 lines, 3 types, 18 members) + a 35-line `DriveLocalDeclaration` (5 kinds); the member itself became the driver so NEITHER call site changed (dispatch :3179 and `AnalyzeUsingStatement` :4820) | The arm inventory, not the brief, chose the target: scored on stay-behind re-entries, this arm has the fewest (5) and the largest body (116). Kinds 1/3/4/5 — analyse an expression, probe the direct-column escape, declare a symbol, record it in the semantic model — are the four operations nearly EVERY statement arm replays, so the territory has one reusable driver | Analyzer.cs 13,875; statement walker 1,049→968 lines; contracts 2,404→2,472 (+68); 27,386 corpus entries, 96.2% unannotated |
| 017 slice 30 | `85d0b5975` (landed); baseline `1ad50517f` | `Analyzer.cs` +58/−919 = net −861 (14,807→13,946): the whole definite-assignment / null-state / narrowing family — 24 members, 857 lines in three clusters, plus the `_suppressNullabilityFlowType` flag and `_reportedNullabilityDiagnostics` dedup log — → three new owners `AnalyzerDefiniteAssignment.nl` (761), `AnalyzerNullFlow.nl` (274), `AnalyzerFlowNarrowing.nl` (253); `IsNullableType` a bonus deletion (its only caller was the constructor arm) | The FIRST family in the arc that moved WHOLE — zero drivers, zero requests, zero `Supply` — and the reason is structural: a flow analysis threads a STATE through the tree instead of asking the tree what things MEAN, so it never needs an answer it does not already hold. Closure scan found exactly ONE outbound call that stays behind (`Error`, the sink) | Analyzer.cs 13,946; N# +1,288 / 3 owners / 149 contracts; contracts 2,255→2,404; gate 32m29s green |
| 017 slice 29 | `1ad50517f` (landed); baseline `7df2723a9` | `Analyzer.cs` +48/−222 = net −174 (14,981→14,807): `AnalyzePattern` (:5869–:6076, 208 lines, the 13-arm walk) and the slice-28 driver `AnalyzePropertyPatterns` (28) → new `AnalyzerPatternAnalysis.nl` (759 lines, 3 types, 26 members); C# keeps a 32-line zero-policy request loop with a five-case switch | This walk SUSPENDS and RESUMES WITH THE ANSWER (unlike slice 28's answer-free loop) on two counts: a literal pattern's second step takes the type its first answered, and a relational pattern's step COUNT changes because a TRUE row-escape deletes both the column step and the comparability judgement. Self-recursion needs no stack — a nested pattern is a kind-5 request and the driver re-enters with a FRESH state; deepest nesting in the estate is THREE | Analyzer.cs 14,807; pattern family closed: 31 C# members, 15,966→14,807 = −1,159 over slices 25–29; contracts 2,205→2,255; gate 30m56s green |
| 017 slice 28 | `7df2723a9` (landed); baseline `8a6398106` | `Analyzer.cs` +26/−58 = net −32 (15,013→14,981): `AnalyzePropertyPatterns` (:6073–:6137, 65 lines, one call site) and its inline NL503 → new `AnalyzerPropertyPatternBinding.nl` (260 lines, 3 types, 7 members) + a 17-line loop; ALL 26 added C# lines mechanical, and NO new C# member at all (not even a `Create…` factory — the owner holds nothing the SCC rebuild replaces) | The schedule is answer-INDEPENDENT (PRE == ACTUAL == POST on all 103 entries) but the DELIVERY cannot be hoisted: `_errors` is one ordered list and 8 of 82 nested analyses report, so a hoist would invert report order. The resumable mechanism is used for REPORT ORDER, not because the count is unknowable | Analyzer.cs 14,981; N# +260 / 30 contracts; contracts 2,175→2,205; gate 30m11s green |
| 017 slice 27 | `8a6398106` (landed); baseline `c824e6cb6` | `Analyzer.cs` +17/−160 = net −143 (15,156→15,013): FOUR members / 134 lines (`IsPatternPossible` 56, the three `ContainsParserErrorPlaceholder` overloads 58/18/2) plus the two inline NL506 blocks (16) → new `AnalyzerPatternReachability.nl` (605 lines, 2 types, 11 members, one of them the STATIC `AnalyzerParserErrorPlaceholders`); all 17 added C# lines mechanical | The slice-25 counter measured only HALF the family: `pat.impossible = 0` counted the type-pattern site alone, and the `is`-EXPRESSION site DOES report in the corpus (NL506 ×3 in `examples/17-issue-tracker/backend/Endpoints.nl`). `Linter.cs`'s near-duplicate placeholder walk STAYS — routing it onto the owner would newly see placeholders inside `alloc`, `stackalloc` and every pattern, a behaviour change dressed as de-duplication | Analyzer.cs 15,013; N# +605 / 41 contracts; contracts 2,134→2,175; gate 29m49s green |
| 017 slice 26 | `c824e6cb6` (landed); baseline `19b523c4c` | `Analyzer.cs` +12/−194 = net −182 (15,338→15,156): NINE members / 174 lines (the list-pattern shape probe — `TryGetListPatternElementType` 26, `TryGetReflectionListPatternElementType` 47, `GetListPatternShapeTypes` 14, `IsIndexableGenericListPatternType` 2 — and the relational comparability five — `ValidateRelationalPattern` 22, `IsRelationalPatternComparableType` 42, `ReportRelationalPatternTypeMismatch` 13, `IsNullableRelationalPatternType` 6, `IsEqualityPatternOperator` 2) plus the inline 9-line NL504 block → new `AnalyzerPatternShapes.nl` (361 lines, 14 members) | The estate's documented "MLC-safe" `FullName` idiom would have SILENTLY CHANGED BEHAVIOUR: `System.Text.StringBuilder` loaded through a `MetadataLoadContext` is list-shaped by NAME but not by `typeof(int)` REFERENCE identity, turning an NL504 into a successful match. The `typeof` test is preserved verbatim. Also corrects slice 25's code map — `PatternTypeMismatch = 504`, `GuardNotBoolean = 505`, `ImpossiblePattern = 506` (the map was one place too high) | Analyzer.cs 15,156; N# +361 / 34 contracts; contracts 2,100→2,134; gate 30m35s green |
| 017 slice 25 | `19b523c4c` (landed); baseline `19a3579ce` | `Analyzer.cs` +24/−652 = net −628 (15,966→15,338): FIFTEEN members / 588 lines — the whole exhaustiveness decision (`CheckMatchExhaustiveness` 175, `CheckEnumMatchExhaustiveness` 95, `IsUnionCaseCoveredByPatterns` 82, `CheckNullableMatchExhaustiveness` 60, `CheckAnonymousUnionMatchExhaustiveness` 45, `TryResolveDeclaredUnionType` 31 and the eight pure predicates) plus the `MatchKeywordLength` const and the now-unused `using System.Buffers` → `AnalyzerExhaustivenessSelector.nl` 60→231 and new `AnalyzerMatchExhaustiveness.nl` (838); `AnalyzeMatchExpression`'s 38-line tail becomes ONE call | The corpus oracle covers the SILENT path only: 96 matches reach the dispatch and NOT ONE of the 71 targets reports a single exhaustiveness diagnostic, with zero anonymous-union and zero nullable matches anywhere. So the reporting core could NOT be split from the pure facts — the facts have no independent observable. This set the whole five-stage arc plan (25→29) | Analyzer.cs 15,338; N# +1,009 across 2 owners; contracts 2,059→2,100 (+41); gate 31m16s green |
| 017 slice 24 | `19a3579ce` (landed); baseline `889528b52` | `Analyzer.cs` +90/−182 = net −92 (16,058→15,966): `AnalyzeCall` (:8600, 172 lines) and both `AnalyzeSyntheticCallReceiver` overloads (190 source lines total) → new `AnalyzerCallAnalysis.nl` (704 lines, 3 types); C# keeps a 64-line zero-policy driver over 14 step kinds plus one `CreateCallAnalysis()` factory | The banked recommendation — a hoisted count-exact schedule — was REFUTED by counterexample: an overload group holding a receiver-style GENERIC candidate and a plain candidate that WINS fires the receiver ONCE, so the count is a function of an answer the walk does not have until it has suspended. The receiver TRIPLE is user-visible: one `Bad(1,2).Tag("x")` receiver prints the same NL401 12 times in `nlc build`, the nested form 48, while `check --json` distincts to one | Analyzer.cs 15,966; overload arc CLOSED; contracts 2,046→2,059 (+13); gate 31m42s green |
| 017 slice 23 | `de8b03aa6` (landed); baseline `47e4b8f44` | `Analyzer.cs` +36/−446 = net −410 (16,468→16,058): SIX members / 425 lines (`ResolveMember` 279, `TryResolveExtensionMethod` 53, `TryResolveReflectionPropertyOrField` 41, `FindExternalExtensionMethods` 41, `GetReflectionMemberFlags` 7, `GetLoadableTypes` 4) → `AnalyzerMemberResolution.nl` 210→671 and `AnalyzerExtensionMethodResolution.nl` 87→250; the 319-line staged blueprint `systems-language-closeout/phase-b-member-resolution-contracts.md` DELETED, its contracts now in the project | The lifetime decisions phase A recorded were applied and pinned: `_extensionMethods`/`_usingNamespaces`/`_mlcAssemblies` cross BY REFERENCE (contracts mutate them after construction and watch the answer change) while `_currentTypeName` crosses as a PARAMETER (a held field could not give three answers for three containing types). `_memberResolution` stops being `readonly` and joins the SCC rebuild list at all 3 sites | Analyzer.cs 16,058; 6,268 differential cells byte-identical (18 event answers); contracts 2,019→2,042 (+23); gate 104 PASSED / 1 environmental ✗ |
| 017 slice 22 | `47e4b8f44` (landed); baseline `89c4dc265` | `Analyzer.cs` +36/−130 = net −94 (16,562→16,468): SEVEN members / 104 body lines (`TryResolveSourceObjectMember` 37, `ResolveDeclaredFunctionMember` 28, `IsExtensionReceiverApplicable` 15, `CreateSoaIntrinsicFunction` 13, `CanResolveFunctionMemberFromTypeInfo` 7, `IsFunctionTypeParameter` 2, `TryGetSoaColumn` 2) → new `AnalyzerExtensionMethodResolution.nl` (87) and `AnalyzerMemberResolution.nl` (200), 19 call sites routed; plus PHASE A — 46 lines of catalog data in `ColumnarExternalBindingPlans.nl` (`System.Reflection.EventInfo`, `Assembly.GetTypes()`, `Type.GetEvent`, the two accessor overloads, three EventInfo getters) | The re-verification OVERTURNED the premise: neither target closes at the pinned toolset. `Assembly.GetTypes()` is unmodeled and `GetExportedTypes` is NOT a substitute (it answers a strictly smaller set — declared > exported on `System.Private.CoreLib` — so it would silently drop every extension on an INTERNAL static class). `System.Reflection.EventInfo` is not on the supported runtime-type surface at all, and it is what makes a .NET event resolve to a `ReflectionEventInfo` rather than the private backing FIELD. Slice 21's closure extraction was INCOMPLETE — it omitted six bare calls | Analyzer.cs 16,468; 1,727 differential cells byte-identical; contracts 2,013→2,019 (+6); gate 32m41s green; STOPPED at the repin wall |
| 017 slice 21 | `89c4dc265` (landed); baseline `d4d383d79` | `Analyzer.cs` +24/−216 = net −192 (16,754→16,562): `FinalizeBoundReflectionCall` (141) and `ValidateFinalReflectionSuppliedArgument` (62) — 203 body lines — → new `AnalyzerReflectionCallFinalizer.nl` (136) plus 308 lines on `AnalyzerReflectionArgumentBinder`; C# keeps a 19-line driver and NO new field, construction site or rebuild-list entry | A static schedule is IMPOSSIBLE and a loop inversion UNSOUND, both by counterexample: an earlier lambda's ANSWER changes a later lambda's expected signature (`Join`, `GroupBy`, `SelectMany`), and 91 of 173 lambda analyses ran against a signature differing from the FINAL bindings — so neither an up-front schedule nor an end-of-walk recomputation reproduces the loop. Phase two is FROZEN (`MUT=N` in 13,070/13,070). The same lambda is analysed twice per candidate and the second answer is DISCARDED — `validatedArgumentTypes` is written five times and read ZERO | Analyzer.cs 16,562; 57,430 protocol rows byte-identical over 15,143 finalisations; 125 assemblies byte-identical; contracts 2,006→2,013; gate 31m29s green |
| 017 slice 20B | `d4d383d79` (landed) | 5 whole C# members deleted, 129 body lines: `PreBindReflectionMethod` 86, `ConvertReflectionSuppliedArgumentType` 16, `GetOpenReflectionSignatureMethod` 13, both `IsExpressionTreeLambdaTarget` overloads 14. `Analyzer.cs` 16,885→16,754 (14,888→14,777) → `AnalyzerReflectionArgumentBinder` +258 (with `ReflectionPreBoundCandidate` replacing a 9-field C# tuple), `AnalyzerReflectionTypeConversion` +27, `AnalyzerFunctionTypeFactory` +43 | The expression-tree predicate landed as STATICS taking context+conversion as PARAMETERS, not fields: `_clrTypeConversion` is replaced on every toolset rebuild and on `Dispose` while `AnalyzerFunctionTypeFactory` is built once — a field would be stale by construction. N# now owns reflected overload SELECTION end to end | 2,895 differential cells, 0 mismatches, md5 `67d809ac1af5d634c1727fe2fa15d8ef` both trees; ORACLE_DIFFS 0 / 859 diags / 70 targets; 112 assemblies byte-identical; contracts 1,997→2,006; gate 1,880s |
| 017 slice 20 phase A | `c430a30d9` + `7665e48e2` | ZERO production C# and ZERO N# members: 27 lines of catalog DATA in `ColumnarExternalBindingPlans.nl` — a `GetInstanceCallPlan` `System.Type` row for `GetMethods(BindingFlags)` → `MethodInfo[]`, and a `GetStaticMemberPlan` row admitting the WHOLE `BindingFlags` enum. `Analyzer.cs` byte-for-byte untouched | Slice 19 MIS-ATTRIBUTED the blocker: the missing piece was not the call row but that `BindingFlags` had no `GetStaticMemberPlan` row, so no expression naming its members could be typed and `TryGetPlannedExternalCall` computed an EMPTY argument type name — one decline site (`emit.call.instance-member-unmodeled`) serves both causes. A CONTROL (`Type.GetProperty(string,BindingFlags)`, a row present for many slices, declining identically) proved it before any guessing. Slice 19's three "enum-local capability facts" were never planner surface and are all gone | contracts 1,991→1,994; staged end-to-end contracts 3/3 vs fresh CLI; audit 18/18; manifest untouched at 391; no IL sweep owed (packaged toolset carries no rows until repin) |
| 017 slice 19 | `e01a772ef` (landed); baseline `74cda4405` | 6 whole C# members + 1 field deleted, 123 body lines: `ReportNoMatchingReflectionOverload` 38, `ReportMethodGroupUsedAsValue` 28, `TryGetNSharpMethodGroupArgumentName` 20, `ReportNoMatchingReflectionMethodGroupOverload` 15, `HandleUnboundReflectionCall` 11, `IsUnboundCallableReference` 11, plus `_reportedCallableReferenceDiagnostics`. `Analyzer.cs` 16,995→16,885 (14,981→14,888) → new `AnalyzerReflectionCallReporter.nl` (302 lines, 2 classes, 11 members) | The NL411 dedupe log had to become its OWN tiny owner (`AnalyzerCallableReferenceReportLog`, constructed once): the reporter holds `_assignabilityFacts`, which is REPLACED on every toolset rebuild, so an owner that also owned the log would forget what it had said and report the same method group twice. Key is `line:column:name`, injective because `int.ToString()` cannot emit a `:`. Slice 19's "one catalog row" diagnosis was later OVERTURNED by slice 20 phase A — the real blocker was the missing `BindingFlags` static-member row | 11,286 differential cells / 18,750 transcript lines / 0 mismatches, md5 `f8d864d334c8cd83ee9209a1f83766b1`; 7,464 sink diagnostics (NL402 7,200 / NL411 264); ORACLE_DIFFS 0 / 326 diags / 70 targets; 112 assemblies byte-identical; contracts 1,968→1,991; gate 1,928s |
| 017 slice 18 | `74cda4405` (landed); baseline `80087951f` | 17 whole C# members deleted, 625 body lines (`ValidateSyntheticFunctionCall` 153, `ValidateSyntheticGenericConstraints` 74, `ValidateSoaSyntheticFunctionCall` 59, `ValidateSoaWrapColumnArguments` 48, `ReportNoMatchingSyntheticNSharpOverload` 44, `ValidateSyntheticNonNegativeIntArgument` 43, `HasParameterlessConstructor(TypeInfo)` 32, +10 more). `Analyzer.cs` 17,617→16,995 (15,532→14,981) → `AnalyzerSyntheticCallValidator.nl` (993 lines, 2 classes, 22 members) + `AnalyzerConstantExpressionFacts` + 54 lines on `AnalyzerCallableReferenceFacts` + `AnalyzerDiagnosticSink.ReportBuilt` (8) | Rich `ErrorMessageBuilder` reports and detail-only reports reached `_errors` by TWO doors in C#; they now reach it by ONE (`ReportBuilt` appends to the same list `Report` writes to), and the two-value rich precondition (file path AND the offending line's text) is stated once in `TryGetRichContext` so three report sites cannot disagree. The `ParameterTypes == null` divergence in the count-exact receiver hoist was PROVED unreachable (600/600 invariant rows, `score=-1`), not assumed | 83,754 differential cells / 0 mismatches / 72 identical throws, md5 `83652e7af443b6e3a007cd4e1e6c5ad8`; 14,880 sink diagnostics over NL401/402/208/202/301; 160 build targets 4,677 lines identical; ORACLE_DIFFS 0 / 326 diags; 112 assemblies byte-identical; contracts 1,932→1,968; gate 2,003s |
| 017 slice 17 | `80087951f` (landed); baseline `1c3aa4597` | 4 whole C# members deleted, 290 body lines: `TryInferSyntheticGenericBindings` 87, `BindSyntheticNSharpCall` 78, `TryGetSyntheticCallMatchScore` 78, `GetSyntheticGenericConstraintDiagnosticSpan` 47. `Analyzer.cs` 17,879→17,617 (15,757→15,532) → `AnalyzerSyntheticCallWalk.nl` (520 lines, 1 class, 8 members); C# keeps two expression-bodied `AnalyzeSyntheticCallReceiver` overloads | The measurement OVERTURNED option (a) (read the recorded/cached receiver type) by counterexample: for `Read.Tag("mg")` the semantic model holds `FunctionTypeInfo` while the walk's own analysis answers `unknown` and IS THE SOLE PRODUCER of the NL411 — caching would have returned the wrong type AND DELETED a user-visible diagnostic. Re-analysis is not idempotent in general (78 corpus REPEATs answered differently). Also: `bool + out int score` became a single `int` with -1 = "does not apply", because ZERO is a real score | 40,320 differential cells / 0 mismatches, md5 `7fa7e56690764deb751c933dbe610f74`; 1,610 sink diagnostics; corpus probe 607,320 analysis rows, ZERO re-entries; ORACLE_DIFFS 0 / 857 diags / 70 targets; 112 assemblies byte-identical; contracts 1,913→1,932; gate 1,857s |
| 017 slice 16 | `1c3aa4597` (landed); baseline `454505582` | 35 whole C# members deleted, 501 body lines + 7 lines of dead N#: the 32-member span sub-tree (426 lines) plus the source binder's whole reporting family (`TryBindSyntheticFunctionArguments` 33-line driver, `ReportSyntheticMissingArgumentBindingError`, `ReportSyntheticArgumentBindingError`). `Analyzer.cs` 18,371→17,879 (16,181→15,757); 159 rewritten refs (127 `_spans.`, 27 `AnalyzerDiagnosticSpanFacts.`, 5 `_syntheticCallReporter.`) → `AnalyzerDiagnosticSpans.nl` (892 lines, 3 classes, 38 members) + 85-line `AnalyzerSyntheticCallReporter`; `ParserDiagnosticSpan.nl` DELETED | Slice 15's claim that "an N# owner returns a class, so all 113 sites change shape" is FALSE, proven before a line was written: C# positional deconstruction binds to any accessible instance `void Deconstruct(out,out,out)` and N# emits exactly that, so every `var (line, column, length) = ...` site survived verbatim — a callee RENAME, not a shape change. That is what converted the blocked reporting arm from "cannot move" to mechanical | 23,580 differential cells / 0 mismatches / 286 distinct answers, md5 `3965df575304bf27e21fe45e6348d291` (same md5 before and after the analyzer fixes); ORACLE_DIFFS 0 / 857 diags / 70 targets; 45 span-fixture diags across 13 widths; 112 assemblies byte-identical; contracts 1,883→1,913; gate 1,827s |
| 017 slice 15 | `454505582` (landed); baseline `2389b6aeb` | 8 whole C# members deleted + the filler's walk = 424 body lines (`CollectNSharpTypeParameterBounds` 98, `TryGetSyntheticArgumentComparisonTypes` 62, `GetSyntheticGenericParameterCost` 46, `TryComputeNumericLub` 44, `ApplyNSharpGenericBindings` 32, `ComputeLeastUpperBound` 28, `TryMatchGenericRefAgainstExternalType` 21, `GetCallTargetName` 9); `TryBindSyntheticFunctionArguments` 117→33 (a reporting DRIVER replaying an N#-produced ordered failure list). `Analyzer.cs` 18,807→18,371 (16,577→16,181) → `AnalyzerSyntheticCallBinder.nl` (885 lines, 5 classes, 18 members) | Two walls recorded as MEASUREMENTS, not crossings: (1) the walk re-entry — `TryInferSyntheticGenericBindings`' one `AnalyzeExpression(memberAccess.Object)` is per-CANDIDATE behind five early-outs and its guard reads the per-candidate `GetSyntheticParameterStartIndex`, so no hoist is count-exact and a provider is a callback; (2) the diagnostic-span wall. `TryGetSyntheticArgumentComparisonTypes`' two `out`s became a `SyntheticArgumentComparison` VALUE because C# encoded "does not match" and "matches but carries no information" both as false-plus-nulls, and collapsing them would have eliminated candidates the arity tables had admitted | 22,856 differential cells (half MetadataLoadContext) / 0 mismatches / 346 distinct answers, md5 `26a0bd793c7ea980b30cd070e0fb37d8`; 1,182 NL402 rows; ORACLE_DIFFS 0 / 832 diags / 49 targets; 112 assemblies byte-identical; contracts 1,847→1,883; gate 1,797s |
| 017 slice 14 | `2389b6aeb` (landed); baseline `6bc0e970f` | 11 whole C# members + 4 bound-argument records deleted, 697 body lines (`TryBindReflectionArguments` 179, `TryScoreReflectionSuppliedArgument` 89, `PopulateTypeInfoBindingsFromType` 83, `TryBindMethodGroupToReflectionDelegate` 68, `CreateDelegateSignatureFromOpenType` 66, `PopulateReflectionBindingsFromTypeInfo` 63, +5 more). `Analyzer.cs` 19,510→18,807 (17,182→16,577) → `AnalyzerReflectionArgumentBinder.nl` (1,101 lines, 5 classes, 22 members). Also LANDED a language capability: enum bitwise OR/AND/XOR across `ColumnarNumericFacts.IsBitwiseEnum`, `ColumnarPrimitiveBinaryPlanner.TryAppendBitwise` and `ColumnarCodePlanExecutor.BinaryBitwiseResultType` (~90 lines, 2 contracts) | The enum-OR gap bisected into THREE independent facts, only one of them the operator: an admitted external enum member read into a local is OK; `a \| b` over two enum PARAMETERS declines uniformly (source enums too); `BindingFlags.Public` alone declines for a missing `GetStaticMemberPlan` row. The non-mechanical part is the RESULT TYPE — an enum is not another row in the promotable table (the CLR already carries it as its underlying integral type), so folding enums in would produce the right instruction and the WRONG type. Opcode selector and schema validator must read the rule from ONE place | 12,866 differential cells (7,439 MetadataLoadContext) / 0 mismatches / 433 distinct answers, md5 `70a6fabaaee134002033242ec20a5be6`; ORACLE_DIFFS 0 / 49 targets; FIXTURE_DIFFS = 2, both the intended capability gain; 95/95 assemblies byte-identical; contracts 1,827→1,847; gate 1,804s |
| 017 slice 13 | `6bc0e970f` (landed); baseline `c86ac6db4` | 35 whole C# members deleted, 454 body lines: the whole overload scoring/applicability kernel (`TryMatchReflectionParameter` 53, `TryFindCompatibleGenericType` 38, `FormatSyntheticParameterSignature` 32, `GetNSharpMatchScore` 24, `TryGetReflectionParamsElementType` 24, +30 more) and the NL402 signature formatters. `Analyzer.cs` 19,993→19,510 (17,584→17,182); 70 rewritten refs (57 `AnalyzerOverloadFacts.`, 9 `_overloadScoring.`, 4 to `NullabilityMetadataReflection.FormatType`) → `AnalyzerOverloadScoring.nl` (986 lines, 2 classes, 35 members) | The arc OPENS here and sets the staged plan (peripheral pure facts → state carriers → reporting core, the `ResolveType`-arc precedent). Overload resolution + reflection binding is ONE family with FOUR entry points. The 12C owner-split discipline is extended: pure statics in `AnalyzerOverloadFacts`, collaborator-backed members in `AnalyzerOverloadScoring`, which is REBUILT at the same two points the assignability SCC is; an owner's fields never change after construction. `GetReflectionMemberFlags` (7 lines) NOT taken — an external-enum bitwise OR declines, and writing it as an int-and-cast-back would trade a readable table for a magic number | 70,758 differential cells (36,993 MetadataLoadContext) / 0 mismatches / 34 identical throws / 422 distinct answers, md5 `0f0dbdb3ad513f2040a9182a9332501f`; ORACLE_DIFFS 0 / 49 targets; 30 fixtures 105 diags FIXTURE_DIFFS 0; 95/95 assemblies byte-identical; contracts 1,787→1,827; gate 1,828s |
| 017 slice 12C | `c86ac6db4` | 24 whole C# members deleted, 842 body lines + the `_activeImplicitConversions` state field: the whole assignability SCC (`IsAssignable` 147, `TryGetDelegateSignatureConversionScore` 87, `IsSubtypeOf` 77, `IsLambdaAssignableToDelegate` 52, `HasImplicitConversion` 44, ...), the four `CreateFunctionTypeInfo*` members and both reflection conversions, plus a 9-member measured recut (131 lines). `Analyzer.cs` 20,857→19,993 (18,329→17,584); 105 rewritten sites → `AnalyzerAssignability.nl` (857), `AnalyzerFunctionTypeFactory.nl` (663), `AnalyzerReflectionTypeConversion.nl` (358) | 12B's `Func<Type, object>` boundary cast is GONE — the override crosses as DATA (`AnalyzerReflectionTypeOverride`). `ApplyReflectionBindings` HAD to come too: three of the four override sites closed over a CONDITIONAL, not a plain call, and the second arm is the `Bound` rule, unrepresentable without the binding walk. The two rules are NOT interchangeable — the override walk builds a `GenericTypeInfo` over converted arguments while applying bindings first yields a closed CLR type converting as ONE reflected instantiation. A PRE-EXISTING unbounded recursion (`IsAssignable(Shape <- Money)`) stack-overflows IDENTICALLY in both trees: the guard bounds `HasImplicitConversion` but nothing bounds the ROOT's re-entry through the conversion's return type — recorded, not fixed | 43,616 differential cells (21,808 MetadataLoadContext) / 0 mismatches / 121 identical throws / 316 distinct answers, md5 `dd715d402b13900fd229715a997ff8d9`; ORACLE_DIFFS 0 / 49 targets; 73/73 assemblies byte-identical; contracts 1,747→1,787; gate 908s |
| 017 slice 12 stage B | `cff81c09b` | `src/NSharpLang.Compiler/NullabilityMetadata.cs` DELETED WHOLE (251 lines / 207 non-blank) → `NullabilityMetadataReflection.nl` (449 lines, 1 class, 32 members: 12 public entries + 20 file-private helpers); all 27 call sites routed as pure RENAMES (`Analyzer.cs` 17/17 with not one added line, `CodeIntelligenceService.cs` 4, `CompletionEngine.cs` 3, tests 3). ZERO C# lines added anywhere. Two C# test methods MIGRATED to 14 native contracts. Authorised split taken: steps 2-3 (645 lines) became slice 12C | The differential caught what reading would not: testing `[NotNullWhen]`'s constructor argument with `argument.get_ArgumentType() == typeof(bool)` is WRONG UNDER A MetadataLoadContext — `ArgumentType` is then a PROJECTED `System.Boolean` that is not `typeof(bool)` while `Value` is still a live boxed CLR bool, silently dropping the flow prefix from every MLC-loaded signature (18 mismatching cells, zero in the live-reflection half). The fix is the value test: `value.Equals(true) \|\| value.Equals(false)` IS `value is bool`. Also: THREE dead C# arms (the `ConvertType(Type, Func<Type,TypeInfo>?)` overload and the `typeOverride` arms of `ConvertProperty`/`ConvertField`) had ZERO callers and were deliberately NOT ported | 33,479 differential cells (4,701 MLC) / 0 mismatches / 8 identical throws, md5 `3965010fd33a5a99bc1f97bf630bcedb` both columns; ORACLE_DIFFS 0 / 49 targets; 72/72 assemblies byte-identical; contracts 1,733→1,747; suite 3,194→3,192 (exactly the two migrated methods); gate 859s |
| 017 slice 12 stage A | `513ba36d0` | ZERO C# moved: a CAPABILITY slice. One file, `ColumnarExternalBindingPlans.nl` +75/−0 — five canonical→runtime rows in `TryGetRuntimeTypeName`, five literal rows plus ONE computed clause in `IsSupportedRuntimeTypeName`, one `MatchesOwner` enum row in `GetStaticMemberPlan` — putting `NullabilityInfoContext`, `NullabilityInfo`, `NullabilityState`, `CustomAttributeData` and `CustomAttributeTypedArgument` on the columnar surface. Stopped at the repin wall as instructed | Admission is catalog DATA, not a kernel wall, and NO CALL PLAN WAS NEEDED — adding one would have been a BUG: `ColumnarDirectCallPlanner`:883 consults `GetInstanceCallPlan` FIRST and a supported plan whose materialization fails is TERMINAL (`plan.Rollback` + `return false`, never falling through), while `ValidatePlanForm` requires `Kind == Call` for a value receiver and the legacy C# host requires `CallVirtual` for an instance call — a plan cannot satisfy both. `CustomAttributeTypedArgument.get_Value` bound ONLY after the 153-line plan block was REMOVED. `ValidatePlanForm`'s `HasExactTypeIdentity` also means a plan can never name a declaring type other than the receiver. `WriteState` was deliberately left OFF the surface rather than admitted "for symmetry" | Every row proven load-bearing BY DELETION; 14-function probe builds AND executes against a fresh CLI; 7/7 staged stage-B contracts; suite 3,194/3,194 zero drift; contracts 1,722→1,726; manifest untouched at 391; no IL sweep owed (packaged SDK unchanged) |
| 017 slice 11 | `6fe719a9f` | 8 whole C# members deleted, 143 lines — the duck arm (`ImplementsDuckInterface` 37, `MethodSignaturesMatch` 25), the ActionResult arm (`IsAspNetActionResultGenericAssignable` 14) and the substitution/owner-resolution closure (`ResolveTypeForSourceOwner` 14, `ResolveTypeWithSubstitution` 16, `GetSourceDeclarationOwner` 15, `ResolveGenericTypeWithSubstitution` 13, `ResolveGenericDefinition` 2); 45 rewritten sites. `Analyzer.cs` 20,993→20,857 (18,440→18,329) → `AnalyzerTypeSubstitution.nl` (163) + `AnalyzerStructuralAssignability.nl` (186) | The coordinator's mandate premise ("every dependency is now N#-owned") is FALSE at this tree, proven by BUILD not inference: `IsAssignable`'s callable-reference arm reaches `CreateFunctionTypeInfoFromDelegate` → `NullabilityMetadata.ConvertParameter`, and `NullabilityInfoContext`/`CustomAttributeData` are OFF the columnar surface. Fork (a) CAPABILITY recommended over (b) PROTOCOL because the duck arm is EFFECTFUL: a re-run can re-emit a diagnostic a first pass already emitted, and across frames a duck evaluation can precede a request, so (b) would need deterministic replay | 12,026 differential cells / 0 mismatches, md5 `926389ecabba4b0cdb8c8831ea82f092`; 230 cells emit a diagnostic, 42 write a new semantic-model record; 43 branch counters over corpus+suite: `blocked.delegate-signature-request` 0/0; ORACLE_DIFFS 0 / 49 targets; 73/73 assemblies byte-identical; contracts 1,699→1,722; gate 857s |
| 017 slice 10 | `b91e4ba02` | 13 whole C# members + 3 gutted bodies + 3 fields deleted, 565 lines — the whole `ResolveType` walk (`ResolveSimpleType(string,int,int)` 118, `ResolveGenericType` 121, `ResolveAnonymousUnionType` 49, `TryResolveDottedNestedType` 26, `ReportSoaRowTypeReferenceIfNeeded` 27, `ResolveType` 23, `ResolveDeclaredType` 21, `ReportInaccessibleMember` 11, ...) plus `_reportUnresolvedTypes`, `_reportedUnresolvedTypeRefs`, `_reportedSoaRowTypeRefs`; `Error`/`Warning`/`GetSourceSnippet` gutted to one-line routes (206/2/38 call sites left untouched). `Analyzer.cs` 21,461→20,993 (18,861→18,441) → `AnalyzerTypeResolver.nl` (714 lines, 23 members) + `AnalyzerDiagnosticSink.nl` (119) | The five-report-site claim of slices 7/9 is TRUE of the NL201/NL207 family and FALSE of the walk — there are TEN (adding NL103 for `var`-as-a-type, NL103 for a SoA `.Row` ref, NL306 duplicate union arm, NL207 over-wide union, NL308 via `ReportInaccessibleMember`). The `_errors` list is passed BY REFERENCE, never owned: the shell's ~218 surviving `Error(` sites and the owner's ten append to the SAME instance, so a diagnostic's position among its neighbours is exact by construction. Dedupe sets are `Dictionary<(Name,Line,Column),bool>` because a tuple-keyed `HashSet` is off the columnar surface while a tuple-keyed `Dictionary` is | 79,911 differential cells / 0 mismatches, md5 `38a9feeebfb89dc97354a3738e88e223`; 9,289 diagnostic rows, 19,906 semantic-model rows, 838 binding rows; ORACLE_DIFFS = 1 (only `checkedFiles` 284→286); 53 fixture runs 238 diags DIFFS 0; 72/72 assemblies byte-identical; contracts 1,675→1,697; GATE INCOMPLETE — VS Code smoke 35/1 (mocha timeout, 19m15s vs 41s) and pack TERMINATED by watchdog |
| 017 slice 9 | `31290556c` | 13 whole C# members + 1 gutted body + 5 fields deleted, 369 lines — the `TryResolveVisibleProjectType` family (46+44+18+12+23+13+10), the source-text/unit provider (`EnumerateProjectSourceTexts` 26, `GetProjectCompilationUnit` 20, `TryGetProjectSourceText` 10) and the namespace members (`GetNamespaceForFile` 25, `GetProjectNamespaces` 23, `ProjectNamespaceExists` 10), plus the five cache fields. `Analyzer.cs` 21,735→21,461 (19,094→18,861) → `AnalyzerProjectDiscovery.nl` (603 lines, 2 classes, 28 members) | The enumeration order is LOAD-BEARING and the two channels DIFFER on duplicates: `AnalyzerDeclarationContext.TryResolveDeclarationInNamespace` REFUSES a duplicate type name inside one namespace (an ambiguity, not a pick) while the function channel and the inaccessible probe take the FIRST match — a first draft contract asserting first-wins for the TYPE channel FAILED, and that failure is what found it. The root corpus target has 47 distinct duplicate pairs (`Main` x42, `Person` x14). There are FOUR caches, not three (`_projectFileNamespaceCache` was never named by slices 7/8) | 46,226 differential cells / 0 mismatches, md5 `720cc579b867b61e52f567eb81a84b26`; 38 InaccessibleMember reports, 20 function-channel hits; ORACLE_DIFFS = 2 (both `checkedFiles` counts); 22 fixtures 51 diags DIFFS 0; 75/75 assemblies byte-identical; contracts 1,651→1,675; gate 852s, VS Code 36 passing |
| 017 slice 8 | `bd11ad61d` | 17 whole C# members + 2 gutted bodies + 2 fields deleted, 403 lines — the `Stack<Scope> _scopes` field and its 51 sites across 35 hosts, plus `Stack<int> _semanticScopeIds` and its `Clear()`; `CheckShadowedDeclaration` 41→14 (only the NL316 report remains), `PushScope`/`PopScope` gutted to one routed call. `Analyzer.cs` 22,050→21,735 (19,366→19,094); 88 routed lines → `AnalyzerScopeStack.nl` (620 lines, 1 class, 36 members) | The two RECORDING walks moved WHOLE because `BindingMap` and `SemanticModel` are themselves N#: the sink is passed as an ARGUMENT (it is REPLACED on every `Analyze`), which is not a callback because no N# code names `Analyzer`. The store is a `List<Scope>` not a `Stack<Scope>` (index-based innermost-first walks, no enumerator) so `Peek`/`Pop`/`GlobalScope` throw EXPLICITLY with the CLR's own messages — the differential caught a trailing period the LINQ `Last()` message does not have, and that was the ONLY mismatch in 12,700 cells | 12,700 differential cells / 0 mismatches, md5 `27f0e299d81066ca6a9aa7de90b0e34b`; 108 throw cells matched by exception TYPE AND MESSAGE; ORACLE 49 targets zero diagnostic diffs (only two `checkedFiles` counts); 10 fixtures 36 diags DIFFS 0; 84/84 assemblies byte-identical; contracts 1,627→1,651; gate 846s |
| 017 slice 7 | `dc65075bf` | 7 whole C# members + 1 inline table + 1 field deleted, 225 lines — `TryResolveExternalType` 41, `TryResolveBuiltInTypeKeyword` 28, `BuildUnresolvedTypeSuggestion` 24, `GetGenericHeadArity` 23, `GetVisibleProjectTypeNamespaces` 23, `TryResolveExactExternalType` 20, `GetKnownGenericHeadArities` 17, the 20-line inline built-in name table, and `_externalTypeCache`. `Analyzer.cs` 22,243→22,050 (19,538→19,366); 29 routed sites → `AnalyzerExternalTypeProbe.nl` (152) + `AnalyzerTypeReferenceFacts.nl` (147) + members on two existing owners | The arc OPENS here with the whole `ResolveType` closure measured and a 5-stage plan recorded. The probe is NEVER rebuilt at the `_wellKnownTypes` mutation points (unlike slice 5/6 owners) because its CACHE IS PART OF THE ANSWER: the bare exported-name scan caches under the BARE spelling and short-circuits the import loop on the next call (measured live at 40/100/9 hits). Two guards measured DEAD (assembly-identity dedupe 0 of 2,326+; using-namespace dedupe 0 of 29,362+) and PRESERVED verbatim, as is the structurally-unreachable using-alias-as-a-type channel | 4,918 differential cells / 0 mismatches / 483 true positives; before/after transcript byte-identical, md5 `892e23a2603e1861102cf60d4d3b7cfd`; ORACLE_DIFFS 0 / 40 targets; 11 fixtures 57 diags DIFFS 0; 64/64 assemblies byte-identical; contracts 1,607→1,627; gate 846s |
| 017 slice 6 | `72ffc3113` | 6 whole C# members deleted + 2 bodies replaced by protocol shells: `IsCollectionType` 61, `IsArrayToSpanAssignable` 18, `CanBindCallableReferenceToExpectedType` 13, `IsReferenceLikeForVariance` 10 (a pure deletion — no caller left), `MayUseDelegateReferenceConversion` 9, `IsDelegateType` 7; `IsKnownGenericTypeAssignable` 45→15 and `IsFunctionTypeAssignable` 31→14, both now zero-classification. `Analyzer.cs` 22,409→22,243 (19,680→19,538); 13 routed sites → `AnalyzerAssignabilityFacts.nl` (408 lines, 2 classes) | `IsAssignable` is ONE strongly-connected component with 8 other members, so the ROOT cannot move until `ResolveType` moves — the duck arm's `MethodSignaturesMatch` makes 128 live `ResolveType` calls that RECORD into the semantic model and REPORT. `IsCollectionType`'s reflection arm had to be gated on `IsGenericType && !IsGenericTypeDefinition`: the original read `Type.GenericTypeArguments` (= `IsConstructedGenericType ? GetGenericArguments() : EmptyTypes`), so using `GetGenericArguments()` without the gate would have handed callers a type PARAMETER as the element type | 420,946 differential cells / 0 mismatches / 0 throws; before/after transcript byte-identical, md5 `d08a772ab66302ed525444685ce02683`; ORACLE_DIFFS 0 / 40 targets; 5 fixtures 26 diags; 64/64 assemblies byte-identical; contracts 1,596→1,607; gate 17m08s |
| 017 slice 5 | `a60260357` | 7 whole C# members deleted, 210 lines — the entire TypeInfo→CLR `Type` conversion funnel: `TryConstructDelegateType` 45, `TryConvertTypeInfoToClrType` 36, `TryConstructKnownGenericType` 35, `TryConvertTypeInfoToClrTypeForBinding` 66 (with doc), `TryConstructRuntimeUnionType` 12, `TryConvertNullableType` 8, `IsJsonTypeInfoGenericName` 3. `Analyzer.cs` 22,608→22,409 (19,848→19,680); 40 routed sites (29+10+1) → `AnalyzerClrTypeConversion.nl` (439 lines, 1 class, 18 members) | `_wellKnownTypes` is NOT readonly — null until `LoadSystemAssemblies`, null again in `Dispose` — and the NULL STATE IS LIVE (it selects the `BuiltInRuntimeClrType` runtime-type fallback). So the owner is REBUILT at exactly those two mutation points rather than captured once or given a setter; its fields stay immutable after construction. This rebuild-not-mutate discipline is the pattern slices 6, 12C and 13 inherit. Slice 3's claim that the funnel is blocked because its arms "recurse into `ResolveType`" was measured FALSE | 1,682 differential cells over 800 TypeInfo shapes / 0 mismatches / 5 cells agreeing on a THROWN exception; before/after transcript 1,170 rows byte-identical; ORACLE_DIFFS 0 / 40 targets; 6 fixtures 39 diags; 64/64 assemblies byte-identical; contracts 1,585→1,596; gate run by COORDINATOR, verdict pending (session hit the no-progress watchdog) |
| 017 slice 4 | `ac389ecac` | 2 C# methods deleted, 20 lines (both `ResolveTypeAlias` overloads); 143 in-class call sites routed to `_declarationContext.ResolveDeclaredAlias`; +5 mechanical C# lines in `DeclareType`. `Analyzer.cs` 22,622→22,608 (19,862→19,848) → +43 lines / 3 members on `AnalyzerDeclarationContext.nl` (82→85 members) | The unification is instance-only: `RegisterDeclaredAlias(filePath, alias)` writes `filesByType[alias]` and NOTHING else. `TryGetCanonicalType`'s `is not AliasTypeInfo` exclusion MUST STAY (adopting the canonical type would replace the `AliasTypeInfo` with its target and change every alias-naming diagnostic) and `RegisterCanonicalType` is NOT reusable (it writes `typesByFile[file][name]`, poisoning the context's own alias resolution). The DELETION LICENCE was measured, not argued: the full suite with the branch probe armed reports `b1=103 b2=0` — the C# `ResolveType` arm of the alias funnel is DEAD across suite, corpus and every fixture | counter flip `aliasSeen=36 b1=0 b2=36` → `b1=28 b2=0`, b2 total 523→0 across 10 targets; ORACLE_DIFFS 0 / 40 targets; FIXTURE_DIFFS = 1, a false positive BEING REMOVED (an NL202 that printed the internal `NSharpLang.Compiler.AliasTypeInfo` as `expectedType`); 64/64 assemblies byte-identical; contracts 1,581→1,585; gate 831s |
| 017 slice 3 | `0dee71b98` | 4 C# units deleted, 271 lines: the nested `internal sealed class WellKnownTypes` (173, the MLC fact bag with its two-probe `Resolve`, required-type throws and lazy `RuntimeUnionOpen`/`RuntimeResultOpen`), `TryGetKnownOpenGenericType` 32, `TryConvertBuiltInTypeInfoToRuntimeClrType` 28, and the inline binding-surrogate table (28→4). `Analyzer.cs` 22,873→22,622 (20,087→19,862); 7 routed sites → `AnalyzerWellKnownTypes.nl` (225 lines, 52 members) + `AnalyzerWellKnownTypeFacts.nl` (212) | A RECUT: the recorded slice-3 target rested on a premise measured FALSE — `ResolveTypeAlias`'s pure branch fires 0 times and its C# `ResolveType` branch 36, because `Analyzer.cs`:369 declares an alias as a FRESH `AliasTypeInfo` while `filesByType` is keyed by reference identity. The two open-generic tables are NOT merged: the surrogate table lacks `Result`, `NSharpLang.Runtime.Result` and both `JsonTypeInfo` spellings, and merging would silently widen the surrogate surface (a `Result<,>` rebuilt with `object` surrogates names a type the program never wrote) | 692 differential cells / 0 mismatches (comparison by value OR THROWN exception type, which pinned a real `TypeLoadException` on `void[]`); end-to-end funnel transcript 146 rows byte-identical before/after; ORACLE_DIFFS 0 / 40 targets; 5 fixtures 37 diags; 64/64 assemblies byte-identical; contracts 1,571→1,581; gate 13m49s |
| 017 slice 2 | `9249b4eb0` (landed); baseline `dfec28f2a` | 8 whole C# `private static` predicates deleted, 66 lines, ZERO C# added: `TryCreateFunctionTypeInfoFromGenericDelegate` 33, `GetFunctionParameterModifier`+`NormalizeDelegateParameterModifier` 13, `IsCallableReferenceType`+`IsMethodGroupReferenceType`+`HasSourceFunctionIdentity` 12, `IsRuntimeDelegateType` 5, `IsSpanTypeName` 3. `Analyzer.cs` 22,938→22,873 (20,139→20,087); 21 routed sites → `AnalyzerCallableReferenceFacts.nl` (148 lines, 7 members) + 9 lines on `AnalyzerConversionFacts` | `IsSpanTypeName` is filed with the CONVERSION family, not the callable one, because its only consumer is `IsArrayToSpanAssignable` — it gates an implicit conversion. The analyzer's span spelling set is a STRICT SUPERSET of `LoopSequenceTypeFacts`'s same-named file-private helper (which matches only the unqualified pair); they were NOT merged and the difference is pinned by contract. An identically-named `GetFunctionParameterModifier` in `CompletionEngine.cs`:751 has an extra `index < 0` guard and was deliberately left alone (a second ratchet row) | 271 differential cells / 0 mismatches, including 9 cells loaded into a real MetadataLoadContext to pin the load-context asymmetry; ORACLE_DIFFS 0 / 40 targets; 4 fixtures 15 diags; 64/64 assemblies byte-identical; contracts 1,561→1,571; gate 13m44s |
| 017 slice 1 | `dfec28f2a` | 7 whole C# `private static` methods deleted, 122 lines, ZERO C# added: `IsReflectionAssignableFrom` + `GetInterfacesSafe` + `GetBaseTypeSafe` 36 (the last two were bodyless pass-throughs, vestiges of a removed try/catch, INLINED into the owner's walk), `IsReferenceType` 31, `IsImplicitNumericConversion(TypeInfo,TypeInfo)` 25, `IsImplicitNumericConversion(Type,Type)` + `GetNumericTypeFullName` 30. `Analyzer.cs` 23,060→22,938 (20,246→20,139); 26 routed sites → `AnalyzerConversionFacts.nl` (254 lines, 1 enum + 1 class, 9 members) | The arc opens at the BOTTOM of `IsAssignable`'s dependency tree, not at a detour. The two C# numeric tables were the SAME policy written twice in two vocabularies; the owner states the widening relation ONCE over a `NumericConversionKind` and reaches it through two DISJOINT name maps (`SourceNumericCode`, `ClrNumericCode`), with cross-vocabulary behaviour preserved exactly and pinned by explicit NEGATIVE contracts | 2,400 differential cells / 0 mismatches (529 + 900 + 900 + 71); ORACLE_DIFFS 0 / 40 targets; 3 fixtures 14 NL202; 64/64 assemblies byte-identical; contracts 1,554→1,561; suite 3,193/3,193; gate 13m47s |

**Durable findings (017).** The end state, the driver protocol and the owner-lifetime rules are in §3.4.

- **THE FILE CRITERION settles task boundaries.** 017's and 018's completion criteria are both FILE-scoped
  (`Analyzer.cs` vs `Performance/SystemsAnalyzer.cs`), so "which FILE's zero-policy state needs this member
  gone" decides ownership, not subject matter. Slice 24's subject-matter line had made 017's terminal state
  unreachable while advancing 018 by nothing, and its "reachable only from the call walk" premise was also
  FALSE (slice 60).
- **A RECORDED WALL IS EVIDENCE WITH AN EXPIRY DATE — re-measure it by EXECUTION before honouring it.** Two
  were retired that way and must NEVER be re-priced: `Assembly.get_FullName`/`AssemblyName.get_Name`
  (slice 65) and the whole two-catalog-row `PropertyInfo.Name`/`FieldInfo.Name` wall slice 55 had priced
  (slice 56, root-caused to the catalog being the legacy planner's surface — §3.3).
- The brief was WRONG about its target's size in EIGHT CONSECUTIVE SLICES (55–62, and again in 64), always
  because it counted DISPATCH ROOTS rather than exclusive closures: 8 → 14 members, 4 → 5, 99 → 396 named
  lines, 401 → 1,188, 183 → 772, 111 → 379. Re-run caller attribution with the extractor re-validated
  against the previous slice's recorded extents before quoting a line count.
- **A TWO-CALLER PREDICATE DIES WHEN THE SECOND CALLER MOVES, AND NEVER BEFORE** (`IsRangeLikeType` at 58,
  `IsIndexLikeType` at 59) — which is why `range` and the ref/out pre-cut had to be one slice.
- Owner merges are decided by what is SHARED, not by driver shape: slice 56 REFUSED to merge `index` and
  `array` (they shared only a driver shape), slice 57 MERGED `new` and `with` (they shared a 196-line rule,
  two reports and the NL202 gate), and slice 58 could do NEITHER — assignment needs the operator family and
  the operator family needs the write-target reports, so one owner would be a CYCLE the language cannot
  express.
- A family cannot be split along the ARM axis when shared tables have callers in BOTH arms: `GetNumericName`,
  `IsIntegralType`, `GetUnaryNumericPromotionType` and `TryResolveOperandClrType` each do, so unary-first
  and binary-first would each leave the other relaying four tables (slice 53).
- Not every family is a WALK: `ResolveIdentifier` takes ZERO expression steps across its whole closure, so
  it moved with no request type, no state, no phase and no driver — the arc's first expression family with
  no driver loop (slice 54). A pure SINK needs none either (slice 39's boolean conditions).
- The expression territory needed exactly ONE new protocol shape, the ANSWERING DRIVER: all ELEVEN
  pre-existing drivers return `void` and carry answers only INWARD via `Supply`, because no statement or
  declaration walk had ever had an answer to carry OUT. `Result(state)` plus a `TypeInfo`-returning loop is
  ten lines (slice 49).
- A hoisted count-exact schedule was REFUTED BY COUNTEREXAMPLE twice: an overload group holding a
  receiver-style GENERIC candidate that LOSES fires the receiver ONCE, not three times (slice 24); and an
  earlier lambda's ANSWER changes a later lambda's expected signature, with 91 of 173 lambda analyses run
  against a signature the FINAL bindings do not give (slice 21).
- **Reading a cached type back out of the SEMANTIC MODEL is UNSOUND**: on `Read.Tag("mg")` the model holds
  the permissive `FunctionTypeInfo` recorded by the callee walk while the walk's own analysis answers
  `unknown` and IS THE SOLE PRODUCER of the NL411 — a cache read would have returned the wrong type AND
  DELETED a user-visible diagnostic. Re-analysis is not idempotent in general (78 corpus REPEATs answered
  differently) (slice 17).
- **A PHASE RANGE ROUTED BEFORE A FALL-THROUGH MUST BE DISJOINT FROM EVERYTHING THE FALL-THROUGH CAN SEE.**
  The reflected bind was numbered 20–26 while `AdvanceCall` routes 14–17 then falls through to the
  N#-method-group return owning 18–23, a range appearing in no listed case. Caught only by the self-host
  oracle; renumbered 30–36 (slice 62).
- NO step kind is ever renumbered and no gap is reused — a kind is a value ~40 contracts pin — and a
  row-by-row step-kind differential is deliberately NOT taken when kinds retire by design, because that
  difference IS the deliverable (slice 37, honoured in 56, 60–63).
- Signature shapes are REDESIGNED at the boundary, not transliterated: `bool` + `out int score` becomes a
  single `int` with `-1` outside the value's real range (zero is a genuine score); two `out`s become a
  three-way VALUE because C# encoded "does not match" and "matches but carries no information"
  identically; an `out` parameter becomes a nullable RETURN read with `is { }`, preserving `&&`
  short-circuit (slices 2, 15, 17).
- An EMPTY params tail is NOT special-cased by the missing-argument phase: `RequiredParameterCount` is the
  only rule, so a signature declaring none is required IN FULL and reports its empty tail. Writing the
  "obvious" exemption would have made the filler and the arity tables disagree (slice 15).
- Landing the diagnostic-span resolver was the arc's unlock: it was the LAST C# dependency of the source
  binder's reporting family, converting an arm slice 15 had measured as "cannot move" into a mechanical one
  in the same slice. And slice 15's claim that "an N# owner returns a class, so all 113 sites change shape"
  is FALSE — C# positional deconstruction binds to an N#-emitted `void Deconstruct(out,out,out)`, so every
  `var (line, column, length) = …` survived verbatim (slice 16).
- The same expression SPANS DIFFERENTLY in value and statement position (as a value an unnamed form
  measures one token; as a statement the finding is "this has no effect" and runs to the end of the written
  line), and an assignment TARGET never widens to a stable path while the general expression span does
  (slice 16).
- The 12C boundary rule: overrides and resolvers cross the C#/N# boundary as DATA, never as a function —
  12B's temporary `Func<Type,object>` cast was erased by `AnalyzerReflectionTypeOverride`, and a
  `Func<TypeReference,TypeInfo>?` resolver was deleted outright by making its five call sites pass the
  containing type explicitly. `ApplyReflectionBindings` HAD to come too, because three of the four override
  sites closed over a CONDITIONAL and the second arm is the `Bound` rule, unrepresentable without the
  binding walk — and the two rules are NOT interchangeable (slices 12B, 12C).
- `NullabilityMetadata.cs` deleted whole with ZERO C# added anywhere, and its differential caught what
  reading would not: testing `[NotNullWhen]`'s constructor argument with `ArgumentType == typeof(bool)` is
  WRONG under a `MetadataLoadContext` and silently dropped the flow prefix from every MLC-loaded signature
  (slice 12B).
- Admitting an external type is CATALOG DATA and no call plan was needed — adding one would have been a BUG
  (§3.3). `CustomAttributeTypedArgument.get_Value` bound only after the 153-line plan block was REMOVED
  (slice 12A).
- The pending-pair PROTOCOL was the arc's one concession and did not survive: 12C ABSORBED both shells and
  the recursion became simply a call (slices 6, 12C).
- Behaviour is PRESERVED, not improved, even where the port makes a defect visible: `System.Array.Sort(points.x)`
  gets the wrong tailored diagnostic; the match arm join is under-specified so `Dog` then `Animal` types as
  `Dog`; `ValidatePackageName` is reachable only through parser error recovery so it reports `'<error>'`.
  Improving them is a language decision, not a port's (slices 59, 60, 66).
- Repeated contract failures were the CONTRACT being wrong, not the port, for seven consecutive slices
  (57–59 and back) — 13 of 17 first-run failures in slice 54 were one fact
  (`AnalyzerScopeStack.RecordVariable` writes the SEMANTIC MODEL's scoped table only, not the lexical
  scope), and ZERO were production bugs.
- The overload merge was NEARLY LOST: C# passes `new[]{existingFunction}` alone and the port's first draft
  passed BOTH, which would have made every overload in the language a duplicate-declaration error. Caught by
  re-reading the C# against the port ARGUMENT BY ARGUMENT before any oracle — a corpus without overloads
  would have passed it (slice 66).
- Slice 63's region-by-region census OVERTURNED the standing 017 completion assessment, which claimed
  exhaustiveness while omitting the attribute validator (48 members / 957 lines), the import family
  (14 / 435), the scope/symbol/default-parameter family (9 / 288) and a ~108-line expression tail — ~1,815
  lines of policy across ~80 members. The zero-policy review must run LAST.
- Slice 64 added NO DRIVER and that is the defining measurement: every collaborator was already N#-owned
  and published, so 959 lines of policy left C# for ONE line of routing.
- `AnalyzeStatement` was proved TERMINAL as a reviewed zero-policy host rather than moved (26 arms, one
  call each; order carries no meaning because all case types are direct mutually exclusive subclasses), and
  `EmptyStatement` was reachable and silently unhandled — a decision nobody had written down, now written
  at a cost of one line and zero behaviour change (slice 45).
- Two slots, not one frame: a class moves BOTH `CurrentClass` and `CurrentTypeName` while a struct, record
  and interface move only the NAME, so a struct nested in a class is analysed with that class still
  current — and the forward-reference first pass is a CLASS's alone; levelling it would have made a forward
  reference between two STRUCT methods resolve where it does not today (slice 48).
- Accessors are a PAIR, not a body: the scope-balance invariant is per ACCESSOR, so `{ get set }` opens TWO
  scopes and absorbing them into the function walk would have weakened three passing slice-44 contracts
  (slices 46, 47).
- Vocabularies that look identical stay SEPARATE with negative contracts pinning the disjointness (the two
  numeric tables of slice 1; the binding-surrogate open-generic table as a strict subset in slice 3;
  `IsSpanTypeName` vs `LoopSequenceTypeFacts`' in slice 2), and existing C# diagnostics tests are never
  hand-mapped to contracts — they STAY and execute against the N# owner, which is strictly stronger.
- `char.IsLower`'s absence from the columnar `System.Char` catalog was the arc's FIRST REAL WALL and its
  first toolset repin, and approximating around it is a SILENT behaviour change (`IsLetter && !IsUpper`
  accepts title-case, `ToUpperInvariant(c) != c` refuses `ß`, an ASCII range refuses `é`) — every
  approximation changes which identifiers get NL903 (slices 46, 48).
- NEXT-TASK HANDOFF measured at slice 67: `Performance/SystemsAnalyzer.cs` at 2,390 lines / 171 extents, AT
  EPOCH, one production consumer, 19 codes NSYS001–NSYS180 all declared in that one file.

### 4.7 Task 016 — the parser front end (complete; `Parser.cs` DELETED; box CHECKED)

Outcome: `src/NSharpLang.Compiler/Parser.cs` (7,116 lines) and the `ParseResult` record it solely produced
(14 lines) are DELETED — 7,130 C# lines out, 0 C# in — and `ColumnarParserRecovery.ParseFileAst` is the
sole parse + ordered-diagnostic authority for production and for every test in the repository. The arc ran
stages 1–17 (family-by-family byte-exact parity against Parser.cs), then N+1 → N+1c (the AST hierarchy
migration and full node-tree materialization, 407/407 in-repo files byte-exact), then N+2 (the production
cutover) and N+3 (the deletion). Suite 3,193 → 3,193 across the deletion: no test file and no `[Fact]` was
removed, so the 2,021 C# xunit parser assertions now execute against the N# owner. Only N+2 and N+3 were
IDE-affecting and both ran the VS Code-enabled gate with the extension rebuilt and reinstalled.

| slice id | commit(s) | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| 016 note (gate-bar note) | no commit | none | Only the two production-touching stages (N+2 cutover, N+3 deletion) needed the IDE bar; Stages 1-8 added self-contained N# owner files plus native contracts with NO production/LSP wiring, so the non-VS-Code gate sufficed until cutover. | 2 IDE-bar runs; Stages 1-8 non-IDE |
| Task 016 status (COMPLETE) | `9f2dd9572` (landed) | `Parser.cs` gone from production, LSP and every test; `ColumnarParserRecovery` is the sole parse + ordered-diagnostic authority | Completion criterion is the FILE being gone, not "a reviewed zero-policy host". The one residual — translating 2,021 rerouted C# parser assertions into native `.tests.nl` contracts — is BOOKKEEPING, moves no ownership, and does not gate the checkbox. | capability arc stages 0-17 closed; 432 native parity contracts at Stage 17; owner 6,855 lines then; contracts 1,217/1,217 at N+1c tranche 2 |
| 016 stage N+3 (Parser.cs deletion arc) | `53e272711` (landed) | DELETED `src/NSharpLang.Compiler/Parser.cs` (−7,116) and `ErrorReporting.cs`'s `ParseResult` (−14); 53 parse sites in 20 test files rerouted to `ColumnarParserRecovery.ParseFileAst`; owner gained `FileParseAst.Success` | Rerouting 2,021 parser assertions beats deleting them: reroute makes each an EXECUTABLE proof obligation on the N# owner over a synthetic surface the 27,694-source corpus never reaches. Deleting on a mapping argument trades executable coverage for prose. | 7,130 C# deleted / 0 added; −7,264 C# / +53 N#; unit 3,193→3,193; contracts 1,554/1,554; audit 18/18; IL 78/78 byte-identical, PRODUCT_IL_DIFFS=0; full VS Code gate EXIT 0 13m48s, 105 steps, 36 VS Code tests |
| 016 stage N+2 (production cutover) | `4d7a7cb79` (landed) | all 12 production consumers (MultiFileCompiler, Analyzer x4, Formatter, CLI FormatSource+Lint, FixApplicator, CodeIntelligenceService, DocumentManager, PlaygroundCompiler) routed to the N# owner; owner gained leaf class `FileParseAst {CompilationUnit, Errors}` | Six owner parity defects were invisible to the tranche-11 probe and only cutover-grade fuzz found them: `TokenTypeToString` has no `Assign` case (renders "assign", not "="); `ParseParameterListRecovery` must anchor on `Previous` EACH iteration, not the list's opening token; `SplitGreaterDepth` resets ONLY in Synchronize*, so an owed `>` crosses a member boundary. | 27,694 sources / 0 mismatches (514 whole-tree + 452 malformed + 26,728 fuzz over 11 seeds); 88/88 assemblies byte-identical, PRODUCT_IL_DIFFS=0; 9 C# files all net-negative; unit 3,193; contracts 1,550; VS Code gate EXIT 0 13m44s |
| 016 stage N+1c tranche 11 (error-node materialization) | `b0ad09fd9` (landed) | owner reproduces EVERY Parser.cs synthetic recovery artifact (9 `IdentifierExpression("<error>")` sites, the `IdentifierPattern` terminal, 3 `SimpleTypeReference("<error>")` substitutes, the `<error>`-named placeholders, the synthetic ctor/local-fn/on-lambda artifacts); zero declines remain | Decision RULED: reproduce every site rather than decline — a declining owner cannot serve the LSP, whose files are malformed most of the time. The multi-line SourceSpan gate is RETIRED: `SourceSpan`'s 4-arg primary constructor is public and emits fine. | 407/407 in-repo, 513/513 whole tree, malformed corpus 453/453 (was 262/453), fuzz 10,560/10,560 = 11,526 sources 0 mismatches; contracts 1,550 (+26, zero retained declines); owner 9,358→9,371; member count unchanged at 280 |
| 016 stage N+1c tranche 10 (10a+10b statement bodies) | `dc0824063` (landed) | whole Statement family + block-bodied lambda (10a) and the member-BODY consumers — function/method/ctor/property/indexer bodies, local functions, test-DSL declarations (10b) | `ColumnarParserRecovery` has reached the columnar front-end's PER-CLASS MEMBER CEILING: adding ANY member function makes `ParseColumnarStructInfoInto` decline the whole class (`NL103 … Declined at parse.struct`) regardless of name/signature/body. Raising it means a KERNEL change, which trips the two-stage bootstrap wall — so inline, or delete an existing member first. | owner 8,614→9,358; tests 4,004→5,170; contracts 1,524 (+82); whole-file sweep 404/407 (was 26); 4 recorded owner divergences retired |
| 016 stage N+1c tranches 9b+9c | `538a9d5c0` (landed) | argument/element-list forms (call/with/new/tuple/array/alloc/stackalloc) and match+patterns / interpolated strings / lambda literals — the expression surface completes except the block-bodied lambda | Parser.cs's `AppendText`/`EmitText`/`AdvancePosition` local closures are INLINED over plain locals (N# has no first-class Func) and deliberately NOT parser fields, so a nested interpolated string inside a hole cannot clobber the outer text buffer. | owner 8,037→8,601; tests 2,673→4,004; contracts 1,438 (+79); triangulation 79/80 (sole non-match = the intended block-lambda decline); whole-file 26/407 |
| 016 stage N+1c tranche 9a | `20335ae4b` (landed) | single-operand / type-carrying postfix + keyword-primary forms (member access, index, is/as, await/must/throw, typeof/nameof/sizeof, checked/unchecked, cast, spread) | The no-stub gate is the proof instrument: a form sets `.Node` only when every operand carried one, so a deferred form declines — "live materializes vs owner declines" is the STRONGEST owner==Parser.cs evidence, stronger than a match. | owner 7,946→8,037; tests 2,293→2,673; contracts 1,359 (+25); triangulation 24/24 |
| 016 stage N+1c tranche 8 (composed operator tiers) | `f46bac09a` (landed) | every binary/range/unary/postfix/ternary/assignment tier returns its byte-exact node; `ParseRequiredExpressionAfter` now returns `Expression?`; field initializers materialize | Binary nodes anchor on the OPERATOR token, not the left operand. The 3 ExternalAssemblyScan failures are PRE-EXISTING Debug-layout infra tests, verified identical 3/3 on the stashed baseline — environment artifacts, not a regression. | owner 7,731→7,946; tests 1,878→2,293; contracts 1,334 total / 1,331 pass (+37 all green); triangulation 34/34 |
| 016 stage N+1c tranche 7 (leaf/primary tier) | `e5324b24e` (landed) | leaf atoms + single-expression parenthesized form materialize; value-bearing enum members unlocked | Parser.cs's enum string-value inference replicated exactly: the FIRST member's `StringLiteralExpression` value infers `EnumType.String` only when there is no explicit `: int or string` backing type. | owner 7,654→7,731; tests 1,538→1,878; contracts 1300/1300 (+19); triangulation 14/14 plus a whole-file DeclarationEnums.nl match |
| 016 stage N+1c tranche 6 (type params, base lists, remaining type bodies) | `067180e91` (landed) | `ParseTypeParameters`/`ParseBaseTypeList`/`ParseUnionBody`/`ParseEnumBody`/`ParseSoaRecordBody` return real lists; type-alias and newtype materialize; `hasTypeParams`/`hasBaseList` gates relaxed | The base-list DISPATCH differs per kind (Parser.cs :977-978, the NL010-era single-colon finding): a class splits [0] to BaseClass and [1..] to Interfaces; struct/record take the whole list as Interfaces; interface takes it as BaseInterfaces. | owner 7,473→7,654; tests 1,074→1,538; contracts 1281 (+26); triangulation 24/24 (21 synthetic + 3 whole-file) |
| 016 stage N+1c tranche 5 (richer TypeReference family) | `7b29042bf` (landed) | the stage-15 type grammar returns byte-exact TypeReference nodes; `ParseFieldTypeReference`/`ParseParameterTypeReference` no longer restricted to single-token simple types | Emitter gap: assigning through a list-index + property chain (`elements[0].Type.Span = …`) declines the columnar backend (NL103 emit.statement.block-child node-kind-23) — bind the element and its inner type to LOCALS first. `T?[]`'s span is NOT token-length-extended: a distinct span rule. | owner 7,270→7,473; tests 719→1,074; contracts 1255 (+17); triangulation 15/15 (11 synthetic + 4 whole-file) |
| 016 stage N+1c tranche 4 (modifiers, primary-ctor params, argument-free attributes) | `feaaef5a3` (landed) | `ParseModifiers` returns the byte-exact `Modifiers` bitmask, `ParseParameterListRecovery` returns `List<Parameter>`, `ParseAttributes` returns `List<AttributeNode>`; five name parsers thread them | MILESTONE: first WHOLE-FILE `ParseFileAst(corpus) == golden` on three real corpus files, each golden triangulated against LIVE Parser.cs via `nlc query ast`, so owner == golden == Parser.cs. | owner 7,117→7,270; tests 520→719; contracts 1238 (+13); 3 whole-file corpus equalities; multi-flag bitmask Public\|Sealed = 129 |
| 016 stage N+1c tranche 3 (members through type bodies) | `a721fe590` (landed) | nesting-safe `TypeMemberStack` + `AddDeclaration`; `ParseTypeBody` returns its member list; `FieldDeclaration` and `SimpleTypeReference` materialize | Byte-exact spans ARE achievable without value-struct construction: `SpanFromTokens(t,t)` is value-equal to the static factory `SourceSpan.FromStartAndLength(t.Line, t.Column, t.Value.Length)`, and a static factory returning the struct emits where `new SourceSpan(...)` declines. | owner +106/−38; tests +141/−5; contracts 1225 (+8); no in-repo `.nl` file fit the subset, so goldens were triangulated via `nlc query ast` |
| 016 stage N+1c tranche 2 (ClassDeclaration; tranche-1 blocker DISPROVEN) | `7f18ad342` (landed) | `ParseClassName` materializes `ClassDeclaration` via the fully-qualified `new NSharpLang.Compiler.Ast.ClassDeclaration(...)`; harness `Golden.AddClass` same | OVERTURNS tranche 1: the "constructor planner declines nullable-generic-list args when a `BaseClass: TypeReference?` param is present" theory is WRONG. Real cause is a SIMPLE-NAME TYPE COLLISION with test-helper classes in `AnalyzerDeclarationContext.tests.nl` under a tests-enabled build; FQN resolves it, no planner change, no wall. | owner +7 lines; contracts 1217 (+2); four empirical disproofs (tests-excluded build emits; empty-list variant also declines; null scores 4; the helper's own `new ClassDeclaration("X")` is green) |
| 016 stage N+1c tranche 1 (CompilationUnit container + FileImports + type skeletons) | `b212eef1f` (landed) | owner constructs the production `CompilationUnit`, FileImport statements and empty-body struct/interface/enum/record declarations; new `ColumnarParserAst.tests.nl` with the `AstEq.Diff` reflection deep-equal comparator | The AST harness had to be native `.nl` because C# `tests/*.cs` is RATCHET-BLOCKED — a new `.cs` trips OWN003 and growth trips OWN004. Its ClassDeclaration "emitter gap" diagnosis was later DISPROVEN by tranche 2. | owner 6,937 (~+63); contracts 1215 (+13, incl. a negative self-check proving the comparator is not vacuous) |
| 016 stage N+1b (AST-hierarchy migration) | `0bbce8e1f` (landed) | ~110 AST types moved from C# records to N# classes in 3 new `.nl` files; DELETED `Ast/Declarations.cs` (238), `Ast/Statements.cs` (225), `Ast/Expressions.cs` (381) — the C# `Ast/` directory is gone | The migration is ALL-OR-NOTHING at the base: C# records cannot derive from N# classes, so moving `AstNode` forces every derived node and the mutually-recursive helper cluster. N# emits data members as public FIELDS (C# records exposed properties) and emits classes WITHOUT the CLR abstract flag. | 844 C# lines removed, net non-N# −846; unit 3190/3190; contracts 1202; LanguageServer 273/273; 159-assembly IL fingerprint diff EMPTY; reviewedHead d7f043fb→1be7f7cb4c07e417 |
| 016 stage N+1 (AST/facts bridge, first increment) | `e50953baf` (landed) | new `PreambleAst` result class + `ParseFilePreambleAst`; `ParseNamespace`/`ParsePackage`/`ParseImport` materialize the production Namespace/Import/Package nodes | The CompilationUnit container was an ASSEMBLY-DEPENDENCY block, NOT an emitter gap: the dependency runs Compiler → BootstrapServices and never the reverse, so the upstream owner cannot NAME the C# container types (every BootstrapServices `.nl` takes `CompilationUnit` as `object` + reflection). | owner 6,855→6,937 (+82); tests 5,711→5,836; contracts 1202 (+8) |
| 016 stage 17 (residual [5]; parity ledger CLOSES) | `cf87d87e4` (landed) | garbage-type cascade shapes + the type-alias underlying-type consumer; `ParseTypeBodyIfPresent` renamed to `ParseTypeBody` and made UNCONDITIONAL | Parser.cs ALWAYS parses a type body (`Consume('{')` + `ParseMemberList`, :970-971); the owner's `if !Check('{') return` simplification diverged for a non-`{` offender. Deferral ledger closed: the EOF-length-clamp class is PERMANENTLY UNMATCHABLE at the CompilerError level, and the table-row HANG is PRODUCTION-BUG-GATED. | contracts 1194 (+22); owner 6,841→6,855; tests 5,347→5,711; residual map [1]-[5] ALL DONE; chip task_1f371371 filed, duplicate task_9babb6f4 dismissed |
| 016 stage 16 (test DSL + attributes, residual [4]) | `550b174fc` (landed) | test/setup/teardown declarations, the table-driven `with (params) [ rows ]` grammar, and attributes at top-level, member AND parameter positions | The malformed table-driven ROW shapes HANG the PRODUCTION parser: Parser.cs `ParseTestDeclaration` :590-604 has no no-progress guard, so `ParseExpression` spins on a `}`/`]` terminator in row position. `nlc check` spun >12s. The faithful model would hang the contract suite, so those shapes are pinned only at EOF. | contracts 1172 (+25); owner 6,640→6,841; tests 5,069→5,347 |
| 016 stage 15 (richer type references, residual [3]) | `822f3bedd` (landed) | union / postfix array-nullable / byref / tuple / `Func<>` type grammar; RETIRED the narrower `ParseSimpleTypeReference` and rerouted its 3 callers | Only ONE genuinely new report exists in the whole type grammar — the union NL103 "Expected a type after a pipe"; everything else reduces to an already-owned primitive. `Func` does NOT call `ReportMissingGenericTypeArgument`, so `Func<>` diverges from `List<>`. Array/nullable-array closes are lookahead-guarded and can never fail. | contracts 1147 (+33); owner 6,520→6,640; tests 4,731→5,069 |
| 016 stage 14 (member grammars + type bodies, residual [2]) | `14ddbea27` (landed) | member dispatch, methods, constructors, indexers, properties, positional/base lists, and the union/enum/soa bodies; ~18 new parser methods; retired the stage-2 deferred non-`{` found-other for record/interface/union/enum/soa | `ReportMissingReturnTypeMarker`'s length is the NAME's length (`func A() int` reports length 1, `func Foo() int` reports 3). A body-less METHOD gets no missing-body report (abstract/interface methods are valid) — unlike a local function. Union/enum/soa bodies each have their own loop and own missing-`}` NL106. | contracts 1114 (+36); owner 5,826→6,520 (+694); tests 4,303→4,731 |
| 016 stage 13 (remaining statement kinds, residual [1]) | `555df048a` (landed) | yield/break/continue/throw/try/using/lock/switch/allow/alloc/unsafe/assert/preprocessor/local-function/await-foreach/off, C-style `for`, tuple deconstruction, typed declarations, `on` subscriptions; `ParseBlockBody` refactored into `ParseBlockStatementsLoop`+`ParseBlock` | A LOCAL function uses plain `ConsumeIdentifier` for its name, NOT the keyword-anchored `ConsumeDeclarationName` used at top level. "Expected block statement after lock" is UNREACHABLE dead C# — `ParseBlock` always yields a block. | contracts 1078 (+45); owner 4,854→5,826 (+972); tests 3,784→4,303 |
| 016 stage 12 (interpolated-string hole grammar) | `e9df04cb2` (landed) | full `$"…"` char-scan port plus `ParseHoleExpression` (state save/swap/restore around a fresh sub-token stream); added a STABLE position-sort to `ParseFilePreamble` | Hole diagnostics BYPASS the outer panic gate: Parser.cs appends the sub-parser's errors via `_errors.AddRange(...)`, and each hole's sub-parser has its own `_panicMode` — so two bad holes both report, and a hole error records even while the outer parser is mid-panic. The stable position-sort mirrors the CLI's `DeduplicateAndSortDiagnostics` and is a proven no-op for every already-ordered family. | contracts 1033 (+21); owner 4,476→4,854 (+378); tests 3,516→3,784 |
| 016 stage 11 (alloc / stackalloc / lambda + is/as) | `6b0cc3918` (landed) | is/as arms on `ParseRelational`, alloc+stackalloc primaries, both lambda prefixes plus `IsLambdaExpression` and `ParseMultiParameterLambda` | `IsLambdaExpression`'s bounded lookahead admits ONLY a well-formed `( ident, … ) =>`, so `ParseMultiParameterLambda`'s ConsumeIdentifier / RightParen / Arrow sites can never fire — the only reachable lambda error is the missing body. The invalid-relational default (:4177) is an unreachable dead arm. | contracts 1012 (+31); owner 4,302→4,476 (+174); tests 3,146→3,516 |
| 016 stage 10 (postfix call/index/generic-call/with + first keyword-primary tranche) | `e0a132afb` (landed) | postfix loop, `ParseArgumentList`, and the new/cast/tuple/typeof/nameof/sizeof/checked/unchecked/array primaries | `with {…}`'s `EnsureProgress` does NOT reset panic — unlike the new-object initializer and match-case resets — so two bad `with` properties report ONCE while two bad object-initializer members report TWICE. `IsCastExpression`'s nested scan closures were lowered to methods over two scan-state fields (N# has no first-class Func). | contracts 981 (+40); owner 3,564→4,302 (+738); tests 2,741→3,146 |
| 016 stage 9 (closing-delimiter recovery) | `2e5e9cf6c` (landed) | `TryReportMissingClosingDelimiter` port + owner-span/unmatched-opening scanners, the block and type-body missing-`}` NL106 sites, and the parameter trailing-comma recovery; retired deferrals from stages 4-8 | `Consume` tries the recovery FIRST for a missing `)`/`]` (RightBrace is DECLINED) and returns a SYNTHETIC closing token so parsing continues; a MID-LINE offender that is not a boundary token DECLINES recovery and falls back to the plain NL102. N# has no reference-typed out args, so the port needed explicit result-carrier classes. | contracts 941 (+13); owner 3,091→3,564 (+473); tests 2,533→2,741 |
| 016 stage 8 (match / pattern family) | `dcd1c9c41` (landed) | `ParseMatchExpression`, the seven pattern tiers, `ParsePropertyPatterns`, and the full `GetHintForMissingToken` mirror | Match's per-case `EnsureProgress` boundary does NOT reset `_panicMode` — unlike the union per-case reset (:1216) and the object-initializer per-element reset — so one bad case cascade-suppresses the rest of the match until the enclosing statement/declaration boundary. | contracts 928 (+18); owner delta not recorded |
| 016 stage 7 (expressions family) | `132e05ed9` (landed) | replaced stage-6's shallow subset with the full 14-tier precedence ladder plus the unexpected-token / prefix-`+` / leading-`.` / ternary / dangling-operator / missing-operand / member-after-dot error families | The four INVALID-OPERATOR switch defaults (:3718, :4177, :4253, :4348) are proven UNREACHABLE dead arms — each switch is guarded by an exact-match fact that admits only tokens it already handles, so they cannot be reached byte-exact and are not modelled. | contracts 910 (+35); +9 dangling-per-tier and 10 negative contracts |
| 016 stage 6 (statement family) | `2a3dba6f1` (landed) | the real `func f() { … }` block-body grammar, `SynchronizeToNextStatement` sync point, per-statement panic reset, `_currentRecoveryBoundaryColumn` tracking | The recovery-boundary-column rule (`IsMissingOperandBoundary`) is what stops a dangling operator swallowing the FOLLOWING statement; the block's own missing-`}` NL106 was reproduced but not corpus-exercised at this stage. | contracts 875 (+25) |
| 016 stage 5 (generics / constraints) | `6a329280e` (landed) | `ParseTypeParameters`, `ReportMissingGenericTypeArgument`, the `ConsumeGreater` split-`>>` discipline, and the `where`-clause constraint validations | A type-parameter list closes with the GENERIC `Consume(Greater)`, not the split-aware `ConsumeGreater`, so its expected string is "greater". Classes do NOT take `where` clauses (verified: `class C<T> where …` cascades to 3 diagnostics). The Parser.cs "…not permitted in ." message TYPO is ported verbatim. | contracts 850 (+22) |
| 016 stage 4 (member / parameter / field declarations) | `eb8c6f949` (landed); record header is DUPLICATED in the source at two consecutive line pairs | real `ParseParameterListRecovery`, `ParseTypeBodyIfPresent`, `ParseMemberList` with the per-member panic reset, `ParseFieldMember` and the four Consume/type reporters; retired the stage-2 braced-kind `{`-offender case | `LooksLikeNextFieldAfterMissingType` is the heuristic that stops a following `Ident with : or :=` on a later line being swallowed as the current field's type. Parameter names anchor a missing name on the FOLLOWING type token; the parameter colon anchors on the parameter NAME. | contracts 828 (+17) |
| 016 stage 3 (malformed-literal family, NL105) | `32c1a7dad` (landed) | the three Parser.cs malformed-literal reporters ported, reached through the `func f() => <literal>` expression-bodied vehicle plus a minimal literal-reaching expression path | The malformed-literal family belongs to the PARSER model, not a separate lexer lane: the already-N# `Lexer.nl` only CLASSIFIES (sets `Token.IsTerminated`) and emits NO diagnostic; every NL105 is reported by Parser.cs through the shared-panic `ReportError`. | contracts 811 (+14) |
| 016 stage 2 (declaration-name family) | `b7c5ad833` (landed) | `ConsumeDeclarationName`, the `ParseTopLevelDeclaration` dispatch in exact Parser.cs keyword order, the per-kind name parsers and the boundary/force-advance loop | `DiagnosticSpanFromToken` KEYWORD-ANCHORING: a missing or invalid declaration name underlines the DECLARATION KEYWORD, not the offending token, in all three `ConsumeIdentifier` variants. | contracts 797 (+24) |
| 016 stage 1 (shared-panic recovery model + import/namespace/package) | `b07c0e747` (landed) | new `ColumnarParserRecovery.nl`; DELETED the inert divergent `ColumnarSyntaxDiagnostics` scaffolding | The whole arc rests on one shared `_panicMode` flag: suppress-while-set, set-on-report, reset ONLY at the declaration-boundary sync point — plus ordered reporting and `LastVisibleTokenSpan` anchoring. | +11 golden parity contracts |

**Durable findings (016).** The panic model, the AST migration and the bookkeeping follow-on are in §3.5.

- Task 016's checkbox criterion is met by the STRONGER arm: `Parser.cs` is GONE, not reduced to a
  zero-policy host — and no test was deleted and no assertion rewritten (stage N+3).
- **Chosen path (a), recorded at Stage 0**: build a recovery-aware N# front-end to FULL parity family by
  family (each stage proven byte-exact against Parser.cs on a native parity corpus, comparisons only in
  `.tests.nl`, NO production shadow route), then wire consumers LAST at parity (N+2, IDE-affecting), then
  delete Parser.cs (N+3). Path (b) — porting the tooling front end to consume columnar node tables — was
  rejected as 017+ scope.
- **Scaffolding fate, recorded**: DELETE the divergent `ColumnarSyntaxDiagnostics` closure
  (`ColumnarSyntaxDiagnostics.nl` + `ParserDiagnosticMessages.nl` + `ParserDiagnosticsTable.nl`, ~2,177
  lines, zero external references). `ParserErrorDiagnostics.nl` is KEPT (live: both Parser.cs and the new
  owner called it). The message ORACLE is Parser.cs itself and git history preserves the scaffolding. Do
  NOT resurrect the scanner.
- `CompilerError` CONSTRUCTION was already delegated to the shared N# `ParserErrorDiagnostics.Create`; only
  the DECISION (whether/where to report under the shared panic model) plus message and hint literals were
  C#-owned, and moving just the literals is not a decision-ownership move — DECLINED (Stage 0).
- BootstrapServices cannot reference `Parser.cs` (Compiler → BootstrapServices; the reverse is a cycle), so
  every parity proof is against GOLDEN Parser.cs output captured out-of-band via `nlc check --json`
  filtered to NL101–NL109 (stages 1+).
- The **no-stub gate** is the materialization discipline: a form sets `.Node` only when every present
  operand materialized, otherwise the whole form declines. "Live materializes vs owner declines" for a
  deferred form is the STRONGEST owner==Parser.cs proof, stronger than a match (tranches 7–9a).
- **RULED at tranche 11**: reproduce every synthetic `<error>` recovery artifact rather than decline — a
  declining owner cannot serve the LSP, whose files are malformed most of the time, and the N+2 cutover
  hands consumers whatever Parser.cs produces today. Result: 407/407 in-repo files, 11,526 sources, zero
  declines.
- Four INVALID-OPERATOR switch defaults and "Expected block statement after lock" are proven UNREACHABLE
  dead C#, each guarded by an exact-match fact, and are deliberately NOT modelled (stages 7, 13).
- The `>>`-split discipline (`_splitGreaterDepth`) is a required part of the generics diagnostic family,
  not an optimisation, and the owed `>` must SURVIVE a member boundary — `class C { A: X<Y>>\n B: int }`
  produces a field literally named `>` (stage 5, N+2 defect 4).
- Stage-6's `ParseBinaryRightOperandOrMissing`/`ParseRightOperandOrMissing` had to be replaced by boolean
  operand-missing helpers because N# has no first-class `Func<Expression>`; every Parser.cs local closure
  had to be inlined or lowered to methods over explicit scan-state fields (stages 7, 10, 12; tranche 9c).
- The statement family's byte-exactness rests on three coupled mechanisms: the per-statement panic reset,
  `_currentRecoveryBoundaryColumn`, and the dangling-operator through-token span (stage 6).
- STAGE 2 excluded class/struct/record/interface/union found-other cases because the member-list body
  consumes trailing junk and resets panic; STAGE 4 deferred non-`{` braced found-other and non-identifier
  parameter names because their garbage-type cascades report in an order that diverges from the oracle's
  position-sorted output (stages 2, 4, 5).
- The tranche-11 triangulation probe was NOT sufficient for cutover: it compared fewer diagnostic fields
  and did not fuzz, and missed ALL SIX owner parity defects. The cutover-grade probe (whole tree + the full
  13-field raw-ordered diagnostic stream + 26,728 LSP-shaped fuzz mutants over 11 seeds) found them
  (stage N+2).
- `ParseModifiers` was EATING `readonly`, swallowing the flag on every readonly field — found only by the
  whole-file sweep, not by any tranche (tranche 10).
- The real caller inventory for `Parser.cs` was 21 FILES, not the 3 the N+1 records named — 20 test files
  plus Parser.cs's own interpolation sub-parser; always re-inventory before a deletion arc (stage N+3).
- Deleting `Parser.cs` required `./scripts/reload-vscode-extension.sh` even though no LanguageServer source
  changed, because the `NSharpLang.Compiler` assembly the server ships had changed (stage N+3).
- The ratchet's assertion-marker heuristic counts `it(` for JS frameworks and `ParseCompilationUnit()`
  contains it, so the N+3 repin's −53 marker delta is 100% FALSE POSITIVES, proven by a per-marker diff
  over all 20 files (stage N+3).
- A production BUG can gate a contract: the table-driven malformed-ROW shapes make `nlc check` spin > 12 s
  (`ParseTestDeclaration`'s row loop has no no-progress guard) and the faithful model REPRODUCES the hang —
  pinned only at EOF and filed as a chip (stages 16, 17; see §5's `170244a5f` remediation).

### 4.8 Tasks 001–014 — the emitter-ownership queue (all accepted, boxes checked)

One row per task, from the completion ledger, with its acceptance commit. Tasks 013 and 014 are NEW
SURFACE, not migrations: no C# iterator or async-iterator emitter ever existed, so "delete the C# owner" is
satisfied by planner-owned decline sites plus zero net C# decision growth against the IMMUTABLE epoch
ceiling (21,723 / 20,646). Task 014 produced the FIRST FULLY-GREEN GATE of the closeout.

| slice id | commit(s) | what moved (C# deleted/shrunk → N# owner) | durable finding | headline numbers |
|---|---|---|---|---|
| Task 001 (accepted) | `6110bbbcf` | Deleted `TryUsePlannedExternalStaticMember`, `PreloadSupportedExternalReferenceAssemblies`, `TryGetStringComparisonValue`, `TryEmitPrimitiveStaticConstant` + the enum/primitive/pool/static-member emission and preflight branches; `ColumnarIlEmitter.cs` 21,515→21,361 → `ColumnarBindingScopeFacts`, `ColumnarExternalStaticMemberPlanner`, `ExternalAssemblyScan`, `ExternalQualifiedTypeResolver`, schema-v3 field handles/`ldsfld` | N# owns external static fields and properties end-to-end, including package and relative-DLL (outside-CWD) resolution. | 3,182 units; 178 BootstrapServices contracts; 18 ownership tests; clean repin |
| Task 002 (accepted) | `61a593715` | Deleted ordinary local/non-byref-parameter, lifted-local, boxed-capture, explicit-`this` and bare current-instance field/property identifier emission + matching preflight/type branches; `ColumnarIlEmitter.cs` 21,361→21,209 → `ColumnarBoundIdentifierPlanner`, exact lexical/current-instance binding facts, recursive code-plan argument-address + declared-signature validation, atomic zero-arity property accessor definition | N# owns bound identifier reads; the accessor definition had to be made ATOMIC (zero-arity property accessors defined together) for the plan to be sound. | 3,182 units; 201 BootstrapServices contracts; 26 range-index product contracts; 18 ownership tests; clean SDK repin |
| Task 003 (accepted) | `ad51692d4` (stage-0 `da2be2c32`, `97cde7c6e`, `aedb1267f`) | Deleted direct one-receiver source field/property read emission, the `Exception.Message` and `WebApplication.Environment` arms, the member-chain preflight shortcut, `typeof` emission/preflight, and zero-hole interpolation emission; `ColumnarIlEmitter.cs` 21,209→21,164 → `ColumnarInstanceMemberPlanner`, exact runtime/source member resolvers, schema-v3 field/method/type handles + receiver-address ops, `ColumnarTypeOfPlanner` | The retained source-member C# branch is restricted to EXCLUDED NESTED RECEIVERS only — the fence, not a general fallback. | 3,182 units; 238 BootstrapServices contracts; 41 range-index product contracts; 18 ownership tests; three adversarial audits |
| Task 004 (accepted) | `5ad756e1d` (stage-0 `d6d551ea1`, `d24ec7bb4`, `8ce4d49e2`, `fcbcf4ef6`, `0cd216a44`, `0e1d02ed1`, `507742abc`, `1e747dd97`, `469408917`, `1b63b9a82`, `0035d82ae`) | Deleted synthesized-record `Equals(object)`/`GetHashCode()` call preflight and emission, the direct `TextWriter.WriteLine(string)` arm, and unrestricted re-entry into ordinary source/runtime fixed-call paths; `ColumnarIlEmitter.cs` 21,164→21,097 → `ColumnarDirectCallPlanner`, exact source/runtime resolvers, contextual conversion + nullable lowering, source-static scope resolution, address-preserving value receivers, executor stack validation | Establishes the FENCED-CALL ARCHITECTURE that task 005 then mirrors: retained C# routes are mechanically fenced to excluded call families, never a general fallback. | 3,181/3,182 fresh-gate units (only 009 left); 382 BootstrapServices contracts; 14 direct-call + 18 ownership + 4 decline-diagnostic + 2 reflection-bootstrap contracts; exact ILVerify; three adversarial audits |
| Task 005 (accepted) | `6746c1b2c` (stage-0 `67a3e5803`, `37822d657`, `f9ed33dd9`, `aca8d35b3`, `91c062dd6`, `e63f27176`, `ff2cf1138`) | Deleted the Analyzer's string-matched member/export/declaration resolution (`Analyzer.cs` 23,471→23,068), the emitter's unconditional construction ownership (kinds 15/58/36 fenced to the whole-subtree residual), and `ColumnarSynthesizedGenericScopeTests.cs`; aggregate C# net −157 → `ColumnarConstructionPlanner`, construction-row execution in `ColumnarCodePlanExecutor`, `ColumnarSemanticTypeRegistry` + `AnalyzerDeclarationContext`, `ColumnarPrimitiveBinaryPlanner`, `ColumnarSourceOperatorResolver`, `TypeInfoIdentityFacts` | Construction, array literals and object initializers (incl. nested values, generic-base member rebinding, target-typed integers, closed generics) are N#-owned through schema-v3 plan rows that the executor stack-validates. | 3,182/3,182 fresh-gate units; 553 BootstrapServices contracts; 7 construction-arrays + 3 generic-scope-invalid + 1 erased-enum-identity new contracts; gate down to four failure groups |
| Task 006 (accepted) | `e57c80c8a` (stage `3dcb60bd2`, `e41570f69`, `83941f204`, `62ab5ffdf`, `096655625`, `5523402c5`, `aade33590`, `8397811ea`) | Deleted the case-12 shifts branch, decimal `op_*` table and right-literal adoption path from both emission and preflight, plus the preflight's arith/bitwise/ordering/numeric-equality arms; `ColumnarIlEmitter.cs` 21,618→21,499 → the full N# primitive binary family plus operand unlocks (numeric casts, decimal literals incl. negative, sibling-function calls, local-delegate invocations, String.Join catalog, List<T> indexer chains, byref-parameter deref over typed-ldind, ushort literal casts, slot-reinterpretation casts) | The retained fenced numeric core serves exactly the whole-subtree residual: contextual-lambda call operands (010), member chains on call results, unary-negated call operands, dictionary-indexer reads, and enum string-constant reads — 015 grows that nested-operand surface. | 608 BootstrapServices contracts; 15 primitive-binary + 41 range-index + 14 direct-call + 3 interface-parameter + 18 ownership; 3,182/3,182 units; toolset repin at each two-stage bootstrap |
| Task 007 (accepted) | `e9df4eb60` (routing `7eaccb1e9`, Brtrue two-stage bootstrap with mid-stage toolset repin) | Deleted the `&&`/or-else sub-arm in `TryGetPreflightBinaryExpressionType` — proven dead, zero hits across units, native contracts, examples and the self-emit; `ColumnarIlEmitter.cs` 21,499→21,497 → `ColumnarConditionalPlanner` (Boolean `&&`/or-else with the exact case-12 short-circuit lowering, relocated ternary planning with widened operand recursion) + the `Brtrue` schema identity (contract id 58) | A residual short-circuit is only ever EMITTED, never preflight-typed — N# types every plannable short-circuit at the front door. The case-12/13 EMIT arms are verify-first load-bearing and were recut as precisely-fenced residual servers. | 619 BootstrapServices contracts; new conditional product project 8/8 with executed side-effect-order and right-operand-not-evaluated proofs; 3,182/3,182 units |
| Task 008 (accepted) | `23ced5034` (historical C# canonical test migrated at `0206a1ed1`; deletions trace to `399008ea9`) | Deleted every range/index decision: five static handles + their resolver, thirteen lowering helpers, the case-11 index-from-end and case-69 range arms, the case-10 string/array Index/Range reads, both preflight type-selection helpers and their dispatch arms; `ColumnarIlEmitter.cs` 21,497→21,209 (−288). Added N# owners: NONE — `ColumnarRangeIndexPlanner`/`ColumnarRangeIndexHandles` already owned it | RESIDUAL INVENTORY EMPTY — the first task with no fallback from N# to any old branch. Only the Index/Range type-system entries remain (typed locals/parameters, not lowering policy). | 41/41 range-index product contracts IDENTICAL before and after the deletion (the decisive dead-code proof); 619 contracts; 3,182/3,182 units |
| Task 009 (accepted) | `85c817440` (base/interface classification), `5f9bf3fce` (inherited external-base-method calls), plus the extension-calls commit | Deleted the emitter's PASS 0a' base/interface classification decision block (`ColumnarIlEmitter.cs` 21,209→21,164); the remaining slices added ZERO C# → `ColumnarBaseTypePlanner` (ordered base classification incl. external runtime class bases with protected-ctor default chaining), inherited external-base-method bare/this call planning, `ColumnarExtensionMethodResolver` (ExtensionAttribute index, instance-beats-extension precedence, trailing-optional null-default fill), IServiceCollection admission, highest-version NuGet runtime-asset unification | ACCEPTANCE was the generated Web API template checking, building and ILVerifying clean; the fresh gate fell from four failure groups to three. | 625 BootstrapServices contracts; external-base-interface 18/18; extension-calls 4/4 executed; 3,182/3,182 units; Web API ILVerify fully verified |
| Task 014 (accepted) | `d396a847c`, `73ae226d5`, `0a33f1ff2`, `f3d1e89c9` | NEW SURFACE, not a migration — no C# async-iterator emitter ever existed. Deletion contract satisfied by planner-owned decline sites (`emit.iterator.async-*`) plus deleting the `emit.iterator.async-emit-pending` gate; emitter net −2 (21,719/20,644 vs immutable epoch 21,723/20,646, case-73 additions paid by lossless comment compression) → `ColumnarIteratorPlanner` async classification + async MoveNextCore/MoveNextAsync/DisposeAsync/GetAsyncEnumerator/AsyncFactory plans, schema-4 catch regions, parser-kernel await-foreach forms | FIRST FULLY-GREEN GATE OF THE CLOSEOUT: full VS Code-enabled gate with ZERO failure groups. Real suspension proven (resuming off-caller-thread), not the blocking model. | 731/731 contracts (717+14); 3,185/3,185 units; native iterators 25/25 (21+4 async); gate 14m11s exit 0; AsyncStreams real delays 1.273s wall; ILVerify 2/2 |
| Task 013 (accepted) | `489895987`, `71c5450b1`, `dd7d12107`, `03849de55`, `d0a4ee530`, `0c0961048`, `9698fbb76`, `bb359043f`, `d3602cfa4`, `edfcbeb66`, `f1c1b3b9f` | NEW SURFACE: no C# iterator emitter ever existed; the C# recursive-descent `func*`/yield parser/analyzer stays as the LSP-fallback/oracle owned by 016/017. Deletion contract satisfied by planner-owned decline sites replacing the blanket `emit.statement.yield-unsupported` arm, zero net C# decision growth (emitter mechanical at 21,619 of the immutable 21,723 ceiling) → parser kernels (func* scan/signature/method-scan + yield), `ColumnarCodePlan`/Executor schema-4 method bodies, `ColumnarIteratorPlanner` | "Delete the C# owner" does not apply to a NEW surface — the contract is satisfied by decline sites plus zero net C# decision growth. Enumerator hoisting follows the Roslyn try/FAULT region discipline; generic iterators need self-instantiation TypeSpec rebinding with an MVAR-leak guard. | Iterators.nl byte-exact across nine sections + ILVerify (6 assemblies); native iterators 21/21; 690/690 contracts; 3,182/3,182 units; VS Code-enabled gate down to ONE failure group (AsyncStreams) |
| Task 012 (accepted) | commit recorded in git only ("Own readonly-field initialization placement in N#") — no hash in ledger | Deleted the initialized-fields decision, unconditional helper synthesis, whole-body helper emission and the inline default-ctor body decision → `ColumnarFieldInitPlanner` (initonly stores inline in every base-reaching constructor; mutable stores in a helper synthesized only when needed; static ownership untouched) | The N# plan is the SOLE placement authority — this is what made the gate's IL-verification step pass. | estate-wide ILVerify 0 findings (empty baseline); gate down to TWO groups (013, 014); new readonly-init project 18/18; 625 contracts; 3,182/3,182 units |
| Task 011 (accepted) | `8a90bcd92` | Deleted the case-52 arm's clone-always callvirt selection, receiver gate, per-field binding and result-type decision, plus the value-record `<Clone>$` synthesis branch (record structs now carry no Clone, matching C#) → `ColumnarRecordWithPlanner` (clone/copy strategy — reference clone vs verifiable value copy through an addressed temp — receiver shape, ordered member resolution, readonly decline, exact call form, result type) | Record structs must carry NO `<Clone>$`, matching C#; the value path is a verifiable value copy through an addressed temp, not a callvirt clone. | RecordStructs ILVerify delta −2 findings; whole-estate ILVerify over 91 assemblies leaves only the task-012 InitOnly finding; record-with project 12/12; 625 contracts |
| Task 010 (accepted) | slice commit recorded in git only ("Own lambda definition placement in N#") — no hash in ledger | Deleted the non-capturing lambda placement decisions: visibility attribute literals, name+counter construction, synthesized-signature guards, value-type/ctor guard, type-parameter ownership decision, static-vs-this classification branching, and the dual sub-emitter constructions (unified); `ColumnarIlEmitter.cs` 21,164→21,150 → `ColumnarLambdaPlacementPlanner` | Lambdas must be emitted assembly-static for a VERIFIABLE cross-type `ldftn`; the historical cross-type MethodAccess shapes are confirmed fixed. The value-capture display-class path remains a precisely-fenced residual pending ModuleBuilder/DefineType modeling. | byte-identical IL across all three product reproducers; lambda-placement project 9/9 in the ilverify gate; 625 contracts; 3,182/3,182 units; gate steady at three groups |

Ledger entries that predate or straddle the arcs above (task 005's acceptance and its wide-stack
follow-ups; the first three 017 slices as the ledger recorded them; the 016 arc's own ledger rows; the two
015 pre-pause sub-slices):

| slice id | commit(s) | what moved (C# deleted/shrunk → N# owner) | durable finding | headline numbers |
|---|---|---|---|---|
| Current evidence (task 005 acceptance + follow-ups) | `6746c1b2c`; follow-ups `195028aa9`, `7f4e727d6` | Analyzer string-matched member/export/declaration resolution deleted (`Analyzer.cs` 23,471→23,068) → `AnalyzerDeclarationContext`/`ColumnarSemanticTypeRegistry`; `ColumnarSynthesizedGenericScopeTests.cs` deleted for native `generic-scope-invalid`; emitter keeps ONE fenced construction residual (kinds 15/58/36 + four helpers) | Columnar emit must run on a dedicated wide-stack thread — MSBuild task threads run ~256 KB stacks and the emitter's per-node frames overflowed every fresh SDK-path emit; the NL103 decline trace is thread-local so it must be built on that same thread. | `ColumnarIlEmitter.cs` 21,586 (epoch ceiling 21,723); units 3,182/3,182; contracts 553/553; gate 4 failure groups, down from 10 |
| 017 slice 3 (well-known-type owner) | `0dee71b98` (landed) | `Analyzer.cs` 22,873→22,622: nested `internal sealed class WellKnownTypes` (173 lines), `TryGetKnownOpenGenericType`, `TryConvertBuiltInTypeInfoToRuntimeClrType`, the inline binding-surrogate open-generic table — 4 units/271 lines out, 20 mechanical routing lines in → `AnalyzerWellKnownTypes` (225 lines/52 members) + `AnalyzerWellKnownTypeFacts` (212/5) + 10 contracts | RECUT: the recorded target (absorb `ResolveTypeAlias` + `TryConvertTypeInfoToClrType`) was REFUTED BY MEASUREMENT — the alias funnel's declaration-context branch fires **0** times and its `ResolveType` branch **36**, because `Analyzer.cs:369` builds a FRESH `AliasTypeInfo` while the N# context keys its catalog by TypeInfo reference identity. | 692 differential cells / 0 mismatches; 146-shape/292-cell before-after funnel transcript byte-identical; `nlc check --json` 40/40 identical; IL 64/64 identical (PRODUCT_IL_DIFFS=0); contracts 1,571→1,581; suite 3,193/3,193 |
| 017 slice 2 (callable/delegate-reference classification) | `9249b4eb0` (landed) | 8 C# methods / 66 lines out of `Analyzer.cs` (22,938→22,873), 0 C# in: `IsCallableReferenceType`, `IsMethodGroupReferenceType`, `HasSourceFunctionIdentity`, `IsRuntimeDelegateType`, `GetFunctionParameterModifier`, `NormalizeDelegateParameterModifier`, `TryCreateFunctionTypeInfoFromGenericDelegate`, `IsSpanTypeName` → `AnalyzerCallableReferenceFacts` (148 lines/7 members) + `AnalyzerConversionFacts` (+9) | The span-name gate is filed with the CONVERSION family because its only consumer is an implicit conversion; the `out`-parameter Try-pattern becomes a nullable return read with `is { }`, preserving `&&` short-circuit. | 271 cells / 0 mismatches (9 types loaded into a real MetadataLoadContext to pin the runtime-vs-load-context asymmetry); check --json 40/40; IL 64/64 identical; contracts 1,561→1,571 |
| 017 slice 1 (conversion/assignability tables — arc opens) | `dfec28f2a` (landed) | 7 C# methods / 122 lines out of `Analyzer.cs` (23,060→22,938), 0 C# in: both `IsImplicitNumericConversion` overloads, `GetNumericTypeFullName`, `IsReferenceType`, `IsReflectionAssignableFrom`, `GetInterfacesSafe`, `GetBaseTypeSafe` → `AnalyzerConversionFacts` (254 lines/9 members) + 7 contracts | The CLR implicit-numeric-widening table was written TWICE in two vocabularies; it is now stated ONCE over a `NumericConversionKind` reached through two disjoint name maps, with cross-vocabulary disjointness pinned by negative contracts. | 2,400 cells / 0 mismatches (23×23 + 30×30 + 30×30 grids, 71 TypeInfo values); check --json 40/40; IL 64/64 identical; contracts 1,554→1,561 |
| 016 terminal slice (STAGE N+3) | `53e272711` (landed) | `src/NSharpLang.Compiler/Parser.cs` (−7,116) and `src/NSharpLang.Compiler/ErrorReporting.cs` (−14, the `ParseResult` record) DELETED — 7,130 C# lines out, 0 C# in; all 53 parse sites across 20 C# test files route to `ColumnarParserRecovery.ParseFileAst`; `FileParseAst` gained `Success` (4 native contracts) | Task 016's checkbox criterion is met by the STRONGER arm: `Parser.cs` is gone, not reduced to a zero-policy host. No test was deleted and no assertion rewritten — the 2,021 C# xunit parser assertions now execute against the N# owner. | suite 3,193/3,193 unchanged; contracts 1,554/1,554; audit 18/18; corpus IL 78/78 identical; FULL VS Code-enabled `test-all.sh --commit` with extension rebuilt/reinstalled; 2 `removed` ratchet rows + 20 net-negative test repins |
| 016 slice 8 (arc STAGE 7 — expressions, recut A) | NOT committed (mandate: do not commit) | No C# deleted (capability-only). `ColumnarParserRecovery.nl` 2,334→2,822 (+488): full precedence ladder, `ParseInvalidPrefixPlusExpression`, `ParseUnaryOperandOrMissing`, `ReportMissingMemberNameAfterDot`, `ParseLeadingMemberAccessWithoutReceiver`, `ShouldSkipUnexpectedExpressionToken`, rewritten `ParsePrimaryExprValue` | Stage-6's `ParseBinaryRightOperandOrMissing`/`ParseRightOperandOrMissing` had to be replaced by boolean operand-missing helpers because N# has no first-class `Func<Expression>`. | contracts 910/910 (875+35); dev.sh Parser 381/381; audit 18/18; no wall (packaged SDK 0.1.0 self-emitted, no repin); full-suite/corpus sweeps N/A (owner referenced only by its own `.tests.nl`) |
| 016 slice 7 (arc STAGE 6 — statements) | NOT committed (mandate: do not commit) | Capability-only. `ColumnarParserRecovery.nl` 1,648→2,334 (+686): `ExprResult` carrier + `RecoveryBoundaryColumn` state, `ParseBlockBody`, `SynchronizeToNextStatement`, `ParseStatement` and the if/while/for/foreach/return/print/expression statement family, `DiagnosticSpanFromExpressionThroughToken`, `IsMissingOperandBoundary` | The statement family's byte-exactness rests on three coupled mechanisms: the per-statement panic reset, `_currentRecoveryBoundaryColumn`, and the dangling-operator through-token span. | contracts 875/875 (850+25); dev.sh Parser 381/381; audit 18/18; no wall, no repin |
| 016 slice 6 (arc STAGE 5 — generics/constraints) | NOT committed (mandate: do not commit) | Capability-only. `ColumnarParserRecovery.nl` 1,252→1,648 (+396): split-aware Check/Advance + `SplitGreaterDepth`, `ParseTypeParameters`, `ConsumeGreater`, `ParseGenericConstraints`, `ReportClassStructConflict`, `ReportStructNewRedundancy`, `DiagnosticSpanFromTokenRange` | The `>>` split discipline (`_splitGreaterDepth` with split-aware Check/Advance and reset at the two sync points) is a required part of the generics diagnostic family, not an optimisation. | contracts 850/850 (828+22); dev.sh Parser 381/381; audit 18/18; no wall, no repin |
| 016 slice 5 (arc STAGE 4 — member/parameter/field) | NOT committed (mandate: do not commit) | Capability-only. `ColumnarParserRecovery.nl` +~350: `ParseParameterListRecovery`, `ConsumeParameterColon`, `ParseParameterTypeReference`, `ParseTypeBodyIfPresent`/`ParseMemberList`/`ParseFieldMember`, `ConsumeFieldColon`, `ParseFieldTypeReference`, `LooksLikeNextFieldAfterMissingType`; retires Stage-2's deferred braced-kind found-other for the `{` offender only | DEFERRED with reasons: non-`{` braced found-other (`class 5`) and non-identifier parameter name (`func f(5)`) emit garbage-type cascades whose report order diverges from the oracle's position-sorted output — they need `ParseTypeReference`-on-garbage + `SynchronizeToNextStatement` + sorted emit. | contracts 828/828 (811+17); dev.sh Parser 381/381; audit 18/18; no wall, no repin |
| 016 slice 4 (arc STAGE 3 — malformed literal, NL105) | NOT committed (mandate: do not commit) | Capability-only. `ReportMalformedLiteralIfNeeded` → the three ported Parser.cs reporters (char :4905 / string :4830 / raw :4876) through the shared-panic `Report`; reached via `func f() => <literal>` and a minimal literal-reaching expression path | ORIGIN RULED: malformed literals belong to the PARSER model, not a lexer lane — the already-N# `Lexer.nl` only CLASSIFIES (`Token.IsTerminated`) and emits no diagnostic; the decision delegates to the live shared `ParserLiteralFacts`. | contracts 811/811 (797+14); dev.sh Parser 381/381; audit 18/18; no wall, no repin |
| 016 slice 3 (arc STAGE 2 — declaration name) | NOT committed (mandate: do not commit) | Capability-only. `ConsumeDeclarationName(message, anchor)` + `ParseTopLevelDeclaration` dispatch (exact Parser.cs keyword order incl. `ref struct`/`soa record`/`duck interface`/`record struct` + LookAhead) + per-kind name parsers + the boundary/force-advance loop; removed the superseded `IsDeclarationStart`/`IsContextualDeclarationStart` | Keyword-ANCHORING discipline: the declaration keyword's span overrides the offending token's in all three variants (reserved-keyword NL109 / EOF NL104 / found-other NL102), so a bad name underlines the keyword. | +24 contracts, 797/797 (773+24); audit 18/18; no wall; class/struct/record/interface/union found-other deliberately excluded (their member-list body resets panic) |
| 016 slice 2 (arc STAGE 1 — shared-panic recovery model) | NOT committed (mandate: do not commit) | New N# owner `src/NSharpLang.Compiler.BootstrapServices/ColumnarParserRecovery.nl` reproducing Parser.cs's `_panicMode` lifecycle + `LastVisibleTokenSpan` EOF anchoring, carrying the import/namespace/package family; DELETED the inert divergent `ColumnarSyntaxDiagnostics` closure (`ColumnarSyntaxDiagnostics.nl` + `ParserDiagnosticMessages.nl` + `ParserDiagnosticsTable.nl`, ~2,177 lines); `ParserErrorDiagnostics.nl` kept (live) | BootstrapServices cannot reference `Parser.cs` (Compiler → BootstrapServices; the reverse is a cycle), so parity is proven against GOLDEN Parser.cs output captured out-of-band via `nlc check --json` filtered to NL101–NL109. | contracts 773/773 (762+11); dev.sh Parser 381/381; audit 18/18 (ratchet tracks only non-N# files); no wall, no repin |
| 016 slice 1 (PROVEN-BLOCKED-WITH-RECORD) | `2feaabd17` (landed) (STATUS.md only) | Nothing moved. Records the consumer inventory, the AST-bridge blocker, and the three independent reasons `ColumnarSyntaxDiagnostics` cannot be wired | The unwired 9-commit `ColumnarSyntaxDiagnostics` arc (`760cf0203`..`771f741b7`) mirrors ~20 of Parser.cs's ~256 diagnostics (~8%), uses a DIVERGENT 10-pass per-token-scan panic model, and shared-panic coupling means even a single-family extraction is not side-effect-free. | ~256 vs ~20 diagnostics; `Parser.cs` 7,117 lines, ratchet `compiler-core` ceiling 7,117, fingerprint `text-v1:895641da1f9de8a6`; 520-assertion `LanguageServerDiagnosticsTests` pins the model |
| 015 sub-slice (interpolation base-call splitter) | NOT committed this turn | The string-classification half of `TryResolveInterpolationBaseCallPlan` (the `base.` prefix + `()` suffix Ordinal parse and name extraction/validation) deleted from `ColumnarIlEmitter.cs` (21,438→21,433, −5) → `ColumnarInterpolationSplitter.TrySplitBaseCall` + 2 contracts; the reflection guard/base-chain resolution/return-type guards stay as mechanical host | This was the LAST inline interpolation string-classification split (cast/equality/coalesce/integer-additive already N#-owned) — after it the directly-MOVABLE decision surface for 015-proper is EXHAUSTED. | PRODUCT_IL_DIFFS=0 across 162 assemblies; native 208/208; contracts 762/762; units 3,190/3,190; ratchet head `d7f043fb072388db` |
| 015 pivot sub-slice (case-12 dead-arm prune) | `6e94ca88c` | Deleted four provably-dead case-12 residual sub-arms: bitwise and/or/xor, record-struct structural equality, the `null == null` fold, and the multi-term string-concat CHAIN (`TryEmitStringConcatChain` + `CanProveStringExpression`). `ColumnarIlEmitter.cs` 21,534→21,438 (−96). No N# owner added — the planners already own the plannable surface | A partial 166-arm instrumentation run MISSED `stringcharconcat`; only the FULL self-emit (228 arms) caught the three sibling arms (ternary, ref-identity equality, string+char) that had to be RETAINED — the slice-5 escape signature. Candidate (a) preflight static-call typing proven load-bearing. | 0 IL diffs across 162 assemblies (the 12 sweep diffs are C# `Compiler.dll`/`BootstrapServices.dll` copied as a reflection-test dependency); native 208/208; contracts 760/760; ratchet head `40cb7fa576abc6c2` |

### 4.9 Measurement slices (2026-09)

Two measurement briefs ran in parallel sessions during the 015-B arc; the user merges them. Their verdicts
are launch-facing inputs to the 015 decision (§7 of `MEASUREMENT-VERDICT-2026-09.md`).

| slice | commit | what moved | durable finding | numbers |
|---|---|---|---|---|
| native-comparison refresh + vectorizer contracts + Step 3c throughput gate | `f1d51c727` + `b55f3d336` (merged) | 88 deleted C# tests / 254 rows re-covered as 92 native blocks / 503 asserts in `tests/native/systems-vectorization-facts`; Step 3c gates medians against `benchmarks/native-comparison/runner/SystemsThroughputBaseline.nl` at 20 %; runner/kernels/baselines are N# (the ratchet refuses new .sh/.json); ratchet net-negative (test-all-core.sh 916→815); head `1012ef9ac0812acc` both keys | N# vs Rust/C re-measured 2026-09-01 on an idle M4: N#/best-native 1.36×–2.65×; the vectorizer (ported at `5b54c269f`) fires on all four vectorizable kernels, yet N# is **1.17×–1.34× slower than June** on them and 1.20× on scalar parse-eight-digits while natives are within 6 % and the helper source is unchanged — the candidate cause is the IL the columnar port emits AROUND the helper calls and its scalar codegen (015 item 3: measure that IL against the ILCompiler's), NOT a missing port | gate green 04:08 (129 passed); Step 3c is load-sensitive by design (`SYSTEMS_BENCH=skip` exists) — 1.75×–2.04× uniform at load 8–10 vs 0.98×–1.05× at load 4 |
| compile-time benchmark + verdict | `2b23d7848` (merged `8e8927647`) | new N#-owned harness `tests/native/compile-time-bench` (spawns `nlc build --timings` / `nlc check --json` as processes, 5 runs, medians, lines/s, RSS, failing-check census); its gate block auto-runs in Step 3a against `tests/fixtures/compile-time/bootstrap-build-baseline.golden.json` (median ×1.5, pinned exit code, honours `SYSTEMS_BENCH=skip`); verdict at `systems-language-closeout/MEASUREMENT-VERDICT-2026-09.md`, raw output under `artifacts/compile-time/2026-09-01/` | `nlc build` on the compiler's own sources = parse + strict lint only and STOPS (45 findings, then 198 analysis errors in the MLC type model) — the SDK disables analysis for that project by name and the emit-only path takes **132.6 s for 172,653 lines (1.3 K lines/s), 14× slower per line than 2026-07-08**, with NO incremental skip on `dotnet build`. Tip pipeline ties the last C# pipeline on the 36 corpus projects both compile (0.995× build / 0.959× check). §7 puts options (a) continue 015 to deletion / (b) reviewed mechanical host + fix the regressions to the USER | BootstrapServices: build 7,868 ms / 172 MB / 21.9 K lines/s; check 26,997 ms / 683 MB / 6.4 K lines/s; harness 51/51; idle window 23:03–23:25 |

- IPv6 to `api.nuget.org` is black-holed on this machine and .NET does not fall back: export
  `DOTNET_SYSTEM_NET_DISABLEIPV6=1` before every gate or the isolated package cache stalls to NuGet's
  100 s timeout (found by the native-comparison session, verified with `curl -6` vs `curl -4`).
- The ownership ratchet refuses new non-N# files under `scripts/` and `tests/` (OWN003) and pins the
  gate scripts' line counts (OWN004), so a new gate step is an N# native project auto-run by Step 3a,
  and its baseline lives at the one JSON exemption under `tests/fixtures/compile-time/`.
- §7's AOT argument for option (a) ("Reflection.Emit cannot ship in a native image") is superseded by
  §3.8's correction: `PersistedAssemblyBuilder` runs under NativeAOT; the AOT path is task 022.

### 4.10 Wave 3 — the gate-speed slice, the IDE defect remediation and the formatter rule

| slice | commit | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| FORMAT-WRAPPING — the argument-list wrapping policy | this commit (branch `stream/format-wrapping`, rebased onto `541edf59c`) | gofmt's model, author-preserving, installed where there was NO model: every list arm wrote `", "` and one line was the only shape it could produce. Now a list the author wrote on one line stays on one line however long, and one that spans more than one source line becomes ONE ELEMENT PER LINE, block indented one level, closer alone at the opening line's indent, no trailing comma (N# rejects one — NL101/NL102). Five list kinds: call args, ctor args, object/collection initializers, array literals, parameter lists. `ColumnarParserRecovery.StampListEnd` stamps each list node's closer into the EXISTING `AstNode.EndLine` (zero new AST surface; it defaults to `Line`, so hand-built trees stay single-line and every AST-built contract is untouched), and the `ObjectInitializerExpression` anchor moves off the `new` keyword onto its own `{`. **The abolished width rule and `GetCurrentColumn` are DELETED** with `FormatExpressionToString` and the four width contracts | **VERIFY-FIRST OVERTURNED THE HUG THREE TIMES, AND THE ESTATE — NOT REVIEW — CAUGHT ALL THREE.** The exemption was specified as "the last element is a wrapped LIST"; the estate says it must be "the last element WILL BE WRITTEN ACROSS LINES", which is a different set. (1) `Task.Run(() => { … })` — a lambda BLOCK BODY is not a list, and the first rule tore every callback into five lines (`examples/11-advanced-features/LockStatement`). (2) The "an interior comment forces the wrap" clause was **unnecessary AND wrong** and is deleted: a `//` comment runs to end of line, so a one-line list provably cannot contain one, and the only cheap test — "a comment between the two delimiter lines" — also catches every comment inside a nested BLOCK, which tore a hugged callback apart in `examples/17-issue-tracker/backend/Endpoints.nl`. (3) `() => new { … }` — a lambda EXPRESSION body spans lines when its expression does (`examples/14-minimal-api`). **Second finding, a soundness one: the formatter can emit a wrap the parser refuses.** `IsContinuationRecoveryBoundary` ends an argument list at a continuation token that starts a declaration, and `ref` IS one — so `f(a, ref b\n)` would be rewritten with `ref b` at the head of a line, fail `FormatSafe`'s reparse gate and make the file **silently stop being formatted at all**. The wrap is refused for a `ref` argument instead. The same boundary is why a wrapped element must be indented past the statement's column — the canonical shape always is, which is why no wrap this rule emits is unreadable | **Estate is a FIXED POINT and the gate paths do not move: `nlc format` over all 932 sources twice is byte-identical, and `--check` reports "All files are properly formatted" on all four gate paths with ZERO churn.** Reparse decliners **8, a set byte-identical to the baseline formatter's own 8** (measured against a `541edf59c` CLI, not inferred from the count — one of them, `ColumnarEmitFacts.tests.nl`, has no triple-quoted string and was already failing). `nlc check --json` **byte-identical** on `tests/fixtures/issue-tracker` and on the 224,402-byte BootstrapServices output. Unit 7,302/7,302; `dev.sh --since` 596/596 (full suite — central change). **Eventual estate reformat, measured not estimated (932 sources, uncommitted): 293 files change, NONE in the four gate paths** — 274 `.tests.nl` + 19 product `.nl` in trees the gate does not format. Lines **406,752 → 414,879 (+8,127; +15,594/−6,926)** and **>120 chars 15,919 → 16,202 (+283)**. The same corpus under the OLD join goes to **394,460 lines (−12,292)** and **>120 = 18,035 (+2,116)**: the rule converts a 12k-line-eating, 2.1k-long-line-adding join into an 8k-line-adding canonicalisation that holds long lines flat — a 20,419-line swing and 87% less long-line regression |
| FORMAT-RULE SPLIT — the idempotence rule alone, without the `.tests.nl` gate widening | this commit (branch `stream/format-rule-split` off `27f4a1b6b`); the bundled original is `1e192a8c2` on `stream/chip-format-idempotence` | ZERO C#, ZERO deletions — four `.nl` files, pure addition. `FormatterWalkState` gains `AccountForEmittedBlankLine` and `Formatter.Format`'s three unconditional separators (after the namespace, after the import block, after the package) call it, so an output line with no source line behind it stops making the gap tracker lie by one. Seven estate contracts pin it: five in `FormatterSourceText.tests.nl` (the three separators as fixed points at ONE blank line, the namespace-then-import second reader, and the convergence/saturation row) plus a `FormatSafe`-WITH-COMMENTS helper trio, and two in `FormatterWalkState.tests.nl` (one line of gap closed; zero still means "nothing emitted yet"). **The discovery widening is deliberately NOT carried**: `FormatCommandKernels.ShouldFormatDiscoveredPath`, its two suffix helpers, its two contract rows, `tests/CliParityAuditTests.cs` and both ratchet keys stay byte-identical to `27f4a1b6b` | The defect and the gate gap are SEPARABLE, and separating them is what lets the fix ship now. The rule is a formatter-owner change with no C#, no fixture and no ratchet repin; the widening is what drags the parity fixture, the two-key repin and the 233-file estate reformat behind it, and the reformat is blocked on a wrapping policy that does not exist yet. A rule held hostage to a policy decision is a rule that does not ship | 4 `.nl` files, +147/−0 (plus this STATUS row); estate 7,264 → 7,271 Failed 0 (+7 exactly, one fewer than `1e192a8c2`'s +8 — the dropped row is the `.tests.nl`-under-fixtures one, which asserts discovery); non-idempotent over 889 `.nl`/`.tests.nl` sources **1 → 0** (the one offender is `ColumnarIteratorPlanner.tests.nl`, named before the run), reparse-declining 8 → 8 untouched, `FormatSafe` declines 9 → 8, and BOTH sweeps are fixed points (pass-1 and pass-2 trees byte-identical); `nlc format --check` on the four gate paths exit 0, "All files are properly formatted" ×4; `nlc check --json` over all 26 `project.yml` projects under those paths BYTE-identical before/after (md5 `b9472402fcc56ec30dbf841c09ee41cf` both); `dev.sh --since` selected the FULL unit suite (fail-safe, unmapped paths) 596/596 Failed 0 |
| GATE-SPEED (landed) | this commit; measured at `d26460045` | `Sdk.targets` gains a stamp-keyed incremental skip for `EmitNSharpIlAssembly`: `Inputs` = sources + `project.yml` + `@(ReferencePath)` + the SDK's three tool assemblies, `Outputs` = a stamp + `@(IntermediateAssembly)`, and a `BeforeTargets` predecessor deletes the stamp when its CONTENT (a Sha256 `StableStringHash` of the resolved source set, tests in/out, configuration) no longer matches. **19 insertions / 19 deletions — 206 lines / 177 non-blank, exactly the epoch ceiling**, paid for by compressing two multi-line comments and deleting ten labels that restated the element beneath them | **OVERTURN: the gate was never test-bound.** The 596 unit tests run in **5 m 42 s** on a quiet box, not the 16 m 28 s of `b16/gate.log` (a 2.78x loaded outlier). What the gate actually spent was **8 full BootstrapServices emits per run** — static analysis said 6-7, the instrument said 8. **Second overturn: an `Sdk.targets` fix cannot take effect in the run that packs it** — `BootstrapServices` resolves the SDK from the NuGet package cache, and the wrapper counts `.targets` as a dependency input, so the edit changes the DepKey and seeds a FRESH dep dir from the OLD package. Two gate runs measured "no change" before this was found (§2.2) | **BEFORE 28m44s / 8 emits (5 Debug, 3 Release), GREEN. AFTER 14m29s / 4 emits — 49.6% off the wall, half the emits.** Per step, before -> after: Step 2 8m34s -> **2m22s**; Step 3 8m06s -> **2m51s**; Step 3a 7m17s -> 6m22s; Step 4 4m21s -> **2m27s**. On the real 403-file / 172,653-line project the no-op rebuild goes **132.84 s -> 0.58 s (229x)**, against the 2026-09-01 baseline's own number; the cold emit reproduces it at 133.07 s. Correctness matrix 8/8 on a toy and 6/6 on BootstrapServices itself, including the reverse flip. Audit 17/18 before the repin (OWN005 fingerprint drift only, no OWN004), **18/18** after |
| IDE D3 — member completion after a trailing `.` (landed) | this commit; branched from `27f4a1b6b` | `CompletionHandler.cs` 700 → 642 / 611 → 562 non-blank: `GetMemberCompletionItems`, `GetMemberCompletionViaAst` and `GetNSharpTypeMembers` DELETED and replaced by a route to the same N# owners `nlc query completions` uses — the project snapshot first (`CompletionEngine.GetCompletions`), the open documents' own models second (`CompletionReceiverFacts.GetMemberAccessCompletions`); `IsMemberCompletion` rerouted to `CompletionEngineKernels.IsCompletionMemberAccessContext`. `DocumentManager.cs` holds at 1449/1246 LINE FOR LINE — one word, `private` → `public` on `TryGetSynchronizedProjectSnapshot`, a fingerprint-only row. NEW `EditorCompletionFacts.nl` (106) + `.tests.nl` (11 blocks) owns the three editor-presentation decisions; `CompletionReflectionFacts.nl` gains `IsOfferableMethod` (+4 estate blocks, +1 native block). | **THE LSP HAD NO PROJECT ROUTE AT ALL, AND THAT — NOT THE TYPE UNIVERSE — WAS D3.** Hover has called `DocumentManager.FindProjectHover` before its AST fallback since forever; completion was the missing FIFTH `FindProject*` sibling, so its only member source was `doc.SymbolsInfo` (one file, source-declared types only) over a SINGLE-FILE `SemanticModel`. A BCL receiver missed by construction and a cross-file receiver missed for want of a project. Task 022 slice 4 was NOT a prerequisite: the LSP `TypeResolver`'s three assemblies are never consulted for member completion, and routing through the snapshot hands the editor the analyzer's universe as a side effect. | unit 596/0; estate 7,264 → 7,279 (+15), 0 failed; native `completion-engine` 13/13, `query-completions` 1/1; ownership audit 17/18 before the repin → 18/18 after; `LanguageServerTests.cs` 4,200 → 4,171 / 3,411 → 3,398 / markers 602 → 589; `editors/vscode/test/suite/completion.test.ts` 162 → 161 / 131 → 129 / `test(` 7 held; four ratchet rows repinned, all at or under their immutable epoch ceilings |
| EMIT-REGRESSION (015 item 1) — root-caused, fixed, measured | this commit; branch `stream/emit-path-regression` off `27f4a1b6b` | **ZERO C#.** Two `.nl` owners. (1) `ColumnarExternalTypeCatalog` RETAINS the scan `Prepare` already opened and immediately threw away (`preparedScan`), and `TryGet` / `TryResolveExtension` read it instead of building a fresh `MetadataLoadContext` over ~196 assemblies per cache miss. (2) `ExternalAssemblyScan.LoadedByIdentity` indexes the loaded-assembly snapshot by full name, so `TryLoadExactRuntimeAssembly` is one hash lookup instead of a walk of every loaded assembly per reference path (~169 × ~110 `Assembly.GetName().FullName` per scan). 3 contracts added to `ExternalAssemblyScan.tests.nl` | **THE JULY NOTE'S NAMED FIRST SUSPECT IS 4.3 % OF THE PROBLEM AND THE REGRESSION WINDOW IS TWO DAYS WIDE.** Measured split of the SDK emit-only path: N# input builder (the per-member scratch arrays) **6,142 ms**, `TryEmitColumnarAssembly` **137,177 ms**. The catalog was introduced at **`6110bbbcf` (2026-07-10, "Own external static members in N#")**, two days after the 3.4 s measurement at `2e1286d99` (2026-07-08), and `TryGet` had the scan-per-miss shape in its first line — so the regression predates the whole 015-B door arc (2026-08-27→), which is exonerated. **Only the SDK path shows it**: `EmitIlAssembly` copies MSBuild's `@(ReferencePath)` into `config.Dependencies` (**169 paths**, 167 of them the net10.0 ref pack) while `nlc build` on a corpus project passes the handful of `project.yml` DLLs — which is why §2.2's corpus is silent and §2.1's large project is 100× worse | **Quiet-window medians of 3+3 matched runs (idle box, 15:07–15:13, only `BootstrapServices.dll` swapped): EMIT 93,626 → 11,167 ms (8.4×), TOTAL 97,618 → 15,116 ms (6.5×)**, parse unchanged at 4,057 → 4,037 ms. **The attribution closes arithmetically from two independent measurements**: the directly timed per-scan `OpenWithReferences` is **30.2 ms** (median of 5, 169 reference paths) and there are **2,952 scans**, so 89.2 s of a 93.6 s emit — **95 %**; the cost implied by the before/after difference is (93,626 − 11,167)/2,952 = **27.9 ms per scan**, within 8 % of the standalone figure. Fix 2's own effect, measured: per-scan **30.2 → 10.7 ms (2.8×)** — but with the scan retained it is called ONCE, so it now saves ~20 ms and is kept as DEFENCE, not as the win. Earlier loaded runs, same direction: emit 131,011 → 14,883 ms, `sys` **20.67 s → 1.39 s**, page reclaims **2,115,158 → 382,526**. **Cost paid, and ACCEPTED — do not "fix" it back:** peak RSS **597 MB → 1,030 MB**, one retained `MetadataLoadContext` instead of 2,952 built and torn down. Re-disposing the scan to recover ~430 MB restores a 9× emit regression. **2,952 scans** measured directly (`resolvedOwners.Count`), 7.3 per file over 404 files. Byte identity control-first, over all six window emits: every control pair (A1-A2, A1-A3, B1-B2) and every slice pair (A1-B1, A2-B3, A3-B2) differs by **17 or 18 bytes and nothing else** — the 16-byte MVID plus 1–2 bytes of PE timestamp at `0x88`, the slice pairs INDISTINGUISHABLE from the control pairs. **IL_DIFFS=0.** Corpus A/B (same CLI, only `BootstrapServices.dll` swapped): 68 projects, **39 emitted both sides, IL_DIFFS=0**, 29 skipped as tests-only. Estate **7,267/7,267 Failed 0** (baseline 7,264 + exactly the 3 new blocks); `dev.sh --since` fail-safed to the FULL unit suite, **596/596**. **FOLLOW-UP DELIBERATELY NOT TAKEN:** widening the cache key from `sourceFileId` to the file's import set (`ResolveOwner` reads only `facts.UnaliasedNamespaceImports`, so it is provably equivalent) would collapse the 2,952 misses further, but with the scan retained a miss is already cheap and a byte-identity slice should carry one behaviour change, not two. File it against the next emit-cost slice, not as a duplicate of this one |
| IDE D2 — hover on BCL members, and D1 with it (LANDED) | this commit; branch `stream/ide-d2-bcl-hover` off `385b7e8d1` | **ZERO NEW C#; the only C# touched SHRANK 307 → 149 lines / 264 → 129 non-blank.** Three causes, three owners, all N#. (1) `AstNodeFinderCore` gains arms for `NewExpression`, `ObjectInitializerExpression` and `InterpolatedStringExpression` — the walk descends by SHAPE, so without them `new Foo { A: x.Y() }` and `$"{x.Y}"` were LEAVES. (2) `CodeIntelligenceTypeResolution` gains a reflected-member arm on `MemberTypeInfoOfType` (`CompletionReflectionFacts.ResolveCompletionReflectionType`, plus a HOVER-LOCAL `ArrayTypeInfo` arm so `nlc query completions` does not move again this batch) and a new `ReflectedMemberOfType`; `CodeIntelligenceNavigation.ReflectedMemberAtPosition` asks it, and asks the ANALYZER'S OWN recorded resolution first. (3) `CodeIntelligenceSignatureKernels` renders May's text over `NullabilityMetadataReflection.FormatReturnType`/`FormatParameter`, with a decline-to-bare fallback. `HoverResult` gains a defaulted `DeclaringType`; the additive `declaringType` JSON key and an aligned `Declaring:  ` text line ship with it, and `cli-toolchain.md` documents both. New `EditorHoverFacts.nl` (159) takes ALL markdown out of `HoverHandler.cs`, which now only routes and speaks OmniSharp | **`MemberInfo` IS NOT A COLUMNAR SURFACE, AND THE ESTATE ALREADY KNEW.** The first build died at `emit.declaration.method-return` on a `MemberInfo?` return; `AnalyzerIndexAccess` reaches `GetDefaultMembers()`'s answer "without naming `MemberInfo`" for the same reason and `AnalyzerExpressionStatements` calls `get_Name()` "the estate's spelling for a `MemberInfo` name". The base class is replaced by `ReflectedMemberHandle`, which carries the three concrete sorts. **SECOND, AND IT IS THE ONE THAT WOULD HAVE SHIPPED A LIE: CLOSING A GENERIC OVER `object` MAKES THE HOVER CONFIDENTLY WRONG.** `CompletionReflectionFacts` substitutes `object` for any argument it cannot spell as a CLR type — which is EVERY N# user type, none of them compiled yet — so a member read off the CLOSED type reported `object?[] ToArray()` for a `List<WeatherForecast>`. Measured in my own output, not predicted. The member is now read off the DEFINITION and the type argument mapped back through `AnalyzerReflectionTypeOverride`, whose override arm `NullabilityMetadataReflection` had recorded as dead ("no caller ever passed one") — it has a caller now. **THIRD: THE BEFORE-STATE HAD THREE FAILURE MODES, NOT TWO.** Beside "nothing" and the `ToUpper(...)` placeholder, two positions answered the RECEIVER with the member's cursor (`array summaries: string[]` for `summaries.Length`, `generic result: List<WeatherForecast>` for `result.ToArray()`) — a wrong subject, which no defect report had named. **FOURTH: the analyzer's recorded resolution beats a fresh metadata lookup** and is asked first, because it is the only one that did real overload resolution | **All five README shapes fixed, measured before/after on the report's own positions with a stashed-baseline CLI** (`hover-BEFORE.txt` / `hover-AFTER.txt`): `DateTime.Now` no symbol → `property Now: DateTime { get; }` + `System.DateTime`; `.AddDays` no symbol → `method AddDays: DateTime AddDays(double value)`; `Random.Shared.Next` no symbol → `method Next: int Next() (+2 overloads)` + `System.Random`; `summaries.Length` `array summaries: string[]` → `property Length: int { get; }` + `System.Array`; `result.ToArray()` `generic result: List<WeatherForecast>` → `method ToArray: WeatherForecast[] ToArray()` + `System.Collections.Generic.List<T>`; `summary.ToUpper()` `method ToUpper: ToUpper(...)` → `method ToUpper: string ToUpper() (+1 overload)` + `System.String`. **D1 closed by the same arm**: `{forecast.TemperatureC}` `string` → `int`, `{forecast.Date}` `string` → `DateTime`. **Both controls byte-identical** (`field Summary: string?`, `function GetForecasts: (int) -> WeatherForecast[]`). Estate **7,320 Failed 0** (+15: 9 signature-kernel + 6 editor-hover blocks); native `query-integration` **65 → 69, all passed** (count-diff against a stashed baseline proves the 4 new blocks execute); `completion-engine` 13/13, `query-completions` 1/1, `cli-command-contracts` 89/89, `doc-query` 11/11, `analyzer-semantic-model` 51/51, `analyzer-clean-source` 991/991, `playground-tooling-surfaces` 33/33; LSP hover+completion **29/29**; `dev.sh --since` fail-safed to the FULL unit suite **595/595 Failed 0** (596 − 2 collapsed + 1 new; the arithmetic closes). Ownership audit **17/18 before the repin → 18/18 after**; two keys moved to `head-v1:3764b579fdba8a1f`. **No hover pin in `tests/native` moved and no golden file moved**: `json-contract-root-keys.golden.json` pins only the six ROOT keys and `declaringType` lives inside `result`. `LanguageServerTests.cs` 4,171 → 4,163 / 3,398 → 3,393 / markers 589 → 588, paid by collapsing `Hover_KeywordIncludesRange` and `Hover_PrimitiveTypeIncludesRange` into the two tests that already proved that markdown (the Range assertion moved with them — redundancy removal, not weakness) |

**Durable findings (IDE D2 + D1 — LANDED).**

- **D2 IS THREE DEFECTS WEARING ONE BUG REPORT, AND ONLY ONE OF THEM IS ABOUT THE BCL.** The README's five positions split
  cleanly: `DateTime.Now`, `.AddDays`, `Random.Shared.Next` and `summaries.Length` are all inside
  `new WeatherForecast { … }` on `WeatherService.nl` lines 21-23 and fail because **the AST position visitor never enters an
  object initializer**, which would fail for a USER member in the same place; `result.ToArray()` (line 27, a plain `return`)
  is reached but has no member source; `summary.ToUpper()` is reached, resolves, and is merely rendered as the analyzer's
  placeholder. Fixing only the rendering would leave four of the five positions still empty.
- **THE 019 SLICE IS EXONERATED; THE OWNER OF THE REGRESSION IS `81c6de9c9` ON 2026-06-24.** `git log -S "Declaring Type"`
  returns exactly two commits: the one that added the rendering (`47abee95f`) and the one that deleted it. The N# hover-text
  move did not narrow the reflection surface — the reflection surface was already gone three months before it.
- **THE DATA FOR A FULL SIGNATURE IS ALREADY IN THE RESOLVED VALUE AND IS THROWN AWAY AT THE LAST STEP.**
  `ReflectionMethodInfo` carries the live `MethodInfo` and `ReflectionMethodGroupInfo` carries the whole `MethodInfo[]`;
  the hover reads only `ToString()`. `NullabilityMetadataReflection.FormatReturnType`/`FormatParameter` — the exact two
  functions the deleted C# called — are already N#-owned. The fix is a renderer, not a new reflection facility.
- **`CompletionReflectionFacts.ResolveCompletionReflectionType` IS THE MEMBER SOURCE D3 ALREADY BUILT AND HOVER SHOULD REUSE, NOT DUPLICATE.**
  It turns a `TypeInfo` into a reflectable CLR `Type`, closes known generic definitions, and already refuses the two
  MLC hazards (a close the CLR throws on, and the poisoned `TypeBuilderInstantiation`). It has **no `ArrayTypeInfo` arm** —
  which is why `arr.Length` needs one. **FORK FOR THE COORDINATOR:** adding that arm to the shared resolver would also change
  `nlc query completions` on an array receiver (new `System.Array` members) and move the `tests/native/completion-engine`
  contract; keeping it hover-local does not. **ACCEPTED: hover-local** — `nlc query completions` output does not move twice in one batch,
  the `playground-tooling-surfaces` pins having only just moved for D3's accessor change.
- **`HoverHandler.cs` HAS ZERO RATCHET HEADROOM (307/307, 264/264 non-blank), SO THE FIX MUST SHRINK IT.** The declaring-type
  line cannot be added without paying for it. The payment is available and is the right direction anyway: `TryCreateKeywordOrPrimitiveHover`,
  `FormatTypeInfo`, `FormatVariable`, `FormatVariableWithSystemType` and `GetWordRange` are pure presentation and belong in an
  `EditorHoverFacts.nl` beside D3's `EditorCompletionFacts.nl`.
- **THE JSON SCHEMA QUESTION IS A REAL FORK.** `HoverResult` has four fields and `definedIn` is normalised as a FILE PATH
  (`OutputFormatterNormalizationKernels.NormalizePath`), so a declaring type must not be put there. The options are an
  additive optional `declaringType` key at `schemaVersion` 1 (the docs say the version increments on BREAKING changes, and an
  optional key is not one) or folding it into `signature`. **ACCEPTED: the additive key**, with `memory/components/cli-toolchain.md`'s
  hover example updated in the same slice. Measured afterwards and it makes the change cheap: `tests/fixtures/json-contract-root-keys.golden.json`
  pins only the SIX ROOT KEYS of the hover envelope (`schemaVersion`, `command`, `ok`, `file`, `position`, `result`), so a key added inside
  `result` moves no golden file at all.
- **XML DOC SUMMARIES ARE OUT OF SCOPE AND SHOULD BE FILED, NOT SMUGGLED IN.** The README's "Expected" asks for the API doc
  summary too; the May report did not have one either (it had signature + declaring type). A doc source exists — the `DocQuery*`
  family — but wiring it into hover is a second behaviour change with its own cost, and this slice should carry one.
- **THE HAZARD WAS REAL BUT BENIGN, AND BOTH UNIVERSES ARE NOW PINNED SEPARATELY.** `NullabilityInfoContext.Create` survives
  MLC members: `tests/native/query-integration` drives the real CLI, whose external types come from the `MetadataLoadContext`, and
  renders `DateTime AddDays(double value)` through it; the estate's `CodeIntelligenceSignatureKernels.tests.nl` renders the same
  shapes through live `typeof`s. Neither substitutes for the other, and the renderer declines to the bare line on any throw rather
  than failing the request.
- **`nlc query type` CHANGED TOO, AND IT IS THE SAME FIX BEING HONEST.** With a reflected arm on `MemberTypeInfoOfType`, a BCL
  member position now answers the MEMBER (`name: ToArray, kind: method`) where it used to answer the RECEIVER (`name: result,
  kind: generic`). No pin moved — `query-integration`'s own `HoverAndType ChainedMemberAccess` still gets `int` for `.Length`.
  **Follow-up, deliberately not taken:** `query type` still renders a method as the analyzer's `ToArray(...)` placeholder, because
  giving it the full signature too would be a second command's output moving in one slice.
- **DELIBERATELY NOT TAKEN, AND WORTH NAMING SO IT IS NOT MISTAKEN FOR AN OVERSIGHT.** (1) XML doc summaries for metadata members
  stay declined and filed. (2) Call-site overload PREFERENCE: where the analyzer recorded a method GROUP it could not narrow, the
  first overload is shown with `(+N overloads)` beside it — the arity-preferring path exists and is used where there is no recorded
  answer, but reaching the enclosing `CallExpression` from a member-access position would need a second public entry point on
  `AstNodeFinderCore`, which is API growth for a case the count already makes non-misleading.
- **HAZARD TO MEASURE BEFORE TRUSTING THE RENDER: `NullabilityInfoContext.Create` IS CALLED WITH NO GUARD.**
  `NullabilityMetadataReflection.CreateNullabilityInfoForParameter` has no try/catch, and the CLI's external types come from a
  `MetadataLoadContext` while the LSP's `TypeResolver` universe is live (§3.8). The analyzer already walks this path for external
  members so it probably survives, but a hover request must never throw — the renderer needs a decline-to-bare fallback, and the
  MLC-vs-live behaviour must be measured on both surfaces rather than assumed.


**Durable findings (EMIT-REGRESSION).**

- **One function held 95 % of the compiler's emit time, and two independent measurements agree on it.** `ColumnarExternalTypeCatalog.TryGet` opened and disposed a whole `ExternalAssemblyScanResult` — 27 `Assembly.Load`s, an `AssemblyName.GetAssemblyName` file-open per reference path, a fresh `MetadataLoadContext` over ~196 paths, a `LoadFromAssemblyPath` per entry — on **every cache miss**, 2,952 times for one build. `Prepare` already opened one and disposed it on the next line, so the fix was a change of LIFETIME, not new machinery.
- **The cost is per (files × distinct external names × reference-set size), which is why only the SDK sees it.** The task hands the compiler MSBuild's whole `@(ReferencePath)`; the CLI hands it `project.yml`. Any future emit-cost measurement taken through `nlc build` on a corpus project is measuring a different machine.
- **`OpenWithReferences` was quadratic inside itself, twice**: `TryLoadExactRuntimeAssembly` walked every loaded assembly per reference path calling `Assembly.GetName().FullName` (~169 × ~110 AssemblyName constructions per scan), and its `Assembly.LoadFrom` fallback GREW that list, so each later scan's inner loop was longer. Indexing the snapshot by identity is first-wins and therefore behaviour-preserving by construction, and it is worth **2.8× on the scan itself (30.2 → 10.7 ms)** — but once the scan is retained it runs ONCE per emit, so **it is defence, not the win**. Keep it anyway: the quadratic returns the moment anything re-opens a scan.
- **RSS is the price and it is worth paying: 597 MB → 1,030 MB.** One retained `MetadataLoadContext` costs about 430 MB of mapped metadata; building and tearing down 2,952 of them cost 2.1 M page reclaims and 20 s of `sys` time. **RSS was also the decoy that hid this for two months** — the July fix had made peak RSS look healthy, and it stayed healthy right through the regression.
- **The July note's named first suspect is measured and small.** The per-member scratch arrays in `ColumnarProgramInputBuilder` are the whole of `TryBuildMultiFile`, which is **6,142 ms of 143,319** — 4.3 %. Do not spend a slice there expecting seconds.
- **The 015-B door arc is exonerated.** The shape entered at `6110bbbcf` on 2026-07-10, two days after the 3.4 s measurement, and is untouched by every A- and B-sub-slice since.
- **`resolvedOwners.Count` is the scan counter, free and exact.** Any future question of the form "how many times did the emitter ask the external world something it had already been told" is one reflected field read after the emit. It reported 2,952 before the fix and 2,954 after (the +2 are my own two edited files' new type references), which is also the proof that the fix changed WHEN the answer is computed and not WHAT it is.
- **A harness outside the repo reproduces the SDK task exactly.** `MultiFileCompiler`'s emit-only path is reachable by reflection over a built `Compiler.dll` + `NSharpLang.Compiler.BootstrapServices.dll`; its output differed from the SDK's own `obj/Debug` assembly by **18 bytes** (2-byte PE timestamp at `0x88`, 16-byte MVID), which both proves the harness faithful and fixes the byte-identity tolerance for every future emit comparison.
- **RETRACTED MID-SLICE, and worth recording as a method lesson: an apparent emit nondeterminism was my own edit.** Two "baseline" runs produced assemblies of different size and I recorded it as a product defect; the second run had simply read the source files AFTER I patched two of them, because the harness reads source at thread start, not at launch. The determinism control run properly (same owner, same source, two processes) is **18 bytes**. **Never compare two emits across an edit to the compiler's own sources — the compiler's sources ARE the corpus.**

**Durable findings (GATE-SPEED).**

- The 2026-09-01 `sdk-emit-only` evidence had already measured the disease and named it -- "the SDK build of an N# project has no incremental skip" -- and nobody had read it. Its 132.84 s no-op is the number this slice moves to 0.58 s.
- **A separate datum for 015 item 1 (emit-path regression): the TESTS-INCLUDED emit of BootstrapServices costs 271,659 ms (273.27 s), almost exactly 2x the 132,461 ms product-only emit.** Item 1 owns seconds-per-emit and now has two points on its curve, not one; this slice owns emits-per-run (8 -> 4). The compile-time gate is untouched by this slice -- it spawns `nlc build`, not MSBuild, so an SDK-level skip cannot move its number or mask a regression in it.
- **The saving reaches the gate ONE GENERATION AFTER this merge.** The packaged `NSharpLang.Sdk` 0.1.0 is what every N# project actually compiles through, so the closing step is the coordinator's SDK republish: repack, place in BOTH `~/.nuget/local-feed` (the one consulted) and `~/.nsharp/packages`, purge the cache entry, then verify through the PACKAGED SDK that the 0.58 s no-op and the tests-flip re-emit both reproduce. run5 simulated exactly that by seeding the run's own dep-dir copy with the bytes Step 4's pack produces; no product feed was packed and no dep dir retains them.
- **One owner for the emit cost, split on two independent factors.** The 015 order’s item 1 (emit-path regression) owns *seconds per emit* — where the 132.6 s for 172,653 lines lives, N# input builder vs C# host. GATE-SPEED owns item 5, *emits per gate run* (6–7 → 3). Neither subsumes the other and neither blocks the other: item 1 landing at, say, 40 s still leaves 4 redundant emits, and this slice landing still leaves every first-of-configuration emit paying item 1’s full cost. Do not re-file either as a duplicate of the other; the compile-time gate (`tests/fixtures/compile-time/bootstrap-build-baseline.golden.json`, median ×1.5) is item 1’s instrument and is untouched by this slice — it spawns `nlc build`, not MSBuild, so an SDK-level incremental skip cannot move its number or mask a regression in it.
- Three independent arithmetic checks agree that Step 2 is exactly two emits, Step 3's pre-test portion exactly one, and Step 4 about two. The gate's step timeline is explainable almost entirely by counting emits.
- The re-emit is not self-contained: it rewrites `BootstrapServices.dll`, which is a `ProjectReference` input to `Compiler.csproj`, so the C# `CoreCompile` of Compiler/Cli/LanguageServer/Tests is invalidated too. `b16/gate.log` reprints the same four `CS8604` warnings on every invocation, which is what that looks like.
- `tests/TestSdkFeed.cs` runs a **second, private** SDK feed build inside the unit suite (`build Build.Tasks -c Release`, `pack Runtime`, `pack Sdk`) — a full Release emit that duplicates gate Step 4. Its cache lives under `Path.GetTempPath()`, and the isolation wrapper remaps `TMPDIR` into the discarded run dir, so it is **always cold** in the gate and always thrown away.
- Concurrency is bounded by shared state, not by cores: every MSBuild invocation writes the same `obj/Debug` of BootstrapServices (two lanes there is a data race), `$CLI_DLL` is a hard barrier after Step 2, and `$LOCAL_FEED` (`$HOME/.nsharp/packages`, with `HOME` remapped so it starts empty) is a hard barrier after Step 4. Step 3c must stay exclusive and last.
- Ratchet headroom is the real constraint on script-level fixes: `tests/scripts/test-all-core.sh` 916/917 (**1 line**), `tests/scripts/test-all.sh` 567/567 and `Sdk.targets` 206/206 (**0 lines**), `.github/workflows/build.yml` 81/81 (**0**). `EmitIlAssembly.cs` has 38 lines of headroom but growing C# is against the ownership direction — the fix belongs in MSBuild XML. OWN003 forbids a new `.slnf`, a new workflow file, or a new shell script, and trips on evidence left inside the byte-copy.
- The naive incrementality key is a **correctness trap**: `NSharpExcludeTests` toggles `.tests.nl` into the *same* `IntermediateOutputPath`, and those files are older than a just-built product-only assembly, so a plain timestamp `Inputs`/`Outputs` would silently skip Step 3a's tests-included emit. The key must be a stamp file named by a hash of the resolved source set + `project.yml` + references + SDK tool version.
- Recommended order: (0) make the SDK's N# emit incremental — ~532 s, no gate-script line pressure, and it fixes every developer's inner loop too; (1) share ONE packed feed between `TestSdkFeed` and Step 4 — ~150 s; (2) lane concurrency in `test-all-core.sh` behind a flag with disjoint obj dirs — ~180–240 s but 1 line of headroom, so it must pay for itself in deletions; (3) give CI the cheap deterministic steps it lacks (format contract, native estate, example chain) rather than the whole gate — ubuntu-latest cannot host 3c or the compile-time gate, and its `machine` baseline pins "Apple M4"; (4) commit-mode artifact reuse is subsumed by (0) and is not worth weakening "fresh isolated" for.

**Durable findings (IDE D3).**

- **THE PARITY COMPARATOR IS THE SLICE'S REAL PRODUCT.** `Completion_MemberAccess_MatchesQueryCompletionsAsync` builds a real
  project on disk, asks `CompletionEngine.GetCompletions` and the LSP `CompletionHandler` the SAME two positions, and asserts the
  sorted `label:lspKind` lists are EQUAL. It runs in-process because `Tests` already references `Compiler`; a `tests/native/*`
  comparator was measured and REFUSED — no native project reaches `LanguageServer.dll`, the gate's Step 2 never builds it
  (`Cli.csproj` and the playground only), and a `dll:` dependency that is absent on a clean run is a contract that passes
  vacuously. Buying it would have cost `test-all-core.sh`'s LAST line (916/917).
- **THE `get_`/`set_` LEAK WAS A CLI DEFECT TOO, so "LSP == CLI" was only worth asserting once both were right.**
  `BuildReflectionMemberItems` read `GetMethods` with no filter, so `nlc query completions` on a `string` receiver offered
  `get_Length` and `get_Chars` beside `Length`. The predicate is `IsSpecialName` and NOT a `get_`/`set_` prefix test — the
  contract proves the difference with `op_Equality`, which a prefix test would keep and the flag drops. Recorded as a CHANGED CLI
  OUTPUT, pinned in `tests/native/completion-engine`.
- **THE ESTATE CAUGHT A FALSE CLAIM IN THIS SLICE'S OWN COMMENT, which is what the contracts are for.** `MemberSortText` padded
  ranks to FOUR digits and the comment asserted "a rank past the pad still sorts after every padded one". It does not: an LSP
  `sortText` is compared as TEXT, so `"10000"` sorts BEFORE `"9999"` and the tail of any list past ten thousand items reverses.
  The pad is now TEN digits — `int.MaxValue`'s own width — so the failure has no representable input.
- **THE FALLBACK TIER IS LOAD-BEARING AND THE TWO OLDEST MEMBER TESTS PROVE IT.** `Completion_MemberAccess_NSharpClassAsync` and
  the CLR-collision variant open `file:///test/...`, which has no `project.yml` and no workspace root, so the snapshot lookup
  answers false. They pass unchanged, which is the evidence that a loose buffer still completes.
- **NOTHING IN THE C# SUITE ASSERTED THE BROKEN BEHAVIOUR, which is why 133 `LanguageServerTests` let D3 ship.** The one test at
  the defect's own position, `Completion_AfterDot_NoIdentifierAsync`, asserted only `Assert.NotNull(completions)` — it could not
  have failed. It was deleted as genuinely weaker; the five `Completion_Snippet_*Async` tests were collapsed into one `[Theory]`
  over the same five (label, placeholder) pairs as REDUNDANCY removal, not weakness, and every placeholder they asserted is
  still asserted.
- **`editors/vscode/test/suite/completion.test.ts` carried an EMPTY `MEMBER COMPLETIONS (DOT ACCESS)` banner** and every row of
  that suite sits at its ceiling, so the repro was paid for by dropping `no duplicate labels in completion list` — a 10 %
  tolerance that pins nothing — for a trailing-dot test on the fixture's own project path that asserts exact members and kinds,
  no scope identifiers, no keywords, ZERO duplicates and no accessors.
- **THE RATCHET'S ONE-LINE HEADROOM SHAPED THE DESIGN, not the other way round.** A `FindProjectCompletions` sibling in
  `DocumentManager.cs` is ~9 lines against 1 line of IMMUTABLE epoch headroom, and OWN004's epoch clause cannot be repinned away.
  The visibility flip moves no metric, so only that row's fingerprint changes and the reviewed head does not move on its account.
**Durable findings (FORMAT-RULE SPLIT).**

- The two halves of `1e192a8c2` touch DISJOINT owners, which is why the split is mechanical: the rule is
  `FormatterWalkState.nl` + `Formatter.nl` + their two contract files; the widening is
  `FormatCommandKernels.nl` + its contract file + `tests/CliParityAuditTests.cs` + the two ratchet keys.
  No hunk had to be edited in place — every file is either wholly kept or wholly restored, except the two
  contract files' single reformat-class blank line.
- **A blank line the formatter writes itself is not free.** `HasBlankLineBefore` holds a SOURCE line, so
  any unconditional output line must advance that baseline or every later gap reads one too wide. The
  three separators were the only such lines in `Format`; the guard on zero keeps "nothing emitted yet"
  meaning that, so the file's opening cannot become a phantom gap.
- The fix is a NORMALISATION, not a deletion: a head that already carried the blank and one that did not
  now format to the same text (ONE blank line), and a head with TWO blank lines still keeps both — which
  is the spelling the entire contract estate is written in and which must not move.
- **`FormatSafe`'s idempotence gate hid the defect behind a green gate.** The formatter never corrupted
  `ColumnarIteratorPlanner.tests.nl`; it DECLINED it, and a decline reports nothing. A safety gate that
  refuses a file silently is a defect detector whose output nobody reads.
- The estate's `Fst*` helpers all passed a NULL comment list, which drops every comment in the file — so
  no existing contract could reach a bug whose whole shape is where a comment lands. The
  `FstSafeComments*` trio is the pipeline `nlc format` actually runs, and it is the reason the rule is
  pinnable at all.
- Three files' header blank line (between the head comment block and the FIRST declaration) is dropped by
  `Format`'s `index > 0` guard regardless of this rule — it is reformat-class, not rule-class, and is
  left for the estate reformat to take with everything else.

**Durable findings (FORMAT-WRAPPING).**

- **The hug's test is about the OUTPUT, not about the grammar, and that distinction is the whole slice.** "Every element starts on the opening line and the last one will be written across lines" is the rule; "the last one is a wrapped list" is the plausible-sounding version that fails on callbacks. `ExpressionSpansLines` therefore enumerates exactly the arms of this walk that emit a newline — a wrapped list, a block-bodied lambda, an expression-bodied lambda over one of those, an `on` subscription, a `match` — and nothing else. The test is deliberately SHALLOW: `f(a + g(\n x))` wraps rather than hugs, because recursing through arbitrary operators buys little and is not obviously idempotent. If a future shape is found torn apart, the fix is one more arm here, and the estate sweep is the instrument that finds it.
- **A one-line list cannot contain a comment, so no comment clause is needed — and adding one is actively harmful.** A `//` comment runs to the end of its line, so the flat shape is never at risk. The only cheap "is a comment inside this list" test is "is it between the two delimiter lines", and that cannot tell a comment standing between two ARGUMENTS from one inside a nested lambda body; it fired on the latter and tore a hugged callback apart. What survives is the useful half: a list that is ALREADY wrapping emits the comments standing between its elements, above the element that follows.
- **The gap tracker has to be re-based INSIDE a wrapped list or every interior comment grows a blank line above it.** `EmitCommentsBefore` asks `HasBlankLineBefore`, which measures against `LastEmittedSourceLine` — still holding the line before the STATEMENT when the walk is halfway down an argument list. Set it to the opening line on entry and to each element's line as it is emitted; this is the same discipline the statement and member loops already use, and without it the two comment contracts fail with a spurious blank line.
- **The formatter can emit a wrap the parser then refuses, and the failure mode is silent.** `IsContinuationRecoveryBoundary` ends an argument list at a continuation token that begins a statement, a declaration or a modifier. `ref` is a declaration keyword (`out` is not), so a wrapped `ref` argument makes the output unparseable, `FormatSafe` returns the ORIGINAL source, and the file stops being formatted with only a warning. The wrap is refused for `ref` instead. The same boundary means a wrapped element must sit strictly right of the line that opened the list — the canonical shape indents one level past it, so every wrap this rule emits reads back.
- **`EndLine` was already the right field and cost nothing to reuse.** It exists on `AstNode`, is stamped for statements and declarations, is read only there, and DEFAULTS TO `Line`. Stamping it on the five list nodes right after the closer is consumed is five call sites; the default is what makes hand-built trees read as single-line, so every AST-built contract in `Formatter.tests.nl` and `FormatterWalk.tests.nl` kept its expectations and the new behaviour is stated where it belongs — against source, in `FormatterSourceText.tests.nl`.
- **A `new` carries TWO independent lists and the initializer must be anchored on its own brace.** It was anchored on the `new` keyword, so `new Foo(\n a) { X: 1 }` read as a wrapped INITIALIZER when only the arguments had wrapped. The fix moved 19 golden `Golden.ObjInit` anchors and the wording of four contract names that had pinned the old anchor as the intended behaviour. `AstEq.Diff` compares `Line`/`Column` but not `EndLine`, which is why the five stamps moved no golden test at all.
- **The columnar backend declines a property assignment whose receiver is a FIELD** (NL103, node kind 23) — `state.LastEmittedSourceLine = x` does not emit, `tracker := state` then `tracker.LastEmittedSourceLine = x` does. Every pre-existing write of that property in the formatter is already spelled through a local, for this reason; it reads as a style until you try the other spelling.
- **N# HAS NO TRAILING COMMAS, so the canonical multi-line form ends with a bare last element.** One in an argument list or array literal is NL101 and in a parameter or type-parameter list NL102 — the opposite of Go, where gofmt requires one. `FormatEnum`, `FormatTest`'s case rows and the `match` arms already wrote it this way; `FormatSafe`'s reparse gate is the backstop that would have caught a violation as a whole-file no-op.
- **The indexer's `this[…]` does not round-trip and that is PRE-EXISTING, not this rule's to fix.** The formatter writes `this[i: int]: T` while the grammar reads `func this[i: int]: T` — the "pinned INDEXER case" the estate's format gate already records. So the indexer's square delimiters and its wrap are contracted directly on `AppendParameterList`, not through a source round-trip. A parameter list is also the one kind whose closer the parser does not stamp, so it wraps on its ELEMENT lines; the two tests differ only for a dangling closer under a complete first line, a shape that appears nowhere in the estate.
- **Owed follow-ups, both deliberate.** (1) `FormatterWalkState.Snapshot`/`Restore` and `FormatterPositionSnapshot` are now CALLERLESS — the measurement pass they served is gone — and are kept for one slice only because a sibling was editing that file; delete them with the estate reformat. Do not give them a new caller: a snapshot around anything that can emit a comment rolls the cursor back and emits that comment twice, which is exactly why the inline initializer path no longer uses one. (2) **The visual format-on-save confirmation in VS Code is owed and is NOT a blocker** — zero lines of Language Server, LSP handler or extension code change (`DocumentFormattingHandler.cs` calls the same `Formatter.FormatSafe`), so the backend gate covers the code path exactly; the IDE-verify session takes it in the same pass as the D3 re-verification.

### 4.11 Task 022 — one external type universe, and a NativeAOT `nlc`

| slice | commit | what moved | durable finding | numbers |
|---|---|---|---|---|
| 022/1 — the AOT capability floor (measurement only) | this commit (branch `stream/022-s1-aot-floor` off `385b7e8d1`) | ZERO product files. One probe (`…/probes/aotfloor`, 970 lines, outside the repo) run on CoreCLR and on a published Mach-O arm64 NativeAOT binary, over runtime types AND `MetadataLoadContext` types; the full table, the adjudicated `ilc` ledger and every red's verbatim exception are in `systems-language-closeout/decodes/2026-09-02-aot-capability-floor-decode.md`. The census tool was rebuilt first (`memberscan2`, MemberRef-table only) because the old one crashes | **The whole persisted-emit pipeline is green under NativeAOT over MLC types — including the EXECUTABLE path — and exactly ONE emit API is red: `CustomAttributeBuilder` cannot be CONSTRUCTED (`PlatformNotSupportedException: Dynamic code generation is not supported on this platform.`), in both universes and for every argument shape. Its substitute is measured green: `SetCustomAttribute(ConstructorInfo, byte[])`, the raw-blob overload, PASSES on both hosts in both universes — and it simultaneously removes an independent MLC wall (`CustomAttributeBuilder` type-checks arguments against the RUNTIME `typeof(string)`, so an MLC-cored builder cannot write an attribute with arguments at all). One change closes both** | 408 joined cells. CoreCLR 387 PASS / 0 AOT-RED / 1 TRIM-RED / 10 RED / 13 n/a; NativeAOT 345 PASS / **9 AOT-RED** / 36 TRIM-RED / 18 RED / 13 n/a. Native binary 3,842,376 B; `ilc` 99 warning lines, **0 errors**; 25 `IL3050` adjudicated → 23 false positives, 2 real (both `DefineDynamicAssembly`, the control, **0 estate sites**), 3 unadjudicated. Census re-derived: **132** distinct reflection members (131 at `8cf40128a`, +`MethodBase::get_IsFinal`) and **128** distinct emit members. Emit surface 124 distinct opcodes (C# 100 / N# 112, union) over 1,197 + 114 sites |

**Durable findings (022/1).**

- **`CustomAttributeBuilder` is the only emit API NativeAOT forbids, and the estate has four sites.** `ColumnarIlEmitter.cs:4117` (`IsByRefLike`), `:4960` (`IsReadOnly`), `:5882` (xunit `Trait`, two string args) and `:5883` (`Fact`). The throw is in the BUILDER'S CONSTRUCTOR, so an AOT `nlc` would lose ref-struct/readonly-struct attributes and every emitted test attribute. `SetCustomAttribute(ConstructorInfo, byte[])` is the fix and is measured PASS on both hosts and in both universes — do not reach for rooting, a fallback or a second emitter.
- **The EXECUTABLE emit path works under NativeAOT, and the proof is a program that ran.** `GenerateMetadata` → `PEHeaderBuilder.CreateExecutableHeader` → `MetadataRootBuilder` → `ManagedPEBuilder.Serialize` → `BlobBuilder.WriteContentTo`, keyed on `MethodBuilder.MetadataToken`, all PASS; the native binary wrote a 2,560-byte executable from an **MLC-cored** builder and `dotnet exe-mlc.dll` printed its string. `Save(stream)` (the library path) likewise, read back clean through a fresh MLC. All 124 union opcodes, all five region openers, `DefineMethodOverride`, `DefinePInvokeMethod`, enums, properties, generic parameters and constraints: PASS.
- **Under NativeAOT a member lookup on a BCL runtime type returns NULL, and calling the member does not help.** `typeof(string).GetMethod("Concat", …)`, `Int32.MaxValue`, `String.Empty`, `String.Length`, `Array.Empty<>`, `IDisposable.Dispose`, `System.EventHandler` and `AppDomain`'s events all resolved to null — in a second run that statically calls every one of them, with no `[DynamicDependency]` and no `rd.xml`. The estate's `Type.GetMethod` (33 sites), `GetField` (19) and `GetProperty` (23) over runtime types would therefore **mis-bind silently**. Over MLC types every one of them reads a metadata file and is immune. This is the measured case for slice 2.
- **Reachability is smaller than feared where slice 5 actually needs it.** Reflecting over the compiler's OWN objects is green (`PropertyInfo.GetValue`, `MethodInfo.Invoke`, `GetProperties()` — the twenty AST sites), `Type.GetType` is green in all four probed shapes including a bare own-type name, and a never-called BCL method (`string.PadLeft(int,char)`) still resolved. Trimming is per-member and not predictable from source; the failure mode is a null, never an exception.
- **`AppDomain.CurrentDomain.GetAssemblies()` does not throw under NativeAOT — it returns 1.** A silent one-entry universe is worse than a throw: `ExternalAssemblyScan.Loaded()` would mis-bind rather than fail. `Assembly.LoadFrom` throws `PlatformNotSupportedException`, `Assembly.Load(AssemblyName)` throws `FileNotFoundException: … No metadata found for this assembly.`, and **both `Assembly.GetEntryAssembly().Location` and `typeof(object).Assembly.Location` return `""`** — confirming that `ExternalAssemblyScan.nl:132`'s `metadataPath := runtimeAssembly.get_Location()` feeds the metadata context nothing under a single-file binary.
- **The MLC-inherent red set is SEVEN members, not the four on record.** Added: `MemberInfo::IsDefined` (2 sites) and `ParameterInfo::IsDefined` (2 sites) — both convert to a `GetCustomAttributesData()` scan, measured green — and `Type::get_TypeHandle` (2 sites), which has no substitute. `FieldInfo::GetRawConstantValue` and `ParameterInfo::get_RawDefaultValue` are green; `PropertyInfo::GetValue` (9 sites) has **no** metadata substitute. Two members are red on RUNTIME types under AOT and green on MLC types — `MemberInfo::get_MetadataToken` (throws `InvalidOperationException: There is no metadata token available…`, 4 sites) and `Module.Name` (returns `"<Unknown>"`) — so the single-universe move fixes them rather than costing anything.
- **`Type::GetTypeFromHandle` is N/A-by-construction and the floor says so in those words.** It is `typeof(X)`; an MLC type has no `RuntimeTypeHandle`. At 1,516 call sites it is the estate's heaviest reflection member and runtime by construction in every one. "One type universe" therefore means the EXTERNAL catalog is single-sourced — the builder stays runtime-cored (`ColumnarIlEmitter.cs:3991`). Measuring slice 2 against the stronger reading would be measuring it against an impossible bar.
- **A warning is never a verdict, and the discrimination has to be mechanical.** 99 `ILC :` lines, 0 errors, `TrimmerSingleWarn=false` required or the ledger cannot be keyed. Of 25 `IL3050`: `Type.MakeGenericType` (8), `Type.MakeArrayType()` (7), `MethodInfo.MakeGenericMethod` (4) and `Enum.GetValues` inside `EnumBuilderImpl..ctor` (1) are FALSE — each PASSes in the NativeAOT column; only `DefineDynamicAssembly` (2) is REAL, and it is the control with **0 estate sites**; 3 (`MakeArrayType(int)`, multi-dimensional) are UNADJUDICATED and named. `IL3000` on `Assembly.Location` is real and confirmed by execution. Two instrument traps: a `PublishAot=true` project bakes `IsDynamicCodeSupported=false` into its ORDINARY build output, so the CoreCLR host must be built `-p:PublishAot=false` or the whole CoreCLR column falsely reds; and the previous decode's `memberscan` **crashes** (`InvalidCastException` at the `MemberReferenceHandle` cast) on a current build — its hand-rolled IL walker mis-sizes an instruction, so the 131 could not be re-derived with it.

## 5. Remediations, corrections, do-not-relitigate verdicts

Two ratchet remediations, one mid-arc reconciliation and the wave-one product-defect chip fixes, recorded as rows:

| record | commit hash(es) | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| CHIP DECODE + FIX: the documented `skip` form fails to emit (2026-09-01) | filed by 021 slice 7; closed on `stream/chip-skip-form-emit` off `50bebbd6b` | **THE DEFECT REPRODUCED, IT IS TWO DEFECTS, AND BOTH FIXES ARE TAKEN — NEITHER BUILDS THE CAPABILITY.** (b) `AnalyzerDeclarationWalkers.AdvanceTest` phase 0 gains `ReportUnsupportedSkipClause`: a `TestDeclaration` carrying a `SkipReason` is refused as `NL323` (`ErrorCode.FeatureNotImplemented`, whose published sentence already reads *parsed for forward compatibility, not available in production builds yet*) at the declaration head, 4 columns wide, with a suggestion. (a) The docs stop promising the form: `cli-reference.md`'s Go/Rust row scored it **`5`** and now reads `None`; `for-go-developers.md`'s "Setup & Skip" example is deleted; `language-tour.md`'s "Skip Tests" becomes "Skipping a Test" and shows the DIAGNOSTIC, not a copyable sample. `memory/testing.md`'s two skip claims are rewritten. Contracts: 4 estate blocks + 4 native blocks (end-to-end `nlc test`, the delete-the-clause control, a docs scanner over every N# code fence in both spellings, and the `cli-reference` score row). **ZERO C# lines touched** | **THE FILED HALF WAS THE SMALLER HALF, AND THE ARCHIVE'S SUPPORTING CLAIM IS HALF FALSE.** Measured on a worktree CLI built at the tip: `nlc test` over the documented form exits 1 with exactly one sentence — `This product path requires successful N# columnar emission after analysis passes.` — no code, no line, no column, no reason; JSON answers `ok:false`, `error: "Test build failed."`, **`total: 0`**, so the PASSING test beside it is destroyed too. `NSHARP_COLUMNAR_DECLINE_LOG=1` shows `parse.declaration-scan … span=0:9`, but only to whoever knows the variable. The scan that refuses it is `ColumnarParserKernels.TopLevelTestHeaderEndsAt`: after the description it accepts an optional `with` table clause and then REQUIRES `{`. **But `nlc check --json` reporting `ok:true` does NOT show the form analyses cleanly — `nlc check` does not analyse `.tests.nl` AT ALL** (`checkedFiles: 0`, and it stays `ok:true` with a plain `NL001` in a test body — control probe). That is why the diagnostic had to come from the analyzer walk `nlc test`'s own build runs, which is also the only place a position exists. **Doing only (a) leaves the bare decline; doing only (b) leaves `cli-reference` scoring an unbuildable form `5`.** 020/2's ruling is untouched: §3.7's `PROVEN UNNECESSARY: skip` bullet is unchanged and nothing added emits, skips or reports a skipped test. SEPARATE PRE-EXISTING DEFECT SEEN IN PASSING, NOT FIXED HERE: every coloured CLI diagnostic writes the LITERAL bytes `\x1b[1;31m` instead of ESC (`od -c` on the captured stderr, present identically before the change) — worth its own chip | before/after `nlc test` on the same 2-test probe: one unlocated sentence + `total: 0` → `NL323 … Probe.tests.nl:7:1` with a 4-wide caret under `test` and a help line, and the old sentence ABSENT; control `probe-plain` 1/1 passed on both. `nlc check --json` BootstrapServices before/after **404 files / 243 rows / 243 errors, ROW-FOR-ROW IDENTICAL**. Estate `dotnet test` after a full `-p:NSharpExcludeTests=false --force-evaluate` restore: **7,226/7,226, Failed 0**, against a stash-baseline of **7,222/7,222** — exactly +4, the new blocks. `tests/native/cli-command-contracts` **84 → 88**, ok true. Full `nlc test` sweep of all **40** native projects: **1,798/1,799**, and the ONE red (`analyzer-clean-source`, an `undefined type names` block from the chip integrated AT `50bebbd6b`) is PRE-EXISTING — proved by stash-baseline, a CLI rebuilt with the arm removed fails the identical block, and the project contains ZERO occurrences of `skip` so the arm cannot fire in it. Four other sweep reds were HARNESS artifacts, not product: `ownership-audit` (18/18) and `query-integration` (65/65) need cwd = repo root, and the two `playground-*` projects (116/116, 19/19) need `NSharpLang.Playground.dll` built. `./scripts/dev.sh --since` selected the FULL unit suite: **596/596, exit 0**, 13m45s. 8 files, **+292/−21**, 0 C# |
| CHIP FIX: `nlc tidy` bare-prefix deletion (020 slice 43's data-loss finding, pinned-as-measured) | `stream/chip-tidy-bare-prefix` off `8cf40128a` | `TidyCommandKernels.RemovalLineStartsWithPackage` compared `packageName.Length` characters and checked NOTHING after them; it now also requires the name to END on the line — the next character may not continue a package id (letter, digit, `.`, `-`, `_`, `+`) — and an empty doomed name matches nothing. The pinned BARE-PREFIX block is CONVERTED to pin the correct behaviour; 4 estate blocks and 1 native block are added (positive, negative, idempotence, empty name, and the end-to-end `--fix` rewrite) | THE CHIP'S TITLE IS WRONG AND THE ARCHIVE IS RIGHT: `nlc tidy` NEVER deletes an `import` — it rewrites `project.yml` DEPENDENCY LINES, so NL010's owner (`LinterNamespaceImportUsage`, a namespace→known-type-name table) answers a different question and cannot be consulted. The CLASSIFIER side was already delimiter-correct (`NamespaceMatchesPrefix` requires `.` after the first segment); only the REMOVAL side was not. The blast radius reached lines tidy never classified: `TidyCommand.RemoveDependencies` hands the filter EVERY line of the file | Zero C# delta (the `tidy` CLI surface is one dispatch arm, `Program.cs:52`); `+194/−20` over 3 `.nl` files. Estate `Passed: 7196, Failed: 0`; native cli-command-contracts `Passed: 84` (83 + 1). Mutation panel (revert the kernel, keep the tests): **5 predicted red, 5 measured red, 0 unpredicted**, the three negative controls green. Before/after `tidy` + `tidy --fix` sweep over 19 `project.yml` (examples/ + BootstrapServices): **0 report divergences, 0 rewrites** |
| RATCHET REMEDIATION of the two chip commits (2026-08-02) | `6658e8304` (nlc-check `NotImplementedException` on receiver-style generics), `c78ea1f22` (formatter safety-check failures) — amended mid-remediation to `c8b9964e1`; idiom precedent `1142885be`; head `head-v1:65015a9692586d08` → `head-v1:8265394c9ce3a302` | Both fixes STAY; both landed WITHOUT ratchet accounting, so the audit failed with **10 violations across five tracked files**. `tests/CheckCommandTests.cs` 721/618/112 → 674/573/101 (exactly at its 674-line ceiling); `tests/ColumnarDeclineDiagnosticsTests.cs` 245/218/32 → 212/184/27 (exactly at its 212-line AND 27-marker ceilings); three fingerprint-only repins (`ColumnarIlEmitter.cs`, `Formatter.cs`, `tests/FormatterTests.cs` 2,134 → 2,132 under the approved-shrink rule) | Paid with LOSSLESS comment compression plus SUBSUMPTION-PROVEN assertion consolidations only — no test, no assertion subject and no program fixture deleted. `Assert.False(result.Success)` was deliberately KEPT at all four sites because `MultiFileCompilationResult.Success` is an INDEPENDENT constructor-supplied bool, NOT derived from `Errors`, so `Assert.Single(NL103 errors)` does NOT subsume it — the tempting fifth consolidation was REJECTED on that proof. | audit 18/18 (all 10 OWN004/OWN005 cleared); manifest still EXACTLY 391 lines; `epochPathFingerprint`/`epochFactFingerprint` BIT-IDENTICAL; 381-row sweep 0 drifted rows; unit 3,194/3,194; contracts 2,046/2,046 |
| RATCHET + PARITY REMEDIATION of `170244a5f` (2026-07-29) | `170244a5f` "Fix infinite loop in ParseTestDeclaration table-case recovery"; head `head-v1:1be7f7cb4c07e417` → `head-v1:682bbdb2c76e50c8` in BOTH the manifest and the mirrored `OwnershipPolicy.ReviewedHeadFingerprint` constant | A CORRECT fix by a separate session that (a) exceeded the IMMUTABLE E0 epoch ceilings on both files and (b) skipped the N# parity mirror — audit failed with 6 violations (OWN004+OWN005 each) and broke the integration gate. Paid: `Parser.cs` 7,128/6,192 → 7,116/6,180 and `ParserErrorTests.cs` 1,944/1,609/568 → 1,923/1,588/563; `ColumnarParserRecovery.nl`'s `ParseTestDeclaration` table-case loops gained the same no-progress guards + 4 parity contracts | The owner's `ConsumeToken` does NOT advance on mismatch either, so the N# mirror REPRODUCED THE HANG FAITHFULLY — a parity mirror inherits the defect unless it carries the same guard. Zero-functional-change was proven by stripping every whole-line comment and blank from HEAD and from the compressed file and showing the remaining 5,872 code lines BYTE-IDENTICAL. | audit 18/18; contracts 1,442/1,442 (1,438 + 4); NET non-N# change −33 lines across two C# files; all new code is N#; no VS Code gate owed (no production/LSP wiring change) |
| 020 reconciliation (slice 43) | slice cut at `e929453e0`; reconciled over chip commits `2d2ddb39d`, `0a66db6ec`, `1e426e07d`, `65c02f471`, `fa6ed3214` | No C#→N# movement: a coordinator reconciliation onto a tip four concurrent chip commits had moved. `tests/TestSdkFeed.cs` losslessly compressed back under its epoch ceiling (326/287 → 324/284, markers unchanged at 3); `NSharpLang.Sdk.csproj` and `test-all-core.sh` repinned as reviewed drift | `LanguageServer.csproj`'s drift was a PHANTOM: the file carries a UTF-8 BOM, the audit reads utf-8-sig, and a plain-utf-8 reader hashes the BOM into a false drift. RULE: ratchet tooling must read utf-8-sig, and the manifest's header keys are colon-space formatted while rows are compact — REGEX the stored head, never string-match it. | contracts 2,897/2,897 (chip baseline 2,865 + slice 32); head `f66e4eda5ec3d44a` → `b283a83ef600d146`, mirrored; audit 18/18; manifest 391 lines, no BOM |
| CHIP FIX: false `NL001` on `off` reads (2026-09-01) | branch `stream/chip-nl001-off-reads` from `8cf40128a` | `LinterWalk.nl` gains an `OffStatement` arm, a `MatchExpression` arm and `VisitPattern`/`VisitPropertyPatterns`; `VisitSwitch` now walks each case's `Pattern`. `LinterWalk.tests.nl` gains 6 contracts. `Analyzer.cs` is UNTOUCHED — the linter is already wholly N#-owned (`Linter.nl` -> `LinterWalk` -> `LinterWalkState`), so no C# delta was needed or taken | THE CHIP'S PREMISE WAS WRONG AND THE DEFECT IS WIDER THAN FILED. `off` is NOT a switch form: `e929453e0`'s own message says "off is NOT switch's other half but an EVENT statement", and `OffStatement` (`Statements.nl:285`) carries ONE slot, `Handle: Expression`, for which `VisitStatement` simply had NO ARM. The SAME class of miss sits in the pattern family, MEASURED not assumed: `VisitSwitch` walked a case's STATEMENTS but not its `Pattern`, and `AstChildrenCore.AddMatchCaseValues` hands a match case its `Guard` and arm `Expression` but not its `Pattern` — and a `RelationalPattern`'s compared value is a PRIMARY expression, so `case > limit =>` is a read of `limit` that BOTH forms lost. ONE rule closes all three: every expression an operand slot carries is a read. | 3 false NL001s deleted, 0 added. Probes: `off sub`, `switch case > limit` and `match > limit` each go NL001 -> gone; controls `print(sub)` and `if value > limit` were and stay clean; a `dead` local beside an `off` is STILL NL001. Corpora row-for-row IDENTICAL before/after — BootstrapServices `check` 403 files, `lint` 45 rows (NL012 20 / NL011 17 / NL010 7 / NL002 1); examples 79 files, 0 rows; `tests/native` 0 rows |
| CHIP DECODE + FIX — "undefined type names silent at declaration sites" (2026-09-01) | filed by 020 slice 35 (`06fdb2fd4`), listed in §1 at `40e0cc20e`; closed on `stream/chip-undefined-type-names` off `8cf40128a` | THE FILED DEFECT IS WITHDRAWN. Re-measured on BOTH analyzer entry points, twenty-two declaration positions already reported `NL201` — nullable/non-nullable/array-element/generic-argument/static field, parameter (plain, `out`, `ref`, constructor, method), return type, local annotation, struct field, interface member, catch clause, union-case payload, type alias, property, `new`. Two SMALLER holes the wrong finding hid are FIXED in N#, zero C# lines touched: `AnalyzerTypeResolver`'s `ResolveTypeIfPresent`/`ResolveTypeReferences` — the base class, the interface and base-interface lists, and the `where` constraint types — were wired to the lenient `ResolveType` even though BOTH owners' doc comments already claimed they reported, and a LOCAL function never resolved its constraint types at all (`AnalyzerFunctionBodies` phase 2 now does; the cycle check stays top-level-only). The estate's "REAL GAP" paragraph is rewritten and a 40-block `undefined type names at declaration sites` family added — the first thing in either estate to pin this subject at all | **THE PROBE NAME WAS THE BUG, AND IT IS THE WHOLE FINDING.** All five of 020/35's probes spelled the undefined type `Missing`; `System.Reflection.Missing` is a REAL BCL type the simple-name external probe resolves with no import, so every probe measured a RESOLVING type and not one tested the claim (`Missing.Value` reads cleanly off it). The corroborating sentence collapses identically: `Variable 'x' is typed as 'Missing', but the value is 'int'` is an ORDINARY `NL202` against a real type, never a phantom naming — with a name that resolves nowhere the `NL201` arrives IN FRONT of it. Do not re-file. Second finding: A DOC COMMENT CLAIMING A DIAGNOSTIC IS NOT EVIDENCE ONE FIRES — both fixed holes were guarded by comments that already described the report they did not make. Third: the base-class fix MOVES a diagnostic from the emitter's late `could not be resolved` decline to a front-door `NL201` with name, caret and help line, which `tests/native/external-base-interface` had pinned on the emitter side | 40 new contract blocks (22 reporting positions / 18 silences incl. the artifact) + 2 existing contracts repinned onto the corrected behaviour; `tests/native/analyzer-clean-source` 928 → 968 cases; estate `dotnet test` **7,192/7,192** after a full `-p:NSharpExcludeTests=false --force-evaluate` restore; `dev.sh --since` selected the FULL unit suite and passed **596/596**; all 40 native projects **1,793/1,793**; `nlc check --json` on the worktree CLI after the fix: `BootstrapServices` 403 files / 243 rows / **ZERO NL201**, `examples/` 18 projects / 39 files / **ZERO rows**, `tests/native`+`templates`+`benchmarks` 46 projects / **ZERO NL201** — no new true or false positive on any real project; 2 `.nl` owners changed, 0 C# lines |
| CHIP DECODE + FIX: "parse failure after a bare member access" (2026-09-01) | filed by 021 slice 2, listed in §1 at `40e0cc20e`; closed on `stream/chip-parse-bare-member-access` off `50bebbd6b` | `ColumnarParserRecovery.IsCastExpression` and the `ColumnarParserKernels` cast arm (`ParsePrimaryExpressionNode`, kind 127) now BOTH require the cast operand to begin on the CLOSING PAREN'S OWN LINE. The recovery test is spelled INLINE because that class is at the per-class member ceiling (§2.1); the kernel gets one new free function, `ParserSourceHasLineBreakBetween`, which answers false when `st.Source` is empty so the six expression-only entry points that build a source-less `ParserState` keep their prior reading. 8 contracts into `ColumnarParserStatements.tests.nl`. ZERO C# lines | **THE CHIP'S TITLE NAMES THE SYMPTOM; THE TRIGGER IS THE CAST DISAMBIGUATION, AND THE MEMBER ACCESS IS INCIDENTAL.** N# has no statement terminator, and the C#-inherited `(Name)operand` rule read straight through the newline: `nlc query ast` on `print(x)` + `sum := 0` showed a `PrintStatement` whose value is a `CastExpression` with `targetType` `SimpleTypeReference "x"` on line 3 and `expression` `IdentifierExpression "sum"` at **line 4 column 5** — the next statement's first token, inside the previous statement's tree. So `print(x)`, `y := (x)` and `v := (c.Count)` all broke identically; the shape is any PARENTHESIZED expression that scans as a type name at end of line. The archive's two controls decode mechanically: a member CALL leaves the paren unclosed as a type (`ScanCurrentType() != RightParen`), and `print(sum)` puts a KEYWORD after the `)` which `IsCastOperandStart` refuses. A real argument list `g(a.B)` was NEVER affected — its `(` is a postfix call, not an expression-primary paren. **A BARE MEMBER ACCESS AS A STATEMENT WAS ALREADY CORRECT**: `c.Count` alone parses and reports `NL313 This expression statement has no effect`, which is the diagnostic the grammar owes; nothing about it needed changing. **THE ONE-LINE FORM THE ARCHIVE WROTE THE PROBE IN IS STILL A CAST AND THAT IS THE RULED ANSWER** — N# does allow several statements on one line (`x := 1  y := 2  print(x + y)` is clean), so on one line the grammar is genuinely ambiguous and the cast reading is the C#-parity answer; the canonical formatter puts ONE STATEMENT PER LINE, so no formatted program can reach it. **ADJACENT GAP, MEASURED NOT ASSUMED**: `ParseExpressionStatement`'s tuple-deconstruction scan crosses lines the same way (`a, b` then `c := 3` binds `c` as the `:=` token), but it can only fire on already-invalid source — a valid statement never starts `Identifier ,` unless it IS a deconstruction — so it is recorded, not fixed | `+17/−4` recovery, `+31/−1` kernels, `+125/−0` contracts; 0 C# lines, no ratchet repin owed (the manifest carries zero `.nl` rows). Estate `dotnet test` **7,230/7,230 Failed: 0** after a full `-p:NSharpExcludeTests=false --force-evaluate` restore, against a MEASURED `50bebbd6b` baseline of 7,222 — exactly the 8 new blocks, so no inherited block moved. `dev.sh --since` classified all three paths UNMAPPED and fail-safed to the FULL unit suite: **596/596, Failed: 0** (19 m 57 s), which is where the 2,021 rerouted C# parser assertions run. Probes: p1/p5/p6/p8 five errors (`NL001`+2×`NL301`+`NL101`+`NL313`) → **0**, and `nlc run` prints the right values; controls p2 (member CALL), p3 (declare first), p7 (real call), p9, p10 (`(int)x`) clean BEFORE and AFTER; p4's `NL313` unmoved. Non-vacuity measured against the baseline CLI on the contract sources themselves: `print(a.B)`+`g()` was ONE statement whose cast operand was the whole next-line call, now two. `nlc check --json` before/after with the two CLIs: **44 projects BYTE-IDENTICAL** — BootstrapServices 404 files / 243 rows row-for-row, examples+templates 48 files / 3 pre-existing `NL402` rows, `tests/native` 0 (check never sees `.tests.nl`). 38 native projects green incl. `parser-literal-facts` 22/22; the two reds (`analyzer-clean-source` 967/968, `ownership-audit` 17/18 `OWN008`) REPRODUCE on the pristine `50bebbd6b` tree with the baseline CLI and are inherited |

### Chip decode + fix — the systems policy accepts unresolved members (chip 6 of the 14 filed at §1)

| record | commit hash(es) | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| CHIP DECODE + FIX — "systems policy accepting unresolved members" (2026-09-01) | filed by 020 slice 41 (`7584d5334`) as the estate's own headline; closed on `stream/chip-systems-unresolved-members` off `50bebbd6b` | `SystemsCallPolicy.nl` gains **`MemberIsPositivelyRejected`** — the analyzer's own recorded UNKNOWN at the callee's position and NOTHING weaker — and **`MarkDeclaredCalleeDischarges`**, the door the RESOLVED half of the walk uses; both ledger-discharge members take a `SemanticModel?`. **`SystemsAnalyzer.cs` is NET ZERO LINES** (1,156 / 1,061 before and after): one two-line `CallSites.Add` reflowed to one line pays for the one routed discharge, and the other three edits are in place, so the ratchet is a FINGERPRINT-ONLY repin — `text-v1:fa452c617450b471` → `text-v1:e7ac66c49f2493b9`, head `58190ee65270a462` → `a903462163326da5` in BOTH keys, with the stored head reproduced exactly from the unmodified manifest first. Estate: the pinned block CONVERTED plus 3 new census blocks (resolved dispose, resolved return, `allow` waiver) and 4 new + 8 repinned `SystemsCallPolicy` contracts | **THE CHIP IS REAL AND IT INVERTS: the only `Dispose()` the resource rule accepted was one that DOES NOT EXIST.** Measured on the shipped CLI, outside the repo. `stream.Dispose()` on a project class with no members closed the ledger AND suppressed NSYS050 (`findings=0`) while `NL303: Member 'Dispose' not found` was reported; the SAME source with `func Dispose()` really declared reported `NSYS090 … is not disposed` and NOTHING else — a false negative on broken source and a false POSITIVE on correct, compiling source, from one rule, and the pool ledger has the identical pair (`pool.Return(buffer)` resolved → NSYS130; `Zqxwvut.Return(buffer)` unresolved → silent). **The mechanism is ORDER, not the table**: `WalkCall` records a resolved project call and RETURNS, so the discharge — which sits after that return — was reachable only on the UNRESOLVED path. **The answer is (b) and (a) together and it needed no new code**: refusing to classify restores the walk's own NSYS050 fall-through, so the systems policy reports the call in the sentence it already owns while NL303/NL301 keep reporting the member. **The rejection test is deliberately the narrowest one that works** — a recorded UNKNOWN only; a resolved member and a position with nothing recorded are both permissive — which is what keeps `File.OpenRead(path)` + `stream.Dispose()` discharging and keeps two machines classifying alike, the determinism the owner's own header demands | 9 out-of-repo probes, base CLI vs fixed CLI: `Dispose` absent `findings=0` → NSYS090+NSYS050; `Dispose` declared NSYS090 → **clean, exit 0**; `.Return` resolved NSYS130 → **clean**; `Zqxwvut.Return` silent → NSYS130; and 5 controls unmoved (`Zqxwvut()` member, undisposed, unreturned, BCL `File.OpenRead` dispose + its undisposed twin). Waiver proved narrow: `unknownExternalCalls: allow` drops the restored NSYS050 and keeps the NSYS090. Corpora row-for-row on the SAME tree, base CLI vs fixed CLI: BootstrapServices `check --json` 404 files / **243 rows, 0 diff**; `examples/` 15 projects **0 diff**; **all 21 `docs/design/systems-samples/proofs` systems reports byte-identical** (33/34/35 are the ones that dispose and return for real). Estate `dotnet test` after a full `-p:NSharpExcludeTests=false --force-evaluate` restore: **7,226 / 7,226**, the 4 new contracts confirmed by name; native `systems-analysis-census` **66/66** (63 + 3), `systems-gauntlet-facts` **13/13**, `systems-proof-corpus` **44/44**, `ownership-audit` **18/18** |
| CHIP DECODE + FIX — "NL309 coverage" (2026-09-02) | filed by 020 slice 33 (`17f093780`), listed in §1 at `40e0cc20e`; closed on `stream/chip-nl309-coverage` off `50bebbd6b` | **THE FILED ARM WAS NEVER BROKEN.** `new Counter { value: 2 }` over a `readonly` field reports `NL309` and always did — the mutation that broke 0+0 tests measured an ESTATE gap, not a dead owner, and four contracts (class, INHERITED field, struct, record) now pin that arm's sentence for the first time in either suite. Probing the rest of the surface NL309 is specified for found THREE real holes, all fixed in N# with **zero C# lines touched**: (1) the bare-name channel read `ambient.CurrentClass`, a slot typed `ClassDeclaration`, so a STRUCT or a RECORD writing its own `readonly` field was silent for all three reports — `AnalyzerAmbientContext` gains a `CurrentTypeMembers` slot that `AnalyzerTypeDeclarations` moves for every type form alongside the NAME it already moved; (2) `InConstructor` was a sticky bool that NESTED BODIES inherited, so a local function or a block lambda inside a constructor got the constructor's exemption — `EnterNestedBody` now clears it and `ExitNestedBody` restores it, the frame going from eight values to nine; (3) widening (1) would have spread a PRE-EXISTING class-only FALSE POSITIVE — a local or parameter shadowing the field was accused of the write the LOCAL received — so the bare-name channel now asks `AnalyzerScopeStack.BindsToLocalOrParameter` first (`this.`-qualified writes are never asked; `value` is deliberately a shadow here, unlike `IsValueBinding`) | **A MUTATION NON-MOVER NAMES A SUITE, NOT AN OWNER.** Slice 33 read "mutating the object-initializer arm breaks nothing" as a live-but-unpinned owner and filed it as coverage; it was right about the estate and the chip title pointed at the one arm that WORKED. The reproduce-first pass is what turned a test-coverage chip into three product fixes. **ROSLYN IS THE ARBITER AND IT WAS CONSULTED BEFORE A LINE MOVED**: a four-case `csc` oracle outside the repo returns `CS0191` for a lambda in a ctor, an anonymous delegate in a ctor, `X = n` in a struct method and `this.X = n` in a struct method — all four of which N# accepted, two of them (`record` bare and `this.`) compiling **completely clean, `ok: true`, zero rows**. **A SILENCE BESIDE A DECLINE IS STILL A SILENCE, AND MUST BE WALK-PROVEN**: three probes reported only `NL103` (a columnar decline), which could have meant "analysis never ran" — appending a deliberate `NL202` to each body proved the walk reached the write and chose not to report it. **ONE SHAPE IS PINNED AS MEASURED, NOT FIXED**: an EXPRESSION-bodied lambda inside a constructor stays silent while the identical lambda in a method reports. It is the only nested body the driver does not bracket with `EnterNestedBody` (`DriveLambda` brackets step kind 5, the BLOCK body, and hands an expression body straight to the expression walk), so closing it needs `AnalyzerLambdaAnalysis` to hold the ambient context — one argument added at `Analyzer.cs::CreateLambdaAnalysis`, which is C# GROWTH plus a two-key ratchet repin. Reported, not taken. | 4 `.nl` owners + 3 `.tests.nl` + 1 native contract file; **0 C# lines**, so no ratchet repin is owed. Estate `dotnet test` **7,231 / 7,231, Failed: 0** after a full `-p:NSharpExcludeTests=false --force-evaluate` restore (baseline 7,222 + 9 new blocks: 3 ambient, 4 scope-stack, 2 write-targets). `tests/native/analyzer-clean-source` 968 → **991 blocks** (+23: 15 positives, 7 negatives, 1 measured-not-endorsed), 990 pass; the 1 failure is PRE-EXISTING and proven so — the BASELINE tests file against the FIXED binaries reads 967/968 with the same single failure, a stale rich-route `NL202` sentence pinned by the undefined-type-names chip before the four-arg chip merged. Probe battery 34 projects outside the repo: **8 shapes flip silent → `NL309`** (struct bare / `this.` / `++` / static, record bare / `this.`, lambda-in-ctor, local-function-in-ctor), **13 already-reporting shapes byte-identical**, **7 negatives silent** (2 of them previously FALSE POSITIVES). `nlc check --json` before/after with baseline-built vs fixed CLIs, row-for-row: `BootstrapServices` **404 files / 243 rows IDENTICAL** (NL202 85, NL402 65, NL905 26, NL012 20, NL011 17, NL301 16, NL010 7, NL303 3, NL412 3, NL002 1; ZERO NL309 either side), `examples/` **18 projects / 41 files / 0 rows IDENTICAL** — no new true or false positive on any real project |
| CHIP DECODE + FIX — "locale-sensitive estate blocks" (2026-09-02) | filed by 021 slice 6 (`80a6e3027`), listed in §1 at `40e0cc20e`; closed on `stream/chip-locale-estate-blocks` off `50bebbd6b` | THE FILED THREE WERE THE VISIBLE HALF OF SEVEN, AND FOUR OF THE SEVEN DEFECTS ARE PRODUCT, NOT CONTRACT. Contract side: six estate boxed-value renderers (`ColumnarCodePlanConversions`, `ColumnarCodePlanExecutor` ×2, `ColumnarBoundIdentifierPlanner`, `ColumnarAddressableDirectCall`, `ColumnarDirectCallConstructedConversions`) now render through `Convert.ToString(x, CultureInfo.InvariantCulture)`, and NINE expected-side renders that read the culture too — `ColumnarScalarLiteralPlanner`'s decimal helper (signature `expected: decimal` → `expectedText: string`, 7 call sites), `ColumnarPrimitiveBinaryPlanner` ×6, `ColumnarBoundIdentifierPlanner` ×2 — are pinned as MEASURED invariant text. Product side, all in N#: `LinterConfig.TryParseSeverity`/`IsDisabledSeverity`/`NormalizeRuleCode`, `ErrorSuggestions.IsPossibleTypo`/`FindSimilarType` (5 folds) and `ErrorSuggestionHelpers.ScoreSimilarity` (2 folds) fold invariantly; `ProgramCommandKernels.GetUnknownCommandMessage` TAKES OVER the fold `Program.cs` used to do with `args[0].ToLower()`. One emitter line: `ColumnarIlEmitter.TestDescriptionToMethodName`'s `char.ToUpper` → `char.ToUpperInvariant`. +4 contract blocks and +6 rows; two-key ratchet repin | **A CONTRACT THAT RENDERS BOTH SIDES CANNOT FAIL ON A RENDERING BUG, AND THAT IS WHY THE FILED COUNT WAS THREE.** Fixing the three named blocks turned FOUR previously-green blocks red under de-DE: each asserted `RunPlan(x) == (2.5).ToString()`, so both halves moved with the culture and cancelled. The de-DE failing set is therefore 3 VISIBLE + 4 MASKED, and only an invariant actual side exposes the masked four. **SECOND, THE CHIP'S TITLE UNDERSTATES IT: THE LOCALE REACHED THE PRODUCT.** A Turkish culture was never run before and it found what de-DE could not — `LinterConfig` case-folded `.editorconfig` severity keywords with the CURRENT culture, so `SILENT` folded to a dotless-i word, matched no disable keyword, and A RULE THE USER DISABLED STAYED ON; and `ColumnarIlEmitter` PascalCased emitted test-method names with `char.ToUpper`, so the compiler wrote a DOTTED capital I into CLR method names and `nlc test --json` reported different names on a Turkish machine. **THIRD, THE COMPILER-AS-GUARANTEE CLAIM (021/6) HOLDS ONLY WHERE `CultureInfo` IS SPELLED.** `CultureInfo.CurrentCulture` is still unbindable, but a bare `.ToLower()`/`.ToUpper()`/`.ToString()` needs no `CultureInfo` at all and compiles everywhere — the wall stops the explicit bug and not the implicit one | estate 7,222 → **7,225**, and **7,225/7,225 under en-US AND de-DE AND tr-TR** (before: en-US 7,222/0, de-DE 3 failed, tr-TR 4 failed; after the actual-side fix alone, de-DE and tr-TR each showed the 4 masked blocks). Native: 46 projects, `cli-command-contracts` 84 → **85**, **identical in all three cultures**, and the tr-TR method names came back ASCII (`ItIsAn`, previously `İtİsAn`) — the emitter fix proved by the run itself. Ratchet: 2 fingerprint-only rows (`Program.cs` HOLDS 786/682, `ColumnarIlEmitter.cs` HOLDS 20,784/19,768 — zero C# growth), two-key head `head-v1:58190ee65270a462` → **`head-v1:9994cd7babcc411d`**, replica validated PRISTINE-FIRST by reproducing the old head over all 381 rows, manifest 391 lines / 3 changed lines / no BOM, epoch triple untouched, audit **18/18** and non-vacuous (one-key flip → 17/1). `nlc check --json` 404 files / 243 rows **row-for-row IDENTICAL** before and after. INHERITED reds at `50bebbd6b`, unchanged by this slice: `analyzer-clean-source` 967/968 (a stale `Type mismatch` pin the four-arg-`Analyze` chip superseded) and `nlc format --check` on `NativeImportSignatureFacts.nl` + `ErrorMessageBuilder.nl` |
| CHIP DECODE + FIX — playground vs `nlc run` divergences (2026-09-02) | filed by 021 slice 11 (`26c88d266`), listed in §1 at `40e0cc20e`; closed on `stream/chip-playground-run-divergence` off `50bebbd6b` | **Five of the seven measured divergences are playground defects and all five are fixed in the N# owner.** `PlaygroundRunFacts.nl` (+62/−35): `DivisionByZeroMessage` becomes the CLR's own `Attempted to divide by zero.`; NEW `DivisionFaults(useIntegerDivision, divisor)` so ONLY integer division by zero faults; `NumericEqualityTolerance` DELETED and `NumbersEqual` is now `left == right`; `ObjectDisplayText`/`UnionDisplayText` are re-signatured onto NEW `QualifiedTypeDisplayText` + `NestedTypeSeparator` and now answer the CLR type name, with `DisplayFieldSeparator` and `ObjectFieldDisplayText` DELETED alongside the structural shape they served. `PlaygroundRunner.cs` is **939 → 939 lines, zero ratchet growth**, and every edit is mechanical routing: `Divide` computes the integer-division flag first, the constructor walks units so each type keeps its DECLARING FILE's namespace, `RuntimeObject`/`RuntimeUnion` carry it, and `JoinFields` dies with the shape it built. 9 new blocks in `tests/native/playground-tooling-surfaces`, 2 estate contracts converted onto the corrected behaviour + 1 added | **THE PLAYGROUND IS NOT WRONG ON ALL SEVEN, AND WHICH SIDE IS RIGHT HAD TO BE MEASURED ONE AT A TIME.** On `"n=" + 1` the PLAYGROUND IS RIGHT and the compiler has the gap: `nlc check` answers `NL103 … Declined at emit.print.expression`, an EMIT decline, and the analyzer reports NOTHING — which is exactly why the playground, which runs the analyzer and not the emitter, executes it. Four spellings decline (`string+int`, `int+string`, `string+double`, `string+bool`) and two emit (`"a"+"b"`, `$"n={n}"`), because `ColumnarPrimitiveBinaryPlanner` plans `+` as `String.Concat` only when the UNIFIED operand type already IS `string`. That is a columnar-emit coverage slice, not a playground fix, and copying a decline into the runner would have created the second spelling this campaign exists to remove. Second finding: **THE INFINITY SYMBOL WAS NEARLY A SIXTH FIX AND IS NOT ONE.** After the double-division fix the playground printed `Infinity` where `nlc run` printed `∞`; running `nlc run` ITSELF under `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` printed `Infinity`, byte-identical — the delta is the runner's DELIBERATE invariant-culture policy (documented at `NumberFormatSpecifier`, so a `de-DE` browser still sees `0.5`), not a divergence. Third: **THE UNCAUGHT-THROW FRAME CANNOT BE CLOSED AND IS PINNED AS A RESIDUE** — `nlc run` aborts with `Unhandled exception.`, a stack trace and exit 134 for EVERY uncaught throw (measured on `throw new Exception("boom")` too), and a browser tab has no process to abort and no stack to walk; only the SENTENCE was matched. Fourth, the one operative rule: **ROUTE, DON'T RESTATE** — the namespace precedence (`package` beats `namespace`) is NOT respelled in the playground, the runner calls the compiler's own `AnalyzerDeclarationFileFacts.GetUnitNamespace` | estate `dotnet test` **7,223/7,223** after a full `-p:NSharpExcludeTests=false --force-evaluate` restore, against a baseline measured at `50bebbd6b` of **7,222** (+1 = the new `DivisionFaults` block); `tests/native/playground-tooling-surfaces` **19 → 28**, `playground-diagnostic-spans` **116/116** unchanged; `nlc check --json` on `BootstrapServices` before/after — **404 checkedFiles / 243 rows, ROW-FOR-ROW IDENTICAL** (NL202 85 / NL402 65 / NL905 26 / NL012 20 / NL011 17 / NL301 16 / NL010 7 / NL303 3 / NL412 3 / NL002 1); all **10 shipped playground examples byte-identical** before/after, including the two that fail for the two sibling chips' reasons; 6 probes re-measured on BOTH sides against the worktree build — 5 moved onto `nlc run`'s answer, 1 deliberately unmoved; `PlaygroundRunner.cs` 939 → 939 lines |

### Chip decode — playground vs `nlc run`: the seven divergences, verdict by verdict

Every row re-measured at `50bebbd6b` against the worktree-built `NSharpLang.Playground.dll` and the
worktree-built `Cli.dll` in a real `project.yml` project. **All seven reproduced**; none was withdrawn.

| # | probe | playground BEFORE | `nlc run` | root cause | verdict |
|---|---|---|---|---|---|
| 1 | `6 / 0` (int) | exit 1, `division by zero` | exit 134, `System.DivideByZeroException: Attempted to divide by zero.` | `DivisionByZeroMessage` invented its own wording for a CLR-defined condition | **PLAYGROUND WRONG — FIXED** (sentence now identical; the abort frame is a named residue) |
| 2 | `6.0 / 0.0` | exit 1, `division by zero` | exit 0, `∞` | `Divide` faulted on ANY zero divisor, ignoring that only INTEGER division by zero is undefined | **PLAYGROUND WRONG — FIXED** (the only divergence that broke a program the compiler runs) |
| 3 | `0.1 + 0.2 == 0.3` | `True` | `False` | a 1e-7 tolerance inside `NumbersEqual` | **PLAYGROUND WRONG — FIXED** (equality is now exact) |
| 4 | `print` a record | `Point { X: 1, Y: 2 }` | `P.Point` | `ObjectDisplayText` invented a structural shape no N# program can produce | **PLAYGROUND WRONG — FIXED** (renders the CLR type name) |
| 5 | `print` a union value | `Shape.Circle(Radius: 3)` | `P.Shape+Circle` | `UnionDisplayText`, same cause; a union case is a NESTED type | **PLAYGROUND WRONG — FIXED** |
| 6 | `"n=" + 1` | prints `n=1` | `NL103`, declines at `emit.print.expression` | `ColumnarPrimitiveBinaryPlanner` plans `+` as `String.Concat` only when the unified operand type IS `string`; the ANALYZER accepts the program | **PLAYGROUND RIGHT — COMPILER GAP; REMAINDER** (a columnar-emit slice, not a playground fix) |
| 7 | union match, shorthand `{ Radius }` | `PG208` | `circle 3` | — | **NOT TOUCHED** — owned by the sibling `playground union shorthand` chip |

- **The record-`ToString` question is the live language fork behind rows 4 and 5, and it is named, not
  taken.** C# synthesises a structural `ToString()` for a `record`; N# does not, so `nlc run` prints
  `Object.ToString()`. The playground now matches the language AS IT IS. If N# later synthesises one,
  these two rules move with it — they are already defined in terms of the CLR type name rather than a
  bespoke shape, so there is one place to change.
- **Do not re-derive the namespace in the playground.** `package` beating `namespace` has exactly one
  spelling, `AnalyzerDeclarationFileFacts.GetUnitNamespace`, and the runner calls it. Measured on four
  headers: `namespace P` → `P.Point`, `package Tutorial` → `Tutorial.Point`, `namespace A.B` →
  `A.B.Point`, no header at all → the bare `Point`.
| CHIP FIX: playground union shorthand (021 slice 11's shipped-example defect, pinned-as-measured) | branch `stream/chip-playground-union-shorthand` off `50bebbd6b` | NEW `AnalyzerPropertyPatternBinding.BoundName(property)` — the ONE answer to "what name does this property pattern bind" — and its three consumers routed to it: `NextStep` (object patterns), `AnalyzerPatternAnalysis.AdvanceUnionProperties` (union arms) and `PlaygroundRunner.PatternMatches`. The C# host is line-neutral (`3/3`, 939 lines / 817 non-blank UNCHANGED) and purely mechanical — its own arm is replaced by a call to the compiler's owner. 4 estate contracts + 5 native contracts (`playground-tooling-surfaces` 19 → 24 blocks); ratchet repinned on ONE row, fingerprint only | **THE PLAYGROUND WAS THE THIRD SPELLING OF ONE RULE AND THE ONLY WRONG ONE.** `BindingName ?? Name` was already spelled twice in the analyzer; the runner spelled it `BindingName != null` — and NO parser production sets `BindingName` (`ParsePropertyPatterns` passes null for the nested form AND the implicit `{ value }` form alike), so the runner's binding arm was DEAD CODE: `Found { name, score }` bound nothing while `Found { name: n, score: s }` bound correctly. The columnar emitter never had the bug because it has no `BindingName` concept at all — `EmitUnionCasePropertyPattern` binds `propertyName` directly. Second finding: the ARM ORDER differed too (the runner tested the binding name FIRST, both compiler owners test the nested pattern first); unobservable while `BindingName` is always null, aligned anyway. Third: **the defect was ONE-SIDED** — `RunProject` runs the analyzer before it executes anything, so a genuinely invalid union spelling already produced the compiler's own `NL503` at the compiler's own span on both paths; the playground only ever refused programs the compiler ACCEPTS, never the reverse | Repro at `50bebbd6b`: playground `PG208@1:1+1` "could not resolve 'name'", exit 2, stdout `""` vs `nlc run` exit 0 `Ada: 99\nMissing player #404\n`; after, identical on both. **8 of 10 shipped examples declare an `ExpectedOutput` and 8/8 now produce it** (04 was the only miss). Mutation panel (revert the one C# routing line, rebuild the playground only): tooling-surfaces 24/24 → **21/3**, **3 predicted red / 3 measured red / 0 unpredicted**, the 2 negative-control blocks green, `playground-diagnostic-spans` unmoved at 116/116, the corpus sweep flipping **exactly one row** (`04-unions-patterns` → `PG208`); control B restores 24/24 and a corpus byte-identical to control A. Estate `dotnet test` **7,226/7,226** (baseline 7,222 + 4). Native: tooling-surfaces **24/24**, diagnostic-spans **116/116**, ownership-audit **18/18**. `nlc check --json` before/after over 50 projects — **441 checked files / 246 rows / 0 differing rows**, identical exit census (BootstrapServices 404 files / 243 rows both sides) |

### Product-defect chip DECODED AND FIXED: the four-argument `Analyze` degrades diagnostics

| record | commit | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| chip `four-arg Analyze degraded diagnostics` | `stream/chip-analyze-four-arg`, cut at `8cf40128a` | `ErrorMessageBuilder.TypeMismatch` gains a `message` parameter; its SIX callers (`AnalyzerVariableDeclaration`, `AnalyzerConstruction`, `AnalyzerAssignment`, `AnalyzerTypeDeclarations`, `AnalyzerAccessorBodies`, `AnalyzerBooleanConditions`) hoist their sentence above the rich/plain branch. Estate repinned to the CORRECT shape, not the measured one | **The degradation was never in `Analyze` — it was in the BUILDER.** The four-arg route is the RICHER walk everywhere except the headline: it alone reaches `ReportBuilt(ErrorMessageBuilder.TypeMismatch(...))`, and that builder wrote its own `Message` because the two disagreeing NAMES are not among its arguments. So the only route that ships traded its sentence for a snippet. Fixed by passing the sentence, not by touching either entry point | 1 owner + 6 call sites; 60 estate rows repinned (56 `analyzer-clean-source`, 2 `analyzer-semantic-model`, 6 playground rows, 2 in-project) + 5 new contracts; 3 C# LSP assertions moved with the product; 9/9 probe NL202s now name what disagrees with what |

- **The two entry points are NOT the defect and must not be "unified".** `Analyze(unit)` delegates to
  `Analyze(unit, null, null, null)`; the whole difference is that the four-arg form feeds
  `_diagnostics.BeginAnalysis(path, source)`. Anchors, `SourceSnippet` and `ContextualHint` are all
  BETTER on the four-arg route and stay that way — the plain route is handed no text and cannot
  measure a token, which is why its anchor length is 1. Only the MESSAGE was a regression.
- **`Analyzer.cs` needed no change.** Both entry points are mechanical; the policy lives in the six N#
  owners. Zero lines of C# compiler code moved.
- **The generic `Suggestion` staying null on the rich route is NOT part of the defect.** `Report` fills
  `Ensure types are compatible or add explicit cast` from the CODE; `ReportBuilt` carries a specific
  `ContextualHint` instead. That substitution is a trade UP and is deliberately left alone.
- **Two of the four codes stay asymmetric ON PURPOSE.** `AnalyzerTypeDeclarations` and
  `AnalyzerAccessorBodies` report `InvalidSyntax` without source and `TypeMismatch` with it. That
  asymmetry is a separately recorded decision; only the sentence was unified.
- **The estate held the answer already.** Every rich row's corrected message was DERIVABLE from the
  plain row in the same block, because both routes now compute one string — 56 of 60 rows were repinned
  mechanically. The 2 rows GUESSED instead of derived were WRONG (`'T'` where the analyzer substitutes
  `'int'`) and were caught by running the fixture through the built CLI. Derive, never guess.
- **The ratchet moved because a C# TEST asserted the defect.** `tests/LanguageServerDiagnosticsTests.cs`
  pinned `Message == "Type mismatch"` at three LSP sites; metrics are unchanged (3182/2542/520) and only
  the fingerprint moved, `text-v1:7a4653509d2cea75` → `text-v1:d8abab82baac7f8a`, reviewed head
  `head-v1:9717a7390756f51c` → `head-v1:58190ee65270a462` in BOTH keys.

Corrections and standing verdicts, one line each:
- 2026-09-01 native-comparison: the dev Debug `NSharpLang.Runtime.dll` carries `DisableOptimizations` (SIMD helpers at minopts, 3–4× understated) so the runner installs the Release runtime; the `NSHARP_VECTORIZE_REDUCTIONS` opt-out has been dead since `1cef0d16e` and is pinned as such.
- 2026-09-01 compile-time: the first isolated gate went red because the bench's gate block printed one line ahead of its JSON envelope (Step 3a's `json.load` refused it — fixed, the block is silent on success) and because of the nuget IPv6 stall; measurement waited 2 h 23 min for other sessions' builds to stop — idle medians need every session holding.
- **The owner that walks reads for NL001** is `LinterWalk`
  (`src/NSharpLang.Compiler.BootstrapServices/LinterWalk.nl`): a read lands in
  `LinterWalkState.MarkVariableUsed` and NL001 is reported by `LinterWalkState.CheckUnusedVariables` when a
  scope pops. There is no C# read-walk left to change — the chip is a pure N# fix.
- **The canonical repro is the shape the feature documents**, not a synthetic one:
  `sub := on AppDomain.CurrentDomain.ProcessExit (sender, args) => { … }` followed by `off sub` reported
  `NL001 Variable 'sub' is declared but never read`, and NL001 is an ERROR, so `nlc build` refused the file.
- **A pattern's BINDINGS are deliberately NOT credited as reads.** `LinterWalkState`'s used-name set is
  file-wide, so crediting `case bound =>` would silence a genuine NL001 against an unrelated local named
  `bound`. A contract pins that, and it is why only expression slots are walked.
- **Adjacent gaps measured and left as separate chips.** `VisitStatement`'s "a shape with no arm is walked no
  further" is FAIL-OPEN where the expression walk's `AstChildrenCore.Of` THROWS: `AllocBlockStatement`,
  `AllowStatement` and `UnsafeBlockStatement` each carry a `BlockStatement` body and still have no arm. And a
  `TypePattern`'s `TypeReference` is still untracked, so an import used only by a type pattern is a false
  NL010 — the same probe shows a false NL010 on `import System` for an `on` target.

- **The tidy bare-prefix REPRODUCTION, so nobody rediscovers it.** A project whose `dependencies:` names an
  unused `Serilog.Sinks` and whose `testDependencies:` names `Serilog.SinksExtra` and
  `Serilog.Sinks.Console`: the table reports ONE possibly-unused dependency, the command prints
  `Removed 1 possibly-unused dependency.`, and the file loses THREE lines — the message and the damage
  disagree, which is what makes the end-to-end row able to fail at all. A repro CANNOT be built inside a
  single `dependencies:` list: the classifier keys on the FIRST SEGMENT only, so a package with a doomed
  name as a bare prefix always shares that name's first segment and therefore its status. The collateral
  only reaches lines tidy never classified (`testDependencies:`, `exclude:`).
- **A SECOND tidy finding is pinned as measured and deliberately NOT fixed:** the removal filter is not
  scoped to a dependency section — it is handed every line of `project.yml` and tests only for `- ` after
  the indent — so a `testDependencies:` entry naming EXACTLY a doomed package still goes. The whole-name
  rule bounds the blast radius to an exact match; section scoping is a separate product decision.
- **A THIRD tidy finding, measured while probing the fix and NOT fixed — `nlc tidy --fix` CORRUPTS the
  mapping form of a dependency.** A dependency written as `  - nuget: X` / `    version: 1.2.3` loses only
  the `- nuget:` line, because the filter's structural test is `- ` after the indent; the `version:` line
  survives as a stray mapping directly under `dependencies:`. Measured end to end: a two-dependency
  `project.yml` came back with `dependencies:` followed by a bare `    version: 1.0.0`. It predates this
  fix (the old and new matchers both remove exactly that one line) and is orthogonal to the prefix rule —
  fixing it means DELETING MORE, which is a separate product decision and a separate chip.

- **The Min/Max correction (`86f4c251b`).** Sub-slice 5's Min/Max deletion was PARTIALLY WRONG: "provably
  dead" held only for plannable receivers, while `Select(v => …).Min()/.Max()` whole-subtree-exits to the
  legacy residual where the deleted emit + preflight arms were load-bearing. The arms are RESTORED as
  fenced load-bearing residuals, and the standing rule is that **every byte-exact corpus sweep MUST include
  the `tests/native/*` projects** — the 59-assembly example/fixture sweep alone missed it and
  `tests/native/lambda-placement` failed to emit at the checkpoint gate. It was a compounding process
  failure: sub-slice 6's refutation of the identical premise for `ToArray`/`ToList`/`Contains` was applied
  RETROACTIVELY to slice 5 and nobody re-checked.
- **The `d2257f33c` refutation is GROUND TRUTH and must NOT be re-litigated.** `ToArray`/`ToList`/`Contains`
  has NO deletion-ready subset before lambda Stages 3–4: (1) the EMIT arms are load-bearing for lambda
  chains routed via the contextual-lambda decline (disabling ToArray makes WeatherDemo fail to build);
  (2) the PREFLIGHT arms are load-bearing for lambda return-type inference, and **only the byte-exact
  corpus IL diff catches the `List<IssueResponse>` → `object` regression — builds and the full unit suite
  do not**; (3) receiver widening is not admission-safe until user-source-extension precedence is modeled,
  because BCL `First`/`Last` shadow user extensions. The contracts baseline for that family is 740 (747
  with Stage 1), NOT 741 — the `ColumnarExtensionMethodResolver` widening test was reverted with the
  refuted slice even though the widening logic was proven correct in isolation.
- **The case-12 prune verdicts (`6e94ca88c`).** Four provably-dead case-12 residual sub-arms were deleted
  (bitwise and/or/xor, record-struct structural equality, the `null == null` fold, and the multi-term
  string-concat CHAIN), `ColumnarIlEmitter.cs` 21,534 → 21,438, with no N# owner added — the planners
  already own the plannable surface. Candidate (a), preflight static-call typing, was assumed dead and
  PROVEN LOAD-BEARING (it types the user's own enclosing-type statics, not catalog facts); candidate (b)
  kept three sibling arms (ternary, ref-identity equality, string+char) because a partial 166-arm
  instrumentation run called `stringcharconcat` dead and only the COMPLETE 228-arm self-emit caught it
  firing late — the slice-5 escape signature. Rerouting a load-bearing arm to a new planner is the
  forbidden add-a-planner-for-a-relocation anti-pattern.
- **Header entries never written** (record-keeping only; every slice's full record exists in its arc):
  020 slice 2 (COMMITTED `493a82eab`), 019 slice 21 (COMMITTED `e6aaf57cd`), 019 slice 16, 017 slice 34 and
  015-A5.
- **R1 is a deliberate difference, recorded and not changed** (`87afbcb39`): C#
  `t is GenericTypeParameterBuilder` admits only builder-backed parameters while N#
  `get_IsGenericParameter()` admits every generic parameter; the emitter only asks about types it resolved
  itself, R1 is invisible to all 90 corpus assemblies, and it is now pinned by a contract naming it as the
  deliberate difference it is.
- **The 021/12 `mechanical`-FAILS verdict is RIGHT in its verdict and WRONG in one of its four quoted
  exhibits** (`6fcb41f64`): `'base has only parameterized constructors'` at `ColumnarIlEmitter.cs:1124` is
  a `?? throw new InvalidOperationException(...)` inside `EmitCtorBaseChain` — an internal invariant that
  never reaches a user as NL103, the same class 021/12 itself accepted as mechanical elsewhere. The verdict
  (133 genuine declines) survives; the exhibit is corrected, and the decode also names a THIRD sentence
  class the closing record never had: 4 `OpCodes.Ldstr` literals baked into the USER's own IL, which retire
  with the lowering that emits them, not with an emitter-policy migration.

### Chip decode — the `LibraryImport` span-marshalling crash (chip 6 of the 15 filed at §1)

| record | commit hash(es) | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| CHIP FIX of the `LibraryImport` span crash (pinned as measured at 020/40) | branch `stream/chip-libraryimport-span` off `8cf40128a` | **The chip's wording is CORRECTED BY MEASUREMENT: the compiler does not crash.** It accepts in SILENCE — `nlc check --json` answers `ok: true` with zero rows and `nlc build` succeeds — and the EMITTED PROGRAM aborts. New N# owner `NativeImportSignatureFacts.nl` plus `AnalyzerAttributeValidator.ValidateNativeImportSignature` refuse a generic or a tuple in a `[LibraryImport]`/`DllImport` signature with `NL405`, naming the parameter and the repair; `27-c-library-cli` is respelled `byte[]`; **zero C# lines changed** | **Working span marshalling is not reachable without GROWING C#**: it needs a synthesized pointer-taking stub plus a pinning managed forwarder — new IL emission in `ColumnarIlEmitter.cs` (the retiring host) and new plan-row kinds in its executor. The docs never promised it: `website/docs/systems.md` scopes interop to "native interop via `LibraryImport`" with `fixed` and function pointers explicitly out. So the precise diagnostic is the in-scope answer, and it is now documented rather than merely enforced. `.ptr` inside a `[trusted]` block is NOT a substitute — it does not pin | throwaway repro OUTSIDE the repo through the worktree CLI: the span shape → exit 134, `MarshalDirectiveException: Cannot marshal 'parameter #1': Non-blittable generic types cannot be marshaled.` at `Repro.SpanImport.NativeHash.Hash64`; the byte-identical `byte[]` shape → exit 134 `DllNotFoundException` naming `fast_hash` from the same method, so the ARRAY marshals and only the library is absent |

- **The owner that throws is the CLR, not the compiler.** `ColumnarIlEmitter.cs:4457–4482` defines the stub
  with `DefinePInvokeMethod` and never asks whether the parameter types are marshalable; the first CALL is
  where the answer arrives. Every future question of this family — "can the runtime accept this shape?" —
  belongs in the analyzer, which can name the parameter, not in the emitter, which cannot.
- **A generic is refused for BEING generic.** `Span<byte>` and `Span<int>` fail identically, so a rule
  phrased around BLITTABILITY would be wrong; a tuple is the same refusal in other syntax (`ValueTuple<…>`
  in metadata). Nullability is deliberately not judged: the written type reference cannot tell `int?`
  (`Nullable<int>`, refused by the runtime) from `string?` (`string`, fine), and a guess would refuse
  marshalable code.
- **The `27` run block got STRONGER, not weaker.** It now pins `DllNotFoundException` raised from
  `NativeHash.Hash64` — only a GENUINE interop stub reaches `dlopen`, which is exactly what the deleted
  `AssertNativeImportHasNoManagedBody` was trying to say and what the marshaller failure never proved. A
  refused shape cannot also be a shipped sample, so the negative is a written-out probe project checked by
  the real CLI, beside a byte-identical positive that differs only in the parameter's spelling.

### Chip fix: the dead `match` wildcard arm and the missing override-virtual check

| record | commit hash(es) | what moved | durable finding | headline numbers |
|---|---|---|---|---|
| CHIP FIX of 020/34's two filed follow-ups (2026-09-01) | pinned at `714aa6d9c` (020 slice 34: M7 `0/755` + `0/6316`, M7b `4/755` + `1/6316`, and the override finding's two silent probes); fixed on `stream/chip-match-wildcard-override` from `8cf40128a` | BOTH halves fixed in N#, ZERO C# lines touched, so no ratchet repin is owed. (a) The dead `_` arm is DELETED — and the identical dead arm in `CheckEnum` was found beside the filed one in `CheckUnion`, so TWO went. (b) `override` is now checked: `AnalyzerTypeDeclarations.ValidateOverrideTargets` runs in the type-header phase and reports `NL311` when an `override` member has no base member of that name, or one that is not `virtual`/`abstract`/non-`sealed` `override`. `DeclaredMemberInfo` gained `DeclaredModifiers` (the whole modifier word, default `0`, so no call site moved) because the source member model could not answer "is this virtual" at all | **DELETE, not make-reachable, and measurement decides it**: `_` carries no dot, so the undotted branch that treats `other =>` as a catch-all already answered for it — M7's true 0/0 is the proof the arm decided nothing, and M7b's 4/1 is the proof the surviving branch decides everything. `NL311 InvalidModifier` was the right code and was ALREADY catalogued with no producer anywhere in the tree; the fault is the modifier, not the name, so `NL303` would have been wrong. The new rule's real risk is the correct program it rejects, not the fault it misses: a base that resolves to nothing, a `:` clause that did not resolve, and a shape the context cannot open all answer "cannot tell" and report nothing | 7 files, all `.nl` + 1 doc; +422/−18; estate contracts +6 (2 exhaustiveness, 4 override); probe: `NL311` on both faults, silent on `override` of a `virtual` base member and on `override func ToString()`; estate-wide census unchanged, 0 `NL311` |

- **The estate cannot trip the new rule, and that was measured before it was written**: a scan of every
  `.nl` under `src`, `examples`, `templates` and `tests` finds exactly THREE overridden names —
  `ToString` 34, `Equals` 10, `GetHashCode` 10 — and all three are `object` virtuals reached through the
  implicit-root arm. A rule that walked only DECLARED bases would have reported all 54.
- **The source member model had no virtual bit at all.** `DeclaredMemberInfo` decoded `static`,
  `readonly`, `async` and `generator` as separate bools and threw the rest of the word away, so no
  inheritance question could be asked of a source base. `DeclaredModifiers` carries the whole word now;
  a defaulted trailing constructor parameter keeps all ten existing call sites spelled as they were.
- **A written-but-unresolved base is NOT a base of `object`.** Falling through to the implicit root when
  a `:` clause failed to resolve would search a surface the class does not inherit and report a member
  that is virtual one link further up — the check's one genuine false-positive shape, guarded explicitly.
