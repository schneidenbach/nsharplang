namespace SystemsProofs.UnmanagedSortComparer

interface Sortable<T> {
    func LessThan(other: T): bool
}

struct PriceLevel: Sortable<PriceLevel> {
    Price: long
    Quantity: int

    func LessThan(other: PriceLevel): bool {
        return Price < other.Price
    }
}

[hot]
func SortPair<T>(items: T[]): int where T: struct, Sortable<T> {
    if items.Length < 2 {
        return 0
    }

    if items[1].LessThan(items[0]) {
        tmp := items[0]
        items[0] = items[1]
        items[1] = tmp
    }

    return 0
}

[boundary]
func Main(): int {
    levels := alloc new PriceLevel[3]
    levels[0] = new PriceLevel { Price: 101, Quantity: 10 }
    levels[1] = new PriceLevel { Price: 99, Quantity: 5 }
    levels[2] = new PriceLevel { Price: 104, Quantity: 2 }

    SortPair<PriceLevel>(levels)

    if levels[0].Price != 99 {
        return 1
    }
    if levels[1].Price != 101 {
        return 2
    }
    if levels[2].Price != 104 {
        return 3
    }
    return 0
}
