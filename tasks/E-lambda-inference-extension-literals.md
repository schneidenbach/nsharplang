# Task E: Lambda Contextual Inference + Extension Methods on Literals

## Context

Two related gaps in expression type resolution, both in `src/NSharpLang.Compiler/Analyzer.cs`.

## Problem 1: Lambda Contextual Type Inference for N# Functions

Currently, lambda parameter types are inferred when calling .NET methods (LINQ etc.) via the `BindReflectionCall` path in Analyzer.cs (~line 2683). But for N#-declared higher-order functions, inference fails:

```n#
func Apply(f: Func<int, int>): int { return f(42) }
Apply(x => x * 2)  // x should infer as int — currently typed as Unknown
```

The expected delegate type (`Func<int, int>`) needs to propagate into lambda parameter inference. Read how `BindReflectionCall` does it for .NET methods and replicate that logic for N#-declared function calls.

### Where to look:
- `Analyzer.cs` — `BindReflectionCall` (~line 2683) for the working .NET path
- `Analyzer.cs` — `ResolveCallExpression` for N#-declared function dispatch
- `Analyzer.cs` — `AnalyzeLambda` for how lambda parameter types are resolved
- `/Users/claude/repos/roslyn` — search for `LambdaSymbol` or `UnboundLambda` for Roslyn's approach

### Test cases:
- `Apply(x => x * 2)` where `Apply` takes `Func<int, int>` — x should be int
- `Transform(items, x => x.Length)` where Transform takes `List<string>, Func<string, int>` — x should be string
- Nested lambdas: `Process((x, y) => x + y)` where Process takes `Func<int, int, int>`
- Lambda with block body: `Apply(x => { return x * 2 })` — same inference

## Problem 2: Extension Methods on Literals

Extension methods work on variables but not on literals:

```n#
count := 5
count.Times(() => print "hi")  // ✅ works
5.Times(() => print "hi")      // ❌ doesn't work — literal has no type info for extension lookup
```

The issue is that literal expressions don't always carry precise enough type info when the member access resolver tries to find extension methods.

### Where to look:
- `Analyzer.cs` — member access resolution path
- `ExpressionTypeResolver.cs` — how literal types are determined
- `Analyzer.cs` — extension method resolution

### Fix:
Ensure int/string/bool/double literals resolve their CLR type (`System.Int32`, `System.String`, etc.) before member access resolution, so extension methods can be found via reflection.

### Test cases:
- `5.Times(() => print "hi")` where Times is an extension on int
- `"hello".IsEmpty()` where IsEmpty is an extension on string
- `3.14.Round()` where Round is an extension on double
- Chaining: `5.Clamp(0, 10).ToString()`

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md
