# S2.2(j1): generic parameter declaration binding

The seeded iterator declaration probe directly creates a type through `ModuleBuilder.DefineType`,
then reaches `TypeBuilder.DefineGenericParameters(string[])` and declines before any test executes.
Its nongeneric twin bakes the directly declared type and passes 1/1. This isolates the remaining
declaration boundary after the accepted `Ldftn` prerequisite.

This cut adds one exact virtual-call plan for that BCL method. The plan retains the genuine
`GenericTypeParameterBuilder[]` return, and the type-admission surface accepts that concrete element
so the returned array can be stored and indexed. It does not add a source alias, a `Type[]` return,
or a broader Reflection.Emit call family. Canonical contracts compare the plan with the actual BCL
receiver, name, staticness, parameter and return identities; other receivers, arities, and argument
types remain unsupported.

The connected iterator realization driver remains unchanged in this prerequisite. Its eventual
generic declaration path will copy each returned builder into a fresh `Type[]` base view and will
retain the original builder array as the method's actual result. A separately owned native control
executes the direct call, verifies the returned element owner and ordinal, and consumes that handle in
a baked closed field before this capability is admitted to dogfood source by a freshly gated SDK.
