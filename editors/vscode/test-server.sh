#!/bin/bash

echo "Testing N# Language Server..."
echo ""

cd "$(dirname "$0")/server"

if [ ! -f "LanguageServer.dll" ]; then
    echo "❌ LanguageServer.dll not found!"
    echo "Run: npm run build-server"
    exit 1
fi

echo "✅ LanguageServer.dll found"
echo ""

echo "Starting server (will timeout after 5 seconds)..."
echo ""

# Start server in background
dotnet LanguageServer.dll 2>&1 &
SERVER_PID=$!

# Give it time to start
sleep 2

# Check if still running
if ps -p $SERVER_PID > /dev/null; then
    echo "✅ Server started successfully (PID: $SERVER_PID)"
    echo ""
    echo "Checking log file..."
    if [ -f ~/.nsharp/lsp.log ]; then
        echo "✅ Log file created at ~/.nsharp/lsp.log"
        echo ""
        echo "Last 10 lines:"
        tail -10 ~/.nsharp/lsp.log
    else
        echo "⚠️  No log file yet"
    fi

    # Kill the server
    kill $SERVER_PID 2>/dev/null
    echo ""
    echo "✅ Test complete - server can start"
else
    echo "❌ Server crashed or exited"
    echo ""
    echo "Try running manually:"
    echo "  cd server"
    echo "  dotnet LanguageServer.dll"
    exit 1
fi
