import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import * as assert from 'assert';

const LANGUAGE_SERVER_TIMEOUT = 60_000;
const DIAGNOSTICS_SETTLE_DELAY = 2_000;
const DIAGNOSTICS_TIMEOUT = 30_000;
const LSP_READY_POLL_INTERVAL = 500;
const LSP_READY_TIMEOUT = 15_000;

// ================================================================
// LANGUAGE SERVER LIFECYCLE
// ================================================================

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

    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (!workspaceFolders?.length) {
        throw new Error('No workspace folder open');
    }

    const nlFiles = await vscode.workspace.findFiles('**/*.nl', undefined, 1);
    if (nlFiles.length === 0) {
        throw new Error('No .nl files found in workspace');
    }

    const doc = await vscode.workspace.openTextDocument(nlFiles[0]);
    await vscode.window.showTextDocument(doc);
    await waitForDiagnosticsToSettle(doc.uri, LANGUAGE_SERVER_TIMEOUT);
}

// ================================================================
// DOCUMENT MANAGEMENT
// ================================================================

/**
 * Open a document by path relative to the workspace root.
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
 * Create a temporary .nl file in the workspace with the given content,
 * open it via the LSP, and return the document along with a cleanup function.
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

// ================================================================
// DIAGNOSTICS
// ================================================================

/**
 * Wait for diagnostics to stop changing for a debounce period.
 */
export async function waitForDiagnosticsToSettle(
    uri: vscode.Uri,
    timeout: number = DIAGNOSTICS_TIMEOUT
): Promise<vscode.Diagnostic[]> {
    return new Promise((resolve) => {
        let lastDiagnostics = vscode.languages.getDiagnostics(uri);
        let settleTimer: ReturnType<typeof setTimeout> | null = null;
        let timeoutTimer: ReturnType<typeof setTimeout>;

        const listener = vscode.languages.onDidChangeDiagnostics(e => {
            if (e.uris.some(u => u.toString() === uri.toString())) {
                lastDiagnostics = vscode.languages.getDiagnostics(uri);

                if (settleTimer) clearTimeout(settleTimer);
                settleTimer = setTimeout(() => {
                    cleanup();
                    resolve(lastDiagnostics);
                }, DIAGNOSTICS_SETTLE_DELAY);
            }
        });

        settleTimer = setTimeout(() => {
            cleanup();
            resolve(lastDiagnostics);
        }, DIAGNOSTICS_SETTLE_DELAY);

        timeoutTimer = setTimeout(() => {
            cleanup();
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

// ================================================================
// LSP FEATURE WRAPPERS
// ================================================================

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

export async function getDocumentSymbols(
    doc: vscode.TextDocument
): Promise<vscode.DocumentSymbol[]> {
    const result = await vscode.commands.executeCommand<vscode.DocumentSymbol[]>(
        'vscode.executeDocumentSymbolProvider',
        doc.uri
    );
    return result || [];
}

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

export async function getCodeActions(
    doc: vscode.TextDocument,
    range: vscode.Range
): Promise<vscode.CodeAction[]> {
    const result = await vscode.commands.executeCommand<vscode.CodeAction[]>(
        'vscode.executeCodeActionProvider',
        doc.uri,
        range
    );
    return result || [];
}

export async function getInlayHints(
    doc: vscode.TextDocument,
    range: vscode.Range
): Promise<vscode.InlayHint[]> {
    const result = await vscode.commands.executeCommand<vscode.InlayHint[]>(
        'vscode.executeInlayHintProvider',
        doc.uri,
        range
    );
    return result || [];
}

export async function executeRename(
    doc: vscode.TextDocument,
    position: vscode.Position,
    newName: string
): Promise<vscode.WorkspaceEdit | undefined> {
    const result = await vscode.commands.executeCommand<vscode.WorkspaceEdit>(
        'vscode.executeDocumentRenameProvider',
        doc.uri,
        position,
        newName
    );
    return result;
}

// ================================================================
// POSITION UTILITIES
// ================================================================

/**
 * Find a position in a document by searching for text.
 * Avoids hard-coding line/column numbers which break when files change.
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
 * Wait until LSP features are actually responsive for a document.
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
                return;
            }
        } catch {
            // Server not ready yet
        }
        await sleep(LSP_READY_POLL_INTERVAL);
    }
}

// ================================================================
// ASSERTION HELPERS — Hard assertions for real test coverage
// ================================================================

/**
 * Extract all text content from hover results as a single string.
 */
export function extractHoverText(hovers: vscode.Hover[]): string {
    return hovers.flatMap(h => h.contents).map(c => {
        if (typeof c === 'string') return c;
        if (c instanceof vscode.MarkdownString) return c.value;
        return (c as { value: string }).value || '';
    }).join('\n');
}

/**
 * Get the label string from a completion item.
 */
export function completionLabel(item: vscode.CompletionItem): string {
    return typeof item.label === 'string' ? item.label : item.label.label;
}

/**
 * Assert that a completion list contains an item with the given label.
 * Optionally check the CompletionItemKind.
 */
export function assertCompletionContains(
    completions: vscode.CompletionList,
    label: string,
    expectedKind?: vscode.CompletionItemKind
): vscode.CompletionItem {
    const item = completions.items.find(i => completionLabel(i) === label);
    assert.ok(item,
        `Expected completion "${label}" not found. Got: ${completions.items.map(i => completionLabel(i)).slice(0, 30).join(', ')}`);
    if (expectedKind !== undefined) {
        assert.strictEqual(item!.kind, expectedKind,
            `Completion "${label}" has kind ${item!.kind} (${vscode.CompletionItemKind[item!.kind!]}), ` +
            `expected ${expectedKind} (${vscode.CompletionItemKind[expectedKind]})`);
    }
    return item!;
}

/**
 * Assert that a completion list does NOT contain an item with the given label.
 */
export function assertCompletionExcludes(
    completions: vscode.CompletionList,
    label: string
): void {
    const item = completions.items.find(i => completionLabel(i) === label);
    assert.ok(!item,
        `Completion "${label}" should NOT be present but was found with kind ${item?.kind}`);
}

/**
 * Assert that a definition/reference location points to a file containing
 * the expected text at the target line. Uses text search, not line numbers.
 */
export async function assertLocationContains(
    location: vscode.Location,
    expectedFilePattern: string,
    expectedLineText: string
): Promise<void> {
    assert.ok(location.uri.fsPath.endsWith(expectedFilePattern) || location.uri.fsPath.includes(expectedFilePattern),
        `Expected location in file matching "${expectedFilePattern}", got ${path.basename(location.uri.fsPath)}`);

    const doc = await vscode.workspace.openTextDocument(location.uri);
    const targetLine = doc.lineAt(location.range.start.line).text;
    assert.ok(targetLine.includes(expectedLineText),
        `Expected target line to contain "${expectedLineText}", got: "${targetLine.trim()}" at line ${location.range.start.line + 1}`);
}

/**
 * Find a symbol by name in a document symbol tree (recursive).
 */
export function findSymbol(
    symbols: vscode.DocumentSymbol[],
    name: string
): vscode.DocumentSymbol | undefined {
    for (const s of symbols) {
        if (s.name === name) return s;
        const child = findSymbol(s.children, name);
        if (child) return child;
    }
    return undefined;
}

/**
 * Assert a symbol exists with the expected kind.
 * Returns the symbol for further assertions.
 */
export function assertSymbolExists(
    symbols: vscode.DocumentSymbol[],
    name: string,
    expectedKind: vscode.SymbolKind
): vscode.DocumentSymbol {
    const sym = findSymbol(symbols, name);
    assert.ok(sym,
        `Expected symbol "${name}" not found. Got: ${flattenSymbolNames(symbols).join(', ')}`);
    assert.strictEqual(sym!.kind, expectedKind,
        `Symbol "${name}" has kind ${vscode.SymbolKind[sym!.kind]}, expected ${vscode.SymbolKind[expectedKind]}`);
    return sym!;
}

/**
 * Flatten all symbol names from a symbol tree (recursive).
 */
export function flattenSymbolNames(symbols: vscode.DocumentSymbol[]): string[] {
    const names: string[] = [];
    for (const s of symbols) {
        names.push(s.name);
        if (s.children.length > 0) {
            names.push(...flattenSymbolNames(s.children));
        }
    }
    return names;
}

/**
 * Measure execution time of an async operation.
 */
export async function timed<T>(
    operation: () => Promise<T>,
    label: string
): Promise<{ result: T; durationMs: number }> {
    const start = Date.now();
    const result = await operation();
    const durationMs = Date.now() - start;
    return { result, durationMs };
}

// ================================================================
// FORMATTING
// ================================================================

export function formatDiagnosticErrors(errors: vscode.Diagnostic[]): string {
    return errors.map(d => {
        const range = `${d.range.start.line + 1}:${d.range.start.character + 1}`;
        const code = d.code ? ` [${d.code}]` : '';
        return `  Line ${range}${code}: ${d.message}`;
    }).join('\n');
}

// ================================================================
// UTILITIES
// ================================================================

export function getRepoRoot(): string {
    const extensionDir = path.resolve(__dirname, '../../../');
    return path.resolve(extensionDir, '../..');
}

export function sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
}

export function findNlFilesInDir(dir: string): string[] {
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir)
        .filter(f => f.endsWith('.nl'))
        .map(f => path.join(dir, f))
        .sort();
}

/**
 * @deprecated Use hard assertions instead. This function silently skips
 * tests, masking real regressions. Only use for genuinely unimplemented features.
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
