### https://github.com/hooke007/MPV_lazy/wiki/3_K7sfunc
### Real-CUGAN upscaling with denoising, specialized for Anime-style content, NVIDIA only
### Requires vsmlrt dependency

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

core.num_threads = k7f.vs_t_dft
clip = video_in

############
# User Options #
############

H_Pre = 720          ## Integer, pre-lower processing source height
Lt_Hd = False        ## <True|False> Whether to process sources exceeding HD resolution (720P)
Fp16_Qnt = True
Nr_Lv = 4         	 ## <-1|0|1|2|3> Denoise level, -1 for no denoising
Sharp_Lv = 1.0      ## Float between 0.0-2.0, sharpness level
Gpu = 0             ## GPU number to use, 0 for first in order
Gpu_T = 2           ## <1|2|3|4> Number of GPU threads (don't exceed 4)
St_Eng = False      ## <True|False> Whether to use static engine (requires preprocessing for different resolutions)
                    ## Dynamic engine adapts to different resolutions (64²→DCI2K)
Ws_Size = 0         ## Integer, VRAM constraint (MiB)
                    ## Minimum 128 for static engine (auto doubles for dynamic)
                    ## Set below 128 for no limit
H_Max = 1440        ## Integer, output height limit (enter your display height)
Lk_Fmt = False      ## <True|False> Whether to lock pixel format to yuv420p8

### Note: When Lt_Hd is disabled, optimal resolution for dynamic engine is 1280x720
###       When Lt_Hd is enabled, optimal resolution becomes 1920x1080
### To reduce VRAM usage, enable St_Eng first, then adjust Ws_Size

### Available models (place in .../mpv-lazy/vapoursynth64/plugins/models/cugan/):
### - pro-conservative-up2x.onnx (Conservative upscale)
### - pro-denoise3x-up2x.onnx (Heavy denoise + upscale)
### - pro-no-denoise-up2x.onnx (Upscale only)
### Download models from the official repository mentioned in documentation

ret = k7f.FMT_CTRL(clip, h_max=1200, h_ret=True)
clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
clip = k7f.CUGAN_NV(clip, lt_hd=Lt_Hd, nr_lv=Nr_Lv, sharp_lv=Sharp_Lv, gpu=Gpu, gpu_t=Gpu_T, st_eng=St_Eng, ws_size=Ws_Size)

clip.set_output()