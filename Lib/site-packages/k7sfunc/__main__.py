
import sys
from .version import __version__

def main():

	print(f"K7sfunc v{__version__}")
	print("\nK7的VapourSynth视频处理的预设工具集")
	print("=" * 50)
	print("\n使用方法：")
	print("  在 Python 脚本中导入：")
	print("    import k7sfunc as k7f")
	print("    clip = k7f.RIFE_NV(input=clip, ...)")
	print("\n文档： https://github.com/hooke007/mpv_PlayKit/wiki/3_K7sfunc")
	print("=" * 50)

if __name__ == "__main__":
	sys.exit(main())

