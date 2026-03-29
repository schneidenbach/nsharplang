// Endpoints.nl — Minimal API routes wired to IssueService.

namespace IssueTracker

import System
import System.IO
import System.Collections.Generic
import System.Text.Json
import System.Threading.Tasks
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http
import "Models"
import "Service"

class Routes {
    service: IssueService
    jsonOptions: JsonSerializerOptions

    constructor(svc: IssueService) {
        service = svc
        jsonOptions = new JsonSerializerOptions {
            PropertyNameCaseInsensitive: true,
            PropertyNamingPolicy: JsonNamingPolicy.CamelCase
        }
    }

    func Map(app: WebApplication) {
        app.MapGet("/api/health", () => "ok")
        app.MapGet("/api/issues", () => service.GetAll())
        app.MapPost("/api/issues", context => HandleCreate(context))
    }

    // Returns Task by calling WriteAsync — satisfies RequestDelegate signature.
    func HandleCreate(context: HttpContext): Task {
        reader := new StreamReader(context.Request.Body)
        body := reader.ReadToEndAsync().Result
        request := JsonSerializer.Deserialize<CreateIssueRequest>(body, jsonOptions)

        if request == null {
            context.Response.StatusCode = 400
            return context.Response.WriteAsync("Invalid request body")
        }

        // Error tuples at the call site — Go-style error handling
        issue, err := service.CreateIssue(
            request.Title,
            request.Description,
            request.Priority,
            request.Tags
        )

        if err != null {
            context.Response.StatusCode = 400
            return context.Response.WriteAsync(err.Message)
        }

        context.Response.StatusCode = 201
        context.Response.ContentType = "application/json"
        json := JsonSerializer.Serialize<object>(issue, jsonOptions)
        return context.Response.WriteAsync(json)
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
