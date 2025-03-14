param containerAppsEnvironmentName string
param containerAppName string
param dnsDomainName string
param location string = resourceGroup().location
param tags object = {}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-08-01-preview' existing = {
  name: containerAppsEnvironmentName
}

resource containerApp 'Microsoft.App/containerApps@2023-08-01-preview' = {
  name: containerAppName
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        customDomains: [
          {
            name: dnsDomainName
            certificateId: null
            bindingType: 'Disabled'
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: 'quickstart'
          image: 'mcr.microsoft.com/k8se/quickstart:latest'
        }
      ]
    }
  }
}

output fqdn string = containerApp.properties.configuration.ingress.fqdn
