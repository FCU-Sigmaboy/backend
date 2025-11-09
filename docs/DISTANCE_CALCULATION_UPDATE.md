# 距離計算更新說明文件

## 📋 變更概述

**日期**: 2025-11-08  
**版本**: v3.0  
**相關 Migration**: 
- `20251109000001_add_use_primary_location_to_items_jo.sql`
- `20251109000002_update_create_item_with_use_primary_location_jo.sql`
- `20251109000003_update_search_and_details_rpc_with_use_primary_location_jo.sql`

---

## 🎯 核心變更

### **新增欄位: `items.use_primary_location`**

```sql
ALTER TABLE items 
ADD COLUMN use_primary_location BOOLEAN NOT NULL DEFAULT true;
```

**用途**:
- `true` → 物品使用賣家的主要地點 (is_primary=true)
- `false` → 物品使用賣家的次要地點 (is_primary=false)

**業務背景**:
- 使用者限制: 最多擁有 1 個主要地點 + 1 個次要地點
- 刊登物品時可選擇使用哪個地點作為銷售地點

---

## 🔄 距離計算邏輯變更

### **變更前 (v2.0)**

```sql
-- 固定使用賣家的主要地點
LEFT JOIN locations seller_loc 
  ON seller_loc.user_id = items.user_id 
  AND seller_loc.is_primary = true
```

**限制**:
- 所有物品都使用賣家的主要地點
- 無法為特定物品選擇不同的地點

---

### **變更後 (v3.0)**

```sql
-- 根據物品設定動態選擇賣家地點
LEFT JOIN locations seller_loc 
  ON seller_loc.user_id = items.user_id 
  AND seller_loc.is_primary = items.use_primary_location
```

**優勢**:
- ✅ 物品可以使用主要地點或次要地點
- ✅ 距離計算更準確（反映物品實際銷售地點）
- ✅ 保持資料庫設計簡潔（只需一個 boolean 欄位）

---

## 📊 完整距離計算邏輯

```
買家位置（查詢者）
    ↓
  固定使用買家的主要地點
  (locations WHERE user_id = 買家ID AND is_primary = true)
    ↓
    ↓ ST_Distance (PostGIS)
    ↓
賣家位置（物品）
    ↓
  根據 items.use_primary_location 動態選擇
  ├─ true  → 賣家主要地點 (is_primary = true)
  └─ false → 賣家次要地點 (is_primary = false)
```

---

## 🛠️ 受影響的 RPC 函數

### 1. **`search_items`** (v6.0 → v7.0)

**檔案**: `20251109000003_update_search_and_details_rpc_with_use_primary_location_jo.sql`

**變更**:
```sql
-- 舊版
LEFT JOIN locations l 
  ON i.user_id = l.user_id 
  AND l.is_primary = true

-- 新版
LEFT JOIN locations l 
  ON i.user_id = l.user_id 
  AND l.is_primary = i.use_primary_location  -- ✅ 動態選擇
```

**影響範圍**:
- 物品搜尋列表
- 距離篩選 (`p_distance_range_km`)
- 距離排序 (`p_sort_by = 'distance'`)

---

### 2. **`get_item_details_with_location`** (v3.0 → v4.0)

**檔案**: `20251109000003_update_search_and_details_rpc_with_use_primary_location_jo.sql`

**變更**:
```sql
-- 舊版
LEFT JOIN locations seller_loc 
  ON i.user_id = seller_loc.user_id 
  AND seller_loc.is_primary = true

-- 新版
LEFT JOIN locations seller_loc 
  ON i.user_id = seller_loc.user_id 
  AND seller_loc.is_primary = i.use_primary_location  -- ✅ 動態選擇
```

**影響範圍**:
- 物品詳情頁
- 顯示距離資訊
- 地圖顯示（顯示物品實際位置）

**新增回傳欄位**:
```json
{
  "use_primary_location": true,  // 顯示使用主要或次要地點
  "location": {
    "is_primary": true,  // 顯示該地點類型
    // ...
  }
}
```

---

## 📝 前端 API 變更

### **`get_searchItemsAPI.js`** (v6.0 → v7.0)

**無需變更前端呼叫方式**：
```javascript
// 前端呼叫方式完全相同
const items = await searchItems({
  distance_range_km: 5,
  keyword: '桌子',
  sort_by: 'distance'
});

// 距離計算已自動更新（使用物品的 use_primary_location）
items.forEach(item => {
  console.log(`${item.title} - ${item.distance_km} km`);
});
```

**內部變更**:
- RPC v7.0 自動使用 `items.use_primary_location` 選擇賣家地點
- 距離計算更準確

---

### **`get_ItemDetailsAPI.js`** (v3.0 → v4.0)

**無需變更前端呼叫方式**：
```javascript
// 前端呼叫方式完全相同
const result = await getItemDetails(itemId);

if (result.success) {
  console.log('距離:', result.data.distance_km, 'km');
  console.log('地點類型:', result.data.location.is_primary ? '主要' : '次要');
  console.log('物品設定:', result.data.use_primary_location ? '主要' : '次要');
}
```

**新增資訊**:
- `use_primary_location`: 物品使用主要或次要地點
- `location.is_primary`: 實際地點的類型

---

## 🧪 測試檢查清單

### 資料庫層級

- [ ] 驗證 `items.use_primary_location` 欄位已建立
- [ ] 驗證預設值為 `true`
- [ ] 驗證索引已建立 (`idx_items_user_id_use_primary_location`)
- [ ] 驗證 `items_with_location` View 正常運作

### RPC 函數測試

**`search_items` 測試**:
- [ ] 測試刊登在主要地點的物品（`use_primary_location=true`）
- [ ] 測試刊登在次要地點的物品（`use_primary_location=false`）
- [ ] 測試距離計算正確性
- [ ] 測試距離篩選功能
- [ ] 測試距離排序功能

**`get_item_details_with_location` 測試**:
- [ ] 測試主要地點物品的詳情
- [ ] 測試次要地點物品的詳情
- [ ] 測試距離計算正確性
- [ ] 測試地點資訊顯示
- [ ] 測試 `use_primary_location` 欄位回傳

### 前端測試

- [ ] 搜尋頁面距離顯示正確
- [ ] 物品詳情頁距離顯示正確
- [ ] 地圖顯示物品實際位置（主要或次要地點）
- [ ] 距離排序功能正常
- [ ] 距離篩選功能正常

---

## 🔍 範例場景

### 場景 1: 物品使用主要地點

```sql
-- 物品資料
items: { id: 1, user_id: 'user-a', use_primary_location: true }

-- 賣家地點
locations:
  - { user_id: 'user-a', is_primary: true,  formatted_address: '台北市' }  ← 使用這個
  - { user_id: 'user-a', is_primary: false, formatted_address: '新竹市' }

-- 買家地點
locations:
  - { user_id: 'buyer-b', is_primary: true, formatted_address: '台中市' }

-- 距離計算
distance = ST_Distance(台北市, 台中市) = X km
```

---

### 場景 2: 物品使用次要地點

```sql
-- 物品資料
items: { id: 2, user_id: 'user-a', use_primary_location: false }

-- 賣家地點
locations:
  - { user_id: 'user-a', is_primary: true,  formatted_address: '台北市' }
  - { user_id: 'user-a', is_primary: false, formatted_address: '新竹市' }  ← 使用這個

-- 買家地點
locations:
  - { user_id: 'buyer-b', is_primary: true, formatted_address: '台中市' }

-- 距離計算
distance = ST_Distance(新竹市, 台中市) = Y km
```

---

## ⚠️ 注意事項

### 1. 舊資料相容性

**所有舊物品的 `use_primary_location` 預設為 `true`**：
- Migration 會自動設定預設值
- 舊物品行為與 v2.0 完全相同（使用主要地點）
- 不需要資料遷移

### 2. 賣家地點驗證

刊登物品時會驗證賣家是否有對應的地點：
```sql
-- create_item RPC 會檢查
IF NOT EXISTS (
  SELECT 1 FROM locations 
  WHERE user_id = 當前用戶 
  AND is_primary = p_use_primary_location
) THEN
  RAISE EXCEPTION '請先設定對應的地點';
END IF;
```

### 3. 買家位置固定

- 買家位置始終使用主要地點
- 如果買家沒有主要地點，`distance_km` 為 NULL
- 未登入用戶看不到距離資訊

---

## 📖 相關文件

- [CHANGELOG v3.0](../../contracts/create_myItemsAPI/CHANGELOG_v3.0.md)
- [Migration 20251108000001](20251108000001_add_use_primary_location_to_items_jo.sql)
- [Migration 20251108000002](20251108000002_update_create_item_with_use_primary_location_jo.sql)
- [Migration 20251108000003](20251108000003_update_search_and_details_rpc_with_use_primary_location_jo.sql)

---

## 🚀 部署順序

1. **執行 Migration 1**: 新增 `use_primary_location` 欄位
   ```bash
   psql < 20251109000001_add_use_primary_location_to_items_jo.sql
   ```

2. **執行 Migration 2**: 更新 `create_item` RPC
   ```bash
   psql < 20251109000002_update_create_item_with_use_primary_location_jo.sql
   ```

3. **執行 Migration 3**: 更新距離計算 RPC
   ```bash
   psql < 20251109000003_update_search_and_details_rpc_with_use_primary_location_jo.sql
   ```

4. **更新前端 API**: 部署新版 API 檔案（向後相容）

5. **測試**: 執行完整測試檢查清單

---

## ✅ 驗證方法

### 快速驗證 SQL

```sql
-- 1. 檢查欄位是否存在
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'items' 
  AND column_name = 'use_primary_location';

-- 2. 檢查 View 是否存在
SELECT * FROM items_with_location LIMIT 1;

-- 3. 測試距離計算（假設有測試資料）
SELECT 
  i.id,
  i.title,
  i.use_primary_location,
  l.formatted_address,
  l.is_primary
FROM items i
LEFT JOIN locations l 
  ON i.user_id = l.user_id 
  AND l.is_primary = i.use_primary_location
LIMIT 5;

-- 4. 測試搜尋功能
SELECT * FROM search_items(
  p_distance_range_km := 10,
  p_page := 1,
  p_size := 5
);
```

---

**更新日期**: 2025-11-08  
**文件版本**: 1.0  
**狀態**: ✅ 已完成  
**維護者**: Backend Team