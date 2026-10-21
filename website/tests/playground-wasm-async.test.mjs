import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {fileURLToPath} from 'node:url';

test('the WebAssembly playground executes async awaiter shapes with runtime semantics', async () => {
  const nativeFetch = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    const url = input instanceof URL ? input : new URL(input);
    if (url.protocol !== 'file:') return nativeFetch(input, init);

    return new Response(await readFile(fileURLToPath(url)), {status: 200});
  };

  try {
    await import('../static/playground/wasm/main.js');
    const wasm = globalThis.NSharpPlaygroundWasm;
    assert.ok(wasm, 'the WASM module exports were initialized');
    const referenceArchive = await readFile(new URL('../static/playground/wasm/references.zip', import.meta.url));
    wasm.RegisterMetadataReferences(referenceArchive.toString('base64'));

    const cases = [
      {
        name: 'Task and Task<T>',
        source: `import System.Threading.Tasks

async func ReadTask(): Task<int> {
    return await Task.FromResult(40)
}

async func main() {
    await Task.Yield()
    print await ReadTask()
}
`,
        stdout: '40\n',
      },
      {
        name: 'ValueTask and ValueTask<T>',
        source: `import System.Threading.Tasks

async func ReadValueTask(): ValueTask<int> {
    await Task.Yield()
    return 41
}

async func PauseValueTask(): ValueTask {
    await Task.Yield()
}

async func main() {
    await PauseValueTask()
    print await ReadValueTask()
}
`,
        stdout: '41\n',
      },
      {
        name: 'custom ICriticalNotifyCompletion awaiter',
        source: `import System
import System.Runtime.CompilerServices
import System.Threading.Tasks

class CriticalAwaitable(source: Task<int>) {
    func GetAwaiter(): CriticalAwaiter {
        return new CriticalAwaiter(source)
    }
}

class CriticalAwaiter(source: Task<int>): ICriticalNotifyCompletion {
    IsCompleted: bool {
        get { return source.IsCompleted }
    }

    func GetResult(): int {
        return source.GetAwaiter().GetResult()
    }

    func OnCompleted(continuation: Action) {
        source.GetAwaiter().OnCompleted(continuation)
    }

    func UnsafeOnCompleted(continuation: Action) {
        source.GetAwaiter().UnsafeOnCompleted(continuation)
    }
}

async func DelayWork(): Task<int> {
    await Task.Yield()
    return 42
}

async func main() {
    print await new CriticalAwaitable(DelayWork())
}
`,
        stdout: '42\n',
      },
      {
        name: 'custom explicit INotifyCompletion awaiter',
        source: `import System
import System.Runtime.CompilerServices
import System.Threading.Tasks

class NotifyAwaitable(source: Task<int>) {
    func GetAwaiter(): NotifyAwaiter {
        return new NotifyAwaiter(source)
    }
}

class NotifyAwaiter(source: Task<int>): INotifyCompletion {
    IsCompleted: bool {
        get { return source.IsCompleted }
    }

    func GetResult(): int {
        return source.GetAwaiter().GetResult()
    }

    func INotifyCompletion.OnCompleted(continuation: Action) {
        source.GetAwaiter().OnCompleted(continuation)
    }
}

async func DelayWork(): Task<int> {
    await Task.Yield()
    return 43
}

async func main() {
    print await new NotifyAwaitable(DelayWork())
}
`,
        stdout: '43\n',
      },
      {
        name: 'ConfigureAwait(false)',
        source: `import System.Threading.Tasks

async func main() {
    await Task.FromResult(1).ConfigureAwait(false)
    print "configured"
}
`,
        stdout: 'configured\n',
      },
      {
        name: 'ValueTask.ConfigureAwait(false)',
        source: `import System.Threading.Tasks

async func main() {
    await ValueTask.CompletedTask.ConfigureAwait(false)
    print "value configured"
}
`,
        stdout: 'value configured\n',
      },
      {
        name: 'Task.Yield',
        source: `import System.Threading.Tasks

async func main() {
    await Task.Yield()
    print "yielded"
}
`,
        stdout: 'yielded\n',
      },
      {
        name: 'await in catch and finally',
        source: `import System
import System.Threading.Tasks

async func Protected(): Task<int> {
    value := 0
    try {
        await Task.Yield()
        throw new Exception("boom")
    } catch error: Exception {
        await Task.Yield()
        value = 40
    } finally {
        await Task.CompletedTask
        value += 2
    }
    return value
}

async func main() {
    print await Protected()
}
`,
        stdout: '42\n',
      },
      {
        name: 'nested awaits and awaits in arguments',
        source: `import System.Threading.Tasks

func AddOne(value: int): int {
    return value + 1
}

async func main() {
    print AddOne(await Task.FromResult(await Task.FromResult(40)))
}
`,
        stdout: '41\n',
      },
    ];

    for (const scenario of cases) {
      let responseText;
      try {
        responseText = await wasm.RunProject(JSON.stringify([
          {name: 'Program.nl', code: scenario.source},
        ]), 'Program.nl');
      } catch (error) {
        assert.fail(`${scenario.name}: WASM execution threw ${String(error)} (${error?.stack ?? 'no stack'})`);
      }
      const response = JSON.parse(responseText);
      assert.equal(response.ok, true, `${scenario.name}: ${JSON.stringify(response.diagnostics)}`);
      assert.equal(response.exitCode, 0, scenario.name);
      assert.equal(response.stdout, scenario.stdout, scenario.name);
      assert.equal(response.stderr, null, scenario.name);
      assert.equal(response.unsupportedReason, null, scenario.name);
    }

    const invalid = `import System.Threading.Tasks

class InvalidAwaitable {
    func GetAwaiter(): InvalidAwaiter { return new InvalidAwaiter() }
}

class InvalidAwaiter {
    IsCompleted: bool { get { return true } }
    func GetResult(): int { return 1 }
    func OnCompleted(continuation: System.Action) {}
}

async func main() {
    print await new InvalidAwaitable()
}
`;
    const invalidText = await wasm.RunProject(JSON.stringify([
      {name: 'Program.nl', code: invalid},
    ]), 'Program.nl');
    const invalidResponse = JSON.parse(invalidText);
    assert.equal(invalidResponse.ok, false, 'non-implementing OnCompleted methods must not pass analysis');
    assert.ok(invalidResponse.diagnostics.some((diagnostic) => diagnostic.line > 0 && diagnostic.column > 0),
      JSON.stringify(invalidResponse.diagnostics));
  } finally {
    globalThis.fetch = nativeFetch;
  }
});
