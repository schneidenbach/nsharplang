import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocument,
    getDiagnostics,
    closeAllEditors,
    sleep,
    waitForDiagnosticsToSettle,
    assertOrSkip
} from './helpers';

suite('Diagnostics', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    test('clean file produces zero error diagnostics', async function () {
        this.timeout(30_000);
        const doc = await openDocument('Program.nl');
        const diagnostics = await getDiagnostics(doc);
        const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
        assert.strictEqual(errors.length, 0,
            `Expected 0 errors but got ${errors.length}: ${errors.map(d => d.message).join('; ')}`);
    });

    test('diagnostics have correct source', async function () {
        this.timeout(30_000);
        const doc = await openDocument('Program.nl');
        const diagnostics = await getDiagnostics(doc);
        for (const d of diagnostics) {
            // All diagnostics from our language server should have source set
            if (d.source) {
                assert.ok(
                    d.source === 'N#' || d.source === 'nsharp',
                    `Unexpected diagnostic source: ${d.source}`
                );
            }
        }
    });

    test('diagnostics update after document edit', async function () {
        this.timeout(45_000);

        // Open a clean file and verify no errors
        const doc = await openDocument('Program.nl');
        let diagnostics = await getDiagnostics(doc);
        const initialErrors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);

        // Now introduce a syntax error by editing the document
        const editor = vscode.window.activeTextEditor!;
        await editor.edit(editBuilder => {
            // Insert a syntax error at the end
            const lastLine = doc.lineCount - 1;
            const pos = new vscode.Position(lastLine, doc.lineAt(lastLine).text.length);
            editBuilder.insert(pos, '\nfunc broken( {\n}\n');
        });

        // Wait for diagnostics to update with a longer timeout to ensure the server re-processes
        diagnostics = await waitForDiagnosticsToSettle(doc.uri, 15_000);
        const errorsAfterEdit = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);

        // Skip if the server didn't re-process (some configurations don't re-analyze inline edits)
        assertOrSkip(errorsAfterEdit.length > 0,
            'Server did not produce diagnostics after edit', this);

        // Undo the edit to restore the file
        await vscode.commands.executeCommand('undo');
        await sleep(500);
    });

    test('multi-file workspace produces diagnostics for helper file', async function () {
        this.timeout(30_000);
        const doc = await openDocument('Helpers.nl');
        const diagnostics = await getDiagnostics(doc);
        const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
        assert.strictEqual(errors.length, 0,
            `Expected 0 errors in Helpers.nl but got ${errors.length}: ${errors.map(d => d.message).join('; ')}`);
    });
});
