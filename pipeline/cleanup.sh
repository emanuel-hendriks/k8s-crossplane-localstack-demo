#!/bin/bash

# Safe Partial Cleanup - Preserves Crossplane Infrastructure
# Removes applications and AWS resources for clean redeployment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/.admin-port-forward.pid"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Safe Partial Cleanup${NC}"
echo "===================="
echo "Preserving: Crossplane, provider configuration"
echo "Removing: Applications, AWS resources, LocalStack"
echo ""

# 1. Stop admin interface
echo -e "${BLUE}Stopping admin interface...${NC}"
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$PID" ]; then
        kill "$PID" 2>/dev/null || true
        echo -e "${GREEN}Admin interface stopped${NC}"
    fi
    rm -f "$PID_FILE"
else
    echo "Admin interface not running"
fi

# 2. Remove Helm applications
echo ""
echo -e "${BLUE}Removing Helm applications...${NC}"
for app in producer consumer dynamodb-admin; do
    if helm list --short | grep -q "^$app$" 2>/dev/null; then
        echo "Uninstalling $app..."
        helm uninstall "$app" 2>/dev/null || true
        echo -e "${GREEN}$app removed${NC}"
    else
        echo "$app not found"
    fi
done

# 3. Remove AWS resources (but keep provider)
echo ""
echo -e "${BLUE}Removing AWS resources...${NC}"
kubectl delete topics --all 2>/dev/null || true
kubectl delete queues --all 2>/dev/null || true
kubectl delete tables --all 2>/dev/null || true
kubectl delete subscriptions --all 2>/dev/null || true
echo -e "${GREEN}AWS resources removed${NC}"

# 4. Remove LocalStack
echo ""
echo -e "${BLUE}Removing LocalStack...${NC}"
kubectl delete namespace localstack 2>/dev/null || true
echo -e "${GREEN}LocalStack removed${NC}"

# 5. Clean test resources
echo ""
echo -e "${BLUE}Cleaning test resources...${NC}"
kubectl delete pods -l run=aws-test 2>/dev/null || true
kubectl delete pods -l run=aws-verify 2>/dev/null || true
kubectl delete pods -l run=localstack-test 2>/dev/null || true
kubectl delete pods --field-selector=status.phase==Succeeded 2>/dev/null || true
kubectl delete pods --field-selector=status.phase==Failed 2>/dev/null || true
echo -e "${GREEN}Test resources cleaned${NC}"

# 6. Verification
echo ""
echo -e "${BLUE}Verification...${NC}"
PODS=$(kubectl get pods -l 'app.kubernetes.io/instance in (producer,consumer,dynamodb-admin)' 2>/dev/null | wc -l)
RELEASES=$(helm list --short | grep -E '^(producer|consumer|dynamodb-admin)$' 2>/dev/null | wc -l)
CROSSPLANE=$(kubectl get deployment crossplane -n crossplane-system 2>/dev/null | wc -l)
PROVIDER=$(kubectl get provider.pkg.crossplane.io/provider-aws 2>/dev/null | wc -l)

if [ "$PODS" -eq 0 ] && [ "$RELEASES" -eq 0 ]; then
    echo -e "${GREEN}SUCCESS: Applications cleaned${NC}"
else
    echo -e "${YELLOW}WARNING: Some application resources may remain${NC}"
fi

if [ "$CROSSPLANE" -gt 0 ] && [ "$PROVIDER" -gt 0 ]; then
    echo -e "${GREEN}SUCCESS: Crossplane and provider preserved${NC}"
else
    echo -e "${YELLOW}WARNING: Crossplane or provider missing${NC}"
fi

echo ""
echo -e "${GREEN}PARTIAL CLEANUP COMPLETED${NC}"
echo "=========================="
echo "Preserved:"
echo "  • Crossplane deployment"
echo "  • AWS provider"
echo ""
echo "Removed:"
echo "  • Applications (producer, consumer, dynamodb-admin)"
echo "  • AWS resources (topics, queues, tables, subscriptions)"
echo "  • LocalStack"
echo ""
echo "Ready to test: ./deploy.sh"
