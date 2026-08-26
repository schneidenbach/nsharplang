namespace NSharpLang.Compiler.Ast

import System
import System.Collections.Generic
import System.IO

// THE SKIPPED-SUBTREE GUARD: EVERY `Expression`-TYPED SLOT OF EVERY EXPRESSION NODE MUST BE
// REACHABLE THROUGH `AstChildrenCore.Of`.
//
// This replaces ONE `[Fact]` deleted from `tests/AstChildrenTests.cs`:
// `EveryExpressionTypedSlot_OfEveryExpressionNode_IsEnumerated` (33 declaration lines, TWO `Assert.`
// rows plus a 90-line reflective constructor kit). It existed because two children —
// `NewExpression.ArrayLengthExpression` and `StackAllocExpression.LengthExpression` — shipped
// TWICE with no walker visiting them, and it was meant to make a third instance impossible.
//
// WHY IT IS RE-FORMULATED RATHER THAN PORTED, MEASURED RATHER THAN ASSUMED. The C# enumerated node
// types with `typeof(Expression).Assembly.GetTypes()`. That shape DECLINES on this emit path —
//
//     NL103 ... Declined at emit.local.initializer: local initializer expression emission
//     declined for 'assemblyTypes'
//
// — measured on a two-line probe through the real estate build. It does not need to be reflective.
// Every Expression node type is declared in ONE file, `Expressions.nl`, and `AstChildrenCore.Of` is
// a STRING-DISPATCH TABLE over `expression.GetType().Name` whose arms name their slots as string
// literals. So the census is read from the two sources directly, and the guard is the containment
// between them, in BOTH directions.
//
// THE RE-FORMULATION IS STRICTLY STRONGER IN THE DIMENSION THAT MATTERS. The C# could only catch a
// missing slot on a node its reflective kit could CONSTRUCT; a node whose constructor it could not
// satisfy silently contributed no sentinels and passed. The source census reads DECLARATIONS, so a
// node no constructor reaches is still checked — and it also catches the reverse error the C# could
// not see at all: an arm naming a slot the node does not declare, which reflects to `null` and is
// then silently skipped by `AddOptionalProperty`.
//
// AND IT IS PAIRED WITH RUNTIME BLOCKS, so the claim is not only about text. The two historically
// unvisited slots are constructed and walked below.

// ── locating the two sources ──────────────────────────────────────────────────

func AstGuardRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln"))
            && Directory.Exists(Path.Combine(directory, "src"))
            && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the repository root above the estate's output directory.")
}

func AstGuardSourceText(fileName: string): string {
    root := AstGuardRepositoryRoot()
    path := Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Compiler.BootstrapServices"), fileName)
    if !File.Exists(path) {
        throw new InvalidOperationException("The AST guard could not read '" + fileName + "' beside the estate.")
    }

    return File.ReadAllText(path)
}

func SourceLines(text: string): string[] {
    return text.Replace("\r\n", "\n").Split('\n')
}

// ── the declaration census, read out of Expressions.nl ────────────────────────
//
// A node is an Expression node when it derives from `Expression` transitively. A slot is an
// Expression-typed slot when its declared type mentions `Expression` or names one of the five
// AGGREGATES that carry expressions — `Argument`, `TupleElement`, `PropertyInitializer`,
// `MatchCase`, `InterpolatedStringPart` — which is exactly the set the deleted body's kit walked.

class ExpressionNodeCensus {
    Names: List<string>
    Bases: List<string>
    SlotOwners: List<string>
    SlotNames: List<string>

    constructor() {
        Names = new List<string>()
        Bases = new List<string>()
        SlotOwners = new List<string>()
        SlotNames = new List<string>()
    }
}

func CoreTypeName(declaredType: string): string {
    return declaredType.Replace("List<", "").Replace(">", "").Replace("?", "").Trim()
}

func IsExpressionCarryingType(declaredType: string): bool {
    // THE TYPE NAME IS MATCHED AS A WHOLE, NOT AS A SUBSTRING, and that is load-bearing:
    // `Argument.Modifier` is declared `ArgumentModifier`, which CONTAINS `Argument` and carries no
    // expression at all. A substring rule would make it a slot and this guard would demand an arm
    // for it.
    core := CoreTypeName(declaredType)
    return core.EndsWith("Expression")
        || core == "Argument"
        || core == "TupleElement"
        || core == "PropertyInitializer"
        || core == "MatchCase"
        || core == "InterpolatedStringPart"
}

func ReadExpressionCensus(): ExpressionNodeCensus {
    census := new ExpressionNodeCensus()
    lines := SourceLines(AstGuardSourceText("Expressions.nl"))
    currentClass := ""

    index := 0
    while index < lines.Length {
        line := lines[index]
        if line.StartsWith("class ") && line.EndsWith("{") {
            header := line.Substring("class ".Length, line.Length - "class ".Length - 1).Trim()
            colon := header.IndexOf(":", 0, StringComparison.Ordinal)
            if colon < 0 {
                currentClass = header
                census.Names.Add(currentClass)
                census.Bases.Add("")
            } else {
                currentClass = header.Substring(0, colon).Trim()
                census.Names.Add(currentClass)
                census.Bases.Add(header.Substring(colon + 1).Trim())
            }
        } else if line.StartsWith("}") {
            currentClass = ""
        } else if currentClass != "" && line.StartsWith("    ") && !line.StartsWith("     ") {
            trimmed := line.Trim()
            colon := trimmed.IndexOf(": ", 0, StringComparison.Ordinal)
            // a field declaration is `Name: Type` and nothing else on the line; a member with a
            // body, an initializer or a parameter list is not one
            if colon > 0 && !trimmed.Contains("(") && !trimmed.Contains("=") && !trimmed.Contains("{") {
                slotName := trimmed.Substring(0, colon)
                declaredType := trimmed.Substring(colon + 2).Trim()
                if IsExpressionCarryingType(declaredType) {
                    census.SlotOwners.Add(currentClass)
                    census.SlotNames.Add(slotName)
                }
            }
        }

        index = index + 1
    }

    return census
}

func DerivesFromExpression(census: ExpressionNodeCensus, name: string): bool {
    current := name
    hops := 0
    while hops < 8 {
        found := -1
        i := 0
        while i < census.Names.Count {
            if census.Names[i] == current {
                found = i
                break
            }

            i = i + 1
        }

        if found < 0 {
            return false
        }

        baseName := census.Bases[found]
        if baseName == "Expression" {
            return true
        }

        if baseName == "" {
            return false
        }

        current = baseName
        hops = hops + 1
    }

    return false
}

func ExpressionNodeNames(census: ExpressionNodeCensus): List<string> {
    names := new List<string>()
    i := 0
    while i < census.Names.Count {
        name := census.Names[i]
        if DerivesFromExpression(census, name) {
            names.Add(name)
        }

        i = i + 1
    }

    return names
}

func SlotsOf(census: ExpressionNodeCensus, owner: string): List<string> {
    slots := new List<string>()
    i := 0
    while i < census.SlotOwners.Count {
        if census.SlotOwners[i] == owner {
            slots.Add(census.SlotNames[i])
        }

        i = i + 1
    }

    return slots
}

// ── the dispatch census, read out of AstChildrenCore.nl ───────────────────────

class DispatchArm {
    TypeName: string
    Body: string

    constructor(typeName: string, body: string) {
        TypeName = typeName
        Body = body
    }
}

func ReadDispatchArms(): List<DispatchArm> {
    arms := new List<DispatchArm>()
    lines := SourceLines(AstGuardSourceText("AstChildrenCore.nl"))
    index := 0
    while index < lines.Length {
        trimmed := lines[index].Trim()
        if trimmed.StartsWith("if typeName == \"") && trimmed.EndsWith("\" {") {
            head := "if typeName == \"".Length
            typeName := trimmed.Substring(head, trimmed.Length - head - "\" {".Length)
            // BRACE-COUNTED, not "stop at the first `}`". The interpolated-string arm nests a
            // `while` inside an `if`, and a line-shaped reader truncates it after its FIRST slot —
            // which would leave a second slot silently unchecked in exactly the file this guard
            // exists to check.
            body := ""
            depth := 1
            scan := index + 1
            while scan < lines.Length && depth > 0 {
                inner := lines[scan]
                character := 0
                while character < inner.Length {
                    if inner[character] == '{' {
                        depth = depth + 1
                    } else if inner[character] == '}' {
                        depth = depth - 1
                    }

                    character = character + 1
                }

                if depth > 0 {
                    body = body + inner.Trim() + "\n"
                }

                scan = scan + 1
            }

            arms.Add(new DispatchArm(typeName, body))
            index = scan - 1
        }

        index = index + 1
    }

    return arms
}

func ArmFor(arms: List<DispatchArm>, typeName: string): DispatchArm? {
    i := 0
    while i < arms.Count {
        if arms[i].TypeName == typeName {
            return arms[i]
        }

        i = i + 1
    }

    return null
}

func DeclaredLeafNames(): List<string> {
    names := new List<string>()
    lines := SourceLines(AstGuardSourceText("AstChildrenCore.nl"))
    index := 0
    while index < lines.Length {
        if lines[index].Contains("static func IsLeafExpression") {
            body := lines[index + 1]
            parts := body.Split('"')
            part := 1
            while part < parts.Length {
                candidate := parts[part]
                if candidate.EndsWith("Expression") {
                    names.Add(candidate)
                }

                part = part + 2
            }

            return names
        }

        index = index + 1
    }

    throw new InvalidOperationException("AstChildrenCore.IsLeafExpression was not found.")
}

// A slot read whose owner is literally `expression` — `…(result, expression, "Left")` and
// `GetRequiredList(expression, "Arguments")` — as opposed to a read on an aggregate element.
func DirectSlotReads(body: string): List<string> {
    reads := new List<string>()
    marker := "expression, \""
    start := 0
    while start < body.Length {
        index := body.IndexOf(marker, start, StringComparison.Ordinal)
        if index < 0 {
            break
        }

        nameStart := index + marker.Length
        close := body.IndexOf("\"", nameStart, StringComparison.Ordinal)
        if close < 0 {
            break
        }

        reads.Add(body.Substring(nameStart, close - nameStart))
        start = close + 1
    }

    return reads
}

// The body of one named helper function, brace-counted from its `func` line.
func HelperBody(source: string, functionName: string): string {
    lines := SourceLines(source)
    index := 0
    while index < lines.Length {
        if lines[index].Contains("func " + functionName + "(") {
            body := ""
            depth := 0
            started := false
            scan := index
            while scan < lines.Length {
                inner := lines[scan]
                character := 0
                while character < inner.Length {
                    if inner[character] == '{' {
                        depth = depth + 1
                        started = true
                    } else if inner[character] == '}' {
                        depth = depth - 1
                    }

                    character = character + 1
                }

                body = body + inner + "\n"
                if started && depth <= 0 {
                    return body
                }

                scan = scan + 1
            }
        }

        index = index + 1
    }

    throw new InvalidOperationException("AstChildrenCore has no function named '" + functionName + "'.")
}

func CheckAggregate(census: ExpressionNodeCensus, source: string, aggregate: string, walker: string, unreachable: List<string>) {
    body := ""
    if walker == "InterpolatedStringExpression" {
        // the hole is walked INLINE in the dispatch arm rather than in a helper of its own — it is
        // the one aggregate with no `Add…Values` function to read
        arms := ReadDispatchArms()
        arm := ArmFor(arms, "InterpolatedStringExpression")
        body = (arm ?? new DispatchArm("", "")).Body
    } else {
        body = HelperBody(source, walker)
    }

    slots := SlotsOf(census, aggregate)
    slot := 0
    while slot < slots.Count {
        if !body.Contains("\"" + slots[slot] + "\"") {
            unreachable.Add(aggregate + "." + slots[slot])
        }

        slot = slot + 1
    }
}

// Reference identity is claimed through a DISTINCT sentinel value rather than a reference
// comparison: `(x as object) == (y as object)` and `object.ReferenceEquals` both decline on this
// emit path (measured — `emit.statement.block-child` and
// `emit.call.static-member-unmodeled: static call 'object.ReferenceEquals'`). Every sentinel below
// carries a value no other sentinel in its block carries, so naming the value names the node.
func SentinelValue(child: object): string {
    identifier := child as IdentifierExpression
    if identifier != null {
        return identifier.Name
    }

    literal := child as IntLiteralExpression
    if literal != null {
        return literal.Value
    }

    return ""
}

// ── the guard itself ──────────────────────────────────────────────────────────

test "the census finds every Expression node type declared in Expressions.nl" {
    // A CONTROL ON THE INSTRUMENT ITSELF. If the reader silently found nothing, every containment
    // block below would pass vacuously — which is exactly how a structural guard dies quietly.
    census := ReadExpressionCensus()
    nodes := ExpressionNodeNames(census)

    assert nodes.Count == 41
    assert nodes.Contains("BinaryExpression")
    assert nodes.Contains("NewExpression")
    assert nodes.Contains("StackAllocExpression")
    assert nodes.Contains("InterpolatedStringExpression")
    // `Expression` itself is the base and is NOT one of its own nodes
    assert (nodes.Contains("Expression")) == false
    // and neither are the aggregates, which are not Expression nodes
    assert (nodes.Contains("Argument")) == false
    assert (nodes.Contains("MatchCase")) == false
}

test "the dispatch reader finds every arm and the declared leaf list" {
    arms := ReadDispatchArms()
    leaves := DeclaredLeafNames()

    assert arms.Count == 29
    assert leaves.Count == 12
    assert leaves.Contains("IntLiteralExpression")
    assert leaves.Contains("TypeOfExpression")

    // the arms and the leaves are DISJOINT — a node is dispatched or it is a leaf, never both
    i := 0
    overlap := 0
    while i < arms.Count {
        if leaves.Contains(arms[i].TypeName) {
            overlap = overlap + 1
        }

        i = i + 1
    }

    assert overlap == 0
}

test "EVERY Expression node is either dispatched by an arm or declared a leaf" {
    // THE FIRST HALF OF THE GUARD. A newly added node hits `Of`'s throwing default at runtime; this
    // block says so BEFORE anything constructs one.
    census := ReadExpressionCensus()
    nodes := ExpressionNodeNames(census)
    arms := ReadDispatchArms()
    leaves := DeclaredLeafNames()

    unhandled := new List<string>()
    i := 0
    while i < nodes.Count {
        name := nodes[i]
        if ArmFor(arms, name) == null && !leaves.Contains(name) {
            unhandled.Add(name)
        }

        i = i + 1
    }

    assert unhandled.Count == 0
}

test "EVERY Expression-typed slot of every node is named by that node's arm" {
    // THE SECOND HALF, AND THE ONE THE TWO HISTORIC BUGS WOULD HAVE TRIPPED. Both a direct child
    // (`AddRequiredProperty(result, expression, "Left")`) and an aggregate one
    // (`GetRequiredList(expression, "Arguments")`) name their slot as a string literal, so the
    // containment is the same check for both.
    census := ReadExpressionCensus()
    nodes := ExpressionNodeNames(census)
    arms := ReadDispatchArms()

    unreachable := new List<string>()
    i := 0
    while i < nodes.Count {
        name := nodes[i]
        arm := ArmFor(arms, name)
        if arm != null {
            body := (arm ?? new DispatchArm("", "")).Body
            slots := SlotsOf(census, name)
            slotIndex := 0
            while slotIndex < slots.Count {
                if !body.Contains("\"" + slots[slotIndex] + "\"") {
                    unreachable.Add(name + "." + slots[slotIndex])
                }

                slotIndex = slotIndex + 1
            }
        }

        i = i + 1
    }

    assert unreachable.Count == 0
}

test "a declared LEAF really has no Expression-typed slot to reach" {
    // The leaf list is an ASSERTION about the node, not a licence to skip it. A leaf that grows a
    // child would otherwise be skipped forever with no arm to notice.
    census := ReadExpressionCensus()
    leaves := DeclaredLeafNames()

    wronglyLeaf := new List<string>()
    i := 0
    while i < leaves.Count {
        slots := SlotsOf(census, leaves[i])
        if slots.Count > 0 {
            wronglyLeaf.Add(leaves[i])
        }

        i = i + 1
    }

    assert wronglyLeaf.Count == 0
}

test "no arm names a slot its node does not declare" {
    // THE REVERSE ERROR, WHICH THE DELETED BODY COULD NOT SEE AT ALL. `AddOptionalProperty` reads a
    // property BY NAME and silently skips a name that resolves to nothing, so a renamed slot leaves
    // an arm that walks nothing and a test that still passes.
    //
    // Only the arm's DIRECT reads are checked — the ones whose owner is literally `expression`. An
    // arm also names slots of the AGGREGATE it reaches (`part`, `argument`, …); those belong to the
    // aggregate and are checked in the block below.
    census := ReadExpressionCensus()
    arms := ReadDispatchArms()

    stale := new List<string>()
    i := 0
    while i < arms.Count {
        arm := arms[i]
        slots := SlotsOf(census, arm.TypeName)
        reads := DirectSlotReads(arm.Body)
        read := 0
        while read < reads.Count {
            if !slots.Contains(reads[read]) {
                stale.Add(arm.TypeName + "." + reads[read])
            }

            read = read + 1
        }

        i = i + 1
    }

    assert stale.Count == 0
}

test "every aggregate's own Expression-typed slots are read by the helper that walks it" {
    // THE FIVE AGGREGATES the deleted body's kit walked. They are not Expression nodes, so no arm
    // covers them; each has one helper, and a slot added to one of them would otherwise be skipped
    // by every walker in the compiler with nothing to notice.
    census := ReadExpressionCensus()
    source := AstGuardSourceText("AstChildrenCore.nl")

    unreachable := new List<string>()
    CheckAggregate(census, source, "Argument", "AddArgumentValues", unreachable)
    CheckAggregate(census, source, "TupleElement", "AddTupleElementValues", unreachable)
    CheckAggregate(census, source, "PropertyInitializer", "AddPropertyInitializerValues", unreachable)
    CheckAggregate(census, source, "MatchCase", "AddMatchCaseValues", unreachable)
    CheckAggregate(census, source, "InterpolatedStringHole", "InterpolatedStringExpression", unreachable)

    assert unreachable.Count == 0
}

// ── the runtime side ──────────────────────────────────────────────────────────

test "a leaf node yields no children and does not throw" {
    identifierChildren := AstChildrenCore.Of(new IdentifierExpression("x", 1, 1))
    literalChildren := AstChildrenCore.Of(new IntLiteralExpression("7", 1, 1))

    assert identifierChildren.Count == 0
    assert literalChildren.Count == 0
}

test "a binary node yields both operands, in left-then-right order" {
    left := new IdentifierExpression("a", 1, 1)
    right := new IdentifierExpression("b", 1, 5)
    children := AstChildrenCore.Of(new BinaryExpression(left, BinaryOperator.Add, right, 1, 1))

    assert children.Count == 2
    assert SentinelValue(children[0]) == "a"
    assert SentinelValue(children[1]) == "b"
}

test "StackAllocExpression yields its length, which shipped unvisited twice" {
    // ONE OF THE TWO SLOTS THIS GUARD EXISTS FOR.
    length := new IntLiteralExpression("16", 1, 1)
    children := AstChildrenCore.Of(new StackAllocExpression(new SimpleTypeReference("int", 1, 1), length, 1, 1))

    assert children.Count == 1
    assert SentinelValue(children[0]) == "16"
}

test "NewExpression yields its array length, the OTHER slot that shipped unvisited" {
    // AND IT IS OPTIONAL, so a walker that only visited the required slots passed for years. The
    // control is the same node WITHOUT the length, which must yield nothing at all.
    length := new IntLiteralExpression("4", 1, 1)
    withLength := AstChildrenCore.Of(new NewExpression(new SimpleTypeReference("int", 1, 1), new List<Argument>(), null, 1, 1, length))
    withoutLength := AstChildrenCore.Of(new NewExpression(new SimpleTypeReference("int", 1, 1), new List<Argument>(), null, 1, 1, null))

    assert withLength.Count == 1
    assert SentinelValue(withLength[0]) == "4"
    assert withoutLength.Count == 0
}

test "an aggregate's element values are yielded, not the aggregate itself" {
    // `Argument` is not an Expression, so a walker handed one would crash. `Of` must unwrap it.
    first := new IdentifierExpression("a", 1, 1)
    second := new IdentifierExpression("b", 1, 4)
    arguments := new List<Argument>()
    arguments.Add(new Argument(null, first, ArgumentModifier.None))
    arguments.Add(new Argument(null, second, ArgumentModifier.None))

    children := AstChildrenCore.Of(new CallExpression(new IdentifierExpression("f", 1, 1), arguments, null, 1, 1))

    assert children.Count == 3
    assert SentinelValue(children[1]) == "a"
    assert SentinelValue(children[2]) == "b"
}

test "an unknown node name is a LOUD failure, not an empty child list" {
    // The throwing default is what makes the first half of the guard enforceable at runtime too.
    threw := false
    try {
        AstChildrenCore.Of(new ExpressionGuardStranger())
    } catch {
        threw = true
    }

    assert threw
}

test "a null node is rejected rather than treated as childless" {
    threw := false
    try {
        AstChildrenCore.Of(null)
    } catch {
        threw = true
    }

    assert threw
}

// A node name `AstChildrenCore.Of` has never heard of. It is deliberately NOT an Expression, so it
// cannot perturb the declaration census above.
class ExpressionGuardStranger {
}
