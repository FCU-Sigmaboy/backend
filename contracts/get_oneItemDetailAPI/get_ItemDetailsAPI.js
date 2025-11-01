import { supabase } from "../src/supabaseClient.js";

// ===================================================================
// ### 單一物品詳情 API - v2.5（2025-11-01）
// ### 特性：
// ###   - 買家位置：自動使用資料庫位置（主要地點優先）
// ###   - 賣家位置：自動查詢主要地點（is_primary=true）
// ###   - 隱私保護：只有登入買家可查看距離資訊
// ###   - 支援未登入用戶瀏覽物品基本資訊
// ###   - PostGIS 精確距離計算
// ###   - 完整的錯誤處理和異常處理
// ###   - 使用 JSONB 優化效能
// ===================================================================

/**
 * 【主要函數】獲取單一物品的完整詳情（優化版）
 *
 * 買家位置策略：
 *   - 自動使用資料庫中的主要地點（is_primary=true）
 *   - 若無主要地點，則使用最早建立的地點
 *   - 若無任何地點，distance_km 為 null
 *
 * 賣家位置：自動查詢該賣家的主要地點（is_primary=true）
 *
 * 隱私保護：
 *   - 只有已登入用戶可以查看距離資訊
 *   - 未登入用戶僅能查看物品基本資訊、文字地址
 *   - 未登入用戶無法查看精確座標
 *   - 物品擁有者查看自己的物品時，不顯示距離資訊
 *
 * @param {number} itemId - 要查詢的物品 ID
 * @returns {Promise<object>} - 回傳統一格式的回應物件
 */
export async function getItemDetails(itemId) {
  try {
    // 1. 參數驗證
    if (!itemId || typeof itemId !== "number") {
      throw new Error("itemId 必須是有效的數字");
    }

    if (itemId <= 0) {
      throw new Error("itemId 必須是正整數");
    }

    console.log(`正在獲取物品 #${itemId} 的詳情...`);

    // 2. 檢查登入狀態
    const isLoggedIn = await checkUserAuthentication();

    if (!isLoggedIn) {
      console.log("提示：未登入用戶僅能查看物品基本資訊");
    }

    // 3. 呼叫優化版 RPC 函式（自動處理位置）
    const { data, error } = await supabase
      .rpc("get_item_details_with_location", {
        p_item_id: itemId,
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
          // 檢查是否需要解析（可能已經是物件）
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
 * 範例 1：基本使用（自動使用資料庫位置）
 *
 * const result = await getItemDetails(123);
 * if (result.success) {
 *   console.log("物品標題:", result.data.title);
 *   console.log("距離:", result.data.distance_km, "km");
 *   console.log("位置來源:", result.locationSource);
 * } else {
 *   console.error("錯誤:", result.message, "(code:", result.code, ")");
 * }
 *
 *
 * 範例 2：未登入用戶使用
 *
 * const result = await getItemDetails(123);
 * // 未登入時：result.hasDistance === false
 * // 未登入時：result.data.distance_km === null
 * // 未登入時：result.data.location.coordinates === null
 *
 *
 * 範例 3：檢查用戶是否為物品擁有者
 *
 * const result = await getItemDetails(123);
 * if (result.success && result.data.is_owner) {
 *   console.log("您是此物品的擁有者");
 *   // 物品擁有者查看自己的物品時，不會顯示距離資訊
 * }
 *
 *
 * 範例 4：錯誤處理
 *
 * const result = await getItemDetails(123);
 * if (!result.success) {
 *   switch (result.code) {
 *     case "INVALID_PARAMETER":
 *       console.error("參數錯誤:", result.message);
 *       break;
 *     case "ITEM_NOT_FOUND":
 *       console.error("物品不存在:", result.message);
 *       break;
 *     case "INTERNAL_ERROR":
 *       console.error("系統錯誤:", result.message);
 *       break;
 *     default:
 *       console.error("未知錯誤:", result.message);
 *   }
 * }
 */

// ===================================================================
// ### API 文檔
// ===================================================================

/**
 * 回傳格式:
 *
 * {
 *   success: boolean,           // 是否成功
 *   error: boolean,             // 是否有錯誤
 *   code?: string,              // 錯誤代碼（僅失敗時）
 *   message: string,            // 狀態訊息
 *   itemId: number,             // 物品 ID
 *   locationSource?: string,    // 位置來源（僅成功時）
 *   isAuthenticated?: boolean,  // 是否已登入（僅成功時）
 *   hasDistance?: boolean,      // 是否有距離資訊（僅成功時）
 *   isOwner?: boolean,          // 是否為物品擁有者（僅成功時）
 *   data: object | null         // 物品詳情資料或 null
 * }
 *
 *
 * locationSource 可能值：
 * - 'database_primary': 使用資料庫主要地點
 * - 'database_fallback': 使用資料庫次要地點
 * - 'none': 無位置資訊（未登入或未設定地點）
 *
 *
 * 錯誤代碼 (code) 可能值：
 * - 'INVALID_PARAMETER': 參數驗證失敗
 * - 'ITEM_NOT_FOUND': 物品不存在或已下架
 * - 'INTERNAL_ERROR': 內部系統錯誤
 *
 *
 * data 結構 (當 success === true):
 * {
 *   // 物品基本資訊（所有人可見）
 *   id: number,
 *   title: string,
 *   description: string,
 *   condition: string,              // '全新', '近全新', '良好', '普通', '需修理'
 *   listing_status: boolean,
 *   price: number,
 *   carbon_value: number,
 *   image_urls: string[],
 *   tags: string[],
 *   created_at: string,
 *   updated_at: string,
 *
 *   // 距離計算（🔒 僅已登入且非擁有者可見）
 *   distance_km: number | null,     // 買家與賣家主要地點的距離（公里）
 *
 *   // 互動狀態
 *   is_favorited: boolean,          // 當前用戶是否已收藏
 *   is_owner: boolean,              // 當前用戶是否為物品擁有者
 *
 *   // 賣家地點資訊
 *   location: {
 *     id: number,
 *     formatted_address: string,    // ✅ 所有人可見（文字地址）
 *     type: string,                 // '家', '公司', '其他'
 *     coordinates: {                // 🔒 僅已登入且非擁有者可見
 *       type: "Point",
 *       coordinates: [number, number]  // [經度, 緯度]
 *     } | null
 *   },
 *
 *   // 賣家資訊（所有人可見）
 *   user: {
 *     id: string,                   // UUID
 *     nickname: string,
 *     profile_picture_url: string | null,
 *     avg_rating: number
 *   },
 *
 *   // 分類資訊（所有人可見）
 *   category: {
 *     sub_category_id: number,
 *     sub_category_name: string,
 *     main_category_id: number,
 *     main_category_name: string,
 *     main_category_icon: string,
 *     main_category_color: string
 *   },
 *
 *   // 買家位置資訊（🔒 僅已登入且非擁有者可見）
 *   user_location: {
 *     has_location: boolean,        // 是否有位置資訊
 *     source: string,               // 'database_primary', 'database_fallback', 'none'
 *     coordinates: {                // 買家的座標（如果有）
 *       type: "Point",
 *       coordinates: [number, number]
 *     } | null,
 *     message: string               // 位置來源說明
 *   } | null
 * }
 */

// ===================================================================
// ### 前端使用範例（Vue 3）
// ===================================================================

/**
 * // 1. 基本使用
 * import { getItemDetails, checkUserAuthentication } from '@/api/itemDetails';
 *
 * const loadItemDetails = async (itemId) => {
 *   const result = await getItemDetails(itemId);
 *
 *   if (result.success) {
 *     console.log('物品標題:', result.data.title);
 *     console.log('價格:', result.data.price);
 *     console.log('地址:', result.data.location.formatted_address);
 *
 *     // 距離資訊處理
 *     if (result.hasDistance && result.data.distance_km !== null) {
 *       console.log('距離:', result.data.distance_km, '公里');
 *     } else if (!result.isAuthenticated) {
 *       console.log('提示：登入以查看距離資訊');
 *     } else if (result.isOwner) {
 *       console.log('這是您的物品');
 *     } else {
 *       console.log('提示：設定您的地點以查看距離');
 *     }
 *   } else {
 *     console.error('載入失敗:', result.message);
 *   }
 * };
 *
 *
 * // 2. 距離格式化輔助函數
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
 *   if (km === null) return '距離：未知（請設定您的地點）';
 *   if (km < 0.1) return `${(km * 1000).toFixed(0)} 公尺`;
 *   if (km < 1) return `${km.toFixed(2)} 公里`;
 *   return `${km.toFixed(1)} 公里`;
 * };
 *
 *
 * // 3. Vue 3 組件範例
 * <template>
 *   <div class="item-detail">
 *     <h1>{{ item.title }}</h1>
 *     <p>{{ item.description }}</p>
 *     <p>價格：${{ item.price }}</p>
 *     <p>地點：{{ item.location.formatted_address }}</p>
 *
 *     <!-- 距離顯示 -->
 *     <div v-if="!result.isOwner">
 *       <div v-if="result.isAuthenticated">
 *         <p v-if="item.distance_km !== null">
 *           距離：{{ formatDistance(item.distance_km) }}
 *         </p>
 *         <p v-else>
 *           <router-link to="/profile/locations">
 *             📍 設定您的地點以查看距離
 *           </router-link>
 *         </p>
 *       </div>
 *       <div v-else>
 *         <p class="login-prompt">
 *           🔒 <router-link to="/login">登入</router-link> 以查看與您的距離
 *         </p>
 *       </div>
 *     </div>
 *
 *     <!-- 地圖顯示 -->
 *     <div v-if="result.isAuthenticated && !result.isOwner && item.location.coordinates">
 *       <Map :coordinates="item.location.coordinates.coordinates" />
 *     </div>
 *   </div>
 * </template>
 */

// ===================================================================
// ### 隱私保護說明
// ===================================================================

/**
 * 【未登入用戶】
 * ✅ 可見：
 *   - 物品標題、描述、價格、圖片
 *   - 賣家暱稱、評分
 *   - 文字地址（formatted_address）
 *   - 分類資訊
 *
 * 🔒 隱藏：
 *   - distance_km: null
 *   - location.coordinates: null
 *   - user_location: null
 *
 * 💡 提示：
 *   - 顯示「登入以查看距離」
 *   - 顯示「登入以查看地圖」
 *
 *
 * 【已登入用戶（非擁有者）】
 * ✅ 可見：
 *   - 所有基本資訊
 *   - 精確距離（如已設定地點）
 *   - 精確座標（GeoJSON）
 *   - 完整地圖功能
 *
 *
 * 【已登入用戶（擁有者）】
 * ✅ 可見：
 *   - 所有基本資訊
 *
 * 🔒 隱藏：
 *   - distance_km: null（不顯示與自己的距離）
 *   - user_location: null
 *
 * 💡 特殊行為：
 *   - is_owner: true
 *   - 可以編輯和刪除物品
 *
 *
 * 【設計理念】
 * 1. 平衡開放性與隱私保護
 * 2. 鼓勵用戶註冊以獲得更好體驗
 * 3. 保護賣家位置隱私
 * 4. 符合資料保護最佳實踐
 * 5. 優化查詢效能（使用 CTE 和 JSONB）
 */

