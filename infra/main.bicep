// targetScope = 'subscription'
targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name to prefix all resources')
param name string = 'babybuddy'

@minLength(1)
@description('Primary location for all resources')
param location string = 'eastus'

@secure()
param databasePassword string

@secure()
param nextAuthSecret string

@description('Id of the user or app to assign application roles')
param principalId string = ''

@secure()
param salt string

param useAuthentication bool = false
param authClientId string = ''
@secure()
param authClientSecret string = ''
param authTenantId string = ''

var databaseAdmin = 'dbadmin'
var databaseName = 'langfuse'
var resourceToken = toLower(uniqueString(subscription().id, name, location))

var tags = { 'azd-env-name': name }
var prefix = '${name}-${resourceToken}'

// resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
//   name: '${name}-resource-group'
//   location: location
//   tags: tags
// }

// Store secrets in a keyvault
module keyVault './core/security/keyvault.bicep' = {
  name: 'keyvault'
  // scope: resourceGroup()
  params: {
    name: '${replace(take(prefix, 17), '-', '')}-vault'
    location: location
    tags: tags
  }
}

// Give the principal access to KeyVault
module principalKeyVaultAccess './core/security/keyvault-access.bicep' = {
  name: 'keyvault-access-${principalId}'
  // scope: resourceGroup
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: principalId
  }
}

// Module for creating a PostgreSQL server
module postgresServer 'core/database/flexibleserver.bicep' = {
  name: 'postgresql'
  // scope: resourceGroup
  params: {
    name: '${prefix}-postgresql'
    location: location
    tags: tags
    sku: {
      name: 'Standard_B1ms'
      tier: 'Burstable'
    }
    storage: {
      storageSizeGB: 32
    }
    version: '16'
    administratorLogin: databaseAdmin
    administratorLoginPassword: databasePassword
    databaseNames: [ databaseName ]
    allowAzureIPsFirewall: true
  }
}

// Module for creating a Log Analytics workspace
module logAnalyticsWorkspace 'core/monitor/loganalytics.bicep' = {
  name: 'loganalytics'
  // scope: resourceGroup
  params: {
    name: '${prefix}-loganalytics'
    location: location
    tags: tags
  }
}

// Module for creating a container app environment
module containerAppEnv 'core/host/container-app-env.bicep' = {
  name: 'container-env'
  // scope: resourceGroup
  params: {
    name: containerAppName
    location: location
    tags: tags
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.outputs.name
    vnetName: 'igarashi-vnet'
    subnetName: 'igarashi-subnet-for-caenv'
  }
}

// Name of the container app
var containerAppName = '${prefix}-app'

// Module for creating a container app
module containerApp 'core/host/container-app.bicep' = {
  name: 'container'
  // scope: resourceGroup
  params: {
    name: containerAppName
    location: location
    tags: tags
    containerEnvId: containerAppEnv.outputs.id
    imageName: 'ghcr.io/langfuse/langfuse:latest'
    targetPort: 3000
    env: [
      {
        name: 'DATABASE_HOST'
        value: postgresServer.outputs.fqdn
      }
      {
        name: 'DATABASE_NAME'
        value: databaseName
      }
      {
        name: 'DATABASE_USERNAME'
        value: databaseAdmin
      }
      {
        name: 'DATABASE_PASSWORD'
        secretRef: 'databasepassword'
      }
      {
        name: 'NEXTAUTH_URL'
        value: 'https://${containerAppName}.${containerAppEnv.outputs.defaultDomain}'
      }
      {
        name: 'NEXTAUTH_SECRET'
        secretRef: 'nextauthsecret'
      }
      {
        name: 'SALT'
        secretRef: 'salt'
      }
      {
        name: 'AUTH_AZURE_AD_CLIENT_ID'
        value: authClientId
      }
      {
        name: 'AUTH_AZURE_AD_CLIENT_SECRET'
        secretRef: 'authclientsecret'
      }
      {
        name: 'AUTH_AZURE_AD_TENANT_ID'
        value: authTenantId
      }
      {
        name: 'AUTH_DISABLE_USERNAME_PASSWORD'
        value: useAuthentication ? 'true' : 'false'
      }
    ]
    secrets: {
      'databasepassword': databasePassword
      'nextauthsecret': nextAuthSecret
      'salt': salt
      'authclientsecret': authClientSecret
    }
  }
}

// Secrets to be stored in Key Vault
var secrets = [
  {
    name: 'DATABASEPASSWORD'
    value: databasePassword
  }
  {
    name: 'NEXTAUTHSECRET'
    value: nextAuthSecret
  }
  {
    name: 'SALT'
    value: salt
  }
]

// Module for creating secrets in Key Vault
module keyVaultSecrets './core/security/keyvault-secret.bicep' = [for secret in secrets: {
  name: 'keyvault-secret-${secret.name}'
  // scope: resourceGroup
  params: {
    keyVaultName: keyVault.outputs.name
    name: secret.name
    secretValue: secret.value
  }
}]

// Output the URI of the service app
output SERVICE_APP_URI string = containerApp.outputs.uri

// Output the name of the Key Vault
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
