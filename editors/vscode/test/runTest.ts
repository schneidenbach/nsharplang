import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import { runTests } from '@vscode/test-electron';

async function main() {
    try {
        const extensionDevelopmentPath = path.resolve(__dirname, '../../');
        const extensionTestsPath = path.resolve(__dirname, './suite/index');
        const vscodeExecutablePath = resolveMachineVSCodeExecutable();
        const vscodeCachePath = process.env.NSHARP_VSCODE_CACHE_PATH
            ?? path.join(resolveCacheRoot(), 'NSharpLang', 'vscode-test');

        // Default to the simple fixture workspace
        const testWorkspace = process.env.TEST_WORKSPACE
            || path.resolve(__dirname, '../../test/fixtures/simple');

        // Use short temp directories for user data to avoid IPC socket path length issues
        // (macOS limits Unix domain sockets to 104 chars) and isolate installed user extensions.
        // Do not pass --disable-extensions: VS Code 1.120 can leave the extension-test host
        // waiting forever before the test entrypoint runs when that global switch is present.
        const profileRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'ns-test-'));
        const userDataDir = path.join(profileRoot, 'user-data');
        const extensionsDir = path.join(profileRoot, 'extensions');
        fs.mkdirSync(userDataDir, { recursive: true });
        fs.mkdirSync(extensionsDir, { recursive: true });

        console.log('=== N# VS Code Integration Tests ===');
        console.log(`Extension: ${extensionDevelopmentPath}`);
        console.log(`Tests:     ${extensionTestsPath}`);
        console.log(`Workspace: ${testWorkspace}`);
        console.log(`UserData:  ${userDataDir}`);

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

        await runTests({
            extensionDevelopmentPath,
            extensionTestsPath,
            extensionTestsEnv,
            ...(vscodeExecutablePath ? { vscodeExecutablePath } : { cachePath: vscodeCachePath }),
            reuseMachineInstall: true,
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
                `--user-data-dir=${userDataDir}`,
                `--extensions-dir=${extensionsDir}`,
            ],
        });

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

function resolveMachineVSCodeExecutable(): string | undefined {
    const explicit = process.env.NSHARP_VSCODE_EXECUTABLE_PATH;
    if (explicit && fs.existsSync(explicit)) {
        return explicit;
    }

    if (process.platform === 'darwin') {
        for (const candidate of [
            '/Applications/Visual Studio Code.app/Contents/MacOS/Code',
            '/Applications/Visual Studio Code.app/Contents/MacOS/Electron'
        ]) {
            if (fs.existsSync(candidate)) {
                return candidate;
            }
        }
    }

    return undefined;
}

function resolveCacheRoot(): string {
    if (process.env.XDG_CACHE_HOME) {
        return process.env.XDG_CACHE_HOME;
    }
    if (process.platform === 'darwin') {
        return path.join(os.homedir(), 'Library', 'Caches');
    }
    if (process.platform === 'win32' && process.env.LOCALAPPDATA) {
        return process.env.LOCALAPPDATA;
    }
    return path.join(os.homedir(), '.cache');
}

main();
