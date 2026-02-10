import nodemailer from 'nodemailer';

const SMTP_HOST = process.env.SMTP_HOST;
const SMTP_PORT = parseInt(process.env.SMTP_PORT || '587', 10);
const SMTP_USER = process.env.SMTP_USER;
const SMTP_PASS = process.env.SMTP_PASS;
const MAIL_FROM = process.env.MAIL_FROM || SMTP_USER || 'noreply@messenger.local';
const APP_BASE_URL = process.env.APP_BASE_URL || 'http://localhost:3000';

let transporter = null;
if (SMTP_HOST && SMTP_USER && SMTP_PASS) {
  transporter = nodemailer.createTransport({
    host: SMTP_HOST,
    port: SMTP_PORT,
    secure: SMTP_PORT === 465,
    auth: { user: SMTP_USER, pass: SMTP_PASS },
  });
}

/**
 * Отправить письмо со ссылкой для сброса пароля.
 * Если SMTP не настроен — выводит ссылку в консоль (для разработки).
 */
export async function sendPasswordResetEmail(email, resetToken) {
  const resetUrl = `${APP_BASE_URL.replace(/\/$/, '')}/reset-password?token=${encodeURIComponent(resetToken)}`;
  const text = `Здравствуйте.\n\nВы запросили сброс пароля. Перейдите по ссылке, чтобы задать новый пароль:\n\n${resetUrl}\n\nСсылка действительна 1 час.\n\nЕсли вы не запрашивали сброс, проигнорируйте это письмо.`;
  const html = `
    <p>Здравствуйте.</p>
    <p>Вы запросили сброс пароля. Нажмите ссылку ниже, чтобы задать новый пароль:</p>
    <p><a href="${resetUrl}">Сбросить пароль</a></p>
    <p>Ссылка действительна 1 час.</p>
    <p>Если вы не запрашивали сброс, проигнорируйте это письмо.</p>
  `;

  if (transporter) {
    await transporter.sendMail({
      from: MAIL_FROM,
      to: email,
      subject: 'Сброс пароля — Мессенджер',
      text,
      html,
    });
  } else {
    console.log('[Mail] SMTP not configured. Password reset link:', resetUrl);
  }
}
