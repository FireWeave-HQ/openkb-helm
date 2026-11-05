# Upstream architecture

Verified against [VectifyAI/OpenKB](https://github.com/VectifyAI/OpenKB) git tag `v0.5.0-rc1` (`9036c2c78517059d866c9743fde4f48f204b677f`). The PyPI version string is `0.5.0rc1`.

`v0.4.5` (`ac118407eacd995618256f121c21a2d275672f47`) has no `openkb/api.py`, no `openkb-web` script, and no `frontend/` tree. It is a CLI. The chart does not deploy it.

`main` was ahead of `v0.5.0-rc1` when this was written (commit `ff54396`, configurable entity types). Those commits are not a numbered final release. The chart installs the PyPI release, not `main`.

## Process

OpenKB is a Python 3.10+ package (`requires-python` in `pyproject.toml`). The server entry points are:

```toml
openkb-web = "openkb.api:main"
openkb-api = "openkb.api:main"
```

`openkb/__main__.py` runs the CLI (`openkb.cli:cli`), not the server. `python -m openkb.api` does call `main()` because `openkb/api.py` ends with `main()`.

`main()` (`openkb/api.py`) parses:

| Flag | Default |
| --- | --- |
| `--host` | `127.0.0.1` |
| `--port` | `7566` |
| `--reload` | off |

It then runs `uvicorn.run("openkb.api:create_app", factory=True, ...)`.

The chart's container command is `openkb-web --host 0.0.0.0 --port 7566`. Binding the upstream default `127.0.0.1` would make the Service fail.

Install extra, from `pyproject.toml`:

- `web` is the canonical extra: `fastapi`, `uvicorn`, `python-multipart` (unpinned in the package metadata).
- `api` is an alias of `web`.

The upstream lock at this tag pins `fastapi==0.139.0`, `uvicorn==0.47.0`, `python-multipart==0.0.29`. The Dockerfile pins those three so a later FastAPI release cannot drift under the chart.

## Workbench

`frontend/vite.config.ts` builds the SPA to `../openkb/web`. `openkb/api_helpers.py` `_mount_web_ui` mounts `StaticFiles` at `/` when `openkb/web` exists (`html=True`, so unknown UI paths return `index.html`).

The published wheel `openkb-0.5.0rc1-py3-none-any.whl` contains `openkb/web/index.html` (141 files under `openkb/web/`). Checked by downloading the wheel from PyPI. The image does not run `npm`.

`/` returns 404 only when that directory is absent. An API-only install does that. This image installs the `web` extra from the wheel, so the directory is present.

Routes registered before the mount, including `/openapi.json`, `/docs`, and `/api/v1/...`, are not swallowed by the SPA. A catch-all `/api/{path:path}` returns JSON 404 for unknown API paths (`openkb/api.py`).

## Storage

`openkb/config.py` `kb_root_dir()`:

1. `OPENKB_KB_ROOT` if set
2. else `kb_root` in `~/.config/openkb/global.yaml`
3. else `~/.config/openkb/kbs`

`GLOBAL_CONFIG_DIR` is `Path.home() / ".config" / "openkb"`. The code does not read `XDG_CONFIG_HOME`. The chart sets `HOME` to `/var/lib/openkb/home` on the same volume as the knowledge bases, and `OPENKB_KB_ROOT` to `/var/lib/openkb/kbs`.

Knowledge bases created by `POST /api/v1/init` land at `<OPENKB_KB_ROOT>/<name>` unless the request passes an absolute `path`. Listing walks that directory plus aliases in `global.yaml`.

`OPENKB_DIR` (`openkb/cli.py`) is a CLI override for a single knowledge-base directory. The server does not use it as the storage root. The chart does not set it.

On init, `initialize_kb` (`openkb/cli.py`) writes `<kb>/.env` and may copy `Path.cwd()/config.yaml` and `Path.cwd()/.env` into the new knowledge base. The chart's working directory is `/tmp` (an emptyDir). It does not place a `.env` there, so process environment credentials are not copied onto the volume at init time. If a client sends `api_key` on `/init`, upstream writes `LLM_API_KEY` into the KB `.env` on the PVC. That is application behavior. The chart does not do it.

Credential resolution for requests (`resolve_credential_bundle`): KB `.env`, then the process environment, then `~/.config/openkb/.env`. Keys: `LLM_API_KEY`, `OPENAI_API_BASE`.

## Configuration the server actually reads

### Environment

| Variable | Role | Chart |
| --- | --- | --- |
| `OPENKB_API_TOKEN` | Bearer token. Unset means the API is open (`require_bearer_token` in `openkb/api_helpers.py`). | Required unless `auth.allowUnauthenticated`. |
| `OPENKB_KB_ROOT` | Knowledge-base root. | Set to the PVC path. |
| `LLM_API_KEY` | LiteLLM key, passed per request by `build_run_config_from_bundle`. | Secret. |
| `OPENAI_API_BASE` | Optional OpenAI-compatible base URL. | ConfigMap, or the existing Secret if that key is present. |
| `PAGEINDEX_API_KEY` | PageIndex Cloud. Read in `openkb/indexer.py`. Empty uses local PageIndex. | Secret, optional. |
| `OPENKB_CORS_ORIGINS` | CORS allowlist. Empty uses localhost `5173` and `7566`. `*` disables credentials. | Optional. |
| `OPENKB_MAX_UPLOAD_FILE_BYTES` | Default `104857600` (100MiB). | Optional. |
| `OPENKB_MAX_UPLOAD_REQUEST_BYTES` | Default `524288000` (500MiB). | Optional. |
| `OPENKB_WATCH_SSE_TIMEOUT` | Default `300`. | Optional. |
| `OPENKB_WATCH_MAX_EVENTS` | Default `200` (`openkb/watch_service.py`). | Optional. |

`openkb/api.py` also sets `LITELLM_LOCAL_MODEL_COST_MAP=true` itself if it is unset.

`NO_COLOR` only affects CLI coloring. It is not required.

The CLI copies `LLM_API_KEY` onto `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, and the other names in `_KNOWN_PROVIDER_KEYS` (`openkb/cli.py`). The REST path does not. It passes `LLM_API_KEY` into `LitellmModel`. The chart sets `LLM_API_KEY` only.

### Not environment variables

`openkb/config.py` `DEFAULT_CONFIG`:

```yaml
model: gpt-5.4
language: en
pageindex_threshold: 20
```

Model ids are LiteLLM strings. OpenAI models may omit the provider prefix. Others use `provider/model` (documented in the upstream README and `examples/configuration`).

`kbDefaults` in the chart writes a `config.yaml` and mounts it at `/tmp/config.yaml`. `initialize_kb` copies `Path.cwd()/config.yaml` into a new KB when the init request does not set `model`.

OAuth providers named in the CLI are `chatgpt` and `github_copilot`. They do not use an API key. The chart does not configure a device-code login.

## HTTP surface

There is no `/health`, `/ready`, `/healthz`, or `/readyz` in the server package. A repository search of `*.py` and `*.md` at this tag only hits the wiki path `reports/health.md` in a test, which is not an HTTP route.

Real unauthenticated routes:

- `GET /openapi.json`
- `GET /docs` and `/redoc` (FastAPI defaults)
- `GET /` when the Workbench bundle is installed

`/api/v1/*` uses `require_bearer_token`. Comparison is `hmac.compare_digest`. A missing or wrong token is HTTP 401 when `OPENKB_API_TOKEN` is set. When it is unset, the dependency returns immediately and the startup log warns that the API is unauthenticated.

The chart probes `/openapi.json` because it is a real route that returns 200 without putting the bearer token into the Pod spec. It does not prove that a knowledge base is writable or that an LLM is reachable.

`examples/rest-api/README.md` says `openkb-web` warns when bound to a non-loopback host without a token. In this tag, `main()` does not check the host. The warning is in the FastAPI lifespan and fires whenever `OPENKB_API_TOKEN` is unset, regardless of bind address.

## Container image

Upstream `publish.yml` builds the Workbench, builds a Python distribution, and publishes it to PyPI. It does not build or push a container image. There is no Dockerfile in the tag. `https://hub.docker.com/v2/repositories/vectifyai/openkb/` returned 404. The public GitHub container page for `VectifyAI/OpenKB` returned 404. Other Docker Hub repositories named `openkb` are different projects.

The image in this repository is community packaging of the PyPI wheel. See [image.md](image.md).

## License

`pyproject.toml` declares Apache-2.0. The upstream `LICENSE` appendix is `Copyright 2026 Vectify AI`. This chart repository is also Apache-2.0, for the chart, Dockerfile, and docs, and does not relicense OpenKB. See the repository `NOTICE`.
