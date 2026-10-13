namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Runtime.CompilerServices
import System.Threading
import NSharpLang.Compiler.Ast


// The iterator's argument/consumer token selection is decided once from the semantic method input and
// reused by machine layout and method metadata. Type and attribute choices are resolved to CLR
// identity; a same-spelled user type cannot acquire the BCL cancellation contract.
class ColumnarIteratorCancellationFacts {
    static func SelectedParameterIndex(functionInput: ColumnarFunctionInput, resolution: ColumnarSemanticTypeResolution): int {
        generatorFlag := Convert.ToInt32(Modifiers.Generator)
        if !functionInput.IsAsync || (functionInput.ModifierFlags & generatorFlag) == 0 {
            return -1
        }

        tokenIndexes := new List<int>()
        for index := 0; index < functionInput.ParamCanonicals.Length; index++ {
            if IsCancellationToken(functionInput.ParamCanonicals[index], resolution) {
                tokenIndexes.Add(index)
            }
        }

        if tokenIndexes.Count == 0 {
            return -1
        }
        if tokenIndexes.Count == 1 {
            return tokenIndexes[0]
        }

        attributes := functionInput.ParameterSourceAttributes
        if attributes == null {
            return -1
        }

        selectedIndex := -1
        selectedCount := 0
        index := 0
        while index < attributes.Length && index < functionInput.ParamCanonicals.Length {
            if IsCancellationToken(functionInput.ParamCanonicals[index], resolution) && HasEnumeratorCancellation(attributes[index], resolution) {
                selectedIndex = index
                selectedCount += 1
            }
            index += 1
        }

        if selectedCount != 1 {
            return -1
        }

        return selectedIndex
    }

    // The source-attribute queue is the sole metadata writer. For the one-token shorthand, add its
    // BCL marker to the same input column before declaration metadata is emitted, so source-authored
    // and compiler-selected markers share the existing attribute ownership path.
    static func EnsureAutomaticEnumeratorCancellationAttribute(functionInput: ColumnarFunctionInput, resolution: ColumnarSemanticTypeResolution) {
        selectedIndex := SelectedParameterIndex(functionInput, resolution)
        if selectedIndex < 0 {
            return
        }

        attributes := functionInput.ParameterSourceAttributes
        if attributes != null && selectedIndex < attributes.Length && ParameterAlreadyHasEnumeratorCancellation(attributes[selectedIndex], resolution) {
            return
        }

        expanded := new ColumnarSourceAttributeInput[][](functionInput.ParamNames.Length)
        index := 0
        while index < expanded.Length {
            if attributes != null && index < attributes.Length {
                expanded[index] = attributes[index]
            }
            index += 1
        }

        prior := expanded[selectedIndex]
        priorCount := prior == null ? 0 : prior.Length
        selected := new ColumnarSourceAttributeInput[priorCount + 1]
        index = 0
        while index < priorCount {
            selected[index] = prior[index]
            index += 1
        }
        selected[priorCount] = new ColumnarSourceAttributeInput(
            "System.Runtime.CompilerServices.EnumeratorCancellation",
            new string[](0)
        )
        expanded[selectedIndex] = selected
        functionInput.ParameterSourceAttributes = expanded
    }

    static func IsCancellationToken(canonical: string, resolution: ColumnarSemanticTypeResolution): bool {
        resolved: Type = null
        if !ColumnarCanonicalTypeResolver.TryResolveType(canonical, resolution.Enums, resolution.Structs, resolution.Unions, out resolved) {
            return false
        }

        return resolved == typeof(CancellationToken)
    }

    static func HasEnumeratorCancellation(attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution): bool {
        if attributes == null {
            return false
        }

        for attribute in attributes {
            attributeType: Type = null
            sourceDefinition: ColumnarStructDef = null
            if ColumnarSourceAttributeBinder.TryResolveAttributeType(attribute.Name, resolution, out attributeType, out sourceDefinition) && attributeType == typeof(EnumeratorCancellationAttribute) {
                return true
            }
        }

        return false
    }

    static func ParameterAlreadyHasEnumeratorCancellation(attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution?): bool {
        if attributes == null || resolution == null {
            return false
        }

        return HasEnumeratorCancellation(attributes, resolution)
    }
}
