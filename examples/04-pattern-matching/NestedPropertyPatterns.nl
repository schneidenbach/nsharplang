// Nested Property Patterns Example
// Demonstrates deep object destructuring in match expressions

import System

class Address {
    Street: string
    City: string
    State: string
    ZipCode: string
}

class Person {
    Name: string
    Age: int
    Address: Address
    HasAddress: bool
}

class Company {
    Name: string
    Headquarters: Address
    HasHQ: bool
}

func ClassifyPerson(person: Person): string {
    // Match with nested property patterns
    return match person {
        // Deep nesting: check if person lives in NYC
        { Address: { City: "New York", State: "NY" } } => "New Yorker",

        // Nested with binding: extract the city name
        { Address: { City: city, State: "CA" } } => $"Californian from {city}",

        // Nested with literal: check specific state
        { Address: { State: "TX" } } => "Texan",

        // Check HasAddress flag
        { HasAddress: false } => "No address on file",

        // Default case
        _ => "Other location"
    }
}

func DescribeCompany(company: Company): string {
    // Three-level nesting
    return match company {
        { Headquarters: { City: "New York", State: "NY", ZipCode: zip } }
            => $"NYC company in {zip}",

        { Headquarters: { City: city, State: state } }
            => $"Based in {city}, {state}",

        { HasHQ: false } => "Remote company",

        _ => "Unknown"
    }
}

func AnalyzePerson(person: Person): string {
    // Combining age check with nested address pattern
    return match person {
        { Age: age, Address: { City: "New York" } } when age < 30
            => "Young New Yorker",

        { Age: age, Address: { State: "CA" } } when age >= 65
            => "Senior Californian",

        { Age: age, HasAddress: false } when age < 18
            => "Minor with no address",

        _ => "Regular person"
    }
}

// Union type with nested patterns
union ApiResponse {
    Success { data: ResponseData }
    Error { message: string, code: int }
}

class ResponseData {
    UserId: int
    UserName: string
    IsActive: bool
}

func HandleResponse(response: ApiResponse): string {
    return match response {
        // Nested pattern in union case
        ApiResponse.Success { data: { UserName: name, IsActive: true } }
            => $"Active user: {name}",

        ApiResponse.Success { data: { UserName: name, IsActive: false } }
            => $"Inactive user: {name}",

        ApiResponse.Error { message, code }
            => $"Error {code}: {message}"
    }
}

func Main() {
    print "=== Nested Property Patterns Example ==="
    print ""

    // Test person in NYC
    addr1 := new Address {
        Street: "123 Broadway",
        City: "New York",
        State: "NY",
        ZipCode: "10001"
    }
    person1 := new Person {
        Name: "Alice",
        Age: 25,
        Address: addr1,
        HasAddress: true
    }

    print $"Person 1: {ClassifyPerson(person1)}"
    print $"Analysis: {AnalyzePerson(person1)}"
    print ""

    // Test person in California
    addr2 := new Address {
        Street: "456 Main St",
        City: "San Francisco",
        State: "CA",
        ZipCode: "94102"
    }
    person2 := new Person {
        Name: "Bob",
        Age: 70,
        Address: addr2,
        HasAddress: true
    }

    print $"Person 2: {ClassifyPerson(person2)}"
    print $"Analysis: {AnalyzePerson(person2)}"
    print ""

    // Test person with no address
    dummyAddr := new Address {
        Street: "",
        City: "",
        State: "",
        ZipCode: ""
    }
    person3 := new Person {
        Name: "Charlie",
        Age: 15,
        Address: dummyAddr,
        HasAddress: false
    }

    print $"Person 3: {ClassifyPerson(person3)}"
    print $"Analysis: {AnalyzePerson(person3)}"
    print ""

    // Test company
    company := new Company {
        Name: "TechCorp",
        Headquarters: addr1,
        HasHQ: true
    }

    print $"Company: {DescribeCompany(company)}"
    print ""

    // Test API response
    responseData := new ResponseData {
        UserId: 42,
        UserName: "Alice",
        IsActive: true
    }

    response := new ApiResponse.Success { data: responseData }
    print $"API Response: {HandleResponse(response)}"

    // Test error response
    errorResponse := new ApiResponse.Error {
        message: "User not found",
        code: 404
    }
    print $"Error Response: {HandleResponse(errorResponse)}"
}
