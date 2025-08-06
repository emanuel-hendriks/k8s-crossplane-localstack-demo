# Dry Run Deployment Documentation

## Overview

The [`deploy_dry_run.sh`](../deploy_dry_run.sh) script provides a comprehensive simulation of the deployment process without creating any actual Kubernetes resources. It serves as a preview tool that shows exactly what the real deployment script would do, making it invaluable for understanding, planning, and troubleshooting deployments.

## Purpose

This dry-run script serves multiple critical functions:
- **Deployment Preview**: Shows the complete deployment flow before execution
- **Learning Tool**: Helps users understand the deployment process step-by-step
- **Planning Aid**: Allows review of all resources that will be created
- **Documentation**: Serves as executable documentation of the deployment process
- **Troubleshooting**: Helps identify potential issues before actual deployment
- **Training**: Safe environment for learning the deployment workflow

## Simulation Coverage

### Complete Deployment Simulation
The dry-run script simulates the entire deployment process with **8 comprehensive steps**:

1. **Prerequisites Check**
2. **Crossplane Installation** 
3. **AWS Provider Setup**
4. **LocalStack Deployment**
5. **AWS Resource Provisioning**
6. **Application Deployment**
7. **Deployment Verification**
8. **Access Information**

### What Gets Simulated

#### Infrastructure Components
- **Crossplane Installation**: Helm repository setup and installation
- **AWS Provider Configuration**: Provider installation and LocalStack endpoint setup
- **LocalStack Deployment**: AWS services simulation environment
- **Certificate Management**: CA certificate configuration for corporate environments

#### AWS Resource Provisioning
- **SNS Topic**: `justtrack-dev-devops-producer-events`
- **SQS Queue**: `justtrack-dev-devops-consumer-events`
- **DynamoDB Table**: `justtrack-dev-devops-consumer-events` with Id (String) hash key
- **SNS-SQS Subscription**: Message routing configuration

#### Application Deployment
- **Producer Application**: Event generation service
- **Consumer Application**: Event processing service
- **DynamoDB Admin**: Web interface for database management

#### Verification and Access
- **Pod Status Verification**: Expected running pods across all namespaces
- **Resource Status Verification**: Crossplane custom resource states
- **Helm Release Verification**: Application deployment confirmation
- **Access Instructions**: Port-forwarding and monitoring commands

## Usage

### Basic Dry Run
```bash
./deploy_dry_run.sh
```

### Prerequisites
- **None required** - This is a simulation that doesn't interact with Kubernetes
- No cluster access needed
- No actual resources created or modified
- Safe to run in any environment

## Dry Run Output

### Step-by-Step Simulation
```
DRY-RUN: Deploying Cloud-Native Event-Driven Architecture
=========================================================

[DRY-RUN] This is a DRY-RUN simulation - no actual commands will be executed

Step 1: Checking Prerequisites
==============================
[DRY-RUN] kubectl cluster-info
✓ Kubernetes cluster: Docker Desktop (simulated)
[DRY-RUN] helm version
✓ Helm version: v3.x.x (simulated)
[DRY-RUN] docker --version
✓ Docker version: 4.40.0+ (simulated)

Step 2: Installing Crossplane
=============================
[DRY-RUN] helm repo add crossplane-stable https://charts.crossplane.io/stable
✓ Crossplane Helm repository added
[DRY-RUN] helm install crossplane crossplane-stable/crossplane --namespace crossplane-system --create-namespace --wait --timeout=600s
✓ Crossplane installed in crossplane-system namespace

Step 3: Setting Up AWS Provider
===============================
[DRY-RUN] kubectl apply -f ../crossplane/aws-provider.yaml
✓ AWS Provider installed
[DRY-RUN] kubectl apply -f ../crossplane/deployment-runtime-config.yaml
✓ DeploymentRuntimeConfig applied

Step 4: Deploying LocalStack
============================
[DRY-RUN] kubectl apply -f ../k8s/localstack.yaml
✓ LocalStack deployed in localstack namespace
[DRY-RUN] kubectl apply -f ../crossplane/provider-config.yaml
✓ ProviderConfig applied

Step 5: Provisioning AWS Resources
==================================
[DRY-RUN] kubectl apply -f ../crossplane/sns-topic.yaml
✓ SNS Topic 'justtrack-dev-devops-producer-events' is ready
[DRY-RUN] kubectl apply -f ../crossplane/sqs-queue.yaml
✓ SQS Queue 'justtrack-dev-devops-consumer-events' is ready
[DRY-RUN] kubectl apply -f ../crossplane/dynamodb-table.yaml
✓ DynamoDB Table 'justtrack-dev-devops-consumer-events' is ready
[DRY-RUN] kubectl apply -f ../crossplane/sns-subscription.yaml
✓ SNS-SQS subscription 'justtrack-dev-devops-subscription' is ready

Step 6: Deploying Applications
==============================
[DRY-RUN] helm install producer ../helm/producer --wait --timeout=300s
✓ producer deployed successfully
[DRY-RUN] helm install consumer ../helm/consumer --wait --timeout=300s
✓ consumer deployed successfully
[DRY-RUN] helm install dynamodb-admin ../helm/dynamodb-admin --wait --timeout=300s
✓ dynamodb-admin deployed successfully

Step 7: Deployment Verification
===============================
[DRY-RUN] kubectl get pods --all-namespaces
Expected pods:
  NAMESPACE           NAME                                             READY   STATUS
  crossplane-system   crossplane-xxx                                   1/1     Running
  crossplane-system   crossplane-rbac-manager-xxx                      1/1     Running
  crossplane-system   provider-aws-xxx                                 1/1     Running
  default             producer-producer-xxx                            1/1     Running
  default             consumer-consumer-xxx                            1/1     Running
  default             dynamodb-admin-dynamodb-admin-xxx               1/1     Running
  localstack          localstack-xxx                                   1/1     Running

[DRY-RUN] kubectl get topics,queues,tables,subscriptions
Expected Crossplane resources:
  NAME                                                               READY   SYNCED
  topic.sns.aws.crossplane.io/justtrack-dev-devops-producer-events   True    True
  queue.sqs.aws.crossplane.io/justtrack-dev-devops-consumer-events   True    True
  table.dynamodb.aws.crossplane.io/justtrack-dev-devops-consumer-events True True
  subscription.sns.aws.crossplane.io/justtrack-dev-devops-subscription True True

Step 8: Access Information
=========================
DynamoDB Admin Web Interface:
[DRY-RUN] kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001
Then open: http://localhost:8001

Monitor Event Processing:
[DRY-RUN] kubectl logs -l app=producer-producer -f
[DRY-RUN] kubectl logs -l app=consumer-consumer -f
```

### Final Summary
```
DEPLOYMENT SUMMARY (DRY-RUN)
============================

✓ Infrastructure Components:
  ✓ Crossplane installed and configured
  ✓ LocalStack deployed for AWS simulation
  ✓ AWS Provider configured with LocalStack endpoint

✓ AWS Resources (via Crossplane):
  ✓ SNS Topic: justtrack-dev-devops-producer-events
  ✓ SQS Queue: justtrack-dev-devops-consumer-events
  ✓ DynamoDB Table: justtrack-dev-devops-consumer-events (Id: String)
  ✓ SNS-SQS Subscription: justtrack-dev-devops-subscription

✓ Applications (via Helm):
  ✓ Producer: ghcr.io/justtrackio/devopstest-producer:latest
  ✓ Consumer: ghcr.io/justtrackio/devopstest-consumer:latest
  ✓ DynamoDB Admin: aaronshaf/dynamodb-admin:latest

✓ Event Flow:
  Producer → SNS Topic → SQS Queue → Consumer → DynamoDB
  All components configured to use LocalStack endpoints

Next Steps:
  • Run the actual deploy.sh script to perform real deployment
  • Use kubectl port-forward to access DynamoDB Admin
  • Monitor logs to verify event processing
  • Use test.sh to run comprehensive tests
  • Use cleanup.sh to remove all resources when done

⚠️  This was a DRY-RUN simulation. No actual resources were created.
ℹ️  To perform actual deployment, run: ./deploy.sh
```

## Key Features

### Visual Command Simulation
- **Command Preview**: Shows exact commands that would be executed
- **Expected Outputs**: Displays anticipated results and confirmations
- **Resource Specifications**: Details all resources that would be created
- **Configuration Values**: Shows actual configuration parameters

### Comprehensive Coverage
- **All Deployment Steps**: Covers every phase of the real deployment
- **Resource Details**: Specifies exact resource names and configurations
- **Expected States**: Shows what successful deployment looks like
- **Access Instructions**: Provides ready-to-use management commands

### Educational Value
- **Step-by-Step Learning**: Understand deployment flow without consequences
- **Command Reference**: See exact kubectl and helm commands used
- **Resource Relationships**: Understand how components interact
- **Best Practices**: Learn proper deployment sequencing

## Use Cases

### Pre-Deployment Planning
- **Resource Review**: Understand what will be created before deployment
- **Naming Validation**: Verify resource names and configurations
- **Dependency Understanding**: See deployment order and relationships
- **Time Estimation**: Understand deployment complexity and duration

### Learning and Training
- **Safe Exploration**: Learn deployment process without cluster access
- **Command Learning**: See exact commands used in real deployments
- **Architecture Understanding**: Visualize complete system architecture
- **Troubleshooting Preparation**: Understand expected states for debugging

### Documentation and Communication
- **Deployment Documentation**: Executable documentation of the process
- **Team Communication**: Share deployment process with stakeholders
- **Review Process**: Allow review of deployment before execution
- **Change Management**: Document what changes will be made

### Development and Testing
- **Script Development**: Test deployment logic without resource creation
- **Process Validation**: Verify deployment steps before implementation
- **Integration Testing**: Understand integration points and dependencies
- **Rollback Planning**: Understand what needs to be cleaned up

## Integration with Deployment Workflow

### Typical Usage Pattern
```bash
# 1. Review deployment process
./deploy_dry_run.sh

# 2. Perform actual deployment
./deploy.sh

# 3. Test the deployment
./test.sh

# 4. Clean up when finished
./cleanup.sh
```

### Development Workflow
- **Planning Phase**: Use dry-run to plan deployment strategy
- **Review Phase**: Share dry-run output for team review
- **Execution Phase**: Run actual deployment with confidence
- **Validation Phase**: Compare actual results with dry-run expectations

## Safety and Benefits

### Zero Risk Operation
- **No Resource Creation**: Completely safe to run anywhere
- **No Cluster Access**: Doesn't require Kubernetes connectivity
- **No Side Effects**: Cannot impact existing deployments
- **Repeatable**: Can be run multiple times safely

### Educational Benefits
- **Complete Visibility**: See every step of the deployment process
- **Command Learning**: Learn exact kubectl and helm commands
- **Architecture Understanding**: Visualize system components and relationships
- **Best Practice Learning**: Understand proper deployment sequencing

### Planning Benefits
- **Resource Planning**: Understand resource requirements before deployment
- **Time Planning**: Estimate deployment duration and complexity
- **Dependency Planning**: Understand component dependencies and order
- **Access Planning**: Know what access methods will be available

The dry-run script is an essential tool for understanding, planning, and communicating the deployment process, providing complete visibility into what the real deployment will do without any risk or resource requirements.
