#!/usr/bin/env bash
set -euo pipefail

# --- Settings (edit these if you want) ---
WEB_DNS_1="web1.demo.local"
WEB_DNS_2="web2.demo.local"
IIS_DNS_1="iis1.demo.local"
IIS_DNS_2="iis2.demo.local"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_CREATION_DIR="${BASE_DIR}/cert_config"
BUNDLE_BASE_DIR="${BASE_DIR}/cert_bundle"
OLD_DIR="${BUNDLE_BASE_DIR}/2025-current"
NEW_DIR="${BUNDLE_BASE_DIR}/2026-rotation"
CA_DIR="${BASE_DIR}/demoCA"

RSA_BITS=2048

# --- Helpers ---
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }

write_req_cnf() {
  local path="$1"
  local cn="$2"
  local dns1="$3"
  local dns2="$4"

  cat > "$path" <<EOF
[req]
prompt = no
default_bits = ${RSA_BITS}
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
CN = ${cn}

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${dns1}
DNS.2 = ${dns2}
EOF
}

make_ca_if_missing() {
  if [[ -f "${CA_DIR}/certs/ca.crt" && -f "${CA_DIR}/private/ca.key" && -f "${CA_DIR}/openssl.cnf" ]]; then
    return
  fi

  echo "==> Creating demo CA in ${CA_DIR}"
  mkdir -p "${CA_DIR}"/{certs,crl,newcerts,private}
  chmod 700 "${CA_DIR}/private"
  : > "${CA_DIR}/index.txt"
  echo 1000 > "${CA_DIR}/serial"

  cat > "${CA_DIR}/openssl.cnf" <<'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ./demoCA
database          = $dir/index.txt
new_certs_dir     = $dir/newcerts
serial            = $dir/serial
private_key       = $dir/private/ca.key
certificate       = $dir/certs/ca.crt
default_md        = sha256
policy            = policy_loose
x509_extensions   = usr_cert
copy_extensions   = copy
unique_subject    = no

[ policy_loose ]
commonName              = supplied

[ usr_cert ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "${CA_DIR}/private/ca.key" \
    -out "${CA_DIR}/certs/ca.crt" \
    -subj "/CN=Demo Rotation CA"
}

sign_with_ca() {
  local csr="$1"
  local out_cert="$2"
  local start="$3"
  local end="$4"

  # openssl ca writes into ./demoCA relative to where it's run due to config paths.
  ( cd "${BASE_DIR}" && \
    openssl ca -batch -config demoCA/openssl.cnf \
      -in "$csr" -out "$out_cert" \
      -startdate "$start" -enddate "$end" >/dev/null
  )
}

gen_pair() {
  local out_dir="$1"          # e.g. certs/cert_bundle/2025-current
  local prefix="$2"           # web or iis
  local cnf="$3"              # path to req config
  local start="$4"
  local end="$5"

  mkdir -p "$out_dir"

  local key="${out_dir}/${prefix}_san_key.pem"
  local csr="${out_dir}/${prefix}.csr"
  local cert="${out_dir}/${prefix}_san_cert.pem"

  echo "==> Generating ${prefix} key+csr"
  openssl req -new -nodes -newkey "rsa:${RSA_BITS}" \
    -keyout "$key" -out "$csr" \
    -config "$cnf" >/dev/null

  echo "==> Signing ${prefix} cert (start=${start}, end=${end})"
  sign_with_ca "$csr" "$cert" "$start" "$end"

  rm -f "$csr"
}

verify_cert() {
  local cert="$1"
  echo "---- $cert"
  openssl x509 -in "$cert" -noout -dates
  openssl x509 -in "$cert" -noout -ext subjectAltName || true
  echo
}

# --- Main ---
need_cmd openssl
need_cmd date

echo "==> Writing request configs into ${CERT_CREATION_DIR}"
mkdir -p "${CERT_CREATION_DIR}"

HTTPD_CNF="${CERT_CREATION_DIR}/httpd.cnf"
IIS_CNF="${CERT_CREATION_DIR}/iis.cnf"

write_req_cnf "${HTTPD_CNF}" "${WEB_DNS_1}" "${WEB_DNS_1}" "${WEB_DNS_2}"
write_req_cnf "${IIS_CNF}"   "${IIS_DNS_1}" "${IIS_DNS_1}" "${IIS_DNS_2}"

make_ca_if_missing

# Dates:
OLD_START="$(date -u -d "1 year ago" +"%Y%m%d%H%M%SZ")"
OLD_END="$(date -u -d "14 days" +"%Y%m%d%H%M%SZ")"

NEW_START="$(date -u +"%Y%m%d%H%M%SZ")"
NEW_END="$(date -u -d "365 days" +"%Y%m%d%H%M%SZ")"

echo "==> Regenerating OLD (expiring soon) bundle: ${OLD_DIR}"
rm -rf "${OLD_DIR}"
gen_pair "${OLD_DIR}" "web" "${HTTPD_CNF}" "${OLD_START}" "${OLD_END}"
gen_pair "${OLD_DIR}" "iis" "${IIS_CNF}"   "${OLD_START}" "${OLD_END}"

echo "==> Regenerating NEW (rotation) bundle: ${NEW_DIR}"
rm -rf "${NEW_DIR}"
gen_pair "${NEW_DIR}" "web" "${HTTPD_CNF}" "${NEW_START}" "${NEW_END}"
gen_pair "${NEW_DIR}" "iis" "${IIS_CNF}"   "${NEW_START}" "${NEW_END}"

# Copy CA cert into bundle dirs (useful for demo trust/validation)
cp -f "${CA_DIR}/certs/ca.crt" "${OLD_DIR}/demo_ca.crt"
cp -f "${CA_DIR}/certs/ca.crt" "${NEW_DIR}/demo_ca.crt"

echo "==> Verifying output"
verify_cert "${OLD_DIR}/web_san_cert.pem"
verify_cert "${OLD_DIR}/iis_san_cert.pem"
verify_cert "${NEW_DIR}/web_san_cert.pem"
verify_cert "${NEW_DIR}/iis_san_cert.pem"

echo "==> Done."
echo "Old bundle (expires ~2 weeks): ${OLD_DIR}"
echo "New bundle (valid 1 year):     ${NEW_DIR}"
echo "CA cert:                       ${CA_DIR}/certs/ca.crt"

