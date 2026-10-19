import sys
from PIL import Image, ImageChops
a=Image.open(sys.argv[1]).convert('RGB');b=Image.open(sys.argv[2]).convert('RGB')
print('diffbbox',ImageChops.difference(a,b).getbbox())
im=Image.new('RGB',(a.width+b.width,max(a.height,b.height)));im.paste(a,(0,0));im.paste(b,(a.width,0));im.save(sys.argv[3])
