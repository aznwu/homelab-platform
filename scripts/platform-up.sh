#!/usr/bin/env bash
# Install / upgrade the platform layer on the homelab cluster. Safe to re-run.
# Order matters: namespaces -> storage -> cert-manager -> MetalLB -> monitoring.
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=platform/versions.env
source platform/versions.env

EXPECTED_CONTEXT="homelab"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# Retry a command (webhooks can need a few seconds after their pods are Ready).
retry() {
  local tries=12 delay=10 n=1
  until "$@"; do
    (( n >= tries )) && return 1
    echo "  ...not ready yet, retrying in ${delay}s (${n}/${tries})"
    sleep "$delay"; n=$((n + 1))
  done
}

for bin in kubectl helm openssl; do
  command -v "$bin" >/dev/null || die "$bin is not installed (brew install $bin)"
done

ctx="$(kubectl config current-context 2>/dev/null || true)"
[[ "$ctx" == "$EXPECTED_CONTEXT" ]] || \
  die "kubectl context is '${ctx:-none}', expected '${EXPECTED_CONTEXT}'. Run: export KUBECONFIG=~/.kube/homelab.yaml"

log "Helm repositories"
helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null
helm repo add metallb https://metallb.github.io/metallb --force-update >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo update >/dev/null

log "Namespaces (Pod Security labels) and network policies"
kubectl apply -f platform/namespaces.yaml
kubectl apply -f platform/network-policies/

log "local-path-provisioner ${LOCAL_PATH_PROVISIONER_VERSION} (vendored)"
helm upgrade --install local-path-provisioner platform/local-path-provisioner/chart \
  --namespace local-path-storage \
  --values platform/local-path-provisioner/values.yaml \
  --wait --timeout 5m

log "cert-manager ${CERT_MANAGER_VERSION}"
helm upgrade --install cert-manager jetstack/cert-manager \
  --version "${CERT_MANAGER_VERSION}" \
  --namespace cert-manager \
  --values platform/cert-manager/values.yaml \
  --wait --timeout 10m

log "Homelab CA and ClusterIssuers"
retry kubectl apply -f platform/cert-manager/issuers.yaml
kubectl -n cert-manager wait --for=condition=Ready certificate/homelab-root-ca --timeout=180s

log "MetalLB ${METALLB_VERSION}"
helm upgrade --install metallb metallb/metallb \
  --version "${METALLB_VERSION}" \
  --namespace metallb-system \
  --values platform/metallb/values.yaml \
  --wait --timeout 10m
retry kubectl apply -f platform/metallb/config.yaml

log "Grafana admin secret"
if kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  echo "  grafana-admin already exists - keeping the current password"
else
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$(openssl rand -base64 24)"
  echo "  created grafana-admin with a random password"
fi

log "kube-prometheus-stack ${KUBE_PROMETHEUS_STACK_VERSION} (first install can take 10+ minutes)"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version "${KUBE_PROMETHEUS_STACK_VERSION}" \
  --namespace monitoring \
  --values platform/kube-prometheus-stack/values.yaml \
  --wait --timeout 20m

log "Done"
cat <<'MSG'
Next:
  1) Add to /etc/hosts on flux:     192.168.2.20  grafana.lab
  2) Grafana password:              kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
  3) Open:                          https://grafana.lab   (user: admin)
  4) Optional - trust the homelab CA on flux:
       kubectl -n cert-manager get secret homelab-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > ~/homelab-root-ca.crt
       sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/homelab-root-ca.crt
MSG
