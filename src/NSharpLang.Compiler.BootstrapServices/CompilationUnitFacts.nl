namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic

public class CompilationUnitFacts {
    public static func ContainsSoaRecordDeclaration(compilationUnit: object): bool {
        declarations := GetRequiredListProperty(compilationUnit, "Declarations")
        return ContainsSoaRecordDeclarationInList(declarations)
    }

    public static func RequiresColumnarSoaEmission(
        soaFeatureEnabled: bool,
        compilationUnits: IEnumerable<object>): bool {
        if !soaFeatureEnabled {
            return false
        }

        foreach compilationUnit in compilationUnits {
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
        return typeName == "ClassDeclaration"
            || typeName == "StructDeclaration"
            || typeName == "RecordDeclaration"
            || typeName == "InterfaceDeclaration"
    }

    static func GetRequiredListProperty(owner: object, propertyName: string): IList {
        property := owner.GetType().GetProperty(propertyName)
        if property == null {
            throw new InvalidOperationException(
                "CompilationUnitFacts expected '" + owner.GetType().Name + "." + propertyName + "' to exist.")
        }

        value := property.GetValue(owner)
        list := value as IList
        if list == null {
            throw new InvalidOperationException(
                "CompilationUnitFacts expected '" + owner.GetType().Name + "." + propertyName + "' to contain a list.")
        }

        return list
    }
}
