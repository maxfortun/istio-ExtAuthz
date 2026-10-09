# ezsso istio-client

Istio integration for ezsso-auth. Supports sidecar mode (default) and ambient mode.

Both modes use **opt-in labels** - only workloads/waypoints with the label get auth.

## Structure

```
components/
├── filter/              # Shared auth logic
│   ├── pre.lua
│   ├── post.lua
│   └── extauthz.yaml
├── sidecar/             # Sidecar mode (default)
│   └── envoyfilter.yaml
└── ambient/             # Ambient mode
    └── envoyfilter.yaml

examples/
├── sidecar/
│   └── deployment.yaml
└── ambient/
    ├── waypoint.yaml
    └── patch-waypoint-secrets.sh
```

## Quick Start

### Configuration

Edit `config.yaml`:
```yaml
APP_NS: default
APP_NAME: ezsso
EXT_AUTH_HOST: api.ezsso.me
```

### Create Secret

```bash
kubectl create secret generic ezsso \
  --from-literal=OIDC_ISSUERS='https://accounts.google.com?client_id=...&client_secret=...&scope=openid email profile'
```

---

## Sidecar Mode (Default)

Traditional Istio with sidecar injection.

### 1. Apply EnvoyFilter

```bash
./render.sh components/sidecar/*.yaml | kubectl apply -f -
```

### 2. Opt-in Apps

Add the label `ezsso-role: client` to deployments:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  labels:
    app: my-app
    ezsso-role: client  # <-- Opt-in
spec:
  template:
    metadata:
      labels:
        app: my-app
        ezsso-role: client  # <-- Required on pod too
      annotations:
        # Mount secrets into sidecar
        sidecar.istio.io/userVolume: |
          [{"name":"ezsso","secret":{"secretName":"ezsso"}}]
        sidecar.istio.io/userVolumeMount: |
          [{"name":"ezsso","mountPath":"/etc/ezsso","readOnly":true}]
        # Optional: exclude paths
        proxy.istio.io/config: |
          proxyMetadata:
            AUTH_PATH: "!^/health,!^/ready"
```

See `examples/sidecar/deployment.yaml` for a complete example.

---

## Ambient Mode

Istio Ambient mesh with waypoint proxies.

### 1. Enable Ambient

```bash
kubectl label namespace default istio.io/dataplane-mode=ambient
```

### 2. Apply EnvoyFilter

```bash
./render.sh components/ambient/*.yaml | kubectl apply -f -
```

### 3. Create & Label Waypoints

Waypoints opt-in with label `ezsso-auth: enabled`.

**Option A: Namespace-wide waypoint**

```bash
# Create waypoint
istioctl waypoint apply --namespace default --name default

# Label it for auth
kubectl label gateway default ezsso-auth=enabled
```

**Option B: Per-service waypoint**

```bash
# Create waypoint for specific service
istioctl waypoint apply --for service --name my-service --namespace default

# Label it for auth
kubectl label gateway my-service ezsso-auth=enabled
```

### 4. Mount Secrets on Waypoint

```bash
# Use the helper script
./examples/ambient/patch-waypoint-secrets.sh default my-service

# Or manually patch
kubectl patch deployment -l istio.io/gateway-name=my-service \
  --type=json -p='[
    {"op":"add","path":"/spec/template/spec/volumes/-",
     "value":{"name":"ezsso","secret":{"secretName":"ezsso"}}},
    {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-",
     "value":{"name":"ezsso","mountPath":"/etc/ezsso","readOnly":true}}
  ]'
```

See `examples/ambient/` for complete examples.

---

## Path Filtering

Exclude paths from auth via `AUTH_PATH` environment variable:

| Pattern | Meaning |
|---------|---------|
| `!^/health` | Exclude paths starting with /health |
| `!^/public/` | Exclude paths starting with /public/ |
| `^/api/.*` | Only auth paths matching /api/* |

Multiple patterns: `AUTH_PATH='!^/health,!^/metrics,^/api/.*'`

**Sidecar mode**: Set in pod annotation
```yaml
proxy.istio.io/config: |
  proxyMetadata:
    AUTH_PATH: "!^/health"
```

**Ambient mode**: Set on waypoint deployment
```bash
kubectl set env deployment/<waypoint> AUTH_PATH='!^/health'
```

---

## Per-Request Secrets Key (BYOK)

Add `OIDC_SECRETS_KEY` to the secret:

```bash
kubectl create secret generic ezsso \
  --from-literal=OIDC_ISSUERS='...' \
  --from-literal=OIDC_SECRETS_KEY="$(openssl rand -base64 32)"
```

---

## Comparison

| Aspect | Sidecar | Ambient |
|--------|---------|---------|
| Opt-in label | `ezsso-role: client` | `ezsso-auth: enabled` |
| Applied to | App pods | Waypoint proxies |
| EnvoyFilter context | `SIDECAR_INBOUND` | `GATEWAY` |
| Secrets mount | Pod annotations | Waypoint deployment |
| Granularity | Per-pod | Per-waypoint (namespace or service) |

## License

MIT
