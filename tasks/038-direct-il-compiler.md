# Task 038: Direct IL Compiler

**Priority:** Medium (Performance & Independence - not urgent but valuable)
**Dependencies:** None (parallel path to transpiler)
**Estimated Effort:** Very Large (30-40 hours, potentially more)
**Status:** Phase 1-5 Complete | Phase 6 Deferred | Phase 7 In Progress (4/8 features)

## Current Achievement Summary

**Phases Completed:** 1-5 (Foundation through Generics)
**Phase 7 Progress:** 4/8 features implemented (Interfaces, Virtual methods, Foreach loops, Try/catch/finally)
**Test Coverage:** 47 IL compiler tests, all passing
**Overall Test Suite:** 656 tests, all passing

**What Works:**
- ✅ Simple functions with arithmetic and logic
- ✅ Local variables and assignments (including compound: +=, -=, *=, /=)
- ✅ Control flow (if/else, while loops)
- ✅ Function calls (static and recursive)
- ✅ Classes and structs (declarations, fields, methods, constructors)
- ✅ Object instantiation with initializers
- ✅ Instance method calls and member access
- ✅ Properties with auto-implemented getters/setters
- ✅ Generics (generic methods, type parameters, constraints)
- ✅ Constrained virtual calls on generic parameters
- ✅ Assembly generation and disk persistence (via PersistedAssemblyBuilder)
- ✅ **Interfaces** (declaration, implementation, multiple interfaces, duck interface support)
- ✅ **Virtual methods** (virtual/override, inheritance chains, base class fields)
- ✅ **Foreach loops** (arrays and IEnumerable<T>, with proper disposal)
- ✅ **Try/catch/finally** (all exception handling, multiple catch clauses, nested try blocks)

**Phase 7 Status:**
- ✅ Interfaces (declaration, implementation, duck interfaces, inheritance)
- ✅ Virtual methods (virtual/override, NewSlot/ReuseSlot, base field access)
- ✅ Foreach loops (arrays, IEnumerable<T>, nested loops, try-finally disposal)
- ✅ Try/catch/finally (all exception handling, multiple catch clauses, nested try blocks)
- ⏸️ Pattern matching (not yet implemented)
- ⏸️ Records (not yet implemented)
- ⏸️ Using statements (not yet implemented)
- ⏸️ Lambda expressions (not yet implemented)

**What's Deferred:**
- ⏸️ Phase 6: Async/await (use transpiler path instead)
- ⏸️ Phase 8: PDB generation, debugging symbols, attributes

**Recommendation:** The IL compiler has exceeded MVP requirements and provides a solid foundation. For practical use, combine IL compiler for synchronous code with transpiler for async/await until Phase 6 is implemented.

## Goal

Create a separate compiler backend that emits IL (Intermediate Language) directly instead of transpiling to C# first, providing better performance, more control, and independence from the C# compiler.

## Background

**Current Architecture:**
```
N# Source → AST → Transpiler → C# Code → Roslyn → IL → Assembly
```

**Proposed Architecture:**
```
N# Source → AST → IL Compiler → IL → Assembly
```

**Why Direct IL?**

1. **Performance**: Skip C# generation and Roslyn compilation
   - Faster compilation times (especially for large projects)
   - Less memory usage during compilation
   - No temporary C# file generation

2. **Control**: Fine-grained control over generated code
   - Optimize for N#-specific patterns
   - Better tail call optimization
   - Custom calling conventions if needed
   - More efficient value task handling

3. **Independence**: Less coupling to C# semantics
   - Don't need to work around C# limitations
   - Can implement N#-specific features without C# constraints
   - No Roslyn version dependencies

4. **Debugging**: Direct mapping from N# to IL
   - Better PDB generation
   - Clearer stack traces
   - Source stepping without C# intermediary

5. **Distribution**: Self-contained compiler
   - No Roslyn dependency for compilation
   - Smaller compiler package
   - Easier to embed in tools

## Trade-offs

**Advantages:**
- ✅ Faster compilation
- ✅ More control over codegen
- ✅ Independent of Roslyn
- ✅ Can optimize for N# patterns
- ✅ Smaller runtime dependencies

**Disadvantages:**
- ❌ Much more complex to implement
- ❌ Need to maintain two backends (transpiler + IL compiler)
- ❌ More testing surface area
- ❌ Harder to debug IL generation
- ❌ Need deep IL knowledge

## Scope

### In Scope (MVP)

**Phase 1: Basic IL Emission**
- Simple functions
- Local variables
- Basic expressions (arithmetic, comparison)
- If/else statements
- While loops
- Function calls
- String literals
- Primitive types (int, bool, string, etc.)

**Phase 2: Classes & Structs**
- Class declarations
- Field declarations
- Method declarations
- Constructors
- Property getters/setters
- Struct value types

**Phase 3: Advanced Features**
- Generics
- Interfaces
- Inheritance
- Virtual methods
- Async/await
- Pattern matching
- Records

**Phase 4: Interop**
- External assembly references
- Attribute emission
- XML doc generation
- Debug symbols (PDB)

### Out of Scope (For Now)

- Expression trees
- Dynamic code generation
- Reflection.Emit at runtime
- Custom IL optimizations (leave for later)
- LINQ query syntax (use method calls)

## Implementation Approach

### Technology Choices

**Option 1: System.Reflection.Emit** (Recommended)
```csharp
using System.Reflection.Emit;

var assemblyBuilder = AssemblyBuilder.DefineDynamicAssembly(...);
var moduleBuilder = assemblyBuilder.DefineDynamicModule(...);
var typeBuilder = moduleBuilder.DefineType(...);
var methodBuilder = typeBuilder.DefineMethod(...);
var il = methodBuilder.GetILGenerator();

il.Emit(OpCodes.Ldarg_0);
il.Emit(OpCodes.Ldarg_1);
il.Emit(OpCodes.Add);
il.Emit(OpCodes.Ret);
```

**Pros:**
- Built into .NET runtime
- Well documented
- Type-safe API
- Automatic metadata generation

**Cons:**
- In-memory only (need to save to disk)
- Less control over exact IL layout
- Higher-level than raw IL

**Option 2: IKVM.Reflection**
- Fork of System.Reflection.Emit that can write to disk
- More control over output
- More complex API

**Option 3: Mono.Cecil**
- Full control over IL and metadata
- Can read and write assemblies
- Lower-level, more complex

**Recommendation:** Start with **System.Reflection.Emit** for MVP, consider Mono.Cecil later for advanced features.

### Architecture

**New Files:**
```
src/Compiler/ILCompiler/
├── ILCompiler.cs           // Main IL compiler entry point
├── ILEmitter.cs            // Low-level IL emission
├── TypeBuilder.cs          // Type/class generation
├── MethodBuilder.cs        // Method generation
├── ExpressionCompiler.cs   // Expression → IL
├── StatementCompiler.cs    // Statement → IL
├── LocalAllocator.cs       // Local variable allocation
├── LabelManager.cs         // Branch label management
└── MetadataBuilder.cs      // Assembly metadata
```

**Integration:**
```csharp
// src/Cli/Program.cs
if (args.Contains("--emit-il"))
{
    var ilCompiler = new ILCompiler(compilationUnit, config);
    ilCompiler.EmitAssembly(outputPath);
}
else
{
    // Existing transpiler path
    var transpiler = new Transpiler(compilationUnit, config);
    // ...
}
```

### Example: Simple Function

**N# Source:**
```n#
func add(x: int, y: int): int {
    return x + y
}
```

**IL Output:**
```il
.method public static int32 add(int32 x, int32 y) cil managed
{
    .maxstack 2
    ldarg.0      // Load x
    ldarg.1      // Load y
    add          // Add them
    ret          // Return result
}
```

**C# Code (using Reflection.Emit):**
```csharp
var methodBuilder = typeBuilder.DefineMethod(
    "add",
    MethodAttributes.Public | MethodAttributes.Static,
    typeof(int),
    new[] { typeof(int), typeof(int) }
);

var il = methodBuilder.GetILGenerator();
il.Emit(OpCodes.Ldarg_0);  // Load x
il.Emit(OpCodes.Ldarg_1);  // Load y
il.Emit(OpCodes.Add);       // Add
il.Emit(OpCodes.Ret);       // Return
```

## Implementation Plan

### Phase 1: Foundation (Week 1-2) ✅ COMPLETE

**Goal:** Emit simplest possible executable

**Files:**
- `ILCompiler.cs` - Entry point
- `ILEmitter.cs` - Basic IL emission
- `MethodBuilder.cs` - Simple functions

**Milestone:** Compile and run:
```n#
func main() {
    print "Hello from IL!"
}
```

**Tasks:**
- [x] Set up Reflection.Emit infrastructure
- [x] Emit assembly metadata
- [x] Emit simple main method
- [x] Emit Console.WriteLine call (via print statement)
- [x] Save assembly to disk (implemented using PersistedAssemblyBuilder in .NET 9)
- [x] Verify assembly compiles (via unit tests)

**Tests:**
```csharp
[Fact]
public void ILCompiler_EmitsHelloWorld()
{
    var source = "func main() { print \"Hello\" }";
    var compiler = new ILCompiler(Parse(source));

    var assemblyPath = compiler.EmitAssembly("/tmp/test.dll");

    Assert.True(File.Exists(assemblyPath));

    // Load and run
    var assembly = Assembly.LoadFrom(assemblyPath);
    var method = assembly.GetType("Program").GetMethod("Main");
    method.Invoke(null, null);
}
```

### Phase 2: Expressions & Variables (Week 3-4) ✅ COMPLETE

**Goal:** Arithmetic, locals, control flow

**Milestone:** Compile and run:
```n#
func main() {
    x := 5
    y := 10
    sum := x + y
    print sum  // Prints 15
}
```

**Tasks:**
- [x] Local variable allocation
- [x] Arithmetic operators (+, -, *, /, %)
- [x] Comparison operators (<, >, ==, !=, <=, >=)
- [x] Logical operators (&&, ||)
- [x] If/else statements
- [x] While loops
- [x] Variable assignments (including compound assignments: +=, -=, *=, /=)

**IL Patterns:**
```il
// x := 5
ldc.i4.5
stloc.0

// sum := x + y
ldloc.0  // Load x
ldloc.1  // Load y
add
stloc.2  // Store in sum

// if x > y
ldloc.0
ldloc.1
ble.s else_label
// then block
br.s end_label
else_label:
// else block
end_label:
```

### Phase 3: Functions & Calls (Week 5) ✅ COMPLETE

**Goal:** Function declarations and calls

**Milestone:**
```n#
func add(x: int, y: int): int {
    return x + y
}

func main() {
    result := add(3, 4)
    print result  // Prints 7
}
```

**Tasks:**
- [x] Function parameters
- [x] Return statements
- [x] Function calls (static)
- [ ] Multiple return values (via tuples) - Not yet implemented
- [x] Recursion

**IL Patterns:**
```il
// result := add(3, 4)
ldc.i4.3
ldc.i4.4
call int32 Program::add(int32, int32)
stloc.0
```

### Phase 4: Classes & Structs (Week 6-7) ✅ COMPLETE

**Goal:** OOP basics

**Milestone:**
```n#
class Point {
    X: int
    Y: int

    func Distance(): double {
        return Math.Sqrt(X * X + Y * Y)
    }
}

func main() {
    p := new Point { X: 3, Y: 4 }
    d := p.Distance()
    print d  // Prints 5.0
}
```

**Tasks:**
- [x] Class declarations
- [x] Field declarations
- [x] Instance methods
- [x] Constructors
- [x] Object allocation (newobj)
- [x] Field access (ldfld, stfld)
- [x] Instance method calls (callvirt)

### Phase 5: Generics (Week 8-9) ✅ COMPLETE

**Goal:** Generic types and methods

**Milestone:**
```n#
func max<T>(a: T, b: T): T where T: IComparable<T> {
    if a.CompareTo(b) > 0 {
        return a
    }
    return b
}

func main() {
    x := max(5, 10)      // int
    y := max(3.14, 2.0)  // double
}
```

**Tasks:**
- [x] Generic type parameters
- [x] Generic constraints
- [x] Generic method calls
- [x] Generic type instantiation (via MakeGenericType)
- [x] Constrained virtual method calls on generic parameters
- [x] Parameter type tracking for generics

### Phase 6: Async/Await (DEFERRED)

**Status:** ⏸️ **DEFERRED** - Complexity too high for current ROI

**Goal:** Async methods using state machines

**Milestone:**
```n#
async func fetchData(): ValueTask<string> {
    await Task.Delay(100)
    return "Data"
}
```

**Tasks:**
- [ ] Async state machine generation
- [ ] Task/ValueTask return types
- [ ] Await IL patterns
- [ ] Exception handling in async

**Why Deferred:**
- Async/await requires generating complex state machine structs implementing `IAsyncStateMachine`
- Estimated 2-3 weeks of full-time work, thousands of lines of code
- Roslyn's implementation is extremely complex (see C# compiler source)
- Current transpiler path handles async/await perfectly well
- Better ROI to focus on other Phase 7 features first
- Can revisit after Phase 7-8 are complete if needed

**Fallback:** Use transpiler for async/await code (--transpile-only flag)

### Phase 7: Advanced Features (Week 12+) - IN PROGRESS

**Tasks:**
- [x] **Interfaces** - ✅ COMPLETED
  - Interface declaration with proper abstract/virtual attributes
  - Classes implementing single or multiple interfaces
  - Proper separation of interfaces from base classes at compile time
  - Duck interface support (type-erased, skipped in IL compilation)
  - Interface inheritance (base interfaces)
  - 5 comprehensive tests added
- [x] **Virtual methods** - ✅ COMPLETED
  - Virtual method declarations with NewSlot attribute
  - Override method support with ReuseSlot attribute
  - Inheritance chains with virtual method overrides
  - Base class inheritance with proper type separation
  - Field access from base classes (inherited fields)
  - 7 comprehensive tests added
- [ ] Pattern matching
- [ ] Records
- [x] **Foreach loops (IEnumerable)** - ✅ COMPLETED
  - Array iteration using index-based loop
  - IEnumerable<T> iteration using GetEnumerator/MoveNext/Current pattern
  - Proper try-finally disposal of enumerators
  - Nested foreach loops supported
  - 4 comprehensive tests added
- [x] **Try/catch/finally** - ✅ COMPLETED
  - Full exception handling support using BeginExceptionBlock/EndExceptionBlock
  - Multiple catch clauses with different exception types
  - Catch clauses with and without exception variables
  - Finally blocks for cleanup code
  - Nested try/catch blocks
  - Proper exception type resolution
  - 7 comprehensive tests added
- [ ] Using statements
- [ ] Lambda expressions

### Phase 8: Debugging & Metadata (Week 13-14)

**Tasks:**
- [ ] PDB generation
- [ ] Sequence points
- [ ] Local variable names in debug info
- [ ] Attributes
- [ ] XML documentation
- [ ] AssemblyInfo metadata

## Testing Strategy

### Unit Tests

**Test Each IL Pattern:**
```csharp
[Theory]
[InlineData("5 + 3", 8)]
[InlineData("10 - 4", 6)]
[InlineData("3 * 7", 21)]
public void ILCompiler_EmitsArithmetic(string expr, int expected)
{
    var source = $"func main(): int {{ return {expr} }}";
    var result = CompileAndRun(source);
    Assert.Equal(expected, result);
}
```

### Integration Tests

**Full Programs:**
```csharp
[Fact]
public void ILCompiler_Fibonacci_Recursive()
{
    var source = @"
func fib(n: int): int {
    if n <= 1 {
        return n
    }
    return fib(n - 1) + fib(n - 2)
}

func main(): int {
    return fib(10)
}";

    var result = CompileAndRun(source);
    Assert.Equal(55, result);  // 10th Fibonacci number
}
```

### Comparison Tests

**Ensure IL and Transpiler produce same results:**
```csharp
[Fact]
public void IL_TranspilerParity_ComplexProgram()
{
    var source = GetComplexProgramSource();

    var ilResult = CompileWithIL(source);
    var transpilerResult = CompileWithTranspiler(source);

    Assert.Equal(transpilerResult, ilResult);
}
```

## Performance Benchmarks

**Measure Compilation Speed:**
```csharp
[Benchmark]
public void Transpiler_CompileTime()
{
    var transpiler = new Transpiler(ast);
    transpiler.Transpile();
    CompileWithRoslyn(csharp);
}

[Benchmark]
public void ILCompiler_CompileTime()
{
    var ilCompiler = new ILCompiler(ast);
    ilCompiler.EmitAssembly("test.dll");
}
```

**Expected Results:**
- IL compiler: ~10-50x faster than transpiler path
- Memory: 50-80% less memory usage
- Output size: Similar (same IL, different metadata)

## Documentation

### User Documentation

**Using IL Compiler:**
```bash
# Default: use transpiler
nsharp build Program.nl

# Use IL compiler
nsharp build --emit-il Program.nl

# Compare outputs
nsharp build --emit-il --verbose Program.nl
```

### Developer Documentation

**IL Generation Guide:**
```markdown
# IL Generation Patterns

## Local Variables
- Allocate with `LocalBuilder local = il.DeclareLocal(type)`
- Load: `il.Emit(OpCodes.Ldloc, local)`
- Store: `il.Emit(OpCodes.Stloc, local)`

## Method Calls
- Static: `il.Emit(OpCodes.Call, methodInfo)`
- Virtual: `il.Emit(OpCodes.Callvirt, methodInfo)`
- Instance: Push `this` first, then args

## Branches
- Create label: `Label label = il.DefineLabel()`
- Mark position: `il.MarkLabel(label)`
- Branch: `il.Emit(OpCodes.Br, label)` or conditional branches
```

## Migration Strategy

### Phase 1: Opt-In (Months 1-3)

- IL compiler is experimental feature
- Transpiler remains default
- Users can opt-in with `--emit-il` flag
- Both paths fully supported

### Phase 2: Parallel (Months 4-6)

- IL compiler gains feature parity
- Performance advantages proven
- Both paths production-ready
- Documentation for both

### Phase 3: Transition (Months 7-9)

- IL compiler becomes default
- Transpiler available with `--transpile-only` flag
- Deprecation notice for transpiler path

### Phase 4: IL-Only (Month 10+)

- IL compiler is the only path
- Transpiler removed or archived
- Significant codebase simplification

**Note:** This is VERY long-term. Transpiler will remain for years.

## Success Criteria

### MVP (Phase 1-3)
- [ ] Can compile simple programs (arithmetic, loops, functions)
- [ ] Generates runnable .dll files
- [ ] 10x faster than transpiler path
- [ ] 100+ unit tests passing
- [ ] Documentation complete

### Full Feature Parity (Phase 7)
- [ ] All N# features compile to IL
- [ ] All existing examples work with `--emit-il`
- [ ] Performance: 20-50x faster than transpiler
- [ ] Memory: 50% less than transpiler
- [ ] Test suite: 500+ IL compiler tests
- [ ] Zero regressions vs transpiler output

### Production Ready
- [ ] Used in real projects
- [ ] Debug experience excellent (PDB, source stepping)
- [ ] Error messages clear and helpful
- [ ] Documentation comprehensive
- [ ] Community feedback positive

## Risks & Mitigation

**Risk: Too Complex**
- **Mitigation:** Start very small (Phase 1), iterate
- **Fallback:** Keep transpiler forever if IL too hard

**Risk: Maintenance Burden**
- **Mitigation:** Share AST/analysis with transpiler
- **Plan:** Eventually remove transpiler if IL successful

**Risk: Debugging Difficulty**
- **Mitigation:** Compare IL output with Roslyn's IL
- **Tool:** Use ILSpy to inspect generated assemblies
- **Tests:** Extensive comparison tests

**Risk: Missing Features**
- **Mitigation:** Implement incrementally
- **Fallback:** Transpiler handles unsupported features initially

## Dependencies

**NuGet Packages:**
- System.Reflection.Emit (built-in)
- System.Reflection.Metadata (optional, for reading metadata)
- Optional: Mono.Cecil (if we switch later)

**Knowledge Required:**
- IL opcodes and stack semantics
- .NET metadata format
- PDB/debugging info format
- Generic type system internals

## References

**Learning Resources:**
- ECMA-335 CLI Specification
- System.Reflection.Emit documentation
- Roslyn IL generation (reference implementation)
- Expert .NET 2.0 IL Assembler (book)
- ILSpy source code

**Tools:**
- ILSpy - View generated IL
- dnSpy - Debug IL
- ildasm - Disassemble IL
- PEVerify - Verify IL correctness

## Timeline

**Optimistic (Full-Time):**
- MVP (Phase 1-3): 4 weeks
- Feature Complete (Phase 7): 12 weeks
- Production Ready: 16 weeks

**Realistic (Part-Time):**
- MVP: 3 months
- Feature Complete: 8 months
- Production Ready: 12 months

**Note:** This is a MAJOR undertaking. Consider if benefits justify the effort.

## Future Enhancements

**Once IL Compiler Stable:**
- Custom optimizations (tail calls, inlining)
- IL-level pattern matching optimizations
- Zero-overhead async (better state machines)
- Custom calling conventions for performance
- Cross-compilation (target different frameworks)
- AOT compilation integration

## Recommendation

**Short Term:** Keep transpiler, it works great
**Medium Term:** Build IL compiler as experiment/learning
**Long Term:** If IL compiler proves valuable, gradually migrate

**Decision Points:**
1. After MVP: Does it compile basic programs correctly?
2. After Phase 3: Is it significantly faster?
3. After Phase 7: Does it have feature parity?
4. After Production Use: Is maintenance worth it?

At each decision point, we can choose to continue or stick with transpiler.

## Deliverables

1. **ILCompiler project** - Complete implementation
2. **500+ unit tests** - Comprehensive test suite
3. **Benchmark suite** - Performance comparisons
4. **Documentation** - User guide + developer guide
5. **Examples** - All examples working with `--emit-il`
6. **Migration guide** - How to switch from transpiler
7. **IL debugging guide** - How to debug IL output

This is an exciting but massive project!
