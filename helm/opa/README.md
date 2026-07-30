# Helm packaging (Wave 15-1)

Additive Kubernetes packaging for the agent. **Does not replace** `docker compose up`.

```bash
helm upgrade --install opa ./helm/opa \
  --set image.repository=opa-agent \
  --set image.tag=latest \
  --set env.CLICKHOUSE_URL=http://clickhouse:8123
```

Scale replicas:

```bash
helm upgrade opa ./helm/opa --set replicaCount=3
```

For TailBuffer-correct multi-ingest, set `OPA_INGEST_SHARDS` to the shard count and run one Deployment per shard index (or use sticky LB + single shard until you split). See Agent `docs/wave15-ha-scale.md`.
