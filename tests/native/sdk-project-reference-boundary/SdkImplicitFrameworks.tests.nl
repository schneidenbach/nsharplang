namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System.IO

// A FRAMEWORK MSBUILD ALREADY REFERENCES IS NOT REFERENCED TWICE.
//
// `nlc` sees only the shared frameworks project.yml names, so a web project writes
// `framework: Microsoft.AspNetCore.App` (as the `nsharp-webapi` template does) and, to see the whole
// base framework, `framework: Microsoft.NETCore.App` (as the docs advise). Under `dotnet build` the
// .NET SDK already references both -- the first from `Microsoft.NET.Sdk.Web` -- and the projection
// used to hand them to MSBuild again: every build
// printed NETSDK1086 once per entry. The row builds that exact project through the SDK and reads the
// build's own output for the warning, then runs the program.
test "a web project naming both shared frameworks builds through the SDK without NETSDK1086" {
    root := SdkBoundaryRepositoryRoot()
    scratch := IlSdkScratch(root, "implicit-frameworks")
    try {
        sdkPackage := SdkBoundaryPreparePackage(root)
        projectDirectory := Path.Combine(scratch, "SdkWebFrameworks")
        projectPath := IlSdkProject(
            projectDirectory,
            "SdkWebFrameworks",
            "name: SdkWebFrameworks\nbackend: il\noutputType: exe\ntargetFramework: net10.0\nsdk: Microsoft.NET.Sdk.Web\ndependencies:\n  - framework: Microsoft.AspNetCore.App\n  - framework: Microsoft.NETCore.App\n",
            sdkPackage
        )
        File.WriteAllText(
            Path.Combine(projectDirectory, "Program.nl"),
            "import System\nimport System.Security.Claims\n\nfunc main() {\n    sp: IServiceProvider? = null\n    id := new ClaimsIdentity()\n    print (sp == null).ToString() + \" \" + id.IsAuthenticated.ToString()\n}\n"
        )

        build := SdkBoundaryRunInCache("build " + SdkBoundaryQuote(projectPath) + " -v m --disable-build-servers", projectDirectory, IlSdkPackages(projectDirectory))
        SdkBoundaryRequireSuccess(build, "SDK build of a web project naming both shared frameworks")
        output := build.Stdout + build.Stderr
        assert !output.Contains("NETSDK1086"), output

        run := SdkBoundaryRunDotnet(SdkBoundaryQuote(IlSdkAssembly(projectDirectory, "SdkWebFrameworks")), projectDirectory)
        SdkBoundaryRequireSuccess(run, "SDK web-frameworks output")
        assert run.Stdout.Trim() == "True False", run.Stdout
    } finally {
        Directory.Delete(scratch, true)
    }
}
