#!/usr/bin/env bash
# Fails if any given file is not fully SOPS-encrypted. Used by pre-commit on *.sops.yaml files.
# Every "key: value" line above the trailing `sops:` metadata block must hold an ENC[...]
# value, so a plaintext value added with a normal editor is caught too.
set -euo pipefail

status=0
for f in "$@"; do
  if ! grep -q '^sops:' "$f"; then
    echo "ERROR: $f is not SOPS-encrypted. Encrypt it with: sops encrypt -i $f" >&2
    status=1
    continue
  fi
  plaintext="$(awk '
    /^sops:/ { exit }                        # metadata block starts; values above are data
    /^[[:space:]]*(#|$)/ { next }            # comments and blank lines
    /:[[:space:]]*[^[:space:]]/ && !/ENC\[AES256_GCM,/ { print NR": "$1 }
  ' "$f")"
  if [[ -n "$plaintext" ]]; then
    echo "ERROR: $f has plaintext values (keys shown, values hidden):" >&2
    echo "$plaintext" | sed 's/^/  line /' >&2
    echo "Re-encrypt with: sops encrypt -i $f  (after fixing the plaintext lines)" >&2
    status=1
  fi
done
exit "$status"
