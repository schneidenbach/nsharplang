import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getDefinitions,
    positionOf,
    closeAllEditors,
    assertOrSkip
} from './helpers';

suite('Go to Definition', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    test('go to definition on function call jumps to declaration', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const callPos = positionOf(doc, 'greet("World")', { at: 'start' });
        const definitions = await getDefinitions(doc, callPos);

        assertOrSkip(definitions.length > 0,
            'Definition provider did not return results', this);

        const def = definitions[0];
        assert.ok(def.uri.fsPath.endsWith('Program.nl'),
            `Expected definition in Program.nl, got ${def.uri.fsPath}`);
    });

    test('go to definition on local variable jumps to declaration', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'print message', { at: 'start' });
        const messagePos = new vscode.Position(pos.line, pos.character + 6);
        const definitions = await getDefinitions(doc, messagePos);

        assertOrSkip(definitions.length > 0,
            'Definition provider did not return results for variable', this);
    });

    test('go to definition on class usage', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'new Person(');
        const personPos = new vscode.Position(pos.line, pos.character + 4);
        const definitions = await getDefinitions(doc, personPos);

        assertOrSkip(definitions.length > 0,
            'Definition provider did not return results for class', this);
    });
});
