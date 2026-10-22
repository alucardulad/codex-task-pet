# 贡献指南

感谢参与 Codex 任务宠物项目。

## 开发环境

- macOS 14+
- Swift 5.10+ 或 Xcode Command Line Tools
- 本机 Codex（仅非演示模式需要）

## 本地检查

```bash
./scripts/build.sh release
swift run AgentPet --demo
./scripts/package.sh
```

提交前至少确认 Release 编译和演示模式启动正常。

## 代码约定

- 保持 `App`、`Models`、`Services`、`Views` 和 `Resources` 的现有职责划分。
- Swift 类型名、方法名和变量名使用英文；注释和文档使用简体中文。
- 不在界面线程外直接更新 SwiftUI 状态。
- 新增定时任务时设置合理间隔和容差，并在对象释放时清理。
- 新增图片时使用透明 PNG，并确认 `WhaleAssetStore` 的缩略与缓存策略仍然有效。
- 不引入不必要的第三方依赖。

## 提交信息

提交信息使用简体中文，简洁描述实际修改，例如：

```text
新增功能：增加任务完成声音开关
修复问题：修复多显示器下窗口位置越界
优化：降低任务面板关闭后的内存占用
```

## 截图与隐私

- 使用演示模式截图。
- 不提交真实任务标题、项目名、用户名、终端输出、访问令牌或其他敏感信息。
- 不在代码、文档或 Issue 中粘贴 API Key、OAuth Token 或本机凭据。

## 美术资源

鲸鱼娘图片授权情况请先阅读 [ASSETS.md](ASSETS.md)。提交新美术资源时，应同时注明作者和授权方式。
