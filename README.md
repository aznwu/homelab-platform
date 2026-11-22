# homelab-platform

[![ansible-ci](https://github.com/aznwu/homelab-platform/actions/workflows/ansible-ci.yml/badge.svg)](https://github.com/aznwu/homelab-platform/actions/workflows/ansible-ci.yml)
[![platform-ci](https://github.com/aznwu/homelab-platform/actions/workflows/platform-ci.yml/badge.svg)](https://github.com/aznwu/homelab-platform/actions/workflows/platform-ci.yml)

A small Kubernetes platform on two 2013 Mac Pros, built and tested as code.

| Layer | Tool |
|---|---|
| OS | Rocky Linux 9 (minimal) |
| Config management | Ansible (`base`, `hardening`, `rke2`) |
| CI | GitHub Actions: yamllint, ansible-lint, Molecule on Rocky 9; Helm render + kubeconform for the platform layer |
| Kubernetes | RKE2 v1.35 (CIS profile, SELinux), RPM install, Traefik ingress |
| Platform | local-path-provisioner, MetalLB (L2), cert-manager (homelab CA) — Helm, pinned in `platform/versions.env` |
| Delivery | Helm via `scripts/platform-up.sh`, then Argo CD (GitOps) — *Phase 4* |
| Monitoring | kube-prometheus-stack (Prometheus, Grafana, Alertmanager), Grafana at https://grafana.lab |

## Hardware

| Host | Role | IP |
|---|---|---|
| mac1 | Mac Pro 2013, Xeon E5 6-core, 32 GB — RKE2 server | 192.168.2.20 |
| mac2 | Mac Pro 2013 — RKE2 agent (Phase 5) | 192.168.2.21 |
| flux | MacBook Pro M1 Max — admin workstation | 192.168.2.10 |

## Layout

```
inventory/            hosts and group_vars
playbooks/site.yml    applies all roles to the lab
roles/base/           packages, chrony, timezone, SELinux enforcing, no swap
roles/hardening/      sshd drop-in, firewalld (off on RKE2 nodes)
roles/rke2/           RKE2 server: repos, CIS prerequisites, config, kubeconfig to flux
platform/             Helm values, manifests and pinned versions for cluster services
scripts/platform-up.sh  installs/upgrades the platform layer (idempotent)
molecule/default/     container tests for base + hardening (run in CI)
.github/workflows/    ansible-ci and platform-ci pipelines
```

## Usage (from flux)

```bash
ansible-galaxy collection install -r requirements.yml
ansible lab -m ping                                    # connectivity (asks for sudo password)
ansible-playbook playbooks/site.yml --check --diff     # dry run
ansible-playbook playbooks/site.yml                    # apply
ansible-playbook playbooks/site.yml --tags rke2        # RKE2 only

export KUBECONFIG=~/.kube/homelab.yaml                 # written by the rke2 role
kubectl get nodes

./scripts/platform-up.sh                               # storage, cert-manager, MetalLB, monitoring
```

Grafana: add `192.168.2.20 grafana.lab` to `/etc/hosts` on flux, then open https://grafana.lab.
The admin password is generated on first install and lives only in the cluster:
`kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d`.
Prometheus and Alertmanager have no authentication, so they are not exposed; use
`kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090`.

`ansible.cfg` sets `become_ask_pass = True`, so every run prompts for the sudo password.
Passwordless sudo is deliberately not used on the nodes.

## CI and security notes

- CI runs **only on GitHub-hosted runners**. No self-hosted runners are attached to this
  public repo, so pull requests from forks can never execute code inside the lab network.
- Fork pull request workflows require maintainer approval.
- Molecule tests config files, packages and idempotence in a systemd Rocky 9 container.
  Steps that need a real host (SELinux mode, firewalld rules, sshd reload, chronyd, timezone)
  are skipped in containers and only exercised on the nodes themselves.
- No secrets live in this repo: kubeconfigs, keys and vault passwords are git-ignored.
- firewalld is disabled on the nodes because it conflicts with RKE2's Canal networking
  (RKE2 known issues). Canal manages the kernel firewall; filtering inside the cluster is
  done with NetworkPolicies.
- RKE2 is pinned (`rke2_version` in `inventory/group_vars/rke2_servers.yml`). Its dnf repos
  are disabled outside the role, so `dnf update` never upgrades Kubernetes.
- Ingress is Traefik (RKE2's bundled `rke2-traefik`). ingress-nginx is retired upstream and is
  not deployed.
- etcd and kube-proxy metrics are exposed for Prometheus. Controller-manager and scheduler
  metrics stay on localhost to keep CIS checks 1.3.7 / 1.4.2 passing
  (`rke2_expose_control_plane_metrics` turns them on).
- The CIS profile enforces Pod Security `restricted` in every namespace except `kube-system`.
  `platform/namespaces.yaml` grants `privileged` only to `local-path-storage`, `metallb-system`
  and `monitoring`, each with the reason next to it.
- The CIS network policies in `kube-system` only allow DNS from outside the namespace;
  `platform/network-policies/` opens CoreDNS metrics to the `monitoring` namespace only.
- local-path volumes live in `/var/lib/rancher/local-path`, labelled `container_file_t` by the
  rke2 role so pods can write there with SELinux enforcing.
- MetalLB hands out `192.168.2.240-249` (outside the router's DHCP pool).

## Roadmap

- [x] Phase 0 – Rocky 9 on mac1/mac2, SSH keys, firewalld
- [x] Phase 1 – repo, base/hardening roles, CI
- [x] Phase 2 – RKE2 single node (CIS profile) via Ansible
- [x] Phase 3a – Traefik ingress, etcd/kube-proxy metrics
- [ ] Phase 3b – local-path-provisioner, MetalLB, cert-manager, kube-prometheus-stack — *in progress*
- [ ] Phase 4 – Argo CD takes over Helm releases
- [ ] Phase 5 – mac2 joins as agent, Longhorn
- [ ] Phase 6 – real workloads (CronJobs for personal bots)
