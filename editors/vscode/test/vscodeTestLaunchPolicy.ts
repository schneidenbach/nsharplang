import * as childProcess from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

const versionFilePath = path.resolve(__dirname, '../../test/vscode-test-version');

export const vscodeTestVersion = fs.readFileSync(versionFilePath, 'utf8').trim();

if (!/^\d+\.\d+\.\d+$/.test(vscodeTestVersion)) {
    throw new Error(`Invalid pinned VS Code test version in ${versionFilePath}: ${vscodeTestVersion}`);
}

export const vscodeTestSettings = {
    'update.mode': 'none',
    'update.showReleaseNotes': false,
    'extensions.autoUpdate': 'off',
    'extensions.autoCheckUpdates': false,
    'telemetry.telemetryLevel': 'off',
    'security.workspace.trust.enabled': false,
    'workbench.startupEditor': 'none'
} as const;

export function resolveVSCodeTestCachePath(extensionDevelopmentPath: string): string {
    return process.env.NSHARP_VSCODE_TEST_CACHE?.trim()
        || process.env.NSHARP_VSCODE_CACHE_PATH?.trim()
        || path.join(extensionDevelopmentPath, '.vscode-test');
}

export function createVSCodeTestLaunchArgs(
    workspaceRoot: string,
    userDataDir: string,
    extensionsDir: string,
    platform: NodeJS.Platform = process.platform
): string[] {
    const launchArgs = [
        workspaceRoot,
        '--disable-updates',
        '--disable-telemetry',
        '--skip-welcome',
        '--skip-release-notes',
        '--disable-workspace-trust',
        '--disable-experiments',
        '--use-inmemory-secretstorage',
        '--disable-gpu'
    ];

    if (platform === 'darwin') {
        launchArgs.push('--use-mock-keychain');
    } else if (platform === 'linux') {
        launchArgs.push('--password-store=basic');
    }

    launchArgs.push(
        `--user-data-dir=${userDataDir}`,
        `--extensions-dir=${extensionsDir}`
    );

    return launchArgs;
}

export function writeVSCodeTestSettings(userDataDir: string): string {
    const settingsPath = path.join(userDataDir, 'User', 'settings.json');
    fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
    fs.writeFileSync(settingsPath, `${JSON.stringify(vscodeTestSettings, null, 2)}\n`, 'utf8');
    return settingsPath;
}

export async function removeMacQuarantineFromVSCode(vscodeExecutablePath: string): Promise<void> {
    if (process.platform !== 'darwin') {
        return;
    }

    const appBundleMatch = vscodeExecutablePath.match(/^(.*?\.app)(?:\/|$)/);
    if (!appBundleMatch) {
        throw new Error(`Downloaded VS Code executable is not inside an app bundle: ${vscodeExecutablePath}`);
    }

    const appBundlePath = appBundleMatch[1];
    if (await hasExtendedAttribute(appBundlePath, 'com.apple.quarantine')) {
        childProcess.execFileSync('xattr', ['-dr', 'com.apple.quarantine', appBundlePath], { stdio: 'ignore' });
    }
}

function hasExtendedAttribute(targetPath: string, attributeName: string): Promise<boolean> {
    return new Promise((resolve, reject) => {
        const child = childProcess.spawn('xattr', ['-lr', targetPath]);
        let found = false;
        let previousTail = '';
        let errorOutput = '';

        child.stdout?.on('data', chunk => {
            const output = previousTail + chunk.toString();
            if (output.includes(attributeName)) {
                found = true;
            }
            previousTail = output.slice(-attributeName.length);
        });

        child.stderr?.on('data', chunk => {
            errorOutput = (errorOutput + chunk.toString()).slice(-2000);
        });

        child.once('error', reject);
        child.once('close', code => {
            if (code === 0) {
                resolve(found);
            } else {
                reject(new Error(`Could not inspect macOS extended attributes for ${targetPath}: ${errorOutput}`));
            }
        });
    });
}
