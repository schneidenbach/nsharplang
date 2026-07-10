namespace NSharpLang.Compiler.Columnar

import System

public enum ColumnarExternalStaticMemberKind {
    None,
    Field,
    Property
}

public enum ColumnarExternalCallKind {
    None,
    Call,
    CallVirtual
}

// Exact CLR selections owned by N#. The compiler host may materialize these names through
// reflection, but it may not substitute a type/member, score overloads, or widen an argument.
public class ColumnarExternalStaticMemberPlan {
    public IsSupported: bool
    public Kind: ColumnarExternalStaticMemberKind
    public DeclaringTypeName: string
    public MemberName: string
    public ValueTypeName: string

    constructor(
        isSupported: bool,
        kind: ColumnarExternalStaticMemberKind,
        declaringTypeName: string,
        memberName: string,
        valueTypeName: string) {
        IsSupported = isSupported
        Kind = kind
        DeclaringTypeName = declaringTypeName
        MemberName = memberName
        ValueTypeName = valueTypeName
    }
}

public class ColumnarExternalCallPlan {
    public IsSupported: bool
    public Kind: ColumnarExternalCallKind
    public DeclaringTypeName: string
    public MemberName: string
    public ParameterTypeNames: string[]
    public ReturnTypeName: string

    constructor(
        isSupported: bool,
        kind: ColumnarExternalCallKind,
        declaringTypeName: string,
        memberName: string,
        parameterTypeNames: string[],
        returnTypeName: string) {
        IsSupported = isSupported
        Kind = kind
        DeclaringTypeName = declaringTypeName
        MemberName = memberName
        ParameterTypeNames = parameterTypeNames
        ReturnTypeName = returnTypeName
    }
}

public class ColumnarExternalBindingPlans {
    public static func TryGetRuntimeTypeName(canonical: string, out runtimeTypeName: string): bool {
        runtimeTypeName = ""

        if canonical == "LocalBuilder" || canonical == "System.Reflection.Emit.LocalBuilder" {
            runtimeTypeName = "System.Reflection.Emit.LocalBuilder"
        } else if canonical == "FieldBuilder" || canonical == "System.Reflection.Emit.FieldBuilder" {
            runtimeTypeName = "System.Reflection.Emit.FieldBuilder"
        } else if canonical == "TypeBuilder" || canonical == "System.Reflection.Emit.TypeBuilder" {
            runtimeTypeName = "System.Reflection.Emit.TypeBuilder"
        } else if canonical == "MethodBuilder" || canonical == "System.Reflection.Emit.MethodBuilder" {
            runtimeTypeName = "System.Reflection.Emit.MethodBuilder"
        } else if canonical == "ConstructorBuilder" || canonical == "System.Reflection.Emit.ConstructorBuilder" {
            runtimeTypeName = "System.Reflection.Emit.ConstructorBuilder"
        } else if canonical == "ILGenerator" || canonical == "System.Reflection.Emit.ILGenerator" {
            runtimeTypeName = "System.Reflection.Emit.ILGenerator"
        } else if canonical == "OpCode" || canonical == "System.Reflection.Emit.OpCode" {
            runtimeTypeName = "System.Reflection.Emit.OpCode"
        } else if canonical == "OpCodes" || canonical == "System.Reflection.Emit.OpCodes" {
            runtimeTypeName = "System.Reflection.Emit.OpCodes"
        } else if canonical == "Label" || canonical == "System.Reflection.Emit.Label" {
            runtimeTypeName = "System.Reflection.Emit.Label"
        } else if canonical == "MethodInfo" || canonical == "System.Reflection.MethodInfo" {
            runtimeTypeName = "System.Reflection.MethodInfo"
        } else if canonical == "FieldInfo" || canonical == "System.Reflection.FieldInfo" {
            runtimeTypeName = "System.Reflection.FieldInfo"
        } else if canonical == "PropertyInfo" || canonical == "System.Reflection.PropertyInfo" {
            runtimeTypeName = "System.Reflection.PropertyInfo"
        } else if canonical == "ConstructorInfo" || canonical == "System.Reflection.ConstructorInfo" {
            runtimeTypeName = "System.Reflection.ConstructorInfo"
        } else if canonical == "ParameterInfo" || canonical == "System.Reflection.ParameterInfo" {
            runtimeTypeName = "System.Reflection.ParameterInfo"
        } else if canonical == "Index" || canonical == "System.Index" {
            runtimeTypeName = "System.Index"
        } else if canonical == "Range" || canonical == "System.Range" {
            runtimeTypeName = "System.Range"
        } else if canonical == "RuntimeHelpers"
            || canonical == "System.Runtime.CompilerServices.RuntimeHelpers" {
            runtimeTypeName = "System.Runtime.CompilerServices.RuntimeHelpers"
        } else {
            return false
        }

        runtimeTypeName = ExactTypeIdentity(runtimeTypeName)
        return true
    }

    public static func IsSupportedRuntimeTypeName(runtimeTypeName: string?): bool {
        name := runtimeTypeName ?? ""
        return name == "System.Reflection.Emit.LocalBuilder"
            || name == "System.Reflection.Emit.FieldBuilder"
            || name == "System.Reflection.Emit.TypeBuilder"
            || name == "System.Reflection.Emit.MethodBuilder"
            || name == "System.Reflection.Emit.ConstructorBuilder"
            || name == "System.Reflection.Emit.ILGenerator"
            || name == "System.Reflection.Emit.OpCode"
            || name == "System.Reflection.Emit.OpCodes"
            || name == "System.Reflection.Emit.Label"
            || name == "System.Reflection.MethodInfo"
            || name == "System.Reflection.FieldInfo"
            || name == "System.Reflection.PropertyInfo"
            || name == "System.Reflection.ConstructorInfo"
            || name == "System.Reflection.ParameterInfo"
            || name == "System.Index"
            || name == "System.Range"
    }

    public static func GetStaticMemberPlan(typeName: string, memberName: string): ColumnarExternalStaticMemberPlan {
        if (typeName == "OpCodes" || typeName == "System.Reflection.Emit.OpCodes")
            && IsSupportedOpCodeMemberName(memberName) {
            return StaticMember(
                ColumnarExternalStaticMemberKind.Field,
                "System.Reflection.Emit.OpCodes",
                memberName,
                "System.Reflection.Emit.OpCode")
        }

        if typeName == "StringComparer"
            && (memberName == "Ordinal" || memberName == "OrdinalIgnoreCase") {
            return StaticMember(
                ColumnarExternalStaticMemberKind.Property,
                "System.StringComparer",
                memberName,
                "System.StringComparer")
        }

        if typeName == "JsonNamingPolicy" && memberName == "CamelCase" {
            return StaticMember(
                ColumnarExternalStaticMemberKind.Property,
                "System.Text.Json.JsonNamingPolicy",
                memberName,
                "System.Text.Json.JsonNamingPolicy")
        }

        if typeName == "CamelCaseNamingConvention" && memberName == "Instance" {
            return StaticMember(
                ColumnarExternalStaticMemberKind.Field,
                "YamlDotNet.Serialization.NamingConventions.CamelCaseNamingConvention",
                memberName,
                "YamlDotNet.Serialization.INamingConvention")
        }

        if typeName == "Environment"
            && (memberName == "NewLine" || memberName == "CurrentDirectory") {
            return StaticMember(
                ColumnarExternalStaticMemberKind.Property,
                "System.Environment",
                memberName,
                "System.String")
        }

        if typeName == "AppContext" && memberName == "BaseDirectory" {
            return StaticMember(
                ColumnarExternalStaticMemberKind.Property,
                "System.AppContext",
                memberName,
                "System.String")
        }

        if typeName == "CultureInfo" && memberName == "InvariantCulture" {
            return StaticMember(
                ColumnarExternalStaticMemberKind.Property,
                "System.Globalization.CultureInfo",
                memberName,
                "System.Globalization.CultureInfo")
        }

        if typeName == "AppDomain" && memberName == "CurrentDomain" {
            return StaticMember(
                ColumnarExternalStaticMemberKind.Property,
                "System.AppDomain",
                memberName,
                "System.AppDomain")
        }

        if typeName == "Console" && memberName == "Error" {
            return StaticMember(
                ColumnarExternalStaticMemberKind.Property,
                "System.Console",
                memberName,
                "System.IO.TextWriter")
        }

        if typeName == "Task" && memberName == "CompletedTask" {
            return StaticMember(
                ColumnarExternalStaticMemberKind.Property,
                "System.Threading.Tasks.Task",
                memberName,
                "System.Threading.Tasks.Task")
        }

        if typeName == "Random" && memberName == "Shared" {
            return StaticMember(
                ColumnarExternalStaticMemberKind.Property,
                "System.Random",
                memberName,
                "System.Random")
        }

        if typeName == "DateTime" {
            if memberName == "Now" || memberName == "UtcNow" || memberName == "Today" {
                return StaticMember(
                    ColumnarExternalStaticMemberKind.Property,
                    "System.DateTime",
                    memberName,
                    "System.DateTime")
            }
            if memberName == "UnixEpoch" || memberName == "MinValue" || memberName == "MaxValue" {
                return StaticMember(
                    ColumnarExternalStaticMemberKind.Field,
                    "System.DateTime",
                    memberName,
                    "System.DateTime")
            }
        }

        return NoStaticMember()
    }

    public static func GetInstanceCallPlan(
        receiverTypeName: string?,
        memberName: string,
        argumentTypeNames: string[]): ColumnarExternalCallPlan {
        receiver := receiverTypeName ?? ""
        count := argumentTypeNames.Length

        if receiver == "System.Type" && count == 1 && argumentTypeNames[0] == "System.String" {
            if memberName == "GetProperty" {
                return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.PropertyInfo")
            }
            if memberName == "GetField" {
                return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.FieldInfo")
            }
            if memberName == "GetMethod" {
                return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.MethodInfo")
            }
        }

        if receiver == "System.Type" {
            if memberName == "GetConstructor"
                && count == 1
                && argumentTypeNames[0] == "System.Type[]" {
                return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.ConstructorInfo")
            }
            if memberName == "GetMethod"
                && count == 2
                && argumentTypeNames[0] == "System.String"
                && argumentTypeNames[1] == "System.Type[]" {
                return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.MethodInfo")
            }
            if (memberName == "GetElementType" || memberName == "MakeArrayType") && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Type")
            }
            if (memberName == "get_IsSZArray"
                    || memberName == "get_IsValueType"
                    || memberName == "get_IsEnum"
                    || memberName == "get_IsByRef")
                && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Boolean")
            }
            if memberName == "IsAssignableFrom"
                && count == 1
                && argumentTypeNames[0] == "System.Type" {
                return VirtualCall(receiver, memberName, One("System.Type"), "System.Boolean")
            }
        }

        if receiver == "System.Reflection.Emit.LocalBuilder"
            && memberName == "get_LocalType" && count == 0 {
            return VirtualCall(receiver, memberName, Empty(), "System.Type")
        }

        if receiver == "System.Reflection.PropertyInfo"
            && memberName == "GetValue" && count == 1 {
            return VirtualCall(receiver, memberName, One("System.Object"), "System.Object")
        }

        if receiver == "System.Reflection.FieldInfo"
            && memberName == "GetValue" && count == 1 {
            return VirtualCall(receiver, memberName, One("System.Object"), "System.Object")
        }

        if receiver == "System.Reflection.PropertyInfo"
            && memberName == "GetGetMethod" && count == 0 {
            return VirtualCall(receiver, memberName, Empty(), "System.Reflection.MethodInfo")
        }

        if receiver == "System.Reflection.MethodInfo"
            && memberName == "MakeGenericMethod"
            && count == 1
            && argumentTypeNames[0] == "System.Type[]" {
            return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.MethodInfo")
        }

        if receiver == "System.Reflection.MethodInfo" && count == 0 {
            if memberName == "GetParameters" {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.ParameterInfo[]")
            }
            if memberName == "get_ReturnType" || memberName == "get_DeclaringType" {
                return VirtualCall(receiver, memberName, Empty(), "System.Type")
            }
            if memberName == "get_IsStatic" {
                return VirtualCall(receiver, memberName, Empty(), "System.Boolean")
            }
        }

        if receiver == "System.Reflection.ConstructorInfo" && count == 0 {
            if memberName == "GetParameters" {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.ParameterInfo[]")
            }
            if memberName == "get_DeclaringType" {
                return VirtualCall(receiver, memberName, Empty(), "System.Type")
            }
            if memberName == "get_IsStatic" {
                return VirtualCall(receiver, memberName, Empty(), "System.Boolean")
            }
        }

        if receiver == "System.Reflection.FieldInfo" && count == 0 {
            if memberName == "get_FieldType" || memberName == "get_DeclaringType" {
                return VirtualCall(receiver, memberName, Empty(), "System.Type")
            }
            if memberName == "get_IsStatic" {
                return VirtualCall(receiver, memberName, Empty(), "System.Boolean")
            }
        }

        if receiver == "System.Reflection.ParameterInfo"
            && memberName == "get_ParameterType" && count == 0 {
            return VirtualCall(receiver, memberName, Empty(), "System.Type")
        }

        if receiver == "System.Diagnostics.Process" {
            if memberName == "Start" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Boolean")
            }
            if memberName == "WaitForExit" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Void")
            }
            if memberName == "WaitForExit" && count == 1 {
                return VirtualCall(receiver, memberName, One("System.Int32"), "System.Boolean")
            }
            if memberName == "Kill" && count == 1 {
                return VirtualCall(receiver, memberName, One("System.Boolean"), "System.Void")
            }
        }

        if receiver == "System.IO.StreamReader"
            && memberName == "ReadToEndAsync" && count == 0 {
            return VirtualCall(
                receiver,
                memberName,
                Empty(),
                "System.Threading.Tasks.Task`1[System.String]")
        }

        if receiver == "System.IO.TextWriter"
            && memberName == "WriteLine"
            && count == 1
            && argumentTypeNames[0] == "System.String" {
            return VirtualCall(receiver, memberName, One("System.String"), "System.Void")
        }

        if receiver == "System.Random" && memberName == "Next" && count <= 2 {
            if count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Int32")
            }
            if count == 1 {
                return VirtualCall(receiver, memberName, One("System.Int32"), "System.Int32")
            }
            return VirtualCall(receiver, memberName, Two("System.Int32", "System.Int32"), "System.Int32")
        }

        if receiver == "System.Reflection.Emit.ILGenerator" {
            if memberName == "DeclareLocal" && count == 1 {
                return VirtualCall(receiver, memberName, One("System.Type"), "System.Reflection.Emit.LocalBuilder")
            }
            if memberName == "DeclareLocal" && count == 2 {
                return VirtualCall(
                    receiver,
                    memberName,
                    Two("System.Type", "System.Boolean"),
                    "System.Reflection.Emit.LocalBuilder")
            }
            if memberName == "DefineLabel" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.Emit.Label")
            }
            if memberName == "MarkLabel" && count == 1 {
                return VirtualCall(receiver, memberName, One("System.Reflection.Emit.Label"), "System.Void")
            }
            if memberName == "BeginExceptionBlock" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.Emit.Label")
            }
            if memberName == "BeginCatchBlock" && count == 1 {
                return VirtualCall(receiver, memberName, One("System.Type"), "System.Void")
            }
            if (memberName == "BeginFinallyBlock"
                    || memberName == "BeginFaultBlock"
                    || memberName == "BeginExceptFilterBlock"
                    || memberName == "EndExceptionBlock")
                && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Void")
            }
            if memberName == "Emit" && count >= 1
                && argumentTypeNames[0] == "System.Reflection.Emit.OpCode" {
                if count == 1 {
                    return VirtualCall(receiver, memberName, One("System.Reflection.Emit.OpCode"), "System.Void")
                }
                if count == 2 && IsSupportedEmitOperand(argumentTypeNames[1]) {
                    return VirtualCall(
                        receiver,
                        memberName,
                        Two("System.Reflection.Emit.OpCode", argumentTypeNames[1]),
                        "System.Void")
                }
            }
        }

        return NoCall()
    }

    static func IsSupportedEmitOperand(typeName: string): bool {
        return typeName == "System.Int32"
            || typeName == "System.Int16"
            || typeName == "System.Int64"
            || typeName == "System.Single"
            || typeName == "System.Double"
            || typeName == "System.String"
            || typeName == "System.Type"
            || typeName == "System.Reflection.Emit.LocalBuilder"
            || typeName == "System.Reflection.Emit.Label"
            || typeName == "System.Reflection.Emit.Label[]"
            || typeName == "System.Reflection.MethodInfo"
            || typeName == "System.Reflection.ConstructorInfo"
            || typeName == "System.Reflection.FieldInfo"
    }

    static func IsSupportedOpCodeMemberName(memberName: string): bool {
        return memberName == "Nop"
            || memberName == "Ldc_I4_M1"
            || memberName == "Ldc_I4_0"
            || memberName == "Ldc_I4_1"
            || memberName == "Ldc_I4_2"
            || memberName == "Ldc_I4_3"
            || memberName == "Ldc_I4_4"
            || memberName == "Ldc_I4_5"
            || memberName == "Ldc_I4_6"
            || memberName == "Ldc_I4_7"
            || memberName == "Ldc_I4_8"
            || memberName == "Ldc_I4"
            || memberName == "Stloc"
            || memberName == "Ldloc"
            || memberName == "Ldloca"
            || memberName == "Ldarg"
            || memberName == "Br"
            || memberName == "Brfalse"
            || memberName == "Call"
            || memberName == "Callvirt"
            || memberName == "Newobj"
            || memberName == "Conv_I4"
            || memberName == "Ldfld"
            || memberName == "Ldlen"
            || memberName == "Ldelem_U1"
            || memberName == "Ldelem_U2"
            || memberName == "Ldelem_I4"
            || memberName == "Ldelem_U4"
            || memberName == "Ldelem_I8"
            || memberName == "Ldelem_R4"
            || memberName == "Ldelem_R8"
            || memberName == "Ldelem_Ref"
            || memberName == "Ldelem"
            || memberName == "Pop"
            || memberName == "Ret"
    }

    static func StaticMember(
        kind: ColumnarExternalStaticMemberKind,
        declaringTypeName: string,
        memberName: string,
        valueTypeName: string): ColumnarExternalStaticMemberPlan {
        return new ColumnarExternalStaticMemberPlan(
            true,
            kind,
            ExactTypeIdentity(declaringTypeName),
            memberName,
            ExactTypeIdentity(valueTypeName))
    }

    static func NoStaticMember(): ColumnarExternalStaticMemberPlan {
        return new ColumnarExternalStaticMemberPlan(
            false,
            ColumnarExternalStaticMemberKind.None,
            "",
            "",
            "")
    }

    static func VirtualCall(
        declaringTypeName: string,
        memberName: string,
        parameterTypeNames: string[],
        returnTypeName: string): ColumnarExternalCallPlan {
        exactParameterTypeNames := new string[](parameterTypeNames.Length)
        i := 0
        while i < parameterTypeNames.Length {
            exactParameterTypeNames[i] = ExactTypeIdentity(parameterTypeNames[i])
            i = i + 1
        }

        return new ColumnarExternalCallPlan(
            true,
            ColumnarExternalCallKind.CallVirtual,
            ExactTypeIdentity(declaringTypeName),
            memberName,
            exactParameterTypeNames,
            ExactTypeIdentity(returnTypeName))
    }

    static func NoCall(): ColumnarExternalCallPlan {
        return new ColumnarExternalCallPlan(
            false,
            ColumnarExternalCallKind.None,
            "",
            "",
            Empty(),
            "")
    }

    static func Empty(): string[] {
        return new string[](0)
    }

    static func One(first: string): string[] {
        values := new string[](1)
        values[0] = first
        return values
    }

    static func Two(first: string, second: string): string[] {
        values := new string[](2)
        values[0] = first
        values[1] = second
        return values
    }

    static func ExactTypeIdentity(fullName: string): string {
        if fullName.StartsWith("YamlDotNet.", StringComparison.Ordinal) {
            return fullName + ", YamlDotNet"
        }
        if fullName == "System.Console" {
            return fullName + ", System.Console"
        }
        if fullName.StartsWith("System.Text.Json.", StringComparison.Ordinal) {
            return fullName + ", System.Text.Json"
        }
        if fullName.StartsWith("System.Diagnostics.Process", StringComparison.Ordinal) {
            return fullName + ", System.Diagnostics.Process"
        }

        return fullName + ", System.Private.CoreLib"
    }
}
