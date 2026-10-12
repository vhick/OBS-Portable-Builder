"""Local regression tests using reconstructed excerpts from source inspection.
These are NOT Windows compilation or runtime tests.
"""
import subprocess, tempfile, sys
from pathlib import Path

SCRIPT=Path(__file__).with_name('Patch-OBS-Meeting-Portable.py')
VERIFY=Path(__file__).with_name('Verify-OBS-Meeting-Portable.py')

SHADER='''#include "d3d11-shaderprocessor.hpp"
#include <filesystem>
BPtr program_data = os_get_program_data_path_ptr("obs-studio/shader-cache");
auto cachePath = std::filesystem::u8path(program_data.Get()) / hashstr;
'''
SUBSYSTEM='''#include "d3d11-subsystem.hpp"
static void CreateShaderCacheDirectory()
{
  BPtr cachePath = os_get_program_data_path_ptr("obs-studio/shader-cache");
  if (os_mkdirs(cachePath) == MKDIR_ERROR) {}
}
'''
PLUGIN='''extern struct obs_source_info game_capture_info;
bool obs_module_load(void)
{
  if (win8_or_above && graphics_uses_d3d11)
    obs_register_source(&duplicator_capture_info);
  else
    obs_register_source(&monitor_capture_info);
  obs_register_source(&window_capture_info);
  char *config_path = obs_module_config_path(NULL);

  init_hook_files();
  init_hooks_thread = CreateThread(NULL, 0, init_hooks, config_path, 0, NULL);
  obs_register_source(&game_capture_info);
  return true;
}
void obs_module_unload(void) {}
'''

def run(line_ending):
    with tempfile.TemporaryDirectory() as d:
        root=Path(d)
        for f,content in [('libobs-d3d11/d3d11-shader.cpp',SHADER),('libobs-d3d11/d3d11-subsystem.cpp',SUBSYSTEM),('plugins/win-capture/plugin-main.c',PLUGIN)]:
            p=root/f; p.parent.mkdir(parents=True,exist_ok=True)
            p.write_bytes(content.replace('\n',line_ending).encode())
        report=root/'report.txt'
        a=subprocess.run([sys.executable,str(SCRIPT),'--root',str(root),'--report',str(report)],capture_output=True,text=True)
        assert a.returncode==0, (a.stdout,a.stderr)
        b=subprocess.run([sys.executable,str(VERIFY),'--root',str(root),'--report',str(root/'verify.txt')],capture_output=True,text=True)
        assert b.returncode==0,(b.stdout,b.stderr)
        c=subprocess.run([sys.executable,str(SCRIPT),'--root',str(root),'--report',str(report)],capture_output=True,text=True)
        assert c.returncode!=0,'patch should reject duplicate application'
        assert line_ending.encode() in (root/'libobs-d3d11/d3d11-shader.cpp').read_bytes()
        print('PASS:',repr(line_ending),'patch, source checks, repeat-patch refusal')

for newline in ('\n','\r\n'):run(newline)
print('ALL MOCK SOURCE TESTS PASSED — not a Windows compilation')
