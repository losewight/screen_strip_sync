# Git / GitHub：禁止 Cursor agent 署名

公开仓库的提交说明与作者信息里**不得**出现 Cursor agent 身份，包括但不限于：

- `Co-authored-by: Cursor <cursoragent@cursor.com>`
- 任意含 `cursoragent` / `cursoragent@cursor.com` 的提交正文或 trailer

## 强制手段

克隆后执行一次：

```powershell
.\scripts\setup-git-hooks.ps1
```

详见 [`.githooks/README.md`](../.githooks/README.md)。

## 对 Agent / 贡献者

- 写 `git commit` 消息时**不要**追加任何 Cursor / cursoragent 的 `Co-authored-by`。
- 不要用 `git commit --no-verify` 绕过上述拦截。
- 若历史里又出现了，用 `git-filter-repo --replace-message` 清掉后再 force-push（需仓库维护者明确授权）。
