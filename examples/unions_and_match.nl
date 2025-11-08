namespace UnionsDemo

using System

// Discriminated union example
union Result {
    Success { value: int }
    Failure { error: string, code: int }
}

// String enum example
enum Status {
    Pending = "pending",
    Active = "active",
    Done = "done"
}

// Int enum example
enum Priority {
    Low = 0,
    Medium = 1,
    High = 2
}

// Type alias example
type UserId = int
type ErrorCode = int

func ProcessResult(r: Result): string {
    // For now, use if-else instead of match since transpilation needs work
    if r is Result.Success {
        s := (Result.Success)r
        return $"Success: {s.value}"
    }
    if r is Result.Failure {
        f := (Result.Failure)r
        return $"Error {f.code}: {f.error}"
    }
    return "Unknown"
}

func GetStatusMessage(status: string): string {
    // Simple if-else chain
    if status == "pending" {
        return "Waiting to start"
    }
    if status == "active" {
        return "Currently running"
    }
    if status == "done" {
        return "Completed"
    }
    return "Unknown status"
}

func Main() {
    Console.WriteLine("=== Unions and Match Demo ===")

    // Test success case
    Console.WriteLine("\n1. Success case:")
    successResult := new Result.Success(42)
    Console.WriteLine(ProcessResult(successResult))

    // Test failure case
    Console.WriteLine("\n2. Failure case:")
    failureResult := new Result.Failure("File not found", 404)
    Console.WriteLine(ProcessResult(failureResult))

    // Test string values (enum simulation)
    Console.WriteLine("\n3. String values:")
    currentStatus := "active"
    Console.WriteLine($"Status: {currentStatus} - {GetStatusMessage(currentStatus)}")

    // Test int enum
    Console.WriteLine("\n4. Int enum:")
    priority := Priority.High
    Console.WriteLine($"Priority: {priority} ({(int)priority})")

    // Test type alias (just use int for now since aliases are comments)
    Console.WriteLine("\n5. Type alias:")
    userId := 12345
    Console.WriteLine($"User ID: {userId}")

    Console.WriteLine("\n=== Demo Complete ===")
}
