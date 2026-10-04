# Security and Hardening

## BitLocker

### Get BitLocker Status
```powershell
Get-BitLockerVolume | Select-Object MountPoint, VolumeStatus, EncryptionPercentage, ProtectionStatus, KeyProtector
```

### Enable BitLocker (TPM)
```powershell
Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -UsedSpaceOnly -TpmProtector
Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector
```

### Enable BitLocker (Password)
```powershell
$Password = ConvertTo-SecureString "StrongPassword123!" -AsPlainText -Force
Enable-BitLocker -MountPoint "D:" -EncryptionMethod XtsAes256 -UsedSpaceOnly -PasswordProtector -Password $Password
```

### Get Recovery Key
```powershell
(Get-BitLockerVolume -MountPoint "C:").KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" } | Select-Object KeyProtectorId, RecoveryPassword
```

### Backup Recovery Key to AD
```powershell
$KeyProtector = (Get-BitLockerVolume -MountPoint "C:").KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
Backup-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $KeyProtector.KeyProtectorId
```

### Suspend BitLocker
```powershell
Suspend-BitLocker -MountPoint "C:" -RebootCount 1
```

### Resume BitLocker
```powershell
Resume-BitLocker -MountPoint "C:"
```

### Disable BitLocker
```powershell
Disable-BitLocker -MountPoint "C:"
```

## Windows Defender

### Get Defender Status
```powershell
Get-MpComputerStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled, IoavProtectionEnabled, BehaviorMonitorEnabled, AntivirusSignatureLastUpdated
```

### Update Definitions
```powershell
Update-MpSignature
```

### Run Quick Scan
```powershell
Start-MpScan -ScanType QuickScan
```

### Run Full Scan
```powershell
Start-MpScan -ScanType FullScan
```

### Scan Specific Path
```powershell
Start-MpScan -ScanType CustomScan -ScanPath "C:\Suspicious"
```

### Get Threat Detection
```powershell
Get-MpThreat | Select-Object ThreatName, SeverityID, IsActive, DidThreatExecute
```

### Get Detection History
```powershell
Get-MpThreatDetection | Select-Object ThreatID, @{N="Threat";E={(Get-MpThreat -ThreatID $_.ThreatID).ThreatName}}, InitialDetectionTime, ActionSuccess
```

### Add Exclusion Path
```powershell
Add-MpPreference -ExclusionPath "C:\SafeFolder"
```

### Add Exclusion Extension
```powershell
Add-MpPreference -ExclusionExtension ".log"
```

### Add Exclusion Process
```powershell
Add-MpPreference -ExclusionProcess "safeapp.exe"
```

### Get Exclusions
```powershell
Get-MpPreference | Select-Object ExclusionPath, ExclusionExtension, ExclusionProcess
```

### Remove Exclusion
```powershell
Remove-MpPreference -ExclusionPath "C:\SafeFolder"
```

### Set Real-Time Protection
```powershell
Set-MpPreference -DisableRealtimeMonitoring $false
```

## Certificate Management

### Get Certificates (Local Machine)
```powershell
Get-ChildItem -Path Cert:\LocalMachine\My | Select-Object Subject, Thumbprint, NotAfter, Issuer
```

### Get Expiring Certificates (30 Days)
```powershell
$Date = (Get-Date).AddDays(30)
Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.NotAfter -lt $Date } | Select-Object Subject, NotAfter, Thumbprint
```

### Get Certificate Details
```powershell
Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq "THUMBPRINT" } | Format-List Subject, Issuer, NotBefore, NotAfter, Thumbprint, EnhancedKeyUsageList
```

### Export Certificate
```powershell
$Cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq "THUMBPRINT" }
Export-Certificate -Cert $Cert -FilePath "C:\cert.cer"
```

### Export Certificate with Private Key
```powershell
$Password = ConvertTo-SecureString "ExportPassword" -AsPlainText -Force
$Cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq "THUMBPRINT" }
Export-PfxCertificate -Cert $Cert -FilePath "C:\cert.pfx" -Password $Password
```

### Import Certificate
```powershell
Import-Certificate -FilePath "C:\cert.cer" -CertStoreLocation Cert:\LocalMachine\My
```

### Import PFX
```powershell
$Password = ConvertTo-SecureString "ImportPassword" -AsPlainText -Force
Import-PfxCertificate -FilePath "C:\cert.pfx" -CertStoreLocation Cert:\LocalMachine\My -Password $Password
```

### Delete Certificate
```powershell
Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq "THUMBPRINT" } | Remove-Item
```

### Request Certificate
```powershell
$Template = "WebServer"
$Subject = "CN=server.domain.com"
Get-Certificate -Template $Template -SubjectName $Subject -CertStoreLocation Cert:\LocalMachine\My
```

## Audit and Security Logs

### Enable Audit Policy
```powershell
auditpol /set /category:"Logon/Logoff" /success:enable /failure:enable
auditpol /set /category:"Account Logon" /success:enable /failure:enable
auditpol /set /category:"Object Access" /success:enable /failure:enable
```

### Get Audit Policy
```powershell
auditpol /get /category:*
```

### Get Failed Logons
```powershell
Get-EventLog -LogName Security -InstanceId 4625 -After (Get-Date).AddDays(-7) | Select-Object TimeGenerated, @{N="User";E={$_.ReplacementStrings[5]}}, @{N="IP";E={$_.ReplacementStrings[19]}}, @{N="Reason";E={$_.ReplacementStrings[8]}}
```

### Get Account Lockouts
```powershell
Get-EventLog -LogName Security -InstanceId 4740 -After (Get-Date).AddDays(-7) | Select-Object TimeGenerated, @{N="Account";E={$_.ReplacementStrings[0]}}, @{N="Source";E={$_.ReplacementStrings[1]}}
```

### Get Password Changes
```powershell
Get-EventLog -LogName Security -InstanceId 4723,4724 -After (Get-Date).AddDays(-7) | Select-Object TimeGenerated, @{N="User";E={$_.ReplacementStrings[0]}}, @{N="ChangedBy";E={$_.ReplacementStrings[4]}}
```

### Get User Creation Events
```powershell
Get-EventLog -LogName Security -InstanceId 4720 -After (Get-Date).AddDays(-30) | Select-Object TimeGenerated, @{N="NewUser";E={$_.ReplacementStrings[0]}}, @{N="CreatedBy";E={$_.ReplacementStrings[4]}}
```

### Get Privileged Logons
```powershell
Get-EventLog -LogName Security -InstanceId 4672 -After (Get-Date).AddDays(-1) | Select-Object TimeGenerated, @{N="User";E={$_.ReplacementStrings[1]}}
```

## File System Security

### Get File/Folder Permissions
```powershell
Get-Acl -Path "C:\Data" | Select-Object -ExpandProperty Access | Select-Object IdentityReference, FileSystemRights, AccessControlType, IsInherited
```

### Set Folder Permissions
```powershell
$Acl = Get-Acl -Path "C:\Data"
$Rule = New-Object System.Security.AccessControl.FileSystemAccessRule("DOMAIN\Group", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
$Acl.SetAccessRule($Rule)
Set-Acl -Path "C:\Data" -AclObject $Acl
```

### Remove Permission
```powershell
$Acl = Get-Acl -Path "C:\Data"
$Rule = New-Object System.Security.AccessControl.FileSystemAccessRule("DOMAIN\User", "FullControl", "Allow")
$Acl.RemoveAccessRule($Rule)
Set-Acl -Path "C:\Data" -AclObject $Acl
```

### Disable Inheritance
```powershell
$Acl = Get-Acl -Path "C:\Data"
$Acl.SetAccessRuleProtection($true, $true)
Set-Acl -Path "C:\Data" -AclObject $Acl
```

### Take Ownership
```powershell
$Acl = Get-Acl -Path "C:\Data"
$User = [System.Security.Principal.NTAccount]"DOMAIN\Admin"
$Acl.SetOwner($User)
Set-Acl -Path "C:\Data" -AclObject $Acl
```

### Get Owner
```powershell
Get-Acl -Path "C:\Data" | Select-Object Owner
```

## Security Hardening

### Disable SMBv1
```powershell
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
```

### Check SMB Versions
```powershell
Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol
```

### Enable SMB Signing
```powershell
Set-SmbServerConfiguration -RequireSecuritySignature $true -Force
Set-SmbClientConfiguration -RequireSecuritySignature $true -Force
```

### Disable LLMNR
```powershell
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -Value 0 -Type DWord
```

### Disable NetBIOS
```powershell
$Adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
$Adapters | ForEach-Object { $_.SetTcpipNetbios(2) }
```

### Disable WPAD
```powershell
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad" -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad" -Name "WpadOverride" -Value 1 -Type DWord
```

### Enable Credential Guard
```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\LSA" -Name "LsaCfgFlags" -Value 1 -Type DWord
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -Value 1 -Type DWord
```

### Disable WDigest
```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -Name "UseLogonCredential" -Value 0 -Type DWord
```

### Enable LSA Protection
```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -Value 1 -Type DWord
```

## Password Policies

### Get Domain Password Policy
```powershell
Get-ADDefaultDomainPasswordPolicy | Select-Object ComplexityEnabled, MinPasswordLength, PasswordHistoryCount, MaxPasswordAge, MinPasswordAge, LockoutThreshold, LockoutDuration
```

### Get Fine-Grained Password Policies
```powershell
Get-ADFineGrainedPasswordPolicy -Filter * | Select-Object Name, Precedence, MinPasswordLength, MaxPasswordAge, LockoutThreshold
```

### Get Local Password Policy
```powershell
net accounts
```

### Set Local Password Policy
```powershell
net accounts /minpwlen:14 /maxpwage:90 /minpwage:1 /uniquepw:24
```

## Security Scanning

### Get Open Ports
```powershell
Get-NetTCPConnection | Where-Object { $_.State -eq "Listen" } | Select-Object LocalAddress, LocalPort, @{N="Process";E={(Get-Process -Id $_.OwningProcess).Name}} | Sort-Object LocalPort
```

### Find Unsigned Drivers
```powershell
Get-WindowsDriver -Online -All | Where-Object { $_.DriverSignature -ne "Signed" } | Select-Object Driver, ClassName, ProviderName, DriverSignature
```

### Get Running Services with Paths
```powershell
Get-CimInstance Win32_Service | Where-Object { $_.State -eq "Running" } | Select-Object Name, StartName, PathName | Sort-Object StartName
```

### Check for Unquoted Service Paths
```powershell
Get-CimInstance Win32_Service | Where-Object { $_.PathName -notlike '"*' -and $_.PathName -like '* *' } | Select-Object Name, PathName
```

### Get Startup Programs
```powershell
Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, User, Location
```

### Get Scheduled Tasks with Actions
```powershell
Get-ScheduledTask | Where-Object { $_.State -eq "Ready" } | ForEach-Object {
    [PSCustomObject]@{
        TaskName = $_.TaskName
        Author = $_.Author
        Action = ($_.Actions | ForEach-Object { $_.Execute + " " + $_.Arguments }) -join "; "
    }
}
```

## Secure Configuration Baseline

### Export Security Configuration
```powershell
secedit /export /cfg "C:\secpol.cfg"
```

### Import Security Configuration
```powershell
secedit /configure /db secedit.sdb /cfg "C:\secpol.cfg"
```

### Get Security Configuration
```powershell
secedit /export /cfg "$env:TEMP\secpol.cfg"
Get-Content "$env:TEMP\secpol.cfg"
Remove-Item "$env:TEMP\secpol.cfg"
```

### LGPO Export
```powershell
# Requires LGPO.exe from Microsoft Security Compliance Toolkit
.\LGPO.exe /b "C:\GPOBackup"
```

### LGPO Import
```powershell
.\LGPO.exe /g "C:\GPOBackup"
```
