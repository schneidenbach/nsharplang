# Task 097: IL Compiler - Pattern Matching

**Effort:** Large (20-25 hours)
**Depends:** None (IL compiler Phase 7)
**Ships:** Pattern matching emits IL directly

## Goal

Complete pattern matching IL emission.

## Current Status

IL compiler Phases 1-5 complete, Phase 7 partial (4/8 features).
This task completes pattern matching from Phase 7.

## Deliverable

Match expressions compile to IL without transpilation.

## Implementation

Emit IL for switch expressions:

```csharp
void EmitMatchExpression(MatchExpression match)
{
    var endLabel = il.DefineLabel();
    var labels = new Label[match.Cases.Count];

    for (int i = 0; i < match.Cases.Count; i++)
        labels[i] = il.DefineLabel();

    // Emit value to match
    EmitExpression(match.Value);

    // Emit comparisons for each case
    for (int i = 0; i < match.Cases.Count; i++)
    {
        var pattern = match.Cases[i].Pattern;

        if (pattern is LiteralPattern lit)
        {
            il.Emit(OpCodes.Dup);
            EmitLiteral(lit.Value);
            il.Emit(OpCodes.Beq, labels[i]);
        }
        else if (pattern is TypePattern type)
        {
            il.Emit(OpCodes.Dup);
            il.Emit(OpCodes.Isinst, ResolveType(type.Type));
            il.Emit(OpCodes.Brtrue, labels[i]);
        }
    }

    // No match - throw
    il.Emit(OpCodes.Pop);
    il.Emit(OpCodes.Ldstr, "No matching case");
    il.Emit(OpCodes.Newobj, typeof(MatchException).GetConstructor(...));
    il.Emit(OpCodes.Throw);

    // Emit case bodies
    for (int i = 0; i < match.Cases.Count; i++)
    {
        il.MarkLabel(labels[i]);
        il.Emit(OpCodes.Pop); // Pop duplicate
        EmitExpression(match.Cases[i].Body);
        il.Emit(OpCodes.Br, endLabel);
    }

    il.MarkLabel(endLabel);
}
```

## Testing

```n#
result := match x {
    0 => "zero",
    1 => "one",
    _ => "other"
}
```

## Done When

- [ ] Literal patterns work
- [ ] Type patterns work
- [ ] Union patterns work
- [ ] Guards work
- [ ] Tests pass
