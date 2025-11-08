import { supabase } from 'src/supabaseClient'; // 假設您已在 src/supabaseClient.js 初始化

// ===================================================================
// ### 獲取我的評價列表 API (Get My Reviews API)
// ===================================================================

/**
 * 【功能】獲取我收到的評價列表 (RPC)
 * @param {Object} params - 查詢參數
 * @param {number} [params.page=1] - 頁碼，預設為 1
 * @param {number} [params.pageSize=20] - 每頁數量，預設為 20
 * @param {string} [params.sortBy='created_at'] - 排序欄位 ('created_at', 'score')
 * @param {string} [params.sortDirection='desc'] - 排序方向 ('asc', 'desc')
 * @returns {Promise<Array>} - 回傳評價列表
 */
export async function getMyReviews(params = {}) {
    // 1. 設定預設參數
    const {
        page = 1,
        pageSize = 20,
        sortBy = 'created_at',
        sortDirection = 'desc'
    } = params;

    // 2. 準備 RPC 參數
    const rpcParams = {
        p_page: page,
        p_page_size: pageSize,
        p_sort_by: sortBy,
        p_sort_direction: sortDirection
    };

    // 3. 呼叫 RPC 函式
    const { data, error } = await supabase.rpc('get_my_reviews', rpcParams);

    // 4. 錯誤處理
    if (error) {
        console.error('獲取評價列表失敗:', error);
        throw new Error(error.message);
    }

    // 5. 回傳資料
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
