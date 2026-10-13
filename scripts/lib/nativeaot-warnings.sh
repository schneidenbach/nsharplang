#!/usr/bin/env bash

# Keep the completed NativeAOT warning scopes in one place for both the standalone smoke gate and
# per-RID toolset publication. Unfinished owners remain visible in the full linker log.
nsharp_check_nativeaot_warning_scopes() {
    local log_path="$1"
    local finished_scopes='NSharpLang\.Compiler\.DotnetInstallationLocator\.|NSharpLang\.Cli\.CompilationReferenceResolverKernels\.FindDotnetRoot\(|NSharpLang\.Compiler\.ProjectConfigYamlMapping\.Read\(|NSharpLang\.Compiler\.ProjectFileParser\.ParseFromDirectory\(|NSharpLang\.Compiler\.CodeIntelligence\.OutputFormatterJsonKernels\.(CheckToJson|AppendDiagnosticJson|AppendJsonString|AppendJsonStringProperty|AppendJsonNumberProperty)\('
    local total_count finished_count

    total_count="$(grep -Ec 'warning IL[0-9]{4}' "$log_path" || true)"
    finished_count="$(grep -Ec "warning IL[0-9]{4}.*($finished_scopes)" "$log_path" || true)"
    echo "NativeAOT analyzer warnings in unfinished owners: $((total_count - finished_count))"
    if [[ "$finished_count" -gt 0 ]]; then
        echo "NativeAOT warnings in completed owners:" >&2
        grep -E "warning IL[0-9]{4}.*($finished_scopes)" "$log_path" >&2 || true
        return 1
    fi

    echo "Completed root-discovery, YAML-mapping, and check-JSON scopes are warning-clean."
}
