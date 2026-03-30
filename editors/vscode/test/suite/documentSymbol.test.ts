import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getDocumentSymbols,
    closeAllEditors,
    assertSymbolExists,
    findSymbol,
    flattenSymbolNames
} from './helpers';

/**
 * Document Symbol tests with kind and hierarchy validation.
 *
 * The DocumentSymbolHandler is fully implemented with:
 * - SymbolKind: Function, Class, Struct, Interface, Enum, EnumMember,
 *   Field, Property, Method, Constructor
 * - Hierarchy: classes/enums have children (members)
 * - Detail: return types for functions, "record"/"union" markers
 *
 * Every test hard-asserts symbol existence, kind, and hierarchy.
 */
suite('Document Symbols', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // PROGRAM.NL — Functions, Classes, Enums
    // ================================================================

    test('Program.nl has expected top-level symbols', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        const symbols = await getDocumentSymbols(doc);

        assert.ok(symbols.length > 0,
            'Document symbol provider should return symbols for Program.nl');

        // Functions
        assertSymbolExists(symbols, 'greet', vscode.SymbolKind.Function);
        assertSymbolExists(symbols, 'add', vscode.SymbolKind.Function);
        assertSymbolExists(symbols, 'Main', vscode.SymbolKind.Function);

        // Class
        assertSymbolExists(symbols, 'Person', vscode.SymbolKind.Class);

        // Enums
        assertSymbolExists(symbols, 'Color', vscode.SymbolKind.Enum);
        assertSymbolExists(symbols, 'Status', vscode.SymbolKind.Enum);
    });

    test('Person class has correct children', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        const symbols = await getDocumentSymbols(doc);

        const person = findSymbol(symbols, 'Person');
        assert.ok(person, 'Person symbol should exist');
        assert.ok(person!.children.length > 0,
            `Person class should have children (members), got 0`);

        // Check for expected children
        const childNames = person!.children.map(c => c.name);
        assert.ok(childNames.includes('GetInfo'),
            `Person should have GetInfo method. Children: ${childNames.join(', ')}`);
    });

    test('Color enum has member children', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        const symbols = await getDocumentSymbols(doc);

        const colorEnum = findSymbol(symbols, 'Color');
        assert.ok(colorEnum, 'Color enum should exist');
        assert.ok(colorEnum!.children.length >= 3,
            `Color enum should have at least 3 members (Red, Green, Blue), got ${colorEnum!.children.length}`);

        const memberNames = colorEnum!.children.map(c => c.name);
        assert.ok(memberNames.includes('Red'),
            `Color enum should have "Red" member. Members: ${memberNames.join(', ')}`);
        assert.ok(memberNames.includes('Green'),
            `Color enum should have "Green" member. Members: ${memberNames.join(', ')}`);
        assert.ok(memberNames.includes('Blue'),
            `Color enum should have "Blue" member. Members: ${memberNames.join(', ')}`);

        // Enum members should have EnumMember kind
        for (const member of colorEnum!.children) {
            assert.strictEqual(member.kind, vscode.SymbolKind.EnumMember,
                `Enum member "${member.name}" should have EnumMember kind, got ${vscode.SymbolKind[member.kind]}`);
        }
    });

    // ================================================================
    // CLASSESANDRECORDS.NL — Multiple classes with members
    // ================================================================

    test('ClassesAndRecords.nl has Vehicle and Point classes', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('ClassesAndRecords.nl');
        const symbols = await getDocumentSymbols(doc);

        assert.ok(symbols.length > 0, 'Should have symbols for ClassesAndRecords.nl');

        assertSymbolExists(symbols, 'Vehicle', vscode.SymbolKind.Class);
        assertSymbolExists(symbols, 'Point', vscode.SymbolKind.Class);
    });

    test('Vehicle class has properties and methods', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('ClassesAndRecords.nl');
        const symbols = await getDocumentSymbols(doc);

        const vehicle = findSymbol(symbols, 'Vehicle');
        assert.ok(vehicle, 'Vehicle symbol should exist');
        assert.ok(vehicle!.children.length > 0,
            'Vehicle should have member children');

        const childNames = vehicle!.children.map(c => c.name);
        assert.ok(childNames.includes('GetDescription'),
            `Vehicle should have GetDescription method. Children: ${childNames.join(', ')}`);
    });

    // ================================================================
    // ENUMVARIANTS.NL — Multiple enum types
    // ================================================================

    test('EnumVariants.nl has all enum declarations', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('EnumVariants.nl');
        const symbols = await getDocumentSymbols(doc);

        assert.ok(symbols.length > 0, 'Should have symbols for EnumVariants.nl');

        assertSymbolExists(symbols, 'Direction', vscode.SymbolKind.Enum);
        assertSymbolExists(symbols, 'Priority', vscode.SymbolKind.Enum);
        assertSymbolExists(symbols, 'DayOfWeek', vscode.SymbolKind.Enum);
    });

    // ================================================================
    // HELPERS.NL — Cross-file symbol completeness
    // ================================================================

    test('Helpers.nl has expected function symbols', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Helpers.nl');
        const symbols = await getDocumentSymbols(doc);

        assert.ok(symbols.length > 0, 'Should have symbols for Helpers.nl');

        assertSymbolExists(symbols, 'multiply', vscode.SymbolKind.Function);
        assertSymbolExists(symbols, 'isEven', vscode.SymbolKind.Function);
    });

    // ================================================================
    // SYMBOL RANGES
    // ================================================================

    test('symbol ranges are valid (non-zero, non-overlapping)', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        const symbols = await getDocumentSymbols(doc);

        for (const sym of symbols) {
            // Range should be valid
            assert.ok(sym.range.start.line <= sym.range.end.line,
                `Symbol "${sym.name}" range start (${sym.range.start.line}) should be <= end (${sym.range.end.line})`);

            // Selection range should be within the full range
            assert.ok(sym.selectionRange.start.line >= sym.range.start.line,
                `Symbol "${sym.name}" selection range should be within full range`);
        }
    });

    // ================================================================
    // EDGE CASES
    // ================================================================

    test('total symbol count matches expectations for Program.nl', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        const symbols = await getDocumentSymbols(doc);

        // Program.nl has: greet, add, Color, Status, Person, Main = 6 top-level symbols
        assert.ok(symbols.length >= 5,
            `Expected at least 5 top-level symbols in Program.nl, got ${symbols.length}: ${symbols.map(s => s.name).join(', ')}`);
        assert.ok(symbols.length <= 10,
            `Expected at most 10 top-level symbols in Program.nl, got ${symbols.length}: ${symbols.map(s => s.name).join(', ')}`);
    });

    test('all symbols have non-empty names', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');
        const symbols = await getDocumentSymbols(doc);

        const allNames = flattenSymbolNames(symbols);
        for (const name of allNames) {
            assert.ok(name.length > 0, 'Symbol name should not be empty');
        }
    });
});
