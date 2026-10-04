# Admin Operations

## Multi-Tenant Management

### Partner Center Connection
```powershell
Connect-MgGraph -TenantId "partner-tenant-id" -Scopes "Organization.Read.All"
$Customers = Get-MgContract -All
$Customers | Select-Object DisplayName, CustomerId, DefaultDomainName
```

### Iterate Through Tenants
```powershell
$Customers = Get-MgContract -All
foreach ($Customer in $Customers) {
    Write-Host "Processing: $($Customer.DisplayName)" -ForegroundColor Cyan
    Connect-MgGraph -TenantId $Customer.CustomerId
    # Perform operations
    $Users = Get-MgUser -All
    Write-Host "  Users: $($Users.Count)"
}
```

### Multi-Tenant User Report
```powershell
$Customers = Get-MgContract -All
$Report = foreach ($Customer in $Customers) {
    Connect-MgGraph -TenantId $Customer.CustomerId -ErrorAction SilentlyContinue
    $Users = Get-MgUser -All -Property DisplayName,UserPrincipalName,AccountEnabled,AssignedLicenses
    foreach ($User in $Users) {
        [PSCustomObject]@{
            Tenant = $Customer.DisplayName
            DisplayName = $User.DisplayName
            UPN = $User.UserPrincipalName
            Enabled = $User.AccountEnabled
            Licensed = $User.AssignedLicenses.Count -gt 0
        }
    }
}
$Report | Export-Csv "multi-tenant-users.csv" -NoTypeInformation
```

### Multi-Tenant License Summary
```powershell
$Customers = Get-MgContract -All
$LicenseReport = foreach ($Customer in $Customers) {
    Connect-MgGraph -TenantId $Customer.CustomerId -ErrorAction SilentlyContinue
    $Skus = Get-MgSubscribedSku
    foreach ($Sku in $Skus) {
        [PSCustomObject]@{
            Tenant = $Customer.DisplayName
            License = $Sku.SkuPartNumber
            Total = $Sku.PrepaidUnits.Enabled
            Consumed = $Sku.ConsumedUnits
            Available = $Sku.PrepaidUnits.Enabled - $Sku.ConsumedUnits
        }
    }
}
$LicenseReport | Export-Csv "multi-tenant-licenses.csv" -NoTypeInformation
```

## Client Onboarding

### New User Provisioning
```powershell
param(
    [string]$DisplayName,
    [string]$FirstName,
    [string]$LastName,
    [string]$Department,
    [string]$Title,
    [string]$Manager,
    [string]$LicenseSku = "ENTERPRISEPACK"
)

$MailNickname = ($FirstName.Substring(0,1) + $LastName).ToLower()
$UPN = "$MailNickname@domain.com"
$TempPassword = [System.Web.Security.Membership]::GeneratePassword(16, 4)

# Create user
$PasswordProfile = @{
    Password = $TempPassword
    ForceChangePasswordNextSignIn = $true
}

$NewUser = New-MgUser -DisplayName $DisplayName -GivenName $FirstName -Surname $LastName -UserPrincipalName $UPN -MailNickname $MailNickname -Department $Department -JobTitle $Title -AccountEnabled -PasswordProfile $PasswordProfile

# Assign license
$License = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq $LicenseSku }
Set-MgUserLicense -UserId $NewUser.Id -AddLicenses @{SkuId = $License.SkuId} -RemoveLicenses @()

# Set manager
if ($Manager) {
    $ManagerUser = Get-MgUser -UserId $Manager
    Set-MgUserManagerByRef -UserId $NewUser.Id -BodyParameter @{"@odata.id" = "https://graph.microsoft.com/v1.0/users/$($ManagerUser.Id)"}
}

[PSCustomObject]@{
    User = $UPN
    TempPassword = $TempPassword
    License = $LicenseSku
}
```

### User Offboarding
```powershell
param([string]$UserPrincipalName)

# Block sign-in
Update-MgUser -UserId $UserPrincipalName -AccountEnabled:$false

# Revoke sessions
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$UserPrincipalName/revokeSignInSessions"

# Convert mailbox to shared
Connect-ExchangeOnline
Set-Mailbox -Identity $UserPrincipalName -Type Shared

# Remove licenses
$Licenses = (Get-MgUserLicenseDetail -UserId $UserPrincipalName).SkuId
if ($Licenses) {
    Set-MgUserLicense -UserId $UserPrincipalName -RemoveLicenses $Licenses -AddLicenses @()
}

# Remove from all groups
$Groups = Get-MgUserMemberOf -UserId $UserPrincipalName -All
foreach ($Group in $Groups) {
    Remove-MgGroupMemberByRef -GroupId $Group.Id -DirectoryObjectId (Get-MgUser -UserId $UserPrincipalName).Id -ErrorAction SilentlyContinue
}

# Set out of office
Set-MailboxAutoReplyConfiguration -Identity $UserPrincipalName -AutoReplyState Enabled -InternalMessage "This user is no longer with the company." -ExternalMessage "This user is no longer with the company."

Write-Host "Offboarding complete for $UserPrincipalName" -ForegroundColor Green
```

### Bulk User Import
```powershell
$Users = Import-Csv "new-users.csv"
$Results = foreach ($User in $Users) {
    try {
        $PasswordProfile = @{
            Password = [System.Web.Security.Membership]::GeneratePassword(16, 4)
            ForceChangePasswordNextSignIn = $true
        }
        
        $NewUser = New-MgUser -DisplayName $User.DisplayName -GivenName $User.FirstName -Surname $User.LastName -UserPrincipalName $User.UPN -MailNickname $User.Alias -Department $User.Department -AccountEnabled -PasswordProfile $PasswordProfile
        
        if ($User.License) {
            $License = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq $User.License }
            Set-MgUserLicense -UserId $NewUser.Id -AddLicenses @{SkuId = $License.SkuId} -RemoveLicenses @()
        }
        
        [PSCustomObject]@{
            UPN = $User.UPN
            Status = "Success"
            TempPassword = $PasswordProfile.Password
        }
    } catch {
        [PSCustomObject]@{
            UPN = $User.UPN
            Status = "Failed: $($_.Exception.Message)"
            TempPassword = $null
        }
    }
}
$Results | Export-Csv "import-results.csv" -NoTypeInformation
```

## Reporting

### Monthly Client Report
```powershell
param([string]$TenantId, [string]$ClientName)

Connect-MgGraph -TenantId $TenantId
Connect-ExchangeOnline

$Report = @"
# Monthly IT Report - $ClientName
Generated: $(Get-Date -Format "yyyy-MM-dd")

## License Summary
"@

$Licenses = Get-MgSubscribedSku | Select-Object SkuPartNumber, @{N="Total";E={$_.PrepaidUnits.Enabled}}, ConsumedUnits, @{N="Available";E={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}}
$Report += $Licenses | ConvertTo-Html -Fragment

$Report += "`n## User Statistics`n"
$TotalUsers = (Get-MgUser -All).Count
$EnabledUsers = (Get-MgUser -All -Filter "accountEnabled eq true").Count
$GuestUsers = (Get-MgUser -All -Filter "userType eq 'Guest'").Count
$Report += "- Total Users: $TotalUsers`n- Enabled Users: $EnabledUsers`n- Guest Users: $GuestUsers`n"

$Report += "`n## Mailbox Statistics`n"
$Mailboxes = Get-Mailbox -ResultSize Unlimited
$TotalMailboxes = $Mailboxes.Count
$SharedMailboxes = ($Mailboxes | Where-Object { $_.RecipientTypeDetails -eq "SharedMailbox" }).Count
$Report += "- Total Mailboxes: $TotalMailboxes`n- Shared Mailboxes: $SharedMailboxes`n"

$Report | Out-File "$ClientName-Report-$(Get-Date -Format 'yyyyMM').md"
```

### Security Audit Report
```powershell
$Report = @()

# Admin role members
$AdminRoles = @("Global Administrator", "Exchange Administrator", "SharePoint Administrator", "User Administrator")
foreach ($RoleName in $AdminRoles) {
    $Role = Get-MgDirectoryRole -Filter "displayName eq '$RoleName'"
    if ($Role) {
        $Members = Get-MgDirectoryRoleMember -DirectoryRoleId $Role.Id
        foreach ($Member in $Members) {
            $Report += [PSCustomObject]@{
                Category = "Admin Role"
                Item = $RoleName
                Value = $Member.AdditionalProperties.displayName
            }
        }
    }
}

# MFA Status (requires Azure AD module or Graph Beta)
$Users = Get-MgUser -All -Property DisplayName,UserPrincipalName,UserType | Where-Object { $_.UserType -eq "Member" }
foreach ($User in $Users) {
    $AuthMethods = Get-MgUserAuthenticationMethod -UserId $User.Id
    $MfaEnabled = $AuthMethods.Count -gt 1
    $Report += [PSCustomObject]@{
        Category = "MFA Status"
        Item = $User.UserPrincipalName
        Value = if ($MfaEnabled) { "Enabled" } else { "Disabled" }
    }
}

# Mailbox forwarding
Connect-ExchangeOnline
$ForwardingMailboxes = Get-Mailbox -ResultSize Unlimited | Where-Object { $_.ForwardingSmtpAddress -or $_.ForwardingAddress }
foreach ($Mailbox in $ForwardingMailboxes) {
    $Report += [PSCustomObject]@{
        Category = "Mail Forwarding"
        Item = $Mailbox.PrimarySmtpAddress
        Value = if ($Mailbox.ForwardingSmtpAddress) { $Mailbox.ForwardingSmtpAddress } else { $Mailbox.ForwardingAddress }
    }
}

$Report | Export-Csv "security-audit.csv" -NoTypeInformation
```

### Stale Account Report
```powershell
$DaysInactive = 90
$CutoffDate = (Get-Date).AddDays(-$DaysInactive)

# Stale Users
$StaleUsers = Get-MgUser -All -Property DisplayName,UserPrincipalName,SignInActivity,AccountEnabled | Where-Object { 
    $_.AccountEnabled -and 
    $_.SignInActivity.LastSignInDateTime -lt $CutoffDate 
} | Select-Object DisplayName, UserPrincipalName, @{N="LastSignIn";E={$_.SignInActivity.LastSignInDateTime}}

# Stale Guests
$StaleGuests = Get-MgUser -All -Filter "userType eq 'Guest'" -Property DisplayName,UserPrincipalName,SignInActivity | Where-Object {
    $_.SignInActivity.LastSignInDateTime -lt $CutoffDate -or -not $_.SignInActivity.LastSignInDateTime
} | Select-Object DisplayName, UserPrincipalName, @{N="LastSignIn";E={$_.SignInActivity.LastSignInDateTime}}

# Stale Devices
$StaleDevices = Get-MgDevice -All | Where-Object { $_.ApproximateLastSignInDateTime -lt $CutoffDate } | Select-Object DisplayName, ApproximateLastSignInDateTime

$StaleUsers | Export-Csv "stale-users.csv" -NoTypeInformation
$StaleGuests | Export-Csv "stale-guests.csv" -NoTypeInformation
$StaleDevices | Export-Csv "stale-devices.csv" -NoTypeInformation
```

## Monitoring and Alerts

### Service Health Check
```powershell
$Health = Get-MgServiceAnnouncementHealthOverview | Select-Object Service, Status
$Issues = Get-MgServiceAnnouncementIssue | Where-Object { $_.Status -ne "resolved" } | Select-Object Title, Service, Status, StartDateTime

if ($Issues) {
    Write-Host "Active Service Issues:" -ForegroundColor Yellow
    $Issues | Format-Table -AutoSize
} else {
    Write-Host "No active service issues" -ForegroundColor Green
}
```

### Mailbox Over Quota Alert
```powershell
$Threshold = 45  # GB
$OverQuota = Get-Mailbox -ResultSize Unlimited | Get-MailboxStatistics | Where-Object {
    $_.TotalItemSize.Value.ToBytes()/1GB -gt $Threshold
} | Select-Object DisplayName, @{N="SizeGB";E={[math]::Round($_.TotalItemSize.Value.ToBytes()/1GB,2)}}

if ($OverQuota) {
    Write-Host "Mailboxes over ${Threshold}GB:" -ForegroundColor Yellow
    $OverQuota | Format-Table -AutoSize
}
```

### License Availability Alert
```powershell
$Threshold = 5  # Alert when less than 5 available
$LowLicenses = Get-MgSubscribedSku | Where-Object {
    ($_.PrepaidUnits.Enabled - $_.ConsumedUnits) -lt $Threshold -and $_.PrepaidUnits.Enabled -gt 0
} | Select-Object SkuPartNumber, @{N="Available";E={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}}

if ($LowLicenses) {
    Write-Host "Low license availability:" -ForegroundColor Yellow
    $LowLicenses | Format-Table -AutoSize
}
```

### Expiring App Credentials
```powershell
$DaysUntilExpiry = 30
$ExpiryDate = (Get-Date).AddDays($DaysUntilExpiry)

$ExpiringApps = Get-MgApplication -All | ForEach-Object {
    $App = $_
    $ExpiringCreds = @()
    
    $App.PasswordCredentials | Where-Object { $_.EndDateTime -lt $ExpiryDate } | ForEach-Object {
        $ExpiringCreds += [PSCustomObject]@{
            AppName = $App.DisplayName
            AppId = $App.AppId
            Type = "Secret"
            ExpiryDate = $_.EndDateTime
        }
    }
    
    $App.KeyCredentials | Where-Object { $_.EndDateTime -lt $ExpiryDate } | ForEach-Object {
        $ExpiringCreds += [PSCustomObject]@{
            AppName = $App.DisplayName
            AppId = $App.AppId
            Type = "Certificate"
            ExpiryDate = $_.EndDateTime
        }
    }
    
    $ExpiringCreds
}

if ($ExpiringApps) {
    Write-Host "App credentials expiring within $DaysUntilExpiry days:" -ForegroundColor Yellow
    $ExpiringApps | Format-Table -AutoSize
}
```

## Automation Patterns

### Scheduled Task Template (SYSTEM)
```powershell
# Script designed to run headless as SYSTEM
# No user interaction, all parameters hardcoded

$TenantId = "tenant-id"
$AppId = "app-client-id"
$CertThumbprint = "certificate-thumbprint"

try {
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $CertThumbprint -NoWelcome
    
    # Your automation logic here
    
} catch {
    $ErrorMessage = $_.Exception.Message
    # Log to Event Log or file
    Write-EventLog -LogName Application -Source "Admin-Automation" -EventId 1001 -EntryType Error -Message $ErrorMessage
} finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
}
```

### RMM Integration Pattern
```powershell
# Output format for RMM tools
param([string]$CheckType)

$Results = @{
    Status = "OK"
    Message = ""
    Details = @()
}

switch ($CheckType) {
    "DiskSpace" {
        $LowDisks = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and ($_.SizeRemaining/$_.Size)*100 -lt 15 }
        if ($LowDisks) {
            $Results.Status = "WARNING"
            $Results.Message = "Low disk space detected"
            $Results.Details = $LowDisks | Select-Object DriveLetter, @{N="PercentFree";E={[math]::Round(($_.SizeRemaining/$_.Size)*100,2)}}
        }
    }
    "Services" {
        $StoppedServices = Get-Service | Where-Object { $_.Status -eq "Stopped" -and $_.StartType -eq "Automatic" }
        if ($StoppedServices) {
            $Results.Status = "WARNING"
            $Results.Message = "Stopped auto-start services detected"
            $Results.Details = $StoppedServices | Select-Object Name, DisplayName
        }
    }
}

# RMM-compatible output
Write-Host "STATUS: $($Results.Status)"
Write-Host "MESSAGE: $($Results.Message)"
if ($Results.Details) {
    $Results.Details | Format-Table -AutoSize
}

# Exit code for RMM
switch ($Results.Status) {
    "OK" { exit 0 }
    "WARNING" { exit 1 }
    "CRITICAL" { exit 2 }
}
```

### Webhook Alert Pattern
```powershell
function Send-Alert {
    param(
        [string]$WebhookUrl,
        [string]$Title,
        [string]$Message,
        [string]$Severity = "warning"
    )
    
    # Teams webhook format
    $Body = @{
        "@type" = "MessageCard"
        "@context" = "http://schema.org/extensions"
        "themeColor" = switch ($Severity) { "critical" { "FF0000" } "warning" { "FFA500" } default { "00FF00" } }
        "summary" = $Title
        "sections" = @(
            @{
                "activityTitle" = $Title
                "facts" = @(
                    @{ "name" = "Message"; "value" = $Message }
                    @{ "name" = "Time"; "value" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") }
                    @{ "name" = "Server"; "value" = $env:COMPUTERNAME }
                )
            }
        )
    }
    
    Invoke-RestMethod -Uri $WebhookUrl -Method Post -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 10)
}

# Usage
Send-Alert -WebhookUrl "https://webhook.url" -Title "Disk Space Alert" -Message "C: drive below 15% free" -Severity "warning"
```

## Documentation Generation

### Tenant Documentation
```powershell
param([string]$OutputPath = ".")

$Doc = @"
# Tenant Documentation
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm")

## Organization Info
"@

$Org = Get-MgOrganization
$Doc += "`nTenant ID: $($Org.Id)`n"
$Doc += "Display Name: $($Org.DisplayName)`n"
$Doc += "Verified Domains: $(($Org.VerifiedDomains | Where-Object { $_.IsDefault }).Name)`n"

$Doc += "`n## License Summary`n"
$Doc += "| License | Total | Used | Available |`n"
$Doc += "|---------|-------|------|-----------|`n"
Get-MgSubscribedSku | ForEach-Object {
    $Doc += "| $($_.SkuPartNumber) | $($_.PrepaidUnits.Enabled) | $($_.ConsumedUnits) | $($_.PrepaidUnits.Enabled - $_.ConsumedUnits) |`n"
}

$Doc += "`n## Admin Accounts`n"
$GlobalAdminRole = Get-MgDirectoryRole -Filter "displayName eq 'Global Administrator'"
$Admins = Get-MgDirectoryRoleMember -DirectoryRoleId $GlobalAdminRole.Id
foreach ($Admin in $Admins) {
    $Doc += "- $($Admin.AdditionalProperties.displayName) ($($Admin.AdditionalProperties.userPrincipalName))`n"
}

$Doc | Out-File "$OutputPath\tenant-documentation.md" -Encoding UTF8
Write-Host "Documentation saved to $OutputPath\tenant-documentation.md"
```
