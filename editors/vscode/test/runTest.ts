import * as fs from 'fs';
import * as path from 'path';
import { runTests } from '@vscode/test-electron';
import {
    createIsolatedVscodeProfile,
    createVscodeLaunchArgs,
    downloadPinnedVscode
} from './launchPolicy';

async function main(): Promise<void> {
    let profileRoot: string | undefined;
    try {
        const extensionSourcePath = path.resolve(__dirname, '../../');
        const extensionTestsPath = path.resolve(__dirname, './suite/index');
        const vscodeCachePath = process.env.NSHARP_VSCODE_TEST_CACHE?.trim()
            || process.env.NSHARP_VSCODE_CACHE_PATH?.trim()
            || path.join(extensionSourcePath, '.vscode-test');
        const profile = createIsolatedVscodeProfile('ns-test-');
        profileRoot = profile.root;

        const testWorkspace = process.env.TEST_WORKSPACE
            || path.resolve(__dirname, '../../test/fixtures/simple');
        const { executablePath: vscodeExecutablePath, version: vscodeTestVersion } =
            await downloadPinnedVscode(extensionSourcePath, vscodeCachePath);

        console.log('=== N# VS Code Integration Tests ===');
        console.log(`Extension: ${extensionSourcePath}`);
        console.log(`Tests:     ${extensionTestsPath}`);
        console.log(`Workspace: ${testWorkspace}`);
        console.log(`UserData:  ${profile.userDataDir}`);
        console.log(`VS Code:   ${vscodeTestVersion}`);
        console.log(`Cache:     ${vscodeCachePath}`);

        const extensionTestsEnv: Record<string, string> = {};
        for (const name of ['TEST_SUITE', 'TEST_GREP']) {
            const value = process.env[name];
            if (value) {
                extensionTestsEnv[name] = value;
                console.log(`Filter:    ${name}=${value}`);
            }
        }

        await runTests({
            extensionDevelopmentPath: extensionSourcePath,
            extensionTestsPath,
            extensionTestsEnv,
            vscodeExecutablePath,
            launchArgs: createVscodeLaunchArgs(testWorkspace, profile)
        });
    } catch (err) {
        console.error('Failed to run tests:', err);
        process.exitCode = 1;
    } finally {
        if (profileRoot) fs.rmSync(profileRoot, { recursive: true, force: true });
    }
}

void main();
