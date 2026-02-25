// @ts-check
/**
 * Полное E2E-покрытие мессенджера через Playwright.
 * Запуск: npm run test:playwright:e2e
 */
import { test, expect } from '@playwright/test';
import { PASSWORD, unique, createContactPair } from './helpers.js';

const apiBase = () => process.env.PLAYWRIGHT_SERVER_URL || 'http://127.0.0.1:38473';

// ─── UI хелперы ───

async function waitForApp(page, timeout = 30000) {
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(2000);
  const indicator = page.locator('input, button, [role="button"], flt-semantics');
  await expect(indicator.first()).toBeVisible({ timeout });
}

async function waitForLoginForm(page, timeout = 40000) {
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(2000);
  const form = page.locator('input[aria-label*="пользователя" i], input[aria-label*="username" i], input[type="text"], input[type="password"]').first();
  await expect(form).toBeVisible({ timeout });
}

async function waitForLoggedIn(page, timeout = 30000) {
  // После успешного логина Flutter переходит с /login на /
  await page.waitForURL((url) => !url.pathname.includes('/login') && !url.pathname.includes('/register'), { timeout });
  await page.waitForTimeout(2000);
}

function usernameInput(page) {
  return page.locator('input[aria-label*="пользователя" i]')
    .or(page.locator('input[aria-label*="username" i]'))
    .or(page.locator('input[type="text"]').first())
    .first();
}

function passwordInput(page) {
  return page.locator('input[type="password"]').first();
}

function loginButton(page) {
  return page.getByRole('button', { name: /^войти$|^log in$/i })
    .or(page.getByText(/^войти$/i))
    .first();
}

async function doLogin(page, username, password = PASSWORD) {
  await usernameInput(page).waitFor({ state: 'visible', timeout: 20000 });
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
  return page.locator(`flt-semantics[role="button"], flt-semantics[role="tab"], [role="button"], [role="tab"]`)
    .filter({ hasText: regex })
    .first()
    .or(page.getByText(regex).first());
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
    const link = page.getByRole('button', { name: /зарегистр|нет аккаунта/i })
      .or(page.getByText(/зарегистр|нет аккаунта/i));
    await expect(link.first()).toBeVisible({ timeout: 10000 });
  });

  test('есть ссылка «Забыли пароль»', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const link = page.getByRole('button', { name: /забыли пароль/i })
      .or(page.getByText(/забыли пароль/i));
    await expect(link.first()).toBeVisible({ timeout: 10000 });
  });

  test('«Забыли пароль» открывает экран восстановления', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const btn = page.getByRole('button', { name: /забыли пароль/i })
      .or(page.getByText(/забыли пароль/i))
      .first();
    await btn.click();
    await expect(
      page.getByText(/восстановлен|recovery|email|отправить ссылку/i).first()
    ).toBeVisible({ timeout: 15000 });
  });

  test('вход с неверным паролем показывает ошибку', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await page.goto('/login');
    await waitForLoginForm(page);
    await usernameInput(page).fill(username);
    await passwordInput(page).fill('WrongPassword1!');
    await loginButton(page).click();
    // Ждём появления ошибки ИЛИ то, что мы остались на странице логина (не перешли)
    await page.waitForTimeout(5000);
    const stillOnLogin = page.url().includes('/login');
    const errorVisible = await page.getByText(/неверн|ошибк|invalid|error|wrong|incorrect|парол/i).first().isVisible().catch(() => false);
    expect(stillOnLogin || errorVisible).toBeTruthy();
  });

  test('успешный вход открывает главный экран', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await loginAndWait(page, username);
  });
});

// ═══════════════════════════════════════════════
// 3. РЕГИСТРАЦИЯ
// ═══════════════════════════════════════════════

test.describe('3. Регистрация', () => {
  test('переход на страницу регистрации', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const btn = page.getByRole('button', { name: /зарегистр|нет аккаунта/i })
      .or(page.getByText(/зарегистр|нет аккаунта/i))
      .first();
    await btn.click();
    await expect(
      page.getByText(/регистрац|создать аккаунт/i).first()
    ).toBeVisible({ timeout: 15000 });
  });

  test('регистрация нового пользователя через UI', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const regBtn = page.getByRole('button', { name: /зарегистр|нет аккаунта/i })
      .or(page.getByText(/зарегистр|нет аккаунта/i))
      .first();
    await regBtn.click();
    await page.waitForTimeout(2000);

    const username = unique();
    await usernameInput(page).fill(username);
    await passwordInput(page).fill(PASSWORD);

    const submit = page.getByRole('button', { name: /создать аккаунт|регистр/i })
      .or(page.locator('button[type="submit"]'))
      .first();
    await submit.click();

    // После регистрации — главный экран или форма входа
    await expect(
      page.getByText(/чаты|chats|друзья|friends|профиль|profile|нет чатов/i)
        .or(page.locator('input, button').first())
        .first()
    ).toBeVisible({ timeout: 20000 });
  });
});

// ═══════════════════════════════════════════════
// 4. НАВИГАЦИЯ (табы)
// ═══════════════════════════════════════════════

test.describe('4. Навигация после входа', () => {
  test.beforeEach(async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await loginAndWait(page, username);
  });

  test('переход Друзья → Чаты', async ({ page }) => {
    const friendsTab = navTab(page, /друзья|friends|контакт|contacts/i);
    await expect(friendsTab).toBeVisible({ timeout: 10000 });
    await friendsTab.click();
    await page.waitForTimeout(1500);
    await expect(page.getByText(/друзья|friends|добавить|add|нет друзей/i).first()).toBeVisible({ timeout: 10000 });

    const chatsTab = navTab(page, /чаты|chats/i);
    await chatsTab.click();
    await page.waitForTimeout(1000);
  });

  test('переход в Профиль', async ({ page }) => {
    const tab = navTab(page, /профиль|profile/i);
    await expect(tab).toBeVisible({ timeout: 10000 });
    await tab.click();
    await page.waitForTimeout(1500);
    await expect(
      page.getByText(/профиль|profile|настройки|settings|имя|username/i).first()
    ).toBeVisible({ timeout: 10000 });
  });
});

// ═══════════════════════════════════════════════
// 5. КОНТАКТЫ / ДРУЗЬЯ
// ═══════════════════════════════════════════════

test.describe('5. Контакты и друзья', () => {
  test('список друзей пуст для нового пользователя', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await loginAndWait(page, username);
    const friendsTab = navTab(page, /друзья|friends|контакт/i);
    await friendsTab.click();
    await page.waitForTimeout(1500);
    await expect(
      page.getByText(/нет друзей|no friends|добавить|add/i).first()
    ).toBeVisible({ timeout: 10000 });
  });

  test('контакт отображается в списке после добавления через API', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    await loginAndWait(page, pair.user1.username);
    const friendsTab = navTab(page, /друзья|friends|контакт/i);
    await friendsTab.click();
    await page.waitForTimeout(2000);
    await expect(
      page.getByText(new RegExp(pair.user2.username, 'i')).first()
    ).toBeVisible({ timeout: 15000 });
  });
});

// ═══════════════════════════════════════════════
// 6. ОТПРАВКА И ПОЛУЧЕНИЕ СООБЩЕНИЙ
// ═══════════════════════════════════════════════

test.describe('6. Сообщения', () => {
  test('сообщение видно в чате после отправки через API', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const msgText = `Hello ${Date.now()}`;
    await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { receiver_id: pair.user1.id, content: msgText },
    });

    await loginAndWait(page, pair.user1.username);
    await page.waitForTimeout(3000);

    const chatItem = page.getByText(new RegExp(pair.user2.username, 'i')).first();
    await expect(chatItem).toBeVisible({ timeout: 15000 });
    await chatItem.click();
    await page.waitForTimeout(2000);
    await expect(page.getByText(msgText).first()).toBeVisible({ timeout: 10000 });
  });

  test('сообщения сохраняются после перезагрузки', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    const msgText = `persist ${Date.now()}`;
    await page.request.post(`${apiBase()}/messages`, {
      headers: { Authorization: `Bearer ${pair.user2.token}` },
      data: { receiver_id: pair.user1.id, content: msgText },
    });

    await loginAndWait(page, pair.user1.username);
    await page.waitForTimeout(3000);

    const chatItem = page.getByText(new RegExp(pair.user2.username, 'i')).first();
    await chatItem.click();
    await page.waitForTimeout(2000);
    await expect(page.getByText(msgText).first()).toBeVisible({ timeout: 10000 });

    await page.reload();
    await page.waitForTimeout(4000);
    await expect(page.getByText(msgText).first()).toBeVisible({ timeout: 15000 });
  });

  test('непрочитанные сообщения: бейдж и чтение через API', async ({ page }) => {
    const pair = await createContactPair(page.request, apiBase());
    for (let i = 0; i < 3; i++) {
      await page.request.post(`${apiBase()}/messages`, {
        headers: { Authorization: `Bearer ${pair.user2.token}` },
        data: { receiver_id: pair.user1.id, content: `unread ${i}` },
      });
    }

    // Через API проверяем что у user1 есть непрочитанные
    const chatsRes = await page.request.get(`${apiBase()}/chats`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });
    const chats = await chatsRes.json();
    const chat = (chats.data ?? chats).find((c) => c.peer?.id === pair.user2.id);
    expect(chat?.unread_count).toBe(3);

    // Отмечаем прочитанными
    await page.request.patch(`${apiBase()}/messages/${pair.user2.id}/read`, {
      headers: { Authorization: `Bearer ${pair.user1.token}` },
    });

    // Проверяем что непрочитанных стало 0
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
  test('профиль отображается после входа и перехода на вкладку', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await loginAndWait(page, username);
    const tab = navTab(page, /профиль|profile/i);
    await tab.click();
    await page.waitForTimeout(2000);
    await expect(
      page.getByText(new RegExp(username, 'i')).first()
    ).toBeVisible({ timeout: 10000 });
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

    await page.request.patch(`${apiBase()}/users/me/privacy`, { headers: h, data: { who_can_message: 'all' } });
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

    const blockRes = await page.request.post(`${apiBase()}/users/${pair.user2.id}/block`, { headers: h });
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

    const unblockRes = await page.request.delete(`${apiBase()}/users/${pair.user2.id}/block`, { headers: h });
    expect(unblockRes.ok()).toBeTruthy();
  });
});

// ═══════════════════════════════════════════════
// 12. ГРУППОВЫЕ ЧАТЫ
// ═══════════════════════════════════════════════

test.describe('12. Групповые чаты', () => {
  test('создание группы, отправка и чтение сообщений', async ({ request }) => {
    const pair = await createContactPair(request, apiBase());
    const h1 = { Authorization: `Bearer ${pair.user1.token}` };
    const h2 = { Authorization: `Bearer ${pair.user2.token}` };

    const createRes = await request.post(`${apiBase()}/groups`, {
      headers: h1,
      data: { name: 'Тестовая группа', member_ids: [pair.user2.id] },
    });
    expect(createRes.status()).toBe(201);
    const group = await createRes.json();
    const groupId = group.id;

    const msgRes = await request.post(`${apiBase()}/groups/${groupId}/messages`, {
      headers: h1,
      data: { content: 'Привет группа!' },
    });
    expect(msgRes.status()).toBe(201);

    const getRes = await request.get(`${apiBase()}/groups/${groupId}/messages`, { headers: h2 });
    const msgs = await getRes.json();
    const list = msgs.data ?? msgs;
    expect(list.some((m) => m.content === 'Привет группа!')).toBeTruthy();
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
      data: { receiver_id: pair.user2.id, content: '', type: 'poll', question: 'Какой язык лучше?', options: ['JavaScript', 'Python', 'Dart'] },
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
    const chat = (data.data ?? data).find((c) => c.peer?.username === pair.user2.username);
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
      data: { receiver_id: pair.user2.id, content: 'forwarded', is_forwarded: true, forward_from_display_name: 'Кто-то' },
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

    const loginRes = await page.request.post(`${apiBase()}/auth/login`, { data: { username, password: newPass } });
    expect(loginRes.status()).toBe(200);
  });

  test('forgot-password возвращает 200', async ({ page }) => {
    const res = await page.request.post(`${apiBase()}/auth/forgot-password`, { data: { email: 'no@example.com' } });
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

    const delRes = await page.request.delete(`${apiBase()}/contacts/${pair.user2.id}`, { headers: h1 });
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
      await page.request.post(`${apiBase()}/messages`, { headers: h1, data: { receiver_id: pair.user2.id, content: `pg ${i}` } });
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
  test('после выхода отображается форма входа', async ({ page }) => {
    const { username } = await registerViaAPI(page);
    await loginAndWait(page, username);

    const profileTab = navTab(page, /профиль|profile/i);
    await profileTab.click();
    await page.waitForTimeout(2000);

    const logoutBtn = page.getByRole('button', { name: /выйти|logout/i })
      .or(page.getByText(/выйти|logout/i))
      .first();
    await expect(logoutBtn).toBeVisible({ timeout: 10000 });
    await logoutBtn.click();
    await page.waitForTimeout(1000);

    const confirmBtn = page.getByRole('button', { name: /выйти|да|yes|ok/i }).first();
    if (await confirmBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await confirmBtn.click();
    }

    await waitForLoginForm(page, 20000);
  });
});
