# Phase-B contracts — the member-resolution and extension-scan surface

Task 017 slice 22 **phase A** landed the capability that `ResolveMember` and the extension carrier
need: catalog rows in `src/NSharpLang.Compiler.BootstrapServices/ColumnarExternalBindingPlans.nl`.
This file holds the contracts that EXERCISE the capability, staged here rather than in the project
because of the bootstrap wall: the packaged toolset that builds
`NSharpLang.Compiler.BootstrapServices` carries its own snapshot of that catalog, so until it is
repacked, `.nl` written against these rows fails to compile. A `.tests.nl` in the project therefore
breaks the contracts gate; a staged `.nl`-suffixed file trips the ownership audit. A closeout `.md`
is the one home that perturbs neither. (This is slice 20A's shape exactly.)

## The two walls, both MEASURED at this tree rather than assumed

Slice 21's closing measurement recorded that `ResolveMember` "closes outright" and that the
extension carrier "also closes". Re-verified at `89c4dc265` by writing both owners and compiling
them, **neither does** — and the reason is not a missing collaborator but missing catalog surface.
Slice 21's extraction listed only field-backed collaborators and one self-recursion; it did not walk
the bodies' bare calls to `Analyzer.cs`'s own private helpers, and the two walls live there.

**Wall 1 — `Assembly.GetTypes()` (the extension carrier).** `FindExternalExtensionMethods`
enumerates each loaded reference assembly through `GetLoadableTypes`, whose whole body is
`assembly.GetTypes()`. Measured:

```
error NL103: ... Declined at emit.call.instance-member-unmodeled: instance call
'Assembly.GetTypes' with 0 argument(s) is not modeled in
'AnalyzerExtensionMethodResolution.ScanExternalExtensionMethods'
```

`GetExportedTypes` — already in the catalog — is NOT a substitute. It answers a strictly smaller
set (measured on `System.Private.CoreLib`: declared types outnumber exported types), so swapping it
in would silently drop every extension method declared on an INTERNAL static class rather than
decline. The row was added instead.

**Wall 2 — `System.Reflection.EventInfo` (`ResolveMember`).**
`TryResolveReflectionPropertyOrField`'s third arm resolves a .NET EVENT to a `ReflectionEventInfo`
so that `+=` against one is rejected with its own diagnostic and `on`/`off` subscribe through the
accessors instead of touching the private backing field. The event arm needs the `EventInfo` TYPE,
which was not on the supported runtime-type surface at all. Measured, at the DECLARATION rather than
in a body — which is why a static-only probe class appears to pass and must not be trusted:

```
error NL103: ... Declined at emit.declaration.method-return: static method return type
'EventInfo?' could not be resolved
```

Everything else both members need was measured to compile at the pinned toolset:
`Type.get_Namespace`, `Type.GetField(string, BindingFlags)`, `Type.GetProperty(string, BindingFlags)`,
`Type.GetMethods(BindingFlags)`, `Type.get_IsSealed`/`get_IsAbstract`, `MethodInfo.get_IsSpecialName`,
`List<string>.Contains`, `List<MethodInfo>.ToArray`.

## The rows this phase adds

In `TryGetRuntimeTypeName` and `IsSupportedRuntimeTypeName`:

- `System.Reflection.EventInfo` (both the canonical mapping and the supported-name test).

In `GetInstanceCallPlan`:

- `System.Reflection.Assembly.GetTypes()` → `System.Type[]`
- `System.Type.GetEvent(string, BindingFlags)` → `System.Reflection.EventInfo`
- `System.Reflection.EventInfo.GetAddMethod(bool)` / `GetRemoveMethod(bool)` → `System.Reflection.MethodInfo`
- `System.Reflection.EventInfo.get_EventHandlerType()` / `get_DeclaringType()` → `System.Type`
- `System.Reflection.EventInfo.get_Name()` → `System.String`

## Proof at phase A — BY EXECUTION, not by compilation

Both shapes were compiled AND RUN against a freshly built compiler, which links a freshly built
`BootstrapServices` and is therefore behaviourally the post-repin toolset. The emitted binaries were
loaded and invoked:

- `Assembly.GetTypes()` on `System.Private.CoreLib` returned exactly the declared-type count that
  C# reflection reports for the same assembly, and that count is strictly GREATER than the exported
  count the same emitted program computes through `GetExportedTypes` — the row demonstrably widening
  the result, not merely compiling.
- The event surface returned `ProcessExit|add_ProcessExit|remove_ProcessExit|EventHandler|AppDomain`
  for `System.AppDomain.ProcessExit`, byte-equal to what C# reflection answers for the same event
  through `GetEvent`/`GetAddMethod(nonPublic: true)`/`GetRemoveMethod(nonPublic: true)`/
  `EventHandlerType`/`DeclaringType`.

A per-row deletion proof was scripted and started but ABANDONED after ~55 minutes — each iteration
rebuilds the whole xunit project — and is recorded here as NOT run. For the two headline rows the
evidence that does exist is stronger than a deletion would be: the PRE-state was measured directly,
with the exact decline text quoted above, before either row existed. The five supporting rows
(`Type.GetEvent`, the two accessor overloads, the two property getters) are unproven individually;
phase B should expect to discover that one of them is spelled wrong rather than that the set is
incomplete, and slice 20A's own history — where a row "in the catalog for many slices" turned out
not to be the cause — is the reason to check rather than assume.

## To activate (phase B, after the toolset repin)

1. Pack and install the SDK so the packaged toolset carries these rows.
2. Move `ResolveMember` (`Analyzer.cs`:8512, 279 lines) and its five exclusive private helpers —
   `CreateSoaIntrinsicFunction`, `TryResolveReflectionPropertyOrField`, `GetReflectionMemberFlags`,
   `ResolveDeclaredFunctionMember` (+ `CanResolveFunctionMemberFromTypeInfo`) and
   `TryResolveSourceObjectMember` — into N#, with `TryGetSoaColumn` moving as a fact the four other
   `Analyzer.cs` readers route to.
3. Move `TryResolveExtensionMethod` and `FindExternalExtensionMethods` onto
   `AnalyzerExtensionMethodResolution`, which slice 22 created and which already owns
   `IsExtensionReceiverApplicable`. Extend its constructor with the declaration context, the
   function-type factory, the CLR conversion, and the analyzer's three LIVE collections
   (`_extensionMethods`, `_usingNamespaces`, `_mlcAssemblies` — all `readonly` and mutated in place,
   so they cross BY REFERENCE); `_currentTypeName` is mutable and must cross as a PARAMETER.
4. The two blocked carrier members were WRITTEN at phase A and are preserved verbatim below, so
   phase B does not re-derive them. They compiled cleanly except for the `GetTypes` decline.
5. `dotnet test src/NSharpLang.Compiler.BootstrapServices -p:NSharpExcludeTests=false`.
6. Delete this file once the contracts live in the project.

## What phase B must pin

The event arm is the part no other arm reveals, and it is why the `EventInfo` row exists at all:

- A .NET event resolves to a `ReflectionEventInfo`, NOT to the private backing FIELD of the same
  name — the field exists in metadata and `GetField` would find it.
- The add/remove accessors are found with the NON-PUBLIC opt-in, because an event may be public
  while its accessors are not.
- The event's handler delegate type and declaring type ride on the answer, because `on`/`off` need
  both to emit the subscription.
- The probe ORDER is property, then field, then event — a name that is both must answer as the
  earlier kind.

And for the external scan:

- An extension declared on an INTERNAL static class in a referenced assembly is a candidate
  (`GetTypes`, not `GetExportedTypes`), while a type outside every imported namespace is not.
- A static class is `sealed abstract` in metadata; nothing else may host an extension.
- The surrogate-receiver rule: when the receiver converts only for BINDING, an instance method of
  the same name wins and the scan is abandoned — the `b91e4ba02` guard.

## The blocked carrier members, verbatim as written and compiled at phase A

Everything here compiled at the pinned toolset except `assemblies[i].GetTypes()`, which is the one
row phase A adds. `ExternalExtensionMethodType` and `ScanExternalExtensionMethods` are new names for
what `TryResolveExtensionMethod`'s duplicated external arms and `GetLoadableTypes` did in C#; the
`FindExternalExtensionMethods` restructure below is behaviour-identical to the C# `??` chain but
avoids the recorded N# narrowing gap (assign a `Type?` twice and N# will not narrow it — answer a
non-null value or fall through).

```
    // SOURCE EXTENSIONS FIRST, AND THE EXTERNAL SCAN IS THE FALLBACK — but only when no source
    // extension is APPLICABLE, not merely when none is named. A source `func` that shares the name
    // and rejects the receiver falls through to the external scan exactly as an unnamed one does.
    public func TryResolveExtensionMethod(
        targetType: TypeInfo,
        methodName: string,
        currentTypeName: string?): TypeInfo {
        matchingExtensions := new List<FunctionDeclaration>()
        matchIndex := 0
        while matchIndex < extensionMethods.Count {
            candidate := extensionMethods[matchIndex]
            if candidate.Name == methodName {
                matchingExtensions.Add(candidate)
            }
            matchIndex = matchIndex + 1
        }

        if matchingExtensions.Count == 0 {
            return ExternalExtensionMethodType(targetType, methodName)
        }

        applicableExtensions := new List<FunctionDeclaration>()
        applicableIndex := 0
        while applicableIndex < matchingExtensions.Count {
            candidate := matchingExtensions[applicableIndex]
            if candidate.Parameters.Count > 0 && IsExtensionReceiverApplicable(candidate, targetType) {
                applicableExtensions.Add(candidate)
            }
            applicableIndex = applicableIndex + 1
        }

        if applicableExtensions.Count == 0 {
            return ExternalExtensionMethodType(targetType, methodName)
        }

        if applicableExtensions.Count == 1 {
            return functionTypeFactory.CreateFromDeclaration(applicableExtensions[0], currentTypeName)
        }

        // Several source extensions claim the name; overload resolution picks between them later.
        functionTypes := new List<FunctionTypeInfo>()
        functionIndex := 0
        while functionIndex < applicableExtensions.Count {
            functionTypes.Add(
                functionTypeFactory.CreateFromDeclaration(applicableExtensions[functionIndex], currentTypeName))
            functionIndex = functionIndex + 1
        }

        return NSharpMethodGroupInfoFactory.FromFunctions(functionTypes)
    }

    // Does this source extension accept this receiver? An UNCONSTRAINED receiver — one spelled with
    // the function's own type parameter — accepts everything, and must answer before the reference
    // is resolved: resolving a type-parameter spelling would answer with whatever type shares that
    // name in scope.
    public func IsExtensionReceiverApplicable(candidate: FunctionDeclaration, targetType: TypeInfo): bool {
        if candidate.Parameters.Count == 0 {
            return false
        }

        receiverTypeReference := candidate.Parameters[0].Type
        simple := receiverTypeReference as SimpleTypeReference
        if simple != null && IsFunctionTypeParameter(candidate, simple.Name) {
            return true
        }

        receiverType := typeResolver.ResolveType(receiverTypeReference)
        return TypeInfoIdentityFacts.AreEqual(receiverType, targetType)
            || assignability.IsAssignable(receiverType, targetType)
    }

    static func IsFunctionTypeParameter(candidate: FunctionDeclaration, name: string): bool {
        typeParameters := candidate.TypeParameters
        if typeParameters == null {
            return false
        }

        index := 0
        while index < typeParameters.Count {
            if typeParameters[index].Name == name {
                return true
            }
            index = index + 1
        }

        return false
    }

    // The external answer, in the shape the member surface expects: one method is a method INFO,
    // several are a method GROUP, none is `unknown`.
    func ExternalExtensionMethodType(targetType: TypeInfo, methodName: string): TypeInfo {
        externalExtensions := FindExternalExtensionMethods(targetType, methodName)
        if externalExtensions.Count == 1 {
            winner := externalExtensions[0]
            return new ReflectionMethodInfo(winner, winner.get_Name() + "(...)")
        }

        if externalExtensions.Count > 1 {
            first := externalExtensions[0]
            return new ReflectionMethodGroupInfo(externalExtensions.ToArray(), first.get_Name() + "(...)")
        }

        return BuiltInTypes.Unknown
    }

    // Every `[Extension]` static under an IMPORTED namespace whose receiver parameter accepts the
    // target, in assembly then type then method order — the order the caller's method group keeps.
    //
    // THE EXACT CONVERSION AND THE BINDING CONVERSION ARE NOT INTERCHANGEABLE. When the receiver
    // converts exactly, that CLR type is the receiver and the scan runs. When it does not, the
    // binding conversion supplies only a SURROGATE — a stand-in whose instance surface was never
    // searched on the receiver's behalf — so an instance method of the same name must still win, and
    // the scan is abandoned rather than allowed to answer with an extension that would hide it.
    public func FindExternalExtensionMethods(targetType: TypeInfo, methodName: string): List<MethodInfo> {
        exactClrType := clrTypeConversion.TryConvertTypeInfoToClrType(targetType)
        if exactClrType != null {
            return ScanExternalExtensionMethods(exactClrType, methodName)
        }

        bindingClrType := clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(targetType)
        if bindingClrType == null {
            return new List<MethodInfo>()
        }

        if declarationContext.HasRuntimeInstanceMethod(bindingClrType, methodName) {
            return new List<MethodInfo>()
        }

        return ScanExternalExtensionMethods(bindingClrType, methodName)
    }

    func ScanExternalExtensionMethods(targetClrType: Type, methodName: string): List<MethodInfo> {
        methods := new List<MethodInfo>()
        memberFlags := BindingFlags.Public | BindingFlags.Static

        assemblyIndex := 0
        while assemblyIndex < assemblies.Count {
            assemblyTypes := assemblies[assemblyIndex].GetTypes()
            typeIndex := 0
            while typeIndex < assemblyTypes.Length {
                hostType := assemblyTypes[typeIndex]
                hostNamespace := hostType.get_Namespace()
                // A static class is `sealed abstract` in metadata; nothing else may declare one.
                if hostNamespace != null
                    && usingNamespaces.Contains(hostNamespace)
                    && hostType.get_IsSealed()
                    && hostType.get_IsAbstract() {
                    CollectExtensionMethods(hostType, memberFlags, methodName, targetClrType, methods)
                }
                typeIndex = typeIndex + 1
            }
            assemblyIndex = assemblyIndex + 1
        }

        return methods
    }

    static func CollectExtensionMethods(
        hostType: Type,
        memberFlags: BindingFlags,
        methodName: string,
        targetClrType: Type,
        methods: List<MethodInfo>) {
        hostMethods := hostType.GetMethods(memberFlags)
        methodIndex := 0
        while methodIndex < hostMethods.Length {
            method := hostMethods[methodIndex]
            if method.get_Name() == methodName && AnalyzerOverloadFacts.HasExtensionAttribute(method) {
                parameters := method.GetParameters()
                if parameters.Length > 0
                    && AnalyzerOverloadFacts.IsExtensionParameterCompatible(
                        parameters[0].get_ParameterType(),
                        targetClrType) {
                    methods.Add(method)
                }
            }
            methodIndex = methodIndex + 1
        }
    }
```
