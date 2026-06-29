/* ==========================================================================
   نظام أمن بوابة الطوارئ - مستشفى البشير
   إعداد Supabase المشترك + دوال مساعدة
   Dev: Dr. Alaa Aqrabawi
   ========================================================================== */

// ⚠️ بيانات الاتصال بـ Supabase (Project URL + Anon/Publishable Key)
const SUPABASE_URL = 'https://ekwxktlgrlzzzwtxhbwa.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_33hRtbFZqTLejkj1d8zGkQ_Zn-7v734';

// عميل Supabase عالمي تستخدمه كل الصفحات (sb)
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  realtime: { params: { eventsPerSecond: 10 } },
});

/* -------------------------------------------------------------------------
   Toast بسيط لعرض رسائل النجاح/الخطأ بدون مكتبات خارجية
   ------------------------------------------------------------------------- */
function showToast(message, type = 'info') {
  const colors = {
    success: { bg: '#0a7a52', fg: '#eafff6' },
    error: { bg: '#8a0d22', fg: '#ffeef0' },
    info: { bg: '#1f2b45', fg: '#eef2f8' },
    warning: { bg: '#a3590a', fg: '#fff5e8' },
  };
  const c = colors[type] || colors.info;
  const el = document.createElement('div');
  el.className = 'toast';
  el.style.background = c.bg;
  el.style.color = c.fg;
  el.style.border = '1px solid rgba(255,255,255,0.12)';
  el.textContent = message;
  document.body.appendChild(el);
  setTimeout(() => {
    el.style.transition = 'opacity .35s ease, transform .35s ease';
    el.style.opacity = '0';
    el.style.transform = 'translateY(10px)';
    setTimeout(() => el.remove(), 380);
  }, 3200);
}

/* -------------------------------------------------------------------------
   تحويل وقت ISO إلى صيغة عربية مقروءة
   ------------------------------------------------------------------------- */
function formatArabicTime(isoString) {
  try {
    const d = new Date(isoString);
    return d.toLocaleString('ar-JO', {
      hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit',
    });
  } catch (e) {
    return isoString;
  }
}

/* -------------------------------------------------------------------------
   إدارة جلسة الأدمن المحلية (sessionStorage) — حماية واجهة فقط
   ملاحظة أمنية: هذا تحقق على مستوى الواجهة وليس بديلاً عن RLS الحقيقي.
   ------------------------------------------------------------------------- */
const ADMIN_SESSION_KEY = 'bashir_gate_admin_session';

function saveAdminSession(adminData) {
  const payload = { ...adminData, loginAt: Date.now() };
  sessionStorage.setItem(ADMIN_SESSION_KEY, JSON.stringify(payload));
}

function getAdminSession() {
  const raw = sessionStorage.getItem(ADMIN_SESSION_KEY);
  if (!raw) return null;
  try {
    const data = JSON.parse(raw);
    // انتهاء الجلسة بعد 8 ساعات (وردية كاملة) كحد أقصى
    const EIGHT_HOURS = 8 * 60 * 60 * 1000;
    if (Date.now() - data.loginAt > EIGHT_HOURS) {
      sessionStorage.removeItem(ADMIN_SESSION_KEY);
      return null;
    }
    return data;
  } catch (e) {
    return null;
  }
}

function clearAdminSession() {
  sessionStorage.removeItem(ADMIN_SESSION_KEY);
}

/* يستخدم في أعلى admin_dashboard.html لحماية الوصول */
function requireAdminSession() {
  const session = getAdminSession();
  if (!session) {
    window.location.replace('login.html');
  }
  return session;
}
