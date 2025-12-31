### https://github.com/hooke007/MPV_lazy/wiki/3_K7sfunc
### Real-ESRGAN upscaling or denoising, extremely high performance requirements, NVIDIA only

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

clip = video_in

############
# User Options #
############

H_Pre = 720
Lt_Hd = False
Model = "animejanaiV3-HD-L3.onnx"  # Model 5010
Gpu = 0
Gpu_T = 2
St_Eng = False
Ws_Size = 0
H_Max = 1440
Lk_Fmt = False
## Integer, pre-lower processing source height
## <True|False> Whether to process sources exceeding HD resolution (720P)
## Model filename to use
## GPU number to use, 0 for first in order
## <1|2|3|4> Number of GPU threads to use
## <True|False> Whether to use static engine (requires preprocessing for sources of different resolutions); dynamic engine adapts to different resolutions
## <0~1024> VRAM constraint (MiB), minimum value for static engine is 128 (automatic double for dynamic engine), set below this value for no limit
## Integer, output height limit (enter your display height)
## <True|False> Whether to lock pixel format to yuv420p8

res_opt = [1920, 1080] if Lt_Hd else [1280, 720]
res_max = [2048, 1080] if Lt_Hd else [1280, 720]

ret = k7f.FMT_CTRL(clip, h_max=1200, h_ret=True)
clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
clip = k7f.UAI_NV_TRT(
    input=clip,
    model_pth=Model,
    opt_lv=3,
    cuda_opt=[1, 1, 1],
    int8_qnt=False,
    fp16_qnt=True,
    gpu=Gpu,
    gpu_t=Gpu_T,
    st_eng=St_Eng,
    res_opt=None if St_Eng else res_opt,
    res_max=None if St_Eng else res_max,
    ws_size=Ws_Size
)
clip = k7f.FMT_CTRL(clip, h_max=H_Max, fmt_pix=1 if Lk_Fmt else 0)

clip.set_output()