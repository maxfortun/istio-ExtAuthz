function in_array(value, array)
  for _, v in ipairs(array) do
    if v == value then
      return true
    end
  end
  return false
end

function envoy_on_request(request_handle)
  request_handle:logDebug('[${config.APP_NAME}-post] in post');

  local headers = request_handle:headers()

  local to_keep = { 'idtoken', 'accesstoken', 'userinfo' }
  local to_remove = {}
  for key, value in pairs(headers) do
    local lkey = string.lower(key)
    if not in_array(key, to_keep) then
      table.insert(to_remove, key)
    end
  end

  for _, name in ipairs(to_remove) do
    headers:remove(name)
    request_handle:logDebug('[${config.APP_NAME}-post] rm head: ' .. name)
  end

  local req = request_handle:streamInfo():dynamicMetadata():get('req')
  for key, value in pairs(req) do
    headers:add(key, value)
  end

  request_handle:logDebug('[${config.APP_NAME}-post] out post');
end
