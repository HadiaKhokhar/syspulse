#!/bin/bash
# ================================================================
# SYSPULSE - System Health Dashboard
# Keep your system's pulse
# ================================================================
#
# Project layout:
#   
#syspulse/
#├── README.md                          # Documentation with ASCII art
#├── monitor.sh                         # Main monitoring script
#├── template.html                      # HTML template used to render the dashboard
#├── install.sh                         # One-click installer
#├── uninstall.sh                       # Uninstaller
#├── .gitignore                         # Git ignore
#├── LICENSE                            # MIT License
#└── reports/                           # Generated reports (auto-created)
#    ├── dashboard_latest.html          # Always the most recent report
#   ├── dashboard_YYYYMMDD_HHMMSS.html # Timestamped snapshot per run
#    ├── monitor.log
#    └── alerts.log

# ================================================================

# ================================================================
# CONFIGURATION
# ================================================================

# Resolve the directory this script lives in, so paths work
# regardless of where it's invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEMPLATE_FILE="$SCRIPT_DIR/template.html"
REPORT_DIR="$SCRIPT_DIR/reports"
TIMESTAMP_TAG="$(date '+%Y%m%d_%H%M%S')"
HTML_FILE="$REPORT_DIR/dashboard_${TIMESTAMP_TAG}.html"
LATEST_FILE="$REPORT_DIR/dashboard_latest.html"
LOG_FILE="$REPORT_DIR/monitor.log"
ALERT_LOG="$REPORT_DIR/alerts.log"

# Alert thresholds
DISK_THRESHOLD=80
MEMORY_THRESHOLD=90
CPU_THRESHOLD=80

# ================================================================
# FUNCTIONS
# ================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_date() {
    date '+%Y-%m-%d %H:%M:%S'
}

get_system_info() {
    local hostname=$(hostname)
    local kernel=$(uname -r)
    local os=$(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")
    local uptime=$(uptime -p 2>/dev/null | sed 's/up //' || echo "Unknown")

    cat << EOF
Hostname: $hostname
Kernel: $kernel
OS: $os
Uptime: $uptime
EOF
}

get_disk_usage() {
    df -h | grep -E '^/dev/' | awk '{print $6 "|" $5 "|" $2 "|" $4}' 2>/dev/null
}

get_memory_usage() {
    local total=$(free -m | grep Mem | awk '{print $2}')
    local used=$(free -m | grep Mem | awk '{print $3}')
    local free=$(free -m | grep Mem | awk '{print $4}')
    local available=$(free -m | grep Mem | awk '{print $7}')
    local percent=$((used * 100 / total))

    echo "Total: ${total}MB | Used: ${used}MB | Free: ${free}MB | Available: ${available}MB | Usage: ${percent}%"
}

get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "0"
}

get_top_processes() {
    ps aux --sort=-%cpu | head -6 | tail -5 | awk '{print $11 "|" $3 "%" "|" $4 "%"}' 2>/dev/null
}

get_network_info() {
    ip addr show | grep -E 'inet ' | grep -v 127.0.0.1 | awk '{print $7 "|" $2}' | head -3 2>/dev/null
}

check_alerts() {
    local alerts=""

    # Check disk
    while read line; do
        if [ -n "$line" ]; then
            local usage=$(echo $line | awk '{print $5}' | sed 's/%//')
            local mount=$(echo $line | awk '{print $6}')
            if [ "$usage" -gt "$DISK_THRESHOLD" ] 2>/dev/null; then
                alerts="${alerts}CRITICAL: Disk $mount is at ${usage}% usage!\n"
            fi
        fi
    done < <(df -h | grep -E '^/dev/')

    # Check memory
    local mem_usage=$(free -m | grep Mem | awk '{printf "%.0f", ($3/$2)*100}' 2>/dev/null)
    if [ -n "$mem_usage" ] && [ "$mem_usage" -gt "$MEMORY_THRESHOLD" ] 2>/dev/null; then
        alerts="${alerts}CRITICAL: Memory usage at ${mem_usage}%!\n"
    fi

    # Check CPU
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null)
    if [ -n "$cpu_usage" ] && [ "$(echo "$cpu_usage > $CPU_THRESHOLD" | bc)" -eq 1 ] 2>/dev/null; then
        alerts="${alerts}CRITICAL: CPU usage at ${cpu_usage}%!\n"
    fi

    echo -e "$alerts"
}

# ---- HTML fragment builders (used to fill the template placeholders) ----

build_alerts_section() {
    local alerts="$1"
    if [ -n "$alerts" ] && [ "$alerts" != "-e " ]; then
        cat << EOF
        <div class="alerts">
            <strong>Critical Alerts Detected</strong>
            <pre>$alerts</pre>
        </div>
EOF
    else
        cat << EOF
        <div class="alerts ok">
            <div class="no-alerts">All systems operational — no critical alerts</div>
        </div>
EOF
    fi
}

build_system_info_rows() {
    local system_info="$1"
    echo "$system_info" | while IFS=':' read -r key value; do
        if [ -n "$key" ] && [ -n "$value" ]; then
            echo "                <div class=\"metric\"><span class=\"key\">${key}</span><span class=\"val\">${value}</span></div>"
        fi
    done
}

build_memory_rows() {
    local memory_info="$1"
    echo "$memory_info" | awk -F'|' '{
        for (i=1; i<=NF; i++) {
            split($i, a, ":");
            gsub(/^[ \t]+|[ \t]+$/, "", a[1]);
            gsub(/^[ \t]+|[ \t]+$/, "", a[2]);
            if (length(a[1]) > 0 && length(a[2]) > 0) {
                print "                <div class=\"metric\"><span class=\"key\">" a[1] "</span><span class=\"val\">" a[2] "</span></div>"
            }
        }
    }'
}

build_disk_rows() {
    local disk_usage="$1"
    echo "$disk_usage" | while IFS='|' read mount usage total used; do
        if [ -n "$mount" ]; then
            local usage_num=$(echo "$usage" | sed 's/%//')
            local color="status-good"
            local fill="fill-good"
            if [ "$usage_num" -gt 80 ] 2>/dev/null; then
                color="status-danger"; fill="fill-danger"
            elif [ "$usage_num" -gt 60 ] 2>/dev/null; then
                color="status-warning"; fill="fill-warning"
            fi
            cat << EOF
                <div class="metric"><span class="key">$mount</span><span class="val $color">$usage</span></div>
                <div class="progress-bar">
                    <div class="progress-fill $fill" style="width: $usage_num%"></div>
                </div>
EOF
        fi
    done
}

build_process_rows() {
    local top_cpu="$1"
    if [ -n "$top_cpu" ]; then
        echo "$top_cpu" | while IFS='|' read process cpu mem; do
            if [ -n "$process" ]; then
                local pname=$(basename "$process" 2>/dev/null || echo "$process")
                echo "                <div class=\"metric\"><span class=\"key\">$pname</span><span class=\"val status-warning\">$cpu</span></div>"
            fi
        done
    else
        echo "                <div class=\"metric\"><span class=\"key\">No processes found</span></div>"
    fi
}

build_network_rows() {
    local network_info="$1"
    if [ -n "$network_info" ]; then
        echo "$network_info" | while IFS='|' read interface ip; do
            if [ -n "$interface" ]; then
                echo "                <div class=\"metric\"><span class=\"key\">$interface</span><span class=\"val\">${ip%%/*}</span></div>"
            fi
        done
    else
        echo "                <div class=\"metric\"><span class=\"key\">No network interfaces found</span></div>"
    fi
}

# Escapes a string for safe use as the replacement side of bash's
# ${var//search/replacement} pattern substitution (handles & and \).
escape_for_replace() {
    printf '%s' "$1"
}

generate_html() {
    local timestamp=$(get_date)
    local hostname=$(hostname)

    # Gather data
    local system_info=$(get_system_info)
    local disk_usage=$(get_disk_usage)
    local memory_info=$(get_memory_usage)
    local cpu_info=$(get_cpu_usage)
    local top_cpu=$(get_top_processes)
    local network_info=$(get_network_info)
    local alerts=$(check_alerts)

    mkdir -p "$REPORT_DIR"

    if [ ! -f "$TEMPLATE_FILE" ]; then
        log "❌ Template not found at $TEMPLATE_FILE"
        exit 1
    fi

    # Memory color/fill
    local mem_percent=$(echo "$memory_info" | grep -o "Usage: [0-9]*%" | grep -o '[0-9]*')
    [ -z "$mem_percent" ] && mem_percent=0
    local mem_color="status-good"
    local mem_fill="fill-good"
    if [ "$mem_percent" -gt 80 ] 2>/dev/null; then
        mem_color="status-danger"; mem_fill="fill-danger"
    elif [ "$mem_percent" -gt 60 ] 2>/dev/null; then
        mem_color="status-warning"; mem_fill="fill-warning"
    fi

    # CPU color/fill
    local cpu_color="status-good"
    local cpu_fill="fill-good"
    if [ -n "$cpu_info" ] && [ "$(echo "$cpu_info > 80" | bc)" -eq 1 ] 2>/dev/null; then
        cpu_color="status-danger"; cpu_fill="fill-danger"
    elif [ -n "$cpu_info" ] && [ "$(echo "$cpu_info > 60" | bc)" -eq 1 ] 2>/dev/null; then
        cpu_color="status-warning"; cpu_fill="fill-warning"
    fi

    # Build fragments
    local alerts_section=$(build_alerts_section "$alerts")
    local system_info_rows=$(build_system_info_rows "$system_info")
    local memory_rows=$(build_memory_rows "$memory_info")
    local disk_rows=$(build_disk_rows "$disk_usage")
    local process_rows=$(build_process_rows "$top_cpu")
    local network_rows=$(build_network_rows "$network_info")
    local footer_date=$(date)

    # Load template and substitute placeholders
    local html
    html=$(cat "$TEMPLATE_FILE")

    html="${html//__TIMESTAMP__/$timestamp}"
    html="${html//__HOSTNAME__/$hostname}"
    html="${html//__ALERTS_SECTION__/$alerts_section}"
    html="${html//__SYSTEM_INFO_ROWS__/$system_info_rows}"
    html="${html//__MEMORY_PERCENT__/$mem_percent}"
    html="${html//__MEMORY_COLOR__/$mem_color}"
    html="${html//__MEMORY_FILL__/$mem_fill}"
    html="${html//__MEMORY_ROWS__/$memory_rows}"
    html="${html//__CPU_PERCENT__/$cpu_info}"
    html="${html//__CPU_COLOR__/$cpu_color}"
    html="${html//__CPU_FILL__/$cpu_fill}"
    html="${html//__DISK_ROWS__/$disk_rows}"
    html="${html//__PROCESS_ROWS__/$process_rows}"
    html="${html//__NETWORK_ROWS__/$network_rows}"
    html="${html//__FOOTER_DATE__/$footer_date}"

    printf '%s\n' "$html" > "$HTML_FILE"
    cp "$HTML_FILE" "$LATEST_FILE"

    log "✅ Dashboard generated: $HTML_FILE"
}

# ================================================================
# MAIN
# ================================================================

main() {
    mkdir -p "$REPORT_DIR"

    log "============================================"
    log "💓 SysPulse - System Health Monitor"
    log "   \"Keep your system's pulse\""
    log "============================================"

    generate_html

    if [ -f "$HTML_FILE" ]; then
        log "✅ Dashboard created successfully"
        echo ""
        echo "📁 Dashboard : $HTML_FILE"
        echo "📁 Latest    : $LATEST_FILE"
        echo ""
        echo "To view: firefox \"$HTML_FILE\""
    else
        log "❌ Dashboard creation failed!"
        exit 1
    fi

    log "============================================"
    exit 0
}

main