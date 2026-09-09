namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// The two lists a condition yields: what it proves when it is TRUE, and what it proves when it is
// FALSE. They are returned together because a caller almost always needs both — the then-branch
// scope takes one, the else-branch scope takes the other, and a guard clause whose taken branch
// exits installs the OPPOSITE one into the surviving flow.
class FlowNarrowingSplit {
    thenValue: List<FlowNarrowing>
    elseValue: List<FlowNarrowing>

    Then: List<FlowNarrowing> => thenValue
    Else: List<FlowNarrowing> => elseValue

    constructor(thenNarrowings: List<FlowNarrowing>, elseNarrowings: List<FlowNarrowing>) {
        thenValue = thenNarrowings
        elseValue = elseNarrowings
    }
}

// WHAT A CONDITION PROVES ABOUT THE CODE IT GUARDS — the producer side of every flow fact the
// analyzer holds, and the writer that installs one into a scope.
//
// EXTRACTION AND APPLICATION ARE SEPARATE ON PURPOSE. A condition yields TWO narrowing lists, one
// for the branch it is true in and one for the branch it is false in, and the caller decides which
// list to install where — the then-branch scope, the else-branch scope, or, for a guard clause
// whose taken branch always returns, the SURVIVING flow after the `if`. That last case is why
// extraction cannot install anything itself: `if x == null { return }` narrows the code AFTER the
// statement, not the code inside it.
//
// THE FOUR CONDITION SHAPES, and the negation rules are what make them non-obvious. `x != null`
// proves not-null when true and null when false; `x == null` is the mirror. `a && b` proves both
// sides in the TRUE branch and NOTHING in the false branch, because the negation of a conjunction
// is a disjunction and a disjunction proves nothing about either side. `a || b` is the mirror: it
// proves both negations in the FALSE branch and nothing in the true one. `x is T` proves T in the
// true branch, and — only when the tested value is an ANONYMOUS UNION — proves the union MINUS the
// matched arm in the false branch. `x.HasValue` proves the nullable's inner type.
//
// THE ARM SUBTRACTION IS ASSIGNABILITY, NOT IDENTITY. An arm is removed when the matched type is
// assignable to it, so testing a base type removes every derived arm. Removing every arm leaves
// `never`; removing all but one collapses to that one rather than to a one-armed union; and
// removing NONE means the test told us nothing and the else-branch gets no narrowing at all.
//
// INSTALLATION INTERSECTS RATHER THAN OVERWRITES. Two conditions can narrow the same name — an
// `&&` chain does it routinely — and the MORE SPECIFIC type wins regardless of which came last.
// Unrelated types keep the newer one, because a later condition is the more recent statement about
// the value. A null fact is installed for every path; a TYPE narrowing is installed only for a
// simple name, because a member path's declared member type is not the scope's to rewrite.
class AnalyzerFlowNarrowing {
    scopesValue: AnalyzerScopeStack
    typeResolverValue: AnalyzerTypeResolver
    assignabilityValue: AnalyzerAssignability

    constructor(scopes: AnalyzerScopeStack, typeResolver: AnalyzerTypeResolver, assignability: AnalyzerAssignability) {
        scopesValue = scopes
        typeResolverValue = typeResolver
        assignabilityValue = assignability
    }

    // Applies narrowings to the current scope, intersecting duplicate symbols
    // (keeping the most specific/derived type rather than last-one-wins).
    func ApplyNarrowingsToScope(narrowings: List<FlowNarrowing>) {
        currentScope := scopesValue.Peek()
        for narrowing in narrowings {
            nullState := narrowing.NullState
            currentScope.NullStates[narrowing.Path] = nullState
            if nullState == NullState.Null {
                scopesValue.MarkErrorTupleResultsAvailableForError(narrowing.Path)
            }

            // Type narrowings currently apply to simple symbols. Stable member-path
            // null facts are tracked above without rewriting the declared member type.
            //
            // The narrowed type is read through a POSITIVE guard rather than an early `continue`,
            // because N# narrows on `if x != null { … }` and does not carry the fact across a
            // `continue`. Same condition, same order, one nesting level deeper.
            narrowedType := narrowing.NarrowedType
            if narrowedType != null && !narrowing.Path.Contains(".", StringComparison.Ordinal) {
                name := narrowing.Path
                existing := new TypeInfo()
                if currentScope.Symbols.TryGetValue(name, out existing) {
                    // If new type is more specific (subtype of existing), use it.
                    // If existing is more specific (subtype of new), keep existing.
                    // Otherwise (unrelated types), keep the new one (it came from a later condition).
                    if assignabilityValue.IsSubtypeOf(narrowedType, existing) {
                        currentScope.Symbols[name] = narrowedType
                    } else if !assignabilityValue.IsSubtypeOf(existing, narrowedType) {
                        currentScope.Symbols[name] = narrowedType
                    }
                } else {
                    currentScope.Symbols[name] = narrowedType
                }
            }
        }
    }

    // Extracts flow-sensitive type narrowings from a condition expression.
    // Returns separate narrowing lists for then-branch and else-branch.
    // Handles: null checks (!=null, ==null), is-type patterns, and && chains.
    func ExtractFlowNarrowings(condition: Expression): FlowNarrowingSplit {
        thenNarrowings := new List<FlowNarrowing>()
        elseNarrowings := new List<FlowNarrowing>()

        binary := condition as BinaryExpression
        isExpr := condition as IsExpression
        if binary != null {
            // x != null → narrow x to non-nullable in then-branch
            if binary.Operator == BinaryOperator.NotEqual {
                TryExtractNullNarrowing(binary.Left, binary.Right, thenNarrowings, elseNarrowings, true)
                TryExtractNullNarrowing(binary.Right, binary.Left, thenNarrowings, elseNarrowings, true)
            } else if binary.Operator == BinaryOperator.Equal {
                // x == null → narrow x to non-nullable in else-branch
                TryExtractNullNarrowing(binary.Left, binary.Right, thenNarrowings, elseNarrowings, false)
                TryExtractNullNarrowing(binary.Right, binary.Left, thenNarrowings, elseNarrowings, false)
            } else if binary.Operator == BinaryOperator.And {
                // a && b → both sides hold in then-branch; else = !a || !b (can't narrow)
                leftSplit := ExtractFlowNarrowings(binary.Left)
                rightSplit := ExtractFlowNarrowings(binary.Right)
                thenNarrowings.AddRange(leftSplit.Then)
                thenNarrowings.AddRange(rightSplit.Then)
            } else if binary.Operator == BinaryOperator.Or {
                // else-branch gets nothing for compound && (negation is disjunction)

                // a || b → both sides must be false in else-branch; then = a || b (can't narrow)
                leftSplit := ExtractFlowNarrowings(binary.Left)
                rightSplit := ExtractFlowNarrowings(binary.Right)
                elseNarrowings.AddRange(leftSplit.Else)
                elseNarrowings.AddRange(rightSplit.Else)
            }
        } else if isExpr != null {
            // then-branch gets nothing for compound || (only one side needs to be true)

            // x is Type varName → narrow/declare in then-branch
            narrowedType := typeResolverValue.ResolveType(isExpr.Type)
            variableName := isExpr.VariableName
            testedPath := AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(isExpr.Expression)
            if variableName != null {
                // `x is Dog d` — declare d: Dog in then-branch
                thenNarrowings.Add(new FlowNarrowing(variableName, narrowedType, NullState.NotNull))
                if testedPath != null && !testedPath.Contains(".", StringComparison.Ordinal) {
                    sourceUnion := scopesValue.LookupSymbol(testedPath) as AnonymousUnionTypeInfo
                    if sourceUnion != null {
                        remainingType := TryRemoveAnonymousUnionArm(sourceUnion, narrowedType)
                        if remainingType != null {
                            elseNarrowings.Add(new FlowNarrowing(testedPath, remainingType, NullState.NotNull))
                        }
                    }
                }
            } else if testedPath != null {
                // `x is Dog` — narrow x to Dog in then-branch
                thenNarrowings.Add(new FlowNarrowing(testedPath, narrowedType, NullState.NotNull))
                if !testedPath.Contains(".", StringComparison.Ordinal) {
                    sourceUnion := scopesValue.LookupSymbol(testedPath) as AnonymousUnionTypeInfo
                    if sourceUnion != null {
                        remainingType := TryRemoveAnonymousUnionArm(sourceUnion, narrowedType)
                        if remainingType != null {
                            elseNarrowings.Add(new FlowNarrowing(testedPath, remainingType, NullState.NotNull))
                        }
                    }
                }
            }
        } else {
            hasValueAccess := condition as MemberAccessExpression
            if hasValueAccess != null {
                if TryExtractHasValueNarrowing(hasValueAccess, thenNarrowings) {
                }
            } else {
                negation := condition as UnaryExpression
                if negation != null && negation.Operator == UnaryOperator.Not {
                    negatedHasValue := negation.Operand as MemberAccessExpression
                    if negatedHasValue != null {
                        if TryExtractHasValueNarrowing(negatedHasValue, elseNarrowings) {
                        }
                    }
                }
            }
        }

        return new FlowNarrowingSplit(thenNarrowings, elseNarrowings)
    }

    func TryRemoveAnonymousUnionArm(sourceUnion: AnonymousUnionTypeInfo, matchedType: TypeInfo): TypeInfo? {
        remaining := new List<TypeInfo>()
        for arm in sourceUnion.Arms {
            if !assignabilityValue.IsAssignable(matchedType, arm) {
                remaining.Add(arm)
            }
        }

        if remaining.Count == sourceUnion.Arms.Count {
            return null
        }

        if remaining.Count == 0 {
            return BuiltInTypes.Never
        }

        if remaining.Count == 1 {
            return remaining[0]
        }

        return new AnonymousUnionTypeInfo(remaining)
    }

    // One side of an equality against `null`. The OTHER side must be the literal, which is what
    // makes this callable twice with the operands swapped rather than needing to know which side
    // the reader wrote the literal on.
    func TryExtractNullNarrowing(expr: Expression, other: Expression, thenNarrowings: List<FlowNarrowing>, elseNarrowings: List<FlowNarrowing>, notEqual: bool) {
        nullLiteral := other as NullLiteralExpression
        if nullLiteral == null {
            return
        }

        path := AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(expr)
        if path == null {
            return
        }

        if notEqual {
            thenNarrowings.Add(new FlowNarrowing(path, null, NullState.NotNull))
            elseNarrowings.Add(new FlowNarrowing(path, null, NullState.Null))
        } else {
            thenNarrowings.Add(new FlowNarrowing(path, null, NullState.Null))
            elseNarrowings.Add(new FlowNarrowing(path, null, NullState.NotNull))
        }
    }

    func TryExtractHasValueNarrowing(memberAccess: MemberAccessExpression, narrowings: List<FlowNarrowing>): bool {
        identifier := memberAccess.Object as IdentifierExpression
        if memberAccess.MemberName != "HasValue" || identifier == null {
            return false
        }

        symbolType := scopesValue.LookupSymbol(identifier.Name)
        nullable := symbolType as NullableTypeInfo
        if nullable == null {
            return false
        }

        narrowings.Add(new FlowNarrowing(identifier.Name, nullable.InnerType, NullState.NotNull))
        return true
    }
}
