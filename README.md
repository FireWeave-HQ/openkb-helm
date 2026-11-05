# openkb-helm

Community Helm chart and container image for [OpenKB](https://github.com/VectifyAI/OpenKB).

This repository deploys the OpenKB REST API and the bundled Knowledge Workbench. It is maintained separately from Vectify AI. It is not an official OpenKB project, and Vectify AI has not endorsed it.

The chart installs the upstream Python package. It does not fork the application.

## What you get

One Deployment runs `openkb-web`, which is the `openkb.api:main` console script. That process serves:

- the REST API under `/api/v1`
- the OpenAPI document at `/openapi.json` and the Swagger UI at `/docs`
- the Knowledge Workbench static bundle at `/`, when the wheel includes `openkb/web` (the published `0.5.0rc1` wheel does)

Knowledge bases are directories on a PersistentVolumeClaim. LLM credentials stay in a Kubernetes Secret.

## Version

| | |
| --- | --- |
| Chart | `0.1.0` |
| Upstream package | `0.5.0rc1` (git tag [`v0.5.0-rc1`](https://github.com/VectifyAI/OpenKB/releases/tag/v0.5.0-rc1)) |
| License of this repo | Apache-2.0. Upstream OpenKB is also Apache-2.0. See [NOTICE](NOTICE). |

`v0.4.5` is the newest stable OpenKB tag and does not contain the web server. This chart tracks `0.5.0rc1` because that is the first PyPI release that does. `main` has moved past that tag; this chart does not follow unreleased commits.

## Architecture

```text
Ingress or Service :7566
        |
        v
   Pod  openkb-web --host 0.0.0.0 --port 7566
        |
        +-- PVC  /var/lib/openkb/kbs     OPENKB_KB_ROOT
        +-- PVC  /var/lib/openkb/home    HOME  (~/.config/openkb)
        +-- emptyDir /tmp                working directory and temp files
        +-- Secret                       OPENKB_API_TOKEN, LLM_API_KEY, ...
```

The process default bind address is `127.0.0.1`. The chart passes `--host 0.0.0.0` so the Service can reach it. The port `7566` is the upstream default.

There is no `/health` or `/ready` route. Probes use `GET /openapi.json`, which FastAPI serves as soon as the process is up. That route is not protected by the bearer token. The API routes are.

Details and file references: [docs/architecture.md](docs/architecture.md).

## Prerequisites

- Kubernetes 1.28 or newer. As of November 2026 the Kubernetes project supports 1.35, 1.36, and 1.37. This chart only uses stable APIs.
- Helm 3 or 4 (`helm` 4.0.4 was used to render and test it).
- A StorageClass that can provision a PersistentVolume, unless you set `persistence.existingClaim` or `persistence.enabled=false`.
- A container image. Upstream does not publish one. Build [docker/Dockerfile](docker/Dockerfile) or use an image you have pushed. See [docs/image.md](docs/image.md).
- An LLM API key if you want query, chat, or compile to call a model. The server starts without one.

## Install from the chart repository

After the first GitHub release, with GitHub Pages enabled from the `gh-pages` branch:

```bash
helm repo add openkb https://<org>.github.io/openkb-helm
helm repo update
helm install openkb openkb/openkb \
  --namespace openkb \
  --create-namespace \
  -f values.yaml
```

`<org>` is the GitHub owner of this repository. The release workflow uses `github.repository_owner`; it is not hardcoded here.

## Install from a checkout

Create the credentials Secret first. The chart will not store these values in a ConfigMap.

```bash
kubectl create namespace openkb
kubectl -n openkb create secret generic openkb-credentials \
  --from-literal=OPENKB_API_TOKEN="$(openssl rand -hex 32)" \
  --from-literal=LLM_API_KEY="paste-your-llm-key"
```

`PAGEINDEX_API_KEY` is optional and only needed for PageIndex Cloud. `OPENAI_API_BASE` is optional and is the OpenAI-compatible base URL.

```bash
helm upgrade --install openkb ./charts/openkb \
  --namespace openkb \
  --create-namespace \
  -f examples/minimal-values.yaml
```

Build and load the image before the Pod can start. With the default values the image reference is `openkb:0.5.0rc1`:

```bash
docker build -f docker/Dockerfile -t openkb:0.5.0rc1 .
# kind: kind load docker-image openkb:0.5.0rc1
```

Point `image.repository` and `image.tag` at your registry if the cluster cannot see a local image.

### Inline credentials

`auth.token`, `llm.apiKey`, and `llm.pageindexApiKey` work and are written to a chart-managed Secret. Helm also stores those values in the release Secret. Prefer `auth.existingSecret`.

If you set neither `auth.existingSecret` nor `auth.token`, Helm generates `OPENKB_API_TOKEN` and reuses it on later upgrades only when the upgrade can read the existing Secret (`lookup`). `helm template` and `helm upgrade --dry-run=client` cannot see the cluster, so they print a new token every time. Do not apply that output over a release you care about.

## Configuration

| Topic | Example |
| --- | --- |
| Token in an existing Secret | [examples/minimal-values.yaml](examples/minimal-values.yaml) |
| Ingress and TLS | [examples/ingress-tls-values.yaml](examples/ingress-tls-values.yaml) |
| Existing PVC | [examples/existing-pvc-values.yaml](examples/existing-pvc-values.yaml) |
| LLM provider, base URL, PageIndex, model | [examples/llm-providers-values.yaml](examples/llm-providers-values.yaml) |
| NetworkPolicy | [examples/networkpolicy-values.yaml](examples/networkpolicy-values.yaml) |

The chart README lists the values: [charts/openkb/README.md](charts/openkb/README.md).

### Secrets

| Key | Required | Where it is read |
| --- | --- | --- |
| `OPENKB_API_TOKEN` | Yes, unless `auth.allowUnauthenticated` | Bearer token for `/api/v1/*` |
| `LLM_API_KEY` | For model calls | LiteLLM credential bundle |
| `PAGEINDEX_API_KEY` | No | PageIndex Cloud. Local indexing is the default |
| `OPENAI_API_BASE` | No | OpenAI-compatible gateway URL |

`auth.allowUnauthenticated: true` omits `OPENKB_API_TOKEN`. Upstream then serves the API with no authentication. Leave it `false`.

Retrieve the token without printing it into a chart note:

```bash
kubectl get secret -n openkb openkb-credentials \
  -o jsonpath='{.data.OPENKB_API_TOKEN}' | base64 -d && echo
```

The Workbench asks for the token once and keeps it in the browser. API clients send `Authorization: Bearer <token>`.

### Storage

`persistence.enabled` defaults to `true`. The claim is named `<release>-data` (`openkb-data` when the release is `openkb`) and is annotated `helm.sh/resource-policy: keep`.

`OPENKB_KB_ROOT` is `/var/lib/openkb/kbs`. `HOME` is `/var/lib/openkb/home`, because OpenKB stores global config at `Path.home() / ".config" / "openkb"` and does not read `XDG_CONFIG_HOME`.

Replicas default to 1. The default access mode is `ReadWriteOnce`, and the Deployment strategy is `Recreate`, so an upgrade does not start a second Pod before the volume is free. More than one replica needs `ReadWriteMany` and is still a poor fit: the file watcher is in-process.

`helm uninstall` does not delete the PVC. To delete the knowledge base:

```bash
kubectl delete pvc -n openkb openkb-data
```

### Ingress and TLS

`service.type` defaults to `ClusterIP`. Set `ingress.enabled` to expose the Workbench. Use a long proxy read timeout. Query, chat, and document upload streams are Server-Sent Events and can run for minutes. The nginx annotations in [examples/ingress-tls-values.yaml](examples/ingress-tls-values.yaml) are examples, not a requirement.

### LLM providers

OpenKB talks to models through LiteLLM. The REST server passes `LLM_API_KEY` (and `OPENAI_API_BASE` when set) on each request. One key covers OpenAI, Anthropic, Gemini, DeepSeek, and any other LiteLLM provider. The chart does not invent per-provider variables.

The model is not an environment variable. Upstream default is `gpt-5.4`, language `en`, `pageindex_threshold` 20. Set `kbDefaults.model` to a LiteLLM id (`gpt-5.4`, or `anthropic/claude-sonnet-4-6`) and the chart writes `config.yaml` into the working directory. REST `/init` copies that file into a new knowledge base when the request does not include a model. You can also change the model later in the Workbench.

OAuth providers (`chatgpt`, `github_copilot`) expect an interactive device login. This chart does not set that up.

### Network policy

`networkPolicy.enabled` is `false`. Turning it on allows ingress to port 7566 and egress to DNS (UDP/TCP 53) and TCP 443. Anything else, including an LLM on another port, needs `networkPolicy.extraEgress`. The policy is off by default so the first install can reach an LLM API.

## Upgrade

```bash
helm upgrade openkb openkb/openkb \
  --namespace openkb \
  -f values.yaml
```

The PVC name does not change across upgrades. Keep using the same `auth.existingSecret` so the bearer token stays put.

`0.5.0rc1` is a release candidate. Moving `appVersion` to a later upstream release is a chart change; read that release's notes before you roll it out. Knowledge-base files are plain Markdown and YAML on the volume.

## Backup and restore

See [docs/backup.md](docs/backup.md). Short version: snapshot the PVC, or copy `/var/lib/openkb`. Restoring that tree and mounting it with `persistence.existingClaim` brings the knowledge bases back. A KB-local `.env` on that volume may contain an LLM key if someone passed `api_key` to `/init`. The chart itself does not write API keys onto the volume.

## Uninstall

```bash
helm uninstall openkb --namespace openkb
kubectl delete pvc -n openkb openkb-data   # only when you want the data gone
kubectl delete secret -n openkb openkb-credentials
```

The second command is required because of `helm.sh/resource-policy: keep`.

## Security

- Authentication is on unless you set `auth.allowUnauthenticated`.
- The container runs as UID 1000, non-root, read-only root filesystem, all capabilities dropped, `RuntimeDefault` seccomp, not privileged.
- The ServiceAccount token is not mounted. OpenKB does not call the Kubernetes API.
- `/openapi.json` and `/docs` are unauthenticated even when the token is set. That is upstream behavior. Do not treat the OpenAPI document as a secret. Do not put the token in a probe header; it would show up in the Pod spec.
- Report vulnerabilities in this chart with [GitHub private vulnerability reporting](SECURITY.md). There is no bounty.

## Image

Build and publishing steps: [docs/image.md](docs/image.md).

```bash
docker build -f docker/Dockerfile -t openkb:0.5.0rc1 .
```

The Dockerfile installs `openkb[web]==0.5.0rc1` from PyPI, plus the FastAPI, uvicorn, and python-multipart versions pinned in the upstream lock file at `v0.5.0-rc1`. It does not clone OpenKB or rebuild the frontend. The wheel already contains `openkb/web/index.html`.

## Development

```bash
./scripts/test.sh
```

That lints the chart, renders the install scenarios, runs `helm unittest`, runs kubeconform when the binary is available, and packages the chart. It does not install into a cluster.

```bash
make docker-build
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Maintainers are the owners of this repository. This file does not name a person.

## License

Apache-2.0 for this chart, the Dockerfile, and these docs. Upstream OpenKB remains under its own Apache-2.0 copyright. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
