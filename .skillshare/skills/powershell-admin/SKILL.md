---
name: powershell-admin
description: Production-ready PowerShell toolkit for MSPs and Windows system administrators. Covers Active Directory, Microsoft Graph API, Exchange Online, Entra ID (Azure AD), Windows Server, Hyper-V, security hardening, and multi-tenant management. Use when automating IT operations, managing Microsoft 365 tenants, administering Windows infrastructure, or building MSP tooling.
---

# PowerShell Admin Toolkit

## Core Principles

- Production-ready: Copy/paste execution with minimal modification
- No script notes or unnecessary comments in output
- Console output only - no log file creation unless requested
- M365 sessions: Never include disconnect commands (session reuse)
- Error handling: Use try/catch with actionable error messages
- Hardcoded parameters: Scripts run headless as SYSTEM when specified

## Reference Files

Load the appropriate reference based on task:

| File | Use Case |
|------|----------|
| `references/active-directory.md` | On-prem AD users, groups, computers, GPO, replication |
| `references/microsoft-graph.md` | MS Graph API for M365, Entra ID, Intune, automation |
| `references/exchange-online.md` | Mailboxes, permissions, transport rules, compliance |
| `references/entra-id.md` | Azure AD/Entra ID users, groups, licensing, conditional access |
| `references/windows-server.md` | Server roles, services, disk, events, clustering |
| `references/security-hardening.md` | BitLocker, Defender, certificates, audit policies |
| `references/remote-management.md` | WinRM, remote execution, multi-server operations |
| `references/msp-operations.md` | Multi-tenant, onboarding, reporting, RMM integration |

## Module Installation

### Microsoft Graph (Recommended for M365)
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
Install-Module Microsoft.Graph.Beta -Scope CurrentUser -Force
```

### Exchange Online
```powershell
Install-Module ExchangeOnlineManagement -Force
```

### Azure/Entra ID
```powershell
Install-Module AzureAD -Force
Install-Module Az -Force
```

### Active Directory (RSAT)
```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

## Connection Patterns

### Microsoft Graph (Delegated)
```powershell
Connect-MgGraph -Scopes "User.Read.All","Group.Read.All","Mail.Read"
```

### Microsoft Graph (App-Only)
```powershell
$ClientId = "app-client-id"
$TenantId = "tenant-id"
$Thumbprint = "cert-thumbprint"
Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

### Exchange Online
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@domain.com
```

### Exchange Online (App-Only)
```powershell
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization "tenant.onmicrosoft.com"
```

## Common Patterns

### Bulk Operations with Progress
```powershell
$Items = Get-MgUser -All
$Total = $Items.Count
$i = 0
foreach ($Item in $Items) {
    $i++
    Write-Progress -Activity "Processing" -Status "$($Item.DisplayName)" -PercentComplete (($i/$Total)*100)
    # Process item
}
Write-Progress -Activity "Processing" -Completed
```

### Error Handling
```powershell
try {
    $Result = Get-MgUser -UserId "user@domain.com" -ErrorAction Stop
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
```

### Parallel Execution (PowerShell 7+)
```powershell
$Servers | ForEach-Object -Parallel {
    Invoke-Command -ComputerName $_ -ScriptBlock { Get-Service }
} -ThrottleLimit 10
```

### CSV Import Pattern
```powershell
Import-Csv "users.csv" | ForEach-Object {
    $Params = @{
        DisplayName = $_.DisplayName
        UserPrincipalName = $_.UPN
        MailNickname = $_.Alias
    }
    New-MgUser @Params
}
```

### Export with Calculated Properties
```powershell
Get-MgUser -All | Select-Object DisplayName, UserPrincipalName, 
    @{N="LastSignIn";E={$_.SignInActivity.LastSignInDateTime}},
    @{N="Licensed";E={$_.AssignedLicenses.Count -gt 0}} |
    Export-Csv "users.csv" -NoTypeInformation
```

## MSP Multi-Tenant Pattern

### Partner Center Connection
```powershell
$Credential = Get-Credential
Connect-MgGraph -TenantId "partner-tenant-id"
$Customers = Get-MgContract -All
foreach ($Customer in $Customers) {
    Connect-MgGraph -TenantId $Customer.CustomerId
    # Perform operations
}
```

### Tenant Context Switching
```powershell
function Invoke-TenantOperation {
    param(
        [string]$TenantId,
        [scriptblock]$ScriptBlock
    )
    Connect-MgGraph -TenantId $TenantId
    & $ScriptBlock
    Disconnect-MgGraph
}
```

## Output Standards

### Console Output
```powershell
# Good - Clean table output
Get-MgUser -All | Select-Object DisplayName, UserPrincipalName | Format-Table -AutoSize

# Good - Object output for pipeline
Get-MgUser -All | Select-Object DisplayName, UserPrincipalName
```

### Status Messages
```powershell
Write-Host "Processing: $UserName" -ForegroundColor Cyan
Write-Host "Success: Created user" -ForegroundColor Green
Write-Host "Warning: License not available" -ForegroundColor Yellow
Write-Host "Error: User not found" -ForegroundColor Red
```

## Quick Reference

### User Lifecycle
```powershell
# Create user
New-MgUser -DisplayName "Name" -UserPrincipalName "user@domain.com" -MailNickname "user" -AccountEnabled -PasswordProfile @{Password="TempPass123!"}

# Disable user
Update-MgUser -UserId "user@domain.com" -AccountEnabled:$false

# Block sign-in
Update-MgUser -UserId "user@domain.com" -AccountEnabled:$false

# Convert to shared mailbox
Set-Mailbox -Identity "user@domain.com" -Type Shared

# Remove licenses
Set-MgUserLicense -UserId "user@domain.com" -RemoveLicenses @((Get-MgUserLicenseDetail -UserId "user@domain.com").SkuId) -AddLicenses @()
```

### Mailbox Operations
```powershell
# Grant full access
Add-MailboxPermission -Identity "shared@domain.com" -User "user@domain.com" -AccessRights FullAccess

# Grant send-as
Add-RecipientPermission -Identity "shared@domain.com" -Trustee "user@domain.com" -AccessRights SendAs

# Set forwarding
Set-Mailbox -Identity "user@domain.com" -ForwardingSmtpAddress "forward@domain.com" -DeliverToMailboxAndForward $true

# Get mailbox size
Get-MailboxStatistics "user@domain.com" | Select-Object DisplayName, TotalItemSize, ItemCount
```

### Group Management
```powershell
# Create M365 group
New-MgGroup -DisplayName "Group Name" -MailEnabled -MailNickname "groupname" -SecurityEnabled -GroupTypes "Unified"

# Add member
New-MgGroupMember -GroupId $GroupId -DirectoryObjectId $UserId

# Get members
Get-MgGroupMember -GroupId $GroupId | ForEach-Object { Get-MgUser -UserId $_.Id }
```

## Notes

- PowerShell 7+ recommended for parallel operations and improved Graph cmdlets
- Always test in non-production tenant first
- Store credentials securely (Azure Key Vault, Windows Credential Manager)
- Use app-only authentication for unattended scripts
- Graph API permissions require admin consent for most operations
