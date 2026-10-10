namespace Census.FreeFunctionIdentity.Y

import System
import System.Collections.Generic


// THE Y HALF. Identical spellings, different answers.
func Helper(): string {
    return "Y"
}

func helper(): string {
    return "y"
}

func UseHelperFromY(): string {
    return Helper()
}

func UseCamelHelperFromY(): string {
    return helper()
}

func HelperGroupFromY(): Func<string> {
    return Helper
}

func Split(): (First: string, Second: string) {
    return ("Y-first", "Y-second")
}

func SplitFirstFromY(): string {
    parts := Split()
    return parts.First
}

func LocalAndSiblingFromY(): string {
    func Marker(): string {
        return "y-local"
    }

    return Marker() + "/" + Helper()
}

func* Steps(): IEnumerable<int> {
    yield 10
    yield 20
}

func StepSumFromY(): int {
    total := 0
    for value in Steps() {
        total = total + value
    }
    return total
}
