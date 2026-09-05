namespace NSharpLang.Cli.Commands

import System.Collections.Generic
import NSharpLang.Compiler.CodeIntelligence

// THE `nlc doc` OPTION, ORDERING, SLUG, SIGNATURE AND MESSAGE KERNELS.
//
// These replace FOUR `[Fact]`s deleted from `tests/CliCommandTests.cs`:
// `DocCommandKernels_SummarizesOptions`, `..._OrdersSymbolsForGeneration`,
// `..._OrdersMembersForGeneration` and `..._CreatesSlugs`.
//
// ONE OF THE FOUR IS SPLIT, AND THE SPLIT IS FORCED. `..._SummarizesOptions` ended by driving
// `DocCommand.Execute` through a console capture for a `--help` run and a missing-project run.
// `Console.SetOut` declines on this emit path at `emit.call.static-member-unmodeled`, so those
// rows are in `tests/native/cli-command-contracts` against the spawned binary.
//
// THE THREE ORDERING/SLUG BODIES COMPUTED THEIR OWN EXPECTATIONS WITH LINQ — `OrderBy(kind
// .ToString(), Ordinal).ThenBy(name, Ordinal)` and a `Select`-based slug — which means each of
// them asserted that the kernel agrees with a SECOND implementation written in the test. That is
// not a pin: both could drift together, and neither says what the order IS. The expectations are
// written out literally below.
func DocSymbol(name: string, kind: SymbolKind): SymbolResult {
    return new SymbolResult(name, kind, "/tmp/Program.nl", 1, 1, null, null, null, null)
}

// ── the option summary ────────────────────────────────────────────────────────

test "the doc option summary reads the project, output, json and open flags" {
    summary := DocCommandKernels.GetOptionSummary(["--json", "--open", "--project", "samples/demo", "--output", "docs/api"])

    assert summary.ProjectOption == "samples/demo"
    assert summary.OutputOption == "docs/api"
    assert summary.Json
    assert summary.Open
    assert !summary.ShowHelp
}

test "doc option values are taken permissively, so flags can be consumed as values" {
    // DELIBERATE AND PINNED: `--project` swallows `--json` and `--output` swallows `--open`, and
    // BOTH flags still set — the parser sets the flag as it walks and never un-sets it.
    summary := DocCommandKernels.GetOptionSummary(["--project", "--json", "--output", "--open"])

    assert summary.ProjectOption == "--json"
    assert summary.OutputOption == "--open"
    assert summary.Json
    assert summary.Open
}

test "help is asked for by the bare word, and by -h after a positional" {
    assert DocCommandKernels.GetOptionSummary(["help"]).ShowHelp
    assert DocCommandKernels.GetOptionSummary(["ignored", "-h"]).ShowHelp
}

test "doc output mode is 2 for text and 1 for json" {
    assert DocCommandKernels.GetOutputMode(false) == 2
    assert DocCommandKernels.GetOutputMode(true) == 1
}

// ── the generation order ──────────────────────────────────────────────────────

test "top-level symbols order by kind name then symbol name, and variables and parameters are dropped" {
    symbols := [
        DocSymbol("zeta", SymbolKind.Method),
        DocSymbol("alpha", SymbolKind.Function),
        DocSymbol("ignoredVariable", SymbolKind.Variable),
        DocSymbol("Customer", SymbolKind.Class),
        DocSymbol("ignoredParameter", SymbolKind.Parameter),
        DocSymbol("alpha", SymbolKind.Function),
        DocSymbol("OrderState", SymbolKind.Enum),
        DocSymbol("Name", SymbolKind.Property),
        DocSymbol("alpha", SymbolKind.Method),
        DocSymbol("Amount", SymbolKind.TypeAlias),
        DocSymbol("Account", SymbolKind.Class)
    ]

    ordered := DocCommandKernels.OrderSymbolsForGeneration(symbols)

    // Nine survive the two dropped kinds, in kind-rank order — Class, Enum, Function, Method,
    // Property, TypeAlias — with ORDINAL name order inside each kind.
    assert ordered.Count == 9
    assert ordered[0].Name == "Account"
    assert ordered[0].Kind == SymbolKind.Class
    assert ordered[1].Name == "Customer"
    assert ordered[1].Kind == SymbolKind.Class
    assert ordered[2].Name == "OrderState"
    assert ordered[2].Kind == SymbolKind.Enum
    assert ordered[3].Name == "alpha"
    assert ordered[3].Kind == SymbolKind.Function
    assert ordered[4].Name == "alpha"
    assert ordered[4].Kind == SymbolKind.Function
    assert ordered[5].Name == "alpha"
    assert ordered[5].Kind == SymbolKind.Method
    assert ordered[6].Name == "zeta"
    assert ordered[6].Kind == SymbolKind.Method
    assert ordered[7].Name == "Name"
    assert ordered[7].Kind == SymbolKind.Property
    assert ordered[8].Name == "Amount"
    assert ordered[8].Kind == SymbolKind.TypeAlias
}

test "the name order is ORDINAL, so every capital sorts ahead of every lowercase" {
    // The consequence the deleted body's LINQ expectation reproduced but never stated: `Account`
    // and `Customer` precede `alpha` INSIDE their kinds, and across kinds `Class` beats
    // `Function`, so the doc index is not alphabetical in the way a reader expects.
    ordered := DocCommandKernels.OrderSymbolsForGeneration([
        DocSymbol("alpha", SymbolKind.Class),
        DocSymbol("Zeta", SymbolKind.Class)
    ])

    assert ordered.Count == 2
    assert ordered[0].Name == "Zeta"
    assert ordered[1].Name == "alpha"
}

test "members keep every kind, including the variables and parameters top-level drops" {
    members := [
        DocSymbol("zeta", SymbolKind.Method),
        DocSymbol("alpha", SymbolKind.Function),
        DocSymbol("value", SymbolKind.Variable),
        DocSymbol("customer", SymbolKind.Parameter),
        DocSymbol("Customer", SymbolKind.Class),
        DocSymbol("Name", SymbolKind.Property),
        DocSymbol("alpha", SymbolKind.Method),
        DocSymbol("Amount", SymbolKind.Field)
    ]

    ordered := DocCommandKernels.OrderMembersForGeneration(members)

    // All eight survive: Class, Field, Function, Method, Parameter, Property, Variable.
    assert ordered.Count == 8
    assert ordered[0].Name == "Customer"
    assert ordered[0].Kind == SymbolKind.Class
    assert ordered[1].Name == "Amount"
    assert ordered[1].Kind == SymbolKind.Field
    assert ordered[2].Name == "alpha"
    assert ordered[2].Kind == SymbolKind.Function
    assert ordered[3].Name == "alpha"
    assert ordered[3].Kind == SymbolKind.Method
    assert ordered[4].Name == "zeta"
    assert ordered[4].Kind == SymbolKind.Method
    assert ordered[5].Name == "customer"
    assert ordered[5].Kind == SymbolKind.Parameter
    assert ordered[6].Name == "Name"
    assert ordered[6].Kind == SymbolKind.Property
    assert ordered[7].Name == "value"
    assert ordered[7].Kind == SymbolKind.Variable
}

// ── the page slug ─────────────────────────────────────────────────────────────

test "a slug keeps only letters and digits, lowercased, and joins with nothing between" {
    slugs := DocCommandKernels.CreateSlugs([
        "Class-Customer-/tmp/Customer.nl",
        "Method-GetById-Service.Core.nl",
        "TypeAlias-Result<T>-Errors.nl",
        "Function-Résumé_Count-Reports 2026.nl",
        "Property-HTTPClient2-API.Client.nl"
    ])

    assert slugs.Length == 5
    assert slugs[0] == "classcustomertmpcustomernl"
    assert slugs[1] == "methodgetbyidservicecorenl"
    // the angle brackets of a generic argument vanish entirely
    assert slugs[2] == "typealiasresultterrorsnl"
    // a non-ASCII LETTER is kept and lowercased; the underscore and the space are not
    assert slugs[3] == "functionrésumécountreports2026nl"
    assert slugs[4] == "propertyhttpclient2apiclientnl"
}

test "two different symbols can slug to the SAME page name" {
    // A CONSEQUENCE THE DELETED BODY COULD NOT SEE, because its expectation was the same
    // transformation applied twice. Dropping every separator makes the slug lossy, so
    // `Get.ById` and `GetById` land on one page.
    slugs := DocCommandKernels.CreateSlugs(["Method-Get.ById-A.nl", "Method-GetById-A.nl"])

    assert slugs.Length == 2
    assert slugs[0] == slugs[1]
}

// ── the signature and location text ───────────────────────────────────────────

test "a location is path, line and column joined by colons" {
    assert DocCommandKernels.GetLocationText("src/Program.nl", 12, 4) == "src/Program.nl:12:4"
}

test "a parameter shows its type, and its default only when it has one" {
    assert DocCommandKernels.GetParameterText("value", "int", false, "") == "value: int"
    assert DocCommandKernels.GetParameterText("value", "int", true, "42") == "value: int = 42"
}

test "a signature takes its keyword from the kind and its parameter list from the flag" {
    assert DocCommandKernels.GetSignatureText(SymbolKind.Function, "Compute", true, "value: int = 42", "string") == "func Compute(value: int = 42): string"
    assert DocCommandKernels.GetSignatureText(SymbolKind.Constructor, "Widget", true, "", "") == "ctor Widget()"
    // no parameter list at all: no parentheses are written
    assert DocCommandKernels.GetSignatureText(SymbolKind.Class, "Widget", false, "", "") == "class Widget"
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the doc help text names the command, its usage and its failure exit condition" {
    helpText := DocCommandKernels.GetHelpText()

    assert helpText.Contains("N# API Documentation")
    assert helpText.Contains("Usage: nlc doc [options]")
    assert helpText.Contains("Documentation generation failed")
}

test "the doc command's sentences are exactly these" {
    assert DocCommandKernels.GetProjectDirectoryNotFoundMessage("/tmp/missing-doc-project") == "Project directory not found: /tmp/missing-doc-project"
    assert DocCommandKernels.GetGeneratedSummaryMessage(7) == "Generated API docs for 7 symbols."
    assert DocCommandKernels.GetOutputPathMessage("/tmp/api") == "Output: /tmp/api"
    assert DocCommandKernels.GetIndexPathMessage("/tmp/api/index.html") == "Index: /tmp/api/index.html"
    assert DocCommandKernels.GetOpenedMessage() == "Opened generated documentation in the default browser."
    assert DocCommandKernels.GetGenerationFailedMessage("no symbols") == "Doc generation failed: no symbols"
    assert DocCommandKernels.GetOpenFailedMessage("/tmp/api/index.html") == "Generated docs, but failed to open /tmp/api/index.html."
    assert DocCommandKernels.GetOpenFailedWithDetailMessage("/tmp/api/index.html", "denied") == "Generated docs, but failed to open /tmp/api/index.html: denied"
}
