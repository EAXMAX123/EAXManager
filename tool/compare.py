from PIL import Image, ImageChops
import io, urllib.request, hashlib, math

def stats(a, b, label):
    if a.size != b.size:
        print(label, 'SIZE MISMATCH', a.size, b.size); return
    diff = ImageChops.difference(a, b).convert('L')
    hist = diff.histogram()
    nonzero = sum(hist[1:]); total = a.size[0]*a.size[1]
    print('%s: diff pixels %.2f%%, max %d' % (label, 100.0*nonzero/total, max(diff.getextrema())))

# 重新下载原始 webp
url = 'https://cdn-msp.jmapinodeudzn.net/media/photos/1474516/00001.webp'
req = urllib.request.Request(url, headers={'user-agent':'Mozilla/5.0 (Linux; Android 9)','X-Requested-With':'com.JMComic3.app'})
data = urllib.request.urlopen(req, timeout=30).read()
py_raw = Image.open(io.BytesIO(data)).convert('RGB')
dart_raw = Image.open('tool/_probe_out/raw_00001.png').convert('RGB')
dart_fixed = Image.open('tool/_probe_out/fixed_00001.png').convert('RGB')
py_fixed = Image.open('tool/_probe_out/py_fixed_00001.png').convert('RGB')

print('--- 解码器差异对照（同一张原图，PIL vs Dart）---')
stats(py_raw, dart_raw, 'raw  PIL vs Dart')
print('--- 还原结果对照 ---')
stats(py_fixed, dart_fixed, 'fixed PIL vs Dart')
print('--- 还原是否真的改变结构 ---')
stats(py_raw, py_fixed, 'PIL raw vs PIL fixed')
stats(dart_raw, dart_fixed, 'Dart raw vs Dart fixed')

# 逐行均值差异，定位差异是否集中在条带边界
import statistics
w, h = py_fixed.size
rows = []
for y in range(h):
    pa = py_fixed.crop((0, y, w, y+1)); pb = dart_fixed.crop((0, y, w, y+1))
    d = ImageChops.difference(pa, pb).convert('L')
    rows.append(sum(i*c for i, c in enumerate(d.histogram()))/w)
worst = sorted(range(h), key=lambda y: -rows[y])[:10]
print('逐行差异最大的 10 行:', sorted(worst))
