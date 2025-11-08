// Interpolated Raw String Literals Example
// Demonstrates C# 11 raw string interpolation feature in N#

import System

class Person {
    Name: string
    Age: int
    Email: string

    constructor(name: string, age: int, email: string) {
        Name = name
        Age = age
        Email = email
    }
}

func Main() {
    person := new Person("Alice Johnson", 30, "alice@example.com")

    // 1. JSON generation with raw strings (no escape sequences needed!)
    json := $"""
    {
        "name": "{person.Name}",
        "age": {person.Age},
        "email": "{person.Email}"
    }
    """

    print "=== JSON Output ==="
    print json

    // 2. SQL query with raw strings
    userId := 123
    sql := $"""
    SELECT *
    FROM users
    WHERE id = {userId}
      AND status = 'active'
      AND created_at >= '2024-01-01'
    """

    print "\n=== SQL Query ==="
    print sql

    // 3. HTML template with raw strings
    title := "Welcome Page"
    content := "Hello, World!"
    html := $"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>{title}</title>
    </head>
    <body>
        <h1>{content}</h1>
        <p>This is generated HTML</p>
    </body>
    </html>
    """

    print "\n=== HTML Template ==="
    print html

    // 4. Regular expression patterns (quotes and backslashes work naturally!)
    pattern := $"""
    ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$
    """

    print "\n=== Regex Pattern ==="
    print pattern
}

func GenerateTable(headers: string[], rows: string[][]): string {
    // Using raw string to generate ASCII table
    result := $"""
    +----------+-----+----------------------+
    | {headers[0],-8} | {headers[1],-3} | {headers[2],-20} |
    +----------+-----+----------------------+
    """

    for row in rows {
        result += $"""
    | {row[0],-8} | {row[1],-3} | {row[2],-20} |
    """
    }

    result += """
    +----------+-----+----------------------+
    """

    return result
}
