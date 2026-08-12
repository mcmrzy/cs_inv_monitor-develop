# -*- coding: utf-8 -*-
"""CSERGY 抠图工具（rembg GUI 版）

基于 rembg AI 语义分割模型（u2net / isnet-general-use）的本地抠图工具：
- 单图模式：打开图片 -> 抠图 -> 预览（透明棋盘格底）-> 保存 PNG
- 批量模式：选择输入/输出目录，批量处理目录下所有常见图片格式

依赖（均已安装）:
    rembg, Pillow, tkinter（Python 自带）
模型目录: %USERPROFILE%/.u2net/（首次运行自动下载）

用法:
    python gui_cutout.py
"""
import os
import queue
import threading
import time
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageTk
from rembg import remove, new_session

# ---------- 常量 ----------

# 模型显示名 -> rembg 会话名（显示名更友好，内部名用于 new_session）
MODELS = {
    "isnet-general-use（推荐，边缘精细）": "isnet-general-use",
    "u2net（经典通用）": "u2net",
}

# 支持打开的图片格式
IMAGE_EXTS = {
    ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".tiff",
}

# 预览区最长边（像素）
PREVIEW_MAX = 420

# 放大镜：窗口边长（像素）与采样半径（原始像素）
MAG_SIZE = 140
MAG_RADIUS = 16

# 透明底棋盘格两色（浅灰/白，便于观察边缘）
CHECK_A = (255, 255, 255)
CHECK_B = (205, 205, 205)
CHECK_CELL = 10


# ---------- 工具函数 ----------

def checker_background(size, cell=CHECK_CELL, color_a=CHECK_A, color_b=CHECK_B):
    """生成透明底预览用的棋盘格背景图（RGBA，alpha=255）"""
    w, h = size
    img = Image.new("RGB", (w, h), color_a)
    px = img.load()
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            if (x // cell + y // cell) % 2:
                for yy in range(y, min(y + cell, h)):
                    for xx in range(x, min(x + cell, w)):
                        px[xx, yy] = color_b
    return img


def fit_preview(img, max_side=PREVIEW_MAX):
    """等比缩放图片用于预览，返回 (缩放图, 显示尺寸)"""
    w, h = img.size
    scale = min(1.0, max_side / max(w, h))
    if scale < 1.0:
        img = img.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
    return img


def compose_preview(rgba):
    """透明图合成棋盘格背景，生成可显示的 RGB 预览图"""
    if rgba.mode != "RGBA":
        return rgba.convert("RGB")
    bg = checker_background(rgba.size).convert("RGBA")
    return Image.alpha_composite(bg, rgba).convert("RGB")


# ---------- 单图工作区 ----------

class CutoutApp:
    def __init__(self, root):
        self.root = root
        self.root.title("CSERGY 抠图工具（rembg）")
        self.root.geometry("980x640")
        self.root.minsize(860, 540)

        # 状态
        self.session = None            # rembg 会话（懒加载）
        self.session_name = None       # 已加载的模型名
        self.src_img = None            # 原始 RGBA 图
        self.src_path = None
        self.result_img = None         # 抠图结果 RGBA
        self._previews = {}            # 保持 PhotoImage 引用防 GC
        self._busy = False             # 抠图中标记
        self.batch_win = None          # 批量窗口引用（用于回传进度）
        self._msg_queue = queue.Queue()

        # 蒙版编辑状态（numpy 数组，尺寸与图一致）
        self._base_alpha = None        # 抠图原始 alpha（不可变基线）
        self._paint_keep = None        # 保留层（255 区域强制 alpha=255）
        self._paint_erase = None       # 删除层（255 区域强制 alpha=0）
        self._last_refresh = 0.0       # 预览刷新节流时间戳
        self._src_display = None       # 原图 RGB 显示缓存（放大镜用）
        self._result_display = None    # 结果图棋盘格合成缓存（放大镜用）

        # 编辑工具变量
        self._tool_var = tk.StringVar(value="none")    # none / keep / erase
        self._brush_var = tk.IntVar(value=20)           # 笔刷直径（图像像素）
        self._feather_var = tk.IntVar(value=0)         # 羽化半径（像素）
        self._mag_on_var = tk.BooleanVar(value=False)  # 放大镜开关

        # 放大镜窗口（懒创建）
        self._mag_win = None
        self._mag_label = None
        self._mag_photo = None

        self._build_toolbar()
        self._build_edit_bar()
        self._build_previews()
        self._build_statusbar()

        # 状态栏消息队列轮询（线程安全更新 UI）
        self.root.after(100, self._drain_queue)

    # ---------- UI 构建 ----------

    def _build_toolbar(self):
        bar = ttk.Frame(self.root, padding=(8, 6))
        bar.pack(side=tk.TOP, fill=tk.X)

        ttk.Button(bar, text="打开图片…", command=self.open_image).pack(side=tk.LEFT)
        ttk.Button(bar, text="抠图", command=self.start_cutout).pack(side=tk.LEFT, padx=(8, 0))

        ttk.Label(bar, text="模型:").pack(side=tk.LEFT, padx=(16, 4))
        self.model_var = tk.StringVar(value=list(MODELS)[0])
        self.model_combo = ttk.Combobox(
            bar, textvariable=self.model_var, state="readonly",
            values=list(MODELS), width=28,
        )
        self.model_combo.pack(side=tk.LEFT)

        ttk.Button(bar, text="保存结果…", command=self.save_result).pack(side=tk.LEFT, padx=(16, 0))
        ttk.Button(bar, text="批量处理…", command=self.open_batch_window).pack(side=tk.RIGHT)

    def _build_edit_bar(self):
        bar = ttk.LabelFrame(self.root, text="结果编辑", padding=(8, 4))
        bar.pack(side=tk.TOP, fill=tk.X, padx=8)
        self._edit_bar = bar

        tk.Radiobutton(bar, text="无工具", value="none",
                       variable=self._tool_var).pack(side=tk.LEFT)
        tk.Radiobutton(bar, text="保留（涂抹恢复主体）", value="keep",
                       variable=self._tool_var).pack(side=tk.LEFT, padx=(6, 0))
        tk.Radiobutton(bar, text="删除（涂抹擦除背景）", value="erase",
                       variable=self._tool_var).pack(side=tk.LEFT, padx=(6, 0))
        tk.Label(bar, text="笔刷:").pack(side=tk.LEFT, padx=(14, 2))
        tk.Scale(bar, from_=5, to=100, orient=tk.HORIZONTAL, length=120,
                 variable=self._brush_var, showvalue=False).pack(side=tk.LEFT)
        tk.Label(bar, text="羽化:").pack(side=tk.LEFT, padx=(10, 2))
        tk.Scale(bar, from_=0, to=10, orient=tk.HORIZONTAL, length=110,
                 variable=self._feather_var, command=self._on_feather).pack(side=tk.LEFT)
        tk.Checkbutton(bar, text="放大镜", variable=self._mag_on_var).pack(side=tk.LEFT, padx=(14, 0))
        tk.Button(bar, text="重置编辑", command=self._reset_edits).pack(side=tk.LEFT, padx=(14, 0))
        tk.Label(bar, text="在右侧结果图上按住左键涂抹").pack(side=tk.RIGHT)
        self._set_edit_enabled(False)

    def _set_edit_enabled(self, enabled):
        """统一启用/禁用编辑工具条（无抠图结果时禁用）"""
        state = tk.NORMAL if enabled else tk.DISABLED
        for child in self._edit_bar.winfo_children():
            try:
                child.configure(state=state)
            except tk.TclError:
                pass

    def _build_previews(self):
        panel = ttk.Frame(self.root, padding=(8, 0))
        panel.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        for side, title in (("left", "原图"), ("right", "抠图结果")):
            frame = ttk.LabelFrame(panel, text=title, padding=4)
            frame.pack(side=side, fill=tk.BOTH, expand=True, padx=4)
            label = tk.Label(frame, bg="#e8e8e8", text="（未加载）",
                             compound=tk.CENTER, anchor=tk.CENTER)
            label.pack(fill=tk.BOTH, expand=True)
            setattr(self, "_left_label" if side == "left" else "_result_label", label)

        # 放大镜：两个预览区悬停放大
        self._left_label.bind("<Motion>", self._on_motion)
        self._left_label.bind("<Leave>", self._on_leave)
        self._result_label.bind("<Motion>", self._on_motion)
        self._result_label.bind("<Leave>", self._on_leave)
        # 涂抹：结果图上按住左键绘制
        self._result_label.bind("<Button-1>", self._on_paint)
        self._result_label.bind("<B1-Motion>", self._on_paint)

    def _build_statusbar(self):
        self.status_var = tk.StringVar(value="就绪：打开一张图片开始抠图")
        bar = ttk.Label(self.root, textvariable=self.status_var,
                        relief=tk.SUNKEN, anchor=tk.W, padding=(8, 3))
        bar.pack(side=tk.BOTTOM, fill=tk.X)

    # ---------- 状态栏与消息 ----------

    def _set_status(self, text):
        self.status_var.set(text)

    def _drain_queue(self):
        """消费后台线程发来的消息（仅主线程更新 UI）"""
        try:
            while True:
                msg = self._msg_queue.get_nowait()
                kind, payload = msg
                if kind == "status":
                    self._set_status(payload)
                elif kind == "done":
                    self.result_img = payload
                    self._busy = False
                    self._init_edits()
                    self._show_preview(self._result_label, self.result_img, transparent=True)
                    self._set_edit_enabled(True)
                    self._set_status(f"抠图完成：{self.result_img.size[0]}x{self.result_img.size[1]}，可涂抹修边/羽化后保存")
                elif kind == "error":
                    self._busy = False
                    messagebox.showerror("抠图失败", payload)
                    self._set_status("抠图失败")
                elif kind == "batch_progress":
                    if self.batch_win is not None:
                        self.batch_win._on_progress(*payload)
                elif kind == "batch_error":
                    messagebox.showerror("批量处理失败", payload)
                elif kind == "batch_finish":
                    if self.batch_win is not None:
                        self.batch_win._finish()
        except queue.Empty:
            pass
        self.root.after(100, self._drain_queue)

    # ---------- 图片加载与预览 ----------

    def open_image(self):
        path = filedialog.askopenfilename(
            title="选择图片",
            filetypes=[("图片文件", "*.png *.jpg *.jpeg *.webp *.bmp *.gif *.tiff"),
                       ("所有文件", "*.*")],
        )
        if not path:
            return
        try:
            img = Image.open(path)
            img.load()
            self.src_img = img.convert("RGBA")
            self._src_display = self.src_img.convert("RGB")
            self.src_path = path
            self.result_img = None
            self._base_alpha = None
            self._paint_keep = None
            self._paint_erase = None
            self._set_edit_enabled(False)
            self._hide_magnifier()
            self._show_preview(self._left_label, self.src_img)
            self._set_status(f"已加载：{os.path.basename(path)}（{img.size[0]}x{img.size[1]}）")
        except Exception as e:
            messagebox.showerror("打开失败", f"无法读取图片：\n{e}")

    def _show_preview(self, label, img, transparent=False):
        """显示预览（透明图叠加棋盘格背景）"""
        if transparent:
            img = compose_preview(img)
        if label is self._result_label:
            self._result_display = img
        preview = fit_preview(img)
        photo = ImageTk.PhotoImage(preview)
        self._previews[id(label)] = photo
        label.configure(image=photo, text="")

    # ---------- 抠图（后台线程） ----------

    def _get_session(self, model_internal):
        """懒加载 rembg 会话（模型首次加载约 2-5 秒）"""
        if self.session is None or self.session_name != model_internal:
            self.session = new_session(model_internal)
            self.session_name = model_internal
        return self.session

    def start_cutout(self):
        if self._busy:
            self._set_status("正在抠图中，请稍候…")
            return
        if self.src_img is None:
            messagebox.showwarning("提示", "请先打开一张图片")
            return
        model_internal = MODELS[self.model_var.get()]
        self._busy = True
        self._set_status("正在加载模型并抠图…")
        threading.Thread(target=self._cutout_worker, args=(model_internal,), daemon=True).start()

    def _cutout_worker(self, model_internal):
        """后台线程执行抠图，结果经消息队列回传主线程"""
        try:
            session = self._get_session(model_internal)
            self._msg_queue.put(("status", "AI 分割中…"))
            out = remove(self.src_img, session=session)
            self._msg_queue.put(("done", out))
        except Exception as e:
            self._msg_queue.put(("error", f"{e}"))

    # ---------- 结果蒙版编辑（涂抹 / 羽化 / 放大镜） ----------

    def _init_edits(self):
        """抠图完成时初始化蒙版编辑状态（以抠图 alpha 为基线）"""
        alpha = np.array(self.result_img.getchannel("A"), dtype=np.uint8)
        h, w = alpha.shape
        self._base_alpha = alpha
        self._paint_keep = np.zeros((h, w), dtype=np.uint8)
        self._paint_erase = np.zeros((h, w), dtype=np.uint8)

    def _rebuild_alpha(self):
        """按 基线 alpha -> 涂抹层 -> 羽化 重建结果 alpha，立即写回 result_img"""
        if self._base_alpha is None or self.result_img is None:
            return
        a = self._base_alpha.copy()
        a[self._paint_keep == 255] = 255
        a[self._paint_erase == 255] = 0
        feather = self._feather_var.get()
        if feather > 0:
            a = np.array(
                Image.fromarray(a, "L").filter(ImageFilter.GaussianBlur(feather)),
                dtype=np.uint8,
            )
        self.result_img.putalpha(Image.fromarray(a, "L"))

    def _refresh_result(self, rebuild=True):
        """重建 alpha（可选）并刷新结果预览，预览刷新带 50ms 节流"""
        if rebuild:
            self._rebuild_alpha()
        now = time.monotonic()
        if now - self._last_refresh < 0.05:
            return
        self._last_refresh = now
        self._show_preview(self._result_label, self.result_img, transparent=True)

    def _on_feather(self, _=None):
        """羽化滑块变化（无结果时忽略）"""
        if self.result_img is not None and self._base_alpha is not None:
            self._refresh_result()

    def _label_to_image_xy(self, label, x, y, img):
        """Label 坐标 -> 图像像素坐标（考虑居中与缩放），越界返回 None"""
        photo = self._previews.get(id(label))
        if photo is None or img is None:
            return None
        pw, ph = photo.width(), photo.height()
        if pw == 0 or ph == 0:
            return None
        lw = max(label.winfo_width(), 1)
        lh = max(label.winfo_height(), 1)
        ox, oy = (lw - pw) // 2, (lh - ph) // 2
        ix = int(round((x - ox) * img.width / pw))
        iy = int(round((y - oy) * img.height / ph))
        if 0 <= ix < img.width and 0 <= iy < img.height:
            return ix, iy
        return None

    def _on_paint(self, event):
        """在结果图上涂抹：keep=恢复主体，erase=擦除"""
        if self.result_img is None or self._paint_keep is None:
            return
        tool = self._tool_var.get()
        if tool not in ("keep", "erase"):
            return
        xy = self._label_to_image_xy(self._result_label, event.x, event.y, self.result_img)
        if xy is None:
            return
        ix, iy = xy
        r = self._brush_var.get() // 2
        h, w = self._paint_keep.shape
        y0, y1 = max(0, iy - r), min(h, iy + r + 1)
        x0, x1 = max(0, ix - r), min(w, ix + r + 1)
        if y0 >= y1 or x0 >= x1:
            return
        yy, xx = np.ogrid[y0:y1, x0:x1]
        mask = (xx - ix) ** 2 + (yy - iy) ** 2 <= r * r
        # 互斥语义：后涂的覆盖先涂的（keep 撤销 erase，反之亦然）
        target = self._paint_keep if tool == "keep" else self._paint_erase
        other = self._paint_erase if tool == "keep" else self._paint_keep
        target[y0:y1, x0:x1][mask] = 255
        other[y0:y1, x0:x1][mask] = 0
        self._rebuild_alpha()                # 数据立即生效（保存始终为最新）
        self._refresh_result(rebuild=False)  # 预览节流刷新

    def _reset_edits(self):
        """清空涂抹与羽化，恢复原始抠图结果"""
        if self.result_img is None:
            return
        self._paint_keep[:] = 0
        self._paint_erase[:] = 0
        self._feather_var.set(0)
        self._refresh_result()
        self._set_status("已重置编辑")

    # ---------- 放大镜 ----------

    def _ensure_magnifier(self):
        if self._mag_win is None:
            self._mag_win = tk.Toplevel(self.root)
            self._mag_win.overrideredirect(True)
            self._mag_label = tk.Label(self._mag_win, borderwidth=1, relief=tk.SOLID)
            self._mag_label.pack()
            self._mag_win.withdraw()

    def _on_motion(self, event):
        """预览区鼠标移动：按开关显示/隐藏放大镜"""
        if not self._mag_on_var.get():
            self._hide_magnifier()
            return
        label = event.widget
        if label is self._left_label:
            img, display = self.src_img, self._src_display
        else:
            img, display = self.result_img, self._result_display
        if display is None:
            self._hide_magnifier()
            return
        xy = self._label_to_image_xy(label, event.x, event.y, img)
        if xy is None:
            self._hide_magnifier()
            return
        self._show_magnifier(display, xy[0], xy[1], event.x_root, event.y_root)

    def _on_leave(self, _):
        self._hide_magnifier()

    def _show_magnifier(self, display, ix, iy, x_root, y_root):
        """跟随鼠标显示鼠标周围原始像素的放大视图（NEAREST 像素风 + 十字线）"""
        self._ensure_magnifier()
        r = MAG_RADIUS
        left, top = max(0, ix - r), max(0, iy - r)
        right, bottom = min(display.width, ix + r), min(display.height, iy + r)
        crop = display.crop((left, top, right, bottom))
        # 边缘处不足 2r 见方时居中补齐
        if crop.size != (2 * r, 2 * r):
            canvas = Image.new(crop.mode, (2 * r, 2 * r), (128, 128, 128))
            canvas.paste(crop, ((2 * r - crop.width) // 2, (2 * r - crop.height) // 2))
            crop = canvas
        crop = crop.resize((MAG_SIZE, MAG_SIZE), Image.NEAREST)
        d = ImageDraw.Draw(crop)
        d.line((MAG_SIZE // 2, 0, MAG_SIZE // 2, MAG_SIZE), fill=(255, 0, 0))
        d.line((0, MAG_SIZE // 2, MAG_SIZE, MAG_SIZE // 2), fill=(255, 0, 0))
        self._mag_photo = ImageTk.PhotoImage(crop)
        self._mag_label.configure(image=self._mag_photo)
        # 窗口跟随鼠标，贴近屏幕边缘时反向放置
        mx, my = x_root + 16, y_root + 16
        sw, sh = self.root.winfo_screenwidth(), self.root.winfo_screenheight()
        if mx + MAG_SIZE > sw:
            mx = x_root - MAG_SIZE - 16
        if my + MAG_SIZE > sh:
            my = y_root - MAG_SIZE - 16
        self._mag_win.geometry(f"+{mx}+{my}")
        self._mag_win.deiconify()

    def _hide_magnifier(self):
        if self._mag_win is not None:
            self._mag_win.withdraw()

    # ---------- 保存 ----------

    def save_result(self):
        if self.result_img is None:
            messagebox.showwarning("提示", "还没有抠图结果")
            return
        default_name = "cutout_" + os.path.splitext(os.path.basename(self.src_path or "image"))[0] + ".png"
        path = filedialog.asksaveasfilename(
            title="保存抠图结果",
            defaultextension=".png",
            initialfile=default_name,
            filetypes=[("PNG 图片", "*.png"), ("WEBP 图片", "*.webp")],
        )
        if not path:
            return
        try:
            self.result_img.save(path)
            self._set_status(f"已保存：{path}")
        except Exception as e:
            messagebox.showerror("保存失败", f"{e}")

    # ---------- 批量处理 ----------

    def open_batch_window(self):
        self.batch_win = BatchWindow(self)


# ---------- 批量处理窗口 ----------

class BatchWindow:
    def __init__(self, app):
        self.app = app
        self.win = tk.Toplevel(app.root)
        self.win.title("批量抠图")
        self.win.geometry("560x300")
        self.win.resizable(False, False)
        self.win.transient(app.root)
        self.win.protocol("WM_DELETE_WINDOW", self._on_close)

        self.in_var = tk.StringVar()
        self.out_var = tk.StringVar()
        self.model_var = tk.StringVar(value=list(MODELS)[0])
        self._running = False

        body = ttk.Frame(self.win, padding=12)
        body.pack(fill=tk.BOTH, expand=True)

        # 输入目录
        row1 = ttk.Frame(body)
        row1.pack(fill=tk.X, pady=4)
        ttk.Label(row1, text="输入目录:", width=9).pack(side=tk.LEFT)
        ttk.Entry(row1, textvariable=self.in_var).pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(row1, text="浏览…", command=self._pick_in).pack(side=tk.LEFT, padx=4)

        # 输出目录
        row2 = ttk.Frame(body)
        row2.pack(fill=tk.X, pady=4)
        ttk.Label(row2, text="输出目录:", width=9).pack(side=tk.LEFT)
        ttk.Entry(row2, textvariable=self.out_var).pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(row2, text="浏览…", command=self._pick_out).pack(side=tk.LEFT, padx=4)

        # 模型
        row3 = ttk.Frame(body)
        row3.pack(fill=tk.X, pady=4)
        ttk.Label(row3, text="模型:", width=9).pack(side=tk.LEFT)
        ttk.Combobox(row3, textvariable=self.model_var, state="readonly",
                     values=list(MODELS), width=28).pack(side=tk.LEFT)

        # 进度
        self.progress = ttk.Progressbar(body, mode="determinate")
        self.progress.pack(fill=tk.X, pady=(12, 4))
        self.progress_var = tk.StringVar(value="等待开始")
        ttk.Label(body, textvariable=self.progress_var).pack(anchor=tk.W)

        # 按钮
        btns = ttk.Frame(body)
        btns.pack(fill=tk.X, pady=(8, 0))
        self.start_btn = ttk.Button(btns, text="开始批量抠图", command=self.start)
        self.start_btn.pack(side=tk.LEFT)
        ttk.Button(btns, text="关闭", command=self.win.destroy).pack(side=tk.RIGHT)

        # 默认输出目录 = 输入目录/cutout
        self.in_var.trace_add("write", self._on_in_changed)

    def _on_close(self):
        """关闭窗口时解除与主窗口的引用（停止后续进度回传）"""
        self.app.batch_win = None
        self.win.destroy()

    def _pick_in(self):
        path = filedialog.askdirectory(title="选择输入目录")
        if path:
            self.in_var.set(path)

    def _pick_out(self):
        path = filedialog.askdirectory(title="选择输出目录")
        if path:
            self.out_var.set(path)

    def _on_in_changed(self, *_):
        if not self.out_var.get():
            self.out_var.set(os.path.join(self.in_var.get(), "cutout"))

    def start(self):
        in_dir = self.in_var.get().strip()
        out_dir = self.out_var.get().strip()
        if not in_dir or not os.path.isdir(in_dir):
            messagebox.showwarning("提示", "请选择有效的输入目录", parent=self.win)
            return
        if not out_dir:
            out_dir = os.path.join(in_dir, "cutout")
            self.out_var.set(out_dir)
        os.makedirs(out_dir, exist_ok=True)

        files = [f for f in os.listdir(in_dir)
                 if os.path.splitext(f)[1].lower() in IMAGE_EXTS]
        if not files:
            messagebox.showwarning("提示", "输入目录中没有可处理的图片", parent=self.win)
            return

        if messagebox.askyesno("确认", f"共 {len(files)} 张图片，将输出到：\n{out_dir}\n\n开始处理？", parent=self.win):
            self._running = True
            self.start_btn.configure(state=tk.DISABLED)
            self.progress.configure(maximum=len(files), value=0)
            threading.Thread(
                target=self._batch_worker,
                args=(MODELS[self.model_var.get()], in_dir, out_dir, files),
                daemon=True,
            ).start()

    def _batch_worker(self, model_internal, in_dir, out_dir, files):
        try:
            session = self.app._get_session(model_internal)
            ok = fail = 0
            for i, name in enumerate(files, 1):
                if not self._running:
                    break
                src = os.path.join(in_dir, name)
                dst = os.path.join(out_dir, os.path.splitext(name)[0] + ".png")
                try:
                    img = Image.open(src).convert("RGBA")
                    out = remove(img, session=session)
                    out.save(dst)
                    ok += 1
                except Exception:
                    fail += 1
                # 进度经队列回传主线程（避免跨线程直接操作 UI）
                self.app._msg_queue.put(("batch_progress", (i, len(files), ok, fail)))
        except Exception as e:
            self.app._msg_queue.put(("batch_error", f"{e}"))
        finally:
            self.app._msg_queue.put(("batch_finish", None))

    def _on_progress(self, i, total, ok, fail):
        self.progress.configure(value=i)
        self.progress_var.set(f"处理中 {i}/{total}（成功 {ok}，失败 {fail}）")

    def _finish(self):
        self._running = False
        self.start_btn.configure(state=tk.NORMAL)
        self.progress_var.set("批量处理完成")
        self.app._set_status("批量抠图完成")


def main():
    root = tk.Tk()
    CutoutApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
