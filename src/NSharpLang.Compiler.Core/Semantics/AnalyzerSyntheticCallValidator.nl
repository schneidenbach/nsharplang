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
    postconditions: AnalyzerNullabilityPostconditions
    terminatingCalls: AnalyzerTerminatingCalls

    constructor(declarations: AnalyzerDeclarationContext, resolver: AnalyzerTypeResolver, assignabilityOwner: AnalyzerAssignability, scoring: AnalyzerOverloadScoring, callWalk: AnalyzerSyntheticCallWalk, callReporter: AnalyzerSyntheticCallReporter, spanResolver: AnalyzerDiagnosticSpans, diagnosticSink: AnalyzerDiagnosticSink, constantFacts: AnalyzerConstantExpressionFacts, postconditionOwner: AnalyzerNullabilityPostconditions, terminatingCallOwner: AnalyzerTerminatingCalls) {
        declarationContext = declarations
        typeResolver = resolver
        assignability = assignabilityOwner
        overloadScoring = scoring
        walk = callWalk
        reporter = callReporter
        spans = spanResolver
        diagnostics = diagnosticSink
        constants = constantFacts
        postconditions = postconditionOwner
        terminatingCalls = terminatingCallOwner
    }

    // THE TYPE AN ARGUMENT IS ANALYSED AGAINST, or null when the position gives no useful shape.
    //
    // The params tail is the interesting arm. Normally it contributes its ELEMENT type, so
    // `params xs: int[]` called as `f(1, 2)` analyses each argument against `int`. A SINGLE trailing
    // ARRAY LITERAL reads as the params ARRAY ITSELF — the normal form — which is C#'s own rule for a
    // collection expression in a params position and is the reading the emitter already chooses.
    // This position used to answer NOTHING there, on the grounds that the literal could also be one
    // expanded element; but a literal with no target infers from its FIRST element, so
    // `f(["a", 1])` reported "All elements in an array must be the same type" before the validation
    // that was supposed to decide ever ran. Answering the array type makes the two readings agree and
    // gives each element the conversion it is owed.
    func GetExpectedArgumentType(functionType: FunctionTypeInfo, call: CallExpression, argumentIndex: int, parameterIndex: int, genericBindings: Dictionary<string, TypeInfo>?): TypeInfo? {
        parameterTypes := functionType.ParameterTypes
        if parameterTypes == null || parameterIndex < 0 || parameterIndex >= parameterTypes.Count {
            return null
        }

        parameterType := AnalyzerSyntheticCallFacts.ApplyGenericBindings(parameterTypes[parameterIndex], genericBindings, NullabilityGenericSubstitution.LiftedTypeParameterNames(functionType.GenericConstraints))
        paramsParameterIndex := AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(functionType, parameterTypes.Count)
        if paramsParameterIndex >= 0 && parameterIndex == paramsParameterIndex {
            paramsElementType := overloadScoring.GetNSharpParamsElementType(parameterType)

            if call.Arguments.Count == paramsParameterIndex + 1 {
                arrayLiteral := call.Arguments[argumentIndex].Value as ArrayLiteralExpression
                if arrayLiteral != null {
                    return parameterType
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
        if !ValidateWrittenTypeArgumentCount(functionType, call, functionName) {
            // Every later report about this call is a CONSEQUENCE of the list being the wrong
            // length — the parameters it did not name stay open and compare badly against every
            // argument — so the root is reported alone.
            return
        }

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

            argument := call.Arguments[currentArgument]
            if argument.Modifier == ArgumentModifier.In && !ExpectsInArgument(functionType, parameterIndex) {
                span := spans.GetInArgumentModifierDiagnosticSpan(argument)
                parameterName := ParameterNameForDirectionError(functionType, parameterIndex)
                diagnostics.Report(ErrorCode.NoMatchingOverload, "Argument uses `in`, but parameter '" + parameterName + "' of '" + functionName + "' is passed by value", span.Line, span.Column, "Remove `in`, or declare the parameter as `in`.", span.Length)
                continue
            }

            expectedType := declarationContext.ResolveDeclaredAlias(AnalyzerOverloadFacts.ApplySyntheticParameterModifier(functionType, parameterIndex, AnalyzerSyntheticCallFacts.ApplyGenericBindings(parameterTypes[parameterIndex], genericBindings, NullabilityGenericSubstitution.LiftedTypeParameterNames(functionType.GenericConstraints))))
            expectedType = ApplyParameterInputNullability(functionType, parameterIndex, expectedType)
            argType := declarationContext.ResolveDeclaredAlias(argTypes[currentArgument])
            if hasParamsParameter && parameterIndex == paramsParameterIndex {
                paramsType := declarationContext.ResolveDeclaredAlias(AnalyzerSyntheticCallFacts.ApplyGenericBindings(parameterTypes[paramsParameterIndex], genericBindings, NullabilityGenericSubstitution.LiftedTypeParameterNames(functionType.GenericConstraints)))
                paramsArrayType := paramsType as ArrayTypeInfo
                if paramsArrayType == null {
                    continue
                }

                paramsArgumentIndex := paramsParameterIndex - parameterStartIndex
                isDirectParamsArrayArgument := overloadScoring.IsDirectNSharpParamsArrayArgument(currentArgument, paramsArgumentIndex, call.Arguments, argTypes, paramsArrayType)

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
            // 023/1e — THIS BINDER-FED POSITION CAN SUPPLY THE CONSTANT AFTER ALL.
            // The Phase-1 census flagged it as one of three that might have discarded the expression by
            // the time they ask; it has not — `call.Arguments[currentArgument].Value` is the argument's
            // own expression, so the constant conversions reach an argument position (`Take(0)` onto an
            // external enum parameter, `Take(65)` onto a `byte` one) exactly as they reach a typed local.
            argumentConstant := ConstantOperandFacts.None()
            if currentArgument < call.Arguments.Count {
                argumentConstant = ConstantOperandFacts.FromExpression(call.Arguments[currentArgument].Value)
            }

            if BuiltInTypes.IsUnknown(expectedType) || BuiltInTypes.IsUnknown(argType) || argumentRow != null || assignability.IsAssignableWithConstant(expectedType, argType, argumentConstant) {
                continue
            }

            ReportWrongArgumentType(functionType, call, functionName, currentArgument, parameterIndex, expectedType, argType)
        }

        ValidateSoaCall(functionType, functionName, call, argTypes, parameterIndexByArgument)
        RecordCallPostconditions(functionType, call, parameterIndexByArgument, genericBindings, expectedCount)
    }

    // `in` is a call-site spelling only for an `in` parameter. A by-value parameter may read the
    // same value, but accepting the modifier leaves emission with a direction it cannot honor.
    static func ExpectsInArgument(functionType: FunctionTypeInfo, parameterIndex: int): bool {
        modifiers := functionType.ParameterModifiers
        return modifiers != null && parameterIndex >= 0 && parameterIndex < modifiers.Count && modifiers[parameterIndex] == Ast.ParameterModifier.In
    }

    static func ApplyParameterInputNullability(functionType: FunctionTypeInfo, parameterIndex: int, expectedType: TypeInfo): TypeInfo {
        facts := functionType.ParameterFlowFacts
        if facts == null || parameterIndex < 0 || parameterIndex >= facts.Count {
            return expectedType
        }

        return NullabilityMetadataCore.ApplyInputFlowFacts(expectedType, facts[parameterIndex])
    }

    static func ParameterNameForDirectionError(functionType: FunctionTypeInfo, parameterIndex: int): string {
        names := functionType.ParameterNames
        if names != null && parameterIndex >= 0 && parameterIndex < names.Count {
            return names[parameterIndex]
        }

        return "parameter " + (parameterIndex + 1).ToString()
    }

    // WHAT THIS CALL LEAVES BEHIND, read off the same binding the argument checks just used.
    //
    // It is a SECOND pass rather than a line inside the first, because the first `continue`s past
    // every position it has nothing to report about — a params tail, an unresolved type, an SoA row —
    // and a postcondition is owed for those positions too. Nothing here reports; the facts are the
    // call's, and the flow decides where they land.
    func RecordCallPostconditions(functionType: FunctionTypeInfo, call: CallExpression, parameterIndexByArgument: int[], genericBindings: Dictionary<string, TypeInfo>?, expectedCount: int) {
        parameterTypes := functionType.ParameterTypes
        modifiers := functionType.ParameterModifiers
        flowFactsByParameter := functionType.ParameterFlowFacts
        facts := new List<NullabilityPostcondition>()
        argumentIndex := 0
        while parameterTypes != null && argumentIndex < call.Arguments.Count {
            currentArgument := argumentIndex
            argumentIndex = argumentIndex + 1
            parameterIndex := parameterIndexByArgument[currentArgument]
            if parameterIndex < 0 || parameterIndex >= expectedCount {
                continue
            }

            isByRefParameter := false
            if modifiers != null && parameterIndex < modifiers.Count {
                modifier := modifiers[parameterIndex]
                isByRefParameter = modifier == Ast.ParameterModifier.Ref || modifier == Ast.ParameterModifier.Out
            }

            // BOTH SPELLINGS OF A BY-REFERENCE PARAMETER. `ref p: T` carries its shell in the
            // modifier and `p: &T` in the type, and either callee may write the caller's storage, so
            // the argument's null state after the call is the declared storage type's — `T`, never
            // the `&T` shell, which has no null state of its own.
            declaredParameterType := parameterTypes[parameterIndex]
            byRefParameter := declaredParameterType as ByRefTypeInfo
            if byRefParameter != null {
                isByRefParameter = true
                declaredParameterType = byRefParameter.InnerType
            }

            parameterFlowFacts := NullabilityFlowFacts.None()
            if flowFactsByParameter != null && parameterIndex < flowFactsByParameter.Count {
                parameterFlowFacts = flowFactsByParameter[parameterIndex]
            }

            if !isByRefParameter && parameterFlowFacts == NullabilityFlowFacts.None() {
                continue
            }

            parameterType := declarationContext.ResolveDeclaredAlias(AnalyzerSyntheticCallFacts.ApplyGenericBindings(declaredParameterType, genericBindings, NullabilityGenericSubstitution.LiftedTypeParameterNames(functionType.GenericConstraints)))
            postconditions.AddArgumentFacts(facts, call.Arguments[currentArgument], parameterType, isByRefParameter, parameterFlowFacts)
        }

        postconditions.AddMemberPostconditions(call, functionType.MemberNullabilityPostconditions, functionType.SourceIsStatic, functionType.SourceContainingType, facts)
        postconditions.Commit(call, facts)
        RecordCallTermination(functionType, call, parameterIndexByArgument, expectedCount)
    }

    // WHETHER THIS CALL ENDS THE PATH IT IS WRITTEN ON, read off the same binding the argument checks
    // used. `[DoesNotReturn]` on the declaration ends it outright; a `[DoesNotReturnIf(b)]` parameter
    // ends it on one branch, and the argument that landed on that parameter is what the surviving
    // flow is narrowed by.
    func RecordCallTermination(functionType: FunctionTypeInfo, call: CallExpression, parameterIndexByArgument: int[], expectedCount: int) {
        reachabilityByParameter := functionType.ParameterReachabilityFacts
        guardArgument: Expression? = null
        guardFacts := ReachabilityFlowFacts.None()
        if reachabilityByParameter != null {
            argumentIndex := 0
            while argumentIndex < call.Arguments.Count && guardArgument == null {
                currentArgument := argumentIndex
                argumentIndex = argumentIndex + 1
                parameterIndex := parameterIndexByArgument[currentArgument]
                if parameterIndex < 0 || parameterIndex >= expectedCount || parameterIndex >= reachabilityByParameter.Count {
                    continue
                }

                parameterFacts := reachabilityByParameter[parameterIndex]
                if parameterFacts == ReachabilityFlowFacts.None() {
                    continue
                }

                guardArgument = call.Arguments[currentArgument].Value
                guardFacts = parameterFacts
            }
        }

        methodFacts := ReachabilityFlowFacts.None()
        if functionType.DoesNotReturn {
            methodFacts = ReachabilityFlowFacts.DoesNotReturn()
        }

        terminatingCalls.Commit(call, methodFacts, guardArgument, guardFacts)
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
        ReportWrongArgumentType(functionType, call, functionName, argumentIndex, parameterIndex, expectedType, argType, null, null)
    }

    func ReportWrongArgumentType(functionType: FunctionTypeInfo, call: CallExpression, functionName: string, argumentIndex: int, parameterIndex: int, expectedType: TypeInfo, argType: TypeInfo, metadataContext: string?, metadataHint: string?) {
        span := spans.GetExpressionDiagnosticSpan(call.Arguments[argumentIndex].Value)
        if assignability.EnforcesReferencedNullability {
            sourceContext := NullabilityMetadataCore.ReferencedNullabilityContext(argType)
            if sourceContext != null {
                if metadataContext == null {
                    metadataContext = sourceContext
                } else {
                    metadataContext = sourceContext + " " + metadataContext
                }

                if metadataHint == null {
                    metadataHint = AnalyzerDiagnosticSpanFacts.ReferencedNullabilityHint(call.Arguments[argumentIndex].Value)
                }
            }
        }

        parameterName: string? = null
        parameterNames := functionType.ParameterNames
        if parameterNames != null && parameterIndex < parameterNames.Count {
            parameterName = parameterNames[parameterIndex]
        }

        parameterNameText := ""
        if parameterName != null {
            parameterNameText = parameterName
        }

        // THE TWO NAMES ARE RENDERED AS A PAIR. "Cannot pass Range as argument for parameter r of
        // type Range" is a sentence that states a contradiction and tells the reader nothing; when
        // the argument and the parameter are DIFFERENT types that share a simple name, both are
        // spelled with their namespaces. This site's own renderings are the baseline, because a
        // delegate signature and a method-group phrase are spelled here and not by `ToString`.
        expectedTypeText := ""
        argumentTypeText := ""
        TypeMismatchDisplay.Qualify(declarationContext, argType, expectedType, DescribeTypeForDiagnostic(argType), DescribeTypeForDiagnostic(expectedType), out argumentTypeText, out expectedTypeText)

        conversion := assignability.ClassifyUserDefinedConversion(expectedType, argType)
        if diagnostics.ReportAmbiguousUserDefinedConversion(conversion, argumentTypeText, expectedTypeText, span.Line, span.Column, span.Length) {
            return
        }

        byReferenceHint := BareByReferenceArgumentHint(functionType, call.Arguments[argumentIndex], parameterIndex, expectedType, argType)
        filePath := ""
        snippet := ""
        if TryGetRichContext(span.Line, out filePath, out snippet) && parameterName != null {
            // The rich shape names the argument the way this site describes it — a METHOD GROUP is a
            // phrase, not a type name, and stays exactly as written. An ordinary type name is the
            // one the pair already decided, so both halves of the report agree.
            argumentDisplayName := GetArgumentTypeDiagnosticName(call.Arguments[argumentIndex], argType)
            if argumentDisplayName == DescribeTypeForDiagnostic(argType) {
                argumentDisplayName = argumentTypeText
            }

            built := ErrorMessageBuilder.WrongArgumentType(filePath, span.Line, span.Column, snippet, span.Length, functionName, argumentIndex + 1, parameterNameText, argumentDisplayName, expectedTypeText, metadataContext, metadataHint)
            if byReferenceHint != null {
                built.ContextualHint = byReferenceHint
            }

            diagnostics.ReportBuilt(built)
            return
        }

        argumentDescription := "Argument " + (argumentIndex + 1).ToString()
        argumentName := call.Arguments[argumentIndex].Name
        if argumentName != null {
            argumentDescription = "Argument '" + argumentName + "'"
        }

        actualType := FormatArgumentTypeDiagnosticPhrase(call.Arguments[argumentIndex], argType)
        suggestion := "Pass a value with the expected type, or update the function signature."
        if byReferenceHint != null {
            suggestion = byReferenceHint
        }

        message := ErrorMessageBuilder.WrongArgumentTypeMessage(argumentDescription, functionName, actualType, parameterName, expectedTypeText)
        if metadataContext != null {
            message = message + ". " + metadataContext
            if metadataHint != null {
                suggestion = metadataHint
            }
        }

        diagnostics.Report(ErrorCode.TypeMismatch, message, span.Line, span.Column, suggestion, span.Length)
    }

    // A BARE ARGUMENT WHERE THE PARAMETER TAKES A REFERENCE, and the storage it names is the right
    // type — the one mismatch whose fix is a keyword, not a conversion. Every by-reference argument
    // says so at the call (`ref x`, `out x`), so the reader sees that the callee may write the
    // caller's storage; that includes a by-reference parameter passed on, which inside its own body
    // is the storage it reaches. `ref`/`out` parameters and `&T` ones read alike here, since both
    // arrive as a `&T` expected type; the keyword is the one the parameter was declared with.
    func BareByReferenceArgumentHint(functionType: FunctionTypeInfo, argument: Argument, parameterIndex: int, expectedType: TypeInfo, argType: TypeInfo): string? {
        expectedByRef := expectedType as ByRefTypeInfo
        if expectedByRef == null || argument.Modifier != ArgumentModifier.None || argType as ByRefTypeInfo != null {
            return null
        }

        if !assignability.IsAssignable(expectedByRef.InnerType, argType) {
            return null
        }

        keyword := "ref"
        modifiers := functionType.ParameterModifiers
        if modifiers != null && parameterIndex >= 0 && parameterIndex < modifiers.Count && modifiers[parameterIndex] == Ast.ParameterModifier.Out {
            keyword = "out"
        }

        written := "the argument"
        identifier := argument.Value as IdentifierExpression
        if identifier != null {
            written = "`" + identifier.Name + "`"
        }

        return "This parameter takes the caller's storage by reference, so the call must say so: write `" + keyword + "` before " + written + "."
    }

    // NL208. A type parameter nothing bound is SKIPPED rather than reported: an open binding means
    // inference had nothing to go on, and a constraint report there would name a type the user never
    // wrote. Every violated arm reports independently, so one argument can carry several.
    // NL207 FOR A CALL'S TYPE-ARGUMENT LIST. A declaration fixes how many type arguments its name
    // takes, and a non-generic one takes none. Written type arguments are ALL-OR-NOTHING: a call that
    // writes some but not all of them has no rule for which parameters it named, so a partial list is
    // as wrong as a long one. Without this the wrong count reached emission, where it could only
    // decline as an unmodeled shape (NL103) — the same failure NL207 already reports for a type's
    // argument list, said in the same words.
    func ValidateWrittenTypeArgumentCount(functionType: FunctionTypeInfo, call: CallExpression, functionName: string): bool {
        writtenTypeArguments := call.TypeArguments
        if writtenTypeArguments == null || writtenTypeArguments.Count == 0 {
            return true
        }

        declaredCount := 0
        typeParameters := functionType.TypeParameters
        if typeParameters != null {
            declaredCount = typeParameters.Count
        }

        if declaredCount == writtenTypeArguments.Count {
            return true
        }

        span := spans.GetCallDiagnosticSpan(call, functionName)
        if declaredCount == 0 {
            diagnostics.Report(
                ErrorCode.InvalidTypeArgument,
                "'" + functionName + "' is not generic, but " + writtenTypeArguments.Count.ToString() + " type argument(s) were provided",
                span.Line,
                span.Column,
                "Remove the type arguments: '" + functionName + "'",
                span.Length
            )
            return false
        }

        diagnostics.Report(
            ErrorCode.InvalidTypeArgument,
            "Generic method '" + functionName + "' takes " + declaredCount.ToString() + " type argument(s), but " + writtenTypeArguments.Count.ToString() + " were provided",
            span.Line,
            span.Column,
            "Write one type argument per type parameter, or omit the list entirely and let it be inferred.",
            span.Length
        )
        return false
    }

    func ValidateGenericConstraints(functionType: FunctionTypeInfo, call: CallExpression, bindings: Dictionary<string, TypeInfo>?) {
        constraints := functionType.GenericConstraints
        if constraints == null || bindings == null || bindings.Count == 0 {
            return
        }

        functionName := AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(functionType, call)
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

            // The predicates and the sentence are `AnalyzerGenericConstraintChecks`, shared with the
            // TYPE-argument reporter so a violation reads identically wherever it is written.
            specialKind := AnalyzerGenericConstraintChecks.SpecialViolationKind(specialValue, boundType)
            if specialKind != AnalyzerGenericConstraintChecks.ViolationNone() {
                diagnostics.Report(ErrorCode.GenericConstraintViolation, AnalyzerGenericConstraintChecks.SpecialViolationMessage(specialKind, boundText, constraint.TypeParameter, functionName), span.Line, span.Column, AnalyzerGenericConstraintChecks.CallSuggestion(specialKind, boundText, constraint.TypeParameter, functionName), span.Length)
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
                    diagnostics.Report(ErrorCode.GenericConstraintViolation, AnalyzerGenericConstraintChecks.TypeConstraintMessage(boundText, closedText, constraint.TypeParameter, functionName), span.Line, span.Column, AnalyzerGenericConstraintChecks.CallTypeConstraintSuggestion(boundText, closedText, functionName), span.Length)
                }
            }
        }
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
        return AnalyzerSyntheticCallFacts.ApplyGenericBindings(returnType, genericBindings, NullabilityGenericSubstitution.LiftedTypeParameterNames(functionType.GenericConstraints))
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
        for argType in argTypes {
            argumentTypeObject := argType as object
            argumentTypes.Add(argumentTypeObject.ToString())
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
        metadataContext: string? = null
        metadataHint: string? = null
        if assignability.EnforcesReferencedNullability {
            metadataParts := new List<string>()
            argumentIndex := 0
            while argumentIndex < argTypes.Count {
                argumentType := argTypes[argumentIndex]
                argumentContext := NullabilityMetadataCore.ReferencedNullabilityContext(argumentType)
                if argumentContext != null {
                    metadataParts.Add(argumentContext)
                    if metadataHint == null && argumentIndex < call.Arguments.Count {
                        metadataHint = AnalyzerDiagnosticSpanFacts.ReferencedNullabilityHint(call.Arguments[argumentIndex].Value)
                    }
                }
                argumentIndex = argumentIndex + 1
            }
            if metadataParts.Count > 0 {
                metadataContext = string.Join(" ", metadataParts)
            }
        }
        if TryGetRichContext(span.Line, out filePath, out snippet) {
            diagnostics.ReportBuilt(ErrorMessageBuilder.NoMatchingOverload(filePath, span.Line, span.Column, snippet, span.Length, functionName, call.Arguments.Count, argumentTypes, candidateSignatures, metadataContext, metadataHint))
            return
        }

        message := "No overload of '" + functionName + "' accepts " + call.Arguments.Count.ToString() + " argument(s) with these types"
        if metadataContext != null {
            message = message + ". " + metadataContext
        }
        suggestion := metadataHint ?? "Check the argument count and types against the available overloads."
        diagnostics.Report(ErrorCode.NoMatchingOverload, message, span.Line, span.Column, suggestion, span.Length)
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

        return DescribeTypeForDiagnostic(argumentType)
    }

    // A TYPE AS A READER SEES IT. Every `TypeInfo` renders through its own `ToString`, except a
    // FUNCTION type: that class has none, so a mismatch between two delegate signatures used to say
    // `NSharpLang.Compiler.FunctionTypeInfo` on BOTH sides of the report and tell the reader nothing
    // at all. The structural renderer already exists for hover and nullability text — `(int) -> bool`
    // — and this is the one place a diagnostic asks it for a signature.
    static func DescribeTypeForDiagnostic(candidate: TypeInfo): string {
        functionType := candidate as FunctionTypeInfo
        if functionType != null {
            return NullabilityTypeDisplay.FormatFunctionType(functionType)
        }

        candidateObject := candidate as object
        rendered := candidateObject.ToString()
        if rendered == null {
            return "unknown"
        }

        return rendered
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
