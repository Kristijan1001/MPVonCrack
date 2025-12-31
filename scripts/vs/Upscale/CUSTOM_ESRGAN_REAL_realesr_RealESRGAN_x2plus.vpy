import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

clip = video_in

############ 
# User Options
############
H_Pre = 720          # Integer, pre-lower processing source height
Gpu = 0              # GPU number to use, 0 for first in order
Gpu_T = 2            # Number of GPU threads to use (1-4)
St_Eng = True        # Use static engine (simpler, often faster)
Ws_Size = 0          # VRAM constraint (MiB), 0 for no limit
H_Max = 1440         # Integer, output height limit (720p x2 = 1440p)
Lk_Fmt = False       # Whether to lock pixel format to yuv420p8

# Pre-process clip to desired height for processing
clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)

# Use UAI_NV_TRT with RealESRGAN-x2plus.onnx model
clip = k7f.UAI_NV_TRT(
    clip,
    model_pth="RealESRGAN_x2plus.onnx",
    opt_lv=3,           # Optimization level (3 is recommended balance)
    fp16_qnt=True,      # Use FP16 quantization for speed boost
    gpu=Gpu,
    gpu_t=Gpu_T,
    st_eng=St_Eng,
    ws_size=Ws_Size
)

# Post-process to limit output height and set format if needed
clip = k7f.FMT_CTRL(clip, h_max=H_Max, fmt_pix=1 if Lk_Fmt else 0)

clip.set_output()