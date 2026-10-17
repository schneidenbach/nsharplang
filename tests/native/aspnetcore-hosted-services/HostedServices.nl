namespace NSharpLang.AspNetCoreHostedServices

import System
import System.Threading
import System.Threading.Tasks
import Microsoft.AspNetCore.Http
import Microsoft.Extensions.Hosting

// THE SHAPES A WEB TEMPLATE'S USER UNIT-TESTS, declared against the ASP.NET Core shared framework.
//
// Nothing here is copied into the test output: `framework: Microsoft.AspNetCore.App` is resolved to
// `<dotnet>/shared/Microsoft.AspNetCore.App/<version>/`, and `nlc test` has to bind these base types
// from that directory at run time exactly as the build bound them at compile time.

// A worker that ticks until its host asks it to stop. `ReachedTarget` completes on the tick that
// meets the target, so a test waits on the worker rather than on a clock; since .NET 10
// `BackgroundService.StartAsync` runs `ExecuteAsync` on the thread pool, so nothing about the
// first tick is synchronous with `StartAsync`.
class TickingWorker: BackgroundService {
    private ticks: int
    private stopObserved: bool
    private target: int
    private reached: TaskCompletionSource<int>

    constructor(target: int) {
        this.target = target
        reached = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    }

    Ticks: int => Volatile.Read(ref ticks)
    StopObserved: bool => Volatile.Read(ref stopObserved)
    ReachedTarget: Task<int> => reached.Task

    protected override async func ExecuteAsync(stoppingToken: CancellationToken): Task {
        try {
            while true {
                current := Interlocked.Increment(ref ticks)
                if current == target {
                    reached.TrySetResult(current)
                }

                await Task.Delay(1, stoppingToken)
            }
        } catch _canceled: OperationCanceledException {
            Volatile.Write(ref stopObserved, true)
        }
    }
}

// The singleton a hosted service reports to, so a test can observe a worker the HOST constructed.
class StartupProbe {
    private started: TaskCompletionSource<string>

    constructor() {
        started = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously)
    }

    Started: Task<string> => started.Task

    func Report(message: string) {
        started.TrySetResult(message)
    }
}

// Registered with `AddHostedService<T>()`: the host activates it through dependency injection.
class ProbeWorker: BackgroundService {
    private probe: StartupProbe

    constructor(probe: StartupProbe) {
        this.probe = probe
    }

    protected override async func ExecuteAsync(stoppingToken: CancellationToken): Task {
        probe.Report("started by the host")
        await Task.Delay(Timeout.Infinite, stoppingToken).ContinueWith(_completed => { })
    }
}

// A conventional middleware: a `RequestDelegate` constructor and an `InvokeAsync(HttpContext)`.
class RequestStampMiddleware {
    private next: RequestDelegate

    constructor(next: RequestDelegate) {
        this.next = next
    }

    async func InvokeAsync(context: HttpContext): Task {
        context.Response.Headers["X-NSharp-Stamp"] = "stamped:" + context.Request.Path.ToString()
        await next(context)
    }
}
