namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// Every `FunctionTypeInfo` the analyzer builds is built here.
//
// Four sources, and they are not interchangeable:
//   * a CLR DELEGATE type — read off a referenced assembly, either through the `Func`/`Action` arity
//     tables or through the delegate's own `Invoke` method, with the nullability reader supplying the
//     annotations;
//   * a source FUNCTION DECLARATION resolved against the file being analysed;
//   * the same declaration resolved against ANOTHER file's declaration context, which is how a
//     cross-file function gets a signature without the current file's imports leaking into it;
//   * a DECLARED MEMBER read off a type's member table, optionally as seen from a declaring owner.
//
// TWO INVARIANTS WORTH STATING. First, a function's OWN type parameters always shadow: each one is
// bound to a `SimpleTypeInfo` of its own name before any reference is resolved, so `func F<T>(x: T)`
// resolves `T` to the parameter rather than to some `T` in scope. Second, an ASYNC function's call
// return type is not its declared return type — `ResolveFunctionCallReturnType` wraps it in the task
// family, and `main` gets `Task`/`Task<T>` while everything else gets `ValueTask`/`ValueTask<T>`.
// A declared type that is ALREADY task-like is left alone, which is what lets a function declare
// `Task<int>` explicitly.
//
// This owner reports nothing and records nothing; resolution is delegated to the declaration context
// and the substitution walk, which own those effects.
class AnalyzerFunctionTypeFactory {
    declarationContext: AnalyzerDeclarationContext
    typeSubstitution: AnalyzerTypeSubstitution

    constructor(context: AnalyzerDeclarationContext, substitution: AnalyzerTypeSubstitution) {
        declarationContext = context
        typeSubstitution = substitution
    }

    // A signature read off a CLR delegate type. An expression tree unwraps to the delegate it
    // encodes first. The `Func`/`Action` arity tables answer WITHOUT consulting nullability metadata,
    // exactly as the C# did — the type arguments are converted plainly — and everything else goes
    // through `Invoke`, where the annotations do apply.
    static func CreateFromRuntimeDelegate(delegateType: Type): FunctionTypeInfo {
        effectiveType := delegateType
        unwrapped: Type = typeof(object)
        if TryGetExpressionTreeDelegateType(effectiveType, out unwrapped) {
            effectiveType = unwrapped
        }

        if effectiveType.get_IsGenericType() {
            definition := effectiveType.GetGenericTypeDefinition()
            definitionName := definition.get_FullName()
            arguments := effectiveType.GetGenericArguments()
            typeArguments := new List<TypeInfo>()
            index := 0
            while index < arguments.Length {
                typeArguments.Add(AnalyzerReflectionTypeConversion.ConvertReflectionType(arguments[index]))
                index = index + 1
            }

            if IsActionDefinitionName(definitionName) {
                action := new FunctionTypeInfo()
                action.ParameterTypes = typeArguments
                action.ParameterModifiers = RepeatNoModifier(typeArguments.Count)
                action.ReturnType = BuiltInTypes.Void
                return action
            }

            if IsFuncDefinitionName(definitionName) {
                parameterCount := typeArguments.Count - 1
                parameterTypes := new List<TypeInfo>()
                parameterIndex := 0
                while parameterIndex < parameterCount {
                    parameterTypes.Add(typeArguments[parameterIndex])
                    parameterIndex = parameterIndex + 1
                }

                modifierCount := parameterCount
                if modifierCount < 0 {
                    modifierCount = 0
                }

                function := new FunctionTypeInfo()
                function.ParameterTypes = parameterTypes
                function.ParameterModifiers = RepeatNoModifier(modifierCount)
                function.ReturnType = typeArguments[typeArguments.Count - 1]
                return function
            }
        }

        invokeMethod := effectiveType.GetMethod("Invoke")
        if invokeMethod == null {
            unknown := new FunctionTypeInfo()
            unknown.ReturnType = BuiltInTypes.Unknown
            return unknown
        }

        invokeParameters := invokeMethod.GetParameters()
        parameterTypeList := new List<TypeInfo>()
        parameterModifierList := new List<ParameterModifier>()
        invokeIndex := 0
        while invokeIndex < invokeParameters.Length {
            parameter := invokeParameters[invokeIndex]
            parameterTypeList.Add(NullabilityMetadataReflection.ConvertParameter(parameter))
            parameterModifierList.Add(GetReflectionParameterModifier(parameter))
            invokeIndex = invokeIndex + 1
        }

        signature := new FunctionTypeInfo()
        signature.ParameterTypes = parameterTypeList
        signature.ParameterModifiers = parameterModifierList
        signature.ReturnType = NullabilityMetadataReflection.ConvertReturn(invokeMethod)
        return signature
    }

    // A signature for a declaration resolved against the file being analysed. `containingType` is the
    // type whose body the declaration is being read in, or null for a free function.
    func CreateFromDeclaration(declaration: FunctionDeclaration, containingType: string?): FunctionTypeInfo {
        return BuildFromDeclaration(declaration, containingType, null)
    }

    // The same declaration resolved against ANOTHER file's declaration context. The containing type
    // is deliberately not carried across: the signature belongs to the declaring file, not to
    // whatever type body the reader happens to be inside.
    func CreateFromDeclarationInFile(declaration: FunctionDeclaration, declarationFile: string): FunctionTypeInfo {
        return BuildFromDeclaration(declaration, null, declarationFile)
    }

    func BuildFromDeclaration(declaration: FunctionDeclaration, containingType: string?, declarationFile: string?): FunctionTypeInfo {
        methodSubstitution := CreateMethodSubstitution(declaration.TypeParameters)
        parameters := declaration.Parameters

        parameterNames := new List<string>()
        parameterTypes := new List<TypeInfo>()
        sourceParameterTypes := new List<TypeReference>()
        parameterModifiers := new List<ParameterModifier>()
        requiredParameterCount := 0
        index := 0
        while index < parameters.Count {
            parameter := parameters[index]
            parameterNames.Add(parameter.Name)
            parameterTypes.Add(ResolveDeclarationReference(parameter.Type, methodSubstitution, declarationFile))
            sourceParameterTypes.Add(parameter.Type)
            parameterModifiers.Add(parameter.Modifier)
            if parameter.Modifier != ParameterModifier.Params && parameter.DefaultValue == null {
                requiredParameterCount = requiredParameterCount + 1
            }

            index = index + 1
        }

        hasParamsParameter := false
        if parameters.Count > 0 {
            lastParameter := parameters[parameters.Count - 1]
            hasParamsParameter = lastParameter.Modifier == ParameterModifier.Params
        }

        declaredReturnType := declaration.ReturnType
        sourceReturnType: TypeInfo = BuiltInTypes.Void
        if declaredReturnType != null {
            sourceReturnType = ResolveDeclarationReference(declaredReturnType, methodSubstitution, declarationFile)
        }

        requiredCount: int? = requiredParameterCount
        modifierBits := System.Convert.ToInt32(declaration.Modifiers)
        isAsync := (modifierBits & System.Convert.ToInt32(Modifiers.Async)) != 0
        isGenerator := (modifierBits & System.Convert.ToInt32(Modifiers.Generator)) != 0

        signature := new FunctionTypeInfo()
        signature.SyntheticName = declaration.Name
        signature.SourceName = declaration.Name
        signature.SourceContainingType = containingType
        signature.SourceLine = declaration.Line
        signature.SourceColumn = declaration.Column
        signature.SourceParameterCount = parameters.Count
        signature.SourceHasReceiverParameter = HasReceiverParameter(parameters)
        signature.ParameterNames = parameterNames
        signature.ParameterTypes = parameterTypes
        signature.SourceParameterTypes = sourceParameterTypes
        signature.SourceReturnType = declaredReturnType
        signature.ParameterModifiers = parameterModifiers
        signature.RequiredParameterCount = requiredCount
        signature.HasParamsParameter = hasParamsParameter
        signature.TypeParameters = declaration.TypeParameters
        signature.GenericConstraints = declaration.Constraints
        signature.ResolvedGenericConstraintTypes = ResolveDeclarationConstraints(declaration.Constraints, methodSubstitution, declarationFile)
        signature.HasMustUseAttribute = HasMustUseAttribute(declaration.Attributes)
        signature.ReturnType = ResolveFunctionCallReturnType(declaration.Name, isAsync, isGenerator, sourceReturnType)
        return signature
    }

    // A signature for a member read off a type's member table. With a declaration owner every
    // reference is resolved AS SEEN FROM that owner; without one it is resolved under the
    // substitution alone.
    func CreateFromDeclaredMember(member: DeclaredMemberInfo, substitution: Dictionary<string, TypeInfo>?, declarationOwner: TypeInfo?): FunctionTypeInfo {
        effectiveSubstitution := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        if substitution != null {
            for entry in substitution {
                effectiveSubstitution[entry.Key] = entry.Value
            }
        }

        memberTypeParameters := member.TypeParameters
        typeParameterIndex := 0
        while typeParameterIndex < memberTypeParameters.Length {
            typeParameter := memberTypeParameters[typeParameterIndex]
            shadowed: TypeInfo = new SimpleTypeInfo(typeParameter.Name)
            effectiveSubstitution[typeParameter.Name] = shadowed
            typeParameterIndex = typeParameterIndex + 1
        }

        memberReturnType := member.ReturnType
        sourceReturnType: TypeInfo = BuiltInTypes.Void
        if memberReturnType != null {
            sourceReturnType = ResolveMemberReference(memberReturnType, declarationOwner, effectiveSubstitution)
        }

        memberParameterTypes := member.ParameterTypes
        parameterTypes := new List<TypeInfo>()
        sourceParameterTypes := new List<TypeReference>()
        parameterIndex := 0
        while parameterIndex < memberParameterTypes.Length {
            reference := memberParameterTypes[parameterIndex]
            parameterTypes.Add(ResolveMemberReference(reference, declarationOwner, effectiveSubstitution))
            sourceParameterTypes.Add(reference)
            parameterIndex = parameterIndex + 1
        }

        signature := new FunctionTypeInfo()
        signature.SyntheticName = member.Name
        signature.SourceName = member.Name
        signature.SourceContainingType = member.ContainingType
        signature.SourceLine = member.Line
        signature.SourceColumn = member.Column
        signature.SourceParameterCount = member.ParameterCount
        signature.SourceHasReceiverParameter = member.HasReceiverParameter
        signature.ParameterNames = ToStringList(member.ParameterNames)
        signature.ParameterTypes = parameterTypes
        signature.SourceParameterTypes = sourceParameterTypes
        signature.SourceReturnType = memberReturnType
        signature.ParameterModifiers = ToModifierList(member.ParameterModifiers)
        memberRequiredCount: int? = member.RequiredParameterCount
        signature.RequiredParameterCount = memberRequiredCount
        signature.HasParamsParameter = member.HasParamsParameter
        signature.TypeParameters = ToTypeParameterList(memberTypeParameters)
        signature.GenericConstraints = ToConstraintList(member.GenericConstraints)
        signature.ResolvedGenericConstraintTypes = ResolveMemberConstraints(member.GenericConstraints, declarationOwner, effectiveSubstitution)
        signature.HasMustUseAttribute = member.HasMustUseAttribute
        signature.ReturnType = ResolveFunctionCallReturnType(member.Name, member.IsAsync, member.IsGenerator, sourceReturnType)
        return signature
    }

    // The type a CALL to this function answers with. Only an async non-generator differs from its
    // declared return type, and a declared type that is already task-like is left exactly as written.
    static func ResolveFunctionCallReturnType(functionName: string, isAsync: bool, isGenerator: bool, sourceReturnType: TypeInfo): TypeInfo {
        if !isAsync || isGenerator {
            return sourceReturnType
        }

        if IsUnitTaskLikeTypeInfo(sourceReturnType) {
            return sourceReturnType
        }

        taskResult: TypeInfo = BuiltInTypes.Unknown
        if TryGetTaskLikeResultTypeInfo(sourceReturnType, out taskResult) {
            return sourceReturnType
        }

        usesTaskFamily := String.Equals(functionName, "main", StringComparison.OrdinalIgnoreCase)
        if BuiltInTypes.Is(sourceReturnType, BuiltInTypes.Void) {
            if usesTaskFamily {
                unitTask: TypeInfo = new ReflectionTypeInfo(RequiredCoreType("System.Threading.Tasks.Task"))
                return unitTask
            }

            unitValueTask: TypeInfo = new ReflectionTypeInfo(RequiredCoreType("System.Threading.Tasks.ValueTask"))
            return unitValueTask
        }

        arguments := new List<TypeInfo>()
        arguments.Add(sourceReturnType)
        if usesTaskFamily {
            wrappedTask: TypeInfo = new GenericTypeInfo("Task", arguments, new ReflectionTypeInfo(RequiredCoreType("System.Threading.Tasks.Task`1")))
            return wrappedTask
        }

        wrappedValueTask: TypeInfo = new GenericTypeInfo("ValueTask", arguments, new ReflectionTypeInfo(RequiredCoreType("System.Threading.Tasks.ValueTask`1")))
        return wrappedValueTask
    }

    // The unit task-likes: the source-declared ones the pure facts know, plus the reflected core
    // `Task`/`ValueTask` under ANY reflection context (see IsCoreTaskFamilyType).
    static func IsUnitTaskLikeTypeInfo(candidate: TypeInfo): bool {
        if TaskLikeTypeFacts.IsUnitTaskLikeType(candidate) {
            return true
        }

        reflection := candidate as ReflectionTypeInfo
        if reflection == null {
            return false
        }

        reflected := reflection.Type
        return IsCoreTaskFamilyType(reflected, "System.Threading.Tasks.Task")
            || IsCoreTaskFamilyType(reflected, "System.Threading.Tasks.ValueTask")
    }

    // The awaited result of a task-like type: the source-declared arm first, then the reflected
    // core generic definitions under ANY reflection context (see IsCoreTaskFamilyType).
    static func TryGetTaskLikeResultTypeInfo(candidate: TypeInfo, out resultType: TypeInfo): bool {
        sourceResult := TaskLikeTypeFacts.GetTaskLikeResultType(candidate)
        declaredResult := sourceResult.SourceResultType
        if declaredResult != null {
            resultType = declaredResult
            return true
        }

        resultType = BuiltInTypes.Unknown
        reflection := candidate as ReflectionTypeInfo
        if reflection == null {
            return false
        }

        reflected := reflection.Type
        if !reflected.get_IsGenericType() {
            return false
        }

        definition := reflected.GetGenericTypeDefinition()
        if !IsCoreTaskFamilyType(definition, "System.Threading.Tasks.Task`1")
            && !IsCoreTaskFamilyType(definition, "System.Threading.Tasks.ValueTask`1") {
            return false
        }

        arguments := reflected.GetGenericArguments()
        resultType = AnalyzerReflectionTypeConversion.ConvertReflectionType(arguments[0])
        return true
    }

    // A by-ref reflection parameter carries its direction; everything else has none.
    static func GetReflectionParameterModifier(parameter: ParameterInfo): ParameterModifier {
        parameterType := parameter.get_ParameterType()
        if !parameterType.get_IsByRef() {
            return ParameterModifier.None
        }

        if parameter.get_IsOut() {
            return ParameterModifier.Out
        }

        return ParameterModifier.Ref
    }

    // `Expression<TDelegate>` unwraps to `TDelegate` when that argument really is a delegate. The
    // by-ref shell is stripped first, so `in Expression<Func<int,int>>` unwraps too.
    static func TryGetExpressionTreeDelegateType(clrType: Type, out delegateType: Type): bool {
        delegateType = typeof(object)
        effectiveType := clrType
        if effectiveType.get_IsByRef() {
            element := effectiveType.GetElementType()
            if element != null {
                effectiveType = element
            }
        }

        if !effectiveType.get_IsGenericType() {
            return false
        }

        definition := effectiveType.GetGenericTypeDefinition()
        definitionName := definition.get_FullName()
        if definitionName != "System.Linq.Expressions.Expression`1" {
            return false
        }

        arguments := effectiveType.GetGenericArguments()
        candidate := arguments[0]
        delegateType = candidate

        // The ROOT test, not the concrete-delegate test: `System.Delegate` and
        // `System.MulticastDelegate` themselves answer true here, which is why this cannot route
        // through `AnalyzerCallableReferenceFacts.IsRuntimeDelegateType` — that one excludes them.
        coreLibrary := typeof(object).get_Assembly()
        delegateRoot := coreLibrary.GetType("System.Delegate")
        if delegateRoot != null {
            if delegateRoot.IsAssignableFrom(candidate) {
                return true
            }
        }

        baseType := candidate.get_BaseType()
        if baseType == null {
            return false
        }

        return baseType.get_FullName() == "System.MulticastDelegate"
    }

    // Does a lambda written against this expected type compile to an expression TREE rather than to
    // a delegate? The question is asked in two spellings and both are answered here.
    //
    // THE CLR SPELLING is the whole predicate: an expression-tree target is exactly an
    // `Expression<TDelegate>` whose argument is a delegate, which the unwrapper above already
    // decides.
    static func IsExpressionTreeLambdaTarget(clrType: Type): bool {
        delegateType := typeof(object)
        return TryGetExpressionTreeDelegateType(clrType, out delegateType)
    }

    // THE N# SPELLING resolves the declared alias, then asks the CLR question of whatever the
    // expected type really is — directly when it is already a reflected type, and through a
    // conversion otherwise.
    //
    // THE CONTEXT AND THE CONVERSION ARE PARAMETERS, NOT FIELDS, AND THAT IS DELIBERATE. This
    // factory is constructed ONCE, but `AnalyzerClrTypeConversion` is REPLACED on every toolset
    // rebuild and again on `Dispose`. A conversion held as a field here would go stale the moment
    // the SCC is rebuilt and would answer from a disposed MetadataLoadContext; taken as a
    // parameter, the caller necessarily passes the live one, so staleness is impossible rather
    // than merely managed.
    static func IsExpressionTreeLambdaTargetTypeInfo(expectedType: TypeInfo?, declaration: AnalyzerDeclarationContext, conversion: AnalyzerClrTypeConversion): bool {
        if expectedType == null {
            return false
        }

        resolvedExpectedType := declaration.ResolveDeclaredAlias(expectedType)
        reflectionType := resolvedExpectedType as ReflectionTypeInfo
        if reflectionType != null {
            return IsExpressionTreeLambdaTarget(reflectionType.Type)
        }

        clrType := conversion.TryConvertTypeInfoToClrType(resolvedExpectedType)
        if clrType == null {
            return false
        }

        return IsExpressionTreeLambdaTarget(clrType)
    }

    func ResolveDeclarationReference(typeReference: TypeReference, methodSubstitution: Dictionary<string, TypeInfo>, declarationFile: string?): TypeInfo {
        if declarationFile == null {
            return typeSubstitution.ResolveTypeWithSubstitution(typeReference, methodSubstitution)
        }

        return declarationContext.ResolveTypeReference(typeReference, declarationFile, methodSubstitution, null)
    }

    func ResolveDeclarationConstraints(constraints: List<GenericConstraint>?, methodSubstitution: Dictionary<string, TypeInfo>, declarationFile: string?): Dictionary<string, List<TypeInfo>>? {
        if constraints == null {
            return null
        }

        grouped := new Dictionary<string, List<TypeInfo>>(StringComparer.Ordinal)
        index := 0
        while index < constraints.Count {
            constraint := constraints[index]
            bucket := GetConstraintBucket(grouped, constraint.TypeParameter)
            inner := constraint.Constraints
            innerIndex := 0
            while innerIndex < inner.Count {
                bucket.Add(ResolveDeclarationReference(inner[innerIndex], methodSubstitution, declarationFile))
                innerIndex = innerIndex + 1
            }

            index = index + 1
        }

        return grouped
    }

    func ResolveMemberReference(typeReference: TypeReference, declarationOwner: TypeInfo?, substitution: Dictionary<string, TypeInfo>): TypeInfo {
        if declarationOwner == null {
            return typeSubstitution.ResolveTypeWithSubstitution(typeReference, substitution)
        }

        return typeSubstitution.ResolveTypeForSourceOwner(typeReference, declarationOwner, substitution)
    }

    func ResolveMemberConstraints(constraints: GenericConstraint[], declarationOwner: TypeInfo?, substitution: Dictionary<string, TypeInfo>): Dictionary<string, List<TypeInfo>> {
        grouped := new Dictionary<string, List<TypeInfo>>(StringComparer.Ordinal)
        index := 0
        while index < constraints.Length {
            constraint := constraints[index]
            bucket := GetConstraintBucket(grouped, constraint.TypeParameter)
            inner := constraint.Constraints
            innerIndex := 0
            while innerIndex < inner.Count {
                bucket.Add(ResolveMemberReference(inner[innerIndex], declarationOwner, substitution))
                innerIndex = innerIndex + 1
            }

            index = index + 1
        }

        return grouped
    }

    static func GetConstraintBucket(grouped: Dictionary<string, List<TypeInfo>>, typeParameter: string): List<TypeInfo> {
        existing: List<TypeInfo>? = null
        if grouped.TryGetValue(typeParameter, out existing) {
            if existing != null {
                return existing
            }
        }

        created := new List<TypeInfo>()
        grouped[typeParameter] = created
        return created
    }

    // A function's own type parameters shadow whatever the enclosing scope binds them to.
    static func CreateMethodSubstitution(typeParameters: List<TypeParameter>?): Dictionary<string, TypeInfo> {
        substitution := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        if typeParameters == null {
            return substitution
        }

        index := 0
        while index < typeParameters.Count {
            typeParameter := typeParameters[index]
            shadowed: TypeInfo = new SimpleTypeInfo(typeParameter.Name)
            substitution[typeParameter.Name] = shadowed
            index = index + 1
        }

        return substitution
    }

    static func HasReceiverParameter(parameters: List<Parameter>): bool {
        if parameters.Count == 0 {
            return false
        }

        first := parameters[0]
        return first.IsThis
    }

    static func HasMustUseAttribute(attributes: List<AttributeNode>): bool {
        index := 0
        while index < attributes.Count {
            attribute := attributes[index]
            if NominalTypeInfoFactory.IsMustUseAttributeName(attribute.Name) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func RepeatNoModifier(count: int): List<ParameterModifier> {
        modifiers := new List<ParameterModifier>()
        index := 0
        while index < count {
            modifiers.Add(ParameterModifier.None)
            index = index + 1
        }

        return modifiers
    }

    static func IsActionDefinitionName(definitionName: string?): bool {
        if definitionName == null {
            return false
        }

        return definitionName == "System.Action`1" || definitionName == "System.Action`2" || definitionName == "System.Action`3" || definitionName == "System.Action`4"
    }

    static func IsFuncDefinitionName(definitionName: string?): bool {
        if definitionName == null {
            return false
        }

        return definitionName == "System.Func`1" || definitionName == "System.Func`2" || definitionName == "System.Func`3" || definitionName == "System.Func`4" || definitionName == "System.Func`5"
    }

    static func ToStringList(values: string[]): List<string> {
        result := new List<string>()
        index := 0
        while index < values.Length {
            result.Add(values[index])
            index = index + 1
        }

        return result
    }

    static func ToModifierList(values: ParameterModifier[]): List<ParameterModifier> {
        result := new List<ParameterModifier>()
        index := 0
        while index < values.Length {
            result.Add(values[index])
            index = index + 1
        }

        return result
    }

    static func ToTypeParameterList(values: TypeParameter[]): List<TypeParameter> {
        result := new List<TypeParameter>()
        index := 0
        while index < values.Length {
            result.Add(values[index])
            index = index + 1
        }

        return result
    }

    static func ToConstraintList(values: GenericConstraint[]): List<GenericConstraint> {
        result := new List<GenericConstraint>()
        index := 0
        while index < values.Length {
            result.Add(values[index])
            index = index + 1
        }

        return result
    }

    // Task-family identity ACROSS reflection contexts. The analyzer sees `Task` under more than one
    // identity — the runtime type, and the MetadataLoadContext twin a declared `: Task` annotation
    // resolves to through the reference scan — and a reference-equality check against the runtime
    // type answers NO for the metadata twin. That NO used to send an `async func(): Task` call
    // result through the ValueTask<...> wrap below, and converting that mixed-context instantiation
    // produced a TypeBuilderInstantiation whose every member lookup throws NotSupportedException —
    // `nlc check` crashed instead of analyzing. Identity here is the full name plus a core-library
    // home, which every twin of the BCL task family carries.
    static func IsCoreTaskFamilyType(candidate: Type, fullName: string): bool {
        if candidate.get_FullName() != fullName {
            return false
        }

        assembly := candidate.get_Assembly()
        identity := assembly.GetName()
        assemblyName := identity.get_Name()
        return assemblyName == "System.Private.CoreLib"
            || assemblyName == "System.Runtime"
            || assemblyName == "netstandard"
            || assemblyName == "mscorlib"
    }

    // The two task families live in the core library. They are read by NAME rather than through
    // `typeof` because the columnar `typeof` surface does not carry them; the instances are the
    // identical runtime types.
    static func RequiredCoreType(fullName: string): Type {
        coreLibrary := typeof(object).get_Assembly()
        resolved := coreLibrary.GetType(fullName)
        if resolved == null {
            throw new InvalidOperationException("The core library does not define '" + fullName + "'.")
        }

        return resolved
    }
}
