using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

internal static class NSharpCompilerDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    private static readonly ConditionalWeakTable<SemanticModel, SemanticScopeCache> s_semanticScopeCaches = new();
    [ThreadStatic]
    private static ParserTokenCompactionScratch? t_parserTokenCompactionScratch;
    [ThreadStatic]
    private static FirstDistinctTypeKeyScratch? t_firstDistinctTypeKeyScratch;
    [ThreadStatic]
    private static FirstDistinctStringScratch? t_firstDistinctStringScratch;
    [ThreadStatic]
    private static DistinctOrderedStringScratch? t_distinctOrderedStringScratch;
    [ThreadStatic]
    private static DeclaredTypeSuffixLookupScratch? t_declaredTypeSuffixLookupScratch;
    [ThreadStatic]
    private static DeclaredTypeNameCandidateScratch? t_declaredTypeNameCandidateScratch;
    [ThreadStatic]
    private static TypeCreationOrderScratch? t_typeCreationOrderScratch;
    [ThreadStatic]
    private static AnonymousUnionShimScratch? t_anonymousUnionShimScratch;
    [ThreadStatic]
    private static MissingEnumMemberScratch? t_missingEnumMemberScratch;
    [ThreadStatic]
    private static MissingUnionCaseScratch? t_missingUnionCaseScratch;
    [ThreadStatic]
    private static FormatterImportOrderingScratch? t_formatterImportOrderingScratch;
    [ThreadStatic]
    private static ProjectSourceFilterScratch? t_projectSourceFilterScratch;
    [ThreadStatic]
    private static OverloadCandidateScratch? t_overloadCandidateScratch;

    internal static bool IsAvailable => s_bindings.Value != null;

    /// <summary>
    /// COLUMNAR PIPELINE — stage 1 (docs/design/columnar-pipeline.md). Builds the top-level function
    /// declared-symbol model (name, modifiers, canonical parameter + return type signatures) DIRECTLY from the
    /// columnar declaration + signature tables, WITHOUT materializing the C# AST. This is the declared-symbol
    /// foundation name resolution queries. Returns false (so callers keep the C# binder) for any non-function
    /// top-level declaration or kernel refusal. Canonical type strings match
    /// <see cref="Columnar.ColumnarFunctionSymbol.CanonicalType"/> exactly for parity.
    /// </summary>
    internal static bool TryBuildTopLevelFunctionSymbols(string source, out List<Columnar.ColumnarFunctionSymbol> symbols)
    {
        symbols = new List<Columnar.ColumnarFunctionSymbol>();

        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

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

            var declKinds = new int[rawCount + 1];
            var declCount = bindings.TopLevelDeclarationKinds(rawKinds, rawCount, declKinds);
            if (declCount < 0)
                return false;
            for (var i = 0; i < declCount; i++)
            {
                if (declKinds[i] != 7)
                    return false;
            }

            // Per-declaration modifier flags ((int)Declaration.Modifiers); all decls are functions here.
            var modKinds = new int[rawCount + 1];
            var modFlags = new int[rawCount + 1];
            var modCount = bindings.TopLevelDeclarationModifiers(rawKinds, rawCount, modKinds, modFlags);
            if (modCount != declCount)
                return false;

            var ck = new int[rawCount];
            var cs = new int[rawCount];
            var cv = new int[rawCount];
            var n = 0;
            for (var i = 0; i < rawCount; i++)
            {
                if (rawKinds[i] == 136)
                    continue;
                ck[n] = rawKinds[i];
                cs[n] = rawStarts[i];
                cv[n] = rawValueLengths[i];
                n++;
            }

            var funcIndices = TopLevelFuncIndices(ck, n);
            if (funcIndices.Count != declCount)
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

                symbols.Add(new Columnar.ColumnarFunctionSymbol(name, modFlags[fi], parameterTypes, returnType));
            }

            return true;
        }
        catch
        {
            symbols = new List<Columnar.ColumnarFunctionSymbol>();
            return false;
        }
    }

    /// <summary>
    /// COLUMNAR PIPELINE — stage 2 (docs/design/columnar-pipeline.md). Lexical name resolution over the
    /// columnar tables (no C# AST): for each top-level function, the binding classification of every bare
    /// identifier in its body (parameter / local / function / not-in-scope), in pre-order. All top-level
    /// functions are pre-declared so forward references resolve. Returns false (C# fallback) for any
    /// non-function declaration or kernel refusal.
    /// </summary>
    internal static bool TryResolveTopLevelFunctionNames(string source, out List<List<Columnar.ColumnarNameRef>> perFunctionRefs)
    {
        perFunctionRefs = new List<List<Columnar.ColumnarNameRef>>();

        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

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

            var declKinds = new int[rawCount + 1];
            var declCount = bindings.TopLevelDeclarationKinds(rawKinds, rawCount, declKinds);
            if (declCount < 0)
                return false;
            for (var i = 0; i < declCount; i++)
            {
                if (declKinds[i] != 7)
                    return false;
            }

            // All top-level function names, pre-declared (forward references resolve).
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
                if (nameStarts[i] >= 0)
                    functionNames.Add(source.Substring(nameStarts[i], nameLengths[i]));
            }

            var ck = new int[rawCount];
            var cs = new int[rawCount];
            var cv = new int[rawCount];
            var n = 0;
            for (var i = 0; i < rawCount; i++)
            {
                if (rawKinds[i] == 136)
                    continue;
                ck[n] = rawKinds[i];
                cs[n] = rawStarts[i];
                cv[n] = rawValueLengths[i];
                n++;
            }

            var funcIndices = TopLevelFuncIndices(ck, n);
            if (funcIndices.Count != declCount)
                return false;

            var cap = n + 1;
            foreach (var funcIndex in funcIndices)
            {
                // Signature kernel → parameter names.
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

                // Statement kernel → body table.
                var bodyBrace = -1;
                for (var t = funcIndex + 1; t < n; t++)
                {
                    if (ck[t] == 129) { bodyBrace = t; break; }
                }
                if (bodyBrace < 0)
                    return false;

                var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
                var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
                var bres = new int[2];
                var bodyNodeCount = bindings.ParseStatementNodes(
                    ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
                if (bodyNodeCount <= 0)
                    return false;

                var resolver = new Columnar.ColumnarNameResolver(
                    bk, bvs, bvl, bcs, bcc, bci, source, parameterNames, functionNames);
                perFunctionRefs.Add(resolver.Resolve(bres[0]));
            }

            return true;
        }
        catch
        {
            perFunctionRefs = new List<List<Columnar.ColumnarNameRef>>();
            return false;
        }
    }

    /// <summary>
    /// COLUMNAR PIPELINE — stage 3 (docs/design/columnar-pipeline.md). Expression type inference over the
    /// columnar tables (no C# AST): for each top-level function, the inferred canonical type of every
    /// expression in its body (post-order). Two passes: (1) every function's signature → the function-return-
    /// type map (so calls infer their return type, incl. forward refs); (2) per function, infer the body with
    /// its parameter types + the shared function map. Pure-N# surface is inferred; BCL forms yield "External".
    /// Fallback-safe (false for any non-function declaration or kernel refusal).
    /// </summary>
    internal static bool TryInferTopLevelFunctionTypes(string source, out List<List<string>> perFunctionTypes)
    {
        perFunctionTypes = new List<List<string>>();

        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

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

            var declKinds = new int[rawCount + 1];
            var declCount = bindings.TopLevelDeclarationKinds(rawKinds, rawCount, declKinds);
            if (declCount < 0)
                return false;
            for (var i = 0; i < declCount; i++)
            {
                if (declKinds[i] != 7)
                    return false;
            }

            var ck = new int[rawCount];
            var cs = new int[rawCount];
            var cv = new int[rawCount];
            var n = 0;
            for (var i = 0; i < rawCount; i++)
            {
                if (rawKinds[i] == 136)
                    continue;
                ck[n] = rawKinds[i];
                cs[n] = rawStarts[i];
                cv[n] = rawValueLengths[i];
                n++;
            }

            var funcIndices = TopLevelFuncIndices(ck, n);
            if (funcIndices.Count != declCount)
                return false;

            var cap = n + 1;

            // Pass 1: each function's signature → parameter types + the shared function-return-type map.
            var perFunctionParameterTypes = new List<Dictionary<string, string>>(funcIndices.Count);
            var functionReturnTypes = new Dictionary<string, string>(StringComparer.Ordinal);
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
                for (var p = 0; p < paramCount; p++)
                    paramTypes[source.Substring(pNameStart[p], pNameLen[p])] = ColumnarTypeCanon(sk, sns, snl, scs, scc, sci, source, pTypeRoot[p]);
                perFunctionParameterTypes.Add(paramTypes);

                var name = source.Substring(sres[3], sres[4]);
                functionReturnTypes[name] = sres[1] >= 0 ? ColumnarTypeCanon(sk, sns, snl, scs, scc, sci, source, sres[1]) : "void";
            }

            // Pass 2: infer each body with its parameter types + the function-return-type map.
            for (var fi = 0; fi < funcIndices.Count; fi++)
            {
                var funcIndex = funcIndices[fi];
                var bodyBrace = -1;
                for (var t = funcIndex + 1; t < n; t++)
                {
                    if (ck[t] == 129) { bodyBrace = t; break; }
                }
                if (bodyBrace < 0)
                    return false;

                var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
                var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
                var bres = new int[2];
                var bodyNodeCount = bindings.ParseStatementNodes(
                    ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
                if (bodyNodeCount <= 0)
                    return false;

                var inferer = new Columnar.ColumnarTypeInferer(
                    bk, bvs, bvl, bcs, bcc, bci, source, perFunctionParameterTypes[fi], functionReturnTypes);
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

    // COLUMNAR PIPELINE stage 3b (docs/design/columnar-pipeline.md): pure-structural diagnostics over the
    // columnar statement tables — no C# AST. This slice emits definite-return (NL305). Per function, the
    // descriptor list is empty or ["missing-return:<canonicalReturnType>"]. Reuses the stage-3 parse scaffold;
    // declines (false → C# fallback) on any unsupported form, exactly like the stage-3 inferer, and
    // additionally on async/generator functions whose NL305 exemptions it cannot model (see below).
    internal static bool TryCollectTopLevelFunctionDiagnostics(string source, out List<List<string>> perFunctionDiagnostics)
    {
        perFunctionDiagnostics = new List<List<string>>();

        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

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

            var declKinds = new int[rawCount + 1];
            var declCount = bindings.TopLevelDeclarationKinds(rawKinds, rawCount, declKinds);
            if (declCount < 0)
                return false;
            for (var i = 0; i < declCount; i++)
            {
                if (declKinds[i] != 7)
                    return false;
            }

            var ck = new int[rawCount];
            var cs = new int[rawCount];
            var cv = new int[rawCount];
            var n = 0;
            for (var i = 0; i < rawCount; i++)
            {
                if (rawKinds[i] == 136)
                    continue;
                ck[n] = rawKinds[i];
                cs[n] = rawStarts[i];
                cv[n] = rawValueLengths[i];
                n++;
            }

            var funcIndices = TopLevelFuncIndices(ck, n);
            if (funcIndices.Count != declCount)
                return false;

            var cap = n + 1;

            // Async / generator functions carry the real analyzer's isAsyncUnitTask / isIterator NL305
            // exemptions (Analyzer.cs:642-643) — `async func f(): Task {}` and `func* g(): int {}` get NO
            // missing-return, which depends on BCL task-type knowledge this structural pass does not model.
            // Decline so the C# analyzer handles them; the dogfood corpus has none, so coverage is unaffected.
            var modKinds = new int[rawCount + 1];
            var modFlags = new int[rawCount + 1];
            var modCount = bindings.TopLevelDeclarationModifiers(rawKinds, rawCount, modKinds, modFlags);
            if (modCount != declCount)
                return false;
            const int asyncOrGenerator = (int)(Modifiers.Async | Modifiers.Generator);
            for (var i = 0; i < declCount; i++)
            {
                if ((modFlags[i] & asyncOrGenerator) != 0)
                    return false;
            }

            // Pass 1: each function's canonical return type ("void" when omitted) — the only signal definite-return needs.
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

            // Byte-offset -> (line, column) from the tokenizer's own per-token metadata, so the unreachable
            // diagnostic's reported position is the exact line/col the parser records — matching the C# AST.
            var lineColByOffset = new Dictionary<int, (int Line, int Column)>(rawCount);
            for (var i = 0; i < rawCount; i++)
                lineColByOffset[rawStarts[i]] = (rawLines[i], rawColumns[i]);
            (int Line, int Column) PositionOf(int offset)
                => lineColByOffset.TryGetValue(offset, out var lc) ? lc : (0, 0);

            // Pass 2: structural diagnostics over each body.
            for (var fi = 0; fi < funcIndices.Count; fi++)
            {
                var funcIndex = funcIndices[fi];
                var bodyBrace = -1;
                for (var t = funcIndex + 1; t < n; t++)
                {
                    if (ck[t] == 129) { bodyBrace = t; break; }
                }
                if (bodyBrace < 0)
                    return false;

                var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
                var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
                var bres = new int[2];
                var bodyNodeCount = bindings.ParseStatementNodes(
                    ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
                if (bodyNodeCount <= 0)
                    return false;

                var pass = new Columnar.ColumnarDiagnosticsPass(bk, bvs, bvl, bcs, bcc, bci, bss, source, PositionOf);
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

    // COLUMNAR PIPELINE stage 3b-iii (docs/design/columnar-pipeline.md): unused-local (NL001, "declared but
    // never read") over the columnar tables — no C# AST. Faithful to the Linter's time-/scope-ordered NL001:
    // functions are processed IN SOURCE ORDER sharing one `usedNames` set that accumulates every identifier
    // use (the analog of the file-level _usedVariables) and is NEVER cleared between functions; each function's
    // parameter names are added before its body is walked (params are always "used"); and each Block's `:=`
    // locals are checked at the Block's exit against usedNames AS OF THEN (so a use after the block closes — a
    // later sibling block or later function — does not suppress it, while an earlier use does). The walk lives
    // in ColumnarDiagnosticsPass.CollectUnusedLocals. Interpolated strings ($"...{x}...") cannot hide a use:
    // the kernel refuses them, so such sources decline here (bodyNodeCount <= 0) to the C# linter.
    internal static bool TryCollectUnusedLocals(string source, out List<List<string>> perFunctionUnusedLocals)
    {
        perFunctionUnusedLocals = new List<List<string>>();

        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

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

            var declKinds = new int[rawCount + 1];
            var declCount = bindings.TopLevelDeclarationKinds(rawKinds, rawCount, declKinds);
            if (declCount < 0)
                return false;
            for (var i = 0; i < declCount; i++)
            {
                if (declKinds[i] != 7)
                    return false;
            }

            var ck = new int[rawCount];
            var cs = new int[rawCount];
            var cv = new int[rawCount];
            var n = 0;
            for (var i = 0; i < rawCount; i++)
            {
                if (rawKinds[i] == 136)
                    continue;
                ck[n] = rawKinds[i];
                cs[n] = rawStarts[i];
                cv[n] = rawValueLengths[i];
                n++;
            }

            var funcIndices = TopLevelFuncIndices(ck, n);
            if (funcIndices.Count != declCount)
                return false;

            var lineColByOffset = new Dictionary<int, (int Line, int Column)>(rawCount);
            for (var i = 0; i < rawCount; i++)
                lineColByOffset[rawStarts[i]] = (rawLines[i], rawColumns[i]);
            (int Line, int Column) PositionOf(int offset)
                => lineColByOffset.TryGetValue(offset, out var lc) ? lc : (0, 0);

            var cap = n + 1;

            // Process functions IN SOURCE ORDER, accumulating usedNames (never cleared) — the Linter's
            // file-level _usedVariables, checked at each block's PopScope in traversal order.
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

                var bodyBrace = -1;
                for (var t = funcIndex + 1; t < n; t++)
                {
                    if (ck[t] == 129) { bodyBrace = t; break; }
                }
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
                var pass = new Columnar.ColumnarDiagnosticsPass(bk, bvs, bvl, bcs, bcc, bci, bss, source, PositionOf);
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

    // COLUMNAR PIPELINE stage 4 SPIKE (docs/design/roadmap-to-done.md): emit a runnable .NET assembly for a
    // single trivial top-level function whose body IL is generated DIRECTLY from the columnar tables (no C# AST).
    // Proof that the columnar pipeline can drive codegen end-to-end. Narrow on purpose (one builtin-typed func;
    // body = a Block of a single Return of a param / int-literal / paren / int +/-/* binary); declines (false,
    // no assembly) on anything else, so the C# path is unaffected. The emitted type is "ColumnarSpike".
    internal static bool TryEmitColumnarFunction(string source, out byte[] assembly, out string typeName, out string methodName)
    {
        assembly = System.Array.Empty<byte>();
        typeName = string.Empty;
        methodName = string.Empty;

        // Single-function entry (the original spike surface): decline anything but exactly one top-level func.
        if (!TryGetColumnarFunctionInputs(source, out var inputs) || inputs.Count != 1)
            return false;
        var fn = inputs[0];
        if (!Columnar.ColumnarIlEmitter.TryEmitSingleFunctionAssembly(
                fn.Name, fn.ReturnCanonical, fn.ParamNames, fn.ParamCanonicals,
                fn.Kinds, fn.ValueStarts, fn.ValueLengths, fn.ChildStart, fn.ChildCount, fn.ChildIndices,
                source, fn.BodyRoot, out assembly))
            return false;
        typeName = "ColumnarSpike";
        methodName = fn.Name;
        return true;
    }

    // Multi-function entry — the standalone columnar backend (the chosen Stage 4j routing: a columnar-first
    // pipeline that owns emission, not a re-parse hook into the C# ILCompiler). Emit EVERY top-level function
    // into one assembly (type "ColumnarProgram") directly from the columnar tables, with NO C# AST; decline the
    // whole program if any function is ineligible. Foundation for sibling calls (4i) and whole-program emission.
    internal static bool TryEmitColumnarProgram(string source, out byte[] assembly, out string typeName, out string[] methodNames)
        => TryEmitColumnarProgram(source, "ColumnarProgram", "ColumnarProgram", out assembly, out typeName, out methodNames);

    // Production-facing entry (Stage 5 routing): emit into an assembly named `assemblyName` and type
    // `typeName`. The MultiFileCompiler uses this (behind a flag) to produce a drop-in replacement for the C#
    // ILCompiler's output — assembly name + type "Program" matching the C# path — for the systems subset it
    // models, falling back to the C# path on decline.
    internal static bool TryEmitColumnarProgram(string source, string assemblyName, string typeName, out byte[] assembly, out string emittedTypeName, out string[] methodNames)
    {
        assembly = System.Array.Empty<byte>();
        emittedTypeName = string.Empty;
        methodNames = System.Array.Empty<string>();

        if (!TryGetColumnarFunctionInputs(source, out var inputs) || inputs.Count == 0)
            return false;
        if (!TryGetColumnarEnumInputs(source, out var enums))
            return false;
        if (!TryGetColumnarStructInputs(source, out var structs))
            return false;
        if (!TryGetColumnarUnionInputs(source, out var unions))
            return false;
        // The columnar emit is a best-effort, DECLINE-on-failure optimization: it must never throw a hard error the
        // authoritative C# path would not. Any unexpected emit exception (e.g. a Reflection.Emit limitation on a
        // not-yet-fully-modelled type shape) is caught here and declines → C# fallback, matching the try/catch the
        // collection helpers already use. A supported program that wrongly declines is caught by the parity tests
        // (which assert Ok == true), so this net cannot silently hide a regression from the gate.
        try
        {
            if (!Columnar.ColumnarIlEmitter.TryEmitColumnarAssembly(assemblyName, typeName, inputs, enums, structs, unions, source, out assembly))
                return false;
        }
        catch
        {
            assembly = System.Array.Empty<byte>();
            return false;
        }

        emittedTypeName = typeName;
        methodNames = new string[inputs.Count];
        for (var i = 0; i < inputs.Count; i++)
            methodNames[i] = inputs[i].Name;
        return true;
    }

    // MULTI-FILE entry (Stage-5 remaining work: the columnar backend was single-file only). The dogfood
    // compiler-service is a MULTI-FILE program — a function in one file calls public functions in others (e.g.
    // ParserFunctionSignatures.ParseFunctionSignatureInto calls ParserTypeReferences.ParseUnionTypeReferenceNode).
    // A single-file emit cannot resolve such a cross-file call (the callee is not a sibling), so those files
    // decline even though every construct they use is modelled. This merges the files by concatenating their
    // sources into ONE columnar program (separated by blank lines so the top-level func scan stays correct);
    // the unified sibling map built in pass 1 then resolves every cross-file call exactly as the C#
    // MultiFileCompiler binds declarations across files. The emitted IL for each function body is independent of
    // how the program is assembled, so the merged program runs identically to the multi-file C# build. Declines
    // (C# fallback) if any file fails to parse or any function is ineligible. LIMITATIONS (none arise for the
    // single-package dogfood corpus, which uses unique PascalCase names; refine if they ever do): (1) two files
    // with a colliding top-level function name decline at the duplicate-name guard rather than being per-file
    // mangled; (2) concatenation flattens files into one scope, so file-private (camelCase) and cross-PACKAGE
    // visibility are NOT enforced — a call the C# build would reject across a package boundary could resolve
    // here. The corpus has no camelCase top-level funcs and is one package, and the multi-file parity oracle
    // (a genuine separate-file MultiFileCompiler build) would surface any such divergence as a compile failure.
    internal static bool TryEmitColumnarProgramMultiFile(
        System.Collections.Generic.IReadOnlyList<string> sources, string assemblyName, string typeName,
        out byte[] assembly, out string emittedTypeName, out string[] methodNames)
    {
        assembly = System.Array.Empty<byte>();
        emittedTypeName = string.Empty;
        methodNames = System.Array.Empty<string>();
        if (sources == null || sources.Count == 0)
            return false;
        var combined = string.Join("\n\n", sources);
        return TryEmitColumnarProgram(combined, assemblyName, typeName, out assembly, out emittedTypeName, out methodNames);
    }

    // Tokenize + compact `source`, require EVERY top-level declaration to be a `func`, and parse each into a
    // ColumnarFunctionInput (signature + body node tables). Returns false on any tokenize/parse failure or a
    // non-func top-level declaration, so the standalone backend declines and the C# path stays authoritative.
    private static bool TryGetColumnarFunctionInputs(string source, out System.Collections.Generic.List<Columnar.ColumnarFunctionInput> inputs)
    {
        inputs = new System.Collections.Generic.List<Columnar.ColumnarFunctionInput>();
        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

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

            var declKinds = new int[rawCount + 1];
            var declCount = bindings.TopLevelDeclarationKinds(rawKinds, rawCount, declKinds);
            if (declCount <= 0)
                return false;
            for (var d = 0; d < declCount; d++)
            {
                // 7 = func, 14 = enum, 9 = struct, 13 = record, 12 = union, 8 = class; any other top-level declaration
                // kind is unsupported and declines the whole program. Enum/struct/record/class/union decls are
                // collected separately (TryGetColumnarEnumInputs / TryGetColumnarStructInputs /
                // TryGetColumnarUnionInputs); the func scan below (TopLevelFuncIndices) only picks `func` tokens, so
                // type decls are skipped here rather than mis-parsed as functions.
                if (declKinds[d] != 7 && declKinds[d] != 14 && declKinds[d] != 9 && declKinds[d] != 13 && declKinds[d] != 12 && declKinds[d] != 8)
                    return false;
            }

            var ck = new int[rawCount];
            var cs = new int[rawCount];
            var cv = new int[rawCount];
            var n = 0;
            for (var i = 0; i < rawCount; i++)
            {
                if (rawKinds[i] == 136)
                    continue;
                ck[n] = rawKinds[i];
                cs[n] = rawStarts[i];
                cv[n] = rawValueLengths[i];
                n++;
            }

            var funcIndices = TopLevelFuncIndices(ck, n);
            if (funcIndices.Count == 0)
                return false;
            foreach (var funcIndex in funcIndices)
            {
                if (!TryParseColumnarFunctionAt(bindings, ck, cs, cv, n, funcIndex, source, out var input))
                    return false;
                inputs.Add(input);
            }
            return true;
        }
        catch
        {
            inputs = new System.Collections.Generic.List<Columnar.ColumnarFunctionInput>();
            return false;
        }
    }

    // Collect every top-level `enum` declaration into a ColumnarEnumInput (name + member names + auto-incremented
    // underlying int values). Tokenizes + compacts exactly like TryGetColumnarFunctionInputs, finds each enum
    // keyword (TopLevelEnumIndices), and parses its body via the ParseEnumDeclaration kernel. Returns true (possibly
    // an empty list) for a program with no enums. Returns FALSE — declining the whole program to C# — on any parse
    // failure OR an enum with an EXPLICIT member value (`= N`): slice A models only auto-incremented `0,1,2,...`
    // enums (explicit values are a later slice). The caller pairs the result with the function inputs for emit.
    private static bool TryGetColumnarEnumInputs(string source, out System.Collections.Generic.List<Columnar.ColumnarEnumInput> enums)
    {
        enums = new System.Collections.Generic.List<Columnar.ColumnarEnumInput>();
        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

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

            var ck = new int[rawCount];
            var cs = new int[rawCount];
            var cv = new int[rawCount];
            var n = 0;
            for (var i = 0; i < rawCount; i++)
            {
                if (rawKinds[i] == 136)
                    continue;
                ck[n] = rawKinds[i];
                cs[n] = rawStarts[i];
                cv[n] = rawValueLengths[i];
                n++;
            }

            var enumIndices = TopLevelEnumIndices(ck, n);
            foreach (var enumIndex in enumIndices)
            {
                var cap = n + 1;
                var outNameStarts = new int[cap];
                var outNameLengths = new int[cap];
                var outValueStarts = new int[cap];
                var outValueLengths = new int[cap];
                var outHasValue = new int[cap];
                var outResult = new int[2];
                var memberCount = bindings.ParseEnumDeclaration(
                    ck, cs, cv, n, enumIndex, outNameStarts, outNameLengths, outValueStarts, outValueLengths,
                    outHasValue, outResult);
                if (memberCount < 0 || outResult[1] <= 0)
                    return false;

                var enumName = source.Substring(outResult[0], outResult[1]);
                var memberNames = new string[memberCount];
                var memberValues = new int[memberCount];
                // C#'s enum value rule (ILCompiler.cs ~21174): nextValue starts at 0; an explicit `= <int>` member
                // sets its value AND resets nextValue to value+1; an implicit member takes the running nextValue.
                // (e.g. `A = 5, B, C = 20, D` -> 5, 6, 20, 21.) Mirror it EXACTLY so the underlying ints byte-match.
                var nextValue = 0;
                for (var m = 0; m < memberCount; m++)
                {
                    int constantValue;
                    if (outHasValue[m] != 0)
                    {
                        // An explicit plain-decimal literal — mirror C#'s int.Parse(intLiteral.Value). A non-decimal
                        // (hex / underscore) or overflowing value declines the whole program to the C# path.
                        var litText = source.Substring(outValueStarts[m], outValueLengths[m]);
                        if (!int.TryParse(litText, out constantValue))
                            return false;
                    }
                    else
                    {
                        constantValue = nextValue;
                    }
                    memberNames[m] = source.Substring(outNameStarts[m], outNameLengths[m]);
                    memberValues[m] = constantValue;
                    nextValue = constantValue + 1;
                }
                enums.Add(new Columnar.ColumnarEnumInput(enumName, memberNames, memberValues));
            }
            return true;
        }
        catch
        {
            enums = new System.Collections.Generic.List<Columnar.ColumnarEnumInput>();
            return false;
        }
    }

    // Collect every top-level fields-only `struct` declaration into a ColumnarStructInput (name + field names + field
    // TYPE canonical strings). Tokenizes + compacts exactly like TryGetColumnarEnumInputs, finds each struct keyword
    // (TopLevelStructIndices), and parses its body via the ParseStructDeclaration kernel. Returns true (possibly an
    // empty list) for a program with no structs. Returns FALSE — declining the whole program to C# — on any parse
    // failure (a primary-ctor struct, a method, a field initializer, a composed field type, an empty struct).
    private static bool TryGetColumnarStructInputs(string source, out System.Collections.Generic.List<Columnar.ColumnarStructInput> structs)
    {
        structs = new System.Collections.Generic.List<Columnar.ColumnarStructInput>();
        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

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

            var ck = new int[rawCount];
            var cs = new int[rawCount];
            var cv = new int[rawCount];
            var n = 0;
            for (var i = 0; i < rawCount; i++)
            {
                if (rawKinds[i] == 136)
                    continue;
                ck[n] = rawKinds[i];
                cs[n] = rawStarts[i];
                cv[n] = rawValueLengths[i];
                n++;
            }

            // Collect value-type structs (keyword 9, IsReference=false) AND reference-type records (keyword 13) and
            // classes (keyword 8), both IsReference=true — all three share the identical decl kernel + body syntax.
            // Records carry IsRecord=true: the oracle emits records SEALED, so a record can never be a BASE type
            // (and record inheritance itself is unmodelled) — the emitter declines those shapes by this flag.
            var decls = new System.Collections.Generic.List<(int Index, bool IsReference, bool IsRecord)>();
            foreach (var i in TopLevelStructIndices(ck, n)) decls.Add((i, false, false));
            foreach (var i in TopLevelRecordIndices(ck, n)) decls.Add((i, true, true));
            foreach (var i in TopLevelClassIndices(ck, n)) decls.Add((i, true, false));
            foreach (var (structIndex, isReference, isRecord) in decls)
            {
                var cap = n + 1;
                var outFieldNameStarts = new int[cap];
                var outFieldNameLengths = new int[cap];
                var outFieldTypeStarts = new int[cap];
                var outFieldTypeLengths = new int[cap];
                var outFieldStaticFlags = new int[cap];
                var outFieldInitKinds = new int[cap];
                var outFieldInitStarts = new int[cap];
                var outFieldInitLengths = new int[cap];
                var outMethodFuncIndices = new int[cap];
                var outMethodStaticFlags = new int[cap];
                var outCtorIndices = new int[cap];
                var outPropIndices = new int[cap];
                var outPropStaticFlags = new int[cap];
                var outTypeParamStarts = new int[cap];
                var outTypeParamLengths = new int[cap];
                var outResult = new int[8];
                var fieldCount = bindings.ParseStructDeclaration(
                    ck, cs, cv, n, structIndex, outFieldNameStarts, outFieldNameLengths, outFieldTypeStarts,
                    outFieldTypeLengths, outFieldStaticFlags, outFieldInitKinds, outFieldInitStarts, outFieldInitLengths,
                    outMethodFuncIndices, outMethodStaticFlags, outCtorIndices, outPropIndices, outPropStaticFlags,
                    outTypeParamStarts, outTypeParamLengths, outResult);
                // The kernel returns -1 on a parse failure; 0 is a legitimate FIELDLESS type. A zero-field
                // REFERENCE type (a pure-behavior class — e.g. an inheritance base with only methods) is modelled;
                // a zero-field VALUE struct keeps declining (a zero-size value type is a CLR layout edge case).
                if (fieldCount < 0 || (fieldCount == 0 && !isReference) || outResult[1] <= 0)
                    return false;

                var structName = source.Substring(outResult[0], outResult[1]);
                // The optional `: Base` single-identifier base-type name (outResult[5]/[6]; 0-length = no base).
                // The emitter resolves it against the declared types and validates (only a reference type may
                // inherit, only from a registered class — anything else declines there).
                var baseName = outResult[6] > 0 ? source.Substring(outResult[5], outResult[6]) : null;

                // Optional generic type parameters `<T, U>` (outResult[7] = count). v1 scope: generic CLASSES
                // and value STRUCTS only — a generic RECORD declines (columnar does not yet model the oracle's
                // backing-field lowering for init-only members on closed generics — the workaround for the
                // .NET 10 PersistedAssemblyBuilder modreq drop), and a generic type with a BASE declines
                // (generic base chains are unsupported in the oracle's closed-member machinery too).
                var typeParamCount = outResult[7];
                string[]? typeParamNames = null;
                if (typeParamCount > 0)
                {
                    if (isRecord || baseName != null)
                        return false;

                    typeParamNames = new string[typeParamCount];
                    for (var tp = 0; tp < typeParamCount; tp++)
                        typeParamNames[tp] = source.Substring(outTypeParamStarts[tp], outTypeParamLengths[tp]);
                }
                var fieldNames = new string[fieldCount];
                var fieldTypes = new string[fieldCount];
                var fieldStatics = new bool[fieldCount];
                var fieldInitKinds = new int[fieldCount];
                var fieldInitTexts = new string?[fieldCount];
                for (var f = 0; f < fieldCount; f++)
                {
                    fieldNames[f] = source.Substring(outFieldNameStarts[f], outFieldNameLengths[f]);
                    fieldTypes[f] = source.Substring(outFieldTypeStarts[f], outFieldTypeLengths[f]);
                    fieldStatics[f] = outFieldStaticFlags[f] == 1;
                    fieldInitKinds[f] = outFieldInitKinds[f];
                    fieldInitTexts[f] = outFieldInitKinds[f] >= 0
                        ? source.Substring(outFieldInitStarts[f], outFieldInitLengths[f])
                        : null;
                }

                // Each method (its `func` token index recorded by the kernel) is parsed with the SAME signature +
                // statement-body kernels as a top-level function — so a struct method's body is just a
                // ColumnarFunctionInput. The kernel's static flag (a `static` keyword before the `func`) is carried
                // onto the input; the emitter declares an instance method or a STATIC method on the TypeBuilder
                // accordingly.
                var methodCount = outResult[2];
                var methods = new System.Collections.Generic.List<Columnar.ColumnarFunctionInput>(methodCount);
                for (var m = 0; m < methodCount; m++)
                {
                    if (!TryParseColumnarFunctionAt(bindings, ck, cs, cv, n, outMethodFuncIndices[m], source, out var methodInput, isStatic: outMethodStaticFlags[m] == 1))
                        return false;
                    methods.Add(methodInput);
                }

                // Each user CONSTRUCTOR (its `constructor`-identifier token index recorded by the kernel) is parsed
                // like a nameless, void-returning function — the adapter verifies the identifier text is literally
                // "constructor" and that there is no return type / chaining initializer (decline otherwise).
                var ctorCount = outResult[3];
                var constructors = new System.Collections.Generic.List<Columnar.ColumnarConstructorInput>(ctorCount);
                for (var c = 0; c < ctorCount; c++)
                {
                    if (!TryParseColumnarConstructorAt(bindings, ck, cs, cv, n, outCtorIndices[c], source, out var ctorInput))
                        return false;
                    constructors.Add(ctorInput);
                }

                // Each get-only PROPERTY (its name token index recorded by the kernel) parses to a get_Name accessor
                // function. A property with a `set` (or any non-`get` accessor) declines (get-only this slice).
                var propCount = outResult[4];
                var properties = new System.Collections.Generic.List<Columnar.ColumnarPropertyInput>(propCount);
                for (var pr = 0; pr < propCount; pr++)
                {
                    if (!TryParseColumnarPropertyAt(bindings, ck, cs, cv, n, outPropIndices[pr], source, out var propInput, isStatic: outPropStaticFlags[pr] == 1))
                        return false;
                    properties.Add(propInput);
                }

                structs.Add(new Columnar.ColumnarStructInput(structName, fieldNames, fieldTypes, methods, constructors, properties, isReference, baseName, fieldStatics, fieldInitKinds, fieldInitTexts, isRecord, typeParamNames));
            }
            return true;
        }
        catch
        {
            structs = new System.Collections.Generic.List<Columnar.ColumnarStructInput>();
            return false;
        }
    }

    // Collect every top-level `union` declaration into a ColumnarUnionInput (name + per-case name + per-case field
    // names + per-case field TYPE canonical strings). Tokenizes + compacts exactly like the struct collector, finds
    // each union keyword (TopLevelUnionIndices), and parses its body via the ParseUnionDeclaration kernel — which
    // flattens fields across cases, with outCaseFieldCounts re-segmenting them per case. Returns true (possibly an
    // empty list) for a program with no unions. Returns FALSE — declining the whole program to C# — on any parse
    // failure (a bare case without a `{ }` body, a composed field type, an empty union). The emitter further gates
    // each field type to a supported CLR type and models the slice scope (non-generic unions, reference-type cases).
    private static bool TryGetColumnarUnionInputs(string source, out System.Collections.Generic.List<Columnar.ColumnarUnionInput> unions)
    {
        unions = new System.Collections.Generic.List<Columnar.ColumnarUnionInput>();
        var bindings = s_bindings.Value;
        if (bindings == null || string.IsNullOrEmpty(source))
            return false;

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

            var ck = new int[rawCount];
            var cs = new int[rawCount];
            var cv = new int[rawCount];
            var n = 0;
            for (var i = 0; i < rawCount; i++)
            {
                if (rawKinds[i] == 136)
                    continue;
                ck[n] = rawKinds[i];
                cs[n] = rawStarts[i];
                cv[n] = rawValueLengths[i];
                n++;
            }

            foreach (var unionIndex in TopLevelUnionIndices(ck, n))
            {
                var cap = n + 1;
                var outCaseNameStarts = new int[cap];
                var outCaseNameLengths = new int[cap];
                var outCaseFieldCounts = new int[cap];
                var outFieldNameStarts = new int[cap];
                var outFieldNameLengths = new int[cap];
                var outFieldTypeStarts = new int[cap];
                var outFieldTypeLengths = new int[cap];
                var outResult = new int[2];
                var caseCount = bindings.ParseUnionDeclaration(
                    ck, cs, cv, n, unionIndex, outCaseNameStarts, outCaseNameLengths, outCaseFieldCounts,
                    outFieldNameStarts, outFieldNameLengths, outFieldTypeStarts, outFieldTypeLengths, outResult);
                if (caseCount <= 0 || outResult[1] <= 0)
                    return false;

                var unionName = source.Substring(outResult[0], outResult[1]);
                var caseNames = new string[caseCount];
                var caseFieldNames = new string[caseCount][];
                var caseFieldTypes = new string[caseCount][];
                var fieldCursor = 0;
                for (var c = 0; c < caseCount; c++)
                {
                    caseNames[c] = source.Substring(outCaseNameStarts[c], outCaseNameLengths[c]);
                    var fc = outCaseFieldCounts[c];
                    var names = new string[fc];
                    var types = new string[fc];
                    for (var f = 0; f < fc; f++)
                    {
                        names[f] = source.Substring(outFieldNameStarts[fieldCursor], outFieldNameLengths[fieldCursor]);
                        types[f] = source.Substring(outFieldTypeStarts[fieldCursor], outFieldTypeLengths[fieldCursor]);
                        fieldCursor++;
                    }
                    caseFieldNames[c] = names;
                    caseFieldTypes[c] = types;
                }

                unions.Add(new Columnar.ColumnarUnionInput(unionName, caseNames, caseFieldNames, caseFieldTypes));
            }
            return true;
        }
        catch
        {
            unions = new System.Collections.Generic.List<Columnar.ColumnarUnionInput>();
            return false;
        }
    }

    // Parse ONE top-level function (at compacted token index `funcIndex`) into its signature + columnar body
    // node tables. Returns false on any parse failure or a missing body brace.
    private static bool TryParseColumnarFunctionAt(
        Bindings bindings, int[] ck, int[] cs, int[] cv, int n, int funcIndex, string source,
        out Columnar.ColumnarFunctionInput input, bool isStatic = false)
    {
        input = null!;
        var cap = n + 1;

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

        var fname = source.Substring(sres[3], sres[4]);
        // sres[1] is the return-type tree root, or -1 when the function OMITS its return type (`func f(...) {`,
        // implicit void — the kernel sets returnRoot = -1, a valid signature, not a parse error). Canonicalize to
        // "void" in that case (the emitter's pass 1 maps "void" -> typeof(void)), matching the symbol/type
        // services' handling (TryInferTopLevelFunctionTypes uses `sres[1] >= 0 ? canon : "void"`). Without this,
        // SemanticScopes' implicit-void procedures (SortIdsByStart, ClearTouched) declined the whole file at parse.
        var returnCanonical = sres[1] >= 0
            ? ColumnarTypeCanon(sk, sns, snl, scs, scc, sci, source, sres[1])
            : "void";
        var paramNames = new string[paramCount];
        var paramCanonicals = new string[paramCount];
        for (var p = 0; p < paramCount; p++)
        {
            paramNames[p] = source.Substring(pNameStart[p], pNameLen[p]);
            paramCanonicals[p] = ColumnarTypeCanon(sk, sns, snl, scs, scc, sci, source, pTypeRoot[p]);
        }

        // Generic TYPE PARAMETERS (`func Identity<T>(...)`): sres[5] names parsed by the kernel. The token at
        // sres[6] (immediately after the signature, PAST any `where` clauses) must be the body `{` — anything
        // else is an unmodelled trailer (an `=>` expression body) and declines to the C# path.
        var bodyBrace = sres[6];
        if (bodyBrace >= n || ck[bodyBrace] != 129)
            return false;
        var typeParamNames = System.Array.Empty<string>();
        if (sres[5] > 0)
        {
            typeParamNames = new string[sres[5]];
            for (var t = 0; t < sres[5]; t++)
                typeParamNames[t] = source.Substring(sTypeParamStarts[t], sTypeParamLengths[t]);
        }

        // Generic CONSTRAINTS (`where T: Base, new()` — D-17b): the kernel reports flat rows (owner-name span +
        // code); group them by declared type-parameter position. Constraints CANNOT be silently dropped (the
        // pipeline enforces NL208 at call sites, so ignoring them would over-accept constraint-violating
        // programs) — every row either lands on its parameter or the whole function declines: an owner naming
        // no declared type parameter declines, and the combos the production parser ERRORS on (`class` with
        // `struct`, `struct` with `new()`) decline so the C# path surfaces its diagnostics. Special flags
        // mirror SpecialConstraintKind (Class=1, Struct=2, New=4).
        var whereItemCount = sres[7];
        int[]? typeParamSpecials = null;
        string[][]? typeParamTypeConstraints = null;
        if (whereItemCount > 0)
        {
            if (typeParamNames.Length == 0)
                return false;
            typeParamSpecials = new int[typeParamNames.Length];
            var constraintLists = new List<string>[typeParamNames.Length];
            for (var w = 0; w < whereItemCount; w++)
            {
                var owner = source.Substring(sWhereNameStarts[w], sWhereNameLengths[w]);
                var ownerIndex = System.Array.IndexOf(typeParamNames, owner);
                if (ownerIndex < 0)
                    return false;
                var code = sWhereItemCodes[w];
                if (code >= 0)
                    (constraintLists[ownerIndex] ??= new List<string>()).Add(
                        ColumnarTypeCanon(sk, sns, snl, scs, scc, sci, source, code));
                else if (code == -2)
                    typeParamSpecials[ownerIndex] |= 1;
                else if (code == -3)
                    typeParamSpecials[ownerIndex] |= 2;
                else if (code == -4)
                    typeParamSpecials[ownerIndex] |= 4;
                else
                    return false;
            }
            typeParamTypeConstraints = new string[typeParamNames.Length][];
            for (var t = 0; t < typeParamNames.Length; t++)
            {
                if ((typeParamSpecials[t] & 3) == 3 || (typeParamSpecials[t] & 6) == 6)
                    return false;
                typeParamTypeConstraints[t] = constraintLists[t]?.ToArray() ?? System.Array.Empty<string>();
            }
        }

        var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
        var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
        var bres = new int[2];
        var bodyNodeCount = bindings.ParseStatementNodes(
            ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
        if (bodyNodeCount <= 0)
            return false;

        input = new Columnar.ColumnarFunctionInput(
            fname, returnCanonical, paramNames, paramCanonicals,
            bk, bvs, bvl, bcs, bcc, bci, bres[0], isStatic, typeParamNames,
            typeParamSpecials, typeParamTypeConstraints);

        // LOCAL FUNCTIONS (kind-41 statements that are DIRECT children of the root block): each node's
        // value span is the `func` keyword's byte span — re-locate the token and parse the nested
        // declaration through the same kernels (recursively: a local function may declare its own).
        // Nested-BLOCK declarations are deliberately NOT collected — their kind-41 nodes stay undeclared
        // and the emitter declines them (scope-precise under-acceptance).
        var rootBlock = bres[0];
        if (bk[rootBlock] == 25)
        {
            for (var rc = 0; rc < bcc[rootBlock]; rc++)
            {
                var stmtNode = bci[bcs[rootBlock] + rc];
                if (bk[stmtNode] != 41)
                    continue;
                var funcTokenIndex = -1;
                for (var ti = 0; ti < n; ti++)
                {
                    if (cs[ti] == bvs[stmtNode] && ck[ti] == 7) { funcTokenIndex = ti; break; }
                }
                if (funcTokenIndex < 0)
                    return false;
                if (!TryParseColumnarFunctionAt(bindings, ck, cs, cv, n, funcTokenIndex, source, out var localFn))
                    return false;
                (input.LocalFunctions ??= new List<(int, Columnar.ColumnarFunctionInput)>()).Add((stmtNode, localFn));
            }
        }
        return true;
    }

    // Parse ONE user CONSTRUCTOR (at compacted token index `ctorIndex`, the "constructor" identifier) into a
    // ColumnarFunctionInput whose name is "constructor" and whose return is "void". Reuses the function-signature
    // kernel (a constructor has no name token and no `: ret`, so it yields funcNameStart = -1 and returnRoot = -1)
    // and the statement kernel for the body. Declines if the identifier text is not literally "constructor", if the
    // signature has a return type (a `: this(...)`/`base(...)` chaining initializer makes the kernel's return-type
    // parse fail → paramCount < 0), or the body is missing.
    private static bool TryParseColumnarConstructorAt(
        Bindings bindings, int[] ck, int[] cs, int[] cv, int n, int ctorIndex, string source,
        out Columnar.ColumnarConstructorInput input)
    {
        input = null!;
        if (string.CompareOrdinal(source, cs[ctorIndex], "constructor", 0, "constructor".Length) != 0
            || cv[ctorIndex] != "constructor".Length)
            return false; // an `id(...)` member whose identifier is not "constructor" is not modelled.

        var cap = n + 1;
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
            ck, cs, cv, n, ctorIndex, sk, sns, snl, scs, scc, sci, sss, ssl,
            pNameStart, pNameLen, pTypeRoot, sTypeParamStarts, sTypeParamLengths,
            sWhereNameStarts, sWhereNameLengths, sWhereItemCodes, sres);
        // A constructor must have NO return type (sres[1] = -1), NO generic type parameters (sres[5] = 0), and
        // NO `where` constraint rows (sres[7] = 0). A non-negative return root means a `: <type>` was parsed —
        // for a constructor that is malformed (or a chaining initializer the kernel rejected differently).
        if (paramCount < 0 || sres[1] >= 0 || sres[5] != 0 || sres[7] != 0)
            return false;

        var paramNames = new string[paramCount];
        var paramCanonicals = new string[paramCount];
        for (var p = 0; p < paramCount; p++)
        {
            paramNames[p] = source.Substring(pNameStart[p], pNameLen[p]);
            paramCanonicals[p] = ColumnarTypeCanon(sk, sns, snl, scs, scc, sci, source, pTypeRoot[p]);
        }

        var bodyBrace = -1;
        for (var t = ctorIndex + 1; t < n; t++)
        {
            if (ck[t] == 129) { bodyBrace = t; break; }
        }
        if (bodyBrace < 0)
            return false;

        var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
        var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
        var bres = new int[2];
        var bodyNodeCount = bindings.ParseStatementNodes(
            ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
        if (bodyNodeCount <= 0)
            return false;

        // Parse the optional `: this(args)` / `: base(args)` chaining initializer (chained args restricted to a param
        // identifier or an int literal; a complex/other-literal arg returns -1 -> decline the whole ctor).
        var caKinds = new int[cap];
        var caStarts = new int[cap];
        var caLengths = new int[cap];
        var caRes = new int[1];
        var chainArgCount = bindings.ParseConstructorChainInfo(ck, cs, cv, n, ctorIndex, caKinds, caStarts, caLengths, caRes);
        if (chainArgCount < 0)
            return false;
        var chainArgKinds = new int[chainArgCount];
        var chainArgTexts = new string[chainArgCount];
        for (var a = 0; a < chainArgCount; a++)
        {
            chainArgKinds[a] = caKinds[a];
            chainArgTexts[a] = source.Substring(caStarts[a], caLengths[a]);
        }

        var body = new Columnar.ColumnarFunctionInput(
            "constructor", "void", paramNames, paramCanonicals,
            bk, bvs, bvl, bcs, bcc, bci, bres[0]);
        input = new Columnar.ColumnarConstructorInput(body, caRes[0], chainArgKinds, chainArgTexts);
        return true;
    }

    // Parse ONE computed PROPERTY (at compacted token index `propIndex`, the property NAME). The kernel recorded it
    // as `Name : Type { … }`; the layout is name(propIndex) `:`(+1) Type(+2) `{`(+3, property block) `get`(+4,
    // identifier "get") `{`(+5, get body). The getter body parses into a ColumnarFunctionInput named "get_Name"
    // (no params, returning the property type). After the get body's `}`, an OPTIONAL `set { … }` accessor parses
    // into "set_Name" (one param "value": Type, returning void); else the property block must close with `}`. A
    // set-first ordering, an expression-bodied accessor, or a third accessor declines (get / get-set this slice).
    private static bool TryParseColumnarPropertyAt(
        Bindings bindings, int[] ck, int[] cs, int[] cv, int n, int propIndex, string source,
        out Columnar.ColumnarPropertyInput input, bool isStatic = false)
    {
        input = null!;
        if (propIndex + 5 >= n)
            return false;
        if (ck[propIndex] != 0 || ck[propIndex + 1] != 122 || ck[propIndex + 2] != 0 || ck[propIndex + 3] != 129)
            return false;
        if (ck[propIndex + 4] != 0 || cv[propIndex + 4] != 3 || string.CompareOrdinal(source, cs[propIndex + 4], "get", 0, 3) != 0)
            return false;
        if (ck[propIndex + 5] != 129)
            return false;

        var propName = source.Substring(cs[propIndex], cv[propIndex]);
        var propType = source.Substring(cs[propIndex + 2], cv[propIndex + 2]);
        var cap = n + 1;

        // Parse the get body. Find its matching `}` to locate what follows (the property `}` for get-only, or a `set`).
        var getBodyBrace = propIndex + 5;
        var getBodyEnd = MatchingCloseBrace(ck, n, getBodyBrace);
        if (getBodyEnd < 0)
            return false;
        var gk = new int[cap]; var gvs = new int[cap]; var gvl = new int[cap]; var gcs = new int[cap];
        var gcc = new int[cap]; var gci = new int[cap]; var gss = new int[cap]; var gsl = new int[cap];
        var gres = new int[2];
        if (bindings.ParseStatementNodes(ck, cs, cv, n, getBodyBrace, gk, gvs, gvl, gcs, gcc, gci, gss, gsl, gres) <= 0)
            return false;
        var getter = new Columnar.ColumnarFunctionInput(
            "get_" + propName, propType, System.Array.Empty<string>(), System.Array.Empty<string>(),
            gk, gvs, gvl, gcs, gcc, gci, gres[0]);

        Columnar.ColumnarFunctionInput? setter = null;
        var after = getBodyEnd + 1;
        if (after < n && ck[after] == 130)
        {
            // get-only: the property block closes right after the getter.
        }
        else if (after + 1 < n && ck[after] == 0 && cv[after] == 3 && string.CompareOrdinal(source, cs[after], "set", 0, 3) == 0 && ck[after + 1] == 129)
        {
            // `set { setBody }` — implicit `value` parameter of the property type, void return. The set body's `}`
            // must be immediately followed by the property block `}` (a third accessor declines).
            var setBodyBrace = after + 1;
            var setBodyEnd = MatchingCloseBrace(ck, n, setBodyBrace);
            if (setBodyEnd < 0 || setBodyEnd + 1 >= n || ck[setBodyEnd + 1] != 130)
                return false;
            var stk = new int[cap]; var stvs = new int[cap]; var stvl = new int[cap]; var stcs = new int[cap];
            var stcc = new int[cap]; var stci = new int[cap]; var stss = new int[cap]; var stsl = new int[cap];
            var stres = new int[2];
            if (bindings.ParseStatementNodes(ck, cs, cv, n, setBodyBrace, stk, stvs, stvl, stcs, stcc, stci, stss, stsl, stres) <= 0)
                return false;
            setter = new Columnar.ColumnarFunctionInput(
                "set_" + propName, "void", new[] { "value" }, new[] { propType },
                stk, stvs, stvl, stcs, stcc, stci, stres[0]);
        }
        else
        {
            return false; // a set-first ordering / expression-bodied / unrecognized accessor -> decline.
        }

        input = new Columnar.ColumnarPropertyInput(propName, propType, getter, setter, isStatic);
        return true;
    }

    // The compacted-token index of the `}` (130) that closes the `{` (129) at `open`, or -1 if unbalanced.
    private static int MatchingCloseBrace(int[] ck, int n, int open)
    {
        var depth = 0;
        for (var t = open; t < n; t++)
        {
            if (ck[t] == 129) depth++;
            else if (ck[t] == 130) { depth--; if (depth == 0) return t; }
        }
        return -1;
    }

    // Canonical type string from a columnar TYPE subtree (kinds 0 Simple,1 Generic,2 Array,3 Nullable,
    // 4 Union,5 ByRef), matching Columnar.ColumnarFunctionSymbol.CanonicalType for the C# AST exactly.
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
                var sb = new System.Text.StringBuilder();
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
                var sb = new System.Text.StringBuilder();
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
                // Tuple `(e0, e1, ...)` -> the canonical `(e0,e1,...)` (parens + comma-joined element canons, no
                // spaces) — the SAME format ColumnarFunctionSymbol.CanonicalType produces and the emitter's
                // TryResolveType parses back into a System.ValueTuple.
                var sb = new System.Text.StringBuilder();
                sb.Append('(');
                var run = childStart[idx];
                for (var k = 0; k < childCount[idx]; k++)
                {
                    if (k > 0) sb.Append(',');
                    sb.Append(ColumnarTypeCanon(kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, childIndices[run + k]));
                }

                sb.Append(')');
                return sb.ToString();
            }
            default:
                return "?";
        }
    }

    /// <summary>Indices of every depth-0 <c>func</c> keyword (TokenType.Func == 7) in the compacted stream.</summary>
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

    // The compacted-token indices of each top-level `enum` keyword (token 14) — at brace/bracket/paren depth 0, so
    // an enum nested in a (hypothetical) type body is not picked. Mirrors TopLevelFuncIndices for the enum keyword.
    private static List<int> TopLevelEnumIndices(int[] kinds, int count)
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
                case 14:
                    if (brace == 0 && bracket == 0 && paren == 0) result.Add(i);
                    break;
            }
        }

        return result;
    }

    // The compacted-token indices of each top-level `struct` keyword (token 9) — at depth 0. Mirrors
    // TopLevelEnumIndices for the struct keyword.
    private static List<int> TopLevelStructIndices(int[] kinds, int count)
    {
        // A depth-0 `where` (53) opens a generic CONSTRAINT clause whose items may include the `struct`
        // KEYWORD — a constraint, not a declaration; suppress until the body `{` (mirrors the kernel
        // scanners' rule).
        var result = new List<int>();
        var brace = 0;
        var bracket = 0;
        var paren = 0;
        var inWhereClause = false;
        for (var i = 0; i < count; i++)
        {
            switch (kinds[i])
            {
                case 129: brace++; inWhereClause = false; break;
                case 130: if (brace > 0) brace--; break;
                case 131: bracket++; break;
                case 132: if (bracket > 0) bracket--; break;
                case 127: paren++; break;
                case 128: if (paren > 0) paren--; break;
                case 53:
                    if (brace == 0 && bracket == 0 && paren == 0) inWhereClause = true;
                    break;
                case 9:
                    if (brace == 0 && bracket == 0 && paren == 0 && !inWhereClause) result.Add(i);
                    break;
            }
        }

        return result;
    }

    // The compacted-token indices of each top-level `record` keyword (token 13) — at depth 0. Mirrors
    // TopLevelStructIndices for the record keyword (records share the struct decl kernel + collection).
    private static List<int> TopLevelRecordIndices(int[] kinds, int count)
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
                case 13:
                    if (brace == 0 && bracket == 0 && paren == 0) result.Add(i);
                    break;
            }
        }

        return result;
    }

    // The compacted-token indices of each top-level `class` keyword (token 8) — at depth 0. Mirrors
    // TopLevelStructIndices for the class keyword (classes share the struct/record decl kernel + collection,
    // IsReference=true). A class with a primary-ctor `(` after the name, or a user `constructor`, declines in the
    // decl kernel (slice 1a: fields + methods + object-init only).
    private static List<int> TopLevelClassIndices(int[] kinds, int count)
    {
        // A depth-0 `where` (53) opens a generic CONSTRAINT clause whose items may include the `class`
        // KEYWORD — a constraint, not a declaration; suppress until the body `{` (mirrors the kernel
        // scanners' rule).
        var result = new List<int>();
        var brace = 0;
        var bracket = 0;
        var paren = 0;
        var inWhereClause = false;
        for (var i = 0; i < count; i++)
        {
            switch (kinds[i])
            {
                case 129: brace++; inWhereClause = false; break;
                case 130: if (brace > 0) brace--; break;
                case 131: bracket++; break;
                case 132: if (bracket > 0) bracket--; break;
                case 127: paren++; break;
                case 128: if (paren > 0) paren--; break;
                case 53:
                    if (brace == 0 && bracket == 0 && paren == 0) inWhereClause = true;
                    break;
                case 8:
                    if (brace == 0 && bracket == 0 && paren == 0 && !inWhereClause) result.Add(i);
                    break;
            }
        }

        return result;
    }

    // The compacted-token indices of each top-level `union` keyword (token 12) — at depth 0. Mirrors
    // TopLevelStructIndices for the union keyword.
    private static List<int> TopLevelUnionIndices(int[] kinds, int count)
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
                case 12:
                    if (brace == 0 && bracket == 0 && paren == 0) result.Add(i);
                    break;
            }
        }

        return result;
    }

    /// <summary>
    /// Single-pass replacement for ProjectConfig.GetSourceFiles' post-enumeration filtering
    /// (test-file filter + exclude-glob filter). Materializes the kept files preserving enumeration
    /// order. Returns false (so callers keep the C# path) when the dogfood assembly is unavailable
    /// or any input is unexpected.
    /// </summary>
    internal static bool TryFilterSourceFiles(
        string[] files,
        string projectRoot,
        Func<string, string, string> getRelativePath,
        string[] excludePatterns,
        bool includeTests,
        out string[] filteredFiles)
    {
        filteredFiles = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var fileCount = files.Length;
        if (fileCount == 0)
            return true;

        var scratch = t_projectSourceFilterScratch ??= new ProjectSourceFilterScratch();
        scratch.EnsureCapacity(fileCount);

        try
        {
            for (var i = 0; i < fileCount; i++)
            {
                var file = files[i];
                if (file == null)
                    return false;

                var relativePath = getRelativePath(projectRoot, file);

                // The production glob uses .NET regex, where '.' (and '.*') does not match '\n' and
                // the trailing '$' anchor matches before a final '\n'. The N# kernel treats '\n' as
                // an ordinary character, so fall back to the exact C# regex path for the (extremely
                // rare) case of a newline in an on-disk file path to preserve exact parity.
                if (relativePath.Contains('\n'))
                    return false;

                scratch.RelativePaths[i] = relativePath;
            }

            var keptCount = bindings.ProjectSourceFilterKeptIndices(
                scratch.RelativePaths,
                excludePatterns,
                includeTests ? 1 : 0,
                scratch.ResultIndices);

            if (keptCount < 0 || keptCount > fileCount)
                return false;

            var result = new string[keptCount];
            for (var i = 0; i < keptCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= fileCount)
                    return false;

                result[i] = files[sourceIndex];
            }

            filteredFiles = result;
            return true;
        }
        catch
        {
            filteredFiles = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ClearRelativePaths(fileCount);
        }
    }

    internal static bool TryGetVisibleVariablesAtPosition(
        SemanticModel semanticModel,
        int line,
        int column,
        out Dictionary<string, TypeInfo> visibleVariables)
    {
        visibleVariables = new Dictionary<string, TypeInfo>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = s_semanticScopeCaches.GetValue(semanticModel, static model => new SemanticScopeCache(model));
            return cache.TryGetVisibleVariablesAtPosition(bindings, line, column, out visibleVariables);
        }
        catch
        {
            visibleVariables = new Dictionary<string, TypeInfo>();
            return false;
        }
    }

    internal static bool TryLookupIdentifierAtPosition(
        SemanticModel semanticModel,
        string name,
        int line,
        int column,
        out TypeInfo? typeInfo)
    {
        typeInfo = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var cache = s_semanticScopeCaches.GetValue(semanticModel, static model => new SemanticScopeCache(model));
            return cache.TryLookupIdentifierAtPosition(bindings, name, line, column, out typeInfo);
        }
        catch
        {
            typeInfo = null;
            return false;
        }
    }

    internal static bool TryCompactParserTokens(IReadOnlyList<Token> tokens, out List<Token> compactedTokens)
    {
        compactedTokens = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var tokenCount = tokens.Count;
        if (tokenCount == 0)
            return true;

        var scratch = t_parserTokenCompactionScratch ??= new ParserTokenCompactionScratch();
        scratch.EnsureCapacity(tokenCount);

        try
        {
            for (var i = 0; i < tokenCount; i++)
            {
                scratch.TokenKinds[i] = (int)tokens[i].Type;
            }

            var compactedCount = bindings.ParserTokenCompaction(
                scratch.TokenKinds,
                scratch.ResultIndices);

            if (compactedCount < 0 || compactedCount > tokenCount)
            {
                compactedTokens = [];
                return false;
            }

            var result = new List<Token>(compactedCount);
            for (var i = 0; i < compactedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= tokenCount)
                {
                    compactedTokens = [];
                    return false;
                }

                result.Add(tokens[sourceIndex]);
            }

            compactedTokens = result;
            return true;
        }
        catch
        {
            compactedTokens = [];
            return false;
        }
    }

    internal static bool TryOrderImportsBySystemThenNamespace(
        IReadOnlyList<ImportDirective> imports,
        out List<ImportDirective> orderedImports)
    {
        orderedImports = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var count = imports.Count;
        if (count == 0)
            return true;

        var scratch = t_formatterImportOrderingScratch ??= new FormatterImportOrderingScratch();
        scratch.EnsureCapacity(count);

        try
        {
            scratch.ResetRanks();
            for (var i = 0; i < count; i++)
            {
                var ns = imports[i].Namespace;
                if (ns == null)
                {
                    orderedImports = [];
                    return false;
                }

                // Match the production LINQ shape exactly: OrderByDescending uses the
                // default (current-culture) StartsWith, ThenBy uses Comparer<string>.Default.
                scratch.SystemFlags[i] = ns.StartsWith("System") ? 1 : 0;
                scratch.AddNamespace(ns);
            }

            scratch.BuildRanks();
            for (var i = 0; i < count; i++)
            {
                scratch.NameRanks[i] = scratch.GetRank(imports[i].Namespace);
            }

            var orderedCount = bindings.FormatterImportOrderIndices(
                scratch.SystemFlags,
                scratch.NameRanks,
                scratch.UniqueNamespaceCount,
                scratch.BucketCounts,
                scratch.BucketOffsets,
                scratch.TempIndices,
                scratch.ResultIndices);

            if (orderedCount != count)
            {
                orderedImports = [];
                return false;
            }

            var result = new List<ImportDirective>(count);
            for (var i = 0; i < count; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= count)
                {
                    orderedImports = [];
                    return false;
                }

                result.Add(imports[sourceIndex]);
            }

            orderedImports = result;
            return true;
        }
        catch
        {
            orderedImports = [];
            return false;
        }
        finally
        {
            scratch.ResetRanks();
        }
    }

    internal static bool TryDeduplicateFirstTypeKeys(
        IReadOnlyList<Type> types,
        Func<Type, string> getTypeKey,
        out List<Type> deduplicatedTypes)
    {
        deduplicatedTypes = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var typeCount = types.Count;
        if (typeCount == 0)
            return true;

        var scratch = t_firstDistinctTypeKeyScratch ??= new FirstDistinctTypeKeyScratch();
        scratch.EnsureCapacity(typeCount);

        try
        {
            scratch.ResetKeys();
            for (var i = 0; i < typeCount; i++)
            {
                scratch.TypeRanks[i] = scratch.AddKey(getTypeKey(types[i]));
            }

            var deduplicatedCount = bindings.FirstDistinctRankIndices(
                scratch.TypeRanks,
                scratch.UniqueKeyCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (deduplicatedCount < 0 || deduplicatedCount > typeCount || deduplicatedCount > scratch.ResultIndices.Length)
            {
                deduplicatedTypes = [];
                return false;
            }

            var result = new List<Type>(deduplicatedCount);
            for (var i = 0; i < deduplicatedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= typeCount)
                {
                    deduplicatedTypes = [];
                    return false;
                }

                result.Add(types[sourceIndex]);
            }

            deduplicatedTypes = result;
            return true;
        }
        catch
        {
            deduplicatedTypes = [];
            return false;
        }
        finally
        {
            scratch.ResetKeys();
        }
    }

    internal static bool TryDeduplicateFirstStringsOrdinalIgnoreCase(
        IReadOnlyList<string> values,
        out List<string> deduplicatedValues)
    {
        deduplicatedValues = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var valueCount = values.Count;
        if (valueCount == 0)
            return true;

        var scratch = t_firstDistinctStringScratch ??= new FirstDistinctStringScratch(StringComparer.OrdinalIgnoreCase);
        scratch.EnsureCapacity(valueCount);

        try
        {
            scratch.ResetKeys();
            for (var i = 0; i < valueCount; i++)
            {
                var value = values[i];
                if (value == null)
                {
                    deduplicatedValues = [];
                    return false;
                }

                scratch.Ranks[i] = scratch.AddKey(value);
            }

            var deduplicatedCount = bindings.FirstDistinctRankIndices(
                scratch.Ranks,
                scratch.UniqueKeyCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (deduplicatedCount < 0 || deduplicatedCount > valueCount || deduplicatedCount > scratch.ResultIndices.Length)
            {
                deduplicatedValues = [];
                return false;
            }

            var result = new List<string>(deduplicatedCount);
            for (var i = 0; i < deduplicatedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= valueCount)
                {
                    deduplicatedValues = [];
                    return false;
                }

                result.Add(values[sourceIndex]);
            }

            deduplicatedValues = result;
            return true;
        }
        catch
        {
            deduplicatedValues = [];
            return false;
        }
        finally
        {
            scratch.ResetKeys();
        }
    }

    internal static bool TryDistinctOrderStringsOrdinal(
        IReadOnlyList<string> values,
        out string[] orderedValues)
    {
        orderedValues = Array.Empty<string>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var valueCount = values.Count;
        if (valueCount == 0)
            return true;

        var scratch = t_distinctOrderedStringScratch ??= new DistinctOrderedStringScratch();
        scratch.EnsureCapacity(valueCount);

        try
        {
            scratch.ResetValues();
            for (var i = 0; i < valueCount; i++)
            {
                var value = values[i];
                if (value == null)
                {
                    orderedValues = Array.Empty<string>();
                    return false;
                }

                scratch.Values[i] = value;
                scratch.AddValue(value);
            }

            scratch.BuildRanks();
            for (var i = 0; i < valueCount; i++)
            {
                scratch.ValueRanks[i] = scratch.GetRank(scratch.Values[i]);
            }

            var orderedCount = bindings.ReferenceFileSummaryRanks(
                scratch.ValueRanks,
                scratch.UniqueValueCount,
                scratch.CountsByRank,
                scratch.ResultRanks);

            if (orderedCount < 0 || orderedCount > scratch.UniqueValueCount || orderedCount > scratch.ResultRanks.Length)
            {
                orderedValues = Array.Empty<string>();
                return false;
            }

            var result = new string[orderedCount];
            for (var i = 0; i < orderedCount; i++)
            {
                var rank = scratch.ResultRanks[i];
                if (rank <= 0 || rank > scratch.UniqueValueCount)
                {
                    orderedValues = Array.Empty<string>();
                    return false;
                }

                result[i] = scratch.UniqueValues[rank - 1];
            }

            orderedValues = result;
            return true;
        }
        catch
        {
            orderedValues = Array.Empty<string>();
            return false;
        }
        finally
        {
            scratch.ClearValues(valueCount);
            scratch.ResetValues();
        }
    }

    internal static bool TryLookupUniqueDeclaredTypeBySuffix<TType>(
        IReadOnlyDictionary<string, TType> types,
        string typeName,
        out TType type,
        out bool found)
        where TType : Type
    {
        type = null!;
        found = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var scratch = t_declaredTypeSuffixLookupScratch ??= new DeclaredTypeSuffixLookupScratch();

        try
        {
            if (!scratch.Load(types))
                return false;

            var tailHashWidth = DeclaredTypeSuffixLookupScratch.GetTailHashWidth(typeName);
            scratch.RefreshTailHashes(tailHashWidth);

            var rank = bindings.DeclaredTypeUniqueSuffixValueRank(
                scratch.Keys,
                scratch.ValueRanks,
                scratch.TailHashes,
                typeName,
                DeclaredTypeSuffixLookupScratch.GetTailHash(typeName, tailHashWidth),
                scratch.Count);

            if (rank == -2)
                return false;

            if (rank <= 0)
                return true;

            if (rank >= scratch.Values.Length || scratch.Values[rank] is not TType result)
                return false;

            type = result;
            found = true;
            return true;
        }
        catch
        {
            type = null!;
            found = false;
            return false;
        }
    }

    internal static bool TrySelectDeclaredTypeNameCandidate(
        CompilationUnit compilationUnit,
        string typeName,
        out string? candidate)
    {
        candidate = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (string.IsNullOrWhiteSpace(typeName))
            return true;

        var scratch = t_declaredTypeNameCandidateScratch ??= new DeclaredTypeNameCandidateScratch();

        try
        {
            scratch.Load(compilationUnit);

            var tailHashWidth = DeclaredTypeSuffixLookupScratch.GetTailHashWidth(typeName);
            scratch.RefreshTailHashes(tailHashWidth);

            var index = bindings.DeclaredTypeNameCandidateIndex(
                scratch.Names,
                scratch.ImportedNamespaceFlags,
                scratch.TailHashes,
                typeName,
                DeclaredTypeSuffixLookupScratch.GetTailHash(typeName, tailHashWidth),
                scratch.Count);

            if (index == -2)
                return false;

            if (index <= 0)
                return true;

            var candidateIndex = index - 1;
            if (candidateIndex >= scratch.Count)
                return false;

            candidate = scratch.Names[candidateIndex];
            return true;
        }
        catch
        {
            candidate = null;
            return false;
        }
    }

    internal static bool TryOrderTypesByDescendingKeyDotCount<TType>(
        IEnumerable<TType> types,
        Func<TType, string> getTypeKey,
        out List<TType> orderedTypes)
        where TType : Type
    {
        orderedTypes = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var scratch = t_typeCreationOrderScratch ??= new TypeCreationOrderScratch();

        try
        {
            if (!scratch.Load(types, getTypeKey))
                return false;

            if (scratch.Count == 0)
                return true;

            var orderedCount = bindings.TypeCreationOrderIndices(
                scratch.Keys,
                scratch.Count,
                scratch.DotCounts,
                scratch.DepthCounts,
                scratch.DepthOffsets,
                scratch.ResultIndices);

            if (orderedCount < 0 || orderedCount > scratch.Count || orderedCount > scratch.ResultIndices.Length)
            {
                orderedTypes = [];
                return false;
            }

            var result = new List<TType>(orderedCount);
            for (var i = 0; i < orderedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= scratch.Count || scratch.Values[sourceIndex] is not TType type)
                {
                    orderedTypes = [];
                    return false;
                }

                result.Add(type);
            }

            orderedTypes = result;
            return true;
        }
        catch
        {
            orderedTypes = [];
            return false;
        }
        finally
        {
            scratch.ClearValues();
        }
    }

    internal static bool TryDeclaresAnonymousUnionShims(
        IReadOnlyList<Parameter> parameters,
        Func<TypeReference, bool> isTwoArmAnonymousUnion,
        out bool declaresShims)
    {
        declaresShims = false;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var parameterCount = parameters.Count;
        if (parameterCount == 0)
            return true;

        var scratch = t_anonymousUnionShimScratch ??= new AnonymousUnionShimScratch();
        scratch.EnsureCapacity(parameterCount);

        try
        {
            var unionParameterCount = 0;
            for (var i = 0; i < parameterCount; i++)
            {
                var parameter = parameters[i];
                if (!isTwoArmAnonymousUnion(parameter.Type))
                {
                    continue;
                }

                var hasDisallowedModifier =
                    parameter.Modifier is Ast.ParameterModifier.Ref or Ast.ParameterModifier.Out or Ast.ParameterModifier.Params;
                scratch.ParameterFlags[unionParameterCount] = hasDisallowedModifier ? 2 : 1;
                unionParameterCount++;
            }

            var result = bindings.AnonymousUnionDeclaresPublicShim(
                scratch.ParameterFlags,
                unionParameterCount);
            if (result is not 0 and not 1)
                return false;

            declaresShims = result != 0;
            return true;
        }
        catch
        {
            declaresShims = false;
            return false;
        }
    }

    /// <summary>
    /// Selects the winning declared-method overload index from a compact candidate table using the
    /// N# ranking kernel. The caller fills the rank columns for each surviving candidate through
    /// <paramref name="fillColumns"/> (writing one entry per candidate into the supplied buffers and
    /// returning the candidate count), and this routine runs the exact four-level tie-break
    /// (score &gt; non-generic &gt; non-params &gt; fewer-defaults, first-wins-on-tie) over those
    /// columns. <paramref name="selectedIndex"/> is the zero-based index of the winning candidate in
    /// fill order, or -1 when no candidate is valid.
    /// </summary>
    internal static bool TrySelectOverloadCandidate(
        int candidateCapacity,
        OverloadColumnFiller fillColumns,
        out int selectedIndex)
    {
        selectedIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (candidateCapacity < 0)
            return false;

        var scratch = t_overloadCandidateScratch ??= new OverloadCandidateScratch();
        scratch.EnsureCapacity(candidateCapacity);

        try
        {
            var count = fillColumns(
                scratch.ValidFlags,
                scratch.Scores,
                scratch.GenericFlags,
                scratch.ParamsFlags,
                scratch.DefaultsUsed);

            if (count < 0 || count > candidateCapacity)
                return false;

            var index = bindings.OverloadSelectBestCandidate(
                scratch.ValidFlags,
                scratch.Scores,
                scratch.GenericFlags,
                scratch.ParamsFlags,
                scratch.DefaultsUsed,
                count);

            if (index < -1 || index >= count)
                return false;

            selectedIndex = index;
            return true;
        }
        catch
        {
            selectedIndex = -1;
            return false;
        }
    }

    /// <summary>
    /// Fills the compact overload-candidate rank columns for surviving candidates and returns the
    /// candidate count.
    /// </summary>
    internal delegate int OverloadColumnFiller(
        int[] validFlags,
        int[] scores,
        int[] genericFlags,
        int[] paramsFlags,
        int[] defaultsUsed);

    internal static bool TrySelectMissingEnumMembers(
        IReadOnlyList<EnumMember> members,
        ISet<string> coveredMembers,
        out List<string> missingMembers)
    {
        missingMembers = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var memberCount = members.Count;
        if (memberCount == 0)
            return true;

        var scratch = t_missingEnumMemberScratch ??= new MissingEnumMemberScratch();
        scratch.EnsureCapacity(memberCount);

        try
        {
            scratch.ResetNames();
            for (var i = 0; i < memberCount; i++)
            {
                var memberName = members[i].Name;
                if (!scratch.AddName(memberName))
                    return false;

                scratch.CoveredFlags[i] = coveredMembers.Contains(memberName) ? 1 : 0;
            }

            var missingCount = bindings.AnalyzerMissingMemberIndices(
                scratch.CoveredFlags,
                memberCount,
                scratch.ResultIndices);

            if (missingCount < 0 || missingCount > memberCount || missingCount > scratch.ResultIndices.Length)
            {
                missingMembers = [];
                return false;
            }

            var result = new List<string>(missingCount);
            for (var i = 0; i < missingCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= memberCount)
                {
                    missingMembers = [];
                    return false;
                }

                result.Add(members[sourceIndex].Name);
            }

            missingMembers = result;
            return true;
        }
        catch
        {
            missingMembers = [];
            return false;
        }
        finally
        {
            scratch.ResetNames();
        }
    }

    internal static bool TrySelectMissingUnionCasesFromFlags(
        IReadOnlyList<UnionCase> cases,
        int[] coveredFlags,
        int[] partialFlags,
        int count,
        out List<string> missingCases,
        out List<string> partialMissingCases,
        out List<string> neverCoveredCases)
    {
        missingCases = [];
        partialMissingCases = [];
        neverCoveredCases = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (count < 0 || count > cases.Count || count > coveredFlags.Length || count > partialFlags.Length)
            return false;

        if (count == 0)
            return true;

        var scratch = t_missingUnionCaseScratch ??= new MissingUnionCaseScratch();
        scratch.EnsureCapacity(count);

        try
        {
            var missingCount = bindings.AnalyzerUnionMissingCaseIndices(
                coveredFlags,
                partialFlags,
                count,
                scratch.MissingIndices,
                scratch.PartialMissingIndices,
                scratch.NeverCoveredIndices,
                scratch.ResultCounts);

            var partialMissingCount = scratch.ResultCounts[1];
            var neverCoveredCount = scratch.ResultCounts[2];
            if (missingCount < 0 ||
                missingCount > count ||
                partialMissingCount < 0 ||
                partialMissingCount > missingCount ||
                neverCoveredCount < 0 ||
                neverCoveredCount > missingCount ||
                partialMissingCount + neverCoveredCount != missingCount)
            {
                missingCases = [];
                partialMissingCases = [];
                neverCoveredCases = [];
                return false;
            }

            missingCases = MaterializeCaseNames(cases, scratch.MissingIndices, missingCount);
            partialMissingCases = MaterializeCaseNames(cases, scratch.PartialMissingIndices, partialMissingCount);
            neverCoveredCases = MaterializeCaseNames(cases, scratch.NeverCoveredIndices, neverCoveredCount);
            return true;
        }
        catch
        {
            missingCases = [];
            partialMissingCases = [];
            neverCoveredCases = [];
            return false;
        }
    }

    private static List<string> MaterializeCaseNames(
        IReadOnlyList<UnionCase> cases,
        int[] indices,
        int count)
    {
        var result = new List<string>(count);
        for (var i = 0; i < count; i++)
        {
            var sourceIndex = indices[i];
            if (sourceIndex < 0 || sourceIndex >= cases.Count)
                throw new InvalidOperationException("Dogfood union missing-case selection returned an invalid source index.");

            result.Add(cases[sourceIndex].Name);
        }

        return result;
    }

    private static Bindings? LoadBindings()
    {
        try
        {
            var assembly = TryLoadDogfoodAssembly();
            var programType = assembly?.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                CreateDelegate<ParserTokenCompactionIndicesInto>(
                    programType,
                    "ParserTokenCompactionIndicesInto"),
                CreateDelegate<FormatterImportOrderIndicesInto>(
                    programType,
                    "FormatterImportOrderIndicesInto"),
                CreateDelegate<FirstDistinctRankIndicesInto>(
                    programType,
                    "FirstDistinctRankIndicesInto"),
                CreateDelegate<DeclaredTypeUniqueSuffixValueRank>(
                    programType,
                    "DeclaredTypeUniqueSuffixValueRank"),
                CreateDelegate<DeclaredTypeNameCandidateIndex>(
                    programType,
                    "DeclaredTypeNameCandidateIndex"),
                CreateDelegate<TypeCreationOrderIndicesInto>(
                    programType,
                    "TypeCreationOrderIndicesInto"),
                CreateDelegate<ReferenceFileSummaryRanksInto>(
                    programType,
                    "ReferenceFileSummaryRanksInto"),
                CreateDelegate<ProjectSourceFilterKeptIndicesInto>(
                    programType,
                    "ProjectSourceFilterKeptIndicesInto"),
                CreateDelegate<AnonymousUnionDeclaresPublicShim>(
                    programType,
                    "AnonymousUnionDeclaresPublicShim"),
                CreateDelegate<AnalyzerMissingMemberIndicesInto>(
                    programType,
                    "AnalyzerMissingMemberIndicesInto"),
                CreateDelegate<AnalyzerUnionMissingCaseIndicesInto>(
                    programType,
                    "AnalyzerUnionMissingCaseIndicesInto"),
                CreateDelegate<SemanticScopeBuildSortedIndexInto>(
                    programType,
                    "SemanticScopeBuildSortedIndexInto"),
                CreateDelegate<SemanticScopeBuildDepthsInto>(
                    programType,
                    "SemanticScopeBuildDepthsInto"),
                CreateDelegate<SemanticScopeVisibleSymbolIndicesInto>(
                    programType,
                    "SemanticScopeVisibleSymbolIndicesInto"),
                CreateDelegate<SemanticScopeLookupSymbolIndicesInto>(
                    programType,
                    "SemanticScopeLookupSymbolIndicesInto"),
                CreateDelegate<OverloadSelectBestCandidate>(
                    programType,
                    "OverloadSelectBestCandidate"),
                CreateDelegate<TokenizeMetadataWithIndentationInto>(
                    programType,
                    "TokenizeMetadataWithIndentationInto"),
                CreateDelegate<TopLevelDeclarationKindsInto>(
                    programType,
                    "TopLevelDeclarationKindsInto"),
                CreateDelegate<TopLevelDeclarationModifiersInto>(
                    programType,
                    "TopLevelDeclarationModifiersInto"),
                CreateDelegate<TopLevelDeclarationNameSpansInto>(
                    programType,
                    "TopLevelDeclarationNameSpansInto"),
                CreateDelegate<NamespaceImportSpansInto>(
                    programType,
                    "NamespaceImportSpansInto"),
                CreateDelegate<PackageNameSpanInto>(
                    programType,
                    "PackageNameSpanInto"),
                CreateDelegate<ParseFunctionSignatureInto>(
                    programType,
                    "ParseFunctionSignatureInto"),
                CreateDelegate<ParseStatementNodesInto>(
                    programType,
                    "ParseStatementNodesInto"),
                CreateDelegate<ParseEnumDeclarationInto>(
                    programType,
                    "ParseEnumDeclarationInto"),
                CreateDelegate<ParseStructDeclarationInto>(
                    programType,
                    "ParseStructDeclarationInto"),
                CreateDelegate<ParseUnionDeclarationInto>(
                    programType,
                    "ParseUnionDeclarationInto"),
                CreateDelegate<ParseConstructorChainInfoInto>(
                    programType,
                    "ParseConstructorChainInfoInto"));
        }
        catch
        {
            return null;
        }
    }

    private static Assembly? TryLoadDogfoodAssembly()
    {
        try
        {
            return Assembly.Load(new AssemblyName(DogfoodAssemblyName));
        }
        catch
        {
            var assemblyPath = Path.Combine(AppContext.BaseDirectory, $"{DogfoodAssemblyName}.dll");
            return File.Exists(assemblyPath)
                ? Assembly.LoadFrom(assemblyPath)
                : null;
        }
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

    private delegate int ParserTokenCompactionIndicesInto(int[] tokenKinds, int[] resultIndices);
    private delegate int FormatterImportOrderIndicesInto(
        int[] systemFlags,
        int[] nameRanks,
        int nameRankCount,
        int[] bucketCounts,
        int[] bucketOffsets,
        int[] tempIndices,
        int[] resultIndices);
    private delegate int FirstDistinctRankIndicesInto(
        int[] ranks,
        int uniqueRankCount,
        int[] seenRanks,
        int[] resultIndices);
    private delegate int DeclaredTypeUniqueSuffixValueRank(
        string[] keys,
        int[] valueRanks,
        int[] tailHashes,
        string typeName,
        int queryTailHash,
        int count);
    private delegate int DeclaredTypeNameCandidateIndex(
        string[] names,
        int[] importedNamespaceFlags,
        int[] tailHashes,
        string typeName,
        int queryTailHash,
        int count);
    private delegate int TypeCreationOrderIndicesInto(
        string[] keys,
        int count,
        int[] dotCounts,
        int[] depthCounts,
        int[] depthOffsets,
        int[] resultIndices);
    private delegate int ReferenceFileSummaryRanksInto(
        int[] fileRanks,
        int uniqueFileCount,
        int[] countsByRank,
        int[] resultRanks);
    private delegate int ProjectSourceFilterKeptIndicesInto(
        string[] relativePaths,
        string[] excludePatterns,
        int includeTests,
        int[] resultIndices);
    private delegate int AnonymousUnionDeclaresPublicShim(int[] parameterFlags, int count);
    private delegate int OverloadSelectBestCandidate(
        int[] validFlags,
        int[] scores,
        int[] genericFlags,
        int[] paramsFlags,
        int[] defaultsUsed,
        int count);
    private delegate int AnalyzerMissingMemberIndicesInto(int[] coveredFlags, int count, int[] resultIndices);
    private delegate int AnalyzerUnionMissingCaseIndicesInto(
        int[] coveredFlags,
        int[] partialFlags,
        int count,
        int[] missingIndices,
        int[] partialMissingIndices,
        int[] neverCoveredIndices,
        int[] resultCounts);
    private delegate int SemanticScopeVisibleSymbolIndicesInto(
        int[] scopeParentIds,
        int[] scopeStartLines,
        int[] scopeStartColumns,
        int[] scopeEndLines,
        int[] scopeEndColumns,
        int[] scopeDepths,
        int[] scopeSymbolStarts,
        int[] scopeSymbolCounts,
        int[] symbolNameIds,
        int[] sortedScopeIds,
        int[] sortedScopeStartLines,
        int[] sortedScopeStartColumns,
        int[] sortedScopeMaxEndLines,
        int[] queryLines,
        int[] queryColumns,
        int[] resultScopeIds,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultSymbolIndices,
        int[] slotNameIds,
        int[] touchedSlots);
    private delegate int SemanticScopeBuildSortedIndexInto(
        int[] scopeStartLines,
        int[] scopeStartColumns,
        int[] scopeEndLines,
        int[] tempScopeIds,
        int[] stackLefts,
        int[] stackRights,
        int[] sortedScopeIds,
        int[] sortedScopeStartLines,
        int[] sortedScopeStartColumns,
        int[] sortedScopeMaxEndLines);
    private delegate int SemanticScopeBuildDepthsInto(
        int[] scopeParentIds,
        int[] scopeDepths);
    private delegate int SemanticScopeLookupSymbolIndicesInto(
        int[] scopeParentIds,
        int[] scopeStartLines,
        int[] scopeStartColumns,
        int[] scopeEndLines,
        int[] scopeEndColumns,
        int[] scopeDepths,
        int[] scopeSymbolStarts,
        int[] scopeSymbolCounts,
        int[] symbolNameIds,
        int[] sortedScopeIds,
        int[] sortedScopeStartLines,
        int[] sortedScopeStartColumns,
        int[] sortedScopeMaxEndLines,
        int[] queryNameIds,
        int[] queryLines,
        int[] queryColumns,
        int[] resultScopeIds,
        int[] resultSymbolIndices);

    // Parser front-end kernels (slices 1-23): the N#-native columnar parser, loaded from the dogfood assembly.
    // These feed the columnar symbol/name/type/diagnostic services and the standalone columnar emit backend
    // (TryGetColumnarFunctionInputs -> ColumnarIlEmitter), consuming the columnar node tables directly.
    private delegate int TokenizeMetadataWithIndentationInto(
        string source, int[] kinds, int[] starts, int[] valueLengths, int[] lines, int[] columns);
    private delegate int TopLevelDeclarationKindsInto(int[] tokenKinds, int count, int[] outKinds);
    private delegate int TopLevelDeclarationModifiersInto(int[] tokenKinds, int count, int[] outKinds, int[] outModifiers);
    private delegate int TopLevelDeclarationNameSpansInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count,
        int[] outKinds, int[] outNameStarts, int[] outNameLengths);
    private delegate int NamespaceImportSpansInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count,
        int[] outNsStarts, int[] outNsLengths, int[] outAliasStarts, int[] outAliasLengths);
    private delegate int PackageNameSpanInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int[] outResult);
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
    private delegate int ParseEnumDeclarationInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int enumIndex,
        int[] outNameStarts, int[] outNameLengths, int[] outValueStarts, int[] outValueLengths,
        int[] outHasValue, int[] outResult);
    private delegate int ParseStructDeclarationInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int structIndex,
        int[] outFieldNameStarts, int[] outFieldNameLengths, int[] outFieldTypeStarts, int[] outFieldTypeLengths,
        int[] outFieldStaticFlags, int[] outFieldInitKinds, int[] outFieldInitStarts, int[] outFieldInitLengths,
        int[] outMethodFuncIndices, int[] outMethodStaticFlags, int[] outCtorIndices, int[] outPropIndices, int[] outPropStaticFlags,
        int[] outTypeParamStarts, int[] outTypeParamLengths, int[] outResult);
    private delegate int ParseUnionDeclarationInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int unionIndex,
        int[] outCaseNameStarts, int[] outCaseNameLengths, int[] outCaseFieldCounts,
        int[] outFieldNameStarts, int[] outFieldNameLengths, int[] outFieldTypeStarts, int[] outFieldTypeLengths,
        int[] outResult);
    private delegate int ParseConstructorChainInfoInto(
        int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int ctorIndex,
        int[] outArgKinds, int[] outArgStarts, int[] outArgLengths, int[] outResult);

    private sealed record Bindings(
        ParserTokenCompactionIndicesInto ParserTokenCompaction,
        FormatterImportOrderIndicesInto FormatterImportOrderIndices,
        FirstDistinctRankIndicesInto FirstDistinctRankIndices,
        DeclaredTypeUniqueSuffixValueRank DeclaredTypeUniqueSuffixValueRank,
        DeclaredTypeNameCandidateIndex DeclaredTypeNameCandidateIndex,
        TypeCreationOrderIndicesInto TypeCreationOrderIndices,
        ReferenceFileSummaryRanksInto ReferenceFileSummaryRanks,
        ProjectSourceFilterKeptIndicesInto ProjectSourceFilterKeptIndices,
        AnonymousUnionDeclaresPublicShim AnonymousUnionDeclaresPublicShim,
        AnalyzerMissingMemberIndicesInto AnalyzerMissingMemberIndices,
        AnalyzerUnionMissingCaseIndicesInto AnalyzerUnionMissingCaseIndices,
        SemanticScopeBuildSortedIndexInto SemanticScopeBuildSortedIndex,
        SemanticScopeBuildDepthsInto SemanticScopeBuildDepths,
        SemanticScopeVisibleSymbolIndicesInto SemanticScopeVisibleSymbolIndices,
        SemanticScopeLookupSymbolIndicesInto SemanticScopeLookupSymbolIndices,
        OverloadSelectBestCandidate OverloadSelectBestCandidate,
        TokenizeMetadataWithIndentationInto TokenizeMetadataWithIndentation,
        TopLevelDeclarationKindsInto TopLevelDeclarationKinds,
        TopLevelDeclarationModifiersInto TopLevelDeclarationModifiers,
        TopLevelDeclarationNameSpansInto TopLevelDeclarationNameSpans,
        NamespaceImportSpansInto NamespaceImportSpans,
        PackageNameSpanInto PackageNameSpan,
        ParseFunctionSignatureInto ParseFunctionSignature,
        ParseStatementNodesInto ParseStatementNodes,
        ParseEnumDeclarationInto ParseEnumDeclaration,
        ParseStructDeclarationInto ParseStructDeclaration,
        ParseUnionDeclarationInto ParseUnionDeclaration,
        ParseConstructorChainInfoInto ParseConstructorChainInfo);

    private sealed class SemanticScopeCache
    {
        private readonly object _gate = new();
        private readonly SemanticModel _model;
        private readonly Dictionary<string, int> _nameIds = new(StringComparer.Ordinal);
        private readonly int[] _lookupResultSymbolIndices = new int[1];
        private readonly int[] _queryColumns = new int[1];
        private readonly int[] _queryLines = new int[1];
        private readonly int[] _queryNameIds = new int[1];
        private readonly int[] _resultCounts = new int[1];
        private readonly int[] _resultScopeIds = new int[1];
        private readonly int[] _resultStarts = new int[1];

        private int[] _scopeDepths = Array.Empty<int>();
        private int[] _scopeEndColumns = Array.Empty<int>();
        private int[] _scopeEndLines = Array.Empty<int>();
        private int[] _scopeParentIds = Array.Empty<int>();
        private int[] _scopeStartColumns = Array.Empty<int>();
        private int[] _scopeStartLines = Array.Empty<int>();
        private int[] _scopeSymbolCounts = Array.Empty<int>();
        private int[] _scopeSymbolStarts = Array.Empty<int>();
        private int[] _resultSymbolIndices = Array.Empty<int>();
        private int[] _slotNameIds = Array.Empty<int>();
        private int[] _sortStackLefts = Array.Empty<int>();
        private int[] _sortStackRights = Array.Empty<int>();
        private int[] _sortTempScopeIds = Array.Empty<int>();
        private int[] _sortedScopeIds = Array.Empty<int>();
        private int[] _sortedScopeMaxEndLines = Array.Empty<int>();
        private int[] _sortedScopeStartColumns = Array.Empty<int>();
        private int[] _sortedScopeStartLines = Array.Empty<int>();
        private int[] _symbolNameIds = Array.Empty<int>();
        private string[] _symbolNames = Array.Empty<string>();
        private TypeInfo[] _symbolTypes = Array.Empty<TypeInfo>();
        private int[] _touchedSlots = Array.Empty<int>();
        private int _version = -1;

        public SemanticScopeCache(SemanticModel model)
        {
            _model = model;
        }

        public bool TryGetVisibleVariablesAtPosition(
            Bindings bindings,
            int line,
            int column,
            out Dictionary<string, TypeInfo> visibleVariables)
        {
            visibleVariables = new Dictionary<string, TypeInfo>();

            lock (_gate)
            {
                EnsureBuilt(bindings);
                if (_scopeParentIds.Length == 0)
                {
                    visibleVariables = new Dictionary<string, TypeInfo>(_model.Variables);
                    return true;
                }

                EnsureQueryCapacity();
                _queryLines[0] = line;
                _queryColumns[0] = column;
                _resultScopeIds[0] = -1;
                _resultStarts[0] = 0;
                _resultCounts[0] = 0;

                var total = bindings.SemanticScopeVisibleSymbolIndices(
                    _scopeParentIds,
                    _scopeStartLines,
                    _scopeStartColumns,
                    _scopeEndLines,
                    _scopeEndColumns,
                    _scopeDepths,
                    _scopeSymbolStarts,
                    _scopeSymbolCounts,
                    _symbolNameIds,
                    _sortedScopeIds,
                    _sortedScopeStartLines,
                    _sortedScopeStartColumns,
                    _sortedScopeMaxEndLines,
                    _queryLines,
                    _queryColumns,
                    _resultScopeIds,
                    _resultStarts,
                    _resultCounts,
                    _resultSymbolIndices,
                    _slotNameIds,
                    _touchedSlots);

                if (total < 0)
                    return false;

                if (_resultScopeIds[0] < 0)
                {
                    visibleVariables = new Dictionary<string, TypeInfo>(_model.Variables);
                    return true;
                }

                var start = _resultStarts[0];
                var count = _resultCounts[0];
                var result = new Dictionary<string, TypeInfo>(count);
                for (var i = 0; i < count; i++)
                {
                    var resultIndex = start + i;
                    if (resultIndex < 0 || resultIndex >= total || resultIndex >= _resultSymbolIndices.Length)
                        return false;

                    var symbolIndex = _resultSymbolIndices[resultIndex];
                    if (symbolIndex < 0 || symbolIndex >= _symbolNames.Length || symbolIndex >= _symbolTypes.Length)
                        return false;

                    result.TryAdd(_symbolNames[symbolIndex], _symbolTypes[symbolIndex]);
                }

                visibleVariables = result;
                return true;
            }
        }

        public bool TryLookupIdentifierAtPosition(
            Bindings bindings,
            string name,
            int line,
            int column,
            out TypeInfo? typeInfo)
        {
            typeInfo = null;

            lock (_gate)
            {
                EnsureBuilt(bindings);
                if (_scopeParentIds.Length == 0)
                {
                    typeInfo = _model.LookupIdentifier(name);
                    return true;
                }

                var nameId = GetExistingNameId(name);
                if (nameId < 0)
                {
                    typeInfo = LookupScopedFallback(name);
                    return true;
                }

                _queryNameIds[0] = nameId;
                _queryLines[0] = line;
                _queryColumns[0] = column;
                _resultScopeIds[0] = -1;
                _lookupResultSymbolIndices[0] = -1;

                var found = bindings.SemanticScopeLookupSymbolIndices(
                    _scopeParentIds,
                    _scopeStartLines,
                    _scopeStartColumns,
                    _scopeEndLines,
                    _scopeEndColumns,
                    _scopeDepths,
                    _scopeSymbolStarts,
                    _scopeSymbolCounts,
                    _symbolNameIds,
                    _sortedScopeIds,
                    _sortedScopeStartLines,
                    _sortedScopeStartColumns,
                    _sortedScopeMaxEndLines,
                    _queryNameIds,
                    _queryLines,
                    _queryColumns,
                    _resultScopeIds,
                    _lookupResultSymbolIndices);

                if (found < 0)
                    return false;

                var symbolIndex = _lookupResultSymbolIndices[0];
                if (symbolIndex >= 0 && symbolIndex < _symbolTypes.Length)
                {
                    typeInfo = _symbolTypes[symbolIndex];
                    return true;
                }

                typeInfo = LookupScopedFallback(name);
                return true;
            }
        }

        private void EnsureBuilt(Bindings bindings)
        {
            if (_version == _model.ScopeVersion)
                return;

            _nameIds.Clear();

            var scopes = _model.Scopes;
            var scopeCount = scopes.Count;
            _scopeParentIds = new int[scopeCount];
            _scopeStartLines = new int[scopeCount];
            _scopeStartColumns = new int[scopeCount];
            _scopeEndLines = new int[scopeCount];
            _scopeEndColumns = new int[scopeCount];
            _scopeDepths = new int[scopeCount];
            _scopeSymbolStarts = new int[scopeCount];
            _scopeSymbolCounts = new int[scopeCount];

            var symbolCount = 0;
            for (var i = 0; i < scopeCount; i++)
            {
                symbolCount += scopes[i].Variables.Count;
                symbolCount += scopes[i].Functions.Count;
            }

            _symbolNames = new string[symbolCount];
            _symbolTypes = new TypeInfo[symbolCount];
            _symbolNameIds = new int[symbolCount];

            var symbolIndex = 0;
            for (var i = 0; i < scopeCount; i++)
            {
                var scope = scopes[i];
                _scopeParentIds[i] = scope.ParentId;
                _scopeStartLines[i] = scope.StartLine;
                _scopeStartColumns[i] = scope.StartColumn;
                _scopeEndLines[i] = scope.EndLine;
                _scopeEndColumns[i] = scope.EndColumn;
                _scopeSymbolStarts[i] = symbolIndex;

                foreach (var (name, type) in scope.Variables)
                {
                    AddSymbol(name, type, ref symbolIndex);
                }

                foreach (var (name, type) in scope.Functions)
                {
                    AddSymbol(name, type, ref symbolIndex);
                }

                _scopeSymbolCounts[i] = symbolIndex - _scopeSymbolStarts[i];
            }

            BuildScopeDepths(bindings, scopeCount);
            BuildSortedScopeIndex(bindings, scopeCount);
            _version = _model.ScopeVersion;
        }

        private void BuildScopeDepths(Bindings bindings, int scopeCount)
        {
            if (scopeCount == 0)
                return;

            var dogfoodCount = bindings.SemanticScopeBuildDepths(_scopeParentIds, _scopeDepths);
            if (dogfoodCount == scopeCount)
                return;

            for (var i = 0; i < scopeCount; i++)
            {
                _scopeDepths[i] = ComputeScopeDepth(i);
            }
        }

        private void BuildSortedScopeIndex(Bindings bindings, int scopeCount)
        {
            _sortedScopeIds = new int[scopeCount];
            _sortedScopeStartLines = new int[scopeCount];
            _sortedScopeStartColumns = new int[scopeCount];
            _sortedScopeMaxEndLines = new int[scopeCount];
            _sortTempScopeIds = new int[scopeCount];
            _sortStackLefts = new int[scopeCount];
            _sortStackRights = new int[scopeCount];

            if (scopeCount == 0)
                return;

            var dogfoodCount = bindings.SemanticScopeBuildSortedIndex(
                _scopeStartLines,
                _scopeStartColumns,
                _scopeEndLines,
                _sortTempScopeIds,
                _sortStackLefts,
                _sortStackRights,
                _sortedScopeIds,
                _sortedScopeStartLines,
                _sortedScopeStartColumns,
                _sortedScopeMaxEndLines);

            if (dogfoodCount == scopeCount)
                return;

            var order = new int[scopeCount];
            for (var i = 0; i < scopeCount; i++)
            {
                order[i] = i;
            }

            Array.Sort(order, CompareScopeStartOrder);

            var maxEndLine = 0;
            for (var sortedIndex = 0; sortedIndex < scopeCount; sortedIndex++)
            {
                var scopeIndex = order[sortedIndex];
                _sortedScopeIds[sortedIndex] = scopeIndex;
                _sortedScopeStartLines[sortedIndex] = _scopeStartLines[scopeIndex];
                _sortedScopeStartColumns[sortedIndex] = _scopeStartColumns[scopeIndex];

                if (_scopeEndLines[scopeIndex] > maxEndLine)
                    maxEndLine = _scopeEndLines[scopeIndex];

                _sortedScopeMaxEndLines[sortedIndex] = maxEndLine;
            }
        }

        private int CompareScopeStartOrder(int left, int right)
        {
            var diff = _scopeStartLines[left].CompareTo(_scopeStartLines[right]);
            if (diff != 0)
                return diff;

            diff = _scopeStartColumns[left].CompareTo(_scopeStartColumns[right]);
            if (diff != 0)
                return diff;

            return left.CompareTo(right);
        }

        private void AddSymbol(string name, TypeInfo type, ref int symbolIndex)
        {
            _symbolNames[symbolIndex] = name;
            _symbolTypes[symbolIndex] = type;
            _symbolNameIds[symbolIndex] = GetOrAddNameId(name);
            symbolIndex++;
        }

        private int ComputeScopeDepth(int scopeIndex)
        {
            var depth = 0;
            var current = scopeIndex;
            while (current >= 0 && current < _scopeParentIds.Length)
            {
                var parent = _scopeParentIds[current];
                if (parent < 0 || parent == current)
                    break;

                depth++;
                current = parent;
            }

            return depth;
        }

        private int GetOrAddNameId(string name)
        {
            if (_nameIds.TryGetValue(name, out var id))
                return id;

            id = _nameIds.Count + 1;
            _nameIds.Add(name, id);
            return id;
        }

        private int GetExistingNameId(string name) => _nameIds.TryGetValue(name, out var id) ? id : -1;

        private TypeInfo? LookupScopedFallback(string name)
        {
            if (_model.Properties.TryGetValue(name, out var propType))
                return propType;
            if (_model.Fields.TryGetValue(name, out var fieldType))
                return fieldType;
            if (_model.Types.TryGetValue(name, out var type))
                return type;

            return null;
        }

        private void EnsureQueryCapacity()
        {
            var symbolCapacity = Math.Max(1, _symbolNameIds.Length);
            if (_resultSymbolIndices.Length < symbolCapacity)
            {
                _resultSymbolIndices = new int[symbolCapacity];
            }

            var slotCapacity = Math.Max(1, _symbolNameIds.Length * 2 + 1);
            if (_slotNameIds.Length < slotCapacity)
            {
                _slotNameIds = new int[slotCapacity];
            }

            if (_touchedSlots.Length < symbolCapacity)
            {
                _touchedSlots = new int[symbolCapacity];
            }
        }
    }

    private sealed class ParserTokenCompactionScratch
    {
        public int[] ResultIndices = Array.Empty<int>();
        public int[] TokenKinds = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (TokenKinds.Length != count)
            {
                TokenKinds = new int[count];
                ResultIndices = new int[count];
            }
        }
    }

    private sealed class FormatterImportOrderingScratch
    {
        // Distinct namespace strings keyed ordinally (so distinct strings stay distinct
        // entries), each mapped to a rank that reflects Comparer<string>.Default ordering.
        // Namespaces that compare EQUAL under that comparer share a rank, exactly mirroring
        // LINQ ThenBy(i => i.Namespace), whose ties are broken by original input order.
        private readonly Dictionary<string, int> _namespaceRanks = new(StringComparer.Ordinal);

        public int[] BucketCounts = Array.Empty<int>();
        public int[] BucketOffsets = Array.Empty<int>();
        public int[] NameRanks = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SystemFlags = Array.Empty<int>();
        public int[] TempIndices = Array.Empty<int>();
        public string[] UniqueNamespaces = Array.Empty<string>();
        public int UniqueNamespaceCount;

        public void EnsureCapacity(int count)
        {
            // Size the per-item arrays exactly to the logical import count: the kernel
            // derives its working count from systemFlags.Length, so these arrays must not
            // retain extra (stale) tail slots from a larger prior call on this thread.
            if (SystemFlags.Length != count)
            {
                SystemFlags = new int[count];
                NameRanks = new int[count];
                TempIndices = new int[count];
                ResultIndices = new int[count];
                UniqueNamespaces = new string[count];
            }

            // The name-pass counting sort uses ranks 1..uniqueRankCount; capacity must
            // cover the worst case where every namespace is distinct (uniqueRankCount == count).
            var bucketCapacity = count + 1;
            if (BucketCounts.Length != bucketCapacity)
            {
                BucketCounts = new int[bucketCapacity];
                BucketOffsets = new int[bucketCapacity];
            }
        }

        public void AddNamespace(string ns)
        {
            if (_namespaceRanks.ContainsKey(ns))
                return;

            _namespaceRanks.Add(ns, 0);
            UniqueNamespaces[UniqueNamespaceCount] = ns;
            UniqueNamespaceCount++;
        }

        public void BuildRanks()
        {
            Array.Sort(UniqueNamespaces, 0, UniqueNamespaceCount, Comparer<string>.Default);

            // Assign 1-based ranks; consecutive entries that compare equal under the
            // sort comparer share a rank so the kernel treats them as a stable tie.
            var rank = 0;
            for (var i = 0; i < UniqueNamespaceCount; i++)
            {
                if (i == 0 || Comparer<string>.Default.Compare(UniqueNamespaces[i], UniqueNamespaces[i - 1]) != 0)
                {
                    rank++;
                }

                _namespaceRanks[UniqueNamespaces[i]] = rank;
            }
        }

        public int GetRank(string ns) => _namespaceRanks[ns];

        public void ResetRanks()
        {
            _namespaceRanks.Clear();
            if (UniqueNamespaceCount > 0)
            {
                Array.Clear(UniqueNamespaces, 0, UniqueNamespaceCount);
                UniqueNamespaceCount = 0;
            }
        }
    }

    private sealed class ProjectSourceFilterScratch
    {
        public string[] RelativePaths = Array.Empty<string>();
        public int[] ResultIndices = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            // The kernel iterates relativePaths.Length, so this buffer must be sized exactly.
            if (RelativePaths.Length != count)
            {
                RelativePaths = new string[count];
                ResultIndices = new int[count];
            }
        }

        public void ClearRelativePaths(int count) => Array.Clear(RelativePaths, 0, count);
    }

    private sealed class AnonymousUnionShimScratch
    {
        public int[] ParameterFlags = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (ParameterFlags.Length < count)
            {
                ParameterFlags = new int[count];
            }
        }
    }

    private sealed class OverloadCandidateScratch
    {
        public int[] ValidFlags = Array.Empty<int>();
        public int[] Scores = Array.Empty<int>();
        public int[] GenericFlags = Array.Empty<int>();
        public int[] ParamsFlags = Array.Empty<int>();
        public int[] DefaultsUsed = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (ValidFlags.Length < count)
            {
                ValidFlags = new int[count];
                Scores = new int[count];
                GenericFlags = new int[count];
                ParamsFlags = new int[count];
                DefaultsUsed = new int[count];
            }
        }
    }

    private sealed class MissingEnumMemberScratch
    {
        private readonly HashSet<string> _seenNames = new(StringComparer.Ordinal);

        public int[] CoveredFlags = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();

        public bool AddName(string name) => _seenNames.Add(name);

        public void EnsureCapacity(int count)
        {
            if (CoveredFlags.Length < count)
            {
                CoveredFlags = new int[count];
                ResultIndices = new int[count];
            }
        }

        public void ResetNames()
        {
            _seenNames.Clear();
        }
    }

    private sealed class MissingUnionCaseScratch
    {
        public int[] MissingIndices = Array.Empty<int>();
        public int[] NeverCoveredIndices = Array.Empty<int>();
        public int[] PartialMissingIndices = Array.Empty<int>();
        public int[] ResultCounts = new int[3];

        public void EnsureCapacity(int count)
        {
            if (MissingIndices.Length < count)
            {
                MissingIndices = new int[count];
                NeverCoveredIndices = new int[count];
                PartialMissingIndices = new int[count];
            }

            if (ResultCounts.Length != 3)
            {
                ResultCounts = new int[3];
            }
        }
    }

    private sealed class FirstDistinctTypeKeyScratch
    {
        private readonly Dictionary<string, int> _keyRanks = new(StringComparer.Ordinal);

        public int[] ResultIndices = Array.Empty<int>();
        public int[] SeenRanks = Array.Empty<int>();
        public int[] TypeRanks = Array.Empty<int>();
        public int UniqueKeyCount;

        public void EnsureCapacity(int count)
        {
            if (TypeRanks.Length != count)
            {
                TypeRanks = new int[count];
                ResultIndices = new int[count];
            }

            var rankCapacity = count + 1;
            if (SeenRanks.Length != rankCapacity)
            {
                SeenRanks = new int[rankCapacity];
            }
        }

        public int AddKey(string key)
        {
            if (_keyRanks.TryGetValue(key, out var rank))
                return rank;

            rank = ++UniqueKeyCount;
            _keyRanks.Add(key, rank);
            return rank;
        }

        public void ResetKeys()
        {
            _keyRanks.Clear();
            UniqueKeyCount = 0;
        }
    }

    private sealed class FirstDistinctStringScratch(IEqualityComparer<string> comparer)
    {
        private readonly Dictionary<string, int> _keyRanks = new(comparer);

        public int[] Ranks = Array.Empty<int>();
        public int[] ResultIndices = Array.Empty<int>();
        public int[] SeenRanks = Array.Empty<int>();
        public int UniqueKeyCount;

        public void EnsureCapacity(int count)
        {
            if (Ranks.Length != count)
            {
                Ranks = new int[count];
                ResultIndices = new int[count];
            }

            var rankCapacity = count + 1;
            if (SeenRanks.Length != rankCapacity)
            {
                SeenRanks = new int[rankCapacity];
            }
        }

        public int AddKey(string key)
        {
            if (_keyRanks.TryGetValue(key, out var rank))
                return rank;

            rank = ++UniqueKeyCount;
            _keyRanks.Add(key, rank);
            return rank;
        }

        public void ResetKeys()
        {
            _keyRanks.Clear();
            UniqueKeyCount = 0;
        }
    }

    private sealed class DistinctOrderedStringScratch
    {
        private readonly Dictionary<string, int> _valueRanks = new(StringComparer.Ordinal);

        public int[] CountsByRank = Array.Empty<int>();
        public int[] ResultRanks = Array.Empty<int>();
        public string[] UniqueValues = Array.Empty<string>();
        public int[] ValueRanks = Array.Empty<int>();
        public string[] Values = Array.Empty<string>();
        public int UniqueValueCount;

        public void EnsureCapacity(int count)
        {
            if (ValueRanks.Length != count)
            {
                ValueRanks = new int[count];
                Values = new string[count];
                ResultRanks = new int[count];
                UniqueValues = new string[count];
            }

            var rankCapacity = count + 1;
            if (CountsByRank.Length != rankCapacity)
            {
                CountsByRank = new int[rankCapacity];
            }
        }

        public void AddValue(string value)
        {
            if (_valueRanks.ContainsKey(value))
                return;

            _valueRanks.Add(value, 0);
            UniqueValues[UniqueValueCount] = value;
            UniqueValueCount++;
        }

        public void BuildRanks()
        {
            Array.Sort(UniqueValues, 0, UniqueValueCount, StringComparer.Ordinal);
            for (var i = 0; i < UniqueValueCount; i++)
            {
                _valueRanks[UniqueValues[i]] = i + 1;
            }
        }

        public int GetRank(string value) => _valueRanks[value];

        public void ClearValues(int count) => Array.Clear(Values, 0, count);

        public void ResetValues()
        {
            _valueRanks.Clear();
            if (UniqueValueCount > 0)
            {
                Array.Clear(UniqueValues, 0, UniqueValueCount);
                UniqueValueCount = 0;
            }
        }
    }

    private sealed class DeclaredTypeSuffixLookupScratch
    {
        private readonly Dictionary<Type, int> _valueRanks = new();
        private object? _source;
        private int _sourceCount;
        private int _tailHashWidth = -1;

        public int Count;
        public string[] Keys = Array.Empty<string>();
        public int[] TailHashes = Array.Empty<int>();
        public int[] ValueRanks = Array.Empty<int>();
        public Type[] Values = Array.Empty<Type>();

        public bool Load<TType>(IReadOnlyDictionary<string, TType> types)
            where TType : Type
        {
            var count = types.Count;
            if (ReferenceEquals(_source, types) && _sourceCount == count && !CachedValuesContainUnbakedBuilder())
                return true;

            EnsureCapacity(count);
            _valueRanks.Clear();

            var index = 0;
            var uniqueValueCount = 0;
            foreach (var entry in types)
            {
                var value = entry.Value;
                if (value == null)
                    return false;

                if (!_valueRanks.TryGetValue(value, out var rank))
                {
                    rank = ++uniqueValueCount;
                    _valueRanks.Add(value, rank);
                    Values[rank] = value;
                }

                Keys[index] = entry.Key;
                ValueRanks[index] = rank;
                index++;
            }

            Count = count;
            _source = types;
            _sourceCount = count;
            _tailHashWidth = -1;
            return true;
        }

        // A cache hit keyed on (same dictionary instance, same count) is unsafe when the
        // dictionary's VALUES were replaced in place since we cached — e.g. ILCompiler's
        // FinalizeTopLevelEnumTypes swaps each EnumBuilder value for its baked Type while keeping
        // the same keys and count. If any cached value is still an unbaked reflection-emit builder,
        // force a reload so we don't hand back a stale EnumBuilder/TypeBuilder (M9).
        private bool CachedValuesContainUnbakedBuilder()
        {
            foreach (var value in _valueRanks.Keys)
            {
                if (value is System.Reflection.Emit.TypeBuilder or System.Reflection.Emit.EnumBuilder)
                {
                    return true;
                }
            }

            return false;
        }

        public void RefreshTailHashes(int width)
        {
            if (_tailHashWidth == width)
                return;

            for (var i = 0; i < Count; i++)
            {
                TailHashes[i] = GetTailHash(Keys[i], width);
            }

            _tailHashWidth = width;
        }

        public static int GetTailHashWidth(string text) => Math.Min(4, text.Length);

        public static int GetTailHash(string text, int width)
        {
            var hash = 0;
            for (var offset = 0; offset < width && offset < text.Length; offset++)
            {
                hash = hash * 31 + text[text.Length - 1 - offset];
            }

            return hash;
        }

        private void EnsureCapacity(int count)
        {
            if (Keys.Length < count)
            {
                Keys = new string[count];
                ValueRanks = new int[count];
                TailHashes = new int[count];
            }

            var valueCapacity = count + 1;
            if (Values.Length < valueCapacity)
            {
                Values = new Type[valueCapacity];
            }
        }
    }

    private sealed class DeclaredTypeNameCandidateScratch
    {
        private readonly HashSet<string> _importedNamespaces = new(StringComparer.Ordinal);
        private readonly Dictionary<string, int> _nameIndices = new(StringComparer.Ordinal);
        private CompilationUnit? _source;
        private int _sourceDeclarationCount;
        private int _sourceImportCount;
        private int _tailHashWidth = -1;

        public int Count;
        public int[] ImportedNamespaceFlags = Array.Empty<int>();
        public string[] Names = Array.Empty<string>();
        public int[] TailHashes = Array.Empty<int>();

        public void Load(CompilationUnit compilationUnit)
        {
            var declarationCount = compilationUnit.Declarations.Count;
            var importCount = compilationUnit.Imports.Count;
            if (ReferenceEquals(_source, compilationUnit)
                && _sourceDeclarationCount == declarationCount
                && _sourceImportCount == importCount)
            {
                return;
            }

            Count = 0;
            _tailHashWidth = -1;
            _nameIndices.Clear();
            _importedNamespaces.Clear();

            for (var i = 0; i < importCount; i++)
            {
                var import = compilationUnit.Imports[i];
                if (import.Alias == null)
                {
                    _importedNamespaces.Add(import.Namespace);
                }
            }

            for (var i = 0; i < declarationCount; i++)
            {
                AddDeclaration(compilationUnit.Declarations[i], containingTypeName: null);
            }

            for (var i = 0; i < Count; i++)
            {
                var namespaceName = GetNamespaceFromTypeName(Names[i]);
                ImportedNamespaceFlags[i] = string.IsNullOrEmpty(namespaceName) || _importedNamespaces.Contains(namespaceName)
                    ? 1
                    : 0;
            }

            _source = compilationUnit;
            _sourceDeclarationCount = declarationCount;
            _sourceImportCount = importCount;
        }

        public void RefreshTailHashes(int width)
        {
            if (_tailHashWidth == width)
                return;

            for (var i = 0; i < Count; i++)
            {
                TailHashes[i] = DeclaredTypeSuffixLookupScratch.GetTailHash(Names[i], width);
            }

            _tailHashWidth = width;
        }

        private void AddDeclaration(Declaration declaration, string? containingTypeName)
        {
            var name = GetDeclaredTypeName(declaration);
            if (string.IsNullOrWhiteSpace(name))
                return;

            var typeName = containingTypeName == null ? name : $"{containingTypeName}.{name}";
            if (!_nameIndices.ContainsKey(typeName))
            {
                EnsureCapacity(Count + 1);
                _nameIndices.Add(typeName, Count);
                Names[Count] = typeName;
                Count++;
            }

            AddNestedTypeDeclarations(declaration, typeName);
        }

        private void AddNestedTypeDeclarations(Declaration declaration, string containingTypeName)
        {
            switch (declaration)
            {
                case ClassDeclaration classDeclaration:
                    AddNestedTypeDeclarations(classDeclaration.Members, containingTypeName);
                    break;
                case StructDeclaration structDeclaration:
                    AddNestedTypeDeclarations(structDeclaration.Members, containingTypeName);
                    break;
                case RecordDeclaration recordDeclaration:
                    AddNestedTypeDeclarations(recordDeclaration.Members, containingTypeName);
                    break;
                case InterfaceDeclaration interfaceDeclaration:
                    AddNestedTypeDeclarations(interfaceDeclaration.Members, containingTypeName);
                    break;
            }
        }

        private void AddNestedTypeDeclarations(List<Declaration> members, string containingTypeName)
        {
            for (var i = 0; i < members.Count; i++)
            {
                var member = members[i];
                if (IsTypeDeclaration(member))
                {
                    AddDeclaration(member, containingTypeName);
                }
            }
        }

        private static string? GetDeclaredTypeName(Declaration declaration)
        {
            return declaration switch
            {
                ClassDeclaration classDeclaration => classDeclaration.Name,
                StructDeclaration structDeclaration => structDeclaration.Name,
                RecordDeclaration recordDeclaration => recordDeclaration.Name,
                InterfaceDeclaration interfaceDeclaration => interfaceDeclaration.Name,
                EnumDeclaration enumDeclaration => enumDeclaration.Name,
                UnionDeclaration unionDeclaration => unionDeclaration.Name,
                NewtypeDeclaration newtypeDeclaration => newtypeDeclaration.Name,
                _ => null
            };
        }

        private static bool IsTypeDeclaration(Declaration declaration)
        {
            return declaration is ClassDeclaration
                or StructDeclaration
                or RecordDeclaration
                or InterfaceDeclaration
                or EnumDeclaration
                or UnionDeclaration
                or NewtypeDeclaration;
        }

        private static string GetNamespaceFromTypeName(string typeName)
        {
            var separatorIndex = typeName.LastIndexOf('.');
            return separatorIndex >= 0 ? typeName[..separatorIndex] : string.Empty;
        }

        private void EnsureCapacity(int count)
        {
            if (Names.Length >= count)
                return;

            var newCapacity = Names.Length == 0 ? 8 : Names.Length * 2;
            while (newCapacity < count)
            {
                newCapacity *= 2;
            }

            Array.Resize(ref Names, newCapacity);
            Array.Resize(ref ImportedNamespaceFlags, newCapacity);
            Array.Resize(ref TailHashes, newCapacity);
        }
    }

    private sealed class TypeCreationOrderScratch
    {
        public int Count;
        public int[] DepthCounts = Array.Empty<int>();
        public int[] DepthOffsets = Array.Empty<int>();
        public int[] DotCounts = Array.Empty<int>();
        public string[] Keys = Array.Empty<string>();
        public int[] ResultIndices = Array.Empty<int>();
        public Type[] Values = Array.Empty<Type>();

        public bool Load<TType>(IEnumerable<TType> types, Func<TType, string> getTypeKey)
            where TType : Type
        {
            Count = 0;
            var maxKeyLength = 0;
            foreach (var type in types)
            {
                if (type == null)
                    return false;

                var key = getTypeKey(type);
                if (key == null)
                    return false;

                EnsureTypeCapacity(Count + 1);
                Values[Count] = type;
                Keys[Count] = key;
                if (key.Length > maxKeyLength)
                {
                    maxKeyLength = key.Length;
                }

                Count++;
            }

            EnsureDepthCapacity(maxKeyLength + 1);
            return true;
        }

        public void ClearValues()
        {
            for (var i = 0; i < Count; i++)
            {
                Values[i] = null!;
                Keys[i] = null!;
            }

            Count = 0;
        }

        private void EnsureTypeCapacity(int count)
        {
            if (Values.Length >= count)
                return;

            var newCapacity = Values.Length == 0 ? 8 : Values.Length * 2;
            while (newCapacity < count)
            {
                newCapacity *= 2;
            }

            Array.Resize(ref Values, newCapacity);
            Array.Resize(ref Keys, newCapacity);
            Array.Resize(ref DotCounts, newCapacity);
            Array.Resize(ref ResultIndices, newCapacity);
        }

        private void EnsureDepthCapacity(int count)
        {
            if (DepthCounts.Length >= count)
                return;

            var newCapacity = DepthCounts.Length == 0 ? 8 : DepthCounts.Length * 2;
            while (newCapacity < count)
            {
                newCapacity *= 2;
            }

            Array.Resize(ref DepthCounts, newCapacity);
            Array.Resize(ref DepthOffsets, newCapacity);
        }
    }
}
