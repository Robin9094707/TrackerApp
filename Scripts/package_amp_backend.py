"""Build the self-contained AMP entrypoint without changing its environment ID."""
from pathlib import Path
import argparse
import hashlib

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
args = parser.parse_args()
prefix = (root / 'Backend/amp_bootstrap.py').read_bytes()
backend = (root / 'Backend/tracker_backend.py').read_bytes()
content = prefix + b'\n' + backend
compile(content, str(args.output), 'exec')
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_bytes(content)
print(f'{args.output.name}: {len(content)} bytes; SHA256 {hashlib.sha256(content).hexdigest()}')
