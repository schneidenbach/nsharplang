namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHAT A STRUCT-OF-ARRAYS VALUE MAY NOT DO — the two escapes, and the registry of column reads the
// second one is decided against.
//
// A `soa record` is not a class. The table is a set of parallel column arrays and a ROW VIEW is a
// borrowed cursor into them, not an object; a COLUMN read (`table.x`) is the raw backing array, not a
// value the program owns. So neither may LEAVE the expression that produced it: a row view that is
// returned, stored, thrown, printed, yielded, compared, indexed or passed on would have to be
// materialised as an object, and a column that escapes would hand out the table's own storage. Every
// statement and expression arm in the analyzer that can carry a value asks these two questions of it,
// in this order, with its own wording for what the value was about to do — "returned", "thrown",
// "used as a foreach collection", "used as an operator operand", and forty more.
//
// THE TWO QUESTIONS ARE NOT THE SAME SHAPE, AND THAT IS THE FAMILY'S WHOLE STRUCTURE.
// The ROW question is answered by the value's TYPE: `SoaRowTypeInfo` and nothing else is a row view,
// so the caller that already holds the analysed type can be told the answer directly. The COLUMN
// question is answered by the value's SYNTAX: only a member access whose receiver is a table and
// whose name is one of its declared columns is a direct column value, and no `TypeInfo` records that
// — a column reads as the plain array type its declaration gives it. That is why one reporter takes a
// type and the other takes only the expression, and why only the second needs the registry below.
//
// THE REGISTRY IS AN ANALYSIS-LIFETIME FACT, NOT A CACHE. `AnalyzeMemberAccess` records every member
// access it has resolved AS a column, by REFERENCE, and the syntactic probe consults that first. It
// matters because the probe's own fallback can only see a column whose receiver is a plain
// identifier naming a table in scope; the recorded set covers every OTHER shape the member walk
// already decided about — a column reached through a `ref` local, through a field, through an alias,
// through a chained receiver. Reference identity is the point: two `table.x` accesses at different
// places in the file are different reads, and only the one the member walk actually resolved is
// known to be a column. The set is cleared once per analysis, from the same reset block that clears
// the scope stack.
//
// THE FALLBACK PROBE UNWRAPS THREE FORMS AND STOPS. `(table.x)`, `checked(table.x)` and
// `unchecked(table.x)` are the same read as `table.x`, so the probe sees through them; a member
// access that is NOT a column does not then recurse into its own receiver, because `a.b.c` escaping
// is a question about `a.b.c`, not about `a.b`. The receiver walk unwraps the same three forms and
// additionally sees through a `ref` binding, because a `ref` to a table is a table.
//
// NEITHER REPORT IS THE SYSTEMS ANALYZER'S. These two are the reporters the SEMANTIC walks call —
// every statement arm and every expression arm — and they are shared surface: the call walk's own
// direct-column gates (which Array methods may take a column, which parameter positions are pinned)
// are systems policy and live elsewhere, but they ask THIS owner what a column is and report through
// THIS owner's wording, so the fact and the wording have exactly one home.
class AnalyzerSoaEscape {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    columnAccessesValue: HashSet<object>

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        columnAccessesValue = new HashSet<object>()
    }

    // One call per analysis, from the same reset block that clears the scope stack. The registry is
    // per-file: a member access from a previous analysis is a node no current expression can be.
    func BeginAnalysis() {
        columnAccessesValue.Clear()
    }

    // THE MEMBER WALK'S OWN VERDICT, RECORDED. Called only where `AnalyzeMemberAccess` has already
    // resolved the receiver to a table and the name to one of its columns, so this is a statement of
    // fact rather than a guess, and it is what makes the syntactic probe complete.
    func RecordColumnMemberAccess(member: MemberAccessExpression) {
        columnAccessesValue.Add(member)
    }

    // WHETHER THIS EXPRESSION IS A DIRECT COLUMN READ, for the callers that only need the yes/no.
    // It consults the RECORDED set alone — this is the question "did the member walk resolve this as
    // a column", not "could it be one" — and unwraps the three transparent forms on the way.
    func IsSoaColumnMemberAccess(expression: Expression): bool {
        member := expression as MemberAccessExpression
        if member != null {
            return columnAccessesValue.Contains(member)
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return IsSoaColumnMemberAccess(parenthesized.Inner)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return IsSoaColumnMemberAccess(checkedExpression.Expression)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return IsSoaColumnMemberAccess(uncheckedExpression.Expression)
        }

        return false
    }

    // THE COLUMN READ INSIDE THIS EXPRESSION, or nothing. The recorded verdict comes first; the
    // declared fallback answers for a column the member walk has not reached yet, which is why an
    // argument can be rejected before its receiver has ever been analysed. A member access that is
    // neither STOPS here rather than recursing into its receiver: `a.b.c` escaping is a question
    // about `a.b.c`.
    //
    // It answers the NODE rather than a boolean because the node's own name is the report's subject
    // — "SoA table member 'x' cannot be returned directly" names the COLUMN, not the expression.
    func FindSoaColumnMemberAccess(expression: Expression): MemberAccessExpression? {
        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            if columnAccessesValue.Contains(memberAccess) {
                return memberAccess
            }

            receiver := FindSoaRecordReceiverType(memberAccess.Object)
            if receiver != null {
                if AnalyzerMemberResolution.TryGetSoaColumn(receiver.Declaration, memberAccess.MemberName) != null {
                    return memberAccess
                }
            }

            return null
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return FindSoaColumnMemberAccess(parenthesized.Inner)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return FindSoaColumnMemberAccess(checkedExpression.Expression)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return FindSoaColumnMemberAccess(uncheckedExpression.Expression)
        }

        return null
    }

    // THE TABLE A RECEIVER NAMES, or nothing. Only a plain identifier answers: a table reached any
    // other way was resolved by the member walk, and its column reads are in the registry. The alias
    // and nullable unwraps run because a table may be declared through either, and the `ref` unwrap
    // runs because a `ref` to a table is a table — and it re-resolves, because the inner type may
    // itself be an alias.
    func FindSoaRecordReceiverType(expression: Expression): SoaRecordTypeInfo? {
        identifier := expression as IdentifierExpression
        if identifier != null {
            symbol := scopesValue.LookupSymbol(identifier.Name)
            declared := BuiltInTypes.Unknown as TypeInfo
            if symbol != null {
                declared = symbol
            }

            resolved := declarationContextValue.ResolveDeclaredAlias(NonNullableType(declared))
            byRefReceiver := resolved as ByRefTypeInfo
            if byRefReceiver != null {
                resolved = declarationContextValue.ResolveDeclaredAlias(NonNullableType(byRefReceiver.InnerType))
            }

            return resolved as SoaRecordTypeInfo
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return FindSoaRecordReceiverType(parenthesized.Inner)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return FindSoaRecordReceiverType(checkedExpression.Expression)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return FindSoaRecordReceiverType(uncheckedExpression.Expression)
        }

        return null
    }

    // THE ROW-VIEW ESCAPE, UNCONDITIONAL. The caller has already decided this value is a row view —
    // either because it holds the type and tested it, or because the arm it is in can only be reached
    // with one — so this reports rather than asks.
    func ReportSoaRowEscape(expression: Expression, action: string) {
        span := spansValue.GetExpressionDiagnosticSpan(expression)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "SoA row views cannot be " + action + "; use the table and row index instead", span.Line, span.Column, "Read or write a column with table[index].column in the same expression.", span.Length)
    }

    // THE ROW-VIEW ESCAPE, ASKED. Answers whether it fired, because a value that has already been
    // rejected as a row view must not then be measured against anything else — the caller replaces
    // its type with `unknown` or ends its walk.
    func ReportSoaRowEscapeIfNeeded(expression: Expression, valueType: TypeInfo, action: string): bool {
        rowView := valueType as SoaRowTypeInfo
        if rowView == null {
            return false
        }

        ReportSoaRowEscape(expression, action)
        return true
    }

    // THE DIRECT-COLUMN ESCAPE, ASKED. The syntactic probe decides, and its answer is the report's
    // subject as well as its trigger.
    func ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(expression: Expression, action: string): bool {
        columnMember := FindSoaColumnMemberAccess(expression)
        if columnMember == null {
            return false
        }

        ReportUnsupportedSoaDirectColumnValueEscape(expression, columnMember, action)
        return true
    }

    // THE DIRECT-COLUMN ESCAPE, TOLD. The SPAN is the whole offending expression and the NAME is the
    // column's own — the two come from different nodes, which is why the column node is a parameter
    // rather than something this member re-derives.
    func ReportUnsupportedSoaDirectColumnValueEscape(expression: Expression, columnMember: MemberAccessExpression, action: string) {
        span := spansValue.GetExpressionDiagnosticSpan(expression)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "SoA table member '" + columnMember.MemberName + "' cannot be " + action + " directly", span.Line, span.Column, "Use table.column[row] for element access, Table.wrap for table views, or Array.Fill, Array.Copy, and Array.Clear for supported whole-column operations.", span.Length)
    }

    // THE DIRECT-COLUMN NULL-CONDITIONAL REFUSAL, ASKED. A direct column is non-null table storage,
    // so `table.column?.Length` and `table.column?[i]` are not safer forms of the same read — the
    // question they ask cannot arise. The SPAN is the whole offending expression and the NAME is the
    // column's, exactly as the value-escape report does it, and `accessKind` is the caller's word for
    // what it was doing ("member access" or "index") so one rule serves both arms.
    func ReportDirectColumnNullConditionalAccessIfNeeded(expression: Expression, receiver: Expression, accessKind: string): bool {
        columnMember := FindSoaColumnMemberAccess(receiver)
        if columnMember == null {
            return false
        }

        span := spansValue.GetExpressionDiagnosticSpan(expression)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "SoA table member '" + columnMember.MemberName + "' cannot use null-conditional " + accessKind + " directly", span.Line, span.Column, "Direct columns are non-null table storage; use direct column access such as table.column[row] or table.column.Length.", span.Length)
        return true
    }

    // The nullable unwrap `Analyzer.cs` performs before every structural question. Its C# original has
    // twenty-one other callers and therefore could not move; its two-call body is reproduced rather
    // than reached back for, so nothing here re-enters C#.
    func NonNullableType(candidate: TypeInfo): TypeInfo {
        nullable := declarationContextValue.ResolveDeclaredAlias(candidate) as NullableTypeInfo
        if nullable != null {
            return nullable.InnerType
        }

        return candidate
    }
}
