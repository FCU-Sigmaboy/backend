import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 刊登物品 API (Item APIs)
// ===================================================================

/**
 * 【功能】刊登一個新物品 (RPC)
 * @param {object} itemData - 來自前端表單的完整物件
 * - itemData.sub_category_id (Number)
 * - itemData.user_location_id (Number)
 * - itemData.title (String)
 * - itemData.description (String)
 * - itemData.condition (String) - '全新', '近全新'...
 * - itemData.price (Number)
 * - itemData.carbon_value (Number)
 * - itemData.image_urls (Array<String>) - ['url1', 'url2'] (已上傳到 Storage)
 * - itemData.tags (Array<String>) - ['#Tag1', '#Tag2']
 * @returns {Promise<object>} - 回傳新建的 item (e.g., { id: 123, title: '...' })
 */
export async function createItem(itemData) {

    // 1. 準備 RPC 參數 (欄位名需與 SQL 函式參數完全對應)
    const rpcParams = {
        p_sub_category_id: itemData.sub_category_id,
        p_user_location_id: itemData.user_location_id,
        p_title: itemData.title,
        p_description: itemData.description,
        p_condition: itemData.condition,
        p_price: itemData.price,
        p_carbon_value: itemData.carbon_value,
        p_image_urls: itemData.image_urls,
        p_tags: itemData.tags
    };

    // 2. 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('create_item', rpcParams);

    // 3. 錯誤處理
    if (error) {
        console.error('Supabase 刊登物品失敗:', error);
        throw new Error(error.message); // 將錯誤往上拋，讓呼叫者知道
    }

    // 4. 回傳 RPC 回傳的 JSON 結果
    return data;
}

/* data 範例
{
  "id": 124,
  "title": "（全新）IKEA 檯燈"
}
 */