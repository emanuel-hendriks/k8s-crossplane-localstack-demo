#!/bin/bash

# LocalStack Deployment Module
# Handles LocalStack deployment and readiness verification

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Deploy LocalStack
deploy_localstack() {
    print_info "Deploying LocalStack..."
    
    local localstack_manifest="apiVersion: v1
kind: Namespace
metadata:
  name: ${LOCALSTACK[namespace]}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${LOCALSTACK[service_name]}
  namespace: ${LOCALSTACK[namespace]}
  labels:
    app: ${LOCALSTACK[service_name]}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${LOCALSTACK[service_name]}
  template:
    metadata:
      labels:
        app: ${LOCALSTACK[service_name]}
    spec:
      containers:
      - name: ${LOCALSTACK[service_name]}
        image: localstack/localstack:latest
        ports:
        - containerPort: ${LOCALSTACK[port]}
        env:
        - name: SERVICES
          value: \"sns,sqs,dynamodb\"
        - name: DEBUG
          value: \"1\"
        - name: DATA_DIR
          value: \"/tmp/localstack/data\"
        - name: DOCKER_HOST
          value: \"unix:///var/run/docker.sock\"
        resources:
          requests:
            memory: \"512Mi\"
            cpu: \"250m\"
          limits:
            memory: \"1Gi\"
            cpu: \"500m\"
        readinessProbe:
          httpGet:
            path: /_localstack/health
            port: ${LOCALSTACK[port]}
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
        livenessProbe:
          httpGet:
            path: /_localstack/health
            port: ${LOCALSTACK[port]}
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: ${LOCALSTACK[service_name]}
  namespace: ${LOCALSTACK[namespace]}
  labels:
    app: ${LOCALSTACK[service_name]}
spec:
  selector:
    app: ${LOCALSTACK[service_name]}
  ports:
  - port: ${LOCALSTACK[port]}
    targetPort: ${LOCALSTACK[port]}
    protocol: TCP
  type: ClusterIP"
    
    echo "$localstack_manifest" | kubectl apply -f - >/dev/null 2>&1
    
    print_success "LocalStack deployment created"
}

# Wait for LocalStack to be ready
wait_for_localstack() {
    print_info "Waiting for LocalStack to be ready..."
    
    # Wait for deployment to be ready
    if kubectl rollout status deployment/"${LOCALSTACK[service_name]}" \
        -n "${LOCALSTACK[namespace]}" \
        --timeout="${TIMEOUTS[rollout_status]}s" >/dev/null 2>&1; then
        print_success "LocalStack deployment is ready"
    else
        handle_error $? "LocalStack deployment failed" \
            "Check pod logs: kubectl logs -n ${LOCALSTACK[namespace]} deployment/${LOCALSTACK[service_name]}"
    fi
    
    # Wait for pods to be ready
    if kubectl wait --for=condition=ready pod \
        -l "app=${LOCALSTACK[service_name]}" \
        -n "${LOCALSTACK[namespace]}" \
        --timeout="${TIMEOUTS[localstack_ready]}s" >/dev/null 2>&1; then
        print_success "LocalStack pods are ready"
    else
        handle_error $? "LocalStack pods failed to become ready" \
            "Check pod status: kubectl get pods -n ${LOCALSTACK[namespace]}"
    fi
    
    # Additional wait for LocalStack services to initialize
    print_info "Waiting for LocalStack services to initialize..."
    sleep 20
}

# Test LocalStack connectivity
test_localstack() {
    print_info "Testing LocalStack connectivity..."
    
    # Create a test pod to verify LocalStack connectivity
    local test_pod="apiVersion: v1
kind: Pod
metadata:
  name: localstack-test
  namespace: default
spec:
  restartPolicy: Never
  containers:
  - name: aws-cli
    image: amazon/aws-cli:latest
    command: ['sh', '-c']
    args:
    - |
      aws --version
      aws --endpoint-url=${LOCALSTACK[endpoint]} \
          --region=${AWS_RESOURCES[region]} \
          sns list-topics || exit 1
      echo \"LocalStack connectivity test passed\"
    env:
    - name: AWS_ACCESS_KEY_ID
      value: \"test\"
    - name: AWS_SECRET_ACCESS_KEY
      value: \"test\"
    - name: AWS_DEFAULT_REGION
      value: \"${AWS_RESOURCES[region]}\""
    
    echo "$test_pod" | kubectl apply -f - >/dev/null 2>&1
    
    # Wait for test to complete
    local count=0
    local timeout=60
    
    while [ $count -lt $timeout ]; do
        local pod_status
        pod_status=$(kubectl get pod localstack-test -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        if [ "$pod_status" = "Succeeded" ]; then
            print_success "LocalStack connectivity test passed"
            kubectl delete pod localstack-test --ignore-not-found=true >/dev/null 2>&1
            return 0
        elif [ "$pod_status" = "Failed" ]; then
            print_error "LocalStack connectivity test failed"
            kubectl logs localstack-test 2>/dev/null || true
            kubectl delete pod localstack-test --ignore-not-found=true >/dev/null 2>&1
            return 1
        fi
        
        sleep 5
        count=$((count + 5))
    done
    
    print_error "LocalStack connectivity test timed out"
    kubectl delete pod localstack-test --ignore-not-found=true >/dev/null 2>&1
    return 1
}

# Verify LocalStack deployment
verify_localstack() {
    print_info "Verifying LocalStack deployment..."
    
    # Check if namespace exists
    if kubectl get namespace "${LOCALSTACK[namespace]}" >/dev/null 2>&1; then
        print_success "LocalStack namespace exists"
    else
        print_error "LocalStack namespace not found"
        return 1
    fi
    
    # Check if deployment exists and is ready
    local ready_replicas
    ready_replicas=$(kubectl get deployment "${LOCALSTACK[service_name]}" \
        -n "${LOCALSTACK[namespace]}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [ "$ready_replicas" -gt 0 ]; then
        print_success "LocalStack deployment is running ($ready_replicas replicas)"
    else
        print_error "LocalStack deployment is not ready"
        return 1
    fi
    
    # Check if service exists
    if kubectl get service "${LOCALSTACK[service_name]}" \
        -n "${LOCALSTACK[namespace]}" >/dev/null 2>&1; then
        print_success "LocalStack service is configured"
    else
        print_error "LocalStack service not found"
        return 1
    fi
    
    return 0
}

# Main LocalStack deployment function
main() {
    print_info "=== LocalStack Deployment ==="
    
    deploy_localstack
    wait_for_localstack
    test_localstack
    verify_localstack
    
    print_success "LocalStack deployment completed"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
