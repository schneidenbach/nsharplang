namespace NSharpLang.Compiler

import System
import System.IO

class Reference {
    Nuget: string?
    Version: string?
    Dll: string?
    Project: string?
    Framework: string?

    Type: ReferenceType => GetReferenceType()

    Value: string => GetValue()

    HasValue: bool => !string.IsNullOrWhiteSpace(Nuget ?? "") || !string.IsNullOrWhiteSpace(Dll ?? "") || !string.IsNullOrWhiteSpace(Project ?? "") || !string.IsNullOrWhiteSpace(Framework ?? "")

    func Validate(projectDirectory: string) {
        typeValue := Type

        if typeValue == ReferenceType.NuGet {
            if string.IsNullOrWhiteSpace(Nuget ?? "") {
                throw new InvalidOperationException("NuGet reference must have a package name")
            }

            return
        }

        if typeValue == ReferenceType.Dll {
            dllValue := Dll ?? ""
            if string.IsNullOrWhiteSpace(dllValue) {
                throw new InvalidOperationException("DLL reference must have a path")
            }

            dllPath := dllValue
            if !Path.IsPathRooted(dllValue) {
                dllPath = Path.Combine(projectDirectory, dllValue)
            }

            if !File.Exists(dllPath) {
                throw new FileNotFoundException("DLL not found: " + dllValue + " (resolved to " + dllPath + ")")
            }

            return
        }

        if typeValue == ReferenceType.Project {
            projectValue := Project ?? ""
            if string.IsNullOrWhiteSpace(projectValue) {
                throw new InvalidOperationException("Project reference must have a path")
            }

            projectPath := projectValue
            if !Path.IsPathRooted(projectValue) {
                projectPath = Path.Combine(projectDirectory, projectValue)
            }

            if !File.Exists(projectPath) {
                throw new FileNotFoundException("Project file not found: " + projectValue + " (resolved to " + projectPath + ")")
            }

            return
        }

        if string.IsNullOrWhiteSpace(Framework ?? "") {
            throw new InvalidOperationException("Framework reference must have a name")
        }
    }

    func GetReferenceType(): ReferenceType {
        if Nuget != null {
            return ReferenceType.NuGet
        }
        if Dll != null {
            return ReferenceType.Dll
        }
        if Project != null {
            return ReferenceType.Project
        }
        if Framework != null {
            return ReferenceType.Framework
        }

        throw new InvalidOperationException("Reference must specify one of: nuget, dll, project, or framework")
    }

    func GetValue(): string {
        if Nuget != null {
            return Nuget ?? ""
        }
        if Dll != null {
            return Dll ?? ""
        }
        if Project != null {
            return Project ?? ""
        }
        if Framework != null {
            return Framework ?? ""
        }

        throw new InvalidOperationException("Invalid reference")
    }
}
