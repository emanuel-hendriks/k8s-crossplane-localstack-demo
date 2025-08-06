# Deploy Script Documentation

## Overview

The `deploy.sh` script deploys a complete cloud-native event-driven architecture using Kubernetes, Crossplane, and Helm. It creates AWS resources (SNS, SQS, DynamoDB) via LocalStack and deploys applications that demonstrate event processing.

## Usage

```bash
./pipeline/deploy.sh
```

## Architecture

The script deploys the following components:

```
Producer → SNS Topic → SQS Queue → Consumer → DynamoDB Table
```

- **Producer**: Publishes events to SNS every second
- **Consumer**: Processes events from SQS and stores them in DynamoDB
- **DynamoDB Admin**: Web interface for viewing stored data

## Deployment Steps

### 1. Prerequisites Validation
- Verifies `kubectl`, `helm`, and `docker` are installed
- Checks Kubernetes cluster connectivity

### 2. Crossplane Installation
- Adds Crossplane Helm repository
- Checks if Crossplane is already installed using `helm list`
- If installed: upgrades existing Crossplane installation
- If not installed: installs Crossplane with `--create-namespace` flag
- Waits for Crossplane pods to be ready

### 3. AWS Provider Installation
- Applies `deployment-runtime-config.yaml` for LocalStack configuration
- Applies `provider.yaml` to install AWS provider
- Allows 30 seconds for provider initialization

### 4. LocalStack Deployment
- Creates `localstack` namespace
- Deploys LocalStack from `k8s/localstack.yaml`
- Waits for LocalStack deployment to be available

### 5. Provider Configuration
- Applies `provider-config.yaml` to configure AWS provider with LocalStack endpoint
- Waits 15 seconds for configuration to propagate

### 6. AWS Resources Creation
Creates Crossplane resources in sequence:
- **SNS Topic**: `justtrack-dev-devops-producer-events`
- **SQS Queue**: `justtrack-dev-devops-consumer-events`
- **DynamoDB Table**: `justtrack-dev-devops-consumer-events`
- **SNS Subscription**: Links topic to queue

### 7. Application Deployment
Deploys three Helm charts:
- **Producer**: `helm/producer` with LocalStack endpoint configuration
- **Consumer**: `helm/consumer` with LocalStack endpoint configuration
- **DynamoDB Admin**: `helm/dynamodb-admin` with LocalStack DynamoDB endpoint

### 8. Verification
- Lists all pods across namespaces
- Shows Helm release status

## Configuration

### Environment Variables
- `AWS_REGION`: Set to `eu-central-1`
- `CROSSPLANE_NAMESPACE`: Set to `crossplane-system`
- `LOCALSTACK_NAMESPACE`: Set to `localstack`

### Application Configuration
All applications are configured to use LocalStack endpoints:
- **SNS/SQS Endpoint**: `http://localstack.localstack.svc.cluster.local:4566`
- **DynamoDB Endpoint**: `http://localstack.localstack.svc.cluster.local:4566`

## Resources Created

### Kubernetes Resources
- **Namespaces**: `crossplane-system`, `localstack`
- **Deployments**: Crossplane, AWS Provider, LocalStack, Producer, Consumer, DynamoDB Admin
- **Services**: LocalStack, Producer, Consumer, DynamoDB Admin

### Crossplane Resources
- **Provider**: AWS provider for LocalStack
- **ProviderConfig**: LocalStack endpoint configuration
- **Topic**: SNS topic for event publishing
- **Queue**: SQS queue for event processing
- **Table**: DynamoDB table for data storage
- **Subscription**: SNS-SQS message routing

### Helm Releases
- **producer**: Event generation application
- **consumer**: Event processing application
- **dynamodb-admin**: Data visualization interface

## Output

The script provides colored output showing:
- Progress indicators for each deployment step
- Success/failure status for each component
- Final deployment summary with duration and component counts
- Access instructions for DynamoDB admin interface
- Commands for monitoring and cleanup

## Dependencies

- Docker Desktop with Kubernetes enabled
- kubectl CLI tool
- Helm package manager
- Internet connectivity for container image pulls

## Post-Deployment

After successful deployment:
- Producer begins publishing events to SNS
- Consumer processes events from SQS and stores in DynamoDB
- DynamoDB Admin interface is accessible via port-forward on port 8001
- All components use LocalStack for AWS service simulation
