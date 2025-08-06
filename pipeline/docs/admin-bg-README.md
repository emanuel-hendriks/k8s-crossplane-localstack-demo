# DynamoDB Admin Interface Access Scripts

Automated scripts for accessing the DynamoDB Admin web interface without manual port-forwarding.

## 📁 Available Scripts

### 🚀 `admin-bg.sh` - Background Service Manager
**Purpose**: Manages DynamoDB Admin interface as a background service with automatic browser opening.

**Features**:
- ✅ Background port-forward management
- ✅ Automatic browser opening
- ✅ Service status monitoring
- ✅ PID-based process management
- ✅ Start/stop/restart/status commands

### 🖥️ `admin.sh` - Interactive Interface
**Purpose**: Interactive port-forward with manual control and cleanup.

**Features**:
- ✅ Interactive port-forward session
- ✅ Automatic cleanup on exit
- ✅ Real-time connection monitoring
- ✅ Manual browser opening
- ✅ Ctrl+C to stop

## 🚀 Quick Start

### **Recommended: Background Service**
```bash
# Start admin interface (opens browser automatically)
./pipeline/admin-bg.sh start

# Check if running
./pipeline/admin-bg.sh status

# Stop when done
./pipeline/admin-bg.sh stop
```

### **Alternative: Interactive Mode**
```bash
# Start interactive session
./pipeline/admin.sh

# Press Ctrl+C to stop
```

## 📋 Background Service Commands

### **Start Service**
```bash
./pipeline/admin-bg.sh start
```

**Output**:
```
🚀 Starting DynamoDB Admin Interface (Background)
================================================
✅ DynamoDB Admin interface started successfully!
ℹ️  🌐 URL: http://localhost:8001
ℹ️  📊 Table: justtrack-dev-devops-consumer-events
ℹ️  🔧 PID: 9842

Commands:
  • Open browser: open http://localhost:8001
  • Stop service: ./pipeline/admin-bg.sh stop
  • Check status: ./pipeline/admin-bg.sh status
ℹ️  Opening browser...
```

### **Check Status**
```bash
./pipeline/admin-bg.sh status
```

**Output**:
```
📊 DynamoDB Admin Interface Status
==================================
✅ Running (PID: 9842)
✅ Interface accessible at http://localhost:8001
```

### **Stop Service**
```bash
./pipeline/admin-bg.sh stop
```

**Output**:
```
🛑 Stopping DynamoDB Admin Interface
====================================
✅ Admin interface stopped (PID: 9842)
```

### **Restart Service**
```bash
./pipeline/admin-bg.sh restart
```

## 🖥️ Interactive Mode

### **Start Interactive Session**
```bash
./pipeline/admin.sh
```

**Output**:
```
🌐 DynamoDB Admin Interface Launcher
====================================

✅ DynamoDB Admin service found
✅ DynamoDB Admin pod is running: dynamodb-admin-dynamodb-admin-7bfc6b97b4-bb8xw
ℹ️  Starting port-forward to DynamoDB Admin interface...
ℹ️  Waiting for connection to establish...
✅ DynamoDB Admin interface is accessible!
ℹ️  URL: http://localhost:8001
ℹ️  Table: justtrack-dev-devops-consumer-events
ℹ️  Opening browser...

🎯 Instructions:
  1. Browser should open automatically to http://localhost:8001
  2. Look for table: justtrack-dev-devops-consumer-events
  3. Click on the table to view stored events
  4. You'll see events with Id, Number, and CreatedAt fields

⚠️  Keep this script running to maintain the connection
ℹ️  Press Ctrl+C to stop the admin interface

Port-forward is active. Waiting...
```

## 🌐 Using the Admin Interface

### **Accessing the Interface**:
1. **URL**: http://localhost:8001
2. **Table**: `justtrack-dev-devops-consumer-events`
3. **Data**: Real-time event data from the producer-consumer flow

### **What You'll See**:
```json
{
  "Id": "f951fbaf-6d70-4f2c-8dc8-bb0f92424f67",
  "Number": 203,
  "CreatedAt": "2025-08-06T03:05:27.082984428Z"
}
```

### **Interface Features**:
- ✅ **Table Browser**: Navigate between DynamoDB tables
- ✅ **Data Viewer**: View individual items and their attributes
- ✅ **Real-time Updates**: See new events as they're processed
- ✅ **Search/Filter**: Find specific events by attributes
- ✅ **Export Options**: Download data in various formats

## 🔧 Technical Details

### **Port Configuration**:
- **Local Port**: 8001
- **Service Port**: 8001
- **Protocol**: HTTP
- **Service**: `dynamodb-admin-dynamodb-admin`

### **Process Management**:
- **PID File**: `.admin-port-forward.pid`
- **Background Process**: `kubectl port-forward`
- **Auto-cleanup**: On script exit or termination

### **Browser Support**:
- **macOS**: Automatic opening with `open` command
- **Other OS**: Manual browser navigation required

## 🛠️ Troubleshooting

### **Common Issues**:

1. **Port Already in Use**:
   ```bash
   # Check what's using port 8001
   lsof -i :8001
   
   # Kill existing process
   kill <PID>
   
   # Or use different port (modify script)
   ```

2. **Service Not Found**:
   ```bash
   # Check if deployment is running
   kubectl get svc dynamodb-admin-dynamodb-admin
   
   # Redeploy if needed
   ./pipeline/deploy.sh
   ```

3. **Pod Not Running**:
   ```bash
   # Check pod status
   kubectl get pods | grep dynamodb-admin
   
   # Check pod logs
   kubectl logs <dynamodb-admin-pod>
   ```

4. **Connection Refused**:
   ```bash
   # Check service endpoints
   kubectl get endpoints dynamodb-admin-dynamodb-admin
   
   # Test direct pod access
   kubectl port-forward pod/<admin-pod> 8001:8001
   ```

5. **Browser Not Opening**:
   ```bash
   # Manual browser opening
   open http://localhost:8001
   
   # Or copy URL to browser
   echo "http://localhost:8001"
   ```

### **Debug Commands**:
```bash
# Check service status
kubectl get svc dynamodb-admin-dynamodb-admin

# Check pod status
kubectl get pods -l app.kubernetes.io/instance=dynamodb-admin

# Test connectivity
curl -s -o /dev/null -w "%{http_code}" http://localhost:8001

# Check port-forward process
ps aux | grep "port-forward"
```

## 📈 Performance Considerations

### **Resource Usage**:
- **CPU**: Minimal (port-forward process)
- **Memory**: ~10MB for port-forward
- **Network**: Local traffic only
- **Startup Time**: 2-3 seconds

### **Scalability**:
- **Concurrent Users**: Single port-forward supports multiple browser sessions
- **Data Volume**: Interface handles large datasets efficiently
- **Real-time Updates**: Manual refresh required for new data

## 🔐 Security Notes

### **Local Access Only**:
- Port-forward creates local-only connection
- No external network exposure
- Traffic stays within Kubernetes cluster

### **Authentication**:
- No authentication required (local development)
- DynamoDB uses LocalStack test credentials
- Admin interface has no built-in security

### **Data Privacy**:
- All data remains in local Kubernetes cluster
- No external data transmission
- LocalStack simulates AWS services locally

## 🎯 Best Practices

### **Usage Recommendations**:
1. **Use background service for continuous access**
2. **Stop service when not needed to free resources**
3. **Check status before starting new sessions**
4. **Use restart command if connection issues occur**
5. **Monitor resource usage in long-running sessions**

### **Development Workflow**:
```bash
# Start development session
./pipeline/deploy.sh
./pipeline/admin-bg.sh start

# Develop and test
./pipeline/test.sh

# View data changes
# (Browser already open at http://localhost:8001)

# Clean up when done
./pipeline/admin-bg.sh stop
./pipeline/cleanup.sh
```

## 📚 Integration with Other Scripts

### **Test Script Integration**:
The test script (`test.sh`) automatically verifies admin interface accessibility but doesn't start it. Use admin scripts for actual access.

### **Deploy Script Integration**:
Deploy scripts create the admin interface but don't start port-forwarding. Use admin scripts post-deployment.

### **Cleanup Integration**:
Cleanup script removes admin interface. Stop admin scripts before cleanup.

## 📊 Monitoring and Logging

### **Service Monitoring**:
```bash
# Continuous status monitoring
watch -n 5 './pipeline/admin-bg.sh status'

# Log port-forward activity
kubectl logs -f deployment/dynamodb-admin-dynamodb-admin
```

### **Connection Testing**:
```bash
# Test connection every 30 seconds
while true; do
  curl -s -o /dev/null -w "$(date): %{http_code}\n" http://localhost:8001
  sleep 30
done
```

## 🔄 Advanced Usage

### **Custom Port Configuration**:
Modify scripts to use different ports if 8001 is unavailable:

```bash
# Edit admin-bg.sh
# Change: kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8001:8001
# To:     kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8002:8001
```

### **Multiple Environments**:
Run multiple admin interfaces for different deployments:

```bash
# Environment 1 (port 8001)
./pipeline/admin-bg.sh start

# Environment 2 (port 8002) - requires script modification
# kubectl port-forward svc/dynamodb-admin-dynamodb-admin 8002:8001
```

---

**The admin scripts provide seamless access to the DynamoDB Admin interface, eliminating the need for manual port-forwarding and enabling efficient data visualization and monitoring.**
