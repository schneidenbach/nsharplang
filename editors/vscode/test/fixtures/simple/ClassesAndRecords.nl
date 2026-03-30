namespace SimpleTest

// Class with typed properties and constructor
class Vehicle {
    Make: string
    Model: string
    Year: int
    Mileage: double

    constructor(make: string, model: string, year: int) {
        Make = make
        Model = model
        Year = year
        Mileage = 0.0
    }

    func GetDescription(): string {
        return $"{Year} {Make} {Model}"
    }

    func AddMileage(miles: double) {
        Mileage = Mileage + miles
    }
}

// Class with multiple constructors
class Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        X = x
        Y = y
    }

    func DistanceSquaredTo(other: Point): int {
        dx := X - other.X
        dy := Y - other.Y
        return dx * dx + dy * dy
    }

    func ToString(): string {
        return $"({X}, {Y})"
    }
}

// Class using other classes
func TestClasses() {
    car := new Vehicle("Toyota", "Camry", 2024)
    print car.GetDescription()
    car.AddMileage(1500.5)
    print $"Mileage: {car.Mileage}"

    p1 := new Point(0, 0)
    p2 := new Point(3, 4)
    print $"Distance² from {p1.ToString()} to {p2.ToString()}: {p1.DistanceSquaredTo(p2)}"
}

// Class with typed fields used as out parameter containers
class ParseResult {
    Value: int
    Success: bool

    constructor(value: int, success: bool) {
        Value = value
        Success = success
    }
}

func CreateParseResult(input: string): ParseResult {
    if input.Length > 0 {
        return new ParseResult(42, true)
    }
    return new ParseResult(0, false)
}

func TestParseResult() {
    result := CreateParseResult("hello")
    print $"Value: {result.Value}, Success: {result.Success}"
}
