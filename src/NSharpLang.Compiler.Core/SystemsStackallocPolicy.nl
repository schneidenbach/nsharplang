namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// One violation of the stackalloc rule, stated by the owner rather than by its caller. The walk
// relays all four fields into the finding sink and adds nothing: the CODE and the EFFECT are part of
// what the rule decided (both arms are NSYS080 lifetime findings, and a future arm that is not must
// be able to say so from here), and so are the sentence a developer reads and the fix it suggests.
record SystemsStackallocViolation(Code: string, Effect: string, Message: string, Suggestion: string) {
}

// WHAT A `stackalloc` MAY RESERVE, AND WHAT IT MAY NOT OUTLIVE.
//
// A `stackalloc` is the systems profile's only unmanaged reservation, and it is unchecked twice
// over: the runtime does not bound the request, and the resulting span borrows a frame that is gone
// the moment the function returns. Both of those become diagnostics here, and nowhere else.
//
// THE SIZE RULE IS A STATIC ONE, DELIBERATELY. The length must be a literal the compiler can read;
// anything computed — a parameter, a field, a sum — is REFUSED rather than assumed small, because
// the only alternative is to trust a value the analyzer cannot see. What counts as "a literal the
// compiler can read" is wider than one token: parentheses, `checked`, `unchecked` and casts to
// integer-shaped types are transparent wrappers around the same constant, and a leading `-` is read
// as a magnitude and a sign so that `stackalloc int[-1]` reports "cannot be negative" rather than
// the misleading "must be statically bounded". `-0` is zero, not negative.
//
// THE ARITHMETIC IS DONE IN `long` AND THAT IS BEHAVIOUR, NOT STYLE. `int * int` wraps:
// `stackalloc int[2_000_000_000]` multiplied out in `int` lands on a small negative number that
// would pass any budget check. The count arrives as a `long` and the product is a `long`, so a
// request that big is reported at its real size.
//
// ELEMENT SIZES ARE THE SOURCE-LEVEL ONES, AND ALIASES ARE FOLLOWED FIRST. `type Sample = int`
// makes `stackalloc Sample[1024]` a 4 KiB request, so the alias table this owner keeps is part of
// the size rule and not a convenience: without it every aliased element type would fall to the
// 16-byte unknown default and the same program would report a different number. The table is
// registered from the declaration walk, cleared once per analysis, and read by nobody else.
// Following it is bounded by a seen-set, so a cyclic alias resolves to the first name it repeats
// instead of looping.
//
// THE ESCAPE RULE IS THE SAME SUBJECT FROM THE OTHER END. A local bound to a `stackalloc` names
// storage that dies with the frame, so returning that local by name is refused. It is deliberately
// LEXICAL and deliberately narrow — only a bare identifier that the walk recorded as stackalloc
// backed — because a conservative widening here would fire on every span-returning function that is
// perfectly legal.
class SystemsStackallocPolicy {
    typeAliasesValue: Dictionary<string, string>
    stackBudgetBytesValue: int

    constructor() {
        typeAliasesValue = new Dictionary<string, string>(StringComparer.Ordinal)
        stackBudgetBytesValue = 4096
    }

    // One call per analysis, from the analyzer's own reset block. The budget is re-read here rather
    // than at each decision because a project's configuration cannot change mid-analysis, and
    // reading it once is what makes the budget visible in this owner's own contracts.
    func BeginAnalysis(config: ProjectConfig) {
        typeAliasesValue.Clear()
        stackBudgetBytesValue = config.Language.Systems.StackBudgetBytes
    }

    // Registered from the declaration walk for every `type X = Y`. Only the erased name is kept: an
    // alias to `List<int>` is an alias to `List` for every size and classification question asked of
    // it.
    func RegisterTypeAlias(name: string, aliased: TypeReference) {
        typeAliasesValue[name] = SystemsTypeNames.ErasedName(aliased)
    }

    // Follows the alias chain to the name that is not itself an alias, simplifying at every hop so
    // that `type Sample = System.Int32` and `type Sample = int` behave alike. The seen-set makes a
    // cycle terminate at its first repeat rather than hang.
    func ResolveTypeAliasName(typeName: string): string {
        simpleName := SystemsTypeNames.SimpleName(typeName)
        seen := new HashSet<string>(StringComparer.Ordinal)
        aliasedName := ""
        while true {
            if !typeAliasesValue.TryGetValue(simpleName, out aliasedName) {
                return simpleName
            }

            if !seen.Add(simpleName) {
                return simpleName
            }

            simpleName = SystemsTypeNames.SimpleName(aliasedName)
        }

        return simpleName
    }

    // THE SIZE RULE. Null means the reservation is within budget; anything else is the violation the
    // walk reports, with its own wording for which of the three ways it failed.
    func BudgetViolation(stackAlloc: StackAllocExpression): SystemsStackallocViolation? {
        elementCount := 0L
        if !TryGetStackallocElementCount(stackAlloc.LengthExpression, out elementCount) {
            return StackallocLifetimeViolation("stackalloc length must be statically bounded in Systems N# v1")
        }

        if elementCount < 0L {
            return StackallocLifetimeViolation("stackalloc length cannot be negative")
        }

        elementSize := ElementSizeBytes(ResolveTypeAliasName(SystemsTypeNames.ErasedName(stackAlloc.ElementType)))
        total := elementCount * elementSize
        if total <= stackBudgetBytesValue {
            return null
        }

        return StackallocLifetimeViolation("stackalloc reserves " + total.ToString() + " bytes, above the configured systems stack budget of " + stackBudgetBytesValue.ToString() + " bytes")
    }

    // WHAT MAKES A LOCAL STACKALLOC BACKED — the escape rule's own input, asked of every local
    // initializer. It is the DIRECT form only: `s := stackalloc int[4]` binds the reservation, while
    // `s := (stackalloc int[4])[0]` binds an element and `s := other` binds a copy of a name, neither
    // of which owns the frame storage. Deliberately NOT the transparent-wrapper unwrap the LENGTH
    // rule uses: seeing through a cast there reads the same constant, but seeing through one here
    // would claim ownership the binding does not have.
    func IsStackallocBackedInitializer(initializer: Expression): bool {
        return initializer as StackAllocExpression != null
    }

    // THE ESCAPE RULE. Asked of every returned value; answers only for a bare identifier the walk
    // has already recorded as stackalloc backed.
    func EscapeViolation(value: Expression, stackallocLocals: HashSet<string>): SystemsStackallocViolation? {
        identifier := value as IdentifierExpression
        if identifier == null {
            return null
        }

        if !stackallocLocals.Contains(identifier.Name) {
            return null
        }

        return new SystemsStackallocViolation("NSYS080", "lifetime", "stackalloc span cannot escape through a return value", "Copy into caller-provided storage or return a heap/parameter-backed span with an explicit lifetime.")
    }

    // Both arms are lifetime findings and both offer the same fix, which is why the size rule's three
    // sentences share one constructor.
    func StackallocLifetimeViolation(message: string): SystemsStackallocViolation {
        return new SystemsStackallocViolation("NSYS080", "lifetime", message, "Use a constant within the systems stack budget, guard the maximum size, or allocate outside the hot path.")
    }

    // A magnitude and a sign, in that order: the negation arm runs FIRST so that `-1` is a negative
    // count rather than an unreadable one. A magnitude above `long.MaxValue` is not readable as a
    // count at all and falls through to the unbounded answer.
    func TryGetStackallocElementCount(expression: Expression, out elementCount: long): bool {
        elementCount = 0L
        unwrapped := UnwrapStackallocLengthExpression(expression)

        unary := unwrapped as UnaryExpression
        if unary != null && unary.Operator == UnaryOperator.Negate {
            negativeMagnitude := 0UL
            if TryGetUnsignedIntegerMagnitude(unary.Operand, out negativeMagnitude) {
                if negativeMagnitude != 0UL {
                    elementCount = -1L
                }

                return true
            }
        }

        literal := unwrapped as IntLiteralExpression
        if literal != null {
            magnitude := 0UL
            if NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(literal.Value, out magnitude) && magnitude <= 9223372036854775807UL {
                elementCount = Convert.ToInt64(magnitude)
                return true
            }
        }

        return false
    }

    // The same transparent wrappers are seen through on the way to the magnitude, so `-(int)(4)` is
    // read as `-4`.
    func TryGetUnsignedIntegerMagnitude(expression: Expression, out magnitude: ulong): bool {
        magnitude = 0UL
        unwrapped := UnwrapStackallocLengthExpression(expression)
        literal := unwrapped as IntLiteralExpression
        if literal == null {
            return false
        }

        return NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(literal.Value, out magnitude)
    }

    // The four transparent forms, peeled until none is left. A cast is transparent only when its
    // target is integer shaped: `(double)4` is not the same reservation as `4`.
    func UnwrapStackallocLengthExpression(expression: Expression): Expression {
        current := expression
        while true {
            parenthesized := current as ParenthesizedExpression
            if parenthesized != null {
                current = parenthesized.Inner
                continue
            }

            checkedExpression := current as CheckedExpression
            if checkedExpression != null {
                current = checkedExpression.Expression
                continue
            }

            uncheckedExpression := current as UncheckedExpression
            if uncheckedExpression != null {
                current = uncheckedExpression.Expression
                continue
            }

            castExpression := current as CastExpression
            if castExpression != null && IsStackallocIntLikeCast(castExpression.TargetType) {
                current = castExpression.Expression
                continue
            }

            return current
        }

        return current
    }

    // Integer shaped for the purpose of reading a LENGTH: the signed and unsigned types a count can
    // be written as, plus `char`, which is a 16-bit integer in this position. `long` is absent on
    // purpose — a cast to `long` is a widening the length rule does not need to see through.
    func IsStackallocIntLikeCast(typeReference: TypeReference): bool {
        typeName := ResolveTypeAliasName(SystemsTypeNames.ErasedName(typeReference))
        return typeName == "int" || typeName == "short" || typeName == "sbyte" || typeName == "byte" || typeName == "ushort" || typeName == "char"
    }

    // Source-level element sizes. An unrecognised element type costs the same as the largest one the
    // table names, so an unknown struct is charged 16 bytes rather than assumed cheap.
    func ElementSizeBytes(elementTypeName: string): int {
        if elementTypeName == "bool" || elementTypeName == "byte" || elementTypeName == "sbyte" {
            return 1
        }

        if elementTypeName == "short" || elementTypeName == "ushort" || elementTypeName == "char" {
            return 2
        }

        if elementTypeName == "int" || elementTypeName == "uint" || elementTypeName == "float" {
            return 4
        }

        if elementTypeName == "long" || elementTypeName == "ulong" || elementTypeName == "double" {
            return 8
        }

        return 16
    }
}
