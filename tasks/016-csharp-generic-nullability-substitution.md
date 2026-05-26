# Task 016: C# Generic Nullability Substitution

Priority: P2.

Make C# generic type-parameter nullability substitution precise when importing nullable metadata. Task 008 imports concrete C# nullability and keeps inferred N# generic bindings stable, but the compiler should also distinguish explicit C# `T?` contracts from unannotated `T` when substituting generic parameters.

## User Outcome

When an N# program calls a generic C# API, the inferred N# type should preserve the C# author's nullable intent without turning ordinary generic inference into nullable noise.

## Scope

- Decode raw nullable flags for generic parameter uses instead of relying only on `NullabilityInfoContext`.
- Preserve inferred N# nullability for unannotated generic `T`.
- Apply explicit `T?` and `T` annotations when substituting a bound reference type.
- Handle nested generic contracts such as `Dictionary<TKey, TValue?>`, delegates, expression trees, arrays, and return types.
- Keep overload resolution stable for LINQ, `String.Join`, and method-group-to-delegate binding.

## Acceptance

- A C# `T Echo<T>(T value)` imported into N# preserves the inferred argument type.
- A C# `T? Maybe<T>(T value)` imported into N# returns nullable when `T` is a reference type.
- LINQ/queryable inference remains non-null for non-null lambda returns unless the C# API explicitly annotates the generic result as nullable.
- Query, hover, and signature help agree on substituted generic nullability.

## Verification

- Add analyzer, query, and language-server tests with C# fixture APIs that cover `T`, `T?`, and nested generic `T?`.
- Keep existing LINQ, `String.Join`, and method-group tests green.
- Run `./scripts/test-all.sh` before committing.
