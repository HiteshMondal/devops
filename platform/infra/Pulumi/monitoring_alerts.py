"""
platform/infra/Pulumi/monitoring_alerts.py
--------------------------------------------------------------------------
Wires Azure Monitor metric alerts (AKS node problems, PostgreSQL
availability) to an Action Group that calls the self-healing Function
App's HTTP endpoint. This is what actually triggers remediation — without
this, self_healing.py's Function App exists but nothing ever invokes it.

STANDALONE BY DESIGN.
"""

from __future__ import annotations

import pulumi
from pulumi import ResourceOptions
from pulumi_azure_native import containerservice, dbforpostgresql, insights, resources, web


def create_self_healing_alerts(
    *,
    enabled: bool,
    app_name: str,
    rg: resources.ResourceGroup,
    common_tags: dict,
    aks_cluster: containerservice.ManagedCluster,
    pg_server: dbforpostgresql.Server,
    self_healing_function_app: web.WebApp | None,
    subscription_id: str,
):
    """Create (or skip) Action Group + alert rules pointed at the
    self-healing function. No-op when disabled or the function app wasn't
    created (e.g. ENABLE_SELF_HEALING=false)."""
    if not enabled or self_healing_function_app is None:
        return

    webhook_url = self_healing_function_app.default_host_name.apply(
        lambda host: f"https://{host}/api/self_healing"
    )

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

    aks_resource_id = aks_cluster.id
    pg_resource_id = pg_server.id

    insights.MetricAlert(
        f"{app_name}-aks-node-alert",
        resource_group_name=rg.name,
        rule_name=f"{app_name}-aks-node-not-ready",
        description="Fires when AKS nodes report not-ready status; triggers self-healing reconcile.",
        severity=2,
        enabled=True,
        scopes=[aks_resource_id],
        evaluation_frequency="PT5M",
        window_size="PT15M",
        criteria=insights.MetricAlertSingleResourceMultipleMetricCriteriaArgs(
            odata_type="Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria",
            all_of=[
                insights.MetricCriteriaArgs(
                    criterion_type="StaticThresholdCriterion",
                    name="NodeNotReady",
                    metric_name="kube_node_status_condition",
                    metric_namespace="Insights.Container/nodes",
                    operator="GreaterThan",
                    threshold=0,
                    time_aggregation="Maximum",
                )
            ],
        ),
        actions=[insights.MetricAlertActionArgs(action_group_id=action_group.id)],
        tags=common_tags,
        opts=ResourceOptions(depends_on=[action_group]),
    )

    insights.MetricAlert(
        f"{app_name}-postgres-alert",
        resource_group_name=rg.name,
        rule_name=f"{app_name}-postgres-unavailable",
        description="Fires when PostgreSQL CPU/connection metrics indicate unavailability; triggers self-healing restart.",
        severity=1,
        enabled=True,
        scopes=[pg_resource_id],
        evaluation_frequency="PT5M",
        window_size="PT15M",
        criteria=insights.MetricAlertSingleResourceMultipleMetricCriteriaArgs(
            odata_type="Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria",
            all_of=[
                insights.MetricCriteriaArgs(
                    criterion_type="StaticThresholdCriterion",
                    name="ConnectionsFailed",
                    metric_name="connections_failed",
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