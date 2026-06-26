namespace NSharpLang.Compiler

import System
import YamlDotNet.Core.Events
import YamlDotNet.Serialization

public class ReferenceConverter: IYamlTypeConverter {
    public func Accepts(targetType: Type): bool {
        return targetType == typeof(Reference)
    }

    public func ReadYaml(parser: YamlDotNet.Core.IParser, targetType: Type, rootDeserializer: ObjectDeserializer): object {
        scalar := parser.Current as Scalar
        if scalar != null {
            parser.MoveNext()
            return ReadScalarReference(scalar.Value)
        }

        mappingStart := parser.Current as MappingStart
        if mappingStart != null {
            parser.MoveNext()
            reference := new Reference()

            while true {
                mappingEnd := parser.Current as MappingEnd
                if mappingEnd != null {
                    break
                }

                key := parser.Current as Scalar
                if key == null {
                    parser.MoveNext()
                    continue
                }

                keyValue := key.Value.ToLowerInvariant()
                parser.MoveNext()

                valueScalar := parser.Current as Scalar
                if valueScalar == null {
                    parser.MoveNext()
                    continue
                }

                value := valueScalar.Value
                parser.MoveNext()
                ApplyMappingValue(reference, keyValue, value)
            }

            parser.MoveNext()
            return reference
        }

        throw new YamlDotNet.Core.YamlException("Invalid reference format")
    }

    public func WriteYaml(emitter: YamlDotNet.Core.IEmitter, value: object?, targetType: Type, serializer: ObjectSerializer): void {
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
