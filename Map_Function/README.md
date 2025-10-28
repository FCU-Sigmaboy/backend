# 地理定位功能實作 (Map Function)

這是一個完整的 Vue.js + Supabase + Google Maps 地理定位應用實作，包含前端介面和後端 Edge Function。

## 📁 專案結構

```
Map_Function/
├── frontend/               # 前端實作 (Vue 3)
│   ├── src/
│   │   ├── components/
│   │   │   ├── Auth.vue           # 登入/註冊組件
│   │   │   └── LocationMap.vue    # 地圖組件
│   │   ├── App.vue                # 主應用組件
│   │   ├── main.js                # Vue 應用入口
│   │   └── supabase.js            # Supabase Client 配置
│   ├── .env.example               # 環境變數範例
│   ├── index.html                 # HTML 入口
│   ├── package.json               # 前端依賴
│   └── vite.config.js             # Vite 配置
│
└── backend/                # 後端實作 (Supabase Edge Functions)
    ├── deploy.sh                  # 部署腳本
    └── supabase/
        └── functions/
            ├── save-location/
            │   └── index.ts       # 儲存位置的 Edge Function
            └── _shared/
                └── cors.ts        # CORS 配置
```

## 🗄️ 資料庫結構

本專案使用現有的 `locations` 表（已在主資料庫中定義），包含以下欄位：

```sql
CREATE TABLE public.locations (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    coordinates GEOGRAPHY(Point, 4326) NOT NULL,  -- PostGIS 地理點
    type VARCHAR(50) CHECK (type IN ('家', '公司', '其他')),
    is_primary BOOLEAN NOT NULL DEFAULT false,     -- 主要地點標記
    formatted_address TEXT,                        -- 格式化地址（選填）
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);
```

### 🔒 安全性 (RLS 策略)

資料庫已啟用 Row Level Security：
- ✅ 使用者只能查看自己的位置
- ✅ 使用者只能新增/修改/刪除自己的位置
- ✅ 禁止跨使用者存取

RLS 策略位置：`supabase/migrations/20251025101010_setup_row_level_security.sql:62-67`

## 🚀 前端設定

### 1. 安裝依賴

```bash
cd Map_Function/frontend
npm install
```

### 2. 設定環境變數

複製 `.env.example` 為 `.env`：

```bash
cp .env.example .env
```

編輯 `.env` 並填入以下資訊：

```env
# Supabase 配置
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key-here

# Google Maps API Key
VITE_GOOGLE_MAPS_API_KEY=your-google-maps-api-key-here
```

#### 取得 Supabase 金鑰

1. 前往 [Supabase Dashboard](https://app.supabase.com/)
2. 選擇您的專案
3. 進入 **Settings** > **API**
4. 複製 **Project URL** 和 **anon public** key

#### 取得 Google Maps API Key

1. 前往 [Google Cloud Console](https://console.cloud.google.com/)
2. 建立或選擇專案
3. 啟用 **Maps JavaScript API**
4. 建立 API 金鑰
5. **重要**：設定 HTTP Referrer 限制，確保只有您的網站能使用

### 3. 本地開發

```bash
npm run dev
```

專案會在 `http://localhost:3000` 啟動。

### 4. 使用應用

本專案提供兩種使用方式：

#### 方式 A：使用完整應用（推薦）

完整應用已包含認證和地圖功能，直接啟動即可：

```bash
npm run dev
```

應用會在 `http://localhost:3000` 啟動，包含：
- 登入/註冊介面
- 地圖定位功能
- 登出功能

#### 方式 B：僅使用地圖組件

如果您有自己的認證系統，可以只引入地圖組件：

```vue
<template>
  <div id="app">
    <!-- 確保使用者已登入 -->
    <LocationMap v-if="user" />
  </div>
</template>

<script setup>
import LocationMap from './components/LocationMap.vue'
import { supabase } from './supabase'
import { ref, onMounted } from 'vue'

const user = ref(null)

onMounted(async () => {
  const { data: { session } } = await supabase.auth.getSession()
  user.value = session?.user
})
</script>
```

#### 方式 C：僅使用認證組件

```vue
<template>
  <Auth @login-success="handleLogin" />
</template>

<script setup>
import Auth from './components/Auth.vue'

const handleLogin = (user) => {
  console.log('User logged in:', user)
  // 處理登入後的邏輯
}
</script>
```

## 🔧 後端設定

### 1. 部署 Edge Function

從專案根目錄執行：

```bash
# 本地測試（需要先啟動 supabase local）
npx supabase start
npx supabase functions serve save-location

# 部署到遠端
npx supabase functions deploy save-location --project-ref your-project-ref
```

### 2. 測試 Edge Function

使用 curl 測試：

```bash
# 本地測試
curl -i --location --request POST 'http://localhost:54321/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_USER_JWT_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{
    "latitude": 25.0330,
    "longitude": 121.5654,
    "type": "家",
    "is_primary": true,
    "formatted_address": "台北市信義區"
  }'

# 遠端測試
curl -i --location --request POST 'https://your-project.supabase.co/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_USER_JWT_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{
    "latitude": 25.0330,
    "longitude": 121.5654,
    "type": "公司",
    "is_primary": false
  }'
```

## 📋 API 參考

### Edge Function: `save-location`

**端點**: `POST /functions/v1/save-location`

**Headers**:
```
Authorization: Bearer <JWT_TOKEN>
Content-Type: application/json
```

**Request Body**:
```typescript
{
  latitude: number;          // 必填：緯度 (-90 到 90)
  longitude: number;         // 必填：經度 (-180 到 180)
  type?: string;             // 選填：'家' | '公司' | '其他'，預設 '其他'
  is_primary?: boolean;      // 選填：是否為主要地點，預設 false
  formatted_address?: string; // 選填：格式化地址
}
```

**Response (成功)**:
```json
{
  "success": true,
  "message": "Location saved successfully",
  "data": {
    "id": 123,
    "coordinates": {
      "latitude": 25.0330,
      "longitude": 121.5654
    },
    "type": "家",
    "is_primary": true,
    "created_at": "2025-10-28T12:34:56.789Z"
  }
}
```

**Response (錯誤)**:
```json
{
  "success": false,
  "error": "Error message"
}
```

## 🔐 安全性最佳實踐

### 前端安全
1. ✅ **環境變數管理**：所有 API 金鑰透過 `.env` 檔案管理
2. ✅ **金鑰保護**：`.env` 檔案已加入 `.gitignore`，不會提交到版本控制
3. ✅ **使用者認證**：呼叫 Edge Function 前檢查使用者登入狀態
4. ✅ **錯誤處理**：友善的錯誤訊息，不暴露系統細節

### 後端安全
1. ✅ **JWT 驗證**：Edge Function 驗證使用者身份
2. ✅ **輸入驗證**：嚴格驗證經緯度範圍和資料型別
3. ✅ **RLS 保護**：資料庫層級的安全策略
4. ✅ **Service Role Key**：後端使用 Service Role Key，前端使用 Anon Key

### Google Maps API 保護
1. ✅ **API Key 限制**：在 Google Cloud Console 設定 HTTP Referrer
2. ✅ **配額管理**：監控 API 使用量，避免超額費用

## 🌍 PostGIS 地理查詢範例

由於使用了 PostGIS 的 `GEOGRAPHY` 型別，您可以進行進階地理查詢：

### 尋找附近的地點

```sql
-- 尋找距離某個點 5 公里內的所有地點
SELECT
    id,
    user_id,
    type,
    formatted_address,
    ST_Distance(
        coordinates,
        ST_GeographyFromText('POINT(121.5654 25.0330)')
    ) / 1000 AS distance_km
FROM public.locations
WHERE ST_DWithin(
    coordinates,
    ST_GeographyFromText('POINT(121.5654 25.0330)'),
    5000  -- 5000 公尺 = 5 公里
)
ORDER BY distance_km;
```

### 計算兩點之間的距離

```sql
-- 計算使用者的主要地點與另一個地點的距離
SELECT
    l1.user_id,
    l1.type AS location1_type,
    l2.type AS location2_type,
    ST_Distance(l1.coordinates, l2.coordinates) / 1000 AS distance_km
FROM public.locations l1
CROSS JOIN public.locations l2
WHERE l1.user_id = 'user-uuid-here'
  AND l1.is_primary = true
  AND l2.id = 456;
```

## 🧪 測試流程

### 本地測試

1. **啟動 Supabase 本地環境**：
   ```bash
   npx supabase start
   ```

2. **執行資料庫遷移**：
   ```bash
   npx supabase db reset
   ```

3. **啟動 Edge Function**：
   ```bash
   npx supabase functions serve save-location
   ```

4. **啟動前端開發伺服器**：
   ```bash
   cd Map_Function/frontend
   npm run dev
   ```

5. **註冊測試使用者**：
   - 前往 `http://localhost:3000`
   - 使用 Supabase Auth 註冊帳號

6. **測試定位功能**：
   - 點擊「取得我的位置並顯示在地圖上」按鈕
   - 允許瀏覽器存取位置權限
   - 查看地圖是否正確顯示位置
   - 檢查資料庫中是否成功儲存位置

### 驗證資料

```sql
-- 查詢所有儲存的地點
SELECT
    id,
    user_id,
    ST_AsText(coordinates) AS coordinates_text,
    ST_Y(coordinates::geometry) AS latitude,
    ST_X(coordinates::geometry) AS longitude,
    type,
    is_primary,
    formatted_address,
    created_at
FROM public.locations
ORDER BY created_at DESC;
```

## 📦 前端依賴

- **vue**: ^3.4.0 - Vue.js 框架
- **@supabase/supabase-js**: ^2.39.0 - Supabase JavaScript 客戶端
- **@fawmi/vue-google-maps**: ^0.9.79 - Vue 3 的 Google Maps 組件

## 🛠 開發工具

- **vite**: ^5.0.0 - 快速的前端建構工具
- **@vitejs/plugin-vue**: ^5.0.0 - Vite 的 Vue 插件

## 📝 待辦事項 / 擴展建議

### 功能擴展
- [ ] 新增地址自動完成功能（Google Places Autocomplete）
- [ ] 支援拖曳標記來調整位置
- [ ] 顯示使用者的所有地點列表
- [ ] 支援刪除和編輯地點
- [ ] 路線規劃功能（Google Directions API）

### 效能優化
- [ ] 地圖元件懶載入
- [ ] 位置快取機制
- [ ] 減少不必要的 API 呼叫

### 使用者體驗
- [ ] 深色模式支援
- [ ] 響應式設計優化（手機版）
- [ ] 位置載入動畫
- [ ] 多語言支援 (i18n)

## 🐛 常見問題

### Q1: 無法取得位置權限

**A**: 確認以下事項：
- 瀏覽器是否支援 Geolocation API（檢查 `navigator.geolocation`）
- 是否使用 HTTPS（Chrome 要求 HTTPS 才能使用定位功能）
- 瀏覽器是否已授予位置權限（檢查瀏覽器設定）

### Q2: Google Maps 無法顯示

**A**: 檢查：
- Google Maps API Key 是否正確
- 是否已啟用 Maps JavaScript API
- 瀏覽器 Console 是否有 API Key 相關錯誤

### Q3: Edge Function 呼叫失敗

**A**: 確認：
- 使用者是否已登入（需要有效的 JWT token）
- Supabase 專案 URL 和 Anon Key 是否正確
- Edge Function 是否已成功部署
- CORS 設定是否正確

### Q4: 資料無法儲存到資料庫

**A**: 檢查：
- RLS 策略是否已啟用且正確配置
- 使用者 ID 是否正確傳遞
- 座標格式是否正確（PostGIS 格式）
- 檢查 Supabase Dashboard 的 Logs

## 📄 授權

本專案僅供內部開發使用。

## 👤 作者

生態交換平台開發團隊

---

**最後更新日期**: 2025-10-28
