# Cleanup Script Documentation

## Overview

The [`cleanup.sh`](../cleanup.sh) script provides comprehensive cleanup of all deployed cloud-native infrastructure resources. It safely removes all components created by the deployment script, ensuring a clean environment for future deployments or complete system removal.

## Purpose

This cleanup script serves multiple critical functions:
- **Complete Resource Removal**: Safely removes all deployed applications and infrastructure
- **Force Deletion Capabilities**: Handles stuck resources with advanced deletion techniques
- **Verification System**: Confirms all resources are properly removed
- **Environment Reset**: Prepares the environment for fresh deployments
- **Conflict Prevention**: Eliminates leftover state that could cause deployment issues

## Cleanup Process

### Step 1: Application Removal
- **Helm Applications**: Uninstalls producer, consumer, and DynamoDB Admin applications
- **Graceful Shutdown**: Allows applications to terminate properly
- **Resource Cleanup**: Removes associated pods, services, and deployments

### Step 2: AWS Resource Cleanup
- **Crossplane Resources**: Removes SNS topics, SQS queues, DynamoDB tables, and subscriptions
- **Force Deletion**: Handles stuck resources with finalizer patching
- **Dependency Management**: Removes resources in proper order to avoid conflicts

### Step 3: Provider and Configuration Cleanup
- **AWS Provider**: Removes the Crossplane AWS provider
- **ProviderConfig**: Cleans up LocalStack endpoint configuration
- **Secrets**: Removes AWS credentials and certificates
- **ConfigMaps**: Cleans up certificate and configuration data

### Step 4: LocalStack Removal
- **Namespace Deletion**: Completely removes the LocalStack namespace
- **Timeout Handling**: Waits for proper namespace deletion with timeout protection
- **Force Cleanup**: Uses aggressive deletion for stuck namespace resources

### Step 5: Test Resource Cleanup
- **Test Pods**: Removes all temporary test and debug pods
- **Verification Resources**: Cleans up connectivity test resources
- **Debug Resources**: Removes AWS CLI and network test pods

### Step 6: Comprehensive Verification
- **Resource Verification**: Confirms all resources are properly removed
- **Detailed Reporting**: Provides pass/fail status for each cleanup category
- **Environment Status**: Reports final environment state

## Usage

### Basic Cleanup
```bash
./cleanup.sh
```

### Prerequisites
- kubectl access to the cluster
- Proper permissions to delete resources
- No external dependencies on the deployed resources

## Advanced Features

### Force Deletion Mechanism
The script includes sophisticated force deletion capabilities for stuck resources:

```bash
# Automatic finalizer removal for stuck resources
kubectl patch <resource-type> <resource-name> -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete <resource-type> <resource-name> --force --grace-period=0
```

### Intelligent Resource Detection
- **Dynamic Discovery**: Automatically finds all related resources
- **Dependency Awareness**: Removes resources in proper dependency order
- **Namespace Handling**: Manages both namespaced and cluster-wide resources

### Comprehensive Verification System
The script performs detailed verification across multiple categories:

#### Application Resources
- Helm releases removal verification
- Pod and service cleanup confirmation
- Deployment and ReplicaSet removal

#### Infrastructure Resources
- Crossplane custom resources (Topics, Queues, Tables, Subscriptions)
- Provider and ProviderConfig removal
- Secret and ConfigMap cleanup

#### System Resources
- Namespace deletion confirmation
- Test pod cleanup verification
- Service account and RBAC cleanup

## Cleanup Output

### Success Scenario
```
Cleaning Up Cloud-Native Event-Driven Architecture
====================================================

Step 1: Removing Applications
============================
✅ producer removed successfully
✅ consumer removed successfully  
✅ dynamodb-admin removed successfully

Step 2: Removing AWS Resources
==============================
✅ SNS Topic removed
✅ SQS Queue removed
✅ DynamoDB Table removed
✅ SNS-SQS Subscription removed

Step 3: Removing Provider Configuration
=======================================
✅ AWS Provider removed
✅ ProviderConfig removed
✅ AWS credentials secret removed

Step 4: Removing LocalStack
==========================
✅ LocalStack namespace removed

Step 5: Cleaning Up Test Resources
=================================
✅ Test pods cleaned up

Step 6: Verification
===================
✅ All checks passed: 15/15

Environment Status:
  All application resources removed
  All AWS resources cleaned up
  All test resources removed
  LocalStack completely removed
  No leftover pods or services

Environment is ready for fresh deployment!
```

### Verification Categories
The script performs **15 comprehensive verification checks**:

1. **Application Verification**
   - Helm releases removed
   - Application pods removed
   - Application services removed

2. **Infrastructure Verification**
   - Crossplane resources removed
   - Provider configuration removed
   - Secrets and ConfigMaps removed

3. **System Verification**
   - LocalStack namespace removed
   - Test resources removed
   - No leftover system resources

## Error Handling

### Stuck Resource Management
The script handles common stuck resource scenarios:

**Finalizer Issues**
- Automatically patches finalizers for stuck custom resources
- Forces deletion when normal deletion fails
- Provides detailed error reporting

**Namespace Deletion Issues**
- Implements timeout-based waiting for namespace deletion
- Uses force deletion for stuck namespaces
- Reports on deletion progress

**Dependency Conflicts**
- Removes resources in proper dependency order
- Handles circular dependencies gracefully
- Provides clear error messages for manual intervention

### Common Issues and Solutions

**Crossplane Resources Won't Delete**
```bash
# The script automatically handles this with:
kubectl patch <resource> -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete <resource> --force --grace-period=0
```

**LocalStack Namespace Stuck**
```bash
# The script waits up to 2 minutes and then forces deletion
kubectl delete namespace localstack --force --grace-period=0
```

**Helm Releases Won't Uninstall**
```bash
# The script uses force uninstall with timeout
helm uninstall <release> --timeout=60s
```

## Safety Features

### Confirmation and Validation
- **Resource Existence Checks**: Only attempts to delete existing resources
- **Graceful Degradation**: Continues cleanup even if some resources fail
- **Detailed Logging**: Provides clear feedback on all operations

### Non-Destructive Verification
- **Read-Only Checks**: Verification phase only reads resource status
- **Comprehensive Reporting**: Shows exactly what was and wasn't cleaned up
- **Safe to Re-run**: Can be executed multiple times safely

## Integration with Deployment Lifecycle

### Typical Usage Pattern
```bash
# Deploy the system
./deploy.sh

# Test the deployment
./test.sh

# Clean up when finished
./cleanup.sh

# Deploy again (clean environment)
./deploy.sh
```

### Development Workflow
- **Iterative Development**: Clean environment for each deployment iteration
- **Testing Cycles**: Reset environment between test runs
- **Troubleshooting**: Clean slate for debugging deployment issues

## Exit Codes

- **0**: Cleanup completed successfully, all verification passed
- **1**: Cleanup completed but some verification checks failed

## Best Practices

### When to Use Cleanup
- **After Testing**: Clean up test environments
- **Before Redeployment**: Ensure clean state for new deployments
- **Troubleshooting**: Reset environment when debugging issues
- **Environment Maintenance**: Regular cleanup of development environments

### What Gets Preserved
The cleanup script preserves:
- **Kubernetes System Resources**: Core Kubernetes components remain untouched
- **Other Namespaces**: Only removes resources in default and localstack namespaces
- **Crossplane Core**: Removes providers but preserves Crossplane installation
- **Cluster Configuration**: kubectl context and cluster access remain unchanged

### Post-Cleanup State
After successful cleanup:
- Environment is ready for fresh deployment
- No resource conflicts will occur
- All application data is removed
- System is in clean, known state

The cleanup script ensures a thorough, safe, and verifiable removal of all deployed resources while preserving the underlying Kubernetes infrastructure.
