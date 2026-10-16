namespace NSharpLang.WebGenericMiddleware

import System
import System.Threading.Tasks
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http
import Microsoft.AspNetCore.Http.Metadata
import Microsoft.AspNetCore.Routing

// A minimal WebApplication pipeline registered through the GENERIC `UseMiddleware<TMiddleware>`,
// whose only parameter after the receiver is `params object?[] args`. The middleware run in
// registration order, and the request is driven in memory through the built pipeline, so the
// program needs no socket and prints exactly what each middleware did.
class Stamp {
    next: RequestDelegate

    constructor(next: RequestDelegate) {
        this.next = next
    }

    func InvokeAsync(context: HttpContext): Task {
        context.Response.Headers["X-Stamp"] = "stamped"
        return next(context)
    }
}

// Constructor arguments past `next` are what the packed tail carries to activation.
class Tagged {
    next: RequestDelegate
    tag: string
    weight: int

    constructor(next: RequestDelegate, tag: string, weight: int) {
        this.next = next
        this.tag = tag
        this.weight = weight
    }

    func InvokeAsync(context: HttpContext): Task {
        context.Response.Headers["X-Tag"] = tag + ":" + weight.ToString()
        return next(context)
    }
}

class Todo {
    Title: string
}

func Terminal(context: HttpContext): Task {
    context.Response.StatusCode = 204
    return Task.CompletedTask
}

// Every response-type declaration the mapped endpoints carry, in order, as `status:type:contentTypes`.
func DescribeProduces(routes: IEndpointRouteBuilder): string {
    text := ""
    for source in routes.DataSources {
        for endpoint in source.Endpoints {
            for produced in endpoint.Metadata.GetOrderedMetadata<IProducesResponseTypeMetadata>() {
                if text.Length > 0 {
                    text = text + "|"
                }
                text = text + produced.StatusCode.ToString() + ":" + (produced.Type?.Name ?? "none") + ":" + string.Join(",", produced.ContentTypes)
            }
        }
    }
    return text
}

func main() {
    app := WebApplication.CreateBuilder().Build()
    // Zero arguments: the whole `params` tail is an empty array.
    app.UseMiddleware<Stamp>()
    // Two arguments: both pack into the tail and reach `Tagged`'s constructor.
    app.UseMiddleware<Tagged>("blue", 7)
    // `Produces<TResponse>(int statusCode = 200, string? contentType = null, params string[]
    // additionalContentTypes)`: omitted defaulted slots fill from metadata before the empty tail, and
    // a full call packs what follows the fixed slots.
    route := app.MapGet("/todo", () => "todo")
    route.Produces<Todo>()
    route.Produces<Todo>(201, "text/plain", "application/xml")
    terminal: RequestDelegate = Terminal
    (app as IApplicationBuilder).Run(terminal)

    pipeline := (app as IApplicationBuilder).Build()
    context := new DefaultHttpContext()
    context.RequestServices = app.Services
    pipeline(context).Wait()

    Console.WriteLine("X-Stamp=" + context.Response.Headers["X-Stamp"].ToString())
    Console.WriteLine("X-Tag=" + context.Response.Headers["X-Tag"].ToString())
    Console.WriteLine("Status=" + context.Response.StatusCode.ToString())
    Console.WriteLine("Produces=" + DescribeProduces(app))
}
