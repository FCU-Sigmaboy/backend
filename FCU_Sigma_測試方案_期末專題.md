# FCU Sigma 生態交換平台 - 軟體測試方案

> 📚 **逢甲大學資訊工程系 軟體測試課程 期末專題報告**  
> 📅 版本: v1.0 | 2025 年  
> 🎯 專案: FCU Sigma 二手交易平台

---

## 📋 目錄

1. [專案概述](#1-專案概述)
2. [測試策略與架構](#2-測試策略與架構)
3. [測試環境設置](#3-測試環境設置)
4. [資料庫層測試 (pgTAP)](#4-資料庫層測試-pgtap)
5. [前端單元測試 (Vitest)](#5-前端單元測試-vitest)
6. [整合測試 (Supabase Local)](#6-整合測試-supabase-local)
7. [端對端測試 (Playwright)](#7-端對端測試-playwright)
8. [CI/CD 自動化測試](#8-cicd-自動化測試)
9. [測試案例總表](#9-測試案例總表)
10. [簡報大綱與投影片建議](#10-簡報大綱與投影片建議)
11. [附錄](#11-附錄)

---

## 1. 專案概述

### 1.1 系統簡介

**FCU Sigma** 是一個基於 Supabase 的校園二手交易平台，提供完整的 C2C（Consumer-to-Consumer）交易功能。

### 1.2 核心功能模組

| 模組 | 說明 | 關鍵技術 |
|------|------|----------|
| 🔐 **使用者認證** | OAuth 登入、Session 管理 | Supabase Auth |
| 🛍️ **物品管理** | 刊登、編輯、上下架、搜尋 | PostgreSQL RPC + PostGIS |
| 💬 **即時訊息** | 買賣雙方聊天、已讀狀態 | Supabase Realtime |
| 🤝 **交易系統** | 確認碼驗證、點數結算 | 狀態機、原子操作 |
| 🎯 **每日簽到** | 連續獎勵、徽章解鎖 | 觸發器、時區處理 |
| 🏆 **徽章系統** | 成就追蹤、進度顯示 | 觸發器、JSONB |
| 👥 **社交功能** | 追蹤、收藏、評價 | RLS 政策 |
| 🤖 **AI 分析** | 物品圖片智慧辨識 | Edge Functions + Gemini |

### 1.3 技術架構

```
┌─────────────────────────────────────────────────────────────┐
│                      前端 (Vue.js / Quasar)                  │
├─────────────────────────────────────────────────────────────┤
│                     Supabase Client SDK                      │
├──────────────┬──────────────┬──────────────┬────────────────┤
│   Auth       │   Database   │   Realtime   │ Edge Functions │
│   認證服務    │   PostgreSQL │   即時推播    │   無伺服器函數  │
├──────────────┴──────────────┴──────────────┴────────────────┤
│                  Row Level Security (RLS)                    │
│                  資料列層級安全策略                            │
└─────────────────────────────────────────────────────────────┘
```

### 1.4 為什麼選擇這套測試策略？

由於 FCU Sigma 的**業務邏輯主要在 Supabase（PostgreSQL）中實現**，而非傳統的後端程式碼，因此我們的測試策略需要特別調整：

| 傳統架構 | Supabase 架構 | 測試策略調整 |
|----------|---------------|--------------|
| 後端 API 測試 | 資料庫 RPC 測試 | 使用 **pgTAP** 測試 SQL 函數 |
| 權限中間件測試 | RLS 政策測試 | 模擬不同角色存取資料 |
| 單元測試 | 觸發器測試 | 驗證自動化資料變更 |
| 整合測試 | Local Supabase | 真實環境完整測試 |

---

## 2. 測試策略與架構

### 2.1 測試金字塔（針對 Supabase 專案優化）

```
                    ╱╲
                   ╱  ╲
                  ╱ E2E ╲          ← 完整使用者流程
                 ╱ (10%) ╲            Playwright
                ╱──────────╲
               ╱  整合測試   ╲       ← Supabase Local + Vitest
              ╱    (25%)     ╲         真實 RLS/RPC 驗證
             ╱────────────────╲
            ╱   資料庫單元測試   ╲    ← pgTAP (最重要！)
           ╱      (40%)         ╲       RLS、觸發器、RPC 函數
          ╱──────────────────────╲
         ╱    前端元件單元測試     ╲  ← Vitest + Mock
        ╱         (25%)           ╲     UI 邏輯驗證
       ╱────────────────────────────╲
```

### 2.2 測試優先順序矩陣

| 優先級 | 測試類型 | 涵蓋範圍 | 工具 | 執行頻率 |
|:------:|----------|----------|------|----------|
| 🔴 **P0** | RLS 政策測試 | 權限隔離、資料保護 | pgTAP | 每次 Commit |
| 🔴 **P0** | 交易流程測試 | 狀態機、點數結算 | pgTAP + Integration | 每次 Commit |
| 🟡 **P1** | RPC 函數測試 | 搜尋、簽到、徽章 | pgTAP | 每次 Commit |
| 🟡 **P1** | 觸發器測試 | 自動更新、級聯操作 | pgTAP | 每次 PR |
| 🟢 **P2** | 前端元件測試 | UI 邏輯、狀態管理 | Vitest | 開發時持續 |
| 🟢 **P2** | E2E 流程測試 | 完整使用者旅程 | Playwright | 部署前 |

### 2.3 測試涵蓋範圍規劃

```
FCU Sigma 功能模組測試涵蓋率目標
============================================================

資料庫層 (pgTAP)
├── RLS 政策 ▓▓▓▓▓▓▓▓▓▓ 100% (安全性關鍵)
├── RPC 函數 ▓▓▓▓▓▓▓▓░░  80%
├── 觸發器   ▓▓▓▓▓▓▓░░░  70%
└── 約束條件 ▓▓▓▓▓▓░░░░  60%

前端元件 (Vitest)
├── 認證流程 ▓▓▓▓▓▓▓▓░░  80%
├── 狀態管理 ▓▓▓▓▓▓▓░░░  70%
├── API 呼叫 ▓▓▓▓▓▓▓░░░  70%
└── UI 元件  ▓▓▓▓▓░░░░░  50%

E2E 測試 (Playwright)
├── 核心流程 ▓▓▓▓▓▓▓▓▓▓ 100%
├── 錯誤處理 ▓▓▓▓▓▓░░░░  60%
└── 邊界案例 ▓▓▓▓░░░░░░  40%
```

---

## 3. 測試環境設置

### 3.1 前置需求

```bash
# 必要軟體
- Docker Desktop 或 OrbStack (macOS 建議使用 OrbStack)
- Node.js 18+
- npm 或 yarn
- Git
```

### 3.2 安裝測試依賴

```bash
# 進入專案目錄
cd backend

# 安裝主要依賴
npm install

# 安裝測試框架
npm install -D vitest @vitest/ui @vitest/coverage-v8
npm install -D @vue/test-utils @testing-library/vue
npm install -D @playwright/test
npm install -D msw  # Mock Service Worker

# 啟動本地 Supabase
npx supabase start

# 重置資料庫（包含遷移和測試資料）
npx supabase db reset
```

### 3.3 專案測試目錄結構

```
backend/
├── supabase/
│   ├── tests/                          # 資料庫測試
│   │   ├── database/                   # pgTAP 測試檔案
│   │   │   ├── 00_test_helpers.sql     # 測試輔助函數
│   │   │   ├── 01_rls_users.test.sql   # 使用者 RLS 測試
│   │   │   ├── 02_rls_items.test.sql   # 物品 RLS 測試
│   │   │   ├── 03_rpc_transactions.test.sql
│   │   │   ├── 04_rpc_daily_signin.test.sql
│   │   │   ├── 05_rpc_badges.test.sql
│   │   │   ├── 06_triggers.test.sql
│   │   │   └── 07_messaging.test.sql
│   │   └── seed.sql                    # 測試資料種子
│   └── migrations/                     # 資料庫遷移
│
├── tests/                              # 前端測試
│   ├── unit/                           # 單元測試
│   │   ├── components/                 # 元件測試
│   │   ├── composables/                # 組合函數測試
│   │   └── stores/                     # Pinia Store 測試
│   ├── integration/                    # 整合測試
│   │   ├── auth.integration.test.ts
│   │   ├── items.integration.test.ts
│   │   └── transactions.integration.test.ts
│   ├── e2e/                            # E2E 測試
│   │   ├── auth.setup.ts               # 認證設定
│   │   ├── purchase-flow.spec.ts       # 購買流程
│   │   └── seller-flow.spec.ts         # 賣家流程
│   └── mocks/                          # Mock 檔案
│       ├── supabase.ts                 # Supabase Mock
│       └── handlers.ts                 # MSW Handlers
│
├── vitest.config.ts                    # Vitest 配置
├── playwright.config.ts                # Playwright 配置
└── package.json                        # 測試腳本
```

### 3.4 配置檔案

#### vitest.config.ts

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';
import path from 'path';

export default defineConfig({
  plugins: [vue()],
  test: {
    globals: true,
    environment: 'jsdom',
    include: ['tests/**/*.{test,spec}.{ts,js}'],
    exclude: ['tests/e2e/**'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'lcov'],
      include: ['src/**/*.{ts,vue}'],
      exclude: ['src/**/*.d.ts']
    },
    setupFiles: ['tests/setup.ts']
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      'src': path.resolve(__dirname, './src')
    }
  }
});
```

#### playwright.config.ts

```typescript
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html', { outputFolder: 'playwright-report' }],
    ['list']
  ],
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure'
  },
  projects: [
    // 認證設置（在其他測試前執行）
    { name: 'setup', testMatch: /.*\.setup\.ts/ },
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
      dependencies: ['setup']
    }
  ],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI
  }
});
```

#### package.json 測試腳本

```json
{
  "scripts": {
    "test": "vitest",
    "test:ui": "vitest --ui",
    "test:coverage": "vitest run --coverage",
    "test:unit": "vitest run tests/unit",
    "test:integration": "vitest run tests/integration",
    "test:db": "npx supabase test db",
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui",
    "test:all": "npm run test:db && npm run test:unit && npm run test:integration && npm run test:e2e"
  }
}
```

---

## 4. 資料庫層測試 (pgTAP)

### 4.1 pgTAP 簡介

**pgTAP** 是 PostgreSQL 的 TAP（Test Anything Protocol）測試框架，是 Supabase 內建的官方測試工具。

**為什麼使用 pgTAP？**
- ✅ 直接在資料庫層面測試 SQL 函數
- ✅ 完整驗證 RLS（Row Level Security）政策
- ✅ 測試觸發器和約束條件
- ✅ Supabase CLI 原生支援

### 4.2 測試輔助函數

```sql
-- supabase/tests/database/00_test_helpers.sql
-- =============================================
-- FCU Sigma 測試輔助函數
-- =============================================

-- 建立測試用戶輔助函數
CREATE OR REPLACE FUNCTION tests.create_test_user(
  p_user_id UUID,
  p_nickname TEXT DEFAULT 'TestUser'
)
RETURNS UUID AS $$
BEGIN
  -- 插入 auth.users（模擬 Supabase Auth）
  INSERT INTO auth.users (id, email, created_at, updated_at)
  VALUES (
    p_user_id,
    p_nickname || '@test.fcu.edu.tw',
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;
  
  -- 插入 public.users
  INSERT INTO public.users (id, nickname, created_at, updated_at)
  VALUES (p_user_id, p_nickname, now(), now())
  ON CONFLICT (id) DO NOTHING;
  
  -- 插入 public.profiles
  INSERT INTO public.profiles (user_id, balance, carbon_saved_kg)
  VALUES (p_user_id, 10000, 0.00)
  ON CONFLICT (user_id) DO NOTHING;
  
  RETURN p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 模擬用戶登入
CREATE OR REPLACE FUNCTION tests.authenticate_as(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
  -- 設定 JWT claims 模擬已認證用戶
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'aud', 'authenticated'
    )::text,
    true
  );
  
  -- 設定當前角色為 authenticated
  PERFORM set_config('role', 'authenticated', true);
END;
$$ LANGUAGE plpgsql;

-- 清除認證狀態
CREATE OR REPLACE FUNCTION tests.clear_authentication()
RETURNS VOID AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
END;
$$ LANGUAGE plpgsql;

-- 取得測試用戶 ID
CREATE OR REPLACE FUNCTION tests.get_user_id(p_nickname TEXT)
RETURNS UUID AS $$
  SELECT id FROM public.users WHERE nickname = p_nickname LIMIT 1;
$$ LANGUAGE sql;

-- 清理測試資料
CREATE OR REPLACE FUNCTION tests.cleanup_test_data()
RETURNS VOID AS $$
BEGIN
  DELETE FROM public.transactions WHERE true;
  DELETE FROM public.items WHERE true;
  DELETE FROM public.locations WHERE true;
  DELETE FROM public.profiles WHERE true;
  DELETE FROM public.users WHERE true;
  DELETE FROM auth.users WHERE true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 4.3 RLS 政策測試

```sql
-- supabase/tests/database/01_rls_users.test.sql
-- =============================================
-- 使用者 RLS 政策測試
-- =============================================

BEGIN;
SELECT plan(10);

-- =========== 測試準備 ===========

-- 建立測試用戶
SELECT tests.create_test_user(
  '11111111-1111-1111-1111-111111111111'::UUID,
  'Seller_A'
);
SELECT tests.create_test_user(
  '22222222-2222-2222-2222-222222222222'::UUID,
  'Buyer_B'
);

-- =========== 測試案例 ===========

-- 測試 1: 已登入用戶可以查看其他用戶的公開資訊
SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

SELECT ok(
  EXISTS(SELECT 1 FROM public.users WHERE nickname = 'Buyer_B'),
  '已登入用戶可以查看其他用戶的公開資訊'
);

-- 測試 2: 可以查詢到 nickname 欄位
SELECT is(
  (SELECT nickname FROM public.users WHERE id = '22222222-2222-2222-2222-222222222222'::UUID),
  'Buyer_B',
  '可以正確查詢到其他用戶的 nickname'
);

-- 測試 3: 用戶只能更新自己的 nickname
UPDATE public.users SET nickname = 'Seller_A_Updated' 
WHERE id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT is(
  (SELECT nickname FROM public.users WHERE id = '11111111-1111-1111-1111-111111111111'::UUID),
  'Seller_A_Updated',
  '用戶可以更新自己的 nickname'
);

-- 測試 4: 用戶不能更新其他人的 nickname
UPDATE public.users SET nickname = 'Hacked!' 
WHERE id = '22222222-2222-2222-2222-222222222222'::UUID;

SELECT is(
  (SELECT nickname FROM public.users WHERE id = '22222222-2222-2222-2222-222222222222'::UUID),
  'Buyer_B',
  '用戶不能更新其他人的 nickname（RLS 阻止）'
);

-- 測試 5: 用戶不能修改 avg_rating
UPDATE public.users SET avg_rating = 5.0 
WHERE id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT is(
  (SELECT avg_rating FROM public.users WHERE id = '11111111-1111-1111-1111-111111111111'::UUID),
  0.00::NUMERIC(3,2),
  '用戶不能直接修改 avg_rating（應由系統計算）'
);

-- 測試 6: 用戶不能直接插入新用戶
SELECT throws_ok(
  $$ INSERT INTO public.users (id, nickname) VALUES (gen_random_uuid(), 'NewUser') $$,
  NULL,
  '用戶不能直接插入新用戶記錄'
);

-- 測試 7: 用戶不能刪除自己的記錄
DELETE FROM public.users WHERE id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT ok(
  EXISTS(SELECT 1 FROM public.users WHERE id = '11111111-1111-1111-1111-111111111111'::UUID),
  '用戶不能刪除自己的記錄'
);

-- 測試 8: 匿名用戶無法查看資料
SELECT tests.clear_authentication();

SELECT is(
  (SELECT COUNT(*) FROM public.users)::INTEGER,
  0,
  '匿名用戶無法查看任何用戶資料'
);

-- =========== 測試 profiles 表 RLS ===========

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

-- 測試 9: 用戶只能查看自己的 profile
SELECT ok(
  (SELECT COUNT(*) FROM public.profiles WHERE user_id = auth.uid()) = 1,
  '用戶可以查看自己的 profile'
);

-- 測試 10: 用戶無法查看他人的 profile
SELECT is(
  (SELECT balance FROM public.profiles WHERE user_id = '22222222-2222-2222-2222-222222222222'::UUID),
  NULL,
  '用戶無法查看他人的 profile（RLS 阻止）'
);

SELECT * FROM finish();
ROLLBACK;
```

### 4.4 物品 RLS 測試

```sql
-- supabase/tests/database/02_rls_items.test.sql
-- =============================================
-- 物品 RLS 政策測試
-- =============================================

BEGIN;
SELECT plan(12);

-- =========== 測試準備 ===========

SELECT tests.create_test_user('11111111-1111-1111-1111-111111111111'::UUID, 'Seller_A');
SELECT tests.create_test_user('22222222-2222-2222-2222-222222222222'::UUID, 'Seller_B');
SELECT tests.create_test_user('33333333-3333-3333-3333-333333333333'::UUID, 'Buyer_C');

-- 建立測試地點
INSERT INTO public.locations (user_id, coordinates, type, is_primary, formatted_address)
VALUES 
  ('11111111-1111-1111-1111-111111111111'::UUID, 
   ST_SetSRID(ST_MakePoint(120.6478, 24.1797), 4326), '公司', true, '台中市西屯區文華路100號'),
  ('22222222-2222-2222-2222-222222222222'::UUID,
   ST_SetSRID(ST_MakePoint(120.6500, 24.1800), 4326), '家', true, '台中市西屯區福星路200號');

-- 建立測試物品（使用 SECURITY DEFINER 繞過 RLS）
INSERT INTO public.items (id, user_id, sub_category_id, title, description, condition, price, listing_status)
VALUES 
  (1001, '11111111-1111-1111-1111-111111111111'::UUID, 1, 'iPhone 15', '九成新', '近全新', 20000, true),
  (1002, '11111111-1111-1111-1111-111111111111'::UUID, 1, '私人筆記', '草稿', '普通', 100, false),
  (1003, '22222222-2222-2222-2222-222222222222'::UUID, 2, 'Nike 運動鞋', '穿過幾次', '良好', 1500, true);

-- =========== 測試案例 ===========

-- 測試 1: 任何已登入用戶可以看到已上架物品
SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333'::UUID);

SELECT is(
  (SELECT COUNT(*) FROM public.items WHERE listing_status = true)::INTEGER,
  2,
  '買家可以看到所有已上架物品'
);

-- 測試 2: 無法看到未上架物品
SELECT ok(
  NOT EXISTS(SELECT 1 FROM public.items WHERE title = '私人筆記'),
  '買家無法看到未上架物品'
);

-- 測試 3: 賣家可以看到自己的所有物品（包含未上架）
SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

SELECT is(
  (SELECT COUNT(*) FROM public.items WHERE user_id = auth.uid())::INTEGER,
  2,
  '賣家可以看到自己的所有物品'
);

-- 測試 4: 賣家可以更新自己的物品
UPDATE public.items SET price = 18000 WHERE id = 1001;

SELECT is(
  (SELECT price FROM public.items WHERE id = 1001),
  18000,
  '賣家可以更新自己物品的價格'
);

-- 測試 5: 賣家無法更新他人的物品
UPDATE public.items SET price = 500 WHERE id = 1003;

SELECT is(
  (SELECT price FROM public.items WHERE id = 1003),
  1500,
  '賣家無法更新他人物品的價格（RLS 阻止）'
);

-- 測試 6: 賣家可以刪除自己的物品
DELETE FROM public.items WHERE id = 1002;

SELECT ok(
  NOT EXISTS(SELECT 1 FROM public.items WHERE id = 1002),
  '賣家可以刪除自己的物品'
);

-- 測試 7: 賣家無法刪除他人的物品
DELETE FROM public.items WHERE id = 1003;

SELECT ok(
  EXISTS(SELECT 1 FROM public.items WHERE id = 1003),
  '賣家無法刪除他人的物品（RLS 阻止）'
);

-- 測試 8: 賣家可以新增自己的物品
INSERT INTO public.items (id, user_id, sub_category_id, title, condition, price, listing_status)
VALUES (1004, '11111111-1111-1111-1111-111111111111'::UUID, 1, '新物品', '全新', 5000, true);

SELECT ok(
  EXISTS(SELECT 1 FROM public.items WHERE id = 1004),
  '賣家可以新增自己的物品'
);

-- 測試 9: 無法為他人新增物品
SELECT throws_ok(
  $$ INSERT INTO public.items (user_id, sub_category_id, title, condition, price)
     VALUES ('22222222-2222-2222-2222-222222222222'::UUID, 1, '偽造物品', '全新', 1000) $$,
  NULL,
  '無法為他人新增物品（RLS 阻止）'
);

-- 測試 10: 匿名用戶無法看到任何物品
SELECT tests.clear_authentication();

SELECT is(
  (SELECT COUNT(*) FROM public.items)::INTEGER,
  0,
  '匿名用戶無法看到任何物品'
);

-- 測試 11: 匿名用戶無法新增物品
SELECT throws_ok(
  $$ INSERT INTO public.items (user_id, sub_category_id, title, condition, price)
     VALUES (gen_random_uuid(), 1, '匿名物品', '全新', 1000) $$,
  NULL,
  '匿名用戶無法新增物品'
);

-- 測試 12: 驗證物品搜尋結果包含距離資訊
SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333'::UUID);

-- 先為買家設定位置
INSERT INTO public.locations (user_id, coordinates, type, is_primary, formatted_address)
VALUES ('33333333-3333-3333-3333-333333333333'::UUID, 
        ST_SetSRID(ST_MakePoint(120.6480, 24.1795), 4326), '家', true, '台中市西屯區文華路50號');

SELECT ok(
  (SELECT COUNT(*) FROM search_items(null, null, null, null, null, 1, 10, 'created_at', 'desc') 
   WHERE distance_km IS NOT NULL) > 0,
  '物品搜尋結果包含距離資訊'
);

SELECT * FROM finish();
ROLLBACK;
```

### 4.5 交易系統 RPC 測試

```sql
-- supabase/tests/database/03_rpc_transactions.test.sql
-- =============================================
-- 交易系統 RPC 函數測試
-- =============================================

BEGIN;
SELECT plan(15);

-- =========== 測試準備 ===========

-- 建立測試用戶
SELECT tests.create_test_user('11111111-1111-1111-1111-111111111111'::UUID, 'Seller');
SELECT tests.create_test_user('22222222-2222-2222-2222-222222222222'::UUID, 'Buyer');

-- 設定買家餘額
UPDATE public.profiles SET balance = 5000 
WHERE user_id = '22222222-2222-2222-2222-222222222222'::UUID;

-- 建立測試地點
INSERT INTO public.locations (user_id, coordinates, type, is_primary, formatted_address)
VALUES ('11111111-1111-1111-1111-111111111111'::UUID,
        ST_SetSRID(ST_MakePoint(120.6478, 24.1797), 4326), '公司', true, '逢甲大學');

-- 建立測試物品
INSERT INTO public.items (id, user_id, sub_category_id, title, condition, price, listing_status, carbon_value)
VALUES (2001, '11111111-1111-1111-1111-111111111111'::UUID, 1, '測試商品', '良好', 1000, true, 2.5);

-- =========== 測試案例 ===========

-- 測試 1: 賣家可以發起交易
SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

SELECT ok(
  (SELECT (initiate_transaction(2001, '22222222-2222-2222-2222-222222222222'::UUID))->>'status') = 'confirming',
  '賣家成功發起交易，狀態為 confirming'
);

-- 測試 2: 交易生成 6 位數確認碼
SELECT is(
  LENGTH((SELECT code FROM public.transactions WHERE item_id = 2001)),
  6,
  '交易生成 6 位數確認碼'
);

-- 測試 3: 物品自動下架
SELECT is(
  (SELECT listing_status FROM public.items WHERE id = 2001),
  false,
  '發起交易後物品自動下架'
);

-- 測試 4: 賣家可以查詢確認中的交易
SELECT ok(
  (SELECT COUNT(*) FROM get_my_transactions_by_status('confirming', 'giver')) > 0,
  '賣家可以查詢確認中的交易'
);

-- 測試 5: 賣家可以更新備註
SELECT ok(
  (SELECT (update_giver_note(
    (SELECT id FROM public.transactions WHERE item_id = 2001),
    '請在校門口等我'
  ))->>'success')::BOOLEAN,
  '賣家可以更新備註'
);

-- 測試 6: 買家可以查詢確認中的交易
SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222'::UUID);

SELECT ok(
  (SELECT COUNT(*) FROM get_my_transactions_by_status('confirming', 'receiver')) > 0,
  '買家可以查詢確認中的交易'
);

-- 測試 7: 買家確認交易，狀態變為 pending
SELECT is(
  (SELECT (buyer_confirm_transaction(
    (SELECT id FROM public.transactions WHERE item_id = 2001),
    '好的，我會準時到'
  ))->>'new_status'),
  'pending',
  '買家確認後，交易狀態變為 pending'
);

-- 測試 8: 買家輸入正確確認碼完成交易
DECLARE
  v_code TEXT;
  v_result JSONB;
BEGIN
  SELECT code INTO v_code FROM public.transactions WHERE item_id = 2001;
  SELECT complete_transaction(
    (SELECT id FROM public.transactions WHERE item_id = 2001),
    v_code
  ) INTO v_result;
  
  PERFORM ok(
    (v_result->>'success')::BOOLEAN,
    '買家輸入正確確認碼完成交易'
  );
END;

-- 測試 9: 交易完成後點數正確轉移
SELECT is(
  (SELECT balance FROM public.profiles WHERE user_id = '22222222-2222-2222-2222-222222222222'::UUID),
  4000,  -- 5000 - 1000
  '買家點數正確扣除'
);

-- 測試 10: 賣家收到點數
SELECT is(
  (SELECT balance FROM public.profiles WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID),
  11000,  -- 10000 + 1000
  '賣家正確收到點數'
);

-- 測試 11: 碳足跡正確累計
SELECT ok(
  (SELECT carbon_saved_kg FROM public.profiles WHERE user_id = '22222222-2222-2222-2222-222222222222'::UUID) = 2.5,
  '買家碳足跡正確累計'
);

-- =========== 錯誤處理測試 ===========

-- 重新建立測試環境
INSERT INTO public.items (id, user_id, sub_category_id, title, condition, price, listing_status)
VALUES (2002, '11111111-1111-1111-1111-111111111111'::UUID, 1, '測試商品2', '良好', 1000, true);

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

-- 測試 12: 賣家不能對自己的商品發起交易
SELECT throws_ok(
  $$ SELECT initiate_transaction(2002, '11111111-1111-1111-1111-111111111111'::UUID) $$,
  NULL,
  '賣家不能對自己發起交易'
);

-- 測試 13: 買家餘額不足時無法完成交易
UPDATE public.profiles SET balance = 100 
WHERE user_id = '22222222-2222-2222-2222-222222222222'::UUID;

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);
SELECT initiate_transaction(2002, '22222222-2222-2222-2222-222222222222'::UUID);

SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222'::UUID);

SELECT throws_ok(
  $$ SELECT buyer_confirm_transaction(
       (SELECT id FROM public.transactions WHERE item_id = 2002),
       '確認購買'
     ) $$,
  'INSUFFICIENT_BALANCE',
  '買家餘額不足時無法確認交易'
);

-- 測試 14: 取消交易後物品重新上架
SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

SELECT cancel_transaction((SELECT id FROM public.transactions WHERE item_id = 2002));

SELECT is(
  (SELECT listing_status FROM public.items WHERE id = 2002),
  true,
  '取消交易後物品重新上架'
);

-- 測試 15: 已完成/取消的交易不能再操作
SELECT throws_ok(
  $$ SELECT cancel_transaction(
       (SELECT id FROM public.transactions WHERE item_id = 2001)
     ) $$,
  NULL,
  '已完成的交易不能再取消'
);

SELECT * FROM finish();
ROLLBACK;
```

### 4.6 每日簽到 RPC 測試

```sql
-- supabase/tests/database/04_rpc_daily_signin.test.sql
-- =============================================
-- 每日簽到系統 RPC 測試
-- =============================================

BEGIN;
SELECT plan(12);

-- =========== 測試準備 ===========

SELECT tests.create_test_user('11111111-1111-1111-1111-111111111111'::UUID, 'TestUser');
SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

-- =========== 測試案例 ===========

-- 測試 1: 首次簽到成功
SELECT ok(
  (SELECT (daily_check_in())->>'success')::BOOLEAN,
  '首次簽到成功'
);

-- 測試 2: 首次簽到獲得 5 點
SELECT is(
  (SELECT (daily_check_in())->>'points_awarded')::INTEGER,
  5,
  '首次簽到獲得 5 點'
);

-- 模擬已經簽到過
UPDATE public.profiles 
SET last_check_in_date = CURRENT_DATE AT TIME ZONE 'Asia/Taipei'
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- 測試 3: 今天已簽到過不能重複簽到
SELECT is(
  (SELECT (daily_check_in())->>'success')::BOOLEAN,
  false,
  '今天已簽到過不能重複簽到'
);

-- 測試 4: 重複簽到返回正確訊息
SELECT ok(
  (SELECT (daily_check_in())->>'message') LIKE '%已經簽到%',
  '重複簽到返回正確訊息'
);

-- 模擬連續簽到情境
UPDATE public.profiles SET 
  last_check_in_date = (CURRENT_DATE AT TIME ZONE 'Asia/Taipei') - INTERVAL '1 day',
  check_in_streak = 2
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- 測試 5: 連續第 3 天簽到獲得額外獎勵
SELECT is(
  (SELECT (daily_check_in())->>'points_awarded')::INTEGER,
  10,
  '連續第 3 天簽到獲得 10 點'
);

-- 測試 6: 連續天數正確更新
SELECT is(
  (SELECT check_in_streak FROM public.profiles 
   WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID),
  3,
  '連續天數正確更新為 3'
);

-- 模擬中斷後重新簽到
UPDATE public.profiles SET 
  last_check_in_date = (CURRENT_DATE AT TIME ZONE 'Asia/Taipei') - INTERVAL '3 day',
  check_in_streak = 10
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- 測試 7: 中斷後連續天數重置
SELECT daily_check_in();

SELECT is(
  (SELECT check_in_streak FROM public.profiles 
   WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID),
  1,
  '中斷後連續天數重置為 1'
);

-- 測試 8: 連續 7 天里程碑獎勵
UPDATE public.profiles SET 
  last_check_in_date = (CURRENT_DATE AT TIME ZONE 'Asia/Taipei') - INTERVAL '1 day',
  check_in_streak = 6
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT is(
  (SELECT (daily_check_in())->>'points_awarded')::INTEGER,
  20,
  '連續第 7 天簽到獲得 20 點'
);

-- 測試 9: 連續 14 天里程碑獎勵
UPDATE public.profiles SET 
  last_check_in_date = (CURRENT_DATE AT TIME ZONE 'Asia/Taipei') - INTERVAL '1 day',
  check_in_streak = 13
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT is(
  (SELECT (daily_check_in())->>'points_awarded')::INTEGER,
  30,
  '連續第 14 天簽到獲得 30 點'
);

-- 測試 10: 簽到結果包含徽章資訊
UPDATE public.profiles SET 
  last_check_in_date = (CURRENT_DATE AT TIME ZONE 'Asia/Taipei') - INTERVAL '1 day',
  check_in_streak = 6
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT ok(
  (SELECT (daily_check_in())->'badges' IS NOT NULL),
  '簽到結果包含徽章資訊'
);

-- 測試 11: 點數餘額正確累計
SELECT ok(
  (SELECT balance FROM public.profiles 
   WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID) > 10000,
  '簽到獲得的點數正確累計到餘額'
);

-- 測試 12: 簽到記錄寫入 point_logs
SELECT ok(
  EXISTS(
    SELECT 1 FROM public.point_logs 
    WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID
    AND reason LIKE '%簽到%'
  ),
  '簽到記錄正確寫入 point_logs'
);

SELECT * FROM finish();
ROLLBACK;
```

### 4.7 徽章系統測試

```sql
-- supabase/tests/database/05_rpc_badges.test.sql
-- =============================================
-- 徽章系統 RPC 測試
-- =============================================

BEGIN;
SELECT plan(10);

-- =========== 測試準備 ===========

SELECT tests.create_test_user('11111111-1111-1111-1111-111111111111'::UUID, 'BadgeUser');
SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

-- =========== 測試案例 ===========

-- 測試 1: 取得使用者徽章資訊結構正確
SELECT ok(
  (SELECT (get_user_badges_with_progress(null))->>'user_id' IS NOT NULL),
  '取得徽章資訊包含 user_id'
);

-- 測試 2: 新用戶沒有已獲得徽章
SELECT ok(
  (SELECT jsonb_array_length((get_user_badges_with_progress(null))->'earned_badges')) = 0,
  '新用戶沒有已獲得徽章'
);

-- 測試 3: 有進行中的徽章
SELECT ok(
  (SELECT jsonb_array_length((get_user_badges_with_progress(null))->'in_progress_badges')) > 0,
  '新用戶有進行中的徽章'
);

-- 測試 4: 進行中徽章包含進度資訊
SELECT ok(
  (SELECT ((get_user_badges_with_progress(null))->'in_progress_badges'->0)->>'percentage' IS NOT NULL),
  '進行中徽章包含百分比進度'
);

-- 模擬達成連續簽到 7 天
UPDATE public.profiles SET check_in_streak = 7
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- 測試 5: 手動檢查徽章會觸發授予
SELECT ok(
  ((SELECT manually_check_badges())->>'newly_earned_count')::INTEGER >= 0,
  '手動檢查徽章功能正常'
);

-- 測試 6: 獲得徽章後自動發放點數獎勵
-- (假設連續簽到 7 天徽章獎勵 50 點)
SELECT ok(
  (SELECT balance FROM public.profiles WHERE user_id = auth.uid()) >= 10000,
  '獲得徽章後點數獎勵正確發放'
);

-- 測試 7: 已獲得徽章不會重複授予
DECLARE
  v_first_check JSONB;
  v_second_check JSONB;
BEGIN
  SELECT manually_check_badges() INTO v_first_check;
  SELECT manually_check_badges() INTO v_second_check;
  
  PERFORM ok(
    (v_second_check->>'newly_earned_count')::INTEGER = 0,
    '已獲得徽章不會重複授予'
  );
END;

-- 測試 8: 可以查看其他用戶的徽章
SELECT tests.create_test_user('22222222-2222-2222-2222-222222222222'::UUID, 'OtherUser');

SELECT ok(
  (SELECT (get_user_badges_with_progress('22222222-2222-2222-2222-222222222222'::UUID))->>'user_id' IS NOT NULL),
  '可以查看其他用戶的徽章'
);

-- 測試 9: 徽章類別正確
SELECT ok(
  (SELECT ((get_user_badges_with_progress(null))->'in_progress_badges'->0)->>'category' 
   IN ('streak', 'transaction', 'points', 'carbon', 'seasonal')),
  '徽章類別為有效值'
);

-- 測試 10: 徽章稀有度正確
SELECT ok(
  (SELECT ((get_user_badges_with_progress(null))->'in_progress_badges'->0)->>'rarity' 
   IN ('Common', 'Uncommon', 'Rare', 'Epic', 'Legendary')),
  '徽章稀有度為有效值'
);

SELECT * FROM finish();
ROLLBACK;
```

### 4.8 執行資料庫測試

```bash
# 執行所有資料庫測試
npx supabase test db

# 執行特定測試檔案
npx supabase test db --file 01_rls_users.test.sql

# 查看詳細輸出
npx supabase test db --debug
```

**預期輸出範例：**

```
Running tests...

supabase/tests/database/01_rls_users.test.sql
1..10
ok 1 - 已登入用戶可以查看其他用戶的公開資訊
ok 2 - 可以正確查詢到其他用戶的 nickname
ok 3 - 用戶可以更新自己的 nickname
ok 4 - 用戶不能更新其他人的 nickname（RLS 阻止）
ok 5 - 用戶不能直接修改 avg_rating（應由系統計算）
ok 6 - 用戶不能直接插入新用戶記錄
ok 7 - 用戶不能刪除自己的記錄
ok 8 - 匿名用戶無法查看任何用戶資料
ok 9 - 用戶可以查看自己的 profile
ok 10 - 用戶無法查看他人的 profile（RLS 阻止）

All tests passed! ✅
```

---

## 5. 前端單元測試 (Vitest)

### 5.1 Supabase Mock 設置

```typescript
// tests/mocks/supabase.ts
import { vi } from 'vitest';

/**
 * 建立可自訂的 Supabase Mock 客戶端
 * 支援鏈式調用和各種 API 方法
 */
export const createMockSupabaseClient = () => {
  // 建立鏈式調用物件
  const createChainMock = () => {
    const chain: any = {
      select: vi.fn().mockReturnThis(),
      insert: vi.fn().mockReturnThis(),
      update: vi.fn().mockReturnThis(),
      delete: vi.fn().mockReturnThis(),
      upsert: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      neq: vi.fn().mockReturnThis(),
      gt: vi.fn().mockReturnThis(),
      gte: vi.fn().mockReturnThis(),
      lt: vi.fn().mockReturnThis(),
      lte: vi.fn().mockReturnThis(),
      in: vi.fn().mockReturnThis(),
      is: vi.fn().mockReturnThis(),
      order: vi.fn().mockReturnThis(),
      limit: vi.fn().mockReturnThis(),
      range: vi.fn().mockReturnThis(),
      single: vi.fn().mockResolvedValue({ data: null, error: null }),
      maybeSingle: vi.fn().mockResolvedValue({ data: null, error: null }),
      then: vi.fn().mockResolvedValue({ data: [], error: null })
    };
    return chain;
  };

  return {
    from: vi.fn(() => createChainMock()),
    
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id: 'test-user-id', email: 'test@fcu.edu.tw' } },
        error: null
      }),
      getSession: vi.fn().mockResolvedValue({
        data: { 
          session: { 
            user: { id: 'test-user-id' },
            access_token: 'fake-token'
          } 
        },
        error: null
      }),
      signInWithPassword: vi.fn().mockResolvedValue({
        data: { 
          user: { id: 'test-user-id' },
          session: { access_token: 'fake-token' }
        },
        error: null
      }),
      signUp: vi.fn().mockResolvedValue({
        data: { user: { id: 'new-user-id' } },
        error: null
      }),
      signOut: vi.fn().mockResolvedValue({ error: null }),
      onAuthStateChange: vi.fn((callback) => {
        return { 
          data: { 
            subscription: { unsubscribe: vi.fn() } 
          } 
        };
      })
    },
    
    rpc: vi.fn().mockResolvedValue({ data: null, error: null }),
    
    channel: vi.fn(() => ({
      on: vi.fn().mockReturnThis(),
      subscribe: vi.fn().mockReturnValue({ unsubscribe: vi.fn() })
    })),
    
    storage: {
      from: vi.fn(() => ({
        upload: vi.fn().mockResolvedValue({ data: { path: 'test/path.jpg' }, error: null }),
        getPublicUrl: vi.fn().mockReturnValue({ data: { publicUrl: 'https://test.com/image.jpg' } }),
        remove: vi.fn().mockResolvedValue({ data: null, error: null })
      }))
    }
  };
};

// 預設 Mock 實例
export const mockSupabaseClient = createMockSupabaseClient();

// 重置所有 Mock
export const resetMocks = () => {
  vi.clearAllMocks();
};
```

### 5.2 認證 Store 測試

```typescript
// tests/unit/stores/auth.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { setActivePinia, createPinia } from 'pinia';
import { useAuthStore } from '@/stores/auth';
import { mockSupabaseClient, resetMocks } from '../../mocks/supabase';

// Mock Supabase Client
vi.mock('@/supabaseClient', () => ({
  supabase: mockSupabaseClient
}));

describe('Auth Store', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    resetMocks();
  });

  describe('登入功能', () => {
    it('應該成功登入並設置用戶狀態', async () => {
      // Arrange
      mockSupabaseClient.auth.signInWithPassword.mockResolvedValue({
        data: {
          user: { id: 'user-123', email: 'test@fcu.edu.tw' },
          session: { access_token: 'token-123' }
        },
        error: null
      });

      const authStore = useAuthStore();

      // Act
      await authStore.signIn('test@fcu.edu.tw', 'password123');

      // Assert
      expect(mockSupabaseClient.auth.signInWithPassword).toHaveBeenCalledWith({
        email: 'test@fcu.edu.tw',
        password: 'password123'
      });
      expect(authStore.user?.id).toBe('user-123');
      expect(authStore.isAuthenticated).toBe(true);
    });

    it('應該處理登入錯誤', async () => {
      // Arrange
      mockSupabaseClient.auth.signInWithPassword.mockResolvedValue({
        data: { user: null, session: null },
        error: { message: '密碼錯誤' }
      });

      const authStore = useAuthStore();

      // Act
      await authStore.signIn('test@fcu.edu.tw', 'wrong-password');

      // Assert
      expect(authStore.error).toBe('密碼錯誤');
      expect(authStore.isAuthenticated).toBe(false);
    });
  });

  describe('登出功能', () => {
    it('應該成功登出並清除狀態', async () => {
      // Arrange
      const authStore = useAuthStore();
      authStore.$patch({
        user: { id: 'user-123' },
        session: { access_token: 'token' }
      });

      // Act
      await authStore.signOut();

      // Assert
      expect(mockSupabaseClient.auth.signOut).toHaveBeenCalled();
      expect(authStore.user).toBeNull();
      expect(authStore.isAuthenticated).toBe(false);
    });
  });

  describe('Session 恢復', () => {
    it('應該從現有 Session 恢復用戶狀態', async () => {
      // Arrange
      mockSupabaseClient.auth.getSession.mockResolvedValue({
        data: {
          session: {
            user: { id: 'restored-user' },
            access_token: 'restored-token'
          }
        },
        error: null
      });

      const authStore = useAuthStore();

      // Act
      await authStore.restoreSession();

      // Assert
      expect(authStore.user?.id).toBe('restored-user');
      expect(authStore.isAuthenticated).toBe(true);
    });
  });
});
```

### 5.3 每日簽到 API 測試

```typescript
// tests/unit/api/dailySignIn.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { dailySignIn } from '@/contracts/dailySignInAPI/dailySignIn';
import { mockSupabaseClient, resetMocks } from '../../mocks/supabase';

vi.mock('src/supabaseClient', () => ({
  supabase: mockSupabaseClient
}));

describe('每日簽到 API', () => {
  beforeEach(() => {
    resetMocks();
    // 模擬已登入狀態
    mockSupabaseClient.auth.getUser.mockResolvedValue({
      data: { user: { id: 'user-123' } },
      error: null
    });
  });

  describe('dailySignIn()', () => {
    it('應該成功執行首次簽到', async () => {
      // Arrange
      mockSupabaseClient.rpc.mockResolvedValue({
        data: {
          success: true,
          message: '簽到成功！',
          points_awarded: 5,
          streak_day: 1,
          next_reward: 2,
          new_balance: 10005,
          badges: {
            newly_earned_count: 0,
            total_points_awarded: 0,
            badges: null
          }
        },
        error: null
      });

      // Act
      const result = await dailySignIn();

      // Assert
      expect(mockSupabaseClient.rpc).toHaveBeenCalledWith('daily_check_in');
      expect(result.success).toBe(true);
      expect(result.points_awarded).toBe(5);
      expect(result.streak_day).toBe(1);
    });

    it('應該處理今天已簽到的情況', async () => {
      // Arrange
      mockSupabaseClient.rpc.mockResolvedValue({
        data: {
          success: false,
          message: '您今天已經簽到過了',
          points_awarded: 0,
          streak_day: 5
        },
        error: null
      });

      // Act
      const result = await dailySignIn();

      // Assert
      expect(result.success).toBe(false);
      expect(result.message).toContain('已經簽到');
    });

    it('應該處理連續簽到獎勵', async () => {
      // Arrange - 連續第 7 天
      mockSupabaseClient.rpc.mockResolvedValue({
        data: {
          success: true,
          message: '簽到成功！',
          points_awarded: 20,
          streak_day: 7,
          next_reward: 7,
          new_balance: 10120,
          badges: {
            newly_earned_count: 1,
            total_points_awarded: 50,
            badges: [{
              badge_id: 'streak_7',
              name: '連續簽到達人',
              icon: '🔥'
            }]
          }
        },
        error: null
      });

      // Act
      const result = await dailySignIn();

      // Assert
      expect(result.points_awarded).toBe(20);
      expect(result.badges.newly_earned_count).toBe(1);
    });

    it('應該在未登入時拋出錯誤', async () => {
      // Arrange
      mockSupabaseClient.auth.getUser.mockResolvedValue({
        data: { user: null },
        error: null
      });

      // Act & Assert
      await expect(dailySignIn()).rejects.toThrow('使用者未登入');
    });

    it('應該處理 RPC 錯誤', async () => {
      // Arrange
      mockSupabaseClient.rpc.mockResolvedValue({
        data: null,
        error: { message: '資料庫連線失敗' }
      });

      // Act & Assert
      await expect(dailySignIn()).rejects.toThrow('資料庫連線失敗');
    });
  });
});
```

### 5.4 交易 API 測試

```typescript
// tests/unit/api/transaction.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { 
  initiateTransaction, 
  getMyTransactionsByStatus,
  buyerConfirmTransaction,
  cancelTransaction 
} from '@/contracts/transaction/transaction_before_meetAPI';
import { mockSupabaseClient, resetMocks } from '../../mocks/supabase';

vi.mock('@/supabaseClient', () => ({
  supabase: mockSupabaseClient
}));

describe('交易 API', () => {
  beforeEach(() => {
    resetMocks();
  });

  describe('initiateTransaction()', () => {
    it('賣家應該能成功發起交易', async () => {
      // Arrange
      mockSupabaseClient.rpc.mockResolvedValue({
        data: {
          transaction_id: 1001,
          status: 'confirming',
          code: '123456'
        },
        error: null
      });

      // Act
      const result = await initiateTransaction(101, 'buyer-uuid');

      // Assert
      expect(mockSupabaseClient.rpc).toHaveBeenCalledWith('initiate_transaction', {
        p_item_id: 101,
        p_receiver_id: 'buyer-uuid'
      });
      expect(result.status).toBe('confirming');
      expect(result.code).toHaveLength(6);
    });

    it('應該處理物品已下架的錯誤', async () => {
      // Arrange
      mockSupabaseClient.rpc.mockResolvedValue({
        data: null,
        error: { message: '物品已下架或不存在' }
      });

      // Act & Assert
      await expect(initiateTransaction(999, 'buyer-uuid'))
        .rejects.toThrow('物品已下架或不存在');
    });
  });

  describe('getMyTransactionsByStatus()', () => {
    it('應該正確查詢確認中的交易', async () => {
      // Arrange
      mockSupabaseClient.rpc.mockResolvedValue({
        data: [{
          id: 1001,
          item: { id: 101, title: 'iPhone 15', price: 20000 },
          giver: { nickname: 'Seller' },
          receiver: { nickname: 'Buyer' },
          status: 'confirming'
        }],
        error: null
      });

      // Act
      const result = await getMyTransactionsByStatus('confirming', 'giver');

      // Assert
      expect(mockSupabaseClient.rpc).toHaveBeenCalledWith('get_my_transactions_by_status', {
        p_status: 'confirming',
        p_role: 'giver'
      });
      expect(result).toHaveLength(1);
      expect(result[0].status).toBe('confirming');
    });
  });

  describe('buyerConfirmTransaction()', () => {
    it('買家確認後交易狀態應變為 pending', async () => {
      // Arrange
      mockSupabaseClient.rpc.mockResolvedValue({
        data: {
          success: true,
          new_status: 'pending'
        },
        error: null
      });

      // Act
      const result = await buyerConfirmTransaction(1001, '我會準時到');

      // Assert
      expect(result.new_status).toBe('pending');
    });

    it('餘額不足時應拋出錯誤', async () => {
      // Arrange
      mockSupabaseClient.rpc.mockResolvedValue({
        data: null,
        error: { message: 'INSUFFICIENT_BALANCE' }
      });

      // Act & Assert
      await expect(buyerConfirmTransaction(1001, '確認'))
        .rejects.toThrow('INSUFFICIENT_BALANCE');
    });
  });

  describe('cancelTransaction()', () => {
    it('取消交易後物品應重新上架', async () => {
      // Arrange
      mockSupabaseClient.rpc.mockResolvedValue({
        data: {
          success: true,
          new_status: 'cancelled'
        },
        error: null
      });

      // Act
      const result = await cancelTransaction(1001);

      // Assert
      expect(result.new_status).toBe('cancelled');
    });
  });
});
```

### 5.5 RLS 錯誤處理測試

```typescript
// tests/unit/components/ItemEditForm.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import ItemEditForm from '@/components/ItemEditForm.vue';
import { mockSupabaseClient, resetMocks } from '../../mocks/supabase';

vi.mock('@/supabaseClient', () => ({
  supabase: mockSupabaseClient
}));

describe('ItemEditForm 元件', () => {
  beforeEach(() => {
    resetMocks();
  });

  it('應該處理 RLS 權限錯誤', async () => {
    // Arrange - 模擬 RLS 拒絕存取
    mockSupabaseClient.from('items').update.mockReturnValue({
      eq: vi.fn().mockResolvedValue({
        data: null,
        error: {
          message: 'new row violates row-level security policy',
          code: '42501',
          details: 'Policy violation on table items'
        }
      })
    });

    const wrapper = mount(ItemEditForm, {
      props: { itemId: 'other-user-item' }
    });

    // Act
    await wrapper.find('form').trigger('submit');
    await wrapper.vm.$nextTick();

    // Assert
    expect(wrapper.text()).toContain('您沒有權限編輯此物品');
    expect(wrapper.emitted('error')?.[0]).toEqual(['permission_denied']);
  });

  it('應該正確顯示 RLS 錯誤代碼', async () => {
    // Arrange
    mockSupabaseClient.from('items').select.mockReturnValue({
      eq: vi.fn().mockReturnValue({
        single: vi.fn().mockResolvedValue({
          data: null,
          error: { code: '42501', message: 'RLS policy violation' }
        })
      })
    });

    const wrapper = mount(ItemEditForm, {
      props: { itemId: 'restricted-item' }
    });

    await wrapper.vm.$nextTick();

    // Assert
    expect(wrapper.find('.error-code').text()).toBe('42501');
  });
});
```

---

## 6. 整合測試 (Supabase Local)

### 6.1 整合測試環境設置

```typescript
// tests/integration/setup.ts
import { createClient, SupabaseClient } from '@supabase/supabase-js';

// 使用本地 Supabase 實例
export const supabase: SupabaseClient = createClient(
  process.env.PUBLIC_SUPABASE_URL || 'http://localhost:54321',
  process.env.PUBLIC_SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'
);

// 建立測試用戶並登入
export async function createAndSignInTestUser(email: string, password: string) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password
  });
  
  if (error) throw error;
  return data;
}

// 清理測試資料
export async function cleanupTestData(userId: string) {
  // 使用 service role key 進行清理
  const adminClient = createClient(
    process.env.PUBLIC_SUPABASE_URL || 'http://localhost:54321',
    process.env.SUPABASE_SERVICE_ROLE_KEY || ''
  );
  
  await adminClient.from('transactions').delete().eq('giver_id', userId);
  await adminClient.from('transactions').delete().eq('receiver_id', userId);
  await adminClient.from('items').delete().eq('user_id', userId);
  await adminClient.from('locations').delete().eq('user_id', userId);
  await adminClient.from('profiles').delete().eq('user_id', userId);
  await adminClient.from('users').delete().eq('id', userId);
  await adminClient.auth.admin.deleteUser(userId);
}
```

### 6.2 完整交易流程整合測試

```typescript
// tests/integration/transactions.integration.test.ts
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { supabase, createAndSignInTestUser, cleanupTestData } from './setup';

describe('交易系統整合測試', () => {
  let sellerId: string;
  let buyerId: string;
  let itemId: number;
  let transactionId: number;
  let confirmCode: string;

  beforeAll(async () => {
    // 建立賣家帳號
    const sellerData = await createAndSignInTestUser(
      `seller-${Date.now()}@test.fcu.edu.tw`,
      'testpass123'
    );
    sellerId = sellerData.user!.id;

    // 為賣家建立地點
    await supabase.from('locations').insert({
      user_id: sellerId,
      coordinates: 'POINT(120.6478 24.1797)',
      type: '公司',
      is_primary: true,
      formatted_address: '逢甲大學'
    });

    // 建立測試物品
    const { data: item } = await supabase.from('items').insert({
      user_id: sellerId,
      sub_category_id: 1,
      title: '整合測試商品',
      condition: '良好',
      price: 1000,
      listing_status: true,
      carbon_value: 2.0
    }).select().single();
    
    itemId = item!.id;

    // 登出賣家，建立買家帳號
    await supabase.auth.signOut();
    
    const buyerData = await createAndSignInTestUser(
      `buyer-${Date.now()}@test.fcu.edu.tw`,
      'testpass123'
    );
    buyerId = buyerData.user!.id;

    // 確保買家有足夠餘額
    // (新用戶預設 10000 點)
  });

  afterAll(async () => {
    await cleanupTestData(sellerId);
    await cleanupTestData(buyerId);
  });

  it('步驟 1: 賣家發起交易', async () => {
    // 切換到賣家
    await supabase.auth.signInWithPassword({
      email: `seller-${sellerId}@test.fcu.edu.tw`,
      password: 'testpass123'
    });

    // 發起交易
    const { data, error } = await supabase.rpc('initiate_transaction', {
      p_item_id: itemId,
      p_receiver_id: buyerId
    });

    expect(error).toBeNull();
    expect(data.status).toBe('confirming');
    expect(data.code).toHaveLength(6);

    transactionId = data.transaction_id;
    confirmCode = data.code;
  });

  it('步驟 2: 物品自動下架', async () => {
    const { data: item } = await supabase
      .from('items')
      .select('listing_status')
      .eq('id', itemId)
      .single();

    expect(item!.listing_status).toBe(false);
  });

  it('步驟 3: 買家確認交易', async () => {
    // 切換到買家
    await supabase.auth.signInWithPassword({
      email: `buyer-${buyerId}@test.fcu.edu.tw`,
      password: 'testpass123'
    });

    const { data, error } = await supabase.rpc('buyer_confirm_transaction', {
      p_transaction_id: transactionId,
      p_note: '我會在校門口等'
    });

    expect(error).toBeNull();
    expect(data.new_status).toBe('pending');
  });

  it('步驟 4: 買家輸入確認碼完成交易', async () => {
    const { data, error } = await supabase.rpc('complete_transaction', {
      p_transaction_id: transactionId,
      p_code: confirmCode
    });

    expect(error).toBeNull();
    expect(data.success).toBe(true);
    expect(data.new_status).toBe('completed');
  });

  it('步驟 5: 驗證點數正確轉移', async () => {
    // 檢查買家餘額 (應該是 10000 - 1000 = 9000)
    const { data: buyerProfile } = await supabase
      .from('profiles')
      .select('balance, carbon_saved_kg')
      .eq('user_id', buyerId)
      .single();

    expect(buyerProfile!.balance).toBe(9000);
    expect(Number(buyerProfile!.carbon_saved_kg)).toBe(2.0);

    // 檢查賣家餘額 (應該是 10000 + 1000 = 11000)
    const { data: sellerProfile } = await supabase
      .from('profiles')
      .select('balance')
      .eq('user_id', sellerId)
      .single();

    expect(sellerProfile!.balance).toBe(11000);
  });

  it('步驟 6: 驗證點數記錄正確', async () => {
    const { data: logs } = await supabase
      .from('point_logs')
      .select('*')
      .or(`user_id.eq.${buyerId},user_id.eq.${sellerId}`)
      .order('created_at', { ascending: false });

    expect(logs!.length).toBeGreaterThanOrEqual(2);
    
    // 應該有一筆買家扣款記錄和一筆賣家收款記錄
    const buyerLog = logs!.find(l => l.user_id === buyerId && l.amount < 0);
    const sellerLog = logs!.find(l => l.user_id === sellerId && l.amount > 0);
    
    expect(buyerLog).toBeDefined();
    expect(sellerLog).toBeDefined();
  });
});
```

### 6.3 RLS 政策整合測試

```typescript
// tests/integration/rls.integration.test.ts
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { supabase, createAndSignInTestUser, cleanupTestData } from './setup';

describe('RLS 政策整合測試', () => {
  let userAId: string;
  let userBId: string;
  let userAItemId: number;

  beforeAll(async () => {
    // 建立兩個測試用戶
    const userA = await createAndSignInTestUser(
      `userA-${Date.now()}@test.fcu.edu.tw`,
      'testpass123'
    );
    userAId = userA.user!.id;

    // 為 User A 建立物品
    const { data: item } = await supabase.from('items').insert({
      user_id: userAId,
      sub_category_id: 1,
      title: 'User A 的物品',
      condition: '良好',
      price: 500,
      listing_status: true
    }).select().single();
    
    userAItemId = item!.id;

    await supabase.auth.signOut();

    const userB = await createAndSignInTestUser(
      `userB-${Date.now()}@test.fcu.edu.tw`,
      'testpass123'
    );
    userBId = userB.user!.id;
  });

  afterAll(async () => {
    await cleanupTestData(userAId);
    await cleanupTestData(userBId);
  });

  it('User B 可以看到 User A 已上架的物品', async () => {
    const { data, error } = await supabase
      .from('items')
      .select('*')
      .eq('id', userAItemId);

    expect(error).toBeNull();
    expect(data).toHaveLength(1);
    expect(data![0].title).toBe('User A 的物品');
  });

  it('User B 無法更新 User A 的物品', async () => {
    const { data, error } = await supabase
      .from('items')
      .update({ price: 999 })
      .eq('id', userAItemId)
      .select();

    // RLS 會阻止更新，返回空結果而非錯誤
    expect(data).toHaveLength(0);
  });

  it('User B 無法刪除 User A 的物品', async () => {
    const { error } = await supabase
      .from('items')
      .delete()
      .eq('id', userAItemId);

    // 檢查物品仍然存在
    const { data } = await supabase
      .from('items')
      .select('*')
      .eq('id', userAItemId);

    expect(data).toHaveLength(1);
  });

  it('User B 無法查看 User A 的 profile', async () => {
    const { data } = await supabase
      .from('profiles')
      .select('balance')
      .eq('user_id', userAId);

    // RLS 應該阻止存取
    expect(data).toHaveLength(0);
  });

  it('User B 只能查看自己的 profile', async () => {
    const { data } = await supabase
      .from('profiles')
      .select('balance')
      .eq('user_id', userBId);

    expect(data).toHaveLength(1);
    expect(data![0].balance).toBeDefined();
  });
});
```

---

## 7. 端對端測試 (Playwright)

### 7.1 認證設置

```typescript
// tests/e2e/auth.setup.ts
import { test as setup, expect } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';
import fs from 'fs';
import path from 'path';

const authFile = path.join(__dirname, '../.auth/user.json');

setup('建立測試用戶認證', async ({ page }) => {
  // 使用 Supabase API 登入
  const supabase = createClient(
    process.env.PUBLIC_SUPABASE_URL!,
    process.env.PUBLIC_SUPABASE_ANON_KEY!
  );

  const { data, error } = await supabase.auth.signInWithPassword({
    email: 'e2e-test@fcu.edu.tw',
    password: 'e2e-test-password'
  });

  expect(error).toBeNull();
  expect(data.session).not.toBeNull();

  // 儲存 session 到檔案
  const sessionData = {
    session: data.session,
    projectRef: process.env.PUBLIC_SUPABASE_URL!.match(
      /https?:\/\/([^.]+)/
    )?.[1] || 'localhost'
  };

  fs.mkdirSync(path.dirname(authFile), { recursive: true });
  fs.writeFileSync(authFile, JSON.stringify(sessionData));
});
```

### 7.2 完整購買流程 E2E 測試

```typescript
// tests/e2e/purchase-flow.spec.ts
import { test, expect } from '@playwright/test';
import fs from 'fs';
import path from 'path';

const authFile = path.join(__dirname, '../.auth/user.json');

test.describe('商品購買流程', () => {
  test.beforeEach(async ({ page, context }) => {
    // 載入認證 session
    const sessionData = JSON.parse(fs.readFileSync(authFile, 'utf-8'));
    
    // 注入 session 到 localStorage
    await context.addInitScript((data) => {
      localStorage.setItem(
        `sb-${data.projectRef}-auth-token`,
        JSON.stringify(data.session)
      );
    }, sessionData);
  });

  test('使用者可以搜尋並瀏覽商品', async ({ page }) => {
    // 前往首頁
    await page.goto('/');
    
    // 驗證已登入
    await expect(page.locator('[data-testid="user-avatar"]')).toBeVisible();

    // 搜尋商品
    await page.fill('[data-testid="search-input"]', 'iPhone');
    await page.click('[data-testid="search-button"]');

    // 等待搜尋結果
    await page.waitForResponse(response =>
      response.url().includes('supabase') &&
      response.url().includes('search_items')
    );

    // 驗證有搜尋結果
    await expect(page.locator('.item-card')).toHaveCount.greaterThan(0);
  });

  test('使用者可以查看商品詳情', async ({ page }) => {
    await page.goto('/');
    
    // 點擊第一個商品
    await page.click('.item-card:first-child');

    // 驗證詳情頁面元素
    await expect(page.locator('[data-testid="item-title"]')).toBeVisible();
    await expect(page.locator('[data-testid="item-price"]')).toBeVisible();
    await expect(page.locator('[data-testid="seller-info"]')).toBeVisible();
    await expect(page.locator('[data-testid="contact-seller-btn"]')).toBeVisible();
  });

  test('買家可以與賣家開始對話', async ({ page }) => {
    await page.goto('/items/1'); // 假設商品 ID 為 1

    // 點擊聯絡賣家
    await page.click('[data-testid="contact-seller-btn"]');

    // 驗證對話視窗開啟
    await expect(page.locator('[data-testid="chat-window"]')).toBeVisible();

    // 發送訊息
    await page.fill('[data-testid="message-input"]', '請問這個還有嗎？');
    await page.click('[data-testid="send-message-btn"]');

    // 驗證訊息已發送
    await expect(page.locator('.message-bubble:last-child'))
      .toContainText('請問這個還有嗎？');
  });
});
```

### 7.3 每日簽到 E2E 測試

```typescript
// tests/e2e/daily-signin.spec.ts
import { test, expect } from '@playwright/test';
import fs from 'fs';
import path from 'path';

const authFile = path.join(__dirname, '../.auth/user.json');

test.describe('每日簽到功能', () => {
  test.beforeEach(async ({ page, context }) => {
    const sessionData = JSON.parse(fs.readFileSync(authFile, 'utf-8'));
    await context.addInitScript((data) => {
      localStorage.setItem(
        `sb-${data.projectRef}-auth-token`,
        JSON.stringify(data.session)
      );
    }, sessionData);
  });

  test('使用者可以執行每日簽到', async ({ page }) => {
    await page.goto('/profile');

    // 點擊簽到按鈕
    await page.click('[data-testid="daily-signin-btn"]');

    // 等待簽到 API 回應
    await page.waitForResponse(response =>
      response.url().includes('daily_check_in')
    );

    // 驗證簽到成功提示
    await expect(page.locator('.toast-success')).toContainText('簽到成功');
    
    // 驗證點數更新
    await expect(page.locator('[data-testid="user-balance"]')).not.toHaveText('10000');
  });

  test('重複簽到應顯示錯誤提示', async ({ page }) => {
    await page.goto('/profile');

    // 第一次簽到
    await page.click('[data-testid="daily-signin-btn"]');
    await page.waitForTimeout(1000);

    // 嘗試第二次簽到
    await page.click('[data-testid="daily-signin-btn"]');

    // 驗證錯誤提示
    await expect(page.locator('.toast-warning')).toContainText('已經簽到');
  });
});
```

---

## 8. CI/CD 自動化測試

### 8.1 GitHub Actions 配置

```yaml
# .github/workflows/test.yml
name: FCU Sigma 測試流程

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}

jobs:
  # ==========================================
  # 資料庫測試 (pgTAP)
  # ==========================================
  database-tests:
    name: 📊 資料庫測試
    runs-on: ubuntu-latest
    
    steps:
      - name: 檢出代碼
        uses: actions/checkout@v4
      
      - name: 設置 Supabase CLI
        uses: supabase/setup-cli@v1
        with:
          version: latest
      
      - name: 啟動本地 Supabase
        run: |
          cd backend
          supabase start
      
      - name: 執行資料庫測試
        run: |
          cd backend
          supabase test db
      
      - name: 停止 Supabase
        if: always()
        run: |
          cd backend
          supabase stop

  # ==========================================
  # 前端單元測試
  # ==========================================
  unit-tests:
    name: 🧪 單元測試
    runs-on: ubuntu-latest
    
    steps:
      - name: 檢出代碼
        uses: actions/checkout@v4
      
      - name: 設置 Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: backend/package-lock.json
      
      - name: 安裝依賴
        run: |
          cd backend
          npm ci
      
      - name: 執行單元測試
        run: |
          cd backend
          npm run test:unit -- --coverage
      
      - name: 上傳覆蓋率報告
        uses: codecov/codecov-action@v3
        with:
          files: backend/coverage/lcov.info
          flags: unittests

  # ==========================================
  # 整合測試
  # ==========================================
  integration-tests:
    name: 🔗 整合測試
    runs-on: ubuntu-latest
    needs: [database-tests]
    
    steps:
      - name: 檢出代碼
        uses: actions/checkout@v4
      
      - name: 設置 Supabase CLI
        uses: supabase/setup-cli@v1
        with:
          version: latest
      
      - name: 啟動本地 Supabase
        run: |
          cd backend
          supabase start
      
      - name: 設置 Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: backend/package-lock.json
      
      - name: 安裝依賴
        run: |
          cd backend
          npm ci
      
      - name: 執行整合測試
        run: |
          cd backend
          npm run test:integration
        env:
          PUBLIC_SUPABASE_URL: http://127.0.0.1:54321
          PUBLIC_SUPABASE_ANON_KEY: ${{ secrets.SUPABASE_LOCAL_ANON_KEY }}
          SUPABASE_SERVICE_ROLE_KEY: ${{ secrets.SUPABASE_LOCAL_SERVICE_KEY }}
      
      - name: 停止 Supabase
        if: always()
        run: |
          cd backend
          supabase stop

  # ==========================================
  # E2E 測試
  # ==========================================
  e2e-tests:
    name: 🎭 E2E 測試
    runs-on: ubuntu-latest
    needs: [unit-tests, integration-tests]
    
    steps:
      - name: 檢出代碼
        uses: actions/checkout@v4
      
      - name: 設置 Supabase CLI
        uses: supabase/setup-cli@v1
        with:
          version: latest
      
      - name: 啟動本地 Supabase
        run: |
          cd backend
          supabase start
      
      - name: 設置 Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      
      - name: 安裝依賴
        run: |
          cd backend
          npm ci
      
      - name: 安裝 Playwright 瀏覽器
        run: npx playwright install --with-deps chromium
      
      - name: 建立測試資料
        run: |
          cd backend
          npx supabase db reset
      
      - name: 執行 E2E 測試
        run: |
          cd backend
          npm run test:e2e
        env:
          PUBLIC_SUPABASE_URL: http://127.0.0.1:54321
          PUBLIC_SUPABASE_ANON_KEY: ${{ secrets.SUPABASE_LOCAL_ANON_KEY }}
      
      - name: 上傳測試報告
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: playwright-report
          path: backend/playwright-report/
          retention-days: 7
      
      - name: 停止 Supabase
        if: always()
        run: |
          cd backend
          supabase stop

  # ==========================================
  # 測試摘要
  # ==========================================
  test-summary:
    name: 📋 測試摘要
    runs-on: ubuntu-latest
    needs: [database-tests, unit-tests, integration-tests, e2e-tests]
    if: always()
    
    steps:
      - name: 測試結果摘要
        run: |
          echo "## 🧪 FCU Sigma 測試結果" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| 測試類型 | 狀態 |" >> $GITHUB_STEP_SUMMARY
          echo "|----------|------|" >> $GITHUB_STEP_SUMMARY
          echo "| 資料庫測試 | ${{ needs.database-tests.result == 'success' && '✅ 通過' || '❌ 失敗' }} |" >> $GITHUB_STEP_SUMMARY
          echo "| 單元測試 | ${{ needs.unit-tests.result == 'success' && '✅ 通過' || '❌ 失敗' }} |" >> $GITHUB_STEP_SUMMARY
          echo "| 整合測試 | ${{ needs.integration-tests.result == 'success' && '✅ 通過' || '❌ 失敗' }} |" >> $GITHUB_STEP_SUMMARY
          echo "| E2E 測試 | ${{ needs.e2e-tests.result == 'success' && '✅ 通過' || '❌ 失敗' }} |" >> $GITHUB_STEP_SUMMARY
```

---

## 9. 測試案例總表

### 9.1 測試案例清單

| ID | 模組 | 測試案例 | 類型 | 優先級 | 狀態 |
|:--:|------|----------|:----:|:------:|:----:|
| **RLS-001** | 使用者 | 已登入用戶可查看他人公開資訊 | pgTAP | P0 | ⬜ |
| **RLS-002** | 使用者 | 用戶只能更新自己的資料 | pgTAP | P0 | ⬜ |
| **RLS-003** | 使用者 | 匿名用戶無法存取資料 | pgTAP | P0 | ⬜ |
| **RLS-004** | Profile | 用戶只能查看自己的餘額 | pgTAP | P0 | ⬜ |
| **RLS-005** | 物品 | 可看到所有已上架物品 | pgTAP | P0 | ⬜ |
| **RLS-006** | 物品 | 無法看到未上架物品 | pgTAP | P0 | ⬜ |
| **RLS-007** | 物品 | 只能編輯/刪除自己的物品 | pgTAP | P0 | ⬜ |
| **TXN-001** | 交易 | 賣家可發起交易 | pgTAP | P0 | ⬜ |
| **TXN-002** | 交易 | 發起後生成 6 位確認碼 | pgTAP | P0 | ⬜ |
| **TXN-003** | 交易 | 發起後物品自動下架 | pgTAP | P0 | ⬜ |
| **TXN-004** | 交易 | 買家確認後狀態變 pending | pgTAP | P0 | ⬜ |
| **TXN-005** | 交易 | 正確確認碼可完成交易 | pgTAP | P0 | ⬜ |
| **TXN-006** | 交易 | 點數正確轉移 | 整合 | P0 | ⬜ |
| **TXN-007** | 交易 | 碳足跡正確累計 | 整合 | P1 | ⬜ |
| **TXN-008** | 交易 | 餘額不足無法確認 | pgTAP | P0 | ⬜ |
| **TXN-009** | 交易 | 取消後物品重新上架 | pgTAP | P1 | ⬜ |
| **SIGN-001** | 簽到 | 首次簽到獲得 5 點 | pgTAP | P1 | ⬜ |
| **SIGN-002** | 簽到 | 今天已簽到不能重複 | pgTAP | P1 | ⬜ |
| **SIGN-003** | 簽到 | 連續 3 天獲得 10 點 | pgTAP | P1 | ⬜ |
| **SIGN-004** | 簽到 | 連續 7 天獲得 20 點 | pgTAP | P1 | ⬜ |
| **SIGN-005** | 簽到 | 中斷後連續天數重置 | pgTAP | P1 | ⬜ |
| **BADGE-001** | 徽章 | 達成條件自動授予徽章 | pgTAP | P1 | ⬜ |
| **BADGE-002** | 徽章 | 徽章獎勵正確發放 | pgTAP | P1 | ⬜ |
| **BADGE-003** | 徽章 | 不會重複授予 | pgTAP | P2 | ⬜ |
| **MSG-001** | 訊息 | 可建立對話 | 整合 | P1 | ⬜ |
| **MSG-002** | 訊息 | 可發送/接收訊息 | 整合 | P1 | ⬜ |
| **MSG-003** | 訊息 | 訊息可標記已讀 | 整合 | P2 | ⬜ |
| **E2E-001** | 流程 | 完整購買流程 | E2E | P0 | ⬜ |
| **E2E-002** | 流程 | 完整賣家上架流程 | E2E | P0 | ⬜ |
| **E2E-003** | 流程 | 每日簽到 UI 流程 | E2E | P1 | ⬜ |

### 9.2 測試覆蓋率目標

| 模組 | 目標覆蓋率 | 說明 |
|------|:----------:|------|
| RLS 政策 | 100% | 安全性關鍵，必須完整測試 |
| 交易系統 | 95% | 核心業務，涉及金流 |
| 簽到/徽章 | 80% | 重要功能但容錯性較高 |
| 訊息系統 | 75% | 已有現成測試腳本 |
| UI 元件 | 60% | 依開發時間調整 |

---

## 10. 簡報大綱與投影片建議

### 10.1 簡報大綱 (15 分鐘)

```
📽️ FCU Sigma 軟體測試策略報告
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

▸ 第一部分：專案介紹 (2 分鐘)
  • 系統簡介：校園二手交易平台
  • 技術架構：Supabase + Vue.js
  • 為什麼測試策略需要調整？

▸ 第二部分：測試策略 (3 分鐘)
  • 測試金字塔（Supabase 優化版）
  • 四層測試架構
  • 優先順序與涵蓋範圍

▸ 第三部分：核心測試展示 (6 分鐘)
  • pgTAP 資料庫測試 Demo
  • RLS 政策測試案例
  • 交易系統測試案例
  • 整合測試展示

▸ 第四部分：自動化與 CI/CD (2 分鐘)
  • GitHub Actions 配置
  • 測試報告生成
  • 測試覆蓋率追蹤

▸ 第五部分：結論與心得 (2 分鐘)
  • 測試策略的價值
  • 遇到的挑戰與解決方案
  • 未來改進方向
  • Q&A
```

### 10.2 投影片內容建議

#### 投影片 1：封面
```
┌─────────────────────────────────────┐
│                                     │
│   FCU Sigma 生態交換平台            │
│   軟體測試策略報告                  │
│                                     │
│   ━━━━━━━━━━━━━━━━━━━━              │
│                                     │
│   逢甲大學 資訊工程系               │
│   軟體測試 期末專題                 │
│                                     │
│   組員：XXX, XXX, XXX               │
│   日期：2025/XX/XX                  │
│                                     │
└─────────────────────────────────────┘
```

#### 投影片 2：系統架構圖
```
展示前端到後端的完整架構：
• Vue.js 前端
• Supabase 後端服務
• PostgreSQL 資料庫
• RLS 安全層

重點標示：「業務邏輯在資料庫層」
```

#### 投影片 3：為什麼需要調整測試策略？
```
傳統後端 vs Supabase 架構對比表

| 傳統架構 | Supabase 架構 |
|----------|---------------|
| API 測試 | RPC 函數測試  |
| 中間件   | RLS 政策      |
| ORM      | SQL 觸發器    |

→ 需要使用 pgTAP 進行資料庫層測試
```

#### 投影片 4：測試金字塔
```
視覺化呈現優化後的測試金字塔

                   E2E (10%)
              ━━━━━━━━━━━━━━━
           整合測試 (25%)
        ━━━━━━━━━━━━━━━━━━━━━
      資料庫測試 - pgTAP (40%) ← 重點！
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━
   前端單元測試 (25%)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

#### 投影片 5-7：核心測試案例展示
```
• RLS 政策測試程式碼截圖
• 交易流程測試程式碼截圖
• 測試執行結果截圖
```

#### 投影片 8：CI/CD 流程圖
```
┌────────┐     ┌─────────┐     ┌──────────┐     ┌─────────┐
│ Commit │ ──▶ │ DB Test │ ──▶ │ Unit Test│ ──▶ │ E2E Test│
└────────┘     └─────────┘     └──────────┘     └─────────┘
                   ↓               ↓                 ↓
              ✅ 通過          ✅ 通過          ✅ 通過
                   ↓               ↓                 ↓
              ┌───────────────────────────────────────┐
              │          🚀 部署到 Production          │
              └───────────────────────────────────────┘
```

#### 投影片 9：測試覆蓋率報告
```
展示實際的測試覆蓋率數據：
• RLS 政策：100%
• 交易系統：95%
• 簽到系統：80%
• 整體覆蓋率：XX%
```

#### 投影片 10：挑戰與心得
```
遇到的挑戰：
• Supabase 測試文件較少
• pgTAP 學習曲線
• Mock Supabase Client

解決方案：
• 參考官方 GitHub 範例
• 建立可重用的測試輔助函數
• 建立標準化的 Mock 模板
```

#### 投影片 11：Q&A
```
┌─────────────────────────────────────┐
│                                     │
│         🙋 Q & A                    │
│                                     │
│       謝謝聆聽！                    │
│                                     │
│   GitHub: github.com/xxx/fcu-sigma  │
│                                     │
└─────────────────────────────────────┘
```

---

## 11. 附錄

### 11.1 參考資源

| 資源 | 連結 | 說明 |
|------|------|------|
| pgTAP 官方文件 | https://pgtap.org/documentation.html | 資料庫測試框架 |
| Supabase 測試指南 | https://supabase.com/docs/guides/database/testing | 官方測試文件 |
| Vitest 官方文件 | https://vitest.dev/ | 前端測試框架 |
| Playwright 官方文件 | https://playwright.dev/ | E2E 測試框架 |
| Vue Test Utils | https://test-utils.vuejs.org/ | Vue 元件測試 |

### 11.2 常見問題 FAQ

**Q1: 為什麼選擇 pgTAP 而不是 Jest 來測試資料庫？**
> A: 因為 FCU Sigma 的業務邏輯主要在 PostgreSQL 的 RPC 函數和 RLS 政策中實現，pgTAP 可以直接在資料庫層面測試這些邏輯，不需要經過網路層。

**Q2: 如何模擬不同用戶角色進行 RLS 測試？**
> A: 使用 `tests.authenticate_as(user_id)` 輔助函數設定 JWT claims，模擬特定用戶的認證狀態。

**Q3: 整合測試需要真實的 Supabase 實例嗎？**
> A: 是的，整合測試使用 `supabase start` 啟動的本地實例，這樣可以真實測試 RLS 政策和觸發器。

**Q4: 如何處理測試資料的清理？**
> A: 資料庫測試使用 `ROLLBACK` 回滾所有變更，整合測試在 `afterAll` 中使用 service role 清理資料。

### 11.3 測試檢查清單

```markdown
## 提交前測試檢查清單

### 本地測試
- [ ] `npm run test:db` 通過
- [ ] `npm run test:unit` 通過
- [ ] `npm run test:integration` 通過
- [ ] `npm run test:e2e` 通過

### 程式碼品質
- [ ] 沒有 console.log 除錯語句
- [ ] 測試覆蓋率達到目標
- [ ] 測試命名清晰描述預期行為

### CI/CD
- [ ] GitHub Actions 全部通過
- [ ] 無安全性警告
- [ ] 測試報告已產生
```

### 11.4 術語表

| 術語 | 說明 |
|------|------|
| **RLS** | Row Level Security，PostgreSQL 的資料列層級安全策略 |
| **RPC** | Remote Procedure Call，Supabase 的遠端函數呼叫 |
| **pgTAP** | PostgreSQL 的 TAP 測試框架 |
| **Mock** | 模擬物件，用於隔離測試環境 |
| **E2E** | End-to-End，端對端測試 |
| **CI/CD** | 持續整合/持續部署 |
| **Fixture** | 測試資料，用於建立測試環境 |
| **Assertion** | 斷言，驗證測試結果的陳述 |

---

## 📝 文件資訊

| 項目 | 內容 |
|------|------|
| 文件名稱 | FCU Sigma 軟體測試方案 |
| 版本 | v1.0 |
| 最後更新 | 2025 年 |
| 適用課程 | 逢甲大學資訊工程系 軟體測試 |
| 授權 | MIT License |

---

> 💡 **提示**：本測試方案為 FCU Sigma 專案量身打造，測試案例和策略可依據專案實際進度調整。建議從 P0 優先級的測試開始實作，確保核心功能的品質。
