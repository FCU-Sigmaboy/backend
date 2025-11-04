import { supabase } from 'src/supabaseClient';

// ===================================================================
// ### 圖片上傳 API (Image Upload APIs)
// ===================================================================

/**
 * 【功能】上傳單張圖片到 Supabase Storage
 * @param {File} file - 圖片檔案
 * @param {string} userId - 使用者 ID
 * @param {string} itemId - 物品 ID (可用臨時 ID)
 * @returns {Promise<string>} - 回傳圖片的公開 URL
 */
export async function uploadItemImage(file, userId, itemId) {
    const filename = `${Date.now()}-${file.name}`;
    const filePath = `${userId}/${itemId}/${filename}`;

    // 上傳檔案到 items bucket
    const { data, error } = await supabase.storage
        .from('items')
        .upload(filePath, file);

    if (error) {
        console.error('圖片上傳失敗:', error);
        throw new Error(error.message);
    }

    // 獲取公開 URL
    const { data: { publicUrl } } = supabase.storage
        .from('items')
        .getPublicUrl(data.path);

    return publicUrl;
}

/**
 * 【功能】批次上傳多張圖片
 * @param {File[]} files - 圖片檔案陣列
 * @param {string} userId - 使用者 ID
 * @param {string} itemId - 物品 ID (可用臨時 ID)
 * @returns {Promise<string[]>} - 回傳所有圖片的 URL 陣列
 */
export async function uploadItemImages(files, userId, itemId) {
    if (!files || files.length === 0) {
        return [];
    }

    const uploadPromises = files.map(file =>
        uploadItemImage(file, userId, itemId)
    );

    return Promise.all(uploadPromises);
}

// ===================================================================
// ### 刊登物品 API (Item APIs)
// ===================================================================

/**
 * 【功能】刊登一個新物品 (RPC)
 * @param {object} itemData - 來自前端表單的完整物件
 * - itemData.sub_category_id (Number) - 必填
 * - itemData.user_location_id (Number) - 必填
 * - itemData.title (String) - 必填
 * - itemData.description (String) - 必填
 * - itemData.condition (String) - 必填 ('全新', '近全新'...)
 * - itemData.price (Number) - 必填
 * - itemData.carbon_value (Number) - 可選
 * - itemData.image_urls (Array<String>) - 可選 (已上傳到 Storage 的 URL)
 * - itemData.tags (Array<String>) - 可選
 * @returns {Promise<object>} - 回傳新建的 item
 */
export async function createItem(itemData) {
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

    const { data, error } = await supabase.rpc('create_item', rpcParams);

    if (error) {
        console.error('Supabase 刊登物品失敗:', error);
        throw new Error(error.message);
    }

    return data;
}

/**
 * 【功能】完整刊登流程 (上傳圖片 + 建立物品)
 * @param {object} itemData - 物品資料
 * @param {File[]} imageFiles - 圖片檔案陣列
 * @returns {Promise<object>} - 回傳新建的 item
 */
export async function createItemWithImages(itemData, imageFiles = []) {
    try {
        // 1. 獲取當前使用者 ID
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) {
            throw new Error('使用者未登入');
        }

        // 2. 產生臨時 ID 用於圖片路徑
        const tempItemId = `temp-${Date.now()}`;

        // 3. 上傳圖片 (若有提供)
        let imageUrls = [];
        if (imageFiles && imageFiles.length > 0) {
            imageUrls = await uploadItemImages(imageFiles, user.id, tempItemId);
        }

        // 4. 建立物品 (傳入圖片 URL)
        const result = await createItem({
            ...itemData,
            image_urls: imageUrls
        });

        return result;
    } catch (error) {
        console.error('刊登物品流程失敗:', error);
        throw error;
    }
}
