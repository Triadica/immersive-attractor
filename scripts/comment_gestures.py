#!/usr/bin/env python3
import re
import os

# 所有需要修改的文件
files = [
    "AttractorLine.swift", "Bifurcation.swift", "Chords.swift", "CornerBouncing.swift",
    "CubesMoving.swift", "CubesNested.swift", "Fireworks.swift", "FireworksBlow.swift",
    "HopfFibration.swift", "HopfFibrationLayer.swift", "HyperbolicHelicoid.swift",
    "Lotus.swift", "MobiusBubbles.swift", "MobiusGrid.swift", "MobiusTrail.swift",
    "MovingLorenz.swift", "Nebula.swift", "Nest.swift", "PolygonWall.swift",
    "RadicalLine.swift", "Snowflake.swift", "SphereBouncing.swift", "SphereLine.swift"
]

base_path = "/Users/chenyong/repo/immersive/immersive-attractors/triangle"

def comment_gesture_blocks(content):
    """注释掉所有手势代码块"""
    lines = content.split('\n')
    result = []
    in_gesture_block = False
    brace_count = 0
    gesture_indent = 0

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # 检测手势块开始
        if not in_gesture_block:
            if stripped.startswith('.gesture(') or stripped.startswith('.simultaneousGesture('):
                # 检查是否已经被注释
                if '// Controller:' in line or line.strip().startswith('//'):
                    result.append(line)
                    i += 1
                    continue

                in_gesture_block = True
                gesture_indent = len(line) - len(line.lstrip())
                brace_count = line.count('(') - line.count(')')

                # 注释这行
                result.append(' ' * gesture_indent + '// Controller: ' + stripped)
                i += 1
                continue

        if in_gesture_block:
            # 继续注释手势块内的所有行
            brace_count += line.count('(') - line.count(')')

            # 注释这行（保持缩进）
            if stripped:
                result.append(' ' * gesture_indent + '// Controller: ' + stripped)
            else:
                result.append(line)

            # 检查是否到达块结束
            if brace_count <= 0:
                in_gesture_block = False

            i += 1
            continue

        result.append(line)
        i += 1

    return '\n'.join(result)

for filename in files:
    filepath = os.path.join(base_path, filename)
    print(f"Processing: {filename}")

    with open(filepath, 'r') as f:
        content = f.read()

    # 检查是否有未注释的手势代码
    if '.gesture(' in content or '.simultaneousGesture(' in content:
        # 检查是否有未注释的
        lines = content.split('\n')
        has_uncommented = False
        for line in lines:
            stripped = line.strip()
            if (stripped.startswith('.gesture(') or stripped.startswith('.simultaneousGesture(')) and '// Controller:' not in line:
                has_uncommented = True
                break

        if has_uncommented:
            new_content = comment_gesture_blocks(content)
            with open(filepath, 'w') as f:
                f.write(new_content)
            print(f"  Commented gesture blocks")
        else:
            print(f"  Already commented")
    else:
        print(f"  No gesture blocks found")

print("\n=== Done ===")
