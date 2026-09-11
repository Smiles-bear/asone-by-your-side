(() => {
  const root = document.querySelector('[data-membership]');
  if (!root) return;

  const copy = {
    zh: {
      workspace: 'Azruiyoi 工作台', sideHome: '首页', sideChat: 'AI 对话', sideModels: '模型配置', sideHistory: '使用记录',
      sideMembership: '会员中心', sideSettings: '账号设置', localMode: '本地优先', eyebrow: 'MEMBERSHIP', pageTitle: '会员中心',
      pageIntro: '选择适合你的会员方案，解锁完整的 AI 朋友体验。', demoBadge: '演示环境', currentMembership: '当前会员',
      trial: '免费体验会员', active: '正式会员', expired: '会员已过期', trialBadge: '免费体验', activeBadge: '有效', expiredBadge: '已过期',
      remaining: '剩余 {value}', validUntil: '有效期至：', trialEnds: '体验截止：', lastEnds: '上次会员到期时间：',
      trialNote: '新用户可免费体验完整会员功能 3 天<br>体验结束后不会自动扣费', expiredNote: '重新开通会员即可恢复完整功能',
      openMember: '提前开通正式会员', renew: '立即续费', reopen: '重新开通', plansEyebrow: 'PLANS', plansTitle: '选择会员套餐',
      plansHint: '会员到期后不会自动扣费，可随时手动续费', loadingPlans: '正在读取套餐…', planMonth: '月卡', planQuarter: '季卡', planYear: '年卡',
      monthDesc: '适合短期使用', quarterDesc: '适合持续使用', yearDesc: '适合长期用户', days: '{value} 天', perMonth: '约 {value} / 月',
      recommended: '推荐', bestValue: '最划算', save: '相比月卡节省 {value}%', openPlan: '开通{value}', benefitFull: '完整会员功能',
      benefitAi: 'AI 功能使用', benefitBasic: '基础会员权益', benefitComplete: '完整会员权益', benefitNew: '后续新增会员能力',
      benefitsEyebrow: 'BENEFITS', benefitsTitle: '会员权益', benefit1: '完整 AI 对话功能', benefit2: '高级模型接入', benefit3: '更高的使用额度',
      benefit4: '配置数据保存', benefit5: '优先体验新功能', benefit6: '后续会员专属功能', ordersEyebrow: 'ORDERS', ordersTitle: '购买记录',
      orderNo: '订单号', orderPlan: '套餐', orderAmount: '金额', orderMethod: '支付方式', orderStatus: '支付状态', orderDate: '购买时间',
      orderCount: '{value} 条记录', emptyOrders: '还没有购买记录', paid: '支付成功', pending: '等待支付', wechat: '微信支付', alipay: '支付宝',
      paymentEyebrow: 'CHECKOUT', paymentTitle: '确认开通会员', durationLabel: '有效期：', paymentAmount: '支付金额', paymentMethod: '支付方式',
      confirmPay: '确认支付', mockDisclaimer: '当前为演示支付，不会产生真实扣款。', pendingEyebrow: 'WAITING FOR PAYMENT', pendingTitle: '等待支付',
      pendingBody: '请使用微信或支付宝扫码支付', pendingExpiry: '订单将在 15 分钟后失效', mockPaid: '模拟支付成功', successEyebrow: 'PAYMENT COMPLETE',
      successTitle: '支付成功', successOpened: '已开通', memberUntil: '会员有效期至：', done: '完成', companyName: '京山市如一软件科技有限公司',
      footerPrivacy: '隐私政策', footerTerms: '用户协议', footerMinors: '未成年人保护规则', footerContact: '联系我们',
      apiError: '套餐暂时无法读取，已展示演示方案。', mockOrder: '演示订单',
    },
    en: {
      workspace: 'Azruiyoi workspace', sideHome: 'Home', sideChat: 'AI chat', sideModels: 'Model settings', sideHistory: 'Usage',
      sideMembership: 'Membership', sideSettings: 'Account', localMode: 'Local first', eyebrow: 'MEMBERSHIP', pageTitle: 'Membership',
      pageIntro: 'Choose a plan that fits you and unlock the complete AI friend experience.', demoBadge: 'Demo mode', currentMembership: 'Current membership',
      trial: 'Free trial', active: 'Membership', expired: 'Membership expired', trialBadge: 'Free trial', activeBadge: 'Active', expiredBadge: 'Expired',
      remaining: '{value} remaining', validUntil: 'Valid until:', trialEnds: 'Trial ends:', lastEnds: 'Last membership ended:',
      trialNote: 'New users get 3 days of full membership access<br>No automatic charge after the trial', expiredNote: 'Renew to restore full access',
      openMember: 'Join now', renew: 'Renew now', reopen: 'Reopen membership', plansEyebrow: 'PLANS', plansTitle: 'Choose a plan',
      plansHint: 'No automatic renewal. Renew manually whenever you need.', loadingPlans: 'Loading plans…', planMonth: 'Monthly', planQuarter: 'Quarterly', planYear: 'Yearly',
      monthDesc: 'For short-term use', quarterDesc: 'For regular use', yearDesc: 'For long-term users', days: '{value} days', perMonth: 'About {value} / month',
      recommended: 'Recommended', bestValue: 'Best value', save: '{value}% less than monthly', openPlan: 'Choose {value}', benefitFull: 'Full membership features',
      benefitAi: 'AI features', benefitBasic: 'Core member benefits', benefitComplete: 'Complete member benefits', benefitNew: 'Future member features',
      benefitsEyebrow: 'BENEFITS', benefitsTitle: 'Member benefits', benefit1: 'Full AI conversations', benefit2: 'Advanced model access', benefit3: 'Higher usage limits',
      benefit4: 'Saved configuration data', benefit5: 'Early access to new features', benefit6: 'Future member-only features', ordersEyebrow: 'ORDERS', ordersTitle: 'Purchase history',
      orderNo: 'Order', orderPlan: 'Plan', orderAmount: 'Amount', orderMethod: 'Payment', orderStatus: 'Status', orderDate: 'Date',
      orderCount: '{value} records', emptyOrders: 'No purchase history yet', paid: 'Paid', pending: 'Pending', wechat: 'WeChat Pay', alipay: 'Alipay',
      paymentEyebrow: 'CHECKOUT', paymentTitle: 'Confirm membership', durationLabel: 'Duration:', paymentAmount: 'Amount', paymentMethod: 'Payment method',
      confirmPay: 'Confirm payment', mockDisclaimer: 'Demo payment only. No real charge will be made.', pendingEyebrow: 'WAITING FOR PAYMENT', pendingTitle: 'Waiting for payment',
      pendingBody: 'Scan with WeChat or Alipay to pay', pendingExpiry: 'This order expires in 15 minutes', mockPaid: 'Simulate successful payment', successEyebrow: 'PAYMENT COMPLETE',
      successTitle: 'Payment complete', successOpened: 'is now active', memberUntil: 'Membership valid until:', done: 'Done', companyName: 'Jingshan Ruyi Software Technology Co., Ltd.',
      footerPrivacy: 'Privacy policy', footerTerms: 'Terms of use', footerMinors: 'Minor protection rules', footerContact: 'Contact us',
      apiError: 'Plans are temporarily unavailable. Demo plans are shown instead.', mockOrder: 'Demo order',
    },
  };

  const fallbackPlans = [
    { id: 'MONTHLY', nameKey: 'planMonth', descKey: 'monthDesc', days: 30, amount: 1900, recommended: false },
    { id: 'QUARTERLY', nameKey: 'planQuarter', descKey: 'quarterDesc', days: 90, amount: 4900, recommended: true },
    { id: 'YEARLY', nameKey: 'planYear', descKey: 'yearDesc', days: 365, amount: 14900, recommended: false },
  ];
  const benefitKeys = ['benefit1', 'benefit2', 'benefit3', 'benefit4', 'benefit5', 'benefit6'];
  const state = { plans: fallbackPlans, selectedPlan: null, order: null, activeUntil: null, trialStartedAt: null, step: 'confirm' };

  const getLanguage = () => document.documentElement.lang === 'en' ? 'en' : 'zh';
  const t = (key, values = {}) => {
    let value = copy[getLanguage()][key] || copy.zh[key] || key;
    Object.entries(values).forEach(([name, replacement]) => { value = value.replace(`{${name}}`, replacement); });
    return value;
  };

  const applyStaticCopy = () => {
    document.querySelectorAll('[data-membership-i18n]').forEach((element) => {
      element.innerHTML = t(element.dataset.membershipI18n);
    });
    document.title = `${t('pageTitle')}｜Azruiyoi`;
    renderPlans();
    renderBenefits();
    renderOrders();
    renderStatus();
    if (state.selectedPlan) updatePaymentSummary(state.selectedPlan);
  };

  const formatAmount = (amount) => `¥${(Number(amount || 0) / 100).toFixed(2)}`;
  const formatDate = (value) => {
    const date = new Date(value);
    return new Intl.DateTimeFormat(getLanguage() === 'en' ? 'en-US' : 'zh-CN', { year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
  };
  const formatDateTime = (value) => {
    const date = new Date(value);
    return new Intl.DateTimeFormat(getLanguage() === 'en' ? 'en-US' : 'zh-CN', { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }).format(date);
  };

  const renderPlans = () => {
    const grid = root.querySelector('[data-pricing-grid]');
    if (!grid) return;
    grid.innerHTML = state.plans.map((plan) => {
      const name = t(plan.nameKey) || plan.name || plan.code;
      const description = t(plan.descKey) || plan.description || '';
      const perMonth = plan.days === 30 ? '' : t('perMonth', { value: formatAmount(Math.round(plan.amount / (plan.days / 30))) });
      const badge = plan.recommended ? `<span class="pricing-badge">${t('recommended')}</span>` : plan.days === 365 ? `<span class="pricing-badge">${t('bestValue')}</span>` : '';
      const saving = plan.days > 30 ? `<p class="pricing-per-month">${t('save', { value: plan.days === 90 ? '14' : '35' })}</p>` : '<p class="pricing-per-month"></p>';
      return `<article class="pricing-card${plan.recommended ? ' is-recommended' : ''}">${badge}<h3>${name}</h3><p class="pricing-card-description">${description}</p><div class="pricing-price"><strong>${formatAmount(plan.amount)}</strong><span>/ ${t('days', { value: plan.days })}</span></div><p class="pricing-per-month">${perMonth}</p>${saving}<ul class="pricing-benefits"><li>${t('benefitFull')}</li><li>${t('benefitAi')}</li><li>${plan.days > 30 ? t('benefitComplete') : t('benefitBasic')}</li>${plan.days === 365 ? `<li>${t('benefitNew')}</li>` : ''}</ul><button class="button ${plan.recommended ? 'button-primary' : 'button-secondary'}" type="button" data-plan-id="${plan.id}">${t('openPlan', { value: name })}</button></article>`;
    }).join('');
    grid.querySelectorAll('[data-plan-id]').forEach((button) => button.addEventListener('click', () => openPayment(state.plans.find((plan) => plan.id === button.dataset.planId))));
  };

  const renderBenefits = () => {
    const list = root.querySelector('[data-benefits]');
    if (list) list.innerHTML = benefitKeys.map((key) => `<li>${t(key)}</li>`).join('');
  };

  const renderOrders = () => {
    const body = root.querySelector('[data-orders]');
    const count = root.querySelector('[data-orders-count]');
    const orders = state.orders || [];
    if (count) count.textContent = t('orderCount', { value: orders.length });
    if (!body) return;
    body.innerHTML = orders.length ? orders.map((order) => `<tr><td>${order.orderNo}</td><td>${order.planName || order.plan}</td><td>${formatAmount(order.amount)}</td><td>${order.paymentMethod === 'ALIPAY' ? t('alipay') : t('wechat')}</td><td class="order-status">${order.demo ? t('mockOrder') : t('paid')}</td><td>${formatDateTime(order.createdAt)}</td></tr>`).join('') : `<tr><td class="orders-empty" colspan="6">${t('emptyOrders')}</td></tr>`;
  };

  const getTrialStart = () => {
    try {
      const saved = Number(window.localStorage.getItem('azruiyoi-trial-start'));
      if (saved) return saved;
      const now = Date.now();
      window.localStorage.setItem('azruiyoi-trial-start', String(now));
      return now;
    } catch { return Date.now(); }
  };

  const renderStatus = () => {
    const title = root.querySelector('[data-status-title]');
    const badge = root.querySelector('[data-status-badge]');
    const detail = root.querySelector('[data-status-detail]');
    const expiry = root.querySelector('[data-status-expiry]');
    const note = root.querySelector('.status-card-side p');
    const action = root.querySelector('[data-open-payment]');
    const progress = root.querySelector('[data-status-progress]');
    const now = Date.now();
    const trialEnd = state.trialStartedAt + 3 * 86400000;
    const activeEnd = state.activeUntil;
    if (activeEnd && activeEnd > now) {
      if (title) title.textContent = t('active');
      if (badge) badge.textContent = t('activeBadge');
      if (detail) detail.textContent = t('remaining', { value: `${Math.ceil((activeEnd - now) / 86400000)} ${t('days', { value: '' }).trim()}`.trim() });
      if (expiry) expiry.textContent = formatDate(activeEnd);
      if (note) note.innerHTML = t('plansHint');
      if (action) action.textContent = t('renew');
      if (progress) progress.style.width = '78%';
      return;
    }
    if (trialEnd > now) {
      const remaining = trialEnd - now;
      const hours = Math.floor(remaining / 3600000);
      const days = Math.floor(hours / 24);
      if (title) title.textContent = t('trial');
      if (badge) badge.textContent = t('trialBadge');
      if (detail) detail.textContent = t('remaining', { value: `${days} ${getLanguage() === 'en' ? 'days' : '天'} ${hours % 24} ${getLanguage() === 'en' ? 'hours' : '小时'}` });
      if (expiry) expiry.textContent = formatDate(trialEnd);
      if (note) note.innerHTML = t('trialNote');
      if (action) action.textContent = t('openMember');
      if (progress) progress.style.width = `${Math.max(5, Math.min(100, (remaining / (3 * 86400000)) * 100))}%`;
      return;
    }
    if (title) title.textContent = t('expired');
    if (badge) badge.textContent = t('expiredBadge');
    if (detail) detail.textContent = t('expiredNote');
    if (expiry) expiry.textContent = formatDate(trialEnd);
    if (note) note.innerHTML = t('expiredNote');
    if (action) action.textContent = t('reopen');
    if (progress) progress.style.width = '0%';
  };

  const updatePaymentSummary = (plan) => {
    if (!plan) return;
    const name = t(plan.nameKey) || plan.name || plan.code;
    root.querySelector('[data-payment-plan]').textContent = `${name}${getLanguage() === 'en' ? '' : '会员'}`;
    root.querySelector('[data-payment-days]').textContent = t('days', { value: plan.days });
    root.querySelector('[data-payment-amount]').textContent = formatAmount(plan.amount);
    root.querySelector('[data-payment-confirm-amount]').textContent = formatAmount(plan.amount);
  };

  const setPaymentStep = (step) => {
    state.step = step;
    root.querySelectorAll('[data-payment-step]').forEach((panel) => { panel.hidden = panel.dataset.paymentStep !== step; });
  };

  const openPayment = (plan) => {
    if (!plan) return;
    state.selectedPlan = plan;
    updatePaymentSummary(plan);
    setPaymentStep('confirm');
    const modal = root.querySelector('[data-payment-modal]');
    modal.hidden = false;
    root.querySelector('.payment-dialog')?.focus();
  };

  const closePayment = () => {
    const modal = root.querySelector('[data-payment-modal]');
    if (modal) modal.hidden = true;
    state.order = null;
    setPaymentStep('confirm');
  };

  const createOrder = async (plan, paymentMethod) => {
    if (root.dataset.apiMode !== 'live') {
      return { orderId: `demo-${Date.now()}`, orderNo: `DEMO${Date.now()}`, planId: plan.id, planName: t(plan.nameKey), amount: plan.amount, paymentMethod, paymentStatus: 'PENDING', expiresAt: new Date(Date.now() + 900000).toISOString(), demo: true };
    }
    try {
      const response = await fetch('/api/membership/orders', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ planId: plan.id, paymentMethod }) });
      if (!response.ok) throw new Error('order request failed');
      return response.json();
    } catch {
      return { orderId: `demo-${Date.now()}`, orderNo: `DEMO${Date.now()}`, planId: plan.id, planName: t(plan.nameKey), amount: plan.amount, paymentMethod, paymentStatus: 'PENDING', expiresAt: new Date(Date.now() + 900000).toISOString(), demo: true };
    }
  };

  const completeMockPayment = () => {
    const plan = state.selectedPlan;
    if (!plan) return;
    const start = Math.max(Date.now(), state.activeUntil || 0, state.trialStartedAt + 3 * 86400000);
    state.activeUntil = start + plan.days * 86400000;
    state.orders = [{ orderNo: state.order?.orderNo || `DEMO${Date.now()}`, plan: t(plan.nameKey), amount: plan.amount, paymentMethod: state.order?.paymentMethod || 'WECHAT', createdAt: new Date().toISOString(), demo: true }, ...(state.orders || [])];
    renderStatus();
    renderOrders();
    root.querySelector('[data-payment-success-plan]').textContent = `${t(plan.nameKey)}${getLanguage() === 'en' ? '' : '会员'}`;
    root.querySelector('[data-payment-success-expiry]').textContent = formatDate(state.activeUntil);
    setPaymentStep('success');
  };

  root.addEventListener('click', async (event) => {
    const close = event.target.closest('[data-close-payment]');
    if (close) { closePayment(); return; }
    if (event.target.closest('[data-open-payment]')) { openPayment(state.plans.find((plan) => plan.recommended) || state.plans[0]); return; }
    if (event.target.closest('[data-confirm-payment]')) {
      state.order = await createOrder(state.selectedPlan, root.querySelector('input[name="payment-method"]:checked')?.value || 'WECHAT');
      setPaymentStep('pending');
      return;
    }
    if (event.target.closest('[data-mock-paid]')) completeMockPayment();
  });

  document.addEventListener('keydown', (event) => { if (event.key === 'Escape' && !root.querySelector('[data-payment-modal]')?.hidden) closePayment(); });
  document.addEventListener('azruiyoi:languagechange', applyStaticCopy);

  state.trialStartedAt = getTrialStart();
  state.orders = [];
  applyStaticCopy();
  window.setInterval(renderStatus, 60000);
})();
