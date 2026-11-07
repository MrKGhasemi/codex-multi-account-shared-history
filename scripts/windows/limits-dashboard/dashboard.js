'use strict';
const $ = id => document.getElementById(id);
const nf = new Intl.NumberFormat('fa-IR');
const clock = new Intl.DateTimeFormat('en-GB', {
  calendar:'gregory', numberingSystem:'latn', day:'2-digit', month:'short',
  year:'numeric', hour:'2-digit', minute:'2-digit', hourCycle:'h23'
});
const formatTime = timestamp => clock.format(new Date(timestamp * 1000));
function timeLabel(label, timestamp, className) {
  const line = el('small', label + ': ', className);
  const time = el('time', formatTime(timestamp));
  time.lang = 'en';
  time.dir = 'ltr';
  time.dateTime = new Date(timestamp * 1000).toISOString();
  line.append(time);
  return line;
}
const el = (tag, value, className) => {
  const node = document.createElement(tag);
  if (value != null) node.textContent = value;
  if (className) node.className = className;
  return node;
};
let last, signature, fetching = false, refreshing = false;
const seenRecoveries = new Map();
function loadPrefs() {
  try { return JSON.parse(localStorage.getItem('codex-dashboard-prefs') || '{}') || {}; }
  catch { return {}; }
}
const prefs = loadPrefs();
const aliases = prefs.aliases || {};
function savePrefs() {
  try { localStorage.setItem('codex-dashboard-prefs', JSON.stringify({
    aliases, view: $('view').value, sort: $('sort').value, filter: $('filter').value,
    hideEmail: $('hide-email').checked, alerts: $('alerts').checked
  })); } catch {}
}
function accountName(row) {
  return aliases[row.number] || 'codex' + row.number;
}
function usageState(row) {
  if (row.loginRequired) return 'login';
  return row.usageAllowed === true ? 'ready' : row.usageAllowed === false ? 'blocked' : 'unknown';
}
const usageLabels = {ready:'آمادهٔ استفاده', blocked:'فعلاً غیرقابل استفاده', login:'نیاز به ورود', unknown:'نامشخص'};
function matches(row, filter, query, hideEmail) {
  if (filter === 'credits' ? !(row.resetCredits > 0 && !row.resetCreditsStale) :
      filter !== 'all' && usageState(row) !== filter) return false;
  return ['codex' + row.number, String(row.number), nf.format(row.number), accountName(row),
    hideEmail ? '' : row.email || ''].some(value => value.toLowerCase().includes(query));
}
function checkRecoveries(rows, baseline) {
  const recovered = [];
  for (const row of rows) {
    const previous = seenRecoveries.get(row.number) || 0;
    if (!baseline && row.recoveredAt > previous && usageState(row) === 'ready') recovered.push(accountName(row));
    if (row.recoveredAt > previous) seenRecoveries.set(row.number, row.recoveredAt);
  }
  if (!$('alerts').checked || !recovered.length) return;
  const message = 'بازگشت سهمیه: ' + recovered.join('، ');
  $('recovery').textContent = message;
  $('recovery').hidden = false;
  if ('Notification' in window && Notification.permission === 'granted') {
    try { new Notification(message); } catch {}
  }
}
function duration(minutes) {
  if (minutes === 10080) return 'هفتگی';
  if (minutes >= 60 && minutes % 60 === 0) return nf.format(minutes / 60) + ' ساعته';
  return minutes ? nf.format(minutes) + ' دقیقه‌ای' : 'سهمیه';
}
function remainingTime(reset, now = Date.now()) {
  const minutes = Math.ceil((reset * 1000 - now) / 60000);
  if (minutes <= 0) return '(زمان بازنشانی رسیده)';
  const parts = [[Math.floor(minutes / 1440), 'روز'],
    [Math.floor(minutes / 60) % 24, 'ساعت'], [minutes % 60, 'دقیقه']];
  return '(' + parts.filter(([value]) => value > 0)
    .map(([value, unit]) => nf.format(value) + ' ' + unit).join(' و ') + ' دیگر)';
}
function updateResetCountdowns() {
  const now = Date.now();
  for (const node of document.querySelectorAll('[data-reset-countdown]')) {
    const label = remainingTime(Number(node.dataset.resetCountdown), now);
    if (node.textContent !== label) node.textContent = label;
  }
}
function resetOrder(row, minutes, now) {
  let nearest = Infinity;
  for (const group of row.groups || []) {
    for (const window of group.windows) {
      if (window.minutes === minutes && Number.isFinite(window.reset) && window.reset > now) {
        nearest = Math.min(nearest, window.reset);
      }
    }
  }
  return nearest;
}
function renderAccounts() {
  if (!last) return;
  const sort = $('sort').value;
  const now = Date.now() / 1000;
  const view = $('view').value;
  const hide = $('hide-email').checked;
  const query = $('search').value.trim().toLowerCase();
  const ordered = last.accounts.filter(row => matches(row, $('filter').value, query, hide)).sort((a, b) =>
    (sort === 'profile' ? 0 : resetOrder(a, Number(sort), now) - resetOrder(b, Number(sort), now))
      || a.number - b.number);
  const nextSignature = JSON.stringify([view, hide, ordered, aliases, last.busyAccounts, refreshing]);
  if (signature !== nextSignature) {
    const area = $('accounts');
    area.classList.toggle('table-wrap', view === 'table');
    area.replaceChildren(...(!ordered.length ? [el('p', 'حسابی مطابق فیلتر پیدا نشد.')] :
      view === 'table' ? [renderTable(ordered)] : ordered.map(row => render(row, signature === undefined))));
    signature = nextSignature;
  }
}
function creditText(row) {
  return Number.isInteger(row.resetCredits) && row.resetCredits >= 0 ?
    nf.format(row.resetCredits) + ' عدد' + (row.resetCreditsStale ? ' (آخرین مقدار)' : '') : 'نامشخص';
}
function accountActions(row) {
  const actions = el('div', null, 'account-actions');
  const refresh = el('button', '↻ بررسی حساب');
  refresh.type = 'button';
  refresh.disabled = refreshing || (last.busyAccounts || []).includes(row.number);
  refresh.setAttribute('aria-label', 'بررسی codex' + row.number);
  refresh.addEventListener('click', () => requestRefresh(row.number));
  const rename = el('button', 'نام مستعار');
  rename.type = 'button';
  rename.addEventListener('click', () => {
    const name = window.prompt('نام مستعار codex' + row.number + ' (خالی برای حذف)', aliases[row.number] || '');
    if (name === null) return;
    aliases[row.number] = name.trim().slice(0, 60);
    savePrefs();
    renderAccounts();
  });
  actions.append(refresh, rename);
  return actions;
}
function quotaCell(row, minutes) {
  const td = el('td');
  for (const group of row.groups || []) {
    for (const window of group.windows.filter(item => item.minutes === minutes)) {
      const line = el('div', (row.groups.length > 1 ? group.label + ': ' : '') + nf.format(window.remaining) + '٪');
      if (Number.isFinite(window.reset) && window.reset > 0) {
        const countdown = el('small', remainingTime(window.reset), 'reset-countdown');
        countdown.dataset.resetCountdown = window.reset;
        line.append(' ', countdown, timeLabel('بازنشانی', window.reset, 'reset'));
      }
      td.append(line);
    }
  }
  if (!td.hasChildNodes()) td.textContent = '—';
  return td;
}
function renderTable(rows) {
  const table = el('table', null, 'compact');
  const headings = el('tr');
  for (const label of ['حساب', 'وضعیت', '۵ ساعته', 'هفتگی', 'کوپن', 'عملیات']) {
    const th = el('th', label);
    th.scope = 'col';
    headings.append(th);
  }
  const head = el('thead');
  head.append(headings);
  const body = el('tbody');
  for (const row of rows) {
    const tr = el('tr');
    const name = el('th', accountName(row));
    name.scope = 'row';
    if (aliases[row.number]) name.append(el('small', 'codex' + row.number));
    if (!$('hide-email').checked && row.email) name.append(el('bdi', row.email));
    const status = el('td', usageLabels[usageState(row)]);
    if (row.error) status.append(el('small', row.updated ? 'دادهٔ قبلی' : 'خواندن ناموفق', 'notice'));
    const actions = el('td');
    actions.append(accountActions(row));
    tr.append(name, status, quotaCell(row, 300), quotaCell(row, 10080), el('td', creditText(row)), actions);
    body.append(tr);
  }
  table.append(head, body);
  return table;
}
function render(row, animate) {
  const card = el('article', null, 'card');
  if (animate) card.classList.add('enter');
  const top = el('div', null, 'top');
  top.append(el('h2', 'codex' + row.number),
    el('span', row.error ? (row.updated ? 'قدیمی' : 'در دسترس نیست') : row.plan || row.accountPlan || (row.updated ? 'آماده' : 'در انتظار'),
      row.error ? 'badge stale' : 'badge'));
  card.append(top);
  if (aliases[row.number]) card.append(el('div', aliases[row.number], 'alias'));
  card.append(el('div', usageLabels[usageState(row)], 'usage-state'));
  const identity = el('div', null, 'identity');
  identity.append(el('small', 'ایمیل حساب'));
  const email = el('bdi', $('hide-email').checked ? 'پنهان' : row.email || 'در دسترس نیست');
  email.dir = row.email && !$('hide-email').checked ? 'ltr' : 'rtl';
  identity.append(email);
  card.append(identity);
  const credits = el('div', null, 'reset-credits');
  credits.append(el('span', 'کوپن بازنشانی لیمیت'),
    el('strong', creditText(row), row.resetCredits > 0 ? 'credit-available' : ''));
  card.append(credits);
  if (row.error) card.append(el('p', row.error, 'notice'));
  for (const group of row.groups || []) {
    if (row.groups.length > 1) card.append(el('div', group.label, 'bucket'));
    for (const window of group.windows) {
      const label = duration(window.minutes);
      const meter = el('div', null, 'meter');
      const title = el('span', label, 'meter-title');
      if (Number.isFinite(window.reset) && window.reset > 0) {
        const countdown = el('span', remainingTime(window.reset), 'reset-countdown');
        countdown.dataset.resetCountdown = window.reset;
        title.append(' ', countdown);
      }
      meter.append(title, el('strong', nf.format(window.remaining) + '٪'));
      const bar = el('div', null, window.remaining <= 15 ? 'track low' : 'track');
      bar.setAttribute('role', 'progressbar');
      bar.setAttribute('aria-label', label + '، باقی‌مانده');
      bar.setAttribute('aria-valuenow', window.remaining);
      const fill = el('span', null, 'fill');
      fill.style.width = window.remaining + '%';
      bar.append(fill);
      card.append(meter, bar, window.reset ? timeLabel('بازنشانی', window.reset, 'reset') :
        el('small', 'زمان بازنشانی اعلام نشده', 'reset'));
    }
  }
  if (row.updated) card.append(timeLabel('آخرین خواندن موفق', row.updated, 'updated'));
  else if (!row.error) card.append(el('p', 'در حال دریافت وضعیت…'));
  card.append(accountActions(row));
  return card;
}
async function poll() {
  if (fetching) return;
  fetching = true;
  try {
    const response = await fetch('/api/limits');
    if (!response.ok) throw Error();
    const data = await response.json();
    checkRecoveries(data.accounts, !last);
    last = data;
    $('total').textContent = nf.format(last.accounts.length);
    $('ready').textContent = nf.format(last.accounts.filter(row => row.updated && !row.error).length);
    $('countdown').textContent = last.running ? 'در حال دریافت' : nf.format(Math.max(0, Math.ceil(last.next - Date.now() / 1000))) + ' ثانیه';
    $('refresh').disabled = refreshing || last.running;
    $('refresh').classList.toggle('busy', refreshing || last.running);
    $('state').dataset.phase = last.running ? 'loading' : 'ready';
    $('state').textContent = last.running ? 'در حال خواندن وضعیت حساب‌ها…' : 'مانیتور محلی فعال است.';
    renderAccounts();
  } catch {
    $('refresh').disabled = false;
    $('refresh').classList.remove('busy');
    $('state').dataset.phase = 'offline';
    $('ready').textContent = '—';
    $('countdown').textContent = '—';
    $('state').textContent = 'ارتباط قطع شده؛ مقادیر نمایش‌داده‌شده مربوط به آخرین خواندن هستند.';
  } finally {
    fetching = false;
  }
}
async function requestRefresh(number) {
  if (refreshing) return;
  refreshing = true;
  renderAccounts();
  $('refresh').disabled = true;
  $('refresh').classList.add('busy');
  try {
    const response = await fetch('/api/refresh' + (number ? '/' + number : ''),
      {method:'POST',headers:{'X-Limits-Refresh':'1'}});
    if (!response.ok) throw Error();
  } catch {
    $('state').textContent = 'درخواست به‌روزرسانی ارسال نشد.';
  } finally {
    refreshing = false;
    renderAccounts();
    await poll();
  }
}
for (const id of ['sort', 'view', 'filter']) {
  const select = $(id);
  if ([...select.options].some(option => option.value === prefs[id])) select.value = prefs[id];
  select.addEventListener('change', () => { savePrefs(); renderAccounts(); });
}
$('hide-email').checked = prefs.hideEmail === true;
$('alerts').checked = prefs.alerts === true;
$('hide-email').addEventListener('change', () => { savePrefs(); renderAccounts(); });
$('alerts').addEventListener('change', () => {
  savePrefs();
  $('recovery').hidden = true;
  if ($('alerts').checked && 'Notification' in window && Notification.permission === 'default') {
    Notification.requestPermission().catch(() => {});
  }
});
$('search').addEventListener('input', renderAccounts);
$('refresh').addEventListener('click', () => requestRefresh());
poll();
setInterval(poll, 1000);
setInterval(updateResetCountdowns, 1000);
