from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest


def test_local_detection_queue_is_provisioned_with_a_dead_letter_redrive_policy() -> None:
    powershell = shutil.which("powershell.exe") or (
        r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    )
    if not Path(powershell).is_file():
        pytest.skip("Windows PowerShell is unavailable")

    script_path = (
        Path(__file__).resolve().parents[2]
        / "infra"
        / "docker"
        / "init-local-resources.ps1"
    )
    script_literal = str(script_path).replace("'", "''")
    mock_docker = rf'''
$env:DETECTION_MAX_ATTEMPTS = '7'
$global:queueNames = @()
$global:capturedAttributes = $null
function docker {{
    $global:LASTEXITCODE = 0
    $joined = $args -join ' '
    if ($joined -match 'config --format json') {{
        return '{{"services":{{"floci":{{"environment":{{"S3_BUCKET_NAME":"assets","SQS_QUEUE_NAME":"events","S3_ENDPOINT_URL":"http://floci:4566","SQS_ENDPOINT_URL":"http://floci:4566"}}}}}}}}'
    }}
    if ($joined -match 's3api list-buckets') {{ return '{{"Buckets":[]}}' }}
    if ($joined -match 's3api create-bucket') {{ return '{{}}' }}
    if ($joined -match 'sqs list-queues') {{
        $urls = @($global:queueNames | ForEach-Object {{ "http://localhost:4566/000000000000/$_" }})
        return (@{{ QueueUrls = $urls }} | ConvertTo-Json -Compress)
    }}
    if ($joined -match 'sqs create-queue') {{
        $nameIndex = [Array]::IndexOf($args, '--queue-name')
        $global:queueNames += [string]$args[$nameIndex + 1]
        return '{{}}'
    }}
    if ($joined -match 'sqs get-queue-url') {{
        $nameIndex = [Array]::IndexOf($args, '--queue-name')
        $name = [string]$args[$nameIndex + 1]
        return ('{{"QueueUrl":"http://localhost:4566/000000000000/' + $name + '"}}')
    }}
    if ($joined -match 'sqs get-queue-attributes') {{
        return '{{"Attributes":{{"QueueArn":"arn:aws:sqs:us-east-1:000000000000:roomforge-local-detection-dlq"}}}}'
    }}
    if ($joined -match 'sqs set-queue-attributes') {{
        $attributesIndex = [Array]::IndexOf($args, '--attributes')
        $global:capturedAttributes = [string]$args[$attributesIndex + 1]
        return '{{}}'
    }}
    throw "Unexpected mocked Docker invocation: $joined"
}}
. '{script_literal}'
Write-Output ("CAPTURED-ATTRIBUTES:" + $global:capturedAttributes)
Write-Output ("CAPTURED-QUEUES:" + ($global:queueNames -join ','))
'''
    result = subprocess.run(
        [powershell, "-NoProfile", "-Command", mock_docker],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr

    lines = result.stdout.splitlines()
    attributes_line = next(
        (line.removeprefix("CAPTURED-ATTRIBUTES:") for line in lines
         if line.startswith("CAPTURED-ATTRIBUTES:")),
        "",
    )
    assert attributes_line, "the provisioner must set the detection queue redrive policy"
    attributes = json.loads(attributes_line)
    redrive_policy = json.loads(attributes["RedrivePolicy"])
    assert redrive_policy == {
        "deadLetterTargetArn": "arn:aws:sqs:us-east-1:000000000000:roomforge-local-detection-dlq",
        "maxReceiveCount": "8",
    }

    queues_line = next(
        (line.removeprefix("CAPTURED-QUEUES:") for line in lines
         if line.startswith("CAPTURED-QUEUES:")),
        "",
    )
    assert "roomforge-local-detection" in queues_line
    assert "roomforge-local-detection-dlq" in queues_line
