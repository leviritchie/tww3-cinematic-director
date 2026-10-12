# Builds silvaron_overlord.pack (PFH5 mod pack, uncompressed) from the script/ and ui/ folders.
import os, struct, sys, time
root = os.path.dirname(os.path.abspath(__file__))
files = []
for d, _, names in [w for top in ('script', 'ui') for w in os.walk(os.path.join(root, top))]:
    for n in names:
        full = os.path.join(d, n)
        rel = os.path.relpath(full, root).replace('/', chr(92))
        files.append((rel, open(full, 'rb').read()))
files.sort()
index = b''.join(struct.pack('<I', len(data)) + b'\x00' + rel.encode('utf8') + b'\x00' for rel, data in files)
header = struct.pack('<4s6I', b'PFH5', 3, 0, 0, len(files), len(index), int(time.time()))
out = os.path.join(root, 'silvaron_overlord.pack')
with open(out, 'wb') as f:
    f.write(header + index + b''.join(data for _, data in files))
print(out, [r for r, _ in files])
