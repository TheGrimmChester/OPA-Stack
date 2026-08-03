# Data model (ClickHouse)

Logical database: `opa`.

| Table | Purpose |
|-------|---------|
| `spans_min` | Hot path span rollup / query surface |
| `spans_full` | Full span payloads |
| `errors` / error grouping tables | Error triage |
| `logs` | Log events |
| `rum_events` | Browser RUM |
| `alert_state` | Durable alert eval / cooldown |
| `chart_annotations` | Dashboard markers |
| `tql_saved_queries` | Saved TQL |
| `audit_log` | Privileged ops audit |
| `leader_leases` (or equivalent) | Best-effort background job lease |

Exact DDL is owned by the Agent migration runner (`migrate.go`). Prefer reading migrations over duplicating schemas here.
