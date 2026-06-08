using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;
using NSharpLang.Cli;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.Compiler.Columnar;
using Xunit;

namespace NSharpLang.Tests;

public class CompilerDogfoodProjectTests
{
    // The production-routed parser token-compaction kernel
    // (LexerTokenKindScanner.nl: ParserTokenCompactionIndicesInto) filters newline tokens by the
    // hard-coded integer ordinal 136. The Parser constructor routes through it via
    // NSharpCompilerDogfoodAdapter.TryCompactParserTokens. If a TokenType member is inserted in the
    // middle of the enum, Newline's ordinal shifts, the kernel filters the wrong token type, and the
    // parser silently sees stray newline tokens (every braced source then fails to parse). This pins
    // the contract: new TokenType members must be appended at the END of the enum. See Token.cs.
    [Fact]
    public void ParserTokenCompactionParityRespectsTokenTypeLayout()
    {
        Assert.Equal(136, (int)TokenType.Newline);
    }

    // Dogfood the C# parser + the `nlc query ast` serializer (OutputFormatter.AstToJson) over every
    // real .nl file in examples/ and the dogfood kernels: parsing must not crash, must yield a
    // CompilationUnit, and the AST JSON must be valid, carry the stable envelope, and be deterministic
    // (byte-identical on repeat) so the schema is stable. This hardens the canonical-AST harness that a
    // future N# parser will be verified against, and catches parser/serializer regressions on real code.
    // First N#-native parser slice: the TopLevelDeclarationKindsInto kernel must reproduce the C#
    // parser's CompilationUnit.Declarations kind sequence (mapping each declaration to its keyword
    // TokenType) from the brace-inserted token stream, on a controlled corpus exercising the keyword
    // declaration kinds (incl. nested declarations that must be EXCLUDED, modifiers, attributes,
    // ref struct, duck interface) and on the dogfood compiler-service kernels themselves.
    [Fact]
    public void Parser_TopLevelDeclarationKinds_MatchProductionParser()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(
            Path.GetTempPath(),
            $"NSharpLang.Compiler.Dogfood.ParserDecls.{Guid.NewGuid():N}.dll");

        try
        {
            var result = new MultiFileCompiler(projectRoot, config)
                .CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);
            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(e => e.Message)));

            var assembly = Assembly.Load(File.ReadAllBytes(outputPath));
            var programType = assembly.GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var tokenizeWithIndentation = programType.GetMethod(
                    "TokenizeMetadataWithIndentationInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeMetadataWithIndentationInto.");
            var topLevelDecls = programType.GetMethod(
                    "TopLevelDeclarationKindsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TopLevelDeclarationKindsInto.");
            var topLevelDeclNames = programType.GetMethod(
                    "TopLevelDeclarationNameSpansInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TopLevelDeclarationNameSpansInto.");
            var packageNameSpan = programType.GetMethod(
                    "PackageNameSpanInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit PackageNameSpanInto.");
            var namespaceImportSpans = programType.GetMethod(
                    "NamespaceImportSpansInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit NamespaceImportSpansInto.");
            var declModifiers = programType.GetMethod(
                    "TopLevelDeclarationModifiersInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TopLevelDeclarationModifiersInto.");

            const string controlledCorpus = """
import System
import A.B.C as Alias

package Demo.Declarations

func top(): int {
    return 1
}

class Container {
    value: int

    func method(): int {
        return value
    }

    struct Nested {
        z: int
    }
}

public struct Point {
    x: int
    y: int
}

enum Color {
    Red,
    Green
}

interface Shape {
    func area(): double
}

record Person {
    name: string
    age: int
}
""";

            AssertTopLevelDeclarationKindsLikeProduction(controlledCorpus, tokenizeWithIndentation, topLevelDecls, topLevelDeclNames, packageNameSpan, namespaceImportSpans, declModifiers);

            // Modifier-rich declarations: every recognized declaration modifier, singly and combined, plus
            // attributes (which sit inside brackets and must not be mistaken for modifiers). Verifies the
            // kernel accumulates the same flag set the C# parser records on Declaration.Modifiers.
            const string modifierCorpus = """
public func a(): int {
    return 1
}

private static func b(): int {
    return 2
}

internal async func c(): int {
    return 3
}

public abstract class C {
    func m(): void {}
}

public sealed class D {
    value: int
}

internal partial struct S {
    x: int
}

[Obsolete]
public record R {
    name: string
}

public interface I {
    func area(): double
}

protected virtual func e(): int {
    return 4
}

public override func f(): int {
    return 5
}
""";
            AssertTopLevelDeclarationKindsLikeProduction(modifierCorpus, tokenizeWithIndentation, topLevelDecls, topLevelDeclNames, packageNameSpan, namespaceImportSpans, declModifiers);

            // Indentation-style declarations: the composed lexer inserts virtual braces, and the kernel
            // tracks depth through them identically to explicit braces, so nested members are excluded.
            const string indentedCorpus = """
func a(): int
    return 1

class B
    value: int
    func m(): int
        return value
    struct N
        z: int
""";
            AssertTopLevelDeclarationKindsLikeProduction(indentedCorpus, tokenizeWithIndentation, topLevelDecls, topLevelDeclNames, packageNameSpan, namespaceImportSpans, declModifiers);

            // The dogfood compiler-service kernels themselves (all top-level funcs) -- real code.
            foreach (var file in Directory
                .EnumerateFiles(Path.Combine(projectRoot, "CompilerServices"), "*.nl")
                .OrderBy(p => p, StringComparer.Ordinal))
            {
                AssertTopLevelDeclarationKindsLikeProduction(File.ReadAllText(file), tokenizeWithIndentation, topLevelDecls, topLevelDeclNames, packageNameSpan, namespaceImportSpans, declModifiers, file);
            }
        }
        finally
        {
            if (File.Exists(outputPath)) File.Delete(outputPath);
        }
    }

    private static void AssertTopLevelDeclarationKindsLikeProduction(
        string source,
        MethodInfo tokenizeWithIndentation,
        MethodInfo topLevelDecls,
        MethodInfo topLevelDeclNames,
        MethodInfo packageNameSpan,
        MethodInfo namespaceImportSpans,
        MethodInfo declModifiers,
        string? label = null)
    {
        var expected = ExpectedDeclarations(source);
        var expectedKinds = expected.Select(d => d.Kind).ToArray();
        var labelSuffix = label != null ? $" for {label}" : string.Empty;

        var capacity = 3 * (source.Length + 1) + 8;
        var kinds = new int[capacity];
        var starts = new int[capacity];
        var valueLengths = new int[capacity];
        var lines = new int[capacity];
        var columns = new int[capacity];
        var count = (int)(tokenizeWithIndentation.Invoke(
            null,
            new object[] { source, kinds, starts, valueLengths, lines, columns }) ?? -1);

        // Slice 1: kind sequence.
        var outKinds = new int[count + 1];
        var declCount = (int)(topLevelDecls.Invoke(null, new object[] { kinds, count, outKinds }) ?? -1);
        var actualKinds = outKinds.Take(declCount).ToArray();
        Assert.True(
            expectedKinds.SequenceEqual(actualKinds),
            $"Top-level declaration kind mismatch{labelSuffix}.\n" +
            $"expected: [{string.Join(", ", expectedKinds)}]\nactual:   [{string.Join(", ", actualKinds)}]");

        // Slice 2: kind + name sequence (name = null for `test` string-named declarations).
        var nameKinds = new int[count + 1];
        var nameStarts = new int[count + 1];
        var nameLengths = new int[count + 1];
        var nameCount = (int)(topLevelDeclNames.Invoke(
            null,
            new object[] { kinds, starts, valueLengths, count, nameKinds, nameStarts, nameLengths }) ?? -1);
        Assert.Equal(expected.Length, nameCount);
        for (var i = 0; i < expected.Length; i++)
        {
            Assert.Equal(expected[i].Kind, nameKinds[i]);
            var actualName = nameStarts[i] < 0 ? null : source.Substring(nameStarts[i], nameLengths[i]);
            // `test` declarations have string names the kernel does not extract; C# side is null too.
            var expectedName = expected[i].Kind == (int)TokenType.Test ? null : expected[i].Name;
            Assert.True(
                expectedName == actualName,
                $"Top-level declaration name mismatch{labelSuffix} at {i} (kind {nameKinds[i]}): " +
                $"expected '{expectedName ?? "<null>"}', actual '{actualName ?? "<null>"}'");
        }

        // Slice 3: package name.
        var packageResult = new int[2];
        var hasPackage = (int)(packageNameSpan.Invoke(
            null,
            new object[] { kinds, starts, valueLengths, count, packageResult }) ?? -1);
        var actualPackage = hasPackage == 1 ? source.Substring(packageResult[0], packageResult[1]) : null;
        var expectedPackage = ExpectedPackage(source);
        Assert.True(
            expectedPackage == actualPackage,
            $"Package name mismatch{labelSuffix}: expected '{expectedPackage ?? "<null>"}', " +
            $"actual '{actualPackage ?? "<null>"}'");

        // Slice 4: namespace imports (namespace + optional alias).
        var nsStartsOut = new int[count + 1];
        var nsLengthsOut = new int[count + 1];
        var aliasStartsOut = new int[count + 1];
        var aliasLengthsOut = new int[count + 1];
        var importCount = (int)(namespaceImportSpans.Invoke(
            null,
            new object[] { kinds, starts, valueLengths, count, nsStartsOut, nsLengthsOut, aliasStartsOut, aliasLengthsOut }) ?? -1);
        var expectedImports = ExpectedImports(source);
        Assert.Equal(expectedImports.Length, importCount);
        for (var i = 0; i < expectedImports.Length; i++)
        {
            var actualNs = source.Substring(nsStartsOut[i], nsLengthsOut[i]);
            var actualAlias = aliasStartsOut[i] < 0 ? null : source.Substring(aliasStartsOut[i], aliasLengthsOut[i]);
            Assert.True(
                expectedImports[i].Namespace == actualNs && expectedImports[i].Alias == actualAlias,
                $"Namespace import mismatch{labelSuffix} at {i}: expected " +
                $"'{expectedImports[i].Namespace}'/'{expectedImports[i].Alias ?? "<null>"}', actual " +
                $"'{actualNs}'/'{actualAlias ?? "<null>"}'");
        }

        // Slice 5: per-declaration modifier flags (mirrors (int)Declaration.Modifiers). The kernel records
        // raw leading modifiers for every declaration keyword; we compare against the C# AST for the seven
        // modifier-bearing node kinds and skip `type`/`test` (DeclarationModifiers == -1) which have no
        // Modifiers field.
        var modKinds = new int[count + 1];
        var modFlags = new int[count + 1];
        var modCount = (int)(declModifiers.Invoke(null, new object[] { kinds, count, modKinds, modFlags }) ?? -1);
        Assert.Equal(expected.Length, modCount);
        for (var i = 0; i < expected.Length; i++)
        {
            Assert.Equal(expected[i].Kind, modKinds[i]);
            if (expected[i].Modifiers < 0) continue; // `type`/`test`: AST drops modifiers, kernel does not.
            Assert.True(
                expected[i].Modifiers == modFlags[i],
                $"Top-level declaration modifier mismatch{labelSuffix} at {i} (kind {modKinds[i]}): " +
                $"expected {expected[i].Modifiers}, actual {modFlags[i]}");
        }
    }

    private static string? ExpectedPackage(string source)
    {
        var tokens = new Lexer(source, "decl-test.nl").Tokenize();
        var compilationUnit = new Parser(tokens, "decl-test.nl").ParseCompilationUnit().CompilationUnit;
        return compilationUnit?.Package?.Name;
    }

    private static (string Namespace, string? Alias)[] ExpectedImports(string source)
    {
        var tokens = new Lexer(source, "decl-test.nl").Tokenize();
        var compilationUnit = new Parser(tokens, "decl-test.nl").ParseCompilationUnit().CompilationUnit;
        if (compilationUnit == null) return Array.Empty<(string, string?)>();
        return compilationUnit.Imports.Select(import => (import.Namespace, import.Alias)).ToArray();
    }

    private static (int Kind, string? Name, int Modifiers)[] ExpectedDeclarations(string source)
    {
        var tokens = new Lexer(source, "decl-test.nl").Tokenize();
        var compilationUnit = new Parser(tokens, "decl-test.nl").ParseCompilationUnit().CompilationUnit;
        if (compilationUnit == null) return Array.Empty<(int, string?, int)>();
        return compilationUnit.Declarations
            .Select(d => (DeclarationKeywordKind(d), DeclarationName(d), DeclarationModifiers(d)))
            .ToArray();
    }

    // (int)Declaration.Modifiers for the modifier-bearing declaration nodes. TypeAliasDeclaration and
    // TestDeclaration have no Modifiers field (the C# parser discards leading modifiers for `type`/`test`),
    // so they return -1 -- a "not tracked" sentinel the modifier verification skips. The N# kernel records
    // raw leading modifiers for every declaration keyword (including `type`), so corpora intentionally do
    // not put modifiers on `type`/`test`, where the C# AST and the kernel would otherwise diverge.
    private static int DeclarationModifiers(Declaration declaration) => declaration switch
    {
        FunctionDeclaration f => (int)f.Modifiers,
        ClassDeclaration c => (int)c.Modifiers,
        StructDeclaration s => (int)s.Modifiers,
        RecordDeclaration r => (int)r.Modifiers,
        InterfaceDeclaration i => (int)i.Modifiers,
        UnionDeclaration u => (int)u.Modifiers,
        EnumDeclaration e => (int)e.Modifiers,
        _ => -1
    };

    private static string? DeclarationName(Declaration declaration) => declaration switch
    {
        FunctionDeclaration f => f.Name,
        ClassDeclaration c => c.Name,
        StructDeclaration s => s.Name,
        RecordDeclaration r => r.Name,
        InterfaceDeclaration i => i.Name,
        UnionDeclaration u => u.Name,
        EnumDeclaration e => e.Name,
        TypeAliasDeclaration t => t.Name,
        _ => null
    };

    private static int DeclarationKeywordKind(Declaration declaration) => declaration switch
    {
        FunctionDeclaration => (int)TokenType.Func,
        ClassDeclaration => (int)TokenType.Class,
        StructDeclaration => (int)TokenType.Struct,
        RecordDeclaration => (int)TokenType.Record,
        InterfaceDeclaration => (int)TokenType.Interface,
        UnionDeclaration => (int)TokenType.Union,
        EnumDeclaration => (int)TokenType.Enum,
        TypeAliasDeclaration => (int)TokenType.Type,
        TestDeclaration => (int)TokenType.Test,
        // Any other declaration (setup/teardown/preprocessor/error placeholder) is out of scope for this
        // first slice; -1 will not be produced by the kernel, so it surfaces as a clear mismatch.
        _ => -1
    };

    // Parser slices 6-8: the first N#-native RECURSIVE-DESCENT, tree-building parser kernel. Where slices
    // 1-5 produced flat top-level indices, ParseTypeReferenceNodesInto (ParserTypeReferences.nl) reproduces
    // the C# parser's ParseTypeReference recursion for Simple / Generic / Array / Nullable (slice 6), Union
    // (slice 7), and ByRef (slice 8) type references and emits a real parent->child AST as a flat columnar
    // node table. This pins it structurally against the production parser's TypeReference tree (kind + name
    // + children) plus byte-span, post-order-root, full-consumption, determinism, deferred-form-seam, and
    // depth-cap invariants. Tuple remains deferred (refused with -1); Func needs source access (see below).
    [Fact]
    public void Parser_TypeReferenceTree_MatchesProductionParser()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(
            Path.GetTempPath(),
            $"NSharpLang.Compiler.Dogfood.ParserTypeRefs.{Guid.NewGuid():N}.dll");

        try
        {
            var result = new MultiFileCompiler(projectRoot, config)
                .CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);
            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(e => e.Message)));

            var assembly = Assembly.Load(File.ReadAllBytes(outputPath));
            var programType = assembly.GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var tokenize = programType.GetMethod(
                    "TokenizeMetadataWithIndentationInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeMetadataWithIndentationInto.");
            var parseTypeRefs = programType.GetMethod(
                    "ParseTypeReferenceNodesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ParseTypeReferenceNodesInto.");

            // Positive corpus: every supported form, singly and recursively composed. Notably exercises the
            // `>>` (RightShift) split (List<List<int>>, Foo<Bar<Baz<int>>>), postfix composition
            // (List<int>[], List<int>[]?, int?[]), and dotted names (A.B.C, Outer.Inner<int>, List<A.B.C>).
            // `Func<...>` is intentionally absent: the C# AST models it as FunctionTypeReference, not a
            // generic, so it belongs to a later rung.
            string[] positives =
            {
                "int", "string", "MyNs.Type", "A.B.C",
                "int[]", "string[][]", "int[][][]", "int?", "string?", "int?[]",
                "List<int>", "Dictionary<string, int>", "IEnumerable<int>", "Tuple<int, string, bool>",
                "List<List<int>>", "List<Dictionary<string, int>>", "Foo<Bar<Baz<int>>>",
                // Multi-arg generics whose args are THEMSELVES generic -- the exact interleaving case that
                // requires gathering args on the LIFO arg-stack before appending the contiguous child run.
                "Dictionary<List<int>, List<int>>", "Dictionary<List<int>, int>",
                "Map<List<int>, Dictionary<string, int>>",
                "List<int[]>", "List<int?>", "List<int>?", "List<int>[]", "List<int>[]?",
                "Outer.Inner<int>", "List<A.B.C>",
                // Unions (slice 7): arms are postfix types; a union may itself be a generic argument.
                "int | string", "int | string | bool", "List<int> | string", "int? | string[]",
                "List<int | string>", "Dictionary<int | string, bool>", "int[] | List<int> | string?",
                // ByRef (slice 8): `&` prefixing a postfix type; reachable as a union arm / generic arg too.
                "&int", "&List<int>", "&int[]", "List<&int>", "&int | string",
            };
            foreach (var t in positives)
                AssertTypeReferenceTreeLikeProduction(t, tokenize, parseTypeRefs);

            // Real-corpus pins: the literal Simple/Array type annotations that appear in the dogfood kernel
            // signatures, mirroring the lexer's real-corpus discipline.
            foreach (var t in new[] { "int", "int[]", "string", "bool", "string[]" })
                AssertTypeReferenceTreeLikeProduction(t, tokenize, parseTypeRefs);

            // Deferred-form seam (REFUSED with -1): tuple/parenthesized types start with `(`, which the
            // kernel does not yet handle (Tuple needs per-element name metadata). `Func<...>` is NOT in the
            // refused set: without source access the kernel cannot detect the "Func" identifier text, so it
            // parses as a Generic node -- it is simply excluded from the corpus until the parser gains
            // source access.
            foreach (var t in new[] { "(int, string)", "(int)" })
                AssertTypeReferenceRefused(t, tokenize, parseTypeRefs);

            // Depth cap: generic nesting beyond 64 returns the -1 overflow sentinel (a tested, documented
            // limit -- the kernel never blows the real stack).
            AssertTypeReferenceRefused(DeeplyNestedGeneric(70), tokenize, parseTypeRefs);
        }
        finally
        {
            if (File.Exists(outputPath)) File.Delete(outputPath);
        }
    }

    private static string DeeplyNestedGeneric(int depth)
    {
        var sb = new System.Text.StringBuilder();
        for (var i = 0; i < depth; i++) sb.Append("List<");
        sb.Append("int");
        for (var i = 0; i < depth; i++) sb.Append('>');
        return sb.ToString();
    }

    private static (int Count, int[] Kinds, int[] Starts, int[] ValueLengths, int Start, string Source)
        TokenizeTypeAnnotation(string typeString, MethodInfo tokenize)
    {
        var source = "class T { v: " + typeString + " }";
        var capacity = 3 * (source.Length + 1) + 8;
        var kinds = new int[capacity];
        var starts = new int[capacity];
        var valueLengths = new int[capacity];
        var lines = new int[capacity];
        var columns = new int[capacity];
        var count = (int)(tokenize.Invoke(
            null,
            new object[] { source, kinds, starts, valueLengths, lines, columns }) ?? -1);

        // The type annotation begins one token after the field's `:` (Colon == 122); type references in this
        // slice contain no colons, so the first Colon is unambiguously the field separator.
        var start = -1;
        for (var i = 0; i < count; i++)
        {
            if (kinds[i] == 122) { start = i + 1; break; }
        }
        Assert.True(start > 0, $"Could not locate field colon for type '{typeString}'.");
        return (count, kinds, starts, valueLengths, start, source);
    }

    private static void AssertTypeReferenceTreeLikeProduction(string typeString, MethodInfo tokenize, MethodInfo parseTypeRefs)
    {
        // Ground truth: parse `class T { v: S }` with the production lexer+parser and pull the field's type.
        var tokens = new Lexer("class T { v: " + typeString + " }", "decl-test.nl").Tokenize();
        var compilationUnit = new Parser(tokens, "decl-test.nl").ParseCompilationUnit().CompilationUnit;
        Assert.NotNull(compilationUnit);
        var cls = compilationUnit!.Declarations.OfType<ClassDeclaration>().Single();
        var field = cls.Members.OfType<FieldDeclaration>().Single();
        var expected = field.Type;
        Assert.True(expected != null, $"Production parser produced no field type for '{typeString}'.");

        var (count, kinds, starts, valueLengths, start, source) = TokenizeTypeAnnotation(typeString, tokenize);

        var (nodeCount, k, ns, nl, cs, cc, ci, ss, sl, res) = InvokeParseTypeRefs(parseTypeRefs, kinds, starts, valueLengths, count, start);
        Assert.True(nodeCount > 0, $"Kernel refused valid type '{typeString}' (returned {nodeCount}).");

        var root = res[0];
        Assert.Equal(nodeCount - 1, root); // post-order: the root is the last node emitted

        AssertTypeRefNode(expected!, root, k, ns, nl, cs, cc, ci, source, typeString);

        // Byte-span pin: the root node's span is exactly the type annotation text.
        Assert.Equal(typeString, source.Substring(ss[root], sl[root]));

        // Full consumption: the continuation cursor lands on a type terminator (RightBrace 130 / Newline 136
        // / Eof 135), proving the kernel consumed the whole type and nothing more.
        Assert.True(res[1] < count, $"Continuation cursor out of range for '{typeString}'.");
        var terminator = kinds[res[1]];
        Assert.True(
            terminator == 130 || terminator == 136 || terminator == 135,
            $"Type '{typeString}' did not consume to a terminator; next token kind = {terminator}.");

        // Determinism: a second invocation produces byte-identical node tables.
        var (nodeCount2, k2, ns2, nl2, cs2, cc2, ci2, ss2, sl2, res2) =
            InvokeParseTypeRefs(parseTypeRefs, kinds, starts, valueLengths, count, start);
        Assert.Equal(nodeCount, nodeCount2);
        Assert.Equal(res[0], res2[0]);
        Assert.Equal(res[1], res2[1]);
        for (var i = 0; i < nodeCount; i++)
        {
            Assert.True(
                k[i] == k2[i] && ns[i] == ns2[i] && nl[i] == nl2[i] && cs[i] == cs2[i] &&
                cc[i] == cc2[i] && ci[i] == ci2[i] && ss[i] == ss2[i] && sl[i] == sl2[i],
                $"Non-deterministic node table at index {i} for '{typeString}'.");
        }
    }

    private static void AssertTypeReferenceRefused(string typeString, MethodInfo tokenize, MethodInfo parseTypeRefs)
    {
        var (count, kinds, starts, valueLengths, start, _) = TokenizeTypeAnnotation(typeString, tokenize);
        var (nodeCount, _, _, _, _, _, _, _, _, _) = InvokeParseTypeRefs(parseTypeRefs, kinds, starts, valueLengths, count, start);
        Assert.True(nodeCount == -1, $"Kernel should refuse deferred form '{typeString}' with -1, got {nodeCount}.");
    }

    private static (int NodeCount, int[] Kinds, int[] NameStarts, int[] NameLengths, int[] ChildStart,
        int[] ChildCount, int[] ChildIndices, int[] SpanStarts, int[] SpanLengths, int[] Result)
        InvokeParseTypeRefs(MethodInfo parseTypeRefs, int[] kinds, int[] starts, int[] valueLengths, int count, int start)
    {
        var outNodeKinds = new int[count + 1];
        var outNameStarts = new int[count + 1];
        var outNameLengths = new int[count + 1];
        var outChildStart = new int[count + 1];
        var outChildCount = new int[count + 1];
        var outChildIndices = new int[count + 1];
        var outSpanStarts = new int[count + 1];
        var outSpanLengths = new int[count + 1];
        var outResult = new int[2];
        var nodeCount = (int)(parseTypeRefs.Invoke(
            null,
            new object[]
            {
                kinds, starts, valueLengths, count, start,
                outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount, outChildIndices,
                outSpanStarts, outSpanLengths, outResult,
            }) ?? -2);
        return (nodeCount, outNodeKinds, outNameStarts, outNameLengths, outChildStart, outChildCount,
            outChildIndices, outSpanStarts, outSpanLengths, outResult);
    }

    private static void AssertTypeRefNode(
        TypeReference expected, int idx,
        int[] kinds, int[] nameStarts, int[] nameLengths, int[] childStart, int[] childCount, int[] childIndices,
        string source, string label)
    {
        switch (expected)
        {
            case SimpleTypeReference s:
                Assert.True(kinds[idx] == 0, $"Expected Simple (0) at node {idx} for '{label}', got kind {kinds[idx]}.");
                Assert.Equal(s.Name, source.Substring(nameStarts[idx], nameLengths[idx]));
                Assert.Equal(0, childCount[idx]);
                break;
            case GenericTypeReference g:
                Assert.True(kinds[idx] == 1, $"Expected Generic (1) at node {idx} for '{label}', got kind {kinds[idx]}.");
                Assert.Equal(g.Name, source.Substring(nameStarts[idx], nameLengths[idx]));
                Assert.Equal(g.TypeArguments.Count, childCount[idx]);
                for (var ai = 0; ai < g.TypeArguments.Count; ai++)
                    AssertTypeRefNode(g.TypeArguments[ai], childIndices[childStart[idx] + ai], kinds, nameStarts, nameLengths, childStart, childCount, childIndices, source, label);
                break;
            case ArrayTypeReference a:
                Assert.True(kinds[idx] == 2, $"Expected Array (2) at node {idx} for '{label}', got kind {kinds[idx]}.");
                Assert.Equal(1, childCount[idx]);
                AssertTypeRefNode(a.ElementType, childIndices[childStart[idx]], kinds, nameStarts, nameLengths, childStart, childCount, childIndices, source, label);
                break;
            case NullableTypeReference n:
                Assert.True(kinds[idx] == 3, $"Expected Nullable (3) at node {idx} for '{label}', got kind {kinds[idx]}.");
                Assert.Equal(1, childCount[idx]);
                AssertTypeRefNode(n.InnerType, childIndices[childStart[idx]], kinds, nameStarts, nameLengths, childStart, childCount, childIndices, source, label);
                break;
            case UnionTypeReference u:
                Assert.True(kinds[idx] == 4, $"Expected Union (4) at node {idx} for '{label}', got kind {kinds[idx]}.");
                Assert.Equal(u.Arms.Count, childCount[idx]);
                for (var ui = 0; ui < u.Arms.Count; ui++)
                    AssertTypeRefNode(u.Arms[ui], childIndices[childStart[idx] + ui], kinds, nameStarts, nameLengths, childStart, childCount, childIndices, source, label);
                break;
            case ByRefTypeReference b:
                Assert.True(kinds[idx] == 5, $"Expected ByRef (5) at node {idx} for '{label}', got kind {kinds[idx]}.");
                Assert.Equal(1, childCount[idx]);
                AssertTypeRefNode(b.InnerType, childIndices[childStart[idx]], kinds, nameStarts, nameLengths, childStart, childCount, childIndices, source, label);
                break;
            default:
                Assert.Fail($"Unexpected production type node {expected.GetType().Name} for '{label}' (out of slice-6/7 scope).");
                break;
        }
    }

    // Parser slice 9: the first declaration-level recursive-descent kernel. ParseFunctionSignatureInto
    // (ParserFunctionSignatures.nl) COMPOSES the slice 6-8 type kernel to parse a function's signature --
    // name, parameter names + parameter type trees, and the return type tree -- and is pinned against the
    // production parser's FunctionDeclaration (Name, Parameters[].Name/.Type, ReturnType) on a synthetic
    // corpus exercising every supported parameter/return type form plus modifiers, defaults, `this`, and
    // type-parameter skipping, and on every top-level function in the real dogfood kernels whose signature
    // stays within the supported type forms.
    [Fact]
    public void Parser_FunctionSignature_MatchesProductionParser()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(
            Path.GetTempPath(),
            $"NSharpLang.Compiler.Dogfood.ParserFnSig.{Guid.NewGuid():N}.dll");

        try
        {
            var result = new MultiFileCompiler(projectRoot, config)
                .CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);
            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(e => e.Message)));

            var assembly = Assembly.Load(File.ReadAllBytes(outputPath));
            var programType = assembly.GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var tokenize = programType.GetMethod(
                    "TokenizeMetadataWithIndentationInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeMetadataWithIndentationInto.");
            var parseSig = programType.GetMethod(
                    "ParseFunctionSignatureInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ParseFunctionSignatureInto.");

            string[] functions =
            {
                "func a(): int { }",
                "func noRet() { }",
                "func one(x: int): string { }",
                "func two(x: int, y: string): bool { }",
                "func gen(items: List<int>): Dictionary<string, int> { }",
                "func nul(x: int?, y: string[]): void { }",
                "func uni(x: int | string): int { }",
                "func arr(data: int[][]): List<int>[] { }",
                "func byref(p: &int): void { }",
                "func mods(ref x: int, out y: string): void { }",
                "func ext(this self: int): int { }",
                "func deflt(x: int = 5, y: string): int { }",
                "func gfn(x: List<int | string>, y: A.B.C): Dictionary<string, List<int>> { }",
            };
            foreach (var fn in functions)
                AssertFunctionSignatureLikeProduction(fn, tokenize, parseSig);

            // Malformed signatures must REFUSE cleanly (-1), never silently mis-parse. A default value with
            // unbalanced brackets would otherwise let the depth tracking consume past the parameter list's
            // `)`; the post-parameter terminator check rejects it. (Full error recovery is deferred.)
            foreach (var bad in new[]
            {
                "func bad1(x: int = {): void { }",
                "func bad2(x: int = (, y: int): void { }",
                "func bad3(x: int = [): int { }",
            })
                AssertFunctionSignatureRefused(bad, tokenize, parseSig);

            // Real-corpus pin: every top-level function in the dogfood kernels whose entire signature stays
            // within the supported type forms (Simple/Generic/Array/Nullable/Union/ByRef). Functions with a
            // deferred form (tuple/Func/scoped/lifetime/`->`) in their signature are skipped and counted.
            var verified = 0;
            var skipped = 0;
            foreach (var file in Directory
                .EnumerateFiles(Path.Combine(projectRoot, "CompilerServices"), "*.nl")
                .OrderBy(p => p, StringComparer.Ordinal))
            {
                var (v, s) = VerifyDogfoodFileFunctionSignatures(File.ReadAllText(file), file, tokenize, parseSig);
                verified += v;
                skipped += s;
            }
            Assert.True(verified > 100, $"Expected to verify >100 real dogfood function signatures, only verified {verified} (skipped {skipped}).");
        }
        finally
        {
            if (File.Exists(outputPath)) File.Delete(outputPath);
        }
    }

    private static (int Count, int[] Kinds, int[] Starts, int[] ValueLengths, string Source)
        TokenizeSourceViaKernel(string source, MethodInfo tokenize)
    {
        var capacity = 3 * (source.Length + 1) + 8;
        var kinds = new int[capacity];
        var starts = new int[capacity];
        var valueLengths = new int[capacity];
        var lines = new int[capacity];
        var columns = new int[capacity];
        var count = (int)(tokenize.Invoke(
            null,
            new object[] { source, kinds, starts, valueLengths, lines, columns }) ?? -1);

        // The C# Parser drops every Newline token before parsing (Parser.cs:24-26); N# is not
        // newline-significant at the parse level (indentation was already turned into virtual braces by the
        // lexer). Compact the stream identically so multi-line signatures parse. Byte offsets are unchanged
        // since removing tokens does not move source positions.
        var ck = new int[count];
        var cs = new int[count];
        var cv = new int[count];
        var n = 0;
        for (var i = 0; i < count; i++)
        {
            if (kinds[i] == 136) continue;
            ck[n] = kinds[i];
            cs[n] = starts[i];
            cv[n] = valueLengths[i];
            n++;
        }

        return (n, ck, cs, cv, source);
    }

    private static void AssertFunctionSignatureLikeProduction(string funcSource, MethodInfo tokenize, MethodInfo parseSig)
    {
        var tokens = new Lexer(funcSource, "fn.nl").Tokenize();
        var compilationUnit = new Parser(tokens, "fn.nl").ParseCompilationUnit().CompilationUnit;
        Assert.NotNull(compilationUnit);
        var fn = compilationUnit!.Declarations.OfType<FunctionDeclaration>().Single();

        var (count, kinds, starts, valueLengths, source) = TokenizeSourceViaKernel(funcSource, tokenize);
        var funcIndex = FirstTopLevelFuncIndex(kinds, count);
        Assert.True(funcIndex >= 0, $"Could not locate `func` keyword for '{funcSource}'.");

        VerifyFunctionSignature(source, kinds, starts, valueLengths, count, funcIndex, fn, parseSig, funcSource);
    }

    private static void AssertFunctionSignatureRefused(string funcSource, MethodInfo tokenize, MethodInfo parseSig)
    {
        var (count, kinds, starts, valueLengths, _) = TokenizeSourceViaKernel(funcSource, tokenize);
        var funcIndex = FirstTopLevelFuncIndex(kinds, count);
        Assert.True(funcIndex >= 0, $"Could not locate `func` keyword for '{funcSource}'.");

        var cap = count + 1;
        var paramCount = (int)(parseSig.Invoke(
            null,
            new object[]
            {
                kinds, starts, valueLengths, count, funcIndex,
                new int[cap], new int[cap], new int[cap], new int[cap], new int[cap], new int[cap], new int[cap], new int[cap],
                new int[cap], new int[cap], new int[cap], new int[5],
            }) ?? -2);

        Assert.True(paramCount == -1, $"Kernel should refuse malformed signature '{funcSource}' with -1, got {paramCount}.");
    }

    private static (int Verified, int Skipped) VerifyDogfoodFileFunctionSignatures(
        string source, string file, MethodInfo tokenize, MethodInfo parseSig)
    {
        var tokens = new Lexer(source, file).Tokenize();
        var compilationUnit = new Parser(tokens, file).ParseCompilationUnit().CompilationUnit;
        Assert.NotNull(compilationUnit);
        var funcs = compilationUnit!.Declarations.OfType<FunctionDeclaration>().ToList();

        var (count, kinds, starts, valueLengths, src) = TokenizeSourceViaKernel(source, tokenize);
        var funcIndices = TopLevelFuncIndices(kinds, count);

        // The dogfood kernels are flat top-level functions, so each depth-0 `func` keyword corresponds 1:1
        // (in order) with a FunctionDeclaration.
        Assert.Equal(funcs.Count, funcIndices.Count);

        var verified = 0;
        var skipped = 0;
        for (var i = 0; i < funcs.Count; i++)
        {
            if (!FunctionSignatureFullySupported(funcs[i]))
            {
                skipped++;
                continue;
            }

            VerifyFunctionSignature(src, kinds, starts, valueLengths, count, funcIndices[i], funcs[i], parseSig, $"{file}#{funcs[i].Name}");
            verified++;
        }

        return (verified, skipped);
    }

    private static void VerifyFunctionSignature(
        string source, int[] kinds, int[] starts, int[] valueLengths, int count, int funcIndex,
        FunctionDeclaration expected, MethodInfo parseSig, string label)
    {
        var cap = count + 1;
        var k = new int[cap];
        var ns = new int[cap];
        var nl = new int[cap];
        var cs = new int[cap];
        var cc = new int[cap];
        var ci = new int[cap];
        var ss = new int[cap];
        var sl = new int[cap];
        var paramNameStarts = new int[cap];
        var paramNameLengths = new int[cap];
        var paramTypeRoots = new int[cap];
        var res = new int[5];

        var paramCount = (int)(parseSig.Invoke(
            null,
            new object[]
            {
                kinds, starts, valueLengths, count, funcIndex,
                k, ns, nl, cs, cc, ci, ss, sl,
                paramNameStarts, paramNameLengths, paramTypeRoots, res,
            }) ?? -2);

        Assert.True(paramCount >= 0, $"Kernel refused function signature for '{label}'.");
        Assert.Equal(expected.Parameters.Count, paramCount);
        Assert.Equal(expected.Parameters.Count, res[0]);

        var actualName = res[3] < 0 ? null : source.Substring(res[3], res[4]);
        Assert.Equal(expected.Name, actualName);

        for (var p = 0; p < expected.Parameters.Count; p++)
        {
            var param = expected.Parameters[p];
            var actualParamName = source.Substring(paramNameStarts[p], paramNameLengths[p]);
            Assert.True(param.Name == actualParamName, $"Param {p} name mismatch for '{label}': expected '{param.Name}', got '{actualParamName}'.");
            AssertTypeRefNode(param.Type, paramTypeRoots[p], k, ns, nl, cs, cc, ci, source, $"{label} param {p}");
        }

        if (expected.ReturnType == null)
        {
            Assert.True(res[1] == -1, $"Expected no return type for '{label}', kernel returned root {res[1]}.");
        }
        else
        {
            Assert.True(res[1] >= 0, $"Expected a return type for '{label}', kernel returned {res[1]}.");
            AssertTypeRefNode(expected.ReturnType, res[1], k, ns, nl, cs, cc, ci, source, $"{label} return");
        }
    }

    private static int FirstTopLevelFuncIndex(int[] kinds, int count)
    {
        var list = TopLevelFuncIndices(kinds, count);
        return list.Count > 0 ? list[0] : -1;
    }

    // Depth-0 `func` keyword (TokenType.Func == 7) token indices, tracking brace/bracket/paren depth so a
    // nested function (a method inside a type body) is not mistaken for a top-level declaration.
    private static List<int> TopLevelFuncIndices(int[] kinds, int count)
    {
        var result = new List<int>();
        var brace = 0;
        var bracket = 0;
        var paren = 0;
        for (var i = 0; i < count; i++)
        {
            switch (kinds[i])
            {
                case 129: brace++; break;
                case 130: if (brace > 0) brace--; break;
                case 131: bracket++; break;
                case 132: if (bracket > 0) bracket--; break;
                case 127: paren++; break;
                case 128: if (paren > 0) paren--; break;
                case 7:
                    if (brace == 0 && bracket == 0 && paren == 0) result.Add(i);
                    break;
            }
        }

        return result;
    }

    private static bool FunctionSignatureFullySupported(FunctionDeclaration fn)
    {
        foreach (var p in fn.Parameters)
        {
            if (p.IsScoped || p.Lifetime != null) return false;
            if (!IsSupportedTypeForm(p.Type)) return false;
        }

        return fn.ReturnType == null || IsSupportedTypeForm(fn.ReturnType);
    }

    private static bool IsSupportedTypeForm(TypeReference type) => type switch
    {
        SimpleTypeReference => true,
        GenericTypeReference g => g.TypeArguments.All(IsSupportedTypeForm),
        ArrayTypeReference a => IsSupportedTypeForm(a.ElementType),
        NullableTypeReference n => IsSupportedTypeForm(n.InnerType),
        UnionTypeReference u => u.Arms.All(IsSupportedTypeForm),
        ByRefTypeReference b => IsSupportedTypeForm(b.InnerType),
        _ => false,
    };

    // Parser slices 10-15, 19: the EXPRESSION kernel. ParseExpressionNodesInto (ParserExpressions.nl) parses
    // primary expressions (slice 10), the postfix chain -- member/index (slice 11), calls (slice 12) --
    // prefix unary (slice 13), the full left-associative binary precedence chain (slice 14), the expression
    // top -- ternary + right-associative assignment (slice 15) -- and `new <type>(args)` (slice 19, composing
    // the type kernel via the unified st) into a columnar node table, pinned against the production parser's
    // Expression AST (extracted from a `return <expr>` statement), including operator precedence and
    // associativity. Deferred: is/as, range, lambdas, new[size]/new{init}, and the remaining primaries.
    [Fact]
    public void Parser_Expression_MatchesProductionParser()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(
            Path.GetTempPath(),
            $"NSharpLang.Compiler.Dogfood.ParserExpr.{Guid.NewGuid():N}.dll");

        try
        {
            var result = new MultiFileCompiler(projectRoot, config)
                .CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);
            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(e => e.Message)));

            var assembly = Assembly.Load(File.ReadAllBytes(outputPath));
            var programType = assembly.GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var tokenize = programType.GetMethod(
                    "TokenizeMetadataWithIndentationInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeMetadataWithIndentationInto.");
            var parseExpr = programType.GetMethod(
                    "ParseExpressionNodesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ParseExpressionNodesInto.");

            string[] expressions =
            {
                "5", "0", "42", "3.14", "0.5", "'a'", "'\\n'", "\"hi\"", "\"\"",
                "true", "false", "null",
                "x", "value", "count",
                "(5)", "(x)", "((42))", "(true)", "(null)", "(\"hi\")",
                // Postfix (slice 11): member access + index access chains.
                "x.y", "a.b.c", "obj.Length", "arr[i]", "arr[0]", "m[key]",
                "a.b[c]", "arr[i].field", "a[b][c]", "(x).y", "x.y[z].w", "data[i].next.value",
                // Calls (slice 12): variable-arity arguments via the arg-stack.
                "f()", "g(x)", "h(a, b)", "obj.method(x)", "a.b.c(1, 2, 3)", "arr[i].foo(y)",
                "f(g(x))", "f(a)(b)", "f(x)[i]", "compute(a, b, c).result", "outer(inner(z), w)",
                // Unary prefix (slice 13): wraps a recursively-parsed operand; composes with postfix.
                "-x", "!flag", "~bits", "-arr[i]", "!a.b", "-f(x)", "++i", "--count", "!!x", "-(value)",
                // Binary precedence chain (slice 14): precedence + left-associativity + composition.
                "a + b", "a - b - c", "1 + 2 * 3", "a * b + c", "i < count", "x == y", "a != b",
                "a && b || c", "x | y & z", "a == b && c != d", "i < count && tokenKinds[pos] == 102",
                "a + b * c - d / e", "n % 2 == 0", "left << 4 | right", "(a + b) * c", "f(x) + g(y) * 2",
                "arr[i] + arr[j]", "a.b.c + d.e", "-a * b", "!found && i < n",
                // Expression top (slice 15): ternary + right-associative assignment.
                "a ? b : c", "x > 0 ? x : -x", "a ? b : c ? d : e", "x = 5", "a = b = c",
                "arr[i] = value", "total = total + n", "count += 1", "x ??= y", "flag = a && b",
                "result = cond ? f(x) : g(y)",
                // New expressions (slice 19): composes the type kernel (element type) + expr kernel (args).
                "new int[](n)", "new char[](length + 1)", "new Foo()", "new Bar(a, b)",
                "new List<int>()", "buffer = new int[](count + 1)", "f(new int[](k))",
                // Nested generics in the new-type exercise the >> split via the shared st (splitGreaterDepth);
                // two news in sequence pin that the type parse leaves no leaked state behind.
                "new List<List<int>>()", "new Dictionary<string, List<int>>(cap)",
                "new List<List<int>>() == new List<int>()",
            };
            foreach (var e in expressions)
                AssertPrimaryExpressionLikeProduction(e, tokenize, parseExpr);

            // Refused (-1): deferred primaries / non-primary leads / tuples / named & ref-out call args.
            foreach (var bad in new[] { "(1, 2)", "(x: 1)", "+5", ".x", ")", "f(x: 1)", "g(ref y)" })
                AssertExpressionRefused(bad, tokenize, parseExpr);
        }
        finally
        {
            if (File.Exists(outputPath)) File.Delete(outputPath);
        }
    }

    private static (int Count, int[] Kinds, int[] Starts, int[] ValueLengths, int Start, string Source)
        TokenizeReturnExpression(string exprString, MethodInfo tokenize)
    {
        var (count, kinds, starts, valueLengths, source) =
            TokenizeSourceViaKernel("func e() { return " + exprString + " }", tokenize);
        // The expression begins one token after the `return` keyword (TokenType.Return == 29).
        var start = -1;
        for (var i = 0; i < count; i++)
        {
            if (kinds[i] == 29) { start = i + 1; break; }
        }
        Assert.True(start > 0, $"Could not locate `return` for expression '{exprString}'.");
        return (count, kinds, starts, valueLengths, start, source);
    }

    private static void AssertPrimaryExpressionLikeProduction(string exprString, MethodInfo tokenize, MethodInfo parseExpr)
    {
        var tokens = new Lexer("func e() { return " + exprString + " }", "e.nl").Tokenize();
        var compilationUnit = new Parser(tokens, "e.nl").ParseCompilationUnit().CompilationUnit;
        Assert.NotNull(compilationUnit);
        var fn = compilationUnit!.Declarations.OfType<FunctionDeclaration>().Single();
        var body = fn.Body;
        Assert.True(body != null, $"No body for '{exprString}'.");
        var ret = body!.Statements.OfType<ReturnStatement>().Single();
        Assert.True(ret.Value != null, $"No return value for '{exprString}'.");

        var (count, kinds, starts, valueLengths, start, source) = TokenizeReturnExpression(exprString, tokenize);

        var cap = count + 1;
        var k = new int[cap];
        var vs = new int[cap];
        var vl = new int[cap];
        var cstart = new int[cap];
        var ccount = new int[cap];
        var ci = new int[cap];
        var ss = new int[cap];
        var sl = new int[cap];
        var res = new int[2];
        var nodeCount = (int)(parseExpr.Invoke(
            null,
            new object[] { kinds, starts, valueLengths, count, start, k, vs, vl, cstart, ccount, ci, ss, sl, res }) ?? -2);

        Assert.True(nodeCount > 0, $"Kernel refused primary expression '{exprString}'.");
        var root = res[0];
        Assert.Equal(nodeCount - 1, root);

        AssertExprNode(ret.Value!, root, k, vs, vl, cstart, ccount, ci, source, exprString);

        // Root span equals the expression text; full consumption lands on the block's `}` (130).
        Assert.Equal(exprString, source.Substring(ss[root], sl[root]));
        Assert.True(res[1] < count && kinds[res[1]] == 130, $"Expression '{exprString}' did not consume to the block close.");

        // Determinism.
        var (n2, k2, vs2, vl2, cstart2, ccount2, ci2, ss2, sl2, res2) = InvokeParseExpr(parseExpr, kinds, starts, valueLengths, count, start);
        Assert.Equal(nodeCount, n2);
        for (var i = 0; i < nodeCount; i++)
        {
            Assert.True(
                k[i] == k2[i] && vs[i] == vs2[i] && vl[i] == vl2[i] && cstart[i] == cstart2[i] &&
                ccount[i] == ccount2[i] && ci[i] == ci2[i] && ss[i] == ss2[i] && sl[i] == sl2[i],
                $"Non-deterministic expression node table at {i} for '{exprString}'.");
        }
        Assert.Equal(res[0], res2[0]);
        Assert.Equal(res[1], res2[1]);
    }

    private static void AssertExpressionRefused(string exprString, MethodInfo tokenize, MethodInfo parseExpr)
    {
        var (count, kinds, starts, valueLengths, start, _) = TokenizeReturnExpression(exprString, tokenize);
        var (nodeCount, _, _, _, _, _, _, _, _, _) = InvokeParseExpr(parseExpr, kinds, starts, valueLengths, count, start);
        Assert.True(nodeCount == -1, $"Kernel should refuse deferred expression '{exprString}' with -1, got {nodeCount}.");
    }

    private static (int NodeCount, int[] Kinds, int[] ValueStarts, int[] ValueLengths, int[] ChildStart,
        int[] ChildCount, int[] ChildIndices, int[] SpanStarts, int[] SpanLengths, int[] Result)
        InvokeParseExpr(MethodInfo parseExpr, int[] kinds, int[] starts, int[] valueLengths, int count, int start)
    {
        var cap = count + 1;
        var k = new int[cap];
        var vs = new int[cap];
        var vl = new int[cap];
        var cstart = new int[cap];
        var ccount = new int[cap];
        var ci = new int[cap];
        var ss = new int[cap];
        var sl = new int[cap];
        var res = new int[2];
        var nodeCount = (int)(parseExpr.Invoke(
            null,
            new object[] { kinds, starts, valueLengths, count, start, k, vs, vl, cstart, ccount, ci, ss, sl, res }) ?? -2);
        return (nodeCount, k, vs, vl, cstart, ccount, ci, ss, sl, res);
    }

    private static void AssertExprNode(
        Expression expected, int idx,
        int[] kinds, int[] valueStarts, int[] valueLengths, int[] childStart, int[] childCount, int[] childIndices,
        string source, string label)
    {
        switch (expected)
        {
            case IntLiteralExpression e:
                Assert.True(kinds[idx] == 0, $"Expected Int (0) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(e.Value, source.Substring(valueStarts[idx], valueLengths[idx]));
                break;
            case FloatLiteralExpression e:
                Assert.True(kinds[idx] == 1, $"Expected Float (1) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(e.Value, source.Substring(valueStarts[idx], valueLengths[idx]));
                break;
            case CharLiteralExpression:
                Assert.True(kinds[idx] == 2, $"Expected Char (2) at node {idx} for '{label}', got {kinds[idx]}.");
                break;
            case StringLiteralExpression:
                Assert.True(kinds[idx] == 3, $"Expected String (3) at node {idx} for '{label}', got {kinds[idx]}.");
                break;
            case BoolLiteralExpression e:
                Assert.True(kinds[idx] == 4, $"Expected Bool (4) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(e.Value, source.Substring(valueStarts[idx], valueLengths[idx]) == "true");
                break;
            case NullLiteralExpression:
                Assert.True(kinds[idx] == 5, $"Expected Null (5) at node {idx} for '{label}', got {kinds[idx]}.");
                break;
            case IdentifierExpression e:
                Assert.True(kinds[idx] == 6, $"Expected Identifier (6) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(e.Name, source.Substring(valueStarts[idx], valueLengths[idx]));
                break;
            case ParenthesizedExpression e:
                Assert.True(kinds[idx] == 7, $"Expected Parenthesized (7) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(1, childCount[idx]);
                AssertExprNode(e.Inner, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                break;
            case MemberAccessExpression e:
                Assert.True(kinds[idx] == 8, $"Expected MemberAccess (8) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.False(e.IsNullConditional, $"Slice-11 kernel only handles non-null-conditional '.' for '{label}'.");
                Assert.Equal(e.MemberName, source.Substring(valueStarts[idx], valueLengths[idx]));
                Assert.Equal(1, childCount[idx]);
                AssertExprNode(e.Object, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                break;
            case IndexAccessExpression e:
                Assert.True(kinds[idx] == 10, $"Expected IndexAccess (10) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.False(e.IsNullConditional, $"Slice-11 kernel only handles non-null-conditional '[' for '{label}'.");
                Assert.Equal(2, childCount[idx]);
                AssertExprNode(e.Object, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                AssertExprNode(e.Index, childIndices[childStart[idx] + 1], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                break;
            case UnaryExpression e:
                Assert.True(kinds[idx] == 11, $"Expected Unary (11) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(UnaryOperatorText(e.Operator), source.Substring(valueStarts[idx], valueLengths[idx]));
                Assert.Equal(1, childCount[idx]);
                AssertExprNode(e.Operand, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                break;
            case BinaryExpression e:
                Assert.True(kinds[idx] == 12, $"Expected Binary (12) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(BinaryOperatorText(e.Operator), source.Substring(valueStarts[idx], valueLengths[idx]));
                Assert.Equal(2, childCount[idx]);
                AssertExprNode(e.Left, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                AssertExprNode(e.Right, childIndices[childStart[idx] + 1], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                break;
            case TernaryExpression e:
                Assert.True(kinds[idx] == 13, $"Expected Ternary (13) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(3, childCount[idx]);
                AssertExprNode(e.Condition, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                AssertExprNode(e.ThenExpression, childIndices[childStart[idx] + 1], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                AssertExprNode(e.ElseExpression, childIndices[childStart[idx] + 2], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                break;
            case AssignmentExpression e:
                Assert.True(kinds[idx] == 14, $"Expected Assignment (14) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(AssignmentOperatorText(e.Operator), source.Substring(valueStarts[idx], valueLengths[idx]));
                Assert.Equal(2, childCount[idx]);
                AssertExprNode(e.Target, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                AssertExprNode(e.Value, childIndices[childStart[idx] + 1], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                break;
            case NewExpression e:
                Assert.True(kinds[idx] == 15, $"Expected New (15) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.True(e.Type != null, $"Slice-19 kernel only handles typed `new <type>(args)` for '{label}'.");
                Assert.True(e.Initializer == null, $"Slice-19 kernel does not handle object initializers for '{label}'.");
                Assert.True(e.ArrayLengthExpression == null, $"Slice-19 kernel does not handle `new type[size]` for '{label}'.");
                Assert.Equal(1 + e.ConstructorArguments.Count, childCount[idx]);
                // child[0] is the constructed TYPE (a type-kernel subtree); the rest are the constructor args.
                AssertTypeRefNode(e.Type!, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                for (var ai = 0; ai < e.ConstructorArguments.Count; ai++)
                {
                    Assert.True(e.ConstructorArguments[ai].Name == null && e.ConstructorArguments[ai].Modifier == ArgumentModifier.None, $"Slice-19 kernel handles positional constructor args only for '{label}'.");
                    AssertExprNode(e.ConstructorArguments[ai].Value, childIndices[childStart[idx] + 1 + ai], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                }
                break;
            case CallExpression e:
                Assert.True(kinds[idx] == 9, $"Expected Call (9) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.True(e.TypeArguments == null || e.TypeArguments.Count == 0, $"Slice-12 kernel does not handle generic calls for '{label}'.");
                Assert.Equal(1 + e.Arguments.Count, childCount[idx]);
                AssertExprNode(e.Callee, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                for (var ai = 0; ai < e.Arguments.Count; ai++)
                {
                    Assert.True(e.Arguments[ai].Name == null && e.Arguments[ai].Modifier == ArgumentModifier.None, $"Slice-12 kernel handles positional args only for '{label}'.");
                    AssertExprNode(e.Arguments[ai].Value, childIndices[childStart[idx] + 1 + ai], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                }
                break;
            default:
                Assert.Fail($"Unexpected production expression node {expected.GetType().Name} for '{label}' (out of slice-10/11 scope).");
                break;
        }
    }

    private static string UnaryOperatorText(UnaryOperator op) => op switch
    {
        UnaryOperator.Negate => "-",
        UnaryOperator.Not => "!",
        UnaryOperator.BitwiseNot => "~",
        UnaryOperator.PreIncrement => "++",
        UnaryOperator.PreDecrement => "--",
        UnaryOperator.IndexFromEnd => "^",
        _ => "<unsupported>", // PostIncrement/PostDecrement are postfix -- not produced by the slice-13 kernel
    };

    private static string BinaryOperatorText(BinaryOperator op) => op switch
    {
        BinaryOperator.Add => "+",
        BinaryOperator.Subtract => "-",
        BinaryOperator.Multiply => "*",
        BinaryOperator.Divide => "/",
        BinaryOperator.Modulo => "%",
        BinaryOperator.Equal => "==",
        BinaryOperator.NotEqual => "!=",
        BinaryOperator.Less => "<",
        BinaryOperator.LessOrEqual => "<=",
        BinaryOperator.Greater => ">",
        BinaryOperator.GreaterOrEqual => ">=",
        BinaryOperator.And => "&&",
        BinaryOperator.Or => "||",
        BinaryOperator.BitwiseAnd => "&",
        BinaryOperator.BitwiseOr => "|",
        BinaryOperator.BitwiseXor => "^",
        BinaryOperator.LeftShift => "<<",
        BinaryOperator.RightShift => ">>",
        BinaryOperator.NullCoalesce => "??",
        _ => "<unsupported>", // Range is deferred (not produced by the slice-14 binary chain)
    };

    private static string AssignmentOperatorText(AssignmentOperator op) => op switch
    {
        AssignmentOperator.Assign => "=",
        AssignmentOperator.AddAssign => "+=",
        AssignmentOperator.SubtractAssign => "-=",
        AssignmentOperator.MultiplyAssign => "*=",
        AssignmentOperator.DivideAssign => "/=",
        AssignmentOperator.NullCoalesceAssign => "??=",
        _ => "<unsupported>",
    };

    // Parser slice 20: real-corpus WHOLE-BODY pin -- the capstone dogfood validation. Runs the full N#
    // front-end statement kernel (which composes the type + expression + new kernels over the shared node
    // table) on every dogfood compiler-kernel function body whose statements stay within the supported forms,
    // and compares the resulting statement tree structurally to the C# parser's FunctionDeclaration.Body.
    // This is the N# parser parsing the actual compiler kernels and matching the production parser. Bodies
    // with any not-yet-supported statement/expression form are skipped and counted (never silently passed).
    [Fact]
    public void Parser_RealCorpusFunctionBodies_MatchProductionParser()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(Path.GetTempPath(), $"NSharpLang.Compiler.Dogfood.RealBody.{Guid.NewGuid():N}.dll");

        try
        {
            var result = new MultiFileCompiler(projectRoot, config)
                .CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);
            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(e => e.Message)));
            var programType = Assembly.Load(File.ReadAllBytes(outputPath)).GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var tokenize = programType.GetMethod("TokenizeMetadataWithIndentationInto", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;
            var parseStmt = programType.GetMethod("ParseStatementNodesInto", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;

            var verified = 0;
            var skipped = 0;
            foreach (var file in Directory
                .EnumerateFiles(Path.Combine(projectRoot, "CompilerServices"), "*.nl")
                .OrderBy(p => p, StringComparer.Ordinal))
            {
                var src = File.ReadAllText(file);
                var cu = new Parser(new Lexer(src, file).Tokenize(), file).ParseCompilationUnit().CompilationUnit;
                if (cu == null) continue;
                var funcs = cu.Declarations.OfType<FunctionDeclaration>().ToList();

                var (count, kinds, starts, valueLengths, source) = TokenizeSourceViaKernel(src, tokenize);
                var funcIndices = TopLevelFuncIndices(kinds, count);
                if (funcIndices.Count != funcs.Count) { skipped += funcs.Count; continue; }

                for (var fi = 0; fi < funcs.Count; fi++)
                {
                    var body = funcs[fi].Body;
                    if (body == null || !IsSupportedStatement(body)) { skipped++; continue; }

                    // The body block opens at the first `{` (LeftBrace 129) after the func keyword; the
                    // signature contains no braces in the dogfood corpus.
                    var bodyBrace = -1;
                    for (var t = funcIndices[fi] + 1; t < count; t++)
                    {
                        if (kinds[t] == 129) { bodyBrace = t; break; }
                    }
                    if (bodyBrace < 0) { skipped++; continue; }

                    var cap = count + 1;
                    var k = new int[cap]; var vs = new int[cap]; var vl = new int[cap];
                    var cs = new int[cap]; var cc = new int[cap]; var ci = new int[cap];
                    var ss = new int[cap]; var sl = new int[cap]; var res = new int[2];
                    var nodeCount = (int)(parseStmt.Invoke(null, new object[] { kinds, starts, valueLengths, count, bodyBrace, k, vs, vl, cs, cc, ci, ss, sl, res }) ?? -2);
                    Assert.True(nodeCount > 0, $"Kernel refused supported real body {file}#{funcs[fi].Name}.");
                    AssertStmtNode(body, res[0], k, vs, vl, cs, cc, ci, source, $"{file}#{funcs[fi].Name}");
                    verified++;
                }
            }

            Assert.True(verified > 30, $"Expected to verify >30 real dogfood function bodies, only verified {verified} (skipped {skipped}).");
        }
        finally
        {
            if (File.Exists(outputPath)) File.Delete(outputPath);
        }
    }

    private static bool IsSupportedStatement(Statement s) => s switch
    {
        ReturnStatement r => r.Value == null || IsSupportedExpr(r.Value),
        BreakStatement or ContinueStatement => true,
        ExpressionStatement e => IsSupportedExpr(e.Expression),
        // Only the `:=` shorthand (no type, with initializer) is supported by the slice-16 statement kernel.
        VariableDeclarationStatement v => v.Type == null && v.Initializer != null && v.Kind == VariableKind.Let && IsSupportedExpr(v.Initializer),
        BlockStatement b => b.Statements.All(IsSupportedStatement),
        WhileStatement w => IsSupportedExpr(w.Condition) && IsSupportedStatement(w.Body),
        IfStatement i => IsSupportedExpr(i.Condition) && IsSupportedStatement(i.ThenStatement) && (i.ElseStatement == null || IsSupportedStatement(i.ElseStatement)),
        _ => false,
    };

    // Slice 22: MATERIALIZATION — the routing bridge. ColumnarAstMaterializer turns the N# front-end's
    // columnar node table into the production C# AST records. This proves the columnar parser output is
    // convertible to the CompilationUnit/Expression tree the rest of the compiler consumes (the prerequisite
    // for routing the N# front-end into production and deleting the C# Parser bridge). Verified by
    // materializing each corpus expression's columnar output and confirming it is STRUCTURALLY identical
    // (ignoring source positions, which differ for operator nodes) to the C# parser's Expression.
    [Fact]
    public void Materializer_Expression_MatchesProductionParserAst()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(Path.GetTempPath(), $"NSharpLang.Compiler.Dogfood.Materializer.{Guid.NewGuid():N}.dll");
        try
        {
            var result = new MultiFileCompiler(projectRoot, config).CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);
            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(e => e.Message)));
            var programType = Assembly.Load(File.ReadAllBytes(outputPath)).GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var tokenize = programType.GetMethod("TokenizeMetadataWithIndentationInto", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;
            var parseExpr = programType.GetMethod("ParseExpressionNodesInto", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;

            string[] expressions =
            {
                "5", "3.14", "true", "null", "x", "\"hi\"", "'a'",
                "a + b * c", "i < count && tokenKinds[pos] == 102", "arr[i].field", "f(g(x), y)",
                "-arr[i]", "!found", "a ? b : c", "total = total + 1", "x ??= y",
                "new int[](count + 1)", "obj.method(a, b)", "data[i].next.value", "(a + b) * c",
                // Hard casts (must NOT be mistaken for parenthesized expressions).
                "(int)left", "(char)(a + b)", "(int)data[i]", "(int)left - (int)right",
            };
            foreach (var e in expressions)
            {
                var src = "func e() { return " + e + " }";
                var cu = new Parser(new Lexer(src, "m.nl").Tokenize(), "m.nl").ParseCompilationUnit().CompilationUnit;
                var expected = cu!.Declarations.OfType<FunctionDeclaration>().Single().Body!.Statements.OfType<ReturnStatement>().Single().Value!;

                var (count, kinds, starts, valueLengths, start, source) = TokenizeReturnExpression(e, tokenize);
                var (nodeCount, k, vs, vl, cstart, ccount, ci, ss, _, res) = InvokeParseExpr(parseExpr, kinds, starts, valueLengths, count, start);
                Assert.True(nodeCount > 0, $"kernel refused '{e}'");

                var materialized = new ColumnarAstMaterializer(k, vs, vl, cstart, ccount, ci, ss, source).MaterializeExpression(res[0]);
                Assert.Equal(StructuralJson(expected), StructuralJson(materialized));
            }

            // Whole-body materialization: every dogfood function body within the supported forms is parsed by
            // the statement kernel, materialized into a C# BlockStatement, and structurally compared to the
            // production parser's FunctionDeclaration.Body. This is the columnar-front-end -> production-AST
            // bridge working on real compiler code.
            var parseStmt = programType.GetMethod("ParseStatementNodesInto", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;
            var bodiesVerified = 0;
            foreach (var file in Directory.EnumerateFiles(Path.Combine(projectRoot, "CompilerServices"), "*.nl").OrderBy(p => p, StringComparer.Ordinal))
            {
                var src = File.ReadAllText(file);
                var cu = new Parser(new Lexer(src, file).Tokenize(), file).ParseCompilationUnit().CompilationUnit;
                if (cu == null) continue;
                var funcs = cu.Declarations.OfType<FunctionDeclaration>().ToList();
                var (count, kinds, starts, valueLengths, source) = TokenizeSourceViaKernel(src, tokenize);
                var funcIndices = TopLevelFuncIndices(kinds, count);
                if (funcIndices.Count != funcs.Count) continue;

                for (var fi = 0; fi < funcs.Count; fi++)
                {
                    var body = funcs[fi].Body;
                    if (body == null || !IsSupportedStatement(body)) continue;
                    var bodyBrace = -1;
                    for (var t = funcIndices[fi] + 1; t < count; t++) { if (kinds[t] == 129) { bodyBrace = t; break; } }
                    if (bodyBrace < 0) continue;

                    var cap = count + 1;
                    var k = new int[cap]; var vs = new int[cap]; var vl = new int[cap];
                    var cs = new int[cap]; var cc = new int[cap]; var ci = new int[cap];
                    var sst = new int[cap]; var sl = new int[cap]; var res = new int[2];
                    var nodeCount = (int)(parseStmt.Invoke(null, new object[] { kinds, starts, valueLengths, count, bodyBrace, k, vs, vl, cs, cc, ci, sst, sl, res }) ?? -2);
                    Assert.True(nodeCount > 0, $"kernel refused supported body {file}#{funcs[fi].Name}");

                    var materializedBody = new ColumnarAstMaterializer(k, vs, vl, cs, cc, ci, sst, source).MaterializeStatement(res[0]);
                    Assert.True(
                        StructuralJson(body) == StructuralJson(materializedBody),
                        $"Materialized body diverges from production AST for {file}#{funcs[fi].Name}");
                    bodiesVerified++;
                }
            }
            Assert.True(bodiesVerified > 30, $"Expected to materialize >30 real dogfood bodies, only did {bodiesVerified}.");
        }
        finally
        {
            if (File.Exists(outputPath)) File.Delete(outputPath);
        }
    }

    // Slice 23: whole-FUNCTION-DECLARATION materialization. Composes the fnsig kernel (name + parameter
    // names/types + return type) and the statement kernel (body) and materializes both into a C#
    // FunctionDeclaration, then confirms the function's shape (name, parameter names + types, return type,
    // body) matches the production parser on every dogfood function within the supported forms. This is the
    // declaration-level unit the whole-file CompilationUnit materialization (and routing) is built from.
    [Fact]
    public void Materializer_FunctionDeclaration_MatchesProductionParserAst()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(Path.GetTempPath(), $"NSharpLang.Compiler.Dogfood.MatFn.{Guid.NewGuid():N}.dll");
        try
        {
            var result = new MultiFileCompiler(projectRoot, config).CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);
            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(e => e.Message)));
            var programType = Assembly.Load(File.ReadAllBytes(outputPath)).GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var tokenize = programType.GetMethod("TokenizeMetadataWithIndentationInto", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;
            var parseSig = programType.GetMethod("ParseFunctionSignatureInto", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;
            var parseStmt = programType.GetMethod("ParseStatementNodesInto", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;

            var verified = 0;
            foreach (var file in Directory.EnumerateFiles(Path.Combine(projectRoot, "CompilerServices"), "*.nl").OrderBy(p => p, StringComparer.Ordinal))
            {
                var src = File.ReadAllText(file);
                var cu = new Parser(new Lexer(src, file).Tokenize(), file).ParseCompilationUnit().CompilationUnit;
                if (cu == null) continue;
                var funcs = cu.Declarations.OfType<FunctionDeclaration>().ToList();
                var (count, kinds, starts, valueLengths, source) = TokenizeSourceViaKernel(src, tokenize);
                var funcIndices = TopLevelFuncIndices(kinds, count);
                if (funcIndices.Count != funcs.Count) continue;

                for (var fi = 0; fi < funcs.Count; fi++)
                {
                    var fn = funcs[fi];
                    if (!FunctionSignatureFullySupported(fn) || fn.Body == null || !IsSupportedStatement(fn.Body)) continue;

                    // --- signature kernel + materialize params/return from the fnsig node table ---
                    var cap = count + 1;
                    var sk = new int[cap]; var sns = new int[cap]; var snl = new int[cap]; var scs = new int[cap];
                    var scc = new int[cap]; var sci = new int[cap]; var sss = new int[cap]; var ssl = new int[cap];
                    var pNameStart = new int[cap]; var pNameLen = new int[cap]; var pTypeRoot = new int[cap]; var sres = new int[5];
                    var paramCount = (int)(parseSig.Invoke(null, new object[] { kinds, starts, valueLengths, count, funcIndices[fi], sk, sns, snl, scs, scc, sci, sss, ssl, pNameStart, pNameLen, pTypeRoot, sres }) ?? -2);
                    Assert.True(paramCount >= 0, $"fnsig refused {file}#{fn.Name}");
                    var sigMat = new ColumnarAstMaterializer(sk, sns, snl, scs, scc, sci, sss, source);
                    var materializedParams = new List<Parameter>();
                    for (var p = 0; p < paramCount; p++)
                        materializedParams.Add(new Parameter(source.Substring(pNameStart[p], pNameLen[p]), sigMat.MaterializeTypeReference(pTypeRoot[p]), null, false));
                    var materializedReturn = sres[1] >= 0 ? sigMat.MaterializeTypeReference(sres[1]) : null;
                    var materializedName = sres[3] < 0 ? null : source.Substring(sres[3], sres[4]);

                    // --- statement kernel + materialize the body ---
                    var bodyBrace = -1;
                    for (var t = funcIndices[fi] + 1; t < count; t++) { if (kinds[t] == 129) { bodyBrace = t; break; } }
                    Assert.True(bodyBrace > 0);
                    var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
                    var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap]; var bres = new int[2];
                    var bnodes = (int)(parseStmt.Invoke(null, new object[] { kinds, starts, valueLengths, count, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres }) ?? -2);
                    Assert.True(bnodes > 0, $"stmt kernel refused body {file}#{fn.Name}");
                    var materializedBody = (BlockStatement)new ColumnarAstMaterializer(bk, bvs, bvl, bcs, bcc, bci, bss, source).MaterializeStatement(bres[0]);

                    // --- focused shape parity vs the production FunctionDeclaration ---
                    Assert.Equal(fn.Name, materializedName);
                    Assert.Equal(fn.Parameters.Count, materializedParams.Count);
                    for (var p = 0; p < fn.Parameters.Count; p++)
                    {
                        Assert.Equal(fn.Parameters[p].Name, materializedParams[p].Name);
                        Assert.Equal(StructuralJson(fn.Parameters[p].Type), StructuralJson(materializedParams[p].Type));
                    }
                    Assert.Equal(StructuralJson(fn.ReturnType), StructuralJson(materializedReturn));
                    Assert.Equal(StructuralJson(fn.Body), StructuralJson(materializedBody));
                    verified++;
                }
            }
            Assert.True(verified > 30, $"Expected to materialize >30 real dogfood function declarations, only did {verified}.");
        }
        finally
        {
            if (File.Exists(outputPath)) File.Delete(outputPath);
        }
    }

    // Slice 24: PRODUCTION ROUTING. NSharpCompilerDogfoodAdapter.TryParseCompilationUnit assembles a whole
    // CompilationUnit from the N#-native front-end -- imports (declarations kernel) + every top-level function
    // (signature kernel + statement kernel + ColumnarAstMaterializer) -- and Parser.ParseCompilationUnit()
    // routes through it when NSHARP_PARSER_FRONTEND is enabled, falling back to the C# parser for any
    // unsupported form. This proves the routed CompilationUnit is structurally identical to the C# parser on
    // fully-supported sources (hand-built corpora plus any real dogfood file the front-end accepts).
    [Fact]
    public void Router_CompilationUnit_MatchesProductionParserAst()
    {
        // Corpora composed ENTIRELY of supported forms (imports + functions whose signatures and bodies the
        // front-end fully handles): these must route AND match the C# parser structurally.
        string[] supportedCorpora =
        {
            "import System\n\nfunc add(a: int, b: int): int {\n    return a + b\n}\n\nfunc neg(x: int): int {\n    return -x\n}\n",
            "func scan(data: int[], count: int): int {\n    total := 0\n    i := 0\n    while i < count {\n        if data[i] < 0 {\n            i = i + 1\n            continue\n        }\n        total = total + data[i]\n        i = i + 1\n    }\n    return total\n}\n",
            "import System.Text\n\nfunc choose(items: string[], flag: bool): string {\n    result := flag ? items[0] : items[1]\n    return result\n}\n",
            // Hard casts: (int)ident, (char)(expr), (int)indexed -- the form that distinguishes the cast branch
            // from a parenthesized expression.
            "func codes(left: char, text: string, i: int): int {\n    leftCode := (int)left\n    ch := (int)text[i]\n    c := (char)(leftCode + 1)\n    return leftCode\n}\n",
        };

        foreach (var src in supportedCorpora)
        {
            var (ok, routed) = RouteCompilationUnit(src, "corpus.nl");
            Assert.True(ok, $"Front-end declined a fully-supported corpus:\n{src}");
            Assert.NotNull(routed);
            var expected = CSharpCompilationUnit(src, "corpus.nl");
            Assert.Equal(StructuralJson(expected), StructuralJson(routed));
        }

        // Real dogfood files: the N# front-end parses 100% of its OWN systems source (the compiler-service
        // kernels) identically to the C# parser. Every CompilerServices/*.nl file must (a) route end-to-end
        // and (b) produce a CompilationUnit structurally identical to the C# parser. This is the self-host
        // parser milestone -- and the safety proof for routing the corpus: any divergence (a form the kernels
        // silently mis-parse instead of refusing) fails here, never reaches production.
        var repoRoot = FindRepoRoot();
        var servicesDir = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood", "CompilerServices");
        var files = Directory.EnumerateFiles(servicesDir, "*.nl").OrderBy(p => p, StringComparer.Ordinal).ToList();
        var routedDogfoodFiles = 0;
        foreach (var file in files)
        {
            var src = File.ReadAllText(file);
            var (ok, routed) = RouteCompilationUnit(src, file);
            Assert.True(ok, $"The N# front-end must fully route its own systems source, but declined {file}.");
            var expected = CSharpCompilationUnit(src, file);
            Assert.True(
                StructuralJson(expected) == StructuralJson(routed),
                $"Routed CompilationUnit diverges from the C# parser for {file}");
            routedDogfoodFiles++;
        }

        Assert.Equal(files.Count, routedDogfoodFiles);
        Assert.True(routedDogfoodFiles >= 30, $"Expected the full dogfood corpus to route; only {routedDogfoodFiles} did.");
    }

    // The routing orchestrator must DECLINE every form the front-end does not fully support -- returning false
    // so the C# parser (with its diagnostics) handles the file -- never a silently-wrong tree. These are all
    // valid N# the C# parser accepts; only the front-end declines.
    [Fact]
    public void Router_RefusesUnsupportedForms()
    {
        (string Label, string Source)[] unsupported =
        {
            ("class declaration", "class Box {\n    value: int\n}\n"),
            ("struct declaration", "struct Point {\n    x: int\n}\n"),
            ("enum declaration", "enum Color {\n    Red,\n    Green\n}\n"),
            ("package declaration", "package Demo.App\n\nfunc f(): int {\n    return 1\n}\n"),
            ("let-keyword declaration", "func f(): int {\n    let x = 0\n    return x\n}\n"),
            ("typed let declaration", "func f(): int {\n    let x: int = 0\n    return x\n}\n"),
            ("foreach loop", "func f(items: int[]): int {\n    foreach item in items {\n        return item\n    }\n    return 0\n}\n"),
        };

        foreach (var (label, src) in unsupported)
        {
            var (ok, routed) = RouteCompilationUnit(src, "unsupported.nl");
            Assert.False(ok, $"Front-end must DECLINE unsupported form ({label}); routing it risks a wrong tree.");
            Assert.Null(routed);
            // The C# parser still parses it (proving it is valid N#, not gibberish).
            Assert.NotNull(CSharpCompilationUnit(src, "unsupported.nl"));
        }
    }

    // COLUMNAR PIPELINE stage 1 (docs/design/columnar-pipeline.md): the top-level function declared-symbol
    // model built DIRECTLY from the columnar tables (no C# AST) must match the C# AST-derived symbol model on
    // every dogfood file -- name, modifiers, and canonical parameter + return type signatures. This is the
    // first downstream stage proving the columnar IR feeds a real semantic model, not just the parser.
    [Fact]
    public void ColumnarSymbols_TopLevelFunctions_MatchProductionBinderModel()
    {
        // Hand-built supported corpora (functions with varied signatures: arrays, generics, nullable, casts).
        string[] supportedCorpora =
        {
            "func add(a: int, b: int): int {\n    return a + b\n}\n\nfunc neg(x: int): int {\n    return -x\n}\n",
            "import System\n\nfunc lookup(keys: string[], values: int[], key: string): int {\n    return values[0]\n}\n\nfunc empty() {\n    return\n}\n",
            "func build(items: Map<string, int>, flags: bool[]): string {\n    return \"\"\n}\n",
        };

        foreach (var src in supportedCorpora)
        {
            var (ok, symbols) = RouteFunctionSymbols(src);
            Assert.True(ok, $"Symbol builder declined a supported corpus:\n{src}");
            Assert.NotNull(symbols);
            Assert.Equal(CSharpFunctionSignatures(src, "corpus.nl"), symbols!.Select(s => s.Signature()).ToList());
        }

        // Real dogfood corpus: every file's top-level function symbol model must match the C# parser's.
        var repoRoot = FindRepoRoot();
        var servicesDir = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood", "CompilerServices");
        var files = Directory.EnumerateFiles(servicesDir, "*.nl").OrderBy(p => p, StringComparer.Ordinal).ToList();
        var built = 0;
        foreach (var file in files)
        {
            var src = File.ReadAllText(file);
            var (ok, symbols) = RouteFunctionSymbols(src);
            Assert.True(ok, $"Columnar symbol builder declined its own systems source: {file}.");
            Assert.Equal(CSharpFunctionSignatures(src, file), symbols!.Select(s => s.Signature()).ToList());
            built++;
        }

        Assert.Equal(files.Count, built);
        Assert.True(built >= 30, $"Expected the full dogfood corpus to build symbols; only {built} did.");
    }

    // COLUMNAR PIPELINE stage 2 (docs/design/columnar-pipeline.md): lexical name resolution over the columnar
    // tables (no C# AST) must match the SAME algorithm walking the C# AST -- every bare identifier in every
    // function body classified identically (parameter / local / function / not-in-scope), in the same
    // pre-order, on the full dogfood corpus plus hand-built corpora (forward refs, while/if scopes, member
    // access, BCL receivers). Proves the columnar IR supports faithful scoped name resolution.
    [Fact]
    public void ColumnarNames_Resolution_MatchesAstWalk()
    {
        string[] supportedCorpora =
        {
            // Forward reference: in `a`, `b` resolves to a function declared later in the file.
            "func a(): int {\n    return b() + 1\n}\n\nfunc b(): int {\n    return 2\n}\n",
            // Params, locals, while/if scopes, index/member, assignment.
            "func scan(data: int[], count: int): int {\n    total := 0\n    i := 0\n    while i < count {\n        x := data[i]\n        if x > 0 {\n            total = total + x\n        }\n        i = i + 1\n    }\n    return total\n}\n",
            // BCL receiver (Array not in scope), member name not resolved, params resolved, call to a function.
            "import System\n\nfunc fill(buf: int[], n: int): int {\n    Array.Fill(buf, n)\n    return helper(buf)\n}\n\nfunc helper(b: int[]): int {\n    return b[0]\n}\n",
            // Cast operand + new args are resolved; type subtrees are not name lookups.
            "func codes(ch: char, n: int): int {\n    code := (int)ch\n    arr := new int[](n)\n    return code\n}\n",
        };

        foreach (var src in supportedCorpora)
        {
            var (ok, refs) = RouteFunctionNameRefs(src);
            Assert.True(ok, $"Name resolver declined a supported corpus:\n{src}");
            Assert.NotNull(refs);
            Assert.Equal(CSharpResolveFunctionNames(src, "corpus.nl"), ColumnarRefStrings(refs!));
        }

        var repoRoot = FindRepoRoot();
        var servicesDir = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood", "CompilerServices");
        var files = Directory.EnumerateFiles(servicesDir, "*.nl").OrderBy(p => p, StringComparer.Ordinal).ToList();
        var resolved = 0;
        foreach (var file in files)
        {
            var src = File.ReadAllText(file);
            var (ok, refs) = RouteFunctionNameRefs(src);
            Assert.True(ok, $"Columnar name resolver declined its own systems source: {file}.");
            Assert.Equal(CSharpResolveFunctionNames(src, file), ColumnarRefStrings(refs!));
            resolved++;
        }

        Assert.Equal(files.Count, resolved);
        Assert.True(resolved >= 30, $"Expected the full dogfood corpus to resolve; only {resolved} did.");
    }

    // COLUMNAR PIPELINE stage 3 (docs/design/columnar-pipeline.md): expression type inference over the
    // columnar tables (no C# AST) must implement the SAME inference rules walking the C# AST -- every
    // expression's inferred canonical type, in the same post-order -- on the full dogfood corpus plus
    // hand-built corpora. Pure-N# forms are inferred (literals, numeric promotion, comparison/logical, locals
    // from initializers, N#-function call returns, index, cast, new, ternary, assignment); BCL forms yield
    // "External". The shared ColumnarTypeLattice rules were adversarially reviewed against the REAL C# binder
    // (Analyzer.cs) and aligned to its actual behavior -- including the binder's current ECMA gaps (bitwise
    // binary and unary ~ are not concretely typed today; flagged in roadmap-to-done.md). This test proves the
    // columnar inferer implements that reviewed spec; the DEFINITIVE binder/output parity is verified
    // end-to-end at stages 4-5 (the columnar pipeline emitting IL that runs identically).
    [Fact]
    public void ColumnarTypes_Inference_MatchesAstWalk()
    {
        string[] supportedCorpora =
        {
            "func add(a: int, b: int): int {\n    sum := a + b\n    return sum\n}\n",
            "func pick(data: int[], i: int, flag: bool): int {\n    x := data[i]\n    return flag ? x : 0\n}\n",
            "func cmp(a: int, b: int): bool {\n    return a < b && a != b\n}\n",
            // forward-ref call return type
            "func a(): int {\n    return b() + 1\n}\n\nfunc b(): int {\n    return 1\n}\n",
            // cast -> int local; char arithmetic promotes to int
            "func codes(ch: char): int {\n    code := (int)ch\n    next := code + 1\n    return next\n}\n",
            // member access -> External; index on array -> element
            "import System\n\nfunc scan(s: string, data: int[], i: int): int {\n    total := data[i]\n    return total\n}\n",
        };

        foreach (var src in supportedCorpora)
        {
            var (ok, types) = RouteFunctionTypes(src);
            Assert.True(ok, $"Type inferer declined a supported corpus:\n{src}");
            Assert.NotNull(types);
            Assert.Equal(CSharpInferFunctionTypes(src, "corpus.nl"), types);
        }

        var repoRoot = FindRepoRoot();
        var servicesDir = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood", "CompilerServices");
        var files = Directory.EnumerateFiles(servicesDir, "*.nl").OrderBy(p => p, StringComparer.Ordinal).ToList();
        var inferred = 0;
        foreach (var file in files)
        {
            var src = File.ReadAllText(file);
            var (ok, types) = RouteFunctionTypes(src);
            Assert.True(ok, $"Columnar type inferer declined its own systems source: {file}.");
            Assert.Equal(CSharpInferFunctionTypes(src, file), types);
            inferred++;
        }

        Assert.Equal(files.Count, inferred);
        Assert.True(inferred >= 30, $"Expected the full dogfood corpus to infer; only {inferred} did.");
    }

    private static (bool Ok, List<List<string>>? Types) RouteFunctionTypes(string source)
    {
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");
        var method = adapterType.GetMethod("TryInferTopLevelFunctionTypes", BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryInferTopLevelFunctionTypes.");
        var args = new object?[] { source, null };
        var ok = (bool)(method.Invoke(null, args) ?? false);
        return (ok, (List<List<string>>?)args[1]);
    }

    // The C# AST mirror of ColumnarTypeInferer -- the EXACT same inference (via the shared ColumnarTypeLattice)
    // and post-order traversal on the object-graph AST. Produces per-function lists of inferred canonical types.
    private static List<List<string>> CSharpInferFunctionTypes(string source, string filePath)
    {
        var cu = CSharpCompilationUnit(source, filePath);
        var funcs = cu!.Declarations.OfType<FunctionDeclaration>().ToList();
        var functionReturnTypes = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var f in funcs)
            functionReturnTypes[f.Name] = f.ReturnType != null ? ColumnarFunctionSymbol.CanonicalType(f.ReturnType) : "void";

        var result = new List<List<string>>();
        foreach (var fn in funcs)
        {
            var parameterTypes = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var p in fn.Parameters) parameterTypes[p.Name] = ColumnarFunctionSymbol.CanonicalType(p.Type);
            var localScopes = new List<Dictionary<string, string>>();
            var types = new List<string>();

            string Lookup(string name)
            {
                for (var i = localScopes.Count - 1; i >= 0; i--)
                    if (localScopes[i].TryGetValue(name, out var t)) return t;
                return parameterTypes.TryGetValue(name, out var p) ? p : ColumnarTypeLattice.External;
            }

            string Expr(Expression e)
            {
                string t;
                switch (e)
                {
                    case IntLiteralExpression il: t = ColumnarTypeLattice.LiteralIntType(il.Value); break;
                    case FloatLiteralExpression fl: t = ColumnarTypeLattice.LiteralFloatType(fl.Value); break;
                    case CharLiteralExpression: t = "char"; break;
                    case StringLiteralExpression: t = "string"; break;
                    case BoolLiteralExpression: t = "bool"; break;
                    case NullLiteralExpression: t = "null"; break;
                    case IdentifierExpression id: t = Lookup(id.Name); break;
                    case ParenthesizedExpression p: t = Expr(p.Inner); break;
                    case MemberAccessExpression m: Expr(m.Object); t = ColumnarTypeLattice.External; break;
                    case CallExpression c:
                        Expr(c.Callee);
                        foreach (var a in c.Arguments) Expr(a.Value);
                        t = c.Callee is IdentifierExpression cid && functionReturnTypes.TryGetValue(cid.Name, out var r)
                            ? r : ColumnarTypeLattice.External;
                        break;
                    case IndexAccessExpression ix:
                    {
                        var o = Expr(ix.Object);
                        Expr(ix.Index);
                        t = ColumnarTypeLattice.ElementType(o);
                        break;
                    }
                    case UnaryExpression u:
                    {
                        var o = Expr(u.Operand);
                        t = ColumnarTypeLattice.Unary(UnaryOperatorText(u.Operator), o);
                        break;
                    }
                    case BinaryExpression b:
                    {
                        var l = Expr(b.Left);
                        var rr = Expr(b.Right);
                        t = ColumnarTypeLattice.Binary(BinaryOperatorText(b.Operator), l, rr);
                        break;
                    }
                    case TernaryExpression tn:
                    {
                        Expr(tn.Condition);
                        var a = Expr(tn.ThenExpression);
                        var bb = Expr(tn.ElseExpression);
                        t = a == bb ? a : ColumnarTypeLattice.Wider(a, bb);
                        break;
                    }
                    case AssignmentExpression asn:
                    {
                        var tg = Expr(asn.Target);
                        Expr(asn.Value);
                        t = tg;
                        break;
                    }
                    case NewExpression nw:
                        foreach (var a in nw.ConstructorArguments) Expr(a.Value);
                        t = ColumnarFunctionSymbol.CanonicalType(nw.Type!);
                        break;
                    case CastExpression cast:
                        Expr(cast.Expression);
                        t = ColumnarFunctionSymbol.CanonicalType(cast.TargetType);
                        break;
                    default: t = ColumnarTypeLattice.External; break;
                }

                types.Add(t);
                return t;
            }

            void Stmt(Statement s)
            {
                switch (s)
                {
                    case BlockStatement b:
                        localScopes.Add(new Dictionary<string, string>(StringComparer.Ordinal));
                        foreach (var inner in b.Statements) Stmt(inner);
                        localScopes.RemoveAt(localScopes.Count - 1);
                        break;
                    case VariableDeclarationStatement v:
                    {
                        var t = v.Initializer != null ? Expr(v.Initializer) : ColumnarTypeLattice.External;
                        if (localScopes.Count == 0) localScopes.Add(new Dictionary<string, string>(StringComparer.Ordinal));
                        localScopes[localScopes.Count - 1][v.Name] = t;
                        break;
                    }
                    case WhileStatement w: Expr(w.Condition); Stmt(w.Body); break;
                    case IfStatement i:
                        Expr(i.Condition); Stmt(i.ThenStatement);
                        if (i.ElseStatement != null) Stmt(i.ElseStatement);
                        break;
                    case ReturnStatement rs: if (rs.Value != null) Expr(rs.Value); break;
                    case ExpressionStatement es: Expr(es.Expression); break;
                }
            }

            if (fn.Body != null) Stmt(fn.Body);
            result.Add(types);
        }

        return result;
    }

    // COLUMNAR PIPELINE stage 3b (docs/design/columnar-pipeline.md): pure-structural diagnostics over the
    // columnar statement tables (no C# AST). This slice is definite-return (NL305): a non-void function must
    // return on every code path. ColumnarDiagnosticsPass.StatementAlwaysReturns is the columnar subset of the
    // real Analyzer.StatementAlwaysReturns — Return always exits, a Block exits if any statement exits, an If
    // exits only with an else where both branches exit; every other columnar statement kind (Break/Continue/
    // ExpressionStatement/VariableDeclaration/While) is non-exiting. The kernel refuses throw/switch/try/wrapper
    // forms, so those richer terminal shapes cannot appear on any body the columnar pass accepts — which makes
    // the subset faithful. Verified two ways: per hand-built case against the exact expected diagnostics AND a
    // C#-AST-walk mirror; and on the full dogfood corpus, equal to the AST-walk mirror AND emitting ZERO
    // missing-return (valid self-host source compiles, so the real analyzer emits no NL305 — a real-analyzer
    // parity check). Definitive routed parity follows at stages 4-5.
    [Fact]
    public void ColumnarDiagnostics_DefiniteReturn_MatchesAstWalk()
    {
        var cases = new (string Src, string[][] Expected)[]
        {
            // non-void, `if` WITHOUT else: the then-branch returns but control can skip it -> NL305.
            ("func score(ok: bool): int {\n    if ok {\n        return 42\n    }\n}\n",
                new[] { new[] { "missing-return:int" } }),
            // non-void, if/else where BOTH branches return -> all paths return -> none.
            ("func choose(ok: bool): int {\n    if ok {\n        return 1\n    } else {\n        return 2\n    }\n}\n",
                new[] { new string[0] }),
            // non-void, a plain return -> none.
            ("func id(x: int): int {\n    return x\n}\n",
                new[] { new string[0] }),
            // omitted return type is void-like -> the check is skipped -> none.
            ("func noop(x: int) {\n    y := x\n}\n",
                new[] { new string[0] }),
            // non-void, the only return is inside a while (a loop may run zero times) -> NL305.
            ("func loopOnly(ok: bool): int {\n    while ok {\n        return 1\n    }\n}\n",
                new[] { new[] { "missing-return:int" } }),
            // non-void, a non-terminal if followed by a trailing return -> the block exits -> none.
            ("func trailing(ok: bool): int {\n    if ok {\n        return 1\n    }\n    return 2\n}\n",
                new[] { new string[0] }),
            // two functions: the first misses a return, the second is fine -> per-function alignment.
            ("func a(ok: bool): int {\n    if ok {\n        return 1\n    }\n}\n\nfunc b(): int {\n    return 2\n}\n",
                new[] { new[] { "missing-return:int" }, new string[0] }),
        };

        foreach (var (src, expected) in cases)
        {
            var (ok, diags) = RouteFunctionDiagnostics(src);
            Assert.True(ok, $"Columnar diagnostics declined a supported corpus:\n{src}");
            Assert.NotNull(diags);
            Assert.Equal(expected.Select(f => f.ToList()).ToList(), diags);
            Assert.Equal(CSharpCollectFunctionDiagnostics(src, "corpus.nl"), diags);
        }

        var repoRoot = FindRepoRoot();
        var servicesDir = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood", "CompilerServices");
        var files = Directory.EnumerateFiles(servicesDir, "*.nl").OrderBy(p => p, StringComparer.Ordinal).ToList();
        var analyzed = 0;
        foreach (var file in files)
        {
            var src = File.ReadAllText(file);
            var (ok, diags) = RouteFunctionDiagnostics(src);
            Assert.True(ok, $"Columnar diagnostics declined its own systems source: {file}.");
            Assert.Equal(CSharpCollectFunctionDiagnostics(src, file), diags);
            Assert.All(diags!, fn => Assert.Empty(fn));
            analyzed++;
        }

        Assert.Equal(files.Count, analyzed);
        Assert.True(analyzed >= 30, $"Expected the full dogfood corpus to analyze; only {analyzed} did.");

        // Boundary: async + generator functions carry the real analyzer's isAsyncUnitTask / isIterator NL305
        // exemptions, which depend on BCL task-type knowledge the columnar pass does not model. The pass must
        // DECLINE such sources (ok == false -> C# fallback) rather than emit a divergent diagnostic. (e.g. the
        // real analyzer emits NO NL305 for `async func f(): Task {}`, but a naive return-type-only check would.)
        string[] declined =
        {
            "async func f(): Task {\n}\n",         // async unit Task — real analyzer exempts (no NL305)
            "async func g(): ValueTask {\n}\n",    // async unit ValueTask — exempt
            "async func h(): Task<int> {\n}\n",    // async non-unit — real analyzer DOES emit NL305 here
            "func* gen(): int {\n}\n",             // generator (func*) — iterator exemption
        };
        foreach (var src in declined)
            Assert.False(RouteFunctionDiagnostics(src).Ok, $"Columnar diagnostics must decline async/generator source:\n{src}");
    }

    // COLUMNAR PIPELINE stage 3b-ii: unreachable-after-terminal (NL312). The columnar pass mirrors
    // Analyzer.AnalyzeStatements — within a statement list, once a statement always exits, the immediately
    // following statement is unreachable (reported once), recursing into nested blocks. Verified equal to the
    // C#-AST-walk mirror (which validates the reported line:col matches the AST) on hand-built cases, plus a
    // non-vacuous count of detected unreachable statements. The corpus (asserted in the test above) compiles,
    // so it has zero unreachable — that test already pins zero false positives over the full 32-file corpus.
    [Fact]
    public void ColumnarDiagnostics_UnreachableAfterTerminal_MatchesAstWalk()
    {
        var cases = new (string Src, int Unreachable)[]
        {
            // a dead statement after a return.
            ("func f(): int {\n    return 1\n    x := 2\n}\n", 1),
            // a dead statement after a terminal if/else (both branches return).
            ("func g(ok: bool): int {\n    if ok {\n        return 1\n    } else {\n        return 2\n    }\n    y := 3\n}\n", 1),
            // only the FIRST unreachable statement is reported, then the rest of the list is skipped.
            ("func h(): int {\n    return 1\n    a := 2\n    b := 3\n}\n", 1),
            // unreachable INSIDE a reachable nested block (dead code after a return in the then-branch).
            ("func k(ok: bool): int {\n    if ok {\n        return 1\n        z := 2\n    }\n    return 3\n}\n", 1),
            // BOTH unreachable (in the then-branch) AND a missing return (the outer block is not terminal):
            // exercises the unreachable-before-missing-return ordering.
            ("func m(ok: bool): int {\n    if ok {\n        return 1\n        dead := 2\n    }\n}\n", 1),
            // fully reachable code: no unreachable.
            ("func clean(): int {\n    x := 1\n    return x\n}\n", 0),
        };

        foreach (var (src, unreachable) in cases)
        {
            var (ok, diags) = RouteFunctionDiagnostics(src);
            Assert.True(ok, $"Columnar diagnostics declined a supported unreachable corpus:\n{src}");
            Assert.NotNull(diags);
            // Exact parity with the AST walk: same descriptors, same order, same reported line:col.
            Assert.Equal(CSharpCollectFunctionDiagnostics(src, "corpus.nl"), diags);
            // Non-vacuous: the case actually detects the expected number of unreachable statements.
            var flat = diags!.SelectMany(d => d).ToList();
            Assert.Equal(unreachable, flat.Count(d => d.StartsWith("unreachable@", StringComparison.Ordinal)));
        }
    }

    private static (bool Ok, List<List<string>>? Diags) RouteFunctionDiagnostics(string source)
    {
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");
        var method = adapterType.GetMethod("TryCollectTopLevelFunctionDiagnostics", BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryCollectTopLevelFunctionDiagnostics.");
        var args = new object?[] { source, null };
        var ok = (bool)(method.Invoke(null, args) ?? false);
        return (ok, (List<List<string>>?)args[1]);
    }

    // The C# AST mirror of ColumnarDiagnosticsPass — the SAME control-flow logic walked on the object-graph
    // AST, so the columnar diagnostics are verified identical to walking the AST. Per function, in the same
    // deterministic order the pass emits: first unreachable-after-terminal (NL312, mirroring
    // Analyzer.AnalyzeStatements), then NL305 ("missing-return:<canonicalReturnType>") iff the return type is
    // non-void and the body does not return on all paths.
    private static List<List<string>> CSharpCollectFunctionDiagnostics(string source, string filePath)
    {
        var cu = CSharpCompilationUnit(source, filePath);
        var funcs = cu!.Declarations.OfType<FunctionDeclaration>().ToList();
        var result = new List<List<string>>();
        foreach (var fn in funcs)
        {
            var diags = new List<string>();
            if (fn.Body != null)
                MirrorCollectUnreachable(fn.Body, diags);
            var ret = fn.ReturnType != null ? ColumnarFunctionSymbol.CanonicalType(fn.ReturnType) : "void";
            if (ret != "void" && fn.Body != null && !MirrorAlwaysReturns(fn.Body))
                diags.Add("missing-return:" + ret);
            result.Add(diags);
        }

        return result;
    }

    // Mirrors Analyzer.AnalyzeStatements (2017): in each statement list, once a statement always exits, the
    // immediately-following statement is unreachable (reported once, then the list is skipped). Recurses into
    // nested blocks / if branches / while bodies exactly as Analyzer.AnalyzeStatement does.
    private static void MirrorCollectUnreachable(Statement s, List<string> diags)
    {
        switch (s)
        {
            case BlockStatement b:
            {
                var terminated = false;
                foreach (var st in b.Statements)
                {
                    if (terminated)
                    {
                        diags.Add("unreachable@" + st.Line + ":" + st.Column);
                        break;
                    }

                    MirrorCollectUnreachable(st, diags);
                    if (MirrorAlwaysReturns(st))
                        terminated = true;
                }

                break;
            }

            case WhileStatement w:
                MirrorCollectUnreachable(w.Body, diags);
                break;

            case IfStatement i:
                MirrorCollectUnreachable(i.ThenStatement, diags);
                if (i.ElseStatement != null)
                    MirrorCollectUnreachable(i.ElseStatement, diags);
                break;
        }
    }

    private static bool MirrorAlwaysReturns(Statement s)
    {
        switch (s)
        {
            case ReturnStatement:
                return true;
            case BlockStatement b:
                foreach (var st in b.Statements)
                {
                    if (MirrorAlwaysReturns(st))
                        return true;
                }

                return false;
            case IfStatement i:
                return i.ElseStatement != null
                    && MirrorAlwaysReturns(i.ThenStatement)
                    && MirrorAlwaysReturns(i.ElseStatement);
            default:
                return false;
        }
    }

    // COLUMNAR PIPELINE stage 3b-iii: unused-local (NL001). The Linter is time-/scope-ordered: it checks each
    // block's locals at PopScope against a file-level _usedVariables set that accumulates in traversal order and
    // is never cleared between functions, so a use AFTER a block closes (later sibling block / later function)
    // does NOT suppress, while an earlier use does. Verified equal to a C#-AST-walk mirror that reproduces that
    // exact ordering; descriptors sorted per function for comparison (identity, not the Linter's Dictionary
    // emission order, is the contract). Covers ordering both ways, nesting, assignment-marks-used, discard, and
    // the full 32-file corpus.
    [Fact]
    public void ColumnarDiagnostics_UnusedLocal_MatchesAstWalk()
    {
        var cases = new (string Src, int Unused)[]
        {
            // never referenced -> unused.
            ("func f(): int {\n    unused := 1\n    return 2\n}\n", 1),
            // read -> used.
            ("func g(): int {\n    x := 1\n    return x\n}\n", 0),
            // assignment target marks the variable used.
            ("func h(): int {\n    x := 1\n    x = 2\n    return 3\n}\n", 0),
            // a discard ("_"-prefixed) local is exempt.
            ("func k(): int {\n    _unused := 1\n    return 2\n}\n", 0),
            // used inside another local's initializer -> both used.
            ("func m(): int {\n    a := 1\n    b := a + 1\n    return b\n}\n", 0),
            // ORDER (later use does NOT suppress): 'shared' is unused in p; q references it LATER, so the
            // Linter flags p's 'shared' (its block closed before q was visited).
            ("func p(): int {\n    shared := 1\n    return 2\n}\n\nfunc q(): int {\n    return shared\n}\n", 1),
            // ORDER (earlier use DOES suppress): 'helper' is read in 'earlier' (visited first), so 'later's
            // unused 'helper' is suppressed by the accumulated usedNames.
            ("func earlier(): int {\n    return helper\n}\n\nfunc later(): int {\n    helper := 1\n    return 2\n}\n", 0),
            // nested-block local, never read -> unused (checked at the inner block's exit).
            ("func nested(ok: bool): int {\n    if ok {\n        inner := 1\n    }\n    return 2\n}\n", 1),
            // two unused locals.
            ("func r(): int {\n    a := 1\n    b := 2\n    return 3\n}\n", 2),
        };

        foreach (var (src, unused) in cases)
        {
            var (ok, diags) = RouteUnusedLocals(src);
            Assert.True(ok, $"Columnar unused-local declined a supported corpus:\n{src}");
            Assert.NotNull(diags);
            Assert.Equal(SortPerFunction(CSharpCollectUnusedLocals(src, "corpus.nl")), SortPerFunction(diags!));
            Assert.Equal(unused, diags!.SelectMany(d => d).Count(d => d.StartsWith("unused-local:", StringComparison.Ordinal)));
        }

        var repoRoot = FindRepoRoot();
        var servicesDir = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood", "CompilerServices");
        var files = Directory.EnumerateFiles(servicesDir, "*.nl").OrderBy(p => p, StringComparer.Ordinal).ToList();
        var analyzed = 0;
        foreach (var file in files)
        {
            var src = File.ReadAllText(file);
            var (ok, diags) = RouteUnusedLocals(src);
            Assert.True(ok, $"Columnar unused-local declined its own systems source: {file}.");
            Assert.Equal(SortPerFunction(CSharpCollectUnusedLocals(src, file)), SortPerFunction(diags!));
            analyzed++;
        }

        Assert.Equal(files.Count, analyzed);
        Assert.True(analyzed >= 30, $"Expected the full dogfood corpus to analyze; only {analyzed} did.");
    }

    private static List<List<string>> SortPerFunction(List<List<string>> perFunction)
        => perFunction.Select(f => f.OrderBy(s => s, StringComparer.Ordinal).ToList()).ToList();

    private static (bool Ok, List<List<string>>? Unused) RouteUnusedLocals(string source)
    {
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");
        var method = adapterType.GetMethod("TryCollectUnusedLocals", BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryCollectUnusedLocals.");
        var args = new object?[] { source, null };
        var ok = (bool)(method.Invoke(null, args) ?? false);
        return (ok, (List<List<string>>?)args[1]);
    }

    // C# AST mirror of TryCollectUnusedLocals — the SAME time-/scope-ordered walk on the object-graph AST:
    // functions in source order share an accumulating usedNames (seeded with each function's params); each
    // block's `:=` locals are checked at the block's exit against usedNames as-of-then.
    private static List<List<string>> CSharpCollectUnusedLocals(string source, string filePath)
    {
        var cu = CSharpCompilationUnit(source, filePath);
        var funcs = cu!.Declarations.OfType<FunctionDeclaration>().ToList();

        var usedNames = new HashSet<string>(StringComparer.Ordinal);
        var result = new List<List<string>>();
        foreach (var fn in funcs)
        {
            foreach (var p in fn.Parameters) usedNames.Add(p.Name);
            var unused = new List<string>();
            if (fn.Body != null)
                MirrorWalkUnused(fn.Body, usedNames, new List<List<(string, int, int)>>(), unused);
            result.Add(unused);
        }

        return result;
    }

    private static void MirrorWalkUnused(
        Statement s, HashSet<string> used, List<List<(string Name, int Line, int Column)>> stack, List<string> unused)
    {
        switch (s)
        {
            case BlockStatement b:
            {
                var scope = new List<(string Name, int Line, int Column)>();
                stack.Add(scope);
                foreach (var st in b.Statements) MirrorWalkUnused(st, used, stack, unused);
                foreach (var (name, line, column) in scope)
                {
                    if (name != "_" && !name.StartsWith("_", StringComparison.Ordinal) && !used.Contains(name))
                        unused.Add("unused-local:" + name + "@" + line + ":" + column);
                }

                stack.RemoveAt(stack.Count - 1);
                break;
            }

            case VariableDeclarationStatement v:
                if (stack.Count > 0) stack[stack.Count - 1].Add((v.Name, v.Line, v.Column));
                if (v.Initializer != null) MirrorCollectIds(v.Initializer, used);
                break;
            case IfStatement i:
                MirrorCollectIds(i.Condition, used);
                MirrorWalkUnused(i.ThenStatement, used, stack, unused);
                if (i.ElseStatement != null) MirrorWalkUnused(i.ElseStatement, used, stack, unused);
                break;
            case WhileStatement w:
                MirrorCollectIds(w.Condition, used);
                MirrorWalkUnused(w.Body, used, stack, unused);
                break;
            case ReturnStatement r:
                if (r.Value != null) MirrorCollectIds(r.Value, used);
                break;
            case ExpressionStatement e:
                MirrorCollectIds(e.Expression, used);
                break;
        }
    }

    private static void MirrorCollectIds(Expression e, HashSet<string> used)
    {
        switch (e)
        {
            case IdentifierExpression id: used.Add(id.Name); break;
            case ParenthesizedExpression p: MirrorCollectIds(p.Inner, used); break;
            case MemberAccessExpression m: MirrorCollectIds(m.Object, used); break;
            case CallExpression c:
                MirrorCollectIds(c.Callee, used);
                foreach (var a in c.Arguments) MirrorCollectIds(a.Value, used);
                break;
            case IndexAccessExpression ix:
                MirrorCollectIds(ix.Object, used);
                MirrorCollectIds(ix.Index, used);
                break;
            case UnaryExpression u: MirrorCollectIds(u.Operand, used); break;
            case BinaryExpression b:
                MirrorCollectIds(b.Left, used);
                MirrorCollectIds(b.Right, used);
                break;
            case TernaryExpression t:
                MirrorCollectIds(t.Condition, used);
                MirrorCollectIds(t.ThenExpression, used);
                MirrorCollectIds(t.ElseExpression, used);
                break;
            case AssignmentExpression asn:
                MirrorCollectIds(asn.Target, used);
                MirrorCollectIds(asn.Value, used);
                break;
            case NewExpression nw:
                foreach (var a in nw.ConstructorArguments) MirrorCollectIds(a.Value, used);
                break;
            case CastExpression cast: MirrorCollectIds(cast.Expression, used); break;
        }
    }

    // COLUMNAR PIPELINE stage 4 SPIKE: emit a runnable .NET assembly for a trivial top-level function whose body
    // IL is generated DIRECTLY from the columnar tables (no C# AST), then LOAD + INVOKE it and check results.
    // Proves the columnar pipeline drives codegen end-to-end. Also checks the spike DECLINES (no assembly, C#
    // path unaffected) on forms it does not yet support.
    [Fact]
    public void ColumnarCodegen_Spike_EmitsRunnableTrivialFunctions()
    {
        AssertEmits("func identity(x: int): int {\n    return x\n}\n", "identity",
            (new object[] { 42 }, 42), (new object[] { -7 }, -7));
        AssertEmits("func answer(): int {\n    return 42\n}\n", "answer",
            (new object[] { }, 42));
        AssertEmits("func add(a: int, b: int): int {\n    return a + b\n}\n", "add",
            (new object[] { 2, 3 }, 5), (new object[] { -5, 10 }, 5));
        AssertEmits("func poly(a: int, b: int, c: int): int {\n    return a * b - c\n}\n", "poly",
            (new object[] { 3, 4, 5 }, 7));
        AssertEmits("func paren(a: int, b: int): int {\n    return (a + b) * b\n}\n", "paren",
            (new object[] { 2, 3 }, 15));
        // nested binary keeps left-associativity ((a - b) - c).
        AssertEmits("func chain(a: int, b: int, c: int): int {\n    return a - b - c\n}\n", "chain",
            (new object[] { 10, 3, 2 }, 5));
        // mixed parameter + int literal.
        AssertEmits("func inc(a: int): int {\n    return a + 1\n}\n", "inc",
            (new object[] { 5 }, 6), (new object[] { -1 }, 0));
        // a `:=` local feeding a return.
        AssertEmits("func sum(a: int, b: int): int {\n    x := a + b\n    return x\n}\n", "sum",
            (new object[] { 2, 3 }, 5), (new object[] { -4, 4 }, 0));
        // chained locals (the second reads the first).
        AssertEmits("func chained(a: int): int {\n    x := a + 1\n    y := x * 2\n    return y\n}\n", "chained",
            (new object[] { 3 }, 8));
        // a local mixed with a parameter in the returned expression.
        AssertEmits("func square(a: int): int {\n    t := a * a\n    return t + a\n}\n", "square",
            (new object[] { 3 }, 12), (new object[] { 0 }, 0));
        // unary negate and bitwise-not.
        AssertEmits("func neg(a: int): int {\n    return -a\n}\n", "neg",
            (new object[] { 5 }, -5), (new object[] { -7 }, 7), (new object[] { 0 }, 0));
        AssertEmits("func bnot(a: int): int {\n    return ~a\n}\n", "bnot",
            (new object[] { 0 }, -1), (new object[] { 5 }, -6));
        // unary in a larger expression.
        AssertEmits("func shift(a: int, b: int): int {\n    x := -a\n    return x + b\n}\n", "shift",
            (new object[] { 3, 10 }, 7));
        // if/else where both branches return (a comparison condition).
        AssertEmits("func max(a: int, b: int): int {\n    if a > b {\n        return a\n    } else {\n        return b\n    }\n}\n", "max",
            (new object[] { 3, 5 }, 5), (new object[] { 7, 2 }, 7), (new object[] { 4, 4 }, 4));
        // `>=` plus subtraction-as-negation.
        AssertEmits("func absish(a: int): int {\n    if a >= 0 {\n        return a\n    } else {\n        return 0 - a\n    }\n}\n", "absish",
            (new object[] { 5 }, 5), (new object[] { -3 }, 3), (new object[] { 0 }, 0));
        // nested if/else (the else branch is itself a both-returning if/else).
        AssertEmits("func sign(a: int): int {\n    if a > 0 {\n        return 1\n    } else {\n        if a < 0 {\n            return 0 - 1\n        } else {\n            return 0\n        }\n    }\n}\n", "sign",
            (new object[] { 5 }, 1), (new object[] { -3 }, -1), (new object[] { 0 }, 0));
        // if WITHOUT an else (a guard clause). Three shapes: a then-branch that RETURNS (control falls
        // through to a trailing return), a then-branch that FALLS THROUGH (a conditional assignment), and
        // two sequential guards. The function-level always-returns gate ensures a statement follows each.
        AssertEmits("func clampLow(a: int): int {\n    if a < 0 {\n        return 0\n    }\n    return a\n}\n", "clampLow",
            (new object[] { -5 }, 0), (new object[] { 0 }, 0), (new object[] { 7 }, 7));
        AssertEmits("func condAdd(a: int): int {\n    x := a\n    if x < 10 {\n        x = x + 1\n    }\n    return x\n}\n", "condAdd",
            (new object[] { 3 }, 4), (new object[] { 10 }, 10), (new object[] { 20 }, 20));
        AssertEmits("func clamp(a: int): int {\n    if a < 0 {\n        return 0 - 1\n    }\n    if a > 100 {\n        return 1\n    }\n    return 0\n}\n", "clamp",
            (new object[] { -5 }, -1), (new object[] { 200 }, 1), (new object[] { 50 }, 0));
        // if-WITH-else, general fall-through merge (not both-return): then-falls/else-returns,
        // then-returns/else-falls, and both-fall-through. (Both-return is covered by max/sign above.)
        AssertEmits("func tf(a: int): int {\n    r := 0\n    if a > 0 {\n        r = 1\n    } else {\n        return 0 - 1\n    }\n    return r\n}\n", "tf",
            (new object[] { 5 }, 1), (new object[] { -5 }, -1), (new object[] { 0 }, -1));
        AssertEmits("func tr(a: int): int {\n    r := 0\n    if a > 0 {\n        return 9\n    } else {\n        r = 2\n    }\n    return r\n}\n", "tr",
            (new object[] { 5 }, 9), (new object[] { -5 }, 2), (new object[] { 0 }, 2));
        AssertEmits("func bf(a: int): int {\n    r := 0\n    if a > 0 {\n        r = 1\n    } else {\n        r = 2\n    }\n    return r\n}\n", "bf",
            (new object[] { 5 }, 1), (new object[] { -5 }, 2), (new object[] { 0 }, 2));
        // a simple `local = expr` assignment statement, then a return of the local.
        AssertEmits("func acc(a: int, b: int): int {\n    x := a\n    x = x + b\n    return x\n}\n", "acc",
            (new object[] { 3, 4 }, 7), (new object[] { 10, -10 }, 0));
        // multiple reassignments of the same local.
        AssertEmits("func bump(a: int): int {\n    x := a\n    x = x + 1\n    x = x * 2\n    return x\n}\n", "bump",
            (new object[] { 3 }, 8));
        // a while loop: count up to n (and n<=0 runs the loop zero times).
        AssertEmits("func count(n: int): int {\n    x := 0\n    i := 0\n    while i < n {\n        x = x + 1\n        i = i + 1\n    }\n    return x\n}\n", "count",
            (new object[] { 5 }, 5), (new object[] { 0 }, 0), (new object[] { -3 }, 0));
        // sum 1..n via a while loop with `<=`.
        AssertEmits("func sumTo(n: int): int {\n    total := 0\n    i := 1\n    while i <= n {\n        total = total + i\n        i = i + 1\n    }\n    return total\n}\n", "sumTo",
            (new object[] { 5 }, 15), (new object[] { 1 }, 1), (new object[] { 0 }, 0));
        // factorial via a while loop (exercises a local read+write each iteration).
        AssertEmits("func fact(n: int): int {\n    result := 1\n    i := 1\n    while i <= n {\n        result = result * i\n        i = i + 1\n    }\n    return result\n}\n", "fact",
            (new object[] { 5 }, 120), (new object[] { 0 }, 1), (new object[] { 1 }, 1));
        // a `:=` local declared INSIDE the loop body and used within it (block-scoped, fine).
        AssertEmits("func twice(n: int): int {\n    total := 0\n    i := 0\n    while i < n {\n        step := 2\n        total = total + step\n        i = i + 1\n    }\n    return total\n}\n", "twice",
            (new object[] { 3 }, 6), (new object[] { 0 }, 0));

        // Declines (no assembly) on forms the spike does not support yet -> the C# path is unaffected.
        Assert.False(RouteColumnarEmit("func two(): int {\n    return 1\n}\n\nfunc other(): int {\n    return 2\n}\n").Ok);
        Assert.False(RouteColumnarEmit("func arr(): string[] {\n    return null\n}\n").Ok);
        // MIXED int/long arithmetic (implicit widening) is not modelled -> decline (pure int/bool/long are now
        // supported; long single-function coverage lives in ColumnarCodegen_Parity_LongType).
        Assert.False(RouteColumnarEmit("func mix(a: int, b: long): long {\n    return a + b\n}\n").Ok);
        // a value-less `return` in an int function would emit invalid IL -> must decline.
        Assert.False(RouteColumnarEmit("func novalue(): int {\n    return\n}\n").Ok);
        // a local shadowing a parameter is a diagnostic in N#; the spike must decline (not silently compile it).
        Assert.False(RouteColumnarEmit("func shadow(x: int): int {\n    x := x + 1\n    return x\n}\n").Ok);
        // redeclaring a local name with `:=` -> decline.
        Assert.False(RouteColumnarEmit("func redecl(a: int): int {\n    x := a\n    x := x + 1\n    return x\n}\n").Ok);
        // a comparison in value position (returning a bool from an int func) would diverge from N# types -> decline.
        Assert.False(RouteColumnarEmit("func gt(a: int, b: int): int {\n    return a > b\n}\n").Ok);
        // unreachable code after a return (an NL312 diagnostic) must decline, not emit code after `ret`.
        Assert.False(RouteColumnarEmit("func unreach(a: int): int {\n    if a > 0 {\n        return 1\n        y := 2\n    } else {\n        return 0\n    }\n}\n").Ok);
        // compound assignment (`+=`) is not lowered yet -> decline.
        Assert.False(RouteColumnarEmit("func compound(a: int): int {\n    x := a\n    x += 1\n    return x\n}\n").Ok);
        // assigning to a parameter (not a `:=` local) -> decline (starg not modeled).
        Assert.False(RouteColumnarEmit("func setp(a: int): int {\n    a = a + 1\n    return a\n}\n").Ok);
        // an int body that does NOT return on all paths (NL305) would emit IL with no final `ret` -> decline.
        Assert.False(RouteColumnarEmit("func noRetAssign(a: int): int {\n    x := a\n    x = x + 1\n}\n").Ok);
        Assert.False(RouteColumnarEmit("func noRetDecl(a: int): int {\n    x := a\n}\n").Ok);
        // a degenerate while whose body always returns (exits on the first iteration) -> decline.
        Assert.False(RouteColumnarEmit("func degen(n: int): int {\n    while n > 0 {\n        return 1\n    }\n    return 0\n}\n").Ok);
        // a loop-body local referenced AFTER the loop is out of scope in N# -> block scoping declines it
        // (rather than reading a possibly-unassigned method-level slot).
        Assert.False(RouteColumnarEmit("func leak(n: int): int {\n    i := 0\n    while i < n {\n        temp := i\n        i = i + 1\n    }\n    return temp\n}\n").Ok);
        // same leak via a BRACELESS single-statement loop body (`:=` directly, not a block) -> still declines.
        Assert.False(RouteColumnarEmit("func bleak(n: int): int {\n    i := 0\n    while i < n  x := i\n    return x\n}\n").Ok);
        // an unsupported unary operator (logical `!`, also a type error on an int) -> decline.
        Assert.False(RouteColumnarEmit("func lnot(a: int): int {\n    return !a\n}\n").Ok);
    }

    // Stage 4c -- the columnar codegen PARITY ORACLE. The Stage-4 emitter is verified not against
    // hand-written expected constants (that only proves self-consistency) but against the
    // AUTHORITATIVE production C# ILCompiler: the SAME N# source is compiled by BOTH the columnar
    // path (TryEmitColumnarFunction) and the C# AST path, then each emitted method is invoked over a
    // spread of inputs -- including negatives, zero, ordering boundaries for comparisons, and
    // overflow extremes -- and the results MUST be identical. This is the acceptance gate every
    // future codegen-routing slice must clear: it proves the columnar IL is semantically equivalent
    // to the path it will eventually replace, catching any divergence (wrong opcode, operand, branch
    // sense, operator precedence, loop bound) that a constants-only test would miss.
    [Fact]
    public void ColumnarCodegen_Parity_MatchesCSharpPath()
    {
        // Trivial returns / params / literals.
        AssertColumnarMatchesCSharp("func identity(x: int): int {\n    return x\n}\n", "identity",
            new object[] { 0 }, new object[] { 7 }, new object[] { -13 }, new object[] { int.MaxValue }, new object[] { int.MinValue });
        AssertColumnarMatchesCSharp("func answer(): int {\n    return 42\n}\n", "answer",
            new object[] { });
        // Arithmetic + operator precedence + left-associativity + parenthesized grouping.
        AssertColumnarMatchesCSharp("func add(a: int, b: int): int {\n    return a + b\n}\n", "add",
            new object[] { 2, 3 }, new object[] { -5, 5 }, new object[] { -7, -8 }, new object[] { int.MaxValue, 1 });
        AssertColumnarMatchesCSharp("func poly(a: int, b: int, c: int): int {\n    return a * b - c\n}\n", "poly",
            new object[] { 3, 4, 5 }, new object[] { -2, 6, -1 }, new object[] { 0, 99, 7 });
        AssertColumnarMatchesCSharp("func paren(a: int, b: int): int {\n    return (a + b) * b\n}\n", "paren",
            new object[] { 2, 3 }, new object[] { -4, 5 }, new object[] { 7, -2 });
        AssertColumnarMatchesCSharp("func chain(a: int, b: int, c: int): int {\n    return a - b - c\n}\n", "chain",
            new object[] { 10, 3, 2 }, new object[] { -1, -2, -3 });
        // Unary negate / bitwise-not.
        AssertColumnarMatchesCSharp("func neg(a: int): int {\n    return -a\n}\n", "neg",
            new object[] { 5 }, new object[] { -9 }, new object[] { 0 }, new object[] { int.MinValue });
        AssertColumnarMatchesCSharp("func bnot(a: int): int {\n    return ~a\n}\n", "bnot",
            new object[] { 0 }, new object[] { 5 }, new object[] { -1 }, new object[] { int.MaxValue });
        // if/else, including the comparison-boundary case a == b.
        AssertColumnarMatchesCSharp("func max(a: int, b: int): int {\n    if a > b {\n        return a\n    } else {\n        return b\n    }\n}\n", "max",
            new object[] { 3, 5 }, new object[] { 5, 3 }, new object[] { 4, 4 }, new object[] { -2, -9 });
        // Nested if/else (three-way branch).
        AssertColumnarMatchesCSharp("func sign(a: int): int {\n    if a > 0 {\n        return 1\n    } else {\n        if a < 0 {\n            return 0 - 1\n        } else {\n            return 0\n        }\n    }\n}\n", "sign",
            new object[] { 9 }, new object[] { -9 }, new object[] { 0 });
        // if WITHOUT else (guard clauses): then-returns, then-falls-through, and two sequential guards.
        AssertColumnarMatchesCSharp("func clampLow(a: int): int {\n    if a < 0 {\n        return 0\n    }\n    return a\n}\n", "clampLow",
            new object[] { -5 }, new object[] { -1 }, new object[] { 0 }, new object[] { 7 }, new object[] { int.MinValue });
        AssertColumnarMatchesCSharp("func condAdd(a: int): int {\n    x := a\n    if x < 10 {\n        x = x + 1\n    }\n    return x\n}\n", "condAdd",
            new object[] { 3 }, new object[] { 9 }, new object[] { 10 }, new object[] { 20 });
        AssertColumnarMatchesCSharp("func clamp(a: int): int {\n    if a < 0 {\n        return 0 - 1\n    }\n    if a > 100 {\n        return 1\n    }\n    return 0\n}\n", "clamp",
            new object[] { -5 }, new object[] { 0 }, new object[] { 100 }, new object[] { 200 });
        // if-without-else at the risky positions (where a merge label could otherwise land badly): a guard
        // NESTED in another guard's then-branch; a guard as the LAST statement of a while body (its merge
        // label is followed by the loop back-edge); and a guard as a NON-last while-body statement.
        AssertColumnarMatchesCSharp("func nested(a: int): int {\n    if a > 0 {\n        if a > 10 {\n            return 2\n        }\n        return 1\n    }\n    return 0\n}\n", "nested",
            new object[] { -1 }, new object[] { 5 }, new object[] { 50 });
        AssertColumnarMatchesCSharp("func guardLast(n: int): int {\n    x := 0\n    i := 0\n    while i < n {\n        i = i + 1\n        if i > 2 {\n            x = x + 1\n        }\n    }\n    return x\n}\n", "guardLast",
            new object[] { 0 }, new object[] { 2 }, new object[] { 5 });
        AssertColumnarMatchesCSharp("func guardMid(n: int): int {\n    x := 0\n    i := 0\n    while i < n {\n        if i > 1 {\n            x = x + 10\n        }\n        i = i + 1\n    }\n    return x\n}\n", "guardMid",
            new object[] { 0 }, new object[] { 2 }, new object[] { 5 });
        // if-WITH-else, general fall-through merge: then-falls/else-returns, then-returns/else-falls, both-fall.
        AssertColumnarMatchesCSharp("func tf(a: int): int {\n    r := 0\n    if a > 0 {\n        r = 1\n    } else {\n        return 0 - 1\n    }\n    return r\n}\n", "tf",
            new object[] { 5 }, new object[] { -5 }, new object[] { 0 });
        AssertColumnarMatchesCSharp("func tr(a: int): int {\n    r := 0\n    if a > 0 {\n        return 9\n    } else {\n        r = 2\n    }\n    return r\n}\n", "tr",
            new object[] { 5 }, new object[] { -5 }, new object[] { 0 });
        AssertColumnarMatchesCSharp("func bf(a: int): int {\n    r := 0\n    if a > 0 {\n        r = 1\n    } else {\n        r = 2\n    }\n    return r\n}\n", "bf",
            new object[] { 5 }, new object[] { -5 }, new object[] { 0 });
        // := local + reassignment.
        AssertColumnarMatchesCSharp("func acc(a: int, b: int): int {\n    x := a\n    x = x + b\n    return x\n}\n", "acc",
            new object[] { 1, 2 }, new object[] { -3, 10 });
        // while loops: empty-iteration, single-iteration, accumulation, and the multiply (fact) case.
        AssertColumnarMatchesCSharp("func count(n: int): int {\n    x := 0\n    i := 0\n    while i < n {\n        x = x + 1\n        i = i + 1\n    }\n    return x\n}\n", "count",
            new object[] { 0 }, new object[] { 1 }, new object[] { 5 }, new object[] { -3 });
        AssertColumnarMatchesCSharp("func sumTo(n: int): int {\n    total := 0\n    i := 1\n    while i <= n {\n        total = total + i\n        i = i + 1\n    }\n    return total\n}\n", "sumTo",
            new object[] { 0 }, new object[] { 1 }, new object[] { 5 }, new object[] { 10 });
        AssertColumnarMatchesCSharp("func fact(n: int): int {\n    result := 1\n    i := 1\n    while i <= n {\n        result = result * i\n        i = i + 1\n    }\n    return result\n}\n", "fact",
            new object[] { 0 }, new object[] { 1 }, new object[] { 5 }, new object[] { 7 });
    }

    // The standalone columnar backend's first MULTI-FUNCTION slice: emit EVERY top-level function of a source
    // into ONE assembly (type "ColumnarProgram") via the columnar path, then invoke each and assert parity with
    // the authoritative C# pipeline. This exercises the two-pass declare-then-emit structure (all methods
    // declared before any body is emitted) that sibling calls (4i) and whole-program emission build on.
    [Fact]
    public void ColumnarCodegen_Parity_MultiFunction()
    {
        // Two independent int functions in one assembly, each matched against the C# path.
        var twoFns = "func add(a: int, b: int): int {\n    return a + b\n}\n\nfunc mul(a: int, b: int): int {\n    return a * b\n}\n";
        AssertColumnarProgramMatchesCSharp(twoFns,
            ("add", new object[] { 2, 3 }), ("add", new object[] { -5, 5 }),
            ("mul", new object[] { 4, 6 }), ("mul", new object[] { -3, 7 }));

        // Three functions with varied control flow (guard clause, while accumulation, if/else) in one assembly.
        var threeFns = "func clampLow(a: int): int {\n    if a < 0 {\n        return 0\n    }\n    return a\n}\n\nfunc sumTo(n: int): int {\n    total := 0\n    i := 1\n    while i <= n {\n        total = total + i\n        i = i + 1\n    }\n    return total\n}\n\nfunc pick(a: int, b: int): int {\n    if a > b {\n        return a\n    } else {\n        return b\n    }\n}\n";
        AssertColumnarProgramMatchesCSharp(threeFns,
            ("clampLow", new object[] { -5 }), ("clampLow", new object[] { 7 }),
            ("sumTo", new object[] { 5 }), ("sumTo", new object[] { 0 }),
            ("pick", new object[] { 3, 9 }), ("pick", new object[] { 9, 3 }));

        // A single function routed through the multi-function path still works (a degenerate one-func program).
        AssertColumnarProgramMatchesCSharp("func id(x: int): int {\n    return x\n}\n",
            ("id", new object[] { 42 }), ("id", new object[] { -7 }));

        // The whole program declines (no assembly) if ANY function is ineligible (here, a not-yet-supported
        // `double` second func — int/bool/long are supported).
        Assert.False(RouteColumnarProgram("func ok(a: int): int {\n    return a\n}\n\nfunc bad(x: double): double {\n    return x\n}\n").Ok);

        // 4i SIBLING CALLS. A caller invoking a sibling, and a nested call (call result as an arg).
        var callHelper = "func add(a: int, b: int): int {\n    return a + b\n}\n\nfunc addThree(a: int, b: int, c: int): int {\n    return add(add(a, b), c)\n}\n";
        AssertColumnarProgramMatchesCSharp(callHelper,
            ("add", new object[] { 2, 3 }),
            ("addThree", new object[] { 1, 2, 3 }), ("addThree", new object[] { -4, 5, -6 }));

        // SELF-RECURSION (the sibling map includes the function itself): factorial and two-call fibonacci.
        AssertColumnarProgramMatchesCSharp("func fact(n: int): int {\n    if n <= 1 {\n        return 1\n    }\n    return n * fact(n - 1)\n}\n",
            ("fact", new object[] { 0 }), ("fact", new object[] { 1 }), ("fact", new object[] { 5 }), ("fact", new object[] { 7 }));
        AssertColumnarProgramMatchesCSharp("func fib(n: int): int {\n    if n < 2 {\n        return n\n    }\n    return fib(n - 1) + fib(n - 2)\n}\n",
            ("fib", new object[] { 0 }), ("fib", new object[] { 1 }), ("fib", new object[] { 7 }), ("fib", new object[] { 10 }));

        // MUTUAL RECURSION (a FORWARD reference: isEven calls isOdd declared AFTER it — the two-pass declare-first
        // design resolves it to a not-yet-emitted MethodBuilder).
        var mutual = "func isEven(n: int): int {\n    if n == 0 {\n        return 1\n    }\n    return isOdd(n - 1)\n}\n\nfunc isOdd(n: int): int {\n    if n == 0 {\n        return 0\n    }\n    return isEven(n - 1)\n}\n";
        AssertColumnarProgramMatchesCSharp(mutual,
            ("isEven", new object[] { 0 }), ("isEven", new object[] { 4 }), ("isEven", new object[] { 7 }),
            ("isOdd", new object[] { 3 }), ("isOdd", new object[] { 8 }));
    }

    // Stage 4b-i — the type-aware emitter, proven by adding BOOL alongside int. Comparisons now produce bool in
    // value position, bool literals / params / locals / returns work, logical-not works, and a bool value drives
    // conditions directly. The type machinery rejects cross-type mixing (a bool can't leak into int arithmetic).
    [Fact]
    public void ColumnarCodegen_Parity_BoolType()
    {
        // Comparison in return position, bool params, logical not, bool literal, bool == bool — all vs the C# path.
        var prog = "func isPositive(a: int): bool {\n    return a > 0\n}\n\n" +
                   "func isEqual(a: int, b: int): bool {\n    return a == b\n}\n\n" +
                   "func negate(b: bool): bool {\n    return !b\n}\n\n" +
                   "func always(): bool {\n    return true\n}\n\n" +
                   "func sameBool(a: bool, b: bool): bool {\n    return a == b\n}\n";
        AssertColumnarProgramMatchesCSharp(prog,
            ("isPositive", new object[] { 5 }), ("isPositive", new object[] { -2 }), ("isPositive", new object[] { 0 }),
            ("isEqual", new object[] { 3, 3 }), ("isEqual", new object[] { 3, 4 }),
            ("negate", new object[] { true }), ("negate", new object[] { false }),
            ("always", System.Array.Empty<object>()),
            ("sameBool", new object[] { true, true }), ("sameBool", new object[] { true, false }));

        // A bool LOCAL (`:=` infers bool from the comparison initializer), and a bool param used as a condition.
        var prog2 = "func bigFlag(a: int): bool {\n    flag := a > 100\n    return flag\n}\n\n" +
                    "func choose(flag: bool, a: int, b: int): int {\n    if flag {\n        return a\n    } else {\n        return b\n    }\n}\n";
        AssertColumnarProgramMatchesCSharp(prog2,
            ("bigFlag", new object[] { 200 }), ("bigFlag", new object[] { 50 }),
            ("choose", new object[] { true, 7, 9 }), ("choose", new object[] { false, 7, 9 }));

        // A bool ARGUMENT passed to a bool parameter (needsBool(x > 0)) — the correct-type call path, confirming
        // the per-arg type check accepts a matching bool arg (and isn't over-rejecting).
        var progBoolArg = "func needsBool(flag: bool): bool {\n    return !flag\n}\n\n" +
                          "func rightCall(x: int): bool {\n    return needsBool(x > 0)\n}\n";
        AssertColumnarProgramMatchesCSharp(progBoolArg,
            ("needsBool", new object[] { true }), ("needsBool", new object[] { false }),
            ("rightCall", new object[] { 5 }), ("rightCall", new object[] { -3 }));

        // A bool-returning CALL used as a condition (if isZero(n) { ... }).
        var prog3 = "func isZero(n: int): bool {\n    return n == 0\n}\n\n" +
                    "func classify(n: int): int {\n    if isZero(n) {\n        return 0\n    }\n    if n > 0 {\n        return 1\n    }\n    return 0 - 1\n}\n";
        AssertColumnarProgramMatchesCSharp(prog3,
            ("isZero", new object[] { 0 }), ("isZero", new object[] { 5 }),
            ("classify", new object[] { 0 }), ("classify", new object[] { 8 }), ("classify", new object[] { -3 }));

        // DECLINES (the type machinery / unsupported forms keep the C# path authoritative):
        // logical && is not lowered (short-circuit branch form) -> decline.
        Assert.False(RouteColumnarProgram("func f(a: int): bool {\n    return a > 0 && a < 10\n}\n").Ok);
        // a type mismatch (a bool value returned from an int function) -> the type-aware emitter declines it.
        Assert.False(RouteColumnarProgram("func g(a: int): int {\n    return a > 0\n}\n").Ok);
        // mixing a bool into int arithmetic (bool + int) -> decline (operands must be the same supported type).
        Assert.False(RouteColumnarProgram("func h(a: int): int {\n    flag := a > 0\n    return flag + 1\n}\n").Ok);
        // a CALL ARG type mismatch (int passed to a bool parameter) -> decline. int and bool are both i4, so
        // without the per-arg type check this would emit verifiable-but-wrong IL instead of declining.
        Assert.False(RouteColumnarProgram("func needsBool(flag: bool): bool {\n    return !flag\n}\n\nfunc caller(): bool {\n    return needsBool(5)\n}\n").Ok);
    }

    // Stage 4b-ii — `long` (i8), the first type with a distinct stack representation. Exercises long literals
    // (L suffix -> ldc.i8), long arithmetic/comparison/unary (same opcodes as int but i8), long
    // params/locals/returns, and VALUES BEYOND int range (proving it is genuinely i8, not i4). All vs the C# path.
    [Fact]
    public void ColumnarCodegen_Parity_LongType()
    {
        const long big = 1000000000L; // 1e9; big*big = 1e18 overflows int but fits long.
        var prog = "func addL(a: long, b: long): long {\n    return a + b\n}\n\n" +
                   "func mulL(a: long, b: long): long {\n    return a * b\n}\n\n" +
                   "func incL(a: long): long {\n    return a + 1L\n}\n\n" +
                   "func negL(a: long): long {\n    return -a\n}\n\n" +
                   "func answerL(): long {\n    return 42L\n}\n";
        AssertColumnarProgramMatchesCSharp(prog,
            ("addL", new object[] { big, big }), ("addL", new object[] { -5L, 5L }),
            ("mulL", new object[] { big, big }), ("mulL", new object[] { -7L, 8L }),
            ("incL", new object[] { big }), ("negL", new object[] { big }), ("answerL", System.Array.Empty<object>()));

        // long comparisons -> bool, a long `:=` local, and long factorial (factL(20) > int.MaxValue).
        var prog2 = "func ltL(a: long, b: long): bool {\n    return a < b\n}\n\n" +
                    "func eqL(a: long, b: long): bool {\n    return a == b\n}\n\n" +
                    "func twiceL(a: long): long {\n    x := a + 1L\n    return x * 2L\n}\n\n" +
                    "func factL(n: long): long {\n    if n <= 1L {\n        return 1L\n    }\n    return n * factL(n - 1L)\n}\n";
        AssertColumnarProgramMatchesCSharp(prog2,
            ("ltL", new object[] { 3L, 9L }), ("ltL", new object[] { 9L, 3L }), ("ltL", new object[] { big, big }),
            ("eqL", new object[] { big, big }), ("eqL", new object[] { 1L, 2L }),
            ("twiceL", new object[] { big }),
            ("factL", new object[] { 1L }), ("factL", new object[] { 13L }), ("factL", new object[] { 20L }));

        // DECLINES: mixed int/long (implicit widening not modelled) and unsigned ulong literal.
        Assert.False(RouteColumnarProgram("func mix(a: long): long {\n    return a + 1\n}\n").Ok);
        Assert.False(RouteColumnarProgram("func u(): ulong {\n    return 5\n}\n").Ok);
    }

    // Compile `source` BOTH ways, invoke `funcName` over each argument set, and assert the columnar
    // codegen result equals the authoritative C# ILCompiler result. Fails loudly if the columnar
    // path declined a function this gate expects it to emit -- a silent decline would make the parity
    // assertion vacuous.
    private static void AssertColumnarMatchesCSharp(string source, string funcName, params object[][] argSets)
    {
        var (ok, assembly, typeName, methodName) = RouteColumnarEmit(source);
        Assert.True(ok, $"Columnar codegen declined a function the parity gate expects it to emit:\n{source}");
        Assert.Equal(funcName, methodName);
        var columnarMethod = System.Reflection.Assembly.Load(assembly!).GetType(typeName!)!.GetMethod(methodName!)!;

        foreach (var args in argSets)
        {
            var columnar = columnarMethod.Invoke(null, args);
            var oracle = InvokeViaCSharpPath(source, funcName, args);
            Assert.Equal(oracle, columnar);
        }
    }

    // The authoritative oracle: compile `source` through the FULL production pipeline (MultiFileCompiler
    // -> ILCompiler, the path the columnar codegen will eventually replace -- not the raw ILCompiler,
    // which skips the binding/analysis passes that production runs) and invoke `funcName`.
    private static object? InvokeViaCSharpPath(string source, string funcName, object[] args)
    {
        var projectRoot = Path.Combine(Path.GetTempPath(), $"nsharp-columnar-parity-{Guid.NewGuid():N}");
        Directory.CreateDirectory(projectRoot);
        var programPath = Path.Combine(projectRoot, "Program.nl");
        var outputPath = Path.Combine(projectRoot, "bin", "ColumnarParity.dll");
        System.Runtime.Loader.AssemblyLoadContext? loadContext = null;
        try
        {
            File.WriteAllText(programPath, source);
            var config = ProjectFileParser.CreateDefault("ColumnarParity");
            config.OutputType = "library";
            config.TargetFramework = "net10.0";

            var compiler = new MultiFileCompiler(new[] { programPath }, projectRoot, config);
            var result = compiler.CompileToIlAssembly("ColumnarParity", outputPath);
            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(e => $"{e.DiagnosticId}: {e.Message}")));
            Assert.NotNull(result.OutputAssemblyPath);

            loadContext = new System.Runtime.Loader.AssemblyLoadContext($"ColumnarParity_{Guid.NewGuid():N}", isCollectible: true);
            var assembly = loadContext.LoadFromAssemblyPath(result.OutputAssemblyPath!);
            // Lowercase N# function names are file-private, so the C# path emits them non-public.
            var method = assembly.GetTypes()
                .Select(t => t.GetMethod(funcName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static))
                .FirstOrDefault(m => m != null)
                ?? throw new InvalidOperationException($"C# path did not emit a static method '{funcName}'.");
            return method.Invoke(null, args);
        }
        finally
        {
            loadContext?.Unload();
            if (Directory.Exists(projectRoot)) Directory.Delete(projectRoot, recursive: true);
        }
    }

    // Emit ALL of `source`'s functions into one columnar-program assembly, then for each (func, args) invoke the
    // columnar method and assert it equals the authoritative C# pipeline result. Fails loudly if the columnar
    // program path declined (a silent decline would make the parity assertion vacuous).
    private static void AssertColumnarProgramMatchesCSharp(string source, params (string Func, object[] Args)[] calls)
    {
        var (ok, assembly, typeName, methodNames) = RouteColumnarProgram(source);
        Assert.True(ok, $"Columnar program codegen declined a source the multi-function gate expects:\n{source}");
        var type = System.Reflection.Assembly.Load(assembly!).GetType(typeName!)!;
        foreach (var (func, args) in calls)
        {
            Assert.Contains(func, methodNames!);
            var columnar = type.GetMethod(func)!.Invoke(null, args);
            var oracle = InvokeViaCSharpPath(source, func, args);
            Assert.Equal(oracle, columnar);
        }
    }

    private static (bool Ok, byte[]? Assembly, string? TypeName, string[]? MethodNames) RouteColumnarProgram(string source)
    {
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");
        var method = adapterType.GetMethod("TryEmitColumnarProgram", BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryEmitColumnarProgram.");
        var args = new object?[] { source, null, null, null };
        var ok = (bool)(method.Invoke(null, args) ?? false);
        return (ok, (byte[]?)args[1], (string?)args[2], (string[]?)args[3]);
    }

    private static void AssertEmits(string source, string funcName, params (object[] Args, int Expected)[] cases)
    {
        var (ok, assembly, typeName, methodName) = RouteColumnarEmit(source);
        Assert.True(ok, $"Columnar codegen declined a supported spike function:\n{source}");
        Assert.Equal(funcName, methodName);
        var asm = System.Reflection.Assembly.Load(assembly!);
        var type = asm.GetType(typeName!);
        Assert.NotNull(type);
        var method = type!.GetMethod(methodName!);
        Assert.NotNull(method);
        foreach (var (args, expected) in cases)
            Assert.Equal(expected, (int)method!.Invoke(null, args)!);
    }

    private static (bool Ok, byte[]? Assembly, string? TypeName, string? MethodName) RouteColumnarEmit(string source)
    {
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");
        var method = adapterType.GetMethod("TryEmitColumnarFunction", BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryEmitColumnarFunction.");
        var args = new object?[] { source, null, null, null };
        var ok = (bool)(method.Invoke(null, args) ?? false);
        return (ok, (byte[]?)args[1], (string?)args[2], (string?)args[3]);
    }

    private static (bool Ok, List<List<ColumnarNameRef>>? Refs) RouteFunctionNameRefs(string source)
    {
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");
        var method = adapterType.GetMethod("TryResolveTopLevelFunctionNames", BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryResolveTopLevelFunctionNames.");
        var args = new object?[] { source, null };
        var ok = (bool)(method.Invoke(null, args) ?? false);
        return (ok, (List<List<ColumnarNameRef>>?)args[1]);
    }

    private static List<List<string>> ColumnarRefStrings(List<List<ColumnarNameRef>> perFunction)
        => perFunction.Select(fn => fn.Select(r => $"{r.Name}:{r.Kind}").ToList()).ToList();

    // The C# AST mirror of ColumnarNameResolver -- the EXACT same scoping + traversal order on the object-graph
    // AST, so the columnar resolution is verified identical. Produces per-function lists of "name:Kind".
    private static List<List<string>> CSharpResolveFunctionNames(string source, string filePath)
    {
        var cu = CSharpCompilationUnit(source, filePath);
        var funcs = cu!.Declarations.OfType<FunctionDeclaration>().ToList();
        var functionNames = new HashSet<string>(funcs.Select(f => f.Name), StringComparer.Ordinal);
        var result = new List<List<string>>();
        foreach (var fn in funcs)
        {
            var parameters = new HashSet<string>(fn.Parameters.Select(p => p.Name), StringComparer.Ordinal);
            var refs = new List<string>();
            var localScopes = new List<HashSet<string>>();

            string Classify(string name)
            {
                for (var i = localScopes.Count - 1; i >= 0; i--)
                    if (localScopes[i].Contains(name)) return "Local";
                if (parameters.Contains(name)) return "Parameter";
                if (functionNames.Contains(name)) return "Function";
                return "NotInScope";
            }

            void Expr(Expression e)
            {
                switch (e)
                {
                    case IdentifierExpression id: refs.Add($"{id.Name}:{Classify(id.Name)}"); break;
                    case ParenthesizedExpression p: Expr(p.Inner); break;
                    case MemberAccessExpression m: Expr(m.Object); break;
                    case CallExpression c:
                        Expr(c.Callee);
                        foreach (var a in c.Arguments) Expr(a.Value);
                        break;
                    case IndexAccessExpression ix: Expr(ix.Object); Expr(ix.Index); break;
                    case UnaryExpression u: Expr(u.Operand); break;
                    case BinaryExpression b: Expr(b.Left); Expr(b.Right); break;
                    case TernaryExpression t: Expr(t.Condition); Expr(t.ThenExpression); Expr(t.ElseExpression); break;
                    case AssignmentExpression a: Expr(a.Target); Expr(a.Value); break;
                    case NewExpression nw: foreach (var a in nw.ConstructorArguments) Expr(a.Value); break;
                    case CastExpression cast: Expr(cast.Expression); break;
                }
            }

            void Stmt(Statement s)
            {
                switch (s)
                {
                    case BlockStatement b:
                        localScopes.Add(new HashSet<string>(StringComparer.Ordinal));
                        foreach (var inner in b.Statements) Stmt(inner);
                        localScopes.RemoveAt(localScopes.Count - 1);
                        break;
                    case VariableDeclarationStatement v:
                        if (v.Initializer != null) Expr(v.Initializer);
                        if (localScopes.Count == 0) localScopes.Add(new HashSet<string>(StringComparer.Ordinal));
                        localScopes[localScopes.Count - 1].Add(v.Name);
                        break;
                    case WhileStatement w: Expr(w.Condition); Stmt(w.Body); break;
                    case IfStatement i:
                        Expr(i.Condition); Stmt(i.ThenStatement);
                        if (i.ElseStatement != null) Stmt(i.ElseStatement);
                        break;
                    case ReturnStatement r: if (r.Value != null) Expr(r.Value); break;
                    case ExpressionStatement es: Expr(es.Expression); break;
                }
            }

            if (fn.Body != null) Stmt(fn.Body);
            result.Add(refs);
        }

        return result;
    }

    private static (bool Ok, List<ColumnarFunctionSymbol>? Symbols) RouteFunctionSymbols(string source)
    {
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");
        var method = adapterType.GetMethod("TryBuildTopLevelFunctionSymbols", BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryBuildTopLevelFunctionSymbols.");
        var args = new object?[] { source, null };
        var ok = (bool)(method.Invoke(null, args) ?? false);
        return (ok, (List<ColumnarFunctionSymbol>?)args[1]);
    }

    private static List<string> CSharpFunctionSignatures(string source, string filePath)
    {
        var cu = CSharpCompilationUnit(source, filePath);
        var signatures = new List<string>();
        foreach (var fn in cu!.Declarations.OfType<FunctionDeclaration>())
        {
            var parameterTypes = fn.Parameters.Select(p => ColumnarFunctionSymbol.CanonicalType(p.Type)).ToList();
            var returnType = fn.ReturnType != null ? ColumnarFunctionSymbol.CanonicalType(fn.ReturnType) : null;
            signatures.Add(new ColumnarFunctionSymbol(fn.Name, (int)fn.Modifiers, parameterTypes, returnType).Signature());
        }

        return signatures;
    }

    // Invokes the internal NSharpCompilerDogfoodAdapter.TryParseCompilationUnit (the production routing entry)
    // reflectively, mirroring the other adapter tests in this file.
    private static (bool Ok, CompilationUnit? Unit) RouteCompilationUnit(string source, string? filePath)
    {
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");
        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var method = adapterType.GetMethod(
                "TryParseCompilationUnit",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryParseCompilationUnit.");
        var args = new object?[] { source, filePath, null };
        var ok = (bool)(method.Invoke(null, args) ?? false);
        return (ok, (CompilationUnit?)args[2]);
    }

    // The C# parser baseline. Routing is off by default (NSHARP_PARSER_FRONTEND unset), so this is always the
    // pure C# parse used as the parity reference.
    private static CompilationUnit? CSharpCompilationUnit(string source, string filePath)
        => new Parser(new Lexer(source, filePath).Tokenize(), filePath, source).ParseCompilationUnit().CompilationUnit;

    // Reflection serialization of an AST node identical to OutputFormatter's AstValueToJson, but SKIPPING
    // Line/Column (source positions differ for operator-keyed nodes between the materializer's span-start and
    // the C# parser's operator-token position; structural equivalence is what matters for the bridge).
    private static string StructuralJson(object? node)
    {
        var sb = new System.Text.StringBuilder();
        WriteStructural(sb, node);
        return sb.ToString();
    }

    private static void WriteStructural(System.Text.StringBuilder sb, object? value)
    {
        switch (value)
        {
            case null: sb.Append("null"); return;
            case string s: sb.Append('"').Append(s.Replace("\\", "\\\\").Replace("\"", "\\\"")).Append('"'); return;
            case bool b: sb.Append(b ? "true" : "false"); return;
            case Enum e: sb.Append(e.ToString()); return;
            case int i: sb.Append(i); return;
            case char c: sb.Append('\'').Append(c).Append('\''); return;
        }
        if (value is System.Collections.IEnumerable seq && value is not string)
        {
            sb.Append('[');
            var first = true;
            foreach (var item in seq) { if (!first) sb.Append(','); first = false; WriteStructural(sb, item); }
            sb.Append(']');
            return;
        }
        var type = value.GetType();
        sb.Append("{node:").Append(type.Name);
        foreach (var p in type.GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Where(p => p.GetIndexParameters().Length == 0 && p.Name != "EqualityContract" && p.Name != "Line" && p.Name != "Column" && p.Name != "Span" && p.Name != "NameSpan")
            .OrderBy(p => p.MetadataToken))
        {
            object? pv;
            try { pv = p.GetValue(value); } catch { continue; }
            sb.Append(',').Append(p.Name).Append(':');
            WriteStructural(sb, pv);
        }
        sb.Append('}');
    }

    // Parser slice 18: real-corpus expression pin. Validates the slice 10-15 expression kernel against the
    // production parser on REAL dogfood code (the anti-overfitting discipline the lexer's 108-file pin
    // established): every `return <expr>` value in the dogfood kernels whose expression stays within the
    // supported forms is parsed by ParseExpressionNodesInto and compared structurally to the C# AST. Files
    // whose recursively-collected return count does not match the `return` token count are skipped (a safety
    // net against an incomplete statement-container walk), so the pin never silently mis-pairs.
    [Fact]
    public void Parser_RealCorpusExpressions_MatchProductionParser()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(Path.GetTempPath(), $"NSharpLang.Compiler.Dogfood.RealExpr.{Guid.NewGuid():N}.dll");

        try
        {
            var result = new MultiFileCompiler(projectRoot, config)
                .CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);
            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(e => e.Message)));
            var assembly = Assembly.Load(File.ReadAllBytes(outputPath));
            var programType = assembly.GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var tokenize = programType.GetMethod("TokenizeMetadataWithIndentationInto", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;
            var parseExpr = programType.GetMethod("ParseExpressionNodesInto", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;

            var verified = 0;
            var skippedExprs = 0;
            var skippedFiles = 0;
            foreach (var file in Directory
                .EnumerateFiles(Path.Combine(projectRoot, "CompilerServices"), "*.nl")
                .OrderBy(p => p, StringComparer.Ordinal))
            {
                var src = File.ReadAllText(file);
                var cu = new Parser(new Lexer(src, file).Tokenize(), file).ParseCompilationUnit().CompilationUnit;
                if (cu == null) continue;

                var returns = new List<ReturnStatement>();
                foreach (var decl in cu.Declarations.OfType<FunctionDeclaration>())
                    if (decl.Body != null)
                        CollectReturnStatements(decl.Body, returns);

                var (count, kinds, starts, valueLengths, source) = TokenizeSourceViaKernel(src, tokenize);
                var returnTokenIndices = new List<int>();
                for (var i = 0; i < count; i++)
                    if (kinds[i] == 29) returnTokenIndices.Add(i);

                // Safety net: if our statement-container walk and the token scan disagree on the number of
                // returns, skip the whole file rather than risk mis-pairing.
                if (returnTokenIndices.Count != returns.Count) { skippedFiles++; continue; }

                for (var r = 0; r < returns.Count; r++)
                {
                    var value = returns[r].Value;
                    if (value == null || !IsSupportedExpr(value)) { skippedExprs++; continue; }

                    var (nodeCount, k, vs, vl, cstart, ccount, ci, ss, sl, res) =
                        InvokeParseExpr(parseExpr, kinds, starts, valueLengths, count, returnTokenIndices[r] + 1);
                    Assert.True(nodeCount > 0, $"Kernel refused real return expression in {file}.");
                    AssertExprNode(value, res[0], k, vs, vl, cstart, ccount, ci, source, $"{file}#return{r}");
                    verified++;
                }
            }

            // Meaningful coverage: the dogfood kernels contain many supported-form return expressions.
            Assert.True(verified > 50, $"Expected to verify >50 real return expressions, only verified {verified} (skipped {skippedExprs} exprs, {skippedFiles} files).");
        }
        finally
        {
            if (File.Exists(outputPath)) File.Delete(outputPath);
        }
    }

    // Recursively collect ReturnStatements in source order, descending into the statement containers the
    // dogfood kernels use. Containers not handled here cause a per-file count mismatch (then the file is
    // skipped), so a missed container can never silently mis-pair returns.
    private static void CollectReturnStatements(Statement statement, List<ReturnStatement> acc)
    {
        switch (statement)
        {
            case ReturnStatement r:
                acc.Add(r);
                break;
            case BlockStatement b:
                foreach (var s in b.Statements) CollectReturnStatements(s, acc);
                break;
            case IfStatement i:
                CollectReturnStatements(i.ThenStatement, acc);
                if (i.ElseStatement != null) CollectReturnStatements(i.ElseStatement, acc);
                break;
            case WhileStatement w:
                CollectReturnStatements(w.Body, acc);
                break;
            case ForStatement f:
                if (f.Initializer != null) CollectReturnStatements(f.Initializer, acc);
                CollectReturnStatements(f.Body, acc);
                break;
            case ForeachStatement fe:
                CollectReturnStatements(fe.Body, acc);
                break;
            default:
                break;
        }
    }

    private static bool IsSupportedExpr(Expression expr) => expr switch
    {
        IntLiteralExpression or FloatLiteralExpression or CharLiteralExpression or StringLiteralExpression
            or BoolLiteralExpression or NullLiteralExpression or IdentifierExpression => true,
        ParenthesizedExpression p => IsSupportedExpr(p.Inner),
        MemberAccessExpression m => !m.IsNullConditional && IsSupportedExpr(m.Object),
        IndexAccessExpression ix => !ix.IsNullConditional && IsSupportedExpr(ix.Object) && IsSupportedExpr(ix.Index),
        CallExpression c => (c.TypeArguments == null || c.TypeArguments.Count == 0)
            && IsSupportedExpr(c.Callee)
            && c.Arguments.All(a => a.Name == null && a.Modifier == ArgumentModifier.None && IsSupportedExpr(a.Value)),
        UnaryExpression u => u.Operator != UnaryOperator.PostIncrement && u.Operator != UnaryOperator.PostDecrement && IsSupportedExpr(u.Operand),
        BinaryExpression b => b.Operator != BinaryOperator.Range && IsSupportedExpr(b.Left) && IsSupportedExpr(b.Right),
        TernaryExpression t => IsSupportedExpr(t.Condition) && IsSupportedExpr(t.ThenExpression) && IsSupportedExpr(t.ElseExpression),
        AssignmentExpression a => IsSupportedExpr(a.Target) && IsSupportedExpr(a.Value),
        NewExpression n => n.Type != null && n.Initializer == null && n.ArrayLengthExpression == null
            && IsSupportedTypeForm(n.Type)
            && n.ConstructorArguments.All(a => a.Name == null && a.Modifier == ArgumentModifier.None && IsSupportedExpr(a.Value)),
        _ => false,
    };

    // Parser slices 16-17: the STATEMENT kernel. ParseStatementNodesInto (ParserStatements.nl) parses one
    // statement -- return / break / continue / expression-statement / `:=` declaration (slice 16) plus
    // blocks, while, and if/else (slice 17) -- composing the expression kernel into a shared node table
    // (statement kinds 20-27), pinned against the production parser's Statement AST (from a `func f() {...}`
    // body). if/while bodies recurse through the statement dispatcher (braceless or `{ }` block); else-if
    // chains as a nested if. Deferred: for/foreach, typed/let declarations, and the less-common statements.
    [Fact]
    public void Parser_Statement_MatchesProductionParser()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(
            Path.GetTempPath(),
            $"NSharpLang.Compiler.Dogfood.ParserStmt.{Guid.NewGuid():N}.dll");

        try
        {
            var result = new MultiFileCompiler(projectRoot, config)
                .CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);
            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(e => e.Message)));

            var assembly = Assembly.Load(File.ReadAllBytes(outputPath));
            var programType = assembly.GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var tokenize = programType.GetMethod(
                    "TokenizeMetadataWithIndentationInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeMetadataWithIndentationInto.");
            var parseStmt = programType.GetMethod(
                    "ParseStatementNodesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ParseStatementNodesInto.");

            string[] statements =
            {
                "return 5", "return", "return a + b", "return arr[i]", "return f(x) && g(y)",
                "break", "continue",
                "x := 0", "count := a + b", "result := f(x)", "node := arr[i].next",
                "total = total + 1", "arr[i] = value", "x += 1", "obj.field = y",
                "f(x)", "obj.method(a, b)", "queue.Enqueue(item)",
                // Control flow (slice 17): blocks, while, if/else, else-if, and nesting.
                "{ x = 1 }", "{ x = 1 y = 2 }",
                "while i < count { i = i + 1 }", "while x > 0 { x = x - 1 }",
                "if a { b = 1 }", "if cond { x = 1 } else { x = 2 }",
                "if a { return 1 } else { return 2 }",
                "if x < 0 { return -1 } else if x > 0 { return 1 } else { return 0 }",
                "while c { break }", "while c { if d { continue } x = 1 }",
                // Nested if inside a multi-statement while body -- stresses the block arg-stack under recursion.
                "while i < n { if arr[i] == target { return i } i = i + 1 }",
            };
            foreach (var stmt in statements)
                AssertStatementLikeProduction(stmt, tokenize, parseStmt);
        }
        finally
        {
            if (File.Exists(outputPath)) File.Delete(outputPath);
        }
    }

    private static void AssertStatementLikeProduction(string statementSource, MethodInfo tokenize, MethodInfo parseStmt)
    {
        var wrapper = "func f() { " + statementSource + " }";
        var tokens = new Lexer(wrapper, "s.nl").Tokenize();
        var compilationUnit = new Parser(tokens, "s.nl").ParseCompilationUnit().CompilationUnit;
        Assert.NotNull(compilationUnit);
        var fn = compilationUnit!.Declarations.OfType<FunctionDeclaration>().Single();
        Assert.True(fn.Body != null, $"No body for '{statementSource}'.");
        var stmt = fn.Body!.Statements.Single();

        var (count, kinds, starts, valueLengths, source) = TokenizeSourceViaKernel(wrapper, tokenize);
        // The statement begins one token after the function body's opening `{` (LeftBrace 129).
        var start = -1;
        for (var i = 0; i < count; i++)
        {
            if (kinds[i] == 129) { start = i + 1; break; }
        }
        Assert.True(start > 0, $"Could not locate body brace for '{statementSource}'.");

        var cap = count + 1;
        var k = new int[cap];
        var vs = new int[cap];
        var vl = new int[cap];
        var cstart = new int[cap];
        var ccount = new int[cap];
        var ci = new int[cap];
        var ss = new int[cap];
        var sl = new int[cap];
        var res = new int[2];
        var nodeCount = (int)(parseStmt.Invoke(
            null,
            new object[] { kinds, starts, valueLengths, count, start, k, vs, vl, cstart, ccount, ci, ss, sl, res }) ?? -2);

        Assert.True(nodeCount > 0, $"Kernel refused statement '{statementSource}'.");
        var root = res[0];
        Assert.Equal(nodeCount - 1, root);

        AssertStmtNode(stmt, root, k, vs, vl, cstart, ccount, ci, source, statementSource);

        // Full consumption: the statement ends at the body's closing `}` (RightBrace 130).
        Assert.True(res[1] < count && kinds[res[1]] == 130, $"Statement '{statementSource}' did not consume to the body close.");
    }

    private static void AssertStmtNode(
        Statement expected, int idx,
        int[] kinds, int[] valueStarts, int[] valueLengths, int[] childStart, int[] childCount, int[] childIndices,
        string source, string label)
    {
        switch (expected)
        {
            case ReturnStatement s:
                Assert.True(kinds[idx] == 20, $"Expected Return (20) at node {idx} for '{label}', got {kinds[idx]}.");
                if (s.Value == null)
                {
                    Assert.Equal(0, childCount[idx]);
                }
                else
                {
                    Assert.Equal(1, childCount[idx]);
                    AssertExprNode(s.Value, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                }
                break;
            case BreakStatement:
                Assert.True(kinds[idx] == 21, $"Expected Break (21) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(0, childCount[idx]);
                break;
            case ContinueStatement:
                Assert.True(kinds[idx] == 22, $"Expected Continue (22) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(0, childCount[idx]);
                break;
            case ExpressionStatement s:
                Assert.True(kinds[idx] == 23, $"Expected ExpressionStatement (23) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(1, childCount[idx]);
                AssertExprNode(s.Expression, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                break;
            case VariableDeclarationStatement s:
                Assert.True(kinds[idx] == 24, $"Expected VariableDeclaration (24) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(s.Name, source.Substring(valueStarts[idx], valueLengths[idx]));
                Assert.True(s.Type == null, $"Slice-16 kernel only handles `:=` shorthand (no type) for '{label}'.");
                Assert.True(s.Initializer != null, $"Production declaration has no initializer for '{label}'.");
                Assert.Equal(1, childCount[idx]);
                AssertExprNode(s.Initializer!, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                break;
            case BlockStatement s:
                Assert.True(kinds[idx] == 25, $"Expected Block (25) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(s.Statements.Count, childCount[idx]);
                for (var bi = 0; bi < s.Statements.Count; bi++)
                    AssertStmtNode(s.Statements[bi], childIndices[childStart[idx] + bi], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                break;
            case WhileStatement s:
                Assert.True(kinds[idx] == 26, $"Expected While (26) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(2, childCount[idx]);
                AssertExprNode(s.Condition, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                AssertStmtNode(s.Body, childIndices[childStart[idx] + 1], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                break;
            case IfStatement s:
                Assert.True(kinds[idx] == 27, $"Expected If (27) at node {idx} for '{label}', got {kinds[idx]}.");
                Assert.Equal(s.ElseStatement == null ? 2 : 3, childCount[idx]);
                AssertExprNode(s.Condition, childIndices[childStart[idx]], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                AssertStmtNode(s.ThenStatement, childIndices[childStart[idx] + 1], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                if (s.ElseStatement != null)
                    AssertStmtNode(s.ElseStatement, childIndices[childStart[idx] + 2], kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, label);
                break;
            default:
                Assert.Fail($"Unexpected production statement node {expected.GetType().Name} for '{label}' (out of slice-16/17 scope).");
                break;
        }
    }

    [Fact]
    public void Parser_RealCorpus_AstSerializesDeterministically()
    {
        var repoRoot = FindRepoRoot();
        var dirs = new[]
        {
            Path.Combine(repoRoot, "examples"),
            Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood", "CompilerServices"),
        };
        var files = dirs
            .Where(Directory.Exists)
            .SelectMany(dir => Directory.EnumerateFiles(dir, "*.nl", SearchOption.AllDirectories))
            .OrderBy(path => path, StringComparer.Ordinal)
            .ToArray();
        Assert.NotEmpty(files);

        foreach (var file in files)
        {
            var source = File.ReadAllText(file);
            var tokens = new Lexer(source, file).Tokenize();
            var parseResult = new Parser(tokens, file).ParseCompilationUnit();
            Assert.True(parseResult.CompilationUnit != null, $"Parser returned no CompilationUnit for {file}");

            var units = new[] { (file, parseResult.CompilationUnit!) };
            var json = OutputFormatter.AstToJson(units);

            using (var doc = JsonDocument.Parse(json))
            {
                Assert.Equal(1, doc.RootElement.GetProperty("schemaVersion").GetInt32());
                Assert.Equal("query.ast", doc.RootElement.GetProperty("command").GetString());
                var ast = doc.RootElement.GetProperty("files")[0].GetProperty("ast");
                Assert.Equal("CompilationUnit", ast.GetProperty("node").GetString());
            }

            // Stable schema: identical input must serialize byte-identically.
            Assert.Equal(json, OutputFormatter.AstToJson(units));
        }
    }

    [Fact]
    public void CodeIntelligenceDogfoodAdapter_LoadsPackagedNSharpAssembly()
    {
        var source = """
func main() {
    value := input.Count

    print value
}
""";
        var filePath = Path.GetFullPath(Path.Combine(Path.GetTempPath(), $"dogfood-adapter-{Guid.NewGuid():N}.nl"));
        var snapshot = new ProjectSnapshot(
            Path.GetTempPath(),
            new Dictionary<string, CompilationUnit>(),
            new Dictionary<string, SemanticModel>(),
            Array.Empty<CompilerError>(),
            new Analyzer(),
            new[] { filePath },
            sourceTexts: new Dictionary<string, string> { [filePath] = source });

        var adapterType = typeof(CodeIntelligenceService).Assembly.GetType(
                "NSharpLang.Compiler.CodeIntelligence.NSharpCodeIntelligenceDogfoodAdapter")
            ?? throw new InvalidOperationException("Dogfood code-intelligence adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var semanticModel = new SemanticModel();
        var rootScope = semanticModel.OpenScope(-1, 1, 1);
        semanticModel.RecordScopedVariable(rootScope, "x", BuiltInTypes.Int);
        semanticModel.RecordScopedVariable(rootScope, "y", BuiltInTypes.String);
        var innerScope = semanticModel.OpenScope(rootScope, 4, 1);
        semanticModel.RecordScopedVariable(innerScope, "x", BuiltInTypes.Bool);
        semanticModel.RecordScopedVariable(innerScope, "z", BuiltInTypes.Double);
        semanticModel.CloseScope(innerScope, 8, 120);
        semanticModel.CloseScope(rootScope, 12, 120);
        semanticModel.RecordProperty("Name", BuiltInTypes.String);

        var tryGetVisibleVariablesAtPosition = adapterType.GetMethod(
                "TryGetVisibleVariablesAtPosition",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryGetVisibleVariablesAtPosition.");
        var visibleArgs = new object?[] { semanticModel, 5, 10, null };
        Assert.True((bool)(tryGetVisibleVariablesAtPosition.Invoke(null, visibleArgs) ?? false));
        var visibleVariables = Assert.IsType<Dictionary<string, NSharpLang.Compiler.TypeInfo>>(visibleArgs[3]);
        Assert.Equal("bool", visibleVariables["x"].ToString());
        Assert.Equal("string", visibleVariables["y"].ToString());
        Assert.Equal("double", visibleVariables["z"].ToString());

        var tryLookupIdentifierAtPosition = adapterType.GetMethod(
                "TryLookupIdentifierAtPosition",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryLookupIdentifierAtPosition.");

        var innerLookupArgs = new object?[] { semanticModel, "x", 5, 10, null };
        Assert.True((bool)(tryLookupIdentifierAtPosition.Invoke(null, innerLookupArgs) ?? false));
        Assert.Equal("bool", innerLookupArgs[4]?.ToString());

        var outerLookupArgs = new object?[] { semanticModel, "y", 5, 10, null };
        Assert.True((bool)(tryLookupIdentifierAtPosition.Invoke(null, outerLookupArgs) ?? false));
        Assert.Equal("string", outerLookupArgs[4]?.ToString());

        var propertyLookupArgs = new object?[] { semanticModel, "Name", 5, 10, null };
        Assert.True((bool)(tryLookupIdentifierAtPosition.Invoke(null, propertyLookupArgs) ?? false));
        Assert.Equal("string", propertyLookupArgs[4]?.ToString());

        var missingLookupArgs = new object?[] { semanticModel, "missing", 5, 10, null };
        Assert.True((bool)(tryLookupIdentifierAtPosition.Invoke(null, missingLookupArgs) ?? false));
        Assert.Null(missingLookupArgs[4]);

        var tryExtractIdentifierName = adapterType.GetMethod(
                "TryExtractIdentifierName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractIdentifierName.");
        var identifierArgs = new object?[] { snapshot, filePath, source, 2, 15, null };
        Assert.True((bool)(tryExtractIdentifierName.Invoke(null, identifierArgs) ?? false));
        Assert.Equal("input", identifierArgs[5]);

        var tryExtractEditorIdentifierSpan = adapterType.GetMethod(
                "TryExtractEditorIdentifierSpan",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractEditorIdentifierSpan.");
        var editorSpanArgs = new object?[] { source, 2, 15, null };
        Assert.True((bool)(tryExtractEditorIdentifierSpan.Invoke(null, editorSpanArgs) ?? false));
        var editorSpan = Assert.IsType<ValueTuple<int, int, string>>(editorSpanArgs[3]);
        Assert.Equal(14, editorSpan.Item1);
        Assert.Equal(18, editorSpan.Item2);
        Assert.Equal("input", editorSpan.Item3);

        var editorPunctuationArgs = new object?[] { source, 2, 19, null };
        Assert.True((bool)(tryExtractEditorIdentifierSpan.Invoke(null, editorPunctuationArgs) ?? false));
        Assert.Null(editorPunctuationArgs[3]);

        Assert.True(CodeIntelligenceTextUtilities.TryGetEditorIdentifierSpanAtPosition(source, 1, 14, out var publicEditorSpan));
        Assert.Equal("input", publicEditorSpan.Name);
        Assert.Equal(13, publicEditorSpan.StartCharacter);
        Assert.Equal(18, publicEditorSpan.EndCharacter);
        Assert.Equal("Count", CodeIntelligenceTextUtilities.GetEditorWordAtPosition(source, 1, 999));
        Assert.False(CodeIntelligenceTextUtilities.TryGetEditorIdentifierSpanAtPosition(source, 1, 18, out _));

        var trySelectedSpanMatchesDeclarationName = adapterType.GetMethod(
                "TrySelectedSpanMatchesDeclarationName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TrySelectedSpanMatchesDeclarationName.");
        var declarationMatchArgs = new object?[] { snapshot, filePath, source, 2, 5, "value", 5, 9, null };
        Assert.True((bool)(trySelectedSpanMatchesDeclarationName.Invoke(null, declarationMatchArgs) ?? false));
        Assert.Equal(true, declarationMatchArgs[8]);

        var declarationMismatchArgs = new object?[] { snapshot, filePath, source, 2, 5, "value", 14, 18, null };
        Assert.True((bool)(trySelectedSpanMatchesDeclarationName.Invoke(null, declarationMismatchArgs) ?? false));
        Assert.Equal(false, declarationMismatchArgs[8]);

        var tryFindIdentifierNameColumn = adapterType.GetMethod(
                "TryFindIdentifierNameColumn",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryFindIdentifierNameColumn.");
        var declarationColumnArgs = new object?[] { source, "value", 2, 1, 0 };
        Assert.True((bool)(tryFindIdentifierNameColumn.Invoke(null, declarationColumnArgs) ?? false));
        Assert.Equal(5, declarationColumnArgs[4]);

        var tryExtractMemberReceiverName = adapterType.GetMethod(
                "TryExtractMemberReceiverName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractMemberReceiverName.");
        var receiverArgs = new object?[] { snapshot, filePath, source, 2, 20, null };
        Assert.True((bool)(tryExtractMemberReceiverName.Invoke(null, receiverArgs) ?? false));
        Assert.Equal("input", receiverArgs[5]);

        var tryExtractSourceContext = adapterType.GetMethod(
                "TryExtractSourceContext",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractSourceContext.");

        var contextArgs = new object?[] { snapshot, filePath, source, 2, null };
        Assert.True((bool)(tryExtractSourceContext.Invoke(null, contextArgs) ?? false));
        Assert.Equal("value := input.Count", contextArgs[4]);

        var blankContextArgs = new object?[] { snapshot, filePath, source, 3, null };
        Assert.True((bool)(tryExtractSourceContext.Invoke(null, blankContextArgs) ?? false));
        Assert.Equal(string.Empty, blankContextArgs[4]);

        var tryExtractSourceLine = adapterType.GetMethod(
                "TryExtractSourceLine",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[] { typeof(ProjectSnapshot), typeof(string), typeof(string), typeof(int), typeof(string).MakeByRefType() },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit snapshot TryExtractSourceLine.");

        var rawLineArgs = new object?[] { snapshot, filePath, source, 2, null };
        Assert.True((bool)(tryExtractSourceLine.Invoke(null, rawLineArgs) ?? false));
        Assert.Equal("    value := input.Count", rawLineArgs[4]);

        var blankLineArgs = new object?[] { snapshot, filePath, source, 3, null };
        Assert.True((bool)(tryExtractSourceLine.Invoke(null, blankLineArgs) ?? false));
        Assert.Equal(string.Empty, blankLineArgs[4]);

        var tryExtractDocComment = adapterType.GetMethod(
                "TryExtractDocComment",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractDocComment.");

        var docSource = """
// First line
//   Second line~~

func documented(): int {
    return 1
}
""".Replace('~', ' ');
        var docFilePath = Path.GetFullPath(Path.Combine(Path.GetTempPath(), $"dogfood-adapter-doc-{Guid.NewGuid():N}.nl"));
        var docCommentArgs = new object?[] { snapshot, docFilePath, docSource, 4, null };
        Assert.True((bool)(tryExtractDocComment.Invoke(null, docCommentArgs) ?? false));
        Assert.Equal("First line\nSecond line", docCommentArgs[4]);

        var tryExtractCompletionPrefix = adapterType.GetMethod(
                "TryExtractCompletionPrefix",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[] { typeof(ProjectSnapshot), typeof(string), typeof(string), typeof(int), typeof(int), typeof(string).MakeByRefType() },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractCompletionPrefix.");

        var prefixArgs = new object?[] { snapshot, filePath, source, 2, 9, null };
        Assert.True((bool)(tryExtractCompletionPrefix.Invoke(null, prefixArgs) ?? false));
        Assert.Equal("    value", prefixArgs[5]);

        var pastEndPrefixArgs = new object?[] { snapshot, filePath, source, 2, 999, null };
        Assert.True((bool)(tryExtractCompletionPrefix.Invoke(null, pastEndPrefixArgs) ?? false));
        Assert.Equal("    value := input.Count", pastEndPrefixArgs[5]);

        var tryClassifyCompletionReceiver = adapterType.GetMethod(
                "TryClassifyCompletionReceiver",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[] { typeof(string), typeof(bool).MakeByRefType(), typeof(string).MakeByRefType() },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryClassifyCompletionReceiver.");

        var completionReceiverArgs = new object?[] { "    factory.Create(name).", null, null };
        Assert.True((bool)(tryClassifyCompletionReceiver.Invoke(null, completionReceiverArgs) ?? false));
        Assert.Equal(true, completionReceiverArgs[1]);
        Assert.Equal("factory.Create()", completionReceiverArgs[2]);

        var identifierCompletionArgs = new object?[] { "    return value", null, null };
        Assert.True((bool)(tryClassifyCompletionReceiver.Invoke(null, identifierCompletionArgs) ?? false));
        Assert.Equal(false, identifierCompletionArgs[1]);
        Assert.Null(identifierCompletionArgs[2]);

        var tryAddGroupedCompletionItemsByKind = adapterType.GetMethod(
                "TryAddGroupedCompletionItemsByKind",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryAddGroupedCompletionItemsByKind.");
        var completionItems = new List<CompletionItem>
        {
            new("WriteLine", "method", "void", "()", null, true),
            new("Length", "property", "int", null, null, false),
            new("ToString", "method", "string", "()", null, false),
            new("MaxValue", "field", "int", null, null, true),
            new("Count", "property", "int", null, null, false)
        };
        var groupedCompletions = new Dictionary<string, List<CompletionItem>>();
        var groupingAdapterArgs = new object?[] { completionItems, groupedCompletions };
        Assert.True((bool)(tryAddGroupedCompletionItemsByKind.Invoke(null, groupingAdapterArgs) ?? false));
        Assert.Equal(new[] { "methods", "properties", "fields" }, groupedCompletions.Keys.ToArray());
        Assert.Equal(new[] { "WriteLine", "ToString" }, groupedCompletions["methods"].Select(static item => item.Name));
        Assert.Equal(new[] { "Length", "Count" }, groupedCompletions["properties"].Select(static item => item.Name));
        Assert.Equal("MaxValue", Assert.Single(groupedCompletions["fields"]).Name);

        var tryGroupReflectionMethodsByName = adapterType.GetMethod(
                "TryGroupReflectionMethodsByName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryGroupReflectionMethodsByName.");
        var completionMethods = typeof(CompletionMethodGroupingFixture).GetMethods(
            BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);
        var methodGroupingArgs = new object?[] { completionMethods, null };
        Assert.True((bool)(tryGroupReflectionMethodsByName.Invoke(null, methodGroupingArgs) ?? false));
        var methodGrouping = methodGroupingArgs[1]
            ?? throw new InvalidOperationException("Dogfood adapter did not return method grouping.");
        var methodGroupingType = methodGrouping.GetType();
        var expectedMethodGroups = completionMethods
            .Where(static method => !method.IsSpecialName && method.DeclaringType?.FullName != "System.Object")
            .GroupBy(static method => method.Name)
            .ToList();
        var methodGroupCount = (int)(methodGroupingType.GetProperty("GroupCount")?.GetValue(methodGrouping) ?? -1);
        var methodNameIds = Assert.IsType<int[]>(methodGroupingType.GetProperty("NameIds")?.GetValue(methodGrouping));
        var methodFirstIndices = Assert.IsType<int[]>(methodGroupingType.GetProperty("FirstIndices")?.GetValue(methodGrouping));
        var methodCounts = Assert.IsType<int[]>(methodGroupingType.GetProperty("Counts")?.GetValue(methodGrouping));
        Assert.Equal(expectedMethodGroups.Count, methodGroupCount);
        for (var groupIndex = 0; groupIndex < expectedMethodGroups.Count; groupIndex++)
        {
            var expectedGroup = expectedMethodGroups[groupIndex];
            Assert.True(methodNameIds[groupIndex] > 0);
            Assert.Equal(expectedGroup.Key, completionMethods[methodFirstIndices[groupIndex]].Name);
            Assert.Equal(Array.IndexOf(completionMethods, expectedGroup.First()), methodFirstIndices[groupIndex]);
            Assert.Equal(expectedGroup.Count(), methodCounts[groupIndex]);
        }

        var tryExtractVariableDeclarationName = adapterType.GetMethod(
                "TryExtractVariableDeclarationName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractVariableDeclarationName.");

        var variableNameArgs = new object?[] { snapshot, filePath, source, 2, null };
        Assert.True((bool)(tryExtractVariableDeclarationName.Invoke(null, variableNameArgs) ?? false));
        Assert.Equal("value", variableNameArgs[4]);

        var noVariableNameArgs = new object?[] { snapshot, filePath, source, 3, null };
        Assert.True((bool)(tryExtractVariableDeclarationName.Invoke(null, noVariableNameArgs) ?? false));
        Assert.Null(noVariableNameArgs[4]);

        var tryClassifyDiagnosticClusterTraits = adapterType.GetMethod(
                "TryClassifyDiagnosticClusterTraits",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryClassifyDiagnosticClusterTraits.");
        var diagnostics = BuildDiagnosticClusterTraitDiagnostics();
        var classificationArgs = new object?[] { diagnostics, null, null };
        Assert.True((bool)(tryClassifyDiagnosticClusterTraits.Invoke(null, classificationArgs) ?? false));
        Assert.Equal(new[] { 1, 0, 2, 3, 4, 5, 6, 7 }, Assert.IsType<int[]>(classificationArgs[1]));
        Assert.Equal(new[] { 1, 0, 4, 0, 2, 5, 7, 8 }, Assert.IsType<int[]>(classificationArgs[2]));

        var tryGroupDiagnosticClusters = adapterType.GetMethod(
                "TryGroupDiagnosticClusters",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryGroupDiagnosticClusters.");
        var groupingDiagnostics = new List<DiagnosticResult>
        {
            BuildDiagnosticWithSeverity("error", 10) with
            {
                Code = "NL102",
                File = "B.nl",
                Column = 5,
                Message = "Expected token '}'"
            },
            BuildDiagnosticWithSeverity("error", 8) with
            {
                Code = "NL102",
                File = "A.nl",
                Column = 3,
                Message = "Expected token '}'"
            },
            BuildDiagnosticWithSeverity("warning", 1) with
            {
                Code = "NL301",
                File = "C.nl",
                Column = 1,
                Message = "Undefined variable 'value'"
            }
        };
        var groupingArgs = new object?[]
        {
            groupingDiagnostics,
            new[] { 1, 1, 3 },
            new[] { 0, 0, 0 },
            new[] { "Expected token {value}", "Expected token {value}", "Undefined variable {value}" },
            null
        };
        Assert.True((bool)(tryGroupDiagnosticClusters.Invoke(null, groupingArgs) ?? false));
        var grouping = groupingArgs[4] ?? throw new InvalidOperationException("Dogfood adapter did not return a grouping result.");
        var groupingType = grouping.GetType();
        Assert.Equal(2, (int)(groupingType.GetProperty("GroupCount")?.GetValue(grouping) ?? -1));
        Assert.Equal(new[] { 1, 2 }, Assert.IsType<int[]>(groupingType.GetProperty("RootIndices")?.GetValue(grouping)).Take(2));
        Assert.Equal(new[] { 2, 1 }, Assert.IsType<int[]>(groupingType.GetProperty("Counts")?.GetValue(grouping)).Take(2));
        Assert.Equal(new[] { 0, 2 }, Assert.IsType<int[]>(groupingType.GetProperty("MemberStarts")?.GetValue(grouping)).Take(2));
        Assert.Equal(new[] { 1, 0, 2 }, Assert.IsType<int[]>(groupingType.GetProperty("MemberIndices")?.GetValue(grouping)).Take(3));

        var tryDeduplicateDiagnostics = adapterType.GetMethod(
                "TryDeduplicateDiagnostics",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateDiagnostics.");
        var deduplicationDiagnostics = new List<DiagnosticResult>
        {
            BuildDiagnosticWithSeverity("error", 10) with
            {
                Code = "NL102",
                File = "B.nl",
                Column = 5,
                Message = "Expected token '}'",
                SourceSnippet = "first duplicate wins"
            },
            BuildDiagnosticWithSeverity("error", 2) with
            {
                Code = "NL301",
                File = "A.nl",
                Column = 3,
                Message = "Undefined variable 'value'"
            },
            BuildDiagnosticWithSeverity("error", 10) with
            {
                Code = "NL102",
                File = "B.nl",
                Column = 5,
                Message = "Expected token '}'",
                SourceSnippet = "duplicate should be ignored"
            },
            BuildDiagnosticWithSeverity("warning", 2) with
            {
                Code = "NL201",
                File = "A.nl",
                Column = 1,
                Message = "Type is inferred"
            },
            BuildDiagnosticWithSeverity("error", 2) with
            {
                Code = "NL301",
                File = "A.nl",
                Column = 3,
                Message = "Undefined variable 'value'"
            }
        };
        var deduplicationArgs = new object?[] { deduplicationDiagnostics, null, null };
        Assert.True((bool)(tryDeduplicateDiagnostics.Invoke(null, deduplicationArgs) ?? false));
        Assert.Equal(3, Assert.IsType<int>(deduplicationArgs[2]));
        Assert.Equal(new[] { 3, 1, 0 }, Assert.IsType<int[]>(deduplicationArgs[1]).Take(3));

        var tryDeduplicateDiagnosticsPreservingOrder = adapterType.GetMethod(
                "TryDeduplicateDiagnosticsPreservingOrder",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateDiagnosticsPreservingOrder.");
        var stableDeduplicationArgs = new object?[] { deduplicationDiagnostics, null, null };
        Assert.True((bool)(tryDeduplicateDiagnosticsPreservingOrder.Invoke(null, stableDeduplicationArgs) ?? false));
        Assert.Equal(3, Assert.IsType<int>(stableDeduplicationArgs[2]));
        Assert.Equal(new[] { 0, 1, 3 }, Assert.IsType<int[]>(stableDeduplicationArgs[1]).Take(3));

        var tryDeduplicateReferences = adapterType.GetMethod(
                "TryDeduplicateReferences",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateReferences.");
        var references = new List<ReferenceResult>
        {
            new("B.nl", 10, 5, 5, "first duplicate wins", IsDefinition: true),
            new("A.nl", 2, 3, 5, "first A reference", IsDefinition: false),
            new("B.nl", 10, 5, 5, "duplicate should be ignored", IsDefinition: false),
            new("A.nl", 2, 1, 5, "earlier column sorts first", IsDefinition: false),
            new("A.nl", 2, 3, 5, "duplicate A reference", IsDefinition: false)
        };
        var referenceDeduplicationArgs = new object?[] { references, null, null };
        Assert.True((bool)(tryDeduplicateReferences.Invoke(null, referenceDeduplicationArgs) ?? false));
        Assert.Equal(3, Assert.IsType<int>(referenceDeduplicationArgs[2]));
        Assert.Equal(new[] { 3, 1, 0 }, Assert.IsType<int[]>(referenceDeduplicationArgs[1]).Take(3));

        var tryBuildInspectSummaryReferenceFiles = adapterType.GetMethod(
                "TryBuildInspectSummaryReferenceFiles",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryBuildInspectSummaryReferenceFiles.");
        var summaryReferences = new List<ReferenceResult>
        {
            new(@"src\B.nl", 10, 5, 5, "B reference", IsDefinition: true),
            new("src/A.nl", 2, 3, 5, "A reference", IsDefinition: false),
            new("src/B.nl", 12, 5, 5, "normalized duplicate", IsDefinition: false),
            new(@"src\C.nl", 4, 1, 5, "C reference", IsDefinition: false),
            new("src/A.nl", 2, 8, 5, "duplicate A", IsDefinition: false)
        };
        var referenceFileSummaryArgs = new object?[] { summaryReferences, null };
        Assert.True((bool)(tryBuildInspectSummaryReferenceFiles.Invoke(null, referenceFileSummaryArgs) ?? false));
        Assert.Equal(
            summaryReferences
                .Select(reference => reference.File.Replace('\\', '/'))
                .Distinct(StringComparer.Ordinal)
                .OrderBy(file => file, StringComparer.Ordinal)
                .ToArray(),
            Assert.IsType<string[]>(referenceFileSummaryArgs[1]));

        var tryBuildDiagnosticClusterFiles = adapterType.GetMethod(
                "TryBuildDiagnosticClusterFiles",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryBuildDiagnosticClusterFiles.");
        var clusterDiagnostics = new List<DiagnosticResult>
        {
            BuildDiagnosticWithSeverity("error", 1) with { File = "src/B.nl" },
            BuildDiagnosticWithSeverity("error", 2) with { File = "src/a.nl" },
            BuildDiagnosticWithSeverity("error", 3) with { File = "SRC/A.NL" },
            BuildDiagnosticWithSeverity("error", 4) with { File = "src/C.nl" },
            BuildDiagnosticWithSeverity("error", 5) with { File = "src/b.NL" }
        };
        var diagnosticClusterFileArgs = new object?[] { clusterDiagnostics, null };
        Assert.True((bool)(tryBuildDiagnosticClusterFiles.Invoke(null, diagnosticClusterFileArgs) ?? false));
        Assert.Equal(
            clusterDiagnostics
                .Select(diagnostic => diagnostic.File)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(file => file, StringComparer.OrdinalIgnoreCase)
                .ToArray(),
            Assert.IsType<string[]>(diagnosticClusterFileArgs[1]));

        var tryGetBindingCandidateColumns = adapterType.GetMethod(
                "TryGetBindingCandidateColumns",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[]
                {
                    typeof(int),
                    typeof(Nullable<ValueTuple<int, int>>),
                    typeof(int[]).MakeByRefType()
                },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryGetBindingCandidateColumns.");
        var candidateColumnArgs = new object?[] { 5, (ValueTuple<int, int>?)new ValueTuple<int, int>(3, 7), null };
        Assert.True((bool)(tryGetBindingCandidateColumns.Invoke(null, candidateColumnArgs) ?? false));
        Assert.Equal(new[] { 5, 4, 6, 3, 7 }, Assert.IsType<int[]>(candidateColumnArgs[2]));

        var noSpanCandidateColumnArgs = new object?[] { 1, null, null };
        Assert.True((bool)(tryGetBindingCandidateColumns.Invoke(null, noSpanCandidateColumnArgs) ?? false));
        Assert.Equal(new[] { 1, 2 }, Assert.IsType<int[]>(noSpanCandidateColumnArgs[2]));

        var tryResolveBindingDeclaration = adapterType.GetMethod(
                "TryResolveBindingDeclaration",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[]
                {
                    typeof(BindingMap),
                    typeof(string),
                    typeof(int),
                    typeof(int[]),
                    typeof(SymbolDeclaration).MakeByRefType()
                },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryResolveBindingDeclaration.");
        var bindingMap = new BindingMap();
        var bDeclaration = new SymbolDeclaration("bValue", "B.nl", 10, 5, "variable");
        var aDeclaration = new SymbolDeclaration("aValue", "A.nl", 2, 3, "variable");
        bindingMap.RecordDeclaration(bDeclaration);
        bindingMap.RecordDeclaration(aDeclaration);
        bindingMap.RecordBinding("A.nl", 7, 9, 6, bDeclaration);
        bindingMap.RecordBinding("A.nl", 2, 3, 6, bDeclaration);

        var bindingUsageArgs = new object?[] { bindingMap, "A.nl", 7, new[] { 9 }, null };
        Assert.True((bool)(tryResolveBindingDeclaration.Invoke(null, bindingUsageArgs) ?? false));
        Assert.Equal(bDeclaration, Assert.IsType<SymbolDeclaration>(bindingUsageArgs[4]));

        var bindingDeclarationFirstArgs = new object?[] { bindingMap, "A.nl", 2, new[] { 3 }, null };
        Assert.True((bool)(tryResolveBindingDeclaration.Invoke(null, bindingDeclarationFirstArgs) ?? false));
        Assert.Equal(aDeclaration, Assert.IsType<SymbolDeclaration>(bindingDeclarationFirstArgs[4]));

        var bindingMissArgs = new object?[] { bindingMap, "A.nl", 99, new[] { 1, 2, 3 }, null };
        Assert.True((bool)(tryResolveBindingDeclaration.Invoke(null, bindingMissArgs) ?? false));
        Assert.Null(bindingMissArgs[4]);

        var tryFindNearestBindingDeclarationByName = adapterType.GetMethod(
                "TryFindNearestBindingDeclarationByName",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[]
                {
                    typeof(BindingMap),
                    typeof(string),
                    typeof(string),
                    typeof(int),
                    typeof(SymbolDeclaration).MakeByRefType()
                },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryFindNearestBindingDeclarationByName.");
        var firstLocal = new SymbolDeclaration("local", "A.nl", 2, 3, "variable");
        var earlierSameLineLocal = new SymbolDeclaration("local", "A.nl", 8, 1, "variable");
        var nearestLocal = new SymbolDeclaration("local", "A.nl", 8, 4, "variable");
        var otherFileLocal = new SymbolDeclaration("local", "B.nl", 20, 1, "variable");
        bindingMap.RecordDeclaration(firstLocal);
        bindingMap.RecordDeclaration(earlierSameLineLocal);
        bindingMap.RecordDeclaration(nearestLocal);
        bindingMap.RecordDeclaration(otherFileLocal);

        var nearestAtLineArgs = new object?[] { bindingMap, "A.nl", "local", 8, null };
        Assert.True((bool)(tryFindNearestBindingDeclarationByName.Invoke(null, nearestAtLineArgs) ?? false));
        Assert.Equal(nearestLocal, Assert.IsType<SymbolDeclaration>(nearestAtLineArgs[4]));

        var nearestBeforeLineArgs = new object?[] { bindingMap, "A.nl", "local", 7, null };
        Assert.True((bool)(tryFindNearestBindingDeclarationByName.Invoke(null, nearestBeforeLineArgs) ?? false));
        Assert.Equal(firstLocal, Assert.IsType<SymbolDeclaration>(nearestBeforeLineArgs[4]));

        var nearestMissArgs = new object?[] { bindingMap, "A.nl", "local", 1, null };
        Assert.True((bool)(tryFindNearestBindingDeclarationByName.Invoke(null, nearestMissArgs) ?? false));
        Assert.Null(nearestMissArgs[4]);

        var unknownNameArgs = new object?[] { bindingMap, "A.nl", "missing", 99, null };
        Assert.True((bool)(tryFindNearestBindingDeclarationByName.Invoke(null, unknownNameArgs) ?? false));
        Assert.Null(unknownNameArgs[4]);

        var trySummarizeDiagnosticSeverities = adapterType.GetMethod(
                "TrySummarizeDiagnosticSeverities",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TrySummarizeDiagnosticSeverities.");
        var summaryArgs = new object?[] { BuildDiagnosticSeveritySummaryDiagnostics(), null };
        Assert.True((bool)(trySummarizeDiagnosticSeverities.Invoke(null, summaryArgs) ?? false));
        var summary = Assert.IsType<DiagnosticSummary>(summaryArgs[1]);
        Assert.Equal(2, summary.Errors);
        Assert.Equal(1, summary.Warnings);
        Assert.Equal(2, summary.Info);

        var trySuppressLintShadowingDiagnostics = adapterType.GetMethod(
                "TrySuppressLintShadowingDiagnostics",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TrySuppressLintShadowingDiagnostics.");
        var shadowDiagnostics = BuildDiagnosticShadowSuppressionDiagnostics();
        var shadowedFiles = new[] { "SRC/a.nl", "src/c.nl", "src/c.nl" };
        var shadowArgs = new object?[] { shadowDiagnostics, shadowedFiles, null, 0 };
        Assert.True((bool)(trySuppressLintShadowingDiagnostics.Invoke(null, shadowArgs) ?? false));
        var shadowIndices = Assert.IsType<int[]>(shadowArgs[2]);
        var shadowCount = Assert.IsType<int>(shadowArgs[3]);
        var expectedShadowIndices = ExpectedDiagnosticShadowSuppressionIndices(shadowDiagnostics, shadowedFiles);
        Assert.Equal(expectedShadowIndices, shadowIndices.Take(shadowCount).ToArray());

        var tryFilterSymbolsByKind = adapterType.GetMethod(
                "TryFilterSymbolsByKind",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryFilterSymbolsByKind.");
        var symbols = BuildSymbolKindFilterSymbols();
        var filterArgs = new object?[] { symbols, SymbolKind.Function, null };
        Assert.True((bool)(tryFilterSymbolsByKind.Invoke(null, filterArgs) ?? false));
        var filteredSymbols = Assert.IsType<List<SymbolResult>>(filterArgs[2]);
        Assert.Equal(
            symbols.Where(symbol => symbol.Kind == SymbolKind.Function).Select(symbol => symbol.Name),
            filteredSymbols.Select(symbol => symbol.Name));
    }

    [Fact]
    public void CodeIntelligenceDogfoodAdapter_DeduplicatesStableStringsOrdinalIgnoreCase()
    {
        var adapterType = typeof(CodeIntelligenceService).Assembly.GetType(
                "NSharpLang.Compiler.CodeIntelligence.NSharpCodeIntelligenceDogfoodAdapter")
            ?? throw new InvalidOperationException("Dogfood code-intelligence adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryDeduplicateStableStrings = adapterType.GetMethod(
                "TryDeduplicateStableStringsOrdinalIgnoreCase",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateStableStringsOrdinalIgnoreCase.");
        var names = new[]
        {
            "System.Console",
            "system.console",
            "System.Text.Json",
            "SYSTEM.TEXT.JSON",
            "Custom.Library"
        };
        var args = new object?[] { names, null };

        Assert.True((bool)(tryDeduplicateStableStrings.Invoke(null, args) ?? false));
        Assert.Equal(
            new[] { "System.Console", "System.Text.Json", "Custom.Library" },
            Assert.IsType<string[]>(args[1]));
    }

    [Fact]
    public void CodeIntelligenceDogfoodAdapter_DeduplicatesStableTypes()
    {
        var adapterType = typeof(CodeIntelligenceService).Assembly.GetType(
                "NSharpLang.Compiler.CodeIntelligence.NSharpCodeIntelligenceDogfoodAdapter")
            ?? throw new InvalidOperationException("Dogfood code-intelligence adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryDeduplicateStableTypes = adapterType.GetMethod(
                "TryDeduplicateStableTypes",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateStableTypes.");
        var types = new[]
        {
            typeof(string),
            typeof(int),
            typeof(string),
            typeof(Console),
            typeof(int)
        };
        var args = new object?[] { types, null };

        Assert.True((bool)(tryDeduplicateStableTypes.Invoke(null, args) ?? false));
        Assert.Equal(
            new[] { typeof(string), typeof(int), typeof(Console) },
            Assert.IsType<Type[]>(args[1]));
    }

    [Fact]
    public void PerformanceDogfoodAdapter_ChecksStructCopyFieldReadonlyShape()
    {
        var adapterType = typeof(NSharpLang.Compiler.Performance.StructCopyAnalysis).Assembly.GetType(
                "NSharpLang.Compiler.Performance.NSharpPerformanceDogfoodAdapter")
            ?? throw new InvalidOperationException("Performance dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryAllInstanceFieldsAreInitOnly = adapterType.GetMethod(
                "TryAllInstanceFieldsAreInitOnly",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryAllInstanceFieldsAreInitOnly.");

        var readonlyFields = new[]
        {
            new NSharpLang.Compiler.Performance.StructCopyAnalysis.StructFieldDescriptor(
                typeof(double),
                IsInitOnly: false,
                IsStatic: true),
            new NSharpLang.Compiler.Performance.StructCopyAnalysis.StructFieldDescriptor(
                typeof(double),
                IsInitOnly: true,
                IsStatic: false),
            new NSharpLang.Compiler.Performance.StructCopyAnalysis.StructFieldDescriptor(
                typeof(double),
                IsInitOnly: true,
                IsStatic: false)
        };
        var readonlyArgs = new object?[] { readonlyFields, false };
        Assert.True((bool)(tryAllInstanceFieldsAreInitOnly.Invoke(null, readonlyArgs) ?? false));
        Assert.Equal(true, readonlyArgs[1]);

        var mutableFields = new[]
        {
            new NSharpLang.Compiler.Performance.StructCopyAnalysis.StructFieldDescriptor(
                typeof(double),
                IsInitOnly: true,
                IsStatic: false),
            new NSharpLang.Compiler.Performance.StructCopyAnalysis.StructFieldDescriptor(
                typeof(double),
                IsInitOnly: false,
                IsStatic: false)
        };
        var mutableArgs = new object?[] { mutableFields, true };
        Assert.True((bool)(tryAllInstanceFieldsAreInitOnly.Invoke(null, mutableArgs) ?? false));
        Assert.Equal(false, mutableArgs[1]);
    }

    [Fact]
    public void CompilerDogfoodAdapter_CompactsParserTokens()
    {
        var source = """
package CompilerDogfood.Tests

func main(): int {
    value := 1
    return value
}
""";
        var tokens = new Lexer(source, "test.nl").Tokenize();
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryCompactParserTokens = adapterType.GetMethod(
                "TryCompactParserTokens",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryCompactParserTokens.");
        var compactArgs = new object?[] { tokens, null };
        Assert.True((bool)(tryCompactParserTokens.Invoke(null, compactArgs) ?? false));
        var compactedTokens = Assert.IsType<List<Token>>(compactArgs[1]);

        var expectedTokens = tokens.Where(static token => token.Type != TokenType.Newline).ToList();
        Assert.Equal(expectedTokens.Select(static token => token.Type), compactedTokens.Select(static token => token.Type));
        Assert.Equal(expectedTokens.Select(static token => token.Value), compactedTokens.Select(static token => token.Value));
        Assert.DoesNotContain(compactedTokens, static token => token.Type == TokenType.Newline);
    }

    [Fact]
    public void CompilerDogfoodAdapter_SelectsMissingEnumMembers()
    {
        var members = new List<EnumMember>
        {
            new("Created", Value: null),
            new("Queued", Value: null),
            new("Running", Value: null),
            new("Succeeded", Value: null),
            new("Failed", Value: null),
            new("Retrying", Value: null)
        };
        var coveredMembers = new HashSet<string>(StringComparer.Ordinal)
        {
            "Queued",
            "Running",
            "Succeeded"
        };
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var trySelectMissingEnumMembers = adapterType.GetMethod(
                "TrySelectMissingEnumMembers",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TrySelectMissingEnumMembers.");
        var trySelectMissingUnionCasesFromFlags = adapterType.GetMethod(
                "TrySelectMissingUnionCasesFromFlags",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TrySelectMissingUnionCasesFromFlags.");

        var missingArgs = new object?[] { members, coveredMembers, null };
        Assert.True((bool)(trySelectMissingEnumMembers.Invoke(null, missingArgs) ?? false));
        Assert.Equal(
            new[] { "Created", "Failed", "Retrying" },
            Assert.IsType<List<string>>(missingArgs[2]));

        var allCoveredArgs = new object?[]
        {
            members,
            new HashSet<string>(members.Select(static member => member.Name), StringComparer.Ordinal),
            null
        };
        Assert.True((bool)(trySelectMissingEnumMembers.Invoke(null, allCoveredArgs) ?? false));
        Assert.Empty(Assert.IsType<List<string>>(allCoveredArgs[2]));

        var duplicateMemberArgs = new object?[]
        {
            new List<EnumMember>
            {
                new("Created", Value: null),
                new("Created", Value: null)
            },
            new HashSet<string>(StringComparer.Ordinal),
            null
        };
        Assert.False((bool)(trySelectMissingEnumMembers.Invoke(null, duplicateMemberArgs) ?? true));

        var unionCases = new List<UnionCase>
        {
            new("Created", Properties: null),
            new("Queued", Properties: null),
            new("Running", Properties: null),
            new("Succeeded", Properties: null),
            new("Failed", Properties: null),
            new("Retrying", Properties: null)
        };
        var coveredFlags = new[] { 0, 1, 0, 1, 0, 0 };
        var partialFlags = new[] { 0, 0, 1, 0, 1, 0 };
        var missingUnionArgs = new object?[] { unionCases, coveredFlags, partialFlags, unionCases.Count, null, null, null };
        Assert.True((bool)(trySelectMissingUnionCasesFromFlags.Invoke(null, missingUnionArgs) ?? false));
        Assert.Equal(
            new[] { "Created", "Running", "Failed", "Retrying" },
            Assert.IsType<List<string>>(missingUnionArgs[4]));
        Assert.Equal(
            new[] { "Running", "Failed" },
            Assert.IsType<List<string>>(missingUnionArgs[5]));
        Assert.Equal(
            new[] { "Created", "Retrying" },
            Assert.IsType<List<string>>(missingUnionArgs[6]));

        var invalidUnionArgs = new object?[] { unionCases, coveredFlags, partialFlags, unionCases.Count + 1, null, null, null };
        Assert.False((bool)(trySelectMissingUnionCasesFromFlags.Invoke(null, invalidUnionArgs) ?? true));
    }

    [Fact]
    public void CompilerDogfoodAdapter_ChecksAnonymousUnionShimEligibility()
    {
        static SimpleTypeReference Simple(string name) => new(name);
        static UnionTypeReference Union(params TypeReference[] arms) => new(arms.ToList());

        static bool IsTwoArmAnonymousUnion(TypeReference typeReference)
        {
            if (typeReference is not UnionTypeReference)
                return false;

            var count = 0;
            CountFlattenedUnionArms(typeReference, ref count);
            return count == 2;
        }

        static void CountFlattenedUnionArms(TypeReference typeReference, ref int count)
        {
            if (count > 2)
                return;

            if (typeReference is UnionTypeReference union)
            {
                foreach (var arm in union.Arms)
                {
                    CountFlattenedUnionArms(arm, ref count);
                    if (count > 2)
                        return;
                }

                return;
            }

            count++;
        }

        static Parameter Parameter(
            string name,
            TypeReference type,
            NSharpLang.Compiler.Ast.ParameterModifier modifier = NSharpLang.Compiler.Ast.ParameterModifier.None) =>
            new(name, type, DefaultValue: null, IsThis: false, modifier);

        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryDeclaresAnonymousUnionShims = adapterType.GetMethod(
                "TryDeclaresAnonymousUnionShims",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeclaresAnonymousUnionShims.");

        var eligibleUnion = Union(Simple("int"), Simple("string"));
        var threeArmUnion = Union(Simple("int"), Union(Simple("string"), Simple("bool")));

        var eligibleParameters = new[]
        {
            Parameter("prefix", Simple("int")),
            Parameter("value", eligibleUnion),
            Parameter("suffix", Simple("string"))
        };
        var eligibleArgs = new object?[]
        {
            eligibleParameters,
            (Func<TypeReference, bool>)IsTwoArmAnonymousUnion,
            false
        };
        Assert.True((bool)(tryDeclaresAnonymousUnionShims.Invoke(null, eligibleArgs) ?? false));
        Assert.Equal(true, eligibleArgs[2]);

        var disallowedParameters = new[]
        {
            Parameter("value", eligibleUnion),
            Parameter("output", eligibleUnion, NSharpLang.Compiler.Ast.ParameterModifier.Out)
        };
        var disallowedArgs = new object?[]
        {
            disallowedParameters,
            (Func<TypeReference, bool>)IsTwoArmAnonymousUnion,
            true
        };
        Assert.True((bool)(tryDeclaresAnonymousUnionShims.Invoke(null, disallowedArgs) ?? false));
        Assert.Equal(false, disallowedArgs[2]);

        var noShimParameters = new[]
        {
            Parameter("value", Simple("int")),
            Parameter("wide", threeArmUnion)
        };
        var noShimArgs = new object?[]
        {
            noShimParameters,
            (Func<TypeReference, bool>)IsTwoArmAnonymousUnion,
            true
        };
        Assert.True((bool)(tryDeclaresAnonymousUnionShims.Invoke(null, noShimArgs) ?? false));
        Assert.Equal(false, noShimArgs[2]);
    }

    [Fact]
    public void CompilerDogfoodAdapter_DeduplicatesFirstTypeKeys()
    {
        var types = new[]
        {
            typeof(IList<string>),
            typeof(IEnumerable<string>),
            typeof(IList<string>),
            typeof(IDictionary<string, int>),
            typeof(IEnumerable<string>),
            typeof(IDictionary<string, int>)
        };
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryDeduplicateFirstTypeKeys = adapterType.GetMethod(
                "TryDeduplicateFirstTypeKeys",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateFirstTypeKeys.");
        var args = new object?[]
        {
            types,
            (Func<Type, string>)(type => type.FullName ?? type.Name),
            null
        };
        Assert.True((bool)(tryDeduplicateFirstTypeKeys.Invoke(null, args) ?? false));
        var deduplicatedTypes = Assert.IsType<List<Type>>(args[2]);

        Assert.Equal(new[]
        {
            typeof(IList<string>),
            typeof(IEnumerable<string>),
            typeof(IDictionary<string, int>)
        }, deduplicatedTypes);
    }

    [Fact]
    public void CompilerDogfoodAdapter_DeduplicatesFirstStringsOrdinalIgnoreCase()
    {
        var paths = new[]
        {
            "/repo/src/App.nl",
            "/repo/src/Shared.nl",
            "/REPO/SRC/app.nl",
            "/repo/src/Feature.nl",
            "/repo/src/shared.nl"
        };
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryDeduplicateFirstStringsOrdinalIgnoreCase = adapterType.GetMethod(
                "TryDeduplicateFirstStringsOrdinalIgnoreCase",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateFirstStringsOrdinalIgnoreCase.");
        var args = new object?[] { paths, null };
        Assert.True((bool)(tryDeduplicateFirstStringsOrdinalIgnoreCase.Invoke(null, args) ?? false));
        var deduplicatedPaths = Assert.IsType<List<string>>(args[1]);

        Assert.Equal(new[]
        {
            "/repo/src/App.nl",
            "/repo/src/Shared.nl",
            "/repo/src/Feature.nl"
        }, deduplicatedPaths);
    }

    [Fact]
    public void CompilerDogfoodAdapter_DistinctOrdersStringsOrdinal()
    {
        var names = new[]
        {
            "Zeta",
            "Alpha",
            "Zeta",
            "Beta",
            "alpha"
        };
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryDistinctOrderStringsOrdinal = adapterType.GetMethod(
                "TryDistinctOrderStringsOrdinal",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDistinctOrderStringsOrdinal.");
        var args = new object?[] { names, null };
        Assert.True((bool)(tryDistinctOrderStringsOrdinal.Invoke(null, args) ?? false));
        var orderedNames = Assert.IsType<string[]>(args[1]);

        Assert.Equal(new[]
        {
            "Alpha",
            "Beta",
            "Zeta",
            "alpha"
        }, orderedNames);
    }

    [Fact]
    public void MultiFileCompiler_DeduplicatesSourceFilesOrdinalIgnoreCase()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-dogfood-source-dedup-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var sourceFile = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourceFile, "func main(): int { return 0 }");

            var compiler = new MultiFileCompiler(
                new[] { sourceFile, sourceFile.ToUpperInvariant(), sourceFile },
                tempDir,
                ProjectFileParser.CreateDefault());

            var source = Assert.Single(compiler.SourceFiles);
            Assert.Equal(Path.GetFullPath(sourceFile), source);
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void CompilationStubEmitter_DeduplicatesSourceFilesBeforeParsing()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-dogfood-stub-dedup-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var sourceFile = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourceFile, """
func helper(): int {
    return 1
}
""");

            var stub = CompilationStubEmitter.Generate(
                ProjectFileParser.CreateDefault(),
                new[] { sourceFile, sourceFile });

            Assert.Equal(1, CountOccurrences(stub, "internal static int helper("));
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void CompilationStubEmitter_UsesDogfoodNamespaceImportOrdering()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-dogfood-stub-namespace-order-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var zetaFile = Path.Combine(tempDir, "Zeta.nl");
            File.WriteAllText(zetaFile, """
namespace Zeta

class ZetaType {
}
""");
            var alphaFile = Path.Combine(tempDir, "Alpha.nl");
            File.WriteAllText(alphaFile, """
namespace Alpha

class AlphaType {
}
""");
            var duplicateZetaFile = Path.Combine(tempDir, "DuplicateZeta.nl");
            File.WriteAllText(duplicateZetaFile, """
namespace Zeta

class OtherZetaType {
}
""");

            var stub = CompilationStubEmitter.Generate(
                ProjectFileParser.CreateDefault(),
                new[] { zetaFile, alphaFile, duplicateZetaFile });

            Assert.Equal(1, CountOccurrences(stub, "using Alpha;"));
            Assert.Equal(1, CountOccurrences(stub, "using Zeta;"));
            Assert.True(
                stub.IndexOf("using Alpha;", StringComparison.Ordinal)
                    < stub.IndexOf("using Zeta;", StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void CompilerDogfoodAdapter_OrdersImportsBySystemThenNamespaceLikeProduction()
    {
        var imports = new List<ImportDirective>
        {
            new("Zenith.Core", Alias: null, Line: 1, Column: 1),
            new("System.Linq", Alias: null, Line: 2, Column: 1),
            new("Acme.Widgets", Alias: "Widgets", Line: 3, Column: 1),
            new("System", Alias: null, Line: 4, Column: 1),
            new("System.Collections.Generic", Alias: null, Line: 5, Column: 1),
            new("Microsoft.Extensions.Logging", Alias: null, Line: 6, Column: 1),
            new("System.Linq", Alias: null, Line: 7, Column: 1),
            new("Acme.Widgets", Alias: null, Line: 8, Column: 1),
            new("NSharpLang.Compiler", Alias: null, Line: 9, Column: 1),
            new("System.Text", Alias: null, Line: 10, Column: 1),
        };

        // Exact production LINQ shape from Formatter.Format.
        var expected = imports
            .OrderByDescending(i => i.Namespace.StartsWith("System"))
            .ThenBy(i => i.Namespace)
            .ToList();

        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryOrderImports = adapterType.GetMethod(
                "TryOrderImportsBySystemThenNamespace",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryOrderImportsBySystemThenNamespace.");

        var args = new object?[] { imports, null };
        Assert.True((bool)(tryOrderImports.Invoke(null, args) ?? false));
        var ordered = Assert.IsType<List<ImportDirective>>(args[1]);

        // Same references, in the same order as production LINQ (stable, reference-identical).
        Assert.Equal(expected.Count, ordered.Count);
        for (var i = 0; i < expected.Count; i++)
        {
            Assert.Same(expected[i], ordered[i]);
        }
    }

    [Fact]
    public void CompilerDogfoodAdapter_OrdersImportsAfterLargerListReusesScratchCorrectly()
    {
        // Regression: the kernel derives its working count from array length, and the
        // adapter scratch is thread-static and reused. A larger list followed by a smaller
        // list on the same thread must not leak stale tail slots into the smaller result.
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryOrderImports = adapterType.GetMethod(
                "TryOrderImportsBySystemThenNamespace",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryOrderImportsBySystemThenNamespace.");

        static List<ImportDirective> ExpectedOrder(List<ImportDirective> imports) => imports
            .OrderByDescending(i => i.Namespace.StartsWith("System"))
            .ThenBy(i => i.Namespace)
            .ToList();

        static List<ImportDirective> Invoke(MethodInfo method, List<ImportDirective> imports)
        {
            var args = new object?[] { imports, null };
            Assert.True((bool)(method.Invoke(null, args) ?? false));
            return Assert.IsType<List<ImportDirective>>(args[1]);
        }

        // First: a large list to grow the thread-static scratch buffers.
        var large = new List<ImportDirective>();
        for (var i = 0; i < 64; i++)
        {
            var ns = (i % 3 == 0 ? "System.Ns" : "Acme.Ns") + (63 - i).ToString("D3");
            large.Add(new ImportDirective(ns, Alias: null, Line: i + 1, Column: 1));
        }

        var largeOrdered = Invoke(tryOrderImports, large);
        Assert.Equal(ExpectedOrder(large), largeOrdered);

        // Then: a smaller list on the same thread must still match production exactly.
        var small = new List<ImportDirective>
        {
            new("Zeta.Core", Alias: null, Line: 1, Column: 1),
            new("System.Linq", Alias: null, Line: 2, Column: 1),
            new("Acme.Widgets", Alias: null, Line: 3, Column: 1),
            new("System", Alias: null, Line: 4, Column: 1),
        };

        var smallOrdered = Invoke(tryOrderImports, small);
        Assert.Equal(ExpectedOrder(small), smallOrdered);
    }

    [Fact]
    public void CompilerDogfoodAdapter_LooksUpUniqueDeclaredTypeBySuffix()
    {
        var declaredTypes = new Dictionary<string, Type>(StringComparer.Ordinal)
        {
            ["Demo.Models.Customer"] = typeof(string),
            ["Demo.Tiny.Foo"] = typeof(decimal),
            ["Demo.Core.Shared"] = typeof(int),
            ["Demo.Other.Shared"] = typeof(long)
        };
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryLookupUniqueDeclaredTypeBySuffix = adapterType.GetMethod(
                "TryLookupUniqueDeclaredTypeBySuffix",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryLookupUniqueDeclaredTypeBySuffix.");
        var genericLookup = tryLookupUniqueDeclaredTypeBySuffix.MakeGenericMethod(typeof(Type));

        var uniqueArgs = new object?[] { declaredTypes, "Customer", null, false };
        Assert.True((bool)(genericLookup.Invoke(null, uniqueArgs) ?? false));
        Assert.Equal(true, uniqueArgs[3]);
        Assert.Same(typeof(string), uniqueArgs[2]);

        var tinyArgs = new object?[] { declaredTypes, "Foo", null, false };
        Assert.True((bool)(genericLookup.Invoke(null, tinyArgs) ?? false));
        Assert.Equal(true, tinyArgs[3]);
        Assert.Same(typeof(decimal), tinyArgs[2]);

        var exactArgs = new object?[] { declaredTypes, "Demo.Core.Shared", null, false };
        Assert.True((bool)(genericLookup.Invoke(null, exactArgs) ?? false));
        Assert.Equal(true, exactArgs[3]);
        Assert.Same(typeof(int), exactArgs[2]);

        var missingArgs = new object?[] { declaredTypes, "Missing", null, false };
        Assert.True((bool)(genericLookup.Invoke(null, missingArgs) ?? false));
        Assert.Equal(false, missingArgs[3]);
        Assert.Null(missingArgs[2]);

        var ambiguousArgs = new object?[] { declaredTypes, "Shared", null, false };
        Assert.True((bool)(genericLookup.Invoke(null, ambiguousArgs) ?? false));
        Assert.Equal(false, ambiguousArgs[3]);
        Assert.Null(ambiguousArgs[2]);
    }

    [Fact]
    public void CompilerDogfoodAdapter_SelectsDeclaredTypeNameCandidate()
    {
        static ClassDeclaration TypeDeclaration(string name) => new(
            name,
            TypeParameters: null,
            BaseClass: null,
            Interfaces: new List<TypeReference>(),
            Members: new List<Declaration>(),
            PrimaryConstructorParameters: null,
            Modifiers: Modifiers.Public,
            Attributes: new List<AttributeNode>(),
            Line: 1,
            Column: 1);

        var compilationUnit = new CompilationUnit(
            Namespace: null,
            Imports: new List<ImportDirective>
            {
                new("Demo.Imported", Alias: null, Line: 1, Column: 1)
            },
            FileImports: new List<Statement>(),
            Package: null,
            Declarations: new List<Declaration>
            {
                TypeDeclaration("Demo.Imported.Customer"),
                TypeDeclaration("Demo.Other.Customer"),
                TypeDeclaration("Demo.Local.Invoice"),
                TypeDeclaration("Demo.Tiny.Foo"),
                TypeDeclaration("Demo.Alpha.Shared"),
                TypeDeclaration("Demo.Beta.Shared")
            },
            Line: 1,
            Column: 1);
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var trySelectDeclaredTypeNameCandidate = adapterType.GetMethod(
                "TrySelectDeclaredTypeNameCandidate",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TrySelectDeclaredTypeNameCandidate.");

        var importedSuffixArgs = new object?[] { compilationUnit, "Customer", null };
        Assert.True((bool)(trySelectDeclaredTypeNameCandidate.Invoke(null, importedSuffixArgs) ?? false));
        Assert.Equal("Demo.Imported.Customer", importedSuffixArgs[2]);

        var uniqueSuffixArgs = new object?[] { compilationUnit, "Invoice", null };
        Assert.True((bool)(trySelectDeclaredTypeNameCandidate.Invoke(null, uniqueSuffixArgs) ?? false));
        Assert.Equal("Demo.Local.Invoice", uniqueSuffixArgs[2]);

        var tinySuffixArgs = new object?[] { compilationUnit, "Foo", null };
        Assert.True((bool)(trySelectDeclaredTypeNameCandidate.Invoke(null, tinySuffixArgs) ?? false));
        Assert.Equal("Demo.Tiny.Foo", tinySuffixArgs[2]);

        var exactArgs = new object?[] { compilationUnit, "Demo.Local.Invoice", null };
        Assert.True((bool)(trySelectDeclaredTypeNameCandidate.Invoke(null, exactArgs) ?? false));
        Assert.Equal("Demo.Local.Invoice", exactArgs[2]);

        var ambiguousArgs = new object?[] { compilationUnit, "Shared", null };
        Assert.True((bool)(trySelectDeclaredTypeNameCandidate.Invoke(null, ambiguousArgs) ?? false));
        Assert.Null(ambiguousArgs[2]);

        var missingArgs = new object?[] { compilationUnit, "Missing", null };
        Assert.True((bool)(trySelectDeclaredTypeNameCandidate.Invoke(null, missingArgs) ?? false));
        Assert.Null(missingArgs[2]);
    }

    [Fact]
    public void CompilerDogfoodAdapter_OrdersTypesByDescendingKeyDotCount()
    {
        var types = new[]
        {
            typeof(string),
            typeof(int),
            typeof(decimal),
            typeof(DateTime),
            typeof(Guid)
        };
        var keys = new Dictionary<Type, string>
        {
            [typeof(string)] = "Root",
            [typeof(int)] = "Root.Nested",
            [typeof(decimal)] = "Root.Nested.Deep",
            [typeof(DateTime)] = "Other.Deep",
            [typeof(Guid)] = "Root.Nested.Deep.More"
        };
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryOrderTypesByDescendingKeyDotCount = adapterType.GetMethod(
                "TryOrderTypesByDescendingKeyDotCount",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryOrderTypesByDescendingKeyDotCount.");
        var genericOrder = tryOrderTypesByDescendingKeyDotCount.MakeGenericMethod(typeof(Type));
        var args = new object?[]
        {
            types,
            (Func<Type, string>)(type => keys[type]),
            null
        };

        Assert.True((bool)(genericOrder.Invoke(null, args) ?? false));
        var orderedTypes = Assert.IsType<List<Type>>(args[2]);
        Assert.Equal(new[]
        {
            typeof(Guid),
            typeof(decimal),
            typeof(int),
            typeof(DateTime),
            typeof(string)
        }, orderedTypes);
    }

    [Fact]
    public void LexerTokenKindScanner_ProjectCompilesAndMatchesProductionLexer()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(
            Path.GetTempPath(),
            $"NSharpLang.Compiler.Dogfood.Tests.{Guid.NewGuid():N}.dll");

        try
        {
            var compiler = new MultiFileCompiler(projectRoot, config);
            var result = compiler.CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            Assert.True(File.Exists(outputPath));

            var assembly = Assembly.Load(File.ReadAllBytes(outputPath));
            var programType = assembly.GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var tokenizeCount = programType.GetMethod(
                    "TokenizeCount",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeCount.");
            var tokenizeKinds = programType.GetMethod(
                    "TokenizeKinds",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeKinds.");
            var tokenizeKindsInto = programType.GetMethod(
                    "TokenizeKindsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeKindsInto.");
            var tokenizeMetadataInto = programType.GetMethod(
                    "TokenizeMetadataInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeMetadataInto.");
            var tokenizeMetadataWithIndentationInto = programType.GetMethod(
                    "TokenizeMetadataWithIndentationInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeMetadataWithIndentationInto.");
            var commentsInto = programType.GetMethod(
                    "CommentsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CommentsInto.");
            var parserTokenCompactionIndicesInto = programType.GetMethod(
                    "ParserTokenCompactionIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ParserTokenCompactionIndicesInto.");
            var parserTokenCompactionChecksumInto = programType.GetMethod(
                    "ParserTokenCompactionChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ParserTokenCompactionChecksumInto.");
            var splitLogicalLines = programType.GetMethod(
                    "SplitLogicalLines",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SplitLogicalLines.");
            var splitLogicalLineRangesInto = programType.GetMethod(
                    "SplitLogicalLineRangesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SplitLogicalLineRangesInto.");
            var buildLogicalLineStartsInto = programType.GetMethod(
                    "BuildLogicalLineStartsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BuildLogicalLineStartsInto.");
            var getLineIndexFromOffset = programType.GetMethod(
                    "GetLineIndexFromOffset",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit GetLineIndexFromOffset.");
            var getColumnFromOffset = programType.GetMethod(
                    "GetColumnFromOffset",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit GetColumnFromOffset.");
            var getOffsetFromLineColumn = programType.GetMethod(
                    "GetOffsetFromLineColumn",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit GetOffsetFromLineColumn.");
            var lineMapCachedChecksumInto = programType.GetMethod(
                    "LineMapCachedChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit LineMapCachedChecksumInto.");
            var lineMapCachedQueryChecksumInto = programType.GetMethod(
                    "LineMapCachedQueryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit LineMapCachedQueryChecksumInto.");
            var lineMapTrustedCachedQueryChecksumInto = programType.GetMethod(
                    "LineMapTrustedCachedQueryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit LineMapTrustedCachedQueryChecksumInto.");
            var codeIntelligenceIdentifierSpanChecksumInto = programType.GetMethod(
                    "CodeIntelligenceIdentifierSpanChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceIdentifierSpanChecksumInto.");
            var codeIntelligenceIdentifierSpansInto = programType.GetMethod(
                    "CodeIntelligenceIdentifierSpansInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceIdentifierSpansInto.");
            var buildCodeIntelligenceLineRangesInto = programType.GetMethod(
                    "BuildCodeIntelligenceLineRangesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BuildCodeIntelligenceLineRangesInto.");
            var codeIntelligenceEditorIdentifierSpanChecksumInto = programType.GetMethod(
                    "CodeIntelligenceEditorIdentifierSpanChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceEditorIdentifierSpanChecksumInto.");
            var codeIntelligenceEditorIdentifierSpansInto = programType.GetMethod(
                    "CodeIntelligenceEditorIdentifierSpansInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceEditorIdentifierSpansInto.");
            var codeIntelligenceDeclarationNameMatchChecksumInto = programType.GetMethod(
                    "CodeIntelligenceDeclarationNameMatchChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceDeclarationNameMatchChecksumInto.");
            var codeIntelligenceDeclarationNameMatchesFromLinesInto = programType.GetMethod(
                    "CodeIntelligenceDeclarationNameMatchesFromLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceDeclarationNameMatchesFromLinesInto.");
            var codeIntelligenceIdentifierNameColumnChecksumInto = programType.GetMethod(
                    "CodeIntelligenceIdentifierNameColumnChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceIdentifierNameColumnChecksumInto.");
            var codeIntelligenceIdentifierNameColumnsInto = programType.GetMethod(
                    "CodeIntelligenceIdentifierNameColumnsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceIdentifierNameColumnsInto.");
            var codeIntelligenceIdentifierNameColumnsFromLinesInto = programType.GetMethod(
                    "CodeIntelligenceIdentifierNameColumnsFromLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceIdentifierNameColumnsFromLinesInto.");
            var codeIntelligenceMemberReceiverChecksumInto = programType.GetMethod(
                    "CodeIntelligenceMemberReceiverChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceMemberReceiverChecksumInto.");
            var codeIntelligenceMemberReceiversInto = programType.GetMethod(
                    "CodeIntelligenceMemberReceiversInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceMemberReceiversInto.");
            var codeIntelligenceMemberReceiverCachedChecksumInto = programType.GetMethod(
                    "CodeIntelligenceMemberReceiverCachedChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceMemberReceiverCachedChecksumInto.");
            var codeIntelligenceMemberReceiversCachedInto = programType.GetMethod(
                    "CodeIntelligenceMemberReceiversCachedInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceMemberReceiversCachedInto.");
            var codeIntelligenceSourceContextChecksumInto = programType.GetMethod(
                    "CodeIntelligenceSourceContextChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceContextChecksumInto.");
            var codeIntelligenceSourceContextsInto = programType.GetMethod(
                    "CodeIntelligenceSourceContextsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceContextsInto.");
            var codeIntelligenceSourceLineChecksumInto = programType.GetMethod(
                    "CodeIntelligenceSourceLineChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceLineChecksumInto.");
            var codeIntelligenceSourceLinesInto = programType.GetMethod(
                    "CodeIntelligenceSourceLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceLinesInto.");
            var codeIntelligenceSourceLinesFromLinesInto = programType.GetMethod(
                    "CodeIntelligenceSourceLinesFromLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceLinesFromLinesInto.");
            var codeIntelligencePathMatches = programType.GetMethod(
                    "CodeIntelligencePathMatches",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligencePathMatches.");
            var codeIntelligencePathMatchChecksumInto = programType.GetMethod(
                    "CodeIntelligencePathMatchChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligencePathMatchChecksumInto.");
            var projectSourceFilterKeptIndicesInto = programType.GetMethod(
                    "ProjectSourceFilterKeptIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ProjectSourceFilterKeptIndicesInto.");
            var projectSourceFilterKeptChecksumInto = programType.GetMethod(
                    "ProjectSourceFilterKeptChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ProjectSourceFilterKeptChecksumInto.");
            var codeIntelligenceCompletionPrefixChecksumInto = programType.GetMethod(
                    "CodeIntelligenceCompletionPrefixChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceCompletionPrefixChecksumInto.");
            var codeIntelligenceCompletionPrefixesInto = programType.GetMethod(
                    "CodeIntelligenceCompletionPrefixesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceCompletionPrefixesInto.");
            var codeIntelligenceCompletionPrefixesFromLinesInto = programType.GetMethod(
                    "CodeIntelligenceCompletionPrefixesFromLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceCompletionPrefixesFromLinesInto.");
            var codeIntelligenceCompletionReceiverChecksumInto = programType.GetMethod(
                    "CodeIntelligenceCompletionReceiverChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceCompletionReceiverChecksumInto.");
            var codeIntelligenceCompletionReceiversInto = programType.GetMethod(
                    "CodeIntelligenceCompletionReceiversInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceCompletionReceiversInto.");
            var completionItemKindGroupsInto = programType.GetMethod(
                    "CompletionItemKindGroupsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CompletionItemKindGroupsInto.");
            var completionItemKindGroupChecksumInto = programType.GetMethod(
                    "CompletionItemKindGroupChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CompletionItemKindGroupChecksumInto.");
            var completionMethodOverloadGroupsInto = programType.GetMethod(
                    "CompletionMethodOverloadGroupsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CompletionMethodOverloadGroupsInto.");
            var completionMethodOverloadGroupChecksumInto = programType.GetMethod(
                    "CompletionMethodOverloadGroupChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CompletionMethodOverloadGroupChecksumInto.");
            var cliTryParsePositionInto = programType.GetMethod(
                    "CliTryParsePositionInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliTryParsePositionInto.");
            var cliQueryPositionsInto = programType.GetMethod(
                    "CliQueryPositionsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliQueryPositionsInto.");
            var cliQueryPositionChecksumInto = programType.GetMethod(
                    "CliQueryPositionChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliQueryPositionChecksumInto.");
            var cliPositionalArgIndicesInto = programType.GetMethod(
                    "CliPositionalArgIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliPositionalArgIndicesInto.");
            var cliBuildOperandIndicesInto = programType.GetMethod(
                    "CliBuildOperandIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBuildOperandIndicesInto.");
            var cliBuildOperandSummaryInto = programType.GetMethod(
                    "CliBuildOperandSummaryInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBuildOperandSummaryInto.");
            var cliBuildFirstOperandIndexInto = programType.GetMethod(
                    "CliBuildFirstOperandIndexInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBuildFirstOperandIndexInto.");
            var cliBuildOptionSummaryInto = programType.GetMethod(
                    "CliBuildOptionSummaryInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBuildOptionSummaryInto.");
            var cliBuildOptionSummaryChecksumInto = programType.GetMethod(
                    "CliBuildOptionSummaryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBuildOptionSummaryChecksumInto.");
            var cliExportCSharpFirstOperandIndexInto = programType.GetMethod(
                    "CliExportCSharpFirstOperandIndexInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliExportCSharpFirstOperandIndexInto.");
            var cliExportCSharpFirstOperandChecksumInto = programType.GetMethod(
                    "CliExportCSharpFirstOperandChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliExportCSharpFirstOperandChecksumInto.");
            var cliRunFirstOperandIndex = programType.GetMethod(
                    "CliRunFirstOperandIndex",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliRunFirstOperandIndex.");
            var cliWatchForwardedArgIndicesInto = programType.GetMethod(
                    "CliWatchForwardedArgIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliWatchForwardedArgIndicesInto.");
            var cliWatchForwardedArgChecksumInto = programType.GetMethod(
                    "CliWatchForwardedArgChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliWatchForwardedArgChecksumInto.");
            var cliPublishOptionsInto = programType.GetMethod(
                    "CliPublishOptionsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliPublishOptionsInto.");
            var cliFirstPositionalArgIndex = programType.GetMethod(
                    "CliFirstPositionalArgIndex",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFirstPositionalArgIndex.");
            var cliLintFileArgIndicesInto = programType.GetMethod(
                    "CliLintFileArgIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliLintFileArgIndicesInto.");
            var cliLintFileArgChecksumInto = programType.GetMethod(
                    "CliLintFileArgChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliLintFileArgChecksumInto.");
            var cliTidyDependencyStatusRanksInto = programType.GetMethod(
                    "CliTidyDependencyStatusRanksInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliTidyDependencyStatusRanksInto.");
            var cliTidyDependencyStatusRankChecksumInto = programType.GetMethod(
                    "CliTidyDependencyStatusRankChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliTidyDependencyStatusRankChecksumInto.");
            var cliTidyRemovalLineKeepFlagsInto = programType.GetMethod(
                    "CliTidyRemovalLineKeepFlagsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliTidyRemovalLineKeepFlagsInto.");
            var cliTidyRemovalLineKeepChecksumInto = programType.GetMethod(
                    "CliTidyRemovalLineKeepChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliTidyRemovalLineKeepChecksumInto.");
            var cliPositionalArgChecksumInto = programType.GetMethod(
                    "CliPositionalArgChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliPositionalArgChecksumInto.");
            var cliFixSafetyFilterIndicesInto = programType.GetMethod(
                    "CliFixSafetyFilterIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixSafetyFilterIndicesInto.");
            var cliFixSafetyFilterChecksumInto = programType.GetMethod(
                    "CliFixSafetyFilterChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixSafetyFilterChecksumInto.");
            var cliFixEditFlattenIndicesInto = programType.GetMethod(
                    "CliFixEditFlattenIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixEditFlattenIndicesInto.");
            var cliFixEditFlattenChecksumInto = programType.GetMethod(
                    "CliFixEditFlattenChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixEditFlattenChecksumInto.");
            var cliFixSkippedIndicesInto = programType.GetMethod(
                    "CliFixSkippedIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixSkippedIndicesInto.");
            var cliFixSkippedChecksumInto = programType.GetMethod(
                    "CliFixSkippedChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixSkippedChecksumInto.");
            var cliFixAppliedFileGroupsInto = programType.GetMethod(
                    "CliFixAppliedFileGroupsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixAppliedFileGroupsInto.");
            var cliFixAppliedFileGroupChecksumInto = programType.GetMethod(
                    "CliFixAppliedFileGroupChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixAppliedFileGroupChecksumInto.");
            var cliUnifiedDiffHunkRangesInto = programType.GetMethod(
                    "CliUnifiedDiffHunkRangesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliUnifiedDiffHunkRangesInto.");
            var cliUnifiedDiffHunkRangeChecksumInto = programType.GetMethod(
                    "CliUnifiedDiffHunkRangeChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliUnifiedDiffHunkRangeChecksumInto.");
            var cliCleanArtifactDirectoryIndicesInto = programType.GetMethod(
                    "CliCleanArtifactDirectoryIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliCleanArtifactDirectoryIndicesInto.");
            var cliCleanArtifactDirectoryChecksumInto = programType.GetMethod(
                    "CliCleanArtifactDirectoryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliCleanArtifactDirectoryChecksumInto.");
            var cliUpdateAllNuGetDependencyIndicesInto = programType.GetMethod(
                    "CliUpdateAllNuGetDependencyIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliUpdateAllNuGetDependencyIndicesInto.");
            var cliUpdateAllNuGetDependencyChecksumInto = programType.GetMethod(
                    "CliUpdateAllNuGetDependencyChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliUpdateAllNuGetDependencyChecksumInto.");
            var cliUpdateTargetNuGetDependencyIndicesInto = programType.GetMethod(
                    "CliUpdateTargetNuGetDependencyIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliUpdateTargetNuGetDependencyIndicesInto.");
            var cliUpdateTargetNuGetDependencyChecksumInto = programType.GetMethod(
                    "CliUpdateTargetNuGetDependencyChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliUpdateTargetNuGetDependencyChecksumInto.");
            var cliReferenceTypeFilterIndicesInto = programType.GetMethod(
                    "CliReferenceTypeFilterIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliReferenceTypeFilterIndicesInto.");
            var cliReferenceTypeFilterChecksumInto = programType.GetMethod(
                    "CliReferenceTypeFilterChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliReferenceTypeFilterChecksumInto.");
            var cliReferenceResolutionBestScoreIndex = programType.GetMethod(
                    "CliReferenceResolutionBestScoreIndex",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliReferenceResolutionBestScoreIndex.");
            var cliReferenceResolutionBestScoreChecksum = programType.GetMethod(
                    "CliReferenceResolutionBestScoreChecksum",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliReferenceResolutionBestScoreChecksum.");
            var cliDocSymbolOrderCountingIndicesInto = programType.GetMethod(
                    "CliDocSymbolOrderCountingIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliDocSymbolOrderCountingIndicesInto.");
            var cliDocSymbolOrderCountingChecksumInto = programType.GetMethod(
                    "CliDocSymbolOrderCountingChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliDocSymbolOrderCountingChecksumInto.");
            var cliDocSlugsInto = programType.GetMethod(
                    "CliDocSlugsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliDocSlugsInto.");
            var cliSymbolNameGlobFilterIndicesInto = programType.GetMethod(
                    "CliSymbolNameGlobFilterIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliSymbolNameGlobFilterIndicesInto.");
            var cliSymbolNameSubstringFilterIndicesInto = programType.GetMethod(
                    "CliSymbolNameSubstringFilterIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliSymbolNameSubstringFilterIndicesInto.");
            var symbolKindFilterIndicesInto = programType.GetMethod(
                    "SymbolKindFilterIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SymbolKindFilterIndicesInto.");
            var symbolKindFilterChecksumInto = programType.GetMethod(
                    "SymbolKindFilterChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SymbolKindFilterChecksumInto.");
            var docQueryBestTypeIndex = programType.GetMethod(
                    "DocQueryBestTypeIndex",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DocQueryBestTypeIndex.");
            var docQueryBestTypeChecksumInto = programType.GetMethod(
                    "DocQueryBestTypeChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DocQueryBestTypeChecksumInto.");
            var docQueryMemberOrderIndicesInto = programType.GetMethod(
                    "DocQueryMemberOrderIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DocQueryMemberOrderIndicesInto.");
            var docQueryMemberOrderChecksumInto = programType.GetMethod(
                    "DocQueryMemberOrderChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DocQueryMemberOrderChecksumInto.");
            var typoSuggestionIndicesInto = programType.GetMethod(
                    "TypoSuggestionIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TypoSuggestionIndicesInto.");
            var typoSuggestionChecksumInto = programType.GetMethod(
                    "TypoSuggestionChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TypoSuggestionChecksumInto.");
            var aotRequirementGroupsInto = programType.GetMethod(
                    "AotRequirementGroupsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit AotRequirementGroupsInto.");
            var aotRequirementGroupChecksumInto = programType.GetMethod(
                    "AotRequirementGroupChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit AotRequirementGroupChecksumInto.");
            var cliBatchDuplicateIdRanksInto = programType.GetMethod(
                    "CliBatchDuplicateIdRanksInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBatchDuplicateIdRanksInto.");
            var cliBatchDuplicateIdRankChecksumInto = programType.GetMethod(
                    "CliBatchDuplicateIdRankChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBatchDuplicateIdRankChecksumInto.");
            var cliBatchResultPackedCountChecksum = programType.GetMethod(
                    "CliBatchResultPackedCountChecksum",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBatchResultPackedCountChecksum.");
            var cliTestOutcomeSummaryChecksumInto = programType.GetMethod(
                    "CliTestOutcomeSummaryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliTestOutcomeSummaryChecksumInto.");
            var cliShouldFormatDiscoveredPath = programType.GetMethod(
                    "CliShouldFormatDiscoveredPath",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliShouldFormatDiscoveredPath.");
            var cliFormatDiscoveredPathChecksumInto = programType.GetMethod(
                    "CliFormatDiscoveredPathChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFormatDiscoveredPathChecksumInto.");
            var cliTreeDependencyDeduplicateIndicesInto = programType.GetMethod(
                    "CliTreeDependencyDeduplicateIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliTreeDependencyDeduplicateIndicesInto.");
            var cliTreeDependencyDeduplicateChecksumInto = programType.GetMethod(
                    "CliTreeDependencyDeduplicateChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliTreeDependencyDeduplicateChecksumInto.");
            var textEditOrderIndicesInto = programType.GetMethod(
                    "TextEditOrderIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TextEditOrderIndicesInto.");
            var textEditOrderChecksumInto = programType.GetMethod(
                    "TextEditOrderChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TextEditOrderChecksumInto.");
            var formatterImportOrderIndicesInto = programType.GetMethod(
                    "FormatterImportOrderIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit FormatterImportOrderIndicesInto.");
            var formatterImportOrderChecksumInto = programType.GetMethod(
                    "FormatterImportOrderChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit FormatterImportOrderChecksumInto.");
            var codeIntelligenceDocCommentChecksumInto = programType.GetMethod(
                    "CodeIntelligenceDocCommentChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceDocCommentChecksumInto.");
            var codeIntelligenceDocCommentLinesInto = programType.GetMethod(
                    "CodeIntelligenceDocCommentLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceDocCommentLinesInto.");
            var codeIntelligenceDocCommentLinesFromLinesInto = programType.GetMethod(
                    "CodeIntelligenceDocCommentLinesFromLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceDocCommentLinesFromLinesInto.");
            var codeIntelligenceVariableDeclarationNameChecksumInto = programType.GetMethod(
                    "CodeIntelligenceVariableDeclarationNameChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceVariableDeclarationNameChecksumInto.");
            var codeIntelligenceVariableDeclarationNamesInto = programType.GetMethod(
                    "CodeIntelligenceVariableDeclarationNamesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceVariableDeclarationNamesInto.");
            var buildCodeIntelligenceVariableDeclarationNameCacheInto = programType.GetMethod(
                    "BuildCodeIntelligenceVariableDeclarationNameCacheInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BuildCodeIntelligenceVariableDeclarationNameCacheInto.");
            var codeIntelligenceVariableDeclarationNamesFromCacheInto = programType.GetMethod(
                    "CodeIntelligenceVariableDeclarationNamesFromCacheInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceVariableDeclarationNamesFromCacheInto.");
            var diagnosticSeveritySummaryInto = programType.GetMethod(
                    "DiagnosticSeveritySummaryInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticSeveritySummaryInto.");
            var diagnosticSeveritySummaryChecksumInto = programType.GetMethod(
                    "DiagnosticSeveritySummaryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticSeveritySummaryChecksumInto.");
            var diagnosticSeverityFilterIndicesInto = programType.GetMethod(
                    "DiagnosticSeverityFilterIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticSeverityFilterIndicesInto.");
            var diagnosticSeverityFilterChecksumInto = programType.GetMethod(
                    "DiagnosticSeverityFilterChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticSeverityFilterChecksumInto.");
            var diagnosticShadowSuppressionIndicesInto = programType.GetMethod(
                    "DiagnosticShadowSuppressionIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticShadowSuppressionIndicesInto.");
            var diagnosticShadowSuppressionChecksumInto = programType.GetMethod(
                    "DiagnosticShadowSuppressionChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticShadowSuppressionChecksumInto.");
            var diagnosticClusterTraitsInto = programType.GetMethod(
                    "DiagnosticClusterTraitsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterTraitsInto.");
            var diagnosticClusterTraitChecksumInto = programType.GetMethod(
                    "DiagnosticClusterTraitChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterTraitChecksumInto.");
            var diagnosticClusterTraitPatternChecksumInto = programType.GetMethod(
                    "DiagnosticClusterTraitPatternChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterTraitPatternChecksumInto.");
            var diagnosticClusterTraitsAndPatternsInto = programType.GetMethod(
                    "DiagnosticClusterTraitsAndPatternsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterTraitsAndPatternsInto.");
            var diagnosticClusterIdsInto = programType.GetMethod(
                    "DiagnosticClusterIdsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterIdsInto.");
            var diagnosticClusterIdChecksumInto = programType.GetMethod(
                    "DiagnosticClusterIdChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterIdChecksumInto.");
            var diagnosticClusterNextCommandsInto = programType.GetMethod(
                    "DiagnosticClusterNextCommandsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterNextCommandsInto.");
            var diagnosticClusterNextCommandChecksumInto = programType.GetMethod(
                    "DiagnosticClusterNextCommandChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterNextCommandChecksumInto.");
            var diagnosticClusterCompactGroupsInto = programType.GetMethod(
                    "DiagnosticClusterCompactGroupsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterCompactGroupsInto.");
            var diagnosticClusterCompactGroupChecksumInto = programType.GetMethod(
                    "DiagnosticClusterCompactGroupChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterCompactGroupChecksumInto.");
            var diagnosticClusterCompactGroupMembersInto = programType.GetMethod(
                    "DiagnosticClusterCompactGroupMembersInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterCompactGroupMembersInto.");
            var diagnosticClusterCompactGroupMemberChecksumInto = programType.GetMethod(
                    "DiagnosticClusterCompactGroupMemberChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterCompactGroupMemberChecksumInto.");
            var diagnosticDeduplicateCompactInto = programType.GetMethod(
                    "DiagnosticDeduplicateCompactInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticDeduplicateCompactInto.");
            var diagnosticDeduplicateCompactChecksumInto = programType.GetMethod(
                    "DiagnosticDeduplicateCompactChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticDeduplicateCompactChecksumInto.");
            var diagnosticDeduplicateStableInto = programType.GetMethod(
                    "DiagnosticDeduplicateStableInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticDeduplicateStableInto.");
            var diagnosticDeduplicateStableChecksumInto = programType.GetMethod(
                    "DiagnosticDeduplicateStableChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticDeduplicateStableChecksumInto.");
            var formatterSafetyHasError = programType.GetMethod(
                    "FormatterSafetyHasError",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit FormatterSafetyHasError.");
            var formatterSafetyErrorIndicesInto = programType.GetMethod(
                    "FormatterSafetyErrorIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit FormatterSafetyErrorIndicesInto.");
            var formatterSafetyErrorIndicesChecksumInto = programType.GetMethod(
                    "FormatterSafetyErrorIndicesChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit FormatterSafetyErrorIndicesChecksumInto.");
            var referenceDeduplicateCompactInto = programType.GetMethod(
                    "ReferenceDeduplicateCompactInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ReferenceDeduplicateCompactInto.");
            var referenceDeduplicateCompactChecksumInto = programType.GetMethod(
                    "ReferenceDeduplicateCompactChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ReferenceDeduplicateCompactChecksumInto.");
            var referenceFileSummaryRanksInto = programType.GetMethod(
                    "ReferenceFileSummaryRanksInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ReferenceFileSummaryRanksInto.");
            var referenceFileSummaryChecksumInto = programType.GetMethod(
                    "ReferenceFileSummaryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ReferenceFileSummaryChecksumInto.");
            var bindingLookupCandidateColumnsInto = programType.GetMethod(
                    "BindingLookupCandidateColumnsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupCandidateColumnsInto.");
            var bindingLookupCandidateColumnChecksumInto = programType.GetMethod(
                    "BindingLookupCandidateColumnChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupCandidateColumnChecksumInto.");
            var bindingLookupBuildSlotsInto = programType.GetMethod(
                    "BindingLookupBuildSlotsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupBuildSlotsInto.");
            var bindingLookupQueryDeclarationIndicesInto = programType.GetMethod(
                    "BindingLookupQueryDeclarationIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupQueryDeclarationIndicesInto.");
            var bindingLookupQueryChecksumInto = programType.GetMethod(
                    "BindingLookupQueryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupQueryChecksumInto.");
            var bindingLookupBuildNearestDeclarationIndexInto = programType.GetMethod(
                    "BindingLookupBuildNearestDeclarationIndexInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupBuildNearestDeclarationIndexInto.");
            var bindingLookupBuildNearestDeclarationIndexChecksumInto = programType.GetMethod(
                    "BindingLookupBuildNearestDeclarationIndexChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupBuildNearestDeclarationIndexChecksumInto.");
            var bindingLookupFindNearestDeclarationIndicesInto = programType.GetMethod(
                    "BindingLookupFindNearestDeclarationIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupFindNearestDeclarationIndicesInto.");
            var bindingLookupFindNearestDeclarationChecksumInto = programType.GetMethod(
                    "BindingLookupFindNearestDeclarationChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupFindNearestDeclarationChecksumInto.");
            var semanticScopeVisibleSymbolIndicesInto = programType.GetMethod(
                    "SemanticScopeVisibleSymbolIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeVisibleSymbolIndicesInto.");
            var semanticScopeVisibleSymbolChecksumInto = programType.GetMethod(
                    "SemanticScopeVisibleSymbolChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeVisibleSymbolChecksumInto.");
            var semanticScopeBuildSortedIndexInto = programType.GetMethod(
                    "SemanticScopeBuildSortedIndexInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeBuildSortedIndexInto.");
            var semanticScopeBuildSortedIndexChecksumInto = programType.GetMethod(
                    "SemanticScopeBuildSortedIndexChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeBuildSortedIndexChecksumInto.");
            var semanticScopeBuildDepthsInto = programType.GetMethod(
                    "SemanticScopeBuildDepthsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeBuildDepthsInto.");
            var semanticScopeBuildDepthChecksumInto = programType.GetMethod(
                    "SemanticScopeBuildDepthChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeBuildDepthChecksumInto.");
            var semanticScopeLookupSymbolIndicesInto = programType.GetMethod(
                    "SemanticScopeLookupSymbolIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeLookupSymbolIndicesInto.");
            var semanticScopeLookupSymbolChecksumInto = programType.GetMethod(
                    "SemanticScopeLookupSymbolChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeLookupSymbolChecksumInto.");
            var declaredTypeUniqueSuffixValueRank = programType.GetMethod(
                    "DeclaredTypeUniqueSuffixValueRank",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DeclaredTypeUniqueSuffixValueRank.");
            var declaredTypeUniqueSuffixValueRankChecksum = programType.GetMethod(
                    "DeclaredTypeUniqueSuffixValueRankChecksum",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DeclaredTypeUniqueSuffixValueRankChecksum.");
            var declaredTypeNameCandidateIndex = programType.GetMethod(
                    "DeclaredTypeNameCandidateIndex",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DeclaredTypeNameCandidateIndex.");
            var declaredTypeNameCandidateChecksum = programType.GetMethod(
                    "DeclaredTypeNameCandidateChecksum",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DeclaredTypeNameCandidateChecksum.");
            var typeCreationOrderIndicesInto = programType.GetMethod(
                    "TypeCreationOrderIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TypeCreationOrderIndicesInto.");
            var typeCreationOrderChecksumInto = programType.GetMethod(
                    "TypeCreationOrderChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TypeCreationOrderChecksumInto.");
            var analyzerUnionMissingCaseChecksumInto = programType.GetMethod(
                    "AnalyzerUnionMissingCaseChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit AnalyzerUnionMissingCaseChecksumInto.");
            var analyzerOverloadSignatureDistinct = programType.GetMethod(
                    "AnalyzerOverloadSignatureDistinct",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit AnalyzerOverloadSignatureDistinct.");
            var analyzerOverloadSignatureDistinctChecksumInto = programType.GetMethod(
                    "AnalyzerOverloadSignatureDistinctChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit AnalyzerOverloadSignatureDistinctChecksumInto.");
            var declaredTypeExactNameFirstIndex = programType.GetMethod(
                    "DeclaredTypeExactNameFirstIndex",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DeclaredTypeExactNameFirstIndex.");
            var declaredTypeExactNameFirstChecksum = programType.GetMethod(
                    "DeclaredTypeExactNameFirstChecksum",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DeclaredTypeExactNameFirstChecksum.");

            const string source = """"
import System
package CompilerDogfood.Tests

func score(value: int): int {
    if value == 0 {
        return 1
    }

    text := $"score:{value}"
    raw := """
hello
world
"""
    return text.Length + raw.Length + value
}
"""";
            AssertTokenizesLikeProductionLexer(source, tokenizeCount, tokenizeKinds, tokenizeKindsInto);
            AssertTokenMetadataLikeProductionLexer(source, tokenizeMetadataInto);
            AssertParserTokenCompactionLikeProduction(
                source,
                parserTokenCompactionIndicesInto,
                parserTokenCompactionChecksumInto);

            const string keywordSource = """
func class struct interface duck union record enum namespace using import package let must const readonly
if else for foreach while in return yield match switch case default break continue throw try catch finally
new this base true false null is as typeof nameof sizeof print where when and or not
virtual override abstract sealed partial static public private internal protected async await immutable
with type assert operator required init ref out lock file params checked unchecked implicit explicit newtype
throws
""";
            AssertTokenizesLikeProductionLexer(keywordSource, tokenizeCount, tokenizeKinds, tokenizeKindsInto);
            AssertTokenMetadataLikeProductionLexer(keywordSource, tokenizeMetadataInto);
            AssertParserTokenCompactionLikeProduction(
                keywordSource,
                parserTokenCompactionIndicesInto,
                parserTokenCompactionChecksumInto);

            // Systems-language keywords: the N# scanner's KeywordKind must recognize the five systems
            // keywords the C# lexer emits (alloc/allow/stackalloc/unsafe/scoped -> ordinals 143/144/145/
            // 146/147), not fall back to Identifier. (Apostrophe-free so this stays orthogonal to the
            // separate lifetime-token gap.) Each appears alone and adjacent to a near-miss prefix to pin
            // the length-gated dispatch (e.g. "all"/"scope"/"alloca" must stay Identifiers).
            const string systemsKeywordSource = """
alloc allow stackalloc unsafe scoped
all scope alloca scopes unsaf
let a = alloc
struct unsafe scoped
""";
            AssertTokenizesLikeProductionLexer(systemsKeywordSource, tokenizeCount, tokenizeKinds, tokenizeKindsInto);
            AssertTokenMetadataLikeProductionLexer(systemsKeywordSource, tokenizeMetadataInto);
            AssertParserTokenCompactionLikeProduction(
                systemsKeywordSource,
                parserTokenCompactionIndicesInto,
                parserTokenCompactionChecksumInto);

            // Lifetime tokens: at an apostrophe the C# lexer emits a single Lifetime token (142) instead
            // of a char literal when it begins an identifier (and the char after isn't a closing quote,
            // distinguishing 'a from 'a') AND the nearest preceding non-whitespace is `<`/`,` or the word
            // `scoped`/`returns`. Brace-style (InsertIndentationBraces is a no-op) so it exercises ALL
            // three raw tokenizers + the composed path; mixes lifetimes with char literals that must STAY
            // char literals ('x', '\n', escaped quote, and `name 'a` whose preceding word isn't scoped/returns).
            const string lifetimeSource = """
func NextFrame<'a>(reader: scoped 'a): Result returns 'a {
    let c = 'x'
    let nl = '\n'
    let q = '\''
    pair<'a, 'b>
    name 'a
}
""";
            AssertTokenizesLikeProductionLexer(lifetimeSource, tokenizeCount, tokenizeKinds, tokenizeKindsInto);
            AssertTokenMetadataLikeProductionLexer(lifetimeSource, tokenizeMetadataInto);
            AssertParserTokenCompactionLikeProduction(
                lifetimeSource,
                parserTokenCompactionIndicesInto,
                parserTokenCompactionChecksumInto);

            // Unicode character classification: the scanner uses the BCL Unicode predicates
            // (char.IsWhiteSpace/IsLetter/IsLetterOrDigit/IsDigit) exactly as the C# lexer does, so
            // Unicode-letter identifiers (café, Ωmega), Unicode inline whitespace (NBSP U+00A0 separating
            // x and y into two identifiers), and a Unicode decimal digit in identifier-continuation
            // position (ident١) all tokenize identically. Flat (col 1) so no indentation braces.
            const string unicodeSource = "let café = 1\nlet x y = 2\nident١ z\n";
            AssertTokenizesLikeProductionLexer(unicodeSource, tokenizeCount, tokenizeKinds, tokenizeKindsInto);
            AssertTokenMetadataLikeProductionLexer(unicodeSource, tokenizeMetadataInto);
            AssertParserTokenCompactionLikeProduction(
                unicodeSource,
                parserTokenCompactionIndicesInto,
                parserTokenCompactionChecksumInto);

            // Char literal whose escaped body runs into a line break (`'\<CR>`): C# ReadCharLiteral does
            // NOT consume the escaped char across a line break (Lexer.cs:882), leaving the CR to become a
            // separate Newline token. Pins the ScanCharLiteral line-break guard.
            const string charLiteralLineBreakSource = "x = '\\\r\ny = 1\n";
            AssertTokenizesLikeProductionLexer(charLiteralLineBreakSource, tokenizeCount, tokenizeKinds, tokenizeKindsInto);
            AssertTokenMetadataLikeProductionLexer(charLiteralLineBreakSource, tokenizeMetadataInto);

            // Malformed numbers: the C# lexer emits an Unknown token (137) for a hex/binary prefix with
            // no valid digit immediately after (a leading '_' counts as "no digit"), a second decimal
            // point, and an exponent e/E[+/-] with no following digit. The N# scanner must produce the
            // same Unknown token (kind AND consumed span / value text) instead of an Int/Float literal.
            // Flat (col 1) so no indentation braces; each malformed number is the last token on its line.
            const string malformedNumberSource = "let a = 0x\nlet b = 0b\nlet c = 1e\nlet d = 1.2.3\nlet e = 0x_F\nlet f = 1e+\n";
            AssertTokenizesLikeProductionLexer(malformedNumberSource, tokenizeCount, tokenizeKinds, tokenizeKindsInto);
            AssertTokenMetadataLikeProductionLexer(malformedNumberSource, tokenizeMetadataInto);
            AssertParserTokenCompactionLikeProduction(
                malformedNumberSource,
                parserTokenCompactionIndicesInto,
                parserTokenCompactionChecksumInto);

            // Comment trivia: the N# CommentsInto kernel must reproduce C# Lexer.Comments. This corpus
            // mixes line/doc/block comments (incl. a multi-line block and a trailing comment with no
            // final newline) with comment-looking sequences INSIDE string and char literals that must
            // NOT be collected as comments.
            const string commentSource = """
// line comment
/// doc comment
let s = "not // a comment"
let t = "not /* still */ a comment"
let x = 1 /* trailing block */ + 2
/* multi
   line
   block */
let c = '/'
func f(): int /* eol */
""" + "\n// final comment, no trailing newline";
            AssertCommentsLikeProductionLexer(commentSource, commentsInto);
            AssertCommentsLikeProductionLexer(source, commentsInto);
            AssertCommentsLikeProductionLexer(lifetimeSource, commentsInto);

            const string metadataSource = """
package CompilerDogfood.Metadata

func values(): int {
    decimal := 1_234
    hex := 0xCA_FE
    binary := 0b1010_0101
    floating := 1.5_0e+2
    /* block
       comment */
    return decimal + hex + binary + floating
}
""";
            AssertTokenMetadataLikeProductionLexer(metadataSource, tokenizeMetadataInto);
            AssertParserTokenCompactionLikeProduction(
                metadataSource,
                parserTokenCompactionIndicesInto,
                parserTokenCompactionChecksumInto);

            // Self-host Phase 1 evidence: the N# metadata scanner must reach full token-stream parity
            // (kind, start, value length, line, column) with the production C# lexer on a single
            // representative source that exercises the broad token surface together — line/doc/block
            // comments, string + interpolated + char literals, separated int/hex/binary/float numbers,
            // a wide operator set, and a spread of keywords. This pins how production-ready the existing
            // N# lexer scanner already is for the lexer-beachhead migration (see roadmap-to-done.md).
            const string representativeSource = """
package CompilerDogfood.Representative

// line comment
/// doc comment line
/* block
   comment */
func classify(value: int, name: string): string {
    label := $"item {name}={value}"
    initial := 'x'
    decimal := 1_000
    hex := 0xFF_FF
    binary := 0b1010_1010
    ratio := 3.14_15e-2
    if value <= 0 || value >= 100 && name != "" {
        return label
    } else {
        total := value + decimal - hex * binary / 2 % 3
        flag := value == 0
        shifted := value << 2
        masked := value & 7 | 1 ^ 4
        return $"{label}:{total}:{flag}:{shifted}:{masked}:{initial}:{ratio}"
    }
}
""";
            AssertTokenMetadataLikeProductionLexer(representativeSource, tokenizeMetadataInto);
            AssertParserTokenCompactionLikeProduction(
                representativeSource,
                parserTokenCompactionIndicesInto,
                parserTokenCompactionChecksumInto);
            AssertCommentsLikeProductionLexer(representativeSource, commentsInto);
            AssertCommentsLikeProductionLexer(metadataSource, commentsInto);

            // Self-host Phase 1: the composed N# lexer entry point (TokenizeMetadataWithIndentationInto)
            // must reach full token-stream parity with the C# production lexer including the virtual
            // indentation braces. First confirm it is a correct SUPERSET on the explicit-brace corpora
            // above (InsertIndentationBraces is a no-op there, so it must equal the raw stream + EOF).
            AssertTokenMetadataWithIndentationLikeProductionLexer(source, tokenizeMetadataWithIndentationInto);
            AssertTokenMetadataWithIndentationLikeProductionLexer(keywordSource, tokenizeMetadataWithIndentationInto);
            AssertTokenMetadataWithIndentationLikeProductionLexer(systemsKeywordSource, tokenizeMetadataWithIndentationInto);
            AssertTokenMetadataWithIndentationLikeProductionLexer(metadataSource, tokenizeMetadataWithIndentationInto);
            AssertTokenMetadataWithIndentationLikeProductionLexer(representativeSource, tokenizeMetadataWithIndentationInto);

            // Then prove it on indentation-style (brace-free) source, where InsertIndentationBraces
            // actively inserts virtual { } tokens -- the remaining lexer kind-stream gap this slice closes.
            // Simple single indent + EOF close.
            const string indentSimpleSource = """
func main(): void
    print("hi")
""";
            AssertTokenMetadataWithIndentationLikeProductionLexer(indentSimpleSource, tokenizeMetadataWithIndentationInto);

            // Nested indentation, multi-level dedent at once, and a sibling block (open/close in the middle).
            const string indentNestedSource = """
func outer(): int
    if cond
        first := 1
        if inner
            deep := 2
    second := 3
    return second
""";
            AssertTokenMetadataWithIndentationLikeProductionLexer(indentNestedSource, tokenizeMetadataWithIndentationInto);

            // Globally-indented source (the leading whitespace becomes the base indent, common in test
            // strings) plus blank lines inside a block (must not perturb indentation tracking).
            const string indentGloballyIndentedSource = "    func g(): void\n        a := 1\n\n        b := 2\n    return\n";
            AssertTokenMetadataWithIndentationLikeProductionLexer(indentGloballyIndentedSource, tokenizeMetadataWithIndentationInto);

            // Parentheses spanning lines (a continuation inside parens must NOT open an indentation block)
            // mixed with an explicit-brace block (explicit braces suppress indentation insertion).
            const string indentParenContinuationSource = """
func h(): int
    total := add(
        1,
        2)
    if total > 0 {
        total = total + 1
    }
    return total
""";
            AssertTokenMetadataWithIndentationLikeProductionLexer(indentParenContinuationSource, tokenizeMetadataWithIndentationInto);

            // CRLF line endings on indentation-style source (line/column parity through \r\n).
            const string indentCrlfSource = "func c(): void\r\n    print(1)\r\n";
            AssertTokenMetadataWithIndentationLikeProductionLexer(indentCrlfSource, tokenizeMetadataWithIndentationInto);

            // Tab-indented source (each tab counts as one column, matching the C# lexer's Advance()).
            const string indentTabSource = "func t(): void\n\tprint(1)\n\t\tnested := 2\n";
            AssertTokenMetadataWithIndentationLikeProductionLexer(indentTabSource, tokenizeMetadataWithIndentationInto);

            // Inconsistent ("halfway") dedent: a dedent that lands between two stack levels pops to the
            // nearest enclosing level WITHOUT re-opening, then a later line re-indents -- the exact
            // deterministic behavior of the C# InsertIndentationBraces stack walk.
            const string indentHalfwayDedentSource = """
func k(): int
        deep := 1
    mid := 2
    return mid
""";
            AssertTokenMetadataWithIndentationLikeProductionLexer(indentHalfwayDedentSource, tokenizeMetadataWithIndentationInto);

            // Degenerate inputs: empty source (only EOF) and whitespace/newline-only source (no blocks
            // ever open, so no braces are inserted and nothing under/overflows).
            AssertTokenMetadataWithIndentationLikeProductionLexer("", tokenizeMetadataWithIndentationInto);
            AssertTokenMetadataWithIndentationLikeProductionLexer("   \n  \n", tokenizeMetadataWithIndentationInto);

            // Composed-path coverage for the flat lifetime/unicode/char-literal/malformed-number corpora
            // (InsertIndentationBraces is a no-op on them, so the composed entry must equal the raw stream).
            AssertTokenMetadataWithIndentationLikeProductionLexer(lifetimeSource, tokenizeMetadataWithIndentationInto);
            AssertTokenMetadataWithIndentationLikeProductionLexer(unicodeSource, tokenizeMetadataWithIndentationInto);
            AssertTokenMetadataWithIndentationLikeProductionLexer(charLiteralLineBreakSource, tokenizeMetadataWithIndentationInto);
            AssertTokenMetadataWithIndentationLikeProductionLexer(malformedNumberSource, tokenizeMetadataWithIndentationInto);

            // Indentation-style source containing lifetimes + a char literal (virtual braces interleaved
            // with Lifetime(142)/CharLiteral(3) tokens in one stream).
            const string indentLifetimeSource = """
func gen<'a>(x: scoped 'a): int
    return uses<'a>('x')
""";
            AssertTokenMetadataWithIndentationLikeProductionLexer(indentLifetimeSource, tokenizeMetadataWithIndentationInto);

            // Real-corpus dogfood: run the COMPLETE N# lexer (composed metadata-with-indentation +
            // comment trivia) against the C# production lexer over every real .nl file in examples/ and
            // the dogfood compiler-service kernels themselves. This exercises the full token + comment
            // stream on diverse, real systems-N# source (lifetimes, scoped/unsafe keywords, raw/
            // interpolated strings, comments, indentation) -- the strongest correctness check that the
            // N# lexer matches C# on the code the compiler is actually written in.
            var realCorpusDirs = new[]
            {
                Path.Combine(repoRoot, "examples"),
                Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood", "CompilerServices"),
            };
            var realCorpusFiles = realCorpusDirs
                .Where(Directory.Exists)
                .SelectMany(dir => Directory.EnumerateFiles(dir, "*.nl", SearchOption.AllDirectories))
                .OrderBy(path => path, StringComparer.Ordinal)
                .ToArray();
            Assert.NotEmpty(realCorpusFiles);
            foreach (var file in realCorpusFiles)
            {
                var realSource = File.ReadAllText(file);
                AssertTokenMetadataWithIndentationLikeProductionLexer(realSource, tokenizeMetadataWithIndentationInto);
                AssertCommentsLikeProductionLexer(realSource, commentsInto);
            }

            AssertSourceTextLineMapLikeProduction(
                "",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one\n",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one\r\n",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one\rtwo",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one\r\ntwo\rthree\n",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "\r\n\r\n\n\r",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);

            AssertIdentifierSpansLikeProduction(
                """
func main() {
    value := input.Count
    print value
}
""",
                codeIntelligenceIdentifierSpanChecksumInto,
                codeIntelligenceIdentifierSpansInto);
            AssertIdentifierSpansLikeProduction(
                "package CompilerDogfood.Tests\r\nfunc main(): int {\r\n    return value\r\n}\r\n",
                codeIntelligenceIdentifierSpanChecksumInto,
                codeIntelligenceIdentifierSpansInto);
            AssertIdentifierSpansLikeProduction(
                "func main() {\r    value := input.Count\r}\n",
                codeIntelligenceIdentifierSpanChecksumInto,
                codeIntelligenceIdentifierSpansInto);
            AssertIdentifierSpansLikeProduction(
                "func main() {\n    café42 := résumé.Count\n    print café42\n}\n",
                codeIntelligenceIdentifierSpanChecksumInto,
                codeIntelligenceIdentifierSpansInto);
            AssertEditorIdentifierSpansLikeProduction(
                """
func main() {
    value := input.Count
    print value
}
""",
                codeIntelligenceEditorIdentifierSpanChecksumInto,
                codeIntelligenceEditorIdentifierSpansInto);
            AssertEditorIdentifierSpansLikeProduction(
                "func main() {\n    café42 := résumé.Count\n    print café42\n}\n",
                codeIntelligenceEditorIdentifierSpanChecksumInto,
                codeIntelligenceEditorIdentifierSpansInto);
            AssertDeclarationNameMatchesLikeProduction(
                """
func main() {
    value := value + 1
    prefixvalue := 0
    café := café
}
""",
                codeIntelligenceDeclarationNameMatchChecksumInto,
                codeIntelligenceDeclarationNameMatchesFromLinesInto);
            AssertIdentifierNameColumnsLikeProduction(
                "func main() {\r\n    prefixvalue := value\r\n    café := café + value\r\n    spaced    := 4\r\n}\r\n",
                codeIntelligenceIdentifierNameColumnChecksumInto,
                codeIntelligenceIdentifierNameColumnsInto,
                buildCodeIntelligenceLineRangesInto,
                codeIntelligenceIdentifierNameColumnsFromLinesInto);

            AssertMemberReceiversLikeProduction(
                """
func main(customer: Customer, résumé: Profile) {
    print customer.Name
    print customer   .Name
    print customer?.Name
    print résumé.Count
}
""",
                codeIntelligenceMemberReceiverChecksumInto,
                codeIntelligenceMemberReceiversInto,
                codeIntelligenceMemberReceiverCachedChecksumInto,
                codeIntelligenceMemberReceiversCachedInto);
            AssertSourceContextsLikeProduction(
                "  first line  \n\tsecond line\r\n   \n\n café42  \n",
                codeIntelligenceSourceContextChecksumInto,
                codeIntelligenceSourceContextsInto);
            AssertSourceLinesLikeProduction(
                "  first line  \n\tsecond line\r\n   \n\n café42  \n",
                codeIntelligenceSourceLineChecksumInto,
                codeIntelligenceSourceLinesInto,
                codeIntelligenceSourceLinesFromLinesInto);
            AssertPathMatchingLikeProduction(
                codeIntelligencePathMatches,
                codeIntelligencePathMatchChecksumInto);
            AssertProjectSourceFilterLikeProduction(
                projectSourceFilterKeptIndicesInto,
                projectSourceFilterKeptChecksumInto);
            AssertCompletionPrefixesLikeProduction(
                "  first line  \n\tsecond line\r\n   \n\n café42  \n",
                codeIntelligenceCompletionPrefixChecksumInto,
                codeIntelligenceCompletionPrefixesInto,
                codeIntelligenceCompletionPrefixesFromLinesInto);
            AssertCompletionReceiversLikeProduction(
                codeIntelligenceCompletionReceiverChecksumInto,
                codeIntelligenceCompletionReceiversInto);
            AssertCompletionItemGroupingLikeProduction(
                completionItemKindGroupsInto,
                completionItemKindGroupChecksumInto);
            AssertCompletionMethodGroupingLikeProduction(
                completionMethodOverloadGroupsInto,
                completionMethodOverloadGroupChecksumInto);
            AssertCliQueryPositionsLikeProduction(
                cliTryParsePositionInto,
                cliQueryPositionsInto,
                cliQueryPositionChecksumInto);
            AssertCliBuildOperandsLikeProduction(
                cliBuildOperandIndicesInto,
                cliBuildOperandSummaryInto,
                cliBuildFirstOperandIndexInto);
            AssertCliBuildOptionsLikeProduction(
                cliBuildOptionSummaryInto,
                cliBuildOptionSummaryChecksumInto);
            AssertCliExportCSharpInputOperandLikeProduction(
                cliExportCSharpFirstOperandIndexInto,
                cliExportCSharpFirstOperandChecksumInto);
            AssertCliRunSourceOperandLikeProduction(cliRunFirstOperandIndex);
            AssertCliWatchForwardedArgsLikeProduction(
                cliWatchForwardedArgIndicesInto,
                cliWatchForwardedArgChecksumInto);
            AssertCliPublishOptionsLikeProduction(cliPublishOptionsInto);
            AssertCliPositionalArgsLikeProduction(
                cliPositionalArgIndicesInto,
                cliFirstPositionalArgIndex,
                cliPositionalArgChecksumInto);
            AssertCliLintFileArgsLikeProduction(
                cliLintFileArgIndicesInto,
                cliLintFileArgChecksumInto);
            AssertCliTidyDependencyClassificationLikeProduction(
                cliTidyDependencyStatusRanksInto,
                cliTidyDependencyStatusRankChecksumInto);
            AssertCliTidyRemovalLinesLikeProduction(
                cliTidyRemovalLineKeepFlagsInto,
                cliTidyRemovalLineKeepChecksumInto);
            AssertCliFixSafetyFilteringLikeProduction(
                cliFixSafetyFilterIndicesInto,
                cliFixSafetyFilterChecksumInto,
                cliFixEditFlattenIndicesInto,
                cliFixEditFlattenChecksumInto,
                cliFixSkippedIndicesInto,
                cliFixSkippedChecksumInto);
            AssertCliFixAppliedFileGroupingLikeProduction(
                cliFixAppliedFileGroupsInto,
                cliFixAppliedFileGroupChecksumInto);
            AssertCliUnifiedDiffHunkRangesLikeProduction(
                cliUnifiedDiffHunkRangesInto,
                cliUnifiedDiffHunkRangeChecksumInto);
            AssertCliCleanArtifactDirectoryOrderingLikeProduction(
                cliCleanArtifactDirectoryIndicesInto,
                cliCleanArtifactDirectoryChecksumInto);
            AssertCliUpdateAllNuGetDependencyFilteringLikeProduction(
                cliUpdateAllNuGetDependencyIndicesInto,
                cliUpdateAllNuGetDependencyChecksumInto);
            AssertCliUpdateTargetNuGetDependencyFilteringLikeProduction(
                cliUpdateTargetNuGetDependencyIndicesInto,
                cliUpdateTargetNuGetDependencyChecksumInto);
            AssertCliReferenceTypeFilteringLikeProduction(
                cliReferenceTypeFilterIndicesInto,
                cliReferenceTypeFilterChecksumInto);
            AssertCliReferenceResolutionBestScoreSelectionLikeProduction(
                cliReferenceResolutionBestScoreIndex,
                cliReferenceResolutionBestScoreChecksum);
            AssertCliDocSymbolOrderingLikeProduction(
                cliDocSymbolOrderCountingIndicesInto,
                cliDocSymbolOrderCountingChecksumInto);
            AssertCliDocMemberOrderingLikeProduction(
                cliDocSymbolOrderCountingIndicesInto,
                cliDocSymbolOrderCountingChecksumInto);
            AssertCliDocSlugsLikeProduction(cliDocSlugsInto);
            AssertCliSymbolNameGlobFilteringLikeProduction(cliSymbolNameGlobFilterIndicesInto);
            AssertCliSymbolNameSubstringFilteringLikeProduction(cliSymbolNameSubstringFilterIndicesInto);
            AssertSymbolKindFilteringLikeProduction(
                symbolKindFilterIndicesInto,
                symbolKindFilterChecksumInto);
            AssertDocQueryBestTypeSelectionLikeProduction(
                docQueryBestTypeIndex,
                docQueryBestTypeChecksumInto);
            AssertDocQueryMemberOrderingLikeProduction(
                docQueryMemberOrderIndicesInto,
                docQueryMemberOrderChecksumInto);
            AssertTypoSuggestionsLikeProduction(
                typoSuggestionIndicesInto,
                typoSuggestionChecksumInto);
            AssertAotRequirementGroupingLikeProduction(
                aotRequirementGroupsInto,
                aotRequirementGroupChecksumInto);
            AssertCliBatchDuplicateIdsLikeProduction(
                cliBatchDuplicateIdRanksInto,
                cliBatchDuplicateIdRankChecksumInto);
            AssertCliBatchResultCountsLikeProduction(cliBatchResultPackedCountChecksum);
            AssertCliTestOutcomeSummaryLikeProduction(cliTestOutcomeSummaryChecksumInto);
            AssertCliFormatDiscoveryLikeProduction(
                cliShouldFormatDiscoveredPath,
                cliFormatDiscoveredPathChecksumInto);
            AssertCliTreeDependencyDeduplicationLikeProduction(
                cliTreeDependencyDeduplicateIndicesInto,
                cliTreeDependencyDeduplicateChecksumInto);
            AssertTextEditOrderingLikeProduction(
                textEditOrderIndicesInto,
                textEditOrderChecksumInto);
            AssertFormatterImportOrderingLikeProduction(
                formatterImportOrderIndicesInto,
                formatterImportOrderChecksumInto);
            AssertDocCommentsLikeProduction(
                """
// ignored

// First line
///   Second line~~
//// Third line
~~~~
func documented(): int {
    return 1
}

// Nearest line only

// Skipped because blank follows comment
func another(): int {
    return 2
}

// Empty follows
///
func emptyDoc(): int {
    return 3
}
""".Replace('~', ' '),
                codeIntelligenceDocCommentChecksumInto,
                codeIntelligenceDocCommentLinesInto,
                codeIntelligenceDocCommentLinesFromLinesInto);
            AssertVariableDeclarationNamesLikeProduction(
                """
func main() {
    value := 1
	résumé_42 := value
    customer.Name := "Ada"
    spaced    := 4
    := missing
    noAssign
}
""",
                codeIntelligenceVariableDeclarationNameChecksumInto,
                codeIntelligenceVariableDeclarationNamesInto,
                buildCodeIntelligenceVariableDeclarationNameCacheInto,
                codeIntelligenceVariableDeclarationNamesFromCacheInto);
            AssertDiagnosticClusterTraitsLikeProduction(
                diagnosticClusterTraitsInto,
                diagnosticClusterTraitChecksumInto,
                diagnosticClusterTraitPatternChecksumInto,
                diagnosticClusterTraitsAndPatternsInto);
            AssertDiagnosticClusterIdsLikeProduction(
                diagnosticClusterIdsInto,
                diagnosticClusterIdChecksumInto);
            AssertDiagnosticClusterNextCommandsLikeProduction(
                diagnosticClusterNextCommandsInto,
                diagnosticClusterNextCommandChecksumInto);
            AssertDiagnosticClusterGroupsLikeProduction(
                diagnosticClusterCompactGroupsInto,
                diagnosticClusterCompactGroupChecksumInto,
                diagnosticClusterCompactGroupMembersInto,
                diagnosticClusterCompactGroupMemberChecksumInto);
            AssertDiagnosticDeduplicationLikeProduction(
                diagnosticDeduplicateCompactInto,
                diagnosticDeduplicateCompactChecksumInto,
                diagnosticDeduplicateStableInto,
                diagnosticDeduplicateStableChecksumInto);
            AssertFormatterSafetyScanLikeProduction(
                formatterSafetyHasError,
                formatterSafetyErrorIndicesInto,
                formatterSafetyErrorIndicesChecksumInto);
            AssertReferenceDeduplicationLikeProduction(
                referenceDeduplicateCompactInto,
                referenceDeduplicateCompactChecksumInto);
            AssertReferenceFileSummaryLikeProduction(
                referenceFileSummaryRanksInto,
                referenceFileSummaryChecksumInto);
            AssertBindingLookupLikeProduction(
                bindingLookupCandidateColumnsInto,
                bindingLookupCandidateColumnChecksumInto,
                bindingLookupBuildSlotsInto,
                bindingLookupQueryDeclarationIndicesInto,
                bindingLookupQueryChecksumInto,
                bindingLookupBuildNearestDeclarationIndexInto,
                bindingLookupBuildNearestDeclarationIndexChecksumInto,
                bindingLookupFindNearestDeclarationIndicesInto,
                bindingLookupFindNearestDeclarationChecksumInto);
            AssertSemanticScopeVisibleVariablesLikeProduction(
                semanticScopeVisibleSymbolIndicesInto,
                semanticScopeVisibleSymbolChecksumInto,
                semanticScopeBuildSortedIndexInto,
                semanticScopeBuildSortedIndexChecksumInto,
                semanticScopeBuildDepthsInto,
                semanticScopeBuildDepthChecksumInto,
                semanticScopeLookupSymbolIndicesInto,
                semanticScopeLookupSymbolChecksumInto);
            AssertAnalyzerUnionMissingCasesLikeProduction(analyzerUnionMissingCaseChecksumInto);
            AssertAnalyzerOverloadSignatureDistinctLikeProduction(
                analyzerOverloadSignatureDistinct,
                analyzerOverloadSignatureDistinctChecksumInto);
            AssertDeclaredTypeExactNameLookupLikeProduction(
                declaredTypeExactNameFirstIndex,
                declaredTypeExactNameFirstChecksum);
            AssertDiagnosticSeveritySummaryLikeProduction(
                diagnosticSeveritySummaryInto,
                diagnosticSeveritySummaryChecksumInto);
            AssertDiagnosticSeverityFilteringLikeProduction(
                diagnosticSeverityFilterIndicesInto,
                diagnosticSeverityFilterChecksumInto);
            AssertDiagnosticShadowSuppressionLikeProduction(
                diagnosticShadowSuppressionIndicesInto,
                diagnosticShadowSuppressionChecksumInto);
        }
        finally
        {
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    private static void AssertTokenizesLikeProductionLexer(
        string source,
        MethodInfo tokenizeCount,
        MethodInfo tokenizeKinds,
        MethodInfo tokenizeKindsInto)
    {
        var expectedKinds = new Lexer(source, "dogfood-test.nl")
            .Tokenize()
            .Select(static token => (int)token.Type)
            .ToArray();

        var count = (int)(tokenizeCount.Invoke(null, new object[] { source }) ?? -1);
        var kinds = (int[])(tokenizeKinds.Invoke(null, new object[] { source })
            ?? throw new InvalidOperationException("TokenizeKinds returned null."));
        var buffer = new int[source.Length + 1];
        var bufferedCount = (int)(tokenizeKindsInto.Invoke(null, new object[] { source, buffer }) ?? -1);

        Assert.Equal(expectedKinds.Length, count);
        Assert.Equal(expectedKinds, kinds);
        Assert.Equal(expectedKinds.Length, bufferedCount);
        Assert.Equal(expectedKinds, buffer.Take(bufferedCount).ToArray());
    }

    private static void AssertTokenMetadataLikeProductionLexer(
        string source,
        MethodInfo tokenizeMetadataInto)
    {
        var expectedTokens = new Lexer(source, "dogfood-test.nl").Tokenize();
        var capacity = source.Length + 1;
        var kinds = new int[capacity];
        var starts = new int[capacity];
        var valueLengths = new int[capacity];
        var lines = new int[capacity];
        var columns = new int[capacity];

        var count = (int)(tokenizeMetadataInto.Invoke(
            null,
            new object[] { source, kinds, starts, valueLengths, lines, columns }) ?? -1);

        Assert.Equal(expectedTokens.Count, count);

        var lineStarts = BuildLineStarts(source);
        for (var i = 0; i < expectedTokens.Count; i++)
        {
            var token = expectedTokens[i];
            Assert.Equal((int)token.Type, kinds[i]);
            Assert.Equal(TokenStartFromLineColumn(lineStarts, token.Line, token.Column, source.Length), starts[i]);
            Assert.Equal(token.Value.Length, valueLengths[i]);
            Assert.Equal(token.Line, lines[i]);
            Assert.Equal(token.Column, columns[i]);
        }
    }

    private static void AssertTokenMetadataWithIndentationLikeProductionLexer(
        string source,
        MethodInfo tokenizeMetadataWithIndentationInto)
    {
        // The composed N# entry point (raw tokenize + indentation-brace post-pass) must reproduce the
        // production C# lexer's full token stream -- including the virtual { } tokens InsertIndentationBraces
        // inserts -- on BOTH explicit-brace and indentation-style source. Buffers are sized to the safe
        // upper bound for the grown stream (<= 3x the raw token count).
        var expectedTokens = new Lexer(source, "dogfood-test.nl").Tokenize();
        var capacity = 3 * (source.Length + 1) + 8;
        var kinds = new int[capacity];
        var starts = new int[capacity];
        var valueLengths = new int[capacity];
        var lines = new int[capacity];
        var columns = new int[capacity];

        var count = (int)(tokenizeMetadataWithIndentationInto.Invoke(
            null,
            new object[] { source, kinds, starts, valueLengths, lines, columns }) ?? -1);

        Assert.Equal(expectedTokens.Count, count);

        var lineStarts = BuildLineStarts(source);
        for (var i = 0; i < expectedTokens.Count; i++)
        {
            var token = expectedTokens[i];
            Assert.Equal((int)token.Type, kinds[i]);
            Assert.Equal(TokenStartFromLineColumn(lineStarts, token.Line, token.Column, source.Length), starts[i]);
            Assert.Equal(token.Value.Length, valueLengths[i]);
            Assert.Equal(token.Line, lines[i]);
            Assert.Equal(token.Column, columns[i]);
        }
    }

    private static void AssertCommentsLikeProductionLexer(string source, MethodInfo commentsInto)
    {
        // The N# comment-trivia kernel must reproduce the C# production lexer's Lexer.Comments exactly
        // (line, column, start offset, text length, and isMultiLine), including NOT treating // or /*
        // inside string/char/lifetime literals as comments.
        var lexer = new Lexer(source, "dogfood-test.nl");
        lexer.Tokenize();
        var expected = lexer.Comments;

        var capacity = source.Length + 1;
        var lines = new int[capacity];
        var columns = new int[capacity];
        var starts = new int[capacity];
        var lengths = new int[capacity];
        var isMultiLine = new int[capacity];

        var count = (int)(commentsInto.Invoke(
            null,
            new object[] { source, lines, columns, starts, lengths, isMultiLine }) ?? -1);

        Assert.Equal(expected.Count, count);

        var lineStarts = BuildLineStarts(source);
        for (var i = 0; i < expected.Count; i++)
        {
            var c = expected[i];
            Assert.Equal(c.Line, lines[i]);
            Assert.Equal(c.Column, columns[i]);
            Assert.Equal(TokenStartFromLineColumn(lineStarts, c.Line, c.Column, source.Length), starts[i]);
            Assert.Equal(c.Text.Length, lengths[i]);
            Assert.Equal(c.IsMultiLine ? 1 : 0, isMultiLine[i]);
        }
    }

    private static void AssertParserTokenCompactionLikeProduction(
        string source,
        MethodInfo parserTokenCompactionIndicesInto,
        MethodInfo parserTokenCompactionChecksumInto)
    {
        var tokenKinds = new Lexer(source, "dogfood-test.nl")
            .Tokenize()
            .Select(static token => (int)token.Type)
            .ToArray();
        var expectedIndices = tokenKinds
            .Select((kind, index) => (kind, index))
            .Where(static item => item.kind != (int)TokenType.Newline)
            .Select(static item => item.index)
            .ToArray();

        var actualIndices = new int[tokenKinds.Length];
        var actualCount = (int)(parserTokenCompactionIndicesInto.Invoke(
            null,
            new object[] { tokenKinds, actualIndices }) ?? -1);

        Assert.Equal(expectedIndices.Length, actualCount);
        Assert.Equal(expectedIndices, actualIndices.Take(actualCount).ToArray());

        var checksumIndices = new int[tokenKinds.Length];
        var actualChecksum = (int)(parserTokenCompactionChecksumInto.Invoke(
            null,
            new object[] { tokenKinds, checksumIndices }) ?? -1);
        var expectedChecksum = ParserTokenCompactionChecksum(expectedIndices, tokenKinds);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedIndices, checksumIndices.Take(expectedIndices.Length).ToArray());
    }

    private static int ParserTokenCompactionChecksum(int[] orderedIndices, int[] tokenKinds)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            checksum += (i + 1) * 97 + tokenKinds[orderedIndices[i]] * 17;
        }

        return checksum;
    }

    private static void AssertAnalyzerUnionMissingCasesLikeProduction(MethodInfo analyzerUnionMissingCaseChecksumInto)
    {
        var coveredFlags = new[] { 0, 1, 0, 1, 0, 0 };
        var partialFlags = new[] { 0, 0, 1, 0, 1, 0 };
        var nameWeights = new[] { 7, 11, 13, 17, 19, 23 };
        var missingIndices = new int[coveredFlags.Length];
        var partialMissingIndices = new int[coveredFlags.Length];
        var neverCoveredIndices = new int[coveredFlags.Length];
        var resultCounts = new int[3];

        var checksum = (int)(analyzerUnionMissingCaseChecksumInto.Invoke(
            null,
            new object[]
            {
                coveredFlags,
                partialFlags,
                coveredFlags.Length,
                nameWeights,
                missingIndices,
                partialMissingIndices,
                neverCoveredIndices,
                resultCounts
            }) ?? -1);

        var expectedMissingIndices = new[] { 0, 2, 4, 5 };
        var expectedPartialMissingIndices = new[] { 2, 4 };
        var expectedNeverCoveredIndices = new[] { 0, 5 };

        Assert.Equal(new[] { 4, 2, 2 }, resultCounts);
        Assert.Equal(expectedMissingIndices, missingIndices.Take(resultCounts[0]).ToArray());
        Assert.Equal(expectedPartialMissingIndices, partialMissingIndices.Take(resultCounts[1]).ToArray());
        Assert.Equal(expectedNeverCoveredIndices, neverCoveredIndices.Take(resultCounts[2]).ToArray());
        Assert.Equal(
            AnalyzerUnionMissingCaseChecksum(
                expectedMissingIndices,
                expectedPartialMissingIndices,
                expectedNeverCoveredIndices,
                nameWeights),
            checksum);

        var invalidChecksum = (int)(analyzerUnionMissingCaseChecksumInto.Invoke(
            null,
            new object[]
            {
                coveredFlags,
                partialFlags,
                coveredFlags.Length + 1,
                nameWeights,
                new int[coveredFlags.Length],
                new int[coveredFlags.Length],
                new int[coveredFlags.Length],
                new int[3]
            }) ?? 0);
        Assert.Equal(-1, invalidChecksum);
    }

    private static void AssertDeclaredTypeExactNameLookupLikeProduction(
        MethodInfo declaredTypeExactNameFirstIndex,
        MethodInfo declaredTypeExactNameFirstChecksum)
    {
        var names = new[]
        {
            "Project.Local.Container",
            "Project.Local.Container.Inner",
            "Project.Local.Container.Inner.Leaf",
            "Project.Other.Container",
            "Project.Local.Container.Inner"
        };
        var nameWeights = new int[names.Length];
        for (var i = 0; i < names.Length; i++)
        {
            nameWeights[i] = names[i].Length;
        }

        // Mirror the production fallback: first ordinal exact-name match wins.
        int CSharpFirstIndex(string typeName, int count)
        {
            for (var i = 0; i < count; i++)
            {
                if (string.Equals(names[i], typeName, StringComparison.Ordinal))
                {
                    return i + 1;
                }
            }

            return 0;
        }

        int TailHash(string text)
        {
            var width = Math.Min(4, text.Length);
            var hash = 0;
            for (var offset = 0; offset < width; offset++)
            {
                hash = hash * 31 + text[text.Length - 1 - offset];
            }

            return hash;
        }

        var tailHashes = names.Select(TailHash).ToArray();

        // Build positive queries as fresh, non-interned instances so the assertion verifies N#
        // string '==' performs ordinal value equality (not reference equality against the interned
        // literals already stored in names).
        static string Fresh(string value) => new(value.ToCharArray());

        foreach (var query in new[]
        {
            Fresh("Project.Local.Container"),          // first top-level
            Fresh("Project.Local.Container.Inner"),    // earliest of two duplicates (index 1, not 4)
            Fresh("Project.Other.Container"),          // later unique match
            Fresh("Project.Missing.Type"),             // no match
            ""                                          // empty query short-circuits the tail-hash gate
        })
        {
            var expectedIndex = CSharpFirstIndex(query, names.Length);
            var actualIndex = (int)(declaredTypeExactNameFirstIndex.Invoke(
                null,
                new object[] { names, tailHashes, query, TailHash(query), names.Length }) ?? -99);
            Assert.Equal(expectedIndex, actualIndex);

            var expectedChecksum = expectedIndex <= 0
                ? expectedIndex
                : expectedIndex * 97 + nameWeights[expectedIndex - 1] * 31;
            var actualChecksum = (int)(declaredTypeExactNameFirstChecksum.Invoke(
                null,
                new object[] { names, tailHashes, query, TailHash(query), names.Length, nameWeights }) ?? -99);
            Assert.Equal(expectedChecksum, actualChecksum);
        }

        // Out-of-range count is rejected.
        var invalid = (int)(declaredTypeExactNameFirstIndex.Invoke(
            null,
            new object[] { names, tailHashes, "Project.Local.Container", TailHash("Project.Local.Container"), names.Length + 1 }) ?? 0);
        Assert.Equal(-2, invalid);
    }

    private static int AnalyzerUnionMissingCaseChecksum(
        int[] missingIndices,
        int[] partialMissingIndices,
        int[] neverCoveredIndices,
        int[] nameWeights)
    {
        var checksum = missingIndices.Length * 31 + partialMissingIndices.Length * 17 + neverCoveredIndices.Length * 13;
        for (var i = 0; i < missingIndices.Length; i++)
        {
            var sourceIndex = missingIndices[i];
            var weight = sourceIndex >= 0 && sourceIndex < nameWeights.Length ? nameWeights[sourceIndex] : 0;
            checksum += (i + 1) * 97 + (sourceIndex + 1) * 31 + weight * 17;
        }

        for (var i = 0; i < partialMissingIndices.Length; i++)
        {
            var sourceIndex = partialMissingIndices[i];
            checksum += (i + 1) * 43 + (sourceIndex + 1) * 19;
        }

        for (var i = 0; i < neverCoveredIndices.Length; i++)
        {
            var sourceIndex = neverCoveredIndices[i];
            checksum += (i + 1) * 37 + (sourceIndex + 1) * 23;
        }

        return checksum;
    }

    private static void AssertAnalyzerOverloadSignatureDistinctLikeProduction(
        MethodInfo analyzerOverloadSignatureDistinct,
        MethodInfo analyzerOverloadSignatureDistinctChecksumInto)
    {
        // Existing overload group: three rows of parameter-type ranks.
        //   row 0: (int)            -> ranks [1]
        //   row 1: (int, string)    -> ranks [1, 2]
        //   row 2: (string, int)    -> ranks [2, 1]   (order matters, distinct from row 1)
        var existingRanks = new[] { 1, 1, 2, 2, 1 };
        var existingOffsets = new[] { 0, 1, 3 };
        var existingLengths = new[] { 1, 2, 2 };
        var existingCount = 3;

        // Single-shot distinct verdicts (1 = distinct/new overload, 0 = duplicate).
        // Duplicate of row 1 (int, string).
        Assert.Equal(0, InvokeOverloadDistinct(
            analyzerOverloadSignatureDistinct,
            new[] { 1, 2 }, 2, existingRanks, existingOffsets, existingLengths, existingCount));
        // Same multiset but swapped order -> matches row 2 exactly (string, int).
        Assert.Equal(0, InvokeOverloadDistinct(
            analyzerOverloadSignatureDistinct,
            new[] { 2, 1 }, 2, existingRanks, existingOffsets, existingLengths, existingCount));
        // Distinct arity-2 row (int, int) -> new overload.
        Assert.Equal(1, InvokeOverloadDistinct(
            analyzerOverloadSignatureDistinct,
            new[] { 1, 1 }, 2, existingRanks, existingOffsets, existingLengths, existingCount));
        // Distinct arity-0 row -> new overload (no existing zero-arity row).
        Assert.Equal(1, InvokeOverloadDistinct(
            analyzerOverloadSignatureDistinct,
            Array.Empty<int>(), 0, existingRanks, existingOffsets, existingLengths, existingCount));
        // Distinct against an empty existing group -> always new.
        Assert.Equal(1, InvokeOverloadDistinct(
            analyzerOverloadSignatureDistinct,
            new[] { 1, 2 }, 2, existingRanks, existingOffsets, existingLengths, 0));
        // Malformed: candidate length exceeds buffer.
        Assert.Equal(-1, InvokeOverloadDistinct(
            analyzerOverloadSignatureDistinct,
            new[] { 1 }, 5, existingRanks, existingOffsets, existingLengths, existingCount));

        // Batched checksum + per-candidate verdicts (covered/partial/exhaustive analogues:
        // candidate[0] duplicate, candidate[1] distinct order-swap-not-matching, candidate[2] distinct).
        var candidateRanks = new[] { 1, 2, /*c0 dup row1*/ 1, 1, /*c1 distinct*/ 5, 6, 7 /*c2 distinct arity3*/ };
        var candidateOffsets = new[] { 0, 2, 4 };
        var candidateLengths = new[] { 2, 2, 3 };
        var candidateCount = 3;
        var results = new int[candidateCount];

        var checksum = (int)(analyzerOverloadSignatureDistinctChecksumInto.Invoke(
            null,
            new object[]
            {
                candidateRanks,
                candidateOffsets,
                candidateLengths,
                candidateCount,
                existingRanks,
                existingOffsets,
                existingLengths,
                existingCount,
                results
            }) ?? -1);

        var expectedVerdicts = new[] { 0, 1, 1 };
        Assert.Equal(expectedVerdicts, results);
        Assert.Equal(
            AnalyzerOverloadSignatureDistinctChecksum(expectedVerdicts, candidateLengths),
            checksum);

        // Malformed batched request: candidate offset/length overruns the packed buffer.
        var malformed = (int)(analyzerOverloadSignatureDistinctChecksumInto.Invoke(
            null,
            new object[]
            {
                candidateRanks,
                new[] { 0 },
                new[] { candidateRanks.Length + 1 },
                1,
                existingRanks,
                existingOffsets,
                existingLengths,
                existingCount,
                new int[1]
            }) ?? 0);
        Assert.Equal(-1, malformed);
    }

    private static int InvokeOverloadDistinct(
        MethodInfo analyzerOverloadSignatureDistinct,
        int[] candidateRanks,
        int candidateLength,
        int[] existingRanks,
        int[] existingOffsets,
        int[] existingLengths,
        int existingCount)
        => (int)(analyzerOverloadSignatureDistinct.Invoke(
            null,
            new object[]
            {
                candidateRanks,
                candidateLength,
                existingRanks,
                existingOffsets,
                existingLengths,
                existingCount
            }) ?? int.MinValue);

    private static int AnalyzerOverloadSignatureDistinctChecksum(int[] verdicts, int[] candidateLengths)
    {
        var checksum = verdicts.Length;
        var distinctCount = 0;
        for (var c = 0; c < verdicts.Length; c++)
        {
            var verdict = verdicts[c];
            if (verdict == 1)
            {
                distinctCount++;
            }

            checksum += (c + 1) * 131 + (verdict + 1) * 17 + (candidateLengths[c] + 1) * 7;
        }

        checksum += distinctCount * 9973;
        return checksum;
    }

    private static int[] BuildLineStarts(string source)
    {
        var starts = new List<int> { 0 };
        var position = 0;
        while (position < source.Length)
        {
            if (source[position] == '\r')
            {
                position++;
                if (position < source.Length && source[position] == '\n')
                {
                    position++;
                }

                starts.Add(position);
                continue;
            }

            if (source[position] == '\n')
            {
                position++;
                starts.Add(position);
                continue;
            }

            position++;
        }

        return starts.ToArray();
    }

    private static int TokenStartFromLineColumn(int[] lineStarts, int line, int column, int sourceLength)
    {
        var lineIndex = line - 1;
        if (lineIndex < 0 || lineIndex >= lineStarts.Length)
        {
            return sourceLength;
        }

        return Math.Min(sourceLength, lineStarts[lineIndex] + column - 1);
    }

    private static void AssertSourceTextLineMapLikeProduction(
        string source,
        MethodInfo splitLogicalLines,
        MethodInfo splitLogicalLineRangesInto,
        MethodInfo buildLogicalLineStartsInto,
        MethodInfo getLineIndexFromOffset,
        MethodInfo getColumnFromOffset,
        MethodInfo getOffsetFromLineColumn,
        MethodInfo lineMapCachedChecksumInto,
        MethodInfo lineMapCachedQueryChecksumInto,
        MethodInfo lineMapTrustedCachedQueryChecksumInto)
    {
        var expected = SourceTextLines.SplitLogicalLines(source);
        var actual = (string[])(splitLogicalLines.Invoke(null, new object[] { source })
            ?? throw new InvalidOperationException("SplitLogicalLines returned null."));

        Assert.Equal(expected, actual);

        var starts = new int[source.Length + 1];
        var lengths = new int[source.Length + 1];
        var count = (int)(splitLogicalLineRangesInto.Invoke(null, new object[] { source, starts, lengths }) ?? -1);
        Assert.Equal(expected.Length, count);
        for (var i = 0; i < count; i++)
        {
            Assert.Equal(expected[i], source.Substring(starts[i], lengths[i]));
        }

        var expectedStarts = BuildLineStarts(source);
        var startOnlyBuffer = new int[source.Length + 1];
        var startOnlyCount = (int)(buildLogicalLineStartsInto.Invoke(null, new object[] { source, startOnlyBuffer }) ?? -1);
        Assert.Equal(expectedStarts.Length, startOnlyCount);
        Assert.Equal(expectedStarts, startOnlyBuffer.Take(startOnlyCount).ToArray());

        for (var offset = -1; offset <= source.Length + 1; offset++)
        {
            var expectedLineIndex = LineIndexFromOffset(expectedStarts, source.Length, offset);
            var expectedColumn = ColumnFromOffset(expectedStarts, source.Length, offset);
            var actualLineIndex = (int)(getLineIndexFromOffset.Invoke(
                null,
                new object[] { startOnlyBuffer, startOnlyCount, source.Length, offset }) ?? -1);
            var actualColumn = (int)(getColumnFromOffset.Invoke(
                null,
                new object[] { startOnlyBuffer, startOnlyCount, source.Length, offset }) ?? -1);

            Assert.Equal(expectedLineIndex, actualLineIndex);
            Assert.Equal(expectedColumn, actualColumn);
        }

        for (var line = 1; line <= expected.Length; line++)
        {
            var lineLength = expected[line - 1].Length;
            for (var column = 0; column <= lineLength; column++)
            {
                var actualOffset = (int)(getOffsetFromLineColumn.Invoke(
                    null,
                    new object[] { starts, lengths, count, source.Length, line, column }) ?? -2);
                Assert.Equal(expectedStarts[line - 1] + column, actualOffset);
            }

            var invalidColumnOffset = (int)(getOffsetFromLineColumn.Invoke(
                null,
                new object[] { starts, lengths, count, source.Length, line, lineLength + 1 }) ?? -2);
            Assert.Equal(-1, invalidColumnOffset);
        }

        var invalidLineOffset = (int)(getOffsetFromLineColumn.Invoke(
            null,
            new object[] { starts, lengths, count, source.Length, expected.Length + 1, 0 }) ?? -2);
        Assert.Equal(-1, invalidLineOffset);

        var offsets = Enumerable.Range(-1, source.Length + 3).ToArray();
        var queryLines = new List<int>();
        var queryColumns = new List<int>();
        for (var line = 1; line <= expected.Length; line++)
        {
            var lineLength = expected[line - 1].Length;
            for (var column = 0; column <= lineLength + 1; column++)
            {
                queryLines.Add(line);
                queryColumns.Add(column);
            }
        }

        queryLines.Add(0);
        queryColumns.Add(0);
        queryLines.Add(expected.Length + 1);
        queryColumns.Add(0);

        var expectedChecksum = expected.Length;
        foreach (var offset in offsets)
        {
            var expectedLineIndex = LineIndexFromOffset(expectedStarts, source.Length, offset);
            var expectedColumn = ColumnFromOffset(expectedStarts, source.Length, offset);
            expectedChecksum += expectedLineIndex * 31 + expectedColumn;
        }

        for (var i = 0; i < queryLines.Count; i++)
        {
            var line = queryLines[i];
            var column = queryColumns[i];
            var expectedOffset = -1;
            if (line >= 1 && line <= expected.Length && column >= 0 && column <= expected[line - 1].Length)
            {
                expectedOffset = expectedStarts[line - 1] + column;
            }

            expectedChecksum += expectedOffset * 17;
        }

        var cachedStarts = new int[source.Length + 1];
        var cachedLengths = new int[source.Length + 1];
        var offsetLineIndices = new int[source.Length + 1];
        var cachedChecksum = (int)(lineMapCachedChecksumInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedStarts,
                cachedLengths,
                offsetLineIndices,
                offsets,
                queryLines.ToArray(),
                queryColumns.ToArray()
            }) ?? -1);

        Assert.Equal(expectedChecksum, cachedChecksum);

        var queryOffsetLineIndices = BuildOffsetLineIndices(expectedStarts, expected.Length, source.Length);
        var queryChecksum = (int)(lineMapCachedQueryChecksumInto.Invoke(
            null,
            new object[]
            {
                expectedStarts,
                lengths,
                expected.Length,
                source.Length,
                queryOffsetLineIndices,
                offsets,
                queryLines.ToArray(),
                queryColumns.ToArray()
            }) ?? -1);

        Assert.Equal(expectedChecksum, queryChecksum);

        var trustedOffsets = Enumerable.Range(0, source.Length + 1).ToArray();
        var trustedQueryLines = new List<int>();
        var trustedQueryColumns = new List<int>();
        for (var line = 1; line <= expected.Length; line++)
        {
            var lineLength = expected[line - 1].Length;
            for (var column = 0; column <= lineLength; column++)
            {
                trustedQueryLines.Add(line);
                trustedQueryColumns.Add(column);
            }
        }

        var trustedQueryLineArray = trustedQueryLines.ToArray();
        var trustedQueryColumnArray = trustedQueryColumns.ToArray();
        var expectedTrustedChecksum = expected.Length;
        foreach (var offset in trustedOffsets)
        {
            var expectedLineIndex = LineIndexFromOffset(expectedStarts, source.Length, offset);
            var expectedColumn = ColumnFromOffset(expectedStarts, source.Length, offset);
            expectedTrustedChecksum += expectedLineIndex * 31 + expectedColumn;
        }

        for (var i = 0; i < trustedQueryLineArray.Length; i++)
        {
            expectedTrustedChecksum += (expectedStarts[trustedQueryLineArray[i] - 1] + trustedQueryColumnArray[i]) * 17;
        }

        var trustedChecksum = (int)(lineMapTrustedCachedQueryChecksumInto.Invoke(
            null,
            new object[]
            {
                expectedStarts,
                expected.Length,
                queryOffsetLineIndices,
                trustedOffsets,
                trustedQueryLineArray,
                trustedQueryColumnArray
            }) ?? -1);

        Assert.Equal(expectedTrustedChecksum, trustedChecksum);
    }

    private static void AssertIdentifierSpansLikeProduction(
        string source,
        MethodInfo codeIntelligenceIdentifierSpanChecksumInto,
        MethodInfo codeIntelligenceIdentifierSpansInto)
    {
        var lines = source.Split('\n');
        var queries = new List<(int Line, int Column)>
        {
            (0, 0),
            (lines.Length + 1, 1)
        };

        for (var lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            var line = lineIndex + 1;
            var lineText = lines[lineIndex];
            queries.Add((line, 0));
            queries.Add((line, 1));
            queries.Add((line, lineText.Length));
            queries.Add((line, lineText.Length + 8));

            var identifier = FindFirstIdentifierSpan(lineText);
            queries.Add((line, identifier.StartColumn));
            queries.Add((line, Math.Max(1, identifier.StartColumn - 1)));
            queries.Add((line, Math.Min(Math.Max(1, lineText.Length), identifier.StartColumn + identifier.Length)));
            queries.Add((line, Math.Min(Math.Max(1, lineText.Length), identifier.StartColumn + identifier.Length + 1)));
        }

        var queryLines = queries.Select(static query => query.Line).ToArray();
        var queryColumns = queries.Select(static query => query.Column).ToArray();
        var expectedStarts = new int[queries.Count];
        var expectedLengths = new int[queries.Count];
        var expectedChecksum = 0;
        var expectedCount = 0;
        for (var i = 0; i < queries.Count; i++)
        {
            var span = ExtractIdentifierSpanAtPosition(source, queryLines[i], queryColumns[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
            if (start >= 0)
                expectedCount++;
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualStarts = new int[queries.Count];
        var actualLengths = new int[queries.Count];
        var actualChecksum = (int)(codeIntelligenceIdentifierSpanChecksumInto.Invoke(
            null,
            new object[] { source, lineStarts, lineLengths, queryLines, queryColumns, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queries.Count];
        var productionLengths = new int[queries.Count];
        var actualCount = (int)(codeIntelligenceIdentifierSpansInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                queryColumns,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);
    }

    private static void AssertEditorIdentifierSpansLikeProduction(
        string source,
        MethodInfo codeIntelligenceEditorIdentifierSpanChecksumInto,
        MethodInfo codeIntelligenceEditorIdentifierSpansInto)
    {
        var lines = source.Split('\n');
        var queries = new List<(int Line, int Column)>
        {
            (0, 0),
            (lines.Length + 1, 1)
        };

        for (var lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            var line = lineIndex + 1;
            var lineText = lines[lineIndex];
            queries.Add((line, 0));
            queries.Add((line, 1));
            queries.Add((line, lineText.Length));
            queries.Add((line, lineText.Length + 8));

            var identifier = FindFirstIdentifierSpan(lineText);
            queries.Add((line, identifier.StartColumn));
            queries.Add((line, identifier.StartColumn + Math.Max(0, identifier.Length - 1)));
            queries.Add((line, identifier.StartColumn + identifier.Length));
        }

        var queryLines = queries.Select(static query => query.Line).ToArray();
        var queryColumns = queries.Select(static query => query.Column).ToArray();
        var expectedStarts = new int[queries.Count];
        var expectedLengths = new int[queries.Count];
        var expectedChecksum = 0;
        var expectedCount = 0;
        for (var i = 0; i < queries.Count; i++)
        {
            var span = ExtractEditorIdentifierSpanAtPosition(source, queryLines[i], queryColumns[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
            if (start >= 0)
                expectedCount++;
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualStarts = new int[queries.Count];
        var actualLengths = new int[queries.Count];
        var actualChecksum = (int)(codeIntelligenceEditorIdentifierSpanChecksumInto.Invoke(
            null,
            new object[] { source, lineStarts, lineLengths, queryLines, queryColumns, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queries.Count];
        var productionLengths = new int[queries.Count];
        var actualCount = (int)(codeIntelligenceEditorIdentifierSpansInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                queryColumns,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);
    }

    private static void AssertDeclarationNameMatchesLikeProduction(
        string source,
        MethodInfo codeIntelligenceDeclarationNameMatchChecksumInto,
        MethodInfo codeIntelligenceDeclarationNameMatchesFromLinesInto)
    {
        var lines = source.Split('\n');
        var firstValueColumn = FindNameStartColumn(lines[1], "value", 1);
        var secondValueColumn = FindNameStartColumn(lines[1], "value", firstValueColumn + "value".Length);
        var prefixValueColumn = FindNameStartColumn(lines[2], "value", 1);
        var cafeColumn = FindNameStartColumn(lines[3], "café", 1);

        var queries = new List<(int Line, int DeclarationColumn, string Name, int SelectedStart, int SelectedEnd)>
        {
            (0, 1, "value", 1, 5),
            (lines.Length + 1, 1, "value", 1, 5),
            (2, firstValueColumn, "value", firstValueColumn, firstValueColumn + "value".Length - 1),
            (2, firstValueColumn, "value", secondValueColumn, secondValueColumn + "value".Length - 1),
            (2, secondValueColumn, "value", secondValueColumn, secondValueColumn + "value".Length - 1),
            (3, 1, "value", prefixValueColumn, prefixValueColumn + "value".Length - 1),
            (3, prefixValueColumn + "value".Length, "value", prefixValueColumn, prefixValueColumn + "value".Length - 1),
            (4, cafeColumn, "café", cafeColumn, cafeColumn + "café".Length - 1),
            (4, cafeColumn, "missing", cafeColumn, cafeColumn + "café".Length - 1)
        };

        var queryLines = queries.Select(static query => query.Line).ToArray();
        var declarationColumns = queries.Select(static query => query.DeclarationColumn).ToArray();
        var declarationNames = queries.Select(static query => query.Name).ToArray();
        var selectedStartColumns = queries.Select(static query => query.SelectedStart).ToArray();
        var selectedEndColumns = queries.Select(static query => query.SelectedEnd).ToArray();
        var expectedMatches = new int[queries.Count];
        var expectedChecksum = 0;
        var expectedCount = 0;

        for (var i = 0; i < queries.Count; i++)
        {
            var query = queries[i];
            var matches = SelectedSpanMatchesDeclarationName(
                source,
                query.Line,
                query.DeclarationColumn,
                query.Name,
                query.SelectedStart,
                query.SelectedEnd);
            expectedMatches[i] = matches ? 1 : 0;
            expectedChecksum += expectedMatches[i] * (i + 1);
            if (matches)
            {
                expectedCount++;
            }
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualMatches = new int[queries.Count];
        var actualChecksum = (int)(codeIntelligenceDeclarationNameMatchChecksumInto.Invoke(
            null,
            new object[]
            {
                source,
                lineStarts,
                lineLengths,
                queryLines,
                declarationColumns,
                declarationNames,
                selectedStartColumns,
                selectedEndColumns,
                actualMatches
            }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedMatches, actualMatches);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var lineCount = BuildLineRanges(source, cachedLineStarts, cachedLineLengths);
        var cachedMatches = new int[queries.Count];
        var cachedCount = (int)(codeIntelligenceDeclarationNameMatchesFromLinesInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedLineStarts,
                cachedLineLengths,
                lineCount,
                queryLines,
                declarationColumns,
                declarationNames,
                selectedStartColumns,
                selectedEndColumns,
                cachedMatches
            }) ?? -1);

        Assert.Equal(expectedCount, cachedCount);
        Assert.Equal(expectedMatches, cachedMatches);
    }

    private static void AssertIdentifierNameColumnsLikeProduction(
        string source,
        MethodInfo codeIntelligenceIdentifierNameColumnChecksumInto,
        MethodInfo codeIntelligenceIdentifierNameColumnsInto,
        MethodInfo buildCodeIntelligenceLineRangesInto,
        MethodInfo codeIntelligenceIdentifierNameColumnsFromLinesInto)
    {
        var lines = source.Split('\n');
        var prefixLineText = lines[1].TrimEnd('\r');
        var cafeLineText = lines[2].TrimEnd('\r');
        var spacedLineText = lines[3].TrimEnd('\r');
        var prefixValueColumn = FindWholeIdentifierColumn(prefixLineText, "value", 1);
        var prefixIdentifierColumn = FindWholeIdentifierColumn(prefixLineText, "prefixvalue", 1);
        var cafeColumn = FindWholeIdentifierColumn(cafeLineText, "café", 1);
        var secondCafeColumn = FindWholeIdentifierColumn(cafeLineText, "café", cafeColumn + "café".Length);
        var cafeValueColumn = FindWholeIdentifierColumn(cafeLineText, "value", 1);
        var spacedColumn = FindWholeIdentifierColumn(spacedLineText, "spaced", 1);

        var queries = new List<(int Line, string Name, int FallbackColumn)>
        {
            (0, "value", 99),
            (lines.Length + 1, "value", 7),
            (2, "value", 1),
            (2, "prefixvalue", prefixIdentifierColumn),
            (2, "value", prefixValueColumn),
            (3, "café", secondCafeColumn),
            (3, "value", 1),
            (4, "spaced", spacedColumn + 20),
            (4, "missing", 6)
        };

        var queryLines = queries.Select(static query => query.Line).ToArray();
        var names = queries.Select(static query => query.Name).ToArray();
        var fallbackColumns = queries.Select(static query => query.FallbackColumn).ToArray();
        var expectedColumns = new int[queries.Count];
        var expectedCount = 0;

        for (var i = 0; i < queries.Count; i++)
        {
            var query = queries[i];
            if (TryFindIdentifierNameColumn(source, query.Name, query.Line, query.FallbackColumn, out var column))
            {
                expectedCount++;
            }

            expectedColumns[i] = column;
        }

        Assert.Equal(prefixValueColumn, expectedColumns[2]);
        Assert.Equal(secondCafeColumn, expectedColumns[5]);
        Assert.Equal(cafeValueColumn, expectedColumns[6]);
        Assert.Equal(fallbackColumns[8], expectedColumns[8]);

        var expectedChecksum = expectedCount;
        for (var i = 0; i < queries.Count; i++)
        {
            expectedChecksum += expectedColumns[i] * 31 + fallbackColumns[i] * 17;
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualColumns = new int[queries.Count];
        var actualChecksum = (int)(codeIntelligenceIdentifierNameColumnChecksumInto.Invoke(
            null,
            new object[] { source, lineStarts, lineLengths, queryLines, names, fallbackColumns, actualColumns }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedColumns, actualColumns);

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionColumns = new int[queries.Count];
        var actualCount = (int)(codeIntelligenceIdentifierNameColumnsInto.Invoke(
            null,
            new object[] { source, productionLineStarts, productionLineLengths, queryLines, names, fallbackColumns, productionColumns }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedColumns, productionColumns);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var lineCount = (int)(buildCodeIntelligenceLineRangesInto.Invoke(
            null,
            new object[] { source, cachedLineStarts, cachedLineLengths }) ?? -1);
        var cachedColumns = new int[queries.Count];
        var cachedCount = (int)(codeIntelligenceIdentifierNameColumnsFromLinesInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedLineStarts,
                cachedLineLengths,
                lineCount,
                queryLines,
                names,
                fallbackColumns,
                cachedColumns
            }) ?? -1);

        Assert.Equal(expectedCount, cachedCount);
        Assert.Equal(expectedColumns, cachedColumns);
    }

    private static void AssertMemberReceiversLikeProduction(
        string source,
        MethodInfo codeIntelligenceMemberReceiverChecksumInto,
        MethodInfo codeIntelligenceMemberReceiversInto,
        MethodInfo codeIntelligenceMemberReceiverCachedChecksumInto,
        MethodInfo codeIntelligenceMemberReceiversCachedInto)
    {
        var lines = source.Split('\n');
        var queries = new List<(int Line, int MemberStartColumn)>
        {
            (0, 0),
            (lines.Length + 1, 1)
        };

        for (var lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            var line = lineIndex + 1;
            var lineText = lines[lineIndex];
            queries.Add((line, 0));
            queries.Add((line, 1));
            queries.Add((line, lineText.Length + 8));

            for (var i = 0; i < lineText.Length - 1; i++)
            {
                if (lineText[i] == '.' && IsIdentifierChar(lineText[i + 1]))
                {
                    queries.Add((line, i + 2));
                }
            }
        }

        var queryLines = queries.Select(static query => query.Line).ToArray();
        var memberStartColumns = queries.Select(static query => query.MemberStartColumn).ToArray();
        var expectedStarts = new int[queries.Count];
        var expectedLengths = new int[queries.Count];
        var expectedChecksum = 0;
        var expectedCount = 0;
        for (var i = 0; i < queries.Count; i++)
        {
            var span = ExtractMemberReceiverSpan(source, queryLines[i], memberStartColumns[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
            if (start >= 0)
                expectedCount++;
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualStarts = new int[queries.Count];
        var actualLengths = new int[queries.Count];
        var actualChecksum = (int)(codeIntelligenceMemberReceiverChecksumInto.Invoke(
            null,
            new object[] { source, lineStarts, lineLengths, queryLines, memberStartColumns, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queries.Count];
        var productionLengths = new int[queries.Count];
        var actualCount = (int)(codeIntelligenceMemberReceiversInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                memberStartColumns,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var receiverStartsBySeparator = new int[source.Length + 1];
        var receiverLengthsBySeparator = new int[source.Length + 1];
        var cachedStarts = new int[queries.Count];
        var cachedLengths = new int[queries.Count];
        var cachedChecksum = (int)(codeIntelligenceMemberReceiverCachedChecksumInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedLineStarts,
                cachedLineLengths,
                receiverStartsBySeparator,
                receiverLengthsBySeparator,
                queryLines,
                memberStartColumns,
                cachedStarts,
                cachedLengths
            }) ?? -1);

        Assert.Equal(expectedChecksum, cachedChecksum);
        Assert.Equal(expectedStarts, cachedStarts);
        Assert.Equal(expectedLengths, cachedLengths);

        var productionCachedLineStarts = new int[source.Length + 1];
        var productionCachedLineLengths = new int[source.Length + 1];
        var productionReceiverStartsBySeparator = new int[source.Length + 1];
        var productionReceiverLengthsBySeparator = new int[source.Length + 1];
        var productionCachedStarts = new int[queries.Count];
        var productionCachedLengths = new int[queries.Count];
        var actualCachedCount = (int)(codeIntelligenceMemberReceiversCachedInto.Invoke(
            null,
            new object[]
            {
                source,
                productionCachedLineStarts,
                productionCachedLineLengths,
                productionReceiverStartsBySeparator,
                productionReceiverLengthsBySeparator,
                queryLines,
                memberStartColumns,
                productionCachedStarts,
                productionCachedLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCachedCount);
        Assert.Equal(expectedStarts, productionCachedStarts);
        Assert.Equal(expectedLengths, productionCachedLengths);
    }

    private static void AssertSourceContextsLikeProduction(
        string source,
        MethodInfo codeIntelligenceSourceContextChecksumInto,
        MethodInfo codeIntelligenceSourceContextsInto)
    {
        var lines = source.Split('\n');
        var queries = new List<int> { 0, lines.Length + 1 };
        for (var line = 1; line <= lines.Length; line++)
        {
            queries.Add(line);
        }

        var queryLines = queries.ToArray();
        var expectedStarts = new int[queryLines.Length];
        var expectedLengths = new int[queryLines.Length];
        var expectedChecksum = 0;
        var expectedCount = 0;
        var lineStarts = BuildLfLineStarts(source);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var start = -1;
            var length = 0;

            if (line >= 1 && line <= lines.Length)
            {
                var lineText = lines[line - 1];
                var trimStart = 0;
                var trimEnd = lineText.Length - 1;
                while (trimStart <= trimEnd && char.IsWhiteSpace(lineText[trimStart]))
                {
                    trimStart++;
                }

                while (trimEnd >= trimStart && char.IsWhiteSpace(lineText[trimEnd]))
                {
                    trimEnd--;
                }

                start = lineStarts[line - 1] + trimStart;
                if (trimEnd >= trimStart)
                {
                    length = trimEnd - trimStart + 1;
                }

                expectedCount++;
            }

            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
        }

        var rangeStarts = new int[source.Length + 1];
        var rangeLengths = new int[source.Length + 1];
        var actualStarts = new int[queryLines.Length];
        var actualLengths = new int[queryLines.Length];
        var actualChecksum = (int)(codeIntelligenceSourceContextChecksumInto.Invoke(
            null,
            new object[] { source, rangeStarts, rangeLengths, queryLines, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var expectedContext = line >= 1 && line <= lines.Length
                ? lines[line - 1].Trim()
                : null;
            var actualContext = actualStarts[i] >= 0
                ? source.Substring(actualStarts[i], actualLengths[i])
                : null;
            Assert.Equal(expectedContext, actualContext);
        }

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queryLines.Length];
        var productionLengths = new int[queryLines.Length];
        var actualCount = (int)(codeIntelligenceSourceContextsInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);
    }

    private static void AssertSourceLinesLikeProduction(
        string source,
        MethodInfo codeIntelligenceSourceLineChecksumInto,
        MethodInfo codeIntelligenceSourceLinesInto,
        MethodInfo codeIntelligenceSourceLinesFromLinesInto)
    {
        var lines = source.Split('\n');
        var queries = new List<int> { 0, lines.Length + 1 };
        for (var line = 1; line <= lines.Length; line++)
        {
            queries.Add(line);
        }

        var queryLines = queries.ToArray();
        var expectedStarts = new int[queryLines.Length];
        var expectedLengths = new int[queryLines.Length];
        var expectedChecksum = 0;
        var expectedCount = 0;
        var lineStarts = BuildLfLineStarts(source);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var start = -1;
            var length = 0;

            if (line >= 1 && line <= lines.Length)
            {
                start = lineStarts[line - 1];
                length = lines[line - 1].Length;
                expectedCount++;
            }

            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
        }

        var rangeStarts = new int[source.Length + 1];
        var rangeLengths = new int[source.Length + 1];
        var actualStarts = new int[queryLines.Length];
        var actualLengths = new int[queryLines.Length];
        var actualChecksum = (int)(codeIntelligenceSourceLineChecksumInto.Invoke(
            null,
            new object[] { source, rangeStarts, rangeLengths, queryLines, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var expectedLine = line >= 1 && line <= lines.Length
                ? lines[line - 1]
                : null;
            var actualLine = actualStarts[i] >= 0
                ? source.Substring(actualStarts[i], actualLengths[i])
                : null;
            Assert.Equal(expectedLine, actualLine);
        }

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queryLines.Length];
        var productionLengths = new int[queryLines.Length];
        var actualCount = (int)(codeIntelligenceSourceLinesInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var cachedStarts = new int[queryLines.Length];
        var cachedLengths = new int[queryLines.Length];
        var lineCount = BuildLineRanges(source, cachedLineStarts, cachedLineLengths);
        var cachedCount = (int)(codeIntelligenceSourceLinesFromLinesInto.Invoke(
            null,
            new object[]
            {
                cachedLineStarts,
                cachedLineLengths,
                lineCount,
                queryLines,
                cachedStarts,
                cachedLengths
            }) ?? -1);

        Assert.Equal(expectedCount, cachedCount);
        Assert.Equal(expectedStarts, cachedStarts);
        Assert.Equal(expectedLengths, cachedLengths);
    }

    private static void AssertPathMatchingLikeProduction(
        MethodInfo codeIntelligencePathMatches,
        MethodInfo codeIntelligencePathMatchChecksumInto)
    {
        var fullPaths = new[]
        {
            "/repo/src/Program.nl",
            "/repo/src/features/Handler.nl",
            "/repo/src/OldProgram.nl",
            @"C:\repo\src\Generated\File.nl",
            "/repo/src/",
            "",
            "/repo/src/cafe/résumé.nl",
            "/repo/src/nested/File.nl"
        };
        var queryPaths = new[]
        {
            @"\REPO\SRC\program.NL",
            @"features\handler.nl",
            "Program.nl",
            "/src/generated/file.nl",
            "",
            "",
            "cafe/RÉSUMÉ.nl",
            "nested/Other.nl"
        };

        var expectedFlags = new int[fullPaths.Length];
        var expectedChecksum = expectedFlags.Length;
        for (var i = 0; i < fullPaths.Length; i++)
        {
            expectedFlags[i] = MatchesFilePathLikeProduction(fullPaths[i], queryPaths[i]) ? 1 : 0;
            expectedChecksum += expectedFlags[i] * (i + 1) * 31;

            var actualFlag = (int)(codeIntelligencePathMatches.Invoke(
                null,
                new object[] { fullPaths[i], queryPaths[i] }) ?? -1);
            Assert.Equal(expectedFlags[i], actualFlag);
        }

        var resultFlags = new int[fullPaths.Length];
        var actualChecksum = (int)(codeIntelligencePathMatchChecksumInto.Invoke(
            null,
            new object[] { fullPaths, queryPaths, resultFlags }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedFlags, resultFlags);
    }

    private static bool MatchesFilePathLikeProduction(string fullPath, string queryPath)
    {
        var normalizedFull = fullPath.Replace('\\', '/');
        var normalizedQuery = queryPath.Replace('\\', '/');

        if (normalizedFull.Equals(normalizedQuery, StringComparison.OrdinalIgnoreCase))
            return true;

        if (!normalizedFull.EndsWith(normalizedQuery, StringComparison.OrdinalIgnoreCase))
            return false;

        var charBefore = normalizedFull[normalizedFull.Length - normalizedQuery.Length - 1];
        return charBefore == '/';
    }

    private static void AssertProjectSourceFilterLikeProduction(
        MethodInfo projectSourceFilterKeptIndicesInto,
        MethodInfo projectSourceFilterKeptChecksumInto)
    {
        var relativePaths = new[]
        {
            "Program.nl",
            "Core/Service.nl",
            "Core/Internal/Helper.nl",
            "Core/Service.tests.nl",
            "Core/Service.TESTS.NL",
            "Generated/Api.nl",
            "Generated/Nested/Api.nl",
            "temp/a/b/Work.nl",
            "tools/snapshots/Snap.nl",
            "vendor/pkg/Lib.nl",
            "scratch7.nl",
            "scratch42.nl",
            @"Features\Auth\Login.nl",
            @"Generated\Win.nl",
            "Models/Customer.nl",
            // Edge cases for glob-semantics parity with the production regex.
            "foo",          // "**/foo" must NOT match (".*?/" requires a slash); "foo" exact must
            "a/foo",        // "**/foo" matches here
            "deep/a/b/foo", // "**/foo" matches across multiple dirs
            "anything/x",   // "**" (greedy ".*") and "src/**" trailing-** cases
            "src/x/y",      // "src/**" matches
            "src",          // "src/**" must NOT match (requires "src/")
            "",             // empty path
            "x/y/z.nl",     // "***" consecutive-star pattern stress
        };

        var excludeSets = new[]
        {
            Array.Empty<string>(),
            new[] { "Generated/*.nl" },
            new[] { "temp/**/*.nl", "**/snapshots/*.nl", "vendor/**", "scratch?.nl" },
            new[] { "Generated/*.nl", "**/snapshots/*.nl", "vendor/**", "scratch?.nl", "temp/**/*.nl" },
            new[] { "**/foo" },       // lazy "**/" anchoring
            new[] { "src/**" },       // trailing "**"
            new[] { "foo" },          // exact-match literal
            new[] { "***" },          // consecutive stars
            new[] { "" },             // empty pattern (matches only empty path)
            new[] { "*" },            // single star, non-slash run
        };

        foreach (var excludePatterns in excludeSets)
        {
            foreach (var includeTests in new[] { false, true })
            {
                var expected = new List<int>(relativePaths.Length);
                for (var i = 0; i < relativePaths.Length; i++)
                {
                    if (!includeTests &&
                        relativePaths[i].EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    if (excludePatterns.Any(pattern => MatchesPatternLikeProduction(relativePaths[i], pattern)))
                    {
                        continue;
                    }

                    expected.Add(i);
                }

                var resultIndices = new int[relativePaths.Length];
                var actualCount = (int)(projectSourceFilterKeptIndicesInto.Invoke(
                    null,
                    new object[] { relativePaths, excludePatterns, includeTests ? 1 : 0, resultIndices }) ?? -1);

                Assert.Equal(expected.Count, actualCount);
                for (var i = 0; i < expected.Count; i++)
                {
                    Assert.Equal(expected[i], resultIndices[i]);
                }

                var expectedChecksum = expected.Count;
                for (var i = 0; i < expected.Count; i++)
                {
                    expectedChecksum += (expected[i] + 1) * (i + 1) * 31;
                }

                var checksumIndices = new int[relativePaths.Length];
                var actualChecksum = (int)(projectSourceFilterKeptChecksumInto.Invoke(
                    null,
                    new object[] { relativePaths, excludePatterns, includeTests ? 1 : 0, checksumIndices }) ?? -1);

                Assert.Equal(expectedChecksum, actualChecksum);
            }
        }
    }

    // Verbatim replica of ProjectConfig.MatchesPattern (the production exclude-glob regex).
    private static bool MatchesPatternLikeProduction(string path, string pattern)
    {
        path = path.Replace('\\', '/');
        pattern = pattern.Replace('\\', '/');

        var regexPattern = "^" + System.Text.RegularExpressions.Regex.Escape(pattern)
            .Replace("\\*\\*/", ".*?/")
            .Replace("\\*\\*", ".*")
            .Replace("\\*", "[^/]*")
            .Replace("\\?", ".")
            + "$";

        return System.Text.RegularExpressions.Regex.IsMatch(path, regexPattern);
    }

    private static void AssertCompletionPrefixesLikeProduction(
        string source,
        MethodInfo codeIntelligenceCompletionPrefixChecksumInto,
        MethodInfo codeIntelligenceCompletionPrefixesInto,
        MethodInfo codeIntelligenceCompletionPrefixesFromLinesInto)
    {
        var lines = source.Split('\n');
        var queryLinesList = new List<int> { 0, lines.Length + 1 };
        var queryColumnsList = new List<int> { 1, 1 };

        for (var line = 1; line <= lines.Length; line++)
        {
            var lineLength = lines[line - 1].Length;
            queryLinesList.Add(line);
            queryColumnsList.Add(0);
            queryLinesList.Add(line);
            queryColumnsList.Add(1);
            queryLinesList.Add(line);
            queryColumnsList.Add(lineLength);
            queryLinesList.Add(line);
            queryColumnsList.Add(lineLength + 1);
        }

        var queryLines = queryLinesList.ToArray();
        var queryColumns = queryColumnsList.ToArray();
        var expectedStarts = new int[queryLines.Length];
        var expectedLengths = new int[queryLines.Length];
        var expectedChecksum = 0;
        var expectedCount = 0;
        var lineStarts = BuildLfLineStarts(source);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var column = queryColumns[i];
            var start = -1;
            var length = 0;

            if (line >= 1 && line <= lines.Length)
            {
                start = lineStarts[line - 1];
                length = lines[line - 1].Length;
                if (column > 0 && column <= length)
                {
                    length = column;
                }

                expectedCount++;
            }

            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
        }

        var rangeStarts = new int[source.Length + 1];
        var rangeLengths = new int[source.Length + 1];
        var actualStarts = new int[queryLines.Length];
        var actualLengths = new int[queryLines.Length];
        var actualChecksum = (int)(codeIntelligenceCompletionPrefixChecksumInto.Invoke(
            null,
            new object[] { source, rangeStarts, rangeLengths, queryLines, queryColumns, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var column = queryColumns[i];
            var expectedPrefix = line >= 1 && line <= lines.Length
                ? ExtractCompletionPrefix(source, line, column)
                : null;
            var actualPrefix = actualStarts[i] >= 0
                ? source.Substring(actualStarts[i], actualLengths[i])
                : null;
            Assert.Equal(expectedPrefix, actualPrefix);
        }

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queryLines.Length];
        var productionLengths = new int[queryLines.Length];
        var actualCount = (int)(codeIntelligenceCompletionPrefixesInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                queryColumns,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var cachedStarts = new int[queryLines.Length];
        var cachedLengths = new int[queryLines.Length];
        var lineCount = BuildLineRanges(source, cachedLineStarts, cachedLineLengths);
        var cachedCount = (int)(codeIntelligenceCompletionPrefixesFromLinesInto.Invoke(
            null,
            new object[]
            {
                cachedLineStarts,
                cachedLineLengths,
                lineCount,
                queryLines,
                queryColumns,
                cachedStarts,
                cachedLengths
            }) ?? -1);

        Assert.Equal(expectedCount, cachedCount);
        Assert.Equal(expectedStarts, cachedStarts);
        Assert.Equal(expectedLengths, cachedLengths);
    }

    private static void AssertCompletionReceiversLikeProduction(
        MethodInfo codeIntelligenceCompletionReceiverChecksumInto,
        MethodInfo codeIntelligenceCompletionReceiversInto)
    {
        var isMemberAccessContext = typeof(CompletionEngine).GetMethod(
                "IsMemberAccessContext",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("CompletionEngine did not emit IsMemberAccessContext.");
        var extractReceiver = typeof(CompletionEngine).GetMethod(
                "ExtractReceiver",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("CompletionEngine did not emit ExtractReceiver.");

        var prefixes = new[]
        {
            "people.",
            "people.Add",
            "factory.Create(name).",
            "factory.Create(name, other.Value).Co",
            "System.Console.",
            "message.ToUpper().",
            "message.ToUpper().Len",
            "    \"abc\".",
            "    $\"hello {name}\".",
            "    \"a.b\".Len",
            "    \"\"\"hello\"\"\".",
            "    \"unterminated.",
            "    true.",
            "    false.ToString().",
            "    42.",
            "    1.5.",
            "    0xCAFE.",
            "    'x'.",
            "    return people",
            "    name",
            "    call(value.withDot).",
            "    namespace.Type.Member",
            "    Console.WriteLine(factory.Create(name, other.Value)).",
            "    items.Where(item => item.Enabled).",
            "/// <summary>A representative lexer service input.</summary>.0xCAFE.",
            "    résumé.Count"
        };

        var expectedContexts = new int[prefixes.Length];
        var expectedReceivers = Enumerable.Repeat(string.Empty, prefixes.Length).ToArray();
        var expectedChecksum = prefixes.Length;

        for (var i = 0; i < prefixes.Length; i++)
        {
            var isMemberAccess = (bool)(isMemberAccessContext.Invoke(null, new object[] { prefixes[i] }) ?? false);
            var receiver = isMemberAccess
                ? (string?)extractReceiver.Invoke(null, new object[] { prefixes[i] }) ?? string.Empty
                : string.Empty;

            expectedContexts[i] = isMemberAccess ? 1 : 0;
            expectedReceivers[i] = receiver;
            expectedChecksum += expectedContexts[i] * 31 + receiver.Length * 17;
        }

        var checksumContexts = new int[prefixes.Length];
        var checksumReceivers = Enumerable.Repeat(string.Empty, prefixes.Length).ToArray();
        var actualChecksum = (int)(codeIntelligenceCompletionReceiverChecksumInto.Invoke(
            null,
            new object[] { prefixes, checksumContexts, checksumReceivers }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedContexts, checksumContexts);
        Assert.Equal(expectedReceivers, checksumReceivers);

        var actualContexts = new int[prefixes.Length];
        var actualReceivers = Enumerable.Repeat(string.Empty, prefixes.Length).ToArray();
        var actualCount = (int)(codeIntelligenceCompletionReceiversInto.Invoke(
            null,
            new object[] { prefixes, actualContexts, actualReceivers }) ?? -1);

        Assert.Equal(prefixes.Length, actualCount);
        Assert.Equal(expectedContexts, actualContexts);
        Assert.Equal(expectedReceivers, actualReceivers);
    }

    private static void AssertCompletionItemGroupingLikeProduction(
        MethodInfo completionItemKindGroupsInto,
        MethodInfo completionItemKindGroupChecksumInto)
    {
        var kindIds = new[] { 2, 1, 2, 3, 1 };
        var kindCounts = new int[4];
        var kindOffsets = new int[4];
        var resultKindIds = new int[kindIds.Length];
        var resultStarts = new int[kindIds.Length];
        var resultCounts = new int[kindIds.Length];
        var resultIndices = new int[kindIds.Length];

        var groupCount = (int)(completionItemKindGroupsInto.Invoke(
            null,
            new object[] { kindIds, kindCounts, kindOffsets, resultKindIds, resultStarts, resultCounts, resultIndices }) ?? -1);

        Assert.Equal(3, groupCount);
        Assert.Equal(new[] { 2, 1, 3 }, resultKindIds.Take(groupCount));
        Assert.Equal(new[] { 0, 2, 4 }, resultStarts.Take(groupCount));
        Assert.Equal(new[] { 2, 2, 1 }, resultCounts.Take(groupCount));
        Assert.Equal(new[] { 0, 2, 1, 4, 3 }, resultIndices);

        var checksumKindCounts = new int[4];
        var checksumKindOffsets = new int[4];
        var checksumResultKindIds = new int[kindIds.Length];
        var checksumResultStarts = new int[kindIds.Length];
        var checksumResultCounts = new int[kindIds.Length];
        var checksumResultIndices = new int[kindIds.Length];
        var expectedChecksum = CompletionItemKindGroupingChecksum(
            resultKindIds,
            resultStarts,
            resultCounts,
            resultIndices,
            groupCount);
        var actualChecksum = (int)(completionItemKindGroupChecksumInto.Invoke(
            null,
            new object[]
            {
                kindIds,
                checksumKindCounts,
                checksumKindOffsets,
                checksumResultKindIds,
                checksumResultStarts,
                checksumResultCounts,
                checksumResultIndices
            }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(resultKindIds, checksumResultKindIds);
        Assert.Equal(resultStarts, checksumResultStarts);
        Assert.Equal(resultCounts, checksumResultCounts);
        Assert.Equal(resultIndices, checksumResultIndices);
    }

    private static int CompletionItemKindGroupingChecksum(
        int[] resultKindIds,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultIndices,
        int groupCount)
    {
        var checksum = groupCount;
        for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
        {
            var start = resultStarts[groupIndex];
            var count = resultCounts[groupIndex];
            checksum += resultKindIds[groupIndex] * 97 + start * 31 + count * 17;

            for (var itemIndex = 0; itemIndex < count; itemIndex++)
            {
                var sourceIndex = resultIndices[start + itemIndex];
                checksum += (sourceIndex + 1) * 13 + (itemIndex + 1) * 7;
            }
        }

        return checksum;
    }

    private static void AssertCompletionMethodGroupingLikeProduction(
        MethodInfo completionMethodOverloadGroupsInto,
        MethodInfo completionMethodOverloadGroupChecksumInto)
    {
        var nameIds = new[] { 2, 1, 2, 3, 1, 0, 2 };
        var includeFlags = new[] { 1, 1, 1, 1, 1, 0, 1 };
        var nameCounts = new int[4];
        var resultNameIds = new int[nameIds.Length];
        var resultFirstIndices = new int[nameIds.Length];
        var resultCounts = new int[nameIds.Length];

        var groupCount = (int)(completionMethodOverloadGroupsInto.Invoke(
            null,
            new object[] { nameIds, includeFlags, nameCounts, resultNameIds, resultFirstIndices, resultCounts }) ?? -1);

        Assert.Equal(3, groupCount);
        Assert.Equal(new[] { 2, 1, 3 }, resultNameIds.Take(groupCount));
        Assert.Equal(new[] { 0, 1, 3 }, resultFirstIndices.Take(groupCount));
        Assert.Equal(new[] { 3, 2, 1 }, resultCounts.Take(groupCount));

        var checksumNameCounts = new int[4];
        var checksumResultNameIds = new int[nameIds.Length];
        var checksumResultFirstIndices = new int[nameIds.Length];
        var checksumResultCounts = new int[nameIds.Length];
        var expectedChecksum = CompletionMethodOverloadGroupingChecksum(
            resultNameIds,
            resultFirstIndices,
            resultCounts,
            groupCount);
        var actualChecksum = (int)(completionMethodOverloadGroupChecksumInto.Invoke(
            null,
            new object[]
            {
                nameIds,
                includeFlags,
                checksumNameCounts,
                checksumResultNameIds,
                checksumResultFirstIndices,
                checksumResultCounts
            }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(resultNameIds, checksumResultNameIds);
        Assert.Equal(resultFirstIndices, checksumResultFirstIndices);
        Assert.Equal(resultCounts, checksumResultCounts);
    }

    private static int CompletionMethodOverloadGroupingChecksum(
        int[] resultNameIds,
        int[] resultFirstIndices,
        int[] resultCounts,
        int groupCount)
    {
        var checksum = groupCount;
        for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
        {
            checksum += resultNameIds[groupIndex] * 97
                + resultFirstIndices[groupIndex] * 31
                + resultCounts[groupIndex] * 17
                + (groupIndex + 1) * 13;
        }

        return checksum;
    }

    private static void AssertCliQueryPositionsLikeProduction(
        MethodInfo cliTryParsePositionInto,
        MethodInfo cliQueryPositionsInto,
        MethodInfo cliQueryPositionChecksumInto)
    {
        var positions = new[]
        {
            "1:1",
            "42:17",
            " 42 : 17 ",
            "+64:+10",
            "-1:5",
            "2147483647:2147483647",
            "-2147483648:-2147483648",
            "0:0",
            "12:",
            ":34",
            "12:abc",
            "abc:12",
            "12:34:56",
            "2147483648:1",
            "1:-2147483649",
            "1_000:2",
            "7 :\t8"
        };
        var expectedLines = new int[positions.Length];
        var expectedColumns = new int[positions.Length];
        var expectedChecksum = positions.Length;

        for (var i = 0; i < positions.Length; i++)
        {
            var parsed = TryParseCliPositionWithSplit(positions[i], out var line, out var column);
            expectedLines[i] = line;
            expectedColumns[i] = column;
            expectedChecksum += (parsed ? 1 : 0) * 97 + line * 31 + column * 17;

            var singleResult = new int[2];
            var actualParsed = (int)(cliTryParsePositionInto.Invoke(
                null,
                new object[] { positions[i], singleResult }) ?? -1);
            Assert.Equal(parsed ? 1 : 0, actualParsed);
            Assert.Equal(line, singleResult[0]);
            Assert.Equal(column, singleResult[1]);
        }

        var actualLines = new int[positions.Length];
        var actualColumns = new int[positions.Length];
        var actualCount = (int)(cliQueryPositionsInto.Invoke(
            null,
            new object[] { positions, actualLines, actualColumns }) ?? -1);

        Assert.Equal(positions.Length, actualCount);
        Assert.Equal(expectedLines, actualLines);
        Assert.Equal(expectedColumns, actualColumns);

        var checksumLines = new int[positions.Length];
        var checksumColumns = new int[positions.Length];
        var actualChecksum = (int)(cliQueryPositionChecksumInto.Invoke(
            null,
            new object[] { positions, checksumLines, checksumColumns }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedLines, checksumLines);
        Assert.Equal(expectedColumns, checksumColumns);
    }

    private static bool TryParseCliPositionWithSplit(string position, out int line, out int column)
    {
        line = 0;
        column = 0;
        var parts = position.Split(':');
        if (parts.Length != 2)
            return false;

        return int.TryParse(parts[0], out line) && int.TryParse(parts[1], out column);
    }

    private static void AssertCliBuildOperandsLikeProduction(
        MethodInfo cliBuildOperandIndicesInto,
        MethodInfo cliBuildOperandSummaryInto,
        MethodInfo cliBuildFirstOperandIndexInto)
    {
        var cases = new[]
        {
            new[]
            {
                "--release",
                "--verbose",
                "--timings",
                "--perf-report",
                "--aot",
                "--output",
                "dist",
                "-o",
                "bin/out",
                "--backend",
                "il",
                "--project",
                "samples/demo",
                "Program.nl"
            },
            new[] { "--output", "--release", "Program.nl" },
            new[] { "--output", "--backend", "il", "Program.nl" },
            new[] { "--project" },
            new[] { "--backend", "il", "--project", "samples/demo" },
            new[] { "Program.nl", "--release", "--backend", "il", "Extra.nl" },
            Array.Empty<string>()
        };

        foreach (var args in cases)
        {
            var expected = CreateExpectedCliBuildOperandIndices(args);
            var kindIds = new int[args.Length];
            var nextIndices = new int[args.Length];
            var previousIndices = new int[args.Length];
            var nextOptionIndices = new int[args.Length];
            var resultIndices = new int[args.Length];
            var actualCount = (int)(cliBuildOperandIndicesInto.Invoke(
                null,
                new object[] { args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices }) ?? -1);

            Assert.Equal(expected.Length, actualCount);
            Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

            Array.Clear(kindIds);
            Array.Clear(nextIndices);
            Array.Clear(previousIndices);
            Array.Clear(nextOptionIndices);
            Array.Clear(resultIndices);
            var summaryCount = (int)(cliBuildOperandSummaryInto.Invoke(
                null,
                new object[] { args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices }) ?? -1);

            Assert.Equal(expected.Length, summaryCount);
            if (expected.Length == 0)
            {
                Assert.True(resultIndices.Length == 0 || resultIndices[0] == -1);
            }
            else
            {
                Assert.Equal(expected[0], resultIndices[0]);
            }

            Array.Clear(kindIds);
            Array.Clear(nextIndices);
            Array.Clear(previousIndices);
            Array.Clear(nextOptionIndices);
            Array.Clear(resultIndices);
            var firstOperandIndex = (int)(cliBuildFirstOperandIndexInto.Invoke(
                null,
                new object[] { args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices }) ?? -2);

            Assert.Equal(expected.Length == 0 ? -1 : expected[0], firstOperandIndex);
        }
    }

    private static int[] CreateExpectedCliBuildOperandIndices(string[] args)
    {
        var remaining = args
            .Select((arg, index) => (arg, index))
            .Where(entry => entry.arg is not "--release" and not "--verbose" and not "--timings" and not "--perf-report" and not "--aot")
            .ToArray();

        remaining = StripExpectedBuildOptionWithValue(remaining, "--output");
        remaining = StripExpectedBuildOptionWithValue(remaining, "-o");
        remaining = StripExpectedBuildOptionWithValue(remaining, "--backend");
        remaining = StripExpectedBuildOptionWithValue(remaining, "--project");
        return remaining.Select(entry => entry.index).ToArray();
    }

    private static (string arg, int index)[] StripExpectedBuildOptionWithValue(
        (string arg, int index)[] args,
        string flag)
    {
        var result = new List<(string arg, int index)>();
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i].arg == flag && i + 1 < args.Length)
            {
                i++;
                continue;
            }

            result.Add(args[i]);
        }

        return result.ToArray();
    }

    private static void AssertCliBuildOptionsLikeProduction(
        MethodInfo cliBuildOptionSummaryInto,
        MethodInfo cliBuildOptionSummaryChecksumInto)
    {
        var cases = new[]
        {
            new[]
            {
                "--release",
                "--verbose",
                "--timings",
                "--perf-report",
                "--aot",
                "--output",
                "dist",
                "-o",
                "ignored-short-output",
                "--backend",
                "il",
                "--project",
                "samples/demo",
                "Program.nl"
            },
            new[] { "-o", "short-dist", "--output", "long-dist", "--project", "--backend" },
            new[] { "--output", "--release", "--backend", "il", "--project" },
            new[] { "help", "--release" },
            new[] { "--help" },
            new[] { "-h" },
            Array.Empty<string>()
        };

        foreach (var args in cases)
        {
            var expected = CreateExpectedCliBuildOptionSummary(args);

            var resultIndices = new int[9];
            var actualCode = (int)(cliBuildOptionSummaryInto.Invoke(
                null,
                new object[] { args, resultIndices }) ?? -2);

            Assert.Equal(0, actualCode);
            Assert.Equal(expected, resultIndices);

            Array.Clear(resultIndices);
            var actualChecksum = (int)(cliBuildOptionSummaryChecksumInto.Invoke(
                null,
                new object[] { args, resultIndices }) ?? -2);

            Assert.Equal(CliBuildOptionSummaryChecksum(args, expected), actualChecksum);
            Assert.Equal(expected, resultIndices);

            var shortCode = (int)(cliBuildOptionSummaryInto.Invoke(
                null,
                new object[] { args, new int[8] }) ?? 0);

            Assert.Equal(-1, shortCode);
        }
    }

    private static int[] CreateExpectedCliBuildOptionSummary(string[] args)
    {
        var result = new int[9];
        result[0] = IndexOfOptionValue(args, "--output");
        if (result[0] < 0)
            result[0] = IndexOfOptionValue(args, "-o");
        result[1] = IndexOfOptionValue(args, "--backend");
        result[2] = IndexOfOptionValue(args, "--project");
        result[3] = args.Contains("--release") ? 1 : 0;
        result[4] = args.Contains("--verbose") ? 1 : 0;
        result[5] = args.Contains("--timings") ? 1 : 0;
        result[6] = args.Contains("--perf-report") ? 1 : 0;
        result[7] = args.Contains("--aot") ? 1 : 0;
        result[8] = args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help")
            ? 1
            : 0;
        return result;
    }

    private static int IndexOfOptionValue(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == flag)
                return i + 1;
        }

        return -1;
    }

    private static int CliBuildOptionSummaryChecksum(string[] args, int[] resultIndices)
    {
        var checksum = args.Length + 23;
        for (var i = 0; i < 9; i++)
        {
            var value = resultIndices[i];
            checksum += (i + 1) * 97 + (value + 1) * 31;
            if (i < 3 && value >= 0 && value < args.Length)
            {
                checksum += args[value].Length * 13;
            }
        }

        return checksum;
    }

    private static void AssertCliExportCSharpInputOperandLikeProduction(
        MethodInfo cliExportCSharpFirstOperandIndexInto,
        MethodInfo cliExportCSharpFirstOperandChecksumInto)
    {
        var cases = new[]
        {
            new[] { "Program.nl" },
            new[] { "--output", "dist", "Program.nl" },
            new[] { "-o", "bin/out", "--project", "samples/demo", "Program.nl" },
            new[] { "--project", "samples/demo" },
            new[] { "--project" },
            new[] { "--unknown", "value-after-unknown" },
            new[] { "-o", "--output", "file" },
            new[] { "--output", "-o", "file" },
            new[] { "--project", "--output", "file" },
            new[] { "--output", "--project", "file" },
            new[] { string.Empty, "--project", "samples/demo" },
            Array.Empty<string>()
        };

        foreach (var args in cases)
        {
            var expected = CreateExpectedCliExportCSharpInputOperandIndex(args);
            var expectedChecksum = ChecksumCliExportCSharpInputOperand(args, expected);
            var kindIds = new int[args.Length];
            var nextIndices = new int[args.Length];
            var previousIndices = new int[args.Length];
            var nextOptionIndices = new int[args.Length];
            var resultIndices = new int[args.Length];
            var actualChecksum = (int)(cliExportCSharpFirstOperandChecksumInto.Invoke(
                null,
                new object[] { args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices }) ?? -3);

            Assert.Equal(expectedChecksum, actualChecksum);

            Array.Clear(kindIds);
            Array.Clear(nextIndices);
            Array.Clear(previousIndices);
            Array.Clear(nextOptionIndices);
            Array.Clear(resultIndices);
            var actual = (int)(cliExportCSharpFirstOperandIndexInto.Invoke(
                null,
                new object[] { args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices }) ?? -3);

            Assert.Equal(expected, actual);
        }
    }

    private static int CreateExpectedCliExportCSharpInputOperandIndex(string[] args)
    {
        var remaining = args
            .Select((arg, index) => (arg, index))
            .ToArray();

        remaining = StripExpectedBuildOptionWithValue(remaining, "--output");
        remaining = StripExpectedBuildOptionWithValue(remaining, "-o");
        remaining = StripExpectedBuildOptionWithValue(remaining, "--project");

        foreach (var (arg, index) in remaining)
        {
            if (!arg.StartsWith("-", StringComparison.Ordinal))
                return index;
        }

        return -1;
    }

    private static int ChecksumCliExportCSharpInputOperand(string[] args, int sourceIndex)
    {
        var checksum = sourceIndex + 1;
        if (sourceIndex < 0)
            return checksum;

        var arg = args[sourceIndex];
        checksum += arg.Length * 31;
        for (var i = 0; i < arg.Length; i++)
        {
            checksum += arg[i] * (i + 1);
        }

        return checksum;
    }

    private static void AssertCliRunSourceOperandLikeProduction(MethodInfo cliRunFirstOperandIndex)
    {
        var cases = new[]
        {
            Array.Empty<string>(),
            new[] { "Program.nl" },
            new[] { "--backend", "il" },
            new[] { "--backend", "il", "Program.nl" },
            new[] { "Program.nl", "--backend", "il" },
            new[] { "--backend" },
            new[] { "--backend", "--unknown", "Program.nl" },
            new[] { "--unknown", "Program.nl" },
            new[] { "--backend", "il", "--backend" },
            new[] { "--backend", "il", "--backend", "native", "Program.nl" }
        };

        foreach (var args in cases)
        {
            var expected = CreateExpectedCliRunSourceOperandIndex(args);
            var actual = (int)(cliRunFirstOperandIndex.Invoke(
                null,
                new object[] { args }) ?? -2);

            Assert.Equal(expected, actual);
        }
    }

    private static int CreateExpectedCliRunSourceOperandIndex(string[] args)
    {
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == "--backend" && i + 1 < args.Length)
            {
                i++;
                continue;
            }

            return i;
        }

        return -1;
    }

    private static void AssertCliWatchForwardedArgsLikeProduction(
        MethodInfo cliWatchForwardedArgIndicesInto,
        MethodInfo cliWatchForwardedArgChecksumInto)
    {
        var cases = new[]
        {
            new[]
            {
                "test",
                "--project",
                "samples/demo",
                "--filter",
                "AddPerson",
                "--debounce-ms",
                "50",
                "--json",
                "--max-runs",
                "2",
                "--coverage",
                "--backend",
                "il",
                "--help",
                "SpecificTest",
                "-h",
                "--",
                "literal",
                "--max-runs",
                "--project",
                "--filter",
                "value-after-missing-project",
                "--unknown",
                "unknown-value"
            },
            new[] { "check" },
            new[] { "lint", "--project" },
            new[] { "format", "--max-runs", "--project", "--diff" },
            Array.Empty<string>()
        };

        foreach (var args in cases)
        {
            var expected = CreateExpectedCliWatchForwardedArgIndices(args);

            var resultIndices = new int[args.Length];
            var actualCount = (int)(cliWatchForwardedArgIndicesInto.Invoke(
                null,
                new object[] { args, resultIndices }) ?? -1);

            Assert.Equal(expected.Length, actualCount);
            Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

            Array.Clear(resultIndices);
            var actualChecksum = (int)(cliWatchForwardedArgChecksumInto.Invoke(
                null,
                new object[] { args, resultIndices }) ?? -1);

            Assert.Equal(CliWatchForwardedArgChecksum(expected, args, expected.Length), actualChecksum);
            Assert.Equal(expected, resultIndices.Take(expected.Length).ToArray());

            if (args.Length > 2)
            {
                var shortBuffer = new int[2];
                var shortCount = (int)(cliWatchForwardedArgIndicesInto.Invoke(
                    null,
                    new object[] { args, shortBuffer }) ?? -1);

                Assert.Equal(expected.Length, shortCount);
                var writtenCount = Math.Min(expected.Length, shortBuffer.Length);
                Assert.Equal(
                    expected.Take(writtenCount).ToArray(),
                    shortBuffer.Take(writtenCount).ToArray());
            }
        }
    }

    private static int[] CreateExpectedCliWatchForwardedArgIndices(string[] args)
    {
        var forwarded = new List<int>();

        for (var i = 1; i < args.Length; i++)
        {
            if (args[i] is "--project" or "--debounce-ms" or "--max-runs")
            {
                i++;
                continue;
            }

            if (args[i] is "--help" or "-h")
                continue;

            forwarded.Add(i);
        }

        return forwarded.ToArray();
    }

    private static int CliWatchForwardedArgChecksum(
        int[] orderedIndices,
        string[] args,
        int resultBufferLength)
    {
        var checksum = orderedIndices.Length;
        var count = Math.Min(orderedIndices.Length, resultBufferLength);
        for (var i = 0; i < count; i++)
        {
            var sourceIndex = orderedIndices[i];
            checksum += (i + 1) * 97 + (sourceIndex + 1) * 31 + args[sourceIndex].Length * 17;
        }

        return checksum;
    }

    private static void AssertCliPublishOptionsLikeProduction(MethodInfo cliPublishOptionsInto)
    {
        var cases = new[]
        {
            Array.Empty<string>(),
            new[]
            {
                "-c", "Debug",
                "--output", "dist",
                "--runtime", "osx-arm64",
                "--aot",
                "--self-contained",
                "--project", "samples/demo",
                "--backend", "il",
                "--configuration", "Release",
                "-o", "ignored-output",
                "-r", "ignored-runtime"
            },
            new[] { "-c", "Debug", "-o", "dist", "-r", "osx-arm64" },
            new[] { "--project", "first", "--project", "second", "--backend", "il" },
            new[] { "--project" },
            new[] { "--project", "--backend", "il" },
            new[] { "--target", "linux-x64" },
            new[] { "--target-platform" },
            new[] { "--bad" },
            new[] { "Project.nl" },
            new[] { string.Empty }
        };

        foreach (var args in cases)
        {
            var expected = CreateExpectedCliPublishOptions(args);
            var resultIndices = Enumerable.Repeat(-99, 8).ToArray();
            var actualCode = (int)(cliPublishOptionsInto.Invoke(
                null,
                new object[] { args, resultIndices }) ?? -2);

            Assert.Equal(expected.Code, actualCode);
            if (expected.Code == 0)
            {
                Assert.Equal(expected.Indices, resultIndices);
            }
            else
            {
                Assert.Equal(expected.ErrorIndex, resultIndices[7]);
            }
        }
    }

    private static (int Code, int[] Indices, int ErrorIndex) CreateExpectedCliPublishOptions(string[] args)
    {
        var indices = new[] { -1, -1, -1, -1, -1, 0, 0, -1 };
        var configurationLongIndex = -1;
        var configurationShortIndex = -1;
        var outputLongIndex = -1;
        var outputShortIndex = -1;
        var runtimeLongIndex = -1;
        var runtimeShortIndex = -1;

        for (var i = 0; i < args.Length; i++)
        {
            var kind = CliPublishArgumentKind(args[i]);
            if (kind is >= 1 and <= 8)
            {
                if (i + 1 >= args.Length || args[i + 1].StartsWith("-", StringComparison.Ordinal))
                {
                    indices[7] = i;
                    return (1, indices, i);
                }

                var valueIndex = i + 1;
                switch (kind)
                {
                    case 1:
                        if (indices[0] < 0) indices[0] = valueIndex;
                        break;
                    case 2:
                        if (indices[1] < 0) indices[1] = valueIndex;
                        break;
                    case 3:
                        if (configurationLongIndex < 0) configurationLongIndex = valueIndex;
                        break;
                    case 4:
                        if (configurationShortIndex < 0) configurationShortIndex = valueIndex;
                        break;
                    case 5:
                        if (outputLongIndex < 0) outputLongIndex = valueIndex;
                        break;
                    case 6:
                        if (outputShortIndex < 0) outputShortIndex = valueIndex;
                        break;
                    case 7:
                        if (runtimeLongIndex < 0) runtimeLongIndex = valueIndex;
                        break;
                    case 8:
                        if (runtimeShortIndex < 0) runtimeShortIndex = valueIndex;
                        break;
                }

                i++;
                continue;
            }

            if (kind == 9)
            {
                indices[5] = 1;
                continue;
            }

            if (kind == 10)
            {
                indices[6] = 1;
                continue;
            }

            indices[7] = i;
            if (kind == 11)
                return (2, indices, i);

            return args[i].StartsWith("-", StringComparison.Ordinal)
                ? (3, indices, i)
                : (4, indices, i);
        }

        indices[2] = configurationLongIndex >= 0 ? configurationLongIndex : configurationShortIndex;
        indices[3] = outputLongIndex >= 0 ? outputLongIndex : outputShortIndex;
        indices[4] = runtimeLongIndex >= 0 ? runtimeLongIndex : runtimeShortIndex;
        return (0, indices, -1);
    }

    private static int CliPublishArgumentKind(string arg) =>
        arg switch
        {
            "--project" => 1,
            "--backend" => 2,
            "--configuration" => 3,
            "-c" => 4,
            "--output" => 5,
            "-o" => 6,
            "--runtime" => 7,
            "-r" => 8,
            "--self-contained" => 9,
            "--aot" => 10,
            "--target" or "--target-platform" => 11,
            _ => 0
        };

    private static void AssertCliPositionalArgsLikeProduction(
        MethodInfo cliPositionalArgIndicesInto,
        MethodInfo cliFirstPositionalArgIndex,
        MethodInfo cliPositionalArgChecksumInto)
    {
        var args = new[]
        {
            "src/App.nl",
            "--project",
            "samples/demo",
            "--check",
            "--unknown",
            "README.md",
            "--output",
            "dist",
            "-o",
            "bin/out",
            "--stdin",
            string.Empty,
            "examples/hello.nl",
            "--backend",
            "il",
            "--verify-no-changes",
            "tests/fixture.nl",
            "--diff",
            "--verbose",
            "relative/path.nl",
            "-x",
            "value-after-unknown",
            "help",
            "--"
        };
        var optionsWithValues = new[] { "--project", "--output", "-o", "--backend" };
        var expected = CreateExpectedCliPositionalArgIndices(args, optionsWithValues);
        var expectedChecksum = expected.Length;
        for (var i = 0; i < expected.Length; i++)
        {
            var sourceIndex = expected[i];
            expectedChecksum += (i + 1) * 97 + (sourceIndex + 1) * 31 + args[sourceIndex].Length * 17;
        }

        var checksumResultIndices = new int[args.Length];
        var actualChecksum = (int)(cliPositionalArgChecksumInto.Invoke(
            null,
            new object[] { args, optionsWithValues, checksumResultIndices }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length));

        var resultIndices = new int[args.Length];
        var actualCount = (int)(cliPositionalArgIndicesInto.Invoke(
            null,
            new object[] { args, optionsWithValues, resultIndices }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount));

        var firstArgCases = new[]
        {
            args,
            new[] { "--project", "samples/demo", "--check", "src/App.nl" },
            new[] { "--project" },
            new[] { "--unknown", "value-after-unknown" },
            new[] { "--stdin", string.Empty, "Program.nl" },
            Array.Empty<string>()
        };

        foreach (var firstArgCase in firstArgCases)
        {
            var expectedFirst = CreateExpectedFirstCliPositionalArgIndex(firstArgCase, optionsWithValues);
            var actualFirst = (int)(cliFirstPositionalArgIndex.Invoke(
                null,
                new object[] { firstArgCase, optionsWithValues }) ?? -2);

            Assert.Equal(expectedFirst, actualFirst);
        }
    }

    private static int[] CreateExpectedCliPositionalArgIndices(
        string[] args,
        string[] optionsWithValues)
    {
        var positional = new List<int>();
        var options = new HashSet<string>(optionsWithValues, StringComparer.Ordinal);

        for (var i = 0; i < args.Length; i++)
        {
            if (options.Contains(args[i]))
            {
                i++;
                continue;
            }

            if (args[i] is "--check" or "--verify-no-changes" or "--diff" or "--stdin" or "--verbose")
                continue;

            if (!args[i].StartsWith("-", StringComparison.Ordinal))
                positional.Add(i);
        }

        return positional.ToArray();
    }

    private static int CreateExpectedFirstCliPositionalArgIndex(
        string[] args,
        string[] optionsWithValues)
    {
        var options = new HashSet<string>(optionsWithValues, StringComparer.Ordinal);

        for (var i = 0; i < args.Length; i++)
        {
            if (options.Contains(args[i]))
            {
                i++;
                continue;
            }

            if (args[i] is "--check" or "--verify-no-changes" or "--diff" or "--stdin" or "--verbose")
                continue;

            if (!args[i].StartsWith("-", StringComparison.Ordinal))
                return i;
        }

        return -1;
    }

    private static void AssertCliLintFileArgsLikeProduction(
        MethodInfo cliLintFileArgIndicesInto,
        MethodInfo cliLintFileArgChecksumInto)
    {
        var args = new[]
        {
            "--project",
            "samples/demo",
            "Program.nl",
            "--json",
            "help",
            "samples/demo",
            "src/App.nl",
            "--project",
            "other/project",
            "other/project",
            "--text",
            "-v",
            "src/Other.nl",
            string.Empty
        };
        var expected = CreateExpectedCliLintFileArgIndices(args);

        var projectValueIndices = new int[args.Length];
        var resultIndices = new int[args.Length];
        var actualCount = (int)(cliLintFileArgIndicesInto.Invoke(
            null,
            new object[] { args, projectValueIndices, resultIndices }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        Array.Clear(projectValueIndices);
        Array.Clear(resultIndices);
        var actualChecksum = (int)(cliLintFileArgChecksumInto.Invoke(
            null,
            new object[] { args, projectValueIndices, resultIndices }) ?? -1);

        Assert.Equal(CliLintFileArgChecksum(expected, args), actualChecksum);
        Assert.Equal(expected, resultIndices.Take(expected.Length).ToArray());

        var failedCount = (int)(cliLintFileArgIndicesInto.Invoke(
            null,
            new object[] { args, new int[args.Length - 1], new int[args.Length] }) ?? 0);

        Assert.Equal(-1, failedCount);
    }

    private static int[] CreateExpectedCliLintFileArgIndices(string[] args)
    {
        return args
            .Select((arg, index) => (arg, index))
            .Where(item => !item.arg.StartsWith("-", StringComparison.Ordinal) && item.arg != "help")
            .Where(item => !CliLintIsProjectOptionValue(args, item.arg))
            .Select(item => item.index)
            .ToArray();
    }

    private static bool CliLintIsProjectOptionValue(string[] args, string value)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == "--project" && args[i + 1] == value)
                return true;
        }

        return false;
    }

    private static int CliLintFileArgChecksum(int[] orderedIndices, string[] args)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31 + args[index].Length * 17;
        }

        return checksum;
    }

    private static void AssertCliTidyDependencyClassificationLikeProduction(
        MethodInfo cliTidyDependencyStatusRanksInto,
        MethodInfo cliTidyDependencyStatusRankChecksumInto)
    {
        var packageNames = new[]
        {
            "Newtonsoft.Json",
            "Serilog.Sinks.Console",
            "Polly",
            "Microsoft.Extensions.Logging",
            "Contoso.Feature.Client",
            "Unused.Package.Library",
            "ACME.Tools"
        };
        var importNamespaces = new[]
        {
            "Newtonsoft.Json.Linq",
            "Microsoft.Extensions.Logging",
            "Contoso.Feature0",
            "Acme.Tools.Runtime"
        };
        var expected = packageNames
            .Select(packageName => CreateExpectedCliTidyDependencyStatusRank(packageName, importNamespaces))
            .ToArray();

        var resultStatusRanks = new int[packageNames.Length];
        var actualCount = (int)(cliTidyDependencyStatusRanksInto.Invoke(
            null,
            new object[] { packageNames, importNamespaces, resultStatusRanks }) ?? -1);

        Assert.Equal(packageNames.Length, actualCount);
        Assert.Equal(expected, resultStatusRanks);

        Array.Clear(resultStatusRanks);
        var actualChecksum = (int)(cliTidyDependencyStatusRankChecksumInto.Invoke(
            null,
            new object[] { packageNames, importNamespaces, resultStatusRanks }) ?? -1);

        Assert.Equal(CliTidyDependencyStatusRankChecksum(expected, packageNames), actualChecksum);
        Assert.Equal(expected, resultStatusRanks);

        var failedCount = (int)(cliTidyDependencyStatusRanksInto.Invoke(
            null,
            new object[] { packageNames, importNamespaces, new int[packageNames.Length - 1] }) ?? 0);

        Assert.Equal(-1, failedCount);
    }

    private static int CreateExpectedCliTidyDependencyStatusRank(
        string packageName,
        IReadOnlyCollection<string> importNamespaces)
    {
        var segments = packageName.Split('.');
        if (segments.Length < 2)
            return 3;

        var prefix1 = segments[0];
        var prefix2 = string.Join(".", segments.Take(2));

        var matched = importNamespaces.Any(ns =>
            ns.StartsWith(prefix1 + ".", StringComparison.OrdinalIgnoreCase) ||
            ns.Equals(prefix1, StringComparison.OrdinalIgnoreCase) ||
            ns.StartsWith(prefix2 + ".", StringComparison.OrdinalIgnoreCase) ||
            ns.Equals(prefix2, StringComparison.OrdinalIgnoreCase));

        return matched ? 2 : 1;
    }

    private static int CliTidyDependencyStatusRankChecksum(
        int[] statusRanks,
        string[] packageNames)
    {
        var checksum = statusRanks.Length;
        for (var i = 0; i < statusRanks.Length; i++)
        {
            checksum += (i + 1) * 97 + statusRanks[i] * 31 + packageNames[i].Length * 17;
        }

        return checksum;
    }

    private static void AssertCliTidyRemovalLinesLikeProduction(
        MethodInfo cliTidyRemovalLineKeepFlagsInto,
        MethodInfo cliTidyRemovalLineKeepChecksumInto)
    {
        var lines = new[]
        {
            "dependencies:",
            "  - Serilog.Sinks.Console@5.0.1",
            "\t- Newtonsoft.Json@13.0.3",
            "  - nuget: Unused.Package",
            "  - NUGET: case.package",
            "  - framework: Microsoft.AspNetCore.App",
            "  - project: ../Shared/Shared.csproj",
            "  - Serilog",
            "  - Other.Package",
            "name: Demo",
            "  - nuget: Kept.Package",
            "  - Humanizer.Core",
            "  - SerilogExtra"
        };
        var packageNames = new[]
        {
            "Serilog",
            "Newtonsoft.Json",
            "Unused.Package",
            "Case.Package"
        };
        var expected = CreateExpectedCliTidyRemovalLineKeepFlags(lines, packageNames);

        var resultFlags = new int[lines.Length];
        var actualCount = (int)(cliTidyRemovalLineKeepFlagsInto.Invoke(
            null,
            new object[] { lines, packageNames, resultFlags }) ?? -1);

        Assert.Equal(lines.Length, actualCount);
        Assert.Equal(expected, resultFlags);

        Array.Clear(resultFlags);
        var actualChecksum = (int)(cliTidyRemovalLineKeepChecksumInto.Invoke(
            null,
            new object[] { lines, packageNames, resultFlags }) ?? -1);

        Assert.Equal(CliTidyRemovalLineKeepChecksum(expected, lines), actualChecksum);
        Assert.Equal(expected, resultFlags);

        var failedCount = (int)(cliTidyRemovalLineKeepFlagsInto.Invoke(
            null,
            new object[] { lines, packageNames, new int[lines.Length - 1] }) ?? 0);

        Assert.Equal(-1, failedCount);
    }

    private static int[] CreateExpectedCliTidyRemovalLineKeepFlags(
        string[] lines,
        string[] packageNames)
    {
        var toRemove = new HashSet<string>(packageNames, StringComparer.OrdinalIgnoreCase);
        return lines.Select(line =>
        {
            var trimmed = line.TrimStart();
            if (!trimmed.StartsWith("- "))
                return 1;

            foreach (var packageName in toRemove)
            {
                if (trimmed.StartsWith($"- {packageName}@", StringComparison.OrdinalIgnoreCase) ||
                    trimmed.StartsWith($"- {packageName}", StringComparison.OrdinalIgnoreCase) ||
                    trimmed.Contains($"nuget: {packageName}", StringComparison.OrdinalIgnoreCase))
                {
                    return 0;
                }
            }

            return 1;
        }).ToArray();
    }

    private static int CliTidyRemovalLineKeepChecksum(
        int[] keepFlags,
        string[] lines)
    {
        var checksum = keepFlags.Length;
        for (var i = 0; i < keepFlags.Length; i++)
        {
            checksum += (i + 1) * 97 + keepFlags[i] * 31 + lines[i].Length * 17;
        }

        return checksum;
    }

    private static void AssertCliFixSafetyFilteringLikeProduction(
        MethodInfo cliFixSafetyFilterIndicesInto,
        MethodInfo cliFixSafetyFilterChecksumInto,
        MethodInfo cliFixEditFlattenIndicesInto,
        MethodInfo cliFixEditFlattenChecksumInto,
        MethodInfo cliFixSkippedIndicesInto,
        MethodInfo cliFixSkippedChecksumInto)
    {
        var safetyRanks = new[]
        {
            1,
            2,
            3,
            1,
            0,
            2,
            3,
            1,
            2
        };

        foreach (var includeReviewNeeded in new[] { false, true })
        {
            var expected = CreateExpectedCliFixSafetyIndices(safetyRanks, includeReviewNeeded);
            var includeFlag = includeReviewNeeded ? 1 : 0;

            var actualIndices = new int[safetyRanks.Length];
            var actualCount = (int)(cliFixSafetyFilterIndicesInto.Invoke(
                null,
                new object[] { safetyRanks, includeFlag, actualIndices }) ?? -1);

            Assert.Equal(expected.Length, actualCount);
            Assert.Equal(expected, actualIndices.Take(actualCount).ToArray());

            var checksumIndices = new int[safetyRanks.Length];
            var actualChecksum = (int)(cliFixSafetyFilterChecksumInto.Invoke(
                null,
                new object[] { safetyRanks, includeFlag, checksumIndices }) ?? -1);
            var expectedChecksum = CliFixSafetyFilterChecksum(expected, safetyRanks);

            Assert.Equal(expectedChecksum, actualChecksum);
            Assert.Equal(expected, checksumIndices.Take(expected.Length).ToArray());

            var expectedSkipped = CreateExpectedCliFixSkippedIndices(safetyRanks, includeReviewNeeded);
            var actualSkippedIndices = new int[safetyRanks.Length];
            var actualSkippedCount = (int)(cliFixSkippedIndicesInto.Invoke(
                null,
                new object[] { safetyRanks, includeFlag, actualSkippedIndices }) ?? -1);

            Assert.Equal(expectedSkipped.Length, actualSkippedCount);
            Assert.Equal(expectedSkipped, actualSkippedIndices.Take(actualSkippedCount).ToArray());

            var skippedChecksumIndices = new int[safetyRanks.Length];
            var actualSkippedChecksum = (int)(cliFixSkippedChecksumInto.Invoke(
                null,
                new object[] { safetyRanks, includeFlag, skippedChecksumIndices }) ?? -1);
            var expectedSkippedChecksum = CliFixSafetyFilterChecksum(expectedSkipped, safetyRanks);

            Assert.Equal(expectedSkippedChecksum, actualSkippedChecksum);
            Assert.Equal(expectedSkipped, skippedChecksumIndices.Take(expectedSkipped.Length).ToArray());
        }

        AssertCliFixEditFlatteningLikeProduction(
            cliFixEditFlattenIndicesInto,
            cliFixEditFlattenChecksumInto);
    }

    private static void AssertCliFixAppliedFileGroupingLikeProduction(
        MethodInfo cliFixAppliedFileGroupsInto,
        MethodInfo cliFixAppliedFileGroupChecksumInto)
    {
        var files = new[]
        {
            "src/B.nl",
            "src/A.nl",
            "src/B.nl",
            "src/C.nl",
            "src/A.nl",
            "src/B.nl",
            "src/D.nl",
            "src/C.nl",
            "src/A.nl"
        };
        var ranksByFile = new Dictionary<string, int>(StringComparer.Ordinal);
        var fileRanks = new int[files.Length];
        for (var i = 0; i < files.Length; i++)
        {
            if (!ranksByFile.TryGetValue(files[i], out var rank))
            {
                rank = ranksByFile.Count + 1;
                ranksByFile.Add(files[i], rank);
            }

            fileRanks[i] = rank;
        }

        var expectedGroups = Enumerable.Range(0, files.Length)
            .GroupBy(i => files[i])
            .ToArray();
        var expectedRanks = expectedGroups
            .Select(group => ranksByFile[group.Key])
            .ToArray();
        var expectedStarts = new int[expectedGroups.Length];
        var expectedCounts = new int[expectedGroups.Length];
        var expectedIndices = new int[files.Length];
        var offset = 0;
        for (var groupIndex = 0; groupIndex < expectedGroups.Length; groupIndex++)
        {
            var members = expectedGroups[groupIndex].ToArray();
            expectedStarts[groupIndex] = offset;
            expectedCounts[groupIndex] = members.Length;
            Array.Copy(members, 0, expectedIndices, offset, members.Length);
            offset += members.Length;
        }

        var expectedChecksum = expectedGroups.Length;
        for (var groupIndex = 0; groupIndex < expectedGroups.Length; groupIndex++)
        {
            var rank = expectedRanks[groupIndex];
            var start = expectedStarts[groupIndex];
            var count = expectedCounts[groupIndex];
            expectedChecksum += (groupIndex + 1) * 97 + rank * 31 + (start + 1) * 17 + count * 13;

            for (var i = 0; i < count; i++)
            {
                var sourceIndex = expectedIndices[start + i];
                expectedChecksum += (sourceIndex + 1) * 11 + fileRanks[sourceIndex] * 7 + (i + 1) * 5;
            }
        }

        var checksumCountsByRank = new int[ranksByFile.Count + 1];
        var checksumOffsetsByRank = new int[ranksByFile.Count + 1];
        var checksumWriteOffsetsByRank = new int[ranksByFile.Count + 1];
        var checksumResultRanks = new int[files.Length];
        var checksumResultStarts = new int[files.Length];
        var checksumResultCounts = new int[files.Length];
        var checksumResultIndices = new int[files.Length];
        var actualChecksum = (int)(cliFixAppliedFileGroupChecksumInto.Invoke(
            null,
            new object[]
            {
                fileRanks,
                ranksByFile.Count,
                checksumCountsByRank,
                checksumOffsetsByRank,
                checksumWriteOffsetsByRank,
                checksumResultRanks,
                checksumResultStarts,
                checksumResultCounts,
                checksumResultIndices
            }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);

        var countsByRank = new int[ranksByFile.Count + 1];
        var offsetsByRank = new int[ranksByFile.Count + 1];
        var writeOffsetsByRank = new int[ranksByFile.Count + 1];
        var resultRanks = new int[files.Length];
        var resultStarts = new int[files.Length];
        var resultCounts = new int[files.Length];
        var resultIndices = new int[files.Length];
        var actualGroupCount = (int)(cliFixAppliedFileGroupsInto.Invoke(
            null,
            new object[]
            {
                fileRanks,
                ranksByFile.Count,
                countsByRank,
                offsetsByRank,
                writeOffsetsByRank,
                resultRanks,
                resultStarts,
                resultCounts,
                resultIndices
            }) ?? -1);

        Assert.Equal(expectedGroups.Length, actualGroupCount);
        Assert.Equal(expectedRanks, resultRanks.Take(actualGroupCount).ToArray());
        Assert.Equal(expectedStarts, resultStarts.Take(actualGroupCount).ToArray());
        Assert.Equal(expectedCounts, resultCounts.Take(actualGroupCount).ToArray());
        Assert.Equal(expectedIndices, resultIndices);
    }

    private static void AssertCliUnifiedDiffHunkRangesLikeProduction(
        MethodInfo cliUnifiedDiffHunkRangesInto,
        MethodInfo cliUnifiedDiffHunkRangeChecksumInto)
    {
        var kindIds = new[]
        {
            0, 0, 2, 1, 0, 0, 0, 0, 2, 0, 1, 1, 0, 0, 0, 2, 2, 1, 0
        };
        var oldLines = new int[kindIds.Length];
        var newLines = new int[kindIds.Length];
        var oldLine = 1;
        var newLine = 1;
        for (var i = 0; i < kindIds.Length; i++)
        {
            if (kindIds[i] == 1)
            {
                oldLines[i] = oldLine;
                newLines[i] = newLine;
                newLine++;
            }
            else if (kindIds[i] == 2)
            {
                oldLines[i] = oldLine;
                newLines[i] = newLine;
                oldLine++;
            }
            else
            {
                oldLines[i] = oldLine;
                newLines[i] = newLine;
                oldLine++;
                newLine++;
            }
        }

        const int ContextLines = 1;
        var expected = CreateExpectedCliUnifiedDiffHunkRanges(kindIds, oldLines, newLines, ContextLines);
        var expectedChecksum = CliUnifiedDiffHunkRangeChecksum(expected);

        var starts = new int[kindIds.Length];
        var lengths = new int[kindIds.Length];
        var oldStarts = new int[kindIds.Length];
        var oldCounts = new int[kindIds.Length];
        var newStarts = new int[kindIds.Length];
        var newCounts = new int[kindIds.Length];
        var actualCount = (int)(cliUnifiedDiffHunkRangesInto.Invoke(
            null,
            new object[]
            {
                kindIds,
                oldLines,
                newLines,
                ContextLines,
                starts,
                lengths,
                oldStarts,
                oldCounts,
                newStarts,
                newCounts
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected.Select(range => range.Start), starts.Take(actualCount));
        Assert.Equal(expected.Select(range => range.Length), lengths.Take(actualCount));
        Assert.Equal(expected.Select(range => range.OldStart), oldStarts.Take(actualCount));
        Assert.Equal(expected.Select(range => range.OldCount), oldCounts.Take(actualCount));
        Assert.Equal(expected.Select(range => range.NewStart), newStarts.Take(actualCount));
        Assert.Equal(expected.Select(range => range.NewCount), newCounts.Take(actualCount));

        Array.Clear(starts);
        Array.Clear(lengths);
        Array.Clear(oldStarts);
        Array.Clear(oldCounts);
        Array.Clear(newStarts);
        Array.Clear(newCounts);
        var actualChecksum = (int)(cliUnifiedDiffHunkRangeChecksumInto.Invoke(
            null,
            new object[]
            {
                kindIds,
                oldLines,
                newLines,
                ContextLines,
                starts,
                lengths,
                oldStarts,
                oldCounts,
                newStarts,
                newCounts
            }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected.Select(range => range.Start), starts.Take(expected.Length));
        Assert.Equal(expected.Select(range => range.Length), lengths.Take(expected.Length));
        Assert.Equal(expected.Select(range => range.OldStart), oldStarts.Take(expected.Length));
        Assert.Equal(expected.Select(range => range.OldCount), oldCounts.Take(expected.Length));
        Assert.Equal(expected.Select(range => range.NewStart), newStarts.Take(expected.Length));
        Assert.Equal(expected.Select(range => range.NewCount), newCounts.Take(expected.Length));

        var tooSmallStarts = new int[kindIds.Length - 1];
        var failedCount = (int)(cliUnifiedDiffHunkRangesInto.Invoke(
            null,
            new object[]
            {
                kindIds,
                oldLines,
                newLines,
                ContextLines,
                tooSmallStarts,
                new int[kindIds.Length],
                new int[kindIds.Length],
                new int[kindIds.Length],
                new int[kindIds.Length],
                new int[kindIds.Length]
            }) ?? 0);

        Assert.Equal(-1, failedCount);
    }

    private static (int Start, int Length, int OldStart, int OldCount, int NewStart, int NewCount)[]
        CreateExpectedCliUnifiedDiffHunkRanges(
            int[] kindIds,
            int[] oldLines,
            int[] newLines,
            int contextLines)
    {
        var ranges = new List<(int Start, int End)>();
        var rangeStart = -1;
        var rangeEnd = -1;
        for (var i = 0; i < kindIds.Length; i++)
        {
            if (kindIds[i] == 0)
                continue;

            var nextStart = Math.Max(0, i - contextLines);
            var nextEnd = Math.Min(kindIds.Length - 1, i + contextLines);
            if (rangeStart < 0)
            {
                rangeStart = nextStart;
                rangeEnd = nextEnd;
            }
            else if (nextStart <= rangeEnd + 1)
            {
                rangeEnd = Math.Max(rangeEnd, nextEnd);
            }
            else
            {
                ranges.Add((rangeStart, rangeEnd));
                rangeStart = nextStart;
                rangeEnd = nextEnd;
            }
        }

        if (rangeStart >= 0)
            ranges.Add((rangeStart, rangeEnd));

        return ranges
            .Select(range =>
            {
                var oldStart = 0;
                var newStart = 0;
                var oldCount = 0;
                var newCount = 0;
                for (var i = range.Start; i <= range.End; i++)
                {
                    if (oldStart == 0 && oldLines[i] > 0)
                        oldStart = oldLines[i];
                    if (newStart == 0 && newLines[i] > 0)
                        newStart = newLines[i];
                    if (kindIds[i] != 1)
                        oldCount++;
                    if (kindIds[i] != 2)
                        newCount++;
                }

                if (oldStart == 0)
                    oldStart = 1;
                if (newStart == 0)
                    newStart = 1;

                return (
                    range.Start,
                    range.End - range.Start + 1,
                    oldStart,
                    oldCount,
                    newStart,
                    newCount);
            })
            .ToArray();
    }

    private static int CliUnifiedDiffHunkRangeChecksum(
        (int Start, int Length, int OldStart, int OldCount, int NewStart, int NewCount)[] ranges)
    {
        var checksum = ranges.Length;
        for (var i = 0; i < ranges.Length; i++)
        {
            checksum += (i + 1) * 97
                + (ranges[i].Start + 1) * 31
                + ranges[i].Length * 17
                + ranges[i].OldStart * 13
                + ranges[i].OldCount * 11
                + ranges[i].NewStart * 7
                + ranges[i].NewCount * 5;
        }

        return checksum;
    }

    private static void AssertCliFixEditFlatteningLikeProduction(
        MethodInfo cliFixEditFlattenIndicesInto,
        MethodInfo cliFixEditFlattenChecksumInto)
    {
        var editCounts = new[]
        {
            1,
            0,
            3,
            8,
            9,
            2
        };
        var expected = CreateExpectedCliFixEditPairs(editCounts);

        var actionIndices = new int[expected.Length];
        var editIndices = new int[expected.Length];
        var actualCount = (int)(cliFixEditFlattenIndicesInto.Invoke(
            null,
            new object[] { editCounts, actionIndices, editIndices }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected.Select(pair => pair.ActionIndex), actionIndices.Take(actualCount));
        Assert.Equal(expected.Select(pair => pair.EditIndex), editIndices.Take(actualCount));

        Array.Clear(actionIndices);
        Array.Clear(editIndices);
        var actualChecksum = (int)(cliFixEditFlattenChecksumInto.Invoke(
            null,
            new object[] { editCounts, actionIndices, editIndices }) ?? -1);

        Assert.Equal(CliFixEditFlattenChecksum(expected, editCounts), actualChecksum);
        Assert.Equal(expected.Select(pair => pair.ActionIndex), actionIndices.Take(expected.Length));
        Assert.Equal(expected.Select(pair => pair.EditIndex), editIndices.Take(expected.Length));

        var tooSmallActions = new int[expected.Length - 1];
        var tooSmallEdits = new int[expected.Length];
        var failedCount = (int)(cliFixEditFlattenIndicesInto.Invoke(
            null,
            new object[] { editCounts, tooSmallActions, tooSmallEdits }) ?? 0);

        Assert.Equal(-1, failedCount);
    }

    private static (int ActionIndex, int EditIndex)[] CreateExpectedCliFixEditPairs(int[] editCounts)
    {
        var expected = new List<(int ActionIndex, int EditIndex)>();
        for (var actionIndex = 0; actionIndex < editCounts.Length; actionIndex++)
        {
            for (var editIndex = 0; editIndex < editCounts[actionIndex]; editIndex++)
            {
                expected.Add((actionIndex, editIndex));
            }
        }

        return expected.ToArray();
    }

    private static int CliFixEditFlattenChecksum(
        (int ActionIndex, int EditIndex)[] pairs,
        int[] editCounts)
    {
        var checksum = pairs.Length;
        for (var i = 0; i < pairs.Length; i++)
        {
            var (actionIndex, editIndex) = pairs[i];
            checksum += (i + 1) * 97
                + (actionIndex + 1) * 31
                + (editIndex + 1) * 17
                + editCounts[actionIndex] * 13;
        }

        return checksum;
    }

    private static int[] CreateExpectedCliFixSafetyIndices(int[] safetyRanks, bool includeReviewNeeded)
    {
        var maxAppliedRank = includeReviewNeeded ? 2 : 1;
        return safetyRanks
            .Select((rank, index) => (rank, index))
            .Where(item => item.rank > 0 && item.rank <= maxAppliedRank)
            .Select(item => item.index)
            .ToArray();
    }

    private static int[] CreateExpectedCliFixSkippedIndices(int[] safetyRanks, bool includeReviewNeeded)
    {
        var maxAppliedRank = includeReviewNeeded ? 2 : 1;
        return safetyRanks
            .Select((rank, index) => (rank, index))
            .Where(item => item.rank == 0 || item.rank > maxAppliedRank)
            .Select(item => item.index)
            .ToArray();
    }

    private static int CliFixSafetyFilterChecksum(int[] orderedIndices, int[] safetyRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31 + safetyRanks[index] * 17;
        }

        return checksum;
    }

    private static void AssertCliCleanArtifactDirectoryOrderingLikeProduction(
        MethodInfo cliCleanArtifactDirectoryIndicesInto,
        MethodInfo cliCleanArtifactDirectoryChecksumInto)
    {
        var kindRanks = new[]
        {
            1, 2, 0, 3, 1, 2, 1, 3, 2, 1
        };
        var nodeModuleFlags = new[]
        {
            0, 0, 0, 0, 1, 0, 0, 0, 0, 0
        };
        var pathRanks = new[]
        {
            1, 2, 3, 4, 5, 6, 1, 7, 8, 9
        };
        var pathLengths = new[]
        {
            30, 35, 20, 42, 50, 25, 30, 42, 35, 10
        };
        var expected = new[] { 3, 7, 1, 8, 0, 5, 9 };

        var resultIndices = new int[kindRanks.Length];
        var actualCount = (int)(cliCleanArtifactDirectoryIndicesInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nodeModuleFlags,
                pathRanks,
                pathLengths,
                new int[pathRanks.Max() + 1],
                new int[pathLengths.Max() + 1],
                new int[pathLengths.Max() + 1],
                new int[kindRanks.Length],
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[kindRanks.Length];
        var actualChecksum = (int)(cliCleanArtifactDirectoryChecksumInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nodeModuleFlags,
                pathRanks,
                pathLengths,
                new int[pathRanks.Max() + 1],
                new int[pathLengths.Max() + 1],
                new int[pathLengths.Max() + 1],
                new int[kindRanks.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = CliCleanArtifactDirectoryChecksum(expected, kindRanks, pathRanks, pathLengths);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static int CliCleanArtifactDirectoryChecksum(
        int[] orderedIndices,
        int[] kindRanks,
        int[] pathRanks,
        int[] pathLengths)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97
                + (index + 1) * 31
                + kindRanks[index] * 17
                + pathRanks[index] * 13
                + pathLengths[index] * 7;
        }

        return checksum;
    }

    private static void AssertCliUpdateTargetNuGetDependencyFilteringLikeProduction(
        MethodInfo cliUpdateTargetNuGetDependencyIndicesInto,
        MethodInfo cliUpdateTargetNuGetDependencyChecksumInto)
    {
        var nameRanks = new[]
        {
            1, 0, 2, 1, 0, 3, 2, 0
        };
        var cases = new[]
        {
            (TargetNameRank: 1, Expected: new[] { 0, 3 }),
            (TargetNameRank: 2, Expected: new[] { 2, 6 }),
            (TargetNameRank: -1, Expected: Array.Empty<int>()),
            (TargetNameRank: 0, Expected: Array.Empty<int>())
        };

        foreach (var (targetNameRank, expected) in cases)
        {
            var resultIndices = new int[nameRanks.Length];
            var actualCount = (int)(cliUpdateTargetNuGetDependencyIndicesInto.Invoke(
                null,
                new object[] { nameRanks, targetNameRank, resultIndices }) ?? -1);

            Assert.Equal(expected.Length, actualCount);
            Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

            var checksumResultIndices = new int[nameRanks.Length];
            var actualChecksum = (int)(cliUpdateTargetNuGetDependencyChecksumInto.Invoke(
                null,
                new object[] { nameRanks, targetNameRank, checksumResultIndices }) ?? -1);
            var expectedChecksum = CliUpdateTargetNuGetDependencyChecksum(expected, nameRanks);

            Assert.Equal(expectedChecksum, actualChecksum);
            Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
        }
    }

    private static void AssertCliUpdateAllNuGetDependencyFilteringLikeProduction(
        MethodInfo cliUpdateAllNuGetDependencyIndicesInto,
        MethodInfo cliUpdateAllNuGetDependencyChecksumInto)
    {
        var nugetFlags = new[]
        {
            1, 0, 1, 1, 0, 0, 1, 0
        };
        var expected = new[] { 0, 2, 3, 6 };

        var resultIndices = new int[nugetFlags.Length];
        var actualCount = (int)(cliUpdateAllNuGetDependencyIndicesInto.Invoke(
            null,
            new object[] { nugetFlags, resultIndices }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[nugetFlags.Length];
        var actualChecksum = (int)(cliUpdateAllNuGetDependencyChecksumInto.Invoke(
            null,
            new object[] { nugetFlags, checksumResultIndices }) ?? -1);
        var expectedChecksum = CliUpdateAllNuGetDependencyChecksum(expected, nugetFlags);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static int CliUpdateAllNuGetDependencyChecksum(
        int[] orderedIndices,
        int[] nugetFlags)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97
                + (index + 1) * 31
                + nugetFlags[index] * 17;
        }

        return checksum;
    }

    private static int CliUpdateTargetNuGetDependencyChecksum(
        int[] orderedIndices,
        int[] nameRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97
                + (index + 1) * 31
                + 17
                + nameRanks[index] * 13;
        }

        return checksum;
    }

    private static void AssertCliReferenceTypeFilteringLikeProduction(
        MethodInfo cliReferenceTypeFilterIndicesInto,
        MethodInfo cliReferenceTypeFilterChecksumInto)
    {
        var typeRanks = new[]
        {
            1, 3, 2, 4, 1, 0, 4, 2, 3, 1
        };
        var cases = new[]
        {
            (TargetTypeRank: 1, Expected: new[] { 0, 4, 9 }),
            (TargetTypeRank: 2, Expected: new[] { 2, 7 }),
            (TargetTypeRank: 3, Expected: new[] { 1, 8 }),
            (TargetTypeRank: 4, Expected: new[] { 3, 6 }),
            (TargetTypeRank: 0, Expected: Array.Empty<int>()),
            (TargetTypeRank: -1, Expected: Array.Empty<int>()),
            (TargetTypeRank: 99, Expected: Array.Empty<int>())
        };

        foreach (var (targetTypeRank, expected) in cases)
        {
            var resultIndices = new int[typeRanks.Length];
            var actualCount = (int)(cliReferenceTypeFilterIndicesInto.Invoke(
                null,
                new object[] { typeRanks, targetTypeRank, resultIndices }) ?? -1);

            Assert.Equal(expected.Length, actualCount);
            Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

            var checksumResultIndices = new int[typeRanks.Length];
            var actualChecksum = (int)(cliReferenceTypeFilterChecksumInto.Invoke(
                null,
                new object[] { typeRanks, targetTypeRank, checksumResultIndices }) ?? -1);
            var expectedChecksum = CliReferenceTypeFilterChecksum(expected, typeRanks);

            Assert.Equal(expectedChecksum, actualChecksum);
            Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
        }
    }

    private static int CliReferenceTypeFilterChecksum(
        int[] orderedIndices,
        int[] typeRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97
                + (index + 1) * 31
                + typeRanks[index] * 17;
        }

        return checksum;
    }

    private static void AssertCliReferenceResolutionBestScoreSelectionLikeProduction(
        MethodInfo cliReferenceResolutionBestScoreIndex,
        MethodInfo cliReferenceResolutionBestScoreChecksum)
    {
        var scores = new[] { -1, 40, 900, 120, 900, 30, -1 };
        var weights = new[] { 0, 11, 19, 23, 31, 37, 0 };
        var expected = Enumerable.Range(0, scores.Length)
            .Where(index => scores[index] >= 0)
            .OrderByDescending(index => scores[index])
            .First();

        var actual = (int)(cliReferenceResolutionBestScoreIndex.Invoke(
            null,
            new object[] { scores, scores.Length }) ?? -1);

        Assert.Equal(expected, actual);

        var actualChecksum = (int)(cliReferenceResolutionBestScoreChecksum.Invoke(
            null,
            new object[] { scores, weights, scores.Length }) ?? -1);
        var expectedChecksum = (expected + 1) * 97 + scores[expected] * 31 + weights[expected] * 17;

        Assert.Equal(expectedChecksum, actualChecksum);

        var noMatchScores = new[] { -1, -1, -1 };
        var noMatch = (int)(cliReferenceResolutionBestScoreIndex.Invoke(
            null,
            new object[] { noMatchScores, noMatchScores.Length }) ?? 0);
        Assert.Equal(-1, noMatch);

        var empty = (int)(cliReferenceResolutionBestScoreIndex.Invoke(
            null,
            new object[] { scores, 0 }) ?? 0);
        Assert.Equal(-1, empty);

        var invalidCount = (int)(cliReferenceResolutionBestScoreIndex.Invoke(
            null,
            new object[] { scores, scores.Length + 1 }) ?? 0);
        Assert.Equal(-2, invalidCount);
    }

    private static void AssertCliSymbolNameGlobFilteringLikeProduction(
        MethodInfo cliSymbolNameGlobFilterIndicesInto)
    {
        var names = new[]
        {
            "UserService",
            "OrderService",
            "UserQuery",
            "RenderPipeline",
            "CurrentUser",
            "DataSet",
            "DataQuerySet",
            "BuildGraph",
            "queryRunner",
            "USER_INDEX"
        };
        var cases = new[]
        {
            (Pattern: "*Service", Limit: 200),
            (Pattern: "User*", Limit: 200),
            (Pattern: "*Query*", Limit: 200),
            (Pattern: "Data*Set", Limit: 200),
            (Pattern: "*", Limit: 3),
            (Pattern: "No*Match", Limit: 200)
        };

        foreach (var (pattern, limit) in cases)
        {
            var expectedIndices = ExpectedCliSymbolNameFilterIndices(names, pattern, limit);
            var actualIndices = new int[Math.Min(limit, names.Length)];
            var actualCount = (int)(cliSymbolNameGlobFilterIndicesInto.Invoke(
                null,
                new object[] { names, pattern, limit, actualIndices }) ?? -1);

            Assert.Equal(expectedIndices.Length, actualCount);
            Assert.Equal(expectedIndices, actualIndices.Take(actualCount).ToArray());
        }
    }

    private static int[] ExpectedCliSymbolNameFilterIndices(
        string[] names,
        string pattern,
        int limit)
    {
        var regex = BuildCliSymbolNameFilterRegex(pattern);
        return names
            .Select((name, index) => (name, index))
            .Where(item => regex.IsMatch(item.name))
            .Take(limit)
            .Select(item => item.index)
            .ToArray();
    }

    private static void AssertCliSymbolNameSubstringFilteringLikeProduction(
        MethodInfo cliSymbolNameSubstringFilterIndicesInto)
    {
        var names = new[]
        {
            "UserService",
            "OrderService",
            "UserQuery",
            "RenderPipeline",
            "CurrentUser",
            "DataSet",
            "DataQuerySet",
            "BuildGraph",
            "queryRunner",
            "USER_INDEX"
        };
        var cases = new[]
        {
            (Pattern: "service", Limit: 200),
            (Pattern: "USER", Limit: 200),
            (Pattern: "query", Limit: 2),
            (Pattern: "Pipeline", Limit: 200),
            (Pattern: "NoMatch", Limit: 200)
        };

        foreach (var (pattern, limit) in cases)
        {
            var expectedIndices = ExpectedCliSymbolNameFilterIndices(names, pattern, limit);
            var actualIndices = new int[Math.Min(limit, names.Length)];
            var actualCount = (int)(cliSymbolNameSubstringFilterIndicesInto.Invoke(
                null,
                new object[] { names, pattern, limit, actualIndices }) ?? -1);

            Assert.Equal(expectedIndices.Length, actualCount);
            Assert.Equal(expectedIndices, actualIndices.Take(actualCount).ToArray());
        }
    }

    private static Regex BuildCliSymbolNameFilterRegex(string pattern)
    {
        if (pattern.Contains('*'))
        {
            var regexPattern = "^" + Regex.Escape(pattern).Replace("\\*", ".*") + "$";
            return new Regex(regexPattern, RegexOptions.IgnoreCase, TimeSpan.FromMilliseconds(200));
        }

        return new Regex(Regex.Escape(pattern), RegexOptions.IgnoreCase, TimeSpan.FromMilliseconds(200));
    }

    private static void AssertCliDocSymbolOrderingLikeProduction(
        MethodInfo cliDocSymbolOrderCountingIndicesInto,
        MethodInfo cliDocSymbolOrderCountingChecksumInto)
    {
        var symbols = new[]
        {
            (Kind: SymbolKind.Method, Name: "zeta"),
            (Kind: SymbolKind.Function, Name: "alpha"),
            (Kind: SymbolKind.Variable, Name: "ignoredVariable"),
            (Kind: SymbolKind.Class, Name: "Customer"),
            (Kind: SymbolKind.Parameter, Name: "ignoredParameter"),
            (Kind: SymbolKind.Function, Name: "alpha"),
            (Kind: SymbolKind.Enum, Name: "OrderState"),
            (Kind: SymbolKind.Property, Name: "Name"),
            (Kind: SymbolKind.Method, Name: "alpha"),
            (Kind: SymbolKind.TypeAlias, Name: "Amount"),
            (Kind: SymbolKind.Class, Name: "Account")
        };
        var expected = symbols
            .Select((symbol, index) => (symbol.Kind, symbol.Name, Index: index))
            .Where(symbol => symbol.Kind is not SymbolKind.Variable and not SymbolKind.Parameter)
            .OrderBy(symbol => symbol.Kind.ToString(), StringComparer.Ordinal)
            .ThenBy(symbol => symbol.Name, StringComparer.Ordinal)
            .Select(symbol => symbol.Index)
            .ToArray();

        var kindRanks = new int[symbols.Length];
        var nameRanks = new int[symbols.Length];
        var includeFlags = new int[symbols.Length];
        var nameRankMap = symbols
            .Select(symbol => symbol.Name)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(name => name, StringComparer.Ordinal)
            .Select((name, index) => (name, rank: index + 1))
            .ToDictionary(item => item.name, item => item.rank, StringComparer.Ordinal);
        var kindRankMap = Enum.GetValues<SymbolKind>()
            .OrderBy(kind => kind.ToString(), StringComparer.Ordinal)
            .Select((kind, index) => (kind, rank: index + 1))
            .ToDictionary(item => item.kind, item => item.rank);

        for (var i = 0; i < symbols.Length; i++)
        {
            kindRanks[i] = kindRankMap[symbols[i].Kind];
            nameRanks[i] = nameRankMap[symbols[i].Name];
            includeFlags[i] = symbols[i].Kind is SymbolKind.Variable or SymbolKind.Parameter ? 0 : 1;
        }

        var resultIndices = new int[symbols.Length];
        var tempIndices = new int[symbols.Length];
        var actualCount = (int)(cliDocSymbolOrderCountingIndicesInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                includeFlags,
                new int[symbols.Length + 1],
                new int[symbols.Length + 1],
                new int[32],
                new int[32],
                tempIndices,
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[symbols.Length];
        var actualChecksum = (int)(cliDocSymbolOrderCountingChecksumInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                includeFlags,
                new int[symbols.Length + 1],
                new int[symbols.Length + 1],
                new int[32],
                new int[32],
                new int[symbols.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = CliDocSymbolOrderChecksum(expected, kindRanks, nameRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static int CliDocSymbolOrderChecksum(
        IReadOnlyList<int> orderedIndices,
        int[] kindRanks,
        int[] nameRanks)
    {
        var checksum = orderedIndices.Count;
        for (var i = 0; i < orderedIndices.Count; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31 + kindRanks[index] * 17 + nameRanks[index] * 13;
        }

        return checksum;
    }

    private static void AssertCliDocMemberOrderingLikeProduction(
        MethodInfo cliDocSymbolOrderCountingIndicesInto,
        MethodInfo cliDocSymbolOrderCountingChecksumInto)
    {
        var members = new[]
        {
            (Kind: SymbolKind.Method, Name: "zeta"),
            (Kind: SymbolKind.Function, Name: "alpha"),
            (Kind: SymbolKind.Variable, Name: "value"),
            (Kind: SymbolKind.Parameter, Name: "customer"),
            (Kind: SymbolKind.Class, Name: "Customer"),
            (Kind: SymbolKind.Property, Name: "Name"),
            (Kind: SymbolKind.Method, Name: "alpha"),
            (Kind: SymbolKind.Field, Name: "Amount")
        };
        var expected = members
            .Select((member, index) => (member.Kind, member.Name, Index: index))
            .OrderBy(member => member.Kind.ToString(), StringComparer.Ordinal)
            .ThenBy(member => member.Name, StringComparer.Ordinal)
            .Select(member => member.Index)
            .ToArray();

        var kindRanks = new int[members.Length];
        var nameRanks = new int[members.Length];
        var includeFlags = Enumerable.Repeat(1, members.Length).ToArray();
        var nameRankMap = members
            .Select(member => member.Name)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(name => name, StringComparer.Ordinal)
            .Select((name, index) => (name, rank: index + 1))
            .ToDictionary(item => item.name, item => item.rank, StringComparer.Ordinal);
        var kindRankMap = Enum.GetValues<SymbolKind>()
            .OrderBy(kind => kind.ToString(), StringComparer.Ordinal)
            .Select((kind, index) => (kind, rank: index + 1))
            .ToDictionary(item => item.kind, item => item.rank);

        for (var i = 0; i < members.Length; i++)
        {
            kindRanks[i] = kindRankMap[members[i].Kind];
            nameRanks[i] = nameRankMap[members[i].Name];
        }

        var resultIndices = new int[members.Length];
        var actualCount = (int)(cliDocSymbolOrderCountingIndicesInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                includeFlags,
                new int[members.Length + 1],
                new int[members.Length + 1],
                new int[32],
                new int[32],
                new int[members.Length],
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[members.Length];
        var actualChecksum = (int)(cliDocSymbolOrderCountingChecksumInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                includeFlags,
                new int[members.Length + 1],
                new int[members.Length + 1],
                new int[32],
                new int[32],
                new int[members.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = CliDocSymbolOrderChecksum(expected, kindRanks, nameRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static void AssertCliDocSlugsLikeProduction(MethodInfo cliDocSlugsInto)
    {
        var rawSlugs = new[]
        {
            "Class-Customer-/tmp/Customer.nl",
            "Method-GetById-Service.Core.nl",
            "TypeAlias-Result<T>-Errors.nl",
            "Function-R\u00e9sum\u00e9_Count-Reports 2026.nl",
            "Property-HTTPClient2-API.Client.nl"
        };
        var expectedSlugs = rawSlugs.Select(CreateExpectedCliDocSlug).ToArray();

        var directSlugs = new string[rawSlugs.Length];
        var directCount = (int)(cliDocSlugsInto.Invoke(
            null,
            new object[] { rawSlugs, directSlugs }) ?? -1);

        Assert.Equal(rawSlugs.Length, directCount);
        Assert.Equal(expectedSlugs, directSlugs);
    }

    private static string CreateExpectedCliDocSlug(string raw)
    {
        var chars = raw
            .ToLowerInvariant()
            .Select(ch => char.IsLetterOrDigit(ch) ? ch : '-')
            .ToArray();
        return string.Join(string.Empty, new string(chars).Split('-', StringSplitOptions.RemoveEmptyEntries));
    }

    private static void AssertCliTreeDependencyDeduplicationLikeProduction(
        MethodInfo cliTreeDependencyDeduplicateIndicesInto,
        MethodInfo cliTreeDependencyDeduplicateChecksumInto)
    {
        var dependencies = new[]
        {
            (Kind: "nuget", Name: "Serilog"),
            (Kind: "framework", Name: "Microsoft.AspNetCore.App"),
            (Kind: "nuget", Name: "serilog"),
            (Kind: "project", Name: "../Shared/Shared.csproj"),
            (Kind: "nuget", Name: "Newtonsoft.Json"),
            (Kind: "framework", Name: "microsoft.aspnetcore.app"),
            (Kind: "dll", Name: "Lib/Analyzers.dll"),
            (Kind: "nuget", Name: "System.Text.Json")
        };
        var firstIndices = new List<int>();
        for (var i = 0; i < dependencies.Length; i++)
        {
            var duplicate = false;
            for (var j = 0; j < i; j++)
            {
                if (string.Equals(dependencies[i].Kind, dependencies[j].Kind, StringComparison.Ordinal) &&
                    string.Equals(dependencies[i].Name, dependencies[j].Name, StringComparison.OrdinalIgnoreCase))
                {
                    duplicate = true;
                    break;
                }
            }

            if (!duplicate)
                firstIndices.Add(i);
        }

        var expected = firstIndices
            .OrderBy(index => dependencies[index].Kind, StringComparer.Ordinal)
            .ThenBy(index => dependencies[index].Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var kindRanks = new int[dependencies.Length];
        var nameRanks = new int[dependencies.Length];
        var kindRankMap = dependencies
            .Select(dependency => dependency.Kind)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(kind => kind, StringComparer.Ordinal)
            .Select((kind, index) => (kind, rank: index + 1))
            .ToDictionary(item => item.kind, item => item.rank, StringComparer.Ordinal);
        var nameRankMap = dependencies
            .Select(dependency => dependency.Name)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(name => name, StringComparer.OrdinalIgnoreCase)
            .Select((name, index) => (name, rank: index + 1))
            .ToDictionary(item => item.name, item => item.rank, StringComparer.OrdinalIgnoreCase);

        for (var i = 0; i < dependencies.Length; i++)
        {
            kindRanks[i] = kindRankMap[dependencies[i].Kind];
            nameRanks[i] = nameRankMap[dependencies[i].Name];
        }

        var resultIndices = new int[dependencies.Length];
        var actualCount = (int)(cliTreeDependencyDeduplicateIndicesInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                new int[nameRankMap.Count + 1],
                new int[nameRankMap.Count + 1],
                new int[kindRankMap.Count + 1],
                new int[kindRankMap.Count + 1],
                new int[dependencies.Length],
                new int[dependencies.Length],
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[dependencies.Length];
        var actualChecksum = (int)(cliTreeDependencyDeduplicateChecksumInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                new int[nameRankMap.Count + 1],
                new int[nameRankMap.Count + 1],
                new int[kindRankMap.Count + 1],
                new int[kindRankMap.Count + 1],
                new int[dependencies.Length],
                new int[dependencies.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = CliDocSymbolOrderChecksum(expected, kindRanks, nameRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static void AssertDocQueryBestTypeSelectionLikeProduction(
        MethodInfo docQueryBestTypeIndex,
        MethodInfo docQueryBestTypeChecksumInto)
    {
        var scores = new[] { 410, 2400, 900, 2400, 2400, 1300, 2400 };
        var namespaceLengths = new[] { 12, 6, 8, 6, 6, 4, 6 };
        var fullNames = new[]
        {
            "NSharpLang.Compiler.DocQuery",
            "System.ConsoleZ",
            "System.Text.StringBuilder",
            "System.ConsoleA",
            "system.consolea",
            "System.IO.File",
            "System.Collections.List"
        };
        var expected = Enumerable.Range(0, scores.Length)
            .OrderByDescending(i => scores[i])
            .ThenBy(i => namespaceLengths[i])
            .ThenBy(i => fullNames[i], StringComparer.OrdinalIgnoreCase)
            .First();

        var actual = (int)(docQueryBestTypeIndex.Invoke(
            null,
            new object[] { scores, namespaceLengths, fullNames, scores.Length }) ?? -1);

        Assert.Equal(expected, actual);

        var actualChecksum = (int)(docQueryBestTypeChecksumInto.Invoke(
            null,
            new object[] { scores, namespaceLengths, fullNames, scores.Length }) ?? -1);
        var expectedChecksum = (expected + 1) * 97 + scores[expected] * 31 + namespaceLengths[expected] * 17;

        Assert.Equal(expectedChecksum, actualChecksum);

        var empty = (int)(docQueryBestTypeIndex.Invoke(
            null,
            new object[] { scores, namespaceLengths, fullNames, 0 }) ?? 0);

        Assert.Equal(-1, empty);
    }

    private static void AssertDocQueryMemberOrderingLikeProduction(
        MethodInfo docQueryMemberOrderIndicesInto,
        MethodInfo docQueryMemberOrderChecksumInto)
    {
        var kinds = new[]
        {
            "method",
            "property",
            "constructor",
            "field",
            "event",
            "nested type",
            "method",
            "property",
            "method"
        };
        var names = new[]
        {
            "ToString",
            "Count",
            "Sample()",
            "value",
            "Changed",
            "Enumerator",
            "add",
            "count",
            "Add"
        };
        var kindRanks = kinds.Select(GetDocQueryMemberKindRank).ToArray();
        var sortedNames = names.ToArray();
        Array.Sort(sortedNames, StringComparer.OrdinalIgnoreCase);

        var nameRankMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var nextRank = 1;
        foreach (var name in sortedNames)
        {
            if (!nameRankMap.ContainsKey(name))
            {
                nameRankMap[name] = nextRank;
                nextRank++;
            }
        }

        var nameRanks = names.Select(name => nameRankMap[name]).ToArray();
        var expected = Enumerable.Range(0, names.Length)
            .OrderBy(i => kinds[i])
            .ThenBy(i => names[i], StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var resultIndices = new int[names.Length];
        var actualCount = (int)(docQueryMemberOrderIndicesInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                new int[nameRankMap.Count + 1],
                new int[nameRankMap.Count + 1],
                new int[16],
                new int[16],
                new int[names.Length],
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[names.Length];
        var actualChecksum = (int)(docQueryMemberOrderChecksumInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                new int[nameRankMap.Count + 1],
                new int[nameRankMap.Count + 1],
                new int[16],
                new int[16],
                new int[names.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = CliDocSymbolOrderChecksum(expected, kindRanks, nameRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static int GetDocQueryMemberKindRank(string kind) =>
        kind switch
        {
            "constructor" => 1,
            "event" => 2,
            "field" => 3,
            "method" => 4,
            "nested type" => 5,
            "property" => 6,
            _ => 0
        };

    private static void AssertTextEditOrderingLikeProduction(
        MethodInfo textEditOrderIndicesInto,
        MethodInfo textEditOrderChecksumInto)
    {
        var edits = new[]
        {
            new TextEdit(1, 0, 1, 0, "line1"),
            new TextEdit(3, 5, 3, 5, "line3-col5-first"),
            new TextEdit(3, 5, 3, 5, "line3-col5-second"),
            new TextEdit(2, 10, 2, 12, "line2"),
            new TextEdit(3, 3, 3, 4, "line3-col3"),
            new TextEdit(4, 1, 5, 0, "multiline")
        };
        var expected = edits
            .Select((edit, index) => (edit, index))
            .OrderByDescending(item => item.edit.StartLine)
            .ThenByDescending(item => item.edit.StartColumn)
            .ThenBy(item => item.edit.EndLine)
            .ThenBy(item => item.edit.EndColumn)
            .ThenByDescending(item => item.index)
            .Select(item => item.index)
            .ToArray();

        var startPositionRanks = BuildTextEditPositionRanks(
            edits,
            edit => (edit.StartLine, edit.StartColumn),
            out var startPositionRankCount);
        var endPositionRanks = BuildTextEditPositionRanks(
            edits,
            edit => (edit.EndLine, edit.EndColumn),
            out var endPositionRankCount);
        var bucketCapacity = Math.Max(startPositionRankCount, endPositionRankCount) + 1;

        var resultIndices = new int[edits.Length];
        var actualCount = (int)(textEditOrderIndicesInto.Invoke(
            null,
            new object[]
            {
                startPositionRanks,
                endPositionRanks,
                startPositionRankCount,
                endPositionRankCount,
                new int[bucketCapacity],
                new int[bucketCapacity],
                new int[edits.Length],
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[edits.Length];
        var actualChecksum = (int)(textEditOrderChecksumInto.Invoke(
            null,
            new object[]
            {
                startPositionRanks,
                endPositionRanks,
                startPositionRankCount,
                endPositionRankCount,
                new int[bucketCapacity],
                new int[bucketCapacity],
                new int[edits.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = TextEditOrderChecksum(
            expected,
            startPositionRanks,
            endPositionRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static int[] BuildTextEditPositionRanks(
        TextEdit[] edits,
        Func<TextEdit, (int Line, int Column)> selector,
        out int rankCount)
    {
        var rankMap = edits
            .Select(selector)
            .Distinct()
            .OrderBy(value => value)
            .Select((value, index) => (value, rank: index + 1))
            .ToDictionary(item => item.value, item => item.rank);
        var ranks = new int[edits.Length];
        for (var i = 0; i < edits.Length; i++)
        {
            ranks[i] = rankMap[selector(edits[i])];
        }

        rankCount = rankMap.Count;
        return ranks;
    }

    private static int TextEditOrderChecksum(
        int[] orderedIndices,
        int[] startPositionRanks,
        int[] endPositionRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31;
            checksum += startPositionRanks[index] * 17 + endPositionRanks[index] * 13;
        }

        return checksum;
    }

    private static void AssertFormatterImportOrderingLikeProduction(
        MethodInfo formatterImportOrderIndicesInto,
        MethodInfo formatterImportOrderChecksumInto)
    {
        // Mirrors Formatter.Format import ordering, including identical-namespace
        // duplicates to exercise the stable-sort tie path.
        var namespaces = new[]
        {
            "Zenith.Core",
            "System.Linq",
            "Acme.Widgets",
            "System",
            "System.Collections.Generic",
            "Microsoft.Extensions.Logging",
            "System.Linq",
            "Acme.Widgets",
            "NSharpLang.Compiler",
            "System.Text",
        };
        var expected = namespaces
            .Select((ns, index) => (ns, index))
            .OrderByDescending(item => item.ns.StartsWith("System", StringComparison.Ordinal))
            .ThenBy(item => item.ns, StringComparer.Ordinal)
            .Select(item => item.index)
            .ToArray();

        var systemFlags = new int[namespaces.Length];
        for (var i = 0; i < namespaces.Length; i++)
        {
            systemFlags[i] = namespaces[i].StartsWith("System", StringComparison.Ordinal) ? 1 : 0;
        }

        var nameRanks = BuildFormatterImportNameRanks(namespaces, out var nameRankCount);
        var bucketCapacity = nameRankCount + 1;

        var resultIndices = new int[namespaces.Length];
        var actualCount = (int)(formatterImportOrderIndicesInto.Invoke(
            null,
            new object[]
            {
                systemFlags,
                nameRanks,
                nameRankCount,
                new int[bucketCapacity],
                new int[bucketCapacity],
                new int[namespaces.Length],
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[namespaces.Length];
        var actualChecksum = (int)(formatterImportOrderChecksumInto.Invoke(
            null,
            new object[]
            {
                systemFlags,
                nameRanks,
                nameRankCount,
                new int[bucketCapacity],
                new int[bucketCapacity],
                new int[namespaces.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = FormatterImportOrderChecksum(expected, systemFlags, nameRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static int[] BuildFormatterImportNameRanks(string[] namespaces, out int rankCount)
    {
        var rankMap = namespaces
            .Distinct(StringComparer.Ordinal)
            .OrderBy(value => value, StringComparer.Ordinal)
            .Select((value, index) => (value, rank: index + 1))
            .ToDictionary(item => item.value, item => item.rank, StringComparer.Ordinal);
        var ranks = new int[namespaces.Length];
        for (var i = 0; i < namespaces.Length; i++)
        {
            ranks[i] = rankMap[namespaces[i]];
        }

        rankCount = rankMap.Count;
        return ranks;
    }

    private static int FormatterImportOrderChecksum(
        int[] orderedIndices,
        int[] systemFlags,
        int[] nameRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31;
            checksum += systemFlags[index] * 17 + nameRanks[index] * 13;
        }

        return checksum;
    }

    private static void AssertTypoSuggestionsLikeProduction(
        MethodInfo typoSuggestionIndicesInto,
        MethodInfo typoSuggestionChecksumInto)
    {
        var candidates = new[]
        {
            "customer",
            "customerName",
            "orderTotal",
            "invoiceNumber",
            "StringBuilder",
            "DateTime",
            "ResolveSymbol",
            "LookupIdentifier",
            "WriteLine"
        };
        var typos = new[]
        {
            "custmer",
            "customerNmae",
            "ordrTotal",
            "StringBuiler",
            "DateTiem",
            "ResolveSymbl",
            "LookupIdentifer",
            "unknown"
        };
        var expectedStarts = new int[typos.Length];
        var expectedCounts = new int[typos.Length];
        var expectedIndices = new int[typos.Length * 3];
        var candidateIndices = candidates
            .Select((candidate, index) => (candidate, index))
            .ToDictionary(item => item.candidate, item => item.index, StringComparer.Ordinal);
        var suggester = new SmartSuggester(candidates.ToList());

        var writeIndex = 0;
        for (var i = 0; i < typos.Length; i++)
        {
            var suggestions = suggester.SuggestSimilarNames(typos[i], 3);
            expectedStarts[i] = writeIndex;
            expectedCounts[i] = suggestions.Count;
            foreach (var suggestion in suggestions)
            {
                expectedIndices[writeIndex] = candidateIndices[suggestion];
                writeIndex++;
            }
        }

        var maxCandidateLength = candidates.Max(candidate => candidate.Length);
        var previousDistances = new int[maxCandidateLength + 1];
        var currentDistances = new int[maxCandidateLength + 1];
        var actualStarts = new int[typos.Length];
        var actualCounts = new int[typos.Length];
        var actualIndices = new int[typos.Length * 3];
        var actualTotal = (int)(typoSuggestionIndicesInto.Invoke(
            null,
            new object[]
            {
                typos,
                candidates,
                3,
                previousDistances,
                currentDistances,
                actualStarts,
                actualCounts,
                actualIndices
            }) ?? -1);

        Assert.Equal(writeIndex, actualTotal);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedCounts, actualCounts);
        Assert.Equal(expectedIndices, actualIndices);

        var checksumStarts = new int[typos.Length];
        var checksumCounts = new int[typos.Length];
        var checksumIndices = new int[typos.Length * 3];
        var actualChecksum = (int)(typoSuggestionChecksumInto.Invoke(
            null,
            new object[]
            {
                typos,
                candidates,
                3,
                previousDistances,
                currentDistances,
                checksumStarts,
                checksumCounts,
                checksumIndices
            }) ?? -1);
        var expectedChecksum = TypoSuggestionChecksum(writeIndex, expectedStarts, expectedCounts, expectedIndices);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, checksumStarts);
        Assert.Equal(expectedCounts, checksumCounts);
        Assert.Equal(expectedIndices, checksumIndices);
    }

    private static int TypoSuggestionChecksum(
        int total,
        int[] starts,
        int[] counts,
        int[] indices)
    {
        var checksum = total;
        for (var i = 0; i < counts.Length; i++)
        {
            var start = starts[i];
            var count = counts[i];
            checksum += start * 7 + count * 97;
            for (var j = 0; j < count; j++)
            {
                checksum += indices[start + j] * 31 + (j + 1) * 17;
            }
        }

        return checksum;
    }

    private static void AssertAotRequirementGroupingLikeProduction(
        MethodInfo aotRequirementGroupsInto,
        MethodInfo aotRequirementGroupChecksumInto)
    {
        var declarationRanks = new[] { 1, 1, 0, 2, 1, 3, 2, 3, 2, 1 };
        var kindIds = new[] { 1, 2, 1, 3, 1, 2, 1, 0, 2, 3 };
        var constructRanks = new[] { 4, 2, 0, 5, 1, 3, 2, 4, 1, 5 };
        const int uniqueDeclarationCount = 3;
        const int uniqueConstructCount = 5;

        var expectedDeclarationRanks = new[] { 1, 2, 3 };
        var expectedRequiresUnreferenced = new[] { 1, 1, 0 };
        var expectedRequiresDynamic = new[] { 1, 1, 1 };
        var expectedConstructStarts = new[] { 0, 3, 6 };
        var expectedConstructCounts = new[] { 3, 3, 2 };
        var expectedConstructRanks = new[] { 1, 2, 4, 1, 2, 5, 3, 4, 0 };

        var declarationCounts = new int[uniqueDeclarationCount + 1];
        var requiresUnreferencedByRank = new int[uniqueDeclarationCount + 1];
        var requiresDynamicByRank = new int[uniqueDeclarationCount + 1];
        var constructSeen = new int[(uniqueDeclarationCount + 1) * (uniqueConstructCount + 1)];
        var resultDeclarationRanks = new int[uniqueDeclarationCount];
        var resultRequiresUnreferenced = new int[uniqueDeclarationCount];
        var resultRequiresDynamic = new int[uniqueDeclarationCount];
        var resultConstructStarts = new int[uniqueDeclarationCount];
        var resultConstructCounts = new int[uniqueDeclarationCount];
        var resultConstructRanks = new int[uniqueDeclarationCount * 3];
        var actualCount = (int)(aotRequirementGroupsInto.Invoke(
            null,
            new object[]
            {
                declarationRanks,
                kindIds,
                constructRanks,
                uniqueDeclarationCount,
                uniqueConstructCount,
                declarationCounts,
                requiresUnreferencedByRank,
                requiresDynamicByRank,
                constructSeen,
                resultDeclarationRanks,
                resultRequiresUnreferenced,
                resultRequiresDynamic,
                resultConstructStarts,
                resultConstructCounts,
                resultConstructRanks
            }) ?? -1);

        Assert.Equal(expectedDeclarationRanks.Length, actualCount);
        Assert.Equal(expectedDeclarationRanks, resultDeclarationRanks);
        Assert.Equal(expectedRequiresUnreferenced, resultRequiresUnreferenced);
        Assert.Equal(expectedRequiresDynamic, resultRequiresDynamic);
        Assert.Equal(expectedConstructStarts, resultConstructStarts);
        Assert.Equal(expectedConstructCounts, resultConstructCounts);
        Assert.Equal(expectedConstructRanks, resultConstructRanks);

        Array.Clear(declarationCounts);
        Array.Clear(requiresUnreferencedByRank);
        Array.Clear(requiresDynamicByRank);
        Array.Clear(constructSeen);
        Array.Clear(resultDeclarationRanks);
        Array.Clear(resultRequiresUnreferenced);
        Array.Clear(resultRequiresDynamic);
        Array.Clear(resultConstructStarts);
        Array.Clear(resultConstructCounts);
        Array.Clear(resultConstructRanks);
        var actualChecksum = (int)(aotRequirementGroupChecksumInto.Invoke(
            null,
            new object[]
            {
                declarationRanks,
                kindIds,
                constructRanks,
                uniqueDeclarationCount,
                uniqueConstructCount,
                declarationCounts,
                requiresUnreferencedByRank,
                requiresDynamicByRank,
                constructSeen,
                resultDeclarationRanks,
                resultRequiresUnreferenced,
                resultRequiresDynamic,
                resultConstructStarts,
                resultConstructCounts,
                resultConstructRanks
            }) ?? -1);

        Assert.Equal(
            AotRequirementGroupingChecksum(
                expectedDeclarationRanks,
                expectedRequiresUnreferenced,
                expectedRequiresDynamic,
                expectedConstructStarts,
                expectedConstructCounts,
                expectedConstructRanks),
            actualChecksum);
        Assert.Equal(expectedDeclarationRanks, resultDeclarationRanks);
        Assert.Equal(expectedRequiresUnreferenced, resultRequiresUnreferenced);
        Assert.Equal(expectedRequiresDynamic, resultRequiresDynamic);
        Assert.Equal(expectedConstructStarts, resultConstructStarts);
        Assert.Equal(expectedConstructCounts, resultConstructCounts);
        Assert.Equal(expectedConstructRanks, resultConstructRanks);
    }

    private static int AotRequirementGroupingChecksum(
        int[] declarationRanks,
        int[] requiresUnreferenced,
        int[] requiresDynamic,
        int[] constructStarts,
        int[] constructCounts,
        int[] constructRanks)
    {
        var checksum = declarationRanks.Length;
        for (var groupIndex = 0; groupIndex < declarationRanks.Length; groupIndex++)
        {
            var start = constructStarts[groupIndex];
            var count = constructCounts[groupIndex];
            checksum += (groupIndex + 1) * 97
                + declarationRanks[groupIndex] * 31
                + requiresUnreferenced[groupIndex] * 17
                + requiresDynamic[groupIndex] * 13
                + count * 7;

            for (var offset = 0; offset < count; offset++)
            {
                checksum += constructRanks[start + offset] * (offset + 1) * 11;
            }
        }

        return checksum;
    }

    private static void AssertCliBatchDuplicateIdsLikeProduction(
        MethodInfo cliBatchDuplicateIdRanksInto,
        MethodInfo cliBatchDuplicateIdRankChecksumInto)
    {
        var ids = new[]
        {
            "zeta",
            "alpha",
            string.Empty,
            "beta",
            "alpha",
            " \t",
            "zeta",
            "résumé",
            "beta",
            "single",
            "Alpha"
        };
        var uniqueIds = ids
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Distinct(StringComparer.Ordinal)
            .OrderBy(id => id, StringComparer.Ordinal)
            .ToArray();
        var ranksById = uniqueIds
            .Select((id, index) => new { id, rank = index + 1 })
            .ToDictionary(item => item.id, item => item.rank, StringComparer.Ordinal);
        var idRanks = ids
            .Select(id => string.IsNullOrWhiteSpace(id) ? 0 : ranksById[id])
            .ToArray();
        var idLengthsByRank = new int[uniqueIds.Length + 1];
        for (var i = 0; i < uniqueIds.Length; i++)
        {
            idLengthsByRank[i + 1] = uniqueIds[i].Length;
        }

        var expectedRanks = ids
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .GroupBy(id => id, StringComparer.Ordinal)
            .Where(group => group.Count() > 1)
            .Select(group => ranksById[group.Key])
            .OrderBy(rank => rank)
            .ToArray();
        var expectedChecksum = expectedRanks.Length;
        foreach (var rank in expectedRanks)
        {
            expectedChecksum += rank * 31 + idLengthsByRank[rank] * 17;
        }

        var checksumCountsByRank = new int[uniqueIds.Length + 1];
        var checksumResultRanks = new int[ids.Length];
        var actualChecksum = (int)(cliBatchDuplicateIdRankChecksumInto.Invoke(
            null,
            new object[] { idRanks, uniqueIds.Length, checksumCountsByRank, checksumResultRanks, idLengthsByRank }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedRanks, checksumResultRanks.Take(expectedRanks.Length));

        var countsByRank = new int[uniqueIds.Length + 1];
        var resultRanks = new int[ids.Length];
        var actualCount = (int)(cliBatchDuplicateIdRanksInto.Invoke(
            null,
            new object[] { idRanks, uniqueIds.Length, countsByRank, resultRanks }) ?? -1);

        Assert.Equal(expectedRanks.Length, actualCount);
        Assert.Equal(expectedRanks, resultRanks.Take(actualCount));
    }

    private static void AssertCliBatchResultCountsLikeProduction(MethodInfo cliBatchResultPackedCountChecksum)
    {
        var cases = new[]
        {
            new[] { 1, 0, 1, 1, 0, 1 },
            new[] { 1, 1, 1, 1 },
            new[] { 0, 0, 0, 0 },
            Array.Empty<int>()
        };

        foreach (var okFlags in cases)
        {
            var successCount = okFlags.Count(flag => flag == 1);
            var failureCount = okFlags.Length - successCount;
            var expectedChecksum = okFlags.Length * 31 + successCount * 17 + failureCount * 13;
            var okWords = PackFlags(okFlags);
            var actualChecksum = (int)(cliBatchResultPackedCountChecksum.Invoke(
                null,
                new object[] { okWords, okFlags.Length }) ?? -1);

            Assert.Equal(expectedChecksum, actualChecksum);
        }

        var trailingBits = PackFlags(new[] { 1, 0, 1 });
        trailingBits[0] |= 1UL << 3;
        trailingBits[0] |= 1UL << 63;
        var trailingActualChecksum = (int)(cliBatchResultPackedCountChecksum.Invoke(
            null,
            new object[] { trailingBits, 3 }) ?? -1);
        Assert.Equal(3 * 31 + 2 * 17 + 1 * 13, trailingActualChecksum);
    }

    private static ulong[] PackFlags(IReadOnlyList<int> okFlags)
    {
        var words = new ulong[(okFlags.Count + 63) >> 6];
        for (var i = 0; i < okFlags.Count; i++)
        {
            if (okFlags[i] == 1)
                words[i >> 6] |= 1UL << (i & 63);
        }

        return words;
    }

    private static void AssertCliTestOutcomeSummaryLikeProduction(MethodInfo cliTestOutcomeSummaryChecksumInto)
    {
        var cases = new[]
        {
            new[] { 1, 1, 1, 1 },
            new[] { 1, 3, 1, 2, 1, 3 },
            new[] { 1, 0, 2, 3, 1 },
            Array.Empty<int>()
        };

        foreach (var outcomeRanks in cases)
        {
            var passed = outcomeRanks.Count(rank => rank == 1);
            var failed = outcomeRanks.Count(rank => rank == 2);
            var skipped = outcomeRanks.Count(rank => rank == 3);
            var nonOk = outcomeRanks.Count(rank => rank is not 1 and not 3);
            var okValue = nonOk == 0 ? 7 : 13;
            var expectedChecksum =
                outcomeRanks.Length + okValue + passed * 31 + failed * 17 + skipped * 11 + nonOk * 5;
            var counts = new int[4];
            var actualChecksum = (int)(cliTestOutcomeSummaryChecksumInto.Invoke(
                null,
                new object[] { outcomeRanks, outcomeRanks.Length, counts }) ?? -1);

            Assert.Equal(expectedChecksum, actualChecksum);
            Assert.Equal(new[] { passed, failed, skipped, nonOk }, counts);
        }
    }

    private static void AssertCliFormatDiscoveryLikeProduction(
        MethodInfo cliShouldFormatDiscoveredPath,
        MethodInfo cliFormatDiscoveredPathChecksumInto)
    {
        var paths = new[]
        {
            "src/Feature/Program.nl",
            "tests/Unit/Spec.nl",
            "test/fixtures/parser/case.nl",
            "Tests/FIXTURES/format/case.nl",
            "bin/Debug/net10.0/generated.nl",
            "src/binocular/File.nl",
            "node_modules/pkg/index.nl",
            ".nlc/cache/file.nl",
            "src/.git/hooks/file.nl",
            "src/obj/Generated/file.nl",
            "src/test//fixtures/case.nl",
            "src/tests/fixturesExtra/case.nl",
            "src/.worktrees/tmp/file.nl",
            "src/.hermes/cache/file.nl",
            "src/.hg/store/file.nl",
            "src/.svn/tmp/file.nl",
            "src\\test\\fixtures\\case.nl"
        };
        var expectedFlags = paths
            .Select(path => ExpectedShouldFormatDiscoveredPath(path) ? 1 : 0)
            .ToArray();

        for (var i = 0; i < paths.Length; i++)
        {
            var actual = (int)(cliShouldFormatDiscoveredPath.Invoke(
                null,
                new object[] { paths[i] }) ?? -1);
            Assert.Equal(expectedFlags[i], actual);
        }

        var resultFlags = new int[paths.Length];
        var actualChecksum = (int)(cliFormatDiscoveredPathChecksumInto.Invoke(
            null,
            new object[] { paths, resultFlags }) ?? -1);
        var expectedChecksum = CliFormatDiscoveredPathChecksum(paths, expectedFlags);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedFlags, resultFlags);
    }

    private static bool ExpectedShouldFormatDiscoveredPath(string relativePath)
    {
        var segments = relativePath
            .Replace('\\', '/')
            .Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Any(segment => segment.Equals(".git", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".hg", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".svn", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".worktrees", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".hermes", StringComparison.OrdinalIgnoreCase)
            || segment.Equals(".nlc", StringComparison.OrdinalIgnoreCase)
            || segment.Equals("bin", StringComparison.OrdinalIgnoreCase)
            || segment.Equals("obj", StringComparison.OrdinalIgnoreCase)
            || segment.Equals("node_modules", StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        for (var i = 0; i <= segments.Length - 2; i++)
        {
            var isFixtureRoot = string.Equals(segments[i], "test", StringComparison.OrdinalIgnoreCase)
                || string.Equals(segments[i], "tests", StringComparison.OrdinalIgnoreCase);
            if (isFixtureRoot && string.Equals(segments[i + 1], "fixtures", StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        return true;
    }

    private static int CliFormatDiscoveredPathChecksum(string[] paths, int[] flags)
    {
        var count = Math.Min(paths.Length, flags.Length);
        var checksum = count;
        for (var i = 0; i < count; i++)
        {
            checksum += (i + 1) * 31 + flags[i] * 17 + paths[i].Length * 7;
        }

        return checksum;
    }

    private static void AssertDocCommentsLikeProduction(
        string source,
        MethodInfo codeIntelligenceDocCommentChecksumInto,
        MethodInfo codeIntelligenceDocCommentLinesInto,
        MethodInfo codeIntelligenceDocCommentLinesFromLinesInto)
    {
        var lines = source.Split('\n');
        var queryLines = new List<int> { 0, lines.Length + 1 };
        for (var line = 1; line <= lines.Length; line++)
        {
            queryLines.Add(line);
        }

        var queries = queryLines.ToArray();
        var expectedLineCounts = new int[queries.Length];
        var expectedTextLengths = new int[queries.Length];
        var expectedChecksum = 0;

        for (var i = 0; i < queries.Length; i++)
        {
            var spans = ExtractDocCommentSpans(source, queries[i]);
            var textLength = spans.Count == 0 ? -1 : spans.Sum(span => span.Length) + spans.Count - 1;
            expectedLineCounts[i] = spans.Count;
            expectedTextLengths[i] = textLength;
            expectedChecksum += spans.Count * 13 + textLength * 7;
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualLineCounts = new int[queries.Length];
        var actualTextLengths = new int[queries.Length];
        var actualChecksum = (int)(codeIntelligenceDocCommentChecksumInto.Invoke(
            null,
            new object[] { source, lineStarts, lineLengths, queries, actualLineCounts, actualTextLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedLineCounts, actualLineCounts);
        Assert.Equal(expectedTextLengths, actualTextLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var lineCount = BuildLineRanges(source, cachedLineStarts, cachedLineLengths);

        foreach (var query in queries)
        {
            var expected = ExtractDocComment(source, query);
            var expectedSpans = ExtractDocCommentSpans(source, query);

            var directStarts = new int[source.Length + 1];
            var directLengths = new int[source.Length + 1];
            var directLineStarts = new int[source.Length + 1];
            var directLineLengths = new int[source.Length + 1];
            var directCount = (int)(codeIntelligenceDocCommentLinesInto.Invoke(
                null,
                new object[] { source, directLineStarts, directLineLengths, query, directStarts, directLengths }) ?? -1);

            Assert.Equal(expectedSpans.Count, directCount);
            Assert.Equal(expected, MaterializeDocComment(source, directStarts, directLengths, directCount));

            var cachedStarts = new int[source.Length + 1];
            var cachedLengths = new int[source.Length + 1];
            var cachedCount = (int)(codeIntelligenceDocCommentLinesFromLinesInto.Invoke(
                null,
                new object[]
                {
                    source,
                    cachedLineStarts,
                    cachedLineLengths,
                    lineCount,
                    query,
                    cachedStarts,
                    cachedLengths
                }) ?? -1);

            Assert.Equal(expectedSpans.Count, cachedCount);
            Assert.Equal(expected, MaterializeDocComment(source, cachedStarts, cachedLengths, cachedCount));
        }
    }

    private static void AssertVariableDeclarationNamesLikeProduction(
        string source,
        MethodInfo codeIntelligenceVariableDeclarationNameChecksumInto,
        MethodInfo codeIntelligenceVariableDeclarationNamesInto,
        MethodInfo buildCodeIntelligenceVariableDeclarationNameCacheInto,
        MethodInfo codeIntelligenceVariableDeclarationNamesFromCacheInto)
    {
        var lines = source.Split('\n');
        var queries = new List<int> { 0, lines.Length + 1 };
        for (var line = 1; line <= lines.Length; line++)
        {
            queries.Add(line);
        }

        var queryLines = queries.ToArray();
        var expectedStarts = new int[queryLines.Length];
        var expectedLengths = new int[queryLines.Length];
        var expectedChecksum = 0;
        var expectedCount = 0;

        for (var i = 0; i < queryLines.Length; i++)
        {
            var span = ExtractVariableDeclarationNameSpan(source, queryLines[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
            if (start >= 0)
            {
                expectedCount++;
            }
        }

        var rangeStarts = new int[source.Length + 1];
        var rangeLengths = new int[source.Length + 1];
        var actualStarts = new int[queryLines.Length];
        var actualLengths = new int[queryLines.Length];
        var actualChecksum = (int)(codeIntelligenceVariableDeclarationNameChecksumInto.Invoke(
            null,
            new object[] { source, rangeStarts, rangeLengths, queryLines, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var expectedName = ExtractVariableDeclarationName(source, line);
            var actualName = actualStarts[i] >= 0
                ? lines[line - 1].Substring(actualStarts[i] - 1, actualLengths[i])
                : null;
            Assert.Equal(expectedName, actualName);
        }

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queryLines.Length];
        var productionLengths = new int[queryLines.Length];
        var actualCount = (int)(codeIntelligenceVariableDeclarationNamesInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var cachedNameStartsByLine = new int[source.Length + 1];
        var cachedNameLengthsByLine = new int[source.Length + 1];
        var cachedStarts = new int[queryLines.Length];
        var cachedLengths = new int[queryLines.Length];
        var lineCount = BuildLineRanges(source, cachedLineStarts, cachedLineLengths);
        var cachedDeclarationCount = (int)(buildCodeIntelligenceVariableDeclarationNameCacheInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedLineStarts,
                cachedLineLengths,
                lineCount,
                cachedNameStartsByLine,
                cachedNameLengthsByLine
            }) ?? -1);

        Assert.Equal(expectedCount, cachedDeclarationCount);

        var cachedMatchCount = (int)(codeIntelligenceVariableDeclarationNamesFromCacheInto.Invoke(
            null,
            new object[]
            {
                lineCount,
                cachedNameStartsByLine,
                cachedNameLengthsByLine,
                queryLines,
                cachedStarts,
                cachedLengths
            }) ?? -1);

        Assert.Equal(expectedCount, cachedMatchCount);
        Assert.Equal(expectedStarts, cachedStarts);
        Assert.Equal(expectedLengths, cachedLengths);
    }

    private static void AssertDiagnosticSeveritySummaryLikeProduction(
        MethodInfo diagnosticSeveritySummaryInto,
        MethodInfo diagnosticSeveritySummaryChecksumInto)
    {
        var diagnostics = BuildDiagnosticSeveritySummaryDiagnostics();
        var severities = diagnostics.Select(static diagnostic => diagnostic.Severity).ToArray();
        var expectedCounts = new[]
        {
            diagnostics.Count(static diagnostic => diagnostic.Severity == "error"),
            diagnostics.Count(static diagnostic => diagnostic.Severity == "warning"),
            diagnostics.Count(static diagnostic => diagnostic.Severity == "info")
        };

        var actualCounts = new int[3];
        var actualCount = (int)(diagnosticSeveritySummaryInto.Invoke(
            null,
            new object[] { severities, severities.Length, actualCounts }) ?? -1);

        Assert.Equal(severities.Length, actualCount);
        Assert.Equal(expectedCounts, actualCounts);

        var checksumCounts = new int[3];
        var actualChecksum = (int)(diagnosticSeveritySummaryChecksumInto.Invoke(
            null,
            new object[] { severities, severities.Length, checksumCounts }) ?? -1);
        var expectedChecksum = severities.Length + expectedCounts[0] * 31 + expectedCounts[1] * 17 + expectedCounts[2] * 13;

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedCounts, checksumCounts);

        var paddedSeverities = severities.Concat(new[] { "error", "warning", "info" }).ToArray();
        var paddedCounts = new int[3];
        var paddedCount = (int)(diagnosticSeveritySummaryInto.Invoke(
            null,
            new object[] { paddedSeverities, severities.Length, paddedCounts }) ?? -1);

        Assert.Equal(severities.Length, paddedCount);
        Assert.Equal(expectedCounts, paddedCounts);
    }

    private static void AssertDiagnosticSeverityFilteringLikeProduction(
        MethodInfo diagnosticSeverityFilterIndicesInto,
        MethodInfo diagnosticSeverityFilterChecksumInto)
    {
        var severities = new[] { "error", "warning", "info", "Error", "hint", "ERROR", "warning" };
        const string targetSeverity = "eRrOr";
        var ranks = BuildDiagnosticSeverityRanks(severities, targetSeverity, out var targetRank);
        var expectedIndices = severities
            .Select((severity, index) => (severity, index))
            .Where(item => item.severity.Equals(targetSeverity, StringComparison.OrdinalIgnoreCase))
            .Select(item => item.index)
            .ToArray();

        var actualIndices = new int[severities.Length];
        var actualCount = (int)(diagnosticSeverityFilterIndicesInto.Invoke(
            null,
            new object[] { ranks, targetRank, actualIndices }) ?? -1);

        Assert.Equal(expectedIndices.Length, actualCount);
        Assert.Equal(expectedIndices, actualIndices.Take(actualCount).ToArray());

        var checksumIndices = new int[severities.Length];
        var actualChecksum = (int)(diagnosticSeverityFilterChecksumInto.Invoke(
            null,
            new object[] { ranks, targetRank, checksumIndices }) ?? -1);
        var expectedChecksum = DiagnosticSeverityFilterChecksum(expectedIndices, ranks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedIndices, checksumIndices.Take(expectedIndices.Length).ToArray());

        var missingTargetRank = ranks.Max() + 1;
        var missingIndices = new int[severities.Length];
        var missingCount = (int)(diagnosticSeverityFilterIndicesInto.Invoke(
            null,
            new object[] { ranks, missingTargetRank, missingIndices }) ?? -1);

        Assert.Equal(0, missingCount);
    }

    private static int[] BuildDiagnosticSeverityRanks(
        string[] severities,
        string targetSeverity,
        out int targetRank)
    {
        var ranksBySeverity = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        void AddSeverity(string severity)
        {
            if (!ranksBySeverity.ContainsKey(severity))
            {
                ranksBySeverity.Add(severity, ranksBySeverity.Count + 1);
            }
        }

        AddSeverity(targetSeverity);
        foreach (var severity in severities)
        {
            AddSeverity(severity);
        }

        targetRank = ranksBySeverity[targetSeverity];
        return severities.Select(severity => ranksBySeverity[severity]).ToArray();
    }

    private static int DiagnosticSeverityFilterChecksum(int[] orderedIndices, int[] severityRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31 + severityRanks[index] * 17;
        }

        return checksum;
    }

    private static void AssertDiagnosticShadowSuppressionLikeProduction(
        MethodInfo diagnosticShadowSuppressionIndicesInto,
        MethodInfo diagnosticShadowSuppressionChecksumInto)
    {
        var diagnostics = BuildDiagnosticShadowSuppressionDiagnostics();
        var shadowedFiles = new[] { "SRC/a.nl", "src/c.nl", "src/c.nl" };
        var expectedIndices = ExpectedDiagnosticShadowSuppressionIndices(diagnostics, shadowedFiles);
        var (codeIds, fileRanks, targetCodeId, shadowFileFlags) =
            BuildDiagnosticShadowSuppressionRanks(diagnostics, shadowedFiles);

        var actualIndices = new int[diagnostics.Count];
        var actualCount = (int)(diagnosticShadowSuppressionIndicesInto.Invoke(
            null,
            new object[] { codeIds, fileRanks, targetCodeId, shadowFileFlags, actualIndices }) ?? -1);

        Assert.Equal(expectedIndices.Length, actualCount);
        Assert.Equal(expectedIndices, actualIndices.Take(actualCount).ToArray());

        var checksumIndices = new int[diagnostics.Count];
        var actualChecksum = (int)(diagnosticShadowSuppressionChecksumInto.Invoke(
            null,
            new object[] { codeIds, fileRanks, targetCodeId, shadowFileFlags, checksumIndices }) ?? -1);
        var expectedChecksum = DiagnosticShadowSuppressionChecksum(expectedIndices, codeIds, fileRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedIndices, checksumIndices.Take(expectedIndices.Length).ToArray());

        var missingTargetIndices = new int[diagnostics.Count];
        var missingTargetCount = (int)(diagnosticShadowSuppressionIndicesInto.Invoke(
            null,
            new object[] { codeIds, fileRanks, 0, shadowFileFlags, missingTargetIndices }) ?? -1);

        Assert.Equal(diagnostics.Count, missingTargetCount);
        Assert.Equal(Enumerable.Range(0, diagnostics.Count), missingTargetIndices.Take(missingTargetCount));
    }

    private static List<DiagnosticResult> BuildDiagnosticShadowSuppressionDiagnostics()
    {
        return new List<DiagnosticResult>
        {
            BuildDiagnosticWithSeverity("warning", 1) with { Code = "NL020", File = "src/A.nl" },
            BuildDiagnosticWithSeverity("warning", 2) with { Code = "NL020", File = "src/B.nl" },
            BuildDiagnosticWithSeverity("warning", 3) with { Code = "NL021", File = "src/A.nl" },
            BuildDiagnosticWithSeverity("warning", 4) with { Code = "NL020", File = "src/c.nl" },
            BuildDiagnosticWithSeverity("warning", 5) with { Code = "NL0200", File = "src/c.nl" },
            BuildDiagnosticWithSeverity("warning", 6) with { Code = "NL020", File = "src/D.nl" },
            BuildDiagnosticWithSeverity("warning", 7) with { Code = "NL020", File = "SRC/A.NL" }
        };
    }

    private static int[] ExpectedDiagnosticShadowSuppressionIndices(
        IReadOnlyList<DiagnosticResult> diagnostics,
        IReadOnlyList<string> shadowedFiles)
    {
        var shadowedFileSet = shadowedFiles.ToHashSet(StringComparer.OrdinalIgnoreCase);
        return diagnostics
            .Select((diagnostic, index) => (diagnostic, index))
            .Where(item => item.diagnostic.Code != "NL020" || !shadowedFileSet.Contains(item.diagnostic.File))
            .Select(item => item.index)
            .ToArray();
    }

    private static (int[] CodeIds, int[] FileRanks, int TargetCodeId, int[] ShadowFileFlags)
        BuildDiagnosticShadowSuppressionRanks(
            IReadOnlyList<DiagnosticResult> diagnostics,
            IReadOnlyList<string> shadowedFiles)
    {
        var codeRanks = new Dictionary<string, int>(StringComparer.Ordinal);
        var fileRanks = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var uniqueFiles = new List<string>();

        int GetCodeId(string code)
        {
            if (codeRanks.TryGetValue(code, out var id))
                return id;

            id = codeRanks.Count + 1;
            codeRanks.Add(code, id);
            return id;
        }

        void AddFile(string file)
        {
            if (fileRanks.ContainsKey(file))
                return;

            fileRanks.Add(file, 0);
            uniqueFiles.Add(file);
        }

        var targetCodeId = GetCodeId("NL020");
        foreach (var diagnostic in diagnostics)
        {
            GetCodeId(diagnostic.Code);
            AddFile(diagnostic.File);
        }

        foreach (var shadowedFile in shadowedFiles)
        {
            AddFile(shadowedFile);
        }

        uniqueFiles.Sort(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < uniqueFiles.Count; i++)
        {
            fileRanks[uniqueFiles[i]] = i + 1;
        }

        var codeIds = diagnostics.Select(diagnostic => codeRanks[diagnostic.Code]).ToArray();
        var diagnosticFileRanks = diagnostics.Select(diagnostic => fileRanks[diagnostic.File]).ToArray();
        var shadowFileFlags = new int[uniqueFiles.Count + 1];
        foreach (var shadowedFile in shadowedFiles)
        {
            shadowFileFlags[fileRanks[shadowedFile]] = 1;
        }

        return (codeIds, diagnosticFileRanks, targetCodeId, shadowFileFlags);
    }

    private static int DiagnosticShadowSuppressionChecksum(
        int[] orderedIndices,
        int[] codeIds,
        int[] fileRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31 + codeIds[index] * 17 + fileRanks[index] * 13;
        }

        return checksum;
    }

    private static void AssertSymbolKindFilteringLikeProduction(
        MethodInfo symbolKindFilterIndicesInto,
        MethodInfo symbolKindFilterChecksumInto)
    {
        var symbols = BuildSymbolKindFilterSymbols();
        var kindIds = symbols.Select(static symbol => (int)symbol.Kind).ToArray();
        var targetKindId = (int)SymbolKind.Function;
        var expectedIndices = symbols
            .Select((symbol, index) => (symbol, index))
            .Where(item => item.symbol.Kind == SymbolKind.Function)
            .Select(item => item.index)
            .ToArray();

        var actualIndices = new int[symbols.Count];
        var actualCount = (int)(symbolKindFilterIndicesInto.Invoke(
            null,
            new object[] { kindIds, targetKindId, actualIndices }) ?? -1);

        Assert.Equal(expectedIndices.Length, actualCount);
        Assert.Equal(expectedIndices, actualIndices.Take(actualCount).ToArray());

        var checksumIndices = new int[symbols.Count];
        var actualChecksum = (int)(symbolKindFilterChecksumInto.Invoke(
            null,
            new object[] { kindIds, targetKindId, checksumIndices }) ?? -1);
        var expectedChecksum = SymbolKindFilterChecksum(expectedIndices, kindIds);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedIndices, checksumIndices.Take(expectedIndices.Length).ToArray());

        var missingIndices = new int[symbols.Count];
        var missingCount = (int)(symbolKindFilterIndicesInto.Invoke(
            null,
            new object[] { kindIds, 99, missingIndices }) ?? -1);

        Assert.Equal(0, missingCount);
    }

    private static int SymbolKindFilterChecksum(int[] orderedIndices, int[] kindIds)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31 + kindIds[index] * 17;
        }

        return checksum;
    }

    private static void AssertDiagnosticClusterTraitsLikeProduction(
        MethodInfo diagnosticClusterTraitsInto,
        MethodInfo diagnosticClusterTraitChecksumInto,
        MethodInfo diagnosticClusterTraitPatternChecksumInto,
        MethodInfo diagnosticClusterTraitsAndPatternsInto)
    {
        var diagnostics = BuildDiagnosticClusterTraitDiagnostics();
        var codes = diagnostics.Select(static diagnostic => diagnostic.Code).ToArray();
        var messages = diagnostics.Select(static diagnostic => diagnostic.Message).ToArray();
        var snippets = diagnostics.Select(static diagnostic => diagnostic.SourceSnippet ?? string.Empty).ToArray();
        var expectedCategories = new[] { 1, 0, 2, 3, 4, 5, 6, 7 };
        var expectedSourceConstructs = new[] { 1, 0, 4, 0, 2, 5, 7, 8 };
        var expectedPatterns = new[]
        {
            "Expected token {value} at line #",
            "Missing semicolon after {value}",
            "Circular import detected",
            "Undefined variable {value}",
            "Type not found {value}",
            "Type mismatch: expected Int##",
            "Member {value} does not exist",
            "unknown-message"
        };

        var checksumCategories = new int[diagnostics.Count];
        var checksumSourceConstructs = new int[diagnostics.Count];
        var actualChecksum = (int)(diagnosticClusterTraitChecksumInto.Invoke(
            null,
            new object[]
            {
                codes,
                messages,
                snippets,
                checksumCategories,
                checksumSourceConstructs
            }) ?? -1);

        var expectedChecksum = diagnostics.Count;
        for (var i = 0; i < diagnostics.Count; i++)
        {
            expectedChecksum += expectedCategories[i] * 31 + expectedSourceConstructs[i] * 17;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedCategories, checksumCategories);
        Assert.Equal(expectedSourceConstructs, checksumSourceConstructs);

        var actualCategories = new int[diagnostics.Count];
        var actualSourceConstructs = new int[diagnostics.Count];
        var actualTraitCount = (int)(diagnosticClusterTraitsInto.Invoke(
            null,
            new object[]
            {
                codes,
                messages,
                snippets,
                actualCategories,
                actualSourceConstructs
            }) ?? -1);

        Assert.Equal(diagnostics.Count, actualTraitCount);
        Assert.Equal(expectedCategories, actualCategories);
        Assert.Equal(expectedSourceConstructs, actualSourceConstructs);

        var patternChecksumCategories = new int[diagnostics.Count];
        var patternChecksumSourceConstructs = new int[diagnostics.Count];
        var patternChecksumPatterns = new string[diagnostics.Count];
        var actualPatternChecksum = (int)(diagnosticClusterTraitPatternChecksumInto.Invoke(
            null,
            new object[]
            {
                codes,
                messages,
                snippets,
                patternChecksumCategories,
                patternChecksumSourceConstructs,
                patternChecksumPatterns
            }) ?? -1);

        var expectedPatternChecksum = diagnostics.Count;
        for (var i = 0; i < diagnostics.Count; i++)
        {
            expectedPatternChecksum += expectedCategories[i] * 31 + expectedSourceConstructs[i] * 17 + expectedPatterns[i].Length;
        }

        Assert.Equal(expectedPatternChecksum, actualPatternChecksum);
        Assert.Equal(expectedCategories, patternChecksumCategories);
        Assert.Equal(expectedSourceConstructs, patternChecksumSourceConstructs);
        Assert.Equal(expectedPatterns, patternChecksumPatterns);

        var actualPatterns = new string[diagnostics.Count];
        var actualCount = (int)(diagnosticClusterTraitsAndPatternsInto.Invoke(
            null,
            new object[]
            {
                codes,
                messages,
                snippets,
                actualCategories,
                actualSourceConstructs,
                actualPatterns
            }) ?? -1);

        Assert.Equal(diagnostics.Count, actualCount);
        Assert.Equal(expectedCategories, actualCategories);
        Assert.Equal(expectedSourceConstructs, actualSourceConstructs);
        Assert.Equal(expectedPatterns, actualPatterns);
    }

    private static List<DiagnosticResult> BuildDiagnosticClusterTraitDiagnostics()
    {
        return new List<DiagnosticResult>
        {
            new(
                "NL102",
                "error",
                "Expected token '}' at line 7",
                "Program.nl",
                1,
                1,
                1,
                "static func Run() {",
                null,
                null,
                null,
                null,
                null,
                null),
            new(
                "NL102",
                "error",
                "Missing semicolon after \"value\"",
                "Program.nl",
                2,
                5,
                1,
                "let value = 1",
                null,
                null,
                null,
                null,
                null,
                null),
            new(
                "NL703",
                "error",
                "Circular import detected",
                "Imports.nl",
                1,
                1,
                1,
                "import Foo",
                null,
                null,
                null,
                null,
                null,
                null),
            new(
                "NL301",
                "error",
                "Undefined variable 'foo'",
                "Program.nl",
                3,
                14,
                7,
                "    value := foo",
                null,
                null,
                null,
                null,
                null,
                null),
            new(
                "NL201",
                "error",
                "Type not found 'Widget'",
                "Models.nl",
                1,
                7,
                6,
                "class Person {",
                null,
                null,
                null,
                null,
                null,
                null),
            new(
                "NL202",
                "error",
                "Type mismatch: expected Int32",
                "Program.nl",
                4,
                12,
                5,
                "return value",
                null,
                null,
                null,
                "Int32",
                "string",
                null),
            new(
                "NL303",
                "error",
                "Member 'Absent' does not exist",
                "Program.nl",
                5,
                14,
                7,
                "customer.Name()",
                null,
                null,
                null,
                null,
                null,
                null),
            new(
                "NL999",
                "warning",
                "   ",
                "Program.nl",
                6,
                1,
                1,
                "   ",
                null,
                null,
                null,
                null,
                null,
                null)
        };
    }

    private static void AssertDiagnosticClusterIdsLikeProduction(
        MethodInfo diagnosticClusterIdsInto,
        MethodInfo diagnosticClusterIdChecksumInto)
    {
        var codes = new[] { "NL102", "NL703", "NL301", "NL202" };
        var severities = new[] { "error", "error", "warning", "error" };
        var categories = new[]
        {
            "syntax-missing-delimiter",
            "import-cycle",
            "identifier-resolution",
            "type-mismatch"
        };
        var sourceConstructs = new[]
        {
            "function-declaration",
            "import",
            "variable-declaration",
            "return-statement"
        };
        var recipes = new[]
        {
            "syntax:delimiter-balancing",
            "architecture:extract-shared-module-or-invert-dependency",
            "symbols:missing-import-or-qualification",
            "refactor:signature-or-expression-shape"
        };
        var messagePatterns = new[]
        {
            "Expected token {value} at line #",
            "Circular import detected",
            "Undefined variable {value}",
            "Type mismatch: expected Int##"
        };
        var expectedIds = Enumerable.Range(0, codes.Length)
            .Select(i => CreateExpectedDiagnosticClusterId(
                codes[i],
                severities[i],
                categories[i],
                sourceConstructs[i],
                recipes[i],
                messagePatterns[i]))
            .ToArray();

        var checksumIds = new string[codes.Length];
        var actualChecksum = (int)(diagnosticClusterIdChecksumInto.Invoke(
            null,
            new object[]
            {
                codes,
                severities,
                categories,
                sourceConstructs,
                recipes,
                messagePatterns,
                checksumIds
            }) ?? -1);

        var expectedChecksum = codes.Length;
        foreach (var id in expectedIds)
        {
            expectedChecksum += id.Length * 31;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedIds, checksumIds);

        var actualIds = new string[codes.Length];
        var actualCount = (int)(diagnosticClusterIdsInto.Invoke(
            null,
            new object[]
            {
                codes,
                severities,
                categories,
                sourceConstructs,
                recipes,
                messagePatterns,
                actualIds
            }) ?? -1);

        Assert.Equal(codes.Length, actualCount);
        Assert.Equal(expectedIds, actualIds);
    }

    private static string CreateExpectedDiagnosticClusterId(
        string code,
        string severity,
        string category,
        string sourceConstruct,
        string recipe,
        string messagePattern)
    {
        var key = $"{code}|{severity}|{category}|{sourceConstruct}|{recipe}|{messagePattern}";
        var hash = 17;
        foreach (var c in key)
        {
            hash = (hash * 31) + c;
        }

        return $"diag-{Math.Abs(hash):x}";
    }

    private static void AssertDiagnosticClusterNextCommandsLikeProduction(
        MethodInfo diagnosticClusterNextCommandsInto,
        MethodInfo diagnosticClusterNextCommandChecksumInto)
    {
        var files = new[]
        {
            "/repo/src/Main.nl",
            "/repo/src/Has Space.nl",
            """C:\repo\quoted"name.nl""",
            "   ",
            "/repo/src/café.nl"
        };
        var lines = new[] { 12, 3, 44, 1, 9 };
        var columns = new[] { 8, 1, 17, 1, 5 };
        var expectedCommands = Enumerable.Range(0, files.Length)
            .Select(i => CreateExpectedDiagnosticClusterNextCommand(files[i], lines[i], columns[i]))
            .ToArray();

        var checksumCommands = new string[files.Length];
        var actualChecksum = (int)(diagnosticClusterNextCommandChecksumInto.Invoke(
            null,
            new object[] { files, lines, columns, checksumCommands }) ?? -1);

        var expectedChecksum = files.Length;
        foreach (var command in expectedCommands)
        {
            expectedChecksum += command.Length * 31;
        }

        Assert.Equal(expectedCommands, checksumCommands);
        Assert.Equal(expectedChecksum, actualChecksum);

        var actualCommands = new string[files.Length];
        var actualCount = (int)(diagnosticClusterNextCommandsInto.Invoke(
            null,
            new object[] { files, lines, columns, actualCommands }) ?? -1);

        Assert.Equal(files.Length, actualCount);
        Assert.Equal(expectedCommands, actualCommands);
    }

    private static string CreateExpectedDiagnosticClusterNextCommand(string file, int line, int column)
    {
        return $"nlc query inspect --file {EscapeExpectedCommandArgument(file)} --pos {line}:{column}";
    }

    private static string EscapeExpectedCommandArgument(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return "\"\"";

        if (value.All(c => char.IsLetterOrDigit(c) || c is '/' or '.' or '_' or '-'))
            return value;

        return $"\"{value.Replace("\\", "\\\\").Replace("\"", "\\\"")}\"";
    }

    private static void AssertDiagnosticClusterGroupsLikeProduction(
        MethodInfo diagnosticClusterGroupsInto,
        MethodInfo diagnosticClusterGroupChecksumInto,
        MethodInfo diagnosticClusterGroupMembersInto,
        MethodInfo diagnosticClusterGroupMemberChecksumInto)
    {
        var codes = new[] { "NL102", "NL301", "NL102", "NL703", "NL301", "NL102", "NL102" };
        var codeIds = new[] { 102, 301, 102, 703, 301, 102, 102 };
        var severities = new[] { "error", "warning", "error", "error", "warning", "error", "error" };
        var severityIds = new[] { 1, 2, 1, 1, 2, 1, 1 };
        var categories = new[]
        {
            "syntax-missing-delimiter",
            "identifier-resolution",
            "syntax-missing-delimiter",
            "import-cycle",
            "identifier-resolution",
            "syntax-missing-delimiter",
            "syntax-missing-delimiter"
        };
        var categoryIds = new[] { 1, 2, 1, 3, 2, 1, 1 };
        var sourceConstructs = new[]
        {
            "function-declaration",
            "variable-declaration",
            "function-declaration",
            "import",
            "variable-declaration",
            "function-declaration",
            "function-declaration"
        };
        var sourceConstructIds = new[] { 1, 2, 1, 3, 2, 1, 1 };
        var recipes = new[]
        {
            "syntax:delimiter-balancing",
            "symbols:missing-import-or-qualification",
            "syntax:delimiter-balancing",
            "architecture:extract-shared-module-or-invert-dependency",
            "symbols:missing-import-or-qualification",
            "syntax:delimiter-balancing",
            "syntax:delimiter-balancing"
        };
        var recipeIds = new[] { 1, 2, 1, 3, 2, 1, 1 };
        var risks = new[] { "high", "medium", "high", "high", "medium", "high", "high" };
        var riskIds = new[] { 1, 2, 1, 1, 2, 1, 1 };
        var messagePatterns = new[]
        {
            "Expected token {value}",
            "Undefined variable {value}",
            "Expected token {value}",
            "Circular import detected",
            "Undefined variable {value}",
            "Expected token {value}",
            "Expected token {value}"
        };
        var messagePatternIds = new[] { 1, 2, 1, 3, 2, 1, 1 };
        var files = new[]
        {
            "/repo/B.nl",
            "/repo/C.nl",
            "/repo/A.nl",
            "/repo/Imports.nl",
            "/repo/C.nl",
            "/repo/D.nl",
            "/repo/a.nl"
        };
        var lines = new[] { 10, 3, 10, 1, 2, 8, 10 };
        var columns = new[] { 5, 7, 3, 1, 9, 1, 2 };
        var expected = CreateExpectedDiagnosticClusterGroups(
            codes,
            severities,
            categories,
            sourceConstructs,
            recipes,
            risks,
            messagePatterns,
            files,
            lines,
            columns);

        var checksumRootIndices = new int[codes.Length];
        var checksumCounts = new int[codes.Length];
        var checksumSlotGroups = new int[codes.Length * 2 + 1];
        var checksumGroupKeyIndices = new int[codes.Length];
        var actualChecksum = (int)(diagnosticClusterGroupChecksumInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                severityIds,
                categoryIds,
                sourceConstructIds,
                recipeIds,
                riskIds,
                messagePatternIds,
                files,
                lines,
                columns,
                checksumSlotGroups,
                checksumGroupKeyIndices,
                checksumRootIndices,
                checksumCounts
            }) ?? -1);

        var expectedChecksum = expected.RootIndices.Length;
        for (var i = 0; i < expected.RootIndices.Length; i++)
        {
            expectedChecksum += (expected.RootIndices[i] + 1) * 31 + expected.Counts[i] * 17;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected.RootIndices, checksumRootIndices.Take(expected.RootIndices.Length));
        Assert.Equal(expected.Counts, checksumCounts.Take(expected.Counts.Length));

        var actualRootIndices = new int[codes.Length];
        var actualCounts = new int[codes.Length];
        var actualSlotGroups = new int[codes.Length * 2 + 1];
        var actualGroupKeyIndices = new int[codes.Length];
        var actualCount = (int)(diagnosticClusterGroupsInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                severityIds,
                categoryIds,
                sourceConstructIds,
                recipeIds,
                riskIds,
                messagePatternIds,
                files,
                lines,
                columns,
                actualSlotGroups,
                actualGroupKeyIndices,
                actualRootIndices,
                actualCounts
            }) ?? -1);

        Assert.Equal(expected.RootIndices.Length, actualCount);
        Assert.Equal(expected.RootIndices, actualRootIndices.Take(actualCount));
        Assert.Equal(expected.Counts, actualCounts.Take(actualCount));

        var checksumMemberStarts = new int[codes.Length];
        var checksumMemberIndices = new int[codes.Length];
        var checksumMemberSlotGroups = new int[codes.Length * 2 + 1];
        var checksumGroupFirstMemberIndices = new int[codes.Length];
        var checksumMemberNextIndices = new int[codes.Length];
        var actualMemberChecksum = (int)(diagnosticClusterGroupMemberChecksumInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                severityIds,
                categoryIds,
                sourceConstructIds,
                recipeIds,
                riskIds,
                messagePatternIds,
                files,
                lines,
                columns,
                expected.RootIndices,
                expected.Counts,
                expected.RootIndices.Length,
                checksumMemberSlotGroups,
                checksumGroupFirstMemberIndices,
                checksumMemberNextIndices,
                checksumMemberStarts,
                checksumMemberIndices
            }) ?? -1);

        var expectedMemberChecksum = expected.MemberIndices.Length;
        for (var i = 0; i < expected.RootIndices.Length; i++)
        {
            expectedMemberChecksum += (expected.MemberStarts[i] + 1) * 31 + expected.Counts[i] * 17;
        }

        foreach (var index in expected.MemberIndices)
        {
            expectedMemberChecksum += (index + 1) * 13 + lines[index] * 7 + columns[index] * 5;
        }

        Assert.Equal(expectedMemberChecksum, actualMemberChecksum);
        Assert.Equal(expected.MemberStarts, checksumMemberStarts.Take(expected.MemberStarts.Length));
        Assert.Equal(expected.MemberIndices, checksumMemberIndices.Take(expected.MemberIndices.Length));

        var actualMemberStarts = new int[codes.Length];
        var actualMemberIndices = new int[codes.Length];
        var actualMemberSlotGroups = new int[codes.Length * 2 + 1];
        var actualGroupFirstMemberIndices = new int[codes.Length];
        var actualMemberNextIndices = new int[codes.Length];
        var actualMemberCount = (int)(diagnosticClusterGroupMembersInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                severityIds,
                categoryIds,
                sourceConstructIds,
                recipeIds,
                riskIds,
                messagePatternIds,
                files,
                lines,
                columns,
                actualRootIndices,
                actualCounts,
                actualCount,
                actualMemberSlotGroups,
                actualGroupFirstMemberIndices,
                actualMemberNextIndices,
                actualMemberStarts,
                actualMemberIndices
            }) ?? -1);

        Assert.Equal(expected.MemberIndices.Length, actualMemberCount);
        Assert.Equal(expected.MemberStarts, actualMemberStarts.Take(expected.MemberStarts.Length));
        Assert.Equal(expected.MemberIndices, actualMemberIndices.Take(expected.MemberIndices.Length));
    }

    private static (int[] RootIndices, int[] Counts, int[] MemberStarts, int[] MemberIndices) CreateExpectedDiagnosticClusterGroups(
        string[] codes,
        string[] severities,
        string[] categories,
        string[] sourceConstructs,
        string[] recipes,
        string[] risks,
        string[] messagePatterns,
        string[] files,
        int[] lines,
        int[] columns)
    {
        var groups = Enumerable.Range(0, codes.Length)
            .GroupBy(i => new
            {
                Severity = severities[i],
                Code = codes[i],
                Category = categories[i],
                SourceConstruct = sourceConstructs[i],
                Recipe = recipes[i],
                Risk = risks[i],
                MessagePattern = messagePatterns[i]
            })
            .Select(group =>
            {
                var members = group
                    .OrderBy(i => lines[i])
                    .ThenBy(i => columns[i])
                    .ThenBy(i => files[i], StringComparer.OrdinalIgnoreCase)
                    .ToArray();
                return new
                {
                    RootIndex = members[0],
                    Count = members.Length,
                    Members = members
                };
            })
            .OrderByDescending(group => group.Count)
            .ThenBy(group => files[group.RootIndex], StringComparer.OrdinalIgnoreCase)
            .ThenBy(group => lines[group.RootIndex])
            .ThenBy(group => columns[group.RootIndex])
            .ToArray();

        var memberStarts = new int[groups.Length];
        var memberIndices = new List<int>(codes.Length);
        for (var i = 0; i < groups.Length; i++)
        {
            memberStarts[i] = memberIndices.Count;
            memberIndices.AddRange(groups[i].Members);
        }

        return (
            groups.Select(static group => group.RootIndex).ToArray(),
            groups.Select(static group => group.Count).ToArray(),
            memberStarts,
            memberIndices.ToArray());
    }

    private static void AssertDiagnosticDeduplicationLikeProduction(
        MethodInfo diagnosticDeduplicateCompactInto,
        MethodInfo diagnosticDeduplicateCompactChecksumInto,
        MethodInfo diagnosticDeduplicateStableInto,
        MethodInfo diagnosticDeduplicateStableChecksumInto)
    {
        var codes = new[] { "NL102", "NL301", "NL102", "NL201", "NL301", "NL302" };
        var files = new[] { "B.nl", "A.nl", "B.nl", "A.nl", "A.nl", "A.nl" };
        var lines = new[] { 10, 2, 10, 2, 2, 2 };
        var columns = new[] { 5, 3, 5, 1, 3, 3 };
        var messages = new[]
        {
            "Expected token '}'",
            "Undefined variable 'value'",
            "Expected token '}'",
            "Type is inferred",
            "Undefined variable 'value'",
            "Different diagnostic at same location"
        };
        var codeIds = CreateOrdinalIds(codes);
        var fileRanks = CreateSortedFileRanks(files);
        var fileIds = CreateOrdinalIds(files);
        var messageIds = CreateOrdinalIds(messages);
        var expected = CreateExpectedDiagnosticDeduplication(codes, files, lines, columns, messages);
        var expectedStable = CreateExpectedStableDiagnosticDeduplication(codes, files, lines, columns, messages);

        var checksumSlotIndices = new int[codes.Length * 2 + 1];
        var checksumResultIndices = new int[codes.Length];
        var actualChecksum = (int)(diagnosticDeduplicateCompactChecksumInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                fileRanks,
                lines,
                columns,
                messageIds,
                checksumSlotIndices,
                checksumResultIndices
            }) ?? -1);

        var expectedChecksum = expected.Length;
        for (var i = 0; i < expected.Length; i++)
        {
            var index = expected[i];
            expectedChecksum += (index + 1) * 31 + lines[index] * 17 + columns[index] * 13;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length));

        var slotIndices = new int[codes.Length * 2 + 1];
        var resultIndices = new int[codes.Length];
        var actualCount = (int)(diagnosticDeduplicateCompactInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                fileRanks,
                lines,
                columns,
                messageIds,
                slotIndices,
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount));

        var stableChecksumSlotIndices = new int[codes.Length * 2 + 1];
        var stableChecksumResultIndices = new int[codes.Length];
        var actualStableChecksum = (int)(diagnosticDeduplicateStableChecksumInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                fileIds,
                lines,
                columns,
                messageIds,
                stableChecksumSlotIndices,
                stableChecksumResultIndices
            }) ?? -1);

        var expectedStableChecksum = expectedStable.Length;
        for (var i = 0; i < expectedStable.Length; i++)
        {
            var index = expectedStable[i];
            expectedStableChecksum += (index + 1) * 31 + lines[index] * 17 + columns[index] * 13;
        }

        Assert.Equal(expectedStableChecksum, actualStableChecksum);
        Assert.Equal(expectedStable, stableChecksumResultIndices.Take(expectedStable.Length));

        var stableSlotIndices = new int[codes.Length * 2 + 1];
        var stableResultIndices = new int[codes.Length];
        var actualStableCount = (int)(diagnosticDeduplicateStableInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                fileIds,
                lines,
                columns,
                messageIds,
                stableSlotIndices,
                stableResultIndices
            }) ?? -1);

        Assert.Equal(expectedStable.Length, actualStableCount);
        Assert.Equal(expectedStable, stableResultIndices.Take(actualStableCount));
    }

    private static int[] CreateExpectedDiagnosticDeduplication(
        string[] codes,
        string[] files,
        int[] lines,
        int[] columns,
        string[] messages)
    {
        return Enumerable.Range(0, codes.Length)
            .GroupBy(i => (codes[i], files[i], lines[i], columns[i], messages[i]))
            .Select(group => group.First())
            .OrderBy(i => files[i])
            .ThenBy(i => lines[i])
            .ThenBy(i => columns[i])
            .ToArray();
    }

    private static int[] CreateExpectedStableDiagnosticDeduplication(
        string[] codes,
        string[] files,
        int[] lines,
        int[] columns,
        string[] messages)
    {
        return Enumerable.Range(0, codes.Length)
            .GroupBy(i => (codes[i], files[i], lines[i], columns[i], messages[i]))
            .Select(group => group.First())
            .ToArray();
    }

    private static void AssertFormatterSafetyScanLikeProduction(
        MethodInfo formatterSafetyHasError,
        MethodInfo formatterSafetyErrorIndicesInto,
        MethodInfo formatterSafetyErrorIndicesChecksumInto)
    {
        // Severity encoding mirrors ErrorSeverity: Warning = 0, Error = 1. The production
        // FormatSafe gate is Errors.Any(e => e.Severity == ErrorSeverity.Error), and the
        // failure path collects error-severity entries for the message join.
        AssertFormatterSafetyScanCase(
            formatterSafetyHasError,
            formatterSafetyErrorIndicesInto,
            formatterSafetyErrorIndicesChecksumInto,
            Array.Empty<int>());
        AssertFormatterSafetyScanCase(
            formatterSafetyHasError,
            formatterSafetyErrorIndicesInto,
            formatterSafetyErrorIndicesChecksumInto,
            new[] { 0, 0, 0 });
        AssertFormatterSafetyScanCase(
            formatterSafetyHasError,
            formatterSafetyErrorIndicesInto,
            formatterSafetyErrorIndicesChecksumInto,
            new[] { 1, 0, 1, 0, 1 });
        AssertFormatterSafetyScanCase(
            formatterSafetyHasError,
            formatterSafetyErrorIndicesInto,
            formatterSafetyErrorIndicesChecksumInto,
            new[] { 0, 1, 0, 0, 1, 0, 0 });
        AssertFormatterSafetyScanCase(
            formatterSafetyHasError,
            formatterSafetyErrorIndicesInto,
            formatterSafetyErrorIndicesChecksumInto,
            new[] { 1, 1, 1, 1 });
    }

    private static void AssertFormatterSafetyScanCase(
        MethodInfo formatterSafetyHasError,
        MethodInfo formatterSafetyErrorIndicesInto,
        MethodInfo formatterSafetyErrorIndicesChecksumInto,
        int[] severities)
    {
        var expectedHasError = severities.Any(severity => severity == 1);
        var actualHasError = (bool)(formatterSafetyHasError.Invoke(
            null,
            new object[] { severities }) ?? false);
        Assert.Equal(expectedHasError, actualHasError);

        var expectedIndices = Enumerable.Range(0, severities.Length)
            .Where(i => severities[i] == 1)
            .ToArray();

        var resultIndices = new int[Math.Max(severities.Length, 1)];
        var actualCount = (int)(formatterSafetyErrorIndicesInto.Invoke(
            null,
            new object[] { severities, resultIndices }) ?? -1);
        Assert.Equal(expectedIndices.Length, actualCount);
        Assert.Equal(expectedIndices, resultIndices.Take(actualCount));

        var checksumResultIndices = new int[Math.Max(severities.Length, 1)];
        var actualChecksum = (int)(formatterSafetyErrorIndicesChecksumInto.Invoke(
            null,
            new object[] { severities, checksumResultIndices }) ?? -1);

        var expectedChecksum = expectedIndices.Length;
        for (var i = 0; i < expectedIndices.Length; i++)
        {
            var index = expectedIndices[i];
            expectedChecksum += (index + 1) * 31 + (i + 1) * 13;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedIndices, checksumResultIndices.Take(expectedIndices.Length));
    }

    private static void AssertReferenceDeduplicationLikeProduction(
        MethodInfo referenceDeduplicateCompactInto,
        MethodInfo referenceDeduplicateCompactChecksumInto)
    {
        var files = new[] { "B.nl", "A.nl", "B.nl", "A.nl", "A.nl", "C.nl" };
        var lines = new[] { 10, 2, 10, 2, 2, 1 };
        var columns = new[] { 5, 3, 5, 1, 3, 1 };
        var fileRanks = CreateSortedFileRanks(files);
        var expected = CreateExpectedReferenceDeduplication(files, lines, columns);

        var checksumSlotIndices = new int[files.Length * 2 + 1];
        var checksumResultIndices = new int[files.Length];
        var actualChecksum = (int)(referenceDeduplicateCompactChecksumInto.Invoke(
            null,
            new object[]
            {
                fileRanks,
                lines,
                columns,
                checksumSlotIndices,
                checksumResultIndices
            }) ?? -1);

        var expectedChecksum = expected.Length;
        for (var i = 0; i < expected.Length; i++)
        {
            var index = expected[i];
            expectedChecksum += (index + 1) * 31 + lines[index] * 17 + columns[index] * 13;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length));

        var slotIndices = new int[files.Length * 2 + 1];
        var resultIndices = new int[files.Length];
        var actualCount = (int)(referenceDeduplicateCompactInto.Invoke(
            null,
            new object[]
            {
                fileRanks,
                lines,
                columns,
                slotIndices,
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount));
    }

    private static int[] CreateExpectedReferenceDeduplication(
        string[] files,
        int[] lines,
        int[] columns)
    {
        return Enumerable.Range(0, files.Length)
            .GroupBy(i => (files[i], lines[i], columns[i]))
            .Select(group => group.First())
            .OrderBy(i => files[i])
            .ThenBy(i => lines[i])
            .ThenBy(i => columns[i])
            .ToArray();
    }

    private static void AssertReferenceFileSummaryLikeProduction(
        MethodInfo referenceFileSummaryRanksInto,
        MethodInfo referenceFileSummaryChecksumInto)
    {
        var files = new[]
        {
            @"src\B.nl",
            "src/A.nl",
            "src/B.nl",
            @"src\C.nl",
            "src/A.nl",
            "src/[weird]/File.nl",
            @"src\zeta\File.nl",
            "src/zeta/File.nl"
        };
        var normalizedFiles = files.Select(file => file.Replace('\\', '/')).ToArray();
        var uniqueFiles = normalizedFiles
            .Distinct(StringComparer.Ordinal)
            .OrderBy(file => file, StringComparer.Ordinal)
            .ToArray();
        var ranksByFile = uniqueFiles
            .Select((file, index) => (file, rank: index + 1))
            .ToDictionary(item => item.file, item => item.rank, StringComparer.Ordinal);
        var fileRanks = normalizedFiles.Select(file => ranksByFile[file]).ToArray();
        var fileLengthsByRank = new int[uniqueFiles.Length + 1];
        for (var i = 0; i < uniqueFiles.Length; i++)
        {
            fileLengthsByRank[i + 1] = uniqueFiles[i].Length;
        }

        var expectedRanks = Enumerable.Range(1, uniqueFiles.Length).ToArray();
        var expectedChecksum = expectedRanks.Length;
        for (var i = 0; i < expectedRanks.Length; i++)
        {
            var rank = expectedRanks[i];
            expectedChecksum += rank * 31 + fileLengthsByRank[rank] * 17 + (i + 1) * 13;
        }

        var checksumCountsByRank = new int[uniqueFiles.Length + 1];
        var checksumResultRanks = new int[files.Length];
        var actualChecksum = (int)(referenceFileSummaryChecksumInto.Invoke(
            null,
            new object[] { fileRanks, uniqueFiles.Length, checksumCountsByRank, checksumResultRanks, fileLengthsByRank }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedRanks, checksumResultRanks.Take(expectedRanks.Length));

        var countsByRank = new int[uniqueFiles.Length + 1];
        var resultRanks = new int[files.Length];
        var actualCount = (int)(referenceFileSummaryRanksInto.Invoke(
            null,
            new object[] { fileRanks, uniqueFiles.Length, countsByRank, resultRanks }) ?? -1);

        Assert.Equal(expectedRanks.Length, actualCount);
        Assert.Equal(expectedRanks, resultRanks.Take(actualCount));
    }

    private static void AssertBindingLookupLikeProduction(
        MethodInfo bindingLookupCandidateColumnsInto,
        MethodInfo bindingLookupCandidateColumnChecksumInto,
        MethodInfo bindingLookupBuildSlotsInto,
        MethodInfo bindingLookupQueryDeclarationIndicesInto,
        MethodInfo bindingLookupQueryChecksumInto,
        MethodInfo bindingLookupBuildNearestDeclarationIndexInto,
        MethodInfo bindingLookupBuildNearestDeclarationIndexChecksumInto,
        MethodInfo bindingLookupFindNearestDeclarationIndicesInto,
        MethodInfo bindingLookupFindNearestDeclarationChecksumInto)
    {
        var candidateQueryColumns = new[] { 5, 1, 0, -3, 10, 1000 };
        var candidateSpanStarts = new[] { 3, -1, 1, -1, 8, 3 };
        var candidateSpanEnds = new[] { 7, -1, 1, -1, 12, 5 };
        var expectedCandidateColumns = BuildExpectedBindingCandidateColumns(
            candidateQueryColumns,
            candidateSpanStarts,
            candidateSpanEnds);
        var expectedCandidateStarts = new int[candidateQueryColumns.Length];
        var expectedCandidateCounts = new int[candidateQueryColumns.Length];
        var expectedFlatCandidateColumns = FlattenExpectedBindingCandidateColumns(
            expectedCandidateColumns,
            expectedCandidateStarts,
            expectedCandidateCounts);

        var candidateStarts = new int[candidateQueryColumns.Length];
        var candidateCounts = new int[candidateQueryColumns.Length];
        var candidateColumns = new int[expectedFlatCandidateColumns.Length];
        var actualCandidateTotal = (int)(bindingLookupCandidateColumnsInto.Invoke(
            null,
            new object[]
            {
                candidateQueryColumns,
                candidateSpanStarts,
                candidateSpanEnds,
                candidateStarts,
                candidateCounts,
                candidateColumns
            }) ?? -1);

        Assert.Equal(expectedFlatCandidateColumns.Length, actualCandidateTotal);
        Assert.Equal(expectedCandidateStarts, candidateStarts);
        Assert.Equal(expectedCandidateCounts, candidateCounts);
        Assert.Equal(expectedFlatCandidateColumns, candidateColumns);

        var checksumStarts = new int[candidateQueryColumns.Length];
        var checksumCounts = new int[candidateQueryColumns.Length];
        var checksumColumns = new int[expectedFlatCandidateColumns.Length];
        var actualCandidateChecksum = (int)(bindingLookupCandidateColumnChecksumInto.Invoke(
            null,
            new object[]
            {
                candidateQueryColumns,
                candidateSpanStarts,
                candidateSpanEnds,
                checksumStarts,
                checksumCounts,
                checksumColumns
            }) ?? -1);
        var expectedCandidateChecksum = CandidateColumnChecksum(
            expectedFlatCandidateColumns.Length,
            expectedCandidateStarts,
            expectedCandidateCounts,
            expectedFlatCandidateColumns);

        Assert.Equal(expectedCandidateChecksum, actualCandidateChecksum);
        Assert.Equal(expectedCandidateStarts, checksumStarts);
        Assert.Equal(expectedCandidateCounts, checksumCounts);
        Assert.Equal(expectedFlatCandidateColumns, checksumColumns);

        var declarationFileRanks = new[] { 2, 1, 3 };
        var declarationLines = new[] { 10, 2, 1 };
        var declarationColumns = new[] { 5, 3, 1 };
        var declarationNameLengths = new[] { 6, 6, 6 };
        var declarationSlots = new int[declarationFileRanks.Length * 2 + 1];

        var bindingFileRanks = new[] { 1, 2, 1 };
        var bindingLines = new[] { 7, 12, 2 };
        var bindingColumns = new[] { 9, 4, 3 };
        var bindingDeclarationIndices = new[] { 0, 2, 0 };
        var bindingSlots = new int[bindingFileRanks.Length * 2 + 1];

        Assert.Equal(declarationFileRanks.Length, (int)(bindingLookupBuildSlotsInto.Invoke(
            null,
            new object[] { declarationFileRanks, declarationLines, declarationColumns, declarationSlots }) ?? -1));
        Assert.Equal(bindingFileRanks.Length, (int)(bindingLookupBuildSlotsInto.Invoke(
            null,
            new object[] { bindingFileRanks, bindingLines, bindingColumns, bindingSlots }) ?? -1));

        var queryFileRanks = new[] { 1, 1, 2, 3 };
        var queryLines = new[] { 2, 7, 12, 99 };
        var queryColumns = new[] { 3, 9, 4, 1 };
        var expected = new[] { 1, 0, 2, -1 };

        var resultIndices = new int[queryFileRanks.Length];
        var actualCount = (int)(bindingLookupQueryDeclarationIndicesInto.Invoke(
            null,
            new object[]
            {
                declarationFileRanks,
                declarationLines,
                declarationColumns,
                declarationSlots,
                bindingFileRanks,
                bindingLines,
                bindingColumns,
                bindingDeclarationIndices,
                bindingSlots,
                queryFileRanks,
                queryLines,
                queryColumns,
                resultIndices
            }) ?? -1);

        Assert.Equal(3, actualCount);
        Assert.Equal(expected, resultIndices);

        var checksumResultIndices = new int[queryFileRanks.Length];
        var actualChecksum = (int)(bindingLookupQueryChecksumInto.Invoke(
            null,
            new object[]
            {
                declarationFileRanks,
                declarationLines,
                declarationColumns,
                declarationNameLengths,
                declarationSlots,
                bindingFileRanks,
                bindingLines,
                bindingColumns,
                bindingDeclarationIndices,
                bindingSlots,
                queryFileRanks,
                queryLines,
                queryColumns,
                checksumResultIndices
            }) ?? -1);

        var expectedChecksum = 3;
        foreach (var declarationIndex in expected.Where(index => index >= 0))
        {
            expectedChecksum += declarationLines[declarationIndex] * 31
                + declarationColumns[declarationIndex] * 17
                + declarationNameLengths[declarationIndex] * 13;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices);

        var unsortedNameIds = new[] { 2, 1, 1, 1, 1 };
        var unsortedFileRanks = new[] { 1, 1, 1, 1, 2 };
        var unsortedLines = new[] { 3, 2, 8, 8, 10 };
        var unsortedColumns = new[] { 1, 3, 1, 4, 1 };
        var expectedSortOrder = new[] { 1, 2, 3, 4, 0 };
        var builtNameIds = new int[unsortedNameIds.Length];
        var builtFileRanks = new int[unsortedNameIds.Length];
        var builtLines = new int[unsortedNameIds.Length];
        var builtColumns = new int[unsortedNameIds.Length];
        var builtDeclarationIndices = new int[unsortedNameIds.Length];
        var buildCount = (int)(bindingLookupBuildNearestDeclarationIndexInto.Invoke(
            null,
            new object[]
            {
                unsortedNameIds,
                unsortedFileRanks,
                unsortedLines,
                unsortedColumns,
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length],
                builtNameIds,
                builtFileRanks,
                builtLines,
                builtColumns,
                builtDeclarationIndices
            }) ?? -1);

        Assert.Equal(unsortedNameIds.Length, buildCount);
        Assert.Equal(expectedSortOrder, builtDeclarationIndices);
        Assert.Equal(expectedSortOrder.Select(index => unsortedNameIds[index]).ToArray(), builtNameIds);
        Assert.Equal(expectedSortOrder.Select(index => unsortedFileRanks[index]).ToArray(), builtFileRanks);
        Assert.Equal(expectedSortOrder.Select(index => unsortedLines[index]).ToArray(), builtLines);
        Assert.Equal(expectedSortOrder.Select(index => unsortedColumns[index]).ToArray(), builtColumns);

        var buildChecksum = (int)(bindingLookupBuildNearestDeclarationIndexChecksumInto.Invoke(
            null,
            new object[]
            {
                unsortedNameIds,
                unsortedFileRanks,
                unsortedLines,
                unsortedColumns,
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length]
            }) ?? -1);
        var expectedBuildChecksum = unsortedNameIds.Length * 17;
        for (var i = 0; i < expectedSortOrder.Length; i++)
        {
            var declarationIndex = expectedSortOrder[i];
            expectedBuildChecksum += (i + 1) * 97
                + unsortedNameIds[declarationIndex] * 31
                + unsortedFileRanks[declarationIndex] * 23
                + unsortedLines[declarationIndex] * 13
                + unsortedColumns[declarationIndex] * 7
                + declarationIndex * 3;
        }

        Assert.Equal(expectedBuildChecksum, buildChecksum);

        var uniqueNameIds = new[] { 1, 2, 3 };
        var uniqueFileRanks = new[] { 1, 1, 1 };
        var uniqueLines = new[] { 1, 2, 3 };
        var uniqueColumns = new[] { 1, 1, 1 };
        var uniqueBuiltIndices = new int[uniqueNameIds.Length];
        var uniqueBuildCount = (int)(bindingLookupBuildNearestDeclarationIndexInto.Invoke(
            null,
            new object[]
            {
                uniqueNameIds,
                uniqueFileRanks,
                uniqueLines,
                uniqueColumns,
                new int[uniqueNameIds.Length + 1],
                new int[uniqueNameIds.Length + 1],
                new int[uniqueNameIds.Length],
                new int[uniqueNameIds.Length],
                new int[uniqueNameIds.Length],
                new int[uniqueNameIds.Length],
                uniqueBuiltIndices
            }) ?? -1);

        Assert.Equal(uniqueNameIds.Length, uniqueBuildCount);
        Assert.Equal(new[] { 0, 1, 2 }, uniqueBuiltIndices);

        var outOfOrderBuildCount = (int)(bindingLookupBuildNearestDeclarationIndexInto.Invoke(
            null,
            new object[]
            {
                new[] { 1, 1 },
                new[] { 1, 1 },
                new[] { 8, 2 },
                new[] { 1, 1 },
                new int[2],
                new int[2],
                new int[2],
                new int[2],
                new int[2],
                new int[2],
                new int[2]
            }) ?? -2);

        Assert.Equal(-1, outOfOrderBuildCount);

        var sortedNameIds = new[] { 1, 1, 1, 1, 2 };
        var sortedFileRanks = new[] { 1, 1, 1, 2, 1 };
        var sortedLines = new[] { 2, 8, 8, 10, 3 };
        var sortedColumns = new[] { 3, 1, 4, 1, 1 };
        var sortedDeclarationIndices = new[] { 0, 1, 2, 4, 3 };
        var nearestQueryNameIds = new[] { 1, 1, 1, 2, 3, 1 };
        var nearestQueryFileRanks = new[] { 1, 1, 1, 1, 1, 2 };
        var nearestQueryLines = new[] { 1, 7, 8, 99, 99, 10 };
        var expectedNearest = new[] { -1, 0, 2, 3, -1, 4 };

        var nearestResultIndices = new int[nearestQueryNameIds.Length];
        var nearestCount = (int)(bindingLookupFindNearestDeclarationIndicesInto.Invoke(
            null,
            new object[]
            {
                sortedNameIds,
                sortedFileRanks,
                sortedLines,
                sortedColumns,
                sortedDeclarationIndices,
                nearestQueryNameIds,
                nearestQueryFileRanks,
                nearestQueryLines,
                nearestResultIndices
            }) ?? -1);

        Assert.Equal(4, nearestCount);
        Assert.Equal(expectedNearest, nearestResultIndices);

        var nearestChecksumResultIndices = new int[nearestQueryNameIds.Length];
        var nearestChecksum = (int)(bindingLookupFindNearestDeclarationChecksumInto.Invoke(
            null,
            new object[]
            {
                sortedNameIds,
                sortedFileRanks,
                sortedLines,
                sortedColumns,
                sortedDeclarationIndices,
                nearestQueryNameIds,
                nearestQueryFileRanks,
                nearestQueryLines,
                nearestChecksumResultIndices
            }) ?? -1);

        var expectedNearestChecksum = 4;
        foreach (var declarationIndex in expectedNearest.Where(index => index >= 0))
        {
            var sortedIndex = Array.IndexOf(sortedDeclarationIndices, declarationIndex);
            expectedNearestChecksum += sortedNameIds[sortedIndex] * 13
                + sortedLines[sortedIndex] * 31
                + sortedColumns[sortedIndex] * 17
                + declarationIndex;
        }

        Assert.Equal(expectedNearestChecksum, nearestChecksum);
        Assert.Equal(expectedNearest, nearestChecksumResultIndices);
    }

    private static int[][] BuildExpectedBindingCandidateColumns(
        int[] queryColumns,
        int[] spanStartColumns,
        int[] spanEndColumns)
    {
        var result = new int[queryColumns.Length][];
        for (var i = 0; i < queryColumns.Length; i++)
        {
            var column = queryColumns[i];
            var seen = new HashSet<int>();
            if (column > 0)
                seen.Add(column);
            if (column > 1)
                seen.Add(column - 1);
            seen.Add(column + 1);

            var spanStart = spanStartColumns[i];
            var spanEnd = spanEndColumns[i];
            if (spanStart > 0 && spanEnd >= spanStart)
            {
                for (var candidate = spanStart; candidate <= spanEnd; candidate++)
                {
                    seen.Add(candidate);
                }
            }

            result[i] = seen.OrderBy(candidate => Math.Abs(candidate - column)).ToArray();
        }

        return result;
    }

    private static int[] FlattenExpectedBindingCandidateColumns(
        int[][] expectedColumns,
        int[] starts,
        int[] counts)
    {
        var total = expectedColumns.Sum(columns => columns.Length);
        var flat = new int[total];
        var offset = 0;
        for (var i = 0; i < expectedColumns.Length; i++)
        {
            starts[i] = offset;
            counts[i] = expectedColumns[i].Length;
            Array.Copy(expectedColumns[i], 0, flat, offset, expectedColumns[i].Length);
            offset += expectedColumns[i].Length;
        }

        return flat;
    }

    private static int CandidateColumnChecksum(
        int total,
        int[] starts,
        int[] counts,
        int[] columns)
    {
        var checksum = total;
        for (var i = 0; i < counts.Length; i++)
        {
            var start = starts[i];
            var count = counts[i];
            checksum += count * 97 + start * 7;
            for (var j = 0; j < count; j++)
            {
                checksum += columns[start + j] * 31 + (j + 1) * 17;
            }
        }

        return checksum;
    }

    private static void AssertSemanticScopeVisibleVariablesLikeProduction(
        MethodInfo semanticScopeVisibleSymbolIndicesInto,
        MethodInfo semanticScopeVisibleSymbolChecksumInto,
        MethodInfo semanticScopeBuildSortedIndexInto,
        MethodInfo semanticScopeBuildSortedIndexChecksumInto,
        MethodInfo semanticScopeBuildDepthsInto,
        MethodInfo semanticScopeBuildDepthChecksumInto,
        MethodInfo semanticScopeLookupSymbolIndicesInto,
        MethodInfo semanticScopeLookupSymbolChecksumInto)
    {
        var model = new SemanticModel();
        var root = model.OpenScope(-1, 1, 1);
        model.RecordScopedVariable(root, "x", BuiltInTypes.Int);
        model.RecordScopedVariable(root, "y", BuiltInTypes.String);

        var inner = model.OpenScope(root, 5, 1);
        model.RecordScopedVariable(inner, "x", BuiltInTypes.Bool);
        model.RecordScopedVariable(inner, "z", BuiltInTypes.Double);
        model.RecordScopedFunction(inner, "localFunc", new SimpleTypeInfo("fn"));
        model.CloseScope(inner, 10, 120);

        var sibling = model.OpenScope(root, 12, 1);
        model.RecordScopedVariable(sibling, "sibling", BuiltInTypes.Char);
        model.CloseScope(sibling, 15, 120);

        var open = model.OpenScope(root, 18, 1);
        model.RecordScopedVariable(open, "openOnly", BuiltInTypes.Object);
        model.CloseScope(root, 20, 120);

        var scopeParentIds = new[] { -1, 0, 0, 0 };
        var scopeStartLines = new[] { 1, 5, 12, 18 };
        var scopeStartColumns = new[] { 1, 1, 1, 1 };
        var scopeEndLines = new[] { 20, 10, 15, 0 };
        var scopeEndColumns = new[] { 120, 120, 120, 0 };
        var scopeDepths = new[] { 0, 1, 1, 1 };
        var scopeSymbolStarts = new[] { 0, 2, 5, 6 };
        var scopeSymbolCounts = new[] { 2, 3, 1, 1 };
        var symbolNames = new[] { "x", "y", "x", "z", "localFunc", "sibling", "openOnly" };
        var symbolTypeNames = new[] { "int", "string", "bool", "double", "fn", "char", "object" };
        var symbolNameIds = CreateOrdinalIds(symbolNames);
        var symbolNameLengths = symbolNames.Select(static name => name.Length).ToArray();
        var symbolTypeNameLengths = symbolTypeNames.Select(static name => name.Length).ToArray();
        var sortedScopeIds = new[] { 0, 1, 2, 3 };
        var sortedScopeStartLines = sortedScopeIds.Select(id => scopeStartLines[id]).ToArray();
        var sortedScopeStartColumns = sortedScopeIds.Select(id => scopeStartColumns[id]).ToArray();
        var sortedScopeMaxEndLines = BuildPrefixMaxEndLines(sortedScopeIds, scopeEndLines);

        var builtScopeDepths = new int[scopeParentIds.Length];
        var builtDepthCount = (int)(semanticScopeBuildDepthsInto.Invoke(
            null,
            new object[] { scopeParentIds, builtScopeDepths }) ?? -1);
        Assert.Equal(scopeParentIds.Length, builtDepthCount);
        Assert.Equal(scopeDepths, builtScopeDepths);

        var nestedScopeParentIds = new[] { -1, 0, 1, 2, 1, 4 };
        var expectedNestedScopeDepths = new[] { 0, 1, 2, 3, 2, 3 };
        var actualNestedScopeDepths = new int[nestedScopeParentIds.Length];
        var nestedDepthCount = (int)(semanticScopeBuildDepthsInto.Invoke(
            null,
            new object[] { nestedScopeParentIds, actualNestedScopeDepths }) ?? -1);
        Assert.Equal(nestedScopeParentIds.Length, nestedDepthCount);
        Assert.Equal(expectedNestedScopeDepths, actualNestedScopeDepths);

        var actualDepthChecksum = (int)(semanticScopeBuildDepthChecksumInto.Invoke(
            null,
            new object[] { nestedScopeParentIds, new int[nestedScopeParentIds.Length] }) ?? -1);
        var expectedDepthChecksum = nestedScopeParentIds.Length * 17;
        for (var i = 0; i < expectedNestedScopeDepths.Length; i++)
        {
            expectedDepthChecksum += (i + 1) * 31 + expectedNestedScopeDepths[i] * 7;
        }

        Assert.Equal(expectedDepthChecksum, actualDepthChecksum);

        var shuffledScopeStartLines = new[] { 12, 1, 18, 5 };
        var shuffledScopeStartColumns = new[] { 1, 1, 1, 1 };
        var shuffledScopeEndLines = new[] { 15, 20, 0, 10 };
        var shuffledResultIds = new int[4];
        var shuffledResultStartLines = new int[4];
        var shuffledResultStartColumns = new int[4];
        var shuffledResultMaxEndLines = new int[4];
        var shuffledCount = (int)(semanticScopeBuildSortedIndexInto.Invoke(
            null,
            new object[]
            {
                shuffledScopeStartLines,
                shuffledScopeStartColumns,
                shuffledScopeEndLines,
                new int[4],
                new int[4],
                new int[4],
                shuffledResultIds,
                shuffledResultStartLines,
                shuffledResultStartColumns,
                shuffledResultMaxEndLines
            }) ?? -1);

        Assert.Equal(4, shuffledCount);
        Assert.Equal(new[] { 1, 3, 0, 2 }, shuffledResultIds);
        Assert.Equal(new[] { 1, 5, 12, 18 }, shuffledResultStartLines);
        Assert.Equal(new[] { 1, 1, 1, 1 }, shuffledResultStartColumns);
        Assert.Equal(new[] { 20, 20, 20, 20 }, shuffledResultMaxEndLines);

        var actualIndexChecksum = (int)(semanticScopeBuildSortedIndexChecksumInto.Invoke(
            null,
            new object[]
            {
                scopeStartLines,
                scopeStartColumns,
                scopeEndLines,
                new int[scopeStartLines.Length],
                new int[scopeStartLines.Length],
                new int[scopeStartLines.Length],
                new int[scopeStartLines.Length],
                new int[scopeStartLines.Length],
                new int[scopeStartLines.Length],
                new int[scopeStartLines.Length]
            }) ?? -1);
        var expectedIndexChecksum = scopeStartLines.Length * 17;
        for (var i = 0; i < sortedScopeIds.Length; i++)
        {
            expectedIndexChecksum += (i + 1) * 97
                + (sortedScopeIds[i] + 1) * 31
                + sortedScopeStartLines[i] * 13
                + sortedScopeStartColumns[i] * 7
                + sortedScopeMaxEndLines[i] * 3;
        }

        Assert.Equal(expectedIndexChecksum, actualIndexChecksum);

        var queryLines = new[] { 2, 6, 13, 19, 30 };
        var queryColumns = new[] { 10, 10, 10, 10, 10 };
        var expectedScopeIds = new[] { 0, 1, 2, 0, -1 };
        var expectedVisibleNames = new[]
        {
            model.GetVisibleVariablesAtPosition(2, 10).Keys.ToArray(),
            model.GetVisibleVariablesAtPosition(6, 10).Keys.ToArray(),
            model.GetVisibleVariablesAtPosition(13, 10).Keys.ToArray(),
            model.GetVisibleVariablesAtPosition(19, 10).Keys.ToArray(),
            Array.Empty<string>()
        };

        var resultScopeIds = new int[queryLines.Length];
        var resultStarts = new int[queryLines.Length];
        var resultCounts = new int[queryLines.Length];
        var resultSymbolIndices = new int[64];
        var slotNameIds = new int[symbolNames.Length * 2 + 1];
        var touchedSlots = new int[symbolNames.Length];
        var total = (int)(semanticScopeVisibleSymbolIndicesInto.Invoke(
            null,
            new object[]
            {
                scopeParentIds,
                scopeStartLines,
                scopeStartColumns,
                scopeEndLines,
                scopeEndColumns,
                scopeDepths,
                scopeSymbolStarts,
                scopeSymbolCounts,
                symbolNameIds,
                sortedScopeIds,
                sortedScopeStartLines,
                sortedScopeStartColumns,
                sortedScopeMaxEndLines,
                queryLines,
                queryColumns,
                resultScopeIds,
                resultStarts,
                resultCounts,
                resultSymbolIndices,
                slotNameIds,
                touchedSlots
            }) ?? -1);

        Assert.Equal(expectedScopeIds, resultScopeIds);
        Assert.Equal(expectedVisibleNames.Sum(static names => names.Length), total);
        for (var queryIndex = 0; queryIndex < queryLines.Length; queryIndex++)
        {
            var actualNames = resultSymbolIndices
                .Skip(resultStarts[queryIndex])
                .Take(resultCounts[queryIndex])
                .Select(index => symbolNames[index])
                .ToArray();
            Assert.Equal(expectedVisibleNames[queryIndex], actualNames);
        }

        Array.Clear(resultScopeIds);
        Array.Clear(resultStarts);
        Array.Clear(resultCounts);
        Array.Clear(resultSymbolIndices);
        Array.Clear(slotNameIds);
        Array.Clear(touchedSlots);

        var actualChecksum = (int)(semanticScopeVisibleSymbolChecksumInto.Invoke(
            null,
            new object[]
            {
                scopeParentIds,
                scopeStartLines,
                scopeStartColumns,
                scopeEndLines,
                scopeEndColumns,
                scopeDepths,
                scopeSymbolStarts,
                scopeSymbolCounts,
                symbolNameIds,
                symbolNameLengths,
                symbolTypeNameLengths,
                sortedScopeIds,
                sortedScopeStartLines,
                sortedScopeStartColumns,
                sortedScopeMaxEndLines,
                queryLines,
                queryColumns,
                resultScopeIds,
                resultStarts,
                resultCounts,
                resultSymbolIndices,
                slotNameIds,
                touchedSlots
            }) ?? -1);
        var expectedChecksum = total * 17;
        for (var queryIndex = 0; queryIndex < queryLines.Length; queryIndex++)
        {
            expectedChecksum += (expectedScopeIds[queryIndex] + 1) * 31;
            for (var i = 0; i < resultCounts[queryIndex]; i++)
            {
                var symbolIndex = resultSymbolIndices[resultStarts[queryIndex] + i];
                expectedChecksum += symbolNameLengths[symbolIndex] * 13
                    + symbolTypeNameLengths[symbolIndex] * 7
                    + (i + 1);
            }
        }

        Assert.Equal(expectedChecksum, actualChecksum);

        var lookupQueryNames = new[] { "x", "y", "z", "localFunc", "sibling", "openOnly", "x", "missing" };
        var lookupQueryLines = new[] { 6, 6, 6, 6, 13, 19, 19, 30 };
        var lookupQueryColumns = new[] { 10, 10, 10, 10, 10, 10, 10, 10 };
        var lookupQueryNameIds = CreateQueryNameIds(symbolNames, symbolNameIds, lookupQueryNames);
        var expectedLookupScopeIds = new[] { 1, 1, 1, 1, 2, 0, 0, -1 };
        var lookupResultScopeIds = new int[lookupQueryNames.Length];
        var lookupResultSymbolIndices = new int[lookupQueryNames.Length];

        var found = (int)(semanticScopeLookupSymbolIndicesInto.Invoke(
            null,
            new object[]
            {
                scopeParentIds,
                scopeStartLines,
                scopeStartColumns,
                scopeEndLines,
                scopeEndColumns,
                scopeDepths,
                scopeSymbolStarts,
                scopeSymbolCounts,
                symbolNameIds,
                sortedScopeIds,
                sortedScopeStartLines,
                sortedScopeStartColumns,
                sortedScopeMaxEndLines,
                lookupQueryNameIds,
                lookupQueryLines,
                lookupQueryColumns,
                lookupResultScopeIds,
                lookupResultSymbolIndices
            }) ?? -1);

        var expectedLookupTypes = lookupQueryNames
            .Select((name, index) => model.LookupIdentifierAtPosition(name, lookupQueryLines[index], lookupQueryColumns[index]))
            .ToArray();
        Assert.Equal(expectedLookupTypes.Count(static type => type != null), found);
        Assert.Equal(expectedLookupScopeIds, lookupResultScopeIds);
        for (var queryIndex = 0; queryIndex < lookupQueryNames.Length; queryIndex++)
        {
            var expectedType = expectedLookupTypes[queryIndex];
            var symbolIndex = lookupResultSymbolIndices[queryIndex];
            if (expectedType == null)
            {
                Assert.Equal(-1, symbolIndex);
            }
            else
            {
                Assert.InRange(symbolIndex, 0, symbolTypeNames.Length - 1);
                Assert.Equal(expectedType.ToString(), symbolTypeNames[symbolIndex]);
            }
        }

        Array.Clear(lookupResultScopeIds);
        Array.Clear(lookupResultSymbolIndices);

        var actualLookupChecksum = (int)(semanticScopeLookupSymbolChecksumInto.Invoke(
            null,
            new object[]
            {
                scopeParentIds,
                scopeStartLines,
                scopeStartColumns,
                scopeEndLines,
                scopeEndColumns,
                scopeDepths,
                scopeSymbolStarts,
                scopeSymbolCounts,
                symbolNameIds,
                symbolNameLengths,
                symbolTypeNameLengths,
                sortedScopeIds,
                sortedScopeStartLines,
                sortedScopeStartColumns,
                sortedScopeMaxEndLines,
                lookupQueryNameIds,
                lookupQueryLines,
                lookupQueryColumns,
                lookupResultScopeIds,
                lookupResultSymbolIndices
            }) ?? -1);

        var expectedLookupChecksum = found * 17;
        for (var queryIndex = 0; queryIndex < lookupQueryNames.Length; queryIndex++)
        {
            expectedLookupChecksum += (expectedLookupScopeIds[queryIndex] + 1) * 31;
            var expectedType = expectedLookupTypes[queryIndex];
            if (expectedType != null)
            {
                expectedLookupChecksum += lookupQueryNames[queryIndex].Length * 13
                    + expectedType.ToString().Length * 7;
            }
        }

        Assert.Equal(expectedLookupChecksum, actualLookupChecksum);
    }

    private static int[] BuildPrefixMaxEndLines(int[] sortedScopeIds, int[] scopeEndLines)
    {
        var result = new int[sortedScopeIds.Length];
        var max = 0;
        for (var i = 0; i < sortedScopeIds.Length; i++)
        {
            var endLine = scopeEndLines[sortedScopeIds[i]];
            if (endLine > max)
                max = endLine;

            result[i] = max;
        }

        return result;
    }

    private static int[] CreateOrdinalIds(string[] values)
    {
        var idsByValue = new Dictionary<string, int>(StringComparer.Ordinal);
        var ids = new int[values.Length];
        for (var i = 0; i < values.Length; i++)
        {
            if (!idsByValue.TryGetValue(values[i], out var id))
            {
                id = idsByValue.Count + 1;
                idsByValue.Add(values[i], id);
            }

            ids[i] = id;
        }

        return ids;
    }

    private static int[] CreateQueryNameIds(string[] symbolNames, int[] symbolNameIds, string[] queryNames)
    {
        var idsByValue = new Dictionary<string, int>(StringComparer.Ordinal);
        var maxId = 0;
        for (var i = 0; i < symbolNames.Length; i++)
        {
            idsByValue.TryAdd(symbolNames[i], symbolNameIds[i]);
            if (symbolNameIds[i] > maxId)
                maxId = symbolNameIds[i];
        }

        var ids = new int[queryNames.Length];
        for (var i = 0; i < queryNames.Length; i++)
        {
            if (!idsByValue.TryGetValue(queryNames[i], out var id))
            {
                id = ++maxId;
                idsByValue.Add(queryNames[i], id);
            }

            ids[i] = id;
        }

        return ids;
    }

    private static int[] CreateSortedFileRanks(string[] files)
    {
        var uniqueFiles = files.Distinct(StringComparer.Ordinal).ToArray();
        Array.Sort(uniqueFiles, Comparer<string>.Default);

        var ranksByFile = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < uniqueFiles.Length; i++)
        {
            ranksByFile.Add(uniqueFiles[i], i + 1);
        }

        var ranks = new int[files.Length];
        for (var i = 0; i < files.Length; i++)
        {
            ranks[i] = ranksByFile[files[i]];
        }

        return ranks;
    }

    private static List<DiagnosticResult> BuildDiagnosticSeveritySummaryDiagnostics()
    {
        return new List<DiagnosticResult>
        {
            BuildDiagnosticWithSeverity("error", 1),
            BuildDiagnosticWithSeverity("warning", 2),
            BuildDiagnosticWithSeverity("info", 3),
            BuildDiagnosticWithSeverity("hint", 4),
            BuildDiagnosticWithSeverity("info", 5),
            BuildDiagnosticWithSeverity("error", 6)
        };
    }

    private static List<SymbolResult> BuildSymbolKindFilterSymbols()
    {
        return new List<SymbolResult>
        {
            BuildSymbol("main", SymbolKind.Function, 1),
            BuildSymbol("Customer", SymbolKind.Class, 5),
            BuildSymbol("Name", SymbolKind.Property, 7),
            BuildSymbol("helper", SymbolKind.Function, 12),
            BuildSymbol("value", SymbolKind.Variable, 13),
            BuildSymbol("render", SymbolKind.Method, 18),
            BuildSymbol("calculate", SymbolKind.Function, 24)
        };
    }

    private static SymbolResult BuildSymbol(string name, SymbolKind kind, int line)
    {
        return new SymbolResult(
            name,
            kind,
            "Program.nl",
            line,
            1,
            null,
            null,
            null,
            null);
    }

    private static DiagnosticResult BuildDiagnosticWithSeverity(string severity, int line)
    {
        return new DiagnosticResult(
            "NL900",
            severity,
            $"Synthetic {severity} diagnostic",
            "Program.nl",
            line,
            1,
            1,
            "value := input",
            null,
            null,
            null,
            null,
            null,
            null);
    }

    private static (int StartColumn, int Length) FindFirstIdentifierSpan(string lineText)
    {
        for (var i = 0; i < lineText.Length; i++)
        {
            if (!IsIdentifierChar(lineText[i]))
                continue;

            var start = i;
            while (i + 1 < lineText.Length && IsIdentifierChar(lineText[i + 1]))
                i++;

            return (start + 1, i - start + 1);
        }

        return (1, 1);
    }

    private static (int StartColumn, int Length)? ExtractIdentifierSpanAtPosition(string source, int line, int col)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length)
                return null;

            var lineText = lines[line - 1];
            if (lineText.Length == 0)
                return null;

            var index = FindNearestIdentifierIndex(lineText, Math.Clamp(col - 1, 0, lineText.Length - 1));
            if (index < 0)
                return null;

            var start = index;
            while (start > 0 && IsIdentifierChar(lineText[start - 1]))
                start--;

            var end = index;
            while (end + 1 < lineText.Length && IsIdentifierChar(lineText[end + 1]))
                end++;

            return (start + 1, end - start + 1);
        }
        catch
        {
            return null;
        }
    }

    private static (int StartColumn, int Length)? ExtractEditorIdentifierSpanAtPosition(string source, int line, int col)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length || col <= 0)
                return null;

            var lineText = lines[line - 1];
            if (lineText.Length == 0)
                return null;

            var index = col - 1;
            if (index >= lineText.Length)
            {
                index = lineText.Length - 1;
                if (!IsIdentifierChar(lineText[index]))
                    return null;
            }
            else if (!IsIdentifierChar(lineText[index]))
            {
                return null;
            }

            var start = index;
            while (start > 0 && IsIdentifierChar(lineText[start - 1]))
                start--;

            var end = index;
            while (end + 1 < lineText.Length && IsIdentifierChar(lineText[end + 1]))
                end++;

            return (start + 1, end - start + 1);
        }
        catch
        {
            return null;
        }
    }

    private static int FindNearestIdentifierIndex(string lineText, int index)
    {
        if (lineText.Length == 0)
            return -1;

        if (index >= 0 && index < lineText.Length && IsIdentifierChar(lineText[index]))
            return index;

        const int MaxDistance = 3;
        for (var distance = 1; distance <= MaxDistance; distance++)
        {
            var left = index - distance;
            if (left >= 0 && IsIdentifierChar(lineText[left]) && IsSnapFriendlyNeighbor(lineText, left + 1, index))
                return left;

            var right = index + distance;
            if (right < lineText.Length && IsIdentifierChar(lineText[right]) && IsSnapFriendlyNeighbor(lineText, index, right - 1))
                return right;
        }

        return -1;
    }

    private static bool IsIdentifierChar(char ch) => char.IsLetterOrDigit(ch) || ch == '_';

    private static bool IsSnapFriendlyNeighbor(string lineText, int start, int end)
    {
        if (start > end)
            return true;

        for (var i = start; i <= end; i++)
        {
            if (i < 0 || i >= lineText.Length)
                continue;

            var ch = lineText[i];
            if (char.IsWhiteSpace(ch))
                continue;

            if (ch is '.' or '?' or '(' or ')' or '[' or ']' or '{' or '}' or ',' or ';' or ':')
                continue;

            return false;
        }

        return true;
    }

    private static int FindNameStartColumn(string lineText, string name, int searchStartColumn)
    {
        var searchStart = Math.Max(0, searchStartColumn - 1);
        var index = lineText.IndexOf(name, searchStart, StringComparison.Ordinal);
        Assert.True(index >= 0, $"Expected to find {name} in {lineText} at or after column {searchStartColumn}.");
        return index + 1;
    }

    private static int FindWholeIdentifierColumn(string lineText, string name, int searchStartColumn)
    {
        var index = FindWholeIdentifier(lineText, name, searchStartColumn - 1);
        Assert.True(index >= 0, $"Expected to find whole identifier {name} in {lineText} at or after column {searchStartColumn}.");
        return index + 1;
    }

    private static bool TryFindIdentifierNameColumn(
        string? sourceText,
        string name,
        int line,
        int fallbackColumn,
        out int column)
    {
        column = fallbackColumn;
        if (string.IsNullOrWhiteSpace(sourceText) || line <= 0)
            return false;

        var lines = sourceText.Split('\n');
        if (line > lines.Length)
            return false;

        var lineText = lines[line - 1].TrimEnd('\r');
        if (lineText.Length == 0)
            return false;

        var start = Math.Clamp(fallbackColumn - 1, 0, lineText.Length);
        var index = FindWholeIdentifier(lineText, name, start);
        if (index < 0)
        {
            index = FindWholeIdentifier(lineText, name, 0);
        }

        if (index < 0)
            return false;

        column = index + 1;
        return true;
    }

    private static int FindWholeIdentifier(string line, string name, int startIndex)
    {
        var searchStart = Math.Clamp(startIndex, 0, line.Length);
        while (searchStart <= line.Length)
        {
            var index = line.IndexOf(name, searchStart, StringComparison.Ordinal);
            if (index < 0)
                return -1;

            var before = index > 0 ? line[index - 1] : '\0';
            var afterIndex = index + name.Length;
            var after = afterIndex < line.Length ? line[afterIndex] : '\0';
            if (!IsIdentifierChar(before) && !IsIdentifierChar(after))
                return index;

            searchStart = index + Math.Max(1, name.Length);
        }

        return -1;
    }

    private static bool SelectedSpanMatchesDeclarationName(
        string source,
        int line,
        int declarationColumn,
        string declarationName,
        int selectedStartColumn,
        int selectedEndColumn)
    {
        var lines = source.Split('\n');
        if (line <= 0 || line > lines.Length)
            return false;

        var lineText = lines[line - 1];
        var searchStart = Math.Max(0, Math.Min(declarationColumn - 1, lineText.Length));
        var nameIndex = lineText.IndexOf(declarationName, searchStart, StringComparison.Ordinal);
        if (nameIndex < 0)
            return false;

        var nameStartColumn = nameIndex + 1;
        var nameEndColumn = nameStartColumn + declarationName.Length - 1;
        return selectedStartColumn == nameStartColumn && selectedEndColumn == nameEndColumn;
    }

    private static (int StartColumn, int Length)? ExtractMemberReceiverSpan(string source, int line, int memberStartColumn)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length)
                return null;

            var lineText = lines[line - 1];
            var memberStartIndex = memberStartColumn - 1;
            if (memberStartIndex <= 0 || memberStartIndex > lineText.Length)
                return null;

            var separatorIndex = memberStartIndex - 1;
            if (separatorIndex >= 0 && lineText[separatorIndex] == '.')
            {
                var receiverEnd = separatorIndex - 1;
                while (receiverEnd >= 0 && char.IsWhiteSpace(lineText[receiverEnd]))
                    receiverEnd--;
                if (receiverEnd < 0)
                    return null;

                var receiverStart = receiverEnd;
                while (receiverStart >= 0 && IsIdentifierChar(lineText[receiverStart]))
                    receiverStart--;

                receiverStart++;
                return receiverStart <= receiverEnd
                    ? (receiverStart + 1, receiverEnd - receiverStart + 1)
                    : null;
            }

            if (separatorIndex >= 1 && lineText[separatorIndex - 1] == '?' && lineText[separatorIndex] == '.')
            {
                var receiverEnd = separatorIndex - 2;
                while (receiverEnd >= 0 && char.IsWhiteSpace(lineText[receiverEnd]))
                    receiverEnd--;
                if (receiverEnd < 0)
                    return null;

                var receiverStart = receiverEnd;
                while (receiverStart >= 0 && IsIdentifierChar(lineText[receiverStart]))
                    receiverStart--;

                receiverStart++;
                return receiverStart <= receiverEnd
                    ? (receiverStart + 1, receiverEnd - receiverStart + 1)
                    : null;
            }

            return null;
        }
        catch
        {
            return null;
        }
    }

    private static string? ExtractCompletionPrefix(string source, int line, int column)
    {
        var lines = source.Split('\n');
        if (line <= 0 || line > lines.Length)
            return null;

        var lineText = lines[line - 1];
        return column > 0 && column <= lineText.Length
            ? lineText.Substring(0, column)
            : lineText;
    }

    private static string? ExtractDocComment(string source, int definitionLine)
    {
        var spans = ExtractDocCommentSpans(source, definitionLine);
        return spans.Count > 0
            ? string.Join("\n", spans.Select(span => source.Substring(span.Start, span.Length)))
            : null;
    }

    private static List<(int Start, int Length)> ExtractDocCommentSpans(string source, int definitionLine)
    {
        var spans = new List<(int Start, int Length)>();
        var lines = source.Split('\n');
        if (definitionLine <= 1 || definitionLine > lines.Length)
            return spans;

        var startLine = -1;
        var commentCount = 0;
        for (var i = definitionLine - 2; i >= 0; i--)
        {
            var trimmed = lines[i].Trim();
            if (trimmed.StartsWith("//", StringComparison.Ordinal))
            {
                startLine = i;
                commentCount++;
            }
            else if (string.IsNullOrWhiteSpace(trimmed) && commentCount == 0)
            {
                continue;
            }
            else
            {
                break;
            }
        }

        if (startLine < 0)
            return spans;

        var lineStarts = BuildLfLineStarts(source);
        for (var i = startLine; i <= definitionLine - 2; i++)
        {
            var span = ExtractDocCommentContentSpan(lines[i], lineStarts[i]);
            if (span != null)
            {
                spans.Add(span.Value);
            }
        }

        return spans;
    }

    private static (int Start, int Length)? ExtractDocCommentContentSpan(string lineText, int lineStart)
    {
        var trimStart = 0;
        var trimEnd = lineText.Length - 1;

        while (trimStart <= trimEnd && char.IsWhiteSpace(lineText[trimStart]))
            trimStart++;

        while (trimEnd >= trimStart && char.IsWhiteSpace(lineText[trimEnd]))
            trimEnd--;

        if (trimStart + 1 > trimEnd || lineText[trimStart] != '/' || lineText[trimStart + 1] != '/')
            return null;

        while (trimStart <= trimEnd && lineText[trimStart] == '/')
            trimStart++;

        while (trimStart <= trimEnd && char.IsWhiteSpace(lineText[trimStart]))
            trimStart++;

        while (trimEnd >= trimStart && char.IsWhiteSpace(lineText[trimEnd]))
            trimEnd--;

        return trimEnd < trimStart
            ? (lineStart + trimStart, 0)
            : (lineStart + trimStart, trimEnd - trimStart + 1);
    }

    private static string? MaterializeDocComment(string source, int[] starts, int[] lengths, int count)
    {
        if (count <= 0)
            return null;

        return string.Join("\n", Enumerable.Range(0, count).Select(i => source.Substring(starts[i], lengths[i])));
    }

    private static string? ExtractVariableDeclarationName(string source, int line)
    {
        var span = ExtractVariableDeclarationNameSpan(source, line);
        if (span == null)
            return null;

        var lineText = source.Split('\n')[line - 1];
        return lineText.Substring(span.Value.StartColumn - 1, span.Value.Length);
    }

    private static (int StartColumn, int Length)? ExtractVariableDeclarationNameSpan(string source, int line)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length)
                return null;

            var lineText = lines[line - 1];
            var assignIndex = lineText.IndexOf(":=", StringComparison.Ordinal);
            if (assignIndex <= 0)
                return null;

            var end = assignIndex - 1;
            while (end >= 0 && char.IsWhiteSpace(lineText[end]))
                end--;
            if (end < 0)
                return null;

            var start = end;
            while (start >= 0 && IsIdentifierChar(lineText[start]))
                start--;

            start++;
            return start <= end
                ? (start + 1, end - start + 1)
                : null;
        }
        catch
        {
            return null;
        }
    }

    private static int BuildLineRanges(string source, int[] starts, int[] lengths)
    {
        var lineStart = 0;
        var count = 0;

        for (var position = 0; position < source.Length; position++)
        {
            if (source[position] != '\n')
                continue;

            starts[count] = lineStart;
            lengths[count] = position - lineStart;
            count++;
            lineStart = position + 1;
        }

        starts[count] = lineStart;
        lengths[count] = source.Length - lineStart;
        return count + 1;
    }

    private static int LineIndexFromOffset(int[] starts, int sourceLength, int offset)
    {
        if (offset < 0)
        {
            offset = 0;
        }

        if (offset > sourceLength)
        {
            offset = sourceLength;
        }

        var result = 0;
        for (var i = 0; i < starts.Length; i++)
        {
            if (starts[i] <= offset)
            {
                result = i;
            }
        }

        return result;
    }

    private static int ColumnFromOffset(int[] starts, int sourceLength, int offset)
    {
        if (offset < 0)
        {
            offset = 0;
        }

        if (offset > sourceLength)
        {
            offset = sourceLength;
        }

        return offset - starts[LineIndexFromOffset(starts, sourceLength, offset)];
    }

    private static int[] BuildOffsetLineIndices(int[] starts, int lineCount, int sourceLength)
    {
        var offsetLineIndices = new int[sourceLength + 1];
        for (var lineIndex = 0; lineIndex < lineCount; lineIndex++)
        {
            var lineStart = starts[lineIndex];
            var endExclusive = lineIndex + 1 < lineCount ? starts[lineIndex + 1] : sourceLength + 1;
            for (var offset = lineStart; offset < endExclusive && offset <= sourceLength; offset++)
            {
                offsetLineIndices[offset] = lineIndex;
            }
        }

        return offsetLineIndices;
    }

    private static int[] BuildLfLineStarts(string source)
    {
        var starts = new List<int> { 0 };
        for (var i = 0; i < source.Length; i++)
        {
            if (source[i] == '\n')
            {
                starts.Add(i + 1);
            }
        }

        return starts.ToArray();
    }

    private static int CountOccurrences(string text, string value)
    {
        var count = 0;
        var startIndex = 0;
        while (true)
        {
            var index = text.IndexOf(value, startIndex, StringComparison.Ordinal);
            if (index < 0)
                return count;

            count++;
            startIndex = index + value.Length;
        }
    }

    [Fact]
    public void OverloadCandidates_SelectsSameIndexAsCSharpTieBreak()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(
            Path.GetTempPath(),
            $"NSharpLang.Compiler.Dogfood.Overloads.{Guid.NewGuid():N}.dll");

        try
        {
            var compiler = new MultiFileCompiler(projectRoot, config);
            var result = compiler.CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);
            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));

            var assembly = Assembly.Load(File.ReadAllBytes(outputPath));
            var programType = assembly.GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var selectBest = programType.GetMethod(
                    "OverloadSelectBestCandidate",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit OverloadSelectBestCandidate.");
            var batchChecksum = programType.GetMethod(
                    "OverloadSelectBatchChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit OverloadSelectBatchChecksumInto.");

            int InvokeSelect(OverloadRankRow[] rows)
            {
                var count = rows.Length;
                var valid = new int[count];
                var scores = new int[count];
                var generic = new int[count];
                var paramsFlags = new int[count];
                var defaults = new int[count];
                for (var i = 0; i < count; i++)
                {
                    valid[i] = rows[i].Valid ? 1 : 0;
                    scores[i] = rows[i].Score;
                    generic[i] = rows[i].IsGeneric ? 1 : 0;
                    paramsFlags[i] = rows[i].UsesParams ? 1 : 0;
                    defaults[i] = rows[i].DefaultsUsed;
                }

                return (int)(selectBest.Invoke(null, new object[]
                {
                    valid, scores, generic, paramsFlags, defaults, count
                }) ?? -1);
            }

            // Each scenario exercises one tie-break level. The expected index comes from the exact
            // C# four-level tie-break (score > non-generic > non-params > fewer-defaults, first-wins).
            var scenarios = new[]
            {
                // Single valid candidate.
                new[] { Row(true, 3, false, false, 0) },
                // No valid candidate.
                new[] { Row(false, 9, false, false, 0), Row(false, 9, false, false, 0) },
                // Higher score wins regardless of order.
                new[] { Row(true, 2, false, false, 0), Row(true, 5, true, true, 3), Row(true, 4, false, false, 0) },
                // Equal score: non-generic preferred over generic.
                new[] { Row(true, 5, true, false, 0), Row(true, 5, false, false, 0) },
                // Equal score and generic: non-params preferred.
                new[] { Row(true, 5, false, true, 0), Row(true, 5, false, false, 0) },
                // Equal score/generic/params: fewer defaults preferred.
                new[] { Row(true, 5, false, false, 2), Row(true, 5, false, false, 1) },
                // Full tie keeps the first candidate.
                new[] { Row(true, 5, false, false, 1), Row(true, 5, false, false, 1) },
                // Invalid candidate skipped even with the best columns.
                new[] { Row(false, 9, false, false, 0), Row(true, 1, false, false, 0) },
                // Generic preference only applies at equal score; lower-score non-generic loses.
                new[] { Row(true, 6, true, false, 0), Row(true, 4, false, false, 0) },
            };

            foreach (var rows in scenarios)
            {
                Assert.Equal(ReferenceSelectBestIndex(rows), InvokeSelect(rows));
            }

            // Batch over many call sites with mixed group sizes: kernel checksum must equal the C#
            // reference batch checksum, and the per-call selected index must match.
            const int callCount = 257;
            var validFlags = new List<int>();
            var scoresList = new List<int>();
            var genericList = new List<int>();
            var paramsList = new List<int>();
            var defaultsList = new List<int>();
            var callOffsets = new int[callCount];
            var callCounts = new int[callCount];
            var expectedIndices = new int[callCount];

            for (var c = 0; c < callCount; c++)
            {
                var offset = validFlags.Count;
                var groupSize = 1 + ((c * 7) % 5);
                var rows = new OverloadRankRow[groupSize];
                for (var k = 0; k < groupSize; k++)
                {
                    var valid = ((c + k) % 9) != 0;
                    var score = ((c * 3) + (k * 2)) % 7;
                    var isGeneric = ((c + k) % 3) == 0;
                    var usesParams = ((c + 2 * k) % 4) == 0;
                    var defaultsUsed = (c + k) % 3;
                    rows[k] = Row(valid, score, isGeneric, usesParams, defaultsUsed);
                    validFlags.Add(valid ? 1 : 0);
                    scoresList.Add(score);
                    genericList.Add(isGeneric ? 1 : 0);
                    paramsList.Add(usesParams ? 1 : 0);
                    defaultsList.Add(defaultsUsed);
                }

                callOffsets[c] = offset;
                callCounts[c] = groupSize;
                expectedIndices[c] = ReferenceSelectBestIndex(rows);
            }

            var resultIndices = new int[callCount];
            var actualChecksum = (int)(batchChecksum.Invoke(null, new object[]
            {
                validFlags.ToArray(),
                scoresList.ToArray(),
                genericList.ToArray(),
                paramsList.ToArray(),
                defaultsList.ToArray(),
                callOffsets,
                callCounts,
                callCount,
                resultIndices
            }) ?? int.MinValue);

            var expectedChecksum = ReferenceBatchChecksum(
                validFlags, scoresList, genericList, paramsList, defaultsList,
                callOffsets, callCounts, callCount, expectedIndices);

            Assert.Equal(expectedChecksum, actualChecksum);
            Assert.Equal(expectedIndices, resultIndices);
        }
        finally
        {
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    private static OverloadRankRow Row(bool valid, int score, bool isGeneric, bool usesParams, int defaultsUsed) =>
        new(valid, score, isGeneric, usesParams, defaultsUsed);

    private static int ReferenceSelectBestIndex(OverloadRankRow[] rows)
    {
        var bestIndex = -1;
        var bestScore = -1;
        var bestUsesParams = true;
        var bestDefaultsUsed = int.MaxValue;
        var bestIsGeneric = true;

        for (var i = 0; i < rows.Length; i++)
        {
            if (!rows[i].Valid)
            {
                continue;
            }

            var score = rows[i].Score;
            var isGeneric = rows[i].IsGeneric;
            var usesParams = rows[i].UsesParams;
            var defaultsUsed = rows[i].DefaultsUsed;

            if (bestIndex < 0
                || score > bestScore
                || (score == bestScore && bestIsGeneric && !isGeneric)
                || (score == bestScore && bestIsGeneric == isGeneric && bestUsesParams && !usesParams)
                || (score == bestScore && bestIsGeneric == isGeneric && bestUsesParams == usesParams && defaultsUsed < bestDefaultsUsed))
            {
                bestIndex = i;
                bestScore = score;
                bestUsesParams = usesParams;
                bestDefaultsUsed = defaultsUsed;
                bestIsGeneric = isGeneric;
            }
        }

        return bestIndex;
    }

    private static int ReferenceBatchChecksum(
        List<int> validFlags,
        List<int> scores,
        List<int> genericFlags,
        List<int> paramsFlags,
        List<int> defaultsUsed,
        int[] callOffsets,
        int[] callCounts,
        int callCount,
        int[] expectedIndices)
    {
        var resolved = 0;
        for (var c = 0; c < callCount; c++)
        {
            if (expectedIndices[c] >= 0)
            {
                resolved++;
            }
        }

        var checksum = resolved;
        for (var c = 0; c < callCount; c++)
        {
            var localIndex = expectedIndices[c];
            if (localIndex >= 0)
            {
                var slot = callOffsets[c] + localIndex;
                checksum += (c + 1) * 97
                    + (localIndex + 1) * 31
                    + scores[slot] * 17
                    + genericFlags[slot] * 13
                    + paramsFlags[slot] * 7
                    + defaultsUsed[slot] * 3;
            }
        }

        return checksum;
    }

    private readonly record struct OverloadRankRow(
        bool Valid,
        int Score,
        bool IsGeneric,
        bool UsesParams,
        int DefaultsUsed);

    private static string FindRepoRoot()
    {
        var dir = AppContext.BaseDirectory;
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")))
            {
                return dir;
            }

            dir = Path.GetDirectoryName(dir);
        }

        throw new InvalidOperationException(
            "Could not find repository root (NSharpLang.sln). "
                + $"Searched upward from {AppContext.BaseDirectory}");
    }

    private sealed class CompletionMethodGroupingFixture
    {
        public int Size { get; set; }

        public void Alpha()
        {
        }

        public void Alpha(int value)
        {
        }

        public string Beta(string value) => value;

        public static void Gamma()
        {
        }
    }
}
