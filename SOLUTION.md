# JustTrack DevOps Task 1 - Event-Driven Architecture Implementation

## Quick Start

1. `./pipeline/deploy.sh` - Deploy everything
2. `./pipeline/test.sh` - Verify it works  
3. Open http://localhost:8001 to see events flowing

**What this does**: Deploys a complete event-driven system where Producer→SNS→SQS→Consumer→DynamoDB, all running locally in Kubernetes with simulated AWS services.

**Architecture Flow**: Producer generates events → SNS topic → SQS queue → Consumer processes events → DynamoDB storage. A web-based admin interface provides real-time visualization of stored events.

## System Requirements

- **Docker Desktop**: 4.40.0+ with Kubernetes enabled (4GB+ RAM allocated)
- **Kubernetes Context**: Must be set to `docker-desktop`
- **Important**: Ensure Docker Desktop setting "Use containerd for pulling and storing images" is **disabled**

## Project Structure

```
task1/
├── README.md                           # Original task requirements
├── SOLUTION.md                         # Implementation guide (this file)
├── .gitignore                          # Git ignore patterns
├── certificates/                       # Certificate management (auto-generated)
├── pipeline/                           # Deployment automation
│   ├── deploy.sh                       # Main deployment script
│   ├── test.sh                         # Testing and verification
│   └── cleanup.sh                      # Resource cleanup
├── crossplane/                         # Infrastructure definitions
│   ├── provider.yaml                   # AWS provider configuration
│   ├── provider-config.yaml            # LocalStack endpoint configuration
│   ├── deployment-runtime-config.yaml  # Runtime configuration
│   ├── sns-topic.yaml                  # SNS topic definition
│   ├── sqs-queue.yaml                  # SQS queue definition
│   ├── dynamodb-table.yaml             # DynamoDB table definition
│   └── sns-subscription.yaml           # SNS-SQS subscription
├── helm/                               # Application charts
│   ├── producer/                       # Producer application
│   ├── consumer/                       # Consumer application
│   └── dynamodb-admin/                 # Admin interface
└── k8s/                                # Kubernetes manifests
    └── localstack.yaml                 # LocalStack deployment
```

## Overview

This project implements a cloud-native event-driven architecture using Docker Desktop Kubernetes, Crossplane, and Helm. The solution demonstrates a producer-consumer pattern with AWS services (SNS, SQS, DynamoDB) simulated locally via LocalStack.

**AWS Resources**

- **SNS Topic**: `justtrack-dev-devops-producer-events`
- **SQS Queue**: `justtrack-dev-devops-consumer-events`  
- **DynamoDB Table**: `justtrack-dev-devops-consumer-events`
- **SNS Subscription**: Links topic to queue

## Usage

### Deployment

```bash
cd task1/pipeline
./deploy.sh
```

The deployment script will:
1. Install Crossplane for infrastructure management
2. Deploy LocalStack for AWS service simulation
3. Create AWS resources (SNS, SQS, DynamoDB) via Crossplane
4. Deploy applications (producer, consumer, admin) via Helm
5. Start the admin interface at http://localhost:8001

### Testing

```bash
./test.sh
```

Verifies the complete event flow and displays system status.

### Cleanup

```bash
./cleanup.sh
```

Removes applications and AWS resources while preserving infrastructure for quick redeployment.

## Monitoring

**View logs:**
```bash
kubectl logs -l app=producer-producer -f    # Producer logs
kubectl logs -l app=consumer-consumer -f     # Consumer logs
```

**Check resources:**
```bash
kubectl get topics,queues,tables,subscriptions  # AWS resources
kubectl get pods                                # Running applications
helm list                                       # Deployed applications
```

This implementation demonstrates Kubernetes expertise, Crossplane proficiency, Helm mastery, and production-ready cloud-native development practices.
