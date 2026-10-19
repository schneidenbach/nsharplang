namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import YamlDotNet.Core.Events
import YamlDotNet.Serialization

class ReferenceConverter: IYamlTypeConverter {
    func Accepts(targetType: Type): bool {
        return targetType == typeof(Reference)
    }

    func ReadYaml(parser: YamlDotNet.Core.IParser, _targetType: Type, _rootDeserializer: ObjectDeserializer): object {
        scalar := parser.Current as Scalar
        if scalar != null {
            parser.MoveNext()
            return ReadScalarReference(scalar.Value)
        }

        mappingStart := parser.Current as MappingStart
        if mappingStart != null {
            parser.MoveNext()
            reference := new Reference()
            kinds := new List<string>()
            hasVersion := false

            while true {
                mappingEnd := parser.Current as MappingEnd
                if mappingEnd != null {
                    break
                }

                key := parser.Current as Scalar
                if key == null {
                    RecordProblem(reference, "it has a key that is not a plain name")
                    SkipNode(parser)
                    SkipNode(parser)
                    continue
                }

                keyValue := key.Value.ToLowerInvariant()
                parser.MoveNext()

                valueScalar := parser.Current as Scalar
                if valueScalar == null {
                    RecordProblem(reference, "'" + key.Value + "' has a nested value, but it must be a single value")
                    SkipNode(parser)
                    continue
                }

                value := valueScalar.Value
                parser.MoveNext()
                if IsKindKey(keyValue) {
                    kinds.Add(keyValue)
                } else if keyValue == "version" {
                    hasVersion = true
                } else {
                    RecordProblem(reference, "'" + key.Value + "' is not a dependency key")
                }

                ApplyMappingValue(reference, keyValue, value)
            }

            if kinds.Count > 1 {
                RecordProblem(reference, "it names more than one kind ('" + string.Join("' and '", kinds) + "')")
            }

            if hasVersion && !(kinds.Count == 1 && kinds[0] == "nuget") {
                RecordProblem(reference, "'version' belongs only to a nuget entry")
            }

            parser.MoveNext()
            return reference
        }

        throw new YamlDotNet.Core.YamlException("Invalid reference format")
    }

    func WriteYaml(emitter: YamlDotNet.Core.IEmitter, value: object?, _targetType: Type, _serializer: ObjectSerializer): void {
        reference := value as Reference
        if reference == null {
            throw new InvalidOperationException("Expected Reference object")
        }

        if reference.Type == ReferenceType.NuGet && !string.IsNullOrEmpty(reference.Version ?? "") {
            emitter.Emit(new Scalar((reference.Nuget ?? "") + "@" + (reference.Version ?? "")))
            return
        }

        emitter.Emit(new MappingStart())

        if reference.Type == ReferenceType.NuGet {
            emitter.Emit(new Scalar("nuget"))
            emitter.Emit(new Scalar(reference.Nuget ?? ""))
        } else if reference.Type == ReferenceType.Dll {
            emitter.Emit(new Scalar("dll"))
            emitter.Emit(new Scalar(reference.Dll ?? ""))
        } else if reference.Type == ReferenceType.Project {
            emitter.Emit(new Scalar("project"))
            emitter.Emit(new Scalar(reference.Project ?? ""))
        } else if reference.Type == ReferenceType.Framework {
            emitter.Emit(new Scalar("framework"))
            emitter.Emit(new Scalar(reference.Framework ?? ""))
        }

        emitter.Emit(new MappingEnd())
    }

    static func ReadScalarReference(value: string): Reference {
        atIndex := value.IndexOf('@')
        if atIndex >= 0 {
            return new Reference {
                Nuget: value.Substring(0, atIndex).Trim(),
                Version: value.Substring(atIndex + 1).Trim()
            }
        }

        return new Reference { Nuget: value.Trim() }
    }

    // Steps past one whole node -- a scalar, or a mapping or sequence with everything inside it.
    static func SkipNode(parser: YamlDotNet.Core.IParser) {
        depth := 0
        while true {
            current := parser.Current
            if (current as MappingStart) != null || (current as SequenceStart) != null {
                depth = depth + 1
            } else if (current as MappingEnd) != null || (current as SequenceEnd) != null {
                depth = depth - 1
            }

            parser.MoveNext()
            if depth <= 0 {
                return
            }
        }
    }

    static func IsKindKey(keyValue: string): bool {
        return keyValue == "nuget" || keyValue == "dll" || keyValue == "project" || keyValue == "framework"
    }

    // The FIRST problem is the one reported: a row is fixed one mistake at a time, and the first is
    // the one nearest the start of the entry the user is reading.
    static func RecordProblem(reference: Reference, problem: string) {
        if reference.Problem == null {
            reference.Problem = problem
        }
    }

    static func ApplyMappingValue(reference: Reference, keyValue: string, value: string) {
        if keyValue == "nuget" {
            atIndex := value.IndexOf('@')
            if atIndex >= 0 {
                reference.Nuget = value.Substring(0, atIndex).Trim()
                reference.Version = value.Substring(atIndex + 1).Trim()
            } else {
                reference.Nuget = value
            }
            return
        }

        if keyValue == "version" {
            reference.Version = value
            return
        }

        if keyValue == "dll" {
            reference.Dll = value
            return
        }

        if keyValue == "project" {
            reference.Project = value
            return
        }

        if keyValue == "framework" {
            reference.Framework = value
        }
    }
}
