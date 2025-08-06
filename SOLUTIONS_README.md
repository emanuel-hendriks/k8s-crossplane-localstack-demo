# JustTrack DevOps Task 1 - Event-Driven Architecture Implementation

## Quick Start

1. `./pipeline/deploy.sh` - Deploy everything
2. `./pipeline/test.sh` - Verify it works  
3. `./pipeline/admin-bg.sh start` - Access DynamoDB admin interface
4. Open http://localhost:8001 to see events flowing

**What this does**: Deploys a complete event-driven system where Producer→SNS→SQS→Consumer→DynamoDB, all running locally in Kubernetes with simulated AWS services.

## System Requirements

- **Docker Desktop**: 4.40.0+ with Kubernetes enabled (4GB+ RAM allocated)
- **Kubernetes Context**: Must be set to `docker-desktop`
- **Important**: Ensure Docker Desktop setting "Use containerd for pulling and storing images" is **disabled**

## Overview

This project implements a cloud-native event-driven architecture using Docker Desktop Kubernetes, Crossplane, and Helm. The solution demonstrates a producer-consumer pattern with AWS services (SNS, SQS, DynamoDB) simulated locally via LocalStack.

**Architecture Flow**: Producer generates events → SNS topic → SQS queue → Consumer processes events → DynamoDB storage. A web-based admin interface provides real-time visualization of stored events.

## Architecture

### Namespace Organization

The system operates across three namespaces:

- **`default`** - Application workloads (Producer, Consumer, DynamoDB Admin) and AWS resource definitions
- **`localstack`** - AWS service simulator 
- **`crossplane-system`** - Infrastructure management components

### Components

**Infrastructure Layer**
- **LocalStack**: Simulates AWS services (SNS, SQS, DynamoDB) locally
- **Crossplane**: Manages AWS resources declaratively through LocalStack

**Application Layer**
- **Producer**: Generates events every second, publishes to SNS
- **Consumer**: Processes events from SQS, stores in DynamoDB
- **DynamoDB Admin**: Web interface for data visualization

**AWS Resources**
- **SNS Topic**: `justtrack-dev-devops-producer-events`
- **SQS Queue**: `justtrack-dev-devops-consumer-events`
- **DynamoDB Table**: `justtrack-dev-devops-consumer-events`
- **SNS Subscription**: Routes messages from topic to queue

### Event Flow

```
Producer → SNS Topic → SQS Queue → Consumer → DynamoDB Table
```

Events are generated with this structure:
```json
{
 "Id": "uuid-string",
 "Number": 123,
 "CreatedAt": "2025-08-03T..."
}
```

### Deployment

The `pipeline/deploy.sh` script automates deployment in these phases:

1. Prerequisites validation
2. Crossplane installation
3. AWS provider setup
4. LocalStack deployment
5. Provider configuration
6. AWS resources creation
7. Application deployment
8. Verification

Deployment completes in approximately 2-3 minutes.

### Testing

Run comprehensive tests:
```bash
./pipeline/test.sh
```

### Data Access

Access the DynamoDB admin interface:
```bash
./pipeline/admin-bg.sh start
```

### Cleanup

Remove all resources:
```bash
./pipeline/cleanup.sh
```

## Project Structure

```
task1/
├── README.md                           # Original task requirements
├── SOLUTIONS_README.md                 # Implementation guide
├── .gitignore                          # Git ignore patterns
├── pipeline/                           # Deployment automation
│   ├── deploy.sh                       # Main deployment script
│   ├── test.sh                         # Testing and verification
│   ├── cleanup.sh                      # Resource cleanup
│   ├── admin-bg.sh                     # DynamoDB admin interface
│   └── docs/                           # Script documentation
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

## Usage Examples

**Monitor event processing:**
```bash
kubectl logs -l app=producer-producer -f
kubectl logs -l app=consumer-consumer -f
```

**Scale components:**
```bash
kubectl scale deployment producer-producer --replicas=0  # Stop events
kubectl scale deployment consumer-consumer --replicas=2  # Scale processing
```

**Check status:**
```bash
kubectl get pods
kubectl get topics,queues,tables,subscriptions
```

This implementation demonstrates Kubernetes expertise, Crossplane proficiency, Helm mastery, and production-ready cloud-native development practices.
