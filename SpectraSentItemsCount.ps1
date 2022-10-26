Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline

cls

$UserList = Get-Mailbox -ResultSize Unlimited | Where-Object {($_.PrimarySMTPAddress -like "*spectracf.com*")} #Change primary SMTP to repurpose 
$UserCount = $UserList.Count

$Results = @()
$i = 1

foreach ($User in $UserList) {

$ErrorActionPreference = 'Continue'

$Messages = @()
$Messages += Get-MessageTrace -SenderAddress $User.PrimarySmtpAddress -StartDate "10/24/2022 00:01" -EndDate "10/26/2022 23:59"
$MessageCount = $Messages.Count

$MailboxStats = Get-MailboxStatistics $User.PrimarySmtpAddress 

Write-Progress -activity "Processing $User" -status "$i out of $UserCount completed"

$Results += New-Object PSObject -Property @{ EmailAddress = $User.PrimarySmtpAddress; Name = $User.Name; LastLogon = $MailboxStats.LastLogonTime; MessageCount = $MessageCount; MailboxSize = $MailboxStats.TotalItemSize.Value; ProxyAddresses = $User.EmailAddresses }

$i ++

}

$Results | Export-CSV -Path C:\PS\SpectraSentItemsCount.csv -NoTypeInformation 