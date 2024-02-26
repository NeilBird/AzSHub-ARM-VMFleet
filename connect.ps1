# Requires Az PowerShell for Azure Stack Hub
# Prerequisite steps here: https://learn.microsoft.com/en-us/azure-stack/operator/powershell-install-az-module
# This script connects to an Azure Stack Hub instance using the Azure Resource Manager model.
# Replace the following placeholder values with the appropriate values for your Azure Stack Hub instance:
# <region> with the region name of your Azure Stack Hub instance.
# <fqdn> with the fully qualified domain name (FQDN) of your Azure Stack Hub instance.
# <tenant.onmicrosoft.com> with the Azure Active Directory (AAD) tenant name of your Azure Stack Hub instance.


# Register an Azure Resource Manager environment that targets your Azure Stack Hub instance.
# Get your Azure Resource Manager endpoint value from your service provider.
Add-AzEnvironment -Name "AzureStack" -ArmEndpoint "https://management.<region>.<fqdn>" `
  -AzureKeyVaultDnsSuffix "adminvault.<region>.<fqdn>" `
  -AzureKeyVaultServiceEndpointResourceId "https://adminvault.<region>.<fqdn>"

# Set your tenant name.
$AuthEndpoint = (Get-AzEnvironment -Name "AzureStack").ActiveDirectoryAuthority.TrimEnd('/')
$AADTenantName = "tenant.onmicrosoft.com"
$TenantId = (invoke-restmethod "$($AuthEndpoint)/$($AADTenantName)/.well-known/openid-configuration").issuer.TrimEnd('/').Split('/')[-1]

# After signing in to your environment, Azure Stack Hub cmdlets
# can be easily targeted at your Azure Stack Hub instance.
Connect-AzAccount -EnvironmentName "AzureStack" -TenantId $TenantId -DeviceCode