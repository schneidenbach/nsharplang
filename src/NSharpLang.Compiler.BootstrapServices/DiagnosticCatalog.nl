namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text

class DiagnosticCatalog {
    static Descriptors: IReadOnlyCollection<DiagnosticDescriptor> => BuildDescriptors()

    static LinterDescriptors: IReadOnlyCollection<DiagnosticDescriptor> => BuildLinterDescriptors()

    static func TryGetDescriptor(code: string, out descriptor: DiagnosticDescriptor): bool {
        descriptor = EmptyDescriptor()

        descriptors := BuildDescriptors()
        i := 0
        while i < descriptors.Count {
            current := descriptors[i]
            if String.Compare(current.Code, code, StringComparison.Ordinal) == 0 {
                descriptor = current
                return true
            }

            i = i + 1
        }

        return false
    }

    static func GetDefaultSeverity(code: string): DiagnosticSeverity {
        return GetDefaultSeverity(code, DiagnosticSeverity.Warning)
    }

    static func GetDefaultSeverity(code: string, fallback: DiagnosticSeverity = DiagnosticSeverity.Warning): DiagnosticSeverity {
        descriptor := EmptyDescriptor()
        if TryGetDescriptor(code, out descriptor) {
            return descriptor.DefaultSeverity
        }

        return fallback
    }

    // NO descriptor stores a URL any more. The four AOT rows were the only ones that ever did, and
    // they were retired with the rest of the unproduced codes, so the catalog answers this question
    // the same way for every code it publishes: from `DiagnosticDocs`, the one host in the product.
    static func DocsUrlFor(code: string): string {
        return DiagnosticDocs.UrlFor(code)
    }

    // The codes this catalog publishes, sorted, as a plain list. `Descriptors` exposes them only
    // through `IReadOnlyCollection<DiagnosticDescriptor>`, which does not survive a cross-assembly
    // walk on the columnar emit path — `tests/native/error-docs-contract` needs the code list to
    // cross that boundary, and so would any tool that wants to enumerate the catalog.
    static func AllCodes(): List<string> {
        codes := new List<string>()
        descriptors := BuildDescriptors()
        i := 0
        while i < descriptors.Count {
            codes.Add(descriptors[i].Code)
            i = i + 1
        }

        codes.Sort()
        return codes
    }

    static func BuildDescriptors(): List<DiagnosticDescriptor> {
        descriptors := new List<DiagnosticDescriptor>()
        AddCompilerDescriptors(descriptors)
        AddLinterRuleDescriptors(descriptors)
        return descriptors
    }

    static func BuildLinterDescriptors(): List<DiagnosticDescriptor> {
        allDescriptors := BuildDescriptors()
        linterDescriptors := new List<DiagnosticDescriptor>()

        i := 0
        while i < allDescriptors.Count {
            descriptor := allDescriptors[i]
            if descriptor.Source == DiagnosticSource.Linter {
                linterDescriptors.Add(descriptor)
            }

            i = i + 1
        }

        return linterDescriptors
    }

    static func AddDescriptor(descriptors: List<DiagnosticDescriptor>, descriptor: DiagnosticDescriptor) {
        i := 0
        while i < descriptors.Count {
            existing := descriptors[i]
            if String.Compare(existing.Code, descriptor.Code, StringComparison.Ordinal) == 0 {
                throw new InvalidOperationException("Duplicate diagnostic code '" + descriptor.Code + "' in diagnostic catalog.")
            }

            i = i + 1
        }

        descriptors.Add(descriptor)
    }

    static func AddCompilerDescriptors(descriptors: List<DiagnosticDescriptor>) {
        AddCompiler(descriptors, ErrorCode.UnexpectedToken)
        AddCompiler(descriptors, ErrorCode.ExpectedToken)
        AddCompiler(descriptors, ErrorCode.InvalidSyntax)
        AddCompiler(descriptors, ErrorCode.UnexpectedEndOfFile)
        AddCompiler(descriptors, ErrorCode.InvalidLiteral)
        AddCompiler(descriptors, ErrorCode.MissingClosingBrace)
        AddCompiler(descriptors, ErrorCode.MissingClosingParen)
        AddCompiler(descriptors, ErrorCode.MissingClosingBracket)
        AddCompiler(descriptors, ErrorCode.ReservedKeywordAsName)
        AddCompiler(descriptors, ErrorCode.InvalidPreprocessorDirective)

        AddCompiler(descriptors, ErrorCode.TypeNotFound)
        AddCompiler(descriptors, ErrorCode.TypeMismatch)
        AddCompiler(descriptors, ErrorCode.CannotInferType)
        AddCompiler(descriptors, ErrorCode.InvalidCast)
        AddCompiler(descriptors, ErrorCode.InvalidTypeArgument)
        AddCompiler(descriptors, ErrorCode.GenericConstraintViolation)

        AddCompiler(descriptors, ErrorCode.UndefinedVariable)
        AddCompiler(descriptors, ErrorCode.UndefinedMember)
        AddCompiler(descriptors, ErrorCode.DefiniteAssignmentError)
        AddCompiler(descriptors, ErrorCode.MissingReturn)
        AddCompiler(descriptors, ErrorCode.DuplicateDeclaration)
        AddCompiler(descriptors, ErrorCode.CircularDependency)
        AddCompiler(descriptors, ErrorCode.InaccessibleMember)
        AddCompiler(descriptors, ErrorCode.ReadonlyAssignment)
        AddCompiler(descriptors, ErrorCode.ConstantRequired)
        AddCompiler(descriptors, ErrorCode.InvalidModifier)
        AddCompiler(descriptors, ErrorCode.UnreachableStatement)
        AddCompiler(descriptors, ErrorCode.InvalidExpressionStatement)
        AddCompiler(descriptors, ErrorCode.UnverifiedErrorResult)
        AddCompiler(descriptors, ErrorCode.DiscardedMustUseResult)
        AddCompiler(descriptors, ErrorCode.ShadowedDeclaration)
        AddCompiler(descriptors, ErrorCode.EventRequiresOnOff)
        AddCompiler(descriptors, ErrorCode.InvalidEventSubscription)
        AddCompiler(descriptors, ErrorCode.ControlTransferOutOfFinally)
        AddCompiler(descriptors, ErrorCode.LockRequiresReferenceType)
        AddCompiler(descriptors, ErrorCode.InvalidSizedArrayConstructorArguments)
        AddCompiler(descriptors, ErrorCode.MemberWriteThroughValueCopy)
        AddCompiler(descriptors, ErrorCode.FeatureNotImplemented)
        AddCompiler(descriptors, ErrorCode.AbstractMemberNotImplemented)
        AddCompiler(descriptors, ErrorCode.InterfaceMemberNotImplemented)

        AddCompiler(descriptors, ErrorCode.WrongArgumentCount)
        AddCompiler(descriptors, ErrorCode.NoMatchingOverload)
        AddCompiler(descriptors, ErrorCode.InvalidParameter)
        AddCompiler(descriptors, ErrorCode.ParamsNotLast)
        AddCompiler(descriptors, ErrorCode.RequiredParameterAfterOptional)
        AddCompiler(descriptors, ErrorCode.InvalidDefaultParameterValue)
        AddCompiler(descriptors, ErrorCode.MethodGroupUsedAsValue)
        AddCompiler(descriptors, ErrorCode.UndefinedFunction)

        AddCompiler(descriptors, ErrorCode.NonExhaustiveMatch)
        AddCompiler(descriptors, ErrorCode.UnreachablePattern)
        AddCompiler(descriptors, ErrorCode.InvalidPattern)
        AddCompiler(descriptors, ErrorCode.PatternTypeMismatch)
        AddCompiler(descriptors, ErrorCode.GuardNotBoolean)
        AddCompiler(descriptors, ErrorCode.ImpossiblePattern)

        AddCompiler(descriptors, ErrorCode.InvalidOperatorOverload)
        AddCompiler(descriptors, ErrorCode.OperatorParameterCount)

        AddCompiler(descriptors, ErrorCode.ImportNotFound)
        AddCompiler(descriptors, ErrorCode.ImportCollision)
        AddCompiler(descriptors, ErrorCode.CircularImport)
        AddCompiler(descriptors, ErrorCode.NamespaceNotFound)

        AddCompiler(descriptors, ErrorCode.MultipleInheritance)
        AddCompiler(descriptors, ErrorCode.SealedInheritance)
        AddCompiler(descriptors, ErrorCode.AbstractInstantiation)
        AddCompiler(descriptors, ErrorCode.ConstructorError)

        AddCompiler(descriptors, ErrorCode.VisibilityConventionWarning)
        AddCompiler(descriptors, ErrorCode.PossibleNullAccess)
        AddCompiler(descriptors, ErrorCode.NullabilityWarning)
        AddCompiler(descriptors, ErrorCode.ReferenceLoadFailure)
    }

    static func AddCompiler(descriptors: List<DiagnosticDescriptor>, code: ErrorCode) {
        category := GetCompilerCategory(code)
        severity := DiagnosticSeverity.Error
        if code == ErrorCode.ReferenceLoadFailure {
            severity = DiagnosticSeverity.Warning
        }

        AddDescriptor(descriptors, new DiagnosticDescriptor(FormatDiagnosticCode(code), ToTitle(ErrorCodeName(code)), DiagnosticSource.Compiler, category, severity, severity == DiagnosticSeverity.Error, false))
    }

    static func GetCompilerCategory(code: ErrorCode): DiagnosticCategory {
        value := Convert.ToInt32(code)
        if value >= Convert.ToInt32(ErrorCode.UnexpectedToken) && value <= Convert.ToInt32(ErrorCode.ReservedKeywordAsName) {
            return DiagnosticCategory.Syntax
        }

        if value >= Convert.ToInt32(ErrorCode.TypeNotFound) && value <= Convert.ToInt32(ErrorCode.GenericConstraintViolation) {
            return DiagnosticCategory.Type
        }

        if value >= Convert.ToInt32(ErrorCode.UndefinedVariable) && value <= Convert.ToInt32(ErrorCode.InterfaceMemberNotImplemented) {
            return DiagnosticCategory.Semantic
        }

        if value >= Convert.ToInt32(ErrorCode.WrongArgumentCount) && value <= Convert.ToInt32(ErrorCode.UndefinedFunction) {
            return DiagnosticCategory.Function
        }

        if value >= Convert.ToInt32(ErrorCode.NonExhaustiveMatch) && value <= Convert.ToInt32(ErrorCode.ImpossiblePattern) {
            return DiagnosticCategory.Pattern
        }

        if value >= Convert.ToInt32(ErrorCode.InvalidOperatorOverload) && value <= Convert.ToInt32(ErrorCode.OperatorParameterCount) {
            return DiagnosticCategory.Operator
        }

        if value >= Convert.ToInt32(ErrorCode.ImportNotFound) && value <= Convert.ToInt32(ErrorCode.NamespaceNotFound) {
            return DiagnosticCategory.Import
        }

        if value >= Convert.ToInt32(ErrorCode.MultipleInheritance) && value <= Convert.ToInt32(ErrorCode.ConstructorError) {
            return DiagnosticCategory.TypeDeclaration
        }

        if code == ErrorCode.PossibleNullAccess || code == ErrorCode.NullabilityWarning {
            return DiagnosticCategory.Nullability
        }

        if code == ErrorCode.VisibilityConventionWarning {
            return DiagnosticCategory.Style
        }

        return DiagnosticCategory.Semantic
    }

    static func AddLinterRuleDescriptors(descriptors: List<DiagnosticDescriptor>) {
        AddDescriptor(descriptors, Linter("NL001", "Unused variable", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, true))
        AddDescriptor(descriptors, Linter("NL002", "Missing import", DiagnosticCategory.Import, DiagnosticSeverity.Error, true))
        AddDescriptor(descriptors, Linter("NL003", "Unnecessary null check", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, true))
        AddDescriptor(descriptors, Linter("NL004", "Async without await", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, true))
        AddDescriptor(descriptors, Linter("NL006", "Unreachable code", DiagnosticCategory.Semantic, DiagnosticSeverity.Error, true))
        AddDescriptor(descriptors, Linter("NL010", "Unused import", DiagnosticCategory.Import, DiagnosticSeverity.Error, true))
        AddDescriptor(descriptors, Linter("NL011", "Empty catch", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, true))
        AddDescriptor(descriptors, Linter("NL012", "Unused parameter", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, true))
        AddDescriptor(descriptors, Linter("NL016", "Redundant null check", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, true))
        AddDescriptor(descriptors, Linter("NL020", "Shadowed variable", DiagnosticCategory.Hygiene, DiagnosticSeverity.Error, true))
    }

    static func Linter(code: string, title: string, category: DiagnosticCategory, severity: DiagnosticSeverity, blocksBuild: bool): DiagnosticDescriptor {
        return new DiagnosticDescriptor(code, title, DiagnosticSource.Linter, category, severity, blocksBuild)
    }

    static func FormatDiagnosticCode(code: ErrorCode): string {
        valueText := Convert.ToInt32(code).ToString()
        while valueText.Length < 3 {
            valueText = "0" + valueText
        }

        return "NL" + valueText
    }

    static func ErrorCodeName(code: ErrorCode): string {
        name := Enum.GetName(typeof(ErrorCode), Convert.ToInt32(code))
        if name == null {
            return Convert.ToInt32(code).ToString()
        }

        return name
    }

    static func ToTitle(pascalCase: string): string {
        title := new StringBuilder()
        i := 0
        while i < pascalCase.Length {
            if i > 0 && char.IsUpper(pascalCase[i]) {
                title.Append(' ')
            }

            title.Append(pascalCase[i])
            i = i + 1
        }

        return title.ToString()
    }

    static func EmptyDescriptor(): DiagnosticDescriptor {
        return new DiagnosticDescriptor("", "", DiagnosticSource.Compiler, DiagnosticCategory.Semantic, DiagnosticSeverity.Warning, false, false)
    }
}
