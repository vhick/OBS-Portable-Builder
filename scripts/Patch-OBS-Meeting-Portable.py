#!/usr/bin/env python3
"""Experimental OBS meeting-only Windows patch; fail closed on source changes.

Inspected baseline: obsproject/obs-studio 7d98bebe1115b12608837b622164ea5fe6d9483a
No edits to upstream fork; intended only for a throw-away GitHub Actions checkout.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import sys

D3D_SHADER = Path('libobs-d3d11/d3d11-shader.cpp')
D3D_SUBSYSTEM = Path('libobs-d3d11/d3d11-subsystem.cpp')
WIN_CAPTURE = Path('plugins/win-capture/plugin-main.c')
HEADER = Path('libobs-d3d11/obs-meeting-shader-cache.hpp')
MARKER = 'OBS_MEETING_PORTABLE_V1'

# Keep same allocation ownership as os_get_program_data_path_ptr: caller uses BPtr.
# The process image root for OBS ZIP layout is ROOT/bin/64bit/obs64.exe.
# If it cannot be resolved, throw rather than silently write into ProgramData.
HEADER_SOURCE = r'''// OBS_MEETING_PORTABLE_V1 - experimental meeting/screen capture only
#pragma once
#include <windows.h>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <util/bmem.h>

inline char *obs_meeting_shader_cache_path_ptr()
{
    // 32768 supports long Windows paths; refuse truncated or invalid paths.
    wchar_t buffer[32768] = {};
    const DWORD len = GetModuleFileNameW(nullptr, buffer, 32768);
    if (len == 0 || len >= 32768)
        throw std::runtime_error("Cannot resolve OBS executable path for portable shader cache");
    auto root = std::filesystem::path(buffer).parent_path().parent_path().parent_path();
    if (root.empty() || root == root.root_path())
        throw std::runtime_error("Unexpected OBS executable layout for portable cache");
    const std::wstring w = (root / L"config" / L"obs-studio" / L"shader-cache").wstring();
    const int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (bytes <= 0)
        throw std::runtime_error("Cannot convert portable shader cache path to UTF-8");
    std::string utf8(static_cast<size_t>(bytes), '\0');
    const int written = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, w.c_str(), -1, utf8.data(), bytes, nullptr, nullptr);
    if (written != bytes)
        throw std::runtime_error("Portable shader cache path conversion failed");
    return bstrdup(utf8.c_str());
}
'''

START_HOOKS = re.compile(
    r'(?m)^[ \t]*char[ \t]+\*[ \t]*config_path[ \t]*=[ \t]*obs_module_config_path\(NULL\);[ \t]*\n'
    r'(?:[ \t]*\n)*[ \t]*init_hook_files\(\);[ \t]*\n'
    r'(?:[ \t]*\n)*[ \t]*init_hooks_thread[ \t]*=[ \t]*CreateThread\(NULL,[ \t]*0,[ \t]*init_hooks,[ \t]*config_path,[ \t]*0,[ \t]*NULL\);[ \t]*\n'
    r'(?:[ \t]*\n)*[ \t]*obs_register_source\(&game_capture_info\);'
)


def exactly_once(source: str, original: str, replacement: str, label: str) -> str:
    count = source.count(original)
    if count != 1:
        raise ValueError(f'{label}: expected original code once; found {count}; source changed upstream')
    return source.replace(original, replacement, 1)


def insert_header(text: str, label: str) -> str:
    # Keep compile dependencies untouched; include the new self-contained helper.
    if MARKER in text or 'obs-meeting-shader-cache.hpp' in text:
        raise ValueError(f'{label}: patch already applied')
    needle = '#include <filesystem>' if label == 'd3d11-shader.cpp' else '#include "d3d11-subsystem.hpp"'
    if needle not in text:
        raise ValueError(f'{label}: expected include {needle!r} missing')
    return exactly_once(text, needle, needle + '\n#include "obs-meeting-shader-cache.hpp"', label)


def patch_shader(source: str) -> str:
    text = insert_header(source, 'd3d11-shader.cpp')
    return exactly_once(text,
        'BPtr program_data = os_get_program_data_path_ptr("obs-studio/shader-cache");',
        'BPtr program_data = obs_meeting_shader_cache_path_ptr(); // OBS_MEETING_PORTABLE_V1',
        'shader cache file path')


def patch_subsystem(source: str) -> str:
    text = insert_header(source, 'd3d11-subsystem.cpp')
    return exactly_once(text,
        'BPtr cachePath = os_get_program_data_path_ptr("obs-studio/shader-cache");',
        'BPtr cachePath = obs_meeting_shader_cache_path_ptr(); // OBS_MEETING_PORTABLE_V1',
        'shader cache creation path')


def patch_capture(source: str) -> str:
    if MARKER in source:
        raise ValueError('win-capture plugin already patched')
    if source.count('obs_register_source(&window_capture_info);') != 1:
        raise ValueError('Window Capture source registration changed; refusing patch')
    if source.count('obs_register_source(&duplicator_capture_info);') != 1:
        raise ValueError('Display Capture source registration changed; refusing patch')
    found=list(START_HOOKS.finditer(source))
    if len(found) != 1:
        raise ValueError(f'Game Capture initialization block changed; found {len(found)} matches')
    # Exclude only Game Capture initialization from obs_module_load;
    # leave the rest of win-capture, including Display and Window Capture, built.
    return START_HOOKS.sub('\t/* OBS_MEETING_PORTABLE_V1: skip Game Capture hook deployment and registration. */',source,count=1)


def main() -> None:
    p=argparse.ArgumentParser()
    p.add_argument('--root',required=True)
    p.add_argument('--report',default='build-report/patch-report.txt')
    args=p.parse_args()
    root=Path(args.root)
    targets={D3D_SHADER:patch_shader, D3D_SUBSYSTEM:patch_subsystem, WIN_CAPTURE:patch_capture}
    prepared={}
    try:
        for rel,transform in targets.items():
            path=root/rel
            if not path.is_file(): raise ValueError(f'Missing source file: {rel}')
            # Preserve LF/CRLF and BOM, despite Python's universal-newlines default.
            raw=path.read_bytes()
            bom=raw.startswith(b'\xef\xbb\xbf')
            body=raw[3:] if bom else raw
            orig=body.decode('utf-8')
            eol='\r\n' if '\r\n' in orig else '\n'
            normalized=orig.replace('\r\n','\n')
            changed=transform(normalized)
            prepared[path]=(b'\xef\xbb\xbf' if bom else b'') + changed.replace('\n',eol).encode('utf-8')
        h=root/HEADER
        if h.exists(): raise ValueError('Experimental header already exists; use a fresh source checkout')
        prepared[h]=HEADER_SOURCE.encode('utf-8')
        # Only write AFTER every patch site passes fail-closed validation.
        for path,blob in prepared.items():
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(blob)
        report=(f'OBS Meeting Portable v1 patch applied\n' +
                '\n'.join(str(f.relative_to(root)) for f in prepared) +
                '\nGame Capture disabled; window/display retained; shader cache is app-relative.\n')
        target=Path(args.report)
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(report,encoding='utf-8')
        print(report)
    except (ValueError, UnicodeError, OSError) as exc:
        raise SystemExit('FAIL CLOSED: '+str(exc))

if __name__=='__main__': main()
