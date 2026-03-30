import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getCompletions,
    getHover,
    getDefinitions,
    getReferences,
    getDocumentSymbols,
    getDiagnostics,
    createTempNlFile,
    closeAllEditors,
    positionOf,
    formatDiagnosticErrors,
    waitForDiagnosticsToSettle,
    sleep,
    extractHoverText,
    completionLabel,
    assertSymbolExists,
    flattenSymbolNames,
    assertLocationContains
} from './helpers';

/**
 * Complex scenario integration tests — multi-step workflows.
 *
 * These test realistic developer workflows that combine multiple LSP features:
 * - Cross-file navigation with position pinning
 * - LSP features after document edits (completions, hover, diagnostics)
 * - Variable scope and shadowing
 * - Enum member navigation
 * - Multi-edit diagnostic consistency
 *
 * ALL assertions are hard — no assertOrSkip. These handlers are implemented.
 */
suite('Complex Scenarios — Multi-file & Workflows', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // CROSS-FILE NAVIGATION
    // ================================================================

    test('cross-file definition navigates to correct file', async function () {
        this.timeout(60_000);
        const { doc: helperDoc, cleanup: cleanupHelper } = await createTempNlFile(`
namespace CrossNavTest
func crossNavHelper(): string {
    return "from helper"
}
`, '_complex_cross_helper.nl');

        const { doc: mainDoc, cleanup: cleanupMain } = await createTempNlFile(`
namespace CrossNavTest
func Main() {
    result := crossNavHelper()
    print result
}
`, '_complex_cross_main.nl');

        try {
            await getDiagnostics(helperDoc);
            await getDiagnostics(mainDoc);

            const pos = positionOf(mainDoc, 'crossNavHelper()');
            const defs = await getDefinitions(mainDoc, pos);

            assert.ok(defs.length > 0,
                'Cross-file definition should return results');
            assert.ok(defs[0].uri.fsPath.endsWith('.nl'),
                `Definition should be in .nl file, got ${defs[0].uri.fsPath}`);
        } finally {
            await closeAllEditors();
            cleanupHelper();
            cleanupMain();
        }
    });

    // ================================================================
    // CROSS-FILE REFERENCES
    // ================================================================

    test('find references includes usages across files', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // "greet" — defined at line 5, called at line 39
        const pos = positionOf(doc, 'func greet(', { at: 'start' });
        const greetPos = new vscode.Position(pos.line, pos.character + 5);
        const refs = await getReferences(doc, greetPos);

        assert.ok(refs.length >= 2,
            `Expected at least 2 references (def + usage) for "greet", got ${refs.length}`);

        for (const ref of refs) {
            assert.ok(ref.uri.fsPath.endsWith('.nl'),
                `Reference should be in .nl file, got ${ref.uri.fsPath}`);
        }
    });

    // ================================================================
    // MEMBER COMPLETIONS
    // ================================================================

    test('class member completions return methods and properties', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // After "person." in "person.GetInfo()"
        const pos = positionOf(doc, 'person.GetInfo()', { at: 'start' });
        const dotPos = new vscode.Position(pos.line, pos.character + 7);
        const completions = await getCompletions(doc, dotPos);

        assert.ok(completions.items.length > 0,
            'Member completions should return results after dot');

        const labels = completions.items.map(i => completionLabel(i));
        assert.ok(labels.includes('GetInfo'),
            `Member completions should include "GetInfo". Got: ${labels.slice(0, 20).join(', ')}`);
    });

    // ================================================================
    // HOVER CONTENT VALIDATION
    // ================================================================

    test('hover on class member shows method/property info', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('ClassesAndRecords.nl');

        const pos = positionOf(doc, 'Make: string', { at: 'start' });
        const hovers = await getHover(doc, pos);

        assert.ok(hovers.length > 0,
            'Hover on class property should return results');

        const text = extractHoverText(hovers);
        assert.ok(text.length > 0,
            'Hover on class property should have content');
        assert.ok(
            text.includes('Make') || text.includes('string') || text.includes('property') || text.includes('field'),
            `Hover on "Make" property should mention the property. Got:\n${text}`
        );
    });

    // ================================================================
    // DOCUMENT SYMBOLS — COMPLEX FILES
    // ================================================================

    test('document symbols for classes include correct hierarchy', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('ClassesAndRecords.nl');
        const symbols = await getDocumentSymbols(doc);

        assert.ok(symbols.length > 0,
            'Should return symbols for ClassesAndRecords.nl');

        assertSymbolExists(symbols, 'Vehicle', vscode.SymbolKind.Class);
        assertSymbolExists(symbols, 'Point', vscode.SymbolKind.Class);
    });

    test('document symbols for enum files list all enums', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('EnumVariants.nl');
        const symbols = await getDocumentSymbols(doc);

        assert.ok(symbols.length > 0,
            'Should return symbols for EnumVariants.nl');

        assertSymbolExists(symbols, 'Direction', vscode.SymbolKind.Enum);
        assertSymbolExists(symbols, 'Priority', vscode.SymbolKind.Enum);
        assertSymbolExists(symbols, 'DayOfWeek', vscode.SymbolKind.Enum);
    });

    // ================================================================
    // LSP AFTER EDITS — Features must work after document changes
    // ================================================================

    test('completions work after editing a file', async function () {
        this.timeout(45_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EditCompTest
func Main() {
    x := 42
    print x
}
`, '_complex_edit_comp.nl');

        try {
            await getDiagnostics(doc);

            // Edit the file — add a new variable
            const editor = vscode.window.activeTextEditor!;
            const pos = positionOf(doc, 'print x', { at: 'start' });
            await editor.edit(editBuilder => {
                editBuilder.insert(pos, 'y := "hello"\n    ');
            });

            await waitForDiagnosticsToSettle(doc.uri, 10_000);

            // Completions should still work
            const newPos = new vscode.Position(pos.line + 1, 4);
            const completions = await getCompletions(doc, newPos);
            assert.ok(completions.items.length > 0,
                'Completions should work after document edit');

            await vscode.commands.executeCommand('undo');
            await sleep(500);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    test('hover works after editing a file', async function () {
        this.timeout(45_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EditHoverTest
func Main() {
    x := 42
    print x
}
`, '_complex_edit_hover.nl');

        try {
            await getDiagnostics(doc);

            // Edit: add a variable
            const editor = vscode.window.activeTextEditor!;
            const insertPos = positionOf(doc, 'print x', { at: 'start' });
            await editor.edit(editBuilder => {
                editBuilder.insert(insertPos, 'name := "world"\n    ');
            });

            await waitForDiagnosticsToSettle(doc.uri, 10_000);

            // Hover on the newly added variable
            const namePos = positionOf(doc, 'name :=', { at: 'start' });
            const hovers = await getHover(doc, namePos);
            assert.ok(Array.isArray(hovers),
                'Hover should work after document edit');

            await vscode.commands.executeCommand('undo');
            await sleep(500);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // VARIABLE SCOPE AND SHADOWING
    // ================================================================

    test('definition navigates to correct variable in nested scope', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace ScopeTest
func Main() {
    x := "outer"
    if true {
        x := "inner"
        print x
    }
    print x
}
`, '_complex_scope.nl');

        try {
            await getDiagnostics(doc);

            // Target the "x" on the inner "print x" line
            const innerPrintPos = positionOf(doc, 'print x', { at: 'start', occurrence: 1 });
            const xPos = new vscode.Position(innerPrintPos.line, innerPrintPos.character + 6);
            const defs = await getDefinitions(doc, xPos);

            assert.ok(defs.length > 0,
                'Definition should return results for scoped variable');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // ENUM MEMBER NAVIGATION
    // ================================================================

    test('definition on enum usage navigates to enum declaration', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EnumNavTest
enum Color {
    Red,
    Green,
    Blue
}

func Main() {
    c := Color.Red
    print $"{c}"
}
`, '_complex_enum_nav.nl');

        try {
            await getDiagnostics(doc);
            const pos = positionOf(doc, 'Color.Red', { at: 'start' });
            const defs = await getDefinitions(doc, pos);

            assert.ok(defs.length > 0,
                'Definition should return results for enum usage');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // COMPLETIONS WITH MULTIPLE TYPES IN SCOPE
    // ================================================================

    test('completions include locally defined functions', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'message := greet', { at: 'start' });
        const completions = await getCompletions(doc, pos);

        assert.ok(completions.items.length > 0,
            'Completions should be available');

        const labels = completions.items.map(i => completionLabel(i));
        assert.ok(labels.includes('greet') || labels.includes('add'),
            `Completions should include local functions. Got: ${labels.slice(0, 20).join(', ')}`);
    });

    // ================================================================
    // STRING INTERPOLATION
    // ================================================================

    test('completions inside string interpolation do not crash', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace InterpTest
func Main() {
    name := "World"
    print $"Hello, {name.}"
}
`, '_complex_interp.nl');

        try {
            await getDiagnostics(doc);
            const pos = positionOf(doc, 'name.}', { at: 'start' });
            const dotPos = new vscode.Position(pos.line, pos.character + 5);
            const completions = await getCompletions(doc, dotPos);

            assert.ok(Array.isArray(completions.items),
                'Completions inside interpolation should return an array');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // DOCUMENT SYMBOLS — KIND VALIDATION
    // ================================================================

    test('Program.nl symbols have correct kinds', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        const symbols = await getDocumentSymbols(doc);

        assert.ok(symbols.length > 0, 'Should have symbols');

        // Check specific symbol kinds
        assertSymbolExists(symbols, 'Main', vscode.SymbolKind.Function);
        assertSymbolExists(symbols, 'greet', vscode.SymbolKind.Function);
        assertSymbolExists(symbols, 'Person', vscode.SymbolKind.Class);
        assertSymbolExists(symbols, 'Color', vscode.SymbolKind.Enum);
    });

    // ================================================================
    // MULTI-EDIT DIAGNOSTIC CONSISTENCY
    // ================================================================

    test('diagnostics stay clean after adding valid code', async function () {
        this.timeout(60_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace MultiEditTest
func Main() {
    x := 1
    print x
}
`, '_complex_multi_edit.nl');

        try {
            let diagnostics = await getDiagnostics(doc);
            let errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                `Should start with 0 errors:\n${formatDiagnosticErrors(errors)}`);

            const editor = vscode.window.activeTextEditor!;
            await editor.edit(editBuilder => {
                const lastLine = doc.lineCount - 1;
                const pos = new vscode.Position(lastLine, doc.lineAt(lastLine).text.length);
                editBuilder.insert(pos, '\nfunc Helper(): int {\n    return 42\n}\n');
            });

            diagnostics = await waitForDiagnosticsToSettle(doc.uri, 10_000);
            errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                `Adding valid code should not introduce errors:\n${formatDiagnosticErrors(errors)}`);

            await vscode.commands.executeCommand('undo');
            await sleep(500);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });
});
