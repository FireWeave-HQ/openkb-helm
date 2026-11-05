# Community packaging image for OpenKB.
# Upstream does not publish a container image. This image installs the
# published PyPI release (Knowledge Workbench extra included) and does not
# fork the application.
#
# Build:
#   docker build -f docker/Dockerfile -t openkb:0.5.0rc1 .

FROM python:3.12-slim-bookworm

ARG OPENKB_VERSION=0.5.0rc1
# Versions locked by upstream uv.lock at git tag v0.5.0-rc1.
# The openkb package itself leaves the web extra unpinned.
ARG FASTAPI_VERSION=0.139.0
ARG UVICORN_VERSION=0.47.0
ARG PYTHON_MULTIPART_VERSION=0.0.30
# openkb 0.5.0rc1 pins json-repair==0.59.10 and litellm==1.87.2. Both are
# fixable HIGH findings. litellm 1.95.0 is still HIGH (GHSA-7hp6-4w63-5g45,
# fixed in 1.100.4), so the override is the first release that clears both.
# A single resolver solve cannot select openkb and these releases together.
ARG JSON_REPAIR_VERSION=0.60.1
ARG LITELLM_VERSION=1.100.4

LABEL org.opencontainers.image.title="openkb" \
      org.opencontainers.image.description="Community image for the OpenKB REST API and Knowledge Workbench" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${OPENKB_VERSION}" \
      org.opencontainers.image.documentation="https://github.com/VectifyAI/OpenKB/blob/v0.5.0-rc1/examples/rest-api/README.md"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1000 openkb \
    && useradd --uid 1000 --gid 1000 --create-home --home-dir /home/openkb openkb \
    && pip install \
        "openkb[web]==${OPENKB_VERSION}" \
        "fastapi==${FASTAPI_VERSION}" \
        "uvicorn==${UVICORN_VERSION}" \
        "python-multipart==${PYTHON_MULTIPART_VERSION}" \
    && pip uninstall -y openkb \
    && pip install \
        "json-repair==${JSON_REPAIR_VERSION}" \
        "litellm==${LITELLM_VERSION}" \
    && pip install --no-deps "openkb==${OPENKB_VERSION}" \
    && python -c "import json_repair, litellm, openkb.cli"

USER 1000:1000
WORKDIR /tmp

EXPOSE 7566

# Upstream has no /health. /openapi.json is served by FastAPI and is not behind the bearer token.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:7566/openapi.json')"

ENTRYPOINT ["openkb-web"]
CMD ["--host", "0.0.0.0", "--port", "7566"]
