### https://github.com/hooke007/mpv_PlayKit/wiki/3_K7sfunc
### RIFE (v4+) Interpolation, high performance requirements, DX12 graphics cards only

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

core.num_threads = k7f.vs_t_dft
clip = video_in

############
# User Options #
############

H_Pre = 1440
Model = 46
Fps_Num = 2
Fps_Den = 1
Sc_Mode = 1
Gpu = 0
Gpu_T = 2
Lk_Fmt = False
## Integer, pre-lowering processing source height (fill in your monitor height)
## <46|4251|426|4262> Model used
## Integer, the value of Fps_Num/Fps_Den is the frame rate multiplier
## Integer
## <0|1|2> Scene change detection mode, 0 to disable
## GPU device index, 0 for the first GPU
## <1|2|3> GPU thread count
## <True|False> Lock pixel format to yuv420p8

ret = k7f.FPS_CTRL(clip, fps_in=container_fps, fps_ret=True)
clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
clip = k7f.RIFE_DML(clip, model=Model, turbo=True, fps_in=container_fps, fps_num=Fps_Num, fps_den=Fps_Den, sc_mode=Sc_Mode, gpu=Gpu, gpu_t=Gpu_T)

clip.set_output()