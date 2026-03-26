import System

// Simple pattern matching with guards demo

// Classify a number with guards
func ClassifyNumber(n: int): string {
    return match n {
        x when x > 100 => "very large",
        x when x > 50 => "large",
        x when x > 10 => "medium",
        x when x > 0 => "small",
        0 => "zero",
        x when x > -10 => "small negative",
        _ => "very negative"
    }
}

// Fizzbuzz with pattern matching and guards
func FizzBuzz(n: int): string {
    return match n {
        x when x % 15 == 0 => "FizzBuzz",
        x when x % 3 == 0 => "Fizz",
        x when x % 5 == 0 => "Buzz",
        x => x.ToString()
    }
}

// Grade calculator with guards
func GetGrade(score: int): string {
    return match score {
        x when x >= 90 => "A",
        x when x >= 80 => "B",
        x when x >= 70 => "C",
        x when x >= 60 => "D",
        x when x >= 0 => "F",
        _ => "Invalid score"
    }
}

func Main() {
    print "=== Pattern Matching with Guards ==="
    print ""

    // Number classification
    print "Number Classification:"
    print $"ClassifyNumber(150) = {ClassifyNumber(150)}"
    print $"ClassifyNumber(75) = {ClassifyNumber(75)}"
    print $"ClassifyNumber(25) = {ClassifyNumber(25)}"
    print $"ClassifyNumber(5) = {ClassifyNumber(5)}"
    print $"ClassifyNumber(0) = {ClassifyNumber(0)}"
    print $"ClassifyNumber(-5) = {ClassifyNumber(-5)}"
    print $"ClassifyNumber(-50) = {ClassifyNumber(-50)}"
    print ""

    // FizzBuzz
    print "FizzBuzz (1-20):"
    for i := 1; i <= 20; i++ {
        Console.Write($"{FizzBuzz(i)} ")
    }
    print ""
    print ""

    // Grade calculator
    print "Grade Calculator:"
    print $"GetGrade(95) = {GetGrade(95)}"
    print $"GetGrade(85) = {GetGrade(85)}"
    print $"GetGrade(75) = {GetGrade(75)}"
    print $"GetGrade(65) = {GetGrade(65)}"
    print $"GetGrade(55) = {GetGrade(55)}"
    print $"GetGrade(-10) = {GetGrade(-10)}"
    print ""

    print "Guards allow complex conditional matching!"
}
