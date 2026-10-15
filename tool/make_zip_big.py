"""生成 1000 张图的测试包，用于压测单包规模下的读取表现。"""
import os
import random
import zipfile

OUT = r"D:\project\archive_lens\tool\_fixtures"
os.makedirs(OUT, exist_ok=True)
zpath = os.path.join(OUT, "test_1000.zip")

random.seed(11)

with zipfile.ZipFile(zpath, "w", compression=zipfile.ZIP_DEFLATED) as z:
    for i in range(1000):
        name = "vol%02d/page_%04d.jpg" % (i % 10, i)
        # 30KB 左右、不可压缩的随机内容（模拟真实 jpeg 数据）
        data = b"\xff\xd8\xff\xe0" + random.randbytes(30000)
        z.writestr(name, data)

print("created", zpath, os.path.getsize(zpath) // 1024, "KB, 1000 entries")
