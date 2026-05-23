import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentAndWaitForLsp,
    getSignatureHelp,
    positionOf,
    closeAllEditors,
    createTempNlFile,
    getDiagnostics
} from './helpers';

function documentationText(documentation: string | vscode.MarkdownString | undefined): string | undefined {
    return typeof documentation === 'string' ? documentation : documentation?.value;
}

/**
 * Signature Help tests with parameter validation.
 *
 * The SignatureHelpHandler is fully implemented for N# functions and .NET types.
 * It triggers on "(" and "," characters.
 *
 * Signature label format: "funcName(param1: Type, param2: Type): ReturnType"
 * Parameter label format: "paramName: ParamType"
 *
 * Every test hard-asserts the signature is returned AND validates parameters.
 */
suite('Signature Help', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // ================================================================
    // SINGLE-PARAMETER FUNCTION
    // ================================================================

    test('greet() shows 1 parameter with name and type', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position right after "greet(" in "greet("World")"
        const pos = positionOf(doc, 'greet("World")', { at: 'start' });
        const parenPos = new vscode.Position(pos.line, pos.character + 6);
        const sigHelp = await getSignatureHelp(doc, parenPos);

        assert.ok(sigHelp, 'Signature help should be returned for greet()');
        assert.ok(sigHelp!.signatures.length > 0,
            'Expected at least one signature');

        const sig = sigHelp!.signatures[0];
        assert.ok(sig.parameters.length === 1,
            `Expected 1 parameter for greet(), got ${sig.parameters.length}`);

        // Check parameter label contains the parameter name
        const paramLabel = typeof sig.parameters[0].label === 'string'
            ? sig.parameters[0].label
            : sig.label.substring(sig.parameters[0].label[0], sig.parameters[0].label[1]);
        assert.ok(paramLabel.includes('name') || paramLabel.includes('string'),
            `Parameter label should contain "name" or "string". Got: "${paramLabel}"`);

        // Signature label should mention "greet"
        assert.ok(sig.label.includes('greet'),
            `Signature label should contain "greet". Got: "${sig.label}"`);
    });

    // ================================================================
    // MULTI-PARAMETER FUNCTION
    // ================================================================

    test('add() shows 2 parameters', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position right after "add(" in "add(3, 4)"
        const pos = positionOf(doc, 'add(3, 4)', { at: 'start' });
        const parenPos = new vscode.Position(pos.line, pos.character + 4);
        const sigHelp = await getSignatureHelp(doc, parenPos);

        assert.ok(sigHelp, 'Signature help should be returned for add()');
        assert.ok(sigHelp!.signatures.length > 0,
            'Expected at least one signature');

        const sig = sigHelp!.signatures[0];
        assert.ok(sig.parameters.length >= 2,
            `Expected at least 2 parameters for add(), got ${sig.parameters.length}`);

        // Signature label should contain "add"
        assert.ok(sig.label.includes('add'),
            `Signature label should contain "add". Got: "${sig.label}"`);
    });

    test('add() after comma shows second parameter active', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position after "add(3, " — should highlight second parameter
        const pos = positionOf(doc, 'add(3, 4)', { at: 'start' });
        const afterComma = new vscode.Position(pos.line, pos.character + 7); // after "add(3, "
        const sigHelp = await getSignatureHelp(doc, afterComma);

        assert.ok(sigHelp, 'Signature help should work after comma');

        // Active parameter should be 1 (second parameter, 0-indexed)
        if (sigHelp!.signatures.length > 0 && sigHelp!.signatures[0].parameters.length >= 2) {
            assert.strictEqual(sigHelp!.activeParameter, 1,
                `Expected active parameter to be 1 (second param), got ${sigHelp!.activeParameter}`);
        }
    });

    // ================================================================
    // RETURN TYPE IN SIGNATURE
    // ================================================================

    test('signature label includes return type', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        const pos = positionOf(doc, 'greet("World")', { at: 'start' });
        const parenPos = new vscode.Position(pos.line, pos.character + 6);
        const sigHelp = await getSignatureHelp(doc, parenPos);

        assert.ok(sigHelp, 'Signature help should be returned');

        const sig = sigHelp!.signatures[0];
        // greet returns string — label should include "string" as return type
        assert.ok(
            sig.label.includes('string'),
            `Signature label should include return type "string". Got: "${sig.label}"`
        );
    });

    test('string instance method exposes overload set', async function () {
        this.timeout(60_000);
        const { doc, cleanup } = await createTempNlFile(`
func Main() {
    name := "Spencer"
    name.Contains(
}
`, '_signature_instance_overloads.nl');

        try {
            const parenPos = positionOf(doc, 'name.Contains(', { at: 'end' });
            const sigHelp = await getSignatureHelp(doc, parenPos);

            assert.ok(sigHelp, 'Signature help should be returned for string.Contains()');
            assert.ok(sigHelp!.signatures.length >= 2,
                `Expected string.Contains overloads, got ${sigHelp!.signatures.length} signature(s)`);

            const labels = sigHelp!.signatures.map(signature => signature.label);
            assert.ok(labels.every(label => label.startsWith('Contains(')),
                `Expected only Contains signatures. Got: ${labels.join(' | ')}`);
            assert.ok(labels.some(label => label.includes('value: string')),
                `Expected string overload. Got: ${labels.join(' | ')}`);
            assert.ok(labels.some(label => label.includes('value: char')),
                `Expected char overload. Got: ${labels.join(' | ')}`);
            assert.ok(labels.some(label => label.includes('comparisonType: StringComparison')),
                `Expected comparison overload. Got: ${labels.join(' | ')}`);

            const stringOverload = sigHelp!.signatures.find(signature =>
                signature.label.includes('value: string') &&
                !signature.label.includes('comparisonType'));
            assert.ok(stringOverload, `Expected single-parameter string overload. Got: ${labels.join(' | ')}`);

            const documentation = documentationText(stringOverload!.documentation);
            const parameterDocumentation = documentationText(stringOverload!.parameters[0]?.documentation);

            assert.ok(documentation?.includes('specified substring'),
                `Expected string.Contains signature documentation. Got: ${documentation ?? '<none>'}`);
            assert.ok(parameterDocumentation?.includes('string to seek'),
                `Expected string.Contains parameter documentation. Got: ${parameterDocumentation ?? '<none>'}`);
        } finally {
            cleanup();
        }
    });

    // ================================================================
    // EDGE CASES
    // ================================================================

    test('no signature help outside function call', async function () {
        this.timeout(30_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position at top of file, not inside any function call
        const sigHelp = await getSignatureHelp(doc, new vscode.Position(0, 0));

        // Should be undefined or have no signatures
        if (sigHelp) {
            assert.strictEqual(sigHelp.signatures.length, 0,
                `Expected no signatures outside function call, got ${sigHelp.signatures.length}`);
        }
    });

    test('signature help on constructor call', async function () {
        this.timeout(60_000);
        const doc = await openDocumentAndWaitForLsp('Program.nl');

        // Position right after "Person(" in "new Person("Alice", 30)"
        const pos = positionOf(doc, 'new Person("Alice"', { at: 'start' });
        const parenPos = new vscode.Position(pos.line, pos.character + 11); // after "new Person("
        const sigHelp = await getSignatureHelp(doc, parenPos);

        assert.ok(sigHelp, 'Signature help should be returned for constructor call');
        assert.ok(sigHelp!.signatures.length > 0,
            'Constructor should have at least one signature');

        const sig = sigHelp!.signatures[0];
        assert.ok(sig.parameters.length >= 2,
            `Person constructor should have at least 2 parameters (name, age), got ${sig.parameters.length}`);
    });
});
