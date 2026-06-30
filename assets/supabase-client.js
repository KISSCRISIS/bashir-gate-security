/* ==========================================================================
   نظام أمن بوابة الطوارئ - مستشفى البشير
   إعداد Supabase المشترك + دوال مساعدة (النسخة المحدثة لعام 2026)
   ========================================================================== */

// ⚠️ بيانات الاتصال بـ Supabase (تأكد من الحفاظ على قيم مشروعك الفعلي)
const SUPABASE_URL = 'https://ekwxktlgrlzzzwtxhbwa.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_33hRtbFZqTLejkj1d8zGkQ_Zn-7v734';

// عميل Supabase عالمي تستخدمه كل الصفحات (sb)
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  realtime: { params: { eventsPerSecond: 10 } },
});

/* -------------------------------------------------------------------------
   تحديث دالة إرسال النتيجة لبث اسم الموظف لحظياً لشاشة الحارس
   ------------------------------------------------------------------------- */
async function pushGateResult(employeeId, actionResult, employeeName = '') {
  try {
    // استدعاء الـ RPC المحدث الذي يعالج الأعمدة الجديدة (last_scanned_employee)
    const { error } = await sb.rpc('push_gate_result', {
      p_employee_id: employeeId,
      p_result: actionResult,
      p_employee_name: employeeName
    });
    if (error) throw error;
  } catch (err) {
    console.error('فشل إرسال التحديث للسحابة:', err);
    showToast('خطأ في الاتصال بالبوابة السحابية', 'error');
  }
}

/* -------------------------------------------------------------------------
   Toast بسيط لعرض رسائل النجاح/الخطأ بتصميم متناسق مع الثيم الداكن الجديد
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
  el.style.cssText = `
    position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%);
    background: ${c.bg}; color: ${c.fg}; padding: 12px 24px; border-radius: 16px;
    font-size: 14px; font-weight: 700; z-index: 9999; box-shadow: 0 10px 30px rgba(0,0,0,0.5);
    border: 1px solid rgba(255,255,255,0.1); direction: rtl; font-family: 'Tajawal', sans-serif;
    transition: all 0.3s ease; opacity: 0;
  `;
  el.textContent = message;
  document.body.appendChild(el);
  
  // تأثير الظهور والإخفاء
  setTimeout(() => { el.style.opacity = '1'; }, 50);
  setTimeout(() => {
    el.style.opacity = '0';
    setTimeout(() => el.remove(), 300);
  }, 3500);
}

/* -------------------------------------------------------------------------
   حفظ محلي لبيانات الكادر على الجوال لتجنب إعادة إدخالها عند كل فحص
   ------------------------------------------------------------------------- */
const CREDS_KEY = 'bashir_gate_cached_creds';

function cacheCreds(employeeId, phone) {
  localStorage.setItem(CREDS_KEY, JSON.stringify({ employeeId, phone }));
}

function getCachedCreds() {
  const raw = localStorage.getItem(CREDS_KEY);
  if (!raw) return null;
  try { return JSON.parse(raw); } catch (e) { return null; }
}

/* -------------------------------------------------------------------------
   دوال مساعدة لتنسيق الوقت والتواريخ للغة العربية في السجلات واللوحات
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
   إدارة جلسة الأدمن المحلية (sessionStorage) — حماية واجهة المستخدم فقط
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
    const EIGHT_HOURS = 8 * 60 * 60 * 1000; // شيفت طبي كامل
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

function requireAdminSession() {
  const s = getAdminSession();
  if (!s) {
    window.location.replace('login.html');
    return null;
  }
  return s;
}
