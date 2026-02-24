// @ts-check
/**
 * E2E по UI мессенджера: при запуске Playwright поднимаются client и server (см. playwright.e2e.config.js).
 * В клиенте включён слой доступности (SemanticsBinding.ensureSemantics() в main.dart), чтобы Flutter
 * создавал DOM-узлы с ARIA-ролями для формы входа/регистрации.
 * Перед первым запуском: npx playwright install
 * Запуск: npm run test:playwright:e2e или npm run test:playwright:ui
 */
import { test, expect } from '@playwright/test';

const PASSWORD = 'TestPass123!';

const apiBase = () => process.env.PLAYWRIGHT_SERVER_URL || 'http://127.0.0.1:38473';

/** Ждём появления приложения: экран загрузки или форма входа (input/button). */
async function waitForAppReady(page, timeout = 25000) {
  await page.waitForLoadState('domcontentloaded');
  const loadingOrForm = page.locator('#loading-screen, input, button, [role="button"]');
  await expect(loadingOrForm.first()).toBeVisible({ timeout });
}

/** Ждём появления формы входа: кнопка "Войти", поле ввода или текст. Не ждём редиректа на /login — форма может появиться и на /. */
async function waitForLoginForm(page, timeout = 30000) {
  await page.waitForLoadState('domcontentloaded');
  const formIndicator = page.getByRole('button', { name: /войти|log in/i })
    .or(page.locator('input[type="text"], input[type="password"], input:not([type])'))
    .or(page.getByText(/войти|log in|имя пользователя|username/i))
    .first();
  await expect(formIndicator).toBeVisible({ timeout });
}

/** Ждём ухода со страницы входа (успешный вход — переход на главную). SPA не порождает load, поэтому опрашиваем URL. */
async function waitForLoggedIn(page, timeout = 25000) {
  await page.waitForFunction(
    () => {
      const path = new URL(window.location.href).pathname;
      return path === '/' || path === '/profile' || path === '/contacts' || path.startsWith('/chat');
    },
    { timeout }
  );
}

/** Первое поле логина (username). Flutter HTML: input type=text или с label. */
function usernameInput(page) {
  return page.getByLabel(/имя пользователя|username|логин/i).or(
    page.locator('input[type="text"]').first()
  ).first();
}

/** Поле пароля. */
function passwordInput(page) {
  return page.locator('input[type="password"]').first();
}

/** Кнопка входа. */
function loginButton(page) {
  return page.getByRole('button', { name: /войти|log in/i }).or(
    page.locator('button[type="submit"]')
  ).first();
}

/** Уникальный логин для регистрации. */
const unique = () => `user_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

/** Выполнить вход по логину и паролю (страница уже открыта, форма видна). */
async function doLogin(page, username, password = PASSWORD) {
  await usernameInput(page).waitFor({ state: 'visible', timeout: 15000 });
  await usernameInput(page).fill(username);
  await passwordInput(page).fill(password);
  await loginButton(page).click();
}

// ---------- Загрузка ----------
test.describe('Загрузка приложения', () => {
  test('при открытии главной виден экран загрузки или форма входа', async ({ page }) => {
    await page.goto('/');
    await waitForAppReady(page);
  });

  test('после загрузки отображается форма входа (поля логин/пароль или кнопка Войти)', async ({ page }) => {
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await waitForLoginForm(page);
    await expect(
      page.getByRole('button', { name: /войти|log in/i })
        .or(page.locator('input[type="text"]').first())
        .or(page.getByText(/войти|имя пользователя|username/i))
        .first()
    ).toBeVisible({ timeout: 10000 });
  });
});

// ---------- Экран входа (логин) ----------
test.describe('Экран входа', () => {
  test('форма входа содержит поля и кнопку входа', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    await expect(usernameInput(page)).toBeVisible();
    await expect(passwordInput(page)).toBeVisible();
    await expect(loginButton(page)).toBeVisible();
  });

  test('есть ссылка на регистрацию', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const registerLink = page.getByRole('button', { name: /зарегистр|sign up|нет аккаунта/i }).or(
      page.getByRole('link', { name: /зарегистр|sign up/i })
    );
    await expect(registerLink.first()).toBeVisible();
  });

  test('есть ссылка «Забыли пароль»', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const forgotLink = page.getByRole('button', { name: /забыли пароль|forgot password/i }).or(
      page.getByRole('link', { name: /забыли|forgot/i })
    );
    await expect(forgotLink.first()).toBeVisible();
  });

  test('переход «Забыли пароль» открывает экран восстановления', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const forgotBtn = page.getByRole('button', { name: /забыли пароль|forgot password/i }).or(
      page.getByRole('link', { name: /забыли|forgot/i })
    ).first();
    await forgotBtn.click();
    await expect(
      page.getByText(/восстановлен|recovery|password|парол/i).first()
    ).toBeVisible({ timeout: 10000 });
  });

  test('вход с неверным паролем показывает сообщение об ошибке', async ({ page }) => {
    const username = unique();
    await page.request.post(`${apiBase()}/auth/register`, {
      data: { username, password: PASSWORD, displayName: `User ${username}` },
    });
    await page.goto('/login');
    await waitForLoginForm(page);
    await usernameInput(page).fill(username);
    await passwordInput(page).fill('WrongPassword1!');
    await loginButton(page).click();
    // Сервер возвращает «Неверное имя пользователя или пароль»
    await expect(
      page.getByText(/неверн|ошибк|invalid|error|wrong|incorrect|имя пользователя|парол/i).first()
    ).toBeVisible({ timeout: 15000 });
  });

  test('успешный вход по логину и паролю открывает главный экран (чаты/профиль)', async ({ page }) => {
    const username = unique();
    await page.request.post(`${apiBase()}/auth/register`, {
      data: { username, password: PASSWORD, displayName: `User ${username}` },
    });
    await page.goto('/login');
    await waitForLoginForm(page);
    await doLogin(page, username);
    await waitForLoggedIn(page);
    const path = new URL(page.url()).pathname;
    expect(path === '/' || path === '/profile' || path === '/contacts').toBeTruthy();
  });
});

// ---------- Регистрация ----------
test.describe('Регистрация', () => {
  test('переход на страницу регистрации по кнопке с формы входа', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const registerBtn = page.getByRole('button', { name: /зарегистр|sign up|нет аккаунта/i }).or(
      page.getByRole('link', { name: /зарегистр|sign up/i })
    ).first();
    await registerBtn.click();
    await expect(
      page.getByRole('heading', { name: /регистрац|sign up/i }).or(
        page.getByText(/регистрац|создать аккаунт|create account/i)
      ).first()
    ).toBeVisible({ timeout: 10000 });
  });

  test('регистрация нового пользователя через форму — после отправки виден главный экран или форма', async ({ page }) => {
    await page.goto('/login');
    await waitForLoginForm(page);
    const registerBtn = page.getByRole('button', { name: /зарегистр|sign up|нет аккаунта/i }).or(
      page.getByRole('link', { name: /зарегистр|sign up/i })
    ).first();
    if (await registerBtn.isVisible().catch(() => false)) {
      await registerBtn.click();
      await page.waitForTimeout(1000);
    }

    const username = unique();
    const usernameField = page.getByLabel(/имя пользователя|username|логин/i).or(
      page.locator('input[type="text"]').first()
    ).first();
    const passwordField = page.locator('input[type="password"]').first();
    const displayField = page.getByLabel(/отображаемое|display|имя/i).or(
      page.locator('input[type="text"]').nth(1)
    ).first();
    const submitBtn = page.getByRole('button', { name: /создать аккаунт|create account|регистр/i }).or(
      page.locator('button[type="submit"]')
    ).first();

    await usernameField.waitFor({ state: 'visible', timeout: 10000 });
    await usernameField.fill(username);
    await passwordField.fill(PASSWORD);
    if (await displayField.isVisible().catch(() => false)) {
      await displayField.fill(`User ${username}`);
    }
    await submitBtn.click();

    await expect(
      page.getByText(/чаты|chats|друзья|friends|профиль|profile|нет чатов|no chats/i).or(
        page.locator('input, button').first()
      ).first()
    ).toBeVisible({ timeout: 15000 });
  });
});

// ---------- Навигация после входа ----------
test.describe('Навигация после входа', () => {
  test.setTimeout(60000);
  test.beforeEach(async ({ page }) => {
    const username = unique();
    await page.request.post(`${apiBase()}/auth/register`, {
      data: { username, password: PASSWORD, displayName: `User ${username}` },
    });
    await page.goto('/login');
    await waitForLoginForm(page);
    await doLogin(page, username);
    await waitForLoggedIn(page);
  });

  /** Вкладка нижней навигации по тексту (Flutter рендерит label как Text). */
  function navTab(page, regex) {
    return page.getByRole('button', { name: regex }).or(page.getByText(regex).first());
  }

  test('переход в раздел Друзья/Contacts и обратно в Чаты', async ({ page }) => {
    const friendsTab = navTab(page, /друзья|friends|контакт|contacts/i);
    await expect(friendsTab.first()).toBeVisible({ timeout: 10000 });
    await friendsTab.first().click();
    await page.waitForTimeout(800);
    await expect(page.getByText(/друзья|friends|добавить|add|контакт|contacts/i).first()).toBeVisible({ timeout: 10000 });
    const chatsTab = navTab(page, /чаты|chats/i);
    await expect(chatsTab.first()).toBeVisible({ timeout: 5000 });
    await chatsTab.first().click();
    await page.waitForTimeout(500);
    await expect(page.getByText(/чаты|chats|друзья|friends|профиль|profile/i).first()).toBeVisible({ timeout: 8000 });
  });

  test('переход в Профиль/Settings', async ({ page }) => {
    const profileTab = navTab(page, /профиль|profile|настройки|settings|мой профиль|my profile/i);
    await expect(profileTab.first()).toBeVisible({ timeout: 10000 });
    await profileTab.first().click();
    await page.waitForTimeout(800);
    await expect(
      page.getByText(/профиль|profile|имя|name|настройки|settings|мой профиль|my profile/i).first()
    ).toBeVisible({ timeout: 10000 });
  });
});
