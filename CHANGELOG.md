# Changelog

## 0.1.0 - 2026-11-05

First community release of the OpenKB Helm chart.

- Packages upstream OpenKB `0.5.0rc1` (git tag `v0.5.0-rc1`), the first
  published release that includes the REST API and Knowledge Workbench.
  The latest stable tag `v0.4.5` is CLI-only and is not what this chart runs.
- No official container image exists. `docker/Dockerfile` installs the PyPI
  release, including the Workbench files already built into the wheel.
- Authentication is on by default via `OPENKB_API_TOKEN`.
- Knowledge-base data is stored on a PersistentVolumeClaim that Helm uninstall
  does not delete.
