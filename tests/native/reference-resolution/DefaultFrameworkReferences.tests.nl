namespace NSharpLang.ReferenceResolution.Tests

import System.IO
import System.Text.Json

// A PROJECT SEES WHAT `dotnet build` GIVES IT: ALL OF Microsoft.NETCore.App, AND ASP.NET CORE UNDER
// THE WEB SDK.
//
// `nlc` used to compile a project with no `dependencies:` against 33 hand-picked assemblies, so
// issue #215's program -- `IServiceProvider` and `ClaimsIdentity` in a plain console project --
// failed NL704/NL201 under `nlc build` while `dotnet build` compiled it. Each row builds a real
// project through the real CLI and runs the program, so the analyzer, the IL back end and the
// runtime all have to agree that the type is there.

func DefaultRefsProject(root: string, projectYml: string, program: string) {
    ResolverWrite(Path.Combine(root, "project.yml"), projectYml)
    ResolverWrite(Path.Combine(root, "Program.nl"), program)
}

func DefaultRefsConsoleYml(name: string, dependencies: string): string {
    return "name: " + name + "\nversion: 1.0.0\nentry: Program.nl\noutputType: exe\ntargetFramework: net10.0\n" + dependencies
}

// Builds the project into `<root>/out` and runs it, answering its standard output with `\n` lines.
func DefaultRefsBuildAndRun(root: string, assemblyName: string): string {
    output := Path.Combine(root, "out")
    build := ResolverRunCli("build --project " + ResolverQuote(root) + " -o " + ResolverQuote(output), root)
    assert build.ExitCode == 0, build.Stdout + build.Stderr
    run := ResolverRunProcess("dotnet", ResolverQuote(Path.Combine(output, assemblyName + ".dll")), output)
    assert run.ExitCode == 0, run.Stdout + run.Stderr
    return run.Stdout.Replace("\r\n", "\n").Trim()
}

func DefaultRefsIssue215Program(): string {
    return "import System\nimport System.Security.Claims\n\nfunc main() {\n    sp: IServiceProvider? = null\n    id := new ClaimsIdentity()\n    print (sp == null).ToString()\n    print id.IsAuthenticated.ToString()\n}\n"
}

test "issue #215: a console project with no dependencies builds and runs IServiceProvider and ClaimsIdentity" {
    root := ResolverNewTempDirectory("default-refs-215")
    try {
        DefaultRefsProject(root, DefaultRefsConsoleYml("Issue215", ""), DefaultRefsIssue215Program())
        assert DefaultRefsBuildAndRun(root, "Issue215") == "True\nFalse"

        check := ResolverRunCli("check --project " + ResolverQuote(root), root)
        assert check.ExitCode == 0, check.Stdout + check.Stderr
        document := JsonDocument.Parse(check.Stdout)
        assert document.RootElement.GetProperty("summary").GetProperty("errors").GetInt32() == 0, check.Stdout
        document.Dispose()
    } finally {
        Directory.Delete(root, true)
    }
}

test "an explicit framework: Microsoft.NETCore.App entry is legal and changes nothing" {
    root := ResolverNewTempDirectory("default-refs-explicit")
    try {
        DefaultRefsProject(root, DefaultRefsConsoleYml("ExplicitBase", "dependencies:\n  - framework: Microsoft.NETCore.App\n"), DefaultRefsIssue215Program())
        assert DefaultRefsBuildAndRun(root, "ExplicitBase") == "True\nFalse"
    } finally {
        Directory.Delete(root, true)
    }
}

test "the rest of the base framework issue #215 found missing builds and runs with no dependencies" {
    root := ResolverNewTempDirectory("default-refs-wide")
    try {
        program := "import System.Collections.Immutable\n" +
            "import System.ComponentModel\n" +
            "import System.Data\n" +
            "import System.Diagnostics\n" +
            "import System.Diagnostics.Metrics\n" +
            "import System.Numerics\n" +
            "import System.Threading.Channels\n" +
            "import System.Xml\n" +
            "\n" +
            "func main() {\n" +
            "    document := new XmlDocument()\n" +
            "    document.LoadXml(\"<order id=\\\"7\\\" />\")\n" +
            "    print (must document.DocumentElement).GetAttribute(\"id\")\n" +
            "    big := BigInteger.Parse(\"123456789012345678901234567890\") + BigInteger.One\n" +
            "    print big.ToString()\n" +
            "    numbers := ImmutableArray.Create(1, 2, 3)\n" +
            "    print numbers.Length.ToString()\n" +
            "    channel := Channel.CreateUnbounded<int>()\n" +
            "    print channel.Writer.TryWrite(5).ToString()\n" +
            "    meter := new Meter(\"Orders\")\n" +
            "    print meter.Name\n" +
            "    activity := new Activity(\"Checkout\")\n" +
            "    print activity.OperationName\n" +
            "    converter := TypeDescriptor.GetConverter(typeof(int))\n" +
            "    print converter.ConvertToString(42)\n" +
            "    table := new DataTable(\"Orders\")\n" +
            "    print table.TableName\n" +
            "}\n"
        DefaultRefsProject(root, DefaultRefsConsoleYml("WideBase", ""), program)
        assert DefaultRefsBuildAndRun(root, "WideBase") == "7\n123456789012345678901234567891\n3\nTrue\nOrders\nCheckout\n42\nOrders"
    } finally {
        Directory.Delete(root, true)
    }
}

test "a fully-qualified framework type needs no import, as under dotnet build" {
    root := ResolverNewTempDirectory("default-refs-qualified")
    try {
        program := "func main() {\n" +
            "    total: System.Numerics.BigInteger = System.Numerics.BigInteger.Parse(\"99999999999999999999\")\n" +
            "    print (total + System.Numerics.BigInteger.One).ToString()\n" +
            "}\n"
        DefaultRefsProject(root, DefaultRefsConsoleYml("QualifiedBase", ""), program)
        assert DefaultRefsBuildAndRun(root, "QualifiedBase") == "100000000000000000000"
    } finally {
        Directory.Delete(root, true)
    }
}

test "a Web SDK project sees ASP.NET Core and the whole base framework without a framework entry" {
    root := ResolverNewTempDirectory("default-refs-web")
    try {
        program := "import Microsoft.AspNetCore.Builder\n" +
            "import System\n" +
            "import System.Security.Claims\n" +
            "\n" +
            "func main() {\n" +
            "    builder := WebApplication.CreateBuilder([])\n" +
            "    app := builder.Build()\n" +
            "    services: IServiceProvider = app.Services\n" +
            "    principal := new ClaimsPrincipal(new ClaimsIdentity())\n" +
            "    print (services != null).ToString()\n" +
            "    print (must principal.Identity).IsAuthenticated.ToString()\n" +
            "}\n"
        DefaultRefsProject(root, "name: WebDefaults\nversion: 1.0.0\nentry: Program.nl\noutputType: exe\ntargetFramework: net10.0\nsdk: Microsoft.NET.Sdk.Web\n", program)
        check := ResolverRunCli("check --project " + ResolverQuote(root), root)
        assert check.ExitCode == 0, check.Stdout + check.Stderr
        document := JsonDocument.Parse(check.Stdout)
        assert document.RootElement.GetProperty("summary").GetProperty("errors").GetInt32() == 0, check.Stdout
        document.Dispose()

        assert DefaultRefsBuildAndRun(root, "WebDefaults") == "True\nFalse"
    } finally {
        Directory.Delete(root, true)
    }
}
