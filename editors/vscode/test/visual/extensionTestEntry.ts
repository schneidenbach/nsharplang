import * as childProcess from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { waitForLanguageServer } from '../suite/helpers';
import {
    runVisualScenario,
    visualScenarioNames,
    VisualScenarioName,
    writeVisualReport
} from './scenarios';

export async function run(): Promise<void> {
    const scenarioValue = requiredEnv('NSHARP_VSCODE_VISUAL_SCENARIO');
    const reportPath = requiredEnv('NSHARP_VSCODE_VISUAL_REPORT_PATH');
    const sentinelPath = requiredEnv('NSHARP_VSCODE_VISUAL_SENTINEL');
    const userDataDir = requiredEnv('NSHARP_VSCODE_VISUAL_USER_DATA_DIR');
    const holdSeconds = Number(requiredEnv('NSHARP_VSCODE_VISUAL_HOLD_SECONDS'));
    if (!visualScenarioNames.includes(scenarioValue as VisualScenarioName)) {
        throw new Error(`Unknown visual scenario: ${scenarioValue}`);
    }
    if (!Number.isInteger(holdSeconds) || holdSeconds < 0) {
        throw new Error(`Invalid hold duration: ${holdSeconds}`);
    }

    const scenario = scenarioValue as VisualScenarioName;
    const windowTitle = `[Extension Development Host] N# Visual Scenario: ${scenario} — Visual Studio Code`;
    try {
        await waitForLanguageServer();
        const details = await runVisualScenario(scenario);
        writeVisualReport(reportPath, scenario, details);

        console.log(`[N# Visual] Scenario passed: ${scenario}`);
        console.log(`[N# Visual] Report: ${reportPath}`);
        console.log(`[N# Visual] Test VS Code PID: ${findVscodePid(userDataDir)}`);
        console.log(`[N# Visual] Test VS Code window title: ${windowTitle}`);
        console.log(`[N# Visual] Sentinel: touch ${sentinelPath} to close early`);
        console.log(`[N# Visual] Holding window for ${holdSeconds === 0 ? 'sentinel only' : `${holdSeconds} seconds`}`);
        await holdWindow(sentinelPath, holdSeconds);
        console.log('[N# Visual] Hold finished; closing the isolated test window.');
    } catch (error) {
        writeFailureReport(reportPath, scenario, error);
        console.error(`[N# Visual] Scenario failed: ${scenario}`);
        console.error(error);
        throw error;
    } finally {
        try {
            await vscode.commands.executeCommand('workbench.action.closeWindow');
        } catch {
            // The extension host may already be shutting down after a failed scenario.
        }
    }
}

async function holdWindow(sentinelPath: string, holdSeconds: number): Promise<void> {
    const deadline = holdSeconds === 0 ? Number.POSITIVE_INFINITY : Date.now() + holdSeconds * 1000;
    while (Date.now() < deadline && !fs.existsSync(sentinelPath)) {
        await sleep(200);
    }
}

function findVscodePid(userDataDir: string): number {
    const result = childProcess.spawnSync('ps', ['-axo', 'pid=,ppid=,args='], { encoding: 'utf8' });
    if (result.error || result.status !== 0) {
        throw result.error ?? new Error(`Unable to inspect process table (ps exited ${result.status})`);
    }

    const matches = result.stdout.split(/\r?\n/).flatMap(line => {
        const match = /^\s*(\d+)\s+(\d+)\s+(.*)$/.exec(line);
        if (!match) return [];
        const command = match[3];
        if (!command.includes(`--user-data-dir=${userDataDir}`)) return [];
        if (command.includes('--type=') || command.includes('--ms-enable-electron-run-as-node')) return [];
        return [{ pid: Number(match[1]), command }];
    });
    const mainProcess = matches.find(match => !match.command.includes('Code Helper')) ?? matches[0];
    if (!mainProcess) {
        throw new Error(`Could not find the isolated VS Code main process for user data ${userDataDir}`);
    }
    return mainProcess.pid;
}

function writeFailureReport(reportPath: string, scenario: VisualScenarioName, error: unknown): void {
    const workspaceRoot = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? null;
    const payload = {
        scenario,
        status: 'failed',
        generatedAt: new Date().toISOString(),
        workspaceRoot,
        vscodeVersion: vscode.version,
        error: error instanceof Error ? `${error.message}\n${error.stack ?? ''}` : String(error)
    };
    fs.mkdirSync(path.dirname(reportPath), { recursive: true });
    fs.writeFileSync(reportPath, JSON.stringify(payload, null, 2));
}

function requiredEnv(name: string): string {
    const value = process.env[name];
    if (!value) throw new Error(`Missing environment variable ${name}`);
    return value;
}

function sleep(milliseconds: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, milliseconds));
}
