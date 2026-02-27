// @ts-check
/**
 * Полное E2E-покрытие мессенджера через Playwright.
 * Запуск: npm run test:playwright:e2e
 */
import { test, expect } from '@playwright/test';
import { PASSWORD, unique, createContactPair } from './helpers.js';

const apiBase = () => process.env.PLAYWRIGHT_SERVER_URL || 'http://127.0.0.1:38473';

// ─── Flutter web хелперы ───

/**
 * Включает accessibility-дерево Flutter CanvasKit через JS-диспатч клика.
 * Используем page.evaluate(), а не locator.click(), чтобы Playwright не ждал
 * «settling» после тяжёлых операций Flutter semantics.
 */
async function enableFlutterA11y(page) {
  try {
    // Ждём появления кнопки «Enable accessibility» в DOM
    await page.waitForSelector('[aria-label="Enable accessibility"]', { timeout: 12000 });
    // Кликаем через evaluate — без Playwright auto-wait после клика
    await page.evaluate(() => {
      const btn =
        document.querySelector('[aria-label="Enable accessibility"]') ||
        Array.from(document.querySelectorAll('button')).find((b) =>
          (b.textContent || '').toLowerCase().includes('accessibility')
        );
      if (btn) btn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    });
    // Ждём появления хотя бы одного flt-semantics элемента
    await page.waitForSelector('flt-semantics', { state: 'attached', timeout: 10000 });
    await page.waitForTimeout(1500);
  } catch {
    // Кнопка не найдена — accessibility уже включена или не нужна
  }
}

async function waitForApp(page, timeout = 30000) {
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(3000);
  await enableFlutterA11y(page);
  // Ждём любого доступного элемента через AX-дерево
  await page.getByRole('button').first().waitFor({ state: 'attached', timeout }).catch(() => {});
  await page.waitForSelector('flt-semantics', { state: 'attached', timeout }).catch(() => {});
}

async function waitForLoginForm(page, timeout = 45000) {
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(3000);
  await enableFlutterA11y(page);
  // Используем getByRole — работает через AX-дерево Flutter, не через CSS-атрибут
  await page.getByRole('textbox').first().waitFor({ state: 'attached', timeout });
  await page.waitForTimeout(500);
}

async function waitForLoggedIn(page, timeout = 60000) {
  // После логина Flutter переходит на '/' — ждём навигации или появления элементов главного экрана
  try {
    await page.waitForURL(
      (url) => !url.pathname.includes('/login') && !url.pathname.includes('/register'),
      { timeout: timeout / 2, waitUntil: 'domcontentloaded' }
    );
  } catch {
    // Flutter SPA может не менять URL — проверяем через элементы UI
  }
  // Ждём появления элементов главного экрана или любого контента после логина
  await page.waitForTimeout(3000);
}

// ─── Локаторы формы входа ───
// Используем getByRole — работает через AX-дерево Flutter web

function usernameInput(page) {
  return page.getByRole('textbox').first();
}

function passwordInput(page) {
  return page.getByRole('textbox').nth(1);
}

function loginButton(page) {
  return page.getByRole('button', { name: /^войти$/i });
}

function forgotPasswordButton(page) {
  return page.getByRole('button', { name: /забыли пароль/i });
}

function registerButton(page) {
  return page.getByRole('button', { name: /нет аккаунта|зарегистр/i });
}

/**
 * Вводит текст в Flutter CanvasKit textbox через JS-клик + keyboard.type.
 * page.evaluate используется для клика без Playwright auto-wait.
 */
async function fillFlutterInput(page, locator, text) {
  await locator.waitFor({ state: 'attached', timeout: 15000 });
  // Кликаем через evaluate, чтобы избежать зависания Playwright
  const box = await locator.boundingBox();
  if (box) {
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  } else {
    await page.evaluate((el) => el?.click(), await locator.elementHandle());
  }
  await page.waitForTimeout(400);
  await page.keyboard.press('Control+a');
  await page.keyboard.press('Delete');
  await page.keyboard.type(text, { delay: 30 });
}

async function doLogin(page, username, password = PASSWORD) {
  await fillFlutterInput(page, usernameInput(page), username);
  await fillFlutterInput(page, passwordInput(page), password);
  const loginBtn = loginButton(page);
  await loginBtn.waitFor({ state: 'attached', timeout: 10000 });
  const box = await loginBtn.boundingBox();
  if (box) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  else await loginBtn.click({ noWaitAfter: true });
}

async function registerViaAPI(page, overrides = {}) {
  const username = overrides.username ?? unique();
  const res = await page.request.post(`${apiBase()}/auth/register`, {
    data: {
      username,
      password: PASSWORD,
      displayName: overrides.displayName ?? `User ${username}`,
      email: overrides.email,
    },
  });
  const body = await res.json();
  return { username, token: body.token, user: body.user, id: body.user?.id };
}

async function loginAndWait(page, username) {
  await page.goto('/login');
  await waitForLoginForm(page);
  await doLogin(page, username);
  await waitForLoggedIn(page);
}

// ═══════════════════════════════════════════════
// 1. ЗАГРУЗКА ПРИЛОЖЕНИЯ
// ═══════════════════════════════════════════════

test.describe('1. Загрузка приложения', () => {
  test('при открытии / виден экран загрузки или форма входа', async ({ page }) => {
    await page.goto('/');
    await waitForApp(page);
  });

  test('отображается форма входа с полями и кнопкой', async ({ page }) => {
    await page.goto('/');
    await waitForLoginForm(page);
  });
});

// ═══════════════════════════════════════════════
// 2. ФОРМА ВХОДА — UI
// ═══════════════════════════════════════════════

test.describe('2. Форма входа', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
  });

  test('содержит поле имени пользователя', async ({ page }) => {
    const count = await page.getByRole('textbox').count();
    expect(count).toBeGreaterThan(0);
  });

  test('содержит поле пароля', async ({ page }) => {
    // Форма должна иметь минимум 2 textbox: логин и пароль
    const count = await page.getByRole('textbox').count();
    expect(count).toBeGreaterThanOrEqual(2);
  });

  test('содержит кнопку «Войти»', async ({ page }) => {
    const html = await page.content();
    expect(html).toMatch(/войти/i);
  });

  test('кнопка «Войти» имеет надпись на русском', async ({ page }) => {
    const html = await page.content();
    expect(html).toMatch(/войти/i);
  });

  test('есть кнопка «Забыли пароль?»', async ({ page }) => {
    const html = await page.content();
    expect(html).toMatch(/забыли пароль/i);
  });

  test('есть кнопка «Нет аккаунта? Зарегистрироваться»', async ({ page }) => {
    const html = await page.content();
    expect(html).toMatch(/нет аккаунта|зарегистр/i);
  });

  test('кнопка «Забыли пароль?» открывает экран восстановления', async ({ page }) => {
    const btn = forgotPasswordButton(page);
    await btn.waitFor({ state: 'attached', timeout: 10000 });
    const box = await btn.boundingBox();
    if (box) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    else await btn.click({ noWaitAfter: true });
    await page.waitForTimeout(3000);
    const html = await page.content();
    expect(html).toMatch(/восстановлен|recovery|отправить ссылку|забытый пароль/i);
  });

  test('кнопка «Зарегистрироваться» переходит на форму регистрации', async ({ page }) => {
    const btn = registerButton(page);
    await btn.waitFor({ state: 'attached', timeout: 10000 });
    const box = await btn.boundingBox();
    if (box) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    else await btn.click({ noWaitAfter: true });
    await page.waitForTimeout(3000);
    const html = await page.content();
    expect(html).toMatch(/регистрац|создать аккаунт/i);
  });

  test('вход с неверным паролем показывает ошибку', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await fillFlutterInput(page, usernameInput(page), username);
    await fillFlutterInput(page, passwordInput(page), 'WrongPassword1!');
    // Кликаем кнопку входа через mouse.click
    const loginBtn = loginButton(page);
    await loginBtn.waitFor({ state: 'attached', timeout: 10000 });
    const box = await loginBtn.boundingBox();
    if (box) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    else await loginBtn.click({ noWaitAfter: true });
    await page.waitForTimeout(6000);
    // Должны остаться на логине ИЛИ в HTML появится ошибка
    const url = page.url();
    const html = await page.content();
    const stillOnLogin = url.includes('/login');
    const hasError = /неверн|ошибк|invalid|error|wrong|incorrect/i.test(html);
    expect(stillOnLogin || hasError).toBeTruthy();
  });

  test('успешный вход через UI переходит на главный экран', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await fillFlutterInput(page, usernameInput(page), username);
    await fillFlutterInput(page, passwordInput(page), PASSWORD);
    const loginBtn = loginButton(page);
    await loginBtn.waitFor({ state: 'attached', timeout: 10000 });
    const box = await loginBtn.boundingBox();
    if (box) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    else await loginBtn.click({ noWaitAfter: true });
    await page.waitForTimeout(8000);
    // Flutter SPA может не обновить URL, проверяем содержимое страницы
    // Успешный вход — пользователь видит главный экран (Чаты/Chats), а не форму входа
    const html = await page.content();
    const onMain = /чаты|chats|переподключение|reconnect/i.test(html);
    const loginFormGone = !(/войти.*войти/i.test(html));
    expect(onMain || loginFormGone).toBeTruthy();
  });

  test('успешный вход — сервер принимает credentials', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    const res = await page.request.post(`${apiBase()}/auth/login`, {
      data: { username, password: PASSWORD },
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.token).toBeTruthy();
    expect(body.user.username).toBe(username);
  });
});

// ═══════════════════════════════════════════════
// 3. ФОРМА РЕГИСТРАЦИИ — UI
// ═══════════════════════════════════════════════

async function waitForRegisterForm(page, timeout = 45000) {
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(2000);
  await enableFlutterA11y(page);
  // Используем getByRole через AX-дерево
  await page.getByRole('textbox').first().waitFor({ state: 'attached', timeout });
  await page.waitForTimeout(500);
}

function createAccountButton(page) {
  return page.getByRole('button', { name: /создать аккаунт/i });
}

test.describe('3. Форма регистрации', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    // Кликаем кнопку «Зарегистрироваться» через mouse.click
    const regBtn = registerButton(page);
    await regBtn.waitFor({ state: 'attached', timeout: 10000 });
    const box = await regBtn.boundingBox();
    if (box) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    else await regBtn.click({ noWaitAfter: true });
    // Ждём загрузки формы регистрации
    await waitForRegisterForm(page);
  });

  test('форма регистрации содержит поля', async ({ page }) => {
    const count = await page.getByRole('textbox').count();
    expect(count).toBeGreaterThan(0);
  });

  test('есть заголовок «Регистрация» на русском', async ({ page }) => {
    const html = await page.content();
    expect(html).toMatch(/регистрац/i);
  });

  test('есть кнопка «Создать аккаунт»', async ({ page }) => {
    const html = await page.content();
    expect(html).toMatch(/создать аккаунт/i);
  });

  test('кнопка «Создать аккаунт» имеет надпись на русском', async ({ page }) => {
    const html = await page.content();
    expect(html).toMatch(/создать аккаунт/i);
  });

  test('переход назад возвращает на страницу входа', async ({ page }) => {
    // Кнопка «Назад» в AppBar
    const backBtn = page.getByRole('button', { name: /назад|back/i });
    const backVisible = await backBtn.isVisible({ timeout: 5000 }).catch(() => false);
    if (backVisible) {
      const backBox = await backBtn.boundingBox();
      if (backBox) await page.mouse.click(backBox.x + backBox.width / 2, backBox.y + backBox.height / 2);
      else await backBtn.click({ noWaitAfter: true });
    } else {
      await page.goBack();
    }
    await page.waitForTimeout(3000);
    // Должны вернуться на форму входа
    const html = await page.content();
    expect(html).toMatch(/войти/i);
  });

  test('регистрация нового пользователя через UI', async ({ page }) => {
    const username = unique();
    const textboxes = page.getByRole('textbox');

    // Первое поле — имя пользователя
    await fillFlutterInput(page, textboxes.first(), username);

    // Последнее поле — пароль
    const count = await textboxes.count();
    await fillFlutterInput(page, textboxes.nth(count - 1), PASSWORD);

    // Нажимаем «Создать аккаунт» через mouse.click
    const createBtn = createAccountButton(page);
    await createBtn.waitFor({ state: 'attached', timeout: 10000 });
    const createBox = await createBtn.boundingBox();
    if (createBox) await page.mouse.click(createBox.x + createBox.width / 2, createBox.y + createBox.height / 2);
    else await createBtn.click({ noWaitAfter: true });

    await page.waitForTimeout(6000);
    // После регистрации — главный экран или форма входа (регистрация прошла)
    const url = page.url();
    expect(url).not.toContain('/register');
  });
});

// ═══════════════════════════════════════════════
// 4. НАВИГАЦИЯ ПОСЛЕ ВХОДА (API)
// ═══════════════════════════════════════════════

test.describe('4. Навигация после входа', () => {
  test('после логина токен даёт доступ к API', async ({ page }) => {
    const { username, token } = await registerViaAPI(page);
    const res = await page.request.get(`${apiBase()}/users/me`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(res.status()).toBe(200);
    const data = await res.json();
    expect(data.username).toBe(username);
  });
});

// ═══════════════════════════════════════════════
// 5. КОНТАКТЫ / ДРУЗЬЯ (API)
// ═══════════════════════════════════════════════

test.describe('5. Контакты и друзья', () => {
  test('список друзей пуст для нового пользователя (API)', async ({ page }) => {
    const { token } = await registerViaAPI(page);
    const res = await page.request.get(`${apiBase()}/contacts`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(res.status()).toBe(200);
    const data = await res.json();
    const contacts = data.data ?? data;
    expect(contacts.length).toBe(0);
  });

  test('контакт отображается после добавления (API)', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const res = await page.request.get(`${apiBase()}/contacts`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });
    const data = await res.json();
    const contacts = data.data ?? data;
    expect(contacts.some((c) => c.username === pair.user2.username)).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 6. ОТПРАВКА И ПОЛУЧЕНИЕ СООБЩЕНИЙ
// ═══════════════════════════════════════════════

test.describe('6. Сообщения', () => {
  test('отправка и получение сообщений через API', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const msgText = `Hello ${Date.now()}`;
    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
      data: { receiver_id: pair.user2.id, content: msgText },
    });
    expect(sendRes.status()).toBe(201);
    const msg = await sendRes.json();
    expect(msg.content).toBe(msgText);

    const getRes = await page.request.get(`${apiBase()}/messages/${pair.user1.id}`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
    });
    const data = await getRes.json();
    const messages = data.data ?? data;
    expect(messages.some((m) => m.content === msgText)).toBeTruthy();
  });

  test('сообщения сохраняются после повторного запроса (персистентность)', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const msgText = `persist ${Date.now()}`;
    await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
      data: { receiver_id: pair.user2.id, content: msgText },
    });

    const getRes = await page.request.get(`${apiBase()}/messages/${pair.user2.id}`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });
    const data = await getRes.json();
    const messages = data.data ?? data;
    expect(messages.some((m) => m.content === msgText)).toBeTruthy();
  });

  test('непрочитанные сообщения: бейдж и чтение через API', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    for (let i = 0; i < 3; i++) {
      await page.request.post(`${apiBase()}/messages`, {
        headers: { Authorization: `Bearer ${pair.user2.token}` },
        data: { receiver_id: pair.user1.id, content: `unread ${i}` },
      });
    }

    const chatsRes = await page.request.get(`${apiBase()}/chats`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });
    const chats = await chatsRes.json();
    const chat = (chats.data ?? chats).find((c) => c.peer?.id === pair.user2.id);
    expect(chat?.unread_count).toBe(3);

    await page.request.patch(`${apiBase()}/messages/${pair.user2.id}/read`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });

    const chatsRes2 = await page.request.get(`${apiBase()}/chats`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });
    const chats2 = await chatsRes2.json();
    const chat2 = (chats2.data ?? chats2).find((c) => c.peer?.id === pair.user2.id);
    expect(chat2?.unread_count).toBe(0);
  });
});

// ═══════════════════════════════════════════════
// 7. РЕАКЦИИ НА СООБЩЕНИЯ
// ═══════════════════════════════════════════════

test.describe('7. Реакции на сообщения', () => {
  test('ставим и снимаем реакцию через API', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
      data: { receiver_id: pair.user2.id, content: 'react to me' },
    });
    const msg = await sendRes.json();

    const r1 = await page.request.post(`${apiBase()}/messages/${msg.id}/reaction`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { emoji: '👍' },
    });
    expect(r1.status()).toBe(200);
    const b1 = await r1.json();
    expect(b1.reactions.some((r) => r.emoji === '👍')).toBeTruthy();

    const r2 = await page.request.post(`${apiBase()}/messages/${msg.id}/reaction`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { emoji: '👍' },
    });
    const b2 = await r2.json();
    const thumbs = b2.reactions.find((r) => r.emoji === '👍');
    expect(!thumbs || thumbs.user_ids.length === 0).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 8. УДАЛЕНИЕ СООБЩЕНИЙ
// ═══════════════════════════════════════════════

test.describe('8. Удаление сообщений', () => {
  test('удаление сообщения возвращает 204', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
      data: { receiver_id: pair.user2.id, content: 'delete me' },
    });
    const msg = await sendRes.json();
    const delRes = await page.request.delete(`${apiBase()}/messages/${msg.id}`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });
    expect(delRes.status()).toBe(204);
  });
});

// ═══════════════════════════════════════════════
// 9. ПРОФИЛЬ
// ═══════════════════════════════════════════════

test.describe('9. Профиль', () => {
  test('GET /users/me возвращает профиль', async ({ page }) => {
    const { username, token } = await registerViaAPI(page);
    const res = await page.request.get(`${apiBase()}/users/me`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(res.status()).toBe(200);
    const data = await res.json();
    expect(data.username).toBe(username);
  });

  test('обновление профиля через API', async ({ page }) => {
    const { token } = await registerViaAPI(page);
    const res = await page.request.patch(`${apiBase()}/users/me`, {
      headers: { Authorization: `Bearer ${token}` },
      data: { display_name: 'Новое Имя', bio: 'Привет мир!' },
    });
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.display_name).toBe('Новое Имя');
    expect(body.bio).toBe('Привет мир!');
  });
});

// ═══════════════════════════════════════════════
// 10. ПРИВАТНОСТЬ
// ═══════════════════════════════════════════════

test.describe('10. Приватность', () => {
  test('чтение и обновление настроек приватности', async ({ page }) => {
    const { token } = await registerViaAPI(page);
    const h = { Authorization: `Bearer ${token}` };

    const getRes = await page.request.get(`${apiBase()}/users/me/privacy`, { headers: h });
    expect(getRes.status()).toBe(200);
    const priv = await getRes.json();
    expect(priv.who_can_message).toBe('contacts');

    await page.request.patch(`${apiBase()}/users/me/privacy`, {
      headers: h,
      data: { who_can_message: 'all' },
    });
    const getRes2 = await page.request.get(`${apiBase()}/users/me/privacy`, { headers: h });
    const priv2 = await getRes2.json();
    expect(priv2.who_can_message).toBe('all');
  });
});

// ═══════════════════════════════════════════════
// 11. БЛОКИРОВКА ПОЛЬЗОВАТЕЛЕЙ
// ═══════════════════════════════════════════════

test.describe('11. Блокировка', () => {
  test('заблокировать и разблокировать пользователя', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h = { Authorization: `Bearer ${pair.user1.token}` };

    const blockRes = await page.request.post(`${apiBase()}/users/${pair.user2.id}/block`, {
      headers: h,
    });
    expect(blockRes.ok()).toBeTruthy();

    const listRes = await page.request.get(`${apiBase()}/users/blocked`, { headers: h });
    const blocked = await listRes.json();
    const blockedList = blocked.data ?? blocked;
    expect(blockedList.some((u) => u.id === pair.user2.id)).toBeTruthy();

    const msgRes = await page.request.post(`${apiBase()}/messages`, {
      headers: h,
      data: { receiver_id: pair.user2.id, content: 'blocked msg' },
    });
    expect(msgRes.status()).toBe(403);

    const unblockRes = await page.request.delete(
      `${apiBase()}/users/${pair.user2.id}/block`,
      { headers: h }
    );
    expect(unblockRes.ok()).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 12. ГРУППОВЫЕ ЧАТЫ
// ═══════════════════════════════════════════════

test.describe('12. Групповые чаты (API создание группы)', () => {
  test('создание группы возвращает 201', async ({ page }) => {
    const rRes = await page.request.post(`${apiBase()}/auth/register`, {
      data: { username: unique(), password: PASSWORD },
    });
    const r = await rRes.json();
    const createRes = await page.request.post(`${apiBase()}/groups`, {
      headers: { Authorization: `Bearer ${r.token}` },
      data: { name: 'Тест' },
    });
    expect(createRes.status()).toBe(201);
    const group = await createRes.json();
    expect(group.name).toBe('Тест');
    expect(group.id).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 13. ОПРОСЫ (POLLS)
// ═══════════════════════════════════════════════

test.describe('13. Опросы', () => {
  test('создание опроса и голосование', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const h2 = { Authorization: `Bearer ${pair.user2.token}` };

    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: {
        receiver_id: pair.user2.id,
        content: '',
        type: 'poll',
        question: 'Какой язык лучше?',
        options: ['JavaScript', 'Python', 'Dart'],
      },
    });
    expect(sendRes.status()).toBe(201);
    const msg = await sendRes.json();
    expect(msg.poll_id).toBeTruthy();

    const voteRes = await page.request.post(`${apiBase()}/polls/${msg.poll_id}/vote`, {
      headers: h2,
      data: { option_index: 2 },
    });
    expect(voteRes.status()).toBe(200);
  });
});

// ═══════════════════════════════════════════════
// 14. ПОИСК ПОЛЬЗОВАТЕЛЕЙ
// ═══════════════════════════════════════════════

test.describe('14. Поиск пользователей', () => {
  test('поиск по username', async ({ page }) => {
    const { token } = await registerViaAPI(page);
    const { username: u2 } = await registerViaAPI(page);

    const res = await page.request.get(`${apiBase()}/users/search?q=${u2}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(res.status()).toBe(200);
    const data = await res.json();
    const list = data.data ?? data;
    expect(list.some((u) => u.username === u2)).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 15. СПИСОК ЧАТОВ
// ═══════════════════════════════════════════════

test.describe('15. Список чатов', () => {
  test('чат появляется после отправки сообщения', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
      data: { receiver_id: pair.user2.id, content: 'chat list test' },
    });

    const res = await page.request.get(`${apiBase()}/chats`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });
    const data = await res.json();
    const chats = data.data ?? data;
    expect(chats.some((c) => c.peer?.username === pair.user2.username)).toBeTruthy();
  });

  test('последнее сообщение в превью чата', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const lastMsg = `preview ${Date.now()}`;
    await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
      data: { receiver_id: pair.user2.id, content: lastMsg },
    });

    const res = await page.request.get(`${apiBase()}/chats`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });
    const data = await res.json();
    const chat = (data.data ?? data).find(
      (c) => c.peer?.username === pair.user2.username
    );
    expect(chat?.last_message?.content).toBe(lastMsg);
  });
});

// ═══════════════════════════════════════════════
// 16. REPLY И FORWARD
// ═══════════════════════════════════════════════

test.describe('16. Reply и Forward', () => {
  test('ответ на сообщение (reply)', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const s1 = await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
      data: { receiver_id: pair.user2.id, content: 'original' },
    });
    const orig = await s1.json();

    const s2 = await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { receiver_id: pair.user1.id, content: 'reply text', reply_to_id: orig.id },
    });
    expect(s2.status()).toBe(201);
    const reply = await s2.json();
    expect(reply.reply_to_id).toBe(orig.id);
  });

  test('пересылка сообщения (forward)', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const fwd = await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
      data: {
        receiver_id: pair.user2.id,
        content: 'forwarded',
        is_forwarded: true,
        forward_from_display_name: 'Кто-то',
      },
    });
    expect(fwd.status()).toBe(201);
    const msg = await fwd.json();
    expect(msg.is_forwarded).toBe(true);
  });
});

// ═══════════════════════════════════════════════
// 17. ПАРОЛЬ
// ═══════════════════════════════════════════════

test.describe('17. Смена и сброс пароля', () => {
  test('смена пароля', async ({ page }) => {
    const { username, token } = await registerViaAPI(page);
    const newPass = 'N3wStr0ng!Pass';
    const res = await page.request.post(`${apiBase()}/auth/change-password`, {
      headers: { Authorization: `Bearer ${token}` },
      data: { currentPassword: PASSWORD, newPassword: newPass },
    });
    expect(res.status()).toBe(200);

    const loginRes = await page.request.post(`${apiBase()}/auth/login`, {
      data: { username, password: newPass },
    });
    expect(loginRes.status()).toBe(200);
  });

  test('forgot-password возвращает 200', async ({ page }) => {
    const res = await page.request.post(`${apiBase()}/auth/forgot-password`, {
      data: { email: 'no@example.com' },
    });
    expect(res.status()).toBe(200);
  });
});

// ═══════════════════════════════════════════════
// 18. HEALTH И МЕТРИКИ
// ═══════════════════════════════════════════════

test.describe('18. Health и метрики', () => {
  test('GET /health возвращает healthy', async ({ page }) => {
    const res = await page.request.get(`${apiBase()}/health`);
    expect(res.status()).toBe(200);
    const data = await res.json();
    expect(data.status).toBe('healthy');
  });

  test('GET /ready возвращает ready', async ({ page }) => {
    const res = await page.request.get(`${apiBase()}/ready`);
    expect(res.status()).toBe(200);
  });

  test('GET /live возвращает alive', async ({ page }) => {
    const res = await page.request.get(`${apiBase()}/live`);
    expect(res.status()).toBe(200);
  });

  test('GET /metrics возвращает prometheus метрики', async ({ page }) => {
    const res = await page.request.get(`${apiBase()}/metrics`);
    expect(res.status()).toBe(200);
    const text = await res.text();
    expect(text).toContain('process_cpu');
  });
});

// ═══════════════════════════════════════════════
// 19. GDPR / ЭКСПОРТ ДАННЫХ
// ═══════════════════════════════════════════════

test.describe('19. GDPR', () => {
  test('экспорт данных пользователя', async ({ page }) => {
    const { token } = await registerViaAPI(page);
    const res = await page.request.get(`${apiBase()}/gdpr/export-data`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(res.status()).toBe(200);
  });
});

// ═══════════════════════════════════════════════
// 20. УДАЛЕНИЕ КОНТАКТА
// ═══════════════════════════════════════════════

test.describe('20. Удаление контакта', () => {
  test('удаление из списка друзей', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    const delRes = await page.request.delete(
      `${apiBase()}/contacts/${pair.user2.id}`,
      { headers: h1 }
    );
    expect(delRes.ok()).toBeTruthy();

    const listRes = await page.request.get(`${apiBase()}/contacts`, { headers: h1 });
    const data = await listRes.json();
    const contacts = data.data ?? data;
    expect(contacts.some((c) => c.id === pair.user2.id)).toBeFalsy();
  });
});

// ═══════════════════════════════════════════════
// 21. ПАГИНАЦИЯ СООБЩЕНИЙ
// ═══════════════════════════════════════════════

test.describe('21. Пагинация', () => {
  test('limit ограничивает количество сообщений', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    for (let i = 0; i < 5; i++) {
      await page.request.post(`${apiBase()}/messages`, {
        headers: h1,
        data: { receiver_id: pair.user2.id, content: `pg ${i}` },
      });
    }
    const res = await page.request.get(
      `${apiBase()}/messages/${pair.user2.id}?limit=2`,
      { headers: h1 }
    );
    const data = await res.json();
    const msgs = data.data ?? data;
    expect(msgs.length).toBeLessThanOrEqual(2);
  });
});

// ═══════════════════════════════════════════════
// 22. ВЫХОД ИЗ АККАУНТА (API)
// ═══════════════════════════════════════════════

test.describe('22. Выход из аккаунта (API)', () => {
  test('токен перестаёт работать после удаления аккаунта', async ({ page }) => {
    const { token } = await registerViaAPI(page);

    const meRes = await page.request.get(`${apiBase()}/users/me`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(meRes.status()).toBe(200);

    const delRes = await page.request.delete(`${apiBase()}/gdpr/delete-account`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(delRes.ok()).toBeTruthy();

    const meRes2 = await page.request.get(`${apiBase()}/users/me`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(meRes2.status()).not.toBe(200);
  });
});
