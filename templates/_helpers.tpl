{{/*
Expand the name of the chart.
*/}}
{{- define "capvcd-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "capvcd-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "capvcd-cluster.labels" -}}
helm.sh/chart: {{ include "capvcd-cluster.chart" . }}
{{ include "capvcd-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "capvcd-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "capvcd-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
VCD credentials secret name — defaults to Release.Name
*/}}
{{- define "capvcd-cluster.identitySecretName" -}}
{{- default .Release.Name .Values.capvcd.identitySecretName }}
{{- end }}

{{/*
Read the ClusterConfig secret value
*/}}
{{- define "capvcd-cluster.clusterConfig" -}}
{{- tpl (.Files.Get .Values.clusterConfigFile) . | b64enc | quote }}
{{- end }}

{{/*
etcd external CA cert
*/}}
{{- define "capvcd-cluster.etcd.caCrt" -}}
{{- if .Values.etcd.external.caCrt }}
{{- .Files.Get .Values.etcd.external.caCrt | b64enc | quote }}
{{- end }}
{{- end }}

{{/*
etcd external client cert
*/}}
{{- define "capvcd-cluster.etcd.apiCrt" -}}
{{- if .Values.etcd.external.apiCrt }}
{{- .Files.Get .Values.etcd.external.apiCrt | b64enc | quote }}
{{- end }}
{{- end }}

{{/*
etcd external client key
*/}}
{{- define "capvcd-cluster.etcd.apiKey" -}}
{{- if .Values.etcd.external.apiKey }}
{{- .Files.Get .Values.etcd.external.apiKey | b64enc | quote }}
{{- end }}
{{- end }}

{{/*
Raw encryption key material (32 chars). Same contract as backend/cluster-manager/capsm:
  Secret.data["secret"] (after decode) == raw key
  EncryptionConfiguration aescbc.keys[].secret == base64(raw key)
Cached in Values._encryptionKey for one helm render so Secret and NCI always match.
*/}}
{{- define "capvcd-cluster.encryptionKeyMaterial" -}}
{{- if not .Values._encryptionKey -}}
{{- $key := "" -}}
{{- $secretName := printf "%s-encryption-configuration" .Release.Name -}}
{{- $existing := lookup "v1" "Secret" .Release.Name $secretName -}}
{{- if and $existing $existing.data $existing.data.secret -}}
{{- $key = index $existing.data "secret" | b64dec -}}
{{- else -}}
{{- $key = sha256sum (printf "%s-encryption-key" .Release.Name) | trunc 32 -}}
{{- end -}}
{{- $_ := set .Values "_encryptionKey" $key -}}
{{- end -}}
{{- .Values._encryptionKey -}}
{{- end -}}

{{/*
Backward-compatible alias: raw key material (NOT base64).
*/}}
{{- define "capvcd-cluster.encryptionKey" -}}
{{- include "capvcd-cluster.encryptionKeyMaterial" . -}}
{{- end -}}

{{/*
Content of /etc/kubernetes/secrets_encryption.yaml — format matches cluster-manager
pkg/nodeconfig/generator/security.go encryptionConfiguration().
*/}}
{{- define "capvcd-cluster.secretsEncryptionContent" -}}
---
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
          - name: key1
            secret: {{ include "capvcd-cluster.encryptionKeyMaterial" . | b64enc }}
    - identity: {}
{{- end -}}

{{/*
Generate nci.json (ShturvalInit) as base64-encoded JSON.
Usage: include "capvcd-cluster.nci.json.b64" (dict "ctx" . "controlplane" true)
*/}}
{{- define "capvcd-cluster.nci.json.b64" -}}
{{- $ctx := .ctx -}}
{{- $nciCtx := dict
  "Values"       $ctx.Values
  "Files"        $ctx.Files
  "Release"      $ctx.Release
  "Chart"        $ctx.Chart
  "controlplane" .controlplane
-}}
{{- tpl ($ctx.Files.Get "conf/nci.yaml") $nciCtx | fromYaml | toJson | b64enc -}}
{{- end }}

{{/*
Generate monitoringid
*/}}
{{- define "capvcd-cluster.monitoringid" -}}
{{ adler32sum .Release.Name | int }}
{{- end }}

{{/*
Minimal KubeletConfiguration YAML — base64-encoded for injection via preKubeadmCommands.
*/}}
{{- define "capvcd-cluster.kubelet.b64" -}}
{{- $cfg := `---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
serverTLSBootstrap: true
protectKernelDefaults: true
` -}}
{{- $cfg | b64enc }}
{{- end }}

{{/*
kube-apiserver extra args.
*/}}
{{- define "capvcd-cluster.apiserver" -}}
extraArgs:
{{- if .Values.secure }}
- name: audit-log-maxage
  value: "30"
- name: audit-log-maxbackup
  value: "10"
- name: audit-log-maxsize
  value: "100"
- name: audit-log-mode
  value: batch
- name: audit-log-path
  value: /var/log/kube-api-audit/audit.log
- name: audit-policy-file
  value: "{{ .Values.auditPolicy.location }}"
- name: encryption-provider-config
  value: /etc/kubernetes/secrets_encryption.yaml
{{- end }}
- name: authorization-mode
  value: Node,RBAC
- name: default-not-ready-toleration-seconds
  value: "30"
- name: default-unreachable-toleration-seconds
  value: "30"
- name: kubelet-certificate-authority
  value: /etc/kubernetes/pki/ca.crt
- name: profiling
  value: "false"
- name: request-timeout
  value: 60s
- name: tls-min-version
  value: VersionTLS13
{{- end }}

{{/*
kube-controller-manager extra args
*/}}
{{- define "capvcd-cluster.controllerManager" -}}
controllerManager:
  extraArgs:
  - name: bind-address
    value: 0.0.0.0
  - name: node-monitor-grace-period
    value: 20s
  - name: node-monitor-period
    value: 2s
  - name: profiling
    value: "false"
  - name: terminated-pod-gc-threshold
    value: "10"
  - name: tls-min-version
    value: VersionTLS13
{{- end }}

{{/*
kube-scheduler extra args
*/}}
{{- define "capvcd-cluster.scheduler" -}}
scheduler:
  extraArgs:
  - name: bind-address
    value: 0.0.0.0
  - name: profiling
    value: "false"
{{- end }}

{{/*
Normalized kubeVersion as vX.Y.Z (for kubeTemplates keys / template.shturval.tech/*).
*/}}
{{- define "capvcd-cluster.kubeVersionKey" -}}
{{- printf "v%s" (trimPrefix "v" (.Values.kubeVersion | toString | trim)) -}}
{{- end }}

{{/*
Resolve default VCD template: capvcd.template, иначе kubeTemplates[<kubeVersion>].
*/}}
{{- define "capvcd-cluster.defaultTemplate" -}}
{{- if .Values.capvcd.template -}}
{{- .Values.capvcd.template -}}
{{- else -}}
{{- $normalizedVersion := include "capvcd-cluster.kubeVersionKey" . -}}
{{- $fromMap := get (.Values.capvcd.kubeTemplates | default dict) $normalizedVersion -}}
{{- required (printf "capvcd.template is required (or set capvcd.kubeTemplates.%s)" $normalizedVersion) $fromMap -}}
{{- end -}}
{{- end }}

{{/*
Node role label suffix for a worker group.
*/}}
{{- define "capvcd-cluster.nodeRole" -}}
{{- if eq . "default" -}}workers{{- else -}}{{ . }}{{- end -}}
{{- end }}

{{/*
Filename for a kubeadm patch in kubeadmPatches.directory.
patch.filename, otherwise kubeapi → kube-apiserver.yaml, otherwise <name>.yaml.
*/}}
{{- define "capvcd-cluster.kubeadmPatchFilename" -}}
{{- $name := .name -}}
{{- $patch := .patch | default dict -}}
{{- if $patch.filename -}}
{{- $patch.filename -}}
{{- else if eq $name "kubeapi" -}}
kube-apiserver.yaml
{{- else -}}
{{- printf "%s.yaml" $name -}}
{{- end -}}
{{- end -}}

{{/*
Effective VCD template for control plane.
*/}}
{{- define "capvcd-cluster.master.template" -}}
{{- default (include "capvcd-cluster.defaultTemplate" .) .Values.master.template }}
{{- end }}

{{/*
Effective sizing policy for control plane.
*/}}
{{- define "capvcd-cluster.master.sizingPolicy" -}}
{{- default .Values.capvcd.sizingPolicy .Values.master.sizingPolicy }}
{{- end }}

{{/*
Effective disk size for control plane.
*/}}
{{- define "capvcd-cluster.master.diskSize" -}}
{{- default .Values.capvcd.diskSize .Values.master.diskSize }}
{{- end }}

{{/*
Comma-separated sizing policies for provider annotations.
*/}}
{{- define "capvcd-cluster.sizingPolicies" -}}
{{- if .Values.capvcd.sizingPolicies }}
{{- join "," .Values.capvcd.sizingPolicies }}
{{- else if .Values.capvcd.sizingPolicy }}
{{- .Values.capvcd.sizingPolicy }}
{{- end }}
{{- end }}

{{/*
Annotations for VCD provider/credentials secrets (used by Shturval backend + CCM).
*/}}
{{- define "capvcd-cluster.providerAnnotations" -}}
shturval.tech/site: {{ required "capvcd.site is required" .Values.capvcd.site | quote }}
shturval.tech/org: {{ required "capvcd.org is required" .Values.capvcd.org | quote }}
shturval.tech/ovdc: {{ required "capvcd.ovdc is required" .Values.capvcd.ovdc | quote }}
shturval.tech/network: {{ required "capvcd.ovdcNetwork is required" .Values.capvcd.ovdcNetwork | quote }}
shturval.tech/vip-subnet: {{ .Values.capvcd.vipSubnet | quote }}
shturval.tech/catalog: {{ required "capvcd.catalog is required" .Values.capvcd.catalog | quote }}
shturval.tech/placement-policy: {{ .Values.capvcd.placementPolicy | quote }}
shturval.tech/storage-profile: {{ .Values.capvcd.storageProfile | quote }}
shturval.tech/sizing-policies: {{ include "capvcd-cluster.sizingPolicies" . | quote }}
shturval.tech/alloweditcsi: {{ .Values.capvcd.allowEditCSI | quote }}
shturval.tech/ip-pool-name: {{ .Values.capvcd.ipPoolName | quote }}
shturval.tech/template-net-interface: {{ .Values.capvcd.templateNetInterface | default "eth0" | quote }}
{{- $ver := include "capvcd-cluster.kubeVersionKey" . }}
{{- $templates := .Values.capvcd.kubeTemplates | default dict }}
{{- range $kubeVersion, $templateName := $templates }}
template.shturval.tech/{{ $kubeVersion }}: {{ $templateName | quote }}
{{- end }}
{{- /* Если для текущей kubeVersion нет явного kubeTemplates — берём capvcd.template */ -}}
{{- if and .Values.capvcd.template (not (get $templates $ver)) }}
template.shturval.tech/{{ $ver }}: {{ .Values.capvcd.template | quote }}
{{- end }}
{{- end }}

{{/*
VCDMachineSpec fields shared by CP and worker templates.
Input: dict "root" $ "diskSize" "..." "sizingPolicy" "..." "template" "..."
*/}}
{{- define "capvcd-cluster.vcdmachine.spec" -}}
{{- $root := .root -}}
catalog: {{ required "capvcd.catalog is required" $root.Values.capvcd.catalog | quote }}
template: {{ required "VCD template is required" .template | quote }}
diskSize: {{ .diskSize | quote }}
{{- if .sizingPolicy }}
sizingPolicy: {{ .sizingPolicy | quote }}
{{- end }}
{{- if $root.Values.capvcd.placementPolicy }}
placementPolicy: {{ $root.Values.capvcd.placementPolicy | quote }}
{{- end }}
{{- if $root.Values.capvcd.storageProfile }}
storageProfile: {{ $root.Values.capvcd.storageProfile | quote }}
{{- end }}
{{- if $root.Values.capvcd.enableNvidiaGPU }}
enableNvidiaGPU: {{ $root.Values.capvcd.enableNvidiaGPU }}
{{- end }}
{{- end }}

{{/*
CSI provider secret YAML blob (key "data") matching backend buildVCDCSISSC.
*/}}
{{- define "capvcd-cluster.csiConfigYaml" -}}
vcd:
  host: {{ .Values.capvcd.site | quote }}
  org: {{ .Values.capvcd.org | quote }}
  vdc: {{ .Values.capvcd.ovdc | quote }}
  vAppName: {{ .Release.Name | quote }}
auth:
  username: {{ .Values.capvcd.username | quote }}
  password: {{ .Values.capvcd.password | quote }}
  refreshToken: {{ .Values.capvcd.refreshToken | quote }}
storageClass:
  storageProfile: {{ required "capvcd.storageProfile is required when enableCSI=true" .Values.capvcd.storageProfile | quote }}
{{- end }}

{{- define "capvcd-cluster.csiSecretName" -}}
vcd-csi-config
{{- end -}}

{{- define "capvcd-cluster.csiSecretWanted" -}}
{{- $root := . -}}
{{- $name := include "capvcd-cluster.csiSecretName" $root -}}
{{- $on := false -}}
{{- if $root.Values.csi -}}
{{- range $root.Values.csi -}}
{{- if eq .serviceConfigName "shturval-capvcd-csi" -}}
{{- if not .providerSecretRef -}}
{{- $on = true -}}
{{- else if and (eq .providerSecretRef.name $name) (or (not .providerSecretRef.namespace) (eq .providerSecretRef.namespace $root.Release.Name)) -}}
{{- $on = true -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- else if $root.Values.capvcd.enableCSI -}}
{{- $on = true -}}
{{- end -}}
{{- if $on }}true{{ end -}}
{{- end -}}

{{/*
True if any workerNodes group has autoscaling.enabled.
*/}}
{{- define "capvcd-cluster.autoscalingEnabled" -}}
{{- $enabled := false -}}
{{- range $k, $v := .Values.workerNodes -}}
{{- if and $v.autoscaling $v.autoscaling.enabled -}}
{{- $enabled = true -}}
{{- end -}}
{{- end -}}
{{- $enabled -}}
{{- end -}}

{{/*
Resolve scale params for a worker MachineDeployment group.
Input: dict "root" $ "name" <groupKey> "group" <groupValues>
Output (YAML): enabled, minSize, maxMachines (if enabled), replicas

При autoscaling.enabled чарт не выставляет MachineDeployment.spec.replicas
(см. machinedeployment.yaml) — иначе helm template / helm-diff всегда
показывают drift относительно живого значения, которым владеет cluster-autoscaler.
replicas из values при этом остаётся min-size (пол автоскейлера);
фактический размер группы догоняет autoscaler (--enforce-node-group-min-size).
*/}}
{{- define "capvcd-cluster.workerGroupScale" -}}
{{- $name := .name -}}
{{- $group := .group -}}
{{- $autoscaling := $group.autoscaling | default dict -}}
{{- $enabled := $autoscaling.enabled | default false -}}
{{- $minSize := $group.replicas -}}
{{- $replicas := $group.replicas -}}
{{- if $enabled -}}
{{- $_ := required (printf "workerNodes.%s.replicas is required when autoscaling.enabled" $name) $group.replicas -}}
{{- $_ := required (printf "workerNodes.%s.autoscaling.maxMachines is required when autoscaling.enabled" $name) $autoscaling.maxMachines -}}
{{- if gt (int $minSize) (int $autoscaling.maxMachines) -}}
{{- fail (printf "workerNodes.%s.replicas (%v) must be <= autoscaling.maxMachines (%v)" $name $minSize $autoscaling.maxMachines) -}}
{{- end -}}
{{- end -}}
enabled: {{ $enabled }}
minSize: {{ $minSize }}
{{- if $enabled }}
maxMachines: {{ $autoscaling.maxMachines }}
{{- end }}
replicas: {{ $replicas }}
{{- end -}}

{{/*
cluster-autoscaler image.
Тег из профиля релиза, не из kubeVersion: 2.15.0 — v1.36.1-325745, 2.14.x — v1.35.1.
Реестр — systemregistry. Полный образ переопределяется images.clusterAutoscaler.
*/}}
{{- define "capvcd-cluster.clusterAutoscalerImage" -}}
{{- if and .Values.images .Values.images.clusterAutoscaler -}}
{{- .Values.images.clusterAutoscaler -}}
{{- else -}}
{{- $p := include "capvcd-cluster.releaseProfile" . | fromYaml -}}
{{- $tag := $p.clusterAutoscalerTag | default (printf "v%s" (include "capvcd-cluster.effectiveKubeVersion" .)) -}}
{{- printf "%s/autoscaling/cluster-autoscaler:%s" .Values.systemregistry $tag -}}
{{- end -}}
{{- end -}}

{{/*
pause image for NCI.
images.pause, иначе conf/releases, иначе nodeInit.pauseImage.
*/}}
{{- define "capvcd-cluster.pauseImage" -}}
{{- $images := .Values.images | default dict -}}
{{- if $images.pause -}}
{{- $images.pause -}}
{{- else -}}
{{- $p := include "capvcd-cluster.releaseProfile" . | fromYaml -}}
{{- if $p.pauseImage -}}
{{- $p.pauseImage -}}
{{- else -}}
{{- $ni := .Values.nodeInit | default dict -}}
{{- required "images.pause (или профиль релиза, или nodeInit.pauseImage) is required" $ni.pauseImage -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Профиль релиза: conf/releases/<shturvalReleaseVersion>.yaml.
Явные values важнее. Профиль нужен для полей, которых не было в 2.14 (CoreDNS),
и как запасной источник, если kubeVersion пустой.
*/}}
{{- define "capvcd-cluster.releaseProfile" -}}
{{- $ver := .Values.shturvalReleaseVersion | default "2.15.0" -}}
{{- $path := printf "conf/releases/%s.yaml" $ver -}}
{{- $raw := .Files.Get $path -}}
{{- if not $raw -}}
{{- fail (printf "нет профиля релиза %s (%s). Ожидаются 2.14.0, 2.14.1 или 2.15.0" $ver $path) -}}
{{- end -}}
{{- $raw -}}
{{- end -}}

{{- define "capvcd-cluster.effectiveKubeVersion" -}}
{{- if .Values.kubeVersion -}}
{{- .Values.kubeVersion -}}
{{- else -}}
{{- (include "capvcd-cluster.releaseProfile" . | fromYaml).kubeVersion -}}
{{- end -}}
{{- end -}}

{{/*
Тег CoreDNS. Пустая строка для 2.14.x — блок dns в KubeadmControlPlane не пишется.
Переопределение: images.coreDNS.
*/}}
{{- define "capvcd-cluster.coreDNSTag" -}}
{{- if and .Values.images (index .Values.images "coreDNS") -}}
{{- index .Values.images "coreDNS" -}}
{{- else -}}
{{- $p := include "capvcd-cluster.releaseProfile" . | fromYaml -}}
{{- $p.coreDNSImageTag | default "" -}}
{{- end -}}
{{- end -}}

{{/*
Тег etcd. Явный etcd.local.imageTag важнее профиля релиза.
*/}}
{{- define "capvcd-cluster.etcdImageTag" -}}
{{- $local := .Values.etcd.local | default dict -}}
{{- if $local.imageTag -}}
{{- $local.imageTag -}}
{{- else -}}
{{- $p := include "capvcd-cluster.releaseProfile" . | fromYaml -}}
{{- required "etcd.local.imageTag (или etcdImageTag в профиле релиза) is required" $p.etcdImageTag -}}
{{- end -}}
{{- end -}}

{{/*
Списки сервисов.
Если ClusterConfig уже есть — берём списки из него (webhook запрещает правку).
Иначе values и, для controllerType=gateway, та же нормализация, что ApplyIngressControllerServiceLists.
*/}}
{{- define "capvcd-cluster.serviceLists" -}}
{{- $enabled := .Values.services.enabledservices | default (list) -}}
{{- $disabled := .Values.services.disablesservices | default (list) -}}
{{- $cc := lookup "cluster.shturval.tech/v1beta1" "ClusterConfig" .Release.Name .Release.Name -}}
{{- if and $cc $cc.spec $cc.spec.systemServicesConfig -}}
{{- $ssc := $cc.spec.systemServicesConfig -}}
{{- if hasKey $ssc "enabledServices" -}}
{{- $enabled = $ssc.enabledServices | default (list) -}}
{{- end -}}
{{- if hasKey $ssc "disabledServices" -}}
{{- $disabled = $ssc.disabledServices | default (list) -}}
{{- end -}}
{{- else -}}
{{- $gateway := eq (.Values.ingressControllerType | default "nginx") "gateway" -}}
{{- $install := "shturval-ingress-controller" -}}
{{- $remove := "shturval-gateway-api-crds" -}}
{{- if $gateway -}}
{{- $install = "shturval-gateway-api-crds" -}}
{{- $remove = "shturval-ingress-controller" -}}
{{- end -}}
{{- $newEnabled := list -}}
{{- $hasInstall := false -}}
{{- range $enabled -}}
{{- if ne . $remove -}}
{{- $newEnabled = append $newEnabled . -}}
{{- if eq . $install }}{{- $hasInstall = true }}{{- end -}}
{{- end -}}
{{- end -}}
{{- if not $hasInstall -}}
{{- $newEnabled = append $newEnabled $install -}}
{{- end -}}
{{- $enabled = $newEnabled -}}
{{- $newDisabled := list -}}
{{- $hasRemove := false -}}
{{- range $disabled -}}
{{- if ne . $install -}}
{{- $newDisabled = append $newDisabled . -}}
{{- if eq . $remove }}{{- $hasRemove = true }}{{- end -}}
{{- end -}}
{{- end -}}
{{- if and $gateway (not $hasRemove) -}}
{{- $newDisabled = append $newDisabled $remove -}}
{{- end -}}
{{- $disabled = $newDisabled -}}
{{- end -}}
enabled:
{{ toYaml $enabled | nindent 2 }}
disabled:
{{ toYaml $disabled | nindent 2 }}
{{- end -}}

{{- define "capvcd-cluster.validateIngressCerts" -}}
{{- $n := 0 -}}
{{- if .Values.ingressCert }}{{- $n = add $n 1 }}{{- end -}}
{{- if .Values.caCert }}{{- $n = add $n 1 }}{{- end -}}
{{- if .Values.acme }}
{{- if or .Values.acme.serverURL .Values.acme.rootCA .Values.acme.rootCABundle .Values.acme.email }}
{{- $n = add $n 1 }}
{{- end }}
{{- end -}}
{{- if .Values.vault }}
{{- if or .Values.vault.server .Values.vault.path .Values.vault.token .Values.vault.caBundle .Values.vault.rootCA }}
{{- $n = add $n 1 }}
{{- end }}
{{- end -}}
{{- if gt (int $n) 1 -}}
{{- fail "укажите только один способ сертификата ingress: ingressCert, caCert, acme или vault" -}}
{{- end -}}
{{- $ct := .Values.ingressControllerType | default "nginx" -}}
{{- if not (or (eq $ct "nginx") (eq $ct "gateway")) -}}
{{- fail "ingressControllerType должен быть nginx или gateway" -}}
{{- end -}}
{{- if and .Values.update .Values.update.strategy -}}
{{- if not (or (eq .Values.update.strategy "InPlace") (eq .Values.update.strategy "RollingUpdate")) -}}
{{- fail "update.strategy должен быть InPlace или RollingUpdate" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "capvcd-cluster.assertCompatibleUpgrade" -}}
{{- $cc := lookup "cluster.shturval.tech/v1beta1" "ClusterConfig" .Release.Name .Release.Name -}}
{{- if and $cc $cc.spec $cc.spec.releaseVersion -}}
{{- $live := $cc.spec.releaseVersion | toString -}}
{{- $want := .Values.shturvalReleaseVersion | toString -}}
{{- if and $live (ne $live $want) (not .Values.platformUpgrade) -}}
{{- fail (printf "ClusterConfig %s уже имеет spec.releaseVersion=%s, в values указано %s. Смена версии запускает обновление платформы. Чтобы обновить только чарт, оставьте shturvalReleaseVersion=%s. Чтобы обновить платформу, задайте platformUpgrade=true. При helm template и в Argo CD lookup пустой, проверка не срабатывает — сверяйте values с живым ClusterConfig до apply." .Release.Name $live $want $live) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "capvcd-cluster.preflight" -}}
{{- include "capvcd-cluster.validateIngressCerts" . -}}
{{- include "capvcd-cluster.assertCompatibleUpgrade" . -}}
{{- end -}}
