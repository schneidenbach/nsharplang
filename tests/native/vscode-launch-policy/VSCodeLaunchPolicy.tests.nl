namespace NSharpLang.VSCodeLaunchPolicy.Tests

import System
import System.IO

func VSCodeRepositoryRoot(): string {
    current: string? = Path.GetFullPath(Environment.CurrentDirectory)
    while current != null {
        root := current ?? ""
        if File.Exists(Path.Combine(root, "AGENTS.md")) && Directory.Exists(Path.Combine(root, "editors")) {
            return root
        }
        parent := Path.GetDirectoryName(root)
        if parent == null || parent == "" || parent == root {
            current = null
        } else {
            current = parent
        }
    }
    return ""
}

func VSCodeLaunchSource(name: string): string {
    return File.ReadAllText(Path.Combine(Path.Combine(Path.Combine(VSCodeRepositoryRoot(), "editors"), "vscode"), name))
}

test "VS Code launch policy pins stable VS Code and test-electron versions" {
    packageJson := VSCodeLaunchSource("package.json")
    assert packageJson.Contains("\"vscodeTestVersion\": \"1.138.0\"")
    assert packageJson.Contains("\"@vscode/test-electron\": \"3.1.0\"")
    assert VSCodeLaunchSource("test/runTest.ts").Contains("config.vscodeTestVersion")
    assert VSCodeLaunchSource("src/test/runTest.ts").Contains("config.vscodeTestVersion")
}

test "VS Code launch policy disables updates welcome release notes trust and telemetry" {
    standard := VSCodeLaunchSource("test/runTest.ts")
    headless := VSCodeLaunchSource("src/test/runTest.ts")
    assert standard.Contains("--disable-updates") && headless.Contains("--disable-updates")
    assert standard.Contains("--disable-telemetry") && headless.Contains("--disable-telemetry")
    assert standard.Contains("--skip-welcome") && headless.Contains("--skip-welcome")
    assert standard.Contains("--skip-release-notes") && headless.Contains("--skip-release-notes")
    assert standard.Contains("--disable-workspace-trust") && headless.Contains("--disable-workspace-trust")
    assert standard.Contains("--disable-experiments") && headless.Contains("--disable-experiments")
    assert standard.Contains("--use-inmemory-secretstorage") && headless.Contains("--use-inmemory-secretstorage")
}

test "VS Code launch policy isolates profiles and selects platform key stores" {
    standard := VSCodeLaunchSource("test/runTest.ts")
    headless := VSCodeLaunchSource("src/test/runTest.ts")
    assert standard.Contains("--user-data-dir=${userDataDir}") && headless.Contains("--user-data-dir=${userDataDir}")
    assert standard.Contains("--extensions-dir=${extensionsDir}") && headless.Contains("--extensions-dir=${extensionsDir}")
    assert standard.Contains("--use-mock-keychain") && headless.Contains("--use-mock-keychain")
    assert standard.Contains("--password-store=basic") && headless.Contains("--password-store=basic")
}

test "VS Code launch policy writes settings that disable prompts and automatic changes" {
    standard := VSCodeLaunchSource("test/runTest.ts")
    headless := VSCodeLaunchSource("src/test/runTest.ts")
    assert standard.Contains("'update.mode': 'none'") && headless.Contains("'update.mode': 'none'")
    assert standard.Contains("'update.showReleaseNotes': false") && headless.Contains("'update.showReleaseNotes': false")
    assert standard.Contains("'extensions.autoUpdate': 'off'") && headless.Contains("'extensions.autoUpdate': 'off'")
    assert standard.Contains("'extensions.autoCheckUpdates': false") && headless.Contains("'extensions.autoCheckUpdates': false")
    assert standard.Contains("'telemetry.telemetryLevel': 'off'") && headless.Contains("'telemetry.telemetryLevel': 'off'")
    assert standard.Contains("'security.workspace.trust.enabled': false") && headless.Contains("'security.workspace.trust.enabled': false")
    assert standard.Contains("'workbench.startupEditor': 'none'") && headless.Contains("'workbench.startupEditor': 'none'")
}

test "VS Code launch policy removes macOS quarantine after download and before launch" {
    standard := VSCodeLaunchSource("test/runTest.ts")
    headless := VSCodeLaunchSource("src/test/runTest.ts")
    assert standard.IndexOf("await downloadAndUnzipVSCode({") < standard.IndexOf("xattr")
    assert headless.IndexOf("await downloadAndUnzipVSCode({") < headless.IndexOf("xattr")
    assert standard.Contains("spawnSync('xattr', ['-p', 'com.apple.quarantine', appBundle], { stdio: 'ignore' })")
    assert headless.Contains("spawnSync('xattr', ['-p', 'com.apple.quarantine', appBundle], { stdio: 'ignore' })")
    assert standard.Contains("quarantine.status !== 0 && quarantine.status !== 1")
    assert headless.Contains("quarantine.status !== 0 && quarantine.status !== 1")
    assert standard.Contains("quarantine.status === 0 && childProcess.spawnSync('xattr', ['-dr', 'com.apple.quarantine', appBundle], { stdio: 'ignore' }).status !== 0")
    assert headless.Contains("quarantine.status === 0 && childProcess.spawnSync('xattr', ['-dr', 'com.apple.quarantine', appBundle], { stdio: 'ignore' }).status !== 0")
    assert !standard.Contains("['-lr', appBundle]") && !headless.Contains("['-lr', appBundle]")
}
