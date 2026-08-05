namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic

class CompilationUnitFacts {
    static func ContainsSoaRecordDeclaration(compilationUnit: object): bool {
        declarations := GetRequiredListProperty(compilationUnit, "Declarations")
        return ContainsSoaRecordDeclarationInList(declarations)
    }

    static func RequiresColumnarSoaEmission(soaFeatureEnabled: bool, compilationUnits: IEnumerable<object>): bool {
        if !soaFeatureEnabled {
            return false
        }

        for compilationUnit in compilationUnits {
            if compilationUnit != null && ContainsSoaRecordDeclaration(compilationUnit) {
                return true
            }
        }

        return false
    }

    static func ContainsSoaRecordDeclarationInList(declarations: IList): bool {
        index := 0
        while index < declarations.Count {
            declaration := declarations[index]
            if declaration != null && ContainsSoaRecordDeclarationInDeclaration(declaration) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func ContainsSoaRecordDeclarationInDeclaration(declaration: object): bool {
        typeName := declaration.GetType().Name

        if typeName == "SoaRecordDeclaration" {
            return true
        }

        if IsMemberOwningDeclaration(typeName) {
            members := GetRequiredListProperty(declaration, "Members")
            return ContainsSoaRecordDeclarationInList(members)
        }

        return false
    }

    static func IsMemberOwningDeclaration(typeName: string): bool {
        return typeName == "ClassDeclaration" || typeName == "StructDeclaration" || typeName == "RecordDeclaration" || typeName == "InterfaceDeclaration"
    }

    static func GetRequiredListProperty(owner: object, propertyName: string): IList {
        value := GetMemberValue(owner, propertyName)
        if value == null {
            throw new InvalidOperationException("CompilationUnitFacts expected '" + owner.GetType().Name + "." + propertyName + "' to exist.")
        }

        list := value as IList
        if list == null {
            throw new InvalidOperationException("CompilationUnitFacts expected '" + owner.GetType().Name + "." + propertyName + "' to contain a list.")
        }

        return list
    }

    // AST nodes are authored as N# classes, which emit their members as fields; older C# records
    // exposed them as properties. Read either shape so the reflection facts survive both.
    static func GetMemberValue(owner: object, propertyName: string): object? {
        property := owner.GetType().GetProperty(propertyName)
        if property != null {
            return property.GetValue(owner)
        }

        field := owner.GetType().GetField(propertyName)
        if field != null {
            return field.GetValue(owner)
        }

        return null
    }
}
