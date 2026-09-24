namespace Census.Operands

import System.Collections.Generic
import System.Reflection


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

    // EVERY ANSWER ABOVE, ONE LINE EACH. The emit-only contract runs the same file through the other path
    // and compares this string, so a shape that emits but emits something else fails there too.
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
        return string.Join("\n", lines)
    }
}
