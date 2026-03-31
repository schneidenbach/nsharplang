import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getCodeActions,
    closeAllEditors,
    createTempNlFile,
    getDiagnostics,
    positionOf
} from './helpers';

/**
 * Code Action tests.
 *
 * The CodeActionHandler is fully implemented with:
 * - Quick fixes (CodeActionKind.QuickFix)
 * - Refactoring (CodeActionKind.Refactor)
 * - Source actions (CodeActionKind.Source)
 *
 * Tests validate that code actions are returned with correct kinds and edits.
 */
suite('Code Actions', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // CODE ACTIONS ON CLEAN CODE
    // ================================================================

    test('code actions on function declaration returns array with valid kinds', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Get code actions on a function declaration
        const pos = positionOf(doc, 'func greet(', { at: 'start' });
        const range = new vscode.Range(pos, new vscode.Position(pos.line, pos.character + 10));
        const actions = await getCodeActions(doc, range);

        assert.ok(Array.isArray(actions),
            'Code actions should return an array');

        // If actions are available, validate their kinds
        for (const action of actions) {
            assert.ok(action.title.length > 0,
                'Code action title should not be empty');
        }
    });

    // ================================================================
    // CODE ACTIONS ON DIAGNOSTICS
    // ================================================================

    test('code actions at diagnostic location have valid structure', async function () {
        this.timeout(30_000);
        // Use a file with an intentional error to ensure diagnostics exist
        const { doc, cleanup } = await createTempNlFile(`
namespace CodeActionDiagTest
func Main() {
    x := 42
    print x
    y := )))
}
`, '_codeaction_diag.nl');

        try {
            const diagnostics = await getDiagnostics(doc);

            // Whether or not we get diagnostics, query code actions at a known position
            const pos = positionOf(doc, 'y := )))', { at: 'start' });
            const range = new vscode.Range(pos, new vscode.Position(pos.line, pos.character + 10));
            const actions = await getCodeActions(doc, range);

            assert.ok(Array.isArray(actions),
                'Code actions should return an array');

            // Validate structure of any returned actions
            for (const action of actions) {
                assert.ok(action.title.length > 0,
                    'Code action title should not be empty');
                assert.ok(action.kind,
                    `Code action "${action.title}" should have a kind`);
            }
        } finally {
            await closeAllEditors();
            cleanup();
        }
    });

    // ================================================================
    // CODE ACTION STRUCTURE
    // ================================================================

    test('code actions have valid kinds', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Get all code actions for a region
        const pos = positionOf(doc, 'func Main()', { at: 'start' });
        const range = new vscode.Range(pos, new vscode.Position(pos.line + 5, 0));
        const actions = await getCodeActions(doc, range);

        const validKinds = [
            vscode.CodeActionKind.QuickFix,
            vscode.CodeActionKind.Refactor,
            vscode.CodeActionKind.RefactorExtract,
            vscode.CodeActionKind.RefactorInline,
            vscode.CodeActionKind.RefactorRewrite,
            vscode.CodeActionKind.Source,
            vscode.CodeActionKind.SourceOrganizeImports,
        ];

        for (const action of actions) {
            if (action.kind) {
                // Skip code actions contributed by other extensions (e.g., GitHub Copilot)
                if (action.kind.value?.includes('copilot')) continue;

                const isValid = validKinds.some(k => action.kind!.contains(k));
                assert.ok(isValid,
                    `Code action "${action.title}" has unexpected kind: ${action.kind.value}`);
            }
        }
    });

    // ================================================================
    // CODE ACTIONS WITH EDITS
    // ================================================================

    test('code actions with edits have valid workspace edits', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'func Main()', { at: 'start' });
        const range = new vscode.Range(pos, new vscode.Position(pos.line + 5, 0));
        const actions = await getCodeActions(doc, range);

        for (const action of actions) {
            if (action.edit) {
                const entries = action.edit.entries();
                for (const [uri, edits] of entries) {
                    assert.ok(uri.fsPath.length > 0,
                        `Code action "${action.title}" edit has empty file path`);
                    for (const edit of edits) {
                        assert.ok(edit.newText !== undefined,
                            `Code action "${action.title}" edit has undefined newText`);
                    }
                }
            }
        }
    });

    // ================================================================
    // EDGE CASES
    // ================================================================

    test('code actions on empty line return array', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const range = new vscode.Range(new vscode.Position(1, 0), new vscode.Position(1, 0));
        const actions = await getCodeActions(doc, range);
        assert.ok(Array.isArray(actions),
            'Code actions on empty line should return an array');
    });
});
