# S2.2(j0): iterator continuation function-pointer binding

The async iterator constructor needs one raw IL instruction that the accepted N# binding surface did
not expose: `ILGenerator.Emit(OpCodes.Ldftn, MethodInfo)`. An initial consumed probe used inferred
`MethodBuilder` and `FieldBuilder` operands; compilation reached the outer `Emit` expression containing
`OpCodes.Ldftn` and then declined, with zero tests executed. A corrected probe explicitly viewed the
core as `MethodInfo` and the fields as `FieldInfo` and stopped at the same expression under the accepted
SDK. This isolates the missing `Ldftn` binding for the intended, already modeled `Emit` overload without
claiming that the preceding emitted instructions ran. This cut adds that one opcode name to the existing
call-and-compute opcode family.

The canonical contracts pin both short and fully qualified `OpCodes` selection, the exact field and
value identities, and the existing `Emit(OpCode, MethodInfo)` call plan. The four byte-operand argument
forms remain unsupported, as does adjacent `Ldvirtftn`; `System.Byte` is still outside the emit-operand
surface. A separately owned native constructor control provides the post-seed executable instruction
proof. The synchronous and asynchronous iterator realization drivers remain unchanged in this
prerequisite cut.
