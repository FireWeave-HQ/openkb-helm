# OpenKB Helm Chart

Community Helm chart for deploying [OpenKB](https://github.com/VectifyAI/OpenKB) (Open LLM Knowledge Base by VectifyAI) on Kubernetes. It runs the OpenKB REST API and Knowledge Workbench, with knowledge bases on a PersistentVolumeClaim and bearer-token authentication on by default.

Not an official Vectify AI chart. Upstream application: <https://github.com/VectifyAI/OpenKB> `0.5.0rc1`. Chart source, docs, and examples: <https://github.com/FireWeave-HQ/openkb-helm>.

```bash
helm repo add openkb https://fireweave-hq.github.io/openkb-helm
helm repo update
helm upgrade --install openkb openkb/openkb \
  --namespace openkb \
  --create-namespace \
  -f values.yaml
```

From a checkout of the repository:

```bash
helm upgrade --install openkb ./charts/openkb \
  --namespace openkb \
  --create-namespace \
  -f examples/minimal-values.yaml
```

The Pod image defaults to `openkb:0.5.0rc1`, which is not published anywhere. Build [docker/Dockerfile](https://github.com/FireWeave-HQ/openkb-helm/blob/main/docker/Dockerfile) and set `image.repository` to your registry. Create the credentials Secret first, as described in the [repository README](https://github.com/FireWeave-HQ/openkb-helm#install-from-a-checkout).

## Values

| Key | Default | Description |
| --- | --- | --- |
| `replicaCount` | `1` | Keep this at 1 with a ReadWriteOnce volume. |
| `image.repository` | `openkb` | Image repository. No official image exists. |
| `image.tag` | `""` | Empty uses `appVersion` (`0.5.0rc1`). |
| `image.digest` | `""` | When set, used instead of the tag (`sha256:...`). |
| `image.pullPolicy` | `IfNotPresent` | Kubernetes pull policy. |
| `imagePullSecrets` | `[]` | Pull secret references. |
| `nameOverride` / `fullnameOverride` | `""` | Truncated name overrides. |
| `serviceAccount.create` | `true` | Create a ServiceAccount. |
| `serviceAccount.automount` | `false` | OpenKB does not call the Kubernetes API. |
| `serviceAccount.name` | `""` | Name to use. Empty follows the fullname, or `default` when `create` is false. |
| `podSecurityContext` | non-root, UID/GID/fsGroup 1000, RuntimeDefault seccomp | Pod security context. |
| `securityContext` | read-only root, drop `ALL`, no privilege escalation | Container security context. |
| `container.host` | `0.0.0.0` | `--host`. Upstream's own default is `127.0.0.1`, which a Service cannot reach. |
| `container.port` | `7566` | `--port` and `containerPort`. This is the upstream default. |
| `container.extraArgs` | `[]` | Extra arguments after `--host` and `--port`. |
| `service.type` | `ClusterIP` | `ClusterIP`, `NodePort`, or `LoadBalancer`. |
| `service.port` | `7566` | Service port. `targetPort` is the named container port `http`. |
| `service.nodePort` | `null` | Fixed NodePort. Ignored unless `type` is `NodePort`. |
| `ingress.enabled` | `false` | Create a `networking.k8s.io/v1` Ingress. |
| `ingress.className` | `""` | `ingressClassName`. Empty omits the field. |
| `ingress.hosts` | `openkb.example.com` `/` | Hosts and paths. Unused until ingress is enabled. |
| `ingress.tls` | `[]` | TLS blocks (`secretName`, `hosts`). |
| `ingress.annotations` | `{}` | Controller-specific annotations. |
| `resources` | 100m/512Mi request, 2 CPU/2Gi limit | Indexing a large PDF may need more memory. |
| `persistence.enabled` | `true` | Mount a PVC. `false` uses an emptyDir and drops data with the Pod. |
| `persistence.existingClaim` | `""` | Use this claim and do not render a PVC. |
| `persistence.size` | `10Gi` | Request size for the chart-managed claim. |
| `persistence.storageClass` | `""` | Empty uses the default class. `"-"` sets `storageClassName: ""`. |
| `persistence.accessModes` | `ReadWriteOnce` | Also selects the default update strategy. |
| `persistence.mountPath` | `/var/lib/openkb` | Volume mount. |
| `persistence.kbSubPath` | `kbs` | `OPENKB_KB_ROOT` is `<mountPath>/<kbSubPath>`. |
| `persistence.homeSubPath` | `home` | `HOME` is `<mountPath>/<homeSubPath>`. |
| `persistence.volumeName` | `""` | Bind the claim to a specific PV. |
| `updateStrategy.type` | `""` | Empty means `Recreate` on ReadWriteOnce, otherwise `RollingUpdate`. |
| `pdb.enabled` | `false` | Render a PDB only when this is true **and** `replicaCount` > 1. |
| `pdb.minAvailable` | `1` | Used when `maxUnavailable` is null. |
| `pdb.maxUnavailable` | `null` | When set, used instead of `minAvailable`. |
| `networkPolicy.enabled` | `false` | Ingress to the app port, egress DNS and TCP 443. |
| `networkPolicy.extraEgress` | `[]` | Extra egress rules for non-443 endpoints. |
| `auth.existingSecret` | `""` | Secret to read. When set, the chart does not render a Secret. |
| `auth.tokenKey` | `OPENKB_API_TOKEN` | Key in `existingSecret`. Chart-managed Secrets always use `OPENKB_API_TOKEN`. |
| `auth.token` | `""` | Inline token. Stored in the Helm release Secret. Empty generates one via `lookup`, then `randAlphaNum`. |
| `auth.allowUnauthenticated` | `false` | Must stay false on any reachable Service. |
| `llm.apiKey` | `""` | `LLM_API_KEY`. Ignored when `auth.existingSecret` is set. |
| `llm.pageindexApiKey` | `""` | `PAGEINDEX_API_KEY`. Same caveat. |
| `llm.openaiApiBase` | `""` | `OPENAI_API_BASE`, from the ConfigMap. Not a substitute for the API key. |
| `config.corsOrigins` | `""` | `OPENKB_CORS_ORIGINS`. Empty keeps the upstream localhost list. |
| `config.maxUploadFileBytes` | `null` | Upstream default is 100MiB. |
| `config.maxUploadRequestBytes` | `null` | Upstream default is 500MiB. |
| `config.watchSseTimeout` | `null` | Upstream default is 300 seconds. |
| `config.watchMaxEvents` | `null` | Upstream default is 200. |
| `kbDefaults.model` | `""` | Written to cwd `config.yaml` for new knowledge bases. |
| `kbDefaults.language` | `""` | Same file. Upstream default language is `en`. |
| `kbDefaults.pageindexThreshold` | `null` | Same file. Upstream default is 20. |
| `extraEnv` | `[]` | Extra env entries. Use `valueFrom` for secrets. |
| `extraVolumes` / `extraVolumeMounts` | `[]` | Extra pod volumes. |
| `nodeSelector` / `tolerations` / `affinity` / `topologySpreadConstraints` | empty | Scheduling. |
| `terminationGracePeriodSeconds` | `120` | Lets in-flight LLM calls finish. |
| `preStopSleepSeconds` | `10` | `python -c "import time; time.sleep(N)"` before stop. |
| `probes.*.path` | `/openapi.json` | There is no `/health` or `/ready`. |
| `probes.startup.failureThreshold` | `36` | 36 × 5s. Importing LiteLLM is slow. |

`podAnnotations`, `podLabels`, `service.annotations`, `persistence.annotations`, and `revisionHistoryLimit` are also accepted.

## Probes

`GET /openapi.json` returns 200 when uvicorn is serving. It does not check that a knowledge base exists, and it does not send the bearer token. A failing process fails the probe. A process that is up but cannot reach an LLM still passes it.

## Authentication and upgrades

Set `auth.existingSecret` for any install you intend to keep. A generated token is stable across `helm upgrade` only when Helm can `lookup` the Secret in the cluster. Client-side `helm template` mints a new one on every run.
