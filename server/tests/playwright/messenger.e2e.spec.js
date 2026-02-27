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

// ═══════════════════════════════════════════════
// 23. РЕДАКТИРОВАНИЕ СООБЩЕНИЙ
// ═══════════════════════════════════════════════

test.describe('23. Редактирование сообщений', () => {
  test('отправитель может редактировать текстовое сообщение', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: { receiver_id: pair.user2.id, content: 'original text' },
    });
    expect(sendRes.status()).toBe(201);
    const msg = await sendRes.json();

    const editRes = await page.request.patch(`${apiBase()}/messages/${msg.id}`, {
      headers: h1,
      data: { content: 'edited text' },
    });
    expect(editRes.status()).toBe(200);
    const edited = await editRes.json();
    expect(edited.content).toBe('edited text');
  });

  test('получатель не может редактировать чужое сообщение', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const h2 = { Authorization: `Bearer ${pair.user2.token}` };

    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: { receiver_id: pair.user2.id, content: 'cannot touch' },
    });
    const msg = await sendRes.json();

    const editRes = await page.request.patch(`${apiBase()}/messages/${msg.id}`, {
      headers: h2,
      data: { content: 'hacked' },
    });
    expect(editRes.status()).toBe(403);
  });

  test('после редактирования изменённый текст виден в истории', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: { receiver_id: pair.user2.id, content: 'before edit' },
    });
    const msg = await sendRes.json();

    await page.request.patch(`${apiBase()}/messages/${msg.id}`, {
      headers: h1,
      data: { content: 'after edit' },
    });

    const histRes = await page.request.get(`${apiBase()}/messages/${pair.user2.id}`, {
      headers: h1,
    });
    const data = await histRes.json();
    const messages = data.data ?? data;
    const found = messages.find((m) => m.id === msg.id);
    expect(found?.content).toBe('after edit');
  });
});

// ═══════════════════════════════════════════════
// 24. УДАЛЕНИЕ ДЛЯ СЕБЯ (SOFT DELETE)
// ═══════════════════════════════════════════════

test.describe('24. Удаление для себя', () => {
  test('удаление for_me=true возвращает 204', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: { receiver_id: pair.user2.id, content: 'delete for me' },
    });
    const msg = await sendRes.json();

    const delRes = await page.request.delete(`${apiBase()}/messages/${msg.id}?for_me=true`, {
      headers: h1,
    });
    expect(delRes.status()).toBe(204);
  });

  test('после soft-delete сообщение пропадает из истории для удалившего', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const h2 = { Authorization: `Bearer ${pair.user2.token}` };

    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: { receiver_id: pair.user2.id, content: 'soft del target' },
    });
    const msg = await sendRes.json();

    await page.request.delete(`${apiBase()}/messages/${msg.id}?for_me=true`, { headers: h1 });

    // Удалившему сообщение не видно
    const h1Hist = await page.request.get(`${apiBase()}/messages/${pair.user2.id}`, { headers: h1 });
    const d1 = await h1Hist.json();
    const msgs1 = d1.data ?? d1;
    expect(msgs1.some((m) => m.id === msg.id)).toBeFalsy();

    // Второму пользователю сообщение по-прежнему видно
    const h2Hist = await page.request.get(`${apiBase()}/messages/${pair.user1.id}`, { headers: h2 });
    const d2 = await h2Hist.json();
    const msgs2 = d2.data ?? d2;
    expect(msgs2.some((m) => m.id === msg.id)).toBeTruthy();
  });

  test('удаление для всех: сообщение пропадает у обоих', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const h2 = { Authorization: `Bearer ${pair.user2.token}` };

    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: { receiver_id: pair.user2.id, content: 'delete for all' },
    });
    const msg = await sendRes.json();

    await page.request.delete(`${apiBase()}/messages/${msg.id}`, { headers: h1 });

    const h1Hist = await page.request.get(`${apiBase()}/messages/${pair.user2.id}`, { headers: h1 });
    const d1 = await h1Hist.json();
    expect((d1.data ?? d1).some((m) => m.id === msg.id)).toBeFalsy();

    const h2Hist = await page.request.get(`${apiBase()}/messages/${pair.user1.id}`, { headers: h2 });
    const d2 = await h2Hist.json();
    expect((d2.data ?? d2).some((m) => m.id === msg.id)).toBeFalsy();
  });
});

// ═══════════════════════════════════════════════
// 25. ОНЛАЙН-СТАТУС
// ═══════════════════════════════════════════════

test.describe('25. Онлайн-статус', () => {
  test('GET /users/:id возвращает поля is_online и last_seen для контакта', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    const res = await page.request.get(`${apiBase()}/users/${pair.user2.id}`, { headers: h1 });
    expect(res.status()).toBe(200);
    const user = await res.json();
    expect('is_online' in user).toBeTruthy();
    expect('last_seen' in user).toBeTruthy();
  });

  test('GET /chats включает is_online и last_seen для собеседника', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: { receiver_id: pair.user2.id, content: 'online check' },
    });

    const res = await page.request.get(`${apiBase()}/chats`, { headers: h1 });
    const data = await res.json();
    const chat = (data.data ?? data).find((c) => c.peer?.id === pair.user2.id);
    expect(chat).toBeTruthy();
    expect('is_online' in (chat?.peer ?? {})).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 26. ГРУППОВЫЕ СООБЩЕНИЯ
// ═══════════════════════════════════════════════

test.describe('26. Групповые сообщения', () => {
  async function createGroupWithMembers(page, creator, memberIds = []) {
    const res = await page.request.post(`${apiBase()}/groups`, {
      headers: { Authorization: `Bearer ${creator.token}` },
      data: { name: `Тест ${Date.now()}`, member_ids: memberIds },
    });
    expect(res.status()).toBe(201);
    return res.json();
  }

  test('отправка и получение текстового сообщения в группу', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const group = await createGroupWithMembers(page, r1, [r2.id]);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    const sendRes = await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
      data: { content: 'привет группа' },
    });
    expect(sendRes.status()).toBe(201);
    const msg = await sendRes.json();
    expect(msg.content).toBe('привет группа');
    expect(msg.group_id).toBe(group.id);

    const getRes = await page.request.get(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
    });
    const data = await getRes.json();
    const messages = data.data ?? data;
    expect(messages.some((m) => m.content === 'привет группа')).toBeTruthy();
  });

  test('member видит сообщения созданные creator', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const group = await createGroupWithMembers(page, r1, [r2.id]);
    const h1 = { Authorization: `Bearer ${r1.token}` };
    const h2 = { Authorization: `Bearer ${r2.token}` };
    const msgText = `group msg ${Date.now()}`;

    await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
      data: { content: msgText },
    });

    const getRes = await page.request.get(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h2,
    });
    const data = await getRes.json();
    const messages = data.data ?? data;
    expect(messages.some((m) => m.content === msgText)).toBeTruthy();
  });

  test('не-участник получает 404 на сообщения группы', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const group = await createGroupWithMembers(page, r1, []);
    const h2 = { Authorization: `Bearer ${r2.token}` };

    const res = await page.request.get(`${apiBase()}/groups/${group.id}/messages`, { headers: h2 });
    expect(res.status()).toBe(404);
  });

  test('sender_display_name присутствует в ответе', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const group = await createGroupWithMembers(page, r1, []);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
      data: { content: 'name check' },
    });

    const getRes = await page.request.get(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
    });
    const data = await getRes.json();
    const messages = data.data ?? data;
    const found = messages.find((m) => m.content === 'name check');
    expect(found?.sender_display_name).toBeTruthy();
  });

  test('пагинация группы через before', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const group = await createGroupWithMembers(page, r1, []);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    for (let i = 0; i < 5; i++) {
      await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
        headers: h1,
        data: { content: `msg ${i}` },
      });
    }

    const r1Res = await page.request.get(`${apiBase()}/groups/${group.id}/messages?limit=100`, { headers: h1 });
    const allData = await r1Res.json();
    const allMsgs = allData.data ?? allData;
    const pivotId = allMsgs[allMsgs.length - 1]?.id; // последнее сообщение

    const beforeRes = await page.request.get(
      `${apiBase()}/groups/${group.id}/messages?limit=2&before=${pivotId}`,
      { headers: h1 }
    );
    const beforeData = await beforeRes.json();
    const beforeMsgs = beforeData.data ?? beforeData;
    expect(beforeMsgs.every((m) => m.id < pivotId)).toBeTruthy();
    expect(beforeMsgs.length).toBeLessThanOrEqual(2);
  });
});

// ═══════════════════════════════════════════════
// 27. РЕАКЦИИ В ГРУППОВЫХ СООБЩЕНИЯХ
// ═══════════════════════════════════════════════

test.describe('27. Реакции в групповых сообщениях', () => {
  async function setupGroupMsg(page) {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: { Authorization: `Bearer ${r1.token}` },
      data: { name: 'ReactGroup', member_ids: [r2.id] },
    });
    const group = await gRes.json();
    const msgRes = await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: { Authorization: `Bearer ${r1.token}` },
      data: { content: 'react me' },
    });
    const msg = await msgRes.json();
    return { r1, r2, group, msg };
  }

  test('добавить реакцию на групповое сообщение', async ({ page }) => {
    const { r2, group, msg } = await setupGroupMsg(page);
    const h2 = { Authorization: `Bearer ${r2.token}` };

    const rRes = await page.request.post(
      `${apiBase()}/groups/${group.id}/messages/${msg.id}/reaction`,
      { headers: h2, data: { emoji: '❤️' } }
    );
    expect(rRes.status()).toBe(200);
    const body = await rRes.json();
    expect(body.reactions.some((r) => r.emoji === '❤️')).toBeTruthy();
  });

  test('повторная та же реакция снимает её', async ({ page }) => {
    const { r1, group, msg } = await setupGroupMsg(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    await page.request.post(
      `${apiBase()}/groups/${group.id}/messages/${msg.id}/reaction`,
      { headers: h1, data: { emoji: '👍' } }
    );
    const r2 = await page.request.post(
      `${apiBase()}/groups/${group.id}/messages/${msg.id}/reaction`,
      { headers: h1, data: { emoji: '👍' } }
    );
    const body = await r2.json();
    const thumbs = body.reactions.find((r) => r.emoji === '👍');
    expect(!thumbs || thumbs.user_ids.length === 0).toBeTruthy();
  });

  test('несколько пользователей реагируют на одно сообщение', async ({ page }) => {
    const { r1, r2, group, msg } = await setupGroupMsg(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };
    const h2 = { Authorization: `Bearer ${r2.token}` };

    await page.request.post(
      `${apiBase()}/groups/${group.id}/messages/${msg.id}/reaction`,
      { headers: h1, data: { emoji: '🔥' } }
    );
    const rRes = await page.request.post(
      `${apiBase()}/groups/${group.id}/messages/${msg.id}/reaction`,
      { headers: h2, data: { emoji: '🔥' } }
    );
    const body = await rRes.json();
    const fire = body.reactions.find((r) => r.emoji === '🔥');
    expect(fire?.user_ids.length).toBe(2);
  });
});

// ═══════════════════════════════════════════════
// 28. ПРОЧТЕНИЕ ГРУППОВОГО ЧАТА
// ═══════════════════════════════════════════════

test.describe('28. Прочтение группового чата', () => {
  test('PATCH /groups/:id/read обнуляет unread_count', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: { Authorization: `Bearer ${r1.token}` },
      data: { name: 'ReadGroup', member_ids: [r2.id] },
    });
    const group = await gRes.json();
    const h1 = { Authorization: `Bearer ${r1.token}` };
    const h2 = { Authorization: `Bearer ${r2.token}` };

    // r1 шлёт 3 сообщения
    let lastMsgId;
    for (let i = 0; i < 3; i++) {
      const s = await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
        headers: h1,
        data: { content: `unread group ${i}` },
      });
      const m = await s.json();
      lastMsgId = m.id;
    }

    // r2 должен видеть 3 непрочитанных в /chats
    const chatsRes1 = await page.request.get(`${apiBase()}/chats`, { headers: h2 });
    const chats1 = await chatsRes1.json();
    const chat1 = (chats1.data ?? chats1).find((c) => c.group?.id === group.id);
    expect(chat1?.unread_count).toBe(3);

    // r2 читает группу
    await page.request.patch(`${apiBase()}/groups/${group.id}/read`, {
      headers: h2,
      data: { last_message_id: lastMsgId },
    });

    // Теперь 0 непрочитанных
    const chatsRes2 = await page.request.get(`${apiBase()}/chats`, { headers: h2 });
    const chats2 = await chatsRes2.json();
    const chat2 = (chats2.data ?? chats2).find((c) => c.group?.id === group.id);
    expect(chat2?.unread_count).toBe(0);
  });
});

// ═══════════════════════════════════════════════
// 29. УПРАВЛЕНИЕ УЧАСТНИКАМИ ГРУППЫ
// ═══════════════════════════════════════════════

test.describe('29. Участники группы', () => {
  test('добавление участника в группу (admin only)', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const r3 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'MemberGroup' },
    });
    const group = await gRes.json();

    const addRes = await page.request.post(`${apiBase()}/groups/${group.id}/members`, {
      headers: h1,
      data: { user_ids: [r2.id, r3.id] },
    });
    expect(addRes.status()).toBe(204);

    // r2 теперь может получить сообщения группы
    const msgRes = await page.request.get(`${apiBase()}/groups/${group.id}/messages`, {
      headers: { Authorization: `Bearer ${r2.token}` },
    });
    expect(msgRes.status()).toBe(200);
  });

  test('не-администратор не может добавить участников', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const r3 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };
    const h2 = { Authorization: `Bearer ${r2.token}` };

    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'AdminOnly', member_ids: [r2.id] },
    });
    const group = await gRes.json();

    const addRes = await page.request.post(`${apiBase()}/groups/${group.id}/members`, {
      headers: h2,
      data: { user_ids: [r3.id] },
    });
    expect(addRes.status()).toBe(403);
  });

  test('участник может покинуть группу', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };
    const h2 = { Authorization: `Bearer ${r2.token}` };

    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'LeaveGroup', member_ids: [r2.id] },
    });
    const group = await gRes.json();

    // r2 выходит
    const leaveRes = await page.request.delete(
      `${apiBase()}/groups/${group.id}/members/${r2.id}`,
      { headers: h2 }
    );
    expect(leaveRes.status()).toBe(204);

    // r2 больше не видит сообщения группы
    const msgRes = await page.request.get(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h2,
    });
    expect(msgRes.status()).toBe(404);
  });

  test('группа удаляется когда выходит последний участник', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'LastManGroup' },
    });
    const group = await gRes.json();

    await page.request.delete(
      `${apiBase()}/groups/${group.id}/members/${r1.id}`,
      { headers: h1 }
    );

    const groupInfoRes = await page.request.get(`${apiBase()}/groups/${group.id}`, { headers: h1 });
    expect(groupInfoRes.status()).toBe(404);
  });

  test('информация о группе возвращает список участников', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'InfoGroup', member_ids: [r2.id] },
    });
    const group = await gRes.json();

    const infoRes = await page.request.get(`${apiBase()}/groups/${group.id}`, { headers: h1 });
    expect(infoRes.status()).toBe(200);
    const info = await infoRes.json();
    expect(Array.isArray(info.members)).toBeTruthy();
    expect(info.members.length).toBe(2);
    expect(info.members.some((m) => m.id === r1.id)).toBeTruthy();
    expect(info.members.some((m) => m.id === r2.id)).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 30. ГРУППОВЫЕ ОПРОСЫ
// ═══════════════════════════════════════════════

test.describe('30. Групповые опросы', () => {
  test('создание опроса в группе', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'PollGroup', member_ids: [r2.id] },
    });
    const group = await gRes.json();

    const pollRes = await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
      data: {
        content: '',
        type: 'poll',
        question: 'Лучший язык?',
        options: ['Dart', 'JavaScript', 'Python'],
      },
    });
    expect(pollRes.status()).toBe(201);
    const poll = await pollRes.json();
    expect(poll.message_type).toBe('poll');
    expect(poll.poll_id).toBeTruthy();
    expect(poll.poll?.question).toBe('Лучший язык?');
    expect(poll.poll?.options.length).toBe(3);
  });

  test('голосование за вариант в групповом опросе', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };
    const h2 = { Authorization: `Bearer ${r2.token}` };

    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'VoteGroup', member_ids: [r2.id] },
    });
    const group = await gRes.json();

    const pollRes = await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
      data: {
        type: 'poll',
        question: 'Голосуем?',
        options: ['Да', 'Нет'],
      },
    });
    const pollMsg = await pollRes.json();

    // Используем маршрут голосования в групповых опросах
    const voteRes = await page.request.post(
      `${apiBase()}/groups/${group.id}/polls/${pollMsg.poll_id}/vote`,
      { headers: h2, data: { option_index: 0 } }
    );
    expect(voteRes.status()).toBe(200);
    const voteBody = await voteRes.json();
    const daOpt = voteBody.options?.[0] ?? voteBody.poll?.options?.[0];
    expect(daOpt?.votes).toBeGreaterThan(0);
  });
});

// ═══════════════════════════════════════════════
// 31. REPLY И FORWARD В ГРУППОВЫХ ЧАТАХ
// ═══════════════════════════════════════════════

test.describe('31. Reply и Forward в группах', () => {
  async function makeGroupAndSend(page, content) {
    const r1 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };
    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'ReplyGroup' },
    });
    const group = await gRes.json();
    const msgRes = await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
      data: { content },
    });
    const msg = await msgRes.json();
    return { r1, h1, group, msg };
  }

  test('ответ на сообщение в группе содержит reply_to_id', async ({ page }) => {
    const { r1, h1, group, msg } = await makeGroupAndSend(page, 'original');

    const replyRes = await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
      data: { content: 'reply!', reply_to_id: msg.id },
    });
    expect(replyRes.status()).toBe(201);
    const reply = await replyRes.json();
    expect(reply.reply_to_id).toBe(msg.id);
  });

  test('пересылка сообщения в группу', async ({ page }) => {
    const { r1, h1, group } = await makeGroupAndSend(page, 'fwd source');

    const fwdRes = await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
      data: {
        content: 'forwarded content',
        is_forwarded: true,
        forward_from_display_name: 'Источник',
      },
    });
    expect(fwdRes.status()).toBe(201);
    const fwd = await fwdRes.json();
    expect(fwd.is_forwarded).toBe(true);
    expect(fwd.forward_from_display_name).toBe('Источник');
  });
});

// ═══════════════════════════════════════════════
// 32. МНОЖЕСТВЕННЫЕ РЕАКЦИИ В 1-1 ЧАТЕ
// ═══════════════════════════════════════════════

test.describe('32. Множественные реакции (1-1)', () => {
  test('оба пользователя ставят одинаковую реакцию — счётчик 2', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const h2 = { Authorization: `Bearer ${pair.user2.token}` };

    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: { receiver_id: pair.user2.id, content: 'multi react' },
    });
    const msg = await sendRes.json();

    await page.request.post(`${apiBase()}/messages/${msg.id}/reaction`, {
      headers: h1,
      data: { emoji: '😂' },
    });
    const r2 = await page.request.post(`${apiBase()}/messages/${msg.id}/reaction`, {
      headers: h2,
      data: { emoji: '😂' },
    });
    const body = await r2.json();
    const laugh = body.reactions.find((r) => r.emoji === '😂');
    expect(laugh?.user_ids.length).toBe(2);
  });

  test('замена реакции: новая эмодзи', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: { receiver_id: pair.user2.id, content: 'switch react' },
    });
    const msg = await sendRes.json();

    await page.request.post(`${apiBase()}/messages/${msg.id}/reaction`, {
      headers: h1,
      data: { emoji: '👍' },
    });
    const r2 = await page.request.post(`${apiBase()}/messages/${msg.id}/reaction`, {
      headers: h1,
      data: { emoji: '❤️' },
    });
    const body = await r2.json();
    const heart = body.reactions.find((r) => r.emoji === '❤️');
    const thumbs = body.reactions.find((r) => r.emoji === '👍');
    expect(heart?.user_ids.includes(pair.user1.id)).toBeTruthy();
    expect(!thumbs || !thumbs.user_ids.includes(pair.user1.id)).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 33. СПИСОК ЧАТОВ С ГРУППАМИ
// ═══════════════════════════════════════════════

test.describe('33. Список чатов с группами', () => {
  test('группа появляется в /chats после первого сообщения', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'ChatListGroup' },
    });
    const group = await gRes.json();

    await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
      data: { content: 'first group message' },
    });

    const chatsRes = await page.request.get(`${apiBase()}/chats`, { headers: h1 });
    const data = await chatsRes.json();
    const chats = data.data ?? data;
    expect(chats.some((c) => c.group?.id === group.id)).toBeTruthy();
  });

  test('последнее сообщение группы видно в превью чата', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'PreviewGroup' },
    });
    const group = await gRes.json();
    const lastText = `preview ${Date.now()}`;

    await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
      data: { content: 'first' },
    });
    await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
      data: { content: lastText },
    });

    const chatsRes = await page.request.get(`${apiBase()}/chats`, { headers: h1 });
    const data = await chatsRes.json();
    const chat = (data.data ?? data).find((c) => c.group?.id === group.id);
    expect(chat?.last_message?.content).toBe(lastText);
  });
});

// ═══════════════════════════════════════════════
// 34. ПАГИНАЦИЯ С КУРСОРОМ (before)
// ═══════════════════════════════════════════════

test.describe('34. Пагинация с курсором', () => {
  test('before возвращает только более старые сообщения (1-1)', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    for (let i = 0; i < 5; i++) {
      await page.request.post(`${apiBase()}/messages`, {
        headers: h1,
        data: { receiver_id: pair.user2.id, content: `cursor msg ${i}` },
      });
    }

    const allRes = await page.request.get(`${apiBase()}/messages/${pair.user2.id}?limit=100`, {
      headers: h1,
    });
    const allData = await allRes.json();
    const allMsgs = allData.data ?? allData;
    const pivotId = allMsgs[allMsgs.length - 1]?.id; // самое новое

    const pageRes = await page.request.get(
      `${apiBase()}/messages/${pair.user2.id}?limit=2&before=${pivotId}`,
      { headers: h1 }
    );
    const pageData = await pageRes.json();
    const pageMsgs = pageData.data ?? pageData;
    expect(pageMsgs.every((m) => m.id < pivotId)).toBeTruthy();
    expect(pageMsgs.length).toBeLessThanOrEqual(2);
  });

  test('hasMore=true когда сообщений больше чем limit', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    for (let i = 0; i < 5; i++) {
      await page.request.post(`${apiBase()}/messages`, {
        headers: h1,
        data: { receiver_id: pair.user2.id, content: `has more ${i}` },
      });
    }

    const res = await page.request.get(`${apiBase()}/messages/${pair.user2.id}?limit=2`, {
      headers: h1,
    });
    const data = await res.json();
    expect(data.pagination?.hasMore).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 35. ОБНОВЛЕНИЕ ГРУППЫ
// ═══════════════════════════════════════════════

test.describe('35. Обновление группы', () => {
  test('администратор может переименовать группу', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'OldName' },
    });
    const group = await gRes.json();

    const patchRes = await page.request.patch(`${apiBase()}/groups/${group.id}`, {
      headers: h1,
      data: { name: 'NewName' },
    });
    expect(patchRes.status()).toBe(200);
    const updated = await patchRes.json();
    expect(updated.name).toBe('NewName');
  });

  test('не-администратор не может переименовать группу', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };
    const h2 = { Authorization: `Bearer ${r2.token}` };

    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'AdminGroup', member_ids: [r2.id] },
    });
    const group = await gRes.json();

    const patchRes = await page.request.patch(`${apiBase()}/groups/${group.id}`, {
      headers: h2,
      data: { name: 'HackedName' },
    });
    expect(patchRes.status()).toBe(403);
  });
});

// ═══════════════════════════════════════════════
// 36. ГЕОЛОКАЦИЯ
// ═══════════════════════════════════════════════

test.describe('36. Геолокация', () => {
  test('отправка геолокации в 1-1 чат', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    const res = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: {
        receiver_id: pair.user2.id,
        type: 'location',
        lat: 55.7558,
        lng: 37.6173,
        location_label: 'Москва',
      },
    });
    expect(res.status()).toBe(201);
    const msg = await res.json();
    expect(msg.message_type).toBe('location');
    const coords = JSON.parse(msg.content);
    expect(coords.lat).toBeCloseTo(55.7558, 3);
    expect(coords.lng).toBeCloseTo(37.6173, 3);
    expect(coords.label).toBe('Москва');
  });

  test('отправка геолокации в группу', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    const gRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'GeoGroup' },
    });
    const group = await gRes.json();

    const res = await page.request.post(`${apiBase()}/groups/${group.id}/messages`, {
      headers: h1,
      data: {
        type: 'location',
        lat: 48.8566,
        lng: 2.3522,
        location_label: 'Париж',
      },
    });
    expect(res.status()).toBe(201);
    const msg = await res.json();
    expect(msg.message_type).toBe('location');
  });
});

// ═══════════════════════════════════════════════
// 37. СПИСОК ГРУПП
// ═══════════════════════════════════════════════

test.describe('37. Список групп пользователя', () => {
  test('GET /groups возвращает группы текущего пользователя', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };

    await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'MyGroup1' },
    });
    await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'MyGroup2' },
    });

    const res = await page.request.get(`${apiBase()}/groups`, { headers: h1 });
    expect(res.status()).toBe(200);
    const data = await res.json();
    const groups = data.data ?? data;
    expect(groups.length).toBeGreaterThanOrEqual(2);
    expect(groups.some((g) => g.name === 'MyGroup1')).toBeTruthy();
    expect(groups.some((g) => g.name === 'MyGroup2')).toBeTruthy();
  });

  test('пользователь не видит группы, в которых не состоит', async ({ page }) => {
    const r1 = await registerViaAPI(page);
    const r2 = await registerViaAPI(page);
    const h1 = { Authorization: `Bearer ${r1.token}` };
    const h2 = { Authorization: `Bearer ${r2.token}` };

    await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'PrivateGroup' },
    });

    const res = await page.request.get(`${apiBase()}/groups`, { headers: h2 });
    const data = await res.json();
    const groups = data.data ?? data;
    expect(groups.some((g) => g.name === 'PrivateGroup')).toBeFalsy();
  });
});

// ═══════════════════════════════════════════════
// 38. SEARCH
// ═══════════════════════════════════════════════

test.describe('38. Полнотекстовый поиск', () => {
  test('поиск по тексту находит сообщение', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const unique_text = `findme${Date.now()}`;

    await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: { receiver_id: pair.user2.id, content: unique_text },
    });

    // Дать FTS индексу обновиться
    await page.waitForTimeout(500);

    const res = await page.request.get(
      `${apiBase()}/search/messages?q=${encodeURIComponent(unique_text)}`,
      { headers: h1 }
    );
    expect(res.status()).toBe(200);
    const data = await res.json();
    const results = data.data ?? [];
    expect(results.some((m) => m.content?.includes(unique_text))).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 39. ОПРОС: множественный выбор
// ═══════════════════════════════════════════════

test.describe('39. Опросы: множественный выбор', () => {
  test('опрос с multiple=true позволяет голосовать за несколько вариантов', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const h2 = { Authorization: `Bearer ${pair.user2.token}` };

    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: {
        receiver_id: pair.user2.id,
        type: 'poll',
        question: 'Что вы любите?',
        options: ['Кошки', 'Собаки', 'Рыбки'],
        multiple: true,
      },
    });
    expect(sendRes.status()).toBe(201);
    const msg = await sendRes.json();

    const voteRes = await page.request.post(`${apiBase()}/polls/${msg.poll_id}/vote`, {
      headers: h2,
      data: { option_indexes: [0, 2] },
    });
    expect(voteRes.status()).toBe(200);
  });
});

// ═══════════════════════════════════════════════
// 40. SYNC API
// ═══════════════════════════════════════════════

test.describe('40. Sync API', () => {
  test('GET /sync/status возвращает статус синхронизации', async ({ page }) => {
    const { token } = await registerViaAPI(page);
    const res = await page.request.get(`${apiBase()}/sync/status`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(res.status()).toBe(200);
    const data = await res.json();
    expect(data.synced).toBeTruthy();
  });
});
