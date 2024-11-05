targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

param principalId string

param userAssignedIdentityName string = ''

param resourceGroupName string = ''

param keyVaultName string = ''

param storageAccountName string = ''

param logAnalyticsName string = ''

param applicationInsightsName string = ''

param applicationInsightsDashboardName string = ''

param containerAppName string = ''

param containerAppsEnvironmentName string = ''

param appImage string = ''
@secure()
param appCrPass string
@secure()
param appDbPass string
@secure()
param appSecretKeyBase string

param appRootPath string = '/'

param appCertificateExists bool = false

param tz string = 'Asia/Tokyo'

param sharedResourceGroupName string

param dnsZoneResourceGroupName string = ''

param dnsZoneName string = ''

param dnsRecordName string = ''

param msTenantId string
param msClientId string
@secure()
param msClientSecret string

var abbrs = loadJsonContent('./abbreviations.json')

var tags = {
  'azd-env-name': environmentName
}

#disable-next-line no-unused-vars
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

resource sharedRG 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: sharedResourceGroupName
}

resource sharedKeyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  scope: sharedRG
  name: sharedRG.tags.KEY_VAULT_NAME
}

module registryToken './app/registry-token.bicep' = {
  scope: sharedRG
  name: 'registryScope'
  params: {
    containerRegistryName: sharedRG.tags.CONTAINER_REGISTRY_NAME
    scopeMapName: xContainerAppName
    scopeMapDescription: '${environmentName}/${xContainerAppName}'
  }
}

var dnsEnable = !empty(dnsZoneResourceGroupName) && !empty(dnsZoneName) && !empty(dnsRecordName)
var appCustomDomainName = dnsEnable ? '${dnsRecordName}.${dnsZoneName}' : ''

resource dnsZoneRG 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (dnsEnable && !appCertificateExists) {
  name: dnsZoneResourceGroupName
}

module dnsTXT './app/dns-txt.bicep' = if (dnsEnable && !appCertificateExists) {
  name: 'dnsTXT'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    dnsRecordName: 'asuid.${dnsRecordName}'
    txt: env.outputs.customDomainVerificationId
  }
}

module dnsCNAME './app/dns-cname.bicep' = if (dnsEnable && !appCertificateExists) {
  name: 'dnsCNAME'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    dnsRecordName: dnsRecordName
    cname: appPrep.outputs.fqdn
  }
}

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module keyVault './core/security/keyvault.bicep' = {
  name: 'keyVault'
  scope: rg
  params: {
    name: !empty(keyVaultName) ? keyVaultName : '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
  }
}

module keyVaultAccessDeployment './core/security/keyvault-access.bicep' = {
  name: 'keyVaultAccessDeployment'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: principalId
    permissions: { secrets: ['list', 'get', 'set'] }
  }
}

module keyVaultSecretContainerRegistry './core/security/keyvault-secret.bicep' = {
  name: 'keyVaultSecretAppCrPass'
  scope: rg
  params: {
    name: 'APP-CR-PASS'
    tags: tags
    keyVaultName: keyVault.outputs.name
    secretValue: appCrPass
  }
}

module keyVaultSecretAppDbPass './core/security/keyvault-secret.bicep' = {
  name: 'keyVaultSecretAppDbPass'
  scope: rg
  params: {
    name: 'APP-DB-PASS'
    tags: tags
    keyVaultName: keyVault.outputs.name
    secretValue: appDbPass
  }
}

module keyVaultSecretAppSecretKeyBase './core/security/keyvault-secret.bicep' = {
  name: 'keyVaultSecretAppSecretKeyBase'
  scope: rg
  params: {
    name: 'SECRET-KEY-BASE'
    tags: tags
    keyVaultName: keyVault.outputs.name
    secretValue: appSecretKeyBase
  }
}

module keyVaultSecretMsClientSecret './core/security/keyvault-secret.bicep' = {
  name: 'keyVaultSecretMsClientSecret'
  scope: rg
  params: {
    name: 'MS-CLIENT-SECRET'
    tags: tags
    keyVaultName: keyVault.outputs.name
    secretValue: sharedKeyVault.getSecret('MS-CLIENT-SECRET')
  }
}

var xTZ = !empty(tz) ? tz : 'Asia/Tokyo'
var xContainerAppsEnvironmentName = !empty(containerAppsEnvironmentName)
  ? containerAppsEnvironmentName
  : '${abbrs.appManagedEnvironments}${resourceToken}'
var xContainerAppName = !empty(containerAppName) ? containerAppName : '${abbrs.appContainerApps}${resourceToken}'
var appCrUser = xContainerAppName
var appDbName = replace(xContainerAppName, '-', '_')
var appDbUrl = format(sharedRG.tags.DB_URL_FORMAT, appDbName, appDbPass, appDbName)

module keyVaultSecretDatabaseUrl './core/security/keyvault-secret.bicep' = {
  name: 'keyVaultSecretDatabaseUrl'
  scope: rg
  params: {
    name: 'DATABASE-URL'
    tags: tags
    keyVaultName: keyVault.outputs.name
    secretValue: appDbUrl
  }
}

module userAssignedIdentity './app/identity.bicep' = {
  name: 'userAssignedIdentity'
  scope: rg
  params: {
    name: !empty(userAssignedIdentityName)
      ? userAssignedIdentityName
      : '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
    location: location
    tags: tags
  }
}

module KeyVaultAccessUserAssignedIdentity './core/security/keyvault-access.bicep' = {
  name: 'KeyVaultAccessUserAssignedIdentity'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: userAssignedIdentity.outputs.principalId
  }
}

module storageAccount './core/storage/storage-account.bicep' = {
  name: 'storageAccount'
  scope: rg
  params: {
    location: location
    tags: tags
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
  }
}

module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName)
      ? logAnalyticsName
      : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName)
      ? applicationInsightsName
      : '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: !empty(applicationInsightsDashboardName)
      ? applicationInsightsDashboardName
      : '${abbrs.portalDashboards}${resourceToken}'
  }
}

module env './app/env.bicep' = {
  name: 'env'
  scope: rg
  params: {
    location: location
    tags: tags
    containerAppsEnvironmentName: xContainerAppsEnvironmentName
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
    storageAccountName: storageAccount.outputs.name
  }
}

module appPrep './app/app-prep.bicep' = if (dnsEnable && !appCertificateExists) {
  dependsOn: [dnsTXT]
  name: 'appPrep'
  scope: rg
  params: {
    location: location
    tags: tags
    containerAppsEnvironmentName: env.outputs.name
    containerAppName: xContainerAppName
    appCustomDomainName: appCustomDomainName
  }
}

module app './app/app.bicep' = {
  dependsOn: [KeyVaultAccessUserAssignedIdentity, dnsCNAME]
  name: 'app'
  scope: rg
  params: {
    location: location
    tags: tags
    containerAppsEnvironmentName: env.outputs.name
    containerAppName: xContainerAppName
    storageAccountName: storageAccount.outputs.name
    containerRegistryEndpoint: sharedRG.tags.CONTAINER_REGISTRY_ENDPOINT
    containerRegistryUsername: appCrUser
    containerRegistryPasswordKV: '${keyVault.outputs.endpoint}secrets/APP-CR-PASS'
    userAssignedIdentityName: userAssignedIdentity.outputs.name
    appImage: appImage
    appRootPath: appRootPath
    appCustomDomainName: appCustomDomainName
    databaseUrlKV: '${keyVault.outputs.endpoint}secrets/DATABASE-URL'
    secretKeyBaseKV: '${keyVault.outputs.endpoint}secrets/SECRET-KEY-BASE'
    msTenantId: msTenantId
    msClientId: msClientId
    msClientSecret: msClientSecret
    tz: xTZ
  }
}

module job './app/job.bicep' = {
  dependsOn: [KeyVaultAccessUserAssignedIdentity]
  name: 'job'
  scope: rg
  params: {
    location: location
    tags: tags
    containerAppsEnvironmentName: env.outputs.name
    containerAppName: xContainerAppName
    containerRegistryEndpoint: sharedRG.tags.CONTAINER_REGISTRY_ENDPOINT
    containerRegistryUsername: appCrUser
    containerRegistryPasswordKV: '${keyVault.outputs.endpoint}secrets/APP-CR-PASS'
    userAssignedIdentityName: userAssignedIdentity.outputs.name
    appImage: appImage
    databaseUrlKV: '${keyVault.outputs.endpoint}secrets/DATABASE-URL'
    tz: xTZ
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP_NAME string = rg.name
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
output AZURE_CONTAINER_APPS_APP_NAME string = app.outputs.name
output AZURE_CONTAINER_APPS_JOB_NAME string = job.outputs.name
output AZURE_STORAGE_ACCOUNT_NAME string = storageAccount.outputs.name
output AZURE_LOG_ANALYTICS_WORKSPACE_CUSTOMER_ID string = monitoring.outputs.logAnalyticsWorkspaceCustomerId
output APP_CERTIFICATE_EXISTS bool = !empty(appCustomDomainName)
output SHARED_CONTAINER_REGISTRY_NAME string = sharedRG.tags.CONTAINER_REGISTRY_NAME
output SHARED_CONTAINER_REGISTRY_ENDPOINT string = sharedRG.tags.CONTAINER_REGISTRY_ENDPOINT
output SHARED_CONTAINER_REGISTRY_SCOPE_MAP_NAME string = registryToken.outputs.scopeMapName
output SHARED_CONTAINER_REGISTRY_TOKEN_NAME string = registryToken.outputs.tokenName
