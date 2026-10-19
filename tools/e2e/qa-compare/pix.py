import sys,glob,re
from PIL import Image, ImageChops
sc=sys.argv[1]
for a in sorted(glob.glob(f'shots/{sc}-next-*.png'), key=lambda x:int(re.search(r'next-(\d+)-',x).group(1))):
    b=a.replace('-next-','-vue-')
    try: im1=Image.open(a).convert('RGB'); im2=Image.open(b).convert('RGB')
    except Exception as e: print('missing',b); continue
    if im1.size!=im2.size: print('SIZE',a); continue
    bb=ImageChops.difference(im1,im2).getbbox(); print('same ' if bb is None else 'PIXDIFF',a.split('-next-')[1],bb or '')
