# OAuth 用戶註冊觸發器實作文件

## 概述

本文件說明 Supabase OAuth 用戶註冊時的自動觸發器實作，該觸發器會在用戶透過 OAuth 提供商（Google、GitHub、Facebook 等）註冊或登入時，自動在資料庫中建立相關的用戶記錄。

## 功能說明

### 1. 自動建立用戶資料

當用戶透過 Supabase OAuth 註冊時，觸發器會：

1. **在 `public.users` 表中建立基本資料**
   - 從 OAuth 提供商的 metadata 中提取暱稱（nickname）
   - 提取頭像 URL（profile_picture_url）
   - 確保暱稱的唯一性（如有重複會自動添加數字後綴）

2. **在 `public.profiles` 表中建立詳細資料**
   - 初始化點數餘額為 0
   - 初始化減碳量為 0.00 kg
   - 建立時間戳記

### 2. 地址解析功能

提供輔助函數從完整地址中提取台灣行政區資訊（例如："台中市北屯區"）。

## 技術實作

### 資料庫觸發器

#### 觸發器函數：`handle_new_user()`

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  base_nickname TEXT;
  final_nickname TEXT;
  counter INTEGER := 0;
BEGIN
  -- 提取基礎暱稱（優先順序）
  -- 1. nickname
  -- 2. name
  -- 3. full_name
  -- 4. user_name
  -- 5. email 前綴
  -- 6. 'user_' + UUID 前 8 碼
  
  -- 確保暱稱唯一性
  -- 如果有重複，自動添加 _1, _2, _3... 等後綴
  
  -- 建立 public.users 記錄
  -- 建立 public.profiles 記錄
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

#### 觸發器設定

```sql
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
```

### 地址解析函數

#### 函數：`extract_district_from_address()`

從完整地址中提取行政區名稱：

```sql
CREATE OR REPLACE FUNCTION public.extract_district_from_address(address TEXT)
RETURNS TEXT AS $$
-- 使用正則表達式提取縣市和區/鄉/鎮/市
-- 輸入："台中市北屯區文心路四段123號"
-- 輸出："台中市北屯區"
```

#### RPC 函數：`get_user_district()`

取得用戶主要地點的行政區：

```sql
SELECT public.get_user_district('user-uuid-here');
-- 返回：'台中市北屯區'
```

## OAuth 提供商 Metadata 對應

不同 OAuth 提供商會提供不同的用戶資料格式：

### Google OAuth
```json
{
  "name": "使用者全名",
  "picture": "https://lh3.googleusercontent.com/...",
  "email": "user@gmail.com"
}
```

### GitHub OAuth
```json
{
  "user_name": "github_username",
  "avatar_url": "https://avatars.githubusercontent.com/...",
  "name": "使用者全名"
}
```

### Facebook OAuth
```json
{
  "full_name": "使用者全名",
  "picture": "https://graph.facebook.com/...",
  "email": "user@example.com"
}
```

## 使用範例

### 1. 前端：使用 Supabase OAuth 登入

```javascript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

// Google OAuth 登入
async function signInWithGoogle() {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: {
      redirectTo: 'http://localhost:3000/callback'
    }
  })
}

// GitHub OAuth 登入
async function signInWithGithub() {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'github',
    options: {
      redirectTo: 'http://localhost:3000/callback'
    }
  })
}
```

### 2. 前端：儲存用戶地理位置

登入後，在前端取得用戶的地理位置並儲存：

```javascript
// 取得瀏覽器地理位置
async function saveUserLocation() {
  if (!navigator.geolocation) {
    console.error('瀏覽器不支援地理定位')
    return
  }

  navigator.geolocation.getCurrentPosition(
    async (position) => {
      const { latitude, longitude } = position.coords
      
      // 使用 Google Geocoding API 或其他服務取得格式化地址
      const address = await getAddressFromCoordinates(latitude, longitude)
      
      // 儲存到資料庫
      const { data: session } = await supabase.auth.getSession()
      const token = session?.session?.access_token
      
      const response = await fetch(
        `${SUPABASE_URL}/functions/v1/save-location`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            latitude,
            longitude,
            type: '其他',
            is_primary: true,
            formatted_address: address
          })
        }
      )
      
      const result = await response.json()
      console.log('位置已儲存:', result)
    },
    (error) => {
      console.error('無法取得位置:', error)
    }
  )
}

// 使用 Google Geocoding API 取得地址
async function getAddressFromCoordinates(lat, lng) {
  const response = await fetch(
    `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${GOOGLE_MAPS_API_KEY}&language=zh-TW`
  )
  const data = await response.json()
  
  if (data.results && data.results.length > 0) {
    return data.results[0].formatted_address
  }
  
  return null
}
```

### 3. 後端：取得用戶行政區

```sql
-- 取得用戶的行政區
SELECT public.get_user_district('488a4712-dd63-4938-9679-336f434ad263');
-- 結果：'台中市北屯區'

-- 在查詢中使用
SELECT 
  u.id,
  u.nickname,
  public.get_user_district(u.id) as district
FROM public.users u
WHERE u.id = '488a4712-dd63-4938-9679-336f434ad263';
```

### 4. 驗證觸發器是否正常運作

```sql
-- 查詢 auth.users 和 public.users 的對應關係
SELECT 
  au.id,
  au.email,
  au.raw_user_meta_data->>'name' as oauth_name,
  pu.nickname,
  pu.profile_picture_url,
  pp.balance,
  pp.carbon_saved_kg
FROM auth.users au
LEFT JOIN public.users pu ON au.id = pu.id
LEFT JOIN public.profiles pp ON au.id = pp.user_id
ORDER BY au.created_at DESC
LIMIT 10;
```

## 前端完整整合範例

```javascript
// 在 Vue.js 或 React 中使用
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

// 1. OAuth 登入
async function handleOAuthLogin(provider) {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: provider, // 'google', 'github', 'facebook', etc.
    options: {
      redirectTo: `${window.location.origin}/auth/callback`
    }
  })
  
  if (error) {
    console.error('登入失敗:', error)
    return
  }
}

// 2. 在 callback 頁面處理登入後的流程
async function handleAuthCallback() {
  // 取得 session
  const { data: { session } } = await supabase.auth.getSession()
  
  if (!session) {
    console.error('未找到 session')
    return
  }
  
  // 檢查是否為新用戶（首次登入）
  const { data: profile } = await supabase
    .from('profiles')
    .select('user_id')
    .eq('user_id', session.user.id)
    .single()
  
  // 如果是新用戶，提示儲存位置
  if (profile && !profile.has_location) {
    promptLocationSave()
  }
}

// 3. 提示用戶儲存位置
function promptLocationSave() {
  if (confirm('是否允許存取您的位置資訊？這將幫助我們提供更好的服務。')) {
    saveUserLocation()
  }
}

// 4. 儲存位置（包含地址解析）
async function saveUserLocation() {
  if (!navigator.geolocation) {
    alert('您的瀏覽器不支援地理定位功能')
    return
  }

  navigator.geolocation.getCurrentPosition(
    async (position) => {
      const { latitude, longitude } = position.coords
      
      try {
        // 使用 Google Geocoding API 取得格式化地址
        const geocodeUrl = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${latitude},${longitude}&key=${GOOGLE_MAPS_API_KEY}&language=zh-TW`
        const geocodeResponse = await fetch(geocodeUrl)
        const geocodeData = await geocodeResponse.json()
        
        let formattedAddress = null
        if (geocodeData.results && geocodeData.results.length > 0) {
          formattedAddress = geocodeData.results[0].formatted_address
        }
        
        // 儲存到資料庫
        const { data: session } = await supabase.auth.getSession()
        const token = session?.session?.access_token
        
        const response = await fetch(
          `${SUPABASE_URL}/functions/v1/save-location`,
          {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${token}`,
              'Content-Type': 'application/json'
            },
            body: JSON.stringify({
              latitude,
              longitude,
              type: '其他',
              is_primary: true,
              formatted_address: formattedAddress
            })
          }
        )
        
        const result = await response.json()
        
        if (result.success) {
          console.log('位置已成功儲存:', result)
          alert('位置已儲存！')
        } else {
          console.error('儲存位置失敗:', result.error)
          alert('儲存位置失敗，請稍後再試')
        }
      } catch (error) {
        console.error('處理位置時發生錯誤:', error)
        alert('處理位置時發生錯誤')
      }
    },
    (error) => {
      console.error('無法取得位置:', error)
      alert('無法取得您的位置，請檢查瀏覽器權限設定')
    },
    {
      enableHighAccuracy: true,
      timeout: 10000,
      maximumAge: 0
    }
  )
}
```

## 測試指南

### 1. 測試觸發器

```sql
-- 模擬新用戶註冊（僅供測試，實際環境由 Supabase Auth 自動觸發）
-- 注意：不要在正式環境直接插入 auth.users

-- 測試：檢查是否自動建立了 public.users 和 public.profiles
SELECT 
  au.id,
  au.email,
  pu.nickname,
  pp.balance,
  pp.carbon_saved_kg
FROM auth.users au
LEFT JOIN public.users pu ON au.id = pu.id
LEFT JOIN public.profiles pp ON au.id = pp.user_id
WHERE au.email = 'test@example.com';
```

### 2. 測試地址解析

```sql
-- 測試地址解析函數
SELECT public.extract_district_from_address('台中市北屯區文心路四段123號');
-- 預期結果：'台中市北屯區'

SELECT public.extract_district_from_address('台北市信義區市府路1號');
-- 預期結果：'台北市信義區'

SELECT public.extract_district_from_address('新北市板橋區縣民大道2段7號');
-- 預期結果：'新北市板橋區'

SELECT public.extract_district_from_address('高雄市鳳山區光復路二段132號');
-- 預期結果：'高雄市鳳山區'
```

### 3. 測試完整流程

1. **啟動本地 Supabase**
   ```bash
   npx supabase start
   ```

2. **執行遷移**
   ```bash
   npx supabase db reset
   ```

3. **在前端應用中測試 OAuth 登入**
   - 使用 Google/GitHub/Facebook 等 OAuth 提供商登入
   - 登入後檢查資料庫是否自動建立用戶記錄

4. **測試位置儲存**
   - 登入後提示儲存位置
   - 允許瀏覽器存取位置
   - 檢查 `locations` 表是否成功儲存位置和地址

5. **驗證行政區解析**
   ```sql
   SELECT 
     l.id,
     l.formatted_address,
     public.extract_district_from_address(l.formatted_address) as district
   FROM public.locations l
   WHERE user_id = 'your-user-id';
   ```

## 安全性考量

### 1. 觸發器安全性

- 使用 `SECURITY DEFINER` 確保觸發器以定義者的權限執行
- 觸發器自動在 `auth.users` 插入後執行，無法被一般用戶直接觸發
- RLS (Row Level Security) 仍然適用於 `public.users` 和 `public.profiles`

### 2. 資料驗證

- 暱稱唯一性由觸發器自動處理
- 如果 OAuth metadata 為空，使用 email 前綴或 UUID 作為後備方案
- 地址解析失敗時返回 NULL，不會影響位置儲存

### 3. 權限控制

- 用戶只能查看和修改自己的資料（由 RLS 策略控制）
- 地理位置資料由 Edge Function 驗證後儲存
- Service Role Key 僅在後端使用，前端使用 Anon Key

## 故障排除

### 問題 1：觸發器未執行

**症狀**：OAuth 登入後，`public.users` 或 `public.profiles` 沒有建立記錄

**解決方法**：
```sql
-- 檢查觸發器是否存在
SELECT * FROM pg_trigger WHERE tgname = 'on_auth_user_created';

-- 檢查觸發器函數是否存在
SELECT * FROM pg_proc WHERE proname = 'handle_new_user';

-- 重新建立觸發器
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
```

### 問題 2：暱稱重複錯誤

**症狀**：收到 unique constraint violation 錯誤

**解決方法**：
- 確保使用最新版本的遷移檔案（包含暱稱唯一性處理邏輯）
- 手動修復重複的暱稱：
```sql
-- 查找重複的暱稱
SELECT nickname, COUNT(*) 
FROM public.users 
GROUP BY nickname 
HAVING COUNT(*) > 1;

-- 手動更新重複的暱稱
UPDATE public.users 
SET nickname = nickname || '_' || SUBSTRING(id::TEXT, 1, 4)
WHERE id IN (
  SELECT id FROM public.users 
  WHERE nickname = 'duplicate_nickname' 
  ORDER BY created_at DESC 
  OFFSET 1
);
```

### 問題 3：地址解析返回 NULL

**症狀**：`extract_district_from_address()` 返回 NULL

**原因**：
- 地址格式不符合台灣地址標準
- 地址中缺少縣市或區域資訊

**解決方法**：
- 確保 Google Geocoding API 使用 `language=zh-TW` 參數
- 檢查 formatted_address 是否包含完整的行政區資訊
- 對於非台灣地址，可以考慮儲存原始地址並標記為「其他地區」

## 維護與更新

### 遷移檔案位置

```
supabase/migrations/20251104094940_create_auth_user_trigger.sql
```

### 回滾方法

如需回滾此功能：

```sql
-- 移除觸發器
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS parse_location_district_trigger ON public.locations;

-- 移除函數
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.parse_location_district();
DROP FUNCTION IF EXISTS public.extract_district_from_address(TEXT);
DROP FUNCTION IF EXISTS public.get_user_district(UUID);
```

## 相關資源

- [Supabase 觸發器文檔](https://supabase.com/docs/guides/database/postgres/triggers)
- [Supabase OAuth 文檔](https://supabase.com/docs/guides/auth/social-login)
- [PostGIS 文檔](https://postgis.net/documentation/)
- [Google Geocoding API](https://developers.google.com/maps/documentation/geocoding)

## 更新日誌

- **2025-11-04**: 初始版本
  - 實作 OAuth 用戶註冊觸發器
  - 實作地址解析功能
  - 新增完整文檔和測試指南
