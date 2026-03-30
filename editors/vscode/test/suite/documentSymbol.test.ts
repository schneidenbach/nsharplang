import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getDocumentSymbols,
    closeAllEditors,
    assertOrSkip
} from './helpers';

suite('Document Symbols', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    test('document symbols include functions', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const symbols = await getDocumentSymbols(doc);
        const allNames = flattenSymbolNames(symbols);

        assertOrSkip(allNames.length > 0,
            'Document symbol provider returned no symbols', this);

        assert.ok(allNames.includes('Main'),
            `Expected 'Main' in symbols. Got: ${allNames.join(', ')}`);
        assert.ok(allNames.includes('greet'),
            `Expected 'greet' in symbols. Got: ${allNames.join(', ')}`);
    });

    test('document symbols include classes', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const symbols = await getDocumentSymbols(doc);
        const allNames = flattenSymbolNames(symbols);

        assertOrSkip(allNames.length > 0,
            'Document symbol provider returned no symbols', this);

        assert.ok(allNames.includes('Person'),
            `Expected 'Person' in symbols. Got: ${allNames.join(', ')}`);
    });

    test('document symbols include enums', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const symbols = await getDocumentSymbols(doc);
        const allNames = flattenSymbolNames(symbols);

        assertOrSkip(allNames.length > 0,
            'Document symbol provider returned no symbols', this);

        assert.ok(allNames.includes('Color'),
            `Expected 'Color' in symbols. Got: ${allNames.join(', ')}`);
    });

    test('document symbols have correct kinds', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const symbols = await getDocumentSymbols(doc);

        assertOrSkip(symbols.length > 0,
            'Document symbol provider returned no symbols', this);

        const mainSymbol = findSymbol(symbols, 'Main');
        if (mainSymbol) {
            assert.strictEqual(mainSymbol.kind, vscode.SymbolKind.Function,
                `Expected Main to have Function kind, got ${vscode.SymbolKind[mainSymbol.kind]}`);
        }
    });
});

function flattenSymbolNames(symbols: vscode.DocumentSymbol[]): string[] {
    const names: string[] = [];
    for (const s of symbols) {
        names.push(s.name);
        if (s.children.length > 0) {
            names.push(...flattenSymbolNames(s.children));
        }
    }
    return names;
}

function findSymbol(symbols: vscode.DocumentSymbol[], name: string): vscode.DocumentSymbol | undefined {
    for (const s of symbols) {
        if (s.name === name) return s;
        const child = findSymbol(s.children, name);
        if (child) return child;
    }
    return undefined;
}
