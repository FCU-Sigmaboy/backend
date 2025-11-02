import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 獲取購買確認畫面資料 API (Confirm API)
// ===================================================================

/**
 * 【功能】獲取購買/索取確認畫面所需的資料 (RPC)
 * @param {number} itemId - 您要確認的物品 ID
 * @returns {Promise<object | null>} - 回傳包含物品和使用者點數的物件, 或在錯誤時拋出
 */
export async function getItemForPurchaseConfirmation(itemId) {
    // 1. 檢查使用者是否登入 (RPC 也會檢查)
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('使用者未登入');

    // 2. 準備 RPC 參數
    const rpcParams = { p_item_id: itemId };

    // 3. 呼叫 RPC
    const { data, error } = await supabase
        .rpc('get_item_for_purchase_confirmation', rpcParams)
        .single(); // 預期只回傳一個物件

    // 4. 錯誤處理 (會捕捉 RPC 的 RAISE EXCEPTION)
    if (error) {
        console.error(`Supabase 獲取購買確認資料 #${itemId} 失敗:`, error);
        if (error.code === 'PGRST200') {
            // 雖然 RPC 應該會 RAISE EXCEPTION，但以防萬一
            throw new Error('找不到物品或物品無法索取');
        }
        throw new Error(error.message); // 把後端錯誤訊息顯示給使用者
    }

    return data;
}

/* 回傳 data 範例
{
  "item": {
    "id": 101,
    "title": "（全新）IKEA 檯燈",
    "cover_image_url": "https://.../item101_cover.jpg",
    "price": 500
  },
  "user": {
    "balance": 850
  }
}
 */


// ===================================================================
// ### 執行購買 API (Purchase API)
// ===================================================================

/**
 * 【新功能】執行購買/索取交易 (RPC)
 * @param {number} itemId - 您要購買/索取的物品 ID
 * @returns {Promise<object>} - 回傳交易結果 (e.g., { success: true, transaction_id: 123, new_balance: 450 })
 */
export async function executePurchase(itemId) {
    // 1. 檢查使用者是否登入 (RPC 也會檢查)
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('使用者未登入');

    // 2. 準備 RPC 參數
    const rpcParams = { p_item_id: itemId };

    // 3. 呼叫 RPC
    const { data, error } = await supabase.rpc('execute_purchase', rpcParams);

    // 4. 錯誤處理 (會捕捉 RPC 的 RAISE EXCEPTION)
    if (error) {
        console.error(`Supabase 執行購買 #${itemId} 失敗:`, error);
        throw new Error(error.message); // 把後端錯誤訊息顯示給使用者 (例如 "點數餘額不足")
    }

    // 5. 回傳 RPC 的成功結果
    return data;
}

/* 回傳 data 範例
{
  "success": true,
  "message": "索取成功",
  "transaction_id": 102,
  "new_balance": 350
}
 */