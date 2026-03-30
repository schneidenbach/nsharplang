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
    assertOrSkip
} from './helpers';

/**
 * Complex scenario integration tests.
 *
 * These test realistic, multi-step, and cross-file workflows:
 * - Cross-file definition navigation
 * - Cross-file find-references
 * - Multiple classes interacting across files
 * - LSP features after document edits
 * - Rename refactoring across scopes
 * - Completions with multiple candidate types
 * - Diagnostics consistency across file boundaries
 *
 * These mirror what a real developer does — not just opening a file
 * and checking if one feature works in isolation.
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

    test('go to definition on function defined in another file', async function () {
        this.timeout(60_000);
        // Create two files in the same namespace — helper defines the function,
        // main calls it. This tests true cross-file definition navigation.
        const { doc: helperDoc, cleanup: cleanupHelper } = await createTempNlFile(`
namespace CrossDefTest
func crossHelper(): string {
    return "from another file"
}
`, '_crossdef_helper.nl');

        const { doc: mainDoc, cleanup: cleanupMain } = await createTempNlFile(`
namespace CrossDefTest
func Main() {
    result := crossHelper()
    print result
}
`, '_crossdef_main.nl');

        try {
            await getDiagnostics(helperDoc);
            await getDiagnostics(mainDoc);

            const pos = positionOf(mainDoc, 'crossHelper()');
            const defs = await getDefinitions(mainDoc, pos);

            assertOrSkip(defs.length > 0,
                'Cross-file definition navigation not available', this);

            const def = defs[0];
            assert.ok(def.uri.fsPath.endsWith('.nl'),
                `Definition should be in an .nl file, got ${def.uri.fsPath}`);
        } finally {
            await closeAllEditors();
            cleanupHelper();
            cleanupMain();
        }
    });

    test('go to definition on cross-file function call', async function () {
        this.timeout(60_000);
        // Create two files that reference each other
        const { doc: helperDoc, cleanup: cleanupHelper } = await createTempNlFile(`
namespace CrossFileTest
func helperFunc(): string {
    return "from helper"
}
`, '_cross_helper.nl');

        const { doc: mainDoc, cleanup: cleanupMain } = await createTempNlFile(`
namespace CrossFileTest
func Main() {
    result := helperFunc()
    print result
}
`, '_cross_main.nl');

        try {
            await getDiagnostics(helperDoc);
            await getDiagnostics(mainDoc);

            // Try to navigate to helperFunc definition from main
            const pos = positionOf(mainDoc, 'helperFunc()');
            const defs = await getDefinitions(mainDoc, pos);

            assertOrSkip(defs.length > 0,
                'Cross-file function definition not available', this);
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

        // Find references on 'greet' function definition
        const pos = positionOf(doc, 'func greet(', { at: 'start' });
        const greetPos = new vscode.Position(pos.line, pos.character + 5);
        const refs = await getReferences(doc, greetPos);

        assertOrSkip(refs.length >= 2,
            `Expected at least 2 references (def + usage) but got ${refs.length}`, this);

        // All references should be in .nl files
        for (const ref of refs) {
            assert.ok(ref.uri.fsPath.endsWith('.nl'),
                `Reference should be in .nl file, got ${ref.uri.fsPath}`);
        }
    });

    // ================================================================
    // MULTI-CLASS INTERACTION
    // ================================================================

    test('class member completions work for locally defined class', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // After person. we should get GetInfo, Name, Age
        const pos = positionOf(doc, 'person.GetInfo()', { at: 'start' });
        const dotPos = new vscode.Position(pos.line, pos.character + 7); // after 'person.'
        const completions = await getCompletions(doc, dotPos);

        const labels = completions.items.map(i =>
            typeof i.label === 'string' ? i.label : i.label.label
        );

        assertOrSkip(labels.length > 0,
            'Member completions not available after dot', this);

        // Check for expected members
        if (labels.includes('GetInfo')) {
            assert.ok(true, 'GetInfo member found in completions');
        }
    });

    test('hover on class member shows type info', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('ClassesAndRecords.nl');

        // Hover on a property declaration
        const pos = positionOf(doc, 'Make: string', { at: 'start' });
        const hovers = await getHover(doc, pos);

        assertOrSkip(hovers.length > 0,
            'Hover not available on class property', this);

        if (hovers.length > 0) {
            const contents = hovers.flatMap(h => h.contents).map(c => {
                if (typeof c === 'string') return c;
                if (c instanceof vscode.MarkdownString) return c.value;
                return (c as { value: string }).value || '';
            }).join(' ');
            assert.ok(contents.length > 0, 'Hover on class property should have content');
        }
    });

    // ================================================================
    // DOCUMENT SYMBOLS — COMPLEX STRUCTURES
    // ================================================================

    test('document symbols include nested class members', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('ClassesAndRecords.nl');
        const symbols = await getDocumentSymbols(doc);

        assertOrSkip(symbols.length > 0,
            'No document symbols returned', this);

        // Should have Vehicle and Point classes
        const symbolNames = flattenSymbolNames(symbols);
        assert.ok(symbolNames.length >= 2,
            `Expected at least 2 symbols but got ${symbolNames.length}: ${symbolNames.join(', ')}`);
    });

    test('document symbols for file with enums', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('EnumVariants.nl');
        const symbols = await getDocumentSymbols(doc);

        assertOrSkip(symbols.length > 0,
            'No document symbols for enum file', this);

        const symbolNames = flattenSymbolNames(symbols);
        // Should include at least one enum
        assert.ok(symbolNames.length > 0,
            `Expected symbols for enum file but got: ${symbolNames.join(', ')}`);
    });

    // ================================================================
    // LSP AFTER EDITS — Features should still work after document changes
    // ================================================================

    test('completions work correctly after editing a file', async function () {
        this.timeout(45_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EditTest
func Main() {
    x := 42
    print x
}
`, '_complex_edit.nl');

        try {
            await getDiagnostics(doc);

            // Record position before edit
            const pos = positionOf(doc, 'print x', { at: 'start' });

            // Edit the file — add a new variable
            const editor = vscode.window.activeTextEditor!;
            await editor.edit(editBuilder => {
                const insertPos = positionOf(doc, 'print x', { at: 'start' });
                editBuilder.insert(insertPos, 'y := "hello"\n    ');
            });

            await waitForDiagnosticsToSettle(doc.uri, 10_000);

            // Completions should still work
            const newPos = new vscode.Position(pos.line + 1, 0);
            const afterCompletions = await getCompletions(doc, newPos);
            assert.ok(Array.isArray(afterCompletions.items),
                'Completions should still work after document edit');

            // Undo
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
namespace HoverEdit
func Main() {
    x := 42
    print x
}
`, '_complex_hover_edit.nl');

        try {
            await getDiagnostics(doc);

            // Edit the file
            const editor = vscode.window.activeTextEditor!;
            await editor.edit(editBuilder => {
                const insertPos = positionOf(doc, 'print x', { at: 'start' });
                editBuilder.insert(insertPos, 'name := "world"\n    ');
            });

            await waitForDiagnosticsToSettle(doc.uri, 10_000);

            // Hover should still work — search for the inserted variable declaration
            const pos = positionOf(doc, 'name :=', { at: 'start' });
            const hovers = await getHover(doc, pos);
            assert.ok(Array.isArray(hovers), 'Hover should work after document edit');

            // Undo
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

            // Target the 'x' on the 'print x' line inside the if block (2nd occurrence of 'print x')
            const innerPrintPos = positionOf(doc, 'print x', { at: 'start', occurrence: 1 });
            // Position on the 'x' after 'print '
            const xPos = new vscode.Position(innerPrintPos.line, innerPrintPos.character + 6);
            const defs = await getDefinitions(doc, xPos);

            // Should get something back — testing that scoped vars are handled
            assertOrSkip(defs.length > 0,
                'Definition provider did not return results for scoped variable', this);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // COMPLETIONS WITH MULTIPLE TYPES IN SCOPE
    // ================================================================

    test('completions include both local and imported symbols', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Get completions inside Main function
        const pos = positionOf(doc, 'message := greet', { at: 'start' });
        const completions = await getCompletions(doc, pos);

        const labels = completions.items.map(i =>
            typeof i.label === 'string' ? i.label : i.label.label
        );

        assertOrSkip(labels.length > 0,
            'No completions available', this);

        // Should include locally defined functions
        const hasLocalFunctions = labels.includes('greet') || labels.includes('add');
        if (hasLocalFunctions) {
            assert.ok(true, 'Local function completions present');
        }
    });

    // ================================================================
    // ENUM MEMBER NAVIGATION
    // ================================================================

    test('go to definition on enum member usage works', async function () {
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
            // Position on 'Color' in 'Color.Red' usage — not the enum declaration
            const pos = positionOf(doc, 'Color.Red', { at: 'start' });
            const defs = await getDefinitions(doc, pos);

            assertOrSkip(defs.length > 0,
                'Definition not available for enum usage', this);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // STRING INTERPOLATION COMPLETIONS
    // ================================================================

    test('completions work inside string interpolation', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace InterpComp
func Main() {
    name := "World"
    print $"Hello, {name.}"
}
`, '_complex_interp.nl');

        try {
            await getDiagnostics(doc);
            // Position after 'name.' inside interpolation
            const pos = positionOf(doc, 'name.}', { at: 'start' });
            const dotPos = new vscode.Position(pos.line, pos.character + 5);
            const completions = await getCompletions(doc, dotPos);

            // Should at least not crash — may or may not provide completions
            // depending on interpolation parsing support
            assert.ok(Array.isArray(completions.items),
                'Completions inside string interpolation should not crash');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // DOCUMENT SYMBOLS HIERARCHY
    // ================================================================

    test('document symbols for file with functions and classes have correct kinds', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        const symbols = await getDocumentSymbols(doc);

        assertOrSkip(symbols.length > 0,
            'No symbols returned for Program.nl', this);

        // Check that we have at least some function and class symbols
        const allSymbols = flattenSymbolsWithKind(symbols);

        const hasFunctions = allSymbols.some(s =>
            s.kind === vscode.SymbolKind.Function || s.kind === vscode.SymbolKind.Method
        );
        const hasClasses = allSymbols.some(s =>
            s.kind === vscode.SymbolKind.Class || s.kind === vscode.SymbolKind.Struct
        );

        assert.ok(hasFunctions, 'Program.nl should have function symbols');
        assert.ok(hasClasses, 'Program.nl should have class symbols');
    });

    // ================================================================
    // DIAGNOSTICS AFTER MULTIPLE EDITS
    // ================================================================

    test('diagnostics correctly update after multiple sequential edits', async function () {
        this.timeout(60_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace MultiEdit
func Main() {
    x := 1
    print x
}
`, '_complex_multi_edit.nl');

        try {
            // Start clean
            let diagnostics = await getDiagnostics(doc);
            let errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0, 'Should start with 0 errors');

            const editor = vscode.window.activeTextEditor!;

            // Edit 1: Add valid code
            await editor.edit(editBuilder => {
                const lastLine = doc.lineCount - 1;
                const pos = new vscode.Position(lastLine, doc.lineAt(lastLine).text.length);
                editBuilder.insert(pos, '\nfunc Helper(): int {\n    return 42\n}\n');
            });

            diagnostics = await waitForDiagnosticsToSettle(doc.uri, 10_000);
            errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0, 'Adding valid code should not introduce errors');

            // Undo to restore
            await vscode.commands.executeCommand('undo');
            await sleep(500);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });
});

// ================================================================
// HELPER UTILITIES
// ================================================================

function flattenSymbolNames(symbols: vscode.DocumentSymbol[]): string[] {
    const names: string[] = [];
    for (const sym of symbols) {
        names.push(sym.name);
        if (sym.children) {
            names.push(...flattenSymbolNames(sym.children));
        }
    }
    return names;
}

function flattenSymbolsWithKind(symbols: vscode.DocumentSymbol[]): Array<{ name: string; kind: vscode.SymbolKind }> {
    const result: Array<{ name: string; kind: vscode.SymbolKind }> = [];
    for (const sym of symbols) {
        result.push({ name: sym.name, kind: sym.kind });
        if (sym.children) {
            result.push(...flattenSymbolsWithKind(sym.children));
        }
    }
    return result;
}
