---
sidebar_label: All error codes
sidebar_position: 0
title: "N# error reference"
---

# N# error reference

Every diagnostic `nlc` prints carries a code, and every code has a page here. The compiler prints
the page's address on the last line of the diagnostic:

```text
error NL324: `Circle` does not implement 2 inherited abstract members: `Perimeter`, `Name`
  --> shapes.nl:7, column 7

Read more: https://schneidenbach.github.io/nsharplang/docs/errors/NL324
```

There are eighty **`NL` codes**, produced by the compiler and the linter, and nineteen **`NSYS`
codes**, produced by the systems analyzer when a project opts into a systems policy. The compiler
codes are grouped by the stage that reports them: the first digit tells you how far your program
got before something went wrong.

| Band | Reported by | What it means |
|---|---|---|
| `NL0xx` | the linter | The program compiles; something in it is dead, missing, or hiding a bug. |
| `NL1xx` | the parser | The text is not N#. Nothing else has run yet. |
| `NL2xx` | the type system | A type could not be found, inferred, or reconciled. |
| `NL3xx` | semantic analysis | The names and the control flow do not hold together. |
| `NL4xx` | call binding | A call does not match anything callable. |
| `NL5xx` | pattern matching | A `match` is incomplete, impossible, or ill-typed. |
| `NL6xx` | operator declarations | An `operator` overload is not a legal one. |
| `NL7xx` | imports | An `import` cannot be resolved, or resolves to two things. |
| `NL8xx` | type declarations | A class, struct or record declares an impossible shape. |
| `NL9xx` | the compiler | Convention, nullability, and the state of your references. |
| `NSYSxxx` | the systems analyzer | A systems policy — `[hot]`, `alloc(none)`, `[boundary]`, an `aotTarget` — was violated. |

Severity is policy, not code range: N# is **near-zero-warnings**, so almost every code in this
reference is a build-blocking error. The deliberate exceptions are noted on their own pages.

## Lint rules — `NL0xx`

The linter runs on every `nlc check`, `nlc build` and `nlc test`, and its findings block the build.
These are not style rules; style is `nlc format`'s job and produces no diagnostics at all.

| Code | Rule |
|---|---|
| `NL001` | A local is declared and never read. |
| `NL002` | A name resolves to nothing, and an import would fix it. |
| `NL003` | A null check on an expression that cannot be null. |
| `NL004` | An `async` function that never awaits. |
| `NL006` | A statement that cannot be reached. |
| `NL010` | An `import` nothing in the file uses. |
| `NL011` | A `catch` block with an empty body. |
| `NL012` | A parameter the function never reads. |
| `NL016` | A redundant null check — the value was already narrowed. |
| `NL020` | A local that shadows a name from an enclosing scope. |

## Syntax — `NL1xx`

| Code | Rule |
|---|---|
| `NL101` | A token the parser did not expect here. |
| `NL102` | A token the parser required and did not find. |
| `NL103` | A construct the compiler cannot represent or emit. |
| `NL104` | The file ended while something was still open. |
| [`NL105`](./NL105.md) | A literal the compiler cannot read as a literal. |
| `NL106` | A `{` with no `}`. |
| `NL107` | A `(` with no `)`. |
| `NL108` | A `[` with no `]`. |
| `NL109` | A reserved word used as a name. |
| `NL110` | A preprocessor directive N# does not have. |

## Types — `NL2xx`

| Code | Rule |
|---|---|
| `NL201` | A written type name resolves to nothing. |
| `NL202` | A value of one type is used where another is required. |
| `NL203` | A `:=` whose right-hand side has no inferable type. |
| `NL204` | A cast or `as` between types with no conversion. |
| `NL206` | A type expression that cannot be resolved to a single type. |
| `NL207` | A type argument that is not a legal argument here. |
| `NL208` | A type argument that violates the parameter's constraints. |

## Semantics — `NL3xx`

| Code | Rule |
|---|---|
| `NL301` | A variable used before it is declared, or never declared. |
| `NL302` | A type name used where no such type exists. |
| `NL303` | A member that the receiver's type does not have. |
| `NL304` | A read of something not assigned on every path. |
| `NL305` | A path out of a value-returning function with no `return`. |
| `NL306` | Two declarations of the same name in one scope. |
| `NL307` | A dependency that closes a cycle. |
| `NL308` | A member the calling code is not allowed to see. |
| `NL309` | A write to a `readonly` field outside its constructor. |
| `NL310` | An expression that must be a compile-time constant and is not. |
| `NL311` | A modifier that is not legal on this declaration. |
| `NL312` | A statement after control has already left. |
| `NL313` | An expression evaluated as a statement, with its value dropped. |
| `NL314` | An error-returning result used without being verified. |
| `NL315` | A must-use result discarded. |
| `NL316` | A declaration that shadows an enclosing one. |
| `NL317` | An event subscribed without `on`/`off`. |
| `NL318` | An event subscription that is not a legal one. |
| [`NL319`](./NL319.md) | Control leaving a `finally` block. |
| [`NL320`](./NL320.md) | A `lock` on a value type. |
| `NL321` | A sized-array constructor with the wrong arguments. |
| `NL322` | A member write through a copy of a value, which would be discarded. |
| `NL323` | A feature that parses but is deliberately not available in production builds. |
| [`NL324`](./NL324.md) | An inherited `abstract` member with no implementation. |
| [`NL325`](./NL325.md) | A declared interface the type does not fully implement. |

## Calls — `NL4xx`

| Code | Rule |
|---|---|
| `NL401` | A call with the wrong number of arguments. |
| `NL402` | A call that matches no overload. |
| `NL405` | A parameter declaration that is not legal. |
| `NL407` | A `params` parameter that is not last. |
| `NL409` | A required parameter after an optional one. |
| `NL410` | A default value that is not legal for the parameter. |
| `NL411` | A method named but not called, where a value is required. |
| `NL412` | A call target that is not a function, method or callable value. |

## Patterns — `NL5xx`

| Code | Rule |
|---|---|
| `NL501` | A `match` that does not cover every case. |
| `NL502` | An arm no value can reach, because an earlier arm covers it. |
| `NL503` | A pattern that is not a legal pattern. |
| `NL504` | A pattern that cannot match the type being matched. |
| `NL505` | A `when` guard that is not boolean. |
| `NL506` | A pattern that can never match anything. |

## Operators — `NL6xx`

| Code | Rule |
|---|---|
| `NL601` | An `operator` declaration that is not a legal overload. |
| `NL602` | An `operator` with the wrong number of parameters. |

## Imports — `NL7xx`

| Code | Rule |
|---|---|
| `NL701` | An `import` that resolves to nothing. |
| `NL702` | Two imports that bring in the same name. |
| `NL703` | An import cycle. |
| `NL704` | A namespace that does not exist. |

## Type declarations — `NL8xx`

| Code | Rule |
|---|---|
| `NL801` | More than one base class. |
| `NL802` | A base class declared `sealed`. |
| `NL803` | `new` on an `abstract` type. |
| `NL806` | A constructor declaration or call that is not legal. |

## Compiler diagnostics — `NL9xx`

| Code | Rule |
|---|---|
| `NL903` | A name whose casing contradicts N#'s visibility convention. |
| `NL905` | A nullable value dereferenced, indexed or called without a guard. |
| `NL907` | A nullability mismatch across an assignment or a call. |
| `NL923` | A referenced assembly failed to load, and names went unresolved because of it. **Advisory warning** — the one code in this range that never blocks a build. |

## Systems policy — `NSYSxxx`

These are reported only where a project opts in: `language.systems` in `project.yml`, a `[hot]` or
`[boundary]` function, an `alloc(none)` block, or an `aotTarget`. See
[Systems Programming](../systems.md).

| Code | Rule |
|---|---|
| `NSYS001` | A heap allocation in systems-strict code that is not marked `alloc`. |
| `NSYS010` | An allocation on a `[hot]` or `alloc(none)` path. |
| `NSYS020` | A boxing conversion on a hot path. |
| `NSYS030` | A delegate or closure constructed on a hot path. |
| `NSYS040` | Runtime dispatch on a hot path. |
| `NSYS050` | A call to an external function with no systems summary. |
| `NSYS060` | A call that blocks AOT or trimming for the declared target. |
| `NSYS070` | A systems-hostile type on a `[hot]` or `[boundary]` signature. |
| `NSYS080` | A `stackalloc` or ref-like value whose lifetime cannot be proven. |
| `NSYS090` | A disposable resource with no obvious disposal path. |
| `NSYS100` | A memory-safety operation outside an `unsafe` block. |
| `NSYS110` | A `[hot]` use of something that needs warmup first. |
| `NSYS120` | An unguarded trap — a throw or an unbounded index — on a hot path. |
| `NSYS130` | A pooled buffer rented and not returned. |
| `NSYS140` | A concurrency primitive with no systems semantics. |
| `NSYS150` | A sidecar `HotSummary` that cannot be audited for drift. |
| `NSYS160` | A `Result` returned by a call and ignored. |
| `NSYS170` | A `Result` ABI a systems surface cannot carry. |
| `NSYS180` | An `[allow]` waiver with no `reason`. |

## Codes that were retired

A diagnostic code is a promise: spell this mistake and the compiler will name it. Twenty-one codes
were published for years without a single place in the compiler that could report them, so the
promise could not be kept and no honest page could be written for them. They were retired on
2026-09-03, each one naming the code that enforces the rule instead.

| Retired | What reports the rule now |
|---|---|
| `NL205` ambiguous type | `NL303`, `NL704` |
| `NL403` missing required parameter | `NL401` |
| `NL404` duplicate parameter | `NL306` |
| `NL406` ref/out mismatch | `NL202` |
| `NL408` multiple `params` | `NL407` |
| `NL603` comparison operator pair | nothing — the rule was never written |
| `NL604` conversion operator invalid | nothing — the rule was never written |
| `NL804` interface implementation missing | `NL325` |
| `NL805` duck interface mismatch | `NL202`, at the argument that does not satisfy the interface |
| `NL901` unused variable | `NL001` |
| `NL902` unreachable code | `NL006` |
| `NL904` obsolete usage | nothing — N# has no obsolete-member rule |
| `NL950`–`NL954` allocation, boxing, dispatch | `NSYS010`, `NSYS020`, `NSYS030`, `NSYS040` |
| `NL960`–`NL963` AOT | `NSYS060` |

These numbers are **retired, not reused**. `NL906` was retired earlier for the same reason, and the
slot was not reused either.
