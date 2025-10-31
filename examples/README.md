# FCU Sigma 物品詳情 API 使用範例

本目錄包含完整的 Supabase 物品詳情 API 使用範例，展示如何在 FCU Sigma 生態交換平台中正確使用地理位置功能和資料庫查詢。

## 🚀 快速開始

### 1. 環境設定

```bash
# 複製環境變數範本
cp ../.env.example .env

# 編輯 .env 檔案，設定您的 Supabase 憑證
nano .env
```

**`.env` 檔案內容範例:**
```env
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### 2. 安裝依賴

```bash
# 安裝必要套件
npm install

# 或者使用 yarn
yarn install
```

### 3. 執行範例

```bash
# 執行所有範例
npm start

# 或者執行特定範例
npm run test:connection    # 連線測試
npm run test:auto         # 自動選擇最佳方式
npm run test:db-location  # 資料庫位置測試
npm run test:coordinates  # 座標位置測試
npm run test:errors       # 錯誤處理測試
```

## 📋 範例說明

### 範例 1: 自動選擇最佳方式
```javascript
const result = await getItemDetailsAuto(itemId, fallbackLocation);
```
- **功能**: 智能選擇使用資料庫位置或提供的座標
- **適用**: 大部分實際應用場景
- **優點**: 自動降級處理，使用者體驗最佳

### 範例 2: 資料庫用戶位置
```javascript
const result = await getItemDetailsWithUserLocation(itemId);
```
- **功能**: 使用 Supabase 資料庫中存儲的用戶位置
- **需求**: 用戶必須已登入且設定地點
- **優點**: 無需每次傳遞座標，效能較佳

### 範例 3: 提供座標位置
```javascript
const result = await getItemDetailsWithCoordinates(itemId, userLocation);
```
- **功能**: 使用即時提供的經緯度座標
- **適用**: 訪客模式或臨時位置查詢
- **優點**: 彈性高，不依賴用戶登入狀態

### 範例 4: 錯誤處理測試
- 測試各種邊界情況
- 驗證參數驗證機制
- 展示友善的錯誤訊息

### 範例 5: 連線測試
- 驗證 Supabase 連線狀態
- 檢查 RPC 函數是否正確部署
- 測試基本資料庫查詢

## 🏗️ 架構說明

### 檔案結構
```
backend/examples/
├── item_detail_usage_example.js  # 主範例檔案
├── package.json                  # 依賴配置
└── README.md                     # 說明文件
```

### 關鍵組件

#### 1. Supabase 初始化
```javascript
import { createClient } from "@supabase/supabase-js";
const supabase = createClient(supabaseUrl, supabaseAnonKey);
```

#### 2. 地理位置計算
使用 PostGIS `ST_Distance` 函數計算距離：
```sql
ST_Distance(item_location, user_location) / 1000.0  -- 轉換為公里
```

#### 3. 認證處理
```javascript
const { data: { user } } = await supabase.auth.getUser();
const isAuthenticated = user !== null;
```

## 📊 回傳資料格式

### 成功回應
```json
{
  "success": true,
  "error": false,
  "message": "物品詳情獲取成功",
  "itemId": 123,
  "data": {
    "id": 123,
    "title": "IKEA 檯燈",
    "description": "全新未使用",
    "condition": "全新",
    "price": 500,
    "carbon_value": "3.50",
    "image_urls": ["url1", "url2"],
    "tags": ["#IKEA", "#檯燈"],
    "distance_km": "1.254",
    "is_favorited": false,
    "is_owner": false,
    "favorites_count": 15,
    "location": {
      "id": 12,
      "formatted_address": "台中市西屯區福星路123號",
      "type": "家",
      "coordinates": {
        "type": "Point",
        "coordinates": [120.645, 24.179]
      }
    },
    "user": {
      "id": "uuid",
      "nickname": "Joseph",
      "profile_picture_url": "https://...",
      "avg_rating": "4.80"
    },
    "category": {
      "sub_category_id": 5,
      "sub_category_name": "燈具",
      "main_category_id": 2,
      "main_category_name": "家居用品"
    },
    "user_location": {
      "has_location": true,
      "coordinates": { ... }
    }
  }
}
```

### 錯誤回應
```json
{
  "success": false,
  "error": true,
  "message": "物品不存在或已下架",
  "itemId": 123,
  "data": null
}
```

## 🔧 故障排除

### 常見問題

#### 1. 連線失敗
```
❌ Supabase 連線測試失敗
```
**解決方案:**
- 檢查 `SUPABASE_URL` 是否正確
- 驗證 `SUPABASE_ANON_KEY` 是否有效
- 確認網路連線正常
- 檢查 Supabase 專案是否啟用

#### 2. RPC 函數不存在
```
❌ RPC 函數不存在，請先執行 SQL migration
```
**解決方案:**
- 執行資料庫 migration 檔案
- 確認 `get_item_details_with_user_location` 函數已建立
- 檢查函數權限設定

#### 3. 認證問題
```
⚠️ 使用者未登入，無法獲取物品詳情
```
**解決方案:**
- 使用 `getItemDetailsWithCoordinates` 替代
- 或提供 fallback location 給 `getItemDetailsAuto`
- 設定測試用戶進行認證測試

#### 4. 地點資料缺失
```
⚠️ 請先設定您的地點以獲得更好的使用體驗
```
**解決方案:**
- 在 `locations` 表中為測試用戶新增地點資料
- 使用座標參數版本的函數
- 檢查 `is_primary` 欄位設定

### 除錯技巧

#### 1. 啟用詳細日誌
```javascript
console.log('Debug info:', {
  itemId,
  userLocation,
  authState: await checkUserAuthentication()
});
```

#### 2. 檢查資料庫狀態
```sql
-- 檢查物品是否存在
SELECT id, title, listing_status FROM items WHERE id = 123;

-- 檢查用戶位置
SELECT * FROM locations WHERE user_id = 'user-uuid';

-- 檢查 RPC 函數
SELECT proname FROM pg_proc WHERE proname LIKE '%item_details%';
```

#### 3. 測試個別組件
```javascript
// 測試基本連線
const { data } = await supabase.from('items').select('id').limit(1);

// 測試認證
const { data: { user } } = await supabase.auth.getUser();

// 測試 RPC
const { data } = await supabase.rpc('get_item_details_with_user_location', {
  p_item_id: 1
});
```

## 🌟 最佳實踐

### 1. 錯誤處理
```javascript
try {
  const result = await getItemDetailsAuto(itemId);
  if (result.success) {
    // 處理成功情況
  } else {
    // 處理失敗情況
    console.log('獲取失敗:', result.message);
  }
} catch (error) {
  // 處理例外情況
  console.error('發生錯誤:', error.message);
}
```

### 2. 效能優化
```javascript
// 批量查詢時使用 Promise.all
const results = await Promise.all(
  itemIds.map(id => getItemDetailsAuto(id))
);

// 快取常用資料
const userLocation = await getCurrentUserLocation();
// 重複使用 userLocation
```

### 3. 用戶體驗
```javascript
// 提供 loading 狀態
console.log('正在載入物品詳情...');

// 友善的錯誤訊息
if (!result.success) {
  if (result.message.includes('登入')) {
    console.log('請先登入以獲得完整功能');
  } else {
    console.log('暫時無法載入，請稍後再試');
  }
}
```

## 📚 相關文件

- [資料庫規格文件](../database-spec.md)
- [Supabase 官方文件](https://supabase.com/docs)
- [PostGIS 文件](https://postgis.net/documentation/)

## 🤝 貢獻

如果您發現問題或有改進建議，請：

1. 建立 Issue 描述問題
2. 提交 Pull Request 包含修正
3. 更新相關文件和測試

## 📄 授權

MIT License - 請參考專案根目錄的 LICENSE 檔案。