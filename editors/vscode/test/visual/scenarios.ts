import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import {
    completionLabel,
    executeRename,
    extractHoverText,
    getCodeActions,
    getCompletions,
    getDefinitions,
    getHover,
    getReferences,
    openDocumentAndWaitForLsp,
    positionOf,
    waitForDiagnosticsToSettle
} from '../suite/helpers';

export const visualScenarioNames = [
    'rename',
    'hover',
    'definition',
    'references',
    'diagnostics',
    'completion',
    'code-action'
] as const;

export type VisualScenarioName = typeof visualScenarioNames[number];

interface ScenarioReport {
    scenario: VisualScenarioName;
    status: 'passed';
    generatedAt: string;
    workspaceRoot: string;
    vscodeVersion: string;
    details: Record<string, unknown>;
}

const oldSymbol = 'CreateIssue';
const newSymbol = 'CreateTrackedIssue';
const renameBefore = 'IssueService';
const renameAfter = 'IssueTrackerService';

export async function runVisualScenario(name: VisualScenarioName): Promise<Record<string, unknown>> {
    switch (name) {
        case 'rename': return runRenameScenario();
        case 'hover': return runHoverScenario();
        case 'definition': return runDefinitionScenario();
        case 'references': return runReferencesScenario();
        case 'diagnostics': return runDiagnosticsScenario();
        case 'completion': return runCompletionScenario();
        case 'code-action': return runCodeActionScenario();
    }
}

export function writeVisualReport(
    reportPath: string,
    scenario: VisualScenarioName,
    details: Record<string, unknown>
): void {
    const report: ScenarioReport = {
        scenario,
        status: 'passed',
        generatedAt: new Date().toISOString(),
        workspaceRoot: workspaceRoot(),
        vscodeVersion: vscode.version,
        details
    };
    fs.mkdirSync(path.dirname(reportPath), { recursive: true });
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
}

async function runRenameScenario(): Promise<Record<string, unknown>> {
    const root = workspaceRoot();
    const source = await openDocumentAndWaitForLsp('backend/Service.nl');
    const declarationPosition = addToPosition(positionOf(source, `class ${renameBefore} {`), 'class '.length);
    const references = await getReferences(source, declarationPosition);
    assert.ok(references.length >= 3, `Expected at least 3 semantic references, got ${references.length}`);

    const beforeByPath = new Map<string, string>();
    for (const file of findNlFiles(root)) beforeByPath.set(file, fs.readFileSync(file, 'utf8'));

    const edit = await executeRename(source, declarationPosition, renameAfter);
    assert.ok(edit, 'Rename provider returned no WorkspaceEdit');
    const entries = edit!.entries();
    const changedLocations = new Set<string>();
    const changesByFile = new Map<string, Array<{
        range: vscode.Range;
        startOffset: number;
        endOffset: number;
        oldText: string;
        newText: string;
    }>>();

    for (const [uri, edits] of entries) {
        const document = await vscode.workspace.openTextDocument(uri);
        const changes = edits.map(textEdit => {
            const oldText = document.getText(textEdit.range);
            assert.strictEqual(oldText, renameBefore, `Unexpected rename source text: ${JSON.stringify(oldText)}`);
            assert.strictEqual(textEdit.newText, renameAfter, `Unexpected rename target: ${textEdit.newText}`);
            const locationKey = `${uri.fsPath}:${textEdit.range.start.line}:${textEdit.range.start.character}`;
            changedLocations.add(locationKey);
            return {
                range: textEdit.range,
                startOffset: document.offsetAt(textEdit.range.start),
                endOffset: document.offsetAt(textEdit.range.end),
                oldText,
                newText: textEdit.newText
            };
        });
        changesByFile.set(uri.fsPath, changes);
    }

    const expectedLocations = new Set(references.map(location =>
        `${location.uri.fsPath}:${location.range.start.line}:${location.range.start.character}`));
    assert.deepStrictEqual(
        [...changedLocations].sort(),
        [...expectedLocations].sort(),
        'Rename edits must cover every semantic reference, with no extra locations'
    );

    const changedFiles = [...changesByFile.keys()];
    assert.ok(new Set(changedFiles).size >= 3, `Expected rename to span 3 or more files, got ${changedFiles.length}`);
    assert.ok(await vscode.workspace.applyEdit(edit!), 'VS Code rejected the rename WorkspaceEdit');

    const reportFiles: Array<Record<string, unknown>> = [];
    for (const [file, changes] of changesByFile) {
        const document = await vscode.workspace.openTextDocument(vscode.Uri.file(file));
        assert.ok(await document.save(), `Could not save renamed file ${file}`);
        const after = document.getText();
        const before = beforeByPath.get(file);
        assert.ok(before !== undefined, `Rename edit targeted a file outside the workspace: ${file}`);
        const expected = applyTextChanges(before!, changes);
        assert.strictEqual(after, expected, `Unexpected edits outside the rename ranges in ${file}`);
        reportFiles.push({
            file: path.relative(root, file),
            before,
            after,
            ranges: changes.map(change => ({
                start: serializePosition(change.range.start),
                end: serializePosition(change.range.end),
                before: change.oldText,
                after: change.newText
            }))
        });
    }

    for (const [file, before] of beforeByPath) {
        if (changesByFile.has(file)) continue;
        assert.strictEqual(fs.readFileSync(file, 'utf8'), before, `Rename modified an unrelated file: ${file}`);
    }

    const serviceFile = path.join(root, 'backend', 'Service.nl');
    const endpointFile = path.join(root, 'backend', 'Endpoints.nl');
    const serviceDoc = await vscode.workspace.openTextDocument(vscode.Uri.file(serviceFile));
    const endpointDoc = await vscode.workspace.openTextDocument(vscode.Uri.file(endpointFile));
    const serviceRange = firstRange(changesByFile.get(serviceFile), renameAfter);
    const endpointRange = firstRange(changesByFile.get(endpointFile), renameAfter);
    await vscode.window.showTextDocument(serviceDoc, {
        viewColumn: vscode.ViewColumn.One,
        preview: false,
        selection: selectionFor(serviceRange, renameAfter.length)
    });
    await vscode.window.showTextDocument(endpointDoc, {
        viewColumn: vscode.ViewColumn.Two,
        preview: false,
        selection: selectionFor(endpointRange, renameAfter.length)
    });

    return {
        symbol: { before: renameBefore, after: renameAfter },
        semanticReferenceCount: references.length,
        files: reportFiles
    };
}

async function runHoverScenario(): Promise<Record<string, unknown>> {
    const document = await openDocumentAndWaitForLsp('backend/Endpoints.nl');
    const position = symbolPosition(document, 'service.CreateIssue');
    const hovers = await getHover(document, position);
    const contents = extractHoverText(hovers);
    assert.ok(hovers.length > 0, 'Hover provider returned no hover contents');
    assert.ok(contents.includes(oldSymbol), `Hover did not describe ${oldSymbol}: ${contents}`);

    await showSelection(document, position, oldSymbol.length);
    const panel = vscode.window.createWebviewPanel(
        'nsharpVisualHover',
        `N# Hover · ${oldSymbol}`,
        vscode.ViewColumn.Beside,
        { enableScripts: false }
    );
    panel.webview.html = hoverHtml(contents);
    return { file: path.relative(workspaceRoot(), document.uri.fsPath), position: serializePosition(position), contents };
}

async function runDefinitionScenario(): Promise<Record<string, unknown>> {
    const source = await openDocumentAndWaitForLsp('backend/Endpoints.nl');
    const position = symbolPosition(source, 'service.CreateIssue');
    const definitions = await getDefinitions(source, position);
    assert.ok(definitions.length > 0, `Definition provider returned no result for ${oldSymbol}`);

    const definition = definitions.find(item => locationUri(item).fsPath.endsWith(path.join('backend', 'Service.nl')));
    assert.ok(definition, `Expected the definition in backend/Service.nl; got ${definitions.map(item => locationUri(item).fsPath).join(', ')}`);
    const targetUri = locationUri(definition!);
    const targetRange = locationRange(definition!);
    const target = await vscode.workspace.openTextDocument(targetUri);
    assert.ok(target.lineAt(targetRange.start.line).text.includes(`func ${oldSymbol}(`), 'Definition did not land on the method declaration');
    await vscode.window.showTextDocument(target, { viewColumn: vscode.ViewColumn.One, preview: false, selection: targetRange });

    return {
        from: path.relative(workspaceRoot(), source.uri.fsPath),
        target: path.relative(workspaceRoot(), targetUri.fsPath),
        range: { start: serializePosition(targetRange.start), end: serializePosition(targetRange.end) },
        line: target.lineAt(targetRange.start.line).text.trim()
    };
}

async function runReferencesScenario(): Promise<Record<string, unknown>> {
    const source = await openDocumentAndWaitForLsp('backend/Service.nl');
    const position = addToPosition(positionOf(source, `class ${renameBefore} {`), 'class '.length);
    const references = await getReferences(source, position);
    assert.ok(references.length >= 3, `Expected at least three references, got ${references.length}`);
    const files = [...new Set(references.map(reference => path.relative(workspaceRoot(), reference.uri.fsPath)))].sort();
    assert.ok(files.length >= 3, `Expected references in at least three files, got ${files.join(', ')}`);

    await vscode.commands.executeCommand('editor.action.showReferences', source.uri, position, references);
    return {
        symbol: renameBefore,
        count: references.length,
        references: references.map(reference => ({
            file: path.relative(workspaceRoot(), reference.uri.fsPath),
            range: { start: serializePosition(reference.range.start), end: serializePosition(reference.range.end) }
        }))
    };
}

async function runDiagnosticsScenario(): Promise<Record<string, unknown>> {
    const document = await openDocumentAndWaitForLsp('backend/Service.nl');
    const original = document.getText();
    const baseline = await waitForDiagnosticsToSettle(document.uri, 30_000);
    const baselineKeys = new Set(baseline.map(diagnosticKey));
    const addition = '\nfunc VisualScenarioBroken( {\n}\n';
    const start = document.positionAt(original.length);
    const insert = new vscode.WorkspaceEdit();
    insert.insert(document.uri, start, addition);
    assert.ok(await vscode.workspace.applyEdit(insert), 'VS Code rejected the diagnostic introduction edit');

    const insertedLine = start.line + 1;
    let introduced: vscode.Diagnostic | undefined;
    try {
        introduced = await waitForCondition('N# error diagnostic for the inserted syntax error', async () => {
            const errors = vscode.languages.getDiagnostics(document.uri).filter(item =>
                item.severity === vscode.DiagnosticSeverity.Error && item.range.start.line >= insertedLine &&
                (item.source === 'N#' || item.source === 'nsharp'));
            return errors[0];
        }, 30_000);
        assert.ok(introduced, 'No N# error was published for the inserted syntax error');

        await showSelection(document, introduced.range.start, Math.max(1, introduced.range.end.character - introduced.range.start.character));
        await vscode.commands.executeCommand('workbench.actions.view.problems');
        await sleep(500);

        const revert = new vscode.WorkspaceEdit();
        revert.delete(document.uri, new vscode.Range(start, document.positionAt(original.length + addition.length)));
        assert.ok(await vscode.workspace.applyEdit(revert), 'VS Code rejected the diagnostic revert edit');
        assert.ok(await document.save(), 'Could not save the restored source file');
        assert.strictEqual(document.getText(), original, 'Diagnostic scenario did not restore the original file text');
        const cleared = await waitForCondition('inserted diagnostic to clear', async () => {
            const current = vscode.languages.getDiagnostics(document.uri);
            const newErrors = current.filter(item => item.severity === vscode.DiagnosticSeverity.Error && !baselineKeys.has(diagnosticKey(item)));
            return newErrors.length === 0 ? current : undefined;
        }, 30_000);

        return {
            file: path.relative(workspaceRoot(), document.uri.fsPath),
            introduced: serializeDiagnostic(introduced),
            diagnosticsAfterRevert: cleared.map(serializeDiagnostic),
            reverted: true
        };
    } finally {
        if (document.getText() !== original) {
            const restore = new vscode.WorkspaceEdit();
            restore.replace(document.uri, new vscode.Range(document.positionAt(0), document.positionAt(document.getText().length)), original);
            await vscode.workspace.applyEdit(restore);
            await document.save();
        }
    }
}

async function runCompletionScenario(): Promise<Record<string, unknown>> {
    const document = await openDocumentAndWaitForLsp('backend/Endpoints.nl');
    const callPosition = positionOf(document, 'service.GetAll');
    const position = addToPosition(callPosition, 'service.'.length);
    const completions = await getCompletions(document, position);
    const labels = completions.items.map(completionLabel);
    assert.ok(labels.includes('CreateIssue'), `Completion results omitted CreateIssue: ${labels.slice(0, 40).join(', ')}`);
    assert.ok(labels.includes('GetAll'), `Completion results omitted GetAll: ${labels.slice(0, 40).join(', ')}`);

    await showSelection(document, position, 0);
    const panel = vscode.window.createWebviewPanel(
        'nsharpVisualCompletions',
        'N# Completions',
        vscode.ViewColumn.Beside,
        { enableScripts: false }
    );
    panel.webview.html = completionHtml(labels, completions.items.length);
    return {
        file: path.relative(workspaceRoot(), document.uri.fsPath),
        count: completions.items.length,
        labels: labels.slice(0, 80)
    };
}

async function runCodeActionScenario(): Promise<Record<string, unknown>> {
    const file = vscode.Uri.file(path.join(workspaceRoot(), 'backend', 'VisualQuickFix.nl'));
    const source = [
        'namespace VisualQuickFix',
        '',
        'func Values(): List<int> {',
        '    return new List<int>()',
        '}',
        ''
    ].join('\n');
    const create = new vscode.WorkspaceEdit();
    create.createFile(file, { overwrite: true, ignoreIfExists: false });
    create.insert(file, new vscode.Position(0, 0), source);
    assert.ok(await vscode.workspace.applyEdit(create), 'Could not create the quick-fix scenario file');

    const document = await openDocumentAndWaitForLsp('backend/VisualQuickFix.nl');
    const diagnostics = await waitForCondition('NL002 missing-import diagnostic', async () =>
        vscode.languages.getDiagnostics(document.uri).find(item => item.code === 'NL002'), 30_000);
    assert.ok(diagnostics, 'Expected NL002 on List<int>');
    const range = diagnostics.range;
    const actions = await waitForCondition('Add import System.Collections.Generic quick fix', async () => {
        const available = await getCodeActions(document, range);
        return available.some(action => action.title === 'Add import System.Collections.Generic') ? available : undefined;
    }, 20_000);
    const quickFix = actions.find(action => action.title === 'Add import System.Collections.Generic');
    assert.ok(quickFix, 'The N# import quick fix was not offered');
    if (quickFix!.edit) {
        assert.ok(await vscode.workspace.applyEdit(quickFix!.edit), 'VS Code rejected the quick-fix WorkspaceEdit');
    } else if (quickFix!.command) {
        await vscode.commands.executeCommand(quickFix!.command.command, ...(quickFix!.command.arguments ?? []));
    } else {
        throw new Error('The N# import quick fix supplied neither an edit nor a command');
    }
    assert.ok(await document.save(), 'Could not save the quick-fix result');
    assert.ok(document.getText().includes('import System.Collections.Generic'), 'Quick fix did not add the collection import');
    await waitForCondition('NL002 to clear after import quick fix', async () =>
        vscode.languages.getDiagnostics(document.uri).some(item => item.code === 'NL002') ? undefined : true, 30_000);

    const importPosition = positionOf(document, 'import System.Collections.Generic');
    await showSelection(document, importPosition, 'import System.Collections.Generic'.length);
    return {
        file: path.relative(workspaceRoot(), document.uri.fsPath),
        action: quickFix!.title,
        finalText: document.getText(),
        diagnosticsAfterFix: vscode.languages.getDiagnostics(document.uri).map(serializeDiagnostic)
    };
}

function applyTextChanges(
    original: string,
    changes: Array<{ startOffset: number; endOffset: number; newText: string }>
): string {
    const sorted = [...changes].sort((left, right) => right.startOffset - left.startOffset);
    let result = original;
    let lastStart = Number.POSITIVE_INFINITY;
    for (const change of sorted) {
        assert.ok(change.endOffset <= lastStart, 'Rename edits overlap');
        result = `${result.slice(0, change.startOffset)}${change.newText}${result.slice(change.endOffset)}`;
        lastStart = change.startOffset;
    }
    return result;
}

function firstRange(
    changes: Array<{ range: vscode.Range; newText: string }> | undefined,
    newText: string
): vscode.Range {
    const found = changes?.find(change => change.newText === newText);
    assert.ok(found, `No WorkspaceEdit range found for ${newText}`);
    return found!.range;
}

function selectionFor(range: vscode.Range, length: number): vscode.Selection {
    const end = new vscode.Position(range.start.line, range.start.character + length);
    return new vscode.Selection(range.start, end);
}

async function showSelection(document: vscode.TextDocument, position: vscode.Position, length: number): Promise<void> {
    const range = new vscode.Range(position, new vscode.Position(position.line, position.character + length));
    await vscode.window.showTextDocument(document, { preview: false, selection: range });
    const editor = vscode.window.activeTextEditor;
    assert.ok(editor, 'No active text editor after opening the scenario document');
    editor!.selection = new vscode.Selection(range.start, range.end);
    editor!.revealRange(range, vscode.TextEditorRevealType.InCenterIfOutsideViewport);
}

function symbolPosition(document: vscode.TextDocument, containingText: string): vscode.Position {
    const start = positionOf(document, containingText);
    return addToPosition(start, containingText.indexOf('.') + 1);
}

function addToPosition(position: vscode.Position, characters: number): vscode.Position {
    return new vscode.Position(position.line, position.character + characters);
}

function locationUri(location: vscode.Location | vscode.LocationLink): vscode.Uri {
    return 'targetUri' in location ? location.targetUri : location.uri;
}

function locationRange(location: vscode.Location | vscode.LocationLink): vscode.Range {
    return 'targetUri' in location ? location.targetSelectionRange ?? location.targetRange : location.range;
}

function serializePosition(position: vscode.Position): { line: number; character: number } {
    return { line: position.line, character: position.character };
}

function serializeDiagnostic(diagnostic: vscode.Diagnostic): Record<string, unknown> {
    return {
        code: diagnostic.code ?? null,
        severity: vscode.DiagnosticSeverity[diagnostic.severity],
        source: diagnostic.source ?? null,
        message: diagnostic.message,
        range: { start: serializePosition(diagnostic.range.start), end: serializePosition(diagnostic.range.end) }
    };
}

function diagnosticKey(diagnostic: vscode.Diagnostic): string {
    return `${diagnostic.code ?? ''}:${diagnostic.severity}:${diagnostic.range.start.line}:${diagnostic.range.start.character}:${diagnostic.message}`;
}

function serializeDiagnosticSummary(diagnostic: vscode.Diagnostic): Record<string, unknown> {
    return serializeDiagnostic(diagnostic);
}

async function waitForCondition<T>(
    description: string,
    probe: () => Promise<T | undefined> | T | undefined,
    timeoutMs: number
): Promise<T> {
    const started = Date.now();
    while (Date.now() - started < timeoutMs) {
        const result = await probe();
        if (result !== undefined) return result;
        await sleep(200);
    }
    throw new Error(`Timed out waiting for ${description}`);
}

function workspaceRoot(): string {
    const root = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
    if (!root) throw new Error('No workspace folder is open');
    return root;
}

function findNlFiles(root: string): string[] {
    const files: string[] = [];
    const visit = (directory: string) => {
        for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
            if (entry.name === '.git' || entry.name === 'node_modules' || entry.name === 'bin' || entry.name === 'obj') continue;
            const fullPath = path.join(directory, entry.name);
            if (entry.isDirectory()) visit(fullPath);
            else if (entry.isFile() && entry.name.endsWith('.nl')) files.push(fullPath);
        }
    };
    visit(root);
    return files.sort();
}

function completionHtml(labels: string[], total: number): string {
    const rows = labels.slice(0, 100).map(label => `<li>${escapeHtml(label)}</li>`).join('\n');
    return `<!DOCTYPE html><html><head><meta charset="UTF-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"><style>body{font-family:var(--vscode-font-family);color:var(--vscode-foreground);padding:12px}h1{font-size:18px}li{padding:3px 0;font-family:var(--vscode-editor-font-family)}</style></head><body><h1>N# member completions (${total})</h1><p>Visible results returned by <code>vscode.executeCompletionItemProvider</code>.</p><ol>${rows}</ol></body></html>`;
}

function hoverHtml(contents: string): string {
    return `<!DOCTYPE html><html><head><meta charset="UTF-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"><style>body{font-family:var(--vscode-font-family);color:var(--vscode-foreground);padding:14px}h1{font-size:18px}pre{white-space:pre-wrap;border-left:3px solid var(--vscode-textLink-foreground);padding:10px 12px;background:var(--vscode-editor-background);font-family:var(--vscode-editor-font-family)}</style></head><body><h1>N# Hover</h1><p>Provider result for <code>${oldSymbol}</code> from <code>vscode.executeHoverProvider</code>.</p><pre>${escapeHtml(contents)}</pre></body></html>`;
}

function escapeHtml(value: string): string {
    return value.replace(/[&<>"']/g, character => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
    })[character]!);
}

function sleep(milliseconds: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, milliseconds));
}
