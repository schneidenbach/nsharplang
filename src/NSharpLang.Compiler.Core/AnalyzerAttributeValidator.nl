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
    memberNamedValue: bool
    hasIntegerConstantValue: bool
    constantMagnitudeValue: ulong
    constantIsNegativeValue: bool

    Argument: Argument => argumentValue
    Name: string? => nameValue
    Value: Expression => valueExpression
    ClrType: Type? => clrTypeValue
    IsNull: bool => isNullValue
    IsMemberNamed: bool => memberNamedValue

    // THE ARGUMENT'S VALUE, WHEN IT IS AN INTEGER CONSTANT, because the NARROWING question cannot be
    // answered by types. `5` fills a `byte` parameter and `300` does not, and they have the same type;
    // C# decides that by the value, and so does this. Absent for every other argument shape.
    //
    // IT IS CARRIED AS A MAGNITUDE AND A SIGN, not as one signed number, because `ulong`'s top half has
    // no signed representation and a flags constant is exactly where that half is used.
    HasIntegerConstant: bool => hasIntegerConstantValue
    ConstantMagnitude: ulong => constantMagnitudeValue
    ConstantIsNegative: bool => constantIsNegativeValue

    constructor(argument: Argument, name: string?, value: Expression, clrType: Type?, isNull: bool, isMemberNamed: bool = false) {
        argumentValue = argument
        nameValue = name
        valueExpression = value
        clrTypeValue = clrType
        isNullValue = isNull
        memberNamedValue = isMemberNamed
        hasIntegerConstantValue = false
        constantMagnitudeValue = 0UL
        constantIsNegativeValue = false
    }

    func RecordIntegerConstant(magnitude: ulong, isNegative: bool) {
        hasIntegerConstantValue = true
        constantMagnitudeValue = magnitude
        constantIsNegativeValue = isNegative
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
// first as a CLR type that derives from `System.Attribute`; then as a CLR type that does NOT (told to
// derive from `Attribute`, named by its formatted CLR name); then as a SOURCE-declared type, which is
// split again — one that derives from `Attribute` is an ordinary attribute and has its arguments
// measured against its own DECLARATION, one that does not is told to derive from `Attribute`, named by
// the type's own `ToString`; and only then is it not found. Reordering these changes which sentence a
// developer reads for the same program.
//
// A SOURCE-DECLARED ATTRIBUTE IS NOT A LESSER ATTRIBUTE. Its constructors and its settable members are
// read from the declaration rather than from metadata — the type does not exist yet, so there is no
// metadata to read — but every question asked of it, and every sentence reported about it, is the one
// a referenced attribute gets. Where a declared parameter or member type cannot be named as a CLR type,
// the question is DROPPED rather than answered: a false "no constructor accepts these types" on a
// program that is correct is worse than a missed one.
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
    // NL010's ledger. An attribute is a TYPE POSITION that is not a `TypeReference`, so it reaches
    // none of the walks the type resolver credits: a file whose only use of an import was
    // `[NotNullWhen(true)]` had that import reported dead until this credit existed.
    importUsageCredit: AnalyzerImportUsageCredit?

    constructor(diagnosticSink: AnalyzerDiagnosticSink, spansOwner: AnalyzerDiagnosticSpans, scopeStack: AnalyzerScopeStack, declarations: AnalyzerDeclarationContext, probe: AnalyzerExternalTypeProbe, resolver: AnalyzerTypeResolver, memberAccessOwner: AnalyzerMemberAccess, literals: AnalyzerLiteralExpressions, clrConversion: AnalyzerClrTypeConversion, knownTypes: AnalyzerWellKnownTypes?) {
        importUsageCredit = null
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
            // A `test` BLOCK IS A METHOD once it is lowered, so an attribute written on it is
            // measured against `AttributeTargets.Method` — the same target a `func` gets.
            ValidateAttributeArgumentsOn(test.Attributes, AnalyzerAttributeUsageFacts.MethodTarget)
            ValidateParameterAttributeArguments(test.TableParameters)
            return
        }

        functionDecl := decl as FunctionDeclaration
        if functionDecl != null {
            ValidateAttributeArgumentsOn(functionDecl.Attributes, AnalyzerAttributeUsageFacts.MethodTarget)
            ValidateParameterAttributeArguments(functionDecl.Parameters)
            ValidateNativeImportSignature(functionDecl)
            ValidateMethodImplCarrier(functionDecl.Attributes, functionDecl.Body != null || functionDecl.ExpressionBody != null)
            return
        }

        classDecl := decl as ClassDeclaration
        if classDecl != null {
            ValidateAttributeArgumentsOn(classDecl.Attributes, AnalyzerAttributeUsageFacts.ClassTarget)
            ValidatePositionalParameterAttributeArguments(classDecl.PrimaryConstructorParameters)
            ReportMethodImplOnNonCarrier(classDecl.Attributes, "a class")
            return
        }

        structDecl := decl as StructDeclaration
        if structDecl != null {
            ValidateAttributeArgumentsOn(structDecl.Attributes, AnalyzerAttributeUsageFacts.StructTarget)
            ValidatePositionalParameterAttributeArguments(structDecl.PrimaryConstructorParameters)
            ReportMethodImplOnNonCarrier(structDecl.Attributes, "a struct")
            ValidateValueTypeMemberMethodImpl(structDecl.Members)
            return
        }

        recordDecl := decl as RecordDeclaration
        if recordDecl != null {
            recordTarget := AnalyzerAttributeUsageFacts.ClassTarget
            if recordDecl.IsStruct {
                recordTarget = AnalyzerAttributeUsageFacts.StructTarget
            }

            ValidateAttributeArgumentsOn(recordDecl.Attributes, recordTarget)
            ValidatePositionalParameterAttributeArguments(recordDecl.PrimaryConstructorParameters)
            ReportMethodImplOnNonCarrier(recordDecl.Attributes, "a record")
            if recordDecl.IsStruct {
                ValidateValueTypeMemberMethodImpl(recordDecl.Members)
            }

            return
        }

        soaRecordDecl := decl as SoaRecordDeclaration
        if soaRecordDecl != null {
            ValidateAttributeArgumentsOn(soaRecordDecl.Attributes, AnalyzerAttributeUsageFacts.StructTarget)
            ReportMethodImplOnNonCarrier(soaRecordDecl.Attributes, "a struct-of-arrays record")
            return
        }

        interfaceDecl := decl as InterfaceDeclaration
        if interfaceDecl != null {
            ValidateAttributeArgumentsOn(interfaceDecl.Attributes, AnalyzerAttributeUsageFacts.InterfaceTarget)
            ReportMethodImplOnNonCarrier(interfaceDecl.Attributes, "an interface")
            return
        }

        unionDecl := decl as UnionDeclaration
        if unionDecl != null {
            ValidateAttributeArgumentsOn(unionDecl.Attributes, AnalyzerAttributeUsageFacts.ClassTarget)
            ReportMethodImplOnNonCarrier(unionDecl.Attributes, "a union")
            return
        }

        enumDecl := decl as EnumDeclaration
        if enumDecl != null {
            ValidateAttributeArgumentsOn(enumDecl.Attributes, AnalyzerAttributeUsageFacts.EnumTarget)
            ReportMethodImplOnNonCarrier(enumDecl.Attributes, "an enum")
            // AN ENUM MEMBER IS A LITERAL FIELD, so its attributes answer to `AttributeTargets.Field`
            // — the same question a `name: int` field answers. `AttributeTargets.Enum` belongs to the
            // declaration above them and says nothing about a member.
            for member2 in enumDecl.Members {
                memberAttributes := member2.Attributes
                ValidateAttributeArgumentsOn(memberAttributes, AnalyzerAttributeUsageFacts.FieldTarget)
                ReportMethodImplOnNonCarrier(memberAttributes, "an enum member")
            }

            return
        }

        fieldDecl := decl as FieldDeclaration
        if fieldDecl != null {
            ValidateAttributeArgumentsOn(fieldDecl.Attributes, AnalyzerAttributeUsageFacts.FieldTarget)
            ReportMethodImplOnNonCarrier(fieldDecl.Attributes, "a field")
            return
        }

        propertyDecl := decl as PropertyDeclaration
        if propertyDecl != null {
            ValidateAttributeArgumentsOn(propertyDecl.Attributes, AnalyzerAttributeUsageFacts.PropertyDeclarationTargets())
            ValidateMethodImplCarrier(propertyDecl.Attributes, true)
            return
        }

        constructorDecl := decl as ConstructorDeclaration
        if constructorDecl != null {
            ValidateAttributeArgumentsOn(constructorDecl.Attributes, AnalyzerAttributeUsageFacts.ConstructorTarget)
            ValidateParameterAttributeArguments(constructorDecl.Parameters)
            ValidateMethodImplCarrier(constructorDecl.Attributes, true)
            return
        }

        indexerDecl := decl as IndexerDeclaration
        if indexerDecl != null {
            ValidateAttributeArgumentsOn(indexerDecl.Attributes, AnalyzerAttributeUsageFacts.PropertyDeclarationTargets())
            ValidateParameterAttributeArguments(indexerDecl.Parameters)
            ValidateMethodImplCarrier(indexerDecl.Attributes, true)
        }
    }

    // ------------------------------------------------------------------------------------------
    // `[MethodImpl(...)]`, WHICH IS NOT AN ORDINARY ATTRIBUTE AND SO IS NOT MEASURED BY THE
    // ORDINARY WALK ALONE.
    //
    // It is a PSEUDO-CUSTOM attribute: it never becomes a custom-attribute row, and what it says is
    // written into the method definition row's implementation flags instead. Three things follow,
    // and none of them is a question the constructor-and-named-member walk above can ask.
    //
    // WHERE IT MAY BE WRITTEN. Only a method-like declaration has an implementation-flags column. On
    // a type, a field or an enum the attribute has nowhere to go — it is not unread metadata, it is
    // a statement the assembly cannot record at all — so it is refused rather than dropped.
    //
    // WHICH VALUES IT MAY CARRY. A bit outside the `MethodImplOptions` members is not an option the
    // runtime has; the C# compiler refuses it, and so does this.
    //
    // WHICH COMBINATIONS THE TYPE LOADER WILL REFUSE. `Synchronized` on a value type's member and
    // `InternalCall` on a member with a body are both decided entirely by the source, and both are
    // otherwise learned as a `TypeLoadException` the first time the type is touched. A refusal at
    // load time is the worst place to learn about a spelling mistake, so it is stated here.
    // ------------------------------------------------------------------------------------------

    func ValidateMethodImplCarrier(attributes: List<AttributeNode>?, hasBody: bool) {
        if attributes == null {
            return
        }

        for attribute in attributes {
            attributeType: Type = typeof(object)
            if !TryResolveClrAttributeType(attribute.Name, out attributeType) || !MethodImplAttributeFacts.IsMethodImplAttributeType(attributeType) {
                continue
            }

            ValidateMethodImplOptions(attribute, attributeType, false, hasBody)
        }
    }

    func ReportMethodImplOnNonCarrier(attributes: List<AttributeNode>?, target: string) {
        if attributes == null {
            return
        }

        for attribute in attributes {
            attributeType: Type = typeof(object)
            if !TryResolveClrAttributeType(attribute.Name, out attributeType) || !MethodImplAttributeFacts.IsMethodImplAttributeType(attributeType) {
                continue
            }

            span := AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute)
            diagnostics.Report(ErrorCode.MethodImplTargetInvalid, "'[MethodImpl]' sets a method's implementation flags, and " + target + " has none", span.Line, span.Column, "Move it to the method, constructor or property whose implementation it describes.", span.Length)
        }
    }

    // `Synchronized` IS THE ONE RULE THAT NEEDS THE ENCLOSING TYPE, so it is asked from the type's own
    // declaration, over its members, rather than from each member — where the kind of the type around
    // it is not in hand. The other two rules are the member's own and are asked there, so no
    // declaration is measured twice for the same thing.
    func ValidateValueTypeMemberMethodImpl(members: List<Declaration>) {
        for member in members {
            memberFunction := member as FunctionDeclaration
            if memberFunction != null {
                ReportValueTypeMethodImplRefusal(memberFunction.Attributes)
                continue
            }

            memberProperty := member as PropertyDeclaration
            if memberProperty != null {
                ReportValueTypeMethodImplRefusal(memberProperty.Attributes)
                continue
            }

            memberConstructor := member as ConstructorDeclaration
            if memberConstructor != null {
                ReportValueTypeMethodImplRefusal(memberConstructor.Attributes)
                continue
            }

            memberIndexer := member as IndexerDeclaration
            if memberIndexer != null {
                ReportValueTypeMethodImplRefusal(memberIndexer.Attributes)
            }
        }
    }

    func ReportValueTypeMethodImplRefusal(attributes: List<AttributeNode>?) {
        if attributes == null {
            return
        }

        for attribute in attributes {
            attributeType: Type = typeof(object)
            if !TryResolveClrAttributeType(attribute.Name, out attributeType) || !MethodImplAttributeFacts.IsMethodImplAttributeType(attributeType) {
                continue
            }

            optionsType: Type = typeof(object)
            if !MethodImplAttributeFacts.TryGetOptionsType(attributeType, out optionsType) {
                continue
            }

            value := 0
            if !TryReadMethodImplOptionValue(attribute, attributeType, optionsType, out value) {
                continue
            }

            refused := MethodImplAttributeFacts.DescribeClrRefusal(value, optionsType, true, false)
            if refused != null {
                ReportMethodImplRefusedByClr(attribute, refused)
            }
        }
    }

    func ValidateMethodImplOptions(attribute: AttributeNode, attributeType: Type, isValueTypeMember: bool, hasBody: bool) {
        optionsType: Type = typeof(object)
        if !MethodImplAttributeFacts.TryGetOptionsType(attributeType, out optionsType) {
            return
        }

        value := 0
        if !TryReadMethodImplOptionValue(attribute, attributeType, optionsType, out value) {
            return
        }

        refused := MethodImplAttributeFacts.DescribeClrRefusal(value, optionsType, isValueTypeMember, hasBody)
        if refused != null {
            ReportMethodImplRefusedByClr(attribute, refused)
        }
    }

    // THE OPTIONS THE ATTRIBUTE ASKS FOR, as one value. False means an argument could not be reduced —
    // the ordinary walk has already said why — so nothing further is judged. An UNDEFINED bit is
    // reported here and then dropped from the value, exactly as the C# compiler drops it, so one
    // mistake produces one sentence rather than two.
    func TryReadMethodImplOptionValue(attribute: AttributeNode, attributeType: Type, optionsType: Type, out value: int): bool {
        value = 0
        total := 0
        complete := true
        for argument in attribute.Arguments {
            argumentName: string? = null
            valueExpression: Expression = argument.Value
            NormalizeAttributeArgument(argument, out argumentName, out valueExpression)
            enumType := optionsType
            isCodeType := false
            if argumentName != null {
                codeTypeType: Type = typeof(object)
                if !string.Equals(argumentName, MethodImplAttributeFacts.CodeTypeMemberName(), StringComparison.Ordinal) || !MethodImplAttributeFacts.TryGetCodeTypeType(attributeType, out codeTypeType) {
                    continue
                }

                enumType = codeTypeType
                isCodeType = true
            }

            argumentValue := 0
            if !MethodImplAttributeFacts.TryEvaluate(valueExpression, enumType, out argumentValue) {
                complete = false
                continue
            }

            undefined := MethodImplAttributeFacts.DescribeUndefinedBits(argumentValue, MethodImplAttributeFacts.DefinedMask(enumType))
            if undefined.Length > 0 {
                ReportMethodImplUndefinedOption(valueExpression, undefined, enumType)
                complete = false
                continue
            }

            if !isCodeType {
                total = total | argumentValue
            }
        }

        value = total
        return complete
    }

    func ReportMethodImplUndefinedOption(expression: Expression, undefinedBits: string, enumType: Type) {
        span := spans.GetExpressionDiagnosticSpan(expression)
        diagnostics.Report(ErrorCode.MethodImplOptionUndefined, "'[MethodImpl]' was given " + undefinedBits + ", which is not a combination of '" + enumType.Name + "' values", span.Line, span.Column, "Name the options you mean, for example 'MethodImplOptions.AggressiveInlining | MethodImplOptions.NoOptimization'.", span.Length)
    }

    func ReportMethodImplRefusedByClr(attribute: AttributeNode, option: string) {
        span := AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute)
        diagnostics.Report(ErrorCode.MethodImplOptionRefusedByClr, "'MethodImplOptions." + option + "' cannot be carried by this member — " + MethodImplAttributeFacts.DescribeRefusalReason(option), span.Line, span.Column, MethodImplAttributeFacts.DescribeRefusalRepair(option), span.Length)
    }

    func ValidateParameterAttributeArguments(parameters: List<Parameter>?) {
        ValidateParameterAttributeArgumentsAs(parameters, AnalyzerAttributeUsageFacts.ParameterTarget)
    }

    // A PRIMARY CONSTRUCTOR'S PARAMETERS ARE MEASURED AS THE MEMBERS THEY ALSO DECLARE. Everything
    // else about them is a parameter's rule; only the placement question has a second answer.
    func ValidatePositionalParameterAttributeArguments(parameters: List<Parameter>?) {
        ValidateParameterAttributeArgumentsAs(parameters, AnalyzerAttributeUsageFacts.PositionalParameterDeclarationTargets())
    }

    func ValidateParameterAttributeArgumentsAs(parameters: List<Parameter>?, target: int) {
        if parameters == null {
            return
        }

        for parameter in parameters {
            ValidateAttributeArgumentsOn(parameter.Attributes, target)
            ReportMethodImplOnNonCarrier(parameter.Attributes, "a parameter")
        }
    }

    // WHAT `[LibraryImport]` DOES TO THE REST OF THE DECLARATION, WHICH IS THE ONE THING AN
    // ATTRIBUTE CAN DO THAT ITS OWN ARGUMENTS DO NOT SAY.
    //
    // Every other rule in this owner reads the attribute's ARGUMENTS. This one reads the attribute
    // and then reads the SIGNATURE, because a native import is the single case where writing an
    // attribute changes who compiles the method: the emitter defines a P/Invoke stub instead of a
    // body, and the CLR's interop marshaller — not this compiler — decides at the first CALL whether
    // that signature can be marshalled. When it cannot, it raises `MarshalDirectiveException` and the
    // process aborts, at the call site, before the native library is looked for. Measured on the
    // shipped `27-c-library-cli` proof: `nlc check` reported `ok: true` with zero diagnostics, `nlc
    // build` succeeded, and the program died at exit 134. A build that says nothing and a program that
    // cannot start is the worst answer available, so the refusal is stated HERE, where it is cheap and
    // it names the parameter.
    //
    // THE RULE IS THE SPELLING'S, NOT THE RESOLVER'S, and that is deliberate: a generic name and a
    // tuple are generic in metadata no matter what they resolve to, so no type resolution is needed
    // and no resolution failure can turn this into a wrong report. Everything the spelling does not
    // settle is left alone.
    func ValidateNativeImportSignature(declaration: FunctionDeclaration) {
        if !NativeImportSignatureFacts.HasNativeImportAttribute(declaration.Attributes) {
            return
        }

        for parameter in declaration.Parameters {
            refusal := NativeImportSignatureFacts.DescribeRefusal(parameter.Type)
            if refusal != null {
                span := AnalyzerDiagnosticSpanFacts.GetParameterDiagnosticSpan(parameter, declaration.Line, declaration.Column)
                diagnostics.Report(ErrorCode.InvalidParameter, "Native import '" + declaration.Name + "' can't marshal parameter '" + parameter.Name + "' — " + refusal, span.Line, span.Column, NativeImportSignatureFacts.DescribeRepair(parameter.Type), span.Length)
            }
        }

        returnType := declaration.ReturnType
        if returnType != null {
            returnRefusal := NativeImportSignatureFacts.DescribeRefusal(returnType)
            if returnRefusal != null {
                returnSpan := TypeReferenceFacts.GetStartSpan(returnType)
                line := declaration.Line
                column := declaration.Column
                length := Math.Max(1, declaration.Name.Length)
                if returnSpan.IsValid {
                    line = returnSpan.StartLine
                    column = returnSpan.StartColumn
                    length = Math.Max(1, returnSpan.Length)
                }

                diagnostics.Report(ErrorCode.InvalidParameter, "Native import '" + declaration.Name + "' can't marshal its return type — " + returnRefusal, line, column, NativeImportSignatureFacts.DescribeRepair(returnType), length)
            }
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
    // THE PUBLIC DOOR THAT SAYS NOTHING ABOUT PLACEMENT. A caller with an attribute list and no
    // declaration behind it asks this one; the `[AttributeUsage]` PLACEMENT rule is then not asked at
    // all, while every other rule still is.
    func ValidateAttributeArguments(attributes: List<AttributeNode>?) {
        ValidateAttributeArgumentsOn(attributes, AnalyzerAttributeUsageFacts.UnknownTarget)
    }

    func ValidateAttributeArgumentsOn(attributes: List<AttributeNode>?, target: int) {
        if attributes == null {
            return
        }

        // HOW MANY TIMES EACH ATTRIBUTE TYPE HAS BEEN WRITTEN ON THIS ONE DECLARATION, keyed by the
        // type's display name because that is the identity both the metadata and the source arms can
        // produce. The count is reset per declaration, which is the scope `AllowMultiple` governs.
        appliedCounts := new Dictionary<string, int>(StringComparer.Ordinal)
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
                memberNamed := argument.Name == null && argumentName != null
                ignoredKind := AttributeArgumentConstantKind.Null
                if !TryValidateAttributeArgumentExpression(valueExpression, out ignoredKind) {
                    allConstantsValid = false
                    argumentInfos.Add(new AttributeArgumentValidationInfo(argument, argumentName, valueExpression, null, false, memberNamed))
                    continue
                }

                inferredType: Type = typeof(object)
                isNull := false
                hasClrType := TryInferAttributeArgumentClrType(valueExpression, out inferredType, out isNull)
                recordedType: Type? = null
                if hasClrType {
                    recordedType = inferredType
                }

                argumentInfo := new AttributeArgumentValidationInfo(argument, argumentName, valueExpression, recordedType, isNull, memberNamed)
                constantMagnitude := 0UL
                constantIsNegative := false
                if TryEvaluateAttributeIntegerConstant(valueExpression, out constantMagnitude, out constantIsNegative) {
                    argumentInfo.RecordIntegerConstant(constantMagnitude, constantIsNegative)
                }

                argumentInfos.Add(argumentInfo)
            }

            // NL209 BEFORE ANY CHANNEL ANSWERS. An attribute's bracket spelling is a type reference,
            // so two imports that both supply it tie exactly as they do at an annotation — and the
            // resolution chain below would otherwise take whichever import came first and validate
            // the arguments against a type the author never chose. Reporting the tie ENDS this
            // attribute: naming a second, different mistake against one of the two candidates would
            // be a guess about which one was meant.
            if ReportAmbiguousAttributeTypeIfNeeded(attribute) {
                continue
            }

            attributeType: Type = typeof(object)
            if TryResolveClrAttributeType(attribute.Name, out attributeType) {
                CreditAttributeImport(attribute, attributeType)
                if allConstantsValid {
                    ValidateClrAttributeArguments(attribute, attributeType, argumentInfos)
                }

                // `[MethodImpl]`'s PLACEMENT IS OWNED BY ITS OWN RULE, which says the same thing
                // better: NL930 names the missing implementation-flags column rather than quoting an
                // `AttributeUsage` list. Asking both would report one mistake twice. Its REPETITION
                // rule is still asked here — nothing else asks it.
                placementTarget := target
                if MethodImplAttributeFacts.IsMethodImplAttributeType(attributeType) {
                    placementTarget = AnalyzerAttributeUsageFacts.UnknownTarget
                }

                EnforceAttributeUsage(attribute, GetAttributeDisplayName(attributeType), AnalyzerAttributeUsageFacts.ReadUsage(attributeType), placementTarget, appliedCounts)
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
                    if allConstantsValid {
                        ValidateSourceAttributeArguments(attribute, sourceType, argumentInfos)
                    }

                    EnforceAttributeUsage(attribute, GetSourceAttributeDisplayName(sourceType), ReadSourceAttributeUsage(sourceType), target, appliedCounts)
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

    func SetImportUsageCredit(credit: AnalyzerImportUsageCredit?) {
        importUsageCredit = credit
    }

    // The import that supplied this attribute's type. An attribute is a TYPE POSITION that is not a
    // `TypeReference`, so it reaches none of the walks the type resolver credits.
    func CreditAttributeImport(attribute: AttributeNode, attributeType: Type) {
        credit := importUsageCredit
        if credit != null {
            credit.CreditAttributeType(attribute.Name, attributeType)
        }
    }

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

    // THE SOURCE DOOR IS THE TYPE RESOLVER'S DOOR, AND IT HAS TO BE.
    //
    // `[Marker]` used to be looked up in the SCOPE STACK alone, with the dotted-nested door as its
    // only fallback. The scope stack answers for this file and for what this file imported; every
    // OTHER channel a type name resolves through — the file-import alias, the namespace-qualified
    // spelling, and above all the project-wide discovery that makes a sibling `.nl` file's public
    // class visible without an import — lives in `AnalyzerTypeResolver`. So an attribute class
    // declared in one file and written in another reported "Attribute type 'Marker' not found" while
    // `func Make(): MarkerAttribute` on the very next line resolved perfectly.
    //
    // Asking the resolver is not a second door: it OPENS WITH the scope stack, so nothing that used
    // to resolve stops resolving, and the six channels behind it are the same ones every other type
    // reference in the language goes through. The position is `0`, which is the resolver's own
    // "resolve but report nothing and bind nothing" mode — an unrecognised name is this validator's
    // to report, with its own wording, and reporting it twice would be worse than not at all.
    //
    // A NAME NOTHING DECLARED comes back as an `ExternalTypeInfo` placeholder, which is not one of
    // the source-declared shapes, so it declines here exactly as a null lookup used to.
    func TryResolveSourceAttributeCandidate(attributeName: string, out sourceType: TypeInfo): bool {
        for candidate in GetClrAttributeNameCandidates(attributeName) {
            resolved := typeResolver.ResolveSimpleType(candidate, 0, 0)
            aliased := declarationContext.ResolveDeclaredAlias(resolved)
            if IsSourceDeclaredAttributeCandidate(aliased) {
                sourceType = aliased
                return true
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

    // THE TIE AT AN ATTRIBUTE, ASKED OF THE ONE PRECEDENCE OWNER EVERY OTHER POSITION ASKS.
    //
    // `[Tag]` may legally mean `Tag` or `TagAttribute`, so BOTH spellings are asked, in
    // `GetClrAttributeNameCandidates`' order, and the first that ties is reported — an attribute
    // names one type, so one report is the whole answer. A DOTTED spelling is skipped: it has already
    // named its namespace, and a qualified reference is never ambiguous.
    func ReportAmbiguousAttributeTypeIfNeeded(attribute: AttributeNode): bool {
        if attribute.Name.Contains(".") {
            return false
        }

        span := AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute)
        for candidate in GetClrAttributeNameCandidates(attribute.Name) {
            if typeResolver.ReportAmbiguousImportedTypeIfNeeded(candidate, attribute.Name, span.Line, span.Column) {
                return true
            }
        }

        return false
    }

    func ReportAttributeTypeNotFound(attribute: AttributeNode) {
        span := AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute)
        suggestedAttributeName := attribute.Name
        if !attribute.Name.EndsWith("Attribute", StringComparison.Ordinal) {
            suggestedAttributeName = attribute.Name + "Attribute"
        }

        diagnostics.Report(ErrorCode.TypeNotFound, "Attribute type '" + attribute.Name + "' not found", span.Line, span.Column, "Check the spelling, add the missing 'import', or define an attribute class named '" + suggestedAttributeName + "'.", span.Length)
    }

    // ------------------------------------------------------------------------------------------
    // WHERE AN ATTRIBUTE MAY BE WRITTEN, AND HOW OFTEN.
    //
    // `[AttributeUsage]` is the only attribute whose subject is another attribute, and the two things
    // it decides are decided HERE rather than at the CLR's expense: an attribute written on a
    // declaration its usage excludes would otherwise become a metadata row that loads fine and means
    // nothing, and a repeated attribute on a type that does not allow it is a `TypeLoadException` the
    // first time anyone reads it.
    //
    // THE TARGET IS THE DECLARATION'S, NOT THE ATTRIBUTE'S. A property in N# has no per-accessor
    // attribute position — the attribute is written once and reaches both accessors — so a property
    // offers BOTH `Property` and `Method`, and an attribute declared for either is accepted there.
    // That is a language fact about where attributes can be written, not a relaxation of the rule.
    // ------------------------------------------------------------------------------------------

    func EnforceAttributeUsage(attribute: AttributeNode, displayName: string, usage: AnalyzerAttributeUsage, target: int, appliedCounts: Dictionary<string, int>) {
        if target != AnalyzerAttributeUsageFacts.UnknownTarget && (usage.Targets & target) == 0 {
            ReportAttributeTargetInvalid(attribute, displayName, usage, target)
        }

        applied := 0
        appliedCounts.TryGetValue(displayName, out applied)
        appliedCounts[displayName] = applied + 1
        if applied > 0 && !usage.AllowMultiple {
            ReportAttributeNotRepeatable(attribute, displayName)
        }
    }

    func ReportAttributeTargetInvalid(attribute: AttributeNode, displayName: string, usage: AnalyzerAttributeUsage, target: int) {
        span := AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute)
        diagnostics.Report(ErrorCode.AttributeTargetInvalid, "Attribute '" + displayName + "' cannot be applied to " + AnalyzerAttributeUsageFacts.DescribeTarget(target) + " — it is declared for " + AnalyzerAttributeUsageFacts.DescribeTargets(usage.Targets), span.Line, span.Column, DescribeAttributeTargetRepair(target), span.Length)
    }

    // WHAT TO DO ABOUT A MISPLACED ATTRIBUTE. A positional constructor parameter gets the longer
    // sentence, because the developer has to be told the rule they did not break rather than only the
    // one they did: the attribute would have been written on the parameter or on the field that
    // parameter declares, and it allows neither.
    static func DescribeAttributeTargetRepair(target: int): string {
        if target == AnalyzerAttributeUsageFacts.PositionalParameterDeclarationTargets() {
            return "A positional constructor parameter carries its attribute on the parameter when the attribute allows parameters, and on the field that parameter declares when it allows fields — this one allows neither. Move it to a declaration it allows, or widen the attribute's own '[AttributeUsage(...)]'."
        }

        return "Move it to one of those declarations, or widen the attribute's own '[AttributeUsage(...)]'."
    }

    func ReportAttributeNotRepeatable(attribute: AttributeNode, displayName: string) {
        span := AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute)
        diagnostics.Report(ErrorCode.AttributeNotRepeatable, "Attribute '" + displayName + "' is already applied to this declaration and does not allow multiples", span.Line, span.Column, "Delete the duplicate, or declare the attribute with '[AttributeUsage(..., AllowMultiple = true)]'.", span.Length)
    }

    // THE USAGE A SOURCE-DECLARED ATTRIBUTE ANNOUNCES, read from its own DECLARATION — the type does
    // not exist as metadata while the program that declares it is being compiled. `[AttributeUsage]`
    // is itself inherited, so a declaration that carries none asks its base, and the walk crosses into
    // metadata at the first base that came from a referenced assembly.
    func ReadSourceAttributeUsage(sourceType: TypeInfo): AnalyzerAttributeUsage {
        current: TypeInfo = sourceType
        depth := 0
        while depth < 64 {
            resolved := declarationContext.ResolveDeclaredAlias(current)
            reflection := resolved as ReflectionTypeInfo
            if reflection != null {
                return AnalyzerAttributeUsageFacts.ReadUsage(reflection.Type)
            }

            classType := resolved as ClassTypeInfo
            if classType == null {
                return AnalyzerAttributeUsageFacts.DefaultUsage()
            }

            declaredAttributes := new List<AttributeNode>()
            usage := AnalyzerAttributeUsageFacts.DefaultUsage()
            if declarationContext.TryGetDeclaredClassAttributes(classType, classType.Name, out declaredAttributes) && TryReadDeclaredAttributeUsage(declaredAttributes, out usage) {
                return usage
            }

            shape := new AnalyzerSourceMemberShape()
            if !declarationContext.TryGetSourceMemberShape(classType, null, out shape) {
                return AnalyzerAttributeUsageFacts.DefaultUsage()
            }

            declaredBase := shape.BaseType
            if declaredBase == null {
                return AnalyzerAttributeUsageFacts.DefaultUsage()
            }

            current = declaredBase
            depth = depth + 1
        }

        return AnalyzerAttributeUsageFacts.DefaultUsage()
    }

    // ONE `[AttributeUsage(...)]` AS WRITTEN. The positional argument is an `AttributeTargets`
    // expression — a member access or a `|` combination of them — and it is evaluated against the
    // runtime enum through the same evaluator `[MethodImpl]`'s options use. An argument this compiler
    // cannot reduce leaves the DEFAULT in place rather than inventing a narrower one, because a wrong
    // narrowing would refuse correct programs.
    func TryReadDeclaredAttributeUsage(declaredAttributes: List<AttributeNode>, out usage: AnalyzerAttributeUsage): bool {
        usage = AnalyzerAttributeUsageFacts.DefaultUsage()
        targetsType: Type = typeof(object)
        attributeIndex := 0
        while attributeIndex < declaredAttributes.Count {
            declaredAttribute := declaredAttributes[attributeIndex]
            attributeIndex = attributeIndex + 1
            if !AnalyzerAttributeUsageFacts.IsAttributeUsageName(declaredAttribute.Name) {
                continue
            }

            if !TryResolveAttributeTargetsType(out targetsType) {
                return false
            }

            targets := AnalyzerAttributeUsageFacts.AllTargets
            allowMultiple := false
            inherited := true
            declaredArguments := declaredAttribute.Arguments
            argumentIndex := 0
            while argumentIndex < declaredArguments.Count {
                declaredArgument := declaredArguments[argumentIndex]
                argumentIndex = argumentIndex + 1
                argumentName: string? = null
                valueExpression: Expression = declaredArgument.Value
                NormalizeAttributeArgument(declaredArgument, out argumentName, out valueExpression)
                if argumentName == null {
                    evaluatedTargets := 0
                    if MethodImplAttributeFacts.TryEvaluate(valueExpression, targetsType, out evaluatedTargets) {
                        targets = evaluatedTargets
                    }

                    continue
                }

                booleanValue := false
                if !TryReadBooleanAttributeArgument(valueExpression, out booleanValue) {
                    continue
                }

                if argumentName == AnalyzerAttributeUsageFacts.AllowMultipleMemberName() {
                    allowMultiple = booleanValue
                }

                if argumentName == AnalyzerAttributeUsageFacts.InheritedMemberName() {
                    inherited = booleanValue
                }
            }

            usage = new AnalyzerAttributeUsage(targets, allowMultiple, inherited)
            return true
        }

        return false
    }

    func TryResolveAttributeTargetsType(out targetsType: Type): bool {
        targetsType = typeof(object)
        resolved := externalTypeProbe.ResolveExternalType("System.AttributeTargets")
        if resolved == null {
            return false
        }

        reflection := resolved as ReflectionTypeInfo
        if reflection == null {
            return false
        }

        targetsType = reflection.Type
        return true
    }

    static func TryReadBooleanAttributeArgument(expression: Expression, out value: bool): bool {
        value = false
        boolLiteral := expression as BoolLiteralExpression
        if boolLiteral == null {
            return false
        }

        value = boolLiteral.Value
        return true
    }

    func ReportAttributeTypeMustDeriveFromAttribute(attribute: AttributeNode, typeName: string) {
        span := AnalyzerDiagnosticSpanFacts.GetAttributeTypeDiagnosticSpan(attribute)
        diagnostics.Report(ErrorCode.TypeMismatch, "Attribute type '" + typeName + "' must derive from System.Attribute", span.Line, span.Column, "Use a CLR attribute type or define a class that inherits System.Attribute.", span.Length)
    }

    // ------------------------------------------------------------------------------------------
    // THE SAME THREE QUESTIONS, ASKED OF A DECLARATION INSTEAD OF METADATA.
    //
    // A source-declared attribute type does not exist as a `Type` while the program that declares it
    // is being compiled, so its constructors and its settable members are read from the DECLARATION.
    // Everything else is shared with the metadata path: the same compatibility rule decides whether
    // an argument fills a parameter, and the same three sentences are reported.
    //
    // WHERE A DECLARED TYPE CANNOT BE NAMED AS A CLR TYPE the question is dropped, and dropping it is
    // the whole point of the `Undecidable` answer. An attribute constructor that takes a
    // SOURCE-DECLARED enum is a correct attribute; refusing it because the analyzer could not turn the
    // parameter into a `System.Type` would be a false error on a program the emitter goes on to
    // compile.
    // ------------------------------------------------------------------------------------------

    static SourceMemberNotFound: int => 0
    static SourceMemberMatched: int => 1
    static SourceMemberUndecidable: int => 2

    func ValidateSourceAttributeArguments(attribute: AttributeNode, sourceType: TypeInfo, argumentInfos: List<AttributeArgumentValidationInfo>) {
        displayName := GetSourceAttributeDisplayName(sourceType)
        for argumentInfo in argumentInfos {
            declaredName := argumentInfo.Name
            if declaredName != null && argumentInfo.IsMemberNamed {
                ValidateSourceNamedAttributeArgument(sourceType, displayName, argumentInfo, declaredName)
            }
        }

        positionalArguments := new List<AttributeArgumentValidationInfo>()
        anyUntyped := false
        for argumentInfo in argumentInfos {
            if !argumentInfo.IsMemberNamed {
                positionalArguments.Add(argumentInfo)
                if argumentInfo.ClrType == null {
                    anyUntyped = true
                }
            }
        }

        if anyUntyped {
            return
        }

        if MeasureSourceAttributeConstructors(sourceType, positionalArguments) == AnalyzerAttributeValidator.SourceMemberNotFound {
            ReportNoMatchingAttributeConstructorOn(attribute, displayName, positionalArguments)
        }
    }

    // THE TYPE'S OWN DISPLAY FORM, read through an `object`-typed local because `ToString` is declared
    // by the base of the `TypeInfo` hierarchy rather than by the hierarchy itself.
    static func GetSourceAttributeDisplayName(sourceType: TypeInfo): string {
        boxedSourceType := sourceType as object
        rendered := boxedSourceType.ToString()
        if rendered != null {
            return rendered
        }

        return "attribute"
    }

    func ValidateSourceNamedAttributeArgument(sourceType: TypeInfo, displayName: string, argumentInfo: AttributeArgumentValidationInfo, argumentName: string) {
        memberType: Type = typeof(object)
        outcome := ProbeSourceAttributeNamedMember(sourceType, argumentName, out memberType)
        if outcome == AnalyzerAttributeValidator.SourceMemberNotFound {
            ReportUnknownAttributeNamedArgumentOn(displayName, argumentInfo)
            return
        }

        if outcome == AnalyzerAttributeValidator.SourceMemberUndecidable {
            return
        }

        if argumentInfo.ClrType != null && !IsAttributeArgumentCompatibleValue(memberType, argumentInfo) {
            ReportAttributeNamedArgumentTypeMismatchOn(displayName, argumentInfo, memberType)
        }
    }

    // A NAMED ARGUMENT NAMES SOMETHING THE CLR CAN SET IN METADATA, and the declaration says which:
    // an EXPORTED instance field that is not `readonly`, or an EXPORTED instance property that
    // declares a setter. The chain crosses into metadata at the first base that came from a
    // referenced assembly, where the metadata rule takes over unchanged.
    func ProbeSourceAttributeNamedMember(candidate: TypeInfo, memberName: string, out memberType: Type): int {
        memberType = typeof(object)
        current: TypeInfo = candidate
        depth := 0
        while depth < 64 {
            resolved := declarationContext.ResolveDeclaredAlias(current)
            reflection := resolved as ReflectionTypeInfo
            if reflection != null {
                if TryGetSettableAttributeNamedMemberType(reflection.Type, memberName, out memberType) {
                    return AnalyzerAttributeValidator.SourceMemberMatched
                }

                return AnalyzerAttributeValidator.SourceMemberNotFound
            }

            classType := resolved as ClassTypeInfo
            if classType == null {
                return AnalyzerAttributeValidator.SourceMemberUndecidable
            }

            shape := new AnalyzerSourceMemberShape()
            if !declarationContext.TryGetSourceMemberShape(classType, null, out shape) {
                return AnalyzerAttributeValidator.SourceMemberUndecidable
            }

            declaredMembers := shape.DeclaredMembers
            memberIndex := 0
            while memberIndex < declaredMembers.Length {
                member := declaredMembers[memberIndex]
                memberIndex = memberIndex + 1
                if member.Name != memberName || member.IsStatic || !member.IsExported {
                    continue
                }

                settableField := member.Kind == DeclaredMemberKind.Field && !member.IsReadonly
                settableProperty := member.Kind == DeclaredMemberKind.Property && member.HasSetter
                if !settableField && !settableProperty {
                    continue
                }

                declaredClrType: Type = typeof(object)
                if TryGetSourceDeclaredClrType(classType, member.Type, out declaredClrType) {
                    memberType = declaredClrType
                    return AnalyzerAttributeValidator.SourceMemberMatched
                }

                return AnalyzerAttributeValidator.SourceMemberUndecidable
            }

            declaredBase := shape.BaseType
            if declaredBase == null {
                return AnalyzerAttributeValidator.SourceMemberNotFound
            }

            current = declaredBase
            depth = depth + 1
        }

        return AnalyzerAttributeValidator.SourceMemberUndecidable
    }

    // EVERY DECLARED CONSTRUCTOR OF THE RIGHT ARITY, and — for a type with primary parameters — the
    // primary constructor beside them. A type that declares NONE has the parameterless one the CLR
    // gives it, which accepts exactly zero arguments.
    func MeasureSourceAttributeConstructors(sourceType: TypeInfo, positionalArguments: List<AttributeArgumentValidationInfo>): int {
        resolved := declarationContext.ResolveDeclaredAlias(sourceType)
        classType := resolved as ClassTypeInfo
        if classType == null {
            return AnalyzerAttributeValidator.SourceMemberUndecidable
        }

        shape := new AnalyzerSourceMemberShape()
        if !declarationContext.TryGetSourceMemberShape(classType, null, out shape) {
            return AnalyzerAttributeValidator.SourceMemberUndecidable
        }

        candidateCount := 0
        for member in shape.DeclaredMembers {
            if member.Kind != DeclaredMemberKind.Constructor {
                continue
            }

            candidateCount = candidateCount + 1
            outcome := MeasureSourceConstructorSignature(classType, member.ParameterNames, member.ParameterTypes, member.RequiredParameterCount, positionalArguments)
            if outcome != AnalyzerAttributeValidator.SourceMemberNotFound {
                return outcome
            }
        }

        if shape.SupportsPrimaryParameters && shape.PrimaryParameters.Length > 0 {
            primaryTypes := new TypeReference[](shape.PrimaryParameters.Length)
            index := 0
            while index < shape.PrimaryParameters.Length {
                primaryTypes[index] = shape.PrimaryParameters[index].Type
                index = index + 1
            }

            candidateCount = candidateCount + 1
            primaryNames := new string[](shape.PrimaryParameters.Length)
            index = 0
            while index < shape.PrimaryParameters.Length {
                primaryNames[index] = shape.PrimaryParameters[index].Name
                index = index + 1
            }
            outcome := MeasureSourceConstructorSignature(classType, primaryNames, primaryTypes, primaryTypes.Length, positionalArguments)
            if outcome != AnalyzerAttributeValidator.SourceMemberNotFound {
                return outcome
            }
        }

        if candidateCount == 0 && positionalArguments.Count == 0 {
            return AnalyzerAttributeValidator.SourceMemberMatched
        }

        return AnalyzerAttributeValidator.SourceMemberNotFound
    }

    // AN OMITTED ARGUMENT IS THE PARAMETER'S DEFAULT. `[Mark]` on `MarkAttribute(level: int = 1)`
    // calls the one-parameter constructor and the blob carries the declared default, exactly as the
    // same call written in code does — so the arity test is a RANGE, from the required count to the
    // full one, and only the arguments the source wrote are measured against their parameters.
    func MeasureSourceConstructorSignature(owner: TypeInfo, parameterNames: string[], parameterTypes: TypeReference[], declaredRequiredCount: int, positionalArguments: List<AttributeArgumentValidationInfo>): int {
        requiredCount := declaredRequiredCount
        if requiredCount < 0 || requiredCount > parameterTypes.Length {
            requiredCount = parameterTypes.Length
        }

        if positionalArguments.Count > parameterTypes.Length || positionalArguments.Count < requiredCount {
            return AnalyzerAttributeValidator.SourceMemberNotFound
        }

        claimed := new bool[](parameterTypes.Length)
        nextPositional := 0
        for positionalArgument in positionalArguments {
            parameterIndex := AttributeConstructorParameterSlot(parameterNames, claimed, positionalArgument.Name, nextPositional)
            if positionalArgument.Name == null {
                nextPositional = parameterIndex + 1
            }
            if parameterIndex < 0 || parameterIndex >= parameterTypes.Length || claimed[parameterIndex] {
                return AnalyzerAttributeValidator.SourceMemberNotFound
            }
            claimed[parameterIndex] = true
            parameterClrType: Type = typeof(object)
            if !TryGetSourceDeclaredClrType(owner, parameterTypes[parameterIndex], out parameterClrType) {
                return AnalyzerAttributeValidator.SourceMemberUndecidable
            }

            if !IsAttributeArgumentCompatibleValue(parameterClrType, positionalArgument) {
                return AnalyzerAttributeValidator.SourceMemberNotFound
            }
        }
        requiredIndex := 0
        while requiredIndex < requiredCount {
            if !claimed[requiredIndex] {
                return AnalyzerAttributeValidator.SourceMemberNotFound
            }
            requiredIndex += 1
        }

        return AnalyzerAttributeValidator.SourceMemberMatched
    }

    // A DECLARED TYPE AS A CLR TYPE, resolved AGAINST THE DECLARING FILE rather than against the file
    // the attribute was written in — an attribute declared in one file and applied in another must
    // read its own parameter types through its own imports. The resolution door is the silent one:
    // asking the reporting resolver here would report a second time about a declaration that has
    // already been walked.
    func TryGetSourceDeclaredClrType(owner: TypeInfo, typeReference: TypeReference?, out clrType: Type): bool {
        clrType = typeof(object)
        if typeReference == null {
            return false
        }

        resolvedInfo := BuiltInTypes.Unknown as TypeInfo
        if !declarationContext.TryResolveTypeForOwner(typeReference, owner, null, out resolvedInfo) {
            return false
        }

        return TryConvertLiteralTypeInfoToClrType(resolvedInfo, out clrType)
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
            if declaredName != null && argumentInfo.IsMemberNamed {
                ValidateNamedAttributeArgument(attributeType, argumentInfo, declaredName)
            }
        }

        positionalArguments := new List<AttributeArgumentValidationInfo>()
        anyUntyped := false
        for argumentInfo in argumentInfos {
            if !argumentInfo.IsMemberNamed {
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

        if argumentInfo.ClrType != null && !IsAttributeArgumentCompatibleValue(memberType, argumentInfo) {
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
            if positionalArguments.Count > parameters.Length || positionalArguments.Count < RequiredParameterCount(parameters) {
                continue
            }

            matches := true
            claimed := new bool[](parameters.Length)
            names := new string[](parameters.Length)
            nameIndex := 0
            while nameIndex < parameters.Length {
                names[nameIndex] = parameters[nameIndex].get_Name() ?? ""
                nameIndex += 1
            }
            nextPositional := 0
            for argumentInfo in positionalArguments {
                parameterIndex := AttributeConstructorParameterSlot(names, claimed, argumentInfo.Name, nextPositional)
                if argumentInfo.Name == null {
                    nextPositional = parameterIndex + 1
                }
                if parameterIndex < 0 || parameterIndex >= parameters.Length || claimed[parameterIndex] {
                    matches = false
                    break
                }
                claimed[parameterIndex] = true
                parameter := parameters[parameterIndex]
                if !IsAttributeArgumentCompatibleValue(parameter.get_ParameterType(), argumentInfo) {
                    matches = false
                    break
                }
            }

            requiredIndex := 0
            while matches && requiredIndex < RequiredParameterCount(parameters) {
                if !claimed[requiredIndex] {
                    matches = false
                }
                requiredIndex += 1
            }

            if matches {
                return true
            }
        }

        return false
    }

    static func AttributeConstructorParameterSlot(parameterNames: string[], claimed: bool[], argumentName: string?, nextPositional: int): int {
        if argumentName == null {
            slot := nextPositional
            while slot < claimed.Length && claimed[slot] {
                slot += 1
            }
            return slot
        }
        index := 0
        while index < parameterNames.Length {
            if parameterNames[index] == argumentName {
                return index
            }
            index += 1
        }
        return -1
    }

    // HOW MANY ARGUMENTS A METADATA SIGNATURE INSISTS ON. Optional parameters are trailing by
    // construction, so the count is the position of the first optional one.
    static func RequiredParameterCount(parameters: ParameterInfo[]): int {
        count := parameters.Length
        while count > 0 {
            parameter := parameters[count - 1]
            if !parameter.get_IsOptional() {
                return count
            }

            count = count - 1
        }

        return 0
    }

    // WHAT ONE ARGUMENT MAY FILL. `null` is decided by the PARAMETER alone — anything that is not a
    // non-nullable value type takes it, whatever the argument's nominal `object` type says. An enum
    // parameter also takes its own underlying integer, which is how `[Attr(1)]` fills a flags
    // parameter. Arrays are compared element-wise under the same three rules, one level deep, which
    // is as deep as attribute metadata goes.
    // THE COMPATIBILITY QUESTION AS THE CALLERS ASK IT: the type rule first, then the CONSTANT rule
    // for the one case types cannot decide. An integer constant fills any integral or floating
    // parameter whose range CONTAINS IT — `[Attr(5)]` into a `byte`, `[Attr(300)]` not — which is the
    // C# constant-expression conversion and the only way a narrow numeric attribute parameter is
    // writable at all.
    static func IsAttributeArgumentCompatibleValue(parameterType: Type, argumentInfo: AttributeArgumentValidationInfo): bool {
        argumentClrType := argumentInfo.ClrType
        if argumentClrType == null {
            return false
        }

        knownArgumentType: Type = argumentClrType
        if IsAttributeArgumentCompatible(parameterType, knownArgumentType, argumentInfo.IsNull) {
            return true
        }

        // AN ARRAY ARGUMENT CONVERTS PER ELEMENT, NOT AS A WHOLE. The array's own type is the common
        // type of what was written — `[1, 2]` is `int[]` — and no conversion exists from `int[]` to
        // `byte[]`, but the blob writes each element against the ELEMENT type and each of these
        // elements is an integer constant a `byte` holds. The rule is therefore the same
        // constant-expression conversion applied one level down, which is exactly as deep as
        // attribute metadata goes.
        if parameterType.get_IsArray() && !argumentInfo.IsNull {
            return ArrayElementsFitParameter(parameterType, argumentInfo.Value)
        }

        if !argumentInfo.HasIntegerConstant || !IsIntegralClrType(knownArgumentType) {
            return false
        }

        return ConstantFitsNumericType(parameterType, argumentInfo.ConstantMagnitude, argumentInfo.ConstantIsNegative)
    }

    // EVERY ELEMENT OF A WRITTEN ARRAY LITERAL, AGAINST THE PARAMETER'S ELEMENT TYPE. Only an integer
    // constant is decided here: an element the type rule already accepted never reaches this, and an
    // element that is neither refuses the whole argument.
    static func ArrayElementsFitParameter(parameterType: Type, value: Expression): bool {
        elementCandidate := parameterType.GetElementType()
        if elementCandidate == null {
            return false
        }

        arrayLiteral := value as ArrayLiteralExpression
        if arrayLiteral == null {
            return false
        }

        elementType: Type = elementCandidate
        for element in arrayLiteral.Elements {
            magnitude := 0UL
            isNegative := false
            if !TryEvaluateAttributeIntegerConstant(element, out magnitude, out isNegative) {
                return false
            }

            if !ConstantFitsNumericType(elementType, magnitude, isNegative) {
                return false
            }
        }

        return true
    }

    static func IsIntegralClrType(clrType: Type): bool {
        fullName := clrType.get_FullName()
        return fullName == "System.SByte" || fullName == "System.Byte" || fullName == "System.Int16" || fullName == "System.UInt16" || fullName == "System.Int32" || fullName == "System.UInt32" || fullName == "System.Int64" || fullName == "System.UInt64" || fullName == "System.Char"
    }

    // THE RANGES, WRITTEN OUT, over a magnitude and a sign. A negative constant is out of range for
    // every unsigned parameter whatever its magnitude, which is why the sign is asked first.
    static func ConstantFitsNumericType(parameterType: Type, magnitude: ulong, isNegative: bool): bool {
        fullName := parameterType.get_FullName()
        if fullName == "System.Single" || fullName == "System.Double" {
            return true
        }

        if isNegative {
            if fullName == "System.SByte" {
                return magnitude <= 128UL
            }
            if fullName == "System.Int16" {
                return magnitude <= 32768UL
            }
            if fullName == "System.Int32" {
                return magnitude <= 2147483648UL
            }
            if fullName == "System.Int64" {
                return magnitude <= 9223372036854775808UL
            }

            return false
        }

        if fullName == "System.SByte" {
            return magnitude <= 127UL
        }
        if fullName == "System.Byte" {
            return magnitude <= 255UL
        }
        if fullName == "System.Int16" {
            return magnitude <= 32767UL
        }
        if fullName == "System.UInt16" || fullName == "System.Char" {
            return magnitude <= 65535UL
        }
        if fullName == "System.Int32" {
            return magnitude <= 2147483647UL
        }
        if fullName == "System.UInt32" {
            return magnitude <= 4294967295UL
        }
        if fullName == "System.Int64" {
            return magnitude <= 9223372036854775807UL
        }
        if fullName == "System.UInt64" {
            return true
        }

        return false
    }

    // THE VALUE OF AN INTEGER CONSTANT EXPRESSION, over exactly the shapes that can spell one: a
    // literal, and the two unary operators that keep it an integer. Anything else has no value here —
    // an enum member's value is the ENUM's, and the enum rule already accepts it by type.
    static func TryEvaluateAttributeIntegerConstant(expression: Expression, out magnitude: ulong, out isNegative: bool): bool {
        magnitude = 0UL
        isNegative = false
        intLiteral := expression as IntLiteralExpression
        if intLiteral != null {
            return NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(intLiteral.Value, out magnitude)
        }

        unary := expression as UnaryExpression
        if unary == null || unary.Operator != UnaryOperator.Negate {
            return false
        }

        operandMagnitude := 0UL
        operandIsNegative := false
        if !TryEvaluateAttributeIntegerConstant(unary.Operand, out operandMagnitude, out operandIsNegative) || operandIsNegative {
            return false
        }

        magnitude = operandMagnitude
        isNegative = operandMagnitude != 0UL
        return true
    }

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
        ReportUnknownAttributeNamedArgumentOn(GetAttributeDisplayName(attributeType), argumentInfo)
    }

    func ReportUnknownAttributeNamedArgumentOn(attributeDisplayName: string, argumentInfo: AttributeArgumentValidationInfo) {
        span := spans.GetAttributeArgumentDiagnosticSpan(argumentInfo.Argument, argumentInfo.Value)
        argumentName := argumentInfo.Name
        if argumentName == null {
            argumentName = ""
        }

        diagnostics.Report(ErrorCode.UndefinedMember, "Attribute '" + attributeDisplayName + "' has no public settable property or field named '" + argumentName + "'", span.Line, span.Column, "Use a named argument exposed by the attribute type.", span.Length)
    }

    func ReportAttributeNamedArgumentTypeMismatch(attributeType: Type, argumentInfo: AttributeArgumentValidationInfo, memberType: Type) {
        ReportAttributeNamedArgumentTypeMismatchOn(GetAttributeDisplayName(attributeType), argumentInfo, memberType)
    }

    func ReportAttributeNamedArgumentTypeMismatchOn(attributeDisplayName: string, argumentInfo: AttributeArgumentValidationInfo, memberType: Type) {
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

        diagnostics.Report(ErrorCode.TypeMismatch, "Attribute named argument '" + argumentName + "' on '" + attributeDisplayName + "' expects '" + NullabilityMetadataReflection.FormatType(memberType) + "' but got '" + actualText + "'", span.Line, span.Column, "Use a value whose type matches the attribute property or field.", span.Length)
    }

    // THE CONSTRUCTOR REFUSAL ANCHORS ON THE FIRST POSITIONAL ARGUMENT when there is one, and on the
    // attribute itself when there is none — `[Attr]` on an attribute with no parameterless
    // constructor has no argument to point at.
    func ReportNoMatchingAttributeConstructor(attribute: AttributeNode, attributeType: Type, positionalArguments: List<AttributeArgumentValidationInfo>) {
        ReportNoMatchingAttributeConstructorOn(attribute, GetAttributeDisplayName(attributeType), positionalArguments)
    }

    func ReportNoMatchingAttributeConstructorOn(attribute: AttributeNode, attributeDisplayName: string, positionalArguments: List<AttributeArgumentValidationInfo>) {
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

        diagnostics.Report(ErrorCode.NoMatchingOverload, "No constructor of attribute '" + attributeDisplayName + "' accepts " + positionalArguments.Count.ToString() + " positional argument(s) with these types: " + string.Join(", ", argumentTypes), span.Line, span.Column, "Check the attribute constructor argument count and types.", span.Length)
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
