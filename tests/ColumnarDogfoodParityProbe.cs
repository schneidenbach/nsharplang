using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Columnar;

namespace NSharpLang.Tests;

internal static class ColumnarDogfoodParityProbe
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryBuildTopLevelFunctionSymbols(string source, out List<ColumnarFunctionSymbol> symbols)
    {
        symbols = new List<ColumnarFunctionSymbol>();

        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

        try
        {
            if (!TryTokenizeColumnarSource(bindings, source, out var tokens))
                return false;

            if (!TryGetTopLevelFunctionDeclarationIndices(source, tokens, out var declCount, out var functionDeclarationIndices))
                return false;

            var rawKinds = tokens.RawKinds;
            var rawCount = tokens.RawCount;
            var modKinds = new int[rawCount + 1];
            var modFlags = new int[rawCount + 1];
            var modCount = bindings.TopLevelDeclarationModifiers(rawKinds, rawCount, modKinds, modFlags);
            if (modCount != declCount)
                return false;

            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            var funcIndices = TopLevelFuncIndices(ck, n);
            if (funcIndices.Count != functionDeclarationIndices.Count)
                return false;

            var cap = n + 1;
            for (var fi = 0; fi < funcIndices.Count; fi++)
            {
                var funcIndex = funcIndices[fi];
                var sk = new int[cap]; var sns = new int[cap]; var snl = new int[cap]; var scs = new int[cap];
                var scc = new int[cap]; var sci = new int[cap]; var sss = new int[cap]; var ssl = new int[cap];
                var pNameStart = new int[cap]; var pNameLen = new int[cap]; var pTypeRoot = new int[cap];
                var sres = new int[8];
                var sTypeParamStarts = new int[cap];
                var sTypeParamLengths = new int[cap];
                var sWhereNameStarts = new int[cap];
                var sWhereNameLengths = new int[cap];
                var sWhereItemCodes = new int[cap];
                var paramCount = bindings.ParseFunctionSignature(
                    ck, cs, cv, n, funcIndex, sk, sns, snl, scs, scc, sci, sss, ssl,
                    pNameStart, pNameLen, pTypeRoot, sTypeParamStarts, sTypeParamLengths,
                    sWhereNameStarts, sWhereNameLengths, sWhereItemCodes, sres);
                if (paramCount < 0 || sres[3] < 0)
                    return false;

                var name = source.Substring(sres[3], sres[4]);
                var parameterTypes = new string[paramCount];
                for (var p = 0; p < paramCount; p++)
                    parameterTypes[p] = ColumnarTypeCanon(sk, sns, snl, scs, scc, sci, source, pTypeRoot[p]);

                var returnType = sres[1] >= 0 ? ColumnarTypeCanon(sk, sns, snl, scs, scc, sci, source, sres[1]) : null;

                symbols.Add(new ColumnarFunctionSymbol(
                    name,
                    modFlags[functionDeclarationIndices[fi]],
                    parameterTypes,
                    returnType));
            }

            return true;
        }
        catch
        {
            symbols = new List<ColumnarFunctionSymbol>();
            return false;
        }
    }

    internal static bool TryResolveTopLevelFunctionNames(string source, out List<List<ColumnarNameRef>> perFunctionRefs)
    {
        perFunctionRefs = new List<List<ColumnarNameRef>>();

        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

        try
        {
            if (!TryTokenizeColumnarSource(bindings, source, out var tokens))
                return false;

            if (!TryGetTopLevelFunctionDeclarationIndices(source, tokens, out var declCount, out var functionDeclarationIndices))
                return false;

            var rawKinds = tokens.RawKinds;
            var rawStarts = tokens.RawStarts;
            var rawValueLengths = tokens.RawValueLengths;
            var rawCount = tokens.RawCount;
            var nameKinds = new int[rawCount + 1];
            var nameStarts = new int[rawCount + 1];
            var nameLengths = new int[rawCount + 1];
            var nameCount = bindings.TopLevelDeclarationNameSpans(
                rawKinds, rawStarts, rawValueLengths, rawCount, nameKinds, nameStarts, nameLengths);
            if (nameCount != declCount)
                return false;
            var functionNames = new HashSet<string>(StringComparer.Ordinal);
            for (var i = 0; i < nameCount; i++)
            {
                if (nameKinds[i] == 7 && nameStarts[i] >= 0)
                    functionNames.Add(source.Substring(nameStarts[i], nameLengths[i]));
            }

            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            var funcIndices = TopLevelFuncIndices(ck, n);
            if (funcIndices.Count != functionDeclarationIndices.Count)
                return false;

            var cap = n + 1;
            foreach (var funcIndex in funcIndices)
            {
                var sk = new int[cap]; var sns = new int[cap]; var snl = new int[cap]; var scs = new int[cap];
                var scc = new int[cap]; var sci = new int[cap]; var sss = new int[cap]; var ssl = new int[cap];
                var pNameStart = new int[cap]; var pNameLen = new int[cap]; var pTypeRoot = new int[cap];
                var sres = new int[8];
                var sTypeParamStarts = new int[cap];
                var sTypeParamLengths = new int[cap];
                var sWhereNameStarts = new int[cap];
                var sWhereNameLengths = new int[cap];
                var sWhereItemCodes = new int[cap];
                var paramCount = bindings.ParseFunctionSignature(
                    ck, cs, cv, n, funcIndex, sk, sns, snl, scs, scc, sci, sss, ssl,
                    pNameStart, pNameLen, pTypeRoot, sTypeParamStarts, sTypeParamLengths,
                    sWhereNameStarts, sWhereNameLengths, sWhereItemCodes, sres);
                if (paramCount < 0 || sres[3] < 0)
                    return false;

                var parameterNames = new string[paramCount];
                for (var p = 0; p < paramCount; p++)
                    parameterNames[p] = source.Substring(pNameStart[p], pNameLen[p]);

                var bodyBrace = FindFunctionBodyBrace(ck, n, funcIndex);
                if (bodyBrace < 0)
                    return false;

                var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
                var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
                var bres = new int[2];
                var bodyNodeCount = bindings.ParseStatementNodes(
                    ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
                if (bodyNodeCount <= 0)
                    return false;

                var bodyNodes = new ColumnarNodeTable(bk, bvs, bvl, bcs, bcc, bci);
                var resolver = new ColumnarNameResolver(bodyNodes, source, parameterNames, functionNames);
                perFunctionRefs.Add(resolver.Resolve(bres[0]));
            }

            return true;
        }
        catch
        {
            perFunctionRefs = new List<List<ColumnarNameRef>>();
            return false;
        }
    }

    internal static bool TryInferTopLevelFunctionTypes(string source, out List<List<string>> perFunctionTypes)
    {
        perFunctionTypes = new List<List<string>>();

        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

        try
        {
            if (!TryTokenizeColumnarSource(bindings, source, out var tokens))
                return false;

            if (!TryGetTopLevelFunctionDeclarationIndices(source, tokens, out _, out var functionDeclarationIndices))
                return false;

            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            var funcIndices = TopLevelFuncIndices(ck, n);
            if (funcIndices.Count != functionDeclarationIndices.Count)
                return false;

            var cap = n + 1;
            var perFunctionParameterTypes = new List<Dictionary<string, string>>(funcIndices.Count);
            var functionReturnTypes = new Dictionary<string, List<ColumnarFunctionReturnSignature>>(StringComparer.Ordinal);
            foreach (var funcIndex in funcIndices)
            {
                var sk = new int[cap]; var sns = new int[cap]; var snl = new int[cap]; var scs = new int[cap];
                var scc = new int[cap]; var sci = new int[cap]; var sss = new int[cap]; var ssl = new int[cap];
                var pNameStart = new int[cap]; var pNameLen = new int[cap]; var pTypeRoot = new int[cap];
                var sres = new int[8];
                var sTypeParamStarts = new int[cap];
                var sTypeParamLengths = new int[cap];
                var sWhereNameStarts = new int[cap];
                var sWhereNameLengths = new int[cap];
                var sWhereItemCodes = new int[cap];
                var paramCount = bindings.ParseFunctionSignature(
                    ck, cs, cv, n, funcIndex, sk, sns, snl, scs, scc, sci, sss, ssl,
                    pNameStart, pNameLen, pTypeRoot, sTypeParamStarts, sTypeParamLengths,
                    sWhereNameStarts, sWhereNameLengths, sWhereItemCodes, sres);
                if (paramCount < 0 || sres[3] < 0)
                    return false;

                var paramTypes = new Dictionary<string, string>(StringComparer.Ordinal);
                var signatureParameterTypes = new string[paramCount];
                for (var p = 0; p < paramCount; p++)
                {
                    var parameterType = ColumnarTypeCanon(sk, sns, snl, scs, scc, sci, source, pTypeRoot[p]);
                    paramTypes[source.Substring(pNameStart[p], pNameLen[p])] = parameterType;
                    signatureParameterTypes[p] = parameterType;
                }
                perFunctionParameterTypes.Add(paramTypes);

                var name = source.Substring(sres[3], sres[4]);
                var returnType = sres[1] >= 0 ? ColumnarTypeCanon(sk, sns, snl, scs, scc, sci, source, sres[1]) : "void";
                if (!functionReturnTypes.TryGetValue(name, out var overloads))
                {
                    overloads = new List<ColumnarFunctionReturnSignature>();
                    functionReturnTypes[name] = overloads;
                }
                overloads.Add(new ColumnarFunctionReturnSignature(signatureParameterTypes, returnType));
            }

            for (var fi = 0; fi < funcIndices.Count; fi++)
            {
                var bodyBrace = FindFunctionBodyBrace(ck, n, funcIndices[fi]);
                if (bodyBrace < 0)
                    return false;

                var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
                var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
                var bres = new int[2];
                var bodyNodeCount = bindings.ParseStatementNodes(
                    ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
                if (bodyNodeCount <= 0)
                    return false;

                var bodyNodes = new ColumnarNodeTable(bk, bvs, bvl, bcs, bcc, bci);
                var inferer = new ColumnarTypeInferer(
                    bodyNodes, source, perFunctionParameterTypes[fi], functionReturnTypes);
                perFunctionTypes.Add(inferer.Infer(bres[0]));
            }

            return true;
        }
        catch
        {
            perFunctionTypes = new List<List<string>>();
            return false;
        }
    }

    internal static bool TryCollectTopLevelFunctionDiagnostics(string source, out List<List<string>> perFunctionDiagnostics)
    {
        perFunctionDiagnostics = new List<List<string>>();

        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

        try
        {
            if (!TryTokenizeColumnarSource(bindings, source, out var tokens))
                return false;

            if (!TryGetTopLevelFunctionDeclarationIndices(source, tokens, out var declCount, out var functionDeclarationIndices))
                return false;

            var rawKinds = tokens.RawKinds;
            var rawStarts = tokens.RawStarts;
            var rawLines = tokens.RawLines;
            var rawColumns = tokens.RawColumns;
            var rawCount = tokens.RawCount;
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            var funcIndices = TopLevelFuncIndices(ck, n);
            if (funcIndices.Count != functionDeclarationIndices.Count)
                return false;

            var cap = n + 1;
            var modKinds = new int[rawCount + 1];
            var modFlags = new int[rawCount + 1];
            var modCount = bindings.TopLevelDeclarationModifiers(rawKinds, rawCount, modKinds, modFlags);
            if (modCount != declCount)
                return false;
            const int asyncOrGenerator = (int)(Modifiers.Async | Modifiers.Generator);
            for (var i = 0; i < functionDeclarationIndices.Count; i++)
            {
                if ((modFlags[functionDeclarationIndices[i]] & asyncOrGenerator) != 0)
                    return false;
            }

            var perFunctionReturnType = new List<string>(funcIndices.Count);
            foreach (var funcIndex in funcIndices)
            {
                var sk = new int[cap]; var sns = new int[cap]; var snl = new int[cap]; var scs = new int[cap];
                var scc = new int[cap]; var sci = new int[cap]; var sss = new int[cap]; var ssl = new int[cap];
                var pNameStart = new int[cap]; var pNameLen = new int[cap]; var pTypeRoot = new int[cap];
                var sres = new int[8];
                var sTypeParamStarts = new int[cap];
                var sTypeParamLengths = new int[cap];
                var sWhereNameStarts = new int[cap];
                var sWhereNameLengths = new int[cap];
                var sWhereItemCodes = new int[cap];
                var paramCount = bindings.ParseFunctionSignature(
                    ck, cs, cv, n, funcIndex, sk, sns, snl, scs, scc, sci, sss, ssl,
                    pNameStart, pNameLen, pTypeRoot, sTypeParamStarts, sTypeParamLengths,
                    sWhereNameStarts, sWhereNameLengths, sWhereItemCodes, sres);
                if (paramCount < 0 || sres[3] < 0)
                    return false;

                perFunctionReturnType.Add(sres[1] >= 0
                    ? ColumnarTypeCanon(sk, sns, snl, scs, scc, sci, source, sres[1])
                    : "void");
            }

            var lineColByOffset = new Dictionary<int, (int Line, int Column)>(rawCount);
            for (var i = 0; i < rawCount; i++)
                lineColByOffset[rawStarts[i]] = (rawLines[i], rawColumns[i]);
            (int Line, int Column) PositionOf(int offset)
                => lineColByOffset.TryGetValue(offset, out var lc) ? lc : (0, 0);

            for (var fi = 0; fi < funcIndices.Count; fi++)
            {
                var bodyBrace = FindFunctionBodyBrace(ck, n, funcIndices[fi]);
                if (bodyBrace < 0)
                    return false;

                var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
                var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
                var bres = new int[2];
                var bodyNodeCount = bindings.ParseStatementNodes(
                    ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
                if (bodyNodeCount <= 0)
                    return false;

                var bodyNodes = new ColumnarNodeTable(bk, bvs, bvl, bcs, bcc, bci, bss);
                var pass = new ColumnarDiagnosticsPass(bodyNodes, source, PositionOf);
                perFunctionDiagnostics.Add(pass.Analyze(bres[0], perFunctionReturnType[fi]));
            }

            return true;
        }
        catch
        {
            perFunctionDiagnostics = new List<List<string>>();
            return false;
        }
    }

    internal static bool TryCollectUnusedLocals(string source, out List<List<string>> perFunctionUnusedLocals)
    {
        perFunctionUnusedLocals = new List<List<string>>();

        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

        try
        {
            if (!TryTokenizeColumnarSource(bindings, source, out var tokens))
                return false;

            if (!TryGetTopLevelFunctionDeclarationIndices(source, tokens, out _, out var functionDeclarationIndices))
                return false;

            var rawStarts = tokens.RawStarts;
            var rawLines = tokens.RawLines;
            var rawColumns = tokens.RawColumns;
            var rawCount = tokens.RawCount;
            var ck = tokens.Kinds;
            var cs = tokens.Starts;
            var cv = tokens.ValueLengths;
            var n = tokens.Count;

            var funcIndices = TopLevelFuncIndices(ck, n);
            if (funcIndices.Count != functionDeclarationIndices.Count)
                return false;

            var lineColByOffset = new Dictionary<int, (int Line, int Column)>(rawCount);
            for (var i = 0; i < rawCount; i++)
                lineColByOffset[rawStarts[i]] = (rawLines[i], rawColumns[i]);
            (int Line, int Column) PositionOf(int offset)
                => lineColByOffset.TryGetValue(offset, out var lc) ? lc : (0, 0);

            var cap = n + 1;
            var usedNames = new HashSet<string>(StringComparer.Ordinal);
            foreach (var funcIndex in funcIndices)
            {
                var sk = new int[cap]; var sns = new int[cap]; var snl = new int[cap]; var scs = new int[cap];
                var scc = new int[cap]; var sci = new int[cap]; var sss = new int[cap]; var ssl = new int[cap];
                var pNameStart = new int[cap]; var pNameLen = new int[cap]; var pTypeRoot = new int[cap];
                var sres = new int[8];
                var sTypeParamStarts = new int[cap];
                var sTypeParamLengths = new int[cap];
                var sWhereNameStarts = new int[cap];
                var sWhereNameLengths = new int[cap];
                var sWhereItemCodes = new int[cap];
                var paramCount = bindings.ParseFunctionSignature(
                    ck, cs, cv, n, funcIndex, sk, sns, snl, scs, scc, sci, sss, ssl,
                    pNameStart, pNameLen, pTypeRoot, sTypeParamStarts, sTypeParamLengths,
                    sWhereNameStarts, sWhereNameLengths, sWhereItemCodes, sres);
                if (paramCount < 0 || sres[3] < 0)
                    return false;
                for (var p = 0; p < paramCount; p++)
                    usedNames.Add(source.Substring(pNameStart[p], pNameLen[p]));

                var bodyBrace = FindFunctionBodyBrace(ck, n, funcIndex);
                if (bodyBrace < 0)
                    return false;

                var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
                var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
                var bres = new int[2];
                var bodyNodeCount = bindings.ParseStatementNodes(
                    ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
                if (bodyNodeCount <= 0)
                    return false;

                var unused = new List<string>();
                var bodyNodes = new ColumnarNodeTable(bk, bvs, bvl, bcs, bcc, bci, bss);
                var pass = new ColumnarDiagnosticsPass(bodyNodes, source, PositionOf);
                pass.CollectUnusedLocals(bres[0], usedNames, unused);
                perFunctionUnusedLocals.Add(unused);
            }

            return true;
        }
        catch
        {
            perFunctionUnusedLocals = new List<List<string>>();
            return false;
        }
    }

    private static bool TryGetTopLevelFunctionDeclarationIndices(
        string source,
        ColumnarTokenizedSource tokens,
        out int declarationCount,
        out List<int> functionDeclarationIndices)
    {
        declarationCount = 0;
        functionDeclarationIndices = new List<int>();

        if (HasTopLevelContextualTestDeclaration(
                source, tokens.RawKinds, tokens.RawStarts, tokens.RawValueLengths, tokens.RawCount))
            return false;

        declarationCount = tokens.DeclarationCount;
        if (declarationCount < 0)
            return false;

        for (var i = 0; i < declarationCount; i++)
        {
            if (tokens.DeclarationKinds[i] == 7)
                functionDeclarationIndices.Add(i);
        }

        return true;
    }

    private static bool TryTokenizeColumnarSource(Bindings bindings, string source, out ColumnarTokenizedSource tokens)
    {
        tokens = null!;
        try
        {
            var capacity = 3 * (source.Length + 1) + 8;
            var rawKinds = new int[capacity];
            var rawStarts = new int[capacity];
            var rawValueLengths = new int[capacity];
            var rawLines = new int[capacity];
            var rawColumns = new int[capacity];
            var rawCount = bindings.TokenizeMetadataWithIndentation(
                source, rawKinds, rawStarts, rawValueLengths, rawLines, rawColumns);
            if (rawCount < 0 || rawCount > capacity)
                return false;

            var declarationKinds = new int[rawCount + 1];
            var declarationCount = bindings.TopLevelDeclarationKinds(rawKinds, rawCount, declarationKinds);
            if (declarationCount < 0)
                return false;

            var kinds = new int[rawCount];
            var starts = new int[rawCount];
            var valueLengths = new int[rawCount];
            var count = 0;
            for (var i = 0; i < rawCount; i++)
            {
                if (rawKinds[i] == (int)TokenType.Newline)
                    continue;
                kinds[count] = rawKinds[i];
                starts[count] = rawStarts[i];
                valueLengths[count] = rawValueLengths[i];
                count++;
            }

            tokens = new ColumnarTokenizedSource(
                rawKinds, rawStarts, rawValueLengths, rawLines, rawColumns, rawCount,
                kinds, starts, valueLengths, count,
                declarationKinds, declarationCount);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static int FindFunctionBodyBrace(int[] kinds, int count, int funcIndex)
    {
        for (var t = funcIndex + 1; t < count; t++)
        {
            if (kinds[t] == (int)TokenType.LeftBrace)
                return t;
        }

        return -1;
    }

    private static bool HasTopLevelContextualTestDeclaration(
        string source,
        int[] rawKinds,
        int[] rawStarts,
        int[] rawValueLengths,
        int rawCount)
    {
        var braceDepth = 0;
        var bracketDepth = 0;
        var parenDepth = 0;

        for (var i = 0; i < rawCount; i++)
        {
            var kind = rawKinds[i];
            if (braceDepth == 0 && bracketDepth == 0 && parenDepth == 0)
            {
                if (kind == (int)TokenType.Test)
                    return true;

                if (kind == (int)TokenType.Identifier)
                {
                    var nextKind = NextNonNewlineTokenKind(rawKinds, rawCount, i + 1);
                    var atDeclarationBoundary = IsTopLevelDeclarationBoundaryBefore(rawKinds, i);

                    if (TokenTextEquals(source, rawStarts[i], rawValueLengths[i], "test")
                        && (nextKind == (int)TokenType.StringLiteral
                            || nextKind == (int)TokenType.LeftBrace
                            || atDeclarationBoundary))
                        return true;

                    if ((TokenTextEquals(source, rawStarts[i], rawValueLengths[i], "setup")
                            || TokenTextEquals(source, rawStarts[i], rawValueLengths[i], "teardown"))
                        && (nextKind == (int)TokenType.LeftBrace || atDeclarationBoundary))
                        return true;
                }
            }

            if (kind == (int)TokenType.LeftBrace)
            {
                braceDepth++;
            }
            else if (kind == (int)TokenType.RightBrace)
            {
                braceDepth--;
                if (braceDepth < 0)
                    braceDepth = 0;
            }
            else if (kind == (int)TokenType.LeftBracket)
            {
                bracketDepth++;
            }
            else if (kind == (int)TokenType.RightBracket)
            {
                bracketDepth--;
                if (bracketDepth < 0)
                    bracketDepth = 0;
            }
            else if (kind == (int)TokenType.LeftParen)
            {
                parenDepth++;
            }
            else if (kind == (int)TokenType.RightParen)
            {
                parenDepth--;
                if (parenDepth < 0)
                    parenDepth = 0;
            }
        }

        return false;
    }

    private static int NextNonNewlineTokenKind(int[] rawKinds, int rawCount, int startIndex)
    {
        for (var i = startIndex; i < rawCount; i++)
        {
            if (rawKinds[i] != (int)TokenType.Newline)
                return rawKinds[i];
        }

        return -1;
    }

    private static bool IsTopLevelDeclarationBoundaryBefore(int[] rawKinds, int index)
    {
        if (index <= 0)
            return true;

        var previousKind = rawKinds[index - 1];
        return previousKind == (int)TokenType.Newline
            || previousKind == (int)TokenType.RightBrace
            || previousKind == (int)TokenType.Semicolon;
    }

    private static bool TokenTextEquals(string source, int start, int length, string expected)
    {
        return start >= 0
            && length == expected.Length
            && start + length <= source.Length
            && string.CompareOrdinal(source, start, expected, 0, expected.Length) == 0;
    }

    private static string ColumnarTypeCanon(
        int[] kinds, int[] valueStarts, int[] valueLengths, int[] childStart, int[] childCount, int[] childIndices,
        string source, int idx)
    {
        switch (kinds[idx])
        {
            case 0:
                return source.Substring(valueStarts[idx], valueLengths[idx]);
            case 1:
            {
                var sb = new StringBuilder();
                sb.Append(source, valueStarts[idx], valueLengths[idx]).Append('<');
                var run = childStart[idx];
                for (var k = 0; k < childCount[idx]; k++)
                {
                    if (k > 0) sb.Append(',');
                    sb.Append(ColumnarTypeCanon(kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, childIndices[run + k]));
                }

                sb.Append('>');
                return sb.ToString();
            }
            case 2:
                return ColumnarTypeCanon(kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, childIndices[childStart[idx]]) + "[]";
            case 3:
                return ColumnarTypeCanon(kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, childIndices[childStart[idx]]) + "?";
            case 4:
            {
                var sb = new StringBuilder();
                var run = childStart[idx];
                for (var k = 0; k < childCount[idx]; k++)
                {
                    if (k > 0) sb.Append('|');
                    sb.Append(ColumnarTypeCanon(kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, childIndices[run + k]));
                }

                return sb.ToString();
            }
            case 5:
                return "&" + ColumnarTypeCanon(kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, childIndices[childStart[idx]]);
            case 6:
            {
                var sb = new StringBuilder();
                sb.Append('(');
                var run = childStart[idx];
                for (var k = 0; k < childCount[idx]; k++)
                {
                    if (k > 0) sb.Append(',');
                    var elem = childIndices[run + k];
                    if (kinds[elem] == 7)
                        elem = childIndices[childStart[elem]];
                    sb.Append(ColumnarTypeCanon(kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, elem));
                }

                sb.Append(')');
                return sb.ToString();
            }
            default:
                return "?";
        }
    }

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
                case (int)TokenType.LeftBrace: brace++; break;
                case (int)TokenType.RightBrace: if (brace > 0) brace--; break;
                case (int)TokenType.LeftBracket: bracket++; break;
                case (int)TokenType.RightBracket: if (bracket > 0) bracket--; break;
                case (int)TokenType.LeftParen: paren++; break;
                case (int)TokenType.RightParen: if (paren > 0) paren--; break;
                case (int)TokenType.Func:
                    if (brace == 0 && bracket == 0 && paren == 0) result.Add(i);
                    break;
            }
        }

        return result;
    }

    private static Bindings? LoadBindings()
    {
        try
        {
            var scope = TryLoadDogfoodAssembly();
            if (scope == null)
                return null;

            var programType = scope.Assembly.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                scope,
                CreateDelegate<TokenizeMetadataWithIndentationInto>(programType, "TokenizeMetadataWithIndentationInto"),
                CreateDelegate<TopLevelDeclarationKindsInto>(programType, "TopLevelDeclarationKindsInto"),
                CreateDelegate<TopLevelDeclarationModifiersInto>(programType, "TopLevelDeclarationModifiersInto"),
                CreateDelegate<TopLevelDeclarationNameSpansInto>(programType, "TopLevelDeclarationNameSpansInto"),
                CreateDelegate<ParseFunctionSignatureInto>(programType, "ParseFunctionSignatureInto"),
                CreateDelegate<ParseStatementNodesInto>(programType, "ParseStatementNodesInto"));
        }
        catch
        {
            return null;
        }
    }

    private static CollectibleAssemblyScope? TryLoadDogfoodAssembly()
    {
        var assemblyPath = Path.Combine(AppContext.BaseDirectory, $"{DogfoodAssemblyName}.dll");
        return File.Exists(assemblyPath)
            ? CollectibleAssemblyScope.LoadFromFile(assemblyPath)
            : null;
    }

    private static TDelegate CreateDelegate<TDelegate>(Type programType, string methodName)
        where TDelegate : Delegate
    {
        var method = programType.GetMethod(
                methodName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new MissingMethodException(programType.FullName, methodName);

        return (TDelegate)Delegate.CreateDelegate(typeof(TDelegate), method);
    }

    private sealed class ColumnarTokenizedSource(
        int[] rawKinds,
        int[] rawStarts,
        int[] rawValueLengths,
        int[] rawLines,
        int[] rawColumns,
        int rawCount,
        int[] kinds,
        int[] starts,
        int[] valueLengths,
        int count,
        int[] declarationKinds,
        int declarationCount)
    {
        internal int[] RawKinds { get; } = rawKinds;
        internal int[] RawStarts { get; } = rawStarts;
        internal int[] RawValueLengths { get; } = rawValueLengths;
        internal int[] RawLines { get; } = rawLines;
        internal int[] RawColumns { get; } = rawColumns;
        internal int RawCount { get; } = rawCount;
        internal int[] Kinds { get; } = kinds;
        internal int[] Starts { get; } = starts;
        internal int[] ValueLengths { get; } = valueLengths;
        internal int Count { get; } = count;
        internal int[] DeclarationKinds { get; } = declarationKinds;
        internal int DeclarationCount { get; } = declarationCount;
    }

    private delegate int TokenizeMetadataWithIndentationInto(
        string source, int[] kinds, int[] starts, int[] valueLengths, int[] lines, int[] columns);
    private delegate int TopLevelDeclarationKindsInto(int[] tokenKinds, int count, int[] outKinds);
    private delegate int TopLevelDeclarationModifiersInto(int[] tokenKinds, int count, int[] outKinds, int[] outModifiers);
    private delegate int TopLevelDeclarationNameSpansInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count,
        int[] outKinds, int[] outNameStarts, int[] outNameLengths);
    private delegate int ParseFunctionSignatureInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int funcIndex,
        int[] outNodeKinds, int[] outNameStarts, int[] outNameLengths, int[] outChildStart, int[] outChildCount,
        int[] outChildIndices, int[] outSpanStarts, int[] outSpanLengths,
        int[] outParamNameStarts, int[] outParamNameLengths, int[] outParamTypeRoots,
        int[] outTypeParamStarts, int[] outTypeParamLengths,
        int[] outWhereNameStarts, int[] outWhereNameLengths, int[] outWhereItemCodes, int[] outResult);
    private delegate int ParseStatementNodesInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int start,
        int[] outNodeKinds, int[] outValueStarts, int[] outValueLengths, int[] outChildStart, int[] outChildCount,
        int[] outChildIndices, int[] outSpanStarts, int[] outSpanLengths, int[] outResult);

    private sealed record Bindings(
        CollectibleAssemblyScope AssemblyScope,
        TokenizeMetadataWithIndentationInto TokenizeMetadataWithIndentation,
        TopLevelDeclarationKindsInto TopLevelDeclarationKinds,
        TopLevelDeclarationModifiersInto TopLevelDeclarationModifiers,
        TopLevelDeclarationNameSpansInto TopLevelDeclarationNameSpans,
        ParseFunctionSignatureInto ParseFunctionSignature,
        ParseStatementNodesInto ParseStatementNodes);
}
