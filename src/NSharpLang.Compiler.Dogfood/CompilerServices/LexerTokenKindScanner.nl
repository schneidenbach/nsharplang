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
            buffer[count] = 136
            count = count + 1
            position = position + 1
            continue
        }

        if ch == '\r' {
            buffer[count] = 136
            count = count + 1
            position = position + 1
            if position < length && source[position] == '\n' {
                position = position + 1
            }
            continue
        }

        if ch == '#' {
            buffer[count] = 138
            count = count + 1
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
                buffer[count] = 6
                count = count + 1
                position = ScanRawString(source, position + 4, length)
            } else {
                buffer[count] = 4
                count = count + 1
                position = ScanString(source, position + 1, length, true)
            }
            continue
        }

        if ch == '"' {
            if position + 2 < length && source[position + 1] == '"' && source[position + 2] == '"' {
                buffer[count] = 5
                count = count + 1
                position = ScanRawString(source, position + 3, length)
            } else {
                buffer[count] = 4
                count = count + 1
                position = ScanString(source, position, length, false)
            }
            continue
        }

        if ch == '\'' {
            buffer[count] = 3
            count = count + 1
            position = ScanCharLiteral(source, position, length)
            continue
        }

        if IsDigit(ch) {
            buffer[count] = ScanNumberKind(source, position, length)
            count = count + 1
            position = ScanNumber(source, position, length)
            continue
        }

        if IsIdentifierStart(ch) {
            start := position
            position = position + 1
            while position < length && IsIdentifierPart(source[position]) {
                position = position + 1
            }

            buffer[count] = KeywordKind(source, start, position - start)
            count = count + 1
            continue
        }

        operatorInfo := OperatorInfo(source, position, length)
        operatorKind := operatorInfo / 4
        buffer[count] = operatorKind
        count = count + 1
        position = position + (operatorInfo - operatorKind * 4)
    }

    buffer[count] = 135
    count = count + 1
    return count
}

func TokenizeMetadataInto(source: string, kinds: int[], starts: int[], valueLengths: int[], lines: int[], columns: int[]): int {
    position := 0
    length := source.Length
    count := 0
    line := 1
    column := 1

    while position < length {
        ch := source[position]

        if IsWhitespaceExceptNewline(ch) {
            position = position + 1
            column = column + 1
            continue
        }

        start := position
        tokenLine := line
        tokenColumn := column

        if ch == '\n' {
            kinds[count] = 136
            starts[count] = start
            valueLengths[count] = 1
            lines[count] = tokenLine
            columns[count] = tokenColumn
            count = count + 1
            position = position + 1
            line = line + 1
            column = 1
            continue
        }

        if ch == '\r' {
            kinds[count] = 136
            starts[count] = start
            valueLengths[count] = 1
            lines[count] = tokenLine
            columns[count] = tokenColumn
            count = count + 1
            position = position + 1
            if position < length && source[position] == '\n' {
                position = position + 1
            }
            line = line + 1
            column = 1
            continue
        }

        if ch == '#' {
            position = position + 1
            column = column + 1
            while position < length && source[position] != '\n' && source[position] != '\r' {
                position = position + 1
                column = column + 1
            }

            kinds[count] = 138
            starts[count] = start
            valueLengths[count] = position - start
            lines[count] = tokenLine
            columns[count] = tokenColumn
            count = count + 1
            continue
        }

        if ch == '/' && position + 1 < length {
            next := source[position + 1]
            if next == '/' {
                position = position + 2
                column = column + 2
                while position < length && source[position] != '\n' && source[position] != '\r' {
                    position = position + 1
                    column = column + 1
                }
                continue
            }

            if next == '*' {
                position = position + 2
                column = column + 2
                while position < length {
                    if source[position] == '*' && position + 1 < length && source[position + 1] == '/' {
                        position = position + 2
                        column = column + 2
                        break
                    }

                    if source[position] == '\r' {
                        position = position + 1
                        if position < length && source[position] == '\n' {
                            position = position + 1
                        }
                        line = line + 1
                        column = 1
                        continue
                    }

                    if source[position] == '\n' {
                        position = position + 1
                        line = line + 1
                        column = 1
                        continue
                    }

                    position = position + 1
                    column = column + 1
                }
                continue
            }
        }

        if ch == '$' && position + 1 < length && source[position + 1] == '"' {
            if position + 3 < length && source[position + 2] == '"' && source[position + 3] == '"' {
                nextPosition := ScanRawString(source, position + 4, length)
                kinds[count] = 6
                starts[count] = start
                valueLengths[count] = nextPosition - start
                lines[count] = tokenLine
                columns[count] = tokenColumn
                count = count + 1
                while position < nextPosition {
                    if source[position] == '\r' {
                        position = position + 1
                        if position < nextPosition && source[position] == '\n' {
                            position = position + 1
                        }
                        line = line + 1
                        column = 1
                        continue
                    }

                    if source[position] == '\n' {
                        position = position + 1
                        line = line + 1
                        column = 1
                        continue
                    }

                    position = position + 1
                    column = column + 1
                }
            } else {
                nextPosition := ScanString(source, position + 1, length, true)
                kinds[count] = 4
                starts[count] = start
                valueLengths[count] = nextPosition - start
                lines[count] = tokenLine
                columns[count] = tokenColumn
                count = count + 1
                column = column + (nextPosition - start)
                position = nextPosition
            }
            continue
        }

        if ch == '"' {
            if position + 2 < length && source[position + 1] == '"' && source[position + 2] == '"' {
                nextPosition := ScanRawString(source, position + 3, length)
                kinds[count] = 5
                starts[count] = start
                valueLengths[count] = RawStringValueLength(source, start, nextPosition)
                lines[count] = tokenLine
                columns[count] = tokenColumn
                count = count + 1
                while position < nextPosition {
                    if source[position] == '\r' {
                        position = position + 1
                        if position < nextPosition && source[position] == '\n' {
                            position = position + 1
                        }
                        line = line + 1
                        column = 1
                        continue
                    }

                    if source[position] == '\n' {
                        position = position + 1
                        line = line + 1
                        column = 1
                        continue
                    }

                    position = position + 1
                    column = column + 1
                }
            } else {
                nextPosition := ScanString(source, position, length, false)
                kinds[count] = 4
                starts[count] = start
                valueLengths[count] = nextPosition - start
                lines[count] = tokenLine
                columns[count] = tokenColumn
                count = count + 1
                column = column + (nextPosition - start)
                position = nextPosition
            }
            continue
        }

        if ch == '\'' {
            nextPosition := ScanCharLiteral(source, position, length)
            kinds[count] = 3
            starts[count] = start
            valueLengths[count] = nextPosition - start
            lines[count] = tokenLine
            columns[count] = tokenColumn
            count = count + 1
            column = column + (nextPosition - start)
            position = nextPosition
            continue
        }

        if IsDigit(ch) {
            nextPosition := ScanNumber(source, position, length)
            kinds[count] = ScanNumberKind(source, position, length)
            starts[count] = start
            valueLengths[count] = NumberValueLength(source, start, nextPosition)
            lines[count] = tokenLine
            columns[count] = tokenColumn
            count = count + 1
            column = column + (nextPosition - start)
            position = nextPosition
            continue
        }

        if IsIdentifierStart(ch) {
            position = position + 1
            while position < length && IsIdentifierPart(source[position]) {
                position = position + 1
            }

            kinds[count] = KeywordKind(source, start, position - start)
            starts[count] = start
            valueLengths[count] = position - start
            lines[count] = tokenLine
            columns[count] = tokenColumn
            count = count + 1
            column = column + (position - start)
            continue
        }

        operatorInfo := OperatorInfo(source, position, length)
        operatorKind := operatorInfo / 4
        operatorWidth := operatorInfo - operatorKind * 4
        kinds[count] = operatorKind
        starts[count] = start
        valueLengths[count] = operatorWidth
        lines[count] = tokenLine
        columns[count] = tokenColumn
        count = count + 1
        position = position + operatorWidth
        column = column + operatorWidth
    }

    kinds[count] = 135
    starts[count] = position
    valueLengths[count] = 0
    lines[count] = line
    columns[count] = column
    count = count + 1
    return count
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
                    position = position + 1
                    if position < length {
                        position = position + 1
                    }
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
            position = position + 1
            if position < length {
                position = position + 1
            }
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
        position = position + 1
        if position < length {
            position = position + 1
        }
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

func NumberValueLength(source: string, start: int, end: int): int {
    position := start
    valueLength := 0
    while position < end {
        if source[position] != '_' {
            valueLength = valueLength + 1
        }
        position = position + 1
    }

    return valueLength
}

func RawStringValueLength(source: string, start: int, end: int): int {
    contentStart := start + 3
    valueLength := end - contentStart
    if end >= start + 6 && source[end - 1] == '"' && source[end - 2] == '"' && source[end - 3] == '"' {
        valueLength = valueLength - 3
    }

    return valueLength
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

// Encodes token kind and source width as kind * 4 + width to avoid tuple/out parameters.
func OperatorInfo(source: string, position: int, length: int): int {
    ch := source[position]
    if position + 1 < length {
        next := source[position + 1]
        if ch == ':' {
            if next == '=' {
                return 486
            }
            if next == ':' {
                return 494
            }
        }

        if ch == '=' {
            if next == '=' {
                return 394
            }
            if next == '>' {
                return 482
            }
        }

        if ch == '!' && next == '=' {
            return 398
        }

        if ch == '<' {
            if next == '=' {
                return 406
            }
            if next == '<' {
                return 446
            }
        }

        if ch == '>' {
            if next == '=' {
                return 414
            }
            if next == '>' {
                return 450
            }
        }

        if ch == '&' && next == '&' {
            return 418
        }

        if ch == '|' && next == '|' {
            return 422
        }

        if ch == '+' {
            if next == '+' {
                return 454
            }
            if next == '=' {
                return 378
            }
        }

        if ch == '-' {
            if next == '-' {
                return 458
            }
            if next == '=' {
                return 382
            }
        }

        if ch == '*' && next == '=' {
            return 386
        }

        if ch == '/' && next == '=' {
            return 390
        }

        if ch == '?' {
            if next == '?' {
                if position + 2 < length && source[position + 2] == '=' {
                    return 471
                }

                return 466
            }

            if next == '.' {
                return 474
            }

            if next == '[' {
                return 478
            }
        }

        if ch == '.' && next == '.' {
            if position + 2 < length && source[position + 2] == '.' {
                return 507
            }

            return 502
        }
    }

    if ch == '+' {
        return 353
    }

    if ch == '-' {
        return 357
    }

    if ch == '*' {
        return 361
    }

    if ch == '/' {
        return 365
    }

    if ch == '%' {
        return 369
    }

    if ch == '=' {
        return 373
    }

    if ch == '<' {
        return 401
    }

    if ch == '>' {
        return 409
    }

    if ch == '!' {
        return 425
    }

    if ch == '&' {
        return 429
    }

    if ch == '|' {
        return 433
    }

    if ch == '^' {
        return 437
    }

    if ch == '~' {
        return 441
    }

    if ch == '?' {
        return 461
    }

    if ch == ':' {
        return 489
    }

    if ch == '.' {
        return 497
    }

    if ch == '(' {
        return 509
    }

    if ch == ')' {
        return 513
    }

    if ch == '{' {
        return 517
    }

    if ch == '}' {
        return 521
    }

    if ch == '[' {
        return 525
    }

    if ch == ']' {
        return 529
    }

    if ch == ';' {
        return 533
    }

    if ch == ',' {
        return 537
    }

    return 549
}

func KeywordKind(source: string, start: int, length: int): int {
    if length < 2 {
        return 0
    }

    ch0 := source[start]

    if length == 2 {
        if ch0 == 'i' {
            if source[start + 1] == 'f' {
                return 23
            }
            if source[start + 1] == 'n' {
                return 28
            }
            if source[start + 1] == 's' {
                return 47
            }
        }
        if ch0 == 'a' && source[start + 1] == 's' {
            return 48
        }
        if ch0 == 'o' && source[start + 1] == 'r' {
            return 56
        }
    }

    if length == 3 {
        if ch0 == 'f' && source[start + 1] == 'o' && source[start + 2] == 'r' {
            return 25
        }
        if ch0 == 'l' && source[start + 1] == 'e' && source[start + 2] == 't' {
            return 19
        }
        if ch0 == 'n' {
            if source[start + 1] == 'e' && source[start + 2] == 'w' {
                return 41
            }
            if source[start + 1] == 'o' && source[start + 2] == 't' {
                return 57
            }
        }
        if ch0 == 't' && source[start + 1] == 'r' && source[start + 2] == 'y' {
            return 38
        }
        if ch0 == 'a' && source[start + 1] == 'n' && source[start + 2] == 'd' {
            return 55
        }
        if ch0 == 'o' && source[start + 1] == 'u' && source[start + 2] == 't' {
            return 79
        }
        if ch0 == 'r' && source[start + 1] == 'e' && source[start + 2] == 'f' {
            return 78
        }
    }

    if length == 4 {
        if ch0 == 'f' {
            if source[start + 1] == 'u' && source[start + 2] == 'n' && source[start + 3] == 'c' {
                return 7
            }
            if source[start + 1] == 'i' && source[start + 2] == 'l' && source[start + 3] == 'e' {
                return 81
            }
        }
        if ch0 == 'd' && source[start + 1] == 'u' && source[start + 2] == 'c' && source[start + 3] == 'k' {
            return 11
        }
        if ch0 == 'e' {
            if source[start + 1] == 'n' && source[start + 2] == 'u' && source[start + 3] == 'm' {
                return 14
            }
            if source[start + 1] == 'l' && source[start + 2] == 's' && source[start + 3] == 'e' {
                return 24
            }
        }
        if ch0 == 't' {
            if source[start + 1] == 'r' && source[start + 2] == 'u' && source[start + 3] == 'e' {
                return 44
            }
            if source[start + 1] == 'h' && source[start + 2] == 'i' && source[start + 3] == 's' {
                return 42
            }
            if source[start + 1] == 'y' && source[start + 2] == 'p' && source[start + 3] == 'e' {
                return 72
            }
        }
        if ch0 == 'b' && source[start + 1] == 'a' && source[start + 2] == 's' && source[start + 3] == 'e' {
            return 43
        }
        if ch0 == 'n' && source[start + 1] == 'u' && source[start + 2] == 'l' && source[start + 3] == 'l' {
            return 46
        }
        if ch0 == 'c' && source[start + 1] == 'a' && source[start + 2] == 's' && source[start + 3] == 'e' {
            return 33
        }
        if ch0 == 'l' && source[start + 1] == 'o' && source[start + 2] == 'c' && source[start + 3] == 'k' {
            return 80
        }
        if ch0 == 'i' && source[start + 1] == 'n' && source[start + 2] == 'i' && source[start + 3] == 't' {
            return 77
        }
        if ch0 == 'w' {
            if source[start + 1] == 'h' && source[start + 2] == 'e' && source[start + 3] == 'n' {
                return 54
            }
            if source[start + 1] == 'i' && source[start + 2] == 't' && source[start + 3] == 'h' {
                return 71
            }
        }
        if ch0 == 'm' && source[start + 1] == 'u' && source[start + 2] == 's' && source[start + 3] == 't' {
            return 20
        }
    }

    if length == 5 {
        if ch0 == 'c' {
            if source[start + 1] == 'l' && source[start + 2] == 'a' && source[start + 3] == 's' && source[start + 4] == 's' {
                return 8
            }
            if source[start + 1] == 'o' && source[start + 2] == 'n' && source[start + 3] == 's' && source[start + 4] == 't' {
                return 21
            }
            if source[start + 1] == 'a' && source[start + 2] == 't' && source[start + 3] == 'c' && source[start + 4] == 'h' {
                return 39
            }
        }
        if ch0 == 'u' {
            if source[start + 1] == 'n' && source[start + 2] == 'i' && source[start + 3] == 'o' && source[start + 4] == 'n' {
                return 12
            }
            if source[start + 1] == 's' && source[start + 2] == 'i' && source[start + 3] == 'n' && source[start + 4] == 'g' {
                return 16
            }
        }
        if ch0 == 't' && source[start + 1] == 'h' && source[start + 2] == 'r' && source[start + 3] == 'o' && source[start + 4] == 'w' {
            return 37
        }
        if ch0 == 'w' {
            if source[start + 1] == 'h' && source[start + 2] == 'i' && source[start + 3] == 'l' && source[start + 4] == 'e' {
                return 27
            }
            if source[start + 1] == 'h' && source[start + 2] == 'e' && source[start + 3] == 'r' && source[start + 4] == 'e' {
                return 53
            }
        }
        if ch0 == 'y' && source[start + 1] == 'i' && source[start + 2] == 'e' && source[start + 3] == 'l' && source[start + 4] == 'd' {
            return 30
        }
        if ch0 == 'm' && source[start + 1] == 'a' && source[start + 2] == 't' && source[start + 3] == 'c' && source[start + 4] == 'h' {
            return 31
        }
        if ch0 == 'b' && source[start + 1] == 'r' && source[start + 2] == 'e' && source[start + 3] == 'a' && source[start + 4] == 'k' {
            return 35
        }
        if ch0 == 'f' && source[start + 1] == 'a' && source[start + 2] == 'l' && source[start + 3] == 's' && source[start + 4] == 'e' {
            return 45
        }
        if ch0 == 'a' {
            if source[start + 1] == 's' && source[start + 2] == 'y' && source[start + 3] == 'n' && source[start + 4] == 'c' {
                return 68
            }
            if source[start + 1] == 'w' && source[start + 2] == 'a' && source[start + 3] == 'i' && source[start + 4] == 't' {
                return 69
            }
        }
        if ch0 == 'p' && source[start + 1] == 'r' && source[start + 2] == 'i' && source[start + 3] == 'n' && source[start + 4] == 't' {
            return 52
        }
    }

    if length == 6 {
        if ch0 == 's' {
            if source[start + 1] == 't' && source[start + 2] == 'r' && source[start + 3] == 'u' && source[start + 4] == 'c' && source[start + 5] == 't' {
                return 9
            }
            if source[start + 1] == 'w' && source[start + 2] == 'i' && source[start + 3] == 't' && source[start + 4] == 'c' && source[start + 5] == 'h' {
                return 32
            }
            if source[start + 1] == 'i' && source[start + 2] == 'z' && source[start + 3] == 'e' && source[start + 4] == 'o' && source[start + 5] == 'f' {
                return 51
            }
            if source[start + 1] == 'e' && source[start + 2] == 'a' && source[start + 3] == 'l' && source[start + 4] == 'e' && source[start + 5] == 'd' {
                return 61
            }
            if source[start + 1] == 't' && source[start + 2] == 'a' && source[start + 3] == 't' && source[start + 4] == 'i' && source[start + 5] == 'c' {
                return 63
            }
        }
        if ch0 == 'r' {
            if source[start + 1] == 'e' && source[start + 2] == 'c' && source[start + 3] == 'o' && source[start + 4] == 'r' && source[start + 5] == 'd' {
                return 13
            }
            if source[start + 1] == 'e' && source[start + 2] == 't' && source[start + 3] == 'u' && source[start + 4] == 'r' && source[start + 5] == 'n' {
                return 29
            }
        }
        if ch0 == 'i' && source[start + 1] == 'm' && source[start + 2] == 'p' && source[start + 3] == 'o' && source[start + 4] == 'r' && source[start + 5] == 't' {
            return 17
        }
        if ch0 == 't' && source[start + 1] == 'y' && source[start + 2] == 'p' && source[start + 3] == 'e' && source[start + 4] == 'o' && source[start + 5] == 'f' {
            return 49
        }
        if ch0 == 'n' && source[start + 1] == 'a' && source[start + 2] == 'm' && source[start + 3] == 'e' && source[start + 4] == 'o' && source[start + 5] == 'f' {
            return 50
        }
        if ch0 == 'p' {
            if source[start + 1] == 'u' && source[start + 2] == 'b' && source[start + 3] == 'l' && source[start + 4] == 'i' && source[start + 5] == 'c' {
                return 64
            }
            if source[start + 1] == 'a' && source[start + 2] == 'r' && source[start + 3] == 'a' && source[start + 4] == 'm' && source[start + 5] == 's' {
                return 82
            }
        }
        if ch0 == 'a' && source[start + 1] == 's' && source[start + 2] == 's' && source[start + 3] == 'e' && source[start + 4] == 'r' && source[start + 5] == 't' {
            return 74
        }
    }

    if length == 7 {
        if ch0 == 'p' {
            if source[start + 1] == 'a' && source[start + 2] == 'c' && source[start + 3] == 'k' && source[start + 4] == 'a' && source[start + 5] == 'g' && source[start + 6] == 'e' {
                return 18
            }
            if source[start + 1] == 'a' && source[start + 2] == 'r' && source[start + 3] == 't' && source[start + 4] == 'i' && source[start + 5] == 'a' && source[start + 6] == 'l' {
                return 62
            }
            if source[start + 1] == 'r' && source[start + 2] == 'i' && source[start + 3] == 'v' && source[start + 4] == 'a' && source[start + 5] == 't' && source[start + 6] == 'e' {
                return 65
            }
        }
        if ch0 == 'f' {
            if source[start + 1] == 'o' && source[start + 2] == 'r' && source[start + 3] == 'e' && source[start + 4] == 'a' && source[start + 5] == 'c' && source[start + 6] == 'h' {
                return 26
            }
            if source[start + 1] == 'i' && source[start + 2] == 'n' && source[start + 3] == 'a' && source[start + 4] == 'l' && source[start + 5] == 'l' && source[start + 6] == 'y' {
                return 40
            }
        }
        if ch0 == 'd' && source[start + 1] == 'e' && source[start + 2] == 'f' && source[start + 3] == 'a' && source[start + 4] == 'u' && source[start + 5] == 'l' && source[start + 6] == 't' {
            return 34
        }
        if ch0 == 'v' && source[start + 1] == 'i' && source[start + 2] == 'r' && source[start + 3] == 't' && source[start + 4] == 'u' && source[start + 5] == 'a' && source[start + 6] == 'l' {
            return 58
        }
        if ch0 == 'c' && source[start + 1] == 'h' && source[start + 2] == 'e' && source[start + 3] == 'c' && source[start + 4] == 'k' && source[start + 5] == 'e' && source[start + 6] == 'd' {
            return 83
        }
        if ch0 == 'n' && source[start + 1] == 'e' && source[start + 2] == 'w' && source[start + 3] == 't' && source[start + 4] == 'y' && source[start + 5] == 'p' && source[start + 6] == 'e' {
            return 87
        }
    }

    if length == 8 {
        if ch0 == 'r' {
            if source[start + 1] == 'e' && source[start + 2] == 'a' && source[start + 3] == 'd' && source[start + 4] == 'o' && source[start + 5] == 'n' && source[start + 6] == 'l' && source[start + 7] == 'y' {
                return 22
            }
            if source[start + 1] == 'e' && source[start + 2] == 'q' && source[start + 3] == 'u' && source[start + 4] == 'i' && source[start + 5] == 'r' && source[start + 6] == 'e' && source[start + 7] == 'd' {
                return 76
            }
        }
        if ch0 == 'c' && source[start + 1] == 'o' && source[start + 2] == 'n' && source[start + 3] == 't' && source[start + 4] == 'i' && source[start + 5] == 'n' && source[start + 6] == 'u' && source[start + 7] == 'e' {
            return 36
        }
        if ch0 == 'a' && source[start + 1] == 'b' && source[start + 2] == 's' && source[start + 3] == 't' && source[start + 4] == 'r' && source[start + 5] == 'a' && source[start + 6] == 'c' && source[start + 7] == 't' {
            return 60
        }
        if ch0 == 'i' {
            if source[start + 1] == 'n' && source[start + 2] == 't' && source[start + 3] == 'e' && source[start + 4] == 'r' && source[start + 5] == 'n' && source[start + 6] == 'a' && source[start + 7] == 'l' {
                return 66
            }
            if source[start + 1] == 'm' && source[start + 2] == 'p' && source[start + 3] == 'l' && source[start + 4] == 'i' && source[start + 5] == 'c' && source[start + 6] == 'i' && source[start + 7] == 't' {
                return 85
            }
        }
        if ch0 == 'e' && source[start + 1] == 'x' && source[start + 2] == 'p' && source[start + 3] == 'l' && source[start + 4] == 'i' && source[start + 5] == 'c' && source[start + 6] == 'i' && source[start + 7] == 't' {
            return 86
        }
        if ch0 == 'o' {
            if source[start + 1] == 'p' && source[start + 2] == 'e' && source[start + 3] == 'r' && source[start + 4] == 'a' && source[start + 5] == 't' && source[start + 6] == 'o' && source[start + 7] == 'r' {
                return 75
            }
            if source[start + 1] == 'v' && source[start + 2] == 'e' && source[start + 3] == 'r' && source[start + 4] == 'r' && source[start + 5] == 'i' && source[start + 6] == 'd' && source[start + 7] == 'e' {
                return 59
            }
        }
    }

    if length == 9 {
        if ch0 == 'i' {
            if source[start + 1] == 'n' && source[start + 2] == 't' && source[start + 3] == 'e' && source[start + 4] == 'r' && source[start + 5] == 'f' && source[start + 6] == 'a' && source[start + 7] == 'c' && source[start + 8] == 'e' {
                return 10
            }
            if source[start + 1] == 'm' && source[start + 2] == 'm' && source[start + 3] == 'u' && source[start + 4] == 't' && source[start + 5] == 'a' && source[start + 6] == 'b' && source[start + 7] == 'l' && source[start + 8] == 'e' {
                return 70
            }
        }
        if ch0 == 'n' && source[start + 1] == 'a' && source[start + 2] == 'm' && source[start + 3] == 'e' && source[start + 4] == 's' && source[start + 5] == 'p' && source[start + 6] == 'a' && source[start + 7] == 'c' && source[start + 8] == 'e' {
            return 15
        }
        if ch0 == 'p' && source[start + 1] == 'r' && source[start + 2] == 'o' && source[start + 3] == 't' && source[start + 4] == 'e' && source[start + 5] == 'c' && source[start + 6] == 't' && source[start + 7] == 'e' && source[start + 8] == 'd' {
            return 67
        }
        if ch0 == 'u' && source[start + 1] == 'n' && source[start + 2] == 'c' && source[start + 3] == 'h' && source[start + 4] == 'e' && source[start + 5] == 'c' && source[start + 6] == 'k' && source[start + 7] == 'e' && source[start + 8] == 'd' {
            return 84
        }
    }

    return 0
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
