namespace NSharpLang.Compiler

import System.Collections.Generic

public class PackageConfig {
    authorValue: string?
    descriptionValue: string?
    tagsValue: List<string>?
    licenseValue: string?
    repositoryValue: string?
    iconValue: string?

    Author: string? {
        get {
            return authorValue
        }
        set {
            authorValue = value
        }
    }

    Description: string? {
        get {
            return descriptionValue
        }
        set {
            descriptionValue = value
        }
    }

    Tags: List<string>? {
        get {
            return tagsValue
        }
        set {
            tagsValue = value
        }
    }

    License: string? {
        get {
            return licenseValue
        }
        set {
            licenseValue = value
        }
    }

    Repository: string? {
        get {
            return repositoryValue
        }
        set {
            repositoryValue = value
        }
    }

    Icon: string? {
        get {
            return iconValue
        }
        set {
            iconValue = value
        }
    }
}

public class LanguageConfig {
    profileValue: string = "default"
    asyncDefaultTypeValue: string = "ValueTask"
    pooledAsyncValue: bool
    systemsValue: SystemsConfig = new SystemsConfig()

    Profile: string {
        get {
            return profileValue
        }
        set {
            profileValue = value
        }
    }

    AsyncDefaultType: string {
        get {
            return asyncDefaultTypeValue
        }
        set {
            asyncDefaultTypeValue = value
        }
    }

    PooledAsync: bool {
        get {
            return pooledAsyncValue
        }
        set {
            pooledAsyncValue = value
        }
    }

    Systems: SystemsConfig {
        get {
            return systemsValue
        }
        set {
            systemsValue = value
        }
    }
}

public class SystemsConfig {
    modeValue: string = "strict"
    unknownExternalCallsValue: string = "warn"
    aotTargetValue: string = "nativeaot"
    warmupValue: List<string> = new List<string>()
    stackBudgetBytesValue: int = 4096
    hotSummaryFilesValue: List<string> = new List<string>()
    allowHotSidecarsValue: bool

    Mode: string {
        get {
            return modeValue
        }
        set {
            modeValue = value
        }
    }

    UnknownExternalCalls: string {
        get {
            return unknownExternalCallsValue
        }
        set {
            unknownExternalCallsValue = value
        }
    }

    AotTarget: string {
        get {
            return aotTargetValue
        }
        set {
            aotTargetValue = value
        }
    }

    Warmup: List<string> {
        get {
            return warmupValue
        }
        set {
            warmupValue = value
        }
    }

    StackBudgetBytes: int {
        get {
            return stackBudgetBytesValue
        }
        set {
            stackBudgetBytesValue = value
        }
    }

    HotSummaryFiles: List<string> {
        get {
            return hotSummaryFilesValue
        }
        set {
            hotSummaryFilesValue = value
        }
    }

    AllowHotSidecars: bool {
        get {
            return allowHotSidecarsValue
        }
        set {
            allowHotSidecarsValue = value
        }
    }
}
