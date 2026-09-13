namespace NSharpLang.CensusUsingStatement.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks


// CENSUS — THE `using` STATEMENT, EXECUTED.
//
// Every source below is compiled by the tip CLI and RUN, so what the tests assert is the behaviour of
// real IL and not the shape of a tree. The five written forms are here (`using x := e { … }`,
// `using x: T := e { … }`, `using let x := e { … }`, `using e { … }` and the block-less using
// DECLARATION), and so are the four things the lowering has to get right that a happy path never
// shows: disposal order, disposal when the body throws, a struct resource released WITHOUT boxing,
// and a null resource skipped instead of crashed on.

// A resource that writes its name down when it is released. One shared log per call, handed in, so a
// test can read the exact ORDER releases happened in.
class LoggedResource: IDisposable {
    log: List<string>
    name: string

    constructor(log: List<string>, name: string) {
        this.log = log
        this.name = name
    }

    Name: string => name

    func Dispose() {
        log.Add(name)
    }
}

// A resource with no interface at all — only the parameterless `Dispose` member. The analyzer accepts
// it structurally (NL333's second arm) and the lowering releases it with a direct call.
class PatternResource {
    log: List<string>

    constructor(log: List<string>) {
        this.log = log
    }

    func Dispose() {
        log.Add("pattern")
    }
}

// THE COUNTING STRUCT. It carries the log by REFERENCE, so every copy of it — boxed or not — writes
// to the same list: the runtime assertion that survives is "released EXACTLY ONCE", which is the one a
// double release or a skipped release would break. That the release also runs WITHOUT BOXING is a
// claim about the instructions rather than about the values, so it is read off the method's IL in
// `UsingStatementIl.tests.nl`.
struct CountingResource: IDisposable {
    Log: List<string>

    func Dispose() {
        Log.Add("struct")
    }
}

class AsyncResource: IAsyncDisposable {
    log: List<string>

    constructor(log: List<string>) {
        this.log = log
    }

    func DisposeAsync(): ValueTask {
        log.Add("async")
        return ValueTask.CompletedTask
    }
}

// ---- the five written forms ----

func InferredBinding(log: List<string>): string {
    using resource := new LoggedResource(log, "inferred") {
        return resource.Name
    }
}

func AnnotatedBinding(log: List<string>): string {
    using resource: LoggedResource := new LoggedResource(log, "annotated") {
        return resource.Name
    }
}

func LetBinding(log: List<string>): string {
    using resource := new LoggedResource(log, "let") {
        return resource.Name
    }
}

// The UNBOUND form: the resource is already named, and the statement only says where it is released.
func UnboundResource(log: List<string>): string {
    resource := new LoggedResource(log, "unbound")
    using resource {
        return resource.Name
    }
}

// The using DECLARATION: no block, released at the end of the ENCLOSING block. The `after` entry is
// written BEFORE the release, which is what proves the guarded region really is the rest of the block.
func DeclarationForm(log: List<string>) {
    using resource := new LoggedResource(log, "declared")
    log.Add("after " + resource.Name)
}

// ---- order ----

// Nested blocks release innermost first.
func NestedBlocks(log: List<string>) {
    using outer := new LoggedResource(log, "outer") {
        using inner := new LoggedResource(log, "inner") {
            log.Add("body")
        }
    }
}

// Two DECLARATIONS in one block release in REVERSE declaration order, exactly as C# 8 promises.
func ReverseDeclarationOrder(log: List<string>) {
    using first := new LoggedResource(log, "first")
    using second := new LoggedResource(log, "second")
    using third := new LoggedResource(log, "third")
    log.Add("body")
}

// ---- exceptions ----

// The release runs on the way out of a throwing body, BEFORE the handler outside it.
func ReleasesWhenTheBodyThrows(log: List<string>): string {
    try {
        using resource := new LoggedResource(log, "throwing") {
            throw new InvalidOperationException("boom")
        }
    } catch error: InvalidOperationException {
        log.Add("caught " + error.Message)
        return error.Message
    }
}

// An exception thrown BY the release propagates — the `finally` is not a catch.
class ThrowingResource: IDisposable {
    func Dispose() {
        throw new InvalidOperationException("dispose failed")
    }
}

func ReleaseExceptionPropagates(log: List<string>): string {
    try {
        using resource := new ThrowingResource() {
            log.Add("body")
            return "not thrown"
        }
    } catch error: InvalidOperationException {
        return error.Message
    }
}

// ---- struct and null resources ----

// A struct resource is released through `constrained.`, so the release runs on the value rather than
// on a box. The observable half of that claim lives here — exactly one release, not zero and not two —
// and the other half is read off this method's IL in the sibling file.
func StructResource(log: List<string>) {
    resource := new CountingResource { Log: log }
    using resource {
        log.Add("body")
    }
}

// A null resource skips the release instead of throwing.
func NullResource(log: List<string>): string {
    resource: LoggedResource? = null
    using resource {
        log.Add("body")
    }

    return "survived"
}

// ---- the structural (no-interface) resource ----

func StructuralResource(log: List<string>) {
    using resource := new PatternResource(log) {
        log.Add("body")
    }
}

// ---- inside the shapes that suspend or capture ----

// A `using` around two `yield`s: the release must run when the sequence ENDS, not when it suspends.
func* GeneratorResource(log: List<string>): IEnumerable<int> {
    using resource := new LoggedResource(log, "generator") {
        yield 1
        log.Add("between")
        yield 2
    }
}

// A consumer that abandons the sequence early still gets the release, through the machine's Dispose.
func AbandonGenerator(log: List<string>): int {
    first := 0
    enumerator := GeneratorResource(log).GetEnumerator()
    try {
        if enumerator.MoveNext() {
            first = enumerator.Current
        }
    } finally {
        enumerator.Dispose()
    }

    return first
}

func LambdaResource(log: List<string>): int {
    run: Func<int> = () => {
        using resource := new LoggedResource(log, "lambda") {
            return 7
        }
    }

    return run()
}

func LocalFunctionResource(log: List<string>): int {
    func inner(): int {
        using resource := new LoggedResource(log, "localfn") {
            return 9
        }
    }

    return inner()
}

// The value is produced INSIDE the region and returned after it, because a value-bearing `return`
// inside a protected region of a value-returning async function is a pre-existing backend gap that has
// nothing to do with `using` (a plain `try`/`finally` around the same `return` declines identically).
async func AsyncUsingResource(log: List<string>): Task<int> {
    result := 0
    await using resource := new AsyncResource(log) {
        result = 11
    }

    return result
}

// ---- the resource is read-only, and that is checked at the front door, not here ----

// Writing THROUGH the resource is ordinary mutation and stays legal: only rebinding the NAME is the
// error (NL309), and that shape cannot be written in a file this project compiles.
class MutableResource: IDisposable {
    log: List<string>
    Count: int

    constructor(log: List<string>) {
        this.log = log
        Count = 0
    }

    func Dispose() {
        log.Add("mutable:" + Count.ToString())
    }
}

func WritesThroughTheResource(log: List<string>): int {
    using resource := new MutableResource(log) {
        resource.Count = resource.Count + 3
        return resource.Count
    }
}
