# x509_rotation_demo

An Ansible Automation Platform (AAP) 2.6 demo that rotates x509 SAN certificates from a pre-built bundle, builds a SAN→cert map, and deploys the matching cert/key to hosts discovered via dynamic AWS inventory. The plays are intended to run as AAP workflow nodes; the static inventory file is only for quick local smoke tests.

## Quick start (local smoke test)
- Ensure Ansible collections: `ansible-galaxy collection install community.crypto`.
- Run the map builder locally: `ansible-playbook -i inventory create_san_cert_map.yaml`.
- Run the Apache deploy play using the published map (from the prior job or by exporting `cert_map` in your environment): `ansible-playbook -i inventory cert_rotation_apache.yaml`.

## How this fits AAP 2.6
- Dynamic inventories: In AAP, inventories are AWS dynamic sources; the `inventory` file here is a minimal stand-in for local runs.
- Workflow: Typical workflow nodes are (1) Build SAN map, (2) Deploy certs to hosts. The first node publishes `cert_map` via `set_stats`; the second node consumes that fact.
- Execution Environment: Use an EE that contains `community.crypto` and OpenSSL tooling (required by `x509_certificate_info`).

## Repository layout
- [create_san_cert_map.yaml](create_san_cert_map.yaml): Gathers SAN certs from a bundle, validates matching keys, reads SANs with `community.crypto.x509_certificate_info`, fails on duplicates, and publishes `cert_map` via `set_stats` for downstream workflow steps.
- [process_cert_info.yaml](process_cert_info.yaml): Helper tasks included by the map builder to reject duplicate SANs and build `cert_map` entries `{cert, key}` per SAN.
- [cert_rotation_apache.yaml](cert_rotation_apache.yaml): Target-side deploy play. Looks up the host’s FQDN/inventory name in `cert_map`, copies cert/key to system paths, regenerates a JSON info file for the demo page, and reloads `httpd` (ignored if absent).
- [inventory](inventory): Minimal static inventory for local smoke testing only. In AAP, replace with dynamic AWS inventory.
- [certs/](certs): Certificate material used by the demo.
	- `cert_bundle/2026-rotation/`: Example bundle containing `*_san_cert.pem` and matching keys.
	- `cert_config/`: OpenSSL configs for issuing demo certs.
	- `demoCA/`: OpenSSL CA state (index, serial, newcerts, private, etc.).
	- `regen_certs.sh`: Helper to regenerate demo certs/bundle.
- [assets/hosts/apache/](assets/hosts/apache/): Host-side artifacts for the Apache demo.
	- `generate_certinfo.sh`: Script run on the host to dump certificate metadata into `/var/www/html/certinfo.json` for the demo page.
	- `ssl.conf`: Example vhost SSL config (not automatically deployed; reference only).
	- `index.html`: Placeholder for a demo landing page.
	- `setup_new_web_server.yaml`: Placeholder (empty) for host bootstrap tasks if needed.
- [execution_environments/](execution_environments/): Placeholder for EE definitions if you choose to commit them.
- [.vscode/](.vscode/): Editor settings (optional).

## Expected workflow (AAP)
1) Map build job: run `create_san_cert_map.yaml` against localhost. It publishes `cert_map` via `set_stats`. Bundle location is `certs/cert_bundle/2026-rotation` by default; override `bundle_dir` if needed.
2) Deploy job: run `cert_rotation_apache.yaml` against your dynamic AWS inventory. It consumes `cert_map` from workflow context, copies the matching cert/key for each host, and reloads Apache.

## Variables of interest
- `bundle_dir` (in map builder): Path to the cert bundle containing `*_san_cert.pem` and matching `*_san_key.pem` files.
- `tls_cert_path`, `tls_key_path` (deploy play): Destination paths on target hosts (defaults: `/etc/pki/tls/certs/server.pem`, `/etc/pki/tls/private/server.key`).
- `cert_map`: Published fact mapping SAN→`{cert, key}`; produced by map builder, consumed by deploy play.

## Operational notes
- Duplicate SANs are rejected during map build to avoid ambiguity.
- Map build fails fast if any key is missing, or a cert lacks DNS SANs.
- Deploy play ignores Apache reload failures so non-Apache hosts don’t block the workflow.
- The demo uses PEM files on the controller; adjust `copy` tasks if you store artifacts elsewhere (e.g., Controller-wide project storage or private automation hub).

## Testing tips
- To simulate multiple hosts locally, duplicate entries in `inventory` and map SANs accordingly in your bundle.
- Use `ansible-playbook -i inventory create_san_cert_map.yaml -e bundle_dir=...` to point at alternate bundles.
- After deployment, check `/var/www/html/certinfo.json` on the target host to verify the deployed cert metadata.