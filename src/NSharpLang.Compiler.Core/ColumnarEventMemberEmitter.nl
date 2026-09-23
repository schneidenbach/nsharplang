namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Threading
import NSharpLang.Compiler


// A SOURCE-DECLARED EVENT IS THREE THINGS, AND THE CLR NEEDS ALL THREE.
//
// `event Changed: EventHandler` is C#'s FIELD-LIKE event, spelled without the field. What it emits is
// exactly what C# emits for `public event EventHandler Changed;`:
//
//   1. a PRIVATE backing field carrying the event's own name, marked `[CompilerGenerated]`. The name
//      is deliberately the same: a field and an event live in different metadata tables, so the two
//      rows never collide, and the shared name is what makes `Changed?.Invoke(...)` inside the
//      declaring type an ordinary field read while `Changed` from outside is only ever the event.
//   2. `add_Changed` / `remove_Changed`, each a one-parameter void accessor that COMBINES or REMOVES
//      the handler with `Interlocked.CompareExchange` in a retry loop. That loop is not decoration:
//      two threads subscribing at once would otherwise lose one of the two handlers.
//   3. an `EventInfo` row wiring the two accessors to the name, so `GetEvent("Changed")` answers and
//      C# can write `widget.Changed += handler` against the assembly N# produced.
//
// THE ACCESSORS TAKE THE EVENT'S OWN VISIBILITY and the backing field is private whatever the event
// says — the same asymmetry C# has, and the reason a reader outside the declaring type reaches the
// event rather than the delegate.
class ColumnarEventMemberEmitter {

    // THE THREE INHERITANCE SHAPES AN EVENT CAN HAVE, as the one number every door below reads.
    // 0 is a plain event, 1 `virtual`, 2 `abstract`, 3 `override`.
    static func PlainEvent(): int {
        return 0
    }

    static func VirtualEvent(): int {
        return 1
    }

    static func AbstractEvent(): int {
        return 2
    }

    static func OverrideEvent(): int {
        return 3
    }

    // THE WORD THE DECLARATION WROTE, as the one number. `abstract` is asked first and `override`
    // last, the same order the analyzer reports them in, so a declaration that somehow carries two is
    // read the same way by both halves.
    static func InheritanceKindOf(isVirtual: bool, isAbstract: bool, isOverride: bool): int {
        if isAbstract {
            return AbstractEvent()
        }

        if isOverride {
            return OverrideEvent()
        }

        if isVirtual {
            return VirtualEvent()
        }

        return PlainEvent()
    }

    // ECMA-335 MethodAttributes: HideBySig 0x0080, SpecialName 0x0800, Static 0x0010, Virtual 0x0040,
    // NewSlot 0x0100, Abstract 0x0400, Final 0x0020. An accessor is a special-named method in every
    // language that emits one; `SpecialName` is what stops a C# caller from writing
    // `widget.add_Changed(h)` directly.
    //
    // AN EVENT'S ACCESSORS ARE METHODS, SO THEY TAKE THE SAME SLOTS METHODS DO, and the words mean
    // exactly what they mean on a `func`: `virtual` and `abstract` each OPEN a slot (Virtual|NewSlot)
    // and `abstract` supplies no IL; `override` REUSES the base's slot, which is NewSlot cleared.
    // `implementsInterfaceSlot` is the fourth shape and is not a word anyone writes: a class member
    // that fills an interface's slot is Virtual|Final|NewSlot — virtual so the interface dispatch
    // finds it, final so nothing else may override it, exactly what C# emits for an implicit
    // implementation.
    static func AccessorAttributeWord(visibilityWord: int, isStatic: bool, inheritanceKind: int, implementsInterfaceSlot: bool): int {
        word := visibilityWord | 0x0080 | 0x0800
        if isStatic {
            return word | 0x0010
        }

        if inheritanceKind == AbstractEvent() {
            return word | 0x0040 | 0x0100 | 0x0400
        }

        if inheritanceKind == VirtualEvent() {
            return word | 0x0040 | 0x0100
        }

        if inheritanceKind == OverrideEvent() {
            return word | 0x0040
        }

        if implementsInterfaceSlot {
            return word | 0x0040 | 0x0100 | 0x0020
        }

        return word
    }

    static func AddAccessorName(eventName: string): string {
        return "add_" + eventName
    }

    static func RemoveAccessorName(eventName: string): string {
        return "remove_" + eventName
    }

    // The delegate a handler must be. An event over a non-delegate type has no accessors to write and
    // no `EventInfo` the CLR would accept, so the caller reports rather than emitting something the
    // runtime would refuse to load.
    static func IsDelegateHandlerType(handlerType: Type?): bool {
        if handlerType == null || handlerType.get_IsValueType() || handlerType.get_IsInterface() {
            return false
        }

        walk: Type? = handlerType
        while walk != null {
            fullName := walk.FullName
            if fullName == "System.MulticastDelegate" || fullName == "System.Delegate" {
                return true
            }

            walk = walk.get_BaseType()
        }

        return false
    }

    // DEFINE THE WHOLE MEMBER — field, both accessors, both bodies, and the `EventInfo` — as one
    // operation, so no caller can register half an event.
    static func Define(owner: ColumnarStructDef, eventName: string, handlerType: Type, isStatic: bool, visibilityWord: int): ColumnarEventDef {
        return Define(owner, eventName, handlerType, isStatic, visibilityWord, PlainEvent(), false)
    }

    static func Define(owner: ColumnarStructDef, eventName: string, handlerType: Type, isStatic: bool, visibilityWord: int, inheritanceKind: int, implementsInterfaceSlot: bool): ColumnarEventDef {
        if owner == null || eventName == null || handlerType == null {
            throw new InvalidOperationException("Source event definition inputs cannot be null.")
        }

        builder := owner.Builder
        isAbstract := inheritanceKind == AbstractEvent()

        // AN ABSTRACT EVENT HAS NO STORAGE. Its accessors are slots, and a field behind a slot nobody
        // can reach would be storage the declaring type cannot raise and a derived type cannot see —
        // C# emits none either. Every other shape, `override` included, owns its own private field:
        // an overriding field-like event keeps its own handler list, which is why a subscriber through
        // the base reference reaches the OVERRIDE's storage through the override's own accessors.
        let backingField: System.Reflection.Emit.FieldBuilder? = null
        if !isAbstract {
            backingFieldAttributes := 1
            // FieldAttributes.Private
            if isStatic {
                backingFieldAttributes = backingFieldAttributes | 16
            }
            // FieldAttributes.Static
            backingField = ColumnarFieldMetadataEmitter.Define(builder, eventName, handlerType, backingFieldAttributes, false, false, 0)
            ApplyCompilerGenerated(backingField)
        }

        accessorWord := AccessorAttributeWord(visibilityWord, isStatic, inheritanceKind, implementsInterfaceSlot)
        accessorParameters := new Type[](1)
        accessorParameters[0] = handlerType
        voidType := ColumnarTypeOfPlanner.RequiredVoidType()
        adder := builder.DefineMethod(AddAccessorName(eventName), (MethodAttributes)accessorWord, voidType, accessorParameters)
        remover := builder.DefineMethod(RemoveAccessorName(eventName), (MethodAttributes)accessorWord, voidType, accessorParameters)
        // The accessor's one parameter is named `value` in every language that emits an event, and a
        // C# caller writing `widget.Changed += h` reads that name in its own tooling.
        adder.DefineParameter(1, ParameterAttributes.None, "value")
        remover.DefineParameter(1, ParameterAttributes.None, "value")

        if backingField != null {
            EmitAccessorBody(adder.GetILGenerator(), backingField, handlerType, isStatic, CombineMethod())
            EmitAccessorBody(remover.GetILGenerator(), backingField, handlerType, isStatic, RemoveMethod())
        }

        eventBuilder := builder.DefineEvent(eventName, EventAttributes.None, handlerType)
        eventBuilder.SetAddOnMethod(adder)
        eventBuilder.SetRemoveOnMethod(remover)

        definition := new ColumnarEventDef(eventName, backingField, adder, remover, handlerType, isStatic, isAbstract, inheritanceKind)
        owner.Events[eventName] = definition
        if backingField != null {
            if isStatic {
                owner.StaticFields[eventName] = backingField
            } else {
                owner.Fields[eventName] = backingField
            }
        }

        return definition
    }

    // `[CompilerGenerated]` ON THE BACKING FIELD. It is what tells every other tool — a decompiler, a
    // serializer, an analyzer — that the field is the event's storage and not a member the author
    // wrote, and C# stamps it for exactly that reason.
    static func ApplyCompilerGenerated(field: FieldBuilder) {
        attributeType := typeof(object).get_Assembly().GetType("System.Runtime.CompilerServices.CompilerGeneratedAttribute")
        if attributeType == null {
            throw new InvalidOperationException("The CompilerGeneratedAttribute runtime type was not found.")
        }

        constructor := attributeType.GetConstructor(new Type[](0))
        if constructor == null {
            throw new InvalidOperationException("The no-argument CompilerGeneratedAttribute constructor was not found.")
        }

        field.SetCustomAttribute(constructor, ColumnarAttributeBlobs.NoArgument())
    }

    static func CombineMethod(): MethodInfo {
        parameters := new Type[](2)
        parameters[0] = typeof(Delegate)
        parameters[1] = typeof(Delegate)
        combine := typeof(Delegate).GetMethod("Combine", parameters)
        if combine == null {
            throw new InvalidOperationException("Delegate.Combine(Delegate, Delegate) was not found.")
        }

        return combine
    }

    static func RemoveMethod(): MethodInfo {
        parameters := new Type[](2)
        parameters[0] = typeof(Delegate)
        parameters[1] = typeof(Delegate)
        remove := typeof(Delegate).GetMethod("Remove", parameters)
        if remove == null {
            throw new InvalidOperationException("Delegate.Remove(Delegate, Delegate) was not found.")
        }

        return remove
    }

    // `Interlocked.CompareExchange<T>(ref T, T, T)` CLOSED OVER THE HANDLER TYPE. The generic overload
    // is the one C# uses, and it is the one that keeps the field's declared type: the non-generic
    // `object` overload would need the backing field to be an `object`, which no C# caller could then
    // subscribe to.
    static func CompareExchangeMethod(handlerType: Type): MethodInfo {
        candidates := typeof(Interlocked).GetMethods()
        for candidate in candidates {
            if candidate.get_Name() == "CompareExchange" && candidate.get_IsGenericMethodDefinition() {
                parameters := candidate.GetParameters()
                if parameters.Length == 3 && parameters[0].get_ParameterType().get_IsByRef() {
                    arguments := new Type[](1)
                    arguments[0] = handlerType
                    return candidate.MakeGenericMethod(arguments)
                }
            }
        }

        throw new InvalidOperationException("Interlocked.CompareExchange<T>(ref T, T, T) was not found.")
    }

    // THE ACCESSOR BODY, BYTE FOR BYTE WHAT C# WRITES. Read the field once, then loop: build the new
    // delegate from the value read, publish it with a compare-and-swap, and start over if somebody
    // else won the race. `combineOrRemove` is the only difference between `add_` and `remove_`.
    static func EmitAccessorBody(il: ILGenerator, backingField: FieldBuilder, handlerType: Type, isStatic: bool, combineOrRemove: MethodInfo) {
        compareExchange := CompareExchangeMethod(handlerType)
        current := il.DeclareLocal(handlerType)
        comparand := il.DeclareLocal(handlerType)
        updated := il.DeclareLocal(handlerType)
        retry := il.DefineLabel()

        EmitLoadBackingField(il, backingField, isStatic)
        il.Emit(OpCodes.Stloc, current)
        il.MarkLabel(retry)
        il.Emit(OpCodes.Ldloc, current)
        il.Emit(OpCodes.Stloc, comparand)
        il.Emit(OpCodes.Ldloc, comparand)
        EmitLoadAccessorValue(il, isStatic)
        il.Emit(OpCodes.Call, combineOrRemove)
        il.Emit(OpCodes.Castclass, handlerType)
        il.Emit(OpCodes.Stloc, updated)
        EmitLoadBackingFieldAddress(il, backingField, isStatic)
        il.Emit(OpCodes.Ldloc, updated)
        il.Emit(OpCodes.Ldloc, comparand)
        il.Emit(OpCodes.Call, compareExchange)
        il.Emit(OpCodes.Stloc, current)
        il.Emit(OpCodes.Ldloc, current)
        il.Emit(OpCodes.Ldloc, comparand)
        il.Emit(OpCodes.Bne_Un, retry)
        il.Emit(OpCodes.Ret)
    }

    static func EmitLoadBackingField(il: ILGenerator, backingField: FieldBuilder, isStatic: bool) {
        if isStatic {
            il.Emit(OpCodes.Ldsfld, backingField)
            return
        }

        il.Emit(OpCodes.Ldarg_0)
        il.Emit(OpCodes.Ldfld, backingField)
    }

    static func EmitLoadBackingFieldAddress(il: ILGenerator, backingField: FieldBuilder, isStatic: bool) {
        if isStatic {
            il.Emit(OpCodes.Ldsflda, backingField)
            return
        }

        il.Emit(OpCodes.Ldarg_0)
        il.Emit(OpCodes.Ldflda, backingField)
    }

    // The accessor's `value` parameter: argument one on an instance accessor, argument zero on a
    // static one, because a static method has no implicit receiver.
    static func EmitLoadAccessorValue(il: ILGenerator, isStatic: bool) {
        if isStatic {
            il.Emit(OpCodes.Ldarg_0)
            return
        }

        il.Emit(OpCodes.Ldarg_1)
    }
}
