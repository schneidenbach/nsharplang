import * as vscode from 'vscode';
import * as cp from 'child_process';
import * as path from 'path';

interface TestResultJson {
    schemaVersion: number;
    command: string;
    ok: boolean;
    projectRoot: string;
    error?: string;
    summary: {
        total: number;
        passed: number;
        failed: number;
        skipped: number;
        duration: string;
    };
    results: Array<{
        name: string;
        displayName: string;
        outcome: string;
        duration: string;
        errorMessage?: string;
        nsharpDescription?: string;
    }>;
}

/**
 * Handles running N# tests via `nlc test --json` and mapping results
 * back to VS Code TestItems.
 */
export class NSharpTestRunner {
    constructor(private controller: vscode.TestController) {}

    async runTests(
        request: vscode.TestRunRequest,
        token: vscode.CancellationToken,
        debug = false
    ): Promise<void> {
        const run = this.controller.createTestRun(request);
        const testsToRun = this.collectTests(request);

        if (testsToRun.length === 0) {
            run.end();
            return;
        }

        // Mark all tests as enqueued
        for (const item of testsToRun) {
            run.enqueued(item);
        }

        // Determine workspace root
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        if (!workspaceFolder) {
            for (const item of testsToRun) {
                run.errored(item, new vscode.TestMessage('No workspace folder open'));
            }
            run.end();
            return;
        }

        const cwd = workspaceFolder.uri.fsPath;

        // Build the filter from test descriptions
        const filter = this.buildFilter(testsToRun, request);

        // Mark tests as started
        for (const item of testsToRun) {
            run.started(item);
        }

        if (debug) {
            await this.runDebug(run, testsToRun, cwd, filter, token);
        } else {
            await this.runNormal(run, testsToRun, cwd, filter, token);
        }

        run.end();
    }

    private async runNormal(
        run: vscode.TestRun,
        testsToRun: vscode.TestItem[],
        cwd: string,
        filter: string | undefined,
        token: vscode.CancellationToken
    ): Promise<void> {
        const nlcPath = vscode.workspace.getConfiguration('nsharp').get<string>('cli.path') || 'nlc';
        const args = ['test', '--json'];
        if (filter) {
            args.push('--filter', filter);
        }

        return new Promise<void>((resolve) => {
            let stdout = '';

            const proc = cp.spawn(nlcPath, args, { cwd });

            token.onCancellationRequested(() => {
                proc.kill();
            });

            proc.stdout.on('data', (data: Buffer) => {
                stdout += data.toString();
            });

            proc.stderr.on('data', (data: Buffer) => {
                // Emit stderr as test output
                run.appendOutput(data.toString().replace(/\n/g, '\r\n'));
            });

            proc.on('close', () => {
                this.parseAndReportResults(run, testsToRun, stdout);
                resolve();
            });

            proc.on('error', (err) => {
                for (const item of testsToRun) {
                    run.errored(item, new vscode.TestMessage(
                        `Failed to run nlc: ${err.message}. Is nlc installed and on PATH?`
                    ));
                }
                resolve();
            });
        });
    }

    private async runDebug(
        run: vscode.TestRun,
        testsToRun: vscode.TestItem[],
        cwd: string,
        filter: string | undefined,
        token: vscode.CancellationToken
    ): Promise<void> {
        // For debug, run nlc test with dotnet test under the debugger
        // First build, then launch with coreclr attach
        const nlcPath = vscode.workspace.getConfiguration('nsharp').get<string>('cli.path') || 'nlc';
        const args = ['test'];
        if (filter) {
            args.push('--filter', filter);
        }

        // Use terminal for debug mode so user can see output
        const terminal = vscode.window.createTerminal({
            name: 'N# Test Debug',
            cwd
        });
        terminal.show();
        terminal.sendText(`${nlcPath} ${args.join(' ')}`);

        // Mark tests as passed (we can't capture results from terminal)
        for (const item of testsToRun) {
            run.skipped(item);
        }
    }

    private collectTests(request: vscode.TestRunRequest): vscode.TestItem[] {
        const tests: vscode.TestItem[] = [];

        if (request.include) {
            for (const item of request.include) {
                this.collectTestItems(item, tests);
            }
        } else {
            // Run all tests
            this.controller.items.forEach(item => {
                this.collectTestItems(item, tests);
            });
        }

        // Exclude items
        if (request.exclude) {
            const excludeIds = new Set(request.exclude.map(e => e.id));
            return tests.filter(t => !excludeIds.has(t.id));
        }

        return tests;
    }

    private collectTestItems(item: vscode.TestItem, tests: vscode.TestItem[]): void {
        if (item.children.size === 0) {
            // Leaf node = individual test
            tests.push(item);
        } else {
            // Container = file with children tests
            item.children.forEach(child => {
                this.collectTestItems(child, tests);
            });
        }
    }

    private buildFilter(
        testsToRun: vscode.TestItem[],
        request: vscode.TestRunRequest
    ): string | undefined {
        // If running all tests (no include specified), don't filter
        if (!request.include) return undefined;

        // If only one test, use its method name directly
        if (testsToRun.length === 1) {
            return testDescriptionToMethodName(testsToRun[0].label);
        }

        // For multiple tests, build a VSTest filter expression with OR predicates.
        // nlc test --filter wraps as DisplayName~X|FullyQualifiedName~X,
        // so we pass each test name separately and let nlc handle matching.
        // Since nlc doesn't support multiple --filter args, we use the
        // dotnet test filter syntax directly via FullyQualifiedName matching.
        const methodNames = testsToRun.map(t => testDescriptionToMethodName(t.label));
        return methodNames.join('|');
    }

    private parseAndReportResults(
        run: vscode.TestRun,
        testsToRun: vscode.TestItem[],
        stdout: string
    ): void {
        let json: TestResultJson;
        try {
            json = JSON.parse(stdout);
        } catch {
            // If JSON parsing fails, mark all as errored
            for (const item of testsToRun) {
                run.errored(item, new vscode.TestMessage(
                    `Failed to parse test output. Raw output:\n${stdout.substring(0, 500)}`
                ));
            }
            return;
        }

        if (json.error) {
            for (const item of testsToRun) {
                run.errored(item, new vscode.TestMessage(json.error));
            }
            return;
        }

        // Match results to test items
        for (const result of json.results) {
            const item = this.findMatchingTestItem(testsToRun, result);
            if (!item) continue;

            const duration = parseFloat(result.duration) * 1000; // Convert seconds to ms

            switch (result.outcome) {
                case 'passed':
                    run.passed(item, duration);
                    break;
                case 'failed': {
                    const msg = new vscode.TestMessage(result.errorMessage || 'Test failed');
                    if (item.uri && item.range) {
                        msg.location = new vscode.Location(item.uri, item.range);
                    }
                    run.failed(item, msg, duration);
                    break;
                }
                case 'notexecuted':
                    run.skipped(item);
                    break;
                default:
                    run.errored(item, new vscode.TestMessage(`Unknown outcome: ${result.outcome}`));
            }
        }

        // Any remaining tests not in results get marked as errored
        const reportedNames = new Set(json.results.map(r => r.nsharpDescription || r.name));
        for (const item of testsToRun) {
            // Check if we already reported this item
            if (!reportedNames.has(item.label) && !json.results.some(r => this.matchesItem(r, item))) {
                // Only if we ran specific tests and they weren't in results
                if (json.summary.total === 0 && json.ok) {
                    run.skipped(item);
                }
            }
        }
    }

    private findMatchingTestItem(
        items: vscode.TestItem[],
        result: { name: string; nsharpDescription?: string }
    ): vscode.TestItem | undefined {
        // First try to match by nsharpDescription (exact match on test label)
        if (result.nsharpDescription) {
            const found = items.find(item => item.label === result.nsharpDescription);
            if (found) return found;
        }

        // Fall back to method name matching
        const methodName = result.name.split('.').pop() || result.name;
        return items.find(item => {
            const expectedMethod = testDescriptionToMethodName(item.label);
            return methodName === expectedMethod;
        });
    }

    private matchesItem(
        result: { name: string; nsharpDescription?: string },
        item: vscode.TestItem
    ): boolean {
        if (result.nsharpDescription === item.label) return true;
        const methodName = result.name.split('.').pop() || result.name;
        return methodName === testDescriptionToMethodName(item.label);
    }
}

/**
 * Converts a test description to a PascalCase method name.
 * Mirrors the C# Transpiler.TestDescriptionToMethodName logic.
 */
export function testDescriptionToMethodName(description: string): string {
    const words = description.split(/[\s\-_]+/).filter(w => w.length > 0);
    let result = words
        .map(word => word.charAt(0).toUpperCase() + word.slice(1))
        .join('');

    // Remove invalid characters
    result = result.replace(/[^a-zA-Z0-9_]/g, '');

    // Ensure starts with letter or underscore
    if (result.length === 0 || !/[a-zA-Z]/.test(result.charAt(0))) {
        result = 'Test_' + result;
    }

    return result;
}
