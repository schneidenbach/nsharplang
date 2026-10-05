namespace NSharpLang.IncrementalBuild.Tests

import NSharpLang.Compiler

// INCREMENTAL RESULTS ARE A CLEAN BUILD'S RESULTS.
//
// For every project of the corpus, a warm session absorbs a seeded sequence of edits — body
// literals, blank and comment lines that move declarations, renamed identifiers, retyped
// signatures, files added, duplicated, removed and restored — and after each one its diagnostics and
// emitted bytes are compared with a from-scratch compilation of the same files. A row also requires
// that the run was not vacuous: some comparisons built successfully, some failed, and some steps
// really did reuse analyses.
//
// The default is eight edits per project, seeded; `NSHARP_INCREMENTAL_DIFFERENTIAL_STEPS` runs more.
test "a warm session's diagnostics and IL bytes equal a clean build's across seeded edits to five multi-file projects" {
    report := new DifferentialReport()
    steps := DifferentialSteps(8)
    seed := 20261005
    for project in DifferentialCorpus() {
        DifferentialRun(project, seed, steps, report)
        seed = seed + 1
    }

    detail := report.Summary()
    if report.Mismatches.Count > 0 {
        detail = detail + "\n" + report.Mismatches[0]
    }
    assert report.Mismatches.Count == 0, detail
    assert report.SuccessfulComparisons > 0, detail
    assert report.FailedComparisons > 0, detail
    assert report.PartialSteps > 0, detail
    assert report.FilesReused > 0, detail
}

test "a body-only edit re-analyses only the edited file" {
    scratch := IncrementalScratch("body-only")
    try {
        project := DifferentialCorpus()[0]
        root := scratch + "/geo"
        originals := DifferentialCopy(project, root)
        session := new IncrementalProjectSession(root, "Geo")
        report := new DifferentialReport()
        DifferentialCompare(session, root, "initial", report)
        assert session.State.LastFilesAnalyzed == originals.Count
        calc := root + "/Util/Calc.nl"
        System.IO.File.WriteAllText(calc, originals[calc].Replace("return value * factor\n}\n\nfunc Scale(value: double", "return value * factor * 1\n}\n\nfunc Scale(value: double"))
        DifferentialCompare(session, root, "body edit", report)
        assert report.Mismatches.Count == 0, report.Summary()
        assert session.State.LastFilesAnalyzed == 1, report.Summary()
        assert session.State.LastFilesReused == originals.Count - 1, report.Summary()
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "a signature edit re-analyses the files that depend on it and no others" {
    scratch := IncrementalScratch("signature")
    try {
        project := DifferentialCorpus()[0]
        root := scratch + "/geo"
        originals := DifferentialCopy(project, root)
        session := new IncrementalProjectSession(root, "Geo")
        report := new DifferentialReport()
        DifferentialCompare(session, root, "initial", report)
        tags := root + "/Model/Tags.nl"
        System.IO.File.WriteAllText(tags, originals[tags].Replace("func Get(): T {", "func Get(): T? {"))
        DifferentialCompare(session, root, "signature edit", report)
        assert report.Mismatches.Count == 0, report.Summary()
        assert session.State.LastFilesAnalyzed > 1, report.Summary()
        assert session.State.LastFilesReused > 0, report.Summary()
    } finally {
        IncrementalCleanup(scratch)
    }
}
