metadata title = 'Virtual Machine Azure Disk Encryption options'
metadata description = 'Virtual Machine Azure Disk Encryption (ADE) and Server Side Encryption (SSE) with Customer Managed Key (CMK)'

targetScope = 'subscription'

// Required parameters
@description('Required. Location for all resources.')
param location string = '<location>'
@description('Required. Existing Subnet ID for the VMs')
param subnetId string = '<subnetResourceId>'

// Optional parameters
@description('Optional. Admin password for the VMs')
@secure()
param adminPassword string = newGuid()
@description('Optional. Name for the Azure Disk Encryption Resources')
param adeName string = 'vmAde'
@description('Optional. Name for the Server Side Encryption Resources')
param sseName string = 'vmSse'
@description('Optional. Name for the Keyvault Key')
param keyName string = 'encryptKey'

// Azure Disk encryption with CMK

@description('VM deployment resource group existing')
resource resourceGroupAde 'Microsoft.Resources/resourceGroups@2021-01-01' = {
  name: 'rg-${adeName}'
  location: location
}

@description('Shared Keyvault for the VM Azure Disk Encryption')
module keyvaultAde 'br/public:avm/res/key-vault/vault:0.11.2' = {
  name: 'keyvaultAde-deploy'
  scope: resourceGroupAde
  params: {
    name: 'kv-${adeName}'
    sku: 'standard'
    enablePurgeProtection: false
    enableSoftDelete: false
    keys: [
      {
        // Key name if CMK required PMK not required
        name: keyName
        kty: 'RSA'
      }
    ] 
  }
}

@description('Virtual Machine with Azure Disk Encryption')
module virtualMachineAde 'br/public:avm/res/compute/virtual-machine:0.11.1' = {
  name: 'virtualMachineAde-Deploy'
  scope: resourceGroupAde
  params: {
    // Required parameters
    adminUsername: 'winadmin'
    imageReference: {
      offer: 'WindowsServer'
      publisher: 'MicrosoftWindowsServer'
      sku: '2019-datacenter'
      version: 'latest'
    }
    name: adeName
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'ipconfig01'
            subnetResourceId: subnetId
          }
        ]
        nicSuffix: '-nic-01'
      }
    ]
    osDisk: {
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    osType: 'Windows'
    vmSize: 'Standard_D2s_v3'
    zone: 0
    // Non-required parameters
    adminPassword: adminPassword
    dataDisks: [
      {
        diskSizeGB: 128
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    ]
    // Encryption at host is not supported for VMs with ADE
    encryptionAtHost: false
    // Azure Disk Encryption configuration
    extensionAzureDiskEncryptionConfig: {
      enabled: true
      settings: {
        EncryptionOperation: 'EnableEncryption'
        KeyEncryptionAlgorithm: 'RSA-OAEP'
        ResizeOSDisk: 'false'
        VolumeType: 'All'
        KekVaultResourceId: keyvaultAde.outputs.resourceId
        KeyVaultResourceId: keyvaultAde.outputs.resourceId
        KeyVaultURL: keyvaultAde.outputs.uri
        // Optional. ADE with CMK requires the key URL, comment out for PMK
        KeyEncryptionKeyURL: keyvaultAde.outputs.keys[0].uriWithVersion
      }
    }
  }
}

// SSE Disk Encryption Set with CMK

@description('VM deployment resource group for SSE with CMK')
resource resourceGroupDes 'Microsoft.Resources/resourceGroups@2021-01-01' = {
  name: 'rg-${sseName}'
  location: location
}

@description('User Assigned Identity for Disk Encryption Set')
module userAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  scope: resourceGroupDes
  name: 'userAssignedIdentity-Deploy'
  params: {
    name: 'uami-${sseName}'
  }
}

@description('Shared Keyvault for the VM encryption purposes')
module keyvaultDes 'br/public:avm/res/key-vault/vault:0.11.2' = {
  name: 'keyvault-deploy'
  scope: resourceGroupDes
  params: {
    name: 'kv-${sseName}'
    location: location
    sku: 'standard'
    // Both the following values must be true for SSE with CMK
    enablePurgeProtection: true
    enableSoftDelete: true
    keys: [
      {
        // Key name if CMK required PMK not required
        name: keyName
        kty: 'RSA'
      }
    ]
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Key Vault Crypto Service Encryption User'
        principalId: userAssignedIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

@description('Disk Encryption Set with Customer Managed Key')
module diskEncryptionSet 'br/public:avm/res/compute/disk-encryption-set:0.3.2' = {
  scope: resourceGroupDes
  name: 'diskEncryptionSet-Deploy'
  params: {
    // For SSE with CMK keyVaultResourceId and keyName are required
    name: 'des-${sseName}'
    keyName: keyName
    keyVaultResourceId: keyvaultDes.outputs.resourceId
    encryptionType: 'EncryptionAtRestWithCustomerKey'
    managedIdentities: {
      userAssignedResourceIds: [
        userAssignedIdentity.outputs.resourceId
      ]
    }
  }
}


@description('Virtual Machine with SSE with CMK and Encryption At Host')
module virtualMachineEahCmk 'br/public:avm/res/compute/virtual-machine:0.11.1' = {
  name: 'virtualMachineDeployment'
  scope: resourceGroupDes
  params: {
    // Required parameters
    adminUsername: 'winadmin'
    imageReference: {
      offer: 'WindowsServer'
      publisher: 'MicrosoftWindowsServer'
      sku: '2019-datacenter'
      version: 'latest'
    }
    name: sseName
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'ipconfig01'
            subnetResourceId: subnetId
          }
        ]
        nicSuffix: '-nic-01'
      }
    ]
    // Encryption at host is supported for VMs with SSE with CMK or PMK
    encryptionAtHost: true
    osDisk: {
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Premium_LRS'
        // Disk Encryption Set with CMK, comment out for PMK
        diskEncryptionSetResourceId: diskEncryptionSet.outputs.resourceId
      }
    }
    osType: 'Windows'
    vmSize: 'Standard_D2s_v3'
    zone: 0
    // Non-required parameters
    adminPassword: adminPassword
    dataDisks: [
      {
        diskSizeGB: 128
        managedDisk: {
          storageAccountType: 'Premium_LRS'
          // Disk Encryption Set with CMK, comment out for PMK
          diskEncryptionSetResourceId: diskEncryptionSet.outputs.resourceId
        }
      }
    ]
  }
}
