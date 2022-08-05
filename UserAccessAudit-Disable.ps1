################################################################################################################### 
##
## This script conducts a user access review in Active Directory and disables aged users.
##
## Search and analysis variables for user disablement
$SearchBase = "DC=SERVIT,DC=NET"
$ExcludedAdGroups = @("OU=Managed Service Accounts,DC=SERVIT,DC=NET","OU=Admin Accounts,OU=IT,OU=Users,OU=Kennesaw,OU=ServIT_OU_Internal,DC=SERVIT,DC=NET") #multiple groups allowed but MUST be independent strings separated by comma
$LessThanDaysDisable = 90 # After this many days, user will be disabled in place
$LogExclusions = $false # Set to $false to only capture issues
$Testing = $true # Set to true to report only and take no action
##
## Output options 
$Logging = $true # Set to $false to Disable Logging
$LogFile = "C:\PS\Logs\UserAccessAudit-Disable.csv" # ie. c:\mylog.csv
$SmtpServer = Import-CSV -Path "C:\PS\Settings\SmtpSettings.csv"
$FromEmailAddr = "ServIT Virtual Administrator <noreply@servit.net>"
$ToEmailAddr = "bwinklesky@servit.net","ksaeed@servit.net","ddecaria@servit.net","bcole@servit.net" #multiple addr allowed but MUST be independent strings separated by comma
$TextEncoding = [System.Text.Encoding]::UTF8
##
###################################################################################################################

# System settings and variables

$Date = Get-Date -Format yyyy-MM-dd
$Today = Get-Date
$CountEnabledUsers = 0
$CountExclusionsDisable = 0
$CountDisabled = 0
$ExcludedUsersDisable = @()
$Results = @()

#Start user processing

$StartTime = Get-Date
Write-Host "`r`nAuditing `"$SearchBase`" for inactive users.`r`n"

# Get enabled users with logon dates before $LessThanDaysDisable

$DateCutoffToDisable = [DateTime]::Today.AddDays(-$LessThanDaysDisable)
$EnabledUsers = Get-ADUser -Filter { (Enabled -eq $true) -and (WhenCreated -le $DateCutoffToDisable) } -Searchbase $SearchBase -Properties SamAccountName, Name, WhenCreated, LastLogonDate, Modified, Info | Where-Object { $_.LastLogonDate -le $DateCutoffToDisable }
$CountEnabledUsers = $EnabledUsers.Count

# Get all users from exclusion groups

foreach ($Group in $ExcludedAdGroups) {
    $ExcludedGroup = Get-ADUser -Filter * -SearchBase $Group -Properties SamAccountName, Name, WhenCreated
    foreach ($User in $ExcludedGroup) {
        $ExcludedUsersDisable += New-Object PSObject -Property @{ SamAccountName = $User.SamAccountName; Name = $User.Name; Created = $User.WhenCreated; ExclusionGroup = $Group }
    }
}

foreach ($User in $EnabledUsers) {

    # Compare $EnabledUsers to excluded AD groups

    if ($ExcludedUsersDisable.SamAccountName -contains $User.SamAccountName) {
        $CountExclusionsDisable ++
        if ($LogExclusions -eq $true) {
            $Results += New-Object PSObject -Property @{ Date = $Date; SamAccountName = $User.SamAccountName; Name = $User.Name; Created = $User.WhenCreated; LastLogonDate = $User.LastLogonDate; LastModifiedDate = $User.Modified; InExclusionGroup = "Y"; Issue = "N/A";Action = "N/A" }
        }

    # Check for manual exclusions

    } elseif ($User.Info -contains "<NO-DISABLE>") {
        $CountExclusionsDisable ++
        if ($LogExclusions -eq $true) {
            $Results += New-Object PSObject -Property @{ Date = $Date; SamAccountName = $User.SamAccountName; Name = $User.Name; Created = $User.WhenCreated; LastLogonDate = $User.LastLogonDate; LastModifiedDate = $User.Modified; InExclusionGroup = "N"; Issue = "N/A";Action = "N/A" }
        }
    } else {
        $Results += New-Object PSObject -Property @{ Date = $Date; SamAccountName = $User.SamAccountName; Name = $User.Name; Created = $User.WhenCreated; LastLogonDate = $User.LastLogonDate; LastModifiedDate = $User.Modified; InExclusionGroup = "N"; Issue = "Last logon more than $LessThanDaysDisable days ago"; Action = "Disabled user" }
        $CountDisabled ++
    }
}

# For testing, announce what would have happened

if ($Testing -eq $true) {
    foreach ($User in $Results) {
        if ($User.Action -eq "Disabled user") { Write-Host "Testing Mode:" $User.Name "would be disabled." }
    }

# For execution, take action on aged users

} else {
    foreach ($User in $Results) {
        if ($User.Action -eq "Disabled user") { 

            # Update description of user

            $UserDescription = Get-AdUser -Identity $User.SamAccountName -Properties Description | Select Description
            Set-ADUser -Identity $User.SamAccountName -Description ($UserDescription.Description + ", Disabled by Virtual Administrator - $Date") 
            
            # Disable user
            
            Disable-ADAccount -Identity $User.SamAccountName
            Write-Host $User.Name "was disabled."
        }                       
    }
}

#End User Processing

$EndTime = Get-Date
$TotalTime = ($EndTime-$StartTime).TotalSeconds
$Minutes = "{0:N0}" -f ($TotalTime/60)
$Seconds = "{0:N0}" -f ($TotalTime%60)

Write-Host "`r`nAudit conducted on `"$SearchBase`" in $Minutes minutes and $Seconds seconds.`r`n"

Write-Host "$CountEnabledUsers enabled users audited."
Write-Host "$CountExclusionsDisable user(s) in exclusion groups."
Write-Host "$CountDisabled user(s) disabled."

# Send output

if ($Logging -eq $true) {
    Write-Host "CSV File created at $LogFile.`r`n"
    $Results | Select-Object Date, SamAccountName, Name, Created, LastLogonDate, LastModifiedDate, InExclusionGroup, Issue, Action | Export-CSV -Path $LogFile -NoTypeInformation 
    
    #email the CSV and stats to admin(s) 
    if ($testing -eq $true) {
        $body="<b><i>Testing Mode</i></b><br>"
    } else {
        $body=""
    }

    if ($Results) { 
        $body+= "CSV Attached for $Date<br>"
    } else {
        $body+= "No CSV Attached for $Date - No Results<br>"
    }
    
    $body+="

    Audit conducted on `"$SearchBase`" in $Minutes minutes and $Seconds seconds.<br>
    <br>
    $CountEnabledUsers enabled users audited.<br>
    $CountExclusionsDisable user(s) in exclusion groups.<br>
    $CountDisabled user(s) disabled.<br>
    "
    
    try {
        Send-MailMessage -SmtpServer $SmtpServer.SmtpServer -from $FromEmailAddr -to $ToEmailAddr -subject "User Access Audit - $LessThanDaysDisable Days Inactive" -body $Body -bodyasHTML -Attachments $logfile -priority High -Encoding $TextEncoding -ErrorAction Stop -ErrorVariable err
    } catch {
        Write-Host "Error: Failed to email CSV log to $ToEmailAddr via $SmtpServer.SmtpServer"
    } finally {
        if ($err.Count -eq 0) {
            Write-Host "Audit results emailed to $ToEmailAddr."
        }
    }
}