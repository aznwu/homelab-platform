# homelab-platform

[![ansible-ci](https://github.com/aznwu/homelab-platform/actions/workflows/ansible-ci.yml/badge.svg)](https://github.com/aznwu/homelab-platform/actions/workflows/ansible-ci.yml)

A small Kubernetes platform on two 2013 Mac Pros, built and tested as code.

| Layer | Tool |
|---|---|
| OS | Rocky Linux 9 (minimal) |
| Config management | Ansible (`base`, `hardening`, `rke2`) |
| CI | GitHub Actions: yamllint, ansible-lint, Molecule on Rocky 9 |
| Kubernetes | RKE2 v1.35 (CIS profile, SELinux), RPM install |
| Delivery | Helm, then Argo CD (GitOps) — *Phases 3–4* |
| Monitoring | kube-prometheus-stack (Prometheus, Grafana, Alertmanager) — *Phase 3* |

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
molecule/default/     container tests for both roles (run in CI)
.github/workflows/    ansible-ci pipeline
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
```

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
- The CIS profile enforces Pod Security `restricted` in every namespace except `kube-system`.
  Workloads that need host access (e.g. node-exporter) get explicit namespace exemptions.

## Roadmap

- [x] Phase 0 – Rocky 9 on mac1/mac2, SSH keys, firewalld
- [x] Phase 1 – repo, base/hardening roles, CI
- [ ] Phase 2 – RKE2 single node (CIS profile) via Ansible — *in progress*
- [ ] Phase 3 – local-path-provisioner, MetalLB, cert-manager, kube-prometheus-stack
- [ ] Phase 4 – Argo CD takes over Helm releases
- [ ] Phase 5 – mac2 joins as agent, Longhorn
- [ ] Phase 6 – real workloads (CronJobs for personal bots)
