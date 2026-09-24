import NSharpLang.Compiler.Columnar


// STRUCT AND UNION DECLARATION BODIES, and the constructor-chain info read out of them.
//
// Formerly part of `CompilerServices/ColumnarParserKernels.nl`, a 17,120-line file whose first
// 2,061 lines were fifteen files mechanically concatenated behind `// ---- X.nl ----` markers --
// a bootstrap artifact of the Dogfood assembly, not a design. Split back by concern; every line
// below is a verbatim move.
func ParseStructDeclarationCore(source: string, tokens: ParserDeclarationTokenTable, count: int, structIndex: int, decl: StructDeclarationTable, result: ParserDeclarationResultTable): int {
    pos := structIndex
    if pos >= count || (tokens.Kinds[pos] != 9 && tokens.Kinds[pos] != 13 && tokens.Kinds[pos] != 8) {
        return -1
    }

    // `record struct Name` — the Struct token is the record-struct TAIL of the Record head.
    if tokens.Kinds[pos] == 13 && pos + 1 < count && tokens.Kinds[pos + 1] == 9 {
        pos = pos + 1
    }

    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }

    result.Values[0] = tokens.Starts[pos]
    result.Values[1] = tokens.ValueLengths[pos]
    pos = pos + 1

    // Optional generic TYPE-PARAMETER list `<T, U>` after the type name (Less 100, Identifier 0,
    // Comma 134, Greater 102): bare comma-separated Identifiers only, the same shape as a generic
    // FUNCTION signature's list. A declaration's list cannot nest, so no `>>` splitting is needed.
    // An inline constraint (`<T: Base>`), an empty list, or any other form returns -1 (the host
    // declines to the N# backend path). Name spans go to outTypeParamStarts/Lengths; the count to
    // outResult[7] (0 with no `<`).
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
                // A consumed comma must be FOLLOWED by another parameter name — a trailing comma
                // (`<T,>`) is a production-parser error (adversarial-review finding: the loop's
                // `!= 102` condition would otherwise exit cleanly and ACCEPT what the pipeline rejects).
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

    result.Values[7] = typeParamCount

    primaryParameters := new PrimaryConstructorParameterTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    primaryResult := new ParserDeclarationResultTable(new int[](1))
    primaryCtorParamCount := 0
    primaryAssignedFlags := new int[](count + 1)
    if pos < count && tokens.Kinds[pos] == 127 {
        primaryCtorParamCount = ParsePrimaryConstructorParameterSpansCore(source, tokens, count, pos, primaryParameters, primaryResult)
        if primaryCtorParamCount < 0 {
            return -1
        }

        pos = primaryResult.Values[0]
    }

    if result.Values.Length > 9 {
        result.Values[9] = primaryCtorParamCount
    }

    // Optional BASE / INTERFACE LIST: `class D: Base, IFace {` or `struct S: IFace<T> {` — a `:` (122)
    // after the type name followed by one or more comma-separated type references. The host resolves names
    // against type registries and decides which one, if any, is a class base versus implemented interface.
    result.Values[5] = 0
    result.Values[6] = 0
    baseTypeResult := new ParserDeclarationResultTable(new int[](2))
    baseNameCount := 0
    if pos < count && tokens.Kinds[pos] == 122 {
        pos = pos + 1
        while true {
            typeEnd := ParseDeclarationTypeSpanCore(tokens, count, pos, baseTypeResult)
            if typeEnd < 0 {
                return -1
            }

            decl.BaseNameStarts[baseNameCount] = baseTypeResult.Values[0]
            decl.BaseNameLengths[baseNameCount] = baseTypeResult.Values[1]
            if baseNameCount == 0 {
                result.Values[5] = baseTypeResult.Values[0]
                result.Values[6] = baseTypeResult.Values[1]
            }

            baseNameCount = baseNameCount + 1
            pos = typeEnd

            if pos < count && tokens.Kinds[pos] == 134 {
                pos = pos + 1
                continue
            }

            break
        }
    }

    result.Values[8] = baseNameCount

    // Generic CONSTRAINTS `where T: …`, between the base/interface list and the body — the position the
    // source puts them in, and the reason the gate below used to refuse the whole declaration.
    whereNext := pos
    whereItemCount := ParseDeclarationWhereClausesCore(tokens, count, pos, decl.Where, out whereNext)
    if whereItemCount < 0 {
        return -1
    }

    pos = whereNext
    if result.Values.Length > 10 {
        result.Values[10] = whereItemCount
    }

    if pos >= count || tokens.Kinds[pos] != 129 {
        return -1
    }

    pos = pos + 1

    // THE BODY IS READ TWICE, AND A MEMBER MAY BE WRITTEN ANYWHERE IN IT.
    //
    // The first pass records the STORAGE members — fields, properties and field-like events — and
    // skips over everything else; the second records the METHODS and CONSTRUCTORS and skips over the
    // storage. It used to be one pass with a section boundary: the field scan STOPPED at the first
    // `func` / conversion operator / constructor, and the member scan behind it refused anything that
    // was not one of those. So `field, func, field` — an entirely ordinary way to group a type's
    // members around the method that uses them — declined the WHOLE declaration at `parse.struct`,
    // reported at the class header with nothing said about the member that caused it, and the same
    // rule refused an `event` written after a method.
    //
    // TWO PASSES RATHER THAN ONE, because the synthesized instance constructor has to be recorded
    // BEFORE any written one and whether it is needed is not known until every field initializer has
    // been seen. Field order is declaration order in both readings, which is what a sequential-layout
    // struct depends on.
    //
    // A field is `id : type` (a `:` after the name), so an `id (` is unambiguously a constructor. A
    // PROPERTY `id : type { get {…} [set {…}] }` — an `id : type` followed by `{` (129) — is recorded
    // (its name token index in outPropIndices) and its `{ … }` block skipped; the host parses the
    // accessor bodies. (A field is just `id : type`; the trailing `{` disambiguates a property from a
    // field.)
    bodyStart := pos
    fieldCount := 0
    propCount := 0
    memberModifierValues := new int[](6)
    memberModifiers := new ParserDeclarationResultTable(memberModifierValues)
    fieldTypeResult := new ParserDeclarationResultTable(new int[](2))
    initializerTypeResult := new ParserDeclarationResultTable(new int[](2))
    hasInstanceInitializer := 0
    while pos < count && tokens.Kinds[pos] != 130 {
        memberStart := ParseMemberModifierPrefixCore(source, tokens, count, pos, memberModifiers)
        if memberStart < 0 || memberStart >= count {
            return -1
        }

        if tokens.Kinds[memberStart] == 7 || tokens.Kinds[memberStart] == 85 || tokens.Kinds[memberStart] == 86 {
            // A METHOD OR CONVERSION OPERATOR, SKIPPED. The second pass records it and decides
            // whether a body-less signature is a legal `abstract` or native-import declaration; this
            // pass only has to step past it.
            methodSignatureEnd := ParseDeclarationFunctionSignatureEndCore(source, tokens, count, memberStart)
            if methodSignatureEnd < 0 || methodSignatureEnd >= count {
                return -1
            }

            if tokens.Kinds[methodSignatureEnd] != 129 && tokens.Kinds[methodSignatureEnd] != 120 {
                pos = methodSignatureEnd
            } else {
                pos = ParseDeclarationMemberBodyEndCore(source, tokens, count, methodSignatureEnd)
                if pos < 0 {
                    return -1
                }
            }
        } else if tokens.Kinds[memberStart] == 0 && memberStart + 1 < count && tokens.Kinds[memberStart + 1] == 127 {
            pos = ParseDeclarationMemberBodyEndCore(source, tokens, count, memberStart + 1)
            if pos < 0 {
                return -1
            }
        } else if ParseDeclarationNestedTypeDeclarationKind(tokens.Kinds[memberStart]) {
            pos = ParseDeclarationSkipDeclarationBlockCore(tokens, count, memberStart)
            if pos < 0 {
                return -1
            }
        } else if tokens.Kinds[memberStart] == 0 && memberStart + 3 < count && tokens.Kinds[memberStart + 1] == 122 && tokens.Kinds[memberStart + 2] == 0 && tokens.Kinds[memberStart + 3] == 129 {
            decl.PropIndices[propCount] = memberStart
            decl.PropStaticFlags[propCount] = memberModifiers.Values[0] | (memberModifiers.Values[4] * 2) | (memberModifiers.Values[5] * 4) | ParseDeclarationMemberPropertyModifierBits(memberModifiers)
            propCount = propCount + 1
            pos = memberStart + 3

            pdepth := 0
            pdone := 0
            while pos < count && pdone == 0 {
                if tokens.Kinds[pos] == 129 {
                    pdepth = pdepth + 1
                } else if tokens.Kinds[pos] == 130 {
                    pdepth = pdepth - 1
                    if pdepth == 0 {
                        pdone = 1
                    }
                }

                pos = pos + 1
            }

            if pdone == 0 {
                return -1
            }
        } else if tokens.Kinds[memberStart] == 0 && memberStart + 2 < count && tokens.Kinds[memberStart + 1] == 0 && tokens.Kinds[memberStart + 2] == 122 && ParserDeclarationTokenTextEquals(source, tokens.Starts[memberStart], tokens.ValueLengths[memberStart], "event") {

            // `event <Name>: <DelegateType>` — C#'s FIELD-LIKE event, recorded as the FIELD it is.
            // The declaration synthesizes one private delegate field carrying the event's own name
            // plus two accessors, so the row that reaches the emitter is a field row with the event
            // bit set; the accessors, the `EventInfo` and the private storage are all decided from
            // that one bit and the visibility word beside it.
            //
            // `event` IS CONTEXTUAL. A field spelled `event` is `event: Type` — a `:` where this arm
            // requires a NAME — so the two shapes cannot be confused, and `event` keeps working as an
            // ordinary identifier everywhere else in the language.
            decl.FieldNameStarts[fieldCount] = tokens.Starts[memberStart + 1]
            decl.FieldNameLengths[fieldCount] = tokens.ValueLengths[memberStart + 1]
            pos = memberStart + 3

            pos = ParseDeclarationTypeSpanCore(tokens, count, pos, fieldTypeResult)
            if pos < 0 {
                return -1
            }

            decl.FieldTypeStarts[fieldCount] = fieldTypeResult.Values[0]
            decl.FieldTypeLengths[fieldCount] = fieldTypeResult.Values[1]
            decl.FieldStaticFlags[fieldCount] = ParseDeclarationMemberFieldModifierWord(memberModifiers) | 256
            decl.FieldInitKinds[fieldCount] = -1
            decl.FieldInitStarts[fieldCount] = -1
            decl.FieldInitLengths[fieldCount] = 0
            decl.FieldInitTokens[fieldCount] = -1
            decl.FieldDeclTokens[fieldCount] = memberStart + 1
            fieldCount = fieldCount + 1
        } else {
            if tokens.Kinds[memberStart] != 0 {
                return -1
            }

            // A VALUE MEMBER'S NAME MAY BE QUALIFIED — `IReadOnlyCollection<string>.Count: int => …` is
            // an explicit interface implementation of a value member — so the `:` is looked for past
            // the whole name rather than one token in.
            memberNameEnd := ParseDeclarationMemberNameEnd(tokens, count, memberStart)
            decl.FieldNameStarts[fieldCount] = tokens.Starts[memberStart]
            decl.FieldNameLengths[fieldCount] = ParseDeclarationMemberNameSpanLength(tokens, memberStart, memberNameEnd)
            pos = memberNameEnd

            if pos >= count || tokens.Kinds[pos] != 122 {
                return -1
            }

            pos = pos + 1

            pos = ParseDeclarationTypeSpanCore(tokens, count, pos, fieldTypeResult)
            if pos < 0 {
                return -1
            }

            decl.FieldTypeStarts[fieldCount] = fieldTypeResult.Values[0]
            decl.FieldTypeLengths[fieldCount] = fieldTypeResult.Values[1]
            decl.FieldStaticFlags[fieldCount] = ParseDeclarationMemberFieldModifierWord(memberModifiers)
            decl.FieldInitKinds[fieldCount] = -1
            decl.FieldInitStarts[fieldCount] = -1
            decl.FieldInitLengths[fieldCount] = 0
            decl.FieldInitTokens[fieldCount] = -1
            decl.FieldDeclTokens[fieldCount] = memberStart

            if pos < count && tokens.Kinds[pos] == 129 {
                decl.PropIndices[propCount] = memberStart
                decl.PropStaticFlags[propCount] = memberModifiers.Values[0] | (memberModifiers.Values[4] * 2) | (memberModifiers.Values[5] * 4) | ParseDeclarationMemberPropertyModifierBits(memberModifiers)
                propCount = propCount + 1

                pdepth := 0
                pdone := 0
                while pos < count && pdone == 0 {
                    if tokens.Kinds[pos] == 129 {
                        pdepth = pdepth + 1
                    } else if tokens.Kinds[pos] == 130 {
                        pdepth = pdepth - 1
                        if pdepth == 0 {
                            pdone = 1
                        }
                    }

                    pos = pos + 1
                }

                if pdone == 0 {
                    return -1
                }

                continue
            }

            if pos < count && tokens.Kinds[pos] == 120 {
                decl.PropIndices[propCount] = memberStart
                decl.PropStaticFlags[propCount] = memberModifiers.Values[0] | (memberModifiers.Values[4] * 2) | (memberModifiers.Values[5] * 4) | ParseDeclarationMemberPropertyModifierBits(memberModifiers)
                propCount = propCount + 1
                pos = ParseDeclarationExpressionBodyEndCore(source, tokens, count, pos)
                if pos < 0 {
                    return -1
                }

                continue
            }

            if pos < count && tokens.Kinds[pos] == 93 {
                pos = pos + 1
                if pos >= count {
                    return -1
                }

                initTokenIndex := pos
                initKind := tokens.Kinds[pos]
                initStart := tokens.Starts[pos]
                initLength := tokens.ValueLengths[pos]
                // A FIELD INITIALIZER IS AN ORDINARY EXPRESSION. Read its full extent with the
                // expression parser, and keep a "simple" classification (a lone literal, a dotted
                // name, or `new T(...)`) only when that simple form covers the WHOLE initializer:
                // `3 + 4` opens on a literal token but is not one, and reading only the literal
                // used to strand `+ 4` in the member scan and decline the entire declaration.
                initEnd := ParseDeclarationInitializerExpressionEndCore(source, tokens, count, pos)
                if initEnd < 0 {
                    return -1
                }

                if ParseDeclarationSimpleInitializerEndCore(tokens, count, pos, initializerTypeResult) != initEnd {
                    initKind = ParserDeclarationFieldInitializerExpressionKind()
                }

                // Only a BARE primary-constructor parameter name makes the declared field that
                // parameter's storage; `param + 1` is an expression that happens to read it.
                if initKind == 0 && initEnd == pos + 1 {
                    primaryParamIndex := PrimaryConstructorParameterIndexOf(source, primaryParameters, primaryCtorParamCount, initStart, initLength)
                    if primaryParamIndex >= 0 {
                        primaryAssignedFlags[primaryParamIndex] = 1
                    }
                }

                initLength = tokens.Starts[initEnd - 1] + tokens.ValueLengths[initEnd - 1] - initStart
                pos = initEnd - 1

                if memberModifiers.Values[0] == 1 {
                    decl.FieldInitKinds[fieldCount] = initKind
                    decl.FieldInitStarts[fieldCount] = initStart
                    decl.FieldInitLengths[fieldCount] = initLength
                    decl.FieldInitTokens[fieldCount] = initTokenIndex
                } else {
                    hasInstanceInitializer = 1
                }

                pos = pos + 1
            }

            fieldCount = fieldCount + 1
        }
    }

    if primaryCtorParamCount > 0 {
        paramIndex := 0
        while paramIndex < primaryCtorParamCount {
            if primaryAssignedFlags[paramIndex] == 0 && StructDeclarationFieldIndexOf(source, decl, fieldCount, primaryParameters.NameStarts[paramIndex], primaryParameters.NameLengths[paramIndex]) < 0 {
                decl.FieldNameStarts[fieldCount] = primaryParameters.NameStarts[paramIndex]
                decl.FieldNameLengths[fieldCount] = primaryParameters.NameLengths[paramIndex]
                decl.FieldTypeStarts[fieldCount] = primaryParameters.TypeStarts[paramIndex]
                decl.FieldTypeLengths[fieldCount] = primaryParameters.TypeLengths[paramIndex]
                decl.FieldStaticFlags[fieldCount] = 0
                decl.FieldInitKinds[fieldCount] = -1
                decl.FieldInitStarts[fieldCount] = -1
                decl.FieldInitLengths[fieldCount] = 0
                decl.FieldInitTokens[fieldCount] = -1
                decl.FieldDeclTokens[fieldCount] = -1
                fieldCount = fieldCount + 1
            }

            paramIndex = paramIndex + 1
        }
    }

    // THE SECOND PASS: METHODS (`func name(...): ret { body }`) and CONSTRUCTORS (`constructor(...) {
    // body }` — lexed as an Identifier followed by `(`). DELIMIT each: record its keyword/identifier token index
    // (outMethodFuncIndices for a method, outCtorIndices for a constructor), then skip its signature to the body `{`
    // and scan to the matching `}` (balanced). The host parses the signatures/bodies via the existing function
    // kernels at the recorded indices (a constructor's `(params)` and `{body}` parse via the same signature/statement
    // kernels — it has no name token and no `: ret`, so the signature kernel yields name=-1, returnRoot=-1; a
    // constructor INITIALIZER `: this(...)`/`base(...)` is skipped by the signature kernel and parsed separately
    // via ParseConstructorChainInfoCore, with the composed constructor core verifying the identifier text.
    // A member with no `{` body declines unless it is a static LibraryImport method; those carry a native-import
    // modifier bit and materialize as P/Invoke methods without managed bodies.
    //
    // It reads the body from the start again, because a method may be written before, between or
    // after the storage members the first pass recorded, and skips whatever that pass owns.
    methodCount := 0
    ctorCount := 0
    syntheticCtorNeeded := primaryCtorParamCount > 0 || hasInstanceInitializer == 1
    if syntheticCtorNeeded {
        decl.CtorIndices[ctorCount] = structIndex
        ctorCount = ctorCount + 1
    }

    pos = bodyStart
    while pos < count && tokens.Kinds[pos] != 130 {
        memberStart := ParseMemberModifierPrefixCore(source, tokens, count, pos, memberModifiers)
        if memberStart < 0 || memberStart >= count {
            return -1
        }

        if tokens.Kinds[memberStart] == 7 || tokens.Kinds[memberStart] == 85 || tokens.Kinds[memberStart] == 86 {
            methodFlags := memberModifiers.Values[2]
            if tokens.Kinds[memberStart] == 85 || tokens.Kinds[memberStart] == 86 {
                methodFlags = methodFlags | 16
            }

            // Generator (`func*`) method: a `*` (Star 90) immediately after `func` sets the generator bit
            // (4096), routed through MethodModifierFlags into the method's ColumnarFunctionInput.
            if tokens.Kinds[memberStart] == 7 && memberStart + 1 < count && tokens.Kinds[memberStart + 1] == 90 {
                methodFlags = methodFlags | 4096
            }

            signatureEnd := ParseDeclarationFunctionSignatureEndCore(source, tokens, count, memberStart)
            if signatureEnd < 0 || signatureEnd >= count {
                return -1
            }

            if tokens.Kinds[signatureEnd] != 129 && tokens.Kinds[signatureEnd] != 120 {
                // `abstract func Name(): T` — a declaration with no body, which is what `abstract`
                // MEANS. It is recorded like any other member; the emitter gives it the abstract
                // method attributes and no IL. A `static abstract` member has no slot to be abstract
                // in, so it falls through to the native-import gate and declines there.
                if ColumnarStructMethodFlagIsAbstract(methodFlags) && !ColumnarStructMethodFlagIsStatic(methodFlags) {
                    decl.MethodFuncIndices[methodCount] = memberStart
                    decl.MethodStaticFlags[methodCount] = methodFlags
                    if decl.MethodModifierFlags.Length > methodCount {
                        decl.MethodModifierFlags[methodCount] = methodFlags
                    }

                    methodCount = methodCount + 1
                    pos = signatureEnd
                    continue
                }

                if (methodFlags & 16) == 0 || !ColumnarStructMethodHasLibraryImportAttribute(source, tokens, memberStart) {
                    return -1
                }

                methodFlags = methodFlags | ColumnarFunctionModifierFlags.NativeImportModifierFlag()
                decl.MethodFuncIndices[methodCount] = memberStart
                decl.MethodStaticFlags[methodCount] = methodFlags
                if decl.MethodModifierFlags.Length > methodCount {
                    decl.MethodModifierFlags[methodCount] = methodFlags
                }

                methodCount = methodCount + 1
                pos = signatureEnd
                continue
            }

            decl.MethodFuncIndices[methodCount] = memberStart
            decl.MethodStaticFlags[methodCount] = methodFlags
            if decl.MethodModifierFlags.Length > methodCount {
                decl.MethodModifierFlags[methodCount] = methodFlags
            }

            methodCount = methodCount + 1
            pos = signatureEnd
        } else if tokens.Kinds[memberStart] == 0 && memberStart + 1 < count && tokens.Kinds[memberStart + 1] == 127 {
            if memberModifiers.Values[0] == 1 {
                return -1
            }

            decl.CtorIndices[ctorCount] = memberStart
            ctorCount = ctorCount + 1
            pos = memberStart + 1
        } else if ParseDeclarationNestedTypeDeclarationKind(tokens.Kinds[memberStart]) {
            pos = ParseDeclarationSkipDeclarationBlockCore(tokens, count, memberStart)
            if pos < 0 {
                return -1
            }

            continue
        } else if tokens.Kinds[memberStart] == 0 {
            // A FIELD, A PROPERTY OR A FIELD-LIKE EVENT — the first pass recorded it, so this one
            // only steps past it. `event <Name>: <Type>` puts an extra NAME token before the `:`.
            storageTypePos := ParseDeclarationMemberNameEnd(tokens, count, memberStart)
            if storageTypePos < count && tokens.Kinds[storageTypePos] == 0 && storageTypePos + 1 < count && tokens.Kinds[storageTypePos + 1] == 122 && ParserDeclarationTokenTextEquals(source, tokens.Starts[memberStart], tokens.ValueLengths[memberStart], "event") {
                storageTypePos = storageTypePos + 1
            }

            if storageTypePos >= count || tokens.Kinds[storageTypePos] != 122 {
                return -1
            }

            storageTypePos = storageTypePos + 1

            storageBodyPos := ParseDeclarationTypeSpanCore(tokens, count, storageTypePos, fieldTypeResult)
            if storageBodyPos < 0 {
                return -1
            }

            pos = storageBodyPos
            if pos < count && tokens.Kinds[pos] == 129 {
                pos = ParseDeclarationMemberBodyEndCore(source, tokens, count, pos)
                if pos < 0 {
                    return -1
                }

                continue
            }

            if pos < count && tokens.Kinds[pos] == 120 {
                pos = ParseDeclarationExpressionBodyEndCore(source, tokens, count, pos)
                if pos < 0 {
                    return -1
                }

                continue
            }

            if pos < count && tokens.Kinds[pos] == 93 {
                initializerEnd := ParseDeclarationInitializerExpressionEndCore(source, tokens, count, pos + 1)
                if initializerEnd < 0 {
                    return -1
                }

                pos = initializerEnd
            }

            continue
        } else {
            return -1
        }

        pos = ParseDeclarationMemberBodyEndCore(source, tokens, count, pos)
        if pos < 0 {
            return -1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 130 {
        return -1
    }

    result.Values[2] = methodCount
    result.Values[3] = ctorCount
    result.Values[4] = propCount
    return fieldCount
}

// ONE MEMBER'S BODY, FROM WHEREVER ITS SIGNATURE ENDED TO JUST PAST ITS CLOSING BRACE. Scans forward
// to the first `{` (129), `=>` (120) or `}` (130): an expression body ends where its expression does,
// a block body ends at its balanced close, and anything else is malformed. Both readings of a type's
// body step over members this way, which is what keeps their two idea of where a member ENDS
// identical — a skip that disagreed with the record would silently shift every member after it.
func ParseDeclarationMemberBodyEndCore(source: string, tokens: ParserDeclarationTokenTable, count: int, start: int): int {
    pos := start
    while pos < count && tokens.Kinds[pos] != 129 && tokens.Kinds[pos] != 130 && tokens.Kinds[pos] != 120 {
        pos = pos + 1
    }

    if pos < count && tokens.Kinds[pos] == 120 {
        return ParseDeclarationExpressionBodyEndCore(source, tokens, count, pos)
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

func ParseDeclarationExpressionBodyEndCore(source: string, tokens: ParserDeclarationTokenTable, count: int, arrowIndex: int): int {
    if arrowIndex < 0 || arrowIndex >= count || tokens.Kinds[arrowIndex] != 120 {
        return -1
    }

    expressionTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    argStack := new ParserArgumentStack(new int[](count + 1))
    nodes := new ParserExpressionNodeTable(new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1), new int[](count + 1))
    children := new ParserChildIndexTable(new int[](count + 1))
    st := new ParserState(arrowIndex + 1, 0, 0, 0, 0, 0)
    // The scan admits exactly what the body parser admits, `=> throw <exception>` included: the two
    // readings of where a member ENDS must agree, and a scan that stopped at the `throw` would shift
    // every member after it.
    valueRoot := ParseBodyValueOrThrowExpressionNode(expressionTokens, count, st, argStack, nodes, children, 0)
    if valueRoot < 0 || st.Pos <= arrowIndex + 1 {
        return -1
    }

    return st.Pos
}

func ParseConstructorChainInfoCore(source: string, tokens: ParserDeclarationTokenTable, count: int, ctorIndex: int, args: ConstructorChainArgTable, result: ParserDeclarationResultTable): int {
    result.Values[0] = 0
    result.Values[1] = -1
    pos := ctorIndex + 1
    if pos >= count || tokens.Kinds[pos] != 127 {
        return 0
    }

    pdepth := 0
    pdone := 0
    while pos < count && pdone == 0 {
        if tokens.Kinds[pos] == 127 {
            pdepth = pdepth + 1
        } else if tokens.Kinds[pos] == 128 {
            pdepth = pdepth - 1
            if pdepth == 0 {
                pdone = 1
            }
        }

        pos = pos + 1
    }

    if pdone == 0 {
        return 0
    }

    if pos >= count || tokens.Kinds[pos] != 122 {
        if pos < count && tokens.Kinds[pos] == 129 {
            result.Values[1] = pos
        }

        return 0
    }

    pos = pos + 1

    if pos >= count {
        return -1
    }

    if tokens.Kinds[pos] == 42 {
        result.Values[0] = 1
    } else if tokens.Kinds[pos] == 43 {
        result.Values[0] = 2
    } else {
        return -1
    }

    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 127 {
        return -1
    }

    pos = pos + 1

    scratchCapacity := (count + 1) * 4
    expressionTokens := new ParserTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths, source)
    expressionArgs := new ParserArgumentStack(new int[](scratchCapacity))
    expressionNodes := new ParserExpressionNodeTable(
        new int[](scratchCapacity),
        new int[](scratchCapacity),
        new int[](scratchCapacity),
        new int[](scratchCapacity),
        new int[](scratchCapacity),
        new int[](scratchCapacity),
        new int[](scratchCapacity)
    )
    expressionChildren := new ParserChildIndexTable(new int[](scratchCapacity * 4))
    expressionState := new ParserState(pos, 0, 0, 0, 0, 0, source)
    argCount := 0
    while pos < count && tokens.Kinds[pos] != 128 {
        if argCount >= args.Kinds.Length || argCount >= args.Starts.Length || argCount >= args.Lengths.Length || argCount >= args.Names.Length {
            return -1
        }

        args.Names[argCount] = ""
        if pos + 1 < count && tokens.Kinds[pos] == 0 && tokens.Kinds[pos + 1] == 122 {
            args.Names[argCount] = source.Substring(tokens.Starts[pos], tokens.ValueLengths[pos])
            pos = pos + 2
        }
        argumentStartToken := pos
        expressionState.Pos = pos
        expressionRoot := ParseLambdaOrAssignmentExpressionNode(
            expressionTokens,
            count,
            expressionState,
            expressionArgs,
            expressionNodes,
            expressionChildren,
            0
        )
        if expressionRoot < 0 || expressionState.Pos <= pos {
            return -1
        }

        args.Kinds[argCount] = tokens.Kinds[argumentStartToken]
        args.Starts[argCount] = expressionNodes.SpanStarts[expressionRoot]
        args.Lengths[argCount] = expressionNodes.SpanLengths[expressionRoot]
        argCount = argCount + 1
        pos = expressionState.Pos

        if pos < count && tokens.Kinds[pos] != 128 {
            if tokens.Kinds[pos] != 134 {
                return -1
            }

            pos = pos + 1
        }
    }

    if pos >= count || tokens.Kinds[pos] != 128 {
        return -1
    }

    pos = pos + 1
    if pos < count && tokens.Kinds[pos] == 129 {
        result.Values[1] = pos
    }

    return argCount
}

func ParseUnionDeclarationCore(tokens: ParserDeclarationTokenTable, count: int, unionIndex: int, decl: UnionDeclarationTable, result: ParserDeclarationResultTable): int {
    pos := unionIndex
    if pos >= count || tokens.Kinds[pos] != 12 {
        return -1
    }

    pos = pos + 1

    if pos >= count || tokens.Kinds[pos] != 0 {
        return -1
    }

    result.Values[0] = tokens.Starts[pos]
    result.Values[1] = tokens.ValueLengths[pos]
    pos = pos + 1

    // Optional generic TYPE-PARAMETER list `<T, U>` after the union name — bare comma-separated
    // Identifiers only, the same shape as the struct/class declaration kernel. A declaration's list
    // cannot nest, so no `>>` splitting is needed.
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
                // A consumed comma must be FOLLOWED by another parameter name — a trailing comma
                // (`<T,>`) is a production-parser error (adversarial-review finding: the loop's
                // `!= 102` condition would otherwise exit cleanly and ACCEPT what the pipeline rejects).
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

    result.Values[2] = typeParamCount

    // Generic CONSTRAINTS, between the type parameters and the case body — a union has no base list.
    unionWhereNext := pos
    unionWhereCount := ParseDeclarationWhereClausesCore(tokens, count, pos, decl.Where, out unionWhereNext)
    if unionWhereCount < 0 {
        return -1
    }

    pos = unionWhereNext
    if result.Values.Length > 5 {
        result.Values[5] = unionWhereCount
    }

    if pos >= count || tokens.Kinds[pos] != 129 {
        return -1
    }

    pos = pos + 1

    caseCount := 0
    totalFields := 0
    while pos < count && tokens.Kinds[pos] != 130 {
        if tokens.Kinds[pos] != 0 {
            return -1
        }

        decl.CaseNameStarts[caseCount] = tokens.Starts[pos]
        decl.CaseNameLengths[caseCount] = tokens.ValueLengths[pos]
        pos = pos + 1

        caseFieldCount := 0
        if pos < count && tokens.Kinds[pos] == 129 {
            pos = pos + 1

            while pos < count && tokens.Kinds[pos] != 130 {
                if tokens.Kinds[pos] != 0 {
                    return -1
                }

                decl.FieldNameStarts[totalFields] = tokens.Starts[pos]
                decl.FieldNameLengths[totalFields] = tokens.ValueLengths[pos]
                pos = pos + 1

                if pos >= count || tokens.Kinds[pos] != 122 {
                    return -1
                }

                pos = pos + 1

                if pos >= count || tokens.Kinds[pos] != 0 {
                    return -1
                }

                decl.FieldTypeStarts[totalFields] = tokens.Starts[pos]
                decl.FieldTypeLengths[totalFields] = tokens.ValueLengths[pos]
                pos = pos + 1

                totalFields = totalFields + 1
                caseFieldCount = caseFieldCount + 1

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

            pos = pos + 1
        } else if pos >= count || (tokens.Kinds[pos] != 0 && tokens.Kinds[pos] != 130) {
            return -1
        }

        decl.CaseFieldCounts[caseCount] = caseFieldCount
        caseCount = caseCount + 1
    }

    if pos >= count || tokens.Kinds[pos] != 130 {
        return -1
    }

    if caseCount == 0 {
        return -1
    }

    return caseCount
}
