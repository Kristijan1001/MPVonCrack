### https://github.com/hooke007/mpv_PlayKit/wiki/3_K7sfunc
### ArtCNN Upscaling, very high performance requirements, NVIDIA only

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

core.num_threads = k7f.vs_t_dft
clip = video_in

############
# User Options #
############

H_Pre = 720
Lt_Hd = True
Model = 8
Gpu = 0
Gpu_T = 2
St_Eng = False
Ws_Size = 0
H_Max = 1440
Lk_Fmt = False
## Integer, pre-processing source height lowering
## <True|False> Whether to process sources exceeding HD resolution (720P)
## <6|7|8> Model index
## GPU index, 0 for first GPU
## <1|2|3> GPU thread count
## <True|False> Whether to use static engine (requires pre-processing for different resolutions); dynamic engine adapts to different resolutions (64²→DCI2K)
## <0~1024> VRAM constraint (MiB). Minimum 128 for static engine (dynamic engine automatically doubles). Values below this mean no limit.
## Integer, output height limit (fill in your monitor height)
## <True|False> Whether to lock pixel format to yuv420p8

ret = k7f.FMT_CTRL(clip, h_max=1200, h_ret=True)
clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
clip = k7f.ARTCNN_NV(clip, h_pre=H_Pre, lt_hd=Lt_Hd, model=Model, gpu=Gpu, gpu_t=Gpu_T, static=St_Eng, ws_size=Ws_Size, h_max=H_Max)

clip.set_output()