# CLAUDE.MD - 項目指南文檔

> 本文檔為 Claude AI 助手提供項目的完整上下文和指導方針。

## 項目概覽

這是一個基於 Supabase 的後端專案，主要功能包含地理定位、使用者認證和物品管理系統。

### 技術棧
- **後端框架**: Supabase (PostgreSQL + PostGIS + Edge Functions)
- **前端框架**: Vue 3 + Vite
- **地圖服務**: Google Maps JavaScript API
- **認證系統**: Supabase Auth (JWT)
- **資料庫擴充**: PostGIS (地理空間資料)

### 主要分支
- `main`: 主要分支
- `dev_chris_map`: 當前開發分支（地圖功能）

## 項目結構

```
backend/
├── database/                    # 資料庫相關
│   └── functions/
│       └── Map_function/        # 地圖功能模組
│           ├── backend/
│           │   └── ARCHITECTURE.md
│           ├── frontend/        # Vue 前端應用
│           │   ├── QUICK_START.md
│           │   ├── INTEGRATION_GUIDE.md
│           │   └── SAVE_LOCATION_GUIDE.md
│           └── STAGING_DEPLOYMENT.md
├── supabase/                    # Supabase 設定
│   └── functions/               # Edge Functions
├── Map_Function/                # 地圖功能主目錄
│   ├── USER_FLOW.md            # 使用者流程文檔
│   └── frontend/                # 前端應用
├── contracts/                   # 合約/協議
├── scripts/                     # 腳本工具
├── API_Example/                 # API 範例
└── .env                         # 環境變數（不提交）
```

## 核心功能模組

### 1. 地理定位系統 (Map_Function)

**功能描述**:
- 使用者位置獲取與儲存
- Google Maps 整合
- PostGIS 地理空間查詢
- RLS (Row Level Security) 保護

**關鍵檔案**:
- `Map_Function/frontend/src/App.vue` - 主應用
- `Map_Function/frontend/src/components/Auth.vue` - 認證組件
- `Map_Function/frontend/src/components/LocationMap.vue` - 地圖組件

**API 端點**:
- `POST /functions/v1/save-location` - 儲存使用者位置
  - 需要 JWT 認證
  - 接受 `{latitude, longitude, type?, is_primary?, formatted_address?}`
  - 使用 PostGIS POINT 格式儲存

**資料庫表**:
- `locations` 表結構:
  ```sql
  - id (uuid, primary key)
  - user_id (uuid, foreign key to auth.users)
  - coordinates (geography(Point, 4326))
  - type (text: '家'/'公司'/'其他')
  - is_primary (boolean)
  - formatted_address (text, nullable)
  - created_at (timestamp)
  ```

**RLS 策略**:
- 使用者只能讀取/插入/更新自己的位置資料
- 使用 `auth.uid()` 進行驗證

### 2. RPC 函數

已實現的 RPC 函數:
- `get_my_items` - 獲取使用者的物品
- `get_my_favorite_items` - 獲取使用者收藏的物品

## 環境設定

### 環境變數檔案

專案使用多個環境變數檔案:
- `.env` - 本地開發環境
- `.env.staging` - Staging 環境
- `.env.production.example` - 生產環境範本
- `.env.example` - 環境變數範本

### 前端環境變數 (.env)

```bash
# Supabase
VITE_SUPABASE_URL=your_supabase_url
VITE_SUPABASE_ANON_KEY=your_anon_key

# Google Maps
VITE_GOOGLE_MAPS_API_KEY=your_google_maps_api_key
```

### 後端環境變數

參考 `.env.example` 進行設定。

## 開發工作流程

### 本地開發

1. **啟動 Supabase 本地服務**:
```bash
npx supabase start
```

2. **前端開發**:
```bash
cd Map_Function/frontend
npm install
npm run dev
```

3. **Edge Functions 開發**:
```bash
npx supabase functions serve
```

### Git 工作流程

- 功能開發在各自的 `dev_*` 分支
- 完成後發 PR 到 `main` 分支
- 最近的 commits:
  - 修正 deploy.sh 並新增前端指南
  - 新增 RPC 函數 (get_my_items, get_my_favorite_items)

## 認證流程

### 使用者註冊/登入
1. 使用 Supabase Auth 的 `signUp` / `signInWithPassword`
2. 成功後獲得 JWT Token
3. 前端將 Token 存於 localStorage 或 session
4. 每次 API 呼叫帶上 `Authorization: Bearer <token>`

### Edge Function 認證驗證
```javascript
const authHeader = req.headers.get('Authorization')
const token = authHeader?.replace('Bearer ', '')
const { data: { user }, error } = await supabase.auth.getUser(token)
```

## 常見開發任務

### 新增 RPC 函數

1. 在 Supabase SQL Editor 建立函數
2. 設定適當的 RLS 策略
3. 在前端使用 `supabase.rpc('function_name', params)`

### 新增 Edge Function

1. 建立函數目錄:
```bash
npx supabase functions new function-name
```

2. 實作函數邏輯
3. 本地測試:
```bash
npx supabase functions serve function-name
```

4. 部署:
```bash
npx supabase functions deploy function-name
```

### 修改資料庫 Schema

1. 建立 migration:
```bash
npx supabase migration new migration_name
```

2. 編寫 SQL
3. 套用 migration:
```bash
npx supabase migration up
```

## 測試指南

### 前端測試
- 開發伺服器: `http://localhost:3000`
- 測試帳號建立: 使用 Auth.vue 組件註冊

### 資料庫測試
- Supabase Studio: `http://localhost:54323`
- 使用 SQL Editor 執行查詢
- Table Editor 查看資料

### API 測試
參考 `API_Example/` 目錄中的範例

## 部署指南

### Staging 環境
參考 `database/functions/Map_function/STAGING_DEPLOYMENT.md`

### 部署腳本
使用 `scripts/deploy.sh` 進行部署

## 文檔索引

### 快速開始
- `Map_Function/USER_FLOW.md` - 完整使用者流程說明
- `database/functions/Map_function/frontend/QUICK_START.md` - 前端快速開始

### 整合指南
- `database/functions/Map_function/frontend/INTEGRATION_GUIDE.md` - 前端整合指南
- `database/functions/Map_function/frontend/SAVE_LOCATION_GUIDE.md` - 位置儲存指南

### 架構文檔
- `database/functions/Map_function/backend/ARCHITECTURE.md` - 後端架構說明

## 安全性考量

### 1. 資料存取控制
- 所有資料表都應設定 RLS 策略
- 使用 `auth.uid()` 限制資料存取

### 2. API 安全
- 所有 Edge Functions 都需驗證 JWT
- 驗證輸入資料格式與範圍
- 座標範圍: latitude (-90~90), longitude (-180~180)

### 3. 環境變數
- 絕不提交 `.env` 檔案
- 敏感資訊使用 Supabase Secrets
- API Keys 只在必要時暴露給前端

## 資料庫查詢範例

### 查詢使用者位置
```sql
SELECT
    id,
    ST_Y(coordinates::geometry) AS latitude,
    ST_X(coordinates::geometry) AS longitude,
    type,
    is_primary,
    formatted_address,
    created_at
FROM public.locations
WHERE user_id = auth.uid()
ORDER BY created_at DESC;
```

### 地理範圍查詢 (未來功能)
```sql
SELECT * FROM locations
WHERE ST_DWithin(
    coordinates,
    ST_MakePoint(121.5654, 25.0330)::geography,
    5000  -- 5公里內
);
```

## 開發注意事項

### DO's
- 遵循既有的程式碼風格
- 所有 API 都需要認證
- 使用 PostGIS 函數處理地理資料
- 提供清晰的錯誤訊息給前端
- 更新相關文檔

### DON'Ts
- 不要在前端儲存敏感資料
- 不要跳過 RLS 策略檢查
- 不要硬編碼環境變數
- 不要提交 .env 檔案
- 不要在沒有測試的情況下部署

## 除錯技巧

### 前端除錯
- 檢查瀏覽器 Console
- 使用 Vue DevTools
- 檢查 Network Tab 的 API 請求

### 後端除錯
- 查看 Supabase Logs
- 使用 `console.log` 在 Edge Functions (會出現在 supabase logs)
- 在 SQL Editor 測試查詢

### 常見問題
1. **地圖無法載入**: 檢查 Google Maps API Key
2. **認證失敗**: 確認 JWT Token 正確傳遞
3. **RLS 阻擋**: 檢查 user_id 是否正確
4. **位置無法儲存**: 檢查座標格式與 PostGIS 函數

## 聯絡與支援

- 查看 GitHub Issues
- 參考專案內各 .md 文檔
- 檢查 Supabase 官方文檔

---

**最後更新**: 2025-10-31
**維護者**: FCU-Sigmaboy Team
**版本**: 1.0.0
