func TokenizeKinds(source: string): int[] {
    length := source.Length
    buffer := new int[](length + 1)
    count := TokenizeKindsInto(source, buffer)
    return CopyKinds(buffer, count)
}

func TokenizeKindsInto(source: string, buffer: int[]): int {
    position := 0
    length := source.Length
    count := 0

    while position < length {
        ch := source[position]

        if IsWhitespaceExceptNewline(ch) {
            position = position + 1
            continue
        }

        if ch == '\n' {
            count = AddKind(buffer, count, 136)
            position = position + 1
            continue
        }

        if ch == '\r' {
            count = AddKind(buffer, count, 136)
            position = position + 1
            if position < length && source[position] == '\n' {
                position = position + 1
            }
            continue
        }

        if ch == '#' {
            count = AddKind(buffer, count, 138)
            position = position + 1
            while position < length && source[position] != '\n' && source[position] != '\r' {
                position = position + 1
            }
            continue
        }

        if ch == '/' && position + 1 < length {
            next := source[position + 1]
            if next == '/' {
                position = position + 2
                while position < length && source[position] != '\n' && source[position] != '\r' {
                    position = position + 1
                }
                continue
            }

            if next == '*' {
                position = position + 2
                while position < length {
                    if source[position] == '*' && position + 1 < length && source[position + 1] == '/' {
                        position = position + 2
                        break
                    }

                    position = position + 1
                }
                continue
            }
        }

        if ch == '$' && position + 1 < length && source[position + 1] == '"' {
            if position + 3 < length && source[position + 2] == '"' && source[position + 3] == '"' {
                count = AddKind(buffer, count, 6)
                position = ScanRawString(source, position + 4, length)
            } else {
                count = AddKind(buffer, count, 4)
                position = ScanString(source, position + 1, length, true)
            }
            continue
        }

        if ch == '"' {
            if position + 2 < length && source[position + 1] == '"' && source[position + 2] == '"' {
                count = AddKind(buffer, count, 5)
                position = ScanRawString(source, position + 3, length)
            } else {
                count = AddKind(buffer, count, 4)
                position = ScanString(source, position, length, false)
            }
            continue
        }

        if ch == '\'' {
            count = AddKind(buffer, count, 3)
            position = ScanCharLiteral(source, position, length)
            continue
        }

        if IsDigit(ch) {
            count = AddKind(buffer, count, ScanNumberKind(source, position, length))
            position = ScanNumber(source, position, length)
            continue
        }

        if IsIdentifierStart(ch) {
            start := position
            position = position + 1
            while position < length && IsIdentifierPart(source[position]) {
                position = position + 1
            }

            count = AddKind(buffer, count, KeywordKind(source, start, position - start))
            continue
        }

        count = AddKind(buffer, count, OperatorKind(source, position, length))
        position = ScanOperator(source, position, length)
    }

    count = AddKind(buffer, count, 135)
    return count
}

func AddKind(buffer: int[], count: int, kind: int): int {
    buffer[count] = kind
    return count + 1
}

func CopyKinds(buffer: int[], count: int): int[] {
    result := new int[](count)
    i := 0
    while i < count {
        result[i] = buffer[i]
        i = i + 1
    }

    return result
}

func TokenizeCount(source: string): int {
    position := 0
    count := 0
    length := source.Length

    while position < length {
        ch := source[position]

        if IsWhitespaceExceptNewline(ch) {
            position = position + 1
            continue
        }

        if ch == '\n' {
            count = count + 1
            position = position + 1
            continue
        }

        if ch == '\r' {
            count = count + 1
            position = position + 1
            if position < length && source[position] == '\n' {
                position = position + 1
            }
            continue
        }

        if ch == '/' && position + 1 < length {
            next := source[position + 1]
            if next == '/' {
                position = position + 2
                while position < length && source[position] != '\n' && source[position] != '\r' {
                    position = position + 1
                }
                continue
            }

            if next == '*' {
                position = position + 2
                while position < length {
                    if source[position] == '*' && position + 1 < length && source[position + 1] == '/' {
                        position = position + 2
                        break
                    }

                    position = position + 1
                }
                continue
            }
        }

        if ch == '$' && position + 1 < length && source[position + 1] == '"' {
            count = count + 1
            if position + 3 < length && source[position + 2] == '"' && source[position + 3] == '"' {
                position = ScanRawString(source, position + 4, length)
            } else {
                position = ScanString(source, position + 1, length, true)
            }
            continue
        }

        if ch == '"' {
            count = count + 1
            if position + 2 < length && source[position + 1] == '"' && source[position + 2] == '"' {
                position = ScanRawString(source, position + 3, length)
            } else {
                position = ScanString(source, position, length, false)
            }
            continue
        }

        if ch == '\'' {
            count = count + 1
            position = ScanCharLiteral(source, position, length)
            continue
        }

        if IsDigit(ch) {
            count = count + 1
            position = ScanNumber(source, position, length)
            continue
        }

        if IsIdentifierStart(ch) {
            count = count + 1
            position = position + 1
            while position < length && IsIdentifierPart(source[position]) {
                position = position + 1
            }
            continue
        }

        count = count + 1
        position = ScanOperator(source, position, length)
    }

    return count + 1
}

func ScanString(source: string, position: int, length: int, isInterpolated: bool): int {
    position = position + 1
    interpolationDepth := 0
    nestedStringDepth := 0

    while position < length {
        ch := source[position]
        if ch == '\n' || ch == '\r' {
            return position
        }

        if isInterpolated {
            if nestedStringDepth > 0 {
                if ch == '\\' {
                    position = position + 2
                    continue
                }

                if ch == '"' {
                    nestedStringDepth = nestedStringDepth - 1
                }

                position = position + 1
                continue
            }

            if ch == '{' {
                interpolationDepth = interpolationDepth + 1
                position = position + 1
                continue
            }

            if ch == '}' && interpolationDepth > 0 {
                interpolationDepth = interpolationDepth - 1
                position = position + 1
                continue
            }

            if ch == '"' && interpolationDepth > 0 {
                nestedStringDepth = nestedStringDepth + 1
                position = position + 1
                continue
            }

            if ch == '"' && interpolationDepth == 0 {
                return position + 1
            }
        } else if ch == '"' {
            return position + 1
        }

        if ch == '\\' {
            position = position + 2
        } else {
            position = position + 1
        }
    }

    return position
}

func ScanRawString(source: string, position: int, length: int): int {
    while position < length {
        if source[position] == '"' && position + 2 < length && source[position + 1] == '"' && source[position + 2] == '"' {
            return position + 3
        }

        position = position + 1
    }

    return position
}

func ScanCharLiteral(source: string, position: int, length: int): int {
    position = position + 1
    if position >= length || source[position] == '\n' || source[position] == '\r' {
        return position
    }

    if source[position] == '\\' {
        position = position + 2
    } else {
        position = position + 1
    }

    if position < length && source[position] == '\'' {
        position = position + 1
    }

    return position
}

func ScanNumber(source: string, position: int, length: int): int {
    if source[position] == '0' && position + 1 < length && (source[position + 1] == 'x' || source[position + 1] == 'X') {
        position = position + 2
        while position < length && (IsHexDigit(source[position]) || source[position] == '_') {
            position = position + 1
        }

        return ConsumeIntegerSuffix(source, position, length)
    }

    if source[position] == '0' && position + 1 < length && (source[position + 1] == 'b' || source[position + 1] == 'B') {
        position = position + 2
        while position < length && (source[position] == '0' || source[position] == '1' || source[position] == '_') {
            position = position + 1
        }

        return ConsumeIntegerSuffix(source, position, length)
    }

    isFloat := false
    while position < length && (IsDigit(source[position]) || source[position] == '.' || source[position] == '_') {
        if source[position] == '.' {
            if position + 1 < length && source[position + 1] == '.' {
                break
            }

            if position + 1 >= length || !IsDigit(source[position + 1]) {
                break
            }

            isFloat = true
        }

        position = position + 1
    }

    if position < length && (source[position] == 'e' || source[position] == 'E') {
        isFloat = true
        position = position + 1
        if position < length && (source[position] == '+' || source[position] == '-') {
            position = position + 1
        }

        while position < length && (IsDigit(source[position]) || source[position] == '_') {
            position = position + 1
        }
    }

    if isFloat {
        return ConsumeFloatSuffix(source, position, length)
    }

    if position < length && (source[position] == 'm' || source[position] == 'M') {
        return position + 1
    }

    return ConsumeIntegerSuffix(source, position, length)
}

func ScanNumberKind(source: string, position: int, length: int): int {
    if source[position] == '0' && position + 1 < length && (source[position + 1] == 'x' || source[position + 1] == 'X') {
        return 1
    }

    if source[position] == '0' && position + 1 < length && (source[position + 1] == 'b' || source[position + 1] == 'B') {
        return 1
    }

    while position < length && (IsDigit(source[position]) || source[position] == '.' || source[position] == '_') {
        if source[position] == '.' {
            if position + 1 < length && source[position + 1] == '.' {
                return 1
            }

            if position + 1 >= length || !IsDigit(source[position + 1]) {
                return 1
            }

            return 2
        }

        position = position + 1
    }

    if position < length && (source[position] == 'e' || source[position] == 'E') {
        return 2
    }

    if position < length && (source[position] == 'm' || source[position] == 'M') {
        return 2
    }

    return 1
}

func ConsumeFloatSuffix(source: string, position: int, length: int): int {
    if position < length && (source[position] == 'f' || source[position] == 'F' || source[position] == 'd' || source[position] == 'D' || source[position] == 'm' || source[position] == 'M') {
        return position + 1
    }

    return position
}

func ConsumeIntegerSuffix(source: string, position: int, length: int): int {
    if position < length && (source[position] == 'u' || source[position] == 'U') {
        position = position + 1
        if position < length && (source[position] == 'l' || source[position] == 'L') {
            position = position + 1
        }
        return position
    }

    if position < length && (source[position] == 'l' || source[position] == 'L') {
        position = position + 1
        if position < length && (source[position] == 'u' || source[position] == 'U') {
            position = position + 1
        }
        return position
    }

    return position
}

func OperatorKind(source: string, position: int, length: int): int {
    ch := source[position]
    if position + 1 < length {
        next := source[position + 1]
        if ch == ':' {
            if next == '=' {
                return 121
            }
            if next == ':' {
                return 123
            }
        }

        if ch == '=' {
            if next == '=' {
                return 98
            }
            if next == '>' {
                return 120
            }
        }

        if ch == '!' && next == '=' {
            return 99
        }

        if ch == '<' {
            if next == '=' {
                return 101
            }
            if next == '<' {
                return 111
            }
        }

        if ch == '>' {
            if next == '=' {
                return 103
            }
            if next == '>' {
                return 112
            }
        }

        if ch == '&' && next == '&' {
            return 104
        }

        if ch == '|' && next == '|' {
            return 105
        }

        if ch == '+' {
            if next == '+' {
                return 113
            }
            if next == '=' {
                return 94
            }
        }

        if ch == '-' {
            if next == '-' {
                return 114
            }
            if next == '=' {
                return 95
            }
        }

        if ch == '*' && next == '=' {
            return 96
        }

        if ch == '/' && next == '=' {
            return 97
        }

        if ch == '?' {
            if next == '?' {
                if position + 2 < length && source[position + 2] == '=' {
                    return 117
                }

                return 116
            }

            if next == '.' {
                return 118
            }

            if next == '[' {
                return 119
            }
        }

        if ch == '.' && next == '.' {
            if position + 2 < length && source[position + 2] == '.' {
                return 126
            }

            return 125
        }
    }

    if ch == '+' {
        return 88
    }

    if ch == '-' {
        return 89
    }

    if ch == '*' {
        return 90
    }

    if ch == '/' {
        return 91
    }

    if ch == '%' {
        return 92
    }

    if ch == '=' {
        return 93
    }

    if ch == '<' {
        return 100
    }

    if ch == '>' {
        return 102
    }

    if ch == '!' {
        return 106
    }

    if ch == '&' {
        return 107
    }

    if ch == '|' {
        return 108
    }

    if ch == '^' {
        return 109
    }

    if ch == '~' {
        return 110
    }

    if ch == '?' {
        return 115
    }

    if ch == ':' {
        return 122
    }

    if ch == '.' {
        return 124
    }

    if ch == '(' {
        return 127
    }

    if ch == ')' {
        return 128
    }

    if ch == '{' {
        return 129
    }

    if ch == '}' {
        return 130
    }

    if ch == '[' {
        return 131
    }

    if ch == ']' {
        return 132
    }

    if ch == ';' {
        return 133
    }

    if ch == ',' {
        return 134
    }

    return 137
}

func KeywordKind(source: string, start: int, length: int): int {
    if length == 2 {
        if IsKeyword(source, start, length, "if") {
            return 23
        }
        if IsKeyword(source, start, length, "in") {
            return 28
        }
        if IsKeyword(source, start, length, "is") {
            return 47
        }
        if IsKeyword(source, start, length, "as") {
            return 48
        }
        if IsKeyword(source, start, length, "or") {
            return 56
        }
    }

    if length == 3 {
        if IsKeyword(source, start, length, "for") {
            return 25
        }
        if IsKeyword(source, start, length, "let") {
            return 19
        }
        if IsKeyword(source, start, length, "new") {
            return 41
        }
        if IsKeyword(source, start, length, "try") {
            return 38
        }
        if IsKeyword(source, start, length, "and") {
            return 55
        }
        if IsKeyword(source, start, length, "not") {
            return 57
        }
        if IsKeyword(source, start, length, "out") {
            return 79
        }
    }

    if length == 4 {
        if IsKeyword(source, start, length, "func") {
            return 7
        }
        if IsKeyword(source, start, length, "duck") {
            return 11
        }
        if IsKeyword(source, start, length, "enum") {
            return 14
        }
        if IsKeyword(source, start, length, "true") {
            return 44
        }
        if IsKeyword(source, start, length, "base") {
            return 43
        }
        if IsKeyword(source, start, length, "null") {
            return 46
        }
        if IsKeyword(source, start, length, "this") {
            return 42
        }
        if IsKeyword(source, start, length, "case") {
            return 33
        }
        if IsKeyword(source, start, length, "else") {
            return 24
        }
        if IsKeyword(source, start, length, "lock") {
            return 80
        }
        if IsKeyword(source, start, length, "file") {
            return 81
        }
        if IsKeyword(source, start, length, "type") {
            return 72
        }
        if IsKeyword(source, start, length, "init") {
            return 77
        }
        if IsKeyword(source, start, length, "when") {
            return 54
        }
    }

    if length == 5 {
        if IsKeyword(source, start, length, "class") {
            return 8
        }
        if IsKeyword(source, start, length, "union") {
            return 12
        }
        if IsKeyword(source, start, length, "using") {
            return 16
        }
        if IsKeyword(source, start, length, "const") {
            return 21
        }
        if IsKeyword(source, start, length, "while") {
            return 27
        }
        if IsKeyword(source, start, length, "yield") {
            return 30
        }
        if IsKeyword(source, start, length, "match") {
            return 31
        }
        if IsKeyword(source, start, length, "break") {
            return 35
        }
        if IsKeyword(source, start, length, "catch") {
            return 39
        }
        if IsKeyword(source, start, length, "false") {
            return 45
        }
        if IsKeyword(source, start, length, "where") {
            return 53
        }
        if IsKeyword(source, start, length, "async") {
            return 68
        }
        if IsKeyword(source, start, length, "await") {
            return 69
        }
        if IsKeyword(source, start, length, "print") {
            return 52
        }
    }

    if length == 6 {
        if IsKeyword(source, start, length, "struct") {
            return 9
        }
        if IsKeyword(source, start, length, "record") {
            return 13
        }
        if IsKeyword(source, start, length, "import") {
            return 17
        }
        if IsKeyword(source, start, length, "return") {
            return 29
        }
        if IsKeyword(source, start, length, "switch") {
            return 32
        }
        if IsKeyword(source, start, length, "throw") {
            return 37
        }
        if IsKeyword(source, start, length, "typeof") {
            return 49
        }
        if IsKeyword(source, start, length, "nameof") {
            return 50
        }
        if IsKeyword(source, start, length, "sizeof") {
            return 51
        }
        if IsKeyword(source, start, length, "sealed") {
            return 61
        }
        if IsKeyword(source, start, length, "static") {
            return 63
        }
        if IsKeyword(source, start, length, "public") {
            return 64
        }
        if IsKeyword(source, start, length, "params") {
            return 82
        }
    }

    if length == 7 {
        if IsKeyword(source, start, length, "package") {
            return 18
        }
        if IsKeyword(source, start, length, "foreach") {
            return 26
        }
        if IsKeyword(source, start, length, "default") {
            return 34
        }
        if IsKeyword(source, start, length, "finally") {
            return 40
        }
        if IsKeyword(source, start, length, "virtual") {
            return 58
        }
        if IsKeyword(source, start, length, "partial") {
            return 62
        }
        if IsKeyword(source, start, length, "private") {
            return 65
        }
        if IsKeyword(source, start, length, "checked") {
            return 83
        }
        if IsKeyword(source, start, length, "newtype") {
            return 87
        }
    }

    if length == 8 {
        if IsKeyword(source, start, length, "readonly") {
            return 22
        }
        if IsKeyword(source, start, length, "continue") {
            return 36
        }
        if IsKeyword(source, start, length, "abstract") {
            return 60
        }
        if IsKeyword(source, start, length, "internal") {
            return 66
        }
        if IsKeyword(source, start, length, "required") {
            return 76
        }
        if IsKeyword(source, start, length, "implicit") {
            return 85
        }
        if IsKeyword(source, start, length, "explicit") {
            return 86
        }
    }

    if length == 9 {
        if IsKeyword(source, start, length, "interface") {
            return 10
        }
        if IsKeyword(source, start, length, "namespace") {
            return 15
        }
        if IsKeyword(source, start, length, "protected") {
            return 67
        }
        if IsKeyword(source, start, length, "immutable") {
            return 70
        }
        if IsKeyword(source, start, length, "unchecked") {
            return 84
        }
    }

    if length == 8 {
        if IsKeyword(source, start, length, "operator") {
            return 75
        }
    }

    if length == 4 {
        if IsKeyword(source, start, length, "test") {
            return 73
        }
    }

    if length == 6 {
        if IsKeyword(source, start, length, "assert") {
            return 74
        }
    }

    if length == 8 {
        if IsKeyword(source, start, length, "override") {
            return 59
        }
    }

    if length == 4 {
        if IsKeyword(source, start, length, "with") {
            return 71
        }
    }

    if length == 3 {
        if IsKeyword(source, start, length, "ref") {
            return 78
        }
    }

    if length == 4 {
        if IsKeyword(source, start, length, "must") {
            return 20
        }
    }

    return 0
}

func IsKeyword(source: string, start: int, length: int, keyword: string): bool {
    if keyword.Length != length {
        return false
    }

    i := 0
    while i < length {
        if source[start + i] != keyword[i] {
            return false
        }

        i = i + 1
    }

    return true
}

func ScanOperator(source: string, position: int, length: int): int {
    ch := source[position]
    if position + 1 >= length {
        return position + 1
    }

    next := source[position + 1]
    if ch == ':' && (next == '=' || next == ':') {
        return position + 2
    }

    if ch == '=' && (next == '=' || next == '>') {
        return position + 2
    }

    if ch == '!' && next == '=' {
        return position + 2
    }

    if ch == '<' && (next == '=' || next == '<') {
        return position + 2
    }

    if ch == '>' && (next == '=' || next == '>') {
        return position + 2
    }

    if ch == '&' && next == '&' {
        return position + 2
    }

    if ch == '|' && next == '|' {
        return position + 2
    }

    if ch == '+' && (next == '+' || next == '=') {
        return position + 2
    }

    if ch == '-' && (next == '-' || next == '=') {
        return position + 2
    }

    if ch == '*' && next == '=' {
        return position + 2
    }

    if ch == '/' && next == '=' {
        return position + 2
    }

    if ch == '?' {
        if next == '.' || next == '[' {
            return position + 2
        }

        if next == '?' {
            if position + 2 < length && source[position + 2] == '=' {
                return position + 3
            }

            return position + 2
        }
    }

    if ch == '.' && next == '.' {
        if position + 2 < length && source[position + 2] == '.' {
            return position + 3
        }

        return position + 2
    }

    return position + 1
}

func IsWhitespaceExceptNewline(ch: char): bool {
    return ch == ' ' || ch == '\t' || ch == '\f' || ch == '\v'
}

func IsIdentifierStart(ch: char): bool {
    return ch == '_' || (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z')
}

func IsIdentifierPart(ch: char): bool {
    return IsIdentifierStart(ch) || IsDigit(ch)
}

func IsDigit(ch: char): bool {
    return ch >= '0' && ch <= '9'
}

func IsHexDigit(ch: char): bool {
    return IsDigit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}
