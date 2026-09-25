namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.IO
import Mono.Cecil

// THE REFERENCE ASSEMBLY IS A PROGRAM'S SURFACE, NOT A COPY OF THE PROGRAM.
//
// What stood here before was a RESCOPED COPY of the implementation: every private method, every
// closure display class, every iterator state machine and every string literal a body happened to
// use travelled into `obj/…/ref/<Asm>.dll`, 4,344,320 bytes against the implementation's 4,440,064,
// a 2.2% difference that was entirely the rewritten reference table. That file could not do the one
// job a reference assembly exists to do: an implementation-only edit changed it, so
// `CopyRefAssembly` copied it, so every dependent project's up-to-date check failed, so the whole
// point of `ProduceReferenceAssembly` was lost.
//
// This writes what Roslyn's `/refout` writes:
//
//   * TYPES the assembly exports — public, and protected/nested-public members of them — plus the
//     package-private ones only when the project declares `internalsVisibleTo:`, which is the one
//     thing that makes internals part of the surface.
//   * NO METHOD BODIES. Every retained body becomes `ldnull; throw`, exactly as Roslyn's reference
//     assemblies do, so the file is still a verifiable assembly and still loads as one, while
//     carrying none of the IL an implementation edit rewrites.
//   * NOTHING THE COMPILER SYNTHESIZED. A display class, an iterator state machine and an anonymous
//     object type all carry a name beginning with `<`, which no source can spell; they exist
//     because of a BODY and they are therefore precisely the types that would make the surface move
//     when no surface moved.
//   * `[ReferenceAssemblyAttribute]`, so the runtime, `ilverify` and every metadata reader can tell
//     what they are holding.
//   * The same TYPE-REFERENCE RESCOPE the copy already performed, because `PersistedAssemblyBuilder`
//     scopes its references to the implementation core library (`System.Private.CoreLib`), which no
//     reference pack contains — without the rescope nothing could compile against the result.
//   * A CONTENT-DERIVED module version id and timestamp (`ColumnarDeterministicPeIdentity`), which
//     is what turns "the surface did not change" into "the bytes did not change".
//
// A NON-VISIBLE TYPE IS NOT DROPPED WHEN THE RETAINED SURFACE STILL NAMES IT. A public member may
// legitimately mention a package-private type — as a base, an interface, a field, a parameter, a
// return, an explicit-implementation slot or an attribute — and a reference assembly that dropped
// the type would carry a signature pointing at nothing. The retained set is therefore closed over
// the surface it itself declares, to a fixed point, before anything is removed.
class ColumnarReferenceAssemblyWriter {

    // The one entry point. `referencePaths` are the resolved reference assemblies the rescope reads
    // ownership from; `keepInternals` is true exactly when the project declares `internalsVisibleTo:`.
    static func TryWrite(
        implementationPath: string,
        referenceAssemblyPath: string,
        referencePaths: IReadOnlyList<string>?,
        keepInternals: bool
    ): bool {
        if string.IsNullOrWhiteSpace(referenceAssemblyPath) {
            return false
        }
        if !File.Exists(implementationPath) {
            return false
        }
        if SdkEmitTaskKernels.IsSameOutputPath(Path.GetFullPath(implementationPath), Path.GetFullPath(referenceAssemblyPath)) {
            return false
        }

        referenceAssemblyDirectory := Path.GetDirectoryName(Path.GetFullPath(referenceAssemblyPath))
        if !string.IsNullOrEmpty(referenceAssemblyDirectory) {
            Directory.CreateDirectory(referenceAssemblyDirectory)
        }

        let ownerNames: Dictionary<string, AssemblyNameDefinition> = null
        owners := BuildReferenceTypeOwners(referencePaths, implementationPath, referenceAssemblyPath, out ownerNames)

        readerParameters := new ReaderParameters()
        readerParameters.ReadingMode = ReadingMode.Immediate
        readerParameters.InMemory = true
        assembly := AssemblyDefinition.ReadAssembly(implementationPath, readerParameters)
        let image: byte[] = null
        try {
            module := assembly.MainModule
            PruneToSurface(assembly, module, keepInternals)
            RescopeTypeReferences(module, owners, ownerNames)
            RemoveUnusedCoreLibAssemblyReference(module)
            ApplyReferenceAssemblyAttribute(assembly, module, owners, ownerNames)
            buffer := new MemoryStream()
            try {
                writeTarget: Stream = buffer
                assembly.Write(writeTarget)
                image = buffer.ToArray()
            } finally {
                buffer.Dispose()
            }
        } finally {
            assembly.Dispose()
        }

        ColumnarDeterministicPeIdentity.Apply(image)
        File.WriteAllBytes(referenceAssemblyPath, image)
        return true
    }

    // ── WHAT THE SURFACE IS ─────────────────────────────────────────────────────────────────────

    private static func PruneToSurface(assembly: AssemblyDefinition, module: ModuleDefinition, keepInternals: bool) {
        index := new Dictionary<string, TypeDefinition>(StringComparer.Ordinal)
        declaringOf := new Dictionary<string, TypeDefinition>(StringComparer.Ordinal)
        allTypes := new List<TypeDefinition>()
        topLevel := MaterializeTypes(module.Types)
        for topLevelType in topLevel {
            IndexTypeTree(topLevelType, null, index, declaringOf, allTypes)
        }

        retainedMethods := new Dictionary<string, List<MethodDefinition>>(StringComparer.Ordinal)
        retainedFields := new Dictionary<string, List<FieldDefinition>>(StringComparer.Ordinal)
        for indexedType in allTypes {
            retainedMethods.Add(indexedType.FullName, SelectRetainedMethods(indexedType, keepInternals))
            retainedFields.Add(indexedType.FullName, SelectRetainedFields(indexedType, keepInternals))
        }

        retained := new HashSet<string>(StringComparer.Ordinal)
        pending := new List<TypeDefinition>()
        for candidate in allTypes {
            if IsRetainedByVisibility(candidate, declaringOf, keepInternals) {
                RetainType(candidate, declaringOf, retained, pending)
            }
        }

        // THE ENTRY POINT SURVIVES WHATEVER ITS VISIBILITY IS. `main` is lowered onto a free-function
        // holder and is not part of anybody's public surface, but `ModuleDefinition.EntryPoint` names
        // it: remove the method and Cecil refuses to write the module at all ("Member 'System.Void
        // main()' is declared in another module and needs to be imported"). A reference assembly for
        // an executable is still an executable, exactly as Roslyn's `/refout` leaves it.
        RetainEntryPoint(module, allTypes, retainedMethods, declaringOf, retained, pending)

        // An ASSEMBLY-level attribute can name a module-local type too, and nothing else in the walk
        // below would reach it.
        assemblySurface := new List<TypeReference>()
        CollectAttributeTypes(MaterializeAttributes(assembly.CustomAttributes), assemblySurface)
        for assemblyReference in assemblySurface {
            MarkReferencedDefinitions(assemblyReference, index, declaringOf, retained, pending)
        }

        // THE FIXED POINT. Each newly retained type contributes the types ITS OWN retained surface
        // names; anything module-local that appears there is retained in turn, and the walk ends
        // when a round adds nothing.
        while pending.Count > 0 {
            current := pending[pending.Count - 1]
            pending.RemoveAt(pending.Count - 1)
            surface := new List<TypeReference>()
            CollectTypeSurface(current, retainedMethods, retainedFields, surface)
            for surfaceReference in surface {
                MarkReferencedDefinitions(surfaceReference, index, declaringOf, retained, pending)
            }
        }

        for pruneTarget in allTypes {
            if retained.Contains(pruneTarget.FullName) {
                PruneMembers(pruneTarget, retainedMethods[pruneTarget.FullName], retainedFields[pruneTarget.FullName])
            }
        }

        RemoveDroppedTypes(module, retained)
    }

    // The owner is found by SCANNING rather than through `MethodDefinition.DeclaringType`, for the
    // same hidden-member reason the type walk carries its declaring type down.
    private static func RetainEntryPoint(
        module: ModuleDefinition,
        allTypes: List<TypeDefinition>,
        retainedMethods: Dictionary<string, List<MethodDefinition>>,
        declaringOf: Dictionary<string, TypeDefinition>,
        retained: HashSet<string>,
        pending: List<TypeDefinition>
    ) {
        entryPoint := module.EntryPoint
        if entryPoint == null {
            return
        }
        for candidate in allTypes {
            methods := MaterializeMethods(candidate.Methods)
            for method in methods {
                if Object.ReferenceEquals(method, entryPoint) {
                    RetainType(candidate, declaringOf, retained, pending)
                    let kept: List<MethodDefinition> = null
                    if retainedMethods.TryGetValue(candidate.FullName, out kept) {
                        if !kept.Contains(method) {
                            kept.Add(method)
                        }
                    }
                    return
                }
            }
        }
    }

    // The declaring type is carried down the walk rather than read back off the type, because
    // `TypeDefinition.DeclaringType` HIDES `TypeReference.DeclaringType` with a narrower return and
    // this back end declines the ambiguous member read.
    private static func IndexTypeTree(
        type: TypeDefinition,
        declaring: TypeDefinition?,
        index: Dictionary<string, TypeDefinition>,
        declaringOf: Dictionary<string, TypeDefinition>,
        allTypes: List<TypeDefinition>
    ) {
        index[type.FullName] = type
        if declaring != null {
            declaringOf[type.FullName] = declaring
        }
        allTypes.Add(type)
        nested := MaterializeTypes(type.NestedTypes)
        for nestedType in nested {
            IndexTypeTree(nestedType, type, index, declaringOf, allTypes)
        }
    }

    // `<Module>` is the module pseudo-type and must survive; every other `<`-prefixed name is a
    // display class, an iterator state machine or an anonymous object type, and belongs to a BODY.
    private static func IsSynthesizedTypeName(name: string): bool {
        if name == SdkEmitTaskKernels.ModuleTypeName() {
            return false
        }
        if name.Length == 0 {
            return false
        }
        return name.StartsWith("<", StringComparison.Ordinal)
    }

    private static func IsRetainedByVisibility(type: TypeDefinition, declaringOf: Dictionary<string, TypeDefinition>, keepInternals: bool): bool {
        if type.FullName == SdkEmitTaskKernels.ModuleTypeName() {
            return true
        }
        if IsSynthesizedTypeName(type.Name) {
            return false
        }
        let declaring: TypeDefinition = null
        if declaringOf.TryGetValue(type.FullName, out declaring) {
            if !IsRetainedByVisibility(declaring, declaringOf, keepInternals) {
                return false
            }
            if type.IsNestedPublic {
                return true
            }
            if type.IsNestedFamily {
                return true
            }
            if type.IsNestedFamilyOrAssembly {
                return true
            }
            if !keepInternals {
                return false
            }
            if type.IsNestedAssembly {
                return true
            }
            return type.IsNestedFamilyAndAssembly
        }

        if type.IsPublic {
            return true
        }
        return keepInternals
    }

    private static func RetainType(type: TypeDefinition, declaringOf: Dictionary<string, TypeDefinition>, retained: HashSet<string>, pending: List<TypeDefinition>) {
        if !retained.Add(type.FullName) {
            return
        }
        pending.Add(type)
        let declaring: TypeDefinition = null
        if declaringOf.TryGetValue(type.FullName, out declaring) {
            RetainType(declaring, declaringOf, retained, pending)
        }
    }

    private static func SelectRetainedMethods(type: TypeDefinition, keepInternals: bool): List<MethodDefinition> {
        selected := new List<MethodDefinition>()
        methods := MaterializeMethods(type.Methods)
        for method in methods {
            if IsRetainedMember(method.IsPublic, method.IsFamily, method.IsFamilyOrAssembly, method.IsAssembly, method.IsFamilyAndAssembly, keepInternals) {
                selected.Add(method)
            } else if method.HasOverrides {
                // An explicit interface implementation is `private final virtual` and IS surface:
                // it is the only thing that says which slot the member fills.
                selected.Add(method)
            }
        }
        return selected
    }

    // A VALUE TYPE KEEPS EVERY FIELD IT HAS. A struct's private instance fields are its layout and
    // its size, an enum's `value__` is its underlying type, and a consumer that cannot see them
    // cannot lay the type out at all. A reference type's fields follow the ordinary visibility rule.
    private static func SelectRetainedFields(type: TypeDefinition, keepInternals: bool): List<FieldDefinition> {
        selected := new List<FieldDefinition>()
        fields := MaterializeFields(type.Fields)
        keepEveryField := type.IsValueType
        for field in fields {
            if keepEveryField {
                selected.Add(field)
            } else if IsRetainedMember(field.IsPublic, field.IsFamily, field.IsFamilyOrAssembly, field.IsAssembly, field.IsFamilyAndAssembly, keepInternals) {
                selected.Add(field)
            }
        }
        return selected
    }

    private static func IsRetainedMember(isPublic: bool, isFamily: bool, isFamilyOrAssembly: bool, isAssembly: bool, isFamilyAndAssembly: bool, keepInternals: bool): bool {
        if isPublic {
            return true
        }
        if isFamily {
            return true
        }
        if isFamilyOrAssembly {
            return true
        }
        if !keepInternals {
            return false
        }
        if isAssembly {
            return true
        }
        return isFamilyAndAssembly
    }

    private static func CollectTypeSurface(
        type: TypeDefinition,
        retainedMethods: Dictionary<string, List<MethodDefinition>>,
        retainedFields: Dictionary<string, List<FieldDefinition>>,
        surface: List<TypeReference>
    ) {
        baseType := type.BaseType
        if baseType != null {
            surface.Add(baseType)
        }
        interfaces := MaterializeInterfaces(type.Interfaces)
        for interfaceImplementation in interfaces {
            surface.Add(interfaceImplementation.InterfaceType)
        }
        CollectAttributeTypes(MaterializeAttributes(type.CustomAttributes), surface)

        let methods: List<MethodDefinition> = null
        if retainedMethods.TryGetValue(type.FullName, out methods) {
            for method in methods {
                surface.Add(method.ReturnType)
                parameters := MaterializeParameters(method.Parameters)
                for parameter in parameters {
                    surface.Add(parameter.ParameterType)
                }
                overrides := MaterializeMethodReferences(method.Overrides)
                for overriddenMethod in overrides {
                    surface.Add(overriddenMethod.DeclaringType)
                }
                CollectAttributeTypes(MaterializeAttributes(method.CustomAttributes), surface)
            }
        }

        let fields: List<FieldDefinition> = null
        if retainedFields.TryGetValue(type.FullName, out fields) {
            for field in fields {
                surface.Add(field.FieldType)
                CollectAttributeTypes(MaterializeAttributes(field.CustomAttributes), surface)
            }
        }
    }

    private static func CollectAttributeTypes(attributes: List<CustomAttribute>, surface: List<TypeReference>) {
        for attribute in attributes {
            constructor := attribute.Constructor
            if constructor != null {
                declaringType := constructor.DeclaringType
                if declaringType != null {
                    surface.Add(declaringType)
                }
            }
        }
    }

    // An array of a package-private type, a `&` to one, a `List<>` closed over one: the definition
    // that has to survive is always reached by peeling the specification and the type arguments.
    private static func MarkReferencedDefinitions(
        reference: TypeReference?,
        index: Dictionary<string, TypeDefinition>,
        declaringOf: Dictionary<string, TypeDefinition>,
        retained: HashSet<string>,
        pending: List<TypeDefinition>
    ) {
        if reference == null {
            return
        }

        specification := reference as TypeSpecification
        if specification != null {
            MarkReferencedDefinitions(specification.ElementType, index, declaringOf, retained, pending)
        }

        genericInstance := reference as GenericInstanceType
        if genericInstance != null {
            arguments := MaterializeTypeReferenceList(genericInstance.GenericArguments)
            for argument in arguments {
                MarkReferencedDefinitions(argument, index, declaringOf, retained, pending)
            }
        }

        let definition: TypeDefinition = null
        if index.TryGetValue(reference.FullName, out definition) {
            RetainType(definition, declaringOf, retained, pending)
        }
    }

    private static func PruneMembers(type: TypeDefinition, keptMethods: List<MethodDefinition>, keptFields: List<FieldDefinition>) {
        keptMethodSet := new HashSet<MethodDefinition>()
        for keptMethod in keptMethods {
            keptMethodSet.Add(keptMethod)
        }
        keptFieldSet := new HashSet<FieldDefinition>()
        for keptField in keptFields {
            keptFieldSet.Add(keptField)
        }

        methods := MaterializeMethods(type.Methods)
        for method in methods {
            if !keptMethodSet.Contains(method) {
                type.Methods.Remove(method)
            } else {
                ReplaceBodyWithThrowNull(method)
            }
        }

        fields := MaterializeFields(type.Fields)
        for field in fields {
            if !keptFieldSet.Contains(field) {
                type.Fields.Remove(field)
            }
        }

        properties := MaterializeProperties(type.Properties)
        for property in properties {
            getter := property.GetMethod
            setter := property.SetMethod
            keptGetter := getter != null && keptMethodSet.Contains(getter)
            keptSetter := setter != null && keptMethodSet.Contains(setter)
            if !keptGetter {
                property.GetMethod = null
            }
            if !keptSetter {
                property.SetMethod = null
            }
            if !keptGetter && !keptSetter {
                type.Properties.Remove(property)
            }
        }

        events := MaterializeEvents(type.Events)
        for eventDefinition in events {
            adder := eventDefinition.AddMethod
            remover := eventDefinition.RemoveMethod
            invoker := eventDefinition.InvokeMethod
            keptAdder := adder != null && keptMethodSet.Contains(adder)
            keptRemover := remover != null && keptMethodSet.Contains(remover)
            keptInvoker := invoker != null && keptMethodSet.Contains(invoker)
            if !keptAdder {
                eventDefinition.AddMethod = null
            }
            if !keptRemover {
                eventDefinition.RemoveMethod = null
            }
            if !keptInvoker {
                eventDefinition.InvokeMethod = null
            }
            if !keptAdder && !keptRemover && !keptInvoker {
                type.Events.Remove(eventDefinition)
            }
        }
    }

    // `ldnull; throw` is what a Roslyn reference assembly carries, and it is deliberately not an
    // empty body: a method with no body at all is abstract or external, which is a DIFFERENT
    // declaration, and `ilverify` would be right to say so.
    private static func ReplaceBodyWithThrowNull(method: MethodDefinition) {
        if !method.HasBody {
            return
        }
        body := new Mono.Cecil.Cil.MethodBody(method)
        processor := body.GetILProcessor()
        processor.Emit(Mono.Cecil.Cil.OpCodes.Ldnull)
        processor.Emit(Mono.Cecil.Cil.OpCodes.Throw)
        body.MaxStackSize = 1
        method.Body = body
    }

    private static func RemoveDroppedTypes(module: ModuleDefinition, retained: HashSet<string>) {
        topLevel := MaterializeTypes(module.Types)
        for topLevelType in topLevel {
            if retained.Contains(topLevelType.FullName) {
                RemoveDroppedNestedTypes(topLevelType, retained)
            } else {
                module.Types.Remove(topLevelType)
            }
        }
    }

    private static func RemoveDroppedNestedTypes(type: TypeDefinition, retained: HashSet<string>) {
        nested := MaterializeTypes(type.NestedTypes)
        for nestedType in nested {
            if retained.Contains(nestedType.FullName) {
                RemoveDroppedNestedTypes(nestedType, retained)
            } else {
                type.NestedTypes.Remove(nestedType)
            }
        }
    }

    // ── THE ATTRIBUTE THAT SAYS WHAT THIS FILE IS ───────────────────────────────────────────────

    // THE ATTRIBUTE IS ADDED LAST AND SCOPED BY OWNER. It is a new `TypeReference`, so it is not in
    // the table `GetTypeReferences` reads and the rescope above cannot move it; and the corelib row
    // it would otherwise name may have just been removed, which would leave the reference pointing
    // at a row that is no longer in the module. Ask the owner table for the assembly that actually
    // declares it — `System.Runtime` in every reference pack — and fall back to the module's own
    // core library only when nothing is known about any reference.
    private static func ApplyReferenceAssemblyAttribute(
        assembly: AssemblyDefinition,
        module: ModuleDefinition,
        owners: ReferenceTypeOwners,
        ownerNames: Dictionary<string, AssemblyNameDefinition>
    ) {
        existing := MaterializeAttributes(assembly.CustomAttributes)
        for attribute in existing {
            attributeType := attribute.AttributeType
            if attributeType != null && attributeType.FullName == ReferenceAssemblyAttributeName() {
                return
            }
        }

        scope: IMetadataScope = module.TypeSystem.CoreLibrary
        owner := owners.Resolve(ReferenceAssemblyAttributeName())
        if owner != null {
            ownerKey: string = owner
            scope = GetOrAddAssemblyReference(module, ownerNames[ownerKey])
        }
        attributeTypeReference := new Mono.Cecil.TypeReference("System.Runtime.CompilerServices", "ReferenceAssemblyAttribute", module, scope)
        constructor := new Mono.Cecil.MethodReference(".ctor", module.TypeSystem.Void, attributeTypeReference)
        constructor.HasThis = true
        assembly.CustomAttributes.Add(new CustomAttribute(constructor))
    }

    private static func ReferenceAssemblyAttributeName(): string {
        return "System.Runtime.CompilerServices.ReferenceAssemblyAttribute"
    }

    // ── THE SCOPE REWRITE, UNCHANGED IN RULE AND MOVED IN OWNER ─────────────────────────────────

    private static func RescopeTypeReferences(module: ModuleDefinition, owners: ReferenceTypeOwners, ownerNames: Dictionary<string, AssemblyNameDefinition>) {
        if SdkEmitTaskKernels.ShouldCopyImplementationVerbatim(owners) {
            return
        }
        typeReferences := MaterializeTypeReferences(module)
        for typeReference in typeReferences {
            owner := owners.Resolve(typeReference.FullName)
            if owner != null && SdkEmitTaskKernels.ShouldRescopeTypeReference(ScopeName(typeReference), true) {
                typeReference.Scope = GetOrAddAssemblyReference(module, ownerNames[owner])
            }
        }
    }

    private static func BuildReferenceTypeOwners(
        referencePaths: IReadOnlyList<string>?,
        implementationPath: string,
        referenceAssemblyPath: string,
        out ownerNames: Dictionary<string, AssemblyNameDefinition>
    ): ReferenceTypeOwners {
        owners := new ReferenceTypeOwners()
        ownerNames = new Dictionary<string, AssemblyNameDefinition>(StringComparer.Ordinal)
        if referencePaths == null {
            return owners
        }

        implementationFullPath := Path.GetFullPath(implementationPath)
        referenceFullPath := Path.GetFullPath(referenceAssemblyPath)
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        referenceIndex := 0
        while referenceIndex < referencePaths.Count {
            referencePath := referencePaths[referenceIndex]
            referenceIndex = referenceIndex + 1
            if string.IsNullOrWhiteSpace(referencePath) {
                continue
            }
            fullPath := Path.GetFullPath(referencePath)
            ownOutput := SdkEmitTaskKernels.IsSameOutputPath(fullPath, implementationFullPath) || SdkEmitTaskKernels.IsSameOutputPath(fullPath, referenceFullPath)
            if SdkEmitTaskKernels.ShouldScanReferenceForOwners(fullPath, File.Exists(fullPath), ownOutput) && seen.Add(fullPath) {
                ScanReferenceAssembly(fullPath, owners, ownerNames)
            }
        }

        return owners
    }

    private static func ScanReferenceAssembly(fullPath: string, owners: ReferenceTypeOwners, ownerNames: Dictionary<string, AssemblyNameDefinition>) {
        let referenceAssembly: AssemblyDefinition? = null
        try {
            readParameters := new ReaderParameters()
            readParameters.ReadingMode = ReadingMode.Deferred
            openedReferenceAssembly := AssemblyDefinition.ReadAssembly(fullPath, readParameters)
            referenceAssembly = openedReferenceAssembly
            RecordReferenceAssembly(owners, ownerNames, openedReferenceAssembly)
        } catch (BadImageFormatException) {
            return
        } catch (IOException) {
            return
        } finally {
            if referenceAssembly != null {
                referenceAssembly.Dispose()
            }
        }
    }

    private static func RecordReferenceAssembly(owners: ReferenceTypeOwners, ownerNames: Dictionary<string, AssemblyNameDefinition>, referenceAssembly: AssemblyDefinition) {
        ownerNameForKey := referenceAssembly.Name
        ownerKey := ownerNameForKey.FullName
        ownerNamesForAdd := ownerNames
        ownerNameForMap := referenceAssembly.Name
        ownerNamesForAdd.TryAdd(ownerKey, ownerNameForMap)

        definitionModule := referenceAssembly.MainModule
        definedTypes := MaterializeTypes(definitionModule.Types)
        for definedType in definedTypes {
            RecordDefinedTypes(owners, ownerKey, definedType)
        }

        forwarderModule := referenceAssembly.MainModule
        exportedTypes := MaterializeExportedTypes(forwarderModule.ExportedTypes)
        for exportedType in exportedTypes {
            owners.RecordForwarder(exportedType.FullName, ownerKey)
        }
    }

    private static func RecordDefinedTypes(owners: ReferenceTypeOwners, ownerKey: string, typeDefinition: TypeDefinition) {
        owners.RecordDefinition(typeDefinition.FullName, ownerKey)
        nested := MaterializeTypes(typeDefinition.NestedTypes)
        for nestedType in nested {
            RecordDefinedTypes(owners, ownerKey, nestedType)
        }
    }

    private static func GetOrAddAssemblyReference(module: ModuleDefinition, owner: AssemblyNameDefinition): AssemblyNameReference {
        assemblyReferences := MaterializeAssemblyReferences(module.AssemblyReferences)
        for reference in assemblyReferences {
            if SdkEmitTaskKernels.AssemblyReferenceMatches(
                reference.Name,
                VersionText(reference.Version),
                owner.Name,
                VersionText(owner.Version)
            ) {
                return reference
            }
        }

        assemblyReference := new AssemblyNameReference(owner.Name, owner.Version)
        assemblyReference.Culture = owner.Culture
        assemblyReference.PublicKeyToken = owner.PublicKeyToken
        module.AssemblyReferences.Add(assemblyReference)
        return assemblyReference
    }

    private static func RemoveUnusedCoreLibAssemblyReference(module: ModuleDefinition) {
        hasCoreLibTypeReference := false
        typeReferences := MaterializeTypeReferences(module)
        for typeReference in typeReferences {
            if SdkEmitTaskKernels.IsImplementationCoreLibrary(ScopeName(typeReference)) {
                hasCoreLibTypeReference = true
                break
            }
        }

        if !SdkEmitTaskKernels.ShouldRemoveCoreLibraryReference(hasCoreLibTypeReference) {
            return
        }

        removable := new List<AssemblyNameReference>()
        assemblyReferences := MaterializeAssemblyReferences(module.AssemblyReferences)
        for reference in assemblyReferences {
            if SdkEmitTaskKernels.IsImplementationCoreLibrary(reference.Name) {
                removable.Add(reference)
            }
        }

        for removableItem in removable {
            module.AssemblyReferences.Remove(removableItem)
        }
    }

    private static func ScopeName(typeReference: Mono.Cecil.TypeReference): string? {
        scopeValue: object = typeReference.Scope
        scope := scopeValue as AssemblyNameReference
        if scope == null {
            return null
        }
        return scope.Name
    }

    private static func VersionText(version: Version?): string {
        if version == null {
            return ""
        }
        versionObject: object = version
        return versionObject.ToString() ?? ""
    }

    // ── MATERIALIZERS ───────────────────────────────────────────────────────────────────────────
    //
    // Cecil's collections are walked through their generic enumerator and the non-generic
    // `IEnumerator` for movement, which is the shape this back end emits; the list is taken whole
    // before anything is removed, because every removal here happens while the collection is being
    // decided about.

    private static func MaterializeTypes(types: IEnumerable<TypeDefinition>): List<TypeDefinition> {
        materialized := new List<TypeDefinition>()
        enumerator := types.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            while movement.MoveNext() {
                materialized.Add(enumerator.get_Current())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return materialized
    }

    private static func MaterializeMethods(methods: IEnumerable<MethodDefinition>): List<MethodDefinition> {
        materialized := new List<MethodDefinition>()
        enumerator := methods.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            while movement.MoveNext() {
                materialized.Add(enumerator.get_Current())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return materialized
    }

    private static func MaterializeFields(fields: IEnumerable<FieldDefinition>): List<FieldDefinition> {
        materialized := new List<FieldDefinition>()
        enumerator := fields.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            while movement.MoveNext() {
                materialized.Add(enumerator.get_Current())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return materialized
    }

    private static func MaterializeProperties(properties: IEnumerable<PropertyDefinition>): List<PropertyDefinition> {
        materialized := new List<PropertyDefinition>()
        enumerator := properties.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            while movement.MoveNext() {
                materialized.Add(enumerator.get_Current())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return materialized
    }

    private static func MaterializeEvents(events: IEnumerable<EventDefinition>): List<EventDefinition> {
        materialized := new List<EventDefinition>()
        enumerator := events.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            while movement.MoveNext() {
                materialized.Add(enumerator.get_Current())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return materialized
    }

    private static func MaterializeInterfaces(interfaces: IEnumerable<InterfaceImplementation>): List<InterfaceImplementation> {
        materialized := new List<InterfaceImplementation>()
        enumerator := interfaces.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            while movement.MoveNext() {
                materialized.Add(enumerator.get_Current())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return materialized
    }

    private static func MaterializeParameters(parameters: IEnumerable<ParameterDefinition>): List<ParameterDefinition> {
        materialized := new List<ParameterDefinition>()
        enumerator := parameters.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            while movement.MoveNext() {
                materialized.Add(enumerator.get_Current())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return materialized
    }

    private static func MaterializeMethodReferences(references: IEnumerable<MethodReference>): List<MethodReference> {
        materialized := new List<MethodReference>()
        enumerator := references.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            while movement.MoveNext() {
                materialized.Add(enumerator.get_Current())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return materialized
    }

    private static func MaterializeAttributes(attributes: IEnumerable<CustomAttribute>): List<CustomAttribute> {
        materialized := new List<CustomAttribute>()
        enumerator := attributes.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            while movement.MoveNext() {
                materialized.Add(enumerator.get_Current())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return materialized
    }

    private static func MaterializeExportedTypes(exportedTypes: IEnumerable<ExportedType>): List<ExportedType> {
        materialized := new List<ExportedType>()
        enumerator := exportedTypes.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            while movement.MoveNext() {
                materialized.Add(enumerator.get_Current())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return materialized
    }

    private static func MaterializeAssemblyReferences(references: IEnumerable<AssemblyNameReference>): List<AssemblyNameReference> {
        materialized := new List<AssemblyNameReference>()
        enumerator := references.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            while movement.MoveNext() {
                materialized.Add(enumerator.get_Current())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return materialized
    }

    private static func MaterializeTypeReferenceList(references: IEnumerable<Mono.Cecil.TypeReference>): List<Mono.Cecil.TypeReference> {
        materialized := new List<Mono.Cecil.TypeReference>()
        enumerator := references.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            while movement.MoveNext() {
                materialized.Add(enumerator.get_Current())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return materialized
    }

    private static func MaterializeTypeReferences(module: ModuleDefinition): List<Mono.Cecil.TypeReference> {
        return MaterializeTypeReferenceList(module.GetTypeReferences())
    }
}
