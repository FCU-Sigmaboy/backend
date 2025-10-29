/**
 * track-interaction Edge Function
 * 
 * 追蹤用戶與物品的互動行為
 * 
 * @endpoint POST /functions/v1/track-interaction
 * @auth Required
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface InteractionRequest {
  user_id?: string
  item_id: number
  interaction_type: 'view' | 'click' | 'favorite' | 'unfavorite' | 'share' | 'contact_seller'
  metadata?: {
    duration_seconds?: number
    source?: string
    position?: number
    [key: string]: any
  }
}

interface InteractionResponse {
  success: boolean
  message?: string
  should_update_preferences?: boolean
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
    const requestData: InteractionRequest = await req.json()
    const {
      user_id = user.id,
      item_id,
      interaction_type,
      metadata = {}
    } = requestData

    // 驗證必填參數
    if (!item_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing item_id' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    if (!interaction_type) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing interaction_type' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // 驗證互動類型
    const validTypes = ['view', 'click', 'favorite', 'unfavorite', 'share', 'contact_seller']
    if (!validTypes.includes(interaction_type)) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: `Invalid interaction_type. Must be one of: ${validTypes.join(', ')}` 
        }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // 調用 RPC 函數記錄互動
    const { data: trackResult, error: trackError } = await supabaseClient.rpc('track_interaction', {
      p_user_id: user_id,
      p_item_id: item_id,
      p_interaction_type: interaction_type,
      p_metadata: metadata
    })

    if (trackError) {
      throw trackError
    }

    // 判斷是否需要更新用戶偏好
    const importantInteractions = ['favorite', 'click', 'contact_seller']
    const shouldUpdatePreferences = importantInteractions.includes(interaction_type)

    // 如果是重要互動，異步觸發偏好更新（不阻塞回應）
    if (shouldUpdatePreferences) {
      // 檢查用戶的總互動數，決定是否立即更新偏好
      const { data: interactionCount } = await supabaseClient
        .from('user_interactions')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', user_id)

      // 如果互動數是 10 的倍數，立即更新偏好
      if (interactionCount && interactionCount.count && interactionCount.count % 10 === 0) {
        supabaseClient.rpc('calculate_user_preferences', {
          p_user_id: user_id
        }).then(({ error }) => {
          if (error) console.error('Failed to update preferences:', error)
        })
      }
    }

    // 更新推薦日誌（如果這次互動來自推薦）
    if (metadata.from_recommendation) {
      const updateData: any = {}
      
      if (interaction_type === 'click') {
        updateData.was_clicked = true
      } else if (interaction_type === 'favorite') {
        updateData.was_favorited = true
      }

      if (Object.keys(updateData).length > 0) {
        supabaseClient
          .from('recommendation_logs')
          .update(updateData)
          .eq('user_id', user_id)
          .eq('item_id', item_id)
          .order('created_at', { ascending: false })
          .limit(1)
          .then(({ error }) => {
            if (error) console.error('Failed to update recommendation log:', error)
          })
      }
    }

    // 構建回應
    const response: InteractionResponse = {
      success: true,
      message: 'Interaction tracked successfully',
      should_update_preferences: shouldUpdatePreferences
    }

    return new Response(
      JSON.stringify(response),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  } catch (error) {
    console.error('Error in track-interaction:', error)
    
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
