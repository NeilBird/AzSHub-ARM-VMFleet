# requires Az.Accounts module
# https://learn.microsoft.com/en-us/azure-stack/operator/powershell-install-az-module

$AADTenantName = ''
$ArmEndpoint = ''

# Register an Azure Resource Manager environment that targets your Azure Stack instance
Add-AzEnvironment `
  -Name "AzureStackUser" `
  -ArmEndpoint $ArmEndpoint -Verbose

$AuthEndpoint = (Get-AzEnvironment -Name "AzureStackUser").ActiveDirectoryAuthority.TrimEnd('/')
$TenantId = (invoke-restmethod "$($AuthEndpoint)/$($AADTenantName)/.well-known/openid-configuration").issuer.TrimEnd('/').Split('/')[-1]

Disconnect-AzAccount


# Sign in to your environment
Login-AzAccount `
  -EnvironmentName "AzureStackUser" `
  -TenantId $TenantId -Verbose