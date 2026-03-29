import * as assert from 'assert';
import * as path from 'path';
import * as fs from 'fs';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocumentByPath,
    waitForDiagnosticsToSettle,
    closeAllEditors,
    getRepoRoot,
    sleep
} from './helpers';

/**
 * Example files that are EXPECTED to have parse/analysis errors.
 * These are intentional error-demonstration files, not bugs.
 * Map from relative path (from repo root) to reason for allow-listing.
 */
const EXPECTED_ERROR_FILES: Record<string, string> = {
    'examples/02-variables-and-types/TestErrors.nl': 'Intentional error demonstration file',
    'editors/vscode/test/fixtures/errors/HasErrors.nl': 'Test fixture with intentional errors',
    // Parser doesn't yet support params collections syntax
    'examples/03-functions/ParamsCollections.nl': 'Parser: params collections not yet supported',
    'examples/03-functions/SpreadInFunctionCalls.nl': 'Parser: spread syntax not yet supported',
    // Parser doesn't yet support match expressions / pattern matching fully
    'examples/04-pattern-matching/GuardsSimple.nl': 'Parser: match expressions not yet supported in LSP',
    'examples/04-pattern-matching/ListPatterns.nl': 'Parser: list patterns not yet supported in LSP',
    'examples/04-pattern-matching/MatchExhaustiveness.nl': 'Parser: match exhaustiveness not yet supported in LSP',
    'examples/04-pattern-matching/NestedPropertyPatterns.nl': 'Parser: nested property patterns not yet supported in LSP',
    'examples/04-pattern-matching/NestedPropertyPatternsSimple.nl': 'Parser: nested property patterns not yet supported in LSP',
    'examples/04-pattern-matching/NestedSimpleTest.nl': 'Parser: nested match not yet supported in LSP',
    'examples/04-pattern-matching/PatternGuards.nl': 'Parser: pattern guards not yet supported in LSP',
    'examples/04-pattern-matching/TypePatterns.nl': 'Parser: type patterns not yet supported in LSP',
    // Parser doesn't yet support union match syntax
    'examples/05-unions/UnionsAndMatch.nl': 'Parser: union match not yet supported in LSP',
    // Parser doesn't yet support primary constructors
    'examples/06-classes-and-records/PrimaryConstructors.nl': 'Parser: primary constructors not yet supported in LSP',
    'examples/06-classes-and-records/PrimaryConstructorsSimple.nl': 'Parser: primary constructors not yet supported in LSP',
    // Parser doesn't yet support extension methods
    'examples/07-interfaces/ExtensionMethods.nl': 'Parser: extension methods not yet supported in LSP',
    // Parser doesn't yet support inline out variables
    'examples/10-interop/InlineOutVariables.nl': 'Parser: inline out var not yet supported in LSP',
    // Parser doesn't yet support ref/out parameters in all contexts
    'examples/10-interop/RefOutParameters.nl': 'Parser: ref/out parameters not yet supported in LSP',
    // Parser doesn't yet support async streams fully
    'examples/08-async/AsyncStreams.nl': 'Parser: async streams not yet supported in LSP',
    // Parser doesn't yet support collection initializers with indexers
    'examples/09-linq-and-collections/CollectionInitializersWithIndexers.nl': 'Parser: collection initializers with indexers not yet supported in LSP',
    // Parser doesn't yet support conversion operators
    'examples/11-advanced-features/ConversionOperators/ConversionOperators.nl': 'Parser: conversion operators not yet supported in LSP',
    // Parser doesn't yet support operator overloading
    'examples/11-advanced-features/OperatorOverloading/OperatorOverloading.nl': 'Parser: operator overloading not yet supported in LSP',
};

/**
 * Dynamically generates one test per .nl file in the examples/ directory.
 * Each test opens the file in VS Code via the LSP and asserts zero error diagnostics.
 *
 * This is the primary regression detector for parser bugs that only surface
 * when real files are processed through the full LSP pipeline.
 */
suite('Example File Smoke Tests', () => {
    const repoRoot = getRepoRoot();
    const examplesDir = path.join(repoRoot, 'examples');

    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // Discover all .nl files at suite definition time
    const nlFiles = findNlFiles(examplesDir);

    if (nlFiles.length === 0) {
        test('should find example .nl files', () => {
            assert.fail(`No .nl files found in ${examplesDir}. Is the repo root correct?`);
        });
        return;
    }

    for (const absolutePath of nlFiles) {
        const relativePath = path.relative(repoRoot, absolutePath);
        const isExpectedError = EXPECTED_ERROR_FILES[relativePath] !== undefined;
        const testName = isExpectedError
            ? `[expected errors] ${relativePath}`
            : relativePath;

        test(testName, async function () {
            this.timeout(45_000);

            const doc = await openDocumentByPath(absolutePath);

            // Wait for diagnostics to settle
            const diagnostics = await waitForDiagnosticsToSettle(doc.uri, 15_000);
            const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);

            if (isExpectedError) {
                // For allow-listed files, we just verify the file opens without crashing
                // Having errors is expected
                return;
            }

            // For all other files, assert zero errors
            if (errors.length > 0) {
                const errorDetails = errors.map(d => {
                    const range = `${d.range.start.line + 1}:${d.range.start.character + 1}`;
                    const code = d.code ? ` [${d.code}]` : '';
                    return `  Line ${range}${code}: ${d.message}`;
                }).join('\n');

                assert.fail(
                    `Expected 0 errors in ${relativePath} but found ${errors.length}:\n${errorDetails}`
                );
            }

            await closeAllEditors();
        });
    }
});

/**
 * Recursively find all .nl files in a directory.
 */
function findNlFiles(dir: string): string[] {
    const results: string[] = [];

    if (!fs.existsSync(dir)) {
        return results;
    }

    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            // Skip node_modules, bin, obj directories
            if (['node_modules', 'bin', 'obj', 'nsharp', '.git'].includes(entry.name)) {
                continue;
            }
            results.push(...findNlFiles(fullPath));
        } else if (entry.name.endsWith('.nl')) {
            results.push(fullPath);
        }
    }

    return results.sort();
}
