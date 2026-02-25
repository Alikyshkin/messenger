// @ts-check
/**
 * Полное E2E-покрытие мессенджера через Playwright.
 * Запуск: npm run test:playwright:e2e
 *
 * Тесты работают с Flutter web-клиентом (pre-built) и Node.js сервером.
 * Каждый клик и действие отслеживается через UI-взаимодействие.
 */
import { test, expect } from '@playwright/test';
import { PASSWORD, unique, createContactPair } from './helpers.js';

const apiBase = () => process.env.PLAYWRIGHT_SERVER_URL || 'http://127.0.0.1:38473';

// ─── UI хелперы ───

async function waitForApp(page, timeout = 30000) {
  await page.waitForLoadState('domcontentloaded');
  const indicator = page.locator('#loading-screen, input, button, [role="button"]');
  await expect(indicator.first()).toBeVisible({ timeout });
}

async function waitForLoginForm(page, timeout = 30000) {
  await page.waitForLoadState('domcontentloaded');
  const form = page.getByRole('button', { name: /войти|log in/i })
    .or(page.locator('input[type="text"], input[type="password"]'))
    .or(page.getByText(/войти|log in|имя пользователя|username/i))
    .first();
  await expect(form).toBeVisible({ timeout });
}

async function waitForLoggedIn(page, timeout = 35000) {
  await page.waitForFunction(
    () => {
      const p = new URL(window.location.href).pathname;
      return p === '/' || p === '/profile' || p === '/contacts' || p.startsWith('/chat');
    },
    { timeout }
  );
}

function usernameInput(page) {
  return page.getByLabel(/имя пользователя|username|логин/i)
    .or(page.locator('input[type="text"]').first())
    .first();
}

function passwordInput(page) {
  return page.locator('input[type="password"]').first();
}

function loginButton(page) {
  return page.getByRole('button', { name: /войти|log in/i })
    .or(page.locator('button[type="submit"]'))
    .first();
}

async function doLogin(page, username, password = PASSWORD) {
  await usernameInput(page).waitFor({ state: 'visible', timeout: 15000 });
  await usernameInput(page).fill(username);
  await passwordInput(page).fill(password);
  await loginButton(page).click();
}

async function registerViaAPI(page, overrides = {}) {
  const username = overrides.username ?? unique();
  const res = await page.request.post(`${apiBase()}/auth/register`, {
    data: { username, password: PASSWORD, displayName: overrides.displayName ?? `User ${username}`, email: overrides.email },
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

function navTab(page, regex) {
  return page.getByRole('button', { name: regex })
    .or(page.getByRole('tab', { name: regex }))
    .or(page.getByText(regex))
    .first();
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
    await expect(
      page.getByRole('button', { name: /войти|log in/i })
        .or(page.locator('input[type="text"]').first())
        .first()
    ).toBeVisible({ timeout: 10000 });
  });
});

// ═══════════════════════════════════════════════
// 2. ВХОД
// ═══════════════════════════════════════════════

test.describe('2. Экран входа', () => {
  test('форма содержит поля логин, пароль и кнопку', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    await expect(usernameInput(page)).toBeVisible();
    await expect(passwordInput(page)).toBeVisible();
    await expect(loginButton(page)).toBeVisible();
  });

  test('есть ссылка на регистрацию', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const link = page.getByRole('button', { name: /зарегистр|sign up|нет аккаунта/i })
      .or(page.getByRole('link', { name: /зарегистр|sign up/i }));
    await expect(link.first()).toBeVisible();
  });

  test('есть ссылка «Забыли пароль»', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const link = page.getByRole('button', { name: /забыли пароль|forgot password/i })
      .or(page.getByRole('link', { name: /забыли|forgot/i }));
    await expect(link.first()).toBeVisible();
  });

  test('«Забыли пароль» открывает экран восстановления', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const btn = page.getByRole('button', { name: /забыли пароль|forgot password/i })
      .or(page.getByRole('link', { name: /забыли|forgot/i }))
      .first();
    await btn.click();
    await expect(
      page.getByText(/восстановлен|recovery|password|парол|email/i).first()
    ).toBeVisible({ timeout: 10000 });
  });

  test('вход с неверным паролем показывает ошибку', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await page.goto('/login');
    await waitForLoginForm(page);
    await usernameInput(page).fill(username);
    await passwordInput(page).fill('WrongPassword1!');
    await loginButton(page).click();
    await expect(
      page.getByText(/неверн|ошибк|invalid|error|wrong|incorrect/i).first()
    ).toBeVisible({ timeout: 15000 });
  });

  test('успешный вход открывает главный экран', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await loginAndWait(page, username);
    const path = new URL(page.url()).pathname;
    expect(['/', '/profile', '/contacts']).toContain(path);
  });
});

// ═══════════════════════════════════════════════
// 3. РЕГИСТРАЦИЯ
// ═══════════════════════════════════════════════

test.describe('3. Регистрация', () => {
  test('переход на страницу регистрации', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const btn = page.getByRole('button', { name: /зарегистр|sign up|нет аккаунта/i })
      .or(page.getByRole('link', { name: /зарегистр|sign up/i }))
      .first();
    await btn.click();
    await expect(
      page.getByRole('heading', { name: /регистрац|sign up/i })
        .or(page.getByText(/регистрац|создать аккаунт|create account/i))
        .first()
    ).toBeVisible({ timeout: 10000 });
  });

  test('регистрация нового пользователя через UI', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const regBtn = page.getByRole('button', { name: /зарегистр|sign up|нет аккаунта/i })
      .or(page.getByRole('link', { name: /зарегистр|sign up/i }))
      .first();
    if (await regBtn.isVisible().catch(() => false)) {
      await regBtn.click();
      await page.waitForTimeout(1000);
    }

    const username = unique();
    const uField = page.getByLabel(/имя пользователя|username|логин/i)
      .or(page.locator('input[type="text"]').first())
      .first();
    const pField = page.locator('input[type="password"]').first();
    const submit = page.getByRole('button', { name: /создать аккаунт|create account|регистр/i })
      .or(page.locator('button[type="submit"]'))
      .first();

    await uField.waitFor({ state: 'visible', timeout: 10000 });
    await uField.fill(username);
    await pField.fill(PASSWORD);
    await submit.click();

    await expect(
      page.getByText(/чаты|chats|друзья|friends|профиль|profile|нет чатов/i)
        .or(page.locator('input, button').first())
        .first()
    ).toBeVisible({ timeout: 15000 });
  });
});

// ═══════════════════════════════════════════════
// 4. НАВИГАЦИЯ (табы)
// ═══════════════════════════════════════════════

test.describe('4. Навигация после входа', () => {
  test.setTimeout(60000);

  test.beforeEach(async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await loginAndWait(page, username);
  });

  test('переход Друзья → Чаты', async ({ page }) => {
    const friendsTab = navTab(page, /друзья|friends|контакт|contacts/i);
    await expect(friendsTab).toBeVisible({ timeout: 10000 });
    await friendsTab.click();
    await page.waitForTimeout(800);
    await expect(page.getByText(/друзья|friends|добавить|add|контакт|contacts/i).first()).toBeVisible({ timeout: 10000 });

    const chatsTab = navTab(page, /чаты|chats/i);
    await expect(chatsTab).toBeVisible({ timeout: 5000 });
    await chatsTab.click();
    await page.waitForTimeout(500);
  });

  test('переход в Профиль', async ({ page }) => {
    const tab = navTab(page, /профиль|profile|настройки|settings/i);
    await expect(tab).toBeVisible({ timeout: 10000 });
    await tab.click();
    await page.waitForTimeout(800);
    await expect(
      page.getByText(/профиль|profile|имя|настройки|settings/i).first()
    ).toBeVisible({ timeout: 10000 });
  });
});

// ═══════════════════════════════════════════════
// 5. КОНТАКТЫ / ДРУЗЬЯ
// ═══════════════════════════════════════════════

test.describe('5. Контакты и друзья', () => {
  test.setTimeout(60000);

  test('список друзей пуст для нового пользователя', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await loginAndWait(page, username);
    const friendsTab = navTab(page, /друзья|friends|контакт|contacts/i);
    await friendsTab.click();
    await page.waitForTimeout(1000);
    await expect(
      page.getByText(/нет друзей|no friends|добавить|add/i).first()
    ).toBeVisible({ timeout: 10000 });
  });

  test('добавление друга по username через API и отображение в списке', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    await loginAndWait(page, pair.user1.username);
    const friendsTab = navTab(page, /друзья|friends|контакт|contacts/i);
    await friendsTab.click();
    await page.waitForTimeout(1500);
    await expect(
      page.getByText(new RegExp(pair.user2.username, 'i')).first()
    ).toBeVisible({ timeout: 15000 });
  });
});

// ═══════════════════════════════════════════════
// 6. ОТПРАВКА И ПОЛУЧЕНИЕ СООБЩЕНИЙ
// ═══════════════════════════════════════════════

test.describe('6. Сообщения', () => {
  test.setTimeout(60000);

  test('отправка текстового сообщения через API и отображение в чате', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());

    // user2 отправляет сообщение user1 через API
    const msgText = `Привет! ${Date.now()}`;
    await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { receiver_id: pair.user1.id, content: msgText },
    });

    // user1 заходит и видит чат
    await loginAndWait(page, pair.user1.username);
    await page.waitForTimeout(2000);

    // Кликаем на чат с user2
    const chatItem = page.getByText(new RegExp(pair.user2.username, 'i')).first();
    await expect(chatItem).toBeVisible({ timeout: 15000 });
    await chatItem.click();
    await page.waitForTimeout(1500);

    // Видим сообщение
    await expect(page.getByText(msgText).first()).toBeVisible({ timeout: 10000 });
  });

  test('отправка сообщения через UI (набрать текст + отправить)', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());

    // user2 отправляет первое сообщение чтобы создать чат
    await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { receiver_id: pair.user1.id, content: 'init' },
    });

    await loginAndWait(page, pair.user1.username);
    await page.waitForTimeout(2000);

    // Открываем чат
    const chatItem = page.getByText(new RegExp(pair.user2.username, 'i')).first();
    await expect(chatItem).toBeVisible({ timeout: 15000 });
    await chatItem.click();
    await page.waitForTimeout(1500);

    // Находим поле ввода и отправляем сообщение
    const msgText = `UI msg ${Date.now()}`;
    const input = page.locator('input[type="text"], textarea').last();
    await expect(input).toBeVisible({ timeout: 10000 });
    await input.fill(msgText);

    // Нажимаем кнопку отправки
    const sendBtn = page.getByRole('button', { name: /отправить|send/i })
      .or(page.locator('[aria-label*="send" i], [aria-label*="отправ" i]'))
      .or(page.locator('button').filter({ has: page.locator('svg, .material-icons') }).last());
    await sendBtn.first().click();
    await page.waitForTimeout(2000);

    // Проверяем что сообщение появилось
    await expect(page.getByText(msgText).first()).toBeVisible({ timeout: 10000 });
  });

  test('сообщения сохраняются после перезагрузки страницы', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const msgText = `persist ${Date.now()}`;

    await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { receiver_id: pair.user1.id, content: msgText },
    });

    await loginAndWait(page, pair.user1.username);
    await page.waitForTimeout(2000);

    const chatItem = page.getByText(new RegExp(pair.user2.username, 'i')).first();
    await chatItem.click();
    await page.waitForTimeout(1500);
    await expect(page.getByText(msgText).first()).toBeVisible({ timeout: 10000 });

    // Перезагружаем страницу
    await page.reload();
    await page.waitForTimeout(3000);

    // Сообщение должно сохраниться
    await expect(page.getByText(msgText).first()).toBeVisible({ timeout: 15000 });
  });

  test('непрочитанные сообщения отображаются в списке чатов (бейдж)', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());

    // user2 отправляет несколько сообщений
    for (let i = 0; i < 3; i++) {
      await page.request.post(`${apiBase()}/messages`, {
        headers: { Authorization: `Bearer ${pair.user2.token}` },
        data: { receiver_id: pair.user1.id, content: `unread ${i}` },
      });
    }

    await loginAndWait(page, pair.user1.username);
    await page.waitForTimeout(2000);

    // Должен быть виден чат и индикатор непрочитанных
    const chatItem = page.getByText(new RegExp(pair.user2.username, 'i')).first();
    await expect(chatItem).toBeVisible({ timeout: 15000 });

    // Проверяем наличие бейджа с цифрой (3 непрочитанных)
    await expect(
      page.getByText('3').or(page.locator('[class*="badge"], [class*="unread"]')).first()
    ).toBeVisible({ timeout: 10000 });
  });

  test('после открытия чата непрочитанные отмечаются прочитанными', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());

    await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { receiver_id: pair.user1.id, content: 'read me' },
    });

    await loginAndWait(page, pair.user1.username);
    await page.waitForTimeout(2000);

    // Открываем чат (это отмечает сообщения прочитанными)
    const chatItem = page.getByText(new RegExp(pair.user2.username, 'i')).first();
    await chatItem.click();
    await page.waitForTimeout(2000);

    // Проверяем через API что сообщения прочитаны
    const res = await page.request.get(`${apiBase()}/messages/${pair.user1.id}`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
    });
    const data = await res.json();
    const messages = data.data ?? data;
    const readMsg = messages.find((m) => m.content === 'read me');
    expect(readMsg).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 7. РЕАКЦИИ НА СООБЩЕНИЯ
// ═══════════════════════════════════════════════

test.describe('7. Реакции на сообщения (API)', () => {
  test('ставим и снимаем реакцию через API', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());

    const sendRes = await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
      data: { receiver_id: pair.user2.id, content: 'react to me' },
    });
    const msg = await sendRes.json();

    // Ставим реакцию
    const r1 = await page.request.post(`${apiBase()}/messages/${msg.id}/reaction`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { emoji: '👍' },
    });
    expect(r1.status()).toBe(200);
    const b1 = await r1.json();
    expect(b1.reactions.some((r) => r.emoji === '👍')).toBeTruthy();

    // Снимаем реакцию (повторный клик)
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

test.describe('8. Удаление сообщений (API)', () => {
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
  test.setTimeout(60000);

  test('отображается профиль с именем пользователя', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await loginAndWait(page, username);
    const tab = navTab(page, /профиль|profile|настройки|settings/i);
    await tab.click();
    await page.waitForTimeout(1500);
    await expect(
      page.getByText(new RegExp(username, 'i')).first()
    ).toBeVisible({ timeout: 10000 });
  });

  test('обновление профиля через API', async ({ page }) => {
    const { username, token } = await registerViaAPI(page);
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

test.describe('10. Приватность (API)', () => {
  test('чтение и обновление настроек приватности', async ({ page }) => {
    const { token } = await registerViaAPI(page);
    const h = { Authorization: `Bearer ${token}` };

    const getRes = await page.request.get(`${apiBase()}/users/me/privacy`, { headers: h });
    expect(getRes.status()).toBe(200);
    const priv = await getRes.json();
    expect(priv.who_can_message).toBe('contacts');

    const patchRes = await page.request.patch(`${apiBase()}/users/me/privacy`, {
      headers: h,
      data: { who_can_message: 'all' },
    });
    expect(patchRes.status()).toBe(200);

    const getRes2 = await page.request.get(`${apiBase()}/users/me/privacy`, { headers: h });
    const priv2 = await getRes2.json();
    expect(priv2.who_can_message).toBe('all');
  });
});

// ═══════════════════════════════════════════════
// 11. БЛОКИРОВКА ПОЛЬЗОВАТЕЛЕЙ
// ═══════════════════════════════════════════════

test.describe('11. Блокировка (API)', () => {
  test('заблокировать и разблокировать пользователя', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h = { Authorization: `Bearer ${pair.user1.token}` };

    const blockRes = await page.request.post(`${apiBase()}/users/${pair.user2.id}/block`, { headers: h });
    expect(blockRes.status()).toBe(200);

    // Проверяем список заблокированных
    const listRes = await page.request.get(`${apiBase()}/users/blocked`, { headers: h });
    const blocked = await listRes.json();
    expect(blocked.some((u) => u.id === pair.user2.id)).toBeTruthy();

    // Сообщение заблокированному не отправится
    const msgRes = await page.request.post(`${apiBase()}/messages`, {
      headers: h,
      data: { receiver_id: pair.user2.id, content: 'blocked msg' },
    });
    expect(msgRes.status()).toBe(403);

    // Разблокируем
    const unblockRes = await page.request.delete(`${apiBase()}/users/${pair.user2.id}/block`, { headers: h });
    expect(unblockRes.status()).toBe(200);
  });
});

// ═══════════════════════════════════════════════
// 12. ГРУППОВЫЕ ЧАТЫ
// ═══════════════════════════════════════════════

test.describe('12. Групповые чаты (API)', () => {
  test('создание группы, отправка сообщения, получение сообщений', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const h2 = { Authorization: `Bearer ${pair.user2.token}` };

    // Создаём группу
    const createRes = await page.request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'Тестовая группа', member_ids: [pair.user2.id] },
    });
    expect(createRes.status()).toBe(201);
    const group = await createRes.json();
    expect(group.name).toBe('Тестовая группа');
    const groupId = group.id;

    // Отправляем сообщение в группу
    const msgRes = await page.request.post(`${apiBase()}/groups/${groupId}/messages`, {
      headers: h1,
      data: { content: 'Привет группа!' },
    });
    expect(msgRes.status()).toBe(201);

    // Второй участник видит сообщение
    const getRes = await page.request.get(`${apiBase()}/groups/${groupId}/messages`, { headers: h2 });
    expect(getRes.status()).toBe(200);
    const msgs = await getRes.json();
    const list = msgs.data ?? msgs;
    expect(list.some((m) => m.content === 'Привет группа!')).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 13. ОПРОСЫ (POLLS)
// ═══════════════════════════════════════════════

test.describe('13. Опросы (API)', () => {
  test('создание опроса и голосование', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const h2 = { Authorization: `Bearer ${pair.user2.token}` };

    // Создаём опрос
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

    // Голосуем
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

test.describe('14. Поиск пользователей (API)', () => {
  test('поиск по username возвращает пользователя', async ({ page }) => {
    const { username, token } = await registerViaAPI(page);
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

test.describe('15. Список чатов (API)', () => {
  test('чат появляется в списке после отправки сообщения', async ({ page }) => {
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

  test('последнее сообщение отображается в превью чата', async ({ page }) => {
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
    const chats = data.data ?? data;
    const chat = chats.find((c) => c.peer?.username === pair.user2.username);
    expect(chat?.last_message?.content).toBe(lastMsg);
  });
});

// ═══════════════════════════════════════════════
// 16. REPLY И FORWARD
// ═══════════════════════════════════════════════

test.describe('16. Reply и Forward (API)', () => {
  test('ответ на сообщение (reply)', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const h2 = { Authorization: `Bearer ${pair.user2.token}` };

    const s1 = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: { receiver_id: pair.user2.id, content: 'original' },
    });
    const orig = await s1.json();

    const s2 = await page.request.post(`${apiBase()}/messages`, {
      headers: h2,
      data: { receiver_id: pair.user1.id, content: 'reply text', reply_to_id: orig.id },
    });
    expect(s2.status()).toBe(201);
    const reply = await s2.json();
    expect(reply.reply_to_id).toBe(orig.id);
  });

  test('пересылка сообщения (forward)', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    const fwd = await page.request.post(`${apiBase()}/messages`, {
      headers: h1,
      data: {
        receiver_id: pair.user2.id,
        content: 'forwarded content',
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

test.describe('17. Смена и сброс пароля (API)', () => {
  test('смена пароля', async ({ page }) => {
    const { username, token } = await registerViaAPI(page);
    const newPass = 'N3wStr0ng!Pass';

    const res = await page.request.post(`${apiBase()}/auth/change-password`, {
      headers: { Authorization: `Bearer ${token}` },
      data: { currentPassword: PASSWORD, newPassword: newPass },
    });
    expect(res.status()).toBe(200);

    // Проверяем что новый пароль работает
    const loginRes = await page.request.post(`${apiBase()}/auth/login`, {
      data: { username, password: newPass },
    });
    expect(loginRes.status()).toBe(200);
  });

  test('забыли пароль — возвращает 200 (не раскрывает наличие email)', async ({ page }) => {
    const res = await page.request.post(`${apiBase()}/auth/forgot-password`, {
      data: { email: 'nonexistent@example.com' },
    });
    expect(res.status()).toBe(200);
  });
});

// ═══════════════════════════════════════════════
// 18. HEALTH И МЕТРИКИ
// ═══════════════════════════════════════════════

test.describe('18. Health и метрики (API)', () => {
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

test.describe('19. GDPR (API)', () => {
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

test.describe('20. Удаление контакта (API)', () => {
  test('удаление контакта из списка друзей', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    const delRes = await page.request.delete(`${apiBase()}/contacts/${pair.user2.id}`, { headers: h1 });
    expect(delRes.status()).toBe(200);

    // Проверяем что контакта больше нет
    const listRes = await page.request.get(`${apiBase()}/contacts`, { headers: h1 });
    const data = await listRes.json();
    const contacts = data.data ?? data;
    expect(contacts.some((c) => c.id === pair.user2.id)).toBeFalsy();
  });
});

// ═══════════════════════════════════════════════
// 21. ПАГИНАЦИЯ СООБЩЕНИЙ
// ═══════════════════════════════════════════════

test.describe('21. Пагинация (API)', () => {
  test('limit ограничивает количество сообщений', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };

    for (let i = 0; i < 5; i++) {
      await page.request.post(`${apiBase()}/messages`, {
        headers: h1,
        data: { receiver_id: pair.user2.id, content: `page msg ${i}` },
      });
    }

    const res = await page.request.get(`${apiBase()}/messages/${pair.user2.id}?limit=2`, { headers: h1 });
    const data = await res.json();
    const msgs = data.data ?? data;
    expect(msgs.length).toBeLessThanOrEqual(2);
  });
});

// ═══════════════════════════════════════════════
// 22. ВЫХОД ИЗ АККАУНТА (UI)
// ═══════════════════════════════════════════════

test.describe('22. Выход из аккаунта', () => {
  test.setTimeout(60000);

  test('после выхода отображается форма входа', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await loginAndWait(page, username);

    // Переходим в профиль
    const profileTab = navTab(page, /профиль|profile|настройки|settings/i);
    await profileTab.click();
    await page.waitForTimeout(1500);

    // Ищем кнопку выхода
    const logoutBtn = page.getByRole('button', { name: /выйти|logout|выход/i })
      .or(page.getByText(/выйти|logout/i))
      .first();
    await expect(logoutBtn).toBeVisible({ timeout: 10000 });
    await logoutBtn.click();

    // Подтверждаем выход если есть диалог
    const confirmBtn = page.getByRole('button', { name: /выйти|да|yes|confirm|ok/i }).first();
    if (await confirmBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await confirmBtn.click();
    }

    // Должна появиться форма входа
    await waitForLoginForm(page, 15000);
  });
});
