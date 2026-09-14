namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Reflection.Emit
import System.Reflection.Metadata
import System.Reflection.Metadata.Ecma335
import System.Reflection.PortableExecutable
import NSharpLang.Compiler

// Reflection.Emit currently omits custom modifiers when it creates a MemberRef for a method on a
// constructed type. `init` exposes that runtime defect because its setter returns
// `void modreq(IsExternalInit)`: the emitted call names a different method and fails to bind.
//
// The repair is deliberately a metadata operation. The discovery pass reads the MemberRef that
// Reflection.Emit actually chose, keeps its parent/name/signature, and records the exact modifier
// positions from the open definition. The final pass appends corrected rows and changes only real
// InlineMethod operands in decoded method bodies. No closed parameter type is reconstructed.
//
// ManagedPEBuilder links a MetadataBuilder's heap builders on Serialize, so the same builder cannot
// be serialized once for discovery and again after appending rows (.NET 10 throws from
// MetadataBuilder.WriteHeapsTo/BlobBuilder.LinkSuffix). ColumnarIlEmitter therefore performs the
// discovery emission only when this ledger is non-empty, then repeats that emission with the plan.
class ColumnarModifiedMemberReferenceRequest {
    Owner: Type
    EmittedMethod: MethodInfo
    SignatureMethod: MethodInfo
    ParameterTypes: Type[]
    ReturnType: Type
    IsStatic: bool
    GenericArity: int
    Name: string
    Identity: string

    constructor(owner: Type, emittedMethod: MethodInfo, signatureMethod: MethodInfo, parameterTypes: Type[], returnType: Type) {
        Owner = owner
        EmittedMethod = emittedMethod
        SignatureMethod = signatureMethod
        ParameterTypes = parameterTypes
        ReturnType = returnType
        IsStatic = emittedMethod.get_IsStatic()
        GenericArity = emittedMethod.get_IsGenericMethod() ? emittedMethod.GetGenericArguments().Length : 0
        Name = signatureMethod.get_Name()
        Identity = ColumnarModifiedMemberReferenceRepair.RuntimeTypeIdentity(owner) + "::" + ColumnarModifiedMemberReferenceRepair.RuntimeMethodIdentity(emittedMethod) + "::source=" + ColumnarModifiedMemberReferenceRepair.RuntimeMethodIdentity(signatureMethod)
    }
}

class ColumnarModifiedMemberReferencePlanEntry {
    OldToken: int
    Parent: EntityHandle
    Name: string
    ExistingSignature: byte[]
    SourceSignature: byte[]
    Modifiers: Dictionary<int, ColumnarModifiedMemberReferenceModifier>
    ReplacementToken: int
    RepairedSignature: byte[]

    constructor(oldToken: int, parent: EntityHandle, name: string, existingSignature: byte[], sourceSignature: byte[], modifiers: Dictionary<int, ColumnarModifiedMemberReferenceModifier>) {
        OldToken = oldToken
        Parent = parent
        Name = name
        ExistingSignature = existingSignature
        SourceSignature = sourceSignature
        Modifiers = modifiers
        ReplacementToken = 0
        RepairedSignature = null
    }
}

class ColumnarModifiedMemberReferenceModifier {
    DiscoveryHandle: EntityHandle
    RuntimeType: Type?

    constructor(discoveryHandle: EntityHandle, runtimeType: Type?) {
        DiscoveryHandle = discoveryHandle
        RuntimeType = runtimeType
    }
}

class ColumnarModifiedMemberReferencePlan {
    Entries: List<ColumnarModifiedMemberReferencePlanEntry>
    Fingerprint: string
    DiscoveryImage: byte[]
    DiscoveryIl: byte[]
    TypeReferenceCount: int
    TypeSpecificationCount: int
    MemberReferenceCount: int

    constructor(entries: List<ColumnarModifiedMemberReferencePlanEntry>, fingerprint: string, discoveryImage: byte[], discoveryIl: byte[], typeReferenceCount: int, typeSpecificationCount: int, memberReferenceCount: int) {
        Entries = entries
        Fingerprint = fingerprint
        DiscoveryImage = discoveryImage
        DiscoveryIl = discoveryIl
        TypeReferenceCount = typeReferenceCount
        TypeSpecificationCount = typeSpecificationCount
        MemberReferenceCount = memberReferenceCount
    }
}

class ColumnarModifiedMemberReferenceLedger {
    Requests: List<ColumnarModifiedMemberReferenceRequest>

    constructor() {
        Requests = new List<ColumnarModifiedMemberReferenceRequest>()
    }

    func Record(owner: Type, signatureMethod: MethodInfo) {
        parameters := signatureMethod.GetParameters()
        parameterTypes := new Type[](parameters.Length)
        for index := 0; index < parameters.Length; index++ {
            parameterTypes[index] = parameters[index].get_ParameterType()
        }
        Record(owner, signatureMethod, signatureMethod, parameterTypes, signatureMethod.get_ReturnType())
    }

    func Record(owner: Type, emittedMethod: MethodInfo, signatureMethod: MethodInfo, parameterTypes: Type[], returnType: Type) {
        request := new ColumnarModifiedMemberReferenceRequest(owner, emittedMethod, signatureMethod, parameterTypes, returnType)
        for existing in Requests {
            if existing.Identity == request.Identity {
                return
            }
        }
        Requests.Add(request)
    }

    func Fingerprint(): string {
        result := ""
        for request in Requests {
            result = result + request.Identity.Length.ToString() + ":" + request.Identity + ";"
        }
        return result
    }
}

class ColumnarModifiedMemberReferenceRepair {

    // ECMA-335 element type codes used by the structural signature walk.
    const CModRequired: int = 0x1f
    const CModOptional: int = 0x20
    const ByRef: int = 0x10
    const Pointer: int = 0x0f
    const SzArray: int = 0x1d
    const ArrayType: int = 0x14
    const GenericInstance: int = 0x15
    const FunctionPointer: int = 0x1b
    const Var: int = 0x13
    const MVar: int = 0x1e
    const Sentinel: int = 0x41
    const Pinned: int = 0x45

    static func RuntimeTypeIdentity(clrType: Type): string {
        if clrType.get_IsByRef() {
            return RuntimeTypeIdentity(clrType.GetElementType()) + "&"
        }
        if clrType.get_IsPointer() {
            return RuntimeTypeIdentity(clrType.GetElementType()) + "*"
        }
        if clrType.get_IsArray() {
            if ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(clrType) {
                return RuntimeTypeIdentity(clrType.GetElementType()) + "[]"
            }
            rank := clrType.GetArrayRank()
            suffix := rank == 1 ? "[*]" : "["
            for index := 1; index < rank; index++ {
                suffix = suffix + ","
            }
            if rank > 1 {
                suffix = suffix + "]"
            }
            return RuntimeTypeIdentity(clrType.GetElementType()) + suffix
        }
        if clrType.get_IsGenericParameter() {
            if clrType.get_IsGenericMethodParameter() {
                declaringMethod := clrType.get_DeclaringMethod()
                if declaringMethod == null {
                    // GenericParameterBuilder preserves the VAR/MVAR kind and ordinal before its
                    // method is baked, but DeclaringMethod may still be unavailable. An MVAR in a
                    // MemberRef operand is contextual to the method body containing that operand,
                    // so the portable signature identity here is exactly its kind and ordinal.
                    // Request identity separately includes the constructed owner and both setter
                    // identities; two different target members therefore cannot collapse here.
                    return "!!:" + clrType.get_GenericParameterPosition().ToString()
                }
                methodOwner := declaringMethod.get_DeclaringType()
                ownerIdentity := methodOwner == null ? "" : RuntimeTypeDefinitionIdentity(methodOwner)
                methodArity := declaringMethod.get_IsGenericMethod() ? declaringMethod.GetGenericArguments().Length : 0
                return "!!" + ownerIdentity + "::" + declaringMethod.get_Name() + "`" + methodArity.ToString() + ":" + clrType.get_GenericParameterPosition().ToString()
            }
            declaringType := clrType.get_DeclaringType()
            return "!" + (declaringType == null ? "" : RuntimeTypeDefinitionIdentity(declaringType)) + ":" + clrType.get_GenericParameterPosition().ToString()
        }
        if clrType.get_IsGenericType() {
            definition := clrType.GetGenericTypeDefinition()
            text := RuntimeTypeDefinitionIdentity(definition)
            text = text + "<"
            arguments := clrType.GetGenericArguments()
            for index := 0; index < arguments.Length; index++ {
                if index > 0 {
                    text = text + ","
                }
                text = text + RuntimeTypeIdentity(arguments[index])
            }
            return text + ">"
        }
        return RuntimeTypeDefinitionIdentity(clrType)
    }

    static func RuntimeTypeDefinitionIdentity(clrType: Type): string {
        assemblyName := clrType.get_Assembly().get_FullName() ?? clrType.get_Assembly().GetName().get_Name() ?? ""
        return assemblyName + "|" + (clrType.get_FullName() ?? clrType.get_Name())
    }

    static func RuntimeMethodIdentity(method: MethodBase): string {
        identity := method.get_Name() + "|" + Convert.ToInt32(method.get_CallingConvention()).ToString()
        if method.get_IsGenericMethod() {
            identity = identity + "|g" + method.GetGenericArguments().Length.ToString()
        }
        try {
            parameters := method.GetParameters()
            identity = identity + "|p" + parameters.Length.ToString()
            for parameter in parameters {
                identity = identity + "|" + Convert.ToInt32(AnalyzerFunctionTypeFactory.GetReflectionParameterModifier(parameter)).ToString() + ":" + RuntimeTypeIdentity(parameter.get_ParameterType())
            }
        } catch {
            identity = identity + "|unbaked"
        }
        methodInfo := method as MethodInfo
        if methodInfo != null {
            try {
                identity = identity + "|r:" + RuntimeTypeIdentity(methodInfo.get_ReturnType())
            } catch {
                identity = identity + "|r:unbaked"
            }
        }
        return identity
    }

    static func Discover(image: byte[], rawIl: byte[], ledger: ColumnarModifiedMemberReferenceLedger): ColumnarModifiedMemberReferencePlan? {
        stream := new MemoryStream(image, false)
        pe := new PEReader(stream)
        reader := pe.GetMetadataReader()
        result := DiscoverFromReader(reader, image, rawIl, ledger)
        pe.Dispose()
        stream.Dispose()
        return result
    }

    private static func DiscoverFromReader(reader: MetadataReader, image: byte[], rawIl: byte[], ledger: ColumnarModifiedMemberReferenceLedger): ColumnarModifiedMemberReferencePlan? {
        entries := new List<ColumnarModifiedMemberReferencePlanEntry>()
        for request in ledger.Requests {
            sourceSignature := ResolveSourceSignature(reader, request)
            if sourceSignature == null {
                return null
            }
            modifiers := ResolveModifiers(reader, request, sourceSignature)
            if modifiers == null {
                return null
            }
            foundCount := 0
            row := 1
            while row <= reader.MemberReferences.Count {
                handle := MetadataTokens.MemberReferenceHandle(row)
                row = row + 1
                token := 0x0a000000 | (row - 1)
                reference := reader.GetMemberReference(handle)
                if reader.GetString(reference.Name) != request.Name || !EntityTypeMatchesRuntime(reader, reference.Parent, request.Owner) {
                    continue
                }
                existingSignature := reader.GetBlobBytes(reference.Signature)
                if !MemberSignatureMatchesRequest(reader, existingSignature, request) {
                    continue
                }
                candidate := new ColumnarModifiedMemberReferencePlanEntry(token, reference.Parent, request.Name, existingSignature, sourceSignature, modifiers)
                if !SignatureCanBeRepaired(reader, candidate) {
                    continue
                }
                entries.Add(candidate)
                foundCount = foundCount + 1
            }
            if foundCount == 0 {
                return null
            }
        }
        discoveryIl := new byte[](rawIl.Length)
        Array.Copy(rawIl, discoveryIl, rawIl.Length)
        fingerprint := ledger.Fingerprint()
        typeReferenceCount := reader.TypeReferences.Count
        typeSpecificationCount := reader.GetTableRowCount(TableIndex.TypeSpec)
        memberReferenceCount := reader.MemberReferences.Count
        plan := new ColumnarModifiedMemberReferencePlan(
            entries,
            fingerprint,
            image,
            discoveryIl,
            typeReferenceCount,
            typeSpecificationCount,
            memberReferenceCount
        )
        return plan
    }

    private static func SignatureCanBeRepaired(reader: MetadataReader, entry: ColumnarModifiedMemberReferencePlanEntry): bool {
        metadata := new MetadataBuilder(0, 0, 0, 0)
        let repaired: byte[] = null
        return TryRepairMethodSignature(metadata, reader, entry, out repaired)
    }

    private static func MemberSignatureMatchesRequest(reader: MetadataReader, signature: byte[], request: ColumnarModifiedMemberReferenceRequest): bool {
        if signature.Length == 0 {
            return false
        }
        header := (int)signature[0]
        hasThis := (header & 0x20) != 0
        if hasThis == request.IsStatic {
            return false
        }
        cursor := 1
        if (header & 0x10) != 0 {
            let arity: int = 0
            if !TryReadCompressed(signature, ref cursor, out arity) || arity != request.GenericArity {
                return false
            }
        } else if request.GenericArity != 0 {
            return false
        }
        let parameterCount: int = 0
        if !TryReadCompressed(signature, ref cursor, out parameterCount) || parameterCount != request.ParameterTypes.Length {
            return false
        }
        if !MemberSignatureTypeMatchesRequest(reader, signature, ref cursor, request.ReturnType, request) {
            return false
        }
        for parameterType in request.ParameterTypes {
            if cursor < signature.Length && signature[cursor] == Sentinel {
                cursor = cursor + 1
            }
            if !MemberSignatureTypeMatchesRequest(reader, signature, ref cursor, parameterType, request) {
                return false
            }
        }
        return cursor == signature.Length
    }

    private static func MemberSignatureTypeMatchesRequest(reader: MetadataReader, signature: byte[], ref cursor: int, expectedType: Type, request: ColumnarModifiedMemberReferenceRequest): bool {
        original := cursor
        if !SkipModifiers(signature, ref cursor) || cursor >= signature.Length {
            return false
        }
        code := (int)signature[cursor]
        if code == Var || code == MVar {
            cursor = cursor + 1
            let position: int = 0
            if !TryReadCompressed(signature, ref cursor, out position) {
                return false
            }
            arguments := code == Var ? request.Owner.GetGenericArguments() : request.EmittedMethod.GetGenericArguments()
            return position >= 0 && position < arguments.Length && RuntimeTypeIdentity(arguments[position]) == RuntimeTypeIdentity(expectedType)
        }
        cursor = original
        return SignatureTypeMatchesRuntime(reader, signature, ref cursor, expectedType)
    }

    static func Apply(metadata: MetadataBuilder, rawIl: byte[], ledger: ColumnarModifiedMemberReferenceLedger, plan: ColumnarModifiedMemberReferencePlan, out patchedIl: BlobBuilder): bool {
        patchedIl = null
        if ledger.Fingerprint() != plan.Fingerprint || !BytesEqual(rawIl, plan.DiscoveryIl) {
            return false
        }
        discoveryStream := new MemoryStream(plan.DiscoveryImage, false)
        discoveryPe := new PEReader(discoveryStream)
        reader := discoveryPe.GetMetadataReader()
        result := ApplyFromReader(metadata, rawIl, plan, reader, out patchedIl)
        discoveryPe.Dispose()
        discoveryStream.Dispose()
        return result
    }

    private static func ApplyFromReader(metadata: MetadataBuilder, rawIl: byte[], plan: ColumnarModifiedMemberReferencePlan, reader: MetadataReader, out patchedIl: BlobBuilder): bool {
        patchedIl = null
        if metadata.GetRowCount(TableIndex.TypeRef) != plan.TypeReferenceCount || metadata.GetRowCount(TableIndex.TypeSpec) != plan.TypeSpecificationCount || metadata.GetRowCount(TableIndex.MemberRef) != plan.MemberReferenceCount {
            return false
        }
        replacements := new Dictionary<int, int>()
        for entry in plan.Entries {
            let repairedSignature: byte[] = null
            if !TryRepairMethodSignature(metadata, reader, entry, out repairedSignature) {
                return false
            }
            nameHandle := metadata.GetOrAddString(entry.Name)
            signatureHandle := metadata.GetOrAddBlob(repairedSignature)
            metadata.AddMemberReference(entry.Parent, nameHandle, signatureHandle)
            replacementToken := 0x0a000000 | metadata.GetRowCount(TableIndex.MemberRef)
            entry.ReplacementToken = replacementToken
            entry.RepairedSignature = repairedSignature
            replacements[entry.OldToken] = replacementToken
        }
        patchedBytes := new byte[](rawIl.Length)
        Array.Copy(rawIl, patchedBytes, rawIl.Length)
        if !TryPatchMethodBodies(patchedBytes, replacements) {
            return false
        }
        patchedIl = new BlobBuilder(patchedBytes.Length)
        patchedIl.WriteBytes(patchedBytes)
        return true
    }

    // The second Reflection.Emit pass must reproduce every handle the discovery plan retained.
    // Validate the serialized image, where heap offsets and coded handles have their final meaning,
    // before the caller publishes its bytes. Original ordered rows are immutable; the only admitted
    // additions are exact modifier type references and the repaired MemberRefs planned above.
    static func ValidateFinal(image: byte[], plan: ColumnarModifiedMemberReferencePlan): bool {
        discoveryStream := new MemoryStream(plan.DiscoveryImage, false)
        finalStream := new MemoryStream(image, false)
        discoveryPe := new PEReader(discoveryStream)
        finalPe := new PEReader(finalStream)
        discovery := discoveryPe.GetMetadataReader()
        finalReader := finalPe.GetMetadataReader()
        result := ValidateFinalReaders(discovery, finalReader, plan)
        finalPe.Dispose()
        discoveryPe.Dispose()
        finalStream.Dispose()
        discoveryStream.Dispose()
        return result
    }

    private static func ValidateFinalReaders(discovery: MetadataReader, finalReader: MetadataReader, plan: ColumnarModifiedMemberReferencePlan): bool {
        if finalReader.GetTableRowCount(TableIndex.TypeSpec) != discovery.GetTableRowCount(TableIndex.TypeSpec) || finalReader.GetTableRowCount(TableIndex.MemberRef) != discovery.GetTableRowCount(TableIndex.MemberRef) + plan.Entries.Count || finalReader.GetTableRowCount(TableIndex.TypeRef) < discovery.GetTableRowCount(TableIndex.TypeRef) || finalReader.GetTableRowCount(TableIndex.AssemblyRef) < discovery.GetTableRowCount(TableIndex.AssemblyRef) || !UnchangedTableCountsMatch(discovery, finalReader) {
            return false
        }

        row := 1
        while row <= discovery.GetTableRowCount(TableIndex.AssemblyRef) {
            if !AssemblyReferenceRowsEqual(discovery, finalReader, row) {
                return false
            }
            row = row + 1
        }
        row = 1
        while row <= discovery.GetTableRowCount(TableIndex.TypeDef) {
            if !TypeDefinitionRowsEqual(discovery, finalReader, row) {
                return false
            }
            row = row + 1
        }
        row = 1
        while row <= discovery.GetTableRowCount(TableIndex.MethodDef) {
            if !MethodDefinitionRowsEqual(discovery, finalReader, row) {
                return false
            }
            row = row + 1
        }
        row = 1
        while row <= discovery.GetTableRowCount(TableIndex.TypeRef) {
            if !TypeReferenceRowsEqual(discovery, finalReader, row) {
                return false
            }
            row = row + 1
        }
        row = 1
        while row <= discovery.GetTableRowCount(TableIndex.TypeSpec) {
            first := discovery.GetTypeSpecification(MetadataTokens.TypeSpecificationHandle(row))
            second := finalReader.GetTypeSpecification(MetadataTokens.TypeSpecificationHandle(row))
            if !BytesEqual(discovery.GetBlobBytes(first.Signature), finalReader.GetBlobBytes(second.Signature)) {
                return false
            }
            row = row + 1
        }
        row = 1
        while row <= discovery.GetTableRowCount(TableIndex.MemberRef) {
            if !MemberReferenceRowsEqual(discovery, finalReader, row) {
                return false
            }
            row = row + 1
        }

        // Runtime modifier types may require new AssemblyRef/TypeRef rows. Every appended row must
        // resolve to a modifier type (or one of its enclosing types); arbitrary metadata growth is a
        // failed deterministic replay.
        row = discovery.GetTableRowCount(TableIndex.AssemblyRef) + 1
        while row <= finalReader.GetTableRowCount(TableIndex.AssemblyRef) {
            if !AssemblyReferenceMatchesAnyRuntimeModifier(finalReader, MetadataTokens.AssemblyReferenceHandle(row), plan) {
                return false
            }
            row = row + 1
        }
        row = discovery.GetTableRowCount(TableIndex.TypeRef) + 1
        while row <= finalReader.GetTableRowCount(TableIndex.TypeRef) {
            if !TypeReferenceMatchesAnyRuntimeModifier(finalReader, MetadataTokens.TypeReferenceHandle(row), plan) {
                return false
            }
            row = row + 1
        }

        for index := 0; index < plan.Entries.Count; index++ {
            entry := plan.Entries[index]
            expectedRow := discovery.GetTableRowCount(TableIndex.MemberRef) + index + 1
            if entry.ReplacementToken != (0x0a000000 | expectedRow) || entry.RepairedSignature == null {
                return false
            }
            handle := MetadataTokens.MemberReferenceHandle(expectedRow)
            reference := finalReader.GetMemberReference(handle)
            if reference.Parent != entry.Parent || finalReader.GetString(reference.Name) != entry.Name || !BytesEqual(finalReader.GetBlobBytes(reference.Signature), entry.RepairedSignature) {
                return false
            }
        }
        return true
    }

    private static func UnchangedTableCountsMatch(first: MetadataReader, second: MetadataReader): bool {
        tables := new List<TableIndex>()
        tables.Add(TableIndex.Module)
        tables.Add(TableIndex.TypeDef)
        tables.Add(TableIndex.Field)
        tables.Add(TableIndex.MethodDef)
        tables.Add(TableIndex.Param)
        tables.Add(TableIndex.InterfaceImpl)
        tables.Add(TableIndex.Constant)
        tables.Add(TableIndex.CustomAttribute)
        tables.Add(TableIndex.ClassLayout)
        tables.Add(TableIndex.FieldLayout)
        tables.Add(TableIndex.StandAloneSig)
        tables.Add(TableIndex.EventMap)
        tables.Add(TableIndex.Event)
        tables.Add(TableIndex.PropertyMap)
        tables.Add(TableIndex.Property)
        tables.Add(TableIndex.MethodSemantics)
        tables.Add(TableIndex.MethodImpl)
        tables.Add(TableIndex.ModuleRef)
        tables.Add(TableIndex.ImplMap)
        tables.Add(TableIndex.FieldRva)
        tables.Add(TableIndex.Assembly)
        tables.Add(TableIndex.File)
        tables.Add(TableIndex.ExportedType)
        tables.Add(TableIndex.ManifestResource)
        tables.Add(TableIndex.GenericParam)
        tables.Add(TableIndex.MethodSpec)
        tables.Add(TableIndex.GenericParamConstraint)
        for table in tables {
            if first.GetTableRowCount(table) != second.GetTableRowCount(table) {
                return false
            }
        }
        return true
    }

    private static func AssemblyReferenceRowsEqual(first: MetadataReader, second: MetadataReader, row: int): bool {
        left := first.GetAssemblyReference(MetadataTokens.AssemblyReferenceHandle(row))
        right := second.GetAssemblyReference(MetadataTokens.AssemblyReferenceHandle(row))
        return first.GetString(left.Name) == second.GetString(right.Name) && left.Version == right.Version && first.GetString(left.Culture) == second.GetString(right.Culture) && left.Flags == right.Flags && BytesEqual(first.GetBlobBytes(left.PublicKeyOrToken), second.GetBlobBytes(right.PublicKeyOrToken)) && BytesEqual(first.GetBlobBytes(left.HashValue), second.GetBlobBytes(right.HashValue))
    }

    private static func TypeReferenceRowsEqual(first: MetadataReader, second: MetadataReader, row: int): bool {
        left := first.GetTypeReference(MetadataTokens.TypeReferenceHandle(row))
        right := second.GetTypeReference(MetadataTokens.TypeReferenceHandle(row))
        return left.ResolutionScope == right.ResolutionScope && first.GetString(left.Namespace) == second.GetString(right.Namespace) && first.GetString(left.Name) == second.GetString(right.Name)
    }

    private static func TypeDefinitionRowsEqual(first: MetadataReader, second: MetadataReader, row: int): bool {
        left := first.GetTypeDefinition(MetadataTokens.TypeDefinitionHandle(row))
        right := second.GetTypeDefinition(MetadataTokens.TypeDefinitionHandle(row))
        if left.Attributes != right.Attributes || left.BaseType != right.BaseType || left.GetDeclaringType() != right.GetDeclaringType() || first.GetString(left.Namespace) != second.GetString(right.Namespace) || first.GetString(left.Name) != second.GetString(right.Name) {
            return false
        }
        leftFields := new List<FieldDefinitionHandle>(left.GetFields())
        rightFields := new List<FieldDefinitionHandle>(right.GetFields())
        if leftFields.Count != rightFields.Count {
            return false
        }
        for index := 0; index < leftFields.Count; index++ {
            if leftFields[index] != rightFields[index] {
                return false
            }
        }
        leftMethods := new List<MethodDefinitionHandle>(left.GetMethods())
        rightMethods := new List<MethodDefinitionHandle>(right.GetMethods())
        if leftMethods.Count != rightMethods.Count {
            return false
        }
        for index := 0; index < leftMethods.Count; index++ {
            if leftMethods[index] != rightMethods[index] {
                return false
            }
        }
        return true
    }

    private static func MethodDefinitionRowsEqual(first: MetadataReader, second: MetadataReader, row: int): bool {
        left := first.GetMethodDefinition(MetadataTokens.MethodDefinitionHandle(row))
        right := second.GetMethodDefinition(MetadataTokens.MethodDefinitionHandle(row))
        if left.Attributes != right.Attributes || left.ImplAttributes != right.ImplAttributes || left.RelativeVirtualAddress != right.RelativeVirtualAddress || first.GetString(left.Name) != second.GetString(right.Name) || !BytesEqual(first.GetBlobBytes(left.Signature), second.GetBlobBytes(right.Signature)) {
            return false
        }
        leftParameters := new List<ParameterHandle>(left.GetParameters())
        rightParameters := new List<ParameterHandle>(right.GetParameters())
        if leftParameters.Count != rightParameters.Count {
            return false
        }
        for index := 0; index < leftParameters.Count; index++ {
            if leftParameters[index] != rightParameters[index] {
                return false
            }
        }
        return true
    }

    private static func MemberReferenceRowsEqual(first: MetadataReader, second: MetadataReader, row: int): bool {
        left := first.GetMemberReference(MetadataTokens.MemberReferenceHandle(row))
        right := second.GetMemberReference(MetadataTokens.MemberReferenceHandle(row))
        return left.Parent == right.Parent && first.GetString(left.Name) == second.GetString(right.Name) && BytesEqual(first.GetBlobBytes(left.Signature), second.GetBlobBytes(right.Signature))
    }

    private static func AssemblyReferenceMatchesAnyRuntimeModifier(reader: MetadataReader, handle: AssemblyReferenceHandle, plan: ColumnarModifiedMemberReferencePlan): bool {
        for entry in plan.Entries {
            modifierTokens := new List<int>(entry.Modifiers.get_Keys())
            for modifierToken in modifierTokens {
                modifier := entry.Modifiers[modifierToken]
                runtimeType := modifier.RuntimeType
                if runtimeType != null && AssemblyReferenceMatchesRuntime(reader, handle, runtimeType.get_Assembly().GetName()) {
                    return true
                }
            }
        }
        return false
    }

    private static func TypeReferenceMatchesAnyRuntimeModifier(reader: MetadataReader, handle: TypeReferenceHandle, plan: ColumnarModifiedMemberReferencePlan): bool {
        for entry in plan.Entries {
            modifierTokens := new List<int>(entry.Modifiers.get_Keys())
            for modifierToken in modifierTokens {
                modifier := entry.Modifiers[modifierToken]
                runtimeType := modifier.RuntimeType
                while runtimeType != null {
                    if TypeReferenceMatchesRuntime(reader, handle, runtimeType) {
                        return true
                    }
                    runtimeType = runtimeType.get_DeclaringType()
                }
            }
        }
        return false
    }

    private static func BytesEqual(left: byte[], right: byte[]): bool {
        if left.Length != right.Length {
            return false
        }
        index := 0
        while index < left.Length {
            if left[index] != right[index] {
                return false
            }
            index = index + 1
        }
        return true
    }

    private static func ResolveSourceSignature(reader: MetadataReader, request: ColumnarModifiedMemberReferenceRequest): byte[]? {
        try {
            if request.SignatureMethod as MethodBuilder != null {
                token := request.SignatureMethod.get_MetadataToken()
                if (token >> 24) != 6 {
                    return null
                }
                method := reader.GetMethodDefinition(MetadataTokens.MethodDefinitionHandle(token & 0x00ffffff))
                return reader.GetBlobBytes(method.Signature)
            } else {
                return request.SignatureMethod.get_Module().ResolveSignature(request.SignatureMethod.get_MetadataToken())
            }
        } catch {
            return null
        }
    }

    private static func ResolveModifiers(reader: MetadataReader, request: ColumnarModifiedMemberReferenceRequest, signature: byte[]): Dictionary<int, ColumnarModifiedMemberReferenceModifier>? {
        names := new Dictionary<int, string>()
        cursor := 0
        if !CollectSignatureModifierTokens(signature, ref cursor, names) {
            return null
        }
        modifiers := new Dictionary<int, ColumnarModifiedMemberReferenceModifier>()
        keys := new List<int>(names.get_Keys())
        for token in keys {
            if request.SignatureMethod as MethodBuilder != null {
                handle := EntityHandleFromTypeDefOrRef(token)
                if handle.get_IsNil() || RenderEntityType(reader, handle).Length == 0 {
                    return null
                }
                modifiers[token] = new ColumnarModifiedMemberReferenceModifier(handle, null)
            } else {
                try {
                    resolved := request.SignatureMethod.get_Module().ResolveType(TypeDefOrRefMetadataToken(token))
                    modifiers[token] = new ColumnarModifiedMemberReferenceModifier(new EntityHandle(), resolved)
                } catch {
                    return null
                }
            }
        }
        return modifiers
    }

    private static func TryRepairMethodSignature(metadata: MetadataBuilder, reader: MetadataReader, entry: ColumnarModifiedMemberReferencePlanEntry, out repaired: byte[]): bool {
        repaired = null
        output := new List<byte>()
        sourceCursor := 0
        existingCursor := 0
        if !CopyMethodHeader(entry.SourceSignature, ref sourceCursor, entry.ExistingSignature, ref existingCursor, output) {
            return false
        }
        parameterCountCursor := 1
        if (entry.ExistingSignature[0] & 0x10) != 0 {
            let ignoredGenericCount: int = 0
            if !TryReadCompressed(entry.ExistingSignature, ref parameterCountCursor, out ignoredGenericCount) {
                return false
            }
        }
        let parameterCount: int = 0
        if !TryReadCompressed(entry.ExistingSignature, ref parameterCountCursor, out parameterCount) {
            return false
        }
        if !TransformType(metadata, reader, entry, ref sourceCursor, ref existingCursor, output) {
            return false
        }
        for parameter := 0; parameter < parameterCount; parameter++ {
            if sourceCursor < entry.SourceSignature.Length && entry.SourceSignature[sourceCursor] == Sentinel {
                if existingCursor >= entry.ExistingSignature.Length || entry.ExistingSignature[existingCursor] != Sentinel {
                    return false
                }
                output.Add((byte)Sentinel)
                sourceCursor = sourceCursor + 1
                existingCursor = existingCursor + 1
            }
            if !TransformType(metadata, reader, entry, ref sourceCursor, ref existingCursor, output) {
                return false
            }
        }
        if sourceCursor != entry.SourceSignature.Length || existingCursor != entry.ExistingSignature.Length {
            return false
        }
        repaired = output.ToArray()
        return true
    }

    private static func CopyMethodHeader(source: byte[], ref sourceCursor: int, existing: byte[], ref existingCursor: int, output: List<byte>): bool {
        if source.Length == 0 || existing.Length == 0 || source[0] != existing[0] {
            return false
        }
        output.Add(existing[0])
        sourceCursor = 1
        existingCursor = 1
        if (source[0] & 0x10) != 0 {
            let sourceArity: int = 0
            let existingArity: int = 0
            if !TryReadCompressed(source, ref sourceCursor, out sourceArity) || !CopyCompressed(existing, ref existingCursor, output, out existingArity) || sourceArity != existingArity {
                return false
            }
        }
        let sourceCount: int = 0
        let existingCount: int = 0
        return TryReadCompressed(source, ref sourceCursor, out sourceCount) && CopyCompressed(existing, ref existingCursor, output, out existingCount) && sourceCount == existingCount
    }

    private static func TransformType(metadata: MetadataBuilder, reader: MetadataReader, entry: ColumnarModifiedMemberReferencePlanEntry, ref source: int, ref existing: int, output: List<byte>): bool {
        if !WriteSourceModifiers(metadata, reader, entry, ref source, output) {
            return false
        }
        if !SkipModifiers(entry.ExistingSignature, ref existing) || source >= entry.SourceSignature.Length || existing >= entry.ExistingSignature.Length {
            return false
        }
        sourceCode := (int)entry.SourceSignature[source]
        existingCode := (int)entry.ExistingSignature[existing]
        source = source + 1
        if sourceCode == Var || sourceCode == MVar {
            let ignoredIndex: int = 0
            if !TryReadCompressed(entry.SourceSignature, ref source, out ignoredIndex) {
                return false
            }
            return CopyWholeType(entry.ExistingSignature, ref existing, output)
        }
        existing = existing + 1
        if sourceCode != existingCode {
            return false
        }
        output.Add((byte)existingCode)
        if sourceCode == ByRef || sourceCode == Pointer || sourceCode == SzArray || sourceCode == Pinned {
            return TransformType(metadata, reader, entry, ref source, ref existing, output)
        }
        if sourceCode == 0x11 || sourceCode == 0x12 {
            let ignoredSourceToken: int = 0
            let ignoredExistingToken: int = 0
            return TryReadCompressed(entry.SourceSignature, ref source, out ignoredSourceToken) && CopyCompressed(entry.ExistingSignature, ref existing, output, out ignoredExistingToken)
        }
        if sourceCode == GenericInstance {
            if source >= entry.SourceSignature.Length || existing >= entry.ExistingSignature.Length || entry.SourceSignature[source] != entry.ExistingSignature[existing] {
                return false
            }
            output.Add(entry.ExistingSignature[existing])
            source = source + 1
            existing = existing + 1
            let ignoredSourceToken2: int = 0
            let ignoredExistingToken2: int = 0
            if !TryReadCompressed(entry.SourceSignature, ref source, out ignoredSourceToken2) || !CopyCompressed(entry.ExistingSignature, ref existing, output, out ignoredExistingToken2) {
                return false
            }
            let sourceCount: int = 0
            let existingCount: int = 0
            if !TryReadCompressed(entry.SourceSignature, ref source, out sourceCount) || !CopyCompressed(entry.ExistingSignature, ref existing, output, out existingCount) || sourceCount != existingCount {
                return false
            }
            for index := 0; index < sourceCount; index++ {
                if !TransformType(metadata, reader, entry, ref source, ref existing, output) {
                    return false
                }
            }
            return true
        }
        if sourceCode == ArrayType {
            if !TransformType(metadata, reader, entry, ref source, ref existing, output) {
                return false
            }
            let sourceRank: int = 0
            let existingRank: int = 0
            if !TryReadCompressed(entry.SourceSignature, ref source, out sourceRank) || !CopyCompressed(entry.ExistingSignature, ref existing, output, out existingRank) || sourceRank != existingRank {
                return false
            }
            return CopyArrayShape(entry.SourceSignature, ref source, entry.ExistingSignature, ref existing, output)
        }
        if sourceCode == FunctionPointer {
            return TransformNestedMethodSignature(metadata, reader, entry, ref source, ref existing, output)
        }
        if sourceCode == Var || sourceCode == MVar {
            let ignoredSourceIndex: int = 0
            let ignoredExistingIndex: int = 0
            return TryReadCompressed(entry.SourceSignature, ref source, out ignoredSourceIndex) && CopyCompressed(entry.ExistingSignature, ref existing, output, out ignoredExistingIndex)
        }
        return true
    }

    private static func TransformNestedMethodSignature(metadata: MetadataBuilder, reader: MetadataReader, entry: ColumnarModifiedMemberReferencePlanEntry, ref source: int, ref existing: int, output: List<byte>): bool {
        // Function-pointer signatures use the same header/return/parameter grammar recursively.
        startCount := output.Count
        if !CopyMethodHeader(entry.SourceSignature, ref source, entry.ExistingSignature, ref existing, output) {
            return false
        }
        cursor := startCount + 1
        // The parameter count was already validated by CopyMethodHeader; read it from the output.
        if (output[startCount] & 0x10) != 0 {
            let ignoredArity: int = 0
            temp := cursor
            bytes := output.ToArray()
            if !TryReadCompressed(bytes, ref temp, out ignoredArity) {
                return false
            }
            cursor = temp
        }
        let count: int = 0
        bytes2 := output.ToArray()
        if !TryReadCompressed(bytes2, ref cursor, out count) || !TransformType(metadata, reader, entry, ref source, ref existing, output) {
            return false
        }
        for index := 0; index < count; index++ {
            if !TransformType(metadata, reader, entry, ref source, ref existing, output) {
                return false
            }
        }
        return true
    }

    private static func WriteSourceModifiers(metadata: MetadataBuilder, reader: MetadataReader, entry: ColumnarModifiedMemberReferencePlanEntry, ref cursor: int, output: List<byte>): bool {
        while cursor < entry.SourceSignature.Length && ((int)entry.SourceSignature[cursor] == CModRequired || (int)entry.SourceSignature[cursor] == CModOptional) {
            kind := entry.SourceSignature[cursor]
            cursor = cursor + 1
            let sourceToken: int = 0
            if !TryReadCompressed(entry.SourceSignature, ref cursor, out sourceToken) {
                return false
            }
            let modifier: ColumnarModifiedMemberReferenceModifier? = null
            if !entry.Modifiers.TryGetValue(sourceToken, out modifier) {
                return false
            }
            let modifierHandle: System.Reflection.Metadata.EntityHandle = new System.Reflection.Metadata.EntityHandle()
            if !TryGetOrAddModifierType(metadata, reader, modifier, out modifierHandle) {
                return false
            }
            output.Add(kind)
            WriteCompressed(output, TypeDefOrRefCodedIndex(modifierHandle))
        }
        return true
    }

    private static func TryGetOrAddModifierType(metadata: MetadataBuilder, reader: MetadataReader, modifier: ColumnarModifiedMemberReferenceModifier, out handle: EntityHandle): bool {
        if !modifier.DiscoveryHandle.get_IsNil() {
            handle = modifier.DiscoveryHandle
            return handle.Kind == HandleKind.TypeDefinition || handle.Kind == HandleKind.TypeReference
        }
        if modifier.RuntimeType == null {
            handle = new EntityHandle()
            return false
        }
        return TryGetOrAddRuntimeTypeReference(metadata, reader, modifier.RuntimeType, out handle)
    }

    private static func SkipModifiers(bytes: byte[], ref cursor: int): bool {
        while cursor < bytes.Length && ((int)bytes[cursor] == CModRequired || (int)bytes[cursor] == CModOptional) {
            cursor = cursor + 1
            let ignored: int = 0
            if !TryReadCompressed(bytes, ref cursor, out ignored) {
                return false
            }
        }
        return true
    }

    private static func CollectSignatureModifierTokens(bytes: byte[], ref cursor: int, names: Dictionary<int, string>): bool {
        if bytes.Length == 0 {
            return false
        }
        header := bytes[cursor]
        cursor = cursor + 1
        if (header & 0x10) != 0 {
            let genericCount: int = 0
            if !TryReadCompressed(bytes, ref cursor, out genericCount) {
                return false
            }
        }
        let parameterCount: int = 0
        if !TryReadCompressed(bytes, ref cursor, out parameterCount) || !CollectTypeModifierTokens(bytes, ref cursor, names) {
            return false
        }
        for index := 0; index < parameterCount; index++ {
            if cursor < bytes.Length && bytes[cursor] == Sentinel {
                cursor = cursor + 1
            }
            if !CollectTypeModifierTokens(bytes, ref cursor, names) {
                return false
            }
        }
        return cursor == bytes.Length
    }

    private static func CollectTypeModifierTokens(bytes: byte[], ref cursor: int, names: Dictionary<int, string>): bool {
        while cursor < bytes.Length && ((int)bytes[cursor] == CModRequired || (int)bytes[cursor] == CModOptional) {
            cursor = cursor + 1
            let token: int = 0
            if !TryReadCompressed(bytes, ref cursor, out token) {
                return false
            }
            names[token] = ""
        }
        if cursor >= bytes.Length {
            return false
        }
        code := (int)bytes[cursor]
        cursor = cursor + 1
        if code == ByRef || code == Pointer || code == SzArray || code == Pinned {
            return CollectTypeModifierTokens(bytes, ref cursor, names)
        }
        if code == 0x11 || code == 0x12 || code == Var || code == MVar {
            let ignored: int = 0
            return TryReadCompressed(bytes, ref cursor, out ignored)
        }
        if code == GenericInstance {
            if cursor >= bytes.Length {
                return false
            }
            cursor = cursor + 1
            let ignoredToken: int = 0
            let count: int = 0
            if !TryReadCompressed(bytes, ref cursor, out ignoredToken) || !TryReadCompressed(bytes, ref cursor, out count) {
                return false
            }
            for index := 0; index < count; index++ {
                if !CollectTypeModifierTokens(bytes, ref cursor, names) {
                    return false
                }
            }
        }
        return true
    }

    private static func CopyWholeType(bytes: byte[], ref cursor: int, output: List<byte>): bool {
        start := cursor
        names := new Dictionary<int, string>()
        if !CollectTypeModifierTokens(bytes, ref cursor, names) {
            return false
        }
        for index := start; index < cursor; index++ {
            output.Add(bytes[index])
        }
        return true
    }

    private static func CopyArrayShape(source: byte[], ref sourceCursor: int, existing: byte[], ref existingCursor: int, output: List<byte>): bool {
        let sourceSizes: int = 0
        let existingSizes: int = 0
        if !TryReadCompressed(source, ref sourceCursor, out sourceSizes) || !CopyCompressed(existing, ref existingCursor, output, out existingSizes) || sourceSizes != existingSizes {
            return false
        }
        for index := 0; index < sourceSizes; index++ {
            let sourceSize: int = 0
            let existingSize: int = 0
            if !TryReadCompressed(source, ref sourceCursor, out sourceSize) || !CopyCompressed(existing, ref existingCursor, output, out existingSize) || sourceSize != existingSize {
                return false
            }
        }
        let sourceBounds: int = 0
        let existingBounds: int = 0
        if !TryReadCompressed(source, ref sourceCursor, out sourceBounds) || !CopyCompressed(existing, ref existingCursor, output, out existingBounds) || sourceBounds != existingBounds {
            return false
        }
        for index := 0; index < sourceBounds; index++ {
            let sourceBound: int = 0
            let existingBound: int = 0
            if !TryReadCompressed(source, ref sourceCursor, out sourceBound) || !CopyCompressed(existing, ref existingCursor, output, out existingBound) || sourceBound != existingBound {
                return false
            }
        }
        return true
    }

    private static func TryReadCompressed(bytes: byte[], ref cursor: int, out value: int): bool {
        value = 0
        if cursor >= bytes.Length {
            return false
        }
        first := (int)bytes[cursor]
        cursor = cursor + 1
        if (first & 0x80) == 0 {
            value = first
            return true
        }
        if (first & 0xc0) == 0x80 {
            if cursor >= bytes.Length {
                return false
            }
            high := (first & 0x3f) << 8
            low := (int)bytes[cursor]
            value = high | low
            cursor = cursor + 1
            return true
        }
        if (first & 0xe0) == 0xc0 && cursor + 2 < bytes.Length {
            firstPart := (first & 0x1f) << 24
            secondByte := (int)bytes[cursor]
            thirdByte := (int)bytes[cursor + 1]
            secondPart := secondByte << 16
            thirdPart := thirdByte << 8
            fourthPart := (int)bytes[cursor + 2]
            value = firstPart | secondPart | thirdPart | fourthPart
            cursor = cursor + 3
            return true
        }
        return false
    }

    private static func CopyCompressed(bytes: byte[], ref cursor: int, output: List<byte>, out value: int): bool {
        start := cursor
        if !TryReadCompressed(bytes, ref cursor, out value) {
            return false
        }
        for index := start; index < cursor; index++ {
            output.Add(bytes[index])
        }
        return true
    }

    private static func WriteCompressed(output: List<byte>, value: int) {
        if value <= 0x7f {
            output.Add((byte)value)
        } else if value <= 0x3fff {
            output.Add((byte)((value >> 8) | 0x80))
            output.Add((byte)value)
        } else {
            output.Add((byte)((value >> 24) | 0xc0))
            output.Add((byte)(value >> 16))
            output.Add((byte)(value >> 8))
            output.Add((byte)value)
        }
    }

    private static func TypeDefOrRefMetadataToken(coded: int): int {
        tag := coded & 3
        row := coded >> 2
        if tag == 0 {
            return 0x02000000 | row
        }
        if tag == 1 {
            return 0x01000000 | row
        }
        return 0x1b000000 | row
    }

    private static func EntityHandleFromTypeDefOrRef(coded: int): EntityHandle => MetadataTokens.EntityHandle(TypeDefOrRefMetadataToken(coded))

    private static func TypeDefOrRefCodedIndex(handle: EntityHandle): int {
        token := MetadataTokens.GetToken(handle)
        row := token & 0x00ffffff
        if handle.Kind == HandleKind.TypeDefinition {
            return row << 2
        }
        if handle.Kind == HandleKind.TypeReference {
            return (row << 2) | 1
        }
        if handle.Kind == HandleKind.TypeSpecification {
            return (row << 2) | 2
        }
        return -1
    }

    private static func EntityTypeMatchesRuntime(reader: MetadataReader, handle: EntityHandle, clrType: Type): bool {
        if handle.Kind == HandleKind.TypeSpecification {
            specification := reader.GetTypeSpecification((TypeSpecificationHandle)handle)
            bytes := reader.GetBlobBytes(specification.Signature)
            cursor := 0
            return SignatureTypeMatchesRuntime(reader, bytes, ref cursor, clrType) && cursor == bytes.Length
        }
        definitionType := clrType.get_IsGenericType() ? clrType.GetGenericTypeDefinition() : clrType
        if handle.Kind == HandleKind.TypeDefinition {
            if !definitionType.get_Assembly().get_IsDynamic() {
                return false
            }
            return RenderTypeDefinition(reader, (TypeDefinitionHandle)handle) == (definitionType.get_FullName() ?? definitionType.get_Name())
        }
        if handle.Kind != HandleKind.TypeReference {
            return false
        }
        return TypeReferenceMatchesRuntime(reader, (TypeReferenceHandle)handle, definitionType)
    }

    private static func TypeReferenceMatchesRuntime(reader: MetadataReader, handle: TypeReferenceHandle, clrType: Type): bool {
        reference := reader.GetTypeReference(handle)
        if reader.GetString(reference.Name) != clrType.get_Name() {
            return false
        }
        declaringType := clrType.get_DeclaringType()
        if declaringType != null {
            return reference.ResolutionScope.Kind == HandleKind.TypeReference && TypeReferenceMatchesRuntime(reader, (TypeReferenceHandle)reference.ResolutionScope, declaringType)
        }
        if reader.GetString(reference.Namespace) != (clrType.get_Namespace() ?? "") || reference.ResolutionScope.Kind != HandleKind.AssemblyReference {
            return false
        }
        return AssemblyReferenceMatchesRuntime(reader, (AssemblyReferenceHandle)reference.ResolutionScope, clrType.get_Assembly().GetName())
    }

    private static func AssemblyReferenceMatchesRuntime(reader: MetadataReader, handle: AssemblyReferenceHandle, runtimeName: AssemblyName): bool {
        reference := reader.GetAssemblyReference(handle)
        if reader.GetString(reference.Name) != (runtimeName.get_Name() ?? "") || reference.Version != runtimeName.get_Version() {
            return false
        }
        metadataCulture := reader.GetString(reference.Culture)
        runtimeCulture := runtimeName.get_CultureName() ?? ""
        if metadataCulture != runtimeCulture {
            return false
        }
        metadataKey := reader.GetBlobBytes(reference.PublicKeyOrToken)
        referenceFlagBits := (int)reference.Flags
        hasFullPublicKey := (referenceFlagBits & 1) != 0
        runtimeKey := hasFullPublicKey ? (runtimeName.GetPublicKey() ?? new byte[](0)) : (runtimeName.GetPublicKeyToken() ?? new byte[](0))
        return BytesEqual(metadataKey, runtimeKey)
    }

    private static func SignatureTypeMatchesRuntime(reader: MetadataReader, bytes: byte[], ref cursor: int, clrType: Type): bool {
        if !SkipModifiers(bytes, ref cursor) || cursor >= bytes.Length {
            return false
        }
        code := (int)bytes[cursor]
        cursor = cursor + 1
        if code == ByRef || code == Pointer || code == SzArray {
            if code == ByRef && !clrType.get_IsByRef() {
                return false
            }
            if code == Pointer && !clrType.get_IsPointer() {
                return false
            }
            if code == SzArray && !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(clrType) {
                return false
            }
            return SignatureTypeMatchesRuntime(reader, bytes, ref cursor, clrType.GetElementType())
        }
        if code == ArrayType {
            if !clrType.get_IsArray() || ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(clrType) || !SignatureTypeMatchesRuntime(reader, bytes, ref cursor, clrType.GetElementType()) {
                return false
            }
            let rank: int = 0
            if !TryReadCompressed(bytes, ref cursor, out rank) || rank != clrType.GetArrayRank() {
                return false
            }
            return SkipArrayShape(bytes, ref cursor)
        }
        if code == Var || code == MVar {
            let position: int = 0
            if !clrType.get_IsGenericParameter() || !TryReadCompressed(bytes, ref cursor, out position) || position != clrType.get_GenericParameterPosition() {
                return false
            }
            methodOwned := clrType.get_IsGenericMethodParameter()
            typeOwned := clrType.get_IsGenericTypeParameter()
            if methodOwned == typeOwned {
                return false
            }
            return (code == MVar && methodOwned) || (code == Var && !methodOwned)
        }
        if code == 0x11 || code == 0x12 {
            let token: int = 0
            return TryReadCompressed(bytes, ref cursor, out token) && EntityTypeMatchesRuntime(reader, EntityHandleFromTypeDefOrRef(token), clrType)
        }
        if code == GenericInstance {
            if !clrType.get_IsGenericType() || cursor >= bytes.Length {
                return false
            }
            cursor = cursor + 1
            let token: int = 0
            let count: int = 0
            arguments := clrType.GetGenericArguments()
            if !TryReadCompressed(bytes, ref cursor, out token) || !EntityTypeMatchesRuntime(reader, EntityHandleFromTypeDefOrRef(token), clrType.GetGenericTypeDefinition()) || !TryReadCompressed(bytes, ref cursor, out count) || count != arguments.Length {
                return false
            }
            for index := 0; index < count; index++ {
                if !SignatureTypeMatchesRuntime(reader, bytes, ref cursor, arguments[index]) {
                    return false
                }
            }
            return true
        }
        return PrimitiveRuntimeTypeMatches(code, clrType)
    }

    private static func PrimitiveRuntimeTypeMatches(code: int, clrType: Type): bool {
        if code == 0x01 {
            return clrType.get_FullName() == "System.Void"
        }
        if code == 0x02 {
            return clrType == typeof(bool)
        }
        if code == 0x03 {
            return clrType == typeof(char)
        }
        if code == 0x04 {
            return clrType == typeof(sbyte)
        }
        if code == 0x05 {
            return clrType == typeof(byte)
        }
        if code == 0x06 {
            return clrType == typeof(short)
        }
        if code == 0x07 {
            return clrType == typeof(ushort)
        }
        if code == 0x08 {
            return clrType == typeof(int)
        }
        if code == 0x09 {
            return clrType == typeof(uint)
        }
        if code == 0x0a {
            return clrType == typeof(long)
        }
        if code == 0x0b {
            return clrType == typeof(ulong)
        }
        if code == 0x0c {
            return clrType == typeof(float)
        }
        if code == 0x0d {
            return clrType == typeof(double)
        }
        if code == 0x0e {
            return clrType == typeof(string)
        }
        if code == 0x18 {
            return clrType == typeof(IntPtr)
        }
        if code == 0x19 {
            return clrType == typeof(UIntPtr)
        }
        if code == 0x1c {
            return clrType == typeof(object)
        }
        return false
    }

    private static func SkipArrayShape(bytes: byte[], ref cursor: int): bool {
        let sizeCount: int = 0
        if !TryReadCompressed(bytes, ref cursor, out sizeCount) {
            return false
        }
        for index := 0; index < sizeCount; index++ {
            let ignoredSize: int = 0
            if !TryReadCompressed(bytes, ref cursor, out ignoredSize) {
                return false
            }
        }
        let boundCount: int = 0
        if !TryReadCompressed(bytes, ref cursor, out boundCount) {
            return false
        }
        for index := 0; index < boundCount; index++ {
            let ignoredBound: int = 0
            if !TryReadCompressed(bytes, ref cursor, out ignoredBound) {
                return false
            }
        }
        return true
    }

    private static func TryGetOrAddRuntimeTypeReference(metadata: MetadataBuilder, reader: MetadataReader, clrType: Type, out handle: EntityHandle): bool {
        definitionType := clrType.get_IsGenericType() ? clrType.GetGenericTypeDefinition() : clrType
        row := 1
        while row <= reader.TypeReferences.Count {
            candidate := MetadataTokens.TypeReferenceHandle(row)
            row = row + 1
            if TypeReferenceMatchesRuntime(reader, candidate, definitionType) {
                handle = candidate
                return true
            }
        }
        let scope: System.Reflection.Metadata.EntityHandle = new System.Reflection.Metadata.EntityHandle()
        declaringType := definitionType.get_DeclaringType()
        if declaringType != null {
            if !TryGetOrAddRuntimeTypeReference(metadata, reader, declaringType, out scope) {
                handle = new EntityHandle()
                return false
            }
        } else {
            runtimeAssembly := definitionType.get_Assembly().GetName()
            assemblyRow := 1
            while assemblyRow <= reader.AssemblyReferences.Count {
                assemblyHandle := MetadataTokens.AssemblyReferenceHandle(assemblyRow)
                assemblyRow = assemblyRow + 1
                if AssemblyReferenceMatchesRuntime(reader, assemblyHandle, runtimeAssembly) {
                    scope = assemblyHandle
                    break
                }
            }
            if scope.get_IsNil() {
                runtimeName := runtimeAssembly.get_Name() ?? ""
                runtimeCulture := runtimeAssembly.get_CultureName() ?? ""
                runtimeKey := runtimeAssembly.GetPublicKeyToken() ?? new byte[](0)
                runtimeVersion := runtimeAssembly.get_Version() ?? new Version(0, 0, 0, 0)
                runtimeFlagBits := (int)runtimeAssembly.get_Flags()
                if (runtimeFlagBits & 1) != 0 {
                    runtimeFlagBits = runtimeFlagBits - 1
                }
                runtimeFlags := (AssemblyFlags)runtimeFlagBits
                nameHandle := metadata.GetOrAddString(runtimeName)
                cultureHandle := metadata.GetOrAddString(runtimeCulture)
                keyHandle := metadata.GetOrAddBlob(runtimeKey)
                addedAssembly := metadata.AddAssemblyReference(nameHandle, runtimeVersion, cultureHandle, keyHandle, runtimeFlags, new BlobHandle())
                scope = addedAssembly
            }
        }
        namespaceText := declaringType == null ? (definitionType.get_Namespace() ?? "") : ""
        namespaceHandle := metadata.GetOrAddString(namespaceText)
        nameHandle2 := metadata.GetOrAddString(definitionType.get_Name())
        addedType := metadata.AddTypeReference(scope, namespaceHandle, nameHandle2)
        handle = addedType
        return true
    }

    private static func RenderEntityType(reader: MetadataReader, handle: EntityHandle): string {
        if handle.Kind == HandleKind.TypeDefinition {
            return RenderTypeDefinition(reader, (TypeDefinitionHandle)handle)
        }
        if handle.Kind == HandleKind.TypeReference {
            return RenderTypeReference(reader, (TypeReferenceHandle)handle)
        }
        if handle.Kind == HandleKind.TypeSpecification {
            specification := reader.GetTypeSpecification((TypeSpecificationHandle)handle)
            bytes := reader.GetBlobBytes(specification.Signature)
            cursor := 0
            let rendered: string = null
            if TryRenderSignatureType(reader, bytes, ref cursor, out rendered) && cursor == bytes.Length {
                return rendered
            }
        }
        return ""
    }

    private static func RenderTypeDefinition(reader: MetadataReader, handle: TypeDefinitionHandle): string {
        definition := reader.GetTypeDefinition(handle)
        name := reader.GetString(definition.Name)
        declaring := definition.GetDeclaringType()
        if !declaring.get_IsNil() {
            return RenderTypeDefinition(reader, declaring) + "+" + name
        }
        ns := reader.GetString(definition.Namespace)
        return ns.Length == 0 ? name : ns + "." + name
    }

    private static func RenderTypeReference(reader: MetadataReader, handle: TypeReferenceHandle): string {
        reference := reader.GetTypeReference(handle)
        ns := reader.GetString(reference.Namespace)
        name := reader.GetString(reference.Name)
        return ns.Length == 0 ? name : ns + "." + name
    }

    private static func TryRenderSignatureType(reader: MetadataReader, bytes: byte[], ref cursor: int, out rendered: string): bool {
        rendered = ""
        if !SkipModifiers(bytes, ref cursor) || cursor >= bytes.Length {
            return false
        }
        code := (int)bytes[cursor]
        cursor = cursor + 1
        if code == 0x11 || code == 0x12 {
            let token: int = 0
            if !TryReadCompressed(bytes, ref cursor, out token) {
                return false
            }
            rendered = RenderEntityType(reader, EntityHandleFromTypeDefOrRef(token))
            return rendered.Length > 0
        }
        if code == GenericInstance {
            if cursor >= bytes.Length {
                return false
            }
            cursor = cursor + 1
            let token: int = 0
            let count: int = 0
            if !TryReadCompressed(bytes, ref cursor, out token) || !TryReadCompressed(bytes, ref cursor, out count) {
                return false
            }
            rendered = RenderEntityType(reader, EntityHandleFromTypeDefOrRef(token)) + "<"
            for index := 0; index < count; index++ {
                let argument: string = null
                if !TryRenderSignatureType(reader, bytes, ref cursor, out argument) {
                    return false
                }
                if index > 0 {
                    rendered = rendered + ","
                }
                rendered = rendered + argument
            }
            rendered = rendered + ">"
            return true
        }
        rendered = PrimitiveIdentity(code)
        return rendered.Length > 0
    }

    private static func PrimitiveIdentity(code: int): string {
        if code == 0x02 {
            return "System.Boolean"
        }
        if code == 0x03 {
            return "System.Char"
        }
        if code == 0x04 {
            return "System.SByte"
        }
        if code == 0x05 {
            return "System.Byte"
        }
        if code == 0x06 {
            return "System.Int16"
        }
        if code == 0x07 {
            return "System.UInt16"
        }
        if code == 0x08 {
            return "System.Int32"
        }
        if code == 0x09 {
            return "System.UInt32"
        }
        if code == 0x0a {
            return "System.Int64"
        }
        if code == 0x0b {
            return "System.UInt64"
        }
        if code == 0x0c {
            return "System.Single"
        }
        if code == 0x0d {
            return "System.Double"
        }
        if code == 0x0e {
            return "System.String"
        }
        if code == 0x18 {
            return "System.IntPtr"
        }
        if code == 0x19 {
            return "System.UIntPtr"
        }
        if code == 0x1c {
            return "System.Object"
        }
        return ""
    }

    private static func TryPatchMethodBodies(bytes: byte[], replacements: Dictionary<int, int>): bool {
        offset := 0
        while offset < bytes.Length {
            while offset < bytes.Length && bytes[offset] == 0 {
                offset = offset + 1
            }
            if offset >= bytes.Length {
                break
            }
            header := (int)bytes[offset]
            codeStart := 0
            codeSize := 0
            moreSections := false
            if (header & 3) == 2 {
                codeStart = offset + 1
                codeSize = header >> 2
            } else if (header & 3) == 3 {
                if offset + 11 >= bytes.Length {
                    return false
                }
                flagsAndSize := ReadUInt16(bytes, offset)
                headerSize := ((flagsAndSize >> 12) & 15) * 4
                if headerSize < 12 || offset + headerSize > bytes.Length {
                    return false
                }
                codeStart = offset + headerSize
                codeSize = ReadInt32(bytes, offset + 4)
                moreSections = (flagsAndSize & 8) != 0
            } else {
                return false
            }
            codeEnd := codeStart + codeSize
            if codeSize < 0 || codeEnd > bytes.Length || !PatchInstructions(bytes, codeStart, codeEnd, replacements) {
                return false
            }
            offset = codeEnd
            if moreSections {
                offset = (offset + 3) & ~3
                sectionMore := true
                while sectionMore {
                    if offset + 3 >= bytes.Length {
                        return false
                    }
                    sectionKind := (int)bytes[offset]
                    sectionMore = (sectionKind & 0x80) != 0
                    fat := (sectionKind & 0x40) != 0
                    size := (int)bytes[offset + 1]
                    if fat {
                        middleByte := (int)bytes[offset + 2]
                        highByte := (int)bytes[offset + 3]
                        size = size | (middleByte << 8) | (highByte << 16)
                    }
                    if size < 4 || offset + size > bytes.Length {
                        return false
                    }
                    offset = (offset + size + 3) & ~3
                }
            }
        }
        return true
    }

    // A narrow test seam for the structural IL walker. Production reaches the same owner through
    // Apply; tests feed complete raw method-body blobs so constants, prefixes, switches, and bounds
    // cannot be mistaken for InlineMethod operands.
    static func TryPatchMethodBodiesForTests(bytes: byte[], replacements: Dictionary<int, int>): bool => TryPatchMethodBodies(bytes, replacements)

    private static func PatchInstructions(bytes: byte[], start: int, end: int, replacements: Dictionary<int, int>): bool {
        cursor := start
        while cursor < end {
            opcode := (int)bytes[cursor]
            cursor = cursor + 1
            if opcode == 0xfe {
                if cursor >= end {
                    return false
                }
                secondOpcodeByte := (int)bytes[cursor]
                opcode = 0xfe00 | secondOpcodeByte
                cursor = cursor + 1
            }
            size := OperandSize(opcode, bytes, cursor, end)
            if size < 0 || cursor + size > end {
                return false
            }
            if IsMethodOperand(opcode) {
                oldToken := ReadInt32(bytes, cursor)
                let newToken: int = 0
                if replacements.TryGetValue(oldToken, out newToken) {
                    WriteInt32(bytes, cursor, newToken)
                }
            }
            cursor = cursor + size
        }
        return cursor == end
    }

    private static func IsMethodOperand(opcode: int): bool {
        return opcode == 0x27 || opcode == 0x28 || opcode == 0x6f || opcode == 0x73 || opcode == 0xfe06 || opcode == 0xfe07
    }

    // Every operand-bearing ECMA-335 opcode. Anything absent has InlineNone. Keeping this as widths
    // rather than an opcode allowlist is what lets the body walk remain structural: it crosses every
    // valid instruction and only treats the six InlineMethod forms above as patchable tokens.
    private static func OperandSize(opcode: int, bytes: byte[], cursor: int, end: int): int {
        if opcode < 0 || opcode > 0xffff || !Enum.IsDefined<ILOpCode>((ILOpCode)opcode) {
            return -1
        }
        if (opcode >= 0x0e && opcode <= 0x13) || opcode == 0x1f || (opcode >= 0x2b && opcode <= 0x37) || opcode == 0xde || opcode == 0xfe12 || opcode == 0xfe19 {
            return 1
        }
        if opcode >= 0xfe09 && opcode <= 0xfe0e {
            return 2
        }
        if opcode == 0x21 || opcode == 0x23 {
            return 8
        }
        if opcode == 0x45 {
            if cursor + 4 > end {
                return -1
            }
            count := ReadInt32(bytes, cursor)
            if count < 0 || count > (end - cursor - 4) / 4 {
                return -1
            }
            return 4 + (count * 4)
        }
        if opcode == 0x20 || opcode == 0x22 || (opcode >= 0x27 && opcode <= 0x29) || (opcode >= 0x38 && opcode <= 0x44) || (opcode >= 0x6f && opcode <= 0x75) || opcode == 0x79 || (opcode >= 0x7b && opcode <= 0x81) || opcode == 0x8c || opcode == 0x8d || opcode == 0x8f || (opcode >= 0xa3 && opcode <= 0xa5) || opcode == 0xc2 || opcode == 0xc6 || opcode == 0xd0 || opcode == 0xdd || opcode == 0xfe06 || opcode == 0xfe07 || opcode == 0xfe15 || opcode == 0xfe16 || opcode == 0xfe1c {
            return 4
        }
        return 0
    }

    private static func ReadUInt16(bytes: byte[], offset: int): int {
        low := (int)bytes[offset]
        high := (int)bytes[offset + 1]
        high = high << 8
        return low | high
    }

    private static func ReadInt32(bytes: byte[], offset: int): int {
        first := (int)bytes[offset]
        second := (int)bytes[offset + 1]
        second = second << 8
        third := (int)bytes[offset + 2]
        third = third << 16
        fourth := (int)bytes[offset + 3]
        fourth = fourth << 24
        return first | second | third | fourth
    }
    private static func WriteInt32(bytes: byte[], offset: int, value: int) {
        bytes[offset] = (byte)value
        bytes[offset + 1] = (byte)(value >> 8)
        bytes[offset + 2] = (byte)(value >> 16)
        bytes[offset + 3] = (byte)(value >> 24)
    }
}
