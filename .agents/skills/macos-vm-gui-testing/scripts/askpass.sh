#!/bin/sh
# SSH invokes this only for an explicitly configured local credential file.
exec "$MESHCHAN_VM_PYTHON" -c '
import json, os, sys
from pathlib import Path
if len(sys.argv) != 2 or "password" not in sys.argv[1].lower():
    sys.exit(1)
path = Path(os.environ["MESHCHAN_VM_CREDENTIALS"])
if path.is_symlink() or path.stat().st_uid != os.getuid() or path.stat().st_mode & 0o077:
    sys.exit(1)
print(json.loads(path.read_text())["password"])
' "$@"
