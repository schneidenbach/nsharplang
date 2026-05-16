using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Http;

namespace IssueTracker.Bridge;

public static class AspNetDelegateBridge
{
    public static RequestDelegate ToRequestDelegate(Func<HttpContext, Task> handler)
    {
        return new RequestDelegate(handler);
    }

    public static RequestDelegate ListIssuesHandler(object service, JsonSerializerOptions jsonOptions)
    {
        var routeJsonOptions = CreateRouteJsonOptions(jsonOptions);

        return async context =>
        {
            var getAll = service.GetType().GetMethod("GetAll", BindingFlags.Instance | BindingFlags.Public)
                ?? throw new InvalidOperationException("IssueService.GetAll method was not found.");
            var issues = (IEnumerable<object>)(getAll.Invoke(service, [])
                ?? throw new InvalidOperationException("IssueService.GetAll returned null."));

            context.Response.ContentType = "application/json";
            await JsonSerializer.SerializeAsync(context.Response.Body, issues.Select(ToIssueDto), routeJsonOptions);
        };
    }

    public static RequestDelegate CreateIssueHandler(object service, JsonSerializerOptions jsonOptions)
    {
        var routeJsonOptions = CreateRouteJsonOptions(jsonOptions);

        return async context =>
        {
            var requestType = service.GetType().Assembly.GetType("IssueTracker.CreateIssueRequest")
                ?? throw new InvalidOperationException("IssueTracker.CreateIssueRequest type was not found.");
            var request = await JsonSerializer.DeserializeAsync(context.Request.Body, requestType, routeJsonOptions);
            if (request is null)
            {
                context.Response.StatusCode = StatusCodes.Status400BadRequest;
                await context.Response.WriteAsync("Invalid request body");
                return;
            }

            var title = GetMemberValue<string>(request, "Title");
            var description = GetMemberValue<string>(request, "Description");
            var priority = GetMemberValue<object>(request, "Priority");
            var tags = GetMemberValue<string[]>(request, "Tags");

            var createIssue = service.GetType().GetMethod("CreateIssue", BindingFlags.Instance | BindingFlags.Public)
                ?? throw new InvalidOperationException("IssueService.CreateIssue method was not found.");

            try
            {
                var issue = createIssue.Invoke(service, [title, description, priority, tags]);
                context.Response.StatusCode = StatusCodes.Status201Created;
                context.Response.ContentType = "application/json";
                await JsonSerializer.SerializeAsync(context.Response.Body, ToIssueDto(issue!), routeJsonOptions);
            }
            catch (TargetInvocationException ex) when (ex.InnerException is not null)
            {
                context.Response.StatusCode = StatusCodes.Status400BadRequest;
                await context.Response.WriteAsync(ex.InnerException.Message);
            }
        };
    }

    private static JsonSerializerOptions CreateRouteJsonOptions(JsonSerializerOptions jsonOptions)
    {
        var routeJsonOptions = new JsonSerializerOptions(jsonOptions)
        {
            IncludeFields = true
        };
        routeJsonOptions.Converters.Add(new JsonStringEnumConverter());
        return routeJsonOptions;
    }

    private static object ToIssueDto(object issue)
    {
        return new
        {
            Id = GetMemberValue<int>(issue, "Id"),
            Title = GetMemberValue<string>(issue, "Title"),
            Description = GetMemberValue<string>(issue, "Description"),
            Status = ToStatusDto(GetMemberValue<object>(issue, "Status")),
            Priority = GetMemberValue<object>(issue, "Priority"),
            CreatedAt = GetMemberValue<DateTime>(issue, "CreatedAt"),
            Tags = GetMemberValue<string[]>(issue, "Tags") ?? []
        };
    }

    private static object ToStatusDto(object? status)
    {
        if (status is null)
        {
            return new { Type = "Unknown" };
        }

        return status.GetType().Name switch
        {
            "InProgress" => new { Type = "InProgress", AssigneeId = GetMemberValue<int>(status, "assigneeId") },
            "Closed" => new
            {
                Type = "Closed",
                Resolution = GetMemberValue<string>(status, "resolution"),
                ClosedAt = GetMemberValue<DateTime>(status, "closedAt")
            },
            _ => new { Type = status.GetType().Name }
        };
    }

    private static T? GetMemberValue<T>(object target, string name)
    {
        var bindingFlags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        var type = target.GetType();

        if (type.GetProperty(name, bindingFlags)?.GetValue(target) is { } propertyValue)
        {
            return (T?)propertyValue;
        }

        if (type.GetField(name, bindingFlags)?.GetValue(target) is { } fieldValue)
        {
            return (T?)fieldValue;
        }

        return default;
    }
}
