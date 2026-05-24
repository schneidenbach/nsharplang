import * as path from 'path';
import * as fs from 'fs';
import * as vscode from 'vscode';
import { spawn, ChildProcessWithoutNullStreams } from 'child_process';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
    TransportKind
} from 'vscode-languageclient/node';
import { createTestController } from './testController';
import { expandHome, findContainingProjectRoot, getNlcEnvironment, getNlcPath } from './toolchain';

let client: LanguageClient;

type NlcTaskName = 'build' | 'run' | 'test' | 'debug build';

type NSharpProjectInfo = {
    projectRoot: string;
    projectName: string;
    targetFramework: string;
    outputType: string;
    debugRoot: string;
    exportedProjectDirectory: string;
    exportedProjectFile: string;
    programPath: string;
};

function createNlcTask(
    workspaceFolder: vscode.WorkspaceFolder,
    label: string,
    args: string[],
    group?: vscode.TaskGroup,
    cwd: string = workspaceFolder.uri.fsPath
): vscode.Task {
    const task = new vscode.Task(
        { type: 'nsharp', task: label },
        workspaceFolder,
        label,
        'nsharp',
        new vscode.ShellExecution(getNlcPath(), args, {
            cwd,
            env: getNlcEnvironment()
        }),
        '$msCompile'
    );
    task.group = group;
    return task;
}

function createNSharpDebugBuildTask(
    workspaceFolder: vscode.WorkspaceFolder,
    config?: vscode.DebugConfiguration
): vscode.Task {
    const task = new vscode.Task(
        { type: 'nsharp', task: 'debug build' },
        workspaceFolder,
        'debug build',
        'nsharp',
        new vscode.CustomExecution(async () => {
            const projectInfo = getNSharpProjectInfo(workspaceFolder, config);
            return new NSharpDebugBuildTerminal(projectInfo);
        }),
        '$msCompile'
    );
    task.group = vscode.TaskGroup.Build;
    return task;
}

function createNlcTasks(workspaceFolder: vscode.WorkspaceFolder): vscode.Task[] {
    return [
        createNlcTask(workspaceFolder, 'build', ['build'], vscode.TaskGroup.Build),
        createNlcTask(workspaceFolder, 'run', ['run']),
        createNlcTask(workspaceFolder, 'test', ['test'], vscode.TaskGroup.Test),
        createNSharpDebugBuildTask(workspaceFolder)
    ];
}

function isNlcTaskName(taskName: string): taskName is NlcTaskName {
    return taskName === 'build' || taskName === 'run' || taskName === 'test' || taskName === 'debug build';
}

function getActiveWorkspaceFolder(): vscode.WorkspaceFolder | undefined {
    const activeDocument = vscode.window.activeTextEditor?.document;
    if (activeDocument?.uri.scheme === 'file') {
        return vscode.workspace.getWorkspaceFolder(activeDocument.uri);
    }

    return vscode.workspace.workspaceFolders?.[0];
}

function getNSharpProjectInfo(
    workspaceFolder: vscode.WorkspaceFolder,
    config?: vscode.DebugConfiguration
): NSharpProjectInfo {
    const projectRoot = resolveProjectRoot(workspaceFolder, config);
    const projectYmlPath = path.join(projectRoot, 'project.yml');
    if (!fs.existsSync(projectYmlPath)) {
        throw new Error(`No project.yml found in ${projectRoot}. Open an N# project folder or set "project" in the launch configuration.`);
    }

    const projectConfig = readTopLevelProjectConfig(projectYmlPath, projectRoot);
    if (projectConfig.outputType.toLowerCase() === 'library') {
        throw new Error(`Project '${projectConfig.name}' is a library. Choose an executable N# project to run or debug.`);
    }

    const debugRoot = path.join(projectRoot, '.nsharp', 'debug');
    const exportedProjectDirectory = path.join(debugRoot, sanitizeFileName(projectConfig.name));
    const exportedProjectFile = path.join(exportedProjectDirectory, `${sanitizeFileName(projectConfig.name)}.csproj`);
    const programPath = path.join(
        exportedProjectDirectory,
        'bin',
        'Debug',
        projectConfig.targetFramework,
        `${projectConfig.name}.dll`
    );

    return {
        projectRoot,
        projectName: projectConfig.name,
        targetFramework: projectConfig.targetFramework,
        outputType: projectConfig.outputType,
        debugRoot,
        exportedProjectDirectory,
        exportedProjectFile,
        programPath
    };
}

function resolveProjectRoot(workspaceFolder: vscode.WorkspaceFolder, config?: vscode.DebugConfiguration): string {
    const configuredProject = typeof config?.project === 'string'
        ? expandWorkspaceFolder(config.project, workspaceFolder)
        : undefined;
    if (configuredProject) {
        const configuredPath = path.isAbsolute(configuredProject)
            ? configuredProject
            : path.join(workspaceFolder.uri.fsPath, configuredProject);
        return fs.statSync(configuredPath).isDirectory()
            ? configuredPath
            : path.dirname(configuredPath);
    }

    const activeDocument = vscode.window.activeTextEditor?.document;
    if (activeDocument?.uri.scheme === 'file') {
        const containingRoot = findContainingProjectRoot(
            path.dirname(activeDocument.uri.fsPath),
            workspaceFolder.uri.fsPath
        );
        if (containingRoot) {
            return containingRoot;
        }
    }

    return findContainingProjectRoot(workspaceFolder.uri.fsPath, workspaceFolder.uri.fsPath)
        ?? workspaceFolder.uri.fsPath;
}

function expandWorkspaceFolder(value: string, workspaceFolder: vscode.WorkspaceFolder): string {
    return value.replace(/\$\{workspaceFolder\}/g, workspaceFolder.uri.fsPath);
}

function readTopLevelProjectConfig(projectYmlPath: string, projectRoot: string): {
    name: string;
    targetFramework: string;
    outputType: string;
} {
    const defaults = {
        name: path.basename(projectRoot) || 'Project',
        targetFramework: 'net10.0',
        outputType: 'exe'
    };

    const values: Record<string, string> = {};
    const lines = fs.readFileSync(projectYmlPath, 'utf8').split(/\r?\n/);
    for (const line of lines) {
        if (/^\s/.test(line) || line.trimStart().startsWith('#')) {
            continue;
        }

        const match = /^([A-Za-z][A-Za-z0-9]*):\s*(.*)$/.exec(line);
        if (!match) {
            continue;
        }

        values[match[1]] = cleanYamlScalar(match[2]);
    }

    return {
        name: values.name || defaults.name,
        targetFramework: values.targetFramework || defaults.targetFramework,
        outputType: values.outputType || defaults.outputType
    };
}

function cleanYamlScalar(value: string): string {
    let trimmed = value.trim();
    if (!trimmed.startsWith('"') && !trimmed.startsWith("'")) {
        trimmed = trimmed.replace(/\s+#.*$/, '').trim();
    }

    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
        return trimmed.slice(1, -1);
    }

    return trimmed;
}

function sanitizeFileName(value: string): string {
    return value.replace(/[<>:"/\\|?*\x00-\x1F]/g, '_') || 'Project';
}

function createNSharpDebugConfiguration(folder: vscode.WorkspaceFolder): vscode.DebugConfiguration {
    const projectInfo = getNSharpProjectInfo(folder);
    return {
        type: 'nsharp',
        request: 'launch',
        name: 'Launch N# Project',
        project: projectInfo.projectRoot,
        args: [],
        cwd: projectInfo.projectRoot,
        console: 'integratedTerminal',
        stopAtEntry: false
    };
}

function createCoreClrDebugConfiguration(
    folder: vscode.WorkspaceFolder,
    config: vscode.DebugConfiguration
): vscode.DebugConfiguration {
    const projectInfo = getNSharpProjectInfo(folder, config);
    return {
        type: 'coreclr',
        request: 'launch',
        name: config.name || 'Launch N# Project',
        program: config.program ?? projectInfo.programPath,
        args: Array.isArray(config.args) ? config.args : [],
        cwd: config.cwd ?? projectInfo.projectRoot,
        console: config.console ?? 'integratedTerminal',
        stopAtEntry: config.stopAtEntry ?? false,
        justMyCode: config.justMyCode ?? true,
        sourceFileMap: config.sourceFileMap
    };
}

async function startNSharpDebugging(
    workspaceFolder: vscode.WorkspaceFolder,
    config: vscode.DebugConfiguration = { type: 'nsharp', request: 'launch', name: 'Launch N# Project' }
): Promise<boolean> {
    try {
        const noDebug = Boolean(config.noDebug);

        if (!hasCoreClrDebuggerExtension()) {
            if (noDebug) {
                await runNSharpTask(workspaceFolder);
                return false;
            }

            const install = 'Install C# Extension';
            const run = 'Run Without Debugging';
            const selected = await vscode.window.showErrorMessage(
                'N# debugging uses the Microsoft C# extension CoreCLR debugger. Install it to debug .nl breakpoints in VS Code.',
                install,
                run
            );

            if (selected === install) {
                await vscode.commands.executeCommand('workbench.extensions.installExtension', 'ms-dotnettools.csharp');
            } else if (selected === run) {
                await runNSharpTask(workspaceFolder);
            }

            return false;
        }

        const buildSucceeded = await runNSharpDebugBuildTask(workspaceFolder, config);
        if (!buildSucceeded) {
            vscode.window.showErrorMessage('N# debug build failed. Check the debug build task output for details.');
            return false;
        }

        const coreClrConfig = createCoreClrDebugConfiguration(workspaceFolder, config);
        const started = await vscode.debug.startDebugging(
            workspaceFolder,
            coreClrConfig,
            { noDebug }
        );

        if (!started) {
            vscode.window.showErrorMessage('N# could not start the CoreCLR debug session.');
        }

        return started;
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        vscode.window.showErrorMessage(`N# debug launch failed: ${message}`);
        return false;
    }
}

function hasCoreClrDebuggerExtension(): boolean {
    return Boolean(
        vscode.extensions.getExtension('ms-dotnettools.csharp')
        || vscode.extensions.getExtension('ms-dotnettools.csdevkit')
    );
}

async function runNSharpTask(workspaceFolder: vscode.WorkspaceFolder): Promise<void> {
    const projectInfo = getNSharpProjectInfo(workspaceFolder);
    await vscode.tasks.executeTask(createNlcTask(workspaceFolder, 'run', ['run'], undefined, projectInfo.projectRoot));
}

async function runNSharpDebugBuildTask(
    workspaceFolder: vscode.WorkspaceFolder,
    config?: vscode.DebugConfiguration
): Promise<boolean> {
    const task = createNSharpDebugBuildTask(workspaceFolder, config);
    const execution = await vscode.tasks.executeTask(task);

    return new Promise(resolve => {
        const disposable = vscode.tasks.onDidEndTaskProcess(event => {
            if (event.execution !== execution) {
                return;
            }

            disposable.dispose();
            resolve(event.exitCode === 0);
        });
    });
}

class NSharpDebugConfigurationProvider implements vscode.DebugConfigurationProvider {
    provideDebugConfigurations(folder: vscode.WorkspaceFolder | undefined): vscode.ProviderResult<vscode.DebugConfiguration[]> {
        const workspaceFolder = folder ?? getActiveWorkspaceFolder();
        if (!workspaceFolder) {
            return [];
        }

        return [createNSharpDebugConfiguration(workspaceFolder)];
    }

    async resolveDebugConfiguration(
        folder: vscode.WorkspaceFolder | undefined,
        config: vscode.DebugConfiguration
    ): Promise<vscode.DebugConfiguration | undefined> {
        const workspaceFolder = folder ?? getActiveWorkspaceFolder();
        if (!workspaceFolder) {
            vscode.window.showErrorMessage('Open an N# project folder before starting the debugger.');
            return undefined;
        }

        await startNSharpDebugging(workspaceFolder, config);
        return undefined;
    }
}

class NSharpDebugBuildTerminal implements vscode.Pseudoterminal {
    private readonly writeEmitter = new vscode.EventEmitter<string>();
    private readonly closeEmitter = new vscode.EventEmitter<number>();
    private activeProcess: ChildProcessWithoutNullStreams | undefined;
    private closed = false;

    readonly onDidWrite = this.writeEmitter.event;
    readonly onDidClose = this.closeEmitter.event;

    constructor(private readonly projectInfo: NSharpProjectInfo) {
    }

    open(): void {
        void this.run();
    }

    close(): void {
        this.closed = true;
        this.activeProcess?.kill();
    }

    private async run(): Promise<void> {
        this.write('Preparing N# debug build...\r\n');

        const exportExitCode = await this.runProcess(
            getNlcPath(),
            ['export', 'csharp', '--project', this.projectInfo.projectRoot, '--output', this.projectInfo.debugRoot],
            this.projectInfo.projectRoot
        );

        if (exportExitCode !== 0) {
            this.write(`N# debug export failed with exit code ${exportExitCode}.\r\n`);
            this.closeEmitter.fire(exportExitCode);
            return;
        }

        const buildExitCode = await this.runProcess(
            'dotnet',
            ['build', this.projectInfo.exportedProjectFile],
            this.projectInfo.debugRoot
        );

        if (buildExitCode === 0) {
            this.write(`N# debug assembly ready: ${this.projectInfo.programPath}\r\n`);
        } else {
            this.write(`N# debug build failed with exit code ${buildExitCode}.\r\n`);
        }

        this.closeEmitter.fire(buildExitCode);
    }

    private runProcess(command: string, args: string[], cwd: string): Promise<number> {
        return new Promise(resolve => {
            if (this.closed) {
                resolve(1);
                return;
            }

            this.write(`> ${[command, ...args].map(quoteForDisplay).join(' ')}\r\n`);
            const child = spawn(command, args, {
                cwd,
                env: getNlcEnvironment()
            });
            this.activeProcess = child;

            child.stdout.on('data', data => this.write(data.toString()));
            child.stderr.on('data', data => this.write(data.toString()));
            child.on('error', error => {
                this.write(`${error.message}\r\n`);
                resolve(1);
            });
            child.on('close', code => {
                this.activeProcess = undefined;
                resolve(code ?? 1);
            });
        });
    }

    private write(value: string): void {
        this.writeEmitter.fire(value.replace(/\r?\n/g, '\r\n'));
    }
}

function quoteForDisplay(value: string): string {
    return /\s/.test(value) ? `"${value.replace(/"/g, '\\"')}"` : value;
}


export function activate(context: vscode.ExtensionContext) {
    console.log('N# language extension is now active');

    // Get configuration
    const config = vscode.workspace.getConfiguration('nsharp');
    let serverPath = config.get<string>('languageServer.path');

    // If no custom path, use the bundled server
    if (!serverPath) {
        // Look for the bundled server in the extension directory
        serverPath = path.join(
            context.extensionPath,
            'server',
            'LanguageServer.dll'
        );

        // Check if the bundled server exists
        if (!fs.existsSync(serverPath)) {
            // Fallback: try to find server in workspace (for development)
            const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
            if (workspaceRoot) {
                const devServerPath = path.join(
                    workspaceRoot,
                    'src',
                    'NSharpLang.LanguageServer',
                    'bin',
                    'Debug',
                    'net10.0',
                    'LanguageServer.dll'
                );
                if (fs.existsSync(devServerPath)) {
                    serverPath = devServerPath;
                }
            }
        }
    }

    if (!serverPath || !fs.existsSync(serverPath)) {
        vscode.window.showErrorMessage(
            'N# Language Server not found. Please ensure the extension is properly installed or configure the path in settings.'
        );
        return;
    }

    console.log(`Using N# Language Server at: ${serverPath}`);

    const serverEnvironment = getNlcEnvironment();

    // Define the server options
    const serverOptions: ServerOptions = {
        run: {
            command: 'dotnet',
            args: [serverPath],
            transport: TransportKind.stdio,
            options: {
                env: serverEnvironment
            }
        },
        debug: {
            command: 'dotnet',
            args: [serverPath],
            transport: TransportKind.stdio,
            options: {
                env: {
                    ...serverEnvironment,
                    NSHARP_LSP_DEBUG: '1'
                }
            }
        }
    };

    // Define the client options
    const clientOptions: LanguageClientOptions = {
        documentSelector: [
            { scheme: 'file', language: 'nsharp' }
        ],
        synchronize: {
            // Notify the server about file changes to .nl files in the workspace
            fileEvents: vscode.workspace.createFileSystemWatcher('**/*.nl')
        },
        outputChannelName: 'N# Language Server'
    };

    // Create the language client
    client = new LanguageClient(
        'nsharpLanguageServer',
        'N# Language Server',
        serverOptions,
        clientOptions
    );

    // Display-only CodeLens labels use this command id because LSP Command requires a command string.
    // The command intentionally does nothing; reference lenses use nsharp.showReferences instead.
    context.subscriptions.push(vscode.commands.registerCommand('nsharp.noop', () => undefined));

    context.subscriptions.push(
        vscode.commands.registerCommand('nsharp.runProject', async () => {
            const workspaceFolder = getActiveWorkspaceFolder();
            if (!workspaceFolder) {
                vscode.window.showErrorMessage('Open an N# project folder before running the project.');
                return;
            }

            await runNSharpTask(workspaceFolder);
        })
    );

    context.subscriptions.push(
        vscode.commands.registerCommand('nsharp.debugProject', async () => {
            const workspaceFolder = getActiveWorkspaceFolder();
            if (!workspaceFolder) {
                vscode.window.showErrorMessage('Open an N# project folder before starting the debugger.');
                return;
            }

            await startNSharpDebugging(workspaceFolder, createNSharpDebugConfiguration(workspaceFolder));
        })
    );

    context.subscriptions.push(
        vscode.debug.registerDebugConfigurationProvider('nsharp', new NSharpDebugConfigurationProvider())
    );

    // Bridge CodeLens reference commands from the language server to VS Code's references UI.
    context.subscriptions.push(
        vscode.commands.registerCommand('nsharp.showReferences', async (uriArg: string | vscode.Uri, line: number, character: number) => {
            const uri = typeof uriArg === 'string' ? vscode.Uri.parse(uriArg) : uriArg;
            const position = new vscode.Position(line, character);
            const locations = await vscode.commands.executeCommand<vscode.Location[]>(
                'vscode.executeReferenceProvider',
                uri,
                position
            ) ?? [];

            await vscode.commands.executeCommand(
                'editor.action.showReferences',
                uri,
                position,
                locations
            );
        })
    );

    // Register nlc-backed build/run/test tasks for fresh project.yml templates.
    context.subscriptions.push(
        vscode.tasks.registerTaskProvider('nsharp', {
            provideTasks(): vscode.Task[] {
                const workspaceFolders = vscode.workspace.workspaceFolders ?? [];
                return workspaceFolders.flatMap(workspaceFolder => createNlcTasks(workspaceFolder));
            },
            resolveTask(task: vscode.Task): vscode.Task | undefined {
                const taskName = typeof task.definition.task === 'string' ? task.definition.task : task.name;
                const workspaceFolder = task.scope && typeof task.scope === 'object' && 'uri' in task.scope
                    ? task.scope
                    : vscode.workspace.workspaceFolders?.[0];

                if (!workspaceFolder || !isNlcTaskName(taskName)) {
                    return undefined;
                }

                if (taskName === 'debug build') {
                    return createNSharpDebugBuildTask(workspaceFolder);
                }

                return createNlcTask(
                    workspaceFolder,
                    taskName,
                    [taskName],
                    taskName === 'build' ? vscode.TaskGroup.Build : taskName === 'test' ? vscode.TaskGroup.Test : undefined
                );
            }
        })
    );

    // Start the client (this will also launch the server)
    client.start().then(() => {
        // Register test controller after LSP is ready
        const testDisposable = createTestController(context);
        context.subscriptions.push(testDisposable);
        console.log('N# Test Controller registered');
    });

    console.log('N# Language Server started');
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}
