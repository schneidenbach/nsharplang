import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';

export function getNlcPath(): string {
    const configuredPath = vscode.workspace.getConfiguration('nsharp').get<string>('cli.path')?.trim();
    if (configuredPath) {
        return expandHome(configuredPath);
    }

    const dotnetToolPath = path.join(os.homedir(), '.dotnet', 'tools', process.platform === 'win32' ? 'nlc.exe' : 'nlc');
    return fs.existsSync(dotnetToolPath) ? dotnetToolPath : 'nlc';
}

export function getNlcEnvironment(): Record<string, string> {
    const env = copyProcessEnvironment();

    const dotnetRoot = resolveDotnetRoot(env);
    if (dotnetRoot) {
        env.DOTNET_ROOT = dotnetRoot;

        const archSpecificVariable = getDotnetRootArchitectureVariable();
        if (archSpecificVariable) {
            env[archSpecificVariable] = dotnetRoot;
        }

        prependPath(env, dotnetRoot);
    }

    const dotnetToolsDirectory = path.join(os.homedir(), '.dotnet', 'tools');
    prependPath(env, dotnetToolsDirectory);

    return env;
}

export function resolveDotnetRoot(env: Record<string, string | undefined> = process.env): string | undefined {
    const archSpecificVariable = getDotnetRootArchitectureVariable();
    const configuredRoots = [
        archSpecificVariable ? env[archSpecificVariable] : undefined,
        env.DOTNET_ROOT
    ];

    for (const configuredRoot of configuredRoots) {
        const root = normalizeDotnetRoot(configuredRoot);
        if (root) {
            return root;
        }
    }

    const dotnetFromPath = findExecutableOnPath(process.platform === 'win32' ? 'dotnet.exe' : 'dotnet', env.PATH);
    const rootFromExecutable = dotnetFromPath ? resolveDotnetRootFromExecutable(dotnetFromPath) : undefined;
    if (rootFromExecutable) {
        return rootFromExecutable;
    }

    for (const candidate of getCommonDotnetRoots()) {
        const root = normalizeDotnetRoot(candidate);
        if (root) {
            return root;
        }
    }

    return undefined;
}

export function findContainingProjectRoot(startPath: string, workspaceRoot: string): string | undefined {
    let current = path.resolve(startPath);
    const root = path.resolve(workspaceRoot);

    while (current.startsWith(root)) {
        if (fs.existsSync(path.join(current, 'project.yml'))) {
            return current;
        }

        const parent = path.dirname(current);
        if (parent === current) {
            break;
        }
        current = parent;
    }

    return undefined;
}

export function expandHome(value: string): string {
    if (value === '~') {
        return os.homedir();
    }

    return value.startsWith(`~${path.sep}`)
        ? path.join(os.homedir(), value.slice(2))
        : value;
}

function copyProcessEnvironment(): Record<string, string> {
    const env: Record<string, string> = {};
    for (const [key, value] of Object.entries(process.env)) {
        if (typeof value === 'string') {
            env[key] = value;
        }
    }

    return env;
}

function getDotnetRootArchitectureVariable(): string | undefined {
    switch (process.arch) {
        case 'arm64':
            return 'DOTNET_ROOT_ARM64';
        case 'x64':
            return 'DOTNET_ROOT_X64';
        case 'ia32':
            return 'DOTNET_ROOT_X86';
        default:
            return undefined;
    }
}

function findExecutableOnPath(command: string, pathValue: string | undefined): string | undefined {
    if (!pathValue) {
        return undefined;
    }

    for (const directory of pathValue.split(path.delimiter)) {
        if (!directory) {
            continue;
        }

        const candidate = path.join(directory, command);
        if (fs.existsSync(candidate)) {
            return candidate;
        }
    }

    return undefined;
}

function resolveDotnetRootFromExecutable(dotnetPath: string): string | undefined {
    const realDotnetPath = realpathOrOriginal(dotnetPath);
    const dotnetDirectory = path.dirname(realDotnetPath);
    const parentDirectory = path.dirname(dotnetDirectory);

    const candidates = [
        dotnetDirectory,
        path.join(parentDirectory, 'libexec'),
        parentDirectory
    ];

    for (const candidate of candidates) {
        const root = normalizeDotnetRoot(candidate);
        if (root) {
            return root;
        }
    }

    return undefined;
}

function getCommonDotnetRoots(): string[] {
    if (process.platform === 'win32') {
        return [
            path.join(process.env.ProgramFiles || 'C:\\Program Files', 'dotnet'),
            path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'dotnet')
        ];
    }

    const roots = [
        path.join(os.homedir(), '.dotnet'),
        '/usr/local/share/dotnet',
        '/opt/homebrew/opt/dotnet/libexec',
        '/usr/local/opt/dotnet/libexec'
    ];

    return roots;
}

function normalizeDotnetRoot(candidate: string | undefined): string | undefined {
    if (!candidate || !fs.existsSync(candidate)) {
        return undefined;
    }

    const root = realpathOrOriginal(candidate);
    return isDotnetRoot(root) ? root : undefined;
}

function isDotnetRoot(candidate: string): boolean {
    return fs.existsSync(path.join(candidate, process.platform === 'win32' ? 'dotnet.exe' : 'dotnet'))
        && fs.existsSync(path.join(candidate, 'shared'));
}

function prependPath(env: Record<string, string>, directory: string): void {
    if (!fs.existsSync(directory)) {
        return;
    }

    const currentPath = env.PATH || '';
    const entries = currentPath.split(path.delimiter).filter(Boolean);
    if (!entries.includes(directory)) {
        env.PATH = [directory, ...entries].join(path.delimiter);
    }
}

function realpathOrOriginal(value: string): string {
    try {
        return fs.realpathSync(value);
    } catch {
        return value;
    }
}
