namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// WHICH TASK AN UNANNOTATED `async` METHOD RETURNS, AS THE ANALYZER SEES IT.
//
// `async func load(): string` wraps `string` in the project's `language.asyncDefaultType`
// (`AsyncTaskFamilyFacts`). A METHOD THAT FILLS A .NET SLOT IS THE EXCEPTION: the CLR binds an
// override or an interface implementation by its exact return type, so
// `override async func ExecuteAsync(token: CancellationToken)` on `BackgroundService` MUST return
// `Task`, whatever the project default is. The rule, in order:
//
//   1. `main` is the `Task` family (the async entry point);
//   2. an `override` takes the family of the base member it overrides — the nearest member of that
//      name and arity up the class chain, whether it is reflected metadata or a source declaration;
//   3. any other instance method takes the family of the interface member it implements — the
//      named interface for an explicit implementation (`func IWorker.RunAsync()`), else the first
//      member of that name and arity in the interfaces the type writes, including what those
//      interfaces inherit;
//   4. otherwise the project default.
//
// A source slot that is itself an unannotated `async` member answers with ITS family, by the same
// rule, so a chain of source overrides above one metadata member all agree with that member.
//
// THE ARITY IS THE OVERLOAD KEY, and the parameter types break a tie. `Stream.ReadAsync` returns
// `Task<int>` at three and four parameters and `ValueTask<int>` at two, so the count separates every
// overload pair the BCL ships; same-arity overloads that disagree about the family are told apart by
// the written parameter types, and when even that leaves both families the walk infers nothing and
// the project default stands. A slot that is found but is not a task at all infers nothing too.
// `SlotFor` answers WHICH slot was found, so `AnalyzerTypeDeclarations.ValidateAsyncSlotReturn` can
// name it when a declaration that WRITES its task type writes the other family.
//
// The columnar emitter makes the same choice from its own member tables
// (`ColumnarAsyncWrapperSelection`); the two must agree, and the native projects
// `tests/native/async-slot-inference` and `tests/native/async-default-type` hold them to it.
// The emitter matches by exact signature, so this walk reads the written parameter types whenever
// arity alone leaves two families: that is the one place the two could otherwise part ways.

// THE SLOT A METHOD FILLS, as far as the async rule cares: whose member it is, what that member
// returns, and that return's family (`-1` when it is not a task, or when same-arity overloads
// disagree about which task).
class AnalyzerAsyncSlot {
    Family: int
    OwnerName: string
    ReturnType: TypeInfo?
    IsInterface: bool

    constructor(family: int, ownerName: string, returnType: TypeInfo?, isInterface: bool) {
        Family = family
        OwnerName = ownerName
        ReturnType = returnType
        IsInterface = isInterface
    }
}

// THE MEMBER BEING MATCHED: its arity, and — read only when same-arity overloads disagree — the
// display of each written parameter type, resolved as the declaring type sees it.
class AnalyzerAsyncSlotQuery {
    ParameterCount: int
    declaration: FunctionDeclaration
    owner: TypeInfo
    context: AnalyzerDeclarationContext
    parameterDisplays: string[]?

    constructor(declarationValue: FunctionDeclaration, ownerValue: TypeInfo, contextValue: AnalyzerDeclarationContext) {
        declaration = declarationValue
        owner = ownerValue
        context = contextValue
        ParameterCount = declarationValue.Parameters.Count
        parameterDisplays = null
    }

    func MatchesParameters(parameters: ParameterInfo[]): bool {
        displays := ParameterDisplays()
        if displays.Length != parameters.Length {
            return false
        }

        index := 0
        while index < parameters.Length {
            parameterType := AnalyzerReflectionMemberProbe.ParameterTypeOrNull(parameters[index])
            if parameterType == null || displays[index].Length == 0 {
                return false
            }

            if displays[index] != TypeMismatchDisplay.Display(AnalyzerReflectionTypeConversion.ConvertReflectionType(parameterType)) {
                return false
            }

            index = index + 1
        }

        return true
    }

    func ParameterDisplays(): string[] {
        cached := parameterDisplays
        if cached != null {
            return cached
        }

        displays := new string[](ParameterCount)
        index := 0
        while index < ParameterCount {
            displays[index] = ""
            written := declaration.Parameters[index].Type
            resolved: TypeInfo = BuiltInTypes.Unknown
            if context.TryResolveTypeForOwner(written, owner, null, out resolved) && !BuiltInTypes.IsUnknown(resolved) {
                displays[index] = TypeMismatchDisplay.Display(resolved)
            }

            index = index + 1
        }

        parameterDisplays = displays
        return displays
    }
}

class AnalyzerAsyncReturnFamily {
    declarationContext: AnalyzerDeclarationContext

    static NotTaskFamily: int => -1

    constructor(context: AnalyzerDeclarationContext) {
        declarationContext = context
    }

    func FamilyFor(declaration: FunctionDeclaration): AsyncTaskFamily {
        return FamilyForCore(declaration, 0)
    }

    func FamilyForCore(declaration: FunctionDeclaration, depth: int): AsyncTaskFamily {
        if AsyncTaskFamilyFacts.IsEntryPointName(declaration.Name) {
            return AsyncTaskFamily.Task
        }

        slot := SlotForCore(declaration, depth)
        if slot != null && slot.Family >= 0 {
            return FamilyFromOrdinal(slot.Family)
        }

        return declarationContext.AsyncDefaultFamily
    }

    // The slot this declaration fills, or null when it fills none this walk can read. A static
    // member and a free function fill nothing; an `override` fills a base member; any other instance
    // method fills the interface member of its name and arity.
    func SlotFor(declaration: FunctionDeclaration): AnalyzerAsyncSlot? {
        return SlotForCore(declaration, 0)
    }

    func SlotForCore(declaration: FunctionDeclaration, depth: int): AnalyzerAsyncSlot? {
        if depth > 16 {
            return null
        }

        modifierBits := Convert.ToInt32(declaration.Modifiers)
        if (modifierBits & Convert.ToInt32(Modifiers.Static)) != 0 {
            return null
        }

        owner: TypeInfo = BuiltInTypes.Unknown
        if !declarationContext.TryGetMemberOwner(declaration, out owner) {
            return null
        }

        query := new AnalyzerAsyncSlotQuery(declaration, owner, declarationContext)
        if (modifierBits & Convert.ToInt32(Modifiers.Override)) != 0 {
            return BaseSlot(owner, declaration.Name, query, depth)
        }

        return InterfaceSlot(owner, declaration.Name, query, depth)
    }

    // ---- the base chain ------------------------------------------------------------------------

    func BaseSlot(owner: TypeInfo, name: string, query: AnalyzerAsyncSlotQuery, depth: int): AnalyzerAsyncSlot? {
        shape := new AnalyzerSourceMemberShape()
        if !declarationContext.TryGetSourceMemberShape(owner, null, out shape) {
            return null
        }

        return ChainSlot(shape.BaseType, name, query, depth, 0)
    }

    func ChainSlot(candidate: TypeInfo?, name: string, query: AnalyzerAsyncSlotQuery, depth: int, hops: int): AnalyzerAsyncSlot? {
        // `null` is the implicit `object`, which declares no task-returning slot.
        if candidate == null || hops > 24 || BuiltInTypes.IsUnknown(candidate) {
            return null
        }

        reflected := ReflectedTypeOf(candidate)
        if reflected != null {
            if reflected.IsInterface {
                return null
            }

            methods := AnalyzerReflectionMemberProbe.MethodsOrEmpty(reflected, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
            return ReflectedSlot(methods, name, query, true)
        }

        sourceType := SourceDefinitionOf(candidate)
        if sourceType as InterfaceTypeInfo != null {
            return null
        }

        shape := new AnalyzerSourceMemberShape()
        if !declarationContext.TryGetSourceMemberShape(sourceType, null, out shape) {
            return null
        }

        declared := SourceSlot(shape.Owner, shape.DeclaredMembers, name, query, depth, false)
        if declared != null {
            return declared
        }

        return ChainSlot(shape.BaseType, name, query, depth, hops + 1)
    }

    // ---- the interfaces the type writes --------------------------------------------------------

    func InterfaceSlot(owner: TypeInfo, name: string, query: AnalyzerAsyncSlotQuery, depth: int): AnalyzerAsyncSlot? {
        slotName := name
        qualifier: string? = null
        if ExplicitInterfaceMemberFacts.IsExplicitMemberName(name) {
            qualifier = ExplicitInterfaceMemberFacts.QualifierSimpleName(ExplicitInterfaceMemberFacts.QualifierOf(name))
            slotName = ExplicitInterfaceMemberFacts.SimpleNameOf(name)
        }

        for reference in WrittenInterfaceReferences(owner) {
            resolved: TypeInfo = BuiltInTypes.Unknown
            if !declarationContext.TryResolveTypeForOwner(reference, owner, null, out resolved) {
                continue
            }

            if qualifier != null && !string.Equals(InterfaceSimpleName(resolved), qualifier, StringComparison.Ordinal) {
                continue
            }

            found := InterfaceMemberSlot(resolved, slotName, query, depth, 0)
            if found != null {
                return found
            }
        }

        return null
    }

    func InterfaceMemberSlot(candidate: TypeInfo, name: string, query: AnalyzerAsyncSlotQuery, depth: int, hops: int): AnalyzerAsyncSlot? {
        if hops > 24 || BuiltInTypes.IsUnknown(candidate) {
            return null
        }

        reflected := ReflectedTypeOf(candidate)
        if reflected != null {
            if !reflected.IsInterface {
                return null
            }

            own := ReflectedSlot(AnalyzerReflectionMemberProbe.MethodsOrEmpty(reflected, BindingFlags.Public | BindingFlags.Instance), name, query, false)
            if own != null {
                return own
            }

            // `GetInterfaces` on an interface is its whole inherited closure, flattened.
            for inherited in AnalyzerReflectionMemberProbe.InterfacesOrEmpty(reflected) {
                inheritedSlot := ReflectedSlot(AnalyzerReflectionMemberProbe.MethodsOrEmpty(inherited, BindingFlags.Public | BindingFlags.Instance), name, query, false)
                if inheritedSlot != null {
                    return inheritedSlot
                }
            }

            return null
        }

        sourceType := SourceDefinitionOf(candidate)
        if sourceType as InterfaceTypeInfo == null {
            return null
        }

        shape := new AnalyzerSourceMemberShape()
        if !declarationContext.TryGetSourceMemberShape(sourceType, null, out shape) {
            return null
        }

        declared := SourceSlot(shape.Owner, shape.DeclaredMembers, name, query, depth, true)
        if declared != null {
            return declared
        }

        for baseInterface in shape.BaseInterfaces {
            inheritedSlot := InterfaceMemberSlot(baseInterface, name, query, depth, hops + 1)
            if inheritedSlot != null {
                return inheritedSlot
            }
        }

        return null
    }

    // THE PARSER SPLITS `: A, B` BY POSITION, so a class whose first entry is an interface carries it
    // in the base-class slot. Both are offered here; `InterfaceMemberSlot` keeps only interfaces.
    static func WrittenInterfaceReferences(owner: TypeInfo): List<TypeReference> {
        references := new List<TypeReference>()
        classType := owner as ClassTypeInfo
        if classType != null {
            baseClass := classType.BaseClass
            if baseClass != null {
                references.Add(baseClass)
            }

            references.AddRange(classType.Interfaces)
            return references
        }

        structType := owner as StructTypeInfo
        if structType != null {
            references.AddRange(structType.Interfaces)
            return references
        }

        recordType := owner as RecordTypeInfo
        if recordType != null {
            references.AddRange(recordType.Interfaces)
        }

        return references
    }

    static func InterfaceSimpleName(candidate: TypeInfo): string {
        reflected := ReflectedTypeOf(candidate)
        if reflected != null {
            return RuntimeSimpleName(reflected)
        }

        interfaceType := SourceDefinitionOf(candidate) as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.Name
        }

        return ""
    }

    static func RuntimeSimpleName(candidate: Type): string {
        name := candidate.Name
        tick := name.IndexOf('`')
        if tick > 0 {
            return name.Substring(0, tick)
        }

        return name
    }

    // ---- reading one slot ----------------------------------------------------------------------

    // A source level's own members: the FIRST function of the name and arity decides.
    func SourceSlot(owner: TypeInfo, members: DeclaredMemberInfo[], name: string, query: AnalyzerAsyncSlotQuery, depth: int, isInterface: bool): AnalyzerAsyncSlot? {
        for member in members {
            if member.Kind == DeclaredMemberKind.Function && member.Name == name && member.ParameterCount == query.ParameterCount {
                return DeclaredMemberSlot(owner, member, depth, isInterface)
            }
        }

        return null
    }

    func DeclaredMemberSlot(owner: TypeInfo, member: DeclaredMemberInfo, depth: int, isInterface: bool): AnalyzerAsyncSlot {
        ownerName := SourceOwnerName(owner)
        declaredReturn: TypeInfo = BuiltInTypes.Void
        returnReference := member.ReturnType
        if returnReference != null {
            resolved: TypeInfo = BuiltInTypes.Unknown
            if !declarationContext.TryResolveTypeForOwner(returnReference, owner, null, out resolved) {
                return new AnalyzerAsyncSlot(NotTaskFamily, ownerName, null, isInterface)
            }

            declaredReturn = resolved
        }

        if member.IsAsync && !member.IsGenerator && AnalyzerFunctionTypeFactory.WrapsAsyncReturn(true, false, declaredReturn) {
            family := declarationContext.AsyncDefaultFamily
            source := member.SourceDeclaration
            if source != null {
                family = FamilyForCore(source, depth + 1)
            }

            wrapped := AnalyzerFunctionTypeFactory.ResolveFunctionCallReturnType(true, false, declaredReturn, family)
            return new AnalyzerAsyncSlot(FamilyOrdinal(family), ownerName, wrapped, isInterface)
        }

        return new AnalyzerAsyncSlot(FamilyOfType(declaredReturn), ownerName, declaredReturn, isInterface)
    }

    // Metadata's answer for one level. Same-arity overloads that agree about the family answer it
    // at once; overloads that DISAGREE are told apart by the written parameter types, and when that
    // still leaves both families the walk infers nothing. An override target must also be an open
    // slot (virtual and not sealed).
    static func ReflectedSlot(methods: MethodInfo[], name: string, query: AnalyzerAsyncSlotQuery, requireOverridable: bool): AnalyzerAsyncSlot? {
        candidates := new List<AnalyzerAsyncSlot>()
        exact := new List<AnalyzerAsyncSlot>()
        for method in methods {
            if method.Name != name || method.IsSpecialName {
                continue
            }

            if requireOverridable && (!method.IsVirtual || method.IsFinal) {
                continue
            }

            parameters := AnalyzerReflectionMemberProbe.ParametersOrNull(method)
            if parameters == null || parameters.Length != query.ParameterCount {
                continue
            }

            returnType := AnalyzerReflectionMemberProbe.ReturnTypeOrNull(method)
            family := NotTaskFamily
            returnInfo: TypeInfo? = null
            if returnType != null {
                family = FamilyOfRuntimeType(returnType)
                returnInfo = AnalyzerReflectionTypeConversion.ConvertReflectionType(returnType)
            }

            ownerName := name
            declaringType := method.DeclaringType
            if declaringType != null {
                ownerName = RuntimeSimpleName(declaringType)
            }

            slot := new AnalyzerAsyncSlot(family, ownerName, returnInfo, requireOverridable == false)
            candidates.Add(slot)
            if query.MatchesParameters(parameters) {
                exact.Add(slot)
            }
        }

        if candidates.Count == 0 {
            return null
        }

        agreed := AgreedSlot(candidates)
        if agreed != null {
            return agreed
        }

        exactAgreed := AgreedSlot(exact)
        if exactAgreed != null {
            return exactAgreed
        }

        return new AnalyzerAsyncSlot(NotTaskFamily, candidates[0].OwnerName, null, candidates[0].IsInterface)
    }

    // The first candidate when every candidate names the same family, else null.
    static func AgreedSlot(candidates: List<AnalyzerAsyncSlot>): AnalyzerAsyncSlot? {
        if candidates.Count == 0 {
            return null
        }

        first := candidates[0]
        for candidate in candidates {
            if candidate.Family != first.Family {
                return null
            }
        }

        return first
    }

    static func SourceOwnerName(owner: TypeInfo): string {
        classType := owner as ClassTypeInfo
        if classType != null {
            return classType.Name
        }

        interfaceType := owner as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.Name
        }

        structType := owner as StructTypeInfo
        if structType != null {
            return structType.Name
        }

        recordType := owner as RecordTypeInfo
        if recordType != null {
            return recordType.Name
        }

        boxed := owner as object
        return boxed.ToString() ?? ""
    }

    // ---- what a type IS --------------------------------------------------------------------------

    static func FamilyOfType(candidate: TypeInfo): int {
        reflected := ReflectedTypeOf(candidate)
        if reflected != null {
            return FamilyOfRuntimeType(reflected)
        }

        return NotTaskFamily
    }

    static func FamilyOfRuntimeType(candidate: Type): int {
        definition := candidate
        if candidate.IsGenericType && !candidate.IsGenericTypeDefinition {
            definition = candidate.GetGenericTypeDefinition()
        }

        if AnalyzerFunctionTypeFactory.IsCoreTaskFamilyType(definition, "System.Threading.Tasks.Task") || AnalyzerFunctionTypeFactory.IsCoreTaskFamilyType(definition, "System.Threading.Tasks.Task`1") {
            return FamilyOrdinal(AsyncTaskFamily.Task)
        }

        if AnalyzerFunctionTypeFactory.IsCoreTaskFamilyType(definition, "System.Threading.Tasks.ValueTask") || AnalyzerFunctionTypeFactory.IsCoreTaskFamilyType(definition, "System.Threading.Tasks.ValueTask`1") {
            return FamilyOrdinal(AsyncTaskFamily.ValueTask)
        }

        return NotTaskFamily
    }

    // The metadata type behind a reflected TypeInfo — a plain one, or a constructed generic whose
    // definition is reflected (`Collection<int>`, `Task<string>`). The family and the member list do
    // not depend on the type arguments.
    static func ReflectedTypeOf(candidate: TypeInfo): Type? {
        reflection := candidate as ReflectionTypeInfo
        if reflection != null {
            return reflection.Type
        }

        generic := candidate as GenericTypeInfo
        if generic != null {
            definition := generic.GenericDefinition as ReflectionTypeInfo
            if definition != null {
                return definition.Type
            }
        }

        return null
    }

    // A constructed SOURCE generic (`Repository<User>`) reads its members from its definition.
    static func SourceDefinitionOf(candidate: TypeInfo): TypeInfo {
        generic := candidate as GenericTypeInfo
        if generic != null {
            definition := generic.GenericDefinition
            if definition != null {
                return definition
            }
        }

        return candidate
    }

    static func FamilyOrdinal(family: AsyncTaskFamily): int {
        if family == AsyncTaskFamily.Task {
            return 1
        }

        return 0
    }

    static func FamilyFromOrdinal(ordinal: int): AsyncTaskFamily {
        if ordinal == 1 {
            return AsyncTaskFamily.Task
        }

        return AsyncTaskFamily.ValueTask
    }
}
