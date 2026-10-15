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
        [Parameter(Mandatory = $true)][string[]]$AwsArguments
    )

    $output = & docker compose --env-file $envFile -f $composeFile exec -T floci aws --endpoint-url $Endpoint @AwsArguments
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
    $queueListJson = Invoke-FlociAws -Endpoint $sqsEndpoint -AwsArguments @('sqs', 'list-queues', '--queue-name-prefix', $queueName, '--output', 'json')
    $queueList = ConvertFrom-Json -InputObject $queueListJson
}
catch {
    throw "Could not verify local S3/SQS resources. No missing-resource decision was made: $($_.Exception.Message)"
}

$bucketExists = @($bucketList.Buckets | Where-Object { $_.Name -ceq $bucketName }).Count -gt 0
$queueSuffix = "/$queueName"
$queueExists = @($queueList.QueueUrls | Where-Object {
    ([string]$_).TrimEnd('/').EndsWith($queueSuffix, [StringComparison]::Ordinal)
}).Count -gt 0

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
$stagingLifecyclePath = '/tmp/roomforge-staging-lifecycle.json'
$stagingLifecycleJson = @'
{
  "Rules": [
    {
      "ID": "expire-listing-photo-staging",
      "Status": "Enabled",
      "Filter": { "Prefix": "staging/" },
      "Expiration": { "Days": 1 }
    }
  ]
}
'@
$stagingLifecycleJson | & docker compose --env-file $envFile -f $composeFile exec -T floci sh -c "cat > $stagingLifecyclePath"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not write the S3 lifecycle configuration inside the Floci container.'
}
$null = Invoke-FlociAws -Endpoint $s3Endpoint -AwsArguments @('s3api', 'put-bucket-lifecycle-configuration', '--bucket', $bucketName, '--lifecycle-configuration', "file://$stagingLifecyclePath", '--output', 'json')
Write-Host "Applied the staging lifecycle rule to bucket '$bucketName' (expire staging/ after 1 day)."

if ($queueExists) {
    Write-Host "SQS queue '$queueName' already exists; leaving it unchanged."
}
else {
    $null = Invoke-FlociAws -Endpoint $sqsEndpoint -AwsArguments @('sqs', 'create-queue', '--queue-name', $queueName, '--output', 'json')
    Write-Host "Created SQS queue '$queueName'."
}
