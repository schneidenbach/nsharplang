namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler.Ast


// The analyzer's type-reference resolution walk: the sole authority for turning a `TypeReference`
// into a `TypeInfo`, for every diagnostic that walk reports, and for every semantic-model and
// binding-map record it writes.
//
// Everything the walk consults is an N# owner handed in by argument — the scope stack, the
// declaration context, project discovery, the external metadata probe, the pure fact tables, the
// diagnostic sink, the semantic model and the binding map — so the walk names no compiler shell and
// there is no callback in either direction.
//
// THE EIGHT CHANNELS, in order, are the whole of `ResolveSimpleType`: the built-in name table, the
// scope stack, the current file's import aliases, a dotted nested type, project-wide discovery, a
// namespace alias resolved as a type, the referenced-assembly probe, and finally an unresolved
// `ExternalTypeInfo` placeholder. The order is behaviour: a local declaration shadows a project
// type, and a project type outranks a CLR type of the same name.
//
// THE TEN REPORT SITES it owns: NL201 for a claimed file alias, for an undotted simple name and for
// a generic name; NL207 for a multi-arity spelling and for an arity mismatch; NL103 for `var` used
// as a type and for a SoA row reference; NL306 and NL207 for a repeated and an over-wide anonymous
// union; and NL308 for an inaccessible project declaration.
//
// THE DEDUPE DISCIPLINE: the unresolved-reference set is keyed by (name, line, column) and is shared
// by all five NL201/NL207 sites AND by the two inaccessible-member reports the shell still owns
// outside this walk, so the first report at a position suppresses every later one there. The SoA-row
// set is separate because its report is not an unresolved-type report. Both are cleared once per
// analysis, and `reportUnresolvedTypes` starts every analysis OFF.
class AnalyzerTypeResolver {
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    projectDiscoveryValue: AnalyzerProjectTypeDiscovery
    externalTypeProbeValue: AnalyzerExternalTypeProbe
    diagnosticsValue: AnalyzerDiagnosticSink
    usingAliasesValue: Dictionary<string, string>
    importedSymbolsByAliasValue: Dictionary<string, Dictionary<string, TypeInfo>>
    importedDeclarationsByAliasValue: Dictionary<string, Dictionary<string, SymbolDeclaration>>
    wellKnownTypesValue: AnalyzerWellKnownTypes?
    semanticModelValue: SemanticModel
    bindingsValue: BindingMap
    currentFilePathValue: string?
    compilationUnitValue: CompilationUnit?
    reportUnresolvedTypesValue: bool
    reportedUnresolvedTypeRefsValue: Dictionary<(Name: string, Line: int, Column: int), bool>
    reportedSoaRowTypeRefsValue: Dictionary<(Name: string, Line: int, Column: int), bool>

    constructor(scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, projectDiscovery: AnalyzerProjectTypeDiscovery, externalTypeProbe: AnalyzerExternalTypeProbe, diagnostics: AnalyzerDiagnosticSink, usingAliases: Dictionary<string, string>, importedSymbolsByAlias: Dictionary<string, Dictionary<string, TypeInfo>>, importedDeclarationsByAlias: Dictionary<string, Dictionary<string, SymbolDeclaration>>, semanticModel: SemanticModel, bindings: BindingMap) {
        scopesValue = scopes
        declarationContextValue = declarationContext
        projectDiscoveryValue = projectDiscovery
        externalTypeProbeValue = externalTypeProbe
        diagnosticsValue = diagnostics
        usingAliasesValue = usingAliases
        importedSymbolsByAliasValue = importedSymbolsByAlias
        importedDeclarationsByAliasValue = importedDeclarationsByAlias
        wellKnownTypesValue = null
        semanticModelValue = semanticModel
        bindingsValue = bindings
        currentFilePathValue = null
        compilationUnitValue = null
        reportUnresolvedTypesValue = false
        reportedUnresolvedTypeRefsValue = new Dictionary<(Name: string, Line: int, Column: int), bool>()
        reportedSoaRowTypeRefsValue = new Dictionary<(Name: string, Line: int, Column: int), bool>()
    }

    // One call per analysis, from the analyzer's own reset block. The semantic model and the binding
    // map are REPLACED per analysis, not cleared, so they arrive here rather than being held from
    // construction.
    func BeginAnalysis(filePath: string?, unit: CompilationUnit?, semanticModel: SemanticModel, bindings: BindingMap) {
        currentFilePathValue = filePath
        compilationUnitValue = unit
        semanticModelValue = semanticModel
        bindingsValue = bindings
        reportUnresolvedTypesValue = false
        reportedUnresolvedTypeRefsValue.Clear()
        reportedSoaRowTypeRefsValue.Clear()
    }

    // The well-known-type bag is rebuilt, never mutated, so the resolver is told about the new bag
    // rather than being rebuilt itself: rebuilding would drop the dedupe sets mid-analysis.
    func SetWellKnownTypes(wellKnownTypes: AnalyzerWellKnownTypes?) {
        wellKnownTypesValue = wellKnownTypes
    }

    // Resolves a type reference at a DECLARED-type position (parameter, return, field, property,
    // variable annotation, type alias, or `new` expression) and reports NL201 when a simple name
    // resolves through no channel. Only these positions opt in: pass-1 signature collection and lazy
    // cross-file member resolution run without generic type parameters in scope and must stay lenient
    // to avoid false positives.
    func ResolveDeclaredType(typeRef: TypeReference): TypeInfo {
        previous := reportUnresolvedTypesValue
        reportUnresolvedTypesValue = true
        resolved: TypeInfo = BuiltInTypes.Unknown
        try {
            resolved = ResolveType(typeRef)
        } finally {
            reportUnresolvedTypesValue = previous
        }

        return resolved
    }

    func ResolveType(typeRef: TypeReference): TypeInfo {
        resolved := ResolveTypeCore(typeRef)
        RecordResolvedTypeReference(typeRef, resolved)
        return resolved
    }

    func ResolveTypeIfPresent(typeReference: TypeReference?) {
        if typeReference != null {
            ResolveType(typeReference)
        }
    }

    func ResolveTypeReferences(typeReferences: List<TypeReference>) {
        index := 0
        while index < typeReferences.Count {
            ResolveType(typeReferences[index])
            index = index + 1
        }
    }

    func ResolveGenericConstraintTypes(constraints: List<GenericConstraint>?) {
        if constraints == null {
            return
        }

        index := 0
        while index < constraints.Count {
            ResolveTypeReferences(constraints[index].Constraints)
            index = index + 1
        }
    }

    func ResolveTypeCore(typeRef: TypeReference): TypeInfo {
        simple := typeRef as SimpleTypeReference
        if simple != null {
            return ResolveSimpleTypeReference(simple)
        }

        generic := typeRef as GenericTypeReference
        if generic != null {
            return ResolveGenericTypeReference(generic)
        }

        array := typeRef as ArrayTypeReference
        if array != null {
            return new ArrayTypeInfo(ResolveType(array.ElementType))
        }

        nullable := typeRef as NullableTypeReference
        if nullable != null {
            return new NullableTypeInfo(ResolveType(nullable.InnerType))
        }

        unionReference := typeRef as UnionTypeReference
        if unionReference != null {
            return ResolveAnonymousUnionType(unionReference)
        }

        tuple := typeRef as TupleTypeReference
        if tuple != null {
            elements := new List<TupleTypeElementInfo>()
            elementIndex := 0
            while elementIndex < tuple.Elements.Count {
                element := tuple.Elements[elementIndex]
                elements.Add(new TupleTypeElementInfo(element.Name, ResolveType(element.Type)))
                elementIndex = elementIndex + 1
            }
            return new TupleTypeInfo(elements)
        }

        functionReference := typeRef as FunctionTypeReference
        if functionReference != null {
            parameterTypes := new List<TypeInfo>()
            parameterIndex := 0
            while parameterIndex < functionReference.ParameterTypes.Count {
                parameterTypes.Add(ResolveType(functionReference.ParameterTypes[parameterIndex]))
                parameterIndex = parameterIndex + 1
            }

            functionType := new FunctionTypeInfo()
            functionType.ParameterTypes = parameterTypes
            functionType.ReturnType = ResolveType(functionReference.ReturnType)
            return functionType
        }

        byRef := typeRef as ByRefTypeReference
        if byRef != null {
            return new ByRefTypeInfo(ResolveType(byRef.InnerType))
        }

        return BuiltInTypes.Unknown
    }

    // Fires for EVERY reference the walk resolves, at the reference's own start span. This is what
    // hover, go-to-definition on a type annotation and the semantic-token pass read.
    func RecordResolvedTypeReference(typeRef: TypeReference, resolved: TypeInfo) {
        span := TypeReferenceFacts.GetStartSpan(typeRef)
        if !span.IsValid {
            return
        }

        semanticModelValue.RecordTypeReference(span.StartLine, span.StartColumn, resolved)
    }

    func ResolveSimpleTypeReference(simple: SimpleTypeReference): TypeInfo {
        if ReportSoaRowTypeReferenceIfNeeded(simple.Name, simple.Line, simple.Column) {
            return BuiltInTypes.Unknown
        }

        return ResolveSimpleType(simple.Name, simple.Line, simple.Column)
    }

    func ResolveGenericTypeReference(generic: GenericTypeReference): TypeInfo {
        if generic.Line > 0 {
            if ReportSoaRowTypeReferenceIfNeeded(generic.Name, generic.Line, generic.Column) {
                return BuiltInTypes.Unknown
            }
        }

        typeArguments := new List<TypeInfo>()
        argumentIndex := 0
        while argumentIndex < generic.TypeArguments.Count {
            typeArguments.Add(ResolveType(generic.TypeArguments[argumentIndex]))
            argumentIndex = argumentIndex + 1
        }

        genericDefinition: TypeInfo? = null

        if generic.Line > 0 {
            genericDefinition = ResolveGenericHead(generic)
        }

        return new GenericTypeInfo(generic.Name, typeArguments, genericDefinition)
    }

    // The open-generic HEAD of `Name<...>`: resolved for its binding and semantic-model side effects,
    // then arity-checked. Unresolved reporting is suppressed for the head probe itself because CLR
    // open generics carry an arity suffix (`List` resolves as ``List`1``), so the plain simple-name
    // probe legitimately misses external generic types; the three reports below are the ones that
    // decide, and they all consult the CALLER's opt-in rather than the suppressed one.
    func ResolveGenericHead(generic: GenericTypeReference): TypeInfo? {
        genericDefinition: TypeInfo? = null
        previousReport := reportUnresolvedTypesValue
        reportUnresolvedTypesValue = false
        resolvedName: TypeInfo = BuiltInTypes.Unknown
        try {
            resolvedName = ResolveSimpleType(generic.Name, generic.Line, generic.Column)
        } finally {
            reportUnresolvedTypesValue = previousReport
        }

        resolvedExternal := resolvedName as ExternalTypeInfo
        if resolvedExternal == null && !BuiltInTypes.IsUnknown(resolvedName) {
            genericDefinition = resolvedName
        }

        genericHeadArity := AnalyzerTypeReferenceFacts.GenericHeadArity(resolvedName)
        arityQualifiedExternalType: Type? = null
        knownGenericHeadArities: List<int>? = null
        resolvedReflection := resolvedName as ReflectionTypeInfo
        if resolvedExternal != null || resolvedReflection != null {
            arityQualifiedExternalType = AnalyzerWellKnownTypeFacts.KnownOpenGenericType(wellKnownTypesValue, generic.Name, generic.TypeArguments.Count)
            if arityQualifiedExternalType == null {
                arityQualified := externalTypeProbeValue.ResolveExternalType(generic.Name + "`" + generic.TypeArguments.Count.ToString())
                arityQualifiedExternal := arityQualified as ReflectionTypeInfo
                if arityQualifiedExternal != null {
                    arityQualifiedExternalType = arityQualifiedExternal.Type
                }
            }

            if arityQualifiedExternalType != null {
                genericHeadArity = generic.TypeArguments.Count
                genericDefinition = new ReflectionTypeInfo(arityQualifiedExternalType)
            } else {
                knownGenericHeadArities = externalTypeProbeValue.KnownGenericHeadArities(wellKnownTypesValue, generic.Name)
                if knownGenericHeadArities.Count == 1 {
                    genericHeadArity = knownGenericHeadArities[0]
                }
            }
        }

        // Report the generic name as unresolved only when it is not compiler-known
        // (Result, Task, Func, ...) and the arity-qualified external probe also misses
        // (e.g. `Lst<int>` instead of `List<int>`).
        noKnownArities := knownGenericHeadArities == null || knownGenericHeadArities.Count == 0
        if previousReport && resolvedExternal != null && !generic.Name.Contains(".") && arityQualifiedExternalType == null && noKnownArities {
            if MarkUnresolvedTypeReported(generic.Name, generic.Line, generic.Column) {
                diagnosticsValue.Report(ErrorCode.TypeNotFound, "Type '" + generic.Name + "' not found", generic.Line, generic.Column, AnalyzerDiagnostics.UnresolvedTypeSuggestion(generic.Name, scopesValue.AllTypeNamesInScope()), generic.Name.Length)
            }
        }

        if previousReport && knownGenericHeadArities != null && knownGenericHeadArities.Count > 1 {
            if MarkUnresolvedTypeReported(generic.Name, generic.Line, generic.Column) {
                diagnosticsValue.Report(ErrorCode.InvalidTypeArgument, "Generic type '" + generic.Name + "' does not take " + generic.TypeArguments.Count.ToString() + " type argument(s); available arities are " + JoinArities(knownGenericHeadArities), generic.Line, generic.Column, "Use one of the supported type-argument counts for '" + generic.Name + "'.", generic.Name.Length)
            }
        }

        // Arity validation for locally-declared generic types: a wrong count previously sailed
        // through analysis and the emitter produced an unloadable assembly (TypeLoadException at
        // runtime). Reported at declared-type positions only, with the same dedupe as NL201 (this
        // resolver runs in both analysis passes).
        if previousReport && genericHeadArity >= 0 && genericHeadArity != generic.TypeArguments.Count {
            if MarkUnresolvedTypeReported(generic.Name, generic.Line, generic.Column) {
                message := "Generic type '" + generic.Name + "' takes " + genericHeadArity.ToString() + " type argument(s), but " + generic.TypeArguments.Count.ToString() + " were provided"
                suggestion := "Match the declaration's type parameter count for '" + generic.Name + "'"
                if genericHeadArity == 0 {
                    message = "'" + generic.Name + "' is not generic, but " + generic.TypeArguments.Count.ToString() + " type argument(s) were provided"
                    suggestion = "Remove the type arguments: '" + generic.Name + "'"
                }

                diagnosticsValue.Report(ErrorCode.InvalidTypeArgument, message, generic.Line, generic.Column, suggestion, generic.Name.Length)
            }
        }

        return genericDefinition
    }

    // NL103. A `Table.Row` reference is legal syntax but is not part of this lowering: row views
    // exist only as `table[index].column` projection syntax, so a row-typed parameter, field or
    // local is refused rather than silently emitted. Gated on the experimental SoA feature, on a
    // real source position, and on the prefix actually naming a SoA table.
    func ReportSoaRowTypeReferenceIfNeeded(name: string, line: int, column: int): bool {
        rowSuffix := ".Row"
        if !SoaFeature.IsEnabled || line <= 0 || !name.EndsWith(rowSuffix, StringComparison.Ordinal) {
            return false
        }

        tableName := name.Substring(0, name.Length - rowSuffix.Length)
        if tableName.Length == 0 {
            return false
        }

        tableCandidate := scopesValue.LookupType(tableName)
        resolvedTable: TypeInfo = BuiltInTypes.Unknown
        if tableCandidate != null {
            resolvedTable = declarationContextValue.ResolveDeclaredAlias(tableCandidate)
        } else {
            resolvedTable = declarationContextValue.ResolveDeclaredAlias(BuiltInTypes.Unknown)
        }

        if resolvedTable as SoaRecordTypeInfo == null {
            return false
        }

        if MarkSoaRowTypeReported(name, line, column) {
            diagnosticsValue.Report(ErrorCode.InvalidSyntax, "SoA row type '" + name + "' is not part of this lowering", line, column, "Pass the '" + tableName + "' table and an int row index instead; row views exist only as table[index].column projection syntax.", name.Length)
        }

        return true
    }

    // An anonymous `A | B`: arms are resolved left to right, a nested anonymous union is FLATTENED
    // into its parent, repeats are dropped with NL306, and more than two distinct arms is NL207.
    // Both reports point at the union's own start span, which is its first arm.
    func ResolveAnonymousUnionType(unionReference: UnionTypeReference): TypeInfo {
        resolvedArms := new List<TypeInfo>()
        armIndex := 0
        while armIndex < unionReference.Arms.Count {
            arm := ResolveType(unionReference.Arms[armIndex])
            nested := arm as AnonymousUnionTypeInfo
            if nested != null {
                nestedIndex := 0
                while nestedIndex < nested.Arms.Count {
                    resolvedArms.Add(nested.Arms[nestedIndex])
                    nestedIndex = nestedIndex + 1
                }
            } else {
                resolvedArms.Add(arm)
            }
            armIndex = armIndex + 1
        }

        uniqueArms := new List<TypeInfo>()
        candidateIndex := 0
        while candidateIndex < resolvedArms.Count {
            arm := resolvedArms[candidateIndex]
            candidateIndex = candidateIndex + 1
            if ContainsArm(uniqueArms, arm) {
                armObject := arm as object
                span := TypeReferenceFacts.GetStartSpan(unionReference)
                diagnosticsValue.Report(ErrorCode.DuplicateDeclaration, "Anonymous union type repeats arm '" + armObject.ToString() + "'. Each arm must be unique.", span.StartLine, span.StartColumn, "Remove the duplicate arm, or declare a named union if the repeated shape represents different cases.", UnionReportLength(unionReference))
                continue
            }

            uniqueArms.Add(arm)
        }

        if uniqueArms.Count > 2 {
            span := TypeReferenceFacts.GetStartSpan(unionReference)
            diagnosticsValue.Report(ErrorCode.InvalidTypeArgument, "Anonymous union types support exactly two arms in v1; this union has " + uniqueArms.Count.ToString() + " arms.", span.StartLine, span.StartColumn, "Declare a named `union` for larger variants.", UnionReportLength(unionReference))
        }

        return new AnonymousUnionTypeInfo(uniqueArms)
    }

    // The eight-channel name walk. `line <= 0` means "no source position": the walk still resolves,
    // but records no binding and reports nothing.
    func ResolveSimpleType(name: string, line: int, column: int): TypeInfo {
        if name == "var" && line > 0 {
            diagnosticsValue.Report(ErrorCode.InvalidSyntax, "'var' is not a type; use ':=' for type inference", line, column, null, 0)
            return BuiltInTypes.Unknown
        }

        builtInType := AnalyzerTypeReferenceFacts.BuiltInSimpleType(name)
        if builtInType != null {
            return builtInType
        }

        localType := scopesValue.LookupType(name)
        if localType != null {
            if line > 0 {
                scopesValue.RecordTypeBinding(bindingsValue, currentFilePathValue, name, line, column)
            }
            return localType
        }

        fileAliasType: TypeInfo = BuiltInTypes.Unknown
        fileAliasDeclaration: SymbolDeclaration? = null
        fileAliasClaimed := false
        if declarationContextValue.TryResolveFileImportAliasType(name, currentFilePathValue, importedSymbolsByAliasValue, importedDeclarationsByAliasValue, out fileAliasType, out fileAliasDeclaration, out fileAliasClaimed) {
            if line > 0 && fileAliasDeclaration != null {
                bindingsValue.RecordBinding(currentFilePathValue, line, column, name.Length, fileAliasDeclaration)
            }
            semanticModelValue.RecordType(name, fileAliasType)
            return fileAliasType
        }
        if fileAliasClaimed {
            if reportUnresolvedTypesValue && line > 0 {
                if MarkUnresolvedTypeReported(name, line, column) {
                    diagnosticsValue.Report(ErrorCode.TypeNotFound, "Type '" + name + "' not found in the imported file alias", line, column, "Use a public type exported by that file, or correct the alias-qualified type name.", name.Length)
                }
            }
            return BuiltInTypes.Unknown
        }

        nestedType: TypeInfo = BuiltInTypes.Unknown
        if TryResolveDottedNestedType(name, out nestedType) {
            return nestedType
        }

        projectType: TypeInfo = BuiltInTypes.Unknown
        projectDeclaration: SymbolDeclaration? = null
        inaccessibleProjectFile: string? = null
        if projectDiscoveryValue.ResolveVisibleProjectType(name, AnalyzerProjectSourceProvider.UnitNamespace(compilationUnitValue), line > 0, out projectType, out projectDeclaration, out inaccessibleProjectFile) {
            if line > 0 {
                // `ResolveVisibleProjectType` materialises the declaration BEFORE it answers true
                // (`TryMaterializeProjectTypeSelection` assigns one on its only success path), so the
                // narrowing below never falls through; it is here because the `out` parameter's
                // declared type is nullable, not because the declaration can be absent.
                if projectDeclaration != null {
                    bindingsValue.RecordBinding(currentFilePathValue, line, column, name.Length, projectDeclaration)
                }
            }

            semanticModelValue.RecordType(name, projectType)
            return projectType
        }

        if inaccessibleProjectFile != null {
            diagnosticsValue.ReportInaccessibleMember(name, inaccessibleProjectFile, line, column)
            MarkUnresolvedTypeReported(name, line, column)
        }

        aliasedFullName := ""
        if usingAliasesValue.TryGetValue(name, out aliasedFullName) {
            aliasedType := externalTypeProbeValue.ResolveExternalType(aliasedFullName)
            if aliasedType != null {
                return aliasedType
            }
        }

        externalType := externalTypeProbeValue.ResolveExternalType(name)
        if externalType != null {
            return externalType
        }

        // No resolution channel recognized this name. Historically this always fell through
        // silently ("might be from an external library"), letting typos and missing references reach
        // IL emission. At declared-type positions (ResolveDeclaredType) report undotted names
        // as NL201; dotted names stay lenient for now because namespace-qualified externals
        // and `new Union.Case` references legitimately resolve through other channels.
        if reportUnresolvedTypesValue && line > 0 && !name.Contains(".") {
            if MarkUnresolvedTypeReported(name, line, column) {
                diagnosticsValue.Report(ErrorCode.TypeNotFound, "Type '" + name + "' not found", line, column, AnalyzerDiagnostics.UnresolvedTypeSuggestion(name, scopesValue.AllTypeNamesInScope()), name.Length)
            }
        }

        return new ExternalTypeInfo(name)
    }

    // `Outer.Inner.Leaf`: the root must be a type IN SCOPE (a project or CLR type is a different
    // channel), and every remaining segment must be a nested member of the previous one. Exported-ness
    // is not required — a nested type is as visible as its owner.
    func TryResolveDottedNestedType(name: string, out typeInfo: TypeInfo): bool {
        parts := SplitNonEmpty(name)
        if parts.Count < 2 {
            typeInfo = BuiltInTypes.Unknown
            return false
        }

        rootCandidate := scopesValue.LookupType(parts[0])
        if rootCandidate != null {
            typeInfo = declarationContextValue.ResolveDeclaredAlias(rootCandidate)
        } else {
            typeInfo = declarationContextValue.ResolveDeclaredAlias(BuiltInTypes.Unknown)
        }

        if BuiltInTypes.IsUnknown(typeInfo) {
            return false
        }

        index := 1
        while index < parts.Count {
            // The nested answer lands in its own local rather than aliasing the `out` parameter that
            // is also the owner argument of the same call.
            nested: TypeInfo = BuiltInTypes.Unknown
            if !declarationContextValue.TryResolveNestedType(typeInfo, parts[index], false, out nested) {
                typeInfo = BuiltInTypes.Unknown
                return false
            }
            typeInfo = nested
            index = index + 1
        }

        return true
    }

    // Records a position as already reported WITHOUT reporting anything, and answers whether this
    // call is the first one at that position. Two report sites outside this walk — the `new
    // Union.Case` inaccessible probe and the identifier-binding inaccessible probe — share the set,
    // so a later NL201 at the same position stays suppressed.
    func MarkUnresolvedTypeReported(name: string, line: int, column: int): bool {
        key := (Name: name, Line: line, Column: column)
        if reportedUnresolvedTypeRefsValue.ContainsKey(key) {
            return false
        }

        reportedUnresolvedTypeRefsValue[key] = true
        return true
    }

    func MarkSoaRowTypeReported(name: string, line: int, column: int): bool {
        key := (Name: name, Line: line, Column: column)
        if reportedSoaRowTypeRefsValue.ContainsKey(key) {
            return false
        }

        reportedSoaRowTypeRefsValue[key] = true
        return true
    }

    static func ContainsArm(arms: List<TypeInfo>, candidate: TypeInfo): bool {
        index := 0
        while index < arms.Count {
            if TypeInfoIdentityFacts.AreEqual(arms[index], candidate) {
                return true
            }
            index = index + 1
        }

        return false
    }

    // The union's own span when it has one, and one column otherwise: the report is anchored at the
    // first arm but underlines the whole union.
    static func UnionReportLength(unionReference: UnionTypeReference): int {
        if unionReference.Span.IsValid {
            return Math.Max(1, unionReference.Span.EndColumn - unionReference.Span.StartColumn)
        }

        return 1
    }

    static func JoinArities(arities: List<int>): string {
        builder := new StringBuilder()
        index := 0
        while index < arities.Count {
            if index > 0 {
                builder.Append(", ")
            }
            builder.Append(arities[index].ToString())
            index = index + 1
        }

        return builder.ToString()
    }

    // `name.Split('.', StringSplitOptions.RemoveEmptyEntries)`: empty segments are dropped, so
    // `A..B` is two parts and `.` alone is none.
    static func SplitNonEmpty(name: string): List<string> {
        parts := new List<string>()
        raw := name.Split('.')
        index := 0
        while index < raw.Length {
            if raw[index].Length > 0 {
                parts.Add(raw[index])
            }
            index = index + 1
        }

        return parts
    }
}
