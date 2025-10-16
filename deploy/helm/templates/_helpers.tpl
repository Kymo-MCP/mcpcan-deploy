{{/*
Expand the name of the chart.
*/}}
{{- define "mcp-box.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "mcp-box.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mcp-box.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mcp-box.labels" -}}
helm.sh/chart: {{ include "mcp-box.chart" . }}
{{ include "mcp-box.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mcp-box.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mcp-box.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Get image tag
*/}}
{{- define "mcp-box.imageTag" -}}
{{- if .tag }}
{{- .tag }}
{{- else }}
{{- $.Values.global.version }}
{{- end }}
{{- end }}

{{/*
Get full image name
*/}}
{{- define "mcp-box.image" -}}
{{- if $.Values.global.registry }}
{{- printf "%s/%s:%s" $.Values.global.registry .repository (include "mcp-box.imageTag" .) }}
{{- else }}
{{- printf "%s:%s" .repository (include "mcp-box.imageTag" .) }}
{{- end }}
{{- end }}