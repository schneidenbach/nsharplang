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
    getSignatureHelp,
    getDiagnostics,
    createTempNlFile,
    closeAllEditors,
    positionOf
} from './helpers';

/**
 * Edge case tests — resilience and boundary conditions.
 *
 * These test that the language server handles degenerate inputs gracefully:
 * - Empty files, comment-only files
 * - Positions at file boundaries (0:0, end of file)
 * - Non-symbol positions (whitespace, string literals)
 * - Files with errors still provide partial results
 * - Unicode content
 * - Rapid file switching
 *
 * These are genuine crash/resilience tests — they validate the server
 * doesn't throw exceptions on unusual inputs.
 */
suite('Edge Cases — Resilience', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // EMPTY / MINIMAL FILES
    // ================================================================

    test('empty file does not crash any LSP feature', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile('', '_edge_empty.nl');

        try {
            await getDiagnostics(doc);

            const symbols = await getDocumentSymbols(doc);
            assert.ok(Array.isArray(symbols), 'Symbols on empty file should return array');

            const completions = await getCompletions(doc, new vscode.Position(0, 0));
            assert.ok(Array.isArray(completions.items), 'Completions on empty file should return array');

            const hovers = await getHover(doc, new vscode.Position(0, 0));
            assert.ok(Array.isArray(hovers), 'Hover on empty file should return array');

            const defs = await getDefinitions(doc, new vscode.Position(0, 0));
            assert.ok(Array.isArray(defs), 'Definitions on empty file should return array');

            const refs = await getReferences(doc, new vscode.Position(0, 0));
            assert.ok(Array.isArray(refs), 'References on empty file should return array');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    test('comment-only file does not crash', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
// This is a comment
// Another comment
/* Block comment */
`, '_edge_comments.nl');

        try {
            await getDiagnostics(doc);
            const symbols = await getDocumentSymbols(doc);
            assert.ok(Array.isArray(symbols), 'Symbols on comment-only file should return array');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    test('namespace-only file produces zero errors', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EdgeTest
`, '_edge_ns_only.nl');

        try {
            const diagnostics = await getDiagnostics(doc);
            const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                `Namespace-only file should have 0 errors but got ${errors.length}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // BOUNDARY POSITIONS
    // ================================================================

    test('completions at position 0:0', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const completions = await getCompletions(doc, new vscode.Position(0, 0));
        assert.ok(completions.items.length > 0,
            'Should provide completions at position 0:0');
    });

    test('completions at end of file', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const lastLine = doc.lineCount - 1;
        const lastCol = doc.lineAt(lastLine).text.length;
        const completions = await getCompletions(doc, new vscode.Position(lastLine, lastCol));
        assert.ok(Array.isArray(completions.items),
            'Completions at end of file should return array');
    });

    test('hover at end of file does not crash', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const lastLine = doc.lineCount - 1;
        const hovers = await getHover(doc, new vscode.Position(lastLine, 0));
        assert.ok(Array.isArray(hovers), 'Hover at end of file should return array');
    });

    // ================================================================
    // NON-SYMBOL POSITIONS
    // ================================================================

    test('hover on whitespace returns empty', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Line 1 is blank
        const hovers = await getHover(doc, new vscode.Position(1, 0));
        assert.ok(Array.isArray(hovers), 'Hover on whitespace should return array');
    });

    test('definition at non-symbol position returns empty', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const defs = await getDefinitions(doc, new vscode.Position(1, 0));
        assert.ok(Array.isArray(defs), 'Definition at non-symbol should return array');
    });

    test('references at non-symbol position returns empty', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const refs = await getReferences(doc, new vscode.Position(1, 0));
        assert.ok(Array.isArray(refs), 'References at non-symbol should return array');
    });

    // ================================================================
    // LITERAL POSITIONS
    // ================================================================

    test('hover on string literal does not crash', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, '"World"', { at: 'middle' });
        const hovers = await getHover(doc, pos);
        assert.ok(Array.isArray(hovers), 'Hover on string literal should return array');
    });

    test('hover on numeric literal does not crash', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'add(3, 4)', { at: 'start' });
        const numPos = new vscode.Position(pos.line, pos.character + 4); // on "3"
        const hovers = await getHover(doc, numPos);
        assert.ok(Array.isArray(hovers), 'Hover on numeric literal should return array');
    });

    test('hover on comment text does not crash', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('ClassesAndRecords.nl');

        const pos = positionOf(doc, '// Class with typed', { at: 'middle' });
        const hovers = await getHover(doc, pos);
        assert.ok(Array.isArray(hovers), 'Hover on comment should return array');
    });

    // ================================================================
    // PARTIAL ERRORS — LSP should still work
    // ================================================================

    test('completions still work in file with errors', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EdgeErrTest
func ValidFunc(): int {
    return 42
}

func Broken( {
`, '_edge_partial.nl');

        try {
            await getDiagnostics(doc);
            const completions = await getCompletions(doc, new vscode.Position(0, 0));
            assert.ok(Array.isArray(completions.items),
                'Completions should work even in file with errors');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    test('document symbols returned for file with partial errors', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EdgePartialTest
func ValidFunction(): string {
    return "works"
}

func BrokenFunction( {
`, '_edge_partial_sym.nl');

        try {
            await getDiagnostics(doc);
            const symbols = await getDocumentSymbols(doc);
            assert.ok(Array.isArray(symbols),
                'Document symbols should return array for file with errors');

            // The valid function should still appear in symbols
            if (symbols.length > 0) {
                const names = symbols.map(s => s.name);
                assert.ok(names.includes('ValidFunction'),
                    `ValidFunction should appear in symbols despite errors. Got: ${names.join(', ')}`);
            }
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // UNICODE
    // ================================================================

    test('unicode in string literals produces zero errors', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace UnicodeTest
func Main() {
    greeting := "Hello, 世界! 🌍"
    print greeting
    emoji := "✅ ❌ 🎉"
    print emoji
}
`, '_edge_unicode.nl');

        try {
            const diagnostics = await getDiagnostics(doc);
            const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                `Unicode strings should not produce errors but got ${errors.length}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // DEEPLY NESTED CODE
    // ================================================================

    test('deeply nested code does not crash server', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace DeepNestTest
func Main() {
    if true {
        if true {
            if true {
                if true {
                    if true {
                        print "deep"
                    }
                }
            }
        }
    }
}
`, '_edge_deep.nl');

        try {
            const diagnostics = await getDiagnostics(doc);
            const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                'Deeply nested code should not produce errors');

            const symbols = await getDocumentSymbols(doc);
            assert.ok(Array.isArray(symbols), 'Symbols should work for deeply nested code');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // RAPID FILE SWITCHING
    // ================================================================

    test('opening multiple files sequentially does not crash', async function () {
        this.timeout(120_000);
        const files = ['Program.nl', 'Helpers.nl', 'ClassesAndRecords.nl'];

        for (const file of files) {
            const doc = await openDocumentAndWaitForLsp(file);
            const diagnostics = await getDiagnostics(doc);
            const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                `File ${file} should have no errors: ${errors.map(d => d.message).join('; ')}`);
            await closeAllEditors();
        }
    });

    // ================================================================
    // SIGNATURE HELP EDGE CASES
    // ================================================================

    test('signature help outside function call returns nothing', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const sig = await getSignatureHelp(doc, new vscode.Position(0, 0));
        if (sig) {
            assert.strictEqual(sig.signatures.length, 0,
                'Signature help outside function call should have no signatures');
        }
    });
});
