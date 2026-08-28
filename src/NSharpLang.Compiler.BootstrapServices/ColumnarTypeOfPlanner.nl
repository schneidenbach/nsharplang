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
import System.Threading
import System.Threading.Tasks
import YamlDotNet.Serialization


// Direct owner for `typeof(Type)`. The embedded type subtree is semantic input, not expression
// text: N# reconstructs its canonical shape, resolves the exact live runtime/TypeBuilder handle,
// and records the CLR `ldtoken; Type.GetTypeFromHandle` lowering in a validated schema-v3 plan.
// The append seam is shared by direct roots and ordinary instance-member receivers.
class ColumnarTypeOfPlanner {
    static func MayPlanRoot(nodes: ColumnarNodeTable, node: int): bool {
        if nodes == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        candidate := UnwrapParentheses(nodes, node)
        return candidate >= 0 && nodes.Kind(candidate) == ColumnarExpressionNodeKind.TypeOfExpression()
    }

    // A parsed typeof root is terminal even when its type facts are corrupt or unavailable. The
    // legacy owner must never get a second opportunity to reinterpret the same type syntax.
    static func ClaimsRoot(nodes: ColumnarNodeTable, node: int): bool {
        return MayPlanRoot(nodes, node)
    }

    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, il: ILGenerator, out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(Type)
            return false
        }
        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    static func TryGetType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        ValidateInputs(nodes, source, node, bindings, plan)
        candidate := UnwrapParentheses(nodes, node)
        targetType := typeof(object)
        if candidate >= 0 && nodes.Kind(candidate) == ColumnarExpressionNodeKind.TypeOfExpression() && (!TryResolveTarget(nodes, source, candidate, bindings, out targetType) || !IsSupportedType(targetType)) {
            plan.PrepareV3()
            resultType = typeof(Type)
            return false
        }
        if Plan(nodes, source, node, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(Type)
            return false
        }
        resultType = RequiredResultType(plan)
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateInputs(nodes, source, node, bindings, plan)
        plan.PrepareV3()
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 || nodes.Kind(candidate) != ColumnarExpressionNodeKind.TypeOfExpression() {
            return plan.Status
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(-1, ColumnarExpressionNodeKind.TypeOfExpression(), candidate)
            resultType := typeof(Type)
            if !TryAppendTypeOf(nodes, source, candidate, bindings, plan, out resultType) {
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

    static func TryAppendTypeOf(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(Type)
        if nodes == null || source == null || bindings == null || plan == null || node < 0 || node >= nodes.Kinds.Length || nodes.Kind(node) != ColumnarExpressionNodeKind.TypeOfExpression() || nodes.ChildCount(node) != 1 {
            return false
        }
        if plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() || plan.Status != ColumnarFragmentPlanStatus.NotOwned || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Typeof append requires an open schema-v3 plan.")
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            targetType := typeof(object)
            if !TryResolveTarget(nodes, source, node, bindings, out targetType) {
                plan.Rollback(checkpoint)
                return false
            }

            targetIndex := plan.AddType(targetType)
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Ldtoken(), targetIndex)

            handleParameters := new Type[](1)
            handleParameters[0] = typeof(RuntimeTypeHandle)
            getTypeFromHandle := typeof(Type).GetMethod("GetTypeFromHandle", handleParameters)
            if getTypeFromHandle == null || !getTypeFromHandle.get_IsStatic() || getTypeFromHandle.get_DeclaringType() != typeof(Type) || getTypeFromHandle.get_ReturnType() != typeof(Type) || getTypeFromHandle.GetParameters().Length != 1 {
                throw new InvalidOperationException("System.Type.GetTypeFromHandle has an unexpected runtime signature.")
            }
            methodIndex := plan.AddMethodWithSignature(getTypeFromHandle, typeof(Type), handleParameters, typeof(Type), true, false)
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
            return true
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    static func TryResolveTarget(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out targetType: Type): bool {
        targetType = typeof(object)
        if nodes == null || source == null || bindings == null || node < 0 || node >= nodes.Kinds.Length || nodes.Kind(node) != ColumnarExpressionNodeKind.TypeOfExpression() || nodes.ChildCount(node) != 1 {
            return false
        }
        canonical := ""
        return TryBuildTypeCanonical(nodes, source, nodes.Child(node, 0), 0, out canonical) && TryResolveType(canonical, bindings, out targetType)
    }

    static func TryBuildTypeCanonical(nodes: ColumnarNodeTable, source: string, node: int, depth: int, out canonical: string): bool {
        canonical = ""
        if depth > 200 || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        kind := nodes.Kind(node)
        if kind == 0 {
            if nodes.ChildCount(node) != 0 {
                return false
            }
            canonical = nodes.Text(source, node)
            return canonical.Length > 0
        }

        if kind == 1 {
            childCount := nodes.ChildCount(node)
            name := nodes.Text(source, node)
            if childCount == 0 || name.Length == 0 {
                return false
            }
            builder := new StringBuilder()
            builder.Append(name)
            builder.Append("<")
            i := 0
            while i < childCount {
                if i > 0 {
                    builder.Append(",")
                }
                argument := ""
                if !TryBuildTypeCanonical(nodes, source, nodes.Child(node, i), depth + 1, out argument) {
                    return false
                }
                builder.Append(argument)
                i += 1
            }
            builder.Append(">")
            canonical = builder.ToString()
            return true
        }

        if kind == 2 || kind == 3 {
            if nodes.ChildCount(node) != 1 {
                return false
            }
            element := ""
            if !TryBuildTypeCanonical(nodes, source, nodes.Child(node, 0), depth + 1, out element) {
                return false
            }
            canonical = element + (kind == 2 ? "[]" : "?")
            return true
        }

        if kind == 4 {
            childCount := nodes.ChildCount(node)
            if childCount != 2 {
                return false
            }
            builder := new StringBuilder()
            i := 0
            while i < childCount {
                if i > 0 {
                    builder.Append("|")
                }
                arm := ""
                if !TryBuildTypeCanonical(nodes, source, nodes.Child(node, i), depth + 1, out arm) {
                    return false
                }
                builder.Append(arm)
                i += 1
            }
            canonical = builder.ToString()
            return true
        }

        if kind == 6 {
            childCount := nodes.ChildCount(node)
            if childCount < 2 || childCount > 7 {
                return false
            }
            builder := new StringBuilder()
            builder.Append("ValueTuple<")
            i := 0
            while i < childCount {
                if i > 0 {
                    builder.Append(",")
                }
                element := ""
                if !TryBuildTypeCanonical(nodes, source, nodes.Child(node, i), depth + 1, out element) {
                    return false
                }
                builder.Append(element)
                i += 1
            }
            builder.Append(">")
            canonical = builder.ToString()
            return true
        }

        // A named tuple element is transparent to CLR type identity.
        if kind == 7 && nodes.ChildCount(node) == 1 {
            return TryBuildTypeCanonical(nodes, source, nodes.Child(node, 0), depth + 1, out canonical)
        }
        return false
    }

    static func TryResolveType(canonical: string, bindings: ColumnarFragmentBindings, out result: Type): bool {
        result = typeof(object)
        if canonical == null || canonical.Length == 0 || bindings == null {
            return false
        }

        unionParts := SplitTopLevelPipes(canonical)
        if unionParts.Count > 0 {
            if unionParts.Count != 2 {
                return false
            }
            left := typeof(object)
            right := typeof(object)
            leftCanonical := unionParts[0]
            rightCanonical := unionParts[1]
            unionDefinition := typeof(object)
            if !TryResolveRuntimeGenericDefinition("NSharpLang.Runtime.Union`2", "NSharpLang.Runtime", out unionDefinition) || !TryResolveType(leftCanonical, bindings, out left) || !TryResolveType(rightCanonical, bindings, out right) || !IsSupportedAnonymousUnionArm(left) || !IsSupportedAnonymousUnionArm(right) || SameTypeShape(left, right) {
                return false
            }
            arguments := new Type[](2)
            arguments[0] = left
            arguments[1] = right
            result = unionDefinition.MakeGenericType(arguments)
            return true
        }

        if canonical.EndsWith("[]", StringComparison.Ordinal) {
            element := typeof(object)
            if !TryResolveType(canonical.Substring(0, canonical.Length - 2), bindings, out element) || !IsSupportedElementType(element) {
                return false
            }
            result = element.MakeArrayType()
            return true
        }

        if canonical.EndsWith("?", StringComparison.Ordinal) {
            element := typeof(object)
            if !TryResolveType(canonical.Substring(0, canonical.Length - 1), bindings, out element) {
                return false
            }
            if !element.get_IsValueType() {
                result = element
                return true
            }
            if !IsLiftableNullableElement(element) {
                return false
            }
            definition := RequiredNullableDefinition()
            arguments := new Type[](1)
            arguments[0] = element
            result = definition.MakeGenericType(arguments)
            return true
        }

        if TryResolveSpecialKnownType(canonical, out result) {
            return true
        }

        runtimeIdentity := ""
        if ColumnarExternalBindingPlans.TryGetRuntimeTypeName(canonical, out runtimeIdentity) {
            runtimeType := Type.GetType(runtimeIdentity)
            if runtimeType != null {
                result = runtimeType
                return true
            }
        }

        if TryResolveKnownExternalType(canonical, out result) || TryResolveExceptionType(canonical, out result) {
            return true
        }

        if canonical.Length >= 2 && canonical[0] == '(' && canonical[canonical.Length - 1] == ')' {
            argumentText := canonical.Substring(1, canonical.Length - 2)
            argumentCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(argumentText)
            definition := OpenValueTupleType(argumentCanonicals.Count)
            if definition == null {
                return false
            }
            arguments := new Type[](argumentCanonicals.Count)
            i := 0
            while i < arguments.Length {
                argumentType := typeof(object)
                argumentCanonical := argumentCanonicals[i]
                if !TryResolveType(argumentCanonical, bindings, out argumentType) {
                    return false
                }
                arguments[i] = argumentType
                i += 1
            }
            result = definition.MakeGenericType(arguments)
            return IsSupportedValueTuple(result)
        }

        if canonical.StartsWith("Func<", StringComparison.Ordinal) && canonical.EndsWith(">", StringComparison.Ordinal) {
            return TryResolveDelegate(canonical.Substring(5, canonical.Length - 6), true, bindings, out result)
        }

        genericOpen := canonical.IndexOf("<", StringComparison.Ordinal)
        if genericOpen > 0 && canonical.EndsWith(">", StringComparison.Ordinal) {
            head := canonical.Substring(0, genericOpen)
            shortHead := ColumnarTypeCanonicalizer.UnqualifiedTypeName(head)
            if shortHead != head {
                return TryResolveType(shortHead + canonical.Substring(genericOpen), bindings, out result)
            }

            if IsCollectionHead(head) && HasSourceTypeNamed(head, bindings) {
                return false
            }

            if TryResolveClosedSourceGeneric(canonical, genericOpen, bindings, out result) {
                return true
            }

            argumentText := canonical.Substring(genericOpen + 1, canonical.Length - genericOpen - 2)
            argumentCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(argumentText)

            if head == "Action" {
                return TryResolveDelegate(argumentText, false, bindings, out result)
            }
            if head == "Span" || head == "ReadOnlySpan" {
                element := typeof(object)
                elementCanonical := ""
                if argumentCanonicals.Count == 1 {
                    elementCanonical = argumentCanonicals[0]
                }
                if argumentCanonicals.Count != 1 || !TryResolveType(elementCanonical, bindings, out element) || !IsSupportedReadOnlySpanElement(element) {
                    return false
                }
                definition := (head == "Span" ? typeof(Span<int>) : typeof(ReadOnlySpan<int>)).GetGenericTypeDefinition()
                arguments := new Type[](1)
                arguments[0] = element
                result = definition.MakeGenericType(arguments)
                return true
            }
            if head == "ValueTuple" {
                definition := OpenValueTupleType(argumentCanonicals.Count)
                if definition == null {
                    return false
                }
                arguments := new Type[](argumentCanonicals.Count)
                i := 0
                while i < arguments.Length {
                    argumentType := typeof(object)
                    argumentCanonical := argumentCanonicals[i]
                    if !TryResolveType(argumentCanonical, bindings, out argumentType) {
                        return false
                    }
                    arguments[i] = argumentType
                    i += 1
                }
                result = definition.MakeGenericType(arguments)
                return IsSupportedValueTuple(result)
            }
            if head == "Task" || head == "ValueTask" {
                element := typeof(object)
                elementCanonical := ""
                if argumentCanonicals.Count == 1 {
                    elementCanonical = argumentCanonicals[0]
                }
                if argumentCanonicals.Count != 1 || !TryResolveType(elementCanonical, bindings, out element) || !IsSupportedType(element) {
                    return false
                }
                definition := (head == "Task" ? typeof(Task<int>) : typeof(ValueTask<int>)).GetGenericTypeDefinition()
                arguments := new Type[](1)
                arguments[0] = element
                result = definition.MakeGenericType(arguments)
                return true
            }
            if head == "Result" {
                definition := typeof(object)
                first := typeof(object)
                second := typeof(object)
                firstCanonical := ""
                secondCanonical := ""
                if argumentCanonicals.Count == 2 {
                    firstCanonical = argumentCanonicals[0]
                    secondCanonical = argumentCanonicals[1]
                }
                if !TryResolveRuntimeGenericDefinition("NSharpLang.Runtime.Result`2", "NSharpLang.Runtime", out definition) || argumentCanonicals.Count != 2 || !TryResolveType(firstCanonical, bindings, out first) || !TryResolveType(secondCanonical, bindings, out second) || IsByRefLike(first) || IsByRefLike(second) || !IsSupportedType(first) || !IsSupportedType(second) {
                    return false
                }
                arguments := new Type[](2)
                arguments[0] = first
                arguments[1] = second
                result = definition.MakeGenericType(arguments)
                return true
            }

            return TryResolveCollection(head, argumentCanonicals, bindings, out result)
        }

        if TryResolveEnum(canonical, bindings, out result) || TryResolveSourceType(canonical, bindings, out result) || TryResolveSourceUnion(canonical, bindings, out result) {
            return true
        }

        if canonical == "Action" {
            result = typeof(Action)
            return true
        }

        if TryResolveBuiltinType(canonical, out result) {
            return true
        }

        if canonical.Contains(".") {
            shortName := ColumnarTypeCanonicalizer.UnqualifiedTypeName(canonical)
            if shortName != canonical {
                return TryResolveType(shortName, bindings, out result)
            }
        }
        return false
    }

    static func TryResolveRuntimeGenericDefinition(fullName: string, assemblyName: string, out result: Type): bool {
        result = typeof(object)
        qualifiedName := fullName + ", " + assemblyName
        direct := Type.GetType(qualifiedName)
        if direct != null && direct.get_IsGenericTypeDefinition() {
            result = direct
            return true
        }

        assemblies := AppDomain.CurrentDomain.GetAssemblies()
        i := 0
        while i < assemblies.Length {
            assembly := assemblies[i]
            identity := assembly.GetName().get_FullName()
            if String.Equals(identity, assemblyName, StringComparison.Ordinal) || identity.StartsWith(assemblyName + ",", StringComparison.Ordinal) {
                candidate := assembly.GetType(fullName)
                if candidate != null && candidate.get_IsGenericTypeDefinition() {
                    result = candidate
                    return true
                }
            }
            i += 1
        }
        return false
    }

    static func TryResolveSpecialKnownType(canonical: string, out result: Type): bool {
        result = typeof(object)
        if canonical == "StringBuilder" {
            result = typeof(StringBuilder)
        } else if canonical == "object" {
            result = typeof(object)
        } else if canonical == "StringComparer" {
            result = typeof(StringComparer)
        } else if canonical == "SearchOption" {
            result = typeof(SearchOption)
        } else if canonical == "IList" {
            result = typeof(IList)
        } else if canonical == "IComparable" {
            comparable := Type.GetType("System.IComparable")
            if comparable == null {
                return false
            }
            result = comparable
        } else if canonical == "Type" {
            result = typeof(Type)
        } else if canonical == "Version" {
            result = typeof(Version)
        } else if canonical == "TimeSpan" {
            result = typeof(TimeSpan)
        } else if canonical == "Random" {
            result = typeof(Random)
        } else if canonical == "Process" {
            result = typeof(Process)
        } else if canonical == "ProcessStartInfo" {
            result = typeof(ProcessStartInfo)
        } else if canonical == "StreamReader" {
            result = typeof(StreamReader)
        } else if canonical == "Stream" {
            result = typeof(Stream)
        } else if canonical == "CancellationToken" {
            result = typeof(CancellationToken)
        } else if canonical == "Task" {
            result = typeof(Task)
        } else if canonical == "ValueTask" {
            result = typeof(ValueTask)
        } else if canonical == "Assembly" {
            result = typeof(Assembly)
        } else {
            return false
        }
        return true
    }

    static func TryResolveBuiltinType(canonical: string, out result: Type): bool {
        result = typeof(object)
        if canonical == "int" {
            result = typeof(int)
        } else if canonical == "long" {
            result = typeof(long)
        } else if canonical == "uint" {
            result = typeof(uint)
        } else if canonical == "ulong" {
            result = typeof(ulong)
        } else if canonical == "short" {
            result = typeof(short)
        } else if canonical == "ushort" {
            result = typeof(ushort)
        } else if canonical == "byte" {
            result = typeof(byte)
        } else if canonical == "sbyte" {
            result = typeof(sbyte)
        } else if canonical == "bool" {
            result = typeof(bool)
        } else if canonical == "char" {
            result = typeof(char)
        } else if canonical == "double" {
            result = typeof(double)
        } else if canonical == "float" {
            result = typeof(float)
        } else if canonical == "decimal" {
            result = typeof(decimal)
        } else if canonical == "string" {
            result = typeof(string)
        } else if canonical == "IntPtr" || canonical == "nint" {
            result = typeof(IntPtr)
        } else if canonical == "UIntPtr" || canonical == "nuint" {
            result = typeof(UIntPtr)
        } else if canonical == "DateTime" {
            result = typeof(DateTime)
        } else if canonical == "Index" {
            result = typeof(Index)
        } else if canonical == "Range" {
            result = typeof(Range)
        } else {
            return false
        }
        return true
    }

    static func TryResolveKnownExternalType(canonical: string, out result: Type): bool {
        result = typeof(object)
        fullName := ""
        if canonical == "IYamlTypeConverter" || canonical == "YamlDotNet.Serialization.IYamlTypeConverter" {
            fullName = "YamlDotNet.Serialization.IYamlTypeConverter"
        } else if canonical == "ObjectDeserializer" || canonical == "YamlDotNet.Serialization.ObjectDeserializer" {
            fullName = "YamlDotNet.Serialization.ObjectDeserializer"
        } else if canonical == "ObjectSerializer" || canonical == "YamlDotNet.Serialization.ObjectSerializer" {
            fullName = "YamlDotNet.Serialization.ObjectSerializer"
        } else if canonical == "DeserializerBuilder" || canonical == "YamlDotNet.Serialization.DeserializerBuilder" {
            fullName = "YamlDotNet.Serialization.DeserializerBuilder"
        } else if canonical == "IDeserializer" || canonical == "YamlDotNet.Serialization.IDeserializer" {
            fullName = "YamlDotNet.Serialization.IDeserializer"
        } else if canonical == "INamingConvention" || canonical == "YamlDotNet.Serialization.INamingConvention" {
            fullName = "YamlDotNet.Serialization.INamingConvention"
        } else if canonical == "CamelCaseNamingConvention" || canonical == "YamlDotNet.Serialization.NamingConventions.CamelCaseNamingConvention" {
            fullName = "YamlDotNet.Serialization.NamingConventions.CamelCaseNamingConvention"
        } else if canonical == "IParser" || canonical == "YamlDotNet.Core.IParser" {
            fullName = "YamlDotNet.Core.IParser"
        } else if canonical == "IEmitter" || canonical == "YamlDotNet.Core.IEmitter" {
            fullName = "YamlDotNet.Core.IEmitter"
        } else if canonical == "YamlException" || canonical == "YamlDotNet.Core.YamlException" {
            fullName = "YamlDotNet.Core.YamlException"
        } else if canonical == "ParsingEvent" || canonical == "YamlDotNet.Core.Events.ParsingEvent" {
            fullName = "YamlDotNet.Core.Events.ParsingEvent"
        } else if canonical == "Scalar" || canonical == "YamlDotNet.Core.Events.Scalar" {
            fullName = "YamlDotNet.Core.Events.Scalar"
        } else if canonical == "MappingStart" || canonical == "YamlDotNet.Core.Events.MappingStart" {
            fullName = "YamlDotNet.Core.Events.MappingStart"
        } else if canonical == "MappingEnd" || canonical == "YamlDotNet.Core.Events.MappingEnd" {
            fullName = "YamlDotNet.Core.Events.MappingEnd"
        }
        if fullName.Length > 0 {
            yamlType := typeof(IYamlTypeConverter).get_Assembly().GetType(fullName)
            if yamlType != null {
                result = yamlType
                return true
            }
            return false
        }

        if canonical == "JsonElement" || canonical == "System.Text.Json.JsonElement" {
            result = typeof(JsonElement)
            return true
        }
        if canonical == "JsonDocument" || canonical == "System.Text.Json.JsonDocument" {
            result = typeof(JsonDocument)
            return true
        }
        if canonical == "JsonValueKind" || canonical == "System.Text.Json.JsonValueKind" {
            result = typeof(JsonValueKind)
            return true
        }
        if canonical == "JsonSerializerOptions" || canonical == "System.Text.Json.JsonSerializerOptions" {
            result = typeof(JsonSerializerOptions)
            return true
        }
        if canonical == "JsonNamingPolicy" || canonical == "System.Text.Json.JsonNamingPolicy" {
            result = typeof(JsonNamingPolicy)
            return true
        }

        aspNetName := canonical
        if canonical == "WebApplication" {
            aspNetName = "Microsoft.AspNetCore.Builder.WebApplication"
        } else if canonical == "WebApplicationBuilder" {
            aspNetName = "Microsoft.AspNetCore.Builder.WebApplicationBuilder"
        } else if canonical == "HttpContext" {
            aspNetName = "Microsoft.AspNetCore.Http.HttpContext"
        } else if canonical == "HttpRequest" {
            aspNetName = "Microsoft.AspNetCore.Http.HttpRequest"
        } else if canonical == "HttpResponse" {
            aspNetName = "Microsoft.AspNetCore.Http.HttpResponse"
        } else if canonical == "RequestDelegate" {
            aspNetName = "Microsoft.AspNetCore.Http.RequestDelegate"
        } else if canonical == "IResult" {
            aspNetName = "Microsoft.AspNetCore.Http.IResult"
        } else if !canonical.Contains(".") {
            return false
        }

        assemblies := ExternalAssemblyScan.Loaded()
        i := 0
        while i < assemblies.Length {
            assembly := assemblies[i]
            try {
                candidate := assembly.GetType(aspNetName)
                if candidate != null && IsSupportedExternalType(candidate) {
                    result = candidate
                    return true
                }
            } catch {
            }
            // A later loaded assembly may carry the exact supported type.

            i += 1
        }
        return false
    }

    static func TryResolveExceptionType(canonical: string, out result: Type): bool {
        result = typeof(object)
        if canonical == "Exception" || canonical == "System.Exception" {
            result = typeof(Exception)
        } else if canonical == "InvalidOperationException" || canonical == "System.InvalidOperationException" {
            result = typeof(InvalidOperationException)
        } else if canonical == "ArgumentException" || canonical == "System.ArgumentException" {
            result = typeof(ArgumentException)
        } else if canonical == "ArgumentNullException" || canonical == "System.ArgumentNullException" {
            result = typeof(ArgumentNullException)
        } else if canonical == "ArgumentOutOfRangeException" || canonical == "System.ArgumentOutOfRangeException" {
            result = typeof(ArgumentOutOfRangeException)
        } else if canonical == "FormatException" || canonical == "System.FormatException" {
            result = typeof(FormatException)
        } else if canonical == "NotSupportedException" || canonical == "System.NotSupportedException" {
            result = typeof(NotSupportedException)
        } else if canonical == "NotImplementedException" || canonical == "System.NotImplementedException" {
            result = typeof(NotImplementedException)
        } else if canonical == "TimeoutException" || canonical == "System.TimeoutException" {
            result = typeof(TimeoutException)
        } else if canonical == "DivideByZeroException" || canonical == "System.DivideByZeroException" {
            result = typeof(DivideByZeroException)
        } else if canonical == "ArithmeticException" || canonical == "System.ArithmeticException" {
            result = typeof(ArithmeticException)
        } else if canonical == "OverflowException" || canonical == "System.OverflowException" {
            result = typeof(OverflowException)
        } else if canonical == "NullReferenceException" || canonical == "System.NullReferenceException" {
            result = typeof(NullReferenceException)
        } else if canonical == "IndexOutOfRangeException" || canonical == "System.IndexOutOfRangeException" {
            result = typeof(IndexOutOfRangeException)
        } else if canonical == "InvalidCastException" || canonical == "System.InvalidCastException" {
            result = typeof(InvalidCastException)
        } else if canonical == "FileNotFoundException" || canonical == "System.IO.FileNotFoundException" {
            result = typeof(FileNotFoundException)
        } else {
            return false
        }
        return true
    }

    static func TryResolveCollection(head: string, argumentCanonicals: List<string>, bindings: ColumnarFragmentBindings, out result: Type): bool {
        result = typeof(object)
        if head == "List" || head == "HashSet" || head == "Stack" || head == "IReadOnlyList" || head == "IReadOnlyCollection" || head == "IReadOnlySet" || head == "IEnumerable" {
            element := typeof(object)
            elementCanonical := ""
            if argumentCanonicals.Count == 1 {
                elementCanonical = argumentCanonicals[0]
            }
            if argumentCanonicals.Count != 1 || !TryResolveType(elementCanonical, bindings, out element) {
                return false
            }
            if head == "HashSet" || head == "IReadOnlySet" {
                if !IsAdmissibleHashSetElement(element) {
                    return false
                }
            } else if !IsAdmissibleCollectionElement(element) {
                return false
            }
            definition := typeof(List<int>).GetGenericTypeDefinition()
            if head == "HashSet" {
                definition = typeof(HashSet<int>).GetGenericTypeDefinition()
            } else if head == "Stack" {
                definition = typeof(Stack<int>).GetGenericTypeDefinition()
            } else if head == "IReadOnlyList" {
                definition = typeof(IReadOnlyList<int>).GetGenericTypeDefinition()
            } else if head == "IReadOnlyCollection" {
                definition = typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition()
            } else if head == "IReadOnlySet" {
                definition = typeof(IReadOnlySet<int>).GetGenericTypeDefinition()
            } else if head == "IEnumerable" {
                definition = typeof(IEnumerable<int>).GetGenericTypeDefinition()
            }
            arguments := new Type[](1)
            arguments[0] = element
            result = definition.MakeGenericType(arguments)
            return true
        }

        // The three two-argument heads. `IReadOnlyDictionary` is the READ-ONLY mirror of `Dictionary` and
        // takes `Dictionary`'s key admissibility exactly (an enum key is allowed; any other builder-bound
        // key is not); only `SortedDictionary` keeps the stricter key rule its comparer needs.
        if head == "Dictionary" || head == "SortedDictionary" || head == "IReadOnlyDictionary" {
            key := typeof(object)
            value := typeof(object)
            keyCanonical := ""
            valueCanonical := ""
            if argumentCanonicals.Count == 2 {
                keyCanonical = argumentCanonicals[0]
                valueCanonical = argumentCanonicals[1]
            }
            if argumentCanonicals.Count != 2 || !TryResolveType(keyCanonical, bindings, out key) || !TryResolveType(valueCanonical, bindings, out value) || (head == "SortedDictionary" ? ContainsBuilderBoundType(key) : ContainsNonEnumBuilderBoundType(key)) || !IsAdmissibleCollectionElement(value) {
                return false
            }
            definition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
            if head == "SortedDictionary" {
                definition = typeof(SortedDictionary<int, int>).GetGenericTypeDefinition()
            } else if head == "IReadOnlyDictionary" {
                definition = RequiredReadOnlyDictionaryDefinition()
            }
            arguments := new Type[](2)
            arguments[0] = key
            arguments[1] = value
            result = definition.MakeGenericType(arguments)
            return true
        }
        return false
    }

    static func TryResolveDelegate(argumentText: string, hasReturn: bool, bindings: ColumnarFragmentBindings, out result: Type): bool {
        result = typeof(object)
        parts := ColumnarTypeCanonicalizer.SplitTopLevelCommas(argumentText)
        if parts.Count == 0 {
            return false
        }
        parameterCount := parts.Count
        voidType := RequiredVoidType()
        returnType := voidType
        if hasReturn {
            parameterCount -= 1
            returnCanonical := parts[parameterCount]
            if returnCanonical != "void" && (!TryResolveType(returnCanonical, bindings, out returnType) || IsAssemblyBuilderBacked(returnType)) {
                return false
            }
        }
        if parameterCount > 4 {
            return false
        }
        parameters := new Type[](parameterCount)
        i := 0
        while i < parameterCount {
            parameterType := typeof(object)
            parameterCanonical := parts[i]
            if parameterCanonical == "void" || !TryResolveType(parameterCanonical, bindings, out parameterType) || IsAssemblyBuilderBacked(parameterType) {
                return false
            }
            parameters[i] = parameterType
            i += 1
        }

        if returnType == voidType {
            if parameterCount == 0 {
                result = typeof(Action)
                return true
            }
            definition := typeof(Action<int>).GetGenericTypeDefinition()
            if parameterCount == 2 {
                definition = typeof(Action<int, int>).GetGenericTypeDefinition()
            } else if parameterCount == 3 {
                definition = typeof(Action<int, int, int>).GetGenericTypeDefinition()
            } else if parameterCount == 4 {
                definition = typeof(Action<int, int, int, int>).GetGenericTypeDefinition()
            }
            result = definition.MakeGenericType(parameters)
            return true
        }

        definition := typeof(Func<int>).GetGenericTypeDefinition()
        if parameterCount == 1 {
            definition = typeof(Func<int, int>).GetGenericTypeDefinition()
        } else if parameterCount == 2 {
            definition = typeof(Func<int, int, int>).GetGenericTypeDefinition()
        } else if parameterCount == 3 {
            definition = typeof(Func<int, int, int, int>).GetGenericTypeDefinition()
        } else if parameterCount == 4 {
            definition = typeof(Func<int, int, int, int, int>).GetGenericTypeDefinition()
        }
        arguments := new Type[](parameterCount + 1)
        i = 0
        while i < parameterCount {
            arguments[i] = parameters[i]
            i += 1
        }
        arguments[parameterCount] = returnType
        result = definition.MakeGenericType(arguments)
        return true
    }

    static func TryResolveClosedSourceGeneric(canonical: string, genericOpen: int, bindings: ColumnarFragmentBindings, out result: Type): bool {
        result = typeof(object)
        head := canonical.Substring(0, genericOpen)
        openType := typeof(object)
        if !TryFindSourceGenericDefinition(head, bindings, out openType) {
            return false
        }
        argumentsText := canonical.Substring(genericOpen + 1, canonical.Length - genericOpen - 2)
        argumentsCanonical := ColumnarTypeCanonicalizer.SplitTopLevelCommas(argumentsText)
        openArguments := openType.GetGenericArguments()
        if argumentsCanonical.Count != openArguments.Length {
            return false
        }
        arguments := new Type[](argumentsCanonical.Count)
        i := 0
        while i < arguments.Length {
            argumentType := typeof(object)
            argumentCanonical := argumentsCanonical[i]
            if !TryResolveType(argumentCanonical, bindings, out argumentType) {
                return false
            }
            arguments[i] = argumentType
            i += 1
        }
        result = openType.MakeGenericType(arguments)
        return true
    }

    static func TryFindSourceGenericDefinition(name: string, bindings: ColumnarFragmentBindings, out result: Type): bool {
        result = typeof(object)
        candidate := typeof(object)
        for definition in bindings.SourceTypeDefinitions {
            if definition == null || definition.Builder == null {
                throw new InvalidOperationException("Typeof source type definitions cannot be null.")
            }
            builder: Type = definition.Builder
            if SourceExactNameMatches(builder, name) && candidate == typeof(object) {
                candidate = builder
            }
        }
        if candidate == typeof(object) {
            for definition in bindings.SourceTypeDefinitions {
                builder: Type = definition.Builder
                if SourceShortNameMatches(builder, name) && candidate == typeof(object) {
                    candidate = builder
                }
            }
        }
        if candidate != typeof(object) {
            if candidate.get_IsGenericTypeDefinition() {
                result = candidate
                return true
            }
            return false
        }

        candidate = typeof(object)
        for definition in bindings.SourceUnionDefinitions {
            if definition == null || definition.Base == null {
                throw new InvalidOperationException("Typeof source union definitions cannot be null.")
            }
            builder: Type = definition.Base
            if SourceExactNameMatches(builder, name) && candidate == typeof(object) {
                candidate = builder
            }
        }
        if candidate == typeof(object) {
            for definition in bindings.SourceUnionDefinitions {
                builder: Type = definition.Base
                if SourceShortNameMatches(builder, name) && candidate == typeof(object) {
                    candidate = builder
                }
            }
        }
        if candidate != typeof(object) && candidate.get_IsGenericTypeDefinition() {
            result = candidate
            return true
        }
        return false
    }

    static func TryResolveEnum(canonical: string, bindings: ColumnarFragmentBindings, out result: Type): bool {
        result = typeof(object)
        if !bindings.Enums.ContainsKey(canonical) {
            return false
        }
        definition := bindings.Enums[canonical]
        if definition == null || definition.EnumType == null {
            throw new InvalidOperationException("Typeof enum facts cannot be null.")
        }
        result = definition.IsStringBacked ? typeof(string) : definition.EnumType
        return true
    }

    static func TryResolveSourceType(canonical: string, bindings: ColumnarFragmentBindings, out result: Type): bool {
        result = typeof(object)
        for definition in bindings.SourceTypeDefinitions {
            if definition == null || definition.Builder == null {
                throw new InvalidOperationException("Typeof source type definitions cannot be null.")
            }
            candidate: Type = definition.Builder
            if SourceExactNameMatches(candidate, canonical) && result == typeof(object) {
                result = SelectUniqueSourceCandidate(result, candidate, "Typeof source type name is ambiguous.")
            }
        }
        if result != typeof(object) || canonical.Contains(".") {
            return result != typeof(object)
        }
        for definition in bindings.SourceTypeDefinitions {
            candidate: Type = definition.Builder
            if SourceShortNameMatches(candidate, canonical) && result == typeof(object) {
                result = candidate
            }
        }
        return result != typeof(object)
    }

    static func TryResolveSourceUnion(canonical: string, bindings: ColumnarFragmentBindings, out result: Type): bool {
        result = typeof(object)
        for definition in bindings.SourceUnionDefinitions {
            if definition == null || definition.Base == null {
                throw new InvalidOperationException("Typeof source union definitions cannot be null.")
            }
            candidate: Type = definition.Base
            if SourceExactNameMatches(candidate, canonical) && result == typeof(object) {
                result = SelectUniqueSourceCandidate(result, candidate, "Typeof source union name is ambiguous.")
            }
        }
        if result == typeof(object) && !canonical.Contains(".") {
            for definition in bindings.SourceUnionDefinitions {
                candidate: Type = definition.Base
                if SourceShortNameMatches(candidate, canonical) && result == typeof(object) {
                    result = candidate
                }
            }
        }
        return result != typeof(object) && !result.get_IsGenericTypeDefinition()
    }

    static func HasSourceTypeNamed(name: string, bindings: ColumnarFragmentBindings): bool {
        if bindings.Enums.ContainsKey(name) {
            return true
        }
        for definition in bindings.SourceTypeDefinitions {
            if definition != null && (SourceExactNameMatches(definition.Builder, name) || SourceShortNameMatches(definition.Builder, name)) {
                return true
            }
        }
        for definition in bindings.SourceUnionDefinitions {
            if definition != null && (SourceExactNameMatches(definition.Base, name) || SourceShortNameMatches(definition.Base, name)) {
                return true
            }
        }
        return false
    }

    static func SourceExactNameMatches(valueType: Type, canonical: string): bool {
        if valueType == null || canonical == null || canonical.Length == 0 {
            return false
        }
        fullName := valueType.FullName ?? ""
        if fullName.Length > 0 {
            return String.Equals(fullName, canonical, StringComparison.Ordinal)
        }
        return String.Equals(valueType.Name, canonical, StringComparison.Ordinal)
    }

    static func SourceShortNameMatches(valueType: Type, canonical: string): bool {
        if valueType == null || canonical == null || canonical.Length == 0 || SourceExactNameMatches(valueType, canonical) {
            return false
        }
        shortCanonical := ColumnarTypeCanonicalizer.UnqualifiedTypeName(canonical)
        fullName := valueType.FullName ?? ""
        shortCandidate := ColumnarTypeCanonicalizer.UnqualifiedTypeName(fullName)
        return String.Equals(valueType.Name, shortCanonical, StringComparison.Ordinal) || String.Equals(shortCandidate, shortCanonical, StringComparison.Ordinal)
    }

    static func SelectUniqueSourceCandidate(current: Type, candidate: Type, ambiguityMessage: string): Type {
        if current != typeof(object) && current != candidate {
            throw new InvalidOperationException(ambiguityMessage)
        }
        return candidate
    }

    static func IsCollectionHead(name: string): bool {
        return name == "List" || name == "Dictionary" || name == "SortedDictionary" || name == "HashSet" || name == "Stack"
    }

    static func IsSupportedType(valueType: Type): bool {
        if valueType == typeof(int) || valueType == typeof(bool) || valueType == typeof(long) || valueType == typeof(ulong) || valueType == typeof(string) || valueType == typeof(char) || valueType == typeof(double) || valueType == typeof(float) || valueType == typeof(byte) || valueType == typeof(sbyte) || valueType == typeof(short) || valueType == typeof(ushort) || valueType == typeof(uint) || valueType == typeof(IntPtr) || valueType == typeof(UIntPtr) || valueType == typeof(decimal) || valueType == typeof(object) || valueType == typeof(Stream) || valueType == typeof(StreamReader) || valueType == typeof(StringComparer) || valueType == typeof(StringBuilder) || valueType == typeof(DateTime) || valueType == typeof(TimeSpan) || valueType == typeof(Index) || valueType == typeof(Range) || valueType == typeof(CancellationToken) || valueType == typeof(Random) || valueType == typeof(IList) || valueType == typeof(Type) || valueType == typeof(Version) || valueType == typeof(Assembly) {
            return true
        }
        if valueType == RequiredTextWriterType() {
            return true
        }
        // The interop heads are owned by ColumnarRuntimeTypeFacts, not re-listed here: the direct-call
        // set is Stream/FileStream/DirectoryInfo and the process set is Process/ProcessStartInfo/
        // StreamReader. Naming only `Stream` inline dropped FileStream and DirectoryInfo.
        if ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(valueType) || ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(valueType) {
            return true
        }
        if IsSupportedTaskType(valueType) || typeof(Exception).IsAssignableFrom(valueType) || ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName(valueType.FullName) || IsSupportedJsonType(valueType) || IsSupportedExternalType(valueType) || IsSupportedSpanLikeType(valueType) || IsSupportedArrayPoolType(valueType) || IsSupportedMemoryPoolType(valueType) || IsSupportedMemoryOwnerType(valueType) || IsSupportedMemoryType(valueType) || IsSupportedResultType(valueType) || IsSupportedAnonymousUnionType(valueType) || IsEnumType(valueType) || valueType is TypeBuilder || valueType.get_IsGenericParameter() || IsClosedSourceGeneric(valueType) || IsSupportedValueTuple(valueType) || IsSupportedDelegateType(valueType) || IsSupportedCollectionType(valueType) || IsSupportedNullable(valueType) {
            return true
        }
        if valueType.get_IsSZArray() {
            element := valueType.GetElementType()
            return element != null && IsSupportedElementType(element)
        }
        return false
    }

    static func IsSupportedElementType(valueType: Type): bool {
        if valueType == typeof(bool) || valueType == typeof(int) || valueType == typeof(uint) || valueType == typeof(long) || valueType == typeof(ulong) || valueType == typeof(byte) || valueType == typeof(sbyte) || valueType == typeof(short) || valueType == typeof(ushort) || valueType == typeof(char) || valueType == typeof(string) || valueType == typeof(double) || valueType == typeof(float) || valueType == typeof(IntPtr) || valueType == typeof(UIntPtr) || valueType == typeof(object) || valueType == typeof(Type) || valueType == typeof(Version) || valueType == typeof(Assembly) || IsEnumType(valueType) || valueType is TypeBuilder || valueType.get_IsGenericParameter() || ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName(valueType.FullName) || IsSupportedNullable(valueType) {
            return true
        }
        if valueType.get_IsSZArray() {
            element := valueType.GetElementType()
            return element != null && IsSupportedElementType(element)
        }
        return false
    }

    static func IsLiftableNullableElement(valueType: Type): bool {
        return valueType == typeof(int) || valueType == typeof(long) || valueType == typeof(ulong) || valueType == typeof(uint) || valueType == typeof(short) || valueType == typeof(ushort) || valueType == typeof(byte) || valueType == typeof(sbyte) || valueType == typeof(bool) || valueType == typeof(char) || valueType == typeof(double) || valueType == typeof(float) || valueType == typeof(decimal) || valueType == typeof(TimeSpan) || IsSupportedValueTuple(valueType)
    }

    static func IsSupportedNullable(valueType: Type): bool {
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() || valueType.GetGenericTypeDefinition() != RequiredNullableDefinition() {
            return false
        }
        return IsLiftableNullableElement(valueType.GetGenericArguments()[0])
    }

    static func IsSupportedReadOnlySpanElement(valueType: Type): bool {
        return valueType == typeof(bool) || valueType == typeof(int) || valueType == typeof(uint) || valueType == typeof(long) || valueType == typeof(ulong) || valueType == typeof(byte) || valueType == typeof(sbyte) || valueType == typeof(short) || valueType == typeof(ushort) || valueType == typeof(char) || valueType == typeof(double) || valueType == typeof(float) || IsEnumType(valueType)
    }

    // A span head alone is NOT admissibility: the span read/write/slice/conversion lowerings are
    // written for the blittable element set, and `Span<T>` over anything else is a byref-like generic
    // whose ctor/Item reflection lookups are not resolvable (a closed span over a source TypeBuilder is
    // a TypeBuilderInstantiation whose `GetConstructor` throws). The ELEMENT is part of the question.
    static func IsSupportedSpanLikeType(valueType: Type): bool {
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }
        name := valueType.GetGenericTypeDefinition().FullName ?? ""
        if name != "System.Span`1" && name != "System.ReadOnlySpan`1" {
            return false
        }
        arguments := valueType.GetGenericArguments()
        return arguments.Length == 1 && IsSupportedReadOnlySpanElement(arguments[0])
    }

    // The two span heads are published SEPARATELY because the span family is not symmetric and three
    // emitter decisions read the difference: only `Span<T>` converts to `ReadOnlySpan<T>` (there is no
    // conversion the other way), an indexed READ of a `ReadOnlySpan<T>` lowers through
    // `MemoryMarshal.AsBytes` while a `Span<T>` read uses the `Item` getter, and an indexed WRITE is a
    // `Span<T>`-only lowering. A single folded head would answer `true` for `ReadOnlySpan<T>` in the
    // source slot of a conversion that does not exist. Both narrow the SAME span-like rule, so the
    // element constraint is still spelled exactly once.
    static func IsSupportedReadOnlySpanType(valueType: Type): bool {
        return IsSupportedSpanLikeType(valueType) && (valueType.GetGenericTypeDefinition().FullName ?? "") == "System.ReadOnlySpan`1"
    }

    static func IsSupportedSpanType(valueType: Type): bool {
        return IsSupportedSpanLikeType(valueType) && (valueType.GetGenericTypeDefinition().FullName ?? "") == "System.Span`1"
    }

    static func IsSupportedTaskType(valueType: Type): bool {
        if valueType == typeof(Task) || valueType == typeof(ValueTask) {
            return true
        }
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }
        name := valueType.GetGenericTypeDefinition().FullName ?? ""
        return (name == "System.Threading.Tasks.Task`1" || name == "System.Threading.Tasks.ValueTask`1") && IsSupportedType(valueType.GetGenericArguments()[0])
    }

    static func IsSupportedJsonType(valueType: Type): bool {
        name := valueType.FullName ?? ""
        return name == "System.Text.Json.JsonElement" || name == "System.Text.Json.JsonDocument" || name == "System.Text.Json.JsonValueKind" || name == "System.Text.Json.JsonSerializerOptions" || name == "System.Text.Json.JsonNamingPolicy" || name == "System.Text.Json.JsonElement+ArrayEnumerator" || name == "System.Text.Json.JsonElement+ObjectEnumerator" || name == "System.Text.Json.JsonProperty"
    }

    // SOLE OWNER since `015-A5`, which deleted the C# emitter's copy and rerouted its two sites.
    // The reroute is deliberately NOT behaviour-preserving: the deleted head asked
    // `IsValueType || IsByRef || IsPointer || ContainsGenericParameters`, and the last two terms are
    // wrong for the shapes the emitter meets.
    //
    // THE ELEMENT GUARD. `IsPointer` is false for an ARRAY, so the C# head admitted `WebApplication[]`
    // as an external reference type without ever consulting the array arm's element rule. Measured on
    // the baseline compiler, that left a half-open surface — such an array could be indexed and have
    // its `Length` read, but could not be CREATED and could not be walked by `for`, because those two
    // paths do read `IsSupportedElementType`. Asking `HasElementType` keeps array-ness (and pointer-
    // and byref-ness) a single decision made in the array arm, so the surface is coherent both ways.
    //
    // THE OPEN-GENERIC GUARD IS A SECOND, DISTINCT ONE. A generic type declared in an AspNet
    // namespace by a source file with a file-scoped `namespace Microsoft.AspNetCore.…` reaches here
    // as a `TypeBuilderImpl`, on which `ContainsGenericParameters` reads FALSE — and its
    // `HasElementType` is false too, so the element guard above cannot catch it.
    // `ContainsOpenGenericParameters` answers by walking the definition and its argument tree.
    //
    // The yaml clause is an ASSEMBLY test asked BEFORE both guards, and it compares by assembly NAME
    // rather than by handle identity: the compiler never loads that assembly twice, and the name
    // comparison is what lets a bootstrap host that did answer the same as the emitting host.
    static func IsSupportedExternalType(valueType: Type): bool {
        valueAssemblyName := valueType.get_Assembly().GetName().get_FullName()
        yamlAssemblyName := typeof(IYamlTypeConverter).get_Assembly().GetName().get_FullName()
        if String.Equals(valueAssemblyName, yamlAssemblyName, StringComparison.Ordinal) {
            return true
        }
        if valueType.get_IsValueType() || valueType.get_IsByRef() || valueType.get_HasElementType() || ContainsOpenGenericParameters(valueType) {
            return false
        }
        namespaceName := valueType.Namespace ?? ""
        return namespaceName.StartsWith("Microsoft.AspNetCore.", StringComparison.Ordinal) || namespaceName.StartsWith("Microsoft.Extensions.Hosting", StringComparison.Ordinal)
    }

    static func ContainsOpenGenericParameters(valueType: Type): bool {
        if valueType.get_IsGenericParameter() || valueType.get_IsGenericTypeDefinition() {
            return true
        }
        if !valueType.get_IsGenericType() {
            return false
        }
        arguments := valueType.GetGenericArguments()
        i := 0
        while i < arguments.Length {
            if ContainsOpenGenericParameters(arguments[i]) {
                return true
            }
            i += 1
        }
        return false
    }

    static func IsSupportedGenericDefinitionName(valueType: Type, definitionName: string): bool {
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }
        definition := valueType.GetGenericTypeDefinition()
        if (definition.FullName ?? "") != definitionName {
            return false
        }
        arguments := valueType.GetGenericArguments()
        return arguments.Length == 1 && arguments[0] == typeof(byte)
    }

    static func IsSupportedRuntimeGeneric(valueType: Type, definitionName: string): bool {
        return valueType.get_IsGenericType() && !valueType.get_IsGenericTypeDefinition() && (valueType.GetGenericTypeDefinition().FullName ?? "") == definitionName
    }

    // The four buffer heads, each admissible at `byte` ONLY: rent/return, the owner's Memory getter
    // and Memory's Span getter are lowered for byte buffers and nothing else, so `ArrayPool<int>` is
    // declined rather than admitted-then-declined. Each head is its own named entry point instead of a
    // string argument at the call site, so a consumer names the head it means.
    static func IsSupportedArrayPoolType(valueType: Type): bool {
        return IsSupportedGenericDefinitionName(valueType, "System.Buffers.ArrayPool`1")
    }

    static func IsSupportedMemoryPoolType(valueType: Type): bool {
        return IsSupportedGenericDefinitionName(valueType, "System.Buffers.MemoryPool`1")
    }

    static func IsSupportedMemoryOwnerType(valueType: Type): bool {
        return IsSupportedGenericDefinitionName(valueType, "System.Buffers.IMemoryOwner`1")
    }

    static func IsSupportedMemoryType(valueType: Type): bool {
        return IsSupportedGenericDefinitionName(valueType, "System.Memory`1")
    }

    // `Result<T, E>` and `Union<A, B>` are admissible only when their ARGUMENTS are: the head alone
    // admits `Result<Queue<int>, string>`, whose Ok/Err member surface has no emit lowering. Byref-like
    // arguments are excluded because a `Result` closed over one cannot be stored in a field or a local.
    static func IsSupportedResultType(valueType: Type): bool {
        if !IsSupportedRuntimeGeneric(valueType, "NSharpLang.Runtime.Result`2") {
            return false
        }
        arguments := valueType.GetGenericArguments()
        return arguments.Length == 2 && !IsByRefLike(arguments[0]) && !IsByRefLike(arguments[1]) && IsSupportedType(arguments[0]) && IsSupportedType(arguments[1])
    }

    static func IsSupportedAnonymousUnionType(valueType: Type): bool {
        if !IsSupportedRuntimeGeneric(valueType, "NSharpLang.Runtime.Union`2") {
            return false
        }
        arguments := valueType.GetGenericArguments()
        i := 0
        while i < arguments.Length {
            if !IsSupportedAnonymousUnionArm(arguments[i]) {
                return false
            }
            i += 1
        }
        return true
    }

    static func IsSupportedAnonymousUnionArm(valueType: Type): bool {
        return valueType.FullName != "System.Void" && !valueType.get_IsByRef() && IsSupportedType(valueType)
    }

    static func IsSupportedCollectionType(valueType: Type): bool {
        if valueType is TypeBuilder || IsEnumBuilder(valueType) || !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }
        name := valueType.GetGenericTypeDefinition().FullName ?? ""
        return name == "System.Collections.Generic.List`1" || name == "System.Collections.Generic.Dictionary`2" || name == "System.Collections.Generic.SortedDictionary`2" || name == "System.Collections.Generic.HashSet`1" || name == "System.Collections.Generic.Stack`1" || name == "System.Collections.Generic.IReadOnlyList`1" || name == "System.Collections.Generic.IReadOnlyCollection`1" || name == "System.Collections.Generic.IReadOnlySet`1" || name == "System.Collections.Generic.IReadOnlyDictionary`2" || name == "System.Collections.Generic.IEnumerable`1"
    }

    // The element/value types a collection may close over (the builder-element rebind rung):
    // - a user TypeBuilder (record/class/struct under construction) — members rebind, probe-pinned working;
    // - a nested admissible collection (List<List<Pt>>, List<HashSet<int>>) — its own resolution already
    //   vetted the inner arguments, which is why the five concrete heads return before asking about them;
    // - the BAKED surface (scalars/string/enums/baked closed generics), through the supported-value tail.
    // PINNED DECLINES (legacy-emitter accepted, flip in later rungs): user-headed closed generics
    // (List<Box<int>>), builder-bound key/equality shapes, and tuples/delegates over builders.
    static func IsAdmissibleCollectionElement(valueType: Type): bool {
        if IsEnumBuilder(valueType) {
            return false
        }
        if IsEnumType(valueType) {
            return true
        }
        if valueType is TypeBuilder {
            return true
        }
        if valueType.get_IsGenericType() && !valueType.get_IsGenericTypeDefinition() {
            name := valueType.GetGenericTypeDefinition().FullName ?? ""
            if name == "System.Collections.Generic.List`1" || name == "System.Collections.Generic.Dictionary`2" || name == "System.Collections.Generic.SortedDictionary`2" || name == "System.Collections.Generic.HashSet`1" || name == "System.Collections.Generic.Stack`1" {
                return true
            }
            if ContainsBuilderBoundType(valueType) {
                return false
            }
        }
        return IsSupportedType(valueType) && !ContainsBuilderBoundType(valueType)
    }

    // HashSet<T> elements are keys: accepting builder-bound elements would make lookup behaviour depend
    // on generated Equals/GetHashCode synthesis before that key path has parity evidence. A source ENUM
    // is the one builder-bound shape that stays, because its underlying integral value is what is hashed.
    static func IsAdmissibleHashSetElement(valueType: Type): bool {
        return IsAdmissibleCollectionElement(valueType) && !ContainsNonEnumBuilderBoundType(valueType)
    }

    static func IsSupportedDelegateType(valueType: Type): bool {
        if valueType == typeof(Action) {
            return true
        }
        if valueType is TypeBuilder || IsEnumBuilder(valueType) || !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }
        name := valueType.GetGenericTypeDefinition().FullName ?? ""
        if name != "System.Action`1" && name != "System.Action`2" && name != "System.Action`3" && name != "System.Action`4" && name != "System.Func`1" && name != "System.Func`2" && name != "System.Func`3" && name != "System.Func`4" && name != "System.Func`5" {
            return false
        }
        arguments := valueType.GetGenericArguments()
        i := 0
        while i < arguments.Length {
            if ContainsBuilderBoundType(arguments[i]) || !IsSupportedType(arguments[i]) {
                return false
            }
            i += 1
        }
        return true
    }

    static func IsSupportedValueTuple(valueType: Type): bool {
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }
        name := valueType.GetGenericTypeDefinition().FullName ?? ""
        if name != "System.ValueTuple`2" && name != "System.ValueTuple`3" && name != "System.ValueTuple`4" && name != "System.ValueTuple`5" && name != "System.ValueTuple`6" && name != "System.ValueTuple`7" {
            return false
        }
        arguments := valueType.GetGenericArguments()
        i := 0
        while i < arguments.Length {
            argument := arguments[i]
            if IsEnumType(argument) || argument is TypeBuilder || IsClosedSourceGeneric(argument) || IsSupportedDelegateType(argument) || ContainsBuilderBoundType(argument) || !IsSupportedType(argument) {
                return false
            }
            i += 1
        }
        return true
    }

    static func OpenValueTupleType(arity: int): Type? {
        if arity == 2 {
            return typeof(ValueTuple<int, int>).GetGenericTypeDefinition()
        }
        if arity == 3 {
            return typeof(ValueTuple<int, int, int>).GetGenericTypeDefinition()
        }
        if arity == 4 {
            return typeof(ValueTuple<int, int, int, int>).GetGenericTypeDefinition()
        }
        if arity == 5 {
            return typeof(ValueTuple<int, int, int, int, int>).GetGenericTypeDefinition()
        }
        if arity == 6 {
            return typeof(ValueTuple<int, int, int, int, int, int>).GetGenericTypeDefinition()
        }
        if arity == 7 {
            return typeof(ValueTuple<int, int, int, int, int, int, int>).GetGenericTypeDefinition()
        }
        return null
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

    static func ContainsBuilderBoundType(valueType: Type): bool {
        if valueType is TypeBuilder || IsEnumBuilder(valueType) || valueType.get_IsGenericParameter() {
            return true
        }
        if valueType.get_IsSZArray() {
            element := valueType.GetElementType()
            return element != null && ContainsBuilderBoundType(element)
        }
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }
        definition := valueType.GetGenericTypeDefinition()
        if definition is TypeBuilder || IsEnumBuilder(definition) {
            return true
        }
        arguments := valueType.GetGenericArguments()
        i := 0
        while i < arguments.Length {
            if ContainsBuilderBoundType(arguments[i]) {
                return true
            }
            i += 1
        }
        return false
    }

    static func ContainsNonEnumBuilderBoundType(valueType: Type): bool {
        if IsEnumBuilder(valueType) {
            return true
        }
        if IsEnumType(valueType) {
            return false
        }
        if valueType is TypeBuilder || valueType.get_IsGenericParameter() {
            return true
        }
        if valueType.get_IsSZArray() {
            element := valueType.GetElementType()
            return element != null && ContainsNonEnumBuilderBoundType(element)
        }
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }
        definition := valueType.GetGenericTypeDefinition()
        if definition is TypeBuilder {
            return true
        }
        arguments := valueType.GetGenericArguments()
        i := 0
        while i < arguments.Length {
            if ContainsNonEnumBuilderBoundType(arguments[i]) {
                return true
            }
            i += 1
        }
        return false
    }

    static func IsClosedSourceGeneric(valueType: Type): bool {
        return !(valueType is TypeBuilder) && valueType.get_IsGenericType() && !valueType.get_IsGenericTypeDefinition() && valueType.GetGenericTypeDefinition() is TypeBuilder
    }

    // `EnumBuilder` is ABSTRACT on this runtime: a live instance is `EnumBuilderImpl` (persisted emit)
    // or `RuntimeEnumBuilder` (run emit), so an EXACT match on the base name can never be true and the
    // predicate silently reported every EnumBuilder as baked. The base chain is walked, exactly as
    // IsAssemblyBuilderBacked already walks it for AssemblyBuilder.
    static func IsEnumBuilder(valueType: Type): bool {
        if valueType == null {
            return false
        }
        candidate := valueType.GetType()
        while candidate != null {
            if candidate.FullName == "System.Reflection.Emit.EnumBuilder" {
                return true
            }
            candidate = candidate.get_BaseType()
        }
        return false
    }

    static func IsAssemblyBuilderBacked(valueType: Type): bool {
        assemblyObject: object = valueType.get_Assembly()
        assemblyType := assemblyObject.GetType()
        while assemblyType != null {
            if assemblyType.FullName == "System.Reflection.Emit.AssemblyBuilder" {
                return true
            }
            assemblyType = assemblyType.get_BaseType()
        }
        return false
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

    static func SameTypeShape(left: Type, right: Type): bool {
        if left == right {
            return true
        }
        if left.get_IsSZArray() || right.get_IsSZArray() {
            if !left.get_IsSZArray() || !right.get_IsSZArray() {
                return false
            }
            leftElement := left.GetElementType()
            rightElement := right.GetElementType()
            return leftElement != null && rightElement != null && SameTypeShape(leftElement, rightElement)
        }
        if !left.get_IsGenericType() || !right.get_IsGenericType() || left.get_IsGenericTypeDefinition() || right.get_IsGenericTypeDefinition() || left.GetGenericTypeDefinition() != right.GetGenericTypeDefinition() {
            return false
        }
        leftArguments := left.GetGenericArguments()
        rightArguments := right.GetGenericArguments()
        if leftArguments.Length != rightArguments.Length {
            return false
        }
        i := 0
        while i < leftArguments.Length {
            if !SameTypeShape(leftArguments[i], rightArguments[i]) {
                return false
            }
            i += 1
        }
        return true
    }

    static func SplitTopLevelPipes(canonical: string): List<string> {
        result := new List<string>()
        start := 0
        angleDepth := 0
        parenDepth := 0
        bracketDepth := 0
        i := 0
        while i < canonical.Length {
            c := canonical[i]
            if c == '<' {
                angleDepth += 1
            } else if c == '>' && angleDepth > 0 {
                angleDepth -= 1
            } else if c == '(' {
                parenDepth += 1
            } else if c == ')' && parenDepth > 0 {
                parenDepth -= 1
            } else if c == '[' {
                bracketDepth += 1
            } else if c == ']' && bracketDepth > 0 {
                bracketDepth -= 1
            } else if c == '|' && angleDepth == 0 && parenDepth == 0 && bracketDepth == 0 {
                result.Add(canonical.Substring(start, i - start))
                start = i + 1
            }
            i += 1
        }
        if result.Count > 0 {
            result.Add(canonical.Substring(start))
        }
        return result
    }

    static func UnwrapParentheses(nodes: ColumnarNodeTable, node: int): int {
        depth := 0
        while node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if depth > 200 || nodes.ChildCount(node) != 1 {
                return -1
            }
            node = nodes.Child(node, 0)
            depth += 1
        }
        return node
    }

    static func ValidateInputs(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan) {
        if nodes == null || source == null || bindings == null || plan == null || bindings.SourceTypeDefinitions == null || bindings.SourceUnionDefinitions == null {
            throw new InvalidOperationException("Typeof planning inputs and source type facts cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Typeof planning received an invalid root node index.")
        }
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        result := plan.ResultType
        if result == null {
            throw new InvalidOperationException("Planned typeof expression has no result type.")
        }
        return result
    }

    // The read-only dictionary definition is fetched BY NAME rather than by `typeof`: this kernel is
    // compiled by the pinned toolset, which is the one that does not yet publish the head.
    static func RequiredReadOnlyDictionaryDefinition(): Type {
        result := Type.GetType("System.Collections.Generic.IReadOnlyDictionary`2")
        if result == null {
            throw new InvalidOperationException("System.Collections.Generic.IReadOnlyDictionary`2 runtime type was not found.")
        }
        return result
    }

    // Fetched BY NAME for the same reason the read-only dictionary head is: the pinned toolset that
    // compiles this kernel does not resolve the `TextWriter` canonical, though it emits the type fine.
    static func RequiredTextWriterType(): Type {
        result := Type.GetType("System.IO.TextWriter")
        if result == null {
            throw new InvalidOperationException("System.IO.TextWriter runtime type was not found.")
        }
        return result
    }

    static func RequiredVoidType(): Type {
        result := Type.GetType("System.Void")
        if result == null {
            throw new InvalidOperationException("System.Void runtime type was not found.")
        }
        return result
    }

    static func RequiredNullableDefinition(): Type {
        result := Type.GetType("System.Nullable`1")
        if result == null {
            throw new InvalidOperationException("System.Nullable<T> runtime type was not found.")
        }
        return result
    }
}
