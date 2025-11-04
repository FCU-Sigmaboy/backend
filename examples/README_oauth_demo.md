# OAuth Trigger Demo

本目錄包含 OAuth 用戶註冊觸發器的實際應用示範。

## 檔案說明

- `oauth-trigger-demo.html` - 完整的前端示範頁面，展示 OAuth 登入和地理定位功能

## 功能展示

這個示範頁面展示了完整的用戶註冊和位置儲存流程：

### 1. OAuth 登入
- 支援 Google OAuth 登入
- 支援 GitHub OAuth 登入
- 自動觸發資料庫觸發器建立用戶記錄

### 2. 用戶資訊顯示
- 顯示從 `public.users` 表取得的基本資料（由觸發器自動建立）
- 顯示從 `public.profiles` 表取得的詳細資料（由觸發器自動建立）
- 包含暱稱、頭像、點數餘額、減碳量等資訊

### 3. 地理定位功能
- 使用瀏覽器 Geolocation API 取得當前位置
- 呼叫 `save-location` Edge Function 儲存位置到資料庫
- 支援查看已儲存的位置資訊

### 4. 行政區解析
- 使用 `get_user_district` RPC 函數取得用戶的行政區
- 自動從 `formatted_address` 中提取台灣行政區資訊

## 使用方法

### 1. 設定 OAuth 提供商

在使用示範頁面前，需要先在 Supabase Dashboard 設定 OAuth 提供商：

#### Google OAuth 設定

1. 前往 [Google Cloud Console](https://console.cloud.google.com/)
2. 建立或選擇專案
3. 啟用 Google+ API
4. 建立 OAuth 2.0 憑證
5. 設定授權的重定向 URI：
   - 本地測試：`http://localhost:8000`
   - Supabase：`https://your-project.supabase.co/auth/v1/callback`
6. 複製 Client ID 和 Client Secret
7. 在 Supabase Dashboard > Authentication > Providers > Google
   - 啟用 Google provider
   - 填入 Client ID 和 Client Secret

#### GitHub OAuth 設定

1. 前往 [GitHub Developer Settings](https://github.com/settings/developers)
2. 點擊 "New OAuth App"
3. 填寫應用資訊：
   - Application name: Your App Name
   - Homepage URL: `http://localhost:8000`
   - Authorization callback URL: `https://your-project.supabase.co/auth/v1/callback`
4. 建立應用後複製 Client ID
5. 產生 Client Secret
6. 在 Supabase Dashboard > Authentication > Providers > GitHub
   - 啟用 GitHub provider
   - 填入 Client ID 和 Client Secret

### 2. 部署 Edge Function

確保已部署 `save-location` Edge Function：

```bash
# 部署到本地（用於測試）
npx supabase functions serve save-location

# 或部署到遠端
npx supabase functions deploy save-location --project-ref your-project-ref
```

### 3. 啟動示範頁面

#### 方法 A: 使用 Python HTTP Server

```bash
# 在專案根目錄執行
cd examples
python3 -m http.server 8000
```

然後打開瀏覽器訪問 `http://localhost:8000/oauth-trigger-demo.html`

#### 方法 B: 使用 Node.js HTTP Server

```bash
# 安裝 http-server（如果尚未安裝）
npm install -g http-server

# 在專案根目錄執行
cd examples
http-server -p 8000
```

然後打開瀏覽器訪問 `http://localhost:8000/oauth-trigger-demo.html`

#### 方法 C: 直接在瀏覽器開啟

對於現代瀏覽器，也可以直接開啟 HTML 檔案，但 OAuth 回調可能無法正常運作。建議使用上述方法。

### 4. 使用示範頁面

1. **輸入 Supabase 資訊**
   - Supabase URL: `https://your-project.supabase.co`
   - Supabase Anon Key: 從 Dashboard > Settings > API 取得
   - 點擊「初始化 Supabase」

2. **OAuth 登入**
   - 點擊「使用 Google 登入」或「使用 GitHub 登入」
   - 完成 OAuth 流程
   - 回到頁面後會自動顯示用戶資訊

3. **查看用戶資訊**
   - 自動顯示由觸發器建立的用戶記錄
   - 包含 `public.users` 和 `public.profiles` 的資料

4. **儲存位置**
   - 點擊「取得並儲存我的位置」
   - 允許瀏覽器存取位置權限
   - 位置會儲存到 `public.locations` 表

5. **查看行政區**
   - 點擊「取得我的行政區」
   - 顯示從地址解析的行政區資訊

## 預期行為

### 成功的流程：

1. ✅ OAuth 登入成功
2. ✅ 自動在 `public.users` 建立記錄（由觸發器執行）
3. ✅ 自動在 `public.profiles` 建立記錄（由觸發器執行）
4. ✅ 暱稱從 OAuth metadata 提取（如有重複會自動添加數字後綴）
5. ✅ 初始點數餘額為 0，初始減碳量為 0.00 kg
6. ✅ 位置成功儲存到 `public.locations`
7. ✅ 行政區資訊正確解析（如果地址格式正確）

### 錯誤處理：

- ❌ 未初始化 Supabase：顯示錯誤訊息
- ❌ OAuth 登入失敗：顯示具體錯誤原因
- ❌ 位置權限被拒絕：顯示友善提示
- ❌ 網路錯誤：顯示連線失敗訊息

## 驗證資料

登入成功後，可以在 Supabase Dashboard 的 SQL Editor 中執行以下查詢來驗證資料：

```sql
-- 查看所有用戶及其資料
SELECT 
  u.id,
  u.nickname,
  u.profile_picture_url,
  p.balance,
  p.carbon_saved_kg,
  l.formatted_address,
  public.get_user_district(u.id) as district
FROM public.users u
LEFT JOIN public.profiles p ON u.id = p.user_id
LEFT JOIN public.locations l ON u.id = l.user_id AND l.is_primary = true
ORDER BY u.created_at DESC;
```

## 常見問題

### Q1: OAuth 登入後頁面沒有反應

**可能原因**：
- OAuth 回調 URL 設定不正確
- 瀏覽器阻擋了 redirect
- Supabase URL 或 Key 輸入錯誤

**解決方法**：
1. 檢查 OAuth 提供商的回調 URL 設定
2. 確認使用 HTTP Server 啟動頁面（不要直接開啟 file:// 協議）
3. 檢查瀏覽器 Console 是否有錯誤訊息
4. 重新輸入正確的 Supabase URL 和 Anon Key

### Q2: 觸發器沒有建立用戶記錄

**可能原因**：
- 資料庫遷移尚未執行
- 觸發器被禁用或刪除
- 權限設定問題

**解決方法**：
```bash
# 重置資料庫並重新執行遷移
npx supabase db reset

# 或手動執行遷移
npx supabase db push
```

### Q3: 無法儲存位置

**可能原因**：
- Edge Function 未部署
- 授權 token 無效
- RLS 策略阻擋

**解決方法**：
1. 確認 `save-location` Edge Function 已部署
2. 檢查 Supabase Dashboard 的 Edge Functions Logs
3. 驗證 RLS 策略是否正確設定

### Q4: 行政區顯示 NULL

**可能原因**：
- 用戶尚未儲存位置
- formatted_address 格式不符合台灣地址標準
- 地址中缺少行政區資訊

**解決方法**：
1. 先儲存位置
2. 確保 formatted_address 包含完整的台灣地址
3. 使用 Google Geocoding API 取得正確格式的地址

## 整合到您的應用

這個示範頁面使用純 JavaScript，可以輕鬆整合到任何前端框架：

### Vue.js 整合

```vue
<template>
  <div>
    <button @click="signInWithGoogle">使用 Google 登入</button>
    <div v-if="user">
      <p>歡迎，{{ userProfile.nickname }}</p>
      <button @click="saveLocation">儲存我的位置</button>
    </div>
  </div>
</template>

<script>
import { createClient } from '@supabase/supabase-js'

export default {
  data() {
    return {
      supabase: null,
      user: null,
      userProfile: null
    }
  },
  mounted() {
    this.supabase = createClient(SUPABASE_URL, SUPABASE_KEY)
    this.checkSession()
  },
  methods: {
    async signInWithGoogle() {
      await this.supabase.auth.signInWithOAuth({ provider: 'google' })
    },
    async checkSession() {
      const { data: { session } } = await this.supabase.auth.getSession()
      if (session) {
        this.user = session.user
        await this.fetchUserProfile()
      }
    },
    async fetchUserProfile() {
      const { data } = await this.supabase
        .from('users')
        .select('*')
        .eq('id', this.user.id)
        .single()
      this.userProfile = data
    },
    async saveLocation() {
      // 實作位置儲存邏輯
    }
  }
}
</script>
```

### React 整合

```jsx
import { createClient } from '@supabase/supabase-js'
import { useState, useEffect } from 'react'

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY)

function App() {
  const [user, setUser] = useState(null)
  const [profile, setProfile] = useState(null)

  useEffect(() => {
    checkSession()
  }, [])

  async function checkSession() {
    const { data: { session } } = await supabase.auth.getSession()
    if (session) {
      setUser(session.user)
      fetchProfile(session.user.id)
    }
  }

  async function fetchProfile(userId) {
    const { data } = await supabase
      .from('users')
      .select('*')
      .eq('id', userId)
      .single()
    setProfile(data)
  }

  async function signInWithGoogle() {
    await supabase.auth.signInWithOAuth({ provider: 'google' })
  }

  return (
    <div>
      {!user ? (
        <button onClick={signInWithGoogle}>使用 Google 登入</button>
      ) : (
        <div>
          <p>歡迎，{profile?.nickname}</p>
        </div>
      )}
    </div>
  )
}
```

## 下一步

- 整合 Google Geocoding API 以取得更準確的地址資訊
- 添加地圖顯示功能（參考 `Map_Function` 目錄）
- 實作用戶資料編輯功能
- 添加更多 OAuth 提供商（Facebook、Discord 等）

## 相關文檔

- [OAuth 觸發器實作文件](../docs/oauth-trigger-implementation.md)
- [測試指南](../tests/README_oauth_trigger_test.md)
- [地圖功能範例](./Map_Function/README.md)
