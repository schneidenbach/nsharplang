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

let client: LanguageClient;

function getNlcPath(): string {
    return vscode.workspace.getConfiguration('nsharp').get<string>('cli.path') || 'nlc';
}

function createNlcTask(
    workspaceFolder: vscode.WorkspaceFolder,
    label: string,
    args: string[],
    group?: vscode.TaskGroup
): vscode.Task {
    const task = new vscode.Task(
        { type: 'nsharp', task: label },
        workspaceFolder,
        label,
        'nsharp',
        new vscode.ShellExecution(getNlcPath(), args, {
            cwd: workspaceFolder.uri.fsPath
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

function isNlcTaskName(taskName: string): taskName is 'build' | 'run' | 'test' {
    return taskName === 'build' || taskName === 'run' || taskName === 'test';
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

    // Define the server options
    const serverOptions: ServerOptions = {
        run: {
            command: 'dotnet',
            args: [serverPath],
            transport: TransportKind.stdio
        },
        debug: {
            command: 'dotnet',
            args: [serverPath],
            transport: TransportKind.stdio,
            options: {
                env: {
                    ...process.env,
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
