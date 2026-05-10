#!/usr/bin/env bash
# Reads terraform output JSON from stdin, strips sensitive values, writes to stdout.
# Usage: terraform output -json | bash scripts/sanitize-outputs.sh
set -euo pipefail

python3 - << 'PYEOF'
import sys, json, re

data = json.load(sys.stdin)

def sanitize(obj):
    if isinstance(obj, dict):
        if obj.get('sensitive') is True:
            return {**obj, 'value': '<redacted>'}
        return {k: sanitize(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [sanitize(i) for i in obj]
    if isinstance(obj, str):
        # Redact AWS account IDs (12-digit numbers)
        obj = re.sub(r'\b\d{12}\b', '<account-id>', obj)
        # Redact JWT-like tokens
        obj = re.sub(r'eyJ[a-zA-Z0-9_-]{20,}', '<token>', obj)
    return obj

print(json.dumps(sanitize(data), indent=2))
PYEOF
