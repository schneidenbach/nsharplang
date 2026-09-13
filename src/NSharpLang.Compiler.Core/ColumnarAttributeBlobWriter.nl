namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Globalization
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler

// ONE NAMED ARGUMENT, RESOLVED. The blob writes a named argument as a member KIND, the member's own
// type, its name and the value — so the binder must have decided which member it is before a single
// byte is written, and that decision is carried here rather than re-made inside the writer.
class ColumnarAttributeNamedArgument {
    Name: string
    MemberType: Type
    IsField: bool
    Value: ColumnarAttributeArgumentNode

    constructor(name: string, memberType: Type, isField: bool, value: ColumnarAttributeArgumentNode) {
        Name = name
        MemberType = memberType
        IsField = isField
        Value = value
    }
}

// THE CUSTOM-ATTRIBUTE BLOB FOR AN ARBITRARY ARGUMENT LIST (ECMA-335 II.23.3).
//
// `ColumnarAttributeBlobs` writes the three blobs the compiler synthesizes for itself, where both
// the constructor and the values are known at the call site. This writes the blob a USER wrote, where
// neither is: the values arrive as argument syntax and the types arrive from the constructor the
// binder chose, and the encoding of a value depends entirely on the type it is filling. `1` is one
// byte in a `byte` parameter and eight in a `long` one; `Colors.Red | Colors.Blue` is an integer of
// the enum's underlying width; `typeof(int)` is a STRING; and an `object` parameter carries the
// value's own type in front of it.
//
// EVERY FAILURE IS A REFUSAL, NEVER A GUESS. A value this writer cannot encode against the type it
// was handed answers false and the attribute is declined as a whole, because a blob that is half
// right is metadata that says something the source did not.
class ColumnarAttributeBlobWriter {
    resolution: ColumnarSemanticTypeResolution

    constructor(typeResolution: ColumnarSemanticTypeResolution) {
        resolution = typeResolution
    }

    // ELEMENT TYPE CODES. Named here once rather than spelled as integers at the twelve places that
    // write them, because a wrong code produces metadata that loads and reads back as a different
    // value rather than an error anyone would see.
    static BooleanCode: int => 2
    static CharCode: int => 3
    static SByteCode: int => 4
    static ByteCode: int => 5
    static Int16Code: int => 6
    static UInt16Code: int => 7
    static Int32Code: int => 8
    static UInt32Code: int => 9
    static Int64Code: int => 10
    static UInt64Code: int => 11
    static SingleCode: int => 12
    static DoubleCode: int => 13
    static StringCode: int => 14
    static SzArrayCode: int => 29
    static TypeCode: int => 80
    static BoxedCode: int => 81
    static FieldCode: int => 83
    static PropertyCode: int => 84
    static EnumCode: int => 85

    func TryWriteBlob(fixedArguments: List<ColumnarAttributeArgumentNode>, parameterTypes: Type[], namedArguments: List<ColumnarAttributeNamedArgument>, out blob: byte[]): bool {
        blob = Array.Empty<byte>()
        if fixedArguments.Count != parameterTypes.Length {
            return false
        }

        bytes := new List<byte>()
        ColumnarAttributeBlobs.WritePrologue(bytes)
        index := 0
        while index < fixedArguments.Count {
            if !TryWriteValue(bytes, fixedArguments[index], parameterTypes[index]) {
                return false
            }

            index = index + 1
        }

        ColumnarAttributeBlobs.WriteNamedArgumentCount(bytes, namedArguments.Count)
        for named in namedArguments {
            ColumnarAttributeBlobs.Append(bytes, named.IsField ? ColumnarAttributeBlobWriter.FieldCode : ColumnarAttributeBlobWriter.PropertyCode)
            if !TryWriteMemberTypeCode(bytes, named.MemberType) {
                return false
            }

            ColumnarAttributeBlobs.WriteSerString(bytes, named.Name)
            if !TryWriteValue(bytes, named.Value, named.MemberType) {
                return false
            }
        }

        blob = bytes.ToArray()
        return true
    }

    // ONE VALUE, AGAINST THE TYPE IT FILLS. The seven arms are the seven shapes attribute metadata
    // admits and they are asked in the order that makes each one decidable: `object` first because it
    // is the only arm that must look at the VALUE to choose an encoding, then array, then the two
    // reference shapes, then enum, and only then the primitives.
    func TryWriteValue(bytes: List<byte>, node: ColumnarAttributeArgumentNode, targetType: Type): bool {
        if IsObjectType(targetType) {
            return TryWriteBoxedValue(bytes, node)
        }

        if targetType.get_IsArray() {
            return TryWriteArrayValue(bytes, node, targetType)
        }

        if IsTypeHandleType(targetType) {
            return TryWriteTypeValue(bytes, node)
        }

        if IsStringType(targetType) {
            return TryWriteStringValue(bytes, node)
        }

        if IsEnumType(targetType) {
            underlying: Type = targetType
            if !TryGetEnumUnderlyingType(targetType, out underlying) {
                return false
            }

            return TryWritePrimitiveValue(bytes, node, underlying)
        }

        if IsUnbakedBuilderType(targetType) {
            return false
        }

        return TryWritePrimitiveValue(bytes, node, targetType)
    }

    // AN `object` PARAMETER CARRIES THE VALUE'S OWN TYPE IN FRONT OF THE VALUE, so the value has to be
    // classified before it can be written. A `null` has no type and is written as a null STRING,
    // which is what the C# compiler writes and what every `CustomAttributeData` reader decodes as
    // `null`.
    func TryWriteBoxedValue(bytes: List<byte>, node: ColumnarAttributeArgumentNode): bool {
        if node.Kind == ColumnarAttributeArgumentKind.NullLiteral {
            ColumnarAttributeBlobs.Append(bytes, ColumnarAttributeBlobWriter.StringCode)
            ColumnarAttributeBlobs.WriteSerString(bytes, null)
            return true
        }

        naturalType: Type = typeof(object)
        if !TryGetNaturalType(node, out naturalType) {
            return false
        }

        ColumnarAttributeBlobs.Append(bytes, ColumnarAttributeBlobWriter.BoxedCode)
        if !TryWriteMemberTypeCode(bytes, naturalType) {
            return false
        }

        return TryWriteValue(bytes, node, naturalType)
    }

    func TryWriteArrayValue(bytes: List<byte>, node: ColumnarAttributeArgumentNode, arrayType: Type): bool {
        elementCandidate := arrayType.GetElementType()
        if elementCandidate == null {
            return false
        }

        elementType: Type = elementCandidate
        if node.Kind == ColumnarAttributeArgumentKind.NullLiteral {
            // A NULL ARRAY is the sentinel length 0xFFFFFFFF, which is the one length that is not a
            // count. Four 0xFF bytes rather than `WriteUInt32(-1)`, because the writer's arithmetic
            // form takes a non-negative count.
            ColumnarAttributeBlobs.Append(bytes, 255)
            ColumnarAttributeBlobs.Append(bytes, 255)
            ColumnarAttributeBlobs.Append(bytes, 255)
            ColumnarAttributeBlobs.Append(bytes, 255)
            return true
        }

        if node.Kind != ColumnarAttributeArgumentKind.ArrayLiteral {
            return false
        }

        ColumnarAttributeBlobs.WriteUInt32(bytes, node.Children.Count)
        for element in node.Children {
            if !TryWriteValue(bytes, element, elementType) {
                return false
            }
        }

        return true
    }

    // A `Type` ARGUMENT IS A STRING IN METADATA — the type's name, not a handle — and the name is
    // assembly-qualified for everything the emitted assembly does not itself define. A type being
    // BUILT has no assembly-qualified name to ask for, and needs none: an unqualified name resolves
    // against the attribute's own assembly first.
    func TryWriteTypeValue(bytes: List<byte>, node: ColumnarAttributeArgumentNode): bool {
        if node.Kind == ColumnarAttributeArgumentKind.NullLiteral {
            ColumnarAttributeBlobs.WriteSerString(bytes, null)
            return true
        }

        if node.Kind != ColumnarAttributeArgumentKind.TypeOf {
            return false
        }

        operandType: Type = typeof(object)
        if !TryResolveWrittenType(node.Text, out operandType) {
            return false
        }

        typeName := ""
        if !TryGetMetadataTypeName(operandType, out typeName) {
            return false
        }

        ColumnarAttributeBlobs.WriteSerString(bytes, typeName)
        return true
    }

    func TryWriteStringValue(bytes: List<byte>, node: ColumnarAttributeArgumentNode): bool {
        if node.Kind == ColumnarAttributeArgumentKind.NullLiteral {
            ColumnarAttributeBlobs.WriteSerString(bytes, null)
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.StringLiteral {
            ColumnarAttributeBlobs.WriteSerString(bytes, node.Text)
            return true
        }

        constantValue: object? = null
        if node.Kind == ColumnarAttributeArgumentKind.MemberPath && TryResolveConstantMember(node.Text, out constantValue) {
            text := constantValue as string
            if text != null {
                ColumnarAttributeBlobs.WriteSerString(bytes, text)
                return true
            }
        }

        return false
    }

    func TryWritePrimitiveValue(bytes: List<byte>, node: ColumnarAttributeArgumentNode, targetType: Type): bool {
        fullName := targetType.get_FullName()
        if fullName == null {
            return false
        }

        if fullName == "System.Boolean" {
            value := false
            if !TryEvaluateBool(node, out value) {
                return false
            }

            ColumnarAttributeBlobs.Append(bytes, value ? 1 : 0)
            return true
        }

        if fullName == "System.Single" {
            single := 0.0
            if !TryEvaluateFloating(node, out single) {
                return false
            }

            WriteIntegerBytes(bytes, (long)BitConverter.SingleToInt32Bits((float)single), 4)
            return true
        }

        if fullName == "System.Double" {
            value := 0.0
            if !TryEvaluateFloating(node, out value) {
                return false
            }

            WriteIntegerBytes(bytes, BitConverter.DoubleToInt64Bits(value), 8)
            return true
        }

        width := IntegerWidth(fullName)
        if width == 0 {
            return false
        }

        bits := 0L
        if !TryEvaluateInteger(node, out bits) {
            return false
        }

        WriteIntegerBytes(bytes, bits, width)
        return true
    }

    // THE BYTE WIDTH OF AN INTEGRAL TYPE, or zero for anything that is not one. `char` is here
    // because its metadata encoding is a two-byte integer, not because it is a number.
    static func IntegerWidth(fullName: string): int {
        if fullName == "System.SByte" || fullName == "System.Byte" {
            return 1
        }

        if fullName == "System.Int16" || fullName == "System.UInt16" || fullName == "System.Char" {
            return 2
        }

        if fullName == "System.Int32" || fullName == "System.UInt32" {
            return 4
        }

        if fullName == "System.Int64" || fullName == "System.UInt64" {
            return 8
        }

        return 0
    }

    // LITTLE-ENDIAN, AND THE MASK RATHER THAN THE SHIFT'S SIGN DECIDES EACH BYTE, so a negative value
    // writes its two's-complement pattern at every width without a separate signed path.
    static func WriteIntegerBytes(bytes: List<byte>, bits: long, byteCount: int) {
        value := bits
        index := 0
        while index < byteCount {
            ColumnarAttributeBlobs.Append(bytes, (int)(value & 255L))
            value = value >> 8
            index = index + 1
        }
    }

    // THE TYPE CODE THAT PRECEDES A NAMED ARGUMENT'S NAME, and the same codes an `object`-typed
    // argument writes in front of its value. An enum carries its TYPE NAME, which is why this cannot
    // be a lookup table over primitives alone.
    func TryWriteMemberTypeCode(bytes: List<byte>, memberType: Type): bool {
        if memberType.get_IsArray() {
            elementCandidate := memberType.GetElementType()
            if elementCandidate == null {
                return false
            }

            ColumnarAttributeBlobs.Append(bytes, ColumnarAttributeBlobWriter.SzArrayCode)
            elementType: Type = elementCandidate
            return TryWriteMemberTypeCode(bytes, elementType)
        }

        if IsEnumType(memberType) {
            typeName := ""
            if !TryGetMetadataTypeName(memberType, out typeName) {
                return false
            }

            ColumnarAttributeBlobs.Append(bytes, ColumnarAttributeBlobWriter.EnumCode)
            ColumnarAttributeBlobs.WriteSerString(bytes, typeName)
            return true
        }

        if IsTypeHandleType(memberType) {
            ColumnarAttributeBlobs.Append(bytes, ColumnarAttributeBlobWriter.TypeCode)
            return true
        }

        if IsObjectType(memberType) {
            ColumnarAttributeBlobs.Append(bytes, ColumnarAttributeBlobWriter.BoxedCode)
            return true
        }

        code := PrimitiveTypeCode(memberType.get_FullName())
        if code == 0 {
            return false
        }

        ColumnarAttributeBlobs.Append(bytes, code)
        return true
    }

    static func PrimitiveTypeCode(fullName: string?): int {
        if fullName == null {
            return 0
        }

        if fullName == "System.Boolean" {
            return ColumnarAttributeBlobWriter.BooleanCode
        }
        if fullName == "System.Char" {
            return ColumnarAttributeBlobWriter.CharCode
        }
        if fullName == "System.SByte" {
            return ColumnarAttributeBlobWriter.SByteCode
        }
        if fullName == "System.Byte" {
            return ColumnarAttributeBlobWriter.ByteCode
        }
        if fullName == "System.Int16" {
            return ColumnarAttributeBlobWriter.Int16Code
        }
        if fullName == "System.UInt16" {
            return ColumnarAttributeBlobWriter.UInt16Code
        }
        if fullName == "System.Int32" {
            return ColumnarAttributeBlobWriter.Int32Code
        }
        if fullName == "System.UInt32" {
            return ColumnarAttributeBlobWriter.UInt32Code
        }
        if fullName == "System.Int64" {
            return ColumnarAttributeBlobWriter.Int64Code
        }
        if fullName == "System.UInt64" {
            return ColumnarAttributeBlobWriter.UInt64Code
        }
        if fullName == "System.Single" {
            return ColumnarAttributeBlobWriter.SingleCode
        }
        if fullName == "System.Double" {
            return ColumnarAttributeBlobWriter.DoubleCode
        }
        if fullName == "System.String" {
            return ColumnarAttributeBlobWriter.StringCode
        }

        return 0
    }

    // ------------------------------------------------------------------------------------------
    // EVALUATION. The three value families an argument can reduce to, each asked only by the arm
    // whose target type wants it — a `bool` parameter never asks the integer question, so `1` in a
    // `bool` parameter is a refusal rather than `true`.
    // ------------------------------------------------------------------------------------------

    func TryEvaluateBool(node: ColumnarAttributeArgumentNode, out value: bool): bool {
        value = false
        if node.Kind == ColumnarAttributeArgumentKind.BoolLiteral {
            value = node.Text == "true"
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.LogicalNot {
            operand := false
            if !TryEvaluateBool(node.Children[0], out operand) {
                return false
            }

            value = !operand
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.MemberPath {
            constantValue: object? = null
            if TryResolveConstantMember(node.Text, out constantValue) && constantValue != null {
                boxedBool := constantValue as object
                if typeof(bool).IsInstanceOfType(boxedBool) {
                    value = Convert.ToBoolean(boxedBool)
                    return true
                }
            }
        }

        return false
    }

    func TryEvaluateFloating(node: ColumnarAttributeArgumentNode, out value: double): bool {
        value = 0.0
        if node.Kind == ColumnarAttributeArgumentKind.FloatLiteral {
            return TryParseFloatingLiteral(node.Text, out value)
        }

        if node.Kind == ColumnarAttributeArgumentKind.Negate {
            operand := 0.0
            if !TryEvaluateFloating(node.Children[0], out operand) {
                return false
            }

            value = 0.0 - operand
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.IntLiteral {
            bits := 0L
            if !TryEvaluateInteger(node, out bits) {
                return false
            }

            value = (double)bits
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.MemberPath {
            constantValue: object? = null
            if TryResolveConstantMember(node.Text, out constantValue) && constantValue != null {
                boxedValue := constantValue as object
                if typeof(double).IsInstanceOfType(boxedValue) || typeof(float).IsInstanceOfType(boxedValue) {
                    value = Convert.ToDouble(boxedValue)
                    return true
                }
            }
        }

        return false
    }

    // `f`/`F`/`d`/`D` suffixes and digit separators are the literal's spelling, not its value. `m` is
    // refused: a decimal is not a metadata constant at all.
    static func TryParseFloatingLiteral(text: string, out value: double): bool {
        value = 0.0
        if text.Length == 0 {
            return false
        }

        last := text[text.Length - 1]
        if last == 'm' || last == 'M' {
            return false
        }

        body := text
        if last == 'f' || last == 'F' || last == 'd' || last == 'D' {
            body = body.Substring(0, body.Length - 1)
        }

        body = body.Replace("_", "")
        return Double.TryParse(body, CultureInfo.InvariantCulture, out value)
    }

    // THE 64-BIT TWO'S-COMPLEMENT PATTERN AN INTEGER EXPRESSION REDUCES TO. Every integral target
    // width takes its low bytes from this one value, which is what makes `Colors.Red | Colors.Blue`
    // and `1 | 2` the same computation over two different enum widths.
    func TryEvaluateInteger(node: ColumnarAttributeArgumentNode, out bits: long): bool {
        bits = 0L
        if node.Kind == ColumnarAttributeArgumentKind.IntLiteral {
            literalKind := 0
            magnitude := 0UL
            if !ColumnarScalarLiteralPlanner.TryParseIntegerLiteral(node.Text, out literalKind, out magnitude) {
                return false
            }

            bits = UnsignedToBits(magnitude)
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.CharLiteral {
            if node.Text.Length < 2 || node.Text[0] != '\'' || node.Text[node.Text.Length - 1] != '\'' {
                return false
            }

            decoded := StringLiteralDecoder.DecodeCharacterBody(node.Text.Substring(1, node.Text.Length - 2))
            if decoded < 0 {
                return false
            }

            bits = (long)decoded
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.Negate {
            operand := 0L
            if !TryEvaluateInteger(node.Children[0], out operand) {
                return false
            }

            bits = 0L - operand
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.BitwiseNot {
            operand := 0L
            if !TryEvaluateInteger(node.Children[0], out operand) {
                return false
            }

            bits = -1L - operand
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.BitwiseOr || node.Kind == ColumnarAttributeArgumentKind.BitwiseAnd || node.Kind == ColumnarAttributeArgumentKind.BitwiseXor {
            left := 0L
            right := 0L
            if !TryEvaluateInteger(node.Children[0], out left) || !TryEvaluateInteger(node.Children[1], out right) {
                return false
            }

            if node.Kind == ColumnarAttributeArgumentKind.BitwiseOr {
                bits = left | right
                return true
            }

            if node.Kind == ColumnarAttributeArgumentKind.BitwiseAnd {
                bits = left & right
                return true
            }

            bits = left ^ right
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.MemberPath {
            constantValue: object? = null
            if !TryResolveConstantMember(node.Text, out constantValue) || constantValue == null {
                return false
            }

            return TryConstantToBits(constantValue, out bits)
        }

        return false
    }

    static func UnsignedToBits(magnitude: ulong): long {
        if magnitude <= 9223372036854775807UL {
            return (long)magnitude
        }

        distanceFromMaximum := 18446744073709551615UL - magnitude
        return -1L - (long)distanceFromMaximum
    }

    // A METADATA CONSTANT ARRIVES BOXED AND ITS RUNTIME TYPE DECIDES HOW TO READ IT. `ulong` is asked
    // first and separately: `Convert.ToInt64` throws on a `ulong` above `long.MaxValue`, which is
    // exactly the value a flags enum's top bit produces.
    static func TryConstantToBits(constantValue: object, out bits: long): bool {
        bits = 0L
        if typeof(ulong).IsInstanceOfType(constantValue) {
            bits = UnsignedToBits(Convert.ToUInt64(constantValue))
            return true
        }

        if typeof(bool).IsInstanceOfType(constantValue) {
            bits = Convert.ToBoolean(constantValue) ? 1L : 0L
            return true
        }

        if typeof(char).IsInstanceOfType(constantValue) {
            bits = (long)Convert.ToInt32(constantValue)
            return true
        }

        if typeof(sbyte).IsInstanceOfType(constantValue) || typeof(byte).IsInstanceOfType(constantValue) || typeof(short).IsInstanceOfType(constantValue) || typeof(ushort).IsInstanceOfType(constantValue) || typeof(int).IsInstanceOfType(constantValue) || typeof(uint).IsInstanceOfType(constantValue) || typeof(long).IsInstanceOfType(constantValue) {
            bits = Convert.ToInt64(constantValue)
            return true
        }

        return false
    }

    // WHICH TYPE A VALUE HAS WHEN NOTHING ASKED IT TO HAVE ONE — the natural type an `object`
    // parameter records in front of the value. An integer literal is `int` and a floating literal is
    // `double`, exactly as they are in an ordinary expression.
    func TryGetNaturalType(node: ColumnarAttributeArgumentNode, out naturalType: Type): bool {
        naturalType = typeof(object)
        if node.Kind == ColumnarAttributeArgumentKind.StringLiteral {
            naturalType = typeof(string)
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.BoolLiteral || node.Kind == ColumnarAttributeArgumentKind.LogicalNot {
            naturalType = typeof(bool)
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.CharLiteral {
            naturalType = typeof(char)
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.FloatLiteral {
            naturalType = typeof(double)
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.TypeOf {
            naturalType = typeof(Type)
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.IntLiteral {
            literalKind := 0
            magnitude := 0UL
            if !ColumnarScalarLiteralPlanner.TryParseIntegerLiteral(node.Text, out literalKind, out magnitude) {
                return false
            }

            naturalType = IntegerLiteralType(literalKind)
            return true
        }

        if node.Kind == ColumnarAttributeArgumentKind.Negate || node.Kind == ColumnarAttributeArgumentKind.BitwiseNot {
            return TryGetNaturalType(node.Children[0], out naturalType)
        }

        if node.Kind == ColumnarAttributeArgumentKind.BitwiseOr || node.Kind == ColumnarAttributeArgumentKind.BitwiseAnd || node.Kind == ColumnarAttributeArgumentKind.BitwiseXor {
            return TryGetNaturalType(node.Children[0], out naturalType)
        }

        if node.Kind == ColumnarAttributeArgumentKind.MemberPath {
            return TryGetConstantMemberType(node.Text, out naturalType)
        }

        // AN ARRAY LITERAL IN AN `object` POSITION takes its element type from its FIRST element, which
        // is the only element whose type C# would infer it from. An empty one has no element type and
        // is refused rather than guessed as `object[]`.
        if node.Kind == ColumnarAttributeArgumentKind.ArrayLiteral && node.Children.Count > 0 {
            elementType: Type = typeof(object)
            if !TryGetNaturalType(node.Children[0], out elementType) {
                return false
            }

            naturalType = elementType.MakeArrayType()
            return true
        }

        return false
    }

    static func IntegerLiteralType(literalKind: int): Type {
        if literalKind == 1 {
            return typeof(long)
        }

        if literalKind == 2 {
            return typeof(ulong)
        }

        if literalKind == 3 {
            return typeof(uint)
        }

        return typeof(int)
    }

    // ------------------------------------------------------------------------------------------
    // NAME RESOLUTION. A dotted path in an attribute argument names a STATIC CONSTANT — an enum
    // member or a `const` field — and it is resolved through the same canonical type resolver every
    // other type name in the emitter goes through. There is no table of known containers.
    // ------------------------------------------------------------------------------------------

    func TryResolveConstantMember(path: string, out constantValue: object?): bool {
        constantValue = null
        separator := path.LastIndexOf(".", StringComparison.Ordinal)
        if separator <= 0 || separator + 1 >= path.Length {
            return false
        }

        containerSpelling := path.Substring(0, separator)
        memberName := path.Substring(separator + 1)
        sourceEnumValue := 0
        if TryGetSourceEnumMemberValue(containerSpelling, memberName, out sourceEnumValue) {
            constantValue = sourceEnumValue
            return true
        }

        containerType: Type = typeof(object)
        if !TryResolveWrittenType(containerSpelling, out containerType) || IsUnbakedBuilderType(containerType) {
            return false
        }

        field := containerType.GetField(memberName, BindingFlags.Public | BindingFlags.Static)
        if field == null || !field.get_IsLiteral() {
            return false
        }

        constantValue = field.GetRawConstantValue()
        return constantValue != null
    }

    // A SOURCE ENUM'S MEMBERS ARE DECLARATION FACTS, NOT METADATA. `EnumBuilder.CreateType()` on the
    // persisted builder answers a type that is still a BUILDER — `GetField` on it throws
    // `NotSupportedException` rather than returning the literal — so the member's value is read from
    // the definition the emitter already keeps for the enum. A STRING-backed enum is not an enum in
    // metadata at all and is not answered here.
    func TryGetSourceEnumMemberValue(containerSpelling: string, memberName: string, out value: int): bool {
        value = 0
        definition: ColumnarEnumDef = null
        if !resolution.Enums.TryGetValue(containerSpelling, out definition) || definition == null || definition.IsStringBacked {
            return false
        }

        return definition.Constants.TryGetValue(memberName, out value)
    }

    func TryGetConstantMemberType(path: string, out memberType: Type): bool {
        memberType = typeof(object)
        separator := path.LastIndexOf(".", StringComparison.Ordinal)
        if separator <= 0 || separator + 1 >= path.Length {
            return false
        }

        containerSpelling := path.Substring(0, separator)
        memberName := path.Substring(separator + 1)
        containerType: Type = typeof(object)
        if !TryResolveWrittenType(containerSpelling, out containerType) {
            return false
        }

        // A SOURCE ENUM MEMBER'S TYPE IS THE ENUM, and the enum is a builder that answers no field
        // question — the registry says whether the member exists and the container type is the answer.
        sourceEnumValue := 0
        if TryGetSourceEnumMemberValue(containerSpelling, memberName, out sourceEnumValue) {
            memberType = containerType
            return true
        }

        if IsUnbakedBuilderType(containerType) {
            return false
        }

        field := containerType.GetField(memberName, BindingFlags.Public | BindingFlags.Static)
        if field == null || !field.get_IsLiteral() {
            return false
        }

        memberType = field.get_FieldType()
        return true
    }

    func TryResolveWrittenType(spelling: string, out resolvedType: Type): bool {
        resolvedType = typeof(object)
        candidate: Type = null
        if !ColumnarCanonicalTypeResolver.TryResolveType(spelling.Trim(), resolution.Enums, resolution.Structs, resolution.Unions, out candidate) || candidate == null {
            return false
        }

        resolvedType = candidate
        return true
    }

    // THE NAME A `Type` ARGUMENT OR AN ENUM'S TYPE CODE CARRIES. A type still being built answers its
    // plain full name — it lives in the assembly the blob is going into — and everything else answers
    // the assembly-qualified name a reader outside that assembly needs.
    static func TryGetMetadataTypeName(clrType: Type, out typeName: string): bool {
        typeName = ""
        fullName := clrType.get_FullName()
        if fullName == null {
            return false
        }

        if IsUnbakedBuilderType(clrType) {
            typeName = fullName
            return true
        }

        qualified := clrType.get_AssemblyQualifiedName()
        if qualified == null {
            typeName = fullName
            return true
        }

        typeName = qualified
        return true
    }

    // ------------------------------------------------------------------------------------------
    // TYPE QUESTIONS. Asked by FULL NAME rather than by identity because an emitted assembly's
    // `System.Type` and a reference-loaded one are different `Type` instances for the same type.
    // ------------------------------------------------------------------------------------------

    static func IsObjectType(clrType: Type): bool {
        return clrType.get_FullName() == "System.Object"
    }

    static func IsStringType(clrType: Type): bool {
        return clrType.get_FullName() == "System.String"
    }

    static func IsTypeHandleType(clrType: Type): bool {
        return clrType.get_FullName() == "System.Type"
    }

    static func IsEnumType(clrType: Type): bool {
        baseType := clrType.get_BaseType()
        if baseType != null && baseType.get_FullName() == "System.Enum" {
            return true
        }

        if IsUnbakedBuilderType(clrType) {
            return false
        }

        return clrType.get_IsEnum()
    }

    // AN ENUM'S UNDERLYING TYPE IS THE TYPE OF ITS `value__` FIELD — for every enum that came from
    // metadata. `Enum.GetUnderlyingType` is not the door because it needs a runtime type and a
    // reference-loaded enum is not one.
    //
    // A SOURCE ENUM IS NOT ASKED AT ALL. Its `CreateType()` answers a builder, which throws rather
    // than answering `GetField`, and its underlying type is a declaration fact: the emitter's enum
    // pass defines every source enum with `DefineEnum(..., typeof(int))`.
    func TryGetEnumUnderlyingType(enumType: Type, out underlyingType: Type): bool {
        underlyingType = typeof(int)
        if IsSourceEnumType(enumType) {
            return true
        }

        if IsUnbakedBuilderType(enumType) {
            return false
        }

        field := enumType.GetField("value__", BindingFlags.Public | BindingFlags.Instance | BindingFlags.NonPublic)
        if field == null {
            return false
        }

        underlyingType = field.get_FieldType()
        return true
    }

    func IsSourceEnumType(candidate: Type): bool {
        for definition in resolution.Enums.Values {
            if definition != null && !definition.IsStringBacked && definition.EnumType == candidate {
                return true
            }
        }

        return false
    }

    // A TYPE STILL BEING BUILT ANSWERS ALMOST NO REFLECTION QUESTION. `TypeBuilder` throws
    // `NotSupportedException: This non-CLS method is not implemented.` from `GetField`, `GetProperty`,
    // `GetConstructors` and `AssemblyQualifiedName`, and a persisted `EnumBuilder`'s CREATED type is
    // still one of these. Every reflection call in this owner is guarded by this question.
    static func IsUnbakedBuilderType(candidate: Type): bool {
        return typeof(TypeBuilder).IsInstanceOfType(candidate) || typeof(EnumBuilder).IsInstanceOfType(candidate) || typeof(GenericTypeParameterBuilder).IsInstanceOfType(candidate)
    }
}
