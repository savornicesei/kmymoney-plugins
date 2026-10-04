# Active Directory Administration

## User Management

### Get User
```powershell
Get-ADUser -Identity username -Properties *
```

### Get User by Email
```powershell
Get-ADUser -Filter "EmailAddress -eq 'user@domain.com'" -Properties EmailAddress, DisplayName
```

### Search Users
```powershell
Get-ADUser -Filter "Name -like '*john*'" -Properties DisplayName, Department | Select-Object Name, SamAccountName, Department
```

### Get Users in OU
```powershell
Get-ADUser -Filter * -SearchBase "OU=Sales,DC=domain,DC=com" -Properties Department, Title | Select-Object Name, SamAccountName, Department, Title
```

### Create User
```powershell
$Password = ConvertTo-SecureString "TempPass123!" -AsPlainText -Force
New-ADUser -Name "First Last" -GivenName "First" -Surname "Last" -SamAccountName "flast" -UserPrincipalName "flast@domain.com" -Path "OU=Users,DC=domain,DC=com" -AccountPassword $Password -Enabled $true -ChangePasswordAtLogon $true
```

### Create User from Template
```powershell
$Template = Get-ADUser -Identity "templateuser" -Properties MemberOf, Department, Company
$Password = ConvertTo-SecureString "TempPass123!" -AsPlainText -Force
$NewUser = New-ADUser -Name "New User" -SamAccountName "nuser" -UserPrincipalName "nuser@domain.com" -Path $Template.DistinguishedName.Split(',',2)[1] -AccountPassword $Password -Enabled $true -PassThru
$Template.MemberOf | ForEach-Object { Add-ADGroupMember -Identity $_ -Members $NewUser }
```

### Bulk Create Users from CSV
```powershell
Import-Csv "users.csv" | ForEach-Object {
    $Password = ConvertTo-SecureString $_.Password -AsPlainText -Force
    New-ADUser -Name "$($_.FirstName) $($_.LastName)" -GivenName $_.FirstName -Surname $_.LastName -SamAccountName $_.Username -UserPrincipalName "$($_.Username)@domain.com" -Path $_.OU -AccountPassword $Password -Department $_.Department -Title $_.Title -Enabled $true
}
```

### Disable User
```powershell
Disable-ADAccount -Identity username
```

### Enable User
```powershell
Enable-ADAccount -Identity username
```

### Move User to OU
```powershell
Get-ADUser -Identity username | Move-ADObject -TargetPath "OU=Disabled,DC=domain,DC=com"
```

### Reset Password
```powershell
Set-ADAccountPassword -Identity username -Reset -NewPassword (ConvertTo-SecureString "NewPass123!" -AsPlainText -Force)
Set-ADUser -Identity username -ChangePasswordAtLogon $true
```

### Unlock Account
```powershell
Unlock-ADAccount -Identity username
```

### Get Locked Accounts
```powershell
Search-ADAccount -LockedOut | Select-Object Name, SamAccountName, LockedOut, LastLogonDate
```

### Find Account Lockout Source
```powershell
$PDC = (Get-ADDomain).PDCEmulator
$User = "username"
Get-WinEvent -ComputerName $PDC -FilterHashtable @{LogName='Security';Id=4740} | Where-Object { $_.Properties[0].Value -eq $User } | Select-Object TimeCreated, @{N='User';E={$_.Properties[0].Value}}, @{N='Source';E={$_.Properties[1].Value}}
```

### Get Password Expiration
```powershell
Get-ADUser -Identity username -Properties msDS-UserPasswordExpiryTimeComputed | Select-Object Name, @{N="PasswordExpires";E={[datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed")}}
```

### Get Users with Password Never Expires
```powershell
Get-ADUser -Filter { PasswordNeverExpires -eq $true -and Enabled -eq $true } -Properties PasswordNeverExpires | Select-Object Name, SamAccountName
```

### Get Inactive Users (90 Days)
```powershell
$Date = (Get-Date).AddDays(-90)
Get-ADUser -Filter { LastLogonDate -lt $Date -and Enabled -eq $true } -Properties LastLogonDate | Select-Object Name, SamAccountName, LastLogonDate | Sort-Object LastLogonDate
```

### Get Users with No Logon
```powershell
Get-ADUser -Filter { LastLogonDate -notlike "*" -and Enabled -eq $true } -Properties LastLogonDate | Select-Object Name, SamAccountName, WhenCreated
```

### Set User Attributes
```powershell
Set-ADUser -Identity username -Department "IT" -Title "Administrator" -Office "HQ" -Company "Company Name" -Manager "managerusername"
```

### Clear User Attribute
```powershell
Set-ADUser -Identity username -Clear Manager
```

### Get User Manager
```powershell
Get-ADUser -Identity username -Properties Manager | Select-Object Name, @{N="Manager";E={(Get-ADUser $_.Manager).Name}}
```

### Get Direct Reports
```powershell
Get-ADUser -Filter { Manager -eq "CN=Manager Name,OU=Users,DC=domain,DC=com" } | Select-Object Name, SamAccountName
```

## Group Management

### Get Group
```powershell
Get-ADGroup -Identity "GroupName" -Properties *
```

### Get Group Members
```powershell
Get-ADGroupMember -Identity "GroupName" | Select-Object Name, SamAccountName, ObjectClass
```

### Get Group Members Recursive
```powershell
Get-ADGroupMember -Identity "GroupName" -Recursive | Select-Object Name, SamAccountName
```

### Add User to Group
```powershell
Add-ADGroupMember -Identity "GroupName" -Members username
```

### Add Multiple Users to Group
```powershell
Add-ADGroupMember -Identity "GroupName" -Members user1, user2, user3
```

### Remove User from Group
```powershell
Remove-ADGroupMember -Identity "GroupName" -Members username -Confirm:$false
```

### Get User Group Memberships
```powershell
Get-ADPrincipalGroupMembership -Identity username | Select-Object Name | Sort-Object Name
```

### Create Security Group
```powershell
New-ADGroup -Name "New Security Group" -GroupScope Global -GroupCategory Security -Path "OU=Groups,DC=domain,DC=com" -Description "Group description"
```

### Create Distribution Group
```powershell
New-ADGroup -Name "New Distribution Group" -GroupScope Universal -GroupCategory Distribution -Path "OU=Groups,DC=domain,DC=com"
```

### Find Empty Groups
```powershell
Get-ADGroup -Filter * -Properties Members | Where-Object { $_.Members.Count -eq 0 } | Select-Object Name, DistinguishedName
```

### Copy Group Membership
```powershell
$SourceGroups = Get-ADPrincipalGroupMembership -Identity sourceuser
$SourceGroups | Where-Object { $_.Name -ne "Domain Users" } | ForEach-Object { Add-ADGroupMember -Identity $_.SamAccountName -Members targetuser }
```

### Compare Group Memberships
```powershell
$User1Groups = Get-ADPrincipalGroupMembership -Identity user1 | Select-Object -ExpandProperty Name
$User2Groups = Get-ADPrincipalGroupMembership -Identity user2 | Select-Object -ExpandProperty Name
Compare-Object $User1Groups $User2Groups
```

## Computer Management

### Get Computer
```powershell
Get-ADComputer -Identity COMPUTERNAME -Properties *
```

### Get All Computers
```powershell
Get-ADComputer -Filter * -Properties OperatingSystem, LastLogonDate | Select-Object Name, OperatingSystem, LastLogonDate | Sort-Object Name
```

### Get Computers by OS
```powershell
Get-ADComputer -Filter "OperatingSystem -like '*Server*'" -Properties OperatingSystem | Select-Object Name, OperatingSystem
```

### Get Inactive Computers (90 Days)
```powershell
$Date = (Get-Date).AddDays(-90)
Get-ADComputer -Filter { LastLogonDate -lt $Date } -Properties LastLogonDate | Select-Object Name, LastLogonDate | Sort-Object LastLogonDate
```

### Move Computer to OU
```powershell
Get-ADComputer -Identity COMPUTERNAME | Move-ADObject -TargetPath "OU=Workstations,DC=domain,DC=com"
```

### Disable Computer
```powershell
Disable-ADAccount -Identity "COMPUTERNAME$"
```

### Delete Computer
```powershell
Remove-ADComputer -Identity COMPUTERNAME -Confirm:$false
```

### Reset Computer Account
```powershell
Reset-ComputerMachinePassword -Server DCNAME -Credential (Get-Credential)
```

### Test Computer Secure Channel
```powershell
Test-ComputerSecureChannel -Repair -Credential (Get-Credential)
```

## Organizational Units

### Get All OUs
```powershell
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName
```

### Create OU
```powershell
New-ADOrganizationalUnit -Name "NewOU" -Path "DC=domain,DC=com" -ProtectedFromAccidentalDeletion $true
```

### Delete OU
```powershell
Set-ADOrganizationalUnit -Identity "OU=OldOU,DC=domain,DC=com" -ProtectedFromAccidentalDeletion $false
Remove-ADOrganizationalUnit -Identity "OU=OldOU,DC=domain,DC=com" -Confirm:$false
```

### Get OU Contents
```powershell
Get-ADObject -Filter * -SearchBase "OU=Users,DC=domain,DC=com" -SearchScope OneLevel | Select-Object Name, ObjectClass
```

## Domain and Forest

### Get Domain Info
```powershell
Get-ADDomain | Select-Object Name, DomainMode, PDCEmulator, RIDMaster, InfrastructureMaster
```

### Get Forest Info
```powershell
Get-ADForest | Select-Object Name, ForestMode, SchemaMaster, DomainNamingMaster, RootDomain
```

### Get Domain Controllers
```powershell
Get-ADDomainController -Filter * | Select-Object Name, IPv4Address, OperatingSystem, Site, IsGlobalCatalog
```

### Get FSMO Roles
```powershell
Get-ADDomain | Select-Object PDCEmulator, RIDMaster, InfrastructureMaster
Get-ADForest | Select-Object SchemaMaster, DomainNamingMaster
```

### Test Domain Controller
```powershell
dcdiag /s:DCNAME
```

### Test Replication
```powershell
repadmin /replsummary
repadmin /showrepl DCNAME
```

### Force Replication
```powershell
repadmin /syncall /Ade
```

## Group Policy

### Get All GPOs
```powershell
Get-GPO -All | Select-Object DisplayName, GpoStatus, CreationTime, ModificationTime
```

### Get GPO Links
```powershell
Get-GPO -Name "GPO Name" | Get-GPOReport -ReportType XML | Select-String "LinksTo"
```

### Get GPOs Linked to OU
```powershell
Get-GPInheritance -Target "OU=Users,DC=domain,DC=com" | Select-Object -ExpandProperty GpoLinks
```

### Create GPO
```powershell
New-GPO -Name "New GPO" -Comment "Description"
```

### Link GPO to OU
```powershell
New-GPLink -Name "GPO Name" -Target "OU=Users,DC=domain,DC=com"
```

### Backup GPO
```powershell
Backup-GPO -Name "GPO Name" -Path "C:\GPOBackups"
```

### Backup All GPOs
```powershell
Backup-GPO -All -Path "C:\GPOBackups"
```

### Restore GPO
```powershell
Restore-GPO -Name "GPO Name" -Path "C:\GPOBackups"
```

### Get GPO Report
```powershell
Get-GPOReport -Name "GPO Name" -ReportType HTML -Path "C:\gpo-report.html"
```

### Force GP Update Remote
```powershell
Invoke-GPUpdate -Computer "COMPUTERNAME" -Force
```

## Fine-Grained Password Policies

### Get Password Policies
```powershell
Get-ADFineGrainedPasswordPolicy -Filter * | Select-Object Name, Precedence, MinPasswordLength, MaxPasswordAge
```

### Create Password Policy
```powershell
New-ADFineGrainedPasswordPolicy -Name "Admin Password Policy" -Precedence 10 -MinPasswordLength 14 -MaxPasswordAge "90.00:00:00" -ComplexityEnabled $true -LockoutThreshold 5 -LockoutDuration "00:30:00"
```

### Apply Password Policy to Group
```powershell
Add-ADFineGrainedPasswordPolicySubject -Identity "Admin Password Policy" -Subjects "Domain Admins"
```

### Get Users with Specific Password Policy
```powershell
Get-ADFineGrainedPasswordPolicySubject -Identity "Admin Password Policy"
```

## Service Accounts

### Get Managed Service Accounts
```powershell
Get-ADServiceAccount -Filter * | Select-Object Name, SamAccountName, Enabled
```

### Create Managed Service Account
```powershell
New-ADServiceAccount -Name "svc_appname" -DNSHostName "svc_appname.domain.com" -PrincipalsAllowedToRetrieveManagedPassword "ServerGroup"
```

### Install Managed Service Account
```powershell
Install-ADServiceAccount -Identity "svc_appname"
```

### Test Managed Service Account
```powershell
Test-ADServiceAccount -Identity "svc_appname"
```

## Export and Reporting

### Export All Users
```powershell
Get-ADUser -Filter * -Properties DisplayName, EmailAddress, Department, Title, Manager, Enabled, LastLogonDate | Select-Object Name, SamAccountName, EmailAddress, Department, Title, @{N="Manager";E={(Get-ADUser $_.Manager -ErrorAction SilentlyContinue).Name}}, Enabled, LastLogonDate | Export-Csv "ad-users.csv" -NoTypeInformation
```

### Export All Groups
```powershell
Get-ADGroup -Filter * -Properties Description, ManagedBy, Members | Select-Object Name, GroupScope, GroupCategory, Description, @{N="MemberCount";E={$_.Members.Count}} | Export-Csv "ad-groups.csv" -NoTypeInformation
```

### Export All Computers
```powershell
Get-ADComputer -Filter * -Properties OperatingSystem, OperatingSystemVersion, LastLogonDate, IPv4Address | Select-Object Name, OperatingSystem, OperatingSystemVersion, LastLogonDate, IPv4Address | Export-Csv "ad-computers.csv" -NoTypeInformation
```

### Group Membership Report
```powershell
$Groups = Get-ADGroup -Filter * -SearchBase "OU=Security Groups,DC=domain,DC=com"
$Report = foreach ($Group in $Groups) {
    $Members = Get-ADGroupMember -Identity $Group -ErrorAction SilentlyContinue
    foreach ($Member in $Members) {
        [PSCustomObject]@{
            GroupName = $Group.Name
            MemberName = $Member.Name
            MemberType = $Member.ObjectClass
        }
    }
}
$Report | Export-Csv "group-membership.csv" -NoTypeInformation
```

### User Attribute Report
```powershell
$Attributes = @("DisplayName", "EmailAddress", "Department", "Title", "Manager", "WhenCreated", "PasswordLastSet", "LastLogonDate")
Get-ADUser -Filter { Enabled -eq $true } -Properties $Attributes | Select-Object $Attributes | Export-Csv "user-attributes.csv" -NoTypeInformation
```
