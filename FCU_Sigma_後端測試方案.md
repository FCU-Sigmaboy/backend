# FCU Sigma 生態交換平台 - 後端測試方案

> 📚 **逢甲大學資訊工程系 軟體測試課程 期末專題報告**  
> 📅 版本: v1.0 | 2025 年  
> 🎯 專案: FCU Sigma 二手交易平台（後端團隊專用）

---

## 📋 目錄

1. [專案概述](#1-專案概述)
2. [後端測試策略](#2-後端測試策略)
3. [測試環境設置](#3-測試環境設置)
4. [資料庫層測試 (pgTAP)](#4-資料庫層測試-pgtap)
5. [RPC 函數測試](#5-rpc-函數測試)
6. [Edge Functions 測試](#6-edge-functions-測試)
7. [API 整合測試](#7-api-整合測試)
8. [CI/CD 自動化測試](#8-cicd-自動化測試)
9. [測試案例總表](#9-測試案例總表)
10. [簡報大綱](#10-簡報大綱)
11. [附錄](#11-附錄)

---

## 1. 專案概述

### 1.1 系統簡介

**FCU Sigma** 是一個基於 Supabase 的校園二手交易平台後端系統，採用「Backend-as-a-Service」架構。

### 1.2 後端核心功能

| 功能模組 | 技術實現 | 測試重點 |
|----------|----------|----------|
| 🔐 **認證系統** | Supabase Auth | 觸發器自動建立 profile |
| 🛍️ **物品管理** | PostgreSQL RPC | `create_item()`, `search_items()` |
| 💬 **即時訊息** | RPC + Realtime | `create_or_get_conversation()`, `send_message()` |
| 🤝 **交易系統** | RPC + 觸發器 | 狀態機、點數結算、原子操作 |
| 🎯 **每日簽到** | RPC + 觸發器 | `daily_check_in()`, 時區處理 |
| 🏆 **徽章系統** | RPC + 觸發器 | 自動授予、進度追蹤 |
| 🤖 **AI 分析** | Edge Functions | `analyze-item-image` |
| 🔒 **權限控制** | Row Level Security | 資料列層級安全策略 |

### 1.3 後端架構圖

```
┌─────────────────────────────────────────────────────────────┐
│                     外部請求（API / SDK）                    │
├─────────────────────────────────────────────────────────────┤
│                   Supabase API Gateway                       │
│              (PostgREST / GoTrue / Realtime)                 │
├──────────────┬──────────────┬──────────────┬────────────────┤
│   Auth       │   Database   │   Realtime   │ Edge Functions │
│   認證服務    │   PostgreSQL │   即時推播    │   無伺服器函數  │
├──────────────┴──────────────┴──────────────┴────────────────┤
│                  Row Level Security (RLS)                    │
│                  資料列層級安全策略                            │
├─────────────────────────────────────────────────────────────┤
│                     PostgreSQL 資料庫                        │
│    ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐      │
│    │  RPC    │  │ Triggers│  │  Views  │  │ Indexes │      │
│    │  函數    │  │  觸發器  │  │  檢視表  │  │  索引   │      │
│    └─────────┘  └─────────┘  └─────────┘  └─────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### 1.4 為什麼後端測試特別重要？

由於 FCU Sigma 採用 Supabase 架構，**所有業務邏輯都在資料庫層實現**：

| 元素 | 說明 | 測試重要性 |
|------|------|:----------:|
| **RLS 政策** | 權限控制的唯一防線 | 🔴 極高 |
| **RPC 函數** | 所有業務邏輯 | 🔴 極高 |
| **觸發器** | 自動化流程 | 🟡 高 |
| **約束條件** | 資料完整性 | 🟡 高 |
| **Edge Functions** | AI 分析等進階功能 | 🟢 中 |

---

## 2. 後端測試策略

### 2.1 測試金字塔（後端專用版）

```
                    ╱╲
                   ╱  ╲
                  ╱ API ╲          ← HTTP API 整合測試
                 ╱ (15%) ╲            驗證完整請求/回應
                ╱──────────╲
               ╱ Edge Func  ╲       ← Edge Functions 測試
              ╱    (10%)     ╲         AI 分析、外部 API
             ╱────────────────╲
            ╱   RPC 函數測試    ╲    ← pgTAP 業務邏輯
           ╱      (30%)         ╲       交易、簽到、徽章
          ╱──────────────────────╲
         ╱     RLS 政策測試       ╲  ← pgTAP 權限驗證
        ╱         (30%)           ╲     資料存取控制
       ╱────────────────────────────╲
      ╱   觸發器與約束條件測試        ╲ ← pgTAP 資料完整性
     ╱           (15%)               ╲    自動化流程驗證
    ╱──────────────────────────────────╲
```

### 2.2 測試優先順序

| 優先級 | 測試類型 | 涵蓋範圍 | 工具 | 執行頻率 |
|:------:|----------|----------|------|----------|
| 🔴 **P0** | RLS 政策測試 | 權限隔離、資料保護 | pgTAP | 每次 Commit |
| 🔴 **P0** | 交易 RPC 測試 | 狀態機、點數結算 | pgTAP | 每次 Commit |
| 🟡 **P1** | 其他 RPC 測試 | 搜尋、簽到、徽章 | pgTAP | 每次 Commit |
| 🟡 **P1** | 觸發器測試 | 自動更新、級聯操作 | pgTAP | 每次 PR |
| 🟢 **P2** | Edge Functions | AI 分析、外部 API | Deno Test | 每次 PR |
| 🟢 **P2** | API 整合測試 | HTTP 端點驗證 | 腳本測試 | 部署前 |

### 2.3 測試涵蓋範圍

```
FCU Sigma 後端測試涵蓋率目標
============================================================

RLS 政策測試
├── users 表     ▓▓▓▓▓▓▓▓▓▓ 100%
├── profiles 表  ▓▓▓▓▓▓▓▓▓▓ 100%
├── items 表     ▓▓▓▓▓▓▓▓▓▓ 100%
├── locations 表 ▓▓▓▓▓▓▓▓▓▓ 100%
├── transactions ▓▓▓▓▓▓▓▓▓▓ 100%
└── messages 表  ▓▓▓▓▓▓▓▓▓▓ 100%

RPC 函數測試
├── 交易系統     ▓▓▓▓▓▓▓▓▓▓ 100% (P0)
├── 搜尋功能     ▓▓▓▓▓▓▓▓░░  80%
├── 每日簽到     ▓▓▓▓▓▓▓▓░░  80%
├── 徽章系統     ▓▓▓▓▓▓▓░░░  70%
└── 訊息系統     ▓▓▓▓▓▓▓░░░  70%

觸發器測試
├── auth 觸發器  ▓▓▓▓▓▓▓▓░░  80%
├── 時間戳更新   ▓▓▓▓▓▓░░░░  60%
└── 徽章授予     ▓▓▓▓▓▓░░░░  60%

Edge Functions
├── analyze-item-image ▓▓▓▓▓▓░░░░  60%
└── save-location      ▓▓▓▓▓▓░░░░  60%
```

---

## 3. 測試環境設置

### 3.1 前置需求

```bash
# 必要軟體
- Docker Desktop 或 OrbStack (macOS 建議使用 OrbStack)
- Supabase CLI
- Deno (用於 Edge Functions 測試)
- psql (PostgreSQL 客戶端，可選)
```

### 3.2 安裝與啟動

```bash
# 進入專案目錄
cd backend

# 安裝 Supabase CLI（如果尚未安裝）
npm install -g supabase

# 啟動本地 Supabase
npx supabase start

# 重置資料庫（套用所有遷移）
npx supabase db reset

# 查看服務狀態
npx supabase status
```

### 3.3 測試目錄結構

```
backend/
├── supabase/
│   ├── tests/                          # 資料庫測試（核心）
│   │   ├── database/                   # pgTAP 測試檔案
│   │   │   ├── 00_test_helpers.sql     # 測試輔助函數
│   │   │   ├── 01_rls_users.test.sql   # 使用者 RLS 測試
│   │   │   ├── 02_rls_profiles.test.sql
│   │   │   ├── 03_rls_items.test.sql   # 物品 RLS 測試
│   │   │   ├── 04_rls_locations.test.sql
│   │   │   ├── 05_rls_transactions.test.sql
│   │   │   ├── 06_rls_messages.test.sql
│   │   │   ├── 10_rpc_transactions.test.sql  # 交易 RPC
│   │   │   ├── 11_rpc_search.test.sql        # 搜尋 RPC
│   │   │   ├── 12_rpc_daily_signin.test.sql  # 簽到 RPC
│   │   │   ├── 13_rpc_badges.test.sql        # 徽章 RPC
│   │   │   ├── 14_rpc_messaging.test.sql     # 訊息 RPC
│   │   │   ├── 20_triggers.test.sql          # 觸發器測試
│   │   │   └── 21_constraints.test.sql       # 約束條件測試
│   │   └── seed.sql                    # 測試資料種子
│   │
│   ├── functions/                      # Edge Functions
│   │   ├── analyze-item-image/
│   │   │   ├── index.ts
│   │   │   └── index.test.ts           # Edge Function 測試
│   │   └── save-location/
│   │       ├── index.ts
│   │       └── index.test.ts
│   │
│   └── migrations/                     # 資料庫遷移
│
├── tests/                              # API 整合測試
│   └── api/
│       ├── setup.ts                    # 測試環境設置
│       ├── auth.api.test.ts            # 認證 API 測試
│       ├── items.api.test.ts           # 物品 API 測試
│       └── transactions.api.test.ts    # 交易 API 測試
│
├── scripts/
│   └── run-tests.sh                    # 測試執行腳本
│
└── package.json                        # 測試腳本配置
```

### 3.4 package.json 測試腳本

```json
{
  "scripts": {
    "test": "npm run test:db",
    "test:db": "npx supabase test db",
    "test:db:verbose": "npx supabase test db --debug",
    "test:db:file": "npx supabase test db --file",
    "test:functions": "cd supabase/functions && deno test --allow-all",
    "test:api": "npx tsx tests/api/run.ts",
    "test:all": "npm run test:db && npm run test:functions && npm run test:api",
    "db:reset": "npx supabase db reset",
    "db:start": "npx supabase start",
    "db:stop": "npx supabase stop"
  },
  "devDependencies": {
    "@supabase/supabase-js": "^2.45.0",
    "@types/node": "^24.10.0",
    "tsx": "^4.19.0"
  }
}
```

---

## 4. 資料庫層測試 (pgTAP)

### 4.1 pgTAP 簡介

**pgTAP** 是 PostgreSQL 原生的 TAP（Test Anything Protocol）測試框架，是 Supabase 官方推薦的測試工具。

**核心優勢：**
- ✅ 直接在資料庫層面執行測試
- ✅ 完整模擬 RLS 政策
- ✅ 測試觸發器和函數
- ✅ Supabase CLI 原生支援
- ✅ 事務回滾確保測試獨立性

### 4.2 測試輔助函數

```sql
-- supabase/tests/database/00_test_helpers.sql
-- =============================================
-- FCU Sigma 後端測試輔助函數
-- =============================================

-- 建立測試用戶（模擬 Supabase Auth）
CREATE OR REPLACE FUNCTION tests.create_test_user(
  p_user_id UUID,
  p_nickname TEXT DEFAULT 'TestUser',
  p_balance INTEGER DEFAULT 10000
)
RETURNS UUID AS $$
BEGIN
  -- 插入 auth.users（模擬 Supabase Auth 註冊）
  INSERT INTO auth.users (
    id, 
    email, 
    encrypted_password,
    email_confirmed_at,
    created_at, 
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data,
    aud,
    role
  )
  VALUES (
    p_user_id,
    p_nickname || '@test.fcu.edu.tw',
    crypt('testpassword', gen_salt('bf')),
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    'authenticated',
    'authenticated'
  )
  ON CONFLICT (id) DO NOTHING;
  
  -- 插入 public.users
  INSERT INTO public.users (id, nickname, created_at, updated_at)
  VALUES (p_user_id, p_nickname, now(), now())
  ON CONFLICT (id) DO NOTHING;
  
  -- 插入 public.profiles（含自訂餘額）
  INSERT INTO public.profiles (user_id, balance, carbon_saved_kg)
  VALUES (p_user_id, p_balance, 0.00)
  ON CONFLICT (user_id) DO NOTHING;
  
  RETURN p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 模擬用戶認證（設定 JWT claims）
CREATE OR REPLACE FUNCTION tests.authenticate_as(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
  -- 設定 JWT claims 模擬已認證用戶
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', p_user_id::text,
      'role', 'authenticated',
      'aud', 'authenticated',
      'email', (SELECT email FROM auth.users WHERE id = p_user_id)
    )::text,
    true  -- 僅對當前事務有效
  );
  
  -- 設定當前角色為 authenticated
  PERFORM set_config('role', 'authenticated', true);
END;
$$ LANGUAGE plpgsql;

-- 模擬匿名用戶
CREATE OR REPLACE FUNCTION tests.authenticate_as_anon()
RETURNS VOID AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
END;
$$ LANGUAGE plpgsql;

-- 清除認證狀態
CREATE OR REPLACE FUNCTION tests.clear_authentication()
RETURNS VOID AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$ LANGUAGE plpgsql;

-- 建立測試物品
CREATE OR REPLACE FUNCTION tests.create_test_item(
  p_item_id BIGINT,
  p_user_id UUID,
  p_title TEXT DEFAULT '測試商品',
  p_price INTEGER DEFAULT 1000,
  p_listing_status BOOLEAN DEFAULT true
)
RETURNS BIGINT AS $$
BEGIN
  INSERT INTO public.items (
    id, user_id, sub_category_id, title, 
    description, condition, price, 
    listing_status, carbon_value
  )
  VALUES (
    p_item_id, p_user_id, 1, p_title,
    '測試用商品描述', '良好', p_price,
    p_listing_status, 2.0
  )
  ON CONFLICT (id) DO NOTHING;
  
  RETURN p_item_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 建立測試地點
CREATE OR REPLACE FUNCTION tests.create_test_location(
  p_user_id UUID,
  p_is_primary BOOLEAN DEFAULT true
)
RETURNS BIGINT AS $$
DECLARE
  v_location_id BIGINT;
BEGIN
  INSERT INTO public.locations (
    user_id, 
    coordinates, 
    type, 
    is_primary, 
    formatted_address
  )
  VALUES (
    p_user_id,
    ST_SetSRID(ST_MakePoint(120.6478, 24.1797), 4326),
    CASE WHEN p_is_primary THEN '公司' ELSE '家' END,
    p_is_primary,
    '逢甲大學 台中市西屯區文華路100號'
  )
  RETURNING id INTO v_location_id;
  
  RETURN v_location_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 取得當前認證用戶 ID
CREATE OR REPLACE FUNCTION tests.current_user_id()
RETURNS UUID AS $$
  SELECT NULLIF(
    current_setting('request.jwt.claims', true)::json->>'sub',
    ''
  )::UUID;
$$ LANGUAGE sql;

-- 清理所有測試資料
CREATE OR REPLACE FUNCTION tests.cleanup_all()
RETURNS VOID AS $$
BEGIN
  -- 按照外鍵順序刪除
  DELETE FROM public.conversation_messages;
  DELETE FROM public.conversations;
  DELETE FROM public.point_logs;
  DELETE FROM public.transactions;
  DELETE FROM public.favorites;
  DELETE FROM public.following;
  DELETE FROM public.ratings;
  DELETE FROM public.items;
  DELETE FROM public.locations;
  DELETE FROM public.profiles;
  DELETE FROM public.users;
  DELETE FROM auth.users;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 4.3 RLS 政策測試 - users 表

```sql
-- supabase/tests/database/01_rls_users.test.sql
-- =============================================
-- users 表 RLS 政策測試
-- =============================================

BEGIN;
SELECT plan(12);

-- =========== 測試準備 ===========

-- 建立測試用戶
SELECT tests.create_test_user(
  '11111111-1111-1111-1111-111111111111'::UUID,
  'UserA'
);
SELECT tests.create_test_user(
  '22222222-2222-2222-2222-222222222222'::UUID,
  'UserB'
);

-- =========== SELECT 測試 ===========

-- 測試 1: 已登入用戶可以查看其他用戶的公開資訊
SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

SELECT ok(
  EXISTS(SELECT 1 FROM public.users WHERE nickname = 'UserB'),
  'RLS-001: 已登入用戶可以查看其他用戶的公開資訊'
);

-- 測試 2: 可以正確查詢 nickname 欄位
SELECT is(
  (SELECT nickname FROM public.users WHERE id = '22222222-2222-2222-2222-222222222222'::UUID),
  'UserB',
  'RLS-002: 可以正確查詢到其他用戶的 nickname'
);

-- 測試 3: 可以查詢 avg_rating 欄位
SELECT ok(
  (SELECT avg_rating FROM public.users WHERE id = '22222222-2222-2222-2222-222222222222'::UUID) IS NOT NULL,
  'RLS-003: 可以查詢到其他用戶的 avg_rating'
);

-- =========== UPDATE 測試 ===========

-- 測試 4: 用戶可以更新自己的 nickname
UPDATE public.users SET nickname = 'UserA_Updated' 
WHERE id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT is(
  (SELECT nickname FROM public.users WHERE id = '11111111-1111-1111-1111-111111111111'::UUID),
  'UserA_Updated',
  'RLS-004: 用戶可以更新自己的 nickname'
);

-- 測試 5: 用戶不能更新其他人的 nickname（RLS 阻止）
UPDATE public.users SET nickname = 'Hacked!' 
WHERE id = '22222222-2222-2222-2222-222222222222'::UUID;

SELECT is(
  (SELECT nickname FROM public.users WHERE id = '22222222-2222-2222-2222-222222222222'::UUID),
  'UserB',
  'RLS-005: 用戶不能更新其他人的 nickname'
);

-- 測試 6: 用戶不能直接修改 avg_rating
UPDATE public.users SET avg_rating = 5.0 
WHERE id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT is(
  (SELECT avg_rating FROM public.users WHERE id = '11111111-1111-1111-1111-111111111111'::UUID),
  0.00::NUMERIC(3,2),
  'RLS-006: 用戶不能直接修改 avg_rating（應由系統計算）'
);

-- =========== INSERT 測試 ===========

-- 測試 7: 一般用戶不能直接插入新用戶
SELECT throws_ok(
  $$ INSERT INTO public.users (id, nickname) VALUES (gen_random_uuid(), 'NewUser') $$,
  NULL,
  'RLS-007: 用戶不能直接插入新用戶記錄'
);

-- =========== DELETE 測試 ===========

-- 測試 8: 用戶不能刪除自己的記錄
DELETE FROM public.users WHERE id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT ok(
  EXISTS(SELECT 1 FROM public.users WHERE id = '11111111-1111-1111-1111-111111111111'::UUID),
  'RLS-008: 用戶不能刪除自己的記錄'
);

-- 測試 9: 用戶不能刪除他人記錄
DELETE FROM public.users WHERE id = '22222222-2222-2222-2222-222222222222'::UUID;

SELECT ok(
  EXISTS(SELECT 1 FROM public.users WHERE id = '22222222-2222-2222-2222-222222222222'::UUID),
  'RLS-009: 用戶不能刪除他人記錄'
);

-- =========== 匿名用戶測試 ===========

SELECT tests.authenticate_as_anon();

-- 測試 10: 匿名用戶無法查看任何用戶資料
SELECT is(
  (SELECT COUNT(*) FROM public.users)::INTEGER,
  0,
  'RLS-010: 匿名用戶無法查看任何用戶資料'
);

-- 測試 11: 匿名用戶無法插入資料
SELECT throws_ok(
  $$ INSERT INTO public.users (id, nickname) VALUES (gen_random_uuid(), 'Anonymous') $$,
  NULL,
  'RLS-011: 匿名用戶無法插入資料'
);

-- 測試 12: 匿名用戶無法更新資料
UPDATE public.users SET nickname = 'Hacked' WHERE id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);
SELECT is(
  (SELECT nickname FROM public.users WHERE id = '11111111-1111-1111-1111-111111111111'::UUID),
  'UserA_Updated',  -- 應該維持之前的更新值
  'RLS-012: 匿名用戶無法更新資料'
);

SELECT * FROM finish();
ROLLBACK;
```

### 4.4 RLS 政策測試 - profiles 表

```sql
-- supabase/tests/database/02_rls_profiles.test.sql
-- =============================================
-- profiles 表 RLS 政策測試
-- =============================================

BEGIN;
SELECT plan(8);

-- =========== 測試準備 ===========

SELECT tests.create_test_user('11111111-1111-1111-1111-111111111111'::UUID, 'UserA', 10000);
SELECT tests.create_test_user('22222222-2222-2222-2222-222222222222'::UUID, 'UserB', 5000);

-- =========== SELECT 測試 ===========

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

-- 測試 1: 用戶可以查看自己的 profile
SELECT is(
  (SELECT balance FROM public.profiles WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID),
  10000,
  'RLS-PROFILE-001: 用戶可以查看自己的 profile 餘額'
);

-- 測試 2: 用戶無法查看他人的 profile（餘額是敏感資訊）
SELECT is(
  (SELECT balance FROM public.profiles WHERE user_id = '22222222-2222-2222-2222-222222222222'::UUID),
  NULL,
  'RLS-PROFILE-002: 用戶無法查看他人的 profile 餘額'
);

-- 測試 3: 只能查到自己的 profile 記錄
SELECT is(
  (SELECT COUNT(*) FROM public.profiles)::INTEGER,
  1,
  'RLS-PROFILE-003: 只能查到自己的 profile 記錄'
);

-- =========== UPDATE 測試 ===========

-- 測試 4: 用戶不能直接更新自己的 balance（必須透過 RPC）
UPDATE public.profiles SET balance = 999999 
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT is(
  (SELECT balance FROM public.profiles WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID),
  10000,  -- 應該維持原值
  'RLS-PROFILE-004: 用戶不能直接更新 balance（防止作弊）'
);

-- 測試 5: 用戶不能直接更新 carbon_saved_kg
UPDATE public.profiles SET carbon_saved_kg = 1000.00 
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT is(
  (SELECT carbon_saved_kg FROM public.profiles WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID),
  0.00::NUMERIC(10,2),  -- 應該維持原值
  'RLS-PROFILE-005: 用戶不能直接更新 carbon_saved_kg'
);

-- =========== INSERT/DELETE 測試 ===========

-- 測試 6: 用戶不能直接插入 profile
SELECT throws_ok(
  $$ INSERT INTO public.profiles (user_id, balance) VALUES (gen_random_uuid(), 999999) $$,
  NULL,
  'RLS-PROFILE-006: 用戶不能直接插入 profile'
);

-- 測試 7: 用戶不能刪除自己的 profile
DELETE FROM public.profiles WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT ok(
  EXISTS(SELECT 1 FROM public.profiles WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID),
  'RLS-PROFILE-007: 用戶不能刪除自己的 profile'
);

-- =========== 匿名用戶測試 ===========

SELECT tests.authenticate_as_anon();

-- 測試 8: 匿名用戶無法查看任何 profile
SELECT is(
  (SELECT COUNT(*) FROM public.profiles)::INTEGER,
  0,
  'RLS-PROFILE-008: 匿名用戶無法查看任何 profile'
);

SELECT * FROM finish();
ROLLBACK;
```

### 4.5 RLS 政策測試 - items 表

```sql
-- supabase/tests/database/03_rls_items.test.sql
-- =============================================
-- items 表 RLS 政策測試
-- =============================================

BEGIN;
SELECT plan(14);

-- =========== 測試準備 ===========

SELECT tests.create_test_user('11111111-1111-1111-1111-111111111111'::UUID, 'SellerA');
SELECT tests.create_test_user('22222222-2222-2222-2222-222222222222'::UUID, 'SellerB');
SELECT tests.create_test_user('33333333-3333-3333-3333-333333333333'::UUID, 'BuyerC');

-- 建立地點
SELECT tests.create_test_location('11111111-1111-1111-1111-111111111111'::UUID, true);
SELECT tests.create_test_location('22222222-2222-2222-2222-222222222222'::UUID, true);

-- 建立測試物品
SELECT tests.create_test_item(1001, '11111111-1111-1111-1111-111111111111'::UUID, 'iPhone 15', 20000, true);
SELECT tests.create_test_item(1002, '11111111-1111-1111-1111-111111111111'::UUID, '私人草稿', 100, false);  -- 未上架
SELECT tests.create_test_item(1003, '22222222-2222-2222-2222-222222222222'::UUID, 'Nike 運動鞋', 1500, true);

-- =========== SELECT 測試（買家視角）===========

SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333'::UUID);

-- 測試 1: 買家可以看到所有已上架物品
SELECT is(
  (SELECT COUNT(*) FROM public.items WHERE listing_status = true)::INTEGER,
  2,
  'RLS-ITEMS-001: 買家可以看到所有已上架物品'
);

-- 測試 2: 買家無法看到未上架物品
SELECT ok(
  NOT EXISTS(SELECT 1 FROM public.items WHERE title = '私人草稿'),
  'RLS-ITEMS-002: 買家無法看到未上架物品'
);

-- 測試 3: 買家可以看到物品詳情
SELECT is(
  (SELECT title FROM public.items WHERE id = 1001),
  'iPhone 15',
  'RLS-ITEMS-003: 買家可以查詢物品標題'
);

-- =========== SELECT 測試（賣家視角）===========

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

-- 測試 4: 賣家可以看到自己的所有物品（包含未上架）
SELECT is(
  (SELECT COUNT(*) FROM public.items WHERE user_id = auth.uid())::INTEGER,
  2,
  'RLS-ITEMS-004: 賣家可以看到自己的所有物品'
);

-- 測試 5: 賣家可以看到自己的未上架物品
SELECT ok(
  EXISTS(SELECT 1 FROM public.items WHERE id = 1002 AND listing_status = false),
  'RLS-ITEMS-005: 賣家可以看到自己的未上架物品'
);

-- =========== UPDATE 測試 ===========

-- 測試 6: 賣家可以更新自己物品的價格
UPDATE public.items SET price = 18000 WHERE id = 1001;

SELECT is(
  (SELECT price FROM public.items WHERE id = 1001),
  18000,
  'RLS-ITEMS-006: 賣家可以更新自己物品的價格'
);

-- 測試 7: 賣家可以更新上架狀態
UPDATE public.items SET listing_status = false WHERE id = 1001;

SELECT is(
  (SELECT listing_status FROM public.items WHERE id = 1001),
  false,
  'RLS-ITEMS-007: 賣家可以更新自己物品的上架狀態'
);

-- 恢復上架狀態
UPDATE public.items SET listing_status = true WHERE id = 1001;

-- 測試 8: 賣家無法更新他人物品的價格
UPDATE public.items SET price = 500 WHERE id = 1003;

SELECT is(
  (SELECT price FROM public.items WHERE id = 1003),
  1500,  -- 應該維持原值
  'RLS-ITEMS-008: 賣家無法更新他人物品的價格'
);

-- =========== DELETE 測試 ===========

-- 測試 9: 賣家可以刪除自己的物品
DELETE FROM public.items WHERE id = 1002;

SELECT ok(
  NOT EXISTS(SELECT 1 FROM public.items WHERE id = 1002),
  'RLS-ITEMS-009: 賣家可以刪除自己的物品'
);

-- 測試 10: 賣家無法刪除他人的物品
DELETE FROM public.items WHERE id = 1003;

SELECT ok(
  EXISTS(SELECT 1 FROM public.items WHERE id = 1003),
  'RLS-ITEMS-010: 賣家無法刪除他人的物品'
);

-- =========== INSERT 測試 ===========

-- 測試 11: 賣家可以新增自己的物品
INSERT INTO public.items (id, user_id, sub_category_id, title, condition, price, listing_status)
VALUES (1004, '11111111-1111-1111-1111-111111111111'::UUID, 1, '新物品', '全新', 5000, true);

SELECT ok(
  EXISTS(SELECT 1 FROM public.items WHERE id = 1004),
  'RLS-ITEMS-011: 賣家可以新增自己的物品'
);

-- 測試 12: 無法為他人新增物品
INSERT INTO public.items (id, user_id, sub_category_id, title, condition, price)
VALUES (1005, '22222222-2222-2222-2222-222222222222'::UUID, 1, '偽造物品', '全新', 1000);

SELECT ok(
  NOT EXISTS(SELECT 1 FROM public.items WHERE id = 1005),
  'RLS-ITEMS-012: 無法為他人新增物品'
);

-- =========== 匿名用戶測試 ===========

SELECT tests.authenticate_as_anon();

-- 測試 13: 匿名用戶無法看到任何物品
SELECT is(
  (SELECT COUNT(*) FROM public.items)::INTEGER,
  0,
  'RLS-ITEMS-013: 匿名用戶無法看到任何物品'
);

-- 測試 14: 匿名用戶無法新增物品
SELECT throws_ok(
  $$ INSERT INTO public.items (user_id, sub_category_id, title, condition, price)
     VALUES (gen_random_uuid(), 1, '匿名物品', '全新', 1000) $$,
  NULL,
  'RLS-ITEMS-014: 匿名用戶無法新增物品'
);

SELECT * FROM finish();
ROLLBACK;
```

### 4.6 RLS 政策測試 - transactions 表

```sql
-- supabase/tests/database/05_rls_transactions.test.sql
-- =============================================
-- transactions 表 RLS 政策測試
-- =============================================

BEGIN;
SELECT plan(10);

-- =========== 測試準備 ===========

SELECT tests.create_test_user('11111111-1111-1111-1111-111111111111'::UUID, 'Seller', 10000);
SELECT tests.create_test_user('22222222-2222-2222-2222-222222222222'::UUID, 'Buyer', 10000);
SELECT tests.create_test_user('33333333-3333-3333-3333-333333333333'::UUID, 'Outsider', 10000);

SELECT tests.create_test_location('11111111-1111-1111-1111-111111111111'::UUID, true);
SELECT tests.create_test_item(2001, '11111111-1111-1111-1111-111111111111'::UUID, '測試商品', 1000, true);

-- 建立測試交易
INSERT INTO public.transactions (
  id, item_id, giver_id, receiver_id, 
  points_amount, carbon_amount_kg, status, code
)
VALUES (
  3001, 2001, 
  '11111111-1111-1111-1111-111111111111'::UUID,
  '22222222-2222-2222-2222-222222222222'::UUID,
  1000, 2.0, 'confirming', '123456'
);

-- =========== SELECT 測試（賣家）===========

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

-- 測試 1: 賣家可以看到自己參與的交易
SELECT ok(
  EXISTS(SELECT 1 FROM public.transactions WHERE id = 3001),
  'RLS-TXN-001: 賣家可以看到自己參與的交易'
);

-- 測試 2: 賣家可以看到確認碼
SELECT is(
  (SELECT code FROM public.transactions WHERE id = 3001),
  '123456',
  'RLS-TXN-002: 賣家可以看到確認碼'
);

-- =========== SELECT 測試（買家）===========

SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222'::UUID);

-- 測試 3: 買家可以看到自己參與的交易
SELECT ok(
  EXISTS(SELECT 1 FROM public.transactions WHERE id = 3001),
  'RLS-TXN-003: 買家可以看到自己參與的交易'
);

-- 測試 4: 買家在 pending 狀態前不能看到確認碼
-- （這個測試取決於你的 RLS 策略設計）
-- 如果策略允許買家看到確認碼，調整測試

-- =========== SELECT 測試（外部人員）===========

SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333'::UUID);

-- 測試 5: 無關人員無法看到交易
SELECT ok(
  NOT EXISTS(SELECT 1 FROM public.transactions WHERE id = 3001),
  'RLS-TXN-004: 無關人員無法看到他人的交易'
);

-- =========== UPDATE 測試 ===========

SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222'::UUID);

-- 測試 6: 買家不能直接更新交易狀態（應透過 RPC）
UPDATE public.transactions SET status = 'completed' WHERE id = 3001;

SELECT is(
  (SELECT status FROM public.transactions WHERE id = 3001),
  'confirming',  -- 應該維持原狀態
  'RLS-TXN-005: 買家不能直接更新交易狀態'
);

-- 測試 7: 買家不能直接修改確認碼
UPDATE public.transactions SET code = '999999' WHERE id = 3001;

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);
SELECT is(
  (SELECT code FROM public.transactions WHERE id = 3001),
  '123456',  -- 應該維持原值
  'RLS-TXN-006: 買家不能直接修改確認碼'
);

-- =========== INSERT 測試 ===========

SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222'::UUID);

-- 測試 8: 用戶不能直接插入交易（應透過 RPC）
SELECT throws_ok(
  $$ INSERT INTO public.transactions (item_id, giver_id, receiver_id, points_amount, carbon_amount_kg, code)
     VALUES (2001, '11111111-1111-1111-1111-111111111111'::UUID, 
             '22222222-2222-2222-2222-222222222222'::UUID, 1000, 2.0, '000000') $$,
  NULL,
  'RLS-TXN-007: 用戶不能直接插入交易記錄'
);

-- =========== DELETE 測試 ===========

-- 測試 9: 用戶不能刪除交易記錄
DELETE FROM public.transactions WHERE id = 3001;

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);
SELECT ok(
  EXISTS(SELECT 1 FROM public.transactions WHERE id = 3001),
  'RLS-TXN-008: 用戶不能刪除交易記錄'
);

-- =========== 匿名用戶測試 ===========

SELECT tests.authenticate_as_anon();

-- 測試 10: 匿名用戶無法看到任何交易
SELECT is(
  (SELECT COUNT(*) FROM public.transactions)::INTEGER,
  0,
  'RLS-TXN-009: 匿名用戶無法看到任何交易'
);

SELECT * FROM finish();
ROLLBACK;
```

---

## 5. RPC 函數測試

### 5.1 交易系統 RPC 測試

```sql
-- supabase/tests/database/10_rpc_transactions.test.sql
-- =============================================
-- 交易系統 RPC 函數測試
-- =============================================

BEGIN;
SELECT plan(20);

-- =========== 測試準備 ===========

SELECT tests.create_test_user('11111111-1111-1111-1111-111111111111'::UUID, 'Seller', 10000);
SELECT tests.create_test_user('22222222-2222-2222-2222-222222222222'::UUID, 'Buyer', 5000);
SELECT tests.create_test_user('33333333-3333-3333-3333-333333333333'::UUID, 'PoorBuyer', 100);

SELECT tests.create_test_location('11111111-1111-1111-1111-111111111111'::UUID, true);

SELECT tests.create_test_item(4001, '11111111-1111-1111-1111-111111111111'::UUID, '測試商品A', 1000, true);
SELECT tests.create_test_item(4002, '11111111-1111-1111-1111-111111111111'::UUID, '測試商品B', 2000, true);
SELECT tests.create_test_item(4003, '11111111-1111-1111-1111-111111111111'::UUID, '昂貴商品', 10000, true);

-- =========== initiate_transaction 測試 ===========

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

-- 測試 1: 賣家可以發起交易
SELECT ok(
  (SELECT (initiate_transaction(4001, '22222222-2222-2222-2222-222222222222'::UUID))->>'status') = 'confirming',
  'RPC-TXN-001: 賣家可以發起交易，狀態為 confirming'
);

-- 測試 2: 交易生成 6 位數確認碼
SELECT is(
  LENGTH((SELECT code FROM public.transactions WHERE item_id = 4001)),
  6,
  'RPC-TXN-002: 交易生成 6 位數確認碼'
);

-- 測試 3: 發起交易後物品自動下架
SELECT is(
  (SELECT listing_status FROM public.items WHERE id = 4001),
  false,
  'RPC-TXN-003: 發起交易後物品自動下架'
);

-- 測試 4: 不能對同一物品重複發起交易
SELECT throws_ok(
  $$ SELECT initiate_transaction(4001, '33333333-3333-3333-3333-333333333333'::UUID) $$,
  NULL,
  'RPC-TXN-004: 不能對同一物品重複發起交易'
);

-- 測試 5: 賣家不能對自己發起交易
SELECT throws_ok(
  $$ SELECT initiate_transaction(4002, '11111111-1111-1111-1111-111111111111'::UUID) $$,
  NULL,
  'RPC-TXN-005: 賣家不能對自己發起交易'
);

-- =========== get_my_transactions_by_status 測試 ===========

-- 測試 6: 賣家可以查詢確認中的交易
SELECT ok(
  (SELECT COUNT(*) FROM get_my_transactions_by_status('confirming', 'giver'))::INTEGER > 0,
  'RPC-TXN-006: 賣家可以查詢確認中的交易'
);

-- 測試 7: 買家可以查詢確認中的交易
SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222'::UUID);

SELECT ok(
  (SELECT COUNT(*) FROM get_my_transactions_by_status('confirming', 'receiver'))::INTEGER > 0,
  'RPC-TXN-007: 買家可以查詢確認中的交易'
);

-- =========== update_giver_note 測試 ===========

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

-- 測試 8: 賣家可以更新備註
SELECT ok(
  (SELECT (update_giver_note(
    (SELECT id FROM public.transactions WHERE item_id = 4001),
    '請在校門口等我'
  ))->>'success')::BOOLEAN,
  'RPC-TXN-008: 賣家可以更新備註'
);

-- 測試 9: 備註正確儲存
SELECT is(
  (SELECT giver_note FROM public.transactions WHERE item_id = 4001),
  '請在校門口等我',
  'RPC-TXN-009: 備註正確儲存'
);

-- =========== buyer_confirm_transaction 測試 ===========

SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222'::UUID);

-- 測試 10: 買家確認交易，狀態變為 pending
SELECT is(
  (SELECT (buyer_confirm_transaction(
    (SELECT id FROM public.transactions WHERE item_id = 4001),
    '好的，我會準時到'
  ))->>'new_status'),
  'pending',
  'RPC-TXN-010: 買家確認後，交易狀態變為 pending'
);

-- 測試 11: 買家備註正確儲存
SELECT is(
  (SELECT receiver_note FROM public.transactions WHERE item_id = 4001),
  '好的，我會準時到',
  'RPC-TXN-011: 買家備註正確儲存'
);

-- =========== complete_transaction 測試 ===========

-- 取得確認碼
DO $$
DECLARE
  v_code TEXT;
  v_txn_id BIGINT;
  v_result JSONB;
BEGIN
  SELECT id, code INTO v_txn_id, v_code 
  FROM public.transactions WHERE item_id = 4001;
  
  -- 測試 12: 錯誤的確認碼無法完成交易
  BEGIN
    PERFORM complete_transaction(v_txn_id, '000000');
    RAISE EXCEPTION '不應該執行到這裡';
  EXCEPTION WHEN OTHERS THEN
    -- 預期會失敗
  END;
  
  -- 測試 13: 正確的確認碼可以完成交易
  SELECT complete_transaction(v_txn_id, v_code) INTO v_result;
  
  IF (v_result->>'success')::BOOLEAN THEN
    RAISE NOTICE 'RPC-TXN-012: 完成交易成功';
  END IF;
END $$;

-- 測試 14: 交易狀態變為 completed
SELECT is(
  (SELECT status FROM public.transactions WHERE item_id = 4001),
  'completed',
  'RPC-TXN-012: 交易狀態變為 completed'
);

-- 測試 15: 買家點數正確扣除（5000 - 1000 = 4000）
SELECT is(
  (SELECT balance FROM public.profiles WHERE user_id = '22222222-2222-2222-2222-222222222222'::UUID),
  4000,
  'RPC-TXN-013: 買家點數正確扣除'
);

-- 測試 16: 賣家點數正確增加（10000 + 1000 = 11000）
SELECT is(
  (SELECT balance FROM public.profiles WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID),
  11000,
  'RPC-TXN-014: 賣家點數正確增加'
);

-- 測試 17: 碳足跡正確累計
SELECT ok(
  (SELECT carbon_saved_kg FROM public.profiles WHERE user_id = '22222222-2222-2222-2222-222222222222'::UUID) > 0,
  'RPC-TXN-015: 買家碳足跡正確累計'
);

-- 測試 18: 點數記錄正確寫入
SELECT ok(
  EXISTS(
    SELECT 1 FROM public.point_logs 
    WHERE user_id = '22222222-2222-2222-2222-222222222222'::UUID
    AND amount = -1000
  ),
  'RPC-TXN-016: 買家扣款記錄正確寫入'
);

-- =========== cancel_transaction 測試 ===========

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);
SELECT initiate_transaction(4002, '22222222-2222-2222-2222-222222222222'::UUID);

-- 測試 19: 取消交易後物品重新上架
SELECT ok(
  (SELECT (cancel_transaction(
    (SELECT id FROM public.transactions WHERE item_id = 4002)
  ))->>'new_status') = 'cancelled',
  'RPC-TXN-017: 可以取消交易'
);

SELECT is(
  (SELECT listing_status FROM public.items WHERE id = 4002),
  true,
  'RPC-TXN-018: 取消交易後物品重新上架'
);

-- =========== 餘額不足測試 ===========

SELECT initiate_transaction(4003, '33333333-3333-3333-3333-333333333333'::UUID);

SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333'::UUID);

-- 測試 20: 餘額不足時無法確認交易
SELECT throws_ok(
  $$ SELECT buyer_confirm_transaction(
       (SELECT id FROM public.transactions WHERE item_id = 4003),
       '確認購買'
     ) $$,
  NULL,
  'RPC-TXN-019: 餘額不足時無法確認交易'
);

SELECT * FROM finish();
ROLLBACK;
```

### 5.2 每日簽到 RPC 測試

```sql
-- supabase/tests/database/12_rpc_daily_signin.test.sql
-- =============================================
-- 每日簽到系統 RPC 測試
-- =============================================

BEGIN;
SELECT plan(12);

-- =========== 測試準備 ===========

SELECT tests.create_test_user('11111111-1111-1111-1111-111111111111'::UUID, 'SignInUser', 10000);
SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111'::UUID);

-- =========== 基本簽到測試 ===========

-- 測試 1: 首次簽到成功
SELECT ok(
  (SELECT (daily_check_in())->>'success')::BOOLEAN,
  'RPC-SIGNIN-001: 首次簽到成功'
);

-- 測試 2: 首次簽到獲得基本點數（5 點）
SELECT is(
  (SELECT (daily_check_in())->>'points_awarded')::INTEGER,
  0,  -- 因為已經簽到過，返回 0
  'RPC-SIGNIN-002: 重複簽到返回 0 點'
);

-- 模擬清除今日簽到狀態以進行更多測試
UPDATE public.profiles 
SET last_check_in_date = NULL, check_in_streak = 0
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- 測試 3: 重新簽到獲得 5 點
SELECT is(
  (SELECT (daily_check_in())->>'points_awarded')::INTEGER,
  5,
  'RPC-SIGNIN-003: 首次簽到獲得 5 點'
);

-- 測試 4: 連續天數為 1
SELECT is(
  (SELECT check_in_streak FROM public.profiles 
   WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID),
  1,
  'RPC-SIGNIN-004: 首次簽到連續天數為 1'
);

-- =========== 重複簽到測試 ===========

-- 測試 5: 今天已簽到過不能重複
SELECT is(
  (SELECT (daily_check_in())->>'success')::BOOLEAN,
  false,
  'RPC-SIGNIN-005: 今天已簽到過不能重複'
);

-- 測試 6: 重複簽到返回正確訊息
SELECT ok(
  (SELECT (daily_check_in())->>'message') LIKE '%已經簽到%',
  'RPC-SIGNIN-006: 重複簽到返回正確訊息'
);

-- =========== 連續簽到獎勵測試 ===========

-- 模擬連續第 3 天
UPDATE public.profiles SET 
  last_check_in_date = (CURRENT_DATE AT TIME ZONE 'Asia/Taipei') - INTERVAL '1 day',
  check_in_streak = 2
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- 測試 7: 連續第 3 天獲得 10 點
SELECT is(
  (SELECT (daily_check_in())->>'points_awarded')::INTEGER,
  10,
  'RPC-SIGNIN-007: 連續第 3 天獲得 10 點'
);

-- 模擬連續第 7 天
UPDATE public.profiles SET 
  last_check_in_date = (CURRENT_DATE AT TIME ZONE 'Asia/Taipei') - INTERVAL '1 day',
  check_in_streak = 6
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- 測試 8: 連續第 7 天獲得 20 點
SELECT is(
  (SELECT (daily_check_in())->>'points_awarded')::INTEGER,
  20,
  'RPC-SIGNIN-008: 連續第 7 天獲得 20 點'
);

-- =========== 中斷簽到測試 ===========

-- 模擬中斷 3 天後重新簽到
UPDATE public.profiles SET 
  last_check_in_date = (CURRENT_DATE AT TIME ZONE 'Asia/Taipei') - INTERVAL '3 day',
  check_in_streak = 10
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

-- 測試 9: 中斷後連續天數重置為 1
SELECT daily_check_in();

SELECT is(
  (SELECT check_in_streak FROM public.profiles 
   WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID),
  1,
  'RPC-SIGNIN-009: 中斷後連續天數重置為 1'
);

-- =========== 點數累計測試 ===========

-- 測試 10: 簽到獲得的點數正確累計到餘額
SELECT ok(
  (SELECT balance FROM public.profiles 
   WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID) > 10000,
  'RPC-SIGNIN-010: 簽到獲得的點數正確累計到餘額'
);

-- 測試 11: 簽到記錄正確寫入 point_logs
SELECT ok(
  EXISTS(
    SELECT 1 FROM public.point_logs 
    WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID
    AND reason LIKE '%簽到%'
  ),
  'RPC-SIGNIN-011: 簽到記錄正確寫入 point_logs'
);

-- =========== 徽章整合測試 ===========

-- 測試 12: 簽到結果包含徽章資訊
UPDATE public.profiles SET 
  last_check_in_date = (CURRENT_DATE AT TIME ZONE 'Asia/Taipei') - INTERVAL '1 day',
  check_in_streak = 6
WHERE user_id = '11111111-1111-1111-1111-111111111111'::UUID;

SELECT ok(
  (SELECT (daily_check_in())->'badges' IS NOT NULL),
  'RPC-SIGNIN-012: 簽到結果包含徽章資訊'
);

SELECT * FROM finish();
ROLLBACK;
```

### 5.3 搜尋功能 RPC 測試

```sql
-- supabase/tests/database/11_rpc_search.test.sql
-- =============================================
-- 搜尋功能 RPC 測試
-- =============================================

BEGIN;
SELECT plan(10);

-- =========== 測試準備 ===========

SELECT tests.create_test_user('11111111-1111-1111-1111-111111111111'::UUID, 'SellerA');
SELECT tests.create_test_user('22222222-2222-2222-2222-222222222222'::UUID, 'SellerB');
SELECT tests.create_test_user('33333333-3333-3333-3333-333333333333'::UUID, 'Buyer');

-- 建立地點
SELECT tests.create_test_location('11111111-1111-1111-1111-111111111111'::UUID, true);
SELECT tests.create_test_location('22222222-2222-2222-2222-222222222222'::UUID, true);
SELECT tests.create_test_location('33333333-3333-3333-3333-333333333333'::UUID, true);

-- 建立測試物品
SELECT tests.create_test_item(5001, '11111111-1111-1111-1111-111111111111'::UUID, 'iPhone 15 Pro', 35000, true);
SELECT tests.create_test_item(5002, '11111111-1111-1111-1111-111111111111'::UUID, 'MacBook Air', 25000, true);
SELECT tests.create_test_item(5003, '22222222-2222-2222-2222-222222222222'::UUID, 'Nike 運動鞋', 2000, true);
SELECT tests.create_test_item(5004, '11111111-1111-1111-1111-111111111111'::UUID, '未上架物品', 1000, false);

SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333'::UUID);

-- =========== 基本搜尋測試 ===========

-- 測試 1: 搜尋返回結果
SELECT ok(
  (SELECT COUNT(*) FROM search_items(null, null, null, null, null, 1, 10, 'created_at', 'desc'))::INTEGER > 0,
  'RPC-SEARCH-001: 搜尋返回結果'
);

-- 測試 2: 只返回已上架物品
SELECT ok(
  NOT EXISTS(
    SELECT 1 FROM search_items(null, null, null, null, null, 1, 100, 'created_at', 'desc')
    WHERE title = '未上架物品'
  ),
  'RPC-SEARCH-002: 只返回已上架物品'
);

-- 測試 3: 關鍵字搜尋有效
SELECT ok(
  (SELECT COUNT(*) FROM search_items(null, null, null, 'iPhone', null, 1, 10, 'created_at', 'desc'))::INTEGER = 1,
  'RPC-SEARCH-003: 關鍵字搜尋 iPhone 返回 1 筆'
);

-- 測試 4: 結果包含距離資訊
SELECT ok(
  (SELECT distance_km FROM search_items(null, null, null, null, null, 1, 1, 'created_at', 'desc') LIMIT 1) IS NOT NULL,
  'RPC-SEARCH-004: 結果包含距離資訊'
);

-- 測試 5: 結果包含賣家資訊
SELECT ok(
  (SELECT (item_row).user FROM search_items(null, null, null, null, null, 1, 1, 'created_at', 'desc') AS item_row LIMIT 1) IS NOT NULL,
  'RPC-SEARCH-005: 結果包含賣家資訊'
);

-- =========== 分頁測試 ===========

-- 測試 6: 分頁功能正常
SELECT is(
  (SELECT COUNT(*) FROM search_items(null, null, null, null, null, 1, 2, 'created_at', 'desc'))::INTEGER,
  2,
  'RPC-SEARCH-006: 分頁限制 2 筆正常'
);

-- =========== 排序測試 ===========

-- 測試 7: 按價格排序
SELECT ok(
  (SELECT price FROM search_items(null, null, null, null, null, 1, 1, 'price', 'desc') LIMIT 1) >= 
  (SELECT price FROM search_items(null, null, null, null, null, 1, 1, 'price', 'asc') LIMIT 1),
  'RPC-SEARCH-007: 按價格排序正常'
);

-- =========== 分類篩選測試 ===========

-- 測試 8: 主分類篩選（假設分類 ID 1 = 電子產品）
SELECT ok(
  (SELECT COUNT(*) FROM search_items(null, 1, null, null, null, 1, 100, 'created_at', 'desc'))::INTEGER >= 0,
  'RPC-SEARCH-008: 主分類篩選正常'
);

-- =========== 距離篩選測試 ===========

-- 測試 9: 距離篩選（5 公里內）
SELECT ok(
  (SELECT COUNT(*) FROM search_items(5, null, null, null, null, 1, 100, 'created_at', 'desc'))::INTEGER >= 0,
  'RPC-SEARCH-009: 距離篩選正常'
);

-- =========== 錯誤處理測試 ===========

-- 測試 10: 無效分頁參數處理
SELECT throws_ok(
  $$ SELECT * FROM search_items(null, null, null, null, null, 0, 10, 'created_at', 'desc') $$,
  NULL,
  'RPC-SEARCH-010: 無效分頁參數拋出錯誤'
);

SELECT * FROM finish();
ROLLBACK;
```

---

## 6. Edge Functions 測試

### 6.1 Deno 測試設置

```typescript
// supabase/functions/analyze-item-image/index.test.ts
import { assertEquals, assertExists } from "https://deno.land/std@0.192.0/testing/asserts.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "http://localhost:54321";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

Deno.test("analyze-item-image: 應該返回分析結果", async () => {
  const response = await fetch(`${supabaseUrl}/functions/v1/analyze-item-image`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${supabaseAnonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      imageUrl: "https://example.com/test-image.jpg",
    }),
  });

  assertEquals(response.status, 200);
  
  const data = await response.json();
  assertExists(data.title);
  assertExists(data.description);
  assertExists(data.category);
});

Deno.test("analyze-item-image: 缺少圖片 URL 應返回錯誤", async () => {
  const response = await fetch(`${supabaseUrl}/functions/v1/analyze-item-image`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${supabaseAnonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({}),
  });

  assertEquals(response.status, 400);
});

Deno.test("analyze-item-image: 未認證請求應被拒絕", async () => {
  const response = await fetch(`${supabaseUrl}/functions/v1/analyze-item-image`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      imageUrl: "https://example.com/test-image.jpg",
    }),
  });

  assertEquals(response.status, 401);
});
```

### 6.2 執行 Edge Functions 測試

```bash
# 確保 Edge Functions 正在運行
npx supabase functions serve

# 執行測試
cd supabase/functions
deno test --allow-all --env=.env.local
```

---

## 7. API 整合測試

### 7.1 整合測試設置

```typescript
// tests/api/setup.ts
import { createClient, SupabaseClient } from "@supabase/supabase-js";

export const supabaseUrl = process.env.PUBLIC_SUPABASE_URL || "http://localhost:54321";
export const supabaseAnonKey = process.env.PUBLIC_SUPABASE_ANON_KEY || "";
export const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || "";

// 一般用戶客戶端
export const supabase: SupabaseClient = createClient(supabaseUrl, supabaseAnonKey);

// 管理員客戶端（用於測試資料設置/清理）
export const adminClient: SupabaseClient = createClient(supabaseUrl, supabaseServiceKey);

// 測試用戶資訊
export interface TestUser {
  id: string;
  email: string;
  password: string;
}

// 建立測試用戶
export async function createTestUser(nickname: string): Promise<TestUser> {
  const email = `${nickname.toLowerCase()}-${Date.now()}@test.fcu.edu.tw`;
  const password = "testpassword123";

  const { data, error } = await supabase.auth.signUp({
    email,
    password,
  });

  if (error) throw error;

  return {
    id: data.user!.id,
    email,
    password,
  };
}

// 以特定用戶登入
export async function signInAs(user: TestUser): Promise<void> {
  const { error } = await supabase.auth.signInWithPassword({
    email: user.email,
    password: user.password,
  });

  if (error) throw error;
}

// 清理測試用戶資料
export async function cleanupTestUser(userId: string): Promise<void> {
  // 使用 admin client 清理資料
  await adminClient.from("transactions").delete().or(`giver_id.eq.${userId},receiver_id.eq.${userId}`);
  await adminClient.from("items").delete().eq("user_id", userId);
  await adminClient.from("locations").delete().eq("user_id", userId);
  await adminClient.from("profiles").delete().eq("user_id", userId);
  await adminClient.from("users").delete().eq("id", userId);
  await adminClient.auth.admin.deleteUser(userId);
}
```

### 7.2 交易 API 整合測試

```typescript
// tests/api/transactions.api.test.ts
import { 
  supabase, 
  createTestUser, 
  signInAs, 
  cleanupTestUser,
  adminClient,
  TestUser 
} from "./setup";

describe("交易 API 整合測試", () => {
  let seller: TestUser;
  let buyer: TestUser;
  let itemId: number;
  let transactionId: number;
  let confirmCode: string;

  beforeAll(async () => {
    // 建立賣家
    seller = await createTestUser("IntegrationSeller");
    await signInAs(seller);

    // 建立地點
    await supabase.from("locations").insert({
      user_id: seller.id,
      coordinates: "POINT(120.6478 24.1797)",
      type: "公司",
      is_primary: true,
      formatted_address: "逢甲大學",
    });

    // 建立物品
    const { data: item } = await supabase
      .from("items")
      .insert({
        user_id: seller.id,
        sub_category_id: 1,
        title: "整合測試商品",
        condition: "良好",
        price: 1000,
        listing_status: true,
        carbon_value: 2.0,
      })
      .select()
      .single();

    itemId = item!.id;

    // 建立買家
    await supabase.auth.signOut();
    buyer = await createTestUser("IntegrationBuyer");
  });

  afterAll(async () => {
    await cleanupTestUser(seller.id);
    await cleanupTestUser(buyer.id);
  });

  test("完整交易流程", async () => {
    // Step 1: 賣家發起交易
    await signInAs(seller);

    const { data: initResult, error: initError } = await supabase.rpc(
      "initiate_transaction",
      {
        p_item_id: itemId,
        p_receiver_id: buyer.id,
      }
    );

    expect(initError).toBeNull();
    expect(initResult.status).toBe("confirming");
    expect(initResult.code).toHaveLength(6);

    transactionId = initResult.transaction_id;
    confirmCode = initResult.code;

    // Step 2: 驗證物品已下架
    const { data: item } = await supabase
      .from("items")
      .select("listing_status")
      .eq("id", itemId)
      .single();

    expect(item!.listing_status).toBe(false);

    // Step 3: 買家確認交易
    await signInAs(buyer);

    const { data: confirmResult, error: confirmError } = await supabase.rpc(
      "buyer_confirm_transaction",
      {
        p_transaction_id: transactionId,
        p_note: "我會準時到",
      }
    );

    expect(confirmError).toBeNull();
    expect(confirmResult.new_status).toBe("pending");

    // Step 4: 買家輸入確認碼完成交易
    const { data: completeResult, error: completeError } = await supabase.rpc(
      "complete_transaction",
      {
        p_transaction_id: transactionId,
        p_code: confirmCode,
      }
    );

    expect(completeError).toBeNull();
    expect(completeResult.success).toBe(true);

    // Step 5: 驗證點數轉移
    const { data: buyerProfile } = await supabase
      .from("profiles")
      .select("balance")
      .eq("user_id", buyer.id)
      .single();

    expect(buyerProfile!.balance).toBe(9000); // 10000 - 1000
  });
});
```

### 7.3 執行 API 整合測試

```bash
# 確保本地 Supabase 正在運行
npx supabase start

# 執行整合測試
npm run test:api
```

---

## 8. CI/CD 自動化測試

### 8.1 GitHub Actions 配置

```yaml
# .github/workflows/backend-tests.yml
name: FCU Sigma 後端測試

on:
  push:
    branches: [main, develop]
    paths:
      - "backend/supabase/**"
      - "backend/tests/**"
  pull_request:
    branches: [main]
    paths:
      - "backend/supabase/**"

env:
  SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}

jobs:
  # ==========================================
  # 資料庫測試
  # ==========================================
  database-tests:
    name: 📊 資料庫測試 (pgTAP)
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
      
      - name: 執行 RLS 政策測試
        run: |
          cd backend
          supabase test db --file 01_rls_users.test.sql
          supabase test db --file 02_rls_profiles.test.sql
          supabase test db --file 03_rls_items.test.sql
          supabase test db --file 05_rls_transactions.test.sql
      
      - name: 執行 RPC 函數測試
        run: |
          cd backend
          supabase test db --file 10_rpc_transactions.test.sql
          supabase test db --file 11_rpc_search.test.sql
          supabase test db --file 12_rpc_daily_signin.test.sql
      
      - name: 停止 Supabase
        if: always()
        run: |
          cd backend
          supabase stop

  # ==========================================
  # Edge Functions 測試
  # ==========================================
  edge-functions-tests:
    name: ⚡ Edge Functions 測試
    runs-on: ubuntu-latest
    needs: database-tests
    
    steps:
      - name: 檢出代碼
        uses: actions/checkout@v4
      
      - name: 設置 Deno
        uses: denoland/setup-deno@v1
        with:
          deno-version: v1.x
      
      - name: 設置 Supabase CLI
        uses: supabase/setup-cli@v1
        with:
          version: latest
      
      - name: 啟動 Supabase 和 Edge Functions
        run: |
          cd backend
          supabase start
          supabase functions serve &
          sleep 5
      
      - name: 執行 Edge Functions 測試
        run: |
          cd backend/supabase/functions
          deno test --allow-all
        env:
          SUPABASE_URL: http://localhost:54321
          SUPABASE_ANON_KEY: ${{ secrets.SUPABASE_LOCAL_ANON_KEY }}
      
      - name: 停止服務
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
    needs: [database-tests, edge-functions-tests]
    if: always()
    
    steps:
      - name: 生成測試報告
        run: |
          echo "## 🧪 FCU Sigma 後端測試結果" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| 測試類型 | 狀態 |" >> $GITHUB_STEP_SUMMARY
          echo "|----------|------|" >> $GITHUB_STEP_SUMMARY
          echo "| 資料庫測試 (pgTAP) | ${{ needs.database-tests.result == 'success' && '✅ 通過' || '❌ 失敗' }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Edge Functions 測試 | ${{ needs.edge-functions-tests.result == 'success' && '✅ 通過' || '❌ 失敗' }} |" >> $GITHUB_STEP_SUMMARY
```

---

## 9. 測試案例總表

### 9.1 RLS 政策測試案例

| ID | 資料表 | 測試案例 | 優先級 | 狀態 |
|:--:|--------|----------|:------:|:----:|
| RLS-001 | users | 已登入用戶可查看他人公開資訊 | P0 | ⬜ |
| RLS-002 | users | 用戶只能更新自己的資料 | P0 | ⬜ |
| RLS-003 | users | 用戶不能修改 avg_rating | P0 | ⬜ |
| RLS-004 | users | 匿名用戶無法存取 | P0 | ⬜ |
| RLS-005 | profiles | 用戶只能查看自己的餘額 | P0 | ⬜ |
| RLS-006 | profiles | 用戶不能直接修改 balance | P0 | ⬜ |
| RLS-007 | items | 可看到所有已上架物品 | P0 | ⬜ |
| RLS-008 | items | 無法看到未上架物品 | P0 | ⬜ |
| RLS-009 | items | 只能編輯/刪除自己的物品 | P0 | ⬜ |
| RLS-010 | transactions | 只能看到自己參與的交易 | P0 | ⬜ |
| RLS-011 | transactions | 不能直接修改交易狀態 | P0 | ⬜ |

### 9.2 RPC 函數測試案例

| ID | 函數 | 測試案例 | 優先級 | 狀態 |
|:--:|------|----------|:------:|:----:|
| RPC-TXN-001 | initiate_transaction | 賣家可發起交易 | P0 | ⬜ |
| RPC-TXN-002 | initiate_transaction | 生成 6 位確認碼 | P0 | ⬜ |
| RPC-TXN-003 | initiate_transaction | 物品自動下架 | P0 | ⬜ |
| RPC-TXN-004 | buyer_confirm | 狀態變 pending | P0 | ⬜ |
| RPC-TXN-005 | complete_transaction | 點數正確轉移 | P0 | ⬜ |
| RPC-TXN-006 | cancel_transaction | 物品重新上架 | P1 | ⬜ |
| RPC-SIGNIN-001 | daily_check_in | 首次簽到獲 5 點 | P1 | ⬜ |
| RPC-SIGNIN-002 | daily_check_in | 不能重複簽到 | P1 | ⬜ |
| RPC-SIGNIN-003 | daily_check_in | 連續獎勵正確 | P1 | ⬜ |
| RPC-SEARCH-001 | search_items | 返回已上架物品 | P1 | ⬜ |
| RPC-SEARCH-002 | search_items | 關鍵字搜尋有效 | P1 | ⬜ |

### 9.3 測試覆蓋率目標

| 模組 | 目標 | 說明 |
|------|:----:|------|
| RLS 政策 | 100% | 安全性關鍵 |
| 交易 RPC | 100% | 核心業務 |
| 簽到 RPC | 80% | 重要功能 |
| 搜尋 RPC | 80% | 重要功能 |
| Edge Functions | 60% | 輔助功能 |

---

## 10. 簡報大綱

### 10.1 簡報結構 (12 分鐘)

```
📽️ FCU Sigma 後端軟體測試策略報告
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

▸ 第一部分：專案與後端架構 (2 分鐘)
  • Supabase 後端架構介紹
  • 為什麼業務邏輯在資料庫層？
  • 後端測試的重要性

▸ 第二部分：測試策略 (2 分鐘)
  • 後端專用測試金字塔
  • pgTAP 資料庫測試框架介紹
  • 測試優先順序

▸ 第三部分：核心測試展示 (5 分鐘)
  • RLS 政策測試 Demo
  • 交易 RPC 測試 Demo
  • 測試執行結果展示

▸ 第四部分：CI/CD 與結論 (3 分鐘)
  • GitHub Actions 配置
  • 心得與挑戰
  • Q&A
```

### 10.2 重點投影片建議

**投影片 1：後端架構圖**
```
展示 Supabase 後端架構，強調：
• 所有業務邏輯在 PostgreSQL
• RLS 是權限的唯一防線
• 沒有傳統後端程式碼
```

**投影片 2：為什麼使用 pgTAP？**
```
| 傳統後端 | Supabase 後端 |
|----------|---------------|
| Jest/Mocha | pgTAP |
| API 測試 | RPC 測試 |
| 中間件測試 | RLS 測試 |

→ 直接在資料庫層測試業務邏輯
```

**投影片 3：測試金字塔**
```
          API 整合 (15%)
       Edge Functions (10%)
      RPC 函數測試 (30%)
     RLS 政策測試 (30%)
    觸發器/約束 (15%)
```

**投影片 4-6：測試 Demo**
```
• 展示 pgTAP 測試程式碼
• 執行 supabase test db
• 展示測試結果輸出
```

---

## 11. 附錄

### 11.1 常用測試命令

```bash
# 啟動/停止 Supabase
npx supabase start
npx supabase stop
npx supabase status

# 資料庫測試
npx supabase test db                    # 執行所有測試
npx supabase test db --file xxx.sql     # 執行特定測試
npx supabase test db --debug            # 詳細輸出

# 資料庫管理
npx supabase db reset                   # 重置資料庫
npx supabase db shell                   # 進入 psql

# Edge Functions
npx supabase functions serve            # 啟動 Functions
cd supabase/functions && deno test      # 測試 Functions
```

### 11.2 pgTAP 常用斷言

| 函數 | 用途 | 範例 |
|------|------|------|
| `ok(bool, msg)` | 驗證為真 | `ok(1=1, 'math works')` |
| `is(got, expected, msg)` | 驗證相等 | `is(balance, 1000, 'balance correct')` |
| `isnt(got, expected, msg)` | 驗證不相等 | `isnt(id, null, 'id exists')` |
| `throws_ok(sql, msg)` | 驗證拋出錯誤 | `throws_ok($$ INSERT... $$, 'blocked')` |
| `lives_ok(sql, msg)` | 驗證不拋錯誤 | `lives_ok($$ SELECT... $$, 'ok')` |

### 11.3 測試檢查清單

```markdown
## 後端測試提交前檢查清單

### 資料庫測試
- [ ] `npx supabase test db` 全部通過
- [ ] RLS 政策測試完整
- [ ] 交易 RPC 測試完整
- [ ] 簽到 RPC 測試完整

### Edge Functions
- [ ] `deno test` 通過
- [ ] 錯誤處理測試完整

### 程式碼品質
- [ ] 測試使用 ROLLBACK 確保獨立性
- [ ] 測試命名清晰
- [ ] 無硬編碼測試資料

### CI/CD
- [ ] GitHub Actions 通過
```

---

## 📝 文件資訊

| 項目 | 內容 |
|------|------|
| 文件名稱 | FCU Sigma 後端測試方案 |
| 版本 | v1.0 |
| 適用對象 | 後端開發團隊 |
| 主要工具 | pgTAP, Deno Test, Supabase CLI |
| 測試重點 | RLS 政策, RPC 函數, Edge Functions |

---

> 💡 **重點提醒**：後端測試的核心是確保 **RLS 政策** 和 **RPC 函數** 的正確性，因為這是整個系統安全性和業務邏輯的基礎。建議從 P0 優先級的測試開始實作。
