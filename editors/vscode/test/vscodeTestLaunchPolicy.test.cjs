const assert = require('node:assert/strict');
const childProcess = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const policy = require('../out/test/vscodeTestLaunchPolicy.js');

test('VS Code test binary is pinned to a stable release', () => {
    assert.equal(policy.vscodeTestVersion, '1.138.0');
});

test('VS Code test launch arguments suppress dialog-producing integrations', () => {
    const darwinArgs = policy.createVSCodeTestLaunchArgs('/workspace', '/profile/user-data', '/profile/extensions', 'darwin');
    const linuxArgs = policy.createVSCodeTestLaunchArgs('/workspace', '/profile/user-data', '/profile/extensions', 'linux');

    for (const arg of [
        '--disable-updates',
        '--disable-telemetry',
        '--skip-welcome',
        '--skip-release-notes',
        '--disable-workspace-trust',
        '--disable-experiments',
        '--use-inmemory-secretstorage',
        '--user-data-dir=/profile/user-data',
        '--extensions-dir=/profile/extensions'
    ]) {
        assert.ok(darwinArgs.includes(arg), `missing macOS test launch argument: ${arg}`);
        assert.ok(linuxArgs.includes(arg), `missing Linux test launch argument: ${arg}`);
    }

    assert.ok(darwinArgs.includes('--use-mock-keychain'));
    assert.ok(!linuxArgs.includes('--use-mock-keychain'));
    assert.ok(linuxArgs.includes('--password-store=basic'));
    assert.ok(!darwinArgs.includes('--password-store=basic'));
});

test('isolated VS Code test profile disables prompts and automatic updates', () => {
    assert.deepEqual(policy.vscodeTestSettings, {
        'update.mode': 'none',
        'update.showReleaseNotes': false,
        'extensions.autoUpdate': 'off',
        'extensions.autoCheckUpdates': false,
        'telemetry.telemetryLevel': 'off',
        'security.workspace.trust.enabled': false,
        'workbench.startupEditor': 'none'
    });
});

test('settings are written to the isolated VS Code user profile', () => {
    const profileRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'nsharp-vscode-policy-'));
    try {
        const settingsPath = policy.writeVSCodeTestSettings(profileRoot);
        assert.equal(settingsPath, path.join(profileRoot, 'User', 'settings.json'));
        assert.deepEqual(JSON.parse(fs.readFileSync(settingsPath, 'utf8')), policy.vscodeTestSettings);
    } finally {
        fs.rmSync(profileRoot, { recursive: true, force: true });
    }
});

test('macOS quarantine is removed recursively before VS Code launch', {
    skip: process.platform !== 'darwin'
}, async () => {
    const profileRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'nsharp-vscode-quarantine-'));
    const appBundlePath = path.join(profileRoot, 'Fake VS Code.app');
    const executablePath = path.join(appBundlePath, 'Contents', 'MacOS', 'Code');
    try {
        fs.mkdirSync(path.dirname(executablePath), { recursive: true });
        fs.writeFileSync(executablePath, 'test executable');
        childProcess.execFileSync('xattr', ['-w', 'com.apple.quarantine', '0081;test', appBundlePath]);
        childProcess.execFileSync('xattr', ['-w', 'com.apple.quarantine', '0081;test', executablePath]);

        await policy.removeMacQuarantineFromVSCode(executablePath);

        const attributes = childProcess.execFileSync('xattr', ['-lr', appBundlePath], { encoding: 'utf8' });
        assert.ok(!attributes.includes('com.apple.quarantine'));
    } finally {
        fs.rmSync(profileRoot, { recursive: true, force: true });
    }
});
