"""支持高度自定义的模块

"""

import typing
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
from .mod_helper import (
	ONNX_ANZ,
	DCF,
)

__all__ = [
	"UAI_COREML",
	"UAI_DML",
	"UAI_MIGX",
	"UAI_NV_TRT",
	"UVR_MAD"
]

##################################################
## 自定义ONNX模型 # helper
##################################################

def UAI_ORT_HUB(
	input : vs.VideoNode,
	crc : bool,
	model_pth : str,
	fp16_qnt : bool,
	gpu_t : int,
	backend_param,
	func_name : str,
	vsmlrt,
) -> vs.VideoNode :

	_validate_input_clip(func_name, input)
	_validate_bool(func_name, "crc", crc)
	_validate_string_length(func_name, "model_pth", model_pth, 5)
	_validate_bool(func_name, "fp16_qnt", fp16_qnt)
	_validate_numeric(func_name, "gpu_t", gpu_t, min_val=1, int_only=True)

	_check_plugin(func_name, "ort")

	plg_dir = os.path.dirname(core.ort.Version()["path"]).decode()
	mdl_pth_rel = plg_dir + "/models/" + model_pth
	if not os.path.exists(mdl_pth_rel) and not os.path.exists(model_pth) :
		raise vs.Error(f"模块 {func_name} 所请求的模型缺失")
	mdl_pth = mdl_pth_rel if os.path.exists(mdl_pth_rel) else model_pth

	fmt_in = input.format.id
	colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)

	mdl_info = ONNX_ANZ(input=mdl_pth)
	if not mdl_info["valid"] :
		raise vs.Error(f"模块 {func_name} 的输入模型无效: {mdl_info['error']}")
	fp16_mdl = mdl_info["elem_type_name"] == "fp16"
	if fp16_mdl :
		fp16_qnt = False ## ort对于fp16模型自动使用对应的IO
	gray_mdl = mdl_info["shape"][1] == 1
	gray_fmt = vs.GRAYH if fp16_mdl else vs.GRAYS
	rgb_fmt = vs.RGBH if fp16_mdl else vs.RGBS
	yuv_fmt = vs.YUV444PH if fp16_mdl else vs.YUV444PS

	if gray_mdl :
		clip_y = core.resize.Point(clip=input, format=gray_fmt)
		be_param = backend_param(fp16_qnt)
		infer = vsmlrt.inference(clips=clip_y, network_path=mdl_pth, backend=be_param)
		clip_uv = core.resize.Bilinear(clip=input, format=yuv_fmt)
		output = core.std.ShufflePlanes([infer, clip_uv], [0, 1, 2], vs.YUV)
		output = core.resize.Bilinear(clip=output, format=fmt_in, range=1 if colorlv==0 else None)
	else :
		clip = core.resize.Point(clip=input, format=rgb_fmt, matrix_in_s="709")
		be_param = backend_param(fp16_qnt)
		infer = vsmlrt.inference(clips=clip, network_path=mdl_pth, backend=be_param)
		if crc :
			infer = DCF(input=infer, ref=clip)
		output = core.resize.Bilinear(clip=infer, format=fmt_in, matrix_s="709", range=1 if colorlv==0 else None)

	return output

##################################################
## 自定义ONNX模型 CoreML
##################################################

def UAI_COREML(
	input : vs.VideoNode,
	crc : bool = False,
	model_pth : str = "",
	fp16_qnt : bool = False,
	be : typing.Literal[0, 1] = 0,
	gpu_t : int = 2,
) -> vs.VideoNode :

	func_name = "UAI_COREML"
	_validate_literal(func_name, "be", be, [0, 1])

	from ._external import vsmlrt

	def backend_param(fp16_qnt):
		## fp16模型或量化都存在未知的性能问题，暂时建议维持fp32链路
		return vsmlrt.BackendV2.ORT_COREML(ml_program=be, num_streams=gpu_t, fp16=fp16_qnt)

	return UAI_ORT_HUB(
		input=input,
		crc=crc,
		model_pth=model_pth,
		fp16_qnt=fp16_qnt,
		gpu_t=gpu_t,
		backend_param=backend_param,
		func_name=func_name,
		vsmlrt=vsmlrt,
	)

##################################################
## 自定义ONNX模型 DirectML
##################################################

def UAI_DML(
	input : vs.VideoNode,
	crc : bool = False,
	model_pth : str = "",
	fp16_qnt : bool = True,
	gpu : typing.Literal[0, 1, 2] = 0,
	gpu_t : int = 2,
) -> vs.VideoNode :

	func_name = "UAI_DML"
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])

	from ._external import vsmlrt

	def backend_param(fp16_qnt):
		return vsmlrt.BackendV2.ORT_DML(device_id=gpu, num_streams=gpu_t, fp16=fp16_qnt)

	return UAI_ORT_HUB(
		input=input,
		crc=crc,
		model_pth=model_pth,
		fp16_qnt=fp16_qnt,
		gpu_t=gpu_t,
		backend_param=backend_param,
		func_name=func_name,
		vsmlrt=vsmlrt,
	)

##################################################
## 自定义ONNX模型 MIGraphX
##################################################

def UAI_MIGX(
	input : vs.VideoNode,
	crc : bool = False,
	model_pth : str = "",
	fp16_qnt : bool = True,
	exh_tune : bool = False,
	gpu : typing.Literal[0, 1, 2] = 0,
	gpu_t : int = 2,
) -> vs.VideoNode :

	func_name = "UAI_MIGX"
	_validate_input_clip(func_name, input)
	_validate_bool(func_name, "crc", crc)
	_validate_string_length(func_name, "model_pth", model_pth, 5)
	_validate_bool(func_name, "fp16_qnt", fp16_qnt)
	_validate_bool(func_name, "exh_tune", exh_tune)
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])
	_validate_numeric(func_name, "gpu_t", gpu_t, min_val=1, int_only=True)

	_check_plugin(func_name, "migx")

	from ._external import vsmlrt

	plg_dir = os.path.dirname(core.migx.Version()["path"]).decode()
	mdl_pth_rel = plg_dir + "/models/" + model_pth
	if not os.path.exists(mdl_pth_rel) and not os.path.exists(model_pth) :
		raise vs.Error(f"模块 {func_name} 所请求的模型缺失")
	mdl_pth = mdl_pth_rel if os.path.exists(mdl_pth_rel) else model_pth

	fmt_in = input.format.id
	colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)

	mdl_info = ONNX_ANZ(input=mdl_pth)
	if not mdl_info["valid"] :
		raise vs.Error(f"模块 {func_name} 的输入模型无效: {mdl_info['error']}")
	fp16_mdl = mdl_info["elem_type_name"] == "fp16"
	if fp16_mdl :
		fp16_qnt = True   ### 量化精度与模型精度匹配
	gray_mdl = mdl_info["shape"][1] == 1
	gray_fmt = vs.GRAYH if fp16_qnt else vs.GRAYS
	rgb_fmt = vs.RGBH if fp16_qnt else vs.RGBS
	yuv_fmt = vs.YUV444PH if fp16_qnt else vs.YUV444PS

	if gray_mdl :
		clip_y = core.resize.Point(clip=input, format=gray_fmt)
		be_param = vsmlrt.BackendV2.MIGX(
			fp16=fp16_qnt, exhaustive_tune=exh_tune, opt_shapes=[clip_y.width, clip_y.height],
			device_id=gpu, num_streams=gpu_t, short_path=True)
		infer = vsmlrt.inference(clips=clip_y, network_path=mdl_pth, backend=be_param)
		clip_uv = core.resize.Bilinear(clip=input, format=yuv_fmt)
		output = core.std.ShufflePlanes([infer, clip_uv], [0, 1, 2], vs.YUV)
		output = core.resize.Bilinear(clip=output, format=fmt_in, range=1 if colorlv==0 else None)
	else :
		clip = core.resize.Point(clip=input, format=rgb_fmt, matrix_in_s="709")
		be_param = vsmlrt.BackendV2.MIGX(
			fp16=fp16_qnt, exhaustive_tune=exh_tune, opt_shapes=[clip.width, clip.height],
			device_id=gpu, num_streams=gpu_t, short_path=True)
		infer = vsmlrt.inference(clips=clip, network_path=mdl_pth, backend=be_param)
		if crc :
			infer = DCF(input=infer, ref=clip)
		output = core.resize.Bilinear(clip=infer, format=fmt_in, matrix_s="709", range=1 if colorlv==0 else None)

	return output

##################################################
## 自定义ONNX模型 TensorRT
##################################################

def UAI_NV_TRT(
	input : vs.VideoNode,
	crc : bool = False,
	model_pth : str = "",
	opt_lv : typing.Literal[0, 1, 2, 3, 4, 5] = 3,
	cuda_opt : typing.List[int] = [0, 0, 0],
	int8_qnt : bool = False,
	fp16_qnt : bool = True,
	gpu : typing.Literal[0, 1, 2] = 0,
	gpu_t : int = 2,
	st_eng : bool = False,
	res_opt : typing.List[int] = None,
	res_max : typing.List[int] = None,
	ws_size : int = 0,
) -> vs.VideoNode :

	func_name = "UAI_NV_TRT"
	_validate_input_clip(func_name, input)
	_validate_bool(func_name, "crc", crc)
	_validate_string_length(func_name, "model_pth", model_pth, 5)
	_validate_literal(func_name, "opt_lv", opt_lv, [0, 1, 2, 3, 4, 5])
	if not (len(cuda_opt) == 3 and all(isinstance(num, int) and num in [0, 1] for num in cuda_opt)) :
		raise vs.Error(f"模块 {func_name} 的子参数 cuda_opt 的值无效")
	_validate_bool(func_name, "int8_qnt", int8_qnt)
	_validate_bool(func_name, "fp16_qnt", fp16_qnt)
	_validate_literal(func_name, "gpu", gpu, [0, 1, 2])
	_validate_numeric(func_name, "gpu_t", gpu_t, min_val=1, int_only=True)
	_validate_bool(func_name, "st_eng", st_eng)
#	if st_eng :
#		if not (res_opt is None and res_max is None) :
#			raise vs.Error(f"模块 {func_name} 的子参数 res_opt 或 res_max 的值无效")
	if not st_eng :
		if not (isinstance(res_opt, list) and len(res_opt) == 2 and all(isinstance(i, int) for i in res_opt)) :
			raise vs.Error(f"模块 {func_name} 的子参数 res_opt 的值无效")
		if not (isinstance(res_max, list) and len(res_max) == 2 and all(isinstance(i, int) for i in res_max)) :
			raise vs.Error(f"模块 {func_name} 的子参数 res_max 的值无效")
	_validate_numeric(func_name, "ws_size", ws_size, min_val=0, int_only=True)

	_check_plugin(func_name, "trt")

	from ._external import vsmlrt

	plg_dir = os.path.dirname(core.trt.Version()["path"]).decode()
	mdl_pth_rel = plg_dir + "/models/" + model_pth
	if not os.path.exists(mdl_pth_rel) and not os.path.exists(model_pth) :
		raise vs.Error(f"模块 {func_name} 所请求的模型缺失")
	mdl_pth = mdl_pth_rel if os.path.exists(mdl_pth_rel) else model_pth

	fmt_in = input.format.id
	colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)

	mdl_info = ONNX_ANZ(input=mdl_pth)
	if not mdl_info["valid"] :
		raise vs.Error(f"模块 {func_name} 的输入模型无效: {mdl_info['error']}")
	fp16_mdl = mdl_info["elem_type_name"] == "fp16"
	if fp16_mdl :
		fp16_qnt = True   ### 量化精度与模型精度匹配
	gray_mdl = mdl_info["shape"][1] == 1

	nv1, nv2, nv3 = [bool(num) for num in cuda_opt]
	if int8_qnt :
		fp16_qnt = True

	gray_fmt = vs.GRAYH if fp16_qnt else vs.GRAYS
	rgb_fmt = vs.RGBH if fp16_qnt else vs.RGBS
	yuv_fmt = vs.YUV444PH if fp16_qnt else vs.YUV444PS

	be_param = vsmlrt.BackendV2.TRT(
		builder_optimization_level=opt_lv, short_path=True, device_id=gpu,
		num_streams=gpu_t, use_cuda_graph=nv1, use_cublas=nv2, use_cudnn=nv3,
		int8=int8_qnt, fp16=fp16_qnt, tf32=False if fp16_qnt else True,
		output_format=1 if fp16_qnt else 0, workspace=None if ws_size < 128 else (ws_size if st_eng else ws_size * 2),
		static_shape=st_eng, min_shapes=[0, 0] if st_eng else [384, 384],
		opt_shapes=None if st_eng else res_opt, max_shapes=None if st_eng else res_max)

	if gray_mdl :
		clip_y = core.resize.Point(clip=input, format=gray_fmt)
		infer = vsmlrt.inference(clips=clip_y, network_path=mdl_pth, backend=be_param)
		clip_uv = core.resize.Bilinear(clip=input, format=yuv_fmt)
		output = core.std.ShufflePlanes([infer, clip_uv], [0, 1, 2], vs.YUV)
		output = core.resize.Bilinear(clip=output, format=fmt_in, range=1 if colorlv==0 else None)
	else :
		clip = core.resize.Point(clip=input, format=rgb_fmt, matrix_in_s="709")
		infer = vsmlrt.inference(clips=clip, network_path=mdl_pth, backend=be_param)
		if crc :
			infer = DCF(input=infer, ref=clip)
		output = core.resize.Bilinear(clip=infer, format=fmt_in, matrix_s="709", range=1 if colorlv==0 else None)

	return output

##################################################
## 自定义MadVR渲染 # TODO
##################################################

def UVR_MAD(
	input : vs.VideoNode,
	ngu : typing.Literal[0, 1, 2, 3, 4] = 0,
	ngu_q : typing.Literal[1, 2, 3, 4] = 1,
	rca_lv : typing.Literal[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14] = 0,
	rca_q : typing.Literal[1, 2, 3, 4] = 1,
#	uopts : typing.Optional[str] = None, # TODO
) -> vs.VideoNode :

	func_name = "UVR_MAD"
	_validate_input_clip(func_name, input)
	_validate_literal(func_name, "ngu", ngu, [0, 1, 2, 3, 4])
	_validate_literal(func_name, "ngu_q", ngu_q, [1, 2, 3, 4])
	_validate_literal(func_name, "rca_lv", rca_lv, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])
	_validate_literal(func_name, "rca_q", rca_q, [1, 2, 3, 4])

	_check_plugin(func_name, "madvr")

	w_in, h_in = input.width, input.height
	colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)
	fmt_in = input.format.id
	fmt_mad = [vs.YUV420P8, vs.YUV420P10, vs.YUV420P16, vs.YUV422P8, vs.YUV422P10, vs.YUV422P16, vs.YUV440P8, vs.YUV444P8, vs.YUV444P10, vs.YUV444P16]
	algo = (["nguAa", "nguSoft", "nguStandard", "nguSharp"][ngu - 1] + ["Low", "Medium", "High", "VeryHigh"][ngu_q - 1]) if ngu > 0 else None
	w_rs, h_rs = w_in * 2, h_in * 2
	quality = ["low", "medium", "high", "veryHigh"][rca_q - 1]

	param_size1 = ("upscale(newWidth=%d,newHeight=%d,algo=%s,sigmoidal=on)" % (w_rs, h_rs, algo)) if algo is not None else None
	param_other2 = ("rca(strength=%d,quality=%s)" % (rca_lv, quality)) if rca_lv > 0 else None
	param_format3 = "setOutputFormat(format=yuv444,bitdepth=10)"
	mad_param = []
	for var in [param_size1, param_other2, param_format3] :
		if var is not None :
			mad_param.append(var)

	if fmt_in not in fmt_mad :
		cut0 = core.resize.Bilinear(clip=input, format=vs.YUV444P10)
	else :
		cut0 = input
	output = core.madvr.Process(clip=cut0, commands=mad_param, adapter=False)
	if colorlv == 0 :
		output = core.resize.Bilinear(clip=output, range=1)

	return output
