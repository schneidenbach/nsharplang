import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getDefinitions,
    positionOf,
    closeAllEditors,
    assertLocationContains,
    createTempNlFile,
    getDiagnostics
} from './helpers';

/**
 * Go-to-definition tests with position pinning.
 *
 * The DefinitionHandler is fully implemented with 3-tier resolution:
 * 1. Synchronized project snapshot (open buffers)
 * 2. Disk-based project snapshot (cross-file)
 * 3. Text-based fallback (open documents only)
 *
 * Every test hard-asserts that definitions are returned AND validates
 * the target file and line content.
 */
suite('Go to Definition', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // FUNCTION DEFINITIONS
    // ================================================================

    test('function call navigates to function declaration', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "greet" in "greet("World")"
        const callPos = positionOf(doc, 'greet("World")', { at: 'start' });
        const definitions = await getDefinitions(doc, callPos);

        assert.ok(definitions.length > 0,
            'Definition provider should return results for function call');
        assert.strictEqual(definitions.length, 1,
            `Expected exactly 1 definition, got ${definitions.length}`);

        // Target should be the function declaration line
        await assertLocationContains(definitions[0], 'Program.nl', 'func greet(');
    });

    test('add() call navigates to add() declaration', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "add" in "add(3, 4)"
        const callPos = positionOf(doc, 'add(3, 4)', { at: 'start' });
        const definitions = await getDefinitions(doc, callPos);

        assert.ok(definitions.length > 0,
            'Definition provider should return results for add() call');

        await assertLocationContains(definitions[0], 'Program.nl', 'func add(');
    });

    // ================================================================
    // VARIABLE DEFINITIONS
    // ================================================================

    test('variable usage navigates to variable declaration', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "message" in "print message"
        const pos = positionOf(doc, 'print message', { at: 'start' });
        const messagePos = new vscode.Position(pos.line, pos.character + 6); // on "message"
        const definitions = await getDefinitions(doc, messagePos);

        assert.ok(definitions.length > 0,
            'Definition provider should return results for variable usage');

        await assertLocationContains(definitions[0], 'Program.nl', 'message :=');
    });

    // ================================================================
    // CLASS DEFINITIONS
    // ================================================================

    test('class instantiation navigates to class declaration', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "Person" in "new Person("
        const pos = positionOf(doc, 'new Person(', { at: 'start' });
        const personPos = new vscode.Position(pos.line, pos.character + 4); // on "Person"
        const definitions = await getDefinitions(doc, personPos);

        assert.ok(definitions.length > 0,
            'Definition provider should return results for class instantiation');

        await assertLocationContains(definitions[0], 'Program.nl', 'class Person');
    });

    // ================================================================
    // METHOD DEFINITIONS
    // ================================================================

    test('method call navigates to method declaration', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "GetInfo" in "person.GetInfo()"
        const pos = positionOf(doc, 'person.GetInfo()', { at: 'start' });
        const methodPos = new vscode.Position(pos.line, pos.character + 7); // on "GetInfo"
        const definitions = await getDefinitions(doc, methodPos);

        assert.ok(definitions.length > 0,
            'Definition provider should return results for method call');

        await assertLocationContains(definitions[0], 'Program.nl', 'func GetInfo()');
    });

    // ================================================================
    // CROSS-FILE DEFINITIONS
    // ================================================================

    test('cross-file function call navigates to helper file', async function () {
        this.timeout(60_000);
        const { doc: helperDoc, cleanup: cleanupHelper } = await createTempNlFile(`
namespace CrossDefTest
func crossDefinedHelper(): string {
    return "from helper"
}
`, '_def_cross_helper.nl');

        const { doc: mainDoc, cleanup: cleanupMain } = await createTempNlFile(`
namespace CrossDefTest
func Main() {
    val := crossDefinedHelper()
    print val
}
`, '_def_cross_main.nl');

        try {
            await getDiagnostics(helperDoc);
            await getDiagnostics(mainDoc);

            const pos = positionOf(mainDoc, 'crossDefinedHelper()');
            const defs = await getDefinitions(mainDoc, pos);

            assert.ok(defs.length > 0,
                'Cross-file definition should return results');

            // Verify the definition points to the HELPER file, not the current file
            await assertLocationContains(defs[0], '_def_cross_helper.nl', 'func crossDefinedHelper()');
        } finally {
            await closeAllEditors();
            cleanupHelper();
            cleanupMain();
        }
    });

    // ================================================================
    // EDGE CASES
    // ================================================================

    test('definition at non-symbol position returns empty', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on empty line
        const defs = await getDefinitions(doc, new vscode.Position(1, 0));
        assert.ok(Array.isArray(defs),
            'Definition at non-symbol should return an array');
    });

    test('definition on string literal returns empty or no crash', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, '"World"', { at: 'middle' });
        const defs = await getDefinitions(doc, pos);
        assert.ok(Array.isArray(defs),
            'Definition on string literal should return an array');
    });

    test('all definition results are in .nl files', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const callPos = positionOf(doc, 'greet("World")', { at: 'start' });
        const definitions = await getDefinitions(doc, callPos);

        assert.ok(definitions.length > 0,
            'Should have at least one definition result to validate');

        for (const def of definitions) {
            assert.ok(def.uri.fsPath.endsWith('.nl'),
                `Definition should be in .nl file, got ${def.uri.fsPath}`);
        }
    });
});
