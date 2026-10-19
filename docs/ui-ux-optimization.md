# UI / UX 验收索引

实现入口见[开发索引](README.md)，交互与状态以源码为准。

| 范围 | 实现 | 回归验证 |
| --- | --- | --- |
| 历史重译显示浮窗、语言交换、编辑模式与旧结果、历史回溯 | [AppModel](../Sources/Glint/AppModel.swift)、[应用入口](../Sources/Glint/GlintApp.swift)、[翻译面板](../Sources/Glint/TranslatorView.swift) | [交互测试](../Tests/GlintTests/InteractionTests.swift)、[窗口诊断](../Sources/Glint/AppDiagnostics.swift) |
| 自动语言外显、语义方向完成后的实际语言 | [语言识别](../Sources/GlintCore/Language.swift)、[方向解析](../Sources/GlintCore/TranslationRequest.swift) | [翻译规则测试](../Tests/GlintCoreTests/TranslationRulesTests.swift)、[真实流式交互](../Tests/GlintTests/InteractionTests.swift) |
| 词典引擎联动、原文自动高度与外侧调高控件、清空按钮、细滚动条与译文边缘渐隐、多行编辑、过期结果操作 | [翻译面板](../Sources/Glint/TranslatorView.swift)、[原生输入](../Sources/Glint/NativeInput.swift)、[共用滚动条](../Sources/Glint/Theme.swift)、[结果区](../Sources/Glint/TranslationResult.swift) | [布局测试](../Tests/GlintTests/TranslatorLayoutTests.swift)、[窗口诊断](../Sources/Glint/AppDiagnostics.swift) |
| 浮窗初始位置、屏幕越界、内容顶对齐、自动高度与右侧调宽 | [窗口](../Sources/Glint/WindowController.swift)、[宽度拖拽](../Sources/Glint/Theme.swift)、[结果区](../Sources/Glint/TranslationResult.swift) | [布局与真实窗口流式测试](../Tests/GlintTests/TranslatorLayoutTests.swift)、[窗口诊断](../Sources/Glint/AppDiagnostics.swift) |
| 朗读启停与加载状态 | [朗读服务与按钮](../Sources/Glint/SpeechService.swift) | [交互测试](../Tests/GlintTests/InteractionTests.swift)、[在线音频测试](../Tests/GlintTests/NativeTests.swift) |
| 快捷键录制生命周期、原生菜单键位、标准窗口快捷键 | [快捷键](../Sources/Glint/Hotkeys.swift)、[菜单](../Sources/Glint/GlintApp.swift)、[窗口](../Sources/Glint/WindowController.swift) | [交互测试](../Tests/GlintTests/InteractionTests.swift) |
| 设置缩放、底部边界、词典子项联动、代理开关联动 | [设置](../Sources/Glint/SettingsView.swift) | [窗口诊断](../Sources/Glint/AppDiagnostics.swift)、下方系统验收 |
| 历史全文展开、复制反馈 | [历史卡片](../Sources/Glint/HistoryCard.swift)、[共用控件](../Sources/Glint/Controls.swift) | 下方交互验收 |
| 生词本词头与读音、朗读、复制、重查、删除确认、排序与键盘导航 | [生词本](../Sources/Glint/VocabularyView.swift)、[词条派生字段](../Sources/GlintCore/Models.swift)、[共用控件](../Sources/Glint/Controls.swift) | [翻译规则测试](../Tests/GlintCoreTests/TranslationRulesTests.swift)、[窗口诊断](../Sources/Glint/AppDiagnostics.swift) |
| 跨显示器截图、取消恢复固定浮窗 | [截图服务](../Sources/Glint/CaptureService.swift)、[截图入口](../Sources/Glint/GlintApp.swift) | [图像合成测试](../Tests/GlintTests/CaptureTextTests.swift)、下方系统验收 |
| OCR 自然段、列表、断词与中外文间距 | [OCR 文本](../Sources/Glint/OCRText.swift) | [段落测试](../Tests/GlintTests/CaptureTextTests.swift)、[真实 Vision 测试](../Tests/GlintTests/NativeTests.swift) |
| 外部选区阻塞条件、菜单复制取词、浮标边界与交互态 | [划词入口](../Sources/Glint/GlintApp.swift)、[划词服务](../Sources/Glint/SelectionService.swift) | [划词索引](selection-popup.md)、下方系统验收 |

## 交互验收

使用独立数据目录运行，命令见[开发索引](README.md#验证)。

- 在历史卡片展开全文，分别复制原文和译文，检查反馈；隐藏翻译窗后点击重译。
- 输入足够长的文本执行流式翻译，译文超过最大高度后应停在顶部；点击「回到最新译文」后再跟随底部。
- 输入长原文并滚动、清空，检查默认一行、自动高度上限、细滚动条与清空按钮；悬停输入框上下边框外侧，检查调高光标、拖动与双击恢复自动高度；滚动长译文，检查上下边缘渐隐、首尾完整显示及贴右细滚动条；拖动窗口越过屏幕底边，再从右侧调整宽度，检查内容完整性；底边不应出现高度缩放入口。
- 在生词本取消删除，检查词条与查询次数；确认删除后检查列表、搜索和详情同步。
- 分别使用 Google 与 AI 引擎，检查词典按钮；修改原文后检查旧结果与操作状态，按回车重译。
- 关闭词典自动模式后检查子项；缩放设置窗口并滚动到页面末尾，检查状态栏边界。

## 系统验收

以下项目依赖真实系统权限、服务或显示器，窗口快照与合成图像测试不能替代。

- 使用实际代理地址，分别开启和关闭代理后测试网络，核对显示的连接方式与翻译请求。
- 浏览设置的历史、通用页时使用四个全局快捷键；录制时检查暂停，切换页面、窗口或应用后检查恢复。
- 设置或生词本保留在后台时，在外部应用划词并点击浮标；在深浅背景检查浮标悬停与按下态。
- 轻按或持续按住划词快捷键，检查多行原文、空行与缩进；连续触发后检查剪贴板恢复。
- 在不同缩放比例、左右及上下排列的显示器之间拖动截图选区，核对图像拼接与 OCR；固定浮窗显示时按 Esc 取消截图。
- 检查在线朗读加载、停止、重新播放、切换原文和译文，以及网络失败后的系统朗读。
