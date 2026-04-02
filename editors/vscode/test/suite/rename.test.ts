import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    executeRename,
    positionOf,
    closeAllEditors,
    createTempNlFile,
    getDiagnostics
} from './helpers';

/**
 * Rename Symbol tests.
 *
 * The RenameHandler is fully implemented:
 * - Returns WorkspaceEdit with changes per file
 * - Cross-file rename support
 * - PrepareProvider validates symbol is renamable before showing dialog
 *
 * Tests validate that rename produces correct edits at correct locations.
 */
suite('Rename Symbol', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // FUNCTION RENAME
    // ================================================================

    test('rename function updates all references', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace RenameTest
func oldName(): string {
    return "hello"
}

func Main() {
    x := oldName()
    print x
}
`, '_rename_func.nl');

        try {
            await getDiagnostics(doc);

            // Position on "oldName" at the declaration
            const pos = positionOf(doc, 'func oldName(', { at: 'start' });
            const namePos = new vscode.Position(pos.line, pos.character + 5); // on "oldName"
            const edit = await executeRename(doc, namePos, 'newName');

            assert.ok(edit, 'Rename should return a WorkspaceEdit');

            // Check that the edit has changes
            const allEntries = edit!.entries();
            assert.ok(allEntries.length > 0,
                'WorkspaceEdit should have at least one file with changes');

            // Validate each edit replaces the old name with the new name
            let totalEdits = 0;
            for (const [, edits] of allEntries) {
                for (const textEdit of edits) {
                    assert.strictEqual(textEdit.newText, 'newName',
                        `Edit newText should be "newName", got "${textEdit.newText}"`);
                    // Edit range should span exactly the old name length (7 = "oldName".length)
                    const rangeLength = textEdit.range.end.character - textEdit.range.start.character;
                    assert.strictEqual(rangeLength, 7,
                        `Edit range should span 7 chars ("oldName"), got ${rangeLength}`);
                }
                totalEdits += edits.length;
            }
            // Should rename both the declaration and the call site
            assert.ok(totalEdits >= 2,
                `Expected at least 2 edits (decl + call), got ${totalEdits}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // VARIABLE RENAME
    // ================================================================

    test('rename variable updates declaration and usages', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace RenameVarTest
func Main() {
    counter := 0
    counter = counter + 1
    print counter
}
`, '_rename_var.nl');

        try {
            await getDiagnostics(doc);

            // Position on "counter" at declaration
            const pos = positionOf(doc, 'counter := 0', { at: 'start' });
            const edit = await executeRename(doc, pos, 'total');

            assert.ok(edit, 'Rename should return a WorkspaceEdit');

            let totalEdits = 0;
            for (const [, edits] of edit!.entries()) {
                totalEdits += edits.length;
            }
            // "counter" appears 3+ times: declaration, assignment, print
            assert.ok(totalEdits >= 3,
                `Expected at least 3 edits for "counter" (decl + 2 usages), got ${totalEdits}`);
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // RENAME EDIT CONTENT
    // ================================================================

    test('rename edit text matches new name', async function () {
        this.timeout(30_000);
        const { doc, cleanup } = await createTempNlFile(`
namespace RenameContentTest
func myFunc(): int {
    return 42
}

func Main() {
    val := myFunc()
    print val
}
`, '_rename_content.nl');

        try {
            await getDiagnostics(doc);

            const pos = positionOf(doc, 'func myFunc(', { at: 'start' });
            const namePos = new vscode.Position(pos.line, pos.character + 5);
            const edit = await executeRename(doc, namePos, 'renamedFunc');

            assert.ok(edit, 'Rename should return a WorkspaceEdit');

            // Every text edit should have "renamedFunc" as the new text
            for (const [, edits] of edit!.entries()) {
                for (const textEdit of edits) {
                    assert.strictEqual(textEdit.newText, 'renamedFunc',
                        `Edit new text should be "renamedFunc", got "${textEdit.newText}"`);
                }
            }
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // EDGE CASES
    // ================================================================

    test('rename at whitespace returns undefined', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on empty line — server returns null, VS Code may throw "No result"
        try {
            const edit = await executeRename(doc, new vscode.Position(1, 0), 'whatever');
            // Rename on non-symbol should return undefined or empty edit
            if (edit) {
                const entries = edit.entries();
                assert.strictEqual(entries.length, 0,
                    'Rename at whitespace should produce no edits');
            }
        } catch (e: any) {
            // VS Code throws "No result" (no PrepareProvider) or "can't be renamed" (PrepareProvider returns null)
            const msg = e.message ?? '';
            assert.ok(msg.includes('No result') || msg.includes("can't be renamed"),
                `Unexpected error: ${msg}`);
        }
    });

    test('rename on string literal returns undefined or empty', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Inside a string literal — server returns null, VS Code may throw "No result"
        const pos = positionOf(doc, '"World"', { at: 'middle' });
        try {
            const edit = await executeRename(doc, pos, 'whatever');
            if (edit) {
                const entries = edit.entries();
                assert.strictEqual(entries.length, 0,
                    'Rename on string literal should produce no edits');
            }
        } catch (e: any) {
            const msg = e.message ?? '';
            assert.ok(msg.includes('No result') || msg.includes("can't be renamed"),
                `Unexpected error: ${msg}`);
        }
    });
});
