#!/bin/bash

# Script to reorganize examples into numbered directories
# Each directory will contain related examples

set -e

cd "$(dirname "$0")/.."

echo "Reorganizing examples..."

# Create the new structure
mkdir -p examples-new/01-hello-world
mkdir -p examples-new/02-variables-and-types
mkdir -p examples-new/03-functions
mkdir -p examples-new/04-pattern-matching
mkdir -p examples-new/05-unions
mkdir -p examples-new/06-classes-and-records
mkdir -p examples-new/07-interfaces
mkdir -p examples-new/08-async
mkdir -p examples-new/09-linq-and-collections
mkdir -p examples-new/10-interop
mkdir -p examples-new/11-advanced-features
mkdir -p examples-new/12-multi-file-projects
mkdir -p examples-new/13-aspnet-demo

# 01-hello-world
cp examples/hello.nl examples-new/01-hello-world/Program.nl
cp examples/simple.nl examples-new/01-hello-world/Simple.nl

# 02-variables-and-types
cp examples/print_nameof_typeof.nl examples-new/02-variables-and-types/PrintNameofTypeof.nl
cp examples/target_typed_new.nl examples-new/02-variables-and-types/TargetTypedNew.nl

# 03-functions
cp examples/expression_bodied_members.nl examples-new/03-functions/ExpressionBodiedMembers.nl
cp examples/local_functions.nl examples-new/03-functions/LocalFunctions.nl
cp examples/generic_methods.nl examples-new/03-functions/GenericMethods.nl
cp examples/params_arrays.nl examples-new/03-functions/ParamsArrays.nl
cp examples/params_collections.nl examples-new/03-functions/ParamsCollections.nl
cp examples/spread_in_function_calls.nl examples-new/03-functions/SpreadInFunctionCalls.nl
cp examples/simple_generic_calls.nl examples-new/03-functions/SimpleGenericCalls.nl

# 04-pattern-matching
cp examples/pattern_guards.nl examples-new/04-pattern-matching/PatternGuards.nl
cp examples/guards_simple.nl examples-new/04-pattern-matching/GuardsSimple.nl
cp examples/list_patterns.nl examples-new/04-pattern-matching/ListPatterns.nl
cp examples/type_patterns.nl examples-new/04-pattern-matching/TypePatterns.nl
cp examples/nested_property_patterns.nl examples-new/04-pattern-matching/NestedPropertyPatterns.nl
cp examples/nested_property_patterns_simple.nl examples-new/04-pattern-matching/NestedPropertyPatternsSimple.nl
cp examples/match_exhaustiveness.nl examples-new/04-pattern-matching/MatchExhaustiveness.nl

# 05-unions
cp examples/unions_and_match.nl examples-new/05-unions/UnionsAndMatch.nl
cp examples/error_handling.nl examples-new/05-unions/ErrorHandling.nl

# 06-classes-and-records
cp examples/records_and_interfaces.nl examples-new/06-classes-and-records/RecordsAndInterfaces.nl
cp examples/record_structs.nl examples-new/06-classes-and-records/RecordStructs.nl
cp examples/primary_constructors.nl examples-new/06-classes-and-records/PrimaryConstructors.nl
cp examples/primary_constructors_simple.nl examples-new/06-classes-and-records/PrimaryConstructorsSimple.nl
cp examples/constructor_chaining.nl examples-new/06-classes-and-records/ConstructorChaining.nl
cp examples/properties_and_nested_types.nl examples-new/06-classes-and-records/PropertiesAndNestedTypes.nl
cp examples/required_and_init_properties.nl examples-new/06-classes-and-records/RequiredAndInitProperties.nl

# 07-interfaces
cp examples/duck_interfaces.nl examples-new/07-interfaces/DuckInterfaces.nl
cp examples/extension_methods.nl examples-new/07-interfaces/ExtensionMethods.nl

# 08-async
cp examples/async_streams.nl examples-new/08-async/AsyncStreams.nl

# 09-linq-and-collections
cp examples/collection_expressions.nl examples-new/09-linq-and-collections/CollectionExpressions.nl
cp examples/collection_initializers_with_indexers.nl examples-new/09-linq-and-collections/CollectionInitializersWithIndexers.nl
cp examples/iterators.nl examples-new/09-linq-and-collections/Iterators.nl
cp examples/range_and_index.nl examples-new/09-linq-and-collections/RangeAndIndex.nl
cp examples/open_ended_ranges.nl examples-new/09-linq-and-collections/OpenEndedRanges.nl

# 10-interop
cp examples/qualified_attributes.nl examples-new/10-interop/QualifiedAttributes.nl
cp examples/ref_out_parameters.nl examples-new/10-interop/RefOutParameters.nl
cp examples/inline_out_variables.nl examples-new/10-interop/InlineOutVariables.nl

# 11-advanced-features
cp examples/operator_overloading.nl examples-new/11-advanced-features/OperatorOverloading.nl
cp examples/conversion_operators.nl examples-new/11-advanced-features/ConversionOperators.nl
cp examples/checked_unchecked.nl examples-new/11-advanced-features/CheckedUnchecked.nl
cp examples/lock_statement.nl examples-new/11-advanced-features/LockStatement.nl
cp examples/preprocessor_directives.nl examples-new/11-advanced-features/PreprocessorDirectives.nl
cp examples/interpolated_raw_strings.nl examples-new/11-advanced-features/InterpolatedRawStrings.nl
cp examples/file_scoped_types.nl examples-new/11-advanced-features/FileScopedTypes.nl
cp examples/file_scoped_simple.nl examples-new/11-advanced-features/FileScopedSimple.nl

# 12-multi-file-projects
cp -r examples/MultiFileProject examples-new/12-multi-file-projects/MultiFileProject
cp -r examples/SimpleProject examples-new/12-multi-file-projects/SimpleProject
cp -r examples/imports examples-new/12-multi-file-projects/imports
cp -r examples/TestExample examples-new/12-multi-file-projects/TestExample
cp -r examples/WeatherDemo examples-new/12-multi-file-projects/WeatherDemo

# Test files (might want to handle these separately)
cp examples/test_errors.nl examples-new/02-variables-and-types/TestErrors.nl
cp examples/nested_simple_test.nl examples-new/04-pattern-matching/NestedSimpleTest.nl

# Placeholder for ASP.NET demo (to be created)
mkdir -p examples-new/13-aspnet-demo/TaskManagementApi

echo "Examples reorganized into examples-new/"
echo "Review the structure, then:"
echo "  rm -rf examples"
echo "  mv examples-new examples"
