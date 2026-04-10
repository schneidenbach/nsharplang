import * as assert from 'assert';
import * as path from 'path';
import * as fs from 'fs';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    openDocument,
    getDiagnostics,
    getDocumentSymbols,
    closeAllEditors,
    formatDiagnosticErrors,
    waitForLspReady
} from './helpers';

/**
 * Comprehensive syntax coverage tests.
 *
 * These tests open every .nl file in the test fixture workspace and assert
 * that the Language Server produces zero error diagnostics. This is the
 * primary regression detector for parser/analysis bugs that cause false
 * positives — e.g., valid syntax flagged as errors.
 *
 * Each fixture file exercises specific language constructs:
 * - TypedDeclarations.nl: typed variable declarations (x: int), out params
 * - EnumVariants.nl: string/int-backed enums, simple enums
 * - OutRefParams.nl: ref/out parameter signatures and call-site usage
 * - PatternMatching.nl: match expressions, guards, control flow
 * - Collections.nl: List<T>, Dictionary<K,V>, collection init
 * - StringInterpolation.nl: interpolation edge cases
 * - ClassesAndRecords.nl: class definitions, constructors, properties
 * - Program.nl: core language features (functions, enums, classes)
 * - Helpers.nl: multi-file project support
 */
suite('Syntax Coverage — Zero Error Assertions', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    // Discover all .nl files in the simple fixture workspace
    // __dirname at runtime is out/test/suite/ — go up 3 levels to reach the extension root
    const extensionRoot = path.resolve(__dirname, '../../../');
    const fixtureDir = path.join(extensionRoot, 'test', 'fixtures', 'simple');
    const nlFiles = discoverNlFiles(fixtureDir);

    if (nlFiles.length === 0) {
        test('should find fixture .nl files', () => {
            assert.fail(`No .nl files found in ${fixtureDir}`);
        });
        return;
    }

    // Generate one test per fixture file
    for (const absolutePath of nlFiles) {
        const fileName = path.basename(absolutePath);

        test(`${fileName} — zero error diagnostics`, async function () {
            this.timeout(60_000);

            const doc = await openDocument(fileName);
            const diagnostics = await getDiagnostics(doc);

            // Filter to errors that are actually within this file's line range.
            // The LSP may publish workspace-wide diagnostics under a single URI
            // during background analysis; ignore out-of-range diagnostics.
            const lineCount = doc.lineCount;
            const errors = diagnostics.filter(
                d => d.severity === vscode.DiagnosticSeverity.Error
                    && d.range.start.line < lineCount
            );

            assert.strictEqual(
                errors.length,
                0,
                `Expected 0 errors in ${fileName} but found ${errors.length}:\n${formatDiagnosticErrors(errors)}`
            );
        });
    }

    // Verify LSP is actually analyzing the files (not just returning empty results)
    test('LSP returns document symbols for fixture files', async function () {
        this.timeout(60_000);

        const doc = await openDocument('Program.nl');
        await waitForLspReady(doc);
        const symbols = await getDocumentSymbols(doc);

        assert.ok(
            symbols.length > 0,
            'LSP should return document symbols for Program.nl — ' +
            'if this fails, the zero-error assertions above are meaningless'
        );
    });

    test('LSP returns document symbols for TypedDeclarations.nl', async function () {
        this.timeout(60_000);

        const doc = await openDocument('TypedDeclarations.nl');
        await waitForLspReady(doc);
        const symbols = await getDocumentSymbols(doc);

        assert.ok(
            symbols.length > 0,
            'LSP should return document symbols for TypedDeclarations.nl'
        );
    });

    test('LSP returns document symbols for EnumVariants.nl', async function () {
        this.timeout(60_000);

        const doc = await openDocument('EnumVariants.nl');
        await waitForLspReady(doc);
        const symbols = await getDocumentSymbols(doc);

        assert.ok(
            symbols.length > 0,
            'LSP should return document symbols for EnumVariants.nl'
        );
    });
});

/**
 * Recursively discover all .nl files in a directory.
 */
function discoverNlFiles(dir: string): string[] {
    const results: string[] = [];
    if (!fs.existsSync(dir)) return results;

    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            if (['node_modules', 'bin', 'obj', '.git'].includes(entry.name)) continue;
            results.push(...discoverNlFiles(fullPath));
        } else if (entry.name.endsWith('.nl') && !entry.name.startsWith('_')) {
            results.push(fullPath);
        }
    }

    return results.sort();
}
