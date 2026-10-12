import * as fs from 'fs';
import * as path from 'path';
import { runTests } from '@vscode/test-electron';
import {
    createIsolatedVscodeProfile,
    createVscodeLaunchArgs,
    downloadPinnedVscode
} from '../launchPolicy';

async function main(): Promise<void> {
    const scenario = requiredEnv('NSHARP_VSCODE_VISUAL_SCENARIO');
    const workspacePath = requiredEnv('NSHARP_VSCODE_VISUAL_WORKSPACE');
    const packagedExtensionPath = requiredEnv('NSHARP_VSCODE_VISUAL_EXTENSION_PATH');
    const reportPath = requiredEnv('NSHARP_VSCODE_VISUAL_REPORT_PATH');
    const sentinelPath = requiredEnv('NSHARP_VSCODE_VISUAL_SENTINEL');
    const holdSeconds = requiredEnv('NSHARP_VSCODE_VISUAL_HOLD_SECONDS');
    const extensionSourcePath = path.resolve(__dirname, '../../..');
    const extensionTestsPath = path.resolve(__dirname, 'extensionTestEntry');
    const vscodeCachePath = process.env.NSHARP_VSCODE_TEST_CACHE?.trim()
        || process.env.NSHARP_VSCODE_CACHE_PATH?.trim()
        || path.join(extensionSourcePath, '.vscode-test');
    const windowTitle = 'N# Visual Scenario: ' + scenario + ' — ${appName}';
    const profile = createIsolatedVscodeProfile('nsv-', undefined, windowTitle);

    try {
        if (!fs.existsSync(path.join(packagedExtensionPath, 'package.json'))) {
            throw new Error(`Packaged VSIX extension folder is missing package.json: ${packagedExtensionPath}`);
        }
        const { executablePath: vscodeExecutablePath, version } =
            await downloadPinnedVscode(extensionSourcePath, vscodeCachePath);

        console.log(`N# VS Code visual scenario: ${scenario}`);
        console.log(`Workspace copy: ${workspacePath}`);
        console.log(`Packaged extension: ${packagedExtensionPath}`);
        console.log(`Pinned VS Code: ${version}`);
        console.log(`Isolated user data: ${profile.userDataDir}`);
        console.log(`Report: ${reportPath}`);
        console.log(`Sentinel: ${sentinelPath}`);
        console.log(`Window title: [Extension Development Host] N# Visual Scenario: ${scenario} — Visual Studio Code`);

        await runTests({
            extensionDevelopmentPath: packagedExtensionPath,
            extensionTestsPath,
            extensionTestsEnv: {
                NSHARP_VSCODE_VISUAL_SCENARIO: scenario,
                NSHARP_VSCODE_VISUAL_REPORT_PATH: reportPath,
                NSHARP_VSCODE_VISUAL_SENTINEL: sentinelPath,
                NSHARP_VSCODE_VISUAL_HOLD_SECONDS: holdSeconds,
                NSHARP_VSCODE_VISUAL_USER_DATA_DIR: profile.userDataDir
            },
            vscodeExecutablePath,
            launchArgs: createVscodeLaunchArgs(workspacePath, profile)
        });
    } catch (error) {
        console.error('N# VS Code visual scenario runner failed.');
        console.error(error);
        process.exitCode = 1;
    } finally {
        fs.rmSync(profile.root, { recursive: true, force: true });
    }
}

function requiredEnv(name: string): string {
    const value = process.env[name];
    if (!value) throw new Error(`Missing environment variable ${name}`);
    return value;
}

void main();
