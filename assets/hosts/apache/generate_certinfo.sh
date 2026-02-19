#!/bin/bash

CERT="/etc/pki/tls/certs/server.pem"
OUT="/var/www/html/certinfo.json"

openssl x509 -in "$CERT" -noout -text > /tmp/cert.txt

SUBJECT=$(openssl x509 -in "$CERT" -noout -subject | sed 's/subject=//')
ISSUER=$(openssl x509 -in "$CERT" -noout -issuer | sed 's/issuer=//')
SERIAL=$(openssl x509 -in "$CERT" -noout -serial | sed 's/serial=//')
NOTBEFORE=$(openssl x509 -in "$CERT" -noout -startdate | cut -d= -f2)
NOTAFTER=$(openssl x509 -in "$CERT" -noout -enddate | cut -d= -f2)
SHA256=$(openssl x509 -in "$CERT" -noout -fingerprint -sha256 | cut -d= -f2)
SHA1=$(openssl x509 -in "$CERT" -noout -fingerprint -sha1 | cut -d= -f2)
PUBKEY=$(openssl x509 -in "$CERT" -noout -text | grep "Public-Key" | head -1 | sed 's/.*Public-Key: //')
SIGALG=$(openssl x509 -in "$CERT" -noout -text | grep "Signature Algorithm" | head -1 | awk -F: '{print $2}' | xargs)

CN=$(openssl x509 -in "$CERT" -noout -subject | sed -n 's/.*CN *= *\([^,/]*\).*/\1/p')

SANS=$(openssl x509 -in "$CERT" -noout -text | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/DNS://g')

IFS=',' read -ra SAN_ARRAY <<< "$SANS"

printf '{\n' > $OUT
printf '  "subject": "%s",\n' "$SUBJECT" >> $OUT
printf '  "issuer": "%s",\n' "$ISSUER" >> $OUT
printf '  "serial": "%s",\n' "$SERIAL" >> $OUT
printf '  "not_before": "%s",\n' "$NOTBEFORE" >> $OUT
printf '  "not_after": "%s",\n' "$NOTAFTER" >> $OUT
printf '  "fingerprint_sha256": "%s",\n' "$SHA256" >> $OUT
printf '  "fingerprint_sha1": "%s",\n' "$SHA1" >> $OUT
printf '  "public_key": "%s",\n' "$PUBKEY" >> $OUT
printf '  "signature_algorithm": "%s",\n' "$SIGALG" >> $OUT
printf '  "common_name": "%s",\n' "$CN" >> $OUT
printf '  "sans": [' >> $OUT

first=1
for san in "${SAN_ARRAY[@]}"; do
  san=$(echo $san | xargs)
  if [ $first -eq 0 ]; then printf ',' >> $OUT; fi
  printf '"%s"' "$san" >> $OUT
  first=0
done

printf ']\n}\n' >> $OUT
