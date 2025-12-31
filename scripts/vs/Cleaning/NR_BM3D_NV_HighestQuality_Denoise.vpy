### https://github.com/hooke007/mpv_PlayKit/wiki/3_K7sfunc
### BM3D Denoising, NVIDIA only

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

core.num_threads = k7f.vs_t_dft
clip = video_in

############
# User Options #
############

Nr_Lv = [5,0,0]
Bs_Ref = 8
Bs_Out = 7
Gpu = 0
## Integer array, denoising strength for each plane (Y, U, V)
## <1|2|3|4|5|6|7|8> block_step for reference
## <1|2|3|4|5|6|7|8> less than or equal to Bs_Ref
## GPU index, 0 for the first GPU

clip = k7f.BM3D_NV(clip, nr_lv=Nr_Lv, bs_ref=Bs_Ref, bs_out=Bs_Out, gpu=Gpu)

clip.set_output()