// Program.nl — App entry point. Compare this to a C# Startup.cs.

namespace IssueTracker

import System
import Microsoft.AspNetCore.Builder
import Microsoft.Extensions.Hosting

func main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()

    // Wire up duck-typed notifiers — no interface declarations needed
    hub := new NotifierHub()
    hub.Register(new ConsoleNotifier())
    hub.Register(new SlackNotifier("https://hooks.slack.example/issues"))

    store := new IssueStore()
    service := new IssueService(store, hub)
    routes := new Routes(service)

    routes.Map(app)

    if app.Environment.IsDevelopment() {
        print "Issue Tracker running at http://localhost:5000"
    }

    app.Run()
}
