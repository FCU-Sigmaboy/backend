# get_ItemDetailsAPI.js - 版本 2.5 更新日誌

**日期：** 2025-11-01  
**版本：** v2.5（優化版）

## 📋 變更摘要

根據優化後的 RPC 函數 `get_item_details_with_location` 重構了 JavaScript API，簡化了實現並遵循 Supabase 最佳實踐。

---

## 🎯 主要改進

### 1. **簡化 API 接口**
- **移除複雜的位置參數**：不再需要傳遞 `p_user_latitude`, `p_user_longitude`, `p_include_distance`
- **自動處理位置**：RPC 函數自動從資料庫獲取用戶的主要地點
- **單一參數**：現在只需要傳遞 `p_item_id`

**之前：**
```javascript
const { data, error } = await supabase
  .rpc("get_item_details_with_location", {
    p_item_id: itemId,
    p_user_latitude: userLatitude,
    p_user_longitude: userLongitude,
    p_include_distance: shouldIncludeDistance,
  })
  .maybeSingle();
```

**之後：**
```javascript
const { data, error } = await supabase
  .rpc("get_item_details_with_location", {
    p_item_id: itemId,
  })
  .maybeSingle();
```

### 2. **移除瀏覽器定位功能**
- **移除** `tryBrowserLocation` 選項
- **移除** `getCurrentLocation()` 輔助函數
- **移除** `isGeolocationSupported()` 檢查函數
- **移除** `checkGeolocationPermission()` 權限檢查

**理由：**
- 簡化實現，減少複雜度
- 統一使用資料庫位置，更可靠
- 減少前端權限請求，改善用戶體驗
- 與 RPC 函數設計保持一致

### 3. **移除多餘的函數**
- **移除** `getItemDetailsWithDatabaseLocation()`（已整合到主函數）
- **移除** `getItemDetailsPublic()`（主函數自動處理未登入用戶）
- **移除** `getItemDetailsWithCoordinates()`（不再支持自定義座標）

**新的簡化使用方式：**
```javascript
// 所有情況都使用同一個函數
const result = await getItemDetails(itemId);
```

### 4. **增強錯誤處理**
- **新增錯誤代碼 (code)**：`INVALID_PARAMETER`, `ITEM_NOT_FOUND`, `INTERNAL_ERROR`
- **標準化錯誤格式**：與 RPC 函數返回的錯誤格式保持一致
- **改進錯誤訊息**：更清晰的錯誤描述

**錯誤處理範例：**
```javascript
const result = await getItemDetails(123);
if (!result.success) {
  switch (result.code) {
    case "INVALID_PARAMETER":
      console.error("參數錯誤:", result.message);
      break;
    case "ITEM_NOT_FOUND":
      console.error("物品不存在:", result.message);
      break;
    case "INTERNAL_ERROR":
      console.error("系統錯誤:", result.message);
      break;
  }
}
```

### 5. **優化數據處理**
- **JSONB 格式支持**：正確處理 PostgreSQL JSONB 格式的座標資料
- **自動解析座標**：智能檢測並解析 GeoJSON 字串或物件
- **保證陣列完整性**：確保 `image_urls` 和 `tags` 始終為陣列

### 6. **新增擁有者標識**
- **新增 `isOwner` 欄位**：回應中明確標識是否為物品擁有者
- **隱私保護邏輯**：擁有者查看自己的物品時，不顯示距離資訊

### 7. **更新文檔和範例**
- **簡化使用範例**：移除過時的 API 調用方式
- **新增 Vue 3 範例**：實用的前端整合範例
- **完整的 API 文檔**：詳細的回傳格式和資料結構說明
- **隱私保護說明**：清楚說明不同用戶角色的可見資料

---

## 📊 對比表

| 項目 | v2.0（舊版） | v2.5（新版） |
|------|-------------|-------------|
| 函數數量 | 7 個 | 2 個 |
| 代碼行數 | ~796 行 | ~500 行 |
| RPC 參數 | 4 個 | 1 個 |
| 位置來源 | 瀏覽器 + 資料庫 | 僅資料庫 |
| 錯誤代碼 | 無 | 3 種標準代碼 |
| 擁有者標識 | 無 | 有 |
| 瀏覽器定位 | 支持 | 移除 |

---

## 🔧 遷移指南

### 更新前端代碼

**之前的調用方式（不再推薦）：**
```javascript
// ❌ 舊方式 1：帶選項參數
const result = await getItemDetails(itemId, { 
  tryBrowserLocation: true,
  includeDistance: true 
});

// ❌ 舊方式 2：使用專用函數
const result = await getItemDetailsPublic(itemId);
const result = await getItemDetailsWithDatabaseLocation(itemId);
```

**新的調用方式（推薦）：**
```javascript
// ✅ 新方式：簡單統一
const result = await getItemDetails(itemId);

// 檢查用戶角色
if (result.isOwner) {
  // 擁有者邏輯
} else if (result.isAuthenticated) {
  // 已登入用戶邏輯
} else {
  // 未登入用戶邏輯
}
```

### 位置策略變更

**之前：**
1. 嘗試瀏覽器定位
2. 失敗則使用資料庫主要地點
3. 再失敗則使用任意地點

**之後：**
1. 直接使用資料庫主要地點
2. 若無主要地點，使用最早建立的地點
3. 若無任何地點，distance_km 為 null

**用戶體驗改進：**
- 不再彈出位置權限請求
- 更快的載入速度（無需等待瀏覽器定位）
- 更一致的距離計算結果

---

## ✅ 測試清單

- [ ] 未登入用戶訪問物品詳情
- [ ] 已登入用戶訪問他人物品
- [ ] 已登入用戶訪問自己的物品
- [ ] 用戶沒有設定地點時的表現
- [ ] 錯誤處理（無效 itemId）
- [ ] 錯誤處理（物品不存在）
- [ ] 座標解析（GeoJSON 字串和物件）
- [ ] 距離顯示邏輯
- [ ] 地圖顯示邏輯

---

## 🚀 效能提升

### 後端（RPC）優化
- 使用 CTE（Common Table Expressions）減少查詢次數
- 使用 JSONB 替代 JSON（更好的效能）
- 使用索引優化查詢（GiST 地理空間索引）
- 提前過濾 `listing_status`

### 前端（API）優化
- 減少函數數量和代碼複雜度
- 移除瀏覽器定位等待時間
- 簡化參數驗證邏輯
- 統一錯誤處理流程

---

## 📝 注意事項

1. **向後不兼容**：舊的 API 調用方式需要更新
2. **位置設定**：提醒用戶在個人資料中設定主要地點
3. **隱私保護**：確保前端正確處理未登入和擁有者的情況
4. **錯誤代碼**：建議使用 `switch` 語句處理不同錯誤類型

---

## 🔗 相關文件

- **RPC 函數**：`/database/functions/get_ItemDetails (RPC)_optimized.sql`
- **API 實現**：`/contracts/get_ItemDetailsAPI.js`
- **資料庫遷移**：`/supabase/migrations/20251101000000_get_ItemDetails_RPC_optimized.sql`

---

## 👥 貢獻者

- 優化設計和實現：AI Assistant
- 日期：2025-11-01

