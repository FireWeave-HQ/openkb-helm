# Security

## Reporting

Report a vulnerability in this Helm chart, Dockerfile, or CI privately with [GitHub private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) on this repository.

Please do not open a public issue for an unfixed vulnerability.

There is no bug bounty.

Vulnerabilities in OpenKB itself should be reported to the upstream project, [VectifyAI/OpenKB](https://github.com/VectifyAI/OpenKB).

## Defaults that matter

- `OPENKB_API_TOKEN` is set unless `auth.allowUnauthenticated` is explicitly true. Upstream treats a missing token as an open API.
- API keys are not rendered into ConfigMaps.
- The container is non-root, with a read-only root filesystem, all capabilities dropped, and `RuntimeDefault` seccomp.
- The chart does not mount the ServiceAccount token.
- `helm template` can print a generated token. Prefer `auth.existingSecret`, and do not commit rendered manifests.

`/openapi.json` and `/docs` are not behind the bearer token. That is how the FastAPI app is written. Network policy and ingress are how you keep that document off the public internet.
