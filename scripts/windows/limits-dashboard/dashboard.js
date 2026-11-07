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
function render(row, animate) {
  const card = el('article', null, 'card');
  if (animate) card.classList.add('enter');
  const top = el('div', null, 'top');
  top.append(el('h2', 'codex' + row.number),
    el('span', row.error ? (row.updated ? 'قدیمی' : 'در دسترس نیست') : row.plan || row.accountPlan || (row.updated ? 'آماده' : 'در انتظار'),
      row.error ? 'badge stale' : 'badge'));
  card.append(top);
  const identity = el('div', null, 'identity');
  identity.append(el('small', 'ایمیل حساب'));
  const email = el('bdi', row.email || 'در دسترس نیست');
  email.dir = row.email ? 'ltr' : 'rtl';
  identity.append(email);
  card.append(identity);
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
  return card;
}
async function poll() {
  if (fetching) return;
  fetching = true;
  try {
    const response = await fetch('/api/limits');
    if (!response.ok) throw Error();
    last = await response.json();
    $('total').textContent = nf.format(last.accounts.length);
    $('ready').textContent = nf.format(last.accounts.filter(row => row.updated && !row.error).length);
    $('countdown').textContent = last.running ? 'در حال دریافت' : nf.format(Math.max(0, Math.ceil(last.next - Date.now() / 1000))) + ' ثانیه';
    $('refresh').disabled = refreshing || last.running;
    $('refresh').classList.toggle('busy', refreshing || last.running);
    $('state').dataset.phase = last.running ? 'loading' : 'ready';
    $('state').textContent = last.running ? 'در حال خواندن وضعیت حساب‌ها…' : 'مانیتور محلی فعال است.';
    const nextSignature = JSON.stringify(last.accounts);
    if (signature !== nextSignature) {
      $('accounts').replaceChildren(...last.accounts.map(row => render(row, signature === undefined)));
      signature = nextSignature;
    }
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
$('refresh').addEventListener('click', async () => {
  refreshing = true;
  $('refresh').disabled = true;
  $('refresh').classList.add('busy');
  try {
    const response = await fetch('/api/refresh', {method:'POST',headers:{'X-Limits-Refresh':'1'}});
    if (!response.ok) throw Error();
  } catch {
    $('state').textContent = 'درخواست به‌روزرسانی ارسال نشد.';
  } finally {
    refreshing = false;
    await poll();
  }
});
poll();
setInterval(poll, 1000);
setInterval(updateResetCountdowns, 1000);
