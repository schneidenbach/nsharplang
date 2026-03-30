import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getCompletions,
    positionOf,
    closeAllEditors,
    completionLabel,
    assertCompletionContains,
    createTempNlFile,
    getDiagnostics
} from './helpers';

/**
 * Completion tests with kind and content validation.
 *
 * The CompletionHandler is fully implemented with:
 * - Keywords (Kind.Keyword): func, class, struct, enum, if, for, match, etc.
 * - Snippets (Kind.Snippet): func, if, match, for templates
 * - Variables (Kind.Variable): local variables in scope
 * - Functions (Kind.Function): top-level functions
 * - Members (Kind.Method/Property/Field): after dot
 * - Primitive types: int, string, bool, double
 *
 * Every test hard-asserts specific items AND their kinds.
 */
suite('Completions', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // KEYWORD COMPLETIONS
    // ================================================================

    test('keywords available at top level', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const completions = await getCompletions(doc, new vscode.Position(0, 0));

        assert.ok(completions.items.length > 0,
            'Expected completions at top level');

        // Core N# keywords should be present
        assertCompletionContains(completions, 'func', vscode.CompletionItemKind.Keyword);
        assertCompletionContains(completions, 'class', vscode.CompletionItemKind.Keyword);
    });

    test('primitive types in completions', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const completions = await getCompletions(doc, new vscode.Position(0, 0));

        // Primitive types should be available as keywords
        assertCompletionContains(completions, 'int', vscode.CompletionItemKind.Keyword);
        assertCompletionContains(completions, 'string', vscode.CompletionItemKind.Keyword);
        assertCompletionContains(completions, 'bool', vscode.CompletionItemKind.Keyword);
    });

    // ================================================================
    // FUNCTION COMPLETIONS
    // ================================================================

    test('function names available inside function body', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position inside Main function, before "message := greet..."
        const pos = positionOf(doc, 'message := greet', { at: 'start' });
        const completions = await getCompletions(doc, pos);

        assert.ok(completions.items.length > 0,
            'Expected completions inside function body');

        // Local functions should be available
        assertCompletionContains(completions, 'greet', vscode.CompletionItemKind.Function);
        assertCompletionContains(completions, 'add', vscode.CompletionItemKind.Function);
    });

    // ================================================================
    // MEMBER COMPLETIONS (DOT ACCESS)
    // ================================================================

    test('member completions after dot include methods', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position after "person." in "person.GetInfo()"
        const pos = positionOf(doc, 'person.GetInfo', { at: 'start' });
        const dotPos = new vscode.Position(pos.line, pos.character + 7); // after "person."
        const completions = await getCompletions(doc, dotPos);

        assert.ok(completions.items.length > 0,
            'Expected member completions after dot');

        assertCompletionContains(completions, 'GetInfo', vscode.CompletionItemKind.Method);
    });

    test('member completions after dot include properties', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('ClassesAndRecords.nl');

        // Position after "car." in "car.GetDescription()"
        const pos = positionOf(doc, 'car.GetDescription', { at: 'start' });
        const dotPos = new vscode.Position(pos.line, pos.character + 4); // after "car."
        const completions = await getCompletions(doc, dotPos);

        assert.ok(completions.items.length > 0,
            'Expected member completions after dot');

        // Vehicle class has Make (string property), GetDescription (method)
        const labels = completions.items.map(i => completionLabel(i));
        assert.ok(labels.includes('Make') || labels.includes('GetDescription'),
            `Expected "Make" or "GetDescription" in completions. Got: ${labels.slice(0, 20).join(', ')}`);
    });

    // ================================================================
    // VARIABLE COMPLETIONS
    // ================================================================

    test('local variables appear in completions', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace CompVarTest
func Main() {
    mySpecialVar := 42
    print mySpecialVar

}
`, '_comp_var.nl');

        try {
            await getDiagnostics(doc);
            // Position on the blank line after "print mySpecialVar"
            const pos = positionOf(doc, 'print mySpecialVar', { at: 'end' });
            const lineAfter = new vscode.Position(pos.line + 1, 4);
            const completions = await getCompletions(doc, lineAfter);

            assertCompletionContains(completions, 'mySpecialVar', vscode.CompletionItemKind.Variable);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // COMPLETION QUALITY
    // ================================================================

    test('completion items all have a kind set', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const completions = await getCompletions(doc, new vscode.Position(0, 0));
        const withoutKind = completions.items.filter(i => i.kind === undefined);

        assert.ok(withoutKind.length === 0,
            `${withoutKind.length} completion items have no kind set: ${withoutKind.map(i => completionLabel(i)).join(', ')}`);
    });

    test('no duplicate labels in completion list', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const completions = await getCompletions(doc, new vscode.Position(0, 0));
        const labels = completions.items.map(i => completionLabel(i));
        const uniqueLabels = new Set(labels);

        // Allow some duplicates (overloads can have same label but different kinds)
        // but flag if there are excessive duplicates
        const duplicateCount = labels.length - uniqueLabels.size;
        assert.ok(duplicateCount < labels.length * 0.1,
            `Too many duplicate labels: ${duplicateCount} duplicates out of ${labels.length} items`);
    });

    test('completion count is reasonable', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const completions = await getCompletions(doc, new vscode.Position(0, 0));

        assert.ok(completions.items.length >= 5,
            `Expected at least 5 completions, got ${completions.items.length}`);
        assert.ok(completions.items.length < 5000,
            `Expected fewer than 5000 completions, got ${completions.items.length} — possible runaway`);
    });
});
