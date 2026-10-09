# ezsso istio-client

Istio/Envoy integration for ezsso-auth using the ExtAuthz filter.

## How it works

1. Envoy sidecar intercepts requests to protected services
2. Lua filter rewrites request to ezsso-auth `/oidc/authorize`
3. ExtAuthz filter makes the auth subrequest
4. If authenticated (200): request proceeds with token headers
5. If unauthenticated (401 + Location): Lua converts to 303 redirect to IdP

## References

- [ExtAuthz Configuration](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/ext_authz_filter)
- [ExtAuthz API](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/filters/http/ext_authz/v3/ext_authz.proto)

<details>
  <summary>Sequence diagram</summary>
  <a href="docs/sequence-diagram.pdf"><img src="docs/sequence-diagram.svg" alt="PDF"></a>
</details>

## Configuration

### Variables

```yaml
APP_NS: default           # Namespace for the protected app
GW_NS: default            # Namespace for the gateway
GW_NAME: default-gateway  # Gateway name

APP_NAME: ezsso           # Prefix for filter components
EXT_AUTH_HOST: api.ezsso.me  # ezsso-auth hostname
```

### Render and Install

```bash
# Render templates with your config
./render.sh components/*.yaml > rendered.yaml

# Apply to cluster
kubectl apply -f rendered.yaml
```

### Gateway Setup

Add label to the Gateway:
```yaml
ezsso-role: gateway
```

### Deployment Setup

Add label to protected Deployments:
```yaml
ezsso-role: client
```

### Auth Configuration

Configure via secret:
```bash
kubectl -n default create secret generic ezsso \
  --from-literal=OIDC_ISSUERS='https://...' \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Per-Request Secrets Key (Optional)

For apps using request-level encryption (BYOK):

```bash
KEY=$(openssl rand -base64 32)

kubectl -n default create secret generic ezsso \
  --from-literal=OIDC_ISSUERS='https://...' \
  --from-literal=OIDC_SECRETS_KEY="$KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
```

The key is sent as `ezsso-oidc-secrets-key` header for decrypting IdP secrets sealed with `source: "request"`.

### Deployment Annotations

```yaml
proxy.istio.io/config: |
  holdApplicationUntilProxyStarts: true
  proxyMetadata:
    AUTH_PATH: "!^/health"      # Exclude paths (! = negation)
    AUTH_PORTS: "8080,8443"     # Only auth these ports (optional)
sidecar.istio.io/userVolume: |
  [{"name":"ezsso","secret":{"secretName":"ezsso"}}]
sidecar.istio.io/userVolumeMount: |
  [{"name":"ezsso","mountPath":"/etc/ezsso/OIDC_ISSUERS","subPath":"OIDC_ISSUERS","readOnly":true},
   {"name":"ezsso","mountPath":"/etc/ezsso/OIDC_SECRETS_KEY","subPath":"OIDC_SECRETS_KEY","readOnly":true}]
```

Or via environment variable:
```yaml
proxy.istio.io/config: |
  proxyMetadata:
    OIDC_SECRETS_KEY: "<base64-32-byte-key>"
```

## License

MIT
