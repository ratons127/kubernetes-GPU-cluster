#!/usr/bin/env bash
set -euo pipefail

K8S_DIR=/root/k8s
DOMAIN="${DOMAIN:-betopialtd.com}"
GRAFANA_URL="${GRAFANA_URL:-https://grafana.betopialtd.com}"

usage() {
  cat <<'EOF'
Usage:
  workspace-admin.sh list
  workspace-admin.sh status <client-id>
  workspace-admin.sh create <client-id> <nodeport> [storage-size]
  workspace-admin.sh apply <client-id>
  workspace-admin.sh suspend <client-id>
  workspace-admin.sh resume <client-id>
  workspace-admin.sh terminate <client-id> [--purge]
  workspace-admin.sh token <client-id>
  workspace-admin.sh url <client-id>
  workspace-admin.sh logs <client-id>
  workspace-admin.sh grafana
EOF
}

require_ns() {
  local client_id="$1"
  kubectl get ns "$client_id" >/dev/null 2>&1 || {
    echo "Namespace $client_id not found" >&2
    exit 1
  }
}

client_url() {
  local client_id="$1"
  local token
  token=$(kubectl get secret -n "$client_id" "${client_id}-jupyter-auth" -o jsonpath='{.data.JUPYTER_TOKEN}' | base64 -d)
  echo "https://${client_id}.${DOMAIN}/lab?token=${token}"
}

case "${1:-}" in
  list)
    kubectl get ns | awk 'NR==1 || $1 ~ /^client[0-9][0-9]$/'
    ;;
  status)
    client_id="${2:?client-id required}"
    require_ns "$client_id"
    kubectl get deploy,pod,svc,pvc,ingress,certificate -n "$client_id" -o wide
    ;;
  create)
    client_id="${2:?client-id required}"
    nodeport="${3:?nodeport required}"
    storage="${4:-200Gi}"
    "$K8S_DIR/provision-client.sh" "$client_id" "$nodeport" "$storage" > "$K8S_DIR/${client_id}.info"
    kubectl apply -f "$K8S_DIR/${client_id}.yaml"
    kubectl rollout status -n "$client_id" deploy/${client_id}-jupyter --timeout=420s
    echo "Workspace deployed."
    echo "URL: $(client_url "$client_id")"
    ;;
  apply)
    client_id="${2:?client-id required}"
    kubectl apply -f "$K8S_DIR/${client_id}.yaml"
    kubectl rollout status -n "$client_id" deploy/${client_id}-jupyter --timeout=420s
    kubectl get deploy,pod,svc,pvc,ingress -n "$client_id" -o wide
    ;;
  suspend)
    client_id="${2:?client-id required}"
    require_ns "$client_id"
    kubectl scale deployment/${client_id}-jupyter -n "$client_id" --replicas=0
    kubectl get deploy,pod -n "$client_id"
    ;;
  resume)
    client_id="${2:?client-id required}"
    require_ns "$client_id"
    kubectl scale deployment/${client_id}-jupyter -n "$client_id" --replicas=1
    kubectl rollout status -n "$client_id" deploy/${client_id}-jupyter --timeout=420s
    kubectl get deploy,pod -n "$client_id" -o wide
    ;;
  terminate)
    client_id="${2:?client-id required}"
    mode="${3:-}"
    require_ns "$client_id"
    kubectl delete deployment -n "$client_id" "${client_id}-jupyter" --ignore-not-found=true
    kubectl delete service -n "$client_id" "${client_id}-jupyter" "${client_id}-jupyter-nodeport" --ignore-not-found=true
    kubectl delete ingress -n "$client_id" "${client_id}-jupyter" --ignore-not-found=true
    kubectl delete certificate -n "$client_id" "${client_id}-${DOMAIN//./-}-tls" --ignore-not-found=true
    kubectl delete secret -n "$client_id" "${client_id}-jupyter-auth" "${client_id}-${DOMAIN//./-}-tls" --ignore-not-found=true
    kubectl delete resourcequota -n "$client_id" "${client_id}-quota" --ignore-not-found=true
    kubectl delete limitrange -n "$client_id" "${client_id}-defaults" --ignore-not-found=true
    if [[ "$mode" == "--purge" ]]; then
      kubectl delete pvc -n "$client_id" "${client_id}-home" --ignore-not-found=true
      kubectl delete ns "$client_id" --ignore-not-found=true
    fi
    ;;
  token)
    client_id="${2:?client-id required}"
    require_ns "$client_id"
    kubectl get secret -n "$client_id" "${client_id}-jupyter-auth" -o jsonpath='{.data.JUPYTER_TOKEN}' | base64 -d; echo
    ;;
  url)
    client_id="${2:?client-id required}"
    require_ns "$client_id"
    client_url "$client_id"
    ;;
  logs)
    client_id="${2:?client-id required}"
    require_ns "$client_id"
    kubectl logs -n "$client_id" deploy/${client_id}-jupyter --tail=200
    ;;
  grafana)
    echo "Grafana URL: ${GRAFANA_URL}"
    echo "Grafana user: admin"
    echo "Grafana password: set separately on the target host"
    ;;
  *)
    usage
    exit 1
    ;;
esac
