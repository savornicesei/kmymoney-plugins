# Entra ID (Azure AD) Administration

## Connection

### AzureAD Module (Legacy)
```powershell
Connect-AzureAD
```

### Microsoft Graph (Recommended)
```powershell
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","Directory.ReadWrite.All"
```

### Az Module
```powershell
Connect-AzAccount
```

## User Management (AzureAD Module)

### Get All Users
```powershell
Get-AzureADUser -All $true | Select-Object DisplayName, UserPrincipalName, AccountEnabled
```

### Get User
```powershell
Get-AzureADUser -ObjectId "user@domain.com"
```

### Create User
```powershell
$PasswordProfile = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
$PasswordProfile.Password = "TempPass123!"
$PasswordProfile.ForceChangePasswordNextLogin = $true
New-AzureADUser -DisplayName "First Last" -UserPrincipalName "user@domain.com" -PasswordProfile $PasswordProfile -AccountEnabled $true -MailNickName "user"
```

### Update User
```powershell
Set-AzureADUser -ObjectId "user@domain.com" -Department "IT" -JobTitle "Administrator"
```

### Disable User
```powershell
Set-AzureADUser -ObjectId "user@domain.com" -AccountEnabled $false
```

### Delete User
```powershell
Remove-AzureADUser -ObjectId "user@domain.com"
```

### Get Deleted Users
```powershell
Get-AzureADMSDeletedDirectoryObject -All | Where-Object { $_.'@odata.type' -eq "#microsoft.graph.user" }
```

### Restore Deleted User
```powershell
Restore-AzureADMSDeletedDirectoryObject -Id $ObjectId
```

### Get User Manager
```powershell
Get-AzureADUserManager -ObjectId "user@domain.com"
```

### Set User Manager
```powershell
$Manager = Get-AzureADUser -ObjectId "manager@domain.com"
Set-AzureADUserManager -ObjectId "user@domain.com" -RefObjectId $Manager.ObjectId
```

## Group Management

### Get All Groups
```powershell
Get-AzureADGroup -All $true | Select-Object DisplayName, ObjectId, SecurityEnabled, MailEnabled
```

### Get Security Groups
```powershell
Get-AzureADGroup -All $true | Where-Object { $_.SecurityEnabled -eq $true -and $_.MailEnabled -eq $false }
```

### Get M365 Groups
```powershell
Get-AzureADMSGroup -All $true | Where-Object { $_.GroupTypes -contains "Unified" }
```

### Create Security Group
```powershell
New-AzureADGroup -DisplayName "Security Group" -MailEnabled $false -MailNickName "secgroup" -SecurityEnabled $true
```

### Create Dynamic Group
```powershell
New-AzureADMSGroup -DisplayName "Dynamic Group" -MailEnabled $false -MailNickName "dyngroup" -SecurityEnabled $true -GroupTypes "DynamicMembership" -MembershipRule "(user.department -eq `"Sales`")" -MembershipRuleProcessingState "On"
```

### Get Group Members
```powershell
Get-AzureADGroupMember -ObjectId $GroupId -All $true | Select-Object DisplayName, UserPrincipalName
```

### Add Group Member
```powershell
Add-AzureADGroupMember -ObjectId $GroupId -RefObjectId $UserId
```

### Remove Group Member
```powershell
Remove-AzureADGroupMember -ObjectId $GroupId -MemberId $UserId
```

### Get User Groups
```powershell
Get-AzureADUserMembership -ObjectId "user@domain.com" | Select-Object DisplayName, ObjectType
```

### Get Group Owners
```powershell
Get-AzureADGroupOwner -ObjectId $GroupId | Select-Object DisplayName
```

### Add Group Owner
```powershell
Add-AzureADGroupOwner -ObjectId $GroupId -RefObjectId $UserId
```

## Licensing

### Get Subscribed SKUs
```powershell
Get-AzureADSubscribedSku | Select-Object SkuPartNumber, @{N="Available";E={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}}, @{N="Total";E={$_.PrepaidUnits.Enabled}}, ConsumedUnits
```

### Get User Licenses
```powershell
Get-AzureADUserLicenseDetail -ObjectId "user@domain.com" | Select-Object SkuPartNumber
```

### Assign License
```powershell
$License = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
$License.SkuId = (Get-AzureADSubscribedSku | Where-Object { $_.SkuPartNumber -eq "ENTERPRISEPACK" }).SkuId
$Licenses = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses
$Licenses.AddLicenses = $License
Set-AzureADUserLicense -ObjectId "user@domain.com" -AssignedLicenses $Licenses
```

### Remove License
```powershell
$License = Get-AzureADUserLicenseDetail -ObjectId "user@domain.com" | Where-Object { $_.SkuPartNumber -eq "ENTERPRISEPACK" }
$Licenses = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses
$Licenses.RemoveLicenses = $License.SkuId
Set-AzureADUserLicense -ObjectId "user@domain.com" -AssignedLicenses $Licenses
```

### Remove All Licenses
```powershell
$UserLicenses = (Get-AzureADUserLicenseDetail -ObjectId "user@domain.com").SkuId
$Licenses = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses
$Licenses.RemoveLicenses = $UserLicenses
Set-AzureADUserLicense -ObjectId "user@domain.com" -AssignedLicenses $Licenses
```

### Get Licensed Users
```powershell
Get-AzureADUser -All $true | Where-Object { $_.AssignedLicenses.Count -gt 0 } | Select-Object DisplayName, UserPrincipalName
```

### Get Unlicensed Users
```powershell
Get-AzureADUser -All $true | Where-Object { $_.AssignedLicenses.Count -eq 0 -and $_.UserType -eq "Member" } | Select-Object DisplayName, UserPrincipalName
```

### License with Disabled Plans
```powershell
$Sku = Get-AzureADSubscribedSku | Where-Object { $_.SkuPartNumber -eq "ENTERPRISEPACK" }
$DisabledPlans = $Sku.ServicePlans | Where-Object { $_.ServicePlanName -like "*YAMMER*" } | Select-Object -ExpandProperty ServicePlanId
$License = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
$License.SkuId = $Sku.SkuId
$License.DisabledPlans = $DisabledPlans
$Licenses = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses
$Licenses.AddLicenses = $License
Set-AzureADUserLicense -ObjectId "user@domain.com" -AssignedLicenses $Licenses
```

## Service Principals and Apps

### Get All Service Principals
```powershell
Get-AzureADServicePrincipal -All $true | Select-Object DisplayName, AppId, ServicePrincipalType
```

### Get App Registrations
```powershell
Get-AzureADApplication -All $true | Select-Object DisplayName, AppId, ObjectId
```

### Get App Credentials
```powershell
Get-AzureADApplication -ObjectId $AppId | Select-Object -ExpandProperty PasswordCredentials | Select-Object KeyId, EndDate
```

### Get Expiring App Credentials (30 Days)
```powershell
Get-AzureADApplication -All $true | ForEach-Object {
    $App = $_
    $_.PasswordCredentials | Where-Object { $_.EndDate -lt (Get-Date).AddDays(30) } | ForEach-Object {
        [PSCustomObject]@{
            AppName = $App.DisplayName
            AppId = $App.AppId
            KeyId = $_.KeyId
            ExpiryDate = $_.EndDate
        }
    }
}
```

### Add App Secret
```powershell
$PasswordCredential = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordCredential
$PasswordCredential.StartDate = Get-Date
$PasswordCredential.EndDate = (Get-Date).AddYears(1)
$PasswordCredential.KeyId = [guid]::NewGuid()
$PasswordCredential.Value = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([guid]::NewGuid()))
New-AzureADApplicationPasswordCredential -ObjectId $AppObjectId -PasswordCredential $PasswordCredential
```

## Device Management

### Get All Devices
```powershell
Get-AzureADDevice -All $true | Select-Object DisplayName, DeviceOSType, DeviceOSVersion, DeviceTrustType
```

### Get User Devices
```powershell
Get-AzureADUserRegisteredDevice -ObjectId "user@domain.com" | Select-Object DisplayName, DeviceOSType
```

### Get Stale Devices
```powershell
$Date = (Get-Date).AddDays(-90)
Get-AzureADDevice -All $true | Where-Object { $_.ApproximateLastLogonTimeStamp -lt $Date } | Select-Object DisplayName, ApproximateLastLogonTimeStamp
```

### Disable Device
```powershell
Set-AzureADDevice -ObjectId $DeviceId -AccountEnabled $false
```

### Delete Device
```powershell
Remove-AzureADDevice -ObjectId $DeviceId
```

## Roles and Admin Units

### Get Directory Roles
```powershell
Get-AzureADDirectoryRole | Select-Object DisplayName, ObjectId
```

### Get Role Members
```powershell
$Role = Get-AzureADDirectoryRole | Where-Object { $_.DisplayName -eq "Global Administrator" }
Get-AzureADDirectoryRoleMember -ObjectId $Role.ObjectId | Select-Object DisplayName, UserPrincipalName
```

### Add Role Member
```powershell
$Role = Get-AzureADDirectoryRole | Where-Object { $_.DisplayName -eq "User Administrator" }
$User = Get-AzureADUser -ObjectId "user@domain.com"
Add-AzureADDirectoryRoleMember -ObjectId $Role.ObjectId -RefObjectId $User.ObjectId
```

### Remove Role Member
```powershell
Remove-AzureADDirectoryRoleMember -ObjectId $RoleId -MemberId $UserId
```

### Get Admin Units
```powershell
Get-AzureADMSAdministrativeUnit | Select-Object DisplayName, Id
```

### Get Admin Unit Members
```powershell
Get-AzureADMSAdministrativeUnitMember -Id $AdminUnitId | ForEach-Object {
    Get-AzureADObjectByObjectId -ObjectIds $_.Id
}
```

## Domains

### Get Domains
```powershell
Get-AzureADDomain | Select-Object Name, IsDefault, IsVerified, AuthenticationType
```

### Get Default Domain
```powershell
Get-AzureADDomain | Where-Object { $_.IsDefault -eq $true }
```

### Verify Domain
```powershell
Confirm-AzureADDomain -Name "domain.com"
```

## Guest Users

### Get Guest Users
```powershell
Get-AzureADUser -All $true -Filter "userType eq 'Guest'" | Select-Object DisplayName, UserPrincipalName, Mail
```

### Invite Guest User
```powershell
New-AzureADMSInvitation -InvitedUserEmailAddress "guest@external.com" -InvitedUserDisplayName "External Guest" -SendInvitationMessage $true -InviteRedirectUrl "https://myapps.microsoft.com"
```

### Get Pending Invitations
```powershell
Get-AzureADUser -All $true -Filter "userType eq 'Guest'" | Where-Object { $_.UserState -eq "PendingAcceptance" } | Select-Object DisplayName, Mail, UserState
```

### Delete Guest User
```powershell
Remove-AzureADUser -ObjectId $GuestUserId
```

## Reporting

### User Report
```powershell
Get-AzureADUser -All $true | Select-Object DisplayName, UserPrincipalName, UserType, AccountEnabled, @{N="Licenses";E={(Get-AzureADUserLicenseDetail -ObjectId $_.ObjectId).SkuPartNumber -join ", "}} | Export-Csv "entra-users.csv" -NoTypeInformation
```

### License Report
```powershell
$Skus = Get-AzureADSubscribedSku
$Report = foreach ($Sku in $Skus) {
    [PSCustomObject]@{
        License = $Sku.SkuPartNumber
        Total = $Sku.PrepaidUnits.Enabled
        Consumed = $Sku.ConsumedUnits
        Available = $Sku.PrepaidUnits.Enabled - $Sku.ConsumedUnits
    }
}
$Report | Export-Csv "license-report.csv" -NoTypeInformation
```

### Group Report
```powershell
Get-AzureADGroup -All $true | ForEach-Object {
    $MemberCount = (Get-AzureADGroupMember -ObjectId $_.ObjectId -All $true).Count
    [PSCustomObject]@{
        GroupName = $_.DisplayName
        Type = if ($_.SecurityEnabled -and -not $_.MailEnabled) { "Security" } elseif ($_.GroupTypes -contains "Unified") { "M365" } else { "Distribution" }
        MemberCount = $MemberCount
    }
} | Export-Csv "group-report.csv" -NoTypeInformation
```

### Admin Role Report
```powershell
Get-AzureADDirectoryRole | ForEach-Object {
    $Role = $_
    Get-AzureADDirectoryRoleMember -ObjectId $_.ObjectId | ForEach-Object {
        [PSCustomObject]@{
            Role = $Role.DisplayName
            Member = $_.DisplayName
            UPN = $_.UserPrincipalName
        }
    }
} | Export-Csv "admin-roles.csv" -NoTypeInformation
```

## Hybrid Identity

### Get Azure AD Connect Status
```powershell
Get-AzureADTenantDetail | Select-Object -ExpandProperty TechnicalNotificationMails
```

### Get Synced Users
```powershell
Get-AzureADUser -All $true | Where-Object { $_.DirSyncEnabled -eq $true } | Select-Object DisplayName, UserPrincipalName
```

### Get Cloud-Only Users
```powershell
Get-AzureADUser -All $true | Where-Object { $_.DirSyncEnabled -ne $true } | Select-Object DisplayName, UserPrincipalName
```

## Conditional Access (Graph)

### Get All Policies
```powershell
Get-MgIdentityConditionalAccessPolicy | Select-Object DisplayName, State
```

### Get Enabled Policies
```powershell
Get-MgIdentityConditionalAccessPolicy | Where-Object { $_.State -eq "enabled" } | Select-Object DisplayName
```

### Export Policy Details
```powershell
Get-MgIdentityConditionalAccessPolicy | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.DisplayName
        State = $_.State
        Users = $_.Conditions.Users.IncludeUsers -join ", "
        Apps = $_.Conditions.Applications.IncludeApplications -join ", "
        GrantControls = $_.GrantControls.BuiltInControls -join ", "
    }
} | Export-Csv "conditional-access.csv" -NoTypeInformation
```
