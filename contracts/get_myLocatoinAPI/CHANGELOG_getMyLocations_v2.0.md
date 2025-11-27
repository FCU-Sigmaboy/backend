# getMyLocations API - CHANGELOG v2.0

## 版本資訊
- **版本**: v2.0
- **更新日期**: 2025-11-27
- **變更類型**: API 約定簡化

## 變更摘要

簡化 `getMyLocations()` API 回傳的 JSON 欄位，僅保留前端必要的核心資料。

## 詳細變更

### 移除的欄位
- ❌ `formatted_address` - 格式化地址
- ❌ `created_at` - 建立時間
- ❌ `updated_at` - 更新時間

### 保留的欄位 (前端 JSON 約定)
- ✅ `id` - 地點 ID
- ✅ `coordinates` - PostGIS 地理座標 (GeoJSON Point)
- ✅ `type` - 地點類型 ('家', '公司', '其他')
- ✅ `is_primary` - 是否為主要地點

## 變更前後對比

### v1.0 (舊版)
```javascript
const selectQuery = `
  id,
  coordinates,
  type,
  is_primary,
  formatted_address,
  created_at,
  updated_at
`;
```

**回傳範例**:
```json
{
  "id": 12,
  "coordinates": { "type": "Point", "coordinates": [120.645, 24.179] },
  "type": "家",
  "is_primary": true,
  "formatted_address": "台中市西屯區福星路123號",
  "created_at": "2025-01-20T10:00:00.789+00:00",
  "updated_at": "2025-09-15T11:00:00.000+00:00"
}
```

### v2.0 (新版)
```javascript
const selectQuery = `
  id,
  coordinates,
  type,
  is_primary
`;
```

**回傳範例**:
```json
{
  "id": 12,
  "coordinates": { "type": "Point", "coordinates": [120.645, 24.179] },
  "type": "家",
  "is_primary": true
}
```

## 變更原因

1. **減少資料傳輸量**: 移除非必要欄位，提升效能
2. **簡化前端邏輯**: 地點選擇器只需要基本資訊
3. **符合 Single Responsibility**: API 專注於地點選擇功能
4. **配合 v2.0 架構**: 與資料庫 migration v2.0 保持一致

## 影響範圍

### 前端需要調整的部分
1. **地點選擇器元件**: 確認不依賴 `formatted_address`
2. **地點列表顯示**: 若需顯示地址，使用 `coordinates` 反查或調用其他 API

### 不受影響的部分
- 資料庫 `locations` 表結構未變更
- RLS 權限政策未變更
- 其他 location 相關 API 不受影響

## 建議

若前端需要完整地址資訊，建議：

### 選項 1: 從座標反查地址
```javascript
// 前端使用 Google Maps Geocoding API
const address = await reverseGeocode(coordinates);
```

### 選項 2: 建立專用 API
若多處需要完整資訊，可建立 `getMyLocationDetails(locationId)` API

### 選項 3: 按需查詢
在特定頁面（如地點管理頁）才查詢完整欄位：
```javascript
const { data } = await supabase
  .from('locations')
  .select('*, formatted_address, created_at')
  .eq('id', locationId)
  .single();
```

## 測試檢查清單

- [x] API 回傳欄位與文件一致
- [x] JSDoc 註解更新
- [x] data 範例更新
- [ ] 前端地點選擇器功能正常
- [ ] 前端不依賴已移除欄位
- [ ] 整合測試通過

## 相關文件

- `/database/database-spec.md` - 資料庫規格 (locations 表定義)
- `/docs/MIGRATION_GUIDE_20251107.md` - Migration v2.0 指南
- `/docs/LOCATIONS_PERMISSIONS_QUICK_REF.md` - Locations 權限參考

## 版本歷史

| 版本 | 日期 | 變更 |
|------|------|------|
| v1.0 | 2025-01-20 | 初始版本，包含所有欄位 |
| v2.0 | 2025-11-27 | 簡化為 4 個核心欄位 |

