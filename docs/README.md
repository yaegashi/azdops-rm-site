# dx2devops-rm-site

## Introduction

A cloud-native DevOps solution for [Redmine][redmine]/[RedMica][redmica] (RM Apps) with Azure Container Apps.

This repository provides GitOps for RM App site instance resources, including Azure Container Apps, site specific container customizations, etc.

|Repository|Description|
|-|-|
|[dx2devops-rm]|Documents|
|[dx2devops-rm-base]|RM Base GitOps: Database, Container Registry, Backups, etc.|
|[dx2devops-rm-site]|RM Site GitOps: Azure Container Apps (This repository)|
|[dx2devops-rm-docker]|RM App Container: Dockerfile, compose.yml, etc.|

[redmine]: https://github.com/redmine/redmine
[redmica]: https://github.com/redmica/redmica
[dx2devops-rm]: https://github.com/yaegashi/dx2devops-rm
[dx2devops-rm-base]: https://github.com/yaegashi/dx2devops-rm-base
[dx2devops-rm-site]: https://github.com/yaegashi/dx2devops-rm-site
[dx2devops-rm-docker]: https://github.com/yaegashi/dx2devops-rm-docker

## AZD Ops Instruction

This repository utilizes GitHub Actions and Azure Developer CLI (AZD) for the GitOps tooling (AZD Ops).
You can bootstrap an AZD Ops repository by following these steps:

1. Create a new **private** GitHub repository by importing from this repository. Forking is not recommended.
2. Copy the AZD Ops settings from `.github/azdops/main/inputs.example.yml` to `.github/azdops/main/inputs.yml` and edit it. You can do this using the GitHub Web UI.
3. Manually run the "AZD Ops Provision" workflow in the GitHub Actions Web UI. It will perform the following tasks:
    - Provision Azure resources using AZD with the `inputs.yml` settings. By default, a resource group named `{repo_name}-{branch_name}` will be created.
    - Make an AZD remote environment in the Azure Storage Account and save the AZD env variables in it.
    - Update `README.md` and `.github/azdops/main/remote.yml`, then commit and push the changes to the repository.
4. Manually run the "AZD Ops Build" workflow in the GitHub Actions Web UI. It will perform the following tasks:
    - Build a container image and push it to the container registry.
    - Deploy the container image to the container app
5. Manually run the "AZD Ops New" workflow in the GitHub Actions Web UI. It will perform the following tasks:
    - Initialize DB (rmops-dbinit)
    - Perform DB migration and initial setup (rmops-setup)
    - Restart the container app