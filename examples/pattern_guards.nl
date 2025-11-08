using System

// Pattern matching with guards demo
// Guards allow you to add additional conditions to patterns

union HttpResponse {
    Ok { statusCode: int, body: string }
    Redirect { location: string, permanent: bool }
    ClientError { statusCode: int, message: string }
    ServerError { statusCode: int, details: string }
}

union IntOption {
    Some { value: int }
    None
}

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

// Process HTTP response with guards
func ProcessResponse(response: HttpResponse): string {
    return match response {
        // Pattern matching with guards on union types
        HttpResponse.Ok { statusCode, body } when statusCode == 200 => $"Success: {body}",
        HttpResponse.Ok { statusCode, body } when statusCode == 201 => $"Created: {body}",
        HttpResponse.Ok { statusCode, body } => $"OK ({statusCode}): {body}",

        HttpResponse.Redirect { location, permanent } when permanent == true => $"Moved permanently to {location}",
        HttpResponse.Redirect { location, permanent } => $"Redirected to {location}",

        HttpResponse.ClientError { statusCode, message } when statusCode == 404 => "Not found!",
        HttpResponse.ClientError { statusCode, message } when statusCode == 401 => "Unauthorized!",
        HttpResponse.ClientError { statusCode, message } => $"Client error {statusCode}: {message}",

        HttpResponse.ServerError { statusCode, details } => $"Server error {statusCode}: {details}"
    }
}

// Validate age with guards
func ValidateAge(age: IntOption): string {
    return match age {
        IntOption.Some { value } when value < 0 => "Age cannot be negative",
        IntOption.Some { value } when value > 150 => "Age seems unrealistic",
        IntOption.Some { value } when value < 18 => $"Minor: {value} years old",
        IntOption.Some { value } => $"Adult: {value} years old",
        IntOption.None => "Age not provided"
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

    // HTTP response processing
    Console.WriteLine("HTTP Response Processing:")
    ok200 := new HttpResponse.Ok { statusCode: 200, body: "Data loaded" }
    Console.WriteLine(ProcessResponse(ok200))

    ok201 := new HttpResponse.Ok { statusCode: 201, body: "Resource created" }
    Console.WriteLine(ProcessResponse(ok201))

    redirect := new HttpResponse.Redirect { location: "/new-url", permanent: true }
    Console.WriteLine(ProcessResponse(redirect))

    notFound := new HttpResponse.ClientError { statusCode: 404, message: "Page not found" }
    Console.WriteLine(ProcessResponse(notFound))

    serverError := new HttpResponse.ServerError { statusCode: 500, details: "Internal error" }
    Console.WriteLine(ProcessResponse(serverError))
    Console.WriteLine()

    // Age validation
    Console.WriteLine("Age Validation:")
    validAge := new IntOption.Some { value: 25 }
    Console.WriteLine(ValidateAge(validAge))

    minorAge := new IntOption.Some { value: 16 }
    Console.WriteLine(ValidateAge(minorAge))

    negativeAge := new IntOption.Some { value: -5 }
    Console.WriteLine(ValidateAge(negativeAge))

    unrealisticAge := new IntOption.Some { value: 200 }
    Console.WriteLine(ValidateAge(unrealisticAge))

    noAge := new IntOption.None { }
    Console.WriteLine(ValidateAge(noAge))
    Console.WriteLine()

    // FizzBuzz
    Console.WriteLine("FizzBuzz (1-20):")
    for i := 1; i <= 20; i++ {
        Console.Write($"{FizzBuzz(i)} ")
    }
    Console.WriteLine()
    Console.WriteLine()

    Console.WriteLine("Pattern guards allow complex matching logic!")
}
