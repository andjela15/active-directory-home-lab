<#
.SYNOPSIS
    Bulk-creates Active Directory users from a CSV file and adds them to
    department-based security groups.

.DESCRIPTION
    - Creates the target OU if it does not exist
    - Reads users from a CSV file (FirstName, LastName, Logon, Department)
    - Skips users that already exist
    - Creates a global security group per department (if missing)
    - Adds each new user to their department group
    - Forces a password change at first logon

.PARAMETER CsvPath
    Path to the CSV file with user data.

.PARAMETER OUName
    Name of the organizational unit where users will be created.

.EXAMPLE
    .\Create-UsersFromCSV.ps1 -CsvPath "C:\Scripts\users.csv" -OUName "Zaposleni"
#>

param(
    [string]$CsvPath = "C:\Scripts\users.csv",
    [string]$OUName  = "Zaposleni"
)

Import-Module ActiveDirectory

# The initial password is entered at runtime and never stored in the script
$password = Read-Host -Prompt "Enter initial password for new users" -AsSecureString

$domainDN = (Get-ADDomain).DistinguishedName
$dnsRoot  = (Get-ADDomain).DNSRoot
$ouPath   = "OU=$OUName,$domainDN"

# Create the OU if it does not exist
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$OUName'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name $OUName -Path $domainDN -ProtectedFromAccidentalDeletion $true
    Write-Host "OU '$OUName' created." -ForegroundColor Green
}

# Check that the CSV file exists
if (-not (Test-Path $CsvPath)) {
    Write-Host "ERROR: CSV file not found at path: $CsvPath" -ForegroundColor Red
    return
}

$users   = Import-Csv -Path $CsvPath
$created = 0
$skipped = 0

foreach ($u in $users) {
    $samAccountName = $u.Logon

    # Skip users that already exist
    if (Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -ErrorAction SilentlyContinue) {
        Write-Host "Skipped (already exists): $samAccountName" -ForegroundColor Yellow
        $skipped++
        continue
    }

    # Create the user account
    New-ADUser -Name "$($u.FirstName) $($u.LastName)" `
        -GivenName $u.FirstName `
        -Surname $u.LastName `
        -SamAccountName $samAccountName `
        -UserPrincipalName "$samAccountName@$dnsRoot" `
        -Path $ouPath `
        -AccountPassword $password `
        -Enabled $true `
        -ChangePasswordAtLogon $true `
        -Department $u.Department

    Write-Host "Created: $($u.FirstName) $($u.LastName) ($samAccountName) - Department: $($u.Department)" -ForegroundColor Green
    $created++

    # Create the department group if it does not exist, then add the user
    $groupName = "$($u.Department)-Grupa"
    if (-not (Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $groupName -GroupScope Global -GroupCategory Security -Path $ouPath
        Write-Host "  -> Group '$groupName' created." -ForegroundColor Cyan
    }
    Add-ADGroupMember -Identity $groupName -Members $samAccountName
}
Write-Host "`n=== Done ===" -ForegroundColor Magenta
Write-Host "Created: $created | Skipped (already existed): $skipped"
Write-Host "Created: $created | Skipped (already existed): $skipped"
