namespace NSharpLang.GateScriptContracts.Tests

import System.IO

// ─── THE INSTALLER CONTRACTS ──────────────────────────────────────────────────────────────────
//
// Replaces `tests/SetupLocalScriptTests.cs`.
//
// Three scripts ship to users: `./install-local.sh` (the top-level developer install),
// `scripts/setup-local.sh` (what it delegates to), and `scripts/install.sh` (the public
// curl-to-bash installer). Every row below runs one of them in `--dry-run` or `--help` mode with
// `HOME` pointed at a throwaway directory, so nothing is ever installed and nothing outside that
// directory is written. The one row that does a real (non-dry-run) install points `--source` and
// `--install-dir` at fake trees under that same throwaway HOME, with a fake `dotnet` and a fake
// `nlc` on PATH. One additional row sources the shipped package helper directly under dry-run so
// its package loop and command boundary can be observed without invoking the entire installer.
//
// The generous 180s ceiling is inherited from the deleted C#: these scripts finish in well under a
// second normally, but a tight cap intermittently tripped under the full product gate's concurrent
// load (process spawn + login-shell init slow under contention).
func PublicInstallCommand(): string {
    return "curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . \"$HOME/.nsharp/env\""
}

// `bash -lc "<command>"` at the repository root with a throwaway HOME, mirroring the deleted C#'s
// four environment pins exactly.
func RunInstaller(home: string, command: string): ProcessRun {
    launch := BashLaunch(command, 180000)
    launch.WithEnvironment("HOME", home)
    launch.WithEnvironment("SHELL", "/bin/zsh")
    launch.WithEnvironment("DOTNET_CLI_HOME", home)
    return Run(launch)
}

func PackageLoopTraceScript(repositoryRoot: string, outputDirectory: string): string {
    return """set -euo pipefail
export PATH=/usr/bin:/bin
export NLC_MSBUILD_SINGLE_NODE=0
export NSHARP_REPO_ROOT='""" + repositoryRoot.Replace("'", "'\\''") + """'
export NSHARP_TEST_OUTPUT='""" + outputDirectory.Replace("'", "'\\''") + """'
source "$NSHARP_REPO_ROOT/scripts/lib/common.sh"
source "$NSHARP_REPO_ROOT/scripts/lib/packages.sh"

# Record every argv value so the exact command boundary is observable.
nsharp_run_in_dir() {
    local directory="$1"
    shift

    printf 'DIR<%s>|' "$directory" >> "$HOME/package loop trace.log"
    for argument in "$@"; do
        printf '<arg>%s|' "$argument" >> "$HOME/package loop trace.log"
    done
    printf '\n' >> "$HOME/package loop trace.log"
}

DRY_RUN=1
nsharp_pack_package_set "$NSHARP_TEST_OUTPUT" q
"""
}

test "the synchronous package loop traces runtime once and exact compiler PDB flags in dry-run" {
    home := NewTempDirectory("nsharp-package-loop-test")
    try {
        outputDirectory := Path.Combine(home, "package output")
        probe := Path.Combine(home, "package loop probe.sh")
        tracePath := Path.Combine(home, "package loop trace.log")
        File.WriteAllText(probe, PackageLoopTraceScript(RepositoryRoot(), outputDirectory))

        run := RunInstaller(home, "bash \"$HOME/package loop probe.sh\"")
        assert run.ExitCode == 0, "package-loop probe failed with " + run.Report()

        repositoryRoot := RepositoryRoot()
        flags := "<arg>--disable-build-servers|<arg>-nr:false|"
        boundary := "DIR<" + repositoryRoot + ">|"
        output := "<arg>" + outputDirectory + "|"
        runtime := "src/NSharpLang.Runtime/NSharpLang.Runtime.csproj"
        restore := "src/NSharpLang.Compiler.Core/NSharpLang.Compiler.Core.csproj"
        buildTasks := "src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj"
        expected := boundary + "<arg>dotnet|<arg>pack|" + flags + "<arg>" + runtime + "|<arg>-c|<arg>Release|<arg>-o|" + output + "<arg>-v|<arg>q|\n"
        expected = expected + boundary + "<arg>dotnet|<arg>restore|" + flags + "<arg>" + restore + "|<arg>--force-evaluate|<arg>-v|<arg>q|\n"
        expected = expected + boundary + "<arg>dotnet|<arg>build|" + flags + "<arg>" + buildTasks + "|<arg>-c|<arg>Release|<arg>-v|<arg>q|\n"
        expected = expected + boundary + "<arg>dotnet|<arg>pack|" + flags + "<arg>src/NSharpLang.Sdk/NSharpLang.Sdk.csproj|<arg>-c|<arg>Release|<arg>-o|" + output + "<arg>-v|<arg>q|\n"
        expected = expected + boundary + "<arg>dotnet|<arg>pack|" + flags + "<arg>templates/NSharpLang.Templates.csproj|<arg>-c|<arg>Release|<arg>-o|" + output + "<arg>-v|<arg>q|\n"
        // Compiler.Model and Compiler.Syntax are carved out of Core and packed before it, lowest first:
        // Syntax's package depends on Model's, and Core's on Syntax's. Compiler.Tooling and
        // Compiler.Driver are carved out ABOVE Core and packed after it, in that order (Driver's package
        // depends on Tooling's, Tooling's on Core's), before the Compiler facade whose package depends
        // on Driver's.
        expected = expected + boundary + "<arg>dotnet|<arg>pack|" + flags + "<arg>src/NSharpLang.Compiler.Model/NSharpLang.Compiler.Model.csproj|<arg>-c|<arg>Release|<arg>-o|" + output + "<arg>-p:DebugSymbols=false|<arg>-p:DebugType=None|<arg>-v|<arg>q|\n"
        expected = expected + boundary + "<arg>dotnet|<arg>pack|" + flags + "<arg>src/NSharpLang.Compiler.Syntax/NSharpLang.Compiler.Syntax.csproj|<arg>-c|<arg>Release|<arg>-o|" + output + "<arg>-p:DebugSymbols=false|<arg>-p:DebugType=None|<arg>-v|<arg>q|\n"
        expected = expected + boundary + "<arg>dotnet|<arg>pack|" + flags + "<arg>" + restore + "|<arg>-c|<arg>Release|<arg>-o|" + output + "<arg>-p:DebugSymbols=false|<arg>-p:DebugType=None|<arg>-v|<arg>q|\n"
        expected = expected + boundary + "<arg>dotnet|<arg>pack|" + flags + "<arg>src/NSharpLang.Compiler.Tooling/NSharpLang.Compiler.Tooling.csproj|<arg>-c|<arg>Release|<arg>-o|" + output + "<arg>-p:DebugSymbols=false|<arg>-p:DebugType=None|<arg>-v|<arg>q|\n"
        expected = expected + boundary + "<arg>dotnet|<arg>pack|" + flags + "<arg>src/NSharpLang.Compiler.Driver/NSharpLang.Compiler.Driver.csproj|<arg>-c|<arg>Release|<arg>-o|" + output + "<arg>-p:DebugSymbols=false|<arg>-p:DebugType=None|<arg>-v|<arg>q|\n"
        expected = expected + boundary + "<arg>dotnet|<arg>pack|" + flags + "<arg>src/NSharpLang.Compiler/Compiler.csproj|<arg>-c|<arg>Release|<arg>-o|" + output + "<arg>-p:DebugSymbols=false|<arg>-p:DebugType=None|<arg>-v|<arg>q|\n"

        traceText := File.ReadAllText(tracePath)
        assert traceText == expected, "unexpected package-loop trace:\n" + traceText + "\n--- expected ---\n" + expected
    } finally {
        DeleteTempDirectory(home)
    }
}

test "install-local dry-run installs the first-class N# toolchain with VS Code on by default and never touches dotnet tool" {
    home := NewTempDirectory("nsharp-setup-local-test")
    try {
        run := RunInstaller(home, "./install-local.sh --dry-run")

        assert run.ExitCode == 0, "setup-local dry-run failed with " + run.Report()
        assert run.Stdout.Contains("Deploying Local N# Toolset")
        assert run.Stdout.Contains("VS Code install:   yes")
        assert run.Stdout.Contains("publish nlc and nsharp-lsp")
        assert run.Stdout.Contains("install toolset")
        assert run.Stdout.Contains("dotnet new install")
        assert run.Stdout.Contains("npm run build-server")
        assert run.Stdout.Contains("code --install-extension")
        assert run.Stdout.Contains(".vsix --force")
        assert run.Stdout.Contains(".nsharp/env")
        assert run.Stdout.Contains("DOTNET_ROOT")
        assert run.Stdout.Contains("nlc doctor --require-vscode")
        assert run.Stdout.Contains("nlc new MyApp")
        assert !run.Stdout.Contains("--skip-vscode")
        assert !run.Stdout.Contains("dotnet" + " tool")
    } finally {
        DeleteTempDirectory(home)
    }
}

test "install-local --help documents the top-level command, both VS Code switches, and NSHARP_INSTALL_DIR" {
    home := NewTempDirectory("nsharp-install-local-help-test")
    try {
        run := RunInstaller(home, "./install-local.sh --help")

        assert run.ExitCode == 0, "install-local help failed with " + run.Report()
        assert run.Stdout.Contains("Usage: ./install-local.sh [options]")
        assert run.Stdout.Contains("--with-vscode        Also package/install the VS Code extension (default)")
        assert run.Stdout.Contains("--skip-vscode        Do not package/install the VS Code extension")
        assert run.Stdout.Contains("NSHARP_INSTALL_DIR")
    } finally {
        DeleteTempDirectory(home)
    }
}

test "install-local --skip-vscode dry-run keeps the CLI-only path and never offers to install the extension" {
    home := NewTempDirectory("nsharp-install-local-skip-vscode-test")
    try {
        run := RunInstaller(home, "./install-local.sh --dry-run --skip-vscode")

        assert run.ExitCode == 0, "install-local skip-vscode dry-run failed with " + run.Report()
        assert run.Stdout.Contains("VS Code install:   no")
        assert run.Stdout.Contains("--skip-vscode")
        assert run.Stdout.Contains("nlc doctor --skip-vscode")
        assert !run.Stdout.Contains("code --install-extension")
    } finally {
        DeleteTempDirectory(home)
    }
}

test "scripts/setup-local.sh run directly still skips VS Code by default" {
    home := NewTempDirectory("nsharp-setup-local-direct-test")
    try {
        run := RunInstaller(home, "scripts/setup-local.sh --dry-run")

        assert run.ExitCode == 0, "setup-local direct dry-run failed with " + run.Report()
        assert run.Stdout.Contains("VS Code install:   no")
        assert run.Stdout.Contains("--skip-vscode")
        assert run.Stdout.Contains("nlc doctor --skip-vscode")
    } finally {
        DeleteTempDirectory(home)
    }
}

test "the public installer's help shows the single-line curl installer and its source, install-dir and no-path-update switches" {
    home := NewTempDirectory("nsharp-install-help-test")
    try {
        run := RunInstaller(home, "scripts/install.sh --help")

        assert run.ExitCode == 0, "install help failed with " + run.Report()
        assert run.Stdout.Contains(PublicInstallCommand())
        assert run.Stdout.Contains("--source SOURCE")
        assert run.Stdout.Contains("--install-dir DIR")
        assert run.Stdout.Contains("--no-path-update")
    } finally {
        DeleteTempDirectory(home)
    }
}

test "the public installer's dry-run copies the compiler tools, installs templates, bootstraps PATH, and never touches dotnet tool" {
    home := NewTempDirectory("nsharp-install-dry-run-test")
    try {
        run := RunInstaller(home, "scripts/install.sh --dry-run --skip-vscode")

        assert run.ExitCode == 0, "install dry-run failed with " + run.Report()
        assert run.Stdout.Contains("Installing N# toolchain")
        assert run.Stdout.Contains("copy bin/lib/packages")
        assert run.Stdout.Contains("dotnet new install")
        assert run.Stdout.Contains("Ensuring nlc is on PATH for future shells")
        assert run.Stdout.Contains(".nsharp/env")
        assert run.Stdout.Contains("Skipping VS Code extension (--skip-vscode)")
        assert !run.Stdout.Contains("dotnet" + " tool")
    } finally {
        DeleteTempDirectory(home)
    }
}

// The one non-dry-run row. It builds a fake toolset and a fake `dotnet`/`nlc` under the throwaway
// HOME, installs into a path WITH A SPACE IN IT, and then reads back the three artifacts a template
// restore depends on: the env file, the shared NuGet.config, and the arguments the installer passed
// to `dotnet`.
func CustomInstallDirScript(): string {
    return """
set -euo pipefail
mkdir -p "$HOME/fake-bin/shared/Microsoft.NETCore.App/10.0.0"
mkdir -p "$HOME/toolset/bin" "$HOME/toolset/lib" "$HOME/toolset/packages"

cat > "$HOME/fake-bin/dotnet" <<'DOTNET'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/dotnet.args"
if [[ "${1:-}" == "--list-runtimes" ]]; then
  echo "Microsoft.NETCore.App 10.0.0 [$HOME/fake-bin/shared/Microsoft.NETCore.App]"
fi
exit 0
DOTNET
chmod +x "$HOME/fake-bin/dotnet"

cat > "$HOME/toolset/bin/nlc" <<'NLC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/nlc.args"
exit 0
NLC
chmod +x "$HOME/toolset/bin/nlc"

touch "$HOME/toolset/packages/NSharpLang.Templates.1.0.0.nupkg"
PATH="$HOME/fake-bin:$PATH" scripts/install.sh --source "$HOME/toolset" --install-dir "$HOME/custom root" --skip-vscode --no-path-update
"""
}

test "the public installer writes a template-restore environment rooted at a custom install directory" {
    home := NewTempDirectory("nsharp-install-custom-root-test")
    try {
        run := RunInstaller(home, CustomInstallDirScript())

        assert run.ExitCode == 0, "install with custom root failed with " + run.Report()

        installRoot := Path.Combine(home, "custom root")
        envFile := File.ReadAllText(Path.Combine(installRoot, "env"))
        assert envFile.Contains("export NSHARP_INSTALL_DIR=\"" + installRoot + "\"")
        assert envFile.Contains("export PATH=\"$NSHARP_INSTALL_DIR/bin:$PATH\"")

        sharedConfig := File.ReadAllText(Path.Combine(installRoot, "NuGet.config"))
        assert sharedConfig.Contains(Path.Combine(installRoot, "packages"))

        dotnetInvocations := File.ReadAllText(Path.Combine(home, "dotnet.args"))
        assert dotnetInvocations.Contains(Path.Combine(Path.Combine(installRoot, "packages"), "NSharpLang.Templates.1.0.0.nupkg"))
    } finally {
        DeleteTempDirectory(home)
    }
}

test "every shipped dotnet template's NuGet.config restores from the install-root environment feed, never a hard-coded home path" {
    templatesDirectory := Path.Combine(RepositoryRoot(), "templates")
    inspectedCount := 0
    for configPath in Directory.EnumerateFiles(templatesDirectory, "NuGet.config", SearchOption.AllDirectories) {
        directoryName := Path.GetFileName(Path.GetDirectoryName(configPath) ?? "")
        if !directoryName.StartsWith("nsharp-") {
            continue
        }

        text := File.ReadAllText(configPath)
        assert text.Contains("%NSHARP_INSTALL_DIR%/packages")
        assert !text.Contains("%HOME%/.nsharp/packages")
        inspectedCount = inspectedCount + 1
    }

    assert inspectedCount > 0
}

test "the public installer's dry-run shows the VS Code marketplace install and the vsix-url fallback" {
    home := NewTempDirectory("nsharp-install-vscode-test")
    try {
        run := RunInstaller(
            home,
            "mkdir -p \"$HOME/fake-bin\" && printf '#!/usr/bin/env bash\\nexit 0\\n' > \"$HOME/fake-bin/code\" && chmod +x \"$HOME/fake-bin/code\" && PATH=\"$HOME/fake-bin:$PATH\" scripts/install.sh --dry-run --no-path-update --vsix-url https://example.test/nsharp.vsix"
        )

        assert run.ExitCode == 0, "install VS Code dry-run failed with " + run.Report()
        assert run.Stdout.Contains("Installing VS Code extension: nsharp.nsharp")
        assert run.Stdout.Contains("code --install-extension nsharp.nsharp --force")
        assert run.Stdout.Contains("curl -fsSL https://example.test/nsharp.vsix -o <temp-vsix>")
        assert run.Stdout.Contains("code --install-extension <temp-vsix> --force")
    } finally {
        DeleteTempDirectory(home)
    }
}
