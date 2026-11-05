{{/*
Expand the name of the chart.
*/}}
{{- define "openkb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
Truncate at 63 chars because some Kubernetes name fields are limited to that.
*/}}
{{- define "openkb.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "openkb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "openkb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openkb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "openkb.labels" -}}
helm.sh/chart: {{ include "openkb.chart" . }}
{{ include "openkb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: server
app.kubernetes.io/part-of: openkb
{{- end -}}

{{- define "openkb.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "openkb.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Image reference. image.digest wins over tag. Empty tag falls back to appVersion.
*/}}
{{- define "openkb.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}
{{- end -}}

{{/*
Knowledge-base root. Must stay on the data volume.
*/}}
{{- define "openkb.kbRoot" -}}
{{- printf "%s/%s" (trimSuffix "/" .Values.persistence.mountPath) .Values.persistence.kbSubPath -}}
{{- end -}}

{{/*
HOME. OpenKB stores ~/.config/openkb via Path.home(); it does not read XDG_CONFIG_HOME.
*/}}
{{- define "openkb.home" -}}
{{- printf "%s/%s" (trimSuffix "/" .Values.persistence.mountPath) .Values.persistence.homeSubPath -}}
{{- end -}}

{{- define "openkb.claimName" -}}
{{- if .Values.persistence.existingClaim -}}
{{- .Values.persistence.existingClaim -}}
{{- else -}}
{{- printf "%s-data" (include "openkb.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Recreate when the data volume is ReadWriteOnce so a second pod is not scheduled
before the volume is released. Explicit updateStrategy.type always wins.
*/}}
{{- define "openkb.strategyType" -}}
{{- if .Values.updateStrategy.type -}}
{{- .Values.updateStrategy.type -}}
{{- else if and .Values.persistence.enabled (has "ReadWriteOnce" .Values.persistence.accessModes) -}}
Recreate
{{- else -}}
RollingUpdate
{{- end -}}
{{- end -}}

{{/*
Render a chart-managed Secret only when we are not delegating to an existing
Secret and there is something to store (the API token and/or LLM keys).
*/}}
{{- define "openkb.createSecret" -}}
{{- if not .Values.auth.existingSecret -}}
{{- if or (not .Values.auth.allowUnauthenticated) .Values.llm.apiKey .Values.llm.pageindexApiKey -}}
true
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Name of the Secret the pod should read. Empty when auth is explicitly disabled
and no chart-managed keys exist.
*/}}
{{- define "openkb.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else if include "openkb.createSecret" . -}}
{{- include "openkb.fullname" . -}}
{{- end -}}
{{- end -}}

{{/*
Key inside the Secret that holds the bearer token.
Chart-managed Secrets always use the env var name. existingSecret may rename it.
*/}}
{{- define "openkb.tokenKey" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.tokenKey -}}
{{- else -}}
OPENKB_API_TOKEN
{{- end -}}
{{- end -}}

{{/*
Bearer token for the chart-managed Secret.

Precedence:
  1. auth.token (explicit; stable across upgrades; stored in the Helm release Secret)
  2. lookup of an existing Secret's OPENKB_API_TOKEN (stable when Helm can read the cluster)
  3. randAlphaNum 32

lookup returns nothing for `helm template` and for `--dry-run=client`, so those
commands mint a new token on every render. Do not apply that output over an
existing release. Prefer auth.existingSecret in production.
*/}}
{{- define "openkb.apiToken" -}}
{{- if .Values.auth.token -}}
{{- .Values.auth.token -}}
{{- else -}}
{{- $name := include "openkb.fullname" . -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace $name -}}
{{- $raw := "" -}}
{{- if and $existing $existing.data -}}
{{- $raw = index $existing.data "OPENKB_API_TOKEN" | default "" -}}
{{- end -}}
{{- if $raw -}}
{{- $raw | b64dec -}}
{{- else -}}
{{- randAlphaNum 32 -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
True when the operator set any project-root KB default. Those values are written
to cwd/config.yaml, which initialize_kb copies into a new knowledge base.
*/}}
{{- define "openkb.kbDefaultsEnabled" -}}
{{- if or .Values.kbDefaults.model .Values.kbDefaults.language (kindIs "int" .Values.kbDefaults.pageindexThreshold) (kindIs "float64" .Values.kbDefaults.pageindexThreshold) -}}
true
{{- end -}}
{{- end -}}
