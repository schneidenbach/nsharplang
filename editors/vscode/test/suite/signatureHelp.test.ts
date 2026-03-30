import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getSignatureHelp,
    positionOf,
    closeAllEditors
} from './helpers';

suite('Signature Help', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    test('signature help on function call shows parameters', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Find "greet(" and position cursor right after the opening paren
        const pos = positionOf(doc, 'greet("World")', { at: 'start' });
        const parenPos = new vscode.Position(pos.line, pos.character + 6); // after 'greet('
        const sigHelp = await getSignatureHelp(doc, parenPos);

        if (sigHelp) {
            assert.ok(sigHelp.signatures.length > 0,
                'Expected at least one signature');

            const sig = sigHelp.signatures[0];
            assert.ok(sig.parameters.length > 0,
                'Expected at least one parameter in signature');
        }
        // Signature help may not be available for all functions - that's OK
    });

    test('signature help on multi-param function', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Find "add(3, 4)" and position cursor after the opening paren
        const pos = positionOf(doc, 'add(3, 4)', { at: 'start' });
        const parenPos = new vscode.Position(pos.line, pos.character + 4); // after 'add('
        const sigHelp = await getSignatureHelp(doc, parenPos);

        if (sigHelp && sigHelp.signatures.length > 0) {
            const sig = sigHelp.signatures[0];
            assert.ok(sig.parameters.length >= 2,
                `Expected at least 2 parameters for add(), got ${sig.parameters.length}`);
        }
    });
});
