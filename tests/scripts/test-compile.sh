#!/bin/bash
# Minimal repro script to test compilation with timeout

set -e

# Use test file from command line arg or default
TEST_FILE=${1:-/tmp/test-minimal.nl}

if [ ! -f "$TEST_FILE" ]; then
    # Create a minimal test file
    cat > /tmp/test-minimal.nl <<'EOF'
import System

func Main() {
    print "hello"
}
EOF
    TEST_FILE=/tmp/test-minimal.nl
fi

echo "Testing with: $TEST_FILE"

# Create a test project
rm -rf /tmp/test-nsharp-project
mkdir -p /tmp/test-nsharp-project
cd /tmp/test-nsharp-project

# Create minimal project files
cat > project.yml <<'EOF'
name: TestProject
version: 1.0.0
targetFramework: net10.0
outputType: exe
EOF

cat > Hello.csproj <<'EOF'
<Project Sdk="NSharpLang.Sdk" />
EOF

cat > global.json <<'EOF'
{
  "sdk": {
    "version": "10.0.100"
  },
  "msbuild-sdks": {
    "NSharpLang.Sdk": "0.1.0"
  }
}
EOF

cp "$TEST_FILE" Program.nl

echo "Starting build with 5 second timeout..."
dotnet build > /tmp/build-output.txt 2>&1 &
BUILD_PID=$!

# Wait up to 5 seconds
for i in {1..50}; do
    if ! kill -0 $BUILD_PID 2>/dev/null; then
        # Process finished
        wait $BUILD_PID
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ]; then
            echo "✅ BUILD SUCCEEDED"
            exit 0
        else
            echo "❌ BUILD FAILED"
            cat /tmp/build-output.txt
            exit $EXIT_CODE
        fi
    fi
    sleep 0.1
done

# Timeout - kill the process
echo "❌ BUILD TIMED OUT (5 seconds)"
kill -9 $BUILD_PID 2>/dev/null
pkill -9 -f "dotnet build" 2>/dev/null
echo "Last output:"
tail -20 /tmp/build-output.txt
exit 124
