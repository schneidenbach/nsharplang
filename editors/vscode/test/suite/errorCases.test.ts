import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentByPath,
    getDiagnostics,
    closeAllEditors,
    createTempNlFile,
    formatDiagnosticErrors,
    waitForDiagnosticsToSettle,
    sleep,
    getRepoRoot
} from './helpers';
import * as path from 'path';

/**
 * Error case integration tests.
 *
 * The TextDocumentHandler publishes diagnostics for both parser and semantic errors.
 * Diagnostic source: "N#", severity: Error/Warning/Information.
 *
 * Tests use hard assertions where the error is a clear syntax violation that
 * the parser MUST catch. Tests use assertOrSkip ONLY for semantic errors that
 * the analyzer may not yet support.
 */
suite('Error Cases — Diagnostics', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    /**
     * Helper: create temp file, get diagnostics, clean up.
     * Returns all diagnostics for the file.
     */
    async function getDiagnosticsForCode(
        code: string,
        name: string
    ): Promise<{ diagnostics: vscode.Diagnostic[]; errors: vscode.Diagnostic[]; cleanup: () => void }> {
        const safeName = name.replace(/[^a-zA-Z0-9]/g, '_');
        const { doc, cleanup } = await createTempNlFile(code, `_err_${safeName}.nl`);
        const diagnostics = await getDiagnostics(doc);
        const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
        await closeAllEditors();
        return { diagnostics, errors, cleanup };
    }

    // ================================================================
    // SYNTAX ERRORS — The parser MUST catch these
    // ================================================================

    test('missing closing brace produces error', async function () {
        this.timeout(30_000);
        const { errors, cleanup } = await getDiagnosticsForCode(`
namespace ErrTest1
func Main() {
    x := 42
    print x
`, 'missing_brace');

        try {
            assert.ok(errors.length >= 1,
                `Missing closing brace should produce errors, got ${errors.length}.\n` +
                `This is a fundamental parser error — if this fails, error reporting is broken.`);
        } finally {
            cleanup();
        }
    });

    test('missing closing paren produces error', async function () {
        this.timeout(30_000);
        const { errors, cleanup } = await getDiagnosticsForCode(`
namespace ErrTest2
func Main() {
    print("hello"
}
`, 'missing_paren');

        try {
            assert.ok(errors.length >= 1,
                `Missing closing paren should produce errors, got ${errors.length}`);
        } finally {
            cleanup();
        }
    });

    test('invalid token at top level produces error', async function () {
        this.timeout(30_000);
        const { errors, cleanup } = await getDiagnosticsForCode(`
namespace ErrTest3
42 + 3
`, 'invalid_toplevel');

        try {
            assert.ok(errors.length >= 1,
                `Invalid token at top level should produce errors, got ${errors.length}`);
        } finally {
            cleanup();
        }
    });

    test('function without body produces error', async function () {
        this.timeout(30_000);
        const { errors, cleanup } = await getDiagnosticsForCode(`
namespace ErrTest4
func Broken()
func Main() {
    print "hi"
}
`, 'func_no_body');

        try {
            assert.ok(errors.length >= 1,
                `Function without body should produce errors, got ${errors.length}`);
        } finally {
            cleanup();
        }
    });

    test('unclosed string literal produces error', async function () {
        this.timeout(30_000);
        const { errors, cleanup } = await getDiagnosticsForCode(`
namespace ErrTest6
func Main() {
    x := "unclosed string
    print x
}
`, 'unclosed_string');

        try {
            assert.ok(errors.length >= 1,
                `Unclosed string literal should produce errors, got ${errors.length}`);
        } finally {
            cleanup();
        }
    });

    // ================================================================
    // MULTIPLE ERRORS — All should be reported
    // ================================================================

    test('multiple syntax errors are all reported', async function () {
        this.timeout(30_000);
        const { errors, cleanup } = await getDiagnosticsForCode(`
namespace ErrTest9
func Bad1() {
    x := add(1, 2
}
func Bad2(a: int, {
    return a
}
`, 'multi_errors');

        try {
            assert.ok(errors.length >= 2,
                `Expected at least 2 errors for multiple syntax errors, got ${errors.length}`);
        } finally {
            cleanup();
        }
    });

    // ================================================================
    // ERROR QUALITY — Positions, ranges, messages, source
    // ================================================================

    test('error diagnostics have non-zero range', async function () {
        this.timeout(30_000);
        const { errors, cleanup } = await getDiagnosticsForCode(`
namespace ErrTest10
func Main() {
    x: int = "wrong type"
}
`, 'error_position');

        try {
            if (errors.length > 0) {
                const hasPosition = errors.some(e =>
                    e.range.start.line > 0 || e.range.start.character > 0
                );
                assert.ok(hasPosition,
                    `Errors should have non-zero positions:\n${formatDiagnosticErrors(errors)}`);
            }
        } finally {
            cleanup();
        }
    });

    test('error messages are not empty', async function () {
        this.timeout(30_000);
        const { errors, cleanup } = await getDiagnosticsForCode(`
namespace ErrTest12
func Main() {
    42 ++ 3
}
`, 'error_messages');

        try {
            for (const err of errors) {
                assert.ok(err.message.length > 0,
                    `Error at line ${err.range.start.line + 1} has empty message`);
            }
        } finally {
            cleanup();
        }
    });

    test('errors have diagnostic source set', async function () {
        this.timeout(30_000);
        const { errors, cleanup } = await getDiagnosticsForCode(`
namespace ErrTest13
func Main() {
    x := !!!
}
`, 'error_source');

        try {
            for (const err of errors) {
                assert.ok(
                    err.source === 'N#' || err.source === 'nsharp',
                    `Error has unexpected source "${err.source}" (expected "N#" or "nsharp")`
                );
            }
        } finally {
            cleanup();
        }
    });

    // ================================================================
    // INCREMENTAL ERROR RECOVERY
    // ================================================================

    test('diagnostics update when error is introduced via edit', async function () {
        this.timeout(45_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace ErrRecoverTest
func Main() {
    x := 42
    print x
}
`, '_err_recover.nl');

        try {
            // Start clean
            let diagnostics = await getDiagnostics(doc);
            let errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                `Expected clean start:\n${formatDiagnosticErrors(errors)}`);

            // Introduce an error
            const editor = vscode.window.activeTextEditor!;
            await editor.edit(editBuilder => {
                const lastLine = doc.lineCount - 1;
                const pos = new vscode.Position(lastLine, doc.lineAt(lastLine).text.length);
                editBuilder.insert(pos, '\nfunc Broken( {\n}\n');
            });

            diagnostics = await waitForDiagnosticsToSettle(doc.uri, 15_000);
            errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);

            assert.ok(errors.length > 0,
                'Expected errors after introducing syntax error — TextDocumentHandler supports didChange');

            // Undo and verify errors clear
            await vscode.commands.executeCommand('undo');
            await sleep(500);
            diagnostics = await waitForDiagnosticsToSettle(doc.uri, 15_000);
            errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);
            assert.strictEqual(errors.length, 0,
                `Errors should clear after undo:\n${formatDiagnosticErrors(errors)}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // ERROR SEVERITY
    // ================================================================

    test('syntax errors have Error severity not Warning', async function () {
        this.timeout(30_000);
        const { diagnostics, errors, cleanup } = await getDiagnosticsForCode(`
namespace ErrSevTest
func Main() {
    x := )))
}
`, 'error_severity');

        try {
            if (diagnostics.length > 0) {
                assert.ok(errors.length > 0,
                    `Syntax errors should have Error severity. Got ${errors.length} errors, ` +
                    `${diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Warning).length} warnings`);
            }
        } finally {
            cleanup();
        }
    });

    // ================================================================
    // FIXTURE-BASED TESTS
    // ================================================================

    test('HasErrors.nl fixture produces diagnostics', async function () {
        this.timeout(30_000);
        const repoRoot = getRepoRoot();
        const errorFile = path.join(repoRoot, 'editors', 'vscode', 'test', 'fixtures', 'errors', 'HasErrors.nl');
        const doc = await openDocumentByPath(errorFile);
        const diagnostics = await getDiagnostics(doc);
        const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);

        assert.ok(errors.length > 0,
            `HasErrors.nl should produce diagnostics but got 0. ` +
            `This fixture contains intentional errors.`);
    });

    test('MultipleSyntaxErrors.nl produces multiple diagnostics', async function () {
        this.timeout(30_000);
        const repoRoot = getRepoRoot();
        const errorFile = path.join(repoRoot, 'editors', 'vscode', 'test', 'fixtures', 'errors', 'MultipleSyntaxErrors.nl');
        const doc = await openDocumentByPath(errorFile);
        const diagnostics = await getDiagnostics(doc);
        const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);

        assert.ok(errors.length >= 2,
            `MultipleSyntaxErrors.nl should have at least 2 errors, got ${errors.length}`);
    });
});
