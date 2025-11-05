export interface SaveLocationRequest {
  latitude: number
  longitude: number
  type?: '家' | '公司' | '其他'
  is_primary?: boolean
}

export interface SaveLocationResponse {
  success: boolean
  data?: {
    id: number
    latitude: number
    longitude: number
    district: string  // 行政區（例如：台中市北屯區）
    type: string
    is_primary: boolean
  }
  message?: string
  error?: string
  details?: string
  valid_types?: string[]
  received?: string
}
