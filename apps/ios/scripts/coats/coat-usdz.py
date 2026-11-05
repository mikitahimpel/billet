"""Copies a USDZ with its MochiColor.jpg replaced by another image: Cat.usdz in a coat, for coat-portraits.sh.

    python3 scripts/coats/coat-usdz.py Nooki/Resources/Cat.usdz Nooki/Resources/Coats/CatColor-ginger.jpg out.usdz
"""
import sys, zipfile
src, tex, out = sys.argv[1:4]
zin = zipfile.ZipFile(src)
with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as zout:
    for info in zin.infolist():
        data = open(tex, "rb").read() if info.filename == "MochiColor.jpg" else zin.read(info.filename)
        # USDZ wants every file's data 64-byte aligned: pad the local header's extra field.
        header_len = 30 + len(info.filename.encode())
        pad = (64 - (zout.fp.tell() + header_len) % 64) % 64
        zi = zipfile.ZipInfo(info.filename, info.date_time); zi.compress_type = zipfile.ZIP_STORED
        zi.extra = b"\0" * pad if pad == 0 or pad >= 4 else b"\0" * (pad + 64)
        zout.writestr(zi, data)
