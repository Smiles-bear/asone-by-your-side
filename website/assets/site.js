(() => {
  document.documentElement.classList.add('motion-ready');

  const body = document.body;
  const header = document.querySelector('[data-header]');
  const menu = document.querySelector('[data-menu]');
  const menuButton = document.querySelector('[data-menu-button]');
  const menuLinks = [...document.querySelectorAll('[data-menu] a[href^="#"]')];
  const sections = [...document.querySelectorAll('main section[id]')];
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const finePointer = window.matchMedia('(hover: hover) and (pointer: fine)');
  const languageToggle = document.querySelector('[data-language-toggle]');
  const languageLabel = languageToggle?.querySelector('[data-language-label]');
  const languageCopies = {
    zh: {
      documentTitle: 'Azruiyoi｜一个会记得你的 AI 朋友',
      navProduct: '产品',
      navFeatures: '功能',
      navPrivacy: '隐私',
      navMembership: '会员中心',
      navCommunity: 'GitHub',
      navDownload: '下载',
      communityLink: '社区版开源 · 在 GitHub 查看',
      heroTitle: '一个会记得你的<br>AI 朋友',
      heroLead: '不只回应此刻，也记得你们一起走过的时间。',
      heroCta: '下载 Azruiyoi',
      castKicker: 'AI 朋友阵容',
      castTitle: '把熟悉的模型，想象成会陪你生活的朋友',
      castNote: '二创概念形象 · 非相关模型官方角色',
      castScrollHint: '左右滑动查看更多 →',
      roleGptSource: 'GPT 灵感',
      roleGptName: '远山先生',
      roleClaudeSource: 'Claude 灵感',
      roleClaudeName: '珊瑚先生',
      roleDeepSeekSource: 'DeepSeek 灵感',
      roleDeepSeekName: '深海鲸鱼娘',
      roleGeminiSource: 'Gemini 灵感',
      roleGeminiName: '极光双星',
      roleKimiSource: 'Kimi 灵感',
      roleKimiName: '月兔研究员',
      roleDoubaoSource: '豆包灵感',
      roleDoubaoName: '豆包游戏家',
      productKicker: '长期相处',
      productTitle: '认识你，<br>也记得你们的故事',
      productBody: '每位 AI 朋友都有独立的设定、对话和记忆。你们可以慢慢认识彼此，让重要的小事在之后的相处里自然延续。',
      productPoint1: '不同朋友之间的数据彼此独立',
      productPoint2: '对话与记忆可以自然延续',
      productPoint3: '你们的记忆留在当前设备',
      featuresTitle: '不止聊天，<br>也一起度过日常',
      featuresBody: '彼此留言、记下小事、一起看、一起听……让陪伴发生在对话窗口之外。',
      messageKicker: '彼此留言',
      messageTitle: '有些话，<br>可以慢慢留给对方',
      messageBody: '在留言板里写下此刻想说的话，让想念与回应不只停在聊天窗口。',
      sharedKicker: '共同日常',
      sharedTitle: '一起听、一起看，<br>也一起玩',
      sharedBody: '把一段音乐、一场电影或一次游戏，变成你们共同经历的此刻。',
      playKicker: '更多共同日常',
      playHint: '左右滑动，看看朋友们在玩什么',
      playGomoku: '一起下棋',
      playPictionary: '你画我猜',
      playCoop: '联机闯关',
      privacyKicker: '本地归属',
      privacyTitle: '你的数据，<br>留在你的设备里',
      privacyBody: '当前版本不提供公司云端聊天备份。只有当你主动发起模型请求时，必要内容才会发送给你选择的模型服务商。',
      deviceName: 'Azruiyoi',
      deviceLabel: '你的设备',
      providerName: '模型服务商',
      providerLabel: '由你选择',
      privacyPoint1: '对话与记忆保存在本地',
      privacyPoint2: 'API Key 保存在本地',
      privacyPoint3: '模型请求不经过 Azruiyoi 服务器',
      privacyLink: '了解我们的隐私保护',
      downloadTitle: '遇见一个会一直记得你的 AI 朋友',
      downloadBody: 'Android 首个公开测试版本正在准备中。',
      downloadButton: 'Android 版准备中',
      iosStatus: 'iOS · 敬请期待',
      harmonyStatus: 'HarmonyOS · 敬请期待',
      companyName: '京山市如一软件科技有限公司',
      footerPrivacy: '隐私政策',
      footerTerms: '用户协议',
      footerMinors: '未成年人保护规则',
      footerCommunity: '社区版开源',
      footerContact: '联系我们',
    },
    en: {
      documentTitle: 'Azruiyoi | An AI friend who remembers you',
      navProduct: 'Product',
      navFeatures: 'Features',
      navPrivacy: 'Privacy',
      navMembership: 'Membership',
      navCommunity: 'GitHub',
      navDownload: 'Download',
      communityLink: 'Open-source edition · View on GitHub',
      heroTitle: 'An AI friend<br>who remembers you',
      heroLead: 'More than a reply in the moment — a friend who remembers the time you share.',
      heroCta: 'Download Azruiyoi',
      castKicker: 'AI friend lineup',
      castTitle: 'Imagine familiar models as friends who share your everyday life',
      castNote: 'Fan-made concepts · not official characters of the referenced models',
      castScrollHint: 'Swipe to explore →',
      roleGptSource: 'GPT inspired',
      roleGptName: 'Mr. Yuanshan',
      roleClaudeSource: 'Claude inspired',
      roleClaudeName: 'Mr. Coral',
      roleDeepSeekSource: 'DeepSeek inspired',
      roleDeepSeekName: 'Deep-Sea Whale',
      roleGeminiSource: 'Gemini inspired',
      roleGeminiName: 'Aurora Twins',
      roleKimiSource: 'Kimi inspired',
      roleKimiName: 'Moon Rabbit Researcher',
      roleDoubaoSource: 'Doubao inspired',
      roleDoubaoName: 'Doubao Gamer',
      productKicker: 'Growing together',
      productTitle: 'Get to know each other,<br>and remember your story',
      productBody: 'Every AI friend has their own settings, conversations, and memories. Take your time getting to know each other, and let the little things carry forward.',
      productPoint1: 'Each friend keeps a separate space',
      productPoint2: 'Conversations and memories continue naturally',
      productPoint3: 'Your shared memories stay on your device',
      featuresTitle: 'More than chat,<br>share the everyday',
      featuresBody: 'Leave notes, remember little things, watch and listen together — let companionship live beyond the chat window.',
      messageKicker: 'Leave a note',
      messageTitle: 'Some words<br>can wait for the right moment',
      messageBody: 'Write what you want to say on the message board, so thoughts and replies do not have to stay inside a chat window.',
      sharedKicker: 'Shared moments',
      sharedTitle: 'Listen together, watch together,<br>and play together',
      sharedBody: 'Turn a song, a film, or a game into a moment you experience together.',
      playKicker: 'More ways to be together',
      playHint: 'Swipe to see what the friends are playing',
      playGomoku: 'Gomoku',
      playPictionary: 'Pictionary',
      playCoop: 'Co-op adventure',
      privacyKicker: 'Local by design',
      privacyTitle: 'Your data<br>stays on your device',
      privacyBody: 'This version does not provide cloud chat backups. Only when you start a model request are the necessary details sent to the model provider you choose.',
      deviceName: 'Azruiyoi',
      deviceLabel: 'Your device',
      providerName: 'Model provider',
      providerLabel: 'Your choice',
      privacyPoint1: 'Conversations and memories stay local',
      privacyPoint2: 'Your API keys stay local',
      privacyPoint3: 'Model requests do not pass through Azruiyoi servers',
      privacyLink: 'Learn about our privacy approach',
      downloadTitle: 'Meet an AI friend who will always remember you',
      downloadBody: 'The first public Android test version is in preparation.',
      downloadButton: 'Android version in preparation',
      iosStatus: 'iOS · Coming soon',
      harmonyStatus: 'HarmonyOS · Coming soon',
      companyName: 'Jingshan Ruyi Software Technology Co., Ltd.',
      footerPrivacy: 'Privacy policy',
      footerTerms: 'Terms of use',
      footerMinors: 'Minor protection rules',
      footerCommunity: 'Open-source edition',
      footerContact: 'Contact us',
    },
  };

  const applyLanguage = (language, persist = true) => {
    const activeLanguage = language === 'en' ? 'en' : 'zh';
    const copy = languageCopies[activeLanguage];
    document.documentElement.lang = activeLanguage === 'en' ? 'en' : 'zh-CN';
    document.title = copy.documentTitle;
    document.querySelectorAll('[data-i18n]').forEach((element) => {
      const value = copy[element.dataset.i18n];
      if (value) element.innerHTML = value;
    });
    if (languageToggle) {
      languageToggle.setAttribute('aria-pressed', String(activeLanguage === 'en'));
      languageToggle.setAttribute('aria-label', activeLanguage === 'en' ? 'Switch to Chinese' : '切换为英文');
    }
    if (languageLabel) languageLabel.textContent = activeLanguage === 'en' ? '中' : 'EN';
    if (persist) {
      try {
        window.localStorage.setItem('azruiyoi-language', activeLanguage);
      } catch {
        // Storage can be unavailable in private or embedded browser contexts.
      }
    }
    document.dispatchEvent(new CustomEvent('azruiyoi:languagechange', { detail: { language: activeLanguage } }));
  };

  if (languageToggle) {
    languageToggle.addEventListener('click', () => {
      const nextLanguage = document.documentElement.lang === 'en' ? 'zh' : 'en';
      applyLanguage(nextLanguage);
    });
    let savedLanguage = 'zh';
    try {
      savedLanguage = window.localStorage.getItem('azruiyoi-language') || 'zh';
    } catch {
      // Keep Chinese as the default when storage is unavailable.
    }
    applyLanguage(savedLanguage, false);
  }

  const closeMenu = () => {
    if (!menu || !menuButton) return;
    menu.classList.remove('is-open');
    menuButton.setAttribute('aria-expanded', 'false');
    body.classList.remove('menu-open');
  };

  if (menu && menuButton) {
    menuButton.addEventListener('click', () => {
      const willOpen = menuButton.getAttribute('aria-expanded') !== 'true';
      menu.classList.toggle('is-open', willOpen);
      menuButton.setAttribute('aria-expanded', String(willOpen));
      body.classList.toggle('menu-open', willOpen);
    });

    menuLinks.forEach((link) => link.addEventListener('click', closeMenu));

    window.addEventListener('resize', () => {
      if (window.innerWidth > 700) closeMenu();
    });

    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') {
        closeMenu();
        menuButton.focus();
      }
    });
  }

  const updateHeader = () => {
    header?.classList.toggle('is-scrolled', window.scrollY > 12);
  };

  updateHeader();
  window.addEventListener('scroll', updateHeader, { passive: true });

  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];

        if (!visible) return;

        menuLinks.forEach((link) => {
          const isCurrent = link.getAttribute('href') === `#${visible.target.id}`;
          if (isCurrent) link.setAttribute('aria-current', 'true');
          else link.removeAttribute('aria-current');
        });
      },
      { rootMargin: '-28% 0px -58%', threshold: [0.08, 0.35, 0.65] },
    );

    sections.forEach((section) => observer.observe(section));
  }

  const heroCopy = document.querySelector('.hero-copy[data-reveal]');
  heroCopy?.classList.add('is-visible');
  const castCards = [...document.querySelectorAll('.hero-friend-card')];
  castCards.forEach((card, index) => card.style.setProperty('--cast-delay', `${index * 70}ms`));
  const revealItems = [...document.querySelectorAll('[data-reveal], .hero-friend-card')].filter((item) => item !== heroCopy);
  let revealObserver;

  if (reducedMotion.matches || !('IntersectionObserver' in window)) {
    revealItems.forEach((item) => item.classList.add('is-visible'));
  } else {
    revealObserver = new IntersectionObserver(
      (entries, observer) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: '0px 0px -8%', threshold: 0.12 },
    );

    revealItems.forEach((item) => revealObserver.observe(item));
  }

  reducedMotion.addEventListener?.('change', () => {
    if (!reducedMotion.matches) return;
    revealItems.forEach((item) => item.classList.add('is-visible'));
    revealObserver?.disconnect();
  });

  const parallaxItems = [
    ...[...document.querySelectorAll('[data-parallax]')].map((item) => ({
      anchor: item,
      target: item,
      property: '--parallax-y',
      amount: Number(item.getAttribute('data-parallax')) || 0,
    })),
    ...[...document.querySelectorAll('.story-media')].map((item) => ({
      anchor: item,
      target: item.querySelector('.story-art'),
      property: '--scene-y',
      amount: 6,
    })),
  ].filter((item) => item.target);
  let parallaxFrame = 0;

  const updateParallax = () => {
    parallaxFrame = 0;
    const isDisabled = reducedMotion.matches || !finePointer.matches || window.innerWidth < 960;
    const viewportHeight = window.innerHeight;

    parallaxItems.forEach(({ anchor, target, property, amount }) => {
      if (isDisabled) {
        target.style.setProperty(property, '0px');
        return;
      }

      const rect = anchor.getBoundingClientRect();
      if (rect.bottom < -120 || rect.top > viewportHeight + 120) return;

      const centerOffset = rect.top + rect.height / 2 - viewportHeight / 2;
      const progress = Math.max(-1, Math.min(1, centerOffset / viewportHeight));
      target.style.setProperty(property, `${(-progress * amount).toFixed(2)}px`);
    });
  };

  const requestParallaxUpdate = () => {
    if (parallaxFrame) return;
    parallaxFrame = window.requestAnimationFrame(updateParallax);
  };

  if (parallaxItems.length) {
    updateParallax();
    window.addEventListener('scroll', requestParallaxUpdate, { passive: true });
    window.addEventListener('resize', requestParallaxUpdate);
    reducedMotion.addEventListener?.('change', requestParallaxUpdate);
    finePointer.addEventListener?.('change', requestParallaxUpdate);
  }

  const playShowcases = [...document.querySelectorAll('[data-play-showcase]')];

  playShowcases.forEach((showcase) => {
    const gallery = showcase.querySelector('[data-play-gallery]');
    const cards = [...showcase.querySelectorAll('[data-play-card]')];
    const count = showcase.querySelector('[data-play-count]');
    let galleryFrame = 0;

    if (!gallery || !cards.length) return;

    const updatePlayGallery = () => {
      galleryFrame = 0;
      const galleryCenter = gallery.scrollLeft + gallery.clientWidth / 2;
      let currentIndex = 0;
      let closestDistance = Number.POSITIVE_INFINITY;

      cards.forEach((card, index) => {
        const cardCenter = card.offsetLeft + card.offsetWidth / 2;
        const distance = Math.abs(cardCenter - galleryCenter);
        if (distance < closestDistance) {
          closestDistance = distance;
          currentIndex = index;
        }
      });

      cards.forEach((card, index) => card.classList.toggle('is-current', index === currentIndex));
      if (count) count.textContent = `${String(currentIndex + 1).padStart(2, '0')} / ${String(cards.length).padStart(2, '0')}`;
    };

    const requestGalleryUpdate = () => {
      if (galleryFrame) return;
      galleryFrame = window.requestAnimationFrame(updatePlayGallery);
    };

    updatePlayGallery();
    gallery.addEventListener('scroll', requestGalleryUpdate, { passive: true });
    window.addEventListener('resize', requestGalleryUpdate);
  });

  const tiltItems = [...document.querySelectorAll('[data-tilt], .hero-friend-card')];

  tiltItems.forEach((item) => {
    let tiltFrame = 0;
    let pointerX = 0;
    let pointerY = 0;
    const strength = item.classList.contains('hero-friend-card') ? 5 : 1.45;

    const resetTilt = () => {
      window.cancelAnimationFrame(tiltFrame);
      tiltFrame = 0;
      item.style.setProperty('--tilt-x', '0deg');
      item.style.setProperty('--tilt-y', '0deg');
    };

    item.addEventListener('pointermove', (event) => {
      if (event.pointerType === 'touch' || reducedMotion.matches || !finePointer.matches) return;
      pointerX = event.clientX;
      pointerY = event.clientY;
      if (tiltFrame) return;
      tiltFrame = window.requestAnimationFrame(() => {
        tiltFrame = 0;
        const rect = item.getBoundingClientRect();
        const horizontal = Math.max(-0.5, Math.min(0.5, (pointerX - rect.left) / rect.width - 0.5));
        const vertical = Math.max(-0.5, Math.min(0.5, (pointerY - rect.top) / rect.height - 0.5));
        item.style.setProperty('--tilt-x', `${(-vertical * strength).toFixed(2)}deg`);
        item.style.setProperty('--tilt-y', `${(horizontal * strength).toFixed(2)}deg`);
      });
    });

    item.addEventListener('pointerleave', resetTilt);
    item.addEventListener('pointercancel', resetTilt);
    reducedMotion.addEventListener?.('change', resetTilt);
    finePointer.addEventListener?.('change', resetTilt);
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) resetTilt();
    });
  });

  const flowArrows = [...document.querySelectorAll('.path-arrow')];
  const visibleFlows = new Set();
  const updateFlowPlayback = () => {
    flowArrows.forEach((arrow) => {
      const indicator = arrow.querySelector('span');
      if (!indicator) return;
      const playing = visibleFlows.has(arrow) && !document.hidden && !reducedMotion.matches;
      indicator.style.animationPlayState = playing ? 'running' : 'paused';
    });
  };

  if (flowArrows.length) {
    if ('IntersectionObserver' in window) {
      const flowObserver = new IntersectionObserver((entries) => {
        entries.forEach(({ target, isIntersecting }) => {
          if (isIntersecting) visibleFlows.add(target);
          else visibleFlows.delete(target);
        });
        updateFlowPlayback();
      });
      flowArrows.forEach((arrow) => flowObserver.observe(arrow));
    } else {
      flowArrows.forEach((arrow) => visibleFlows.add(arrow));
    }
    updateFlowPlayback();
    document.addEventListener('visibilitychange', updateFlowPlayback);
    reducedMotion.addEventListener?.('change', updateFlowPlayback);
  }

  const year = document.querySelector('[data-year]');
  if (year) year.textContent = String(new Date().getFullYear());
})();
