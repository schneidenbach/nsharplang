namespace NSharpLang.LambdaParameterNames

import System
import System.Collections.Generic
import System.IO
import System.Text
import System.Threading.Tasks
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http
import Microsoft.AspNetCore.Routing

// EVERY SHAPE A LAMBDA LOWERS TO, each handed back as the delegate whose `Method` reflection reads.
// The synthesized method is the delegate's `Method`, so its `Param` rows are a public contract:
// ASP.NET Core binds a Minimal-API handler's route values, query string and services BY PARAMETER
// NAME, and a lambda whose method had no names failed every request (issue #216).

// A free function's lambda: the static helper on the namespace's program holder.
func StaticLambda(): Func<int, string, int> {
    return (count, label) => count + label.Length
}

// A lambda whose parameter TYPES are written, against a delegate target.
func TypedLambda(): Func<int, int> {
    return (value: int) => value + 1
}

// A block body.
func BlockLambda(): Func<int, int, int> {
    return (left, right) => {
        total := left + right
        return total
    }
}

// An `async` lambda: the synthesized method is the kickoff stub and keeps the user's signature.
func AsyncLambda(): Func<int, Task<int>> {
    return async (delayMs: int) => {
        await Task.Delay(delayMs)
        return delayMs
    }
}

// A capturing lambda: an instance method on the display class, whose receiver is `this` — never a
// parameter — so the user's parameters still start at sequence one.
func CapturingLambda(offset: int): Func<int, int> {
    return (input: int) => input + offset
}

// A lambda inferred at `:=`: defined signature-less, named only after `SetParameters`.
func InferredLambda(): Delegate {
    inferred := (quantity: int, unit: string) => quantity.ToString() + unit
    return inferred
}

// A lambda written in a generator body: the iterator planner's own lowering.
func* GeneratorLambdas(): IEnumerable<Delegate> {
    yieldedHandler: Func<int, string> = (itemId) => itemId.ToString()
    yield yieldedHandler
}

class Scaler {
    Factor: int

    constructor(factor: int) {
        Factor = factor
    }

    // Reads `this`, so it lowers to a private INSTANCE method on `Scaler` bound to the receiver.
    func Scale(): Func<int, int> {
        return (amount) => amount * Factor
    }

    // Reads nothing of the instance: a static helper on `Scaler` itself.
    func Describe(): Func<string, string> {
        return (text) => "[" + text + "]"
    }
}

// The comma-joined parameter names of a delegate's method, `<null>` for a missing one.
func ParameterNames(handler: Delegate): string {
    names := new List<string>()
    for parameter in handler.Method.GetParameters() {
        names.Add(parameter.Name ?? "<null>")
    }
    return string.Join(",", names)
}

// A WEB APPLICATION WHOSE ROUTE HANDLERS ARE LAMBDAS WITH PARAMETERS — the shapes issue #216 named.
// It is never started: the tests read each endpoint's `RequestDelegate` back out of the route table
// and invoke it in process, which is exactly what Kestrel does with a matched request.
func BuildApp(): WebApplication {
    builder := WebApplication.CreateBuilder()
    app := builder.Build()
    greeting := "hello "
    app.MapGet("/todos/{id}", (id: int) => "todo " + id.ToString())
    app.MapGet("/greet/{name}", (name: string) => greeting + name)
    app.MapGet("/sum/{left}/{right}", (left: int, right: int) => (left + right).ToString())
    app.MapGet("/search", (term: string) => "searching " + term)
    app.MapGet("/context", (ctx: HttpContext) => ctx.Response.WriteAsync("context " + ctx.Request.Path.ToString()))
    app.MapGet("/async-context", async (ctx: HttpContext) => await ctx.Response.WriteAsync("async context"))
    typed: Func<int, string> = (orderId: int) => "order " + orderId.ToString()
    app.MapGet("/orders/{orderId}", typed as Delegate)
    app.MapGet("/receipts/{orderId}", (Delegate)typed)
    return app
}

// The request delegate the route table built for `pattern`.
func EndpointFor(app: WebApplication, pattern: string): RequestDelegate {
    routes: IEndpointRouteBuilder = app
    for dataSource in routes.DataSources {
        for endpoint in dataSource.Endpoints {
            if endpoint is RouteEndpoint && (endpoint as RouteEndpoint).RoutePattern.RawText == pattern {
                handler := endpoint.RequestDelegate
                if handler != null {
                    return handler
                }
            }
        }
    }
    throw new InvalidOperationException("no endpoint for " + pattern)
}

// Invoke one request delegate the way the server would, and read the response back as
// `<status> <body>`.
async func Invoke(app: WebApplication, handler: RequestDelegate, path: string, routeValues: Dictionary<string, string>, query: string): string {
    context := new DefaultHttpContext()
    context.RequestServices = app.Services
    context.Request.Method = "GET"
    context.Request.Path = new PathString(path)
    context.Request.QueryString = new QueryString(query)
    for pair in routeValues {
        context.Request.RouteValues[pair.Key] = pair.Value
    }
    body := new MemoryStream()
    context.Response.Body = body
    await handler(context)
    return context.Response.StatusCode.ToString() + " " + Encoding.UTF8.GetString(body.ToArray())
}
