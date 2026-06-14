// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/LexerTokenKindScanner.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

struct LexerCommentTable {
    Lines: int[]
    Columns: int[]
    Starts: int[]
    Lengths: int[]
    IsMultiLine: int[]
}

func TokenizeKinds(source: string): int[] {
    tokens := new LexerTokenKindTable { Kinds: new int[](source.Length + 1) }
    count := TokenizeKindsCore(source, ref tokens)
    return CopyKindsCore(ref tokens, count)
}

func TokenizeKindsInto(source: string, buffer: int[]): int {
    tokens := new LexerTokenKindTable { Kinds: buffer }
    return TokenizeKindsCore(source, ref tokens)
}

func TokenizeKindsCore(source: string, tokens: &LexerTokenKindTable): int {
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
            tokens.Kinds[count] = 136
            count = count + 1
            position = position + 1
            continue
        }

        if ch == '\r' {
            tokens.Kinds[count] = 136
            count = count + 1
            position = position + 1
            if position < length && source[position] == '\n' {
                position = position + 1
            }
            continue
        }

        if ch == '#' {
            tokens.Kinds[count] = 138
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
                tokens.Kinds[count] = 6
                count = count + 1
                position = ScanRawString(source, position + 4, length)
            } else {
                tokens.Kinds[count] = 4
                count = count + 1
                position = ScanString(source, position + 1, length, true)
            }
            continue
        }

        if ch == '"' {
            if position + 2 < length && source[position + 1] == '"' && source[position + 2] == '"' {
                tokens.Kinds[count] = 5
                count = count + 1
                position = ScanRawString(source, position + 3, length)
            } else {
                tokens.Kinds[count] = 4
                count = count + 1
                position = ScanString(source, position, length, false)
            }
            continue
        }

        if ch == '\'' && IsLifetimeStartAt(source, position, length) {
            tokens.Kinds[count] = 142
            count = count + 1
            position = ScanLifetime(source, position, length)
            continue
        }

        if ch == '\'' {
            tokens.Kinds[count] = 3
            count = count + 1
            position = ScanCharLiteral(source, position, length)
            continue
        }

        if IsDigit(ch) {
            numberInfo := ScanNumberInfo(source, position, length)
            numberKind := numberInfo & 3
            if numberKind == 3 {
                numberKind = 137
            }

            tokens.Kinds[count] = numberKind
            count = count + 1
            position = numberInfo >> 2
            continue
        }

        if IsIdentifierStart(ch) {
            start := position
            position = position + 1
            while position < length && IsIdentifierPart(source[position]) {
                position = position + 1
            }

            tokens.Kinds[count] = KeywordKind(source, start, position - start)
            count = count + 1
            continue
        }

        operatorInfo := OperatorInfo(source, position, length)
        operatorKind := operatorInfo >> 2
        tokens.Kinds[count] = operatorKind
        count = count + 1
        position = position + (operatorInfo & 3)
    }

    tokens.Kinds[count] = 135
    count = count + 1
    return count
}

func TokenizeMetadataInto(source: string, kinds: int[], starts: int[], valueLengths: int[], lines: int[], columns: int[]): int {
    metadata := new LexerTokenMetadataTable { Kinds: kinds, Starts: starts, ValueLengths: valueLengths, Lines: lines, Columns: columns }
    return TokenizeMetadataCore(source, ref metadata)
}

func CommentsInto(source: string, lines: int[], columns: int[], starts: int[], lengths: int[], isMultiLine: int[]): int {
    comments := new LexerCommentTable { Lines: lines, Columns: columns, Starts: starts, Lengths: lengths, IsMultiLine: isMultiLine }
    return CommentsCore(source, ref comments)
}

// Collect comment trivia exactly as the C# production lexer does (Lexer.Tokenize fills Lexer.Comments
// from the Comment/MultiLineComment/XmlDocComment tokens it excludes from the stream). For each comment
// this records line, column, start offset, length, and isMultiLine (1 = block /* */, 0 = line // or
// doc ///). The comment text C# stores is the full span including delimiters for line/doc comments and
// "/*" + inner + "*/" for block comments -- both equal (end - start), so `length` here = end - start.
// The loop mirrors TokenizeMetadataCore's token dispatch (consuming strings/raw strings/char/lifetime/
// number/identifier/operator runs as units) so a `//` or `/*` INSIDE a literal is never misread as a
// comment, and so line/column tracking through multi-line raw strings stays exact.
func CommentsCore(source: string, comments: &LexerCommentTable): int {
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

        if ch == '\n' {
            position = position + 1
            line = line + 1
            column = 1
            continue
        }

        if ch == '\r' {
            position = position + 1
            if position < length && source[position] == '\n' {
                position = position + 1
            }

            line = line + 1
            column = 1
            continue
        }

        start := position
        tokenLine := line
        tokenColumn := column

        if ch == '#' {
            position = position + 1
            column = column + 1
            while position < length && source[position] != '\n' && source[position] != '\r' {
                position = position + 1
                column = column + 1
            }

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

                comments.Lines[count] = tokenLine
                comments.Columns[count] = tokenColumn
                comments.Starts[count] = start
                comments.Lengths[count] = position - start
                comments.IsMultiLine[count] = 0
                count = count + 1
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

                comments.Lines[count] = tokenLine
                comments.Columns[count] = tokenColumn
                comments.Starts[count] = start
                comments.Lengths[count] = position - start
                comments.IsMultiLine[count] = 1
                count = count + 1
                continue
            }
        }

        if ch == '$' && position + 1 < length && source[position + 1] == '"' {
            if position + 3 < length && source[position + 2] == '"' && source[position + 3] == '"' {
                nextPosition := ScanRawString(source, position + 4, length)
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
                column = column + (nextPosition - start)
                position = nextPosition
            }

            continue
        }

        if ch == '"' {
            if position + 2 < length && source[position + 1] == '"' && source[position + 2] == '"' {
                nextPosition := ScanRawString(source, position + 3, length)
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
                column = column + (nextPosition - start)
                position = nextPosition
            }

            continue
        }

        if ch == '\'' && IsLifetimeStartAt(source, position, length) {
            nextPosition := ScanLifetime(source, position, length)
            column = column + (nextPosition - start)
            position = nextPosition
            continue
        }

        if ch == '\'' {
            nextPosition := ScanCharLiteral(source, position, length)
            column = column + (nextPosition - start)
            position = nextPosition
            continue
        }

        if IsDigit(ch) {
            nextPosition := ScanNumberInfo(source, position, length) >> 2
            column = column + (nextPosition - start)
            position = nextPosition
            continue
        }

        if IsIdentifierStart(ch) {
            position = position + 1
            while position < length && IsIdentifierPart(source[position]) {
                position = position + 1
            }

            column = column + (position - start)
            continue
        }

        operatorInfo := OperatorInfo(source, position, length)
        operatorWidth := operatorInfo & 3
        position = position + operatorWidth
        column = column + operatorWidth
    }

    return count
}

func CopyKindsCore(source: &LexerTokenKindTable, count: int): int[] {
    result := new int[](count)
    target := new LexerTokenKindTable { Kinds: result }
    i := 0
    while i < count {
        target.Kinds[i] = source.Kinds[i]
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

        if ch == '\'' && IsLifetimeStartAt(source, position, length) {
            count = count + 1
            position = ScanLifetime(source, position, length)
            continue
        }

        if ch == '\'' {
            count = count + 1
            position = ScanCharLiteral(source, position, length)
            continue
        }

        if IsDigit(ch) {
            count = count + 1
            position = ScanNumberInfo(source, position, length) >> 2
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

func ParserTokenCompactionChecksumInto(tokenKinds: int[], resultIndices: int[]): int {
    length := tokenKinds.Length
    if resultIndices.Length < length {
        compactedCount := ParserTokenCompactionIndicesInto(tokenKinds, resultIndices)
        checksum := compactedCount

        i := 0
        while i < compactedCount {
            index := resultIndices[i]
            checksum = checksum + (i + 1) * 97 + tokenKinds[index] * 17
            i = i + 1
        }

        return checksum
    }

    compactedCount := 0
    checksum := 0
    i := 0
    unrolledLimit := length - 8
    while i <= unrolledLimit {
        if tokenKinds[i] != 136 {
            resultIndices[compactedCount] = i
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[i] * 17
            compactedCount = compactedCount + 1
        }

        next := i + 1
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        next = i + 2
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        next = i + 3
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        next = i + 4
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        next = i + 5
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        next = i + 6
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        next = i + 7
        if tokenKinds[next] != 136 {
            resultIndices[compactedCount] = next
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[next] * 17
            compactedCount = compactedCount + 1
        }

        i = i + 8
    }

    while i < length {
        if tokenKinds[i] != 136 {
            resultIndices[compactedCount] = i
            checksum = checksum + (compactedCount + 1) * 97 + tokenKinds[i] * 17
            compactedCount = compactedCount + 1
        }

        i = i + 1
    }

    return checksum + compactedCount
}
