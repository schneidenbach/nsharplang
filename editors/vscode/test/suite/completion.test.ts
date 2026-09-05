import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer, openDocumentAndWaitForLsp, getCompletions, positionOf, closeAllEditors,
    completionLabel, assertCompletionContains, assertCompletionExcludes, createTempNlFile, getDiagnostics
} from './helpers';

/**
 * Keywords, primitive types and in-scope variables and functions at an identifier position; the
 * receiver's members after a dot. Every test hard-asserts specific items AND their kinds.
 */
suite('Completions', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // --- KEYWORDS AND PRIMITIVE TYPES ---

    test('keywords available at top level', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const completions = await getCompletions(doc, new vscode.Position(0, 0));
        assert.ok(completions.items.length > 0, 'Expected completions at top level');
        assertCompletionContains(completions, 'func', vscode.CompletionItemKind.Keyword);
        assertCompletionContains(completions, 'class', vscode.CompletionItemKind.Keyword);
    });

    test('primitive types in completions', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const completions = await getCompletions(doc, new vscode.Position(0, 0));
        assertCompletionContains(completions, 'int', vscode.CompletionItemKind.Keyword);
        assertCompletionContains(completions, 'string', vscode.CompletionItemKind.Keyword);
        assertCompletionContains(completions, 'bool', vscode.CompletionItemKind.Keyword);
    });

    // --- FUNCTIONS ---

    test('function names available inside function body', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const completions = await getCompletions(doc, positionOf(doc, 'message := greet', { at: 'start' }));
        assert.ok(completions.items.length > 0, 'Expected completions inside function body');
        assertCompletionContains(completions, 'greet', vscode.CompletionItemKind.Function);
        assertCompletionContains(completions, 'add', vscode.CompletionItemKind.Function);
    });

    // --- MEMBER COMPLETIONS (DOT ACCESS) ---

    test('trailing dot offers the receiver members, not scope identifiers', async function () {
        this.timeout(30_000);
        // Vehicle is declared in ClassesAndRecords.nl: a CROSS-FILE receiver with a trailing dot,
        // the shape defect D3 answered with the scope and the keyword list.
        const { doc, cleanup } = await createTempNlFile(`
namespace SimpleTest
func CompMemberTest() {
    vehicle := new Vehicle("Ford", "Focus", 2020)
    tc := vehicle.
    name := "Spencer"
    upper := name.
}
`, '_comp_member.nl');

        try {
            await getDiagnostics(doc);
            const completions = await getCompletions(doc, positionOf(doc, 'tc := vehicle.', { at: 'end' }));

            assertCompletionContains(completions, 'Make', vscode.CompletionItemKind.Property);
            assertCompletionContains(completions, 'GetDescription', vscode.CompletionItemKind.Method);
            assertCompletionExcludes(completions, 'vehicle');
            assertCompletionExcludes(completions, 'func');

            const labels = completions.items.map(i => completionLabel(i));
            assert.strictEqual(labels.length, new Set(labels).size,
                `Duplicate member labels: ${labels.join(', ')}`);
            assert.ok(!labels.some(l => l.startsWith('get_') || l.startsWith('set_')),
                `Property accessors leaked into the member list: ${labels.join(', ')}`);

            // THE SAME CHECK ON A BCL RECEIVER, WHICH IS WHERE THE OVERLOADS ARE. `string` reflects
            // 105 methods under 39 names — `Split` eleven, `IndexOf` ten — and each one used to be
            // its own row wearing the same label. The May headless suite has had a duplicate-label
            // check since, but nothing in the product gate ever ran it, which is why this survived.
            const bcl = await getCompletions(doc, positionOf(doc, 'upper := name.', { at: 'end' }));
            assertCompletionContains(bcl, 'Split', vscode.CompletionItemKind.Method);
            assertCompletionContains(bcl, 'Length', vscode.CompletionItemKind.Property);
            const bclLabels = bcl.items.map(i => completionLabel(i));
            assert.strictEqual(bclLabels.length, new Set(bclLabels).size,
                `Duplicate BCL member labels: ${bclLabels.join(', ')}`);
            const split = bcl.items.find(i => completionLabel(i) === 'Split');
            assert.ok(split && /\(\+\d+ overloads?\)$/.exec(String(split.detail ?? '')) !== null,
                `Expected Split to carry its overload count, got: ${String(split?.detail)}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // --- VARIABLES ---

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
            // The blank line after "print mySpecialVar".
            const pos = positionOf(doc, 'print mySpecialVar', { at: 'end' });
            const completions = await getCompletions(doc, new vscode.Position(pos.line + 1, 4));
            assertCompletionContains(completions, 'mySpecialVar', vscode.CompletionItemKind.Variable);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // --- COMPLETION QUALITY ---

    test('completion items all have a kind set', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const completions = await getCompletions(doc, new vscode.Position(0, 0));
        const withoutKind = completions.items.filter(i => i.kind === undefined);
        assert.ok(withoutKind.length === 0,
            `${withoutKind.length} completion items have no kind set: ${withoutKind.map(i => completionLabel(i)).join(', ')}`);
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
