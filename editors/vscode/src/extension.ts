import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import { execSync } from 'child_process';
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
                    'LanguageServer',
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

    // Register formatter
    context.subscriptions.push(
        vscode.languages.registerDocumentFormattingEditProvider('nsharp', {
            provideDocumentFormattingEdits(document: vscode.TextDocument): vscode.TextEdit[] {
                try {
                    const formatted = formatDocument(document);
                    const fullRange = new vscode.Range(
                        document.positionAt(0),
                        document.positionAt(document.getText().length)
                    );
                    return [vscode.TextEdit.replace(fullRange, formatted)];
                } catch (error) {
                    vscode.window.showErrorMessage(`N# Format failed: ${error}`);
                    return [];
                }
            }
        })
    );

    // Start the client (this will also launch the server)
    client.start();

    console.log('N# Language Server started');
}

function formatDocument(document: vscode.TextDocument): string {
    // Create a temp file with the document content
    const tempFile = path.join(os.tmpdir(), `nsharp-format-${Date.now()}.nl`);

    try {
        // Write document content to temp file
        fs.writeFileSync(tempFile, document.getText(), 'utf-8');

        // Run nsharp format on the temp file
        // The format command formats in-place
        execSync(`nsharp format "${tempFile}"`, {
            encoding: 'utf-8',
            stdio: ['pipe', 'pipe', 'pipe']
        });

        // Read the formatted content
        const formatted = fs.readFileSync(tempFile, 'utf-8');
        return formatted;
    } catch (error) {
        throw new Error(`Failed to format document: ${error}`);
    } finally {
        // Clean up temp file
        try {
            if (fs.existsSync(tempFile)) {
                fs.unlinkSync(tempFile);
            }
        } catch {
            // Ignore cleanup errors
        }
    }
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}
