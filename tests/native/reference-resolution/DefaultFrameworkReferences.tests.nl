namespace NSharpLang.ReferenceResolution.Tests

import System
import System.Collections.Generic
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
        source := new List<string>()
        source.Add("import System.Collections.Immutable")
        source.Add("import System.ComponentModel")
        source.Add("import System.Data")
        source.Add("import System.Diagnostics")
        source.Add("import System.Diagnostics.Metrics")
        source.Add("import System.Numerics")
        source.Add("import System.Threading.Channels")
        source.Add("import System.Xml")
        source.Add("")
        source.Add("func main() {")
        source.Add("    document := new XmlDocument()")
        source.Add("    document.LoadXml(\"<order id=\\\"7\\\" />\")")
        source.Add("    print (must document.DocumentElement).GetAttribute(\"id\")")
        source.Add("    big := BigInteger.Parse(\"123456789012345678901234567890\") + BigInteger.One")
        source.Add("    print big.ToString()")
        source.Add("    numbers := ImmutableArray.Create(1, 2, 3)")
        source.Add("    print numbers.Length.ToString()")
        source.Add("    channel := Channel.CreateUnbounded<int>()")
        source.Add("    print channel.Writer.TryWrite(5).ToString()")
        source.Add("    meter := new Meter(\"Orders\")")
        source.Add("    print meter.Name")
        source.Add("    activity := new Activity(\"Checkout\")")
        source.Add("    print activity.OperationName")
        source.Add("    converter := TypeDescriptor.GetConverter(typeof(int))")
        source.Add("    print converter.ConvertToString(42)")
        source.Add("    table := new DataTable(\"Orders\")")
        source.Add("    print table.TableName")
        source.Add("}")
        program := string.Join("\n", source) + "\n"
        DefaultRefsProject(root, DefaultRefsConsoleYml("WideBase", ""), program)
        assert DefaultRefsBuildAndRun(root, "WideBase") == "7\n123456789012345678901234567891\n3\nTrue\nOrders\nCheckout\n42\nOrders"
    } finally {
        Directory.Delete(root, true)
    }
}

test "a fully-qualified framework type needs no import, as under dotnet build" {
    root := ResolverNewTempDirectory("default-refs-qualified")
    try {
        source := new List<string>()
        source.Add("func main() {")
        source.Add("    total: System.Numerics.BigInteger = System.Numerics.BigInteger.Parse(\"99999999999999999999\")")
        source.Add("    print (total + System.Numerics.BigInteger.One).ToString()")
        source.Add("}")
        program := string.Join("\n", source) + "\n"
        DefaultRefsProject(root, DefaultRefsConsoleYml("QualifiedBase", ""), program)
        assert DefaultRefsBuildAndRun(root, "QualifiedBase") == "100000000000000000000"
    } finally {
        Directory.Delete(root, true)
    }
}

test "a Web SDK project sees ASP.NET Core and the whole base framework without a framework entry" {
    root := ResolverNewTempDirectory("default-refs-web")
    try {
        source := new List<string>()
        source.Add("import Microsoft.AspNetCore.Builder")
        source.Add("import System")
        source.Add("import System.Security.Claims")
        source.Add("")
        source.Add("func main() {")
        source.Add("    builder := WebApplication.CreateBuilder([])")
        source.Add("    app := builder.Build()")
        source.Add("    services: IServiceProvider = app.Services")
        source.Add("    principal := new ClaimsPrincipal(new ClaimsIdentity())")
        source.Add("    print (services != null).ToString()")
        source.Add("    print (must principal.Identity).IsAuthenticated.ToString()")
        source.Add("}")
        program := string.Join("\n", source) + "\n"
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

// AN OLD PACKAGE GRAPH IS NOT THE FRAMEWORK. `System.IO 4.1.0` brings
// `system.runtime/4.1.0/ref/netstandard1.5/System.Runtime.dll` along; a reference that is merely named
// `System.Runtime.dll` used to switch every on-demand framework load off, so the issue #215 program
// failed again as soon as the project depended on such a package. Only a real reference pack
// (`data/FrameworkList.xml` naming Microsoft.NETCore.App) supplies the framework itself. The package
// comes from the machine's cache when it has it, and from nuget.org otherwise.
test "a netstandard1.x package's System.Runtime.dll does not hide the base framework" {
    root := ResolverNewTempDirectory("default-refs-old-graph")
    try {
        DefaultRefsProject(root, DefaultRefsConsoleYml("OldGraph", "dependencies:\n  - nuget: System.IO\n    version: 4.1.0\n"), DefaultRefsIssue215Program())
        assert DefaultRefsBuildAndRun(root, "OldGraph") == "True\nFalse"
    } finally {
        Directory.Delete(root, true)
    }
}

// A TYPE REACHED ONLY THROUGH A MEMBER. `HttpRequestMessage.RequestUri` returns `System.Uri`, which
// lives in `System.Private.Uri` -- an assembly nothing here imports or names -- and the program then
// calls a member on it. The type arrives through the metadata of a loaded assembly, not through a
// namespace, and both the analyzer and the IL back end have to follow it.
test "a framework type reached only through a loaded member's return type binds and runs" {
    root := ResolverNewTempDirectory("default-refs-return-type")
    try {
        source := new List<string>()
        source.Add("import System.Net.Http")
        source.Add("")
        source.Add("func main() {")
        source.Add("    request := new HttpRequestMessage(HttpMethod.Get, \"http://example.com/orders/7\")")
        source.Add("    print (must request.RequestUri).AbsolutePath")
        source.Add("}")
        DefaultRefsProject(root, DefaultRefsConsoleYml("ReturnType", ""), string.Join("\n", source) + "\n")
        assert DefaultRefsBuildAndRun(root, "ReturnType") == "/orders/7"
    } finally {
        Directory.Delete(root, true)
    }
}

// THE COMPILE SURFACE IS THE REFERENCE PACK'S, TYPE BY TYPE. `TreeSet<T>` and `ZLibException` are
// public in the runtime's implementation assemblies and absent from the reference pack, so
// `dotnet build` refuses them; `nlc` refuses them too, with the ordinary type-not-found error.
test "a public type only a runtime implementation carries is not nameable" {
    root := ResolverNewTempDirectory("default-refs-implementation-only")
    try {
        source := new List<string>()
        source.Add("import System.Collections.Generic")
        source.Add("import System.IO.Compression")
        source.Add("")
        source.Add("func main() {")
        source.Add("    tree: TreeSet<int>? = null")
        source.Add("    failure: ZLibException? = null")
        source.Add("    print (tree == null && failure == null).ToString()")
        source.Add("}")
        DefaultRefsProject(root, DefaultRefsConsoleYml("ImplementationOnly", ""), string.Join("\n", source) + "\n")
        check := ResolverRunCli("check --project " + ResolverQuote(root) + " --json", root)
        assert check.ExitCode != 0, check.Stdout
        assert ResolverDiagnosticCount(check.Stdout, "NL201", "TreeSet") == 1, check.Stdout
        assert ResolverDiagnosticCount(check.Stdout, "NL201", "ZLibException") == 1, check.Stdout
    } finally {
        Directory.Delete(root, true)
    }
}

// A CONSOLE PROJECT DOES NOT SEE ASP.NET CORE UNLESS IT REFERENCES IT, as under `dotnet build`; a
// `framework: Microsoft.AspNetCore.App` entry is what makes the same import resolve.
test "a console project imports ASP.NET Core only once it references the framework" {
    root := ResolverNewTempDirectory("default-refs-console-aspnet")
    try {
        source := new List<string>()
        source.Add("import Microsoft.AspNetCore.Builder")
        source.Add("")
        source.Add("func main() {")
        source.Add("    builder := WebApplication.CreateBuilder([])")
        source.Add("    print (builder != null).ToString()")
        source.Add("}")
        DefaultRefsProject(root, DefaultRefsConsoleYml("ConsoleAspNet", ""), string.Join("\n", source) + "\n")
        refused := ResolverRunCli("check --project " + ResolverQuote(root) + " --json", root)
        assert refused.ExitCode != 0, refused.Stdout
        assert ResolverDiagnosticCount(refused.Stdout, "NL704", "Microsoft.AspNetCore.Builder") == 1, refused.Stdout

        DefaultRefsProject(root, DefaultRefsConsoleYml("ConsoleAspNet", "dependencies:\n  - framework: Microsoft.AspNetCore.App\n"), string.Join("\n", source) + "\n")
        assert DefaultRefsBuildAndRun(root, "ConsoleAspNet") == "True"
    } finally {
        Directory.Delete(root, true)
    }
}

// THE ANSWER DOES NOT DEPEND ON HOW THE WORK WAS SPLIT. `A.nl` spells `System.Numerics.BigInteger`
// fully qualified, which loads `System.Runtime.Numerics`; `Z.nl` writes a bare `BigInteger` and imports
// nothing that supplies it. Whether `A.nl` was analysed first, by the same worker, used to decide
// whether `Z.nl` bound. A bare name resolves only through the file's own imports (and the preloaded
// common set), so one worker and four give the same diagnostics, and so does a check that reuses
// `A.nl`'s earlier analysis.
func DefaultRefsOrderProject(root: string) {
    ResolverWrite(Path.Combine(root, "project.yml"), "name: OrderProbe\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\n")
    ResolverWrite(Path.Combine(root, "A.nl"), "namespace OrderProbe\n\nfunc Seed(): System.Numerics.BigInteger {\n    return System.Numerics.BigInteger.One\n}\n")
    ResolverWrite(Path.Combine(root, "Z.nl"), "namespace OrderProbe\n\nfunc Twice(): BigInteger {\n    return Seed() + Seed()\n}\n")
}

test "a bare framework name binds the same with one worker and four, and after reuse" {
    root := ResolverNewTempDirectory("default-refs-order")
    try {
        DefaultRefsOrderProject(root)
        one := ResolverRunCliWithWorkers("check --project " + ResolverQuote(root) + " --json", root, 1)
        DefaultRefsForgetPersistedCheck(root)
        four := ResolverRunCliWithWorkers("check --project " + ResolverQuote(root) + " --json", root, 4)
        assert one.Stdout == four.Stdout, "one worker:\n" + one.Stdout + "\nfour workers:\n" + four.Stdout
        assert ResolverDiagnosticCount(one.Stdout, "NL201", "BigInteger") == 1, one.Stdout

        // Reuse: only Z.nl changes, so A.nl's analysis is taken from the persisted check and its
        // fully-qualified load never runs in this process.
        ResolverWrite(Path.Combine(root, "Z.nl"), "namespace OrderProbe\n\nfunc Twice(): BigInteger {\n    return Seed() + Seed() + Seed()\n}\n")
        reused := ResolverRunCliWithWorkers("check --project " + ResolverQuote(root) + " --json", root, 1)
        DefaultRefsForgetPersistedCheck(root)
        fresh := ResolverRunCliWithWorkers("check --project " + ResolverQuote(root) + " --json", root, 1)
        assert reused.Stdout == fresh.Stdout, "reused:\n" + reused.Stdout + "\nfresh:\n" + fresh.Stdout
    } finally {
        Directory.Delete(root, true)
    }
}

// How many diagnostics of `code` a `check --json` result reports whose message mentions `fragment`.
func ResolverDiagnosticCount(stdout: string, code: string, fragment: string): int {
    document := JsonDocument.Parse(stdout)
    count := 0
    try {
        for diagnostic in document.RootElement.GetProperty("results").EnumerateArray() {
            diagnosticCode := diagnostic.GetProperty("code").GetString() ?? ""
            message := diagnostic.GetProperty("message").GetString() ?? ""
            if diagnosticCode == code && message.Contains(fragment, StringComparison.Ordinal) {
                count = count + 1
            }
        }
    } finally {
        document.Dispose()
    }
    return count
}

// A new process with no persisted check to reuse.
func DefaultRefsForgetPersistedCheck(root: string) {
    for directory in ["obj", "bin", ".nlc"] {
        path := Path.Combine(root, directory)
        if Directory.Exists(path) {
            Directory.Delete(path, true)
        }
    }
}
