$existingDCRG = 'rg-lab-azure-files-sync-dc'
$testEnvironmentRG = 'rg-contoso-testenvironment'
$location = 'westeurope'
$dcVMName = 'adVM'
$restoreStorageAccountName = 'sacontosorestore160721'
$testVnetName = 'vnet-contoso-isolated-test'
$dcSubnetName = 'dcSubnet'

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


function CreateDisk {
    param (
        [Parameter(Mandatory)]
        [System.String]$id,

        [Parameter(Mandatory)]
        [string]$diskName,

        [Parameter(Mandatory)]
        [string]$rg
    )

    $snapshotName = $diskName + '-snapshot'
    
    $diskSnapshotConf =  New-AzSnapshotConfig -SourceUri $id -Location $location -CreateOption copy

    $snap = Get-AzSnapshot -ResourceGroupName $rg -Name $snapshotName -ErrorVariable SnapNotPresent -ErrorAction SilentlyContinue
    if ($SnapNotPresent) {
        $diskSnapshot = New-AzSnapshot -Snapshot $diskSnapshotConf -SnapshotName ($snapshotName) -ResourceGroupName $rg 
    }
    else {
        $diskSnapshot = Update-AzSnapshot -Snapshot $diskSnapshotConf -SnapshotName ($snapshotName) -ResourceGroupName $rg
    }

    $diskConfig = New-AzDiskConfig -Location $diskSnapshot.Location -SourceResourceId $diskSnapshot.Id -CreateOption Copy
    $disk = New-AzDisk -Disk $diskConfig -ResourceGroupName $rg -DiskName $diskName

    $disk.Id
}

# Create snapshots of DC disks 
$vm = Get-Azvm -ResourceGroupName $existingDCRG -Name $dcVMName

$osDisk = CreateDisk $vm.StorageProfile.OsDisk.ManagedDisk.Id ($vm.StorageProfile.OsDisk.Name + '-test') $testEnvironmentRG

$dataDisks = @()
foreach ($disk in $vm.StorageProfile.DataDisks) {
    $dataDisks += CreateDisk $disk.ManagedDisk.Id ($disk.Name + '-test') $testEnvironmentRG
}

# Deploy test enironment (VNet, Bastion, Test DC...)
New-AzResourceGroupDeployment -Name 'TestEnvironmentDeployment' -ResourceGroupName $testEnvironmentRG -TemplateFile .\testEnvironment.bicep `
 -location  $location `
 -vnetName $testVnetName `
 -vnetIPSpace '172.168.16.0/24' `
 -adIPSpace '172.168.16.128/27' `
 -bastionIPSpace '172.168.16.160/27' `
 -appIPSpace '172.168.16.0/25' `
 -dcIP '172.168.16.132' `
 -dcName ($vm.Name + '-test') `
 -dcVmSize $vm.HardwareProfile.VmSize `
 -bastionName 'bastion-contosotestaccess' `
 -bastionPIPName 'bastion-contosotestaccess-pip' `
 -dcSubnetName $dcSubnetName `
 -appSubnetName 'appSubnet' `
 -nsgName 'nsg-test-environment' `
 -osDiskId $osDisk `
 -dataDiskIds $dataDisks

