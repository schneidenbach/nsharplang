// Endpoints.nl — Minimal API routes wired to IssueService.

namespace IssueTracker

import System.IO
import System.Linq
import System.Text.Json
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http
import "Models"
import "Service"

class Routes {
    readonly service: IssueService
    readonly jsonOptions: JsonSerializerOptions

    constructor(svc: IssueService) {
        service = svc
        jsonOptions = new JsonSerializerOptions {
            IncludeFields: true,
            PropertyNameCaseInsensitive: true,
            PropertyNamingPolicy: JsonNamingPolicy.CamelCase
        }
    }

    func Map(app: WebApplication) {
        app.MapGet("/api/health", context => context.Response.WriteAsync("ok"))
        app.MapGet("/api/issues", () => service.GetAll().Select(issue => ToResponse(issue)).ToList())
        app.MapPost("/api/issues", context => {
            reader := new StreamReader(context.Request.Body)
            body := reader.ReadToEndAsync().Result
            request := JsonSerializer.Deserialize<CreateIssueRequest>(body, jsonOptions)

            if request == null {
                context.Response.StatusCode = 400
                return context.Response.WriteAsync("Invalid request body")
            }

            if !IsPriorityName(request.Priority) {
                context.Response.StatusCode = 400
                return context.Response.WriteAsync("Invalid priority")
            }

            priority := ParsePriority(request.Priority)

            // Error tuples at the call site — Go-style error handling
            issue, err := service.CreateIssue(request.Title, request.Description, priority, request.Tags)

            if err != null {
                context.Response.StatusCode = 400
                return context.Response.WriteAsync(err.Message)
            }

            context.Response.StatusCode = 201
            return context.Response.WriteAsJsonAsync(ToResponse(issue), jsonOptions, context.RequestAborted)
        })
    }

    func ToResponse(issue: Issue): IssueResponse {
        return new IssueResponse {
            Id: issue.Id,
            Title: issue.Title,
            Description: issue.Description,
            Status: new IssueStatusResponse { Type: StatusType(issue.Status) },
            Priority: PriorityName(issue.Priority),
            CreatedAt: issue.CreatedAt,
            Tags: issue.Tags
        }
    }

    func PriorityName(priority: Priority): string {
        if priority == Priority.Low {
            return "Low"
        }

        if priority == Priority.Medium {
            return "Medium"
        }

        if priority == Priority.High {
            return "High"
        }

        if priority == Priority.Critical {
            return "Critical"
        }

        return "Unknown"
    }

    func IsPriorityName(priority: string): bool {
        return priority == "Low" || priority == "Medium" || priority == "High" || priority == "Critical"
    }

    func ParsePriority(priority: string): Priority {
        if priority == "Low" {
            return Priority.Low
        }

        if priority == "Medium" {
            return Priority.Medium
        }

        if priority == "High" {
            return Priority.High
        }

        if priority == "Critical" {
            return Priority.Critical
        }

        throw new Exception("Invalid priority")
    }

    func StatusType(status: IssueStatus): string {
        if status is IssueStatus.Open {
            return "Open"
        }

        if status is IssueStatus.InProgress {
            return "InProgress"
        }

        if status is IssueStatus.Closed {
            return "Closed"
        }

        return "Unknown"
    }
}

// Request DTOs — records, not classes. Immutable, concise.
record CreateIssueRequest {
    Title: string
    Description: string
    Priority: string
    Tags: string[]
}

record IssueStatusResponse {
    Type: string
}

record IssueResponse {
    Id: int
    Title: string
    Description: string
    Status: IssueStatusResponse
    Priority: string
    CreatedAt: DateTime
    Tags: string[]
}

record TransitionRequest {
    Status: string
}
