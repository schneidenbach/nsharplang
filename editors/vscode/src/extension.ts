import * as path from 'path';
import * as fs from 'fs';
import * as vscode from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
    TransportKind
} from 'vscode-languageclient/node';

let client: LanguageClient;

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
                    'net9.0',
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

    // Register debug configuration command
    context.subscriptions.push(
        vscode.commands.registerCommand('nsharp.generateDebugConfig', async () => {
            await generateDebugConfig();
        })
    );

    // Register zero-config debug configuration provider for F5
    context.subscriptions.push(
        vscode.debug.registerDebugConfigurationProvider('coreclr', {
            provideDebugConfigurations(
                _folder: vscode.WorkspaceFolder | undefined
            ): vscode.ProviderResult<vscode.DebugConfiguration[]> {
                return [];
            },
            resolveDebugConfiguration(
                folder: vscode.WorkspaceFolder | undefined,
                config: vscode.DebugConfiguration,
                _token?: vscode.CancellationToken
            ): vscode.ProviderResult<vscode.DebugConfiguration> {
                // Only intervene when there's no launch.json (config will be nearly empty)
                if (config.request) {
                    return config;
                }

                // Only trigger for active .nl files
                const activeEditor = vscode.window.activeTextEditor;
                if (!activeEditor || activeEditor.document.languageId !== 'nsharp') {
                    return config;
                }

                if (!folder) {
                    return config;
                }

                const workspacePath = folder.uri.fsPath;
                const projectYmlPath = path.join(workspacePath, 'project.yml');

                let projectName = path.basename(workspacePath);
                let targetFramework = 'net9.0';
                let outputType = 'exe';

                if (fs.existsSync(projectYmlPath)) {
                    try {
                        const projectYml = fs.readFileSync(projectYmlPath, 'utf-8');
                        const nameMatch = projectYml.match(/^name:\s*(.+)$/m);
                        const frameworkMatch = projectYml.match(/^targetFramework:\s*(.+)$/m);
                        const outputTypeMatch = projectYml.match(/^outputType:\s*(.+)$/m);

                        if (nameMatch) projectName = nameMatch[1].trim();
                        if (frameworkMatch) targetFramework = frameworkMatch[1].trim();
                        if (outputTypeMatch) outputType = outputTypeMatch[1].trim();
                    } catch (error) {
                        console.error('Failed to parse project.yml:', error);
                    }
                }

                // Don't launch libraries
                if (outputType.toLowerCase() === 'library') {
                    return undefined;
                }

                return {
                    name: 'Launch N#',
                    type: 'coreclr',
                    request: 'launch',
                    preLaunchTask: 'build',
                    program: path.join(workspacePath, 'bin', 'Debug', targetFramework, `${projectName}.dll`),
                    args: [],
                    cwd: workspacePath,
                    console: 'internalConsole',
                    stopAtEntry: false
                };
            }
        })
    );

    // Register task provider for nsharp build task
    context.subscriptions.push(
        vscode.tasks.registerTaskProvider('nsharp', {
            provideTasks(): vscode.Task[] {
                const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
                if (!workspaceFolder) {
                    return [];
                }

                const buildTask = new vscode.Task(
                    { type: 'nsharp' },
                    workspaceFolder,
                    'build',
                    'nsharp',
                    new vscode.ShellExecution('dotnet', ['build']),
                    '$msCompile'
                );
                buildTask.group = vscode.TaskGroup.Build;

                return [buildTask];
            },
            resolveTask(_task: vscode.Task): vscode.Task | undefined {
                return undefined;
            }
        })
    );

    // Check for C# extension dependency (needed for F5 debugging only).
    // Skip the check when running in extension development/test mode since
    // --disable-extensions prevents other extensions from loading.
    if (context.extensionMode === vscode.ExtensionMode.Production) {
        const csharpExtension = vscode.extensions.getExtension('ms-dotnettools.csharp');
        if (!csharpExtension) {
            vscode.window.showWarningMessage(
                'The C# extension (ms-dotnettools.csharp) is not installed. N# debugging requires it for CoreCLR support.',
                'Install'
            ).then(selection => {
                if (selection === 'Install') {
                    vscode.commands.executeCommand(
                        'workbench.extensions.installExtension',
                        'ms-dotnettools.csharp'
                    );
                }
            });
        }
    }

    // Start the client (this will also launch the server)
    client.start();

    console.log('N# Language Server started');
}

async function generateDebugConfig() {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    if (!workspaceFolder) {
        vscode.window.showErrorMessage('No workspace folder open');
        return;
    }

    const workspacePath = workspaceFolder.uri.fsPath;
    const vscodePath = path.join(workspacePath, '.vscode');

    // Create .vscode directory if it doesn't exist
    if (!fs.existsSync(vscodePath)) {
        fs.mkdirSync(vscodePath, { recursive: true });
    }

    // Read project.yml to get project name and target framework
    const projectYmlPath = path.join(workspacePath, 'project.yml');
    let projectName = path.basename(workspacePath);
    let targetFramework = 'net9.0';
    let outputType = 'exe';

    if (fs.existsSync(projectYmlPath)) {
        try {
            const projectYml = fs.readFileSync(projectYmlPath, 'utf-8');
            const nameMatch = projectYml.match(/^name:\s*(.+)$/m);
            const frameworkMatch = projectYml.match(/^targetFramework:\s*(.+)$/m);
            const outputTypeMatch = projectYml.match(/^outputType:\s*(.+)$/m);

            if (nameMatch) projectName = nameMatch[1].trim();
            if (frameworkMatch) targetFramework = frameworkMatch[1].trim();
            if (outputTypeMatch) outputType = outputTypeMatch[1].trim();
        } catch (error) {
            console.error('Failed to parse project.yml:', error);
        }
    }

    // Generate launch.json
    const launchJsonPath = path.join(vscodePath, 'launch.json');
    const launchJson = generateLaunchJson(projectName, targetFramework, outputType);

    // Check if launch.json already exists
    if (fs.existsSync(launchJsonPath)) {
        const overwrite = await vscode.window.showWarningMessage(
            'launch.json already exists. Overwrite?',
            'Yes',
            'No'
        );
        if (overwrite !== 'Yes') {
            return;
        }
    }

    fs.writeFileSync(launchJsonPath, launchJson, 'utf-8');

    // Generate tasks.json
    const tasksJsonPath = path.join(vscodePath, 'tasks.json');
    const tasksJson = generateTasksJson();

    // Check if tasks.json already exists
    if (fs.existsSync(tasksJsonPath)) {
        const overwrite = await vscode.window.showWarningMessage(
            'tasks.json already exists. Overwrite?',
            'Yes',
            'No'
        );
        if (overwrite !== 'Yes') {
            vscode.window.showInformationMessage('Debug configuration created: launch.json');
            return;
        }
    }

    fs.writeFileSync(tasksJsonPath, tasksJson, 'utf-8');

    vscode.window.showInformationMessage('Debug configuration created successfully!');
}

function generateLaunchJson(projectName: string, targetFramework: string, outputType: string): string {
    const config = {
        version: '0.2.0',
        configurations: [
            {
                name: 'Launch N#',
                type: 'coreclr',
                request: 'launch',
                preLaunchTask: 'build',
                program: `\${workspaceFolder}/bin/Debug/${targetFramework}/${projectName}.dll`,
                args: [],
                cwd: '\${workspaceFolder}',
                console: 'internalConsole',
                stopAtEntry: false
            },
            {
                name: 'Attach to Process',
                type: 'coreclr',
                request: 'attach'
            }
        ]
    };

    return JSON.stringify(config, null, 2);
}

function generateTasksJson(): string {
    const config = {
        version: '2.0.0',
        tasks: [
            {
                label: 'build',
                command: 'dotnet',
                type: 'process',
                args: ['build'],
                problemMatcher: '$msCompile',
                group: {
                    kind: 'build',
                    isDefault: true
                }
            },
            {
                label: 'run',
                command: 'dotnet',
                type: 'process',
                args: ['run'],
                problemMatcher: '$msCompile',
                dependsOn: 'build'
            },
            {
                label: 'test',
                command: 'dotnet',
                type: 'process',
                args: ['test'],
                problemMatcher: '$msCompile',
                group: {
                    kind: 'test',
                    isDefault: true
                }
            },
            {
                label: 'format',
                command: 'nlc',
                type: 'process',
                args: ['format'],
                problemMatcher: []
            },
            {
                label: 'lint',
                command: 'nlc',
                type: 'process',
                args: ['lint'],
                problemMatcher: []
            }
        ]
    };

    return JSON.stringify(config, null, 2);
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}
