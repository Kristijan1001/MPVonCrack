### Using a custom AI upscaling model, RTX NVIDIA cards only
### Documentation_ https://github.com/hooke007/mpv_PlayKit/discussions/329
### Parameters_ https://github.com/hooke007/mpv_PlayKit/wiki/3_K7sfunc#uai_nv_trt

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

core.num_threads = k7f.vs_t_dft
clip = video_in

############
# User Options #
############

H_Pre = 720
Model = "the_database_AnimeJaNaiV2L1_x2_fp16_op17.onnx"
Fp16_Qnt = True
Gpu = 0
Gpu_T = 2
St_Eng = False
Res_Opt = [1280, 720]
Res_Max = [1920, 1200]
Ws_Size = 0
H_Max = 1440
Lk_Fmt = False
## Integer, pre-lowering processing source height
## Specify the model used, file placement is .../mpv-lazy/vs-plugins/models/
## <True|False> Whether to use fp16 quantization for fp32 models
## GPU device index, 0 for the first GPU
## <1|2|3> GPU thread count
## <True|False> Whether to use static engine, otherwise dynamic
## Optimized source resolution for dynamic engine (height not greater than H_Pre)
## Max supported source resolution for dynamic engine
## Integer, manually limit VRAM during engine build phase (MiB), minimum 128. Lower values maximize usage.
## Integer, output height limit (fill in your monitor height)
## <True|False> Whether to lock pixel format to yuv420p8

ret = k7f.FMT_CTRL(clip, h_max=1200, h_ret=True)
clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
clip = k7f.UAI_NV_TRT(clip, model=Model, fp16=Fp16_Qnt, gpu=Gpu, gpu_t=Gpu_T, static=St_Eng, opt_res=Res_Opt, max_res=Res_Max, ws_size=Ws_Size, h_max=H_Max)

clip.set_output()