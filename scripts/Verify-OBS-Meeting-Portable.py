#!/usr/bin/env python3
"""Source-level checks only. A Windows runtime test is still mandatory."""
import argparse
from pathlib import Path
import re


def main():
    a=argparse.ArgumentParser()
    a.add_argument('--root',required=True)
    a.add_argument('--report',required=True)
    args=a.parse_args()
    root=Path(args.root)
    files={
        'shader':root/'libobs-d3d11/d3d11-shader.cpp',
        'subsystem':root/'libobs-d3d11/d3d11-subsystem.cpp',
        'plugin':root/'plugins/win-capture/plugin-main.c',
        'header':root/'libobs-d3d11/obs-meeting-shader-cache.hpp',
    }
    text={k:v.read_text(encoding='utf-8-sig') for k,v in files.items()}
    init=text['plugin'].split('bool obs_module_load(void)',1)
    init_body=init[1].split('void obs_module_unload(void)',1)[0] if len(init)==2 else ''
    checks={
        'both shader callers use redirected helper': all('obs_meeting_shader_cache_path_ptr()' in text[k] for k in ('shader','subsystem')),
        'original ProgramData shader calls absent':all('os_get_program_data_path_ptr("obs-studio/shader-cache")' not in text[k] for k in ('shader','subsystem')),
        'helper tied to process executable, not host ProgramData': 'GetModuleFileNameW' in text['header'] and 'obs-studio' in text['header'] and 'shader-cache' in text['header'] and 'ProgramData' not in text['header'],
        'helper refuses failed resolution instead of falling back': 'throw std::runtime_error' in text['header'],
        'Display Capture registration kept': 'obs_register_source(&duplicator_capture_info);' in init_body and 'obs_register_source(&monitor_capture_info);' in init_body,
        'Window Capture registration kept': 'obs_register_source(&window_capture_info);' in init_body,
        'Game Capture hook deployment not called in module load':re.search(r'(?m)^\s*init_hook_files\s*\(',init_body) is None,
        'Game Capture thread creation not called in module load':'CreateThread(NULL, 0, init_hooks, config_path, 0, NULL)' not in init_body,
        'Game Capture registration removed from module load':'obs_register_source(&game_capture_info);' not in init_body,
        'shader source patch marker present': 'OBS_MEETING_PORTABLE_V1' in text['shader'],
        'subsystem source patch marker present': 'OBS_MEETING_PORTABLE_V1' in text['subsystem'],
        'plugin source patch marker present': 'OBS_MEETING_PORTABLE_V1' in text['plugin'],
    }
    lines=['OBS MEETING PORTABLE SOURCE VERIFICATION', '']
    lines += [('PASS' if v else 'FAIL')+': '+k for k,v in checks.items()]
    lines += ['', 'Not a compiled/runtime test; ProgramData and registry traces may remain.',
              'Game Capture intentionally disabled; Display/Window Capture retained by source.',
              'Audio/microphone capture and MKV still require a real Windows recording test.']
    report='\n'.join(lines)+'\n'
    dest=Path(args.report); dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(report,encoding='utf-8'); print(report)
    if not all(checks.values()):raise SystemExit('Source verifier failed; build blocked')

if __name__=='__main__':main()
