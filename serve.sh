#!/bin/bash
##
## Local Web Server for Godot Game
##
## This script starts a local HTTP server to test the web build.
## Godot web exports require proper HTTP headers for SharedArrayBuffer support.
##

set -e  # Exit on error

# Configuration
PORT=8000
BUILD_DIR="build/web"
DOWNLOAD_DIR="web-build"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Godot Web Game Local Server${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to find which directory to serve
find_web_directory() {
    if [ -d "$BUILD_DIR" ]; then
        echo "$BUILD_DIR"
    elif [ -d "$DOWNLOAD_DIR" ]; then
        echo "$DOWNLOAD_DIR"
    else
        echo ""
    fi
}

# Find the web directory
WEB_DIR=$(find_web_directory)

if [ -z "$WEB_DIR" ]; then
    echo -e "${RED}❌ Error: No web build found!${NC}"
    echo ""
    echo "Please build the game first:"
    echo "  1. Open Godot"
    echo "  2. Go to Project → Export"
    echo "  3. Select 'Web' preset"
    echo "  4. Click 'Export Project'"
    echo ""
    echo "Or download the web-build artifact from GitHub Actions"
    echo "and extract it to ./web-build/"
    exit 1
fi

echo -e "${GREEN}✅ Found web build in: ${WEB_DIR}${NC}"
echo ""

# Check if index.html exists
if [ ! -f "$WEB_DIR/index.html" ]; then
    echo -e "${RED}❌ Error: index.html not found in ${WEB_DIR}${NC}"
    exit 1
fi

# Function to check if port is in use
check_port() {
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1 || netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
        return 0
    else
        return 1
    fi
}

# Find available port
while check_port; do
    echo -e "${YELLOW}⚠️  Port $PORT is already in use${NC}"
    PORT=$((PORT + 1))
done

echo -e "${BLUE}🌐 Starting server on port ${PORT}...${NC}"
echo ""

# Detect Python version and start appropriate server
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
else
    echo -e "${RED}❌ Error: Python not found!${NC}"
    echo "Please install Python 3 to run the local server."
    echo ""
    echo "Alternatives:"
    echo "  - Install Python: https://www.python.org/downloads/"
    echo "  - Use Node.js: npm install -g http-server && http-server $WEB_DIR -p $PORT"
    exit 1
fi

# Get Python version
PYTHON_VERSION=$($PYTHON_CMD --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1)

echo -e "${GREEN}✅ Using: $PYTHON_CMD${NC}"
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}🎮 Server is running!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "  ${GREEN}Local:${NC}    http://localhost:$PORT"
echo -e "  ${GREEN}Network:${NC}  http://$(hostname -I | awk '{print $1}'):$PORT"
echo ""
echo -e "${YELLOW}📝 Instructions:${NC}"
echo "  1. Open your browser"
echo "  2. Navigate to: ${BLUE}http://localhost:$PORT${NC}"
echo "  3. Wait for the game to load"
echo ""
echo -e "${YELLOW}🛑 To stop the server:${NC} Press Ctrl+C"
echo ""
echo -e "${BLUE}========================================${NC}"
echo ""

# Try to open browser automatically (optional)
if command -v xdg-open &> /dev/null; then
    echo -e "${BLUE}🌐 Opening browser...${NC}"
    sleep 1
    xdg-open "http://localhost:$PORT" &
elif command -v open &> /dev/null; then
    echo -e "${BLUE}🌐 Opening browser...${NC}"
    sleep 1
    open "http://localhost:$PORT" &
fi

# Start the server
cd "$WEB_DIR"

if [ "$PYTHON_VERSION" = "3" ]; then
    # Python 3
    $PYTHON_CMD -m http.server $PORT
else
    # Python 2 (fallback)
    $PYTHON_CMD -m SimpleHTTPServer $PORT
fi
