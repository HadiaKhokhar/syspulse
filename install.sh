#!/bin/bash
# ================================================================
# SYSPULSE - Installer
# ================================================================

echo "============================================"
echo "  💓 SYSPULSE - System Health Dashboard"
echo "  Installer v1.0"
echo "============================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ASCII Art
echo -e "${RED}"
echo "███████╗██╗   ██╗███████╗██████╗ ██╗   ██╗██╗     ███████╗███████╗"
echo "██╔════╝╚██╗ ██╔╝██╔════╝██╔══██╗██║   ██║██║     ██╔════╝██╔════╝"
echo "███████╗ ╚████╔╝ ███████╗██████╔╝██║   ██║██║     ███████╗█████╗  "
echo "╚════██║  ╚██╔╝  ╚════██║██╔═══╝ ██║   ██║██║     ╚════██║██╔══╝  "
echo "███████║   ██║   ███████║██║     ╚██████╔╝███████╗███████║███████╗"
echo "╚══════╝   ╚═╝   ╚══════╝╚═╝      ╚═════╝ ╚══════╝╚══════╝╚══════╝"
echo -e "${NC}"
echo -e "${CYAN}   \"Keep your system's pulse\"${NC}"
echo ""

# Resolve the directory this installer lives in, so it works
# regardless of where it's invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Check if monitor.sh exists
if [ ! -f "monitor.sh" ]; then
    echo -e "${RED}❌ monitor.sh not found!${NC}"
    exit 1
fi

# Check if template.html exists
if [ ! -f "template.html" ]; then
    echo -e "${RED}❌ template.html not found!${NC}"
    echo -e "${YELLOW}   monitor.sh needs template.html in the same folder to generate the dashboard.${NC}"
    exit 1
fi

# Make executable
chmod +x monitor.sh
echo -e "${GREEN}✅ monitor.sh is executable${NC}"

# Install Python (for web server)
echo -e "${YELLOW}📦 Checking dependencies...${NC}"
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}Installing Python3...${NC}"
    sudo apt update
    sudo apt install python3 -y
fi
echo -e "${GREEN}✅ Python3 installed${NC}"

# Create report directory (inside the project folder, next to the script)
mkdir -p "$SCRIPT_DIR/reports"
echo -e "${GREEN}✅ Report directory created: $SCRIPT_DIR/reports${NC}"

# Setup cron
echo ""
echo -e "${YELLOW}🕐 Schedule automatic monitoring?${NC}"
read -p "Add to cron to run every 5 minutes? (y/n): " answer

if [[ $answer == "y" || $answer == "Y" ]]; then
    SCRIPT_PATH="$SCRIPT_DIR/monitor.sh"
    (crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT_PATH") | crontab -
    echo -e "${GREEN}✅ Cron job added (every 5 minutes)${NC}"
fi

# Run initial report
echo ""
echo -e "${YELLOW}📊 Generating initial report...${NC}"
./monitor.sh
echo -e "${GREEN}✅ Initial report generated${NC}"

# Checks whether a TCP port is already taken on localhost.
is_port_in_use() {
    local port="$1"
    (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null
    local result=$?
    exec 3>&- 2>/dev/null
    return $result
}

# Starting from a preferred port, finds the first free one.
find_free_port() {
    local port="$1"
    while is_port_in_use "$port"; do
        port=$((port + 1))
    done
    echo "$port"
}

# Start web server
echo ""
echo -e "${YELLOW}🌐 Start web server to view dashboard?${NC}"
read -p "Start Python web server on port 8080? (y/n): " answer

if [[ $answer == "y" || $answer == "Y" ]]; then
    DEFAULT_PORT=8080
    PORT=$(find_free_port "$DEFAULT_PORT")

    if [ "$PORT" != "$DEFAULT_PORT" ]; then
        echo -e "${YELLOW}⚠️  Port $DEFAULT_PORT is already in use (likely a web server left running from a previous install).${NC}"
        echo -e "${YELLOW}   Using port $PORT instead.${NC}"
        echo -e "${YELLOW}   To free up $DEFAULT_PORT yourself: fuser -k ${DEFAULT_PORT}/tcp${NC}"
    fi

    cd "$SCRIPT_DIR/reports" || exit 1
    python3 -m http.server "$PORT" >/dev/null 2>&1 &
    SERVER_PID=$!
    sleep 0.3

    if kill -0 "$SERVER_PID" 2>/dev/null; then
        echo -e "${GREEN}✅ Web server started on port $PORT${NC}"
        echo "   🔗 View at: http://localhost:$PORT/dashboard_latest.html"
        echo "   🔗 Or: http://$(hostname -I | awk '{print $1}'):$PORT/dashboard_latest.html"
    else
        echo -e "${RED}❌ Web server failed to start.${NC}"
        echo -e "${YELLOW}   You can still open the dashboard directly in a browser (see path below).${NC}"
    fi
    cd "$SCRIPT_DIR" || exit 1
fi

echo ""
echo "============================================"
echo -e "${RED}💓 SYSPULSE${NC}"
echo -e "${GREEN}✅ Installation complete!${NC}"
echo "============================================"
echo ""
echo "📁 Project   : $SCRIPT_DIR"
echo "📁 Dashboard : $SCRIPT_DIR/reports/dashboard_latest.html"
echo "📝 Log       : $SCRIPT_DIR/reports/monitor.log"
echo ""
echo "To run manually: ./monitor.sh"
echo "To view dashboard:"
echo "  firefox \"$SCRIPT_DIR/reports/dashboard_latest.html\""
echo ""
echo -e "${CYAN}💓 \"Keep your system's pulse\"${NC}"