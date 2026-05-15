import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { runTests } from '@vscode/test-electron';

async function main(): Promise<void> {
    const extensionDevelopmentPath = path.resolve(__dirname, '../../..');
    const repoRoot = path.resolve(extensionDevelopmentPath, '../..');
    const reportPath = process.env.NSHARP_VSCODE_REPORT_PATH
        ?? path.join(repoRoot, '.context', 'vscode-headless-report.json');
    const serverPath = process.env.NSHARP_VSCODE_SERVER_PATH
        ?? path.join(repoRoot, 'src', 'NSharpLang.LanguageServer', 'bin', 'Release', 'net10.0', 'LanguageServer.dll');

    if (!fs.existsSync(serverPath)) {
        throw new Error(`Language server binary not found: ${serverPath}`);
    }

    const workspaceRoot = createFixtureWorkspace(serverPath);
    const extensionTestsPath = path.resolve(__dirname, 'suite', 'index.js');
    const profileRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'nsharp-vscode-profile-'));
    const userDataDir = path.join(profileRoot, 'user-data');
    const extensionsDir = path.join(profileRoot, 'extensions');

    fs.mkdirSync(userDataDir, { recursive: true });
    fs.mkdirSync(extensionsDir, { recursive: true });

    process.env.NSHARP_VSCODE_FIXTURE_ROOT = workspaceRoot;
    process.env.NSHARP_VSCODE_REPORT_PATH = reportPath;
    process.env.NSHARP_VSCODE_SERVER_PATH = serverPath;

    try {
        await runTests({
            extensionDevelopmentPath,
            extensionTestsPath,
            extensionTestsEnv: {
                NSHARP_VSCODE_FIXTURE_ROOT: workspaceRoot,
                NSHARP_VSCODE_REPORT_PATH: reportPath,
                NSHARP_VSCODE_SERVER_PATH: serverPath
            },
            reuseMachineInstall: true,
            launchArgs: [
                workspaceRoot,
                '--disable-workspace-trust',
                '--skip-welcome',
                '--skip-release-notes',
                '--disable-gpu',
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
                `--extensions-dir=${extensionsDir}`
            ]
        });
    } finally {
        fs.rmSync(profileRoot, { recursive: true, force: true });
        fs.rmSync(workspaceRoot, { recursive: true, force: true });
    }
}

function createFixtureWorkspace(serverPath: string): string {
    const workspaceRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'nsharp-vscode-headless-'));
    const vscodeDir = path.join(workspaceRoot, '.vscode');

    fs.mkdirSync(vscodeDir, { recursive: true });

    fs.writeFileSync(path.join(vscodeDir, 'settings.json'), JSON.stringify({
        'nsharp.languageServer.path': serverPath,
        'nsharp.trace.server': 'off',
        'editor.inlineSuggest.enabled': false
    }, null, 2));

    fs.writeFileSync(path.join(workspaceRoot, 'project.yml'), [
        'name: HeadlessSmoke',
        'version: 1.0.0',
        'targetFramework: net10.0',
        'outputType: exe',
        'entry: Program.nl',
        ''
    ].join('\n'));

    fs.writeFileSync(path.join(workspaceRoot, 'HeadlessSmoke.csproj'), '<Project Sdk="NSharpLang.Sdk" />\n');

    fs.writeFileSync(path.join(workspaceRoot, 'Helpers.nl'), [
        'func greet(name: string): string {',
        '    return name.ToUpper()',
        '}',
        ''
    ].join('\n'));

    fs.writeFileSync(path.join(workspaceRoot, 'Program.nl'), [
        'import System',
        '',
        'func Main() {',
        '    name := "Spencer"',
        '    result := greet(name)',
        '    upper := name.ToUpper()',
        '    print result',
        '    print upper',
        '}',
        ''
    ].join('\n'));

    fs.writeFileSync(path.join(workspaceRoot, 'Completion.nl'), [
        'import System',
        '',
        'func Main() {',
        '    name := "Spencer"',
        '    name.',
        '}',
        ''
    ].join('\n'));

    fs.writeFileSync(path.join(workspaceRoot, 'Broken.nl'), [
        'func Broken() -> int {',
        '    return "oops"',
        '}',
        ''
    ].join('\n'));

    fs.writeFileSync(path.join(workspaceRoot, 'AutoImport.nl'), [
        'func Main() {',
        '    list := new List<int>()',
        '    print list',
        '}',
        ''
    ].join('\n'));

    return workspaceRoot;
}

main().catch(error => {
    console.error('Headless VS Code test harness failed.');
    console.error(error);
    process.exit(1);
});
