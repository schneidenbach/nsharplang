namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

// THE THREE PURE STATIC FILTERS BEHIND `nlc update`, `nlc check` AND `nlc query symbols`.
//
// These blocks replace THREE `[Fact]`s deleted from `tests/CliCommandTests.cs`:
// `UpdateDependencyFilter_FiltersTargetNuGetDependencies` (24 lines / 3 `Assert.`),
// `CompilerErrorSeverityFilter_FiltersCompilerErrorsBySeverity` (24 / 2) and
// `QuerySymbolNameFilter_FiltersSymbolsByNamePattern` (59 / 5). They are grouped because all three
// are the same shape — a static call with no command wrapper at all, which is why no naming
// convention found them before the ownership census did.
//
// THE DELETED BODIES MADE FIVE `Assert.` ROWS BETWEEN THEM AND HID THEIR MECHANISMS INSIDE
// SEQUENCE COMPARISONS. Each is unpacked here into the rule it tests, and each gains the control
// that would have caught a kernel ignoring one of its arguments.

// ── UpdateDependencyFilter ────────────────────────────────────────────────────
func FilterFixture(): Reference[] {
    return [
        new Reference { Nuget: "Serilog", Version: "3.1.1" },
        new Reference { Framework: "Microsoft.AspNetCore.App" },
        new Reference { Nuget: "Newtonsoft.Json", Version: "13.0.3" },
        new Reference { Dll: "lib/Analyzer.dll" },
        new Reference { Nuget: "serilog", Version: "4.0.0" },
        new Reference { Project: "../Shared/project.yml" },
        new Reference { Nuget: "System.Text.Json", Version: "10.0.0" }
    ]
}

test "the all-nuget filter keeps every nuget entry in order and drops the other three kinds" {
    all := UpdateDependencyFilter.FilterAllNuGetDependencies(FilterFixture())

    assert all.Count == 4
    assert all[0].Nuget == "Serilog"
    assert all[1].Nuget == "Newtonsoft.Json"
    assert all[2].Nuget == "serilog"
    assert all[3].Nuget == "System.Text.Json"
}

test "the target filter is case-insensitive on the package name and keeps BOTH casings" {
    // The fixture carries `Serilog` and `serilog` as two separate entries, so a filter comparing
    // ordinally would answer one. The deleted body asserted the pair and never said which
    // comparison produced it.
    serilog := UpdateDependencyFilter.FilterTargetNuGetDependencies(FilterFixture(), "SERILOG")

    assert serilog.Count == 2
    assert serilog[0].Nuget == "Serilog"
    assert serilog[0].Version == "3.1.1"
    assert serilog[1].Nuget == "serilog"
    assert serilog[1].Version == "4.0.0"
}

test "a package that is not a dependency filters to nothing" {
    assert UpdateDependencyFilter.FilterTargetNuGetDependencies(FilterFixture(), "Missing.Package").Count == 0
}

test "the target filter HONOURS its argument, so a different name answers a different set" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. It asked for one name and one miss, so a filter
    // that returned every nuget entry for any hit would have passed the first row.
    newtonsoft := UpdateDependencyFilter.FilterTargetNuGetDependencies(FilterFixture(), "newtonsoft.json")

    assert newtonsoft.Count == 1
    assert newtonsoft[0].Nuget == "Newtonsoft.Json"
}

test "a framework, a dll and a project reference are never nuget dependencies" {
    // THE OTHER HALF OF THE FIRST ROW, STATED. The deleted body proved the four survivors by
    // listing them; it never said the three non-survivors are non-survivors for three different
    // reasons.
    assert UpdateDependencyFilter.FilterTargetNuGetDependencies(FilterFixture(), "Microsoft.AspNetCore.App").Count == 0
    assert UpdateDependencyFilter.FilterTargetNuGetDependencies(FilterFixture(), "lib/Analyzer.dll").Count == 0
    assert UpdateDependencyFilter.FilterTargetNuGetDependencies(FilterFixture(), "../Shared/project.yml").Count == 0
}

// ── CompilerErrorSeverityFilter ───────────────────────────────────────────────

func SeverityFixture(): List<CompilerError> {
    errors := new List<CompilerError>()
    errors.Add(new CompilerError(ErrorCode.InvalidSyntax, "parse warning", 1, 1, ErrorSeverity.Warning))
    errors.Add(new CompilerError(ErrorCode.InvalidSyntax, "parse error", 1, 1, ErrorSeverity.Error))
    errors.Add(new CompilerError(ErrorCode.InvalidSyntax, "backend error", 1, 1, ErrorSeverity.Error))
    errors.Add(new CompilerError(ErrorCode.InvalidSyntax, "lint warning", 1, 1, ErrorSeverity.Warning))
    errors.Add(new CompilerError(ErrorCode.InvalidSyntax, "aot error", 1, 1, ErrorSeverity.Error))
    return errors
}

test "the severity filter selects the three errors, in their original order" {
    actualErrors := CompilerErrorSeverityFilter.Filter(SeverityFixture(), ErrorSeverity.Error)

    assert actualErrors.Count == 3
    assert actualErrors[0].Message == "parse error"
    assert actualErrors[1].Message == "backend error"
    assert actualErrors[2].Message == "aot error"
}

test "the severity filter selects the two warnings, in their original order" {
    actualWarnings := CompilerErrorSeverityFilter.Filter(SeverityFixture(), ErrorSeverity.Warning)

    assert actualWarnings.Count == 2
    assert actualWarnings[0].Message == "parse warning"
    assert actualWarnings[1].Message == "lint warning"
}

test "the two selections PARTITION the input, so nothing is dropped and nothing is duplicated" {
    // A CLAIM THE DELETED BODY COULD NOT MAKE. It compared each answer to a hand-written array and
    // never said the two answers together account for every input row.
    errors := CompilerErrorSeverityFilter.Filter(SeverityFixture(), ErrorSeverity.Error)
    warnings := CompilerErrorSeverityFilter.Filter(SeverityFixture(), ErrorSeverity.Warning)

    assert errors.Count + warnings.Count == SeverityFixture().Count
}

test "every selected row really carries the severity that was asked for" {
    // THE CLAIM THE ARRAY COMPARISON IMPLIED AND NEVER CHECKED. A filter that returned the right
    // COUNT of the wrong rows would have needed the reference identities to fail; this checks the
    // property directly.
    errors := CompilerErrorSeverityFilter.Filter(SeverityFixture(), ErrorSeverity.Error)
    i := 0
    while i < errors.Count {
        assert errors[i].Severity == ErrorSeverity.Error
        i = i + 1
    }

    warnings := CompilerErrorSeverityFilter.Filter(SeverityFixture(), ErrorSeverity.Warning)
    j := 0
    while j < warnings.Count {
        assert warnings[j].Severity == ErrorSeverity.Warning
        j = j + 1
    }
}

// ── QuerySymbolNameFilter ─────────────────────────────────────────────────────

func NewSymbol(name: string): SymbolResult {
    return new SymbolResult(name, SymbolKind.Function, "Program.nl", 1, 1, null, null, null, null)
}

func SymbolFixture(): SymbolResult[] {
    return [
        NewSymbol("UserService"),
        NewSymbol("OrderService"),
        NewSymbol("UserQuery"),
        NewSymbol("RenderPipeline"),
        NewSymbol("CurrentUser")
    ]
}

test "a pattern with no wildcard is a case-insensitive SUBSTRING match anywhere in the name" {
    substringMatches := QuerySymbolNameFilter.Filter(SymbolFixture(), "user", 200)

    assert substringMatches.Count == 3
    assert substringMatches[0].Name == "UserService"
    assert substringMatches[1].Name == "UserQuery"
    // `CurrentUser` is the one that shows the match is not anchored at the start
    assert substringMatches[2].Name == "CurrentUser"
}

test "a leading star anchors the pattern at the END of the name" {
    globMatches := QuerySymbolNameFilter.Filter(SymbolFixture(), "*Service", 200)

    assert globMatches.Count == 2
    assert globMatches[0].Name == "UserService"
    assert globMatches[1].Name == "OrderService"
    // AND IT IS NOT A SUBSTRING MATCH — the control the deleted body did not have. `UserQuery`
    // contains no `Service` and `RenderPipeline` contains no anchor, but a naive implementation
    // that fell back to `Contains` would still answer these two, so the sharper control is a
    // pattern that a substring match WOULD accept and a suffix match must not.
    assert QuerySymbolNameFilter.Filter(SymbolFixture(), "*User", 200).Count == 1
    assert QuerySymbolNameFilter.Filter(SymbolFixture(), "*User", 200)[0].Name == "CurrentUser"
}

test "a trailing star anchors the pattern at the START of the name" {
    // A WHOLE ARM THE DELETED BODY NEVER REACHED. `User*` and `*User` are different questions and
    // the kernel answers them with two different helpers.
    prefixMatches := QuerySymbolNameFilter.Filter(SymbolFixture(), "User*", 200)

    assert prefixMatches.Count == 2
    assert prefixMatches[0].Name == "UserService"
    assert prefixMatches[1].Name == "UserQuery"
}

test "an interior star matches across the middle of a name" {
    // THE GENERAL BACKTRACKING ARM, WHICH NEITHER OF THE ANCHORED FAST PATHS REACHES.
    interior := QuerySymbolNameFilter.Filter(SymbolFixture(), "User*ice", 200)

    assert interior.Count == 1
    assert interior[0].Name == "UserService"
}

test "the limit truncates the answer to a PREFIX of the matches" {
    limitedMatches := QuerySymbolNameFilter.Filter(SymbolFixture(), "*", 2)

    assert limitedMatches.Count == 2
    assert limitedMatches[0].Name == "UserService"
    assert limitedMatches[1].Name == "OrderService"
}

test "a bare star matches everything, and a zero or negative limit matches nothing" {
    assert QuerySymbolNameFilter.Filter(SymbolFixture(), "*", 200).Count == 5
    // A CONTROL THE DELETED BODY DID NOT HAVE: the limit guard runs BEFORE the pattern check, so a
    // zero limit answers empty rather than throwing on a bad pattern.
    assert QuerySymbolNameFilter.Filter(SymbolFixture(), "*", 0).Count == 0
    assert QuerySymbolNameFilter.Filter(SymbolFixture(), "*", -1).Count == 0
}

test "a non-ASCII SYMBOL NAME is refused rather than silently mismatched" {
    caught := false
    try {
        QuerySymbolNameFilter.Filter([NewSymbol("café")], "caf*", 200)
    } catch error: InvalidOperationException {
        caught = true
        assert error.Message == "N# query symbol-name filter kernel rejected the pattern."
    }

    assert caught
}

test "a non-ASCII PATTERN is refused too, and the deleted body never pinned the sentence" {
    caught := false
    try {
        QuerySymbolNameFilter.Filter(SymbolFixture(), "usér", 200)
    } catch error: InvalidOperationException {
        caught = true
        assert error.Message == "N# query symbol-name filter kernel rejected the pattern."
    }

    assert caught
}

test "the ASCII probe draws its line at code point 127" {
    assert QuerySymbolNameFilter.IsAscii("UserService")
    assert QuerySymbolNameFilter.IsAscii("")
    assert QuerySymbolNameFilter.IsAscii("~")
    assert !QuerySymbolNameFilter.IsAscii("é")
}
