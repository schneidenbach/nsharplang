namespace MultiFileProject.Models


// Person record - immutable data type
record Person {
    Name: string
    Age: int
    Email: string

    func GetInfo(): string {
        return $"{Name} ({Age}) - {Email}"
    }
}

// Status enum
enum Status: string {
    Active = "active",
    Inactive = "inactive",
    Pending = "pending"
}
