import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import { downloadAndUnzipVSCode, runTests } from '@vscode/test-electron';
import {
    createVSCodeTestLaunchArgs,
    removeMacQuarantineFromVSCode,
    resolveVSCodeTestCachePath,
    vscodeTestVersion,
    writeVSCodeTestSettings
} from './vscodeTestLaunchPolicy';

async function main() {
    let profileRoot: string | undefined;
    try {
        const extensionDevelopmentPath = path.resolve(__dirname, '../../');
        const extensionTestsPath = path.resolve(__dirname, './suite/index');
        const vscodeCachePath = resolveVSCodeTestCachePath(extensionDevelopmentPath);
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
        writeVSCodeTestSettings(userDataDir);

        const vscodeExecutablePath = await downloadAndUnzipVSCode({
            version: vscodeTestVersion,
            cachePath: vscodeCachePath,
            extensionDevelopmentPath
        });
        await removeMacQuarantineFromVSCode(vscodeExecutablePath);

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
                ...createVSCodeTestLaunchArgs(testWorkspace, userDataDir, extensionsDir),
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
