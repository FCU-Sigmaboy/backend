# 變更日誌 - v4.0：物品位置設定方式變更（2025-11-09）

## 概述

隨著新的物品位置設定方式變更，系統從固定使用主要地點改為允許物品選擇使用主要或次要地點。本文檔詳細說明了所有受影響的組件和變更內容。

## 核心變更

### 1. 數據庫架構變更

#### 新增欄位
- **`items.use_primary_location`** (BOOLEAN, NOT NULL, DEFAULT true)
  - `true`: 物品使用賣家的主要地點
  - `false`: 物品使用賣家的次要地點
  
#### 移除欄位
- `items.location_id` (已於 v3.0 移除)

#### 新增視圖
- **`items_with_location`**: 物品及其關聯地點的完整視圖
  ```sql
  LEFT JOIN public.locations l
    ON l.user_id = i.user_id
    AND l.is_primary = i.use_primary_location;
  ```

#### 新增索引
- `idx_items_user_id_use_primary_location`: 優化物品與位置查詢
- `idx_items_listing_status_use_primary`: 優化已上架物品查詢
- `idx_locations_user_id_is_primary`: 優化位置查詢

---

## 受影響的 API 和函數

### 1. RPC 函數：`get_item_details_with_location()` (v3.0 → v4.0)

**版本更新**: v3.0 → v4.0  
**日期**: 2025-11-09  
**文件**: `/database/functions/get_ItemDetails (RPC)_optimized.sql`

#### 主要變更
```sql
-- v3.0（舊版）
LEFT JOIN public.locations seller_loc 
  ON i.user_id = seller_loc.user_id 
  AND seller_loc.is_primary = true

-- v4.0（新版）
LEFT JOIN public.locations seller_loc 
  ON i.user_id = seller_loc.user_id 
  AND seller_loc.is_primary = i.use_primary_location
```

#### 新增輸出字段
- `use_primary_location` (boolean): 物品使用的位置類型

#### 買家位置策略（無變更）
- 仍然使用買家的主要地點（`is_primary = true`）計算距離

#### 隱私保護（無變更）
- 未登入用戶：無法查看距離和精確座標
- 物品擁有者：查看自己的物品時不顯示距離

### 2. RPC 函數：`search_items()` (已更新)

**版本**: v5.0+  
**文件**: `/supabase/migrations/20251109000003_update_search_and_details_rpc_with_use_primary_location_jo.sql`

#### 主要變更
- 所有位置 JOIN 都使用 `seller_loc.is_primary = i.use_primary_location`
- 距離計算基於物品選定的地點

### 3. RPC 函數：`create_item()` (已更新)

**版本**: v3.0  
**文件**: `/supabase/migrations/20251109000002_update_create_item_with_use_primary_location_jo.sql`

#### 新增參數
```javascript
p_use_primary_location BOOLEAN DEFAULT true
```

#### 功能
- 刊登物品時可指定使用主要或次要地點
- 驗證用戶是否擁有對應的地點
- 若不存在對應地點，拋出例外

---

## JavaScript API 變更

### 文件：`contracts/get_oneItemDetailAPI/get_ItemDetailsAPI.js`

**版本更新**: v3.0 → v4.0  
**日期**: 2025-11-09

#### 變更內容
1. **版本號更新**
   - 舊版: v3.0（2025-11-07）
   - 新版: v4.0（2025-11-09）

2. **文檔更新**
   - 添加 `use_primary_location` 欄位說明
   - 更新賣家位置策略文檔
   - 更新 API 文檔中的回傳資料結構

3. **回傳格式**
   ```javascript
   {
     // ... 其他欄位
     use_primary_location: boolean,  // ✅ 新增
     location: {
       // 根據 use_primary_location 動態決定
     }
     // ... 其他欄位
   }
   ```

---

## 遷移和部署

### 已應用的遷移

1. **20251109000001**: `add_use_primary_location_to_items_jo.sql`
   - 新增 `items.use_primary_location` 欄位
   - 移除 `items.location_id` 欄位（如存在）
   - 建立支援視圖和索引

2. **20251109000002**: `update_create_item_with_use_primary_location_jo.sql`
   - 更新 `create_item()` 函數以支援新參數

3. **20251109000003**: `update_search_and_details_rpc_with_use_primary_location_jo.sql`
   - 更新 `search_items()` 和 `get_item_details_with_location()` RPC 函數
   - 所有位置查詢都使用新的 JOIN 邏輯

### 源文件更新

1. `/database/functions/get_ItemDetails (RPC)_optimized.sql`
   - 更新版本號和文檔
   - 更新 SELECT 中的位置 JOIN 邏輯
   - 添加 `use_primary_location` 到 JSON 輸出

---

## 前端使用範例

### 檢查物品使用的位置類型

```javascript
const result = await getItemDetails(itemId);

if (result.success) {
  const item = result.data;
  
  if (item.use_primary_location) {
    console.log('使用主要地點:', item.location.formatted_address);
  } else {
    console.log('使用次要地點:', item.location.formatted_address);
  }
}
```

### 刊登物品並指定位置

```javascript
// 使用主要地點（預設）
await createItem({
  sub_category_id: 1,
  title: '二手書',
  description: '狀態很好',
  condition: '良好',
  price: 100
  // use_primary_location 預設為 true
});

// 使用次要地點
await createItem({
  sub_category_id: 1,
  title: '二手書',
  description: '狀態很好',
  condition: '良好',
  price: 100,
  use_primary_location: false
});
```

---

## 數據一致性保證

### 驗證檢查
1. 所有已上架物品必須有對應的地點設定
2. 物品無法刊登，除非用戶擁有對應的地點

### 異常處理
- 如果物品設定為使用主要地點，但用戶未設定主要地點 → 錯誤
- 如果物品設定為使用次要地點，但用戶未設定次要地點 → 錯誤

---

## 向後相容性

### ✅ 相容的變更
- 新的 `use_primary_location` 欄位有默認值 `true`，保持原有行為
- 舊的物品自動使用新的默認值

### ⚠️ 需要更新的組件
- 前端物品刊登表單（可選支援次要地點選擇）
- 任何直接查詢物品位置的後端邏輯

---

## 測試建議

### 單位測試
1. 驗證 `use_primary_location=true` 時使用主要地點
2. 驗證 `use_primary_location=false` 時使用次要地點
3. 驗證距離計算基於正確的地點

### 集成測試
1. 刊登物品時，驗證 `use_primary_location` 參數正常運作
2. 查詢物品詳情時，驗證回傳正確的 `use_primary_location` 值
3. 驗證物品沒有對應地點時的錯誤處理

### 邊界情況
1. 用戶只有主要地點，嘗試刊登使用次要地點的物品 → 應該失敗
2. 修改物品位置設定後，驗證距離重新計算
3. 用戶刪除次要地點，已刊登使用次要地點的物品 → 應標記為異常

---

## 性能考量

### 新增的索引
```sql
-- 組合索引：user_id + use_primary_location
CREATE INDEX idx_items_user_id_use_primary_location 
  ON public.items(user_id, use_primary_location);

-- 部分索引：已上架物品
CREATE INDEX idx_items_listing_status_use_primary 
  ON public.items(listing_status, use_primary_location) 
  WHERE listing_status = true;

-- 地理空間索引
CREATE INDEX idx_locations_coordinates_gist 
  ON public.locations USING GIST(coordinates);
```

### 查詢優化
- 使用 LEFT JOIN 而非 EXISTS 改善查詢效能
- 使用 CTE 減少重複查詢
- 適當使用部分索引減少索引大小

---

## 相關文檔

- [位置管理快速參考](./LOCATIONS_PERMISSIONS_QUICK_REF.md)
- [遷移指南 v3.0](./MIGRATION_GUIDE_20251107.md)
- [快速參考](./QUICK_REFERENCE.md)
- [RLS 政策檢查表](./RLS_POLICY_CHECKLIST.md)

---

## 常見問題 (FAQ)

### Q: 舊物品會受到影響嗎？
A: 不會。舊物品的 `use_primary_location` 預設設為 `true`，保持原有行為（使用主要地點）。

### Q: 我可以在刊登後更改位置類型嗎？
A: 目前設計不支援，但可以透過修改 `items.use_primary_location` 欄位進行更新。

### Q: 如果用戶刪除了次要地點怎麼辦？
A: 已刊登使用次要地點的物品將無法正確關聯地點，需要額外的驗證機制。

### Q: 距離計算會變嗎？
A: 會。距離不再總是基於主要地點，而是基於物品設定的地點類型。

---

## 聯絡信息

如有問題或建議，請聯絡開發團隊。

---

**最後更新**: 2025-11-09  
**文檔版本**: 1.0

