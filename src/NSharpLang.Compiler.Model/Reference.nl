namespace NSharpLang.Compiler

import System
import System.IO

class Reference {
    Nuget: string?
    Version: string?
    Dll: string?
    Project: string?
    Framework: string?

    // WHAT THE ROW SAID THAT THE ROW CANNOT MEAN, recorded by `ReferenceConverter` while it reads a
    // mapping and refused by `ProjectFileParser.ValidateConfig`: a key that is not one of the five a
    // dependency takes, a second kind (`nuget:` and `dll:` in one entry), `version:` on anything but a
    // NuGet entry, or a nested value. The converter used to drop each of these silently and keep the
    // first kind in nuget > dll > project > framework order, so a typo or a pasted MSBuild attribute
    // changed what the project referenced with no word said. Null when the row is well formed.
    Problem: string?

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

            // A DIRECTORY IS THE LIKELY MISTAKE HERE, and its fix is one path segment, so the message
            // spells the entry that works instead of only reporting a missing file.
            if Directory.Exists(projectPath) && File.Exists(Path.Combine(projectPath, "project.yml")) {
                separator := "/"
                if projectValue.EndsWith("/") || projectValue.EndsWith("\\") {
                    separator = ""
                }

                throw new FileNotFoundException("Project reference '" + projectValue + "' names a directory, but a project: entry must name the project file. Write 'project: " + projectValue + separator + "project.yml' instead.")
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
