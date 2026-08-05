namespace NSharpLang.Compiler.Columnar

import System

enum ColumnarExternalStaticMemberKind {
    None,
    Field,
    Property
}

enum ColumnarExternalCallKind {
    None,
    Call,
    CallVirtual
}

// Exact CLR selections owned by N#. The compiler host may materialize these names through
// reflection, but it may not substitute a type/member, score overloads, or widen an argument.
class ColumnarExternalStaticMemberPlan {
    IsSupported: bool
    Kind: ColumnarExternalStaticMemberKind
    DeclaringTypeName: string
    MemberName: string
    ValueTypeName: string

    constructor(isSupported: bool, kind: ColumnarExternalStaticMemberKind, declaringTypeName: string, memberName: string, valueTypeName: string) {
        IsSupported = isSupported
        Kind = kind
        DeclaringTypeName = declaringTypeName
        MemberName = memberName
        ValueTypeName = valueTypeName
    }
}

class ColumnarExternalCallPlan {
    IsSupported: bool
    Kind: ColumnarExternalCallKind
    DeclaringTypeName: string
    MemberName: string
    ParameterTypeNames: string[]
    ReturnTypeName: string

    // Non-empty ONLY for a plan that closes a generic method definition with plan-pinned type
    // arguments (`String.Join<int>`). The parameter/return identities above always describe the
    // CLOSED signature; an empty list keeps the original non-generic contract.
    TypeArgumentNames: string[]

    constructor(isSupported: bool, kind: ColumnarExternalCallKind, declaringTypeName: string, memberName: string, parameterTypeNames: string[], returnTypeName: string) {
        IsSupported = isSupported
        Kind = kind
        DeclaringTypeName = declaringTypeName
        MemberName = memberName
        ParameterTypeNames = parameterTypeNames
        ReturnTypeName = returnTypeName
        TypeArgumentNames = new string[](0)
    }
}

class ColumnarExternalBindingPlans {
    static func TryGetRuntimeTypeName(canonical: string, out runtimeTypeName: string): bool {
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
        } else if canonical == "DynamicMethod" || canonical == "System.Reflection.Emit.DynamicMethod" {
            runtimeTypeName = "System.Reflection.Emit.DynamicMethod"
        } else if canonical == "OpCode" || canonical == "System.Reflection.Emit.OpCode" {
            runtimeTypeName = "System.Reflection.Emit.OpCode"
        } else if canonical == "OpCodes" || canonical == "System.Reflection.Emit.OpCodes" {
            runtimeTypeName = "System.Reflection.Emit.OpCodes"
        } else if canonical == "Label" || canonical == "System.Reflection.Emit.Label" {
            runtimeTypeName = "System.Reflection.Emit.Label"
        } else if canonical == "MethodInfo" || canonical == "System.Reflection.MethodInfo" {
            runtimeTypeName = "System.Reflection.MethodInfo"
        } else if canonical == "MethodAttributes" || canonical == "System.Reflection.MethodAttributes" {
            runtimeTypeName = "System.Reflection.MethodAttributes"
        } else if canonical == "CallingConventions" || canonical == "System.Reflection.CallingConventions" {
            runtimeTypeName = "System.Reflection.CallingConventions"
        } else if canonical == "MethodBase" || canonical == "System.Reflection.MethodBase" {
            runtimeTypeName = "System.Reflection.MethodBase"
        } else if canonical == "FieldInfo" || canonical == "System.Reflection.FieldInfo" {
            runtimeTypeName = "System.Reflection.FieldInfo"
        } else if canonical == "PropertyInfo" || canonical == "System.Reflection.PropertyInfo" {
            runtimeTypeName = "System.Reflection.PropertyInfo"
        } else if canonical == "ConstructorInfo" || canonical == "System.Reflection.ConstructorInfo" {
            runtimeTypeName = "System.Reflection.ConstructorInfo"
        } else if canonical == "AssemblyName" || canonical == "System.Reflection.AssemblyName" {
            runtimeTypeName = "System.Reflection.AssemblyName"
        } else if canonical == "MetadataLoadContext" || canonical == "System.Reflection.MetadataLoadContext" {
            runtimeTypeName = "System.Reflection.MetadataLoadContext"
        } else if canonical == "PathAssemblyResolver" || canonical == "System.Reflection.PathAssemblyResolver" {
            runtimeTypeName = "System.Reflection.PathAssemblyResolver"
        } else if canonical == "MetadataAssemblyResolver" || canonical == "System.Reflection.MetadataAssemblyResolver" {
            runtimeTypeName = "System.Reflection.MetadataAssemblyResolver"
        } else if canonical == "ParameterInfo" || canonical == "System.Reflection.ParameterInfo" {
            runtimeTypeName = "System.Reflection.ParameterInfo"
        } else if canonical == "EventInfo" || canonical == "System.Reflection.EventInfo" {
            runtimeTypeName = "System.Reflection.EventInfo"
        } else if canonical == "Index" || canonical == "System.Index" {
            runtimeTypeName = "System.Index"
        } else if canonical == "Range" || canonical == "System.Range" {
            runtimeTypeName = "System.Range"
        } else if canonical == "RuntimeTypeHandle" || canonical == "System.RuntimeTypeHandle" {
            runtimeTypeName = "System.RuntimeTypeHandle"
        } else if canonical == "RuntimeHelpers" || canonical == "System.Runtime.CompilerServices.RuntimeHelpers" {
            runtimeTypeName = "System.Runtime.CompilerServices.RuntimeHelpers"
        } else if canonical == "Array" || canonical == "System.Array" {
            runtimeTypeName = "System.Array"
        } else if canonical == "NullabilityInfoContext" || canonical == "System.Reflection.NullabilityInfoContext" {
            runtimeTypeName = "System.Reflection.NullabilityInfoContext"
        } else if canonical == "NullabilityInfo" || canonical == "System.Reflection.NullabilityInfo" {
            runtimeTypeName = "System.Reflection.NullabilityInfo"
        } else if canonical == "NullabilityState" || canonical == "System.Reflection.NullabilityState" {
            runtimeTypeName = "System.Reflection.NullabilityState"
        } else if canonical == "CustomAttributeData" || canonical == "System.Reflection.CustomAttributeData" {
            runtimeTypeName = "System.Reflection.CustomAttributeData"
        } else if canonical == "CustomAttributeTypedArgument" || canonical == "System.Reflection.CustomAttributeTypedArgument" {
            runtimeTypeName = "System.Reflection.CustomAttributeTypedArgument"
        } else {
            return false
        }

        runtimeTypeName = ExactTypeIdentity(runtimeTypeName)
        return true
    }

    static func IsSupportedRuntimeTypeName(runtimeTypeName: string?): bool {
        name := runtimeTypeName ?? ""
        return name == "System.Reflection.Emit.LocalBuilder" || name == "System.Reflection.Emit.FieldBuilder" || name == "System.Reflection.Emit.TypeBuilder" || name == "System.Reflection.Emit.MethodBuilder" || name == "System.Reflection.Emit.ConstructorBuilder" || name == "System.Reflection.Emit.ILGenerator" || name == "System.Reflection.Emit.DynamicMethod" || name == "System.Reflection.Emit.OpCode" || name == "System.Reflection.Emit.OpCodes" || name == "System.Reflection.Emit.Label" || name == "System.Reflection.MethodInfo" || name == "System.Reflection.MethodAttributes" || name == "System.Reflection.CallingConventions" || name == "System.Reflection.MethodBase" || name == "System.Reflection.FieldInfo" || name == "System.Reflection.PropertyInfo" || name == "System.Reflection.ConstructorInfo" || name == "System.Reflection.AssemblyName" || name == "System.Reflection.MetadataLoadContext" || name == "System.Reflection.PathAssemblyResolver" || name == "System.Reflection.MetadataAssemblyResolver" || name == "System.Reflection.ParameterInfo" || name == "System.Reflection.EventInfo" || name == "System.Index" || name == "System.Range" || name == "System.RuntimeTypeHandle" || name == "System.Reflection.NullabilityInfoContext" || name == "System.Reflection.NullabilityInfo" || name == "System.Reflection.NullabilityState" || name == "System.Reflection.CustomAttributeData" || name == "System.Reflection.CustomAttributeTypedArgument" || IsCustomAttributeSequenceName(name)
    }
    // A .NET EVENT is a distinct member kind, not a field: `+=` against one must be
    // rejected with its own diagnostic and `on`/`off` must subscribe through the add_/
    // remove_ accessors instead of writing the private backing field. Naming the member
    // kind is what makes that distinction expressible.

    // The reflected-nullability surface. NullabilityInfoContext.Create answers the read
    // state a `?` annotation compiles to, and CustomAttributeData carries the flow
    // attributes (MaybeNull/NotNull/NotNullWhen/ParamArray) that annotation cannot express;
    // together they are what an external member's N# type must be built from.

    // The attribute-data sequences the reflected members answer with. Their identity is COMPUTED,
    // never spelled: a closed BCL generic's FullName carries its argument's version and public key,
    // so a literal row would pin one runtime version. The prefix test comes first so that this
    // admission path — which every emitted local type reaches — stays off reflection for every
    // name that is not a closed IList.
    static func IsCustomAttributeSequenceName(name: string): bool {
        if !name.StartsWith("System.Collections.Generic.IList`1[[", StringComparison.Ordinal) {
            return false
        }

        return name == CustomAttributeDataListFullName() || name == CustomAttributeTypedArgumentListFullName()
    }

    // `System.Collections.Generic.IList`1[[System.Reflection.CustomAttributeData, ...]]` as this
    // runtime spells it. GetCustomAttributesData answers exactly this type, so it must be a
    // declarable local type for the attribute walk to bind at all.
    static func CustomAttributeDataListFullName(): string {
        return ClosedListFullName("System.Reflection.CustomAttributeData")
    }

    // The same for `CustomAttributeData.ConstructorArguments`.
    static func CustomAttributeTypedArgumentListFullName(): string {
        return ClosedListFullName("System.Reflection.CustomAttributeTypedArgument")
    }

    static func ClosedListFullName(elementFullName: string): string {
        definition := Type.GetType("System.Collections.Generic.IList`1, System.Private.CoreLib")
        if definition == null {
            throw new InvalidOperationException("Required runtime generic type 'System.Collections.Generic.IList`1' was not found.")
        }
        elementType := Type.GetType(elementFullName + ", System.Private.CoreLib")
        if elementType == null {
            throw new InvalidOperationException("Required runtime type '" + elementFullName + "' was not found.")
        }
        arguments := new Type[](1)
        arguments[0] = elementType
        listType := definition.MakeGenericType(arguments)
        fullName := listType.FullName ?? ""
        return fullName
    }

    static func GetStaticMemberPlan(typeName: string, memberName: string): ColumnarExternalStaticMemberPlan {
        if (typeName == "ArrayPool" || typeName == "ByteArrayPool" || typeName == "System.Buffers.ArrayPool") && memberName == "Shared" {
            poolType := ClosedByteGenericType("System.Buffers.ArrayPool`1, System.Private.CoreLib")
            return StaticMemberFromTypes(ColumnarExternalStaticMemberKind.Property, poolType, memberName, poolType)
        }

        if (typeName == "MemoryPool" || typeName == "ByteMemoryPool" || typeName == "System.Buffers.MemoryPool") && memberName == "Shared" {
            poolType := ClosedByteGenericType("System.Buffers.MemoryPool`1, System.Memory")
            return StaticMemberFromTypes(ColumnarExternalStaticMemberKind.Property, poolType, memberName, poolType)
        }

        if MatchesOwner(typeName, "StringComparison", "System.StringComparison") {
            return StaticMember(ColumnarExternalStaticMemberKind.Field, "System.StringComparison", memberName, "System.StringComparison")
        }

        // The nullability read state a reflected member answers with. It is an ordinary CLR enum,
        // so every member is a literal field on its own type.
        if MatchesOwner(typeName, "NullabilityState", "System.Reflection.NullabilityState") {
            return StaticMember(ColumnarExternalStaticMemberKind.Field, "System.Reflection.NullabilityState", memberName, "System.Reflection.NullabilityState")
        }

        if MatchesOwner(typeName, "JsonValueKind", "System.Text.Json.JsonValueKind") {
            return StaticMember(ColumnarExternalStaticMemberKind.Field, "System.Text.Json.JsonValueKind", memberName, "System.Text.Json.JsonValueKind")
        }

        if MatchesOwner(typeName, "SearchOption", "System.IO.SearchOption") && memberName == "TopDirectoryOnly" {
            return StaticMember(ColumnarExternalStaticMemberKind.Field, "System.IO.SearchOption", memberName, "System.IO.SearchOption")
        }

        if MatchesOwner(typeName, "NumberStyles", "System.Globalization.NumberStyles") && memberName == "HexNumber" {
            return StaticMember(ColumnarExternalStaticMemberKind.Field, "System.Globalization.NumberStyles", memberName, "System.Globalization.NumberStyles")
        }

        if MatchesOwner(typeName, "MethodAttributes", "System.Reflection.MethodAttributes") && memberName == "Public" {
            return StaticMember(ColumnarExternalStaticMemberKind.Field, "System.Reflection.MethodAttributes", memberName, "System.Reflection.MethodAttributes")
        }

        // The binding mask. Every member is a literal field on its own type, and the whole enum is
        // admitted rather than a chosen few: a mask is USED by combining its members, so admitting
        // a subset would only move the decline. Without this row no expression mentioning a
        // `BindingFlags` member can be typed at all, which is why the filtered-overload call rows
        // below (`Type.GetMethods`, and `Type.GetProperty`'s two-argument form before it) are
        // unreachable until it exists.
        if MatchesOwner(typeName, "BindingFlags", "System.Reflection.BindingFlags") {
            return StaticMember(ColumnarExternalStaticMemberKind.Field, "System.Reflection.BindingFlags", memberName, "System.Reflection.BindingFlags")
        }

        if MatchesOwner(typeName, "CallingConventions", "System.Reflection.CallingConventions") && memberName == "Standard" {
            return StaticMember(ColumnarExternalStaticMemberKind.Field, "System.Reflection.CallingConventions", memberName, "System.Reflection.CallingConventions")
        }

        if MatchesOwner(typeName, "Environment.SpecialFolder", "System.Environment.SpecialFolder") && memberName == "UserProfile" {
            return StaticMember(ColumnarExternalStaticMemberKind.Field, "System.Environment+SpecialFolder", memberName, "System.Environment+SpecialFolder")
        }

        primitiveTypeName := PrimitiveLimitTypeName(typeName)
        if primitiveTypeName.Length > 0 && (memberName == "MinValue" || memberName == "MaxValue") {
            return StaticMember(ColumnarExternalStaticMemberKind.Field, primitiveTypeName, memberName, primitiveTypeName)
        }

        if (typeName == "OpCodes" || typeName == "System.Reflection.Emit.OpCodes") && IsSupportedOpCodeMemberName(memberName) {
            return StaticMember(ColumnarExternalStaticMemberKind.Field, "System.Reflection.Emit.OpCodes", memberName, "System.Reflection.Emit.OpCode")
        }

        if MatchesOwner(typeName, "StringComparer", "System.StringComparer") && (memberName == "Ordinal" || memberName == "OrdinalIgnoreCase") {
            return StaticMember(ColumnarExternalStaticMemberKind.Property, "System.StringComparer", memberName, "System.StringComparer")
        }

        if MatchesOwner(typeName, "JsonNamingPolicy", "System.Text.Json.JsonNamingPolicy") && memberName == "CamelCase" {
            return StaticMember(ColumnarExternalStaticMemberKind.Property, "System.Text.Json.JsonNamingPolicy", memberName, "System.Text.Json.JsonNamingPolicy")
        }

        if MatchesOwner(typeName, "CamelCaseNamingConvention", "YamlDotNet.Serialization.NamingConventions.CamelCaseNamingConvention") && memberName == "Instance" {
            return StaticMember(ColumnarExternalStaticMemberKind.Field, "YamlDotNet.Serialization.NamingConventions.CamelCaseNamingConvention", memberName, "YamlDotNet.Serialization.INamingConvention")
        }

        if MatchesOwner(typeName, "Environment", "System.Environment") && (memberName == "NewLine" || memberName == "CurrentDirectory") {
            return StaticMember(ColumnarExternalStaticMemberKind.Property, "System.Environment", memberName, "System.String")
        }

        if MatchesOwner(typeName, "AppContext", "System.AppContext") && memberName == "BaseDirectory" {
            return StaticMember(ColumnarExternalStaticMemberKind.Property, "System.AppContext", memberName, "System.String")
        }

        if MatchesOwner(typeName, "CultureInfo", "System.Globalization.CultureInfo") && memberName == "InvariantCulture" {
            return StaticMember(ColumnarExternalStaticMemberKind.Property, "System.Globalization.CultureInfo", memberName, "System.Globalization.CultureInfo")
        }

        if MatchesOwner(typeName, "AppDomain", "System.AppDomain") && memberName == "CurrentDomain" {
            return StaticMember(ColumnarExternalStaticMemberKind.Property, "System.AppDomain", memberName, "System.AppDomain")
        }

        if MatchesOwner(typeName, "Console", "System.Console") && memberName == "Error" {
            return StaticMember(ColumnarExternalStaticMemberKind.Property, "System.Console", memberName, "System.IO.TextWriter")
        }

        if MatchesOwner(typeName, "Task", "System.Threading.Tasks.Task") && memberName == "CompletedTask" {
            return StaticMember(ColumnarExternalStaticMemberKind.Property, "System.Threading.Tasks.Task", memberName, "System.Threading.Tasks.Task")
        }

        if MatchesOwner(typeName, "Random", "System.Random") && memberName == "Shared" {
            return StaticMember(ColumnarExternalStaticMemberKind.Property, "System.Random", memberName, "System.Random")
        }

        if MatchesOwner(typeName, "DateTime", "System.DateTime") {
            if memberName == "Now" || memberName == "UtcNow" || memberName == "Today" {
                return StaticMember(ColumnarExternalStaticMemberKind.Property, "System.DateTime", memberName, "System.DateTime")
            }
            if memberName == "UnixEpoch" || memberName == "MinValue" || memberName == "MaxValue" {
                return StaticMember(ColumnarExternalStaticMemberKind.Field, "System.DateTime", memberName, "System.DateTime")
            }
        }

        return NoStaticMember()
    }

    static func PrimitiveLimitTypeName(typeName: string): string {
        if typeName == "int" || typeName == "Int32" || typeName == "System.Int32" {
            return "System.Int32"
        }
        if typeName == "long" || typeName == "Int64" || typeName == "System.Int64" {
            return "System.Int64"
        }
        if typeName == "uint" || typeName == "UInt32" || typeName == "System.UInt32" {
            return "System.UInt32"
        }
        if typeName == "ulong" || typeName == "UInt64" || typeName == "System.UInt64" {
            return "System.UInt64"
        }
        if typeName == "short" || typeName == "Int16" || typeName == "System.Int16" {
            return "System.Int16"
        }
        if typeName == "ushort" || typeName == "UInt16" || typeName == "System.UInt16" {
            return "System.UInt16"
        }
        if typeName == "byte" || typeName == "Byte" || typeName == "System.Byte" {
            return "System.Byte"
        }
        if typeName == "sbyte" || typeName == "SByte" || typeName == "System.SByte" {
            return "System.SByte"
        }
        return ""
    }

    static func MatchesOwner(value: string, shortName: string, fullName: string): bool {
        return value == shortName || value == fullName
    }

    static func GetStaticCallPlan(typeName: string, memberName: string, argumentTypeNames: string[]): ColumnarExternalCallPlan {
        count := argumentTypeNames.Length

        if MatchesOwner(typeName, "Object", "System.Object") && memberName == "ReferenceEquals" && count == 2 && IsReferenceIdentityArgumentType(argumentTypeNames[0]) && IsReferenceIdentityArgumentType(argumentTypeNames[1]) {
            return StaticCall("System.Object", memberName, Two("System.Object", "System.Object"), "System.Boolean")
        }

        if (typeName == "Assembly" || typeName == "System.Reflection.Assembly") && memberName == "LoadFrom" && count == 1 && argumentTypeNames[0] == "System.String" {
            return StaticCall("System.Reflection.Assembly", memberName, One("System.String"), "System.Reflection.Assembly")
        }

        if (typeName == "Assembly" || typeName == "System.Reflection.Assembly") && memberName == "Load" && count == 1 && argumentTypeNames[0] == "System.String" {
            return StaticCall("System.Reflection.Assembly", memberName, One("System.String"), "System.Reflection.Assembly")
        }

        if typeName == "AssemblyName" || typeName == "System.Reflection.AssemblyName" {
            if memberName == "GetAssemblyName" && count == 1 && argumentTypeNames[0] == "System.String" {
                return StaticCall("System.Reflection.AssemblyName", memberName, One("System.String"), "System.Reflection.AssemblyName")
            }
            if memberName == "ReferenceMatchesDefinition" && count == 2 && argumentTypeNames[0] == "System.Reflection.AssemblyName" && argumentTypeNames[1] == "System.Reflection.AssemblyName" {
                return StaticCall("System.Reflection.AssemblyName", memberName, Two("System.Reflection.AssemblyName", "System.Reflection.AssemblyName"), "System.Boolean")
            }
        }

        if typeName == "Type" && memberName == "GetType" && count == 1 && argumentTypeNames[0] == "System.String" {
            return StaticCall("System.Type", memberName, One("System.String"), "System.Type")
        }

        if typeName == "TypeBuilder" || typeName == "System.Reflection.Emit.TypeBuilder" {
            if memberName == "GetField" && count == 2 && argumentTypeNames[0] == "System.Type" && argumentTypeNames[1] == "System.Reflection.FieldInfo" {
                return StaticCall("System.Reflection.Emit.TypeBuilder", memberName, Two("System.Type", "System.Reflection.FieldInfo"), "System.Reflection.FieldInfo")
            }
            if memberName == "GetMethod" && count == 2 && argumentTypeNames[0] == "System.Type" && argumentTypeNames[1] == "System.Reflection.MethodInfo" {
                return StaticCall("System.Reflection.Emit.TypeBuilder", memberName, Two("System.Type", "System.Reflection.MethodInfo"), "System.Reflection.MethodInfo")
            }
            if memberName == "GetConstructor" && count == 2 && argumentTypeNames[0] == "System.Type" && argumentTypeNames[1] == "System.Reflection.ConstructorInfo" {
                return StaticCall("System.Reflection.Emit.TypeBuilder", memberName, Two("System.Type", "System.Reflection.ConstructorInfo"), "System.Reflection.ConstructorInfo")
            }
        }

        if typeName == "Int32" || typeName == "int" {
            if memberName == "Parse" && count == 1 && argumentTypeNames[0] == "System.String" {
                return StaticCall("System.Int32", memberName, One("System.String"), "System.Int32")
            }
            if memberName == "TryParse" && count == 2 && argumentTypeNames[0] == "System.String" && argumentTypeNames[1] == "System.Int32&" {
                return StaticCall("System.Int32", memberName, Two("System.String", "System.Int32&"), "System.Boolean")
            }
        }

        if typeName == "Double" {
            if memberName == "Parse" && count == 2 && argumentTypeNames[0] == "System.String" && argumentTypeNames[1] == "System.Globalization.CultureInfo" {
                return StaticCall("System.Double", memberName, Two("System.String", "System.IFormatProvider"), "System.Double")
            }
            if memberName == "TryParse" && count == 3 && argumentTypeNames[0] == "System.String" && argumentTypeNames[1] == "System.Globalization.CultureInfo" && argumentTypeNames[2] == "System.Double&" {
                return StaticCall("System.Double", memberName, Three("System.String", "System.IFormatProvider", "System.Double&"), "System.Boolean")
            }
        }

        if (typeName == "String" || typeName == "System.String") && memberName == "Join" && count == 2 && argumentTypeNames[0] == "System.String" {
            if IsStringSequenceJoinArgument(argumentTypeNames[1]) {
                // `String.Join(sep, values)` over a `List<string>`/`IEnumerable<string>` binds the exact
                // `String.Join(String, IEnumerable<String>)` overload; a concrete List flows to the
                // enumerable parameter through the ordinary reference upcast (no cast instruction),
                // matching the legacy special-arm lowering byte for byte. Only owner spellings that
                // resolve to a runtime static owner are admitted — the lowercase `string` keyword is not
                // a resolvable external owner, so it stays with the legacy string owner instead of a
                // terminal ownership claim.
                return StaticCall("System.String", memberName, Two("System.String", "System.Collections.Generic.IEnumerable`1[System.String]"), "System.String")
            }
            joinElementTypeName := ""
            if TryGetGenericJoinElementTypeName(argumentTypeNames[1], out joinElementTypeName) {
                // Non-string element sequences have NO non-generic Join overload: `T[]`, `List<T>`,
                // `IEnumerable<T>`, `IReadOnlyList<T>`, and `IReadOnlyCollection<T>` over a supported
                // primitive value element all bind the generic `String.Join<T>(String,
                // IEnumerable<T>)` closed at that element (a value array is not covariant to
                // object[], so the params overload can never own these). Arrays and lists flow to the
                // enumerable parameter through the ordinary reference upcast, mirroring the string
                // row. T=Int32 reproduces the historical int row byte for byte.
                return GenericStaticCall("System.String", memberName, One(joinElementTypeName), Two("System.String", "System.Collections.Generic.IEnumerable`1[" + joinElementTypeName + "]"), "System.String")
            }
        }

        if typeName == "Decimal" || typeName == "decimal" {
            // The decimal-literal owner parses with the invariant Number style and reads the four
            // GetBits words to lower a `System.Decimal(int,int,int,bool,byte)` construction.
            if memberName == "TryParse" && count == 3 && argumentTypeNames[0] == "System.String" && argumentTypeNames[1] == "System.Globalization.CultureInfo" && argumentTypeNames[2] == "System.Decimal&" {
                return StaticCall("System.Decimal", memberName, Three("System.String", "System.IFormatProvider", "System.Decimal&"), "System.Boolean")
            }
            if memberName == "GetBits" && count == 1 && argumentTypeNames[0] == "System.Decimal" {
                return StaticCall("System.Decimal", memberName, One("System.Decimal"), "System.Int32[]")
            }
        }

        return NoCall()
    }

    static func IsReferenceIdentityArgumentType(typeName: string): bool {
        return typeName == "System.Object" || typeName == "System.Reflection.MethodInfo"
    }

    // A `List<string>` or `IEnumerable<string>` argument that flows to the exact
    // `String.Join(String, IEnumerable<String>)` overload. The incoming names are runtime
    // `FullName` values whose type argument is assembly-qualified (`[[System.String, ...]]`), so the
    // markers stop before the version to stay framework-version robust.
    static func IsStringSequenceJoinArgument(typeName: string): bool {
        return typeName.StartsWith("System.Collections.Generic.List`1[[System.String,", StringComparison.Ordinal) || typeName.StartsWith("System.Collections.Generic.IEnumerable`1[[System.String,", StringComparison.Ordinal)
    }

    // A `T[]`, `List<T>`, `IEnumerable<T>`, `IReadOnlyList<T>`, or `IReadOnlyCollection<T>` argument
    // whose element `T` is a supported primitive value type. The closure binds the generic
    // `String.Join<T>(String, IEnumerable<T>)` overload at that element; string sequences are owned
    // separately by the non-generic enumerable overload. The incoming names are runtime `FullName`
    // values whose element is assembly-qualified inside `[[...]]`, so parsing stops at the element's
    // own `FullName` (before its assembly/version) to stay framework-version robust.
    static func TryGetGenericJoinElementTypeName(typeName: string, out elementTypeName: string): bool {
        elementTypeName = ""
        candidate := ""
        if typeName.EndsWith("[]", StringComparison.Ordinal) {
            candidate = typeName.Substring(0, typeName.Length - 2)
        } else if IsGenericJoinSequenceOpen(typeName) {
            markerIndex := typeName.IndexOf("`1[[", StringComparison.Ordinal)
            if markerIndex < 0 {
                return false
            }

            afterMarker := typeName.Substring(markerIndex + 4)
            elementEnd := afterMarker.IndexOf(",", StringComparison.Ordinal)
            if elementEnd < 0 {
                return false
            }

            candidate = afterMarker.Substring(0, elementEnd)
        } else {
            return false
        }

        if IsGenericJoinElementTypeName(candidate) {
            elementTypeName = candidate
            return true
        }

        return false
    }

    // The closed generic collection definitions whose element flows to `IEnumerable<T>` for the
    // generic Join overload. The `` `1[[ `` marker guarantees an assembly-qualified element follows.
    static func IsGenericJoinSequenceOpen(typeName: string): bool {
        return typeName.StartsWith("System.Collections.Generic.List`1[[", StringComparison.Ordinal) || typeName.StartsWith("System.Collections.Generic.IEnumerable`1[[", StringComparison.Ordinal) || typeName.StartsWith("System.Collections.Generic.IReadOnlyList`1[[", StringComparison.Ordinal) || typeName.StartsWith("System.Collections.Generic.IReadOnlyCollection`1[[", StringComparison.Ordinal)
    }

    // The primitive value elements the generic Join owns. These are exactly the non-string primitive
    // value types the legacy emitter arm closed through `String.Join<T>`; string uses the non-generic
    // enumerable overload instead.
    static func IsGenericJoinElementTypeName(typeName: string): bool {
        return typeName == "System.Boolean" || typeName == "System.Char" || typeName == "System.SByte" || typeName == "System.Byte" || typeName == "System.Int16" || typeName == "System.UInt16" || typeName == "System.Int32" || typeName == "System.UInt32" || typeName == "System.Int64" || typeName == "System.UInt64" || typeName == "System.Single" || typeName == "System.Double"
    }

    static func GetInstanceCallPlan(receiverTypeName: string?, memberName: string, argumentTypeNames: string[]): ColumnarExternalCallPlan {
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
            if memberName == "GetProperty" && count == 2 && argumentTypeNames[0] == "System.String" && argumentTypeNames[1] == "System.Reflection.BindingFlags" {
                return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.PropertyInfo")
            }
            if memberName == "GetEvent" && count == 2 && argumentTypeNames[0] == "System.String" && argumentTypeNames[1] == "System.Reflection.BindingFlags" {
                return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.EventInfo")
            }
            if memberName == "GetMethods" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.MethodInfo[]")
            }
            // The filtered overload. Re-finding a member on a generic type DEFINITION means asking
            // for the declared methods regardless of visibility or staticness, which is the binding
            // mask's whole job; the unfiltered arm above answers public instance members only, so
            // it cannot stand in for this one.
            if memberName == "GetMethods" && count == 1 && argumentTypeNames[0] == "System.Reflection.BindingFlags" {
                return VirtualCall(receiver, memberName, One("System.Reflection.BindingFlags"), "System.Reflection.MethodInfo[]")
            }
            if memberName == "GetConstructors" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.ConstructorInfo[]")
            }
            if memberName == "GetType" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Type")
            }
            if memberName == "GetConstructor" && count == 1 && argumentTypeNames[0] == "System.Type[]" {
                return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.ConstructorInfo")
            }
            if memberName == "GetMethod" && count == 2 && argumentTypeNames[0] == "System.String" && argumentTypeNames[1] == "System.Type[]" {
                return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.MethodInfo")
            }
            if (memberName == "GetElementType" || memberName == "MakeArrayType" || memberName == "GetEnumUnderlyingType" || memberName == "GetGenericTypeDefinition" || memberName == "get_BaseType") && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Type")
            }
            if memberName == "MakeGenericType" && count == 1 && argumentTypeNames[0] == "System.Type[]" {
                return VirtualCall(receiver, memberName, argumentTypeNames, "System.Type")
            }
            if memberName == "GetGenericArguments" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Type[]")
            }
            if (memberName == "get_IsSZArray" || memberName == "get_IsValueType" || memberName == "get_IsEnum" || memberName == "get_IsByRef" || memberName == "get_IsGenericParameter" || memberName == "get_IsGenericType" || memberName == "get_IsGenericTypeDefinition" || memberName == "get_HasElementType" || memberName == "get_IsAbstract" || memberName == "get_IsInterface" || memberName == "get_IsByRefLike") && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Boolean")
            }
            if memberName == "get_GenericParameterPosition" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Int32")
            }
            if memberName == "get_DeclaringMethod" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.MethodBase")
            }
            if memberName == "get_AssemblyQualifiedName" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.String")
            }
            if memberName == "get_Assembly" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.Assembly")
            }
            if memberName == "IsAssignableFrom" && count == 1 && argumentTypeNames[0] == "System.Type" {
                return VirtualCall(receiver, memberName, One("System.Type"), "System.Boolean")
            }
        }

        if receiver == "System.Reflection.Emit.TypeBuilder" && memberName == "DefineMethod" && count == 4 && argumentTypeNames[0] == "System.String" && argumentTypeNames[1] == "System.Reflection.MethodAttributes" && argumentTypeNames[2] == "System.Type" && argumentTypeNames[3] == "System.Type[]" {
            return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.Emit.MethodBuilder")
        }

        if receiver == "System.Reflection.Emit.TypeBuilder" && memberName == "DefineConstructor" && count == 3 && argumentTypeNames[0] == "System.Reflection.MethodAttributes" && argumentTypeNames[1] == "System.Reflection.CallingConventions" && argumentTypeNames[2] == "System.Type[]" {
            return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.Emit.ConstructorBuilder")
        }

        if receiver == "System.Reflection.Emit.LocalBuilder" && memberName == "get_LocalType" && count == 0 {
            return VirtualCall(receiver, memberName, Empty(), "System.Type")
        }

        if receiver == "System.Reflection.PropertyInfo" && memberName == "GetValue" && count == 1 {
            return VirtualCall(receiver, memberName, One("System.Object"), "System.Object")
        }

        if receiver == "System.Reflection.FieldInfo" && memberName == "GetValue" && count == 1 {
            return VirtualCall(receiver, memberName, One("System.Object"), "System.Object")
        }

        if receiver == "System.Reflection.PropertyInfo" && memberName == "GetGetMethod" && count == 0 {
            return VirtualCall(receiver, memberName, Empty(), "System.Reflection.MethodInfo")
        }

        if receiver == "System.Reflection.PropertyInfo" && memberName == "get_SetMethod" && count == 0 {
            return VirtualCall(receiver, memberName, Empty(), "System.Reflection.MethodInfo")
        }

        if receiver == "System.Reflection.PropertyInfo" && memberName == "get_PropertyType" && count == 0 {
            return VirtualCall(receiver, memberName, Empty(), "System.Type")
        }

        if receiver == "System.Reflection.MethodInfo" && memberName == "MakeGenericMethod" && count == 1 && argumentTypeNames[0] == "System.Type[]" {
            return VirtualCall(receiver, memberName, argumentTypeNames, "System.Reflection.MethodInfo")
        }

        if receiver == "System.Reflection.ConstructorInfo" && memberName == "Invoke" && count == 1 && argumentTypeNames[0] == "System.Object[]" {
            return VirtualCall(receiver, memberName, One("System.Object[]"), "System.Object")
        }

        if receiver == "System.Reflection.Emit.DynamicMethod" {
            if memberName == "GetILGenerator" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.Emit.ILGenerator")
            }
            if memberName == "Invoke" && count == 2 && argumentTypeNames[0] == "System.Object" && argumentTypeNames[1] == "System.Object[]" {
                return VirtualCall(receiver, memberName, Two("System.Object", "System.Object[]"), "System.Object")
            }
        }

        if receiver == "System.Reflection.MethodInfo" && count == 0 {
            if memberName == "GetParameters" {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.ParameterInfo[]")
            }
            if memberName == "GetGenericArguments" {
                return VirtualCall(receiver, memberName, Empty(), "System.Type[]")
            }
            if memberName == "GetGenericMethodDefinition" {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.MethodInfo")
            }
            if memberName == "get_ReturnType" || memberName == "get_DeclaringType" {
                return VirtualCall(receiver, memberName, Empty(), "System.Type")
            }
            if memberName == "get_Name" {
                return VirtualCall(receiver, memberName, Empty(), "System.String")
            }
            if memberName == "get_IsStatic" || memberName == "get_IsAbstract" || memberName == "get_IsPublic" {
                return VirtualCall(receiver, memberName, Empty(), "System.Boolean")
            }
            if memberName == "get_IsGenericMethod" || memberName == "get_IsGenericMethodDefinition" {
                return VirtualCall(receiver, memberName, Empty(), "System.Boolean")
            }
            if memberName == "get_CallingConvention" {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.CallingConventions")
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
            if memberName == "get_CallingConvention" {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.CallingConventions")
            }
        }

        if receiver == "System.Reflection.FieldInfo" && count == 0 {
            if memberName == "get_FieldType" || memberName == "get_DeclaringType" {
                return VirtualCall(receiver, memberName, Empty(), "System.Type")
            }
            if memberName == "get_IsStatic" || memberName == "get_IsLiteral" || memberName == "get_IsPublic" {
                return VirtualCall(receiver, memberName, Empty(), "System.Boolean")
            }
        }

        // The event's own surface. `GetAddMethod`/`GetRemoveMethod` take the NON-PUBLIC opt-in
        // because an event's accessors may be private while the event itself is public, and the
        // subscription must still find them.
        if receiver == "System.Reflection.EventInfo" {
            if (memberName == "GetAddMethod" || memberName == "GetRemoveMethod") && count == 1 && argumentTypeNames[0] == "System.Boolean" {
                return VirtualCall(receiver, memberName, One("System.Boolean"), "System.Reflection.MethodInfo")
            }
            if (memberName == "get_EventHandlerType" || memberName == "get_DeclaringType") && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Type")
            }
            if memberName == "get_Name" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.String")
            }
        }

        if receiver == "System.Reflection.Assembly" {
            if memberName == "GetName" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Reflection.AssemblyName")
            }
            if memberName == "get_Location" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.String")
            }
            // Distinguishes a MetadataLoadContext assembly from a runtime one; the CLR-conversion
            // funnel's mixed-context guard is built on this answer.
            if memberName == "get_ReflectionOnly" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Boolean")
            }
            if memberName == "GetType" && count == 1 && argumentTypeNames[0] == "System.String" {
                return VirtualCall(receiver, memberName, One("System.String"), "System.Type")
            }
            if memberName == "GetExportedTypes" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Type[]")
            }
            // NOT interchangeable with GetExportedTypes. An extension-method scan must see the
            // INTERNAL static classes of a referenced assembly too: the exported surface answers a
            // strictly smaller set, so substituting it would silently drop candidates rather than
            // decline.
            if memberName == "GetTypes" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Type[]")
            }
        }

        if receiver == "System.Reflection.AssemblyName" && memberName == "get_FullName" && count == 0 {
            return VirtualCall(receiver, memberName, Empty(), "System.String")
        }

        if receiver == "System.Reflection.MetadataLoadContext" {
            if (memberName == "LoadFromAssemblyPath" || memberName == "LoadFromAssemblyName") && count == 1 && argumentTypeNames[0] == "System.String" {
                return VirtualCall(receiver, memberName, One("System.String"), "System.Reflection.Assembly")
            }
            if memberName == "Dispose" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Void")
            }
        }

        if receiver == "System.Reflection.ParameterInfo" {
            if memberName == "get_ParameterType" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Type")
            }
            if memberName == "get_IsOptional" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Boolean")
            }
            if memberName == "IsDefined" && count == 2 && argumentTypeNames[0] == "System.Type" && argumentTypeNames[1] == "System.Boolean" {
                return VirtualCall(receiver, memberName, Two("System.Type", "System.Boolean"), "System.Boolean")
            }
            if (memberName == "get_IsOut" || memberName == "get_IsIn") && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Boolean")
            }
            if memberName == "get_Name" && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.String")
            }
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

        if receiver == "System.IO.StreamReader" && memberName == "ReadToEndAsync" && count == 0 {
            return VirtualCall(receiver, memberName, Empty(), "System.Threading.Tasks.Task`1[System.String]")
        }

        if receiver == "System.IO.TextWriter" && memberName == "WriteLine" && count == 1 && argumentTypeNames[0] == "System.String" {
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
                return VirtualCall(receiver, memberName, Two("System.Type", "System.Boolean"), "System.Reflection.Emit.LocalBuilder")
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
            if (memberName == "BeginFinallyBlock" || memberName == "BeginFaultBlock" || memberName == "BeginExceptFilterBlock" || memberName == "EndExceptionBlock") && count == 0 {
                return VirtualCall(receiver, memberName, Empty(), "System.Void")
            }
            if memberName == "Emit" && count >= 1 && argumentTypeNames[0] == "System.Reflection.Emit.OpCode" {
                if count == 1 {
                    return VirtualCall(receiver, memberName, One("System.Reflection.Emit.OpCode"), "System.Void")
                }
                if count == 2 && IsSupportedEmitOperand(argumentTypeNames[1]) {
                    return VirtualCall(receiver, memberName, Two("System.Reflection.Emit.OpCode", argumentTypeNames[1]), "System.Void")
                }
            }
        }

        return NoCall()
    }

    static func IsSupportedEmitOperand(typeName: string): bool {
        return typeName == "System.Int32" || typeName == "System.Int16" || typeName == "System.Int64" || typeName == "System.Single" || typeName == "System.Double" || typeName == "System.String" || typeName == "System.Type" || typeName == "System.Reflection.Emit.LocalBuilder" || typeName == "System.Reflection.Emit.Label" || typeName == "System.Reflection.Emit.Label[]" || typeName == "System.Reflection.MethodInfo" || typeName == "System.Reflection.ConstructorInfo" || typeName == "System.Reflection.FieldInfo"
    }

    // The OpCodes allowlist, split into three family predicates: a single 120-clause `||` chain nests
    // one AST level per clause and overflows the legacy linter's 100-deep expression-visit guard.
    static func IsSupportedOpCodeMemberName(memberName: string): bool {
        return IsSupportedValueOpCodeMemberName(memberName) || IsSupportedComputeOpCodeMemberName(memberName) || IsSupportedObjectModelOpCodeMemberName(memberName)
    }

    // Constants, locals/arguments, and indirect loads.
    static func IsSupportedValueOpCodeMemberName(memberName: string): bool {
        return memberName == "Nop" || memberName == "Ldc_I4_M1" || memberName == "Ldc_I4_0" || memberName == "Ldc_I4_1" || memberName == "Ldc_I4_2" || memberName == "Ldc_I4_3" || memberName == "Ldc_I4_4" || memberName == "Ldc_I4_5" || memberName == "Ldc_I4_6" || memberName == "Ldc_I4_7" || memberName == "Ldc_I4_8" || memberName == "Ldc_I4" || memberName == "Ldc_I8" || memberName == "Ldc_R4" || memberName == "Ldc_R8" || memberName == "Dup" || memberName == "Ldstr" || memberName == "Ldtoken" || memberName == "Stloc" || memberName == "Ldloc" || memberName == "Ldloca" || memberName == "Ldarg" || memberName == "Ldarga" || memberName == "Ldind_I1" || memberName == "Ldind_U1" || memberName == "Ldind_I2" || memberName == "Ldind_U2" || memberName == "Ldind_I4" || memberName == "Ldind_U4" || memberName == "Ldind_I8" || memberName == "Ldind_R4" || memberName == "Ldind_R8" || memberName == "Ldind_Ref"
    }

    // Branches, calls, arithmetic, comparisons, and conversions.
    static func IsSupportedComputeOpCodeMemberName(memberName: string): bool {
        return memberName == "Br" || memberName == "Brfalse" || memberName == "Brtrue" || memberName == "Call" || memberName == "Callvirt" || memberName == "Newobj" || memberName == "Add" || memberName == "Sub" || memberName == "Mul" || memberName == "Div" || memberName == "Div_Un" || memberName == "Rem" || memberName == "Rem_Un" || memberName == "And" || memberName == "Or" || memberName == "Xor" || memberName == "Shl" || memberName == "Shr" || memberName == "Shr_Un" || memberName == "Add_Ovf" || memberName == "Add_Ovf_Un" || memberName == "Mul_Ovf" || memberName == "Mul_Ovf_Un" || memberName == "Sub_Ovf" || memberName == "Sub_Ovf_Un" || memberName == "Neg" || memberName == "Not" || memberName == "Ceq" || memberName == "Cgt" || memberName == "Cgt_Un" || memberName == "Clt" || memberName == "Clt_Un" || memberName == "Conv_I1" || memberName == "Conv_I2" || memberName == "Conv_I4" || memberName == "Conv_I8" || memberName == "Conv_R4" || memberName == "Conv_R8" || memberName == "Conv_U1" || memberName == "Conv_U2" || memberName == "Conv_U4" || memberName == "Conv_U8"
    }

    // Object model, fields, arrays, and body terminators/regions.
    static func IsSupportedObjectModelOpCodeMemberName(memberName: string): bool {
        return memberName == "Box" || memberName == "Castclass" || memberName == "Ldnull" || memberName == "Initobj" || memberName == "Ldfld" || memberName == "Ldflda" || memberName == "Stfld" || memberName == "Ldsfld" || memberName == "Newarr" || memberName == "Ldlen" || memberName == "Ldelem_U1" || memberName == "Ldelem_U2" || memberName == "Ldelem_I4" || memberName == "Ldelem_U4" || memberName == "Ldelem_I8" || memberName == "Ldelem_R4" || memberName == "Ldelem_R8" || memberName == "Ldelem_Ref" || memberName == "Ldelem" || memberName == "Stelem_I1" || memberName == "Stelem_I2" || memberName == "Stelem_I4" || memberName == "Stelem_I8" || memberName == "Stelem_R4" || memberName == "Stelem_R8" || memberName == "Stelem_Ref" || memberName == "Stelem" || memberName == "Pop" || memberName == "Ret" || memberName == "Throw" || memberName == "Isinst" || memberName == "Stsfld" || memberName == "Leave"
    }
    // Method-body opcodes (code-plan schema v4): the executor emits these when replaying a full
    // method body (iterator MoveNext/Dispose). Isinst/Stsfld carry Type/FieldInfo operands and
    // Leave carries a Label operand, all already supported emit operands; Throw takes no operand.

    static func StaticMember(kind: ColumnarExternalStaticMemberKind, declaringTypeName: string, memberName: string, valueTypeName: string): ColumnarExternalStaticMemberPlan {
        return new ColumnarExternalStaticMemberPlan(true, kind, ExactTypeIdentity(declaringTypeName), memberName, ExactTypeIdentity(valueTypeName))
    }

    static func StaticMemberFromTypes(kind: ColumnarExternalStaticMemberKind, declaringType: Type, memberName: string, valueType: Type): ColumnarExternalStaticMemberPlan {
        declaringIdentity := declaringType.get_AssemblyQualifiedName() ?? ""
        valueIdentity := valueType.get_AssemblyQualifiedName() ?? ""
        if declaringIdentity.Length == 0 || valueIdentity.Length == 0 {
            return NoStaticMember()
        }
        return new ColumnarExternalStaticMemberPlan(true, kind, declaringIdentity, memberName, valueIdentity)
    }

    static func ClosedByteGenericType(fullName: string): Type {
        definition := Type.GetType(fullName)
        if definition == null {
            throw new InvalidOperationException("Required runtime generic type '" + fullName + "' was not found.")
        }
        arguments := new Type[](1)
        arguments[0] = typeof(byte)
        return definition.MakeGenericType(arguments)
    }

    static func NoStaticMember(): ColumnarExternalStaticMemberPlan {
        return new ColumnarExternalStaticMemberPlan(false, ColumnarExternalStaticMemberKind.None, "", "", "")
    }

    static func VirtualCall(declaringTypeName: string, memberName: string, parameterTypeNames: string[], returnTypeName: string): ColumnarExternalCallPlan {
        exactParameterTypeNames := new string[](parameterTypeNames.Length)
        i := 0
        while i < parameterTypeNames.Length {
            exactParameterTypeNames[i] = ExactTypeIdentity(parameterTypeNames[i])
            i = i + 1
        }

        return new ColumnarExternalCallPlan(true, ColumnarExternalCallKind.CallVirtual, ExactTypeIdentity(declaringTypeName), memberName, exactParameterTypeNames, ExactTypeIdentity(returnTypeName))
    }

    static func StaticCall(declaringTypeName: string, memberName: string, parameterTypeNames: string[], returnTypeName: string): ColumnarExternalCallPlan {
        exactParameterTypeNames := new string[](parameterTypeNames.Length)
        i := 0
        while i < parameterTypeNames.Length {
            exactParameterTypeNames[i] = ExactTypeIdentity(parameterTypeNames[i])
            i = i + 1
        }

        return new ColumnarExternalCallPlan(true, ColumnarExternalCallKind.Call, ExactTypeIdentity(declaringTypeName), memberName, exactParameterTypeNames, ExactTypeIdentity(returnTypeName))
    }

    // A static call that CLOSES a generic method definition with plan-pinned type arguments
    // (`String.Join<int>(String, IEnumerable<Int32>)`). The host still may not substitute, score,
    // or infer: the plan names the exact type arguments and the exact CLOSED signature, and the
    // runtime resolver validates the closure against those identities member-for-member.
    static func GenericStaticCall(declaringTypeName: string, memberName: string, typeArgumentNames: string[], parameterTypeNames: string[], returnTypeName: string): ColumnarExternalCallPlan {
        plan := StaticCall(declaringTypeName, memberName, parameterTypeNames, returnTypeName)
        exactTypeArgumentNames := new string[](typeArgumentNames.Length)
        i := 0
        while i < typeArgumentNames.Length {
            exactTypeArgumentNames[i] = ExactTypeIdentity(typeArgumentNames[i])
            i = i + 1
        }

        plan.TypeArgumentNames = exactTypeArgumentNames
        return plan
    }

    static func NoCall(): ColumnarExternalCallPlan {
        return new ColumnarExternalCallPlan(false, ColumnarExternalCallKind.None, "", "", Empty(), "")
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

    static func Three(first: string, second: string, third: string): string[] {
        values := new string[](3)
        values[0] = first
        values[1] = second
        values[2] = third
        return values
    }

    static func ExactTypeIdentity(fullName: string): string {
        if fullName == "System.Threading.Tasks.Task`1[System.String]" || (fullName.StartsWith("System.Collections.Generic.IEnumerable`1[", StringComparison.Ordinal) && fullName.EndsWith("]", StringComparison.Ordinal)) {
            // Closed BCL generics must carry their fully version-qualified identity: the runtime
            // exact-identity check compares the assembly-qualified name (with the type argument's
            // own assembly and version), so a short `[System.String]`/`[System.Int64]` spelling would
            // never match. Any `IEnumerable<T>` element resolvable from the default context (every
            // supported Join element is a CoreLib primitive) closes to its full identity here.
            runtimeType := Type.GetType(fullName + ", System.Private.CoreLib")
            if runtimeType == null {
                throw new InvalidOperationException("Required runtime generic type was unavailable.")
            }
            identity := runtimeType.get_AssemblyQualifiedName()
            if identity == null || identity.Length == 0 {
                throw new InvalidOperationException("Required runtime generic type identity was unavailable.")
            }
            return identity
        }
        if fullName == "System.Reflection.MetadataLoadContext" || fullName == "System.Reflection.PathAssemblyResolver" || fullName == "System.Reflection.MetadataAssemblyResolver" {
            return fullName + ", System.Reflection.MetadataLoadContext"
        }
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
