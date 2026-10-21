namespace NSharpLang.AspNetCoreHostedServices.Tests

import System
import System.Threading.Tasks
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http

// WHAT `app.MapGet(pattern, handler)` ACCEPTS AT ITS `Delegate` OVERLOAD, built (not served).
//
// The ASP.NET endpoint binder reads a handler's parameters by name and type, so the handler has to be a
// real delegate the call can pass: a method group takes the natural `Func`/`Action` its signature
// spells, a delegate value converts by reference, and a lambda that writes its parameter types is built
// at its own natural type. Each of these used to build and then throw InvalidProgramException at the
// call, because the call's first emission attempt left its route string on the stack.
class Endpoints {
    static func Hello(ctx: HttpContext): Task {
        return ctx.Response.WriteAsync("hello")
    }

    static func Echo(name: string): string {
        return name
    }

    virtual func Instance(ctx: HttpContext): Task {
        return ctx.Response.WriteAsync("instance")
    }

    func MapInstance(app: WebApplication) {
        app.MapGet("/instance", Instance)
    }
}

func NewApp(): WebApplication {
    builder := WebApplication.CreateBuilder()
    return builder.Build()
}

func MapStaticGroup(app: WebApplication) {
    app.MapGet("/hello", Endpoints.Hello)
}

func MapDelegateValue(app: WebApplication) {
    echo: Func<string, string> = Endpoints.Echo
    app.MapGet("/echo/{name}", echo as Delegate)
}

func MapTypedLambda(app: WebApplication) {
    app.MapGet("/typed/{name}", (name: string) => name)
}

func MapContextLambda(app: WebApplication) {
    app.MapGet("/context", (ctx: HttpContext) => ctx.Response.WriteAsync("context"))
}

func MapZeroLambda(app: WebApplication) {
    app.MapGet("/zero", () => "zero")
}

func MapFallbackFile(app: WebApplication) {
    app.MapFallbackToFile("index.html")
}
