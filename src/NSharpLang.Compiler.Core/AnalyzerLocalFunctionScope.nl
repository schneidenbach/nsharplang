namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHERE A LOCAL FUNCTION'S NAME IS VISIBLE — the whole block that declares it, from its first
// statement to its last, and not one statement further.
//
// A local function is not a local VARIABLE. A variable's name starts existing where the declaration
// runs, because reading it earlier would read a value that does not exist yet; a function's name
// names CODE, and the code exists as soon as the block is parsed. C# says so explicitly
// (`LocalScopeBinder`: every local function of a block is in the block's scope before any of its
// statements are bound), and the shape that needs it is the ordinary one — two local functions that
// call each other. Declaring the name where the statement is walked makes `visitStatement` calling
// `visitBlock` an error about correct code whenever `visitBlock` is written second, and leaves
// MUTUAL recursion unspellable: whichever is written first cannot see the other.
//
// So a block binds ALL of its local functions before it walks ANY of its statements, and this owner
// is the list of names that binding declares. It reads statements and builds function types; it
// reports nothing and it opens no scope, because the driver owns both.
//
// WHAT IT DELIBERATELY DOES NOT DO is descend. Only the local functions written DIRECTLY in the
// list are hoisted: one declared inside a nested block belongs to that block and stays invisible
// outside it, which is the same rule C# has and the reason a block's set dies with its scope.
//
// THE POSITION IS THE STATEMENT'S, not the inner `FunctionDeclaration`'s — the same choice
// `AnalyzerFunctionBodies.BeginLocalFunction` makes, so the name is declared at exactly the
// position the statement walk would have declared it at and go-to-definition does not move.
class AnalyzerHoistedLocalFunction {
    nameValue: string
    signatureValue: TypeInfo
    lineValue: int
    columnValue: int

    Name: string => nameValue
    Signature: TypeInfo => signatureValue
    Line: int => lineValue
    Column: int => columnValue

    constructor(name: string, signature: TypeInfo, line: int, column: int) {
        nameValue = name
        signatureValue = signature
        lineValue = line
        columnValue = column
    }
}

class AnalyzerLocalFunctionScope {

    // EVERY LOCAL FUNCTION WRITTEN DIRECTLY IN THIS STATEMENT LIST, IN DECLARATION ORDER. The order
    // is behaviour: two local functions that collide on a name must report the SECOND one as the
    // duplicate, exactly as two written declarations do.
    static func Hoist(statements: List<Statement>?, containingType: string?, functionTypeFactory: AnalyzerFunctionTypeFactory): List<AnalyzerHoistedLocalFunction> {
        hoisted := new List<AnalyzerHoistedLocalFunction>()
        if statements == null {
            return hoisted
        }

        for statement in statements {
            localFunction := statement as LocalFunctionStatement
            if localFunction != null {
                declaration := localFunction.Function
                signature: TypeInfo = functionTypeFactory.CreateFromDeclaration(declaration, containingType)
                hoisted.Add(new AnalyzerHoistedLocalFunction(declaration.Name, signature, localFunction.Line, localFunction.Column))
            }
        }

        return hoisted
    }
}
