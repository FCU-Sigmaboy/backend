# 疑難排解文檔

> 本文檔記錄了在開發 AI 物品圖片分析功能時遇到的所有問題及解決方案
>
> **日期**: 2025-11-02 (初版) | 2025-11-19 (更新)
> **功能**: AI 自動填寫物品刊登資訊

---

## 目錄

### 🚨 Supabase 環境問題
0. [Edge Runtime 503 錯誤 - 服務未啟動](#0-edge-runtime-503-錯誤---服務未啟動) **[NEW - 2025-11-19]**

### AI 功能開發問題
1. [CORS 錯誤 - Edge Function 未部署](#1-cors-錯誤---edge-function-未部署)
2. [Google OAuth 登入失敗](#2-google-oauth-登入失敗)
3. [Google OAuth Redirect 錯誤](#3-google-oauth-redirect-錯誤)
4. [Storage Bucket 不存在](#4-storage-bucket-不存在)
5. [Edge Function 環境變數未載入](#5-edge-function-環境變數未載入)
6. [Docker 網路連線問題](#6-docker-網路連線問題)
7. [大圖片處理堆疊溢位](#7-大圖片處理堆疊溢位)
8. [Gemini API 模型版本錯誤](#8-gemini-api-模型版本錯誤)
9. [Gemini API 參數錯誤](#9-gemini-api-參數錯誤)
10. [JSON 解析錯誤](#10-json-解析錯誤)
11. [AI 分類未自動選擇](#11-ai-分類未自動選擇)
12. [位置建立外鍵約束錯誤](#12-位置建立外鍵約束錯誤)
13. [分類顯示錯誤 - 硬編碼與資料庫不一致](#13-分類顯示錯誤---硬編碼與資料庫不一致)

---

## 0. Edge Runtime 503 錯誤 - 服務未啟動

### 問題描述

呼叫 Edge Function 時出現 503 錯誤：

```
Failed to load resource: the server responded with a status of 503 (Service Temporarily Unavailable)
Error: Edge Function returned a non-2xx status code
```

前端顯示多個圖片上傳成功，但 AI 分析失敗。

### 問題截圖

使用者上傳 8 張圖片，全部顯示：
- 圖片上傳至 Storage 成功 ✅
- 開始分析圖片
- **Edge Function 錯誤: FunctionsHttpError: Edge Function returned a non-2xx status code** ❌

### 根本原因

`supabase_edge_runtime_backend` 服務未正常運行。

執行 `npx supabase status` 時顯示：
```
Stopped services: [supabase_edge_runtime_backend supabase_imgproxy_backend supabase_pooler_backend]
```

常見導致原因：
1. **Storage 遷移失敗**：Supabase CLI 版本過舊（例如 v2.53.6），缺少新版 Storage 遷移文件
2. **容器名稱衝突**：先前的容器未正確清理
3. **Docker 狀態異常**：容器處於 Restarting 或 Unhealthy 狀態

### 診斷方法

#### 步驟 1: 檢查 Supabase 服務狀態

```bash
npx supabase status
```

查看 `Stopped services` 列表，如果包含 `supabase_edge_runtime_backend`，代表服務已停止。

#### 步驟 2: 檢查容器運行狀態

```bash
docker ps --filter "name=supabase" --format "table {{.Names}}\t{{.Status}}"
```

預期輸出（正常狀態）：
```
NAMES                           STATUS
supabase_edge_runtime_backend   Up X seconds
supabase_storage_backend        Up X seconds (healthy)
supabase_db_backend             Up X seconds (healthy)
...
```

如果 `supabase_edge_runtime_backend` 不在列表中，或狀態為 `Restarting`/`Exited`，代表有問題。

#### 步驟 3: 查看錯誤日誌

```bash
# 查看 Edge Runtime 日誌
docker logs supabase_edge_runtime_backend --tail 50

# 查看 Storage 日誌（如果有遷移錯誤）
docker logs supabase_storage_backend --tail 50
```

常見錯誤訊息：
```
Migration iceberg-catalog-ids not found
supabase_storage_backend container is not ready: unhealthy
```

### 解決方案

#### 🔧 標準修復流程（推薦）

**完整步驟**：

```bash
# 步驟 1: 停止所有 Supabase 服務
npx supabase stop

# 步驟 2: 清理所有容器衝突
# Linux / macOS
docker ps -a --filter "name=supabase" -q | xargs -r docker rm -f

# Windows PowerShell
docker ps -a --filter "name=supabase" -q | ForEach-Object { docker rm -f $_ }

# 步驟 3: 使用 beta 版本重新啟動（解決 Storage 遷移問題）
npx supabase@beta start

# 步驟 4: 驗證服務狀態
npx supabase status
docker ps --filter "name=supabase" --format "table {{.Names}}\t{{.Status}}"
```

#### 📝 一鍵修復腳本

**Linux / macOS:**

建立檔案 `scripts/fix-supabase.sh`：

```bash
#!/bin/bash
echo "🔄 停止 Supabase 服務..."
npx supabase stop

echo "🧹 清理容器..."
docker ps -a --filter "name=supabase" -q | xargs -r docker rm -f

echo "🚀 重新啟動 Supabase (beta)..."
npx supabase@beta start

echo "✅ 檢查服務狀態..."
npx supabase status

echo ""
echo "📊 容器狀態："
docker ps --filter "name=supabase" --format "table {{.Names}}\t{{.Status}}"
```

執行：
```bash
chmod +x scripts/fix-supabase.sh
./scripts/fix-supabase.sh
```

**Windows PowerShell:**

建立檔案 `scripts/Fix-Supabase.ps1`：

```powershell
Write-Host "🔄 停止 Supabase 服務..." -ForegroundColor Yellow
npx supabase stop

Write-Host "🧹 清理容器..." -ForegroundColor Yellow
docker ps -a --filter "name=supabase" -q | ForEach-Object { docker rm -f $_ }

Write-Host "🚀 重新啟動 Supabase (beta)..." -ForegroundColor Yellow
npx supabase@beta start

Write-Host "✅ 檢查服務狀態..." -ForegroundColor Green
npx supabase status

Write-Host ""
Write-Host "📊 容器狀態：" -ForegroundColor Cyan
docker ps --filter "name=supabase" --format "table {{.Names}}\t{{.Status}}"
```

執行：
```powershell
.\scripts\Fix-Supabase.ps1
```

### 驗證修復成功

#### 1. 檢查服務狀態

```bash
npx supabase status
```

預期輸出（不應有 Stopped services）：
```
API URL: http://127.0.0.1:54321
...
Stopped services: []  # 應該是空的
supabase local development setup is running.
```

#### 2. 確認 Edge Runtime 正在運行

```bash
docker ps --filter "name=supabase_edge_runtime" --format "table {{.Names}}\t{{.Status}}"
```

預期輸出：
```
NAMES                           STATUS
supabase_edge_runtime_backend   Up About a minute
```

狀態應該是 `Up`，而非 `Restarting` 或 `Exited`。

#### 3. 測試 Edge Function

刷新前端頁面，重新上傳圖片並點擊「AI 自動填寫」，應該能夠成功分析。

### 為什麼使用 `npx supabase@beta start`？

- **解決 Storage 遷移問題**：beta 版本包含最新的 Storage 遷移文件
- **向後兼容**：beta 版本仍然兼容現有的資料庫和配置
- **避免 CLI 升級**：不需要全域安裝新版本的 Supabase CLI

### 常見問題

**Q: 為什麼不直接升級 Supabase CLI？**

A: 全域升級可能影響其他專案。使用 `npx supabase@beta` 可以在當前專案使用最新版本，而不影響系統全域設定。

**Q: 每次啟動都需要用 beta 版本嗎？**

A: 是的。建議在專案的 `package.json` 中新增腳本：

```json
{
  "scripts": {
    "supabase:start": "npx supabase@beta start",
    "supabase:stop": "npx supabase stop",
    "supabase:status": "npx supabase status"
  }
}
```

**Q: 資料會遺失嗎？**

A: 不會。Supabase 本地資料儲存在 Docker volumes 中：
```bash
docker volume ls --filter label=com.supabase.cli.project=backend
```

除非刪除 volumes，否則資料會保留。

**Q: 如果還是失敗怎麼辦？**

A: 完全重置環境（⚠️ 會刪除所有本地資料）：

```bash
# 停止服務
npx supabase stop

# 刪除所有容器
docker ps -a --filter "name=supabase" -q | xargs -r docker rm -f

# 刪除所有 volumes（資料將被刪除！）
docker volume ls --filter label=com.supabase.cli.project=backend -q | xargs -r docker volume rm

# 重新啟動
npx supabase@beta start

# 執行資料庫遷移和種子
npx supabase db reset
```

### 相關問題

- [#4 Storage Bucket 不存在](#4-storage-bucket-不存在)
- [#5 Edge Function 環境變數未載入](#5-edge-function-環境變數未載入)

### 成功案例

**問題回報日期**: 2025-11-19

**問題描述**：使用者上傳 8 張圖片進行 AI 分析，全部出現 503 錯誤。

**解決過程**：
1. 檢查 `npx supabase status`，發現 `supabase_edge_runtime_backend` 已停止
2. 嘗試使用 `npx supabase start` 重啟，出現 Storage 遷移錯誤
3. 清理容器並使用 `npx supabase@beta start`
4. 所有服務成功啟動，AI 分析恢復正常

**修復時間**: 約 5 分鐘

---

## 1. CORS 錯誤 - Edge Function 未部署

### 問題描述

前端嘗試呼叫 `analyze-item-image` Edge Function 時出現 CORS 錯誤：

```
Access to fetch at 'https://rsubfpxltwkrdejnvzxw.supabase.co/functions/v1/analyze-item-image'
from origin 'http://localhost:5174' has been blocked by CORS policy
```

### 根本原因

- 前端連接到**遠端 Supabase** (`https://rsubfpxltwkrdejnvzxw.supabase.co`)
- `analyze-item-image` Edge Function 只存在於本地環境，尚未部署到遠端

### 解決方案

將前端環境變數切換到本地 Supabase：

**修改檔案**: `frontend-demo/.env`

```bash
# 本地開發環境
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0

# 遠端環境（暫時註解）
# VITE_SUPABASE_URL=https://rsubfpxltwkrdejnvzxw.supabase.co
# VITE_SUPABASE_ANON_KEY=your-remote-anon-key
```

### 驗證

重新啟動前端，確認連接到本地 Supabase：
```bash
cd frontend-demo
npm run dev
```

---

## 2. Google OAuth 登入失敗

### 問題描述

點選「使用 Google 登入」時出現錯誤：

```json
{
  "code": 400,
  "error_code": "validation_failed",
  "msg": "Unsupported provider: provider is not enabled"
}
```

### 根本原因

本地 Supabase 環境沒有啟用 Google OAuth provider。遠端和本地是獨立的環境，需要分別設定。

### 解決方案

#### 步驟 1: 啟用 Google OAuth

**修改檔案**: `supabase/config.toml`

```toml
[auth.external.google]
enabled = true
client_id = "env(GOOGLE_CLIENT_ID)"
secret = "env(GOOGLE_CLIENT_SECRET)"
skip_nonce_check = true  # 本地開發必須啟用
```

#### 步驟 2: 設定環境變數

**修改檔案**: `supabase/.env.local`

```bash
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret
```

#### 步驟 3: 取得 Google OAuth 憑證

**方式 A - 從遠端 Supabase 複製**（推薦）:

1. 前往：https://supabase.com/dashboard/project/YOUR_PROJECT_ID/auth/providers
2. 點選 **Google** provider
3. 複製 **Client ID** 和 **Client Secret**

**方式 B - 建立新憑證**:

1. 前往：https://console.cloud.google.com/apis/credentials
2. 建立 OAuth 2.0 用戶端 ID
3. 設定 Redirect URIs（見下一節）

#### 步驟 4: 重啟 Supabase

```bash
npx supabase stop
npx supabase start
```

### 相關文檔

詳細設定步驟請參考：`supabase/GOOGLE_OAUTH_SETUP.md`

---

## 3. Google OAuth Redirect 錯誤

### 問題描述

Google OAuth 授權後，瀏覽器顯示「127.0.0.1:3000 拒絕連線」。

### 根本原因

`supabase/config.toml` 中的 `site_url` 設定為 `http://127.0.0.1:3000`，但前端實際運行在 port `5174`。

### 解決方案

#### 步驟 1: 修正 Supabase 配置

**修改檔案**: `supabase/config.toml`

```toml
[auth]
enabled = true
site_url = "http://localhost:5174"  # 修正為前端實際 port
additional_redirect_urls = [
  "http://127.0.0.1:5174",
  "http://localhost:5174"
]
```

#### 步驟 2: 更新 Google Cloud Console

前往：https://console.cloud.google.com/apis/credentials

**已授權的重新導向 URI**（必須包含這 4 個）:
```
http://127.0.0.1:54321/auth/v1/callback
http://localhost:54321/auth/v1/callback
http://127.0.0.1:5174
http://localhost:5174
```

**已授權的 JavaScript 來源**:
```
http://127.0.0.1:54321
http://localhost:54321
http://127.0.0.1:5174
http://localhost:5174
```

#### 步驟 3: 重啟 Supabase

```bash
npx supabase stop
npx supabase start
```

### OAuth 流程說明

```
前端 (localhost:5174)
  ↓ 點選 Google 登入
Supabase Auth (127.0.0.1:54321)
  ↓ Redirect to Google
Google OAuth 同意畫面
  ↓ 授權後 redirect
Supabase Callback (127.0.0.1:54321/auth/v1/callback)
  ↓ 處理 token
Redirect 回前端 (localhost:5174)
  ↓
✅ 登入成功
```

---

## 4. Storage Bucket 不存在

### 問題描述

上傳圖片時出現錯誤：

```
StorageApiError: Bucket not found
```

### 根本原因

雖然 `supabase/config.toml` 有定義 `items` bucket，但該配置只在**初次啟動**時生效。如果 Supabase 是在配置 bucket 之前啟動的，就不會自動建立。

### 解決方案

#### 步驟 1: 建立 Migration

**建立檔案**: `supabase/migrations/20251102100057_create_storage_buckets.sql`

```sql
-- Create Storage Buckets for local development
-- Date: 2025-11-02
-- Description: Create avatars and items storage buckets

-- 1. Create avatars bucket for user profile images
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'avatars',
    'avatars',
    true,
    52428800,  -- 50MB in bytes
    ARRAY['image/png', 'image/jpeg', 'image/jpg', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- 2. Create items bucket for item images
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'items',
    'items',
    true,
    10485760,  -- 10MB in bytes
    ARRAY['image/png', 'image/jpeg', 'image/jpg', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;
```

#### 步驟 2: 套用 Migration

```bash
npx supabase db reset --local
```

### 驗證

檢查 Supabase Studio：
1. 開啟：http://127.0.0.1:54323
2. 點選左側選單：**Storage**
3. 應該會看到 `items` 和 `avatars` 兩個 buckets

---

## 5. Edge Function 環境變數未載入

### 問題描述

Edge Function 執行時顯示：

```
[Error] GEMINI_API_KEY is not set!
```

Docker logs 也顯示環境變數未載入。

### 根本原因

本地 Supabase 的 Edge Runtime 不會自動讀取 `supabase/.env.local`，需要在 `config.toml` 中明確設定。

### 解決方案

#### 步驟 1: 在 config.toml 設定環境變數

**修改檔案**: `supabase/config.toml`

```toml
[edge_runtime.secrets]
GEMINI_API_KEY = "env(GEMINI_API_KEY)"
```

這會讓 Edge Runtime 從 `supabase/.env.local` 讀取 `GEMINI_API_KEY` 並注入到 Edge Function 環境中。

#### 步驟 2: 確認 .env.local 有設定

**檔案**: `supabase/.env.local`

```bash
GEMINI_API_KEY=AIzaSyDBLZdbiyYUDWnEETMUD-hKZCbL96hzY-o
```

#### 步驟 3: 重啟 Supabase

```bash
npx supabase stop
npx supabase start
```

### 驗證

查看 Docker logs：
```bash
docker logs supabase_edge_runtime_backend --follow
```

觸發 AI 分析後，應該**不會**再看到 "GEMINI_API_KEY is not set!" 錯誤。

### 取得 Gemini API Key

1. 前往：https://aistudio.google.com/app/apikey
2. 登入 Google 帳號
3. 點擊 "Create API Key"
4. 複製 API Key 到 `supabase/.env.local`

---

## 6. Docker 網路連線問題

### 問題描述

Edge Function 嘗試讀取圖片時出現錯誤：

```
[Error] 圖片轉換失敗: TypeError: error sending request for url
(http://127.0.0.1:54321/storage/...): client error (Connect):
tcp connect error: Connection refused
```

### 根本原因

Edge Function 在 Docker 容器內執行，容器內的 `127.0.0.1` 指向**容器自己**，而不是宿主機的 Supabase Storage。

### 解決方案

將 Storage URL 替換為 Docker 內部網路地址。

**修改檔案**: `supabase/functions/analyze-item-image/index.ts`

```typescript
try {
  // 將外部 URL (127.0.0.1:54321) 轉換為 Docker 內部 URL
  // 在 Docker 容器內，通過 Kong API Gateway 存取
  let fetchUrl = image_url
  if (image_url.includes('127.0.0.1:54321') || image_url.includes('localhost:54321')) {
    // 本地開發環境：使用 Kong 容器作為 API Gateway
    fetchUrl = image_url
      .replace('http://127.0.0.1:54321', 'http://supabase_kong_backend:8000')
      .replace('http://localhost:54321', 'http://supabase_kong_backend:8000')
  }

  console.log(`Fetching image from: ${fetchUrl}`)
  const imageResponse = await fetch(fetchUrl)
  // ...
}
```

### Docker 網路架構

```
Edge Function (容器內)
    ↓
supabase_kong_backend:8000 (API Gateway)
    ↓
supabase_storage_backend:5000 (Storage 服務)
    ↓
返回圖片
```

### 為什麼要用 Kong？

- Storage 服務 (`supabase_storage_backend:5000`) 不直接暴露
- 所有 API 請求都通過 Kong API Gateway 路由
- Kong 處理認證、限流等中間件邏輯

---

## 7. 大圖片處理堆疊溢位

### 問題描述

上傳大圖片時出現錯誤：

```
[Error] 圖片轉換失敗: RangeError: Maximum call stack size exceeded
```

### 根本原因

原本的 base64 編碼使用展開運算符：

```typescript
const bytes = new Uint8Array(arrayBuffer)
imageBase64 = btoa(String.fromCharCode(...bytes))  // ❌ 大圖片會 stack overflow
```

當圖片過大時，`...bytes` 展開會超過 JavaScript 的呼叫堆疊大小限制。

### 解決方案

改用 for 迴圈逐字節處理。

**修改檔案**: `supabase/functions/analyze-item-image/index.ts`

```typescript
const imageBlob = await imageResponse.blob()
imageMimeType = imageBlob.type || 'image/jpeg'
const arrayBuffer = await imageBlob.arrayBuffer()
const bytes = new Uint8Array(arrayBuffer)

// 使用更高效的 base64 編碼方式，避免 call stack overflow
let binary = ''
const len = bytes.byteLength
for (let i = 0; i < len; i++) {
  binary += String.fromCharCode(bytes[i])
}
imageBase64 = btoa(binary)

console.log(`圖片已轉換為 base64, MIME type: ${imageMimeType}`)
```

### 效能比較

| 方法 | 小圖片 (<1MB) | 大圖片 (>5MB) |
|------|--------------|--------------|
| `...bytes` 展開 | ✅ 快速 | ❌ Stack overflow |
| for 迴圈 | ✅ 稍慢 | ✅ 穩定處理 |

---

## 8. Gemini API 模型版本錯誤

### 問題描述

呼叫 Gemini API 時出現錯誤：

```json
{
  "error": {
    "code": 404,
    "message": "models/gemini-1.5-flash is not found for API version v1beta",
    "status": "NOT_FOUND"
  }
}
```

### 根本原因

Google 的模型名稱已更新，`gemini-1.5-flash` 已經不存在或被重新命名。

### 解決方案

#### 步驟 1: 查詢可用模型

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models?key=YOUR_API_KEY"
```

#### 步驟 2: 更新為正確的模型名稱

**修改檔案**: `supabase/functions/analyze-item-image/index.ts`

```typescript
// 使用 gemini-2.5-flash (穩定版本)
const geminiResponse = await fetch(
  `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`,
  {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      // ...
    })
  }
)
```

### 可用的 Gemini 模型 (2025-11-02)

| 模型名稱 | 版本 | 說明 | 輸入限制 | 輸出限制 |
|---------|------|------|---------|---------|
| `gemini-2.5-flash` | 穩定版 | 快速多模態模型 | 1M tokens | 65K tokens |
| `gemini-2.5-pro` | 穩定版 | 高性能模型 | 1M tokens | 65K tokens |
| `gemini-2.0-flash` | 穩定版 | 2.0 快速版本 | 1M tokens | 8K tokens |
| `gemini-flash-latest` | 最新版 | 自動使用最新版本 | 1M tokens | 65K tokens |

### 推薦

使用 `gemini-2.5-flash` - 穩定且免費，支援圖片分析。

---

## 9. Gemini API 參數錯誤

### 問題描述

```json
{
  "error": {
    "code": 400,
    "message": "Invalid JSON payload received. Unknown name \"responseMimeType\"",
    "status": "INVALID_ARGUMENT"
  }
}
```

### 根本原因

`v1beta` API 的某些版本不支援 `responseMimeType` 參數。

### 解決方案

移除 `responseMimeType` 參數，改為在 prompt 中要求 JSON 格式。

**修改檔案**: `supabase/functions/analyze-item-image/index.ts`

```typescript
body: JSON.stringify({
  contents: [
    {
      parts: [
        {
          text: `你是一個專業的二手物品分析專家。請根據圖片分析物品，並以繁體中文回答。

【回傳格式】
請嚴格按照以下 JSON 格式回傳（不要包含任何其他文字）：
{
  "title": "物品名稱",
  "description": "詳細描述",
  "sub_category_id": 分類ID,
  "carbon_value": 碳足跡值,
  "tags": ["標籤1", "標籤2"],
  "confidence": 0.95,
  "warnings": []
}

請分析這個物品的圖片，提供詳細資訊。`
        },
        {
          inline_data: {
            mime_type: imageMimeType,
            data: imageBase64
          }
        }
      ]
    }
  ],
  generationConfig: {
    temperature: 0.7,
    maxOutputTokens: 1000
    // ❌ 移除 responseMimeType: "application/json"
  }
})
```

### 依賴 Prompt 要求格式

雖然沒有 `responseMimeType`，但透過 prompt 明確要求，Gemini 仍會返回 JSON 格式。

---

## 10. JSON 解析錯誤

### 問題描述

```
SyntaxError: Unexpected token '`', "```json..." is not valid JSON
```

### 根本原因

Gemini 返回的 JSON 被包在 markdown 代碼塊中：

```
```json
{
  "title": "...",
  ...
}
```
```

直接解析會失敗。

### 解決方案

在解析前移除 markdown 標記。

**修改檔案**: `supabase/functions/analyze-item-image/index.ts`

```typescript
// 從 Gemini 回應中提取文字
let generatedText = aiResult.candidates?.[0]?.content?.parts?.[0]?.text
if (!generatedText) {
  throw new Error('Gemini API 未回傳有效內容')
}

// 移除 markdown 代碼塊標記（如果存在）
generatedText = generatedText.trim()
if (generatedText.startsWith('```json')) {
  generatedText = generatedText.replace(/^```json\s*\n/, '').replace(/\n```\s*$/, '')
} else if (generatedText.startsWith('```')) {
  generatedText = generatedText.replace(/^```\s*\n/, '').replace(/\n```\s*$/, '')
}

const analysisResult = JSON.parse(generatedText.trim())
```

### 處理流程

```
Gemini 回應
  ↓
```json\n{...}\n```
  ↓
移除 ```json 和 ```
  ↓
{...}
  ↓
JSON.parse()
  ↓
✅ 成功解析
```

---

## 完整流程驗證

### 成功的 AI 分析流程

1. **使用者登入** (Google OAuth)
2. **上傳圖片** → `items` bucket
3. **點選 AI 自動填寫**
4. **Edge Function 處理**:
   ```
   讀取圖片 URL
     ↓
   通過 Kong Gateway 獲取圖片
     ↓
   逐字節轉換為 base64
     ↓
   呼叫 Gemini 2.5 Flash API
     ↓
   移除 markdown 標記
     ↓
   解析 JSON 回應
     ↓
   驗證分類 ID
     ↓
   返回結果
   ```
5. **前端自動填入**:
   - ✅ 標題
   - ✅ 描述
   - ✅ 分類
   - ✅ 碳足跡值
   - ✅ 標籤
   - ✅ 信心度

### 範例成功日誌

```
[Info] User 4ac899e1-9290-468d-b496-dce81073b66f is analyzing an image
[Info] Analyzing image: http://127.0.0.1:54321/storage/v1/object/public/items/1762079563477_cup.webp
[Info] Found 36 categories
[Info] Fetching image from: http://supabase_kong_backend:8000/storage/v1/object/public/items/1762079563477_cup.webp
[Info] 圖片已轉換為 base64, MIME type: image/webp
[Info] Gemini API 回應: {...}
[Info] AI analysis completed: {
  "title": "簡約白色陶瓷馬克杯",
  "description": "這是一個簡約風格的白色陶瓷馬克杯...",
  "sub_category_id": 66,
  "carbon_value": 1.2,
  "tags": ["馬克杯", "陶瓷", "白色", "廚房用具", "簡約"],
  "confidence": 0.98,
  "warnings": []
}
```

---

## 修改檔案總覽

### 配置檔案

| 檔案 | 修改內容 | 目的 |
|------|---------|------|
| `frontend-demo/.env` | 切換到本地 Supabase URL | 連接本地環境 |
| `supabase/config.toml` | 啟用 Google OAuth<br>設定 site_url<br>設定 edge_runtime.secrets | OAuth 登入<br>正確 redirect<br>環境變數載入 |
| `supabase/.env.local` | GEMINI_API_KEY<br>GOOGLE_CLIENT_ID<br>GOOGLE_CLIENT_SECRET | Edge Function 環境變數 |

### Migration 檔案

| 檔案 | 內容 |
|------|------|
| `supabase/migrations/20251102100057_create_storage_buckets.sql` | 建立 items 和 avatars buckets |

### Edge Function

| 檔案 | 修改內容 |
|------|---------|
| `supabase/functions/analyze-item-image/index.ts` | API Key 檢查<br>Docker 網路 URL 轉換<br>改進的 base64 編碼<br>使用 gemini-2.5-flash<br>移除 responseMimeType<br>Markdown 清理 |

### 文檔

| 檔案 | 內容 |
|------|------|
| `supabase/GOOGLE_OAUTH_SETUP.md` | Google OAuth 詳細設定指南 |
| `TROUBLESHOOTING.md` | 本文檔 - 完整問題解決記錄 |

---

## 常用除錯指令

### 查看 Edge Function 日誌

```bash
docker logs supabase_edge_runtime_backend --follow
```

### 查看所有 Supabase 容器

```bash
docker ps --filter "name=supabase"
```

### 重啟 Supabase

```bash
npx supabase stop
npx supabase start
```

### 重置資料庫（套用所有 migrations）

```bash
npx supabase db reset --local
```

### 查看 Supabase 狀態

```bash
npx supabase status
```

### 查詢 Gemini 可用模型

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models?key=YOUR_API_KEY"
```

---

## 部署到遠端

如果要將此功能部署到遠端 Supabase，需要：

### 1. 設定遠端環境變數

```bash
npx supabase secrets set GEMINI_API_KEY=your-api-key
```

### 2. 部署 Edge Function

```bash
npx supabase functions deploy analyze-item-image
```

### 3. 建立遠端 Storage Bucket

在 Supabase Dashboard:
1. 前往 Storage
2. 建立 `items` bucket
3. 設定為 public
4. 設定 RLS policies

### 4. 切換前端環境變數

**修改**: `frontend-demo/.env`

```bash
VITE_SUPABASE_URL=https://rsubfpxltwkrdejnvzxw.supabase.co
VITE_SUPABASE_ANON_KEY=your-remote-anon-key
```

### 5. 更新 Edge Function (如果需要)

移除 Docker 網路 URL 轉換邏輯，因為遠端環境不需要：

```typescript
// 遠端環境直接使用原始 URL
const fetchUrl = image_url
const imageResponse = await fetch(fetchUrl)
```

---

## 相關資源

### Supabase 文檔

- [Local Development](https://supabase.com/docs/guides/cli/local-development)
- [Edge Functions](https://supabase.com/docs/guides/functions)
- [Storage](https://supabase.com/docs/guides/storage)
- [Auth Providers](https://supabase.com/docs/guides/auth/social-login/auth-google)

### Google 文檔

- [Gemini API](https://ai.google.dev/gemini-api/docs)
- [Google Cloud Console](https://console.cloud.google.com/)
- [OAuth 2.0](https://developers.google.com/identity/protocols/oauth2)

### 專案文檔

- `CLAUDE.md` - 專案完整指南
- `supabase/GOOGLE_OAUTH_SETUP.md` - Google OAuth 設定
- `Map_Function/USER_FLOW.md` - 使用者流程

---

## 11. AI 分類未自動選擇

### 問題描述

AI 分析完成後，雖然回傳了 `sub_category_id`，但前端的分類下拉選單沒有自動選擇對應的主分類。

### 根本原因

- AI 回傳的是 `sub_category_id`（子分類 ID）
- 前端下拉選單顯示的是 `main_category_id`（主分類 ID）
- 沒有將子分類 ID 對應到主分類 ID

### 解決方案

修改 `frontend-demo/src/views/CreateListingPage.vue` 的 `analyzeWithAI` 函數：

```javascript
// 儲存 AI 回傳的子分類 ID
formData.value.subcategoryId = aiData.sub_category_id;

// 查詢對應的主分類 ID
if (aiData.sub_category_id) {
  const { data: subCat, error: subCatError } = await supabase
    .from('sub_categories')
    .select('main_category_id')
    .eq('id', aiData.sub_category_id)
    .single();

  if (subCat) {
    // 設定下拉選單的值為主分類 ID
    formData.value.category = String(subCat.main_category_id);
  }
}
```

同時更新 `formData` 結構：

```javascript
const formData = ref({
  images: [],
  title: '',
  category: '',         // main_category_id (用於顯示下拉選單)
  subcategoryId: null,  // sub_category_id (用於發布時提交)
  description: '',
  // ...
});
```

### 驗證

1. 上傳圖片並點擊「AI 自動填寫」
2. AI 分析完成後，分類下拉選單應該自動選擇對應的主分類
3. 發布時會使用 AI 回傳的精確子分類 ID

---

## 12. 位置建立外鍵約束錯誤

### 問題描述

使用 Google OAuth 登入後刊登物品時出現錯誤：

```
insert or update on table "locations" violates foreign key constraint "locations_user_id_fkey"
```

### 根本原因

- `locations` 表的 `user_id` 外鍵參考 `public.users(id)`
- Google OAuth 使用者只會在 `auth.users` 建立記錄
- 沒有自動同步到 `public.users` 表

### 解決方案

#### 步驟 1: 建立觸發器自動同步使用者

建立新的 migration：`supabase/migrations/20251102111257_handle_new_user_signup.sql`

```sql
-- Auto-create public.users record when auth.users is created
-- Date: 2025-11-02
-- Purpose: Sync OAuth user signup to public.users table

-- Create trigger function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, nickname, profile_picture_url, created_at, updated_at)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'name', NEW.email, 'User_' || substring(NEW.id::text, 1, 8)),
        NEW.raw_user_meta_data->>'avatar_url',
        NEW.created_at,
        NEW.updated_at
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- Backfill existing auth.users to public.users (if missing)
INSERT INTO public.users (id, nickname, profile_picture_url, created_at, updated_at)
SELECT
    id,
    COALESCE(raw_user_meta_data->>'name', email, 'User_' || substring(id::text, 1, 8)),
    raw_user_meta_data->>'avatar_url',
    created_at,
    updated_at
FROM auth.users
WHERE NOT EXISTS (
    SELECT 1 FROM public.users WHERE public.users.id = auth.users.id
)
ON CONFLICT (id) DO NOTHING;
```

#### 步驟 2: 套用 Migration

```bash
cd supabase
npx supabase db reset
```

#### 步驟 3: 修改前端位置建立邏輯

修改 `frontend-demo/src/views/CreateListingPage.vue` 的 `handleSubmit` 函數：

```javascript
// 如果使用者沒有位置，建立預設位置
const { data: newLocation, error: createLocationError } = await supabase
  .from('locations')
  .insert({
    user_id: user.id,
    coordinates: 'POINT(121.5654 25.0330)',  // 台北101座標
    type: '其他',
    is_primary: true,
    formatted_address: '台北市信義區'
  })
  .select('id')
  .single();

if (createLocationError) {
  console.error('建立 location 失敗:', createLocationError);
  throw new Error(`建立位置資訊失敗: ${createLocationError.message}`);
}

userLocationId = newLocation.id;
```

### 驗證

1. 使用 Google OAuth 登入
2. 查看 `public.users` 表，應該會自動建立對應記錄
3. 刊登物品時，如果沒有位置會自動建立預設位置
4. 物品應該成功刊登

### 相關檔案

- `supabase/migrations/20251102111257_handle_new_user_signup.sql`
- `frontend-demo/src/views/CreateListingPage.vue:556-574`

---

## 13. 分類顯示錯誤 - 硬編碼與資料庫不一致

### 問題描述

AI 分析成功並正確選擇了分類，但前端顯示的分類名稱錯誤。例如：
- 上傳 iPhone 或筆記型電腦圖片
- AI 正確選擇了「3C 電子」分類（id=3）
- 但前端下拉選單顯示為「美妝保養」

### 根本原因

前端硬編碼的分類選項與資料庫不一致：

**前端硬編碼**（CreateListingPage.vue 原始版本）：
```html
<option value="1">流行服飾</option>
<option value="2">鞋包配件</option>
<option value="3">美妝保養</option>  <!-- ❌ 資料庫沒有這個分類 -->
<option value="4">電子 3C</option>
<option value="5">家電用品</option>
<option value="6">家具家飾</option>  <!-- ❌ 資料庫沒有這個分類 -->
<option value="7">親子婦幼</option>
<option value="8">生活娛樂</option>
<option value="9">圖書影音</option>  <!-- ❌ 資料庫沒有這個分類 -->
```

**資料庫實際分類**（`main_categories` 表）：
```sql
id=1: 流行服飾
id=2: 鞋包配件
id=3: 3C 電子      -- ✅ 正確名稱
id=4: 家電用品
id=5: 親子婦幼
id=6: 生活娛樂
```

當 AI 選擇 `sub_category_id=33`（筆記型電腦，屬於 `main_category_id=3`），前端將 `value="3"` 顯示為「美妝保養」而非「3C 電子」。

### 解決方案

#### 步驟 1: 修改前端為動態載入分類

修改 `frontend-demo/src/views/CreateListingPage.vue`：

```javascript
// 1. 添加 import
import { ref, onMounted } from 'vue';

// 2. 新增分類相關狀態
const categories = ref([]);
const isLoadingCategories = ref(false);

// 3. 新增載入分類函數
const loadCategories = async () => {
  isLoadingCategories.value = true;
  try {
    const { data, error } = await supabase
      .from('main_categories')
      .select('id, name')
      .order('id');

    if (error) throw error;
    categories.value = data || [];
    console.log('分類載入成功:', categories.value);
  } catch (error) {
    console.error('載入分類失敗:', error);
    alert('載入分類失敗，請重新整理頁面');
  } finally {
    isLoadingCategories.value = false;
  }
};

// 4. 頁面載入時執行
onMounted(() => {
  loadCategories();
});
```

#### 步驟 2: 更新 HTML 模板

將硬編碼的分類選項改為動態生成：

```vue
<select
  id="category"
  v-model="formData.category"
  class="form-select"
  required
  :disabled="isLoadingCategories"
>
  <option value="">{{ isLoadingCategories ? '載入中...' : '請選擇分類' }}</option>
  <option
    v-for="cat in categories"
    :key="cat.id"
    :value="String(cat.id)"
  >
    {{ cat.name }}
  </option>
</select>
```

### 驗證

#### 1. 查詢資料庫確認分類

```bash
docker exec supabase_db_backend psql -U postgres -d postgres -c "SELECT id, name FROM main_categories ORDER BY id;"
```

預期輸出：
```
 id |   name
----+----------
  1 | 流行服飾
  2 | 鞋包配件
  3 | 3C 電子
  4 | 家電用品
  5 | 親子婦幼
  6 | 生活娛樂
(6 rows)
```

#### 2. 測試前端分類顯示

1. 重新整理刊登頁面
2. 檢查分類下拉選單是否顯示正確的 6 個分類
3. 上傳物品圖片（例如 iPhone、筆記型電腦）
4. 點擊「AI 自動填寫」
5. 確認分類下拉選單自動選擇「3C 電子」

#### 3. 檢查 Edge Function 日誌

```bash
docker logs supabase_edge_runtime_backend --follow
```

查看 AI 回傳的分類是否正確：
```json
{
  "sub_category_id": 33,  // 33 = 筆記型電腦
  "title": "Apple MacBook Pro 14吋",
  ...
}
```

查詢子分類對應的主分類：
```bash
docker exec supabase_db_backend psql -U postgres -d postgres -c \
"SELECT sc.id, sc.name as sub_name, sc.main_category_id, mc.name as main_name
FROM sub_categories sc
JOIN main_categories mc ON sc.main_category_id = mc.id
WHERE sc.id = 33;"
```

預期輸出：
```
 id |   sub_name   | main_category_id | main_name
----+--------------+------------------+-----------
 33 | 筆記型電腦   |                3 | 3C 電子
```

### 相關檔案

- `frontend-demo/src/views/CreateListingPage.vue:288-372` (分類載入邏輯)
- `frontend-demo/src/views/CreateListingPage.vue:120-127` (HTML 模板)
- `frontend-demo/src/views/CreateListingPage.vue:455-472` (AI 分類映射邏輯)

### 補充說明

**為什麼需要動態載入？**

1. **資料一致性**：確保前端顯示與資料庫一致
2. **易於維護**：新增分類時不需修改前端程式碼
3. **避免錯誤**：消除硬編碼造成的 ID 與名稱不匹配問題

**AI 分類映射流程**：

```
AI 分析圖片
    ↓
選擇 sub_category_id (例如: 33 = 筆記型電腦)
    ↓
前端查詢 sub_categories 表
    ↓
取得 main_category_id (例如: 3)
    ↓
設定下拉選單為 "3C 電子"
    ↓
發布時使用精確的 sub_category_id (33)
```

---

## 聯絡資訊

如有其他問題，請：
1. 查看本文檔
2. 參考專案內其他 `.md` 文檔
3. 查看 Supabase 官方文檔
4. 提交 GitHub Issues

---

**最後更新**: 2025-11-19
**維護者**: FCU-Sigmaboy Team
**版本**: 1.3.0

## 更新日誌

### v1.3.0 (2025-11-19)
- ✨ 新增：Edge Runtime 503 錯誤診斷與修復方案
- 📝 新增：標準 Supabase 環境修復流程
- 🔧 新增：一鍵修復腳本（Linux/macOS 和 Windows）
- 💡 新增：使用 `npx supabase@beta start` 解決 Storage 遷移問題
- 📚 優化：文檔結構，分類 Supabase 環境問題和 AI 功能問題

### v1.2.0 (2025-11-02)
- AI 分類自動選擇功能
- 位置建立外鍵約束問題修復
- 分類顯示錯誤修復（動態載入分類）

### v1.1.0 (2025-11-02)
- Google OAuth 設定
- Edge Function 環境變數配置
- Docker 網路連線問題
- Gemini API 整合

### v1.0.0 (2025-11-02)
- 初版發布
- 基本 AI 圖片分析功能疑難排解
