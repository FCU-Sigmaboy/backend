# CHANGELOG - create_myItemsAPI

## v2.0 (2025-11-07) - Migration: 移除 location_id 參數

### 🔄 重大變更 (Breaking Changes)

#### 移除的參數
- ❌ **`p_user_location_id`** - 不再需要傳遞此參數
- ❌ **`itemData.user_location_id`** - 從前端表單移除

#### 新增的功能
- ✅ 自動使用使用者的主要地點 (is_primary=true)
- ✅ 新增 `checkUserHasLocation()` 輔助函數
- ✅ 前置檢查：確保使用者已設定地點才能刊登

---

### 📊 資料庫架構變更

#### 變更前 (v1.0)
```
items.location_id → locations.id (直接關聯)
```

#### 變更後 (v2.0)
```
items.user_id → users.id → locations.user_id (is_primary=true)
```

---

### 💻 程式碼變更對照

#### Before (v1.0)

```javascript
// ❌ 舊版：需要傳遞 user_location_id
export async function createItem(itemData) {
  const rpcParams = {
    p_sub_category_id: itemData.sub_category_id,
    p_user_location_id: itemData.user_location_id,  // 必填
    p_title: itemData.title,
    p_description: itemData.description,
    p_condition: itemData.condition,
    p_price: itemData.price,
    p_carbon_value: itemData.carbon_value,
    p_image_urls: itemData.image_urls,
    p_tags: itemData.tags
  };

  const { data, error } = await supabase.rpc('create_item', rpcParams);
  // ...
}
```

#### After (v2.0)

```javascript
// ✅ 新版：不需要 user_location_id
export async function createItem(itemData) {
  const rpcParams = {
    p_sub_category_id: itemData.sub_category_id,
    // p_user_location_id 已移除
    p_title: itemData.title,
    p_description: itemData.description,
    p_condition: itemData.condition,
    p_price: itemData.price,
    p_carbon_value: itemData.carbon_value,
    p_image_urls: itemData.image_urls,
    p_tags: itemData.tags
  };

  const { data, error } = await supabase.rpc('create_item', rpcParams);
  // ...
}
```

---

### 🎯 前端 UI/UX 變更

#### 移除的元素
```html
<!-- ❌ v1.0: 需要地點選擇器 -->
<select v-model="formData.user_location_id" required>
  <option v-for="loc in userLocations" :key="loc.id" :value="loc.id">
    {{ loc.formatted_address }}
  </option>
</select>
```

#### 新增的元素
```html
<!-- ✅ v2.0: 自動使用主要地點，顯示提示 -->
<div v-if="!hasLocation" class="warning">
  ⚠️ 請先
  <router-link to="/profile/locations">設定您的地點</router-link>
  才能刊登物品
</div>

<div v-else class="info">
  📍 物品將使用您的主要地點
</div>
```

---

### 🔧 Migration 步驟

#### Phase 1-3: 資料庫更新
1. ✅ 執行 `20251107000001_update_items_location_relationship.sql`
2. ✅ 執行 `20251107000002_update_rpc_functions_use_user_location.sql`
3. ✅ 執行 `20251107000003_update_create_item_function.sql`

#### Phase 4: 前端更新（此版本）
4. ✅ 更新 `create_myItemAPI.js` 移除 `p_user_location_id`
5. ✅ 更新前端表單，移除地點選擇器
6. ✅ 新增前置檢查 `checkUserHasLocation()`
7. ✅ 更新 TypeScript 型別定義

#### Phase 5: 最終清理
8. ⏳ 待執行 `20251107000004_remove_location_id_column.sql`

---

### ⚠️ 錯誤處理變更

#### 新增的錯誤訊息
```javascript
// v2.0 新增的錯誤
if (error.message.includes('請先在個人資料中設定地點')) {
  // 引導使用者到設定頁面
  router.push('/profile/locations');
  alert('請先設定您的地點才能刊登物品');
}
```

#### 可能的錯誤情境
| 錯誤訊息 | 原因 | 解決方法 |
|---------|------|---------|
| "請先在個人資料中設定地點後再刊登物品" | 使用者沒有任何地點 | 引導至 `/profile/locations` |
| "子分類不存在" | `sub_category_id` 無效 | 檢查分類 ID |
| "參數驗證失敗" | 必填欄位缺失 | 檢查表單驗證 |

---

### 📝 使用範例更新

#### v1.0 使用方式（已廢棄）
```javascript
// ❌ 不再支援
const item = await createItem({
  sub_category_id: 1,
  user_location_id: 123,  // 已移除
  title: '物品標題',
  description: '描述',
  condition: '良好',
  price: 100
});
```

#### v2.0 使用方式（推薦）
```javascript
// ✅ 推薦方式
// 1. 先檢查使用者是否有地點
const hasLocation = await checkUserHasLocation();
if (!hasLocation) {
  alert('請先設定您的地點');
  router.push('/profile/locations');
  return;
}

// 2. 刊登物品（不需要 location_id）
const item = await createItem({
  sub_category_id: 1,
  title: '物品標題',
  description: '描述',
  condition: '良好',
  price: 100
});
```

---

### ✨ 新增的輔助函數

#### checkUserHasLocation()
```javascript
/**
 * 【新增】檢查使用者是否已設定地點
 * @returns {Promise<boolean>} - 是否有地點
 */
export async function checkUserHasLocation() {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return false;

    const { data, error } = await supabase
      .from('locations')
      .select('id')
      .eq('user_id', user.id)
      .limit(1);

    return !error && data && data.length > 0;
  } catch (error) {
    console.error('檢查使用者地點失敗:', error);
    return false;
  }
}
```

---

### 🎨 TypeScript 型別變更

#### Before (v1.0)
```typescript
interface CreateItemParams {
  sub_category_id: number;
  user_location_id: number;  // ❌ 已移除
  title: string;
  description: string;
  condition: ItemCondition;
  price: number;
  carbon_value?: number;
  image_urls?: string[];
  tags?: string[];
}
```

#### After (v2.0)
```typescript
interface CreateItemParams {
  sub_category_id: number;
  // user_location_id 已移除
  title: string;
  description: string;
  condition: ItemCondition;
  price: number;
  carbon_value?: number;
  image_urls?: string[];
  tags?: string[];
}
```

---

### 🚀 優勢與效益

#### 1. 簡化使用者體驗
- ❌ 舊版：使用者需要在刊登時選擇地點
- ✅ 新版：自動使用主要地點，無需選擇

#### 2. 減少錯誤
- ❌ 舊版：可能選錯地點
- ✅ 新版：系統自動處理，不會選錯

#### 3. 彈性更新
- ❌ 舊版：更改地點需要更新所有物品
- ✅ 新版：更改主要地點，所有物品自動更新

#### 4. 符合邏輯
- ✅ 物品屬於使用者
- ✅ 地點屬於使用者
- ✅ 物品透過使用者關聯地點

---

### 📋 升級檢查清單

#### 後端檢查
- [x] Migration 1-3 已執行
- [x] `create_item` RPC 已更新（無 `p_user_location_id`）
- [x] `user_has_location` 輔助函數已建立
- [x] 所有測試通過

#### 前端檢查
- [x] `create_myItemAPI.js` 已更新
- [ ] 移除所有地點選擇器 UI
- [ ] 更新 TypeScript 型別
- [ ] 新增「設定地點」提示
- [ ] 新增前置檢查邏輯
- [ ] 更新表單驗證
- [ ] 更新錯誤處理
- [ ] 所有測試通過

#### 文件檢查
- [x] CHANGELOG 已建立
- [x] API 文件已更新
- [x] 使用範例已更新
- [ ] 團隊已通知

---

### 🔗 相關文件

- [MIGRATION_GUIDE_20251107.md](../../supabase/migrations/MIGRATION_GUIDE_20251107.md)
- [QUICK_REFERENCE.md](../../supabase/migrations/QUICK_REFERENCE.md)
- Migration 檔案：
  - `20251107000001_update_items_location_relationship.sql`
  - `20251107000002_update_rpc_functions_use_user_location.sql`
  - `20251107000003_update_create_item_function.sql`
  - `20251107000004_remove_location_id_column.sql` (待執行)

---

### 📞 問題回報

如有任何問題，請聯繫開發團隊或在以下位置提交 issue：
- GitHub Issues
- Slack: #backend-team

---

**更新日期**: 2025-11-07  
**版本**: v2.0  
**狀態**: ✅ 已完成（等待前端整合）