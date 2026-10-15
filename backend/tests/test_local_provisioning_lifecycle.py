from __future__ import annotations

import json
import shutil
import subprocess
import uuid
from pathlib import Path
from typing import Any

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
LIFECYCLE_SCRIPT = REPOSITORY_ROOT / "infra" / "docker" / "set-staging-lifecycle.ps1"
COMPOSE_FILE = "infra/docker/compose.local.yml"
BUCKET_NAME = "roomforge-local-assets"
ENDPOINT = "http://floci:4566"
RULE_ID = "expire-listing-photo-staging"
RULE_PREFIX = "staging/"
EXPIRATION_DAYS = 1


def _find_powershell() -> str | None:
    for executable in ("pwsh", "pwsh.exe", "powershell.exe"):
        resolved = shutil.which(executable)
        if resolved is not None:
            return resolved
    return None


def _expected_staging_rule() -> dict[str, Any]:
    return {
        "ID": RULE_ID,
        "Status": "Enabled",
        "Filter": {"Prefix": RULE_PREFIX},
        "Expiration": {"Days": EXPIRATION_DAYS},
    }


def _run_dry_run(
    powershell: str,
    current_configuration: dict[str, Any] | None,
) -> dict[str, Any]:
    completed = subprocess.run(
        [
            powershell,
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(LIFECYCLE_SCRIPT),
            "-BucketName",
            BUCKET_NAME,
            "-Endpoint",
            ENDPOINT,
            "-RuleId",
            RULE_ID,
            "-RulePrefix",
            RULE_PREFIX,
            "-ExpirationDays",
            str(EXPIRATION_DAYS),
            "-DryRun",
            "-CurrentConfigurationJson",
            json.dumps(current_configuration),
        ],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        check=False,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    return json.loads(completed.stdout)


def test_dry_run_adds_rule_when_lifecycle_configuration_is_missing() -> None:
    powershell = _find_powershell()
    if powershell is None:
        pytest.skip("PowerShell is unavailable; this test invokes the lifecycle script with -DryRun.")

    merged = _run_dry_run(powershell, None)

    assert merged == {"Rules": [_expected_staging_rule()]}


def test_dry_run_discards_read_only_top_level_lifecycle_fields() -> None:
    powershell = _find_powershell()
    if powershell is None:
        pytest.skip("PowerShell is unavailable; this test invokes the lifecycle script with -DryRun.")

    merged = _run_dry_run(
        powershell,
        {
            "TransitionDefaultMinimumObjectSize": "all_storage_classes_128K",
            "Rules": [],
        },
    )

    assert merged == {"Rules": [_expected_staging_rule()]}


def test_dry_run_preserves_unrelated_rules() -> None:
    powershell = _find_powershell()
    if powershell is None:
        pytest.skip("PowerShell is unavailable; this test invokes the lifecycle script with -DryRun.")

    foreign_rule: dict[str, Any] = {
        "ID": "keep-existing-rule",
        "Status": "Enabled",
        "Filter": {"Prefix": "other/"},
        "Expiration": {"Days": 7},
    }
    merged = _run_dry_run(powershell, {"Rules": [foreign_rule]})

    assert merged == {"Rules": [foreign_rule, _expected_staging_rule()]}


def test_dry_run_replaces_our_rule_by_id_without_duplicates() -> None:
    powershell = _find_powershell()
    if powershell is None:
        pytest.skip("PowerShell is unavailable; this test invokes the lifecycle script with -DryRun.")

    old_staging_rule: dict[str, Any] = {
        "ID": RULE_ID,
        "Status": "Disabled",
        "Filter": {"Prefix": "old-staging/"},
        "Expiration": {"Days": 30},
    }
    foreign_rule: dict[str, Any] = {
        "ID": "keep-existing-rule",
        "Status": "Enabled",
        "Filter": {"Prefix": "other/"},
        "Expiration": {"Days": 7},
    }
    merged = _run_dry_run(
        powershell,
        {"Rules": [old_staging_rule, foreign_rule, old_staging_rule]},
    )

    assert merged == {"Rules": [_expected_staging_rule(), foreign_rule]}
    assert sum(rule["ID"] == RULE_ID for rule in merged["Rules"]) == 1


def _run_floci_aws(
    docker_executable: str,
    *aws_arguments: str,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            docker_executable,
            "compose",
            "-f",
            COMPOSE_FILE,
            "exec",
            "-T",
            "floci",
            "aws",
            "--endpoint-url",
            ENDPOINT,
            *aws_arguments,
        ],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        check=False,
        text=True,
        timeout=45,
    )


def _get_lifecycle_configuration(
    docker_executable: str,
) -> dict[str, Any] | None:
    completed = _run_floci_aws(
        docker_executable,
        "s3api",
        "get-bucket-lifecycle-configuration",
        "--bucket",
        BUCKET_NAME,
        "--output",
        "json",
    )
    if completed.returncode == 0:
        return json.loads(completed.stdout)
    if "NoSuchLifecycleConfiguration" in completed.stdout + completed.stderr:
        return None
    raise AssertionError(
        f"Could not get lifecycle configuration (exit {completed.returncode}): "
        f"{completed.stdout}{completed.stderr}"
    )


def _put_lifecycle_rules(docker_executable: str, rules: list[dict[str, Any]]) -> None:
    completed = _run_floci_aws(
        docker_executable,
        "s3api",
        "put-bucket-lifecycle-configuration",
        "--bucket",
        BUCKET_NAME,
        "--lifecycle-configuration",
        json.dumps({"Rules": rules}, separators=(",", ":")),
        "--output",
        "json",
    )
    assert completed.returncode == 0, (
        f"Could not put lifecycle rules (exit {completed.returncode}): "
        f"{completed.stdout}{completed.stderr}"
    )


def test_floci_provisioning_preserves_an_unrelated_lifecycle_rule() -> None:
    pwsh = shutil.which("pwsh") or shutil.which("pwsh.exe")
    if pwsh is None:
        pytest.skip("pwsh is unavailable; Windows PowerShell is not used for the Floci integration test.")

    docker_executable = shutil.which("docker.exe")
    if docker_executable is None:
        pytest.skip("docker.exe is unavailable; Floci cannot be queried by this integration test.")

    bucket_list = _run_floci_aws(docker_executable, "s3api", "list-buckets", "--output", "json")
    if bucket_list.returncode != 0:
        pytest.skip(
            "Floci is unavailable through the local Compose service: "
            f"{bucket_list.stderr.strip() or bucket_list.stdout.strip()}"
        )
    bucket_names = {bucket["Name"] for bucket in json.loads(bucket_list.stdout).get("Buckets", [])}
    if BUCKET_NAME not in bucket_names:
        pytest.skip(f"Floci is available, but bucket {BUCKET_NAME!r} has not been provisioned.")

    original_configuration = _get_lifecycle_configuration(docker_executable)
    original_rules = [] if original_configuration is None else original_configuration.get("Rules", [])
    test_rule_id = f"test-preserve-lifecycle-{uuid.uuid4().hex}"
    test_rule: dict[str, Any] = {
        "ID": test_rule_id,
        "Status": "Enabled",
        "Filter": {"Prefix": "test-preserve/"},
        "Expiration": {"Days": 2},
    }

    try:
        _put_lifecycle_rules(docker_executable, [*original_rules, test_rule])
        completed = subprocess.run(
            [
                pwsh,
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-File",
                str(LIFECYCLE_SCRIPT),
                "-BucketName",
                BUCKET_NAME,
                "-Endpoint",
                ENDPOINT,
                "-RuleId",
                RULE_ID,
                "-RulePrefix",
                RULE_PREFIX,
                "-ExpirationDays",
                str(EXPIRATION_DAYS),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            check=False,
            text=True,
            timeout=60,
        )
        assert completed.returncode == 0, (
            f"Lifecycle script failed (exit {completed.returncode}): "
            f"{completed.stdout}{completed.stderr}"
        )

        final_configuration = _get_lifecycle_configuration(docker_executable)
        assert final_configuration is not None
        final_rules = final_configuration.get("Rules", [])
        rules_by_id = {rule["ID"]: rule for rule in final_rules}
        assert test_rule_id in rules_by_id
        assert rules_by_id[test_rule_id] == test_rule
        assert rules_by_id[RULE_ID] == _expected_staging_rule()
    finally:
        current_configuration = _get_lifecycle_configuration(docker_executable)
        current_rules = [] if current_configuration is None else current_configuration.get("Rules", [])
        remaining_rules = [rule for rule in current_rules if rule.get("ID") != test_rule_id]
        remaining_ids = {rule["ID"] for rule in remaining_rules}
        remaining_rules.extend(rule for rule in original_rules if rule["ID"] not in remaining_ids)
        if len(remaining_rules) != len(current_rules):
            if remaining_rules:
                _put_lifecycle_rules(docker_executable, remaining_rules)
            else:
                deleted = _run_floci_aws(
                    docker_executable,
                    "s3api",
                    "delete-bucket-lifecycle",
                    "--bucket",
                    BUCKET_NAME,
                )
                assert deleted.returncode == 0, (
                    f"Could not remove the test-only lifecycle configuration "
                    f"(exit {deleted.returncode}): {deleted.stdout}{deleted.stderr}"
                )
