### https://github.com/hooke007/mpv_PlayKit/wiki/3_K7sfunc
### Reduce chroma noise, moderate overhead

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

clip = video_in

############
# User Options #
############

Nr_Lv = 30.0
## Float, chroma noise threshold. Higher values result in more obvious denoising (and more blurring).

clip = k7f.CCD_STD(clip, nr_lv=Nr_Lv)

clip.set_output()