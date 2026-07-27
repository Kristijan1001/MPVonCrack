import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

clip = video_in

############ 
# User Options
############
Gpu = 0              # GPU number to use, 0 for first in order
Gpu_T = 2            # Number of GPU threads to use (1-4)
St_Eng = True        # Whether to use static engine, False for dynamic engine
Ws_Size = 0          # VRAM constraint (MiB), 0 for no limit
H_Max = 4320         # Integer, output height limit (8K support)
Lk_Fmt = False       # Whether to lock pixel format to yuv420p8

# Use UAI_NV_TRT with RealESRGAN-x4plus.onnx model
# Note: Static engine requires building separate engines for each source resolution
# but provides more stable performance. Use dynamic engine if you need flexibility.
clip = k7f.UAI_NV_TRT(
    input=clip,
    model_pth="RealESRGAN-x4plus.onnx",
    opt_lv=3,                            # Optimization level (0-5)
    cuda_opt=[1, 1, 1],                  # Enable cuda_graph, cudnn, cublas
    int8_qnt=False,                      # Don't use INT8 quantization (preserves quality)
    fp16_qnt=True,                       # Use FP16 quantization for FP32 models
    gpu=Gpu,
    gpu_t=Gpu_T,
    st_eng=St_Eng,                       # Static engine
    res_opt=None,                        # None for static engine
    res_max=None,                        # None for static engine
    ws_size=Ws_Size
)

clip = k7f.FMT_CTRL(clip, h_max=H_Max, fmt_pix=1 if Lk_Fmt else 0)
clip.set_output()