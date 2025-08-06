# Cloud-Native Infrastructure Deployment

Standard deployment script for the cloud-native event-driven architecture using Docker Desktop Kubernetes, Crossplane, and Helm.

## 🚀 Quick Start

```bash
./pipeline/deploy.sh
```

## 📋 Prerequisites

- Docker Desktop 4.40.0+ with Kubernetes enabled
- LocalStack Docker Desktop extension
- kubectl command-line tool
- Helm package manager
- Container images accessible:
  - `ghcr.io/justtrackio/devopstest-producer:latest`
  - `ghcr.io/justtrackio/devopstest-consumer:latest`

## 🏗️ Architecture Overview

The deployment creates a complete event-driven architecture:

```
Producer → SNS Topic → SQS Queue → Consumer → DynamoDB Table
    ↓         ↓          ↓           ↓           ↓
  Helm     Crossplane  Crossplane  Helm     Crossplane
  Chart    Resource    Resource    Chart    Resource
```

### Infrastructure Components:
- **SNS Topic**: `justtrack-dev-devops-producer-events`
- **SQS Queue**: `justtrack-dev-devops-consumer-events`
- **DynamoDB Table**: `justtrack-dev-devops-consumer-events`
- **SNS Subscription**: Links topic to queue
- **LocalStack**: Simulates AWS services locally

### Application Components:
- **Producer**: Publishes events to SNS
- **Consumer**: Processes events from SQS, stores in DynamoDB
- **DynamoDB Admin**: Web interface for data visualization

## 🔧 Deployment Process

The script follows a systematic deployment sequence:

### 1. **Prerequisites Validation**
- Checks required tools (kubectl, helm, docker)
- Validates Kubernetes cluster access
- Verifies required directories exist
- Adds Crossplane Helm repository

### 2. **Crossplane Installation**
- Installs/upgrades Crossplane via Helm
- Waits for Crossplane deployment readiness

### 3. **AWS Provider Installation**
- Applies DeploymentRuntimeConfig
- Installs AWS provider package
- Waits for provider to be healthy

### 4. **LocalStack Deployment**
- Deploys LocalStack to simulate AWS services
- Waits for LocalStack availability

### 5. **Provider Configuration**
- Creates ProviderConfig for LocalStack endpoint
- Sets up AWS credentials for local access

### 6. **AWS Resources Creation**
- Creates SNS topic, SQS queue, DynamoDB table
- Sets up SNS-SQS subscription
- Waits for all resources to be ready

### 7. **Application Deployment**
- Deploys Producer, Consumer, and DynamoDB Admin via Helm
- Configures applications for LocalStack connectivity

### 8. **Verification**
- Validates all resources are ready
- Confirms application deployments
- Displays deployment summary

## 📊 Expected Output

### Success Deployment:
```
🚀 Deploying Cloud-Native Event-Driven Architecture
====================================================
Started at: 2025-08-06 05:01:14

ℹ️  Starting deployment with standard configuration
✅ Prerequisites validated
✅ Crossplane installation completed
✅ AWS Provider installation completed
✅ LocalStack deployment completed
✅ ProviderConfig setup completed
✅ All AWS resources created successfully
✅ All applications deployed successfully
✅ Deployment verification completed

🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!
=====================================

📊 Deployment Summary:
  • Duration: 45s
  • AWS Resources: 4 created (SNS, SQS, DynamoDB, Subscription)
  • Applications: 3 deployed (Producer, Consumer, DynamoDB Admin)
  • LocalStack: Running

🔗 Access Information:
  • Producer: kubectl get pods -l app=producer
  • Consumer: kubectl get pods -l app=consumer
  • DynamoDB Admin: ./pipeline/admin-bg.sh start

🧪 Testing:
  • Check producer logs: kubectl logs -l app=producer
  • Check consumer logs: kubectl logs -l app=consumer
  • Verify data: ./pipeline/admin-bg.sh start

✅ Event-driven architecture is ready!
```

## 🛠️ Configuration Options

### Environment Variables (Optional):
```bash
# Override default timeouts
export PROVIDER_TIMEOUT=180
export LOCALSTACK_TIMEOUT=300
export RESOURCE_WAIT=120

# Override AWS region
export AWS_REGION=eu-central-1
```

## 🧪 Post-Deployment Testing

After successful deployment, run comprehensive tests:
```bash
./pipeline/test.sh
```

Expected result: `ALL TESTS PASSED! (27/27)`

## 🌐 Accessing DynamoDB Admin Interface

### Quick Access (Recommended):
```bash
./pipeline/admin-bg.sh start
```

This will:
- Start port-forward in background
- Open browser automatically to http://localhost:8001
- Display table: `justtrack-dev-devops-consumer-events`

### Manual Access:
```bash
kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001
# Open: http://localhost:8001
```

## 🔧 Troubleshooting

### Common Issues:

1. **Provider Installation Timeout**
   ```bash
   # Check provider status
   kubectl describe providers provider-aws
   
   # Check provider logs
   kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws
   ```

2. **LocalStack Connection Issues**
   ```bash
   # Check LocalStack pod
   kubectl get pods -n localstack
   
   # Check LocalStack logs
   kubectl logs -n localstack -l app=localstack
   ```

3. **Resource Creation Failures**
   ```bash
   # Check Crossplane resources
   kubectl get topics,queues,tables,subscriptions
   
   # Describe specific resource
   kubectl describe topic justtrack-dev-devops-producer-events
   ```

4. **Application Deployment Issues**
   ```bash
   # Check Helm releases
   helm list
   
   # Check pod status
   kubectl get pods
   
   # Check application logs
   kubectl logs -l app=producer
   ```

### Solutions:

- **Restart deployment**: `./pipeline/cleanup.sh` then `./pipeline/deploy.sh`
- **Check prerequisites**: Ensure Docker Desktop Kubernetes is enabled
- **Verify images**: Ensure container images are accessible
- **Check resources**: Monitor CPU/memory usage

## 📈 Performance Metrics

- **Deployment Time**: 30-60 seconds typical
- **Resource Usage**: ~2GB RAM, 2 CPU cores
- **Storage**: ~5GB for container images
- **Network**: Requires internet for image pulls

## 🧹 Cleanup

To remove all deployed resources:
```bash
./pipeline/cleanup.sh
```

## 🔐 Security Notes

- Uses LocalStack with test credentials (`AWS_ACCESS_KEY_ID=test`)
- No real AWS resources created
- All traffic stays within Kubernetes cluster
- Suitable for development and testing environments

## 📚 Related Documentation

- [Testing Guide](test-README.md) - Comprehensive testing suite
- [Cleanup Guide](cleanup-README.md) - Resource cleanup procedures
- [Admin Interface Guide](admin-README.md) - DynamoDB admin access
- [Custom Deployment](deploy-custom-README.md) - Enterprise/corporate deployment

## 🎯 Best Practices

1. **Always run tests after deployment**: `./pipeline/test.sh`
2. **Monitor resource usage during deployment**
3. **Use admin interface for data inspection**: `./pipeline/admin-bg.sh start`
4. **Clean up resources when done**: `./pipeline/cleanup.sh`
5. **Check logs for troubleshooting**: `kubectl logs -l app=<component>`

## 🔄 Development Workflow

```bash
# 1. Deploy infrastructure
./pipeline/deploy.sh

# 2. Run tests to verify
./pipeline/test.sh

# 3. Access admin interface
./pipeline/admin-bg.sh start

# 4. Monitor and develop
kubectl logs -l app=producer -f

# 5. Clean up when done
./pipeline/admin-bg.sh stop
./pipeline/cleanup.sh
```

## 📊 What Gets Deployed

### Kubernetes Resources:
- **Namespaces**: `crossplane-system`, `localstack`
- **Deployments**: 4 (crossplane, localstack, producer, consumer, admin)
- **Services**: 4 (localstack, producer, consumer, admin)
- **ConfigMaps**: Crossplane configuration
- **Secrets**: AWS credentials for LocalStack

### Crossplane Resources:
- **Provider**: AWS provider for LocalStack
- **ProviderConfig**: LocalStack endpoint configuration
- **Topic**: SNS topic for event publishing
- **Queue**: SQS queue for event processing
- **Table**: DynamoDB table for data storage
- **Subscription**: SNS-SQS message routing

### Helm Releases:
- **crossplane**: Infrastructure management
- **producer**: Event generation application
- **consumer**: Event processing application
- **dynamodb-admin**: Data visualization interface

---

**This deployment script provides a clean, reliable way to set up the complete event-driven architecture for development and testing purposes.**
