import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 單一物品詳情 API (Item APIs) - 續
// ===================================================================

/**
 * 【功能】獲取單一物品的完整詳情 (RPC)
 * @param {number} itemId - 要查詢的物品 ID
 * @param {object} userLocation - 當前使用者的位置 { latitude: number, longitude: number }
 * @returns {Promise<object | null>} - 成功則回傳物品詳情物件，找不到則回傳 null
 */
export async function getItemDetails(itemId, userLocation) {

    // 1. 檢查必要參數
    if (!itemId) throw new Error("必須提供物品 ID。");
    if (!userLocation || userLocation.latitude == null || userLocation.longitude == null) {
        // 嘗試自動獲取，或拋出錯誤要求提供位置
        try {
            userLocation = await getCurrentLocation();
        } catch (err) {
            throw new Error(`獲取物品詳情時需要使用者位置以計算距離: ${err.message}`);
        }
    }

    // 2. 準備 RPC 參數
    const rpcParams = {
        p_item_id: itemId,
        p_user_latitude: userLocation.latitude,
        p_user_longitude: userLocation.longitude
    };

    // 3. 呼叫 RPC 函式
    const { data, error } = await supabase
        .rpc('get_item_details', rpcParams)
        .maybeSingle(); // <-- 使用 maybeSingle()，找不到物品時回傳 null 而非錯誤

    // 4. 錯誤處理 (maybeSingle 不會因為找不到而報錯)
    if (error) {
        console.error(`Supabase 獲取物品詳情 #${itemId} 失敗:`, error);
        throw new Error(error.message);
    }

    // 5. 回傳 RPC 回傳的 JSON 物件 (如果找不到物品，data 會是 null)
    return data;
}

/* data 範例
(如果 itemId 不存在或物品已下架，data 會是 null)

{
  "id": 101,
  "title": "（全新）IKEA 檯燈",
  "description": "買來後發現尺寸不合，便宜交換。",
  "condition": "全新",
  "listing_status": true,
  "price": 500,
  "carbon_value": "3.50",
  "image_urls": [
    "https://.../item101_cover.jpg",
    "https://.../item101_detail_A.jpg",
    "https://.../item101_detail_B.jpg"
  ],
  "tags": [
    "#IKEA",
    "#檯燈",
    "#居家"
  ],
  "created_at": "2025-10-18T10:30:00.123+00:00",
  "updated_at": "2025-10-18T10:30:00.123+00:00",
  "distance_km": "1.254",
  "favorites_count": 15,
  "location": {
    "id": 12,
    "formatted_address": "台中市西屯區福星路123號",
    "coordinates": {
      "type": "Point",
      "coordinates": [120.645, 24.179]
    }
  },
  "user": {
    "id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
    "nickname": "Joseph",
    "profile_picture_url": "https://.../joseph.jpg",
    "avg_rating": "4.80"
  },
  "category": {
    "sub_category_id": 5,
    "sub_category_name": "燈具",
    "main_category_id": 2,
    "main_category_name": "居家生活"
  }
}
 */