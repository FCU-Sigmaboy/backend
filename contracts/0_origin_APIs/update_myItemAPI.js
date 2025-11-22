import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 更新物品 API (Item APIs)
// ===================================================================

/**
 * 【功能】更新 "當前登入者" 的指定物品 (RPC)
 * @param {number} itemId - 要更新的物品 ID
 * @param {object} updateData - 包含 "有變動" 欄位的物件
 * e.g., { title: '新標題', price: 600, tags: ['#新標籤'], image_urls: ['new_url'] }
 * @returns {Promise<object>} - 回傳更新後的完整物品物件
 */
export async function updateMyItem(itemId, updateData) {
    // 1. 檢查使用者是否登入 (RPC 也會檢查)
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('使用者未登入，無法更新物品');

    // 2. 準備 RPC 參數
    const rpcParams = {
        p_item_id: itemId,
        p_update_data: updateData // 直接傳遞包含更新欄位的物件
    };

    // 3. 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('update_my_item', rpcParams);

    // 4. 錯誤處理
    if (error) {
        console.error(`Supabase 更新物品 #${itemId} 失敗:`, error);
        throw new Error(error.message); // 將錯誤往上拋
    }

    // 5. 回傳 RPC 回傳的 JSON 結果 (更新後的完整物品)
    return data;
}

/* 回傳 data 範例
{
  "id": 101,
  "user_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
  "sub_category_id": 2,
  "user_location_id": 12,
  "title": "（全新）IKEA 檯燈 - 已更新",
  "description": "買來後發現尺寸不合，便宜交換。",
  "condition": "全新",
  "listing_status": true,
  "price": 600,
  "carbon_value": "3.50",
  "image_urls": [
    "https://.../new_cover.jpg",
    "https://.../detail_A.jpg"
  ],
  "tags": [
    "#IKEA",
    "#檯燈",
    "#書房",
    "#新標籤"
  ],
  "created_at": "2025-10-18T10:30:00.123+00:00",
  "updated_at": "2025-10-19T07:12:45.678+00:00", // 更新時間會改變
  "deleted_at": null // 如果您沒有使用邏輯刪除，此欄位不存在
}
 */