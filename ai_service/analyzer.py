"""
Core image analysis engine using OpenCV for computer vision
and OpenAI GPT-4o for intelligent analysis.
"""
from __future__ import annotations
import cv2
import numpy as np
import io
import httpx
from openai import OpenAI
from typing import Optional, List
import base64
import json
import os
from PIL import Image as PILImage
import moondream as md

from prompts import (
    PROMPT_DETECCAO_VISUAL,
    PROMPT_ANALISE_TECNICA,
    PROMPT_RELATORIO,
    PROMPT_SUPRESSAO,
)

from models import (
    AnalyzeImageResponse,
    QualityMetrics,
    BoundingBox,
    CompareImagesResponse,
    GenerateSummaryResponse,
)


class ImageAnalyzer:
    """Analyzes aerial inspection photos using CV + AI."""

    def __init__(self, openai_api_key: str, moondream_api_key: str = ""):
        # Disable SSL verification for corporate networks / Python 3.9 Windows
        import ssl
        ssl_context = ssl.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE

        custom_http = httpx.Client(
            verify=False,
            timeout=httpx.Timeout(60.0, connect=15.0),
        )
        self.client = OpenAI(api_key=openai_api_key, http_client=custom_http)
        self.ssl_verify = False  # for async downloads
        
        # Initialize Moondream 3 cloud client
        self.moondream_client = None
        if moondream_api_key:
            try:
                self.moondream_client = md.vl(api_key=moondream_api_key)
                print("[Moondream] Client initialized via Cloud API")
            except Exception as e:
                print(f"[Moondream] Failed to initialize: {e}")

    async def download_image(self, url: str) -> np.ndarray:
        """Download image from URL and decode to OpenCV format."""
        async with httpx.AsyncClient(timeout=30, verify=self.ssl_verify) as client:
            response = await client.get(url)
            response.raise_for_status()
            img_array = np.frombuffer(response.content, dtype=np.uint8)
            img = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
            if img is None:
                raise ValueError(f"Could not decode image from {url}")
            return img

    def analyze_quality(self, img: np.ndarray) -> QualityMetrics:
        """Evaluate image quality: blur and exposure."""
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

        # Blur detection via Laplacian variance
        laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
        blur_score = min(100, laplacian_var / 5)  # normalize: >500 var = sharp

        # Exposure: histogram analysis
        hist = cv2.calcHist([gray], [0], None, [256], [0, 256])
        hist = hist.flatten() / hist.sum()
        # Good exposure: energy spread across histogram
        dark_pct = hist[:50].sum()
        bright_pct = hist[200:].sum()
        mid_pct = hist[50:200].sum()
        if dark_pct > 0.6:
            exposure_score = 30  # underexposed
        elif bright_pct > 0.6:
            exposure_score = 30  # overexposed
        else:
            exposure_score = min(100, mid_pct * 120)

        overall = (blur_score * 0.6 + exposure_score * 0.4)
        return QualityMetrics(
            blur_score=round(blur_score, 1),
            exposure_score=round(exposure_score, 1),
            overall=round(overall, 1),
        )

    def detect_vegetation_cv(self, img: np.ndarray) -> tuple[bool, float]:
        """Detect green vegetation using HSV color space."""
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        # Green vegetation mask
        lower_green = np.array([25, 40, 40])
        upper_green = np.array([85, 255, 255])
        mask = cv2.inRange(hsv, lower_green, upper_green)
        green_ratio = np.count_nonzero(mask) / mask.size * 100
        return green_ratio > 15, round(min(100, green_ratio * 2), 1)

    def detect_fire_signs_cv(self, img: np.ndarray) -> tuple[bool, float]:
        """Detect fire/burn marks using red-orange HSV + dark patterns."""
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        # Red-orange mask (fire/burn)
        lower_red1 = np.array([0, 80, 80])
        upper_red1 = np.array([10, 255, 255])
        lower_red2 = np.array([160, 80, 80])
        upper_red2 = np.array([180, 255, 255])
        mask1 = cv2.inRange(hsv, lower_red1, upper_red1)
        mask2 = cv2.inRange(hsv, lower_red2, upper_red2)

        # Dark/burned areas
        lower_dark = np.array([0, 0, 0])
        upper_dark = np.array([180, 80, 60])
        mask_dark = cv2.inRange(hsv, lower_dark, upper_dark)

        fire_ratio = (np.count_nonzero(mask1) + np.count_nonzero(mask2)) / mask1.size * 100
        dark_ratio = np.count_nonzero(mask_dark) / mask_dark.size * 100

        # Fire signs if significant red-orange AND dark burned areas nearby
        has_fire = fire_ratio > 5 or (fire_ratio > 2 and dark_ratio > 20)
        score = round(min(100, fire_ratio * 5 + dark_ratio * 0.5), 1)
        return has_fire, score

    _reference_cache = None  # class-level cache

    def _load_reference_images(self) -> list:
        """Load reference images from reference_images/ folder for few-shot prompting.
        
        Loads max 1 image per category, resized to 256x256 for efficiency.
        Results are cached after first load.
        """
        if ImageAnalyzer._reference_cache is not None:
            return ImageAnalyzer._reference_cache
        
        ref_dir = os.path.join(os.path.dirname(__file__), "reference_images")
        if not os.path.exists(ref_dir):
            ImageAnalyzer._reference_cache = []
            return []
        
        references = []
        category_labels = {
            "ancoragem": "ANCORAGEM (torre de ancoragem - isoladores horizontais, estrutura robusta para tração dos cabos, cruzetas mais largas)",
            "suspensao": "SUSPENSÃO (torre de suspensão - isoladores verticais pendurados, estrutura mais leve, cabos passam suspensos)",
        }
        
        for category in ["ancoragem", "suspensao"]:
            cat_dir = os.path.join(ref_dir, category)
            if not os.path.exists(cat_dir):
                continue
            files = [f for f in os.listdir(cat_dir) if f.lower().endswith(('.jpg', '.jpeg', '.png', '.webp'))]
            if not files:
                continue
            # Take only the first image per category
            fname = files[0]
            fpath = os.path.join(cat_dir, fname)
            try:
                # Read and resize to 256x256 to keep payload small
                img = cv2.imread(fpath)
                if img is not None:
                    img = cv2.resize(img, (256, 256))
                    _, buf = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 60])
                    img_b64 = base64.b64encode(buf).decode("utf-8")
                    references.append({
                        "category": category,
                        "label": category_labels.get(category, category),
                        "base64": img_b64,
                        "mime": "image/jpeg",
                        "filename": fname,
                    })
                    print(f"[few-shot] Loaded reference: {category}/{fname} (256x256)")
            except Exception as e:
                print(f"[few-shot] Failed to load {fpath}: {e}")
        
        ImageAnalyzer._reference_cache = references
        return references

    async def analyze_with_gpt4o(self, img: np.ndarray, photo_id: str, torre_codigo: str = "") -> dict:
        """Use GPT-4o vision to analyze the aerial inspection image.
        
        Uses PROMPT_DETECCAO_VISUAL + few-shot reference images for tower classification.
        """
        # Encode image to base64
        _, buffer = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 85])
        img_base64 = base64.b64encode(buffer).decode('utf-8')

        prompt = PROMPT_DETECCAO_VISUAL
        if torre_codigo:
            prompt += f"\n\nCONTEXTO: Esta é a torre {torre_codigo}. Use este código como referência."

        # Build messages with few-shot reference images
        messages = []
        
        # Load reference images for few-shot
        references = self._load_reference_images()
        if references:
            # System message explaining the references
            messages.append({
                "role": "system",
                "content": "Você receberá imagens de referência de tipos de torre antes da imagem a ser analisada. Use essas referências para classificar corretamente a torre_function como 'ancoragem' ou 'suspensao'."
            })
            
            # Add each reference as a separate user+assistant turn
            for ref in references:
                messages.append({
                    "role": "user",
                    "content": [
                        {"type": "text", "text": f"Imagem de referência - {ref['label']}:"},
                        {"type": "image_url", "image_url": {"url": f"data:{ref['mime']};base64,{ref['base64']}", "detail": "low"}},
                    ],
                })
                messages.append({
                    "role": "assistant",
                    "content": f"Entendido. Registrei esta imagem como referência de torre tipo {ref['category'].upper()}.",
                })
        
        # Add the actual image to analyze
        messages.append({
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/jpeg;base64,{img_base64}",
                        "detail": "high",
                    },
                },
            ],
        })

        try:
            response = self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=messages,
                max_tokens=1200,
                temperature=0.1,
            )
            result_text = response.choices[0].message.content.strip()
            # Clean markdown code fences if present
            if result_text.startswith("```"):
                result_text = result_text.split("\n", 1)[1]
                if result_text.endswith("```"):
                    result_text = result_text[:-3]
            return json.loads(result_text)
        except Exception as e:
            print(f"GPT-4o analysis failed for {photo_id}: {e}")
            return {}

    def annotate_image(self, img: np.ndarray, torre_codigo: str, tower_type: str = "", severity: str = "") -> bytes:
        """Write tower name, type and severity on the image. Returns annotated JPEG bytes."""
        annotated = img.copy()
        h, w = annotated.shape[:2]
        
        # Color based on severity
        severity_colors = {
            "none": (0, 200, 0),      # green
            "low": (0, 200, 0),       # green
            "medium": (0, 200, 255),  # orange
            "high": (0, 100, 255),    # red-orange
            "critical": (0, 0, 255),  # red
        }
        color = severity_colors.get(severity, (255, 255, 255))
        bg_color = (0, 0, 0)
        
        # Font settings
        font = cv2.FONT_HERSHEY_SIMPLEX
        scale = max(0.6, min(2.0, w / 800))  # scale based on image size
        thickness = max(1, int(scale * 2))
        
        # Line 1: Tower code
        label1 = f"Torre: {torre_codigo}"
        (tw1, th1), _ = cv2.getTextSize(label1, font, scale, thickness)
        
        # Line 2: Tower type (if available)
        label2 = f"Tipo: {tower_type}" if tower_type and tower_type != "desconhecido" else ""
        (tw2, th2), _ = cv2.getTextSize(label2, font, scale * 0.8, thickness) if label2 else ((0, 0), 0)
        
        # Background rectangle (top-left)
        padding = int(10 * scale)
        total_h = th1 + (th2 + padding if label2 else 0) + padding * 3
        total_w = max(tw1, tw2) + padding * 2
        
        # Semi-transparent background
        overlay = annotated.copy()
        cv2.rectangle(overlay, (0, 0), (total_w, total_h), bg_color, -1)
        cv2.addWeighted(overlay, 0.7, annotated, 0.3, 0, annotated)
        
        # Draw text
        y = th1 + padding
        cv2.putText(annotated, label1, (padding, y), font, scale, color, thickness, cv2.LINE_AA)
        if label2:
            y += th2 + padding
            cv2.putText(annotated, label2, (padding, y), font, scale * 0.8, (200, 200, 200), thickness, cv2.LINE_AA)
        
        # Encode to JPEG
        _, buffer = cv2.imencode('.jpg', annotated, [cv2.IMWRITE_JPEG_QUALITY, 90])
        return buffer.tobytes()

    async def annotate_with_moondream(
        self,
        img: np.ndarray,
        segments: List[dict],
        vao_total_m: float,
        largura_m: float = 40.0,
        torre_codigo: str = "",
    ) -> bytes:
        """Annotate an aerial inspection photo with vegetation clearing segments.

        Strategy:
        1. Moondream 3 → locate the tower (anchor = km 0).
        2. OpenCV HoughLinesP → detect long straight lines (power cables / road edge)
           to determine the REAL angle and direction of the corridor (works for diagonals).
        3. Project a parallelogram-shaped strip of width=largura_m from the tower
           along that angle, then subdivide it per segment distances.

        segments: list of {tipo, inicio, fim} in meters.
        Returns annotated JPEG bytes.
        """
        if not self.moondream_client:
            raise ValueError("Moondream client not initialized. Check MOONDREAM_API_KEY.")

        import math

        h, w = img.shape[:2]
        annotated = img.copy()
        overlay   = annotated.copy()

        pil_img = PILImage.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
        # Compress image to save bandwidth and API time (prevents 90s timeouts)
        pil_img.thumbnail((1200, 1200))
        
        font      = cv2.FONT_HERSHEY_SIMPLEX
        fs        = max(0.45, w / 1800.0)   # font scale
        ft        = max(1, int(fs * 2))      # font thickness

        # ─────────────────────────────────────────────────────────────────────
        # STEP 1 – Locate tower with Moondream (anchor = km 0)
        # ─────────────────────────────────────────────────────────────────────
        tower_px, tower_py = w // 2, h // 2   # fallback: image centre
        tower_box = None

        all_detected_objs = []
        for q in ["electric transmission tower structure",
                  "high voltage transmission tower",
                  "power line tower"]:
            det  = self.moondream_client.detect(pil_img, q)
            objs = det.get("objects", [])
            if objs:
                all_detected_objs = objs
                best = max(objs, key=lambda o: (o["x_max"]-o["x_min"])*(o["y_max"]-o["y_min"]))
                tower_px = int((best["x_min"] + best["x_max"]) / 2 * w)
                tower_py = int(best["y_max"] * h) # Anchor at the base of the tower
                tower_box = (int(best["x_min"]*w), int(best["y_min"]*h),
                             int(best["x_max"]*w), int(best["y_max"]*h))
                print(f"[Moondream] Tower found via '{q}': px=({tower_px},{tower_py})")
                break
        
        if tower_box:
            x1, y1, x2, y2 = tower_box
            cv2.rectangle(annotated, (x1, y1), (x2, y2), (0, 255, 255), 3)
            cv2.putText(annotated, f"TORRE: {torre_codigo or 'detectada'}",
                        (x1, max(y1-8, 14)), font, fs, (0, 255, 255), ft, cv2.LINE_AA)
        else:
            print("[Moondream] Tower not found - using image centre as anchor.")
            cv2.drawMarker(annotated, (tower_px, tower_py),
                           (0, 255, 255), cv2.MARKER_CROSS, 50, 3)
            cv2.putText(annotated, "Ancora (estimada)", (tower_px+8, tower_py-8),
                        font, fs*0.8, (0, 255, 255), 1, cv2.LINE_AA)

        # ─────────────────────────────────────────────────────────────────────
        # STEP 2 – Detect corridor angle (3-layer strategy)
        # Layer A: detect second tower → angle between the two towers = exact corridor direction
        # Layer B: filtered HoughLinesP near the main tower
        # Layer C: green-channel gradient direction from the cleared strip
        # ─────────────────────────────────────────────────────────────────────
        corridor_angle = None
        has_directed_angle = False

        # ── Layer A1: second tower detection ─────────────────────────────────
        if len(all_detected_objs) >= 2:
            objs_sorted = sorted(all_detected_objs, key=lambda o: (o["x_max"]-o["x_min"])*(o["y_max"]-o["y_min"]), reverse=True)
            main  = objs_sorted[0]
            other = objs_sorted[1]
            main_cx  = (main["x_min"]  + main["x_max"])  / 2
            main_cy  = main["y_max"] # Base
            other_cx = (other["x_min"] + other["x_max"]) / 2
            other_cy = other["y_max"] # Base
            corridor_angle = math.atan2((other_cy - main_cy) * h, (other_cx - main_cx) * w)
            has_directed_angle = True
            print(f"[Moondream] Two towers detected -> angle={math.degrees(corridor_angle):.1f} deg")
            ox1, oy1 = int(other["x_min"] * w), int(other["y_min"] * h)
            ox2, oy2 = int(other["x_max"] * w), int(other["y_max"] * h)
            cv2.rectangle(annotated, (ox1, oy1), (ox2, oy2), (0, 200, 200), 2)
            cv2.putText(annotated, "prox. torre", (ox1+2, oy1-6), font, fs*0.75, (0, 200, 200), 1, cv2.LINE_AA)
            
        # ── Layer B: HoughLinesP near main tower ───────────────────────────
        if corridor_angle is None:
            gray  = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            # Mask: ignore top 25% (sky) and right 15% (helicopter body)
            mask = np.zeros_like(gray)
            sky_cut = int(h * 0.25)
            heli_cut = int(w * 0.85)
            mask[sky_cut:, :heli_cut] = 255
            masked_gray = cv2.bitwise_and(gray, gray, mask=mask)

            # Use 3x3 blur to avoid destroying thin cables!
            blur  = cv2.GaussianBlur(masked_gray, (3, 3), 0)
            edges = cv2.Canny(blur, 40, 130)
            kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
            edges  = cv2.dilate(edges, kernel, iterations=1)

            min_line_len = int(min(w, h) * 0.18)
            lines = cv2.HoughLinesP(edges, 1, np.pi/180,
                                    threshold=50,
                                    minLineLength=min_line_len,
                                    maxLineGap=50)

            # Helper: distance from point to line segment
            def dist_pt_to_seg(px, py, x1, y1, x2, y2):
                ddx, ddy = x2-x1, y2-y1
                if ddx == 0 and ddy == 0:
                    return math.hypot(px-x1, py-y1)
                t = max(0.0, min(1.0, ((px-x1)*ddx + (py-y1)*ddy) / (ddx*ddx + ddy*ddy)))
                return math.hypot(px-(x1+t*ddx), py-(y1+t*ddy))

            # Only lines that pass within 45% of image size from the tower center
            proximity_threshold = max(w, h) * 0.45
            angle_votes: list[float] = []
            near_lines = []
            
            # Recompute tower center for proximity (since tower_py is at base)
            t_cx, t_cy = tower_px, tower_py
            if tower_box:
                t_cx = (tower_box[0] + tower_box[2]) // 2
                t_cy = (tower_box[1] + tower_box[3]) // 2

            if lines is not None:
                for ln in lines:
                    x1l, y1l, x2l, y2l = ln[0]
                    d = dist_pt_to_seg(t_cx, t_cy, x1l, y1l, x2l, y2l)
                    if d > proximity_threshold:
                        continue
                    ang = math.atan2(y2l-y1l, x2l-x1l)
                    ang_deg = abs(math.degrees(ang)) % 180
                    # Reject only exact horizontal horizon lines (0-5 degrees)
                    if ang_deg < 5 or ang_deg > 175:
                        continue
                    length = math.hypot(x2l-x1l, y2l-y1l)
                    angle_votes.extend([ang] * int(length))
                    near_lines.append((x1l, y1l, x2l, y2l))

            if angle_votes:
                corridor_angle = float(np.median(angle_votes))
                print(f"[HoughLines-filtered] Corridor angle: {math.degrees(corridor_angle):.1f} deg "
                      f"from {len(near_lines)} lines near tower")
                # Debug: draw only the near-tower lines
                for x1l, y1l, x2l, y2l in near_lines[:12]:
                    cv2.line(annotated, (x1l, y1l), (x2l, y2l), (0, 165, 255), 1)
                print("[HoughLines-filtered] No valid near-tower lines found.")

        # Absolute fallback if all vision algorithms fail
        if corridor_angle is None:
            corridor_angle = -math.pi / 4   # 45 deg diagonal
            print("[Fallback] Using 45 deg diagonal as absolute fallback.")

        # ─────────────────────────────────────────────────────────────────────
        # STEP 3 – Compute direction and scale
        # ─────────────────────────────────────────────────────────────────────
        if vao_total_m <= 0:
            vao_total_m = 100.0

        dx = math.cos(corridor_angle)
        dy = math.sin(corridor_angle)
        px_perp = -dy
        py_perp =  dx

        # How far can we go in the corridor direction from the tower?
        corners = [(0, 0), (w, 0), (0, h), (w, h)]
        reach_pos, reach_neg = [], []
        for cx, cy in corners:
            t = (cx - tower_px) * dx + (cy - tower_py) * dy
            (reach_pos if t >= 0 else reach_neg).append(t)

        max_pos = max(reach_pos) if reach_pos else w
        max_neg = abs(min(reach_neg)) if reach_neg else 0

        if has_directed_angle:
            direction_sign = 1.0
            total_reach_px = max_pos if max_pos > 0 else w
        else:
            direction_sign = 1.0 if max_pos >= max_neg else -1.0
            total_reach_px = max(max_pos, max_neg)

        px_per_m = max(0.5, min(total_reach_px / vao_total_m, 20.0))
        strip_half_px = max(20, int(largura_m * px_per_m * 0.5))

        # Guide line
        end_gx = int(tower_px + direction_sign * vao_total_m * px_per_m * dx)
        end_gy = int(tower_py + direction_sign * vao_total_m * px_per_m * dy)
        cv2.line(annotated, (tower_px, tower_py), (end_gx, end_gy), (255, 255, 255), 2, cv2.LINE_AA)
        cv2.putText(annotated, "0m",
                    (tower_px + int(-py_perp*22), tower_py + int(px_perp*22) - 6),
                    font, fs*0.8, (0, 255, 255), 1, cv2.LINE_AA)

        # ─────────────────────────────────────────────────────────────────────
        # STEP 4 – Draw each segment as a rotated parallelogram strip
        # ─────────────────────────────────────────────────────────────────────
        color_map = {
            "mecanizado": (173, 68, 142),
            "manual":     (39,  127, 230),
            "seletivo":   (39,  174, 96),
            "cultivado":  (86,  215, 100),
            "nao_rocar":  (80,  80,  80),
        }
        label_map = {
            "mecanizado": "Mecanizado",
            "manual":     "Manual",
            "seletivo":   "Seletivo",
            "cultivado":  "Cultivado",
            "nao_rocar":  "Sem Roco",
        }

        for seg in segments:
            tipo     = seg.get("tipo", "manual")
            inicio_m = float(seg.get("inicio", 0))
            fim_m    = float(seg.get("fim", vao_total_m))
            if vao_total_m <= 0:
                continue

            color = color_map.get(tipo, (200, 200, 200))
            label = label_map.get(tipo, tipo)

            start_d = direction_sign * inicio_m * px_per_m
            end_d   = direction_sign * fim_m   * px_per_m

            def pt(dist_along, perp_sign):
                ax = tower_px + dist_along * dx + perp_sign * strip_half_px * px_perp
                ay = tower_py + dist_along * dy + perp_sign * strip_half_px * py_perp
                return (int(ax), int(ay))

            pts = np.array([pt(start_d, -1), pt(start_d, 1),
                            pt(end_d,   1),  pt(end_d,  -1)], dtype=np.int32)

            cv2.fillPoly(overlay, [pts], color)
            cv2.polylines(annotated, [pts], True, color, 2)

            mid_d  = (start_d + end_d) / 2
            mid_cx = int(tower_px + mid_d * dx)
            mid_cy = int(tower_py + mid_d * dy)
            line1  = label
            line2  = f"{int(inicio_m)}–{int(fim_m)}m"
            (tw1, th1), _ = cv2.getTextSize(line1, font, fs, ft)
            (tw2, th2), _ = cv2.getTextSize(line2, font, fs*0.8, 1)
            bw_px = max(tw1, tw2) + 12
            bh_px = th1 + th2 + 14
            cv2.rectangle(annotated,
                          (mid_cx - bw_px//2, mid_cy - bh_px//2),
                          (mid_cx + bw_px//2, mid_cy + bh_px//2), (0, 0, 0), -1)
            cv2.putText(annotated, line1, (mid_cx - tw1//2, mid_cy - 2),
                        font, fs, (255, 255, 255), ft, cv2.LINE_AA)
            cv2.putText(annotated, line2, (mid_cx - tw2//2, mid_cy + th2 + 4),
                        font, fs*0.8, color, 1, cv2.LINE_AA)

            tick_cx = int(tower_px + end_d * dx)
            tick_cy = int(tower_py + end_d * dy)
            cv2.line(annotated, pt(end_d, -1), pt(end_d, 1), (255, 255, 255), 1)
            cv2.putText(annotated, f"{int(fim_m)}m", (tick_cx + 4, tick_cy - 4),
                        font, fs*0.7, (255, 255, 255), 1, cv2.LINE_AA)

        # Blend overlay
        cv2.addWeighted(overlay, 0.28, annotated, 0.72, 0, annotated)

        # Tower badge
        badge = f"TORRE: {torre_codigo}" if torre_codigo else "TORRE: detectada"
        (bw, bh), _ = cv2.getTextSize(badge, font, fs*1.1, ft+1)
        cv2.rectangle(annotated, (6, 6), (bw+18, bh+18), (0, 0, 0), -1)
        cv2.putText(annotated, badge, (12, bh+10),
                    font, fs*1.1, (0, 255, 255), ft+1, cv2.LINE_AA)

        _, buffer = cv2.imencode('.jpg', annotated, [cv2.IMWRITE_JPEG_QUALITY, 92])
        return buffer.tobytes()



    async def analyze_image(self, image_url: str, photo_id: str) -> AnalyzeImageResponse:
        """Full analysis pipeline: CV + GPT-4o."""
        img = await self.download_image(image_url)

        # 1. CV-based quality analysis
        quality = self.analyze_quality(img)

        # 2. CV-based vegetation detection
        veg_detected_cv, veg_score_cv = self.detect_vegetation_cv(img)

        # 3. CV-based fire detection
        fire_detected_cv, fire_score_cv = self.detect_fire_signs_cv(img)

        # 4. GPT-4o intelligent analysis
        gpt_result = await self.analyze_with_gpt4o(img, photo_id)

        # Merge CV + GPT results (GPT takes precedence for classification)
        vegetation_detected = gpt_result.get("vegetation_detected", veg_detected_cv)
        fire_signs = gpt_result.get("fire_signs", fire_detected_cv)
        structural_issue = gpt_result.get("structural_issue", False)
        anomaly_type = gpt_result.get("anomaly_type")
        confidence = gpt_result.get("confidence", 0.5)
        summary = gpt_result.get("summary", "")

        # Calculate severity score
        severity_map = {"none": 0, "low": 20, "medium": 50, "high": 75, "critical": 95}
        severity_str = gpt_result.get("severity", "none")
        severity_score = severity_map.get(severity_str, 0)

        # Boost severity with CV detections
        if veg_detected_cv and veg_score_cv > 30:
            severity_score = max(severity_score, veg_score_cv * 0.5)
        if fire_detected_cv and fire_score_cv > 20:
            severity_score = max(severity_score, fire_score_cv)

        return AnalyzeImageResponse(
            photo_id=photo_id,
            vegetation_detected=vegetation_detected,
            vegetation_score=max(veg_score_cv, gpt_result.get("vegetation_risk", "none") == "high" and 80 or 0),
            fire_signs=fire_signs,
            fire_score=fire_score_cv,
            structural_issue=structural_issue,
            anomaly_type=anomaly_type,
            severity_score=round(min(100, severity_score), 1),
            confidence=round(confidence, 2),
            quality=quality,
            summary=summary,
        )

    async def compare_images(
        self, current_url: str, previous_url: str, photo_atual_id: str, photo_anterior_id: str
    ) -> CompareImagesResponse:
        """Compare two images of the same tower from different campaigns."""
        img_current = await self.download_image(current_url)
        img_previous = await self.download_image(previous_url)

        # Resize to same dimensions for comparison
        h, w = 512, 512
        img_c = cv2.resize(img_current, (w, h))
        img_p = cv2.resize(img_previous, (w, h))

        # Structural Similarity via histogram comparison
        gray_c = cv2.cvtColor(img_c, cv2.COLOR_BGR2GRAY)
        gray_p = cv2.cvtColor(img_p, cv2.COLOR_BGR2GRAY)
        hist_c = cv2.calcHist([gray_c], [0], None, [256], [0, 256])
        hist_p = cv2.calcHist([gray_p], [0], None, [256], [0, 256])
        cv2.normalize(hist_c, hist_c)
        cv2.normalize(hist_p, hist_p)
        similarity = cv2.compareHist(hist_c, hist_p, cv2.HISTCMP_CORREL)

        # Vegetation change detection
        _, veg_score_c = self.detect_vegetation_cv(img_c)
        _, veg_score_p = self.detect_vegetation_cv(img_p)
        veg_growth = max(0, veg_score_c - veg_score_p)

        # Overall change
        diff = cv2.absdiff(gray_c, gray_p)
        change_pct = np.count_nonzero(diff > 30) / diff.size * 100

        change_detected = change_pct > 10 or abs(veg_growth) > 15
        degradation = max(0, min(100, change_pct * 2))

        return CompareImagesResponse(
            change_detected=change_detected,
            vegetation_growth_level=round(veg_growth, 1),
            degradation_level=round(degradation, 1),
            new_anomaly_detected=degradation > 40,
            comparison_details={
                "similarity": round(similarity, 3),
                "change_percentage": round(change_pct, 1),
                "vegetation_current": round(veg_score_c, 1),
                "vegetation_previous": round(veg_score_p, 1),
            },
        )

    async def generate_summary(
        self, photo_id: str, image_url: Optional[str] = None, analysis_data: Optional[dict] = None
    ) -> GenerateSummaryResponse:
        """Generate LLM summary for a photo inspection using PROMPT_RELATORIO."""
        analise_text = json.dumps(analysis_data, indent=2, ensure_ascii=False) if analysis_data else "Sem dados de análise"
        report_prompt = PROMPT_RELATORIO.format(analise=analise_text)

        messages = [{"role": "system", "content": "Você é um engenheiro especialista em inspeção de linhas de transmissão."}]

        if image_url:
            try:
                img = await self.download_image(image_url)
                _, buffer = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 80])
                img_b64 = base64.b64encode(buffer).decode('utf-8')
                messages.append({
                    "role": "user",
                    "content": [
                        {"type": "text", "text": report_prompt},
                        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{img_b64}", "detail": "high"}},
                    ],
                })
            except Exception:
                messages.append({"role": "user", "content": report_prompt})
        else:
            messages.append({"role": "user", "content": report_prompt})

        try:
            print(f"[generate_summary] Calling OpenAI for {photo_id}...")
            response = self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=messages,
                max_tokens=800,
                temperature=0.3,
            )
            result_text = response.choices[0].message.content.strip()
            print(f"[generate_summary] OpenAI response: {result_text[:200]}")
            if result_text.startswith("```"):
                result_text = result_text.split("\n", 1)[1]
                if result_text.endswith("```"):
                    result_text = result_text[:-3]
            data = json.loads(result_text)
            return GenerateSummaryResponse(
                photo_id=photo_id,
                content=data.get("descricao_tecnica", data.get("content", "Análise indisponível")),
                suggested_action=data.get("acao_recomendada", data.get("suggested_action")),
                risk_interpretation=data.get("nivel_risco", data.get("risk_interpretation")),
            )
        except Exception as e:
            print(f"[generate_summary] ERROR: {type(e).__name__}: {e}")
            return GenerateSummaryResponse(
                photo_id=photo_id,
                content=f"Erro na geração do relatório: {e}",
            )

    async def analyze_with_suppression(
        self,
        image_url: str,
        photo_id: str,
        suppression_data: dict,
        torre_codigo: str = "",
    ) -> dict:
        """Analyze aerial photo considering vegetation suppression mapping data.
        
        Uses GPT-4o Vision to compare what the photo shows vs what the
        suppression plan says should have been done.
        """
        img = await self.download_image(image_url)
        
        # CV vegetation analysis
        veg_detected, veg_score = self.detect_vegetation_cv(img)
        quality = self.analyze_quality(img)
        
        # Encode image
        _, buffer = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 85])
        img_base64 = base64.b64encode(buffer).decode('utf-8')
        
        # Build suppression context
        supp_info = []
        if suppression_data:
            supp_info.append(f"Torre/Vão: EST {suppression_data.get('est_codigo', '?')}")
            supp_info.append(f"Código Torre: {torre_codigo}")
            
            # Include ALL non-null, non-zero fields for maximum context
            field_labels = {
                'vao_frente_m': 'Vão de Frente (m)',
                'largura_m': 'Largura da Faixa (m)',
                'map_mec_extensao': 'Mapeamento Mecanizado - Extensão (m)',
                'map_mec_largura': 'Mapeamento Mecanizado - Largura (m)',
                'map_man_extensao': 'Mapeamento Manual - Extensão (m)',
                'map_man_largura': 'Mapeamento Manual - Largura (m)',
                'exec_mec_extensao': 'Execução Mecanizada - Extensão (m)',
                'exec_mec_largura': 'Execução Mecanizada - Largura (m)',
                'exec_man_extensao': 'Execução Manual - Extensão (m)',
                'exec_man_largura': 'Execução Manual - Largura (m)',
                'data_conclusao': 'Data de Conclusão',
                'roco_concluido': 'Roço Concluído',
                'atende': 'Atende aos Requisitos',
                'area_manual': 'Área Manual Trabalhada (m)',
                'area_mecanizado': 'Área Mecanizada Trabalhada (m)',
                'desconto_seletivo': 'Desconto Seletivo (m)',
                'conferencia_vao': 'Conferência do Vão',
                'area_manual_m2': 'Área Manual (m²)',
                'area_mecanizado_m2': 'Área Mecanizada (m²)',
                'desconto_seletivo_m2': 'Desconto Seletivo (m²)',
                'numeracao_ggt': 'Numeração GGT',
                'mapeamento_ggt': 'Mapeamento GGT',
                'codigo_ggt_execucao': 'Código GGT Execução',
                'descricao_servico': 'Descrição do Serviço',
                'prioridade': 'Prioridade',
                'corte_arvores_25cm': 'Corte Árvores ≥25cm (unid)',
                'corte_arvores_15cm': 'Corte Árvores ≤15cm (m²)',
                'campanha_roco': 'Campanha de Roço',
            }
            
            supp_info.append("\n--- DADOS DO MAPEAMENTO ---")
            for field, label in field_labels.items():
                val = suppression_data.get(field)
                if val is not None and val != '' and val != 0 and val != 0.0 and val is not False:
                    if field == 'roco_concluido':
                        supp_info.append(f"{label}: {'SIM' if val else 'NÃO'}")
                    else:
                        supp_info.append(f"{label}: {val}")
                elif field in ('roco_concluido',):
                    supp_info.append(f"{label}: NÃO")
                elif field in ('prioridade',):
                    supp_info.append(f"{label}: Não definida")
            
            # Summary of what should have been done
            map_mec = suppression_data.get('map_mec_extensao') or 0
            map_man = suppression_data.get('map_man_extensao') or 0
            exec_mec = suppression_data.get('exec_mec_extensao') or 0
            exec_man = suppression_data.get('exec_man_extensao') or 0
            
            supp_info.append(f"\n--- RESUMO ---")
            supp_info.append(f"Total mapeado: {map_mec}m mecanizado + {map_man}m manual")
            supp_info.append(f"Total executado: {exec_mec}m mecanizado + {exec_man}m manual")
            if map_mec + map_man > 0:
                executed = exec_mec + exec_man
                planned = map_mec + map_man
                pct = round(executed / planned * 100, 1) if planned else 0
                supp_info.append(f"Progresso: {pct}% executado")
        
        suppression_context = "\n".join(supp_info)
        
        prompt = PROMPT_SUPRESSAO.format(
            suppression_context=suppression_context,
            veg_detected_text='SIM' if veg_detected else 'NÃO',
            veg_score=veg_score,
        )

        try:
            response = self.client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": prompt},
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/jpeg;base64,{img_base64}",
                                    "detail": "high",
                                },
                            },
                        ],
                    }
                ],
                max_tokens=1200,
                temperature=0.1,
            )
            result_text = response.choices[0].message.content.strip()
            if result_text.startswith("```"):
                result_text = result_text.split("\n", 1)[1]
                if result_text.endswith("```"):
                    result_text = result_text[:-3]
            ai_result = json.loads(result_text)
        except Exception as e:
            print(f"GPT-4o suppression analysis failed for {photo_id}: {e}")
            ai_result = {"error": str(e)}

        return {
            "photo_id": photo_id,
            "torre_codigo": torre_codigo,
            "suppression_data": suppression_data,
            "cv_vegetation_detected": veg_detected,
            "cv_vegetation_score": veg_score,
            "quality": {
                "blur_score": quality.blur_score,
                "exposure_score": quality.exposure_score,
                "overall": quality.overall,
            },
            "ai_analysis": ai_result,
        }

    async def parse_roco_text(self, texto: str, vao_m: int) -> dict:
        """Parse natural language into roco segments using GPT."""
        try:
            from prompts import PROMPT_PARSE_ROCO
            
            prompt = PROMPT_PARSE_ROCO.format(texto=texto, vao_m=vao_m)
            
            response = self.client.chat.completions.create(
                model="gpt-4o",
                response_format={"type": "json_object"},
                messages=[
                    {"role": "system", "content": prompt},
                ],
                max_tokens=500,
                temperature=0.0
            )
            
            content = response.choices[0].message.content
            if content:
                import json
                return json.loads(content)
            
            return {"segmentos": []}
        except Exception as e:
            print(f"Parse Roco text failed: {e}")
            return {"segmentos": []}
