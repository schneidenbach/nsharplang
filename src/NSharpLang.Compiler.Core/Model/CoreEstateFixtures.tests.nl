namespace NSharpLang.Compiler

import System
import System.Reflection
import System.Reflection.Emit


// THE CORE ESTATE'S OWN FIXTURES.
//
// Core's rows (its `Semantics/` and `Model/` directories) build in Compiler.Core's own assembly, which
// Compiler.Plan sits ABOVE, so they cannot call a helper Plan's rows declare. These are the
// Reflection.Emit builders Core's rows share. Each one spells the API it stands for directly; the
// planner rows' helpers of the same shape (`TypeOfCreateBuilder`, `PlanFixtureBake` ...) stay with
// the planner rows.

// A public type in its own run-only dynamic assembly, with `T0..Tn` when it is generic. Two calls
// with the same name build two distinct declarations in two distinct modules.
func CoreFixtureTypeBuilder(name: string, assemblyIdentity: string, genericParameterCount: int): TypeBuilder {
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(assemblyIdentity), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule(name)
    builder := module.DefineType(name, TypeAttributes.Public)
    if genericParameterCount > 0 {
        names := new string[](genericParameterCount)
        index := 0
        while index < names.Length {
            names[index] = "T" + index.ToString()
            index = index + 1
        }
        builder.DefineGenericParameters(names)
    }
    return builder
}

func CoreFixtureBake(builder: TypeBuilder): Type {
    baked := builder.CreateType()
    if baked == null {
        throw new InvalidOperationException("The Core fixture did not produce a runtime type.")
    }
    return baked
}
