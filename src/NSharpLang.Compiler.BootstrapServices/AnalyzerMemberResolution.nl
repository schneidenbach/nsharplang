namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

// WHAT A MEMBER NAME RESOLVES TO ON A DECLARED SHAPE — the source half of member resolution, beside
// the declaration context that answers WHICH shape a type has.
//
// The declaration context finds the member; this owner decides what its TYPE is: a single function
// type or a method group for a declared `func`, the inherited `object` surface for a source type,
// the SoA intrinsics a table exposes, and which column a name denotes. Every answer is a value; this
// owner reports nothing and records nothing.
//
// WHAT IS NOT HERE YET. `ResolveMember` itself — the dispatcher these answers hang off — cannot
// move at the pinned toolset: its reflection arm resolves a .NET EVENT, and
// `System.Reflection.EventInfo` is not on the columnar surface. The row is staged; see
// `systems-language-closeout/phase-b-member-resolution-contracts.md`.
public class AnalyzerMemberResolution {

    functionTypeFactory: AnalyzerFunctionTypeFactory

    constructor(functionTypes: AnalyzerFunctionTypeFactory) {
        functionTypeFactory = functionTypes
    }

    // A DECLARED `func` member's type. ONE match is that function's type; SEVERAL are a method
    // group, and overload resolution chooses later.
    //
    // THE ALL-OR-NOTHING GUARD IS THE POINT, AND IT IS NOT A NULL CHECK. A declared member whose
    // recorded arity arrays disagree with its recorded counts is not a member this owner can build a
    // signature from — and if ANY overload is in that state the whole NAME answers nothing, rather
    // than a method group silently missing one of its overloads. A partial group would bind a call
    // to the wrong overload with no diagnostic at all.
    public func ResolveDeclaredFunctionMember(
        members: DeclaredMemberInfo[],
        memberName: string,
        substitution: Dictionary<string, TypeInfo>?,
        declarationOwner: TypeInfo?): TypeInfo? {
        matching := new List<DeclaredMemberInfo>()
        index := 0
        while index < members.Length {
            candidate := members[index]
            if candidate.Kind == DeclaredMemberKind.Function && candidate.Name == memberName {
                matching.Add(candidate)
            }
            index = index + 1
        }

        if matching.Count == 0 {
            return null
        }

        resolvableIndex := 0
        while resolvableIndex < matching.Count {
            if !CanResolveFunctionMemberFromTypeInfo(matching[resolvableIndex]) {
                return null
            }
            resolvableIndex = resolvableIndex + 1
        }

        functionTypes := new List<FunctionTypeInfo>()
        buildIndex := 0
        while buildIndex < matching.Count {
            functionTypes.Add(
                functionTypeFactory.CreateFromDeclaredMember(
                    matching[buildIndex], substitution, declarationOwner))
            buildIndex = buildIndex + 1
        }

        if functionTypes.Count == 1 {
            return functionTypes[0]
        }

        return NSharpMethodGroupInfoFactory.FromFunctions(functionTypes)
    }

    // The recorded shape is self-consistent: the arrays are as long as the counts say, and the
    // required-parameter count is a real prefix of the parameter list.
    public static func CanResolveFunctionMemberFromTypeInfo(member: DeclaredMemberInfo): bool {
        return member.TypeParameters.Length == member.TypeParameterCount
            && member.RequiredParameterCount >= 0
            && member.RequiredParameterCount <= member.ParameterCount
            && member.ParameterNames.Length == member.ParameterCount
            && member.ParameterTypes.Length == member.ParameterCount
            && member.ParameterModifiers.Length == member.ParameterCount
    }

    // EVERY SOURCE TYPE INHERITS `object`, AND THIS IS THAT SURFACE. A source declaration names no
    // base type of its own, so the members `object` contributes — `ToString`, `Equals`,
    // `GetHashCode`, `GetType` — are resolved against the runtime type directly rather than through
    // any declared shape. Instance members only: a static `object` member is not inherited.
    //
    // THE PROBE ORDER IS PROPERTY, THEN FIELD, THEN METHOD, and the method arm distinguishes a
    // single method from a group because `Equals` is overloaded on `object` and `ToString` is not.
    // Accessor methods are excluded by the property arm answering first, not by a name test.
    public static func TryResolveSourceObjectMember(memberName: string, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown
        flags := BindingFlags.Public | BindingFlags.Instance
        objectType := typeof(object)

        property := objectType.GetProperty(memberName, flags)
        if property != null {
            memberType = NullabilityMetadataReflection.ConvertProperty(property)
            return true
        }

        field := objectType.GetField(memberName, flags)
        if field != null {
            memberType = NullabilityMetadataReflection.ConvertField(field)
            return true
        }

        methods := objectType.GetMethods(flags)
        matching := new List<MethodInfo>()
        index := 0
        while index < methods.Length {
            method := methods[index]
            if method.get_Name() == memberName && !method.get_IsSpecialName() {
                matching.Add(method)
            }
            index = index + 1
        }

        if matching.Count == 1 {
            single := matching[0]
            memberType = new ReflectionMethodInfo(single, single.get_Name() + "(...)")
            return true
        }

        if matching.Count > 1 {
            first := matching[0]
            memberType = new ReflectionMethodGroupInfo(matching.ToArray(), first.get_Name() + "(...)")
            return true
        }

        return false
    }

    // Which COLUMN a name denotes on a SoA record, or nothing. Column names are matched exactly:
    // a table's columns are its declared fields and nothing else answers for them.
    public static func TryGetSoaColumn(
        declaration: SoaRecordDeclarationInfo,
        name: string): SoaColumnInfo? {
        index := 0
        while index < declaration.Columns.Count {
            column := declaration.Columns[index]
            if column.Name == name {
                return column
            }
            index = index + 1
        }

        return null
    }

    // THE SoA TABLE'S INTRINSIC OPERATIONS. A table is a value view, not a class, so `add`, `clear`,
    // `ensureCapacity` and `copyRow` have no declaration anywhere to resolve against — their
    // signatures are synthesised here and exist nowhere else. The three arities are spelled out
    // rather than defaulted because the intrinsics are a closed set of exactly these shapes.
    public static func CreateSoaIntrinsic(syntheticName: string, returnType: TypeInfo): FunctionTypeInfo {
        result := new FunctionTypeInfo()
        result.SyntheticName = syntheticName
        result.ParameterNames = new List<string>()
        result.ParameterTypes = new List<TypeInfo>()
        result.ReturnType = returnType
        return result
    }

    public static func CreateSoaIntrinsicWithParameter(
        syntheticName: string,
        returnType: TypeInfo,
        parameterName: string,
        parameterType: TypeInfo): FunctionTypeInfo {
        names := new List<string>()
        names.Add(parameterName)
        types := new List<TypeInfo>()
        types.Add(parameterType)

        result := new FunctionTypeInfo()
        result.SyntheticName = syntheticName
        result.ParameterNames = names
        result.ParameterTypes = types
        result.ReturnType = returnType
        return result
    }

    public static func CreateSoaIntrinsicWithTwoParameters(
        syntheticName: string,
        returnType: TypeInfo,
        firstName: string,
        firstType: TypeInfo,
        secondName: string,
        secondType: TypeInfo): FunctionTypeInfo {
        names := new List<string>()
        names.Add(firstName)
        names.Add(secondName)
        types := new List<TypeInfo>()
        types.Add(firstType)
        types.Add(secondType)

        result := new FunctionTypeInfo()
        result.SyntheticName = syntheticName
        result.ParameterNames = names
        result.ParameterTypes = types
        result.ReturnType = returnType
        return result
    }
}
