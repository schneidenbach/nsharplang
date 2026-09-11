namespace NSharpLang.Compiler.Columnar

class ColumnarNodeTable {
    kinds: int[]
    valueStarts: int[]
    valueLengths: int[]
    childStarts: int[]
    childCounts: int[]
    childIndices: int[]
    spanStarts: int[]?
    spanLengths: int[]?
    bindingScope: ColumnarBindingScopeFacts?
    enclosingTypeName: string
    visibleTypeParameterNames: string[]
    additionalRootBindingNames: string[]

    Kinds: int[] => kinds
    ValueLengths: int[] => valueLengths
    BindingScope: ColumnarBindingScopeFacts? => bindingScope
    EnclosingTypeName: string => enclosingTypeName
    VisibleTypeParameterNames: string[] => visibleTypeParameterNames

    constructor(kindsValue: int[], valueStartsValue: int[], valueLengthsValue: int[], childStartsValue: int[], childCountsValue: int[], childIndicesValue: int[], spanStartsValue: int[]? = null, spanLengthsValue: int[]? = null) {
        this.kinds = kindsValue
        this.valueStarts = valueStartsValue
        this.valueLengths = valueLengthsValue
        this.childStarts = childStartsValue
        this.childCounts = childCountsValue
        this.childIndices = childIndicesValue
        this.spanStarts = spanStartsValue
        this.spanLengths = spanLengthsValue
        this.bindingScope = null
        this.enclosingTypeName = ""
        this.visibleTypeParameterNames = new string[](0)
        this.additionalRootBindingNames = new string[](0)
    }

    func SetBindingContext(scope: ColumnarBindingScopeFacts, enclosingType: string, typeParameterNames: string[], additionalRootBindingNames: string[]?) {
        if scope == null || enclosingType == null || typeParameterNames == null {
            throw new System.InvalidOperationException("Columnar binding context cannot contain null values.")
        }
        bindingScope = scope
        enclosingTypeName = enclosingType
        visibleTypeParameterNames = typeParameterNames
        this.additionalRootBindingNames = additionalRootBindingNames ?? new string[](0)
    }

    // Expression fragments reparsed from a body (currently interpolation holes) retain the
    // immutable lexical context of that body. The host only routes the two node tables through
    // this N# operation; it never interprets or reconstructs the binding facts.
    static func InheritBindingContext(target: ColumnarNodeTable, source: ColumnarNodeTable): ColumnarNodeTable {
        if target == null || source == null {
            throw new System.InvalidOperationException("Columnar binding context inheritance requires two node tables.")
        }
        target.bindingScope = source.bindingScope
        target.enclosingTypeName = source.enclosingTypeName
        target.visibleTypeParameterNames = source.visibleTypeParameterNames
        target.additionalRootBindingNames = source.additionalRootBindingNames
        return target
    }

    func HasAdditionalRootBinding(name: string): bool {
        index := 0
        while index < additionalRootBindingNames.Length {
            if additionalRootBindingNames[index] == name {
                return true
            }
            index = index + 1
        }
        return false
    }

    func Kind(index: int): int => kinds[index]

    func ValueStart(index: int): int => valueStarts[index]

    func ChildCount(index: int): int => childCounts[index]

    func Child(index: int, childOrdinal: int): int => childIndices[childStarts[index] + childOrdinal]

    func Text(source: string, index: int): string => source.Substring(valueStarts[index], valueLengths[index])

    func SpanStart(index: int): int {
        spans := spanStarts
        if spans == null {
            return valueStarts[index]
        }

        return spans[index]
    }

    func SpanLength(index: int): int {
        spans := spanLengths
        if spans == null {
            return valueLengths[index]
        }

        return spans[index]
    }
}
