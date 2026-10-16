from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest


def test_compose_overlay_passes_the_shared_attempt_limit_to_api_and_worker() -> None:
    overlay_path = (
        Path(__file__).resolve().parents[2]
        / "infra"
        / "docker"
        / "compose.inference.yml"
    )
    overlay = overlay_path.read_text(encoding="utf-8")
    service_blocks = {
        name: body
        for name, body in re.findall(
            r"(?ms)^  ([\w-]+):\n(.*?)(?=^  [\w-]+:\n|\Z)", overlay
        )
    }

    for service in ("api", "worker"):
        assert re.search(
            r"(?m)^      DETECTION_MAX_ATTEMPTS: \$\{DETECTION_MAX_ATTEMPTS:-3\}$",
            service_blocks[service],
        ), f"{service} must receive the same host-configured retry cap as provisioning"


def _find_powershell() -> str | None:
    # The lifecycle scripts are plain PowerShell, so pwsh (cross-platform, present
    # on Linux CI runners) works as well as Windows PowerShell 5.1.
    for executable in ("pwsh", "pwsh.exe", "powershell.exe"):
        resolved = shutil.which(executable)
        if resolved is not None:
            return resolved
    return None


def test_local_detection_queue_is_provisioned_with_a_dead_letter_redrive_policy() -> None:
    powershell = _find_powershell()
    if powershell is None:
        pytest.skip("PowerShell (pwsh or Windows PowerShell) is unavailable")

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
    if ($joined -match 's3api get-bucket-lifecycle-configuration') {{
        # Mimic AWS CLI behavior for a bucket without a lifecycle configuration:
        # nonzero exit and a NoSuchLifecycleConfiguration error payload, which the
        # lifecycle script treats as "no current configuration".
        $global:LASTEXITCODE = 1
        return '{{"Error":{{"Code":"NoSuchLifecycleConfiguration"}}}}'
    }}
    if ($joined -match 'exec -T floci sh -c') {{
        return '{{}}'
    }}
    if ($joined -match 's3api put-bucket-lifecycle-configuration') {{
        return '{{}}'
    }}
    if ($joined -match 'sqs set-queue-attributes') {{
        $attributesIndex = [Array]::IndexOf($args, '--attributes')
        $global:capturedAttributes = [string]$args[$attributesIndex + 1]
        return '{{}}'
    }}
    throw "Unexpected mocked Docker invocation: $joined"
}}
# set-staging-lifecycle.ps1 invokes docker.exe with the extension, which bypasses
# a function named only `docker` and would reach the real CLI; mirror the mock.
function docker.exe {{ docker @args }}
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
