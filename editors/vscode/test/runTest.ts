import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import * as childProcess from 'child_process';
import { downloadAndUnzipVSCode, runTests } from '@vscode/test-electron';

async function main() {
    let profileRoot: string | undefined;
    try {
        const extensionDevelopmentPath = path.resolve(__dirname, '../../');
        const extensionTestsPath = path.resolve(__dirname, './suite/index');
        const vscodeCachePath = process.env.NSHARP_VSCODE_TEST_CACHE?.trim()
            || process.env.NSHARP_VSCODE_CACHE_PATH?.trim()
            || path.join(extensionDevelopmentPath, '.vscode-test');
        const vscodeTestVersion = (require(path.join(extensionDevelopmentPath, 'package.json')) as {
            config: { vscodeTestVersion: string }
        }).config.vscodeTestVersion;
        const profileParent = process.env.NSHARP_VSCODE_PROFILE_ROOT?.trim() || os.tmpdir();

        // Default to the simple fixture workspace
        const testWorkspace = process.env.TEST_WORKSPACE
            || path.resolve(__dirname, '../../test/fixtures/simple');

        // Use short temp directories for user data to avoid IPC socket path length issues
        // (macOS limits Unix domain sockets to 104 chars) and isolate installed user extensions.
        // Do not pass --disable-extensions: VS Code 1.120 can leave the extension-test host
        // waiting forever before the test entrypoint runs when that global switch is present.
        fs.mkdirSync(profileParent, { recursive: true });
        profileRoot = fs.mkdtempSync(path.join(profileParent, 'ns-test-'));
        const userDataDir = path.join(profileRoot, 'user-data');
        const extensionsDir = path.join(profileRoot, 'extensions');
        fs.mkdirSync(userDataDir, { recursive: true });
        fs.mkdirSync(extensionsDir, { recursive: true });
        const settingsPath = path.join(userDataDir, 'User', 'settings.json');
        fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
        fs.writeFileSync(settingsPath, JSON.stringify({
            'update.mode': 'none',
            'update.showReleaseNotes': false,
            'extensions.autoUpdate': 'off',
            'extensions.autoCheckUpdates': false,
            'telemetry.telemetryLevel': 'off',
            'security.workspace.trust.enabled': false,
            'workbench.startupEditor': 'none'
        }, null, 2));

        const vscodeExecutablePath = await downloadAndUnzipVSCode({
            version: vscodeTestVersion,
            cachePath: vscodeCachePath,
            extensionDevelopmentPath
        });
        if (process.platform === 'darwin') {
            const appBundle = vscodeExecutablePath.match(/^(.*?\.app)(?:\/|$)/)?.[1];
            if (!appBundle) throw new Error(`VS Code executable is outside an app bundle: ${vscodeExecutablePath}`);
            const quarantine = childProcess.spawnSync('xattr', ['-p', 'com.apple.quarantine', appBundle], { stdio: 'ignore' });
            if (quarantine.error || (quarantine.status !== 0 && quarantine.status !== 1)) throw quarantine.error ?? new Error(`Failed to inspect VS Code quarantine attribute (xattr exited ${quarantine.status}).`);
            if (quarantine.status === 0 && childProcess.spawnSync('xattr', ['-dr', 'com.apple.quarantine', appBundle], { stdio: 'ignore' }).status !== 0) throw new Error('Failed to remove VS Code quarantine attribute.');
        }

        console.log('=== N# VS Code Integration Tests ===');
        console.log(`Extension: ${extensionDevelopmentPath}`);
        console.log(`Tests:     ${extensionTestsPath}`);
        console.log(`Workspace: ${testWorkspace}`);
        console.log(`UserData:  ${userDataDir}`);
        console.log(`VS Code:   ${vscodeTestVersion}`);
        console.log(`Cache:     ${vscodeCachePath}`);
        fs.mkdirSync(vscodeCachePath, { recursive: true });

        // Pass test filtering env vars through to the VS Code instance
        const extensionTestsEnv: Record<string, string> = {};
        if (process.env.TEST_SUITE) {
            extensionTestsEnv.TEST_SUITE = process.env.TEST_SUITE;
            console.log(`Filter:    TEST_SUITE=${process.env.TEST_SUITE}`);
        }
        if (process.env.TEST_GREP) {
            extensionTestsEnv.TEST_GREP = process.env.TEST_GREP;
            console.log(`Filter:    TEST_GREP=${process.env.TEST_GREP}`);
        }

        const testOptions = {
            extensionDevelopmentPath,
            extensionTestsPath,
            extensionTestsEnv,
            vscodeExecutablePath,
            launchArgs: [
                testWorkspace,
                '--disable-updates',
                '--disable-telemetry',
                '--skip-welcome',
                '--skip-release-notes',
                '--disable-workspace-trust',
                '--disable-experiments',
                '--use-inmemory-secretstorage',
                '--disable-gpu',
                ...(process.platform === 'darwin' ? ['--use-mock-keychain'] : []),
                ...(process.platform === 'linux' ? ['--password-store=basic'] : []),
                `--user-data-dir=${userDataDir}`,
                `--extensions-dir=${extensionsDir}`,
                '--disable-extension',
                'vscode.git',
                '--disable-extension',
                'vscode.github',
                '--disable-extension',
                'vscode.github-authentication',
                '--disable-extension',
                'GitHub.copilot',
                '--disable-extension',
                'GitHub.copilot-chat',
                '--disable-extension',
                'github.copilot',
                '--disable-extension',
                'github.copilot-chat',
            ],
        };

        await runTests(testOptions);
    } catch (err) {
        console.error('Failed to run tests:', err);
        process.exitCode = 1;
    } finally {
        if (profileRoot) {
            fs.rmSync(profileRoot, { recursive: true, force: true });
        }
    }
}

main();
