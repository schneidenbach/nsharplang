import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getCompletions,
    getHover,
    getDefinitions,
    getDocumentSymbols,
    getDiagnostics,
    createTempNlFile,
    closeAllEditors,
    positionOf,
    timed,
    sleep,
    waitForDiagnosticsToSettle
} from './helpers';

/**
 * Performance baseline tests.
 *
 * These validate that LSP operations complete within reasonable time limits
 * and that the server handles stress scenarios without crashing.
 *
 * Timing thresholds are generous (designed for CI, not local dev) but
 * will catch severe regressions (e.g., 30-second completions).
 */
suite('Performance Baselines', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // RESPONSE TIME BASELINES
    // ================================================================

    test('completions respond within 5 seconds', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'message := greet', { at: 'start' });
        const { result, durationMs } = await timed(
            () => getCompletions(doc, pos),
            'completions'
        );

        assert.ok(result.items.length > 0, 'Should return completions');
        assert.ok(durationMs < 5000,
            `Completions took ${durationMs}ms — expected under 5000ms`);
    });

    test('hover responds within 3 seconds', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'func greet(', { at: 'start' });
        const hoverPos = new vscode.Position(pos.line, pos.character + 5);
        const { result, durationMs } = await timed(
            () => getHover(doc, hoverPos),
            'hover'
        );

        assert.ok(result.length > 0, 'Should return hover results');
        assert.ok(durationMs < 3000,
            `Hover took ${durationMs}ms — expected under 3000ms`);
    });

    test('definition responds within 3 seconds', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'greet("World")', { at: 'start' });
        const { result, durationMs } = await timed(
            () => getDefinitions(doc, pos),
            'definition'
        );

        assert.ok(result.length > 0, 'Should return definition results');
        assert.ok(durationMs < 3000,
            `Definition took ${durationMs}ms — expected under 3000ms`);
    });

    test('document symbols respond within 3 seconds', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const { result, durationMs } = await timed(
            () => getDocumentSymbols(doc),
            'document symbols'
        );

        assert.ok(result.length > 0, 'Should return document symbols');
        assert.ok(durationMs < 3000,
            `Document symbols took ${durationMs}ms — expected under 3000ms`);
    });

    // ================================================================
    // LARGE FILE HANDLING
    // ================================================================

    test('large file (200+ lines) opens and analyzes without crash', async function () {
        this.timeout(60_000);
        // Generate a large file with many functions and classes
        const lines: string[] = ['namespace LargeFileTest', ''];
        for (let i = 0; i < 50; i++) {
            lines.push(`func func_${i}(a: int, b: string): string {`);
            lines.push(`    result := $"a={a}, b={b}, i=${i}"`);
            lines.push(`    return result`);
            lines.push(`}`);
            lines.push('');
        }
        // Add some classes
        for (let i = 0; i < 10; i++) {
            lines.push(`class Class_${i} {`);
            lines.push(`    Value_${i}: int`);
            lines.push(`    Name_${i}: string`);
            lines.push(`    constructor(v: int, n: string) {`);
            lines.push(`        Value_${i} = v`);
            lines.push(`        Name_${i} = n`);
            lines.push(`    }`);
            lines.push(`    func GetInfo(): string {`);
            lines.push(`        return $"{Name_${i}}: {Value_${i}}"`);
            lines.push(`    }`);
            lines.push(`}`);
            lines.push('');
        }

        const code = lines.join('\n');
        const { doc, cleanup } = await createTempNlFile(code, '_perf_large.nl');

        try {
            const { result: diagnostics, durationMs } = await timed(
                () => getDiagnostics(doc),
                'large file diagnostics'
            );

            const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                `Large file should have 0 errors but got ${errors.length}`);
            assert.ok(durationMs < 30_000,
                `Large file analysis took ${durationMs}ms — expected under 30s`);

            // Symbols should also work
            const symbols = await getDocumentSymbols(doc);
            assert.ok(symbols.length >= 50,
                `Expected at least 50 symbols for large file, got ${symbols.length}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // RAPID EDITS — Server should handle sequential edits
    // ================================================================

    test('rapid sequential edits do not crash the server', async function () {
        this.timeout(60_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace RapidEditTest
func Main() {
    x := 1
    print x
}
`, '_perf_rapid.nl');

        try {
            await getDiagnostics(doc);

            const editor = vscode.window.activeTextEditor!;

            // Perform 5 rapid edits
            for (let i = 0; i < 5; i++) {
                await editor.edit(editBuilder => {
                    const lastLine = doc.lineCount - 1;
                    const pos = new vscode.Position(lastLine, doc.lineAt(lastLine).text.length);
                    editBuilder.insert(pos, `\nfunc edit_${i}(): int { return ${i} }\n`);
                });
                // Brief pause between edits (simulating fast typing)
                await sleep(200);
            }

            // Wait for everything to settle
            const diagnostics = await waitForDiagnosticsToSettle(doc.uri, 15_000);
            const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);

            assert.strictEqual(errors.length, 0,
                `Rapid edits should not produce errors:\n${errors.map(d => d.message).join('; ')}`);

            // Verify the server is still responsive
            const symbols = await getDocumentSymbols(doc);
            assert.ok(symbols.length >= 5,
                `Expected at least 5 symbols after rapid edits, got ${symbols.length}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // MEMBER COMPLETION RESPONSE TIME
    // ================================================================

    test('member completions (dot access) respond within 5 seconds', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'person.GetInfo', { at: 'start' });
        const dotPos = new vscode.Position(pos.line, pos.character + 7);
        const { result, durationMs } = await timed(
            () => getCompletions(doc, dotPos),
            'member completions'
        );

        assert.ok(result.items.length > 0, 'Should return member completions');
        assert.ok(durationMs < 5000,
            `Member completions took ${durationMs}ms — expected under 5000ms`);
    });
});
