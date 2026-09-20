namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// ONE UNIT OF THE PROGRAM THE CARET IS BEING HELPED INSIDE, with the text it was parsed from.
// The text is what a doc comment is read out of, and it is optional because a unit that was never
// on disk (an unsaved buffer that has not been handed to the snapshot yet) still has declarations
// worth answering with.
class SignatureHelpSourceUnit {
    unitValue: CompilationUnit
    sourceTextValue: string?

    Unit: CompilationUnit => unitValue
    SourceText: string? => sourceTextValue

    constructor(Unit: CompilationUnit, SourceText: string?) {
        unitValue = Unit
        sourceTextValue = SourceText
    }
}

// ONE OVERLOAD, as the protocol will show it: the whole call written out, the rows the editor
// underlines one at a time, and whatever documentation the declaration carries.
//
// The parameter rows are their own list rather than something a reader must cut back out of the
// label, because the active-parameter rule is written against the ROWS and a label is free to
// contain a comma inside a type argument.
class SignatureHelpOverload {
    labelValue: string
    documentationValue: string?
    parameterLabelsValue: List<string>

    Label: string => labelValue
    Documentation: string? => documentationValue
    ParameterLabels: List<string> => parameterLabelsValue

    constructor(Label: string, Documentation: string?, ParameterLabels: List<string>) {
        labelValue = Label
        documentationValue = Documentation
        parameterLabelsValue = ParameterLabels
    }
}

// WHAT A CALL BEING TYPED RESOLVES TO. The whole decision — which declarations the name means,
// what each of them is called, which one the arguments written so far point at, and which row of
// it the caret is in — is made here, so that a protocol handler has nothing left to decide.
//
// The resolution order is the one COMPLETION already follows, and it follows it for the same
// reason: a source declaration wins outright over a same-spelled type the process happens to have
// loaded, and metadata answers only when source was silent. That is why `Person.Create(` shows the
// project's `Person` and `Console.WriteLine(` shows the BCL's.
class SignatureHelpOverloadFacts {

    // THE WHOLE ANSWER for a call the argument facts have already located. Empty means "no
    // signature help here", which is the only thing a caller has to know.
    static func ResolveOverloads(call: SignatureHelpCallContext, units: List<SignatureHelpSourceUnit>, currentUnit: CompilationUnit?, semanticModel: SemanticModel?, catalog: EditorTypeCatalog?, line: int, column: int): List<SignatureHelpOverload> {
        if call.IsConstructor {
            return ConstructorOverloads(call.MethodName, units, currentUnit, catalog)
        }

        if call.ReceiverName == null {
            return FunctionOverloads(call.MethodName, units)
        }

        return MemberOverloads(call.ReceiverName ?? "", call.MethodName, units, currentUnit, semanticModel, catalog, line, column)
    }

    // ── free functions ────────────────────────────────────────────────────────────────────────

    // EVERY top-level `func` of that name across the program, in unit order. A project is allowed
    // to declare the name once per namespace, and a reader typing it wants to see the ones that
    // exist rather than the first one found.
    static func FunctionOverloads(name: string, units: List<SignatureHelpSourceUnit>): List<SignatureHelpOverload> {
        overloads := new List<SignatureHelpOverload>()
        for sourceUnit in units {
            for declaration in sourceUnit.Unit.Declarations {
                function := declaration as FunctionDeclaration
                if function != null && function.Name == name {
                    overloads.Add(FunctionOverload(function, function.Name, sourceUnit.SourceText))
                }
            }
        }

        return overloads
    }

    // ── constructors ──────────────────────────────────────────────────────────────────────────

    static func ConstructorOverloads(typeName: string, units: List<SignatureHelpSourceUnit>, currentUnit: CompilationUnit?, catalog: EditorTypeCatalog?): List<SignatureHelpOverload> {
        overloads := new List<SignatureHelpOverload>()
        simpleName := SimpleName(typeName)

        for sourceUnit in units {
            for declaration in sourceUnit.Unit.Declarations {
                if IsTypeDeclarationNamed(declaration, simpleName) {
                    AppendSourceConstructors(declaration, simpleName, sourceUnit.SourceText, overloads)
                }
            }
        }

        if overloads.Count > 0 {
            return overloads
        }

        clrType := ResolveTypeReceiver(typeName, units, currentUnit, catalog)
        if clrType == null {
            return overloads
        }

        constructors := clrType.GetConstructors()
        for constructor in constructors {
            overloads.Add(ClrConstructorOverload(clrType, constructor))
        }

        return overloads
    }

    static func AppendSourceConstructors(declaration: Declaration, typeName: string, sourceText: string?, overloads: List<SignatureHelpOverload>) {
        members := DeclarationFacts.GetDeclarationMembers(declaration)
        if members == null {
            return
        }

        index := 0
        while index < members.Count {
            constructor := members[index] as ConstructorDeclaration
            if constructor != null {
                parameterLabels := ParameterLabels(constructor.Parameters)
                overloads.Add(new SignatureHelpOverload(FormatLabel(typeName, parameterLabels, "void"), LeadingDocumentation(sourceText, constructor.Line), parameterLabels))
            }

            index = index + 1
        }
    }

    // ── members ───────────────────────────────────────────────────────────────────────────────

    // A DOT-QUALIFIED CALL. The receiver is resolved as a VALUE first — that is what the semantic
    // model can answer and what a local, a parameter or a field is — and only then as a TYPE NAME,
    // which is what a static call is written as. Each of the two, in turn, asks source before it
    // asks metadata.
    static func MemberOverloads(receiverName: string, methodName: string, units: List<SignatureHelpSourceUnit>, currentUnit: CompilationUnit?, semanticModel: SemanticModel?, catalog: EditorTypeCatalog?, line: int, column: int): List<SignatureHelpOverload> {
        valueType := ValueReceiverType(receiverName, semanticModel, line, column)
        if valueType != null {
            typeText := CompletionTypeTextFacts.FormatTypeText(valueType)
            sourceOverloads := SourceMemberOverloads(SimpleName(typeText), methodName, units)
            if sourceOverloads.Count > 0 {
                return sourceOverloads
            }

            valueClrType := CompletionReflectionFacts.ResolveCompletionReflectionType(valueType)
            if valueClrType != null {
                instanceOverloads := ClrMethodOverloads(valueClrType, methodName, false)
                if instanceOverloads.Count > 0 {
                    return instanceOverloads
                }
            }
        }

        // A TYPE NAME RECEIVER. `DeclarationReceiverName` is what strips the namespace a caller
        // wrote in front of a type of their own project, so `Catalog.Box.Method(` finds `Box`.
        declaredReceiver := SignatureHelpArgumentFacts.DeclarationReceiverName(receiverName, UnitNamespaceName(currentUnit))
        declaredOverloads := SourceMemberOverloads(SimpleName(declaredReceiver), methodName, units)
        if declaredOverloads.Count > 0 {
            return declaredOverloads
        }

        typeReceiver := ResolveTypeReceiver(receiverName, units, currentUnit, catalog)
        if typeReceiver != null {
            return ClrMethodOverloads(typeReceiver, methodName, true)
        }

        return new List<SignatureHelpOverload>()
    }

    static func ValueReceiverType(receiverName: string, semanticModel: SemanticModel?, line: int, column: int): TypeInfo? {
        if semanticModel == null || !IdentifierText.IsValid(receiverName) {
            return null
        }

        typeInfo := semanticModel.LookupIdentifierAtPosition(receiverName, line, column)
        if typeInfo == null {
            typeInfo = semanticModel.LookupIdentifier(receiverName)
        }

        if typeInfo == null || BuiltInTypes.IsUnknown(typeInfo) {
            return null
        }

        return typeInfo
    }

    static func SourceMemberOverloads(typeName: string, methodName: string, units: List<SignatureHelpSourceUnit>): List<SignatureHelpOverload> {
        overloads := new List<SignatureHelpOverload>()
        for sourceUnit in units {
            for declaration in sourceUnit.Unit.Declarations {
                if IsTypeDeclarationNamed(declaration, typeName) {
                    AppendSourceMembers(declaration, typeName, methodName, sourceUnit.SourceText, overloads)
                }
            }
        }

        return overloads
    }

    static func AppendSourceMembers(declaration: Declaration, typeName: string, methodName: string, sourceText: string?, overloads: List<SignatureHelpOverload>) {
        members := DeclarationFacts.GetDeclarationMembers(declaration)
        if members == null {
            return
        }

        index := 0
        while index < members.Count {
            member := members[index]
            function := member as FunctionDeclaration
            if function != null && function.Name == methodName {
                overloads.Add(FunctionOverload(function, function.Name, sourceText))
            }

            // A CONSTRUCTOR WRITTEN AS `Type.Type(` is the same declaration the `new` form finds,
            // and the shape the old resolution answered for it is preserved.
            constructor := member as ConstructorDeclaration
            if constructor != null && methodName == typeName {
                parameterLabels := ParameterLabels(constructor.Parameters)
                overloads.Add(new SignatureHelpOverload(FormatLabel(typeName, parameterLabels, "void"), LeadingDocumentation(sourceText, constructor.Line), parameterLabels))
            }

            index = index + 1
        }
    }

    // ── the metadata door ─────────────────────────────────────────────────────────────────────

    // EVERY overload of that name the CLR type declares, in reflection order. `IsOfferableMethod`
    // is the same gate completion uses, so an accessor the compiler synthesised never appears as a
    // callable signature.
    static func ClrMethodOverloads(clrType: Type, methodName: string, staticOnly: bool): List<SignatureHelpOverload> {
        overloads := new List<SignatureHelpOverload>()
        filter := CompletionMemberFilter.InstanceOnly
        if staticOnly {
            filter = CompletionMemberFilter.StaticOnly
        }

        methods := clrType.GetMethods(CompletionReflectionFacts.GetReflectionBindingFlags(filter))
        for method in methods {
            if CompletionReflectionFacts.IsOfferableMethod(method) && method.get_Name() == methodName {
                overloads.Add(ClrMethodOverload(method))
            }
        }

        return overloads
    }

    static func ClrMethodOverload(method: MethodInfo): SignatureHelpOverload {
        parameterLabels := ClrParameterLabels(method.GetParameters())
        return new SignatureHelpOverload(FormatLabel(method.get_Name(), parameterLabels, CompletionTypeTextFacts.FormatClrTypeText(method.get_ReturnType())), null, parameterLabels)
    }

    static func ClrConstructorOverload(clrType: Type, constructor: ConstructorInfo): SignatureHelpOverload {
        parameterLabels := ClrParameterLabels(constructor.GetParameters())
        return new SignatureHelpOverload(FormatLabel(ClrTypeSimpleName(clrType), parameterLabels, "void"), null, parameterLabels)
    }

    static func ClrParameterLabels(parameters: ParameterInfo[]): List<string> {
        labels := new List<string>()
        for parameter in parameters {
            name := parameter.get_Name() ?? "arg"
            labels.Add(name + ": " + CompletionTypeTextFacts.FormatClrTypeText(parameter.get_ParameterType()))
        }

        return labels
    }

    // A CONSTRUCTED TYPE'S REFLECTED NAME CARRIES ITS ARITY (`List\`1`), which no caller wrote and
    // no reader wants to read back. The backtick and everything after it goes.
    static func ClrTypeSimpleName(clrType: Type): string {
        name := clrType.get_Name()
        tick := name.IndexOf('`')
        if tick < 0 {
            return name
        }

        return name.Substring(0, tick)
    }

    // ── shared shaping ────────────────────────────────────────────────────────────────────────

    static func FunctionOverload(function: FunctionDeclaration, name: string, sourceText: string?): SignatureHelpOverload {
        parameterLabels := ParameterLabels(function.Parameters)
        return new SignatureHelpOverload(FormatLabel(name, parameterLabels, TypeReferenceFacts.GetDisplayNameOrVoid(function.ReturnType)), LeadingDocumentation(sourceText, function.Line), parameterLabels)
    }

    static func ParameterLabels(parameters: List<Parameter>): List<string> {
        labels := new List<string>()
        for parameter in parameters {
            labels.Add(parameter.Name + ": " + TypeReferenceFacts.GetDisplayNameOrVoid(parameter.Type))
        }

        return labels
    }

    static func FormatLabel(name: string, parameterLabels: List<string>, returnText: string): string {
        builder := new StringBuilder()
        builder.Append(name)
        builder.Append('(')
        index := 0
        while index < parameterLabels.Count {
            if index > 0 {
                builder.Append(", ")
            }

            builder.Append(parameterLabels[index])
            index = index + 1
        }

        builder.Append("): ")
        builder.Append(returnText)
        return builder.ToString()
    }

    static func LeadingDocumentation(sourceText: string?, declarationLine: int): string? {
        if sourceText == null {
            return null
        }

        documentation: string? = null
        if !CodeIntelligenceSourceTextKernels.TryExtractDocComment(sourceText, declarationLine, out documentation) {
            return null
        }

        return documentation
    }

    // ── receiver and declaration lookup ───────────────────────────────────────────────────────

    static func IsTypeDeclarationNamed(declaration: Declaration, name: string): bool {
        if DeclarationFacts.GetDeclarationMembers(declaration) == null {
            return false
        }

        return DeclarationFacts.GetDeclarationName(declaration) == name
    }

    // A TYPE THE CALLER SPELLED. The editor's type catalog holds the analyzer's own assembly
    // registry, so a package the project depends on answers here exactly as it answers for
    // completion; the built-in receiver table answers for the names the analyzer models directly.
    static func ResolveTypeReceiver(receiverName: string, units: List<SignatureHelpSourceUnit>, currentUnit: CompilationUnit?, catalog: EditorTypeCatalog?): Type? {
        known := CompletionReflectionFacts.KnownReceiverType(receiverName)
        if known != null {
            return known
        }

        if catalog == null {
            return null
        }

        resolved := catalog.ResolveType(receiverName)
        if resolved != null {
            return resolved
        }

        return catalog.ResolveType(SimpleName(receiverName))
    }

    static func UnitNamespaceName(unit: CompilationUnit?): string? {
        if unit == null {
            return null
        }

        namespaceDeclaration := unit.Namespace
        if namespaceDeclaration == null {
            return null
        }

        return namespaceDeclaration.Name
    }

    static func SimpleName(name: string): string {
        lastDot := name.LastIndexOf('.')
        if lastDot < 0 {
            return name
        }

        return name.Substring(lastDot + 1)
    }

    // ── which overload, and which row of it ───────────────────────────────────────────────────

    // THE OVERLOAD THE ARGUMENTS WRITTEN SO FAR POINT AT: the one whose arity the caller has
    // already matched, else the first that could still take what is being typed, else the first.
    static func SelectActiveOverload(overloads: List<SignatureHelpOverload>, argumentCount: int): int {
        index := 0
        while index < overloads.Count {
            if overloads[index].ParameterLabels.Count == argumentCount {
                return index
            }

            index = index + 1
        }

        index = 0
        while index < overloads.Count {
            if overloads[index].ParameterLabels.Count > argumentCount {
                return index
            }

            index = index + 1
        }

        return 0
    }

    // THE ROW THE CARET IS IN, asked of the overload that is actually being shown — a named
    // argument points at the row wearing that name, so the answer depends on which overload's rows
    // are on screen.
    static func ActiveParameter(overloads: List<SignatureHelpOverload>, activeOverload: int, argumentText: string): int {
        if activeOverload < 0 || activeOverload >= overloads.Count {
            return SignatureHelpArgumentFacts.ActiveParameterIndex(argumentText, new string[](0))
        }

        return SignatureHelpArgumentFacts.ActiveParameterIndex(argumentText, overloads[activeOverload].ParameterLabels.ToArray())
    }
}
