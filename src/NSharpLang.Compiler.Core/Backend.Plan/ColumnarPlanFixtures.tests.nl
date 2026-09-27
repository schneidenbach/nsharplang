namespace NSharpLang.Compiler

import System
import System.Collections
import System.Reflection.Emit


// THE PLAN ESTATE'S OWN FIXTURES.
//
// Backend.Plan's rows build in Compiler.Plan's own assembly, which references Compiler.Core -- and
// every slice below it -- PRODUCT-ONLY, so they cannot call a helper Core's rows declare. These are
// the helpers the planner rows share that used to be borrowed from Core's rows, each spelling the API
// it stands for directly.

// Bakes a Reflection.Emit type; a builder that produces no runtime type is a fixture failure.
func PlanFixtureBake(builder: TypeBuilder): Type {
    baked := builder.CreateType()
    if baked == null {
        throw new InvalidOperationException("The plan fixture did not produce a runtime type.")
    }
    return baked
}

// The element count of a reflection answer typed as an `IList<T>` of a metadata row type
// (`CustomAttributeData`, `CustomAttributeTypedArgument` ...), read through the non-generic list.
func PlanFixtureSequenceCount(sequence: object): int {
    list := (IList)sequence
    return list.Count
}
