# Edge Function 環境變數說明

## 必須設定的變數

### GOOGLE_MAPS_API_KEY
- **用途**: 呼叫 Google Maps Geocoding API 進行地址解析
- **如何取得**:
  1. 前往 [Google Cloud Console](https://console.cloud.google.com/)
  2. 建立專案或選擇現有專案
  3. 啟用 Geocoding API
  4. 建立 API Key
  5. （建議）設定 API Key 限制（IP 限制或 HTTP referrer 限制）

### 設定方式

#### 本地開發
1. 複製 `.env.example` 為 `.env`
   ```bash
   cp .env.example .env
   ```

2. 編輯 `.env` 檔案，填入真實的 API Key
   ```bash
   GOOGLE_MAPS_API_KEY=AIzaSy...
   ```

3. 啟動本地 Edge Function
   ```bash
   npx supabase functions serve save-location --env-file ./supabase/.env
   ```

#### 生產環境（Supabase Dashboard）
1. 前往 Supabase Dashboard
2. Settings → Edge Functions → Secrets
3. 新增 secret:
   - Name: `GOOGLE_MAPS_API_KEY`
   - Value: 你的 API Key

或使用 CLI:
```bash
npx supabase secrets set GOOGLE_MAPS_API_KEY=your_api_key_here
```

## 自動提供的變數

以下變數由 Supabase 自動提供，無需手動設定：

- `SUPABASE_URL`: Supabase 專案 URL
- `SUPABASE_ANON_KEY`: 匿名金鑰（公開金鑰）
- `SUPABASE_SERVICE_ROLE_KEY`: Service Role 金鑰（管理員金鑰）

## 安全性建議

1. **不要提交 `.env` 檔案到 Git**
   - 已在 `.gitignore` 中排除

2. **定期輪換 API Key**
   - Google Maps API Key 應定期更新

3. **設定 API Key 限制**
   - 限制可呼叫的 API
   - 限制請求來源

4. **監控 API 使用量**
   - 設定配額警告
   - 監控異常請求

## 測試環境變數

```bash
# 本地測試
npx supabase functions serve save-location --env-file ./supabase/.env

# 驗證環境變數
curl -i --location --request POST \
  'http://localhost:54321/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_ANON_KEY' \
  --header 'Content-Type: application/json' \
  --data '{
    "latitude": 24.1817,
    "longitude": 120.7344,
    "type": "其他",
    "is_primary": true
  }'
```
