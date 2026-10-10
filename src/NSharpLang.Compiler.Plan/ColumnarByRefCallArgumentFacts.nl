namespace NSharpLang.Compiler.Columnar

// Syntax facts shared by the direct-call planner and the runtime emitter. A written direction word
// always requires storage; only an unmodified argument may be materialized for a read-only reference.
class ColumnarByRefCallArgumentFacts {
    static func TryGetAddressableArgumentTarget(nodes: ColumnarNodeTable, source: string, argumentNode: int, out targetNode: int, out modifierKind: int): bool {
        targetNode = -1
        modifierKind = 0
        if nodes == null || source == null || argumentNode < 0 || argumentNode >= nodes.Kinds.Length {
            return false
        }

        if nodes.Kind(argumentNode) == ColumnarExpressionNodeKind.RefOutArgument {
            if nodes.ChildCount(argumentNode) != 1 {
                return false
            }

            modifier := nodes.Text(source, argumentNode)
            if modifier == "ref" {
                modifierKind = 1
            } else if modifier == "out" {
                modifierKind = 2
            } else if modifier == "in" {
                modifierKind = 5
            } else {
                return false
            }

            targetNode = nodes.Child(argumentNode, 0)
            return targetNode >= 0 && targetNode < nodes.Kinds.Length
        }

        targetNode = ColumnarPlannerSupport.UnwrapParentheses(nodes, argumentNode)
        if targetNode < 0 {
            return false
        }

        kind := nodes.Kind(targetNode)
        return kind == ColumnarExpressionNodeKind.IdentifierExpression || kind == ColumnarExpressionNodeKind.MemberAccessExpression || kind == ColumnarExpressionNodeKind.IndexAccessExpression
    }

    static func IsBareUnmodifiedArgument(nodes: ColumnarNodeTable, argumentNode: int): bool {
        if nodes == null || argumentNode < 0 || argumentNode >= nodes.Kinds.Length {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, argumentNode)
        return candidate >= 0 && nodes.Kind(candidate) != ColumnarExpressionNodeKind.RefOutArgument
    }

    static func DirectionAllowsArgument(parameterModifierKind: int, writtenModifierKind: int): bool {
        if parameterModifierKind == 0 {
            // A source `&T` parameter has no separate direction fact; preserve its addressable caller forms.
            return true
        }
        if writtenModifierKind == 0 {
            return parameterModifierKind == 5
        }
        if parameterModifierKind == 5 {
            return writtenModifierKind == 5
        }
        if parameterModifierKind == 6 {
            return writtenModifierKind == 1 || writtenModifierKind == 5
        }
        if parameterModifierKind == 1 {
            return writtenModifierKind == 1
        }
        if parameterModifierKind == 2 {
            return writtenModifierKind == 2
        }
        return false
    }
}
