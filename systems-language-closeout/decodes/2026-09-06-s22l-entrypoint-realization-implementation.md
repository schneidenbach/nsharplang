# S2.2(l): N# entry-point selection and wrapper realization

`ColumnarEntryPointRealization.TryEmit` now owns the complete assembly entry-point decision. It
returns the selected nullable `MethodBuilder` through the original caller slot and reports only
whether selection and wrapper emission succeeded. `ColumnarIlEmitter` retains the assembly host and
one mechanical bool/out forward; its former 56-line selection and wrapper block is deleted. The C#
file falls from 18,923/17,984 total/nonblank lines to 18,883/17,947, a net reduction of 40/37.

The N# owner preserves the two indexed name walks, including lowercase `main` priority, ordinal
comparison and every `funcs.Count` read before the `mainIndex` guard. It retains the selected method
before rejecting async parameters, uses the actual shared `Type.EmptyTypes`, defines the wrapper
before building its body plan, completes the plan before acquiring the wrapper IL generator, and
publishes the wrapper only after successful execution. The static fallback acquires the concrete
`Dictionary<string, ColumnarStructDef>.ValueCollection.Enumerator` only when reached and disposes it
through `finally`; it keeps the first eligible row, the two separate `mains[0]` reads and a null
builder as the selected failure state.

`ColumnarAsyncEntryPointPlanner.BuildWrapperPlan` now receives the assembly's semantic catalog. It
does not read the structural table during argument guards, awaiter discovery, return classification,
plan preparation or entry-point method registration. At the former raw `AddType` site it selects the
actual awaiter from that same table and adds the selected key, runtime companion and table together.
The existing wrapper facts prove the retained table and independently selected key, then corrupt
only the companion in a fresh plan and require validation to reject it. The unsupported-awaitable
case passes a null catalog and still reaches its earlier reflection refusal, pinning the lazy read.

The accepted l1 SDK compiles the parked direct owner without source repair. After the production
route was connected, `./scripts/dev.sh EntryPoint` passed its focused host tests 4/4. A forced
test-enabled BootstrapServices run passed 14/14 with no skips and explicitly selected the keyed-row
positive and companion-mismatch contracts. The first test-enabled attempt is retained separately:
the product compiled, while the new test catalog helper omitted the already-required final defaulted
argument to `CreateSingleSource`; spelling the existing `null` argument corrected only the fixture.
Its argv, output and prelaunch source hashes were retained. The exact failed test bytes were
reconstructed afterward and hash-verified against that launch record; the supplemental receipt states
this provenance limit rather than claiming a pre-correction source copy.

Exact sources, the 14-file compiler payload, generating build receipt and final TRX are frozen under
`/private/tmp/nsharp-s22l-executor-logs/resume-l1-accepted/candidate-payload-01/`; manifest SHA-256 is
`b8f881cd4cf1933d5f82d3025c87108a596981387880a260155bd3b4a14a25e9`. Fixed-corpus parity,
strict diagnostics, ownership-ratchet updates and the fresh integration gate remain coordinator-owned.
