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
