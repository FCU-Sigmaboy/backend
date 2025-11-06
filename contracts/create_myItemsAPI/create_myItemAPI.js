import { supabase } from "src/supabaseClient";

// ===================================================================
// ### 圖片上傳 API (Image Upload APIs)
// ===================================================================

/**
 * 【功能】上傳單張圖片到 Supabase Storage
 * @param {File} file - 圖片檔案
 * @param {string} userId - 使用者 ID
 * @param {string} itemId - 物品 ID (可用臨時 ID)
 * @returns {Promise<string>} - 回傳圖片的公開 URL
 */
export async function uploadItemImage(file, userId, itemId) {
  const filename = `${Date.now()}-${file.name}`;
  const filePath = `${userId}/${itemId}/${filename}`;

  // 上傳檔案到 items bucket
  const { data, error } = await supabase.storage
    .from("items")
    .upload(filePath, file);

  if (error) {
    console.error("圖片上傳失敗:", error);
    throw new Error(error.message);
  }

  // 獲取公開 URL
  const {
    data: { publicUrl },
  } = supabase.storage.from("items").getPublicUrl(data.path);

  return publicUrl;
}

/**
 * 【功能】批次上傳多張圖片
 * @param {File[]} files - 圖片檔案陣列
 * @param {string} userId - 使用者 ID
 * @param {string} itemId - 物品 ID (可用臨時 ID)
 * @returns {Promise<string[]>} - 回傳所有圖片的 URL 陣列
 */
export async function uploadItemImages(files, userId, itemId) {
  if (!files || files.length === 0) {
    return [];
  }

  const uploadPromises = files.map((file) =>
    uploadItemImage(file, userId, itemId),
  );

  return Promise.all(uploadPromises);
}

// ===================================================================
// ### 刊登物品 API (Item APIs) - v2.0 (2025-11-07)
// ===================================================================
// ### 變更：
// ###   - 移除 user_location_id 參數
// ###   - 物品自動使用使用者的主要地點 (is_primary=true)
// ###   - 使用者必須先設定地點才能刊登物品
// ===================================================================

/**
 * 【功能】刊登一個新物品 (RPC v2.0)
 *
 * ⚠️ 重要變更 (2025-11-07):
 *   - 不再需要傳遞 user_location_id
 *   - 系統自動使用使用者的主要地點 (is_primary=true)
 *   - 使用者必須先在個人資料中設定地點
 *
 * @param {object} itemData - 來自前端表單的完整物件
 * - itemData.sub_category_id (Number) - 必填
 * - itemData.title (String) - 必填
 * - itemData.description (String) - 必填
 * - itemData.condition (String) - 必填 ('全新', '近全新', '良好', '普通', '需修理')
 * - itemData.price (Number) - 必填
 * - itemData.carbon_value (Number) - 可選
 * - itemData.image_urls (Array<String>) - 可選 (已上傳到 Storage 的 URL)
 * - itemData.tags (Array<String>) - 可選
 * @returns {Promise<object>} - 回傳新建的 item
 */
export async function createItem(itemData) {
  // 準備 RPC 參數 (不再包含 p_user_location_id)
  const rpcParams = {
    p_sub_category_id: itemData.sub_category_id,
    // ❌ p_user_location_id: itemData.user_location_id, // 已移除
    p_title: itemData.title,
    p_description: itemData.description,
    p_condition: itemData.condition,
    p_price: itemData.price,
    p_carbon_value: itemData.carbon_value,
    p_image_urls: itemData.image_urls,
    p_tags: itemData.tags,
  };

  const { data, error } = await supabase.rpc("create_item", rpcParams);

  if (error) {
    console.error("Supabase 刊登物品失敗:", error);
    // 可能的錯誤：
    // - "請先在個人資料中設定地點後再刊登物品"
    // - "子分類不存在"
    // - "參數驗證失敗"
    throw new Error(error.message);
  }

  return data;
}

/**
 * 【功能】完整刊登流程 (上傳圖片 + 建立物品)
 * @param {object} itemData - 物品資料
 * @param {File[]} imageFiles - 圖片檔案陣列
 * @returns {Promise<object>} - 回傳新建的 item
 */
export async function createItemWithImages(itemData, imageFiles = []) {
  try {
    // 1. 獲取當前使用者 ID
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      throw new Error("使用者未登入");
    }

    // 2. 檢查使用者是否已設定地點 (可選的前置檢查)
    const hasLocation = await checkUserHasLocation();
    if (!hasLocation) {
      throw new Error("請先在個人資料中設定地點後再刊登物品");
    }

    // 3. 產生臨時 ID 用於圖片路徑
    const tempItemId = `temp-${Date.now()}`;

    // 4. 上傳圖片 (若有提供)
    let imageUrls = [];
    if (imageFiles && imageFiles.length > 0) {
      imageUrls = await uploadItemImages(imageFiles, user.id, tempItemId);
    }

    // 5. 建立物品 (傳入圖片 URL，不需要 location_id)
    const result = await createItem({
      ...itemData,
      image_urls: imageUrls,
    });

    return result;
  } catch (error) {
    console.error("刊登物品流程失敗:", error);
    throw error;
  }
}

/**
 * 【輔助函數】檢查使用者是否已設定地點
 * @returns {Promise<boolean>} - 是否有地點
 */
export async function checkUserHasLocation() {
  try {
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return false;

    const { data, error } = await supabase
      .from("locations")
      .select("id")
      .eq("user_id", user.id)
      .limit(1);

    return !error && data && data.length > 0;
  } catch (error) {
    console.error("檢查使用者地點失敗:", error);
    return false;
  }
}

// ===================================================================
// ### 使用範例 (Updated v2.0)
// ===================================================================

/**
 * 範例 1：基本刊登流程
 *
 * import { createItemWithImages, checkUserHasLocation } from '@/api/items';
 *
 * async function handleSubmit(formData, imageFiles) {
 *   try {
 *     // 可選：前置檢查
 *     const hasLocation = await checkUserHasLocation();
 *     if (!hasLocation) {
 *       alert('請先在個人資料中設定地點');
 *       router.push('/profile/locations');
 *       return;
 *     }
 *
 *     // 刊登物品（不需要 location_id）
 *     const item = await createItemWithImages({
 *       sub_category_id: formData.category,
 *       title: formData.title,
 *       description: formData.description,
 *       condition: formData.condition,
 *       price: formData.price,
 *       carbon_value: formData.carbonValue,
 *       tags: formData.tags
 *     }, imageFiles);
 *
 *     console.log('刊登成功:', item);
 *     router.push(`/items/${item.id}`);
 *   } catch (error) {
 *     console.error('刊登失敗:', error.message);
 *     alert(error.message);
 *   }
 * }
 *
 *
 * 範例 2：簡化版（只有物品資料，無圖片）
 *
 * import { createItem } from '@/api/items';
 *
 * const item = await createItem({
 *   sub_category_id: 1,
 *   title: '二手書桌',
 *   description: '九成新，自取',
 *   condition: '良好',
 *   price: 500
 * });
 *
 *
 * 範例 3：Vue 3 組件範例
 *
 * <template>
 *   <form @submit.prevent="submitItem">
 *     <!-- 不再需要地點選擇器 -->
 *     <!-- ❌ 舊版：<select v-model="formData.location_id">...</select> -->
 *
 *     <!-- ✅ 新版：顯示提示訊息 -->
 *     <div v-if="!hasLocation" class="warning">
 *       ⚠️ 請先
 *       <router-link to="/profile/locations">設定您的地點</router-link>
 *       才能刊登物品
 *     </div>
 *
 *     <input v-model="formData.title" placeholder="標題" required />
 *     <textarea v-model="formData.description" placeholder="描述" required />
 *     <select v-model="formData.condition" required>
 *       <option value="全新">全新</option>
 *       <option value="近全新">近全新</option>
 *       <option value="良好">良好</option>
 *       <option value="普通">普通</option>
 *       <option value="需修理">需修理</option>
 *     </select>
 *     <input v-model.number="formData.price" type="number" placeholder="價格" required />
 *     <input type="file" multiple @change="handleImageSelect" accept="image/*" />
 *
 *     <button type="submit" :disabled="!hasLocation || isSubmitting">
 *       {{ isSubmitting ? '刊登中...' : '刊登物品' }}
 *     </button>
 *   </form>
 * </template>
 *
 * <script setup>
 * import { ref, onMounted } from 'vue';
 * import { createItemWithImages, checkUserHasLocation } from '@/api/items';
 *
 * const hasLocation = ref(false);
 * const isSubmitting = ref(false);
 * const formData = ref({
 *   sub_category_id: 1,
 *   title: '',
 *   description: '',
 *   condition: '良好',
 *   price: 0
 * });
 * const imageFiles = ref([]);
 *
 * onMounted(async () => {
 *   hasLocation.value = await checkUserHasLocation();
 * });
 *
 * function handleImageSelect(event) {
 *   imageFiles.value = Array.from(event.target.files);
 * }
 *
 * async function submitItem() {
 *   if (!hasLocation.value) {
 *     alert('請先設定您的地點');
 *     return;
 *   }
 *
 *   isSubmitting.value = true;
 *
 *   try {
 *     const item = await createItemWithImages(formData.value, imageFiles.value);
 *     alert('刊登成功！');
 *     router.push(`/items/${item.id}`);
 *   } catch (error) {
 *     alert(`刊登失敗: ${error.message}`);
 *   } finally {
 *     isSubmitting.value = false;
 *   }
 * }
 * </script>
 */

// ===================================================================
// ### Migration 變更說明 (2025-11-07)
// ===================================================================

/**
 * 【變更前 (v1.0)】
 * - 需要傳遞 user_location_id
 * - 每個物品綁定一個固定的 location_id
 * - 使用者需要在刊登時選擇地點
 *
 * const item = await createItem({
 *   sub_category_id: 1,
 *   user_location_id: 123,  // ❌ 需要手動選擇
 *   title: '物品標題',
 *   // ...
 * });
 *
 *
 * 【變更後 (v2.0)】
 * - 不需要傳遞 user_location_id
 * - 物品自動使用使用者的主要地點
 * - 使用者更新主要地點時，所有物品自動更新
 *
 * const item = await createItem({
 *   sub_category_id: 1,
 *   // user_location_id 已移除 ✅
 *   title: '物品標題',
 *   // ...
 * });
 *
 *
 * 【優勢】
 * 1. 簡化 UI/UX - 不需要地點選擇器
 * 2. 減少錯誤 - 不會選錯地點
 * 3. 自動更新 - 更改主要地點後，所有物品自動使用新地點
 * 4. 符合邏輯 - 物品屬於使用者，地點也屬於使用者
 *
 *
 * 【注意事項】
 * 1. 使用者必須先設定至少一個地點
 * 2. 建議設定主要地點 (is_primary=true)
 * 3. 如果沒有主要地點，系統會使用建立時間最早的地點
 * 4. 刊登前可使用 checkUserHasLocation() 檢查
 *
 *
 * 【錯誤處理】
 * - "請先在個人資料中設定地點後再刊登物品"
 *   → 使用者沒有任何地點，引導至設定頁面
 *
 * - "子分類不存在"
 *   → sub_category_id 無效
 *
 * - "參數驗證失敗"
 *   → 必填欄位缺失或格式錯誤
 */

// ===================================================================
// ### TypeScript 型別定義 (參考)
// ===================================================================

/**
 * interface CreateItemParams {
 *   sub_category_id: number;
 *   // user_location_id: number;  // ❌ v2.0 已移除
 *   title: string;
 *   description: string;
 *   condition: 'full_new' | 'like_new' | 'good' | 'fair' | 'poor';
 *   price: number;
 *   carbon_value?: number;
 *   image_urls?: string[];
 *   tags?: string[];
 * }
 *
 * interface CreateItemResponse {
 *   id: number;
 *   user_id: string;
 *   sub_category_id: number;
 *   title: string;
 *   description: string;
 *   condition: string;
 *   listing_status: boolean;
 *   price: number;
 *   carbon_value: number;
 *   image_urls: string[];
 *   tags: string[];
 *   created_at: string;
 *   updated_at: string;
 * }
 */
