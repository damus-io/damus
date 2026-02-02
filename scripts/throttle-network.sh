#!/bin/bash
#
# throttle-network.sh - Simulate poor network conditions using macOS dummynet
#
# Usage:
#   ./throttle-network.sh start 3g      # Start 3G simulation
#   ./throttle-network.sh start edge    # Start Edge simulation
#   ./throttle-network.sh stop          # Stop throttling
#   ./throttle-network.sh status        # Show current status
#
# Requires: sudo (uses pfctl/dnctl)
#
# This affects ALL network traffic on the machine, including:
# - HTTP/HTTPS requests
# - WebSocket connections (wss://)
# - Connections to real external servers
#

set -e

ANCHOR_NAME="damus_throttle"

# Network profiles (bandwidth in Kbit/s, delay in ms, packet loss ratio)
declare -A PROFILES
PROFILES[3g]="bw 780Kbit/s delay 100 plr 0.01"
PROFILES[3gfast]="bw 1500Kbit/s delay 75 plr 0.005"
PROFILES[3gslow]="bw 400Kbit/s delay 200 plr 0.02"
PROFILES[edge]="bw 240Kbit/s delay 400 plr 0.01"
PROFILES[2g]="bw 50Kbit/s delay 500 plr 0.05"
PROFILES[lte]="bw 12000Kbit/s delay 50 plr 0.001"
PROFILES[verybad]="bw 100Kbit/s delay 500 plr 0.10"
PROFILES[lossy]="bw 10000Kbit/s delay 10 plr 0.05"

usage() {
    echo "Usage: $0 <command> [profile]"
    echo ""
    echo "Commands:"
    echo "  start <profile>  Start network throttling"
    echo "  stop             Stop network throttling"
    echo "  status           Show current throttling status"
    echo ""
    echo "Profiles:"
    echo "  3g       780 Kbps, 100ms latency, 1% loss"
    echo "  3gfast   1.5 Mbps, 75ms latency, 0.5% loss"
    echo "  3gslow   400 Kbps, 200ms latency, 2% loss"
    echo "  edge     240 Kbps, 400ms latency, 1% loss"
    echo "  2g       50 Kbps, 500ms latency, 5% loss"
    echo "  lte      12 Mbps, 50ms latency, 0.1% loss"
    echo "  verybad  100 Kbps, 500ms latency, 10% loss"
    echo "  lossy    10 Mbps, 10ms latency, 5% loss (tests packet loss)"
    echo ""
    echo "Example:"
    echo "  sudo $0 start 3g"
    echo "  # ... run tests ..."
    echo "  sudo $0 stop"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run with sudo"
        echo "  sudo $0 $*"
        exit 1
    fi
}

start_throttle() {
    local profile=$1

    if [[ -z "$profile" ]]; then
        echo "Error: Profile required"
        usage
    fi

    if [[ -z "${PROFILES[$profile]}" ]]; then
        echo "Error: Unknown profile '$profile'"
        usage
    fi

    local config="${PROFILES[$profile]}"

    echo "Starting network throttle with profile: $profile"
    echo "  Config: $config"

    # Stop any existing throttling first
    stop_throttle 2>/dev/null || true

    # Create dummynet pipe
    dnctl pipe 1 config $config

    # Create PF anchor rules
    (
        echo "dummynet in quick proto tcp from any to any pipe 1"
        echo "dummynet in quick proto udp from any to any pipe 1"
        echo "dummynet out quick proto tcp from any to any pipe 1"
        echo "dummynet out quick proto udp from any to any pipe 1"
    ) | pfctl -a "$ANCHOR_NAME" -f -

    # Enable PF if not already enabled
    pfctl -E 2>/dev/null || true

    echo "✓ Network throttling enabled"
    echo ""
    echo "To stop: sudo $0 stop"
}

stop_throttle() {
    echo "Stopping network throttle..."

    # Flush anchor rules
    pfctl -a "$ANCHOR_NAME" -F all 2>/dev/null || true

    # Flush dummynet pipes
    dnctl -q flush 2>/dev/null || true

    echo "✓ Network throttling disabled"
}

show_status() {
    echo "=== PF Status ==="
    pfctl -s info 2>/dev/null | head -5 || echo "PF not running"

    echo ""
    echo "=== Dummynet Pipes ==="
    dnctl list 2>/dev/null || echo "No pipes configured"

    echo ""
    echo "=== Anchor Rules ($ANCHOR_NAME) ==="
    pfctl -a "$ANCHOR_NAME" -s rules 2>/dev/null || echo "No rules in anchor"
}

# Main
case "${1:-}" in
    start)
        check_root
        start_throttle "$2"
        ;;
    stop)
        check_root
        stop_throttle
        ;;
    status)
        show_status
        ;;
    *)
        usage
        ;;
esac
