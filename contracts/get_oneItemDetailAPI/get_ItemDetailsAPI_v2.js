import { supabase } from "../src/supabaseClient.js";

// ===================================================================
// ### 單一物品詳情 API - v5.2.0（2025-11-27）
// ###
// ### v5.2.0 (2025-11-27):
// ###   - 支援前端傳入當前位置（p_user_lat, p_user_lng）
// ###   - 支援次要地點切換（p_use_secondary_location）
// ###   - 更新 RPC 函數名稱為 get_item_details_with_location_v2
// ###   - 新增 current_position 位置來源類型
// ###   - 返回值改為 JSONB 格式
// ###   - 增強參數驗證（經緯度範圍檢查）
// ###   - 改進錯誤處理（新增 INVALID_COORDINATES 錯誤代碼）
// ###
// ### v4.1.1 (2025-11-18):
// ###   - 修復所有者無法查看已下架物品的缺陷
// ###
// ### v4.1.0:
// ###   - 改進上架狀態判邏輯與地點驗證
// ###   - 新增 LOCATION_NOT_FOUND 錯誤代碼處理
// ###
// ### v4.0.0:
// ###   - 支援 items.use_primary_location 欄位
// ###   - 物品可選擇使用主要或次要地點
// ===================================================================

/**
 * 【主要函數】獲取單一物品的完整詳情（v5.2.0）
 *
 * 買家位置優先級（新版）：
 *   1. 當前位置（前端傳入的 userLat, userLng）
 *   2. 次要地點（如 useSecondaryLocation = true）
 *   3. 主要地點（預設）
 *   4. 無位置
 *
 * @param {number} itemId - 要查詢的物品 ID
 * @param {object} options - 可選參數
 * @param {number} options.userLat - 用戶當前緯度（-90 ~ 90）
 * @param {number} options.userLng - 用戶當前經度（-180 ~ 180）
 * @param {boolean} options.useSecondaryLocation - 是否使用次要地點（預設 false）
 * @returns {Promise<object>} - 回傳統一格式的回應物件
 */
export async function getItemDetails(itemId, options = {}) {
  try {
    // 1. 參數驗證
    if (!itemId || typeof itemId !== "number") {
      throw new Error("itemId 必須是有效的數字");
    }

    if (itemId <= 0) {
      throw new Error("itemId 必須是正整數");
    }

    // 解構可選參數
    const {
      userLat = null,
      userLng = null,
      useSecondaryLocation = false,
    } = options;

    // 驗證經緯度參數
    if (
      (userLat !== null && userLng === null) ||
      (userLat === null && userLng !== null)
    ) {
      throw new Error("經緯度參數必須同時提供或同時為空");
    }

    if (userLat !== null) {
      if (userLat < -90 || userLat > 90) {
        throw new Error("緯度必須在 -90 到 90 之間");
      }
      if (userLng < -180 || userLng > 180) {
        throw new Error("經度必須在 -180 到 180 之間");
      }
    }

    console.log(`正在獲取物品 #${itemId} 的詳情...`);
    if (userLat !== null && userLng !== null) {
      console.log(`使用當前位置: (${userLat}, ${userLng})`);
    } else if (useSecondaryLocation) {
      console.log(`使用次要地點`);
    }

    // 2. 檢查登入狀態
    const isLoggedIn = await checkUserAuthentication();

    if (!isLoggedIn) {
      console.log("提示：未登入用戶僅能查看物品基本資訊");
    }

    // 3. 呼叫 v5.2.0 RPC 函式
    const { data, error } = await supabase
      .rpc("get_item_details_with_location_v2", {
        p_item_id: itemId,
        p_user_lat: userLat,
        p_user_lng: userLng,
        p_use_secondary_location: useSecondaryLocation,
      })
      .maybeSingle();

    // 4. 錯誤處理
    if (error) {
      console.error(`Supabase RPC 錯誤:`, error);
      throw new Error(`資料庫查詢失敗: ${error.message}`);
    }

    // 5. 檢查是否有錯誤回應（RPC 內部錯誤）
    if (data && data.error) {
      console.log(`物品查詢回應: ${data.message} (code: ${data.code})`);
      return {
        success: false,
        error: true,
        code: data.code,
        message: data.message,
        itemId: itemId,
        data: null,
      };
    }

    // 6. 資料後處理
    if (data) {
      // 確保陣列欄位的完整性
      data.image_urls = data.image_urls || [];
      data.tags = data.tags || [];

      // 處理地理座標（JSONB 格式）
      if (data.location && data.location.coordinates) {
        try {
          if (typeof data.location.coordinates === "string") {
            data.location.coordinates = JSON.parse(data.location.coordinates);
          }
        } catch (e) {
          console.warn("無法解析物品位置座標:", e);
          data.location.coordinates = null;
        }
      }

      // 處理用戶位置座標
      if (data.user_location && data.user_location.coordinates) {
        try {
          if (typeof data.user_location.coordinates === "string") {
            data.user_location.coordinates = JSON.parse(
              data.user_location.coordinates,
            );
          }
        } catch (e) {
          console.warn("無法解析用戶位置座標:", e);
          data.user_location.coordinates = null;
        }
      }

      // 記錄位置來源資訊
      const locationSource = data.user_location?.source || "none";
      const distanceInfo = data.distance_km
        ? `距離: ${data.distance_km} km`
        : "距離: 未提供";
      console.log(
        `成功獲取物品 #${itemId} 詳情，位置來源: ${locationSource}，${distanceInfo}`,
      );

      return {
        success: true,
        error: false,
        message: "物品詳情獲取成功",
        itemId: itemId,
        locationSource: locationSource,
        isAuthenticated: isLoggedIn,
        hasDistance: data.distance_km !== null,
        isOwner: data.is_owner || false,
        data: data,
      };
    }

    // 7. 沒有資料的情況
    return {
      success: false,
      error: true,
      code: "ITEM_NOT_FOUND",
      message: "物品不存在或已下架",
      itemId: itemId,
      data: null,
    };
  } catch (error) {
    console.error(`獲取物品詳情失敗 (itemId: ${itemId}):`, error.message);

    return {
      success: false,
      error: true,
      code: "INTERNAL_ERROR",
      message: error.message,
      itemId: itemId,
      data: null,
    };
  }
}

/**
 * 【輔助函數】檢查當前用戶是否已登入
 * @returns {Promise<boolean>} - 是否已登入
 */
export async function checkUserAuthentication() {
  try {
    const {
      data: { user },
      error,
    } = await supabase.auth.getUser();

    if (error) {
      console.warn("檢查登入狀態時發生錯誤:", error.message);
      return false;
    }

    return user !== null;
  } catch (error) {
    console.error("檢查登入狀態失敗:", error.message);
    return false;
  }
}

// ===================================================================
// ### 使用範例
// ===================================================================

/**
 * 範例 1：基本使用（使用資料庫主要地點）
 *
 * const result = await getItemDetails(123);
 * if (result.success) {
 *   console.log("物品標題:", result.data.title);
 *   console.log("距離:", result.data.distance_km, "km");
 *   console.log("位置來源:", result.locationSource); // 'database_primary'
 * }
 *
 *
 * 範例 2：使用當前位置（GPS）
 *
 * const result = await getItemDetails(123, {
 *   userLat: 25.0330,
 *   userLng: 121.5654
 * });
 * console.log("位置來源:", result.locationSource); // 'current_position'
 *
 *
 * 範例 3：使用次要地點
 *
 * const result = await getItemDetails(123, {
 *   useSecondaryLocation: true
 * });
 * console.log("位置來源:", result.locationSource); // 'database_secondary'
 *
 *
 * 範例 4：錯誤處理（含新增的 INVALID_COORDINATES）
 *
 * const result = await getItemDetails(123, {
 *   userLat: 100, // 無效緯度
 *   userLng: 121
 * });
 * if (!result.success && result.code === "INVALID_COORDINATES") {
 *   console.error("座標無效:", result.message);
 * }
 */

// ===================================================================
// ### API 文檔
// ===================================================================

/**
 * 回傳格式:
 *
 * {
 *   success: boolean,
 *   error: boolean,
 *   code?: string,
 *   message: string,
 *   itemId: number,
 *   locationSource?: string,
 *   isAuthenticated?: boolean,
 *   hasDistance?: boolean,
 *   isOwner?: boolean,
 *   data: object | null
 * }
 *
 *
 * locationSource 可能值（v5.2.0 更新）：
 * - 'current_position': 使用前端傳入的當前位置 ⭐ 新增
 * - 'database_primary': 使用資料庫主要地點
 * - 'database_secondary': 使用資料庫次要地點 ⭐ 更新（舊版為 database_fallback）
 * - 'none': 無位置資訊
 *
 *
 * 錯誤代碼 (code) 可能值：
 * - 'INVALID_PARAMETER': 參數驗證失敗
 * - 'INVALID_COORDINATES': 經緯度參數無效 ⭐ 新增
 * - 'ITEM_NOT_FOUND': 物品不存在或已下架
 * - 'LOCATION_NOT_FOUND': 賣家未設定指定的地點類型
 * - 'INTERNAL_ERROR': 內部系統錯誤
 *
 *
 * data 結構（與 v4.1.1 相同，僅 JSONB 格式優化）
 */

// ===================================================================
// ### 前端使用範例（Vue 3）
// ===================================================================

/**
 * // 1. 使用 GPS 當前位置
 * import { getItemDetails } from '@/api/itemDetails_v2';
 *
 * const loadItemWithCurrentLocation = async (itemId) => {
 *   if (navigator.geolocation) {
 *     navigator.geolocation.getCurrentPosition(async (position) => {
 *       const result = await getItemDetails(itemId, {
 *         userLat: position.coords.latitude,
 *         userLng: position.coords.longitude
 *       });
 *
 *       if (result.success) {
 *         console.log('使用您的當前位置，距離:', result.data.distance_km, 'km');
 *       }
 *     });
 *   }
 * };
 *
 *
 * // 2. 切換主要/次要地點
 * <template>
 *   <div>
 *     <button @click="toggleLocation">
 *       {{ useSecondary ? '使用主要地點' : '使用次要地點' }}
 *     </button>
 *     <p>距離: {{ formatDistance(result.data.distance_km) }}</p>
 *   </div>
 * </template>
 *
 * <script setup>
 * import { ref } from 'vue';
 *
 * const useSecondary = ref(false);
 * const result = ref(null);
 *
 * const toggleLocation = async () => {
 *   useSecondary.value = !useSecondary.value;
 *   result.value = await getItemDetails(itemId, {
 *     useSecondaryLocation: useSecondary.value
 *   });
 * };
 * </script>
 *
 *
 * // 3. 距離格式化（支援新的 locationSource）
 * const formatDistance = (result) => {
 *   if (!result.isAuthenticated) {
 *     return '🔒 登入以查看距離';
 *   }
 *
 *   if (result.isOwner) {
 *     return '這是您的物品';
 *   }
 *
 *   const km = result.data.distance_km;
 *   if (km === null) {
 *     const source = result.locationSource;
 *     if (source === 'none') {
 *       return '📍 請設定您的地點或開啟位置權限';
 *     }
 *     return '距離：未知';
 *   }
 *
 *   if (km < 0.1) return `${(km * 1000).toFixed(0)} 公尺`;
 *   if (km < 1) return `${km.toFixed(2)} 公里`;
 *   return `${km.toFixed(1)} 公里`;
 * };
 * </script>
 */
