# Contributing

This repository is a community Helm chart for OpenKB. Changes here should deploy upstream OpenKB, not fork it.

Maintainers are the owners of this Git repository. There is no CODEOWNERS file, because this project does not invent GitHub usernames.

## What belongs here

- Chart templates, values, tests, and docs.
- The Dockerfile that installs a published OpenKB release.
- CI that lints and renders the chart.

## What does not

- Application features. Those belong in [VectifyAI/OpenKB](https://github.com/VectifyAI/OpenKB).
- A copied tree of the OpenKB source.
- Credentials, tokens, or realistic API keys. Use empty strings or obviously fake placeholders such as `replace-me`.

## Before you open a pull request

```bash
./scripts/test.sh
```

The chart uses Helm chart API `v2`. It was tested with Helm 4.0.4. CI installs that same Helm, `helm unittest` v0.8.2, and kubeconform v0.6.7. The script still checks renders if the plugin is missing, and it says so.

If you change the Dockerfile, build it:

```bash
docker build -f docker/Dockerfile -t openkb:0.5.0rc1 .
```

Do not claim a cluster install worked unless you ran one. `./scripts/test.sh` does not talk to a cluster.

## Chart version

`charts/openkb/Chart.yaml` `version` is this chart. `appVersion` is the upstream PyPI version, currently `0.5.0rc1`.

Bump the chart version when behavior or defaults change, and add an entry to [CHANGELOG.md](CHANGELOG.md). Releases are git tags `vX.Y.Z` matching that chart version. See the root README.

## Environment variables

Only add an environment variable that you can point at in the upstream tag this chart deploys. Quote the file. If upstream does not read it, the chart should not set it.

## Reviews

Use the pull request template. A reviewer should be able to see which upstream behavior a new value maps to.
