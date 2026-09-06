"""Build the repo-native radar/pin icon. No fonts, downloads or third-party dependencies."""
import json
import math
import struct
import zlib
from pathlib import Path

OUT = Path('App/Resources/Assets.xcassets/AppIcon.appiconset')
SPECS = [('iphone', s, scale) for s in (20, 29, 40, 60) for scale in (2, 3)]
SPECS += [('ipad', s, scale) for s in (20, 29, 40, 76) for scale in (1, 2)]
SPECS += [('ipad', 83.5, 2), ('ios-marketing', 1024, 1)]

def blend(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))

def coverage(distance, width, pixel):
    return max(0, min(1, (width - distance) / pixel + .5))

def pin(x, y):
    # A circular head joins a triangular tip; the hole is applied separately.
    circle = math.hypot(x - .5, y - .425) - .205
    triangle = max(.46 - y, y - .795, abs(x - .5) - (.795 - y) * .60)
    return min(circle, triangle)

def color(x, y, pixel):
    glow = max(0, 1 - math.hypot(x - .22, y - .12) / 1.15)
    rgb = blend((5, 14, 34), (17, 73, 99), glow)
    radius = math.hypot(x - .5, y - .49)
    for ring in (.29, .385, .48):
        alpha = coverage(abs(radius - ring), .0018, pixel) * .22
        rgb = blend(rgb, (69, 225, 229), alpha)
    rgb = blend(rgb, (0, 4, 18), coverage(pin(x, y - .023), .018, pixel) * .38)
    rgb = blend(rgb, (242, 253, 255), coverage(pin(x, y), 0, pixel))
    hole = math.hypot(x - .5, y - .425)
    rgb = blend(rgb, (9, 46, 65), coverage(hole, .092, pixel))
    rgb = blend(rgb, (77, 231, 218), coverage(hole, .047, pixel))
    # One small satellite dot gives the otherwise quiet mark an orbit.
    rgb = blend(rgb, (77, 231, 218), coverage(math.hypot(x - .78, y - .23), .019, pixel))
    return bytes(round(max(0, min(255, v))) for v in rgb)

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)

def write_png(path, n):
    rows = [b'\0' + b''.join(color((x + .5) / n, (y + .5) / n, 1 / n) for x in range(n)) for y in range(n)]
    # Opaque RGB: iOS supplies the rounded mask itself.
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', n, n, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b''))

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    images = []
    for idiom, size, scale in SPECS:
        filename = f'Icon-{size}-{scale}-{idiom}.png'
        write_png(OUT / filename, round(size * scale))
        images.append(dict(idiom=idiom, size=f'{size}x{size}', scale=f'{scale}x', filename=filename))
    (OUT / 'Contents.json').write_text(json.dumps(dict(images=images, info=dict(author='xcode', version=1)), indent=2))
    print(f'Generated {len(images)} opaque AppIcon sizes')

if __name__ == '__main__':
    main()
