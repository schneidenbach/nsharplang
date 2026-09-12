namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Globalization
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler

// `MethodImplAttribute` IS A PSEUDO-CUSTOM ATTRIBUTE (ECMA-335 II.21.2.1), AND THAT IS THE WHOLE
// REASON THIS OWNER EXISTS.
//
// The CLR does not store it in the CustomAttribute table. What the source says goes into the
// METHOD DEFINITION ROW'S `ImplFlags` column — `MethodImplAttributes` — which is what the JIT reads
// when it decides whether to inline a call, and what `MethodBase.GetMethodImplementationFlags()`
// reads back. `MethodBuilder.SetImplementationFlags` / `ConstructorBuilder.SetImplementationFlags`
// write that column. A `[MethodImpl(...)]` written as a blob instead would be metadata nothing
// consults: the method would claim `AggressiveInlining` to a reader of `GetCustomAttributesData()`
// and mean nothing to the JIT.
//
// So the routing is exactly the C# compiler's: `MethodImpl` NEVER becomes a blob (the blob writer
// refuses it by name-independent type identity, see `ColumnarSourceAttributes.Bind`) and ALWAYS
// becomes flags. `GetCustomAttributesData()` on an N#-emitted method therefore answers the same
// thing it answers for a C#-emitted one — the attribute is not there — while
// `GetMethodImplementationFlags()` answers what was written.
//
// `MethodImplOptions` and `MethodCodeType` are both mapped verbatim: every `MethodImplOptions`
// member has the same numeric value as the `MethodImplAttributes` bit it names, and the
// `MethodCodeType` named argument occupies `MethodImplAttributes.CodeTypeMask` (the low two bits).
class ColumnarMethodImplAttributes {

    // The CLR's own identity for the three types this owner understands. A user type that merely
    // SPELLS one of these names resolves to itself and is left to the ordinary blob path.
    static func AttributeFullName(): string {
        return "System.Runtime.CompilerServices.MethodImplAttribute"
    }

    static func OptionsFullName(): string {
        return "System.Runtime.CompilerServices.MethodImplOptions"
    }

    static func CodeTypeFullName(): string {
        return "System.Runtime.CompilerServices.MethodCodeType"
    }

    // The named argument `MethodImplAttribute.MethodCodeType` — a public field on the attribute, not
    // a constructor parameter, so it is written `[MethodImpl(MethodCodeType = MethodCodeType.Runtime)]`.
    static func CodeTypeArgumentName(): string {
        return "MethodCodeType"
    }

    // Does this source attribute name the CLR's `MethodImplAttribute`? Resolution is the ordinary
    // scoped one the blob path uses (`MethodImpl` and `MethodImpl` + `Attribute` are both tried), and
    // the ANSWER is the resolved type's full name — never the spelling, so a locally declared
    // `MethodImplAttribute` in another namespace stays an ordinary custom attribute.
    static func IsMethodImplAttribute(attribute: ColumnarSourceAttributeInput, resolution: ColumnarSemanticTypeResolution): bool {
        for candidate in AnalyzerAttributeValidator.GetClrAttributeNameCandidates(attribute.Name) {
            resolved: Type = null
            if ColumnarCanonicalTypeResolver.TryResolveType(candidate, resolution.Enums, resolution.Structs, resolution.Unions, out resolved) && resolved != null && string.Equals(resolved.get_FullName(), AttributeFullName(), StringComparison.Ordinal) {
                return true
            }
        }

        return false
    }

    // Does the declaration carry a `[MethodImpl(...)]` at all? The flags an ABSENT attribute implies
    // are the same zero an explicit `[MethodImpl]` with no arguments implies, so the two cases are
    // only distinguishable here, and only this tells the emitter whether to touch the column.
    static func HasMethodImplAttribute(attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution): bool {
        if attributes == null {
            return false
        }

        for attribute in attributes {
            if IsMethodImplAttribute(attribute, resolution) {
                return true
            }
        }

        return false
    }

    // The implementation flags a declaration's attributes ask for. False means an argument could not
    // be reduced to a compile-time `MethodImplOptions` / `MethodCodeType` constant — the analyzer
    // refuses that shape (NL930/NL931) before emission, so reaching it here is a decline rather than
    // a silently dropped attribute.
    static func TryFlags(attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution, out flags: MethodImplAttributes): bool {
        flags = (MethodImplAttributes)0
        if attributes == null {
            return true
        }

        value := 0
        for attribute in attributes {
            if !IsMethodImplAttribute(attribute, resolution) {
                continue
            }

            for index in ArgumentIndices(attribute) {
                text := attribute.ArgumentTexts[index]
                argumentName := ""
                argumentValue := ""
                SplitNamedArgument(text, out argumentName, out argumentValue)
                enumFullName := OptionsFullName()
                if argumentName.Length > 0 {
                    if !string.Equals(argumentName, CodeTypeArgumentName(), StringComparison.Ordinal) {
                        return false
                    }

                    enumFullName = CodeTypeFullName()
                }

                termValue := 0
                if !TryEvaluate(argumentValue, enumFullName, resolution, out termValue) {
                    return false
                }

                value = value | termValue
            }
        }

        flags = (MethodImplAttributes)value
        return true
    }

    // Positions of an attribute's arguments, so the walk over them reads as a walk and not as an
    // index arithmetic exercise.
    static func ArgumentIndices(attribute: ColumnarSourceAttributeInput): List<int> {
        indices := new List<int>()
        index := 0
        while index < attribute.ArgumentTexts.Length {
            indices.Add(index)
            index = index + 1
        }

        return indices
    }

    // `Name = value` splits; anything else is positional and leaves the name empty. The `=` that
    // counts is a bare one: `==`, `!=`, `<=`, `>=` and `=>` are all operators inside a value.
    static func SplitNamedArgument(text: string, out argumentName: string, out argumentValue: string) {
        argumentName = ""
        argumentValue = text.Trim()
        index := 0
        while index < text.Length {
            if text[index] == '=' && !IsAdjacentOperatorCharacter(text, index - 1) && !IsAdjacentOperatorCharacter(text, index + 1) {
                argumentName = text.Substring(0, index).Trim()
                argumentValue = text.Substring(index + 1, text.Length - index - 1).Trim()
                return
            }

            index = index + 1
        }
    }

    static func IsAdjacentOperatorCharacter(text: string, index: int): bool {
        if index < 0 || index >= text.Length {
            return false
        }

        character := text[index]
        return character == '=' || character == '!' || character == '<' || character == '>'
    }

    // A `|`-separated combination of constants of ONE enum type. Each term is either an integer
    // literal or a member access whose qualifier names that enum.
    static func TryEvaluate(text: string, enumFullName: string, resolution: ColumnarSemanticTypeResolution, out value: int): bool {
        value = 0
        terms := SplitOnBitwiseOr(text)
        total := 0
        for term in terms {
            termValue := 0
            if !TryEvaluateTerm(term.Trim(), enumFullName, resolution, out termValue) {
                return false
            }

            total = total | termValue
        }

        value = total
        return true
    }

    static func SplitOnBitwiseOr(text: string): List<string> {
        terms := new List<string>()
        start := 0
        index := 0
        while index < text.Length {
            if text[index] == '|' {
                terms.Add(text.Substring(start, index - start))
                start = index + 1
            }

            index = index + 1
        }

        terms.Add(text.Substring(start, text.Length - start))
        return terms
    }

    static func TryEvaluateTerm(text: string, enumFullName: string, resolution: ColumnarSemanticTypeResolution, out value: int): bool {
        value = 0
        if text.Length == 0 {
            return false
        }

        literal := 0
        if Int32.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out literal) {
            value = literal
            return true
        }

        lastDot := text.LastIndexOf('.')
        if lastDot <= 0 || lastDot + 1 >= text.Length {
            return false
        }

        qualifier := text.Substring(0, lastDot)
        memberName := text.Substring(lastDot + 1, text.Length - lastDot - 1)
        enumType: Type = null
        if !TryResolveEnum(qualifier, enumFullName, resolution, out enumType) || enumType == null {
            return false
        }

        member := enumType.GetField(memberName, BindingFlags.Public | BindingFlags.Static)
        if member == null || !member.get_IsLiteral() {
            return false
        }

        value = Convert.ToInt32(member.GetRawConstantValue(), CultureInfo.InvariantCulture)
        return true
    }

    // The qualifier as written must resolve — through the declaration's ordinary scope — to the enum
    // this argument position takes. `MethodImplOptions` and
    // `System.Runtime.CompilerServices.MethodImplOptions` are the same type and both arrive here.
    static func TryResolveEnum(qualifier: string, enumFullName: string, resolution: ColumnarSemanticTypeResolution, out enumType: Type): bool {
        enumType = null
        resolved: Type = null
        if !ColumnarCanonicalTypeResolver.TryResolveType(qualifier, resolution.Enums, resolution.Structs, resolution.Unions, out resolved) || resolved == null {
            return false
        }

        if !string.Equals(resolved.get_FullName(), enumFullName, StringComparison.Ordinal) {
            return false
        }

        enumType = resolved
        return true
    }

    // `SetImplementationFlags` REPLACES the column, so it runs once per declaration and only when
    // the declaration actually said something. Leaving an unmarked method alone keeps its
    // `MethodImplAttributes.IL | MethodImplAttributes.Managed` (both zero), which is what
    // `GetMethodImplementationFlags()` answers for an unmarked C# method too.
    static func TryApplyToMethod(target: MethodBuilder, attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution): bool {
        if !HasMethodImplAttribute(attributes, resolution) {
            return true
        }

        flags := (MethodImplAttributes)0
        if !TryFlags(attributes, resolution, out flags) {
            return false
        }

        target.SetImplementationFlags(flags)
        return true
    }

    static func TryApplyToConstructor(target: ConstructorBuilder, attributes: ColumnarSourceAttributeInput[]?, resolution: ColumnarSemanticTypeResolution): bool {
        if !HasMethodImplAttribute(attributes, resolution) {
            return true
        }

        flags := (MethodImplAttributes)0
        if !TryFlags(attributes, resolution, out flags) {
            return false
        }

        target.SetImplementationFlags(flags)
        return true
    }
}
