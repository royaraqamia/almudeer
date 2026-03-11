# Al-Mudeer Library - Monitoring Quick Start Guide

## Overview

This guide helps you set up complete monitoring for the library feature using Prometheus and Grafana.

---

## Prerequisites

- Docker and Docker Compose
- Al-Mudeer backend running on port 8000
- Admin access to install monitoring tools

---

## Quick Start (5 minutes)

### 1. Install Prometheus & Grafana

Create `docker-compose.monitoring.yml`:

```yaml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./monitoring/library_alerts.yml:/etc/prometheus/library_alerts.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.enable-lifecycle'
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana-library-dashboard.json:/etc/grafana/provisioning/dashboards/library-dashboard.json
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=almudeer123
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-piechart-panel
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
    restart: unless-stopped

volumes:
  prometheus_data:
  grafana_data:
```

### 2. Start Monitoring Stack

```bash
docker-compose -f docker-compose.monitoring.yml up -d
```

### 3. Access Dashboards

- **Grafana:** http://localhost:3000
  - Username: `admin`
  - Password: `almudeer123`
  - Dashboard: Library Monitoring (auto-imported)

- **Prometheus:** http://localhost:9090
  - Query: `library_uploads_total`
  - Alerts: http://localhost:9090/alerts

---

## Configuration

### Prometheus Targets

Edit `monitoring/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'almudeer-backend'
    static_configs:
      - targets: ['host.docker.internal:8000']  # Linux: localhost:8000
    metrics_path: '/metrics'
    scrape_interval: 15s
```

**Note for Linux:** Replace `host.docker.internal` with `localhost`

**Note for Production:** Use actual service name or IP

### Alerting

Configure alert notifications in `monitoring/library_alerts.yml`:

```yaml
# Add to the end of library_alerts.yml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
```

For Slack notifications, add to your alert rules:

```yaml
- alert: LibraryStorageQuotaEmergency
  expr: library_quota_warning >= 3
  for: 2m
  labels:
    severity: emergency
  annotations:
    summary: "Storage at 95%"
    description: "License {{ $labels.license_id }} at 95% capacity"
  # Slack notification
  receivers:
    - name: 'slack-notifications'
      slack_configs:
        - api_url: 'YOUR_SLACK_WEBHOOK_URL'
          channel: '#alerts'
```

---

## Verifying Metrics

### 1. Check Metrics Endpoint

```bash
curl http://localhost:8000/metrics
```

Expected output:
```
# HELP library_uploads_total Total number of library uploads
# TYPE library_uploads_total counter
library_uploads_total{license_id="1",item_type="note",status="success"} 150.0
...
```

### 2. Test Queries in Prometheus

Navigate to http://localhost:9090 and try these queries:

```promql
# Upload rate (last 5 minutes)
rate(library_uploads_total[5m])

# Storage usage by license
library_storage_usage_bytes

# Error rate
rate(library_errors_total[5m])

# Latency percentiles
histogram_quantile(0.95, rate(library_operation_duration_seconds_bucket[5m]))
```

### 3. Import Dashboard (if not auto-imported)

1. Open Grafana: http://localhost:3000
2. Go to **Dashboards** > **Import**
3. Upload `monitoring/grafana-library-dashboard.json`
4. Select Prometheus data source
5. Click **Import**

---

## Monitoring Best Practices

### 1. Set Up Alerting

Configure notifications for critical alerts:

```yaml
# In Prometheus alert rules
- alert: LibraryEndpointDown
  expr: up{job="almudeer-backend"} == 0
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "Backend is down"
  # Send to PagerDuty
  receivers:
    - name: 'pagerduty-critical'
      pagerduty_configs:
        - service_key: 'YOUR_PAGERDUTY_KEY'
```

### 2. Create Runbook Links

Add runbook URLs to alert annotations:

```yaml
annotations:
  summary: "Storage at 95%"
  runbook_url: "https://github.com/almudeer/backend/blob/main/docs/INCIDENT_RUNBOOK.md#storage-quota-emergency"
```

### 3. Set Up Log Aggregation

For production, integrate with Loki or ELK:

```yaml
# Loki configuration example
loki:
  url: http://loki:3100
  labels:
    job: almudeer-backend
```

---

## Troubleshooting

### No Metrics Showing

1. **Check backend is running:**
   ```bash
   curl http://localhost:8000/metrics
   ```

2. **Verify Prometheus target:**
   - Go to http://localhost:9090/targets
   - Check if `almudeer-backend` is UP

3. **Check Prometheus logs:**
   ```bash
   docker logs prometheus
   ```

### Grafana Dashboard Empty

1. **Verify data source:**
   - Go to Configuration > Data Sources
   - Ensure Prometheus is configured
   - Click "Save & Test"

2. **Check time range:**
   - Dashboard might be set to future time
   - Select "Last 6 hours" or "Last 24 hours"

### Alerts Not Firing

1. **Check alert rules:**
   ```bash
   curl http://localhost:9090/api/v1/rules
   ```

2. **Verify expression:**
   - Test query in Prometheus UI
   - Ensure it returns expected results

---

## Production Deployment

### Railway Deployment

Add to your `railway.toml`:

```toml
[build]
builder = "DOCKERFILE"

[deploy]
healthcheckPath = "/metrics"
healthcheckTimeout = 100

[[services]]
name = "prometheus"
image = "prom/prometheus:latest"
port = 9090

[[services]]
name = "grafana"
image = "grafana/grafana:latest"
port = 3000
```

### Docker Swarm

```bash
docker stack deploy -c docker-compose.monitoring.yml monitoring
```

### Kubernetes

Create `monitoring-namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
```

Apply Prometheus Operator:

```bash
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml
```

---

## Cost Optimization

### Retention Settings

Reduce storage costs with shorter retention:

```yaml
# In prometheus.yml
global:
  scrape_interval: 30s  # Less frequent scraping

# Command line flags
command:
  - '--storage.tsdb.retention.time=7d'  # Keep 7 days
  - '--storage.tsdb.retention.size=1GB'  # Max 1GB
```

### Sampling

For high-traffic endpoints, use sampling:

```yaml
scrape_configs:
  - job_name: 'almudeer-backend'
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: 'library_.*'
        action: keep
```

---

## Next Steps

1. ✅ Set up alerting channels (Slack/PagerDuty)
2. ✅ Configure log aggregation (Loki/ELK)
3. ✅ Create custom dashboards for business metrics
4. ✅ Set up synthetic monitoring (uptime checks)
5. ✅ Implement distributed tracing (Jaeger/Tempo)

---

## Support

- **Documentation:** `docs/INCIDENT_RUNBOOK.md`
- **Metrics Reference:** `services/library_metrics_service.py`
- **Alert Rules:** `monitoring/library_alerts.yml`

For issues, contact the DevOps team or create a GitHub issue.
