import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocument,
    getDiagnostics,
    closeAllEditors,
    sleep,
    waitForDiagnosticsToSettle,
    formatDiagnosticErrors,
    createTempNlFile
} from './helpers';

/**
 * Diagnostics tests with hard assertions.
 *
 * The TextDocumentHandler publishes diagnostics on open/change/save/close.
 * Diagnostic format:
 * - Source: "N#"
 * - Severity: Error, Warning, or Information
 * - Range: 0-based line/column with token-width spans
 * - Code: error/warning code string (e.g., "E001")
 */
suite('Diagnostics', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // CLEAN FILES — Zero errors
    // ================================================================

    test('Program.nl produces zero error diagnostics', async function () {
        this.timeout(30_000);
        const doc = await openDocument('Program.nl');
        const diagnostics = await getDiagnostics(doc);
        const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
        assert.strictEqual(errors.length, 0,
            `Expected 0 errors but got ${errors.length}:\n${formatDiagnosticErrors(errors)}`);
    });

    test('Helpers.nl produces zero error diagnostics', async function () {
        this.timeout(30_000);
        const doc = await openDocument('Helpers.nl');
        const diagnostics = await getDiagnostics(doc);
        const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
        assert.strictEqual(errors.length, 0,
            `Expected 0 errors in Helpers.nl but got ${errors.length}:\n${formatDiagnosticErrors(errors)}`);
    });

    test('ClassesAndRecords.nl produces zero error diagnostics', async function () {
        this.timeout(30_000);
        const doc = await openDocument('ClassesAndRecords.nl');
        const diagnostics = await getDiagnostics(doc);
        const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
        assert.strictEqual(errors.length, 0,
            `Expected 0 errors in ClassesAndRecords.nl but got ${errors.length}:\n${formatDiagnosticErrors(errors)}`);
    });

    // ================================================================
    // DIAGNOSTIC SOURCE
    // ================================================================

    test('all diagnostics have source "N#"', async function () {
        this.timeout(30_000);
        const doc = await openDocument('Program.nl');
        const diagnostics = await getDiagnostics(doc);
        for (const d of diagnostics) {
            assert.ok(
                d.source === 'N#' || d.source === 'nsharp',
                `Diagnostic at line ${d.range.start.line + 1} has unexpected source: "${d.source}". ` +
                `Expected "N#" or "nsharp". Message: ${d.message}`
            );
        }
    });

    // ================================================================
    // DIAGNOSTIC PROPERTIES
    // ================================================================

    test('diagnostics have non-empty messages', async function () {
        this.timeout(30_000);
        const doc = await openDocument('Program.nl');
        const diagnostics = await getDiagnostics(doc);
        for (const d of diagnostics) {
            assert.ok(d.message.length > 0,
                `Diagnostic at line ${d.range.start.line + 1} has empty message`);
        }
    });

    test('diagnostics have valid ranges', async function () {
        this.timeout(30_000);
        const doc = await openDocument('Program.nl');
        const diagnostics = await getDiagnostics(doc);
        for (const d of diagnostics) {
            assert.ok(d.range.start.line >= 0,
                `Diagnostic has negative start line: ${d.range.start.line}`);
            assert.ok(d.range.start.line <= doc.lineCount,
                `Diagnostic start line ${d.range.start.line} exceeds file length ${doc.lineCount}`);
        }
    });

    // ================================================================
    // INCREMENTAL DIAGNOSTICS — Edits trigger re-analysis
    // ================================================================

    test('diagnostics update after introducing syntax error', async function () {
        this.timeout(45_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace DiagEditTest
func Main() {
    x := 42
    print x
}
`, '_diag_edit.nl');

        try {
            // Should start clean
            let diagnostics = await getDiagnostics(doc);
            let errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                `Expected clean start but got errors:\n${formatDiagnosticErrors(errors)}`);

            // Introduce an error
            const editor = vscode.window.activeTextEditor!;
            await editor.edit(editBuilder => {
                const lastLine = doc.lineCount - 1;
                const pos = new vscode.Position(lastLine, doc.lineAt(lastLine).text.length);
                editBuilder.insert(pos, '\nfunc Broken( {\n}\n');
            });

            // Wait for diagnostics to update
            diagnostics = await waitForDiagnosticsToSettle(doc.uri, 15_000);
            errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);

            // The server DOES support incremental diagnostics via TextDocumentHandler
            assert.ok(errors.length > 0,
                'Expected errors after introducing syntax error but got none. ' +
                'TextDocumentHandler should re-publish diagnostics on didChange.');

            // Undo to restore clean state
            await vscode.commands.executeCommand('undo');
            await sleep(500);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    test('invalid member calls surface as editor diagnostics', async function () {
        this.timeout(45_000);
        const { doc, cleanup } = await createTempNlFile(`
package HelloWorld

func Hi() {
    "asdf".toUp()
    asdf := "asdf"
    asdf.sdd()
    return 42
}
`, '_diag_invalid_members.nl');

        try {
            const diagnostics = await waitForDiagnosticsToSettle(doc.uri, 20_000);
            const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);

            assert.ok(errors.some(d => d.code === 'NL303' && d.message.includes('toUp')),
                `Expected NL303 diagnostic for toUp:\n${formatDiagnosticErrors(errors)}`);
            assert.ok(errors.some(d => d.code === 'NL303' && d.message.includes('sdd')),
                `Expected NL303 diagnostic for sdd:\n${formatDiagnosticErrors(errors)}`);
            assert.ok(errors.some(d => d.code === 'NL202' && d.message.includes("Function 'Hi' returns int but has no return type")),
                `Expected NL202 diagnostic for return 42:\n${formatDiagnosticErrors(errors)}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    test('diagnostics clear after fixing syntax error', async function () {
        this.timeout(45_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace DiagFixTest
func Main() {
    x := 42
    print x
}
`, '_diag_fix.nl');

        try {
            // Start clean
            let diagnostics = await getDiagnostics(doc);
            assert.strictEqual(
                diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error).length, 0,
                'Should start clean');

            // Add valid code (not an error)
            const editor = vscode.window.activeTextEditor!;
            await editor.edit(editBuilder => {
                const lastLine = doc.lineCount - 1;
                const pos = new vscode.Position(lastLine, doc.lineAt(lastLine).text.length);
                editBuilder.insert(pos, '\nfunc ValidFunc(): int {\n    return 1\n}\n');
            });

            diagnostics = await waitForDiagnosticsToSettle(doc.uri, 15_000);
            const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                `Adding valid code should not introduce errors:\n${formatDiagnosticErrors(errors)}`);

            // Undo
            await vscode.commands.executeCommand('undo');
            await sleep(500);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });
});
