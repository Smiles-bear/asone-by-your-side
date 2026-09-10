# Azruiyoi 官网

这是一个无后端、无第三方运行时依赖的静态官网。

## 本地预览

在项目根目录运行：

```powershell
python -m http.server 4173 --directory website
```

然后访问 `http://127.0.0.1:4173/`。

## 内容维护

- 首页文案和结构：`index.html`
- 视觉样式：`assets/site.css`
- 移动菜单与导航状态：`assets/site.js`
- 品牌和截图规则：`brand-spec.md`
- GPT 生成的辅助视觉：`assets/generated/`（用于情绪与关系叙事，不替代官方产品资产；安全区和使用规则见 `brand-spec.md`）
- 法律页面来源：项目根目录的 `隐私政策用户协议/`
- 重新生成法律页面：`python website/tools/generate_legal_pages.py`
- 静态结构检查：`python website/tools/check_site.py`

## 上线前必须完成

1. 从最新安装版本重新截取脱敏的对话、助手、记忆和功能页面。
2. 将功能页旧设计稿中的“蓝牙”更新为当前产品中的“我的设备”。
3. 提供正式签名 APK、下载地址、版本号、文件大小和 SHA-256。
4. 如已有备案号，在页脚加入真实备案信息；没有时保持不显示。
5. 确认正式域名后补充 canonical、站点地图和分享预览图。

## 动效原则

- 首页使用进入视口动效、低幅视差、隐私请求路径流动和轻微悬停透视。
- 不使用滚动劫持、视频背景、粒子引擎或第三方动画库。
- 所有持续动画在 `prefers-reduced-motion: reduce` 下自动关闭。
