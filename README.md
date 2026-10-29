# capvcd-cluster

Helm chart creates a Shturval client cluster using CAPVCD (Cluster API Provider for VMware Cloud Director). The Shturval backend provider identifier is `capcd`.

## Created resources

- `Namespace` for the cluster;
- CAPI `Cluster` and CAPVCD `VCDCluster`;
- `KubeadmControlPlane`, `VCDMachineTemplate` for control plane, and a `MachineDeployment`, `KubeadmConfigTemplate`, and `VCDMachineTemplate` for every `workerNodes` group;
- cluster-namespace identity `Secret` used by CAPVCD and the Shturval CCM;
- optional provider identity `Secret` in `capvcd.credentialsNamespace` for the Shturval backend (`shturval.tech/provider: capcd`);
- `ClusterConfig`, encryption and optional external-etcd secrets, health checks and cluster-autoscaler resources.

`ClusterConfig.spec.systemServicesConfig.ccm.providerSecretRef` always references the identity secret in the cluster namespace. It configures `deployKeepAlived: false`. By default CSI is `shturval-local-csi`. Set `capvcd.enableCSI: true` to use `shturval-capvcd-csi`: the chart creates Secret `vcd-csi-config` in the cluster namespace from `capvcd` credentials and points `providerSecretRef` at it. A `csi` list overrides that selection; for `shturval-capvcd-csi` the secret reference is still filled in when omitted.

## Required CAPVCD values

Set `capvcd.org`, `capvcd.ovdc`, `capvcd.ovdcNetwork`, `capvcd.catalog`, and a VM template through `capvcd.template` or `capvcd.kubeTemplates`. Supply credentials with `username`/`password` or `refreshToken`. `site` defaults to an example URL and must also be changed for real use.

Machine sizing uses `diskSize`, `sizingPolicy`, and `template`; they can be overridden globally, in `master`, or per worker group. CAPVCD does not use OpenStack-style availability zones or `MachineDeployment.failureDomain` here.

## Install

```sh
helm dependency build ./capvcd-cluster
helm upgrade --install my-cluster ./capvcd-cluster \
  --namespace my-cluster --create-namespace -f my-values.yaml
```

For a rendering smoke test:

```sh
helm template test-cluster ./capvcd-cluster -f ./capvcd-cluster/values-test.yaml
```

## Обновление чарта с 2.14 на 2.15

Чарт `2.15` ставит новый кластер Штурвала **2.15.0** (Kubernetes 1.36.5).
Уже работающий кластер 2.14 этим чартом обновляется только как Helm-релиз:
машины не пересоздаются и обновление платформы не стартует, если values
по-прежнему описывают 2.14.

1. Сначала обновите менеджмент-кластер до Штурвала 2.15 (CRD `InfrastructureProvider`, CAPI v1beta2). Потом обновляйте чарты клиентских кластеров.
2. Возьмите values, которыми кластер ставился (`helm get values <release> -n <namespace> -o yaml`), а не дефолты нового чарта.
3. Не используйте `--reuse-values` вслепую и не подставляйте голый `--reset-values`: новый чарт по умолчанию содержит `shturvalReleaseVersion: 2.15.0`, `kubeVersion: 1.36.5`, новые теги etcd, pause и kube-vip. Для обновления только чарта оставьте прежние версии.
4. Предпочтительно `helm upgrade --reset-then-reuse-values` вместе с файлом старых values, затем `helm diff upgrade` (если плагин установлен) или `helm template` / `helm upgrade --dry-run`.
5. `shturvalReleaseVersion` меняйте только вместе с `platformUpgrade: true`. Иначе при живом кластере чарт останавливает рендер: смена `spec.releaseVersion` запускает обновление платформы. `helm template` и Argo CD не видят объекты кластера (`lookup` пустой), поэтому проверку нужно сделать до apply.
6. `enabledServices` и `disabledServices` у существующего ClusterConfig чарт не переписывает: webhook запрещает их менять, списки читаются из живого объекта.
7. `InfrastructureProvider` создаётся только если CRD уже есть (`infrastructureProvider.create: auto`) и объект с тем же именем не принадлежит другому релизу. Нативные секреты и аннотации `shturval.tech/*` чарт не удаляет: они нужны менеджмент-кластеру 2.14 и миграции 2.15.
8. Поле `services.disablesservices` — явный список. Значение `all` в ClusterConfig не работает (его понимает только REST API backend и нельзя совместить с `enabledServices`). Некритичный сервис, которого нет ни в одном списке и у которого режим по умолчанию `auto`, будет установлен.

Платформенное обновление клиентского кластера 2.14 → 2.15 делайте отдельно, через shturval-update / `platformUpgrade: true`, а не как побочный эффект `helm upgrade`.
