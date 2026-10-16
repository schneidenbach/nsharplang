namespace NSharpLang.AutoProperties.Tests

import Microsoft.EntityFrameworkCore

// WHICH BARE MEMBERS ARE PROPERTIES (`MemberStorageRules`, website/docs/types.md "Fields and
// properties"). An exported instance member of a class or record is a get/set auto-property — what
// EF Core maps, what System.Text.Json serializes and what model binding binds. A camelCase or
// `private` member, a `static`, `readonly` or `const` one, and every member of a struct is a field.
class Order {
    Id: int
    Customer: string = ""
    Notes: string?
    protected Audit: string = "created"
    internal Batch: int = 7
    lines: int = 3
    private total: int = 10
    private Hidden: int = 11
    static Created: int = 0
    readonly Stamp: int = 42
    const Version: int = 2

    func LinesAndTotal(): int => lines + total + Hidden
    func AuditTrail(): string => Audit
}

struct Point {
    X: double
    Y: double
}

record Person {
    Name: string = ""
    Age: int
}

record struct Pair {
    Left: int
    Right: int
}

// A POSITIONAL MEMBER FOLLOWS THE SAME RULE: `Name` and `Age` are properties, the camelCase capture
// `secret` a field.
record Customer(Name: string, Age: int) {
}

class Service(secret: string, Label: string) {
    func Secret(): string => secret
}

// EF CORE POPULATES A `DbSet<T>` PROPERTY IN THE CONTEXT'S OWN CONSTRUCTOR, without a provider. As a
// field this member was never assigned and read back null.
class Shop: DbContext {
    People: DbSet<Person>
    Orders: DbSet<Order>
}

// A STRUCT-TYPED AUTO-PROPERTY IS READ AS A COPY, inside the type and out.
struct Tally {
    count: int

    func Bump() {
        count = count + 1
    }

    func Read(): int => count
}

class Scoreboard {
    Home: Tally = new Tally()
    away: Tally = new Tally()
    Total: int
    Label: string = "game"

    func BumpBoth(): string {
        Home.Bump()
        away.Bump()
        return Home.Read().ToString() + "/" + away.Read().ToString()
    }

    func Score(points: int): int {
        Total += points
        this.Total *= 2
        Total++
        return Total
    }
}

class Overtime: Scoreboard {
    func Extra(): int {
        Total += 100
        Total--
        return Total
    }
}

// A GENERIC CLASS'S MEMBERS ARE PROPERTIES OF EVERY INSTANTIATION.
class Box<T> {
    Value: T
    Count: int

    func Add(n: int): int {
        Count += n
        return Count
    }
}
