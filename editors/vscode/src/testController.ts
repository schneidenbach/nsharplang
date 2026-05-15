import * as vscode from 'vscode';
import { NSharpTestRunner } from './testRunner';

/**
 * Creates and manages the N# Test Controller for VS Code's Test Explorer.
 * Discovers tests from .tests.nl files via DocumentSymbol LSP requests
 * and provides a run profile.
 */
export function createTestController(
    context: vscode.ExtensionContext
): vscode.Disposable {
    const controller = vscode.tests.createTestController('nsharp-tests', 'N# Tests');
    const runner = new NSharpTestRunner(controller);
    const disposables: vscode.Disposable[] = [controller];

    // Map from file URI string to its top-level TestItem
    const fileItems = new Map<string, vscode.TestItem>();

    // Run profile
    controller.createRunProfile(
        'Run',
        vscode.TestRunProfileKind.Run,
        (request, token) => runner.runTests(request, token),
        true
    );


    // Resolve handler: called when a test item needs its children populated
    controller.resolveHandler = async (item) => {
        if (!item) {
            // Root level: discover all .tests.nl files
            await discoverAllTestFiles();
            return;
        }
        // File-level item: discover tests within the file
        await discoverTestsInFile(item);
    };

    // Watch for .tests.nl file changes
    const watcher = vscode.workspace.createFileSystemWatcher('**/*.tests.nl');
    disposables.push(watcher);

    watcher.onDidCreate(uri => {
        addTestFileItem(uri);
    });

    watcher.onDidChange(async uri => {
        const item = fileItems.get(uri.toString());
        if (item) {
            await discoverTestsInFile(item);
        }
    });

    watcher.onDidDelete(uri => {
        const key = uri.toString();
        const item = fileItems.get(key);
        if (item) {
            controller.items.delete(item.id);
            fileItems.delete(key);
        }
    });

    // Re-discover when text documents change (live updates while editing)
    disposables.push(
        vscode.workspace.onDidChangeTextDocument(async e => {
            if (e.document.fileName.endsWith('.tests.nl')) {
                const item = fileItems.get(e.document.uri.toString());
                if (item) {
                    await discoverTestsInFile(item);
                }
            }
        })
    );

    // Register commands for CodeLens
    disposables.push(
        vscode.commands.registerCommand('nsharp.runTest', (description: string, fileUri?: string) => {
            const testItem = findTestByDescription(description, fileUri);
            if (testItem) {
                const request = new vscode.TestRunRequest([testItem]);
                runner.runTests(request, new vscode.CancellationTokenSource().token);
            }
        })
    );

    // Initial discovery
    discoverAllTestFiles();

    return vscode.Disposable.from(...disposables);

    // --- Helper functions ---

    async function discoverAllTestFiles() {
        const files = await vscode.workspace.findFiles('**/*.tests.nl');
        for (const uri of files) {
            addTestFileItem(uri);
        }
    }

    function addTestFileItem(uri: vscode.Uri) {
        const key = uri.toString();
        if (fileItems.has(key)) return;

        const relativePath = vscode.workspace.asRelativePath(uri);
        const item = controller.createTestItem(key, relativePath, uri);
        item.canResolveChildren = true;
        controller.items.add(item);
        fileItems.set(key, item);
    }

    async function discoverTestsInFile(fileItem: vscode.TestItem) {
        if (!fileItem.uri) return;

        try {
            const symbols = await vscode.commands.executeCommand<vscode.DocumentSymbol[]>(
                'vscode.executeDocumentSymbolProvider',
                fileItem.uri
            );

            if (!symbols) return;

            // Clear existing children
            fileItem.children.replace([]);

            for (const symbol of symbols) {
                if (symbol.detail === 'test') {
                    const testId = `${fileItem.id}::${symbol.name}`;
                    const testItem = controller.createTestItem(testId, symbol.name, fileItem.uri);
                    testItem.range = symbol.range;
                    fileItem.children.add(testItem);
                }
            }
        } catch {
            // LSP might not be ready yet; will be populated on next change
        }
    }

    function findTestByDescription(description: string, fileUri?: string): vscode.TestItem | undefined {
        // If file URI provided, search only in that file's tests
        if (fileUri) {
            const fileItem = fileItems.get(fileUri);
            if (fileItem) {
                let found: vscode.TestItem | undefined;
                fileItem.children.forEach(child => {
                    if (child.label === description) {
                        found = child;
                    }
                });
                if (found) return found;
            }
        }

        // Fallback: search all files
        for (const [, fileItem] of fileItems) {
            let found: vscode.TestItem | undefined;
            fileItem.children.forEach(child => {
                if (child.label === description) {
                    found = child;
                }
            });
            if (found) return found;
        }
        return undefined;
    }
}
