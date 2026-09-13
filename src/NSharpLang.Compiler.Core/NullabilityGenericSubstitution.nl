namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection


// A SUBSTITUTED TYPE PARAMETER TAKES THE TYPE ARGUMENT'S NULLABILITY, NOT `NullabilityInfoContext`'S.
//
// `Lazy<T>.Value`, `Task<T>.Result`, `Tuple<T1, T2>.Item1` and `Predicate<T>.Invoke(T)` are all
// declared with a BARE type parameter, and `NullabilityInfoContext` answers `Nullable` for every one
// of them — measured, on the CLOSED instantiation as well as on the open definition. It has to: an
// unconstrained `T` may be instantiated with a nullable type, so without knowing the ARGUMENT the
// most it can say is "maybe". The compiler DOES know the argument, so it must not take that answer:
// `Lazy<string>.Value` is `string`, and reporting NL905 "`docQuery.Value` is maybe-null" for it is a
// diagnostic about correct code.
//
// C#'s rule is the substitution's: the substituted position's nullability is the type ARGUMENT's,
// unless the MEMBER annotated the position itself. `Lazy<T>.Value` is `T` and follows the argument;
// `List<T>.Find` returns `T?` and is maybe-null whatever the argument is. In metadata that
// annotation is `NullableAttribute(2)` on the member position (measured: `List<>.Find`'s return
// parameter carries it, `Stack<>.Peek`'s does not), and `[MaybeNull]` / `[NotNull]` are read
// separately by the flow-attribute pass that already exists.
//
// This owner answers the two facts that decision needs, and nothing else: whether the position is a
// substituted type parameter, and whether the member annotated it nullable. It reports nothing,
// records nothing, and never decides a TYPE — only a read state.
//
// FINDING THE OPEN SPELLING IS THE WHOLE JOB. A member read off a CONSTRUCTED generic already has
// its type substituted by the CLR, so `Lazy<string>.Value` presents as `System.String` and the fact
// that it was written `T` is only visible on the DEFINITION. The counterpart is looked up on
// `DeclaringType`'s definition — the DECLARING type, not the receiver, so an inherited member
// resolves against the base that declares it — and matched by name plus the shape that can
// distinguish two members with that name. A lookup that finds nothing answers with the CLOSED type,
// which is exactly the old behaviour.
class NullabilityGenericSubstitution {
    static func MemberFlags(): BindingFlags {
        return BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static
    }

    // The definition of the type this member is DECLARED on, when that type is a constructed generic
    // and the definition is therefore where the member's type is spelled with type PARAMETERS. Null
    // when there is nothing to substitute — a non-generic type, or an open definition already.
    static func DeclaringDefinition(declaringType: Type?): Type? {
        if declaringType == null {
            return null
        }

        if !declaringType.get_IsGenericType() {
            return null
        }

        if declaringType.get_IsGenericTypeDefinition() {
            return null
        }

        return declaringType.GetGenericTypeDefinition()
    }

    // A PROPERTY'S DECLARED TYPE AS ITS DEFINITION SPELLS IT. Indexers are matched on their index
    // ARITY as well as their name, because a type may declare several and they are all called
    // `Item`.
    static func OpenPropertyType(property: PropertyInfo): Type {
        declared := property.get_PropertyType()
        definition := DeclaringDefinition(property.get_DeclaringType())
        if definition == null {
            return declared
        }

        indexCount := property.GetIndexParameters().Length
        candidates := definition.GetProperties(MemberFlags())
        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            if candidate.get_Name() == property.get_Name() && candidate.GetIndexParameters().Length == indexCount {
                return candidate.get_PropertyType()
            }

            index = index + 1
        }

        return declared
    }

    static func OpenFieldType(field: FieldInfo): Type {
        declared := field.get_FieldType()
        definition := DeclaringDefinition(field.get_DeclaringType())
        if definition == null {
            return declared
        }

        candidate := definition.GetField(field.get_Name(), MemberFlags())
        if candidate == null {
            return declared
        }

        return candidate.get_FieldType()
    }

    // A PARAMETER'S — OR A RETURN'S — DECLARED TYPE AS ITS DEFINITION SPELLS IT. A return parameter's
    // `Position` is -1 and that is how the two are told apart.
    //
    // THERE ARE TWO SUBSTITUTIONS AND BOTH HAVE TO BE UNDONE. A method may be closed over its OWN
    // type parameters (`Enumerable.FirstOrDefault<string>`, whose definition spells the return
    // `TSource?`) and it may be declared on a closed generic TYPE (`List<string>.Find`, whose
    // definition spells it `T?`). The method definition is taken first because it is the cheaper and
    // exact one — positions align — and the declaring type's definition second.
    //
    // Methods may be overloaded, so the counterpart on a type definition is matched on name AND
    // parameter count; a tie between two overloads that differ only in parameter TYPES cannot be
    // resolved from the closed side without re-doing binding, so an ambiguous name answers with the
    // closed type rather than guessing. A CONSTRUCTOR is matched the same way.
    static func OpenParameterType(parameter: ParameterInfo): Type {
        declared := parameter.get_ParameterType()
        method := parameter.get_Member() as MethodInfo
        if method != null {
            return OpenMethodPositionType(method, parameter, declared)
        }

        constructor := parameter.get_Member() as ConstructorInfo
        if constructor != null {
            return OpenConstructorPositionType(constructor, parameter, declared)
        }

        return declared
    }

    static func OpenMethodPositionType(method: MethodInfo, parameter: ParameterInfo, declared: Type): Type {
        open := method
        if method.get_IsGenericMethod() && !method.get_IsGenericMethodDefinition() {
            open = method.GetGenericMethodDefinition()
        }

        definition := DeclaringDefinition(open.get_DeclaringType())
        if definition != null {
            parameterCount := open.GetParameters().Length
            candidates := definition.GetMethods(MemberFlags())
            found: MethodInfo? = null
            matches := 0
            index := 0
            while index < candidates.Length {
                candidate := candidates[index]
                if candidate.get_Name() == open.get_Name() && candidate.GetParameters().Length == parameterCount {
                    found = candidate
                    matches = matches + 1
                }

                index = index + 1
            }

            if matches == 1 && found != null {
                open = found
            }
        }

        if open == method {
            return declared
        }

        if parameter.get_Position() < 0 {
            return open.get_ReturnType()
        }

        return PositionType(open.GetParameters(), parameter.get_Position(), declared)
    }

    static func OpenConstructorPositionType(constructor: ConstructorInfo, parameter: ParameterInfo, declared: Type): Type {
        definition := DeclaringDefinition(constructor.get_DeclaringType())
        if definition == null {
            return declared
        }

        parameterCount := constructor.GetParameters().Length
        candidates := definition.GetConstructors(MemberFlags())
        found: ConstructorInfo? = null
        matches := 0
        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            if candidate.GetParameters().Length == parameterCount {
                found = candidate
                matches = matches + 1
            }

            index = index + 1
        }

        if matches != 1 || found == null {
            return declared
        }

        return PositionType(found.GetParameters(), parameter.get_Position(), declared)
    }

    static func PositionType(parameters: ParameterInfo[], position: int, declared: Type): Type {
        if position < 0 || position >= parameters.Length {
            return declared
        }

        return parameters[position].get_ParameterType()
    }

    // IS THIS POSITION A TYPE PARAMETER THE INSTANTIATION SUBSTITUTED? A by-ref shell is transparent:
    // `ref T` is still `T` for this question, exactly as the conversion reads through it.
    static func IsTypeParameterPosition(openType: Type?): bool {
        if openType == null {
            return false
        }

        effective := openType
        if openType.get_IsByRef() {
            element := openType.GetElementType()
            if element != null {
                effective = element
            }
        }

        return effective.get_IsGenericParameter()
    }

    // DID THE MEMBER ANNOTATE THE POSITION `T?`?
    //
    // C# writes that annotation in TWO places and both have to be read, which is the whole reason
    // this is a walk rather than one attribute test:
    //
    //   * `NullableAttribute` on the POSITION itself — a single byte, 2 for annotated, 1 for not, 0
    //     for oblivious. `List<T>.Find`'s return carries it (measured); `Stack<T>.Peek`'s does not.
    //   * `NullableContextAttribute`, the compiler's SIZE OPTIMISATION: a member, a type or a module
    //     may declare the default byte for every position under it that has none of its own.
    //     `Enumerable.FirstOrDefault<TSource>`'s return has NO attributes at all and is still
    //     `TSource?`, because the METHOD carries `NullableContextAttribute(2)` while the enclosing
    //     `Enumerable` carries `NullableContextAttribute(1)` (measured). Reading only the position
    //     would say `First` and `FirstOrDefault` mean the same thing.
    //
    // The position wins over the context, and the nearest context wins over the outer one. Nothing
    // found at all is 0 — oblivious — which is not "annotated nullable": the substituted argument
    // decides, exactly as it does for an unannotated `T`.
    //
    // The byte comparisons are against BOXED bytes, because under a MetadataLoadContext the
    // argument's own `ArgumentType` is a projected `System.Byte` that is not `typeof(byte)` while
    // `Value` is still a live boxed CLR byte — the same insight the `[NotNullWhen(...)]` reader is
    // written around.
    // `[MaybeNullWhen(...)]` IS DELIBERATELY NOT READ HERE, AND THAT IS THE WHOLE SPLIT. A TYPE says
    // what a value IS; `[MaybeNullWhen(false)]` says what it BECOMES on one branch. `Dictionary<K,
    // V>.TryGetValue` declares `out TValue value`, so with a `Dictionary<string, Entry>` receiver the
    // parameter's type is `Entry` — non-null — and the false branch's maybe-null is a POSTCONDITION
    // that `AnalyzerNullabilityPostconditions` files against the call. Folding the attribute into the
    // TYPE here makes both branches maybe-null, because the branch the attribute did not name falls
    // back to the declared state: `if map.TryGetValue(k, out found) { found.Label }` then reports
    // NL905 in the branch the call just proved. The same goes for `[MaybeNull]`, `[NotNull]` and
    // `[NotNullWhen(b)]`, which the flow-attribute pass and the postcondition owner read.
    static func IsAnnotatedNullable(attributes: IList<CustomAttributeData>, member: MemberInfo?): bool {
        direct := ReadFlag(attributes, "System.Runtime.CompilerServices.NullableAttribute")
        if direct >= 0 {
            return direct == 2
        }

        return ContextFlag(member) == 2
    }

    // The nearest `NullableContextAttribute` at or above this member, or -1 when there is none.
    static func ContextFlag(member: MemberInfo?): int {
        if member == null {
            return -1
        }

        memberFlag := ReadFlag(member.GetCustomAttributesData(), "System.Runtime.CompilerServices.NullableContextAttribute")
        if memberFlag >= 0 {
            return memberFlag
        }

        owner := member.get_DeclaringType()
        while owner != null {
            ownerFlag := ReadFlag(owner.GetCustomAttributesData(), "System.Runtime.CompilerServices.NullableContextAttribute")
            if ownerFlag >= 0 {
                return ownerFlag
            }

            owner = owner.get_DeclaringType()
        }

        return -1
    }

    // The single-byte argument of the named attribute, or -1 when it is absent or carries the
    // byte-ARRAY form — an array describes a COMPOSITE type and never a bare parameter, so reading
    // its first element here would answer about the wrong position.
    static func ReadFlag(attributes: IList<CustomAttributeData>, attributeFullName: string): int {
        count := NullabilityMetadataReflection.SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            attributeType := attribute.get_AttributeType()
            if string.Equals(attributeType.FullName ?? "", attributeFullName, StringComparison.Ordinal) {
                constructorArguments := attribute.get_ConstructorArguments()
                if NullabilityMetadataReflection.SequenceCount(constructorArguments) == 1 {
                    return ByteValue(constructorArguments.get_Item(0).get_Value())
                }
            }

            index = index + 1
        }

        return -1
    }

    static func ByteValue(value: object?): int {
        if value == null {
            return -1
        }

        obliviousByte: object = ByteOf(0)
        if value.Equals(obliviousByte) {
            return 0
        }

        notNullByte: object = ByteOf(1)
        if value.Equals(notNullByte) {
            return 1
        }

        annotatedByte: object = ByteOf(2)
        if value.Equals(annotatedByte) {
            return 2
        }

        return -1
    }

    static func ByteOf(value: int): byte {
        return (byte)value
    }
}
