"""去块降噪

"""

import typing
import math
import os
import vapoursynth as vs
from ._internal import (
	core,
	_validate_input_clip,
	_validate_bool,
	_validate_literal,
	_validate_numeric,
	_validate_string_length,
	_check_plugin,
	_check_script,
)
from .mod_helper import LAYER_HIGH

__all__ = [
	"DPIR_DBLK_NV",
	"BILA_NV",
	"BM3D_METAL", "BM3D_NV",
	"CCD_STD",
	"DFTT_STD", "DFTT_NV",
	"DPIR_NR_NV",
	"FFT3D_STD",
	"NLM_STD", "NLM_NV"
]

##################################################
## DPIR # helper
##################################################

def DPIR_TRT_HUB(
	input : vs.VideoNode,
	lt_hd : bool,
	model : int,
	nr_lv : float,
	gpu : typing.Literal[0, 1, 2],
	gpu_t : int,
	st_eng : bool,
	ws_size : int,
	work_type : str,
	func_name : str,
) -> vs.VideoNode :

	_validate_input_clip(func_name, input)
	_validate_bool(func_name, "lt_hd", lt_hd)
	_validate_numeric(func_name, "nr_lv", nr_lv, min_val=0.0, exclusive_min=True)
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])
	_validate_numeric(func_name, "gpu_t", gpu_t, min_val=1, int_only=True)
	_validate_bool(func_name, "st_eng", st_eng)
	_validate_numeric(func_name, "ws_size", ws_size, min_val=0, int_only=True)

	_check_plugin(func_name, "trt")
	_check_plugin(func_name, "akarin")

	from ._external import vsmlrt

	plg_dir = os.path.dirname(core.trt.Version()["path"]).decode()
	if work_type == "deblock" :
		mdl_fname = ["drunet_deblocking_grayscale", "drunet_deblocking_color"][[2, 3].index(model)]
	else :  # "降噪模式"
		mdl_fname = ["drunet_gray", "drunet_color"][[0, 1].index(model)]
	mdl_pth = plg_dir + "/models/dpir/" + mdl_fname + ".onnx"
	if not os.path.exists(mdl_pth) :
		raise vs.Error(f"模块 {func_name} 所请求的模型缺失")

	w_in, h_in = input.width, input.height
	size_in = w_in * h_in
	colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)
	fmt_src = input.format
	fmt_in = fmt_src.id
	fmt_bit_in = fmt_src.bits_per_sample
	fmt_cf_in = fmt_src.color_family

	if (not lt_hd and (size_in > 1280 * 720)) or (size_in > 2048 * 1080) :
		raise Exception("源分辨率超过限制的范围，已临时中止。")
	if not st_eng and (((w_in > 2048) or (h_in > 1080)) or ((w_in < 256) or (h_in < 256))) :
		raise Exception("源分辨率不属于动态引擎支持的范围，已临时中止。")

	tile_size = 8
	w_tmp = math.ceil(w_in / tile_size) * tile_size - w_in
	h_tmp = math.ceil(h_in / tile_size) * tile_size - h_in
	if w_tmp + h_tmp > 0 :
		cut0 = core.std.AddBorders(clip=input, right=w_tmp, bottom=h_tmp)
	else :
		cut0 = input

	is_gray = (work_type == "deblock" and model == 2) or (work_type == "denoise" and model == 0)

	if is_gray :
	##	cut1 = core.resize.Point(clip=cut0, format=vs.GRAYH, matrix_in_s="709")
	##	cut2 = core.std.ShufflePlanes(clips=cut1, planes=0, colorfamily=vs.GRAY)
		cut1 = core.std.ShufflePlanes(clips=cut0, planes=0, colorfamily=vs.GRAY)
		cut2 = core.resize.Point(clip=cut1, format=vs.GRAYH, matrix_in_s="709")
	else :
		cut2 = core.resize.Point(clip=cut0, format=vs.RGBH, matrix_in_s="709")

	fin = vsmlrt.DPIR(clip=cut2, strength=nr_lv, model=model, backend=vsmlrt.BackendV2.TRT(
		num_streams=gpu_t, force_fp16=True, output_format=1,
		workspace=None if ws_size < 128 else (ws_size if st_eng else ws_size * 2),
		use_cuda_graph=True, use_cublas=False, use_cudnn=False,
		static_shape=st_eng, min_shapes=[0, 0] if st_eng else [384, 384],
		opt_shapes=None if st_eng else ([1920, 1080] if lt_hd else [1280, 720]),
		max_shapes=None if st_eng else ([2048, 1080] if lt_hd else [1280, 720]),
		device_id=gpu, short_path=True))

	if is_gray :
		pre_mg = core.resize.Point(clip=fin, format=fin.format.replace(bits_per_sample=fmt_bit_in, sample_type=0))
	##	pre_mg = core.resize.Bilinear(clip=fin, format=fmt_in, matrix_s="709", range=1 if colorlv==0 else None)
		output = core.std.ShufflePlanes(clips=[pre_mg, cut0, cut0], planes=[0, 1, 2], colorfamily=fmt_cf_in)
	else :
		output = core.resize.Bilinear(clip=fin, format=fmt_in, matrix_s="709", range=1 if colorlv==0 else None)

	if w_tmp + h_tmp > 0 :
		output = core.std.Crop(clip=output, right=w_tmp, bottom=h_tmp)

	return output

##################################################
## DPIR去块
##################################################

def DPIR_DBLK_NV(
	input : vs.VideoNode,
	lt_hd : bool = False,
	model : typing.Literal[2, 3] = 2,
	nr_lv : float = 50.0,
	gpu : typing.Literal[0, 1, 2] = 0,
	gpu_t : int = 2,
	st_eng : bool = False,
	ws_size : int = 0,
) -> vs.VideoNode :

	func_name = "DPIR_DBLK_NV"
	_validate_literal(func_name, "model", model, [2, 3])

	return DPIR_TRT_HUB(
		input=input,
		lt_hd=lt_hd,
		model=model,
		nr_lv=nr_lv,
		gpu=gpu,
		gpu_t=gpu_t,
		st_eng=st_eng,
		ws_size=ws_size,
		work_type="deblock",
		func_name=func_name,
	)

##################################################
## Bilateral降噪
##################################################

def BILA_NV(
	input : vs.VideoNode,
	nr_spat : typing.List[float] = [3.0, 0.0, 0.0],
	nr_csp : typing.List[float] = [0.02, 0.0, 0.0],
	gpu : typing.Literal[0, 1, 2] = 0,
	gpu_t : int = 4,
) -> vs.VideoNode :

	func_name = "BILA_NV"
	_validate_input_clip(func_name, input)
	if not (isinstance(nr_spat, list) and len(nr_spat) == 3) :
		raise vs.Error(f"模块 {func_name} 的子参数 nr_spat 的值无效")
	if not (isinstance(nr_csp, list) and len(nr_csp) == 3) :
		raise vs.Error(f"模块 {func_name} 的子参数 nr_csp 的值无效")
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])
	_validate_numeric(func_name, "gpu_t", gpu_t, min_val=1, int_only=True)

	_check_plugin(func_name, "bilateralgpu_rtc")

	fmt_in = input.format.id

	if fmt_in == vs.YUV444P16 :
		cut0 = input
	else :
		cut0 = core.resize.Bilinear(clip=input, format=vs.YUV444P16)
	cut1 = core.bilateralgpu_rtc.Bilateral(clip=cut0,
		sigma_spatial=nr_spat, sigma_color=nr_csp,
		device_id=gpu, num_streams=gpu_t, use_shared_memory=True)
	output = core.resize.Bilinear(clip=cut1, format=fmt_in)

	return output

##################################################
## BM3D降噪 # helper
##################################################

def BM3D_HUB(
	input : vs.VideoNode,
	nr_lv : typing.List[int],
	bs_ref : typing.Literal[1, 2, 3, 4, 5, 6, 7, 8],
	bs_out : typing.Literal[1, 2, 3, 4, 5, 6, 7, 8],
	gpu : typing.Literal[0, 1, 2],
	plugin_name : str,
	func_name : str,
) -> vs.VideoNode :

	_validate_input_clip(func_name, input)
	if not (isinstance(nr_lv, list) and len(nr_lv) == 3 and all(isinstance(i, int) for i in nr_lv)) :
		raise vs.Error(f"模块 {func_name} 的子参数 nr_lv 的值无效")
	_validate_literal(func_name, "bs_ref", bs_ref, [1, 2, 3, 4, 5, 6, 7, 8])
	if bs_out not in [1, 2, 3, 4, 5, 6, 7, 8] or bs_out >= bs_ref :
		raise vs.Error(f"模块 {func_name} 的子参数 bs_out 的值无效")
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])

	_check_plugin(func_name, plugin_name)

	fmt_in = input.format.id

	if plugin_name == "bm3dmetal" :
		bm3d_plugin = core.bm3dmetal
	elif plugin_name == "bm3dcuda_rtc" :
		bm3d_plugin = core.bm3dcuda_rtc

	cut0 = core.resize.Point(clip=input, format=vs.YUV444PS)
	ref = bm3d_plugin.BM3D(clip=cut0, sigma=nr_lv, block_step=bs_ref, device_id=gpu)
	cut1 = bm3d_plugin.BM3D(clip=cut0, ref=ref, sigma=nr_lv, block_step=bs_out, device_id=gpu)
	output = core.resize.Bilinear(clip=cut1, format=fmt_in)

	return output

##################################################
## BM3D降噪 Metal
##################################################

def BM3D_METAL(
	input : vs.VideoNode,
	nr_lv : typing.List[int] = [5,0,0],
	bs_ref : typing.Literal[1, 2, 3, 4, 5, 6, 7, 8] = 8,
	bs_out : typing.Literal[1, 2, 3, 4, 5, 6, 7, 8] = 7,
	gpu : typing.Literal[0, 1, 2] = 0,
) -> vs.VideoNode :

	func_name = "BM3D_METAL"

	return BM3D_HUB(
		input=input,
		nr_lv=nr_lv,
		bs_ref=bs_ref,
		bs_out=bs_out,
		gpu=gpu,
		plugin_name="bm3dmetal",
		func_name=func_name,
	)

##################################################
## BM3D降噪 CUDA
##################################################

def BM3D_NV(
	input : vs.VideoNode,
	nr_lv : typing.List[int] = [5,0,0],
	bs_ref : typing.Literal[1, 2, 3, 4, 5, 6, 7, 8] = 8,
	bs_out : typing.Literal[1, 2, 3, 4, 5, 6, 7, 8] = 7,
	gpu : typing.Literal[0, 1, 2] = 0,
) -> vs.VideoNode :

	func_name = "BM3D_NV"

	return BM3D_HUB(
		input=input,
		nr_lv=nr_lv,
		bs_ref=bs_ref,
		bs_out=bs_out,
		gpu=gpu,
		plugin_name="bm3dcuda_rtc",
		func_name=func_name,
	)

##################################################
## PORT jvsfunc (7bed2d843fd513505b209470fd82c71ef8bcc0dd)
## 减少彩色噪点
##################################################

def CCD_STD(
	input : vs.VideoNode,
	nr_lv : float = 20.0,
) -> vs.VideoNode :

	func_name = "CCD_STD"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "nr_lv", nr_lv, min_val=0.0, exclusive_min=True)

	_check_plugin(func_name, "akarin")

	colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)
	fmt_in = input.format.id

	def _ccd(src: vs.VideoNode, threshold: float = 4) -> vs.VideoNode :
		thr = threshold**2/195075.0
		r = core.std.ShufflePlanes([src, src, src], [0, 0, 0], vs.RGB)
		g = core.std.ShufflePlanes([src, src, src], [1, 1, 1], vs.RGB)
		b = core.std.ShufflePlanes([src, src, src], [2, 2, 2], vs.RGB)
		ex_ccd = core.akarin.Expr([r, g, b, src],
			'x[-12,-12] x - 2 pow y[-12,-12] y - 2 pow z[-12,-12] z - 2 pow + + A! '
			'x[-4,-12] x - 2 pow y[-4,-12] y - 2 pow z[-4,-12] z - 2 pow + + B! '
			'x[4,-12] x - 2 pow y[4,-12] y - 2 pow z[4,-12] z - 2 pow + + C! '
			'x[12,-12] x - 2 pow y[12,-12] y - 2 pow z[12,-12] z - 2 pow + + D! '
			'x[-12,-4] x - 2 pow y[-12,-4] y - 2 pow z[-12,-4] z - 2 pow + + E! '
			'x[-4,-4] x - 2 pow y[-4,-4] y - 2 pow z[-4,-4] z - 2 pow + + F! '
			'x[4,-4] x - 2 pow y[4,-4] y - 2 pow z[4,-4] z - 2 pow + + G! '
			'x[12,-4] x - 2 pow y[12,-4] y - 2 pow z[12,-4] z - 2 pow + + H! '
			'x[-12,4] x - 2 pow y[-12,4] y - 2 pow z[-12,4] z - 2 pow + + I! '
			'x[-4,4] x - 2 pow y[-4,4] y - 2 pow z[-4,4] z - 2 pow + + J! '
			'x[4,4] x - 2 pow y[4,4] y - 2 pow z[4,4] z - 2 pow + + K! '
			'x[12,4] x - 2 pow y[12,4] y - 2 pow z[12,4] z - 2 pow + + L! '
			'x[-12,12] x - 2 pow y[-12,12] y - 2 pow z[-12,12] z - 2 pow + + M! '
			'x[-4,12] x - 2 pow y[-4,12] y - 2 pow z[-4,12] z - 2 pow + + N! '
			'x[4,12] x - 2 pow y[4,12] y - 2 pow z[4,12] z - 2 pow + + O! '
			'x[12,12] x - 2 pow y[12,12] y - 2 pow z[12,12] z - 2 pow + + P! '
			f'A@ {thr} < 1 0 ? B@ {thr} < 1 0 ? C@ {thr} < 1 0 ? D@ {thr} < 1 0 ? '
			f'E@ {thr} < 1 0 ? F@ {thr} < 1 0 ? G@ {thr} < 1 0 ? H@ {thr} < 1 0 ? '
			f'I@ {thr} < 1 0 ? J@ {thr} < 1 0 ? K@ {thr} < 1 0 ? L@ {thr} < 1 0 ? '
			f'M@ {thr} < 1 0 ? N@ {thr} < 1 0 ? O@ {thr} < 1 0 ? P@ {thr} < 1 0 ? '
			'+ + + + + + + + + + + + + + + 1 + Q! '
			f'A@ {thr} < a[-12,-12] 0 ? B@ {thr} < a[-4,-12] 0 ? '
			f'C@ {thr} < a[4,-12] 0 ? D@ {thr} < a[12,-12] 0 ? '
			f'E@ {thr} < a[-12,-4] 0 ? F@ {thr} < a[-4,-4] 0 ? '
			f'G@ {thr} < a[4,-4] 0 ? H@ {thr} < a[12,-4] 0 ? '
			f'I@ {thr} < a[-12,4] 0 ? J@ {thr} < a[-4,4] 0 ? '
			f'K@ {thr} < a[4,4] 0 ? L@ {thr} < a[12,4] 0 ? '
			f'M@ {thr} < a[-12,12] 0 ? N@ {thr} < a[-4,12] 0 ? '
			f'O@ {thr} < a[4,12] 0 ? P@ {thr} < a[12,12] 0 ? '
			'+ + + + + + + + + + + + + + + a + Q@ /')
		return ex_ccd

	cut = core.resize.Point(clip=input, format=vs.RGBS, matrix_in_s="709")
	fin = _ccd(src=cut, threshold=nr_lv)
	output = core.resize.Bilinear(clip=fin, format=fmt_in, matrix_s="709", range=1 if colorlv==0 else None)

	return output

##################################################
## DFTTest # helper
##################################################

def DFTT_HUB(
	input : vs.VideoNode,
	plane : typing.List[int],
	nr_lv : float,
	size_sb : int,
	size_so : int,
	size_tb : int,
	backend_param,
	func_name : str,
	dfttest2,
) -> vs.VideoNode :

	_validate_input_clip(func_name, input)
	_validate_literal(func_name, "plane", plane, [[0], [1], [2], [0, 1], [0, 2], [1, 2], [0, 1, 2]])
	_validate_numeric(func_name, "nr_lv", nr_lv, min_val=0.0, exclusive_min=True)
	_validate_numeric(func_name, "size_sb", size_sb, min_val=1, int_only=True)
	_validate_numeric(func_name, "size_so", size_so, min_val=1, int_only=True)
	_validate_numeric(func_name, "size_tb", size_tb, min_val=1, int_only=True)

	fmt_in = input.format.id

	if fmt_in == vs.YUV444P16 :
		cut0 = input
	else :
		cut0 = core.resize.Point(clip=input, format=vs.YUV444P16)

	backend = backend_param(dfttest2)
	cut1 = dfttest2.DFTTest2(clip=cut0, planes=plane, sigma=nr_lv,
							 sbsize=size_sb, sosize=size_so, tbsize=size_tb,
							 backend=backend)
	output = core.resize.Bilinear(clip=cut1, format=fmt_in)

	return output

##################################################
## DFTTest降噪 CPU
##################################################

def DFTT_STD(
	input : vs.VideoNode,
	plane : typing.List[int] = [0],
	nr_lv : float = 8.0,
	size_sb : int = 16,
	size_so : int = 12,
	size_tb : int = 3,
) -> vs.VideoNode :

	func_name = "DFTT_STD"
	_check_plugin(func_name, "dfttest2_cpu")

	from ._external import dfttest2

	def backend_param(dfttest2):
		return dfttest2.Backend.CPU()

	return DFTT_HUB(
		input=input,
		plane=plane,
		nr_lv=nr_lv,
		size_sb=size_sb,
		size_so=size_so,
		size_tb=size_tb,
		backend_param=backend_param,
		func_name=func_name,
		dfttest2=dfttest2,
	)

##################################################
## DFTTest降噪 CUDA
##################################################

def DFTT_NV(
	input : vs.VideoNode,
	plane : typing.List[int] = [0],
	nr_lv : float = 8.0,
	size_sb : int = 16,
	size_so : int = 12,
	size_tb : int = 3,
	gpu : typing.Literal[0, 1, 2] = 0,
	gpu_t : int = 4,
) -> vs.VideoNode :

	func_name = "DFTT_NV"
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])
	_validate_numeric(func_name, "gpu_t", gpu_t, min_val=1, int_only=True)

	_check_plugin(func_name, "dfttest2_nvrtc")

	from ._external import dfttest2

	def backend_param(dfttest2):
		return dfttest2.Backend.NVRTC(device_id=gpu, num_streams=gpu_t)

	return DFTT_HUB(
		input=input,
		plane=plane,
		nr_lv=nr_lv,
		size_sb=size_sb,
		size_so=size_so,
		size_tb=size_tb,
		backend_param=backend_param,
		func_name=func_name,
		dfttest2=dfttest2,
	)

##################################################
## DPIR降噪
##################################################

def DPIR_NR_NV(
	input : vs.VideoNode,
	lt_hd : bool = False,
	model : typing.Literal[0, 1] = 0,
	nr_lv : float = 5.0,
	gpu : typing.Literal[0, 1, 2] = 0,
	gpu_t : int = 2,
	st_eng : bool = False,
	ws_size : int = 0,
) -> vs.VideoNode :

	func_name = "DPIR_NR_NV"
	_validate_literal(func_name, "model", model, [0, 1])

	return DPIR_TRT_HUB(
		input=input,
		lt_hd=lt_hd,
		model=model,
		nr_lv=nr_lv,
		gpu=gpu,
		gpu_t=gpu_t,
		st_eng=st_eng,
		ws_size=ws_size,
		work_type="denoise",
		func_name=func_name,
	)

##################################################
## FFT3D降噪
##################################################

def FFT3D_STD(
	input : vs.VideoNode,
	mode : typing.Literal[1, 2] = 1,
	nr_lv : float = 2.0,
	plane : typing.List[int] = [0],
	frame_bk : typing.Literal[-1, 0, 1, 2, 3, 4, 5] = 3,
	cpu_t : int = 6,
) -> vs.VideoNode :

	func_name = "FFT3D_STD"
	_validate_input_clip(func_name, input)
	_validate_literal(func_name, "mode", mode, [1, 2])
	_validate_numeric(func_name, "nr_lv", nr_lv, min_val=0.0, exclusive_min=True)
	_validate_literal(func_name, "plane", plane, [[0], [1], [2], [0, 1], [0, 2], [1, 2], [0, 1, 2]])
	_validate_literal(func_name, "frame_bk", frame_bk, [-1, 0, 1, 2, 3, 4, 5])
	_validate_numeric(func_name, "cpu_t", cpu_t, min_val=1, int_only=True)

	_check_plugin(func_name, "trt")
	if mode == 1 :
		_check_plugin(func_name, "fft3dfilter")
	elif mode == 2 :
		_check_plugin(func_name, "neo_fft3d")

	if mode == 1 :
		output = core.fft3dfilter.FFT3DFilter(clip=input, sigma=nr_lv, planes=plane, bt=frame_bk, ncpu=cpu_t)
	elif mode == 2 :
		output = core.neo_fft3d.FFT3D(clip=input, sigma=nr_lv, planes=plane, bt=frame_bk, ncpu=cpu_t, mt=False)

	return output

##################################################
## NLmeans降噪
##################################################

def NLM_STD(
	input : vs.VideoNode,
	blur_m : typing.Literal[0, 1, 2] = 2,
	nlm_m : typing.Literal[1, 2] = 1,
	frame_num : int = 1,
	rad_sw : int = 2,
	rad_snw : int = 2,
	nr_lv : float = 3.0,
	gpu : typing.Literal[0, 1, 2] = 0,
) -> vs.VideoNode :

	func_name = "NLM_STD"
	_validate_input_clip(func_name, input)
	_validate_literal(func_name, "blur_m", blur_m, [0, 1, 2])
	_validate_literal(func_name, "nlm_m", nlm_m, [1, 2])
	_validate_numeric(func_name, "frame_num", frame_num, min_val=0, int_only=True)
	_validate_numeric(func_name, "rad_sw", rad_sw, min_val=0, int_only=True)
	_validate_numeric(func_name, "rad_snw", rad_snw, min_val=0, int_only=True)
	_validate_numeric(func_name, "nr_lv", nr_lv, min_val=0.0, exclusive_min=True)
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])

	if blur_m == 1 :
		_check_plugin(func_name, "rgvs")
	if nlm_m == 1 :
		_check_plugin(func_name, "knlm")
	elif nlm_m == 2 :
		_check_plugin(func_name, "nlm_ispc")

	fmt_in = input.format.id
	blur, diff = LAYER_HIGH(input=input, blur_m=blur_m)

	if blur_m :
		if nlm_m == 1 :
			cut1 = core.knlm.KNLMeansCL(clip=diff, d=frame_num, a=rad_sw, s=rad_snw, h=nr_lv,
				channels="auto", wmode=2, wref=1.0, rclip=None, device_type="GPU", device_id=gpu)
		elif nlm_m == 2 :
			cut1 = core.nlm_ispc.NLMeans(clip=diff, d=frame_num, a=rad_sw, s=rad_snw, h=nr_lv,
				channels="AUTO", wmode=2, wref=1.0, rclip=None)
		merge = core.std.MergeDiff(clipa=blur, clipb=cut1)
	else :
		if nlm_m == 1 :
			cut1 = core.knlm.KNLMeansCL(clip=blur, d=frame_num, a=rad_sw, s=rad_snw, h=nr_lv,
				channels="auto", wmode=2, wref=1.0, rclip=None, device_type="GPU", device_id=gpu)
		elif nlm_m == 2 :
			cut1 = core.nlm_ispc.NLMeans(clip=blur, d=frame_num, a=rad_sw, s=rad_snw, h=nr_lv,
				channels="AUTO", wmode=2, wref=1.0, rclip=None)
	output = core.resize.Bilinear(clip=merge if blur_m else cut1, format=fmt_in)

	return output

##################################################
## NLmeans降噪
##################################################

def NLM_NV(
	input : vs.VideoNode,
	blur_m : typing.Literal[0, 1, 2] = 2,
	frame_num : int = 1,
	rad_sw : int = 2,
	rad_snw : int = 2,
	nr_lv : float = 3.0,
	gpu : typing.Literal[0, 1, 2] = 0,
	gpu_t : int = 4,
) -> vs.VideoNode :

	func_name = "NLM_NV"
	_validate_input_clip(func_name, input)
	_validate_literal(func_name, "blur_m", blur_m, [0, 1, 2])
	_validate_numeric(func_name, "frame_num", frame_num, min_val=0, int_only=True)
	_validate_numeric(func_name, "rad_sw", rad_sw, min_val=0, int_only=True)
	_validate_numeric(func_name, "rad_snw", rad_snw, min_val=0, int_only=True)
	_validate_numeric(func_name, "nr_lv", nr_lv, min_val=0.0, exclusive_min=True)
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])
	_validate_numeric(func_name, "gpu_t", gpu_t, min_val=1, int_only=True)

	_check_plugin(func_name, "nlm_cuda")
	if blur_m == 1 :
		_check_plugin(func_name, "rgvs")

	fmt_in = input.format.id
	blur, diff = LAYER_HIGH(input=input, blur_m=blur_m)

	if blur_m :
		cut1 = core.nlm_cuda.NLMeans(clip=diff, d=frame_num, a=rad_sw, s=rad_snw, h=nr_lv,
			channels="AUTO", wmode=2, wref=1.0, rclip=None, device_id=gpu, num_streams=gpu_t)
		merge = core.std.MergeDiff(clipa=blur, clipb=cut1)
	else :
		cut1 = core.nlm_cuda.NLMeans(clip=blur, d=frame_num, a=rad_sw, s=rad_snw, h=nr_lv,
			channels="AUTO", wmode=2, wref=1.0, rclip=None, device_id=gpu, num_streams=gpu_t)
	output = core.resize.Bilinear(clip=merge if blur_m else cut1, format=fmt_in)

	return output
