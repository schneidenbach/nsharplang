// Interpolated Raw String Literals Example
// Demonstrates C# 11 raw string interpolation feature in N#

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

    // 1. SQL query with raw strings (quotes and special chars work naturally!)
    userId := 123
    sql := $"""
    SELECT *
    FROM users
    WHERE id = {userId}
      AND status = 'active'
      AND created_at >= '2024-01-01'
    """

    print "=== SQL Query ==="
    print sql

    // 2. HTML template with raw strings
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

    // 3. Multi-line report with interpolation
    name := person.Name
    age := person.Age
    email := person.Email
    report := $"""
    ================================
    User Report
    ================================
    Name:  {name}
    Age:   {age}
    Email: {email}
    ================================
    """

    print "\n=== Report ==="
    print report

    print "\n=== Key Benefits ==="
    print "1. No need to escape quotes inside raw strings"
    print "2. Multi-line strings preserve formatting"
    print "3. Interpolation works with $-prefix triple quotes"
    print "4. Great for SQL, HTML, XML, and other embedded languages"
}
