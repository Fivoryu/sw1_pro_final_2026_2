[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BucketName,
    [Parameter(Mandatory = $true)][string]$Endpoint,
    [Parameter(Mandatory = $true)][string]$RuleId,
    [Parameter(Mandatory = $true)][string]$RulePrefix,
    [Parameter(Mandatory = $true)][ValidateRange(1, 36500)][int]$ExpirationDays,
    [switch]$DryRun,
    [AllowEmptyString()][string]$CurrentConfigurationJson
)

function Merge-StagingLifecycleConfiguration {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$CurrentConfiguration,
        [Parameter(Mandatory = $true)][object]$StagingRule
    )

    $existingRules = @()
    if ($null -ne $CurrentConfiguration -and $null -ne $CurrentConfiguration.Rules) {
        $existingRules = @($CurrentConfiguration.Rules)
    }

    $mergedRules = New-Object 'System.Collections.Generic.List[object]'
    $stagingRuleAdded = $false
    foreach ($existingRule in $existingRules) {
        if ($null -ne $existingRule -and [string]$existingRule.ID -ceq [string]$StagingRule.ID) {
            if (-not $stagingRuleAdded) {
                $mergedRules.Add($StagingRule)
                $stagingRuleAdded = $true
            }
            continue
        }

        $mergedRules.Add($existingRule)
    }

    if (-not $stagingRuleAdded) {
        $mergedRules.Add($StagingRule)
    }

    $writeConfiguration = [ordered]@{
        Rules = @($mergedRules.ToArray())
    }
    return ConvertTo-Json -InputObject $writeConfiguration -Depth 100 -Compress
}

function Invoke-FlociAws {
    param(
        [Parameter(Mandatory = $true)][string]$EndpointUrl,
        [Parameter(Mandatory = $true)][string[]]$AwsArguments
    )

    $output = & $dockerCommand compose --env-file $envFile -f $composeFile exec -T floci aws --endpoint-url $EndpointUrl @AwsArguments 2>&1
    $exitCode = $LASTEXITCODE
    $outputText = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $outputText
    }
}

$composeFile = Join-Path -Path $PSScriptRoot -ChildPath 'compose.local.yml'
$envFile = Join-Path -Path $PSScriptRoot -ChildPath 'local-env.example'
# Windows ships docker.exe; pwsh on Linux only exposes plain docker. Resolve once
# so the script runs identically under Windows PowerShell and cross-platform pwsh.
$dockerCommand = $null
foreach ($dockerCandidate in @('docker.exe', 'docker')) {
    $dockerCommand = Get-Command $dockerCandidate -ErrorAction SilentlyContinue
    if ($null -ne $dockerCommand) {
        break
    }
}
if ($null -eq $dockerCommand -and (-not $DryRun -or -not $PSBoundParameters.ContainsKey('CurrentConfigurationJson'))) {
    throw 'Docker CLI (docker or docker.exe) is required to read or update the local Floci lifecycle configuration.'
}

if ($PSBoundParameters.ContainsKey('CurrentConfigurationJson')) {
    if (-not $DryRun) {
        throw '-CurrentConfigurationJson is available only together with -DryRun.'
    }
    if ([string]::IsNullOrWhiteSpace($CurrentConfigurationJson)) {
        $currentConfiguration = $null
    }
    else {
        try {
            $currentConfiguration = ConvertFrom-Json -InputObject $CurrentConfigurationJson
        }
        catch {
            throw "Could not parse -CurrentConfigurationJson: $($_.Exception.Message)"
        }
    }
}
else {
    $getResult = Invoke-FlociAws -EndpointUrl $Endpoint -AwsArguments @(
        's3api',
        'get-bucket-lifecycle-configuration',
        '--bucket',
        $BucketName,
        '--output',
        'json'
    )

    if ($getResult.ExitCode -eq 0) {
        try {
            $currentConfiguration = ConvertFrom-Json -InputObject $getResult.Output
        }
        catch {
            throw "Could not parse the current bucket lifecycle configuration: $($_.Exception.Message)"
        }
    }
    elseif ($getResult.Output -match '(?i)NoSuchLifecycleConfiguration') {
        $currentConfiguration = $null
    }
    else {
        throw "Floci could not read lifecycle configuration for bucket '$BucketName' (exit code $($getResult.ExitCode)): $($getResult.Output)"
    }
}

$stagingRule = [ordered]@{
    ID         = $RuleId
    Status     = 'Enabled'
    Filter     = [ordered]@{ Prefix = $RulePrefix }
    Expiration = [ordered]@{ Days = $ExpirationDays }
}
$mergedConfigurationJson = Merge-StagingLifecycleConfiguration `
    -CurrentConfiguration $currentConfiguration `
    -StagingRule $stagingRule

if ($DryRun) {
    Write-Output $mergedConfigurationJson
    return
}

$lifecycleConfigurationPath = '/tmp/roomforge-staging-lifecycle.json'
$fileWriteOutput = $mergedConfigurationJson | & $dockerCommand compose --env-file $envFile -f $composeFile exec -T floci sh -c "cat > $lifecycleConfigurationPath" 2>&1
$fileWriteExitCode = $LASTEXITCODE
if ($fileWriteExitCode -ne 0) {
    $fileWriteText = ($fileWriteOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    throw "Could not write the merged lifecycle configuration inside the Floci container (exit code $fileWriteExitCode): $fileWriteText"
}

$putResult = Invoke-FlociAws -EndpointUrl $Endpoint -AwsArguments @(
    's3api',
    'put-bucket-lifecycle-configuration',
    '--bucket',
    $BucketName,
    '--lifecycle-configuration',
    "file://$lifecycleConfigurationPath",
    '--output',
    'json'
)
if ($putResult.ExitCode -ne 0) {
    throw "Floci could not write lifecycle configuration for bucket '$BucketName' (exit code $($putResult.ExitCode)): $($putResult.Output)"
}

Write-Host "Applied the staging lifecycle rule to bucket '$BucketName' (expire $RulePrefix after $ExpirationDays day(s)); unrelated lifecycle rules were preserved."
