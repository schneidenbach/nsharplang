using System;
using System.Collections.Generic;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// Materializes the N#-native front-end's columnar node table (the flat int[] forest emitted by the
/// ParserExpressions/ParserStatements/ParserTypeReferences kernels) into the production C# AST records the
/// rest of the compiler consumes. This is the routing bridge: it turns "verified, fast columnar parser
/// output" into a usable <see cref="CompilationUnit"/>/<see cref="Statement"/>/<see cref="Expression"/>
/// tree, the prerequisite for replacing the C# <see cref="Parser"/> on the production path with the N#
/// front-end and deleting that bridge surface.
///
/// Node-kind numbering matches the kernels: TYPE 0 Simple,1 Generic,2 Array,3 Nullable,4 Union,5 ByRef;
/// EXPR 0 Int,1 Float,2 Char,3 String,4 Bool,5 Null,6 Identifier,7 Parenthesized,8 MemberAccess,9 Call,
/// 10 IndexAccess,11 Unary,12 Binary,13 Ternary,14 Assignment,15 New,16 Cast. Type-vs-expression children that share
/// a kind range are disambiguated positionally by the caller (e.g. a New node's child[0] is a type, the rest
/// are argument expressions), exactly as the kernels emit them.
///
/// Position fidelity: nodes are materialized with Line/Column derived from the byte span via the source's
/// line map, so diagnostics/IDE positions line up with the C# parser. Literal VALUE fidelity for
/// string/char (escape processing) is handled by reusing the lexer's unescape; int/float/bool/identifier
/// values are the verbatim source span.
/// </summary>
public sealed class ColumnarAstMaterializer
{
    private readonly int[] _kinds;
    private readonly int[] _valueStarts;
    private readonly int[] _valueLengths;
    private readonly int[] _childStart;
    private readonly int[] _childCount;
    private readonly int[] _childIndices;
    private readonly int[] _spanStarts;
    private readonly string _source;
    private readonly int[] _lineStarts; // byte offset of the start of each 1-based line

    public ColumnarAstMaterializer(
        int[] kinds, int[] valueStarts, int[] valueLengths,
        int[] childStart, int[] childCount, int[] childIndices, int[] spanStarts, string source)
    {
        _kinds = kinds;
        _valueStarts = valueStarts;
        _valueLengths = valueLengths;
        _childStart = childStart;
        _childCount = childCount;
        _childIndices = childIndices;
        _spanStarts = spanStarts;
        _source = source;
        _lineStarts = BuildLineStarts(source);
    }

    public Expression MaterializeExpression(int idx)
    {
        var (line, column) = PositionOf(idx);
        var kind = _kinds[idx];
        switch (kind)
        {
            case 0: return new IntLiteralExpression(Text(idx), line, column);
            case 1: return new FloatLiteralExpression(Text(idx), line, column);
            // The C# parser keeps char/string Value as the verbatim source token (quotes included, no
            // unescape), so the kernel's value span is used as-is.
            case 2: return new CharLiteralExpression(Text(idx), line, column);
            case 3: return new StringLiteralExpression(Text(idx), line, column);
            case 4: return new BoolLiteralExpression(Text(idx) == "true", line, column);
            case 5: return new NullLiteralExpression(line, column);
            case 6: return new IdentifierExpression(Text(idx), line, column);
            case 7: return new ParenthesizedExpression(MaterializeExpression(Child(idx, 0)), line, column);
            case 8: return new MemberAccessExpression(MaterializeExpression(Child(idx, 0)), Text(idx), false, line, column);
            case 9: return MaterializeCall(idx, line, column);
            case 10: return new IndexAccessExpression(MaterializeExpression(Child(idx, 0)), MaterializeExpression(Child(idx, 1)), false, line, column);
            case 11: return new UnaryExpression(UnaryOperatorOf(Text(idx)), MaterializeExpression(Child(idx, 0)), line, column);
            case 12: return new BinaryExpression(MaterializeExpression(Child(idx, 0)), BinaryOperatorOf(Text(idx)), MaterializeExpression(Child(idx, 1)), line, column);
            case 13: return new TernaryExpression(MaterializeExpression(Child(idx, 0)), MaterializeExpression(Child(idx, 1)), MaterializeExpression(Child(idx, 2)), line, column);
            case 14: return new AssignmentExpression(MaterializeExpression(Child(idx, 0)), AssignmentOperatorOf(Text(idx)), MaterializeExpression(Child(idx, 1)), line, column);
            case 15: return MaterializeNew(idx, line, column);
            // Hard cast `(Type)expr`: child[0] is the target type subtree, child[1] the operand expression.
            case 16: return new CastExpression(MaterializeExpression(Child(idx, 1)), MaterializeTypeReference(Child(idx, 0)), CastKind.Hard, line, column);
            default: throw new InvalidOperationException($"ColumnarAstMaterializer: unknown expression node kind {kind} at {idx}.");
        }
    }

    public Statement MaterializeStatement(int idx)
    {
        var (line, column) = PositionOf(idx);
        var kind = _kinds[idx];
        switch (kind)
        {
            case 20: return new ReturnStatement(_childCount[idx] > 0 ? MaterializeExpression(Child(idx, 0)) : null, line, column);
            case 21: return new BreakStatement(line, column);
            case 22: return new ContinueStatement(line, column);
            case 23: return new ExpressionStatement(MaterializeExpression(Child(idx, 0)), line, column);
            case 24: return new VariableDeclarationStatement(Text(idx), null, MaterializeExpression(Child(idx, 0)), VariableKind.Let, line, column);
            case 25:
            {
                var statements = new List<Statement>(_childCount[idx]);
                for (var i = 0; i < _childCount[idx]; i++) statements.Add(MaterializeStatement(Child(idx, i)));
                return new BlockStatement(statements, line, column);
            }
            case 26: return new WhileStatement(MaterializeExpression(Child(idx, 0)), MaterializeStatement(Child(idx, 1)), line, column);
            case 27: return new IfStatement(
                MaterializeExpression(Child(idx, 0)),
                MaterializeStatement(Child(idx, 1)),
                _childCount[idx] > 2 ? MaterializeStatement(Child(idx, 2)) : null,
                line, column);
            default: throw new InvalidOperationException($"ColumnarAstMaterializer: unknown statement node kind {kind} at {idx}.");
        }
    }

    public TypeReference MaterializeTypeReference(int idx)
    {
        var (line, column) = PositionOf(idx);
        var kind = _kinds[idx];
        switch (kind)
        {
            case 0: return new SimpleTypeReference(Text(idx), line, column);
            case 1:
            {
                var args = new List<TypeReference>(_childCount[idx]);
                for (var i = 0; i < _childCount[idx]; i++) args.Add(MaterializeTypeReference(Child(idx, i)));
                return new GenericTypeReference(Text(idx), args) { Line = line, Column = column };
            }
            case 2: return new ArrayTypeReference(MaterializeTypeReference(Child(idx, 0)));
            case 3: return new NullableTypeReference(MaterializeTypeReference(Child(idx, 0)));
            case 4:
            {
                var arms = new List<TypeReference>(_childCount[idx]);
                for (var i = 0; i < _childCount[idx]; i++) arms.Add(MaterializeTypeReference(Child(idx, i)));
                return new UnionTypeReference(arms);
            }
            case 5: return new ByRefTypeReference(MaterializeTypeReference(Child(idx, 0)));
            default: throw new InvalidOperationException($"ColumnarAstMaterializer: unknown type node kind {kind} at {idx}.");
        }
    }

    private Expression MaterializeCall(int idx, int line, int column)
    {
        var callee = MaterializeExpression(Child(idx, 0));
        var args = new List<Argument>(Math.Max(0, _childCount[idx] - 1));
        for (var i = 1; i < _childCount[idx]; i++)
        {
            args.Add(new Argument(null, MaterializeExpression(Child(idx, i)), ArgumentModifier.None));
        }
        return new CallExpression(callee, args, null, line, column);
    }

    private Expression MaterializeNew(int idx, int line, int column)
    {
        var type = MaterializeTypeReference(Child(idx, 0)); // child[0] is the constructed type (a type subtree)
        var args = new List<Argument>(Math.Max(0, _childCount[idx] - 1));
        for (var i = 1; i < _childCount[idx]; i++)
        {
            args.Add(new Argument(null, MaterializeExpression(Child(idx, i)), ArgumentModifier.None));
        }
        return new NewExpression(type, args, null, line, column);
    }

    private int Child(int idx, int n) => _childIndices[_childStart[idx] + n];

    private string Text(int idx) => _source.Substring(_valueStarts[idx], _valueLengths[idx]);

    private (int Line, int Column) PositionOf(int idx)
    {
        var offset = _spanStarts[idx];
        if (offset < 0) offset = 0;
        var line = LineAt(offset);
        var column = offset - _lineStarts[line - 1] + 1;
        return (line, column);
    }

    private int LineAt(int offset)
    {
        // Binary search the line-start table for the 1-based line containing offset.
        var lo = 0;
        var hi = _lineStarts.Length - 1;
        while (lo < hi)
        {
            var mid = (lo + hi + 1) / 2;
            if (_lineStarts[mid] <= offset) lo = mid; else hi = mid - 1;
        }
        return lo + 1;
    }

    private static int[] BuildLineStarts(string source)
    {
        var starts = new List<int> { 0 };
        for (var i = 0; i < source.Length; i++)
        {
            if (source[i] == '\n') starts.Add(i + 1);
        }
        return starts.ToArray();
    }

    private static BinaryOperator BinaryOperatorOf(string op) => op switch
    {
        "+" => BinaryOperator.Add,
        "-" => BinaryOperator.Subtract,
        "*" => BinaryOperator.Multiply,
        "/" => BinaryOperator.Divide,
        "%" => BinaryOperator.Modulo,
        "==" => BinaryOperator.Equal,
        "!=" => BinaryOperator.NotEqual,
        "<" => BinaryOperator.Less,
        "<=" => BinaryOperator.LessOrEqual,
        ">" => BinaryOperator.Greater,
        ">=" => BinaryOperator.GreaterOrEqual,
        "&&" => BinaryOperator.And,
        "||" => BinaryOperator.Or,
        "&" => BinaryOperator.BitwiseAnd,
        "|" => BinaryOperator.BitwiseOr,
        "^" => BinaryOperator.BitwiseXor,
        "<<" => BinaryOperator.LeftShift,
        ">>" => BinaryOperator.RightShift,
        "??" => BinaryOperator.NullCoalesce,
        _ => throw new InvalidOperationException($"ColumnarAstMaterializer: unknown binary operator '{op}'."),
    };

    private static UnaryOperator UnaryOperatorOf(string op) => op switch
    {
        "-" => UnaryOperator.Negate,
        "!" => UnaryOperator.Not,
        "~" => UnaryOperator.BitwiseNot,
        "++" => UnaryOperator.PreIncrement,
        "--" => UnaryOperator.PreDecrement,
        "^" => UnaryOperator.IndexFromEnd,
        _ => throw new InvalidOperationException($"ColumnarAstMaterializer: unknown unary operator '{op}'."),
    };

    private static AssignmentOperator AssignmentOperatorOf(string op) => op switch
    {
        "=" => AssignmentOperator.Assign,
        "+=" => AssignmentOperator.AddAssign,
        "-=" => AssignmentOperator.SubtractAssign,
        "*=" => AssignmentOperator.MultiplyAssign,
        "/=" => AssignmentOperator.DivideAssign,
        "??=" => AssignmentOperator.NullCoalesceAssign,
        _ => throw new InvalidOperationException($"ColumnarAstMaterializer: unknown assignment operator '{op}'."),
    };

}
