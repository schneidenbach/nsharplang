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
    const asyncFixtureArchive = await readFile(new URL('../../artifacts/playground-wasm/async-awaitable-pattern-fixture.zip', import.meta.url));
    wasm.RegisterMetadataReferences(asyncFixtureArchive.toString('base64'));

    const pendingMatrixRows = [
      {id: 'task', gateType: 'TaskCompletionSource<int>', call: (gate) => `ReadTask(${gate}.Task)`, completion: (gate) => `${gate}.SetResult(61)`, result: 61},
      {id: 'decoy', gateType: 'TaskCompletionSource<int>', call: (gate) => `ReadDecoy(${gate}.Task)`, completion: (gate) => `${gate}.SetResult(62)`, result: 62},
      {id: 'inherited', gateType: 'TaskCompletionSource<int>', call: (gate) => `ReadInherited(${gate}.Task)`, completion: (gate) => `${gate}.SetResult(63)`, result: 63},
      {id: 'extension', gateType: 'TaskCompletionSource<int>', call: (gate) => `ReadExtension(${gate}.Task)`, completion: (gate) => `${gate}.SetResult(64)`, result: 64},
      {id: 'genericExtension', gateType: 'TaskCompletionSource<int>', call: (gate) => `ReadConcreteGenericExtension(new CriticalBox<int>(${gate}.Task))`, completion: (gate) => `${gate}.SetResult(65)`, result: 65},
      {id: 'reflectedGenericExtension', gateType: 'ReflectedGenericExtensionBox<int>', call: (gate) => `ReadReflectedGenericExtension(${gate})`, completion: (gate) => `${gate}.Complete(74)`, result: 74},
      {id: 'interfaceAwaiter', gateType: 'TaskCompletionSource<int>', call: (gate) => `ReadInterfaceAwaiter(new InterfaceAwaitable(${gate}.Task))`, completion: (gate) => `${gate}.SetResult(75)`, result: 75},
      {id: 'implicitDecoy', gateType: 'TaskCompletionSource<int>', call: (gate) => `ReadImplicitDecoy(${gate}.Task)`, completion: (gate) => `${gate}.SetResult(66)`, result: 66},
      {id: 'publicExplicit', gateType: 'TaskCompletionSource<int>', call: (gate) => `ReadPublicAndExplicit(${gate}.Task)`, completion: (gate) => `${gate}.SetResult(67)`, result: 67},
      {id: 'configured', gateType: 'TaskCompletionSource<int>', call: (gate) => `ReadConfigured(${gate}.Task)`, completion: (gate) => `${gate}.SetResult(68)`, result: 68},
      {id: 'inheritedInterface', gateType: 'TaskCompletionSource<int>', call: (gate) => `ReadInheritedInterface(new InheritedInterfaceAwaitable(${gate}.Task))`, completion: (gate) => `${gate}.SetResult(72)`, result: 72},
      {id: 'plainTask', gateType: 'TaskCompletionSource', call: (gate) => `ReadPlainTask(${gate}.Task)`, completion: (gate) => `${gate}.SetResult()`, result: 69},
      {id: 'unitValueTask', gateType: 'TaskCompletionSource', call: (gate) => `ReadUnitValueTask(new ValueTask(${gate}.Task))`, completion: (gate) => `${gate}.SetResult()`, result: 70},
      {id: 'valueTask', gateType: 'TaskCompletionSource<int>', call: (gate) => `ReadGenericValueTask(new ValueTask<int>(${gate}.Task))`, completion: (gate) => `${gate}.SetResult(73)`, result: 73},
    ];
    const pendingMatrixMain = [
      'async func main() {',
      ...pendingMatrixRows.map(({id, gateType}) => `    ${id}Gate := new ${gateType}`),
      ...pendingMatrixRows.map(({id, call}) => `    ${id}Task := ${call(`${id}Gate`)}`),
      ...pendingMatrixRows.map(({id}) => `    if ${id}Task.IsCompleted { throw new Exception("${id} matrix row did not suspend") }`),
      ...pendingMatrixRows.map(({id, completion}) => `    ${completion(`${id}Gate`)}`),
      ...pendingMatrixRows.map(({id}) => `    print await ${id}Task`),
      '}',
    ].join('\n');

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
        name: 'pending awaiter binding matrix across source and referenced shapes',
        source: `import System
import System.Runtime.CompilerServices
import System.Threading.Tasks
import NSharpLang.AsyncAwaitablePatternFixtures

interface WrongCompletion {
    func OnCompleted(continuation: object)
}

interface EarlierCompletion {
    func OnCompleted(continuation: Action)
}

class DecoyAwaitable(source: Task<int>) {
    func GetAwaiter(): DecoyAwaiter { return new DecoyAwaiter(source) }
}

interface InterfaceAwaiter: INotifyCompletion {
    IsCompleted: bool
    func GetResult(): int
}

class InterfaceAwaiterImplementation(source: Task<int>): InterfaceAwaiter {
    IsCompleted: bool { get { return source.IsCompleted } }
    func GetResult(): int { return source.GetAwaiter().GetResult() }
    func OnCompleted(continuation: Action) { source.GetAwaiter().OnCompleted(continuation) }
}

class InterfaceAwaitable(source: Task<int>) {
    func GetAwaiter(): InterfaceAwaiter { return new InterfaceAwaiterImplementation(source) }
}

class DecoyAwaiter(source: Task<int>): EarlierCompletion, WrongCompletion, INotifyCompletion {
    IsCompleted: bool { get { return source.IsCompleted } }
    func GetResult(): int { return source.GetAwaiter().GetResult() }
    func EarlierCompletion.OnCompleted(_continuation: Action) { }
    func OnCompleted(_continuation: object) { }
    func WrongCompletion.OnCompleted(_continuation: object) { }
    func INotifyCompletion.OnCompleted(continuation: Action) {
        source.GetAwaiter().OnCompleted(continuation)
    }
}

class ImplicitDecoyAwaiter(source: Task<int>): INotifyCompletion {
    IsCompleted: bool { get { return source.IsCompleted } }
    func GetResult(): int { return source.GetAwaiter().GetResult() }
    func OnCompleted(_continuation: object) { }
    func OnCompleted(continuation: Action) { source.GetAwaiter().OnCompleted(continuation) }
}

class ImplicitDecoyAwaitable(source: Task<int>) {
    func GetAwaiter(): ImplicitDecoyAwaiter { return new ImplicitDecoyAwaiter(source) }
}

class PublicAndExplicitAwaiter(source: Task<int>): INotifyCompletion {
    IsCompleted: bool { get { return source.IsCompleted } }
    func GetResult(): int { return source.GetAwaiter().GetResult() }
    func OnCompleted(_continuation: Action) { }
    func INotifyCompletion.OnCompleted(continuation: Action) {
        source.GetAwaiter().OnCompleted(continuation)
    }
}

class PublicAndExplicitAwaitable(source: Task<int>) {
    func GetAwaiter(): PublicAndExplicitAwaiter { return new PublicAndExplicitAwaiter(source) }
}

class BaseAwaiter: INotifyCompletion {
    func OnCompleted(continuation: Action) { Register(continuation) }
    virtual func Register(_continuation: Action) {}
}

class InheritedAwaiter(source: Task<int>): BaseAwaiter {
    IsCompleted: bool { get { return source.IsCompleted } }
    func GetResult(): int { return source.GetAwaiter().GetResult() }
    override func Register(continuation: Action) { source.GetAwaiter().OnCompleted(continuation) }
}

class InheritedAwaitable(source: Task<int>) {
    func GetAwaiter(): InheritedAwaiter { return new InheritedAwaiter(source) }
}

interface ResumableCompletion: INotifyCompletion {}

class InheritedInterfaceAwaiter(source: Task<int>): ResumableCompletion {
    IsCompleted: bool { get { return source.IsCompleted } }
    func GetResult(): int { return source.GetAwaiter().GetResult() }
    func OnCompleted(_continuation: Action) { }
    func INotifyCompletion.OnCompleted(continuation: Action) {
        source.GetAwaiter().OnCompleted(continuation)
    }
}

class InheritedInterfaceAwaitable(source: Task<int>) {
    func GetAwaiter(): InheritedInterfaceAwaiter { return new InheritedInterfaceAwaiter(source) }
}

class ExtensionBox(source: Task<int>) {
    Source: Task<int> { get { return source } }
}

class ExtensionAwaiter(source: Task<int>): INotifyCompletion {
    IsCompleted: bool { get { return source.IsCompleted } }
    func GetResult(): int { return source.GetAwaiter().GetResult() }
    func OnCompleted(continuation: Action) { source.GetAwaiter().OnCompleted(continuation) }
}

func GetAwaiter(this value: ExtensionBox): ExtensionAwaiter {
    return new ExtensionAwaiter(value.Source)
}

class CriticalBox<T>(source: Task<T>) {
    Source: Task<T> { get { return source } }
}

class CriticalAwaiter<T>(source: Task<T>): ICriticalNotifyCompletion {
    IsCompleted: bool { get { return source.IsCompleted } }
    func GetResult(): T { return source.GetAwaiter().GetResult() }
    func OnCompleted(continuation: Action) { source.GetAwaiter().OnCompleted(continuation) }
    func UnsafeOnCompleted(continuation: Action) { source.GetAwaiter().UnsafeOnCompleted(continuation) }
}

func GetAwaiter<T>(this value: CriticalBox<T>): CriticalAwaiter<T> {
    return new CriticalAwaiter<T>(value.Source)
}

async func ReadTask(source: Task<int>): Task<int> { return await source }
async func ReadInterfaceAwaiter(source: InterfaceAwaitable): Task<int> { return await source }
async func ReadReflectedGenericExtension(source: ReflectedGenericExtensionBox<int>): Task<int> { return await source }
async func ReadDecoy(source: Task<int>): Task<int> { return await new DecoyAwaitable(source) }
async func ReadInherited(source: Task<int>): Task<int> { return await new InheritedAwaitable(source) }
async func ReadInheritedInterface(source: InheritedInterfaceAwaitable): Task<int> { return await source }
async func ReadExtension(source: Task<int>): Task<int> {
    return await new ExtensionBox(source)
}
async func ReadGenericExtension<T>(source: Task<T>): Task<T> {
    return await new CriticalBox<T>(source)
}
async func ReadConcreteGenericExtension(value: CriticalBox<int>): Task<int> {
    return await value
}
async func ReadImplicitDecoy(source: Task<int>): Task<int> {
    return await new ImplicitDecoyAwaitable(source)
}
async func ReadPublicAndExplicit(source: Task<int>): Task<int> {
    return await new PublicAndExplicitAwaitable(source)
}
async func ReadConfigured(source: Task<int>): Task<int> {
    return await source.ConfigureAwait(false)
}
async func ReadPlainTask(source: Task): Task<int> {
    await source
    return 69
}
async func ReadUnitValueTask(source: ValueTask): Task<int> {
    await source
    return 70
}
async func ReadGenericValueTask(source: ValueTask<int>): Task<int> {
    return await source
}

${pendingMatrixMain}
`,
        stdout: pendingMatrixRows.map(({result}) => `${result}\n`).join(''),
        timeoutMs: 5000,
      },
      {
        name: 'reflected TaskAwaiter completion interface map',
        source: `import System
import System.Threading.Tasks

async func ReadTask(source: Task<int>): Task<int> {
    return await source
}

async func main() {
    gate := new TaskCompletionSource<int>
    pending := ReadTask(gate.Task)
    if pending.IsCompleted { throw new Exception("reflected await did not suspend") }
    gate.SetResult(45)
    print await pending
}
`,
        stdout: '45\n',
        timeoutMs: 5000,
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
        name: 'explicit INotifyCompletion slot wins over an earlier unrelated OnCompleted',
        source: `import System
import System.Runtime.CompilerServices
import System.Threading.Tasks

interface EarlierCompletion {
    func OnCompleted(continuation: Action)
}

class OrderedAwaitable(source: Task<int>) {
    func GetAwaiter(): OrderedAwaiter {
        return new OrderedAwaiter(source)
    }
}

class OrderedAwaiter(source: Task<int>): EarlierCompletion, INotifyCompletion {
    IsCompleted: bool {
        get { return source.IsCompleted }
    }

    func GetResult(): int {
        return source.GetAwaiter().GetResult()
    }

    func EarlierCompletion.OnCompleted(_continuation: Action) {
    }

    func INotifyCompletion.OnCompleted(continuation: Action) {
        source.GetAwaiter().OnCompleted(continuation)
    }
}

async func DelayWork(): Task<int> {
    await Task.Yield()
    return 44
}

async func main() {
    print await new OrderedAwaitable(DelayWork())
}
`,
        stdout: '44\n',
        timeoutMs: 5000,
      },
      {
        name: 'explicit INotifyCompletion slot wins over a public same-name no-op',
        source: `import System
import System.Runtime.CompilerServices
import System.Threading.Tasks

class PublicAndExplicitAwaitable(source: Task<int>) {
    func GetAwaiter(): PublicAndExplicitAwaiter {
        return new PublicAndExplicitAwaiter(source)
    }
}

class PublicAndExplicitAwaiter(source: Task<int>): INotifyCompletion {
    IsCompleted: bool {
        get { return source.IsCompleted }
    }

    func GetResult(): int {
        return source.GetAwaiter().GetResult()
    }

    func OnCompleted(_continuation: Action) {
    }

    func INotifyCompletion.OnCompleted(continuation: Action) {
        source.GetAwaiter().OnCompleted(continuation)
    }
}

async func DelayWork(): Task<int> {
    await Task.Yield()
    return 45
}

async func main() {
    print await new PublicAndExplicitAwaitable(DelayWork())
}
`,
        stdout: '45\n',
        timeoutMs: 5000,
      },
      {
        name: 'source interface inheritance carries the INotifyCompletion slot closure',
        source: `import System
import System.Runtime.CompilerServices
import System.Threading.Tasks

interface ResumableCompletion: INotifyCompletion {}

class InheritedInterfaceAwaitable(source: Task<int>) {
    func GetAwaiter(): InheritedInterfaceAwaiter {
        return new InheritedInterfaceAwaiter(source)
    }
}

class InheritedInterfaceAwaiter(source: Task<int>): ResumableCompletion {
    IsCompleted: bool {
        get { return source.IsCompleted }
    }

    func GetResult(): int {
        return source.GetAwaiter().GetResult()
    }

    func OnCompleted(_continuation: Action) {
    }

    func INotifyCompletion.OnCompleted(continuation: Action) {
        source.GetAwaiter().OnCompleted(continuation)
    }
}

async func DelayWork(): Task<int> {
    await Task.Yield()
    return 46
}

async func main() {
    print await new InheritedInterfaceAwaitable(DelayWork())
}
`,
        stdout: '46\n',
        timeoutMs: 5000,
      },
      {
        name: 'generic extension GetAwaiter uses receiver inference',
        source: `import System
import System.Runtime.CompilerServices
import System.Threading.Tasks

class GenericBox<T>(source: Task<T>) {
    Source: Task<T> { get { return source } }
}

class GenericBoxAwaiter<T>(source: Task<T>): ICriticalNotifyCompletion {
    IsCompleted: bool { get { return source.IsCompleted } }
    func GetResult(): T { return source.GetAwaiter().GetResult() }
    func OnCompleted(continuation: Action) { source.GetAwaiter().OnCompleted(continuation) }
    func UnsafeOnCompleted(continuation: Action) { source.GetAwaiter().UnsafeOnCompleted(continuation) }
}

func GetAwaiter<T>(this value: GenericBox<T>): GenericBoxAwaiter<T> {
    return new GenericBoxAwaiter<T>(value.Source)
}

async func main() {
    gate := new TaskCompletionSource<int>
    pending := ReadGenericBox(new GenericBox<int>(gate.Task))
    if pending.IsCompleted { throw new Exception("generic extension did not suspend") }
    gate.SetResult(47)
    print await pending
}

async func ReadGenericBox(value: GenericBox<int>): Task<int> { return await value }
`,
        stdout: '47\n',
        timeoutMs: 5000,
      },
      {
        name: 'ConfigureAwait(false)',
        source: `import System
import System.Threading.Tasks

async func ReadConfigured(source: Task<int>): Task<int> {
    return await source.ConfigureAwait(false)
}

async func main() {
    gate := new TaskCompletionSource<int>
    pending := ReadConfigured(gate.Task)
    if pending.IsCompleted { throw new Exception("ConfigureAwait(false) did not suspend") }
    gate.SetResult(48)
    print await pending
}
`,
        stdout: '48\n',
        timeoutMs: 5000,
      },
      {
        name: 'ValueTask.ConfigureAwait(false)',
        source: `import System
import System.Threading.Tasks

async func ReadValueConfigured(source: ValueTask<int>): Task<int> {
    return await source.ConfigureAwait(false)
}

async func main() {
    gate := new TaskCompletionSource<int>
    value := new ValueTask<int>(gate.Task)
    pending := ReadValueConfigured(value)
    if pending.IsCompleted { throw new Exception("ValueTask ConfigureAwait(false) did not suspend") }
    gate.SetResult(49)
    print await pending
}
`,
        stdout: '49\n',
        timeoutMs: 5000,
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
        name: 'pending await in try, catch, and finally',
        source: `import System
import System.Threading.Tasks

async func ReadProtected(source: Task<int>, catchGate: Task<int>, finallyGate: Task): Task<int> {
    total := 0
    try {
        total = await source
        throw new Exception("enter catch")
    } catch error: Exception {
        total += await catchGate
    } finally {
        await finallyGate
        total += 1
    }
    return total
}

async func main() {
    sourceGate := new TaskCompletionSource<int>
    catchGate := new TaskCompletionSource<int>
    finallyGate := new TaskCompletionSource
    protectedTask := ReadProtected(sourceGate.Task, catchGate.Task, finallyGate.Task)
    if protectedTask.IsCompleted { throw new Exception("try await did not suspend") }
    sourceGate.SetResult(10)
    if protectedTask.IsCompleted { throw new Exception("catch await did not suspend") }
    catchGate.SetResult(31)
    if protectedTask.IsCompleted { throw new Exception("finally await did not suspend") }
    finallyGate.SetResult()
    print await protectedTask
}
`,
        stdout: '42\n',
        timeoutMs: 5000,
      },
      {
        name: 'pending nested awaits and awaited arguments',
        source: `import System
import System.Threading.Tasks

func Add(left: int, right: int): int { return left + right }

async func ReadNested(first: Task<int>, second: Task<int>, secondStarted: TaskCompletionSource): Task<int> {
    left := await first
    secondStarted.SetResult()
    return Add(left, Add(await second, 1))
}

async func main() {
    firstGate := new TaskCompletionSource<int>
    secondGate := new TaskCompletionSource<int>
    secondStarted := new TaskCompletionSource
    nested := ReadNested(firstGate.Task, secondGate.Task, secondStarted)
    if nested.IsCompleted { throw new Exception("nested await did not suspend") }
    firstGate.SetResult(20)
    await secondStarted.Task
    if nested.IsCompleted { throw new Exception("second nested await did not suspend") }
    secondGate.SetResult(21)
    print await nested
}
`,
        stdout: '42\n',
        timeoutMs: 5000,
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
        const run = wasm.RunProject(JSON.stringify([
          {name: 'Program.nl', code: scenario.source},
        ]), 'Program.nl');
        if (scenario.timeoutMs) {
          let timer;
          responseText = await Promise.race([
            run,
            new Promise((_, reject) => {
              timer = setTimeout(() => reject(new Error(`${scenario.name} timed out`)), scenario.timeoutMs);
            }),
          ]).finally(() => clearTimeout(timer));
        } else {
          responseText = await run;
        }
      } catch (error) {
        assert.fail(`${scenario.name}: WASM execution threw ${String(error)} (${error?.stack ?? 'no stack'})`);
      }
      const response = JSON.parse(responseText);
      assert.equal(response.ok, true, `${scenario.name}: ${JSON.stringify(response)}`);
      assert.equal(response.exitCode, 0, scenario.name);
      assert.equal(response.stdout, scenario.stdout, scenario.name);
      assert.equal(response.stderr, null, scenario.name);
      assert.equal(response.unsupportedReason, null, scenario.name);
    }

    const invalidCases = [
      {
        name: 'public OnCompleted without INotifyCompletion',
        source: `import System.Threading.Tasks

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
`,
      },
      {
        name: 'generic-only GetAwaiter',
        source: `import System.Runtime.CompilerServices

class InvalidAwaitable {
    func GetAwaiter<T>(): InvalidAwaiter { return new InvalidAwaiter() }
}

class InvalidAwaiter: INotifyCompletion {
    IsCompleted: bool { get { return true } }
    func GetResult(): int { return 2 }
    func OnCompleted(continuation: System.Action) { continuation() }
}

async func main() {
    print await new InvalidAwaitable()
}
`,
      },
      {
        name: 'generic-only GetResult',
        source: `import System.Runtime.CompilerServices

class InvalidAwaitable {
    func GetAwaiter(): InvalidAwaiter { return new InvalidAwaiter() }
}

class InvalidAwaiter: INotifyCompletion {
    IsCompleted: bool { get { return true } }
    func GetResult<T>(): int { return 3 }
    func OnCompleted(continuation: System.Action) { continuation() }
}

async func main() {
    print await new InvalidAwaitable()
}
`,
      },
      {
        name: 'private source awaiter members',
        source: `import System.Runtime.CompilerServices

class InvalidAwaitable {
    func GetAwaiter(): InvalidAwaiter { return new InvalidAwaiter() }
}

class InvalidAwaiter: INotifyCompletion {
    private IsCompleted: bool { get { return true } }
    private func GetResult(): int { return 4 }
    func OnCompleted(continuation: System.Action) { continuation() }
}

async func main() {
    print await new InvalidAwaitable()
}
`,
      },
      {
        name: 'nullable value type does not lift GetAwaiter',
        source: `import System
import System.Runtime.CompilerServices

struct NullableAwaitable {
    func GetAwaiter(): NullableAwaiter { return new NullableAwaiter() }
}

struct NullableAwaiter: INotifyCompletion {
    IsCompleted: bool { get { return true } }
    func GetResult(): int { return 5 }
    func OnCompleted(continuation: Action) { continuation() }
}

async func main(value: Nullable<NullableAwaitable>) {
    await value
}
`,
      },
      {
        name: 'applicable instance GetAwaiter blocks extension fallback',
        source: `import System
import System.Runtime.CompilerServices

class ExtensionAwaiter: INotifyCompletion {
    IsCompleted: bool { get { return true } }
    func GetResult(): int { return 99 }
    func OnCompleted(continuation: Action) { continuation() }
}

class InvalidInstanceAwaitable {
    func GetAwaiter(): int { return 0 }
}

func GetAwaiter(this _value: InvalidInstanceAwaitable): ExtensionAwaiter {
    return new ExtensionAwaiter()
}

async func main() {
    print await new InvalidInstanceAwaitable()
}
`,
      },
    ];
    for (const invalidCase of invalidCases) {
      const invalidText = await wasm.RunProject(JSON.stringify([
        {name: 'Program.nl', code: invalidCase.source},
      ]), 'Program.nl');
      const invalidResponse = JSON.parse(invalidText);
      assert.equal(invalidResponse.ok, false, `${invalidCase.name} must be rejected: ${JSON.stringify(invalidResponse.diagnostics)}`);
      assert.ok(invalidResponse.diagnostics.some((diagnostic) => diagnostic.line > 0 && diagnostic.column > 0),
        `${invalidCase.name}: ${JSON.stringify(invalidResponse.diagnostics)}`);
    }
  } finally {
    globalThis.fetch = nativeFetch;
  }
});
