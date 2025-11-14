


/**
 * 【新功能 - 安全版】切換物品上架/下架狀態
 * 這是您前端元件 "唯一" 應該呼叫的函式。
 * @param {number} itemId - 物品 ID
 * @param {boolean} newStatus - 您「想要」的新狀態 (true = 上架, false = 下架)
 * @returns {Promise<object>} - 回傳 'relistMyItem' 或 'unlistItem' 的成功結果
 */
export async function toggleItemStatus(itemId, newStatus) {

    if (newStatus === true) {
        //
        // 意圖：重新上架 (False -> True)
        //
        // 呼叫 `relistMyItem` RPC，
        // 它會在後端檢查是否 *沒有* 'completed', 'pending' 等交易
        //
        console.log(`正在嘗試重新上架物品 #${itemId}...`);
        return await relistMyItem(itemId);

    } else {
        //
        // 意圖：下架 (True -> False)
        //
        // 呼叫 `unlistItem` RPC，
        // 它會在後端檢查是否 *沒有* 'pending' 或 'confirming' 交易
        //
        console.log(`正在嘗試下架物品 #${itemId}...`);
        return await unlistItem(itemId);
    }
}

/**
 * 【新功能】(API 7 - 賣家) 重新上架物品 (RPC)
 * @param {number} itemId - 您要重新上架的物品 ID
 * @returns {Promise<object>} - 回傳操作結果
 */
export async function relistMyItem(itemId) {
    // 1. 檢查使用者是否登入 (RPC 也會檢查)
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('使用者未登入');

    // 2. 準備 RPC 參數
    const rpcParams = {
        p_item_id: itemId
    };

    // 3. 呼叫 RPC
    const { data, error } = await supabase.rpc('relist_item', rpcParams);

    // 4. 錯誤處理 (會捕捉 RPC 的 RAISE EXCEPTION)
    if (error) {
        console.error(`Supabase 重新上架 #${itemId} 失敗:`, error);
        throw new Error(error.message); // (例如 "此物品已綁定於一個進行中或已完成的交易...")
    }
    return data;
}
/* 回傳 data 範例
{
  "success": true,
  "message": "物品已重新上架",
  "item_id": 133,
  "new_listing_status": true
}
// 範例：執行失敗 (拋出錯誤)
// Error: 物品不存在
// Error: 您不是此物品的擁有者
// Error: 物品已經是上架狀態
// Error: 此物品已綁定於一個進行中或已完成的交易，無法重新上架
 */


/**
 * 【新功能】(API 8 - 賣家) 安全下架物品 (RPC)
 * @param {number} itemId - 您要下架的物品 ID
 * @returns {Promise<object>} - 回傳操作結果
 */
export async function unlistItem(itemId) {
    // 1. 檢查使用者是否登入 (RPC 也會檢查)
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('使用者未登入');

    // 2. 準備 RPC 參數
    const rpcParams = {
        p_item_id: itemId
    };

    // 3. 呼叫 RPC
    const { data, error } = await supabase.rpc('unlist_item', rpcParams);

    // 4. 錯誤處理 (會捕捉 RPC 的 RAISE EXCEPTION)
    if (error) {
        console.error(`Supabase 下架 #${itemId} 失敗:`, error);
        throw new Error(error.message); // (例如 "物品正在交易中，無法下架。")
    }
    return data;
}
/* 回傳 data 範例
{
  "success": true,
  "message": "物品已下架",
  "item_id": 101,
  "new_listing_status": false
}
// 範例：執行失敗 (拋出錯誤)
// Error: 物品不存在
// Error: 您不是此物品的擁有者
// Error: 物品已經是下架狀態
// Error: 物品正在交易中，無法下架。請先取消該筆交易。
 */