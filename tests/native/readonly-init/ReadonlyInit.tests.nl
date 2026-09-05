namespace NSharpLang.ReadonlyInit.Tests

import System
import System.Collections
import System.IO
import System.Reflection

// --- Execution: readonly initializers hold their values after construction -------------------------
test "a readonly-only class initializes both readonly fields through its synthesized default constructor" {
    r := new ReadonlyOnly()
    assert r.Pi == 3.14159
    assert r.Label == "ro"
}

test "a mutable-only class initializes its fields through the helper the constructor calls" {
    m := new MutableOnly()
    assert m.Count == 5
    assert m.Name == "m"
}

test "a mixed class inlines the readonly store and keeps the mutable store in the helper" {
    x := new Mixed()
    assert x.Ro == 1
    assert x.Mut == 2
}

test "a static readonly initializer runs in the type initializer and an instance readonly inlines in the ctor" {
    s := new StaticAndInstance()
    assert StaticAndInstance.Shared == 99
    assert s.Local == 2.5
}

test "the RecordsAndInterfaces.Circle shape: a readonly initializer inlines ahead of the ctor body" {
    // Pi is initialized inline; Radius is assigned by the explicit constructor. Area proves both stores ran.
    c := new ExplicitCtor(5.0)
    assert c.Radius == 5.0
    assert c.Pi == 3.14159
    assert c.Area() == 78.53975
}

test "a readonly initializer is inlined in EACH of multiple constructors" {
    a := new MultiCtor(55)
    b := new MultiCtor()
    assert a.Base == 100
    assert a.Value == 55
    assert b.Base == 100
    assert b.Value == 0
}

test "a this-chaining constructor does not re-run the field initializer: the delegated ctor sets it once" {
    t := new ThisChained()
    assert t.Tag == 42
    assert t.X == 9
}

test "inheritance: each type inlines its own readonly initializer in its own constructor" {
    d := new Dog()
    assert d.Legs == 4
    assert d.Name == "Rex"
}

test "an explicit base-chaining constructor initializes the base readonly then the derived readonly" {
    t := new Triangle()
    assert t.Sides == 3
    assert t.Kind == "triangle"
    assert t.Color == "red"
}

test "a record with a readonly field initializer initializes it through the object-initializer path" {
    g := new Tagged { Id: 7 }
    assert g.Id == 7
    assert g.Kind == "default"
}

// --- Persisted execution ---------------------------------------------------------------------------

test "a readonly-initialized instance persists through a local and reads back its initializer values" {
    original := new ReadonlyOnly()
    stored := original
    assert stored.Pi == 3.14159
    assert stored.Label == "ro"
}

// --- Reflection: the initonly attribute is emitted for readonly fields, not mutable ones ------------

test "readonly fields carry the initonly attribute and mutable fields do not" {
    roField := typeof(Mixed).GetField("Ro")
    mutField := typeof(Mixed).GetField("Mut")
    assert roField != null, "the readonly field Ro must be present"
    assert mutField != null, "the mutable field Mut must be present"
    if roField != null {
        assert roField.get_IsInitOnly(), "a readonly field must be emitted initonly"
    }
    if mutField != null {
        assert !mutField.get_IsInitOnly(), "a mutable field must not be emitted initonly"
    }
}

// --- Exact placement: the <InitializeFields>$ helper exists ONLY when a mutable store needs it ------
// A readonly store is unverifiable in the helper, so a readonly-only type carries no helper at all; the
// readonly stores are inlined directly in each constructor (which ILVerify confirms over this assembly).

test "a readonly-only type synthesizes NO <InitializeFields>$ helper" {
    hasHelper := false
    methods := typeof(ReadonlyOnly).GetRuntimeMethods()
    for method in methods {
        if method.get_Name() == "<InitializeFields>$" {
            hasHelper = true
        }
    }
    assert !hasHelper, "a readonly-only type must inline its stores, not route them through a helper"
}

test "a mutable-only type synthesizes the <InitializeFields>$ helper" {
    hasHelper := false
    methods := typeof(MutableOnly).GetRuntimeMethods()
    for method in methods {
        if method.get_Name() == "<InitializeFields>$" {
            hasHelper = true
        }
    }
    assert hasHelper, "a mutable-field initializer keeps the helper"
}

test "a mixed type keeps the helper for its mutable store while inlining the readonly store" {
    hasHelper := false
    methods := typeof(Mixed).GetRuntimeMethods()
    for method in methods {
        if method.get_Name() == "<InitializeFields>$" {
            hasHelper = true
        }
    }
    assert hasHelper, "a mixed type keeps the helper for the mutable store"
}

test "a class whose only initialized readonly field is set in the explicit constructor keeps no helper" {
    hasHelper := false
    methods := typeof(ExplicitCtor).GetRuntimeMethods()
    for method in methods {
        if method.get_Name() == "<InitializeFields>$" {
            hasHelper = true
        }
    }
    assert !hasHelper, "the Circle shape has only a readonly initializer, so it needs no helper"
}

// --- Invalid reassignment declines through the production compiler ----------------------------------

class ReadonlyInitFixtureResult {
    Succeeded: bool
    Diagnostics: string

    constructor(succeeded: bool, diagnostics: string) {
        Succeeded = succeeded
        Diagnostics = diagnostics
    }
}

func SetFixtureObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

// Drive the real production compiler on a single-file fixture through the public whole-project emit route
// and report whether it succeeded plus the first diagnostic.
func CompileReadonlyInitFixture(source: string): ReadonlyInitFixtureResult {
    fixtureRoot := Path.Combine(
        Path.GetTempPath(),
        "nsharp-readonly-init-" + Guid.NewGuid().ToString("N")
    )
    Directory.CreateDirectory(fixtureRoot)
    File.WriteAllText(Path.Combine(fixtureRoot, "Program.nl"), source)

    compilerType := Type.GetType("NSharpLang.Compiler.MultiFileCompiler, Compiler")
    projectConfigType := Type.GetType(
        "NSharpLang.Compiler.ProjectConfig, NSharpLang.Compiler.BootstrapServices"
    )
    if compilerType == null || projectConfigType == null {
        throw new InvalidOperationException("The production compiler types were not loadable.")
    }

    configConstructor := projectConfigType.GetConstructor(new Type[](0))
    if configConstructor == null {
        throw new InvalidOperationException("The production project configuration constructor was not found.")
    }
    config := configConstructor.Invoke(new object?[](0))

    constructorTypes := new Type[](2)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = projectConfigType
    constructor := compilerType.GetConstructor(constructorTypes)
    if constructor == null {
        throw new InvalidOperationException("The production compiler constructor was not found.")
    }
    constructorArguments := new object?[](2)
    SetFixtureObject(constructorArguments, 0, fixtureRoot)
    SetFixtureObject(constructorArguments, 1, config)
    compiler := constructor.Invoke(constructorArguments)

    compileParameterTypes := new Type[](4)
    compileParameterTypes[0] = typeof(string)
    compileParameterTypes[1] = typeof(string)
    compileParameterTypes[2] = typeof(bool)
    compileParameterTypes[3] = typeof(bool)
    compileMethod := compilerType.GetMethod("CompileToIlAssembly", compileParameterTypes)
    if compileMethod == null {
        throw new InvalidOperationException("The production compiler entry point was not found.")
    }
    compileArguments := new object?[](4)
    SetFixtureObject(compileArguments, 0, "ReadonlyInitFixture")
    SetFixtureObject(
        compileArguments,
        1,
        Path.Combine(fixtureRoot, "out/ReadonlyInitFixture.dll")
    )
    SetFixtureObject(compileArguments, 2, false)
    // validateWithLegacyAnalysis: true — run the full analysis pipeline so the readonly-reassignment
    // diagnostic (NL309) is produced, not just an emit-only pass.
    SetFixtureObject(compileArguments, 3, true)
    compilation := compileMethod.Invoke(compiler, compileArguments)
    if compilation == null {
        throw new InvalidOperationException("The production compiler returned no compilation result.")
    }

    compilationType := compilation.GetType()
    successProperty := compilationType.GetProperty("Success")
    errorsProperty := compilationType.GetProperty("Errors")
    if successProperty == null || errorsProperty == null {
        throw new InvalidOperationException("The production compilation result contract was incomplete.")
    }
    successValue := successProperty.GetValue(compilation)
    errorsValue := errorsProperty.GetValue(compilation)
    errors := errorsValue as IList
    if successValue == null || errors == null {
        throw new InvalidOperationException("The production compilation result values were incomplete.")
    }

    diagnostics := ""
    if errors.Count > 0 {
        firstError := errors[0]
        if firstError == null {
            throw new InvalidOperationException("The production compiler returned a null diagnostic.")
        }
        errorType := firstError.GetType()
        formatParameterTypes := new Type[](2)
        formatParameterTypes[0] = typeof(bool)
        formatParameterTypes[1] = typeof(bool)
        formatMethod := errorType.GetMethod("FormatForTooling", formatParameterTypes)
        if formatMethod == null {
            throw new InvalidOperationException("The production diagnostic contract was incomplete.")
        }
        formatArguments := new object?[](2)
        SetFixtureObject(formatArguments, 0, true)
        SetFixtureObject(formatArguments, 1, false)
        formattedValue := formatMethod.Invoke(firstError, formatArguments)
        if formattedValue == null {
            throw new InvalidOperationException("The production diagnostic values were incomplete.")
        }
        diagnostics = formattedValue.ToString() ?? ""
    }

    succeeded := successValue.ToString() == "True"
    Directory.Delete(fixtureRoot, true)
    return new ReadonlyInitFixtureResult(succeeded, diagnostics)
}

test "assigning a readonly field outside a constructor is rejected (NL309)" {
    result := CompileReadonlyInitFixture(
        """
class Widget {
    readonly Size: int = 10

    func Resize(n: int) {
        Size = n
    }
}

func main() {
    w := new Widget()
    w.Resize(5)
}
"""
    )
    assert !result.Succeeded, result.Diagnostics
    assert result.Diagnostics.Contains("NL309"), result.Diagnostics
}

test "a well-formed readonly initializer compiles cleanly through the production emitter" {
    result := CompileReadonlyInitFixture(
        """
class Circle {
    readonly Radius: double
    readonly Pi: double = 3.14159

    constructor(radius: double) {
        Radius = radius
    }
}

func main() {
    c := new Circle(2.0)
    _ := c
}
"""
    )
    assert result.Succeeded, result.Diagnostics
}
