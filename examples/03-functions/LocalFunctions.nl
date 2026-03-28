import System.Linq

func ProcessData(items: int[]): int[] {
    func IsValid(value: int): bool {
        return value > 0 && value < 100
    }

    static func Transform(value: int): int {
        return value * 2
    }

    return items.Where(IsValid).Select(Transform).ToArray()
}

func RecursiveExample(n: int): int {
    func Factorial(num: int): int {
        if num <= 1 {
            return 1
        }

        return num * Factorial(num - 1)
    }

    return Factorial(n)
}

func Main(): void {
    items := [1, 5, 50, 75, 150, 200]
    filtered := ProcessData(items)

    print "Filtered items:"
    for item in filtered {
        print item
    }

    fact := RecursiveExample(5)
    print $"Factorial of 5 is {fact}"
}
