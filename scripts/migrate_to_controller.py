#!/usr/bin/env python3
import re
import os

# 所有需要修改的文件
files = [
    "AttractorLine.swift", "Bifurcation.swift", "Chords.swift", "CornerBouncing.swift",
    "CubesMoving.swift", "CubesNested.swift", "Fireworks.swift", "FireworksBlow.swift",
    "FractalBranches.swift", "FractalTree.swift", "FractalUmbrella.swift", "HopfFibration.swift",
    "HopfFibrationLayer.swift", "HyperbolicHelicoid.swift", "Lotus.swift", "MobiusBubbles.swift",
    "MobiusGrid.swift", "MobiusTrail.swift", "MovingLorenz.swift", "Nebula.swift",
    "Nest.swift", "PolygonWall.swift", "RadicalLine.swift", "Snowflake.swift",
    "SphereBouncing.swift", "SphereLine.swift"
]

base_path = "/Users/chenyong/repo/immersive/immersive-attractors/triangle"

for filename in files:
    filepath = os.path.join(base_path, filename)
    print(f"Processing: {filename}")

    with open(filepath, 'r') as f:
        content = f.read()

    modified = False

    # 1. 添加 controllerHelper 属性 (如果还没有)
    if "let controllerHelper = ControllerHelper()" not in content:
        # 在 @State private var updateTrigger 后面添加
        pattern = r'(@State private var updateTrigger = false)'
        replacement = r'\1\n\n  // MARK: - Controller for gamepad input\n  let controllerHelper = ControllerHelper()'
        if re.search(pattern, content):
            content = re.sub(pattern, replacement, content)
            modified = True
            print(f"  Added controllerHelper property")

    # 2. 注释掉 CollisionComponent (多行)
    # 匹配从 "let bounds = getBounds()" 到 CollisionComponent 结束的 "))"
    collision_pattern = r'(\s+)(let bounds = getBounds\(\)\n\s+rootEntity\.components\.set\(\n\s+CollisionComponent\(\n\s+shapes: \[\n\s+\.generateBox\(\n\s+width: bounds\.extents\.x \* \d+,\n\s+height: bounds\.extents\.y \* \d+,\n\s+depth: bounds\.extents\.z \* \d+\)\n\s+\]\n\s+\)\))'
    if re.search(collision_pattern, content) and "// Controller: let bounds" not in content:
        def comment_collision(match):
            indent = match.group(1)
            block = match.group(2)
            # 给每行添加注释
            lines = block.split('\n')
            commented = '\n'.join([indent + '// Controller: ' + line.strip() if line.strip() else line for line in lines])
            return commented
        content = re.sub(collision_pattern, comment_collision, content)
        modified = True
        print(f"  Commented CollisionComponent")

    # 3. 注释掉手势代码 (.gesture 和 .simultaneousGesture)
    # 这个比较复杂，需要匹配整个手势块
    gesture_patterns = [
        # DragGesture
        r'(\.gesture\(\n\s+DragGesture\(\)[\s\S]*?\.onEnded \{ _ in[\s\S]*?\}\n\s+\)\n\s+\))',
        # RotateGesture3D
        r'(\.gesture\(\n\s+RotateGesture3D\(\)[\s\S]*?\.onEnded \{ _ in[\s\S]*?\}\n\s+\)\n\s+\))',
        # MagnifyGesture
        r'(\.simultaneousGesture\(\n\s+MagnifyGesture\(\)[\s\S]*?\.onEnded \{ _ in[\s\S]*?\}\n\s+\)\n\s+\))',
    ]

    for pattern in gesture_patterns:
        match = re.search(pattern, content)
        if match and "// Controller: .gesture" not in content:
            block = match.group(1)
            # 注释掉整个块
            lines = block.split('\n')
            commented_lines = ['      // Controller: ' + line.lstrip() if line.strip() else line for line in lines]
            commented_block = '\n'.join(commented_lines)
            content = content.replace(block, commented_block)
            modified = True
            print(f"  Commented gesture block")

    # 4. 在 startTimer 中添加 controllerHelper.reset()
    if "controllerHelper.reset()" not in content:
        pattern = r'(func startTimer\(\) \{\n\s+self\.mesh = try! createMesh\(\))'
        replacement = r'\1\n    controllerHelper.reset()  // Reset controller timing'
        if re.search(pattern, content):
            content = re.sub(pattern, replacement, content)
            modified = True
            print(f"  Added controllerHelper.reset()")

    # 5. 在 timer 循环中添加控制器更新
    if "controllerHelper.updateEntityTransform(rootEntity)" not in content:
        pattern = r'(self\.updateTrigger\.toggle\(\))'
        replacement = r'// Update controller input\n        self.controllerHelper.updateEntityTransform(self.rootEntity)\n        \1'
        if re.search(pattern, content):
            content = re.sub(pattern, replacement, content)
            modified = True
            print(f"  Added controllerHelper.updateEntityTransform()")

    if modified:
        with open(filepath, 'w') as f:
            f.write(content)
        print(f"  Saved: {filename}")
    else:
        print(f"  No changes needed: {filename}")

print("\n=== Done ===")
