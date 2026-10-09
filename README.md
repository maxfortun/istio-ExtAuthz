# ezsso istio-client

Istio integration for ezsso-auth. Supports sidecar mode (default) and ambient mode.

## Structure

```
components/
├── filter/              # Shared auth logic (Lua + ExtAuthz config)
│   ├── pre.lua          # PRE stage: prepare auth request
│   ├── post.lua         # POST stage: restore headers
│   └── extauthz.yaml    # ExtAuthz filter config
├── sidecar/             # Sidecar mode EnvoyFilter
│   └── envoyfilter.yaml
└── ambient/             # Ambient mode EnvoyFilter
    └── envoyfilter.yaml
```

## Configuration

Edit `config.yaml`:
```yaml
APP_NS: default
APP_NAME: ezsso
EXT_AUTH_HOST: api.ezsso.me

# Ambient mode only
WAYPOINT_NAME: default
```

## Sidecar Mode

For traditional Istio with sidecar injection.

### Setup

1. Label your app for auth:
```bash
kubectl label deployment my-app ezsso-role=client
```

2. Render and apply:
```bash
./render.sh components/sidecar/*.yaml | kubectl apply -f -
```

3. Create secrets (mounted via pod annotations):
```bash
kubectl create secret generic ezsso \
  --from-literal=OIDC_ISSUERS='https://accounts.google.com?client_id=...&client_secret=...'
```

4. Add pod annotations:
```yaml
proxy.istio.io/config: |
  proxyMetadata:
    AUTH_PATH: "!^/health"
sidecar.istio.io/userVolume: |
  [{"name":"ezsso","secret":{"secretName":"ezsso"}}]
sidecar.istio.io/userVolumeMount: |
  [{"name":"ezsso","mountPath":"/etc/ezsso","readOnly":true}]
```

## Ambient Mode

For Istio Ambient mesh with waypoint proxies.

### Setup

1. Enable ambient for namespace:
```bash
kubectl label namespace my-app istio.io/dataplane-mode=ambient
```

2. Deploy waypoint:
```bash
istioctl waypoint apply --namespace my-app --name default
```

3. Render and apply:
```bash
./render.sh components/ambient/*.yaml | kubectl apply -f -
```

4. Mount secrets on waypoint:
```bash
kubectl create secret generic ezsso \
  --from-literal=OIDC_ISSUERS='https://accounts.google.com?client_id=...&client_secret=...'

kubectl patch deployment -l istio.io/gateway-name=default \
  --type=json \
  -p='[
    {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"ezsso","secret":{"secretName":"ezsso"}}},
    {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"ezsso","mountPath":"/etc/ezsso","readOnly":true}}
  ]'
```

## Path Filtering

Set `AUTH_PATH` environment variable:
- `!^/health` - exclude paths starting with /health
- `^/api/.*` - only auth paths matching pattern

Multiple patterns separated by commas: `!^/health,!^/metrics,^/api/.*`

## Per-Request Secrets Key (BYOK)

Add `OIDC_SECRETS_KEY` to the secret:
```bash
kubectl create secret generic ezsso \
  --from-literal=OIDC_ISSUERS='...' \
  --from-literal=OIDC_SECRETS_KEY="$(openssl rand -base64 32)"
```

## Comparison

| Aspect | Sidecar | Ambient |
|--------|---------|---------|
| Proxy | Per-pod sidecar | Shared waypoint |
| EnvoyFilter context | `SIDECAR_INBOUND` | `GATEWAY` |
| Selector | App labels | Waypoint labels |
| Secrets | Pod volumes | Waypoint volumes |

## License

MIT
