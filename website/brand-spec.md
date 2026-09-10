# Azruiyoi 官网品牌与素材基线

## Design Read

- Artifact：单页产品官网与配套法律文件入口。
- Audience：希望拥有一个能长期陪伴、记得彼此，同时重视本地数据控制的 Android 用户。
- Visual language：以“AI 朋友”为核心的温暖人文产品展示；共同日常使用鲜明但统一的二维角色插画，产品能力继续由真实界面承载。
- Mode：extension；保留五屏结构、导航、法律入口、真实产品截图与下载路径，在首屏增加二创 AI 朋友阵容并增强陪伴感素材。
- Visual variance：6/10。保持熟悉的导航与阅读顺序，在共同日常区加入角色群像和手机横滑叙事。
- Motion intensity：5/10。角色按 70ms 间隔依次进入，桌面指针倾斜不超过 2.5°；场景采用最高 6px 的画框内视差，按钮在悬停或键盘聚焦时仅扫光一次，收尾合照淡入。
- Information density：3/10。每屏只表达一个主要观点。
- Asset dependence：9/10。官网以官方标志和真实 App 界面为主要识别资产。
- Brand fidelity：9/10。颜色、圆角、文案语气均以现有 App 和官网实施稿为准。

## Design Decisions

- Color palette：页面背景 `#FAF8F4`；暖色表面 `#FFF1E9`；主文字 `#2B2926`；次级文字 `#706A63`；强调色 `#E86B5D`；边线 `#E9E3DB`。
- Typography：苹方、微软雅黑、Noto Sans SC 与系统无衬线字体；不加载第三方字体。
- Spacing：8px 基准，常用间距为 16 / 24 / 32 / 48 / 72 / 96。
- Radius：按钮 14px；普通表面 20px；产品截图 28px；胶囊仅用于状态标签。
- Shadow：只使用一层低透明暖灰阴影，产品截图不叠加多重发光。
- Motion：150–300ms 状态反馈、600–900ms 入场过渡，场景缩放最高 1.045；手机只保留较短距离的入场、横滑反馈，不启用指针倾斜或视差。请求光点只在可见且页面处于前台时循环；没有新增常驻装饰循环。系统动态切换 `prefers-reduced-motion` 时立即归零倾斜与视差、停止动画并显示所有内容。

## Official assets

- `assets/azruiyoi-brand/logo.svg`：App 官方矢量标志。
- `assets/azruiyoi-brand/app-icon.png`：本轮替换后的 App 官方图标（含白边版本）。
- `assets/azruiyoi-brand/app-icon-framed.svg`：本轮提供的 App 图标矢量备份，便于后续导出不同尺寸。
- `assets/azruiyoi-brand/chat.png`：对话页设计资产。
- `assets/azruiyoi-brand/assistant-list.png`：助手列表设计资产。
- `assets/azruiyoi-brand/memory.png`：助手记忆页设计资产。
- `assets/azruiyoi-brand/features.png`：功能页设计资产。

## Generated supporting assets

- `assets/generated/memory-moon-rabbit-cohesive-v8.webp`：用户与月兔 AI 朋友共同整理记忆；左侧文案区使用柔和安全渐变。
- `assets/generated/message-board-ai-friends-v11.webp`：珊瑚先生与豆包游戏家在留言板前留下空白纸条；左侧保留文案安全区。
- `assets/generated/shared-evening-ai-friends-v16.webp`：严格参考六位最新角色设定（含 Gemini 蓝紫粉橙渐变发色与豆包双丸子头、薄荷围巾）的影音游戏夜；左侧场景保留人物群像，网页右侧独立承载文案。
- `assets/generated/local-memories-ai-friends-v11.webp`：远山先生与月兔研究员在本地设备旁整理相册；右侧保留隐私文案安全区。
- `assets/generated/closing-ai-friends-cast-v16.webp`：六位 AI 朋友近距离交叠互动的群像合照，明确包含豆包双丸子头、薄荷围巾与游戏少女造型；上方为下载文案安全区，背景接近 `#FAF8F4`。
- `assets/generated/ai-friends-play-mobile-v9.webp`：历史竖版候选，首页不再引用，避免和游戏画廊重复。
- `assets/generated/ai-friends-gomoku-v11.webp`：严格参考六位新角色设定、豆包固定造型的一起下五子棋横版场景，用于手机横滑画廊。
- `assets/generated/ai-friends-pictionary-v11.webp`：严格参考六位新角色设定、豆包固定造型的一起你画我猜横版场景，用于手机横滑画廊。
- `assets/generated/ai-friends-coop-game-v11.webp`：严格参考六位新角色设定、豆包固定造型的一起联机闯关横版场景，用于手机横滑画廊。
- `assets/generated/roles/GPT.webp`：用户提供的 GPT 灵感远山先生设定图。
- `assets/generated/roles/Claude.webp`：本轮替换后的 Claude 灵感珊瑚先生设定图，源文件保留为同名 PNG。
- `assets/generated/roles/DeepSeek-clean.webp`：参考用户提供的 DeepSeek 角色设定图生成的无文字鲸鱼娘卡片图。
- `assets/generated/roles/Gemini-clean.webp`：参考用户提供的 Gemini 角色设定图生成的无文字双星少女卡片图。
- `assets/generated/roles/kimi.webp`：用户提供的 Kimi 灵感月兔研究员设定图。
- `assets/generated/roles/doubao.webp`：用户提供的豆包灵感游戏少女设定图。
- 首屏明确标注这些角色为二创概念形象，不代表相关模型官方角色或 App 预装内容；DeepSeek、Gemini 设定图以其外观为参考重新生成了无文字卡片图。
- 所有生成场景保留 PNG 原图，网页只加载压缩后的 WebP 发布版本。
- 2026-09-10：应用 `C:/Users/何俊雄/Desktop/Azruiyoi官网素材/修改替换版本/` 中的场景插画、官方界面、Claude 角色设定与品牌图标；网页继续使用同名 WebP 发布版本，避免旧缓存。
- 生成素材只能承担背景氛围和区块收尾，不替代官方 Logo、产品截图或功能图标。
- 暖白场景放入圆角叙事面板，桌面图文采用独立的 56:44 栏位，边界仅用 40px 渐变衔接，不在人物上覆盖文案或大面积白雾；959px 以下采用文案在上、场景在下的排布，保留人物焦点。
- 角色卡和游戏卡使用浅色独立标签栏，保持人物可见，不用黑色渐变遮挡插画。
- 朋友阵容在 1199px 及以下切换为横向滚动轨道，配合“左右滑动查看更多”提示与滚动吸附，避免中小屏角色被压缩或裁掉；宽屏仍完整展示六张卡片。
- 下载合照放在文案之后的正常排版中，保留全部角色头部，边缘轻微淡出；不采用超宽绝对定位或上下漂浮，避免手机端角色被裁掉。
- 旧粘土人物素材保留在仓库作为历史候选，但首页不再引用；当前首页角色卡与新场景统一采用用户最新提供的角色设定及其衍生画面。

## Generated asset prompt set

- Hero：六位单人二创角色卡，突出不同性格和统一世界观，真实产品截图继续承担功能证明。
- Closing：六位 AI 朋友组成欢迎群像，下载文案位于独立区域；Kimi 保留白发、深蓝兔耳兜帽、金色滚边与研究员挎包等原设定，不采用泛化兔子形象。
- Memory：用户与月兔研究员共同整理相册，左侧保留文案安全区。
- Shared moments：六位朋友共度影音游戏夜，网页单独承载右侧文案安全区。
- Message board：珊瑚先生和豆包游戏家把空白纸条留给彼此，左侧保留文案安全区。
- Local ownership：远山先生与月兔研究员在手机旁整理相册，右侧保留隐私事实安全区。
- Shared constraints：统一二维日系角色插画、干净线稿、柔和赛璐璐光影和轻微水彩质感；禁止粘土、三维渲染、珠子、线团、机器人、文字、Logo、霓虹和额外人物。

## Inspiration notes

- 参考 Dribbble 当前 Web Design 热门作品的产品型首屏、真实界面证明、立体焦点素材、错层展示和微交互节奏。
- 只借用构图原则，不复制具体作品，不引入暗黑霓虹、紫色渐变、玻璃卡片墙、虚构评价或合作 Logo。
- 首屏仍只有一个主要行动目标；功能与隐私区继续以当前产品事实为准。

## Release notes

- 当前图片来自仓库内的正式 UI 设计资产，可用于官网 v0 版式确认。
- 正式上线前必须从最新安装包重新截取脱敏图片，尤其应把功能页中的“蓝牙”替换为当前版本的“我的设备”。
- 不展示虚构评分、下载量、用户评价或合作方标志。
- 当前没有正式签名的公开 APK，下载区保持“准备中”状态。
