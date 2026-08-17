namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Reflection
import System.Reflection.Emit
import System.Text
import System.Text.Json
import System.Threading.Tasks
import YamlDotNet.Serialization


// Exact result of runtime instance-member binding. Source TypeBuilder definitions use the
// source-definition resolver instead; this row owns only the established baked/BCL/external
// receiver surface.
class ColumnarRuntimeInstanceMemberSelection {
    IsField: bool
    DeclaringType: Type
    ResultType: Type
    Field: FieldInfo?
    Getter: MethodInfo?
    ReceiverIsReference: bool

    constructor(isField: bool, declaringType: Type, resultType: Type, field: FieldInfo?, getter: MethodInfo?, receiverIsReference: bool) {
        IsField = isField
        DeclaringType = declaringType
        ResultType = resultType
        Field = field
        Getter = getter
        ReceiverIsReference = receiverIsReference
    }

    static func Empty(): ColumnarRuntimeInstanceMemberSelection {
        return new ColumnarRuntimeInstanceMemberSelection(false, typeof(object), typeof(object), null, null, false)
    }
}

// Runtime half of ordinary instance field/property binding. The allow-set deliberately matches
// the former production case-8 clauses: it is not a general reflection or dynamic-member binder.
// Selection completes before a code plan emits the receiver, so every false result is atomic.
class ColumnarRuntimeInstanceMemberResolver {
    static func CanOwnReceiver(receiverType: Type): bool {
        if receiverType == null || IsSourceBuilderShape(receiverType) || receiverType.get_IsByRef() || receiverType.get_IsGenericTypeDefinition() || receiverType.get_IsSZArray() {
            return false
        }

        if receiverType == typeof(string) || receiverType == typeof(StringBuilder) || receiverType == typeof(Version) || receiverType == typeof(TimeSpan) {
            return true
        }

        if receiverType == typeof(DateTime) || receiverType == typeof(Type) || receiverType == typeof(Process) || receiverType == typeof(IList) || receiverType == typeof(JsonSerializerOptions) {
            return true
        }

        jsonPropertyType := RequiredJsonType("System.Text.Json.JsonProperty")
        jsonArrayEnumeratorType := RequiredJsonType("System.Text.Json.JsonElement+ArrayEnumerator")

        jsonObjectEnumeratorType := RequiredJsonType("System.Text.Json.JsonElement+ObjectEnumerator")

        yamlParserType := RequiredYamlType("YamlDotNet.Core.IParser")
        yamlScalarType := RequiredYamlType("YamlDotNet.Core.Events.Scalar")

        if receiverType == typeof(Assembly) {
            return true
        }

        if receiverType == typeof(JsonDocument) {
            return true
        }

        if receiverType == typeof(JsonElement) {
            return true
        }

        if receiverType == jsonPropertyType {
            return true
        }

        if receiverType == jsonArrayEnumeratorType {
            return true
        }

        if receiverType == jsonObjectEnumeratorType {
            return true
        }

        if receiverType == yamlParserType {
            return true
        }

        if receiverType == yamlScalarType {
            return true
        }

        if IsSupportedXmlLinqReceiver(receiverType) {
            return true
        }

        if typeof(Exception).IsAssignableFrom(receiverType) || IsSupportedAspNetReceiver(receiverType) || IsSupportedTaskReceiver(receiverType) || IsSupportedUnitTaskReceiver(receiverType) || IsSupportedNullableReceiver(receiverType) || IsSupportedResultReceiver(receiverType) || IsSupportedMemoryOwnerReceiver(receiverType) || IsSupportedMemoryReceiver(receiverType) || IsSupportedCountReceiver(receiverType) || IsSupportedKeyValuePairReceiver(receiverType) || IsSupportedSpanLikeReceiver(receiverType) || IsSupportedValueTupleReceiver(receiverType) {
            return true
        }

        return false
    }

    // THE LINQ-TO-XML RECEIVERS THE DOC WALK HOLDS. Matched by exact metadata name, for the same
    // reason the WebApplication arm below is: this assembly cannot reference the Linq-to-XML types by
    // spelling, because the toolset that compiles it has no rows for them yet. A source-declared
    // namesake cannot reach this test — `CanOwnReceiver` rejects every builder shape first — and
    // `TrySelect` still resolves each getter by reflection ON THE RECEIVER and demands an exact
    // result-type shape, so a namesake without those properties selects nothing.
    static func IsSupportedXmlLinqReceiver(receiverType: Type): bool {
        name := receiverType.FullName ?? ""
        return name == "System.Xml.Linq.XDocument" || name == "System.Xml.Linq.XElement" || name == "System.Xml.Linq.XName" || name == "System.Xml.Linq.XAttribute" || name == "System.Xml.Linq.XText"
    }

    // A type from the SAME assembly the receiver came from. Resolving the expected result type out of
    // the receiver's own assembly is stronger than a load-context lookup: it cannot answer with a
    // same-named type from somewhere else.
    static func RequiredXmlLinqType(receiverType: Type, fullName: string): Type {
        return RequiredAssemblyType(receiverType.get_Assembly(), fullName)
    }

    static func TrySelect(receiverType: Type, member: string, out selection: ColumnarRuntimeInstanceMemberSelection): bool {
        selection = EmptySelection()
        if receiverType == null || member == null || member.Length == 0 || !CanOwnReceiver(receiverType) {
            return false
        }

        jsonPropertyType := RequiredJsonType("System.Text.Json.JsonProperty")
        jsonArrayEnumeratorType := RequiredJsonType("System.Text.Json.JsonElement+ArrayEnumerator")

        jsonObjectEnumeratorType := RequiredJsonType("System.Text.Json.JsonElement+ObjectEnumerator")

        yamlParserType := RequiredYamlType("YamlDotNet.Core.IParser")
        yamlScalarType := RequiredYamlType("YamlDotNet.Core.Events.Scalar")
        parsingEventType := RequiredYamlType("YamlDotNet.Core.Events.ParsingEvent")

        if IsSupportedValueTupleReceiver(receiverType) {
            return TrySelectValueTupleField(receiverType, member, out selection)
        }

        if typeof(Exception).IsAssignableFrom(receiverType) && member == "Message" {
            return TrySelectExpectedProperty(receiverType, typeof(Exception), member, typeof(string), out selection)
        }

        if receiverType == typeof(Version) && (member == "Major" || member == "Minor" || member == "Build" || member == "Revision") {
            return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(int), out selection)
        }

        if receiverType == typeof(TimeSpan) && member == "TotalMilliseconds" {
            return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(double), out selection)
        }

        if receiverType == typeof(DateTime) {
            return TrySelectAdmittedProperty(receiverType, receiverType, member, out selection)
        }

        if receiverType == typeof(JsonElement) && member == "ValueKind" {
            return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(JsonValueKind), out selection)
        }

        if receiverType == typeof(JsonSerializerOptions) && member == "WriteIndented" {
            return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(bool), out selection)
        }

        if receiverType == jsonArrayEnumeratorType && member == "Current" {
            return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(JsonElement), out selection)
        }

        if receiverType == jsonObjectEnumeratorType && member == "Current" {
            return TrySelectExpectedProperty(receiverType, receiverType, member, jsonPropertyType, out selection)
        }

        if receiverType == jsonPropertyType && member == "Name" {
            return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(string), out selection)
        }

        if receiverType == jsonPropertyType && member == "Value" {
            return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(JsonElement), out selection)
        }

        if receiverType == typeof(Type) && (member == "Name" || member == "FullName" || member == "Namespace" || member == "IsNested") {
            expected := typeof(string)
            if member == "IsNested" {
                expected = typeof(bool)
            }

            return TrySelectExpectedProperty(receiverType, receiverType, member, expected, out selection)
        }

        if receiverType == yamlParserType && member == "Current" {
            return TrySelectExpectedProperty(receiverType, receiverType, member, parsingEventType, out selection)
        }

        if receiverType == yamlScalarType && member == "Value" {
            return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(string), out selection)
        }

        if receiverType == typeof(Process) {
            if member == "ExitCode" {
                return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(int), out selection)
            }

            if member == "StandardOutput" || member == "StandardError" {
                return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(StreamReader), out selection)
            }

            return false
        }

        if IsSupportedTaskReceiver(receiverType) && member == "Result" {
            arguments := receiverType.GetGenericArguments()
            return TrySelectExpectedProperty(receiverType, receiverType, member, arguments[0], out selection)
        }

        // `IsCompleted` answers on both task shapes: the bare `Task` a unit async function
        // returns, and the generic `Task<T>`.
        if member == "IsCompleted" {
            if IsSupportedUnitTaskReceiver(receiverType) || IsSupportedTaskReceiver(receiverType) {
                return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(bool), out selection)
            }
        }

        if receiverType == typeof(IList) && member == "Count" {
            collectionType := RequiredAssemblyType(typeof(object).get_Assembly(), "System.Collections.ICollection")

            return TrySelectExpectedProperty(receiverType, collectionType, member, typeof(int), out selection)
        }

        if receiverType == typeof(Assembly) && (member == "IsDynamic" || member == "IsCollectible") {
            return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(bool), out selection)
        }

        if receiverType == typeof(JsonDocument) && member == "RootElement" {
            return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(JsonElement), out selection)
        }

        // THE SIX XML DOC PROPERTY READS. Each names its exact result: the document's root element,
        // an element's text and its name, that name's local part, and the text an attribute or a text
        // node carries. `XElement.Value` and `XText.Value` are DIFFERENT properties on different
        // types that happen to share a name and a result, so both are spelled.
        if IsSupportedXmlLinqReceiver(receiverType) {
            receiverName := receiverType.FullName ?? ""
            if receiverName == "System.Xml.Linq.XDocument" && member == "Root" {
                return TrySelectExpectedProperty(receiverType, receiverType, member, RequiredXmlLinqType(receiverType, "System.Xml.Linq.XElement"), out selection)
            }

            if receiverName == "System.Xml.Linq.XElement" && member == "Name" {
                return TrySelectExpectedProperty(receiverType, receiverType, member, RequiredXmlLinqType(receiverType, "System.Xml.Linq.XName"), out selection)
            }

            if member == "Value" && (receiverName == "System.Xml.Linq.XElement" || receiverName == "System.Xml.Linq.XAttribute" || receiverName == "System.Xml.Linq.XText") {
                return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(string), out selection)
            }

            if receiverName == "System.Xml.Linq.XName" && member == "LocalName" {
                return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(string), out selection)
            }

            return false
        }

        // The old WebApplication arm repeated the general ASP.NET rule but omitted its result
        // admission check. Environment's exact result is itself on the admitted external surface.
        if receiverType.FullName == "Microsoft.AspNetCore.Builder.WebApplication" && member == "Environment" {
            return TrySelectAdmittedProperty(receiverType, receiverType, member, out selection)
        }

        if IsSupportedAspNetReceiver(receiverType) {
            return TrySelectAdmittedProperty(receiverType, receiverType, member, out selection)
        }

        if IsSupportedNullableReceiver(receiverType) && (member == "HasValue" || member == "Value") {
            expected := typeof(bool)
            if member == "Value" {
                expected = receiverType.GetGenericArguments()[0]
            }

            return TrySelectExpectedProperty(receiverType, receiverType, member, expected, out selection)
        }

        if IsSupportedResultReceiver(receiverType) {
            resultArguments := receiverType.GetGenericArguments()
            expected := typeof(object)
            if member == "IsOk" || member == "IsErr" {
                expected = typeof(bool)
            } else if member == "OkValue" || member == "OkValueUnchecked" {
                expected = resultArguments[0]
            } else if member == "ErrValue" || member == "ErrValueUnchecked" {
                expected = resultArguments[1]
            } else {
                return false
            }

            return TrySelectExpectedProperty(receiverType, receiverType, member, expected, out selection)
        }

        if IsSupportedMemoryOwnerReceiver(receiverType) && member == "Memory" {
            return TrySelectAdmittedProperty(receiverType, receiverType, member, out selection)
        }

        if IsSupportedMemoryReceiver(receiverType) && member == "Span" {
            return TrySelectAdmittedProperty(receiverType, receiverType, member, out selection)
        }

        if IsSupportedCountReceiver(receiverType) && (member == "Count" || member == "Capacity" && receiverType.GetGenericTypeDefinition() == typeof(List<int>).GetGenericTypeDefinition()) {
            countOwner := receiverType
            if member == "Count" {
                definition := receiverType.GetGenericTypeDefinition()
                if definition == typeof(IReadOnlyList<int>).GetGenericTypeDefinition() || definition == typeof(IReadOnlySet<int>).GetGenericTypeDefinition() {
                    countOwner = typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition().MakeGenericType(receiverType.GetGenericArguments())
                }
            }

            return TrySelectExpectedProperty(receiverType, countOwner, member, typeof(int), out selection)
        }

        if IsSupportedKeyValuePairReceiver(receiverType) && (member == "Key" || member == "Value") {
            pairArguments := receiverType.GetGenericArguments()
            expected := pairArguments[0]
            if member == "Value" {
                expected = pairArguments[1]
            }

            return TrySelectExpectedProperty(receiverType, receiverType, member, expected, out selection)
        }

        if (receiverType == typeof(string) || receiverType == typeof(StringBuilder) || IsSupportedSpanLikeReceiver(receiverType)) && member == "Length" {
            return TrySelectExpectedProperty(receiverType, receiverType, member, typeof(int), out selection)
        }

        return false
    }

    static func TrySelectValueTupleField(receiverType: Type, member: string, out selection: ColumnarRuntimeInstanceMemberSelection): bool {
        selection = EmptySelection()
        if member.Length <= 4 || !member.StartsWith("Item", StringComparison.Ordinal) || !char.IsDigit(member[4]) {
            return false
        }

        field := receiverType.GetField(member)
        if field == null || !field.get_IsPublic() || field.get_IsStatic() || field.get_IsLiteral() {
            return false
        }

        declaringType := field.get_DeclaringType()
        resultType := field.get_FieldType()
        if declaringType == null || declaringType != receiverType || !IsSelectableResultType(resultType) {
            return false
        }

        selection = new ColumnarRuntimeInstanceMemberSelection(true, declaringType, resultType, field, null, false)

        return true
    }

    static func TrySelectExpectedProperty(receiverType: Type, lookupType: Type, member: string, expectedResultType: Type, out selection: ColumnarRuntimeInstanceMemberSelection): bool {
        selection = EmptySelection()
        getter: MethodInfo? = null
        declaringType := typeof(object)
        resultType := typeof(object)
        if !TryResolvePublicGetter(lookupType, member, out getter, out declaringType, out resultType) || getter == null || !ExactTypeShapeMatches(resultType, expectedResultType) || !IsSelectableResultType(expectedResultType) || !ReceiverMatchesDeclaringType(receiverType, declaringType) {
            return false
        }

        receiverIsReference := !receiverType.get_IsValueType()
        selection = new ColumnarRuntimeInstanceMemberSelection(false, declaringType, expectedResultType, null, getter, receiverIsReference)

        return true
    }

    static func TrySelectAdmittedProperty(receiverType: Type, lookupType: Type, member: string, out selection: ColumnarRuntimeInstanceMemberSelection): bool {
        selection = EmptySelection()
        getter: MethodInfo? = null
        declaringType := typeof(object)
        resultType := typeof(object)
        if !TryResolvePublicGetter(lookupType, member, out getter, out declaringType, out resultType) || getter == null || !IsAdmittedValueType(resultType) || !ReceiverMatchesDeclaringType(receiverType, declaringType) {
            return false
        }

        receiverIsReference := !receiverType.get_IsValueType()
        selection = new ColumnarRuntimeInstanceMemberSelection(false, declaringType, resultType, null, getter, receiverIsReference)

        return true
    }

    static func TryResolvePublicGetter(lookupType: Type, member: string, out getter: MethodInfo?, out declaringType: Type, out resultType: Type): bool {
        getter = null
        declaringType = typeof(object)
        resultType = typeof(object)

        signatureGetter: MethodInfo? = null
        if ContainsBuilderBoundType(lookupType) {
            if !lookupType.get_IsGenericType() || lookupType.get_IsGenericTypeDefinition() {
                return false
            }

            definition := lookupType.GetGenericTypeDefinition()
            if definition is TypeBuilder {
                return false
            }

            property := definition.GetProperty(member)
            if property == null {
                return false
            }

            signatureGetter = property.GetGetMethod()
            if signatureGetter == null || !ValidatePublicGetterSignature(signatureGetter) {
                return false
            }

            rebound := TypeBuilder.GetMethod(lookupType, signatureGetter)
            if rebound == null {
                return false
            }

            getter = (MethodInfo)rebound
            resultType = SubstituteClosedTypeArguments(property.get_PropertyType(), lookupType.GetGenericArguments())
        } else {
            property := lookupType.GetProperty(member)
            if property == null {
                return false
            }

            signatureGetter = property.GetGetMethod()
            if signatureGetter == null || !ValidatePublicGetterSignature(signatureGetter) {
                return false
            }

            getter = signatureGetter
            resultType = property.get_PropertyType()
        }

        exactGetter := getter
        if exactGetter == null || !exactGetter.get_IsPublic() || exactGetter.get_IsStatic() {
            getter = null
            return false
        }

        exactDeclaringType := exactGetter.get_DeclaringType()
        if exactDeclaringType == null {
            getter = null
            return false
        }

        declaringType = exactDeclaringType

        actualReturn := exactGetter.get_ReturnType()
        if lookupType.get_IsGenericType() && !lookupType.get_IsGenericTypeDefinition() {
            actualReturn = SubstituteClosedTypeArguments(actualReturn, lookupType.GetGenericArguments())
        }

        if !ExactTypeShapeMatches(actualReturn, resultType) || !IsSelectableResultType(resultType) {
            getter = null
            return false
        }

        return true
    }

    static func ValidatePublicGetterSignature(getter: MethodInfo): bool {
        if getter == null || !getter.get_IsPublic() || getter.get_IsStatic() || getter.get_IsGenericMethodDefinition() || getter.get_ReturnType().get_IsByRef() {
            return false
        }

        parameters := getter.GetParameters()
        return parameters.Length == 0
    }

    static func ReceiverMatchesDeclaringType(receiverType: Type, declaringType: Type): bool {
        if ExactTypeShapeMatches(receiverType, declaringType) {
            return true
        }

        if receiverType.get_IsValueType() || declaringType.get_IsValueType() {
            return false
        }

        // Reflection.Emit's BCL-headed constructed wrappers do not implement IsAssignableFrom.
        // Count is the one admitted member whose exact getter owner can be an interface base of
        // such a wrapper: IReadOnlyList<T>/IReadOnlySet<T> inherit IReadOnlyCollection<T>.
        if ContainsBuilderBoundType(receiverType) || ContainsBuilderBoundType(declaringType) {
            if !receiverType.get_IsGenericType() || !declaringType.get_IsGenericType() || receiverType.get_IsGenericTypeDefinition() || declaringType.get_IsGenericTypeDefinition() {
                return false
            }

            receiverDefinition := receiverType.GetGenericTypeDefinition()
            declaringDefinition := declaringType.GetGenericTypeDefinition()
            if declaringDefinition != typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition() || (receiverDefinition != typeof(IReadOnlyList<int>).GetGenericTypeDefinition() && receiverDefinition != typeof(IReadOnlySet<int>).GetGenericTypeDefinition()) {
                return false
            }

            receiverArguments := receiverType.GetGenericArguments()
            declaringArguments := declaringType.GetGenericArguments()
            return receiverArguments.Length == 1 && declaringArguments.Length == 1 && ExactTypeShapeMatches(receiverArguments[0], declaringArguments[0])
        }

        return declaringType.IsAssignableFrom(receiverType)
    }

    static func IsSelectableResultType(valueType: Type): bool {
        return valueType != null && valueType.FullName != "System.Void" && !valueType.get_IsByRef() && !valueType.get_IsGenericTypeDefinition()
    }

    static func IsSourceBuilderShape(valueType: Type): bool {
        if valueType is TypeBuilder || IsEnumBuilder(valueType) {
            return true
        }

        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }

        definition := valueType.GetGenericTypeDefinition()
        return definition is TypeBuilder || IsEnumBuilder(definition)
    }

    static func ContainsBuilderBoundType(valueType: Type): bool {
        if valueType is TypeBuilder || IsEnumBuilder(valueType) || valueType.get_IsGenericParameter() {
            return true
        }

        if valueType.get_IsSZArray() {
            elementType := valueType.GetElementType()
            return elementType != null && ContainsBuilderBoundType(elementType)
        }

        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }

        definition := valueType.GetGenericTypeDefinition()
        if definition is TypeBuilder || IsEnumBuilder(definition) {
            return true
        }

        arguments := valueType.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            if ContainsBuilderBoundType(arguments[index]) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func SubstituteClosedTypeArguments(signatureType: Type, closedArguments: Type[]): Type {
        if signatureType.get_IsGenericParameter() {
            if signatureType.get_DeclaringMethod() == null {
                position := signatureType.get_GenericParameterPosition()
                if position >= 0 && position < closedArguments.Length {
                    return closedArguments[position]
                }
            }

            return signatureType
        }

        if signatureType.get_IsSZArray() {
            elementType := signatureType.GetElementType()
            if elementType == null {
                return signatureType
            }

            return SubstituteClosedTypeArguments(elementType, closedArguments).MakeArrayType()
        }

        if signatureType.get_IsGenericType() && !signatureType.get_IsGenericTypeDefinition() {
            definition := signatureType.GetGenericTypeDefinition()
            arguments := signatureType.GetGenericArguments()
            substituted := new Type[](arguments.Length)
            index := 0
            while index < arguments.Length {
                substituted[index] = SubstituteClosedTypeArguments(arguments[index], closedArguments)

                index = index + 1
            }

            return definition.MakeGenericType(substituted)
        }

        return signatureType
    }

    static func ExactTypeShapeMatches(left: Type, right: Type): bool {
        if left == right {
            return true
        }

        if left.get_IsSZArray() && right.get_IsSZArray() {
            leftElement := left.GetElementType()
            rightElement := right.GetElementType()
            return leftElement != null && rightElement != null && ExactTypeShapeMatches(leftElement, rightElement)
        }

        if !left.get_IsGenericType() || !right.get_IsGenericType() || left.get_IsGenericTypeDefinition() || right.get_IsGenericTypeDefinition() || left.GetGenericTypeDefinition() != right.GetGenericTypeDefinition() {
            return false
        }

        leftArguments := left.GetGenericArguments()
        rightArguments := right.GetGenericArguments()
        if leftArguments.Length != rightArguments.Length {
            return false
        }

        index := 0
        while index < leftArguments.Length {
            if !ExactTypeShapeMatches(leftArguments[index], rightArguments[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func IsSupportedTaskReceiver(valueType: Type): bool {
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }

        return valueType.GetGenericTypeDefinition() == typeof(Task<int>).GetGenericTypeDefinition() && IsAdmittedValueType(valueType.GetGenericArguments()[0])
    }

    // The BARE `Task` a unit async function answers with. Read by name because the pinned
    // toolset's `typeof` surface does not carry the non-generic task types.
    static func IsSupportedUnitTaskReceiver(valueType: Type): bool {
        return valueType == RequiredAssemblyType(typeof(object).get_Assembly(), "System.Threading.Tasks.Task")
    }

    static func IsSupportedNullableReceiver(valueType: Type): bool {
        nullableDefinition := RequiredAssemblyType(typeof(object).get_Assembly(), "System.Nullable`1")

        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() || valueType.GetGenericTypeDefinition() != nullableDefinition {
            return false
        }

        return IsLiftableNullableElement(valueType.GetGenericArguments()[0])
    }

    static func IsLiftableNullableElement(valueType: Type): bool {
        return valueType == typeof(int) || valueType == typeof(long) || valueType == typeof(ulong) || valueType == typeof(uint) || valueType == typeof(short) || valueType == typeof(ushort) || valueType == typeof(byte) || valueType == typeof(sbyte) || valueType == typeof(bool) || valueType == typeof(char) || valueType == typeof(double) || valueType == typeof(float) || valueType == typeof(decimal) || valueType == typeof(TimeSpan) || IsSupportedValueTupleReceiver(valueType)
    }

    static func IsSupportedResultReceiver(valueType: Type): bool {
        resultDefinition := Type.GetType("NSharpLang.Runtime.Result`2, NSharpLang.Runtime")
        if resultDefinition == null || !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() || valueType.GetGenericTypeDefinition() != resultDefinition {
            return false
        }

        arguments := valueType.GetGenericArguments()
        return arguments.Length == 2 && !IsByRefLike(arguments[0]) && !IsByRefLike(arguments[1]) && IsAdmittedValueType(arguments[0]) && IsAdmittedValueType(arguments[1])
    }

    static func IsByRefLike(valueType: Type): bool {
        try {
            return valueType.get_IsByRefLike()
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
    }

    static func IsSupportedMemoryOwnerReceiver(valueType: Type): bool {
        definition := RequiredAssemblyType(typeof(object).get_Assembly(), "System.Buffers.IMemoryOwner`1")

        return IsClosedGenericWithSingleByteArgument(valueType, definition)
    }

    static func IsSupportedMemoryReceiver(valueType: Type): bool {
        definition := RequiredAssemblyType(typeof(object).get_Assembly(), "System.Memory`1")

        return IsClosedGenericWithSingleByteArgument(valueType, definition)
    }

    static func IsClosedGenericWithSingleByteArgument(valueType: Type, definition: Type): bool {
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() || valueType.GetGenericTypeDefinition() != definition {
            return false
        }

        arguments := valueType.GetGenericArguments()
        return arguments.Length == 1 && arguments[0] == typeof(byte)
    }

    static func IsSupportedCountReceiver(valueType: Type): bool {
        if !IsSupportedCollectionType(valueType) {
            return false
        }

        return valueType.GetGenericTypeDefinition() != typeof(IEnumerable<int>).GetGenericTypeDefinition()
    }

    static func IsSupportedCollectionType(valueType: Type): bool {
        if valueType is TypeBuilder || !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }

        definition := valueType.GetGenericTypeDefinition()
        return definition == typeof(List<int>).GetGenericTypeDefinition() || definition == typeof(Dictionary<int, int>).GetGenericTypeDefinition() || definition == typeof(SortedDictionary<int, int>).GetGenericTypeDefinition() || definition == typeof(HashSet<int>).GetGenericTypeDefinition() || definition == typeof(Stack<int>).GetGenericTypeDefinition() || definition == typeof(IReadOnlyList<int>).GetGenericTypeDefinition() || definition == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition() || definition == typeof(IReadOnlySet<int>).GetGenericTypeDefinition() || (definition.FullName ?? "") == "System.Collections.Generic.IReadOnlyDictionary`2" || definition == typeof(IEnumerable<int>).GetGenericTypeDefinition()
    }

    static func IsSupportedKeyValuePairReceiver(valueType: Type): bool {
        if valueType is TypeBuilder || !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }

        definition := RequiredAssemblyType(typeof(object).get_Assembly(), "System.Collections.Generic.KeyValuePair`2")

        return valueType.GetGenericTypeDefinition() == definition
    }

    static func IsSupportedSpanLikeReceiver(valueType: Type): bool {
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }

        definition := valueType.GetGenericTypeDefinition()
        spanDefinition := RequiredAssemblyType(typeof(object).get_Assembly(), "System.Span`1")

        readOnlySpanDefinition := RequiredAssemblyType(typeof(object).get_Assembly(), "System.ReadOnlySpan`1")

        if definition != spanDefinition && definition != readOnlySpanDefinition {
            return false
        }

        return IsSupportedSpanElement(valueType.GetGenericArguments()[0])
    }

    static func IsSupportedSpanElement(valueType: Type): bool {
        return valueType == typeof(bool) || valueType == typeof(int) || valueType == typeof(uint) || valueType == typeof(long) || valueType == typeof(ulong) || valueType == typeof(byte) || valueType == typeof(sbyte) || valueType == typeof(short) || valueType == typeof(ushort) || valueType == typeof(char) || valueType == typeof(double) || valueType == typeof(float) || IsEnumType(valueType)
    }

    static func IsSupportedValueTupleReceiver(valueType: Type): bool {
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }

        definition := valueType.GetGenericTypeDefinition()
        if definition != typeof(ValueTuple<int, int>).GetGenericTypeDefinition() && definition != typeof(ValueTuple<int, int, int>).GetGenericTypeDefinition() && definition != typeof(ValueTuple<int, int, int, int>).GetGenericTypeDefinition() && definition != typeof(ValueTuple<int, int, int, int, int>).GetGenericTypeDefinition() && definition != typeof(ValueTuple<int, int, int, int, int, int>).GetGenericTypeDefinition() && definition != typeof(ValueTuple<int, int, int, int, int, int, int>).GetGenericTypeDefinition() {
            return false
        }

        arguments := valueType.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            argument := arguments[index]
            if IsEnumType(argument) || argument is TypeBuilder || IsSourceBuilderShape(argument) || IsSupportedDelegateType(argument) || ContainsBuilderBoundType(argument) || !IsAdmittedValueType(argument) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func IsSupportedAspNetReceiver(valueType: Type): bool {
        if !IsSupportedExternalReferenceShape(valueType) {
            return false
        }

        namespaceName := valueType.Namespace ?? ""
        return namespaceName.StartsWith("Microsoft.AspNetCore.", StringComparison.Ordinal) || namespaceName.StartsWith("Microsoft.Extensions.Hosting", StringComparison.Ordinal)
    }

    static func IsSupportedExternalReferenceShape(valueType: Type): bool {
        return !valueType.get_IsValueType() && !valueType.get_HasElementType() && !ContainsOpenGenericParameters(valueType)
    }

    static func ContainsOpenGenericParameters(valueType: Type): bool {
        if valueType.get_IsGenericParameter() || valueType.get_IsGenericTypeDefinition() {
            return true
        }

        if !valueType.get_IsGenericType() {
            return false
        }

        arguments := valueType.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            if ContainsOpenGenericParameters(arguments[index]) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func IsAdmittedValueType(valueType: Type): bool {
        if !IsSelectableResultType(valueType) {
            return false
        }

        if valueType == typeof(int) || valueType == typeof(bool) || valueType == typeof(long) || valueType == typeof(ulong) || valueType == typeof(string) || valueType == typeof(char) {
            return true
        }

        if valueType == typeof(double) || valueType == typeof(float) || valueType == typeof(byte) || valueType == typeof(sbyte) || valueType == typeof(short) || valueType == typeof(ushort) || valueType == typeof(uint) {
            return true
        }

        if valueType == typeof(IntPtr) || valueType == typeof(UIntPtr) || valueType == typeof(decimal) || valueType == typeof(object) || valueType == typeof(Stream) || valueType == typeof(StreamReader) {
            return true
        }

        if valueType == typeof(StringComparer) {
            return true
        }
        textWriterType := RequiredAssemblyType(typeof(object).get_Assembly(), "System.IO.TextWriter")
        if valueType == textWriterType {
            return true
        }
        if valueType == typeof(StringBuilder) {
            return true
        }
        if valueType == typeof(DateTime) {
            return true
        }
        if valueType == typeof(TimeSpan) {
            return true
        }
        if valueType == typeof(Index) {
            return true
        }
        if valueType == typeof(Range) {
            return true
        }

        if valueType == typeof(System.Threading.CancellationToken) || valueType == typeof(Random) || valueType == typeof(IList) || valueType == typeof(Type) || valueType == typeof(Version) || valueType == typeof(Assembly) {
            return true
        }

        // The dependency-injection service collection is the receiver produced by a hosting builder's
        // `Services` property (`builder.Services.AddControllers()`); admitting it as an instance-member
        // result lets that external reference flow into extension-method resolution. Matched by exact
        // metadata name because this assembly does not reference the DI abstractions.
        if valueType.FullName == "Microsoft.Extensions.DependencyInjection.IServiceCollection" {
            return true
        }

        if ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(valueType) || IsSupportedTaskValueType(valueType) || typeof(Exception).IsAssignableFrom(valueType) || ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName(valueType.FullName) {
            return true
        }

        if IsSupportedJsonType(valueType) || IsSupportedExternalType(valueType) || IsSupportedSpanLikeReceiver(valueType) || IsSupportedArrayPoolType(valueType) || IsSupportedMemoryPoolType(valueType) {
            return true
        }

        if IsSupportedMemoryOwnerReceiver(valueType) || IsSupportedMemoryReceiver(valueType) || IsSupportedNullableReceiver(valueType) || IsSupportedResultReceiver(valueType) || IsSupportedAnonymousUnionType(valueType) {
            return true
        }

        if IsEnumType(valueType) || valueType is TypeBuilder || valueType.get_IsGenericParameter() || IsSourceBuilderShape(valueType) || IsSupportedValueTupleReceiver(valueType) {
            return true
        }

        if IsSupportedDelegateType(valueType) || IsSupportedCollectionType(valueType) {
            return true
        }

        if valueType.get_IsSZArray() {
            elementType := valueType.GetElementType()
            return elementType != null && IsSupportedElementType(elementType)
        }

        return false
    }

    static func IsSupportedTaskValueType(valueType: Type): bool {
        if valueType == typeof(Task) || valueType == typeof(ValueTask) {
            return true
        }

        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }

        definition := valueType.GetGenericTypeDefinition()
        if definition != typeof(Task<int>).GetGenericTypeDefinition() && definition != typeof(ValueTask<int>).GetGenericTypeDefinition() {
            return false
        }

        return IsAdmittedValueType(valueType.GetGenericArguments()[0])
    }

    static func IsSupportedJsonType(valueType: Type): bool {
        jsonPropertyType := RequiredJsonType("System.Text.Json.JsonProperty")
        jsonArrayEnumeratorType := RequiredJsonType("System.Text.Json.JsonElement+ArrayEnumerator")

        jsonObjectEnumeratorType := RequiredJsonType("System.Text.Json.JsonElement+ObjectEnumerator")

        return valueType == typeof(JsonElement) || valueType == typeof(JsonDocument) || valueType == typeof(JsonValueKind) || valueType == typeof(JsonSerializerOptions) || valueType == typeof(JsonNamingPolicy) || valueType == jsonArrayEnumeratorType || valueType == jsonObjectEnumeratorType || valueType == jsonPropertyType
    }

    static func IsSupportedExternalType(valueType: Type): bool {
        valueAssemblyName := valueType.get_Assembly().GetName().get_FullName()
        yamlAssemblyName := typeof(IYamlTypeConverter).get_Assembly().GetName().get_FullName()
        if String.Equals(valueAssemblyName, yamlAssemblyName, StringComparison.Ordinal) {
            return true
        }
        return IsSupportedAspNetReceiver(valueType)
    }

    static func IsSupportedArrayPoolType(valueType: Type): bool {
        definition := RequiredRuntimeType("System.Buffers.ArrayPool`1, System.Private.CoreLib")

        return IsClosedGenericWithSingleByteArgument(valueType, definition)
    }

    static func IsSupportedMemoryPoolType(valueType: Type): bool {
        definition := RequiredRuntimeType("System.Buffers.MemoryPool`1, System.Memory")

        return IsClosedGenericWithSingleByteArgument(valueType, definition)
    }

    static func IsSupportedAnonymousUnionType(valueType: Type): bool {
        unionDefinition := Type.GetType("NSharpLang.Runtime.Union`2, NSharpLang.Runtime")
        if unionDefinition == null || !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() || valueType.GetGenericTypeDefinition() != unionDefinition {
            return false
        }

        arguments := valueType.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            if !IsAdmittedValueType(arguments[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func IsSupportedDelegateType(valueType: Type): bool {
        if valueType == typeof(Action) {
            return true
        }

        if valueType is TypeBuilder || !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() || ContainsBuilderBoundType(valueType) {
            return false
        }

        definition := valueType.GetGenericTypeDefinition()
        if definition != typeof(Action<int>).GetGenericTypeDefinition() && definition != typeof(Action<int, int>).GetGenericTypeDefinition() && definition != typeof(Action<int, int, int>).GetGenericTypeDefinition() && definition != typeof(Action<int, int, int, int>).GetGenericTypeDefinition() && definition != typeof(Func<int>).GetGenericTypeDefinition() && definition != typeof(Func<int, int>).GetGenericTypeDefinition() && definition != typeof(Func<int, int, int>).GetGenericTypeDefinition() && definition != typeof(Func<int, int, int, int>).GetGenericTypeDefinition() && definition != typeof(Func<int, int, int, int, int>).GetGenericTypeDefinition() {
            return false
        }

        arguments := valueType.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            if !IsAdmittedValueType(arguments[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func IsSupportedElementType(valueType: Type): bool {
        if valueType == typeof(bool) || valueType == typeof(int) || valueType == typeof(uint) || valueType == typeof(long) || valueType == typeof(ulong) || valueType == typeof(byte) || valueType == typeof(sbyte) || valueType == typeof(short) || valueType == typeof(ushort) || valueType == typeof(char) || valueType == typeof(string) || valueType == typeof(double) || valueType == typeof(float) || valueType == typeof(IntPtr) || valueType == typeof(UIntPtr) || valueType == typeof(object) || valueType == typeof(Type) || valueType == typeof(Version) || valueType == typeof(Assembly) || IsEnumType(valueType) || valueType is TypeBuilder || valueType.get_IsGenericParameter() || ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName(valueType.FullName) || IsSupportedNullableReceiver(valueType) {
            return true
        }

        if valueType.get_IsSZArray() {
            elementType := valueType.GetElementType()
            return elementType != null && IsSupportedElementType(elementType)
        }

        return false
    }

    static func IsEnumType(valueType: Type): bool {
        if IsEnumBuilder(valueType) {
            return true
        }

        if valueType is TypeBuilder {
            try {
                baseType := valueType.get_BaseType()
                return baseType != null && baseType.FullName == "System.Enum"
            } catch ex: NotSupportedException {
                return false
            } catch ex: NotImplementedException {
                return false
            }
        }

        try {
            return valueType.get_IsEnum()
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
    }

    static func RequiredJsonType(fullName: string): Type {
        return RequiredAssemblyType(typeof(JsonElement).get_Assembly(), fullName)
    }

    static func IsEnumBuilder(valueType: Type): bool {
        return valueType != null && valueType.GetType().FullName == "System.Reflection.Emit.EnumBuilder"
    }

    static func RequiredYamlType(fullName: string): Type {
        return RequiredAssemblyType(typeof(IYamlTypeConverter).get_Assembly(), fullName)
    }

    static func RequiredAssemblyType(assembly: Assembly, fullName: string): Type {
        valueType := assembly.GetType(fullName)
        if valueType == null {
            throw new InvalidOperationException("Required runtime instance-member type '" + fullName + "' was not found.")
        }

        return valueType
    }

    static func RequiredRuntimeType(assemblyQualifiedName: string): Type {
        valueType := Type.GetType(assemblyQualifiedName)
        if valueType == null {
            throw new InvalidOperationException("Required runtime instance-member type '" + assemblyQualifiedName + "' was not found.")
        }

        return valueType
    }

    static func EmptySelection(): ColumnarRuntimeInstanceMemberSelection {
        return ColumnarRuntimeInstanceMemberSelection.Empty()
    }
}
