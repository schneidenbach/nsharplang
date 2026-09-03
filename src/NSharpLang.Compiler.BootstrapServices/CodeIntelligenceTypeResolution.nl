namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE TYPE-INFO RESOLVERS — the answer behind every hover, every `query type`, and the type half of
// go-to-definition. Given a position, a semantic model and the project's compilation units, this is
// what turns a syntax node into a `TypeInfo`.
//
// THERE ARE THREE INDEPENDENT ROUTES TO A TYPE AND THEY ARE TRIED IN A FIXED ORDER, which is the
// service's driver order and not this owner's: the DECLARED NAME (the cursor is sitting on a
// declaration's own name), the TYPE USE (the cursor is on a type reference), and finally the
// EXPRESSION (everything else). Each is a separate entry point here.
//
// THE SEMANTIC MODEL ALWAYS WINS WHEN IT HAS AN ANSWER, AND `unknown` DOES NOT COUNT AS ONE.
// `TypeInfoFromExpression` asks `LookupTypeAtPosition` first and only falls back to the syntactic
// walk when the model returns null OR an `UnknownTypeInfo` — an analyzer that recorded a type it
// could not resolve must not stop the walk that can.
//
// TWO MUTUAL RECURSIONS, MEASURED RATHER THAN ASSUMED. `TypeInfoFromExpression` and `MemberTypeInfo`
// are one cycle (a member access resolves its receiver, which may itself be a member access);
// `TypeReferenceToTypeInfo` and `FindNamedTypeInfo` are the other (a named type resolves to a
// declaration whose alias or arguments are themselves type references). The two cycles are joined
// ONE WAY — the expression cycle reaches the type-reference cycle and nothing comes back — and
// `TypeInfoByName` sits between them in no cycle at all.
//
// THE TWO `FindMemberTypeInfo` OVERLOADS BECAME TWO NAMES. C# could tell
// `FindMemberTypeInfo(snapshot, TypeInfo, string)` from
// `FindMemberTypeInfo(snapshot, IReadOnlyList<DeclaredMemberInfo>, string)` by argument type; here
// they are `MemberTypeInfoOfType` and `MemberTypeInfoInMembers`, and the edge between them runs one
// way only — a type asks its member list, never the reverse.
//
// THE COMPILATION UNITS CROSS AS THE SNAPSHOT'S OWN `IReadOnlyDictionary` AND ARE NEVER
// MATERIALISED. The key is never read: both walks discard it exactly as the C# `foreach (var (_, cu)
// in snapshot.CompilationUnits)` did. Passing the dictionary through unchanged keeps the per-hover
// rebuild that the published catalog row removed from the diagnostics path from coming back here.
//
// TWO WALKS OVER THE SAME DECLARATIONS ANSWER DIFFERENT QUESTIONS, AND THE DIFFERENCE IS
// DELIBERATE. `TypeInfoFromDeclaration` answers "what is the type OF the thing called `name`" and
// so matches functions, fields and properties as well as types. `FindNamedTypeInfo` answers "what
// TYPE is called `name`" and so matches ONLY type declarations — a field called `Foo` never
// satisfies a `Foo` type reference. That is why the two arm-chains are not shared.
//
// A DECLARED-NAME ANSWER IS ONLY GIVEN ON THE DECLARATION'S OWN LINE. The walk descends into
// members, but every candidate must match BOTH the selected word and the queried line, so a field
// named `Value` does not answer a query on a different `Value` twenty lines away.
class CodeIntelligenceTypeResolution {

    // ── Route 1: the declared name ──────────────────────────────────────
    // The recursion is over MEMBERS, so a nested type's member is reachable; a member whose type
    // cannot be determined does NOT stop the walk, it falls through to the member loop exactly as
    // the `&&` chain it replaces did.
    static func DeclaredNameTypeInDeclaration(projectRoot: string, compilationUnits: IReadOnlyDictionary<string, CompilationUnit>, filePath: string, declaration: Declaration, selectedName: string, line: int): TypeResult? {
        declarationName := DeclarationFacts.GetDeclarationName(declaration)
        if declaration.Line == line && declarationName == selectedName {
            typeInfo := DeclaredNameTypeInfo(declaration, compilationUnits)
            if typeInfo != null {
                location := new LocationResult(CodeIntelligenceSourceDoor.RelativePath(projectRoot, filePath), declaration.Line, declaration.Column)
                return new TypeResult(selectedName, NullabilityMetadataReflection.FormatTypeInfo(typeInfo), CodeIntelligenceDisplayText.TypeInfoToKind(typeInfo), location, NullStateFacts.GetSchemaText(DefaultNullState(typeInfo)))
            }
        }

        members := DeclarationFacts.GetDeclarationMembers(declaration)
        if members != null {
            index := 0
            while index < members.Count {
                member := members[index] as Declaration
                if member != null {
                    memberResult := DeclaredNameTypeInDeclaration(projectRoot, compilationUnits, filePath, member, selectedName, line)
                    if memberResult != null {
                        return memberResult
                    }
                }

                index = index + 1
            }
        }

        return null
    }

    // THE TYPE A DECLARATION DECLARES. Null means "this declaration form carries no type at all" —
    // a constructor, an indexer, a preprocessor line — and is the caller's signal to keep walking.
    // A FIELD WITH NO WRITTEN TYPE IS ALSO NULL: an inferred field is not a declared-name answer.
    // A FUNCTION WITH NO RETURN TYPE IS `void`, which IS an answer.
    static func DeclaredNameTypeInfo(declaration: Declaration, compilationUnits: IReadOnlyDictionary<string, CompilationUnit>): TypeInfo? {
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null {
            returnType := functionDeclaration.ReturnType
            if returnType != null {
                return TypeReferenceToTypeInfo(returnType, compilationUnits)
            }

            return new SimpleTypeInfo("void")
        }

        fieldDeclaration := declaration as FieldDeclaration
        if fieldDeclaration != null {
            fieldType := fieldDeclaration.Type
            if fieldType != null {
                return TypeReferenceToTypeInfo(fieldType, compilationUnits)
            }

            return null
        }

        propertyDeclaration := declaration as PropertyDeclaration
        if propertyDeclaration != null {
            return TypeReferenceToTypeInfo(propertyDeclaration.Type, compilationUnits)
        }

        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            return NominalTypeInfoFactory.FromClassDeclaration(classDeclaration)
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            return NominalTypeInfoFactory.FromStructDeclaration(structDeclaration)
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            return NominalTypeInfoFactory.FromRecordDeclaration(recordDeclaration)
        }

        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            return NominalTypeInfoFactory.FromInterfaceDeclaration(interfaceDeclaration)
        }

        enumDeclaration := declaration as EnumDeclaration
        if enumDeclaration != null {
            return EnumTypeInfoFactory.FromDeclaration(enumDeclaration)
        }

        unionDeclaration := declaration as UnionDeclaration
        if unionDeclaration != null {
            return UnionTypeInfoFactory.FromDeclaration(unionDeclaration)
        }

        aliasDeclaration := declaration as TypeAliasDeclaration
        if aliasDeclaration != null {
            return TypeReferenceToTypeInfo(aliasDeclaration.Type, compilationUnits)
        }

        newtypeDeclaration := declaration as NewtypeDeclaration
        if newtypeDeclaration != null {
            return new NewtypeInfo(newtypeDeclaration.Name, newtypeDeclaration.UnderlyingType)
        }

        return null
    }

    // ── Route 3: the expression ─────────────────────────────────────────
    // THE LITERAL ARMS ARE THE FLOOR AND THEY ARE UNCONDITIONAL: an int literal is `int` even where
    // the model knows better, because the model was asked first and declined.
    // A FLOAT LITERAL IS `double` AND A NULL LITERAL IS `object` — both are the shipped answers.
    static func TypeInfoFromExpression(expr: Expression?, semanticModel: SemanticModel?, compilationUnits: IReadOnlyDictionary<string, CompilationUnit>, currentUnit: CompilationUnit): TypeInfo? {
        if expr != null && semanticModel != null {
            resolved := semanticModel.LookupTypeAtPosition(expr.Line, expr.Column)
            if resolved != null && !BuiltInTypes.IsUnknown(resolved) {
                return resolved
            }
        }

        identifier := expr as IdentifierExpression
        if identifier != null {
            return TypeInfoByName(identifier.Name, semanticModel, compilationUnits, currentUnit)
        }

        // A MEMBER ACCESS FALLS BACK TO THE MEMBER'S BARE NAME. When the receiver cannot be typed,
        // `a.Foo` is resolved as if `Foo` had been written alone — which is how a member access on
        // an unknown receiver still names a type declared in the project.
        memberAccess := expr as MemberAccessExpression
        if memberAccess != null {
            memberType := MemberTypeInfo(memberAccess, semanticModel, compilationUnits, currentUnit)
            if memberType != null {
                return memberType
            }

            return TypeInfoByName(memberAccess.MemberName, semanticModel, compilationUnits, currentUnit)
        }

        // A CALL IS TYPED BY ITS CALLEE, NOT BY ITS RETURN TYPE — the callee resolves to the
        // function's declared return type through `DeclaredNameTypeInfo`'s function arm.
        call := expr as CallExpression
        if call != null {
            return TypeInfoFromExpression(call.Callee, semanticModel, compilationUnits, currentUnit)
        }

        newExpression := expr as NewExpression
        if newExpression != null {
            newType := newExpression.Type
            if newType != null {
                return TypeReferenceToTypeInfo(newType, compilationUnits)
            }

            return null
        }

        withExpression := expr as WithExpression
        if withExpression != null {
            return TypeInfoFromExpression(withExpression.Target, semanticModel, compilationUnits, currentUnit)
        }

        // AN AWAIT IS TYPED AS ITS OPERAND AND THE TASK IS NOT UNWRAPPED — the shipped answer.
        awaitExpression := expr as AwaitExpression
        if awaitExpression != null {
            return TypeInfoFromExpression(awaitExpression.Expression, semanticModel, compilationUnits, currentUnit)
        }

        castExpression := expr as CastExpression
        if castExpression != null {
            return TypeReferenceToTypeInfo(castExpression.TargetType, compilationUnits)
        }

        parenthesized := expr as ParenthesizedExpression
        if parenthesized != null {
            return TypeInfoFromExpression(parenthesized.Inner, semanticModel, compilationUnits, currentUnit)
        }

        intLiteral := expr as IntLiteralExpression
        if intLiteral != null {
            return new SimpleTypeInfo("int")
        }

        floatLiteral := expr as FloatLiteralExpression
        if floatLiteral != null {
            return new SimpleTypeInfo("double")
        }

        charLiteral := expr as CharLiteralExpression
        if charLiteral != null {
            return new SimpleTypeInfo("char")
        }

        stringLiteral := expr as StringLiteralExpression
        if stringLiteral != null {
            return new SimpleTypeInfo("string")
        }

        interpolatedString := expr as InterpolatedStringExpression
        if interpolatedString != null {
            return new SimpleTypeInfo("string")
        }

        boolLiteral := expr as BoolLiteralExpression
        if boolLiteral != null {
            return new SimpleTypeInfo("bool")
        }

        nullLiteral := expr as NullLiteralExpression
        if nullLiteral != null {
            return new SimpleTypeInfo("object")
        }

        return null
    }

    // THE RECEIVER IS ASKED TWICE. The general expression walk runs first; only if it fails and the
    // receiver is a bare identifier is the name looked up on its own. The second attempt is not
    // redundant — the first can decline for an identifier the semantic model has no entry for.
    static func MemberTypeInfo(memberAccess: MemberAccessExpression, semanticModel: SemanticModel?, compilationUnits: IReadOnlyDictionary<string, CompilationUnit>, currentUnit: CompilationUnit): TypeInfo? {
        receiverType: TypeInfo? = TypeInfoFromExpression(memberAccess.Object, semanticModel, compilationUnits, currentUnit)
        if receiverType == null {
            receiverIdentifier := memberAccess.Object as IdentifierExpression
            if receiverIdentifier != null {
                receiverType = TypeInfoByName(receiverIdentifier.Name, semanticModel, compilationUnits, currentUnit)
            }
        }

        if receiverType == null {
            return null
        }

        return MemberTypeInfoOfType(compilationUnits, receiverType, memberAccess.MemberName)
    }

    // A CLASS IS THE ONLY ARM THAT CLIMBS. Its declared members are searched first and its base
    // class second; a struct, a record and an interface are asked about their own members only.
    // AN ENUM, A UNION AND AN ANONYMOUS UNION ANSWER WITH THEMSELVES whatever member was asked for,
    // which is what makes `Color.Red` report `Color`.
    // A NULLABLE, AN OBLIVIOUS AND AN ALIAS ARE TRANSPARENT: the member is looked up on what they
    // wrap, so `x?.Length` is the same answer as `x.Length`.
    static func MemberTypeInfoOfType(compilationUnits: IReadOnlyDictionary<string, CompilationUnit>, receiverType: TypeInfo, memberName: string): TypeInfo? {
        classType := receiverType as ClassTypeInfo
        if classType != null {
            declared := MemberTypeInfoInMembers(compilationUnits, classType.DeclaredMembers, memberName)
            if declared != null {
                return declared
            }

            baseClass := classType.BaseClass
            if baseClass != null {
                return MemberTypeInfoOfType(compilationUnits, TypeReferenceToTypeInfo(baseClass, compilationUnits), memberName)
            }

            return null
        }

        structType := receiverType as StructTypeInfo
        if structType != null {
            return MemberTypeInfoInMembers(compilationUnits, structType.DeclaredMembers, memberName)
        }

        recordType := receiverType as RecordTypeInfo
        if recordType != null {
            return MemberTypeInfoInMembers(compilationUnits, recordType.DeclaredMembers, memberName)
        }

        interfaceType := receiverType as InterfaceTypeInfo
        if interfaceType != null {
            return MemberTypeInfoInMembers(compilationUnits, interfaceType.DeclaredMembers, memberName)
        }

        enumType := receiverType as EnumTypeInfo
        if enumType != null {
            return receiverType
        }

        anonymousUnionType := receiverType as AnonymousUnionTypeInfo
        if anonymousUnionType != null {
            return receiverType
        }

        namedUnionType := receiverType as UnionTypeInfo
        if namedUnionType != null {
            return receiverType
        }

        aliasType := receiverType as AliasTypeInfo
        if aliasType != null {
            return MemberTypeInfoOfType(compilationUnits, TypeReferenceToTypeInfo(aliasType.AliasedType, compilationUnits), memberName)
        }

        nullableType := receiverType as NullableTypeInfo
        if nullableType != null {
            return MemberTypeInfoOfType(compilationUnits, nullableType.InnerType, memberName)
        }

        obliviousType := receiverType as ObliviousTypeInfo
        if obliviousType != null {
            return MemberTypeInfoOfType(compilationUnits, obliviousType.InnerType, memberName)
        }

        // THE LAST ARM IS THE ONE THAT WAS MISSING, AND IT IS WHY A BCL RECEIVER HAD NO MEMBERS AT
        // ALL. Every arm above answers from a SOURCE DECLARATION, so a receiver the project did not
        // declare fell straight through to null and hover depended entirely on whether the analyzer
        // happened to have recorded something at that exact position. A receiver metadata explains
        // is now answered from metadata.
        return ReflectedMemberTypeInfo(receiverType, memberName)
    }

    // ── The reflected member ────────────────────────────────────────────
    // THE MEMBER'S TYPE, WHICH IS NOT THE SAME QUESTION AS THE MEMBER. This answers what a member
    // access EVALUATES TO, so a property and a field answer with their own type and a method answers
    // with the method group the analyzer would have built. Hover wants the MEMBER as well — its
    // parameters, its return type, its declaring type — and asks `ReflectedMemberOfType` for that
    // directly rather than trying to recover it from a type that no longer carries it.
    static func ReflectedMemberTypeInfo(receiverType: TypeInfo, memberName: string): TypeInfo? {
        handle := ReflectedMemberOfType(receiverType, memberName)
        if handle == null {
            return null
        }

        typeOverride := handle.TypeOverride

        property := handle.Property
        if property != null {
            return NullabilityMetadataReflection.ConvertPropertyWithOverride(property, typeOverride)
        }

        field := handle.Field
        if field != null {
            return NullabilityMetadataReflection.ConvertFieldWithOverride(field, typeOverride)
        }

        method := handle.Method
        if method != null {
            return new ReflectionMethodInfo(method, method.get_Name() + "(...)")
        }

        return null
    }

    static func ReflectedMemberOfType(receiverType: TypeInfo, memberName: string): ReflectedMemberHandle? {
        return ReflectedMemberOfTypeForCall(receiverType, memberName, null)
    }

    // A CONSTRUCTED GENERIC IS RESOLVED ON ITS DEFINITION, AND THAT IS THE ONLY WAY TO GET THE RIGHT
    // ANSWER. `CompletionReflectionFacts` closes a known definition by substituting `object` for any
    // argument it cannot spell as a CLR type — which is every N# user type, since none of them is
    // compiled yet — so a member read off the CLOSED type reports `object[] ToArray()` for a
    // `List<WeatherForecast>`. That is not a missing answer, it is a WRONG one, and a hover that
    // states a wrong return type is worse than a hover that states nothing. Reading the member off
    // `List<>` instead leaves every type written as `T`, and the override maps `T` back to the
    // receiver's real argument on the way out.
    //
    // `argumentTypes` IS NULL WHEN THERE IS NO CALL SITE AND IS THE CALL'S OWN ARGUMENT TYPES WHEN
    // THERE IS. The distinction is not "how many arguments" — a call with zero arguments is still a
    // call, and `Next()` means the nullary overload where a bare `Next` means the group.
    static func ReflectedMemberOfTypeForCall(receiverType: TypeInfo, memberName: string, argumentTypes: TypeInfo?[]?): ReflectedMemberHandle? {
        genericType := UnwrapGenericReceiver(receiverType)
        if genericType != null {
            definition := CompletionReflectionFacts.KnownReceiverGenericDefinition(genericType.Name)
            if definition != null && definition.GetGenericArguments().Length == genericType.TypeArguments.Count {
                return ReflectedMemberOfClrType(definition, memberName, argumentTypes, BuildGenericArgumentOverride(definition, genericType))
            }
        }

        clrType := ReflectionReceiverClrType(receiverType)
        if clrType == null {
            return null
        }

        return ReflectedMemberOfClrType(clrType, memberName, argumentTypes, null)
    }

    static func UnwrapGenericReceiver(receiverType: TypeInfo): GenericTypeInfo? {
        genericType := receiverType as GenericTypeInfo
        if genericType != null {
            return genericType
        }

        nullableType := receiverType as NullableTypeInfo
        if nullableType != null {
            return UnwrapGenericReceiver(nullableType.InnerType)
        }

        obliviousType := receiverType as ObliviousTypeInfo
        if obliviousType != null {
            return UnwrapGenericReceiver(obliviousType.InnerType)
        }

        return null
    }

    static func BuildGenericArgumentOverride(definition: Type, genericType: GenericTypeInfo): AnalyzerReflectionTypeOverride {
        overrides := new Dictionary<Type, TypeInfo>()
        parameters := definition.GetGenericArguments()
        index := 0
        while index < parameters.Length && index < genericType.TypeArguments.Count {
            overrides[parameters[index]] = genericType.TypeArguments[index]
            index = index + 1
        }

        return AnalyzerReflectionTypeOverride.Direct(overrides, null)
    }

    // THE PROBE ORDER IS PROPERTY, THEN FIELD, THEN METHOD — the same order and the same reason as
    // `AnalyzerMemberResolution.TryResolveSourceObjectMember`: the property arm answering first is
    // what keeps `get_Length` from being offered as a method, so the accessor filter is a
    // consequence of the order rather than a name test.
    //
    // EVERY READ IS WRAPPED, AND THAT IS NOT DEFENSIVENESS. These types can come from a
    // `MetadataLoadContext` (the CLI) or from the live runtime (the language server), and the two
    // universes fail differently: an ambiguous match throws, and a member read on a poisoned generic
    // instantiation throws `NotSupportedException`. A hover request that throws is a broken editor,
    // so every failure here is a DECLINE and the caller falls back to the bare rendering.
    static func ReflectedMemberOfClrType(clrType: Type, memberName: string, argumentTypes: TypeInfo?[]?, typeOverride: AnalyzerReflectionTypeOverride?): ReflectedMemberHandle? {
        // The flags are a LOCAL, not an inline `|`: an inline flag expression does not type as
        // `BindingFlags` at the call site and the instance call declines as unmodeled. That is
        // `AnalyzerIndexAccess.FindReflectedIndexerProperty`'s note, and it holds here too.
        flags := BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static
        try {
            property := clrType.GetProperty(memberName, flags)
            if property != null {
                return new ReflectedMemberHandle(property, null, null, property.get_Name(), DeclaringTypeText(property.get_DeclaringType()), typeOverride, 1)
            }

            field := clrType.GetField(memberName, flags)
            if field != null {
                return new ReflectedMemberHandle(null, field, null, field.get_Name(), DeclaringTypeText(field.get_DeclaringType()), typeOverride, 1)
            }

            matching := new List<MethodInfo>()
            methods := clrType.GetMethods(flags)
            index := 0
            while index < methods.Length {
                method := methods[index]
                if method.get_Name() == memberName && !method.get_IsSpecialName() {
                    matching.Add(method)
                }

                index = index + 1
            }

            if matching.Count > 0 {
                candidates := matching.ToArray()
                chosen := ChooseReflectedOverload(candidates, argumentTypes)
                return new ReflectedMemberHandle(null, null, chosen, chosen.get_Name(), DeclaringTypeText(chosen.get_DeclaringType()), typeOverride, VisibleOverloadCount(chosen, candidates.Length, argumentTypes))
            }
        } catch {
            return null
        }

        return null
    }

    // THE OVERLOAD THE CALL SITE MEANT.
    //
    // AWAY FROM A CALL SITE THERE IS NOTHING TO GO ON and the first candidate is shown with the
    // count beside it, which is what `(+N overloads)` is for. AT a call site there is: the reader
    // wrote arguments, and showing them a signature their own call could not possibly bind to is
    // worse than showing nothing. `b.Append("x")` showed `Append(char, int)` out of twenty-six and
    // `text.IndexOf("l", StringComparison.Ordinal)` showed `IndexOf(char)` out of ten — both are
    // one-argument-versus-two wrong, which no count makes honest.
    //
    // ARITY IS THE GATE AND TYPE IDENTITY RANKS WITHIN IT. A candidate the call could not call is
    // never the answer, so a wrong arity scores zero however well its types read; among the
    // right-arity candidates each parameter whose type IS the argument's type scores one more.
    //
    // THE COMPARISON IS BY FULL NAME, AND THAT IS A UNIVERSE DECISION RATHER THAN A SHORTCUT. A
    // parameter's type comes from wherever the RECEIVER came from — the compiler's
    // `MetadataLoadContext` for a project receiver, a live `typeof` for a known simple name — while
    // an argument's type is resolved through `CompletionReflectionFacts`, which answers with live
    // types. `Type.IsAssignableFrom` across those two universes answers FALSE rather than throwing,
    // so a predicate built on it would silently degrade to arity and no test would ever say so.
    // A full name is the same string in both universes. It buys identity and not widening, and
    // widening is exactly what arity already covers: `AddDays(1)` has one one-argument overload and
    // reaches `AddDays(double)` without anything having to know that `int` widens.
    static func ChooseReflectedOverload(candidates: MethodInfo[], argumentTypes: TypeInfo?[]?): MethodInfo {
        if argumentTypes == null {
            return candidates[0]
        }

        best := candidates[0]
        bestScore := -1
        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            score := ScoreReflectedOverload(candidate, argumentTypes ?? new TypeInfo?[](0))
            if score > bestScore {
                bestScore = score
                best = candidate
            }

            index = index + 1
        }

        return best
    }

    static func ScoreReflectedOverload(candidate: MethodInfo, argumentTypes: TypeInfo?[]): int {
        parameters := candidate.GetParameters()
        if parameters.Length != argumentTypes.Length {
            return 0
        }

        score := 1
        index := 0
        while index < parameters.Length {
            argumentType := argumentTypes[index]
            if argumentType != null {
                parameterTypeName := ReflectedParameterTypeName(parameters[index])
                argumentTypeName := ReflectedArgumentTypeName(argumentType)
                if parameterTypeName != null && argumentTypeName != null && parameterTypeName == argumentTypeName {
                    score = score + 1
                }
            }

            index = index + 1
        }

        return score
    }

    static func ReflectedParameterTypeName(parameter: ParameterInfo): string? {
        parameterType := parameter.get_ParameterType()
        return parameterType.get_FullName()
    }

    static func ReflectedArgumentTypeName(argumentType: TypeInfo): string? {
        clrType := CompletionReflectionFacts.ResolveCompletionReflectionType(argumentType)
        if clrType == null {
            return null
        }

        return clrType.get_FullName()
    }

    // WHAT THE COUNT MEANS ONCE A CALL SITE HAS SPOKEN. `(+N overloads)` tells the reader there are
    // others they might have meant; where their own arguments picked one, there are not, so the
    // count collapses and the suffix disappears. It collapses ONLY when the chosen candidate takes
    // exactly the arguments written — a call no candidate's arity fits was not narrowed at all, and
    // claiming otherwise would trade a misleading signature for a misleading count.
    static func VisibleOverloadCount(chosen: MethodInfo, candidateCount: int, argumentTypes: TypeInfo?[]?): int {
        if argumentTypes == null {
            return candidateCount
        }

        parameters := chosen.GetParameters()
        if parameters.Length == argumentTypes.Length {
            return 1
        }

        return candidateCount
    }

    // THE FULL NAME, AND THE SIMPLE NAME ONLY WHEN THERE IS NO FULL ONE. `System.String` is what
    // makes the answer navigable by hand; a constructed or generic-parameter type can have no full
    // name at all, and its simple name is better than declining the line over it.
    static func DeclaringTypeText(declaringType: Type?): string? {
        if declaringType == null {
            return null
        }

        fullName := declaringType.get_FullName()
        if fullName == null {
            return declaringType.get_Name()
        }

        return FormatDeclaringTypeName(declaringType, fullName ?? "")
    }

    // A GENERIC DEFINITION'S METADATA NAME IS NOT A NAME ANYONE READS. `List`1` is how the CLR spells
    // it and it is what a member found on a generic DEFINITION reports; the reader wants
    // `System.Collections.Generic.List<T>`. The arity marker is stripped with the estate's own
    // `StripClrGenericArity` and the parameter names are put back, so the answer stays a real,
    // searchable type name.
    static func FormatDeclaringTypeName(declaringType: Type, fullName: string): string {
        if !declaringType.get_IsGenericType() {
            return fullName
        }

        builder := new StringBuilder()
        builder.Append(NullabilityMetadataCore.StripClrGenericArity(fullName))
        builder.Append("<")

        arguments := declaringType.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            if index > 0 {
                builder.Append(", ")
            }

            builder.Append(arguments[index].get_Name())
            index = index + 1
        }

        builder.Append(">")
        return builder.ToString()
    }

    // THE ARRAY ARM LIVES HERE AND NOT IN `CompletionReflectionFacts`, DELIBERATELY. That owner is
    // shared with `nlc query completions`, and teaching it about arrays would start offering
    // `System.Array`'s members after a `.` on an array receiver — a second behaviour change riding
    // on a hover fix. `Length`, `Rank` and `LongLength` are declared on `System.Array`, so the array
    // question is answered here and the completion answer does not move.
    static func ReflectionReceiverClrType(receiverType: TypeInfo): Type? {
        arrayType := receiverType as ArrayTypeInfo
        if arrayType != null {
            return typeof(Array)
        }

        nullableType := receiverType as NullableTypeInfo
        if nullableType != null {
            return ReflectionReceiverClrType(nullableType.InnerType)
        }

        obliviousType := receiverType as ObliviousTypeInfo
        if obliviousType != null {
            return ReflectionReceiverClrType(obliviousType.InnerType)
        }

        return CompletionReflectionFacts.ResolveCompletionReflectionType(receiverType)
    }

    // THE FIRST NAME MATCH ENDS THE SEARCH EVEN WHEN IT HAS NO TYPE. A constructor or a nested type
    // called `Foo` shadows a later field called `Foo` and answers null rather than letting the walk
    // continue — the shipped behaviour, asserted so it cannot drift into "keep looking".
    // A FUNCTION WITH NO RETURN TYPE IS `void`; A FIELD OR PROPERTY WITH NO TYPE IS NULL.
    static func MemberTypeInfoInMembers(compilationUnits: IReadOnlyDictionary<string, CompilationUnit>, members: DeclaredMemberInfo[], memberName: string): TypeInfo? {
        index := 0
        while index < members.Length {
            member := members[index]
            index = index + 1

            if member.Name != memberName {
                continue
            }

            if member.Kind == DeclaredMemberKind.Field {
                fieldType := member.Type
                if fieldType != null {
                    return TypeReferenceToTypeInfo(fieldType, compilationUnits)
                }

                return null
            }

            if member.Kind == DeclaredMemberKind.Property {
                propertyType := member.Type
                if propertyType != null {
                    return TypeReferenceToTypeInfo(propertyType, compilationUnits)
                }

                return null
            }

            if member.Kind == DeclaredMemberKind.Function {
                functionReturnType := member.ReturnType
                if functionReturnType != null {
                    return TypeReferenceToTypeInfo(functionReturnType, compilationUnits)
                }

                return new SimpleTypeInfo("void")
            }

            return null
        }

        return null
    }

    // ── The name walk ───────────────────────────────────────────────────
    // THE SEMANTIC MODEL'S IDENTIFIER TABLE IS ASKED FIRST AND THE PROJECT WALK IS THE FALLBACK,
    // which is why a local variable's type beats a type declaration of the same name.
    static func TypeInfoByName(name: string, semanticModel: SemanticModel?, compilationUnits: IReadOnlyDictionary<string, CompilationUnit>, currentUnit: CompilationUnit): TypeInfo? {
        if semanticModel != null {
            fromModel := semanticModel.LookupIdentifier(name)
            if fromModel != null {
                return fromModel
            }
        }

        return FindTypeInfoByName(compilationUnits, currentUnit, name)
    }

    // VISIBILITY IS NAMESPACE-BASED AND IT IS NOT TRANSITIVE. A unit is searched when its namespace
    // equals the current unit's namespace — INCLUDING when both are absent — or when the current
    // unit imports it by name. An import of a DIFFERENT unit's imports buys nothing.
    static func FindTypeInfoByName(compilationUnits: IReadOnlyDictionary<string, CompilationUnit>, currentUnit: CompilationUnit, name: string): TypeInfo? {
        currentNamespace: string? = null
        currentNamespaceDeclaration := currentUnit.Namespace
        if currentNamespaceDeclaration != null {
            currentNamespace = currentNamespaceDeclaration.Name
        }

        importedNamespaces := new HashSet<string>(StringComparer.Ordinal)
        imports := currentUnit.Imports
        importIndex := 0
        while importIndex < imports.Count {
            importedNamespaces.Add(imports[importIndex].Namespace)
            importIndex = importIndex + 1
        }

        for entry in compilationUnits {
            unit := entry.Value

            unitNamespace: string? = null
            unitNamespaceDeclaration := unit.Namespace
            if unitNamespaceDeclaration != null {
                unitNamespace = unitNamespaceDeclaration.Name
            }

            visible := unitNamespace == currentNamespace
            if !visible && unitNamespace != null {
                visible = importedNamespaces.Contains(unitNamespace)
            }

            if visible {
                declarations := unit.Declarations
                declarationIndex := 0
                while declarationIndex < declarations.Count {
                    typeInfo := FindTypeInfoInDeclaration(declarations[declarationIndex], name, compilationUnits)
                    if typeInfo != null {
                        return typeInfo
                    }

                    declarationIndex = declarationIndex + 1
                }
            }
        }

        return null
    }

    // THE DECLARATION ITSELF IS ASKED FIRST, THEN ITS MEMBERS, AND THE ENUM AND UNION CASE NAMES
    // LAST. That order is observable: a class called `Red` that CONTAINS an enum with a `Red` member
    // answers with the class.
    static func FindTypeInfoInDeclaration(decl: Declaration, name: string, compilationUnits: IReadOnlyDictionary<string, CompilationUnit>): TypeInfo? {
        directMatch := TypeInfoFromDeclaration(decl, name, compilationUnits)
        if directMatch != null {
            return directMatch
        }

        members := DeclarationFacts.GetDeclarationMembers(decl)
        if members != null {
            index := 0
            while index < members.Count {
                member := members[index] as Declaration
                if member != null {
                    memberMatch := FindTypeInfoInDeclaration(member, name, compilationUnits)
                    if memberMatch != null {
                        return memberMatch
                    }
                }

                index = index + 1
            }
        }

        // AN ENUM MEMBER AND A UNION CASE RESOLVE TO THEIR DECLARING TYPE, not to a type of their
        // own — which is how a bare `Red` hovers as `Color`.
        enumDeclaration := decl as EnumDeclaration
        if enumDeclaration != null {
            enumMembers := enumDeclaration.Members
            enumMemberIndex := 0
            while enumMemberIndex < enumMembers.Count {
                enumMember := enumMembers[enumMemberIndex]
                if enumMember.Name == name {
                    return EnumTypeInfoFactory.FromDeclaration(enumDeclaration)
                }

                enumMemberIndex = enumMemberIndex + 1
            }
        }

        unionDeclaration := decl as UnionDeclaration
        if unionDeclaration != null {
            unionCases := unionDeclaration.Cases
            caseIndex := 0
            while caseIndex < unionCases.Count {
                unionCase := unionCases[caseIndex]
                if unionCase.Name == name {
                    return UnionTypeInfoFactory.FromDeclaration(unionDeclaration)
                }

                caseIndex = caseIndex + 1
            }
        }

        return null
    }

    // "WHAT IS THE TYPE OF THE THING CALLED `name`" — so a function answers with its RETURN type, a
    // field and a property with their declared type, and a type declaration with itself.
    // A FIELD WITH NO WRITTEN TYPE DOES NOT MATCH AT ALL, which lets the walk continue past it.
    //
    // ONLY THE THREE VALUE ARMS LIVE HERE. The nine TYPE arms are shared with `FindNamedTypeInfo`
    // through `NamedTypeInfoFromDeclaration` — the C# spelled them out twice, in two switches that
    // had to be kept in step by hand, and the ONLY difference between the two walks is these three
    // arms and where they are applied.
    static func TypeInfoFromDeclaration(decl: Declaration, name: string, compilationUnits: IReadOnlyDictionary<string, CompilationUnit>): TypeInfo? {
        functionDeclaration := decl as FunctionDeclaration
        if functionDeclaration != null {
            if functionDeclaration.Name != name {
                return null
            }

            functionReturnType := functionDeclaration.ReturnType
            if functionReturnType != null {
                return TypeReferenceToTypeInfo(functionReturnType, compilationUnits)
            }

            return new SimpleTypeInfo("void")
        }

        fieldDeclaration := decl as FieldDeclaration
        if fieldDeclaration != null {
            fieldType := fieldDeclaration.Type
            if fieldDeclaration.Name == name && fieldType != null {
                return TypeReferenceToTypeInfo(fieldType, compilationUnits)
            }

            return null
        }

        propertyDeclaration := decl as PropertyDeclaration
        if propertyDeclaration != null {
            if propertyDeclaration.Name == name {
                return TypeReferenceToTypeInfo(propertyDeclaration.Type, compilationUnits)
            }

            return null
        }

        return NamedTypeInfoFromDeclaration(decl, name, compilationUnits)
    }

    // THE NINE TYPE ARMS, WRITTEN ONCE. A declaration form is either a type or it is not, and the
    // arms are disjoint, so the order they are tried in is not observable.
    // AN ALIAS RESOLVES THROUGH to what it aliases while a NEWTYPE STAYS ITSELF — the one place the
    // two wrapper forms part company.
    static func NamedTypeInfoFromDeclaration(decl: Declaration, name: string, compilationUnits: IReadOnlyDictionary<string, CompilationUnit>): TypeInfo? {
        classDeclaration := decl as ClassDeclaration
        if classDeclaration != null {
            if classDeclaration.Name == name {
                return NominalTypeInfoFactory.FromClassDeclaration(classDeclaration)
            }

            return null
        }

        structDeclaration := decl as StructDeclaration
        if structDeclaration != null {
            if structDeclaration.Name == name {
                return NominalTypeInfoFactory.FromStructDeclaration(structDeclaration)
            }

            return null
        }

        recordDeclaration := decl as RecordDeclaration
        if recordDeclaration != null {
            if recordDeclaration.Name == name {
                return NominalTypeInfoFactory.FromRecordDeclaration(recordDeclaration)
            }

            return null
        }

        soaDeclaration := decl as SoaRecordDeclaration
        if soaDeclaration != null {
            if soaDeclaration.Name == name {
                return SoaTypeInfoFactory.FromDeclaration(soaDeclaration)
            }

            return null
        }

        interfaceDeclaration := decl as InterfaceDeclaration
        if interfaceDeclaration != null {
            if interfaceDeclaration.Name == name {
                return NominalTypeInfoFactory.FromInterfaceDeclaration(interfaceDeclaration)
            }

            return null
        }

        enumDeclaration := decl as EnumDeclaration
        if enumDeclaration != null {
            if enumDeclaration.Name == name {
                return EnumTypeInfoFactory.FromDeclaration(enumDeclaration)
            }

            return null
        }

        unionDeclaration := decl as UnionDeclaration
        if unionDeclaration != null {
            if unionDeclaration.Name == name {
                return UnionTypeInfoFactory.FromDeclaration(unionDeclaration)
            }

            return null
        }

        aliasDeclaration := decl as TypeAliasDeclaration
        if aliasDeclaration != null {
            if aliasDeclaration.Name == name {
                return TypeReferenceToTypeInfo(aliasDeclaration.Type, compilationUnits)
            }

            return null
        }

        newtypeDeclaration := decl as NewtypeDeclaration
        if newtypeDeclaration != null {
            if newtypeDeclaration.Name == name {
                return new NewtypeInfo(newtypeDeclaration.Name, newtypeDeclaration.UnderlyingType)
            }

            return null
        }

        return null
    }

    // ── The type-reference walk ─────────────────────────────────────────
    // A SIMPLE NAME IS LOOKED UP PROJECT-WIDE FIRST AND FALLS BACK TO ITSELF. `int` finds no
    // declaration and becomes `SimpleTypeInfo("int")`; a project type finds its declaration and
    // becomes the nominal info, which is what carries members into the member walk.
    // THE FALLBACK ARM RENDERS THE REFERENCE'S OWN TEXT — a tuple, a function type or a by-ref
    // reference has no `TypeInfo` arm here and reports as whatever it prints as.
    static func TypeReferenceToTypeInfo(typeRef: TypeReference, compilationUnits: IReadOnlyDictionary<string, CompilationUnit>): TypeInfo {
        simpleReference := typeRef as SimpleTypeReference
        if simpleReference != null {
            named := FindNamedTypeInfo(compilationUnits, simpleReference.Name)
            if named != null {
                return named
            }

            return new SimpleTypeInfo(simpleReference.Name)
        }

        // A GENERIC REFERENCE IS NEVER LOOKED UP BY NAME — its head stays a name and only its
        // ARGUMENTS are resolved, so `List<Foo>` carries a resolved `Foo` under an unresolved head.
        genericReference := typeRef as GenericTypeReference
        if genericReference != null {
            typeArguments := genericReference.TypeArguments
            resolvedArguments := new List<TypeInfo>()
            argumentIndex := 0
            while argumentIndex < typeArguments.Count {
                resolvedArguments.Add(TypeReferenceToTypeInfo(typeArguments[argumentIndex], compilationUnits))
                argumentIndex = argumentIndex + 1
            }

            return new GenericTypeInfo(genericReference.Name, resolvedArguments)
        }

        arrayReference := typeRef as ArrayTypeReference
        if arrayReference != null {
            return new ArrayTypeInfo(TypeReferenceToTypeInfo(arrayReference.ElementType, compilationUnits))
        }

        nullableReference := typeRef as NullableTypeReference
        if nullableReference != null {
            return new NullableTypeInfo(TypeReferenceToTypeInfo(nullableReference.InnerType, compilationUnits))
        }

        // A UNION IS FLATTENED BEFORE ITS ARMS ARE RESOLVED, so `(A | B) | C` and `A | (B | C)`
        // produce the same three-armed answer.
        unionReference := typeRef as UnionTypeReference
        if unionReference != null {
            flattened := FlattenUnionTypeReference(typeRef)
            resolvedArms := new List<TypeInfo>()
            armIndex := 0
            while armIndex < flattened.Count {
                resolvedArms.Add(TypeReferenceToTypeInfo(flattened[armIndex], compilationUnits))
                armIndex = armIndex + 1
            }

            return new AnonymousUnionTypeInfo(resolvedArms)
        }

        boxedReference := typeRef as object
        renderedText := boxedReference.ToString()
        if renderedText != null {
            return new SimpleTypeInfo(renderedText)
        }

        return new SimpleTypeInfo("unknown")
    }

    // DEPTH-FIRST AND ORDER-PRESERVING. A non-union reference is a one-element list, which is what
    // makes the recursion terminate on every arm.
    static func FlattenUnionTypeReference(typeRef: TypeReference): List<TypeReference> {
        flattened := new List<TypeReference>()

        unionReference := typeRef as UnionTypeReference
        if unionReference == null {
            flattened.Add(typeRef)
            return flattened
        }

        arms := unionReference.Arms
        armIndex := 0
        while armIndex < arms.Count {
            nested := FlattenUnionTypeReference(arms[armIndex])
            nestedIndex := 0
            while nestedIndex < nested.Count {
                flattened.Add(nested[nestedIndex])
                nestedIndex = nestedIndex + 1
            }

            armIndex = armIndex + 1
        }

        return flattened
    }

    // "WHAT TYPE IS CALLED `name`" — TYPE DECLARATIONS ONLY, and TOP-LEVEL ONLY. A nested type is
    // not reachable here even though `FindTypeInfoInDeclaration` would find it, and a function,
    // field or property of that name is deliberately not a type. THE WALK IGNORES NAMESPACES
    // ENTIRELY: unlike `FindTypeInfoByName` this searches every unit in the project.
    static func FindNamedTypeInfo(compilationUnits: IReadOnlyDictionary<string, CompilationUnit>, name: string): TypeInfo? {
        for entry in compilationUnits {
            unit := entry.Value
            declarations := unit.Declarations
            declarationIndex := 0
            while declarationIndex < declarations.Count {
                typeInfo := NamedTypeInfoFromDeclaration(declarations[declarationIndex], name, compilationUnits)
                if typeInfo != null {
                    return typeInfo
                }

                declarationIndex = declarationIndex + 1
            }
        }

        return null
    }

    // ── The null state a type implies ───────────────────────────────────
    // THE REFLECTED ARM IS THE ONLY INTERESTING ONE: a CLR value type that is not `Nullable<T>` can
    // never be null and is NOT-NULL, while every other reflected type is OBLIVIOUS rather than
    // not-null — external metadata whose nullability was never recorded must not produce a
    // confident answer in either direction.
    // EVERYTHING ELSE — including a project class, a record and an array — IS NOT-NULL by default.
    static func DefaultNullState(typeInfo: TypeInfo): NullState {
        nullableType := typeInfo as NullableTypeInfo
        if nullableType != null {
            return NullState.MaybeNull
        }

        unknownType := typeInfo as UnknownTypeInfo
        if unknownType != null {
            return NullState.Unknown
        }

        reflectionType := typeInfo as ReflectionTypeInfo
        if reflectionType != null {
            clrType := reflectionType.Type
            if clrType.get_IsValueType() && Nullable.GetUnderlyingType(clrType) == null {
                return NullState.NotNull
            }

            return NullState.Oblivious
        }

        simpleType := typeInfo as SimpleTypeInfo
        if simpleType != null && simpleType.Name == "null" {
            return NullState.Null
        }

        return NullState.NotNull
    }
}
