# OTel collector: Elastic Streams + Splunk O11y

One collector. Apps speak **OTLP**. The collector fans out:

| Backend | Traces | Metrics | Logs |
|---|---|---|---|
| **Elastic Streams** (managed OTLP, 9.5+ downsample/dedup) | yes | full fidelity | yes |
| **Splunk Observability / SignalFx** | yes | cardinality-filtered | no (use HEC if needed) |

```
Prometheus / Kubelet / Rancher API / Portworx / App OTLP
                         │
                   OTel Collector
               ┌─────────┴─────────┐
               ▼                   ▼
        Elastic Streams      Splunk O11y
```

---

## 1. Prerequisites

- **Go 1.24+** (`go version`)
- Git, make optional
- Network to proxy.golang.org (builder downloads collector modules)

```bash
go version   # go1.24 or newer
```

---

## 2. Install the OpenTelemetry Collector Builder

```bash
go install go.opentelemetry.io/collector/cmd/builder@v0.161.0
export PATH="$(go env GOPATH)/bin:$PATH"
builder --version
```

The binary is named `builder` (also published as `ocb`).

---

## 3. Build the custom collector

```bash
cd ~/opt/otel/streams-splunk-clickhouse

builder --config builder-config.yaml
```

This compiles `./dist/otelcol-streams-fanout` with the components in `builder-config.yaml` (OTLP, Prometheus, kubeletstats, k8s, Splunk/OTLP HTTP, Elastic OTLP HTTP, …).

First build downloads modules and takes several minutes. Rebuilds are incremental.

**Linux/amd64 from a Mac (for a cluster image):**

```bash
GOOS=linux GOARCH=amd64 builder --config builder-config.yaml
```

---

## 4. Credentials (do not commit)

```bash
cp env.example .env
# edit .env
set -a && source .env && set +a
```

Minimum:

| Variable | Example |
|---|---|
| `ELASTIC_OTLP_ENDPOINT` | `https://xxxx.ingest.us-east-1.aws.elastic.cloud:443` |
| `ELASTIC_API_KEY` | ingest API key |
| `SPLUNK_REALM` | `us1` |
| `SPLUNK_ACCESS_TOKEN` | SignalFx / Splunk O11y token |
| `K8S_CLUSTER_NAME` | `rancher-prod` |

Local laptop (no kubelet): you can still receive **OTLP on :4317/:4318**. Kubelet/Prometheus scrape needs in-cluster RBAC.

---

## 5. Run

**Laptop (OTLP only — no kubelet/Prometheus scrape):**

```bash
./dist/otelcol-streams-fanout --config collector-local.yaml
```

**In-cluster (full diagram: Prometheus, kubelet, Rancher, Portworx):**

```bash
./dist/otelcol-streams-fanout --config collector.yaml
```

Health: `http://127.0.0.1:13133/`  
zPages: `http://127.0.0.1:55679/debug/tracez`

Point apps at `http://127.0.0.1:4318`. Confirm in Elastic Discover / APM and Splunk O11y Metric Finder + APM.

---

## 6. Skip the custom binary (contrib image)

```bash
docker run --rm -p 4317:4317 -p 4318:4318 -p 13133:13133 \
  --env-file .env \
  -v "$PWD/collector-local.yaml:/etc/otelcol-contrib/config.yaml:ro" \
  otel/opentelemetry-collector-contrib:0.161.0 \
  --config=/etc/otelcol-contrib/config.yaml
```

Kubernetes:

```bash
kubectl create secret generic otel-fanout -n observability \
  --from-literal=elastic_otlp_endpoint='https://xxxx.ingest.elastic.cloud:443' \
  --from-literal=elastic_api_key='...' \
  --from-literal=splunk_realm='us1' \
  --from-literal=splunk_access_token='...'

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm upgrade --install otel-fanout open-telemetry/opentelemetry-collector \
  --namespace observability --create-namespace \
  --values helm-values.yaml
```

---

## 7. Docker image of the custom build

```bash
GOOS=linux GOARCH=amd64 builder --config builder-config.yaml

docker build -t otelcol-streams-fanout:0.161.0 .
docker run --rm -p 4317:4317 -p 4318:4318 --env-file .env \
  -v "$PWD/collector.yaml:/etc/otelcol/config.yaml:ro" \
  otelcol-streams-fanout:0.161.0
```

---

## EDOT 9.5.4 (supported path — agent / cluster / gateway)

Same topology as Splunk OTel agent + contrib gateway:

| Role | Deploy | Image |
|---|---|---|
| agent | DaemonSet | `docker.elastic.co/elastic-agent/elastic-otel-collector:9.5.4` |
| k8s-cluster-receiver | Deployment | same |
| gateway | Deployment | same — fans out to Elastic managed OTLP + Splunk O11y |

- `edot-gateway.yaml` — gateway-only config
- `edot-agent-and-cluster.yaml` — edge DaemonSet pattern
- `edot-kube-stack-values.yaml` — Helm overlay for kube-stack

```bash
docker pull docker.elastic.co/elastic-agent/elastic-otel-collector:9.5.4
```

---

## Files

| File | Role |
|---|---|
| `builder-config.yaml` | OCB manifest (what gets compiled in) |
| `collector.yaml` | Runtime pipelines (contrib / custom) |
| `helm-values.yaml` | DaemonSet for contrib/custom image |
| `edot-gateway.yaml` | Supported EDOT gateway (Elastic + Splunk) |
| `edot-agent-and-cluster.yaml` | EDOT edge agent / cluster receiver |
| `edot-kube-stack-values.yaml` | EDOT kube-stack Helm overlay |
| `env.example` | Credential template |
| `Dockerfile` | Image around `./dist/otelcol-streams-fanout` |
