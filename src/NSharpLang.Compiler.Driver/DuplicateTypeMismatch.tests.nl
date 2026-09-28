namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO


// A MISMATCH BETWEEN THE TWO HALVES OF A DUPLICATED TYPE NAME.
//
// One namespace that declares `class Entry` in two files is NL339 at the later declaration — and the
// program around it is still analysed, so a call that hands one file's `Entry` to a function written
// against the other's is ALSO a type mismatch. Before these rows that mismatch read "Cannot pass
// `List<Entry>` as argument for parameter `entries` of type `List<Entry>`", a contradiction that
// buried the NL339 under a screenful of its own echoes: the two types have one simple name AND one
// namespace, so the namespace-qualifying rung of `TypeMismatchDisplay` had nothing to add. The rung
// above it spells each colliding leaf with the site that declared it, so every echo names the two
// declarations the reader has to reconcile.
//
// THESE RUN THROUGH `MultiFileCompiler` over a real project on disk, because the fact under test is a
// whole-project fact: a per-file harness has no second file to collide with.
func DuplicateMismatchProject(tag: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-duplicate-mismatch-" + tag + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    File.WriteAllText(Path.Combine(root, "project.yml"), "name: DuplicateMismatch\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    // `A.nl` sorts first, so it is the declaration NL339 names and the one a third file's bare `Entry`
    // resolves to; `B.nl` is the duplicate, and its own functions are written against its own `Entry`.
    File.WriteAllText(Path.Combine(root, "A.nl"), "namespace Ledger\n\nclass Entry {\n    Key: string\n\n    constructor(key: string) {\n        Key = key\n    }\n}\n")
    File.WriteAllText(Path.Combine(root, "B.nl"), "namespace Ledger\n\nimport System.Collections.Generic\n\nclass Entry {\n    Label: string\n\n    constructor(label: string) {\n        Label = label\n    }\n}\n\nfunc CountEntries(entries: List<Entry>): int {\n    return entries.Count\n}\n\nfunc KeepEntry(entry: Entry?): bool {\n    return entry != null\n}\n\nfunc MakeEntry(): Entry {\n    return new Entry(\"made\")\n}\n")
    return root
}

func DuplicateMismatchErrors(root: string, callerBody: string): IReadOnlyList<CompilerError> {
    File.WriteAllText(Path.Combine(root, "C.nl"), "namespace Ledger\n\nimport System.Collections.Generic\n\n" + callerBody + "\n")
    AssertCompilesOnlyItsOwnSources(root)
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.CompileForAnalysis()
    return compiler.AllErrors
}

func DuplicateMismatchWithCode(errors: IReadOnlyList<CompilerError>, code: ErrorCode): List<CompilerError> {
    matches := new List<CompilerError>()
    for candidate in errors {
        if candidate.Code == code {
            matches.Add(candidate)
        }
    }
    return matches
}

func DuplicateMismatchAll(errors: IReadOnlyList<CompilerError>): string {
    text := ""
    for candidate in errors {
        if text.Length > 0 {
            text = text + " | "
        }
        text = text + candidate.Code.ToString() + ": " + candidate.Message
    }
    return text
}

func DuplicateMismatchSingle(errors: IReadOnlyList<CompilerError>): CompilerError {
    matches := DuplicateMismatchWithCode(errors, ErrorCode.TypeMismatch)
    assert matches.Count == 1, DuplicateMismatchAll(errors)
    return matches[0]
}

func DuplicateMismatchDelete(root: string) {
    try {
        Directory.Delete(root, true)
    } catch ex: Exception {
        // A temporary project another process still holds open is the operating system's to reclaim.
        _ = ex.Message
    }
}

test "a mismatch between the two halves of a duplicated name names both declarations" {
    root := DuplicateMismatchProject("generic-argument")
    try {
        errors := DuplicateMismatchErrors(root, "func Total(): int {\n    return CountEntries(new List<Entry>())\n}")

        // The root cause is still reported, once, at the later declaration.
        duplicates := DuplicateMismatchWithCode(errors, ErrorCode.TypeDeclaredInAnotherFile)
        assert duplicates.Count == 1, DuplicateMismatchAll(errors)
        assert duplicates[0].Message.StartsWith("A type named 'Entry' is already declared in this namespace, at A.nl:3"), duplicates[0].Message

        // The echo no longer contradicts itself: the colliding leaf carries its declaration site on
        // both sides, and the head that does not collide keeps its simple name.
        mismatch := DuplicateMismatchSingle(errors)
        assert mismatch.Message == "Cannot pass `List<Entry [A.nl:3]>` as argument for parameter `entries` of type `List<Entry [B.nl:5]>`", mismatch.Message
        assert mismatch.ActualType == "List<Entry [A.nl:3]>", mismatch.ActualType ?? "<null>"
        assert mismatch.ExpectedType == "List<Entry [B.nl:5]>", mismatch.ExpectedType ?? "<null>"
    } finally {
        DuplicateMismatchDelete(root)
    }
}

test "two renderings that already differ still name the declarations when the difference is not the one that failed" {
    root := DuplicateMismatchProject("nullable-parameter")
    try {
        // `Entry` against `Entry?` reads as a nullability mismatch, but passing a non-null value to a
        // nullable parameter is legal: what failed is that the two `Entry`s are different types.
        errors := DuplicateMismatchErrors(root, "func Keep(): bool {\n    return KeepEntry(new Entry(\"key\"))\n}")

        mismatch := DuplicateMismatchSingle(errors)
        assert mismatch.Message == "Cannot pass `Entry [A.nl:3]` as argument for parameter `entry` of type `Entry [B.nl:5]?`", mismatch.Message
    } finally {
        DuplicateMismatchDelete(root)
    }
}

test "an annotation and a return between the two halves name both declarations too" {
    root := DuplicateMismatchProject("annotation-return")
    try {
        declared := DuplicateMismatchSingle(DuplicateMismatchErrors(root, "func Held(): string {\n    held: Entry = MakeEntry()\n    return held.Key\n}"))
        assert declared.Message == "Variable 'held' is typed as 'Entry [A.nl:3]', but the value is 'Entry [B.nl:5]'", declared.Message

        returned := DuplicateMismatchSingle(DuplicateMismatchErrors(root, "func Give(): Entry {\n    return MakeEntry()\n}"))
        assert returned.ExpectedType == "Entry [A.nl:3]", returned.ExpectedType ?? "<null>"
        assert returned.ActualType == "Entry [B.nl:5]", returned.ActualType ?? "<null>"
    } finally {
        DuplicateMismatchDelete(root)
    }
}

test "one type that differs only in nullability is not re-spelled" {
    root := DuplicateMismatchProject("same-type")
    try {
        // `B.nl`'s own functions are written against `B.nl`'s own `Entry`, so a nullable argument to a
        // non-null parameter is the ordinary nullability mismatch, and nothing about it is identity.
        File.WriteAllText(Path.Combine(root, "B.nl"), "namespace Ledger\n\nclass Record {\n    Label: string = \"\"\n}\n\nfunc Describe(record: Record): string {\n    return record.Label\n}\n\nfunc DescribeMaybe(record: Record?): string {\n    return Describe(record)\n}\n")
        errors := DuplicateMismatchErrors(root, "func Unused(): int {\n    return 0\n}")

        assert DuplicateMismatchWithCode(errors, ErrorCode.TypeDeclaredInAnotherFile).Count == 0, DuplicateMismatchAll(errors)
        for candidate in errors {
            assert !candidate.Message.Contains("["), candidate.Message
        }
    } finally {
        DuplicateMismatchDelete(root)
    }
}
