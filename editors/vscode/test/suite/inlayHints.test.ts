import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getInlayHints,
    closeAllEditors,
    createTempNlFile,
    getDiagnostics,
    positionOf
} from './helpers';

/**
 * Inlay Hint tests.
 *
 * The InlayHintHandler is fully implemented:
 * - Shows inferred type annotations after variable names
 * - Label format: ": typeName" (colon + space + type)
 * - Kind: InlayHintKind.Type
 * - Only for inferred declarations (not explicitly typed)
 * - Position: immediately after variable name
 */
suite('Inlay Hints', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // INFERRED TYPE HINTS
    // ================================================================

    test('inferred int variable shows type hint', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace InlayTest
func Main() {
    x := 42
    print x
}
`, '_inlay_int.nl');

        try {
            await getDiagnostics(doc);

            const fullRange = new vscode.Range(
                new vscode.Position(0, 0),
                new vscode.Position(doc.lineCount, 0)
            );
            const hints = await getInlayHints(doc, fullRange);

            assert.ok(hints.length > 0,
                'Expected at least one inlay hint for inferred variable');

            // Find the hint for "x"
            const xLine = positionOf(doc, 'x := 42').line;
            const xHint = hints.find(h => h.position.line === xLine);
            assert.ok(xHint,
                `Expected inlay hint on line with "x := 42" (line ${xLine})`);

            // Label should contain ": int" — validate both the colon prefix and the type
            const label = typeof xHint!.label === 'string'
                ? xHint!.label
                : (xHint!.label as vscode.InlayHintLabelPart[]).map(p => p.value).join('');
            assert.ok(label.includes(':'),
                `Inlay hint label should contain ":" for type annotation. Got: "${label}"`);
            assert.ok(label.toLowerCase().includes('int'),
                `Inlay hint for "x := 42" should contain "int". Got: "${label}"`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    test('inferred string variable shows type hint', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace InlayStrTest
func Main() {
    name := "hello"
    print name
}
`, '_inlay_str.nl');

        try {
            await getDiagnostics(doc);

            const fullRange = new vscode.Range(
                new vscode.Position(0, 0),
                new vscode.Position(doc.lineCount, 0)
            );
            const hints = await getInlayHints(doc, fullRange);

            assert.ok(hints.length > 0,
                'Expected at least one inlay hint for inferred string variable');

            const nameLine = positionOf(doc, 'name := "hello"').line;
            const nameHint = hints.find(h => h.position.line === nameLine);
            assert.ok(nameHint,
                `Expected inlay hint on line with "name := "hello"" (line ${nameLine})`);

            const label = typeof nameHint!.label === 'string'
                ? nameHint!.label
                : (nameHint!.label as vscode.InlayHintLabelPart[]).map(p => p.value).join('');
            assert.ok(label.includes('string') || label.includes('String'),
                `Inlay hint for string variable should contain "string". Got: "${label}"`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // EXPLICITLY TYPED — NO HINTS
    // ================================================================

    test('explicitly typed variable has no inlay hint', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace InlayExplicitTest
func Main() {
    x: int = 42
    print x
}
`, '_inlay_explicit.nl');

        try {
            await getDiagnostics(doc);

            const fullRange = new vscode.Range(
                new vscode.Position(0, 0),
                new vscode.Position(doc.lineCount, 0)
            );
            const hints = await getInlayHints(doc, fullRange);

            // Should not have a hint on the explicitly typed line
            const xLine = positionOf(doc, 'x: int = 42').line;
            const xHint = hints.find(h => h.position.line === xLine);
            assert.ok(!xHint,
                `Explicitly typed variable should NOT have an inlay hint, but found one on line ${xLine}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // MULTIPLE HINTS
    // ================================================================

    test('multiple inferred variables get multiple hints', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace InlayMultiTest
func Main() {
    a := 1
    b := "hello"
    c := true
    print $"{a} {b} {c}"
}
`, '_inlay_multi.nl');

        try {
            await getDiagnostics(doc);

            const fullRange = new vscode.Range(
                new vscode.Position(0, 0),
                new vscode.Position(doc.lineCount, 0)
            );
            const hints = await getInlayHints(doc, fullRange);

            assert.ok(hints.length >= 3,
                `Expected at least 3 inlay hints for 3 inferred variables, got ${hints.length}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // HINT KIND
    // ================================================================

    test('inlay hints have Type kind', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace InlayKindTest
func Main() {
    x := 42
    print x
}
`, '_inlay_kind.nl');

        try {
            await getDiagnostics(doc);

            const fullRange = new vscode.Range(
                new vscode.Position(0, 0),
                new vscode.Position(doc.lineCount, 0)
            );
            const hints = await getInlayHints(doc, fullRange);

            assert.ok(hints.length > 0,
                'Expected at least one inlay hint to validate kind');

            for (const hint of hints) {
                assert.strictEqual(hint.kind, vscode.InlayHintKind.Type,
                    `Inlay hint at line ${hint.position.line} should have Type kind, got ${hint.kind}`);
            }
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // EDGE CASES
    // ================================================================

    test('no inlay hints for empty file', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace InlayEmptyTest
`, '_inlay_empty.nl');

        try {
            await getDiagnostics(doc);

            const fullRange = new vscode.Range(
                new vscode.Position(0, 0),
                new vscode.Position(doc.lineCount, 0)
            );
            const hints = await getInlayHints(doc, fullRange);
            assert.strictEqual(hints.length, 0,
                `Expected 0 inlay hints for file with no variables, got ${hints.length}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    test('inlay hints on fixture file Program.nl', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const fullRange = new vscode.Range(
            new vscode.Position(0, 0),
            new vscode.Position(doc.lineCount, 0)
        );
        const hints = await getInlayHints(doc, fullRange);

        // Program.nl has several inferred variables: message, result, numbers, person
        assert.ok(hints.length >= 3,
            `Expected at least 3 inlay hints for Program.nl inferred variables, got ${hints.length}`);

        // All hints should have labels starting with ":"
        for (const hint of hints) {
            const label = typeof hint.label === 'string'
                ? hint.label
                : (hint.label as vscode.InlayHintLabelPart[]).map(p => p.value).join('');
            assert.ok(label.includes(':'),
                `Inlay hint label should contain ":" for type annotation. Got: "${label}"`);
        }
    });
});
