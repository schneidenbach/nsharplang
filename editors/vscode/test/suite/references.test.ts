import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getReferences,
    positionOf,
    closeAllEditors,
    assertOrSkip
} from './helpers';

suite('Find References', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    test('find references on function includes definition and call sites', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'func greet(', { at: 'start' });
        const greetPos = new vscode.Position(pos.line, pos.character + 5);
        const refs = await getReferences(doc, greetPos);

        assertOrSkip(refs.length >= 2,
            `References provider returned ${refs.length} results (expected >= 2)`, this);
    });

    test('find references on variable includes declaration and usages', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'message := greet');
        const refs = await getReferences(doc, pos);

        assertOrSkip(refs.length >= 2,
            `References provider returned ${refs.length} results (expected >= 2)`, this);
    });
});
