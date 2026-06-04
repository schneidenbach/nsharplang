import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import { runTests, type TestOptions } from '@vscode/test-electron';

async function main() {
    try {
        const extensionDevelopmentPath = path.resolve(__dirname, '../../');
        const extensionTestsPath = path.resolve(__dirname, './suite/index');
        const vscodeVersion = getVSCodeTestVersion();
        const vscodeCachePath = process.env.NSHARP_VSCODE_TEST_CACHE?.trim();
        const profileParent = process.env.NSHARP_VSCODE_PROFILE_ROOT?.trim() || os.tmpdir();

        // Default to the simple fixture workspace
        const testWorkspace = process.env.TEST_WORKSPACE
            || path.resolve(__dirname, '../../test/fixtures/simple');

        // Use short temp directories for user data to avoid IPC socket path length issues
        // (macOS limits Unix domain sockets to 104 chars) and isolate installed user extensions.
        // Do not pass --disable-extensions: VS Code 1.120 can leave the extension-test host
        // waiting forever before the test entrypoint runs when that global switch is present.
        fs.mkdirSync(profileParent, { recursive: true });
        const profileRoot = fs.mkdtempSync(path.join(profileParent, 'ns-test-'));
        const userDataDir = path.join(profileRoot, 'user-data');
        const extensionsDir = path.join(profileRoot, 'extensions');
        fs.mkdirSync(userDataDir, { recursive: true });
        fs.mkdirSync(extensionsDir, { recursive: true });

        console.log('=== N# VS Code Integration Tests ===');
        console.log(`Extension: ${extensionDevelopmentPath}`);
        console.log(`Tests:     ${extensionTestsPath}`);
        console.log(`Workspace: ${testWorkspace}`);
        console.log(`UserData:  ${userDataDir}`);
        if (vscodeVersion) {
            console.log(`VS Code:   ${vscodeVersion}`);
        }
        if (vscodeCachePath) {
            console.log(`Cache:     ${vscodeCachePath}`);
            fs.mkdirSync(vscodeCachePath, { recursive: true });
        }

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

        const testOptions: TestOptions = {
            extensionDevelopmentPath,
            extensionTestsPath,
            extensionTestsEnv,
            version: vscodeVersion,
            cachePath: vscodeCachePath,
            launchArgs: [
                testWorkspace,
                '--disable-workspace-trust',
                '--password-store=basic',
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
                '--disable-gpu',
                `--user-data-dir=${userDataDir}`,
                `--extensions-dir=${extensionsDir}`,
            ],
        };

        await runTests(testOptions);

        // Clean up the temporary profile.
        try {
            fs.rmSync(profileRoot, { recursive: true, force: true });
        } catch {
            // Best effort cleanup
        }
    } catch (err) {
        console.error('Failed to run tests:', err);
        process.exit(1);
    }
}

main();

function getVSCodeTestVersion(): TestOptions['version'] {
    const version = process.env.NSHARP_VSCODE_TEST_VERSION?.trim();
    return version ? version as TestOptions['version'] : undefined;
}
