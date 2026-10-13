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
    launchPolicy := VSCodeLaunchSource("test/launchPolicy.ts")
    visualRunner := VSCodeLaunchSource("test/visual/runVisualScenario.ts")
    assert packageJson.Contains("\"vscodeTestVersion\": \"1.138.0\"")
    assert packageJson.Contains("\"@vscode/test-electron\": \"3.1.0\"")
    assert launchPolicy.Contains("downloadAndUnzipVSCode")
    assert launchPolicy.Contains("config.vscodeTestVersion")
    assert VSCodeLaunchSource("test/runTest.ts").Contains("downloadPinnedVscode")
    assert VSCodeLaunchSource("src/test/runTest.ts").Contains("downloadPinnedVscode")
    assert visualRunner.Contains("downloadPinnedVscode")
    assert visualRunner.Contains("runTests")
}

test "VS Code launch policy disables updates welcome release notes trust and telemetry" {
    standard := VSCodeLaunchSource("test/runTest.ts")
    headless := VSCodeLaunchSource("src/test/runTest.ts")
    visualRunner := VSCodeLaunchSource("test/visual/runVisualScenario.ts")
    policy := VSCodeLaunchSource("test/launchPolicy.ts")
    assert standard.Contains("createVscodeLaunchArgs") && headless.Contains("createVscodeLaunchArgs")
    assert visualRunner.Contains("createVscodeLaunchArgs")
    assert policy.Contains("--disable-updates")
    assert policy.Contains("--disable-telemetry")
    assert policy.Contains("--skip-welcome")
    assert policy.Contains("--skip-release-notes")
    assert policy.Contains("--disable-workspace-trust")
    assert policy.Contains("--disable-experiments")
    assert policy.Contains("--use-inmemory-secretstorage")
}

test "VS Code launch policy isolates profiles and selects platform key stores" {
    policy := VSCodeLaunchSource("test/launchPolicy.ts")
    assert policy.Contains("--user-data-dir=${profile.userDataDir}")
    assert policy.Contains("--extensions-dir=${profile.extensionsDir}")
    assert policy.Contains("--use-mock-keychain")
    assert policy.Contains("--password-store=basic")
}

test "VS Code launch policy writes settings that disable prompts and automatic changes" {
    policy := VSCodeLaunchSource("test/launchPolicy.ts")
    assert policy.Contains("'update.mode': 'none'")
    assert policy.Contains("'update.showReleaseNotes': false")
    assert policy.Contains("'extensions.autoUpdate': 'off'")
    assert policy.Contains("'extensions.autoCheckUpdates': false")
    assert policy.Contains("'telemetry.telemetryLevel': 'off'")
    assert policy.Contains("'security.workspace.trust.enabled': false")
    assert policy.Contains("'workbench.startupEditor': 'none'")
}

test "VS Code launch policy removes macOS quarantine after download and before launch" {
    policy := VSCodeLaunchSource("test/launchPolicy.ts")
    assert policy.IndexOf("await downloadAndUnzipVSCode({") < policy.IndexOf("removeMacQuarantine(executablePath)")
    assert policy.Contains("spawnSync('xattr', ['-p', 'com.apple.quarantine', appBundle], { stdio: 'ignore' })")
    assert policy.Contains("quarantine.status !== 0 && quarantine.status !== 1")
    assert policy.Contains("spawnSync('xattr', ['-dr', 'com.apple.quarantine', appBundle], { stdio: 'ignore' })")
    assert !policy.Contains("['-lr', appBundle]")
}
