namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections
import System.Collections.Generic
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

        return null
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
