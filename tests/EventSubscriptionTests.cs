using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Parser and analyzer coverage for the <c>on</c>/<c>off</c> event-subscription keywords and the
/// diagnostics that replace the old silent-accept-then-FieldAccessException behavior.
/// </summary>
public class EventSubscriptionTests
{
    private static CompilationUnit Parse(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        return parser.ParseCompilationUnit().CompilationUnit!;
    }

    private static AnalysisResult Analyze(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var result = parser.ParseCompilationUnit();
        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        return analyzer.Analyze(result.CompilationUnit!);
    }

    private static BlockStatement MainBody(CompilationUnit cu)
    {
        var fn = Assert.IsType<FunctionDeclaration>(cu.Declarations[0]);
        Assert.NotNull(fn.Body);
        return fn.Body!;
    }

    // ---- Parsing ----

    [Fact]
    public void Parse_OnSubscription_AsStatement()
    {
        var cu = Parse(@"func main() {
    on widget.Clicked (sender, args) => { print ""hi"" }
}");

        var exprStmt = Assert.IsType<ExpressionStatement>(MainBody(cu).Statements[0]);
        var on = Assert.IsType<OnSubscriptionExpression>(exprStmt.Expression);
        Assert.IsType<MemberAccessExpression>(on.Target);
        Assert.Equal(2, on.Handler.Parameters.Count);
    }

    [Fact]
    public void Parse_OnSubscription_AsShorthandDeclaration()
    {
        var cu = Parse(@"func main() {
    sub := on widget.Clicked (sender, args) => { }
}");

        var decl = Assert.IsType<VariableDeclarationStatement>(MainBody(cu).Statements[0]);
        Assert.Equal("sub", decl.Name);
        Assert.IsType<OnSubscriptionExpression>(decl.Initializer);
    }

    [Fact]
    public void Parse_OnSubscription_AllowsThisTarget()
    {
        // Subscribing to an event inherited from a .NET base class: `on this.Event ...`.
        var cu = Parse(@"func main() {
    on this.Clicked (sender, args) => { }
}");

        var exprStmt = Assert.IsType<ExpressionStatement>(MainBody(cu).Statements[0]);
        var on = Assert.IsType<OnSubscriptionExpression>(exprStmt.Expression);
        var member = Assert.IsType<MemberAccessExpression>(on.Target);
        Assert.IsType<ThisExpression>(member.Object);
        Assert.Equal("Clicked", member.MemberName);
    }

    [Fact]
    public void Parse_OffStatement()
    {
        var cu = Parse(@"func main() {
    off sub
}");

        var off = Assert.IsType<OffStatement>(MainBody(cu).Statements[0]);
        var handle = Assert.IsType<IdentifierExpression>(off.Handle);
        Assert.Equal("sub", handle.Name);
    }

    [Fact]
    public void Parse_OnAndOff_RemainUsableAsIdentifiers()
    {
        // `on`/`off` are contextual keywords; existing code that uses them as names must still parse.
        var cu = Parse(@"func main() {
    on := 5
    off := 10
    total := on + off
    print total
}");

        var statements = MainBody(cu).Statements;
        Assert.Equal("on", Assert.IsType<VariableDeclarationStatement>(statements[0]).Name);
        Assert.Equal("off", Assert.IsType<VariableDeclarationStatement>(statements[1]).Name);
        Assert.IsType<VariableDeclarationStatement>(statements[2]);
    }

    // ---- Analysis / diagnostics ----

    [Fact]
    public void Analyze_EventPlusEquals_IsRejectedWithOnOffGuidance()
    {
        // The core bug: this used to pass analysis and then throw FieldAccessException at runtime.
        var result = Analyze(@"
import System

func main() {
    AppDomain.CurrentDomain.ProcessExit += (sender, args) => {
        print ""exiting""
    }
}");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.EventRequiresOnOff);
        Assert.Contains("ProcessExit", error.Message);
    }

    [Fact]
    public void Analyze_EventMinusEquals_IsRejected()
    {
        var result = Analyze(@"
import System

func main() {
    AppDomain.CurrentDomain.ProcessExit -= (sender, args) => {
        print ""exiting""
    }
}");

        Assert.Single(result.Errors, e => e.Code == ErrorCode.EventRequiresOnOff);
    }

    [Fact]
    public void Analyze_OnSubscriptionToEvent_HasNoErrors()
    {
        var result = Analyze(@"
import System

func main() {
    on AppDomain.CurrentDomain.ProcessExit (sender, args) => {
        print ""exiting""
    }
    print ""ok""
}");

        Assert.False(result.HasErrors, string.Join("\n", result.Errors.Select(e => e.Message)));
    }

    [Fact]
    public void Analyze_DelegateFieldPlusEquals_IsAllowed()
    {
        // A real Func/delegate is not an event; `+=` must keep type-checking.
        var result = Analyze(@"
import System

func main() {
    f: Func<int, int> = x => x + 1
    g: Func<int, int> = x => x + 2
    f += g
}");

        Assert.False(result.HasErrors, string.Join("\n", result.Errors.Select(e => e.Message)));
    }

    [Fact]
    public void Analyze_OffOnNonSubscription_IsRejected()
    {
        var result = Analyze(@"
func main() {
    x := 5
    off x
}");

        Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidEventSubscription);
    }
}
