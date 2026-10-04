# Microsoft Graph PowerShell

## Connection

### Interactive (Delegated)
```powershell
Connect-MgGraph -Scopes "User.Read.All","Group.ReadWrite.All","Directory.Read.All"
```

### App-Only (Certificate)
```powershell
Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
```

### App-Only (Client Secret)
```powershell
$Body = @{
    Grant_Type    = "client_credentials"
    Scope         = "https://graph.microsoft.com/.default"
    Client_Id     = $AppId
    Client_Secret = $ClientSecret
}
$Token = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $Body
Connect-MgGraph -AccessToken ($Token.access_token | ConvertTo-SecureString -AsPlainText -Force)
```

### Check Connection
```powershell
Get-MgContext | Select-Object Account, TenantId, Scopes
```

## User Management

### Get All Users
```powershell
Get-MgUser -All -Property DisplayName,UserPrincipalName,AccountEnabled,SignInActivity |
    Select-Object DisplayName, UserPrincipalName, AccountEnabled, @{N="LastSignIn";E={$_.SignInActivity.LastSignInDateTime}}
```

### Get User by UPN
```powershell
Get-MgUser -UserId "user@domain.com" -Property *
```

### Create User
```powershell
$PasswordProfile = @{
    Password = "TempPassword123!"
    ForceChangePasswordNextSignIn = $true
}
New-MgUser -DisplayName "First Last" -UserPrincipalName "user@domain.com" -MailNickname "user" -AccountEnabled -PasswordProfile $PasswordProfile
```

### Update User
```powershell
Update-MgUser -UserId "user@domain.com" -Department "IT" -JobTitle "Administrator"
```

### Disable User
```powershell
Update-MgUser -UserId "user@domain.com" -AccountEnabled:$false
```

### Delete User (Soft)
```powershell
Remove-MgUser -UserId "user@domain.com"
```

### Restore Deleted User
```powershell
Restore-MgDirectoryDeletedItem -DirectoryObjectId $DeletedUserId
```

### Get Deleted Users
```powershell
Get-MgDirectoryDeletedItem -DirectoryObjectType "microsoft.graph.user" | 
    Select-Object Id, @{N="UPN";E={$_.AdditionalProperties.userPrincipalName}}
```

### Get Inactive Users (90 Days)
```powershell
$Date = (Get-Date).AddDays(-90).ToString("yyyy-MM-ddTHH:mm:ssZ")
Get-MgUser -All -Property DisplayName,UserPrincipalName,SignInActivity |
    Where-Object { $_.SignInActivity.LastSignInDateTime -lt $Date } |
    Select-Object DisplayName, UserPrincipalName, @{N="LastSignIn";E={$_.SignInActivity.LastSignInDateTime}}
```

### Get Guest Users
```powershell
Get-MgUser -All -Filter "userType eq 'Guest'" | Select-Object DisplayName, UserPrincipalName, CreatedDateTime
```

### Reset Password
```powershell
$NewPassword = @{
    Password = "NewPassword123!"
    ForceChangePasswordNextSignIn = $true
}
Update-MgUser -UserId "user@domain.com" -PasswordProfile $NewPassword
```

### Get User Manager
```powershell
Get-MgUserManager -UserId "user@domain.com" | Select-Object @{N="Manager";E={$_.AdditionalProperties.displayName}}
```

### Set User Manager
```powershell
$Manager = Get-MgUser -UserId "manager@domain.com"
Set-MgUserManagerByRef -UserId "user@domain.com" -BodyParameter @{"@odata.id" = "https://graph.microsoft.com/v1.0/users/$($Manager.Id)"}
```

## Group Management

### Get All Groups
```powershell
Get-MgGroup -All | Select-Object DisplayName, GroupTypes, SecurityEnabled, MailEnabled
```

### Get M365 Groups
```powershell
Get-MgGroup -All -Filter "groupTypes/any(c:c eq 'Unified')" | Select-Object DisplayName, Mail
```

### Get Security Groups
```powershell
Get-MgGroup -All -Filter "securityEnabled eq true and mailEnabled eq false" | Select-Object DisplayName
```

### Create Security Group
```powershell
New-MgGroup -DisplayName "Security Group" -MailEnabled:$false -MailNickname "secgroup" -SecurityEnabled
```

### Create M365 Group
```powershell
New-MgGroup -DisplayName "M365 Group" -MailEnabled -MailNickname "m365group" -SecurityEnabled -GroupTypes "Unified"
```

### Get Group Members
```powershell
Get-MgGroupMember -GroupId $GroupId -All | ForEach-Object {
    Get-MgDirectoryObject -DirectoryObjectId $_.Id | Select-Object @{N="Name";E={$_.AdditionalProperties.displayName}}, @{N="Type";E={$_.AdditionalProperties.'@odata.type'}}
}
```

### Add Group Member
```powershell
New-MgGroupMember -GroupId $GroupId -DirectoryObjectId $UserId
```

### Remove Group Member
```powershell
Remove-MgGroupMemberByRef -GroupId $GroupId -DirectoryObjectId $UserId
```

### Get Group Owners
```powershell
Get-MgGroupOwner -GroupId $GroupId | ForEach-Object { $_.AdditionalProperties.displayName }
```

### Add Group Owner
```powershell
New-MgGroupOwner -GroupId $GroupId -DirectoryObjectId $UserId
```

### Get User Groups
```powershell
Get-MgUserMemberOf -UserId "user@domain.com" -All | ForEach-Object { $_.AdditionalProperties.displayName }
```

## Licensing

### Get Available Licenses
```powershell
Get-MgSubscribedSku | Select-Object SkuPartNumber, 
    @{N="Available";E={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}}, 
    @{N="Total";E={$_.PrepaidUnits.Enabled}}, 
    ConsumedUnits
```

### Get User Licenses
```powershell
Get-MgUserLicenseDetail -UserId "user@domain.com" | Select-Object SkuPartNumber, SkuId
```

### Assign License
```powershell
$License = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq "ENTERPRISEPACK" }
Set-MgUserLicense -UserId "user@domain.com" -AddLicenses @{SkuId = $License.SkuId} -RemoveLicenses @()
```

### Remove License
```powershell
$UserLicense = Get-MgUserLicenseDetail -UserId "user@domain.com" | Where-Object { $_.SkuPartNumber -eq "ENTERPRISEPACK" }
Set-MgUserLicense -UserId "user@domain.com" -RemoveLicenses @($UserLicense.SkuId) -AddLicenses @()
```

### Remove All Licenses
```powershell
$Licenses = (Get-MgUserLicenseDetail -UserId "user@domain.com").SkuId
Set-MgUserLicense -UserId "user@domain.com" -RemoveLicenses $Licenses -AddLicenses @()
```

### Get Licensed Users
```powershell
Get-MgUser -All -Property DisplayName,UserPrincipalName,AssignedLicenses |
    Where-Object { $_.AssignedLicenses.Count -gt 0 } |
    Select-Object DisplayName, UserPrincipalName
```

### Get Unlicensed Users
```powershell
Get-MgUser -All -Property DisplayName,UserPrincipalName,AssignedLicenses |
    Where-Object { $_.AssignedLicenses.Count -eq 0 } |
    Select-Object DisplayName, UserPrincipalName
```

### License Assignment with Disabled Plans
```powershell
$License = Get-MgSubscribedSku | Where-Object { $_.SkuPartNumber -eq "ENTERPRISEPACK" }
$DisabledPlans = $License.ServicePlans | Where-Object { $_.ServicePlanName -like "*YAMMER*" } | Select-Object -ExpandProperty ServicePlanId
Set-MgUserLicense -UserId "user@domain.com" -AddLicenses @{SkuId = $License.SkuId; DisabledPlans = $DisabledPlans} -RemoveLicenses @()
```

## Device Management

### Get All Devices
```powershell
Get-MgDevice -All | Select-Object DisplayName, OperatingSystem, OperatingSystemVersion, TrustType
```

### Get User Devices
```powershell
Get-MgUserRegisteredDevice -UserId "user@domain.com" | Select-Object @{N="Name";E={$_.AdditionalProperties.displayName}}
```

### Get Stale Devices (90 Days)
```powershell
$Date = (Get-Date).AddDays(-90)
Get-MgDevice -All | Where-Object { $_.ApproximateLastSignInDateTime -lt $Date } |
    Select-Object DisplayName, ApproximateLastSignInDateTime
```

## Application Management

### Get Enterprise Applications
```powershell
Get-MgServicePrincipal -All | Select-Object DisplayName, AppId, SignInAudience
```

### Get App Registrations
```powershell
Get-MgApplication -All | Select-Object DisplayName, AppId, CreatedDateTime
```

### Get App Permissions
```powershell
$App = Get-MgApplication -Filter "displayName eq 'App Name'"
$App.RequiredResourceAccess | ForEach-Object {
    $ResourceApp = Get-MgServicePrincipal -Filter "appId eq '$($_.ResourceAppId)'"
    $_.ResourceAccess | ForEach-Object {
        [PSCustomObject]@{
            Resource = $ResourceApp.DisplayName
            Permission = $_.Id
            Type = $_.Type
        }
    }
}
```

## Conditional Access

### Get All Policies
```powershell
Get-MgIdentityConditionalAccessPolicy | Select-Object DisplayName, State, CreatedDateTime
```

### Get Policy Details
```powershell
Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $PolicyId | Format-List *
```

### Get Enabled Policies
```powershell
Get-MgIdentityConditionalAccessPolicy -Filter "state eq 'enabled'" | Select-Object DisplayName
```

## Sign-In Logs

### Get Recent Sign-Ins
```powershell
Get-MgAuditLogSignIn -Top 100 | Select-Object UserDisplayName, AppDisplayName, Status, CreatedDateTime
```

### Get Failed Sign-Ins
```powershell
Get-MgAuditLogSignIn -Filter "status/errorCode ne 0" -Top 100 |
    Select-Object UserDisplayName, AppDisplayName, @{N="Error";E={$_.Status.ErrorCode}}, CreatedDateTime
```

### Get User Sign-Ins
```powershell
Get-MgAuditLogSignIn -Filter "userPrincipalName eq 'user@domain.com'" -Top 50 |
    Select-Object AppDisplayName, IpAddress, @{N="Location";E={$_.Location.City}}, CreatedDateTime
```

## Audit Logs

### Get Directory Audit Logs
```powershell
Get-MgAuditLogDirectoryAudit -Top 100 | Select-Object ActivityDisplayName, InitiatedBy, TargetResources, ActivityDateTime
```

### Get User Creation Events
```powershell
Get-MgAuditLogDirectoryAudit -Filter "activityDisplayName eq 'Add user'" -Top 50 |
    Select-Object @{N="CreatedBy";E={$_.InitiatedBy.User.DisplayName}}, @{N="User";E={$_.TargetResources.DisplayName}}, ActivityDateTime
```

## Service Health

### Get Service Health
```powershell
Get-MgServiceAnnouncementHealthOverview | Select-Object Service, Status
```

### Get Active Issues
```powershell
Get-MgServiceAnnouncementIssue -Filter "status ne 'resolved'" | Select-Object Title, Service, Status, StartDateTime
```

## Direct API Calls

### GET Request
```powershell
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users"
```

### POST Request
```powershell
$Body = @{
    displayName = "New User"
    userPrincipalName = "newuser@domain.com"
    mailNickname = "newuser"
    accountEnabled = $true
    passwordProfile = @{
        password = "TempPass123!"
        forceChangePasswordNextSignIn = $true
    }
}
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users" -Body $Body
```

### PATCH Request
```powershell
$Body = @{ department = "IT" }
Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/users/user@domain.com" -Body $Body
```

### Batch Request
```powershell
$Batch = @{
    requests = @(
        @{ id = "1"; method = "GET"; url = "/users/user1@domain.com" }
        @{ id = "2"; method = "GET"; url = "/users/user2@domain.com" }
        @{ id = "3"; method = "GET"; url = "/users/user3@domain.com" }
    )
}
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/`$batch" -Body $Batch
```

## Pagination

### Get All Results
```powershell
$AllUsers = @()
$Users = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users"
$AllUsers += $Users.value
while ($Users.'@odata.nextLink') {
    $Users = Invoke-MgGraphRequest -Method GET -Uri $Users.'@odata.nextLink'
    $AllUsers += $Users.value
}
```

## Common Scopes Reference

| Scope | Use |
|-------|-----|
| User.Read.All | Read all users |
| User.ReadWrite.All | Read/write all users |
| Group.Read.All | Read all groups |
| Group.ReadWrite.All | Read/write all groups |
| Directory.Read.All | Read directory data |
| Mail.Read | Read user mail |
| Mail.Send | Send mail |
| AuditLog.Read.All | Read audit logs |
| Reports.Read.All | Read reports |
| DeviceManagementManagedDevices.Read.All | Read Intune devices |
