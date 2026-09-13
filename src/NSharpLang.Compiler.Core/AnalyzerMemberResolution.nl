namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// WHAT A MEMBER NAME RESOLVES TO ON A TYPE — the analyzer's whole member surface.
//
// `ResolveMember` is the dispatcher: it strips the spellings that are not shapes (oblivious, by-ref,
// alias), answers the shapes that have a closed member set of their own (nullable, SoA row, SoA
// table, tuple, enum, anonymous union, union, newtype, array), converts everything the CLR can
// answer for into a reflection type and asks metadata, asks the declaration context for a declared
// shape's members, and falls through to the extension surface. Every answer is a value: this owner
// reports NO diagnostic, records nothing into the semantic model, and re-enters no walk.
//
// THE RECEIVER THE EXTENSION SURFACE SEES IS THE ONE THE CALLER WROTE, NOT THE ONE RESOLUTION
// ARRIVED AT. `extensionReceiverType` is captured immediately after alias resolution and before any
// conversion to a reflection type or generic definition, so a source shape that was converted to
// CLR metadata for the metadata probe still offers the extensions declared against the SOURCE
// spelling. The two arms that deliberately pass the converted type instead are the anonymous-union
// arm and nothing else.
//
// THE CONTAINING TYPE NAME CROSSES AS A PARAMETER. `Analyzer`'s `_currentTypeName` is a plain
// mutable field reassigned every time the walk enters or leaves a type, so it is read at the call
// and threaded through to the extension surface rather than held here.
class AnalyzerMemberResolution {
    functionTypeFactory: AnalyzerFunctionTypeFactory
    declarationContext: AnalyzerDeclarationContext
    typeSubstitution: AnalyzerTypeSubstitution
    typeResolver: AnalyzerTypeResolver
    clrTypeConversion: AnalyzerClrTypeConversion
    extensionMethodResolution: AnalyzerExtensionMethodResolution
    usingNamespaces: List<string>

    constructor(functionTypes: AnalyzerFunctionTypeFactory, declarations: AnalyzerDeclarationContext, substitution: AnalyzerTypeSubstitution, types: AnalyzerTypeResolver, clrConversion: AnalyzerClrTypeConversion, extensions: AnalyzerExtensionMethodResolution, importedNamespaces: List<string>) {
        functionTypeFactory = functionTypes
        declarationContext = declarations
        typeSubstitution = substitution
        typeResolver = types
        clrTypeConversion = clrConversion
        extensionMethodResolution = extensions
        usingNamespaces = importedNamespaces
    }

    // WHAT A MEMBER NAME RESOLVES TO, read as a VALUE. Every caller that is not the callee of a call
    // asks this question.
    func ResolveMember(objectType: TypeInfo, memberName: string, includeStaticMembers: bool, currentTypeName: string?): TypeInfo {
        return ResolveMember(objectType, memberName, includeStaticMembers, currentTypeName, false, false)
    }

    func ResolveMember(objectType: TypeInfo, memberName: string, includeStaticMembers: bool, currentTypeName: string?, invocationPosition: bool): TypeInfo {
        return ResolveMember(objectType, memberName, includeStaticMembers, currentTypeName, invocationPosition, false)
    }

    // WHAT A MEMBER NAME RESOLVES TO. `unknown` is the "no such member" answer; every arm that can
    // answer does so by returning, so the order of the arms IS the resolution order.
    //
    // `invocationPosition` IS C#'s "must be invocable if member" RULE AND IT IS NOT AN OPTIMISATION.
    // When the name is the thing a call names, a member whose value cannot be CALLED is not a
    // candidate at all and must not hide the method or the extension that shares its name. That is
    // the whole reason `list.Count(predicate)` is a legal program: `List<T>.Count` is an `int`
    // property, `Enumerable.Count<TSource>` is an extension, and only the second one is invocable.
    // Every arm that answers with a VALUE asks the question; the arms that answer with a method
    // group, a signature or a shape are invocable by construction and do not.
    // `inheritedProtectedAccess` IS THE PROTECTED RULE'S RECEIVER HALF, ANSWERED BY THE CALLER.
    //
    // A `protected` member of an EXTERNAL base — `Collection<T>.Items`, `KeyedCollection<K,V>.SetItem`
    // — is a member of every type that derives from it, and a source type that does derive may read
    // it through `this`, through a bare name and through `base`. Metadata resolution asked for
    // `BindingFlags.Public` only, so all three answered "no such member" (NL303/NL412) on a member
    // the CLR would have let the derived type reach.
    //
    // The caller answers because only the caller knows where the access was WRITTEN: the receiver's
    // type has to be the accessing type or derived from it (C# §7.5.4), and `base.` is its own case.
    // `MemberAccessibility` then decides which non-public levels that admits — `family` and its two
    // combinations, never `private`, and never `assembly`, because the member lives in another
    // assembly and N# models no `InternalsVisibleTo`.
    func ResolveMember(objectType: TypeInfo, memberName: string, includeStaticMembers: bool, currentTypeName: string?, invocationPosition: bool, inheritedProtectedAccess: bool): TypeInfo {
        current: TypeInfo = objectType

        oblivious := current as ObliviousTypeInfo
        if oblivious != null {
            current = oblivious.InnerType
        }

        byRef := current as ByRefTypeInfo
        if byRef != null {
            current = byRef.InnerType
        }

        current = declarationContext.ResolveDeclaredAlias(current)
        extensionReceiverType := current
        sourceGenericSubstitution: Dictionary<string, TypeInfo>? = null

        nullable := current as NullableTypeInfo
        if nullable != null {
            if memberName == "HasValue" {
                return BuiltInTypes.Bool
            }
            if memberName == "Value" {
                return nullable.InnerType
            }
        }

        // A ROW IS A VIEW OVER THE TABLE'S COLUMNS AND NOTHING ELSE. A column read through the
        // table's own type carries that table's substitution; a row whose table is not registered
        // falls back to the plain resolution of the written column type.
        soaRowType := current as SoaRowTypeInfo
        if soaRowType != null {
            rowColumn := TryGetSoaColumn(soaRowType.Declaration, memberName)
            if rowColumn != null {
                soaOwner := new SoaRecordTypeInfo(soaRowType.Declaration)
                if declarationContext.TryGetSoaType(soaRowType.Declaration, out soaOwner) {
                    return typeSubstitution.ResolveTypeForSourceOwner(rowColumn.Type, soaOwner, null)
                }

                return typeResolver.ResolveType(rowColumn.Type)
            }

            return BuiltInTypes.Unknown
        }

        // A TABLE'S INSTANCE SURFACE IS ITS COLUMNS-AS-ARRAYS PLUS THE INTRINSICS; ITS STATIC
        // SURFACE IS `wrap` AND NOTHING ELSE.
        soaRecordType := current as SoaRecordTypeInfo
        if soaRecordType != null {
            if !includeStaticMembers {
                columnInfo := TryGetSoaColumn(soaRecordType.Declaration, memberName)
                if columnInfo != null {
                    return new ArrayTypeInfo(typeSubstitution.ResolveTypeForSourceOwner(columnInfo.Type, soaRecordType, null))
                }

                if memberName == "length" || memberName == "capacity" {
                    return BuiltInTypes.Int
                }
                if memberName == "add" {
                    return CreateSoaIntrinsic("add", BuiltInTypes.Int)
                }
                if memberName == "clear" {
                    return CreateSoaIntrinsic("clear", BuiltInTypes.Void)
                }
                if memberName == "ensureCapacity" {
                    return CreateSoaIntrinsicWithParameter("ensureCapacity", BuiltInTypes.Void, "capacity", BuiltInTypes.Int)
                }
                if memberName == "copyRow" {
                    return CreateSoaIntrinsicWithTwoParameters("copyRow", BuiltInTypes.Void, "from", BuiltInTypes.Int, "to", BuiltInTypes.Int)
                }

                return BuiltInTypes.Unknown
            }

            if memberName == "wrap" {
                wrapParameterNames := new List<string>()
                wrapParameterTypes := new List<TypeInfo>()
                wrapColumns := soaRecordType.Declaration.Columns
                wrapIndex := 0
                while wrapIndex < wrapColumns.Count {
                    wrapColumn := wrapColumns[wrapIndex]
                    wrapParameterNames.Add(wrapColumn.Name)
                    wrapParameterTypes.Add(new ArrayTypeInfo(typeSubstitution.ResolveTypeForSourceOwner(wrapColumn.Type, soaRecordType, null)))
                    wrapIndex = wrapIndex + 1
                }

                wrapParameterNames.Add("length")
                wrapParameterTypes.Add(BuiltInTypes.Int)

                wrapType := new FunctionTypeInfo()
                wrapType.SyntheticName = "wrap"
                wrapType.ParameterNames = wrapParameterNames
                wrapType.ParameterTypes = wrapParameterTypes
                wrapType.ReturnType = soaRecordType
                return wrapType
            }

            return BuiltInTypes.Unknown
        }

        // A BUILT-IN SIMPLE TYPE HAS A CLR TYPE BEHIND IT, and member access on a literal or a
        // primitive resolves against that type's metadata. `null`, `never` and `void` have no
        // members and `unknown` must stay unknown, so all four are excluded by name.
        simpleType := current as SimpleTypeInfo
        if simpleType != null && !BuiltInTypes.IsUnknown(current) && BuiltInTypes.IsNot(current, BuiltInTypes.Null) && BuiltInTypes.IsNot(current, BuiltInTypes.Never) && BuiltInTypes.IsNot(current, BuiltInTypes.Void) {
            simpleClrType := clrTypeConversion.TryConvertTypeInfoToClrType(current)
            if simpleClrType != null {
                current = new ReflectionTypeInfo(simpleClrType)
            }
        }

        // A CONSTRUCTED SOURCE GENERIC RESOLVES AGAINST ITS DEFINITION UNDER A SUBSTITUTION. A
        // constructed EXTERNAL generic does not: its definition is a reflection type, and metadata
        // answers for it directly in the reflection arm below.
        handledAsSourceGeneric := false
        sourceGeneric := current as GenericTypeInfo
        if sourceGeneric != null {
            genericDefinition := typeSubstitution.ResolveGenericDefinition(sourceGeneric)
            if genericDefinition != null {
                definitionAsReflection := genericDefinition as ReflectionTypeInfo
                if definitionAsReflection == null {
                    sourceGenericSubstitution = declarationContext.CreateGenericSubstitution(genericDefinition, sourceGeneric.TypeArguments)
                    current = genericDefinition
                    handledAsSourceGeneric = true
                }
            }
        }

        if !handledAsSourceGeneric {
            if !includeStaticMembers {
                arrayExtensionMemberType: TypeInfo = BuiltInTypes.Unknown
                if declarationContext.TryResolveKnownArrayExtensionMember(current, memberName, usingNamespaces.Contains("System"), out arrayExtensionMemberType) && AnswersInPosition(arrayExtensionMemberType, invocationPosition) {
                    return arrayExtensionMemberType
                }

                structuralMemberType: TypeInfo = BuiltInTypes.Unknown
                if declarationContext.TryResolveKnownGenericStructuralMember(current, memberName, out structuralMemberType) && AnswersInPosition(structuralMemberType, invocationPosition) {
                    return structuralMemberType
                }
            }

            genericCandidate := current as GenericTypeInfo
            arrayCandidate := current as ArrayTypeInfo
            if genericCandidate != null || arrayCandidate != null {
                convertedClrType := clrTypeConversion.TryConvertTypeInfoToClrType(current)
                if convertedClrType != null {
                    // A MEMBER DECLARED WITH ONE OF THE INSTANTIATION'S OWN TYPE PARAMETERS IS
                    // ANSWERED FROM THE SPELLING, NOT FROM THE CLOSED CLR TYPE. `Lazy<string?>` and
                    // `Lazy<string>` are the SAME CLR type — the argument's `?` lives in the source
                    // spelling and nowhere in metadata — so reading `Value` off the closed type
                    // answers `string` for both. Read it off the DEFINITION instead, where the
                    // position is still `T`, and let the spelled arguments substitute.
                    spelledMemberType: TypeInfo = BuiltInTypes.Unknown
                    if genericCandidate != null && TryResolveSpelledTypeParameterMember(convertedClrType, genericCandidate, memberName, includeStaticMembers, out spelledMemberType) {
                        return spelledMemberType
                    }

                    current = new ReflectionTypeInfo(convertedClrType)
                } else {
                    // Only a SURROGATE CLR type exists. Metadata may still answer for a property or
                    // a field, but the method arm is deliberately not reached through it.
                    bindingClrType := clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(current)
                    if bindingClrType != null {
                        // THE SURROGATE IS A BINDING DEVICE, NOT AN ANSWER. `Comparer<Item>` binds
                        // as `Comparer<object>` because `Item` has no CLR handle while it is being
                        // emitted, and reading `Default` off that instantiation would answer
                        // `Comparer<object?>` — a type nothing in this compilation can be assigned
                        // to. Read the member off the OPEN DEFINITION instead and substitute the
                        // SPELLED arguments by position, so the answer names `Item` again.
                        surrogateMemberType: TypeInfo = BuiltInTypes.Unknown
                        if genericCandidate != null && TryResolveConstructedGenericPropertyOrField(bindingClrType, genericCandidate, memberName, includeStaticMembers, out surrogateMemberType) && AnswersInPosition(surrogateMemberType, invocationPosition) {
                            return surrogateMemberType
                        }

                        bindingMemberType: TypeInfo = BuiltInTypes.Unknown
                        if TryResolveReflectionPropertyOrField(bindingClrType, memberName, includeStaticMembers, inheritedProtectedAccess, out bindingMemberType) && AnswersInPosition(bindingMemberType, invocationPosition) {
                            return bindingMemberType
                        }

                        // A METHOD IS NOT A MEMBER READ, AND THAT IS WHY IT CAN COME THROUGH THE
                        // SURROGATE. The objection above is about the ANSWER's type: reading
                        // `Comparer<Item>.Default` off `Comparer<object>` would hand back
                        // `Comparer<object?>`. A method group is not an answer — it is a set of
                        // candidates the reflected binder then closes, and that binder already
                        // rebuilds every signature position from the SPELLED receiver through
                        // `TryPopulateReceiverGenericTypeBindings`, so `Dictionary<string, Info>`'s
                        // `TryGetValue` comes back with `out Info` and not with `out object`.
                        //
                        // Without this arm the call's callee typed as `unknown` and the call was not
                        // checked at all: no argument conversion, no arity, and — the census site —
                        // no `[MaybeNullWhen(false)]`, so `if map.TryGetValue(k, out v)` left `v`
                        // maybe-null in the branch where the BCL guarantees it is present.
                        bindingMethodGroup: TypeInfo = BuiltInTypes.Unknown
                        if TryResolveReflectionMethodGroup(bindingClrType, memberName, includeStaticMembers, true, inheritedProtectedAccess, out bindingMethodGroup) {
                            return bindingMethodGroup
                        }
                    }
                }
            }
        }

        // METADATA'S OWN ANSWER. Interface members first — an interface's inherited members are not
        // on the type itself — then property/field/event, then the method GROUP, because overload
        // resolution happens later and a single name may name several methods.
        reflectionType := current as ReflectionTypeInfo
        if reflectionType != null {
            clrType := reflectionType.Type
            memberFlags := GetReflectionMemberFlags(includeStaticMembers, inheritedProtectedAccess)

            interfaceMemberType: TypeInfo = BuiltInTypes.Unknown
            if declarationContext.TryResolveRuntimeInterfaceMethodMember(clrType, memberName, includeStaticMembers, out interfaceMemberType) {
                return interfaceMemberType
            }

            reflectedMemberType: TypeInfo = BuiltInTypes.Unknown
            if TryResolveReflectionPropertyOrField(clrType, memberName, includeStaticMembers, inheritedProtectedAccess, out reflectedMemberType) && AnswersInPosition(reflectedMemberType, invocationPosition) {
                return reflectedMemberType
            }

            reflectedMethods := AnalyzerReflectionMemberProbe.MethodsOrEmpty(clrType, memberFlags)
            matchingMethods := new List<MethodInfo>()
            reflectedIndex := 0
            while reflectedIndex < reflectedMethods.Length {
                reflectedMethod := reflectedMethods[reflectedIndex]
                if reflectedMethod.get_Name() == memberName && IsReachableReflectedMethod(reflectedMethod, inheritedProtectedAccess) {
                    matchingMethods.Add(reflectedMethod)
                }
                reflectedIndex = reflectedIndex + 1
            }

            if matchingMethods.Count > 0 {
                firstMatchingMethod := matchingMethods[0]
                return new ReflectionMethodGroupInfo(matchingMethods.ToArray(), firstMatchingMethod.get_Name() + "(...)")
            }

            // Nothing on the metadata surface; the extension surface still sees the SOURCE receiver.
            return extensionMethodResolution.TryResolveExtensionMethod(extensionReceiverType, memberName, currentTypeName)
        }

        // A DECLARED SHAPE'S OWN MEMBERS. Value members before function members, then the primary
        // constructor's parameters (instance only), then nested types (static only), then the base
        // type, then the inherited `object` surface — and the base walk is a full re-resolution, so
        // a base class's own extension fall-through does NOT apply to a derived receiver.
        sourceShape := new AnalyzerSourceMemberShape()
        if declarationContext.TryGetSourceMemberShape(current, sourceGenericSubstitution, out sourceShape) {
            // AN EVENT ANSWERS TWO DIFFERENT THINGS DEPENDING ON WHO IS ASKING, and it is asked before
            // the value members because the backing delegate carries the same name. Inside the
            // declaring type the name IS that delegate — which is what makes `Changed?.Invoke(...)`
            // and `Changed == null` ordinary reads there. Everywhere else it is the EVENT, a shape
            // with no value at all, so `on`/`off` bind it and every other use is reported rather than
            // silently reaching a private field.
            declaredEventHandler: TypeInfo = BuiltInTypes.Unknown
            if declarationContext.TryResolveDeclaredEventMember(sourceShape.Owner, sourceShape.DeclaredMembers, memberName, sourceGenericSubstitution, out declaredEventHandler) {
                if SourceEventFacts.IsInsideDeclaringType(sourceShape.Owner, currentTypeName) {
                    return declaredEventHandler
                }

                return new SourceEventInfo(memberName, SourceEventFacts.DeclaringTypeName(sourceShape.Owner), declaredEventHandler, SourceEventFacts.DeclaringTypeIsValueType(sourceShape.Owner))
            }

            declaredValueMember: TypeInfo = BuiltInTypes.Unknown
            if declarationContext.TryResolveDeclaredValueMember(sourceShape.Owner, sourceShape.DeclaredMembers, memberName, sourceGenericSubstitution, out declaredValueMember) && AnswersInPosition(declaredValueMember, invocationPosition) {
                return declaredValueMember
            }

            declaredFunctionMember := ResolveDeclaredFunctionMember(sourceShape.DeclaredMembers, memberName, sourceGenericSubstitution, sourceShape.Owner)
            if declaredFunctionMember != null {
                return declaredFunctionMember
            }

            if !includeStaticMembers && sourceShape.SupportsPrimaryParameters {
                primaryConstructorMember: TypeInfo = BuiltInTypes.Unknown
                if declarationContext.TryResolvePrimaryParameter(sourceShape.Owner, sourceShape.PrimaryParameters, memberName, sourceGenericSubstitution, out primaryConstructorMember) && AnswersInPosition(primaryConstructorMember, invocationPosition) {
                    return primaryConstructorMember
                }
            }

            if includeStaticMembers {
                nestedTypeMember: TypeInfo = BuiltInTypes.Unknown
                if declarationContext.TryResolveNestedType(sourceShape.Owner, memberName, false, out nestedTypeMember) {
                    return nestedTypeMember
                }
            }

            declaredBaseType := sourceShape.BaseType
            if declaredBaseType != null {
                baseMember := ResolveMember(declaredBaseType, memberName, includeStaticMembers, currentTypeName, invocationPosition, inheritedProtectedAccess)
                if !BuiltInTypes.IsUnknown(baseMember) {
                    return baseMember
                }
            }

            if !includeStaticMembers && sourceShape.SupportsObjectMembers {
                shapeObjectMember: TypeInfo = BuiltInTypes.Unknown
                if TryResolveSourceObjectMember(memberName, out shapeObjectMember) {
                    return shapeObjectMember
                }
            }
        }

        tupleType := current as TupleTypeInfo
        if tupleType != null {
            tupleMember: TypeInfo = BuiltInTypes.Unknown
            if declarationContext.TryResolveTupleMember(tupleType, memberName, out tupleMember) && AnswersInPosition(tupleMember, invocationPosition) {
                return tupleMember
            }

            if !includeStaticMembers {
                tupleObjectMember: TypeInfo = BuiltInTypes.Unknown
                if TryResolveSourceObjectMember(memberName, out tupleObjectMember) {
                    return tupleObjectMember
                }
            }
        }

        // AN ENUM MEMBER READ OFF THE ENUM TYPE IS THE ENUM TYPE. Instance access falls to the
        // inherited `System.Enum` surface instead — an enum VALUE has no declared members of its own.
        enumType := current as EnumTypeInfo
        if enumType != null {
            if includeStaticMembers {
                enumMembers := enumType.Declaration.Members
                enumIndex := 0
                while enumIndex < enumMembers.Count {
                    if enumMembers[enumIndex].Name == memberName {
                        return current
                    }
                    enumIndex = enumIndex + 1
                }
            }

            if !includeStaticMembers {
                enumObjectMember: TypeInfo = BuiltInTypes.Unknown
                if TryResolveSourceEnumMember(memberName, out enumObjectMember) {
                    return enumObjectMember
                }
            }
        }

        // THE ANONYMOUS UNION'S DISCRIMINATOR PAIR, and its extension fall-through is the ONE arm
        // that offers the RESOLVED type rather than the written receiver.
        anonymousUnion := current as AnonymousUnionTypeInfo
        if anonymousUnion != null {
            if memberName == "Index" {
                return BuiltInTypes.Int
            }
            if memberName == "Value" {
                return BuiltInTypes.Object
            }

            return extensionMethodResolution.TryResolveExtensionMethod(current, memberName, currentTypeName)
        }

        // A DECLARED UNION ANSWERS WITH ITSELF for every name: the arms are resolved by the match
        // walk, not by member access, and answering `unknown` here would report a member error on a
        // shape whose members are legitimately open.
        declaredUnion := current as UnionTypeInfo
        if declaredUnion != null {
            return current
        }

        newtypeCandidate := current as NewtypeInfo
        if newtypeCandidate != null {
            if memberName == "Value" {
                newtypeValueMember := typeSubstitution.ResolveTypeForSourceOwner(newtypeCandidate.UnderlyingType, newtypeCandidate, null)
                if AnswersInPosition(newtypeValueMember, invocationPosition) {
                    return newtypeValueMember
                }
            }

            if !includeStaticMembers {
                newtypeObjectMember: TypeInfo = BuiltInTypes.Unknown
                if TryResolveSourceObjectMember(memberName, out newtypeObjectMember) {
                    return newtypeObjectMember
                }
            }
        }

        arrayType := current as ArrayTypeInfo
        if arrayType != null {
            if memberName == "Length" && AnswersInPosition(BuiltInTypes.Int, invocationPosition) {
                return BuiltInTypes.Int
            }
        }

        return extensionMethodResolution.TryResolveExtensionMethod(extensionReceiverType, memberName, currentTypeName)
    }

    // Whether a resolved VALUE member is allowed to be this resolution's answer. Outside invocation
    // position every member is; inside it only a member a call could actually name.
    static func AnswersInPosition(memberType: TypeInfo, invocationPosition: bool): bool {
        if !invocationPosition {
            return true
        }

        return AnalyzerCallableReferenceFacts.IsInvocableMemberType(memberType)
    }

    // Public instance members always; static members only when the name was written against the
    // TYPE rather than against a value.
    // A PROPERTY OR FIELD OF A CONSTRUCTED GENERIC WHOSE ARGUMENTS ONLY BOUND AS SURROGATES.
    // The definition is a real reflection type in the binding type's own universe, so its member is
    // readable; what the member's type mentions are the DEFINITION's parameters, which the spelled
    // arguments replace by position. Arity is checked because a spelling and a definition that
    // disagree about it cannot be substituted at all.
    static func TryResolveConstructedGenericPropertyOrField(bindingClrType: Type, genericType: GenericTypeInfo, memberName: string, includeStaticMembers: bool, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown
        if !bindingClrType.get_IsGenericType() || bindingClrType.get_IsGenericTypeDefinition() {
            return false
        }

        definition := bindingClrType.GetGenericTypeDefinition()
        if definition.GetGenericArguments().Length != genericType.TypeArguments.Count {
            return false
        }

        typeOverride := AnalyzerReflectionTypeOverride.ForGenericArguments(definition, genericType)
        memberFlags := GetReflectionMemberFlags(includeStaticMembers)
        property := definition.GetProperty(memberName, memberFlags)
        if property != null {
            memberType = NullabilityMetadataReflection.ConvertPropertyWithOverride(property, typeOverride)
            return true
        }

        field := definition.GetField(memberName, memberFlags)
        if field != null {
            memberType = NullabilityMetadataReflection.ConvertFieldWithOverride(field, typeOverride)
            return true
        }

        return false
    }

    // Every method of that name the type declares, as a group. The caller decides whether a group is
    // an acceptable answer in its position; overload resolution happens later, in the binder.
    // A PROPERTY'S ACCESSIBILITY IS ITS ACCESSORS'. Metadata carries no accessibility on a property
    // row at all, so the getter decides; a property with no getter is not a read this arm can answer.
    static func IsReachableReflectedProperty(property: PropertyInfo, inheritedProtectedAccess: bool): bool {
        getter := property.GetGetMethod(true)
        if getter == null {
            return false
        }

        return IsReachableReflectedMethod(getter, inheritedProtectedAccess)
    }

    static func TryResolveReflectionMethodGroup(clrType: Type, memberName: string, includeStaticMembers: bool, surrogateBinding: bool, out memberType: TypeInfo): bool {
        return TryResolveReflectionMethodGroup(clrType, memberName, includeStaticMembers, surrogateBinding, false, out memberType)
    }

    static func TryResolveReflectionMethodGroup(clrType: Type, memberName: string, includeStaticMembers: bool, surrogateBinding: bool, inheritedProtectedAccess: bool, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown
        methods := clrType.GetMethods(GetReflectionMemberFlags(includeStaticMembers, inheritedProtectedAccess))
        matching := new List<MethodInfo>()
        index := 0
        while index < methods.Length {
            method := methods[index]
            if method.get_Name() == memberName && IsReachableReflectedMethod(method, inheritedProtectedAccess) {
                matching.Add(method)
            }

            index = index + 1
        }

        if matching.Count == 0 {
            return false
        }

        memberType = new ReflectionMethodGroupInfo(matching.ToArray(), matching[0].get_Name() + "(...)", surrogateBinding)
        return true
    }

    // A PROPERTY OR FIELD OF A CONSTRUCTED GENERIC WHOSE DECLARED TYPE IS ONE OF THE DEFINITION'S OWN
    // TYPE PARAMETERS. This is the EXACT-conversion twin of `TryResolveConstructedGenericPropertyOrField`
    // above: that one exists because the arguments only bound as surrogates, this one because the
    // arguments' NULLABILITY is in the spelling and not in the CLR type they convert to.
    //
    // It answers for nothing else. A member whose type does not mention a type parameter reads
    // identically off the closed type, and an INHERITED one is spelled in its BASE's parameters,
    // which the receiver's arguments do not index — so both fall through to the ordinary reflection
    // arm, which is where they were answered before.
    static func TryResolveSpelledTypeParameterMember(closedClrType: Type, genericType: GenericTypeInfo, memberName: string, includeStaticMembers: bool, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown
        if !closedClrType.get_IsGenericType() || closedClrType.get_IsGenericTypeDefinition() {
            return false
        }

        definition := closedClrType.GetGenericTypeDefinition()
        if definition.GetGenericArguments().Length != genericType.TypeArguments.Count {
            return false
        }

        memberFlags := GetReflectionMemberFlags(includeStaticMembers)
        property := definition.GetProperty(memberName, memberFlags)
        if property != null && property.get_DeclaringType() == definition && NullabilityGenericSubstitution.IsTypeParameterPosition(property.get_PropertyType()) {
            memberType = NullabilityMetadataReflection.ConvertPropertyWithOverride(property, AnalyzerReflectionTypeOverride.ForGenericArguments(definition, genericType))
            return true
        }

        field := definition.GetField(memberName, memberFlags)
        if field != null && field.get_DeclaringType() == definition && NullabilityGenericSubstitution.IsTypeParameterPosition(field.get_FieldType()) {
            memberType = NullabilityMetadataReflection.ConvertFieldWithOverride(field, AnalyzerReflectionTypeOverride.ForGenericArguments(definition, genericType))
            return true
        }

        return false
    }

    static func GetReflectionMemberFlags(includeStaticMembers: bool): BindingFlags {
        return GetReflectionMemberFlags(includeStaticMembers, false)
    }

    // NON-PUBLIC IS AN OPT-IN AND THE FILTER BESIDE IT IS NOT OPTIONAL. Asking metadata for
    // non-public members returns `private` and `assembly` ones too, neither of which a derived type
    // in ANOTHER assembly may touch, so every arm that widens these flags also asks
    // `IsReachableReflectedLevel` about what came back.
    static func GetReflectionMemberFlags(includeStaticMembers: bool, includeInheritedProtected: bool): BindingFlags {
        memberFlags := BindingFlags.Public | BindingFlags.Instance
        if includeStaticMembers {
            memberFlags = memberFlags | BindingFlags.Static
        }

        if includeInheritedProtected {
            memberFlags = memberFlags | BindingFlags.NonPublic
        }

        return memberFlags
    }

    // Which levels a source type derived from an EXTERNAL base may reach on it: `public` always, and
    // the three `family` spellings when the access is written inside that derived type through a
    // compatible receiver. `assembly` and `private` never — the member is in a referenced assembly.
    static func IsReachableReflectedLevel(level: int, inheritedProtectedAccess: bool): bool {
        return MemberAccessibility.IsAccessible(level, false, inheritedProtectedAccess, inheritedProtectedAccess, false)
    }

    static func IsReachableReflectedMethod(method: MethodInfo, inheritedProtectedAccess: bool): bool {
        return IsReachableReflectedLevel(MemberAccessibility.LevelOfMethod(method), inheritedProtectedAccess)
    }

    // PROPERTY, THEN FIELD, THEN EVENT — and a name that is more than one answers as the earlier
    // kind.
    //
    // THE EVENT ARM IS NOT A CONVENIENCE. A .NET event's private backing field carries the SAME
    // name in metadata, so without this arm `GetField` would find it and an event would resolve to
    // a delegate-typed field: `+=` against it would silently become a field assignment instead of a
    // subscription, and `on`/`off` would write the field rather than call the accessors. The
    // accessors are found with the NON-PUBLIC opt-in because an event may be public while its
    // add/remove methods are not, and the handler delegate type and declaring type ride on the
    // answer because the subscription needs both to emit.
    // AN INTERFACE DOES NOT INHERIT ITS BASES' MEMBERS THROUGH `GetProperty`, and that is the whole
    // reason `IList<T>.Count` reported NL303 while `IList<T>.get_Count()` — the accessor for the very
    // same property — resolved: method resolution already walked the base interfaces and this arm did
    // not. A CLASS receiver needs no sweep, because metadata already walks its base chain.
    // `GetInterfaces()` is FLATTENED, so one loop reaches every transitive base and there is no
    // recursion to bound.
    static func TryResolveReflectionPropertyOrField(reflectedType: Type, memberName: string, includeStaticMembers: bool, out memberType: TypeInfo): bool {
        return TryResolveReflectionPropertyOrField(reflectedType, memberName, includeStaticMembers, false, out memberType)
    }

    static func TryResolveReflectionPropertyOrField(reflectedType: Type, memberName: string, includeStaticMembers: bool, inheritedProtectedAccess: bool, out memberType: TypeInfo): bool {
        if TryResolveReflectionMemberOnType(reflectedType, memberName, includeStaticMembers, inheritedProtectedAccess, out memberType) {
            return true
        }

        if !reflectedType.get_IsInterface() {
            return false
        }

        baseInterfaces := reflectedType.GetInterfaces()
        index := 0
        while index < baseInterfaces.Length {
            if TryResolveReflectionMemberOnType(baseInterfaces[index], memberName, includeStaticMembers, inheritedProtectedAccess, out memberType) {
                return true
            }

            index = index + 1
        }

        memberType = BuiltInTypes.Unknown
        return false
    }

    static func TryResolveReflectionMemberOnType(reflectedType: Type, memberName: string, includeStaticMembers: bool, inheritedProtectedAccess: bool, out memberType: TypeInfo): bool {
        memberFlags := GetReflectionMemberFlags(includeStaticMembers, inheritedProtectedAccess)

        property := reflectedType.GetProperty(memberName, memberFlags)
        if property != null && IsReachableReflectedProperty(property, inheritedProtectedAccess) {
            memberType = NullabilityMetadataReflection.ConvertProperty(property)
            return true
        }

        field := reflectedType.GetField(memberName, memberFlags)
        if field != null && IsReachableReflectedLevel(MemberAccessibility.LevelOfField(field), inheritedProtectedAccess) {
            memberType = NullabilityMetadataReflection.ConvertField(field)
            return true
        }

        eventMember := reflectedType.GetEvent(memberName, memberFlags)
        if eventMember != null {
            memberType = new ReflectionEventInfo(eventMember.get_Name(), eventMember.GetAddMethod(true), eventMember.GetRemoveMethod(true), eventMember.get_EventHandlerType(), eventMember.get_DeclaringType(), "event " + eventMember.get_Name())
            return true
        }

        memberType = BuiltInTypes.Unknown
        return false
    }

    // A DECLARED `func` member's type. ONE match is that function's type; SEVERAL are a method
    // group, and overload resolution chooses later.
    //
    // THE ALL-OR-NOTHING GUARD IS THE POINT, AND IT IS NOT A NULL CHECK. A declared member whose
    // recorded arity arrays disagree with its recorded counts is not a member this owner can build a
    // signature from — and if ANY overload is in that state the whole NAME answers nothing, rather
    // than a method group silently missing one of its overloads. A partial group would bind a call
    // to the wrong overload with no diagnostic at all.
    func ResolveDeclaredFunctionMember(members: DeclaredMemberInfo[], memberName: string, substitution: Dictionary<string, TypeInfo>?, declarationOwner: TypeInfo?): TypeInfo? {
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
            functionTypes.Add(functionTypeFactory.CreateFromDeclaredMember(matching[buildIndex], substitution, declarationOwner))
            buildIndex = buildIndex + 1
        }

        if functionTypes.Count == 1 {
            return functionTypes[0]
        }

        return NSharpMethodGroupInfoFactory.FromFunctions(functionTypes)
    }

    // The recorded shape is self-consistent: the arrays are as long as the counts say, and the
    // required-parameter count is a real prefix of the parameter list.
    static func CanResolveFunctionMemberFromTypeInfo(member: DeclaredMemberInfo): bool {
        return member.TypeParameters.Length == member.TypeParameterCount && member.RequiredParameterCount >= 0 && member.RequiredParameterCount <= member.ParameterCount && member.ParameterNames.Length == member.ParameterCount && member.ParameterTypes.Length == member.ParameterCount && member.ParameterModifiers.Length == member.ParameterCount
    }

    // EVERY SOURCE TYPE INHERITS `object`, AND THIS IS THAT SURFACE. A source declaration names no
    // base type of its own, so the members `object` contributes — `ToString`, `Equals`,
    // `GetHashCode`, `GetType` — are resolved against the runtime type directly rather than through
    // any declared shape. Instance members only: a static `object` member is not inherited.
    static func TryResolveSourceObjectMember(memberName: string, out memberType: TypeInfo): bool {
        return TryResolveInheritedRuntimeMember(typeof(object), memberName, out memberType)
    }

    // A SOURCE ENUM'S INSTANCE SURFACE IS `System.Enum`, NOT `object`. The CLR gives every enum
    // `System.Enum` as its base type, so `HasFlag`, `CompareTo`, `GetTypeCode` and — decisively —
    // `Enum.ToString()`, which returns a NON-NULL `string`, are the members an enum value inherits.
    // Resolving an enum against `object` instead handed back `object.ToString()`'s `string?`, so
    // `symbol.Kind.ToString().ToLower()` reported NL905 and `enum.HasFlag(other)` reported NL303
    // even though both are ordinary inherited members. This is the same ordinary reflection walk the
    // `object` surface uses, asked of the base type the runtime actually gives an enum.
    static func TryResolveSourceEnumMember(memberName: string, out memberType: TypeInfo): bool {
        return TryResolveInheritedRuntimeMember(typeof(Enum), memberName, out memberType)
    }

    // THE PROBE ORDER IS PROPERTY, THEN FIELD, THEN METHOD, and the method arm distinguishes a
    // single method from a group because `Equals` is overloaded on `object` and `ToString` is not.
    // Accessor methods are excluded by the property arm answering first, not by a name test.
    static func TryResolveInheritedRuntimeMember(objectType: Type, memberName: string, out memberType: TypeInfo): bool {
        memberType = BuiltInTypes.Unknown
        flags := BindingFlags.Public | BindingFlags.Instance

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
    static func TryGetSoaColumn(declaration: SoaRecordDeclarationInfo, name: string): SoaColumnInfo? {
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
    static func CreateSoaIntrinsic(syntheticName: string, returnType: TypeInfo): FunctionTypeInfo {
        result := new FunctionTypeInfo()
        result.SyntheticName = syntheticName
        result.ParameterNames = new List<string>()
        result.ParameterTypes = new List<TypeInfo>()
        result.ReturnType = returnType
        return result
    }

    static func CreateSoaIntrinsicWithParameter(syntheticName: string, returnType: TypeInfo, parameterName: string, parameterType: TypeInfo): FunctionTypeInfo {
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

    static func CreateSoaIntrinsicWithTwoParameters(syntheticName: string, returnType: TypeInfo, firstName: string, firstType: TypeInfo, secondName: string, secondType: TypeInfo): FunctionTypeInfo {
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
