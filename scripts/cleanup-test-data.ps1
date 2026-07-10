<#
.SYNOPSIS
    Nuclear cleanup: removes test data left in staging DynamoDB by crashed
    or interrupted pytest runs.

.DESCRIPTION
    Per-test cleanup fixtures handle the happy path. This script handles
    the crash path -- when a test panics or you Ctrl+C halfway through a
    suite. Run it on demand or as a periodic safety sweep.

    What it deletes:
      - Items in staging-UserProfiles where userSub matches one of our
        3 permanent test users
      - Items in staging-UserTokens for those same userSubs
      - As a belt-and-suspenders pass, any UserProfiles row whose
        displayName begins with "test-" (catches orphans from any test
        user past or present)

    What it does NOT delete:
      - The test users themselves (they're permanent)
      - Any data outside the test prefix / test userSub set
      - SSM parameters
      - .env.test

.PARAMETER DryRun
    Show what would be deleted without deleting. Recommended on first run.

.EXAMPLE
    .\cleanup-test-data.ps1 -DryRun

.EXAMPLE
    .\cleanup-test-data.ps1
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$UserPoolId = "us-east-1_zYyPI7xxr",
    [string]$AwsRegion  = "us-east-1",
    [int]$TestUserCount = 3
)

$ErrorActionPreference = "Continue"

function Resolve-TestUserSub {
    param([string]$Email)
    $json = aws cognito-idp admin-get-user `
        --user-pool-id $UserPoolId `
        --username $Email `
        --region $AwsRegion `
        --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARN: could not resolve sub for $Email — skipping" -ForegroundColor Yellow
        return $null
    }
    $obj = $json | ConvertFrom-Json
    $subAttr = $obj.UserAttributes | Where-Object { $_.Name -eq 'sub' } | Select-Object -First 1
    return $subAttr.Value
}

function Remove-DynamoItem {
    param(
        [string]$TableName,
        [hashtable]$Key
    )
    if ($DryRun) {
        Write-Host "  [DRY RUN] would delete from ${TableName}: $($Key | ConvertTo-Json -Compress)" -ForegroundColor DarkYellow
        return
    }
    $keyJson = $Key | ConvertTo-Json -Compress
    aws dynamodb delete-item `
        --table-name $TableName `
        --key $keyJson `
        --region $AwsRegion 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  deleted from ${TableName}: $($Key.Values -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "  FAILED to delete from ${TableName}: $($Key.Values -join ', ')" -ForegroundColor Red
    }
}

# ---- Resolve userSubs for the 3 test users ---------------------------------

Write-Host ""
Write-Host "Resolving test user subs..." -ForegroundColor Cyan

$testSubs = @()
for ($i = 1; $i -le $TestUserCount; $i++) {
    $email = "agent-test-$i@studyspheres-internal.test"
    $sub = Resolve-TestUserSub -Email $email
    if ($sub) {
        Write-Host "  $email -> $sub"
        $testSubs += $sub
    }
}

if ($testSubs.Count -eq 0) {
    Write-Host "No test users resolved. Has create-test-users.ps1 been run?" -ForegroundColor Red
    exit 1
}

# ---- Sweep 1: Delete UserProfiles rows for known test userSubs -------------

Write-Host ""
Write-Host "Sweep 1: staging-UserProfiles by userSub..." -ForegroundColor Cyan

foreach ($sub in $testSubs) {
    $key = @{ userSub = @{ S = $sub } }
    Remove-DynamoItem -TableName "staging-UserProfiles" -Key $key
}

# ---- Sweep 2: Delete UserTokens rows for known test userSubs ---------------

Write-Host ""
Write-Host "Sweep 2: staging-UserTokens by userSub..." -ForegroundColor Cyan

foreach ($sub in $testSubs) {
    $key = @{ userSub = @{ S = $sub } }
    Remove-DynamoItem -TableName "staging-UserTokens" -Key $key
}

# ---- Sweep 3: Find orphan UserProfiles with test- displayName prefix -------
#
# This catches rows that may have been created with a different userSub
# (e.g., during exploratory testing before the permanent test users existed)
# and never cleaned up.

Write-Host ""
Write-Host "Sweep 3: scanning staging-UserProfiles for orphan test- displayNames..." -ForegroundColor Cyan

$scanResult = aws dynamodb scan `
    --table-name "staging-UserProfiles" `
    --filter-expression "begins_with(displayName, :prefix)" `
    --expression-attribute-values '{\":prefix\":{\"S\":\"test-\"}}' `
    --projection-expression "userSub, displayName" `
    --region $AwsRegion `
    --output json 2>&1

if ($LASTEXITCODE -eq 0) {
    $items = ($scanResult | ConvertFrom-Json).Items
    if ($items.Count -eq 0) {
        Write-Host "  no orphans found" -ForegroundColor Green
    } else {
        Write-Host "  found $($items.Count) orphan rows" -ForegroundColor Yellow
        foreach ($item in $items) {
            $orphanSub = $item.userSub.S
            $orphanName = $item.displayName.S
            # Only delete if this row wasn't already covered by sweep 1.
            if ($orphanSub -notin $testSubs) {
                Write-Host "  orphan: $orphanName (sub=$orphanSub)" -ForegroundColor Yellow
                $key = @{ userSub = @{ S = $orphanSub } }
                Remove-DynamoItem -TableName "staging-UserProfiles" -Key $key
            }
        }
    }
} else {
    Write-Host "  scan failed: $scanResult" -ForegroundColor Red
}

# ---- Summary ---------------------------------------------------------------

Write-Host ""
if ($DryRun) {
    Write-Host "===== Dry run complete (nothing was deleted) =====" -ForegroundColor Cyan
    Write-Host "Re-run without -DryRun to actually delete." -ForegroundColor White
} else {
    Write-Host "===== Cleanup complete =====" -ForegroundColor Green
}
