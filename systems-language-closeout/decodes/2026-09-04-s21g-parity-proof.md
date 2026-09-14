# S2.1(g) custom attributes: completed parity proof

**PASS:** 94 N#-emitted images, identical normalized PE bytes, output sets and project outcomes.
The accepted arms are d/e/f, with every command run from its own committed corpus root. This is
emission/parity evidence; the fresh product gate is a separate integration checkpoint.

| Arm | Compiler source | Fixed corpus | Projects passed | Native tests |
|---|---|---|---:|---:|
| d, pristine | `5ac4faa798ffe60f89781e4ccaffd78e1949fc21` | same base | 73/75 | 2,138/2,138 |
| e, independent pristine | same base | same base | 73/75 | 2,138/2,138 |
| f, edited compiler | `f6ebcf42ba18c23a342af1e0610493bd45dc304e` | same base | 73/75 | 2,138/2,138 |

Both d/e and d/f compare 94 images with `IL_DIFFS=0`, no missing/extra image, and no changed outcome.
There are zero failed or skipped native tests. The only declines are the two pre-existing systems
templates, both exit 1 with their unchanged NL402 diagnostics. The fixed corpus archive SHA256 is
`aba285c9d8f77cef38e06ea3b01627b24af898453198a182bb2386316e68fc90`.

The compiler and support binaries were built from committed source and their snapshot hashes were
verified before reuse in d/e/f. Product source/build inputs at merge `4f2a8e63` match `f6ebcf42`;
integration adds the observed ownership manifest/policy repin and documentation. No cached product
gate is represented as new evidence.

## Explicit attribute witnesses

Independent IL dumps of the pre/post images are identical, including these owners:

- `SystemsProofs.ZeroCopyFrameReader.FrameReader` and `FrameResult`: two IsByRefLike attributes.
- `TaskCli.Models.Status`: one IsReadOnly attribute on the payload-free value union.
- `NSharpTests` in TaskCli: twelve Trait attributes followed by twelve paired Fact attributes.
  Trait precedes Fact within every test method, and the exact constructor signature/blob is retained.

`IssueTracker.IssueStatus` has payloads and is not a readonly value-union witness; the initial
implementation note's attribution was corrected after source/metadata inspection.

`nlc test --json` on TaskCli passes 12/12 on both compilers. The complete reports compare identically
after removing only projectRoot and duration fields, including result order, names, displayName,
nsharpDescription, outcomes and schemaVersion. The literal description
`AddTask creates a task with correct fields` is present on both paths.

The unchanged whole-PE normalizer excludes timestamps, checksum/debug volatility and the GUID heap;
it retains custom-attribute table ordering, constructor tokens and blobs. A predicted one-byte
mutation changes Program.Hi's return 42 to 43 in Hello.dll: exactly one normalized image changes,
both executions exit 0, and stdout changes only from `hi returned 42` to `hi returned 43`.

## Rejected harness result and correction

The original a/b controls matched, and a/c matched all 94 images, but c failed ownership-audit 17/18.
The harness ran commands with the live checkout as their working directory. After the merged ratchet
changed, the fixed-corpus test's older policy inspected the newer live manifest. This was not a
product or corpus-source difference. The same emitted test assembly was run twice: live checkout
produced OWN008/17 passed, its corpus directory produced 18 passed.

The harness now runs every project from its own corpus root. All three arms were rerun; no failed
row was filtered out or reclassified. Rejected scripts, logs and comparisons remain beside the
accepted evidence. Future corpus harness reuse must preserve this working-directory boundary.

## Ownership and focused evidence

The merged C# emitter is 20,722 lines / 19,710 nonblank, a reduction of two each. Selection/data/order
moved into N#; comment shortening is documentation cleanup, not additional policy retirement.
The observed file fingerprint is `text-v1:c0a1c13228e6f44a`. The native ownership audit passed 18/18
before integration, then reported the expected new manifest head with 17/18 after updating the row,
and passed 18/18 after both head keys became `head-v1:3d58ab0370b44a15`. No ceiling or epoch changed.

Stage-0 spelling, focused estate 10/10, full estate 7,658/7,658 (+8), declaration declines 5/5 and root
format are green. Strict compiler-source analysis retains exactly 259 prior findings, with only the
unused Collections.Generic import removed. Self-hosting is not complete.

Raw proof: `/private/tmp/nsharp-023-s21g-proof-20260904/`, especially `verdict.json`, `fixed.log`,
`fixed-coverage.json`, `compare-d-e.json`, `compare-d-f.json`, `attribute-witnesses.json`,
`test-json-comparison.json`, `nonvacuity.json`, and the three merged audit logs.
Fresh backend checkpoint: `/private/tmp/gate-20260904-goal-s21g-r1/`; read source.json, gate.log and
exit-code.txt for its exact revision and terminal verdict. That gate result is separate from this
parity verdict. Tasks 015, 021, 022 and 023 remain open; the next writer slice is S2.1(h).
