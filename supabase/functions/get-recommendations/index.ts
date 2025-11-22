/**
 * get-recommendations Edge Function
 * 
 * 獲取個性化推薦物品列表
 * 
 * @endpoint POST /functions/v1/get-recommendations
 * @auth Required
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface RecommendationRequest {
  user_id?: string
  limit?: number
  offset?: number
  exclude_item_ids?: number[]
  filter?: {
    main_category_id?: number
    sub_category_id?: number
    max_distance_km?: number
    min_price?: number
    max_price?: number
    condition?: string[]
  }
  algorithm?: 'hybrid' | 'content' | 'collaborative' | 'popular' | 'location' | 'following' | 'high_rated'
}

interface RecommendationResponse {
  success: boolean
  data?: {
    items: any[]
    total_count: number
    algorithm_used: string
    personalization_level: number
  }
  error?: string
}

serve(async (req) => {
  // Handle CORS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 初始化 Supabase 客戶端
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    
    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error('Missing Supabase configuration')
    }

    const supabaseClient = createClient(supabaseUrl, supabaseServiceKey)

    // 驗證用戶身份
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing authorization header' }),
        { 
          status: 401, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token)
    
    if (authError || !user) {
      return new Response(
        JSON.stringify({ success: false, error: 'Unauthorized' }),
        { 
          status: 401, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // 解析請求參數
    const requestData: RecommendationRequest = await req.json()
    const {
      user_id = user.id,
      limit = 20,
      offset = 0,
      filter = {},
      algorithm = 'hybrid'
    } = requestData

    // 驗證參數
    if (limit < 1 || limit > 100) {
      return new Response(
        JSON.stringify({ success: false, error: 'Limit must be between 1 and 100' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    if (offset < 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'Offset must be non-negative' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // 獲取用戶偏好以計算個性化程度
    let personalizationLevel = 25 // 預設值（未登入或新用戶）
    const { data: userPreferences } = await supabaseClient
      .from('user_preferences')
      .select('preference_score, total_interactions')
      .eq('user_id', user_id)
      .single()

    if (userPreferences) {
      personalizationLevel = Math.min(userPreferences.preference_score || 25, 100)
    }

    // 根據算法類型調用不同的推薦函數
    let recommendedItems = []
    
    if (algorithm === 'popular') {
      // 調用熱門物品函數
      const { data, error } = await supabaseClient.rpc('get_popular_items', {
        p_limit: limit,
        p_offset: offset,
        p_days: 7
      })
      
      if (error) throw error
      recommendedItems = data || []
    } else if (algorithm === 'following') {
      // 新增：調用追蹤賣家物品函數
      const { data, error } = await supabaseClient.rpc('get_following_items', {
        p_user_id: user_id,
        p_limit: limit,
        p_offset: offset
      })
      
      if (error) throw error
      recommendedItems = data || []
    } else if (algorithm === 'high_rated') {
      // 新增：調用高評價賣家物品函數
      const { data, error } = await supabaseClient.rpc('get_high_rated_seller_items', {
        p_min_rating: 4.0,
        p_min_reviews: 3,
        p_limit: limit,
        p_offset: offset
      })
      
      if (error) throw error
      recommendedItems = data || []
    } else {
      // Call personalized recommendation function (updated v2.0)
      const { data, error } = await supabaseClient.rpc('get_personalized_items', {
        p_user_id: user_id,
        p_limit: limit,
        p_offset: offset,
        p_filter: filter
      })
      
      if (error) throw error
      recommendedItems = data || []
    }

    // 記錄推薦日誌
    if (recommendedItems.length > 0) {
      const logs = recommendedItems.map((item: any, index: number) => ({
        user_id: user_id,
        item_id: item.item_id,
        recommendation_score: item.recommendation_score || item.popularity_score || 0,
        recommendation_reason: item.recommendation_reason || 'popular',
        position: offset + index,
        algorithm_version: 'v1.0'
      }))
      
      // 異步插入日誌，不阻塞回應
      supabaseClient
        .from('recommendation_logs')
        .insert(logs)
        .then(({ error }) => {
          if (error) console.error('Failed to log recommendations:', error)
        })
    }

    // 構建回應
    const response: RecommendationResponse = {
      success: true,
      data: {
        items: recommendedItems,
        total_count: recommendedItems.length,
        algorithm_used: algorithm,
        personalization_level: personalizationLevel
      }
    }

    return new Response(
      JSON.stringify(response),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  } catch (error) {
    console.error('Error in get-recommendations:', error)
    
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: error.message || 'Internal server error' 
      }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})
