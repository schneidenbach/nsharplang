import * as assert from 'assert';
import * as childProcess from 'child_process';
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
    positionOf
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
    const before = await editorDiagnosticsOracle('before scenario');
    let details: Record<string, unknown>;
    switch (name) {
        case 'rename': details = await runRenameScenario(); break;
        case 'hover': details = await runHoverScenario(); break;
        case 'definition': details = await runDefinitionScenario(); break;
        case 'references': details = await runReferencesScenario(); break;
        case 'diagnostics': details = await runDiagnosticsScenario(); break;
        case 'completion': details = await runCompletionScenario(); break;
        case 'code-action': details = await runCodeActionScenario(); break;
    }
    const after = await editorDiagnosticsOracle('after scenario');
    if (name === 'rename') assertNoNewDiagnostics(before, after);
    return { ...details!, diagnosticsOracle: { sourceFiles: after.files, before: before.census.length, after: after.census.length, matchedCli: true,
        messageComparison: 'CLI summary line; VS Code retains its expanded help text' } };
}

async function editorDiagnosticsOracle(stage: string): Promise<{ files: number; census: string[] }> {
    const root = workspaceRoot();
    const uris = await vscode.workspace.findFiles('**/*.nl');
    const files = uris.map(uri => path.relative(root, uri.fsPath).split(path.sep).join('/'));
    const documents = await Promise.all(uris.map(uri => vscode.workspace.openTextDocument(uri)));
    const expected = runVisualOracle<{ census: string[] }>('diagnostics', [
        process.env.NSHARP_VSCODE_VISUAL_CLI_DLL ?? '', root
    ], JSON.stringify({ files })).census.sort();
    let lastActual: string[] = [], deadline = Date.now() + 45_000;
    while (Date.now() < deadline) {
        lastActual = documents.flatMap((document, index) => vscode.languages.getDiagnostics(uris[index]).map(diagnostic => {
            const code = diagnostic.code === undefined ? '' : typeof diagnostic.code === 'string' || typeof diagnostic.code === 'number'
                ? String(diagnostic.code) : String(diagnostic.code.value);
            const length = diagnostic.range.end.line === diagnostic.range.start.line
                ? diagnostic.range.end.character - diagnostic.range.start.character : -1;
            const message = diagnostic.message.replace(/\r?\n[\s\S]*/, '');
            return [code, vscode.DiagnosticSeverity[diagnostic.severity].toLowerCase(), files[index],
                diagnostic.range.start.line + 1, diagnostic.range.start.character + 1, length,
                message.startsWith(`${code}: `) ? message.slice(code.length + 2) : message].join('|');
        })).sort();
        if (lastActual.length === expected.length && lastActual.every((item, index) => item === expected[index]))
            return { files: files.length, census: expected };
        await sleep(250);
    }
    throw new Error(`Editor diagnostics did not match nlc check ${stage}: ${JSON.stringify({ editor: lastActual, cli: expected })}`);
}

function runVisualOracle<T>(mode: string, args: string[], input?: string): T {
    const script = process.env.NSHARP_VSCODE_VISUAL_ORACLE;
    if (!script) throw new Error('Visual oracle script path was not supplied');
    const run = childProcess.spawnSync('bash', [script, mode, ...args], {
        cwd: workspaceRoot(), encoding: 'utf8', input, timeout: 120_000,
        env: { ...process.env, NLC_NO_DAEMON: '1' }
    });
    if (run.error || run.status !== 0) throw new Error(`Independent ${mode} oracle failed: ${run.stderr}\n${run.stdout}`);
    return JSON.parse(run.stdout) as T;
}

function assertNoNewDiagnostics(before: { census: string[] }, after: { census: string[] }): void {
    const prior = new Set(before.census);
    const introduced = after.census.filter(item => !prior.has(item));
    assert.deepStrictEqual(introduced, [], `Rename introduced diagnostics: ${introduced.join('\n')}`);
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
    const cliReferences = runVisualOracle<any>('references', [
        process.env.NSHARP_VSCODE_VISUAL_CLI_DLL ?? '', path.join(root, 'backend'), 'Service.nl',
        `${declarationPosition.line + 1}:${declarationPosition.character + 1}`
    ]);
    assert.strictEqual(cliReferences.count, 9, 'Independent CLI reference oracle must include all nine source and test-block uses');
    const cliLocations = cliReferences.results.map((item: any) => `${path.resolve(root, 'backend', item.file)}:${item.line - 1}:${item.column - 1}`);
    const providerLocations = references.map(item => `${item.uri.fsPath}:${item.range.start.line}:${item.range.start.character}`);
    assert.deepStrictEqual(providerLocations.sort(), cliLocations.sort(), 'VS Code references differ from nlc query references');
    const beforeTokens = runVisualOracle<Record<string, { old: number; new: number }>>('tokens', [root, renameBefore, renameAfter]);
    assert.strictEqual(beforeTokens['backend/Service.tests.nl']?.old, 5, 'CLI token oracle must find five test-block uses before rename');
    const edit = await executeRename(source, declarationPosition, renameAfter);
    assert.ok(edit, 'Rename provider returned no WorkspaceEdit');
    const cliEditLocations = cliReferences.results.map((item: any) => `${path.resolve(root, 'backend', item.file)}:${item.line - 1}:${item.column - 1}`);
    const entries = edit!.entries();
    const editLocations = entries.flatMap(([uri, edits]) => edits.map(item => `${uri.fsPath}:${item.range.start.line}:${item.range.start.character}`));
    assert.deepStrictEqual(editLocations.sort(), cliEditLocations.sort(), 'WorkspaceEdit omitted or added a CLI-reported reference');
    if (!await vscode.workspace.applyEdit(edit!)) throw new Error('VS Code rejected the rename WorkspaceEdit');
    for (const [uri] of entries) {
        if (!await (await vscode.workspace.openTextDocument(uri)).save()) throw new Error(`Could not save renamed file ${uri.fsPath}`);
    }
    const afterTokens = runVisualOracle<Record<string, { old: number; new: number }>>('tokens', [root, renameBefore, renameAfter]);
    assert.strictEqual(Object.values(afterTokens).reduce((total, file) => total + file.old, 0), 0, 'Old symbol remains in an identifier position');
    assert.strictEqual(afterTokens['backend/Service.tests.nl']?.new, 5, 'Rename must update all five test-block uses');
    assert.strictEqual(Object.values(afterTokens).reduce((total, file) => total + file.new, 0), cliReferences.count,
        'New identifier count differs from the independent CLI reference count');
    const reportFiles = [...new Set([...Object.keys(beforeTokens), ...Object.keys(afterTokens)])].sort().map(file => ({
        file, beforeIdentifierCount: beforeTokens[file]?.old ?? 0,
        afterOldIdentifierCount: afterTokens[file]?.old ?? 0,
        afterNewIdentifierCount: afterTokens[file]?.new ?? 0
    }));

    const serviceFile = path.join(root, 'backend', 'Service.nl');
    const endpointFile = path.join(root, 'backend', 'Endpoints.nl');
    const serviceDoc = await vscode.workspace.openTextDocument(vscode.Uri.file(serviceFile));
    const endpointDoc = await vscode.workspace.openTextDocument(vscode.Uri.file(endpointFile));
    const serviceRange = addToPosition(positionOf(serviceDoc, `class ${renameAfter} {`), 'class '.length);
    const endpointRange = positionOf(endpointDoc, renameAfter);
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
        independentCliReferenceCount: cliReferences.count,
        oldIdentifierOccurrencesAfter: 0,
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
    const cli = runVisualOracle<{ count: number; results: Array<{ file: string; line: number; column: number }> }>('references', [
        process.env.NSHARP_VSCODE_VISUAL_CLI_DLL ?? '', path.join(workspaceRoot(), 'backend'), 'Service.nl',
        `${position.line + 1}:${position.character + 1}`
    ]);
    const cliLocations = cli.results.map(item => `${path.resolve(workspaceRoot(), 'backend', item.file)}:${item.line - 1}:${item.column - 1}`);
    assert.deepStrictEqual(references.map(item => `${item.uri.fsPath}:${item.range.start.line}:${item.range.start.character}`).sort(),
        cliLocations.sort(), 'VS Code references differ from nlc query references');
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
    const addition = '\nfunc VisualScenarioBroken( {\n}\n';
    const start = document.positionAt(document.getText().length);
    const insert = new vscode.WorkspaceEdit();
    insert.insert(document.uri, start, addition);
    if (!await vscode.workspace.applyEdit(insert)) throw new Error('VS Code rejected the diagnostic introduction edit');
    fs.writeFileSync(document.uri.fsPath, document.getText(), 'utf8');

    const insertedLine = start.line + 1;
    const introduced = await waitForCondition('N# error diagnostic for the inserted syntax error', async () => {
        const errors = vscode.languages.getDiagnostics(document.uri).filter(item =>
            item.severity === vscode.DiagnosticSeverity.Error && item.range.start.line >= insertedLine &&
            (item.source === 'N#' || item.source === 'nsharp'));
        return errors[0];
    }, 30_000);
    if (!introduced) throw new Error('No N# error was published for the inserted syntax error');
    const diagnosticOracle = await editorDiagnosticsOracle('while the inserted syntax error is present');
    await showSelection(document, introduced.range.start, Math.max(1, introduced.range.end.character - introduced.range.start.character));
    await vscode.commands.executeCommand('workbench.actions.view.problems');
    await sleep(750);
    return {
        file: path.relative(workspaceRoot(), document.uri.fsPath),
        introduced: serializeDiagnostic(introduced),
        diagnosticsCompared: diagnosticOracle.census.length,
        diagnosticRemainsVisible: true
    };
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

function selectionFor(position: vscode.Position, length: number): vscode.Selection {
    return new vscode.Selection(position, new vscode.Position(position.line, position.character + length));
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
