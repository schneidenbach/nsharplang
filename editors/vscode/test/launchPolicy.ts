import * as childProcess from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { downloadAndUnzipVSCode } from '@vscode/test-electron';

export interface IsolatedVscodeProfile {
    root: string;
    userDataDir: string;
    extensionsDir: string;
}

const disabledBuiltInExtensions = [
    'vscode.git',
    'vscode.github',
    'vscode.github-authentication',
    'GitHub.copilot',
    'GitHub.copilot-chat',
    'github.copilot',
    'github.copilot-chat'
];

export function createIsolatedVscodeProfile(
    prefix: string,
    profileParent = process.env.NSHARP_VSCODE_PROFILE_ROOT?.trim() || os.tmpdir(),
    windowTitle?: string
): IsolatedVscodeProfile {
    fs.mkdirSync(profileParent, { recursive: true });
    const root = fs.mkdtempSync(path.join(profileParent, prefix));
    const userDataDir = path.join(root, 'user-data');
    const extensionsDir = path.join(root, 'extensions');
    fs.mkdirSync(userDataDir, { recursive: true });
    fs.mkdirSync(extensionsDir, { recursive: true });

    const settingsPath = path.join(userDataDir, 'User', 'settings.json');
    fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
    const settings: Record<string, unknown> = {
        'update.mode': 'none',
        'update.showReleaseNotes': false,
        'extensions.autoUpdate': 'off',
        'extensions.autoCheckUpdates': false,
        'telemetry.telemetryLevel': 'off',
        'security.workspace.trust.enabled': false,
        'workbench.startupEditor': 'none'
    };
    if (windowTitle) settings['window.title'] = windowTitle;
    fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));

    return { root, userDataDir, extensionsDir };
}

export async function downloadPinnedVscode(
    extensionSourcePath: string,
    cachePath: string
): Promise<{ executablePath: string; version: string }> {
    const packageJson = require(path.join(extensionSourcePath, 'package.json')) as {
        config: { vscodeTestVersion: string };
    };
    const version = packageJson.config.vscodeTestVersion;
    fs.mkdirSync(cachePath, { recursive: true });

    const executablePath = await downloadAndUnzipVSCode({
        version,
        cachePath,
        extensionDevelopmentPath: extensionSourcePath
    });
    removeMacQuarantine(executablePath);
    return { executablePath, version };
}

export function createVscodeLaunchArgs(
    workspacePath: string,
    profile: IsolatedVscodeProfile
): string[] {
    return [
        workspacePath,
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
        `--user-data-dir=${profile.userDataDir}`,
        `--extensions-dir=${profile.extensionsDir}`,
        ...disabledBuiltInExtensions.flatMap(extension => ['--disable-extension', extension])
    ];
}

function removeMacQuarantine(executablePath: string): void {
    if (process.platform !== 'darwin') return;

    const appBundle = executablePath.match(/^(.*?\.app)(?:\/|$)/)?.[1];
    if (!appBundle) throw new Error(`VS Code executable is outside an app bundle: ${executablePath}`);

    const quarantine = childProcess.spawnSync('xattr', ['-p', 'com.apple.quarantine', appBundle], { stdio: 'ignore' });
    if (quarantine.error || (quarantine.status !== 0 && quarantine.status !== 1)) {
        throw quarantine.error ?? new Error(`Failed to inspect VS Code quarantine attribute (xattr exited ${quarantine.status}).`);
    }

    if (quarantine.status === 0) {
        const removal = childProcess.spawnSync('xattr', ['-dr', 'com.apple.quarantine', appBundle], { stdio: 'ignore' });
        if (removal.error || removal.status !== 0) {
            throw removal.error ?? new Error(`Failed to remove VS Code quarantine attribute (xattr exited ${removal.status}).`);
        }
    }
}
