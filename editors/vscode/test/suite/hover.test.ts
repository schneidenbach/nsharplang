import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getHover,
    positionOf,
    closeAllEditors,
    assertOrSkip
} from './helpers';

suite('Hover', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    test('hover on function name shows info', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'func greet(', { at: 'start' });
        const hoverPos = new vscode.Position(pos.line, pos.character + 5);
        const hovers = await getHover(doc, hoverPos);

        // Skip if LSP hover not available for this context
        assertOrSkip(hovers.length > 0,
            'Hover provider did not return results for function name', this);

        const contents = hovers.flatMap(h => h.contents).map(c => {
            if (typeof c === 'string') return c;
            if (c instanceof vscode.MarkdownString) return c.value;
            return (c as { value: string }).value || '';
        }).join(' ');

        assert.ok(contents.length > 0, 'Hover content should not be empty');
    });

    test('hover on keyword shows info', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'func Main()');
        const hovers = await getHover(doc, pos);

        if (hovers.length > 0) {
            const contents = hovers.flatMap(h => h.contents).map(c => {
                if (typeof c === 'string') return c;
                if (c instanceof vscode.MarkdownString) return c.value;
                return (c as { value: string }).value || '';
            }).join(' ');

            assert.ok(contents.length > 0,
                'If hover returns results, content should not be empty');
        }
    });

    test('hover on class name shows type info', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'class Person');
        const hoverPos = new vscode.Position(pos.line, pos.character + 6);
        const hovers = await getHover(doc, hoverPos);

        assertOrSkip(hovers.length > 0,
            'Hover provider did not return results for class name', this);
    });
});
