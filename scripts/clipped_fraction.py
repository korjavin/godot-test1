"""How much of a hero's FACE is blown out to white, as a number.

Bead godot-test1-z3e.14 (the authored faces clipped to paper white; the owner
could not make out a nose or a pair of lips). The fix was judged on this, not on
opinion: the fraction of face pixels whose Rec.709 luma is >= `THRESHOLD` in a
`17_head_face` frame. Run it again the day anyone touches a hero palette,
`scripts/toon_shading.gd` or the environment block in `scenes/main.tscn` — those
three are the only things that can move it.

    # take the frames first (WINDOWED, one at a time, bounded — --headless hangs)
    perl -e 'alarm 600; exec @ARGV' godot --path . scenes/style_shots.tscn \
        -- /tmp/after/windman_fp hero=windman only=17_head_face hide=weather,fauna
    perl -e 'alarm 600; exec @ARGV' godot --rendering-method gl_compatibility \
        --path . scenes/style_shots.tscn -- /tmp/after/windman_web \
        hero=windman only=17_head_face hide=weather,fauna web
    # teibi's face is on the skinned body: add `body=skinned`
    python3 scripts/clipped_fraction.py windman /tmp/after/windman_fp/17_head_face.png
    python3 scripts/clipped_fraction.py 0.377,0.489,0.498,0.636 frame.png   # own rect

THE RECT IS THE WHOLE TRICK. It is given in FRACTIONS of the frame, so it follows
the framing at any resolution, and each hero's is chosen to lie ENTIRELY INSIDE
the face — no sky, no ground, no collar. The printed fraction is then exactly
"how much of the face is clipped" with nothing to argue about, and the same rect
must be used before and after or the comparison means nothing. `17_head_face`
frames crown-relative, so these three hold for any build of these heroes.

No PIL on the machine this was written for, hence the ~40 lines of zlib below;
`Image.get_pixel` in GDScript would have been the other way round.
"""

import struct
import sys
import zlib

# Rec.709 luma on the DISPLAYED (sRGB-encoded) pixel, which is what an eye
# judges, and the level above which a face has stopped showing its shape.
THRESHOLD = 0.97

# hero -> (x0, y0, x1, y1) as fractions of the frame; see the module docstring.
FACE_RECTS = {
    "windman": (0.377, 0.489, 0.498, 0.636),
    "primm": (0.445, 0.533, 0.570, 0.689),
    "teibi": (0.460, 0.498, 0.600, 0.711),
}


def read_rgb(path):
    """(width, height, channels, pixels) from an 8-bit RGB/RGBA PNG."""
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "%s is not a PNG" % path
    pos, idat, width, height, nch = 8, b"", 0, 0, 3
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, ctype = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and ctype in (2, 6), "8-bit RGB/RGBA only"
            nch = 3 if ctype == 2 else 4
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = width * nch
    out = bytearray(height * stride)
    prev = bytearray(stride)
    at = 0
    for y in range(height):
        # PNG filters, per scanline (0 none, 1 sub, 2 up, 3 average, 4 paeth).
        f = raw[at]
        at += 1
        line = bytearray(raw[at:at + stride])
        at += stride
        if f == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                left = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                c = prev[i - nch] if i >= nch else 0
                b = prev[i]
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, nch, out


def measure(path, rect, threshold=THRESHOLD):
    """(clipped fraction, mean luma, pixel count) inside `rect`."""
    width, height, nch, px = read_rgb(path)
    x0, x1 = int(rect[0] * width), int(rect[2] * width)
    y0, y1 = int(rect[1] * height), int(rect[3] * height)
    clipped, total, n = 0, 0.0, 0
    for y in range(y0, y1):
        row = y * width * nch
        for x in range(x0, x1):
            i = row + x * nch
            luma = (0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2]) / 255.0
            total += luma
            n += 1
            if luma >= threshold:
                clipped += 1
    assert n, "empty rect"
    return clipped / n, total / n, n


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: clipped_fraction.py <hero|x0,y0,x1,y1> <png>...")
    key = sys.argv[1]
    if key in FACE_RECTS:
        rect = FACE_RECTS[key]
    else:
        rect = tuple(float(v) for v in key.split(","))
        assert len(rect) == 4, "rect is x0,y0,x1,y1 as fractions of the frame"
    for path in sys.argv[2:]:
        clipped, mean, n = measure(path, rect)
        print("%s  clipped=%.4f mean=%.4f n=%d rect=%s"
              % (path, clipped, mean, n, ",".join("%.3f" % v for v in rect)))


if __name__ == "__main__":
    main()
