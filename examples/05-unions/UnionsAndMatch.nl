namespace UnionsDemo

import System


// Discriminated union example
union Result {
    Success { value: int }
    Failure { error: string, code: int }
}

// String enum example
enum Status: string {
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
    return match r {
        Result.Success { value } => $"Success: {value}",
        Result.Failure { error, code } => $"Error {code}: {error}"
    }
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
    print "=== Unions and Match Demo ==="

    // Test success case
    print "\n1. Success case:"
    successResult := new Result.Success(42)
    print ProcessResult(successResult)

    // Test failure case
    print "\n2. Failure case:"
    failureResult := new Result.Failure("File not found", 404)
    print ProcessResult(failureResult)

    // Test string values (enum simulation)
    print "\n3. String values:"
    currentStatus := "active"
    print $"Status: {currentStatus} - {GetStatusMessage(currentStatus)}"

    // Test int enum
    print "\n4. Int enum:"
    priority := Priority.High
    print $"Priority: {priority} ({(int)priority})"

    // Test type alias (just use int for now since aliases are comments)
    print "\n5. Type alias:"
    userId := 12345
    print $"User ID: {userId}"

    print "\n=== Demo Complete ==="
}
