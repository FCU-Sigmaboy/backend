import { supabase } from '@/lib/supabase';

/**
 * 【功能】使用 AI 分析物品圖片
 *
 * @param {string} imageUrl - 圖片的 URL（已上傳到 Supabase Storage）
 * @returns {Promise<object>} - AI 分析結果
 *
 * 回傳格式：
 * {
 *   title: string,           // 物品名稱
 *   description: string,     // 物品描述
 *   sub_category_id: number, // 子分類 ID
 *   carbon_value: number,    // 碳足跡值
 *   tags: string[],          // 標籤
 *   confidence: number,      // 信心度 (0-1)
 *   warnings: string[]       // 警告訊息
 * }
 */
export async function analyzeItemImage(imageUrl) {
  try {
    console.log('🤖 Calling AI to analyze image:', imageUrl);

    // 獲取當前 session token
    const { data: { session }, error: sessionError } = await supabase.auth.getSession();
    if (sessionError || !session) {
      throw new Error('使用者未登入');
    }

    // 呼叫 Edge Function
    const { data, error } = await supabase.functions.invoke('analyze-item-image', {
      body: {
        image_url: imageUrl
      }
    });

    if (error) {
      console.error('❌ AI 分析失敗:', error);
      throw new Error(error.message || 'AI 分析失敗');
    }

    if (!data || !data.success) {
      throw new Error(data?.error || 'AI 分析失敗：未知錯誤');
    }

    console.log('✅ AI 分析成功:', data.data);
    return data.data;

  } catch (error) {
    console.error('❌ AI 分析過程發生錯誤:', error);
    throw error;
  }
}
