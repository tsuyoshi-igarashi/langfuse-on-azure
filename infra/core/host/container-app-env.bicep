
param name string                                   // Name of the container app environment
param location string = resourceGroup().location    // Location of the resource group
param tags object = {}                              // Tags to be assigned to the container app environment

param logAnalyticsWorkspaceName string              // Name of the existing Log Analytics workspace
param vnetName string                               // Name of the existing VNet
param subnetName string                             // Name of the subnet in the VNet

// Reference to the existing Log Analytics workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logAnalyticsWorkspaceName
}

// Reference to the existing VNet
resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' existing = {
  name: vnetName
}

// Reference to the existing subnet in the VNet
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  parent: vnet
  name: subnetName
}

// Definition of the container app environment
resource containerEnv 'Microsoft.App/managedEnvironments@2022-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    // Configuration for sending app logs to Log Analytics
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        // Use the customer ID and shared key of the Log Analytics workspace
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    // The container app environment is not zone redundant
    zoneRedundant: false
    // Add the VNet configuration
    vnetConfiguration: {
      // vnetId: vnet.id
      // subnetId: subnet.id
      infrastructureSubnetId: subnet.id
    }
  }
}

// Output the ID of the container app environment
output id string = containerEnv.id

// Output the default domain of the container app environment
output defaultDomain string = containerEnv.properties.defaultDomain
