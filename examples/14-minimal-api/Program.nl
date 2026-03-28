import System
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http
import Microsoft.Extensions.Hosting

func main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()

    // Simple text endpoint
    app.MapGet("/", () => "Hello from N#!")

    // DateTime endpoint
    app.MapGet("/time", () => DateTime.Now.ToString())

    // JSON endpoint
    app.MapGet("/json", () => new() { Message: "Hello from N#", Timestamp: DateTime.Now, Language: "N#" })

    // Environment check
    if app.Environment.IsDevelopment() {
        print "Running in development mode"
        print "Try these endpoints:"
        print "  GET /"
        print "  GET /time"
        print "  GET /json"
    }

    app.Run()
}
