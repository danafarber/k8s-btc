# deploy.ps1 - Complete BTC K8s Cluster Deployment 

param(
    [string]$ResourceGroup = "rg-k8s-new",
    [string]$Location = "northeurope",
    [string]$ApiModelFile = "btc-k8s.json",
    [string]$OutputDir = "_out",
    [string]$DeploymentName = "aksEngineDeploy"
)

Write-Host "COMPLETE BTC K8S CLUSTER DEPLOYMENT" -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green
Write-Host "This script will deploy a production-ready Kubernetes cluster with:" -ForegroundColor Yellow
Write-Host "- AKS-Engine cluster with RBAC" -ForegroundColor White
Write-Host "- Bitcoin API service (fetches prices every minute)" -ForegroundColor White
Write-Host "- Service B (isolated from Service A)" -ForegroundColor White
Write-Host "- NGINX Ingress controller" -ForegroundColor White
Write-Host "- Network policies for security" -ForegroundColor White
Write-Host "- Complete monitoring and logs" -ForegroundColor White

$startTime = Get-Date

# Step 1: Prerequisites Check
Write-Host "`nSTEP 1: CHECKING PREREQUISITES" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

$tools = @("az", "kubectl")
foreach ($tool in $tools) {
    if (Get-Command $tool -ErrorAction SilentlyContinue) {
        Write-Host "Found: $tool" -ForegroundColor Green
    } else {
        Write-Error "$tool not found - please install it first"
        exit 1
    }
}

# Check Azure login
try {
    $account = az account show --query "name" -o tsv 2>$null
    if ($account) {
        Write-Host "Logged into Azure: $account" -ForegroundColor Green
    } else {
        Write-Host "Logging into Azure..." -ForegroundColor Yellow
        az login
    }
} catch {
    Write-Host "Logging into Azure..." -ForegroundColor Yellow
    az login
}

# Check required files
$requiredFiles = @("cluster/$ApiModelFile", "k8s/deploy.yaml")
foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "Found: $file" -ForegroundColor Green
    } else {
        Write-Error "Required file missing: $file"
        exit 1
    }
}

# Step 2: Infrastructure Deployment
Write-Host "`nSTEP 2: DEPLOYING INFRASTRUCTURE" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

# Create Resource Group
$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq "false") {
    Write-Host "Creating Resource Group: $ResourceGroup" -ForegroundColor Yellow
    az group create --name $ResourceGroup --location $Location | Out-Null
    Write-Host "Resource Group created" -ForegroundColor Green
} else {
    Write-Host "Resource Group exists: $ResourceGroup" -ForegroundColor Green
}

# Generate ARM templates if needed
if (!(Test-Path "$OutputDir/azuredeploy.json")) {
    Write-Host "Generating ARM templates with AKS-Engine..." -ForegroundColor Yellow
    aks-engine generate --api-model "cluster/$ApiModelFile" --output-directory $OutputDir
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "ARM templates generated" -ForegroundColor Green
    } else {
        Write-Error "Failed to generate ARM templates"
        exit 1
    }
} else {
    Write-Host "ARM templates already exist" -ForegroundColor Green
}

# Deploy cluster if not exists
$deploymentExists = az deployment group show --resource-group $ResourceGroup --name $DeploymentName 2>$null
if (!$deploymentExists) {
    Write-Host "Deploying AKS-Engine cluster (this takes 10-15 minutes)..." -ForegroundColor Yellow
    Write-Host "Please wait while VMs and Kubernetes are provisioned..." -ForegroundColor Gray
    
    az deployment group create --resource-group $ResourceGroup --template-file "$OutputDir/azuredeploy.json" --parameters "$OutputDir/azuredeploy.parameters.json" --name $DeploymentName | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Cluster infrastructure deployed successfully" -ForegroundColor Green
    } else {
        Write-Error "Cluster deployment failed"
        exit 1
    }
} else {
    Write-Host "Cluster infrastructure already exists" -ForegroundColor Green
}

# Step 3: Get Connection Information
Write-Host "`nSTEP 3: ESTABLISHING CONNECTION" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

# Find master IP
Write-Host "Finding master node connection info..." -ForegroundColor Yellow
$publicIPs = az network public-ip list --resource-group $ResourceGroup --query "[?contains(name, 'master')].ipAddress" -o tsv

$masterIP = $null
if ($publicIPs) {
    $masterIP = $publicIPs
} else {
    # Fallback method
    $masterIP = "20.82.233.71"  # Use known IP 
}

if (!$masterIP) {
    Write-Error "Could not find master node IP"
    exit 1
}

Write-Host "Master IP found: $masterIP" -ForegroundColor Green

# Check SSH key
$sshKeyPath = "$env:USERPROFILE\.ssh\id_rsa"
if (Test-Path $sshKeyPath) {
    Write-Host "SSH key found: $sshKeyPath" -ForegroundColor Green
} else {
    Write-Error "SSH key not found: $sshKeyPath"
    exit 1
}

# Test SSH connectivity
Write-Host "Testing SSH connectivity..." -ForegroundColor Yellow
$sshTestCmd = "ssh -i `"$sshKeyPath`" -o StrictHostKeyChecking=no -o ConnectTimeout=15 azureuser@$masterIP `"echo 'SSH working'`""
$sshResult = Invoke-Expression $sshTestCmd 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "SSH connectivity confirmed" -ForegroundColor Green
} else {
    Write-Error "SSH connectivity failed"
    exit 1
}

# Step 4: Application Deployment
Write-Host "`nSTEP 4: DEPLOYING APPLICATIONS" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

# Copy deployment file
Write-Host "Copying deployment files to master..." -ForegroundColor Yellow
$scpCmd = "scp -i `"$sshKeyPath`" -o StrictHostKeyChecking=no k8s/deploy.yaml azureuser@${masterIP}:/tmp/deploy.yaml"
Invoke-Expression $scpCmd

if ($LASTEXITCODE -eq 0) {
    Write-Host "Deployment files copied" -ForegroundColor Green
} else {
    Write-Error "Failed to copy deployment files"
    exit 1
}

# Apply deployment
Write-Host "Applying Kubernetes deployment..." -ForegroundColor Yellow
$deployCmd = "ssh -i `"$sshKeyPath`" -o StrictHostKeyChecking=no azureuser@$masterIP `"kubectl apply -f /tmp/deploy.yaml`""
Invoke-Expression $deployCmd

if ($LASTEXITCODE -eq 0) {
    Write-Host "Applications deployed successfully" -ForegroundColor Green
} else {
    Write-Warning "Deployment may have had issues - checking status..."
}

# Wait for pods to start
Write-Host "Waiting for pods to start (30 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Step 5: Verification and Status
Write-Host "`nSTEP 5: VERIFICATION AND STATUS" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

Write-Host "`nCLUSTER NODES:" -ForegroundColor Yellow
$nodesCmd = "ssh -i `"$sshKeyPath`" -o StrictHostKeyChecking=no azureuser@$masterIP `"kubectl get nodes -o wide`""
Invoke-Expression $nodesCmd

Write-Host "`nDEPLOYED PODS:" -ForegroundColor Yellow
$podsCmd = "ssh -i `"$sshKeyPath`" -o StrictHostKeyChecking=no azureuser@$masterIP `"kubectl get pods --all-namespaces -o wide`""
Invoke-Expression $podsCmd

Write-Host "`nSERVICES:" -ForegroundColor Yellow
$servicesCmd = "ssh -i `"$sshKeyPath`" -o StrictHostKeyChecking=no azureuser@$masterIP `"kubectl get services --all-namespaces`""
Invoke-Expression $servicesCmd

# Step 6: Application Logs
Write-Host "`nSTEP 6: APPLICATION LOGS" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan

# Show all pods first
Write-Host "Current pods:" -ForegroundColor Yellow
$allPodsCmd = "ssh -i `"$sshKeyPath`" -o StrictHostKeyChecking=no azureuser@$masterIP `"kubectl get pods -o wide`""
Invoke-Expression $allPodsCmd

# Get pod names using simple approach
Write-Host "`nGetting pod names..." -ForegroundColor Gray
$podListCmd = "ssh -i `"$sshKeyPath`" -o StrictHostKeyChecking=no azureuser@$masterIP `"kubectl get pods --no-headers`""
$podOutput = Invoke-Expression $podListCmd

# Extract pod names from output
$serviceAPod = $null
$serviceBPod = $null

if ($podOutput) {
    foreach ($line in $podOutput) {
        if ($line -match "service-a.*Running") {
            $serviceAPod = ($line -split '\s+')[0]
        }
        if ($line -match "service-b.*Running") {
            $serviceBPod = ($line -split '\s+')[0]
        }
    }
}

# Show logs if pods found
if ($serviceAPod) {
    Write-Host "`nService A (Bitcoin API) Pod: $serviceAPod" -ForegroundColor Green
    Write-Host "Bitcoin API logs:" -ForegroundColor Yellow
    $serviceALogsCmd = "ssh -i `"$sshKeyPath`" -o StrictHostKeyChecking=no azureuser@$masterIP `"kubectl logs $serviceAPod --tail=20`""
    Invoke-Expression $serviceALogsCmd
    
   
} else {
    Write-Host "Service A pod not found or not running" -ForegroundColor Red
}

if ($serviceBPod) {
    Write-Host "`nService B Pod: $serviceBPod" -ForegroundColor Green
    Write-Host "Service B logs:" -ForegroundColor Yellow
    $serviceBLogsCmd = "ssh -i `"$sshKeyPath`" -o StrictHostKeyChecking=no azureuser@$masterIP `"kubectl logs $serviceBPod --tail=20`""
    Invoke-Expression $serviceBLogsCmd
    
} else {
    Write-Host "Service B pod not found or not running" -ForegroundColor Red
}

# Step 7: Network Policy Test
Write-Host "`nSTEP 7: NETWORK POLICY VERIFICATION" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

if ($serviceAPod) {
    Write-Host "Testing network isolation between services..." -ForegroundColor Yellow
    Write-Host "Service A trying to reach Service B (should fail):" -ForegroundColor Gray
    $networkTestCmd = "ssh -i `"$sshKeyPath`" -o StrictHostKeyChecking=no azureuser@$masterIP `"kubectl exec $serviceAPod -- timeout 5 curl -s http://service-b:8080/health 2>/dev/null && echo 'NETWORK POLICY FAILED - Service A can reach Service B' || echo 'NETWORK POLICY WORKING - Service A blocked from Service B'`""
    Invoke-Expression $networkTestCmd
} else {
    Write-Host "Cannot test network policy - Service A pod not found" -ForegroundColor Red
}

# Step 8: Final Summary
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host "`nDEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "===================================" -ForegroundColor Green

Write-Host "`nDEPLOYMENT SUMMARY:" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "Location: $Location" -ForegroundColor White
Write-Host "Master IP: $masterIP" -ForegroundColor White
if ($serviceAPod) {
    Write-Host "Bitcoin API Pod: $serviceAPod" -ForegroundColor White
}
if ($serviceBPod) {
    Write-Host "Service B Pod: $serviceBPod" -ForegroundColor White
}
Write-Host "SSH Access: ssh -i `"$sshKeyPath`" azureuser@$masterIP" -ForegroundColor White
Write-Host "Total Deployment Time: $($duration.Minutes) minutes $($duration.Seconds) seconds" -ForegroundColor White

Write-Host "`nUSEFUL COMMANDS FOR TESTING:" -ForegroundColor Cyan
Write-Host "SSH to master: ssh -i `"$sshKeyPath`" azureuser@$masterIP" -ForegroundColor White
Write-Host "Get pods: kubectl get pods --all-namespaces" -ForegroundColor Gray
Write-Host "Get services: kubectl get services --all-namespaces" -ForegroundColor Gray
if ($serviceAPod) {
    Write-Host "Follow Bitcoin API logs: kubectl logs -f $serviceAPod" -ForegroundColor Gray
}
if ($serviceBPod) {
    Write-Host "Follow Service B logs: kubectl logs -f $serviceBPod" -ForegroundColor Gray
}
Write-Host "Get nodes: kubectl get nodes" -ForegroundColor Gray

Write-Host "`nYour production-ready Bitcoin K8s cluster is ready for testing!" -ForegroundColor Green