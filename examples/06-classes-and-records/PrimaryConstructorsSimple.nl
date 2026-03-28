// Primary Constructors (C# 12 Feature)
// Simple demonstration showing the syntax
class Logger(name: string) {
    logName: string = name

    func Log(message: string) {
        print $"[{logName}] {message}"
    }
}

struct Point {
    X: double = x
    Y: double = y

    func ToString(): string {
        return $"Point({X}, {Y})"
    }
}

record Person(name: string, age: int) {
    Name: string = name
    Age: int = age
}

func Main() {
    print "=== Primary Constructors Demo ==="

    logger := new Logger("MyApp")
    logger.Log("Hello World")

    p := new Point(3.0, 4.0)
    print p.ToString()

    person := new Person("Alice", 30)
    print $"{person.Name} is {person.Age} years old"
}
