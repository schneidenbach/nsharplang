using System

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
    Console.WriteLine("=== Pattern Matching with Guards ===")
    Console.WriteLine()

    // Number classification
    Console.WriteLine("Number Classification:")
    Console.WriteLine($"ClassifyNumber(150) = {ClassifyNumber(150)}")
    Console.WriteLine($"ClassifyNumber(75) = {ClassifyNumber(75)}")
    Console.WriteLine($"ClassifyNumber(25) = {ClassifyNumber(25)}")
    Console.WriteLine($"ClassifyNumber(5) = {ClassifyNumber(5)}")
    Console.WriteLine($"ClassifyNumber(0) = {ClassifyNumber(0)}")
    Console.WriteLine($"ClassifyNumber(-5) = {ClassifyNumber(-5)}")
    Console.WriteLine($"ClassifyNumber(-50) = {ClassifyNumber(-50)}")
    Console.WriteLine()

    // FizzBuzz
    Console.WriteLine("FizzBuzz (1-20):")
    for i := 1; i <= 20; i++ {
        Console.Write($"{FizzBuzz(i)} ")
    }
    Console.WriteLine()
    Console.WriteLine()

    // Grade calculator
    Console.WriteLine("Grade Calculator:")
    Console.WriteLine($"GetGrade(95) = {GetGrade(95)}")
    Console.WriteLine($"GetGrade(85) = {GetGrade(85)}")
    Console.WriteLine($"GetGrade(75) = {GetGrade(75)}")
    Console.WriteLine($"GetGrade(65) = {GetGrade(65)}")
    Console.WriteLine($"GetGrade(55) = {GetGrade(55)}")
    Console.WriteLine($"GetGrade(-10) = {GetGrade(-10)}")
    Console.WriteLine()

    Console.WriteLine("Guards allow complex conditional matching!")
}
