namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

// Ordinary source-interface target discovery deliberately uses the live CLR Type equality policy
// that the declaration host used: own declaration first, then interface bases in list-order depth
// first, and only the first declaration retained in Methods for a name. Structural references record
// the selected member after that policy succeeds; they do not participate in candidate matching.
enum ColumnarSourceInterfaceMethodDefinitionFamily {
    InstanceDefinition = 0
}

class ColumnarSourceInterfaceMethodParameterDescriptor {
    readonly typeValue: ColumnarSelectedTypeReference
    readonly runtimeTypeValue: Type
    readonly modifierKindValue: int

    Type: ColumnarSelectedTypeReference => typeValue
    RuntimeType: Type => runtimeTypeValue
    ModifierKind: int => modifierKindValue

    constructor(selectedType: ColumnarSelectedTypeReference, runtimeType: Type, modifierKind: int) {
        if selectedType == null || runtimeType == null {
            throw new InvalidOperationException("A source-interface method parameter requires structural type identity.")
        }
        typeValue = selectedType
        runtimeTypeValue = runtimeType
        modifierKindValue = modifierKind
    }
}

// Immutable identity for one source-interface method definition. The declaring source type and
// every signature type are selected in the current emission table from the authoritative source
// registry facts. The arrays are copied and the unbaked MethodBuilder is never reflected here.
class ColumnarSourceInterfaceMethodDescriptor {
    readonly tableValue: ColumnarStructuralTypeReferenceTable
    readonly declaringTypeValue: ColumnarSelectedTypeReference
    readonly declaringRuntimeTypeValue: Type
    readonly memberNameValue: string
    readonly returnTypeValue: ColumnarSelectedTypeReference
    readonly returnRuntimeTypeValue: Type
    readonly parametersValue: IReadOnlyList<object>
    readonly parameterCountValue: int
    readonly parameterModifierCountValue: int

    StructuralTypeReferences: ColumnarStructuralTypeReferenceTable => tableValue
    DeclaringType: ColumnarSelectedTypeReference => declaringTypeValue
    MemberName: string => memberNameValue
    DefinitionFamily: ColumnarSourceInterfaceMethodDefinitionFamily => ColumnarSourceInterfaceMethodDefinitionFamily.InstanceDefinition
    MethodGenericArity: int => 0
    ReturnType: ColumnarSelectedTypeReference => returnTypeValue
    ParameterCount: int => parameterCountValue
    ParameterModifierCount: int => parameterModifierCountValue

    constructor(
        owner: ColumnarStructDef,
        memberName: string,
        definition: ColumnarInstanceMethodDef,
        table: ColumnarStructuralTypeReferenceTable
    ) {
        if owner == null || memberName == null || memberName.Length == 0 || definition == null || table == null {
            throw new InvalidOperationException("A source-interface member descriptor requires its found declaration and emission table.")
        }
        if definition.ParamTypes == null || definition.ParamModifierKinds == null || definition.ReturnType == null {
            throw new InvalidOperationException("A source-interface member descriptor requires complete source signature facts.")
        }
        if definition.ParamModifierKinds.Length != 0 && definition.ParamModifierKinds.Length != definition.ParamTypes.Length {
            throw new InvalidOperationException("Source-interface member modifier facts must be empty or match the parameter count.")
        }
        registered: ColumnarInstanceMethodDef = null
        if !owner.Methods.TryGetValue(memberName, out registered) || !Object.ReferenceEquals(registered, definition) {
            throw new InvalidOperationException("A source-interface member descriptor must bind the owner's authoritative Methods row.")
        }

        tableValue = table
        declaringTypeValue = table.SelectSourceDefinition(owner.DeclaredTypeName, owner.Builder)
        declaringRuntimeTypeValue = owner.Builder
        memberNameValue = memberName
        returnTypeValue = table.SelectRuntimeType(definition.ReturnType)
        returnRuntimeTypeValue = definition.ReturnType
        parameterCopy := new List<object>()
        index := 0
        while index < definition.ParamTypes.Length {
            modifierKind := 0
            if definition.ParamModifierKinds.Length > 0 {
                modifierKind = definition.ParamModifierKinds[index]
            }
            parameterCopy.Add(new ColumnarSourceInterfaceMethodParameterDescriptor(
                table.SelectRuntimeType(definition.ParamTypes[index]),
                definition.ParamTypes[index],
                modifierKind
            ))
            index += 1
        }
        parametersValue = parameterCopy.AsReadOnly()
        parameterCountValue = definition.ParamTypes.Length
        parameterModifierCountValue = definition.ParamModifierKinds.Length
    }

    func ParameterType(index: int): ColumnarSelectedTypeReference {
        return Parameter(index).Type
    }

    func ParameterModifierKind(index: int): int {
        return Parameter(index).ModifierKind
    }

    func Parameter(index: int): ColumnarSourceInterfaceMethodParameterDescriptor {
        parameter := parametersValue.get_Item(index) as ColumnarSourceInterfaceMethodParameterDescriptor
        if parameter == null {
            throw new InvalidOperationException("Source-interface parameter storage is invalid.")
        }
        return parameter
    }

    func Validate(expectedTable: ColumnarStructuralTypeReferenceTable): bool {
        if expectedTable == null || !Object.ReferenceEquals(tableValue, expectedTable) {
            return false
        }
        if !expectedTable.ValidatePair(declaringTypeValue, declaringRuntimeTypeValue) || !expectedTable.ValidatePair(returnTypeValue, returnRuntimeTypeValue) {
            return false
        }
        index := 0
        while index < parameterCountValue {
            parameter := Parameter(index)
            selected := parameter.Type
            if selected == null || !expectedTable.ValidatePair(selected, parameter.RuntimeType) {
                return false
            }
            index += 1
        }
        return parameterModifierCountValue == 0 || parameterModifierCountValue == parameterCountValue
    }
}

// The executable companion and descriptor are captured together from one successful source row.
// Callers cannot supply an independent descriptor/handle pair. Validation receives the consuming
// emission table so a completion retained from another emission cannot attach metadata here.
class ColumnarSourceInterfaceMethodBinding {
    readonly descriptorValue: ColumnarSourceInterfaceMethodDescriptor
    readonly targetValue: MethodBuilder

    Descriptor: ColumnarSourceInterfaceMethodDescriptor => descriptorValue
    Target: MethodInfo => targetValue

    constructor(
        owner: ColumnarStructDef,
        memberName: string,
        definition: ColumnarInstanceMethodDef,
        table: ColumnarStructuralTypeReferenceTable
    ) {
        if definition == null || definition.Builder == null {
            throw new InvalidOperationException("A source-interface member binding requires its original method builder.")
        }
        targetValue = definition.Builder
        descriptorValue = new ColumnarSourceInterfaceMethodDescriptor(owner, memberName, definition, table)
    }

    func ValidatedTarget(expectedTable: ColumnarStructuralTypeReferenceTable): MethodInfo {
        if expectedTable == null || !descriptorValue.Validate(expectedTable) {
            throw new InvalidOperationException("A source-interface member binding does not belong to the consuming emission.")
        }
        return targetValue
    }
}

class ColumnarSourceInterfaceMethodResolver {
    static func TryFind(
        interfaceDefinition: ColumnarStructDef,
        memberName: string,
        returnType: Type,
        parameterTypes: Type[],
        table: ColumnarStructuralTypeReferenceTable,
        out binding: ColumnarSourceInterfaceMethodBinding?
    ): bool {
        binding = null
        own: ColumnarInstanceMethodDef = null
        if interfaceDefinition.Methods.TryGetValue(memberName, out own) {
            if own == null {
                throw new InvalidOperationException("A source-interface Methods row cannot be null.")
            }
            if own.ReturnType == returnType && ParameterTypesMatch(own.ParamTypes, parameterTypes) {
                binding = new ColumnarSourceInterfaceMethodBinding(interfaceDefinition, memberName, own, table)
                return true
            }
        }

        for baseDefinition in interfaceDefinition.InterfaceBases {
            if TryFind(baseDefinition, memberName, returnType, parameterTypes, table, out binding) {
                return true
            }
        }
        return false
    }

    static func ParameterTypesMatch(left: Type[], right: Type[]): bool {
        if left.Length != right.Length {
            return false
        }
        index := 0
        while index < left.Length {
            if left[index] != right[index] {
                return false
            }
            index += 1
        }
        return true
    }
}
