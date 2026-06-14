struct AnonymousUnionParameterTable {
    Flags: int[]
}

func AnonymousUnionDeclaresPublicShim(parameterFlags: int[], count: int): int {
    if count < 0 || count > parameterFlags.Length {
        return -1
    }

    parameters := new AnonymousUnionParameterTable { Flags: parameterFlags }
    return AnonymousUnionDeclaresPublicShimTrustedCore(ref parameters, count)
}

func AnonymousUnionDeclaresPublicShimTrustedCore(parameters: &AnonymousUnionParameterTable, count: int): int {
    hasEligibleUnion := 0
    i := 0
    limit := count - 7
    while i < limit {
        a := parameters.Flags[i]
        b := parameters.Flags[i + 1]
        c := parameters.Flags[i + 2]
        d := parameters.Flags[i + 3]
        e := parameters.Flags[i + 4]
        f := parameters.Flags[i + 5]
        g := parameters.Flags[i + 6]
        h := parameters.Flags[i + 7]

        if a == 2 || b == 2 || c == 2 || d == 2 || e == 2 || f == 2 || g == 2 || h == 2 {
            return 0
        }

        if a + b + c + d + e + f + g + h != 0 {
            hasEligibleUnion = 1
        }

        i = i + 8
    }

    while i < count {
        flag := parameters.Flags[i]
        if flag == 2 {
            return 0
        }

        if flag == 1 {
            hasEligibleUnion = 1
        }

        i = i + 1
    }

    return hasEligibleUnion
}
