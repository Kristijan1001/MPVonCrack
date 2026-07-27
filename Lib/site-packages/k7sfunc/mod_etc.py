"""未归类的其它函数

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
	_check_plugin,
	_check_script,
)
from .mod_helper import EQ

__all__ = [
	"CSC_UV",
	"DEBAND_STD",
	"DEINT_LQ", "DEINT_STD", "DEINT_EX",
	"EDI_AA_STD", "EDI_AA_NV",
	"IVTC_STD",
	"STAB_STD", "STAB_HQ"
]

##################################################
## MOD HAvsFunc
## 修正U蓝V红色度偏移
##################################################

def CSC_UV(
	input : vs.VideoNode,
	cx : int = 4,
	cy : int = 4,
	sat_lv1 : float = 4.0,
	sat_lv2 : float = 0.8,
	blur : bool = False,
) -> vs.VideoNode :

	func_name = "CSC_UV"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "cx", cx, int_only=True)
	_validate_numeric(func_name, "cy", cy, int_only=True)
	_validate_numeric(func_name, "sat_lv1", sat_lv1)
	_validate_numeric(func_name, "sat_lv2", sat_lv2)
	_validate_bool(func_name, "blur", blur)

	neutral = 1 << (input.format.bits_per_sample - 1)
	peak = (1 << input.format.bits_per_sample) - 1
	def _cround(x) :
		return math.floor(x + 0.5) if x > 0 else math.ceil(x - 0.5)
	def _scale(value, peak) :
		return _cround(value * peak / 255) if peak != 1 else value / 255
	def _Levels(clip, input_low, gamma, input_high, output_low, output_high, coring=True) :
		gamma = 1 / gamma
		divisor = input_high - input_low + (input_high == input_low)
		tvLow, tvHigh = _scale(16, peak), [_scale(235, peak), _scale(240, peak)]
		scaleUp, scaleDown = peak / _scale(219, peak), _scale(219, peak) / peak
		def _get_lut1(x) :
			p = ((x - tvLow) * scaleUp - input_low) / divisor if coring else (x - input_low) / divisor
			p = min(max(p, 0), 1) ** gamma * (output_high - output_low) + output_low
			return min(max(_cround(p * scaleDown + tvLow), tvLow), tvHigh[0]) if coring else min(max(_cround(p), 0), peak)
		def _get_lut2(x) :
			q = _cround((x - neutral) * (output_high - output_low) / divisor + neutral)
			return min(max(q, tvLow), tvHigh[1]) if coring else min(max(q, 0), peak)
		last = clip.std.Lut(planes=[0], function=_get_lut1)
		if clip.format.color_family != vs.GRAY :
			last = last.std.Lut(planes=[1, 2], function=_get_lut2)
		return last
	def _GetPlane(clip, plane=0) :
		sFormat = clip.format
		sNumPlanes = sFormat.num_planes
		last = core.std.ShufflePlanes(clips=clip, planes=plane, colorfamily=vs.GRAY)
		return last

	fmt_cf_in = input.format.color_family
	vch = _GetPlane(EQ(input, sat=sat_lv1), 2)
	area = vch
	if blur :
		area = vch.std.Convolution(matrix=[1, 2, 1, 2, 4, 2, 1, 2, 1])

	red = _Levels(area, _scale(255, peak), 1.0, _scale(255, peak), _scale(255, peak), 0)
	blue = _Levels(area, 0, 1.0, 0, 0, _scale(255, peak))
	mask = core.std.Merge(clipa=red, clipb=blue)

	if not blur :
		mask = mask.std.Convolution(matrix=[1, 2, 1, 2, 4, 2, 1, 2, 1])
	mask = _Levels(mask, _scale(250, peak), 1.0, _scale(250, peak), _scale(255, peak), 0)
	mask = mask.std.Convolution(matrix=[0, 0, 0, 1, 0, 0, 0, 0, 0], divisor=1, saturate=False).std.Convolution(
		matrix=[1, 1, 1, 1, 1, 1, 0, 0, 0], divisor=8, saturate=False)
	mask = _Levels(mask, _scale(10, peak), 1.0, _scale(10, peak), 0, _scale(255, peak)).std.Inflate()
	input_c = EQ(input.resize.Spline16(src_left=cx, src_top=cy), sat=sat_lv2)
	fu = core.std.MaskedMerge(clipa=_GetPlane(input, 1), clipb=_GetPlane(input_c, 1), mask=mask)
	fv = core.std.MaskedMerge(clipa=_GetPlane(input, 2), clipb=_GetPlane(input_c, 2), mask=mask)

	output = core.std.ShufflePlanes([input, fu, fv], planes=[0, 0, 0], colorfamily=fmt_cf_in)

	return output

##################################################
## f3kdb去色带
##################################################

def DEBAND_STD(
	input : vs.VideoNode,
	bd_range : int = 15,
	bdy_rth : int = 48,
	bdc_rth : int = 48,
	grainy : int = 48,
	grainc : int = 48,
	spl_m : typing.Literal[1, 2, 3, 4] = 4,
	grain_dy : bool = True,
	depth : typing.Literal[8, 10] = 8,
) -> vs.VideoNode :

	func_name = "DEBAND_STD"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "bd_range", bd_range, min_val=1, int_only=True)
	_validate_numeric(func_name, "bdy_rth", bdy_rth, min_val=1, int_only=True)
	_validate_numeric(func_name, "bdc_rth", bdc_rth, min_val=1, int_only=True)
	_validate_numeric(func_name, "grainy", grainy, min_val=1, int_only=True)
	_validate_numeric(func_name, "grainc", grainc, min_val=1, int_only=True)
	_validate_literal(func_name, "spl_m", spl_m, [1, 2, 3, 4])
	_validate_bool(func_name, "grain_dy", grain_dy)
	_validate_literal(func_name, "depth", depth, [8, 10])

	_check_plugin(func_name, "neo_f3kdb")

	fmt_in = input.format.id
	color_lv = getattr(input.get_frame(0).props, "_ColorRange", 0)

	if fmt_in == vs.YUV444P16 :
		cut0 = input
	else :
		cut0 = core.resize.Point(clip=input, format=vs.YUV444P16)
	output = core.neo_f3kdb.Deband(clip=cut0, range=bd_range, y=bdy_rth,
		cb=bdc_rth, cr=bdc_rth, grainy=grainy, grainc=grainc, sample_mode=spl_m,
		dynamic_grain=grain_dy, mt=True, keep_tv_range=True if color_lv==1 else False,
		output_depth=depth)

	return output

##################################################
## 简易反交错
##################################################

def DEINT_LQ(
	input : vs.VideoNode,
	iden : bool = True,
	tff : bool = True,
) -> vs.VideoNode :

	func_name = "DEINT_LQ"
	_validate_input_clip(func_name, input)
	_validate_bool(func_name, "iden", iden)
	_validate_bool(func_name, "tff", tff)

	_check_plugin(func_name, "bwdif")

	field = 0
	if iden :
		field = field + 2
	if tff :
		field = field + 1
	output = core.bwdif.Bwdif(clip=input, field=field)

	return output

##################################################
## 基于nnedi3/eedi3作参考的反交错
##################################################

def DEINT_STD(
	input : vs.VideoNode,
	ref_m : typing.Literal[1, 2, 3] = 1,
	tff : bool = True,
	gpu : typing.Literal[-1, 0, 1, 2] = -1,
	deint_m : typing.Literal[1, 2, 3] = 1,
) -> vs.VideoNode :

	func_name = "DEINT_STD"
	_validate_input_clip(func_name, input)
	_validate_literal(func_name, "ref_m", ref_m, [1, 2, 3])
	_validate_bool(func_name, "tff", tff)
	_validate_literal(func_name, "gpu", gpu, [-1, 0, 1, 2])
	_validate_literal(func_name, "deint_m", deint_m, [1, 2, 3])

	if ref_m == 1 :
		_check_plugin(func_name, "znedi3")
	elif ref_m == 2 :
		_check_plugin(func_name, "nnedi3cl")
	elif ref_m == 3 :
		_check_plugin(func_name, "eedi3m")
	if deint_m == 1 :
		_check_plugin(func_name, "bwdif")
	elif deint_m == 2 :
		_check_plugin(func_name, "yadifmod")
	elif deint_m == 3 :
		_check_plugin(func_name, "tdm")

	h_in = input.height

	if h_in % 2 != 0 :
		input = core.std.Crop(clip=input, bottom=1)

	if ref_m == 1 :
		ref = core.znedi3.nnedi3(clip=input, field=3 if tff else 2, dh=False)
	elif ref_m == 2 :
		ref = core.nnedi3cl.NNEDI3CL(clip=input, field=3 if tff else 2, dh=False, device=gpu)
	elif ref_m == 3 :
		ref = core.eedi3m.EEDI3CL(clip=input, field=3 if tff else 2, dh=False, device=gpu)

	if deint_m == 1 :
		output = core.bwdif.Bwdif(clip=input, field=3 if tff else 2, edeint=ref)
	elif deint_m == 2 :
		output = core.yadifmod.Yadifmod(clip=input, edeint=ref, order=1 if tff else 0, mode=1)
	elif deint_m == 3 :
		output = core.tdm.TDeintMod(clip=input, order=1 if tff else 0, mode=1, length=6, ttype=0, edeint=ref)

	return output

##################################################
## 终极反交错
##################################################

def DEINT_EX(
	input : vs.VideoNode,
	fps_in : float = 23.976,
	deint_lv : typing.Literal[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] = 6,
	src_type : typing.Literal[0, 1, 2, 3] = 0,
	deint_den : typing.Literal[1, 2] = 1,
	tff : typing.Literal[0, 1, 2] = 0,
	cpu : bool = True,
	gpu : typing.Literal[-1, 0, 1, 2] = -1,
) -> vs.VideoNode :

	func_name = "DEINT_EX"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "fps_in", fps_in, min_val=0.0, exclusive_min=True)
	_validate_literal(func_name, "deint_lv", deint_lv, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
	_validate_literal(func_name, "src_type", src_type, [0, 1, 2, 3])
	_validate_literal(func_name, "deint_den", deint_den, [1, 2])
	_validate_literal(func_name, "tff", tff, [0, 1, 2])
	_validate_bool(func_name, "cpu", cpu)
	_validate_literal(func_name, "gpu", gpu, [-1, 0, 1, 2])

	from ._external import qtgmc

	h_in = input.height

	if h_in % 2 != 0 :
		input = core.std.Crop(clip=input, bottom=1)
	output = qtgmc.QTGMCv2(input=input, fps_in=fps_in, deint_lv=deint_lv,
						   src_type=src_type, deint_den=deint_den, tff=tff,
						   cpu=cpu, gpu=gpu)

	return output

##################################################
## NNEDI3抗锯齿
##################################################

def EDI_AA_STD(
	input : vs.VideoNode,
	cpu : bool = True,
	gpu : typing.Literal[-1, 0, 1, 2] = -1,
) -> vs.VideoNode :

	func_name = "EDI_AA_STD"
	_validate_input_clip(func_name, input)
	_validate_bool(func_name, "cpu", cpu)
	_validate_literal(func_name, "gpu", gpu, [-1, 0, 1, 2])

	if cpu :
		_check_plugin(func_name, "znedi3")
	else :
		_check_plugin(func_name, "nnedi3cl")

	w_in, h_in = input.width, input.height

	if cpu :
		clip = core.znedi3.nnedi3(clip=input, field=1, dh=True)
		clip = core.std.Transpose(clip=clip)
		clip = core.znedi3.nnedi3(clip=clip, field=1, dh=True)
		clip = core.std.Transpose(clip=clip)
	else:
		clip = core.nnedi3cl.NNEDI3CL(clip=input, field=1, dh=True, device=gpu)
		clip = core.std.Transpose(clip=clip)
		clip = core.nnedi3cl.NNEDI3CL(clip=clip, field=1, dh=True, device=gpu)
		clip = core.std.Transpose(clip=clip)

	output = core.resize.Spline36(clip=clip, width=w_in, height=h_in, src_left=-0.5, src_top=-0.5)

	return output

##################################################
## EEID2抗锯齿
##################################################

def EDI_AA_NV(
	input : vs.VideoNode,
#	plane : typing.List[int] = [0],
	gpu : typing.Literal[-1, 0, 1, 2] = -1,
	gpu_t : int = 4,
) -> vs.VideoNode :

	func_name = "EDI_AA_NV"
	_validate_input_clip(func_name, input)
#	if plane not in ([0], [1], [2], [0, 1], [0, 2], [1, 2], [0, 1, 2]) :
#		raise vs.Error(f"模块 {func_name} 的子参数 plane 的值无效")
	_validate_literal(func_name, "gpu", gpu, [-1, 0, 1, 2])
	_validate_numeric(func_name, "gpu_t", gpu_t, min_val=1, int_only=True)

	_check_plugin(func_name, "eedi2cuda")

	output = core.eedi2cuda.AA2(clip=input, mthresh=10, lthresh=20, vthresh=20,
								estr=2, dstr=4, maxd=24, map=0, nt=50, pp=1,
								device_id=gpu)

	return output

##################################################
## 恢复被错误转换的25/30帧的源为24帧
##################################################

def IVTC_STD(
	input : vs.VideoNode,
	fps_in : float = 25,
	ivtc_m : typing.Literal[1, 2] = 1,
) -> vs.VideoNode :

	func_name = "IVTC_STD"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "fps_in", fps_in, min_val=0.0, exclusive_min=True)
	_validate_literal(func_name, "ivtc_m", ivtc_m, [1, 2])

	if ivtc_m == 1 :
		_check_plugin(func_name, "vivtc")
	elif ivtc_m == 2 :
		_check_plugin(func_name, "tivtc")

	if fps_in <= 24 or fps_in >= 31 or (fps_in >= 26 and fps_in <= 29) :
		raise Exception("源帧率无效，已临时中止。")
	else :

		if ivtc_m == 1 :
			if fps_in > 24 and fps_in < 26 :
				output = core.vivtc.VDecimate(clip=input, cycle=25)
			elif fps_in > 29 and fps_in < 31 :
				output = core.vivtc.VDecimate(clip=input, cycle=5)
		elif ivtc_m == 2 :
			cut0 = core.std.AssumeFPS(clip=input, fpsnum=fps_in * 1e6, fpsden=1e6)
			cut1 = core.tivtc.TDecimate(clip=cut0, mode=7, rate=24 / 1.001)
			output = core.std.AssumeFPS(clip=cut1, fpsnum=24000, fpsden=1001)

	return output

##################################################
## MOD HAvsFunc
## 抗镜头抖动
##################################################

def STAB_STD(
	input : vs.VideoNode,
) -> vs.VideoNode :

	func_name = "STAB_STD"
	_validate_input_clip(func_name, input)

	_check_plugin(func_name, "focus2")
	_check_plugin(func_name, "mv")
	_check_plugin(func_name, "misc")
	_check_plugin(func_name, "rgvs")

	threshold = 255 << (input.format.bits_per_sample - 8)
	temp = input.focus2.TemporalSoften2(7, threshold, threshold, 25, 2)
	inter = core.std.Interleave([core.rgvs.Repair(temp, input.focus2.TemporalSoften2(1, threshold, threshold, 25, 2), mode=[1]), input])
	mdata = inter.mv.DepanEstimate(trust=0, dxmax=4, dymax=4)
	mdata_fin = inter.mv.DepanCompensate(data=mdata, offset=-1, mirror=15)
	output = mdata_fin[::2]

	return output

##################################################
## PORT HAvsFunc
## 抗镜头抖动
##################################################

def STAB_HQ(
	input : vs.VideoNode,
) -> vs.VideoNode :

	func_name = "STAB_HQ"
	_validate_input_clip(func_name, input)

	_check_plugin(func_name, "mv")
	_check_plugin(func_name, "misc")
	_check_plugin(func_name, "rgvs")

	def _scdetect(clip: vs.VideoNode, threshold: float = 0.1) -> vs.VideoNode :
		def _copy_property(n: int, f: list[vs.VideoFrame]) -> vs.VideoFrame :
			fout = f[0].copy()
			fout.props["_SceneChangePrev"] = f[1].props["_SceneChangePrev"]
			fout.props["_SceneChangeNext"] = f[1].props["_SceneChangeNext"]
			return fout
		sc = clip
		if clip.format.color_family == vs.RGB :
			sc = core.resize.Point(clip=clip, format=vs.GRAY8, matrix_s="709")
		sc = sc.misc.SCDetect(threshold=threshold)
		if clip.format.color_family == vs.RGB :
			sc = clip.std.ModifyFrame(clips=[clip, sc], selector=_copy_property)
		return sc

	def _average_frames(
		clip: vs.VideoNode, weights: typing.Union[float, typing.Sequence[float]],
		scenechange: typing.Optional[float] = None,
		planes: typing.Optional[typing.Union[int, typing.Sequence[int]]] = None) -> vs.VideoNode :
		if scenechange :
			clip = _scdetect(clip, scenechange)
		return clip.std.AverageFrames(weights=weights, scenechange=scenechange, planes=planes)

	def _Stab(clp, dxmax=4, dymax=4, mirror=0) :
		temp = _average_frames(clp, weights=[1] * 15, scenechange=25 / 255)
		inter = core.std.Interleave([core.rgvs.Repair(temp, _average_frames(clp, weights=[1] * 3, scenechange=25 / 255), mode=[1]), clp])
		mdata = inter.mv.DepanEstimate(trust=0, dxmax=dxmax, dymax=dymax)
		last = inter.mv.DepanCompensate(data=mdata, offset=-1, mirror=mirror)
		return last[::2]

	output = _Stab(clp=input, mirror=15)

	return output
