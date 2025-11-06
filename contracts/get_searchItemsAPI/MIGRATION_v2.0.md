# Migration v2.0 更新說明 - get_searchItemsAPI

## 📅 更新日期：2025-11-07

## ✅ 狀態：已符合 Migration v2.0 規範

---

## 🔄 變更摘要

此 API **已經**使用正確的架構，符合 Migration v2.0 的要求。

### 架構變更
- **變更前**：`items.location_id → locations.id`
- **變更後**：`items.user_id → locations.user_id (is_primary=true)`

### API 行為
- ✅ 自動使用買家（登入者）的主要地點計算距離
- ✅ 自動使用賣家的主要地點（透過 `items.user_id`）
- ✅ 不需要傳遞經緯度參數
- ✅ PostGIS 自動計算距離

---

## 📝 無需變更

### 函數簽章保持不變

```javascript
// v1.0 和 v2.0 的函數簽章相同
export async function searchItems(filters = {}) {
  const rpcParams = {
    p_distance_range_km: filters.distance_range_km || null,
    p_main_category_id: filters.main_category_id || null,
    p_sub_category_id: filters.sub_category_id || null,
    p_keyword: filters.keyword || null,
    p_user_id: filters.user_id || null,
    p_page: filters.page || 1,
    p_size: filters.size || 20,
    p_sort_by: filters.sort_by || 'created_at',
    p_sort_direction: filters.sort_direction || 'desc'
  };

  const { data, error } = await supabase.rpc('search_items', rpcParams);
  return data;
}
```

### 前端調用保持不變

```javascript
// 使用方式完全相同
const items = await searchItems({
  keyword: '書桌',
  distance_range_km: 5,
  page: 1,
  size: 20
});
```

---

## 🔍 內部實現變更

雖然前端 API 保持不變，但後端 RPC 函數已更新為 v6.0：

### 後端 SQL 變更（已完成）

#### Before (v5.0)
```sql
-- 使用 items.location_id 直接關聯
JOIN locations seller_loc ON items.location_id = seller_loc.id
```

#### After (v6.0)
```sql
-- 使用 items.user_id 關聯賣家的主要地點
JOIN locations seller_loc ON items.user_id = seller_loc.user_id 
  AND seller_loc.is_primary = true
```

---

## 📊 回傳格式

完全相同，無變更：

```javascript
[
  {
    "item_id": 101,
    "title": "（全新）IKEA 檯燈",
    "image_url": "https://.../item101_cover.jpg",
    "price": 500,
    "distance_km": "1.254",  // 自動計算（買賣雙方主要地點）
    "formatted_address": "台中市西屯區福星路",
    "created_at": "2025-10-18T10:30:00.123+00:00",
    "updated_at": "2025-10-18T10:30:00.123+00:00",
    "favorites_count": 15,
    "user": {
      "id": "a1b2c3d4-...",
      "nickname": "Joseph",
      "profile_picture_url": "https://.../joseph.jpg"
    }
  }
]
```

---

## ⚠️ 注意事項

### 使用者地點要求

如果使用者沒有設定任何地點：
- `distance_km` 將為 `null`
- 其他資訊正常顯示
- 不會拋出錯誤

### 建議處理方式

```javascript
// 前端顯示邏輯
const items = await searchItems({ keyword: '書桌' });

items.forEach(item => {
  if (item.distance_km !== null) {
    console.log(`距離: ${item.distance_km} 公里`);
  } else {
    console.log('距離: 未知（請設定您的地點）');
  }
});
```

---

## 🎯 Migration 檢查清單

- [x] 後端 RPC 已更新至 v6.0
- [x] 使用 `items.user_id` 關聯位置
- [x] 自動查詢主要地點 (is_primary=true)
- [x] 前端 API 無需修改
- [x] 回傳格式保持一致
- [x] 文件已更新

---

## 🔗 相關文件

- [MIGRATION_GUIDE_20251107.md](../../supabase/migrations/MIGRATION_GUIDE_20251107.md)
- [QUICK_REFERENCE.md](../../supabase/migrations/QUICK_REFERENCE.md)
- 相關 Migration:
  - `20251107000001_update_items_location_relationship.sql`
  - `20251107000002_update_rpc_functions_use_user_location.sql` ⭐ (包含 search_items v6.0)

---

## ✨ 優勢

1. **向後相容**：前端無需修改
2. **自動化**：系統自動處理位置關聯
3. **彈性**：使用者更改主要地點，搜尋結果自動更新
4. **效能**：透過索引優化查詢速度

---

**結論**：此 API 已完全符合 Migration v2.0 規範，無需額外修改。✅