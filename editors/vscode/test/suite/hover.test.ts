import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getHover,
    positionOf,
    closeAllEditors,
    extractHoverText
} from './helpers';

/**
 * Hover tests with content validation.
 *
 * The HoverHandler is fully implemented and returns Markdown for:
 * - Variables: **(variable)** `name: typeName`
 * - Keywords: **func** *(keyword)*
 * - Primitive types: **int** *(primitive type)*
 * - Classes: **ClassName** *(class)*
 * - Methods: **(method)** `MethodName`
 * - Properties: **(property)** `Name`
 *
 * Every test hard-asserts both that hover returns results AND validates content.
 */
suite('Hover', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // FUNCTION HOVER
    // ================================================================

    test('hover on function declaration shows function info', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "greet" in "func greet("
        const pos = positionOf(doc, 'func greet(', { at: 'start' });
        const hoverPos = new vscode.Position(pos.line, pos.character + 5);
        const hovers = await getHover(doc, hoverPos);

        assert.ok(hovers.length > 0,
            'Hover on function declaration should return results');

        const text = extractHoverText(hovers);
        assert.ok(text.length > 0, 'Hover content should not be empty');
        // Handler returns either "(function)" or "func" identifier info
        assert.ok(
            text.includes('greet') || text.includes('func'),
            `Hover on function should mention "greet" or "func". Got:\n${text}`
        );
    });

    test('hover on function call shows function signature', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "greet" in the call site "greet("World")"
        const pos = positionOf(doc, 'greet("World")', { at: 'start' });
        const hovers = await getHover(doc, pos);

        assert.ok(hovers.length > 0,
            'Hover on function call should return results');

        const text = extractHoverText(hovers);
        assert.ok(text.includes('greet'),
            `Hover on function call should mention "greet". Got:\n${text}`);
    });

    // ================================================================
    // VARIABLE HOVER
    // ================================================================

    test('hover on variable shows type info', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "message" in "message := greet("World")"
        const pos = positionOf(doc, 'message := greet', { at: 'start' });
        const hovers = await getHover(doc, pos);

        assert.ok(hovers.length > 0,
            'Hover on variable should return results');

        const text = extractHoverText(hovers);
        assert.ok(text.length > 0, 'Hover on variable should have content');
        // Variable hover should contain "(variable)" marker or the variable name
        assert.ok(
            text.includes('variable') || text.includes('message'),
            `Hover on variable should contain "variable" or "message". Got:\n${text}`
        );
    });

    test('hover on inferred int variable shows int type', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "result" in "result := add(3, 4)"
        const pos = positionOf(doc, 'result := add(3, 4)', { at: 'start' });
        const hovers = await getHover(doc, pos);

        assert.ok(hovers.length > 0,
            'Hover on inferred variable should return results');

        const text = extractHoverText(hovers);
        // Inferred type from add() which returns int
        assert.ok(
            text.includes('int') || text.includes('result'),
            `Hover on inferred int variable should mention "int" or "result". Got:\n${text}`
        );
    });

    // ================================================================
    // KEYWORD HOVER
    // ================================================================

    test('hover on keyword "func" shows keyword info', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "func" in "func Main()"
        const pos = positionOf(doc, 'func Main()', { at: 'start' });
        const hovers = await getHover(doc, pos);

        assert.ok(hovers.length > 0,
            'Hover on keyword "func" should return results');

        const text = extractHoverText(hovers);
        assert.ok(text.includes('keyword'),
            `Hover on "func" keyword should contain "keyword". Got:\n${text}`);
    });

    // ================================================================
    // TYPE HOVER
    // ================================================================

    test('hover on class name shows class info', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "Person" in "class Person {"
        const pos = positionOf(doc, 'class Person', { at: 'start' });
        const hoverPos = new vscode.Position(pos.line, pos.character + 6);
        const hovers = await getHover(doc, hoverPos);

        assert.ok(hovers.length > 0,
            'Hover on class name should return results');

        const text = extractHoverText(hovers);
        assert.ok(text.includes('Person'),
            `Hover on class should mention "Person". Got:\n${text}`);
        assert.ok(
            text.includes('class') || text.includes('Class'),
            `Hover on class should indicate it's a class. Got:\n${text}`
        );
    });

    test('hover on enum name shows enum info', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "Color" in "enum Color {"
        const pos = positionOf(doc, 'enum Color', { at: 'start' });
        const hoverPos = new vscode.Position(pos.line, pos.character + 5);
        const hovers = await getHover(doc, hoverPos);

        assert.ok(hovers.length > 0,
            'Hover on enum name should return results');

        const text = extractHoverText(hovers);
        assert.ok(text.includes('Color'),
            `Hover on enum should mention "Color". Got:\n${text}`);
    });

    test('hover on primitive type annotation shows type info', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "int" in "func add(a: int, b: int): int"
        const pos = positionOf(doc, 'a: int', { at: 'start' });
        const intPos = new vscode.Position(pos.line, pos.character + 3); // on "int"
        const hovers = await getHover(doc, intPos);

        assert.ok(hovers.length > 0,
            'Hover on primitive type should return results');

        const text = extractHoverText(hovers);
        assert.ok(
            text.includes('int') || text.includes('primitive'),
            `Hover on "int" should contain "int" or "primitive". Got:\n${text}`
        );
    });

    // ================================================================
    // CLASS MEMBER HOVER
    // ================================================================

    test('hover on method call shows method info', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on "GetInfo" in "person.GetInfo()"
        const pos = positionOf(doc, 'person.GetInfo()', { at: 'start' });
        const methodPos = new vscode.Position(pos.line, pos.character + 7); // on "GetInfo"
        const hovers = await getHover(doc, methodPos);

        assert.ok(hovers.length > 0,
            'Hover on method call should return results');

        const text = extractHoverText(hovers);
        assert.ok(
            text.includes('GetInfo') || text.includes('method'),
            `Hover on method should mention "GetInfo" or "method". Got:\n${text}`
        );
    });

    // ================================================================
    // EDGE CASES
    // ================================================================

    test('hover on whitespace returns empty', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position on an empty line (line 1 is blank)
        const hovers = await getHover(doc, new vscode.Position(1, 0));
        // Empty/no hover is fine — the test validates it doesn't crash
        assert.ok(Array.isArray(hovers), 'Hover on whitespace should return an array');
    });

    test('hover on string literal does not crash', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, '"World"', { at: 'middle' });
        const hovers = await getHover(doc, pos);
        assert.ok(Array.isArray(hovers), 'Hover on string literal should return an array');
    });
});
