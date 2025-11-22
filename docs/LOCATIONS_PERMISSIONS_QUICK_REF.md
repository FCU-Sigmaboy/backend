# Locations 表權限配置 - 快速參考

## 🎯 核心概念

**Edge Function 使用 Service Role Key 繞過 RLS**

```
前端請求 (User JWT) 
  ↓
Edge Function 驗證身份
  ↓
使用 Service Role Key 執行 INSERT (繞過 RLS)
  ↓
成功儲存地點
```

---

## 📋 Migration 檔案

**檔案**: `20251107100000_fix_locations_permissions_for_edge_function_jo.sql`

**執行**:
```bash
# Supabase CLI
npx supabase db push

# 或透過 Dashboard
# SQL Editor → 貼上並執行
```

---

## 🔐 RLS 政策 (4 個)

| 政策名稱 | 操作 | 規則 |
|---------|------|------|
| Users can view own locations | SELECT | `auth.uid() = user_id` |
| Users can insert own locations | INSERT | `auth.uid() = user_id` |
| Users can update own locations | UPDATE | `auth.uid() = user_id` |
| Users can delete own locations | DELETE | `auth.uid() = user_id` |

---

## ✅ 驗證權限

```sql
-- 快速測試
SELECT * FROM test_locations_permissions();

-- 預期: 所有測試 PASS
```

---

## 🔧 Edge Function 設定

### index.ts 關鍵程式碼

```typescript
// 1. 驗證用戶身份 (使用 User JWT)
const supabaseClient = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_ANON_KEY') ?? '',
  { global: { headers: { Authorization: authHeader } } }
)

const { data: { user } } = await supabaseClient.auth.getUser()

// 2. 執行資料庫操作 (使用 Service Role)
const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''  // ← 關鍵！
)

await supabaseAdmin.from('locations').insert({
  user_id: user.id,  // 使用已驗證的 user.id
  coordinates: wktPoint,
  type: type,
  is_primary: is_primary,
  formatted_address: formattedAddress
})
```

---

## 🚨 常見錯誤

### 錯誤 1: "new row violates row-level security policy"

**原因**: 使用了 ANON_KEY 而非 SERVICE_ROLE_KEY

**解決**:
```typescript
// ❌ 錯誤
const client = createClient(URL, SUPABASE_ANON_KEY)

// ✅ 正確
const client = createClient(URL, SUPABASE_SERVICE_ROLE_KEY)
```

### 錯誤 2: "permission denied for table locations"

**原因**: service_role 缺少權限

**解決**:
```sql
GRANT ALL ON public.locations TO service_role;
GRANT USAGE, SELECT ON SEQUENCE locations_id_seq TO service_role;
```

### 錯誤 3: "SUPABASE_SERVICE_ROLE_KEY is not defined"

**原因**: 環境變數未設定

**解決**:
```bash
# 本地開發
echo "SUPABASE_SERVICE_ROLE_KEY=eyJhbGc..." >> supabase/.env

# Supabase Cloud (自動提供，無需設定)
```

---

## 🧪 測試步驟

### 1. Migration 後驗證
```sql
SELECT * FROM test_locations_permissions();
-- 預期: 4 個 PASS
```

### 2. 測試 Edge Function
```bash
curl -X POST https://xxx.supabase.co/functions/v1/save-location \
  -H "Authorization: Bearer $USER_JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 24.1817,
    "longitude": 120.7344,
    "type": "家",
    "is_primary": true
  }'
```

### 3. 測試前端查詢
```typescript
const { data } = await supabase
  .from('locations')
  .select('*')
// 應只返回當前用戶的地點
```

---

## 🔒 安全檢查清單

- [ ] Service Role Key 只在後端使用
- [ ] 不將 Service Role Key 暴露給前端
- [ ] Edge Function 有驗證用戶身份
- [ ] RLS 政策保護用戶資料
- [ ] 測試函數全部 PASS

---

## 📊 權限矩陣

| 角色 | SELECT | INSERT | UPDATE | DELETE |
|------|--------|--------|--------|--------|
| anon | ❌ | ❌ | ❌ | ❌ |
| authenticated | ✅ (自己) | ✅ (自己) | ✅ (自己) | ✅ (自己) |
| service_role | ✅ (全部) | ✅ (全部) | ✅ (全部) | ✅ (全部) |

---

## 📞 故障排除

**問題**: Edge Function 執行失敗

**檢查順序**:
1. ✅ Migration 是否已執行？
2. ✅ `test_locations_permissions()` 是否全部 PASS？
3. ✅ Edge Function 是否使用 `SUPABASE_SERVICE_ROLE_KEY`？
4. ✅ 環境變數是否正確設定？
5. ✅ 用戶身份驗證是否成功？

**詳細文件**: 參見 `PERMISSIONS.md`

---

**快速連結**:
- 完整文件: `save-location/PERMISSIONS.md`
- Migration: `20251107100000_fix_locations_permissions_for_edge_function_jo.sql`
- Edge Function: `save-location/index.ts`
