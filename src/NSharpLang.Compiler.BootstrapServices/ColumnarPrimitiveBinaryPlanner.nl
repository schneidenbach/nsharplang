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
public class ColumnarPrimitiveBinaryPlanner {
    // Root front-door gate: a two-operand binary whose operator text is one of the claimed
    // families. Short-circuit `&&`/`||` and coalesce `??` are deliberately excluded so they route
    // straight to their legacy owner.
    public static func MayPlanRoot(
        nodes: ColumnarNodeTable,
        source: string,
        node: int): bool {
        if nodes == null || source == null || node < 0
            || node >= nodes.Kinds.Length {
            return false
        }
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0
            || nodes.Kind(candidate)
                != ColumnarExpressionNodeKind.BinaryExpression()
            || nodes.ChildCount(candidate) != 2 {
            return false
        }
        return IsClaimedOperatorText(nodes, source, candidate)
    }

    // Root ownership seam consumed by the emitter front door. A planned root claims the whole node;
    // any decline is a NotOwned whole-subtree exit (never terminal) so the legacy arm can serve the
    // string-chain, string/char, mixed-numeric, and non-numeric-equality forms outside this slice.
    public static func TryEmitRoot(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        il: ILGenerator,
        out nsharpOwned: bool,
        out legacyWholeSubtreePlanning: bool,
        out resultType: Type): bool {
        nsharpOwned = false
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if Plan(nodes, source, node, bindings, handles, plan)
                != ColumnarFragmentPlanStatus.Planned {
            legacyWholeSubtreePlanning = true
            return false
        }

        nsharpOwned = true
        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    public static func TryGetTypeRoot(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        out nsharpOwned: bool,
        out legacyWholeSubtreePlanning: bool,
        out resultType: Type): bool {
        nsharpOwned = false
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if Plan(nodes, source, node, bindings, handles, plan)
                != ColumnarFragmentPlanStatus.Planned {
            legacyWholeSubtreePlanning = true
            return false
        }

        nsharpOwned = true
        resultType = RequiredResultType(plan)
        return true
    }

    public static func Plan(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateRootInputs(nodes, source, node, bindings, handles, plan)
        plan.PrepareV3()
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0
            || !IsAdmittedSyntax(nodes, source, candidate, 0) {
            return plan.Status
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(
                -1, ColumnarExpressionNodeKind.BinaryExpression(), candidate)
            resultType := typeof(int)
            nestedOwnership := ColumnarDirectCallOwnership.NotOwned
            if !TryAppend(
                    nodes, source, candidate, bindings, handles, plan,
                    fragment, 0, out resultType, out nestedOwnership) {
                plan.Rollback(checkpoint)
                return plan.Status
            }

            plan.CompleteFragment(fragment, resultType)
            plan.CompleteV3(resultType)
            return plan.Status
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    public static func IsAdmittedSyntax(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        depth: int): bool {
        if nodes == null || source == null || depth > 200 {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0
            || nodes.Kind(candidate)
                != ColumnarExpressionNodeKind.BinaryExpression()
            || nodes.ChildCount(candidate) != 2
            || !IsClaimedOperatorText(nodes, source, candidate) {
            return false
        }

        return IsAdmittedOperandSyntax(
                nodes, source, nodes.Child(candidate, 0), depth + 1)
            && IsAdmittedOperandSyntax(
                nodes, source, nodes.Child(candidate, 1), depth + 1)
    }

    // Append to an already-open binary fragment. A decline is atomic and does not claim mixed
    // primitive pairs, unselected source-operator families, or the non-numeric equality forms.
    public static func TryAppend(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        parentFragment: int,
        depth: int,
        out resultType: Type,
        out nestedOwnership: ColumnarDirectCallOwnership): bool {
        ValidateAppendInputs(
            nodes, source, node, bindings, handles, plan, parentFragment)
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0
            || !IsAdmittedSyntax(nodes, source, candidate, depth) {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            leftType := typeof(int)
            leftOwnership := ColumnarDirectCallOwnership.NotOwned
            if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(
                    nodes, source, nodes.Child(candidate, 0),
                    bindings, handles, plan, parentFragment, depth + 1,
                    out leftType, out leftOwnership) {
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
                adopted = TryAppendAdoptedRightLiteral(
                    nodes, source, nodes.Child(candidate, 1), leftType,
                    plan, parentFragment, depth + 1, out rightType)
            }
            if !adopted
                && !ColumnarRangeIndexPlanner.TryAppendConstructionValue(
                    nodes, source, nodes.Child(candidate, 1),
                    bindings, handles, plan, parentFragment, depth + 1,
                    out rightType, out rightOwnership) {
                if rightOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                    nestedOwnership = rightOwnership
                }
                plan.Rollback(checkpoint)
                return false
            }

            // Shifts keep each operand's own type: the value is int/long/ulong, the count is int,
            // and the result is the value's type. They never reduce to the unified opType path.
            if HasExactOperatorText(nodes, source, candidate, "<<")
                || HasExactOperatorText(nodes, source, candidate, ">>") {
                if TryAppendShift(
                        nodes, source, candidate, leftType, rightType, plan,
                        out resultType) {
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
            } else if ColumnarNumericFacts.IsIntPromotable(leftType)
                && ColumnarNumericFacts.IsIntPromotable(rightType) {
                opType = typeof(int)
                opTypeResolved = true
            }

            planned := false
            if opTypeResolved {
                if HasExactOperatorText(nodes, source, candidate, "+")
                    && opType == typeof(string) {
                    methodIndex := plan.AddMethod(RequiredStringConcat())
                    plan.AppendMethodInstruction(
                        ColumnarCodePlanContract.Call(), methodIndex)
                    resultType = typeof(string)
                    planned = true
                } else if opType == typeof(decimal) {
                    planned = TryAppendDecimalOperator(
                        nodes, source, candidate, plan, out resultType)
                } else if IsArithmeticOperator(nodes, source, candidate) {
                    planned = TryAppendArithmetic(
                        nodes, source, candidate, opType, bindings, plan,
                        out resultType)
                } else if IsBitwiseOperator(nodes, source, candidate) {
                    planned = TryAppendBitwise(
                        nodes, source, candidate, opType, plan, out resultType)
                } else if IsOrderingOperator(nodes, source, candidate) {
                    planned = TryAppendOrdering(
                        nodes, source, candidate, opType, plan, out resultType)
                } else if IsEqualityOperator(nodes, source, candidate) {
                    planned = TryAppendEquality(
                        nodes, source, candidate, opType, plan, out resultType)
                }
            }

            if planned {
                return true
            }

            // Only `+` selects one exact source-declared operator; every other operator over source
            // operands is a whole-subtree exit served by the legacy source-operator branch.
            if HasExactOperatorText(nodes, source, candidate, "+") {
                sourceSelection := ColumnarSourceOperatorResolver.ResolveBinary(
                    "+", leftType, rightType, bindings.SourceTypeDefinitions)
                if sourceSelection.IsSourceType {
                    if !sourceSelection.IsSelected {
                        plan.Rollback(checkpoint)
                        return false
                    }
                    method := sourceSelection.Method
                    if method == null {
                        throw new InvalidOperationException(
                            "A selected source addition operator has no exact method handle.")
                    }
                    methodIndex := plan.AddMethodWithSignature(
                        method,
                        sourceSelection.DeclaringType,
                        sourceSelection.ParameterTypes,
                        sourceSelection.ReturnType,
                        true,
                        false)
                    plan.AppendMethodInstruction(
                        ColumnarCodePlanContract.Call(), methodIndex)
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

    // shl/shr/shr.un: an Int32/Int64/UInt64 left operand shifted by an Int32 count. shr is the
    // signed (arithmetic) right shift for int/long; a UInt64 left uses the unsigned shr.un so a
    // high-bit value zero-fills rather than sign-extends.
    static func TryAppendShift(
        nodes: ColumnarNodeTable,
        source: string,
        candidate: int,
        leftType: Type,
        rightType: Type,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        resultType = typeof(int)
        if rightType != typeof(int) {
            return false
        }
        if leftType != typeof(int) && leftType != typeof(long)
            && leftType != typeof(ulong) {
            return false
        }

        if HasExactOperatorText(nodes, source, candidate, "<<") {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Shl())
        } else if leftType == typeof(ulong) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ShrUn())
        } else {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Shr())
        }
        resultType = leftType
        return true
    }

    // The RIGHT operand of an admitted binary whose LEFT operand is an exact uint/long/ulong may be
    // an unsuffixed decimal int literal that ADOPTS the left's type — N#'s constant conversion, and
    // exactly the legacy case-12 arm's TryEmitIntLiteralAsType adoption: `u / 2` runs uint/uint,
    // `l != 0` runs long/long. Only these three left types adopt (the legacy arm gates on them), and
    // only the RIGHT operand adopts (a literal LEFT cannot — its value is already committed, so the
    // planner declines that mix through the ordinary mixed-pair path). The in-range magnitude cap is
    // Int32.MaxValue for every target, matching the pipeline's overflow on unsuffixed literals beyond
    // Int32 range whatever the target. A negative literal (unary minus wrapping the bare literal)
    // adopts long only; uint and ulong reject it. The value emits pre-negated with no neg opcode via
    // ldc.i4/ldc.i8, and the adopted operand seals its own fragment with the target type, exactly
    // like the ordinary operand path, so the unified op type is the left type. Every decline is
    // mutation-free: no plan row is written before the adoption is fully admitted.
    static func TryAppendAdoptedRightLiteral(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        leftType: Type,
        plan: ColumnarCodePlan,
        parentFragment: int,
        depth: int,
        out resultType: Type): bool {
        resultType = leftType
        if depth > 200
            || node < 0
            || node >= nodes.Kinds.Length {
            return false
        }
        if leftType != typeof(uint) && leftType != typeof(long)
            && leftType != typeof(ulong) {
            return false
        }

        negative := false
        literalNode := node
        if nodes.Kind(node) == ColumnarExpressionNodeKind.UnaryExpression()
            && nodes.ChildCount(node) == 1
            && nodes.Text(source, node) == "-" {
            negative = true
            literalNode = nodes.Child(node, 0)
        }
        if literalNode < 0
            || literalNode >= nodes.Kinds.Length
            || nodes.Kind(literalNode)
                != ColumnarExpressionNodeKind.IntLiteralExpression()
            || nodes.ChildCount(literalNode) != 0 {
            return false
        }

        // Only an unsuffixed decimal literal within Int32's positive magnitude adopts, exactly like
        // the legacy ulong.TryParse plus range gate; a suffixed literal keeps its own fixed type.
        magnitude := 0
        if !ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude(
                nodes.Text(source, literalNode), out magnitude) {
            return false
        }

        // A negative magnitude adopts long only (the unsigned targets reject it). The cap already
        // proved the magnitude at or below Int32.MaxValue, matching the legacy negation range gate.
        if negative && leftType != typeof(long) {
            return false
        }

        fragment := plan.BeginFragment(parentFragment, nodes.Kind(node), node)
        if negative {
            negatedValue := 0L - (long)magnitude
            valueIndex := plan.AddInt64(negatedValue)
            plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), valueIndex)
        } else if leftType == typeof(uint) {
            valueIndex := plan.AddInt32(magnitude)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
        } else {
            valueIndex := plan.AddInt64((long)magnitude)
            plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), valueIndex)
        }

        plan.CompleteFragment(fragment, leftType)
        resultType = leftType
        return true
    }

    // add/sub/mul/div/rem over the int-promotable set, long, ulong, uint, double, or float. div/rem
    // are unsigned for uint/ulong; checked add/sub/mul select the overflow opcode variants for the
    // integral op types when the enclosing checked context is active. The int-promotable set
    // promotes its result to int; every wider op type keeps its own type.
    static func TryAppendArithmetic(
        nodes: ColumnarNodeTable,
        source: string,
        candidate: int,
        opType: Type,
        bindings: ColumnarFragmentBindings,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        resultType = typeof(int)
        if !ColumnarNumericFacts.IsIntPromotable(opType)
            && opType != typeof(long) && opType != typeof(ulong)
            && opType != typeof(uint) && opType != typeof(double)
            && opType != typeof(float) {
            return false
        }

        unsigned := opType == typeof(ulong) || opType == typeof(uint)
        integral := ColumnarNumericFacts.IsIntPromotable(opType)
            || opType == typeof(long) || opType == typeof(ulong)
            || opType == typeof(uint)
        isAdd := HasExactOperatorText(nodes, source, candidate, "+")
        isSub := HasExactOperatorText(nodes, source, candidate, "-")
        isMul := HasExactOperatorText(nodes, source, candidate, "*")
        isDiv := HasExactOperatorText(nodes, source, candidate, "/")
        isRem := HasExactOperatorText(nodes, source, candidate, "%")
        checkedIntegral := bindings.OverflowCheckingEnabled
            && (isAdd || isSub || isMul) && integral

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

    // and/or/xor over the int-promotable set, long, ulong, or uint. Boolean pairs are not part of
    // this family (the short-circuit `&&`/`||` owner serves logical Boolean operators).
    static func TryAppendBitwise(
        nodes: ColumnarNodeTable,
        source: string,
        candidate: int,
        opType: Type,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        resultType = typeof(int)
        if !ColumnarNumericFacts.IsIntPromotable(opType)
            && opType != typeof(long) && opType != typeof(ulong)
            && opType != typeof(uint) {
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

        if ColumnarNumericFacts.IsIntPromotable(opType) {
            resultType = typeof(int)
        } else {
            resultType = opType
        }
        return true
    }

    // Ordering over the int-promotable set, long, ulong, uint, double, or float. `<`/`>` use the
    // ordered signed cgt/clt (unsigned cgt.un/clt.un for uint/ulong). `<=`/`>=` negate the opposite
    // ordering (`x <= y` is `!(x > y)`); a float op type uses the UNORDERED cgt.un/clt.un complement
    // so a NaN operand yields false, exactly as the legacy comparison lowering emits.
    static func TryAppendOrdering(
        nodes: ColumnarNodeTable,
        source: string,
        candidate: int,
        opType: Type,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        resultType = typeof(bool)
        if !ColumnarNumericFacts.IsIntPromotable(opType)
            && opType != typeof(long) && opType != typeof(ulong)
            && opType != typeof(uint) && opType != typeof(double)
            && opType != typeof(float) {
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
    static func TryAppendEquality(
        nodes: ColumnarNodeTable,
        source: string,
        candidate: int,
        opType: Type,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        resultType = typeof(bool)
        if !ColumnarNumericFacts.IsIntPromotable(opType)
            && opType != typeof(long) && opType != typeof(ulong)
            && opType != typeof(uint) && opType != typeof(double)
            && opType != typeof(float) && opType != typeof(bool) {
            return false
        }

        isEqual := HasExactOperatorText(nodes, source, candidate, "==")
        isNotEqual := HasExactOperatorText(nodes, source, candidate, "!=")
        if !isEqual && !isNotEqual {
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
    static func TryAppendDecimalOperator(
        nodes: ColumnarNodeTable,
        source: string,
        candidate: int,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
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
        methodIndex := plan.AddMethodWithSignature(
            method,
            typeof(decimal),
            parameterTypes,
            returnType,
            true,
            false)
        plan.AppendMethodInstruction(
            ColumnarCodePlanContract.Call(), methodIndex)
        resultType = returnType
        return true
    }

    static func IsAdmittedOperandSyntax(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        depth: int): bool {
        if depth > 200 {
            return false
        }
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }
        if nodes.Kind(candidate)
                == ColumnarExpressionNodeKind.BinaryExpression() {
            return IsAdmittedSyntax(nodes, source, candidate, depth)
        }
        if ColumnarConstructionPlanner.MayPlanRoot(nodes, candidate) {
            return ColumnarConstructionPlanner.IsAdmittedValueSyntax(
                nodes, candidate, depth)
        }
        return ColumnarDirectCallPlanner.IsAdmittedValueSyntax(
            nodes, candidate, depth)
    }

    static func IsClaimedOperatorText(
        nodes: ColumnarNodeTable,
        source: string,
        node: int): bool {
        return IsArithmeticOperator(nodes, source, node)
            || IsBitwiseOperator(nodes, source, node)
            || IsShiftOperator(nodes, source, node)
            || IsOrderingOperator(nodes, source, node)
            || IsEqualityOperator(nodes, source, node)
    }

    static func IsArithmeticOperator(
        nodes: ColumnarNodeTable,
        source: string,
        node: int): bool {
        return HasExactOperatorText(nodes, source, node, "+")
            || HasExactOperatorText(nodes, source, node, "-")
            || HasExactOperatorText(nodes, source, node, "*")
            || HasExactOperatorText(nodes, source, node, "/")
            || HasExactOperatorText(nodes, source, node, "%")
    }

    static func IsBitwiseOperator(
        nodes: ColumnarNodeTable,
        source: string,
        node: int): bool {
        return HasExactOperatorText(nodes, source, node, "&")
            || HasExactOperatorText(nodes, source, node, "|")
            || HasExactOperatorText(nodes, source, node, "^")
    }

    static func IsShiftOperator(
        nodes: ColumnarNodeTable,
        source: string,
        node: int): bool {
        return HasExactOperatorText(nodes, source, node, "<<")
            || HasExactOperatorText(nodes, source, node, ">>")
    }

    static func IsOrderingOperator(
        nodes: ColumnarNodeTable,
        source: string,
        node: int): bool {
        return HasExactOperatorText(nodes, source, node, "<")
            || HasExactOperatorText(nodes, source, node, ">")
            || HasExactOperatorText(nodes, source, node, "<=")
            || HasExactOperatorText(nodes, source, node, ">=")
    }

    static func IsEqualityOperator(
        nodes: ColumnarNodeTable,
        source: string,
        node: int): bool {
        return HasExactOperatorText(nodes, source, node, "==")
            || HasExactOperatorText(nodes, source, node, "!=")
    }

    static func RequiredStringConcat(): MethodInfo {
        parameterTypes := new Type[](2)
        parameterTypes[0] = typeof(string)
        parameterTypes[1] = typeof(string)
        method := typeof(string).GetMethod("Concat", parameterTypes)
        if method == null
            || method.get_DeclaringType() != typeof(string)
            || !method.get_IsStatic()
            || method.get_ReturnType() != typeof(string) {
            throw new InvalidOperationException(
                "Required CLR method String.Concat(String,String) was not found exactly.")
        }
        parameters := method.GetParameters()
        if parameters.Length != 2
            || parameters[0].get_ParameterType() != typeof(string)
            || parameters[1].get_ParameterType() != typeof(string) {
            throw new InvalidOperationException(
                "String.Concat(String,String) has an unexpected runtime signature.")
        }
        return method
    }

    static func RequiredDecimalOperator(
        name: string,
        expectedReturn: Type,
        parameterTypes: Type[]): MethodInfo {
        method := typeof(decimal).GetMethod(name, parameterTypes)
        if method == null
            || method.get_DeclaringType() != typeof(decimal)
            || !method.get_IsStatic()
            || method.get_IsGenericMethod()
            || method.get_ReturnType() != expectedReturn {
            throw new InvalidOperationException(
                "Required CLR decimal operator " + name + " was not found exactly.")
        }
        parameters := method.GetParameters()
        if parameters.Length != 2
            || parameters[0].get_ParameterType() != typeof(decimal)
            || parameters[1].get_ParameterType() != typeof(decimal) {
            throw new InvalidOperationException(
                "Decimal operator " + name + " has an unexpected runtime signature.")
        }
        return method
    }

    static func HasExactOperatorText(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        expected: string): bool {
        start := nodes.ValueStart(node)
        length := nodes.ValueLengths[node]
        return start >= 0
            && length == expected.Length
            && length <= source.Length
            && start <= source.Length - length
            && source.Substring(start, length) == expected
    }

    static func UnwrapParentheses(
        nodes: ColumnarNodeTable,
        node: int): int {
        depth := 0
        current := node
        while current >= 0
            && current < nodes.Kinds.Length
            && nodes.Kind(current)
                == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if nodes.ChildCount(current) != 1 || depth > 200 {
                return -1
            }
            current = nodes.Child(current, 0)
            depth += 1
        }
        if current < 0 || current >= nodes.Kinds.Length {
            return -1
        }
        return current
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException(
                "Planned primitive binary expression has no result type.")
        }
        return resultType
    }

    static func ValidateRootInputs(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan) {
        if nodes == null || source == null || bindings == null
            || handles == null || plan == null {
            throw new InvalidOperationException(
                "Primitive binary planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException(
                "Primitive binary planning received an invalid node index.")
        }
    }

    static func ValidateAppendInputs(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        parentFragment: int) {
        ValidateRootInputs(nodes, source, node, bindings, handles, plan)
        if plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion()
            || plan.Status != ColumnarFragmentPlanStatus.NotOwned
            || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException(
                "Primitive binary expressions can only append to an open schema-v3 plan.")
        }
        if parentFragment < 0 || parentFragment >= plan.FragmentCount
            || plan.FragmentCompleted == null
            || plan.FragmentCompleted.Length <= parentFragment
            || plan.FragmentCompleted[parentFragment] {
            throw new InvalidOperationException(
                "Primitive binary expressions require an open parent expression fragment.")
        }
    }
}
