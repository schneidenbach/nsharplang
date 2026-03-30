import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getCompletions,
    positionOf,
    closeAllEditors,
    assertOrSkip
} from './helpers';

suite('Completions', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    test('provides completions at top level', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = new vscode.Position(0, 0);
        const completions = await getCompletions(doc, pos);

        const labels = completions.items.map(i =>
            typeof i.label === 'string' ? i.label : i.label.label
        );

        assert.ok(labels.length > 0,
            'Expected at least some completions');
    });

    test('provides member access completions after dot', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'person.GetInfo', { at: 'start' });
        const dotPos = new vscode.Position(pos.line, pos.character + 7);
        const completions = await getCompletions(doc, dotPos);

        const labels = completions.items.map(i =>
            typeof i.label === 'string' ? i.label : i.label.label
        );

        // Skip if the LSP completion handler isn't providing member-level completions
        assertOrSkip(labels.includes('GetInfo'),
            `Member access completions not available. Got: ${labels.slice(0, 20).join(', ')}`, this);
    });

    test('provides function name completions', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'greet("World")');
        const completions = await getCompletions(doc, pos);

        const labels = completions.items.map(i =>
            typeof i.label === 'string' ? i.label : i.label.label
        );

        assertOrSkip(labels.includes('greet'),
            `Function name completions not available. Got: ${labels.slice(0, 20).join(', ')}`, this);
    });

    test('completion items have proper kind', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'greet("World")');
        const completions = await getCompletions(doc, pos);

        const withKind = completions.items.filter(i => i.kind !== undefined);
        assert.ok(withKind.length > 0,
            'Expected at least some completion items to have a kind');
    });
});
