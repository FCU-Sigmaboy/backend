import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 交易與評價 API (Transaction & Rating APIs)
// ===================================================================

/**
 * 【功能】獲取某個使用者的所有交易紀錄 (包含評價)
 * @param {string} userId - 您要查看的使用者的 UUID
 * @returns {Promise<Array>} - 回傳一個 "巢狀" 的交易陣列
 */
export async function getUserTransactionHistory(userId) {

    const selectQuery = `
    id,
    item_id,
    giver_id,
    receiver_id,
    points_amount,
    carbon_amount_kg,
    transaction_status,
    completed_at,
    ratings (
      id,
      score,
      comment,
      created_at
    )
  `;

    const { data, error } = await supabase
        .from('transactions')
        .select(selectQuery)
        .or(`giver_id.eq.${userId},receiver_id.eq.${userId}`)
        .order('completed_at', { ascending: false });

    if (error) {
        console.error('Supabase 獲取交易歷史失敗:', error);
        throw new Error(error.message);
    }

    return data;
}

/* data 範例
[
  {
    "id": 101,
    "item_id": 205,
    "giver_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
    "receiver_id": "b2c3d4e5-xxxx-xxxx-xxxx-user002",
    "points_amount": 500,
    "carbon_amount_kg": "8.50",
    "transaction_status": "completed",
    "completed_at": "2025-10-18T10:30:00+00:00",
    "ratings": {
      "id": 55,
      "score": 5,
      "comment": "非常棒的賣家，寄貨迅速！",
      "created_at": "2025-10-18T11:00:00+00:00"
    }
  },
  {
    "id": 98,
    "item_id": 133,
    "giver_id": "c3d4e5f6-xxxx-xxxx-xxxx-user003",
    "receiver_id": "a1b2c3d4-e5f6-4a5b-8c9d-123456789abc",
    "points_amount": 0,
    "carbon_amount_kg": "3.10",
    "transaction_status": "completed",
    "completed_at": "2025-10-17T15:00:00+00:00",
    "ratings": null
  }
]
 */
