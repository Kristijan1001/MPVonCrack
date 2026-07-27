"""格式转换

"""

import typing
import math
import vapoursynth as vs
from ._internal import (
	core,
	_validate_input_clip,
	_validate_bool,
	_validate_literal,
	_validate_numeric,
)

__all__ = [
	"FMT_CHANGE",
	"FMT_CTRL",
	"FPS_CHANGE",
	"FPS_CTRL"
]

##################################################
## 格式转换 # TODO
##################################################

def FMT_CHANGE(
	input : vs.VideoNode,
	fmtc : bool = False, # TODO
	algo : typing.Literal[1, 2, 3, 4] = 1,
	param_a : float = 0.0,
	param_b : float = 0.0,
	w_out : int = 0,
	h_out : int = 0,
	fmt_pix : typing.Literal[-1, 0, 1, 2, 3] = -1,
	dither : typing.Literal[0, 1, 2, 3] = 0,
) -> vs.VideoNode :

	func_name = "FMT_CHANGE"
	_validate_input_clip(func_name, input)
	_validate_bool(func_name, "fmtc", fmtc)
	_validate_literal(func_name, "algo", algo, [1, 2, 3, 4])
	_validate_numeric(func_name, "param_a", param_a)
	_validate_numeric(func_name, "param_b", param_b)
	_validate_numeric(func_name, "w_out", w_out, min_val=0, int_only=True)
	_validate_numeric(func_name, "h_out", h_out, min_val=0, int_only=True)
	_validate_literal(func_name, "fmt_pix", fmt_pix, [-1, 0, 1, 2, 3])
	_validate_literal(func_name, "dither", dither, [0, 1, 2, 3])

	fmt_in = input.format.id
	algo_val = ["Bilinear", "Bicubic", "Lanczos", "Spline36"][algo - 1]
	resizer = getattr(core.resize, algo_val)
	if fmt_pix > 0 :
		fmt_pix_val = [vs.YUV420P8, vs.YUV420P10, vs.YUV444P16][fmt_pix - 1]
		fmt_out = fmt_pix_val
	elif fmt_pix == 0 :
		fmt_out = fmt_in
		if fmt_in not in [vs.YUV420P8, vs.YUV420P10] :
			fmt_out = vs.YUV420P10
	dither_val = ["none", "ordered", "random", "error_diffusion"][dither]

	output = resizer(clip=input, width=w_out if w_out else None, height=h_out if h_out else None,
		filter_param_a=param_a, filter_param_b=param_b,
		format=fmt_pix_val if fmt_pix >= 0 else None, dither_type=dither_val)

	return output

##################################################
## 限制输出的格式与高度
##################################################

def FMT_CTRL(
	input : vs.VideoNode,
	h_max : int = 0,
	h_ret : bool = False,
	spl_b : float = 1/3, # TODO 替换为 FMT_CHANGE
	spl_c : float = 1/3,
	fmt_pix : typing.Literal[0, 1, 2, 3] = 0,
) -> vs.VideoNode :

	func_name = "FMT_CTRL"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "h_max", h_max, min_val=0, int_only=True)
	_validate_bool(func_name, "h_ret", h_ret)
	_validate_numeric(func_name, "spl_b", spl_b)
	_validate_numeric(func_name, "spl_c", spl_c)
	_validate_literal(func_name, "fmt_pix", fmt_pix, [0, 1, 2, 3])

	fmt_src = input.format
	fmt_in = fmt_src.id
	spl_b, spl_c = float(spl_b), float(spl_c)
	w_in, h_in = input.width, input.height
	# https://github.com/mpv-player/mpv/blob/master/video/filter/vf_vapoursynth.c
	fmt_mpv = [vs.YUV420P8, vs.YUV420P10, vs.YUV422P8, vs.YUV422P10, vs.YUV410P8, vs.YUV411P8, vs.YUV440P8, vs.YUV444P8, vs.YUV444P10]
	fmt_pass = [vs.YUV420P8, vs.YUV420P10, vs.YUV444P16]
	fmt_safe = [vs.YUV444P8, vs.YUV444P10, vs.YUV444P16]

	if fmt_pix :
		fmt_pix_val = fmt_pass[fmt_pix - 1]
		fmt_out = fmt_pix_val
		if fmt_out == fmt_in :
			clip = input
		else :
			if (fmt_out not in fmt_safe) and (fmt_in in fmt_safe) :
				if not (w_in % 2 == 0) :
					w_in = w_in - 1
				if not (h_in % 2 == 0) :
					h_in = h_in - 1
				clip = core.resize.Bicubic(clip=input, width=w_in, height=h_in,
					filter_param_a=spl_b, filter_param_b=spl_c, format=fmt_out)
			else :
				clip = core.resize.Bilinear(clip=input, format=fmt_out)
	else :
		if fmt_in not in fmt_mpv :
			fmt_out = vs.YUV420P10
			if (fmt_out not in fmt_safe) and (fmt_in in fmt_safe) :
				if not (w_in % 2 == 0) :
					w_in = w_in - 1
				if not (h_in % 2 == 0) :
					h_in = h_in - 1
				clip = core.resize.Bicubic(clip=input, width=w_in, height=h_in,
					filter_param_a=spl_b, filter_param_b=spl_c, format=fmt_out)
			else :
				clip = core.resize.Bilinear(clip=input, format=fmt_out)
		else :
			fmt_out = fmt_in
			clip = input

	if h_max :
		if h_in > h_max :
			if h_ret :
				raise Exception("源高度超过限制的范围，已临时中止。")
			else :
				w_ds = w_in * (h_max / h_in)
				h_ds = h_max
				if fmt_src.subsampling_w or fmt_src.subsampling_h :
					if not (w_ds % 2 == 0) :
						w_ds = math.floor(w_ds / 2) * 2
					if not (h_ds % 2 == 0) :
						h_ds = math.floor(h_ds / 2) * 2

	if not h_max and not fmt_pix :
		output = clip
	elif h_max and not fmt_pix :
		if h_max >= h_in :
			output = clip
		else :
			output = core.resize.Bicubic(clip=clip, width=w_ds, height=h_ds,
				filter_param_a=spl_b, filter_param_b=spl_c)
	elif not h_max and fmt_pix :
		if fmt_pix_val == fmt_out :
			output = clip
		else :
			output = core.resize.Bilinear(clip=clip, format=fmt_pix_val)
	else :
		if h_max >= h_in :
			if fmt_pix_val == fmt_out :
				output = clip
			else :
				output = core.resize.Bilinear(clip=clip, format=fmt_pix_val)
		else :
			if fmt_pix_val == fmt_out :
				output = core.resize.Bicubic(clip=clip, width=w_ds, height=h_ds,
					filter_param_a=spl_b, filter_param_b=spl_c)
			else :
				output = core.resize.Bicubic(clip=clip, width=w_ds, height=h_ds,
					filter_param_a=spl_b, filter_param_b=spl_c)

	return output

##################################################
## MOD HAvsFunc (e1fcce2b4645ed4acde9192606d00bcac1b5c9e5)
## 变更源帧率
##################################################

def FPS_CHANGE(
	input : vs.VideoNode,
	fps_in : float = 24.0,
	fps_out : float = 60.0,
) -> vs.VideoNode :

	func_name = "FPS_CHANGE"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "fps_in", fps_in, min_val=0.0, exclusive_min=True)
	if not isinstance(fps_out, (int, float)) or fps_out <= 0.0 or fps_out == fps_in :
		raise vs.Error(f"模块 {func_name} 的子参数 fps_out 的值无效")

	def _ChangeFPS(clip: vs.VideoNode, fpsnum: int, fpsden: int = 1) -> vs.VideoNode :
		factor = (fpsnum / fpsden) * (clip.fps_den / clip.fps_num)
		def _frame_adjuster(n: int) -> vs.VideoNode :
			real_n = math.floor(n / factor)
			one_frame_clip = clip[real_n] * (len(clip) + 100)
			return one_frame_clip
		attribute_clip = clip.std.BlankClip(length=math.floor(len(clip) * factor), fpsnum=fpsnum, fpsden=fpsden)
		return attribute_clip.std.FrameEval(eval=_frame_adjuster)

	src = core.std.AssumeFPS(clip=input, fpsnum=fps_in * 1e6, fpsden=1e6)
	fin = _ChangeFPS(clip=src, fpsnum=fps_out * 1e6, fpsden=1e6)
	output = core.std.AssumeFPS(clip=fin, fpsnum=fps_out * 1e6, fpsden=1e6)

	return output

##################################################
## 限制源帧率
##################################################

def FPS_CTRL(
	input : vs.VideoNode,
	fps_in : float = 23.976,
	fps_max : float = 32.0,
	fps_out : typing.Optional[str] = None,
	fps_ret : bool = False,
) -> vs.VideoNode :

	func_name = "FPS_CTRL"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "fps_in", fps_in, min_val=0.0, exclusive_min=True)
	if fps_out is not None :
		_validate_numeric(func_name, "fps_out", fps_out, min_val=0.0)
	_validate_bool(func_name, "fps_ret", fps_ret)

	if fps_in > fps_max :
		if fps_ret :
			raise Exception("源帧率超过限制的范围，已临时中止。")
		else :
			output = FPS_CHANGE(input=input, fps_in=fps_in, fps_out=fps_out if fps_out else fps_max)
	else :
		output = input

	return output
