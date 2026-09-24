# platform/infra/pulumi/monitoring_alerts.py

from __future__ import annotations

import pulumi
from pulumi import ResourceOptions
from pulumi_azure_native import dbforpostgresql, insights, resources, web


def create_self_healing_alerts(
    *,
    enabled: bool,
    app_name: str,
    rg: resources.ResourceGroup,
    common_tags: dict,
    pg_server: dbforpostgresql.Server,
    self_healing_function_app: web.WebApp | None,
    subscription_id: str,
):
    """Create (or skip) Action Group + Postgres alert pointed at the
    self-healing function, and export the webhook URL for Alertmanager.
    No-op when disabled or the function app wasn't created."""
    if not enabled or self_healing_function_app is None:
        return

    webhook_url = self_healing_function_app.default_host_name.apply(
        lambda host: f"https://{host}/api/self_healing"
    )

    # Exported so it can be pasted into Alertmanager's receivers/webhook
    # config for AKS/pod-level triggering (cluster-side, out of Pulumi's
    # reach).
    pulumi.export("self_healing_webhook_url", webhook_url)

    action_group = insights.ActionGroup(
        f"{app_name}-self-healing-ag",
        resource_group_name=rg.name,
        action_group_name=f"{app_name}-self-healing",
        group_short_name="selfheal",
        location="global",
        enabled=True,
        webhook_receivers=[
            insights.WebhookReceiverArgs(
                name="self-healing-function",
                service_uri=webhook_url,
                use_common_alert_schema=True,
            )
        ],
        tags=common_tags,
    )

    insights.MetricAlert(
        f"{app_name}-postgres-alert",
        resource_group_name=rg.name,
        rule_name=f"{app_name}-postgres-unavailable",
        description="Fires when PostgreSQL connection failures spike; triggers self-healing restart.",
        severity=1,
        enabled=True,
        location="global",
        scopes=[pg_server.id],
        evaluation_frequency="PT5M",
        window_size="PT15M",
        criteria=insights.MetricAlertSingleResourceMultipleMetricCriteriaArgs(
            odata_type="Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria",
            all_of=[
                insights.MetricCriteriaArgs(
                    criterion_type="StaticThresholdCriterion",
                    name="ConnectionsFailed",
                    metric_name="connections_failed",
                    metric_namespace="Microsoft.DBforPostgreSQL/flexibleServers",
                    operator="GreaterThan",
                    threshold=5,
                    time_aggregation="Total",
                )
            ],
        ),
        actions=[insights.MetricAlertActionArgs(action_group_id=action_group.id)],
        tags=common_tags,
        opts=ResourceOptions(depends_on=[action_group]),
    )