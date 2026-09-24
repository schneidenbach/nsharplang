namespace NSharpLang.Compiler.Columnar

// THE BINDING CONTEXT A BODY'S NODE TABLE CARRIES, AS THE SYNTAX SLICE SEES IT.
//
// Every body's node table is stamped with the program's binding facts
// (`ColumnarProgramInput.StampBindingContexts`), so a planner reading that body resolves a name
// against the right file, namespace and imports without being handed the program. The node table
// only CARRIES that context: it stores it, returns it and copies it onto a fragment reparsed out of
// the body (`ColumnarNodeTable.InheritBindingContext`), and it never asks it anything.
//
// The facts themselves, `ColumnarBindingScopeFacts`, are a planner model built from the whole
// program, a slice above the parser. So the table names them through this base, which declares
// nothing because the table asks nothing, and the planners read them back through
// `ColumnarBindingScopeFacts.Of` - the one place the context is narrowed to what it is. It is the
// shape `TypeInfo` already has for the analyzer's type model.
//
// A BASE CLASS, NOT AN INTERFACE. The columnar emitter registers every source interface
// structurally, `duck` or not, and an interface that declares nothing is satisfied by every type -
// so a marker interface here would be written onto every class in the assembly.
// SEED: duckfix ae7daa9a4 - the tip emitter registers only `duck interface`s structurally, so a
// plain marker interface is nominal. Core is compiled by the committed seed, which predates that
// fix; after the next reseed this base may collapse to `interface IColumnarBindingScope {}`.
class ColumnarBindingScope {
}
