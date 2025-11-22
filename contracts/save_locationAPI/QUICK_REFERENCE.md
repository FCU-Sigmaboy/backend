# 快速參考 - 移除 items.location_id Migration

## 🎯 核心變更

**從**: `items.location_id → locations.id`  
**到**: `items.user_id → users.id → locations.user_id (is_primary=true)`

## 📋 執行順序

```
1. ✅ 20251107000001_update_items_location_relationship_jo.sql
   移除外鍵，location_id 改為可選

2. ✅ 20251107000002_update_rpc_functions_use_user_location_jo.sql
   更新所有 RPC 函數的 JOIN 邏輯

3. ✅ 20251107000003_update_create_item_function_jo.sql
   移除 create_item 的 p_user_location_id 參數

   ⏸️ === 暫停：更新前端 ===

4. ⚠️ 20251107000004_remove_location_id_column_jo.sql
   完全刪除 location_id 欄位（不可逆！）
```

## 🔧 前端 API 變更

### Before (舊)
```typescript
await supabase.rpc('create_item', {
  p_sub_category_id: 1,
  p_user_location_id: 123,  // ❌ 移除此參數
  p_title: '物品',
  p_condition: '良好',
  p_price: 100
});
```

### After (新)
```typescript
await supabase.rpc('create_item', {
  p_sub_category_id: 1,
  // p_user_location_id 已移除
  p_title: '物品',
  p_condition: '良好',
  p_price: 100
});
```

## 🔍 快速驗證

```sql
-- 測試搜尋
SELECT * FROM search_items(p_page := 1, p_size := 5);

-- 測試刊登
SELECT create_item(
  p_sub_category_id := 1,
  p_title := '測試',
  p_condition := '良好',
  p_price := 100
);

-- 檢查 location_id 欄位
SELECT column_name 
FROM information_schema.columns 
WHERE table_name = 'items' 
  AND column_name = 'location_id';
-- Migration 1-3: 應返回 1 筆
-- Migration 4: 應返回 0 筆
```

## ⚠️ 重要警告

- **Migration 4 不可逆** - 執行前務必備份！
- **必須先更新前端** - 才能執行 Migration 4
- **測試環境先行** - 不要直接在 Production 執行

## 🔄 回滾方法

### Migration 1-3 (可回滾)
```sql
-- 從 Git history 或備份恢復舊版函數
```

### Migration 4 (困難)
```sql
-- 必須從完整備份恢復
-- 或重新建立欄位並填充資料
```

## 📱 受影響的函數

| 函數 | 變更 |
|------|------|
| `search_items` | JOIN 邏輯更新 |
| `get_my_favorite_items` | JOIN 邏輯更新 |
| `get_item_details_with_location` | JOIN 邏輯更新 |
| `create_item` | **移除 location_id 參數** |

## 📞 問題排查

**錯誤**: "function create_item(..., bigint, ...) does not exist"
- **原因**: 前端仍在傳遞 `p_user_location_id`
- **解決**: 移除該參數

**錯誤**: "請先在個人資料中設定地點後再刊登物品"
- **原因**: 使用者沒有設定任何地點
- **解決**: 引導使用者設定地點

**查詢返回空**: distance_km 全是 NULL
- **原因**: 使用者沒有設定主要地點 (is_primary)
- **解決**: 確保使用者至少有一個 is_primary=true 的地點

## ✅ 完成檢查清單

- [ ] Migration 1 執行並驗證
- [ ] Migration 2 執行並驗證  
- [ ] Migration 3 執行並驗證
- [ ] 前端 API 已更新
- [ ] 前端測試通過
- [ ] 已部署前端到 Production
- [ ] 已備份資料庫
- [ ] Migration 4 執行並驗證
- [ ] 完整功能測試通過

---

**詳細文件**: 參見 `MIGRATION_GUIDE_20251107.md`
