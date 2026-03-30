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
    formatDiagnosticErrors
} from './helpers';

/**
 * Repo-wide .nl file scan — reproduces what you see opening the nsharplang folder.
 *
 * When someone opens the repo root in VS Code, the Language Server scans ALL .nl
 * files recursively via Directory.EnumerateFiles("*.nl", AllDirectories). This test
 * does the same thing: find every .nl file, open it, and check diagnostics.
 *
 * Files that are EXPECTED to have errors must be in KNOWN_ERROR_FILES with a reason.
 * Everything else must produce zero error diagnostics — if it doesn't, either
 * the parser has a bug or the file needs to go in the allow-list with an explanation.
 *
 * This is the "open folder in VS Code" regression test.
 */

// ================================================================
// FILE DISCOVERY — Must be defined before suite body executes
// ================================================================

/**
 * Directories to skip when scanning from repo root.
 * These either don't contain .nl source files or are build artifacts.
 */
const SKIP_DIRS = new Set([
    'node_modules', 'bin', 'obj', 'nsharp', '.git', '.vscode-test',
    'out', 'server', '.context',
    // C# source directories — no .nl files
    'src', 'tests',
    // Build/config directories
    'scripts', 'docs', 'memory', '.github', '.vscode',
]);

function findAllNlFiles(dir: string): string[] {
    const results: string[] = [];
    if (!fs.existsSync(dir)) return results;

    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            if (SKIP_DIRS.has(entry.name)) {
                continue;
            }
            results.push(...findAllNlFiles(fullPath));
        } else if (entry.name.endsWith('.nl')) {
            results.push(fullPath);
        }
    }

    return results.sort();
}

// ================================================================
// KNOWN ERROR FILES — Every .nl file in the repo that has errors
// must be listed here with a reason. If a file is NOT listed and
// produces errors, the test fails — either fix the file or add it
// here with an explanation.
//
// Format: path relative to repo root → reason
// ================================================================
const KNOWN_ERROR_FILES: Record<string, string> = {
    // Intentional error demonstration / test fixtures
    'editors/vscode/test/fixtures/errors/HasErrors.nl':
        'Test fixture: intentional type error',
    'editors/vscode/test/fixtures/errors/MultipleSyntaxErrors.nl':
        'Test fixture: intentional multiple syntax errors',
    'examples/02-variables-and-types/TestErrors.nl':
        'Example: intentional error demonstrations',

    // Parser limitations — features not yet supported in LSP analysis
    'examples/03-functions/ParamsCollections.nl':
        'Parser: params collections not yet supported',
    'examples/03-functions/SpreadInFunctionCalls.nl':
        'Parser: spread syntax not yet supported',
    'examples/04-pattern-matching/GuardsSimple.nl':
        'Parser: match expressions not yet supported',
    'examples/04-pattern-matching/ListPatterns.nl':
        'Parser: list patterns not yet supported',
    'examples/04-pattern-matching/MatchExhaustiveness.nl':
        'Parser: match exhaustiveness not yet supported',
    'examples/04-pattern-matching/NestedPropertyPatterns.nl':
        'Parser: nested property patterns not yet supported',
    'examples/04-pattern-matching/NestedPropertyPatternsSimple.nl':
        'Parser: nested property patterns not yet supported',
    'examples/04-pattern-matching/NestedSimpleTest.nl':
        'Parser: nested match not yet supported',
    'examples/04-pattern-matching/PatternGuards.nl':
        'Parser: pattern guards not yet supported',
    'examples/04-pattern-matching/TypePatterns.nl':
        'Parser: type patterns not yet supported',
    'examples/05-unions/UnionsAndMatch.nl':
        'Parser: union match not yet supported',
    'examples/06-classes-and-records/PrimaryConstructors.nl':
        'Parser: primary constructors not yet supported',
    'examples/06-classes-and-records/PrimaryConstructorsSimple.nl':
        'Parser: primary constructors not yet supported',
    'examples/07-interfaces/ExtensionMethods.nl':
        'Parser: extension methods not yet supported',
    'examples/08-async/AsyncStreams.nl':
        'Parser: async streams not yet supported',
    'examples/09-linq-and-collections/CollectionInitializersWithIndexers.nl':
        'Parser: collection initializers with indexers not yet supported',
    'examples/10-interop/InlineOutVariables.nl':
        'Parser: inline out var not yet supported',
    'examples/10-interop/RefOutParameters.nl':
        'Parser: ref/out parameters not yet supported',
    'examples/11-advanced-features/ConversionOperators/ConversionOperators.nl':
        'Parser: conversion operators not yet supported',
    'examples/11-advanced-features/OperatorOverloading/OperatorOverloading.nl':
        'Parser: operator overloading not yet supported',
};

// ================================================================
// TEST SUITE
// ================================================================

suite('Repo-Wide File Scan — Full Workspace Simulation', () => {
    const repoRoot = getRepoRoot();

    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // Discover all .nl files from repo root, skipping build artifacts
    // and C# source directories (which don't contain N# source files).
    const allNlFiles = findAllNlFiles(repoRoot);

    if (allNlFiles.length === 0) {
        test('should find .nl files in repo', () => {
            assert.fail(`No .nl files found under ${repoRoot}. Is repo root correct?`);
        });
        return;
    }

    // ================================================================
    // GENERATE ONE TEST PER FILE
    // ================================================================

    for (const absolutePath of allNlFiles) {
        const relativePath = path.relative(repoRoot, absolutePath);
        const isKnownError = KNOWN_ERROR_FILES[relativePath] !== undefined;
        const reason = KNOWN_ERROR_FILES[relativePath];
        const testLabel = isKnownError
            ? `[known: ${reason}] ${relativePath}`
            : relativePath;

        test(testLabel, async function () {
            this.timeout(45_000);

            const doc = await openDocumentByPath(absolutePath);
            const diagnostics = await waitForDiagnosticsToSettle(doc.uri, 15_000);
            const errors = diagnostics.filter(d => d.severity === vscode.DiagnosticSeverity.Error);

            if (isKnownError) {
                // File opens without crashing. Reason is in the test name.
                return;
            }

            // NOT in allow-list: must have zero errors
            if (errors.length > 0) {
                assert.fail(
                    `${relativePath} has ${errors.length} unexpected error(s).\n` +
                    `If these errors are expected (unsupported feature, demo file), ` +
                    `add the file to KNOWN_ERROR_FILES in repoWideScan.test.ts.\n\n` +
                    `Errors:\n${formatDiagnosticErrors(errors)}`
                );
            }

            await closeAllEditors();
        });
    }

    // ================================================================
    // META-TESTS — Ensure our allow-list is honest
    // ================================================================

    test('all KNOWN_ERROR_FILES entries point to real files', function () {
        const missing: string[] = [];
        for (const relPath of Object.keys(KNOWN_ERROR_FILES)) {
            const absPath = path.join(repoRoot, relPath);
            if (!fs.existsSync(absPath)) {
                missing.push(relPath);
            }
        }

        assert.strictEqual(missing.length, 0,
            `KNOWN_ERROR_FILES contains entries for files that don't exist:\n` +
            missing.map(f => `  - ${f}`).join('\n') +
            `\n\nRemove these stale entries.`);
    });

    test('file count is reasonable (sanity check)', function () {
        // If we suddenly have way fewer files, something is wrong with scanning
        assert.ok(allNlFiles.length >= 40,
            `Expected at least 40 .nl files in repo but found ${allNlFiles.length}. ` +
            `Is the repo root correct? (${repoRoot})`);
    });
});
