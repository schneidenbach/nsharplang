namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// ONE ATTRIBUTE ARGUMENT, MEASURED TWICE.
//
// An attribute argument is asked TWO independent questions and the answers are kept side by side,
// because the second question's answer is meaningless without the first's. The first is "is this a
// compile-time constant at all?"; only when EVERY argument on the attribute answers yes is the
// second asked, "which CLR type does this constant have?", and only then is the attribute's own
// constructor and named-member surface consulted. `ClrType` is therefore null in two different
// situations that must not be confused: the argument was not a constant, or it was a constant whose
// CLR type could not be named. `IsNull` is carried separately from `ClrType` because a null literal
// types as `object` and yet matches any reference or nullable parameter — the type alone cannot say
// that.
class AttributeArgumentValidationInfo {
    argumentValue: Argument
    nameValue: string?
    valueExpression: Expression
    clrTypeValue: Type?
    isNullValue: bool

    Argument: Argument => argumentValue
    Name: string? => nameValue
    Value: Expression => valueExpression
    ClrType: Type? => clrTypeValue
    IsNull: bool => isNullValue

    constructor(argument: Argument, name: string?, value: Expression, clrType: Type?, isNull: bool) {
        argumentValue = argument
        nameValue = name
        valueExpression = value
        clrTypeValue = clrType
        isNullValue = isNull
    }
}

// WHAT AN ATTRIBUTE MEANS.
//
// This owner answers every question a written attribute raises, for every declaration form that can
// carry one: which arguments are compile-time constants, which CLR type each constant has, which
// type the attribute NAME resolves to and whether that type is an attribute at all, which
// constructor accepts the positional arguments, and which named argument is settable and with what
// type. It is the largest single subject in the analyzer and it is one subject: a caller that asks
// half of it gets a wrong answer, because the constructor question is only asked when every argument
// answered the constant question, and the type question is only asked when the attribute type
// resolved.
//
// IT IS A DIRECT CALL, NOT A WALK, AND THAT IS A MEASUREMENT RATHER THAN A PREFERENCE. Every
// collaborator it needs — the scope stack, the declaration context's alias and member-shape doors,
// the external metadata probe, the type resolver's SoA-row rule, the member-access reporter, the
// three span doors, the literal type table, the CLR-type conversion and the well-known-type bag —
// is already owned here, so nothing in the walk ever has to hand control back to a host. There are
// no driver kinds and no suspension points.
//
// THE FOUR-WAY ATTRIBUTE-TYPE DECISION IS ORDERED AND THE ORDER IS OBSERVABLE. A name resolves
// first as a CLR type that derives from `System.Attribute` (the only admissible answer); then as a
// CLR type that does NOT (told to derive from `Attribute`, named by its formatted CLR name); then as
// a SOURCE-declared type, which is split again — one that derives from `Attribute` is told IL
// emission does not support it yet, one that does not is told to derive from `Attribute`, named by
// the type's own `ToString`; and only then is it not found. Reordering these changes which sentence
// a developer reads for the same program.
//
// BOTH CANDIDATE SPELLINGS ARE TRIED, ALWAYS IN THE SAME ORDER: the name as written, then the name
// with `Attribute` appended when it does not already end that way. `[Obsolete]` and
// `[ObsoleteAttribute]` are the same attribute and the written spelling wins the search.
class AnalyzerAttributeValidator {
    diagnostics: AnalyzerDiagnosticSink
    spans: AnalyzerDiagnosticSpans
    scopes: AnalyzerScopeStack
    declarationContext: AnalyzerDeclarationContext
    externalTypeProbe: AnalyzerExternalTypeProbe
    typeResolver: AnalyzerTypeResolver
    memberReports: AnalyzerMemberAccess
    literalExpressions: AnalyzerLiteralExpressions
    clrTypeConversion: AnalyzerClrTypeConversion
    wellKnownTypes: AnalyzerWellKnownTypes?

    constructor(diagnosticSink: AnalyzerDiagnosticSink, spansOwner: AnalyzerDiagnosticSpans, scopeStack: AnalyzerScopeStack, declarations: AnalyzerDeclarationContext, probe: AnalyzerExternalTypeProbe, resolver: AnalyzerTypeResolver, memberAccessOwner: AnalyzerMemberAccess, literals: AnalyzerLiteralExpressions, clrConversion: AnalyzerClrTypeConversion, knownTypes: AnalyzerWellKnownTypes?) {
        diagnostics = diagnosticSink
        spans = spansOwner
        scopes = scopeStack
        declarationContext = declarations
        externalTypeProbe = probe
        typeResolver = resolver
        memberReports = memberAccessOwner
        literalExpressions = literals
        clrTypeConversion = clrConversion
        wellKnownTypes = knownTypes
    }

    // WHICH ATTRIBUTES A DECLARATION CARRIES. Thirteen declaration forms carry attributes and five of
    // them carry parameters that carry their own. A test carries NO attributes of its own — only its
    // table parameters do — and the enumeration reflects that rather than papering over it.
    func ValidateDeclarationAttributeArguments(decl: Declaration) {
        test := decl as TestDeclaration
        if test != null {
            ValidateParameterAttributeArguments(test.TableParameters)
            return
        }

        functionDecl := decl as FunctionDeclaration
        if functionDecl != null {
            ValidateAttributeArguments(functionDecl.Attributes)
            ValidateParameterAttributeArguments(functionDecl.Parameters)
            return
        }

        classDecl := decl as ClassDeclaration
        if classDecl != null {
            ValidateAttributeArguments(classDecl.Attributes)
            ValidateParameterAttributeArguments(classDecl.PrimaryConstructorParameters)
            return
        }

        structDecl := decl as StructDeclaration
        if structDecl != null {
            ValidateAttributeArguments(structDecl.Attributes)
            ValidateParameterAttributeArguments(structDecl.PrimaryConstructorParameters)
            return
        }

        recordDecl := decl as RecordDeclaration
        if recordDecl != null {
            ValidateAttributeArguments(recordDecl.Attributes)
            ValidateParameterAttributeArguments(recordDecl.PrimaryConstructorParameters)
            return
        }

        soaRecordDecl := decl as SoaRecordDeclaration
        if soaRecordDecl != null {
            ValidateAttributeArguments(soaRecordDecl.Attributes)
            return
        }

        interfaceDecl := decl as InterfaceDeclaration
        if interfaceDecl != null {
            ValidateAttributeArguments(interfaceDecl.Attributes)
            return
        }

        unionDecl := decl as UnionDeclaration
        if unionDecl != null {
            ValidateAttributeArguments(unionDecl.Attributes)
            return
        }

        enumDecl := decl as EnumDeclaration
        if enumDecl != null {
            ValidateAttributeArguments(enumDecl.Attributes)
            return
        }

        fieldDecl := decl as FieldDeclaration
        if fieldDecl != null {
            ValidateAttributeArguments(fieldDecl.Attributes)
            return
        }

        propertyDecl := decl as PropertyDeclaration
        if propertyDecl != null {
            ValidateAttributeArguments(propertyDecl.Attributes)
            return
        }

        constructorDecl := decl as ConstructorDeclaration
        if constructorDecl != null {
            ValidateAttributeArguments(constructorDecl.Attributes)
            ValidateParameterAttributeArguments(constructorDecl.Parameters)
            return
        }

        indexerDecl := decl as IndexerDeclaration
        if indexerDecl != null {
            ValidateAttributeArguments(indexerDecl.Attributes)
            ValidateParameterAttributeArguments(indexerDecl.Parameters)
        }
    }

    func ValidateParameterAttributeArguments(parameters: List<Parameter>?) {
        if parameters == null {
            return
        }

        for parameter in parameters {
            ValidateAttributeArguments(parameter.Attributes)
        }
    }

    // THE WHOLE RULE FOR ONE DECLARATION'S ATTRIBUTES, IN THE ORDER THAT MAKES THE DIAGNOSTICS READ.
    //
    // Every argument is measured for constant-ness FIRST and the failures are recorded rather than
    // thrown away — a non-constant argument still occupies its position, so the constructor question
    // can see the shape of the call even when it declines to ask it. The CLR type is inferred only
    // for arguments that WERE constant; a non-constant argument carries a null type and its own
    // report has already been made.
    //
    // THE CONSTRUCTOR AND NAMED-MEMBER QUESTIONS ARE ASKED ONLY WHEN EVERY ARGUMENT WAS CONSTANT.
    // One non-constant argument already produced the sentence the developer must act on; adding "no
    // constructor accepts these types" on top of it would name types that were never computed.
    func ValidateAttributeArguments(attributes: List<AttributeNode>?) {
        if attributes == null {
            return
        }

        for attribute in attributes {
            if IsSystemsPolicyAttribute(attribute) {
                continue
            }

            argumentInfos := new List<AttributeArgumentValidationInfo>()
            allConstantsValid := true
            for argument in attribute.Arguments {
                argumentName: string? = null
                valueExpression: Expression = argument.Value
                NormalizeAttributeArgument(argument, out argumentName, out valueExpression)
                ignoredKind := AttributeArgumentConstantKind.Null
                if !TryValidateAttributeArgumentExpression(valueExpression, out ignoredKind) {
                    allConstantsValid = false
                    argumentInfos.Add(new AttributeArgumentValidationInfo(argument, argumentName, valueExpression, null, false))
                    continue
                }

                inferredType: Type = typeof(object)
                isNull := false
                hasClrType := TryInferAttributeArgumentClrType(valueExpression, out inferredType, out isNull)
                recordedType: Type? = null
                if hasClrType {
                    recordedType = inferredType
                }

                argumentInfos.Add(new AttributeArgumentValidationInfo(argument, argumentName, valueExpression, recordedType, isNull))
            }

            attributeType: Type = typeof(object)
            if TryResolveClrAttributeType(attribute.Name, out attributeType) {
                if allConstantsValid {
                    ValidateClrAttributeArguments(attribute, attributeType, argumentInfos)
                }

                continue
            }

            nonAttributeType: Type = typeof(object)
            if TryResolveNonAttributeClrAttributeCandidate(attribute.Name, out nonAttributeType) {
                ReportAttributeTypeMustDeriveFromAttribute(attribute, NullabilityMetadataReflection.FormatType(nonAttributeType))
                continue
            }

            sourceType: TypeInfo = BuiltInTypes.Unknown
            if TryResolveSourceAttributeCandidate(attribute.Name, out sourceType) {
                if SourceTypeDerivesFromAttribute(sourceType) {
                    ReportSourceDefinedAttributeUnsupported(attribute)
                } else {
                    // The type's OWN display form, read through an `object`-typed local because
                    // `ToString` is declared by the base of the `TypeInfo` hierarchy rather than by
                    // the hierarchy itself. The null fall-back to the written name is the C#'s.
                    boxedSourceType := sourceType as object
                    renderedSourceType := boxedSourceType.ToString()
                    displayName: string = attribute.Name
                    if renderedSourceType != null {
                        displayName = renderedSourceType
                    }

                    ReportAttributeTypeMustDeriveFromAttribute(attribute, displayName)
                }

                continue
            }

            ReportAttributeTypeNotFound(attribute)
        }
    }

    // THE SYSTEMS-POLICY ATTRIBUTES ARE NOT CLR ATTRIBUTES AND ARE NEVER RESOLVED AS ONE. They are
    // language directives that the systems analyzer reads; asking metadata for a type named `hot`
    // would report "attribute type not found" for a construct that is spelled correctly. A DOTTED
    // name is never one of them — `Foo.hot` is a real qualified type reference.
    static func IsSystemsPolicyAttribute(attribute: AttributeNode): bool {
        policyName := attribute.Name
        if policyName.Contains('.') {
            return false
        }

        if policyName.EndsWith("Attribute", StringComparison.Ordinal) {
            policyName = policyName.Substring(0, policyName.Length - 9)
        }

        return policyName == "hot" || policyName == "boundary" || policyName == "alloc" || policyName == "allow" || policyName == "trusted" || policyName == "memory" || policyName == "aotSafe" || policyName == "MustUse"
    }

    // `[Attr(Name = value)]` PARSES AS A POSITIONAL ASSIGNMENT EXPRESSION, NOT AS A NAMED ARGUMENT,
    // and this is where the two spellings become one. Only an assignment whose target is a bare
    // identifier is a named argument; `[Attr(a.b = 1)]` stays positional and is refused downstream as
    // a non-constant.
    static func NormalizeAttributeArgument(argument: Argument, out argumentName: string?, out valueExpression: Expression) {
        argumentName = argument.Name
        valueExpression = argument.Value
        if argument.Name != null {
            return
        }

        assignment := argument.Value as AssignmentExpression
        if assignment == null {
            return
        }

        identifier := assignment.Target as IdentifierExpression
        if identifier == null {
            return
        }

        argumentName = identifier.Name
        valueExpression = assignment.Value
    }

    // ------------------------------------------------------------------------------------------
    // QUESTION ONE — IS THIS ARGUMENT A COMPILE-TIME CONSTANT, AND OF WHAT KIND?
    //
    // The KIND is not the CLR type; it is the coarse family the operator rules work over, and it is
    // what lets `A.B | C.D` be admitted as an enum combination while `1 | "x"` is not. Every arm
    // that answers FALSE has already reported — this walk never returns a silent refusal.
    // ------------------------------------------------------------------------------------------
    func TryValidateAttributeArgumentExpression(expression: Expression, out kind: AttributeArgumentConstantKind): bool {
        intLiteral := expression as IntLiteralExpression
        if intLiteral != null {
            kind = AttributeArgumentConstantKind.Integer
            return true
        }

        floatLiteral := expression as FloatLiteralExpression
        if floatLiteral != null {
            kind = AttributeArgumentConstantKind.Floating
            return true
        }

        charLiteral := expression as CharLiteralExpression
        if charLiteral != null {
            kind = AttributeArgumentConstantKind.Char
            return true
        }

        stringLiteral := expression as StringLiteralExpression
        if stringLiteral != null {
            kind = AttributeArgumentConstantKind.String
            return true
        }

        boolLiteral := expression as BoolLiteralExpression
        if boolLiteral != null {
            kind = AttributeArgumentConstantKind.Bool
            return true
        }

        nullLiteral := expression as NullLiteralExpression
        if nullLiteral != null {
            kind = AttributeArgumentConstantKind.Null
            return true
        }

        // A `typeof` inside an attribute is a constant, and it is ALSO a written type reference —
        // resolving it records it, and an SoA row named there gets the same refusal it gets anywhere
        // else. The rule belongs to the type resolver and is asked, not re-implemented.
        typeOfExpression := expression as TypeOfExpression
        if typeOfExpression != null {
            typeResolver.ReportSoaRowTypeReferencesIn(typeOfExpression.Type)
            kind = AttributeArgumentConstantKind.Type
            return true
        }

        // `nameof` ANSWERS A STRING AND STILL FAILS: the kind is String either way, because the
        // sentence the developer reads is about the TARGET, and a downstream type mismatch on top of
        // it would name a type nobody wrote.
        nameofExpression := expression as NameofExpression
        if nameofExpression != null {
            if IsSupportedNameofAttributeTarget(nameofExpression.Target) {
                kind = AttributeArgumentConstantKind.String
                return true
            }

            ReportUnsupportedAttributeArgument(nameofExpression.Target, "nameof target")
            kind = AttributeArgumentConstantKind.String
            return false
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            return TryValidateAttributeMemberAccess(memberAccess, out kind)
        }

        arrayLiteral := expression as ArrayLiteralExpression
        if arrayLiteral != null {
            return TryValidateAttributeArrayArgument(arrayLiteral, out kind)
        }

        unary := expression as UnaryExpression
        if unary != null {
            return TryValidateAttributeUnaryArgument(unary, out kind)
        }

        binary := expression as BinaryExpression
        if binary != null {
            return TryValidateAttributeBinaryArgument(binary, out kind)
        }

        ReportUnsupportedAttributeArgument(expression, DescribeAttributeArgumentForDiagnostic(expression))
        kind = AttributeArgumentConstantKind.UnknownStaticMember
        return false
    }

    // AN ARRAY'S ELEMENTS ARE ALL MEASURED EVEN AFTER ONE FAILS, so a developer sees every bad
    // element at once rather than one per build. `null` elements are SKIPPED when fixing the
    // element kind — `[null, "a"]` is a string array with a null hole, not a mixed-type array.
    func TryValidateAttributeArrayArgument(arrayLiteral: ArrayLiteralExpression, out kind: AttributeArgumentConstantKind): bool {
        kind = AttributeArgumentConstantKind.Array
        elementKind := AttributeArgumentConstantKind.Null
        hasElementKind := false
        valid := true
        for element in arrayLiteral.Elements {
            currentKind := AttributeArgumentConstantKind.Null
            if !TryValidateAttributeArgumentExpression(element, out currentKind) {
                valid = false
                continue
            }

            if currentKind == AttributeArgumentConstantKind.Null {
                continue
            }

            if !hasElementKind {
                elementKind = currentKind
                hasElementKind = true
            }

            if elementKind != currentKind {
                ReportUnsupportedAttributeArgument(element, "mixed-type array element")
                valid = false
            }
        }

        return valid
    }

    // THREE UNARY OPERATORS ARE ADMITTED AND EACH ONLY OVER ITS OWN OPERAND KIND: negation over a
    // number, `!` over a bool, `~` over an integer. A refused operator STILL ANSWERS THE OPERAND'S
    // KIND, which is what keeps `-x | 1` from being reported twice.
    func TryValidateAttributeUnaryArgument(unary: UnaryExpression, out kind: AttributeArgumentConstantKind): bool {
        operandKind := AttributeArgumentConstantKind.Null
        if !TryValidateAttributeArgumentExpression(unary.Operand, out operandKind) {
            kind = operandKind
            return false
        }

        if unary.Operator == UnaryOperator.Negate && (operandKind == AttributeArgumentConstantKind.Integer || operandKind == AttributeArgumentConstantKind.Floating) {
            kind = operandKind
            return true
        }

        if unary.Operator == UnaryOperator.Not && operandKind == AttributeArgumentConstantKind.Bool {
            kind = AttributeArgumentConstantKind.Bool
            return true
        }

        if unary.Operator == UnaryOperator.BitwiseNot && operandKind == AttributeArgumentConstantKind.Integer {
            kind = AttributeArgumentConstantKind.Integer
            return true
        }

        ReportUnsupportedAttributeOperator(unary, OperatorFacts.GetUnaryText(unary.Operator))
        kind = operandKind
        return false
    }

    // BOTH OPERANDS ARE ALWAYS MEASURED, EVEN WHEN THE LEFT ONE FAILED — the right one's own report
    // is worth having. Only the three bitwise operators are admitted, and only over two integers,
    // two enums, or anything paired with an UNRESOLVED static member, which is the shape of a flags
    // combination whose owner could not be found and which has already been reported once.
    func TryValidateAttributeBinaryArgument(binary: BinaryExpression, out kind: AttributeArgumentConstantKind): bool {
        leftKind := AttributeArgumentConstantKind.Null
        rightKind := AttributeArgumentConstantKind.Null
        leftValid := TryValidateAttributeArgumentExpression(binary.Left, out leftKind)
        rightValid := TryValidateAttributeArgumentExpression(binary.Right, out rightKind)
        kind = leftKind
        if !leftValid || !rightValid {
            return false
        }

        if binary.Operator != BinaryOperator.BitwiseOr && binary.Operator != BinaryOperator.BitwiseAnd && binary.Operator != BinaryOperator.BitwiseXor {
            ReportUnsupportedAttributeOperator(binary, OperatorFacts.GetBinaryText(binary.Operator))
            return false
        }

        bothIntegers := leftKind == AttributeArgumentConstantKind.Integer && rightKind == AttributeArgumentConstantKind.Integer
        bothEnums := leftKind == AttributeArgumentConstantKind.Enum && rightKind == AttributeArgumentConstantKind.Enum
        eitherUnknown := leftKind == AttributeArgumentConstantKind.UnknownStaticMember || rightKind == AttributeArgumentConstantKind.UnknownStaticMember
        if bothIntegers || bothEnums || eitherUnknown {
            if leftKind == AttributeArgumentConstantKind.Enum || rightKind == AttributeArgumentConstantKind.Enum {
                kind = AttributeArgumentConstantKind.Enum
            } else {
                kind = AttributeArgumentConstantKind.Integer
            }

            return true
        }

        ReportUnsupportedAttributeOperator(binary, OperatorFacts.GetBinaryText(binary.Operator))
        return false
    }

    // A STATIC MEMBER READ IS THE ONLY NON-LITERAL CONSTANT AN ATTRIBUTE ADMITS, and telling the four
    // container shapes apart is the whole of this member. THE PROBE ORDER IS OBSERVABLE: a SOURCE
    // enum first (its members are known from the declaration), then a well-known built-in keyword
    // (`int.MaxValue`), then an external metadata type (`System.String.Empty`), and only then the
    // fall-through — a container that resolved to SOMETHING the analyzer knows but is not an enum or
    // a metadata type is admitted as an unknown static member rather than refused, because a source
    // constant's value is not this owner's question and a false refusal is worse than a missed one.
    func TryValidateAttributeMemberAccess(memberAccess: MemberAccessExpression, out kind: AttributeArgumentConstantKind): bool {
        containerName := ""
        if !TryGetQualifiedName(memberAccess.Object, out containerName) {
            ReportUnsupportedAttributeArgument(memberAccess, "member access")
            kind = AttributeArgumentConstantKind.UnknownStaticMember
            return false
        }

        looked := scopes.LookupType(containerName)
        lookedOrUnknown: TypeInfo = BuiltInTypes.Unknown
        if looked != null {
            lookedOrUnknown = looked
        }

        resolvedType := declarationContext.ResolveDeclaredAlias(lookedOrUnknown)
        enumType := resolvedType as EnumTypeInfo
        if enumType != null {
            if !TypeInfoIdentityFacts.HasSourceEnumMember(enumType, memberAccess.MemberName) {
                ReportUndefinedAttributeStaticMember(enumType, memberAccess)
                kind = AttributeArgumentConstantKind.UnknownStaticMember
                return false
            }

            kind = AttributeArgumentConstantKind.Enum
            return true
        }

        builtInCandidate := AnalyzerWellKnownTypeFacts.BuiltInMetadataClrType(wellKnownTypes, containerName)
        if builtInCandidate != null {
            builtInType: Type = builtInCandidate
            return TryValidateAttributeRuntimeStaticMemberAccess(new ReflectionTypeInfo(builtInType), builtInType, memberAccess, out kind)
        }

        external := externalTypeProbe.ResolveExternalType(containerName)
        if external != null {
            externalReflection := external as ReflectionTypeInfo
            if externalReflection != null {
                return TryValidateAttributeRuntimeStaticMemberAccess(externalReflection, externalReflection.Type, memberAccess, out kind)
            }
        }

        if !BuiltInTypes.IsUnknown(resolvedType) {
            kind = AttributeArgumentConstantKind.UnknownStaticMember
            return true
        }

        ReportUnsupportedAttributeArgument(memberAccess, "member access")
        kind = AttributeArgumentConstantKind.UnknownStaticMember
        return false
    }

    // THE SAME QUESTION AGAINST METADATA. A runtime enum's member must exist; anything else must be
    // a readable static field or property, and its CLR type decides the kind. A member that does not
    // exist gets the SAME "undefined member" report a normal member access gets, through the same
    // owner, so the sentence and its suggestions match what the developer sees elsewhere.
    func TryValidateAttributeRuntimeStaticMemberAccess(receiverType: ReflectionTypeInfo, runtimeType: Type, memberAccess: MemberAccessExpression, out kind: AttributeArgumentConstantKind): bool {
        if IsRuntimeEnumType(runtimeType) {
            if !TypeInfoIdentityFacts.HasRuntimeEnumMember(runtimeType, memberAccess.MemberName) {
                ReportUndefinedAttributeStaticMember(receiverType, memberAccess)
                kind = AttributeArgumentConstantKind.UnknownStaticMember
                return false
            }

            kind = AttributeArgumentConstantKind.Enum
            return true
        }

        memberType: Type = typeof(object)
        if !TryGetRuntimeStaticAttributeMemberType(runtimeType, memberAccess.MemberName, out memberType) {
            ReportUndefinedAttributeStaticMember(receiverType, memberAccess)
            kind = AttributeArgumentConstantKind.UnknownStaticMember
            return false
        }

        kind = ClassifyAttributeRuntimeType(memberType)
        return true
    }

    func ReportUndefinedAttributeStaticMember(receiverType: TypeInfo, memberAccess: MemberAccessExpression) {
        memberReports.ReportUndefinedMemberAt(receiverType, memberAccess.MemberName, memberAccess.Line, spans.GetMemberNameColumn(memberAccess), true, null)
    }

    // WHICH KIND A METADATA TYPE IS. Arrays and enums are decided by shape; everything else is
    // decided by FULL NAME against the closed set the CLR admits in attribute metadata. A type
    // outside that set is `UnknownStaticMember` rather than an error — the constant exists, its kind
    // is simply not one the operator rules work over.
    static func ClassifyAttributeRuntimeType(clrType: Type): AttributeArgumentConstantKind {
        if clrType.get_IsArray() {
            return AttributeArgumentConstantKind.Array
        }

        if IsRuntimeEnumType(clrType) {
            return AttributeArgumentConstantKind.Enum
        }

        fullName := clrType.get_FullName()
        if fullName == "System.Boolean" {
            return AttributeArgumentConstantKind.Bool
        }

        if fullName == "System.Byte" || fullName == "System.SByte" || fullName == "System.Int16" || fullName == "System.UInt16" || fullName == "System.Int32" || fullName == "System.UInt32" || fullName == "System.Int64" || fullName == "System.UInt64" {
            return AttributeArgumentConstantKind.Integer
        }

        if fullName == "System.Single" || fullName == "System.Double" || fullName == "System.Decimal" {
            return AttributeArgumentConstantKind.Floating
        }

        if fullName == "System.Char" {
            return AttributeArgumentConstantKind.Char
        }

        if fullName == "System.String" {
            return AttributeArgumentConstantKind.String
        }

        if fullName == "System.Type" {
            return AttributeArgumentConstantKind.Type
        }

        return AttributeArgumentConstantKind.UnknownStaticMember
    }

    // A METADATA-LOADED ENUM DOES NOT ALWAYS ANSWER `IsEnum`, because a `MetadataLoadContext` type's
    // `IsEnum` depends on the core assembly being the one it was loaded against. The base-type name
    // is the second door and it is the one that answers for reference-only loads.
    static func IsRuntimeEnumType(clrType: Type): bool {
        if clrType.get_IsEnum() {
            return true
        }

        baseType := clrType.get_BaseType()
        if baseType == null {
            return false
        }

        return baseType.get_FullName() == "System.Enum"
    }

    // `nameof` ADMITS A NAME AND A DOTTED PATH OF NAMES, AND NOTHING ELSE. A null-conditional link in
    // the chain is refused: `nameof(a?.b)` is not a name.
    static func IsSupportedNameofAttributeTarget(target: Expression): bool {
        identifier := target as IdentifierExpression
        if identifier != null {
            return true
        }

        memberAccess := target as MemberAccessExpression
        if memberAccess != null && !memberAccess.IsNullConditional {
            return IsSupportedNameofAttributeTarget(memberAccess.Object)
        }

        return false
    }

    // THE DOTTED NAME AN EXPRESSION SPELLS, or false when it spells none. This is shared with the
    // DEFAULT-PARAMETER rule, which asks the same question of an enum member's owner — a default
    // value and an attribute argument are both metadata constants and both name their owner the same
    // way. A null-conditional link answers false: `a?.B` names nothing.
    static func TryGetQualifiedName(expression: Expression, out name: string): bool {
        identifier := expression as IdentifierExpression
        if identifier != null {
            name = identifier.Name
            return true
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null && !memberAccess.IsNullConditional {
            parentName := ""
            if TryGetQualifiedName(memberAccess.Object, out parentName) {
                name = parentName + "." + memberAccess.MemberName
                return true
            }
        }

        name = ""
        return false
    }

    func ReportUnsupportedAttributeArgument(expression: Expression, description: string) {
        span := spans.GetExpressionDiagnosticSpan(expression)
        diagnostics.Report(ErrorCode.ConstantRequired, "Attribute arguments must be compile-time constants; " + description + " is not supported here", span.Line, span.Column, "Use a literal, typeof(...), nameof(...), enum/static constant, or an array of those constants.", span.Length)
    }

    // WHAT TO CALL AN ARGUMENT THAT IS NOT CONSTANT. An identifier and a member access are named
    // outright because their generic descriptions read badly in this sentence; a description that
    // already reads as a phrase is used as written; anything else is lower-cased and suffixed.
    static func DescribeAttributeArgumentForDiagnostic(expression: Expression): string {
        description := AnalyzerExpressionStatements.DescribeExpression(expression)
        identifier := expression as IdentifierExpression
        if identifier != null {
            return "identifier"
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            return "member access"
        }

        if description.Contains(' ') {
            return description
        }

        return char.ToLowerInvariant(description[0]).ToString() + description.Substring(1) + " expression"
    }

    // THE OPERATOR REFUSAL ANCHORS ON THE OPERATOR ITSELF FOR A BINARY EXPRESSION, not on the whole
    // expression — the developer must change the operator, and the squiggle says which one.
    func ReportUnsupportedAttributeOperator(expression: Expression, operatorText: string) {
        binary := expression as BinaryExpression
        span: DiagnosticSpan = spans.GetExpressionDiagnosticSpan(expression)
        if binary != null {
            span = AnalyzerDiagnosticSpanFacts.GetBinaryOperatorDiagnosticSpan(binary)
        }

        diagnostics.Report(ErrorCode.ConstantRequired, "Attribute arguments must be compile-time constants; operator '" + operatorText + "' is not supported here", span.Line, span.Column, "Use a literal, typeof(...), nameof(...), enum/static constant, or an array of those constants.", span.Length)
    }

    // ------------------------------------------------------------------------------------------
    // QUESTION TWO — WHICH TYPE IS THIS ATTRIBUTE, AND IS IT AN ATTRIBUTE AT ALL?
    // ------------------------------------------------------------------------------------------

    func TryResolveClrAttributeType(attributeName: string, out attributeType: Type): bool {
        for candidate in GetClrAttributeNameCandidates(attributeName) {
            resolved := externalTypeProbe.ResolveExternalType(candidate)
            if resolved != null {
                reflection := resolved as ReflectionTypeInfo
                if reflection != null && IsClrAttributeType(reflection.Type) {
                    attributeType = reflection.Type
                    return true
                }
            }
        }

        attributeType = typeof(object)
        return false
    }

    // THE SAME SEARCH WITHOUT THE `Attribute` REQUIREMENT. It exists so a name that resolves to a
    // real CLR type which simply is not an attribute gets "must derive from System.Attribute"
    // instead of "type not found" — the developer named a type that exists and the sentence says so.
    func TryResolveNonAttributeClrAttributeCandidate(attributeName: string, out clrType: Type): bool {
        for candidate in GetClrAttributeNameCandidates(attributeName) {
            resolved := externalTypeProbe.ResolveExternalType(candidate)
            if resolved != null {
                reflection := resolved as ReflectionTypeInfo
                if reflection != null {
                    clrType = reflection.Type
                    return true
                }
            }
        }

        clrType = typeof(object)
        return false
    }

    // THE SOURCE DOOR, WITH THE NESTED-TYPE FALLBACK. The scope stack answers a simple or imported
    // name; a dotted name that names a NESTED source type is only found through the type resolver's
    // own dotted door, and it is asked exactly when the scope stack declined.
    func TryResolveSourceAttributeCandidate(attributeName: string, out sourceType: TypeInfo): bool {
        for candidate in GetClrAttributeNameCandidates(attributeName) {
            candidateType: TypeInfo = BuiltInTypes.Unknown
            found := false
            looked := scopes.LookupType(candidate)
            if looked != null {
                candidateType = looked
                found = true
            } else {
                nested: TypeInfo = BuiltInTypes.Unknown
                if typeResolver.TryResolveDottedNestedType(candidate, out nested) {
                    candidateType = nested
                    found = true
                }
            }

            if found {
                aliased := declarationContext.ResolveDeclaredAlias(candidateType)
                if IsSourceDeclaredAttributeCandidate(aliased) {
                    sourceType = aliased
                    return true
                }
            }
        }

        sourceType = BuiltInTypes.Unknown
        return false
    }

    // EVERY SOURCE-DECLARED TYPE SHAPE COUNTS AS A CANDIDATE, including ones that can never be an
    // attribute (an interface, an enum, a newtype). That is deliberate: a candidate that is the
    // wrong SHAPE is told "must derive from System.Attribute", which is true and actionable, rather
    // than "not found", which is false.
    static func IsSourceDeclaredAttributeCandidate(candidate: TypeInfo): bool {
        classType := candidate as ClassTypeInfo
        if classType != null {
            return true
        }

        structType := candidate as StructTypeInfo
        if structType != null {
            return true
        }

        recordType := candidate as RecordTypeInfo
        if recordType != null {
            return true
        }

        interfaceType := candidate as InterfaceTypeInfo
        if interfaceType != null {
            return true
        }

        unionType := candidate as UnionTypeInfo
        if unionType != null {
            return true
        }

        enumType := candidate as EnumTypeInfo
        if enumType != null {
            return true
        }

        soaRecordType := candidate as SoaRecordTypeInfo
        if soaRecordType != null {
            return true
        }

        newtypeInfo := candidate as NewtypeInfo
        return newtypeInfo != null
    }

    // THE BASE CHAIN IS WALKED BY FULL NAME RATHER THAN BY IDENTITY, because a `MetadataLoadContext`
    // `System.Attribute` and the compiler's own are different `Type` instances for the same type.
    static func IsClrAttributeType(clrType: Type): bool {
        current: Type? = clrType
        while current != null {
            step: Type = current
            if step.get_FullName() == "System.Attribute" {
                return true
            }

            current = step.get_BaseType()
        }

        return false
    }

    static func GetClrAttributeNameCandidates(attributeName: string): List<string> {
        candidates := new List<string>()
        candidates.Add(attributeName)
        if !attributeName.EndsWith("Attribute", StringComparison.Ordinal) {
            candidates.Add(attributeName + "Attribute")
        }

        return candidates
    }

    func SourceTypeDerivesFromAttribute(candidate: TypeInfo): bool {
        return SourceTypeDerivesFromAttributeCore(candidate, new HashSet<object>())
    }

    // A SOURCE CLASS DERIVES FROM `Attribute` WHEN ITS BASE CHAIN REACHES A METADATA TYPE THAT DOES.
    // The chain is walked through the ALIAS door at every step, and a `seen` set guards the cycle a
    // malformed program can write — a class whose base is itself must answer false, not hang.
    func SourceTypeDerivesFromAttributeCore(candidate: TypeInfo, seenClasses: HashSet<object>): bool {
        resolved := declarationContext.ResolveDeclaredAlias(candidate)
        reflection := resolved as ReflectionTypeInfo
        if reflection != null {
            return IsClrAttributeType(reflection.Type)
        }

        classType := resolved as ClassTypeInfo
        if classType == null {
            return false
        }

        classObject := classType as object
        if !seenClasses.Add(classObject) {
            return false
        }

        shape := new AnalyzerSourceMemberShape()
        if !declarationContext.TryGetSourceMemberShape(classType, null, out shape) {
            return false
        }

        declaredBase := shape.BaseType
        if declaredBase == null {
            return false
        }

        baseType := declarationContext.ResolveDeclaredAlias(declaredBase)
        baseReflection := baseType as ReflectionTypeInfo
        if baseReflection != null && IsClrAttributeType(baseReflection.Type) {
            return true
        }

        return SourceTypeDerivesFromAttributeCore(baseType, seenClasses)
    }

    func ReportAttributeTypeNotFound(attribute: AttributeNode) {
        span := AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute)
        suggestedAttributeName := attribute.Name
        if !attribute.Name.EndsWith("Attribute", StringComparison.Ordinal) {
            suggestedAttributeName = attribute.Name + "Attribute"
        }

        diagnostics.Report(ErrorCode.TypeNotFound, "Attribute type '" + attribute.Name + "' not found", span.Line, span.Column, "Check the spelling, add the missing 'import', or define an attribute class named '" + suggestedAttributeName + "'.", span.Length)
    }

    func ReportAttributeTypeMustDeriveFromAttribute(attribute: AttributeNode, typeName: string) {
        span := AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute)
        diagnostics.Report(ErrorCode.TypeMismatch, "Attribute type '" + typeName + "' must derive from System.Attribute", span.Line, span.Column, "Use a CLR attribute type or define a class that inherits System.Attribute.", span.Length)
    }

    func ReportSourceDefinedAttributeUnsupported(attribute: AttributeNode) {
        span := AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute)
        diagnostics.Report(ErrorCode.FeatureNotImplemented, "Source-defined attribute '" + attribute.Name + "' is not supported by IL emission yet", span.Line, span.Column, "Use an attribute type from a referenced CLR assembly for now.", span.Length)
    }

    // ------------------------------------------------------------------------------------------
    // QUESTION THREE — DOES THIS ATTRIBUTE ACCEPT THESE ARGUMENTS?
    //
    // Named arguments are checked FIRST and each one independently, so every bad name and every bad
    // named type is reported in one build. The positional question is asked ONCE, at the end, and
    // only when every positional argument named a CLR type — an unnamed type would make the
    // "no constructor accepts these types" sentence list a type that was never computed.
    // ------------------------------------------------------------------------------------------
    func ValidateClrAttributeArguments(attribute: AttributeNode, attributeType: Type, argumentInfos: List<AttributeArgumentValidationInfo>) {
        for argumentInfo in argumentInfos {
            declaredName := argumentInfo.Name
            if declaredName != null {
                ValidateNamedAttributeArgument(attributeType, argumentInfo, declaredName)
            }
        }

        positionalArguments := new List<AttributeArgumentValidationInfo>()
        anyUntyped := false
        for argumentInfo in argumentInfos {
            if argumentInfo.Name == null {
                positionalArguments.Add(argumentInfo)
                if argumentInfo.ClrType == null {
                    anyUntyped = true
                }
            }
        }

        if anyUntyped {
            return
        }

        if !HasMatchingAttributeConstructor(attributeType, positionalArguments) {
            ReportNoMatchingAttributeConstructor(attribute, attributeType, positionalArguments)
        }
    }

    // ONE NAMED ARGUMENT. It must name a settable member, and — when its own type was inferred — that
    // member's type must accept it. An argument whose CLR type could NOT be inferred is left alone:
    // it was not a constant, and its own report has already been made.
    func ValidateNamedAttributeArgument(attributeType: Type, argumentInfo: AttributeArgumentValidationInfo, argumentName: string) {
        memberType: Type = typeof(object)
        if !TryGetSettableAttributeNamedMemberType(attributeType, argumentName, out memberType) {
            ReportUnknownAttributeNamedArgument(attributeType, argumentInfo)
            return
        }

        argumentClrType := argumentInfo.ClrType
        if argumentClrType != null && !IsAttributeArgumentCompatible(memberType, argumentClrType, argumentInfo.IsNull) {
            ReportAttributeNamedArgumentTypeMismatch(attributeType, argumentInfo, memberType)
        }
    }

    // A NAMED ARGUMENT MUST NAME SOMETHING THE CLR CAN SET IN METADATA: a public instance property
    // with a public setter and no index parameters, or a public instance field that is neither
    // `readonly` nor `const`. An indexer is excluded because `[Attr(Item = 1)]` has nowhere to put
    // the index.
    static func TryGetSettableAttributeNamedMemberType(attributeType: Type, memberName: string, out memberType: Type): bool {
        instanceFlags := BindingFlags.Public | BindingFlags.Instance
        property := attributeType.GetProperty(memberName, instanceFlags)
        if property != null {
            setter := property.get_SetMethod()
            if setter != null && setter.get_IsPublic() && property.GetIndexParameters().Length == 0 {
                memberType = property.get_PropertyType()
                return true
            }
        }

        field := attributeType.GetField(memberName, instanceFlags)
        if field != null && !field.get_IsInitOnly() && !field.get_IsLiteral() {
            memberType = field.get_FieldType()
            return true
        }

        memberType = typeof(object)
        return false
    }

    // ANY public constructor of the right arity whose parameters all accept the arguments. The FIRST
    // match wins and no further constructor is measured, which matches the metadata question being
    // asked — "can this attribute be constructed?" — rather than overload resolution's.
    static func HasMatchingAttributeConstructor(attributeType: Type, positionalArguments: List<AttributeArgumentValidationInfo>): bool {
        instanceFlags := BindingFlags.Public | BindingFlags.Instance
        constructors := attributeType.GetConstructors(instanceFlags)
        for constructor in constructors {
            parameters := constructor.GetParameters()
            if parameters.Length != positionalArguments.Count {
                continue
            }

            matches := true
            index := 0
            while index < parameters.Length {
                parameter := parameters[index]
                argumentInfo := positionalArguments[index]
                argumentClrType := argumentInfo.ClrType
                compatible := false
                if argumentClrType != null {
                    compatible = IsAttributeArgumentCompatible(parameter.get_ParameterType(), argumentClrType, argumentInfo.IsNull)
                }

                if !compatible {
                    matches = false
                    break
                }

                index = index + 1
            }

            if matches {
                return true
            }
        }

        return false
    }

    // WHAT ONE ARGUMENT MAY FILL. `null` is decided by the PARAMETER alone — anything that is not a
    // non-nullable value type takes it, whatever the argument's nominal `object` type says. An enum
    // parameter also takes its own underlying integer, which is how `[Attr(1)]` fills a flags
    // parameter. Arrays are compared element-wise under the same three rules, one level deep, which
    // is as deep as attribute metadata goes.
    static func IsAttributeArgumentCompatible(parameterType: Type, argumentType: Type, isNull: bool): bool {
        if isNull {
            if !parameterType.get_IsValueType() {
                return true
            }

            return Nullable.GetUnderlyingType(parameterType) != null
        }

        if parameterType == argumentType || parameterType.IsAssignableFrom(argumentType) {
            return true
        }

        if MatchesRuntimeEnumUnderlyingType(parameterType, argumentType) {
            return true
        }

        if parameterType.get_IsArray() && argumentType.get_IsArray() {
            parameterElementCandidate := parameterType.GetElementType()
            argumentElementCandidate := argumentType.GetElementType()
            if parameterElementCandidate == null || argumentElementCandidate == null {
                return false
            }

            parameterElementType: Type = parameterElementCandidate
            argumentElementType: Type = argumentElementCandidate
            if parameterElementType == argumentElementType || parameterElementType.IsAssignableFrom(argumentElementType) {
                return true
            }

            return MatchesRuntimeEnumUnderlyingType(parameterElementType, argumentElementType)
        }

        return false
    }

    // AN ENUM PARAMETER ALSO TAKES ITS UNDERLYING INTEGER. A non-enum parameter has no underlying
    // type and therefore matches nothing here — the C# asked this with a `Type? == Type` comparison
    // whose null case answered false, and this says the same thing out loud.
    static func MatchesRuntimeEnumUnderlyingType(parameterType: Type, argumentType: Type): bool {
        underlying := TryGetRuntimeEnumUnderlyingType(parameterType)
        if underlying == null {
            return false
        }

        knownUnderlying: Type = underlying
        return knownUnderlying == argumentType
    }

    static func TryGetRuntimeEnumUnderlyingType(clrType: Type): Type? {
        if !clrType.get_IsEnum() {
            return null
        }

        return Enum.GetUnderlyingType(clrType)
    }

    func ReportUnknownAttributeNamedArgument(attributeType: Type, argumentInfo: AttributeArgumentValidationInfo) {
        span := spans.GetAttributeArgumentDiagnosticSpan(argumentInfo.Argument, argumentInfo.Value)
        argumentName := argumentInfo.Name
        if argumentName == null {
            argumentName = ""
        }

        diagnostics.Report(ErrorCode.UndefinedMember, "Attribute '" + GetAttributeDisplayName(attributeType) + "' has no public settable property or field named '" + argumentName + "'", span.Line, span.Column, "Use a named argument exposed by the attribute type.", span.Length)
    }

    func ReportAttributeNamedArgumentTypeMismatch(attributeType: Type, argumentInfo: AttributeArgumentValidationInfo, memberType: Type) {
        span := spans.GetAttributeArgumentDiagnosticSpan(argumentInfo.Argument, argumentInfo.Value)
        argumentName := argumentInfo.Name
        if argumentName == null {
            argumentName = ""
        }

        actualCandidate := argumentInfo.ClrType
        actualText := ""
        if actualCandidate != null {
            actualType: Type = actualCandidate
            actualText = NullabilityMetadataReflection.FormatType(actualType)
        }

        diagnostics.Report(ErrorCode.TypeMismatch, "Attribute named argument '" + argumentName + "' on '" + GetAttributeDisplayName(attributeType) + "' expects '" + NullabilityMetadataReflection.FormatType(memberType) + "' but got '" + actualText + "'", span.Line, span.Column, "Use a value whose type matches the attribute property or field.", span.Length)
    }

    // THE CONSTRUCTOR REFUSAL ANCHORS ON THE FIRST POSITIONAL ARGUMENT when there is one, and on the
    // attribute itself when there is none — `[Attr]` on an attribute with no parameterless
    // constructor has no argument to point at.
    func ReportNoMatchingAttributeConstructor(attribute: AttributeNode, attributeType: Type, positionalArguments: List<AttributeArgumentValidationInfo>) {
        span: DiagnosticSpan = AnalyzerDiagnosticSpanFacts.GetAttributeFallbackDiagnosticSpan(attribute)
        if positionalArguments.Count > 0 {
            firstArgument := positionalArguments[0]
            span = spans.GetExpressionDiagnosticSpan(firstArgument.Value)
        }

        argumentTypes := new List<string>()
        for argumentInfo in positionalArguments {
            argumentClrType := argumentInfo.ClrType
            if argumentClrType != null {
                knownArgumentType: Type = argumentClrType
                argumentTypes.Add(NullabilityMetadataReflection.FormatType(knownArgumentType))
            } else {
                argumentTypes.Add("")
            }
        }

        diagnostics.Report(ErrorCode.NoMatchingOverload, "No constructor of attribute '" + GetAttributeDisplayName(attributeType) + "' accepts " + positionalArguments.Count.ToString() + " positional argument(s) with these types: " + string.Join(", ", argumentTypes), span.Line, span.Column, "Check the attribute constructor argument count and types.", span.Length)
    }

    static func GetAttributeDisplayName(attributeType: Type): string {
        fullName := attributeType.get_FullName()
        if fullName != null {
            return fullName
        }

        return attributeType.get_Name()
    }

    // ------------------------------------------------------------------------------------------
    // QUESTION FOUR — WHICH CLR TYPE DOES THIS CONSTANT HAVE?
    //
    // THIS IS A DIFFERENT QUESTION FROM QUESTION ONE AND IT KEEPS ITS OWN LITERAL TABLE FOR A
    // REASON. Question one answers a KIND over a closed family; this answers a metadata `Type` that
    // a constructor parameter is measured against. The two disagree on purpose in two places:
    // `null` is a valid constant of kind `Null` but types as `object` WITH `isNull` set, so that it
    // can fill any reference or nullable parameter; and `typeof(...)` is kind `Type` but types as
    // the well-known `System.Type` from the metadata context, not as a name. Folding the two tables
    // together would change which constructor a null argument matches.
    // ------------------------------------------------------------------------------------------
    func TryInferAttributeArgumentClrType(expression: Expression, out clrType: Type, out isNull: bool): bool {
        isNull = false
        intLiteral := expression as IntLiteralExpression
        if intLiteral != null {
            return TryConvertLiteralTypeInfoToClrType(literalExpressions.IntLiteralType(intLiteral.Value), out clrType)
        }

        floatLiteral := expression as FloatLiteralExpression
        if floatLiteral != null {
            return TryConvertLiteralTypeInfoToClrType(NumericLiteralFacts.GetFloatLiteralTypeInfo(floatLiteral.Value), out clrType)
        }

        charLiteral := expression as CharLiteralExpression
        if charLiteral != null {
            return TryConvertLiteralTypeInfoToClrType(BuiltInTypes.Char, out clrType)
        }

        stringLiteral := expression as StringLiteralExpression
        if stringLiteral != null {
            return TryConvertLiteralTypeInfoToClrType(BuiltInTypes.String, out clrType)
        }

        boolLiteral := expression as BoolLiteralExpression
        if boolLiteral != null {
            return TryConvertLiteralTypeInfoToClrType(BuiltInTypes.Bool, out clrType)
        }

        nullLiteral := expression as NullLiteralExpression
        if nullLiteral != null {
            isNull = true
            return TryConvertLiteralTypeInfoToClrType(BuiltInTypes.Object, out clrType)
        }

        typeOfExpression := expression as TypeOfExpression
        if typeOfExpression != null {
            if wellKnownTypes != null {
                knownTypes: AnalyzerWellKnownTypes = wellKnownTypes
                clrType = knownTypes.SystemType
            } else {
                clrType = typeof(Type)
            }

            return true
        }

        nameofExpression := expression as NameofExpression
        if nameofExpression != null {
            return TryConvertLiteralTypeInfoToClrType(BuiltInTypes.String, out clrType)
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            return TryInferAttributeMemberAccessClrType(memberAccess, out clrType)
        }

        arrayLiteral := expression as ArrayLiteralExpression
        if arrayLiteral != null {
            return TryInferAttributeArrayClrType(arrayLiteral, out clrType)
        }

        unary := expression as UnaryExpression
        if unary != null {
            return TryInferAttributeUnaryClrType(unary, out clrType, out isNull)
        }

        binary := expression as BinaryExpression
        if binary != null {
            return TryInferAttributeBinaryClrType(binary, out clrType)
        }

        clrType = typeof(object)
        return false
    }

    // `object` IS BOTH THE FAILURE VALUE AND A LEGITIMATE ANSWER, and the second clause is what tells
    // them apart: a conversion that produced `object` succeeded only when `object` is what was asked
    // for — which is exactly the null literal's case.
    func TryConvertLiteralTypeInfoToClrType(typeInfo: TypeInfo, out clrType: Type): bool {
        converted := clrTypeConversion.TryConvertTypeInfoToClrType(typeInfo)
        if converted != null {
            knownConverted: Type = converted
            clrType = knownConverted
        } else {
            clrType = typeof(object)
        }

        if clrType != typeof(object) {
            return true
        }

        return BuiltInTypes.Is(typeInfo, BuiltInTypes.Object)
    }

    // THE MEMBER'S OWN CLR TYPE, ASKED OF METADATA. An EXTERNAL enum answers with the ENUM type
    // rather than with the member's declared type, because `Colors.Red` fills a `Colors` parameter.
    // A well-known built-in keyword has no enum case — `int.MaxValue` is an `int`.
    func TryInferAttributeMemberAccessClrType(memberAccess: MemberAccessExpression, out clrType: Type): bool {
        clrType = typeof(object)
        containerName := ""
        if !TryGetQualifiedName(memberAccess.Object, out containerName) {
            return false
        }

        builtInCandidate := AnalyzerWellKnownTypeFacts.BuiltInMetadataClrType(wellKnownTypes, containerName)
        if builtInCandidate != null {
            builtInType: Type = builtInCandidate
            return TryGetRuntimeStaticAttributeMemberType(builtInType, memberAccess.MemberName, out clrType)
        }

        resolved := externalTypeProbe.ResolveExternalType(containerName)
        if resolved == null {
            return false
        }

        reflection := resolved as ReflectionTypeInfo
        if reflection == null {
            return false
        }

        reflectionType := reflection.Type
        if IsRuntimeEnumType(reflectionType) {
            clrType = reflectionType
            return true
        }

        return TryGetRuntimeStaticAttributeMemberType(reflectionType, memberAccess.MemberName, out clrType)
    }

    // NON-PUBLIC STATICS ARE INCLUDED DELIBERATELY. The question is what the member's TYPE is, not
    // whether the program may read it — accessibility is the member-access owner's rule and it has
    // already run by the time this is asked.
    static func TryGetRuntimeStaticAttributeMemberType(containerType: Type, memberName: string, out memberType: Type): bool {
        staticFlags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static
        field := containerType.GetField(memberName, staticFlags)
        if field != null {
            memberType = field.get_FieldType()
            return true
        }

        property := containerType.GetProperty(memberName, staticFlags)
        if property != null && property.get_GetMethod() != null {
            memberType = property.get_PropertyType()
            return true
        }

        memberType = typeof(object)
        return false
    }

    // AN ARRAY TYPES AS AN ARRAY OF ITS ELEMENTS' COMMON TYPE, and `null` elements are skipped when
    // fixing it, exactly as question one skips them when fixing the kind. AN EMPTY ARRAY — or one
    // that is all nulls — types as `object[]`.
    func TryInferAttributeArrayClrType(arrayLiteral: ArrayLiteralExpression, out clrType: Type): bool {
        elementType: Type = typeof(object)
        hasElementType := false
        for element in arrayLiteral.Elements {
            currentType: Type = typeof(object)
            elementIsNull := false
            if !TryInferAttributeArgumentClrType(element, out currentType, out elementIsNull) {
                clrType = typeof(object)
                return false
            }

            if elementIsNull {
                continue
            }

            if !hasElementType {
                elementType = currentType
                hasElementType = true
            }

            if elementType != currentType {
                clrType = typeof(object)
                return false
            }
        }

        if !hasElementType {
            fallbackElementType: Type = typeof(object)
            if !TryConvertLiteralTypeInfoToClrType(BuiltInTypes.Object, out fallbackElementType) {
                clrType = typeof(object)
                return false
            }

            elementType = fallbackElementType
        }

        clrType = elementType.MakeArrayType()
        return true
    }

    // A UNARY CONSTANT KEEPS ITS OPERAND'S TYPE and only the four numeric shapes, the bool and the
    // two integers are admitted — the SAME rule question one applies to kinds, applied to types.
    // A NULL OPERAND is refused outright: `-null` is not a constant of any type.
    func TryInferAttributeUnaryClrType(unary: UnaryExpression, out clrType: Type, out isNull: bool): bool {
        isNull = false
        operandIsNull := false
        if !TryInferAttributeArgumentClrType(unary.Operand, out clrType, out operandIsNull) || operandIsNull {
            return false
        }

        if unary.Operator == UnaryOperator.Negate {
            return IsClrType(clrType, typeof(int)) || IsClrType(clrType, typeof(long)) || IsClrType(clrType, typeof(float)) || IsClrType(clrType, typeof(double))
        }

        if unary.Operator == UnaryOperator.Not {
            return IsClrType(clrType, typeof(bool))
        }

        if unary.Operator == UnaryOperator.BitwiseNot {
            return IsClrType(clrType, typeof(int)) || IsClrType(clrType, typeof(long))
        }

        return false
    }

    // A BITWISE COMBINATION KEEPS ITS OPERANDS' SHARED TYPE, and the two sides must agree exactly —
    // `Colors.Red | 1` types as nothing, which makes the positional question decline rather than
    // guess.
    func TryInferAttributeBinaryClrType(binary: BinaryExpression, out clrType: Type): bool {
        clrType = typeof(object)
        if binary.Operator != BinaryOperator.BitwiseOr && binary.Operator != BinaryOperator.BitwiseAnd && binary.Operator != BinaryOperator.BitwiseXor {
            return false
        }

        leftType: Type = typeof(object)
        rightType: Type = typeof(object)
        leftIsNull := false
        rightIsNull := false
        if !TryInferAttributeArgumentClrType(binary.Left, out leftType, out leftIsNull) {
            return false
        }

        if !TryInferAttributeArgumentClrType(binary.Right, out rightType, out rightIsNull) {
            return false
        }

        if leftIsNull || rightIsNull {
            return false
        }

        if leftType == rightType && (IsClrType(leftType, typeof(int)) || IsClrType(leftType, typeof(long)) || IsRuntimeEnumType(leftType)) {
            clrType = leftType
            return true
        }

        return false
    }

    // IDENTITY OR FULL NAME. The compiler's own `typeof(int)` and a `MetadataLoadContext`'s
    // `System.Int32` are different instances of the same type, and every comparison against a
    // literal `typeof` in this file has to admit both.
    static func IsClrType(clrType: Type, runtimeType: Type): bool {
        if clrType == runtimeType {
            return true
        }

        return clrType.get_FullName() == runtimeType.get_FullName()
    }
}
