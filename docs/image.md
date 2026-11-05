# Container image

OpenKB `v0.5.0-rc1` does not publish a container image. See [architecture.md](architecture.md) for what was checked.

`docker/Dockerfile` installs the upstream release instead of copying the OpenKB git tree:

```text
pip install "openkb[web]==0.5.0rc1" \
            "fastapi==0.139.0" \
            "uvicorn==0.47.0" \
            "python-multipart==0.0.29"
```

The wheel already contains the built Knowledge Workbench (`openkb/web/`). The image does not run Node.

The base image is `python:3.12-slim-bookworm`. Upstream supports Python 3.10 through 3.13. The process user is `openkb`, uid 1000. The entrypoint is `openkb-web` with `--host 0.0.0.0 --port 7566`.

## Build

From the repository root:

```bash
docker build -f docker/Dockerfile -t openkb:0.5.0rc1 .
```

Or `make docker-build`.

Override the package version only if you have confirmed that version's server, port, and environment variables. The chart defaults assume `0.5.0rc1`.

```bash
docker build -f docker/Dockerfile \
  --build-arg OPENKB_VERSION=0.5.0rc1 \
  -t openkb:0.5.0rc1 .
```

## Run outside Kubernetes

```bash
docker run --rm -p 7566:7566 \
  -e OPENKB_API_TOKEN="$(openssl rand -hex 32)" \
  -e LLM_API_KEY="paste-your-llm-key" \
  -v openkb-data:/home/openkb \
  -e HOME=/home/openkb \
  -e OPENKB_KB_ROOT=/home/openkb/kbs \
  openkb:0.5.0rc1
```

Without those volume settings the container uses `/home/openkb` from the image, which is writable only when the root filesystem is writable. The chart turns the root filesystem read-only and supplies the PVC and `/tmp` instead.

## Publish

This repository's release workflow publishes the Helm chart. It does not push the image.

Push the image to a registry your cluster can pull, then set:

```yaml
image:
  repository: registry.example.com/openkb
  tag: "0.5.0rc1"
  pullPolicy: IfNotPresent
```

Prefer `image.digest` once the tag is immutable.

An optional OCI Helm publish (`oci://ghcr.io/<owner>/charts`) is not wired up. The chart release path is GitHub Pages via chart-releaser, which avoids needing extra package permissions. You can add `helm push` later without changing the chart.

## Checked locally

A container built from this Dockerfile was started with `OPENKB_API_TOKEN` set and no Kubernetes cluster:

| Request | Result |
| --- | --- |
| `GET /openapi.json` | 200 |
| `GET /` | 200, Workbench HTML (`<title>OpenKB Studio</title>`) |
| `GET /health` | 404 |
| `GET /api/v1/meta` with no token or a wrong token | 401 |
| `GET /api/v1/meta` with the token | 200, `{"version":"0.5.0rc1"}` |

Uvicorn logged `Uvicorn running on http://0.0.0.0:7566`.

## CI

`.github/workflows/ci.yaml` builds `openkb:ci` with `docker buildx build --load` and scans it with Trivy for fixed `CRITICAL` and `HIGH` findings. The scan does not push.
