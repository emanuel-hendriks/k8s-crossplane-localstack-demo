# CLI Cheatsheet - JustTrack Event-Driven Architecture

This cheatsheet provides essential commands for interacting with the deployed event-driven architecture cluster.

## Quick Status Overview

```bash
# Check all pods across namespaces
kubectl get pods --all-namespaces

# Check specific application pods
kubectl get pods -l app=producer-producer
kubectl get pods -l app=consumer-consumer
kubectl get pods -l app=dynamodb-admin-dynamodb-admin

# Check LocalStack status
kubectl get pods -n localstack

# Check Crossplane resources
kubectl get topics,queues,tables,subscriptions
```

## Application Monitoring

### Producer Application
```bash
# View producer logs (real-time)
kubectl logs -l app=producer-producer -f

# Check producer pod details
kubectl describe pod -l app=producer-producer

# Check producer service
kubectl get svc producer-producer

# Scale producer (stop/start event generation)
kubectl scale deployment producer-producer --replicas=0  # Stop
kubectl scale deployment producer-producer --replicas=1  # Start
```

### Consumer Application
```bash
# View consumer logs (real-time)
kubectl logs -l app=consumer-consumer -f

# Check consumer pod details
kubectl describe pod -l app=consumer-consumer

# Scale consumer for load testing
kubectl scale deployment consumer-consumer --replicas=2  # Scale up
kubectl scale deployment consumer-consumer --replicas=1  # Scale back
```

### DynamoDB Admin Interface
```bash
# Port forward to access web interface
kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001

# Then open in browser: http://localhost:8001

# Check admin pod status
kubectl get pods -l app=dynamodb-admin-dynamodb-admin
```

## AWS Resources (Crossplane)

### SNS Topic
```bash
# Check SNS topic status
kubectl get topic justtrack-dev-devops-producer-events

# Describe topic details
kubectl describe topic justtrack-dev-devops-producer-events

# Check topic events/issues
kubectl get events --field-selector involvedObject.name=justtrack-dev-devops-producer-events
```

### SQS Queue
```bash
# Check SQS queue status
kubectl get queue justtrack-dev-devops-consumer-events

# Describe queue details
kubectl describe queue justtrack-dev-devops-consumer-events

# Check queue readiness
kubectl get queue justtrack-dev-devops-consumer-events -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
```

### DynamoDB Table
```bash
# Check DynamoDB table status
kubectl get table justtrack-dev-devops-consumer-events

# Describe table details
kubectl describe table justtrack-dev-devops-consumer-events

# Check table readiness
kubectl get table justtrack-dev-devops-consumer-events -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
```

### SNS Subscription
```bash
# Check subscription status
kubectl get subscription justtrack-dev-devops-subscription

# Describe subscription details
kubectl describe subscription justtrack-dev-devops-subscription
```

## LocalStack Operations

```bash
# Check LocalStack pod status
kubectl get pods -n localstack

# View LocalStack logs
kubectl logs -n localstack deployment/localstack -f

# Port forward to LocalStack (for direct API access)
kubectl port-forward -n localstack svc/localstack 4566:4566

# Restart LocalStack (if needed)
kubectl rollout restart deployment/localstack -n localstack

# Check LocalStack service
kubectl get svc -n localstack
```

## Crossplane Management

```bash
# Check Crossplane provider status
kubectl get providers

# Check provider health
kubectl describe provider provider-aws

# Check provider configuration
kubectl get providerconfigs

# View Crossplane system pods
kubectl get pods -n crossplane-system
```

## Troubleshooting Commands

### Pod Issues
```bash
# Get pod events for troubleshooting
kubectl get events --sort-by=.metadata.creationTimestamp

# Check pod resource usage
kubectl top pods

# Get detailed pod information
kubectl get pods -o wide

# Check pod logs for errors
kubectl logs <pod-name> --previous  # Previous container logs
```

### Network Connectivity
```bash
# Test LocalStack connectivity from producer pod
kubectl exec -it deployment/producer-producer -- curl http://localstack.localstack.svc.cluster.local:4566

# Check service endpoints
kubectl get endpoints

# Verify DNS resolution
kubectl exec -it deployment/producer-producer -- nslookup localstack.localstack.svc.cluster.local
```

### Resource Status
```bash
# Check all Crossplane resources at once
kubectl get topics,queues,tables,subscriptions -o wide

# Check resource conditions
kubectl get topics,queues,tables,subscriptions -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'

# Monitor resource creation progress
watch kubectl get topics,queues,tables,subscriptions
```

## Performance Monitoring

```bash
# Monitor event processing rate
kubectl logs -l app=producer-producer --tail=10 | grep -o "Published event"
kubectl logs -l app=consumer-consumer --tail=10 | grep -o "Processed event"

# Check resource utilization
kubectl top pods --all-namespaces

# Monitor pod restarts
kubectl get pods --all-namespaces -o wide | grep -v "0/0"
```

## Data Verification

### Direct LocalStack API Access
```bash
# Port forward LocalStack
kubectl port-forward -n localstack svc/localstack 4566:4566

# Then use AWS CLI with LocalStack endpoint
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=eu-central-1

# List SNS topics
aws --endpoint-url=http://localhost:4566 sns list-topics

# Get SQS queue attributes
aws --endpoint-url=http://localhost:4566 sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/justtrack-dev-devops-consumer-events --attribute-names All

# Scan DynamoDB table
aws --endpoint-url=http://localhost:4566 dynamodb scan --table-name justtrack-dev-devops-consumer-events --max-items 5
```

## Helm Operations

```bash
# List installed Helm releases
helm list

# Check release status
helm status producer
helm status consumer
helm status dynamodb-admin

# Upgrade applications (if needed)
helm upgrade producer ./helm/producer
helm upgrade consumer ./helm/consumer
helm upgrade dynamodb-admin ./helm/dynamodb-admin

# View Helm release history
helm history producer
```

## Cleanup Operations

```bash
# Stop event generation
kubectl scale deployment producer-producer --replicas=0

# Delete specific applications
helm uninstall producer
helm uninstall consumer
helm uninstall dynamodb-admin

# Delete AWS resources (will trigger Crossplane cleanup)
kubectl delete topics,queues,tables,subscriptions --all

# Delete LocalStack
kubectl delete -f k8s/localstack.yaml

# Full cleanup (use the provided script)
./cleanup.sh
```

## Useful Aliases

Add these to your shell profile for faster access:

```bash
# Kubernetes shortcuts
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgpa='kubectl get pods --all-namespaces'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
alias klf='kubectl logs -f'

# Application-specific shortcuts
alias producer-logs='kubectl logs -l app=producer-producer -f'
alias consumer-logs='kubectl logs -l app=consumer-consumer -f'
alias localstack-logs='kubectl logs -n localstack deployment/localstack -f'
alias aws-resources='kubectl get topics,queues,tables,subscriptions'

# Port forwarding shortcuts
alias dynamo-admin='kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001'
alias localstack-port='kubectl port-forward -n localstack svc/localstack 4566:4566'
```

## Common Workflows

### Start/Stop Event Processing
```bash
# Stop everything
kubectl scale deployment producer-producer --replicas=0
kubectl scale deployment consumer-consumer --replicas=0

# Start everything
kubectl scale deployment producer-producer --replicas=1
kubectl scale deployment consumer-consumer --replicas=1
```

### View Real-time Event Flow
```bash
# Terminal 1: Producer logs
kubectl logs -l app=producer-producer -f

# Terminal 2: Consumer logs  
kubectl logs -l app=consumer-consumer -f

# Terminal 3: DynamoDB Admin (after port-forward)
kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001
# Open http://localhost:8001 in browser
```

### Health Check Sequence
```bash
# 1. Check all pods are running
kubectl get pods --all-namespaces

# 2. Verify Crossplane resources are ready
kubectl get topics,queues,tables,subscriptions -o wide

# 3. Check application logs for errors
kubectl logs -l app=producer-producer --tail=5
kubectl logs -l app=consumer-consumer --tail=5

# 4. Verify data flow via DynamoDB Admin
kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001
```
