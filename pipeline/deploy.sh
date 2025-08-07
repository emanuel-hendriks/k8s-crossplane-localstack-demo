#!/bin/bash

# Deployment Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PID_FILE="$SCRIPT_DIR/.admin-port-forward.pid"

# Simple colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Minimal Safe Deployment${NC}"
echo "======================="
echo "Started: $(date)"
echo ""

# 1. Prerequisites check
echo -e "${BLUE}Checking prerequisites...${NC}"
for tool in kubectl helm docker curl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: $tool not found"
        exit 1
    fi
done
echo -e "${GREEN}Prerequisites OK${NC}"

# 2. Crossplane installation
echo ""
echo -e "${BLUE}Setting up Crossplane...${NC}"
helm repo add crossplane-stable https://charts.crossplane.io/stable 2>/dev/null || true
helm repo update crossplane-stable 2>/dev/null || true

if kubectl get deployment crossplane -n crossplane-system >/dev/null 2>&1; then
    echo "Crossplane already installed"
else
    echo "Installing Crossplane..."
    helm install crossplane crossplane-stable/crossplane \
        --namespace crossplane-system \
        --create-namespace \
        --wait --timeout=300s
fi
echo -e "${GREEN}Crossplane ready${NC}"

# 3. AWS Provider Setup

echo ""
echo -e "${BLUE}Setting up AWS Provider...${NC}"

# Apply deployment runtime config and provider
kubectl apply -f "$PROJECT_ROOT/crossplane/deployment-runtime-config.yaml" 2>/dev/null || true
kubectl apply -f "$PROJECT_ROOT/crossplane/provider.yaml" 2>/dev/null || true

# Wait for provider to become healthy
echo "Waiting for AWS provider..."
for i in {1..12}; do
    PROVIDER_STATUS=$(kubectl get provider.pkg.crossplane.io/provider-aws -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' 2>/dev/null || echo "")
    PROVIDER_INSTALLED=$(kubectl get provider.pkg.crossplane.io/provider-aws -o jsonpath='{.status.conditions[?(@.type=="Installed")].status}' 2>/dev/null || echo "")
    
    if [ "$PROVIDER_STATUS" = "True" ] && [ "$PROVIDER_INSTALLED" = "True" ]; then
        echo -e "${GREEN}AWS provider ready${NC}"
        break
    elif [ "$i" -eq 12 ]; then
        echo -e "${RED}ERROR: AWS provider failed to become healthy${NC}"
        echo "Check: kubectl describe provider.pkg.crossplane.io/provider-aws"
        exit 1
    fi
    echo "Attempt $i/12 - Provider Status: Healthy=$PROVIDER_STATUS, Installed=$PROVIDER_INSTALLED"
    sleep 10
done

# 5. LocalStack
echo ""
echo -e "${BLUE}Deploying LocalStack...${NC}"
kubectl create namespace localstack --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
kubectl apply -f "$PROJECT_ROOT/k8s/localstack.yaml" 2>/dev/null || true

echo "Waiting for LocalStack..."
kubectl wait --for=condition=available deployment/localstack -n localstack --timeout=300s 2>/dev/null || true
echo -e "${GREEN}LocalStack ready${NC}"

# 6. Provider Configuration
echo ""
echo -e "${BLUE}Configuring provider...${NC}"
kubectl apply -f "$PROJECT_ROOT/crossplane/provider-config.yaml" 2>/dev/null || true
echo -e "${GREEN}Provider configured${NC}"

# 7. AWS Resources
echo ""
echo -e "${BLUE}Creating AWS resources...${NC}"
kubectl apply -f "$PROJECT_ROOT/crossplane/sns-topic.yaml" 2>/dev/null || true
kubectl apply -f "$PROJECT_ROOT/crossplane/sqs-queue.yaml" 2>/dev/null || true
kubectl apply -f "$PROJECT_ROOT/crossplane/dynamodb-table.yaml" 2>/dev/null || true
kubectl apply -f "$PROJECT_ROOT/crossplane/sns-subscription.yaml" 2>/dev/null || true

echo "Waiting for AWS resources..."
for i in {1..30}; do
    READY_COUNT=0
    kubectl get topic -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True" && ((READY_COUNT++)) || true
    kubectl get queue -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True" && ((READY_COUNT++)) || true
    kubectl get table -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True" && ((READY_COUNT++)) || true
    kubectl get subscription -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True" && ((READY_COUNT++)) || true
    
    if [ "$READY_COUNT" -eq 4 ]; then
        echo -e "${GREEN}AWS resources ready (4/4)${NC}"
        break
    fi
    sleep 10
    echo "Attempt $i/30 - $READY_COUNT/4 resources ready"
done

# 8. Applications
echo ""
echo -e "${BLUE}Deploying applications...${NC}"

echo "Installing producer..."
helm upgrade --install producer "$PROJECT_ROOT/helm/producer" \
    --set image.repository=ghcr.io/justtrackio/devopstest-producer \
    --set image.tag=latest \
    --set env.CLOUD_AWS_DEFAULTS_ENDPOINT=http://localstack.localstack.svc.cluster.local:4566 \
    --wait --timeout=300s 2>/dev/null || true

echo "Installing consumer..."
helm upgrade --install consumer "$PROJECT_ROOT/helm/consumer" \
    --set image.repository=ghcr.io/justtrackio/devopstest-consumer \
    --set image.tag=latest \
    --set env.CLOUD_AWS_DEFAULTS_ENDPOINT=http://localstack.localstack.svc.cluster.local:4566 \
    --wait --timeout=300s 2>/dev/null || true

echo "Installing dynamodb-admin..."
helm upgrade --install dynamodb-admin "$PROJECT_ROOT/helm/dynamodb-admin" \
    --set env.DYNAMO_ENDPOINT=http://localstack.localstack.svc.cluster.local:4566 \
    --set env.AWS_REGION=eu-central-1 \
    --wait --timeout=300s 2>/dev/null || true

echo -e "${GREEN}Applications deployed${NC}"

# 9. Admin Interface
echo ""
echo -e "${BLUE}Starting admin interface...${NC}"

# Stop any existing port-forward
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ]; then
        kill "$OLD_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

# Start new port-forward
kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!
echo "$PORT_FORWARD_PID" > "$PID_FILE"

# Wait for interface to be ready
echo "Waiting for admin interface..."
for i in {1..10}; do
    if curl -s --connect-timeout 2 http://localhost:8001 >/dev/null 2>&1; then
        echo -e "${GREEN}Admin interface ready!${NC}"
        echo "URL: http://localhost:8001"
        echo "PID: $PORT_FORWARD_PID"
        
        # FIXED: Check if running in interactive mode before prompting
        if [[ -t 0 && -t 1 ]]; then
            # Ask about browser with timeout
            echo ""
            echo -e "${YELLOW}Open browser? (Y/n) [10s timeout]:${NC}"
            if read -t 10 -r response; then
                if [[ ! "$response" =~ ^[nN]$ ]]; then
                    if command -v open >/dev/null 2>&1; then
                        open http://localhost:8001
                        echo "Browser opened"
                    else
                        echo "Browser not available"
                    fi
                fi
            else
                echo ""
                echo "Timeout reached, skipping browser open"
            fi
        else
            echo "Non-interactive mode detected, skipping browser prompt"
            echo "You can manually open: http://localhost:8001"
        fi
        break
    fi
    sleep 2
    echo "Attempt $i/10..."
done

# 10. Summary
echo ""
echo -e "${GREEN}DEPLOYMENT COMPLETED${NC}"
echo "===================="
echo "Duration: Safe and reliable"
echo ""
echo "Services:"
echo "  • Producer: Running"
echo "  • Consumer: Running" 
echo "  • DynamoDB Admin: http://localhost:8001"
echo "  • LocalStack: Running"
echo ""
echo "Monitor:"
echo "  • Producer logs: kubectl logs -l app=producer-producer -f"
echo "  • Consumer logs: kubectl logs -l app=consumer-consumer -f"
echo ""
echo "Cleanup:"
echo "  • Run './cleanup.sh' to clean up"
