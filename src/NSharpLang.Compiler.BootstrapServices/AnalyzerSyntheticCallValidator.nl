namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// LITERAL AND CONSTANT SHAPE, for the validators that have to look at what the user WROTE rather
// than at the type it resolved to.
//
// Two questions live here. "Is this argument the null literal?" is what turns a wrap column into a
// report, because a `null` column array is a runtime failure the type system happily admits. "Is
// this argument a compile-time NEGATIVE?" is what turns a row id, a capacity or a wrap length into a
// report, and it is a question about the SOURCE: `-1` is a unary negation of the literal `1`, never
// an `IntLiteralExpression` of its own.
//
// Both peel the same three transparent wrappers first — parentheses, `checked` and `unchecked`
// change nothing about the value — and the sign question additionally peels casts to the SIGNED
// integer types, because `(int)-1` is still negative while `(uint)-1` is emphatically not. Deciding
// whether a WRITTEN type name is one of those is the one thing here that is not pure: an alias
// declared in the analysed program can name `int`, so the scope stack and the declaration context
// both have to answer.
class AnalyzerConstantExpressionFacts {
    scopes: AnalyzerScopeStack
    declarationContext: AnalyzerDeclarationContext

    constructor(scopeStack: AnalyzerScopeStack, declarations: AnalyzerDeclarationContext) {
        scopes = scopeStack
        declarationContext = declarations
    }

    // Parentheses, `checked` and `unchecked` wrap an expression without changing what it IS, so
    // every shape question peels them first. The loop is repeated rather than recursive because the
    // wrappers nest arbitrarily and in any order.
    static func UnwrapTransparentWrappers(expression: Expression): Expression {
        current := expression
        unwrapping := true
        while unwrapping {
            unwrapping = false

            parenthesized := current as ParenthesizedExpression
            if parenthesized != null {
                current = parenthesized.Inner
                unwrapping = true
                continue
            }

            checkedForm := current as CheckedExpression
            if checkedForm != null {
                current = checkedForm.Expression
                unwrapping = true
                continue
            }

            uncheckedForm := current as UncheckedExpression
            if uncheckedForm != null {
                current = uncheckedForm.Expression
                unwrapping = true
            }
        }

        return current
    }

    // `null` or `default`, through any number of transparent wrappers and any number of casts. The
    // cast is peeled unconditionally here — `(int[])null` is still the null literal whatever the
    // target type is.
    static func IsNullOrDefaultLiteral(expression: Expression): bool {
        current := expression
        unwrapping := true
        while unwrapping {
            unwrapping = false
            current = UnwrapTransparentWrappers(current)
            cast := current as CastExpression
            if cast != null {
                current = cast.Expression
                unwrapping = true
            }
        }

        nullLiteral := current as NullLiteralExpression
        if nullLiteral != null {
            return true
        }

        defaultLiteral := current as DefaultExpression
        return defaultLiteral != null
    }

    // A written compile-time negative: unary negation applied to a NON-ZERO unsigned magnitude.
    // `-0` is not negative, which is why the magnitude is checked rather than just the operator.
    func IsConstantNegative(expression: Expression): bool {
        current := UnwrapSignedIntegerCasts(expression)
        unary := current as UnaryExpression
        if unary == null || unary.Operator != UnaryOperator.Negate {
            return false
        }

        magnitude: ulong = 0
        if !TryGetUnsignedIntegerMagnitude(unary.Operand, out magnitude) {
            return false
        }

        zero: ulong = 0
        return magnitude != zero
    }

    // Casts to a SIGNED integer type are transparent to the sign question; casts to anything else
    // are not, because they change what the negation means.
    func UnwrapSignedIntegerCasts(expression: Expression): Expression {
        current := expression
        unwrapping := true
        while unwrapping {
            unwrapping = false
            current = UnwrapTransparentWrappers(current)
            cast := current as CastExpression
            if cast != null && IsSignedIntegerCast(cast.TargetType) {
                current = cast.Expression
                unwrapping = true
            }
        }

        return current
    }

    func TryGetUnsignedIntegerMagnitude(expression: Expression, out magnitude: ulong): bool {
        magnitude = 0
        current := UnwrapSignedIntegerCasts(expression)
        literal := current as IntLiteralExpression
        if literal == null {
            return false
        }

        parsed: ulong = 0
        if !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(literal.Value, out parsed) {
            return false
        }

        magnitude = parsed
        return true
    }

    // The three built-in spellings answer without a lookup; anything else may still BE one of them
    // through a declared alias, so the written name is resolved through the scope stack.
    func IsSignedIntegerCast(typeReference: TypeReference): bool {
        simple := typeReference as SimpleTypeReference
        if simple == null {
            return false
        }

        if simple.Name == "int" || simple.Name == "short" || simple.Name == "sbyte" {
            return true
        }

        candidate: TypeInfo = BuiltInTypes.Unknown
        looked := scopes.LookupType(simple.Name)
        if looked != null {
            candidate = looked
        }

        resolved := declarationContext.ResolveDeclaredAlias(candidate)
        return BuiltInTypes.Is(resolved, BuiltInTypes.Int) || BuiltInTypes.Is(resolved, BuiltInTypes.Short) || BuiltInTypes.Is(resolved, BuiltInTypes.SByte)
    }
}

// THE SYNTHETIC CALL'S VALIDATOR — everything the analyzer says about a call to an N#-DECLARED
// function once the walk has chosen which one it is calling.
//
// The walk (`AnalyzerSyntheticCallWalk`) answers "which overload, and what is `T`". This answers the
// four questions that follow from that answer, and all four of them REPORT:
//
//   * is the argument COUNT inside the signature's band, and is every argument's TYPE assignable to
//     the parameter it landed on (`ValidateCall`);
//   * does every inferred type argument satisfy the constraints written on the signature
//     (`ValidateGenericConstraints`);
//   * when the walk chose NOTHING, what does the user see (`ReportNoMatchingOverload`);
//   * and for the SoA intrinsics, are the arguments that carry a row id, a capacity, a length or a
//     backing column array actually usable (`ValidateSoaCall`).
//
// It also answers the one non-reporting question the argument walk asks BEFORE any of this:
// `GetExpectedArgumentType`, the expected type an argument is analysed against, which is what lets a
// lambda or a collection literal in argument position see its target shape.
//
// EVERY REPORT HAS TWO SHAPES AND THE CHOICE IS NOT A STYLE. When the analysed file's path AND the
// offending line's source text are both available, the rich `ErrorMessageBuilder` form renders with
// a snippet, a human explanation and a docs link; when either is missing — an in-memory analysis, a
// synthesised node at line 0 — the detail-only form is the only one that can be built. Both append
// to the SAME list in the SAME position, so the choice never moves a diagnostic relative to its
// neighbours.
//
// THE ONE THING THIS OWNER CANNOT COMPUTE, AND WHY IT IS A PARAMETER. A receiver-style call supplies
// its first source parameter from the member-access RECEIVER, so generic inference has to see that
// receiver's TYPE, and only the analyzer's own expression walk can answer it. It arrives as an
// ordinary value on the two members that infer, exactly as it does on the walk, and the DECISION
// about whether one is needed at all stays in `AnalyzerSyntheticCallWalk.NeedsReceiverType`.
class AnalyzerSyntheticCallValidator {
    declarationContext: AnalyzerDeclarationContext
    typeResolver: AnalyzerTypeResolver
    assignability: AnalyzerAssignability
    overloadScoring: AnalyzerOverloadScoring
    walk: AnalyzerSyntheticCallWalk
    reporter: AnalyzerSyntheticCallReporter
    spans: AnalyzerDiagnosticSpans
    diagnostics: AnalyzerDiagnosticSink
    constants: AnalyzerConstantExpressionFacts

    constructor(declarations: AnalyzerDeclarationContext, resolver: AnalyzerTypeResolver, assignabilityOwner: AnalyzerAssignability, scoring: AnalyzerOverloadScoring, callWalk: AnalyzerSyntheticCallWalk, callReporter: AnalyzerSyntheticCallReporter, spanResolver: AnalyzerDiagnosticSpans, diagnosticSink: AnalyzerDiagnosticSink, constantFacts: AnalyzerConstantExpressionFacts) {
        declarationContext = declarations
        typeResolver = resolver
        assignability = assignabilityOwner
        overloadScoring = scoring
        walk = callWalk
        reporter = callReporter
        spans = spanResolver
        diagnostics = diagnosticSink
        constants = constantFacts
    }

    // THE TYPE AN ARGUMENT IS ANALYSED AGAINST, or null when the position gives no useful shape.
    //
    // The params tail is the interesting arm. Normally it contributes its ELEMENT type, so
    // `params xs: int[]` called as `f(1, 2)` analyses each argument against `int`. But a SINGLE
    // trailing array literal is ambiguous — it can be the params array itself or one expanded
    // element of it — so the position deliberately answers null and lets validation decide once it
    // has seen the value.
    func GetExpectedArgumentType(functionType: FunctionTypeInfo, call: CallExpression, argumentIndex: int, parameterIndex: int, genericBindings: Dictionary<string, TypeInfo>?): TypeInfo? {
        parameterTypes := functionType.ParameterTypes
        if parameterTypes == null || parameterIndex < 0 || parameterIndex >= parameterTypes.Count {
            return null
        }

        parameterType := AnalyzerSyntheticCallFacts.ApplyGenericBindings(parameterTypes[parameterIndex], genericBindings)
        paramsParameterIndex := AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(functionType, parameterTypes.Count)
        if paramsParameterIndex >= 0 && parameterIndex == paramsParameterIndex {
            paramsElementType := overloadScoring.GetNSharpParamsElementType(parameterType)

            if call.Arguments.Count == paramsParameterIndex + 1 {
                arrayLiteral := call.Arguments[argumentIndex].Value as ArrayLiteralExpression
                if arrayLiteral != null {
                    return null
                }
            }

            if paramsElementType != null {
                return paramsElementType
            }

            return parameterType
        }

        return AnalyzerOverloadFacts.ApplySyntheticParameterModifier(functionType, parameterIndex, parameterType)
    }

    // EVERYTHING THE ANALYZER SAYS ABOUT A CALL TO A CHOSEN N#-DECLARED FUNCTION.
    //
    // The order is load-bearing. Constraints check FIRST, because a violated constraint explains the
    // argument errors that follow it. Then arity, which RETURNS when it fires: an argument-by-
    // argument type check against a signature the call does not even fit would bury the real
    // problem. Then placement, which reports its own naming failures. Only then does each written
    // argument get compared to the parameter it actually landed on, and finally the SoA intrinsics
    // get their value-level check.
    func ValidateCall(functionType: FunctionTypeInfo, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>, receiverType: TypeInfo?) {
        parameterTypes := functionType.ParameterTypes
        if parameterTypes == null {
            return
        }

        functionName := AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(functionType, call)
        expectedCount := parameterTypes.Count
        parameterStartIndex := AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(functionType, call)
        requiredCount := AnalyzerOverloadFacts.GetSyntheticRequiredArgumentCount(functionType, expectedCount, parameterStartIndex)
        expectedArgumentCount := Math.Max(0, expectedCount - parameterStartIndex)
        paramsParameterIndex := AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(functionType, expectedCount)
        hasParamsParameter := paramsParameterIndex >= 0
        genericBindings := walk.InferGenericBindings(functionType, call, argTypes, receiverType)
        ValidateGenericConstraints(functionType, call, genericBindings)
        if argTypes.Count < requiredCount || (!hasParamsParameter && argTypes.Count > expectedArgumentCount) {
            ReportWrongArgumentCount(call, functionName, requiredCount, expectedArgumentCount, argTypes.Count)
            return
        }

        parameterIndexByArgument: int[] = new int[0]
        if !reporter.TryBindAndReport(functionType, functionName, call, out parameterIndexByArgument, parameterStartIndex, true) {
            return
        }

        argumentIndex := 0
        while argumentIndex < call.Arguments.Count {
            currentArgument := argumentIndex
            argumentIndex = argumentIndex + 1
            parameterIndex := parameterIndexByArgument[currentArgument]
            if parameterIndex < 0 || parameterIndex >= expectedCount {
                continue
            }

            expectedType := declarationContext.ResolveDeclaredAlias(AnalyzerOverloadFacts.ApplySyntheticParameterModifier(functionType, parameterIndex, AnalyzerSyntheticCallFacts.ApplyGenericBindings(parameterTypes[parameterIndex], genericBindings)))
            argType := declarationContext.ResolveDeclaredAlias(argTypes[currentArgument])
            if hasParamsParameter && parameterIndex == paramsParameterIndex {
                paramsType := declarationContext.ResolveDeclaredAlias(AnalyzerSyntheticCallFacts.ApplyGenericBindings(parameterTypes[paramsParameterIndex], genericBindings))
                paramsArrayType := paramsType as ArrayTypeInfo
                if paramsArrayType == null {
                    continue
                }

                paramsArgumentIndex := paramsParameterIndex - parameterStartIndex
                isDirectParamsArrayArgument := overloadScoring.IsSingleDirectNSharpParamsArrayArgument(paramsArgumentIndex, call.Arguments, argTypes, paramsArrayType)

                if !isDirectParamsArrayArgument {
                    spread := call.Arguments[currentArgument].Value as SpreadExpression
                    if spread != null {
                        // A spread compares ELEMENT to ELEMENT; an unresolved spread says nothing.
                        spreadArrayType := argType as ArrayTypeInfo
                        if spreadArrayType != null {
                            expectedType = declarationContext.ResolveDeclaredAlias(paramsArrayType.ElementType)
                            argType = declarationContext.ResolveDeclaredAlias(spreadArrayType.ElementType)
                        } else if BuiltInTypes.IsUnknown(argType) {
                            continue
                        }
                    } else {
                        expectedType = declarationContext.ResolveDeclaredAlias(paramsArrayType.ElementType)
                    }
                }
            }

            argumentRow := argType as SoaRowTypeInfo
            if BuiltInTypes.IsUnknown(expectedType) || BuiltInTypes.IsUnknown(argType) || argumentRow != null || assignability.IsAssignable(expectedType, argType) {
                continue
            }

            ReportWrongArgumentType(functionType, call, functionName, currentArgument, parameterIndex, expectedType, argType)
        }

        ValidateSoaCall(functionType, functionName, call, argTypes, parameterIndexByArgument)
    }

    // NL401. The rich form names the count it wanted; the fallback names the whole BAND, because
    // without a snippet the reader has no other way to see that some parameters are optional.
    func ReportWrongArgumentCount(call: CallExpression, functionName: string, requiredCount: int, expectedArgumentCount: int, actualCount: int) {
        span := spans.GetCallDiagnosticSpan(call, functionName)
        filePath := ""
        snippet := ""
        if TryGetRichContext(span.Line, out filePath, out snippet) {
            expected := expectedArgumentCount
            if actualCount < requiredCount {
                expected = requiredCount
            }

            diagnostics.ReportBuilt(ErrorMessageBuilder.WrongArgumentCount(filePath, span.Line, span.Column, snippet, span.Length, functionName, expected, actualCount))
            return
        }

        expectedDescription := expectedArgumentCount.ToString()
        if requiredCount != expectedArgumentCount {
            expectedDescription = requiredCount.ToString() + " to " + expectedArgumentCount.ToString()
        }

        diagnostics.Report(ErrorCode.WrongArgumentCount, "'" + functionName + "' takes " + expectedDescription + " argument(s), but you passed " + actualCount.ToString(), span.Line, span.Column, "Check the argument count against the function signature.", span.Length)
    }

    // NL202 for one argument. The rich form additionally needs the PARAMETER'S NAME — it renders
    // "the parameter `x` expects …" — so a signature that carries no names falls back even when the
    // snippet is available.
    func ReportWrongArgumentType(functionType: FunctionTypeInfo, call: CallExpression, functionName: string, argumentIndex: int, parameterIndex: int, expectedType: TypeInfo, argType: TypeInfo) {
        span := spans.GetExpressionDiagnosticSpan(call.Arguments[argumentIndex].Value)
        parameterName: string? = null
        parameterNames := functionType.ParameterNames
        if parameterNames != null && parameterIndex < parameterNames.Count {
            parameterName = parameterNames[parameterIndex]
        }

        parameterNameText := ""
        if parameterName != null {
            parameterNameText = parameterName
        }

        expectedTypeText := "unknown"
        expectedTypeObject := expectedType as object
        renderedExpectedType := expectedTypeObject.ToString()
        if renderedExpectedType != null {
            expectedTypeText = renderedExpectedType
        }

        filePath := ""
        snippet := ""
        if TryGetRichContext(span.Line, out filePath, out snippet) && parameterName != null {
            diagnostics.ReportBuilt(ErrorMessageBuilder.WrongArgumentType(filePath, span.Line, span.Column, snippet, span.Length, functionName, argumentIndex + 1, parameterNameText, GetArgumentTypeDiagnosticName(call.Arguments[argumentIndex], argType), expectedTypeText))
            return
        }

        argumentDescription := "Argument " + (argumentIndex + 1).ToString()
        argumentName := call.Arguments[argumentIndex].Name
        if argumentName != null {
            argumentDescription = "Argument '" + argumentName + "'"
        }

        actualType := FormatArgumentTypeDiagnosticPhrase(call.Arguments[argumentIndex], argType)
        diagnostics.Report(ErrorCode.TypeMismatch, ErrorMessageBuilder.WrongArgumentTypeMessage(argumentDescription, functionName, actualType, parameterName, expectedTypeText), span.Line, span.Column, "Pass a value with the expected type, or update the function signature.", span.Length)
    }

    // NL208. A type parameter nothing bound is SKIPPED rather than reported: an open binding means
    // inference had nothing to go on, and a constraint report there would name a type the user never
    // wrote. Every violated arm reports independently, so one argument can carry several.
    func ValidateGenericConstraints(functionType: FunctionTypeInfo, call: CallExpression, bindings: Dictionary<string, TypeInfo>?) {
        constraints := functionType.GenericConstraints
        if constraints == null || bindings == null || bindings.Count == 0 {
            return
        }

        functionName := AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(functionType, call)
        classFlag := Convert.ToInt32(SpecialConstraintKind.Class)
        structFlag := Convert.ToInt32(SpecialConstraintKind.Struct)
        newFlag := Convert.ToInt32(SpecialConstraintKind.New)
        index := 0
        while index < constraints.Count {
            constraint := constraints[index]
            index = index + 1

            boundType: TypeInfo = BuiltInTypes.Unknown
            if !bindings.TryGetValue(constraint.TypeParameter, out boundType) {
                continue
            }

            span := walk.GetGenericConstraintDiagnosticSpan(functionType, call, constraint.TypeParameter, functionName)
            boundObject := boundType as object
            boundText := boundObject.ToString()
            specialValue := Convert.ToInt32(constraint.SpecialConstraints)

            if (specialValue & classFlag) == classFlag {
                if !AnalyzerConversionFacts.IsReferenceType(boundType) {
                    diagnostics.Report(ErrorCode.GenericConstraintViolation, "`" + boundText + "` is a value type, but type parameter `" + constraint.TypeParameter + "` of `" + functionName + "` requires a reference type (the `class` constraint)", span.Line, span.Column, "Pass a class instance for `" + constraint.TypeParameter + "`, or relax the `class` constraint on `" + functionName + "`.", span.Length)
                }
            }

            if (specialValue & structFlag) == structFlag {
                boundNullable := boundType as NullableTypeInfo
                if AnalyzerConversionFacts.IsReferenceType(boundType) || boundNullable != null {
                    diagnostics.Report(ErrorCode.GenericConstraintViolation, "`" + boundText + "` is not a non-nullable value type, but type parameter `" + constraint.TypeParameter + "` of `" + functionName + "` requires one (the `struct` constraint)", span.Line, span.Column, "Pass a non-nullable value type for `" + constraint.TypeParameter + "`, or relax the `struct` constraint on `" + functionName + "`.", span.Length)
                }
            }

            if (specialValue & newFlag) == newFlag {
                if !HasParameterlessConstructor(boundType) {
                    diagnostics.Report(ErrorCode.GenericConstraintViolation, "`" + boundText + "` has no parameterless constructor, but type parameter `" + constraint.TypeParameter + "` of `" + functionName + "` requires one (the `new()` constraint)", span.Line, span.Column, "Give `" + boundText + "` a parameterless constructor, or relax the `new()` constraint on `" + functionName + "`.", span.Length)
                }
            }

            // The declaration's OWN resolved constraint types win when it recorded them; only a
            // signature that did not resolves the written references here.
            resolvedConstraintTypes := new List<TypeInfo>()
            resolvedFromDeclaration := false
            declaredConstraintTypesByParameter := functionType.ResolvedGenericConstraintTypes
            if declaredConstraintTypesByParameter != null {
                declaredConstraintTypes: List<TypeInfo> = new List<TypeInfo>()
                if declaredConstraintTypesByParameter.TryGetValue(constraint.TypeParameter, out declaredConstraintTypes) {
                    resolvedConstraintTypes = declaredConstraintTypes
                    resolvedFromDeclaration = true
                }
            }

            if !resolvedFromDeclaration {
                writtenIndex := 0
                while writtenIndex < constraint.Constraints.Count {
                    resolvedConstraintTypes.Add(typeResolver.ResolveType(constraint.Constraints[writtenIndex]))
                    writtenIndex = writtenIndex + 1
                }
            }

            constraintTypeIndex := 0
            while constraintTypeIndex < resolvedConstraintTypes.Count {
                constraintType := resolvedConstraintTypes[constraintTypeIndex]
                constraintTypeIndex = constraintTypeIndex + 1
                closedConstraintType := AnalyzerSyntheticCallFacts.ApplyGenericBindings(constraintType, bindings)

                // Either direction satisfies: the bound type may BE a subtype of the constraint, or
                // be assignable to it through a conversion the constraint admits.
                if !assignability.IsSubtypeOf(boundType, closedConstraintType) && !assignability.IsAssignable(closedConstraintType, boundType) {
                    closedObject := closedConstraintType as object
                    closedText := closedObject.ToString()
                    diagnostics.Report(ErrorCode.GenericConstraintViolation, "`" + boundText + "` does not implement `" + closedText + "`, which type parameter `" + constraint.TypeParameter + "` of `" + functionName + "` requires", span.Line, span.Column, "Implement `" + closedText + "` on `" + boundText + "`, or relax the constraint on `" + functionName + "`.", span.Length)
                }
            }
        }
    }

    // Whether a type satisfies the `new()` constraint.
    //
    // Every value type has one implicitly, declared or not — that covers structs, record structs and
    // every CLR value type. A record CLASS is the one that can lose it: a primary constructor with
    // parameters suppresses the default constructor. An unknown type is assumed to satisfy: a
    // constraint report about a type the analyzer could not resolve is noise on top of the
    // resolution failure the user already has.
    static func HasParameterlessConstructor(candidate: TypeInfo): bool {
        structType := candidate as StructTypeInfo
        if structType != null {
            return true
        }

        classType := candidate as ClassTypeInfo
        if classType != null {
            return classType.HasParameterlessConstructor
        }

        recordType := candidate as RecordTypeInfo
        if recordType != null {
            if recordType.IsStruct {
                return true
            }

            return recordType.PrimaryConstructorParameters.Length == 0
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            clrType := reflectionType.Type
            if clrType.get_IsValueType() {
                return true
            }

            return clrType.GetConstructor(new Type[](0)) != null
        }

        return true
    }

    // THE RETURN TYPE OF A CALL TO AN N#-DECLARED FUNCTION, closed over whatever the call inferred.
    // A signature that declares no return type is `void`, not unknown.
    func ResolveReturnType(functionType: FunctionTypeInfo, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>, receiverType: TypeInfo?): TypeInfo {
        returnType: TypeInfo = BuiltInTypes.Void
        declaredReturnType := functionType.ReturnType
        if declaredReturnType != null {
            returnType = declaredReturnType
        }

        genericBindings := walk.InferGenericBindings(functionType, call, argTypes, receiverType)
        return AnalyzerSyntheticCallFacts.ApplyGenericBindings(returnType, genericBindings)
    }

    // NL402 — the walk considered every candidate and chose none.
    //
    // The candidate list is rendered DISTINCT and capped at eight: overload groups can be large, and
    // a hint the reader will not finish is worse than a shorter one. Distinctness comes first, so
    // the cap counts eight DIFFERENT signatures rather than eight candidates.
    func ReportNoMatchingOverload(candidates: IReadOnlyList<FunctionTypeInfo>, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>) {
        if candidates.Count == 0 {
            return
        }

        functionName := "function"
        targetName := AnalyzerSyntheticCallFacts.GetCallTargetName(call)
        if targetName != null {
            functionName = targetName
        } else {
            firstSyntheticName := candidates[0].SyntheticName
            if firstSyntheticName != null {
                functionName = firstSyntheticName
            }
        }

        span := spans.GetCallDiagnosticSpan(call, functionName)
        argumentTypes := new List<string>()
        typeIndex := 0
        while typeIndex < argTypes.Count {
            argumentTypeObject := argTypes[typeIndex] as object
            argumentTypes.Add(argumentTypeObject.ToString())
            typeIndex = typeIndex + 1
        }

        candidateSignatures := new List<string>()
        candidateIndex := 0
        while candidateIndex < candidates.Count && candidateSignatures.Count < 8 {
            candidate := candidates[candidateIndex]
            candidateIndex = candidateIndex + 1
            candidateName := functionName
            candidateSyntheticName := candidate.SyntheticName
            if candidateSyntheticName != null {
                candidateName = candidateSyntheticName
            }

            signature := AnalyzerOverloadFacts.FormatSyntheticFunctionSignature(candidate, candidateName, AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(candidate, call))
            if !candidateSignatures.Contains(signature) {
                candidateSignatures.Add(signature)
            }
        }

        filePath := ""
        snippet := ""
        if TryGetRichContext(span.Line, out filePath, out snippet) {
            diagnostics.ReportBuilt(ErrorMessageBuilder.NoMatchingOverload(filePath, span.Line, span.Column, snippet, span.Length, functionName, call.Arguments.Count, argumentTypes, candidateSignatures))
            return
        }

        diagnostics.Report(ErrorCode.NoMatchingOverload, "No overload of '" + functionName + "' accepts " + call.Arguments.Count.ToString() + " argument(s) with these types", span.Line, span.Column, "Check the argument count and types against the available overloads.", span.Length)
    }

    // THE SoA INTRINSICS' VALUE-LEVEL CHECKS. These are the only synthetic functions whose arguments
    // have a meaning beyond their type: a wrap column that is null, or a row id, capacity or length
    // written as a negative constant, is a guaranteed runtime failure that the type system admits.
    func ValidateSoaCall(functionType: FunctionTypeInfo, functionName: string, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>, parameterIndexByArgument: int[]) {
        syntheticName := functionType.SyntheticName
        if syntheticName == null {
            return
        }

        if syntheticName == "wrap" {
            ValidateSoaWrapColumnArguments(functionType, functionName, call, argTypes, parameterIndexByArgument)

            lengthParameterIndex := -1
            parameterNames := functionType.ParameterNames
            if parameterNames != null {
                nameIndex := 0
                while nameIndex < parameterNames.Count {
                    if parameterNames[nameIndex] == "length" {
                        lengthParameterIndex = nameIndex
                        break
                    }

                    nameIndex = nameIndex + 1
                }
            }

            if lengthParameterIndex >= 0 {
                ValidateNonNegativeIntArgument(functionName, call, argTypes, parameterIndexByArgument, lengthParameterIndex, "SoA table wrap length must not be negative", "Use zero or a valid row count no greater than the column lengths.")
            }

            return
        }

        if syntheticName == "ensureCapacity" {
            ValidateNonNegativeIntArgument(functionName, call, argTypes, parameterIndexByArgument, 0, "SoA table capacity must not be negative", "Use zero or a positive capacity; the table can grow later with add or ensureCapacity.")
            return
        }

        if syntheticName == "copyRow" {
            ValidateNonNegativeIntArgument(functionName, call, argTypes, parameterIndexByArgument, 0, "SoA table source row id must not be negative", "Use zero or a valid non-negative source row id.")
            ValidateNonNegativeIntArgument(functionName, call, argTypes, parameterIndexByArgument, 1, "SoA table target row id must not be negative", "Use zero or a valid non-negative target row id.")
        }
    }

    // A wrap column written as `null` or `default`.
    //
    // The type gate is deliberately inverted: an argument whose type is KNOWN and NOT assignable is
    // skipped, because the ordinary NL202 already names it and two reports on one argument is one
    // too many. What is left is the argument that type-checks fine and is still null.
    func ValidateSoaWrapColumnArguments(functionType: FunctionTypeInfo, functionName: string, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>, parameterIndexByArgument: int[]) {
        parameterTypes := functionType.ParameterTypes
        if parameterTypes == null {
            return
        }

        argumentIndex := 0
        while argumentIndex < call.Arguments.Count {
            currentArgument := argumentIndex
            argumentIndex = argumentIndex + 1
            parameterIndex := parameterIndexByArgument[currentArgument]
            if parameterIndex < 0 || parameterIndex >= parameterTypes.Count {
                continue
            }

            expectedType := parameterTypes[parameterIndex]
            resolvedExpectedType := declarationContext.ResolveDeclaredAlias(expectedType)
            expectedArrayType := resolvedExpectedType as ArrayTypeInfo
            if expectedArrayType == null {
                continue
            }

            if currentArgument < argTypes.Count && !BuiltInTypes.IsUnknown(argTypes[currentArgument]) && !assignability.IsAssignable(expectedType, argTypes[currentArgument]) {
                continue
            }

            argument := call.Arguments[currentArgument]
            if !AnalyzerConstantExpressionFacts.IsNullOrDefaultLiteral(argument.Value) {
                continue
            }

            columnName := "column " + (parameterIndex + 1).ToString()
            parameterNames := functionType.ParameterNames
            if parameterNames != null && parameterIndex < parameterNames.Count {
                columnName = parameterNames[parameterIndex]
            }

            span := spans.GetExpressionDiagnosticSpan(argument.Value)
            diagnostics.Report(ErrorCode.TypeMismatch, "SoA table wrap column '" + columnName + "' cannot be null", span.Line, span.Column, "Pass the backing '" + columnName + "' column array, or allocate one before calling " + functionName + ".", span.Length)
        }
    }

    // The argument that filled ONE named parameter position, checked for a written negative
    // constant. The parameter is located through the placement map rather than by position, so a
    // named argument is checked wherever the caller wrote it.
    func ValidateNonNegativeIntArgument(functionName: string, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>, parameterIndexByArgument: int[], parameterIndex: int, message: string, suggestion: string) {
        argumentIndex := -1
        placementIndex := 0
        while placementIndex < parameterIndexByArgument.Length {
            if parameterIndexByArgument[placementIndex] == parameterIndex {
                argumentIndex = placementIndex
                break
            }

            placementIndex = placementIndex + 1
        }

        if argumentIndex < 0 {
            return
        }

        if argumentIndex >= call.Arguments.Count || argumentIndex >= argTypes.Count {
            return
        }

        argType := declarationContext.ResolveDeclaredAlias(argTypes[argumentIndex])
        argumentRow := argType as SoaRowTypeInfo
        if BuiltInTypes.IsUnknown(argType) || argumentRow != null || !assignability.IsAssignable(BuiltInTypes.Int, argType) {
            return
        }

        if !constants.IsConstantNegative(call.Arguments[argumentIndex].Value) {
            return
        }

        span := spans.GetExpressionDiagnosticSpan(call.Arguments[argumentIndex].Value)
        diagnostics.Report(ErrorCode.TypeMismatch, message, span.Line, span.Column, functionName + " expects a non-negative int argument here. " + suggestion, span.Length)
    }

    // HOW AN ARGUMENT'S TYPE IS NAMED IN A DIAGNOSTIC. A method group has no useful type name — the
    // reader needs the METHOD'S name, not `method group` — so it is named rather than typed.
    func GetArgumentTypeDiagnosticName(argument: Argument, argumentType: TypeInfo): string {
        resolvedType := declarationContext.ResolveDeclaredAlias(argumentType)
        if AnalyzerCallableReferenceFacts.IsCallableReferenceType(resolvedType) {
            return "method group '" + AnalyzerCallableReferenceFacts.GetCallableReferenceName(argument.Value, resolvedType) + "'"
        }

        argumentTypeObject := argumentType as object
        renderedArgumentType := argumentTypeObject.ToString()
        if renderedArgumentType == null {
            return "unknown"
        }

        return renderedArgumentType
    }

    // The same name as a PHRASE. An ordinary type is quoted; a method group already carries its own
    // quotes around the method name, so quoting again would double them.
    func FormatArgumentTypeDiagnosticPhrase(argument: Argument, argumentType: TypeInfo): string {
        resolvedType := declarationContext.ResolveDeclaredAlias(argumentType)
        name := GetArgumentTypeDiagnosticName(argument, argumentType)
        if AnalyzerCallableReferenceFacts.IsCallableReferenceType(resolvedType) {
            return name
        }

        return "'" + name + "'"
    }

    // The two values every rich report needs: the analysed file's path and the offending line's
    // source text. Both are read through the sink, so a report's snippet and its span are computed
    // against one resolution of the file's text.
    func TryGetRichContext(line: int, out filePath: string, out snippet: string): bool {
        filePath = ""
        snippet = ""
        resolvedFilePath := diagnostics.CurrentFilePath
        if resolvedFilePath != null {
            filePath = resolvedFilePath
        }

        resolvedSnippet := diagnostics.SourceSnippet(line)
        if resolvedSnippet != null {
            snippet = resolvedSnippet
        }

        return resolvedFilePath != null && resolvedSnippet != null
    }
}
