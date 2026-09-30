import * as path from 'path';
import * as fs from 'fs';
import * as vscode from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
    TransportKind
} from 'vscode-languageclient/node';
import { createTestController } from './testController';
import { expandHome, findContainingProjectRoot, getNlcEnvironment, getNlcPath } from './toolchain';

let client: LanguageClient;

type NlcTaskName = 'build' | 'run' | 'test';

type NSharpProjectInfo = {
    projectRoot: string;
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

function createNlcTasks(workspaceFolder: vscode.WorkspaceFolder): vscode.Task[] {
    return [
        createNlcTask(workspaceFolder, 'build', ['build'], vscode.TaskGroup.Build),
        createNlcTask(workspaceFolder, 'run', ['run']),
        createNlcTask(workspaceFolder, 'test', ['test'], vscode.TaskGroup.Test)
    ];
}

function isNlcTaskName(taskName: string): taskName is NlcTaskName {
    return taskName === 'build' || taskName === 'run' || taskName === 'test';
}

function getActiveWorkspaceFolder(): vscode.WorkspaceFolder | undefined {
    const activeDocument = vscode.window.activeTextEditor?.document;
    if (activeDocument?.uri.scheme === 'file') {
        return vscode.workspace.getWorkspaceFolder(activeDocument.uri);
    }

    return vscode.workspace.workspaceFolders?.[0];
}

function getNSharpProjectInfo(workspaceFolder: vscode.WorkspaceFolder): NSharpProjectInfo {
    const projectRoot = resolveProjectRoot(workspaceFolder);
    const projectYmlPath = path.join(projectRoot, 'project.yml');
    if (!fs.existsSync(projectYmlPath)) {
        throw new Error(`No project.yml found in ${projectRoot}. Open an N# project folder before running the project.`);
    }

    const projectConfig = readTopLevelProjectConfig(projectYmlPath, projectRoot);
    if (projectConfig.outputType.toLowerCase() === 'library') {
        throw new Error(`Project '${projectConfig.name}' is a library. Choose an executable N# project to run.`);
    }

    return {
        projectRoot
    };
}

function resolveProjectRoot(workspaceFolder: vscode.WorkspaceFolder): string {
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

function readTopLevelProjectConfig(projectYmlPath: string, projectRoot: string): {
    name: string;
    outputType: string;
} {
    const defaults = {
        name: path.basename(projectRoot) || 'Project',
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

async function runNSharpTask(workspaceFolder: vscode.WorkspaceFolder): Promise<void> {
    const projectInfo = getNSharpProjectInfo(workspaceFolder);
    await vscode.tasks.executeTask(createNlcTask(workspaceFolder, 'run', ['run'], undefined, projectInfo.projectRoot));
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
