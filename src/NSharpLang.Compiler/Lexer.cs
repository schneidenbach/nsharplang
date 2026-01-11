using System;
using System.Text;
using System.Collections.Generic;

namespace NSharpLang.Compiler;

public class Lexer
{
    private readonly string _source;
    private readonly string? _fileName;
    private int _position;
    private int _line = 1;
    private int _column = 1;

    private static readonly Dictionary<string, TokenType> Keywords = new()
    {
        { "func", TokenType.Func },
        { "class", TokenType.Class },
        { "struct", TokenType.Struct },
        { "interface", TokenType.Interface },
        { "duck", TokenType.Duck },
        { "union", TokenType.Union },
        { "record", TokenType.Record },
        { "enum", TokenType.Enum },
        { "namespace", TokenType.Namespace },
        { "using", TokenType.Using },
        { "import", TokenType.Import },
        { "package", TokenType.Package },
        { "let", TokenType.Let },
        { "var", TokenType.Let },  // var is an alias for let (C# compat)
        { "const", TokenType.Const },
        { "readonly", TokenType.Readonly },
        { "if", TokenType.If },
        { "else", TokenType.Else },
        { "for", TokenType.For },
        { "foreach", TokenType.Foreach },
        { "while", TokenType.While },
        { "in", TokenType.In },
        { "return", TokenType.Return },
        { "yield", TokenType.Yield },
        { "match", TokenType.Match },
        { "switch", TokenType.Switch },
        { "case", TokenType.Case },
        { "default", TokenType.Default },
        { "break", TokenType.Break },
        { "continue", TokenType.Continue },
        { "throw", TokenType.Throw },
        { "try", TokenType.Try },
        { "catch", TokenType.Catch },
        { "finally", TokenType.Finally },
        { "new", TokenType.New },
        { "this", TokenType.This },
        { "base", TokenType.Base },
        { "true", TokenType.True },
        { "false", TokenType.False },
        { "null", TokenType.Null },
        { "is", TokenType.Is },
        { "as", TokenType.As },
        { "typeof", TokenType.Typeof },
        { "nameof", TokenType.Nameof },
        { "sizeof", TokenType.Sizeof },
        { "print", TokenType.Print },
        { "where", TokenType.Where },
        { "when", TokenType.When },
        { "and", TokenType.AndKeyword },
        { "or", TokenType.OrKeyword },
        { "not", TokenType.NotKeyword },
        { "virtual", TokenType.Virtual },
        { "override", TokenType.Override },
        { "abstract", TokenType.Abstract },
        { "sealed", TokenType.Sealed },
        { "partial", TokenType.Partial },
        { "static", TokenType.Static },
        { "internal", TokenType.Internal },
        { "protected", TokenType.Protected },
        { "async", TokenType.Async },
        { "await", TokenType.Await },
        { "immutable", TokenType.Immutable },
        { "with", TokenType.With },
        { "type", TokenType.Type },
        { "assert", TokenType.Assert },
        { "operator", TokenType.Operator },
        { "required", TokenType.Required },
        { "init", TokenType.Init },
        { "ref", TokenType.Ref },
        { "out", TokenType.Out },
        { "lock", TokenType.Lock },
        { "file", TokenType.File },
        { "params", TokenType.Params },
        { "checked", TokenType.Checked },
        { "unchecked", TokenType.Unchecked },
        { "implicit", TokenType.Implicit },
        { "explicit", TokenType.Explicit },
    };

    public Lexer(string source, string? fileName = null)
    {
        _source = source;
        _fileName = fileName;
    }

    public List<Token> Tokenize()
    {
        var tokens = new List<Token>();

        while (!IsAtEnd())
        {
            SkipWhitespaceExceptNewlines();

            if (IsAtEnd())
                break;

            var token = NextToken();

            // Skip comments but keep newlines
            if (token.Type == TokenType.Comment ||
                token.Type == TokenType.MultiLineComment ||
                token.Type == TokenType.XmlDocComment)
                continue;

            tokens.Add(token);
        }

        tokens.Add(new Token(TokenType.Eof, "", _line, _column, _fileName));
        return InsertIndentationBraces(tokens);
    }

    private List<Token> InsertIndentationBraces(List<Token> tokens)
    {
        // Supports indentation-based blocks:
        // func main(): void
        //     print("hi")
        //
        // by inserting virtual { } tokens based on indentation changes at line boundaries.

        var output = new List<Token>(tokens.Count);
        var indentStack = new Stack<int>();
        indentStack.Push(0);

        bool atLineStart = true;
        int explicitBraceDepth = 0; // only braces from the source tokens (not the virtual ones we insert)
        int parenBracketDepth = 0;
        var hasBaseIndent = false;
        var baseIndent = 0;

        foreach (var token in tokens)
        {
            if (token.Type == TokenType.Newline)
            {
                output.Add(token);
                atLineStart = true;
                continue;
            }

            if (token.Type == TokenType.Eof)
            {
                // Close any remaining indentation blocks before EOF
                while (indentStack.Count > 1)
                {
                    indentStack.Pop();
                    output.Add(new Token(TokenType.RightBrace, "}", token.Line, 1, token.FileName));
                }

                output.Add(token);
                break;
            }

            if (atLineStart)
            {
                var rawIndent = Math.Max(0, token.Column - 1);

                // Support sources that are globally indented (common in test strings):
                // treat the first non-empty line's indentation as the base indent (0).
                if (!hasBaseIndent && indentStack.Count == 1)
                {
                    baseIndent = rawIndent;
                    hasBaseIndent = true;
                }

                var currentIndent = Math.Max(0, rawIndent - baseIndent);
                var canIndent = parenBracketDepth == 0 && explicitBraceDepth == 0;

                if (canIndent)
                {
                    var previousIndent = indentStack.Peek();

                    if (currentIndent > previousIndent)
                    {
                        indentStack.Push(currentIndent);
                        output.Add(new Token(TokenType.LeftBrace, "{", token.Line, 1, token.FileName));
                    }
                    else if (currentIndent < previousIndent)
                    {
                        while (indentStack.Count > 1 && currentIndent < indentStack.Peek())
                        {
                            indentStack.Pop();
                            output.Add(new Token(TokenType.RightBrace, "}", token.Line, 1, token.FileName));
                        }
                    }
                }

                atLineStart = false;
            }

            // Track source brace nesting so we don't insert indentation braces inside explicit { } blocks.
            if (token.Type == TokenType.LeftBrace)
            {
                explicitBraceDepth++;
            }
            else if (token.Type == TokenType.RightBrace)
            {
                explicitBraceDepth = Math.Max(0, explicitBraceDepth - 1);
            }
            else if (token.Type == TokenType.LeftParen || token.Type == TokenType.LeftBracket)
            {
                parenBracketDepth++;
            }
            else if (token.Type == TokenType.RightParen || token.Type == TokenType.RightBracket)
            {
                parenBracketDepth = Math.Max(0, parenBracketDepth - 1);
            }

            output.Add(token);
        }

        return output;
    }

    private Token NextToken()
    {
        var startLine = _line;
        var startColumn = _column;

        var ch = Peek();

        // Newlines
        if (ch == '\n')
        {
            Advance();
            var token = new Token(TokenType.Newline, "\n", startLine, startColumn, _fileName);
            _line++;
            _column = 1;
            return token;
        }

        // Preprocessor directives
        if (ch == '#')
        {
            return ReadPreprocessorDirective(startLine, startColumn);
        }

        // Comments
        if (ch == '/' && PeekNext() == '/')
        {
            if (PeekAhead(2) == '/')
            {
                return ReadXmlDocComment(startLine, startColumn);
            }
            return ReadSingleLineComment(startLine, startColumn);
        }

        if (ch == '/' && PeekNext() == '*')
        {
            return ReadMultiLineComment(startLine, startColumn);
        }

        // String literals (including interpolated strings)
        if (ch == '$' && PeekNext() == '"')
        {
            Advance(); // consume $
            // Check for interpolated raw string: $"""
            if (Peek() == '"' && PeekNext() == '"' && PeekAhead(2) == '"')
            {
                return ReadInterpolatedRawString(startLine, startColumn);
            }
            return ReadString(startLine, startColumn, isInterpolated: true);
        }

        if (ch == '"')
        {
            if (PeekNext() == '"' && PeekAhead(2) == '"')
            {
                return ReadTripleQuoteString(startLine, startColumn);
            }
            return ReadString(startLine, startColumn);
        }

        // Numbers
        if (char.IsDigit(ch))
        {
            return ReadNumber(startLine, startColumn);
        }

        // Identifiers and keywords
        if (char.IsLetter(ch) || ch == '_')
        {
            return ReadIdentifier(startLine, startColumn);
        }

        // Multi-character operators
        if (ch == ':')
        {
            Advance();
            if (Peek() == '=')
            {
                Advance();
                return new Token(TokenType.ColonAssign, ":=", startLine, startColumn, _fileName);
            }
            if (Peek() == ':')
            {
                Advance();
                return new Token(TokenType.DoubleColon, "::", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.Colon, ":", startLine, startColumn, _fileName);
        }

        if (ch == '=')
        {
            Advance();
            if (Peek() == '=')
            {
                Advance();
                return new Token(TokenType.Equal, "==", startLine, startColumn, _fileName);
            }
            if (Peek() == '>')
            {
                Advance();
                return new Token(TokenType.Arrow, "=>", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.Assign, "=", startLine, startColumn, _fileName);
        }

        if (ch == '!')
        {
            Advance();
            if (Peek() == '=')
            {
                Advance();
                return new Token(TokenType.NotEqual, "!=", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.Not, "!", startLine, startColumn, _fileName);
        }

        if (ch == '<')
        {
            Advance();
            if (Peek() == '=')
            {
                Advance();
                return new Token(TokenType.LessEqual, "<=", startLine, startColumn, _fileName);
            }
            if (Peek() == '<')
            {
                Advance();
                return new Token(TokenType.LeftShift, "<<", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.Less, "<", startLine, startColumn, _fileName);
        }

        if (ch == '>')
        {
            Advance();
            if (Peek() == '=')
            {
                Advance();
                return new Token(TokenType.GreaterEqual, ">=", startLine, startColumn, _fileName);
            }
            if (Peek() == '>')
            {
                Advance();
                return new Token(TokenType.RightShift, ">>", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.Greater, ">", startLine, startColumn, _fileName);
        }

        if (ch == '&')
        {
            Advance();
            if (Peek() == '&')
            {
                Advance();
                return new Token(TokenType.And, "&&", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.BitwiseAnd, "&", startLine, startColumn, _fileName);
        }

        if (ch == '|')
        {
            Advance();
            if (Peek() == '|')
            {
                Advance();
                return new Token(TokenType.Or, "||", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.BitwiseOr, "|", startLine, startColumn, _fileName);
        }

        if (ch == '+')
        {
            Advance();
            if (Peek() == '+')
            {
                Advance();
                return new Token(TokenType.Increment, "++", startLine, startColumn, _fileName);
            }
            if (Peek() == '=')
            {
                Advance();
                return new Token(TokenType.PlusAssign, "+=", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.Plus, "+", startLine, startColumn, _fileName);
        }

        if (ch == '-')
        {
            Advance();
            if (Peek() == '-')
            {
                Advance();
                return new Token(TokenType.Decrement, "--", startLine, startColumn, _fileName);
            }
            if (Peek() == '=')
            {
                Advance();
                return new Token(TokenType.MinusAssign, "-=", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.Minus, "-", startLine, startColumn, _fileName);
        }

        if (ch == '*')
        {
            Advance();
            if (Peek() == '=')
            {
                Advance();
                return new Token(TokenType.StarAssign, "*=", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.Star, "*", startLine, startColumn, _fileName);
        }

        if (ch == '/')
        {
            Advance();
            if (Peek() == '=')
            {
                Advance();
                return new Token(TokenType.SlashAssign, "/=", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.Slash, "/", startLine, startColumn, _fileName);
        }

        if (ch == '?')
        {
            Advance();
            if (Peek() == '?')
            {
                Advance();
                if (Peek() == '=')
                {
                    Advance();
                    return new Token(TokenType.QuestionQuestionAssign, "??=", startLine, startColumn, _fileName);
                }
                return new Token(TokenType.QuestionQuestion, "??", startLine, startColumn, _fileName);
            }
            if (Peek() == '.')
            {
                Advance();
                return new Token(TokenType.QuestionDot, "?.", startLine, startColumn, _fileName);
            }
            if (Peek() == '[')
            {
                Advance();
                return new Token(TokenType.QuestionBracket, "?[", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.Question, "?", startLine, startColumn, _fileName);
        }

        if (ch == '.')
        {
            Advance();
            if (Peek() == '.')
            {
                Advance();
                if (Peek() == '.')
                {
                    Advance();
                    return new Token(TokenType.DotDotDot, "...", startLine, startColumn, _fileName);
                }
                return new Token(TokenType.DotDot, "..", startLine, startColumn, _fileName);
            }
            return new Token(TokenType.Dot, ".", startLine, startColumn, _fileName);
        }

        // Single-character tokens
        var singleChar = ch;
        Advance();

	        return singleChar switch
	        {
	            '(' => new Token(TokenType.LeftParen, "(", startLine, startColumn, _fileName),
	            ')' => new Token(TokenType.RightParen, ")", startLine, startColumn, _fileName),
	            '{' => new Token(TokenType.LeftBrace, "{", startLine, startColumn, _fileName),
	            '}' => new Token(TokenType.RightBrace, "}", startLine, startColumn, _fileName),
	            '[' => new Token(TokenType.LeftBracket, "[", startLine, startColumn, _fileName),
	            ']' => new Token(TokenType.RightBracket, "]", startLine, startColumn, _fileName),
	            ';' => new Token(TokenType.Semicolon, ";", startLine, startColumn, _fileName),
	            ',' => new Token(TokenType.Comma, ",", startLine, startColumn, _fileName),
	            '%' => new Token(TokenType.Percent, "%", startLine, startColumn, _fileName),
	            '^' => new Token(TokenType.BitwiseXor, "^", startLine, startColumn, _fileName),
	            '~' => new Token(TokenType.BitwiseNot, "~", startLine, startColumn, _fileName),
	            // Don't throw here: this lexer is used for error-recovery scenarios where we still want to produce tokens.
	            _ => new Token(TokenType.Unknown, singleChar.ToString(), startLine, startColumn, _fileName)
	        };
	    }

    private Token ReadIdentifier(int startLine, int startColumn)
    {
        var sb = new StringBuilder();

        while (!IsAtEnd() && (char.IsLetterOrDigit(Peek()) || Peek() == '_'))
        {
            sb.Append(Peek());
            Advance();
        }

        var value = sb.ToString();
        var tokenType = Keywords.TryGetValue(value, out var keyword)
            ? keyword
            : TokenType.Identifier;

        return new Token(tokenType, value, startLine, startColumn, _fileName);
    }

    private Token ReadNumber(int startLine, int startColumn)
    {
        var sb = new StringBuilder();
        var isFloat = false;

        while (!IsAtEnd() && (char.IsDigit(Peek()) || Peek() == '.' || Peek() == '_'))
        {
            if (Peek() == '_')
            {
                Advance();
                continue;
            }

            if (Peek() == '.')
            {
                // Check if it's a range operator (..)
                if (PeekNext() == '.')
                    break;

                if (isFloat)
                    throw new Exception($"Invalid number format at {_fileName ?? "?"}:{startLine}:{startColumn}");

                isFloat = true;
            }

            sb.Append(Peek());
            Advance();
        }

        var value = sb.ToString();
        var tokenType = isFloat ? TokenType.FloatLiteral : TokenType.IntLiteral;

        return new Token(tokenType, value, startLine, startColumn, _fileName);
    }

    private Token ReadString(int startLine, int startColumn, bool isInterpolated = false)
    {
        var sb = new StringBuilder();

        // Add $ prefix for interpolated strings
        if (isInterpolated)
            sb.Append('$');

        sb.Append('"');
        Advance(); // consume opening quote

        while (!IsAtEnd() && Peek() != '"')
        {
            // Non-raw strings can't span lines; treat newline as an unterminated string and recover.
            if (Peek() == '\n')
            {
                return new Token(TokenType.StringLiteral, sb.ToString(), startLine, startColumn, _fileName);
            }

            if (Peek() == '\\')
            {
                sb.Append('\\');
                Advance();
                if (IsAtEnd())
                    return new Token(TokenType.StringLiteral, sb.ToString(), startLine, startColumn, _fileName);

                sb.Append(Peek());
                Advance();
            }
            else
            {
                sb.Append(Peek());
                Advance();
            }
        }

        if (IsAtEnd())
            return new Token(TokenType.StringLiteral, sb.ToString(), startLine, startColumn, _fileName);

        sb.Append('"');
        Advance(); // consume closing quote

        return new Token(TokenType.StringLiteral, sb.ToString(), startLine, startColumn, _fileName);
    }

    private Token ReadTripleQuoteString(int startLine, int startColumn)
    {
        var sb = new StringBuilder();
        Advance(); // first quote
        Advance(); // second quote
        Advance(); // third quote

        while (!IsAtEnd())
        {
            if (Peek() == '"' && PeekNext() == '"' && PeekAhead(2) == '"')
            {
                Advance();
                Advance();
                Advance();
                return new Token(TokenType.TripleQuoteStringLiteral, sb.ToString(), startLine, startColumn, _fileName);
            }

            if (Peek() == '\n')
            {
                _line++;
                _column = 0;
            }

            sb.Append(Peek());
            Advance();
        }

        return new Token(TokenType.TripleQuoteStringLiteral, sb.ToString(), startLine, startColumn, _fileName);
    }

    private Token ReadInterpolatedRawString(int startLine, int startColumn)
    {
        var sb = new StringBuilder();
        sb.Append("$\"\"\"");

        Advance(); // first quote
        Advance(); // second quote
        Advance(); // third quote

        while (!IsAtEnd())
        {
            if (Peek() == '"' && PeekNext() == '"' && PeekAhead(2) == '"')
            {
                sb.Append("\"\"\"");
                Advance();
                Advance();
                Advance();
                return new Token(TokenType.InterpolatedRawStringLiteral, sb.ToString(), startLine, startColumn, _fileName);
            }

            if (Peek() == '\n')
            {
                _line++;
                _column = 0;
            }

            sb.Append(Peek());
            Advance();
        }

        return new Token(TokenType.InterpolatedRawStringLiteral, sb.ToString(), startLine, startColumn, _fileName);
    }

    private Token ReadSingleLineComment(int startLine, int startColumn)
    {
        var sb = new StringBuilder();

        while (!IsAtEnd() && Peek() != '\n')
        {
            sb.Append(Peek());
            Advance();
        }

        return new Token(TokenType.Comment, sb.ToString(), startLine, startColumn, _fileName);
    }

    private Token ReadMultiLineComment(int startLine, int startColumn)
    {
        var sb = new StringBuilder();
        Advance(); // consume /
        Advance(); // consume *

        while (!IsAtEnd())
        {
            if (Peek() == '*' && PeekNext() == '/')
            {
                Advance();
                Advance();
                return new Token(TokenType.MultiLineComment, sb.ToString(), startLine, startColumn, _fileName);
            }

            if (Peek() == '\n')
            {
                _line++;
                _column = 0;
            }

            sb.Append(Peek());
            Advance();
        }

        return new Token(TokenType.MultiLineComment, sb.ToString(), startLine, startColumn, _fileName);
    }

    private Token ReadXmlDocComment(int startLine, int startColumn)
    {
        var sb = new StringBuilder();

        while (!IsAtEnd() && Peek() != '\n')
        {
            sb.Append(Peek());
            Advance();
        }

        return new Token(TokenType.XmlDocComment, sb.ToString(), startLine, startColumn, _fileName);
    }

    private Token ReadPreprocessorDirective(int startLine, int startColumn)
    {
        var sb = new StringBuilder();

        while (!IsAtEnd() && Peek() != '\n')
        {
            sb.Append(Peek());
            Advance();
        }

        return new Token(TokenType.PreprocessorDirective, sb.ToString(), startLine, startColumn, _fileName);
    }

    private void SkipWhitespaceExceptNewlines()
    {
        while (!IsAtEnd() && char.IsWhiteSpace(Peek()) && Peek() != '\n')
        {
            Advance();
        }
    }

    private char Peek()
    {
        if (IsAtEnd())
            return '\0';
        return _source[_position];
    }

    private char PeekNext()
    {
        if (_position + 1 >= _source.Length)
            return '\0';
        return _source[_position + 1];
    }

    private char PeekAhead(int offset)
    {
        if (_position + offset >= _source.Length)
            return '\0';
        return _source[_position + offset];
    }

    private void Advance()
    {
        if (!IsAtEnd())
        {
            _position++;
            _column++;
        }
    }

    private bool IsAtEnd() => _position >= _source.Length;
}
