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
// hold and stay with those callers; everything else — the null reference, `default`, and every
// boolean, character, string, integral, floating and decimal literal, signed or not — is here.
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
    // A literal is held to the rule the analyzer typed it by: an unsuffixed integer adopts any
    // integral (or `char`) target it fits in, and any floating or decimal one; a suffixed integer,
    // a floating literal and a character keep their own type and convert only where that type
    // widens implicitly. Anything else answers null, and the caller declines rather than guesses.
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

        constantType := ConstantTargetOf(parameterType)
        if constantType == null {
            return null
        }

        targetName := constantType.FullName ?? ""
        if kind == ColumnarParameterDefaultValue.TrueKind || kind == ColumnarParameterDefaultValue.FalseKind {
            if targetName != "System.Boolean" {
                return null
            }

            boolValue: object = kind == ColumnarParameterDefaultValue.TrueKind
            return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ConstantForm, parameterType, boolValue)
        }

        if text == null {
            return null
        }

        if kind == ColumnarParameterDefaultValue.StringLiteralKind {
            if targetName != "System.String" {
                return null
            }

            stringValue: object = StringLiteralDecoder.Decode(text, false)
            return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ConstantForm, parameterType, stringValue)
        }

        if kind == ColumnarParameterDefaultValue.CharLiteralKind {
            return FromCharacter(text.Trim(), targetName, parameterType)
        }

        if kind != ColumnarParameterDefaultValue.IntLiteralKind && kind != ColumnarParameterDefaultValue.FloatLiteralKind {
            return null
        }

        negative := false
        body := text.Trim()
        if body.Length > 0 && (body[0] == '-' || body[0] == '+') {
            negative = body[0] == '-'
            body = body.Substring(1).Trim()
        }

        if body.Length == 0 {
            return null
        }

        boxed: object? = null
        if !TryDecodeNumber(kind, body, negative, targetName, out boxed) || boxed == null {
            return null
        }

        return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ConstantForm, parameterType, boxed)
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
        zero: object? = null
        if IsIntegralName(name) && TryBoxIntegral(name, false, 0UL, out zero) {
            return zero
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

    static func FromCharacter(text: string, targetName: string, parameterType: Type): ColumnarParameterDefaultValue? {
        if text.Length < 2 || text[0] != '\'' || text[text.Length - 1] != '\'' {
            return null
        }

        decoded := StringLiteralDecoder.DecodeCharacterBody(text.Substring(1, text.Length - 2))
        if decoded < 0 {
            return null
        }

        // `char` widens to `ushort` and every wider integral, floating and decimal type.
        boxed: object? = null
        if targetName == "System.Char" {
            boxed = (char)decoded
        } else if targetName == "System.UInt16" || targetName == "System.Int32" || targetName == "System.UInt32" || targetName == "System.Int64" || targetName == "System.UInt64" {
            TryBoxIntegral(targetName, false, (ulong)decoded, out boxed)
        } else {
            TryBoxWidened(targetName, false, (ulong)decoded, out boxed)
        }

        if boxed == null {
            return null
        }

        return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ConstantForm, parameterType, boxed)
    }

    // A NUMERIC LITERAL, its sign already split off. The suffix decides the literal's own type —
    // `m` decimal, `f` float, `d` (or a floating literal with none) double, and `u`/`l`/`ul` the
    // suffixed integers — and the target decides whether that type reaches it. A hex or binary
    // literal's trailing `d`/`f` is a digit, not a suffix.
    static func TryDecodeNumber(kind: int, body: string, negative: bool, targetName: string, out boxed: object?): bool {
        boxed = null
        last := body[body.Length - 1]
        isRadixInteger := body.Length > 1 && body[0] == '0' && (body[1] == 'x' || body[1] == 'X' || body[1] == 'b' || body[1] == 'B')
        if last == 'm' || last == 'M' {
            return TryDecodeDecimal(body.Substring(0, body.Length - 1), negative, targetName, out boxed)
        }

        if !isRadixInteger && (last == 'f' || last == 'F') {
            return TryDecodeSingle(body.Substring(0, body.Length - 1), negative, targetName, out boxed)
        }

        if !isRadixInteger && (last == 'd' || last == 'D') {
            return TryDecodeDouble(body.Substring(0, body.Length - 1), negative, targetName, out boxed)
        }

        if kind == ColumnarParameterDefaultValue.FloatLiteralKind {
            return TryDecodeDouble(body, negative, targetName, out boxed)
        }

        literalKind := 0
        magnitude := 0UL
        if !NumericLiteralFacts.TryParseIntegerLiteral(body, out literalKind, out magnitude) {
            return false
        }

        // 0 unsuffixed, 1 `L`, 2 `UL`, 3 `U` — `NumericLiteralFacts.TryParseIntegerLiteral`'s kinds.
        if literalKind == 0 {
            if IsIntegralName(targetName) || targetName == "System.Char" {
                return TryBoxIntegral(targetName, negative, magnitude, out boxed)
            }
            return TryBoxWidened(targetName, negative, magnitude, out boxed)
        }

        if negative && literalKind != 1 {
            return false
        }

        ownName := "System.UInt32"
        if literalKind == 1 {
            ownName = "System.Int64"
        } else if literalKind == 2 {
            ownName = "System.UInt64"
        }

        if targetName == ownName || (literalKind == 3 && (targetName == "System.Int64" || targetName == "System.UInt64")) {
            return TryBoxIntegral(targetName, negative, magnitude, out boxed)
        }

        return TryBoxWidened(targetName, negative, magnitude, out boxed)
    }

    // An integer constant into a floating or decimal target, which every integral type reaches.
    static func TryBoxWidened(targetName: string, negative: bool, magnitude: ulong, out boxed: object?): bool {
        boxed = null
        value := (decimal)magnitude
        if negative {
            value = -value
        }

        if targetName == "System.Single" {
            boxed = (float)value
            return true
        }
        if targetName == "System.Double" {
            boxed = (double)value
            return true
        }
        if targetName == "System.Decimal" {
            boxed = value
            return true
        }
        return false
    }

    // An integer constant into an integral (or `char`) target, refused when it does not fit.
    static func TryBoxIntegral(targetName: string, negative: bool, magnitude: ulong, out boxed: object?): bool {
        boxed = null
        if negative && magnitude != 0UL {
            maxMagnitude := 0UL
            if !NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude(ShortName(targetName), out maxMagnitude) || magnitude > maxMagnitude {
                return false
            }

            // `-(long)(magnitude - 1) - 1` reaches `long.MinValue` without overflowing.
            signed := -(long)(magnitude - 1UL) - 1L
            if targetName == "System.SByte" {
                boxed = (sbyte)signed
            } else if targetName == "System.Int16" {
                boxed = (short)signed
            } else if targetName == "System.Int32" {
                boxed = (int)signed
            } else if targetName == "System.Int64" {
                boxed = signed
            } else {
                return false
            }
            return true
        }

        maxValue := 0UL
        if !NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue(ShortName(targetName), out maxValue) || magnitude > maxValue {
            return false
        }

        if targetName == "System.SByte" {
            boxed = (sbyte)(long)magnitude
        } else if targetName == "System.Byte" {
            boxed = (byte)magnitude
        } else if targetName == "System.Int16" {
            boxed = (short)(long)magnitude
        } else if targetName == "System.UInt16" {
            boxed = (ushort)magnitude
        } else if targetName == "System.Char" {
            boxed = (char)magnitude
        } else if targetName == "System.Int32" {
            boxed = (int)(long)magnitude
        } else if targetName == "System.UInt32" {
            boxed = (uint)magnitude
        } else if targetName == "System.Int64" {
            boxed = (long)magnitude
        } else if targetName == "System.UInt64" {
            boxed = magnitude
        } else {
            return false
        }
        return true
    }

    // The built-in spelling `NumericLiteralFacts`' range tables are keyed by.
    static func ShortName(fullName: string): string {
        if fullName == "System.SByte" {
            return "sbyte"
        }
        if fullName == "System.Byte" {
            return "byte"
        }
        if fullName == "System.Int16" {
            return "short"
        }
        if fullName == "System.UInt16" {
            return "ushort"
        }
        if fullName == "System.Char" {
            return "char"
        }
        if fullName == "System.Int32" {
            return "int"
        }
        if fullName == "System.UInt32" {
            return "uint"
        }
        if fullName == "System.Int64" {
            return "long"
        }
        if fullName == "System.UInt64" {
            return "ulong"
        }
        return ""
    }

    static func TryDecodeSingle(body: string, negative: bool, targetName: string, out boxed: object?): bool {
        boxed = null
        value := 0.0f
        if !Single.TryParse(body.Replace("_", ""), NumberStyles.Float, CultureInfo.InvariantCulture, out value) {
            return false
        }
        if negative {
            value = -value
        }

        if targetName == "System.Single" {
            boxed = value
            return true
        }
        if targetName == "System.Double" {
            boxed = (double)value
            return true
        }
        return false
    }

    static func TryDecodeDouble(body: string, negative: bool, targetName: string, out boxed: object?): bool {
        boxed = null
        value := 0.0
        if targetName != "System.Double" || !Double.TryParse(body.Replace("_", ""), NumberStyles.Float, CultureInfo.InvariantCulture, out value) {
            return false
        }
        if negative {
            value = -value
        }

        boxed = value
        return true
    }

    static func TryDecodeDecimal(body: string, negative: bool, targetName: string, out boxed: object?): bool {
        boxed = null
        value := 0m
        if targetName != "System.Decimal" || !Decimal.TryParse(body.Replace("_", ""), NumberStyles.Float, CultureInfo.InvariantCulture, out value) {
            return false
        }
        if negative {
            value = -value
        }

        boxed = value
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
