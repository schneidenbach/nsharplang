namespace MatchExamplesDEMO

import System

// Discriminated union for HTTP responses
union HttpResponse {
    Success { statusCode: int, body: string }
    Redirect { location: string }
    ClientError { code: int, message: string }
    ServerError { code: int, details: string }
}

// Function demonstrating exhaustive match (all cases covered)
func HandleResponse(response: HttpResponse): string {
    return match response {
        HttpResponse.Success { statusCode, body } => $"Success ({statusCode}): {body}",
        HttpResponse.Redirect { location } => $"Redirecting to: {location}",
        HttpResponse.ClientError { code, message } => $"Client Error {code}: {message}",
        HttpResponse.ServerError { code, details } => $"Server Error {code}: {details}"
    }
}

// Function demonstrating wildcard pattern (catch-all for remaining cases)
func GetStatusCategory(response: HttpResponse): string {
    return match response {
        HttpResponse.Success { statusCode, body } => "2xx Success",
        _ => "Non-success response"
    }
}

// Simpler union for demonstration
union FileOperation {
    Read { path: string }
    Write { path: string, content: string }
    Delete { path: string }
}

// Pattern matching with property destructuring
func DescribeOperation(op: FileOperation): string {
    return match op {
        FileOperation.Read { path } => $"Reading from {path}",
        FileOperation.Write { path, content } => $"Writing {content.Length} bytes to {path}",
        FileOperation.Delete { path } => $"Deleting {path}"
    }
}

func Main() {
    Console.WriteLine("=== Match Expression Exhaustiveness Demo ===\n")

    // Test all HttpResponse cases
    Console.WriteLine("1. Exhaustive matching on HttpResponse:")
    successResp := new HttpResponse.Success { statusCode: 200, body: "OK" }
    Console.WriteLine(HandleResponse(successResp))

    redirectResp := new HttpResponse.Redirect { location: "/new-page" }
    Console.WriteLine(HandleResponse(redirectResp))

    clientErr := new HttpResponse.ClientError { code: 404, message: "Not Found" }
    Console.WriteLine(HandleResponse(clientErr))

    serverErr := new HttpResponse.ServerError { code: 500, details: "Internal error" }
    Console.WriteLine(HandleResponse(serverErr))

    // Test wildcard pattern
    Console.WriteLine("\n2. Wildcard pattern matching:")
    Console.WriteLine(GetStatusCategory(successResp))
    Console.WriteLine(GetStatusCategory(clientErr))

    // Test FileOperation
    Console.WriteLine("\n3. File operation matching:")
    readOp := new FileOperation.Read { path: "/data.txt" }
    Console.WriteLine(DescribeOperation(readOp))

    writeOp := new FileOperation.Write { path: "/output.txt", content: "Hello, World!" }
    Console.WriteLine(DescribeOperation(writeOp))

    deleteOp := new FileOperation.Delete { path: "/temp.log" }
    Console.WriteLine(DescribeOperation(deleteOp))

    Console.WriteLine("\n=== Demo Complete ===")
    Console.WriteLine("Note: The compiler enforces exhaustiveness checking!")
    Console.WriteLine("Missing cases or invalid union cases are caught at compile time.")
}
