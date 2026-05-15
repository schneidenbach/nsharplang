namespace SimpleTest


// String-backed enum (regression: parser error on `: string`)
enum Direction: string {
    North = "north",
    South = "south",
    East = "east",
    West = "west"
}

// Int-backed enum
enum Priority {
    Low = 1,
    Medium = 2,
    High = 3,
    Critical = 4
}

// Simple enum (no backing type) - control case
enum DayOfWeek {
    Monday,
    Tuesday,
    Wednesday,
    Thursday,
    Friday,
    Saturday,
    Sunday
}

// String-backed enum with single member
enum SingleValueEnum: string {
    Only = "only"
}

// Int-backed enum with explicit zero
enum ErrorCode {
    None = 0,
    NotFound = 404,
    ServerError = 500
}

// Enum usage in functions
func TestEnumUsage() {
    dir := Direction.North
    print $"Direction: {dir}"

    priority := Priority.High
    print $"Priority: {priority}"

    day := DayOfWeek.Friday
    print $"Day: {day}"

    code := ErrorCode.NotFound
    print $"Error code: {code}"
}
