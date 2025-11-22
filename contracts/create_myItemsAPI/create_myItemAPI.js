// 版本更新註釋：2025-11-10 修復 Storage 圖片無快取標頭，加入 cacheControl 減少 Egress 流量

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

  // 上傳檔案到 items bucket，設定快取標頭
  const { data, error } = await supabase.storage
    .from("items")
    .upload(filePath, file, {
      cacheControl: "public, max-age=31536000, immutable",
      upsert: false,
    });

  if (error) {
    console.error("圖片上傳失敗:", error);
    throw new Error(error.message);
  }

  // 獲取公開 URL (包含快取標頭)
  const {
    data: { publicUrl },
  } = supabase.storage.from("items").getPublicUrl(data.path, {
    download: false,
  });

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
// ### 刊登物品 API (Item APIs) - v3.0 (2025-11-08)
// ===================================================================
// ### 變更：
// ###   - 新增 use_primary_location 參數（預設 true）
// ###   - true = 使用主要地點 (is_primary=true)
// ###   - false = 使用次要地點 (is_primary=false)
// ###   - 使用者限制：最多擁有 1 個主要地點 + 1 個次要地點
// ###   - 透過 boolean 欄位 JOIN locations 表，避免儲存 location_id
// ===================================================================

/**
 * 【功能】刊登一個新物品 (RPC v3.0)
 *
 * ⚠️ 重要變更 (2025-11-08):
 *   - 新增 use_primary_location 參數（可選，預設 true）
 *   - true: 使用主要地點 (is_primary=true)
 *   - false: 使用次要地點 (is_primary=false)
 *   - 系統會驗證使用者是否有對應的地點設定
 *
 * @param {object} itemData - 來自前端表單的完整物件
 * - itemData.sub_category_id (Number) - 必填
 * - itemData.title (String) - 必填
 * - itemData.description (String) - 必填
 * - itemData.condition (String) - 必填 ('全新', '近全新', '良好', '普通', '需修理')
 * - itemData.price (Number) - 必填
 * - itemData.use_primary_location (Boolean) - 可選，預設 true (主要地點)
 * - itemData.carbon_value (Number) - 可選
 * - itemData.image_urls (Array<String>) - 可選 (已上傳到 Storage 的 URL)
 * - itemData.tags (Array<String>) - 可選
 * @returns {Promise<object>} - 回傳新建的 item 及地點資訊
 */
export async function createItem(itemData) {
  // 準備 RPC 參數
  const rpcParams = {
    p_sub_category_id: itemData.sub_category_id,
    p_title: itemData.title,
    p_description: itemData.description,
    p_condition: itemData.condition,
    p_price: itemData.price,
    p_use_primary_location:
      itemData.use_primary_location !== undefined
        ? itemData.use_primary_location
        : true, // 預設使用主要地點
    p_carbon_value: itemData.carbon_value,
    p_image_urls: itemData.image_urls,
    p_tags: itemData.tags,
  };

  const { data, error } = await supabase.rpc("create_item", rpcParams);

  if (error) {
    console.error("Supabase 刊登物品失敗:", error);
    // 可能的錯誤：
    // - "請先在個人資料中設定主要地點後再刊登物品"
    // - "請先在個人資料中設定次要地點後再刊登物品"
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
 * @returns {Promise<object>} - 回傳新建的 item 及地點資訊
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

    // 2. 檢查使用者是否已設定對應的地點
    const usePrimary =
      itemData.use_primary_location !== undefined
        ? itemData.use_primary_location
        : true;
    const hasLocation = await checkUserHasLocation(usePrimary);
    if (!hasLocation) {
      const locationType = usePrimary ? "主要地點" : "次要地點";
      throw new Error(`請先在個人資料中設定${locationType}後再刊登物品`);
    }

    // 3. 產生臨時 ID 用於圖片路徑
    const tempItemId = `temp-${Date.now()}`;

    // 4. 上傳圖片 (若有提供)
    let imageUrls = [];
    if (imageFiles && imageFiles.length > 0) {
      imageUrls = await uploadItemImages(imageFiles, user.id, tempItemId);
    }

    // 5. 建立物品 (傳入圖片 URL 和地點選擇)
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
 * 【輔助函數】檢查使用者是否已設定指定類型的地點
 * @param {boolean} isPrimary - true=檢查主要地點, false=檢查次要地點
 * @returns {Promise<boolean>} - 是否有該類型的地點
 */
export async function checkUserHasLocation(isPrimary = true) {
  try {
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return false;

    const { data, error } = await supabase
      .from("locations")
      .select("id")
      .eq("user_id", user.id)
      .eq("is_primary", isPrimary)
      .limit(1);

    return !error && data && data.length > 0;
  } catch (error) {
    console.error("檢查使用者地點失敗:", error);
    return false;
  }
}

// ===================================================================
// ### 使用範例 (v3.0)
// ===================================================================

/**
 * 範例 1：基本刊登流程（使用主要地點）
 *
 * import { createItemWithImages, checkUserHasLocation } from '@/api/items';
 *
 * async function handleSubmit(formData, imageFiles) {
 *   try {
 *     // 可選：前置檢查主要地點
 *     const hasPrimaryLocation = await checkUserHasLocation(true);
 *     if (!hasPrimaryLocation) {
 *       alert('請先在個人資料中設定主要地點');
 *       router.push('/profile/locations');
 *       return;
 *     }
 *
 *     // 刊登物品（預設使用主要地點）
 *     const result = await createItemWithImages({
 *       sub_category_id: formData.category,
 *       title: formData.title,
 *       description: formData.description,
 *       condition: formData.condition,
 *       price: formData.price,
 *       // use_primary_location: true,  // 可省略，預設為 true
 *       carbon_value: formData.carbonValue,
 *       tags: formData.tags
 *     }, imageFiles);
 *
 *     console.log('刊登成功:', result.item);
 *     console.log('使用地點:', result.location);
 *     router.push(`/items/${result.item.id}`);
 *   } catch (error) {
 *     console.error('刊登失敗:', error.message);
 *     alert(error.message);
 *   }
 * }
 *
 *
 * 範例 2：使用次要地點刊登
 *
 * import { createItem } from '@/api/items';
 *
 * const result = await createItem({
 *   sub_category_id: 1,
 *   title: '二手書桌',
 *   description: '九成新，自取',
 *   condition: '良好',
 *   price: 500,
 *   use_primary_location: false  // 使用次要地點
 * });
 *
 * console.log('物品 ID:', result.item.id);
 * console.log('銷售地點:', result.location.formatted_address);
 *
 *
 * 範例 3：查詢物品及地點資訊（使用 View）
 *
 * // 直接使用 Supabase 客戶端查詢 View
 * const { data: item } = await supabase
 *   .from('items_with_location')
 *   .select('*')
 *   .eq('id', itemId)
 *   .single();
 *
 * console.log('物品標題:', item.title);
 * console.log('銷售地點:', item.location_address);
 * console.log('使用主要地點:', item.use_primary_location);
 * console.log('地點類型:', item.location_type);
 *
 *
 * 範例 4：查詢使用者的所有地點
 *
 * // 前端直接查詢 locations 表
 * const { data: { user } } = await supabase.auth.getUser();
 *
 * const { data: locations } = await supabase
 *   .from('locations')
 *   .select('*')
 *   .eq('user_id', user.id)
 *   .order('is_primary', { ascending: false });  // 主要地點排在前面
 *
 * const primaryLocation = locations.find(loc => loc.is_primary === true);
 * const secondaryLocation = locations.find(loc => loc.is_primary === false);
 *
 *
 * 範例 5：更新物品地點（使用 Supabase 直接更新）
 *
 * // 將物品切換至次要地點
 * const { data, error } = await supabase
 *   .from('items')
 *   .update({ use_primary_location: false })
 *   .eq('id', itemId)
 *   .select();
 *
 * if (error) {
 *   console.error('更新失敗:', error);
 * } else {
 *   console.log('已切換至次要地點');
 * }
 *
 *
 * 範例 6：Vue 3 組件範例
 *
 * <template>
 *   <form @submit.prevent="submitItem">
 *     <h2>刊登物品</h2>
 *
 *     <!-- 基本資訊 -->
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
 *
 *     <!-- 地點選擇 -->
 *     <div class="location-section" v-if="userLocations.length > 0">
 *       <h3>📍 銷售地點</h3>
 *       <label v-if="primaryLocation">
 *         <input
 *           type="radio"
 *           v-model="formData.use_primary_location"
 *           :value="true"
 *         />
 *         主要地點
 *         <span class="location-preview">
 *           ({{ primaryLocation.formatted_address }})
 *         </span>
 *       </label>
 *       <label v-if="secondaryLocation">
 *         <input
 *           type="radio"
 *           v-model="formData.use_primary_location"
 *           :value="false"
 *         />
 *         次要地點
 *         <span class="location-preview">
 *           ({{ secondaryLocation.formatted_address }})
 *         </span>
 *       </label>
 *       <p v-if="!secondaryLocation" class="hint">
 *         💡 您可以在個人資料中新增次要地點
 *       </p>
 *     </div>
 *
 *     <!-- 圖片上傳 -->
 *     <input type="file" multiple @change="handleImageSelect" accept="image/*" />
 *
 *     <button type="submit" :disabled="!canSubmit || isSubmitting">
 *       {{ isSubmitting ? '刊登中...' : '刊登物品' }}
 *     </button>
 *   </form>
 * </template>
 *
 * <script setup>
 * import { ref, computed, onMounted } from 'vue';
 * import { supabase } from '@/supabaseClient';
 * import { createItemWithImages, checkUserHasLocation } from '@/api/items';
 *
 * const isSubmitting = ref(false);
 * const userLocations = ref([]);
 * const imageFiles = ref([]);
 *
 * const formData = ref({
 *   sub_category_id: 1,
 *   title: '',
 *   description: '',
 *   condition: '良好',
 *   price: 0,
 *   use_primary_location: true  // 預設使用主要地點
 * });
 *
 * // 計算主要地點
 * const primaryLocation = computed(() => {
 *   return userLocations.value.find(loc => loc.is_primary === true);
 * });
 *
 * // 計算次要地點
 * const secondaryLocation = computed(() => {
 *   return userLocations.value.find(loc => loc.is_primary === false);
 * });
 *
 * // 是否可以提交
 * const canSubmit = computed(() => {
 *   if (formData.value.use_primary_location) {
 *     return !!primaryLocation.value;
 *   } else {
 *     return !!secondaryLocation.value;
 *   }
 * });
 *
 * onMounted(async () => {
 *   try {
 *     // 獲取當前使用者
 *     const { data: { user } } = await supabase.auth.getUser();
 *     if (!user) return;
 *
 *     // 查詢使用者的所有地點
 *     const { data: locations } = await supabase
 *       .from('locations')
 *       .select('*')
 *       .eq('user_id', user.id)
 *       .order('is_primary', { ascending: false });
 *
 *     userLocations.value = locations || [];
 *
 *     // 如果沒有主要地點，提示使用者設定
 *     if (!primaryLocation.value) {
 *       alert('請先設定您的主要地點');
 *       router.push('/profile/locations');
 *     }
 *   } catch (error) {
 *     console.error('獲取地點失敗:', error);
 *   }
 * });
 *
 * function handleImageSelect(event) {
 *   imageFiles.value = Array.from(event.target.files);
 * }
 *
 * async function submitItem() {
 *   if (!canSubmit.value) {
 *     const locationType = formData.value.use_primary_location ? '主要' : '次要';
 *     alert(`請先設定您的${locationType}地點`);
 *     return;
 *   }
 *
 *   isSubmitting.value = true;
 *
 *   try {
 *     const result = await createItemWithImages(formData.value, imageFiles.value);
 *     alert('刊登成功！');
 *     console.log('物品資訊:', result.item);
 *     console.log('使用地點:', result.location);
 *     router.push(`/items/${result.item.id}`);
 *   } catch (error) {
 *     alert(`刊登失敗: ${error.message}`);
 *   } finally {
 *     isSubmitting.value = false;
 *   }
 * }
 * </script>
 *
 * <style scoped>
 * .location-section {
 *   margin: 1rem 0;
 *   padding: 1rem;
 *   border: 1px solid #ddd;
 *   border-radius: 8px;
 * }
 *
 * .location-preview {
 *   color: #666;
 *   font-size: 0.9em;
 *   margin-left: 0.5rem;
 * }
 *
 * .hint {
 *   color: #888;
 *   font-size: 0.85em;
 *   margin-top: 0.5rem;
 * }
 * </style>
 */

// ===================================================================
// ### TypeScript 型別定義 (參考)
// ===================================================================

/**
 * interface CreateItemParams {
 *   sub_category_id: number;
 *   title: string;
 *   description: string;
 *   condition: '全新' | '近全新' | '良好' | '普通' | '需修理';
 *   price: number;
 *   use_primary_location?: boolean;  // v3.0 新增，預設 true
 *   carbon_value?: number;
 *   image_urls?: string[];
 *   tags?: string[];
 * }
 *
 * interface CreateItemResponse {
 *   success: boolean;
 *   item: {
 *     id: number;
 *     title: string;
 *     price: number;
 *     use_primary_location: boolean;
 *     created_at: string;
 *   };
 *   location: {
 *     id: number;
 *     formatted_address: string;
 *     type: string;
 *     is_primary: boolean;
 *   };
 *   message: string;
 * }
 *
 * interface Location {
 *   id: number;
 *   user_id: string;
 *   coordinates: any;
 *   type: '家' | '公司' | '其他';
 *   is_primary: boolean;
 *   formatted_address: string;
 *   created_at: string;
 *   updated_at: string;
 * }
 *
 * interface ItemWithLocation {
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
 *   use_primary_location: boolean;
 *   created_at: string;
 *   updated_at: string;
 *   location_id: number;
 *   location_coordinates: any;
 *   location_type: string;
 *   location_address: string;
 *   location_is_primary: boolean;
 * }
 */
