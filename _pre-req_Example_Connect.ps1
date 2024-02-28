# Requires Az PowerShell for Azure Stack Hub
# Prerequisite steps here for both connected and disonnected installations:
# https://learn.microsoft.com/azure-stack/operator/powershell-install-az-module

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

# Example for either ADFS Identity Provider stamps, or if your are using Entra ID and your user account's "home tenant":
# After signing in to your environment, Azure Stack Hub cmdlets
# // does not require the TenantId parameter
Add-AzAccount -EnvironmentName "AzureStack"

# Example when your user account is a Guest Account in another Entra ID tenant:
# Requires Tenant ID, if you are using a Guest Account in another tenant:
$AADTenantName = "<tenant>.onmicrosoft.com"
$AuthEndpoint = (Get-AzEnvironment -Name "AzureStack").ActiveDirectoryAuthority.TrimEnd('/')
$TenantId = (invoke-restmethod "$($AuthEndpoint)/$($AADTenantName)/.well-known/openid-configuration").issuer.TrimEnd('/').Split('/')[-1]

# After signing in to your environment, Azure Stack Hub cmdlets
Add-AzAccount -EnvironmentName "AzureStack" -TenantId $TenantId

