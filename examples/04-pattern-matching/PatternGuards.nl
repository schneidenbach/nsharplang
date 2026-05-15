import System


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

    // HTTP response processing
    print "HTTP Response Processing:"
    ok200 := new HttpResponse.Ok(200, "Data loaded")
    print ProcessResponse(ok200)

    ok201 := new HttpResponse.Ok(201, "Resource created")
    print ProcessResponse(ok201)

    redirect := new HttpResponse.Redirect("/new-url", true)
    print ProcessResponse(redirect)

    notFound := new HttpResponse.ClientError(404, "Page not found")
    print ProcessResponse(notFound)

    serverError := new HttpResponse.ServerError(500, "Internal error")
    print ProcessResponse(serverError)
    print ""

    // Age validation
    print "Age Validation:"
    validAge := new IntOption.Some(25)
    print ValidateAge(validAge)

    minorAge := new IntOption.Some(16)
    print ValidateAge(minorAge)

    negativeAge := new IntOption.Some(-5)
    print ValidateAge(negativeAge)

    unrealisticAge := new IntOption.Some(200)
    print ValidateAge(unrealisticAge)

    noAge := new IntOption.None {  }
    print ValidateAge(noAge)
    print ""

    // FizzBuzz
    print "FizzBuzz (1-20):"
    for i := 1; i <= 20; i++ {
        Console.Write($"{FizzBuzz(i)} ")
    }

    print ""
    print ""

    print "Pattern guards allow complex matching logic!"
}
