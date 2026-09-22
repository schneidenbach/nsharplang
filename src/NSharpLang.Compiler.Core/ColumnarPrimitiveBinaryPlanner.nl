namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// Direct schema-v3 owner for the modelled primitive binary families: arithmetic (+ - * / %),
// bitwise (& | ^), shifts (<< >>), ordering (< > <= >=), and equality (== !=) over the exact
// numeric surface the CLR runs without conversions, plus decimal operator statics, string
// concatenation, and one exact source-declared `+` operator. Every operand pair that does not
// reduce to that surface — mixed numeric widening, string chains, string/char concatenation,
// string/Type/enum/record equality, unselected source operators, and the short-circuit / coalesce
// families — remains a whole-subtree boundary served by its existing owner. Malformed syntax in an
// admitted family rolls the candidate back to an empty, NotOwned plan.
class ColumnarPrimitiveBinaryPlanner {

    // Root front-door gate: a two-operand binary whose operator text is one of the claimed
    // families. Short-circuit `&&`/`||` and coalesce `??` are deliberately excluded so they route
    // straight to their legacy owner.
    static func MayPlanRoot(nodes: ColumnarNodeTable, source: string, node: int): bool {
        if nodes == null || source == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        candidate := ColumnarPlannerSupport.UnwrapParenthesesInRange(nodes, node)
        if candidate < 0 || nodes.Kind(candidate) != ColumnarExpressionNodeKind.BinaryExpression() || nodes.ChildCount(candidate) != 2 {
            return false
        }
        return IsClaimedOperatorText(nodes, source, candidate)
    }

    // Root ownership seam consumed by the emitter front door. A planned root claims the whole node;
    // any decline is a NotOwned whole-subtree exit (never terminal) so the legacy arm can serve the
    // string-chain, string/char, mixed-numeric, and non-numeric-equality forms outside this slice.
    static func TryEmitRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, il: ILGenerator, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        nsharpOwned = false
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if Plan(nodes, source, node, bindings, handles, plan) != ColumnarFragmentPlanStatus.Planned {
            legacyWholeSubtreePlanning = true
            return false
        }

        nsharpOwned = true
        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = ColumnarPlannerSupport.RequiredResultType(plan, "primitive binary expression")
        return true
    }

    static func TryGetTypeRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        nsharpOwned = false
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if Plan(nodes, source, node, bindings, handles, plan) != ColumnarFragmentPlanStatus.Planned {
            legacyWholeSubtreePlanning = true
            return false
        }

        nsharpOwned = true
        resultType = ColumnarPlannerSupport.RequiredResultType(plan, "primitive binary expression")
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateRootInputs(nodes, source, node, bindings, handles, plan)
        plan.PrepareV3()
        resultType := typeof(int)
        if !TryAppendRoot(nodes, source, node, bindings, handles, plan, out resultType) {
            return plan.Status
        }

        plan.CompleteV3(resultType)
        return plan.Status
    }

    // THE ROOT-APPEND SEQUENCE, OWNED ONCE (015-B9) — the same factoring `015-B7` applied to the
    // direct-call owner, for the same reason. A binary root is an admission test, a checkpoint, a root
    // fragment, the append and the fragment's completion; whether the plan around it is a standalone
    // schema-v3 expression (`Plan` wraps this between `PrepareV3` and `CompleteV3`) or an open schema-v4
    // METHOD BODY (`ColumnarMethodBodyPlanner`'s expression door calls it directly) is the wrapper's
    // business, not the sequence's. Both callers therefore produce the SAME row sequence, which is the
    // whole of producing the same bytes.
    //
    // Byte identity for a claimed binary is against ONE owner, and the route is measured rather than
    // assumed: `ColumnarIlEmitter.EmitExpressionCore` offers four pre-cascade owners first (boolean,
    // unary-literal, scalar-literal, `nameof`) and none has a binary arm, then
    // `ColumnarRangeIndexPlanner.TryEmitFromFacts` answers `FacadeRootMayNeedFacts` for kind 12 with THIS
    // class's `MayPlanRoot`, and inside the cascade the construction arm answers only 15/36/58 and the
    // direct-call arm only kind 9 — so the THIRD arm, `TryEmitRoot`, owns every claimed-operator binary
    // root. `&&`/`||` are not claimed operators here; they are the conditional owner's roots, and the
    // same `IsAdmittedSyntax` that refuses them for `Plan` refuses them for the door.
    //
    // The null contract is the softer one the second caller needs: `Plan` still THROWS through
    // `ValidateRootInputs` before it gets here, so its behaviour is unchanged, and a door that hands this
    // a null table declines instead of crashing.
    static func TryAppendRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || handles == null || plan == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParenthesesInRange(nodes, node)
        if candidate < 0 || !IsAdmittedSyntax(nodes, source, candidate, 0) {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(-1, ColumnarExpressionNodeKind.BinaryExpression(), candidate)
            nestedOwnership := ColumnarDirectCallOwnership.NotOwned
            if !TryAppend(nodes, source, candidate, bindings, handles, plan, fragment, 0, out resultType, out nestedOwnership) {
                plan.Rollback(checkpoint)
                return false
            }

            plan.CompleteFragment(fragment, resultType)
            return true
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    static func IsAdmittedSyntax(nodes: ColumnarNodeTable, source: string, node: int, depth: int): bool {
        if nodes == null || source == null || depth > 200 {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParenthesesInRange(nodes, node)
        if candidate < 0 || nodes.Kind(candidate) != ColumnarExpressionNodeKind.BinaryExpression() || nodes.ChildCount(candidate) != 2 || !IsClaimedOperatorText(nodes, source, candidate) {
            return false
        }

        return IsAdmittedOperandSyntax(nodes, source, nodes.Child(candidate, 0), depth + 1) && IsAdmittedOperandSyntax(nodes, source, nodes.Child(candidate, 1), depth + 1)
    }

    // Append to an already-open binary fragment. A decline is atomic and does not claim mixed
    // primitive pairs, unselected source-operator families, or the non-numeric equality forms.
    static func TryAppend(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        ValidateAppendInputs(nodes, source, node, bindings, handles, plan, parentFragment)
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        candidate := ColumnarPlannerSupport.UnwrapParenthesesInRange(nodes, node)
        if candidate < 0 || !IsAdmittedSyntax(nodes, source, candidate, depth) {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            leftType := typeof(int)
            leftOwnership := ColumnarDirectCallOwnership.NotOwned
            if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(candidate, 0), bindings, handles, plan, parentFragment, depth + 1, out leftType, out leftOwnership) {
                if leftOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                    nestedOwnership = leftOwnership
                }
                plan.Rollback(checkpoint)
                return false
            }

            rightType := typeof(int)
            rightOwnership := ColumnarDirectCallOwnership.NotOwned
            // An unsuffixed int literal RIGHT operand adopts an exact uint/long/ulong LEFT
            // operand's type before the ordinary operand path runs; a declined adoption leaves
            // the plan untouched so the literal still plans as its own Int32 type below. Shift
            // operators are excluded: their right operand is a shift COUNT that is always Int32 and
            // must never take the left's type, so their count keeps the ordinary operand path.
            adopted := false
            if !IsShiftOperator(nodes, source, candidate) {
                adopted = TryAppendAdoptedIntegerLiteral(nodes, source, nodes.Child(candidate, 1), leftType, plan, parentFragment, depth + 1, out rightType)
            }
            if !adopted && !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(candidate, 1), bindings, handles, plan, parentFragment, depth + 1, out rightType, out rightOwnership) {
                if rightOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                    nestedOwnership = rightOwnership
                }
                plan.Rollback(checkpoint)
                return false
            }

            // THE CONSTANT CONVERSION IS SYMMETRIC, AND THE SECOND PASS IS WHAT MAKES IT SO.
            //
            // `mask & 0xFF` adopts on the way down, because the left operand's type is already known
            // when the literal is reached. `0xFF & mask` cannot: a plan is written left to right, so
            // the literal's type is committed before the operand that would decide it exists. The
            // analyzer accepts both — §10.2.11 does not care which side the constant is written on —
            // so the planner replans rather than declining a program the front end admitted. The
            // retry is ATOMIC: the checkpoint rolls the whole pair away and both operands are
            // appended again, with the literal adopting the type the first pass discovered.
            if !adopted && !IsShiftOperator(nodes, source, candidate) && leftType == typeof(int) && rightType != typeof(int) {
                retriedLeftType := typeof(int)
                retriedRightType := typeof(int)
                replanFailed := false
                if TryReplanWithAdoptedLeftLiteral(nodes, source, candidate, rightType, bindings, handles, plan, parentFragment, depth, checkpoint, out retriedLeftType, out retriedRightType, out replanFailed) {
                    leftType = retriedLeftType
                    rightType = retriedRightType
                } else if replanFailed {
                    plan.Rollback(checkpoint)
                    return false
                }
            }

            // Shifts keep each operand's own type: the value is int/uint/long/ulong, the count is
            // int, and the result is the value's type. They never reduce to the unified opType path.
            if HasExactOperatorText(nodes, source, candidate, "<<") || HasExactOperatorText(nodes, source, candidate, ">>") {
                if TryAppendShift(nodes, source, candidate, leftType, rightType, plan, out resultType) {
                    return true
                }
                plan.Rollback(checkpoint)
                return false
            }

            // Binary numeric promotion (ECMA §12.4.7): char and the small integral types share the
            // Int32 stack slot, so any mix of them runs as int; the wider primitives must match
            // exactly. Every retained numeric family keys off this single unified operation type.
            opType := typeof(int)
            opTypeResolved := false
            if leftType == rightType {
                opType = leftType
                opTypeResolved = true
            } else if ColumnarNumericFacts.IsIntPromotable(leftType) && ColumnarNumericFacts.IsIntPromotable(rightType) {
                opType = typeof(int)
                opTypeResolved = true
            }

            planned := false
            if opTypeResolved {
                if HasExactOperatorText(nodes, source, candidate, "+") && opType == typeof(string) {
                    methodIndex := plan.AddMethod(RequiredStringConcat())
                    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
                    resultType = typeof(string)
                    planned = true
                } else if opType == typeof(decimal) {
                    planned = TryAppendDecimalOperator(nodes, source, candidate, plan, out resultType)
                } else if IsArithmeticOperator(nodes, source, candidate) {
                    planned = TryAppendArithmetic(nodes, source, candidate, opType, bindings, plan, out resultType)
                } else if IsBitwiseOperator(nodes, source, candidate) {
                    planned = TryAppendBitwise(nodes, source, candidate, opType, plan, out resultType)
                } else if IsOrderingOperator(nodes, source, candidate) {
                    planned = TryAppendOrdering(nodes, source, candidate, opType, plan, out resultType)
                } else if IsEqualityOperator(nodes, source, candidate) {
                    planned = TryAppendEquality(nodes, source, candidate, opType, plan, out resultType)
                }
            }

            if planned {
                return true
            }

            // A USER-DEFINED OPERATOR DECLARED BY AN EXTERNAL TYPE. The predefined families above have
            // already declined the pair, which is exactly C#'s ordering: a predefined operator wins for
            // the types that have one, and everything else asks the operand types what they declare.
            // Both operands are already appended, so only an operator whose parameters match them
            // EXACTLY can be planned -- a conversion would have to reach a value the plan has already
            // sealed into its own fragment. A pair that needs one is a whole-subtree exit, and the
            // emitter's preflighting arm serves it with the conversion in place.
            // Both operands being IL primitives is the predefined surface's business -- the same refusal
            // the emitter's arms make -- so `s1 == s2` stays the string-equality owner's, not
            // `String.op_Equality`'s.
            runtimeSelection := ColumnarRuntimeOperatorResolver.ResolveBinary(nodes.Text(source, candidate), leftType, rightType)
            if runtimeSelection.IsSelected && !(ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(leftType) && ColumnarRuntimeOperatorResolver.IsIlPrimitiveOperandType(rightType)) {
                runtimeMethod := runtimeSelection.Method
                if runtimeMethod == null {
                    throw new InvalidOperationException("A selected runtime operator has no exact method handle.")
                }
                if ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(runtimeSelection.ParameterTypes[0], leftType) && ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(runtimeSelection.ParameterTypes[1], rightType) {
                    runtimeIndex := plan.AddMethodWithSignature(runtimeMethod, runtimeSelection.DeclaringType, runtimeSelection.ParameterTypes, runtimeSelection.ReturnType, true, false)
                    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), runtimeIndex)
                    resultType = runtimeSelection.ReturnType
                    return true
                }
            }

            // Only `+` selects one exact source-declared operator; every other operator over source
            // operands is a whole-subtree exit served by the legacy source-operator branch.
            if HasExactOperatorText(nodes, source, candidate, "+") {
                sourceSelection := ColumnarSourceOperatorResolver.ResolveBinary("+", leftType, rightType, bindings.SourceTypeDefinitions)
                if sourceSelection.IsSourceType {
                    if !sourceSelection.IsSelected {
                        plan.Rollback(checkpoint)
                        return false
                    }
                    method := sourceSelection.Method
                    if method == null {
                        throw new InvalidOperationException("A selected source addition operator has no exact method handle.")
                    }
                    methodIndex := plan.AddMethodWithSignature(method, sourceSelection.DeclaringType, sourceSelection.ParameterTypes, sourceSelection.ReturnType, true, false)
                    plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
                    resultType = sourceSelection.ReturnType
                    return true
                }
            }

            plan.Rollback(checkpoint)
            return false
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    // shl/shr/shr.un: an Int32/UInt32/Int64/UInt64 left operand shifted by an Int32 count. shr is the
    // signed (arithmetic) right shift for int/long; an UNSIGNED left uses shr.un so a high-bit value
    // zero-fills rather than sign-extends. `uint` is one of the four because C# has an operator for
    // it (`uint << int`) and because it shares Int32's stack slot, so its shift is the same
    // instruction with the unsigned right form — a left shift emits the same `shl` either way.
    static func TryAppendShift(nodes: ColumnarNodeTable, source: string, candidate: int, leftType: Type, rightType: Type, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if rightType != typeof(int) {
            return false
        }
        if leftType != typeof(int) && leftType != typeof(uint) && leftType != typeof(long) && leftType != typeof(ulong) {
            return false
        }

        if HasExactOperatorText(nodes, source, candidate, "<<") {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Shl())
        } else if leftType == typeof(ulong) || leftType == typeof(uint) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ShrUn())
        } else {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Shr())
        }
        resultType = leftType
        return true
    }

    // ONE OPERAND OF AN ADMITTED BINARY MAY BE AN INTEGER CONSTANT THAT ADOPTS THE OTHER'S TYPE —
    // ECMA-334 §10.2.11, the same rule the analyzer applies to the same pair. `u / 2` runs
    // uint/uint, `l != 0` runs long/long and `mask & 0xFF` runs ulong/ulong. Only uint, long and
    // ulong are adopted into, because only those three have no common type with `int` to fall back
    // on; everything narrower already promotes.
    //
    // WHAT COUNTS AS THE CONSTANT IS `ConstantConversionFacts`' ANSWER AND NOT A SECOND ONE. That
    // owner exists so the emitter, the planner and this adoption agree on which literals convert and
    // to what, INCLUDING its three deliberate caps below the spec's own ranges; asking it here also
    // ended a fourth divergence this arc found — the decimal-digit scan that used to gate the
    // adoption refused every hexadecimal constant, so `mask & 0xFF` declined at emit while
    // `mask & 255` planned.
    //
    // A negative literal arrives as unary minus over the bare literal and emits PRE-NEGATED with no
    // `neg` opcode. The adopted operand seals its own fragment with the target type, exactly as the
    // ordinary operand path does, so the unified operation type is the adopted one. Every decline is
    // mutation-free: no plan row is written before the adoption is fully admitted.
    static func TryAppendAdoptedIntegerLiteral(nodes: ColumnarNodeTable, source: string, node: int, targetType: Type, plan: ColumnarCodePlan, parentFragment: int, depth: int, out resultType: Type): bool {
        resultType = targetType
        value := 0L
        if !TryGetAdoptedIntegerLiteral(nodes, source, node, targetType, depth, out value) {
            return false
        }

        fragment := plan.BeginFragment(parentFragment, nodes.Kind(node), node)
        if targetType == typeof(uint) {
            valueIndex := plan.AddInt32((int)value)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
        } else {
            valueIndex := plan.AddInt64(value)
            plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), valueIndex)
        }

        plan.CompleteFragment(fragment, targetType)
        resultType = targetType
        return true
    }

    // WHETHER THIS OPERAND IS SUCH A CONSTANT, AND WHAT VALUE IT TAKES — a pure question, asked
    // before any plan row is written. The replanning arm needs it separately from the append,
    // because it must know the answer BEFORE it rolls a written pair away.
    static func TryGetAdoptedIntegerLiteral(nodes: ColumnarNodeTable, source: string, node: int, targetType: Type, depth: int, out value: long): bool {
        value = 0L
        if depth > 200 || node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        if targetType != typeof(uint) && targetType != typeof(long) && targetType != typeof(ulong) {
            return false
        }

        negative := false
        literalNode := node
        if nodes.Kind(node) == ColumnarExpressionNodeKind.UnaryExpression() && nodes.ChildCount(node) == 1 && nodes.Text(source, node) == "-" {
            negative = true
            literalNode = nodes.Child(node, 0)
        }
        if literalNode < 0 || literalNode >= nodes.Kinds.Length || nodes.Kind(literalNode) != ColumnarExpressionNodeKind.IntLiteralExpression() || nodes.ChildCount(literalNode) != 0 {
            return false
        }

        return ConstantConversionFacts.TryGetInRangeIntegralConstant(targetType, nodes.Text(source, literalNode), negative, out value)
    }

    // THE SECOND PASS, AND IT COMMITS TO NOTHING UNTIL THE ANSWER IS KNOWN. The probe runs over the
    // written literal alone, so a pair that cannot adopt is never rolled away; a pair that can is
    // replanned whole, and a replan that fails a step leaves the checkpoint restored and says so, so
    // the caller declines rather than continuing over a plan it half-wrote.
    static func TryReplanWithAdoptedLeftLiteral(nodes: ColumnarNodeTable, source: string, candidate: int, rightType: Type, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, checkpoint: ColumnarCodePlanCheckpoint, out leftType: Type, out replannedRightType: Type, out replanFailed: bool): bool {
        leftType = typeof(int)
        replannedRightType = rightType
        replanFailed = false

        probeValue := 0L
        if !TryGetAdoptedIntegerLiteral(nodes, source, nodes.Child(candidate, 0), rightType, depth + 1, out probeValue) {
            return false
        }

        plan.Rollback(checkpoint)
        adoptedLeftType := typeof(int)
        if !TryAppendAdoptedIntegerLiteral(nodes, source, nodes.Child(candidate, 0), rightType, plan, parentFragment, depth + 1, out adoptedLeftType) {
            replanFailed = true
            return false
        }

        retriedRightType := typeof(int)
        retriedOwnership := ColumnarDirectCallOwnership.NotOwned
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(candidate, 1), bindings, handles, plan, parentFragment, depth + 1, out retriedRightType, out retriedOwnership) {
            replanFailed = true
            return false
        }

        leftType = adoptedLeftType
        replannedRightType = retriedRightType
        return true
    }

    // add/sub/mul/div/rem over the int-promotable set, long, ulong, uint, double, or float. div/rem
    // are unsigned for uint/ulong; checked add/sub/mul select the overflow opcode variants for the
    // integral op types when the enclosing checked context is active. The int-promotable set
    // promotes its result to int; every wider op type keeps its own type.
    static func TryAppendArithmetic(nodes: ColumnarNodeTable, source: string, candidate: int, opType: Type, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        return TryAppendArithmeticOperator(OperatorText(nodes, source, candidate), opType, bindings, plan, out resultType)
    }

    // THE ARITHMETIC INSTRUCTION FOR ONE OPERATOR AND ONE OPERAND TYPE, with the operator given rather
    // than read out of a node. A binary expression reads it from its own node; a COMPOUND ASSIGNMENT
    // (`x += v`) has no such node to read — the operator lives in the assignment's own span — and
    // without this seam that caller would have to restate the opcode choice, which is exactly the
    // second owner this file exists to prevent. The body below is unchanged; only where the five
    // operator questions get their text moved.
    static func TryAppendArithmeticOperator(operatorText: string, opType: Type, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if opType == null || (!ColumnarNumericFacts.IsIntPromotable(opType) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(uint) && opType != typeof(double) && opType != typeof(float)) {
            return false
        }

        unsigned := opType == typeof(ulong) || opType == typeof(uint)
        integral := ColumnarNumericFacts.IsIntPromotable(opType) || opType == typeof(long) || opType == typeof(ulong) || opType == typeof(uint)
        isAdd := operatorText == "+"
        isSub := operatorText == "-"
        isMul := operatorText == "*"
        isDiv := operatorText == "/"
        isRem := operatorText == "%"
        checkedIntegral := bindings.OverflowCheckingEnabled && (isAdd || isSub || isMul) && integral

        opcode := ColumnarCodePlanContract.Add()
        if isAdd {
            if checkedIntegral && unsigned {
                opcode = ColumnarCodePlanContract.AddOvfUn()
            } else if checkedIntegral {
                opcode = ColumnarCodePlanContract.AddOvf()
            } else {
                opcode = ColumnarCodePlanContract.Add()
            }
        } else if isSub {
            if checkedIntegral && unsigned {
                opcode = ColumnarCodePlanContract.SubOvfUn()
            } else if checkedIntegral {
                opcode = ColumnarCodePlanContract.SubOvf()
            } else {
                opcode = ColumnarCodePlanContract.Sub()
            }
        } else if isMul {
            if checkedIntegral && unsigned {
                opcode = ColumnarCodePlanContract.MulOvfUn()
            } else if checkedIntegral {
                opcode = ColumnarCodePlanContract.MulOvf()
            } else {
                opcode = ColumnarCodePlanContract.Mul()
            }
        } else if isDiv {
            if unsigned {
                opcode = ColumnarCodePlanContract.DivUn()
            } else {
                opcode = ColumnarCodePlanContract.Div()
            }
        } else if isRem {
            if unsigned {
                opcode = ColumnarCodePlanContract.RemUn()
            } else {
                opcode = ColumnarCodePlanContract.Rem()
            }
        } else {
            return false
        }

        plan.AppendInstructionWithoutOperand(opcode)
        if ColumnarNumericFacts.IsIntPromotable(opType) {
            resultType = typeof(int)
        } else {
            resultType = opType
        }
        return true
    }

    // and/or/xor over the int-promotable set, long, ulong, uint, or ONE ENUM. Boolean pairs are not
    // part of this family (the short-circuit `&&`/`||` owner serves logical Boolean operators).
    //
    // THE ENUM ARM IS NOT ANOTHER ROW IN THE PROMOTABLE TABLE, and that is the whole point. The CLR
    // carries an enum on the evaluation stack as its UNDERLYING integral type, and this family is
    // only reached when both operands already unified to ONE op type, so the two values share that
    // form and `and`/`or`/`xor` apply with no conversion at all. What differs is the RESULT: a
    // bitwise operation over an enum keeps the ENUM type (`Public | Instance` is a `BindingFlags`,
    // not an `int`), whereas an int-promotable pair promotes to `int`. Folding enums into the
    // promotable table would have produced the right instruction and the wrong type.
    static func TryAppendBitwise(nodes: ColumnarNodeTable, source: string, candidate: int, opType: Type, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        enumOperand := ColumnarNumericFacts.IsBitwiseEnum(opType)
        if !enumOperand && !ColumnarNumericFacts.IsIntPromotable(opType) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(uint) {
            return false
        }

        if HasExactOperatorText(nodes, source, candidate, "&") {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.And())
        } else if HasExactOperatorText(nodes, source, candidate, "|") {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Or())
        } else if HasExactOperatorText(nodes, source, candidate, "^") {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Xor())
        } else {
            return false
        }

        if enumOperand || !ColumnarNumericFacts.IsIntPromotable(opType) {
            resultType = opType
        } else {
            resultType = typeof(int)
        }
        return true
    }

    // Ordering over the int-promotable set, long, ulong, uint, double, or float. `<`/`>` use the
    // ordered signed cgt/clt (unsigned cgt.un/clt.un for uint/ulong). `<=`/`>=` negate the opposite
    // ordering (`x <= y` is `!(x > y)`); a float op type uses the UNORDERED cgt.un/clt.un complement
    // so a NaN operand yields false, exactly as the legacy comparison lowering emits.
    static func TryAppendOrdering(nodes: ColumnarNodeTable, source: string, candidate: int, opType: Type, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(bool)
        if !ColumnarNumericFacts.IsIntPromotable(opType) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(uint) && opType != typeof(double) && opType != typeof(float) {
            return false
        }

        unsigned := opType == typeof(ulong) || opType == typeof(uint)
        isFloat := opType == typeof(double) || opType == typeof(float)

        ltOpcode := ColumnarCodePlanContract.Clt()
        if unsigned {
            ltOpcode = ColumnarCodePlanContract.CltUn()
        }
        gtOpcode := ColumnarCodePlanContract.Cgt()
        if unsigned {
            gtOpcode = ColumnarCodePlanContract.CgtUn()
        }
        ltComplement := ltOpcode
        if isFloat {
            ltComplement = ColumnarCodePlanContract.CltUn()
        }
        gtComplement := gtOpcode
        if isFloat {
            gtComplement = ColumnarCodePlanContract.CgtUn()
        }

        if HasExactOperatorText(nodes, source, candidate, "<") {
            plan.AppendInstructionWithoutOperand(ltOpcode)
        } else if HasExactOperatorText(nodes, source, candidate, ">") {
            plan.AppendInstructionWithoutOperand(gtOpcode)
        } else if HasExactOperatorText(nodes, source, candidate, "<=") {
            plan.AppendInstructionWithoutOperand(gtComplement)
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
        } else if HasExactOperatorText(nodes, source, candidate, ">=") {
            plan.AppendInstructionWithoutOperand(ltComplement)
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
        } else {
            return false
        }
        resultType = typeof(bool)
        return true
    }

    // ceq over the numeric surface (int-promotable, long, ulong, uint, double, float) and Boolean
    // pairs; `!=` negates the ceq result. String, Type, enum, and user reference/record equality
    // are intentionally excluded and remain whole-subtree exits for the legacy equality forms.
    static func TryAppendEquality(nodes: ColumnarNodeTable, source: string, candidate: int, opType: Type, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(bool)
        isEqual := HasExactOperatorText(nodes, source, candidate, "==")
        isNotEqual := HasExactOperatorText(nodes, source, candidate, "!=")
        if !isEqual && !isNotEqual {
            return false
        }

        // STRING EQUALITY IS VALUE EQUALITY, and the plan path had no arm for it at all. `ceq` over
        // two string references compares the REFERENCES, which is the wrong answer, so this owner
        // declined the pair — and every consumer that plans rather than emits directly went with it:
        // `name == "a"` inside a `func*` reported `emit.iterator.unsupported-shape: an iterator body
        // expression (node kind 12) could not be lowered`, while `name + "!"` in the same body
        // planned fine. `String.op_Equality` is the same call the ordinary body emitter makes for the
        // same pair, so the two paths now emit the same IL.
        if opType == typeof(string) {
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(RequiredStringEquality()))
            if isNotEqual {
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
            }
            resultType = typeof(bool)
            return true
        }

        if !ColumnarNumericFacts.IsIntPromotable(opType) && opType != typeof(long) && opType != typeof(ulong) && opType != typeof(uint) && opType != typeof(double) && opType != typeof(float) && opType != typeof(bool) {
            return false
        }

        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
        if isNotEqual {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
        }
        resultType = typeof(bool)
        return true
    }

    // decimal is not an IL primitive: every admitted operator calls the matching System.Decimal
    // op_* static over the two already-emitted decimal operands. Arithmetic yields decimal;
    // comparison and equality yield bool. Bitwise and shift operators have no decimal form.
    static func TryAppendDecimalOperator(nodes: ColumnarNodeTable, source: string, candidate: int, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(decimal)
        name := ""
        returnType := typeof(decimal)
        if HasExactOperatorText(nodes, source, candidate, "+") {
            name = "op_Addition"
            returnType = typeof(decimal)
        } else if HasExactOperatorText(nodes, source, candidate, "-") {
            name = "op_Subtraction"
            returnType = typeof(decimal)
        } else if HasExactOperatorText(nodes, source, candidate, "*") {
            name = "op_Multiply"
            returnType = typeof(decimal)
        } else if HasExactOperatorText(nodes, source, candidate, "/") {
            name = "op_Division"
            returnType = typeof(decimal)
        } else if HasExactOperatorText(nodes, source, candidate, "%") {
            name = "op_Modulus"
            returnType = typeof(decimal)
        } else if HasExactOperatorText(nodes, source, candidate, "<") {
            name = "op_LessThan"
            returnType = typeof(bool)
        } else if HasExactOperatorText(nodes, source, candidate, ">") {
            name = "op_GreaterThan"
            returnType = typeof(bool)
        } else if HasExactOperatorText(nodes, source, candidate, "<=") {
            name = "op_LessThanOrEqual"
            returnType = typeof(bool)
        } else if HasExactOperatorText(nodes, source, candidate, ">=") {
            name = "op_GreaterThanOrEqual"
            returnType = typeof(bool)
        } else if HasExactOperatorText(nodes, source, candidate, "==") {
            name = "op_Equality"
            returnType = typeof(bool)
        } else if HasExactOperatorText(nodes, source, candidate, "!=") {
            name = "op_Inequality"
            returnType = typeof(bool)
        } else {
            return false
        }

        parameterTypes := new Type[](2)
        parameterTypes[0] = typeof(decimal)
        parameterTypes[1] = typeof(decimal)
        method := RequiredDecimalOperator(name, returnType, parameterTypes)
        methodIndex := plan.AddMethodWithSignature(method, typeof(decimal), parameterTypes, returnType, true, false)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
        resultType = returnType
        return true
    }

    static func IsAdmittedOperandSyntax(nodes: ColumnarNodeTable, source: string, node: int, depth: int): bool {
        if depth > 200 {
            return false
        }
        candidate := ColumnarPlannerSupport.UnwrapParenthesesInRange(nodes, node)
        if candidate < 0 {
            return false
        }
        if nodes.Kind(candidate) == ColumnarExpressionNodeKind.BinaryExpression() {
            return IsAdmittedSyntax(nodes, source, candidate, depth)
        }
        if nodes.Kind(candidate) == 53 {
            return nodes.ChildCount(candidate) == 1 && IsAdmittedOperandSyntax(nodes, source, nodes.Child(candidate, 0), depth + 1)
        }
        if ColumnarConstructionPlanner.MayPlanRoot(nodes, candidate) {
            return ColumnarConstructionPlanner.IsAdmittedValueSyntax(nodes, source, candidate, depth)
        }
        return ColumnarDirectCallPlanner.IsAdmittedValueSyntax(nodes, source, candidate, depth)
    }

    static func IsClaimedOperatorText(nodes: ColumnarNodeTable, source: string, node: int): bool {
        return IsArithmeticOperator(nodes, source, node) || IsBitwiseOperator(nodes, source, node) || IsShiftOperator(nodes, source, node) || IsOrderingOperator(nodes, source, node) || IsEqualityOperator(nodes, source, node)
    }

    static func IsArithmeticOperator(nodes: ColumnarNodeTable, source: string, node: int): bool {
        return HasExactOperatorText(nodes, source, node, "+") || HasExactOperatorText(nodes, source, node, "-") || HasExactOperatorText(nodes, source, node, "*") || HasExactOperatorText(nodes, source, node, "/") || HasExactOperatorText(nodes, source, node, "%")
    }

    static func IsBitwiseOperator(nodes: ColumnarNodeTable, source: string, node: int): bool {
        return HasExactOperatorText(nodes, source, node, "&") || HasExactOperatorText(nodes, source, node, "|") || HasExactOperatorText(nodes, source, node, "^")
    }

    static func IsShiftOperator(nodes: ColumnarNodeTable, source: string, node: int): bool {
        return HasExactOperatorText(nodes, source, node, "<<") || HasExactOperatorText(nodes, source, node, ">>")
    }

    static func IsOrderingOperator(nodes: ColumnarNodeTable, source: string, node: int): bool {
        return HasExactOperatorText(nodes, source, node, "<") || HasExactOperatorText(nodes, source, node, ">") || HasExactOperatorText(nodes, source, node, "<=") || HasExactOperatorText(nodes, source, node, ">=")
    }

    static func IsEqualityOperator(nodes: ColumnarNodeTable, source: string, node: int): bool {
        return HasExactOperatorText(nodes, source, node, "==") || HasExactOperatorText(nodes, source, node, "!=")
    }

    static func RequiredStringConcat(): MethodInfo {
        parameterTypes := new Type[](2)
        parameterTypes[0] = typeof(string)
        parameterTypes[1] = typeof(string)
        method := typeof(string).GetMethod("Concat", parameterTypes)
        if method == null || method.get_DeclaringType() != typeof(string) || !method.get_IsStatic() || method.get_ReturnType() != typeof(string) {
            throw new InvalidOperationException("Required CLR method String.Concat(String,String) was not found exactly.")
        }
        parameters := method.GetParameters()
        if parameters.Length != 2 || parameters[0].get_ParameterType() != typeof(string) || parameters[1].get_ParameterType() != typeof(string) {
            throw new InvalidOperationException("String.Concat(String,String) has an unexpected runtime signature.")
        }
        return method
    }

    static func RequiredStringEquality(): MethodInfo {
        parameterTypes := new Type[](2)
        parameterTypes[0] = typeof(string)
        parameterTypes[1] = typeof(string)
        method := typeof(string).GetMethod("op_Equality", parameterTypes)
        if method == null || method.get_DeclaringType() != typeof(string) || !method.get_IsStatic() || method.get_ReturnType() != typeof(bool) {
            throw new InvalidOperationException("Required CLR method String.op_Equality(String,String) was not found exactly.")
        }
        parameters := method.GetParameters()
        if parameters.Length != 2 || parameters[0].get_ParameterType() != typeof(string) || parameters[1].get_ParameterType() != typeof(string) {
            throw new InvalidOperationException("String.op_Equality(String,String) has an unexpected runtime signature.")
        }
        return method
    }

    static func RequiredDecimalOperator(name: string, expectedReturn: Type, parameterTypes: Type[]): MethodInfo {
        method := typeof(decimal).GetMethod(name, parameterTypes)
        if method == null || method.get_DeclaringType() != typeof(decimal) || !method.get_IsStatic() || method.get_IsGenericMethod() || method.get_ReturnType() != expectedReturn {
            throw new InvalidOperationException("Required CLR decimal operator " + name + " was not found exactly.")
        }
        parameters := method.GetParameters()
        if parameters.Length != 2 || parameters[0].get_ParameterType() != typeof(decimal) || parameters[1].get_ParameterType() != typeof(decimal) {
            throw new InvalidOperationException("Decimal operator " + name + " has an unexpected runtime signature.")
        }
        return method
    }

    // The operator span a binary node carries, or "" when the node carries none.
    static func OperatorText(nodes: ColumnarNodeTable, source: string, node: int): string {
        start := nodes.ValueStart(node)
        length := nodes.ValueLengths[node]
        if start < 0 || length <= 0 || length > source.Length || start > source.Length - length {
            return ""
        }
        return source.Substring(start, length)
    }

    static func HasExactOperatorText(nodes: ColumnarNodeTable, source: string, node: int, expected: string): bool {
        start := nodes.ValueStart(node)
        length := nodes.ValueLengths[node]
        return start >= 0 && length == expected.Length && length <= source.Length && start <= source.Length - length && source.Substring(start, length) == expected
    }

    static func ValidateRootInputs(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan) {
        if nodes == null || source == null || bindings == null || handles == null || plan == null {
            throw new InvalidOperationException("Primitive binary planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Primitive binary planning received an invalid node index.")
        }
    }

    static func ValidateAppendInputs(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int) {
        ValidateRootInputs(nodes, source, node, bindings, handles, plan)
        // 015-B6: a schema-v4 METHOD BODY is admitted alongside v3. This gate threw — a hard crash out
        // of the compiler, not a decline — on every method-body plan, and ALL NINE owners that carried
        // it were widened in ONE move because the value surface routes by operand kind: admitting a
        // subset would mean pre-scanning operands to predict which owner they reach, which is a second
        // copy of the dispatcher's own decision.
        // Its two operands recurse through the shared value dispatcher, so it could not be
        // admitted alone.
        if (plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() && plan.SchemaVersion != ColumnarCodePlanContract.MethodBodySchemaVersion()) || plan.Status != ColumnarFragmentPlanStatus.NotOwned || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Primitive binary expressions can only append to an open schema-v3 or method-body plan.")
        }
        if parentFragment < 0 || parentFragment >= plan.FragmentCount || plan.FragmentCompleted == null || plan.FragmentCompleted.Length <= parentFragment || plan.FragmentCompleted[parentFragment] {
            throw new InvalidOperationException("Primitive binary expressions require an open parent expression fragment.")
        }
    }
}
