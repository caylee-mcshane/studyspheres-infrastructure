<#
.SYNOPSIS
    One-time bootstrap: creates permanent test users for pytest and writes
    credentials to backend\.env.test and SSM Parameter Store.

.DESCRIPTION
    Creates N test users (default 3) in the staging Cognito User Pool with
    pre-confirmed status and verified emails. Suppresses the email-verification
    flow because @studyspheres-internal.test addresses cannot receive mail
    (the .test TLD is RFC 2606 reserved).

    Writes credentials to two places to mirror the rest of your env handling:
      - C:\studyspheres\backend\.env.test  (gitignored, for local pytest)
      - SSM Parameter Store under /studyspheres/test/* (for future CI use)

    Idempotent: if a user already exists, creation is skipped and that user's
    .env.test entry is left alone. To rotate passwords on existing users,
    use -RotatePasswords.

.PARAMETER UserCount
    Number of test users to create (default 3).

.PARAMETER RotatePasswords
    If users already exist, rotate their passwords instead of skipping.

.EXAMPLE
    .\create-test-users.ps1

.EXAMPLE
    .\create-test-users.ps1 -RotatePasswords

.NOTES
    Run from anywhere — paths are absolute. Requires AWS CLI configured with
    the same profile/credentials you use for terraform.
#>
[CmdletBinding()]
param(
    [int]$UserCount = 3,
    [switch]$RotatePasswords,
    [string]$UserPoolId = "us-east-1_zYyPI7xxr",
    [string]$AwsRegion = "us-east-1",
    [string]$BackendPath = "C:\studyspheres\backend",
    [string]$InfraPath   = "C:\studyspheres\studyspheres-infrastructure"
)

$ErrorActionPreference = "Continue"

# ---- Verify .env.test is gitignored before writing any secrets to it --------

$envTestPath   = Join-Path $BackendPath ".env.test"
$gitignorePath = Join-Path $BackendPath ".gitignore"

if (-not (Test-Path $gitignorePath)) {
    throw "No .gitignore at $gitignorePath. Refusing to write secrets without one."
}

$gitignoreContent = Get-Content $gitignorePath -Raw
$envTestIgnored = $gitignoreContent -match "(?m)^\s*\.env\.test\s*$" `
               -or $gitignoreContent -match "(?m)^\s*\.env\*\s*$" `
               -or $gitignoreContent -match "(?m)^\s*\.env\.\*\s*$"

if (-not $envTestIgnored) {
    Write-Host ""
    Write-Host "FAIL: .env.test is not in $gitignorePath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Add this line to .gitignore, commit it, then re-run:" -ForegroundColor Yellow
    Write-Host "    .env.test" -ForegroundColor Yellow
    Write-Host ""
    throw "Refusing to write credentials to a non-gitignored file."
}

Write-Host "OK: .env.test is gitignored" -ForegroundColor Green

# ---- Read test client ID from terraform output -----------------------------

Write-Host "Reading test client ID from terraform output..." -ForegroundColor Cyan
Push-Location (Join-Path $InfraPath "environments\staging")
try {
    $testClientId = (terraform output -raw cognito_test_client_id).Trim()
} finally {
    Pop-Location
}

if (-not $testClientId -or $testClientId.Length -lt 10) {
    throw "Could not read cognito_test_client_id from terraform. Did the apply succeed?"
}
Write-Host "OK: Test client ID = $testClientId" -ForegroundColor Green

# ---- Helpers ---------------------------------------------------------------

function New-StrongPassword {
    # 24 chars total, guaranteed to satisfy default Cognito policy:
    # at least one each of uppercase, lowercase, digit, special.
    $upper   = -join (1..6 | ForEach-Object { [char](Get-Random -Min 65 -Max 91) })
    $lower   = -join (1..6 | ForEach-Object { [char](Get-Random -Min 97 -Max 123) })
    $digit   = -join (1..6 | ForEach-Object { [char](Get-Random -Min 48 -Max 58) })
    $specials = '!@#$%^&*-_+='
    $special = -join (1..6 | ForEach-Object { $specials[(Get-Random -Min 0 -Max $specials.Length)] })
    $combined = ($upper + $lower + $digit + $special).ToCharArray()
    -join ($combined | Get-Random -Count $combined.Length)
}

function Test-CognitoUserExists {
    param([string]$Email)
    aws cognito-idp admin-get-user `
        --user-pool-id $UserPoolId `
        --username $Email `
        --region $AwsRegion 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# ---- Create or rotate each user --------------------------------------------

$users = @()

for ($i = 1; $i -le $UserCount; $i++) {
    $email = "agent-test-$i@studyspheres-internal.test"
    Write-Host ""
    Write-Host "--- Test user ${i}: $email ---" -ForegroundColor Cyan

    $exists = Test-CognitoUserExists -Email $email

    if ($exists -and -not $RotatePasswords) {
        Write-Host "  Already exists. Skipping (pass -RotatePasswords to rotate)." -ForegroundColor Yellow
        Write-Host "  This user's .env.test entry will be preserved." -ForegroundColor Yellow
        $users += [PSCustomObject]@{
            Index = $i; Email = $email; Password = $null; Action = "skipped"
        }
        continue
    }

    $password = New-StrongPassword

    if (-not $exists) {
        Write-Host "  Creating user (suppressing email)..." -ForegroundColor Cyan
        aws cognito-idp admin-create-user `
            --user-pool-id $UserPoolId `
            --username $email `
            --user-attributes "Name=email,Value=$email" "Name=email_verified,Value=true" `
            --temporary-password $password `
            --message-action SUPPRESS `
            --region $AwsRegion `
            --output json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to create $email" }
        Write-Host "  Created." -ForegroundColor Green
    } else {
        Write-Host "  Exists; rotating password..." -ForegroundColor Yellow
    }

    Write-Host "  Setting permanent password..." -ForegroundColor Cyan
    aws cognito-idp admin-set-user-password `
        --user-pool-id $UserPoolId `
        --username $email `
        --password $password `
        --permanent `
        --region $AwsRegion | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to set password for $email" }
    Write-Host "  Password set (permanent, no FORCE_CHANGE_PASSWORD)." -ForegroundColor Green

    $users += [PSCustomObject]@{
        Index = $i; Email = $email; Password = $password
        Action = if ($exists) { "rotated" } else { "created" }
    }
}

# ---- Write .env.test --------------------------------------------------------

$activeUsers = $users | Where-Object { $null -ne $_.Password }

if ($activeUsers.Count -gt 0) {
    Write-Host ""
    Write-Host "--- Writing $envTestPath ---" -ForegroundColor Cyan

    $envContent = @"
# StudySpheres test credentials -- DO NOT COMMIT
# Generated by scripts/create-test-users.ps1 on $(Get-Date -Format "yyyy-MM-dd HH:mm")
# Used by pytest to obtain Cognito ID tokens for integration tests.

AWS_REGION=$AwsRegion
COGNITO_POOL_ID=$UserPoolId
COGNITO_TEST_CLIENT_ID=$testClientId

"@

    foreach ($user in $activeUsers) {
        $envContent += "TEST_USER_$($user.Index)_EMAIL=$($user.Email)`n"
        $envContent += "TEST_USER_$($user.Index)_PASSWORD=$($user.Password)`n"
        $envContent += "`n"
    }

    Set-Content -Path $envTestPath -Value $envContent -NoNewline
    Write-Host "  Written. (gitignored)" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "All users skipped. .env.test not modified." -ForegroundColor Yellow
}

# ---- Mirror to SSM Parameter Store -----------------------------------------

Write-Host ""
Write-Host "--- Writing SSM parameters under /studyspheres/test/ ---" -ForegroundColor Cyan

aws ssm put-parameter `
    --name "/studyspheres/test/cognito_test_client_id" `
    --value $testClientId `
    --type "String" `
    --overwrite `
    --region $AwsRegion | Out-Null
Write-Host "  /studyspheres/test/cognito_test_client_id" -ForegroundColor Green

foreach ($user in $activeUsers) {
    aws ssm put-parameter `
        --name "/studyspheres/test/user_$($user.Index)_email" `
        --value $user.Email `
        --type "String" `
        --overwrite `
        --region $AwsRegion | Out-Null
    Write-Host "  /studyspheres/test/user_$($user.Index)_email" -ForegroundColor Green

    aws ssm put-parameter `
        --name "/studyspheres/test/user_$($user.Index)_password" `
        --value $user.Password `
        --type "SecureString" `
        --overwrite `
        --region $AwsRegion | Out-Null
    Write-Host "  /studyspheres/test/user_$($user.Index)_password (SecureString)" -ForegroundColor Green
}

# ---- Verify auth actually works -- catches setup bugs before pytest does ---

Write-Host ""
Write-Host "--- Verifying authentication for each user ---" -ForegroundColor Cyan

foreach ($user in $activeUsers) {
    Write-Host -NoNewline "  $($user.Email)... "

    $authResult = aws cognito-idp initiate-auth `
        --client-id $testClientId `
        --auth-flow USER_PASSWORD_AUTH `
        --auth-parameters "USERNAME=$($user.Email),PASSWORD=$($user.Password)" `
        --region $AwsRegion `
        --output json 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK (token received)" -ForegroundColor Green
    } else {
        Write-Host "FAIL" -ForegroundColor Red
        Write-Host "  $authResult" -ForegroundColor Red
        throw "Authentication test failed for $($user.Email)"
    }
}

# ---- Summary ----------------------------------------------------------------

Write-Host ""
Write-Host "===== Setup complete =====" -ForegroundColor Green
Write-Host ""
Write-Host "Test users:" -ForegroundColor White
foreach ($user in $users) {
    $colour = switch ($user.Action) {
        "created" { "Green" }
        "rotated" { "Yellow" }
        "skipped" { "Gray" }
    }
    Write-Host "  $($user.Email) -- $($user.Action)" -ForegroundColor $colour
}
Write-Host ""
Write-Host "Credentials written to:" -ForegroundColor White
Write-Host "  $envTestPath"
Write-Host "  SSM /studyspheres/test/*"
Write-Host ""
Write-Host "Next: pytest fixtures in tests/conftest.py will read these for integration tests." -ForegroundColor Cyan
