import sys
from pathlib import Path
from PIL import Image, ImageDraw
d=Path(sys.argv[1]); names=sys.argv[2:]
W=384; im=Image.new("RGB",(W*3, W*len(names)),(255,255,255)); dr=ImageDraw.Draw(im)
for r,n in enumerate(names):
    for k in range(3):
        im.paste(Image.open(d/f"{n}_v{k}.png").convert("RGB"),(W*k,W*r))
    dr.text((6,W*r+6),n,fill=(0,0,0))
im.save(d/"sheet.png")
