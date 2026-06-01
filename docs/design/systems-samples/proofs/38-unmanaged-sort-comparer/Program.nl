namespace SystemsProofs.UnmanagedSortComparer

import System

interface ValueComparer<T> where T : unmanaged {
    func Less(a: T, b: T): bool
}

struct PriceLevel {
    Price: long
    Quantity: int
}

struct PriceAscending : ValueComparer<PriceLevel> {
    func Less(a: PriceLevel, b: PriceLevel): bool {
        return a.Price < b.Price
    }
}

[hot]
func Sort<T, TComparer>(items: Span<T>, comparer: TComparer)
    where T : unmanaged
    where TComparer : struct, ValueComparer<T> {
    for i := 1; i < items.Length; i++ {
        j := i
        while j > 0 && comparer.Less(items[j], items[j - 1]) {
            tmp := items[j - 1]
            items[j - 1] = items[j]
            items[j] = tmp
            j = j - 1
        }
    }
}

func Main() {
    levels := new PriceLevel[] {
        PriceLevel { Price: 101, Quantity: 10 },
        PriceLevel { Price: 99, Quantity: 5 }
    }
    Sort(levels, PriceAscending {})
}
