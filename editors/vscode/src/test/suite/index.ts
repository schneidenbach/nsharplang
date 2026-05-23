import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';

type TestStatus = 'passed' | 'failed';

interface TestCaseResult {
    name: string;
    status: TestStatus;
    durationMs: number;
    details?: Record<string, unknown>;
    error?: string;
}

interface Report {
    schemaVersion: '1';
    generatedAt: string;
    workspaceRoot: string;
    serverPath: string;
    vscodeVersion: string;
    extensionId: string;
    successCount: number;
    failureCount: number;
    results: TestCaseResult[];
}

const workspaceRoot = mustGetEnv('NSHARP_VSCODE_FIXTURE_ROOT');
const reportPath = mustGetEnv('NSHARP_VSCODE_REPORT_PATH');
const serverPath = mustGetEnv('NSHARP_VSCODE_SERVER_PATH');
const extensionId = 'nsharp.nsharp';

export async function run(): Promise<void> {
    const results: TestCaseResult[] = [];
    let exitCode = 0;

    try {
        await runCase(results, 'activate-extension', async () => {
            const document = await openDocument('Program.nl');
            const extension = await waitForExtension();
            await waitFor(
                'program document to load',
                async () => document.getText().length > 0 ? true : undefined);

            return {
                active: extension.isActive,
                document: path.basename(document.uri.fsPath)
            };
        });

        await runCase(results, 'diagnostics', async () => {
            const document = await openDocument('Broken.nl');
            const diagnostics = await waitForDiagnostics(
                document,
                items => items.some(item => item.severity === vscode.DiagnosticSeverity.Error));

            const error = diagnostics.find(item => item.severity === vscode.DiagnosticSeverity.Error);
            assert.ok(error, 'Expected an error diagnostic for Broken.nl');

            return {
                diagnostics: serializeDiagnostics(diagnostics)
            };
        });

        await runCase(results, 'completion', async () => {
            const document = await openDocument('Completion.nl');
            const position = findPosition(document, 'name.', 'name.'.length);
            const completion = await waitFor(
                'member completion results',
                async () => {
                    const value = await vscode.commands.executeCommand<vscode.CompletionList>(
                        'vscode.executeCompletionItemProvider',
                        document.uri,
                        position);

                    if (!value || value.items.length === 0) {
                        return undefined;
                    }

                    const labels = value.items.map(item => normalizeLabel(item.label));
                    return labels.includes('ToUpper') ? value : undefined;
                });

            const duplicateLabels = findDuplicateLabels(completion.items);
            assert.deepStrictEqual(duplicateLabels, [], `Duplicate completion labels: ${duplicateLabels.join(', ')}`);

            return {
                count: completion.items.length,
                sample: completion.items.slice(0, 10).map(item => normalizeLabel(item.label)),
                duplicateLabels
            };
        });

        await runCase(results, 'hover', async () => {
            const document = await openDocument('Program.nl');
            const position = findPosition(document, 'ToUpper');
            const hovers = await waitFor(
                'hover results',
                async () => {
                    const value = await vscode.commands.executeCommand<vscode.Hover[]>(
                        'vscode.executeHoverProvider',
                        document.uri,
                        position);

                    return value && value.length > 0 ? value : undefined;
                });

            return {
                contents: hovers.flatMap(hover => hover.contents.map(stringifyHoverContent))
            };
        });

        await runCase(results, 'definition', async () => {
            const document = await openDocument('Program.nl');
            const position = findPosition(document, 'greet(name)');
            const definitions = await waitFor(
                'definition results',
                async () => {
                    const value = await vscode.commands.executeCommand<Array<vscode.Location | vscode.LocationLink>>(
                        'vscode.executeDefinitionProvider',
                        document.uri,
                        position);

                    if (!value || value.length === 0) {
                        return undefined;
                    }

                    return value;
                });

            const helperDefinition = definitions.find(item => {
                const uri = 'targetUri' in item ? item.targetUri : item.uri;
                return uri.fsPath.endsWith('Helpers.nl');
            });

            assert.ok(helperDefinition, 'Expected definition to resolve into Helpers.nl');

            return {
                definitions: definitions.map(serializeDefinition)
            };
        });

        await runCase(results, 'references', async () => {
            const document = await openDocument('Program.nl');
            const position = findPosition(document, 'greet(name)');
            const references = await waitFor(
                'reference results',
                async () => {
                    const value = await vscode.commands.executeCommand<vscode.Location[]>(
                        'vscode.executeReferenceProvider',
                        document.uri,
                        position);

                    return value && value.length >= 2 ? value : undefined;
                });

            return {
                references: references.map(reference => ({
                    file: path.basename(reference.uri.fsPath),
                    line: reference.range.start.line,
                    character: reference.range.start.character
                }))
            };
        });

        await runCase(results, 'code-actions', async () => {
            const document = await openDocument('AutoImport.nl');
            const diagnostics = await waitForDiagnostics(
                document,
                items => items.some(item => item.code === 'NL002'));
            const missingImport = diagnostics.find(item => item.code === 'NL002');

            assert.ok(missingImport, 'Expected NL002 missing import diagnostic');

            const codeActions = await waitFor(
                'code action results',
                async () => {
                    const value = await vscode.commands.executeCommand<readonly (vscode.Command | vscode.CodeAction)[]>(
                        'vscode.executeCodeActionProvider',
                        document.uri,
                        missingImport.range,
                        vscode.CodeActionKind.QuickFix.value);

                    if (!value || value.length === 0) {
                        return undefined;
                    }

                    const titles = value.map(getActionTitle);
                    return titles.includes('Add import System.Collections.Generic') ? value : undefined;
                });

            return {
                actions: codeActions.map(getActionTitle)
            };
        });
    } finally {
        writeReport(results);
        exitCode = results.some(result => result.status === 'failed') ? 1 : 0;

        setTimeout(() => process.exit(exitCode), 250);
    }

    const failures = results.filter(result => result.status === 'failed');
    if (failures.length > 0) {
        throw new Error(`${failures.length} headless VS Code smoke test(s) failed. See ${reportPath}`);
    }
}

async function runCase(
    results: TestCaseResult[],
    name: string,
    action: () => Promise<Record<string, unknown> | void>): Promise<void> {
    const startedAt = Date.now();

    try {
        const details = await action();
        results.push({
            name,
            status: 'passed',
            durationMs: Date.now() - startedAt,
            details: details ?? undefined
        });
    } catch (error) {
        results.push({
            name,
            status: 'failed',
            durationMs: Date.now() - startedAt,
            error: error instanceof Error ? `${error.message}\n${error.stack ?? ''}` : String(error)
        });
    }
}

async function openDocument(relativePath: string): Promise<vscode.TextDocument> {
    const uri = vscode.Uri.file(path.join(workspaceRoot, relativePath));
    const document = await vscode.workspace.openTextDocument(uri);
    await vscode.window.showTextDocument(document, { preview: false });
    return document;
}

async function waitForExtension(): Promise<vscode.Extension<unknown>> {
    return waitFor(
        'extension activation',
        async () => {
            const extension = vscode.extensions.getExtension(extensionId);
            if (!extension) {
                return undefined;
            }

            if (!extension.isActive) {
                await extension.activate();
            }

            return extension.isActive ? extension : undefined;
        });
}

async function waitForDiagnostics(
    document: vscode.TextDocument,
    predicate: (items: readonly vscode.Diagnostic[]) => boolean): Promise<readonly vscode.Diagnostic[]> {
    return waitFor(
        `diagnostics for ${path.basename(document.uri.fsPath)}`,
        async () => {
            const items = vscode.languages.getDiagnostics(document.uri);
            return predicate(items) ? items : undefined;
        },
        30000);
}

async function waitFor<T>(
    description: string,
    probe: () => Promise<T | undefined> | T | undefined,
    timeoutMs = 20000,
    intervalMs = 250): Promise<T> {
    const startedAt = Date.now();
    let lastError: unknown;

    while (Date.now() - startedAt < timeoutMs) {
        try {
            const value = await probe();
            if (value !== undefined) {
                return value;
            }
        } catch (error) {
            lastError = error;
        }

        await delay(intervalMs);
    }

    const suffix = lastError == null ? '' : ` Last error: ${String(lastError)}`;
    throw new Error(`Timed out waiting for ${description}.${suffix}`);
}

function findPosition(document: vscode.TextDocument, needle: string, offset = 0): vscode.Position {
    const index = document.getText().indexOf(needle);
    assert.ok(index >= 0, `Could not find '${needle}' in ${path.basename(document.uri.fsPath)}`);
    return document.positionAt(index + offset);
}

function normalizeLabel(label: string | vscode.CompletionItemLabel): string {
    return typeof label === 'string' ? label : label.label;
}

function findDuplicateLabels(items: readonly vscode.CompletionItem[]): string[] {
    const counts = new Map<string, number>();
    for (const item of items) {
        const label = normalizeLabel(item.label);
        counts.set(label, (counts.get(label) ?? 0) + 1);
    }

    return [...counts.entries()]
        .filter(([, count]) => count > 1)
        .map(([label]) => label)
        .sort();
}

function stringifyHoverContent(content: vscode.MarkdownString | vscode.MarkedString): string {
    if (typeof content === 'string') {
        return content;
    }

    if (content instanceof vscode.MarkdownString) {
        return content.value;
    }

    const markedString = content as { language?: string; value: string };
    return markedString.language
        ? `${markedString.language}\n${markedString.value}`
        : markedString.value;
}

function serializeDiagnostics(diagnostics: readonly vscode.Diagnostic[]): Array<Record<string, unknown>> {
    return diagnostics.map(diagnostic => ({
        code: diagnostic.code ?? null,
        severity: diagnostic.severity,
        message: diagnostic.message,
        line: diagnostic.range.start.line,
        character: diagnostic.range.start.character
    }));
}

function serializeDefinition(definition: vscode.Location | vscode.LocationLink): Record<string, unknown> {
    if ('targetUri' in definition) {
        return {
            file: path.basename(definition.targetUri.fsPath),
            line: definition.targetRange.start.line,
            character: definition.targetRange.start.character
        };
    }

    return {
        file: path.basename(definition.uri.fsPath),
        line: definition.range.start.line,
        character: definition.range.start.character
    };
}

function getActionTitle(action: vscode.Command | vscode.CodeAction): string {
    return action.title;
}

function writeReport(results: TestCaseResult[]): void {
    const report: Report = {
        schemaVersion: '1',
        generatedAt: new Date().toISOString(),
        workspaceRoot,
        serverPath,
        vscodeVersion: vscode.version,
        extensionId,
        successCount: results.filter(result => result.status === 'passed').length,
        failureCount: results.filter(result => result.status === 'failed').length,
        results
    };

    fs.mkdirSync(path.dirname(reportPath), { recursive: true });
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
}

function mustGetEnv(name: string): string {
    const value = process.env[name];
    if (!value) {
        throw new Error(`Missing required environment variable: ${name}`);
    }

    return value;
}

function delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
}
