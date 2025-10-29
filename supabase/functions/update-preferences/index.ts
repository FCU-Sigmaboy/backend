/**
 * update-preferences Edge Function
 * 
 * 更新用戶偏好設定檔
 * 
 * @endpoint POST /functions/v1/update-preferences
 * @auth Required
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface UpdatePreferencesRequest {
  user_id?: string
  force_recalculate?: boolean
  manual_preferences?: {
    excluded_seller_ids?: string[]
    preferred_distance_km?: number
    max_price_range?: number
    min_price_range?: number
  }
}

interface UpdatePreferencesResponse {
  success: boolean
  message?: string
  preferences?: any
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
    const requestData: UpdatePreferencesRequest = await req.json()
    const {
      user_id = user.id,
      force_recalculate = false,
      manual_preferences
    } = requestData

    // 確保用戶只能更新自己的偏好
    if (user_id !== user.id) {
      return new Response(
        JSON.stringify({ success: false, error: 'Cannot update preferences for other users' }),
        { 
          status: 403, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // 如果有手動偏好設定，先更新
    if (manual_preferences) {
      const { data: currentPrefs } = await supabaseClient
        .from('user_preferences')
        .select('*')
        .eq('user_id', user_id)
        .single()

      if (currentPrefs) {
        // 更新現有偏好
        const updateData: any = {}
        
        if (manual_preferences.excluded_seller_ids !== undefined) {
          updateData.excluded_seller_ids = manual_preferences.excluded_seller_ids
        }
        if (manual_preferences.preferred_distance_km !== undefined) {
          updateData.preferred_distance_km = manual_preferences.preferred_distance_km
        }
        if (manual_preferences.max_price_range !== undefined) {
          updateData.max_price_range = manual_preferences.max_price_range
        }
        if (manual_preferences.min_price_range !== undefined) {
          updateData.min_price_range = manual_preferences.min_price_range
        }

        const { error: updateError } = await supabaseClient
          .from('user_preferences')
          .update(updateData)
          .eq('user_id', user_id)

        if (updateError) {
          throw updateError
        }
      } else {
        // 創建新的偏好記錄
        const { error: insertError } = await supabaseClient
          .from('user_preferences')
          .insert({
            user_id,
            ...manual_preferences
          })

        if (insertError) {
          throw insertError
        }
      }
    }

    // 檢查是否需要重新計算偏好
    let shouldRecalculate = force_recalculate

    if (!shouldRecalculate) {
      // 檢查上次更新時間
      const { data: currentPrefs } = await supabaseClient
        .from('user_preferences')
        .select('updated_at, total_interactions')
        .eq('user_id', user_id)
        .single()

      if (currentPrefs) {
        const lastUpdate = new Date(currentPrefs.updated_at)
        const hoursSinceUpdate = (Date.now() - lastUpdate.getTime()) / (1000 * 60 * 60)
        
        // 如果超過 24 小時未更新，或者互動數顯著增加，則重新計算
        shouldRecalculate = hoursSinceUpdate > 24
      } else {
        // 如果沒有偏好記錄，需要計算
        shouldRecalculate = true
      }
    }

    // 重新計算偏好
    if (shouldRecalculate) {
      const { error: calcError } = await supabaseClient.rpc('calculate_user_preferences', {
        p_user_id: user_id
      })

      if (calcError) {
        throw calcError
      }
    }

    // 獲取更新後的偏好
    const { data: updatedPrefs, error: fetchError } = await supabaseClient
      .from('user_preferences')
      .select('*')
      .eq('user_id', user_id)
      .single()

    if (fetchError) {
      throw fetchError
    }

    // 構建回應
    const response: UpdatePreferencesResponse = {
      success: true,
      message: shouldRecalculate ? 'Preferences recalculated successfully' : 'Preferences updated successfully',
      preferences: updatedPrefs
    }

    return new Response(
      JSON.stringify(response),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  } catch (error) {
    console.error('Error in update-preferences:', error)
    
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
