# Vendored chart

`chart/` is copied unmodified from
[rancher/local-path-provisioner](https://github.com/rancher/local-path-provisioner)
tag `v0.0.37`, path `deploy/chart/local-path-provisioner` (Apache-2.0, see `chart/LICENSE`).
The project does not publish a Helm repository, so the chart lives here.

To upgrade: replace `chart/` with the same path from the new tag, and bump
`LOCAL_PATH_PROVISIONER_VERSION` in `platform/versions.env`.
