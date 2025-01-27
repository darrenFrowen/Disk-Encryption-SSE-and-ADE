# Azure Disk Encryption and Server-Side Encryption with Encryption at Host

This document provides an overview of two encryption options for Azure Virtual Machines: Azure Disk Encryption (ADE) and Server-Side Encryption (SSE) with encryption at host. It also includes the specific code for each option.

## Azure Disk Encryption (ADE)

Azure Disk Encryption helps protect and safeguard your data to meet your organizational security and compliance commitments. ADE encrypts the OS and data disks of Azure virtual machines (VMs) inside your VMs by using the DM-Crypt feature of Linux or the BitLocker feature of Windows. ADE is integrated with Azure Key Vault to help you control and manage the disk encryption keys and secrets.

### Paramters used

```bicep
@description('Required. Location for all resources.')
param location string = '<location>'
@description('Required. Existing Subnet ID for the VMs')
param subnetId string = '<subnetResourceId>'
@description('Optional. Admin password for the VMs')
@secure()
param adminPassword string = newGuid()
@description('Optional. Name for the Azure Disk Encryption Resources')
param adeName string = 'vmAde'
@description('Optional. Name for the Server Side Encryption Resources')
param sseName string = 'vmSse'
@description('Optional. Name for the Keyvault Key')
param keyName string = 'encryptKey'
```

### Code Example

```bicep
targetScope = 'subscription'

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
```

### Deployment specifics

- **Key Vault**: `enablePurgeProtection` and `enableSoftDelete` can be set to `false` for ADE.
- **Virtual Machine**: `encryptionAtHost` is set to `false` and is not compatible for ADE.
- **Azure Disk Encryption Configuration**: The `extensionAzureDiskEncryptionConfig` property is used to configure ADE, the code block below describes the required configuration.

```bicep
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
```

## Server-Side Encryption (SSE) with Encryption at Host

Server-Side Encryption (SSE) with encryption at host ensures that all temp disks and disk caches are encrypted at rest and flow encrypted to the Storage clusters. This option enhances Azure Disk Storage Server-Side Encryption to provide end-to-end encryption for your VM data.

### Code Example

```bicep
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

```

### Deployment Specifics

- **Managed Identity**: Required for the Disk encryption set to access the keyvault key. 
- **Key Vault**: `enablePurgeProtection` and `enableSoftDelete` are set to `true` for SSE with CMK, whereas they can be set to `false` for ADE.
- **Virtual Machine**:
  - **Encryption at Host**: `encryptionAtHost` is set to `true` for SSE with CMK, while it is set to `false` for ADE.
  - **Disk Encryption Configuration**: For ADE, the `extensionAzureDiskEncryptionConfig` property is used to configure ADE, whereas for SSE with CMK, the `diskEncryptionSetResourceId` property is used to reference the Disk Encryption Set. The required configuration can be seen below code block.

```bicep
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
```

## Summary

- **Azure Disk Encryption (ADE)**: Encrypts the OS and data disks of Azure VMs using DM-Crypt (Linux) or BitLocker (Windows). Integrated with Azure Key Vault for key management.
- **Server-Side Encryption (SSE) with Encryption at Host**: Ensures all temp disks and disk caches are encrypted at rest and flow encrypted to the Storage clusters. Enhances Azure Disk Storage SSE to provide end-to-end encryption for your VM data.