func AnonymousUnionDeclaresPublicShim(parameterFlags: int[], count: int): int {
    if count < 0 || count > parameterFlags.Length {
        return -1
    }

    return AnonymousUnionDeclaresPublicShimTrusted(parameterFlags, count)
}

func AnonymousUnionDeclaresPublicShimTrusted(parameterFlags: int[], count: int): int {
    hasEligibleUnion := 0
    i := 0
    limit := count - 7
    while i < limit {
        a := parameterFlags[i]
        b := parameterFlags[i + 1]
        c := parameterFlags[i + 2]
        d := parameterFlags[i + 3]
        e := parameterFlags[i + 4]
        f := parameterFlags[i + 5]
        g := parameterFlags[i + 6]
        h := parameterFlags[i + 7]

        if a == 2 || b == 2 || c == 2 || d == 2 || e == 2 || f == 2 || g == 2 || h == 2 {
            return 0
        }

        if a + b + c + d + e + f + g + h != 0 {
            hasEligibleUnion = 1
        }

        i = i + 8
    }

    while i < count {
        flag := parameterFlags[i]
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

func AnonymousUnionDeclaresPublicShimChecksum(parameterFlags: int[], count: int): int {
    result := AnonymousUnionDeclaresPublicShim(parameterFlags, count)
    if result < 0 {
        return result
    }

    checksum := result * 17 + count
    i := 0
    while i < count {
        checksum = checksum + parameterFlags[i] * 31 + (i + 1) * 7
        i = i + 1
    }

    return checksum
}
