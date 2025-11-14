import { supabase } from '@/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

/**
 * (API 1 - 賣家) 發起一個交易要約 (RPC)
 * @param {number} itemId - 您要出售的物品 ID
 * @param {string} receiverId - 您要出售給的買家 UUID
 * @returns {Promise<object>} - 回傳 { transaction_id, status, code }
 */
export async function initiateTransaction(itemId, receiverId) {
    const { data, error } = await supabase.rpc('initiate_transaction', {
        p_item_id: itemId,
        p_receiver_id: receiverId
    });
    if (error) throw new Error(`發起交易失敗: ${error.message}`);
    return data;
}

/**
 * (API 2 - 共用) 查詢 "我的" 交易列表 (依狀態和角色)
 * @param {'confirming' | 'pending'} status - 您要查詢的狀態
 * @param {'giver' | 'receiver'} role - 您在此交易中的角色
 * @returns {Promise<Array>} - 回傳交易明細列表
 */
export async function getMyTransactionsByStatus(status, role) {
    const { data, error } = await supabase.rpc('get_my_transactions_by_status', {
        p_status: status,
        p_role: role
    });
    if (error) throw new Error(`查詢交易列表失敗: ${error.message}`);
    return data;
}

/**
 * (API 3 - 賣家) 更新 Giver 備註
 * @param {number} transactionId - 交易 ID
 * @param {string} note - 備註內容
 * @returns {Promise<object>} - 回傳 { success: true, giver_note: '...' }
 */
export async function updateGiverNote(transactionId, note) {
    const { data, error } = await supabase.rpc('update_giver_note', {
        p_transaction_id: transactionId,
        p_note: note
    });
    if (error) throw new Error(`更新備註失敗: ${error.message}`);
    return data;
}

/**
 * (API 4 - 買家) 確認交易並更新 Receiver 備註
 * (這會將狀態從 'confirming' 推進到 'pending')
 * @param {number} transactionId - 交易 ID
 * @param {string} note - 備註內容
 * @returns {Promise<object>} - 回傳 { success: true, new_status: 'pending', ... }
 */
export async function buyerConfirmTransaction(transactionId, note) {
    const { data, error } = await supabase.rpc('buyer_confirm_transaction', {
        p_transaction_id: transactionId,
        p_note: note
    });
    if (error) throw new Error(`買家確認失敗: ${error.message}`);
    return data;
}

/**
 * (API 5 - 共用) 取消交易
 * (這會將狀態從 'confirming' 或 'pending' 推進到 'cancelled')
 * (並將物品重新上架)
 * @param {number} transactionId - 交易 ID
 * @returns {Promise<object>} - 回傳 { success: true, new_status: 'cancelled' }
 */
export async function cancelTransaction(transactionId) {
    const { data, error } = await supabase.rpc('cancel_transaction', {
        p_transaction_id: transactionId
    });
    if (error) throw new Error(`取消交易失敗: ${error.message}`);
    return data;
}