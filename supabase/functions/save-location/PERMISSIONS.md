# Edge Function 權限配置說明

## 📋 概述

`save-location` Edge Function 需要特定的資料庫權限才能正常運作。本文件說明權限配置的原理、設定方式和故障排除。

---

## 🔐 權限架構

### 1. Supabase 認證角色

Supabase 有三個主要的認證角色：

| 角色 | 說明 | 用途 |
|------|------|------|
| `anon` | 匿名角色 | 未登入的公開訪問 |
| `authenticated` | 已認證用戶 | 已登入的用戶操作 |
| `service_role` | 服務角色 | 後端服務、Edge Functions（**繞過 RLS**） |

### 2. Row Level Security (RLS)

- **RLS** 是 PostgreSQL 的安全功能，限制用戶只能存取特定的資料列
- **RLS 政策** 定義誰可以對哪些資料進行什麼操作
- **Service Role** 會**自動繞過 RLS**，這是 Edge Function 的關鍵

---

## 🎯 save-location 的權限需求

### Edge Function 的運作流程

```
1. 前端發送請求 → Authorization: Bearer {USER_JWT}
2. Edge Function 接收請求
3. 使用 USER_JWT 驗證用戶身份 → 確保是合法用戶
4. 使用 SERVICE_ROLE_KEY 執行資料庫操作 → 繞過 RLS
5. 成功儲存地點資料
```

### 為什麼需要 Service Role？

**問題**：用戶的 JWT token 受到 RLS 限制

```typescript
// ❌ 使用 Anon Key + User JWT（會受 RLS 限制）
const supabaseClient = createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  { global: { headers: { Authorization: userJWT } } }
)

// RLS 政策: "Users can insert own locations"
// WITH CHECK (auth.uid() = user_id)
// 
// 問題：Edge Function 在執行 INSERT 時，
// auth.uid() 可能無法正確識別，導致插入失敗
```

**解決方案**：使用 Service Role Key

```typescript
// ✅ 使用 Service Role Key（繞過 RLS）
const supabaseAdmin = createClient(
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY  // 關鍵！
)

// Service Role 會繞過所有 RLS 政策
// 可以直接 INSERT 任何 user_id 的資料
```

---

## 🛠️ 權限配置

### Migration: 20251107100000_fix_locations_permissions_for_edge_function_jo.sql

此 migration 配置了 `locations` 表的完整權限：

#### 1. RLS 政策（保護用戶資料）

```sql
-- ✓ 用戶只能查看自己的地點
CREATE POLICY "Users can view own locations"
ON public.locations
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- ✓ 用戶只能建立自己的地點
CREATE POLICY "Users can insert own locations"
ON public.locations
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- ✓ 用戶只能更新自己的地點
CREATE POLICY "Users can update own locations"
ON public.locations
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id);

-- ✓ 用戶只能刪除自己的地點
CREATE POLICY "Users can delete own locations"
ON public.locations
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);
```

#### 2. 表格權限（允許操作）

```sql
-- Authenticated 用戶的基本權限
GRANT SELECT, INSERT, UPDATE, DELETE ON public.locations TO authenticated;

-- Service Role 的完整權限（Edge Function 使用）
GRANT ALL ON public.locations TO service_role;

-- 序列權限（用於自動遞增 ID）
GRANT USAGE, SELECT ON SEQUENCE locations_id_seq TO authenticated, service_role;
```

---

## 🔍 權限驗證

### 執行測試函數

Migration 包含了一個測試函數，可以驗證權限是否正確設定：

```sql
SELECT * FROM test_locations_permissions();
```

**預期輸出**：

```
test_name                      | result | details
-------------------------------|--------|----------------------------------
RLS Status                     | PASS   | RLS is enabled
Policy Count                   | PASS   | Found 4 policies (expected 4+)
Authenticated Role Permissions | PASS   | Checking SELECT, INSERT, UPDATE, DELETE permissions
Service Role Permissions       | PASS   | Checking service_role has permissions
```

### 檢查 RLS 政策

```sql
SELECT
    policyname,
    cmd,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'locations'
ORDER BY policyname;
```

### 檢查表格權限

```sql
SELECT
    grantee,
    privilege_type
FROM information_schema.table_privileges
WHERE table_name = 'locations'
ORDER BY grantee, privilege_type;
```

**預期結果應包含**：
- `authenticated` → SELECT, INSERT, UPDATE, DELETE
- `service_role` → SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE

---

## 🚨 故障排除

### 錯誤 1: "new row violates row-level security policy"

**症狀**：
```
Error: new row violates row-level security policy for table "locations"
```

**原因**：Edge Function 使用了 Anon Key 而非 Service Role Key

**解決方案**：
```typescript
// 檢查 index.ts 中是否正確使用 Service Role Key
const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''  // ← 確認這一行
)

// 確保使用 supabaseAdmin 執行 INSERT
const { data, error } = await supabaseAdmin
  .from('locations')
  .insert({ ... })
```

### 錯誤 2: "permission denied for table locations"

**症狀**：
```
Error: permission denied for table locations
```

**原因**：`service_role` 沒有表格權限

**解決方案**：
```sql
-- 重新授予權限
GRANT ALL ON public.locations TO service_role;
GRANT USAGE, SELECT ON SEQUENCE locations_id_seq TO service_role;
```

### 錯誤 3: Edge Function 可以插入，但用戶無法查詢

**症狀**：Edge Function 成功儲存，但前端查詢不到資料

**原因**：用戶的 SELECT 政策有問題

**解決方案**：
```sql
-- 檢查 SELECT 政策
SELECT * FROM pg_policies WHERE tablename = 'locations' AND cmd = 'SELECT';

-- 確保有以下政策
CREATE POLICY "Users can view own locations"
ON public.locations
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);
```

### 錯誤 4: "SUPABASE_SERVICE_ROLE_KEY is not defined"

**症狀**：
```
Error: SUPABASE_SERVICE_ROLE_KEY is not defined
```

**原因**：環境變數未設定

**解決方案**：

**Production（Supabase Cloud）**：
```bash
# Service Role Key 會自動提供
# 無需手動設定
```

**本地開發**：
```bash
# 1. 檢查 .env 檔案
cat supabase/.env

# 2. 如果缺少，從 Supabase Dashboard 取得
# Settings → API → service_role key (secret)

# 3. 加入到 .env
echo "SUPABASE_SERVICE_ROLE_KEY=eyJhbGc..." >> supabase/.env

# 4. 重新啟動 Edge Function
npx supabase functions serve save-location --env-file ./supabase/.env
```

---

## 🔒 安全性考量

### 1. Service Role Key 的安全性

⚠️ **重要**：Service Role Key 擁有完整的資料庫權限，必須妥善保管！

**正確做法**：
- ✅ 只在後端（Edge Function）使用
- ✅ 永遠不要暴露給前端
- ✅ 使用環境變數儲存
- ✅ 不要提交到 Git

**錯誤做法**：
- ❌ 在前端程式碼中使用
- ❌ 硬編碼在程式中
- ❌ 提交到公開的 Git repository

### 2. 用戶身份驗證

雖然使用 Service Role Key 繞過 RLS，但仍然要驗證用戶身份：

```typescript
// ✓ 正確：先驗證用戶
const { data: { user }, error: userError } = await supabaseClient.auth.getUser()

if (userError || !user) {
  return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 })
}

// ✓ 然後使用 Service Role 執行操作（使用已驗證的 user.id）
await supabaseAdmin.from('locations').insert({
  user_id: user.id,  // 使用已驗證的用戶 ID
  ...
})
```

### 3. 資料驗證

即使繞過 RLS，也要在應用層進行驗證：

```typescript
// ✓ 驗證資料格式
if (latitude < -90 || latitude > 90) {
  throw new Error('Invalid latitude')
}

// ✓ 驗證業務邏輯
if (!validTypes.includes(type)) {
  throw new Error('Invalid location type')
}

// ✓ 檢查用戶是否已有該類型的地點
const existingLocation = await supabaseClient
  .from('locations')
  .select('id')
  .eq('user_id', user.id)
  .eq('type', type)

if (existingLocation.data?.length > 0) {
  throw new Error('Location type already exists')
}
```

---

## 📊 權限矩陣

| 操作 | Anon | Authenticated (前端) | Service Role (Edge Function) |
|------|------|---------------------|----------------------------|
| SELECT own locations | ❌ | ✅ | ✅ |
| SELECT other's locations | ❌ | ❌ | ✅ (但不應該) |
| INSERT own location | ❌ | ✅ (受 RLS 限制) | ✅ (繞過 RLS) |
| INSERT other's location | ❌ | ❌ | ✅ (可以，但需驗證) |
| UPDATE own location | ❌ | ✅ | ✅ |
| UPDATE other's location | ❌ | ❌ | ✅ (可以，但不應該) |
| DELETE own location | ❌ | ✅ | ✅ |
| DELETE other's location | ❌ | ❌ | ✅ (可以，但不應該) |

---

## 📝 最佳實踐

### 1. Edge Function 模式

```typescript
// 模式：雙重客戶端
// 1. 用於驗證身份（使用 User JWT）
const supabaseClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  global: { headers: { Authorization: userJWT } }
})

// 2. 用於執行操作（使用 Service Role）
const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

// 流程
const { data: { user } } = await supabaseClient.auth.getUser()  // 驗證
await supabaseAdmin.from('locations').insert({ user_id: user.id, ... })  // 操作
```

### 2. 前端直接存取模式

```typescript
// 前端：使用 Anon Key + User JWT
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

// 登入後，JWT 會自動附加到所有請求
await supabase.auth.signInWithPassword({ email, password })

// RLS 會自動限制只能存取自己的資料
const { data } = await supabase
  .from('locations')
  .select('*')  // 只會返回 user_id = auth.uid() 的資料
```

---

## 🧪 測試清單

### Migration 後測試

- [ ] 執行 `SELECT * FROM test_locations_permissions()` - 所有測試 PASS
- [ ] 檢查 RLS 政策數量 - 應有 4 個政策
- [ ] 檢查 service_role 權限 - 應有 ALL 權限

### Edge Function 測試

- [ ] 測試儲存地點 - 應該成功
- [ ] 測試首次建立（必須為「家」） - 應該成功
- [ ] 測試重複類型 - 應該返回錯誤
- [ ] 測試未登入 - 應該返回 401

### 前端測試

- [ ] 登入後查詢自己的地點 - 應該成功
- [ ] 嘗試查詢他人的地點 - 應該返回空（受 RLS 保護）
- [ ] 嘗試更新他人的地點 - 應該失敗（受 RLS 保護）

---

## 📚 相關資源

- [Supabase Row Level Security](https://supabase.com/docs/guides/auth/row-level-security)
- [Supabase Edge Functions Security](https://supabase.com/docs/guides/functions/auth)
- [PostgreSQL RLS Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- [Service Role vs Anon Key](https://supabase.com/docs/guides/api/api-keys)

---

**版本**: 1.0.0  
**最後更新**: 2025-11-07  
**維護者**: FCU-Sigma Backend Team