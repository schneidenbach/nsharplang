import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import { runTests } from '@vscode/test-electron';

async function main() {
    try {
        const extensionDevelopmentPath = path.resolve(__dirname, '../../');
        const extensionTestsPath = path.resolve(__dirname, './suite/index');

        // Default to the simple fixture workspace
        const testWorkspace = process.env.TEST_WORKSPACE
            || path.resolve(__dirname, '../../test/fixtures/simple');

        // Use a short temp directory for user data to avoid IPC socket path length issues
        // (macOS limits Unix domain sockets to 104 chars)
        const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ns-test-'));

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
            launchArgs: [
                testWorkspace,
                '--disable-extensions',
                '--disable-workspace-trust',
                `--user-data-dir=${userDataDir}`,
            ],
        });

        // Clean up user data
        try {
            fs.rmSync(userDataDir, { recursive: true, force: true });
        } catch {
            // Best effort cleanup
        }
    } catch (err) {
        console.error('Failed to run tests:', err);
        process.exit(1);
    }
}

main();
