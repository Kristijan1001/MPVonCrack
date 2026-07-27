"""补帧

"""

import typing
import math
import fractions
import os
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
from .mod_helper import (
	SCENE_DETECT,
	FMT2YUV_SP,
)

__all__ = [
	"MVT_LQ", "MVT_MQ",
	"DRBA_NV",
	"RIFE_STD", "RIFE_COREML", "RIFE_DML", "RIFE_NV",
	"SVP_LQ", "SVP_HQ", "SVP_PRO"
]

##################################################
## MVtools补帧
##################################################

def MVT_LQ(
	input : vs.VideoNode,
	fps_in : float = 23.976,
	fps_out : float = 59.940,
	recal : bool = True,
	block : bool = True,
) -> vs.VideoNode :

	func_name = "MVT_LQ"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "fps_in", fps_in, min_val=0.0, exclusive_min=True)
	if not isinstance(fps_out, (int, float)) or fps_out <= 0.0 or fps_out <= fps_in :
		raise vs.Error(f"模块 {func_name} 的子参数 fps_out 的值无效")
	_validate_bool(func_name, "recal", recal)
	_validate_bool(func_name, "block", block)

	_check_plugin(func_name, "mv")

	w_in, h_in = input.width, input.height
	blk_size = 32
	w_tmp = math.ceil(w_in / blk_size) * blk_size - w_in
	h_tmp = math.ceil(h_in / blk_size) * blk_size - h_in
	if w_tmp + h_tmp > 0 :
		cut0 = core.std.AddBorders(clip=input, right=w_tmp, bottom=h_tmp)
	else :
		cut0 = input

	cut1 = core.std.AssumeFPS(clip=cut0, fpsnum=int(fps_in * 1e6), fpsden=1e6)
	cut_s = core.mv.Super(clip=cut1, pel=1, sharp=0)
	cut_b = core.mv.Analyse(super=cut_s, blksize=blk_size, search=2, isb=True)
	cut_f = core.mv.Analyse(super=cut_s, blksize=blk_size, search=2)

	if recal :
		cut_b = core.mv.Recalculate(super=cut_s, vectors=cut_b, thsad=200,
									blksize=blk_size / 2, search=2, searchparam=1)
		cut_f = core.mv.Recalculate(super=cut_s, vectors=cut_f, thsad=200,
									blksize=blk_size / 2, search=2, searchparam=1)
	else :
		cut_b, cut_f = cut_b, cut_f

	if block :
		output = core.mv.BlockFPS(clip=cut1, super=cut_s, mvbw=cut_b, mvfw=cut_f,
								  num=fps_out * 1e6, den=1e6)
	else :
		output = core.mv.FlowFPS(clip=cut1, super=cut_s, mvbw=cut_b, mvfw=cut_f,
								 num=fps_out * 1e6, den=1e6, mask=1)
	if w_tmp + h_tmp > 0 :
		output = core.std.Crop(clip=output, right=w_tmp, bottom=h_tmp)

	return output

##################################################
## MOD xvs (b24d5594206635f7373838acb80643d2ab141222)
## MVtools补帧
##################################################

def MVT_MQ(
	input : vs.VideoNode,
	fps_in : float = 23.976,
	fps_out : float = 59.940,
	qty_lv : typing.Literal[1, 2, 3] = 1,
	block : bool = True,
	blksize : typing.Literal[4, 8, 16, 32] = 8,
	thscd1 : int = 360,
	thscd2 : int = 80,
) -> vs.VideoNode :

	func_name = "MVT_MQ"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "fps_in", fps_in, min_val=0.0, exclusive_min=True)
	if not isinstance(fps_out, (int, float)) or fps_out <= 0.0 or fps_out <= fps_in :
		raise vs.Error(f"模块 {func_name} 的子参数 fps_out 的值无效")
	_validate_literal(func_name, "qty_lv", qty_lv, [1, 2, 3])
	_validate_bool(func_name, "block", block)
	_validate_literal(func_name, "blksize", blksize, [4, 8, 16, 32])
	_validate_numeric(func_name, "thscd1", thscd1, min_val=0, int_only=True)
	_validate_numeric(func_name, "thscd2", thscd2, min_val=0, max_val=255, int_only=True)

	_check_plugin(func_name, "mv")

	blksizev = blksize
	search = [0, 3, 3][(qty_lv - 1)]
	block_mode = [0, 0, 3][(qty_lv - 1)]
	flow_mask = [0, 1, 2][(qty_lv - 1)]
	analParams = { 'overlap':0,'overlapv':0,'search':search,'dct':0,'truemotion':True,
				   'blksize':blksize,'blksizev':blksizev,'searchparam':2,
				   'badsad':10000,'badrange':24,'divide':0 }
	bofp = { 'thscd1':thscd1,'thscd2':thscd2,'blend':True,'num':int(fps_out * 1e6),'den':1e6 }

	cut0 = core.std.AssumeFPS(input, fpsnum=int(fps_in * 1e6), fpsden=1e6)
	sup = core.mv.Super(input, pel=2, sharp=2, rfilter=4)
	bvec = core.mv.Analyse(sup, isb=True, **analParams)
	fvec = core.mv.Analyse(sup, isb=False, **analParams)
	if block == True :
		output =  core.mv.BlockFPS(cut0, sup, bvec, fvec, **bofp, mode=block_mode)
	else :
		output = core.mv.FlowFPS(cut0, sup, bvec, fvec, **bofp, mask=flow_mask)

	return output

##################################################
## DRBA补帧 TensorRT
##################################################

def DRBA_NV(
	input : vs.VideoNode,
	model : typing.Literal[1, 2] = 2,
	int8_qnt : bool = False,
	turbo : typing.Literal[0, 1, 2] = 1,
	fps_in : float = 23.976,
	fps_num : int = 2,
	fps_den : int = 1,
	sc_mode : typing.Literal[0, 1, 2] = 0,
	gpu : typing.Literal[0, 1, 2] = 0,
	gpu_t : int = 2,
	ws_size : int = 0,
) -> vs.VideoNode :

	func_name = "DRBA_NV"
	_validate_input_clip(func_name, input)
	_validate_literal(func_name, "model", model, [1, 2])
	_validate_bool(func_name, "int8_qnt", int8_qnt)
	_validate_literal(func_name, "turbo", turbo, [0, 1, 2])
	_validate_numeric(func_name, "fps_in", fps_in, min_val=0.0, exclusive_min=True)
	_validate_numeric(func_name, "fps_num", fps_num, min_val=2, int_only=True)
	if not isinstance(fps_den, int) or fps_den >= fps_num or fps_num/fps_den <= 1 :
		raise vs.Error(f"模块 {func_name} 的子参数 fps_den 的值无效")
	_validate_literal(func_name, "sc_mode", sc_mode, [0, 1, 2])
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])
	_validate_numeric(func_name, "gpu_t", gpu_t, min_val=1, int_only=True)
	_validate_numeric(func_name, "ws_size", ws_size, min_val=0, int_only=True)

	_check_plugin(func_name, "trt")
	if sc_mode == 1 :
		_check_plugin(func_name, "misc")
	elif sc_mode == 2 :
		_check_plugin(func_name, "mv")
	_check_plugin(func_name, "akarin")

	from ._external import vsmlrt

	model_scale = False
	model_ap = False
	if turbo :
		model_ap = True
		if turbo == 2 :
			model_scale = True

	plg_dir = os.path.dirname(core.trt.Version()["path"]).decode()
	mdl_pname = "drba/"
	mdl_fname = ["distilDRBA_v1", "distilDRBA_v2_lite"][[1, 2].index(model)] ## 暂只检查核心模型
	mdl_pth = plg_dir + "/models/" + mdl_pname + mdl_fname + ".onnx"
	if not os.path.exists(mdl_pth) :
		raise vs.Error(f"模块 {func_name} 所请求的模型缺失")

	w_in, h_in = input.width, input.height
	size_in = w_in * h_in
	colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)
	fmt_in = input.format.id
	fps_factor = fps_num/fps_den

	st_eng = False
	if model_ap :
		st_eng = True
	if (size_in > 4096 * 2176) :
		raise Exception("源分辨率超过限制的范围，已临时中止。")
	if not st_eng and (((w_in > 4096) or (h_in > 2176)) or ((w_in < 384) or (h_in < 384))) :
		raise Exception("源分辨率不属于动态引擎支持的范围，已临时中止。")

	tile_size = 64
	scale = 1.0
	if model_scale :
		tile_size = 128
		scale = 0.5
	w_tmp = math.ceil(w_in / tile_size) * tile_size - w_in
	h_tmp = math.ceil(h_in / tile_size) * tile_size - h_in

	shape_list = {
		64: {"min": (5, 4), "opt": (30, 17), "max1": (64, 34), "max2": (32, 17)},
		128: {"min": (3, 2), "opt": (15, 9), "max1": (32, 17), "max2": (16, 9)},}
	shape_cfg = shape_list[tile_size]
	min_shapes = [tile_size * x for x in shape_cfg["min"]]
	opt_shapes = [tile_size * x for x in shape_cfg["opt"]]
	max_shapes1 = [tile_size * x for x in shape_cfg["max1"]]
	max_shapes2 = [tile_size * x for x in shape_cfg["max2"]]

	cut0 = SCENE_DETECT(input=input, sc_mode=sc_mode)

	cut1 = core.resize.Point(clip=cut0, format=vs.RGBH, matrix_in_s="709")
	if model_ap :
		fin = vsmlrt.DRBA(clip=cut1, multi=fractions.Fraction(fps_num, fps_den), scale=scale, ap=model_ap, model=model, video_player=True, backend=vsmlrt.BackendV2.TRT(
			num_streams=gpu_t, int8=int8_qnt, fp16=True, output_format=1,
			workspace=None if ws_size < 128 else ws_size,
			use_cuda_graph=True, use_cublas=False, use_cudnn=False,
			static_shape=st_eng, min_shapes=[0, 0],
			opt_shapes=None, max_shapes=None,
			device_id=gpu, short_path=True))
	else :
		if w_tmp + h_tmp > 0 :
			cut1 = core.std.AddBorders(clip=cut1, right=w_tmp, bottom=h_tmp)
		fin = vsmlrt.DRBA(clip=cut1, multi=fractions.Fraction(fps_num, fps_den), scale=scale, ap=model_ap, model=model, video_player=True, backend=vsmlrt.BackendV2.TRT(
			num_streams=gpu_t, int8=int8_qnt, fp16=True, output_format=1,
			workspace=None if ws_size < 128 else (ws_size if st_eng else ws_size * 2),
			use_cuda_graph=True, use_cublas=False, use_cudnn=False,
			static_shape=st_eng, min_shapes=[0, 0] if st_eng else min_shapes,
			opt_shapes=None if st_eng else opt_shapes,
			max_shapes=None if st_eng else (max_shapes1 if (size_in > 2048 * 1088) else max_shapes2),
			device_id=gpu, short_path=True))
		if w_tmp + h_tmp > 0 :
			fin = core.std.Crop(clip=fin, right=w_tmp, bottom=h_tmp)
	output = core.resize.Bilinear(clip=fin, format=fmt_in, matrix_s="709", range=1 if colorlv==0 else None)
	if not fps_factor.is_integer() :
		output = core.std.AssumeFPS(clip=output, fpsnum=fps_in * fps_num * 1e6, fpsden=fps_den * 1e6)

	return output

##################################################
## RIFE补帧 ncnn Vulkan
##################################################

def RIFE_STD(
	input : vs.VideoNode,
	model : typing.Literal[23, 70, 72, 73] = 23,
	t_tta : bool = False,
	fps_num : int = 2,
	fps_den : int = 1,
	sc_mode : typing.Literal[0, 1, 2] = 1,
	skip : bool = True,
	stat_th : float = 60.0,
	gpu : typing.Literal[0, 1, 2] = 0,
	gpu_t : int = 2,
) -> vs.VideoNode :

	func_name = "RIFE_STD"
	_validate_input_clip(func_name, input)
	_validate_literal(func_name, "model", model, [23, 70, 72, 73])
	_validate_bool(func_name, "t_tta", t_tta)
	_validate_numeric(func_name, "fps_num", fps_num, min_val=2, int_only=True)
	if not isinstance(fps_den, int) or fps_den >= fps_num or fps_num/fps_den <= 1 :
		raise vs.Error(f"模块 {func_name} 的子参数 fps_den 的值无效")
	_validate_literal(func_name, "sc_mode", sc_mode, [0, 1, 2])
	_validate_bool(func_name, "skip", skip)
	_validate_numeric(func_name, "stat_th", stat_th, min_val=0.0, max_val=60.0)
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])
	_validate_numeric(func_name, "gpu_t", gpu_t, min_val=1, int_only=True)

	_check_plugin(func_name, "rife")
	if skip :
		_check_plugin(func_name, "vmaf")
	if sc_mode == 1 :
		_check_plugin(func_name, "misc")
	elif sc_mode == 2 :
		_check_plugin(func_name, "mv")

	fmt_in = input.format.id
	colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)

	cut0 = SCENE_DETECT(input=input, sc_mode=sc_mode)
	if model >= 63 :
		t_tta = False

	cut1 = core.resize.Point(clip=cut0, format=vs.RGBS, matrix_in_s="709")
	cut2 = core.rife.RIFE(clip=cut1, model=(model+1) if t_tta else model,
		factor_num=fps_num, factor_den=fps_den, gpu_id=gpu, gpu_thread=gpu_t,
		sc=True if sc_mode else False, skip=skip, skip_threshold=stat_th)
	output = core.resize.Bilinear(clip=cut2, format=fmt_in, matrix_s="709", range=1 if colorlv==0 else None)

	return output

##################################################
## RIFE补帧 # helper
##################################################

def RIFE_ORT_HUB(
	input : vs.VideoNode,
	model : typing.Literal[46, 4251, 426, 4262],
	turbo : bool,
	fps_in : float,
	fps_num : int,
	fps_den : int,
	sc_mode : typing.Literal[0, 1, 2],
	gpu_t : int,
	backend_type : str,
	backend_param,
	func_name : str,
	vsmlrt,
) -> vs.VideoNode :

	_validate_input_clip(func_name, input)
	_validate_literal(func_name, "model", model, [46, 4251, 426, 4262])
	_validate_bool(func_name, "turbo", turbo)
	_validate_numeric(func_name, "fps_in", fps_in, min_val=0.0, exclusive_min=True)
	_validate_numeric(func_name, "fps_num", fps_num, min_val=2, int_only=True)
	if not isinstance(fps_den, int) or fps_den >= fps_num or fps_num/fps_den <= 1 :
		raise vs.Error(f"模块 {func_name} 的子参数 fps_den 的值无效")
	_validate_literal(func_name, "sc_mode", sc_mode, [0, 1, 2])
	_validate_numeric(func_name, "gpu_t", gpu_t, min_val=1, int_only=True)

	_check_plugin(func_name, "ort")
	if sc_mode == 1 :
		_check_plugin(func_name, "misc")
	elif sc_mode == 2 :
		_check_plugin(func_name, "mv")

	if backend_type == "coreml" :
		## CoreML 缺失 akarin，不支持 ext_proc
		cond_support = False
	else :
		## 其它后端需要 akarin 支持
		_check_plugin(func_name, "akarin")
		cond_support = True

	#ext_proc = True
	#t_tta = False
	if turbo :
		ext_proc = False
		t_tta = False
	else :
		ext_proc = cond_support
		t_tta = True

	plg_dir = os.path.dirname(core.ort.Version()["path"]).decode()
	mdl_pname = "rife/" if ext_proc else "rife_v2/"
	if model in [4251, 426, 4262] :
		## https://github.com/AmusementClub/vs-mlrt/blob/2adfbab790eebe51c62c886400b0662570dfe3e9/scripts/vsmlrt.py#L1031-L1032
		t_tta = False
	if t_tta :
		mdl_fname = ["rife_v4.6_ensemble"][[46].index(model)]
	else :
		mdl_fname = ["rife_v4.6", "rife_v4.25_lite", "rife_v4.26", "rife_v4.26_heavy"][[46, 4251, 426, 4262].index(model)]
	mdl_pth = plg_dir + "/models/" + mdl_pname + mdl_fname + ".onnx"
	if not os.path.exists(mdl_pth) :
		raise vs.Error(f"模块 {func_name} 所请求的模型缺失")

	w_in, h_in = input.width, input.height
	size_in = w_in * h_in
	colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)
	fmt_in = input.format.id
	fps_factor = fps_num/fps_den

	if (size_in > 4096 * 2176) :
		raise Exception("源分辨率超过限制的范围，已临时中止。")

	scale_model = 1
	if (size_in > 2048 * 1088) :
		scale_model = 0.5
		if not ext_proc :
			## https://github.com/AmusementClub/vs-mlrt/blob/abc5b1c777a5dde6bad51a099f28eba99375ef4e/scripts/vsmlrt.py#L1002
			scale_model = 1
	if model >= 47 :
		## https://github.com/AmusementClub/vs-mlrt/blob/2adfbab790eebe51c62c886400b0662570dfe3e9/scripts/vsmlrt.py#L1036-L1037
		scale_model = 1

	## https://github.com/AmusementClub/vs-mlrt/blob/2adfbab790eebe51c62c886400b0662570dfe3e9/scripts/vsmlrt.py#L1014-L1023
	tile_size = 32
	if model == 4251 :
		tile_size = 128
	elif model in [426, 4262] :
		tile_size = 64
	tile_size = tile_size / scale_model
	w_tmp = math.ceil(w_in / tile_size) * tile_size - w_in
	h_tmp = math.ceil(h_in / tile_size) * tile_size - h_in

	cut0 = SCENE_DETECT(input=input, sc_mode=sc_mode)
	cut1 = core.resize.Point(clip=cut0, format=vs.RGBS, matrix_in_s="709")

	backend = backend_param(ext_proc)
	if ext_proc :
		if w_tmp + h_tmp > 0 :
			cut1 = core.std.AddBorders(clip=cut1, right=w_tmp, bottom=h_tmp)
		fin = vsmlrt.RIFE(clip=cut1, multi=fractions.Fraction(fps_num, fps_den),
						  scale=scale_model, model=model, ensemble=t_tta,
						  _implementation=1, video_player=True, backend=backend)
		if w_tmp + h_tmp > 0 :
			fin = core.std.Crop(clip=fin, right=w_tmp, bottom=h_tmp)
	else :
		fin = vsmlrt.RIFE(clip=cut1, multi=fractions.Fraction(fps_num, fps_den),
						  scale=scale_model, model=model, ensemble=t_tta,
						  _implementation=2, video_player=True, backend=backend)

	output = core.resize.Bilinear(clip=fin, format=fmt_in, matrix_s="709", range=1 if colorlv==0 else None)
	if not fps_factor.is_integer() :
		output = core.std.AssumeFPS(clip=output, fpsnum=fps_in * fps_num * 1e6, fpsden=fps_den * 1e6)

	return output

##################################################
## RIFE补帧 CoreML
##################################################

def RIFE_COREML(
	input : vs.VideoNode,
	model : typing.Literal[46, 4251, 426, 4262] = 46,
	turbo : bool = True,
	fps_in : float = 23.976,
	fps_num : int = 2,
	fps_den : int = 1,
	sc_mode : typing.Literal[0, 1, 2] = 1,
	be : typing.Literal[0, 1] = 0,
	gpu_t : int = 2,
) -> vs.VideoNode :

	func_name = "RIFE_COREML"
	_validate_literal(func_name, "be", be, [0, 1])

	from ._external import vsmlrt

	fps_den = 1 ## akarin 缺失mac版，暂锁整数倍
	def backend_param(ext_proc):
		return vsmlrt.BackendV2.ORT_COREML(num_streams=gpu_t, fp16=False, ml_program=be) ## CoreML 因未知性能问题禁用fp16

	return RIFE_ORT_HUB(
		input=input,
		model=model,
		turbo=turbo,
		fps_in=fps_in,
		fps_num=fps_num,
		fps_den=fps_den,
		sc_mode=sc_mode,
		gpu_t=gpu_t,
		backend_type="coreml",
		backend_param=backend_param,
		func_name=func_name,
		vsmlrt=vsmlrt,
	)

##################################################
## RIFE补帧 DirectML
##################################################

def RIFE_DML(
	input : vs.VideoNode,
	model : typing.Literal[46, 4251, 426, 4262] = 46,
	turbo : bool = True,
	fps_in : float = 23.976,
	fps_num : int = 2,
	fps_den : int = 1,
	sc_mode : typing.Literal[0, 1, 2] = 1,
	gpu : typing.Literal[0, 1, 2] = 0,
	gpu_t : int = 2,
) -> vs.VideoNode :

	func_name = "RIFE_DML"
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])

	from ._external import vsmlrt

	def backend_param(ext_proc):
		fp16 = True if ext_proc else False ## https://github.com/AmusementClub/vs-mlrt/issues/56#issuecomment-2801745592
		return vsmlrt.BackendV2.ORT_DML(num_streams=gpu_t, fp16=fp16, device_id=gpu)

	return RIFE_ORT_HUB(
		input=input,
		model=model,
		turbo=turbo,
		fps_in=fps_in,
		fps_num=fps_num,
		fps_den=fps_den,
		sc_mode=sc_mode,
		gpu_t=gpu_t,
		backend_type="dml",
		backend_param=backend_param,
		func_name=func_name,
		vsmlrt=vsmlrt,
	)

##################################################
## RIFE补帧 TensorRT
##################################################

def RIFE_NV(
	input : vs.VideoNode,
	model : typing.Literal[46, 4251, 426, 4262] = 46,
	int8_qnt : bool = False,
	turbo : bool = True,
	fps_in : float = 23.976,
	fps_num : int = 2,
	fps_den : int = 1,
	sc_mode : typing.Literal[0, 1, 2] = 1,
	gpu : typing.Literal[0, 1, 2] = 0,
	gpu_t : int = 2,
	ws_size : int = 0,
) -> vs.VideoNode :

	func_name = "RIFE_NV"
	_validate_input_clip(func_name, input)
	_validate_literal(func_name, "model", model, [46, 4251, 426, 4262])
	_validate_bool(func_name, "int8_qnt", int8_qnt)
	_validate_bool(func_name, "turbo", turbo)
	_validate_numeric(func_name, "fps_in", fps_in, min_val=0.0, exclusive_min=True)
	_validate_numeric(func_name, "fps_num", fps_num, min_val=2, int_only=True)
	if not isinstance(fps_den, int) or fps_den >= fps_num or fps_num/fps_den <= 1 :
		raise vs.Error(f"模块 {func_name} 的子参数 fps_den 的值无效")
	_validate_literal(func_name, "sc_mode", sc_mode, [0, 1, 2])
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])
	_validate_numeric(func_name, "gpu_t", gpu_t, min_val=1, int_only=True)
	_validate_numeric(func_name, "ws_size", ws_size, min_val=0, int_only=True)

	_check_plugin(func_name, "trt")
	if sc_mode == 1 :
		_check_plugin(func_name, "misc")
	elif sc_mode == 2 :
		_check_plugin(func_name, "mv")
	_check_plugin(func_name, "akarin")

	from ._external import vsmlrt

	#ext_proc = True
	#t_tta = False
	if turbo :
		ext_proc = False
		t_tta = False
	else :
		ext_proc = True
		t_tta = True

	plg_dir = os.path.dirname(core.trt.Version()["path"]).decode()
	mdl_pname = "rife/" if ext_proc else "rife_v2/"
	if model in [4251, 426, 4262] : ## https://github.com/AmusementClub/vs-mlrt/blob/2adfbab790eebe51c62c886400b0662570dfe3e9/scripts/vsmlrt.py#L1031-L1032
		t_tta = False
	if t_tta :
		mdl_fname = ["rife_v4.6_ensemble"][[46].index(model)]
	else :
		mdl_fname = ["rife_v4.6", "rife_v4.25_lite", "rife_v4.26", "rife_v4.26_heavy"][[46, 4251, 426, 4262].index(model)]
	mdl_pth = plg_dir + "/models/" + mdl_pname + mdl_fname + ".onnx"
	if not os.path.exists(mdl_pth) :
		raise vs.Error(f"模块 {func_name} 所请求的模型缺失")

	w_in, h_in = input.width, input.height
	size_in = w_in * h_in
	colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)
	fmt_in = input.format.id
	fps_factor = fps_num/fps_den

	st_eng = False
	if not ext_proc and model >= 47 : # https://github.com/AmusementClub/vs-mlrt/issues/72
		st_eng = True
	if (size_in > 4096 * 2176) :
		raise Exception("源分辨率超过限制的范围，已临时中止。")
	if not st_eng and (((w_in > 4096) or (h_in > 2176)) or ((w_in < 384) or (h_in < 384))) :
		raise Exception("源分辨率不属于动态引擎支持的范围，已临时中止。")

	scale_model = 1
	if st_eng and (size_in > 2048 * 1088) :
		scale_model = 0.5
		if not ext_proc : ## https://github.com/AmusementClub/vs-mlrt/blob/abc5b1c777a5dde6bad51a099f28eba99375ef4e/scripts/vsmlrt.py#L1002
			scale_model = 1
	if model >= 47 : ## https://github.com/AmusementClub/vs-mlrt/blob/2adfbab790eebe51c62c886400b0662570dfe3e9/scripts/vsmlrt.py#L1036-L1037
		scale_model = 1

	tile_size = 32 ## https://github.com/AmusementClub/vs-mlrt/blob/2adfbab790eebe51c62c886400b0662570dfe3e9/scripts/vsmlrt.py#L1014-L1023
	if model == 4251 :
		tile_size = 128
	elif model in [426, 4262] :
		tile_size = 64
	tile_size = tile_size / scale_model
	w_tmp = math.ceil(w_in / tile_size) * tile_size - w_in
	h_tmp = math.ceil(h_in / tile_size) * tile_size - h_in

	shape_list = {
		32: {"min": (10, 8), "opt": (60, 34), "max1": (128, 68), "max2": (64, 34)},
		64: {"min": (5, 4), "opt": (30, 17), "max1": (64, 34), "max2": (32, 17)},
		128: {"min": (3, 2), "opt": (15, 9), "max1": (32, 17), "max2": (16, 9)},}
	shape_cfg = shape_list[tile_size]
	min_shapes = [tile_size * x for x in shape_cfg["min"]]
	opt_shapes = [tile_size * x for x in shape_cfg["opt"]]
	max_shapes1 = [tile_size * x for x in shape_cfg["max1"]]
	max_shapes2 = [tile_size * x for x in shape_cfg["max2"]]

	cut0 = SCENE_DETECT(input=input, sc_mode=sc_mode)

	cut1 = core.resize.Point(clip=cut0, format=vs.RGBH, matrix_in_s="709")
	if ext_proc :
		if w_tmp + h_tmp > 0 :
			cut1 = core.std.AddBorders(clip=cut1, right=w_tmp, bottom=h_tmp)
		fin = vsmlrt.RIFE(clip=cut1, multi=fractions.Fraction(fps_num, fps_den), scale=scale_model, model=model, ensemble=t_tta, _implementation=1, video_player=True, backend=vsmlrt.BackendV2.TRT(
			num_streams=gpu_t, int8=int8_qnt, fp16=True, output_format=1,
			workspace=None if ws_size < 128 else (ws_size if st_eng else ws_size * 2),
			use_cuda_graph=True, use_cublas=False, use_cudnn=False,
			static_shape=st_eng, min_shapes=[0, 0] if st_eng else min_shapes,
			opt_shapes=None if st_eng else opt_shapes,
			max_shapes=None if st_eng else (max_shapes1 if (size_in > 2048 * 1088) else max_shapes2),
			device_id=gpu, short_path=True))
		if w_tmp + h_tmp > 0 :
			fin = core.std.Crop(clip=fin, right=w_tmp, bottom=h_tmp)
	else :
		fin = vsmlrt.RIFE(clip=cut1, multi=fractions.Fraction(fps_num, fps_den), scale=scale_model, model=model, ensemble=t_tta, _implementation=2, video_player=True, backend=vsmlrt.BackendV2.TRT(
			num_streams=gpu_t, int8=int8_qnt, fp16=True, output_format=1,
			workspace=None if ws_size < 128 else ws_size,
			use_cuda_graph=True, use_cublas=False, use_cudnn=False,
			static_shape=st_eng, min_shapes=[0, 0],
			opt_shapes=None, max_shapes=None,
			device_id=gpu, short_path=True))
	output = core.resize.Bilinear(clip=fin, format=fmt_in, matrix_s="709", range=1 if colorlv==0 else None)
	if not fps_factor.is_integer() :
		output = core.std.AssumeFPS(clip=output, fpsnum=fps_in * fps_num * 1e6, fpsden=fps_den * 1e6)

	return output

##################################################
## SVP补帧
##################################################

def SVP_LQ(
	input : vs.VideoNode,
	fps_in : float = 23.976,
	fps_num : typing.Literal[2, 3, 4] = 2,
	cpu : typing.Literal[0, 1] = 0,
	gpu : typing.Literal[0, 11, 12, 21] = 0,
) -> vs.VideoNode :

	func_name = "SVP_LQ"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "fps_in", fps_in, min_val=0.0, exclusive_min=True)
	_validate_literal(func_name, "fps_num", fps_num, [2, 3, 4])
	_validate_literal(func_name, "cpu", cpu, [0, 1])
	_validate_literal(func_name, "gpu", gpu, [0, 11, 12, 21])

	_check_plugin(func_name, "svp1")
	_check_plugin(func_name, "svp2")

	fps_num = fps_num
	acc = 1 if cpu == 0 else 0

	smooth_param = "{rate:{num:%d,den:1,abs:false},algo:21,gpuid:%d,mask:{area:100},scene:{mode:0,limits:{m1:1800,m2:3600,scene:5200,zero:100,blocks:45}}}" % (fps_num, gpu)
	super_param = "{pel:2,gpu:%d,scale:{up:2,down:4}}" % (acc)
	analyse_param = "{block:{w:32,h:16,overlap:2},main:{levels:4,search:{type:4,distance:-8,coarse:{type:2,distance:-5,bad:{range:0}}},penalty:{lambda:10.0,plevel:1.5,pzero:110,pnbour:65}},refine:[{thsad:200,search:{type:4,distance:2}}]}"

	clip, clip8 = FMT2YUV_SP(input)
	svps = core.svp1.Super(clip8, super_param)
	svpv = core.svp1.Analyse(svps["clip"], svps["data"], clip if acc else clip8, analyse_param)
	output = core.svp2.SmoothFps(clip if acc else clip8,
		svps["clip"], svps["data"], svpv["clip"], svpv["data"],
		smooth_param, src=clip if acc else clip8, fps=fps_in)

	return output

##################################################
## PORT https://github.com/natural-harmonia-gropius
## SVP补帧
##################################################

def SVP_HQ(
	input : vs.VideoNode,
	fps_in : float = 23.976,
	fps_dp : float = 59.940,
	cpu : typing.Literal[0, 1] = 0,
	gpu : typing.Literal[0, 11, 12, 21] = 0,
) -> vs.VideoNode :

	func_name = "SVP_HQ"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "fps_in", fps_in, min_val=0.0, exclusive_min=True)
	_validate_numeric(func_name, "fps_dp", fps_dp, min_val=23.976)
	_validate_literal(func_name, "cpu", cpu, [0, 1])
	_validate_literal(func_name, "gpu", gpu, [0, 11, 12, 21])

	_check_plugin(func_name, "svp1")
	_check_plugin(func_name, "svp2")

	fps = fps_in or 23.976
	freq = fps_dp or 59.970
	acc = 1 if cpu == 0 else 0
	overlap = 2 if cpu == 0 else 3
	w, h = input.width, input.height

	if (freq - fps < 2) :
		raise Exception("Interpolation is not necessary.")

	target_fps = 60

	sp = "{gpu:%d}" % (acc)
	ap = "{block:{w:32,h:16,overlap:%d},main:{levels:5,search:{type:4,distance:-12,coarse:{type:4,distance:-1,trymany:true,bad:{range:0}}},penalty:{lambda:3.33,plevel:1.33,lsad:3300,pzero:110,pnbour:50}},refine:[{thsad:400},{thsad:200,search:{type:4,distance:-4}}]}" % (overlap)
	fp = "{gpuid:%d,algo:23,rate:{num:%d,den:%d,abs:true},mask:{cover:80,area:30,area_sharp:0.75},scene:{mode:0,limits:{scene:6000,zero:100,blocks:40}}}" % (gpu, round(min(max(target_fps, fps * 2, freq / 2), freq)) * 1000, 1001)

	def _svpflow(clip, fps, sp, ap, fp) :
		clip, clip8 = FMT2YUV_SP(clip)
		s = core.svp1.Super(clip8, sp)
		r = s["clip"], s["data"]
		v = core.svp1.Analyse(*r, clip, ap)
		r = *r, v["clip"], v["data"]
		clip = core.svp2.SmoothFps(clip if acc else clip8, *r, fp, src=clip, fps=fps)
		return clip

	output = _svpflow(input, fps, sp, ap, fp)

	return output

##################################################
## CREDIT https://github.com/BlackMickey
## SVP补帧
##################################################

def SVP_PRO(
	input : vs.VideoNode,
	fps_in : float = 23.976,
	fps_num : int = 2,
	fps_den : int = 1,
	abs : bool = False,
	cpu : typing.Literal[0, 1] = 0,
	nvof : bool = False,
	gpu : typing.Literal[0, 11, 12, 21] = 0,
) -> vs.VideoNode :

	func_name = "SVP_PRO"
	_validate_input_clip(func_name, input)
	_validate_numeric(func_name, "fps_in", fps_in, min_val=0.0, exclusive_min=True)
	_validate_numeric(func_name, "fps_num", fps_num, min_val=2, int_only=True)
	if not (isinstance(fps_den, int) and fps_den >= 1 and fps_den < fps_num) :
		raise vs.Error(f"模块 {func_name} 的子参数 fps_den 的值无效")
	_validate_bool(func_name, "abs", abs)
	if abs and (fps_num / fps_den <= fps_in) :
		raise vs.Error(f"模块 {func_name} 的子参数 fps_num 或 fps_den 的值无效")
	_validate_literal(func_name, "cpu", cpu, [0, 1])
	_validate_bool(func_name, "nvof", nvof)
	if nvof and cpu :
		raise vs.Error(f"模块 {func_name} 的子参数 cpu 的值无效")
	_validate_literal(func_name, "gpu", gpu, [0, 11, 12, 21])

	_check_plugin(func_name, "svp1")
	_check_plugin(func_name, "svp2")

	w_in, h_in = input.width, input.height
	size_in = w_in * h_in
	multi = "true" if abs else "false"
	acc = 1 if cpu == 0 else 0
	ana_lv = 5 if size_in > 510272 else 2

	super_param = "{pel:1,gpu:%d,full:true,scale:{up:2,down:4}}" % (acc)
	analyse_param = "{vectors:3,block:{w:32,h:32,overlap:1},main:{levels:%d,search:{type:4,distance:3,sort:true,satd:false,coarse:{width:960,type:4,distance:4,satd:true,trymany:false,bad:{sad:1000,range:0}}},penalty:{lambda:3.0,plevel:1.3,lsad:8000,pnew:50,pglobal:50,pzero:100,pnbour:65,prev:0}},refine:[{thsad:800,search:{type:4,distance:1,satd:false},penalty:{pnew:50}}]}" % (ana_lv)
	smooth_param = "{rate:{num:%d,den:%d,abs:%s},algo:13,block:false,cubic:%d,gpuid:%d,linear:true,mask:{cover:40,area:16,area_sharp:0.7},scene:{mode:3,blend:false,limits:{m1:2400,m2:3601,scene:5002,zero:125,blocks:40},luma:1.5}}" % (fps_num, fps_den, multi, acc, gpu)
	smooth_nvof_param = smooth_param

	clip, clip8 = FMT2YUV_SP(input)
	if nvof :
		output  = core.svp2.SmoothFps_NVOF(clip, smooth_nvof_param, nvof_src=clip8, src=clip,fps=fps_in)
	else :
		super = core.svp1.Super(clip8, super_param)
		vectors = core.svp1.Analyse(super["clip"], super["data"], clip if acc else clip8, analyse_param)
		output = core.svp2.SmoothFps(clip if acc else clip8,
			super["clip"], super["data"], vectors["clip"], vectors["data"],
			smooth_param, src=clip if acc else clip8, fps=fps_in)

	return output
