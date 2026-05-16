// Endpoints.nl — Minimal API routes wired to IssueService.

namespace IssueTracker

import System.Text.Json
import Microsoft.AspNetCore.Builder
import IssueTracker.Bridge
import "Models"
import "Service"

class Routes {
    service: IssueService
    jsonOptions: JsonSerializerOptions

    constructor(svc: IssueService) {
        service = svc
        jsonOptions = new JsonSerializerOptions {
            IncludeFields: true,
            PropertyNameCaseInsensitive: true,
            PropertyNamingPolicy: JsonNamingPolicy.CamelCase
        }
    }

    func Map(app: WebApplication) {
        app.MapGet("/api/health", () => "ok")
        listHandler := AspNetDelegateBridge.ListIssuesHandler(service, jsonOptions)
        createHandler := AspNetDelegateBridge.CreateIssueHandler(service, jsonOptions)
        app.MapGet("/api/issues", listHandler)
        app.MapPost("/api/issues", createHandler)
    }
}

// Request DTOs — records, not classes. Immutable, concise.
record CreateIssueRequest {
    Title: string
    Description: string
    Priority: Priority
    Tags: string[]
}

record TransitionRequest {
    Status: string
}
