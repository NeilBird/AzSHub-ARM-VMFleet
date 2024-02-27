﻿# Requires Az PowerShell for Azure Stack Hub
# Prerequisite steps here: https://learn.microsoft.com/azure-stack/operator/powershell-install-az-module

# Example, how to add a custom "AzEnvironment" for Azure Stack Hub and connect to the User (management) endpoint.

# //// ACTION = TO DO: Replace the <values> with the appropriate values for your Azure Stack Hub instance.
# <region> with the region name of your Azure Stack Hub instance.
# <fqdn> with the fully qualified domain name (FQDN) of your Azure Stack Hub instance.
# <tenant>.onmicrosoft.com with the Azure Active Directory (AAD) tenant name of your Azure Stack Hub instance.


# Register an Azure Resource Manager environment that targets your Azure Stack Hub instance.
# Get your Azure Resource Manager endpoint value from your service provider.
Add-AzEnvironment -Name "AzureStack" -ArmEndpoint "https://management.<region>.<fqdn>" `
  -AzureKeyVaultDnsSuffix "vault.<region>.<fqdn>" `
  -AzureKeyVaultServiceEndpointResourceId "https://vault.<region>.<fqdn>"

# Get your Tenant ID.
$AADTenantName = "<tenant>.onmicrosoft.com"
$AuthEndpoint = (Get-AzEnvironment -Name "AzureStack").ActiveDirectoryAuthority.TrimEnd('/')
$TenantId = (invoke-restmethod "$($AuthEndpoint)/$($AADTenantName)/.well-known/openid-configuration").issuer.TrimEnd('/').Split('/')[-1]

# After signing in to your environment, Azure Stack Hub cmdlets
# can be easily targeted at your Azure Stack Hub instance.
Add-AzAccount -EnvironmentName "AzureStack" -TenantId $TenantId