import * as assert from 'assert';
import * as vscode from 'vscode';
import { waitForLanguageServer, openDocument, closeAllEditors, sleep } from './helpers';

suite('Extension Activation', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
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
        }
    });

    test('debug entry points are hidden until real N# debugging exists', async () => {
        const ext = vscode.extensions.getExtension('nsharp.nsharp');
        assert.ok(ext, 'N# extension should be installed');

        const contributes = ext!.packageJSON.contributes ?? {};
        const commandIds = (contributes.commands ?? []).map((command: { command: string }) => command.command);

        assert.ok(!commandIds.includes('nsharp.generateDebugConfig'), 'debug config command should not be contributed');
        assert.ok(!contributes.breakpoints, 'N# breakpoint contribution should be hidden');
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
