namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.Reflection


// READING `TupleElementNamesAttribute` BACK OFF AN EXTERNAL MEMBER.
//
// The attribute is the other half of the emitter's contract: a C# method declared
// `(int Min, int Max) MinMaxInt32(...)` is `ValueTuple<int, int>` in its signature and carries the
// names in an attribute on the return position. Without reading it, `csharpMethod().Min` is
// `NL303 'ValueTuple<int, int>' does not have a member named 'Min'` and the only spellings that work
// are `Item1`/`Item2` and deconstruction -- which is what N# did before this owner existed.
//
// THE NAMES GO ON THE TYPE THE POSITION ANSWERS, NOT ON THE MEMBER. `TupleTypeInfo` already carries
// element names, `AnalyzerDeclarationContext.TryResolveTupleMember` already answers both `Item1` and
// the declared name, and `TypeInfoIdentityFacts.AreEqual` already compares tuples by their ELEMENT
// TYPES and ignores the names. So the whole of consumption is: convert the reflected
// `ValueTuple<...>` into a `TupleTypeInfo` whose elements carry the attribute's names. Assignment
// compatibility is unchanged by construction -- names are not part of tuple identity in N#, exactly
// as they are not in C#, where a name mismatch is a warning and never an error. N# has no lint that
// mirrors that warning and this stream did not add one.
//
// A POSITION WITHOUT THE ATTRIBUTE IS LEFT EXACTLY AS IT WAS. An unnamed external tuple keeps the
// reflected `GenericTypeInfo` it has always had, so nothing that resolves `Item1` today changes
// shape; only a position that actually declares names becomes a `TupleTypeInfo`.
//
// THE WALK MIRRORS THE EMITTER'S FLATTENING EXACTLY. The attribute's array is a pre-order walk of
// the written type with each tuple's own names first (see `ColumnarTupleElementNames`), so the
// consumer has to spend the array in the same order or a nested tuple silently takes its parent's
// names. That includes the `ValueTuple` REST nesting: a tuple of more than seven elements is
// `ValueTuple<T1..T7, ValueTuple<...>>` in metadata, its elements are read back FLAT, and the rest
// tuple's own (nameless) slots are consumed before the walk continues inside it.
class AnalyzerTupleElementNames {

    // The flattened names an external position declares, or null when it declares none. Null is the
    // "leave the converted type alone" answer.
    static func Read(attributes: IList<CustomAttributeData>): string?[]? {
        count := NullabilityMetadataReflection.SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            attributeType := attribute.get_AttributeType()
            if attributeType.FullName == "System.Runtime.CompilerServices.TupleElementNamesAttribute" {
                constructorArguments := attribute.get_ConstructorArguments()
                if NullabilityMetadataReflection.SequenceCount(constructorArguments) == 1 {
                    return ReadStringArrayArgument(constructorArguments.get_Item(0))
                }

                return null
            }

            index = index + 1
        }

        return null
    }

    // The attribute's single `string[]` fixed argument. Each element is a `CustomAttributeTypedArgument`
    // whose `Value` is the name, or null for an element the declaring language left unnamed.
    //
    // BOTH HOPS GO THROUGH `object` ON PURPOSE, AND BOTH ARE COMPILER LIMITATIONS RATHER THAN TASTE.
    // `Value` answers the element list as `object`, and the columnar backend emits neither
    // `value as IList<CustomAttributeTypedArgument>` nor the equivalent cast: an `as`/`is` target must
    // be a bare identifier, so every CONSTRUCTED GENERIC target declines
    // (`value as List<int>` declines the same way). The non-generic `IList` reaches the same instance
    // and the same count -- the trick `SequenceCount` already plays for `Count` -- and each element's
    // `Value` is read through the property itself because a boxed struct cannot be unboxed here
    // either. Nothing about the metadata is guessed: this is the same
    // `CustomAttributeTypedArgument.Value` a strongly-typed reader would call.
    static func ReadStringArrayArgument(argument: CustomAttributeTypedArgument): string?[]? {
        value := argument.get_Value()
        if value == null {
            return null
        }

        elements := value as IList
        if elements == null {
            return null
        }

        valueProperty := typeof(CustomAttributeTypedArgument).GetProperty("Value")
        if valueProperty == null {
            return null
        }

        count := elements.Count
        names := new string?[](count)
        index := 0
        while index < count {
            element := elements.get_Item(index)
            if element != null {
                names[index] = valueProperty.GetValue(element) as string
            }

            index = index + 1
        }

        return names
    }

    // The converted type with the declared element names attached. Called with the names a position
    // actually declares; a position that declares none never reaches here.
    static func Apply(typeInfo: TypeInfo, names: string?[]): TypeInfo {
        cursor := new int[](1)
        cursor[0] = 0
        return Rewrite(typeInfo, names, cursor)
    }

    // The convenience the four member-facing conversions use: read and apply in one step, answering
    // the original type when there is nothing to say.
    static func ApplyDeclared(typeInfo: TypeInfo, attributes: IList<CustomAttributeData>): TypeInfo {
        names := Read(attributes)
        if names == null {
            return typeInfo
        }

        return Apply(typeInfo, names)
    }

    // NAMES TRAVEL WITH THE POSITION A VALUE WAS READ OUT OF, AND A MEMBER RESOLVED THROUGH REFLECTION
    // LOSES THEM.
    //
    // `Dictionary<string, (Item: string, Ranges: List<int>)>.Values` answers
    // `Dictionary<K, V>.ValueCollection` with `K` and `V` substituted, and the substitution runs over
    // the CLOSED CLR type -- which has no element names in it at all, because a named tuple has no CLR
    // identity. So `groups.Values` typed as `ValueCollection<string, (string, List<int>)>` and every
    // read off it reported NL303 "Member 'Ranges' not found", even though the dictionary's own
    // declaration is the position that named those elements.
    //
    // THE RULE IS THE ONE C# APPLIES, STATED AS A TYPE OPERATION: a value taken out of a receiver
    // keeps the annotation the receiver's WRITTEN type gave that position. So an UNNAMED tuple in the
    // member's type takes the names of the receiver's own tuple when the receiver's written type
    // mentions exactly ONE tuple of that shape. Names are the only thing that changes -- the type is
    // identical either way, because `TypeInfoIdentityFacts.AreEqual` ignores element names.
    //
    // THE MATCH MUST BE UNIQUE. A receiver that mentions the same tuple shape twice with different
    // names (`Dictionary<(A: int, B: int), (C: int, D: int)>`) cannot say which position a value came
    // from, so it says nothing and the member's type stays unnamed -- the answer it had before.
    static func GraftFromReceiver(memberType: TypeInfo, receiverType: TypeInfo): TypeInfo {
        if memberType == null || receiverType == null {
            return memberType
        }

        named := new List<TupleTypeInfo>()
        CollectNamedTuples(receiverType, named)
        if named.Count == 0 {
            return memberType
        }

        return GraftInto(memberType, named)
    }

    static func CollectNamedTuples(typeInfo: TypeInfo, collected: List<TupleTypeInfo>) {
        if typeInfo == null {
            return
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            CollectNamedTuples(oblivious.InnerType, collected)
            return
        }

        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            CollectNamedTuples(nullable.InnerType, collected)
            return
        }

        array := typeInfo as ArrayTypeInfo
        if array != null {
            CollectNamedTuples(array.ElementType, collected)
            return
        }

        tuple := typeInfo as TupleTypeInfo
        if tuple != null {
            if HasDeclaredName(tuple) {
                collected.Add(tuple)
            }

            elementIndex := 0
            while elementIndex < tuple.Elements.Count {
                CollectNamedTuples(tuple.Elements[elementIndex].Type, collected)
                elementIndex = elementIndex + 1
            }

            return
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            argumentIndex := 0
            while argumentIndex < generic.TypeArguments.Count {
                CollectNamedTuples(generic.TypeArguments[argumentIndex], collected)
                argumentIndex = argumentIndex + 1
            }
        }
    }

    static func HasDeclaredName(tuple: TupleTypeInfo): bool {
        index := 0
        while index < tuple.Elements.Count {
            elementName := tuple.Elements[index].Name
            if elementName != null && elementName.Length > 0 {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func GraftInto(typeInfo: TypeInfo, named: List<TupleTypeInfo>): TypeInfo {
        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            graftedOblivious: TypeInfo = new ObliviousTypeInfo(GraftInto(oblivious.InnerType, named))
            return graftedOblivious
        }

        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            grafted: TypeInfo = new NullableTypeInfo(GraftInto(nullable.InnerType, named))
            return grafted
        }

        array := typeInfo as ArrayTypeInfo
        if array != null {
            graftedArray: TypeInfo = new ArrayTypeInfo(GraftInto(array.ElementType, named))
            return graftedArray
        }

        tuple := typeInfo as TupleTypeInfo
        if tuple != null {
            if !HasDeclaredName(tuple) {
                matched: TupleTypeInfo = null
                if TryUniqueNamedMatch(tuple, named, out matched) {
                    replacement: TypeInfo = matched
                    return replacement
                }
            }

            elements := new List<TupleTypeElementInfo>()
            elementIndex := 0
            while elementIndex < tuple.Elements.Count {
                element := tuple.Elements[elementIndex]
                elements.Add(new TupleTypeElementInfo(element.Name, GraftInto(element.Type, named)))
                elementIndex = elementIndex + 1
            }

            graftedTuple: TypeInfo = new TupleTypeInfo(elements)
            return graftedTuple
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            arguments := new List<TypeInfo>()
            argumentIndex := 0
            while argumentIndex < generic.TypeArguments.Count {
                arguments.Add(GraftInto(generic.TypeArguments[argumentIndex], named))
                argumentIndex = argumentIndex + 1
            }

            graftedGeneric: TypeInfo = new GenericTypeInfo(generic.Name, arguments, generic.GenericDefinition)
            return graftedGeneric
        }

        // A METHOD GROUP read off the receiver is a member too, and what a caller reads back is its
        // RETURN type, so the graft has to reach through the signature as well as into it.
        functionType := typeInfo as FunctionTypeInfo
        if functionType != null && functionType.ReturnType != null {
            graftedReturn := GraftInto(functionType.ReturnType, named)
            functionType.ReturnType = graftedReturn
            return functionType
        }

        return typeInfo
    }

    static func TryUniqueNamedMatch(tuple: TupleTypeInfo, named: List<TupleTypeInfo>, out matched: TupleTypeInfo): bool {
        matched = null
        found := 0
        index := 0
        while index < named.Count {
            candidate := named[index]
            if TypeInfoIdentityFacts.AreEqual(candidate, tuple) {
                found = found + 1
                matched = candidate
            }

            index = index + 1
        }

        if found != 1 {
            matched = null
            return false
        }

        return true
    }

    static func Rewrite(typeInfo: TypeInfo, names: string?[], cursor: int[]): TypeInfo {
        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            rewrittenInner: TypeInfo = new NullableTypeInfo(Rewrite(nullable.InnerType, names, cursor))
            return rewrittenInner
        }

        array := typeInfo as ArrayTypeInfo
        if array != null {
            rewrittenArray: TypeInfo = new ArrayTypeInfo(Rewrite(array.ElementType, names, cursor))
            return rewrittenArray
        }

        tuple := typeInfo as TupleTypeInfo
        if tuple != null {
            elements := new List<TypeInfo>()
            elementIndex := 0
            while elementIndex < tuple.Elements.Count {
                elements.Add(tuple.Elements[elementIndex].Type)
                elementIndex = elementIndex + 1
            }

            return RewriteTuple(elements, names, cursor)
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            if IsValueTupleInstantiation(generic) {
                return RewriteTuple(FlattenValueTupleArguments(generic), names, cursor)
            }

            arguments := new List<TypeInfo>()
            argumentIndex := 0
            while argumentIndex < generic.TypeArguments.Count {
                arguments.Add(Rewrite(generic.TypeArguments[argumentIndex], names, cursor))
                argumentIndex = argumentIndex + 1
            }

            rewrittenGeneric: TypeInfo = new GenericTypeInfo(generic.Name, arguments, generic.GenericDefinition)
            return rewrittenGeneric
        }

        return typeInfo
    }

    // A `ValueTuple` instantiation, identified by its generic DEFINITION's CLR name rather than by the
    // written name, so a user type that happens to be called `ValueTuple` is not mistaken for one.
    static func IsValueTupleInstantiation(generic: GenericTypeInfo): bool {
        definition := generic.GenericDefinition as ReflectionTypeInfo
        if definition == null {
            return false
        }

        fullName := definition.Type.FullName
        if fullName == null {
            return false
        }

        return fullName.StartsWith("System.ValueTuple`", StringComparison.Ordinal)
    }

    // The tuple's elements, read FLAT out of the `ValueTuple` nesting metadata uses: seven arguments
    // and, when there is an eighth, the rest tuple's own elements appended in order.
    static func FlattenValueTupleArguments(generic: GenericTypeInfo): List<TypeInfo> {
        elements := new List<TypeInfo>()
        index := 0
        while index < generic.TypeArguments.Count {
            argument := generic.TypeArguments[index]
            isRest := index == 7 && generic.TypeArguments.Count == 8
            restGeneric := argument as GenericTypeInfo
            if isRest && restGeneric != null && IsValueTupleInstantiation(restGeneric) {
                rest := FlattenValueTupleArguments(restGeneric)
                restIndex := 0
                while restIndex < rest.Count {
                    elements.Add(rest[restIndex])
                    restIndex = restIndex + 1
                }
            } else {
                elements.Add(argument)
            }

            index = index + 1
        }

        return elements
    }

    static func RewriteTuple(elements: List<TypeInfo>, names: string?[], cursor: int[]): TypeInfo {
        elementNames := new string?[](elements.Count)
        nameIndex := 0
        while nameIndex < elements.Count {
            elementNames[nameIndex] = NameAt(names, cursor[0])
            cursor[0] = cursor[0] + 1
            nameIndex = nameIndex + 1
        }

        rewritten := new TypeInfo[](elements.Count)
        RewriteUnderlyingArguments(elements, 0, names, cursor, rewritten)

        rebuilt := new List<TupleTypeElementInfo>()
        buildIndex := 0
        while buildIndex < elements.Count {
            rebuilt.Add(new TupleTypeElementInfo(elementNames[buildIndex], rewritten[buildIndex]))
            buildIndex = buildIndex + 1
        }

        result: TypeInfo = new TupleTypeInfo(rebuilt)
        return result
    }

    // The mirror of `ColumnarTupleElementNames.AppendUnderlyingArguments`: seven or fewer elements are
    // the `ValueTuple`'s own arguments, and beyond that the eighth argument is a REST tuple whose own
    // nameless slots are spent before the walk continues inside it.
    static func RewriteUnderlyingArguments(elements: List<TypeInfo>, start: int, names: string?[], cursor: int[], rewritten: TypeInfo[]) {
        remaining := elements.Count - start
        if remaining <= 7 {
            index := start
            while index < elements.Count {
                rewritten[index] = Rewrite(elements[index], names, cursor)
                index = index + 1
            }

            return
        }

        index := start
        while index < start + 7 {
            rewritten[index] = Rewrite(elements[index], names, cursor)
            index = index + 1
        }

        restStart := start + 7
        cursor[0] = cursor[0] + (elements.Count - restStart)
        RewriteUnderlyingArguments(elements, restStart, names, cursor, rewritten)
    }

    // The attribute's array can be shorter than the type's slots when a producer wrote a truncated
    // one; a missing slot reads as unnamed rather than throwing.
    static func NameAt(names: string?[], index: int): string? {
        if index < 0 || index >= names.Length {
            return null
        }

        return names[index]
    }
}
