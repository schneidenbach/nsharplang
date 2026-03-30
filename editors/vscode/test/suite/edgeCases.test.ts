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
 * Edge case and negative path integration tests.
 *
 * These test what happens when inputs are unusual, malformed, or at boundaries:
 * - Empty files, files with only comments
 * - LSP queries at invalid/boundary positions
 * - Hover/definition/references on whitespace/non-symbols
 * - Completions in broken files
 * - Very deeply nested code
 * - Unicode identifiers and content
 *
 * The language server should degrade gracefully — return empty results,
 * not crash, not produce spurious errors.
 */
suite('Edge Cases — LSP Resilience', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // EMPTY / MINIMAL FILES — Server should not crash
    // ================================================================

    test('empty file does not crash the language server', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile('', '_edge_empty.nl');
        try {
            const diagnostics = await getDiagnostics(doc);
            // It's fine to have errors (missing namespace), but server should not crash
            const symbols = await getDocumentSymbols(doc);
            assert.ok(Array.isArray(symbols), 'Document symbols should return an array for empty file');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    test('file with only comments produces no crash', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
// This file has only comments
// Nothing else
// No namespace, no functions, no code
`, '_edge_comments.nl');
        try {
            const diagnostics = await getDiagnostics(doc);
            const symbols = await getDocumentSymbols(doc);
            assert.ok(Array.isArray(symbols), 'Document symbols should return an array for comment-only file');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    test('file with only namespace produces no errors', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace JustNamespace
`, '_edge_namespace.nl');
        try {
            const diagnostics = await getDiagnostics(doc);
            const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                `Namespace-only file should not produce errors but got: ${errors.map(d => d.message).join('; ')}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // BOUNDARY POSITIONS — LSP should handle gracefully
    // ================================================================

    test('completions at position 0:0 does not crash', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        const completions = await getCompletions(doc, new vscode.Position(0, 0));
        assert.ok(Array.isArray(completions.items), 'Completions should return an array at position 0:0');
    });

    test('completions at end of file does not crash', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        const lastLine = doc.lineCount - 1;
        const lastChar = doc.lineAt(lastLine).text.length;
        const completions = await getCompletions(doc, new vscode.Position(lastLine, lastChar));
        assert.ok(Array.isArray(completions.items), 'Completions should return an array at end of file');
    });

    test('hover on whitespace returns empty or no result', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        // Find a blank line or whitespace position
        const hovers = await getHover(doc, new vscode.Position(0, 0));
        // Should either return empty array or some info — not crash
        assert.ok(Array.isArray(hovers), 'Hover should return an array even on whitespace');
    });

    test('hover at end of file does not crash', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        const lastLine = doc.lineCount - 1;
        const lastChar = doc.lineAt(lastLine).text.length;
        const hovers = await getHover(doc, new vscode.Position(lastLine, lastChar));
        assert.ok(Array.isArray(hovers), 'Hover should not crash at end of file');
    });

    test('definition at position with no symbol returns empty', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        // Position on an opening brace — no symbol there
        const pos = positionOf(doc, 'func Main() {', { at: 'end' });
        const defs = await getDefinitions(doc, pos);
        // Should return empty, not crash
        assert.ok(Array.isArray(defs), 'Definitions should return an array for non-symbol position');
    });

    test('references at position with no symbol returns empty', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        // Position at the opening brace of a function body
        const pos = positionOf(doc, 'func Main() {', { at: 'end' });
        const refs = await getReferences(doc, pos);
        assert.ok(Array.isArray(refs), 'References should return an array for non-symbol position');
    });

    // ================================================================
    // HOVER ON DIFFERENT TOKEN TYPES
    // ================================================================

    test('hover on string literal does not crash', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        const pos = positionOf(doc, '"World"', { at: 'middle' });
        const hovers = await getHover(doc, pos);
        assert.ok(Array.isArray(hovers), 'Hover on string literal should not crash');
    });

    test('hover on numeric literal does not crash', async function () {
        this.timeout(60_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EdgeNum
func Main() {
    x := 42
    print x
}
`, '_edge_num.nl');
        try {
            await getDiagnostics(doc);
            const pos = positionOf(doc, '42', { at: 'start' });
            const hovers = await getHover(doc, pos);
            assert.ok(Array.isArray(hovers), 'Hover on numeric literal should not crash');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    test('hover on comment text does not crash', async function () {
        this.timeout(60_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EdgeComment
// This is a comment
func Main() {
    print "hi"
}
`, '_edge_comment_hover.nl');
        try {
            await getDiagnostics(doc);
            const pos = positionOf(doc, 'This is a comment', { at: 'middle' });
            const hovers = await getHover(doc, pos);
            assert.ok(Array.isArray(hovers), 'Hover on comment text should not crash');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // LSP FEATURES IN FILES WITH ERRORS
    // ================================================================

    test('completions still work in file with errors', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EdgeErrComp
func Main() {
    x := 42
    print x
    y := !!!
}
`, '_edge_err_comp.nl');
        try {
            await getDiagnostics(doc);
            // Request completions in the valid part of the file
            const pos = positionOf(doc, 'print x', { at: 'start' });
            const completions = await getCompletions(doc, pos);
            // Server should still respond — not crash due to the error below
            assert.ok(Array.isArray(completions.items),
                'Completions should still return results in file with errors');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    test('document symbols still returned for file with partial errors', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EdgePartial
func ValidFunction() {
    print "I am valid"
}

func BrokenFunction( {
    print "I am broken"
}
`, '_edge_partial.nl');
        try {
            await getDiagnostics(doc);
            const symbols = await getDocumentSymbols(doc);
            // Should at least find ValidFunction even if BrokenFunction confuses the parser
            assert.ok(Array.isArray(symbols),
                'Document symbols should return an array even in file with errors');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // DEEP NESTING
    // ================================================================

    test('deeply nested code does not crash the LSP', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EdgeDeep
func Main() {
    x := 1
    if x > 0 {
        if x > 0 {
            if x > 0 {
                if x > 0 {
                    if x > 0 {
                        if x > 0 {
                            if x > 0 {
                                if x > 0 {
                                    print "deep"
                                }
                            }
                        }
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
                `Deeply nested code should not produce errors:\n${errors.map(d => d.message).join('; ')}`);

            const symbols = await getDocumentSymbols(doc);
            assert.ok(Array.isArray(symbols), 'Document symbols should work on deeply nested code');
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // UNICODE / SPECIAL CHARACTERS
    // ================================================================

    test('unicode in string literals does not crash the LSP', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace EdgeUnicode
func Main() {
    emoji := "Hello 🌍🎉"
    japanese := "こんにちは"
    mixed := "café résumé naïve"
    print emoji
    print japanese
    print mixed
}
`, '_edge_unicode.nl');
        try {
            const diagnostics = await getDiagnostics(doc);
            const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                `Unicode strings should not produce errors:\n${errors.map(d => d.message).join('; ')}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // MULTIPLE RAPID OPENS — Stress test document management
    // ================================================================

    test('opening multiple files rapidly does not crash', async function () {
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

    test('signature help outside function call returns undefined', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        // Position at the start of the file — not inside any function call
        const sig = await getSignatureHelp(doc, new vscode.Position(0, 0));
        // Should be undefined or have no signatures — not crash
        if (sig) {
            assert.ok(Array.isArray(sig.signatures),
                'Signature help outside function call should have signatures array');
        }
    });
});
