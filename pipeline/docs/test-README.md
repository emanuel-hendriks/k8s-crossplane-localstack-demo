# Cloud-Native Infrastructure Testing Guide

Comprehensive testing suite for the event-driven architecture deployment with detailed verification of all components and data flow.

## 🧪 Test Script Overview

The `test.sh` script provides comprehensive validation of the entire cloud-native event-driven architecture, including:
- Infrastructure status verification
- Crossplane resource validation
- Event flow integrity testing
- DynamoDB data verification
- Admin interface accessibility
- System health monitoring

## 🚀 Quick Start

```bash
# Run comprehensive tests
./pipeline/test.sh

# Expected output: ALL TESTS PASSED! (27/27)
```

## 📋 Test Categories

### **Test 1: Infrastructure Status**
Validates that all application pods are running correctly.

**Checks**:
- ✅ Producer pod status
- ✅ Consumer pod status  
- ✅ DynamoDB Admin pod status

**Sample Output**:
```
Discovered pods:
  • Producer: producer-producer-6645d4b69-cbs9x
  • Consumer: consumer-consumer-78c6bf97f7-wv24q
  • DynamoDB Admin: dynamodb-admin-dynamodb-admin-7bfc6b97b4-bb8xw
✅ Producer pod is running
✅ Consumer pod is running
✅ DynamoDB Admin pod is running
```

### **Test 2: Crossplane Resources**
Verifies all AWS resources provisioned through Crossplane are ready and synced.

**Checks**:
- ✅ SNS Topic: `justtrack-dev-devops-producer-events`
- ✅ SQS Queue: `justtrack-dev-devops-consumer-events`
- ✅ DynamoDB Table: `justtrack-dev-devops-consumer-events`
- ✅ SNS-SQS Subscription: Message routing configuration

**Sample Output**:
```
✅ SNS Topic is ready
✅ SQS Queue is ready
✅ DynamoDB Table is ready
✅ SNS-SQS Subscription is ready
```

### **Test 3: LocalStack Connectivity & Event Flow**
Comprehensive validation of the complete event-driven architecture flow.

**Basic Flow Checks**:
- ✅ SNS events published to LocalStack
- ✅ SQS events consumed from LocalStack
- ✅ DynamoDB events stored in LocalStack
- ✅ Producer publishing events
- ✅ Consumer processing events

**Enhanced Flow Verification**:
- ✅ Producer writing to SNS with specific event IDs
- ✅ SNS-SQS subscription delivering messages
- ✅ Consumer receiving from SQS with event correlation
- ✅ Event flow correlation (Producer-Consumer sync)
- ✅ DynamoDB receiving processed events

**Sample Output**:
```
✅ Producer writing to SNS (Event #865, ID: 17a5e3a6...)
✅ SNS-SQS subscription delivering messages
✅ Consumer receiving from SQS (Event #865, ID: 17a5e3a6...)
✅ Event flow correlation verified (Producer-Consumer sync)
✅ DynamoDB receiving processed events (2 recent writes)
```

### **Test 4: DynamoDB Data Verification**
Direct validation of data storage and structure in DynamoDB.

**Checks**:
- ✅ DynamoDB table data retrieval
- ✅ Item count verification
- ✅ Data structure validation (Id, Number, CreatedAt fields)
- ✅ Sample data display

**Sample Output**:
```
✅ DynamoDB table data retrieved successfully
DynamoDB Table Status: ACTIVE
Total Items in Table: 871
✅ DynamoDB Table contains data (871 items)
✅ Items have Id field (String type)
✅ Items have Number field (Number type)
✅ Items have CreatedAt field (String type)

Sample DynamoDB Items:
=====================
{
  "Items": [
    {
      "Number": {"N": "203"},
      "Id": {"S": "f951fbaf-6d70-4f2c-8dc8-bb0f92424f67"},
      "CreatedAt": {"S": "2025-08-06T03:05:27.082984428Z"}
    }
  ]
}
```

### **Test 5: DynamoDB Admin Interface Verification**
Validates the web-based admin interface for DynamoDB data visualization.

**Checks**:
- ✅ DynamoDB Admin service exists
- ✅ HTTP 200 response verification
- ✅ Interface accessibility testing
- ✅ Access instructions provided

**Sample Output**:
```
✅ DynamoDB Admin service exists on port 8001
✅ DynamoDB Admin interface is accessible (HTTP 200)

DynamoDB Admin Interface Details:
  • URL: http://localhost:8001
  • Status: Accessible and responding
  • Table: justtrack-dev-devops-consumer-events
  • Total Items: 871 events

How to access:
  1. Quick access: ./pipeline/admin-bg.sh start
  2. Manual: kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001
  3. Open: http://localhost:8001
```

### **Test 6: Event Processing Status**
Real-time monitoring of event processing activity.

**Checks**:
- ✅ Producer publishing status
- ✅ Current producer event number
- ✅ Consumer processing readiness
- ✅ Last processed event tracking

**Sample Output**:
```
✅ Producer is publishing events
Current Producer Event: #877
✅ Consumer is ready to process events
Last processed event: #877
```

### **Test 7: System Health Summary**
Overall system health and deployment status.

**Checks**:
- ✅ Helm releases deployment status
- ✅ Crossplane resources readiness
- ✅ System component counts

**Sample Output**:
```
✅ All Helm releases are deployed (3/3)
✅ All Crossplane resources are ready (4/4)
```

## 📊 Test Results Summary

### Success Output:
```
TEST RESULTS SUMMARY
======================

✅ ALL TESTS PASSED! (27/27)

✨ Event-Driven Architecture Status: FULLY OPERATIONAL ✨

📈 System Summary:
  • Total Events Stored: 871
  • DynamoDB Table: ACTIVE with complete data
  • Admin Interface: Accessible at http://localhost:8001
  • Producer Status: RUNNING
  • Consumer Status: READY

🔗 Complete Event Flow:
  Producer → SNS Topic → SQS Queue → Consumer → DynamoDB
     PASS         PASS          PASS         PASS         PASS

🛠️ Management Commands:
  • Start Producer: kubectl scale deployment producer-producer --replicas=1
  • Stop Producer: kubectl scale deployment producer-producer --replicas=0
  • View DynamoDB: ./pipeline/admin-bg.sh start
  • Monitor Consumer: kubectl logs consumer-consumer-78c6bf97f7-wv24q -f
```

## 🌐 DynamoDB Admin Interface Access

The test script verifies admin interface accessibility, but to actually use it:

### **Quick Access (Recommended)**:
```bash
# Start admin interface in background
./pipeline/admin-bg.sh start

# Check status
./pipeline/admin-bg.sh status

# Stop when done
./pipeline/admin-bg.sh stop
```

### **Manual Access**:
```bash
# Start port-forward
kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001

# Open browser to: http://localhost:8001
# Navigate to table: justtrack-dev-devops-consumer-events
```

### **Available Admin Scripts**:
- `./pipeline/admin-bg.sh` - Background service management
- `./pipeline/admin.sh` - Interactive mode

## 🔍 Detailed Event Flow Verification

The test script now includes comprehensive event flow verification:

### **Event Correlation Tracking**:
```
Producer Event: #865, ID: 17a5e3a6-c975-47ab-b794-a427d07241cb
Consumer Event: #865, ID: 17a5e3a6-c975-47ab-b794-a427d07241cb
✅ Perfect correlation - same event processed end-to-end
```

### **Real-time Flow Monitoring**:
1. **Producer** publishes event with unique ID to **SNS**
2. **SNS** delivers event to **SQS** via subscription
3. **Consumer** receives same event ID from **SQS**
4. **Consumer** stores event in **DynamoDB**
5. **Admin Interface** displays stored event

## 🛠️ Troubleshooting

### **Test Failures**:

1. **Infrastructure Issues**:
   ```bash
   # Check pod status
   kubectl get pods
   
   # Check pod logs
   kubectl logs <pod-name>
   ```

2. **Crossplane Resource Issues**:
   ```bash
   # Check resource status
   kubectl get topics,queues,tables,subscriptions
   
   # Describe specific resource
   kubectl describe topic justtrack-dev-devops-producer-events
   ```

3. **Event Flow Issues**:
   ```bash
   # Check producer logs
   kubectl logs -l app=producer
   
   # Check consumer logs
   kubectl logs -l app=consumer
   
   # Check LocalStack logs
   kubectl logs -n localstack -l app=localstack
   ```

4. **DynamoDB Access Issues**:
   ```bash
   # Check LocalStack pod
   kubectl get pods -n localstack
   
   # Test direct DynamoDB access
   kubectl exec -n localstack <localstack-pod> -- aws dynamodb list-tables --endpoint-url http://localhost:4566
   ```

5. **Admin Interface Issues**:
   ```bash
   # Check admin pod
   kubectl get pods | grep dynamodb-admin
   
   # Check admin service
   kubectl get svc dynamodb-admin-dynamodb-admin
   
   # Test port-forward
   kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001
   ```

### **Common Solutions**:

- **Restart failed pods**: `kubectl delete pod <pod-name>`
- **Check resource events**: `kubectl describe <resource-type> <resource-name>`
- **Verify LocalStack connectivity**: Check LocalStack pod logs
- **Restart admin interface**: `./pipeline/admin-bg.sh restart`

## 📈 Performance Metrics

### **Test Execution Time**:
- **Total Duration**: ~30-45 seconds
- **Infrastructure Tests**: ~5 seconds
- **Event Flow Tests**: ~15 seconds
- **Data Verification**: ~10 seconds
- **Admin Interface Tests**: ~5 seconds

### **Resource Verification**:
- **Pods**: 3 application pods + LocalStack
- **Services**: 4 services (producer, consumer, admin, localstack)
- **Crossplane Resources**: 4 AWS resources
- **Data Volume**: 800+ events typically stored

## 🔄 Continuous Testing

### **Automated Testing**:
```bash
# Run tests every 30 seconds
watch -n 30 './pipeline/test.sh'

# Run tests with timestamp
while true; do echo "=== $(date) ==="; ./pipeline/test.sh; sleep 60; done
```

### **Selective Testing**:
The test script runs all tests by default, but you can monitor specific components:

```bash
# Monitor producer logs
kubectl logs -l app=producer -f

# Monitor consumer logs  
kubectl logs -l app=consumer -f

# Monitor LocalStack logs
kubectl logs -n localstack -l app=localstack -f
```

## 📚 Related Documentation

- [Deployment Guide](deploy-README.md)
- [Cleanup Guide](cleanup-README.md)
- [Admin Interface Scripts](../admin-bg.sh)

## 🎯 Best Practices

1. **Run tests after every deployment**
2. **Monitor event flow correlation**
3. **Verify data persistence in DynamoDB**
4. **Use admin interface for data inspection**
5. **Check logs for detailed troubleshooting**
6. **Ensure all 27 tests pass before proceeding**

---

**The test suite provides comprehensive validation of the entire event-driven architecture, ensuring all components work together seamlessly from event generation to data storage and visualization.**
