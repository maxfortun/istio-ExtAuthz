# Config
Implementation for ExtAuthz
[Conf](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/ext_authz_filter)
[API](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/filters/http/ext_authz/v3/ext_authz.proto#extensions-filters-http-ext-authz-v3-extauthz)

### Gateway
Add label:
```
sponge-auth-role: gateway
```

### Deployment
Add label:
```
sponge-auth-role: client
```

Exclude health path from auth:
> AUTH_PATH is a comma separated list of single path regexes, with a leading exclamation mark (!) indicating negation.
```
        proxy.istio.io/config: |
          holdApplicationUntilProxyStarts: true
          proxyMetadata:
            AUTH_PATH: "!^/health"

```

# Ext Authz flow

Req -> Pre Req -> Ext Authz -> VS Auth -> Post Req -> Pre Res -> Svc -> Res
                               |-> !200 -> Pre Res -> Res
