# Migration 執行指南 - 移除 items.location_id

**日期**: 2025-11-07  
**目標**: 將 items 表從直接使用 `location_id` 改為透過 `user_id` 關聯 locations 表

---

## 📋 目錄

1. [背景說明](#背景說明)
2. [變更摘要](#變更摘要)
3. [Migration 檔案列表](#migration-檔案列表)
4. [執行步驟](#執行步驟)
5. [驗證方法](#驗證方法)
6. [回滾計畫](#回滾計畫)
7. [前端 API 變更](#前端-api-變更)
8. [常見問題](#常見問題)

---

## 🎯 背景說明

### 現有架構問題

```sql
-- 舊架構
items.location_id → locations.id

問題：
1. 每個物品需要指定一個固定的 location_id
2. 如果使用者更新地點，需要更新所有物品的 location_id
3. 物品與地點綁定過於緊密
```

### 新架構優勢

```sql
-- 新架構
items.user_id → users.id
users.id → locations.user_id (透過 is_primary = true)

優勢：
1. 物品自動使用使用者的主要地點
2. 使用者更新主要地點時，所有物品自動更新
3. 更符合業務邏輯（物品屬於使用者，地點也屬於使用者）
```

---

## 📊 變更摘要

### 資料庫變更

| 項目 | 變更前 | 變更後 |
|------|--------|--------|
| items.location_id | BIGINT NOT NULL (FK) | 欄位刪除 |
| 關聯方式 | items → locations (直接) | items → users → locations |
| JOIN 語法 | `JOIN locations l ON i.location_id = l.id` | `JOIN locations l ON i.user_id = l.user_id AND l.is_primary = true` |

### 函數變更

| 函數名稱 | 變更內容 |
|----------|----------|
| `search_items` | 更新 JOIN 邏輯，使用 user_id 關聯 |
| `get_my_favorite_items` | 更新 JOIN 邏輯，使用 user_id 關聯 |
| `get_item_details_with_location` | 更新 JOIN 邏輯，使用 user_id 關聯 |
| `create_item` | **移除 `p_user_location_id` 參數** |

---

## 📁 Migration 檔案列表

### 執行順序

```
1️⃣ 20251107000001_update_items_location_relationship_jo.sql
   - 移除外鍵約束
   - location_id 改為可選（允許 NULL）
   - 建立新索引

2️⃣ 20251107000002_update_rpc_functions_use_user_location_jo.sql
   - 更新 search_items 函數
   - 更新 get_my_favorite_items 函數
   - 更新 get_item_details_with_location 函數

3️⃣ 20251107000003_update_create_item_function_jo.sql
   - 更新 create_item 函數
   - 移除 p_user_location_id 參數
   - 新增 user_has_location 輔助函數

⏸️ === 暫停：等待前端 API 更新完成 ===

4️⃣ 20251107000004_remove_location_id_column_jo.sql
   ⚠️ 只有在前端更新完成且測試通過後才執行
   - 完全刪除 location_id 欄位
   - 清理相關索引
```

---

## 🚀 執行步驟

### Phase 1: 準備階段

#### 1.1 備份資料庫

```bash
# 使用 Supabase CLI 或直接在 Dashboard 建立備份
# 確保可以回滾到當前狀態
```

#### 1.2 在開發/測試環境先執行

```bash
# 不要直接在 Production 執行！
```

### Phase 2: 資料庫更新（Migration 1-3）

#### 2.1 執行 Migration 1

```bash
# 透過 Supabase Dashboard 或 CLI 執行
psql -f 20251107000001_update_items_location_relationship_jo.sql
```

**預期結果**:
- ✅ 外鍵約束已移除
- ✅ location_id 允許 NULL
- ✅ 新索引已建立

**驗證**:
```sql
-- 檢查約束是否已移除
SELECT constraint_name 
FROM information_schema.table_constraints 
WHERE table_name = 'items' 
  AND constraint_type = 'FOREIGN KEY'
  AND constraint_name LIKE '%location_id%';
-- 應該返回 0 筆

-- 檢查欄位是否允許 NULL
SELECT is_nullable 
FROM information_schema.columns 
WHERE table_name = 'items' 
  AND column_name = 'location_id';
-- 應該返回 'YES'
```

#### 2.2 執行 Migration 2

```bash
psql -f 20251107000002_update_rpc_functions_use_user_location_jo.sql
```

**預期結果**:
- ✅ search_items v6.0 已更新
- ✅ get_my_favorite_items v2.0 已更新
- ✅ get_item_details_with_location v3.0 已更新

**驗證**:
```sql
-- 測試 search_items
SELECT * FROM public.search_items(
    p_page := 1,
    p_size := 5
);

-- 測試 get_my_favorite_items
SELECT * FROM public.get_my_favorite_items(
    p_page := 1,
    p_size := 5
);

-- 測試 get_item_details_with_location
SELECT public.get_item_details_with_location(1);
```

#### 2.3 執行 Migration 3

```bash
psql -f 20251107000003_update_create_item_function_jo.sql
```

**預期結果**:
- ✅ create_item v2.0 已更新（無 location_id 參數）
- ✅ user_has_location 輔助函數已建立

**驗證**:
```sql
-- 測試新的 create_item（注意：沒有 location_id 參數）
SELECT public.create_item(
    p_sub_category_id := 1,
    p_title := '測試物品',
    p_description := '這是測試',
    p_condition := '良好',
    p_price := 100
);
```

### Phase 3: 前端更新

⚠️ **在執行 Migration 4 之前，必須完成此階段**

#### 3.1 更新 API 呼叫

**舊程式碼**:
```typescript
// ❌ 舊版：需要傳遞 user_location_id
const { data, error } = await supabase.rpc('create_item', {
  p_sub_category_id: 1,
  p_user_location_id: userLocationId, // 不再需要！
  p_title: '物品標題',
  p_description: '物品描述',
  p_condition: '良好',
  p_price: 100,
  p_image_urls: ['url1', 'url2'],
  p_tags: ['tag1', 'tag2']
});
```

**新程式碼**:
```typescript
// ✅ 新版：移除 user_location_id 參數
const { data, error } = await supabase.rpc('create_item', {
  p_sub_category_id: 1,
  p_title: '物品標題',
  p_description: '物品描述',
  p_condition: '良好',
  p_price: 100,
  p_image_urls: ['url1', 'url2'],
  p_tags: ['tag1', 'tag2']
});
```

#### 3.2 更新相關 UI/UX

- 刪除「選擇地點」的下拉選單或輸入欄位
- 更新說明文字：「物品將使用您的主要地點」
- 確保使用者在刊登物品前已設定主要地點

#### 3.3 測試前端功能

- [ ] 測試刊登物品功能
- [ ] 測試搜尋物品功能
- [ ] 測試查看物品詳情
- [ ] 測試收藏物品列表
- [ ] 測試我的物品列表

### Phase 4: 最終清理（Migration 4）

⚠️ **警告：此步驟不可逆！請確保已完成所有測試！**

#### 4.1 最終檢查清單

- [ ] Migration 1-3 已在 Production 執行
- [ ] 前端已更新並部署
- [ ] 所有功能測試通過
- [ ] 已確認沒有程式碼仍在使用 location_id 參數
- [ ] 已完成資料庫完整備份

#### 4.2 執行 Migration 4

```bash
psql -f 20251107000004_remove_location_id_column_jo.sql
```

**預期結果**:
- ✅ location_id 欄位已完全刪除
- ✅ 相關索引已刪除
- ✅ 表格已優化

**驗證**:
```sql
-- 確認欄位已刪除
SELECT column_name 
FROM information_schema.columns 
WHERE table_name = 'items' 
  AND column_name = 'location_id';
-- 應該返回 0 筆
```

---

## ✅ 驗證方法

### 完整功能測試腳本

```sql
-- 測試 1: 搜尋物品
SELECT COUNT(*) as search_count 
FROM public.search_items(p_page := 1, p_size := 10);

-- 測試 2: 查看物品詳情
SELECT 
    (result->>'id')::bigint as item_id,
    result->>'title' as title,
    result->'location'->>'formatted_address' as address
FROM public.get_item_details_with_location(1) as result;

-- 測試 3: 收藏列表
SELECT COUNT(*) as favorite_count
FROM public.get_my_favorite_items(p_page := 1, p_size := 10);

-- 測試 4: 我的物品
SELECT COUNT(*) as my_items_count
FROM public.get_my_items(p_page := 1, p_size := 10);

-- 測試 5: 刊登物品
SELECT public.create_item(
    p_sub_category_id := 1,
    p_title := '測試物品 ' || NOW()::text,
    p_description := '自動化測試',
    p_condition := '良好',
    p_price := 999
);
```

### 效能測試

```sql
-- 檢查查詢計畫
EXPLAIN ANALYZE
SELECT i.*, l.formatted_address
FROM items i
LEFT JOIN locations l ON i.user_id = l.user_id AND l.is_primary = true
WHERE i.listing_status = true
LIMIT 20;
```

---

## 🔄 回滾計畫

### 如果在 Migration 1-3 階段發現問題

#### 回滾 Migration 3
```sql
-- 恢復舊版 create_item（包含 location_id 參數）
-- 從備份中執行舊版 SQL 或從 Git history 取得
```

#### 回滾 Migration 2
```sql
-- 恢復舊版 RPC 函數
-- 從以下檔案恢復：
-- - 20251030063927_get_searchItems_RPC_v5.sql
-- - 20251030115919_get_myFavorite_RPC.sql
-- - 20251101000000_get_ItemDetails_RPC_optimized.sql
```

#### 回滾 Migration 1
```sql
-- 恢復外鍵約束
ALTER TABLE public.items
ALTER COLUMN location_id SET NOT NULL;

ALTER TABLE public.items
ADD CONSTRAINT items_location_id_fkey
FOREIGN KEY (location_id)
REFERENCES public.locations(id)
ON DELETE RESTRICT;
```

### 如果在 Migration 4 之後需要回滾

⚠️ **非常困難！** Migration 4 刪除了欄位，資料已丟失。

必須步驟：
1. 從備份恢復整個資料庫
2. 或者重新建立欄位並重新填充資料（見 Migration 4 檔案中的回滾說明）

**這就是為什麼 Migration 4 要最後執行！**

---

## 📱 前端 API 變更

### TypeScript 型別更新

```typescript
// 舊型別
interface CreateItemParams {
  p_sub_category_id: number;
  p_user_location_id: number; // ❌ 移除
  p_title: string;
  p_description: string;
  p_condition: ItemCondition;
  p_price: number;
  p_carbon_value?: number;
  p_image_urls?: string[];
  p_tags?: string[];
}

// 新型別
interface CreateItemParams {
  p_sub_category_id: number;
  // p_user_location_id 已移除
  p_title: string;
  p_description: string;
  p_condition: ItemCondition;
  p_price: number;
  p_carbon_value?: number;
  p_image_urls?: string[];
  p_tags?: string[];
}
```

### API 呼叫範例

```typescript
// 在 items.service.ts 或類似檔案中

export async function createItem(params: CreateItemParams) {
  // 確保使用者已設定地點
  const hasLocation = await checkUserHasLocation();
  if (!hasLocation) {
    throw new Error('請先在個人資料中設定地點');
  }

  const { data, error } = await supabase.rpc('create_item', params);
  
  if (error) throw error;
  return data;
}

async function checkUserHasLocation(): Promise<boolean> {
  const { data: user } = await supabase.auth.getUser();
  if (!user) return false;

  const { data, error } = await supabase
    .from('locations')
    .select('id')
    .eq('user_id', user.user.id)
    .limit(1);

  return !error && data && data.length > 0;
}
```

---

## ❓ 常見問題

### Q1: 為什麼要分成 4 個 Migration？

**A**: 為了安全和可控：
1. Migration 1-3 可以安全回滾
2. 在前端更新前不會破壞現有功能
3. Migration 4 是不可逆的，所以最後執行

### Q2: 如果使用者沒有設定地點會怎樣？

**A**: 
- 刊登物品時會收到錯誤：「請先在個人資料中設定地點後再刊登物品」
- 查詢物品時不會顯示距離資訊（distance_km 為 NULL）

### Q3: 如果使用者有多個地點，會使用哪一個？

**A**: 
- 使用 `is_primary = true` 的地點
- 如果沒有設定主要地點，使用建立時間最早的地點

### Q4: 舊的物品資料會受影響嗎？

**A**: 
- Migration 1-3：不會，location_id 仍然存在
- Migration 4：location_id 欄位會被刪除，但物品仍然可以透過 user_id 找到地點

### Q5: 效能會受影響嗎？

**A**: 
- 不會，我們已經建立適當的索引
- 新的 JOIN 方式可能更有效率（一個使用者通常只有少數幾個地點）

### Q6: 如何測試 Migration 是否成功？

**A**: 執行「驗證方法」章節中的所有測試 SQL

---

## 📞 支援

如果執行過程中遇到問題：

1. **不要驚慌** - Migration 1-3 可以回滾
2. **檢查錯誤訊息** - 大部分問題都有清楚的錯誤訊息
3. **查看 logs** - 每個 Migration 都有詳細的 NOTICE 和 WARNING
4. **聯繫團隊** - 如果無法解決，請立即通知團隊

---

## ✨ 完成檢查清單

### Phase 1-2: 資料庫更新
- [ ] 已備份資料庫
- [ ] 已在測試環境執行
- [ ] Migration 1 執行成功
- [ ] Migration 2 執行成功
- [ ] Migration 3 執行成功
- [ ] 所有 RPC 函數測試通過

### Phase 3: 前端更新
- [ ] 已更新 create_item API 呼叫
- [ ] 已移除 location_id 相關 UI
- [ ] 已更新 TypeScript 型別
- [ ] 前端功能測試通過
- [ ] 已部署到 Production

### Phase 4: 最終清理
- [ ] 已確認前端運作正常
- [ ] 已完成最終資料庫備份
- [ ] Migration 4 執行成功
- [ ] 完整功能驗證通過

---

**Migration 完成日期**: ___________  
**執行者**: ___________  
**備註**: ___________