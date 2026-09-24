import System
import System.Text


// MEMBERS: interface and enum declarations, the declaration name, namespace and type-span readers,
// the modifier words, and the initializer scans a member body needs.
//
// Formerly part of `CompilerServices/ColumnarParserKernels.nl`, a 17,120-line file whose first
// 2,061 lines were fifteen files mechanically concatenated behind `// ---- X.nl ----` markers --
// a bootstrap artifact of the Dogfood assembly, not a design. Split back by concern; every line
// below is a verbatim move.
func ParseInterfaceDeclarationCore(source: string, tokens: ParserDeclarationTokenTable, count: int, interfaceIndex: int, decl: InterfaceDeclarationTable, result: ParserDeclarationResultTable): int {
    pos := interfaceIndex
    if pos >= count || tokens.Kinds[pos] != 10 {
        return -1
    }

    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }

    result.Values[0] = tokens.Starts[pos]
    result.Values[1] = tokens.ValueLengths[pos]
    pos = pos + 1

    typeParamCount := 0
    if pos < count && tokens.Kinds[pos] == 100 {
        pos = pos + 1
        while pos < count && tokens.Kinds[pos] != 102 {
            if tokens.Kinds[pos] != 0 {
                return -1
            }

            decl.TypeParamStarts[typeParamCount] = tokens.Starts[pos]
            decl.TypeParamLengths[typeParamCount] = tokens.ValueLengths[pos]
            typeParamCount = typeParamCount + 1
            pos = pos + 1

            if pos < count && tokens.Kinds[pos] != 102 {
                if tokens.Kinds[pos] != 134 {
                    return -1
                }

                pos = pos + 1
                if pos >= count || tokens.Kinds[pos] != 0 {
                    return -1
                }
            }
        }

        if pos >= count || tokens.Kinds[pos] != 102 || typeParamCount == 0 {
            return -1
        }

        pos = pos + 1
    }

    if result.Values.Length > 4 {
        result.Values[4] = typeParamCount
    }

    baseTypeResult := new ParserDeclarationResultTable(new int[](2))
    baseCount := 0
    if pos < count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        while true {
            typeEnd := ParseDeclarationTypeSpanCore(tokens, count, pos, baseTypeResult)
            if typeEnd < 0 {
                return -1
            }

            decl.BaseNameStarts[baseCount] = baseTypeResult.Values[0]
            decl.BaseNameLengths[baseCount] = baseTypeResult.Values[1]
            baseCount = baseCount + 1
            pos = typeEnd

            if pos < count && tokens.Kinds[pos] == 134 {
                pos = pos + 1
                continue
            }

            break
        }
    }

    result.Values[2] = baseCount

    // Generic CONSTRAINTS, between the base-interface list and the body.
    ifaceWhereNext := pos
    ifaceWhereCount := ParseDeclarationWhereClausesCore(tokens, count, pos, decl.Where, out ifaceWhereNext)
    if ifaceWhereCount < 0 {
        return -1
    }

    pos = ifaceWhereNext
    if result.Values.Length > 6 {
        result.Values[6] = ifaceWhereCount
    }

    if pos >= count || tokens.Kinds[pos] != 129 {
        return -1
    }

    pos = pos + 1

    methodCount := 0
    eventCount := 0
    propertyCount := 0
    eventTypeResult := new ParserDeclarationResultTable(new int[](2))
    propertyTypeResult := new ParserDeclarationResultTable(new int[](2))
    while pos < count && tokens.Kinds[pos] != 130 {
        // AN EVENT MEMBER: `event Name: DelegateType`. `event` is CONTEXTUAL here exactly as it is in a
        // struct body — the word is an ordinary identifier followed by a NAME and a `:`, which no
        // other interface member spells — so `event` keeps working as a name everywhere else.
        if ParseInterfaceDeclarationMemberIsEvent(source, tokens, count, pos) {
            decl.EventNameStarts[eventCount] = tokens.Starts[pos + 1]
            decl.EventNameLengths[eventCount] = tokens.ValueLengths[pos + 1]
            pos = pos + 3
            pos = ParseDeclarationTypeSpanCore(tokens, count, pos, eventTypeResult)
            if pos < 0 {
                return -1
            }

            decl.EventTypeStarts[eventCount] = eventTypeResult.Values[0]
            decl.EventTypeLengths[eventCount] = eventTypeResult.Values[1]
            eventCount = eventCount + 1
            continue
        }

        // A VALUE MEMBER: `Name: Type`, the bare spelling a class uses for its own value members. It
        // is read AFTER the event arm because an event is `event Name :` — an identifier more — and
        // what it declares is a get-only abstract property slot.
        if ParseInterfaceDeclarationMemberIsValue(tokens, count, pos) {
            decl.PropertyNameStarts[propertyCount] = tokens.Starts[pos]
            decl.PropertyNameLengths[propertyCount] = tokens.ValueLengths[pos]
            pos = pos + 2
            pos = ParseDeclarationTypeSpanCore(tokens, count, pos, propertyTypeResult)
            if pos < 0 {
                return -1
            }

            decl.PropertyTypeStarts[propertyCount] = propertyTypeResult.Values[0]
            decl.PropertyTypeLengths[propertyCount] = propertyTypeResult.Values[1]
            propertyCount = propertyCount + 1
            continue
        }

        if tokens.Kinds[pos] != 7 {
            return -1
        }

        decl.MethodFuncIndices[methodCount] = pos
        pos = pos + 1
        // A PARAMETER IS SPELLED `name: type` TOO, so the value-member test can only be asked OUTSIDE
        // the signature's own brackets — `func Mutate(ref left: int)` otherwise ends the method at
        // `left` and reads the rest of the parameter list as members.
        signatureDepth := 0
        while pos < count && tokens.Kinds[pos] != 130 && (signatureDepth > 0 || (tokens.Kinds[pos] != 7 && !ParseInterfaceDeclarationMemberIsEvent(source, tokens, count, pos) && !ParseInterfaceDeclarationMemberIsValue(tokens, count, pos))) {
            if tokens.Kinds[pos] == 127 || tokens.Kinds[pos] == 131 {
                signatureDepth = signatureDepth + 1
                pos = pos + 1
                continue
            }

            if tokens.Kinds[pos] == 128 || tokens.Kinds[pos] == 132 {
                signatureDepth = signatureDepth - 1
                if signatureDepth < 0 {
                    return -1
                }

                pos = pos + 1
                continue
            }

            if tokens.Kinds[pos] == 129 {
                depth := 1
                pos = pos + 1
                while pos < count && depth > 0 {
                    if tokens.Kinds[pos] == 129 {
                        depth = depth + 1
                    } else if tokens.Kinds[pos] == 130 {
                        depth = depth - 1
                    }

                    pos = pos + 1
                }

                if depth != 0 {
                    return -1
                }

                break
            }

            pos = pos + 1
        }

        methodCount = methodCount + 1
    }

    if pos >= count {
        return -1
    }

    if result.Values.Length > 7 {
        result.Values[7] = eventCount
    }

    if result.Values.Length > 8 {
        result.Values[8] = propertyCount
    }

    return methodCount
}

// `event Name: …` at this position, read the way the struct body reads it: the word is an ordinary
// identifier, so the shape after it is what identifies the member.
func ParseInterfaceDeclarationMemberIsEvent(source: string, tokens: ParserDeclarationTokenTable, count: int, pos: int): bool {
    if pos + 2 >= count || tokens.Kinds[pos] != 0 || tokens.Kinds[pos + 1] != 0 || tokens.Kinds[pos + 2] != 122 {
        return false
    }

    return ParserDeclarationTokenTextEquals(source, tokens.Starts[pos], tokens.ValueLengths[pos], "event")
}

// `Name: …` at this position — an identifier followed by a `:`. No other interface member spells
// that: a method opens with `func`, an event has a NAME between the word and the colon, and a base
// list and a constraint clause are both read before the body opens.
func ParseInterfaceDeclarationMemberIsValue(tokens: ParserDeclarationTokenTable, count: int, pos: int): bool {
    return pos + 1 < count && tokens.Kinds[pos] == 0 && tokens.Kinds[pos + 1] == 122
}

func ParseEnumMemberValuesCore(source: string, members: EnumMemberTable, memberCount: int, values: EnumMemberValueTable): bool {
    if memberCount < 0 || memberCount > values.Values.Length {
        return false
    }

    nextValue := 0
    i := 0
    while i < memberCount {
        value := nextValue
        if members.HasValue[i] != 0 {
            if !ParserDeclarationTryParseIntLiteralCore(source, members.ValueStarts[i], members.ValueLengths[i], values, i) {
                return false
            }

            value = values.Values[i]
        } else {
            values.Values[i] = value
        }

        nextValue = ParserDeclarationNextEnumValue(value)
        i = i + 1
    }

    return true
}

func ParserDeclarationSpanText(source: string, start: int, length: int): string {
    if start < 0 || length <= 0 || start + length > source.Length {
        return ""
    }

    return source.Substring(start, length)
}

func ParserDeclarationSourceSpansEqual(source: string, leftStart: int, leftLength: int, rightStart: int, rightLength: int): bool {
    if leftStart < 0 || rightStart < 0 || leftLength != rightLength {
        return false
    }

    if leftStart + leftLength > source.Length || rightStart + rightLength > source.Length {
        return false
    }

    i := 0
    while i < leftLength {
        if source[leftStart + i] != source[rightStart + i] {
            return false
        }

        i = i + 1
    }

    return true
}

// THE SAME SCAN, ONCE. Eight functions -- `ColumnarStructFieldNamesDistinct`,
// `ColumnarStructBaseNamesDistinct`, `ColumnarStructTypeParameterNamesDistinct`,
// `ColumnarUnionCaseNamesDistinct`, `ColumnarUnionTypeParameterNamesDistinct`,
// `ColumnarEnumMemberNamesDistinct`, `FunctionSignatureTypeParameterNamesDistinctCore` and
// `FunctionSignatureParameterNamesDistinctCore` -- were the same twenty-five lines over a different
// pair of span columns on a different scratch table. The columns are `int[]`, so they are ordinary
// arguments; the table each pair lives on is the caller's business, not this scan's.
func ParserDeclarationNameSpansDistinct(source: string, starts: int[], lengths: int[], count: int): int {
    if count < 0 {
        return 0
    }

    i := 0
    while i < count {
        if starts[i] < 0 || lengths[i] <= 0 {
            return 0
        }

        j := i + 1
        while j < count {
            if ParserDeclarationSourceSpansEqual(source, starts[i], lengths[i], starts[j], lengths[j]) {
                return 0
            }

            j = j + 1
        }

        i = i + 1
    }

    return 1
}

func ParserDeclarationDottedNameSpanAfter(tokens: ParserDeclarationTokenTable, count: int, nameStartIndex: int, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 2 {
        return -1
    }

    result.Values[0] = -1
    result.Values[1] = 0

    if nameStartIndex < 0 || nameStartIndex >= count || tokens.Kinds[nameStartIndex] != 0 {
        return -1
    }

    start := tokens.Starts[nameStartIndex]
    end := tokens.Starts[nameStartIndex] + tokens.ValueLengths[nameStartIndex]
    pos := nameStartIndex + 1
    expectDot := 1
    while pos < count {
        if expectDot == 1 {
            if tokens.Kinds[pos] != 124 {
                break
            }

            expectDot = 0
        } else {
            if tokens.Kinds[pos] != 0 {
                return -1
            }

            end = tokens.Starts[pos] + tokens.ValueLengths[pos]
            expectDot = 1
        }

        pos = pos + 1
    }

    if expectDot == 0 {
        return -1
    }

    result.Values[0] = start
    result.Values[1] = end - start
    return pos
}

func ParserDeclarationNamespaceSpanBefore(tokens: ParserDeclarationTokenTable, count: int, declarationIndex: int, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 2 || declarationIndex < 0 || declarationIndex > count {
        return -1
    }

    result.Values[0] = -1
    result.Values[1] = 0
    braceDepth := 0
    bracketDepth := 0
    parenDepth := 0
    i := 0
    nameResult := new ParserDeclarationResultTable(new int[](2))
    while i < declarationIndex {
        kind := tokens.Kinds[i]
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
        } else if braceDepth == 0 && bracketDepth == 0 && parenDepth == 0 && (kind == 15 || kind == 18) {
            next := ParserDeclarationDottedNameSpanAfter(tokens, count, i + 1, nameResult)
            if next < 0 {
                return -1
            }

            result.Values[0] = nameResult.Values[0]
            result.Values[1] = nameResult.Values[1]
            i = next - 1
        }

        i = i + 1
    }

    return 1
}

func ParserDeclarationQualifiedNameText(source: string, tokens: ParserDeclarationTokenTable, count: int, declarationIndex: int, nameStart: int, nameLength: int): string {
    name := ParserDeclarationSpanText(source, nameStart, nameLength)
    if name == "" {
        return ""
    }

    namespaceResult := new ParserDeclarationResultTable(new int[](2))
    if ParserDeclarationNamespaceSpanBefore(tokens, count, declarationIndex, namespaceResult) < 0 {
        return ""
    }

    if namespaceResult.Values[1] <= 0 {
        return name
    }

    namespaceName := ParserDeclarationSpanText(source, namespaceResult.Values[0], namespaceResult.Values[1])
    if namespaceName == "" {
        return ""
    }

    return namespaceName + "." + name
}

func ParserDeclarationDirectContainingTypeNameText(source: string, tokens: ParserDeclarationTokenTable, count: int, declarationIndex: int): string {
    if declarationIndex < 0 || declarationIndex > count {
        return ""
    }

    depth := 0
    i := declarationIndex - 1
    while i >= 0 {
        kind := tokens.Kinds[i]
        if kind == 130 {
            depth = depth + 1
        } else if kind == 129 {
            if depth == 0 {
                ownerKeyword := i - 1
                ownerFound := 0
                while ownerKeyword >= 0 && ownerFound == 0 {
                    ownerKind := tokens.Kinds[ownerKeyword]
                    if ownerKind == 8 || ownerKind == 9 || ownerKind == 13 {
                        ownerFound = 1
                    } else {
                        ownerKeyword = ownerKeyword - 1
                    }
                }

                if ownerFound == 0 {
                    return ""
                }

                ownerNameIndex := ownerKeyword + 1
                if tokens.Kinds[ownerKeyword] == 13 && ownerNameIndex < count && tokens.Kinds[ownerNameIndex] == 9 {
                    ownerNameIndex = ownerNameIndex + 1
                }

                if ownerNameIndex >= count || tokens.Kinds[ownerNameIndex] != 0 {
                    return ""
                }

                return ParserDeclarationQualifiedNameText(source, tokens, count, ownerKeyword, tokens.Starts[ownerNameIndex], tokens.ValueLengths[ownerNameIndex])
            }

            depth = depth - 1
        }

        i = i - 1
    }

    return ""
}

func ParserDeclarationNamespacesEqual(source: string, tokens: ParserDeclarationTokenTable, count: int, leftDeclarationIndex: int, rightDeclarationIndex: int): int {
    leftResult := new ParserDeclarationResultTable(new int[](2))
    rightResult := new ParserDeclarationResultTable(new int[](2))
    if ParserDeclarationNamespaceSpanBefore(tokens, count, leftDeclarationIndex, leftResult) < 0 {
        return -1
    }

    if ParserDeclarationNamespaceSpanBefore(tokens, count, rightDeclarationIndex, rightResult) < 0 {
        return -1
    }

    if leftResult.Values[1] != rightResult.Values[1] {
        return 0
    }

    if leftResult.Values[1] == 0 {
        return 1
    }

    if ParserDeclarationSourceSpansEqual(source, leftResult.Values[0], leftResult.Values[1], rightResult.Values[0], rightResult.Values[1]) {
        return 1
    }

    return 0
}

func ParserDeclarationNextEnumValue(value: int): int {
    if value == 2147483647 {
        return 0 - 2147483647 - 1
    }

    return value + 1
}

func ParserDeclarationTryParseIntLiteralCore(source: string, start: int, length: int, result: EnumMemberValueTable, resultIndex: int): bool {
    if start < 0 || length <= 0 || start + length > source.Length || resultIndex < 0 || resultIndex >= result.Values.Length {
        return false
    }

    negative := false
    index := start
    end := start + length
    if source[index] == '+' || source[index] == '-' {
        negative = source[index] == '-'
        index = index + 1
        if index >= end {
            return false
        }
    }

    value := 0
    hasDigit := false
    while index < end {
        ch := source[index]
        if ch == '_' {
            index = index + 1
            continue
        }

        if ch < '0' || ch > '9' {
            return false
        }

        hasDigit = true
        digit := ch - '0'
        if value > 214748364 {
            return false
        }

        if value == 214748364 {
            if negative {
                if digit == 8 && ParserDeclarationOnlyNumericSeparatorsRemain(source, index + 1, end) {
                    result.Values[resultIndex] = 0 - 2147483647 - 1
                    return true
                }

                return false
            }

            if digit > 7 {
                return false
            }
        }

        value = value * 10 + digit
        index = index + 1
    }

    if !hasDigit {
        return false
    }

    if negative {
        result.Values[resultIndex] = 0 - value
    } else {
        result.Values[resultIndex] = value
    }

    return true
}

func ParserDeclarationOnlyNumericSeparatorsRemain(source: string, start: int, end: int): bool {
    index := start
    while index < end {
        if source[index] != '_' {
            return false
        }

        index = index + 1
    }

    return true
}

func ParseEnumDeclarationCore(tokens: ParserDeclarationTokenTable, count: int, enumIndex: int, members: EnumMemberTable, result: ParserDeclarationResultTable): int {
    pos := enumIndex
    if pos >= count || tokens.Kinds[pos] != 14 {
        return -1
    }

    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }

    result.Values[0] = tokens.Starts[pos]
    result.Values[1] = tokens.ValueLengths[pos]
    pos = pos + 1

    if pos < count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        if pos >= count || tokens.Kinds[pos] != 0 {
            return -1
        }

        pos = pos + 1
    }

    if pos >= count || tokens.Kinds[pos] != 129 {
        return -1
    }

    pos = pos + 1

    memberCount := 0
    while pos < count && tokens.Kinds[pos] != 130 {
        // AN ENUM MEMBER MAY CARRY ATTRIBUTES, and they are stepped over here rather than read:
        // the member's own token index is what this kernel records, and the reader that wants the
        // `[...]` groups walks back from it. A group that never closes is a malformed declaration.
        while pos < count && tokens.Kinds[pos] == 131 {
            close := ParserDeclarationAttributeGroupClose(tokens, count, pos)
            if close < 0 {
                return -1
            }

            pos = close + 1
        }

        if pos >= count || tokens.Kinds[pos] != 0 {
            return -1
        }

        members.NameStarts[memberCount] = tokens.Starts[pos]
        members.NameLengths[memberCount] = tokens.ValueLengths[pos]
        members.NameTokens[memberCount] = pos
        members.HasValue[memberCount] = 0
        members.ValueStarts[memberCount] = -1
        members.ValueLengths[memberCount] = 0
        pos = pos + 1

        if pos < count && tokens.Kinds[pos] == 93 {
            pos = pos + 1
            if pos >= count || (tokens.Kinds[pos] != 1 && tokens.Kinds[pos] != 4) {
                return -1
            }

            members.HasValue[memberCount] = 1
            members.ValueStarts[memberCount] = tokens.Starts[pos]
            members.ValueLengths[memberCount] = tokens.ValueLengths[pos]
            pos = pos + 1
        }

        memberCount = memberCount + 1

        if pos < count && tokens.Kinds[pos] != 130 {
            if tokens.Kinds[pos] != 134 {
                return -1
            }

            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 130 {
        return -1
    }

    return memberCount
}

func ParserDeclarationCanonicalTypeText(source: string, start: int, length: int): string {
    if start < 0 || length <= 0 || start + length > source.Length {
        return ""
    }

    // A COMPOSED type is the one whose written form can hold whitespace, and a TUPLE is composed:
    // `(Item: string, Count: int)` must canonicalise to `(Item:string,Count:int)` exactly as
    // `List< int >` canonicalises to `List<int>`, because a canonical never contains a space.
    hasComposedSuffix := false
    i := 0
    while i < length {
        if source[start + i] == '<' || source[start + i] == '(' {
            hasComposedSuffix = true
            break
        }

        i = i + 1
    }

    if !hasComposedSuffix {
        return source.Substring(start, length)
    }

    builder := new StringBuilder(length)
    i = 0
    while i < length {
        ch := source[start + i]
        if !Char.IsWhiteSpace(ch) {
            builder.Append(ch)
        }

        i = i + 1
    }

    return builder.ToString()
}

// A MEMBER NAME MAY BE QUALIFIED, AND THIS IS THE SHAPE OF THE QUALIFICATION.
//
// An EXPLICIT INTERFACE IMPLEMENTATION is spelled `Interface.Member` in the type body —
// `func IEnumerable.GetEnumerator(): IEnumerator { … }`, `IReadOnlyCollection<string>.Count: int => …`
// — and a generic interface is written CLOSED, exactly as the implements list writes it. The
// qualifier may itself be dotted (`System.Collections.IEnumerable.GetEnumerator`), so the scan is a
// LOOP and the member name is whatever follows the LAST dot.
//
// IT IS DECIDED PURELY BY TOKEN KIND, which is what lets the member scan, the signature kernel and
// the property kernel all ask the same question of their own token columns. `start` is the index just
// PAST the name's first identifier; the answer is the index just past the whole qualified name, or -1
// when the name is an ordinary one-token name.
//
// -1 RATHER THAN `start` IS THE POINT. A generic METHOD is `Compare<T>(` — an argument list with no
// dot after it — and a plain method is `Read(`. Both must leave the caller's cursor exactly where it
// was, because the type-parameter list behind it is parsed by the owner that has always parsed it.
func ExplicitInterfaceMemberNameEnd(kinds: int[], count: int, start: int): int {
    pos := start
    lastEnd := -1
    scanning := true
    while scanning {
        if pos < count && kinds[pos] == 100 {
            closed := ExplicitInterfaceQualifierArgumentListEnd(kinds, count, pos)
            if closed < 0 {
                return lastEnd
            }

            pos = closed
        }

        if pos + 1 < count && kinds[pos] == 124 && kinds[pos + 1] == 0 {
            pos = pos + 2
            lastEnd = pos
        } else {
            scanning = false
        }
    }

    return lastEnd
}

// The `<` … `>` of a closed qualifier. `>>` is ONE token (RightShift, 112) and closes TWO levels,
// which is the same rule every type scanner in this file applies. A brace, a newline or end of file
// cannot appear inside a type-argument list, so meeting one means the `<` was a comparison and the
// name is not qualified.
func ExplicitInterfaceQualifierArgumentListEnd(kinds: int[], count: int, lessIndex: int): int {
    depth := 0
    pos := lessIndex
    while pos < count {
        kind := kinds[pos]
        if kind == 100 {
            depth = depth + 1
        } else if kind == 102 {
            depth = depth - 1
            if depth <= 0 {
                return pos + 1
            }
        } else if kind == 112 {
            depth = depth - 2
            if depth <= 0 {
                return pos + 1
            }
        } else if kind == 129 || kind == 130 || kind == 135 || kind == 136 {
            return -1
        }

        pos = pos + 1
    }

    return -1
}

// The token index just past a MEMBER's name, which is more than one token when the name is qualified.
// Every walk that used to write `memberStart + 1` asks this instead, so the two readings of a type's
// body cannot disagree about where a member's name ends.
func ParseDeclarationMemberNameEnd(tokens: ParserDeclarationTokenTable, count: int, memberStart: int): int {
    if memberStart < 0 || memberStart >= count || tokens.Kinds[memberStart] != 0 {
        return memberStart
    }

    qualifiedEnd := ExplicitInterfaceMemberNameEnd(tokens.Kinds, count, memberStart + 1)
    if qualifiedEnd > memberStart + 1 {
        return qualifiedEnd
    }

    return memberStart + 1
}

// The source LENGTH of that name, from its first token through its last.
func ParseDeclarationMemberNameSpanLength(tokens: ParserDeclarationTokenTable, memberStart: int, nameEnd: int): int {
    return tokens.Starts[nameEnd - 1] + tokens.ValueLengths[nameEnd - 1] - tokens.Starts[memberStart]
}

// A MEMBER NAME'S TEXT. A qualified one may have been written with whitespace around its punctuation,
// and a canonical name never contains a space — the same rule a composed TYPE text follows. An
// ordinary one-token name carries no punctuation at all and is returned exactly as written, so
// nothing on the hot path allocates that did not allocate before.
func ParserDeclarationMemberNameText(source: string, start: int, length: int): string {
    if start < 0 || length <= 0 || start + length > source.Length {
        return ""
    }

    i := 0
    while i < length {
        ch := source[start + i]
        if ch == '.' || ch == '<' {
            return ParserDeclarationCanonicalDottedNameText(source, start, length)
        }

        i = i + 1
    }

    return source.Substring(start, length)
}

func ParserDeclarationCanonicalDottedNameText(source: string, start: int, length: int): string {
    if start < 0 || length <= 0 || start + length > source.Length {
        return ""
    }

    builder := new StringBuilder(length)
    i := 0
    while i < length {
        ch := source[start + i]
        if !Char.IsWhiteSpace(ch) {
            builder.Append(ch)
        }
        i = i + 1
    }
    return builder.ToString()
}

// WHICH SETS OF VISIBILITY WORDS A DECLARATION MAY SPELL. One word is always legal; the only legal
// PAIRS are `protected internal` (8|4) and `private protected` (8|2), both of which name an
// accessibility the CLR has a single word for. Every other pair contradicts itself — `public private`
// says two different things about the same member — and is refused.
func ParserDeclarationVisibilityWordsAreLegal(flags: int): bool {
    if flags == 0 || flags == 1 || flags == 2 || flags == 4 || flags == 8 {
        return true
    }

    return flags == 12 || flags == 10
}

func ParserDeclarationMemberModifierKind(kind: int): int {
    if kind == 63 {
        return 2
    }

    if kind == 64 || kind == 65 || kind == 66 || kind == 67 {
        return 1
    }

    // `required` (76) and `init` (77) are MEMBER modifier words, admitted here for the same reason
    // every other word on this row is: the member scan has to step across them before it can read the
    // name. They carry no visibility and no storage decision of their own, so they are kind 3 —
    // ordinary prefix words whose meaning the field/property columns behind this scan decide.
    if kind == 21 || kind == 22 || kind == 58 || kind == 59 || kind == 60 || kind == 61 || kind == 62 || kind == 68 || kind == 76 || kind == 77 || kind == 81 {
        return 3
    }

    return 0
}

func ParserDeclarationMemberModifierFlag(kind: int): int {
    if kind == 22 {
        return 512
    }

    return ModifierFlag(kind)
}

func ParserDeclarationModifierFlagsIncludeReadonly(flags: int): bool {
    return (flags / 512) % 2 == 1
}

func ParserDeclarationModifierFlagsIncludeConst(flags: int): bool {
    return (flags & 1024) != 0
}

// Field metadata currently has one intrinsic attribute surface. Require the exact System-qualified
// CLR identity, accept its suffixed spelling, and allow either omitted or empty argument syntax.
// The parser has no semantic import scope, so an unqualified or foreign name cannot prove that
// identity; a payload or unrelated attribute must also remain ordinary skipped prefix data.
func ParserDeclarationIsExactThreadStaticAttribute(source: string, tokens: ParserDeclarationTokenTable, count: int, openIndex: int): bool {
    if openIndex < 0 || openIndex + 2 >= count || tokens.Kinds[openIndex] != 131 {
        return false
    }

    scan := openIndex + 1
    if scan + 2 < count && tokens.Kinds[scan] == 0 && ColumnarTokenTextEquals(source, tokens, scan, "System") && tokens.Kinds[scan + 1] == 124 && tokens.Kinds[scan + 2] == 0 && (ColumnarTokenTextEquals(source, tokens, scan + 2, "ThreadStatic") || ColumnarTokenTextEquals(source, tokens, scan + 2, "ThreadStaticAttribute")) {
        scan = scan + 3
    } else {
        return false
    }

    if scan + 1 < count && tokens.Kinds[scan] == 127 && tokens.Kinds[scan + 1] == 128 {
        scan = scan + 2
    }

    return scan < count && tokens.Kinds[scan] == 132
}

// MSBuild task inputs use this exact marker on properties. Keep the declaration scanner's
// recognition as narrow as the CLR identity the emitter later binds: a fully-qualified,
// argument-free Microsoft.Build.Framework.RequiredAttribute only. An unqualified name, a foreign
// namespace, or a payload stays ordinary skipped attribute syntax and does not acquire metadata.
func ParserDeclarationIsExactMsBuildRequiredAttribute(source: string, tokens: ParserDeclarationTokenTable, count: int, openIndex: int): bool {
    if openIndex < 0 || openIndex + 6 >= count || tokens.Kinds[openIndex] != 131 {
        return false
    }

    scan := openIndex + 1
    if scan + 6 < count && tokens.Kinds[scan] == 0 && ColumnarTokenTextEquals(source, tokens, scan, "Microsoft") && tokens.Kinds[scan + 1] == 124 && tokens.Kinds[scan + 2] == 0 && ColumnarTokenTextEquals(source, tokens, scan + 2, "Build") && tokens.Kinds[scan + 3] == 124 && tokens.Kinds[scan + 4] == 0 && ColumnarTokenTextEquals(source, tokens, scan + 4, "Framework") && tokens.Kinds[scan + 5] == 124 && tokens.Kinds[scan + 6] == 0 && (ColumnarTokenTextEquals(source, tokens, scan + 6, "Required") || ColumnarTokenTextEquals(source, tokens, scan + 6, "RequiredAttribute")) {
        scan = scan + 7
    } else {
        return false
    }

    if scan + 1 < count && tokens.Kinds[scan] == 127 && tokens.Kinds[scan + 1] == 128 {
        scan = scan + 2
    }

    return scan < count && tokens.Kinds[scan] == 132
}

// MSBuild task outputs use this exact marker on properties. Keep the declaration scanner's
// recognition as narrow as the CLR identity the emitter later binds: a fully-qualified,
// argument-free Microsoft.Build.Framework.OutputAttribute only. An unqualified name, a foreign
// namespace, or a payload stays ordinary skipped attribute syntax and does not acquire metadata.
func ParserDeclarationIsExactMsBuildOutputAttribute(source: string, tokens: ParserDeclarationTokenTable, count: int, openIndex: int): bool {
    if openIndex < 0 || openIndex + 6 >= count || tokens.Kinds[openIndex] != 131 {
        return false
    }

    scan := openIndex + 1
    if scan + 6 < count && tokens.Kinds[scan] == 0 && ColumnarTokenTextEquals(source, tokens, scan, "Microsoft") && tokens.Kinds[scan + 1] == 124 && tokens.Kinds[scan + 2] == 0 && ColumnarTokenTextEquals(source, tokens, scan + 2, "Build") && tokens.Kinds[scan + 3] == 124 && tokens.Kinds[scan + 4] == 0 && ColumnarTokenTextEquals(source, tokens, scan + 4, "Framework") && tokens.Kinds[scan + 5] == 124 && tokens.Kinds[scan + 6] == 0 && (ColumnarTokenTextEquals(source, tokens, scan + 6, "Output") || ColumnarTokenTextEquals(source, tokens, scan + 6, "OutputAttribute")) {
        scan = scan + 7
    } else {
        return false
    }

    if scan + 1 < count && tokens.Kinds[scan] == 127 && tokens.Kinds[scan + 1] == 128 {
        scan = scan + 2
    }

    return scan < count && tokens.Kinds[scan] == 132
}

func ParseMemberModifierPrefixCore(source: string, tokens: ParserDeclarationTokenTable, count: int, pos: int, result: ParserDeclarationResultTable): int {
    if pos < 0 || pos > count || result.Values.Length < 2 {
        return -1
    }

    result.Values[0] = 0
    result.Values[1] = 0
    if result.Values.Length >= 3 {
        result.Values[2] = 0
    }
    if result.Values.Length >= 4 {
        result.Values[3] = 0
    }
    if result.Values.Length >= 5 {
        result.Values[4] = 0
    }
    if result.Values.Length >= 6 {
        result.Values[5] = 0
    }

    while pos < count {
        if tokens.Kinds[pos] == 131 {
            if result.Values.Length >= 4 && ParserDeclarationIsExactThreadStaticAttribute(source, tokens, count, pos) {
                result.Values[3] = 1
            }
            if result.Values.Length >= 5 && ParserDeclarationIsExactMsBuildRequiredAttribute(source, tokens, count, pos) {
                result.Values[4] = 1
            }
            if result.Values.Length >= 6 && ParserDeclarationIsExactMsBuildOutputAttribute(source, tokens, count, pos) {
                result.Values[5] = 1
            }
            bracketDepth := 1
            pos = pos + 1
            while pos < count && bracketDepth > 0 {
                if tokens.Kinds[pos] == 131 {
                    bracketDepth = bracketDepth + 1
                } else if tokens.Kinds[pos] == 132 {
                    bracketDepth = bracketDepth - 1
                }

                pos = pos + 1
            }

            if bracketDepth != 0 {
                return -1
            }

            continue
        }

        modifierKind := ParserDeclarationMemberModifierKind(tokens.Kinds[pos])
        if modifierKind == 0 {
            break
        }

        if result.Values.Length >= 3 {
            flag := ParserDeclarationMemberModifierFlag(tokens.Kinds[pos])
            if flag != 0 {
                result.Values[2] = result.Values[2] | flag
            }
        }

        // A const field has static storage in the source model even though the spelling omits
        // `static`. Keep the existing static marker column authoritative for every downstream
        // field/initializer decision, and carry the Const bit separately in the packed flags.
        if tokens.Kinds[pos] == 21 {
            result.Values[0] = 1
        }

        if modifierKind == 2 {
            if result.Values[0] == 1 {
                return -1
            }

            result.Values[0] = 1
        } else if modifierKind == 1 {
            // THE VISIBILITY WORDS ACCUMULATE INTO A SET, NOT A COUNT. Two of them are a legal
            // spelling — `protected internal` and `private protected`, in either order — and the
            // rest are contradictions. Counting refused all pairs alike, which is why
            // `protected internal Shared: int` declined at parse while the metadata planner beside
            // it already knew what word to emit for it.
            result.Values[1] = result.Values[1] | ParserDeclarationMemberModifierFlag(tokens.Kinds[pos])
            if !ParserDeclarationVisibilityWordsAreLegal(result.Values[1]) {
                return -1
            }
        }

        pos = pos + 1
    }

    return pos
}

// The declaration scan reports `func*` as a 0/1 generator column; the MODIFIER word a generator
// carries is `Modifiers.Generator` (4096, DeclarationEnums.nl). Turning the column into the word is
// a decision about this file's own output, so it is answered here rather than mirrored by a caller.
func ColumnarFunctionModifierFlagsForGenerator(generatorFlag: int): int {
    if generatorFlag == 1 {
        return 4096
    }

    return 0
}

func ParseDeclarationFunctionSignatureEndCore(source: string, tokens: ParserDeclarationTokenTable, count: int, funcIndex: int): int {
    signatureTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    typeStack := new ParserArgumentStack(new int[](count + 1))
    nodes := new ParserNodeTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    children := new ParserChildIndexTable(new int[](count + 1))
    parameters := new ParserFunctionParameterTable(new int[](count + 1), new int[](count + 1), new int[](count + 1))
    typeParams := new ParserFunctionTypeParameterTable(new int[](count + 1), new int[](count + 1))
    whereItems := new ParserFunctionWhereTable(new int[](count + 1), new int[](count + 1), new int[](count + 1))
    signatureResult := new ParserResultTable(new int[](8))
    paramCount := ParseFunctionSignatureCore(signatureTokens, count, funcIndex, typeStack, nodes, children, parameters, typeParams, whereItems, signatureResult)
    if paramCount < 0 {
        return -1
    }

    return signatureResult.Values[6]
}

func ColumnarStructLibraryImportAttributeSpanCore(source: string, tokens: ParserDeclarationTokenTable, memberStart: int, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 2 {
        return 0
    }

    result.Values[0] = -1
    result.Values[1] = -1
    scan := memberStart - 1
    while scan >= 0 && ParserDeclarationMemberModifierKind(tokens.Kinds[scan]) != 0 {
        scan = scan - 1
    }

    if scan < 0 || tokens.Kinds[scan] != 132 {
        return 0
    }

    attributeEnd := tokens.Starts[scan] + tokens.ValueLengths[scan]
    closeIndex := scan
    depth := 1
    scan = scan - 1
    while scan >= 0 {
        if tokens.Kinds[scan] == 132 {
            depth = depth + 1
        } else if tokens.Kinds[scan] == 131 {
            depth = depth - 1
            if depth == 0 {
                attributeStart := tokens.Starts[scan]
                if attributeStart < 0 || attributeEnd < attributeStart || attributeEnd > source.Length {
                    return 0
                }

                attributeText := source.Substring(attributeStart, attributeEnd - attributeStart)
                if attributeText.IndexOf("LibraryImport", StringComparison.Ordinal) >= 0 {
                    result.Values[0] = scan
                    result.Values[1] = closeIndex
                    return 1
                }

                return 0
            }
        }

        scan = scan - 1
    }

    return 0
}

func ColumnarStructMethodHasLibraryImportAttribute(source: string, tokens: ParserDeclarationTokenTable, memberStart: int): bool {
    spanResult := new ParserDeclarationResultTable(new int[](2))
    return ColumnarStructLibraryImportAttributeSpanCore(source, tokens, memberStart, spanResult) == 1
}

func ColumnarTokenTextEquals(source: string, tokens: ParserDeclarationTokenTable, index: int, text: string): bool {
    if index < 0 || index >= tokens.Kinds.Length {
        return false
    }

    if tokens.Starts[index] < 0 || tokens.ValueLengths[index] != text.Length {
        return false
    }

    if tokens.Starts[index] + tokens.ValueLengths[index] > source.Length {
        return false
    }

    return source.Substring(tokens.Starts[index], tokens.ValueLengths[index]) == text
}

func DecodeColumnarAttributeStringToken(source: string, tokens: ParserDeclarationTokenTable, index: int): string {
    if index < 0 || index >= tokens.Kinds.Length || tokens.Kinds[index] != 4 {
        return ""
    }

    start := tokens.Starts[index]
    length := tokens.ValueLengths[index]
    if start < 0 || length <= 0 || start + length > source.Length {
        return ""
    }

    if length >= 2 && source[start] == '"' && source[start + length - 1] == '"' {
        return source.Substring(start + 1, length - 2)
    }

    return source.Substring(start, length)
}

func ParseColumnarNativeImportInfoInto(source: string, tokenKinds: int[], tokenStarts: int[], tokenValueLengths: int[], count: int, memberStart: int, methodName: string, outTexts: string[]): int {
    if outTexts.Length < 2 {
        return -1
    }

    tokens := new ParserDeclarationTokenTable(tokenKinds, tokenStarts, tokenValueLengths)
    spanResult := new ParserDeclarationResultTable(new int[](2))
    if ColumnarStructLibraryImportAttributeSpanCore(source, tokens, memberStart, spanResult) != 1 {
        return -1
    }

    openIndex := spanResult.Values[0]
    closeIndex := spanResult.Values[1]
    if openIndex < 0 || closeIndex <= openIndex || closeIndex >= count {
        return -1
    }

    scan := openIndex + 1
    while scan < closeIndex && !ColumnarTokenTextEquals(source, tokens, scan, "LibraryImport") {
        scan = scan + 1
    }

    if scan >= closeIndex {
        return -1
    }

    scan = scan + 1

    if scan >= closeIndex || tokenKinds[scan] != 127 {
        return -1
    }

    scan = scan + 1

    if scan >= closeIndex || tokenKinds[scan] != 4 {
        return -1
    }

    libraryName := DecodeColumnarAttributeStringToken(source, tokens, scan)
    if libraryName == "" {
        return -1
    }

    entryPointName := methodName
    scan = scan + 1

    if scan < closeIndex && tokenKinds[scan] == 134 {
        scan = scan + 1
        if scan + 2 >= closeIndex || !ColumnarTokenTextEquals(source, tokens, scan, "EntryPoint") || tokenKinds[scan + 1] != 93 || tokenKinds[scan + 2] != 4 {
            return -1
        }

        entryPointName = DecodeColumnarAttributeStringToken(source, tokens, scan + 2)
        if entryPointName == "" {
            return -1
        }

        scan = scan + 3
    }

    if scan >= closeIndex || tokenKinds[scan] != 128 {
        return -1
    }

    outTexts[0] = libraryName
    outTexts[1] = entryPointName
    return 1
}

// The index of the `)` that closes a TUPLE type opened at `open`, or -1 when the group is not a tuple
// type at all. A `(` group is a TUPLE only when it holds a comma at its OWN paren depth: `(int)` is a
// parenthesised type and C# reads it as one too (Roslyn's `ScanTupleType` refuses a one-element group
// for the same reason), and the group may contain nothing but type grammar -- qualified names, nested
// generics, array ranks, nullable suffixes, element labels and nested tuples.
func ScanDeclarationTupleTypeCloseCore(tokens: ParserDeclarationTokenTable, count: int, open: int): int {
    depth := 0
    sawTopLevelComma := 0
    scan := open
    while scan < count {
        kind := tokens.Kinds[scan]
        if kind == 127 {
            depth = depth + 1
        } else if kind == 128 {
            depth = depth - 1
            if depth == 0 {
                if sawTopLevelComma == 0 {
                    return -1
                }

                return scan
            }

            if depth < 0 {
                return -1
            }
        } else if kind == 134 {
            if depth == 1 {
                sawTopLevelComma = 1
            }
        } else if kind != 0 && kind != 124 && kind != 131 && kind != 132 && kind != 115 && kind != 100 && kind != 102 && kind != 112 && kind != 122 {
            return -1
        }

        scan = scan + 1
    }

    return -1
}

// A TYPE AS WRITTEN IN A DECLARED POSITION, as a source span. A TUPLE type is one of the forms it
// reads: the kernel used to require the first token to be an identifier, which is why a field or a
// property declared `Pair: (Item: string, Count: int)` declined the WHOLE enclosing type at
// `parse.struct` while the same type on a local, a parameter or a return read fine. The tuple group
// is scanned by the shared rule above and then falls into the same suffix walk every other type
// takes, so `(int, int)?` and `(int, int)[]` read here exactly as they read anywhere else.
func ParseDeclarationTypeSpanCore(tokens: ParserDeclarationTokenTable, count: int, pos: int, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 2 || pos < 0 || pos >= count {
        return -1
    }

    typeStart := tokens.Starts[pos]
    typeEnd := 0

    if tokens.Kinds[pos] == 127 {
        tupleClose := ScanDeclarationTupleTypeCloseCore(tokens, count, pos)
        if tupleClose < 0 {
            return -1
        }

        typeEnd = tokens.Starts[tupleClose] + tokens.ValueLengths[tupleClose]
        pos = tupleClose + 1
        return ParseDeclarationTypeSuffixSpanCore(tokens, count, pos, typeStart, typeEnd, result)
    }

    if tokens.Kinds[pos] != 0 {
        return -1
    }

    typeEnd = tokens.Starts[pos] + tokens.ValueLengths[pos]
    pos = pos + 1

    while pos + 1 < count && tokens.Kinds[pos] == 124 && tokens.Kinds[pos + 1] == 0 {
        typeEnd = tokens.Starts[pos + 1] + tokens.ValueLengths[pos + 1]
        pos = pos + 2
    }

    if pos < count && tokens.Kinds[pos] == 100 {
        gdepth := 0
        parenDepth := 0
        gdone := 0
        gprevIdent := 0
        while pos < count && gdone == 0 {
            gk := tokens.Kinds[pos]
            if gk == 100 {
                gdepth = gdepth + 1
                gprevIdent = 0
            } else if gk == 102 {
                gdepth = gdepth - 1
                if gdepth == 0 && parenDepth != 0 {
                    return -1
                }

                if gdepth == 0 {
                    gdone = 1
                }

                gprevIdent = 0
            } else if gk == 112 {
                gdepth = gdepth - 2
                if gdepth == 0 && parenDepth != 0 {
                    return -1
                }

                if gdepth == 0 {
                    gdone = 1
                }

                gprevIdent = 0
            } else if gk == 127 {
                parenDepth = parenDepth + 1
                gprevIdent = 0
            } else if gk == 128 {
                parenDepth = parenDepth - 1
                if parenDepth < 0 {
                    return -1
                }

                gprevIdent = 1
            } else if gk == 0 {
                if gprevIdent == 1 {
                    return -1
                }

                gprevIdent = 1
            } else if gk == 131 || gk == 132 || gk == 115 {
                gprevIdent = gprevIdent
            } else if gk == 122 && parenDepth > 0 {
                gprevIdent = 0
            } else if gk == 134 || gk == 124 {
                gprevIdent = 0
            } else {
                return -1
            }

            if gdepth < 0 {
                return -1
            }

            typeEnd = tokens.Starts[pos] + tokens.ValueLengths[pos]
            pos = pos + 1
        }

        if gdone == 0 {
            return -1
        }

        if parenDepth != 0 {
            return -1
        }
    }

    return ParseDeclarationTypeSuffixSpanCore(tokens, count, pos, typeStart, typeEnd, result)
}

// The `[]` / `?[]` / `?` suffixes a written type may carry, shared by every head form above.
func ParseDeclarationTypeSuffixSpanCore(tokens: ParserDeclarationTokenTable, count: int, pos: int, typeStart: int, typeEnd: int, result: ParserDeclarationResultTable): int {
    scanPos := pos
    scanEnd := typeEnd
    suffixDone := 0
    while suffixDone == 0 && scanPos < count {
        if scanPos + 1 < count && tokens.Kinds[scanPos] == 131 && tokens.Kinds[scanPos + 1] == 132 {
            scanEnd = tokens.Starts[scanPos + 1] + tokens.ValueLengths[scanPos + 1]
            scanPos = scanPos + 2
        } else if scanPos + 1 < count && tokens.Kinds[scanPos] == 119 && tokens.Kinds[scanPos + 1] == 132 {
            scanEnd = tokens.Starts[scanPos + 1] + tokens.ValueLengths[scanPos + 1]
            scanPos = scanPos + 2
        } else if tokens.Kinds[scanPos] == 115 {
            scanEnd = tokens.Starts[scanPos] + tokens.ValueLengths[scanPos]
            scanPos = scanPos + 1
        } else {
            suffixDone = 1
        }
    }

    result.Values[0] = typeStart
    result.Values[1] = scanEnd - typeStart
    return scanPos
}

func ParseDeclarationSimpleInitializerEndCore(tokens: ParserDeclarationTokenTable, count: int, pos: int, typeResult: ParserDeclarationResultTable): int {
    if pos < 0 || pos >= count {
        return -1
    }

    kind := tokens.Kinds[pos]
    if ParseDeclarationSimpleInitializerTokenIsLiteral(kind) {
        return pos + 1
    }

    if kind == 0 {
        pos = pos + 1
        dotCount := 0
        while pos + 1 < count && tokens.Kinds[pos] == 124 && tokens.Kinds[pos + 1] == 0 {
            dotCount = dotCount + 1
            pos = pos + 2
        }

        if dotCount > 0 {
            return pos
        }

        return -1
    }

    if kind != 41 {
        return -1
    }

    pos = pos + 1
    pos = ParseDeclarationTypeSpanCore(tokens, count, pos, typeResult)
    if pos < 0 || pos >= count || tokens.Kinds[pos] != 127 {
        return -1
    }

    depth := 0
    done := 0
    while pos < count && done == 0 {
        if tokens.Kinds[pos] == 127 {
            depth = depth + 1
        } else if tokens.Kinds[pos] == 128 {
            depth = depth - 1
            if depth == 0 {
                done = 1
            }
        }

        pos = pos + 1
    }

    if done == 0 {
        return -1
    }

    return pos
}

func ParseDeclarationInitializerExpressionEndCore(source: string, tokens: ParserDeclarationTokenTable, count: int, pos: int): int {
    if pos < 0 || pos >= count {
        return -1
    }

    expressionTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    argStack := new ParserArgumentStack(new int[](count + 1))
    nodes := new ParserExpressionNodeTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    children := new ParserChildIndexTable(new int[](count + 1))
    st := new ParserState(pos, 0, 0, 0, 0, 0)
    valueRoot := ParseLambdaOrAssignmentExpressionNode(expressionTokens, count, st, argStack, nodes, children, 0)
    if valueRoot < 0 || st.Pos <= pos {
        return -1
    }

    return st.Pos
}

func ParseDeclarationSimpleInitializerTokenIsLiteral(kind: int): bool {
    return kind == 46 || kind == 44 || kind == 45 || kind == 1 || kind == 2 || kind == 3 || kind == 4
}

func ParserDeclarationFieldInitializerExpressionKind(): int {
    return 1001
}

func PrimaryConstructorParameterIndexOf(source: string, parameters: PrimaryConstructorParameterTable, parameterCount: int, nameStart: int, nameLength: int): int {
    i := 0
    while i < parameterCount {
        if ParserDeclarationSourceSpansEqual(source, parameters.NameStarts[i], parameters.NameLengths[i], nameStart, nameLength) {
            return i
        }

        i = i + 1
    }

    return -1
}

func ParserDeclarationDefaultMemberAccessKind(): int {
    return 1000
}

func ParserDeclarationDefaultDottedNameSupported(tokens: ParserDeclarationTokenTable, startIndex: int, endIndex: int): bool {
    if startIndex < 0 || endIndex <= startIndex || endIndex > tokens.Kinds.Length {
        return false
    }

    identifierCount := 0
    dotCount := 0
    expectIdentifier := true
    i := startIndex
    while i < endIndex {
        kind := tokens.Kinds[i]
        if expectIdentifier {
            if kind != 0 {
                return false
            }

            identifierCount = identifierCount + 1
            expectIdentifier = false
        } else {
            if kind != 124 {
                return false
            }

            dotCount = dotCount + 1
            expectIdentifier = true
        }

        i = i + 1
    }

    return !expectIdentifier && identifierCount >= 2 && dotCount >= 1
}

// THE `[...]` GROUPS WRITTEN BEFORE A PRIMARY CONSTRUCTOR PARAMETER, skipped so the parameter itself
// parses. The group is not read here: `ColumnarSourceAttributes.ReadParameters` scans back from the
// parameter's NAME token, exactly the way it does for a method's parameters, so there is one reader
// for an attribute on a parameter rather than two. -1 means the brackets never closed.
func SkipPrimaryConstructorParameterAttributeGroups(tokens: ParserDeclarationTokenTable, count: int, start: int): int {
    pos := start
    while pos < count && tokens.Kinds[pos] == 131 {
        depth := 0
        closed := 0
        while pos < count && closed == 0 {
            if tokens.Kinds[pos] == 131 {
                depth = depth + 1
            } else if tokens.Kinds[pos] == 132 {
                depth = depth - 1
                if depth == 0 {
                    closed = 1
                }
            }

            pos = pos + 1
        }

        if closed == 0 {
            return -1
        }
    }

    return pos
}

func ParsePrimaryConstructorParameterSpansCore(_source: string, tokens: ParserDeclarationTokenTable, count: int, leftParenIndex: int, parameters: PrimaryConstructorParameterTable, result: ParserDeclarationResultTable): int {
    if result.Values.Length < 1 || leftParenIndex < 0 || leftParenIndex >= count || tokens.Kinds[leftParenIndex] != 127 {
        return -1
    }

    pos := leftParenIndex + 1
    paramCount := 0
    foundDefault := 0
    typeResult := new ParserDeclarationResultTable(new int[](2))

    while pos < count && tokens.Kinds[pos] != 128 {
        if paramCount >= parameters.NameStarts.Length || paramCount >= parameters.TypeStarts.Length || paramCount >= parameters.DefaultKinds.Length {
            return -1
        }

        pos = SkipPrimaryConstructorParameterAttributeGroups(tokens, count, pos)
        if pos < 0 || pos >= count {
            return -1
        }

        if tokens.Kinds[pos] != 0 {
            return -1
        }

        parameters.NameStarts[paramCount] = tokens.Starts[pos]
        parameters.NameLengths[paramCount] = tokens.ValueLengths[pos]
        pos = pos + 1

        if pos >= count || tokens.Kinds[pos] != 122 {
            return -1
        }

        pos = pos + 1

        pos = ParseDeclarationTypeSpanCore(tokens, count, pos, typeResult)
        if pos < 0 {
            return -1
        }

        parameters.TypeStarts[paramCount] = typeResult.Values[0]
        parameters.TypeLengths[paramCount] = typeResult.Values[1]
        parameters.DefaultKinds[paramCount] = -1
        parameters.DefaultStarts[paramCount] = -1
        parameters.DefaultLengths[paramCount] = 0

        if pos < count && tokens.Kinds[pos] == 93 {
            foundDefault = 1
            pos = pos + 1
            if pos >= count {
                return -1
            }

            defaultKind := tokens.Kinds[pos]
            defaultStart := tokens.Starts[pos]
            defaultLength := tokens.ValueLengths[pos]
            defaultTokenStart := pos
            defaultTokenCount := 0
            defaultDepth := 0
            keepSkipping := true
            while keepSkipping && pos < count {
                k := tokens.Kinds[pos]
                if k == 127 || k == 131 || k == 129 {
                    defaultDepth = defaultDepth + 1
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                } else if k == 128 || k == 132 || k == 130 {
                    if defaultDepth == 0 {
                        keepSkipping = false
                    } else {
                        defaultDepth = defaultDepth - 1
                        defaultTokenCount = defaultTokenCount + 1
                        pos = pos + 1
                    }
                } else if k == 134 && defaultDepth == 0 {
                    keepSkipping = false
                } else {
                    defaultTokenCount = defaultTokenCount + 1
                    pos = pos + 1
                }
            }

            if defaultTokenCount == 1 && (defaultKind == 46 || defaultKind == 44 || defaultKind == 45 || defaultKind == 1 || defaultKind == 4) {
                defaultLength = tokens.ValueLengths[defaultTokenStart]
            } else if ParserDeclarationDefaultDottedNameSupported(tokens, defaultTokenStart, pos) {
                defaultKind = ParserDeclarationDefaultMemberAccessKind()
                defaultLength = tokens.Starts[pos - 1] + tokens.ValueLengths[pos - 1] - defaultStart
            } else {
                return -1
            }

            parameters.DefaultKinds[paramCount] = defaultKind
            parameters.DefaultStarts[paramCount] = defaultStart
            parameters.DefaultLengths[paramCount] = defaultLength
        } else if foundDefault == 1 {
            return -1
        }

        paramCount = paramCount + 1

        if pos >= count || (tokens.Kinds[pos] != 134 && tokens.Kinds[pos] != 128) {
            return -1
        }

        if tokens.Kinds[pos] == 134 {
            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 128 {
        return -1
    }

    result.Values[0] = pos + 1
    return paramCount
}

func StructDeclarationFieldIndexOf(source: string, decl: StructDeclarationTable, fieldCount: int, nameStart: int, nameLength: int): int {
    i := 0
    while i < fieldCount {
        if ParserDeclarationSourceSpansEqual(source, decl.FieldNameStarts[i], decl.FieldNameLengths[i], nameStart, nameLength) {
            return i
        }

        i = i + 1
    }

    return -1
}

func ParseDeclarationNestedTypeDeclarationKind(kind: int): bool {
    return kind == 8 || kind == 9 || kind == 10 || kind == 12 || kind == 13 || kind == 14
}

func ParseDeclarationSkipDeclarationBlockCore(tokens: ParserDeclarationTokenTable, count: int, start: int): int {
    pos := start
    while pos < count && tokens.Kinds[pos] != 129 {
        pos = pos + 1
    }

    if pos >= count || tokens.Kinds[pos] != 129 {
        return -1
    }

    depth := 0
    done := 0
    while pos < count && done == 0 {
        if tokens.Kinds[pos] == 129 {
            depth = depth + 1
        } else if tokens.Kinds[pos] == 130 {
            depth = depth - 1
            if depth == 0 {
                done = 1
            }
        }

        pos = pos + 1
    }

    if done == 0 {
        return -1
    }

    return pos
}

// THE FIELD WORD, PACKED FROM ONE MEMBER'S MODIFIER PREFIX. Bit 0 `static`, bit 1 `readonly`,
// bit 2 `private`, bit 3 the exact System.ThreadStatic intrinsic, bit 4 `const`, bit 5 `protected`,
// bit 6 `internal`, bit 7 `public`. (Bit 8 is set by the EVENT arm, which is the one member that is a
// field without having been written as one; it is not a modifier and so is not packed here.)
//
// `private` had a bit of its own from the start and the other three visibility words had none, so
// `protected Seed: int` reached the field planner indistinguishable from an unmarked field and was
// emitted PUBLIC while `protected func` beside it was emitted `family`. Each word has a bit now and
// the planner reads the set.
func ParseDeclarationMemberFieldModifierWord(memberModifiers: ParserDeclarationResultTable): int {
    fieldModifierFlags := memberModifiers.Values[0]
    if ParserDeclarationModifierFlagsIncludeReadonly(memberModifiers.Values[2]) {
        fieldModifierFlags = fieldModifierFlags + 2
    }
    if (memberModifiers.Values[2] & 2) != 0 {
        fieldModifierFlags = fieldModifierFlags + 4
    }
    if memberModifiers.Values[3] == 1 {
        fieldModifierFlags = fieldModifierFlags + 8
    }
    if (memberModifiers.Values[2] & 1024) != 0 {
        fieldModifierFlags = fieldModifierFlags + 16
    }
    if (memberModifiers.Values[2] & 8) != 0 {
        fieldModifierFlags = fieldModifierFlags + 32
    }
    if (memberModifiers.Values[2] & 4) != 0 {
        fieldModifierFlags = fieldModifierFlags + 64
    }
    if (memberModifiers.Values[2] & 1) != 0 {
        fieldModifierFlags = fieldModifierFlags + 128
    }
    // Bits 9, 10 and 11 — the three inheritance words. A plain FIELD can never carry them (a CLR field
    // has no slot), and the analyzer says so with NL311; an EVENT can, because its accessors are
    // methods and methods have slots. The bits are packed for every field row all the same, because
    // the word is one word: the reader decides what a bit MEANS for the row it is on.
    if (memberModifiers.Values[2] & 32) != 0 {
        fieldModifierFlags = fieldModifierFlags + 512
    }
    if (memberModifiers.Values[2] & 64) != 0 {
        fieldModifierFlags = fieldModifierFlags + 1024
    }
    if (memberModifiers.Values[2] & 65536) != 0 {
        fieldModifierFlags = fieldModifierFlags + 2048
    }
    // Bits 12 and 13 — `required` and `init`. `required` keeps the row a FIELD and adds the metadata
    // that makes a caller's object initializer name it; `init` turns the row into an init-only
    // AUTO-PROPERTY, because the promise it makes ("settable in an object initializer, nowhere else")
    // is spelled in the CLR as a setter carrying `modreq(IsExternalInit)`, and a field has no setter.
    if (memberModifiers.Values[2] & 8192) != 0 {
        fieldModifierFlags = fieldModifierFlags + 4096
    }
    if (memberModifiers.Values[2] & 16384) != 0 {
        fieldModifierFlags = fieldModifierFlags + 8192
    }

    return fieldModifierFlags
}

// The `required` / `init` words as the PROPERTY column's own two bits (8 and 16). A property row
// packs its prefix differently from a field row — its word is small and its meanings are its own —
// so the translation from the shared modifier word lives beside the packing that uses it.
func ParseDeclarationMemberPropertyModifierBits(memberModifiers: ParserDeclarationResultTable): int {
    bits := 0
    if (memberModifiers.Values[2] & 8192) != 0 {
        bits = bits | 8
    }
    if (memberModifiers.Values[2] & 16384) != 0 {
        bits = bits | 16
    }

    return bits
}
