# Task 098: IL Compiler - Records

**Effort:** Medium (12-15 hours)
**Depends:** None (IL compiler Phase 7)
**Ships:** Records emit IL directly

## Goal

Emit IL for record types with value equality.

## Deliverable

Record declarations compile to IL classes with equality.

## Implementation

```csharp
void EmitRecordDeclaration(RecordDeclaration record)
{
    var typeBuilder = moduleBuilder.DefineType(
        record.Name,
        TypeAttributes.Public | TypeAttributes.Sealed,
        typeof(object));

    // Emit fields
    var fields = new List<FieldBuilder>();
    foreach (var prop in record.Properties)
    {
        var field = typeBuilder.DefineField(
            $"<{prop.Name}>k__BackingField",
            ResolveType(prop.Type),
            FieldAttributes.Private | FieldAttributes.InitOnly);

        fields.Add(field);

        // Emit property getter
        var getter = typeBuilder.DefineMethod(
            $"get_{prop.Name}",
            MethodAttributes.Public | MethodAttributes.SpecialName,
            ResolveType(prop.Type),
            Type.EmptyTypes);

        var il = getter.GetILGenerator();
        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Ldfld, field);
        il.Emit(OpCodes.Ret);
    }

    // Emit constructor
    EmitRecordConstructor(typeBuilder, fields);

    // Emit Equals
    EmitRecordEquals(typeBuilder, fields);

    // Emit GetHashCode
    EmitRecordGetHashCode(typeBuilder, fields);

    // Emit ToString
    EmitRecordToString(typeBuilder, record.Properties);

    typeBuilder.CreateType();
}
```

## Testing

```n#
record Person {
    Name: string,
    Age: int
}

p1 := new Person { Name: "Alice", Age: 30 }
p2 := new Person { Name: "Alice", Age: 30 }
assert p1 == p2  // Value equality
```

## Done When

- [ ] Records emit as classes
- [ ] Value equality works
- [ ] ToString works
- [ ] Immutable by default
- [ ] Tests pass
