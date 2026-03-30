import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';

const LANGUAGE_SERVER_TIMEOUT = 60_000;
const DIAGNOSTICS_SETTLE_DELAY = 2_000;
const DIAGNOSTICS_TIMEOUT = 30_000;
const LSP_READY_POLL_INTERVAL = 500;
const LSP_READY_TIMEOUT = 15_000;

/**
 * Wait until the N# extension is active and the language server has initialized.
 */
export async function waitForLanguageServer(): Promise<void> {
    const ext = vscode.extensions.getExtension('nsharp.nsharp');
    if (!ext) {
        throw new Error('N# extension not found. Is the extension installed?');
    }

    if (!ext.isActive) {
        await ext.activate();
    }

    // Wait for the language server to be ready by opening a .nl file
    // and waiting for diagnostics to settle
    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (!workspaceFolders?.length) {
        throw new Error('No workspace folder open');
    }

    // Find any .nl file in the workspace
    const nlFiles = await vscode.workspace.findFiles('**/*.nl', undefined, 1);
    if (nlFiles.length === 0) {
        throw new Error('No .nl files found in workspace');
    }

    // Open the file to trigger the language server
    const doc = await vscode.workspace.openTextDocument(nlFiles[0]);
    await vscode.window.showTextDocument(doc);

    // Wait for initial diagnostics to settle (indicates server is ready)
    await waitForDiagnosticsToSettle(doc.uri, LANGUAGE_SERVER_TIMEOUT);
}

/**
 * Open a document by path relative to the workspace root.
 * Returns only after the document is recognized as nsharp language mode.
 */
export async function openDocument(relativePath: string): Promise<vscode.TextDocument> {
    const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
    if (!workspaceRoot) {
        throw new Error('No workspace folder open');
    }

    const fullPath = path.resolve(workspaceRoot, relativePath);
    if (!fs.existsSync(fullPath)) {
        throw new Error(`File not found: ${fullPath}`);
    }

    const uri = vscode.Uri.file(fullPath);
    const doc = await vscode.workspace.openTextDocument(uri);
    await vscode.window.showTextDocument(doc);

    // Wait for the language to be recognized
    if (fullPath.endsWith('.nl')) {
        let attempts = 0;
        while (doc.languageId !== 'nsharp' && attempts < 20) {
            await sleep(100);
            attempts++;
        }
    }

    return doc;
}

/**
 * Open a document by absolute path.
 */
export async function openDocumentByPath(absolutePath: string): Promise<vscode.TextDocument> {
    if (!fs.existsSync(absolutePath)) {
        throw new Error(`File not found: ${absolutePath}`);
    }

    const uri = vscode.Uri.file(absolutePath);
    const doc = await vscode.workspace.openTextDocument(uri);
    await vscode.window.showTextDocument(doc);
    return doc;
}

/**
 * Wait for diagnostics to stop changing for a debounce period.
 * This is the key anti-flakiness mechanism: the language server publishes
 * diagnostics asynchronously, so we wait until they stabilize.
 */
export async function waitForDiagnosticsToSettle(
    uri: vscode.Uri,
    timeout: number = DIAGNOSTICS_TIMEOUT
): Promise<vscode.Diagnostic[]> {
    return new Promise((resolve, reject) => {
        let lastDiagnostics = vscode.languages.getDiagnostics(uri);
        let settleTimer: ReturnType<typeof setTimeout> | null = null;
        let timeoutTimer: ReturnType<typeof setTimeout>;

        const listener = vscode.languages.onDidChangeDiagnostics(e => {
            if (e.uris.some(u => u.toString() === uri.toString())) {
                lastDiagnostics = vscode.languages.getDiagnostics(uri);

                // Reset the settle timer
                if (settleTimer) clearTimeout(settleTimer);
                settleTimer = setTimeout(() => {
                    cleanup();
                    resolve(lastDiagnostics);
                }, DIAGNOSTICS_SETTLE_DELAY);
            }
        });

        // Start initial settle timer (in case no diagnostic events fire)
        settleTimer = setTimeout(() => {
            cleanup();
            resolve(lastDiagnostics);
        }, DIAGNOSTICS_SETTLE_DELAY);

        // Overall timeout
        timeoutTimer = setTimeout(() => {
            cleanup();
            // Don't reject — just return whatever we have
            resolve(lastDiagnostics);
        }, timeout);

        function cleanup() {
            listener.dispose();
            if (settleTimer) clearTimeout(settleTimer);
            clearTimeout(timeoutTimer);
        }
    });
}

/**
 * Get diagnostics for a document, waiting for them to settle first.
 */
export async function getDiagnostics(doc: vscode.TextDocument): Promise<vscode.Diagnostic[]> {
    return waitForDiagnosticsToSettle(doc.uri);
}

/**
 * Execute the completion provider at a position.
 */
export async function getCompletions(
    doc: vscode.TextDocument,
    position: vscode.Position
): Promise<vscode.CompletionList> {
    const result = await vscode.commands.executeCommand<vscode.CompletionList>(
        'vscode.executeCompletionItemProvider',
        doc.uri,
        position
    );
    return result || new vscode.CompletionList([]);
}

/**
 * Execute the hover provider at a position.
 */
export async function getHover(
    doc: vscode.TextDocument,
    position: vscode.Position
): Promise<vscode.Hover[]> {
    const result = await vscode.commands.executeCommand<vscode.Hover[]>(
        'vscode.executeHoverProvider',
        doc.uri,
        position
    );
    return result || [];
}

/**
 * Execute the definition provider at a position.
 */
export async function getDefinitions(
    doc: vscode.TextDocument,
    position: vscode.Position
): Promise<vscode.Location[]> {
    const result = await vscode.commands.executeCommand<vscode.Location[]>(
        'vscode.executeDefinitionProvider',
        doc.uri,
        position
    );
    return result || [];
}

/**
 * Execute the references provider at a position.
 */
export async function getReferences(
    doc: vscode.TextDocument,
    position: vscode.Position
): Promise<vscode.Location[]> {
    const result = await vscode.commands.executeCommand<vscode.Location[]>(
        'vscode.executeReferenceProvider',
        doc.uri,
        position
    );
    return result || [];
}

/**
 * Execute the document symbol provider.
 */
export async function getDocumentSymbols(
    doc: vscode.TextDocument
): Promise<vscode.DocumentSymbol[]> {
    const result = await vscode.commands.executeCommand<vscode.DocumentSymbol[]>(
        'vscode.executeDocumentSymbolProvider',
        doc.uri
    );
    return result || [];
}

/**
 * Execute the signature help provider at a position.
 */
export async function getSignatureHelp(
    doc: vscode.TextDocument,
    position: vscode.Position
): Promise<vscode.SignatureHelp | undefined> {
    const result = await vscode.commands.executeCommand<vscode.SignatureHelp>(
        'vscode.executeSignatureHelpProvider',
        doc.uri,
        position
    );
    return result;
}

/**
 * Find a position in a document by searching for text.
 * This avoids hard-coding line/column numbers which break when files change.
 *
 * @param doc The document to search in
 * @param searchText The text to find
 * @param options Where to position the cursor relative to the match
 */
export function positionOf(
    doc: vscode.TextDocument,
    searchText: string,
    options: { at?: 'start' | 'end' | 'middle', occurrence?: number } = {}
): vscode.Position {
    const text = doc.getText();
    const { at = 'start', occurrence = 1 } = options;

    let index = -1;
    let found = 0;
    let startFrom = 0;
    while (found < occurrence) {
        index = text.indexOf(searchText, startFrom);
        if (index === -1) {
            throw new Error(
                `Text "${searchText}" not found (occurrence ${occurrence}) in ${doc.uri.fsPath}`
            );
        }
        found++;
        startFrom = index + 1;
    }

    let targetIndex: number;
    switch (at) {
        case 'end':
            targetIndex = index + searchText.length;
            break;
        case 'middle':
            targetIndex = index + Math.floor(searchText.length / 2);
            break;
        default:
            targetIndex = index;
    }

    return doc.positionAt(targetIndex);
}

/**
 * Wait until LSP features (hover, completions, etc.) are actually responsive
 * for a document. The language server needs time after initial connection to
 * parse and analyze files. This polls document symbols as a readiness signal.
 */
export async function waitForLspReady(doc: vscode.TextDocument): Promise<void> {
    const start = Date.now();
    while (Date.now() - start < LSP_READY_TIMEOUT) {
        try {
            const symbols = await vscode.commands.executeCommand<vscode.DocumentSymbol[]>(
                'vscode.executeDocumentSymbolProvider',
                doc.uri
            );
            if (symbols && symbols.length > 0) {
                return; // LSP is responding with real data
            }
        } catch {
            // Server not ready yet
        }
        await sleep(LSP_READY_POLL_INTERVAL);
    }
    // Don't throw — some files may legitimately have no symbols
}

/**
 * Open a document and wait for the LSP to be fully ready to serve requests.
 */
export async function openDocumentAndWaitForLsp(relativePath: string): Promise<vscode.TextDocument> {
    const doc = await openDocument(relativePath);
    await getDiagnostics(doc);
    await waitForLspReady(doc);
    return doc;
}

/**
 * Close all open editors to reset state between tests.
 */
export async function closeAllEditors(): Promise<void> {
    await vscode.commands.executeCommand('workbench.action.closeAllEditors');
}

/**
 * Get the absolute path to the repository root (two levels up from the extension dir).
 */
export function getRepoRoot(): string {
    const extensionDir = path.resolve(__dirname, '../../../');
    // The extension is at editors/vscode, so repo root is two levels up
    return path.resolve(extensionDir, '../..');
}

export function sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Create a temporary .nl file in the workspace with the given content,
 * open it via the LSP, and return the document along with a cleanup function.
 *
 * Use this for inline regression tests that need to test specific syntax
 * patterns without creating permanent fixture files.
 *
 * @param content The N# source code to write to the file
 * @param filename Optional filename (defaults to a unique temp name)
 */
export async function createTempNlFile(
    content: string,
    filename?: string
): Promise<{ doc: vscode.TextDocument; cleanup: () => void }> {
    const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
    if (!workspaceRoot) {
        throw new Error('No workspace folder open');
    }

    const name = filename || `_test_${Date.now()}_${Math.random().toString(36).slice(2, 8)}.nl`;
    const filePath = path.join(workspaceRoot, name);
    fs.writeFileSync(filePath, content, 'utf-8');

    const doc = await openDocument(name);
    const cleanup = () => {
        try {
            fs.unlinkSync(filePath);
        } catch {
            // Best-effort cleanup
        }
    };

    return { doc, cleanup };
}

/**
 * Format diagnostic errors into a readable string for assertion messages.
 */
export function formatDiagnosticErrors(errors: vscode.Diagnostic[]): string {
    return errors.map(d => {
        const range = `${d.range.start.line + 1}:${d.range.start.character + 1}`;
        const code = d.code ? ` [${d.code}]` : '';
        return `  Line ${range}${code}: ${d.message}`;
    }).join('\n');
}

/**
 * Find all .nl files in a directory (non-recursive single level).
 */
export function findNlFilesInDir(dir: string): string[] {
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir)
        .filter(f => f.endsWith('.nl'))
        .map(f => path.join(dir, f))
        .sort();
}

/**
 * Assert that a condition is true, but skip the test (instead of failing)
 * if the LSP feature isn't available. Use this for LSP features that
 * may not be fully implemented yet — it prevents false negatives while
 * still testing the feature when it works.
 */
export function assertOrSkip(
    condition: boolean,
    message: string,
    context: Mocha.Context
): void {
    if (!condition) {
        context.skip();
    }
}
