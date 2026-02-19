#!/usr/bin/env bash
set -euo pipefail

DIR="${1:-.}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need openssl
need awk
need sed
need tr
need date

shopt -s nullglob

printf "\nCERT INVENTORY: %s\n" "$(cd "$DIR" && pwd)"
printf "%-32s %-20s %-20s %-11s %s\n" "FILE" "NOT BEFORE (UTC)" "NOT AFTER (UTC)" "FP(last4)" "SANS (DNS)"
printf "%-32s %-20s %-20s %-11s %s\n" "--------------------------------" "--------------------" "--------------------" "----------" "---------"

for f in "$DIR"/*.pem; do
  # skip non-x509 PEMs (keys, etc.)
  if ! openssl x509 -in "$f" -noout >/dev/null 2>&1; then
    continue
  fi

  base="$(basename "$f")"

  # Dates
  nb_raw="$(openssl x509 -in "$f" -noout -startdate | sed 's/^notBefore=//')"
  na_raw="$(openssl x509 -in "$f" -noout -enddate   | sed 's/^notAfter=//')"

  nb="$(date -u -d "$nb_raw" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$nb_raw")"
  na="$(date -u -d "$na_raw" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$na_raw")"

  # Fingerprint -> last 4 bytes (XX:XX:XX:XX)
  fp_full="$(openssl x509 -in "$f" -noout -fingerprint -sha256 | sed 's/^.*=//')"
  fp="${fp_full: -11}"

  # SANs (DNS only), compact comma-separated
  sans="$(
    openssl x509 -in "$f" -noout -ext subjectAltName 2>/dev/null \
      | tr '\n' ' ' \
      | sed 's/.*X509v3 Subject Alternative Name:[[:space:]]*//; s/[[:space:]]*//g'
  )"

  # Fallback parse if ext output differs
  if [[ -z "${sans// }" ]]; then
    sans="$(
      openssl x509 -in "$f" -noout -text 2>/dev/null \
        | awk '
          /X509v3 Subject Alternative Name/ {in_san=1; next}
          in_san && /^[[:space:]]*X509v3/ {in_san=0}
          in_san {print}
        ' \
        | tr '\n' ' ' \
        | sed 's/[[:space:]]//g'
    )"
  fi

  # Keep only DNS entries and strip DNS:
  sans_clean="$(echo "$sans" \
    | tr ',' '\n' \
    | sed -n 's/^DNS://p' \
    | paste -sd',' - \
    | sed 's/,$//'
  )"

  max_sans=70
  if (( ${#sans_clean} > max_sans )); then
    sans_short="${sans_clean:0:max_sans}…"
  else
    sans_short="$sans_clean"
  fi

  printf "%-32s %-20s %-20s %-11s %s\n" \
    "$base" "$nb" "$na" "$fp" "$sans_short"

  if [[ "$sans_short" != "$sans_clean" ]]; then
    printf "%-32s %-20s %-20s %-11s %s\n" "" "" "" "" "SANS(full): $sans_clean"
  fi
done

printf "\nDETAILS (Subject / Issuer)\n"
printf "%-32s %-44s %-44s\n" "FILE" "SUBJECT" "ISSUER"
printf "%-32s %-44s %-44s\n" "--------------------------------" "--------------------------------------------" "--------------------------------------------"

for f in "$DIR"/*.pem; do
  if ! openssl x509 -in "$f" -noout >/dev/null 2>&1; then
    continue
  fi
  base="$(basename "$f")"
  subj="$(openssl x509 -in "$f" -noout -subject | sed 's/^subject=//')"
  issr="$(openssl x509 -in "$f" -noout -issuer  | sed 's/^issuer=//')"
  printf "%-32s %-44.44s %-44.44s\n" "$base" "$subj" "$issr"
done

echo
