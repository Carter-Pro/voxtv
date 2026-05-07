- # VoxTV 图标应用说明

  本文档用于交给 Claude Code，目标是在当前 macOS 工程中应用 VoxTV 的两个图标：

  1. **彩色 App 图标**：用于 Dock、Finder、应用列表、设置等场景。
  2. **单色菜单栏图标**：用于 macOS menu bar / status item，支持 light mode 和 dark mode 自动适配。

  请严格按本文档执行，不要改动语音识别、Apple TV 控制、Dashboard、配置、日志等业务逻辑。

  ------

  ## 1. 设计目标

  App 名称：**VoxTV**

  Logo 语义：

  - **圆角电视屏幕**：表示电视 / Apple TV 输入场景。
  - **声波曲线**：表示语音输入。
  - **中间隐含 V 形**：对应 Vox / Voice / VoxTV。
  - **简洁几何风格**：保证在小尺寸下仍然可识别。

  设计原则：

  - 不使用 Apple 官方 Logo。
  - 不使用 Apple TV 官方图标。
  - 不在图标中放文字。
  - App 图标可以使用渐变和阴影。
  - 菜单栏图标必须是单色 template image。
  - 菜单栏图标必须在 macOS light / dark mode 下都清晰。
  - 菜单栏图标必须保留“圆角电视外框”，不能退化成普通矩形、方框、麦克风或声波单独图标。

  ------

  ## 2. 图标一：彩色 App 图标

  用途：

  - Dock
  - Finder
  - Launchpad
  - App Switcher
  - 系统设置 / 权限列表
  - `.app` bundle 图标

  建议资源名：

  ```text
  AppIcon.appiconset
  ```

  或如果项目已有默认 AppIcon，则直接替换现有：

  ```text
  Assets.xcassets/AppIcon.appiconset
  ```

  ### 2.1 彩色 App 图标 SVG 源文件

  请将下面内容保存为：

  ```text
  design/VoxTV-AppIcon.svg
  <svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="title desc">
    <title id="title">VoxTV App Icon</title>
    <desc id="desc">A rounded TV outline with a voice wave forming a hidden V shape, designed for VoxTV.</desc>
    <defs>
      <linearGradient id="bg" x1="180" y1="140" x2="850" y2="900" gradientUnits="userSpaceOnUse">
        <stop offset="0" stop-color="#1D4ED8"/>
        <stop offset="0.55" stop-color="#4338CA"/>
        <stop offset="1" stop-color="#0891B2"/>
      </linearGradient>
      <linearGradient id="wave" x1="270" y1="400" x2="760" y2="640" gradientUnits="userSpaceOnUse">
        <stop offset="0" stop-color="#67E8F9"/>
        <stop offset="1" stop-color="#FFFFFF"/>
      </linearGradient>
      <filter id="softShadow" x="-20%" y="-20%" width="140%" height="140%">
        <feDropShadow dx="0" dy="28" stdDeviation="34" flood-color="#172554" flood-opacity="0.22"/>
      </filter>
    </defs>
  
    <rect x="96" y="96" width="832" height="832" rx="216" fill="url(#bg)" filter="url(#softShadow)"/>
  
    <rect x="230" y="260" width="564" height="380" rx="76" fill="none" stroke="#FFFFFF" stroke-width="58" stroke-linecap="round" stroke-linejoin="round"/>
  
    <path d="M318 462 C368 462 368 560 418 560 C468 560 468 376 518 376 C568 376 568 560 618 560 C668 560 668 462 718 462" fill="none" stroke="url(#wave)" stroke-width="64" stroke-linecap="round" stroke-linejoin="round"/>
  
    <path d="M512 640 L512 720" fill="none" stroke="#FFFFFF" stroke-width="54" stroke-linecap="round"/>
    <path d="M404 744 H620" fill="none" stroke="#FFFFFF" stroke-width="54" stroke-linecap="round"/>
  </svg>
  ```

  ### 2.2 AppIcon 生成要求

  请根据 `design/VoxTV-AppIcon.svg` 生成 macOS AppIcon 所需尺寸，并放入：

  ```text
  Assets.xcassets/AppIcon.appiconset/
  ```

  需要包含常见 macOS icon 尺寸：

  ```text
  16x16
  16x16@2x = 32x32
  32x32
  32x32@2x = 64x64
  128x128
  128x128@2x = 256x256
  256x256
  256x256@2x = 512x512
  512x512
  512x512@2x = 1024x1024
  ```

  如果项目使用 Xcode 自动管理 AppIcon，请保持 `Contents.json` 格式正确。

  ------

  ## 3. 图标二：单色菜单栏图标

  用途：

  - macOS menu bar
  - NSStatusItem
  - SwiftUI MenuBarExtra

  建议资源名：

  ```text
  MenuBarIcon.imageset
  ```

  或：

  ```text
  VoxTVMenuBarIcon.imageset
  ```

  ### 3.1 菜单栏图标设计说明

  菜单栏图标不能直接使用彩色 App 图标。原因：

  - 菜单栏尺寸很小，通常只有 16pt 到 18pt。
  - 彩色渐变在菜单栏会显得脏、糊、不统一。
  - macOS 菜单栏图标应使用 template image，由系统根据 light / dark mode 自动渲染颜色。

  菜单栏版本保留核心符号：

  ```text
  圆角电视外框 + 简化声波 V
  ```

  移除：

  - 背景渐变
  - 阴影
  - 电视底座
  - 复杂色彩
  - 过细线条

  ### 3.2 菜单栏 SVG 源文件

  请将下面内容保存为：

  ```text
  design/VoxTV-MenuBarIcon.svg
  ```

  这是当前指定版本。不要自行重画为普通矩形，也不要让转换工具自动裁剪掉圆角和边距。

  ```svg
  <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="title desc">
    <title id="title">VoxTV Menu Bar Icon</title>
    <desc id="desc">A monochrome rounded TV outline with a simplified voice wave forming a hidden V shape.</desc>
  
    <rect x="7" y="13" width="50" height="36" rx="10" ry="10"
          fill="none"
          stroke="#000000"
          stroke-width="5.5"
          stroke-linecap="round"
          stroke-linejoin="round"/>
  
    <path d="M17 32 C21 32 21 39 25 39 C29 39 29 24 33 24 C37 24 37 39 41 39 C45 39 45 32 49 32"
          fill="none"
          stroke="#000000"
          stroke-width="6"
          stroke-linecap="round"
          stroke-linejoin="round"/>
  </svg>
  ```

  ### 3.3 菜单栏图标必须保留圆角电视外框

  之前生成出来的图标外框不像圆角电视，通常是下面几个原因导致的：

  1. **SVG 转 PNG 时被裁剪**：外框边缘被贴边裁掉，圆角看起来像普通矩形。
  2. **小尺寸线宽过粗**：18pt 下 stroke 太粗，圆角细节被挤没。
  3. **转换工具不支持 `rx` / `ry` 或处理异常**：圆角矩形被转成了普通矩形。
  4. **Assets 导入后缩放方式不对**：图形被拉伸或裁切。
  5. **代码仍然引用旧麦克风图标或旧资源名**：实际显示的不是新图标。

  因此实现时必须检查：

  - SVG 原文件中 `<rect>` 必须保留 `rx="10" ry="10"`。
  - 导出的 PNG / PDF 必须有透明边距，不能紧贴画布边缘。
  - 不要使用自动裁剪参数，例如 ImageMagick 的 `-trim`。
  - 不要手工把圆角矩形转换为普通矩形。
  - 不要用 SF Symbol 的 `mic`、`tv`、`waveform` 替代这个自定义图标。
  - 替换资源后必须确认菜单栏实际引用的是新资源，而不是旧图标缓存或旧资源名。

  ### 3.4 菜单栏 PDF / PNG 资源要求

  请从 `design/VoxTV-MenuBarIcon.svg` 生成 template 资源。

  优先推荐：使用 PDF vector asset

  ```text
  Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.pdf
  ```

  如果 PDF vector asset 显示正常，优先使用 PDF，因为它更适合 macOS 菜单栏小尺寸缩放。

  备选：使用 PNG 多倍图

  ```text
  Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png       # 18x18 or 20x20
  Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png    # 36x36 or 40x40
  Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@3x.png    # 可选
  ```

  菜单栏图标要求：

  - 背景透明。
  - 图形为纯黑色或纯白色均可，但必须作为 template image 使用。
  - 不要包含彩色渐变。
  - 不要包含阴影。
  - 小尺寸下外框和声波都必须清晰。
  - 图标需要留出适当透明边距，避免菜单栏显示时圆角被系统裁切。

  ------

  ## 4. macOS 代码接入要求

  请先检查项目当前使用的是哪种菜单栏实现方式。

  可能情况一：SwiftUI `MenuBarExtra`

  示例方向：

  ```swift
  MenuBarExtra {
      // menu content
  } label: {
      Image("MenuBarIcon")
          .renderingMode(.template)
  }
  ```

  如果当前代码使用 SF Symbol，例如：

  ```swift
  Image(systemName: "mic")
  ```

  必须替换为 asset image：

  ```swift
  Image("MenuBarIcon")
      .renderingMode(.template)
  ```

  可能情况二：AppKit `NSStatusItem`

  示例方向：

  ```swift
  let image = NSImage(named: "MenuBarIcon")
  image?.isTemplate = true
  statusItem.button?.image = image
  ```

  如果当前代码使用 SF Symbol，例如：

  ```swift
  NSImage(systemSymbolName: "mic", accessibilityDescription: "VoxTV")
  ```

  必须替换为 asset image，并设置 template：

  ```swift
  let image = NSImage(named: "MenuBarIcon")
  image?.isTemplate = true
  statusItem.button?.image = image
  ```

  无论使用哪种方式，都必须确保：

  ```text
  菜单栏图标按 template image 渲染。
  ```

  不要把彩色 AppIcon 用作菜单栏图标。

  ------

  ## 5. Claude Code 执行流程

  请严格按以下流程执行。

  ### 5.1 第一轮：只做检查和计划，不写代码

  收到本文档后，请先不要写代码。

  请完成：

  1. 阅读 `CLAUDE.md`。
  2. 阅读 `docs/technical-plan.md`。
  3. 检查当前项目结构。
  4. 检查当前菜单栏图标实现方式。
  5. 检查当前 `Assets.xcassets` 结构。
  6. 判断应该新增还是替换图标资源。
  7. 确认当前菜单栏是否仍在使用 SF Symbol 麦克风图标。
  8. 确认当前构建系统是否支持 SVG / PDF / PNG asset。
  9. 输出实现计划。

  请按下面格式回复：

  ```markdown
  ## 任务理解
  
  ## 当前实现检查结果
  
  ## 当前菜单栏图标引用位置
  
  ## 预计修改文件
  
  ## 实现计划
  
  ## 验证方式
  
  ## 风险点
  ```

  等我确认后再继续。

  ### 5.2 第二轮：确认后再执行

  我确认后，会发送：

  ```markdown
  计划确认，可以开始实现。
  
  请严格限制改动范围，只处理 VoxTV AppIcon、MenuBarIcon 资源与引用。
  不要改动语音识别、Apple TV 控制、Dashboard、配置、日志等业务逻辑。
  完成后运行构建验证。
  ```

  这时才可以开始修改文件。

  ------

  ## 6. 实施任务清单

  确认后请完成以下任务：

  1. 新增目录：

  ```text
  design/
  ```

  1. 新增 SVG 源文件：

  ```text
  design/VoxTV-AppIcon.svg
  design/VoxTV-MenuBarIcon.svg
  ```

  1. 生成或更新 AppIcon 资源：

  ```text
  Assets.xcassets/AppIcon.appiconset/
  ```

  1. 新增菜单栏图标资源，优先使用 PDF vector asset：

  ```text
  Assets.xcassets/MenuBarIcon.imageset/
  ```

  1. 更新菜单栏图标引用：

  ```text
  MenuBarIcon
  ```

  1. 确认菜单栏图标 template rendering：

  - SwiftUI：使用 `.renderingMode(.template)`。
  - AppKit：设置 `image.isTemplate = true`。

  1. 如果生成 PNG，必须检查透明边距和圆角是否保留。
  2. 构建项目，确认无资源错误。

  ------

  ## 7. 验收标准

  完成后必须满足：

  - App 图标已替换为 VoxTV 彩色图标。
  - 菜单栏图标不再是默认麦克风图标。
  - 菜单栏图标为单色符号。
  - 菜单栏图标外框明确是圆角电视，而不是普通矩形。
  - 菜单栏图标在 light mode 下清晰。
  - 菜单栏图标在 dark mode 下清晰。
  - 菜单栏图标小尺寸下可识别为“电视 + 声波”。
  - 菜单栏图标没有被裁剪、拉伸或压扁。
  - 没有引入 Apple 官方商标或 Apple TV 官方图标。
  - 没有改动业务逻辑。
  - 项目构建通过。

  ------

  ## 8. 交付汇报格式

  完成后请按以下格式汇报：

  ```markdown
  ## 完成内容
  
  ## 修改文件
  
  ## 验证结果
  
  ## Light / Dark Mode 检查
  
  ## 圆角电视外框检查
  
  ## 遗留问题或建议
  ```

  如果无法自动生成 `.appiconset` 所需 PNG，请说明原因，并至少保留：

  ```text
  design/VoxTV-AppIcon.svg
  design/VoxTV-MenuBarIcon.svg
  ```

  同时给出手动生成命令或建议工具。

  ------

  ## 9. 可选生成命令参考

  如果本机安装了 ImageMagick，可参考：

  ```bash
  mkdir -p Assets.xcassets/AppIcon.appiconset
  magick -background none design/VoxTV-AppIcon.svg -resize 16x16 Assets.xcassets/AppIcon.appiconset/icon_16x16.png
  magick -background none design/VoxTV-AppIcon.svg -resize 32x32 Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png
  magick -background none design/VoxTV-AppIcon.svg -resize 32x32 Assets.xcassets/AppIcon.appiconset/icon_32x32.png
  magick -background none design/VoxTV-AppIcon.svg -resize 64x64 Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png
  magick -background none design/VoxTV-AppIcon.svg -resize 128x128 Assets.xcassets/AppIcon.appiconset/icon_128x128.png
  magick -background none design/VoxTV-AppIcon.svg -resize 256x256 Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png
  magick -background none design/VoxTV-AppIcon.svg -resize 256x256 Assets.xcassets/AppIcon.appiconset/icon_256x256.png
  magick -background none design/VoxTV-AppIcon.svg -resize 512x512 Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png
  magick -background none design/VoxTV-AppIcon.svg -resize 512x512 Assets.xcassets/AppIcon.appiconset/icon_512x512.png
  magick -background none design/VoxTV-AppIcon.svg -resize 1024x1024 Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
  ```

  生成菜单栏 PNG 时不要使用 `-trim`，并建议先生成较大图再缩放：

  ```bash
  mkdir -p Assets.xcassets/MenuBarIcon.imageset
  magick -background none design/VoxTV-MenuBarIcon.svg -resize 20x20 Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png
  magick -background none design/VoxTV-MenuBarIcon.svg -resize 40x40 Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png
  magick -background none design/VoxTV-MenuBarIcon.svg -resize 60x60 Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@3x.png
  ```

  如果发现圆角不明显，可以改用 22 / 44 / 66 尺寸试一次，但代码侧仍按菜单栏 template image 使用。

  如果使用 `sips`，SVG 支持不稳定，建议先用 Sketch、Figma、Preview、Inkscape、ImageMagick 或 Xcode 支持的 PDF vector asset 方式处理。

  ------

  ## 10. 菜单栏图标专项注意事项

  ### 10.1 不要让图标外框变成普通矩形

  菜单栏图标的关键识别点不是“一个屏幕方框”，而是“圆角电视屏幕”。因此：

  - 必须保留 `rx` / `ry` 圆角属性。
  - 不能用普通 `<rect>` 但不带 `rx` / `ry`。
  - 不能在生成 PNG 时裁掉透明边距。
  - 不能把线宽调到把圆角挤没。
  - 不能用只有声波的图标替代。

  ### 10.2 如果小尺寸不清晰，优先这样调整

  如果 18pt 下圆角电视不够明显，调整优先级如下：

  1. 先增加画布透明边距。
  2. 再略微减小 stroke-width。
  3. 再加大 `rx` / `ry`。
  4. 最后才考虑简化内部声波。

  不要第一反应就删除圆角、删除电视外框，或者换回 SF Symbol。

  ### 10.3 如果图标显示仍是麦克风

  请检查：

  - SwiftUI 中是否仍然使用 `Image(systemName: "mic")`。
  - AppKit 中是否仍然使用 `NSImage(systemSymbolName: "mic", ...)`。
  - Assets 中是否存在同名旧资源。
  - 代码引用的资源名是否确实是 `MenuBarIcon`。
  - Xcode 是否缓存了旧 asset，必要时 clean build。

  ### 10.4 如果图标显示为黑块或白块

  请检查：

  - PNG 是否有透明背景。
  - SVG/PDF 是否没有背景填充矩形。
  - 是否把 AppIcon 当成菜单栏图标用了。
  - 是否错误地导出了带底色的图片。

  ### 10.5 如果 light / dark mode 下颜色不对

  请检查：

  - AppKit 是否设置 `image.isTemplate = true`。
  - SwiftUI 是否设置 `.renderingMode(.template)`。
  - Asset catalog 中是否没有设置成固定彩色渲染。
  - 是否错误使用彩色 PNG 而不是 template 图标。

  ### 10.6 如果圆角在 SVG 正常、PNG 不正常

  请优先改用 PDF vector asset，或者用支持 SVG 圆角矩形更稳定的工具生成，例如 Inkscape、Figma、Sketch、ImageMagick。

  不要使用会丢失 SVG 圆角属性的转换流程。

  ------

  ## 11. 最终提醒

  - 菜单栏图标不要追求完整表达 App 图标细节。
  - 菜单栏 18pt 下最重要的是轮廓清楚。
  - 如果电视外框和声波在 18pt 下过密，可以进一步简化内部声波，但不要删除圆角电视外框。
  - 如果使用 `NSImage.SymbolConfiguration` 或 SF Symbols，请不要继续用麦克风 SF Symbol 作为最终图标。
  - 本任务属于 UI 资源替换，不属于 Phase 功能扩展。
