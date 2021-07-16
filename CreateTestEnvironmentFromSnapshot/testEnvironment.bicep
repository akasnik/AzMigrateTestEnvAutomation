param location string  = resourceGroup().location
param vnetName string = 'vnet-contoso-isolated-test'
param vnetIPSpace string = '172.168.16.0/24'
param adIPSpace string = '172.168.16.128/27'
param bastionIPSpace string = '172.168.16.160/27'
param appIPSpace string = '172.168.16.0/25'
param dcIP string = '172.168.16.132'
param dcName string = 'vmdc-test'
param dcVmSize string = 'Standard_D2ds_v4'
param bastionName string = 'bastion-contosotestaccess'
param bastionPIPName string = '${bastionName}-pip'
param dcSubnetName string = 'dcSubnet'
param appSubnetName string = 'appSubnet'
param nsgName string = 'nsg-test-environment'
//param avSetName string = 'avSetDCTest'
param osDiskId string
param dataDiskIds array

var bastionSubnetName = 'AzureBastionSubnet'
var dcNicName = '${dcName}-nic'
var dataDisksConfig = [for (dataDisk, i) in dataDiskIds: {
  lun: i
  caching: 'ReadOnly'
  createOption: 'Attach'
  //name: substring(dataDisk, (lastIndexOf(dataDisk, '/') + 1))
  vhd: null
  managedDisk: {
    id: dataDisk
  } 
}] 



resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  location: location
  name: vnetName
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetIPSpace
      ]
    }
    dhcpOptions: {
      dnsServers: [
        dcIP
      ]
    }
    subnets: [
      {
        name: appSubnetName
        properties: {
          addressPrefix: appIPSpace
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: dcSubnetName
        properties: {
          addressPrefix: adIPSpace
          networkSecurityGroup: {
            id: nsg.id
          }
        }             
      }
      {
        name: bastionSubnetName
        properties: {
          addressPrefix: bastionIPSpace
        }
      }
    ]
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2021-02-01' = {
  location: location
  name: bastionName
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfigBastion'
        properties: {
          subnet: {            
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, bastionSubnetName)
          }
          publicIPAddress: {
            id: bastionPIP.id
          }
        }
      }
    ]
  }
}

resource bastionPIP 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  location: location
  name: bastionPIPName
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Network Security Group
var networkSecurityGroup = {
  securityRules: [
    /*{
      name: 'default-allow-3389'
      properties: {
        priority: 1000
        access: 'Allow'
        direction: 'Inbound'
        protocol: 'TCP'
        sourcePortRange: '*'
        sourceAddressPrefix: '*'
        destinationAddressPrefix: '*'
        destinationPortRange: 3389
      }
    }*/
  ]
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2020-06-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: networkSecurityGroup.securityRules
  }
}

// resource avSet 'Microsoft.Compute/availabilitySets@2021-03-01' = {
//   name: avSetName
//   location: location
//   sku: {
//     name: 'Aligned'
//   }
//   properties: {
//     platformFaultDomainCount: 3
//   }
// }

resource dcnic 'Microsoft.Network/networkInterfaces@2021-02-01' = {
  location: location
  name: dcNicName
  properties: {
    ipConfigurations:[
      {
        name: 'ipConfig1'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, dcSubnetName)
          }
          privateIPAddress: dcIP
          privateIPAllocationMethod: 'Static'
        }
      }
    ]
  }
}

resource vmdc 'Microsoft.Compute/virtualMachines@2021-03-01' = {
  location: location
  name: dcName
  properties: {
    hardwareProfile: {
      vmSize: dcVmSize
    }
    storageProfile: {
      osDisk: {
        createOption: 'Attach'
        osType: 'Windows'
        caching: 'ReadOnly'
        vhd: null
        //name: substring(osDiskId, (lastIndexOf(osDiskId, '/') + 1))
        managedDisk: {
          id: osDiskId
        }        
      }
      dataDisks: dataDisksConfig
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: dcnic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}
