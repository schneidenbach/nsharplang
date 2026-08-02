namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

// WHICH EXTENSION METHOD A MEMBER NAME RESOLVES TO — the analyzer's extension surface, whole.
//
// A member name that is not declared on the receiver's own shape reaches this surface, and the
// surface answers with the extension that claims it: a source `func` whose first parameter accepts
// the receiver, or a `[Extension]` static found in a referenced assembly under an imported
// namespace. This owner is SILENT: it reports no diagnostic and records nothing into the semantic
// model. Every answer is a value.
//
// SOURCE EXTENSIONS FIRST, AND THE EXTERNAL SCAN IS THE FALLBACK — but only when no source
// extension is APPLICABLE, not merely when none is named. A source `func` that shares the name and
// rejects the receiver falls through to the external scan exactly as an unnamed one does.
//
// THE THREE COLLECTIONS CROSS BY REFERENCE, NOT BY VALUE. The analyzer's `_extensionMethods`,
// `_usingNamespaces` and `_mlcAssemblies` are `readonly` fields mutated in place — cleared at the
// start of every `Analyze`, appended to as declarations and imports and references are walked,
// NEVER reassigned — so the reference held here is always the live collection. Snapshot none of
// them: an extension declared later in the same file would then be invisible, and the external scan
// would search whichever namespace set existed when the copy was taken. The containing type name is
// the opposite case and must NOT be held: `_currentTypeName` is a plain mutable field that changes
// every time the walk enters or leaves a type, so it crosses as a PARAMETER, read at the call.
public class AnalyzerExtensionMethodResolution {

    typeResolver: AnalyzerTypeResolver
    assignability: AnalyzerAssignability
    declarationContext: AnalyzerDeclarationContext
    functionTypeFactory: AnalyzerFunctionTypeFactory
    clrTypeConversion: AnalyzerClrTypeConversion
    extensionMethods: List<FunctionDeclaration>
    usingNamespaces: List<string>
    assemblies: List<Assembly>

    constructor(
        types: AnalyzerTypeResolver,
        assignabilityOwner: AnalyzerAssignability,
        declarations: AnalyzerDeclarationContext,
        functionTypes: AnalyzerFunctionTypeFactory,
        clrConversion: AnalyzerClrTypeConversion,
        declaredExtensions: List<FunctionDeclaration>,
        importedNamespaces: List<string>,
        referenceAssemblies: List<Assembly>) {
        typeResolver = types
        assignability = assignabilityOwner
        declarationContext = declarations
        functionTypeFactory = functionTypes
        clrTypeConversion = clrConversion
        extensionMethods = declaredExtensions
        usingNamespaces = importedNamespaces
        assemblies = referenceAssemblies
    }

    // SOURCE EXTENSIONS FIRST, AND THE EXTERNAL SCAN IS THE FALLBACK — but only when no source
    // extension is APPLICABLE, not merely when none is named. A source `func` that shares the name
    // and rejects the receiver falls through to the external scan exactly as an unnamed one does.
    public func TryResolveExtensionMethod(
        targetType: TypeInfo,
        methodName: string,
        currentTypeName: string?): TypeInfo {
        matchingExtensions := new List<FunctionDeclaration>()
        matchIndex := 0
        while matchIndex < extensionMethods.Count {
            candidate := extensionMethods[matchIndex]
            if candidate.Name == methodName {
                matchingExtensions.Add(candidate)
            }
            matchIndex = matchIndex + 1
        }

        if matchingExtensions.Count == 0 {
            return ExternalExtensionMethodType(targetType, methodName)
        }

        applicableExtensions := new List<FunctionDeclaration>()
        applicableIndex := 0
        while applicableIndex < matchingExtensions.Count {
            candidate := matchingExtensions[applicableIndex]
            if candidate.Parameters.Count > 0 && IsExtensionReceiverApplicable(candidate, targetType) {
                applicableExtensions.Add(candidate)
            }
            applicableIndex = applicableIndex + 1
        }

        if applicableExtensions.Count == 0 {
            return ExternalExtensionMethodType(targetType, methodName)
        }

        if applicableExtensions.Count == 1 {
            return functionTypeFactory.CreateFromDeclaration(applicableExtensions[0], currentTypeName)
        }

        // Several source extensions claim the name; overload resolution picks between them later.
        functionTypes := new List<FunctionTypeInfo>()
        functionIndex := 0
        while functionIndex < applicableExtensions.Count {
            functionTypes.Add(
                functionTypeFactory.CreateFromDeclaration(applicableExtensions[functionIndex], currentTypeName))
            functionIndex = functionIndex + 1
        }

        return NSharpMethodGroupInfoFactory.FromFunctions(functionTypes)
    }

    // Does this source extension accept this receiver?
    //
    // AN UNCONSTRAINED RECEIVER ACCEPTS EVERYTHING, AND MUST ANSWER BEFORE THE REFERENCE IS
    // RESOLVED. A first parameter spelled with the function's OWN type parameter is a placeholder,
    // not a type: resolving it would answer with whichever type happens to share that name in scope
    // — a real declaration called `T`, or `unknown` — and the extension would then be offered to the
    // wrong receivers or to none. The spelling is therefore checked against the declaration's type
    // parameter list first, and only a spelling that is NOT one of them is resolved.
    //
    // A RESOLVED RECEIVER MATCHES BY IDENTITY OR BY ASSIGNABILITY, IN THAT ORDER. Identity is the
    // exact-shape answer that assignability's conversions would also give but more expensively;
    // assignability is what admits an extension declared on a base type, an interface the receiver
    // implements, or a nullable/oblivious spelling of the same underlying type.
    public func IsExtensionReceiverApplicable(candidate: FunctionDeclaration, targetType: TypeInfo): bool {
        if candidate.Parameters.Count == 0 {
            return false
        }

        receiverTypeReference := candidate.Parameters[0].Type
        simple := receiverTypeReference as SimpleTypeReference
        if simple != null && IsFunctionTypeParameter(candidate, simple.Name) {
            return true
        }

        receiverType := typeResolver.ResolveType(receiverTypeReference)
        return TypeInfoIdentityFacts.AreEqual(receiverType, targetType)
            || assignability.IsAssignable(receiverType, targetType)
    }

    // A declaration with NO type parameter list at all is not a generic function, so no spelling can
    // be one of its type parameters.
    static func IsFunctionTypeParameter(candidate: FunctionDeclaration, name: string): bool {
        typeParameters := candidate.TypeParameters
        if typeParameters == null {
            return false
        }

        index := 0
        while index < typeParameters.Count {
            if typeParameters[index].Name == name {
                return true
            }
            index = index + 1
        }

        return false
    }

    // The external answer, in the shape the member surface expects: one method is a method INFO,
    // several are a method GROUP, none is `unknown`.
    func ExternalExtensionMethodType(targetType: TypeInfo, methodName: string): TypeInfo {
        externalExtensions := FindExternalExtensionMethods(targetType, methodName)
        if externalExtensions.Count == 1 {
            winner := externalExtensions[0]
            return new ReflectionMethodInfo(winner, winner.get_Name() + "(...)")
        }

        if externalExtensions.Count > 1 {
            first := externalExtensions[0]
            return new ReflectionMethodGroupInfo(externalExtensions.ToArray(), first.get_Name() + "(...)")
        }

        return BuiltInTypes.Unknown
    }

    // Every `[Extension]` static under an IMPORTED namespace whose receiver parameter accepts the
    // target, in assembly then type then method order — the order the caller's method group keeps.
    //
    // THE EXACT CONVERSION AND THE BINDING CONVERSION ARE NOT INTERCHANGEABLE. When the receiver
    // converts exactly, that CLR type is the receiver and the scan runs. When it does not, the
    // binding conversion supplies only a SURROGATE — a stand-in whose instance surface was never
    // searched on the receiver's behalf — so an instance method of the same name must still win, and
    // the scan is abandoned rather than allowed to answer with an extension that would hide it.
    public func FindExternalExtensionMethods(targetType: TypeInfo, methodName: string): List<MethodInfo> {
        exactClrType := clrTypeConversion.TryConvertTypeInfoToClrType(targetType)
        if exactClrType != null {
            return ScanExternalExtensionMethods(exactClrType, methodName)
        }

        bindingClrType := clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(targetType)
        if bindingClrType == null {
            return new List<MethodInfo>()
        }

        if declarationContext.HasRuntimeInstanceMethod(bindingClrType, methodName) {
            return new List<MethodInfo>()
        }

        return ScanExternalExtensionMethods(bindingClrType, methodName)
    }

    // The DECLARED types of every reference assembly, not the exported ones. An extension declared
    // on an INTERNAL static class is a candidate the exported surface would silently drop.
    func ScanExternalExtensionMethods(targetClrType: Type, methodName: string): List<MethodInfo> {
        methods := new List<MethodInfo>()
        memberFlags := BindingFlags.Public | BindingFlags.Static

        assemblyIndex := 0
        while assemblyIndex < assemblies.Count {
            assemblyTypes := assemblies[assemblyIndex].GetTypes()
            typeIndex := 0
            while typeIndex < assemblyTypes.Length {
                hostType := assemblyTypes[typeIndex]
                hostNamespace := hostType.get_Namespace()
                // A static class is `sealed abstract` in metadata; nothing else may declare one.
                if hostNamespace != null
                    && usingNamespaces.Contains(hostNamespace)
                    && hostType.get_IsSealed()
                    && hostType.get_IsAbstract() {
                    CollectExtensionMethods(hostType, memberFlags, methodName, targetClrType, methods)
                }
                typeIndex = typeIndex + 1
            }
            assemblyIndex = assemblyIndex + 1
        }

        return methods
    }

    static func CollectExtensionMethods(
        hostType: Type,
        memberFlags: BindingFlags,
        methodName: string,
        targetClrType: Type,
        methods: List<MethodInfo>) {
        hostMethods := hostType.GetMethods(memberFlags)
        methodIndex := 0
        while methodIndex < hostMethods.Length {
            method := hostMethods[methodIndex]
            if method.get_Name() == methodName && AnalyzerOverloadFacts.HasExtensionAttribute(method) {
                parameters := method.GetParameters()
                if parameters.Length > 0
                    && AnalyzerOverloadFacts.IsExtensionParameterCompatible(
                        parameters[0].get_ParameterType(),
                        targetClrType) {
                    methods.Add(method)
                }
            }
            methodIndex = methodIndex + 1
        }
    }
}
