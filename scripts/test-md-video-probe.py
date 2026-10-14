#!/usr/bin/env python3
import subprocess
from pathlib import Path
out=Path('/build/md-video-probe');out.mkdir(exist_ok=True)
subprocess.run(['verilator','--binary','--timing','--top-module','tb_md_video_probe','-Wno-fatal','-I/work/build/hdl/md','--build-jobs','1','--Mdir',str(out),'/work/build/hdl/md/Genesis.sv','/work/rtl/video/km_frame_config_cdc.sv','/work/sim/tb_md_video_probe.sv'],check=True,cwd=out)
subprocess.run([str(out/'Vtb_md_video_probe')],check=True,cwd=out)
