local OIDC_ISSUERS = nil

function getOIDCIssuers(request_handle)
  if OIDC_ISSUERS then
      return OIDC_ISSUERS
  end

  local OIDC_ISSUERS_FILE_NAME = os.getenv("OIDC_ISSUERS_FILE_NAME") or "/etc/ezsso/OIDC_ISSUERS"
  request_handle:logDebug('[${config.APP_NAME}-getOIDCIssuers] reading ' .. OIDC_ISSUERS_FILE_NAME)

  local f = io.open(OIDC_ISSUERS_FILE_NAME, "r")
  if f then
      OIDC_ISSUERS = f:read("*l")
      f:close()
      request_handle:logDebug('[${config.APP_NAME}-getOIDCIssuers] loaded OIDC_ISSUERS: ' .. OIDC_ISSUERS)
  else
      request_handle:logErr('[${config.APP_NAME}-getOIDCIssuers] failed to open ' .. OIDC_ISSUERS_FILE_NAME)
      OIDC_ISSUERS = ""
  end

  return OIDC_ISSUERS
end

local OIDC_SECRETS_KEY = nil

function getOIDCSecretsKey(request_handle)
  if OIDC_SECRETS_KEY then
      return OIDC_SECRETS_KEY
  end

  OIDC_SECRETS_KEY = os.getenv("OIDC_SECRETS_KEY")
  if OIDC_SECRETS_KEY and OIDC_SECRETS_KEY ~= "" then
      request_handle:logDebug('[${config.APP_NAME}-getOIDCSecretsKey] loaded from env')
      return OIDC_SECRETS_KEY
  end

  local OIDC_SECRETS_KEY_FILE_NAME = os.getenv("OIDC_SECRETS_KEY_FILE_NAME") or "/etc/ezsso/OIDC_SECRETS_KEY"
  request_handle:logDebug('[${config.APP_NAME}-getOIDCSecretsKey] reading ' .. OIDC_SECRETS_KEY_FILE_NAME)

  local f = io.open(OIDC_SECRETS_KEY_FILE_NAME, "r")
  if f then
      OIDC_SECRETS_KEY = f:read("*l")
      f:close()
      request_handle:logDebug('[${config.APP_NAME}-getOIDCSecretsKey] loaded from file')
  else
      request_handle:logDebug('[${config.APP_NAME}-getOIDCSecretsKey] no secrets key configured')
      OIDC_SECRETS_KEY = ""
  end

  return OIDC_SECRETS_KEY
end


local AUTH_PATH = os.getenv("AUTH_PATH") or "^.*$"
local AUTH_PATH_TOKENS = {}

for token in AUTH_PATH:gmatch("([^,]+)") do
  table.insert(AUTH_PATH_TOKENS, token)
end

local AUTH_PORTS = os.getenv("AUTH_PORTS") or ""
local AUTH_PORTS_SET = {}

for port in AUTH_PORTS:gmatch("([^,]+)") do
  AUTH_PORTS_SET[port] = true
end

function shouldAuth(request_handle, path)
  if AUTH_PORTS ~= "" then
    local port = tostring(request_handle:connection():localAddress():portValue())
    if not AUTH_PORTS_SET[port] then
      request_handle:logDebug('[${config.APP_NAME}-pre-req] shouldAuth(false): port ' .. port .. ' not in AUTH_PORTS')
      return false
    end
  end

  if not path then
    request_handle:logDebug('[${config.APP_NAME}-pre-req] shouldAuth(true): no path');
    return true
  end

  for _, token in ipairs(AUTH_PATH_TOKENS) do
      local negated = false
      if token:sub(1,1) == "!" then
        negated = true
        token = token:sub(2)
      end

      if negated then
        if path:match(token) then
          request_handle:logDebug('[${config.APP_NAME}-pre-req] shouldAuth(false): ' .. path .. ' excluded by ' .. token);
          return false
        end
      else
        if not path:match(token) then
          request_handle:logDebug('[${config.APP_NAME}-pre-req] shouldAuth(false): ' .. path .. ' not matching ' .. token);
          return false
        end
      end
  end

  request_handle:logDebug('[${config.APP_NAME}-pre-req] shouldAuth(true): ' .. path);
  return true
end

function envoy_on_request(request_handle)
  request_handle:logDebug('[${config.APP_NAME}-pre-req] in pre');

  local metadata = request_handle:streamInfo():dynamicMetadata()

  local headers = request_handle:headers()
  for key, value in pairs(headers) do
     metadata:set('req', key, value)
  end

  local scheme = headers:get(':scheme') or 'http'
  local authority = headers:get(':authority') or 'localhost'
  local path = headers:get('x-envoy-original-path') or headers:get(':path') or '/'

  if not shouldAuth(request_handle, path) then
    metadata:set("envoy.filters.http.ext_authz", "disabled", true)
    return
  end
  metadata:set("envoy.filters.http.ext_authz", "disabled", false)

  local uri = 'https://' .. authority .. path

  headers:add('X-OIDC-RedirectURI', uri)

  headers:replace(':scheme', 'https')
  headers:replace(':authority', '${config.EXT_AUTH_HOST}')

  local query_index = string.find(path, '?', 1, true)
  local query = ''
  if query_index then
    query = string.sub(path, query_index)
  end
  headers:replace(':path', '/oidc/authorize' .. query)

  headers:add('X-OIDC-Issuers', getOIDCIssuers(request_handle))

  local secretsKey = getOIDCSecretsKey(request_handle)
  if secretsKey and secretsKey ~= '' then
    headers:add('ezsso-oidc-secrets-key', secretsKey)
  end

  request_handle:logDebug('[${config.APP_NAME}-pre-req] out pre');
end

function envoy_on_response(response_handle)
  response_handle:logDebug('[${config.APP_NAME}-pre-res] in response');

  local headers = response_handle:headers()

  local location = headers:get('location')
  if location and location ~= '' then
    response_handle:headers():replace(':status', '303')
    response_handle:logDebug('[${config.APP_NAME}-pre-res] response code changed to 303');
  end

  local status = headers:get(':status')
  if status ~= '200' then
    response_handle:logDebug('[${config.APP_NAME}-pre-res] status: ' .. status);

    local body = ''
    local ok, result = pcall(function()
      local len = response_handle:body():length()
      return response_handle:body():getBytes(0, len)
    end)

    if ok then
      body = result
    else
      response_handle:logWarn('Failed to read body: ' .. tostring(result))
    end

    response_handle:body():setBytes(body)
  end
end
