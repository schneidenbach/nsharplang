namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Threading
import System.Threading.Tasks

enum ColumnarIteratorOverrideTargetKind {
    SyncMoveNext = 1,
    SyncGenericCurrent = 2,
    SyncObjectCurrent = 3,
    SyncReset = 4,
    SyncDispose = 5,
    SyncGenericGetEnumerator = 6,
    SyncObjectGetEnumerator = 7,
    AsyncMoveNext = 8,
    AsyncCurrent = 9,
    AsyncDispose = 10,
    AsyncGetEnumerator = 11
}

// Exact interface handles already constructed by the iterator host. Construction snapshots handles
// only; each row performs lookup, rebinding and structural capture at its original attachment phase.
class ColumnarIteratorOverrideContext {
    readonly tableValue: ColumnarStructuralTypeReferenceTable
    readonly elementTypeValue: Type
    readonly sequenceContextValue: Type
    readonly enumeratorContextValue: Type
    readonly asyncValue: bool

    StructuralTypeReferences: ColumnarStructuralTypeReferenceTable => tableValue
    ElementType: Type => elementTypeValue
    SequenceContext: Type => sequenceContextValue
    EnumeratorContext: Type => enumeratorContextValue
    IsAsync: bool => asyncValue

    constructor(
        table: ColumnarStructuralTypeReferenceTable,
        elementType: Type,
        sequenceContext: Type,
        enumeratorContext: Type,
        isAsync: bool
    ) {
        tableValue = table
        elementTypeValue = elementType
        sequenceContextValue = sequenceContext
        enumeratorContextValue = enumeratorContext
        asyncValue = isAsync
    }

    static func ForSync(
        table: ColumnarStructuralTypeReferenceTable,
        elementType: Type,
        enumerableContext: Type,
        enumeratorContext: Type
    ): ColumnarIteratorOverrideContext {
        return new ColumnarIteratorOverrideContext(table, elementType, enumerableContext, enumeratorContext, false)
    }

    static func ForAsync(
        table: ColumnarStructuralTypeReferenceTable,
        elementType: Type,
        enumerableContext: Type,
        enumeratorContext: Type
    ): ColumnarIteratorOverrideContext {
        return new ColumnarIteratorOverrideContext(table, elementType, enumerableContext, enumeratorContext, true)
    }
}

// A consumed iterator declaration binding. The caller supplies a row and the exact host-created
// context, never a target or signature certificate. This constructor performs the row's historical
// lookup and optional rebinding before inspecting the authoritative OPEN member signature.
class ColumnarIteratorMemberBinding {
    readonly tableValue: ColumnarStructuralTypeReferenceTable
    readonly targetValue: MethodInfo
    readonly openMethodValue: MethodInfo
    readonly openDeclaringTypeValue: ColumnarSelectedTypeReference
    readonly openDeclaringRuntimeTypeValue: Type
    readonly declaringContextValue: ColumnarSelectedTypeReference
    readonly declaringContextRuntimeTypeValue: Type
    readonly moduleVersionIdValue: string
    readonly methodMetadataTokenValue: int
    readonly methodNameValue: string
    readonly methodGenericArityValue: int
    readonly methodCallingConventionValue: int
    readonly methodIsStaticValue: bool
    readonly openReturnValue: ColumnarExternalMethodSignatureTypeDescriptor
    readonly effectiveReturnValue: ColumnarExternalMethodSignatureTypeDescriptor
    readonly parametersValue: IReadOnlyList<object>
    readonly parameterCountValue: int

    StructuralTypeReferences: ColumnarStructuralTypeReferenceTable => tableValue
    Target: MethodInfo => targetValue
    OpenMethod: MethodInfo => openMethodValue
    OpenDeclaringType: ColumnarSelectedTypeReference => openDeclaringTypeValue
    DeclaringContext: ColumnarSelectedTypeReference => declaringContextValue
    OpenReturn: ColumnarExternalMethodSignatureTypeDescriptor => openReturnValue
    EffectiveReturn: ColumnarExternalMethodSignatureTypeDescriptor => effectiveReturnValue
    ParameterCount: int => parameterCountValue
    ModuleVersionId: string => moduleVersionIdValue
    MethodMetadataToken: int => methodMetadataTokenValue
    MethodName: string => methodNameValue
    MethodGenericArity: int => methodGenericArityValue
    MethodCallingConvention: int => methodCallingConventionValue
    MethodIsStatic: bool => methodIsStaticValue

    constructor(
        targetKind: ColumnarIteratorOverrideTargetKind,
        lookupName: string,
        context: ColumnarIteratorOverrideContext
    ) {
        if context == null {
            throw new InvalidOperationException("Iterator member binding requires its declaration and emission context.")
        }

        kind := targetKind
        openOwner: Type? = null
        declaringContext: Type? = null
        propertyLookup := false
        rebound := false

        if kind == ColumnarIteratorOverrideTargetKind.SyncMoveNext {
            openOwner = RequiredType("System.Collections.IEnumerator")
            declaringContext = openOwner
        } else if kind == ColumnarIteratorOverrideTargetKind.SyncGenericCurrent {
            openOwner = RequiredType("System.Collections.Generic.IEnumerator`1")
            declaringContext = context.EnumeratorContext
            rebound = true
        } else if kind == ColumnarIteratorOverrideTargetKind.SyncObjectCurrent {
            openOwner = RequiredType("System.Collections.IEnumerator")
            declaringContext = openOwner
            propertyLookup = true
        } else if kind == ColumnarIteratorOverrideTargetKind.SyncReset {
            openOwner = RequiredType("System.Collections.IEnumerator")
            declaringContext = openOwner
        } else if kind == ColumnarIteratorOverrideTargetKind.SyncDispose {
            openOwner = RequiredType("System.IDisposable")
            declaringContext = openOwner
        } else if kind == ColumnarIteratorOverrideTargetKind.SyncGenericGetEnumerator {
            openOwner = RequiredType("System.Collections.Generic.IEnumerable`1")
            declaringContext = context.SequenceContext
            rebound = true
        } else if kind == ColumnarIteratorOverrideTargetKind.SyncObjectGetEnumerator {
            openOwner = RequiredType("System.Collections.IEnumerable")
            declaringContext = openOwner
        } else if kind == ColumnarIteratorOverrideTargetKind.AsyncMoveNext {
            openOwner = RequiredType("System.Collections.Generic.IAsyncEnumerator`1")
            declaringContext = context.EnumeratorContext
            rebound = true
        } else if kind == ColumnarIteratorOverrideTargetKind.AsyncCurrent {
            openOwner = RequiredType("System.Collections.Generic.IAsyncEnumerator`1")
            declaringContext = context.EnumeratorContext
            propertyLookup = true
            rebound = true
        } else if kind == ColumnarIteratorOverrideTargetKind.AsyncDispose {
            openOwner = RequiredType("System.IAsyncDisposable")
            declaringContext = openOwner
        } else if kind == ColumnarIteratorOverrideTargetKind.AsyncGetEnumerator {
            openOwner = RequiredType("System.Collections.Generic.IAsyncEnumerable`1")
            declaringContext = context.SequenceContext
            rebound = true
        }

        openOwnerObject: object? = openOwner
        authoritativeOpenOwner := (Type)openOwnerObject
        contextObject: object? = declaringContext
        exactDeclaringContext := (Type)contextObject
        openMethod: MethodInfo? = null
        if propertyLookup {
            propertyObject: object? = authoritativeOpenOwner.GetProperty(lookupName)
            property := (PropertyInfo)propertyObject
            openMethod = property.GetGetMethod()
        } else {
            openMethod = authoritativeOpenOwner.GetMethod(lookupName)
        }
        openMethodObject: object? = openMethod
        rawOpenMethod := (MethodInfo)openMethodObject
        target := rawOpenMethod
        if rebound {
            target = ColumnarClosedGenericMemberResolver.ResolveMethod(exactDeclaringContext, rawOpenMethod)
        }
        if openMethod == null || target == null {
            throw new InvalidOperationException("Iterator method-override handles cannot be null.")
        }

        effectiveReturnType: Type? = null
        effectiveParameterTypes := new Type[](0)
        if kind == ColumnarIteratorOverrideTargetKind.SyncMoveNext {
            effectiveReturnType = typeof(bool)
        } else if kind == ColumnarIteratorOverrideTargetKind.SyncGenericCurrent || kind == ColumnarIteratorOverrideTargetKind.AsyncCurrent {
            effectiveReturnType = context.ElementType
        } else if kind == ColumnarIteratorOverrideTargetKind.SyncObjectCurrent {
            effectiveReturnType = typeof(object)
        } else if kind == ColumnarIteratorOverrideTargetKind.SyncReset || kind == ColumnarIteratorOverrideTargetKind.SyncDispose {
            effectiveReturnType = ColumnarTypeOfPlanner.RequiredVoidType()
        } else if kind == ColumnarIteratorOverrideTargetKind.SyncGenericGetEnumerator || kind == ColumnarIteratorOverrideTargetKind.AsyncGetEnumerator {
            effectiveReturnType = context.EnumeratorContext
        } else if kind == ColumnarIteratorOverrideTargetKind.SyncObjectGetEnumerator {
            effectiveReturnType = RequiredType("System.Collections.IEnumerator")
        } else if kind == ColumnarIteratorOverrideTargetKind.AsyncMoveNext {
            effectiveReturnType = ValueTaskOfBoolType()
        } else if kind == ColumnarIteratorOverrideTargetKind.AsyncDispose {
            effectiveReturnType = typeof(ValueTask)
        }
        if kind == ColumnarIteratorOverrideTargetKind.AsyncGetEnumerator {
            effectiveParameterTypes = new Type[](1)
            effectiveParameterTypes[0] = typeof(CancellationToken)
        }
        returnObject: object? = effectiveReturnType
        exactReturnType := (Type)returnObject
        exactParameterTypes := effectiveParameterTypes

        openParameters := openMethod.GetParameters()
        if openParameters.Length != exactParameterTypes.Length {
            throw new InvalidOperationException("Iterator open and effective parameter counts disagree.")
        }
        openReturnParameter := openMethod.get_ReturnParameter()
        openReturn := new ColumnarExternalMethodSignatureTypeDescriptor(
            context.StructuralTypeReferences,
            openMethod.get_ReturnType(),
            openReturnParameter.GetRequiredCustomModifiers(),
            openReturnParameter.GetOptionalCustomModifiers(),
            true
        )
        effectiveReturn := new ColumnarExternalMethodSignatureTypeDescriptor(
            context.StructuralTypeReferences,
            exactReturnType,
            openReturnParameter.GetRequiredCustomModifiers(),
            openReturnParameter.GetOptionalCustomModifiers(),
            false
        )

        parameters := new List<object>()
        index := 0
        while index < openParameters.Length {
            openParameter := openParameters[index]
            requiredModifiers := openParameter.GetRequiredCustomModifiers()
            optionalModifiers := openParameter.GetOptionalCustomModifiers()
            parameters.Add(new ColumnarExternalMethodParameterDescriptor(
                new ColumnarExternalMethodSignatureTypeDescriptor(
                    context.StructuralTypeReferences,
                    openParameter.get_ParameterType(),
                    requiredModifiers,
                    optionalModifiers,
                    true
                ),
                new ColumnarExternalMethodSignatureTypeDescriptor(
                    context.StructuralTypeReferences,
                    exactParameterTypes[index],
                    requiredModifiers,
                    optionalModifiers,
                    false
                )
            ))
            index += 1
        }

        tableValue = context.StructuralTypeReferences
        targetValue = target
        openMethodValue = openMethod
        openDeclaringRuntimeTypeValue = authoritativeOpenOwner
        openDeclaringTypeValue = tableValue.SelectRuntimeType(authoritativeOpenOwner)
        declaringContextRuntimeTypeValue = exactDeclaringContext
        declaringContextValue = tableValue.SelectRuntimeType(exactDeclaringContext)
        moduleVersionIdValue = ReadModuleVersionId(openMethod)
        methodMetadataTokenValue = openMethod.get_MetadataToken()
        methodNameValue = openMethod.get_Name()
        methodGenericArityValue = openMethod.GetGenericArguments().Length
        methodCallingConventionValue = Convert.ToInt32(openMethod.get_CallingConvention())
        methodIsStaticValue = openMethod.get_IsStatic()
        openReturnValue = openReturn
        effectiveReturnValue = effectiveReturn
        parametersValue = parameters.AsReadOnly()
        parameterCountValue = parameters.Count
    }

    func Parameter(index: int): ColumnarExternalMethodParameterDescriptor {
        parameter := parametersValue.get_Item(index) as ColumnarExternalMethodParameterDescriptor
        if parameter == null {
            throw new InvalidOperationException("Iterator method parameter storage is invalid.")
        }
        return parameter
    }

    func Validate(expectedTable: ColumnarStructuralTypeReferenceTable): bool {
        if expectedTable == null || !Object.ReferenceEquals(tableValue, expectedTable) {
            return false
        }
        if !expectedTable.ValidatePair(openDeclaringTypeValue, openDeclaringRuntimeTypeValue) || !expectedTable.ValidatePair(declaringContextValue, declaringContextRuntimeTypeValue) || !ColumnarExternalMethodSignatureRelation.DeclaringContextMatchesOpenDefinition(openDeclaringTypeValue, declaringContextValue) {
            return false
        }
        if !openReturnValue.Validate(expectedTable) || !effectiveReturnValue.Validate(expectedTable) || !ColumnarExternalMethodSignatureRelation.SignatureTypesRelate(openReturnValue, effectiveReturnValue, openDeclaringTypeValue, declaringContextValue) {
            return false
        }
        index := 0
        while index < parameterCountValue {
            parameter := Parameter(index)
            if !parameter.Open.Validate(expectedTable) || !parameter.Effective.Validate(expectedTable) || !ColumnarExternalMethodSignatureRelation.SignatureTypesRelate(parameter.Open, parameter.Effective, openDeclaringTypeValue, declaringContextValue) {
                return false
            }
            index += 1
        }
        return moduleVersionIdValue == ReadModuleVersionId(openMethodValue) && methodMetadataTokenValue == openMethodValue.get_MetadataToken() && methodNameValue == openMethodValue.get_Name() && methodGenericArityValue == openMethodValue.GetGenericArguments().Length && methodCallingConventionValue == Convert.ToInt32(openMethodValue.get_CallingConvention()) && methodIsStaticValue == openMethodValue.get_IsStatic()
    }

    func ValidatedTarget(expectedTable: ColumnarStructuralTypeReferenceTable): MethodInfo {
        if !Validate(expectedTable) {
            throw new InvalidOperationException("An iterator member binding does not belong to the consuming emission.")
        }
        return targetValue
    }

    static func ValueTaskOfBoolType(): Type {
        definition := Type.GetType("System.Threading.Tasks.ValueTask`1")
        if definition == null {
            throw new InvalidOperationException("System.Threading.Tasks.ValueTask`1 was not found.")
        }
        arguments := new Type[](1)
        arguments[0] = typeof(bool)
        return definition.MakeGenericType(arguments)
    }

    static func RequiredType(name: string): Type {
        resolved := Type.GetType(name)
        if resolved == null {
            throw new InvalidOperationException(name + " was not found.")
        }
        return resolved
    }

    static func ReadModuleVersionId(method: MethodInfo): string {
        module := method.get_Module()
        return module.get_ModuleVersionId().ToString()
    }
}
