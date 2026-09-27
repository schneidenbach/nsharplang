namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit

// These controls use the public N# resolver only.  They intentionally cover normal bool/out paths;
// exception and enumerator-disposal timing remains in the product owner's direct resolver tests.
func SourceDefinitionControlDefinition(builder: TypeBuilder, isInterface: bool, name: string): ColumnarStructDef {
    definition := new ColumnarStructDef(
        builder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        name
    )
    definition.IsInterface = isInterface
    return definition
}

func SourceDefinitionControlClosed(builder: TypeBuilder): Type {
    arguments := new Type[](1)
    arguments[0] = typeof(int)
    open: Type = builder
    return open.MakeGenericType(arguments)
}

// The reflected BCL singleton stays boxed: these controls need only its exact object identity,
// and do not depend on an otherwise-unadmitted object-to-array downcast.
func SourceDefinitionControlBclEmptyTypeArray(): object? {
    emptyDefinition := typeof(Array).GetMethod("Empty")
    if emptyDefinition == null || !emptyDefinition.get_IsGenericMethodDefinition() {
        throw new InvalidOperationException("System.Array.Empty<T>() was not found.")
    }

    typeArguments := new Type[](1)
    typeArguments[0] = typeof(Type)
    closedEmpty := emptyDefinition.MakeGenericMethod(typeArguments)
    noArguments := new object[](0)
    value := TypeOfRequiredInvocation(closedEmpty, null, noArguments)
    if value == null {
        throw new InvalidOperationException("System.Array.Empty<Type>() did not return Type[].")
    }
    return value
}

test "source definition builder identity uses first current row and live registry changes" {
    shared := TypeOfCreateBuilder("Shared", "ColumnarSourceDefinitionDiscoveryControls.Shared", 0)
    first := SourceDefinitionControlDefinition(shared, false, "First")
    second := SourceDefinitionControlDefinition(shared, false, "Second")
    definitions := new ColumnarStructDef[](2)
    definitions[0] = first
    definitions[1] = second

    selected: ColumnarStructDef? = null
    assert ColumnarSourceDefinitionResolver.TryFindByBuilderIdentity(definitions, shared, out selected)
    assert Object.ReferenceEquals(selected, first)
    assert Object.ReferenceEquals(ColumnarSourceDefinitionResolver.FindByBuilderIdentity(definitions, shared), first)

    definitions[0] = second
    definitions[1] = first
    selected = null
    assert ColumnarSourceDefinitionResolver.TryFindByBuilderIdentity(definitions, shared, out selected)
    assert Object.ReferenceEquals(selected, second)

    changed := TypeOfCreateBuilder("Changed", "ColumnarSourceDefinitionDiscoveryControls.Changed", 0)
    second.Builder = changed
    selected = null
    assert ColumnarSourceDefinitionResolver.TryFindByBuilderIdentity(definitions, shared, out selected)
    assert Object.ReferenceEquals(selected, first)
    selected = null
    assert ColumnarSourceDefinitionResolver.TryFindByBuilderIdentity(definitions, changed, out selected)
    assert Object.ReferenceEquals(selected, second)

    absent := TypeOfCreateBuilder("Absent", "ColumnarSourceDefinitionDiscoveryControls.Absent", 0)
    selected = first
    assert !ColumnarSourceDefinitionResolver.TryFindByBuilderIdentity(definitions, absent, out selected)
    assert selected == null
    assert ColumnarSourceDefinitionResolver.FindByBuilderIdentity(definitions, absent) == null
}

test "source interface resolution keeps the first resolved classification and clears normal misses" {
    shared := TypeOfCreateBuilder("Interface", "ColumnarSourceDefinitionDiscoveryControls.Interface", 0)
    classDefinition := SourceDefinitionControlDefinition(shared, false, "Class")
    interfaceDefinition := SourceDefinitionControlDefinition(shared, true, "Interface")
    definitions := new ColumnarStructDef[](2)
    definitions[0] = classDefinition
    definitions[1] = interfaceDefinition

    resolved: ColumnarStructDef? = null
    assert ColumnarSourceDefinitionResolver.TryResolveStruct(shared, definitions, out resolved)
    assert Object.ReferenceEquals(resolved, classDefinition)

    resolved = interfaceDefinition
    assert !ColumnarSourceDefinitionResolver.TryResolveInterface(shared, definitions, out resolved)
    assert resolved == null

    definitions[0] = interfaceDefinition
    definitions[1] = classDefinition
    resolved = null
    assert ColumnarSourceDefinitionResolver.TryResolveInterface(shared, definitions, out resolved)
    assert Object.ReferenceEquals(resolved, interfaceDefinition)

    absent := TypeOfCreateBuilder("InterfaceAbsent", "ColumnarSourceDefinitionDiscoveryControls.InterfaceAbsent", 0)
    resolved = interfaceDefinition
    assert !ColumnarSourceDefinitionResolver.TryResolveStruct(absent, definitions, out resolved)
    assert resolved == null
}

test "source definition direct null and closed receiver paths retain separate contracts" {
    expectedEmpty := SourceDefinitionControlBclEmptyTypeArray()
    expectedEmptyAgain := SourceDefinitionControlBclEmptyTypeArray()
    assert expectedEmpty != null
    assert expectedEmptyAgain != null
    assert Object.ReferenceEquals(expectedEmpty, expectedEmptyAgain)

    open := TypeOfCreateBuilder("Generic", "ColumnarSourceDefinitionDiscoveryControls.Generic", 1)
    definition := SourceDefinitionControlDefinition(open, false, "Generic")
    definitions := new ColumnarStructDef[](1)
    definitions[0] = definition
    registry := new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
    registry["Generic"] = definition
    closed := SourceDefinitionControlClosed(open)

    assert Object.ReferenceEquals(ColumnarSourceDefinitionResolver.FindDirectType(registry, open), definition)
    assert ColumnarSourceDefinitionResolver.FindDirectType(registry, closed) == null
    noType: Type = null
    assert ColumnarSourceDefinitionResolver.FindDirectType(registry, noType) == null

    resolved: ColumnarStructDef? = null
    assert ColumnarSourceDefinitionResolver.TryResolveStruct(closed, definitions, out resolved)
    assert Object.ReferenceEquals(resolved, definition)

    closedDefinition: ColumnarStructDef? = null
    closedArguments := new Type[](0)
    assert ColumnarSourceDefinitionResolver.TryResolveClosedReceiver(closed, registry, out closedDefinition, out closedArguments)
    assert Object.ReferenceEquals(closedDefinition, definition)
    assert closedArguments.Length == 1
    assert closedArguments[0] == typeof(int)

    closedDefinition = definition
    closedArguments = new Type[](1)
    closedArguments[0] = typeof(string)
    assert !ColumnarSourceDefinitionResolver.TryResolveClosedReceiver(open, registry, out closedDefinition, out closedArguments)
    assert closedDefinition == null
    assert closedArguments.Length == 0
    assert Object.ReferenceEquals(closedArguments, expectedEmpty)

    assert ColumnarSourceDefinitionResolver.FindDirectType(null, typeof(int)) == null
    assert ColumnarSourceDefinitionResolver.FindDirectType(null, noType) == null

    directRegistryThrew := false
    try {
        candidate := ColumnarSourceDefinitionResolver.FindDirectType(null, open)
        if candidate != null {
            throw new InvalidOperationException("Null registry unexpectedly resolved a direct builder")
        }
        throw new InvalidOperationException("Null registry unexpectedly returned from direct builder lookup")
    } catch error: NullReferenceException {
        directRegistryThrew = true
    }
    assert directRegistryThrew

    closedDefinition = definition
    closedArguments = new Type[](1)
    closedArguments[0] = typeof(string)
    assert !ColumnarSourceDefinitionResolver.TryResolveClosedReceiver(open, null, out closedDefinition, out closedArguments)
    assert closedDefinition == null
    assert Object.ReferenceEquals(closedArguments, expectedEmpty)

    nullReceiver: Type = null
    closedDefinition = definition
    closedArguments = new Type[](1)
    closedArguments[0] = typeof(string)
    nullReceiverThrew := false
    try {
        if ColumnarSourceDefinitionResolver.TryResolveClosedReceiver(nullReceiver, null, out closedDefinition, out closedArguments) {
            throw new InvalidOperationException("Null receiver unexpectedly resolved as closed")
        }
        throw new InvalidOperationException("Null receiver unexpectedly returned from closed lookup")
    } catch error: NullReferenceException {
        nullReceiverThrew = true
    }
    assert nullReceiverThrew
    assert closedDefinition == null
    assert Object.ReferenceEquals(closedArguments, expectedEmpty)
}

test "source discovery preserves caller slots around direct source null failures" {
    builder := TypeOfCreateBuilder("Null", "ColumnarSourceDefinitionDiscoveryControls.Null", 0)
    definition := SourceDefinitionControlDefinition(builder, false, "Null")
    definitions := new ColumnarStructDef[](1)
    definitions[0] = definition
    registry := new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
    registry["Null"] = definition
    nullSource: Type = null

    structResult: ColumnarStructDef? = definition
    structThrew := false
    try {
        if ColumnarSourceDefinitionResolver.TryResolveStruct(nullSource, definitions, out structResult) {
            throw new InvalidOperationException("Null source unexpectedly resolved as a struct")
        }
        throw new InvalidOperationException("Null source unexpectedly returned from struct lookup")
    } catch error: NullReferenceException {
        structThrew = true
    }
    assert structThrew
    assert Object.ReferenceEquals(structResult, definition)

    interfaceResult: ColumnarStructDef? = definition
    interfaceThrew := false
    try {
        if ColumnarSourceDefinitionResolver.TryResolveInterface(nullSource, definitions, out interfaceResult) {
            throw new InvalidOperationException("Null source unexpectedly resolved as an interface")
        }
        throw new InvalidOperationException("Null source unexpectedly returned from interface lookup")
    } catch error: NullReferenceException {
        interfaceThrew = true
    }
    assert interfaceThrew
    assert Object.ReferenceEquals(interfaceResult, definition)

    closedResult: ColumnarStructDef? = definition
    closedArguments := new Type[](1)
    closedArguments[0] = typeof(string)
    closedThrew := false
    try {
        if ColumnarSourceDefinitionResolver.TryResolveClosedReceiver(nullSource, registry, out closedResult, out closedArguments) {
            throw new InvalidOperationException("Null source unexpectedly resolved as a closed receiver")
        }
        throw new InvalidOperationException("Null source unexpectedly returned from closed receiver lookup")
    } catch error: NullReferenceException {
        closedThrew = true
    }
    assert closedThrew
    assert closedResult == null
    assert closedArguments.Length == 0
    expectedEmpty := SourceDefinitionControlBclEmptyTypeArray()
    assert Object.ReferenceEquals(closedArguments, expectedEmpty)

    secondClosedResult: ColumnarStructDef? = definition
    secondClosedArguments := new Type[](1)
    secondClosedArguments[0] = typeof(string)
    secondClosedThrew := false
    try {
        if ColumnarSourceDefinitionResolver.TryResolveClosedReceiver(nullSource, registry, out secondClosedResult, out secondClosedArguments) {
            throw new InvalidOperationException("Second null source unexpectedly resolved as a closed receiver")
        }
        throw new InvalidOperationException("Second null source unexpectedly returned from closed receiver lookup")
    } catch error: NullReferenceException {
        secondClosedThrew = true
    }
    assert secondClosedThrew
    assert secondClosedResult == null
    assert secondClosedArguments.Length == 0
    assert Object.ReferenceEquals(secondClosedArguments, expectedEmpty)
    assert Object.ReferenceEquals(closedArguments, secondClosedArguments)
}
