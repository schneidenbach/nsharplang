namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import NSharpLang.Compiler

// WHERE AN ATTRIBUTE MAY BE WRITTEN, ASKED AT EMIT TIME.
//
// The analyzer asks the same question of the same program and answers it from the declarations it
// holds. The emitter cannot reuse that answer and cannot ask reflection for it either: by the time an
// attribute is attached, a source-declared attribute class is a `TypeBuilder`, and a type still being
// built answers no question about itself — `GetCustomAttributesData` has nothing to read.
//
// So the `[AttributeUsage]` of a type this program declares is read from the attributes its own
// declaration carried, which the definition kept for exactly this reason, and the usage of a type
// from a referenced assembly is read from metadata the ordinary way. `[AttributeUsage]` is itself
// inherited, so a declaration that carries none asks its base, and the walk crosses from source into
// metadata at the first base that came from a referenced assembly — the same shape the analyzer's
// walk has.
//
// ONE CALLER ASKS THIS, AND IT ASKS ONE QUESTION. An attribute written on a POSITIONAL CONSTRUCTOR
// PARAMETER is written on a declaration that becomes both a parameter and a field, and N# has no
// target prefix to choose between them, so what the attribute ADMITS chooses.
class ColumnarAttributeUsageTargets {

    // The `AttributeTargets` bits the attribute type admits. A usage this compiler cannot reduce
    // answers "every target", which is the CLR's own default and the answer that refuses nothing.
    static func Of(attributeType: Type, sourceDefinition: ColumnarStructDef?, resolution: ColumnarSemanticTypeResolution): int {
        definition := sourceDefinition
        depth := 0
        while definition != null && depth < 64 {
            declared := 0
            if TryReadDeclaredTargets(definition.DeclaredSourceAttributes, resolution, out declared) {
                return declared
            }

            baseDefinition := definition.BaseDef
            if baseDefinition == null {
                externalBase := definition.ExactBaseType
                if externalBase != null && !ColumnarAttributeBlobWriter.IsUnbakedBuilderType(externalBase) {
                    return AnalyzerAttributeUsageFacts.ReadUsage(externalBase).Targets
                }

                return AnalyzerAttributeUsageFacts.AllTargets
            }

            definition = baseDefinition
            depth = depth + 1
        }

        if attributeType != null && !ColumnarAttributeBlobWriter.IsUnbakedBuilderType(attributeType) {
            return AnalyzerAttributeUsageFacts.ReadUsage(attributeType).Targets
        }

        return AnalyzerAttributeUsageFacts.AllTargets
    }

    // ONE `[AttributeUsage(...)]` AS THE DECLARATION WROTE IT. The positional argument is an
    // `AttributeTargets` expression — a member path, or a `|` of them — and it is reduced by the same
    // evaluator that encodes every other enum-valued attribute argument into a blob, so there is one
    // reading of `AttributeTargets.Method | AttributeTargets.Class` rather than two.
    //
    // False means this declaration says nothing about its usage, and the caller asks its base. An
    // argument that cannot be reduced is also "says nothing": inventing a narrower answer would move
    // the attribute to the wrong metadata row.
    static func TryReadDeclaredTargets(attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution, out targets: int): bool {
        targets = AnalyzerAttributeUsageFacts.AllTargets
        if attributes == null {
            return false
        }

        declared: ColumnarSourceAttributeInput[] = attributes
        index := 0
        while index < declared.Length {
            attribute := declared[index]
            index = index + 1
            if !AnalyzerAttributeUsageFacts.IsAttributeUsageName(attribute.Name) {
                continue
            }

            writer := new ColumnarAttributeBlobWriter(resolution)
            written := attribute.ArgumentSyntax
            argumentIndex := 0
            while argumentIndex < written.Count {
                argument := written[argumentIndex]
                argumentIndex = argumentIndex + 1
                if argument.Name != null {
                    continue
                }

                bits := 0L
                if !writer.TryEvaluateInteger(argument.Value, out bits) {
                    return false
                }

                targets = (int)bits
                return true
            }

            // `[AttributeUsage]` WITH NO POSITIONAL ARGUMENT names no targets of its own, and the
            // answer stays the CLR's default rather than falling through to the base — the
            // declaration did carry a usage.
            return true
        }

        return false
    }
}
