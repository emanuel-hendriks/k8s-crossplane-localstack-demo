#!/bin/bash

# DynamoDB Admin Interface Background Service
# Starts port-forward in background and keeps it running

set -euo pipefail

# Colors for output
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_success() { echo -e "${GREEN} $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED} $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/.admin-port-forward.pid"

case "${1:-start}" in
    "start")
        echo "Starting DynamoDB Admin Interface (Background)"
        echo "================================================"
        
        # Check if already running
        if [ -f "$PID_FILE" ]; then
            OLD_PID=$(cat "$PID_FILE")
            if kill -0 "$OLD_PID" 2>/dev/null; then
                print_warning "Admin interface is already running (PID: $OLD_PID)"
                print_info "Access at: http://localhost:8001"
                print_info "To stop: ./pipeline/admin-bg.sh stop"
                exit 0
            else
                rm -f "$PID_FILE"
            fi
        fi
        
        # Check if service exists
        if ! kubectl get svc dynamodb-admin-dynamodb-admin >/dev/null 2>&1; then
            print_error "DynamoDB Admin service not found"
            print_info "Run deployment first: ./pipeline/deploy.sh"
            exit 1
        fi
        
        # Start port-forward in background
        print_info "Starting port-forward in background..."
        kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001 >/dev/null 2>&1 &
        PORT_FORWARD_PID=$!
        
        # Save PID
        echo "$PORT_FORWARD_PID" > "$PID_FILE"
        
        # Wait and test
        sleep 3
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8001 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" = "200" ]; then
            print_success "DynamoDB Admin interface started successfully!"
            print_info "🌐 URL: http://localhost:8001"
            print_info "📊 Table: justtrack-dev-devops-consumer-events"
            print_info "🔧 PID: $PORT_FORWARD_PID"
            echo ""
            print_info "Commands:"
            echo "  • Open browser: open http://localhost:8001"
            echo "  • Stop service: ./pipeline/admin-bg.sh stop"
            echo "  • Check status: ./pipeline/admin-bg.sh status"
            
            # Try to open browser automatically
            if command -v open >/dev/null 2>&1; then
                print_info "Opening browser..."
                open http://localhost:8001
            fi
        else
            print_error "Failed to start admin interface"
            kill "$PORT_FORWARD_PID" 2>/dev/null || true
            rm -f "$PID_FILE"
            exit 1
        fi
        ;;
        
    "stop")
        echo "Stopping DynamoDB Admin Interface"
        echo "===================================="
        
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if kill -0 "$PID" 2>/dev/null; then
                kill "$PID"
                print_success "Admin interface stopped (PID: $PID)"
            else
                print_warning "Process not running (PID: $PID)"
            fi
            rm -f "$PID_FILE"
        else
            print_warning "No admin interface running"
        fi
        ;;
        
    "status")
        echo "DynamoDB Admin Interface Status"
        echo "=================================="
        
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if kill -0 "$PID" 2>/dev/null; then
                print_success "Running (PID: $PID)"
                HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8001 2>/dev/null || echo "000")
                if [ "$HTTP_CODE" = "200" ]; then
                    print_success "Interface accessible at http://localhost:8001"
                else
                    print_warning "Process running but interface not accessible"
                fi
            else
                print_error "Not running (stale PID file)"
                rm -f "$PID_FILE"
            fi
        else
            print_info "Not running"
        fi
        ;;
        
    "restart")
        echo "Restarting DynamoDB Admin Interface"
        echo "======================================"
        "$0" stop
        sleep 2
        "$0" start
        ;;
        
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        echo ""
        echo "Commands:"
        echo "  start   - Start admin interface in background"
        echo "  stop    - Stop admin interface"
        echo "  status  - Check if admin interface is running"
        echo "  restart - Restart admin interface"
        exit 1
        ;;
esac
