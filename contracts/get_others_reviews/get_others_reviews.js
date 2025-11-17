import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 獲取其他用戶的評價列表 API (Get Others Reviews API)
// ===================================================================

/**
 * 【功能】獲取指定用戶收到的評價列表 (RPC)
 * @param {Object} params - 查詢參數
 * @param {string} params.userId - 目標用戶 ID（必填）
 * @param {number} [params.page=1] - 頁碼，預設為 1
 * @param {number} [params.pageSize=20] - 每頁數量，預設為 20
 * @param {string} [params.sortBy='created_at'] - 排序欄位 ('created_at', 'score')
 * @param {string} [params.sortDirection='desc'] - 排序方向 ('asc', 'desc')
 * @returns {Promise<Array>} - 回傳評價列表
 */
export async function getOthersReviews(params = {}) {
    // 1. 參數驗證
    const {
        userId,
        page = 1,
        pageSize = 20,
        sortBy = 'created_at',
        sortDirection = 'desc'
    } = params;

    // 2. 檢查必填參數
    if (!userId) {
        throw new Error('必須提供目標用戶 ID (userId)');
    }

    // 3. 準備 RPC 參數
    const rpcParams = {
        p_user_id: userId,
        p_page: page,
        p_page_size: pageSize,
        p_sort_by: sortBy,
        p_sort_direction: sortDirection
    };

    // 4. 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('get_others_reviews', rpcParams);

    // 5. 錯誤處理
    if (error) {
        console.error('獲取用戶評價列表失敗:', error);
        throw new Error(error.message);
    }

    // 6. 回傳資料
    return data || [];
}

/* 回傳 data 範例
[
  {
    "review_id": 1,
    "reviewer_id": "cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788",
    "reviewer_nickname": "Yo",
    "reviewer_avatar": "https://example.com/avatar.jpg",
    "score": 5,
    "comment": "很棒的交易體驗！",
    "created_at": "2024-10-15T10:20:00Z",
    "transaction_id": 1,
    "item_id": 5,
    "item_title": "咖啡機",
    "item_image": "https://example.com/item.jpg"
  }
]
*/
