# About
Implementation of ExtAuthz
[Conf](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/ext_authz_filter) 
[API](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/filters/http/ext_authz/v3/ext_authz.proto#extensions-filters-http-ext-authz-v3-extauthz)  

## Ext Authz flow
<pre>
Http request -> Gateway -> Pre request -> ExtAuthz -> VS Authorize -> Post request -> Pre response -> Service -> Http response
                                             |-> !200 -> Pre response -> Http response
</pre>

## Config
### Variables
```yaml
APP_NS: default
GW_NS: default
GW_NAME: default-gateway

APP_NAME: ext-auth
EXT_AUTH_HOST: authorizer.myorg.com
REDIRECT_URI: https://gateway.myorg.com/oidc/idpresponse

OIDC_ISSUERS: https://myorg.okta.com/oauth2/default?client_id=...&client_secret=...&scope=openid email profile address phone offline_access,https://myorg.okta.com?client_id=...&client_secret=...&scope=openid email profile address phone offline_access,https://cognito-idp.us-east-1.amazonaws.com/us-east-1_...?client_id=...&https://cognito-idp.us-west-2.amazonaws.com/us-west-2_...?client_id=...
```

### Render
Components of the filter are templatized, and need to be rendered with config from config.yaml:
```bash
./render.sh components/*.yaml > rendered.yaml
```

### Install
```bash
kubectl apply -f rendered.yaml 
```

### Gateway
Add label ${config.APP_NAME}-role to the Gateway you want to support ExtAuthz:
```
ext-auth-role: gateway
```

### Deployment
Add label ${config.APP_NAME}-role to the Deployment you want to be protected by ExtAuthz:
```
ext-auth-role: client
```

Exclude health path, if needed, from auth:
> AUTH_PATH is a comma separated list of single path regexes, with a leading exclamation mark (!) indicating negation.
```yaml
      annotations:
        proxy.istio.io/config: |
          holdApplicationUntilProxyStarts: true
          proxyMetadata:
            AUTH_PATH: "!^/health"

```

