[CmdletBinding()]
param()

$composeFile = Join-Path -Path $PSScriptRoot -ChildPath 'compose.local.yml'
$envFile = Join-Path -Path $PSScriptRoot -ChildPath 'local-env.example'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI is required to initialize the local Floci resources.'
}

$composeJsonLines = & docker compose --env-file $envFile -f $composeFile config --format json
$composeExitCode = $LASTEXITCODE
if ($composeExitCode -ne 0) {
    throw "Could not read the effective local Compose configuration (exit code $composeExitCode)."
}

try {
    $composeConfig = ($composeJsonLines -join [Environment]::NewLine) | ConvertFrom-Json
}
catch {
    throw "Could not parse the effective local Compose configuration: $($_.Exception.Message)"
}

$flociEnvironment = $composeConfig.services.floci.environment
$bucketName = [string]$flociEnvironment.S3_BUCKET_NAME
$queueName = [string]$flociEnvironment.SQS_QUEUE_NAME
$detectionQueueName = 'roomforge-local-detection'
$detectionDeadLetterQueueName = 'roomforge-local-detection-dlq'
# Keep the queue redrive threshold coupled to the worker's DETECTION_MAX_ATTEMPTS.
# Its unset default matches Settings.from_env() and job_worker.py.
[long]$detectionReceiveCap = 3
if (-not [string]::IsNullOrWhiteSpace($env:DETECTION_MAX_ATTEMPTS)) {
    [long]$configuredReceiveCap = 0
    if (-not [long]::TryParse([string]$env:DETECTION_MAX_ATTEMPTS, [ref]$configuredReceiveCap) -or
        $configuredReceiveCap -lt 1 -or $configuredReceiveCap -ge [int]::MaxValue) {
        throw 'DETECTION_MAX_ATTEMPTS must be a positive integer below Int32.MaxValue.'
    }
    $detectionReceiveCap = $configuredReceiveCap
}
$detectionRedriveReceiveCount = $detectionReceiveCap + 1
$s3Endpoint = [string]$flociEnvironment.S3_ENDPOINT_URL
$sqsEndpoint = [string]$flociEnvironment.SQS_ENDPOINT_URL
if ([string]::IsNullOrWhiteSpace($bucketName) -or
    [string]::IsNullOrWhiteSpace($queueName) -or
    [string]::IsNullOrWhiteSpace($s3Endpoint) -or
    [string]::IsNullOrWhiteSpace($sqsEndpoint)) {
    throw 'The local Compose configuration must define both resource names and both service endpoints.'
}

function Invoke-FlociAws {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][string[]]$AwsArguments,
        [string]$StandardInput
    )

    if ($PSBoundParameters.ContainsKey('StandardInput')) {
        # Windows PowerShell 5.1 strips inner double quotes from native arguments,
        # so JSON values travel through stdin (file:///dev/stdin) instead.
        $output = $StandardInput | & docker compose --env-file $envFile -f $composeFile exec -T floci aws --endpoint-url $Endpoint @AwsArguments
    } else {
        $output = & docker compose --env-file $envFile -f $composeFile exec -T floci aws --endpoint-url $Endpoint @AwsArguments
    }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $operation = $AwsArguments -join ' '
        throw "Floci AWS CLI operation '$operation' failed with exit code $exitCode. The failure is not treated as a missing resource; verify Floci health, local credentials, and endpoint connectivity."
    }

    return ($output -join [Environment]::NewLine)
}

try {
    $bucketListJson = Invoke-FlociAws -Endpoint $s3Endpoint -AwsArguments @('s3api', 'list-buckets', '--output', 'json')
    $bucketList = ConvertFrom-Json -InputObject $bucketListJson
    $queueListJson = Invoke-FlociAws -Endpoint $sqsEndpoint -AwsArguments @('sqs', 'list-queues', '--output', 'json')
    $queueList = ConvertFrom-Json -InputObject $queueListJson
}
catch {
    throw "Could not verify local S3/SQS resources. No missing-resource decision was made: $($_.Exception.Message)"
}

$bucketExists = @($bucketList.Buckets | Where-Object { $_.Name -ceq $bucketName }).Count -gt 0
$plainQueueNames = @($queueName, $detectionDeadLetterQueueName) | Select-Object -Unique

if ($bucketExists) {
    Write-Host "S3 bucket '$bucketName' already exists; leaving it unchanged."
}
else {
    $null = Invoke-FlociAws -Endpoint $s3Endpoint -AwsArguments @('s3api', 'create-bucket', '--bucket', $bucketName, '--output', 'json')
    Write-Host "Created S3 bucket '$bucketName'."
}

# Listing-photo staging objects are the only ones a presigned PUT can (re)create, so they
# live under their own top-level prefix. The API's deletion journal already sweeps them;
# this rule is the backstop that bounds whatever escapes that sweep. S3 lifecycle
# granularity is days, and 1 is the minimum, so it bounds retention instead of closing a
# race. A lifecycle filter can only match a prefix, which is exactly why staging must not
# share a prefix with the confirmed original and its public derivative: those never expire.
& (Join-Path -Path $PSScriptRoot -ChildPath 'set-staging-lifecycle.ps1') `
    -BucketName $bucketName `
    -Endpoint $s3Endpoint `
    -RuleId 'expire-listing-photo-staging' `
    -RulePrefix 'staging/' `
    -ExpirationDays 1

foreach ($targetQueueName in $plainQueueNames) {
    $queueSuffix = "/$targetQueueName"
    $queueExists = @($queueList.QueueUrls | Where-Object {
        ([string]$_).TrimEnd('/').EndsWith($queueSuffix, [StringComparison]::Ordinal)
    }).Count -gt 0

    if ($queueExists) {
        Write-Host "SQS queue '$targetQueueName' already exists; leaving it unchanged."
    }
    else {
        $null = Invoke-FlociAws -Endpoint $sqsEndpoint -AwsArguments @('sqs', 'create-queue', '--queue-name', $targetQueueName, '--output', 'json')
        Write-Host "Created SQS queue '$targetQueueName'."
    }
}

$deadLetterQueueJson = Invoke-FlociAws -Endpoint $sqsEndpoint -AwsArguments @(
    'sqs', 'get-queue-url', '--queue-name', $detectionDeadLetterQueueName, '--output', 'json'
)
$deadLetterQueueUrl = [string](ConvertFrom-Json -InputObject $deadLetterQueueJson).QueueUrl
$deadLetterAttributesJson = Invoke-FlociAws -Endpoint $sqsEndpoint -AwsArguments @(
    'sqs', 'get-queue-attributes', '--queue-url', $deadLetterQueueUrl,
    '--attribute-names', 'QueueArn', '--output', 'json'
)
$deadLetterQueueArn = [string](ConvertFrom-Json -InputObject $deadLetterAttributesJson).Attributes.QueueArn
if ([string]::IsNullOrWhiteSpace($deadLetterQueueArn)) {
    throw "Could not resolve the ARN for detection dead-letter queue '$detectionDeadLetterQueueName'."
}

$updatedQueueListJson = Invoke-FlociAws -Endpoint $sqsEndpoint -AwsArguments @(
    'sqs', 'list-queues', '--output', 'json'
)
$updatedQueueList = ConvertFrom-Json -InputObject $updatedQueueListJson
$detectionQueueSuffix = "/$detectionQueueName"
$detectionQueueExists = @($updatedQueueList.QueueUrls | Where-Object {
    ([string]$_).TrimEnd('/').EndsWith($detectionQueueSuffix, [StringComparison]::Ordinal)
}).Count -gt 0
if (-not $detectionQueueExists) {
    $null = Invoke-FlociAws -Endpoint $sqsEndpoint -AwsArguments @(
        'sqs', 'create-queue', '--queue-name', $detectionQueueName, '--output', 'json'
    )
    Write-Host "Created SQS queue '$detectionQueueName'."
}

$detectionQueueJson = Invoke-FlociAws -Endpoint $sqsEndpoint -AwsArguments @(
    'sqs', 'get-queue-url', '--queue-name', $detectionQueueName, '--output', 'json'
)
$detectionQueueUrl = [string](ConvertFrom-Json -InputObject $detectionQueueJson).QueueUrl
$redrivePolicyJson = [ordered]@{
    deadLetterTargetArn = $deadLetterQueueArn
    maxReceiveCount = [string]$detectionRedriveReceiveCount
} | ConvertTo-Json -Compress
$queueAttributesJson = @{ RedrivePolicy = $redrivePolicyJson } | ConvertTo-Json -Compress
$null = Invoke-FlociAws -Endpoint $sqsEndpoint -AwsArguments @(
    'sqs', 'set-queue-attributes', '--queue-url', $detectionQueueUrl,
    '--attributes', 'file:///dev/stdin', '--output', 'json'
) -StandardInput $queueAttributesJson
Write-Host "Configured SQS redrive for '$detectionQueueName' after $detectionRedriveReceiveCount receives to '$detectionDeadLetterQueueName'."
