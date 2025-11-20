// ====================================================================
// AI 物品圖片分析 API
// ====================================================================
// 建立日期: 2025-11-02
// 作者: Claude Code
// 功能: 呼叫 Supabase Edge Function 分析物品圖片
// AI 模型: Google Gemini 2.5 Flash-Lite (低延遲、高性價比)
// 修改日期: 2025-11-20 (升級為 Gemini 2.5 Flash-Lite)
// ====================================================================

// 注意：前端使用時請改為您的 supabase 引入路徑
// 例如：import { supabase } from '@/lib/supabase'
import { supabase } from '../lib/supabase'

/**
 * 使用 AI 分析物品圖片，自動提取物品資訊
 * @param {string} imageUrl - Supabase Storage 中的圖片 URL
 * @returns {Promise<object>} - AI 分析結果
 *
 * 回傳格式：
 * {
 *   success: true,
 *   data: {
 *     title: "物品名稱",
 *     description: "詳細描述",
 *     sub_category_id: 11,
 *     carbon_value: 1.5,
 *     tags: ["標籤1", "標籤2"],
 *     confidence: 0.95,
 *     warnings: []
 *   },
 *   usage: { promptTokenCount: 100, candidatesTokenCount: 200, totalTokenCount: 300 },
 *   model: "gemini-2.5-flash-lite"
 * }
 */
export async function analyzeItemImage(imageUrl) {
  try {
    console.log('[analyzeItemImage] 開始分析圖片:', imageUrl)

    // 呼叫 Supabase Edge Function
    const { data, error } = await supabase.functions.invoke('analyze-item-image', {
      body: {
        image_url: imageUrl
      }
    })

    if (error) {
      console.error('[analyzeItemImage] Edge Function 錯誤:', error)
      throw new Error(error.message || 'AI 分析失敗')
    }

    // 檢查回傳狀態
    if (!data || !data.success) {
      console.error('[analyzeItemImage] 分析失敗:', data)
      throw new Error(data?.error || 'AI 分析失敗')
    }

    console.log('[analyzeItemImage] 分析成功:', data)
    return data

  } catch (error) {
    console.error('[analyzeItemImage] 呼叫失敗:', error)
    throw error
  }
}
