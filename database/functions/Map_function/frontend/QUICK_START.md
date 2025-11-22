# Map Function 快速開始指南

## 🎯 5 分鐘快速部署

這是最簡化的部署步驟，讓您快速測試地理定位功能。

---

## 📦 已創建的檔案

```
Map_Function/
├── .gitignore                                    # Git 忽略規則
├── README.md                                     # 完整功能文件
├── INTEGRATION_GUIDE.md                          # 集成指南
├── QUICK_START.md                                # ← 您正在閱讀
│
├── frontend/                                     # 前端代碼
│   ├── .env.example                             # 環境變數範例
│   ├── .gitignore                               # 前端忽略規則
│   ├── index.html                               # 測試頁面
│   ├── package.json                             # 依賴列表
│   ├── vite.config.js                           # Vite 配置
│   └── src/
│       ├── main.js                              # Vue 入口
│       ├── supabase.js                          # Supabase Client
│       └── components/
│           └── LocationMap.vue                  # 地圖組件 ⭐
│
└── backend/                                      # 後端代碼
    ├── deploy.sh                                # 部署腳本 ⭐
    └── supabase/
        └── functions/
            ├── _shared/
            │   └── cors.ts                      # CORS 配置
            └── save-location/
                └── index.ts                     # Edge Function ⭐
```

---

## ⚡ 快速部署（本地測試）

### 步驟 1：啟動 Supabase 本地環境

```bash
# 在專案根目錄（backend/）
npx supabase start
```

**輸出範例**：
```
Started supabase local development setup.

         API URL: http://localhost:54321
          DB URL: postgresql://postgres:postgres@localhost:54322/postgres
      Studio URL: http://localhost:54323
```

### 步驟 2：部署 Edge Function

```bash
# 進入 Map_Function/backend 目錄
cd Map_Function/backend

# 執行部署腳本
./deploy.sh local
```

**如果遇到權限問題（Windows Git Bash）**：
```bash
bash deploy.sh local
```

### 步驟 3：設定前端環境變數

```bash
# 進入前端目錄
cd ../frontend

# 複製環境變數範例
cp .env.staging.example .env.staging
```

**編輯 `.env` 檔案**：
```env
# 本地開發環境配置
VITE_SUPABASE_URL=http://localhost:54321
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0

# Google Maps API Key（需要自己申請）
VITE_GOOGLE_MAPS_API_KEY=your-google-maps-api-key-here
```

### 步驟 4：安裝並啟動前端

```bash
# 安裝依賴
npm install

# 啟動開發伺服器
npm run dev
```

瀏覽器會自動開啟 `http://localhost:3000`

### 步驟 5：測試功能

1. **開啟前端應用**
   - 瀏覽器會自動開啟 `http://localhost:3000`
   - 您會看到登入/註冊畫面

2. **註冊新帳號**
   - 在登入畫面點擊「還沒有帳號？點此註冊」
   - 輸入 Email 和密碼（至少 6 個字元）
   - 點擊「註冊」按鈕

   **注意**：本地開發環境預設不需要郵件確認，註冊後會自動登入

3. **登入**（如果已有帳號）
   - 直接輸入 Email 和密碼
   - 點擊「登入」按鈕

4. **測試定位功能**
   - 登入成功後會看到地圖界面
   - 點擊「取得我的位置並顯示在地圖上」按鈕
   - 允許瀏覽器存取位置權限
   - 地圖會顯示您的位置標記
   - 看到「位置已成功儲存到資料庫！」訊息

5. **驗證資料**
   - 開啟 Supabase Studio: `http://localhost:54323`
   - 進入 Table Editor > `locations`
   - 確認資料已成功儲存（可以看到經緯度、類型等資訊）

6. **測試登出**
   - 點擊右上角的「登出」按鈕
   - 應該會返回到登入畫面

---

## 🌍 取得 Google Maps API Key

### 1. 前往 Google Cloud Console
訪問：https://console.cloud.google.com/

### 2. 建立專案
- 點擊頂部的專案選擇器
- 點擊「新增專案」
- 輸入專案名稱

### 3. 啟用 Maps JavaScript API
- 在左側選單選擇「API 和服務」>「程式庫」
- 搜尋「Maps JavaScript API」
- 點擊並啟用

### 4. 建立憑證
- 在左側選單選擇「API 和服務」>「憑證」
- 點擊「建立憑證」>「API 金鑰」
- 複製生成的 API Key

### 5. 限制 API Key（重要！）
- 點擊剛建立的 API Key
- 在「應用程式限制」中選擇「HTTP 參照網址」
- 新增允許的網址：
  - `http://localhost:3000/*` (本地開發)
  - `https://yourdomain.com/*` (生產環境)

---

## 🧪 手動測試 Edge Function

使用 curl 直接測試 Edge Function：

```bash
# 先取得 JWT Token
# 方法 1：從瀏覽器開發者工具的 Network 標籤中複製
# 方法 2：使用 Supabase Client 取得

# 測試 Edge Function
curl -i --location --request POST \
  'http://localhost:54321/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_JWT_TOKEN_HERE' \
  --header 'Content-Type: application/json' \
  --data '{
    "latitude": 25.0330,
    "longitude": 121.5654,
    "type": "家",
    "is_primary": true,
    "formatted_address": "台北市信義區"
  }'
```

**預期成功回應**：
```json
{
  "success": true,
  "message": "Location saved successfully",
  "data": {
    "id": 1,
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

---

## 🚀 生產環境部署

### 1. 部署 Edge Function 到遠端

```bash
cd Map_Function/backend

# 編輯 deploy.sh，修改 YOUR_PRODUCTION_PROJECT_REF
nano deploy.sh  # 或使用您喜歡的編輯器

# 執行部署
./deploy.sh production
```

### 2. 更新前端環境變數

在生產環境的前端專案中設定：

```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-actual-anon-key
VITE_GOOGLE_MAPS_API_KEY=your-google-maps-api-key
```

### 3. 建置並部署前端

```bash
cd Map_Function/frontend

# 建置生產版本
npm run build

# dist/ 目錄中的檔案即為生產版本
# 將其部署到您的主機或 CDN
```

---

## 📊 查詢儲存的位置

在 Supabase Studio 中執行：

```sql
-- 查看所有位置（格式化）
SELECT
    id,
    user_id,
    ST_Y(coordinates::geometry) AS latitude,
    ST_X(coordinates::geometry) AS longitude,
    type,
    is_primary,
    formatted_address,
    created_at
FROM public.locations
ORDER BY created_at DESC;
```

---

## 🐛 常見問題快速解決

### 問題 1：無法取得位置權限
**解決**：
- 確認使用 HTTPS 或 localhost
- 檢查瀏覽器設定是否允許位置存取

### 問題 2：Google Maps 無法載入
**解決**：
- 確認 API Key 正確
- 檢查 Maps JavaScript API 是否已啟用
- 查看瀏覽器 Console 錯誤訊息

### 問題 3：Edge Function 呼叫失敗
**解決**：
```bash
# 檢查 Supabase 是否運行
npx supabase status

# 重新啟動
npx supabase stop
npx supabase start
```

### 問題 4：資料無法儲存
**解決**：
- 確認使用者已登入
- 檢查 Supabase Studio 的 Logs
- 驗證 RLS 策略是否正確

---

## 📚 完整文件

- **[README.md](./README.md)** - 完整功能說明和 API 文件
- **[INTEGRATION_GUIDE.md](./INTEGRATION_GUIDE.md)** - 與主專案集成指南
- **[vue-supabase-geolocation-guide.md](../../vue-supabase-geolocation-guide.md)** - 原始開發規範

---

## ✅ 檢查清單

- [ ] Supabase 本地環境已啟動
- [ ] Edge Function 已部署
- [ ] 前端 `.env` 已配置
- [ ] Google Maps API Key 已取得並限制
- [ ] 前端依賴已安裝
- [ ] 測試帳號已註冊
- [ ] 位置功能測試成功
- [ ] 資料庫中已確認有資料

---

**準備好了嗎？開始部署吧！** 🚀

如有任何問題，請參考完整的 [README.md](./README.md) 或 [INTEGRATION_GUIDE.md](./INTEGRATION_GUIDE.md)。
