struct LexerTokenKindTable {
    Kinds: int[]
}

struct LexerTokenIndexTable {
    Indices: int[]
}

struct LexerTokenMetadataTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Lines: int[]
    Columns: int[]
}

struct LexerCompactTokenMetadataTable {
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
}

struct LexerIndentStackTable {
    Indents: int[]
}

func ParserTokenCompactionIndicesCountedInto(tokenKinds: int[], tokenCount: int, resultIndices: int[]): int {
    if tokenCount < 0 {
        return -1
    }

    if tokenCount > tokenKinds.Length {
        return -1
    }

    tokens := new LexerTokenKindTable { Kinds: tokenKinds }
    result := new LexerTokenIndexTable { Indices: resultIndices }
    return ParserTokenCompactionIndicesCore(ref tokens, ref result, tokenCount)
}

func ParserTokenCompactionIndicesCore(tokens: &LexerTokenKindTable, result: &LexerTokenIndexTable, length: int): int {
    count := 0
    i := 0

    if result.Indices.Length >= length {
        unrolledLimit := length - 8
        while i <= unrolledLimit {
            if tokens.Kinds[i] != 136 {
                result.Indices[count] = i
                count = count + 1
            }

            next := i + 1
            if tokens.Kinds[next] != 136 {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 2
            if tokens.Kinds[next] != 136 {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 3
            if tokens.Kinds[next] != 136 {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 4
            if tokens.Kinds[next] != 136 {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 5
            if tokens.Kinds[next] != 136 {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 6
            if tokens.Kinds[next] != 136 {
                result.Indices[count] = next
                count = count + 1
            }

            next = i + 7
            if tokens.Kinds[next] != 136 {
                result.Indices[count] = next
                count = count + 1
            }

            i = i + 8
        }

        while i < length {
            if tokens.Kinds[i] != 136 {
                result.Indices[count] = i
                count = count + 1
            }

            i = i + 1
        }

        return count
    }

    while i < length {
        if tokens.Kinds[i] != 136 {
            if count >= result.Indices.Length {
                return -1
            }

            result.Indices[count] = i
            count = count + 1
        }

        i = i + 1
    }

    return count
}

func ParserTokenCompactedMetadataCore(tokens: &LexerCompactTokenMetadataTable, length: int, result: &LexerCompactTokenMetadataTable): int {
    count := 0
    i := 0

    while i < length {
        if tokens.Kinds[i] != 136 {
            result.Kinds[count] = tokens.Kinds[i]
            result.Starts[count] = tokens.Starts[i]
            result.ValueLengths[count] = tokens.ValueLengths[i]
            count = count + 1
        }

        i = i + 1
    }

    return count
}

func TokenizeMetadataCore(source: string, metadata: &LexerTokenMetadataTable): int {
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
            metadata.Kinds[count] = 136
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = 1
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
            count = count + 1
            position = position + 1
            line = line + 1
            column = 1
            continue
        }

        if ch == '\r' {
            metadata.Kinds[count] = 136
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = 1
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
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

            metadata.Kinds[count] = 138
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = position - start
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
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
                metadata.Kinds[count] = 6
                metadata.Starts[count] = start
                metadata.ValueLengths[count] = nextPosition - start
                metadata.Lines[count] = tokenLine
                metadata.Columns[count] = tokenColumn
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
                metadata.Kinds[count] = 4
                metadata.Starts[count] = start
                metadata.ValueLengths[count] = nextPosition - start
                metadata.Lines[count] = tokenLine
                metadata.Columns[count] = tokenColumn
                count = count + 1
                column = column + (nextPosition - start)
                position = nextPosition
            }
            continue
        }

        if ch == '"' {
            if position + 2 < length && source[position + 1] == '"' && source[position + 2] == '"' {
                nextPosition := ScanRawString(source, position + 3, length)
                metadata.Kinds[count] = 5
                metadata.Starts[count] = start
                metadata.ValueLengths[count] = nextPosition - start
                metadata.Lines[count] = tokenLine
                metadata.Columns[count] = tokenColumn
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
                metadata.Kinds[count] = 4
                metadata.Starts[count] = start
                metadata.ValueLengths[count] = nextPosition - start
                metadata.Lines[count] = tokenLine
                metadata.Columns[count] = tokenColumn
                count = count + 1
                column = column + (nextPosition - start)
                position = nextPosition
            }
            continue
        }

        if ch == '\'' && IsLifetimeStartAt(source, position, length) {
            nextPosition := ScanLifetime(source, position, length)
            metadata.Kinds[count] = 142
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = nextPosition - start
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
            count = count + 1
            column = column + (nextPosition - start)
            position = nextPosition
            continue
        }

        if ch == '\'' {
            nextPosition := ScanCharLiteral(source, position, length)
            metadata.Kinds[count] = 3
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = nextPosition - start
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
            count = count + 1
            column = column + (nextPosition - start)
            position = nextPosition
            continue
        }

        if IsDigit(ch) {
            numberInfo := ScanNumberInfo(source, position, length)
            nextPosition := numberInfo >> 2
            numberKind := numberInfo & 3
            if numberKind == 3 {
                numberKind = 137
            }

            metadata.Kinds[count] = numberKind
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = NumberValueLength(source, start, nextPosition)
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
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

            metadata.Kinds[count] = KeywordKind(source, start, position - start)
            metadata.Starts[count] = start
            metadata.ValueLengths[count] = position - start
            metadata.Lines[count] = tokenLine
            metadata.Columns[count] = tokenColumn
            count = count + 1
            column = column + (position - start)
            continue
        }

        operatorInfo := OperatorInfo(source, position, length)
        operatorKind := operatorInfo >> 2
        operatorWidth := operatorInfo & 3
        metadata.Kinds[count] = operatorKind
        metadata.Starts[count] = start
        metadata.ValueLengths[count] = operatorWidth
        metadata.Lines[count] = tokenLine
        metadata.Columns[count] = tokenColumn
        count = count + 1
        position = position + operatorWidth
        column = column + operatorWidth
    }

    metadata.Kinds[count] = 135
    metadata.Starts[count] = position
    metadata.ValueLengths[count] = 0
    metadata.Lines[count] = line
    metadata.Columns[count] = column
    count = count + 1
    return count
}

// Insert the virtual indentation braces that the production lexer's InsertIndentationBraces
// post-pass produces, but write only the parser-consumed token metadata columns. The raw metadata
// stream still carries line/column because indentation decisions require it; the product adapter no
// longer pays for line/column output columns that the parser route never reads.
func InsertIndentationParserMetadataCore(
    raw: &LexerTokenMetadataTable,
    rawCount: int,
    output: &LexerCompactTokenMetadataTable,
    indentStack: &LexerIndentStackTable): int {
    outCount := 0
    stackTop := 0
    indentStack.Indents[0] = 0
    atLineStart := true
    explicitBraceDepth := 0
    parenBracketDepth := 0
    hasBaseIndent := false
    baseIndent := 0

    i := 0
    while i < rawCount {
        kind := raw.Kinds[i]
        tokenStart := raw.Starts[i]
        tokenValueLength := raw.ValueLengths[i]
        tokenColumn := raw.Columns[i]
        lineStart := tokenStart - (tokenColumn - 1)

        if kind == 136 {
            output.Kinds[outCount] = kind
            output.Starts[outCount] = tokenStart
            output.ValueLengths[outCount] = tokenValueLength
            outCount = outCount + 1
            atLineStart = true
            i = i + 1
            continue
        }

        if kind == 135 {
            while stackTop > 0 {
                stackTop = stackTop - 1
                output.Kinds[outCount] = 130
                output.Starts[outCount] = lineStart
                output.ValueLengths[outCount] = 1
                outCount = outCount + 1
            }

            output.Kinds[outCount] = kind
            output.Starts[outCount] = tokenStart
            output.ValueLengths[outCount] = tokenValueLength
            outCount = outCount + 1
            return outCount
        }

        if atLineStart {
            rawIndent := tokenColumn - 1
            if rawIndent < 0 {
                rawIndent = 0
            }

            if !hasBaseIndent && stackTop == 0 {
                baseIndent = rawIndent
                hasBaseIndent = true
            }

            currentIndent := rawIndent - baseIndent
            if currentIndent < 0 {
                currentIndent = 0
            }

            if parenBracketDepth == 0 && explicitBraceDepth == 0 {
                previousIndent := indentStack.Indents[stackTop]
                if currentIndent > previousIndent {
                    stackTop = stackTop + 1
                    indentStack.Indents[stackTop] = currentIndent
                    output.Kinds[outCount] = 129
                    output.Starts[outCount] = lineStart
                    output.ValueLengths[outCount] = 1
                    outCount = outCount + 1
                } else if currentIndent < previousIndent {
                    while stackTop > 0 && currentIndent < indentStack.Indents[stackTop] {
                        stackTop = stackTop - 1
                        output.Kinds[outCount] = 130
                        output.Starts[outCount] = lineStart
                        output.ValueLengths[outCount] = 1
                        outCount = outCount + 1
                    }
                }
            }

            atLineStart = false
        }

        if kind == 129 {
            explicitBraceDepth = explicitBraceDepth + 1
        } else if kind == 130 {
            explicitBraceDepth = explicitBraceDepth - 1
            if explicitBraceDepth < 0 {
                explicitBraceDepth = 0
            }
        } else if kind == 127 || kind == 131 {
            parenBracketDepth = parenBracketDepth + 1
        } else if kind == 128 || kind == 132 {
            parenBracketDepth = parenBracketDepth - 1
            if parenBracketDepth < 0 {
                parenBracketDepth = 0
            }
        }

        output.Kinds[outCount] = kind
        output.Starts[outCount] = tokenStart
        output.ValueLengths[outCount] = tokenValueLength
        outCount = outCount + 1
        i = i + 1
    }

    return outCount
}

// Product columnar lexer entry: tokenize, insert indentation braces, and compact parser metadata before
// returning to the host. resultCounts[0] is the raw indentation-expanded count; resultCounts[1] is the
// compact parser-token count. This keeps the transition adapter from binding standalone lexer probe ABIs.
func TokenizeColumnarSourceInto(source: string, rawKinds: int[], rawStarts: int[], rawValueLengths: int[], compactKinds: int[], compactStarts: int[], compactValueLengths: int[], resultCounts: int[]): int {
    if resultCounts.Length < 2 {
        return -1
    }

    rawMetadata := new LexerTokenMetadataTable {
        Kinds: new int[](source.Length + 1),
        Starts: new int[](source.Length + 1),
        ValueLengths: new int[](source.Length + 1),
        Lines: new int[](source.Length + 1),
        Columns: new int[](source.Length + 1)
    }
    rawTarget := new LexerCompactTokenMetadataTable { Kinds: rawKinds, Starts: rawStarts, ValueLengths: rawValueLengths }
    tokenCount := TokenizeMetadataCore(source, ref rawMetadata)
    indentStack := new LexerIndentStackTable { Indents: new int[](source.Length + 2) }
    rawCount := InsertIndentationParserMetadataCore(ref rawMetadata, tokenCount, ref rawTarget, ref indentStack)
    if rawCount < 0 {
        return -1
    }

    raw := new LexerCompactTokenMetadataTable { Kinds: rawKinds, Starts: rawStarts, ValueLengths: rawValueLengths }
    compact := new LexerCompactTokenMetadataTable { Kinds: compactKinds, Starts: compactStarts, ValueLengths: compactValueLengths }
    compactCount := ParserTokenCompactedMetadataCore(ref raw, rawCount, ref compact)
    if compactCount < 0 {
        return -1
    }

    resultCounts[0] = rawCount
    resultCounts[1] = compactCount
    return compactCount
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
        // Do not consume the escaped char across a line
        // break, so e.g. `'\<CR>` leaves the CR to become a separate Newline token.
        if position < length && source[position] != '\n' && source[position] != '\r' {
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

// Lifetime token support, mirroring the production lexer (Lexer.cs:325-328, 903-960). At an
// apostrophe, the lexer emits a single Lifetime token (ordinal 142) -- instead of a char literal --
// when the apostrophe begins an identifier (next char letter/'_', and the char after that is not a
// closing quote, distinguishing `'a` from the char literal `'a'`) AND it appears in a lifetime
// CONTEXT: the nearest preceding non-whitespace character is `<` or `,`, or the identifier word
// immediately before it is `scoped` or `returns`. These checks intentionally use the scanner's
// existing ASCII character classification (consistent with IsDigit/IsIdentifierStart elsewhere);
// the scanner-wide ASCII-vs-Unicode classification gap is tracked separately in self-host-progress.md.
// Whitespace for the lifetime-context lookback.
func IsLifetimeLookbackWhitespace(ch: char): bool {
    return char.IsWhiteSpace(ch)
}

func MatchesScopedOrReturns(source: string, start: int, length: int): bool {
    if length == 6 {
        return source[start] == 's' && source[start + 1] == 'c' && source[start + 2] == 'o' && source[start + 3] == 'p' && source[start + 4] == 'e' && source[start + 5] == 'd'
    }

    if length == 7 {
        return source[start] == 'r' && source[start + 1] == 'e' && source[start + 2] == 't' && source[start + 3] == 'u' && source[start + 4] == 'r' && source[start + 5] == 'n' && source[start + 6] == 's'
    }

    return false
}

func IsLifetimeContextAt(source: string, position: int): bool {
    index := position - 1
    while index >= 0 && IsLifetimeLookbackWhitespace(source[index]) {
        index = index - 1
    }

    if index < 0 {
        return false
    }

    previous := source[index]
    if previous == '<' || previous == ',' {
        return true
    }

    if !IsIdentifierPart(previous) {
        return false
    }

    end := index + 1
    while index >= 0 && IsIdentifierPart(source[index]) {
        index = index - 1
    }

    wordStart := index + 1
    return MatchesScopedOrReturns(source, wordStart, end - wordStart)
}

func IsLifetimeStartAt(source: string, position: int, length: int): bool {
    if position + 1 >= length {
        return false
    }

    if !IsIdentifierStart(source[position + 1]) {
        return false
    }

    if position + 2 < length && source[position + 2] == '\'' {
        return false
    }

    return IsLifetimeContextAt(source, position)
}

func ScanLifetime(source: string, position: int, length: int): int {
    position = position + 1
    while position < length && IsIdentifierPart(source[position]) {
        position = position + 1
    }

    return position
}

// Returns ((exclusive end offset) << 2) | kind, where kind is 1 = IntLiteral, 2 = FloatLiteral, and
// 3 = Unknown (the malformed-number error token). The 1/2 values double as the
// TokenType ordinals; callers map the sentinel 3 to Unknown (137). Each error branch returns the same
// span consumed by the production lexer (so NumberValueLength, which counts non-'_' chars, reproduces token text):
//   - 0x / 0b with no valid digit immediately after the prefix (a leading '_' counts as "no digit",
//     matching the production lexer) -> Unknown ending right after the prefix;
//   - a second decimal point (Lexer.cs:650-659) -> Unknown after consuming the remaining digits/dots;
//   - an exponent e/E[+/-] with no digit after it (Lexer.cs:681-684) -> Unknown ending after the sign.
func ScanNumberInfo(source: string, position: int, length: int): int {
    if source[position] == '0' && position + 1 < length && (source[position + 1] == 'x' || source[position + 1] == 'X') {
        position = position + 2
        if position >= length || !IsHexDigit(source[position]) {
            return (position << 2) | 3
        }

        while position < length && (IsHexDigit(source[position]) || source[position] == '_') {
            position = position + 1
        }

        return (ConsumeIntegerSuffix(source, position, length) << 2) | 1
    }

    if source[position] == '0' && position + 1 < length && (source[position + 1] == 'b' || source[position + 1] == 'B') {
        position = position + 2
        if position >= length || (source[position] != '0' && source[position] != '1') {
            return (position << 2) | 3
        }

        while position < length && (source[position] == '0' || source[position] == '1' || source[position] == '_') {
            position = position + 1
        }

        return (ConsumeIntegerSuffix(source, position, length) << 2) | 1
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

            if isFloat {
                while position < length && (IsDigit(source[position]) || source[position] == '.') {
                    position = position + 1
                }

                return (position << 2) | 3
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

        if position >= length || !IsDigit(source[position]) {
            return (position << 2) | 3
        }

        while position < length && (IsDigit(source[position]) || source[position] == '_') {
            position = position + 1
        }
    }

    if isFloat {
        return (ConsumeFloatSuffix(source, position, length) << 2) | 2
    }

    if position < length && (source[position] == 'm' || source[position] == 'M') {
        return ((position + 1) << 2) | 2
    }

    return (ConsumeIntegerSuffix(source, position, length) << 2) | 1
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
            if source[start + 1] == 'l' && source[start + 2] == 'l' && source[start + 3] == 'o' && source[start + 4] == 'c' {
                return 143
            }
            if source[start + 1] == 'l' && source[start + 2] == 'l' && source[start + 3] == 'o' && source[start + 4] == 'w' {
                return 144
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
            if source[start + 1] == 'c' && source[start + 2] == 'o' && source[start + 3] == 'p' && source[start + 4] == 'e' && source[start + 5] == 'd' {
                return 147
            }
        }
        if ch0 == 'u' && source[start + 1] == 'n' && source[start + 2] == 's' && source[start + 3] == 'a' && source[start + 4] == 'f' && source[start + 5] == 'e' {
            return 146
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

    if length == 10 {
        if ch0 == 's' && source[start + 1] == 't' && source[start + 2] == 'a' && source[start + 3] == 'c' && source[start + 4] == 'k' && source[start + 5] == 'a' && source[start + 6] == 'l' && source[start + 7] == 'l' && source[start + 8] == 'o' && source[start + 9] == 'c' {
            return 145
        }
    }

    return 0
}

func IsWhitespaceExceptNewline(ch: char): bool {
    return char.IsWhiteSpace(ch) && ch != '\n' && ch != '\r'
}

// Character classification mirrors the production lexer's use of the BCL Unicode predicates
// (Lexer.cs: char.IsLetter at 342/905, char.IsLetterOrDigit at 567/922/926/942, char.IsDigit at
// 336/631/647/653/681/686/757, char.IsWhiteSpace at 912/1084).
func IsIdentifierStart(ch: char): bool {
    return ch == '_' || char.IsLetter(ch)
}

func IsIdentifierPart(ch: char): bool {
    return ch == '_' || char.IsLetterOrDigit(ch)
}

func IsDigit(ch: char): bool {
    return char.IsDigit(ch)
}

// Hex digits are ASCII-only letters plus any Unicode decimal digit, matching production IsHexDigit
// (Lexer.cs:757 = char.IsDigit(c) || a-f || A-F).
func IsHexDigit(ch: char): bool {
    return IsDigit(ch) || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
}
