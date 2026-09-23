namespace NSharpLang.GateScriptContracts.Tests

import System.Text.RegularExpressions

// ─── STEP 3a's NATIVE SWEEP: WHAT MAY RUN BESIDE WHAT ─────────────────────────────────────────
//
// Read as TEXT. Nothing here runs the gate or a native project.
//
// Step 3a runs one `nlc test` PROCESS per project over ~129 projects. It ran them strictly one at
// a time and cost about 17 minutes of a 33-minute gate, while Steps 8, 9 and 10 of the same script
// have run their per-project work under `xargs -P "$MAX_JOBS"` all along. The sweep now uses that
// same pattern — and these rows pin the three things that make it safe to do so:
//
//   * the projects whose claims are about the MACHINE, or that touch state outside their own
//     directory, stay in a serial group, and that group runs FIRST (which also warms the shared
//     NuGet cache before anything runs concurrently, the race Step 8's warm-up exists to avoid);
//   * the parent replays every project in DISCOVERY order, so a parallel log reads like a serial
//     one and a diff between two runs is meaningful;
//   * the per-project JSON validator is the same one that guarded the sequential loop. A parallel
//     sweep that accepted a weaker envelope would be faster and worthless.

func SweepScript(): string {
    return ReadGateScript("test-all-core.sh")
}

func SerialGroupBody(coreScript: string): string {
    return RequireMatch(
        coreScript,
        "native_requires_serial_run\\(\\) \\{(?<body>.*?)\\n    \\}",
        "Could not find the native sweep's serial-group predicate in tests/scripts/test-all-core.sh."
    ).Groups["body"].Value
}

test "the native sweep runs its serial group first and only then runs the rest in parallel, under a capped worker count" {
    coreScript := SweepScript()

    serialIndex := coreScript.IndexOf("xargs -P 1 -I{} bash -lc \"$NATIVE_WORKER\" _ {} \"$NATIVE_RESULTS_DIR\" \"$CLI_DLL\" \"$NATIVE_READER\" < \"$NATIVE_SERIAL_LIST\"")
    parallelIndex := coreScript.IndexOf("xargs -P \"$NATIVE_MAX_JOBS\" -I{} bash -lc \"$NATIVE_WORKER\" _ {} \"$NATIVE_RESULTS_DIR\" \"$CLI_DLL\" \"$NATIVE_READER\" < \"$NATIVE_PARALLEL_LIST\"")

    assert serialIndex >= 0, "The native sweep must run its serial group under `xargs -P 1`."
    assert parallelIndex >= 0, "The native sweep must run its parallel group under `xargs -P \"$NATIVE_MAX_JOBS\"`."
    assert serialIndex < parallelIndex, "The serial group must run BEFORE the parallel one: it carries the machine-sensitive projects and warms the shared NuGet cache."

    // The worker count is bounded, and bounded below the whole box.
    assert coreScript.Contains("NATIVE_MAX_JOBS=\"$MAX_JOBS\"")
    cap := RequireMatch(coreScript, "if \\[ \"\\$NATIVE_MAX_JOBS\" -gt (?<cap>\\d+) \\]; then\\s*\\n\\s*NATIVE_MAX_JOBS=(?<set>\\d+)", "The native sweep must cap its parallel worker count.")
    assert cap.Groups["cap"].Value == cap.Groups["set"].Value, "The cap and the value it clamps to must be the same number."
    capText := cap.Groups["cap"].Value
    assert capText == "1" || capText == "2" || capText == "3" || capText == "4" || capText == "5" || capText == "6", "The native sweep's worker cap must stay at or below 6 (found " + capText + "): the projects it runs are whole compiler processes, not unit tests."
}

test "a native project whose claim is about the machine, or that touches state outside its own directory, stays serial" {
    body := SerialGroupBody(SweepScript())

    // Measures latency against a baseline taken on an idle machine and reads the load average.
    assert body.Contains("tests/native/compile-time-bench)"), "compile-time-bench measures wall time and reads the one-minute load average; it may not run beside siblings."
    // Daemon sockets and state outside the project directory.
    assert body.Contains("tests/native/daemon-command)")
    // Runs the installers, the reseed fixtures and scripts/dev.sh as processes.
    assert body.Contains("tests/native/gate-script-contracts)")
    // Real dotnet restores/builds against a package cache.
    assert body.Contains("tests/native/compilation-backend)")
    assert body.Contains("tests/native/nuget-resolution-fidelity)")
    assert body.Contains("tests/native/reference-resolution)")
    assert body.Contains("tests/native/sdk-emit-path-parity)")
    assert body.Contains("tests/native/template-project-smoke)")
    // Packs the in-repo SDK and Runtime, which builds Build.Tasks and the Runtime into the SHARED
    // `src/*/obj` and `src/*/bin`: run beside the sibling that packs the same two projects, one row
    // of its 28 failed with an MSBuild file lock.
    assert body.Contains("tests/native/sdk-project-reference-boundary)")
    // Walks the whole working tree and counts what it finds there.
    assert body.Contains("tests/native/ownership-audit)")
}

test "the sweep packs the one private SDK feed itself, before any worker exists, and hands it to the projects that would otherwise each pack it" {
    coreScript := SweepScript()

    // The two packs, and the environment contract the three SDK-path projects read before packing
    // anything themselves. Both packs must PRECEDE the first worker: the pack writes the shared
    // `src/*/obj` and `src/*/bin`, so two of them overlapping is an MSBuild file lock.
    runtimePack := coreScript.IndexOf("dotnet pack src/NSharpLang.Runtime/NSharpLang.Runtime.csproj -o \"$NATIVE_SDK_FEED\"")
    sdkPack := coreScript.IndexOf("dotnet pack src/NSharpLang.Sdk/NSharpLang.Sdk.csproj -o \"$NATIVE_SDK_FEED\"")
    exportFeed := coreScript.IndexOf("export NSHARP_SDK_PROJECT_REFERENCE_FEED=\"$NATIVE_SDK_FEED\"")
    exportVersion := coreScript.IndexOf("export NSHARP_SDK_PROJECT_REFERENCE_VERSION=\"$NATIVE_SDK_FEED_VERSION\"")
    firstWorker := coreScript.IndexOf("xargs -P 1 -I{} bash -lc \"$NATIVE_WORKER\"")

    assert runtimePack >= 0, "Step 3a must pack the private Runtime package itself."
    assert sdkPack >= 0, "Step 3a must pack the private SDK package itself."
    assert exportFeed >= 0 && exportVersion >= 0, "Step 3a must export both halves of the feed contract; a feed without its version is not honored by any of the three projects."
    assert firstWorker >= 0
    assert runtimePack < firstWorker && sdkPack < firstWorker, "The shared feed must be packed BEFORE the first worker starts, which is the whole point: a pack that overlaps another pack takes an MSBuild file lock."

    // A pack the step could not do is a failure of the step, never a sweep that quietly packs
    // per project again.
    assert coreScript.Contains("handle_error \"Native N# tests: shared private SDK feed\"")
    assert coreScript.Contains("NATIVE_STEP_OK=0")

    // A feed handed in from outside is honored and never deleted; only one this step packed is.
    assert coreScript.Contains("if [ -z \"${NSHARP_SDK_PROJECT_REFERENCE_FEED:-}\" ] || [ -z \"${NSHARP_SDK_PROJECT_REFERENCE_VERSION:-}\" ]; then")
    assert coreScript.Contains("if [ -n \"${NATIVE_SDK_FEED:-}\" ]; then")
}

test "the parallel sweep replays every project in discovery order, records what each one cost, and refuses a project whose worker left no result" {
    coreScript := SweepScript()

    // One numbered list, written in discovery order, is both what the workers consume and what the
    // parent replays. A log printed in completion order could not be diffed against a serial run.
    assert coreScript.Contains("done < \"$NATIVE_LIST\""), "The parent must replay results from the discovery-ordered list."
    assert coreScript.Contains("printf '%04d|%s\\n' \"$native_index\" \"$native_dir\" >> \"$NATIVE_LIST\"")
    assert coreScript.Contains("echo \"Testing native project: $native_dir\""), "The per-project banner must survive the move to workers."

    // Per-project wall time, the only durable record of what this step spends.
    assert coreScript.Contains("printf 'project=%s seconds=%s\\n' \"$native_dir\""), "Step 3a must print one `project=<dir> seconds=<n>` line per project."

    // A worker that died without writing its result is a failure, never a silent pass.
    missing := RequireMatch(
        coreScript,
        "if \\[ ! -f \"\\$native_result_file\" \\]; then(?<body>.*?)\\n\\s*continue",
        "A project whose worker recorded no result must fail the step."
    ).Groups["body"].Value
    assert missing.Contains("handle_error")
    assert missing.Contains("NATIVE_STEP_OK=0")
}

test "the parallel sweep's per-project JSON validator is the one that guarded the sequential loop" {
    coreScript := SweepScript()
    reader := RequireMatch(
        coreScript,
        "NATIVE_READ_SUMMARY='(?<body>.*?)'\\s*\\n",
        "Could not find the native sweep's JSON validator in tests/scripts/test-all-core.sh."
    ).Groups["body"].Value

    // Every clause that makes a green project mean something. None of them may be relaxed to make
    // a parallel sweep pass.
    assert reader.Contains("payload.get(\"schemaVersion\") == 1")
    assert reader.Contains("payload.get(\"command\") == \"test\"")
    assert reader.Contains("payload.get(\"ok\") is True")
    assert reader.Contains("total > 0")
    assert reader.Contains("len(results) == total")
    assert reader.Contains("passed > 0")
    assert reader.Contains("failed == 0")
    assert reader.Contains("passed + failed + skipped == total")
    assert reader.Contains("outcome_counts[\"passed\"] == passed")
    assert reader.Contains("outcome_counts[\"failed\"] == failed")
    assert reader.Contains("outcome_counts[\"skipped\"] == skipped")
    assert reader.Contains("raise SystemExit(\"native N# test JSON did not prove a nonempty successful run\")")

    // The worker runs THAT validator, and only counts a project green when both the run and the
    // validation succeeded.
    worker := RequireMatch(coreScript, "NATIVE_WORKER='(?<body>.*?)'\\s*\\n", "Could not find the native sweep's worker in tests/scripts/test-all-core.sh.").Groups["body"].Value
    assert worker.Contains("dotnet \"$cli_dll\" test --project \"$native_dir\" --no-cache --json")
    assert worker.Contains("python3 \"$reader\" \"$native_output\"")
    assert worker.Contains("native_status=OK")
    assert Regex.Matches(worker, "native_status=OK").Count == 1, "There must be exactly one place a project is recorded as passing."
}
