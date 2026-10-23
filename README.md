# capvcd-cluster

Helm chart creates a Shturval client cluster using CAPVCD (Cluster API Provider for VMware Cloud Director). The Shturval backend provider identifier is `capcd`.

## Created resources

- `Namespace` for the cluster;
- CAPI `Cluster` and CAPVCD `VCDCluster`;
- `KubeadmControlPlane`, `VCDMachineTemplate` for control plane, and a `MachineDeployment`, `KubeadmConfigTemplate`, and `VCDMachineTemplate` for every `workerNodes` group;
- cluster-namespace identity `Secret` used by CAPVCD and the Shturval CCM;
- optional provider identity `Secret` in `capvcd.credentialsNamespace` for the Shturval backend (`shturval.tech/provider: capcd`);
- `ClusterConfig`, encryption and optional external-etcd secrets, health checks and cluster-autoscaler resources.

`ClusterConfig.spec.systemServicesConfig.ccm.providerSecretRef` always references the identity secret in the cluster namespace. It configures `deployKeepAlived: false`. By default CSI is `shturval-local-csi`; set `capvcd.enableCSI: true` to render `vcd-csi-config` and use `shturval-capvcd-csi`. Set `csi` explicitly to override this selection.

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
