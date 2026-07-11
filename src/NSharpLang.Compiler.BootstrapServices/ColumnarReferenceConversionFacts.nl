namespace NSharpLang.Compiler.Columnar

import System

// Reflection.Emit cannot answer IsAssignableFrom for every closed BCL wrapper while one of
// its generic arguments is still an unbaked TypeBuilder. Keep the exact CLR interface edges
// that N# admits in one place so overload selection and sealed-plan validation cannot drift.
class ColumnarReferenceConversionFacts {
    static func IsExactKnownUpcast(sourceType: Type, targetType: Type): bool {
        if targetType.get_IsGenericType()
            && !targetType.get_IsGenericTypeDefinition()
            && sourceType.get_IsSZArray() {
            sourceElement := sourceType.GetElementType()
            targetArguments := targetType.GetGenericArguments()
            if sourceElement == null
                || targetArguments.Length != 1
                || !ExactTypeShapeMatches(sourceElement, targetArguments[0]) {
                return false
            }

            targetDefinition := targetType.GetGenericTypeDefinition()
            return targetDefinition
                    == typeof(IReadOnlyList<int>).GetGenericTypeDefinition()
                || targetDefinition
                    == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition()
                || targetDefinition
                    == typeof(IEnumerable<int>).GetGenericTypeDefinition()
        }

        if !sourceType.get_IsGenericType()
            || sourceType.get_IsGenericTypeDefinition()
            || !targetType.get_IsGenericType()
            || targetType.get_IsGenericTypeDefinition() {
            return false
        }

        sourceArguments := sourceType.GetGenericArguments()
        targetArguments := targetType.GetGenericArguments()
        if sourceArguments.Length < 1
            || targetArguments.Length != 1
            || !ExactTypeShapeMatches(sourceArguments[0], targetArguments[0]) {
            return false
        }

        sourceDefinition := sourceType.GetGenericTypeDefinition()
        targetDefinition := targetType.GetGenericTypeDefinition()
        if targetDefinition
                == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition()
            && (sourceDefinition
                    == typeof(IReadOnlyList<int>).GetGenericTypeDefinition()
                || sourceDefinition
                    == typeof(IReadOnlySet<int>).GetGenericTypeDefinition()) {
            return true
        }

        if sourceDefinition == typeof(List<int>).GetGenericTypeDefinition() {
            return targetDefinition
                    == typeof(IReadOnlyList<int>).GetGenericTypeDefinition()
                || targetDefinition
                    == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition()
                || targetDefinition
                    == typeof(IEnumerable<int>).GetGenericTypeDefinition()
        }

        if sourceDefinition == typeof(HashSet<int>).GetGenericTypeDefinition() {
            return targetDefinition
                    == typeof(IReadOnlySet<int>).GetGenericTypeDefinition()
                || targetDefinition
                    == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition()
                || targetDefinition
                    == typeof(IEnumerable<int>).GetGenericTypeDefinition()
        }

        return sourceDefinition == typeof(Stack<int>).GetGenericTypeDefinition()
            && targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition()
    }

    static func ExactTypeShapeMatches(left: Type, right: Type): bool {
        if left == right {
            return true
        }

        if left.get_IsSZArray() || right.get_IsSZArray() {
            if !left.get_IsSZArray() || !right.get_IsSZArray() {
                return false
            }

            leftElement := left.GetElementType()
            rightElement := right.GetElementType()
            return leftElement != null
                && rightElement != null
                && ExactTypeShapeMatches(leftElement, rightElement)
        }

        if !left.get_IsGenericType()
            || !right.get_IsGenericType()
            || left.get_IsGenericTypeDefinition()
            || right.get_IsGenericTypeDefinition()
            || left.GetGenericTypeDefinition() != right.GetGenericTypeDefinition() {
            return false
        }

        leftArguments := left.GetGenericArguments()
        rightArguments := right.GetGenericArguments()
        if leftArguments.Length != rightArguments.Length {
            return false
        }

        index := 0
        while index < leftArguments.Length {
            if !ExactTypeShapeMatches(leftArguments[index], rightArguments[index]) {
                return false
            }

            index += 1
        }

        return true
    }
}
