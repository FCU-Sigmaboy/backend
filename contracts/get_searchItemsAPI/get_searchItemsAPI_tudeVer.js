// ===================================================================
// ### 物品搜尋 API (Item Search API) - 可接受經緯度版
// -- 原版的 RPC 函式: search_items，仍然健在
// -- 這裡的 RPC 函式: search_items_tudeVer，基於原版，更改可接受前端輸入之經緯度，其他都一樣
// -- 這裡只是建立個檔案，以示提醒
// ===================================================================

/**
 * 統一的物品搜尋函式 (RPC)
 * @param {object} filters - 篩選條件
 * @param {number} [filters.latitude] - (可選) 使用者緯度
 * @param {number} [filters.longitude] - (可選) 使用者經度
 * @returns {Promise<Array>}
 */
export async function searchItems(filters = {}) {

    // 準備 RPC 參數
    const rpcParams = {
        p_user_latitude: filters.latitude || null,   // 新增
        p_user_longitude: filters.longitude || null, // 新增
        p_distance_range_km: filters.distance_range_km || null,
        p_main_category_id: filters.main_category_id || null,
        p_sub_category_id: filters.sub_category_id || null,
        p_keyword: filters.keyword || null,
        p_user_id: filters.user_id || null,
        p_page: filters.page || 1,
        p_size: filters.size || 20,
        p_sort_by: filters.sort_by || 'created_at',
        p_sort_direction: filters.sort_direction || 'desc'
    };

    const { data, error } = await supabase.rpc('search_items_tudeVer', rpcParams);

    if (error) {
        console.error('Supabase 搜尋物品失敗:', error);
        throw new Error(error.message);
    }

    return data;
}