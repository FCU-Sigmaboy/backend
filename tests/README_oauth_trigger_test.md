# OAuth Trigger 測試指南

本目錄包含 OAuth 用戶註冊觸發器的測試腳本。

## 測試檔案

- `test_oauth_trigger.sql` - SQL 測試腳本，用於驗證觸發器和地址解析函數

## 如何執行測試

### 方法 1: 使用 Supabase CLI (推薦)

```bash
# 1. 啟動本地 Supabase
cd /home/runner/work/backend/backend
npx supabase start

# 2. 執行資料庫遷移
npx supabase db reset

# 3. 執行測試腳本
npx supabase db shell < tests/test_oauth_trigger.sql
```

### 方法 2: 使用 psql

```bash
# 連接到本地資料庫
psql postgresql://postgres:postgres@localhost:54322/postgres

# 執行測試腳本
\i tests/test_oauth_trigger.sql
```

### 方法 3: 在 Supabase Studio

1. 打開 Supabase Studio (http://localhost:54323)
2. 進入 SQL Editor
3. 複製 `test_oauth_trigger.sql` 的內容
4. 點擊 RUN 執行

## 測試內容

測試腳本包含以下測試案例：

### 1. 觸發器和函數存在性檢查
- 驗證 `on_auth_user_created` 觸發器是否存在
- 驗證 `handle_new_user()` 函數是否存在
- 驗證 `extract_district_from_address()` 函數是否存在
- 驗證 `get_user_district()` 函數是否存在

### 2. 地址解析函數測試
測試不同的台灣地址格式：
- 台中市北屯區文心路四段123號 → 台中市北屯區
- 台北市信義區市府路1號 → 台北市信義區
- 新北市板橋區縣民大道2段7號 → 新北市板橋區
- 高雄市鳳山區光復路二段132號 → 高雄市鳳山區
- 台南市東區大學路1號 → 台南市東區
- 空字串和 NULL 值處理

### 3. 資料完整性檢查
- 驗證 `auth.users` 和 `public.users` 的對應關係
- 驗證 `public.users` 和 `public.profiles` 的對應關係
- 檢查是否有重複的 nickname

### 4. get_user_district 函數測試
- 測試從用戶主要地點提取行政區資訊

### 5. 新用戶註冊模擬（註解掉）
- 此部分需要在具有 auth schema 寫入權限的環境中執行
- 實際測試應該使用 OAuth 流程進行

## 整合測試（前端）

完整的 OAuth 流程測試需要在前端應用中進行：

### 步驟 1: 設定 OAuth 提供商

在 Supabase Dashboard 中設定 OAuth 提供商：

1. 前往 Authentication > Providers
2. 啟用 Google/GitHub/Facebook 等提供商
3. 設定 Client ID 和 Client Secret
4. 設定回調 URL

### 步驟 2: 前端測試

```javascript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

// 測試 Google OAuth 登入
async function testGoogleOAuth() {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: {
      redirectTo: 'http://localhost:3000/auth/callback'
    }
  })
  
  if (error) {
    console.error('OAuth 登入失敗:', error)
    return
  }
  
  console.log('OAuth 登入成功，等待回調...')
}

// 在回調頁面驗證用戶資料
async function verifyUserData() {
  const { data: { session } } = await supabase.auth.getSession()
  
  if (!session) {
    console.error('未找到 session')
    return
  }
  
  console.log('用戶 ID:', session.user.id)
  
  // 檢查 public.users 記錄
  const { data: userData, error: userError } = await supabase
    .from('users')
    .select('*')
    .eq('id', session.user.id)
    .single()
  
  console.log('public.users 記錄:', userData)
  
  // 檢查 public.profiles 記錄
  const { data: profileData, error: profileError } = await supabase
    .from('profiles')
    .select('*')
    .eq('user_id', session.user.id)
    .single()
  
  console.log('public.profiles 記錄:', profileData)
  
  // 驗證初始值
  if (profileData.balance === 0 && profileData.carbon_saved_kg === 0) {
    console.log('✓ 初始值正確')
  } else {
    console.error('✗ 初始值不正確')
  }
}
```

### 步驟 3: 測試位置儲存

```javascript
// 測試儲存用戶位置
async function testLocationSave() {
  // 取得測試位置（台中市北屯區）
  const testLocation = {
    latitude: 24.1817,
    longitude: 120.7344,
    formatted_address: '台中市北屯區文心路四段123號'
  }
  
  const { data: session } = await supabase.auth.getSession()
  const token = session?.session?.access_token
  
  // 呼叫 save-location Edge Function
  const response = await fetch(
    `${SUPABASE_URL}/functions/v1/save-location`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        latitude: testLocation.latitude,
        longitude: testLocation.longitude,
        type: '其他',
        is_primary: true,
        formatted_address: testLocation.formatted_address
      })
    }
  )
  
  const result = await response.json()
  console.log('位置儲存結果:', result)
  
  // 驗證行政區解析
  const { data: districtData } = await supabase
    .rpc('get_user_district', { p_user_id: session.user.id })
  
  console.log('解析的行政區:', districtData)
  
  if (districtData === '台中市北屯區') {
    console.log('✓ 行政區解析正確')
  } else {
    console.error('✗ 行政區解析不正確')
  }
}
```

## 預期結果

### 成功的測試結果應該顯示：

1. ✓ 所有觸發器和函數都存在
2. ✓ 地址解析函數正確提取所有測試地址的行政區
3. ✓ 所有 auth.users 都有對應的 public.users 記錄
4. ✓ 所有 public.users 都有對應的 public.profiles 記錄
5. ✓ 沒有重複的 nickname
6. ✓ get_user_district 函數正確返回行政區

### OAuth 整合測試成功的結果：

1. ✓ 用戶透過 OAuth 成功登入
2. ✓ 自動在 public.users 建立記錄，nickname 從 OAuth metadata 提取
3. ✓ 自動在 public.profiles 建立記錄，初始值正確（balance=0, carbon_saved_kg=0）
4. ✓ 用戶地理位置成功儲存到 locations 表
5. ✓ formatted_address 中的行政區資訊正確解析

## 常見問題

### Q1: 測試腳本執行失敗

**可能原因**：
- 遷移檔案尚未執行
- 資料庫連接失敗
- 權限不足

**解決方法**：
```bash
# 重置資料庫並重新執行遷移
npx supabase db reset

# 或手動執行遷移
npx supabase db push
```

### Q2: 地址解析測試失敗

**可能原因**：
- 正則表達式不匹配特定地址格式
- 資料庫編碼問題

**解決方法**：
- 檢查地址格式是否符合台灣地址標準
- 確保資料庫使用 UTF-8 編碼
- 如需支援其他地址格式，修改 `extract_district_from_address` 函數

### Q3: OAuth 整合測試失敗

**可能原因**：
- OAuth 提供商未正確設定
- 回調 URL 不正確
- 觸發器未正確執行

**解決方法**：
1. 檢查 Supabase Dashboard 中的 Auth 設定
2. 驗證 OAuth 提供商的 Client ID 和 Secret
3. 檢查瀏覽器 Console 是否有錯誤訊息
4. 查看 Supabase Dashboard 的 Logs

## 相關文檔

- [OAuth 觸發器實作文件](../docs/oauth-trigger-implementation.md)
- [Supabase Auth 文檔](https://supabase.com/docs/guides/auth)
- [Supabase 觸發器文檔](https://supabase.com/docs/guides/database/postgres/triggers)
