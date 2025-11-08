using System;

namespace MatchExamplesDEMO;

abstract record HttpResponse
{
    public record Success(int statusCode, string body) : HttpResponse;
    public record Redirect(string location) : HttpResponse;
    public record ClientError(int code, string message) : HttpResponse;
    public record ServerError(int code, string details) : HttpResponse;
}

abstract record FileOperation
{
    public record Read(string path) : FileOperation;
    public record Write(string path, string content) : FileOperation;
    public record Delete(string path) : FileOperation;
}

internal static class _MatchExamplesDEMO_TopLevel
{
    internal static string HandleResponse(HttpResponse response)
    {
        return response switch {
        HttpResponse.Success { statusCode: var statusCode, body: var body } => $"Success ({statusCode}): {body}",
        HttpResponse.Redirect { location: var location } => $"Redirecting to: {location}",
        HttpResponse.ClientError { code: var code, message: var message } => $"Client Error {code}: {message}",
        HttpResponse.ServerError { code: var code, details: var details } => $"Server Error {code}: {details}"
        };
    }

    internal static string GetStatusCategory(HttpResponse response)
    {
        return response switch {
        HttpResponse.Success { statusCode: var statusCode, body: var body } => "2xx Success",
        _ => "Non-success response"
        };
    }

    internal static string DescribeOperation(FileOperation op)
    {
        return op switch {
        FileOperation.Read { path: var path } => $"Reading from {path}",
        FileOperation.Write { path: var path, content: var content } => $"Writing {content.Length} bytes to {path}",
        FileOperation.Delete { path: var path } => $"Deleting {path}"
        };
    }

    internal static void Main()
    {
        Console.WriteLine("=== Match Expression Exhaustiveness Demo ===\n");
        Console.WriteLine("1. Exhaustive matching on HttpResponse:");
        var successResp = new HttpResponse.Success() { statusCode = 200, body = "OK" };
        Console.WriteLine(HandleResponse(successResp));
        var redirectResp = new HttpResponse.Redirect() { location = "/new-page" };
        Console.WriteLine(HandleResponse(redirectResp));
        var clientErr = new HttpResponse.ClientError() { code = 404, message = "Not Found" };
        Console.WriteLine(HandleResponse(clientErr));
        var serverErr = new HttpResponse.ServerError() { code = 500, details = "Internal error" };
        Console.WriteLine(HandleResponse(serverErr));
        Console.WriteLine("\n2. Wildcard pattern matching:");
        Console.WriteLine(GetStatusCategory(successResp));
        Console.WriteLine(GetStatusCategory(clientErr));
        Console.WriteLine("\n3. File operation matching:");
        var readOp = new FileOperation.Read() { path = "/data.txt" };
        Console.WriteLine(DescribeOperation(readOp));
        var writeOp = new FileOperation.Write() { path = "/output.txt", content = "Hello, World!" };
        Console.WriteLine(DescribeOperation(writeOp));
        var deleteOp = new FileOperation.Delete() { path = "/temp.log" };
        Console.WriteLine(DescribeOperation(deleteOp));
        Console.WriteLine("\n=== Demo Complete ===");
        Console.WriteLine("Note: The compiler enforces exhaustiveness checking!");
        Console.WriteLine("Missing cases or invalid union cases are caught at compile time.");
    }

}
