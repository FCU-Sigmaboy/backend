# RLS 策略檢查清單

**專案**: FCU-Sigma  
**檢查日期**: 2025-11-05  
**目的**: 確保 Row Level Security (RLS) 策略與業務邏輯一致

## 檢查範圍

- [x] `public.users` 表
- [x] `public.profiles` 表
- [x] `public.locations` 表
- [ ] 其他相關表

---

## 1. public.users 表

### 1.1 應該有的策略

#### ✅ SELECT 策略
**目的**: 允許所有已登入用戶查看其他用戶的基本公開資訊

```sql
-- 策略名稱: users_select_policy
CREATE POLICY users_select_policy ON public.users
  FOR SELECT
  TO authenticated
  USING (true);  -- 所有已登入用戶都可以查看
```

**驗證查詢**:
```sql
SELECT * FROM public.users WHERE id = 'other-user-id';
-- 應該可以查詢到其他用戶的 nickname, profile_picture_url, avg_rating
```

**業務邏輯**:
- ✅ 符合社群平台需求：用戶需要看到其他用戶的基本資訊
- ✅ 隱私保護：只公開非敏感欄位（nickname, profile_picture_url, avg_rating）
- ⚠️ 注意：如果未來需要隱私模式，需要調整此策略

#### ✅ INSERT 策略
**目的**: 禁止一般用戶直接插入，只允許觸發器插入

```sql
-- 策略名稱: users_insert_policy
CREATE POLICY users_insert_policy ON public.users
  FOR INSERT
  TO authenticated
  WITH CHECK (false);  -- 禁止所有用戶直接插入
  
-- 或者：只允許插入自己的記錄（由觸發器使用）
CREATE POLICY users_insert_policy ON public.users
  FOR INSERT
  TO authenticated
  WITH CHECK (id = auth.uid());
```

**驗證查詢**:
```sql
-- 應該失敗（被 RLS 拒絕）
INSERT INTO public.users (id, nickname) 
VALUES (gen_random_uuid(), 'test');
```

**業務邏輯**:
- ✅ 安全性：防止用戶手動創建帳號
- ✅ 資料完整性：確保所有用戶都透過 OAuth 觸發器創建

#### ✅ UPDATE 策略
**目的**: 只允許用戶更新自己的記錄（透過 RPC）

```sql
-- 策略名稱: users_update_policy
CREATE POLICY users_update_policy ON public.users
  FOR UPDATE
  TO authenticated
  USING (id = auth.uid())  -- 只能更新自己的記錄
  WITH CHECK (
    id = auth.uid() AND
    -- 禁止更新 avg_rating（應由系統計算）
    avg_rating = (SELECT avg_rating FROM public.users WHERE id = auth.uid())
  );
```

**驗證查詢**:
```sql
-- 應該成功
UPDATE public.users 
SET nickname = 'new_nickname' 
WHERE id = auth.uid();

-- 應該失敗（嘗試更新其他人）
UPDATE public.users 
SET nickname = 'new_nickname' 
WHERE id = 'other-user-id';

-- 應該失敗（嘗試更改 avg_rating）
UPDATE public.users 
SET avg_rating = 5.0 
WHERE id = auth.uid();
```

**業務邏輯**:
- ✅ 隱私保護：用戶只能修改自己的資料
- ✅ 資料完整性：防止手動修改計算欄位（avg_rating）
- ⚠️ 建議：最好透過 RPC 更新，並在 RPC 中進行額外驗證

#### ✅ DELETE 策略
**目的**: 禁止刪除用戶記錄（應由管理員處理）

```sql
-- 策略名稱: users_delete_policy
CREATE POLICY users_delete_policy ON public.users
  FOR DELETE
  TO authenticated
  USING (false);  -- 禁止所有刪除操作
```

**業務邏輯**:
- ✅ 資料保護：防止意外刪除
- ✅ 審計需求：保留歷史記錄

---

## 2. public.profiles 表

### 2.1 應該有的策略

#### ✅ SELECT 策略
**目的**: 只允許用戶查看自己的 profile

```sql
-- 策略名稱: profiles_select_policy
CREATE POLICY profiles_select_policy ON public.profiles
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());  -- 只能查看自己的 profile
```

**驗證查詢**:
```sql
-- 應該成功
SELECT * FROM public.profiles WHERE user_id = auth.uid();

-- 應該失敗或返回空結果
SELECT * FROM public.profiles WHERE user_id = 'other-user-id';
```

**業務邏輯**:
- ✅ 隱私保護：balance 和 carbon_saved_kg 是敏感資訊
- ✅ 符合需求：用戶只需要看到自己的餘額和減碳量

#### ✅ INSERT 策略
**目的**: 禁止一般用戶直接插入，只允許觸發器插入

```sql
-- 策略名稱: profiles_insert_policy
CREATE POLICY profiles_insert_policy ON public.profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());  -- 只能插入自己的記錄（由觸發器使用）
```

**業務邏輯**:
- ✅ 安全性：防止用戶手動創建 profile
- ✅ 資料完整性：確保 profile 與 user 一對一關係

#### ❌ UPDATE 策略（重要）
**目的**: **禁止直接更新**，必須透過 RPC

```sql
-- 策略名稱: profiles_update_policy
-- 選項 1: 完全禁止直接更新
CREATE POLICY profiles_update_policy ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (false)  -- 禁止所有直接更新
  WITH CHECK (false);

-- 選項 2: 只允許更新 updated_at（由 RPC 使用）
CREATE POLICY profiles_update_policy ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid() AND
    -- 確保 balance 和 carbon_saved_kg 沒有被直接修改
    balance = (SELECT balance FROM public.profiles WHERE user_id = auth.uid()) AND
    carbon_saved_kg = (SELECT carbon_saved_kg FROM public.profiles WHERE user_id = auth.uid())
  );
```

**⚠️ 關鍵安全問題**:
- **當前 RPC 允許前端直接更新 balance** - 這是高風險操作
- 建議：採用**選項 1**（完全禁止），所有更新透過 RPC + 業務邏輯驗證

**驗證查詢**:
```sql
-- 應該失敗
UPDATE public.profiles 
SET balance = 999999 
WHERE user_id = auth.uid();
```

#### ✅ DELETE 策略
**目的**: 禁止刪除（CASCADE 由 users 表處理）

```sql
-- 策略名稱: profiles_delete_policy
CREATE POLICY profiles_delete_policy ON public.profiles
  FOR DELETE
  TO authenticated
  USING (false);
```

---

## 3. public.locations 表

### 3.1 應該有的策略

#### ✅ SELECT 策略
**目的**: 允許查看自己的地點 + 允許查看物品賣家的主要地點（用於計算距離）

```sql
-- 策略名稱: locations_select_own
CREATE POLICY locations_select_own ON public.locations
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());  -- 自己的所有地點

-- 策略名稱: locations_select_primary_for_items
CREATE POLICY locations_select_primary_for_items ON public.locations
  FOR SELECT
  TO authenticated
  USING (
    is_primary = true AND  -- 只能看到主要地點
    user_id IN (
      SELECT user_id FROM public.items WHERE listing_status = true
    )  -- 只能看到有上架物品的用戶的主要地點
  );
```

**業務邏輯**:
- ✅ 隱私保護：只公開有上架物品的用戶的主要地點
- ✅ 功能需求：買家需要知道賣家大概位置以計算距離
- ⚠️ 注意：不公開詳細地址，只用於距離計算

**當前文件中提到**:
```sql
-- backend/database/policies/20251031130000_open_locations_rls_for_demo.sql
-- 可能為了 demo 開放了所有 SELECT 權限，生產環境需要修改
```

#### ✅ INSERT 策略
**目的**: 只允許插入自己的地點

```sql
-- 策略名稱: locations_insert_policy
CREATE POLICY locations_insert_policy ON public.locations
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());
```

#### ✅ UPDATE 策略
**目的**: 只允許更新自己的地點（透過 RPC）

```sql
-- 策略名稱: locations_update_policy
CREATE POLICY locations_update_policy ON public.locations
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
```

**建議**: 建議透過 RPC 更新，並在 RPC 中驗證：
- 地點類型是否有效（'家', '公司', '其他'）
- 座標是否有效
- is_primary 邏輯（確保只有一個主要地點）

#### ✅ DELETE 策略
**目的**: 允許刪除自己的地點（但如果有物品使用該地點則由 FK 約束阻止）

```sql
-- 策略名稱: locations_delete_policy
CREATE POLICY locations_delete_policy ON public.locations
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());
```

**業務邏輯**:
- ✅ FK 約束：如果有物品使用該地點，DELETE 會失敗（ON DELETE RESTRICT）
- ✅ 用戶體驗：應在前端提示用戶先移除使用該地點的物品

---

## 4. 與 RPC 函數的整合

### 4.1 RPC 使用 SECURITY DEFINER

所有 RPC 函數應該使用 `SECURITY DEFINER`，這樣：
- RPC 以**定義者（超級用戶）權限**執行
- 可以繞過 RLS 策略
- 但必須在 RPC 內部實作**業務邏輯驗證**

### 4.2 驗證流程

```sql
-- RPC 內部應該始終驗證
DECLARE
  v_current_uid UUID := auth.uid();
BEGIN
  -- 1. 檢查用戶是否登入
  IF v_current_uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;
  
  -- 2. 檢查是否有權限操作此資源
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = v_current_uid
  ) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  
  -- 3. 執行業務邏輯...
END;
```

---

## 5. 檢查清單總結

### ✅ 必須檢查的項目

- [ ] **users 表**
  - [ ] SELECT: 所有已登入用戶可以查看
  - [ ] INSERT: 禁止直接插入（只允許觸發器）
  - [ ] UPDATE: 只能更新自己的記錄，且不能修改 avg_rating
  - [ ] DELETE: 禁止刪除

- [ ] **profiles 表**
  - [ ] SELECT: 只能查看自己的 profile
  - [ ] INSERT: 禁止直接插入（只允許觸發器）
  - [ ] UPDATE: **禁止直接更新 balance 和 carbon_saved_kg**
  - [ ] DELETE: 禁止刪除

- [ ] **locations 表**
  - [ ] SELECT: 可以查看自己的所有地點 + 其他用戶的主要地點（如有上架物品）
  - [ ] INSERT: 只能插入自己的地點
  - [ ] UPDATE: 只能更新自己的地點（透過 RPC）
  - [ ] DELETE: 只能刪除自己的地點（FK 約束保護）

### ⚠️ 高風險項目

1. **profiles.balance 直接更新** - 必須禁止或嚴格驗證
2. **locations SELECT 策略** - 確認 demo 策略已移除
3. **users.avg_rating 保護** - 防止手動修改

### 📝 建議行動

1. **立即執行**:
   - 移除 `backend/database/policies/20251031130000_open_locations_rls_for_demo.sql`（如果存在）
   - 禁止直接更新 `profiles.balance`

2. **短期內執行**:
   - 審查所有 RLS 策略是否與業務邏輯一致
   - 添加 RPC 內部驗證
   - 撰寫 RLS 策略測試

3. **長期優化**:
   - 建立 RLS 策略版本管理
   - 定期審查權限變更
   - 監控異常的資料庫操作

---

## 6. 測試腳本

### 6.1 驗證 RLS 策略

```sql
-- 測試 users 表
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims.sub TO '00000000-0000-0000-0000-000000000001';

-- 應該成功：查看其他用戶
SELECT nickname FROM public.users WHERE id != auth.uid() LIMIT 1;

-- 應該失敗：更新其他用戶
UPDATE public.users SET nickname = 'hacked' WHERE id != auth.uid();

-- 應該失敗：插入新用戶
INSERT INTO public.users (id, nickname) VALUES (gen_random_uuid(), 'test');

ROLLBACK;
```

### 6.2 驗證 RPC 權限

```javascript
// 前端測試
// 測試 1: 更新自己的 nickname（應該成功）
await supabase.rpc('update_my_profile', {
  p_user_data: { nickname: 'ValidNickname' },
  p_profile_data: {},
  p_locations_data: []
})

// 測試 2: 嘗試更新 balance（應該失敗）
await supabase.rpc('update_my_profile', {
  p_user_data: {},
  p_profile_data: { balance: 999999 },
  p_locations_data: []
})
// 預期: 拋出 'FORBIDDEN: Balance 不可直接更新' 錯誤
```

---

**建立日期**: 2025-11-05  
**最後更新**: 2025-11-05  
**負責人**: 後端團隊  
**狀態**: 待審查
