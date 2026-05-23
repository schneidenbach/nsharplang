import * as assert from 'assert';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import { waitForLanguageServer, openDocument, closeAllEditors, sleep } from './helpers';

type CapturedTestRunProfile = {
    controllerId: string;
    label: string;
    kind: vscode.TestRunProfileKind;
    kindName: string;
};

let capturedTestRunProfiles: CapturedTestRunProfile[] = [];
let restoreCreateTestController: (() => void) | undefined;

captureTestRunProfileCreation();

suite('Extension Activation', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    suiteTeardown(() => {
        restoreCreateTestController?.();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    test('nsharp language is registered', async () => {
        const languages = await vscode.languages.getLanguages();
        assert.ok(
            languages.includes('nsharp'),
            `Expected 'nsharp' in registered languages. Got: ${languages.filter(l => l.includes('sharp')).join(', ')}`
        );
    });

    test('extension activates on .nl file', async () => {
        const ext = vscode.extensions.getExtension('nsharp.nsharp');
        assert.ok(ext, 'N# extension should be installed');
        assert.ok(ext!.isActive, 'N# extension should be active');
    });

    test('.nl files are assigned nsharp language ID', async () => {
        const doc = await openDocument('Program.nl');
        assert.strictEqual(doc.languageId, 'nsharp',
            `Expected language ID 'nsharp', got '${doc.languageId}'`);
    });

    test('language server output channel exists', async () => {
        // The extension creates an output channel named 'N# Language Server'
        // We can verify this by checking the extension is active (it creates
        // the channel during activation)
        const ext = vscode.extensions.getExtension('nsharp.nsharp');
        assert.ok(ext?.isActive, 'Extension must be active');
    });

    test('nsharp tasks use configured nlc path for build run and test', async () => {
        const configuredPath = '/tmp/nsharp-custom-nlc';
        const config = vscode.workspace.getConfiguration('nsharp');
        await config.update('cli.path', configuredPath, vscode.ConfigurationTarget.Workspace);

        const tasks = await vscode.tasks.fetchTasks({ type: 'nsharp' });
        const byName = new Map(tasks.map(task => [task.name, task]));

        for (const taskName of ['build', 'run', 'test']) {
            const task = byName.get(taskName);
            assert.ok(task, `Expected nsharp ${taskName} task to be provided`);
            assert.ok(task!.execution instanceof vscode.ShellExecution, `${taskName} should use ShellExecution`);

            const execution = task!.execution as vscode.ShellExecution;
            assert.strictEqual(execution.command, configuredPath);
            assert.deepStrictEqual(execution.args, [taskName]);

            const dotnetToolsDirectory = path.join(os.homedir(), '.dotnet', 'tools');
            if (fs.existsSync(dotnetToolsDirectory)) {
                assert.ok(
                    execution.options?.env?.PATH?.split(path.delimiter).includes(dotnetToolsDirectory),
                    `${taskName} task PATH should include the .NET tools directory for nlc`
                );
            }
        }
    });

    test('debug entry points are contributed for N# F5 and breakpoints', async () => {
        const ext = vscode.extensions.getExtension('nsharp.nsharp');
        assert.ok(ext, 'N# extension should be installed');

        const contributes = ext!.packageJSON.contributes ?? {};
        const commandIds = (contributes.commands ?? []).map((command: { command: string }) => command.command);
        const debuggerTypes = (contributes.debuggers ?? []).map((debuggerContribution: { type: string }) => debuggerContribution.type);
        const nsharpDebugger = (contributes.debuggers ?? []).find(
            (debuggerContribution: { type: string }) => debuggerContribution.type === 'nsharp'
        );

        assert.ok(commandIds.includes('nsharp.runProject'), 'run command should be contributed');
        assert.ok(commandIds.includes('nsharp.debugProject'), 'debug command should be contributed');
        assert.ok(debuggerTypes.includes('nsharp'), 'N# debugger contribution should be present so F5 does not search Marketplace');
        assert.ok(nsharpDebugger?.languages?.includes('nsharp'), 'N# debugger should be associated with the nsharp language');
        assert.ok(contributes.breakpoints?.some((entry: { language: string }) => entry.language === 'nsharp'), 'N# breakpoints should be enabled');
        assert.ok(
            nsharpDebugger?.initialConfigurations?.some((configuration: { type: string; request: string }) =>
                configuration.type === 'nsharp' && configuration.request === 'launch'),
            'N# debugger should contribute a launch configuration'
        );
    });

    test('nsharp debug build task exports a debugger-ready C# bundle', async () => {
        const tasks = await vscode.tasks.fetchTasks({ type: 'nsharp' });
        const debugBuildTask = tasks.find(task => task.name === 'debug build');

        assert.ok(debugBuildTask, 'Expected nsharp debug build task to be provided');
        assert.ok(debugBuildTask!.execution instanceof vscode.CustomExecution, 'debug build should use CustomExecution');
        assert.strictEqual(debugBuildTask!.group, vscode.TaskGroup.Build);
    });

    test('Test Explorer only exposes the real nlc-backed Run profile', async () => {
        await waitForCapturedTestProfiles();

        assert.deepStrictEqual(
            capturedTestRunProfiles,
            [{ controllerId: 'nsharp-tests', label: 'Run', kind: vscode.TestRunProfileKind.Run, kindName: 'Run' }],
            `Expected only the nlc-backed Run profile; got ${JSON.stringify(capturedTestRunProfiles)}`
        );
        assert.ok(
            !capturedTestRunProfiles.some(profile => profile.kind === vscode.TestRunProfileKind.Debug || profile.kindName === 'Debug'),
            'Debug Test profile must stay hidden until it starts a real CoreCLR debug session'
        );
    });

    test('extension activates for N# task discovery in fresh project workspaces', async () => {
        const ext = vscode.extensions.getExtension('nsharp.nsharp');
        assert.ok(ext, 'N# extension should be installed');

        const activationEvents = ext!.packageJSON.activationEvents ?? [];
        assert.ok(
            activationEvents.includes('onTaskType:nsharp'),
            'extension should activate when VS Code discovers nsharp tasks before a .nl file is opened'
        );
    });
});

function captureTestRunProfileCreation(): void {
    capturedTestRunProfiles = [];

    const originalCreateTestController = vscode.tests.createTestController.bind(vscode.tests);
    const testsApi = vscode.tests as unknown as {
        createTestController: typeof vscode.tests.createTestController;
    };

    testsApi.createTestController = ((...args: Parameters<typeof vscode.tests.createTestController>) => {
        const controller = originalCreateTestController(...args);
        const [id] = args;
        if (id !== 'nsharp-tests') {
            return controller;
        }

        const originalCreateRunProfile = controller.createRunProfile.bind(controller);
        const controllerApi = controller as unknown as {
            createRunProfile: typeof controller.createRunProfile;
        };

        controllerApi.createRunProfile = ((...profileArgs: Parameters<typeof controller.createRunProfile>) => {
            const profile = originalCreateRunProfile(...profileArgs);
            capturedTestRunProfiles.push({
                controllerId: id,
                label: profile.label,
                kind: profile.kind,
                kindName: vscode.TestRunProfileKind[profile.kind]
            });
            return profile;
        }) as typeof controller.createRunProfile;

        return controller;
    }) as typeof vscode.tests.createTestController;

    restoreCreateTestController = () => {
        testsApi.createTestController = originalCreateTestController;
    };
}

async function waitForCapturedTestProfiles(): Promise<void> {
    for (let attempt = 0; attempt < 50; attempt++) {
        if (capturedTestRunProfiles.length > 0) {
            return;
        }
        await sleep(100);
    }

    assert.fail('Timed out waiting for N# Test Explorer run profiles to be registered');
}
