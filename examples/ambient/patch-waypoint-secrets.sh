#!/bin/bash
# Patch a waypoint deployment to mount ezsso secrets
#
# Usage: ./patch-waypoint-secrets.sh <namespace> <waypoint-name>
# Example: ./patch-waypoint-secrets.sh default my-service

set -e

NS=${1:-default}
WAYPOINT=${2:-default}

echo "Creating ezsso secret in namespace $NS..."
kubectl -n "$NS" create secret generic ezsso \
  --from-literal=OIDC_ISSUERS='https://accounts.google.com?client_id=YOUR_CLIENT_ID&client_secret=YOUR_SECRET&scope=openid email profile' \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Finding waypoint deployment..."
DEPLOY=$(kubectl -n "$NS" get deploy -l "istio.io/gateway-name=$WAYPOINT" -o name | head -1)

if [ -z "$DEPLOY" ]; then
  echo "Error: No deployment found for waypoint '$WAYPOINT' in namespace '$NS'"
  exit 1
fi

echo "Patching $DEPLOY to mount ezsso secret..."
kubectl -n "$NS" patch "$DEPLOY" --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "ezsso",
      "secret": {
        "secretName": "ezsso"
      }
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "name": "ezsso",
      "mountPath": "/etc/ezsso",
      "readOnly": true
    }
  }
]'

echo "Done. Waypoint will restart with secrets mounted."
