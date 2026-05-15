// Product.nl — Types auto-discovered by the project compiler.
// No explicit import needed from other project files.

namespace AutoDiscovery.Models

record Product {
    Id: int
    Name: string
    Price: decimal

    func Display(): string {
        return $"{Name} (${Price})"
    }
}

enum Category: string {
    Electronics = "electronics",
    Books = "books",
    Clothing = "clothing"
}
