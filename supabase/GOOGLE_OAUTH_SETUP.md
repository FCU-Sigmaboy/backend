# Google OAuth 本地開發設定指南

## 問題說明

當你在本地開發環境使用 Google 登入時，會出現以下錯誤：
```
{"code":400,"error_code":"validation_failed","msg":"Unsupported provider: provider is not enabled"}
```

這是因為本地 Supabase 需要單獨配置 Google OAuth 憑證。

## 解決方案

### 方案 A：從遠端 Supabase 複製憑證（推薦）

1. **登入遠端 Supabase Dashboard**
   - 前往：https://supabase.com/dashboard
   - 選擇你的專案：`rsubfpxltwkrdejnvzxw`

2. **獲取 Google OAuth 憑證**
   - 點選左側選單：**Authentication** → **Providers**
   - 找到 **Google** provider
   - 複製以下資訊：
     - **Client ID** (OAuth client ID)
     - **Client Secret** (OAuth client secret)

3. **更新本地環境變數**
   - 編輯檔案：`supabase/.env.local`
   - 填入你複製的憑證：
     ```bash
     GOOGLE_CLIENT_ID=你的-client-id
     GOOGLE_CLIENT_SECRET=你的-client-secret
     ```

4. **重啟 Supabase**
   ```bash
   npx supabase stop
   npx supabase start
   ```

5. **重啟前端**
   ```bash
   cd frontend-demo
   npm run dev
   ```

---

### 方案 B：建立新的 Google OAuth 憑證（進階）

如果你想要為本地開發建立獨立的 OAuth 憑證：

#### 1. 前往 Google Cloud Console

https://console.cloud.google.com/apis/credentials

#### 2. 建立 OAuth 2.0 用戶端 ID

1. 點選「建立憑證」→「OAuth 用戶端 ID」
2. 應用程式類型：選擇「網頁應用程式」
3. 名稱：`Supabase Local Development`
4. 已授權的 JavaScript 來源：
   ```
   http://localhost:54321
   http://127.0.0.1:54321
   http://localhost:5174
   http://127.0.0.1:5174
   ```
5. 已授權的重新導向 URI：
   ```
   http://localhost:54321/auth/v1/callback
   http://127.0.0.1:54321/auth/v1/callback
   ```

#### 3. 複製憑證

建立完成後，會顯示：
- **用戶端 ID** (Client ID)
- **用戶端密鑰** (Client Secret)

#### 4. 更新本地環境變數

編輯 `supabase/.env.local`：
```bash
GOOGLE_CLIENT_ID=你的新-client-id
GOOGLE_CLIENT_SECRET=你的新-client-secret
```

#### 5. 重啟服務

```bash
npx supabase stop
npx supabase start
```

---

## 驗證設定

### 1. 檢查 Supabase 配置

執行以下命令確認 Google provider 已啟用：
```bash
npx supabase status
```

### 2. 測試登入

1. 開啟前端：http://localhost:5174
2. 點選「使用 Google 登入」
3. 應該會看到 Google OAuth 同意畫面
4. 授權後應該成功登入

### 3. 檢查錯誤

如果還是有問題，檢查瀏覽器 Console：
```
F12 → Console
```

查看是否有相關錯誤訊息。

---

## 常見問題

### Q: 為什麼遠端可以用，本地不行？

A: 遠端 Supabase 和本地 Supabase 是獨立的環境，需要分別設定 OAuth 憑證。

### Q: 我可以用相同的 Google OAuth 憑證嗎？

A: 可以！你可以在同一個 Google OAuth 憑證中新增本地的 redirect URI，這樣遠端和本地都能使用。

### Q: skip_nonce_check = true 安全嗎？

A: 僅在本地開發環境建議啟用。生產環境不應該使用此設定。

### Q: 我需要在 Google Cloud Console 啟用什麼 API？

A: 確保以下 API 已啟用：
- Google+ API（或 Google People API）
- Google OAuth2 API

---

## 已完成的設定

✅ `supabase/config.toml` - 已啟用 Google OAuth
```toml
[auth.external.google]
enabled = true
client_id = "env(GOOGLE_CLIENT_ID)"
secret = "env(GOOGLE_CLIENT_SECRET)"
skip_nonce_check = true  # 本地開發必須
```

⚠️ `supabase/.env.local` - **需要你手動填入憑證**
```bash
GOOGLE_CLIENT_ID=your-google-client-id-here
GOOGLE_CLIENT_SECRET=your-google-client-secret-here
```

---

## 下一步

1. 按照上方的**方案 A** 或**方案 B** 獲取 Google OAuth 憑證
2. 填入 `supabase/.env.local`
3. 重啟 Supabase 和前端
4. 測試 Google 登入功能

---

**最後更新**: 2025-11-02
**維護者**: FCU-Sigmaboy Team
