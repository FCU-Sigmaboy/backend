# Edge Function Staging 部署指南

本文件說明如何將 `save-location` Edge Function 部署到 Supabase Staging 環境。

---

## 📋 目錄

- [前置準備](#前置準備)
- [步驟 1: 設定 Staging 環境變數](#步驟-1-設定-staging-環境變數)
- [步驟 2: 修改部署腳本](#步驟-2-修改部署腳本)
- [步驟 3: 登入 Supabase CLI](#步驟-3-登入-supabase-cli)
- [步驟 4: 部署資料庫 Migrations](#步驟-4-部署資料庫-migrations)
- [步驟 5: 執行 Staging 部署](#步驟-5-執行-staging-部署)
- [步驟 6: 驗證部署](#步驟-6-驗證部署)
- [問題排除](#問題排除)
- [快速執行摘要](#快速執行摘要)

---

## 前置準備

### 1. 確保你有 Staging Supabase 專案

首先，你需要在 Supabase Dashboard 建立一個 staging 專案（如果還沒有的話）：

1. 前往 https://supabase.com/dashboard
2. 建立一個新專案，命名如 `your-project-staging`
3. 記錄以下資訊：

| 資訊 | 位置 | 用途 |
|------|------|------|
| **Project Reference ID** | Settings > General | 部署時使用 |
| **Project URL** | Settings > API | 前端連接使用 |
| **Anon Key** | Settings > API | 前端認證使用 |
| **Service Role Key** | Settings > API | 後端管理使用 |

**範例：**
```
Project Reference ID: abcdefghijk
Project URL: https://abcdefghijk.supabase.co
Anon Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Service Role Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

---

## 步驟 1: 設定 Staging 環境變數

### 1.1 建立 `.env.staging` 檔案

```bash
# 在專案根目錄
cd C:\Users\Chris\IdeaProjects\backend
cp .env.staging.example .env.staging
```

### 1.2 編輯 `.env.staging` 檔案

將你的 staging Supabase 專案資訊填入：

```env
# .env.staging
# Staging 專案設定
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_STAGING_REF.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_staging_anon_key_here
SUPABASE_SERVICE_ROLE_KEY=your_staging_service_role_key_here

# 環境標識
NEXT_PUBLIC_APP_ENV=staging
NODE_ENV=production
```

**實際範例：**
```env
NEXT_PUBLIC_SUPABASE_URL=https://abcdefghijk.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFiY2RlZmdoaWprIiwicm9sZSI6ImFub24iLCJpYXQiOjE2OTg0MDAwMDAsImV4cCI6MjAxMzk3NjAwMH0...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFiY2RlZmdoaWprIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTY5ODQwMDAwMCwiZXhwIjoyMDEzOTc2MDAwfQ...
NEXT_PUBLIC_APP_ENV=staging
NODE_ENV=production
```

---

## 步驟 2: 修改部署腳本

### 2.1 編輯 `deploy.sh`

開啟 `database/functions/Map_function/backend/deploy.sh` 檔案。

### 2.2 修改 Staging Project Reference

找到第 109 行（staging 部署段落）：

```bash
npx supabase functions deploy save-location --project-ref YOUR_STAGING_PROJECT_REF
```

將 `YOUR_STAGING_PROJECT_REF` 替換為你實際的 staging project reference ID。

**修改前：**
```bash
npx supabase functions deploy save-location --project-ref YOUR_STAGING_PROJECT_REF
```

**修改後（範例）：**
```bash
npx supabase functions deploy save-location --project-ref abcdefghijk
```

### 2.3 (可選) 同時修改 Production Project Reference

找到第 140 行（production 部署段落）：

```bash
npx supabase functions deploy save-location --project-ref YOUR_PRODUCTION_PROJECT_REF
```

如果你也有 production 專案，也可以一併修改。

---

## 步驟 3: 登入 Supabase CLI

在部署之前，需要先登入 Supabase CLI：

```bash
npx supabase login
```

**執行過程：**
1. 終端機會顯示一個授權 URL
2. 瀏覽器會自動開啟授權頁面
3. 點擊「Authorize」允許 Supabase CLI 存取你的專案
4. 回到終端機，應該會看到「Logged in successfully」

**如果無法自動開啟瀏覽器：**
```bash
# 手動複製終端機顯示的 URL 並在瀏覽器中開啟
```

---

## 步驟 4: 部署資料庫 Migrations

如果你的 staging 資料庫還沒有建立 `locations` 表和相關結構，需要先執行 migrations。

### 4.1 檢查 Staging 資料庫狀態

前往 Supabase Dashboard > Table Editor，檢查是否已有以下表：
- `users`
- `profiles`
- `locations`
- `main_categories`
- `items`

### 4.2 推送 Migrations

如果資料表尚未建立，執行：

```bash
cd C:\Users\Chris\IdeaProjects\backend

# 推送所有 migrations 到 staging
npx supabase db push --project-ref YOUR_STAGING_PROJECT_REF
```

**範例：**
```bash
npx supabase db push --project-ref abcdefghijk
```

### 4.3 驗證 Migrations

執行完成後，會部署以下 migrations：

| Migration 檔案 | 功能 |
|---------------|------|
| `20251025092807_create_initial_schema.sql` | 建立資料表結構 |
| `20251025101010_setup_row_level_security.sql` | 設定 RLS 安全策略 |
| `20251025180327_setup_storage_rls.sql` | 設定存儲 RLS |
| `20251026142101_setup_public_table_permissions.sql` | 設定公開表權限 |
| `20251026144304_add_columns_main_categories.sql` | 擴展主類別欄位 |
| `20251028085736_get_searchItems_RPC.sql` | 建立搜尋 RPC 函數 |

---

## 步驟 5: 執行 Staging 部署

### 5.1 進入部署腳本目錄

```bash
cd C:\Users\Chris\IdeaProjects\backend\database\functions\Map_function\backend
```

### 5.2 執行部署

```bash
# Linux / macOS / Git Bash
./deploy.sh staging

# Windows CMD / PowerShell
bash deploy.sh staging
```

### 5.3 部署過程

腳本會執行以下步驟：

1. ✅ **檢查 Supabase CLI** - 確認 CLI 已安裝
2. ✅ **檢查 Edge Function 目錄** - 確認 `save-location` 目錄存在
3. ✅ **檢查配置文件** - 確認 `.env.staging.example` 存在
4. ⚠️ **確認提示** - 提示你確認已在 Dashboard 設定好 staging 專案
5. 🚀 **執行部署** - 部署 `save-location` Edge Function
6. ✅ **顯示結果** - 顯示 staging 測試端點

**預期輸出：**
```
======================================
   Supabase Edge Function 部署工具
======================================

部署環境：staging

✓ Supabase CLI 已安裝
✓ Edge Function 目錄存在

開始部署到 Staging 環境...

請確認您已在 Supabase Dashboard 中設定好 staging 專案
按 Enter 繼續，或 Ctrl+C 取消...

✓ Edge Function 已部署到 Staging！

Staging 測試端點：
  https://abcdefghijk.supabase.co/functions/v1/save-location

======================================
          部署完成！
======================================
```

---

## 步驟 6: 驗證部署

### 6.1 檢查 Supabase Dashboard

1. 前往你的 staging Supabase 專案
2. 點擊左側選單 **Edge Functions**
3. 應該會看到 `save-location` 函數已部署
4. 狀態應顯示為「Active」

### 6.2 測試 Edge Function

#### 方法 1: 使用前端測試

如果你有前端應用，更新環境變數為 staging：

```env
VITE_SUPABASE_URL=https://abcdefghijk.supabase.co
VITE_SUPABASE_ANON_KEY=your_staging_anon_key
```

然後執行前端應用測試位置儲存功能。

#### 方法 2: 使用 curl 測試

首先需要取得 JWT token：

**A. 在瀏覽器開發者工具取得 token：**
1. 開啟前端應用並登入
2. 開啟瀏覽器開發者工具 (F12)
3. 前往 Network 標籤
4. 找到任何 Supabase API 請求
5. 複製 `Authorization` header 中的 Bearer token

**B. 使用 curl 測試：**

```bash
curl -i --location --request POST \
  'https://abcdefghijk.supabase.co/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_STAGING_JWT_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{
    "latitude": 25.0330,
    "longitude": 121.5654,
    "type": "家",
    "is_primary": true,
    "formatted_address": "台北市信義區"
  }'
```

**預期成功回應：**
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
    "created_at": "2025-10-30T12:34:56.789Z"
  }
}
```

### 6.3 檢查 Logs

在 Supabase Dashboard 中：

1. 前往 **Edge Functions** > **save-location**
2. 點擊 **Logs** 標籤
3. 查看是否有錯誤訊息或成功日誌

### 6.4 檢查資料庫

在 Supabase Dashboard 中：

1. 前往 **Table Editor** > **locations**
2. 確認剛才測試的資料已成功儲存
3. 檢查欄位值是否正確：
   - `coordinates` (geography 類型)
   - `type`
   - `is_primary`
   - `formatted_address`

---

## 問題排除

### 問題 1: `未找到 Supabase CLI`

**錯誤訊息：**
```
錯誤：未找到 Supabase CLI
請先安裝 Supabase CLI：
  npm install -g supabase
```

**解決方案：**
```bash
# 全域安裝
npm install -g supabase

# 或使用 npx（不需要全域安裝）
npx supabase --version
```

---

### 問題 2: `找不到 Edge Function 目錄`

**錯誤訊息：**
```
錯誤：找不到 Edge Function 目錄
請確認您在 Map_Function/backend 目錄下執行此腳本
```

**解決方案：**
```bash
# 確認當前目錄
pwd

# 正確目錄應該是
# C:\Users\Chris\IdeaProjects\backend\database\functions\Map_function\backend

# 如果不在正確目錄，切換到正確位置
cd C:\Users\Chris\IdeaProjects\backend\database\functions\Map_function\backend
```

---

### 問題 3: `未登入 Supabase CLI`

**錯誤訊息：**
```
Error: You need to be logged in to deploy functions
```

**解決方案：**
```bash
npx supabase login
```

然後在瀏覽器中授權。

---

### 問題 4: `權限錯誤`

**錯誤訊息：**
```
Error: You don't have permission to deploy to this project
```

**解決方案：**
1. 確認你的 Supabase 帳號有該 staging 專案的「Owner」或「Developer」權限
2. 前往 Supabase Dashboard > Settings > Team
3. 確認你的帳號在專案成員列表中
4. 如果不在，請專案擁有者邀請你加入

---

### 問題 5: `CORS 錯誤`

**錯誤訊息（前端測試時）：**
```
Access to fetch at 'https://xxx.supabase.co/functions/v1/save-location'
from origin 'http://localhost:3000' has been blocked by CORS policy
```

**解決方案：**

檢查 `database/functions/Map_function/backend/supabase/functions/_shared/cors.ts`：

```typescript
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*', // 開發環境使用 '*'
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS, PUT, DELETE',
}
```

如果需要限制特定網域（生產環境建議）：

```typescript
export const corsHeaders = {
  'Access-Control-Allow-Origin': 'https://yourdomain.com', // 替換為你的前端網域
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS, PUT, DELETE',
}
```

修改後重新部署：
```bash
./deploy.sh staging
```

---

### 問題 6: `Database migration failed`

**錯誤訊息：**
```
Error: Migration 20251025092807_create_initial_schema.sql failed
```

**解決方案：**

1. **檢查 Staging 資料庫狀態：**
   前往 Supabase Dashboard > Database > Migrations

2. **手動執行 Migration：**
   ```bash
   npx supabase db push --project-ref YOUR_STAGING_REF --debug
   ```

3. **如果 Migration 已經執行過：**
   可以跳過此步驟，直接部署 Edge Function

---

### 問題 7: `Invalid coordinates`

**錯誤訊息（API 回應）：**
```json
{
  "success": false,
  "error": "Invalid coordinates: latitude must be between -90 and 90"
}
```

**解決方案：**

確認傳入的經緯度格式正確：
- `latitude`: -90 到 90 之間的數字
- `longitude`: -180 到 180 之間的數字

**正確範例：**
```json
{
  "latitude": 25.0330,    // 數字類型，不是字串
  "longitude": 121.5654   // 數字類型，不是字串
}
```

**錯誤範例：**
```json
{
  "latitude": "25.0330",  // ❌ 字串類型
  "longitude": "121.5654" // ❌ 字串類型
}
```

---

### 問題 8: `Unauthorized: Invalid or expired token`

**錯誤訊息：**
```json
{
  "success": false,
  "error": "Unauthorized: Invalid or expired token"
}
```

**解決方案：**

1. **確認使用者已登入：**
   ```javascript
   const { data: { session } } = await supabase.auth.getSession()
   console.log('Session:', session) // 應該要有 session 物件
   ```

2. **重新登入取得新 token：**
   ```javascript
   await supabase.auth.signOut()
   await supabase.auth.signInWithPassword({
     email: 'user@example.com',
     password: 'password'
   })
   ```

3. **檢查 Anon Key 是否正確：**
   確認 `.env.staging` 中的 `NEXT_PUBLIC_SUPABASE_ANON_KEY` 是從 staging 專案複製的。

---

## 快速執行摘要

如果你已經準備好所有資訊，可以按照以下步驟快速執行：

### ✅ 部署清單

- [ ] 在 Supabase Dashboard 建立 staging 專案
- [ ] 記錄 staging project reference ID
- [ ] 建立 `.env.staging` 檔案並填入正確的值
- [ ] 修改 `deploy.sh` 中的 `YOUR_STAGING_PROJECT_REF`
- [ ] 登入 Supabase CLI
- [ ] 部署 migrations (如果需要)
- [ ] 執行部署
- [ ] 在 Dashboard 確認 Edge Function 已部署
- [ ] 測試 API 端點
- [ ] 檢查 Logs 確認無錯誤

### 🚀 一鍵執行腳本

```bash
# 1. 登入 Supabase
npx supabase login

# 2. 部署資料庫 migrations（如果需要）
cd C:\Users\Chris\IdeaProjects\backend
npx supabase db push --project-ref YOUR_STAGING_PROJECT_REF

# 3. 部署 Edge Function
cd database\functions\Map_function\backend
bash deploy.sh staging

# 4. 測試 API（替換 YOUR_STAGING_REF 和 YOUR_JWT_TOKEN）
curl -i --location --request POST \
  'https://YOUR_STAGING_REF.supabase.co/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_JWT_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"latitude": 25.0330, "longitude": 121.5654, "type": "家", "is_primary": true}'
```

---

## 部署完成後

### Staging 環境資訊

部署成功後，你的 staging 環境端點為：

```
Edge Function URL:
https://YOUR_STAGING_PROJECT_REF.supabase.co/functions/v1/save-location

Supabase URL:
https://YOUR_STAGING_PROJECT_REF.supabase.co

Dashboard:
https://supabase.com/dashboard/project/YOUR_STAGING_PROJECT_REF
```

### 交付給前端夥伴

將以下資訊提供給前端開發者：

```env
# Staging 環境配置
VITE_SUPABASE_URL=https://YOUR_STAGING_REF.supabase.co
VITE_SUPABASE_ANON_KEY=your_staging_anon_key_here
```

前端使用方式：
```javascript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.VITE_SUPABASE_URL,
  process.env.VITE_SUPABASE_ANON_KEY
)

// 調用 Edge Function
const { data, error } = await supabase.functions.invoke('save-location', {
  body: {
    latitude: 25.0330,
    longitude: 121.5654,
    type: '家',
    is_primary: true
  }
})
```

---

## 下一步

部署到 staging 成功後，你可能需要：

1. **設定 CI/CD Pipeline**
   - 使用 GitHub Actions 自動部署
   - 參考：https://supabase.com/docs/guides/cli/github-action

2. **配置監控和告警**
   - 在 Supabase Dashboard 設定錯誤告警
   - 整合 Sentry 或其他監控工具

3. **準備 Production 部署**
   - 參考本文件步驟，替換為 production 專案資訊
   - 執行 `./deploy.sh production`

4. **撰寫測試腳本**
   - 建立自動化測試 Edge Function 的腳本
   - 整合到 CI/CD pipeline

---

## 相關文件

- [Map Function 完整文檔](README.md)
- [快速開始指南](frontend/QUICK_START.md)
- [整合指南](frontend/INTEGRATION_GUIDE.md)
- [Supabase Edge Functions 官方文檔](https://supabase.com/docs/guides/functions)
- [Supabase CLI 參考](https://supabase.com/docs/reference/cli)

---

**最後更新**：2025-10-30
**版本**：1.0.0
