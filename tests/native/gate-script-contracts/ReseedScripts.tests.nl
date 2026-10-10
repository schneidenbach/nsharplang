namespace NSharpLang.GateScriptContracts.Tests

import System
import System.IO

// ─── THE RESEED CACHE-BYTE CONTRACTS ──────────────────────────────────────────────────────────
//
// `scripts/reseed.sh` deliberately republishes a same-version SDK. That means a successful restore
// alone cannot prove the following build used the freshly verified bootstrap bytes: NuGet may have
// supplied an older extracted copy from its global cache. These rows run the real runbook against a
// tiny synthetic repository, a disposable bootstrap/cache tree, and a fake `dotnet`. The fake
// copies the committed seed bytes into the restore cache (or deliberately makes them missing or
// different); the runbook still performs its real SHA256 and bootstrap-manifest checks. Nothing
// beneath the checkout's bootstrap, artifacts, obj/bin, or shared NuGet cache is touched.
class ReseedFixture {
    Root: string
    Bootstrap: string
    Packages: string
    Stage: string
    PackageSource: string
    Bin: string
    Trace: string

    constructor(root: string, bootstrap: string, packages: string, stage: string, packageSource: string, bin: string, trace: string) {
        Root = root
        Bootstrap = bootstrap
        Packages = packages
        Stage = stage
        PackageSource = packageSource
        Bin = bin
        Trace = trace
    }
}

func ReseedPinnedVersion(): string {
    source := File.ReadAllText(Path.Combine(RepositoryRoot(), "src/NSharpLang.Compiler.Core/global.json"))
    marker := "\"NSharpLang.Sdk\": \""
    markerIndex := source.IndexOf(marker)
    if markerIndex < 0 {
        throw new InvalidOperationException("The compiler Core global.json did not pin NSharpLang.Sdk.")
    }

    remaining := source.Substring(markerIndex + marker.Length)
    closingQuote := remaining.IndexOf("\"")
    if closingQuote < 0 {
        throw new InvalidOperationException("The compiler Core SDK pin had no closing quote.")
    }

    return remaining.Substring(0, closingQuote)
}

func ReseedPackageFile(packageName: string, version: string): string {
    return packageName + "." + version + ".nupkg"
}

func ReseedWriteFile(root: string, relativePath: string, text: string) {
    path := Path.Combine(root, relativePath)
    parent := Path.GetDirectoryName(path)
    if parent != null {
        Directory.CreateDirectory(parent ?? "")
    }

    File.WriteAllText(path, text)
}

func ReseedCopyRepositoryFile(root: string, relativePath: string) {
    destination := Path.Combine(root, relativePath)
    parent := Path.GetDirectoryName(destination)
    if parent != null {
        Directory.CreateDirectory(parent ?? "")
    }

    File.Copy(Path.Combine(RepositoryRoot(), relativePath), destination, true)
}

func ReseedFakeDotnetScript(): string {
    return """
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$FAKE_RESEED_TRACE"

copy_seed_packages() {
  local output_dir="$1"
  mkdir -p "$output_dir"
  cp "$FAKE_RESEED_PACKAGE_SOURCE/NSharpLang.Sdk.$FAKE_RESEED_VERSION.nupkg" "$output_dir/NSharpLang.Sdk.$FAKE_RESEED_VERSION.nupkg"
  cp "$FAKE_RESEED_PACKAGE_SOURCE/NSharpLang.Runtime.$FAKE_RESEED_VERSION.nupkg" "$output_dir/NSharpLang.Runtime.$FAKE_RESEED_VERSION.nupkg"
}

restore_seed_packages() {
  local sdk_dir="$NUGET_PACKAGES/nsharplang.sdk/$FAKE_RESEED_VERSION"
  local runtime_dir="$NUGET_PACKAGES/nsharplang.runtime/$FAKE_RESEED_VERSION"
  mkdir -p "$sdk_dir/Sdk" "$runtime_dir"
  cp "$FAKE_RESEED_PACKAGE_SOURCE/NSharpLang.Sdk.$FAKE_RESEED_VERSION.nupkg" "$sdk_dir/nsharplang.sdk.$FAKE_RESEED_VERSION.nupkg"
  if [[ "$FAKE_RESEED_CACHE_MODE" != "missing" ]]; then
    cp "$FAKE_RESEED_PACKAGE_SOURCE/NSharpLang.Runtime.$FAKE_RESEED_VERSION.nupkg" "$runtime_dir/nsharplang.runtime.$FAKE_RESEED_VERSION.nupkg"
  fi
  if [[ "$FAKE_RESEED_CACHE_MODE" == "mismatch" ]]; then
    printf 'not bootstrap bytes' >> "$sdk_dir/nsharplang.sdk.$FAKE_RESEED_VERSION.nupkg"
  fi
}

case "${1:-}" in
  pack)
    output_dir=""
    shift
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "-o" ]]; then
        output_dir="$2"
        shift 2
        continue
      fi
      shift
    done
    copy_seed_packages "$output_dir"
    ;;
  restore)
    restore_seed_packages
    ;;
  build)
    if [[ "$*" == *"NSharpLang.Compiler.Driver/NSharpLang.Compiler.Driver.csproj"* ]]; then
      printf '%s\n' compiler-build >> "$FAKE_RESEED_TRACE"
    fi
    ;;
esac
"""
}

func ReseedFakeShasumScript(): string {
    return """
#!/usr/bin/env bash
set -euo pipefail

if [[ "${FAKE_RESEED_SHASUM_MODE:-pass}" == "empty-cache-verification" && "$*" == *"/nsharplang.sdk/"* ]]; then
  exit 0
fi

if [[ "${FAKE_RESEED_SHASUM_MODE:-pass}" == "fail-cache-verification" && "$*" == *"/nsharplang.sdk/"* ]]; then
  echo "synthetic cache SHA256 failure" >&2
  exit 73
fi

PATH="$FAKE_RESEED_SYSTEM_PATH"
exec shasum "$@"
"""
}

func ReseedMakeFakeDotnet(fixture: ReseedFixture) {
    dotnet := Path.Combine(fixture.Bin, "dotnet")
    Directory.CreateDirectory(fixture.Bin)
    File.WriteAllText(dotnet, ReseedFakeDotnetScript())

    chmod := new ProcessLaunch("chmod", fixture.Root, 60000)
    chmod.Arguments.Add("+x")
    chmod.Arguments.Add(dotnet)
    chmodRun := Run(chmod)
    if chmodRun.ExitCode != 0 {
        throw new InvalidOperationException("Could not make synthetic dotnet executable: " + chmodRun.Report())
    }
}

func ReseedMakeFakeShasum(fixture: ReseedFixture) {
    shasum := Path.Combine(fixture.Bin, "shasum")
    File.WriteAllText(shasum, ReseedFakeShasumScript())

    chmod := new ProcessLaunch("chmod", fixture.Root, 60000)
    chmod.Arguments.Add("+x")
    chmod.Arguments.Add(shasum)
    chmodRun := Run(chmod)
    if chmodRun.ExitCode != 0 {
        throw new InvalidOperationException("Could not make synthetic shasum executable: " + chmodRun.Report())
    }
}

func CreateReseedFixture(prefix: string): ReseedFixture {
    root := NewTempDirectory(prefix)
    bootstrap := Path.Combine(root, "bootstrap target")
    packages := Path.Combine(root, "NuGet cache")
    stage := Path.Combine(root, "stage output")
    packageSource := Path.Combine(root, "verified seed source")
    bin := Path.Combine(root, "fake bin")
    trace := Path.Combine(root, "dotnet.trace")
    fixture := new ReseedFixture(root, bootstrap, packages, stage, packageSource, bin, trace)

    ReseedCopyRepositoryFile(root, "scripts/reseed.sh")
    ReseedCopyRepositoryFile(root, "scripts/lib/common.sh")
    ReseedCopyRepositoryFile(root, "scripts/lib/packages.sh")
    ReseedCopyRepositoryFile(root, "scripts/verify-bootstrap.py")
    ReseedWriteFile(root, "src/NSharpLang.Compiler.Core/global.json", File.ReadAllText(Path.Combine(RepositoryRoot(), "src/NSharpLang.Compiler.Core/global.json")))
    ReseedWriteFile(root, "src/NSharpLang.Sdk/NSharpLang.Sdk.csproj", "<Project><PropertyGroup><Version>" + ReseedPinnedVersion() + "</Version></PropertyGroup></Project>\n")
    ReseedWriteFile(root, "src/NSharpLang.Sdk/Sdk/Sdk.props", "<Project />\n")

    version := ReseedPinnedVersion()
    Directory.CreateDirectory(packageSource)
    File.Copy(Path.Combine(RepositoryRoot(), "bootstrap/" + ReseedPackageFile("NSharpLang.Sdk", version)), Path.Combine(packageSource, ReseedPackageFile("NSharpLang.Sdk", version)), true)
    File.Copy(Path.Combine(RepositoryRoot(), "bootstrap/" + ReseedPackageFile("NSharpLang.Runtime", version)), Path.Combine(packageSource, ReseedPackageFile("NSharpLang.Runtime", version)), true)

    ReseedMakeFakeDotnet(fixture)
    ReseedMakeFakeShasum(fixture)
    return fixture
}

func RunReseedFixtureWithCacheRoot(fixture: ReseedFixture, cacheMode: string, shasumMode: string, dryRun: bool, cacheRootEnvironmentName: string, packagesDirectory: string, workingDirectory: string): ProcessRun {
    launch := new ProcessLaunch("bash", workingDirectory, 120000)
    launch.Arguments.Add(Path.Combine(fixture.Root, "scripts/reseed.sh"))
    launch.WithEnvironment("PATH", fixture.Bin + ":" + (Environment.GetEnvironmentVariable("PATH") ?? ""))
    launch.WithEnvironment("FAKE_RESEED_SYSTEM_PATH", Environment.GetEnvironmentVariable("PATH") ?? "")
    launch.WithEnvironment("FAKE_RESEED_TRACE", fixture.Trace)
    launch.WithEnvironment("FAKE_RESEED_PACKAGE_SOURCE", fixture.PackageSource)
    launch.WithEnvironment("FAKE_RESEED_VERSION", ReseedPinnedVersion())
    launch.WithEnvironment("FAKE_RESEED_CACHE_MODE", cacheMode)
    launch.WithEnvironment("FAKE_RESEED_SHASUM_MODE", shasumMode)
    launch.WithEnvironment("NSHARP_RESEED_BOOTSTRAP_DIR", fixture.Bootstrap)
    if cacheRootEnvironmentName == "NUGET_PACKAGES" {
        launch.ClearedEnvironmentNames.Add("NSHARP_RESEED_PACKAGES_DIR")
    }
    launch.WithEnvironment(cacheRootEnvironmentName, packagesDirectory)
    launch.WithEnvironment("NSHARP_RESEED_STAGE_ROOT", fixture.Stage)
    launch.WithEnvironment("NSHARP_RESEED_STOP_AFTER", "rebuild2")
    if dryRun {
        launch.WithEnvironment("DRY_RUN", "1")
    }

    return Run(launch)
}

func RunReseedFixtureWithPaths(fixture: ReseedFixture, cacheMode: string, shasumMode: string, dryRun: bool, packagesDirectory: string, workingDirectory: string): ProcessRun {
    return RunReseedFixtureWithCacheRoot(fixture, cacheMode, shasumMode, dryRun, "NSHARP_RESEED_PACKAGES_DIR", packagesDirectory, workingDirectory)
}

func RunReseedFixture(fixture: ReseedFixture, cacheMode: string, dryRun: bool): ProcessRun {
    return RunReseedFixtureWithPaths(fixture, cacheMode, "pass", dryRun, fixture.Packages, fixture.Root)
}

func ReseedCachePackagePathIn(packagesRoot: string, packageName: string): string {
    version := ReseedPinnedVersion()
    lowerName := packageName.ToLowerInvariant()
    return Path.Combine(Path.Combine(Path.Combine(packagesRoot, lowerName), version), lowerName + "." + version + ".nupkg")
}

func ReseedCachePackagePath(fixture: ReseedFixture, packageName: string): string {
    return ReseedCachePackagePathIn(fixture.Packages, packageName)
}

func ReseedBootstrapPackagePath(fixture: ReseedFixture, packageName: string): string {
    return Path.Combine(fixture.Bootstrap, ReseedPackageFile(packageName, ReseedPinnedVersion()))
}

func ReseedBytesMatch(first: byte[], second: byte[]): bool {
    if first.Length != second.Length {
        return false
    }

    index := 0
    while index < first.Length {
        if first[index] != second[index] {
            return false
        }

        index = index + 1
    }

    return true
}

func ReseedTraceCount(fixture: ReseedFixture, value: string): int {
    if !File.Exists(fixture.Trace) {
        return 0
    }

    count := 0
    lines := File.ReadAllText(fixture.Trace).Split('\n')
    index := 0
    while index < lines.Length {
        if lines[index] == value {
            count = count + 1
        }

        index = index + 1
    }

    return count
}

func ReseedSection(run: ProcessRun, label: string): string {
    marker := "Clean self-rebuild of the compiler (" + label + ")"
    index := run.Stdout.IndexOf(marker)
    if index < 0 {
        throw new InvalidOperationException("The reseed run did not reach " + marker + ": " + run.Report())
    }

    return run.Stdout.Substring(index)
}

func RequireReseedRestoreVerificationBuildOrder(run: ProcessRun, label: string) {
    section := ReseedSection(run, label)
    restoreIndex := section.IndexOf("dotnet restore")
    verificationIndex := section.IndexOf("Verifying restored seed package bytes")
    buildIndex := section.IndexOf("dotnet build")

    assert restoreIndex >= 0, section
    assert verificationIndex > restoreIndex, section
    assert buildIndex > verificationIndex, section
}

test "reseed compares matching cache bytes in spaced paths before both self-build stages" {
    fixture := CreateReseedFixture("nsharp reseed cache match")
    try {
        run := RunReseedFixture(fixture, "match", false)

        assert run.ExitCode == 0, run.Report()
        assert ReseedTraceCount(fixture, "compiler-build") == 2, run.Report()
        assert File.Exists(ReseedCachePackagePath(fixture, "NSharpLang.Sdk"))
        assert File.Exists(ReseedCachePackagePath(fixture, "NSharpLang.Runtime"))
        assert ReseedBytesMatch(File.ReadAllBytes(ReseedBootstrapPackagePath(fixture, "NSharpLang.Sdk")), File.ReadAllBytes(ReseedCachePackagePath(fixture, "NSharpLang.Sdk")))
        assert ReseedBytesMatch(File.ReadAllBytes(ReseedBootstrapPackagePath(fixture, "NSharpLang.Runtime")), File.ReadAllBytes(ReseedCachePackagePath(fixture, "NSharpLang.Runtime")))
        RequireReseedRestoreVerificationBuildOrder(run, "stage 1")
        RequireReseedRestoreVerificationBuildOrder(run, "stage 2")
    } finally {
        DeleteTempDirectory(fixture.Root)
    }
}

test "reseed refuses a restored package whose bytes differ from verified bootstrap" {
    fixture := CreateReseedFixture("nsharp-reseed-cache-mismatch")
    try {
        run := RunReseedFixture(fixture, "mismatch", false)

        assert run.ExitCode != 0, run.Report()
        assert run.Stderr.Contains("restored NuGet cache package differs from verified bootstrap"), run.Report()
        assert run.Stderr.Contains(ReseedCachePackagePath(fixture, "NSharpLang.Sdk")), run.Report()
        assert ReseedTraceCount(fixture, "compiler-build") == 0, run.Report()
    } finally {
        DeleteTempDirectory(fixture.Root)
    }
}

test "reseed refuses a restored package that is missing from the effective NuGet cache" {
    fixture := CreateReseedFixture("nsharp-reseed-cache-missing")
    try {
        run := RunReseedFixture(fixture, "missing", false)

        assert run.ExitCode != 0, run.Report()
        assert run.Stderr.Contains("restored NuGet cache package is missing"), run.Report()
        assert run.Stderr.Contains(ReseedCachePackagePath(fixture, "NSharpLang.Runtime")), run.Report()
        assert ReseedTraceCount(fixture, "compiler-build") == 0, run.Report()
    } finally {
        DeleteTempDirectory(fixture.Root)
    }
}

test "reseed refuses a restored package when SHA256 calculation fails" {
    fixture := CreateReseedFixture("nsharp-reseed-cache-hash-failure")
    try {
        run := RunReseedFixtureWithPaths(fixture, "match", "fail-cache-verification", false, fixture.Packages, fixture.Root)

        assert run.ExitCode != 0, run.Report()
        assert run.Stderr.Contains("could not calculate SHA256"), run.Report()
        assert run.Stderr.Contains(ReseedCachePackagePath(fixture, "NSharpLang.Sdk")), run.Report()
        assert ReseedTraceCount(fixture, "compiler-build") == 0, run.Report()
    } finally {
        DeleteTempDirectory(fixture.Root)
    }
}

test "reseed refuses an empty SHA256 result for a restored package" {
    fixture := CreateReseedFixture("nsharp-reseed-cache-empty-hash")
    try {
        run := RunReseedFixtureWithPaths(fixture, "match", "empty-cache-verification", false, fixture.Packages, fixture.Root)

        assert run.ExitCode != 0, run.Report()
        assert run.Stderr.Contains("SHA256 command returned an invalid digest"), run.Report()
        assert run.Stderr.Contains(ReseedCachePackagePath(fixture, "NSharpLang.Sdk")), run.Report()
        assert ReseedTraceCount(fixture, "compiler-build") == 0, run.Report()
    } finally {
        DeleteTempDirectory(fixture.Root)
    }
}

test "reseed resolves a relative NuGet cache override from its repository root" {
    fixture := CreateReseedFixture("nsharp-reseed-relative-cache")
    try {
        caller := Path.Combine(fixture.Root, "outside repository")
        relativePackages := "relative NuGet cache"
        effectivePackages := Path.Combine(fixture.Root, relativePackages)
        Directory.CreateDirectory(caller)
        run := RunReseedFixtureWithPaths(fixture, "match", "pass", false, relativePackages, caller)

        assert run.ExitCode == 0, run.Report()
        assert ReseedTraceCount(fixture, "compiler-build") == 2, run.Report()
        assert File.Exists(ReseedCachePackagePathIn(effectivePackages, "NSharpLang.Sdk")), run.Report()
        assert File.Exists(ReseedCachePackagePathIn(effectivePackages, "NSharpLang.Runtime")), run.Report()
    } finally {
        DeleteTempDirectory(fixture.Root)
    }
}

test "reseed resolves a relative NUGET_PACKAGES root from its repository root" {
    fixture := CreateReseedFixture("nsharp-reseed-relative-nuget-packages")
    try {
        caller := Path.Combine(fixture.Root, "outside repository")
        relativePackages := "direct relative NuGet cache"
        effectivePackages := Path.Combine(fixture.Root, relativePackages)
        Directory.CreateDirectory(caller)
        run := RunReseedFixtureWithCacheRoot(fixture, "match", "pass", false, "NUGET_PACKAGES", relativePackages, caller)

        assert run.ExitCode == 0, run.Report()
        assert ReseedTraceCount(fixture, "compiler-build") == 2, run.Report()
        assert File.Exists(ReseedCachePackagePathIn(effectivePackages, "NSharpLang.Sdk")), run.Report()
        assert File.Exists(ReseedCachePackagePathIn(effectivePackages, "NSharpLang.Runtime")), run.Report()
    } finally {
        DeleteTempDirectory(fixture.Root)
    }
}

test "reseed dry-run prints cache verification without creating override bootstrap cache or stage directories" {
    fixture := CreateReseedFixture("nsharp-reseed-dry-run")
    try {
        run := RunReseedFixture(fixture, "match", true)

        assert run.ExitCode == 0, run.Report()
        assert run.Stdout.Contains("Verifying restored seed package bytes"), run.Report()
        assert run.Stdout.Contains("nsharplang.sdk"), run.Report()
        assert !Directory.Exists(fixture.Bootstrap)
        assert !Directory.Exists(fixture.Packages)
        assert !Directory.Exists(fixture.Stage)
        assert !File.Exists(fixture.Trace)
    } finally {
        DeleteTempDirectory(fixture.Root)
    }
}
