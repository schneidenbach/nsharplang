namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Reflection


// WHAT A REFLECTED TYPE READS AS, IN THE TWO SPELLINGS `nlc query doc` NEEDS.
//
// A doc answer names a type twice and the two names are NOT the same string. One is for a HUMAN —
// `List<string>`, `int`, `string[]`, `Environment.SpecialFolder` — and one is for the XML
// documentation file, whose member keys are the ECMA-334 doc-comment ids the C# compiler emits:
// `System.Collections.Generic.List{System.String}`, `System.Int32@`, `T:System.Environment.SpecialFolder`.
// Both are read off the same `Type`, both recurse through the same element and argument walks, and
// mixing them up produces an answer that looks right and finds no documentation at all.
//
// EVERY DECISION IN THIS FILE IS AN ORDER OF CHECKS, AND THE ORDER IS THE POLICY. A generic
// PARAMETER is answered before anything else because `T` has no full name to look a built-in up by;
// a BUILT-IN alias wins over the generic and array walks because `int` is spelled `System.Int32`
// and would otherwise render as `Int32`; and on the doc-id side by-ref precedes pointer precedes
// array precedes generic parameter precedes generic, because a `ref int[]` is a by-ref BEFORE it is
// an array and the id it needs is `System.Int32[]@`.
//
// THE TEXT ITSELF IS NOT DECIDED HERE. Every arm ends in a `DocQueryKernels` speller, so this file
// owns WHICH question a `Type` is asked and in WHAT ORDER, and the kernels own how the answer is
// written. The two halves were already split that way; what moved is the half that reads metadata.
//
// THE ELEMENT-TYPE GUARDS ARE NOT DEFENSIVE PADDING. The CLR guarantees `GetElementType()` is
// non-null exactly when `IsArray`, `IsByRef` or `IsPointer` holds, so the deleted C# wrote `!` and
// would have thrown on a violation. Answering the un-decorated name instead is the same result on
// every input the CLR can produce and is not a crash on any input it cannot.
class DocQueryReflectionFacts {

    // THE HUMAN SPELLING. Generic parameter first (a `T` has no full name), then the built-in alias
    // (`System.Int32` must read as `int`, not `Int32`), then the generic and array walks, then the
    // bare name with its arity suffix stripped.
    static func FormatType(reflectionType: Type): string {
        if reflectionType.get_IsGenericParameter() {
            return reflectionType.get_Name()
        }

        builtinName := DocQueryKernels.FormatBuiltinTypeName(reflectionType.get_FullName())
        if builtinName != null {
            return builtinName
        }

        if reflectionType.get_IsGenericType() {
            arguments := reflectionType.GetGenericArguments()
            formattedArguments := new string[](arguments.Length)
            argumentIndex := 0
            while argumentIndex < arguments.Length {
                formattedArguments[argumentIndex] = FormatType(arguments[argumentIndex])
                argumentIndex = argumentIndex + 1
            }

            return DocQueryKernels.FormatGenericTypeName(reflectionType.get_Name(), formattedArguments)
        }

        if reflectionType.get_IsArray() {
            arrayElementType := reflectionType.GetElementType()
            if arrayElementType != null {
                return DocQueryKernels.FormatArrayTypeName(FormatType(arrayElementType))
            }
        }

        return DocQueryKernels.StripGenericArity(reflectionType.get_Name())
    }

    // THE QUALIFIED SPELLING, WHICH IS NOT THE FULL NAME. A nested type is rendered through its
    // DECLARING type rather than through the CLR's `Outer+Inner`, so `Environment.SpecialFolder`
    // reads the way a user would write it; a top-level type is rendered through its namespace.
    static func FormatQualifiedType(reflectionType: Type): string {
        if reflectionType.get_IsGenericParameter() {
            return reflectionType.get_Name()
        }

        declaringType := reflectionType.get_DeclaringType()
        if reflectionType.get_IsNested() && declaringType != null {
            return DocQueryKernels.FormatNestedQualifiedTypeName(FormatQualifiedType(declaringType), FormatTypeName(reflectionType))
        }

        return DocQueryKernels.FormatQualifiedTypeName(reflectionType.get_Namespace(), FormatTypeName(reflectionType))
    }

    // THE ONE PLACE A DEFINITION AND A CONSTRUCTION DIVERGE. `List<>` shows its PARAMETER names
    // (`List<T>`) while `List<string>` shows its ARGUMENTS formatted (`List<string>`), so the same
    // walk cannot serve both and the definition test is what picks.
    static func FormatTypeName(reflectionType: Type): string {
        name := DocQueryKernels.StripGenericArity(reflectionType.get_Name())
        if !reflectionType.get_IsGenericType() {
            return name
        }

        arguments := reflectionType.GetGenericArguments()
        isDefinition := reflectionType.get_IsGenericTypeDefinition()
        formattedArguments := new string[](arguments.Length)
        argumentIndex := 0
        while argumentIndex < arguments.Length {
            argument := arguments[argumentIndex]
            if isDefinition {
                formattedArguments[argumentIndex] = argument.get_Name()
            } else {
                formattedArguments[argumentIndex] = FormatType(argument)
            }

            argumentIndex = argumentIndex + 1
        }

        return DocQueryKernels.FormatGenericTypeName(name, formattedArguments)
    }

    // A CALLABLE'S ONE-LINE SIGNATURE. A constructor is named after its DECLARING type rather than
    // after `.ctor`, which is why the declaring name is read here and not left to the speller.
    static func FormatMethodSignature(method: MethodBase): string {
        parameters := method.GetParameters()
        parameterNames := new string[](parameters.Length)
        parameterTypeNames := new string[](parameters.Length)
        parameterIndex := 0
        while parameterIndex < parameters.Length {
            parameter := parameters[parameterIndex]
            parameterNames[parameterIndex] = parameter.get_Name() ?? ""
            parameterTypeNames[parameterIndex] = FormatType(parameter.get_ParameterType())
            parameterIndex = parameterIndex + 1
        }

        declaringType := method.get_DeclaringType()
        declaringTypeName: string? = null
        if declaringType != null {
            declaringTypeName = declaringType.get_Name()
        }

        name := DocQueryKernels.GetMethodSignatureName(method.get_Name(), declaringTypeName, method is ConstructorInfo)
        return DocQueryKernels.FormatMethodSignature(name, parameterNames, parameterTypeNames)
    }

    // THE PARAMETER LIST ON ITS OWN, which a member row shows beside its name.
    static func FormatParameters(method: MethodBase): string {
        parameters := method.GetParameters()
        parameterNames := new string[](parameters.Length)
        parameterTypeNames := new string[](parameters.Length)
        parameterIndex := 0
        while parameterIndex < parameters.Length {
            parameter := parameters[parameterIndex]
            parameterNames[parameterIndex] = parameter.get_Name() ?? ""
            parameterTypeNames[parameterIndex] = FormatType(parameter.get_ParameterType())
            parameterIndex = parameterIndex + 1
        }

        return DocQueryKernels.FormatParameterList(parameterNames, parameterTypeNames)
    }

    // THE DOC-ID SPELLING, WHOSE ORDER IS LOAD-BEARING. A `ref int[]` is a BY-REF first and an
    // array second, and its id is `System.Int32[]@` — reversing the first two arms produces
    // `System.Int32@[]`, which matches no member in any XML file.
    static func FormatTypeForDocId(reflectionType: Type): string {
        if reflectionType.get_IsByRef() {
            byRefElementType := reflectionType.GetElementType()
            if byRefElementType != null {
                return DocQueryKernels.FormatByRefTypeDocId(FormatTypeForDocId(byRefElementType))
            }
        }

        if reflectionType.get_IsPointer() {
            pointerElementType := reflectionType.GetElementType()
            if pointerElementType != null {
                return DocQueryKernels.FormatPointerTypeDocId(FormatTypeForDocId(pointerElementType))
            }
        }

        if reflectionType.get_IsArray() {
            arrayElementType := reflectionType.GetElementType()
            if arrayElementType != null {
                return DocQueryKernels.FormatArrayTypeDocId(FormatTypeForDocId(arrayElementType), reflectionType.GetArrayRank())
            }
        }

        // A TYPE's parameter and a METHOD's parameter take different prefixes, and the position is
        // the only identity a parameter has in a doc id at all — so which prefix it takes is decided
        // by whether a method declared it, and nothing else about it is written down.
        if reflectionType.get_IsGenericParameter() {
            return DocQueryKernels.FormatGenericParameterDocId(reflectionType.get_DeclaringMethod() != null, reflectionType.get_GenericParameterPosition())
        }

        if reflectionType.get_IsGenericType() {
            genericType := reflectionType
            if !reflectionType.get_IsGenericTypeDefinition() {
                genericType = reflectionType.GetGenericTypeDefinition()
            }

            arguments := reflectionType.GetGenericArguments()
            parameterTypeDocIds := new string[](arguments.Length)
            argumentIndex := 0
            while argumentIndex < arguments.Length {
                parameterTypeDocIds[argumentIndex] = FormatTypeForDocId(arguments[argumentIndex])
                argumentIndex = argumentIndex + 1
            }

            return DocQueryKernels.FormatGenericTypeDocId(genericType.get_FullName(), parameterTypeDocIds)
        }

        return DocQueryKernels.FormatNamedTypeDocId(reflectionType.get_FullName(), reflectionType.get_Name())
    }

    // A CALLABLE'S DOC-ID, whose parameter list is the doc-id spelling and NOT the human one.
    static func GetMethodDocId(method: MethodBase): string {
        parameters := method.GetParameters()
        parameterTypeDocIds := new string[](parameters.Length)
        parameterIndex := 0
        while parameterIndex < parameters.Length {
            parameter := parameters[parameterIndex]
            parameterTypeDocIds[parameterIndex] = FormatTypeForDocId(parameter.get_ParameterType())
            parameterIndex = parameterIndex + 1
        }

        memberName := DocQueryKernels.GetMethodDocMemberName(method.get_Name(), method is ConstructorInfo)
        declaringType := method.get_DeclaringType()
        declaringTypeFullName: string? = null
        if declaringType != null {
            declaringTypeFullName = declaringType.get_FullName()
        }

        return DocQueryKernels.GetMethodDocId(declaringTypeFullName, memberName, parameterTypeDocIds)
    }

    // WHICH OF THE FIVE WORDS A TYPE IS. The five predicates are read here and ranked by the
    // kernel, because the ranking is where `enum` beating `struct` lives.
    static func GetTypeKind(reflectionType: Type): string {
        return DocQueryKernels.GetReflectionTypeKind(reflectionType.get_IsEnum(), reflectionType.get_IsInterface(), reflectionType.get_IsValueType(), reflectionType.get_IsAbstract(), reflectionType.get_IsSealed())
    }

    // WHAT A TYPE INHERITS AND IMPLEMENTS, as one list. The base type is passed twice — once as its
    // FULL name, which is how the kernel decides whether `System.Object` is worth showing, and once
    // as its DISPLAY name, which is what a reader sees.
    static func GetBaseTypes(reflectionType: Type): string[] {
        baseType := reflectionType.get_BaseType()
        baseTypeFullName: string? = null
        baseTypeDisplayName: string? = null
        if baseType != null {
            baseTypeFullName = baseType.get_FullName()
            baseTypeDisplayName = FormatType(baseType)
        }

        interfaces := reflectionType.GetInterfaces()
        interfaceDisplayNames := new string[](interfaces.Length)
        interfaceIndex := 0
        while interfaceIndex < interfaces.Length {
            interfaceDisplayNames[interfaceIndex] = FormatType(interfaces[interfaceIndex])
            interfaceIndex = interfaceIndex + 1
        }

        return DocQueryKernels.FormatBaseTypeList(baseTypeFullName, baseTypeDisplayName, interfaceDisplayNames)
    }
}
