namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Globalization
import System.Reflection
import System.Reflection.Emit
import System.Text
import NSharpLang.Compiler


// N# owner for the reflection-free scalar literals admitted by schema v3. Root planning owns
// lifecycle/fragment sealing; recursive owners call TryAppendLiteral only after opening the
// literal's fragment, so one parser and one opcode/type decision serve every expression context.
class ColumnarScalarLiteralPlanner {
    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, il: ILGenerator, out resultType: Type): bool {
        if Plan(nodes, source, node, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    static func TryGetType(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, out resultType: Type): bool {
        if Plan(nodes, source, node, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        resultType = RequiredResultType(plan)
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateRootInputs(nodes, source, node, plan)
        plan.PrepareV3()
        kind := nodes.Kind(node)
        if !IsOwnedLiteralKind(kind) {
            return plan.Status
        }

        checkpoint := plan.CreateCheckpoint()
        fragment := plan.BeginFragment(-1, kind, node)
        resultType := typeof(int)
        if !TryAppendLiteral(nodes, source, node, plan, out resultType) {
            plan.Rollback(checkpoint)
            return plan.Status
        }

        plan.CompleteFragment(fragment, resultType)
        plan.CompleteV3(resultType)
        return plan.Status
    }

    // Append exactly one literal value to an already-open schema-v3 fragment. Every decline is
    // mutation-free; the enclosing recursive owner remains responsible for its fragment rollback.
    static func TryAppendLiteral(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, out resultType: Type): bool {
        ValidateAppendInputs(nodes, source, node, plan)
        resultType = typeof(int)
        text := ""
        if nodes.ChildCount(node) != 0 || !TryGetNodeText(nodes, source, node, out text) {
            return false
        }

        kind := nodes.Kind(node)
        // Decimal literals (`5m`, `2.5m`) arrive as an Int or Float literal token whose text carries
        // the `m`/`M` suffix. They lower to the System.Decimal(int,int,int,bool,byte) constructor,
        // exactly like the legacy TryEmitDecimalLiteral path, rather than an ldc numeric constant.
        if (kind == ColumnarExpressionNodeKind.IntLiteralExpression() || kind == ColumnarExpressionNodeKind.FloatLiteralExpression()) && text.Length > 0 && (text[text.Length - 1] == 'm' || text[text.Length - 1] == 'M') {
            return TryAppendDecimal(text.Substring(0, text.Length - 1), plan, out resultType)
        }
        if kind == ColumnarExpressionNodeKind.IntLiteralExpression() {
            return TryAppendInteger(text, plan, out resultType)
        }
        if kind == ColumnarExpressionNodeKind.FloatLiteralExpression() {
            return TryAppendFloatingPoint(text, plan, out resultType)
        }
        if kind == ColumnarExpressionNodeKind.CharLiteralExpression() {
            return TryAppendCharacter(text, plan, out resultType)
        }
        if kind == ColumnarExpressionNodeKind.StringLiteralExpression() {
            return TryAppendString(text, plan, out resultType)
        }
        return false
    }

    static func TryAppendInteger(text: string, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        literalKind := 0
        magnitude := 0UL
        if !TryParseIntegerLiteral(text, out literalKind, out magnitude) {
            return false
        }

        if literalKind == 0 {
            if magnitude > 2147483647UL {
                return false
            }
            valueIndex := plan.AddInt32((int)magnitude)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
            return true
        }

        if literalKind == 1 {
            if magnitude > 9223372036854775807UL {
                return false
            }
            valueIndex := plan.AddInt64((long)magnitude)
            plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), valueIndex)
            resultType = typeof(long)
            return true
        }

        bits := (long)0
        if magnitude <= 9223372036854775807UL {
            bits = (long)magnitude
        } else {
            distanceFromMaximum := 18446744073709551615UL - magnitude
            bits = -1L - (long)distanceFromMaximum
        }
        valueIndex := plan.AddInt64(bits)
        plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), valueIndex)
        resultType = typeof(ulong)
        return true
    }

    // Contextual call binding may retain the syntax fact that an otherwise-Int32 literal can
    // adopt a declaration's integral parameter type. Match the legacy columnar rule exactly:
    // only unsuffixed decimal digits within Int32's positive magnitude participate.
    static func TryGetTargetTypedIntegerMagnitude(text: string, out magnitude: int): bool {
        magnitude = 0
        if text == null || text.Length == 0 {
            return false
        }

        index := 0
        while index < text.Length {
            if text[index] < '0' || text[index] > '9' {
                return false
            }
            index += 1
        }

        literalKind := 0
        parsedMagnitude := 0UL
        if !TryParseIntegerLiteral(text, out literalKind, out parsedMagnitude) || literalKind != 0 || parsedMagnitude > 2147483647UL {
            return false
        }

        magnitude = (int)parsedMagnitude
        return true
    }

    static func TryAppendFloatingPoint(text: string, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(double)
        if text.Length == 0 {
            return false
        }

        last := text[text.Length - 1]
        if last == 'm' || last == 'M' {
            return false
        }
        isSingle := last == 'f' || last == 'F'
        body := text
        if isSingle || last == 'd' || last == 'D' {
            body = body.Substring(0, body.Length - 1)
        }
        body = body.Trim().Replace("_", "")

        value := 0.0
        if !Double.TryParse(body, CultureInfo.InvariantCulture, out value) {
            return false
        }
        if isSingle {
            valueIndex := plan.AddSingle((float)value)
            plan.AppendSingleInstruction(ColumnarCodePlanContract.LdcR4(), valueIndex)
            resultType = typeof(float)
            return true
        }

        valueIndex := plan.AddDouble(value)
        plan.AppendDoubleInstruction(ColumnarCodePlanContract.LdcR8(), valueIndex)
        return true
    }

    // Lower a decimal literal body (the token text with its `m`/`M` suffix already removed) exactly
    // like the legacy TryEmitDecimalLiteral path: strip digit separators, parse with the invariant
    // culture's Number style, then push the three GetBits magnitude words plus the sign flag and
    // scale and construct through the canonical System.Decimal(int, int, int, bool, byte)
    // constructor. Malformed text declines mutation-free.
    static func TryAppendDecimal(body: string, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(decimal)
        parsed := (decimal)0
        if !Decimal.TryParse(body.Replace("_", ""), CultureInfo.InvariantCulture, out parsed) {
            return false
        }

        bits := Decimal.GetBits(parsed)
        if bits.Length != 4 {
            return false
        }

        lo := bits[0]
        mid := bits[1]
        high := bits[2]
        flags := bits[3]
        isNegative := 0
        if flags < 0 {
            isNegative = 1
        }
        scale := (flags >> 16) & 255

        AppendLdcI4(plan, lo)
        AppendLdcI4(plan, mid)
        AppendLdcI4(plan, high)
        AppendLdcI4(plan, isNegative)
        AppendLdcI4(plan, scale)
        constructorIndex := plan.AddConstructor(RequiredDecimalBitsConstructor())
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
        return true
    }

    static func AppendLdcI4(plan: ColumnarCodePlan, value: int) {
        valueIndex := plan.AddInt32(value)
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
    }

    static func RequiredDecimalBitsConstructor(): ConstructorInfo {
        parameterTypes := new Type[](5)
        parameterTypes[0] = typeof(int)
        parameterTypes[1] = typeof(int)
        parameterTypes[2] = typeof(int)
        parameterTypes[3] = typeof(bool)
        parameterTypes[4] = typeof(byte)
        constructor := typeof(decimal).GetConstructor(parameterTypes)
        if constructor == null {
            throw new InvalidOperationException("Required System.Decimal(int, int, int, bool, byte) constructor was not found.")
        }
        return constructor
    }

    // kind 0 = unsuffixed Int32, 1 = signed Int64 (L), 2 = UInt64 (UL/LU).
    static func TryParseIntegerLiteral(text: string, out literalKind: int, out magnitude: ulong): bool {
        literalKind = 0
        magnitude = 0UL
        if text.Length == 0 {
            return false
        }

        end := text.Length
        hasUnsigned := false
        hasLong := false
        suffixLength := 0
        while end > 0 {
            last := text[end - 1]
            if last == 'u' || last == 'U' {
                if hasUnsigned {
                    return false
                }
                hasUnsigned = true
            } else if last == 'l' || last == 'L' {
                if hasLong {
                    return false
                }
                hasLong = true
            } else {
                break
            }
            suffixLength = suffixLength + 1
            if suffixLength > 2 {
                return false
            }
            end = end - 1
        }

        if suffixLength == 0 {
            literalKind = 0
        } else if suffixLength == 1 && hasLong && !hasUnsigned {
            literalKind = 1
        } else if suffixLength == 2 && hasLong && hasUnsigned {
            literalKind = 2
        } else {
            return false
        }
        return TryParseIntegerBody(text, end, out magnitude)
    }

    static func TryParseIntegerBody(text: string, end: int, out magnitude: ulong): bool {
        magnitude = 0UL
        if end <= 0 {
            return false
        }
        radix := 10
        index := 0
        if end >= 2 && text[0] == '0' {
            marker := text[1]
            if marker == 'x' || marker == 'X' {
                radix = 16
                index = 2
            } else if marker == 'b' || marker == 'B' {
                radix = 2
                index = 2
            }
        }
        if index >= end {
            return false
        }
        firstDigit := IntegerDigitValue(text[index])
        if firstDigit < 0 || firstDigit >= radix {
            return false
        }

        digitCount := 0
        while index < end {
            ch := text[index]
            if ch == '_' {
                index = index + 1
                continue
            }
            digit := IntegerDigitValue(ch)
            if digit < 0 || digit >= radix {
                return false
            }
            unsignedDigit := (ulong)digit
            unsignedRadix := (ulong)radix
            if magnitude > (18446744073709551615UL - unsignedDigit) / unsignedRadix {
                magnitude = 0UL
                return false
            }
            magnitude = magnitude * unsignedRadix + unsignedDigit
            digitCount = digitCount + 1
            index = index + 1
        }
        return digitCount > 0
    }

    static func IntegerDigitValue(ch: char): int {
        if ch >= '0' && ch <= '9' {
            return ch - '0'
        }
        if ch >= 'a' && ch <= 'f' {
            return 10 + ch - 'a'
        }
        if ch >= 'A' && ch <= 'F' {
            return 10 + ch - 'A'
        }
        return -1
    }

    static func TryAppendCharacter(text: string, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(char)
        if text.Length < 2 || text[0] != '\'' || text[text.Length - 1] != '\'' {
            return false
        }
        body := text.Substring(1, text.Length - 2)
        decodedValue := StringLiteralDecoder.DecodeCharacterBody(body)
        if decodedValue < 0 {
            return false
        }

        valueIndex := plan.AddInt32(decodedValue)
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
        return true
    }

    static func TryAppendString(text: string, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(string)
        if text.Length > 0 && text[0] == '$' {
            return TryAppendZeroHoleInterpolatedString(text, plan)
        }
        if !IsPlainStringLiteral(text) {
            return false
        }

        decoded := StringLiteralDecoder.Decode(text, false)
        valueIndex := plan.AddString(decoded)
        plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), valueIndex)
        return true
    }

    // Interpolation holes remain with the later expression-owner slices. The complete zero-hole
    // family is a scalar constant: split and decode every normal/raw literal segment before any
    // plan mutation, then persist the same single ldstr shape as an ordinary string literal.
    static func TryAppendZeroHoleInterpolatedString(text: string, plan: ColumnarCodePlan): bool {
        parts := new List<ColumnarInterpolationPart>()
        if !ColumnarInterpolationSplitter.TrySplit(text, parts) {
            return false
        }

        decoded := new StringBuilder()
        for part in parts {
            if part.IsHole {
                return false
            }
            decoded.Append(StringLiteralDecoder.DecodeInterpolatedText(text, part.Text))
        }

        valueIndex := plan.AddString(decoded.ToString())
        plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), valueIndex)
        return true
    }

    static func IsPlainStringLiteral(text: string): bool {
        if text.Length < 2 || text[0] == '$' || text[0] != '"' {
            return false
        }
        if text.Length >= 3 && text[1] == '"' && text[2] == '"' {
            return StringLiteralDecoder.IsTripleQuoteStringLiteral(text)
        }
        return text[text.Length - 1] == '"'
    }

    static func IsOwnedLiteralKind(kind: int): bool {
        return kind == ColumnarExpressionNodeKind.IntLiteralExpression() || kind == ColumnarExpressionNodeKind.FloatLiteralExpression() || kind == ColumnarExpressionNodeKind.CharLiteralExpression() || kind == ColumnarExpressionNodeKind.StringLiteralExpression()
    }

    static func TryGetNodeText(nodes: ColumnarNodeTable, source: string, node: int, out text: string): bool {
        text = ""
        start := nodes.ValueStart(node)
        length := nodes.ValueLengths[node]
        if start < 0 || length <= 0 || length > source.Length || start > source.Length - length {
            return false
        }
        text = source.Substring(start, length)
        return true
    }

    static func ValidateRootInputs(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan) {
        if nodes == null || source == null || plan == null {
            throw new InvalidOperationException("Scalar-literal planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Scalar-literal planning received an invalid node index.")
        }
    }

    // A schema-v4 METHOD BODY is admitted alongside v3, and it is admitted WITHOUT the open-fragment
    // requirement rather than with a faked one: v4 is a documented superset of v3 that carries a FLAT
    // operation stream and no fragments at all (`PrepareMethodBody` does not even reserve fragment
    // capacity), while every appender this owner reaches for — Int32/Int64/Single/Double/String and the
    // decimal constructor — is already v4-legal. Widening the gate is what lets the ONE literal owner
    // this file's header promises serve a method body as well as an expression fragment.
    static func ValidateAppendInputs(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan) {
        ValidateRootInputs(nodes, source, node, plan)
        if (plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() && plan.SchemaVersion != ColumnarCodePlanContract.MethodBodySchemaVersion()) || plan.Status != ColumnarFragmentPlanStatus.NotOwned || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Scalar literals can only append to an open schema-v3 or method-body plan.")
        }
        if plan.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion() {
            return
        }
        if plan.FragmentCount <= 0 || plan.FragmentCompleted == null || plan.FragmentCompleted.Length < plan.FragmentCount {
            throw new InvalidOperationException("Scalar literals require an open expression fragment.")
        }
        hasOpenFragment := false
        i := 0
        while i < plan.FragmentCount {
            if !plan.FragmentCompleted[i] {
                hasOpenFragment = true
            }
            i = i + 1
        }
        if !hasOpenFragment {
            throw new InvalidOperationException("Scalar literals require an open expression fragment.")
        }
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException("Planned scalar literal has no result type.")
        }
        return resultType
    }
}
