// CLR assembly-version component parsing kernels.
//
// Mirrors int.TryParse(component, NumberStyles.None, InvariantCulture) for non-negative
// version components after the caller has split the package-version numeric core.

struct AssemblyVersionIntResultTable {
    Values: int[]
}

func AssemblyVersionTryParseComponentInto(component: string, result: int[]): int {
    if result.Length < 1 {
        return -1
    }

    result[0] = 0
    values := new AssemblyVersionIntResultTable { Values: result }
    if AssemblyVersionTryParseComponentCore(component, ref values, 0) {
        return 1
    }

    return 0
}

func AssemblyVersionTryParseComponentCore(
    component: string,
    result: &AssemblyVersionIntResultTable,
    resultIndex: int): bool {
    if component.Length == 0 {
        return false
    }

    value := 0
    index := 0
    while index < component.Length {
        ch := component[index]
        if ch < '0' || ch > '9' {
            return false
        }

        digit := ch - '0'
        if value > 214748364 {
            return false
        }

        if value == 214748364 && digit > 7 {
            return false
        }

        value = value * 10 + digit
        index = index + 1
    }

    result.Values[resultIndex] = value
    return true
}

func AssemblyVersionMinInt(a: int, b: int): int {
    if a < b {
        return a
    }

    return b
}
