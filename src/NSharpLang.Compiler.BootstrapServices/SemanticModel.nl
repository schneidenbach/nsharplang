namespace NSharpLang.Compiler

import System.Collections.Generic

public class ScopeInfo {
    idValue: int
    parentIdValue: int
    startLineValue: int
    startColumnValue: int
    endLineValue: int
    endColumnValue: int
    variablesValue: Dictionary<string, TypeInfo>
    functionsValue: Dictionary<string, TypeInfo>

    Id: int => idValue
    ParentId: int => parentIdValue
    StartLine: int => startLineValue
    StartColumn: int => startColumnValue
    EndLine: int => endLineValue
    EndColumn: int => endColumnValue
    Variables: Dictionary<string, TypeInfo> => variablesValue
    Functions: Dictionary<string, TypeInfo> => functionsValue

    constructor(id: int, parentId: int, startLine: int, startColumn: int) {
        idValue = id
        parentIdValue = parentId
        startLineValue = startLine
        startColumnValue = startColumn
        endLineValue = 0
        endColumnValue = 0
        variablesValue = new Dictionary<string, TypeInfo>()
        functionsValue = new Dictionary<string, TypeInfo>()
    }

    public func SetEndPosition(endLine: int, endColumn: int) {
        endLineValue = endLine
        endColumnValue = endColumn
    }

    public func ContainsPosition(line: int, column: int): bool {
        if endLineValue == 0 {
            return false
        }

        if line < startLineValue || line > endLineValue {
            return false
        }

        if line == startLineValue && column < startColumnValue {
            return false
        }

        if line == endLineValue && column > endColumnValue {
            return false
        }

        return true
    }
}

public class SemanticModel {
    scopesValue: List<ScopeInfo>
    expressionTypesValue: Dictionary<(Line: int, Column: int), TypeInfo>
    expressionNullStatesValue: Dictionary<(Line: int, Column: int), NullState>
    typeReferenceTypesValue: Dictionary<(Line: int, Column: int), TypeInfo>
    variablesValue: Dictionary<string, TypeInfo>
    functionsValue: Dictionary<string, TypeInfo>
    propertiesValue: Dictionary<string, TypeInfo>
    fieldsValue: Dictionary<string, TypeInfo>
    typesValue: Dictionary<string, TypeInfo>
    typeMembersValue: Dictionary<string, Dictionary<string, TypeInfo>>
    scopeVersionValue: int

    ExpressionTypes: Dictionary<(Line: int, Column: int), TypeInfo> => expressionTypesValue
    ExpressionNullStates: Dictionary<(Line: int, Column: int), NullState> => expressionNullStatesValue
    TypeReferenceTypes: Dictionary<(Line: int, Column: int), TypeInfo> => typeReferenceTypesValue
    Variables: Dictionary<string, TypeInfo> => variablesValue
    Functions: Dictionary<string, TypeInfo> => functionsValue
    Properties: Dictionary<string, TypeInfo> => propertiesValue
    Fields: Dictionary<string, TypeInfo> => fieldsValue
    Types: Dictionary<string, TypeInfo> => typesValue
    TypeMembers: Dictionary<string, Dictionary<string, TypeInfo>> => typeMembersValue
    Scopes: IReadOnlyList<ScopeInfo> => scopesValue
    ScopeVersion: int => scopeVersionValue

    constructor() {
        scopesValue = new List<ScopeInfo>()
        expressionTypesValue = new Dictionary<(Line: int, Column: int), TypeInfo>()
        expressionNullStatesValue = new Dictionary<(Line: int, Column: int), NullState>()
        typeReferenceTypesValue = new Dictionary<(Line: int, Column: int), TypeInfo>()
        variablesValue = new Dictionary<string, TypeInfo>()
        functionsValue = new Dictionary<string, TypeInfo>()
        propertiesValue = new Dictionary<string, TypeInfo>()
        fieldsValue = new Dictionary<string, TypeInfo>()
        typesValue = new Dictionary<string, TypeInfo>()
        typeMembersValue = new Dictionary<string, Dictionary<string, TypeInfo>>()
        scopeVersionValue = 0
    }

    public func OpenScope(parentId: int, startLine: int, startColumn: int): int {
        id := scopesValue.Count
        scopesValue.Add(new ScopeInfo(id, parentId, startLine, startColumn))
        scopeVersionValue = scopeVersionValue + 1
        return id
    }

    public func CloseScope(scopeId: int, endLine: int, endColumn: int) {
        if scopeId >= 0 && scopeId < scopesValue.Count {
            scopesValue[scopeId].SetEndPosition(endLine, endColumn)
            scopeVersionValue = scopeVersionValue + 1
        }
    }

    public func RecordScopedVariable(scopeId: int, name: string, typeInfo: TypeInfo) {
        if scopeId >= 0 && scopeId < scopesValue.Count {
            scopesValue[scopeId].Variables[name] = typeInfo
            scopeVersionValue = scopeVersionValue + 1
        }

        variablesValue[name] = typeInfo
    }

    public func RecordScopedFunction(scopeId: int, name: string, typeInfo: TypeInfo) {
        if scopeId >= 0 && scopeId < scopesValue.Count {
            scopesValue[scopeId].Functions[name] = typeInfo
            scopeVersionValue = scopeVersionValue + 1
        }

        functionsValue[name] = typeInfo
    }

    public func RecordVariable(name: string, typeInfo: TypeInfo) {
        variablesValue[name] = typeInfo
    }

    public func RecordFunction(name: string, typeInfo: TypeInfo) {
        functionsValue[name] = typeInfo
    }

    public func RecordProperty(name: string, typeInfo: TypeInfo) {
        propertiesValue[name] = typeInfo
    }

    public func RecordField(name: string, typeInfo: TypeInfo) {
        fieldsValue[name] = typeInfo
    }

    public func RecordType(name: string, typeInfo: TypeInfo) {
        typesValue[name] = typeInfo
    }

    public func RecordTypeMember(typeName: string, memberName: string, memberType: TypeInfo) {
        members := new Dictionary<string, TypeInfo>()
        if typeMembersValue.TryGetValue(typeName, out members) {
            members[memberName] = memberType
            return
        }

        members = new Dictionary<string, TypeInfo>()
        typeMembersValue[typeName] = members
        members[memberName] = memberType
    }

    public func GetTypeMembers(typeName: string): Dictionary<string, TypeInfo>? {
        members := new Dictionary<string, TypeInfo>()
        if typeMembersValue.TryGetValue(typeName, out members) {
            return members
        }

        return null
    }

    public func RecordExpressionType(line: int, column: int, typeInfo: TypeInfo) {
        expressionTypesValue[(Line: line, Column: column)] = typeInfo
    }

    public func RecordExpressionNullState(line: int, column: int, state: NullState) {
        expressionNullStatesValue[(Line: line, Column: column)] = state
    }

    public func RecordTypeReference(line: int, column: int, typeInfo: TypeInfo) {
        if line <= 0 || column <= 0 {
            return
        }

        typeReferenceTypesValue[(Line: line, Column: column)] = typeInfo
    }

    public func LookupIdentifier(name: string): TypeInfo? {
        value := new TypeInfo()

        if variablesValue.TryGetValue(name, out value) {
            return value
        }

        if propertiesValue.TryGetValue(name, out value) {
            return value
        }

        if fieldsValue.TryGetValue(name, out value) {
            return value
        }

        if functionsValue.TryGetValue(name, out value) {
            return GetFunctionLookupType(value)
        }

        if typesValue.TryGetValue(name, out value) {
            return value
        }

        return null
    }

    public func LookupIdentifierAtPosition(name: string, line: int, column: int): TypeInfo? {
        best: TypeInfo? = null
        bestDepth := -1

        i := 0
        while i < scopesValue.Count {
            scope := scopesValue[i]
            if scope.ContainsPosition(line, column) {
                depth := GetScopeDepth(scope.Id)
                if depth > bestDepth {
                    value := new TypeInfo()
                    if scope.Variables.TryGetValue(name, out value) {
                        best = value
                        bestDepth = depth
                    } else if scope.Functions.TryGetValue(name, out value) {
                        best = GetFunctionLookupType(value)
                        bestDepth = depth
                    }
                }
            }

            i = i + 1
        }

        return best
    }

    static func GetFunctionLookupType(typeInfo: TypeInfo): TypeInfo {
        function := typeInfo as FunctionTypeInfo
        if function != null && function.ReturnType != null {
            return function.ReturnType
        }

        return typeInfo
    }

    public func GetVisibleVariablesAtPosition(line: int, column: int): Dictionary<string, TypeInfo> {
        result := new Dictionary<string, TypeInfo>()

        i := scopesValue.Count - 1
        while i >= 0 {
            scope := scopesValue[i]
            if scope.ContainsPosition(line, column) {
                foreach entry in scope.Variables {
                    if !result.ContainsKey(entry.Key) {
                        result[entry.Key] = entry.Value
                    }
                }

                foreach entry in scope.Functions {
                    if !result.ContainsKey(entry.Key) {
                        result[entry.Key] = entry.Value
                    }
                }
            }

            i = i - 1
        }

        return result
    }

    public func LookupTypeAtPosition(line: int, column: int): TypeInfo? {
        value := new TypeInfo()
        if expressionTypesValue.TryGetValue((Line: line, Column: column), out value) {
            return value
        }

        return null
    }

    public func LookupTypeReferenceAtPosition(line: int, column: int): TypeInfo? {
        value := new TypeInfo()
        if typeReferenceTypesValue.TryGetValue((Line: line, Column: column), out value) {
            return value
        }

        return null
    }

    func GetScopeDepth(scopeId: int): int {
        depth := 0
        current := scopeId

        while current >= 0 && current < scopesValue.Count {
            parentId := scopesValue[current].ParentId
            if parentId < 0 || parentId == current {
                return depth
            }

            depth = depth + 1
            current = parentId
        }

        return depth
    }
}
