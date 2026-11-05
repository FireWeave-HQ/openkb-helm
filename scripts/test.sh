#!/usr/bin/env bash
# Shared entrypoint for local checks and GitHub Actions.
# Renders the chart and asserts the install scenarios. Does not talk to a cluster.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${ROOT}/charts/openkb"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

echo "helm: $(helm version --short 2>/dev/null || helm version)"

echo "== helm lint =="
helm lint "${CHART}"
shopt -s nullglob
example_values=("${ROOT}"/examples/*.yaml)
shopt -u nullglob
if [[ ${#example_values[@]} -eq 0 ]]; then
  fail "examples/*.yaml is empty"
fi
for values in "${example_values[@]}"; do
  echo "-- lint $(basename "${values}")"
  helm lint "${CHART}" -f "${values}"
done

render() {
  local name="$1"
  shift
  helm template openkb "${CHART}" --namespace openkb "$@" > "${WORKDIR}/${name}.yaml"
}

count_kind() {
  local name="$1"
  local kind="$2"
  grep -c "^kind: ${kind}$" "${WORKDIR}/${name}.yaml" || true
}

require_kind() {
  local name="$1"
  local kind="$2"
  local expected="$3"
  local actual
  actual="$(count_kind "${name}" "${kind}")"
  [[ "${actual}" == "${expected}" ]] || fail "${name}: expected ${expected} ${kind}, found ${actual}"
}

echo "== scenario renders =="

render default
require_kind default Deployment 1
require_kind default Service 1
require_kind default PersistentVolumeClaim 1
require_kind default Secret 1
require_kind default ConfigMap 1
require_kind default ServiceAccount 1
require_kind default Ingress 0
require_kind default PodDisruptionBudget 0
require_kind default NetworkPolicy 0
grep -q "type: Recreate" "${WORKDIR}/default.yaml" || fail "default strategy is not Recreate"
grep -q "rollingUpdate:" "${WORKDIR}/default.yaml" && fail "default render includes rollingUpdate" || true
grep -q "containerPort: 7566" "${WORKDIR}/default.yaml" || fail "container port"
grep -q 'image: "openkb:0.5.0rc1"' "${WORKDIR}/default.yaml" || fail "default image"
grep -q "openkb-web" "${WORKDIR}/default.yaml" || fail "start command"
grep -q '"0.0.0.0"' "${WORKDIR}/default.yaml" || fail "bind host"
grep -q "path: /openapi.json" "${WORKDIR}/default.yaml" || fail "probe path"
grep -q "readOnlyRootFilesystem: true" "${WORKDIR}/default.yaml" || fail "read-only root"
grep -q "runAsNonRoot: true" "${WORKDIR}/default.yaml" || fail "runAsNonRoot"
grep -q "privileged: false" "${WORKDIR}/default.yaml" || fail "privileged"
grep -q "drop:" "${WORKDIR}/default.yaml" || fail "capability drop"
grep -q -e "- ALL" "${WORKDIR}/default.yaml" || fail "drop ALL"
grep -q "claimName: openkb-data" "${WORKDIR}/default.yaml" || fail "pvc claim"
grep -q "helm.sh/resource-policy: keep" "${WORKDIR}/default.yaml" || fail "pvc keep"
grep -q "name: OPENKB_KB_ROOT" "${WORKDIR}/default.yaml" || fail "kb root env"
grep -q 'value: "/var/lib/openkb/kbs"' "${WORKDIR}/default.yaml" || fail "kb root path"
grep -q "name: OPENKB_API_TOKEN" "${WORKDIR}/default.yaml" || fail "auth env missing; unauthenticated would be the default"
grep -q "key: OPENKB_API_TOKEN" "${WORKDIR}/default.yaml" || fail "auth secret key"
# ConfigMap document must not carry credentials. The Secret may.
awk '
  $0 ~ /^kind: ConfigMap$/ { in_cm=1 }
  in_cm && $0 ~ /^kind: / && $0 !~ /^kind: ConfigMap$/ { in_cm=0 }
  in_cm { print }
' "${WORKDIR}/default.yaml" > "${WORKDIR}/default-cm.txt"
grep -q "LLM_API_KEY" "${WORKDIR}/default-cm.txt" && fail "LLM key leaked into ConfigMap" || true
grep -q "PAGEINDEX_API_KEY" "${WORKDIR}/default-cm.txt" && fail "PageIndex key leaked into ConfigMap" || true
grep -q "OPENKB_API_TOKEN" "${WORKDIR}/default-cm.txt" && fail "API token leaked into ConfigMap" || true

render persistence \
  --set persistence.size=50Gi \
  --set persistence.storageClass=fast-ssd \
  --set 'persistence.accessModes[0]=ReadWriteOnce' \
  --set auth.token=replace-me
grep -q 'storage: "50Gi"' "${WORKDIR}/persistence.yaml" || fail "pvc size"
grep -q 'storageClassName: "fast-ssd"' "${WORKDIR}/persistence.yaml" || fail "storage class"
grep -q "ReadWriteOnce" "${WORKDIR}/persistence.yaml" || fail "access mode"
grep -q "name: openkb-data" "${WORKDIR}/persistence.yaml" || fail "stable pvc name"
grep -q "helm.sh/resource-policy: keep" "${WORKDIR}/persistence.yaml" || fail "keep on custom pvc"

render rwx \
  --set 'persistence.accessModes[0]=ReadWriteMany' \
  --set auth.token=replace-me
grep -q "type: RollingUpdate" "${WORKDIR}/rwx.yaml" || fail "RWX should roll"

render existing-pvc \
  --set persistence.existingClaim=team-openkb-data \
  --set auth.token=replace-me
require_kind existing-pvc PersistentVolumeClaim 0
grep -q "claimName: team-openkb-data" "${WORKDIR}/existing-pvc.yaml" || fail "existing claim"

render existing-secret \
  --set auth.existingSecret=my-openkb \
  --set llm.apiKey=should-not-render
require_kind existing-secret Secret 0
grep -q "name: my-openkb" "${WORKDIR}/existing-secret.yaml" || fail "existing secret ref"
grep -q "should-not-render" "${WORKDIR}/existing-secret.yaml" && fail "inline key rendered alongside existingSecret" || true

render ingress -f "${ROOT}/examples/ingress-tls-values.yaml"
require_kind ingress Ingress 1
grep -q "kb.example.com" "${WORKDIR}/ingress.yaml" || fail "ingress host"
grep -q "openkb-tls" "${WORKDIR}/ingress.yaml" || fail "tls secret"
grep -q "networking.k8s.io/v1" "${WORKDIR}/ingress.yaml" || fail "ingress api"

render image \
  --set image.repository=ghcr.io/example/openkb \
  --set image.tag=9.9.9 \
  --set auth.token=replace-me
grep -q 'image: "ghcr.io/example/openkb:9.9.9"' "${WORKDIR}/image.yaml" || fail "custom image"

render unauth --set auth.allowUnauthenticated=true
require_kind unauth Secret 0
grep -q "OPENKB_API_TOKEN" "${WORKDIR}/unauth.yaml" && fail "unauthenticated render still sets the token" || true

# Two renders of the default chart must name the PVC identically.
# The generated token may differ without a cluster; the volume name must not.
render upgrade-a
render upgrade-b
pvc_a="$(awk '/^kind: PersistentVolumeClaim$/{p=1} p && /^  name:/{print $2; exit}' "${WORKDIR}/upgrade-a.yaml")"
pvc_b="$(awk '/^kind: PersistentVolumeClaim$/{p=1} p && /^  name:/{print $2; exit}' "${WORKDIR}/upgrade-b.yaml")"
[[ "${pvc_a}" == "openkb-data" && "${pvc_a}" == "${pvc_b}" ]] || fail "PVC name is not stable (${pvc_a} vs ${pvc_b})"

echo "== helm unittest =="
if helm plugin list 2>/dev/null | grep -q unittest; then
  helm unittest "${CHART}"
else
  echo "helm-unittest is not installed; scenario assertions above still ran."
  echo "Install with: helm plugin install https://github.com/helm-unittest/helm-unittest --version v0.8.2 --verify=false"
fi

if command -v kubeconform >/dev/null 2>&1; then
  KUBECONFORM="$(command -v kubeconform)"
elif [[ -x /tmp/kubeconform ]]; then
  KUBECONFORM=/tmp/kubeconform
else
  KUBECONFORM=""
fi

if [[ -n "${KUBECONFORM}" ]]; then
  echo "== kubeconform (${KUBECONFORM}) =="
  for manifest in "${WORKDIR}"/*.yaml; do
    echo "-- $(basename "${manifest}")"
    "${KUBECONFORM}" -kubernetes-version 1.35.0 -strict -summary "${manifest}"
  done
else
  echo "kubeconform not found; manifest schema validation was skipped."
fi

echo "== helm package =="
helm package "${CHART}" --destination "${WORKDIR}" >/dev/null
ls -1 "${WORKDIR}"/*.tgz

echo "All chart checks passed."
