namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit


// Generic sibling-call inference and result-shape ownership. Inference mutates the caller-supplied
// binding array as each parameter is learned; a later mismatch deliberately retains those earlier
// writes. Return substitution is a separate, narrower model whose source-generic and admitted BCL
// collection rules must not inherit the broader constraint-substitution behavior.
class ColumnarGenericCallBindingPlanner {
    static func TryUnifyTypeParam(
        typeParams: Type[],
        binding: Type[],
        declared: Type,
        actual: Type
    ): bool {
        position := -1
        parameterIndex := 0
        while parameterIndex < typeParams.Length {
            if Object.ReferenceEquals(typeParams[parameterIndex], declared) {
                position = parameterIndex
                break
            }
            parameterIndex = parameterIndex + 1
        }
        if position < 0 {
            return false
        }

        if !actual.get_IsGenericParameter() && ColumnarTypeOfPlanner.ContainsBuilderBoundType(actual) && !(actual is TypeBuilder) && !(actual is EnumBuilder) {
            return false
        }
        if !actual.get_IsGenericParameter() && !ColumnarTypeOfPlanner.IsSupportedType(actual) {
            return false
        }
        if binding[position] == null {
            binding[position] = actual
            return true
        }
        return Object.ReferenceEquals(binding[position], actual) || binding[position] == actual
    }

    static func TryUnifyGenericCallArgument(
        typeParams: Type[],
        binding: Type[],
        declared: Type,
        actual: Type
    ): bool {
        if declared.get_IsGenericParameter() {
            return TryUnifyTypeParam(typeParams, binding, declared, actual)
        }
        if declared.get_IsSZArray() && declared.GetElementType().get_IsGenericParameter() {
            return actual.get_IsSZArray() && TryUnifyTypeParam(
                typeParams,
                binding,
                declared.GetElementType(),
                actual.GetElementType()
            )
        }
        if declared.get_IsGenericType() && !declared.get_IsGenericTypeDefinition() {
            return TryUnifyGenericContainer(typeParams, binding, declared, actual)
        }
        return ColumnarTypeEquivalenceFacts.TypesEquivalent(declared, actual)
    }

    static func TryUnifyGenericContainer(
        typeParams: Type[],
        binding: Type[],
        declared: Type,
        actual: Type
    ): bool {
        if !actual.get_IsGenericType() || actual.get_IsGenericTypeDefinition() {
            return false
        }

        declaredDefinition := declared.GetGenericTypeDefinition()
        actualDefinition := actual.GetGenericTypeDefinition()
        if !Object.ReferenceEquals(declaredDefinition, actualDefinition) {
            return false
        }

        declaredArguments := declared.GetGenericArguments()
        actualArguments := actual.GetGenericArguments()
        if declaredArguments.Length != actualArguments.Length {
            return false
        }

        argumentIndex := 0
        while argumentIndex < declaredArguments.Length {
            declaredArgument := declaredArguments[argumentIndex]
            if declaredArgument.get_IsGenericParameter() {
                if !TryUnifyTypeParam(
                    typeParams,
                    binding,
                    declaredArgument,
                    actualArguments[argumentIndex]
                ) {
                    return false
                }
            } else if declaredArgument.get_IsGenericType() && !declaredArgument.get_IsGenericTypeDefinition() {
                if !TryUnifyGenericContainer(
                    typeParams,
                    binding,
                    declaredArgument,
                    actualArguments[argumentIndex]
                ) {
                    return false
                }
            } else if !ColumnarTypeEquivalenceFacts.TypesEquivalent(
                declaredArgument,
                actualArguments[argumentIndex]
            ) {
                return false
            }
            argumentIndex = argumentIndex + 1
        }
        return true
    }

    static func TrySubstituteReturnType(
        typeParams: Type[],
        binding: Type[],
        declaredReturn: Type,
        out substituted: Type
    ): bool {
        substituted = null
        if declaredReturn.get_IsGenericParameter() {
            parameterIndex := 0
            while parameterIndex < typeParams.Length {
                if Object.ReferenceEquals(typeParams[parameterIndex], declaredReturn) {
                    substituted = binding[parameterIndex]
                    return true
                }
                parameterIndex = parameterIndex + 1
            }
            return false
        }

        if declaredReturn.get_IsSZArray() && declaredReturn.GetElementType().get_IsGenericParameter() {
            element := declaredReturn.GetElementType()
            parameterIndex := 0
            while parameterIndex < typeParams.Length {
                if Object.ReferenceEquals(typeParams[parameterIndex], element) {
                    substituted = binding[parameterIndex].MakeArrayType()
                    return true
                }
                parameterIndex = parameterIndex + 1
            }
            return false
        }

        if ColumnarTypeOfPlanner.IsClosedSourceGeneric(declaredReturn) {
            declaredArguments := declaredReturn.GetGenericArguments()
            substitutedArguments := new Type[](declaredArguments.Length)
            argumentIndex := 0
            while argumentIndex < declaredArguments.Length {
                substitutedArgument: Type = null
                if !TrySubstituteReturnType(
                    typeParams,
                    binding,
                    declaredArguments[argumentIndex],
                    out substitutedArgument
                ) {
                    return false
                }
                substitutedArguments[argumentIndex] = substitutedArgument
                argumentIndex = argumentIndex + 1
            }
            substituted = declaredReturn.GetGenericTypeDefinition().MakeGenericType(substitutedArguments)
            return true
        }

        if declaredReturn.get_IsGenericType() && !declaredReturn.get_IsGenericTypeDefinition() && ColumnarTypeOfPlanner.ContainsBuilderBoundType(declaredReturn) {
            returnDefinition := declaredReturn.GetGenericTypeDefinition()
            if returnDefinition != typeof(List<int>).GetGenericTypeDefinition() && !IsAnyDictionaryCollectionDefinition(returnDefinition) && returnDefinition != typeof(HashSet<int>).GetGenericTypeDefinition() && returnDefinition != typeof(IEnumerable<int>).GetGenericTypeDefinition() {
                return false
            }

            collectionArguments := declaredReturn.GetGenericArguments()
            substitutedCollectionArguments := new Type[](collectionArguments.Length)
            argumentIndex := 0
            while argumentIndex < collectionArguments.Length {
                substitutedCollectionArgument: Type = null
                if !TrySubstituteReturnType(
                    typeParams,
                    binding,
                    collectionArguments[argumentIndex],
                    out substitutedCollectionArgument
                ) {
                    return false
                }
                substitutedCollectionArguments[argumentIndex] = substitutedCollectionArgument
                argumentIndex = argumentIndex + 1
            }
            substituted = returnDefinition.MakeGenericType(substitutedCollectionArguments)
            return true
        }

        stillOpen := declaredReturn.get_ContainsGenericParameters()
        if stillOpen && !(declaredReturn is TypeBuilder) && !(declaredReturn is EnumBuilder) {
            return false
        }
        substituted = declaredReturn
        return true
    }

    static func IsDictionaryLikeCollectionDefinition(definition: Type): bool {
        return definition == typeof(Dictionary<int, int>).GetGenericTypeDefinition() || definition == typeof(SortedDictionary<int, int>).GetGenericTypeDefinition()
    }

    static func IsReadOnlyDictionaryCollectionDefinition(definition: Type): bool {
        return definition == typeof(IReadOnlyDictionary<int, int>).GetGenericTypeDefinition()
    }

    static func IsAnyDictionaryCollectionDefinition(definition: Type): bool {
        return IsDictionaryLikeCollectionDefinition(definition) || IsReadOnlyDictionaryCollectionDefinition(definition)
    }
}
