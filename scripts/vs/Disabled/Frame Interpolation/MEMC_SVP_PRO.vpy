### https://github.com/hooke007/mpv_PlayKit/wiki/3_K7sfunc
### Modified simplified version based on Black Mickey's solution

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

clip = video_in

############
# User Options #
############

H_Pre = 1440
Fps_Num = 60000
Fps_Den = 1001
Abs = True
Nvof = False
Gpu = 0
Lk_Fmt = False
## Integer, pre-lowering processing source height (fill in your monitor height)
## Integer, the calculation result of Fps_Num/Fps_Den is the final frame rate or multiplier
## Integer
## <True|False> Output frame rate (True) or multiplier (False)
## <True|False> Whether to enable Optical Flow (NVIDIA only)
## <0|11|12|21> GPU device index, 0 for the first GPU
## <True|False> Whether to lock pixel format to yuv420p8

ret = k7f.FPS_CTRL(clip, fps_in=container_fps, fps_ret=True)
clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
clip = k7f.SVP_PRO(clip, fps_in=container_fps, fps_num=Fps_Num, fps_den=Fps_Den, abs=Abs, nvof=Nvof, gpu=Gpu)

clip.set_output()