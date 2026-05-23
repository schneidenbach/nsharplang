// Program.nl — App entry point. Compare this to a C# Startup.cs.

namespace IssueTracker

import Microsoft.AspNetCore.Builder
import Microsoft.Extensions.Hosting
import "Database"
import "Notifier"
import "Service"
import "Endpoints"

func main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()

    // Serve built frontend from wwwroot/ (production path)
    app.UseDefaultFiles()
    app.UseStaticFiles()

    // Wire up duck-typed notifiers — no interface declarations needed
    hub := new NotifierHub()
    hub.Register(new ConsoleNotifier())
    hub.Register(new SlackNotifier("https://hooks.slack.example/issues"))

    store := new IssueStore()
    service := new IssueService(store, hub)
    routes := new Routes(service)

    routes.Map(app)

    // SPA route handling: unmatched routes serve index.html for client-side routing.
    app.MapFallbackToFile("index.html")

    if app.Environment.IsDevelopment() {
        print "Issue Tracker started"
    }

    app.Run()
}
