# Exchange Online Administration

## Connection

### Interactive
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@domain.com
```

### App-Only (Certificate)
```powershell
Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $Thumbprint -Organization "tenant.onmicrosoft.com"
```

### Check Connection
```powershell
Get-ConnectionInformation
```

## Mailbox Management

### Get All Mailboxes
```powershell
Get-Mailbox -ResultSize Unlimited | Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails
```

### Get Mailbox by Type
```powershell
Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox | Select-Object DisplayName, PrimarySmtpAddress
Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails SharedMailbox | Select-Object DisplayName, PrimarySmtpAddress
Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails RoomMailbox | Select-Object DisplayName, PrimarySmtpAddress
```

### Get Mailbox Statistics
```powershell
Get-MailboxStatistics -Identity "user@domain.com" | Select-Object DisplayName, TotalItemSize, ItemCount, LastLogonTime
```

### Get All Mailbox Sizes
```powershell
Get-Mailbox -ResultSize Unlimited | Get-MailboxStatistics | Select-Object DisplayName, @{N="SizeGB";E={[math]::Round($_.TotalItemSize.Value.ToBytes()/1GB,2)}}, ItemCount | Sort-Object SizeGB -Descending
```

### Create Shared Mailbox
```powershell
New-Mailbox -Shared -Name "Shared Mailbox" -DisplayName "Shared Mailbox" -Alias sharedmbx -PrimarySmtpAddress shared@domain.com
```

### Convert to Shared Mailbox
```powershell
Set-Mailbox -Identity "user@domain.com" -Type Shared
```

### Convert to User Mailbox
```powershell
Set-Mailbox -Identity "shared@domain.com" -Type Regular
```

### Set Mailbox Properties
```powershell
Set-Mailbox -Identity "user@domain.com" -DisplayName "New Display Name" -CustomAttribute1 "Value"
```

### Hide from GAL
```powershell
Set-Mailbox -Identity "user@domain.com" -HiddenFromAddressListsEnabled $true
```

### Set Mailbox Quota
```powershell
Set-Mailbox -Identity "user@domain.com" -ProhibitSendQuota 49GB -ProhibitSendReceiveQuota 50GB -IssueWarningQuota 48GB
```

### Enable Archive
```powershell
Enable-Mailbox -Identity "user@domain.com" -Archive
```

### Get Archive Statistics
```powershell
Get-MailboxStatistics -Identity "user@domain.com" -Archive | Select-Object DisplayName, TotalItemSize, ItemCount
```

## Mailbox Permissions

### Get Mailbox Permissions
```powershell
Get-MailboxPermission -Identity "mailbox@domain.com" | Where-Object { $_.User -notlike "NT AUTHORITY\*" -and $_.User -notlike "S-1-5-*" } | Select-Object User, AccessRights
```

### Grant Full Access
```powershell
Add-MailboxPermission -Identity "mailbox@domain.com" -User "user@domain.com" -AccessRights FullAccess -InheritanceType All
```

### Grant Full Access (No Automapping)
```powershell
Add-MailboxPermission -Identity "mailbox@domain.com" -User "user@domain.com" -AccessRights FullAccess -AutoMapping $false
```

### Remove Full Access
```powershell
Remove-MailboxPermission -Identity "mailbox@domain.com" -User "user@domain.com" -AccessRights FullAccess -Confirm:$false
```

### Grant Send As
```powershell
Add-RecipientPermission -Identity "mailbox@domain.com" -Trustee "user@domain.com" -AccessRights SendAs -Confirm:$false
```

### Get Send As Permissions
```powershell
Get-RecipientPermission -Identity "mailbox@domain.com" | Where-Object { $_.Trustee -notlike "NT AUTHORITY\*" } | Select-Object Trustee, AccessRights
```

### Remove Send As
```powershell
Remove-RecipientPermission -Identity "mailbox@domain.com" -Trustee "user@domain.com" -AccessRights SendAs -Confirm:$false
```

### Grant Send on Behalf
```powershell
Set-Mailbox -Identity "mailbox@domain.com" -GrantSendOnBehalfTo @{Add="user@domain.com"}
```

### Get Delegate Permissions
```powershell
Get-Mailbox -Identity "mailbox@domain.com" | Select-Object -ExpandProperty GrantSendOnBehalfTo
```

## Calendar Permissions

### Get Calendar Permissions
```powershell
Get-MailboxFolderPermission -Identity "user@domain.com:\Calendar" | Select-Object User, AccessRights
```

### Grant Calendar Access
```powershell
Add-MailboxFolderPermission -Identity "user@domain.com:\Calendar" -User "user2@domain.com" -AccessRights Editor
```

### Modify Calendar Access
```powershell
Set-MailboxFolderPermission -Identity "user@domain.com:\Calendar" -User "user2@domain.com" -AccessRights Reviewer
```

### Remove Calendar Access
```powershell
Remove-MailboxFolderPermission -Identity "user@domain.com:\Calendar" -User "user2@domain.com" -Confirm:$false
```

### Grant Default Calendar Access (All Users)
```powershell
Set-MailboxFolderPermission -Identity "user@domain.com:\Calendar" -User Default -AccessRights LimitedDetails
```

## Mail Flow

### Set Forwarding
```powershell
Set-Mailbox -Identity "user@domain.com" -ForwardingSmtpAddress "forward@domain.com" -DeliverToMailboxAndForward $true
```

### Remove Forwarding
```powershell
Set-Mailbox -Identity "user@domain.com" -ForwardingSmtpAddress $null -ForwardingAddress $null
```

### Get All Forwarding Rules
```powershell
Get-Mailbox -ResultSize Unlimited | Where-Object { $_.ForwardingSmtpAddress -ne $null -or $_.ForwardingAddress -ne $null } | Select-Object DisplayName, ForwardingSmtpAddress, ForwardingAddress, DeliverToMailboxAndForward
```

### Get Inbox Rules
```powershell
Get-InboxRule -Mailbox "user@domain.com" | Select-Object Name, Description, Enabled
```

### Get Inbox Rules with Forwarding
```powershell
Get-Mailbox -ResultSize Unlimited | ForEach-Object {
    Get-InboxRule -Mailbox $_.PrimarySmtpAddress | Where-Object { $_.ForwardTo -or $_.RedirectTo }
} | Select-Object MailboxOwnerId, Name, ForwardTo, RedirectTo
```

### Remove Inbox Rule
```powershell
Remove-InboxRule -Mailbox "user@domain.com" -Identity "Rule Name" -Confirm:$false
```

### Disable Inbox Rule
```powershell
Disable-InboxRule -Mailbox "user@domain.com" -Identity "Rule Name" -Confirm:$false
```

## Distribution Groups

### Get All Distribution Groups
```powershell
Get-DistributionGroup -ResultSize Unlimited | Select-Object DisplayName, PrimarySmtpAddress, GroupType
```

### Create Distribution Group
```powershell
New-DistributionGroup -Name "Team DL" -DisplayName "Team DL" -Alias teamdl -PrimarySmtpAddress teamdl@domain.com
```

### Create Dynamic Distribution Group
```powershell
New-DynamicDistributionGroup -Name "All Sales" -Alias allsales -RecipientFilter "Department -eq 'Sales'"
```

### Get Group Members
```powershell
Get-DistributionGroupMember -Identity "groupname" -ResultSize Unlimited | Select-Object Name, PrimarySmtpAddress
```

### Add Group Member
```powershell
Add-DistributionGroupMember -Identity "groupname" -Member "user@domain.com"
```

### Remove Group Member
```powershell
Remove-DistributionGroupMember -Identity "groupname" -Member "user@domain.com" -Confirm:$false
```

### Get Dynamic Group Members
```powershell
$Group = Get-DynamicDistributionGroup -Identity "groupname"
Get-Recipient -RecipientPreviewFilter $Group.RecipientFilter | Select-Object DisplayName, PrimarySmtpAddress
```

### Set Group Moderation
```powershell
Set-DistributionGroup -Identity "groupname" -ModerationEnabled $true -ModeratedBy "moderator@domain.com"
```

### Allow External Senders
```powershell
Set-DistributionGroup -Identity "groupname" -RequireSenderAuthenticationEnabled $false
```

## M365 Groups

### Get All M365 Groups
```powershell
Get-UnifiedGroup -ResultSize Unlimited | Select-Object DisplayName, PrimarySmtpAddress, ManagedBy
```

### Create M365 Group
```powershell
New-UnifiedGroup -DisplayName "Project Team" -Alias projectteam -AccessType Private
```

### Get M365 Group Members
```powershell
Get-UnifiedGroupLinks -Identity "groupname" -LinkType Members | Select-Object Name, PrimarySmtpAddress
```

### Add M365 Group Member
```powershell
Add-UnifiedGroupLinks -Identity "groupname" -LinkType Members -Links "user@domain.com"
```

### Add M365 Group Owner
```powershell
Add-UnifiedGroupLinks -Identity "groupname" -LinkType Owners -Links "user@domain.com"
```

## Transport Rules

### Get Transport Rules
```powershell
Get-TransportRule | Select-Object Name, State, Priority
```

### Get Rule Details
```powershell
Get-TransportRule -Identity "Rule Name" | Format-List *
```

### Create Transport Rule
```powershell
New-TransportRule -Name "External Email Disclaimer" -ApplyHtmlDisclaimerLocation Append -ApplyHtmlDisclaimerText "DISCLAIMER: This email is confidential." -FromScope NotInOrganization
```

### Disable Transport Rule
```powershell
Disable-TransportRule -Identity "Rule Name" -Confirm:$false
```

### Enable Transport Rule
```powershell
Enable-TransportRule -Identity "Rule Name"
```

## Message Trace

### Trace by Sender
```powershell
Get-MessageTrace -SenderAddress "sender@domain.com" -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) | Select-Object Received, SenderAddress, RecipientAddress, Subject, Status
```

### Trace by Recipient
```powershell
Get-MessageTrace -RecipientAddress "recipient@domain.com" -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) | Select-Object Received, SenderAddress, RecipientAddress, Subject, Status
```

### Trace Failed Messages
```powershell
Get-MessageTrace -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) -Status Failed | Select-Object Received, SenderAddress, RecipientAddress, Subject
```

### Get Message Trace Details
```powershell
Get-MessageTraceDetail -MessageTraceId $MessageTraceId -RecipientAddress "recipient@domain.com" | Select-Object Date, Event, Detail
```

### Export Message Trace
```powershell
Get-MessageTrace -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) | Export-Csv "messagetrace.csv" -NoTypeInformation
```

## Retention and Compliance

### Get Retention Policies
```powershell
Get-RetentionPolicy | Select-Object Name, RetentionPolicyTagLinks
```

### Get Retention Tags
```powershell
Get-RetentionPolicyTag | Select-Object Name, Type, RetentionAction, AgeLimitForRetention
```

### Place Mailbox on Litigation Hold
```powershell
Set-Mailbox -Identity "user@domain.com" -LitigationHoldEnabled $true -LitigationHoldDuration 365
```

### Get Mailboxes on Hold
```powershell
Get-Mailbox -ResultSize Unlimited | Where-Object { $_.LitigationHoldEnabled -eq $true } | Select-Object DisplayName, LitigationHoldEnabled, LitigationHoldDate
```

### Remove Litigation Hold
```powershell
Set-Mailbox -Identity "user@domain.com" -LitigationHoldEnabled $false
```

## Resource Mailboxes

### Create Room Mailbox
```powershell
New-Mailbox -Room -Name "Conference Room A" -DisplayName "Conference Room A" -Alias confrooma
```

### Create Equipment Mailbox
```powershell
New-Mailbox -Equipment -Name "Projector 1" -DisplayName "Projector 1" -Alias projector1
```

### Set Room Booking Options
```powershell
Set-CalendarProcessing -Identity "confrooma" -AutomateProcessing AutoAccept -AllowConflicts $false -BookingWindowInDays 180 -MaximumDurationInMinutes 480
```

### Get Room Configuration
```powershell
Get-CalendarProcessing -Identity "confrooma" | Select-Object AutomateProcessing, AllowConflicts, BookingWindowInDays
```

### Set Room Capacity
```powershell
Set-Place -Identity "confrooma" -Capacity 20
```

### Get All Rooms
```powershell
Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails RoomMailbox | Select-Object DisplayName, PrimarySmtpAddress
```

## Email Addresses

### Add Email Alias
```powershell
Set-Mailbox -Identity "user@domain.com" -EmailAddresses @{Add="alias@domain.com"}
```

### Remove Email Alias
```powershell
Set-Mailbox -Identity "user@domain.com" -EmailAddresses @{Remove="alias@domain.com"}
```

### Set Primary SMTP Address
```powershell
Set-Mailbox -Identity "user@domain.com" -WindowsEmailAddress "newprimary@domain.com"
```

### Get All Email Addresses
```powershell
Get-Mailbox -Identity "user@domain.com" | Select-Object -ExpandProperty EmailAddresses
```

## Mobile Device Management

### Get Mobile Devices
```powershell
Get-MobileDevice -Mailbox "user@domain.com" | Select-Object FriendlyName, DeviceModel, DeviceOS, FirstSyncTime, LastSuccessSync
```

### Get All Mobile Devices
```powershell
Get-MobileDevice -ResultSize Unlimited | Select-Object UserDisplayName, FriendlyName, DeviceModel, LastSuccessSync
```

### Remove Mobile Device
```powershell
Remove-MobileDevice -Identity $DeviceId -Confirm:$false
```

### Wipe Mobile Device
```powershell
Clear-MobileDevice -Identity $DeviceId -Confirm:$false
```

### Get Mobile Device Statistics
```powershell
Get-MobileDeviceStatistics -Mailbox "user@domain.com" | Select-Object DeviceFriendlyName, DeviceModel, LastSuccessSync, Status
```

## Mailbox Export/Import

### Create Export Request
```powershell
New-MailboxExportRequest -Mailbox "user@domain.com" -FilePath "\\server\share\export.pst"
```

### Get Export Status
```powershell
Get-MailboxExportRequest | Get-MailboxExportRequestStatistics | Select-Object TargetMailbox, Status, PercentComplete
```

### Create Import Request
```powershell
New-MailboxImportRequest -Mailbox "user@domain.com" -FilePath "\\server\share\import.pst"
```

### Get Import Status
```powershell
Get-MailboxImportRequest | Get-MailboxImportRequestStatistics | Select-Object TargetMailbox, Status, PercentComplete
```

## Reporting

### Get Mailbox Usage Report
```powershell
Get-Mailbox -ResultSize Unlimited | ForEach-Object {
    $Stats = Get-MailboxStatistics -Identity $_.PrimarySmtpAddress
    [PSCustomObject]@{
        DisplayName = $_.DisplayName
        Email = $_.PrimarySmtpAddress
        Type = $_.RecipientTypeDetails
        SizeGB = [math]::Round($Stats.TotalItemSize.Value.ToBytes()/1GB,2)
        ItemCount = $Stats.ItemCount
        LastLogon = $Stats.LastLogonTime
    }
} | Sort-Object SizeGB -Descending | Export-Csv "mailbox-report.csv" -NoTypeInformation
```

### Get Shared Mailbox Report
```powershell
Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails SharedMailbox | ForEach-Object {
    $Permissions = Get-MailboxPermission -Identity $_.PrimarySmtpAddress | Where-Object { $_.User -notlike "NT AUTHORITY\*" }
    [PSCustomObject]@{
        Mailbox = $_.DisplayName
        Email = $_.PrimarySmtpAddress
        FullAccess = ($Permissions | Where-Object { $_.AccessRights -contains "FullAccess" }).User -join "; "
    }
}
```
