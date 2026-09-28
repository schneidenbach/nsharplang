namespace Census.Operands

import System
import System.Collections.Generic
import System.Reflection
import System.Text


// EVERY USE SITE BELOW WAS A SOURCE-TYPE USE UNTIL ITS TYPES MOVED TO A REFERENCED ASSEMBLY.
//
// The types live in `tests/fixtures/census-external-operands-library`, in this same namespace, which is
// what carving `Compiler.Model` out of `Compiler.Core` does to the compiler's own source. Each function
// is one shape the columnar emitter declined against a referenced type while it emitted against a source
// one; `ExternalOperands.tests.nl` runs them as this project compiled them (the analysis path) and
// `EmitOnlyOperands.tests.nl` compiles THIS FILE again through the analysis-free path the compiler's own
// source is built with, runs that assembly and compares `Digest()`.
class OperandUses {
    static order: List<string> = new List<string>()

    // `==`/`!=` BETWEEN TWO REFERENCED REFERENCE TYPES is identity (ECMA-334 §12.12.7): the same type,
    // a base against a derived one, and `object` against `object`.
    static func SameShape(left: Shape, right: Shape): bool {
        return left == right
    }

    static func ResolvedDiffers(resolved: Shape, owner: AliasShape): bool {
        return resolved != owner
    }

    static func SameObject(left: object, right: object): bool {
        return left == right
    }

    static func GuardedIdentity(left: Node, right: Node): int {
        if left == right {
            return 1
        }
        return 0
    }

    // A referenced type's OWN `==` still decides: identity is not chosen over it.
    static func TalliesMatch(left: Tally, right: Tally): bool {
        return left == right
    }

    // G2: an enum `==` as a referenced constructor's argument, with and without a trailing optional.
    static func ByRef(inner: Shape, modifier: Modifier): ByRefShape {
        return new ByRefShape(inner, modifier == Modifier.Out)
    }

    static func NoteFor(kind: Modifier, text: string): Note {
        return new Note(3, 7, text, kind == Modifier.Params)
    }

    // G3: a referenced record built with an object initializer, whose arguments are a call over a
    // concatenation and two enum members.
    static func Required(name: string, detail: string?, line: int, column: int): Report {
        return new Report(Modifier.Ref, AddDetail("Emission is required for '" + name + "'.", detail), line, column, Severity.Error) {
            FileName: name + ".nl",
            Length: name.Length,
            Explanation: "why " + name
        }
    }

    static func AddDetail(message: string, detail: string?): string {
        if detail == null {
            return message
        }
        return message + " " + detail
    }

    // G4: an enum cast as a referenced constructor's argument, and the optional it would otherwise take.
    static func Constrained(parameter: string, flags: int): Constraint {
        return new Constraint(parameter, new List<string>(), (SpecialFlags)flags)
    }

    static func Unconstrained(parameter: string): Constraint {
        return new Constraint(parameter, new List<string>())
    }

    // G5: nested `new`, free-function and `as` arguments, and a concatenation over a call on a
    // parenthesized receiver, each with the defaults the constructor still has to fill.
    static func Depth(index: int, line: int): TypeRef {
        return new TypeRef("Depth" + (index - 1).ToString(), line, 5)
    }

    static func Bare(name: string): TypeRef {
        return new TypeRef(name)
    }

    static func Statement(names: string[], index: int): ExprStmt {
        return new ExprStmt(IdentAt(names[index], index + 10, 5), index + 10, 5)
    }

    static func IdentAt(name: string, line: int, column: int): Ident {
        return new Ident(name, line, column)
    }

    static func Foreach(): Loop {
        return new Loop("item", new Ident("items", 5, 20), EmptyBlock(5), 5, 5)
    }

    static func Guarded(body: Stmt): TryStmt {
        return new TryStmt(body as Block, new List<string>(), null, 1, 1)
    }

    static func EmptyBlock(line: int): Block {
        return new Block(new List<Stmt>(), line, 1)
    }

    // Arguments run in the order they are written, and the constructor's defaults after them.
    static func Ordered(): Loop {
        order.Clear()
        return new Loop(Track("variable"), TrackIdent("collection"), TrackBlock("body"), TrackLine("line"), TrackLine("column"))
    }

    static func Ordering(): string {
        written := order
        return string.Join(",", written)
    }

    static func Track(label: string): string {
        order.Add(label)
        return label
    }

    static func TrackIdent(label: string): Expr {
        order.Add(label)
        return new Ident(label, 1, 1)
    }

    static func TrackBlock(label: string): Stmt {
        order.Add(label)
        return new Block(new List<Stmt>(), 1, 1)
    }

    static func TrackLine(label: string): int {
        order.Add(label)
        return order.Count
    }

    // Two constructors of one arity: the written argument decides, whichever it is.
    static func PickText(text: string): Pick {
        return new Pick(text + "!")
    }

    static func PickCount(count: int): Pick {
        return new Pick(count * 2)
    }

    // G6: a narrowed nullable member of a third assembly's type, passed on and called through.
    static func ContextName(scan: Scan): string {
        context := scan.Context
        if context == null {
            return "none"
        }
        return CoreName(context)
    }

    static func CoreName(context: MetadataLoadContext): string {
        return context.CoreAssembly?.GetName().Name ?? ""
    }

    static func LabelLength(scan: Scan): int {
        label := scan.Label
        if label == null {
            return -1
        }
        return label.Length
    }

    // G10: a referenced static call whose argument is another referenced static call over a `must`
    // operand, or over a call on an operator. The inner call emitted on its own; typed as an argument it
    // had no answer, and the outer call declined at `emit.call.static-member-unmodeled`.
    static func MustNested(maybe: Shape?): int {
        return Facts.Length(Facts.Name(must maybe))
    }

    static func MustNestedLocal(alias: AliasShape?): int {
        held := alias
        return Facts.Twice(Facts.Length(Facts.Name(must held)))
    }

    static func OperatorNested(index: int): int {
        return Facts.Twice(Facts.Twice(Math.Abs(index - 1)))
    }

    // A member read over `must` inside the inner call, and the inner call as an argument an OVERLOADED
    // framework method chooses by — the compiler's `_il.Emit(OpCodes.Call, Bind((must p).Getter))`.
    static func MustMemberNested(maybe: Shape?): int {
        return Facts.Twice(Facts.Length((must maybe).Name))
    }

    static func OverloadedOuter(maybe: Shape?): string {
        builder := new StringBuilder("|")
        builder.Insert(0, Facts.Name(must maybe))
        return builder.ToString()
    }

    // The neighbours: a SOURCE static inside a referenced one, a referenced static inside a source one,
    // and a referenced static as a referenced INSTANCE call's argument.
    static func SourceInner(maybe: Shape?): int {
        return Facts.Length(LocalName(must maybe))
    }

    static func SourceOuter(maybe: Shape?): int {
        return LocalLength(Facts.Name(must maybe))
    }

    static func InstanceOuter(shape: Shape, maybe: Shape?): string {
        return shape.Describe(Facts.Name(must maybe))
    }

    static func LocalName(shape: Shape): string {
        return shape.Name + "~"
    }

    static func LocalLength(text: string): int {
        return text.Length + 100
    }

    // EVERY ANSWER ABOVE, ONE LINE EACH. The emit-only contract runs the same file through the other path
    // and compares this string, so a shape that emits but emits something else fails there too.
    // G7: `==`/`!=` with a maybe-null REFERENCED class value on either side, or both, is identity; a
    // referenced type's own `==` still decides for a maybe-null operand.
    static func MaybeSameShape(left: Shape?, right: Shape): bool {
        return left == right
    }

    static func MaybeNodesDiffer(left: Node?, right: Node?): bool {
        return left != right
    }

    static func MaybeTalliesMatch(left: Tally?, right: Tally): bool {
        return left == right
    }

    // G8: a conditional with a `null` arm, passed to a referenced static or instance method that is
    // chosen by its arguments. Either arm may be the `null`, a derived class reaches a base parameter,
    // and a value arm lifts to an `int?` one.
    static func DescribeNullFirst(flag: bool, label: string): string {
        return OperandFacts.Describe(flag ? null : label, 1)
    }

    static func DescribeNullSecond(flag: bool, label: string): string {
        return OperandFacts.Describe(flag ? label : null, 2)
    }

    static func NameOfAlias(flag: bool, alias: AliasShape): string {
        return OperandFacts.NameOf(flag ? null : alias)
    }

    static func CountOrAbsent(flag: bool, count: int): int {
        return OperandFacts.CountOf(flag ? null : count)
    }

    static func LabelOrPrefix(flag: bool, labeler: Labeler, suffix: string): string {
        return labeler.Label(flag ? null : suffix)
    }

    // G9: a `&T` parameter passed on by reference to a referenced `&T` parameter, one hop and two.
    static func BumpThrough(slot: &int, amount: int) {
        OperandFacts.Bump(ref slot, amount)
    }

    static func BumpTwoHops(slot: &int, amount: int) {
        BumpThrough(ref slot, amount)
    }

    static func GrowThrough(counter: &Counter, amount: int) {
        OperandFacts.Grow(ref counter, amount)
    }

    static func Forwarded(): string {
        slot := 1
        BumpThrough(ref slot, 2)
        BumpTwoHops(ref slot, 3)
        counter := new Counter { Value: 10 }
        GrowThrough(ref counter, 5)
        return slot.ToString() + " " + counter.Value.ToString()
    }

    // G10: a referenced STRUCT built by an object initializer, and written through a local's address,
    // with `=` and with a compound operator.
    static func InitializedCounter(): int {
        counter := new Counter { Value: 10 }
        return counter.Value
    }

    static func ConstructedThenInitialized(): int {
        counter := new Counter() { Value: 12 }
        return counter.Value
    }

    static func StoredCounter(): int {
        counter := new Counter()
        counter.Value = 10
        counter.Value += 5
        return counter.Value
    }

    // A by-value parameter is its own copy: the write changes it and not the caller's.
    static func BumpedCopy(counter: Counter): int {
        counter.Value = counter.Value + 1
        return counter.Value
    }

    static func CallerKeepsItsCopy(): string {
        counter := new Counter { Value: 4 }
        bumped := BumpedCopy(counter)
        return bumped.ToString() + " " + counter.Value.ToString()
    }

    // A referenced struct held in a SOURCE struct's field: the write goes through that field's address.
    static func NestedStore(): int {
        holder := new CounterHolder()
        holder.Inner.Value = 7
        holder.Inner.Value += 2
        return holder.Inner.Value
    }

    // A SOURCE struct built with `new T() { ... }` holding a referenced struct built by an initializer.
    static func HeldCounter(): int {
        holder := new CounterHolder() { Inner: new Counter { Value: 3 } }
        return holder.Inner.Value
    }

    // A referenced struct's `init` member and settable property, set by an initializer and then written.
    static func GaugeReading(): string {
        gauge := new Gauge { Unit: "kPa", Level: 3 }
        gauge.Level = gauge.Level * 5
        return gauge.Unit + " " + gauge.Level.ToString()
    }

    // The same initializers with a value only the emitter itself writes -- an interpolated string -- so
    // the construction is its to make, not the planner's.
    static func Interpolated(n: int): string {
        gauge := new Gauge { Unit: $"u{n}", Level: n }
        settings := new Settings { Name: $"s{n}", Count: n }
        counter := new Counter() { Value: $"{n}{n}".Length }
        return gauge.Unit + gauge.Level.ToString() + " " + settings.Name + settings.Count.ToString() + settings.Owner + " " + counter.Value.ToString()
    }

    // A referenced CLASS with no constructor argument written: its parameterless constructor, and one
    // whose every parameter is optional.
    static func Configured(): string {
        settings := new Settings { Name: "n", Count: 2, Owner: "o" }
        settings.Count += 3
        tuned := new Tuned { Label: "t" }
        untouched := new Settings { Name: "m" }
        return settings.Name + settings.Count.ToString() + settings.Owner + " " + tuned.Label + tuned.Level.ToString() + " " + untouched.Owner
    }

    static func Digest(): string {
        shape := new Shape("s")
        alias := new AliasShape("a", shape)
        node := new Node(1, 1)
        lines := new List<string>()
        lines.Add("identity " + SameShape(shape, shape).ToString() + " " + SameShape(shape, new Shape("s")).ToString() + " " + ResolvedDiffers(alias, alias).ToString() + " " + ResolvedDiffers(shape, alias).ToString())
        lines.Add("object " + SameObject(shape, shape).ToString() + " " + SameObject(shape, alias).ToString() + " guard " + GuardedIdentity(node, node).ToString() + GuardedIdentity(node, new Node(1, 1)).ToString())
        lines.Add("tally " + TalliesMatch(new Tally(2), new Tally(2)).ToString() + " " + TalliesMatch(new Tally(2), new Tally(3)).ToString())
        byRef := ByRef(shape, Modifier.Out)
        byValue := ByRef(shape, Modifier.Ref)
        lines.Add("byref " + byRef.Name + " " + byRef.IsOut.ToString() + " " + byValue.IsOut.ToString())
        note := NoteFor(Modifier.Params, "t")
        lines.Add("note " + note.Line.ToString() + ":" + note.Column.ToString() + " " + note.IsMultiLine.ToString() + " " + NoteFor(Modifier.None, "u").IsMultiLine.ToString())
        report := Required("Core", "at emit", 4, 9)
        lines.Add("report " + report.message + " | " + (report.FileName ?? "") + " " + report.Length.ToString() + " " + (report.Explanation ?? "") + " " + report.line.ToString() + ":" + report.column.ToString())
        lines.Add("constraint " + ((int)Constrained("T", 3).Flags).ToString() + " " + ((int)Unconstrained("U").Flags).ToString())
        depth := Depth(4, 12)
        bare := Bare("x")
        lines.Add("typeref " + depth.Name + " " + depth.Line.ToString() + ":" + depth.Column.ToString() + " " + bare.Name + " " + bare.Line.ToString() + ":" + bare.Column.ToString())
        names: string[] = ["zero", "one"]
        statement := Statement(names, 1)
        lines.Add("statement " + (statement.Expression as Ident)?.Name + " " + statement.Line.ToString() + " " + statement.Expression.Line.ToString())
        loop := Foreach()
        lines.Add("loop " + loop.Variable + " " + (loop.Collection as Ident)?.Name + " " + (loop.Declared == null).ToString())
        guarded := Guarded(EmptyBlock(2))
        notABlock := Guarded(new ExprStmt(new Ident("x", 1, 1), 1, 1))
        lines.Add("try " + (guarded.Body != null).ToString() + " " + (notABlock.Body == null).ToString() + " " + (guarded.Finally == null).ToString())
        ordered := Ordered()
        lines.Add("order " + Ordering() + " " + ordered.Line.ToString() + ":" + ordered.Column.ToString())
        lines.Add("pick " + PickText("a").Chosen + " " + PickCount(21).Chosen)
        lines.Add("scan " + ContextName(new Scan(null, null)) + " " + LabelLength(new Scan(null, "four")).ToString() + " " + LabelLength(new Scan(null, null)).ToString())
        lines.Add("maybe " + MaybeSameShape(shape, shape).ToString() + " " + MaybeSameShape(null, shape).ToString() + " " + MaybeNodesDiffer(node, node).ToString() + " " + MaybeNodesDiffer(null, node).ToString() + " " + MaybeNodesDiffer(null, null).ToString() + " " + MaybeTalliesMatch(new Tally(2), new Tally(2)).ToString() + " " + MaybeTalliesMatch(new Tally(2), new Tally(3)).ToString())
        lines.Add("conditional " + DescribeNullFirst(true, "a") + " " + DescribeNullFirst(false, "a") + " " + DescribeNullSecond(true, "b") + " " + DescribeNullSecond(false, "b") + " " + NameOfAlias(true, alias) + " " + NameOfAlias(false, alias) + " " + CountOrAbsent(true, 3).ToString() + " " + CountOrAbsent(false, 3).ToString() + " " + LabelOrPrefix(true, new Labeler("p"), "!") + " " + LabelOrPrefix(false, new Labeler("p"), "!"))
        lines.Add("forwarded " + Forwarded())
        lines.Add("nested " + MustNested(shape).ToString() + " " + MustNestedLocal(alias).ToString() + " " + OperatorNested(-2).ToString() + " " + new Cursor("ab").Matches(1, 5).ToString() + " " + new Cursor("ab").Matches(2, 7).ToString())
        lines.Add("must-member " + MustMemberNested(alias).ToString() + " " + OverloadedOuter(shape))
        lines.Add("neighbours " + SourceInner(shape).ToString() + " " + SourceOuter(alias).ToString() + " " + InstanceOuter(shape, alias))
        lines.Add("struct " + InitializedCounter().ToString() + " " + ConstructedThenInitialized().ToString() + " " + StoredCounter().ToString() + " " + CallerKeepsItsCopy() + " " + NestedStore().ToString() + " " + HeldCounter().ToString() + " " + GaugeReading() + " " + Configured() + " " + Interpolated(4))
        return string.Join("\n", lines)
    }
}

// G10 over an implicit `this`: the argument of the inner referenced call is a call on the current
// instance whose own argument is an operator.
class Cursor {
    Label: string

    constructor(label: string) {
        Label = label
    }

    func Child(index: int, count: int): int {
        return index + count
    }

    func Matches(index: int, count: int): bool {
        return Facts.Both(count, Facts.Join(Label, Label, Child(index, count - 1)))
    }
}

// A SOURCE struct holding a referenced one, so a member write reaches the referenced struct's field
// through this one's.
struct CounterHolder {
    Inner: Counter
}
