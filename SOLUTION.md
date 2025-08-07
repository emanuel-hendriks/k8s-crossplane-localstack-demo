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

## Architecture

**Functional Architecture**: Producer generates events → SNS topic → SQS queue → Consumer processes events → DynamoDB storage. A web-based admin interface provides real-time visualization of stored events.


### 4-Layer Deployment Architecture Stack

```
┌─────────────────────────────────────────────────────────────┐
│                    LAYER 4: APPLICATIONS                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Producer   │  │  Consumer   │  │  DynamoDB Admin     │  │
│  │             │  │             │  │                     │  │
│  │ Sends msgs  │  │ Reads msgs  │  │ Shows data in       │  │
│  │ to SNS      │  │ from SQS    │  │ web interface       │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    LAYER 3: LOCALSTACK                      │
│                    (Fake AWS Services)                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ SNS Topic   │  │ SQS Queue   │  │ DynamoDB Table      │  │
│  │             │  │             │  │                     │  │
│  │ Receives    │──│ Gets msgs   │──│ Stores processed    │  │
│  │ messages    │  │ via sub     │  │ messages            │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   LAYER 2: CROSSPLANE                       │
│                 (Infrastructure Manager, CR)                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ topic.yaml  │  │ queue.yaml  │  │ table.yaml          │  │
│  │             │  │             │  │                     │  │ 
│  │ Tells       │  │ Tells       │  │ Tells               │  │
│  │ LocalStack  │  │ LocalStack  │  │ LocalStack          │  │
│  │ "create SNS"│  │ "create SQS"│  │ "create DynamoDB"   │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   LAYER 1: KUBERNETES                       │
│                    (Container Platform)                     │
│  Runs all the containers and manages networking             │
└─────────────────────────────────────────────────────────────┘
```

### Layer Responsibilities

**Layer 1: Kubernetes (Foundation)**
- Container orchestration platform
- Runs all containers (LocalStack, applications, Crossplane)
- Manages networking between containers
- Provides service discovery

**Layer 2: Crossplane (Infrastructure Manager)**
- Kubernetes extension for managing cloud resources (CR) 
- Reads YAML files (sns-topic.yaml, sqs-queue.yaml, etc.)
- Makes API calls to LocalStack to create resources
- Tracks resource state as Kubernetes Custom Resource Definitions (CRDs)

**Layer 3: LocalStack (Simulated AWS)**
- Container that simulates AWS services
- Provides SNS, SQS, DynamoDB APIs
- Stores data in memory (not persistent)
- Responds to AWS API calls from applications and Crossplane

**Layer 4: Applications (Business Logic)**
- Producer: Sends messages to SNS
- Consumer: Reads from SQS, writes to DynamoDB
- Admin: Shows DynamoDB data in web interface
- Connect to LocalStack using standard AWS SDKs

**Helm (Package Manager)**
- Manages Kubernetes application deployments across all layers
- Handles application lifecycle (install, upgrade, uninstall)
- Manages configuration through values.yaml files
- Deploys to Layer 1 (Kubernetes) but manages Layer 4 (Applications)
- Packages applications as charts (producer, consumer, dynamodb-admin)
    - **Producer Chart** [`helm/producer/values.yaml`](helm/producer/values.yaml) creates:
        - Deployment: Runs `ghcr.io/justtrackio/devopstest-producer:latest`
        - Service: Exposes producer on port `8080`
        - Environment variables: Points to `LocalStack` endpoint
    - **Consumer Chart** [`helm/consumer/values.yaml`](helm/consumer/values.yaml) creates:
        - Deployment: Runs `ghcr.io/justtrackio/devopstest-consumer:latest`
        - Service: Exposes consumer on port 8080
        - Environment variables: Points to `LocalStack` endpoint
    - **DynamoDB Admin Chart** [`helm/dynamodb-admin/values.yaml`](helm/dynamodb-admin/values.yaml) creates:
        - Deployment: Runs `aaronshaf/dynamodb-admin:latest`
        - Service: Exposes admin UI on port 8001
        - Environment variables: Points to LocalStack DynamoDB (`DYNAMO_ENDPOINT: "http://localstack.localstack.svc.cluster.local:4566"`)

```
http://localstack.localstack.svc.cluster.local:4566
│      │         │         │   │       │     │
│      │         │         │   │       │     └── Port number
│      │         │         │   │       └────── Cluster domain
│      │         │         │   └────────────── Service type indicator (Kubernetes DNS convention indicating this is a Service)
│      │         │         └────────────────── Namespace
│      │         └──────────────────────────── Service name
│      └─────────────────────────────────────── Service name (repeated)
└────────────────────────────────────────────── Protocol
```

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

**AWS Resources **
- **SNS Topic**: `justtrack-dev-devops-producer-events`
- **SQS Queue**: `justtrack-dev-devops-consumer-events`
- **DynamoDB Table**: `justtrack-dev-devops-consumer-events`
- **SNS Subscription**: Routes messages from topic to queue

### System Flow

**During Deployment:**
1. [`deploy.sh`](task1/pipeline) runs
2. Helm installs Crossplane to Kubernetes
3. Kubernetes starts LocalStack container
4. **SNS Topic Creation:**
   - Crossplane reads `sns-topic.yaml`
   - Crossplane calls LocalStack API: "create SNS topic"
   - LocalStack creates fake SNS topic in memory
    
5. **SQS Queue Creation:**
   - Crossplane reads `sqs-queue.yaml`
   - Crossplane calls LocalStack API: "create SQS queue"
   - LocalStack creates fake SQS queue in memory

6. **DynamoDB Table Creation:**
   - Crossplane reads `dynamodb-table.yaml`
   - Crossplane calls LocalStack API: "create DynamoDB table"
   - LocalStack creates fake DynamoDB table in memory

7. **SNS Subscription Creation:**
   - Crossplane reads `sns-subscription.yaml`
   - Crossplane calls LocalStack API: "create SNS subscription"
   - LocalStack creates fake subscription linking SNS topic to SQS queue

8. Helm installs application charts (producer, consumer, dynamodb-admin)
9. Applications start and connect to LocalStack

**During Runtime:**
1. Producer app → sends message → LocalStack SNS Topic
2. SNS Subscription → forwards message → LocalStack SQS Queue
3. Consumer app → reads message → LocalStack SQS
4. Consumer app → stores data → LocalStack DynamoDB
5. Admin app → reads data → LocalStack DynamoDB → shows in web UI

**During Cleanup:**
1. `cleanup.sh` runs
2. Helm uninstalls application releases (producer, consumer, dynamodb-admin)
3. Delete Crossplane YAML objects (`kubectl delete` topics)
4. Crossplane sees deletion → calls LocalStack API: "delete SNS topic"
5. LocalStack deletes fake SNS topic from memory
6. Delete LocalStack container
7. All fake AWS resources disappear (they were in memory)
8. Optionally: Helm uninstalls Crossplane

### Resource Mapping

| What You See in kubectl | What It Actually Is | Where It Lives | Managed By |
|-------------------------|-------------------|----------------|------------|
| `kubectl get topics` | Kubernetes CRD object | Kubernetes API | Crossplane |
| SNS Topic | Fake AWS resource | LocalStack memory | LocalStack |
| `kubectl get pods` | Running containers | Docker | Kubernetes |
| Producer app | Container | Kubernetes pod | Helm |
| LocalStack | Container | Kubernetes pod | Kubernetes |
| `helm list` | Deployed applications | Helm releases | Helm |

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

### Architecture Benefits

**Development Advantages:**
- No AWS costs - Everything runs locally
- Fast development - No internet dependency
- Infrastructure as Code - Everything in YAML
- Kubernetes native - Uses standard K8s patterns
- Production ready - Same patterns work with real AWS

**Trade-offs:**
- Not persistent - Data lost when LocalStack restarts
- Limited features - LocalStack doesn't support all AWS features
- Memory usage - Everything runs in local machine

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

View stored events via DynamoDB admin web interface:
```bash
./pipeline/admin-bg.sh start    # Opens http://localhost:8001
./pipeline/admin-bg.sh stop     # Stop when done
```

### Cleanup Process

Remove all resources:
```bash
./pipeline/cleanup.sh
```

**Cleanup Sequence:**
1. Helm uninstalls application releases (producer, consumer, dynamodb-admin)
2. Delete Crossplane CRDs (triggers LocalStack resource removal)
3. Remove LocalStack namespace (destroys simulated AWS environment)
4. Optionally remove Crossplane system (Helm uninstall crossplane)

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
helm list                                    # Show Helm releases
helm status producer                         # Check specific release
```

**Helm operations:**
```bash
helm upgrade producer ./helm/producer        # Update application
helm rollback consumer 1                     # Rollback to previous version
helm uninstall dynamodb-admin               # Remove specific application
```

**Inspect LocalStack resources directly:**
```bash
# Port forward to LocalStack
kubectl port-forward -n localstack svc/localstack 4566:4566

# Use AWS CLI against LocalStack
aws --endpoint-url=http://localhost:4566 sns list-topics
aws --endpoint-url=http://localhost:4566 sqs list-queues
aws --endpoint-url=http://localhost:4566 dynamodb list-tables
```

## Common Questions

**Are these real AWS resources?**
No. They are simulated resources running in LocalStack container. No real AWS account is needed.

**What does Crossplane actually do?**
Crossplane translates Kubernetes YAML definitions into AWS API calls made to LocalStack instead of real AWS.

**Where is the data stored?**
In LocalStack's memory. When LocalStack container stops, all data is lost.

**What happens when I delete a Crossplane resource?**
```
kubectl delete topic my-topic
    ↓
Crossplane sees the deletion
    ↓
Crossplane calls LocalStack: "delete topic"
    ↓
LocalStack removes topic from memory
    ↓
Topic is gone
```