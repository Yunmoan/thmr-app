# 仓库协作规则

- 代码中新增或修改的注释使用中文，包括文档注释。
- Git 提交信息遵循 [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)。首行格式为 `type: 中文标题`，可选范围写成 `type(scope): 中文标题`。中文描述写在正文中，与首行之间空一行。
  - 按变更内容选择小写英文 `type`，例如新功能用 `feat`、缺陷修复用 `fix`、文档修改用 `docs`、重构用 `refactor`、测试用 `test`。
  - 无范围标题示例为 `docs: 更新开发说明`。
  - 带范围的完整示例

    ```text
    fix(player): 修复切歌卡顿

    避免切换曲目时重复加载音频。
    ```
