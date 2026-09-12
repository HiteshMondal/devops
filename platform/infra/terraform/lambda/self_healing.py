"""
platform/infra/terraform/lambda/self_healing.py
--------------------------------------------------------------------------
Self-healing remediation Lambda for the AWS stack.

STANDALONE BY DESIGN: this file has no imports from anywhere else in the
repo, and no third-party dependencies beyond boto3 (already present in
the Lambda Python runtime). It is packaged directly by Terraform
(archive_file data source in self_healing.tf) — no separate build step,
zip script, or CI job required. `terraform apply` alone is enough.

Triggered by CloudWatch Alarms (via SNS) for two conditions:
  1. EKS worker node ASG has an unhealthy EC2 instance
     -> terminate the instance; the Auto Scaling Group replaces it
        automatically (self-healing via replacement, not in-place fix).
  2. RDS instance CloudWatch alarm (e.g. status check failed)
     -> reboot the RDS instance.

Environment variables (set by Terraform):
  ASG_NAME     - name of the EKS worker node Auto Scaling Group
  DB_INSTANCE_IDENTIFIER - RDS instance identifier
"""

from __future__ import annotations

import json
import os

import boto3

autoscaling = boto3.client("autoscaling")
ec2 = boto3.client("ec2")
rds = boto3.client("rds")

ASG_NAME = os.environ.get("ASG_NAME", "")
DB_INSTANCE_IDENTIFIER = os.environ.get("DB_INSTANCE_IDENTIFIER", "")


def _parse_sns_message(record: dict) -> dict:
    return json.loads(record["Sns"]["Message"])


def _remediate_asg_instance(alarm_message: dict) -> str:
    """Terminate any unhealthy instance in the target ASG so the ASG's
    normal replacement behavior brings up a fresh, healthy node."""
    response = autoscaling.describe_auto_scaling_groups(AutoScalingGroupNames=[ASG_NAME])
    groups = response.get("AutoScalingGroups", [])
    if not groups:
        return f"ASG {ASG_NAME} not found; nothing to remediate."

    unhealthy = [
        i["InstanceId"]
        for i in groups[0].get("Instances", [])
        if i.get("HealthStatus") != "Healthy" or i.get("LifecycleState") != "InService"
    ]

    if not unhealthy:
        return f"No unhealthy instances found in {ASG_NAME}; alarm may be transient."

    for instance_id in unhealthy:
        autoscaling.terminate_instance_in_auto_scaling_group(
            InstanceId=instance_id,
            ShouldDecrementDesiredCapacity=False,
        )

    return f"Terminated unhealthy instances {unhealthy} in {ASG_NAME}; ASG will replace them."


def _remediate_rds() -> str:
    """Reboot the RDS instance. Safe to call even if it's already
    recovering; RDS will simply reject/no-op if a reboot is already
    in progress."""
    try:
        rds.reboot_db_instance(DBInstanceIdentifier=DB_INSTANCE_IDENTIFIER)
        return f"Reboot triggered for RDS instance {DB_INSTANCE_IDENTIFIER}."
    except rds.exceptions.InvalidDBInstanceStateFault:
        return f"RDS instance {DB_INSTANCE_IDENTIFIER} already rebooting/unavailable; skipped."


def handler(event, context):  # noqa: ANN001, ANN201 - Lambda entrypoint signature
    results = []

    for record in event.get("Records", []):
        try:
            message = _parse_sns_message(record)
        except (KeyError, json.JSONDecodeError):
            results.append("Skipped record: not a valid SNS/CloudWatch alarm message.")
            continue

        alarm_name = message.get("AlarmName", "")

        if "asg" in alarm_name.lower() or "node" in alarm_name.lower():
            results.append(_remediate_asg_instance(message))
        elif "rds" in alarm_name.lower() or "db" in alarm_name.lower():
            results.append(_remediate_rds())
        else:
            results.append(f"Alarm '{alarm_name}' did not match any known remediation rule.")

    print(json.dumps({"remediation_results": results}))
    return {"statusCode": 200, "body": json.dumps(results)}