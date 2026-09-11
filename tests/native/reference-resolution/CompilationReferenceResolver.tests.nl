namespace NSharpLang.ReferenceResolution.Tests

import System
import System.IO
import System.Text.Json

func ResolverJsonErrorMessageContains(stdout: string, fragment: string): bool {
    document := JsonDocument.Parse(stdout)
    found := false
    try {
        error := document.RootElement.GetProperty("error")
        message := error.GetProperty("message").GetString() ?? ""
        found = message.Contains(fragment, StringComparison.Ordinal)
    } finally {
        document.Dispose()
    }
    return found
}

test "real build and publish keep project and local NuGet runtime assets executable" {
    scratch := ResolverNewTempDirectory("build-publish")
    packagesRoot := Path.Combine(scratch, "packages")
    previousPackages := Environment.GetEnvironmentVariable("NUGET_PACKAGES")
    try {
        ResolverPrepareNewtonsoftCache(packagesRoot)
        Environment.SetEnvironmentVariable("NUGET_PACKAGES", packagesRoot)

        buildRoot := Path.Combine(scratch, "build-project")
        Directory.CreateDirectory(buildRoot)
        ResolverWriteProjectReferenceFixture(buildRoot)
        buildOutput := Path.Combine(buildRoot, "dist")
        build := ResolverRunCli("build --project " + ResolverQuote(buildRoot) + " --backend il -o " + ResolverQuote(buildOutput), buildRoot)
        assert build.ExitCode == 0, build.Stdout + build.Stderr
        assert build.Stdout.Contains("Build successful!", StringComparison.Ordinal)
        assert build.Stderr.Trim().Length == 0, build.Stderr
        buildAssembly := Path.Combine(buildOutput, "App.dll")
        assert File.Exists(buildAssembly)
        assert File.Exists(Path.Combine(buildOutput, "App.runtimeconfig.json"))
        assert File.Exists(Path.Combine(buildOutput, "SharedLib.dll"))
        assert File.Exists(Path.Combine(buildOutput, "Newtonsoft.Json.dll"))
        assert Directory.GetFiles(buildRoot, "*.g.csproj", SearchOption.TopDirectoryOnly).Length == 0
        assert Directory.GetFiles(Path.Combine(buildRoot, "Shared"), "*.g.csproj", SearchOption.TopDirectoryOnly).Length == 0
        buildRun := ResolverRunProcess("dotnet", ResolverQuote(buildAssembly), buildOutput)
        assert buildRun.ExitCode == 0, buildRun.Stderr
        assert buildRun.Stdout.Contains("hello from shared", StringComparison.Ordinal), buildRun.Stdout

        publishRoot := Path.Combine(scratch, "publish-project")
        Directory.CreateDirectory(publishRoot)
        ResolverWriteProjectReferenceFixture(publishRoot)
        publishOutput := Path.Combine(publishRoot, "publish")
        publish := ResolverRunCli("publish --project " + ResolverQuote(publishRoot) + " --backend il --output " + ResolverQuote(publishOutput), publishRoot)
        assert publish.ExitCode == 0, publish.Stdout + publish.Stderr
        assert publish.Stdout.Contains("Publish successful!", StringComparison.Ordinal)
        assert publish.Stderr.Trim().Length == 0, publish.Stderr
        publishAssembly := Path.Combine(publishOutput, "App.dll")
        assert File.Exists(publishAssembly)
        assert File.Exists(Path.Combine(publishOutput, "App.runtimeconfig.json"))
        assert File.Exists(Path.Combine(publishOutput, "SharedLib.dll"))
        assert File.Exists(Path.Combine(publishOutput, "Newtonsoft.Json.dll"))
        assert Directory.GetFiles(publishRoot, "*.g.csproj", SearchOption.TopDirectoryOnly).Length == 0
        assert Directory.GetFiles(Path.Combine(publishRoot, "Shared"), "*.g.csproj", SearchOption.TopDirectoryOnly).Length == 0
        publishRun := ResolverRunProcess("dotnet", ResolverQuote(publishAssembly), publishOutput)
        assert publishRun.ExitCode == 0, publishRun.Stderr
        assert publishRun.Stdout.Contains("hello from shared", StringComparison.Ordinal), publishRun.Stdout
    } finally {
        Environment.SetEnvironmentVariable("NUGET_PACKAGES", previousPackages)
        Directory.Delete(scratch, true)
    }
}

test "Web SDK framework resolution feeds a clean check without analyzer errors" {
    projectRoot := ResolverNewTempDirectory("web-framework")
    try {
        ResolverWriteWebFixture(projectRoot)
        check := ResolverRunCli("check --project " + ResolverQuote(projectRoot), projectRoot)
        assert check.ExitCode == 0, check.Stdout + check.Stderr
        assert check.Stderr == "", check.Stderr
        document := JsonDocument.Parse(check.Stdout)
        assert document.RootElement.GetProperty("ok").GetBoolean()
        assert document.RootElement.GetProperty("summary").GetProperty("errors").GetInt32() == 0
        document.Dispose()
    } finally {
        Directory.Delete(projectRoot, true)
    }
}

test "build and check retain the exact child AOT diagnostic and produce no child output" {
    scratch := ResolverNewTempDirectory("aot-child")
    try {
        buildRoot := Path.Combine(scratch, "build")
        Directory.CreateDirectory(buildRoot)
        ResolverWriteAotProjectFixture(buildRoot, "exe")
        buildOutput := Path.Combine(buildRoot, "dist")
        build := ResolverRunCli("build --project " + ResolverQuote(buildRoot) + " --backend il --aot -o " + ResolverQuote(buildOutput), buildRoot)
        assert build.ExitCode == 1
        assert (build.Stdout + build.Stderr).Contains("AOT builds require successful N# columnar emission", StringComparison.Ordinal)
        assert !File.Exists(Path.Combine(buildOutput, "SharedLib.dll"))

        checkRoot := Path.Combine(scratch, "check")
        Directory.CreateDirectory(checkRoot)
        ResolverWriteAotProjectFixture(checkRoot, "library")
        check := ResolverRunCli("check --project " + ResolverQuote(checkRoot) + " --aot", checkRoot)
        assert check.ExitCode == 1
        document := JsonDocument.Parse(check.Stdout)
        assert !document.RootElement.GetProperty("ok").GetBoolean()
        document.Dispose()
        assert ResolverJsonErrorMessageContains(check.Stdout, "AOT builds require successful N# columnar emission")
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "query does not build a referenced project that the next normal build does build" {
    projectRoot := ResolverNewTempDirectory("query-no-build")
    try {
        sharedRoot := Path.Combine(projectRoot, "Shared")
        Directory.CreateDirectory(sharedRoot)
        ResolverWrite(
            Path.Combine(sharedRoot, "project.yml"),
            "name: QueryChild\noutputType: library\ntargetFramework: net10.0"
        )
        ResolverWrite(Path.Combine(sharedRoot, "Shared.nl"), "func ChildValue(): int {\n    return 17\n}")
        ResolverWrite(
            Path.Combine(projectRoot, "project.yml"),
            "name: QueryRoot\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - project: Shared/project.yml"
        )
        ResolverWrite(Path.Combine(projectRoot, "Program.nl"), "func RootValue(): int {\n    return 3\n}")

        childOutput := Path.Combine(Path.Combine(Path.Combine(sharedRoot, "bin"), "Debug/net10.0"), "QueryChild.dll")
        assert !File.Exists(childOutput)
        query := ResolverRunCli("query ast --project " + ResolverQuote(projectRoot), projectRoot)
        assert query.ExitCode == 0, query.Stdout + query.Stderr
        document := JsonDocument.Parse(query.Stdout)
        assert document.RootElement.GetProperty("ok").GetBoolean()
        document.Dispose()
        assert !File.Exists(childOutput), "nlc query built a referenced project"

        buildOutput := Path.Combine(projectRoot, "dist")
        build := ResolverRunCli("build --project " + ResolverQuote(projectRoot) + " --backend il -o " + ResolverQuote(buildOutput), projectRoot)
        assert build.ExitCode == 0, build.Stdout + build.Stderr
        assert File.Exists(childOutput), "the normal build did not build the referenced project"
        assert File.Exists(Path.Combine(buildOutput, "QueryChild.dll"))
    } finally {
        Directory.Delete(projectRoot, true)
    }
}
