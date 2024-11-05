param containerRegistryName string
param scopeMapName string
param scopeMapDescription string = ''
param now string = utcNow('O')

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' existing = {
  name: containerRegistryName
}

resource scopeMap 'Microsoft.ContainerRegistry/registries/scopeMaps@2023-11-01-preview' = {
  parent: containerRegistry
  name: scopeMapName
  properties: {
    description: scopeMapDescription
    actions: [
      'repositories/${scopeMapName}/content/read'
      'repositories/${scopeMapName}/*/content/read'
    ]
  }
}

// DISABLED: You cannot re-deploy this resource without wiping out the existing credentials.
// https://github.com/Azure/acr/issues/667
// https://github.com/Azure/acr/issues/596
resource token 'Microsoft.ContainerRegistry/registries/tokens@2023-11-01-preview' = if (false) {
  parent: containerRegistry
  name: scopeMapName
  properties: {
    status: 'enabled'
    scopeMapId: scopeMap.id
    credentials: {
      passwords: [
        { name: 'password1', creationTime: now }
        { name: 'password2', creationTime: now }
      ]
    }
  }
}

output scopeMapName string = scopeMap.name
output tokenName string = scopeMap.name
