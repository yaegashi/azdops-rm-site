# dx2devops-rm-azdapp

## Introduction

This AZD project deploys Azure Container Apps using [dx2devops-rm-azdshared](https://github.com/yaegashi/dx2devops-rm-azdshared) shared resources.

## Authentication

Authenticate with the Azure CLI, then use its auth for the Azure Developer CLI.

```
$ az login
$ azd config set auth.useAzCliAuth true
```

## Config & Deploy

You need a shared resource group deployed by dx2devops-rm-azdshared.

(Optional) Put the remote state backend configuration like the following in [azure.yaml](azure.yaml) to enable
[the remote environments](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/remote-environments-support).

```
name: dx2devops-rm-azdapp
state:
  remote:
    backend: AzureBlobStorage
    config:
      accountName: stxxxxxxxx
```

Create an environment and set configuration variables.

```
$ azd env new app1
$ azd env set SHARED_RESOURCE_GROUP_NAME rg-shared1
$ azd env set APP_ROOT_PATH /
$ azd env set DNS_ZONE_RESOURCE_GROUP_NAME rg-dns
$ azd env set DNS_ZONE_NAME rm.example.com
$ azd env set DNS_RECORD_NAME foo
$ azd env set MS_TENANT_ID xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
$ azd env set MS_CLIENT_ID yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
$ azd env set MS_CLIENT_SECRET zzzzzzzz
```

Provision resourcess (1st pass).

```
$ azd provision
```

Update Azure Container Registry token.

```
$ ./azdapp.sh acr-token
```


Build and push the app container.  This sets the APP_IMAGE env value.

```
$ ./azdapp.sh acr-build
```

Provision AZD resources (2nd pass).

```
$ azd provision
```
