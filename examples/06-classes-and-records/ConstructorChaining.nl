// Constructor Chaining Example
// Demonstrates constructor chaining with this() and base() initializers

// Base class with multiple constructors
class Person {
    Name: string
    Age: int
    Email: string

    // Full constructor
    constructor(name: string, age: int, email: string) {
        Name = name
        Age = age
        Email = email
        print $"Created person: {Name}, {Age} years old, {Email}"
    }

    // Constructor chaining to full constructor with default age
    constructor(name: string, email: string): this(name, 0, email) {
        print "  (using constructor chaining with default age)"
    }

    // Constructor chaining with all defaults except name
    constructor(name: string): this(name, 0, "") {
        print "  (using constructor chaining with name only)"
    }

    func GetInfo(): string {
        return $"{Name} ({Age})"
    }
}

// Derived class using base constructor
class Employee : Person {
    EmployeeId: string
    Department: string

    // Full constructor - calls base constructor
    constructor(name: string, age: int, email: string, empId: string, dept: string):
        base(name, age, email) {
        EmployeeId = empId
        Department = dept
        print $"  Employee ID: {EmployeeId}, Department: {Department}"
    }

    // Simplified constructor for new employees (calls this)
    constructor(name: string, empId: string, dept: string):
        this(name, 0, "", empId, dept) {
        print "  (new employee with minimal info)"
    }

    // Constructor for transferring employees (calls base then this)
    constructor(name: string, empId: string):
        this(name, empId, "Unassigned") {
        print "  (transferred employee - department TBD)"
    }

    func GetEmployeeInfo(): string {
        return $"{GetInfo()} - {EmployeeId} ({Department})"
    }
}

// Dependency injection pattern - simplified constructor
class UserService {
    Logger: ILogger
    Database: IDatabase
    Cache: ICache
    ConfigValue: string

    // Full constructor with all dependencies
    constructor(logger: ILogger, db: IDatabase, cache: ICache, config: string) {
        Logger = logger
        Database = db
        Cache = cache
        ConfigValue = config
    }

    // Simplified constructor for DI frameworks (uses defaults via chaining)
    constructor(logger: ILogger, db: IDatabase): this(logger, db, new MemoryCache(), "default") {
        print "Using default cache and config"
    }
}

// Mock interfaces for the example
interface ILogger {
    func Log(message: string)
}

interface IDatabase {
    func Query(sql: string): string[]
}

interface ICache {
    func Get(key: string): string?
}

class MemoryCache : ICache {
    func Get(key: string): string? {
        return null
    }
}

func Main() {
    print "=== Constructor Chaining Example ==="
    p1 := new Person("Alice", 30, "alice@example.com")
    p2 := new Person("Bob", "bob@example.com")
    p3 := new Person("Charlie")
    e1 := new Employee("Diana", 28, "diana@company.com", "EMP001", "Engineering")
    e2 := new Employee("Eve", "EMP002", "Sales")
    e3 := new Employee("Frank", "EMP003")
    print e1.GetEmployeeInfo()
    print e2.GetEmployeeInfo()
    print e3.GetEmployeeInfo()
}
