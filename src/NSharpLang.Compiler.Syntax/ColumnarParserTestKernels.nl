import System.Text
import NSharpLang.Compiler


// PROPERTY ACCESSORS AND THE TEST DSL: accessor info, the `test` header and table shapes, and the
// case entries they resolve to.
//
// Formerly part of `CompilerServices/ColumnarParserKernels.nl`, a 17,120-line file whose first
// 2,061 lines were fifteen files mechanically concatenated behind `// ---- X.nl ----` markers --
// a bootstrap artifact of the Dogfood assembly, not a design. Split back by concern; every line
// below is a verbatim move.
func ParsePropertyAccessorInfoCore(source: string, tokens: ParserDeclarationTokenTable, count: int, propIndex: int, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 6 {
        return -1
    }

    if count < 0 {
        return -1
    }

    if count > tokens.Kinds.Length {
        return -1
    }

    if count > tokens.Starts.Length {
        return -1
    }

    if count > tokens.ValueLengths.Length {
        return -1
    }

    if propIndex < 0 || propIndex + 4 >= count {
        return -1
    }

    if tokens.Kinds[propIndex] != 0 {
        return -1
    }

    // A VALUE MEMBER'S NAME MAY BE QUALIFIED (an explicit interface implementation), so the `:` and the
    // type behind it are found past the WHOLE name and the recorded name span is the whole name.
    nameEnd := ParseDeclarationMemberNameEnd(tokens, count, propIndex)
    if nameEnd >= count || tokens.Kinds[nameEnd] != 122 {
        return -1
    }

    nameLength := ParseDeclarationMemberNameSpanLength(tokens, propIndex, nameEnd)

    typeResult := new ParserDeclarationResultTable(new int[](2))
    typeEnd := ParseDeclarationTypeSpanCore(tokens, count, nameEnd + 1, typeResult)
    if typeEnd < 0 || typeEnd >= count {
        return -1
    }

    if tokens.Kinds[typeEnd] == 120 {
        result.Values[0] = tokens.Starts[propIndex]
        result.Values[1] = nameLength
        result.Values[2] = typeResult.Values[0]
        result.Values[3] = typeResult.Values[1]
        result.Values[4] = typeEnd
        result.Values[5] = -1
        return 0
    }

    if typeEnd + 2 >= count || tokens.Kinds[typeEnd] != 129 {
        return -1
    }

    if tokens.Kinds[typeEnd + 1] != 0 || !ParserDeclarationTokenTextEquals(source, tokens.Starts[typeEnd + 1], tokens.ValueLengths[typeEnd + 1], "get") {
        return -1
    }

    if tokens.Kinds[typeEnd + 2] != 129 {
        return -1
    }

    getBodyBrace := typeEnd + 2
    kindStream := new ParserDeclarationKindStream(tokens.Kinds)
    getBodyEnd := MatchingCloseBraceCore(kindStream, count, getBodyBrace)
    if getBodyEnd < 0 {
        return -1
    }

    result.Values[0] = tokens.Starts[propIndex]
    result.Values[1] = nameLength
    result.Values[2] = typeResult.Values[0]
    result.Values[3] = typeResult.Values[1]
    result.Values[4] = getBodyBrace
    result.Values[5] = -1

    after := getBodyEnd + 1
    if after < count && tokens.Kinds[after] == 130 {
        return 0
    }

    if after + 1 < count && tokens.Kinds[after] == 0 && ParserDeclarationTokenTextEquals(source, tokens.Starts[after], tokens.ValueLengths[after], "set") && tokens.Kinds[after + 1] == 129 {
        setBodyBrace := after + 1
        setBodyEnd := MatchingCloseBraceCore(kindStream, count, setBodyBrace)
        if setBodyEnd < 0 || setBodyEnd + 1 >= count || tokens.Kinds[setBodyEnd + 1] != 130 {
            return -1
        }

        result.Values[5] = setBodyBrace
        return 1
    }

    return -1
}

// A top-level TEST-family shape the columnar route does NOT model yet: setup/teardown blocks, and
// any `test` form that is not exactly `test "<description>" [with (…) […]] {` (skip clauses or a
// malformed header). Well-formed plain AND table-driven tests are MODELED (scanned by
// TopLevelColumnarTestDeclarationIndicesInto and parsed by ParseColumnarTestInfoInto), so they no
// longer gate the declaration scan.
func TopLevelUnmodeledTestShapeExistsCore(source: string, tokens: ParserDeclarationTokenTable, count: int): int {
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0

    i := 0
    while i < count {
        kind := tokens.Kinds[i]
        if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            isTestHead := kind == 73
            if kind == 0 && ParserDeclarationTokenTextEquals(source, tokens.Starts[i], tokens.ValueLengths[i], "test") {
                nextAfterTest := ParserDeclarationNextNonNewlineTokenKind(tokens, count, i + 1)
                if nextAfterTest == 4 || nextAfterTest == 129 || ParserDeclarationIsTopLevelDeclarationBoundaryBefore(tokens, i) {
                    isTestHead = true
                }
            }

            if isTestHead {
                if TopLevelTestHeaderEndsAt(tokens, count, i) < 0 {
                    return 1
                }
            } else if kind == 0 && (ParserDeclarationTokenTextEquals(source, tokens.Starts[i], tokens.ValueLengths[i], "setup") || ParserDeclarationTokenTextEquals(source, tokens.Starts[i], tokens.ValueLengths[i], "teardown")) {
                nextKind := ParserDeclarationNextNonNewlineTokenKind(tokens, count, i + 1)
                atDeclarationBoundary := ParserDeclarationIsTopLevelDeclarationBoundaryBefore(tokens, i)
                if nextKind == 129 || atDeclarationBoundary {
                    return 1
                }
            }
        }

        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        }

        i = i + 1
    }

    return 0
}

// The test header `test "<description>"` — optionally followed by the TABLE-DRIVEN clause
// `with ( name: Type, … ) [ (row), … ]` — starting at `testIndex`: returns the token index of the
// body's opening brace, or -1 when the shape is anything else (a `skip` clause, a malformed table,
// missing pieces). `skip` is deliberately NOT accepted here: it is a later capability, and a header
// that parsed it without lowering it would silently DROP the modifier and run a skipped test.
func TopLevelTestHeaderEndsAt(tokens: ParserDeclarationTokenTable, count: int, testIndex: int): int {
    descIndex := TestDescriptionIndexAt(tokens, count, testIndex)
    if descIndex < 0 {
        return -1
    }

    i := SkipTestHeaderNewlines(tokens, count, descIndex + 1)
    if i < count && tokens.Kinds[i] == 71 {
        if TestTableRowCount(tokens, count, i) <= 0 {
            return -1
        }

        i = TestTableClauseEndsAt(tokens, count, i)
        if i < 0 {
            return -1
        }
    }

    if i >= count || tokens.Kinds[i] != 129 {
        return -1
    }

    return i
}

// The first non-newline token index at or after `startIndex`.
func SkipTestHeaderNewlines(tokens: ParserDeclarationTokenTable, count: int, startIndex: int): int {
    i := startIndex
    while i < count && tokens.Kinds[i] == 136 {
        i = i + 1
    }

    return i
}

// The STRING-literal description token index for the test head at `testIndex`, or -1.
func TestDescriptionIndexAt(tokens: ParserDeclarationTokenTable, count: int, testIndex: int): int {
    i := SkipTestHeaderNewlines(tokens, count, testIndex + 1)
    if i >= count || tokens.Kinds[i] != 4 {
        return -1
    }

    return i
}

// From an OPENING delimiter at `openIndex`, the token index directly AFTER its match, or -1 when
// the run never closes. Only the named pair is counted, so a balanced inner pair of a DIFFERENT
// kind (a `[…]` index inside a `(…)` row) passes through untouched.
func MatchingTestDelimiterAfter(tokens: ParserDeclarationTokenTable, count: int, openIndex: int, openKind: int, closeKind: int): int {
    depth := 0
    i := openIndex
    while i < count {
        kind := tokens.Kinds[i]
        if kind == openKind {
            depth = depth + 1
        } else if kind == closeKind {
            depth = depth - 1
            if depth == 0 {
                return i + 1
            }
        }

        i = i + 1
    }

    return -1
}

// `with ( name: Type, … ) [ (row), … ]` starting at the `with` token: the token index directly
// after the closing `]`, or -1.
func TestTableClauseEndsAt(tokens: ParserDeclarationTokenTable, count: int, withIndex: int): int {
    bracketIndex := TestTableRowListStartAt(tokens, count, withIndex)
    if bracketIndex < 0 {
        return -1
    }

    afterRows := MatchingTestDelimiterAfter(tokens, count, bracketIndex, 131, 132)
    if afterRows < 0 {
        return -1
    }

    return SkipTestHeaderNewlines(tokens, count, afterRows)
}

// The `[` that opens the row list of the table clause whose `with` token is at `withIndex`, or -1.
func TestTableRowListStartAt(tokens: ParserDeclarationTokenTable, count: int, withIndex: int): int {
    i := SkipTestHeaderNewlines(tokens, count, withIndex + 1)
    if i >= count || tokens.Kinds[i] != 127 {
        return -1
    }

    afterParameters := MatchingTestDelimiterAfter(tokens, count, i, 127, 128)
    if afterParameters < 0 {
        return -1
    }

    i = SkipTestHeaderNewlines(tokens, count, afterParameters)
    if i >= count || tokens.Kinds[i] != 131 {
        return -1
    }

    return i
}

// The `with` token index for the test head at `testIndex`, or -1 when the test declares no table.
func TestTableWithIndexAt(tokens: ParserDeclarationTokenTable, count: int, testIndex: int): int {
    descIndex := TestDescriptionIndexAt(tokens, count, testIndex)
    if descIndex < 0 {
        return -1
    }

    i := SkipTestHeaderNewlines(tokens, count, descIndex + 1)
    if i < count && tokens.Kinds[i] == 71 {
        return i
    }

    return -1
}

// The token index of the `caseIndex`'th row's opening `(` inside the table clause whose `with`
// token is at `withIndex`, or -1 when there is no such row. Rows are the parenthesised runs
// directly inside the row list's brackets; each one is skipped whole, so a `[…]` or a nested `(…)`
// inside a row value never registers as a row of its own.
func TestTableRowOpenAt(tokens: ParserDeclarationTokenTable, count: int, withIndex: int, caseIndex: int): int {
    bracketIndex := TestTableRowListStartAt(tokens, count, withIndex)
    if bracketIndex < 0 || caseIndex < 0 {
        return -1
    }

    seen := 0
    depth := 0
    i := bracketIndex
    while i < count {
        kind := tokens.Kinds[i]
        if kind == 131 {
            depth = depth + 1
        } else if kind == 132 {
            depth = depth - 1
            if depth == 0 {
                return -1
            }
        } else if kind == 127 && depth == 1 {
            if seen == caseIndex {
                return i
            }

            seen = seen + 1
            afterRow := MatchingTestDelimiterAfter(tokens, count, i, 127, 128)
            if afterRow < 0 {
                return -1
            }

            i = afterRow - 1
        }

        i = i + 1
    }

    return -1
}

// How many rows the table clause at `withIndex` declares. Zero for a test with no table clause,
// and zero for an EMPTY row list — which the header shape then refuses, because a table test with
// no cases would emit no test at all and silently lose the assertions in its body.
func TestTableRowCount(tokens: ParserDeclarationTokenTable, count: int, withIndex: int): int {
    total := 0
    while TestTableRowOpenAt(tokens, count, withIndex, total) >= 0 {
        total = total + 1
    }

    return total
}

// The table parameter list `( name: Type, … )` of the clause at `withIndex`, written into the
// caller's span arrays. Returns the parameter count, or -1 for anything other than the minimal
// `name: Type` form — defaults, modifiers and untyped names are NOT modeled, because each
// parameter becomes a TYPED local declaration whose declared type is exactly what was written.
func TestTableParameterSpansInto(tokens: ParserDeclarationTokenTable, count: int, withIndex: int, outNameStarts: int[], outNameLengths: int[], outTypeStarts: int[], outTypeLengths: int[]): int {
    openIndex := SkipTestHeaderNewlines(tokens, count, withIndex + 1)
    if openIndex >= count || tokens.Kinds[openIndex] != 127 {
        return -1
    }

    afterParameters := MatchingTestDelimiterAfter(tokens, count, openIndex, 127, 128)
    if afterParameters < 0 {
        return -1
    }

    closeIndex := afterParameters - 1
    total := 0
    i := SkipTestHeaderNewlines(tokens, count, openIndex + 1)
    while i < closeIndex {
        if total >= outNameStarts.Length || total >= outTypeStarts.Length {
            return -1
        }

        if tokens.Kinds[i] != 0 {
            return -1
        }

        nameStart := tokens.Starts[i]
        nameLength := tokens.ValueLengths[i]
        i = SkipTestHeaderNewlines(tokens, count, i + 1)
        if i >= closeIndex || tokens.Kinds[i] != 122 {
            return -1
        }

        i = SkipTestHeaderNewlines(tokens, count, i + 1)
        typeStart := -1
        typeEnd := -1
        nestingDepth := 0
        while i < closeIndex {
            kind := tokens.Kinds[i]
            if nestingDepth == 0 && kind == 134 {
                break
            }

            if kind == 100 || kind == 131 {
                nestingDepth = nestingDepth + 1
            } else if kind == 112 {
                nestingDepth = nestingDepth - 2
            } else if kind == 102 || kind == 132 {
                nestingDepth = nestingDepth - 1
            }

            if nestingDepth < 0 {
                nestingDepth = 0
            }

            if kind != 136 {
                if typeStart < 0 {
                    typeStart = tokens.Starts[i]
                }

                typeEnd = tokens.Starts[i] + tokens.ValueLengths[i]
            }

            i = i + 1
        }

        if typeStart < 0 || typeEnd <= typeStart {
            return -1
        }

        outNameStarts[total] = nameStart
        outNameLengths[total] = nameLength
        outTypeStarts[total] = typeStart
        outTypeLengths[total] = typeEnd - typeStart
        total = total + 1
        if i < closeIndex && tokens.Kinds[i] == 134 {
            i = SkipTestHeaderNewlines(tokens, count, i + 1)
        }
    }

    if total <= 0 {
        return -1
    }

    return total
}

// Top-level NEWTYPE declarations: `type X = newtype T` (Type 72, Identifier name, Assign 93,
// Newtype 87, ONE simple underlying type token). Records the Type token index plus the name and
// underlying-type token spans. A composed underlying type (generics, arrays) is unmodeled and
// fails the scan (-1) so the host declines with a reason instead of mis-synthesizing.
func TopLevelColumnarNewtypeDeclarationIndicesInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, outIndices: int[], outNameStarts: int[], outNameLengths: int[], outTypeStarts: int[], outTypeLengths: int[], outResult: int[]): int {
    if count < 0 || count > tokenKinds.Length || outIndices.Length < count + 1 || outResult.Length < 1 {
        return -1
    }

    braceDepth := 0
    outCount := 0
    i := 0
    while i < count {
        kind := tokenKinds[i]
        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if braceDepth == 0 && tokenKinds[i] == 0 && TypeAliasKeywordFacts.SpanNamesAliasKeyword(source, tokenStarts[i], tokenValueLengths[i]) && i + 3 < count && tokenKinds[i + 1] == 0 && tokenKinds[i + 2] == 93 && tokenKinds[i + 3] == 87 {
            if i + 4 >= count || tokenKinds[i + 4] != 0 {
                return -1
            }

            // A COMPOSED underlying type (generic `<`, array `[`, dotted access) is unmodeled.
            if i + 5 < count && (tokenKinds[i + 5] == 100 || tokenKinds[i + 5] == 131 || tokenKinds[i + 5] == 124) {
                return -1
            }

            outIndices[outCount] = i
            outNameStarts[outCount] = tokenStarts[i + 1]
            outNameLengths[outCount] = tokenValueLengths[i + 1]
            outTypeStarts[outCount] = tokenStarts[i + 4]
            outTypeLengths[outCount] = tokenValueLengths[i + 4]
            outCount = outCount + 1
        }

        i = i + 1
    }

    outResult[0] = outCount
    return outCount
}

// Records one entry per top-level test CASE — not per declaration. A plain test contributes its
// `test` keyword token index; a TABLE-DRIVEN test contributes one entry per row, each being that
// row's opening `(` token index. Both are real token indices into the same stream, so a caller that
// reports a failure at the entry points at the exact row that failed. Returns the case count;
// outResult[0] mirrors it (the flat-int ABI convention).
//
// The per-CASE grain is what makes each row its own test: the caller parses each entry through
// ParseColumnarTestInfoInto and gets an independent body with the row's values bound, so a row
// reports under its own name and one row's failure never hides another's.
func TopLevelColumnarTestDeclarationIndicesInto(source: string, rawTokenKinds: int[], rawTokenStarts: int[], rawTokenValueLengths: int[], rawCount: int, outTestIndices: int[], outResult: int[]): int {
    if rawCount < 0 || rawCount > rawTokenKinds.Length || outTestIndices.Length < rawCount + 1 || outResult.Length < 1 {
        return -1
    }

    tokens := new ParserDeclarationTokenTable(rawTokenKinds, rawTokenStarts, rawTokenValueLengths)
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    outCount := 0

    i := 0
    while i < rawCount {
        kind := tokens.Kinds[i]
        if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            isTestHead := kind == 73
            if kind == 0 && ParserDeclarationTokenTextEquals(source, tokens.Starts[i], tokens.ValueLengths[i], "test") {
                nextAfterTest := ParserDeclarationNextNonNewlineTokenKind(tokens, rawCount, i + 1)
                if nextAfterTest == 4 {
                    isTestHead = true
                }
            }

            if isTestHead && TopLevelTestHeaderEndsAt(tokens, rawCount, i) >= 0 {
                withIndex := TestTableWithIndexAt(tokens, rawCount, i)
                if withIndex < 0 {
                    if outCount >= outTestIndices.Length {
                        return -1
                    }

                    outTestIndices[outCount] = i
                    outCount = outCount + 1
                } else {
                    rowIndex := 0
                    rowOpen := TestTableRowOpenAt(tokens, rawCount, withIndex, rowIndex)
                    while rowOpen >= 0 {
                        if outCount >= outTestIndices.Length {
                            return -1
                        }

                        outTestIndices[outCount] = rowOpen
                        outCount = outCount + 1
                        rowIndex = rowIndex + 1
                        rowOpen = TestTableRowOpenAt(tokens, rawCount, withIndex, rowIndex)
                    }
                }
            }
        }

        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        }

        i = i + 1
    }

    outResult[0] = outCount
    return outCount
}

// Parse ONE test CASE at the entry `testIndex` that TopLevelColumnarTestDeclarationIndicesInto
// recorded — either a plain `test "<description>" { body }` head, or one row of a table-driven
// `test "<description>" with (name: Type, …) [ (row), … ] { body }`.
//
// The description STRING token's span lands in outResult[0]/[1] (raw, quotes included);
// outResult[4]/[5] carry the ROW's source span for a table case and (-1, 0) for a plain one, so the
// host composes the case's label through ColumnarTestCaseLabel rather than deciding it itself.
// outResult[2] = body root node id, outResult[3] = token index past the body. Returns the body node
// count, or -1.
//
// A TABLE CASE IS LOWERED, NOT SPECIAL-CASED DOWNSTREAM. The row's values are parsed into the same
// node table as the body and then bound as TYPED local declarations (kind 40) prepended to the
// body block — so what the emitter, the analyser and the runner all see is an ordinary test whose
// first statements happen to be `name: Type = value`. Every row therefore emits its own method,
// carries its own description and reports its own result.
func ParseColumnarTestInfoInto(source: string, rawTokenKinds: int[], rawTokenStarts: int[], rawTokenValueLengths: int[], rawCount: int, testIndex: int, bodyKinds: int[], bodyValueStarts: int[], bodyValueLengths: int[], bodyChildStarts: int[], bodyChildCounts: int[], bodyChildIndices: int[], bodySpanStarts: int[], bodySpanLengths: int[], outResult: int[]): int {
    if rawCount < 0 || testIndex < 0 || testIndex >= rawCount || outResult.Length < 6 {
        return -1
    }

    declTokens := new ParserDeclarationTokenTable(rawTokenKinds, rawTokenStarts, rawTokenValueLengths)
    entry := new int[](2)
    if !ResolveColumnarTestCaseEntry(source, declTokens, rawCount, testIndex, entry) {
        return -1
    }

    headIndex := entry[0]
    caseIndex := entry[1]
    bodyBrace := TopLevelTestHeaderEndsAt(declTokens, rawCount, headIndex)
    if bodyBrace < 0 {
        return -1
    }

    descIndex := TestDescriptionIndexAt(declTokens, rawCount, headIndex)
    if descIndex < 0 {
        return -1
    }

    outResult[0] = rawTokenStarts[descIndex]
    outResult[1] = rawTokenValueLengths[descIndex]
    outResult[4] = -1
    outResult[5] = 0

    statementTokens := new ParserTokenTable(rawTokenKinds, rawTokenStarts, rawTokenValueLengths, source)
    argStack := new ParserArgumentStack(new int[](rawCount + 1))
    nodes := new ParserExpressionNodeTable(bodyKinds, bodyValueStarts, bodyValueLengths, bodyChildStarts, bodyChildCounts, bodySpanStarts, bodySpanLengths)
    children := new ParserChildIndexTable(bodyChildIndices)
    if caseIndex < 0 {
        statementResult := new ParserResultTable(new int[](2))
        bodyNodeCount := ParseStatementNodesCore(source, statementTokens, rawCount, bodyBrace, argStack, nodes, children, statementResult)
        if bodyNodeCount <= 0 {
            return -1
        }

        outResult[2] = statementResult.Values[0]
        outResult[3] = statementResult.Values[1]
        return bodyNodeCount
    }

    return ParseColumnarTableTestCaseInto(source, declTokens, statementTokens, rawCount, headIndex, caseIndex, bodyBrace, argStack, nodes, children, outResult)
}

// Which declaration an entry recorded by TopLevelColumnarTestDeclarationIndicesInto belongs to.
// entry[0] = the test head's keyword token index; entry[1] = the row ordinal, or -1 for a plain
// test. A `(` entry is resolved by re-walking the top-level heads rather than scanning backwards,
// because only the forward walk knows which parens are at row depth of a MODELED header.
func ResolveColumnarTestCaseEntry(source: string, tokens: ParserDeclarationTokenTable, count: int, entryIndex: int, entry: int[]): bool {
    if entry.Length < 2 {
        return false
    }

    if tokens.Kinds[entryIndex] != 127 {
        entry[0] = entryIndex
        entry[1] = -1
        return TopLevelTestHeaderEndsAt(tokens, count, entryIndex) >= 0
    }

    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    i := 0
    while i < count {
        kind := tokens.Kinds[i]
        if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 {
            isTestHead := kind == 73
            if kind == 0 && ParserDeclarationTokenTextEquals(source, tokens.Starts[i], tokens.ValueLengths[i], "test") {
                if ParserDeclarationNextNonNewlineTokenKind(tokens, count, i + 1) == 4 {
                    isTestHead = true
                }
            }

            if isTestHead && TopLevelTestHeaderEndsAt(tokens, count, i) >= 0 {
                withIndex := TestTableWithIndexAt(tokens, count, i)
                if withIndex >= 0 {
                    rowIndex := 0
                    rowOpen := TestTableRowOpenAt(tokens, count, withIndex, rowIndex)
                    while rowOpen >= 0 {
                        if rowOpen == entryIndex {
                            entry[0] = i
                            entry[1] = rowIndex
                            return true
                        }

                        rowIndex = rowIndex + 1
                        rowOpen = TestTableRowOpenAt(tokens, count, withIndex, rowIndex)
                    }
                }
            }
        }

        if kind == 129 {
            braceDepth = braceDepth + 1
        } else if kind == 130 {
            braceDepth = braceDepth - 1
            if braceDepth < 0 {
                braceDepth = 0
            }
        } else if kind == 131 {
            bracketDepth = bracketDepth + 1
        } else if kind == 132 {
            bracketDepth = bracketDepth - 1
            if bracketDepth < 0 {
                bracketDepth = 0
            }
        } else if kind == 127 {
            parenDepth = parenDepth + 1
        } else if kind == 128 {
            parenDepth = parenDepth - 1
            if parenDepth < 0 {
                parenDepth = 0
            }
        }

        i = i + 1
    }

    return false
}

// Lower one ROW of a table-driven test into a self-contained body: parse the row's values, parse
// the shared body, then prepend one typed local per table parameter binding that parameter's
// DECLARED type to the row's own expression. Returns the node count, or -1.
func ParseColumnarTableTestCaseInto(source: string, declTokens: ParserDeclarationTokenTable, statementTokens: ParserTokenTable, rawCount: int, headIndex: int, caseIndex: int, bodyBrace: int, argStack: ParserArgumentStack, nodes: ParserExpressionNodeTable, children: ParserChildIndexTable, outResult: int[]): int {
    withIndex := TestTableWithIndexAt(declTokens, rawCount, headIndex)
    if withIndex < 0 {
        return -1
    }

    nameStarts := new int[](rawCount + 1)
    nameLengths := new int[](rawCount + 1)
    typeStarts := new int[](rawCount + 1)
    typeLengths := new int[](rawCount + 1)
    parameterCount := TestTableParameterSpansInto(declTokens, rawCount, withIndex, nameStarts, nameLengths, typeStarts, typeLengths)
    if parameterCount <= 0 {
        return -1
    }

    rowOpen := TestTableRowOpenAt(declTokens, rawCount, withIndex, caseIndex)
    if rowOpen < 0 {
        return -1
    }

    afterRow := MatchingTestDelimiterAfter(declTokens, rawCount, rowOpen, 127, 128)
    if afterRow < 0 {
        return -1
    }

    rowClose := afterRow - 1
    outResult[4] = declTokens.Starts[rowOpen]
    outResult[5] = declTokens.Starts[rowClose] + declTokens.ValueLengths[rowClose] - declTokens.Starts[rowOpen]

    valueRoots := new int[](parameterCount)
    valueCount := 0
    st := new ParserState(rowOpen + 1, 0, 0, 0, 0, 0, source)
    while st.Pos < rowClose {
        if statementTokens.Kinds[st.Pos] == 136 {
            st.Pos = st.Pos + 1
        } else {
            if valueCount >= parameterCount {
                return -1
            }

            valueRoot := ParseLambdaOrAssignmentExpressionNode(statementTokens, rowClose, st, argStack, nodes, children, 0)
            if valueRoot < 0 {
                return -1
            }

            valueRoots[valueCount] = valueRoot
            valueCount = valueCount + 1
            while st.Pos < rowClose && statementTokens.Kinds[st.Pos] == 136 {
                st.Pos = st.Pos + 1
            }

            if st.Pos < rowClose {
                if statementTokens.Kinds[st.Pos] != 134 {
                    return -1
                }

                st.Pos = st.Pos + 1
            }
        }
    }

    // A row must fill EVERY parameter. A short or long row is a decline rather than a silent
    // binding, because the missing name would otherwise resolve to whatever else is in scope.
    if valueCount != parameterCount {
        return -1
    }

    st.Pos = bodyBrace
    bodyRoot := ParseStatementCoreNode(statementTokens, rawCount, st, argStack, nodes, children, 0)
    if bodyRoot < 0 || nodes.Kinds[bodyRoot] != 25 {
        return -1
    }

    bodyChildStart := nodes.ChildStart[bodyRoot]
    bodyChildCount := nodes.ChildCount[bodyRoot]
    if st.NodeCursor + 2 * parameterCount > nodes.Kinds.Length {
        return -1
    }

    if st.ChildCursor + 3 * parameterCount + bodyChildCount > children.Indices.Length {
        return -1
    }

    declarationRoots := new int[](parameterCount)
    p := 0
    while p < parameterCount {
        nameNode := EmitExpressionNode(st, nodes, 6, nameStarts[p], nameLengths[p], -1, 0, nameStarts[p], nameLengths[p])
        declarationChildStart := st.ChildCursor
        AppendExpressionChild(st, children, nameNode)
        AppendExpressionChild(st, children, valueRoots[p])
        parameterEnd := typeStarts[p] + typeLengths[p]
        declarationRoots[p] = EmitExpressionNode(st, nodes, 40, typeStarts[p], typeLengths[p], declarationChildStart, 2, nameStarts[p], parameterEnd - nameStarts[p])
        p = p + 1
    }

    loweredChildStart := st.ChildCursor
    p = 0
    while p < parameterCount {
        AppendExpressionChild(st, children, declarationRoots[p])
        p = p + 1
    }

    c := 0
    while c < bodyChildCount {
        AppendExpressionChild(st, children, children.Indices[bodyChildStart + c])
        c = c + 1
    }

    nodes.ChildStart[bodyRoot] = loweredChildStart
    nodes.ChildCount[bodyRoot] = parameterCount + bodyChildCount
    outResult[2] = bodyRoot
    outResult[3] = st.Pos
    return st.NodeCursor
}

// The DESCRIPTION a single test case reports under, composed from the spans
// ParseColumnarTestInfoInto returned. A plain test reports its literal description; a table row
// reports that description followed by the row's own source text, whitespace-collapsed — so
// `test "adds" with (a: int, b: int, sum: int) [ (1, 2, 3) ]` reports `adds (1, 2, 3)`. The label
// is the CASE's identity everywhere it is seen: the emitted method name derives from it, the
// `NSharpDescription` trait carries it, and `nlc test --json` prints it as `displayName`.
func ColumnarTestCaseLabel(source: string, result: int[]): string {
    if result.Length < 6 || result[0] < 0 || result[1] <= 0 || result[0] + result[1] > source.Length {
        return ""
    }

    description := StringLiteralDecoder.Decode(source.Substring(result[0], result[1]), false)
    if result[4] < 0 || result[5] <= 0 || result[4] + result[5] > source.Length {
        return description
    }

    return description + " " + CollapseTestCaseWhitespace(source.Substring(result[4], result[5]))
}

// The row's source text with every whitespace run collapsed to a single space, the edges trimmed,
// and no space left hugging the row's own punctuation — so a row spread over several lines labels
// its case on ONE line and in the shape the developer would have written it inline.
func CollapseTestCaseWhitespace(text: string): string {
    builder := new StringBuilder()
    pendingSpace := false
    written := 0
    previous := ' '
    for ch in text {
        if char.IsWhiteSpace(ch) {
            pendingSpace = written > 0
        } else {
            if pendingSpace && !IsTestCaseLabelCloser(ch) && !IsTestCaseLabelOpener(previous) {
                builder.Append(' ')
            }

            pendingSpace = false
            builder.Append(ch)
            previous = ch
            written = written + 1
        }
    }

    return builder.ToString()
}

// True for a character nothing should be spaced AFTER.
func IsTestCaseLabelOpener(ch: char): bool {
    return ch == '(' || ch == '['
}

// True for a character nothing should be spaced BEFORE.
func IsTestCaseLabelCloser(ch: char): bool {
    return ch == ')' || ch == ']' || ch == ','
}

func ParserDeclarationNextNonNewlineTokenKind(tokens: ParserDeclarationTokenTable, count: int, startIndex: int): int {
    i := startIndex
    while i < count {
        if tokens.Kinds[i] != 136 {
            return tokens.Kinds[i]
        }

        i = i + 1
    }

    return -1
}

func ParserDeclarationIsTopLevelDeclarationBoundaryBefore(tokens: ParserDeclarationTokenTable, index: int): bool {
    if index <= 0 {
        return true
    }

    previousKind := tokens.Kinds[index - 1]
    return previousKind == 136 || previousKind == 130 || previousKind == 133
}

// Does the source between two token offsets contain a line break? The cast lookahead uses it to keep a
// `(Type)` at the end of a line from swallowing the FIRST TOKEN OF THE NEXT STATEMENT as its operand:
// N# has no statement terminator, so that newline IS the boundary. `source` may be empty (several
// expression-only entry points build their ParserState without it), in which case the range check below
// answers false and the caller keeps its prior reading rather than guessing.
func ParserSourceHasLineBreakBetween(source: string, start: int, end: int): bool {
    if start < 0 || start >= end || end > source.Length {
        return false
    }

    i := start
    while i < end {
        if source[i] == '\n' {
            return true
        }

        i = i + 1
    }

    return false
}

func ParserDeclarationTokenTextEquals(source: string, start: int, length: int, expected: string): bool {
    if start < 0 || length != expected.Length || start + length > source.Length {
        return false
    }

    i := 0
    while i < length {
        if source[start + i] != expected[i] {
            return false
        }

        i = i + 1
    }

    return true
}
