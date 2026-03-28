namespace MatchExamplesDEMO

import System


// Discriminated union for HTTP responses
union HttpResponse {
    Success(statusCode: int, body: string)
    Redirect(location: string)
    ClientError(code: int, message: string)
    ServerError(code: int, details: string)
}

// Function demonstrating exhaustive match (all cases covered)
func HandleResponse(response: HttpResponse): string {
    return response match {
        HttpResponse.Success(statusCode: , body: ) => $"Success ({statusCode}): {body}"
        HttpResponse.Redirect(location: ) => $"Redirecting to: {location}"
        HttpResponse.ClientError(code: , message: ) => $"Client Error {code}: {message}"
        HttpResponse.ServerError(code: , details: ) => $"Server Error {code}: {details}"
    }
}

// Function demonstrating wildcard pattern (catch-all for remaining cases)
func GetStatusCategory(response: HttpResponse): string {
    return response match {
        HttpResponse.Success(statusCode: , body: ) => "2xx Success"
        _ => "Non-success response"
    }
}

// Simpler union for demonstration
union FileOperation {
    Read(path: string)
    Write(path: string, content: string)
    Delete(path: string)
}

// Pattern matching with property destructuring
func DescribeOperation(op: FileOperation): string {
    return op match {
        FileOperation.Read(path: ) => $"Reading from {path}"
        FileOperation.Write(path: , content: ) => $"Writing {content.Length} bytes to {path}"
        FileOperation.Delete(path: ) => $"Deleting {path}"
    }
}

func Main() {
    print "=== Match Expression Exhaustiveness Demo ===\n"

    // Test all HttpResponse cases
    print "1. Exhaustive matching on HttpResponse:"
    successResp := new HttpResponse.Success() { statusCode: 200, body: "OK" }
    print HandleResponse(successResp)

    redirectResp := new HttpResponse.Redirect() { location: "/new-page" }
    print HandleResponse(redirectResp)

    clientErr := new HttpResponse.ClientError() { code: 404, message: "Not Found" }
    print HandleResponse(clientErr)

    serverErr := new HttpResponse.ServerError() { code: 500, details: "Internal error" }
    print HandleResponse(serverErr)

    // Test wildcard pattern
    print "\n2. Wildcard pattern matching:"
    print GetStatusCategory(successResp)
    print GetStatusCategory(clientErr)

    // Test FileOperation
    print "\n3. File operation matching:"
    readOp := new FileOperation.Read() { path: "/data.txt" }
    print DescribeOperation(readOp)

    writeOp := new FileOperation.Write() { path: "/output.txt", content: "Hello, World!" }
    print DescribeOperation(writeOp)

    deleteOp := new FileOperation.Delete() { path: "/temp.log" }
    print DescribeOperation(deleteOp)

    print "\n=== Demo Complete ==="
    print "Note: The compiler enforces exhaustiveness checking!"
    print "Missing cases or invalid union cases are caught at compile time."
}
