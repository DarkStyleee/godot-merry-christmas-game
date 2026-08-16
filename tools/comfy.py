# -*- coding: utf-8 -*-
"""
Тонкая обвязка к ComfyUI: отправить граф, дождаться, забрать результат.

Использование:
    python tools/comfy.py sdxl  item_coal "prompt..."
    python tools/comfy.py wan   santa_spin  assets/raw/santa_c2.png
"""
import json
import os
import shutil
import sys
import time
import urllib.parse
import urllib.request
import uuid

HOST = "http://127.0.0.1:8188"
COMFY = r"D:\Program\ComfyUI_windows_portable\ComfyUI"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "assets", "raw")
CLIENT = str(uuid.uuid4())


def post(graph):
    body = json.dumps({"prompt": graph, "client_id": CLIENT}).encode()
    req = urllib.request.Request(HOST + "/prompt", body,
                                 {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req))["prompt_id"]


def wait(pid, timeout=1800):
    t0 = time.time()
    while time.time() - t0 < timeout:
        with urllib.request.urlopen(HOST + "/history/" + pid) as r:
            h = json.load(r)
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("completed") or st.get("status_str") == "success":
                return h[pid]["outputs"]
            if st.get("status_str") == "error":
                raise RuntimeError(json.dumps(st)[:600])
        time.sleep(2)
    raise TimeoutError("ComfyUI не ответил за %d с" % timeout)


def fetch(outputs, prefix):
    """Скачивает все картинки из выходов, кладёт в assets/raw как prefix_NN.png."""
    saved = []
    n = 0
    for node in outputs.values():
        for im in node.get("images", []):
            q = urllib.parse.urlencode({"filename": im["filename"],
                                        "subfolder": im.get("subfolder", ""),
                                        "type": im.get("type", "output")})
            data = urllib.request.urlopen(HOST + "/view?" + q).read()
            name = "%s.png" % prefix if len(saved) == 0 and n == 0 else "%s_%02d.png" % (prefix, n)
            path = os.path.join(RAW, name)
            with open(path, "wb") as f:
                f.write(data)
            saved.append(path)
            n += 1
    return saved


# --------------------------------------------------------------- графы ----
NEG = ("photo, photorealistic, 3d render, gradient shading, soft shading, blurry, "
       "grainy, text, letters, watermark, signature, frame, border, multiple objects, "
       "sticker, white outline, white border, drop shadow, vignette, dark background, "
       "textured background, gradient background")


def graph_sdxl(prompt, w=1024, h=1024, steps=8, cfg=2.0, seed=12345):
    return {
        "1": {"class_type": "CheckpointLoaderSimple",
              "inputs": {"ckpt_name": "dreamshaperXL_lightningDPMSDE.safetensors"}},
        "2": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["1", 1], "text": prompt}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["1", 1], "text": NEG}},
        "4": {"class_type": "EmptyLatentImage",
              "inputs": {"width": w, "height": h, "batch_size": 1}},
        "5": {"class_type": "KSampler",
              "inputs": {"model": ["1", 0], "positive": ["2", 0], "negative": ["3", 0],
                         "latent_image": ["4", 0], "seed": seed, "steps": steps,
                         "cfg": cfg, "sampler_name": "dpmpp_sde", "scheduler": "karras",
                         "denoise": 1.0}},
        "6": {"class_type": "VAEDecode", "inputs": {"samples": ["5", 0], "vae": ["1", 2]}},
        "7": {"class_type": "SaveImage", "inputs": {"images": ["6", 0], "filename_prefix": "cc"}},
    }


def graph_wan(image_name, prompt, w=512, h=512, length=25, steps=20, cfg=5.0, seed=7):
    """Wan 2.2 TI2V-5B: из одной картинки короткий ролик, дальше режем на кадры."""
    return {
        "1": {"class_type": "UnetLoaderGGUF",
              "inputs": {"unet_name": "Wan2.2-TI2V-5B-Q8_0.gguf"}},
        "2": {"class_type": "CLIPLoader",
              "inputs": {"clip_name": "umt5_xxl_fp8_e4m3fn_scaled.safetensors",
                         "type": "wan"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "wan2.2_vae.safetensors"}},
        "4": {"class_type": "LoadImage", "inputs": {"image": image_name}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": prompt}},
        "6": {"class_type": "CLIPTextEncode",
              "inputs": {"clip": ["2", 0],
                         "text": "camera movement, zoom, background change, blur, "
                                 "realistic, 3d, extra characters, morphing"}},
        "7": {"class_type": "Wan22ImageToVideoLatent",
              "inputs": {"vae": ["3", 0], "width": w, "height": h,
                         "length": length, "batch_size": 1, "start_image": ["4", 0]}},
        "8": {"class_type": "ModelSamplingSD3", "inputs": {"model": ["1", 0], "shift": 8.0}},
        "9": {"class_type": "KSampler",
              "inputs": {"model": ["8", 0], "positive": ["5", 0], "negative": ["6", 0],
                         "latent_image": ["7", 0], "seed": seed, "steps": steps,
                         "cfg": cfg, "sampler_name": "uni_pc", "scheduler": "simple",
                         "denoise": 1.0}},
        "10": {"class_type": "VAEDecode", "inputs": {"samples": ["9", 0], "vae": ["3", 0]}},
        "11": {"class_type": "SaveImage",
               "inputs": {"images": ["10", 0], "filename_prefix": "wan"}},
    }


def main():
    mode = sys.argv[1]
    name = sys.argv[2]
    if mode == "sdxl":
        g = graph_sdxl(sys.argv[3])
    elif mode == "wan":
        src = sys.argv[3]
        dst = os.path.join(COMFY, "input", os.path.basename(src))
        shutil.copy(os.path.abspath(src), dst)
        prompt = sys.argv[4] if len(sys.argv) > 4 else (
            "the cartoon santa claus tumbles and flails his arms and legs in mid air, "
            "flat 2d cartoon animation, thick black outline, solid magenta background, "
            "static camera, character stays centered and the same size")
        g = graph_wan(os.path.basename(src), prompt)
    else:
        raise SystemExit("режимы: sdxl | wan")

    pid = post(g)
    print("отправлено:", pid)
    out = wait(pid)
    for p in fetch(out, name):
        print("  ->", os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
