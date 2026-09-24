namespace NSharpLang.Build.Tasks

import System
import Microsoft.Build.Framework
import Microsoft.Build.Utilities
import NSharpLang.Compiler

class LoadProjectReferences: Microsoft.Build.Utilities.Task {
    private projectFileValue: string?

    ProjectFile: string? {
        get {
            return projectFileValue
        }
        set {
            projectFileValue = value
        }
    }

    private packageReferencesValue: ITaskItem[]

    [Microsoft.Build.Framework.Output]
    PackageReferences: ITaskItem[] {
        get {
            return packageReferencesValue
        }
        set {
            packageReferencesValue = value
        }
    }

    private frameworkReferencesValue: string[]

    [Microsoft.Build.Framework.Output]
    FrameworkReferences: string[] {
        get {
            return frameworkReferencesValue
        }
        set {
            frameworkReferencesValue = value
        }
    }

    private existingProjectReferencesValue: string[]

    ExistingProjectReferences: string[] {
        get {
            return existingProjectReferencesValue
        }
        set {
            existingProjectReferencesValue = value
        }
    }

    private projectReferencesValue: string[]

    [Microsoft.Build.Framework.Output]
    ProjectReferences: string[] {
        get {
            return projectReferencesValue
        }
        set {
            projectReferencesValue = value
        }
    }

    constructor() {
        projectFileValue = null
        packageReferencesValue = Array.Empty<ITaskItem>()
        frameworkReferencesValue = Array.Empty<string>()
        existingProjectReferencesValue = Array.Empty<string>()
        projectReferencesValue = Array.Empty<string>()
    }

    override func Execute(): bool {
        try {
            projection := SdkProjectReferenceProjection.Resolve(ProjectFile, ExistingProjectReferences)
            packageReferences := new ITaskItem[](projection.PackageReferences.Length)
            packageIndex := 0
            while packageIndex < packageReferences.Length {
                reference := projection.PackageReferences[packageIndex]
                packageItem: ITaskItem = new TaskItem(reference.Identity, reference.Metadata)
                packageReferences[packageIndex] = packageItem
                packageIndex = packageIndex + 1
            }

            PackageReferences = packageReferences
            FrameworkReferences = projection.FrameworkReferences
            ProjectReferences = projection.ProjectReferences
            return true
        } catch ex: Exception {
            emptyProjectFile: string? = null
            get_Log().LogErrorFromException(ex, true, false, emptyProjectFile)
            return false
        }
    }
}
