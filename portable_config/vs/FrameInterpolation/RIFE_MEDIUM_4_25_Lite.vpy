### https://github.com/hooke007/mpv_PlayKit/wiki/3_K7sfunc
### RIFE (v4+) Interpolation, high performance requirements, NVIDIA cards only

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

core.num_threads = k7f.vs_t_dft
clip = video_in

############
# User Options #
############

H_Pre = 1440
Model = 4251
Fps_Num = 2
Fps_Den = 1
Sc_Mode = 1
Gpu = 0
Gpu_T = 2
Ws_Size = 0
Lk_Fmt = False
## Integer, pre-lowering processing source height (fill in your monitor height)
## <46|4251|426|4262> Model used
## Integer, the value of Fps_Num/Fps_Den is the frame rate multiplier
## Integer
## <0|1|2> Scene change detection mode, 0 to disable
## GPU device index, 0 for the first GPU
## <1|2|3> GPU thread count
## Integer, manually limit VRAM during engine build phase (MiB), minimum 128. Lower values maximize usage.
## <True|False> Lock pixel format to yuv420p8

# Detect framerate and handle VFR
is_vfr = False
try:
    actual_fps = container_fps
    # If container_fps works, use it directly (CFR video)
    ret = k7f.FPS_CTRL(clip, fps_in=actual_fps, fps_ret=True)
except:
    # VFR video detected - convert to CFR
    is_vfr = True
    
    try:
        actual_fps = clip.fps_num / clip.fps_den if clip.fps_den > 0 else 23.976
    except:
        actual_fps = 23.976
    
    # Snap to common framerates and convert to CFR
    if abs(actual_fps - 23.976) < 0.01:
        clip = core.std.AssumeFPS(clip, fpsnum=24000, fpsden=1001)
        actual_fps = 24000/1001
    elif abs(actual_fps - 29.97) < 0.01:
        clip = core.std.AssumeFPS(clip, fpsnum=30000, fpsden=1001)
        actual_fps = 30000/1001
    elif abs(actual_fps - 59.94) < 0.01:
        clip = core.std.AssumeFPS(clip, fpsnum=60000, fpsden=1001)
        actual_fps = 60000/1001
    else:
        clip = core.std.AssumeFPS(clip, fpsnum=int(actual_fps * 1000), fpsden=1000)
    
    ret = k7f.FPS_CTRL(clip, fps_in=actual_fps, fps_ret=True)

# Add on-screen overlay showing mode (uncomment to enable)
#if is_vfr:
#    clip = core.text.Text(clip, f"VFR MODE - Converted to {actual_fps:.3f} fps", alignment=7)
#else:
#    clip = core.text.Text(clip, f"CFR MODE - Native {actual_fps:.3f} fps", alignment=7)

clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
clip = k7f.RIFE_NV(clip, model=Model, turbo=True, fps_in=actual_fps, fps_num=Fps_Num, fps_den=Fps_Den, sc_mode=Sc_Mode, gpu=Gpu, gpu_t=Gpu_T, ws_size=Ws_Size)

clip.set_output()
