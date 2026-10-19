namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Globalization
import System.Reflection
import System.Reflection.Emit
import System.Runtime.CompilerServices
import NSharpLang.Compiler


// ONE PARAMETER DEFAULT, DECODED AGAINST THE TYPE IT DEFAULTS. A default reaches the back end in
// two spellings — the source's literal (its token kind and written text) and a referenced
// assembly's metadata — and is consumed in three places: the parameter's own metadata row, a
// call site that omits the argument through the code plan, and one that omits it through the IL
// emitter. Each of those used to keep its own short list of the types it understood, so an `int`
// default worked everywhere while a `long`, a `char`, a `decimal` or `int? = null` worked only in
// whichever place happened to list it. This owner makes the decision once: what the default IS, as
// a value of the parameter's own type, or that it is not a default this type can hold.
//
// Enum MEMBER defaults (`c: Color = Color.Red`) resolve through the enum registries their callers
// hold and stay with those callers — including the members a constant expression names, which the
// caller resolves before `FromExpression` folds it. Everything else — the null reference,
// `default`, every literal, and the arithmetic over them — is here, and the arithmetic itself is
// `ConstantFolder`'s, the same folder the analyzer reports from.
class ColumnarParameterDefaultValue {

    // `null` for a reference type: `ldnull`, and a null `Constant` row.
    static NullReferenceForm: int => 1
    // The all-zero value of a value type that has no constant spelling — a struct's `default`, a
    // `Nullable<T>` with no value, a type parameter's `default`. The call site zero-initialises a
    // local of the parameter type; the metadata row is the null `Constant` Roslyn writes for the
    // same source (ECMA-335 II.15.4.1.4 admits it for any value type).
    static ZeroValueForm: int => 2
    // A constant of a CLR primitive, `string` or `decimal`, boxed as exactly that type: the
    // parameter's own type, its enum's underlying type, or the `T` of a `Nullable<T>` parameter.
    static ConstantForm: int => 3

    // The token kinds a source default arrives as (`Token.nl`'s `enum TokenType` ordinals).
    static IntLiteralKind: int => 1
    static FloatLiteralKind: int => 2
    static CharLiteralKind: int => 3
    static StringLiteralKind: int => 4
    static DefaultKind: int => 34
    static TrueKind: int => 44
    static FalseKind: int => 45
    static NullKind: int => 46
    // A default the parameter-list parser captured as a whole constant EXPRESSION (`2 * 3`,
    // `Options.A | Options.B`): its source text, folded here by `ConstantFolder`.
    static ConstantExpressionKind: int => 1002

    Form: int
    ParameterType: Type
    Constant: object?

    constructor(form: int, parameterType: Type, constant: object?) {
        Form = form
        ParameterType = parameterType
        Constant = constant
    }

    static func IsSourceLiteralKind(kind: int): bool {
        return kind == ColumnarParameterDefaultValue.IntLiteralKind || kind == ColumnarParameterDefaultValue.FloatLiteralKind || kind == ColumnarParameterDefaultValue.CharLiteralKind || kind == ColumnarParameterDefaultValue.StringLiteralKind || kind == ColumnarParameterDefaultValue.DefaultKind || kind == ColumnarParameterDefaultValue.TrueKind || kind == ColumnarParameterDefaultValue.FalseKind || kind == ColumnarParameterDefaultValue.NullKind
    }

    // ------------------------------------------------------------------------------------------
    // DECODING
    // ------------------------------------------------------------------------------------------

    // A SOURCE DEFAULT. `text` is the default as written, a leading sign included (`-3`, `- 2.5`).
    // What a literal is worth is `ConstantFolder`'s; whether that value is a default of THIS
    // parameter is `FromConstant`'s. Anything else answers null, and the caller declines rather
    // than guesses.
    static func FromSource(kind: int, text: string?, parameterType: Type): ColumnarParameterDefaultValue? {
        if parameterType == null || parameterType.IsByRef {
            return null
        }

        if kind == ColumnarParameterDefaultValue.NullKind {
            return NullOf(parameterType)
        }

        if kind == ColumnarParameterDefaultValue.DefaultKind {
            return DefaultOf(parameterType)
        }

        if kind == ColumnarParameterDefaultValue.TrueKind || kind == ColumnarParameterDefaultValue.FalseKind {
            spelling := "false"
            if kind == ColumnarParameterDefaultValue.TrueKind {
                spelling = "true"
            }
            return FromConstant(ConstantFolder.Fold(ConstantTerm.Literal(kind, spelling)).Value, parameterType)
        }

        if text == null || !IsLiteralKind(kind) {
            return null
        }

        // A signed literal arrives as one text, `-3` or `- 2.5`; it folds as the negation of the
        // literal, which is how `-2147483648` stays an `int`.
        body := text.Trim()
        negated := false
        if (kind == ColumnarParameterDefaultValue.IntLiteralKind || kind == ColumnarParameterDefaultValue.FloatLiteralKind) && body.Length > 0 && (body[0] == '-' || body[0] == '+') {
            negated = body[0] == '-'
            body = body.Substring(1).Trim()
        }

        term := ConstantTerm.Literal(kind, body)
        if negated {
            term = ConstantTerm.Unary("-", term)
        }
        return FromConstant(ConstantFolder.Fold(term).Value, parameterType)
    }

    static func IsLiteralKind(kind: int): bool {
        return kind == ColumnarParameterDefaultValue.IntLiteralKind || kind == ColumnarParameterDefaultValue.FloatLiteralKind || kind == ColumnarParameterDefaultValue.CharLiteralKind || kind == ColumnarParameterDefaultValue.StringLiteralKind
    }

    // A CONSTANT EXPRESSION DEFAULT. The text is re-read with the same expression kernels as a
    // body; its enum members were resolved by the caller, in the caller's scope, into
    // `memberValues` (keyed by the member's text as written — see `ExpressionMemberNames`).
    static func FromExpression(text: string?, parameterType: Type, memberValues: Dictionary<string, int>): ColumnarParameterDefaultValue? {
        if text == null || parameterType == null || parameterType.IsByRef {
            return null
        }

        nodes: ColumnarNodeTable = null
        root := -1
        if !ColumnarProgramInputBuilder.TryBuildExpressionNodeTable(text, out nodes, out root) {
            return null
        }

        enumType := EnumTargetOf(parameterType)
        term := TermOf(nodes, text, root, enumType, memberValues)
        if term == null {
            return null
        }
        return FromConstant(ConstantFolder.Fold(term).Value, parameterType)
    }

    // The dotted member names a constant expression mentions, in the spelling `FromExpression`
    // looks them up by, or null when the text is not an expression the kernels can read.
    static func ExpressionMemberNames(text: string?): List<string>? {
        if text == null {
            return null
        }

        nodes: ColumnarNodeTable = null
        root := -1
        if !ColumnarProgramInputBuilder.TryBuildExpressionNodeTable(text, out nodes, out root) {
            return null
        }

        names := new List<string>()
        CollectMemberNames(nodes, text, root, names)
        return names
    }

    static func CollectMemberNames(nodes: ColumnarNodeTable, source: string, node: int, names: List<string>) {
        if nodes.Kind(node) == ColumnarExpressionNodeKind.MemberAccessExpression {
            names.Add(MemberText(nodes, source, node))
            return
        }

        child := 0
        while child < nodes.ChildCount(node) {
            CollectMemberNames(nodes, source, nodes.Child(node, child), names)
            child = child + 1
        }
    }

    static func MemberText(nodes: ColumnarNodeTable, source: string, node: int): string {
        return source.Substring(nodes.SpanStart(node), nodes.SpanLength(node)).Replace(" ", "")
    }

    // THE TERM THE FOLDER READS, from the node table. Only constant shapes have a term; anything
    // else — a call, a bare name, an index — answers null, and the default declines.
    static func TermOf(nodes: ColumnarNodeTable, source: string, node: int, enumType: Type?, memberValues: Dictionary<string, int>): ConstantTerm? {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.IntLiteralExpression {
            return ConstantTerm.Literal(ColumnarParameterDefaultValue.IntLiteralKind, nodes.Text(source, node))
        }
        if kind == ColumnarExpressionNodeKind.FloatLiteralExpression {
            return ConstantTerm.Literal(ColumnarParameterDefaultValue.FloatLiteralKind, nodes.Text(source, node))
        }
        if kind == ColumnarExpressionNodeKind.CharLiteralExpression {
            return ConstantTerm.Literal(ColumnarParameterDefaultValue.CharLiteralKind, nodes.Text(source, node))
        }
        if kind == ColumnarExpressionNodeKind.StringLiteralExpression {
            return ConstantTerm.Literal(ColumnarParameterDefaultValue.StringLiteralKind, nodes.Text(source, node))
        }
        if kind == ColumnarExpressionNodeKind.BoolLiteralExpression {
            boolKind := ColumnarParameterDefaultValue.FalseKind
            if nodes.Text(source, node) == "true" {
                boolKind = ColumnarParameterDefaultValue.TrueKind
            }
            return ConstantTerm.Literal(boolKind, nodes.Text(source, node))
        }
        if kind == ColumnarExpressionNodeKind.ParenthesizedExpression && nodes.ChildCount(node) == 1 {
            return TermOf(nodes, source, nodes.Child(node, 0), enumType, memberValues)
        }
        if kind == ColumnarExpressionNodeKind.UnaryExpression && nodes.ChildCount(node) == 1 {
            operand := TermOf(nodes, source, nodes.Child(node, 0), enumType, memberValues)
            if operand == null {
                return null
            }
            return ConstantTerm.Unary(nodes.Text(source, node), operand)
        }
        if kind == ColumnarExpressionNodeKind.BinaryExpression && nodes.ChildCount(node) == 2 {
            left := TermOf(nodes, source, nodes.Child(node, 0), enumType, memberValues)
            right := TermOf(nodes, source, nodes.Child(node, 1), enumType, memberValues)
            if left == null || right == null {
                return null
            }
            return ConstantTerm.Binary(nodes.Text(source, node), left, right)
        }
        if kind == ColumnarExpressionNodeKind.MemberAccessExpression && enumType != null {
            value := 0
            if memberValues.TryGetValue(MemberText(nodes, source, node), out value) {
                return ConstantTerm.EnumMember(enumType.FullName ?? enumType.Name, value)
            }
        }
        return null
    }

    // THE FOLDED CONSTANT, AS A DEFAULT OF THIS PARAMETER'S TYPE. The constant converts the way an
    // assignment would: to its own type; widened along C#'s implicit numeric conversions; an `int`
    // constant to any narrower or unsigned integral type it fits (C#'s implicit constant
    // conversion), and an unsuffixed integer LITERAL to any integral or `char` type it fits (N#'s
    // literal rule); an enum constant only to its own enum, and the literal `0` to any enum.
    static func FromConstant(folded: ConstantValue?, parameterType: Type): ColumnarParameterDefaultValue? {
        if folded == null {
            return null
        }

        constantType := ConstantTargetOf(parameterType)
        if constantType == null {
            return null
        }

        targetName := constantType.FullName ?? ""
        sourceName := folded.TypeName
        if EnumTargetOf(parameterType) != null {
            isZeroLiteral := folded.IsAdoptableLiteral && folded.IntegralValue() == 0m
            if folded.EnumIdentity == null && !isZeroLiteral {
                return null
            }
            return ConstantDefault(parameterType, ConstantFolder.BoxIntegral(targetName, folded.IntegralValue()))
        }

        if folded.EnumIdentity != null {
            return null
        }

        if sourceName == targetName {
            return ConstantDefault(parameterType, folded.Value)
        }

        isIntegralSource := ConstantFolder.IsIntegralName(sourceName) || sourceName == "System.Char"
        if isIntegralSource && (ConstantFolder.IsIntegralName(targetName) || targetName == "System.Char") {
            if folded.IsAdoptableLiteral || WidensIntegral(sourceName, targetName) || ConvertsAsConstant(folded, targetName) {
                return ConstantDefault(parameterType, ConstantFolder.BoxIntegral(targetName, folded.IntegralValue()))
            }
            return null
        }

        if isIntegralSource && targetName == "System.Decimal" {
            return ConstantDefault(parameterType, folded.IntegralValue())
        }
        if (isIntegralSource || sourceName == "System.Single") && targetName == "System.Double" {
            return ConstantDefault(parameterType, folded.FloatingValue())
        }
        if isIntegralSource && targetName == "System.Single" {
            return ConstantDefault(parameterType, (float)folded.FloatingValue())
        }
        return null
    }

    static func ConstantDefault(parameterType: Type, value: object?): ColumnarParameterDefaultValue? {
        if value == null {
            return null
        }
        return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ConstantForm, parameterType, value)
    }

    // C#'s implicit numeric conversions between integral types (and from `char`).
    static func WidensIntegral(sourceName: string, targetName: string): bool {
        if sourceName == "System.SByte" {
            return targetName == "System.Int16" || targetName == "System.Int32" || targetName == "System.Int64"
        }
        if sourceName == "System.Byte" {
            return targetName == "System.Int16" || targetName == "System.UInt16" || targetName == "System.Int32" || targetName == "System.UInt32" || targetName == "System.Int64" || targetName == "System.UInt64"
        }
        if sourceName == "System.Int16" {
            return targetName == "System.Int32" || targetName == "System.Int64"
        }
        if sourceName == "System.UInt16" || sourceName == "System.Char" {
            return targetName == "System.Int32" || targetName == "System.UInt32" || targetName == "System.Int64" || targetName == "System.UInt64" || (sourceName == "System.Char" && targetName == "System.UInt16")
        }
        if sourceName == "System.Int32" {
            return targetName == "System.Int64"
        }
        if sourceName == "System.UInt32" {
            return targetName == "System.Int64" || targetName == "System.UInt64"
        }
        return false
    }

    // C#'s implicit CONSTANT conversions: an `int` constant to `sbyte`, `byte`, `short`, `ushort`,
    // `uint` or `ulong`, and a `long` constant to `ulong`, each only when the value fits (the fit is
    // `BoxIntegral`'s to check).
    static func ConvertsAsConstant(folded: ConstantValue, targetName: string): bool {
        if folded.TypeName == "System.Int32" {
            return targetName == "System.SByte" || targetName == "System.Byte" || targetName == "System.Int16" || targetName == "System.UInt16" || targetName == "System.UInt32" || targetName == "System.UInt64"
        }
        return folded.TypeName == "System.Int64" && targetName == "System.UInt64"
    }

    // The enum a constant for this parameter must be a member of — the parameter's own type, or
    // the `T` of a `Nullable<T>` — or null when the parameter is not an enum.
    static func EnumTargetOf(parameterType: Type): Type? {
        target := parameterType
        if IsNullableValueType(target) {
            target = target.GetGenericArguments()[0]
        }
        if !target.IsEnum {
            return null
        }
        return target
    }

    // A METADATA DEFAULT, read off a referenced method's parameter. The `Constant` row the CLR
    // decoded arrives boxed as whatever primitive it was stored as; a `decimal` has no `Constant`
    // row at all and is carried by `[DecimalConstant]`, which C# writes and reads. A null row on a
    // value-type parameter is how C# spells `default` for a struct or `null` for a `Nullable<T>`.
    // An omitted argument is not a conversion site, so a stored constant whose type is not the
    // parameter's own (or its enum's underlying type) is refused rather than widened.
    //
    // `parameterType` is the parameter's type as the CALL resolved it. One still open over a type
    // parameter has no zero value this call site can name, so it is refused, and so is a default
    // whose stored value cannot be read at all.
    static func FromMetadata(parameter: ParameterInfo, parameterType: Type): ColumnarParameterDefaultValue? {
        if parameter == null || parameterType == null || parameterType.IsByRef || parameterType.IsPointer || parameterType.IsGenericParameter || !parameter.IsOptional {
            return null
        }

        decimalConstant: object? = null
        if TryReadDecimalConstant(parameter, out decimalConstant) {
            constantType := ConstantTargetOf(parameterType)
            if constantType == null || constantType.FullName != "System.Decimal" {
                return null
            }

            return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ConstantForm, parameterType, decimalConstant)
        }

        raw: object? = null
        try {
            // `[Optional]` with no constant at all has no default value: there is nothing this call
            // site may write for it.
            if !parameter.HasDefaultValue {
                return null
            }

            raw = parameter.RawDefaultValue
        } catch ex: Exception {
            return null
        }

        if raw == null {
            // The zero value only where the DECLARED type admits one: a value type, or a type
            // parameter the call closed over a value type. A null row on a reference parameter is
            // not an `int` default because a caller asked for one.
            if parameterType.IsValueType {
                declared := parameter.ParameterType
                if !declared.IsValueType && !declared.ContainsGenericParameters {
                    return null
                }

                return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ZeroValueForm, parameterType, null)
            }

            return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.NullReferenceForm, parameterType, null)
        }

        constantTarget := ConstantTargetOf(parameterType)
        if constantTarget == null {
            return null
        }

        // A reader may hand an enum parameter's constant back already boxed as the enum; the row
        // itself holds only the underlying integer, and that is what is compared and emitted.
        known: object = raw
        storedType := known.GetType()
        if storedType.IsEnum {
            storedType = Enum.GetUnderlyingType(storedType)
        }

        storedName := storedType.FullName ?? ""
        if storedName != (constantTarget.FullName ?? "") || !IsConstantName(storedName) {
            return null
        }

        return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ConstantForm, parameterType, RuntimeConstant(storedName, known))
    }

    static func NullOf(parameterType: Type): ColumnarParameterDefaultValue? {
        if IsNullableValueType(parameterType) {
            return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ZeroValueForm, parameterType, null)
        }

        if parameterType.IsValueType || parameterType.IsGenericParameter {
            return null
        }

        return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.NullReferenceForm, parameterType, null)
    }

    // `default`, FOR EVERY TYPE. A type with a constant spelling — a primitive, `decimal`, an enum —
    // gets its zero as that constant, which is what C# writes into the `Constant` row; a reference
    // type gets null; every other value type, a `Nullable<T>` and a type parameter get the zero value.
    static func DefaultOf(parameterType: Type): ColumnarParameterDefaultValue? {
        if parameterType.IsGenericParameter || IsNullableValueType(parameterType) {
            return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ZeroValueForm, parameterType, null)
        }

        if !parameterType.IsValueType {
            return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.NullReferenceForm, parameterType, null)
        }

        constantType := ConstantTargetOf(parameterType)
        if constantType != null {
            zero := ZeroConstant(constantType.FullName ?? "")
            if zero != null {
                return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ConstantForm, parameterType, zero)
            }
        }

        return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ZeroValueForm, parameterType, null)
    }

    // THE TYPE A CONSTANT FOR THIS PARAMETER IS HELD AS: the `T` of a `Nullable<T>`, an enum's
    // underlying integral type, or the type itself — and null when none of those is a primitive,
    // `string` or `decimal`.
    static func ConstantTargetOf(parameterType: Type): Type? {
        target := parameterType
        if IsNullableValueType(target) {
            target = target.GetGenericArguments()[0]
        }

        if target.IsEnum {
            underlying: Type? = null
            try {
                underlying = target.GetEnumUnderlyingType()
            } catch ex: Exception {
                return null
            }
            if underlying == null {
                return null
            }
            target = underlying
        }

        if !IsConstantName(target.FullName ?? "") {
            return null
        }

        return target
    }

    static func IsNullableValueType(candidate: Type): bool {
        if !candidate.IsGenericType || candidate.IsGenericTypeDefinition {
            return false
        }

        definition := candidate.GetGenericTypeDefinition()
        return definition.FullName == "System.Nullable`1" && candidate.GetGenericArguments().Length == 1
    }

    static func IsConstantName(name: string): bool {
        return name == "System.String" || name == "System.Decimal" || name == "System.Boolean" || name == "System.Char" || IsIntegralName(name) || name == "System.Single" || name == "System.Double"
    }

    static func IsIntegralName(name: string): bool {
        return name == "System.SByte" || name == "System.Byte" || name == "System.Int16" || name == "System.UInt16" || name == "System.Int32" || name == "System.UInt32" || name == "System.Int64" || name == "System.UInt64"
    }

    static func ZeroConstant(name: string): object? {
        if name == "System.Boolean" {
            return false
        }
        if name == "System.Char" {
            return (char)0
        }
        if name == "System.Single" {
            return 0.0f
        }
        if name == "System.Double" {
            return 0.0
        }
        if name == "System.Decimal" {
            return 0m
        }
        if IsIntegralName(name) {
            return ConstantFolder.BoxIntegral(name, 0m)
        }
        return null
    }

    // A constant the metadata reader decoded is re-boxed in THIS runtime's primitive, so a value a
    // `MetadataLoadContext` produced and one the running corelib produced emit identically.
    static func RuntimeConstant(name: string, known: object): object {
        if name == "System.String" {
            return Convert.ToString(known, CultureInfo.InvariantCulture) ?? ""
        }
        if name == "System.Boolean" {
            return Convert.ToBoolean(known, CultureInfo.InvariantCulture)
        }
        if name == "System.Char" {
            return Convert.ToChar(known, CultureInfo.InvariantCulture)
        }
        if name == "System.Single" {
            return Convert.ToSingle(known, CultureInfo.InvariantCulture)
        }
        if name == "System.Double" {
            return Convert.ToDouble(known, CultureInfo.InvariantCulture)
        }
        if name == "System.Decimal" {
            return Convert.ToDecimal(known, CultureInfo.InvariantCulture)
        }
        if name == "System.SByte" {
            return Convert.ToSByte(known, CultureInfo.InvariantCulture)
        }
        if name == "System.Byte" {
            return Convert.ToByte(known, CultureInfo.InvariantCulture)
        }
        if name == "System.Int16" {
            return Convert.ToInt16(known, CultureInfo.InvariantCulture)
        }
        if name == "System.UInt16" {
            return Convert.ToUInt16(known, CultureInfo.InvariantCulture)
        }
        if name == "System.Int32" {
            return Convert.ToInt32(known, CultureInfo.InvariantCulture)
        }
        if name == "System.UInt32" {
            return Convert.ToUInt32(known, CultureInfo.InvariantCulture)
        }
        if name == "System.Int64" {
            return Convert.ToInt64(known, CultureInfo.InvariantCulture)
        }
        return Convert.ToUInt64(known, CultureInfo.InvariantCulture)
    }

    // `[DecimalConstant(scale, sign, hi, mid, lo)]`, in either of its constructors (the magnitude
    // words as `uint` or as `int`), read off the attribute data so it answers the same in every
    // reflection universe.
    static func TryReadDecimalConstant(parameter: ParameterInfo, out value: object?): bool {
        value = null
        attributes: IList<CustomAttributeData> = new List<CustomAttributeData>()
        try {
            attributes = parameter.GetCustomAttributesData()
        } catch ex: Exception {
            return false
        }

        for attribute in attributes {
            if attribute.AttributeType.FullName != "System.Runtime.CompilerServices.DecimalConstantAttribute" {
                continue
            }

            arguments := attribute.ConstructorArguments
            if arguments.Count != 5 {
                return false
            }

            scale := Convert.ToByte(arguments[0].Value, CultureInfo.InvariantCulture)
            sign := Convert.ToByte(arguments[1].Value, CultureInfo.InvariantCulture)
            high := 0
            mid := 0
            low := 0
            if scale > 28 || !SignedWord(arguments[2].Value, out high) || !SignedWord(arguments[3].Value, out mid) || !SignedWord(arguments[4].Value, out low) {
                return false
            }

            value = new Decimal(low, mid, high, sign != 0, scale)
            return true
        }

        return false
    }

    static func SignedWord(argument: object?, out word: int): bool {
        word = 0
        if argument == null {
            return false
        }

        known: object = argument
        if known is int {
            word = Convert.ToInt32(known, CultureInfo.InvariantCulture)
            return true
        }

        word = Int32Bits(Convert.ToUInt32(known, CultureInfo.InvariantCulture))
        return true
    }

    // THE SAME VALUE, IN THE SPELLING A SOURCE DEFAULT IS CARRIED IN — the token kind and text that
    // `FromSource` reads back into this value against `ParameterType`. A referenced free function's
    // defaults travel in the sibling columns a source declaration fills, so a metadata default is
    // spelled into them rather than carried in a second shape. Every integral constant (an enum's
    // and a `char`'s included) is its unsuffixed decimal value, which `FromSource` adopts into any
    // integral target it fits; a string that would need an escape, and a non-finite floating value,
    // have no plain spelling and are left unspelled.
    func TrySpellSource(out kind: int, out text: string): bool {
        kind = -1
        text = ""
        if Form == ColumnarParameterDefaultValue.NullReferenceForm {
            kind = ColumnarParameterDefaultValue.NullKind
            text = "null"
            return true
        }

        if Form == ColumnarParameterDefaultValue.ZeroValueForm {
            kind = ColumnarParameterDefaultValue.DefaultKind
            text = "default"
            return true
        }

        known := Constant
        if known == null {
            return false
        }

        if known is bool {
            kind = Convert.ToBoolean(known, CultureInfo.InvariantCulture) ? ColumnarParameterDefaultValue.TrueKind : ColumnarParameterDefaultValue.FalseKind
            text = kind == ColumnarParameterDefaultValue.TrueKind ? "true" : "false"
            return true
        }

        written := known as string
        if written != null {
            for character in written {
                if character == '"' || character == '\\' || character == '{' || character == '}' || Char.IsControl(character) {
                    return false
                }
            }
            kind = ColumnarParameterDefaultValue.StringLiteralKind
            text = "\"" + written + "\""
            return true
        }

        if known is decimal {
            kind = ColumnarParameterDefaultValue.FloatLiteralKind
            text = Convert.ToDecimal(known, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture) + "m"
            return true
        }

        if known is float || known is double {
            floating := Convert.ToDouble(known, CultureInfo.InvariantCulture)
            if Double.IsNaN(floating) || Double.IsInfinity(floating) {
                return false
            }
            kind = ColumnarParameterDefaultValue.FloatLiteralKind
            if known is float {
                text = Convert.ToSingle(known, CultureInfo.InvariantCulture).ToString("R", CultureInfo.InvariantCulture) + "f"
            } else {
                text = floating.ToString("R", CultureInfo.InvariantCulture)
            }
            return true
        }

        kind = ColumnarParameterDefaultValue.IntLiteralKind
        if known is char {
            text = ((int)Convert.ToChar(known, CultureInfo.InvariantCulture)).ToString(CultureInfo.InvariantCulture)
        } else if known is ulong {
            text = Convert.ToUInt64(known, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture)
        } else {
            text = Convert.ToInt64(known, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture)
        }
        return true
    }

    // ------------------------------------------------------------------------------------------
    // THE PARAMETER'S METADATA
    // ------------------------------------------------------------------------------------------

    // Whether the parameter row carries `HasDefault`. A `decimal` constant has no `Constant` row —
    // the metadata format has no element type for it — and is `[Optional]` plus `[DecimalConstant]`,
    // exactly as C# writes it, so C# and every reflection reader see the same default.
    func HasConstantRow(): bool {
        return !IsDecimalConstant()
    }

    func IsDecimalConstant(): bool {
        known := Constant
        return Form == ColumnarParameterDefaultValue.ConstantForm && known != null && known is decimal
    }

    func ApplyTo(parameter: ParameterBuilder) {
        if IsDecimalConstant() {
            parameter.SetCustomAttribute(DecimalConstantAttributeFor(Convert.ToDecimal(Constant, CultureInfo.InvariantCulture)))
            return
        }

        parameter.SetConstant(Form == ColumnarParameterDefaultValue.ConstantForm ? Constant : null)
    }

    static func DecimalConstantAttributeFor(value: decimal): CustomAttributeBuilder {
        bits := Decimal.GetBits(value)
        parameterTypes := new Type[](5)
        parameterTypes[0] = typeof(byte)
        parameterTypes[1] = typeof(byte)
        parameterTypes[2] = typeof(uint)
        parameterTypes[3] = typeof(uint)
        parameterTypes[4] = typeof(uint)
        constructor := typeof(DecimalConstantAttribute).GetConstructor(parameterTypes)
        if constructor == null {
            throw new InvalidOperationException("Required DecimalConstantAttribute(byte, byte, uint, uint, uint) constructor was not found.")
        }

        arguments := new object[](5)
        arguments[0] = (byte)((bits[3] >> 16) & 255)
        arguments[1] = (byte)(bits[3] < 0 ? 1 : 0)
        arguments[2] = UnsignedWord(bits[2])
        arguments[3] = UnsignedWord(bits[1])
        arguments[4] = UnsignedWord(bits[0])
        return new CustomAttributeBuilder(constructor, arguments)
    }

    static func UnsignedWord(word: int): uint {
        if word >= 0 {
            return (uint)word
        }
        return 4294967295u - (uint)(-1 - word)
    }

    // ------------------------------------------------------------------------------------------
    // THE OMITTED ARGUMENT
    // ------------------------------------------------------------------------------------------

    // Appends the value to the caller's open fragment: the constant in its own type, lifted into
    // `Nullable<T>` when the parameter is one, or the zero value / null the form names.
    func AppendTo(plan: ColumnarCodePlan): bool {
        if Form == ColumnarParameterDefaultValue.NullReferenceForm {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
            return true
        }

        if Form == ColumnarParameterDefaultValue.ZeroValueForm {
            ColumnarConstructionPlanner.AppendDefaultValueConstruction(plan, ParameterType)
            return true
        }

        nullableConstructor: ConstructorInfo? = null
        if IsNullableValueType(ParameterType) && !TryNullableConstructor(out nullableConstructor) {
            return false
        }

        known := Constant
        if known == null {
            return false
        }

        if known is string {
            plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), plan.AddString(Convert.ToString(known, CultureInfo.InvariantCulture) ?? ""))
        } else if known is decimal {
            ColumnarScalarLiteralPlanner.AppendDecimalValue(Convert.ToDecimal(known, CultureInfo.InvariantCulture), plan)
        } else if known is float {
            plan.AppendSingleInstruction(ColumnarCodePlanContract.LdcR4(), plan.AddSingle(Convert.ToSingle(known, CultureInfo.InvariantCulture)))
        } else if known is double {
            plan.AppendDoubleInstruction(ColumnarCodePlanContract.LdcR8(), plan.AddDouble(Convert.ToDouble(known, CultureInfo.InvariantCulture)))
        } else if known is long || known is ulong {
            plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), plan.AddInt64(Int64Bits(known)))
        } else if known is bool {
            if Convert.ToBoolean(known, CultureInfo.InvariantCulture) {
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
            } else {
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
            }
        } else {
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(Int32Bits(known)))
        }

        if nullableConstructor != null {
            // THE SIGNATURE IS THE CONSTRUCTOR'S OWN `T`, not the constant's carrier: for a
            // `Nullable<SomeEnum>` the constant is the enum's underlying integer and the
            // constructor still takes the enum.
            wrapSignature := new Type[](1)
            wrapSignature[0] = ParameterType.GetGenericArguments()[0]
            plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), plan.AddConstructorWithSignature(nullableConstructor, ParameterType, wrapSignature))
        }
        return true
    }

    // The same value, through the IL emitter's own generator.
    func EmitTo(il: ILGenerator): bool {
        if Form == ColumnarParameterDefaultValue.NullReferenceForm {
            il.Emit(OpCodes.Ldnull)
            return true
        }

        if Form == ColumnarParameterDefaultValue.ZeroValueForm {
            local := il.DeclareLocal(ParameterType)
            il.Emit(OpCodes.Ldloca, local)
            il.Emit(OpCodes.Initobj, ParameterType)
            il.Emit(OpCodes.Ldloc, local)
            return true
        }

        nullableConstructor: ConstructorInfo? = null
        if IsNullableValueType(ParameterType) && !TryNullableConstructor(out nullableConstructor) {
            return false
        }

        known := Constant
        if known == null {
            return false
        }

        if known is string {
            il.Emit(OpCodes.Ldstr, Convert.ToString(known, CultureInfo.InvariantCulture) ?? "")
        } else if known is decimal {
            bits := Decimal.GetBits(Convert.ToDecimal(known, CultureInfo.InvariantCulture))
            il.Emit(OpCodes.Ldc_I4, bits[0])
            il.Emit(OpCodes.Ldc_I4, bits[1])
            il.Emit(OpCodes.Ldc_I4, bits[2])
            il.Emit(OpCodes.Ldc_I4, bits[3] < 0 ? 1 : 0)
            il.Emit(OpCodes.Ldc_I4, (bits[3] >> 16) & 255)
            il.Emit(OpCodes.Newobj, ColumnarScalarLiteralPlanner.RequiredDecimalBitsConstructor())
        } else if known is float {
            il.Emit(OpCodes.Ldc_R4, Convert.ToSingle(known, CultureInfo.InvariantCulture))
        } else if known is double {
            il.Emit(OpCodes.Ldc_R8, Convert.ToDouble(known, CultureInfo.InvariantCulture))
        } else if known is long || known is ulong {
            il.Emit(OpCodes.Ldc_I8, Int64Bits(known))
        } else {
            il.Emit(OpCodes.Ldc_I4, Int32Bits(known))
        }

        if nullableConstructor != null {
            il.Emit(OpCodes.Newobj, nullableConstructor)
        }
        return true
    }

    func TryNullableConstructor(out constructorInfo: ConstructorInfo?): bool {
        constructorInfo = null
        selected: ConstructorInfo = null
        if !ColumnarNullableArgumentLowering.TryGetNullableConstructor(ParameterType, out selected) || selected == null {
            return false
        }

        constructorInfo = selected
        return true
    }

    // The 64-bit pattern `ldc.i8` carries; a `ulong` above `long.MaxValue` is its two's complement.
    static func Int64Bits(known: object): long {
        if known is ulong {
            unsigned := Convert.ToUInt64(known, CultureInfo.InvariantCulture)
            if unsigned <= 9223372036854775807UL {
                return (long)unsigned
            }
            return -1L - (long)(18446744073709551615UL - unsigned)
        }
        return Convert.ToInt64(known, CultureInfo.InvariantCulture)
    }

    // The 32-bit pattern `ldc.i4` carries for every narrower primitive; a `uint` above
    // `int.MaxValue` is its two's complement, and `bool`/`char` are their integer values.
    static func Int32Bits(known: object): int {
        if known is bool {
            return Convert.ToBoolean(known, CultureInfo.InvariantCulture) ? 1 : 0
        }
        if known is char {
            return (int)Convert.ToChar(known, CultureInfo.InvariantCulture)
        }
        if known is uint {
            unsigned := Convert.ToUInt32(known, CultureInfo.InvariantCulture)
            if unsigned <= 2147483647u {
                return (int)unsigned
            }
            return -1 - (int)(4294967295u - unsigned)
        }
        return Convert.ToInt32(known, CultureInfo.InvariantCulture)
    }
}
