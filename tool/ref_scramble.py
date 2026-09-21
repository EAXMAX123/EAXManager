# 用 jmcomic 官方算法生成基准图，用于校验 Dart 移植
import hashlib, math, sys, urllib.request
from PIL import Image

SCRAMBLE_268850 = 268850
SCRAMBLE_421926 = 421926

def get_num(scramble_id, aid, filename):
    scramble_id = int(scramble_id); aid = int(aid)
    if aid < scramble_id:
        return 0
    elif aid < SCRAMBLE_268850:
        return 10
    else:
        x = 10 if aid < SCRAMBLE_421926 else 8
        s = f"{aid}{filename}".encode()
        s = hashlib.md5(s).hexdigest()
        num = ord(s[-1]); num %= x; num = num * 2 + 2
        return num

def decode_and_save(num, img_src, path):
    if num == 0:
        img_src.save(path); return
    w, h = img_src.size
    img_decode = Image.new("RGB", (w, h))
    over = h % num
    for i in range(num):
        move = math.floor(h / num)
        y_src = h - (move * (i + 1)) - over
        y_dst = move * i
        if i == 0:
            move += over
        else:
            y_dst += over
        img_decode.paste(img_src.crop((0, y_src, w, y_src + move)), (0, y_dst, w, y_dst + move))
    img_decode.save(path)

photo_id = sys.argv[1] if len(sys.argv) > 1 else '1474516'
img_name  = sys.argv[2] if len(sys.argv) > 2 else '00001.webp'
scramble_id = sys.argv[3] if len(sys.argv) > 3 else '220980'

domain = 'cdn-msp.jmapiproxy1.cc'
url = f'https://{domain}/media/photos/{photo_id}/{img_name}'
req = urllib.request.Request(url, headers={'user-agent':'Mozilla/5.0 (Linux; Android 9)','X-Requested-With':'com.JMComic3.app'})
data = urllib.request.urlopen(req, timeout=30).read()
print('下载字节:', len(data))

import io
img_src = Image.open(io.BytesIO(data)).convert('RGB')
print('尺寸:', img_src.size)

bare = img_name.rsplit('.', 1)[0]
num = get_num(scramble_id, photo_id, bare)
print('切割数 num =', num)

decode_and_save(num, img_src, f'tool/_probe_out/py_fixed_{bare}.png')
print('基准图已保存: tool/_probe_out/py_fixed_%s.png' % bare)
