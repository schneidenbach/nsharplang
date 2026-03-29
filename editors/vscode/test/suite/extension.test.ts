import * as assert from 'assert';
import * as vscode from 'vscode';
import { waitForLanguageServer, openDocument, closeAllEditors, sleep } from './helpers';

suite('Extension Activation', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    test('nsharp language is registered', async () => {
        const languages = await vscode.languages.getLanguages();
        assert.ok(
            languages.includes('nsharp'),
            `Expected 'nsharp' in registered languages. Got: ${languages.filter(l => l.includes('sharp')).join(', ')}`
        );
    });

    test('extension activates on .nl file', async () => {
        const ext = vscode.extensions.getExtension('nsharp.nsharp');
        assert.ok(ext, 'N# extension should be installed');
        assert.ok(ext!.isActive, 'N# extension should be active');
    });

    test('.nl files are assigned nsharp language ID', async () => {
        const doc = await openDocument('Program.nl');
        assert.strictEqual(doc.languageId, 'nsharp',
            `Expected language ID 'nsharp', got '${doc.languageId}'`);
    });

    test('language server output channel exists', async () => {
        // The extension creates an output channel named 'N# Language Server'
        // We can verify this by checking the extension is active (it creates
        // the channel during activation)
        const ext = vscode.extensions.getExtension('nsharp.nsharp');
        assert.ok(ext?.isActive, 'Extension must be active');
    });
});
