"""生成用于验证 ZipReader 的测试压缩包 + 清单文件。"""
import json
import os
import random
import zipfile

OUT = r"D:\project\archive_lens\tool\_fixtures"
os.makedirs(OUT, exist_ok=True)

manifest = []
zpath = os.path.join(OUT, "test_mixed.zip")

random.seed(7)

with zipfile.ZipFile(zpath, "w", compression=zipfile.ZIP_DEFLATED) as z:
    # 1) 300 张"图片"（PNG 头 + 随机 payload，部分内容可压缩）
    for i in range(300):
        name = "folder%02d/img_%04d.png" % (i % 5, i)
        payload = bytes([i % 256]) * (500 + (i * 37) % 4000)
        data = b"\x89PNG\r\n\x1a\n" + payload
        ct = zipfile.ZIP_STORED if i % 10 == 0 else zipfile.ZIP_DEFLATED
        z.writestr(name, data, compress_type=ct)
        manifest.append({"name": name, "size": len(data)})
    # 2) 非图片文件（应被过滤掉）
    z.writestr("readme.txt", b"not an image" * 10)
    # 3) 中文文件名 + UTF-8 flag
    z.writestr("中文目录/图片_测试_001.jpg", b"\xff\xd8\xff\xe0" + b"A" * 1234)
    manifest.append({"name": "中文目录/图片_测试_001.jpg", "size": 1238})
    # 4) 目录条目
    z.writestr("emptydir/", b"")

with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=1)

print("created", zpath, os.path.getsize(zpath), "bytes")
print("entries", len(manifest))
