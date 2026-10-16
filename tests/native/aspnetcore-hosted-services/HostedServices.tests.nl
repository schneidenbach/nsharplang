namespace NSharpLang.AspNetCoreHostedServices.Tests

import System
import System.IO
import System.Threading
import System.Threading.Tasks
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http
import Microsoft.Extensions.DependencyInjection
import Microsoft.Extensions.Hosting
import NSharpLang.AspNetCoreHostedServices

// `nlc test` FOR A `framework: Microsoft.AspNetCore.App` PROJECT RUNS ITS TYPES, NOT JUST READS THEM.
//
// Before the test host probed the project's shared-framework directories, every row below died
// before its first line with `Could not load file or assembly 'Microsoft.Extensions.Hosting.
// Abstractions, Version=10.0.0.0'`: the build references the framework but never copies it, and
// the tests run inside the CLI's own process, whose host bound only `Microsoft.NETCore.App`.

func WithinTenSeconds<T>(task: Task<T>): Task<T> {
    return task.WaitAsync(TimeSpan.FromSeconds(10))
}

test "a framework base type binds from the shared framework the build referenced" {
    location := typeof(BackgroundService).Assembly.Location
    versionDirectory := Path.GetDirectoryName(location) ?? ""
    frameworkDirectory := Path.GetDirectoryName(versionDirectory) ?? ""
    sharedDirectory := Path.GetDirectoryName(frameworkDirectory) ?? ""
    assert Path.GetFileName(frameworkDirectory) == "Microsoft.AspNetCore.App", location
    assert Path.GetFileName(sharedDirectory) == "shared", location
}

test "a BackgroundService subclass starts, runs and observes its stop" {
    worker := new TickingWorker(3)
    await worker.StartAsync(CancellationToken.None)
    reached := await WithinTenSeconds(worker.ReachedTarget)
    await worker.StopAsync(CancellationToken.None)

    assert reached == 3
    assert worker.Ticks >= 3
    assert worker.StopObserved
    executeTask := worker.ExecuteTask
    assert executeTask != null
    assert executeTask.IsCompletedSuccessfully
    worker.Dispose()
}

test "a generic host activates a hosted service through dependency injection" {
    builder := Host.CreateEmptyApplicationBuilder(new HostApplicationBuilderSettings())
    builder.Services.AddSingleton<StartupProbe>()
    builder.Services.AddHostedService<ProbeWorker>()
    using host := builder.Build()

    await host.StartAsync()
    probe := host.Services.GetRequiredService<StartupProbe>()
    message := await WithinTenSeconds(probe.Started)
    await host.StopAsync()

    assert message == "started by the host"
}

// `UseMiddleware(typeof(T))` rather than `UseMiddleware<T>()`: the columnar emitter still declines
// the generic `params` extension call (`emit.call.generic-unresolved`). Both overloads activate the
// same conventional middleware.
test "a conventional middleware runs in an ApplicationBuilder pipeline" {
    services := new ServiceCollection().BuildServiceProvider()
    app := new ApplicationBuilder(services)
    app.UseMiddleware(typeof(RequestStampMiddleware))
    terminalRan := false
    app.Run(context => {
        terminalRan = true
        context.Response.StatusCode = 204
        return Task.CompletedTask
    })
    pipeline := app.Build()

    context := new DefaultHttpContext()
    context.Request.Path = new PathString("/orders")
    await pipeline(context)

    assert terminalRan
    assert context.Response.StatusCode == 204
    assert context.Response.Headers["X-NSharp-Stamp"].ToString() == "stamped:/orders"
}
