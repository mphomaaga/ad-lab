# bulk-create-users.ps1
# Creates Active Directory users from a CSV file
# Run on DC01 as a Domain Admin

# ---- Configuration ----
$CsvPath = "C:\Scripts\new-users.csv"
$DefaultPassword = ConvertTo-SecureString "Lab@12345" -AsPlainText -Force
$Domain = "mylab.local"
$LogFile = "C:\Scripts\user-creation-log.txt"

# ---- Department to OU and Group mapping ----
$DepartmentMap = @{
    "IT"         = @{ OU = "OU=IT,DC=mylab,DC=local";         Group = "IT-Staff" }
    "HR"         = @{ OU = "OU=HR,DC=mylab,DC=local";         Group = "HR-Staff" }
    "Finance"    = @{ OU = "OU=Finance,DC=mylab,DC=local";    Group = "Finance-Staff" }
    "Management" = @{ OU = "OU=Management,DC=mylab,DC=local"; Group = "Management-Staff" }
}

# ---- Start logging ----
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"===== User Creation Run: $Timestamp =====" | Out-File -FilePath $LogFile -Append

# ---- Import and process CSV ----
$Users = Import-Csv -Path $CsvPath
$Created = 0
$Skipped = 0
$Failed = 0

foreach ($User in $Users) {

    $First     = $User.FirstName.Trim()
    $Last      = $User.LastName.Trim()
    $Username  = $User.Username.Trim()
    $Dept      = $User.Department.Trim()
    $Title     = $User.JobTitle.Trim()
    $FullName  = "$First $Last"

    # Check if department exists in the mapping
    if (-not $DepartmentMap.ContainsKey($Dept)) {
        $Message = "FAILED: $Username - Unknown department: $Dept"
        Write-Host $Message -ForegroundColor Red
        $Message | Out-File -FilePath $LogFile -Append
        $Failed++
        continue
    }

    $TargetOU = $DepartmentMap[$Dept].OU
    $GroupName = $DepartmentMap[$Dept].Group

    # Check if user already exists
    $Existing = Get-ADUser -Filter "SamAccountName -eq '$Username'" -ErrorAction SilentlyContinue
    if ($Existing) {
        $Message = "SKIPPED: $Username - Already exists in AD"
        Write-Host $Message -ForegroundColor Yellow
        $Message | Out-File -FilePath $LogFile -Append
        $Skipped++
        continue
    }

    # Create the user
    try {
        New-ADUser `
            -Name $FullName `
            -GivenName $First `
            -Surname $Last `
            -SamAccountName $Username `
            -UserPrincipalName "$Username@$Domain" `
            -Path $TargetOU `
            -AccountPassword $DefaultPassword `
            -ChangePasswordAtLogon $true `
            -Enabled $true `
            -Department $Dept `
            -Title $Title `
            -Description "Created by bulk-create-users.ps1"

        # Add to department security group
        Add-ADGroupMember -Identity $GroupName -Members $Username

        $Message = "CREATED: $Username ($FullName) -> $TargetOU -> $GroupName"
        Write-Host $Message -ForegroundColor Green
        $Message | Out-File -FilePath $LogFile -Append
        $Created++
    }
    catch {
        $Message = "FAILED: $Username - $($_.Exception.Message)"
        Write-Host $Message -ForegroundColor Red
        $Message | Out-File -FilePath $LogFile -Append
        $Failed++
    }
}

# ---- Summary ----
$Summary = @"

----- Summary -----
Total processed: $($Users.Count)
Created: $Created
Skipped: $Skipped
Failed: $Failed
--------------------
"@

Write-Host $Summary
$Summary | Out-File -FilePath $LogFile -Append

Write-Host "`nLog saved to $LogFile" -ForegroundColor Cyan
