$testEnvironmentRG = 'rg-contoso-testenvironment'
$location = 'westeurope'
$backupVaultName = 'rsv-azfiles-1'
$backupVaultRG = 'rg-lab-azure-files-sync-dc'
$dcVMName = 'adVM'
$restoreStorageAccountName = 'sacontosorestore120721'
$testVnetName = 'vnet-contoso-isolated-test'
$dcSubnetName = 'dcSubnet'
$avSetName = 'avSetDCTest'

# Create required resources
Get-AzResourceGroup -Name $testEnvironmentRG -ErrorVariable RGNotPresent -ErrorAction SilentlyContinue

# Create RG if not exists
if ($RGNotPresent)
{
    New-AzResourceGroup -Name $testEnvironmentRG -Location $location
}

# Create recovery stirage account if not exists
Get-AzStorageAccount -Name $restoreStorageAccountName -ResourceGroupName $testEnvironmentRG -ErrorVariable SANotPresent -ErrorAction SilentlyContinue 

if ($SANotPresent)
{
    New-AzStorageAccount -Name $restoreStorageAccountName -Location $location -ResourceGroupName $testEnvironmentRG -SkuName Standard_LRS -Kind StorageV2 
}


# Retrieve and restore latest DC backup to get managed disks
$targetVault = Get-AzRecoveryServicesVault -ResourceGroupName $backupVaultRG -Name $backupVaultName

$namedContainer = Get-AzRecoveryServicesBackupContainer  -ContainerType "AzureVM" -Status "Registered" -FriendlyName $dcVMName -VaultId $targetVault.ID
$backupitem = Get-AzRecoveryServicesBackupItem -Container $namedContainer  -WorkloadType "AzureVM" -VaultId $targetVault.ID

$startDate = (Get-Date).AddDays(-29)
$endDate = Get-Date

$rp = Get-AzRecoveryServicesBackupRecoveryPoint -Item $backupitem -StartDate $startdate.ToUniversalTime() -EndDate $enddate.ToUniversalTime() -VaultId $targetVault.ID

$targetVault | Set-AzRecoveryServicesVaultContext
$restorejob = Restore-AzRecoveryServicesBackupItem -RecoveryPoint $rp[0] -StorageAccountName $restoreStorageAccountName -StorageAccountResourceGroupName $testEnvironmentRG -VaultId $targetVault.ID -TargetResourceGroupName $testEnvironmentRG


# Deploy test enironment (VNet, Bastion...)
New-AzResourceGroupDeployment -Name 'TestEnvironmentDeployment' -ResourceGroupName $testEnvironmentRG -TemplateFile .\testEnvironment.bicep `
 -location  $location `
 -vnetName $testVnetName `
 -vnetIPSpace '172.168.16.0/24' `
 -adIPSpace '172.168.16.128/27' `
 -bastionIPSpace '172.168.16.160/27' `
 -appIPSpace '172.168.16.0/25' `
 -dcIP '172.168.16.132' `
 -bastionName 'bastion-contosotestaccess' `
 -bastionPIPName 'bastion-contosotestaccess-pip' `
 -dcSubnetName $dcSubnetName `
 -appSubnetName 'appSubnet' `
 -nsgName 'nsg-test-environment' `
 -avSet $avSetName



# Retrieve ARM template for VM deployment from restore job
$details = Get-AzRecoveryServicesBackupJobDetail -JobId $restorejob.JobId
$properties = $details.properties
$storageAccountName = $properties["Target Storage Account Name"]
$containerName = $properties["Config Blob Container Name"]
$templateBlobURI = $properties["Template Blob Uri"]
$templateName = $templateBlobURI.Substring($templateBlobURI.LastIndexOf('/')+1)

Set-AzCurrentStorageAccount -Name $storageAccountName -ResourceGroupName $testEnvironmentRG
$templateBlobFullURI = New-AzStorageBlobSASToken -Container $containerName -Blob $templateName  -Permission r -FullUri

# Deploy DC VM
New-AzResourceGroupDeployment `
    -Name 'TestDCDeployment' `
    -ResourceGroupName $testEnvironmentRG `
    -TemplateUri $templateBlobFullURI `
    -VirtualMachineName ($dcVMName + '-test') `
    -VirtualNetwork $testVnetName `
    -VirtualNetworkResourceGroup $testEnvironmentRG `
    -Subnet $dcSubnetName `
    -AvailabilitySetName $avSetName
