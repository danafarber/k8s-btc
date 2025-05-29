# BTC Kubernetes Cluster - Production Ready Deployment

## Overview

This project deploys a production-ready Kubernetes cluster using AKS-Engine with Bitcoin price tracking system meeting all specified requirements.

## What It Does

**Infrastructure:**
- Creates AKS-Engine based Kubernetes cluster (not managed AKS)
- Enables RBAC for security
- Deploys NGINX Ingress controller for traffic routing
- Implements network policies for service isolation

**Applications:**
- **Service A (Bitcoin API)**: Fetches Bitcoin prices every minute, calculates 10-minute averages
- **Service B**: Simple web service isolated from Service A
- **Network Policy**: Prevents Service A from communicating with Service B
- **URL Routing**: `/service-a/` and `/service-b/` paths via Ingress

**Production Features:**
- Liveness and readiness probes
- Resource limits and requests
- Health monitoring
- Automated deployment
- Fully repeatable process

## Requirements Met

1. **AKS-Engine cluster** (not pre-defined AKS)
2. **RBAC enabled**
3. **2 services: A and B**
4. **Ingress controller** with URL routing (`/service-a`, `/service-b`)
5. **Network policy** blocking Service A to Service B communication
6. **Service A** fetches Bitcoin prices every minute + 10-minute averages

## Prerequisites

- Azure CLI with active subscription
- kubectl
- PowerShell 5.1+
- SSH key pair at `~/.ssh/id_rsa`

## Quick Start

### Installation
```powershell
# Install required tools
winget install Microsoft.AzureCLI
az aks install-cli
az login
```

### Deployment
```powershell
# One command deployment
.\scripts\deploy-complete-fixed.ps1
```

**Deployment time: 10-15 minutes**

### Custom Configuration
```powershell
.\scripts\deploy.ps1 -ResourceGroup "my-rg" -Location "mylocation"
```

## Project Structure

btc-k8s-cluster/
├── scripts/
│   └── deploy.ps1                  # Main deployment script
├── cluster/
│   └── btc-k8s.json                # AKS-Engine cluster definition
├── k8s/
│   └── deploy.yaml                 # Kubernetes manifests
├── src/
│   ├── service-a/                # Service A source code
│   │   ├── app.py                  # Bitcoin API application
│   │   └── Dockerfile              # Container build file
│   └── service-b/                  # Service B source code
│       ├── app.py                  # Simple web service
│       └── Dockerfile              # Container build file
└── README.md

## Verification

### Expected Output
After deployment, you should see:
- 1 master + 2 worker nodes in "Ready" state
- Bitcoin API pod fetching prices every minute
- Service B pod running
- NGINX Ingress controller operational
- Network policy blocking Service A to Service B

### Check Logs
```bash
# SSH to master
ssh -i ~/.ssh/id_rsa azureuser@<MASTER_IP>

# View Bitcoin API logs
kubectl logs -f <bitcoin-api-pod-name>

# Expected log pattern:
# [timestamp] Bitcoin Price: $42,123.45
# [timestamp] Bitcoin Price: $42,156.78
# ...
# [timestamp] 10-Minute Average Bitcoin Price: $42,089.78
```

### Test Network Policy
```bash
# This should fail (network policy working)
kubectl exec <service-a-pod> -- curl http://service-b:8080/health
```

## Key Components

### AKS-Engine Cluster
- **Master**: 1x Standard_D2s_v3 VM
- **Agents**: 2x Standard_D2s_v3 VMs
- **RBAC**: Enabled
- **Network**: Azure CNI with network policies

### Service A - Bitcoin API
- Fetches Bitcoin prices from CoinDesk API every 60 seconds
- Calculates 10-minute rolling averages
- Endpoints: `/health`, `/ready`, `/price`, `/average`, `/status`
- Fallback to CoinGecko API for reliability

### Service B - Web Service
- Simple HTTP service for testing isolation
- Endpoints: `/health`, `/ready`, `/status`
- Cannot be accessed by Service A due to network policy

### Network Architecture
```
Internet → Load Balancer → NGINX Ingress → Services
                                     ↓
                          /service-a/ → Bitcoin API
                          /service-b/ → Service B
                                     ↓
                          Network Policy Blocks A→B
```




### Debug Commands
```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get services,ingress --all-namespaces
kubectl get events --sort-by='.lastTimestamp'
```

## Cleanup

```powershell
# Remove all resources
az group delete --name rg-k8s-new --yes --no-wait
```

## Files Included

- **deploy.ps1** - Main deployment script
- **btc-k8s.json** - AKS-Engine cluster definition
- **deploy.yaml** - Kubernetes manifests
- **README.md** - This documentation

## Technical Details

### Security
- RBAC enabled with service accounts
- Network policies for service isolation
- Private cluster communication
- SSH key-based authentication

### Monitoring
- Liveness probes for container health
- Readiness probes for traffic routing
- Resource limits and requests
- Health check endpoints

### Production Ready
- Automated deployment process
- Repeatable infrastructure as code
- Error handling and validation
- Comprehensive logging
- Health monitoring

This deployment provides a complete, production-ready Kubernetes cluster meeting all specified requirements with full automation and monitoring capabilities.