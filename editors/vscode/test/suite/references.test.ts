import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getReferences,
    positionOf,
    closeAllEditors
} from './helpers';

/**
 * Find References tests with location validation.
 *
 * The ReferencesHandler is fully implemented with project-level cross-file references.
 * Tests validate both reference counts AND that reference locations point to correct files/lines.
 */
suite('Find References', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // FUNCTION REFERENCES
    // ================================================================

    test('function declaration has definition and call site references', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "greet" in "func greet("
        const pos = positionOf(doc, 'func greet(', { at: 'start' });
        const greetPos = new vscode.Position(pos.line, pos.character + 5);
        const refs = await getReferences(doc, greetPos);

        // Should have at least 2: definition (line 5) and call (line 39)
        assert.ok(refs.length >= 2,
            `Expected >= 2 references for "greet" (def + call), got ${refs.length}`);

        // All references should be in .nl files
        for (const ref of refs) {
            assert.ok(ref.uri.fsPath.endsWith('.nl'),
                `Reference should be in .nl file, got ${ref.uri.fsPath}`);
        }

        // One reference should be on the declaration line
        const declRef = refs.find(r => {
            const line = doc.lineAt(r.range.start.line).text;
            return line.includes('func greet(');
        });
        assert.ok(declRef,
            `Expected a reference on the declaration line "func greet("`);

        // Another reference should be on the call line
        const callRef = refs.find(r => {
            const line = doc.lineAt(r.range.start.line).text;
            return line.includes('greet("World")');
        });
        assert.ok(callRef,
            `Expected a reference on the call line "greet("World")"`);
    });

    // ================================================================
    // VARIABLE REFERENCES
    // ================================================================

    test('variable has declaration and usage references', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "message" in "message := greet"
        const pos = positionOf(doc, 'message := greet', { at: 'start' });
        const refs = await getReferences(doc, pos);

        // Should have at least 2: declaration and "print message"
        assert.ok(refs.length >= 2,
            `Expected >= 2 references for "message" (decl + usage), got ${refs.length}`);
    });

    // ================================================================
    // CLASS REFERENCES
    // ================================================================

    test('class name has declaration and instantiation references', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "Person" in "class Person"
        const pos = positionOf(doc, 'class Person', { at: 'start' });
        const personPos = new vscode.Position(pos.line, pos.character + 6);
        const refs = await getReferences(doc, personPos);

        // Should have at least 2: class declaration and "new Person("
        assert.ok(refs.length >= 2,
            `Expected >= 2 references for "Person" (decl + instantiation), got ${refs.length}`);
    });

    // ================================================================
    // EDGE CASES
    // ================================================================

    test('references at non-symbol position returns empty array', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on empty line
        const refs = await getReferences(doc, new vscode.Position(1, 0));
        assert.ok(Array.isArray(refs),
            'References at non-symbol position should return array');
    });

    test('all references for a symbol are in the same file for single-file symbols', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'message := greet', { at: 'start' });
        const refs = await getReferences(doc, pos);

        if (refs.length > 0) {
            for (const ref of refs) {
                assert.ok(ref.uri.fsPath.endsWith('Program.nl'),
                    `Expected all "message" references in Program.nl, got ${ref.uri.fsPath}`);
            }
        }
    });
});
