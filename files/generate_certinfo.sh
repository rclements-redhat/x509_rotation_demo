{% raw %}
#!/usr/bin/env bash
set -euo pipefail

CERT="/etc/pki/tls/certs/server.crt"
OUT="/var/www/html/certinfo.json"

if [[ ! -r "$CERT" ]]; then
  cat > "$OUT" <<EOF
{"error":"certificate file not readable","path":"$CERT"}
EOF
  exit 0
fi

subject="$(openssl x509 -in "$CERT" -noout -subject | sed 's/^subject= *//')"
issuer="$(openssl x509 -in "$CERT" -noout -issuer | sed 's/^issuer= *//')"
serial="$(openssl x509 -in "$CERT" -noout -serial | sed 's/^serial=//')"
not_before="$(openssl x509 -in "$CERT" -noout -startdate | cut -d= -f2)"
not_after="$(openssl x509 -in "$CERT" -noout -enddate   | cut -d= -f2)"
fp_sha256="$(openssl x509 -in "$CERT" -noout -fingerprint -sha256 | cut -d= -f2)"
fp_sha1="$(openssl x509 -in "$CERT" -noout -fingerprint -sha1 | cut -d= -f2)"
pubkey="$(openssl x509 -in "$CERT" -noout -text | awk -F'Public-Key: ' '/Public-Key:/ {print $2; exit}' | xargs || true)"
sigalg="$(openssl x509 -in "$CERT" -noout -text | awk -F': ' '/Signature Algorithm/ {print $2; exit}' | xargs || true)"
cn="$(openssl x509 -in "$CERT" -noout -subject | sed -n 's/.*CN *= *\([^,\/]*\).*/\1/p' | head -1 || true)"

# SANs array (DNS only)
mapfile -t sans < <(openssl x509 -in "$CERT" -noout -text \
  | awk '/X509v3 Subject Alternative Name/ {getline; gsub(/DNS:/,""); gsub(/, /,"\n"); print}' \
  | sed 's/^ *//;s/ *$//' \
  | awk 'NF')

json_escape() {
  python3 - <<'PY'
import json,sys
print(json.dumps(sys.stdin.read().rstrip("\n"))[1:-1])
PY
}

# Write JSON
{
  echo "{"
  echo "  \"subject\": \"$(printf "%s" "$subject" | json_escape)\","
  echo "  \"issuer\": \"$(printf "%s" "$issuer" | json_escape)\","
  echo "  \"serial\": \"$(printf "%s" "$serial" | json_escape)\","
  echo "  \"not_before\": \"$(printf "%s" "$not_before" | json_escape)\","
  echo "  \"not_after\": \"$(printf "%s" "$not_after" | json_escape)\","
  echo "  \"fingerprint_sha256\": \"$(printf "%s" "$fp_sha256" | json_escape)\","
  echo "  \"fingerprint_sha1\": \"$(printf "%s" "$fp_sha1" | json_escape)\","
  echo "  \"public_key\": \"$(printf "%s" "$pubkey" | json_escape)\","
  echo "  \"signature_algorithm\": \"$(printf "%s" "$sigalg" | json_escape)\","
  echo "  \"common_name\": \"$(printf "%s" "$cn" | json_escape)\","
  echo "  \"sans\": ["
  for i in "${!sans[@]}"; do
    comma=","
    [[ "$i" -eq $(( ${#sans[@]} - 1 )) ]] && comma=""
    echo "    \"$(printf "%s" "${sans[$i]}" | json_escape)\"$comma"
  done
  echo "  ]"
  echo "}"
} > "$OUT"

{% endraw %}