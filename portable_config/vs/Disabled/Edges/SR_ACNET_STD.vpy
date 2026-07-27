### https://github.com/hooke007/mpv_PlayKit/wiki/3_K7sfunc
### ACNet V3 Upscaling

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

core.num_threads = k7f.vs_t_dft
clip = video_in

############
# User Options #
############

H_Pre = 1080
Model = 1
Model_Var = 0
Gpu = 0
Gpu_M = 1
H_Max = 1440
Lk_Fmt = False
## Integer, pre-processing source height lowering
## <1|2|3> Model index
## <0|1|2|3> Model variant (only for model 2, represents denoising strength)
## GPU index, 0 for the first GPU
## <1|2> GPU acceleration mode, mode 2 is NVIDIA only
## Integer, output height limit (fill in your monitor height)
## <True|False> Whether to lock pixel format to yuv420p8

ret = k7f.FMT_CTRL(clip, h_max=1200, h_ret=True)
clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
clip = k7f.ACNET_STD(clip, model=Model, model_var=Model_Var, turbo=True, gpu=Gpu, gpu_m=Gpu_M)
clip = k7f.FMT_CTRL(clip, h_max=H_Max)

clip.set_output()