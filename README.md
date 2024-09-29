# dx2devops-rm-azdapp

## Deploy

```
$ azd env new app1
$ azd env set SHARED_RESOURCE_GROUP_NAME rg-shared1
$ azd env set DNS_ZONE_RESOURCE_GROUP_NAME rg-dns
$ azd env set DNS_ZONE_NAME rm.banadev.org
$ azd env set DNS_RECORD_NAME foo
$ azd provision
```
