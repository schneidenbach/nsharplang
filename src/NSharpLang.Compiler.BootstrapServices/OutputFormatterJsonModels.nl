namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

class PerfReportSiteJson {
    codeValue: string
    effectValue: string
    fileValue: string
    lineValue: int
    columnValue: int
    messageValue: string
    functionValue: string?
    suggestionValue: string?

    Code: string {
        get {
            return codeValue
        }
        set {
            codeValue = value
        }
    }

    Effect: string {
        get {
            return effectValue
        }
        set {
            effectValue = value
        }
    }

    File: string {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Line: int {
        get {
            return lineValue
        }
        set {
            lineValue = value
        }
    }

    Column: int {
        get {
            return columnValue
        }
        set {
            columnValue = value
        }
    }

    Message: string {
        get {
            return messageValue
        }
        set {
            messageValue = value
        }
    }

    Function: string? {
        get {
            return functionValue
        }
        set {
            functionValue = value
        }
    }

    Suggestion: string? {
        get {
            return suggestionValue
        }
        set {
            suggestionValue = value
        }
    }

    constructor(Code: string, Effect: string, File: string, Line: int, Column: int, Message: string, Function: string?, Suggestion: string?) {
        codeValue = Code
        effectValue = Effect
        fileValue = File
        lineValue = Line
        columnValue = Column
        messageValue = Message
        functionValue = Function
        suggestionValue = Suggestion
    }
}

class PerfReportTrustedSiteJson {
    functionValue: string
    fileValue: string
    lineValue: int
    columnValue: int
    ownerValue: string?
    reviewValue: string?
    expiresValue: string?
    hasUnsafeValue: bool
    bodyStatementCountValue: int

    Function: string {
        get {
            return functionValue
        }
        set {
            functionValue = value
        }
    }

    File: string {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Line: int {
        get {
            return lineValue
        }
        set {
            lineValue = value
        }
    }

    Column: int {
        get {
            return columnValue
        }
        set {
            columnValue = value
        }
    }

    Owner: string? {
        get {
            return ownerValue
        }
        set {
            ownerValue = value
        }
    }

    Review: string? {
        get {
            return reviewValue
        }
        set {
            reviewValue = value
        }
    }

    Expires: string? {
        get {
            return expiresValue
        }
        set {
            expiresValue = value
        }
    }

    HasUnsafe: bool {
        get {
            return hasUnsafeValue
        }
        set {
            hasUnsafeValue = value
        }
    }

    BodyStatementCount: int {
        get {
            return bodyStatementCountValue
        }
        set {
            bodyStatementCountValue = value
        }
    }

    constructor(Function: string, File: string, Line: int, Column: int, Owner: string?, Review: string?, Expires: string?, HasUnsafe: bool, BodyStatementCount: int) {
        functionValue = Function
        fileValue = File
        lineValue = Line
        columnValue = Column
        ownerValue = Owner
        reviewValue = Review
        expiresValue = Expires
        hasUnsafeValue = HasUnsafe
        bodyStatementCountValue = BodyStatementCount
    }
}

class SystemsAotReportJson {
    targetValue: string
    analysisValue: string
    nativeImageEmittedValue: bool
    trimSafeValue: bool

    Target: string {
        get {
            return targetValue
        }
        set {
            targetValue = value
        }
    }

    Analysis: string {
        get {
            return analysisValue
        }
        set {
            analysisValue = value
        }
    }

    NativeImageEmitted: bool {
        get {
            return nativeImageEmittedValue
        }
        set {
            nativeImageEmittedValue = value
        }
    }

    TrimSafe: bool {
        get {
            return trimSafeValue
        }
        set {
            trimSafeValue = value
        }
    }

    constructor(Target: string, Analysis: string, NativeImageEmitted: bool, TrimSafe: bool) {
        targetValue = Target
        analysisValue = Analysis
        nativeImageEmittedValue = NativeImageEmitted
        trimSafeValue = TrimSafe
    }
}

class SystemsEffectFactsJson {
    allocatesValue: bool
    boxesValue: bool
    constructsDelegateValue: bool
    capturesClosureValue: bool
    usesRuntimeDispatchValue: bool
    usesReflectionValue: bool
    usesDynamicCodeValue: bool
    throwsValue: bool
    hasImplicitTrapObligationValue: bool
    usesUnknownExternalCallValue: bool
    usesResourceValue: bool
    usesPoolValue: bool
    usesConcurrencyPrimitiveValue: bool
    requiresWarmupValue: bool
    aotSafeValue: bool

    Allocates: bool {
        get {
            return allocatesValue
        }
        set {
            allocatesValue = value
        }
    }

    Boxes: bool {
        get {
            return boxesValue
        }
        set {
            boxesValue = value
        }
    }

    ConstructsDelegate: bool {
        get {
            return constructsDelegateValue
        }
        set {
            constructsDelegateValue = value
        }
    }

    CapturesClosure: bool {
        get {
            return capturesClosureValue
        }
        set {
            capturesClosureValue = value
        }
    }

    UsesRuntimeDispatch: bool {
        get {
            return usesRuntimeDispatchValue
        }
        set {
            usesRuntimeDispatchValue = value
        }
    }

    UsesReflection: bool {
        get {
            return usesReflectionValue
        }
        set {
            usesReflectionValue = value
        }
    }

    UsesDynamicCode: bool {
        get {
            return usesDynamicCodeValue
        }
        set {
            usesDynamicCodeValue = value
        }
    }

    Throws: bool {
        get {
            return throwsValue
        }
        set {
            throwsValue = value
        }
    }

    HasImplicitTrapObligation: bool {
        get {
            return hasImplicitTrapObligationValue
        }
        set {
            hasImplicitTrapObligationValue = value
        }
    }

    UsesUnknownExternalCall: bool {
        get {
            return usesUnknownExternalCallValue
        }
        set {
            usesUnknownExternalCallValue = value
        }
    }

    UsesResource: bool {
        get {
            return usesResourceValue
        }
        set {
            usesResourceValue = value
        }
    }

    UsesPool: bool {
        get {
            return usesPoolValue
        }
        set {
            usesPoolValue = value
        }
    }

    UsesConcurrencyPrimitive: bool {
        get {
            return usesConcurrencyPrimitiveValue
        }
        set {
            usesConcurrencyPrimitiveValue = value
        }
    }

    RequiresWarmup: bool {
        get {
            return requiresWarmupValue
        }
        set {
            requiresWarmupValue = value
        }
    }

    AotSafe: bool {
        get {
            return aotSafeValue
        }
        set {
            aotSafeValue = value
        }
    }

    constructor(Allocates: bool, Boxes: bool, ConstructsDelegate: bool, CapturesClosure: bool, UsesRuntimeDispatch: bool, UsesReflection: bool, UsesDynamicCode: bool, Throws: bool, HasImplicitTrapObligation: bool, UsesUnknownExternalCall: bool, UsesResource: bool, UsesPool: bool, UsesConcurrencyPrimitive: bool, RequiresWarmup: bool, AotSafe: bool) {
        allocatesValue = Allocates
        boxesValue = Boxes
        constructsDelegateValue = ConstructsDelegate
        capturesClosureValue = CapturesClosure
        usesRuntimeDispatchValue = UsesRuntimeDispatch
        usesReflectionValue = UsesReflection
        usesDynamicCodeValue = UsesDynamicCode
        throwsValue = Throws
        hasImplicitTrapObligationValue = HasImplicitTrapObligation
        usesUnknownExternalCallValue = UsesUnknownExternalCall
        usesResourceValue = UsesResource
        usesPoolValue = UsesPool
        usesConcurrencyPrimitiveValue = UsesConcurrencyPrimitive
        requiresWarmupValue = RequiresWarmup
        aotSafeValue = AotSafe
    }
}

class SystemsFunctionSummaryJson {
    nameValue: string
    fileValue: string
    lineValue: int
    columnValue: int
    isHotValue: bool
    isBoundaryValue: bool
    allocNoneValue: bool
    summarySourceValue: string
    effectsValue: SystemsEffectFactsJson
    callsValue: IReadOnlyList<string>

    Name: string {
        get {
            return nameValue
        }
        set {
            nameValue = value
        }
    }

    File: string {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Line: int {
        get {
            return lineValue
        }
        set {
            lineValue = value
        }
    }

    Column: int {
        get {
            return columnValue
        }
        set {
            columnValue = value
        }
    }

    IsHot: bool {
        get {
            return isHotValue
        }
        set {
            isHotValue = value
        }
    }

    IsBoundary: bool {
        get {
            return isBoundaryValue
        }
        set {
            isBoundaryValue = value
        }
    }

    AllocNone: bool {
        get {
            return allocNoneValue
        }
        set {
            allocNoneValue = value
        }
    }

    SummarySource: string {
        get {
            return summarySourceValue
        }
        set {
            summarySourceValue = value
        }
    }

    Effects: SystemsEffectFactsJson {
        get {
            return effectsValue
        }
        set {
            effectsValue = value
        }
    }

    Calls: IReadOnlyList<string> {
        get {
            return callsValue
        }
        set {
            callsValue = value
        }
    }

    constructor(Name: string, File: string, Line: int, Column: int, IsHot: bool, IsBoundary: bool, AllocNone: bool, SummarySource: string, Effects: SystemsEffectFactsJson, Calls: IReadOnlyList<string>) {
        nameValue = Name
        fileValue = File
        lineValue = Line
        columnValue = Column
        isHotValue = IsHot
        isBoundaryValue = IsBoundary
        allocNoneValue = AllocNone
        summarySourceValue = SummarySource
        effectsValue = Effects
        callsValue = Calls
    }
}

class SystemsFindingJson {
    codeValue: string
    severityValue: string
    effectValue: string
    messageValue: string
    fileValue: string
    lineValue: int
    columnValue: int
    lengthValue: int
    functionValue: string?
    policyValue: string?
    summarySourceValue: string?
    suggestionValue: string?
    callPathValue: IReadOnlyList<string>

    Code: string {
        get {
            return codeValue
        }
        set {
            codeValue = value
        }
    }

    Severity: string {
        get {
            return severityValue
        }
        set {
            severityValue = value
        }
    }

    Effect: string {
        get {
            return effectValue
        }
        set {
            effectValue = value
        }
    }

    Message: string {
        get {
            return messageValue
        }
        set {
            messageValue = value
        }
    }

    File: string {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Line: int {
        get {
            return lineValue
        }
        set {
            lineValue = value
        }
    }

    Column: int {
        get {
            return columnValue
        }
        set {
            columnValue = value
        }
    }

    Length: int {
        get {
            return lengthValue
        }
        set {
            lengthValue = value
        }
    }

    Function: string? {
        get {
            return functionValue
        }
        set {
            functionValue = value
        }
    }

    Policy: string? {
        get {
            return policyValue
        }
        set {
            policyValue = value
        }
    }

    SummarySource: string? {
        get {
            return summarySourceValue
        }
        set {
            summarySourceValue = value
        }
    }

    Suggestion: string? {
        get {
            return suggestionValue
        }
        set {
            suggestionValue = value
        }
    }

    CallPath: IReadOnlyList<string> {
        get {
            return callPathValue
        }
        set {
            callPathValue = value
        }
    }

    constructor(Code: string, Severity: string, Effect: string, Message: string, File: string, Line: int, Column: int, Length: int, Function: string?, Policy: string?, SummarySource: string?, Suggestion: string?, CallPath: IReadOnlyList<string>) {
        codeValue = Code
        severityValue = Severity
        effectValue = Effect
        messageValue = Message
        fileValue = File
        lineValue = Line
        columnValue = Column
        lengthValue = Length
        functionValue = Function
        policyValue = Policy
        summarySourceValue = SummarySource
        suggestionValue = Suggestion
        callPathValue = CallPath
    }
}

class SystemsTrustedSiteJson {
    functionValue: string
    fileValue: string
    lineValue: int
    columnValue: int
    reasonValue: string?
    ownerValue: string?
    reviewValue: string?
    expiresValue: string?
    hasUnsafeValue: bool
    bodyStatementCountValue: int

    Function: string {
        get {
            return functionValue
        }
        set {
            functionValue = value
        }
    }

    File: string {
        get {
            return fileValue
        }
        set {
            fileValue = value
        }
    }

    Line: int {
        get {
            return lineValue
        }
        set {
            lineValue = value
        }
    }

    Column: int {
        get {
            return columnValue
        }
        set {
            columnValue = value
        }
    }

    Reason: string? {
        get {
            return reasonValue
        }
        set {
            reasonValue = value
        }
    }

    Owner: string? {
        get {
            return ownerValue
        }
        set {
            ownerValue = value
        }
    }

    Review: string? {
        get {
            return reviewValue
        }
        set {
            reviewValue = value
        }
    }

    Expires: string? {
        get {
            return expiresValue
        }
        set {
            expiresValue = value
        }
    }

    HasUnsafe: bool {
        get {
            return hasUnsafeValue
        }
        set {
            hasUnsafeValue = value
        }
    }

    BodyStatementCount: int {
        get {
            return bodyStatementCountValue
        }
        set {
            bodyStatementCountValue = value
        }
    }

    constructor(Function: string, File: string, Line: int, Column: int, Reason: string?, Owner: string?, Review: string?, Expires: string?, HasUnsafe: bool, BodyStatementCount: int) {
        functionValue = Function
        fileValue = File
        lineValue = Line
        columnValue = Column
        reasonValue = Reason
        ownerValue = Owner
        reviewValue = Review
        expiresValue = Expires
        hasUnsafeValue = HasUnsafe
        bodyStatementCountValue = BodyStatementCount
    }
}

class SystemsReportSummaryJson {
    functionsValue: int
    hotFunctionsValue: int
    boundaryFunctionsValue: int
    findingsValue: int
    errorsValue: int
    warningsValue: int
    trustedSitesValue: int

    Functions: int {
        get {
            return functionsValue
        }
        set {
            functionsValue = value
        }
    }

    HotFunctions: int {
        get {
            return hotFunctionsValue
        }
        set {
            hotFunctionsValue = value
        }
    }

    BoundaryFunctions: int {
        get {
            return boundaryFunctionsValue
        }
        set {
            boundaryFunctionsValue = value
        }
    }

    Findings: int {
        get {
            return findingsValue
        }
        set {
            findingsValue = value
        }
    }

    Errors: int {
        get {
            return errorsValue
        }
        set {
            errorsValue = value
        }
    }

    Warnings: int {
        get {
            return warningsValue
        }
        set {
            warningsValue = value
        }
    }

    TrustedSites: int {
        get {
            return trustedSitesValue
        }
        set {
            trustedSitesValue = value
        }
    }

    constructor(Functions: int, HotFunctions: int, BoundaryFunctions: int, Findings: int, Errors: int, Warnings: int, TrustedSites: int) {
        functionsValue = Functions
        hotFunctionsValue = HotFunctions
        boundaryFunctionsValue = BoundaryFunctions
        findingsValue = Findings
        errorsValue = Errors
        warningsValue = Warnings
        trustedSitesValue = TrustedSites
    }
}

class SystemsReportJsonPayload {
    schemaVersionValue: int
    profileValue: string
    modeValue: string
    aotTargetValue: string
    aotValue: SystemsAotReportJson
    warmupValue: IReadOnlyList<string>
    functionsValue: SystemsFunctionSummaryJson[]
    findingsValue: SystemsFindingJson[]
    trustedSitesValue: SystemsTrustedSiteJson[]
    summaryValue: SystemsReportSummaryJson

    SchemaVersion: int {
        get {
            return schemaVersionValue
        }
        set {
            schemaVersionValue = value
        }
    }

    Profile: string {
        get {
            return profileValue
        }
        set {
            profileValue = value
        }
    }

    Mode: string {
        get {
            return modeValue
        }
        set {
            modeValue = value
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

    Aot: SystemsAotReportJson {
        get {
            return aotValue
        }
        set {
            aotValue = value
        }
    }

    Warmup: IReadOnlyList<string> {
        get {
            return warmupValue
        }
        set {
            warmupValue = value
        }
    }

    Functions: SystemsFunctionSummaryJson[] {
        get {
            return functionsValue
        }
        set {
            functionsValue = value
        }
    }

    Findings: SystemsFindingJson[] {
        get {
            return findingsValue
        }
        set {
            findingsValue = value
        }
    }

    TrustedSites: SystemsTrustedSiteJson[] {
        get {
            return trustedSitesValue
        }
        set {
            trustedSitesValue = value
        }
    }

    Summary: SystemsReportSummaryJson {
        get {
            return summaryValue
        }
        set {
            summaryValue = value
        }
    }

    constructor(SchemaVersion: int, Profile: string, Mode: string, AotTarget: string, Aot: SystemsAotReportJson, Warmup: IReadOnlyList<string>, Functions: SystemsFunctionSummaryJson[], Findings: SystemsFindingJson[], TrustedSites: SystemsTrustedSiteJson[], Summary: SystemsReportSummaryJson) {
        schemaVersionValue = SchemaVersion
        profileValue = Profile
        modeValue = Mode
        aotTargetValue = AotTarget
        aotValue = Aot
        warmupValue = Warmup
        functionsValue = Functions
        findingsValue = Findings
        trustedSitesValue = TrustedSites
        summaryValue = Summary
    }
}
